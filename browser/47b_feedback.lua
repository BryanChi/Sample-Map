-- Sample Map Browser module: feedback
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
-- Hooks the shared feedback window (feedback/CRS_Feedback.lua) into Sample Map:
-- the menu bar's "Feedback" item opens it, and the browser's log ring buffer
-- (log() / sm_error_log_lines()) becomes the report's usage log.
local r = reaper

local FEEDBACK_MAX_INCOMPLETE = 40
local FEEDBACK_SCAN_LOG_TAIL = 80

-- "WAV pcm 24-bit 2ch 48000 Hz" style summary of a file's header, or why it can't be read.
local function sm_feedback_header(path)
  local fh = io.open(path or "", "rb")
  if not fh then
    return "can't open file"
  end
  local head = fh:read(64) or ""
  local size = fh:seek("end")
  fh:close()
  local function u16(at) local a, b = head:byte(at, at + 1); return (a or 0) + (b or 0) * 256 end
  local function u32(at) return u16(at) + u16(at + 2) * 65536 end
  local out
  if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WAVE" then
    if head:sub(13, 16) == "fmt " then
      local tags = { [1] = "pcm", [3] = "float", [2] = "adpcm", [17] = "ima-adpcm", [85] = "mp3", [65534] = "extensible" }
      local tag = u16(21)
      out = string.format("WAV %s %d-bit %dch %d Hz", tags[tag] or ("format " .. tag), u16(35), u16(23), u32(25))
    else
      out = "WAV, first chunk '" .. head:sub(13, 16):gsub("[^%w ]", "?") .. "'"
    end
  elseif head:sub(1, 4) == "FORM" then
    out = head:sub(9, 12) == "AIFC" and "AIFF-C" or "AIFF"
  else
    out = "starts with bytes " .. head:sub(1, 12):gsub(".", function(c) return string.format("%02X", c:byte()) end)
  end
  return string.format("%s, %d bytes", out, size or 0)
end

-- Usage log for feedback reports: error log, then scan diagnostics at the end
-- (the feedback window keeps the last lines when the log is long).
function sm_feedback_log_lines()
  local out = {}
  for _, l in ipairs(sm_error_log_lines() or {}) do
    out[#out + 1] = l
  end
  out[#out + 1] = ""
  out[#out + 1] = "-- Library and analyzer --"
  out[#out + 1] = string.format("Samples: %d, analyzer: %s, scan running: %s",
    #(state.samples or {}), tostring(state.analyzer_numpy_status or "unknown"), tostring(state.scan_running and true or false))
  local ok_inc, incomplete = pcall(function()
    local list = {}
    for _, s in ipairs(state.samples or {}) do
      if sample_analysis_incomplete(s) then
        list[#list + 1] = s
      end
    end
    return list
  end)
  if ok_inc and #incomplete > 0 then
    out[#out + 1] = string.format("%d sample(s) missing analysis%s:", #incomplete,
      #incomplete > FEEDBACK_MAX_INCOMPLETE and (" (first " .. FEEDBACK_MAX_INCOMPLETE .. ")") or "")
    for i = 1, math.min(#incomplete, FEEDBACK_MAX_INCOMPLETE) do
      local s = incomplete[i]
      local why = s._analyze_fail
      if type(why) ~= "string" or why == "" then
        why = "not analyzed this session; missing " .. table.concat(sample_analysis_missing_fields(s), ", ")
      end
      local ok_h, header = pcall(sm_feedback_header, s.path)
      out[#out + 1] = string.format("  %s | %s | %s | duration %s",
        tostring(s.path), why, ok_h and header or "header error", tostring(s.duration))
    end
  elseif ok_inc then
    out[#out + 1] = "All samples have analysis."
  end
  local scan = state.scan_logs or {}
  if #scan > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "-- Scan log (last " .. math.min(#scan, FEEDBACK_SCAN_LOG_TAIL) .. " lines) --"
    for i = math.max(1, #scan - FEEDBACK_SCAN_LOG_TAIL + 1), #scan do
      out[#out + 1] = scan[i]
    end
  end
  return out
end

local function sm_feedback_module()
  if SM_FEEDBACK ~= nil then
    return SM_FEEDBACK or nil
  end
  local dir = (select(2, r.get_action_context()) or ""):match("^(.+)[/\\][^/\\]+$")
    or (r.GetResourcePath() .. "/Scripts/Sample Map")
  local ok, mod = pcall(dofile, dir .. "/feedback/CRS_Feedback.lua")
  if not ok or type(mod) ~= "table" then
    log("Feedback window unavailable: " .. tostring(mod))
    SM_FEEDBACK = false
    return nil
  end
  local version = "?"
  local fh = io.open(dir .. "/Sample Map Browser.lua", "rb")
  if fh then
    version = (fh:read(400) or ""):match("@version%s+(%S+)") or version
    fh:close()
  end
  mod.Setup({
    script_id = "sample-map",
    script_name = "Sample Map",
    version = version,
    repo = "BryanChi/Sample-Map",
    get_log = sm_feedback_log_lines,
  })
  SM_FEEDBACK = mod
  return mod
end

function sm_open_feedback(opts)
  local mod = sm_feedback_module()
  if mod then
    mod.Open(opts)
  else
    sm_notify("The feedback window is missing; update Sample Map to get it.", "warn")
  end
end

-- Load the module at startup so a bug recording left on resumes with Sample Map.
pcall(sm_feedback_module)

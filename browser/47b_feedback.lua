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
    -- Monolith fonts for the window's own context (a missing mono falls back)
    fonts = {
      title = dir .. "/assets/fonts/Anton-Regular.ttf",
      body = dir .. "/assets/fonts/InterTight-VariableFont_wght.ttf",
      body_bold = dir .. "/assets/fonts/InterTight-SemiBold.ttf",
    },
    record_hint = "or the red dot next to Send feedback in the menu bar",
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

-- Menu bar "Send feedback" with a red record dot on its left: the dot starts
-- bug recording right away, and while recording it blinks and stops it
-- (opening the window with the recording attached). A green count after the
-- label: bug recordings saved and waiting to be sent.
local FB_DOT_W = 20
local FB_COUNT_W = 18
local FB_RED = 0xEF5A5AFF
local FB_GREEN = 0x49CC85FF

local function fb_alpha(c, a)
  return (c & 0xFFFFFF00) | (math.floor(a) & 0xFF)
end

local function fb_tip(text)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, text)
  end
end

function sm_draw_feedback_pill()
  local mod = SM_FEEDBACK or nil
  local recording = mod and mod.IsRecording and mod.IsRecording() or false
  local saved = mod and mod.RecordingCount and mod.RecordingCount() or 0
  local label = SM_MONO_SPACE and "SEND FEEDBACK" or "Send feedback"
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local _, fpy = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
  local py = math.min(3, fpy or 3)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local dot_click = r.ImGui_InvisibleButton(ctx, "##sm_fb_rec", FB_DOT_W, th)
  local dot_hov, dot_held = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local L, T = r.ImGui_GetItemRectMin(ctx)
  local M = r.ImGui_GetItemRectMax(ctx)
  fb_tip(recording and "Bug recording is on.\nClick to stop and send it with a report."
    or "Start bug recording now.\nRepeat the problem, then click the dot again to stop and send it.")
  r.ImGui_SameLine(ctx, 0, 0) -- the two halves share one frame
  local lbl_click = r.ImGui_InvisibleButton(ctx, "##sm_fb", 7 + tw + 7 + (saved > 0 and FB_COUNT_W or 0), th)
  local lbl_hov, lbl_held = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local R, B = r.ImGui_GetItemRectMax(ctx)
  fb_tip(recording and "Bug recording is on. Open the feedback window."
    or (saved > 0 and (saved .. (saved == 1 and " bug recording waits" or " bug recordings wait") .. " to be sent. Open the feedback window."))
    or "Report a bug or suggest an idea.\nYou can add pictures and the usage log; it goes to the developer on GitHub.")

  T, B = T - py, B + py
  local round = SM_MONO_SPACE and 0 or 4
  local function plate(x0, x1, hov, held, flags)
    if hov then
      r.ImGui_DrawList_AddRectFilled(dl, x0, T, x1, B, held and UI_THEME.surface_act or UI_THEME.surface_hvr, round, flags)
    end
  end
  plate(L, M, dot_hov, dot_held, r.ImGui_DrawFlags_RoundCornersLeft())
  plate(M, R, lbl_hov, lbl_held, r.ImGui_DrawFlags_RoundCornersRight())
  r.ImGui_DrawList_AddRect(dl, L, T, R, B, (dot_hov or lbl_hov) and UI_THEME.border_hvr or UI_THEME.border, round, 0, 1)
  r.ImGui_DrawList_AddLine(dl, M, T + 4, M, B - 4, UI_THEME.border, 1)

  local cx, cy = L + FB_DOT_W / 2 + 1, (T + B) / 2
  if recording then
    local a = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(r.time_precise() * 4.2))
    r.ImGui_DrawList_AddCircle(dl, cx, cy, 7, fb_alpha(FB_RED, a * 0x70), 0, 1)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 4.5, fb_alpha(FB_RED, a * 0xFF))
  else
    if dot_hov then r.ImGui_DrawList_AddCircle(dl, cx, cy, 7, fb_alpha(FB_RED, 0x80), 0, 1) end
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 4, dot_hov and 0xFF7A7AFF or fb_alpha(FB_RED, 0xCC))
  end
  local lx = M + 7
  r.ImGui_DrawList_AddText(dl, lx, cy - th / 2, lbl_hov and UI_THEME.text or UI_THEME.text_dim, label)
  if saved > 0 then
    local n = saved > 9 and "9+" or tostring(saved)
    local nw, nh = r.ImGui_CalcTextSize(ctx, n)
    local ccx = lx + tw + 4 + FB_COUNT_W / 2 - 2
    r.ImGui_DrawList_AddCircleFilled(dl, ccx, cy, 7, FB_GREEN)
    r.ImGui_DrawList_AddText(dl, ccx - nw / 2, cy - nh / 2, 0x000000FF, n)
  end

  if dot_click then
    if not mod then
      sm_open_feedback() -- says the window is missing
    elseif recording then
      if mod.StopAndReport then mod.StopAndReport() else mod.StopRecording(); mod.Open() end
    elseif mod.StartRecording then
      mod.StartRecording()
    end
  elseif lbl_click then
    sm_open_feedback()
  end
end

-- Load the module at startup so a bug recording left on resumes with Sample Map.
pcall(sm_feedback_module)

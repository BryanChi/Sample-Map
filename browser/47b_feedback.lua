-- Sample Map Browser module: feedback
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
-- Hooks the shared feedback window (feedback/CRS_Feedback.lua) into Sample Map:
-- the menu bar's "Feedback" item opens it, and the browser's log ring buffer
-- (log() / sm_error_log_lines()) becomes the report's usage log.
local r = reaper

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
    get_log = sm_error_log_lines,
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

-- @noindex
-- CRS Feedback recorder: the bug-recording badge and the window that sends the
-- recording, as a script of their own. CRS_Feedback.lua (next to this file)
-- starts it when bug recording starts, so the badge stays up and the report
-- can still be sent when the script being recorded crashes or is closed.
-- It isn't meant to be run by hand: without a script asking for it, it quits.

local r = reaper
local dir = (debug.getinfo(1, "S").source or ""):match("^@(.+)[/\\][^/\\]+$")
local script_id = r.GetExtState("CRS_Feedback", "recorder_launch")
r.DeleteExtState("CRS_Feedback", "recorder_launch", false)
if script_id == "" or not dir then
  return
end

-- Relaunching (the host thinks this one stopped) restarts it; its state is on disk.
if r.set_action_options then
  r.set_action_options(1 | 2)
end

local ok, F = pcall(dofile, dir .. "/CRS_Feedback.lua")
if not ok or type(F) ~= "table" or not F.RunCompanion then
  r.ShowConsoleMsg("CRS Feedback recorder couldn't start: " .. tostring(F) .. "\n")
  return
end
F.RunCompanion(script_id)

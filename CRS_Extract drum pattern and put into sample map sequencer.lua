-- @description CRS_Extract drum pattern and put into sample map sequencer
-- @version 0.1.0
-- @author bryan
-- @about
--   Companion to Sample Map Browser. Run with an audio item selected.
--   Stem-splits (or skips mix split for drum loops), splits the kit,
--   detects transients, tempo-maps, and places hits on the Sample Map sequencer
--   using per-hit sample offsets from the original audio.
-- @provides
--   [main] .

local r = reaper

local _, script_path = r.get_action_context()
local SCRIPT_DIR = (script_path and script_path:match("^(.+)[/\\][^/\\]+$"))
  or (r.GetResourcePath() .. "/Scripts/Sample Map")

local ok_load, err_load = pcall(dofile, SCRIPT_DIR .. "/SampleMapStemImport.lua")
if not ok_load or not SampleMapStemImport then
  r.ShowMessageBox(
    "Could not load SampleMapStemImport.lua:\n" .. tostring(err_load),
    "Extract drum pattern",
    0
  )
  return
end

local SM = SampleMapStemImport
local info, err = SM.selected_item_audio()
if not info then
  r.ShowMessageBox(err or "Select an audio item first.", "Extract drum pattern", 0)
  return
end

SM.write_request({
  path = info.path,
  start = string.format("%.6f", info.start or 0),
  duration = string.format("%.6f", info.duration or 0),
  place_time = string.format("%.6f", info.place_time or 0),
  name = info.name or "",
  item_guid = info.guid or "",
})

if SM.sample_map_is_running() then
  return
end

local launched, launch_err = SM.launch_sample_map(SCRIPT_DIR)
if not launched then
  r.ShowMessageBox(
    (launch_err or "Could not open Sample Map Browser.")
      .. "\n\nOpen Sample Map Sequencer, then run this action again.",
    "Extract drum pattern",
    0
  )
end

-- @description Sample Map Browser (Lua + ReaImGui)
-- @version 0.1.0
-- @author bryan
-- @about Scans user folders for audio files, derives simple metadata, and shows an interactive 2D map where each file is a dot. Click a dot to preview the file.
-- @requires ReaImGui
-- @provides
--   [nomain] browser/*.lua
--   [nomain] SampleMapUpdate.lua
--   [nomain] SampleMapStemImport.lua
--   [nomain] SampleMapAnalyzer.py
--   [nomain] SampleMapDrumAI.py
--   [nomain] SampleMapGrooveMIDI.py
--   [nomain] tag_presets.default.lua
--   [nomain] assets/*
--   [nomain] assets/behringer-icons/*
--   [nomain] assets/behringer-icons/png/*
--   [nomain] assets/fx-device-icons/*
--   [nomain] assets/vertical-fx-icons/*
--   [effect] Effects/*.jsfx

r = reaper

-- Check for ReaImGui
if not r.APIExists('ImGui_GetVersion') then
  r.ShowMessageBox("ReaImGui is required for this script.", "Missing dependency", 0)
  return
end

-- Check for JS_ReaScriptAPI (optional but recommended for folder browsing)
if not r.APIExists("JS_Dialog_BrowseForFolder") then
  r.ShowMessageBox("JS_ReaScriptAPI extension is recommended for folder browsing.\n\nInstall via: Extensions > ReaPack > Browse Packages > Search 'js_ReaScriptAPI'\n\nYou can still use the script, but folder selection will be limited.", "Extension Recommended", 0)
end

-- The browser is split into modules under browser/. They run in order and share
-- globals, which also keeps each chunk well under Lua's 200-local limit.
SAMPLE_MAP_BROWSER_MODULES = {
  "01_state.lua",
  "02_helpers.lua",
  "03_json.lua",
  "04_preview_track.lua",
  "05_persistence.lua",
  "06_scanning.lua",
  "07_waveform.lua",
  "08_preview.lua",
  "09_ui_helpers.lua",
  "10_map_index.lua",
  "11_ui_kit.lua",
  "11b_hint_card.lua",
  "12_seq_tracks.lua",
  "13_seq_track_order.lua",
  "14_seq_note_samples.lua",
  "15_seq_popups.lua",
  "16_seq_icons.lua",
  "17_seq_arrange_overlay.lua",
  "18_seq_regions.lua",
  "19_seq_random.lua",
  "20_seq_random_ui.lua",
  "21_seq_notes.lua",
  "22_seq_parent_items.lua",
  "23_seq_render_items.lua",
  "24_seq_mix_envelope.lua",
  "25_seq_envelope_apply.lua",
  "26_seq_track_controls.lua",
  "27_seq_midi_env_popups.lua",
  "28_drum_layering.lua",
  "29_groove.lua",
  "30_seq_sync.lua",
  "31_seq_ingest.lua",
  "32_seq_transport_input.lua",
  "33_seq_generate.lua",
  "34_seq_pattern_popup.lua",
  "35_seq_kit_random.lua",
  "36_seq_razor.lua",
  "37_seq_note_drag.lua",
  "38_seq_header.lua",
  "39_seq_stem_import.lua",
  "40_sequencer_view.lua",
  "41_explorer.lua",
  "42_map_tabs.lua",
  "43_map_layout.lua",
  "44_settings.lua",
  "45_map_input.lua",
  "46_map_render.lua",
  "47_main_loop.lua",
  "48_main_entry.lua",
}
do
  local dir = (select(2, reaper.get_action_context()) or ""):match("^(.+)[/\\][^/\\]+$")
    or (reaper.GetResourcePath() .. "/Scripts/Sample Map")
  local missing = {}
  for _, name in ipairs(SAMPLE_MAP_BROWSER_MODULES) do
    local fh = io.open(dir .. "/browser/" .. name, "rb")
    if fh then
      fh:close()
    else
      missing[#missing + 1] = "browser/" .. name
    end
  end
  -- An update made by an older updater brings this file but not browser/*.lua;
  -- fetch the missing modules from the installed version once.
  if #missing > 0 then
    SAMPLE_MAP_SCRIPT_DIR = dir
    local ok_upd = pcall(dofile, dir .. "/SampleMapUpdate.lua")
    local ok, err = false, "SampleMapUpdate.lua is missing"
    if ok_upd and SampleMapFetchFilesSync then
      ok, err = SampleMapFetchFilesSync(missing)
    end
    if not ok then
      reaper.ShowMessageBox("Sample Map Browser is missing " .. #missing .. " file(s) in its browser/ folder"
        .. " and could not download them:\n\n" .. tostring(err)
        .. "\n\nReinstall or update Sample Map from GitHub (BryanChi/Sample-Map).", "Sample Map Browser", 0)
      return
    end
  end
  for _, name in ipairs(SAMPLE_MAP_BROWSER_MODULES) do
    local chunk, err = loadfile(dir .. "/browser/" .. name)
    if not chunk then
      reaper.ShowMessageBox("Could not load browser/" .. name .. ":\n\n" .. tostring(err), "Sample Map Browser", 0)
      return
    end
    chunk()
  end
end

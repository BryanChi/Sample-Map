"""Tests for the pattern presets (browser/19b_seq_pattern_library.lua), two-bar
template generation, and a smoke render of the pattern window with a stub
ReaImGui. Requires `pip install lupa`."""
import os
import tempfile

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Generic reaper stub: ImGui getters return zeros, predicates false, enums 0.
STUB = r'''
EXT = {}
local special = {
  get_action_context = function() return false, SCRIPT_PATH, 0, 0, 0, 0, 0 end,
  GetResourcePath = function() return RES end,
  GetOS = function() return "macOS-arm64" end,
  GetExtState = function(s, k) return EXT[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) EXT[s .. "/" .. k] = tostring(v) end,
  HasExtState = function(s, k) return EXT[s .. "/" .. k] ~= nil end,
  APIExists = function() return true end,
  time_precise = function() return os.clock() end,
  EnumProjects = function() return "PROJ", "" end,
  ImGui_Begin = function() return true, true end,
  ImGui_BeginChild = function() return true end,
  ImGui_CalcTextSize = function(_, s) return #tostring(s) * 7, 14 end,
  ImGui_GetContentRegionAvail = function() return 360, 600 end,
  ImGui_GetCursorScreenPos = function() return 0, 0 end,
  ImGui_GetMousePos = function() return 40, 40 end,
  ImGui_GetItemRectMin = function() return 0, 0 end,
  ImGui_GetItemRectMax = function() return 360, 46 end,
  ImGui_GetStyleVar = function() return 4, 4 end,
  ImGui_GetWindowDrawList = function() return {} end,
  ImGui_IsItemHovered = function() return HOVER end,
  ImGui_IsWindowHovered = function() return HOVER end,
  ImGui_InputTextWithHint = function(_, _, _, v) return false, v end,
}
DRAWN = {}
reaper = setmetatable({}, { __index = function(t, k)
  local f = special[k]
  if not f then
    if k:match("^ImGui_DrawList_") then
      f = function(...) DRAWN[#DRAWN + 1] = k end
    elseif k:match("^ImGui_[A-Z]%w*Flags_") or k:match("^ImGui_Col_") or k:match("^ImGui_Key_")
        or k:match("^ImGui_StyleVar_") or k:match("^ImGui_Cond_") or k:match("^ImGui_Mod_") then
      f = function() return 0 end
    elseif k:match("^ImGui_Is") or k:match("^ImGui_Begin") then
      f = function() return false end
    elseif k:match("^ImGui_Get") or k:match("^ImGui_Calc") then
      f = function() return 0, 0 end
    else
      f = function() return nil end
    end
  end
  rawset(t, k, f)
  return f
end })
gfx = setmetatable({}, { __index = function() return function() return 0 end end })
'''

MODULES = [
    "01_state.lua", "02_helpers.lua", "03_json.lua", "09_ui_helpers.lua", "11_ui_kit.lua",
    "11b_hint_card.lua", "18_seq_regions.lua", "19_seq_random.lua", "19b_seq_pattern_library.lua",
    "33_seq_generate.lua", "34_seq_pattern_popup.lua",
]


def _runtime():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    tmp = tempfile.mkdtemp()
    L.globals().RES = tmp
    L.globals().SCRIPT_PATH = os.path.join(tmp, "Sample Map Browser.lua")
    L.globals().HOVER = False
    L.execute(STUB)
    for name in MODULES:
        with open(os.path.join(ROOT, "browser", name), "rb") as fh:
            L.execute(fh.read())
    L.execute("ctx = {}; log = function() end; save_config = function() end")
    return L


def test_every_preset_is_consistent():
    L = _runtime()
    problems = L.execute(r'''
      local out, seen, cats = {}, {}, {}
      for _, c in ipairs(SEQ_PATTERN_CATEGORIES) do cats[c.key] = true end
      for _, s in ipairs(SEQ_GEN_STYLE_ORDER) do
        if s.key then
          if seen[s.key] then out[#out + 1] = "duplicate " .. s.key end
          seen[s.key] = true
          if not cats[s.cat or ""] then out[#out + 1] = "no category " .. s.key end
          local t = SEQ_GEN_TEMPLATES[s.key]
          if not t then out[#out + 1] = "no template " .. s.key end
          for role, steps in pairs(t or {}) do
            if not SEQ_ROLE_LABELS[role] then out[#out + 1] = s.key .. " unknown role " .. tostring(role) end
            for _, st in ipairs(steps) do
              if math.type(st) ~= "integer" or st < 0 or st > 31 then
                out[#out + 1] = s.key .. " bad step " .. tostring(st)
              end
            end
          end
        end
      end
      for key in pairs(SEQ_GEN_TEMPLATES) do
        if not seen[key] then out[#out + 1] = "template without a list entry " .. key end
      end
      return table.concat(out, "\n")
    ''')
    assert problems == ""
    count = L.execute("local n = 0 for k in pairs(SEQ_GEN_TEMPLATES) do n = n + 1 end return n")
    assert count >= 60


def test_existing_style_keys_still_resolve():
    # Saved projects store these keys; they must keep working.
    L = _runtime()
    for key in ["house", "techno", "disco", "basic", "rock", "hiphop", "trap", "funk", "dnb",
                "breakbeat", "reggaeton", "afrobeat", "dust_motes", "static_bloom"]:
        assert L.globals().normalize_seq_gen_style(key) == key


def test_two_bar_template_alternates_bars():
    L = _runtime()
    hits = L.execute(r'''
      SEQ_GEN_TEMPLATES.__test = { kick = {0, 20} }
      state.seq_grid_qn = 0.25
      state.seq_tracks = { { id = 1, sample_path = "/k.wav" } }
      infer_seq_track_role = function() return "kick" end
      get_seq_pattern = function() return PAT end
      PAT = { notes = {} }
      get_seq_region_length_qn = function() return 16 end -- 4 bars
      seq_merge_locked_cell_seen = function(seen) return seen end
      make_default_seq_note = function(_, step) return { step = step } end
      local placed = {}
      set_seq_note = function(_, _, step) placed[#placed + 1] = step end
      sync_seq_pattern_regions = function() end
      generate_seq_pattern({ pattern_id = 1 }, "__test", {})
      table.sort(placed)
      return table.concat(placed, ",")
    ''')
    # bar 1: step 0, bar 2: step 16 + 4, bar 3: 32, bar 4: 48 + 4
    assert hits == "0,20,32,52"


def test_pattern_window_renders_all_categories():
    L = _runtime()
    err = L.execute(r'''
      seq_mark_text_input_item = function() end
      seq_preset_can_generate = function() return true end
      seq_gmd_available = function() return false end
      seq_truncate_text_to_width = function(s) return s end
      get_seq_region_display_name = function() return "Region 1" end
      state.main_window_rect = { x = 0, y = 0, w = 800, h = 600 }
      state.seq_pattern_window_open = true
      local region = { id = 1, pattern_id = 1 }
      local cats = { "all", "fav", "gmd" }
      for _, c in ipairs(SEQ_PATTERN_CATEGORIES) do cats[#cats + 1] = c.key end
      for pass = 1, 2 do
        HOVER = pass == 2
        for _, c in ipairs(cats) do
          seq_pattern_set_category(c)
          local ok, e = xpcall(render_seq_pattern_popup, debug.traceback, region)
          if not ok then return c .. ": " .. tostring(e) end
        end
      end
      return ""
    ''')
    assert err == ""
    assert L.execute("return #DRAWN") > 100


def test_favorites_persist_and_filter():
    L = _runtime()
    shown = L.execute(r'''
      seq_pattern_toggle_favorite("trap")
      seq_pattern_toggle_favorite("bossa")
      seq_pattern_toggle_favorite("trap")
      state.seq_pattern_favs = nil -- reload from ExtState
      seq_gmd_available = function() return false end
      seq_pattern_set_category("fav")
      local keys = {}
      for _, e in ipairs(seq_pattern_browser_entries()) do
        if e.kind == "template" then keys[#keys + 1] = e.style_def.key end
      end
      return table.concat(keys, ",")
    ''')
    assert shown == "bossa"


def test_map_preview_lanes_and_two_bar_width():
    L = _runtime()
    out = L.execute(r'''
      local d = seq_pattern_preview_from_map({ snare = {4, 12}, kick = {0, 20}, hat = {} })
      local roles = {}
      for _, lane in ipairs(d.lanes) do roles[#roles + 1] = lane.role end
      return table.concat(roles, ",") .. "|" .. d.cols .. "|" .. tostring(seq_pattern_preview_from_map({ kick = {0} }) ~= nil)
    ''')
    assert out == "kick,snare|32|true"


def test_collect_preview_positions_keeps_first_bars():
    L = _runtime()
    out = L.execute(r'''
      state.seq_grid_qn = 0.25
      state.seq_tracks = { { id = 1, sample_path = "/k.wav" }, { id = 2, sample_path = "/s.wav" } }
      infer_seq_track_role = function(slot) return slot.id == 1 and "kick" or "snare" end
      get_seq_pattern = function() return { notes = {
        ["1"] = { ["0"] = { step = 0 }, ["18"] = { step = 18 }, ["40"] = { step = 40 } },
        ["2"] = { ["4"] = { step = 4 }, ["6"] = { step = 6, enabled = false } },
      } } end
      local m = seq_collect_preview_positions({ pattern_id = 1 }, 2)
      return table.concat(m.kick, ",") .. "|" .. table.concat(m.snare, ",")
    ''')
    assert out == "0,18|4"


def test_child_rows_and_variation_popup_render():
    L = _runtime()
    err = L.execute(r'''
      reaper.ImGui_BeginPopup = function() return true end
      seq_truncate_text_to_width = function(s) return s end
      get_seq_region_display_name = function() return "Region 1" end
      local region = { id = 1, pattern_id = 1 }
      HOVER = true
      local child = { label = "Funk 1", item = { id = "d1/s1/1", bpm = 96, drummer = "drummer1",
        preview = { kick = {0, 10}, snare = {4, 12}, hat = {0, 2, 4, 6} }, preview_bar = 1 } }
      local old = { label = "Funk 2", item = { id = "d1/s1/2", bpm = 100 } }
      state.seq_pattern_variations = { house = { counter = 2, entries = {
        { id = 1, strength = 3, seed = 9, preview = { kick = {0, 4, 8, 12} } },
        { id = 2, ai = true, ai_variation = 0.5, ai_pattern = { kick = {0}, clap = {4, 12} } },
      } } }
      state.seq_pattern_variations_open_key = "house"
      for _, f in ipairs({
        function() render_seq_gmd_pattern_row(region, child, "g") end,
        function() render_seq_gmd_pattern_row(region, old, "g") end,
        function() render_seq_pattern_variations_popup(region) end,
      }) do
        local ok, e = xpcall(f, debug.traceback)
        if not ok then return tostring(e) end
      end
      return ""
    ''')
    assert err == ""

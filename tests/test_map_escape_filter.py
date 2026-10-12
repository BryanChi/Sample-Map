"""Esc in the Sample Map clears the applied filter: tag chips first, then the
search text. Loads the whole browser with the stub REAPER API from load_browser.py.
Requires `pip install lupa`."""
import os
import re
import tempfile

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def _runtime():
    src = open(os.path.join(HERE, "load_browser.py"), encoding="utf-8").read()
    stub = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    g.FRAMES = 0
    err = L.execute(stub + r'''
      local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
      if not chunk then return err end
      local ok, e = xpcall(chunk, debug.traceback)
      if not ok then return e end
      log = function() end
      save_config = function() end
      save_samples = function() end
      return nil
    ''')
    assert err is None, err
    return L


def test_escape_clears_tags_then_search_text():
    L = _runtime()
    out = L.execute(r'''
      state.active_view = "sample_map"
      state.sample_map_floating = false
      state.map_ui_edit = false
      state.active_tags = { kick = true, ["120 bpm"] = true }
      state.selected_tag_parents = { tempo = true }
      state.filter = "808"
      local o = {}
      o[#o + 1] = tostring(map_clear_applied_filter())
      o[#o + 1] = tostring(next(state.active_tags) == nil and next(state.selected_tag_parents) == nil)
      o[#o + 1] = state.filter
      o[#o + 1] = tostring(map_clear_applied_filter())
      o[#o + 1] = state.filter == "" and "cleared" or "kept"
      o[#o + 1] = tostring(map_clear_applied_filter())
      return table.concat(o, "|")
    ''')
    assert out == "true|true|808|true|cleared|false"


def test_escape_is_ignored_while_layout_editing():
    L = _runtime()
    out = L.execute(r'''
      state.map_ui_edit = true
      state.active_tags = { kick = true }
      -- handle_map_arrow_keys sees Esc pressed, but layout edit owns it.
      local pressed = 0
      rawset(reaper, "ImGui_Key_Escape", function() return 1 end)
      rawset(reaper, "ImGui_IsKeyPressed", function() pressed = pressed + 1 return true end)
      handle_map_arrow_keys()
      return tostring(next(state.active_tags) ~= nil) .. "|" .. tostring(pressed)
    ''')
    assert out.startswith("true|")

"""Sample Map Tabs / Path / Waveform modules (browser/42b_map_modules.lua):
how they lay themselves out for any module size, tab actions, and the
column that has nothing stretchy giving its spare room to the waveform."""
import os
import re
import tempfile

from lupa import lua54

here = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(here, ".."))
src = open(os.path.join(here, "load_browser.py"), encoding="utf-8").read()
STUB = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)

HARNESS = r'''
local chunk = assert(loadfile(REPO .. "/Sample Map Browser.lua"))
assert(xpcall(chunk, debug.traceback))
save_config = function() end
function lines_of(plan)
  local out = {}
  for i, line in ipairs(plan.lines) do
    local t = {}
    for k, v in ipairs(line) do t[k] = tostring(v) end
    out[i] = table.concat(t, ",")
  end
  return table.concat(out, "|")
end
function const(w) return function() return w end end
'''


def _rt():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO, g.RES, g.FRAMES = REPO, tempfile.mkdtemp(), 1
    L.execute(STUB + HARNESS)
    return L


def test_tabs_fit_on_one_line_when_there_is_room():
    L = _rt()
    plan = 'map_tabs_plan({80, 60, 90}, 400, 1, { gap = 3, add_w = 22 })'
    assert L.eval(f'lines_of({plan})') == "1,2,3,add"


def test_tabs_wrap_when_the_module_has_more_lines():
    L = _rt()
    plan = 'map_tabs_plan({120, 120, 120, 120}, 260, 2, { gap = 3, add_w = 22 })'
    assert L.eval(f'lines_of({plan})') == "1,2|3,4,add"


def test_tabs_shrink_before_anything_is_hidden():
    L = _rt()
    L.execute('P = map_tabs_plan({120, 120, 120}, 300, 1, { gap = 3, add_w = 22, min_w = 52 })')
    assert L.eval('lines_of(P)') == "1,2,3,add"
    assert L.eval('#P.hidden') == 0
    total = L.eval('P.widths[1] + P.widths[2] + P.widths[3]') + 22 + 9
    assert total <= 300
    assert L.eval('P.widths[1]') >= 52


def test_tabs_overflow_into_more_and_keep_the_active_one():
    L = _rt()
    L.execute('P = map_tabs_plan({90, 90, 90, 90, 90, 90, 90, 90}, 240, 1, { gap = 3, add_w = 22, min_w = 52, more_w = 38, active = 8 })')
    line = L.eval('lines_of(P)').split(",")
    assert line[-2:] == ["more", "add"]
    assert "8" in line  # the active tab is shown
    hidden = [L.eval(f'P.hidden[{i}]') for i in range(1, L.eval('#P.hidden') + 1)]
    shown = [int(x) for x in line if x.isdigit()]
    assert sorted(hidden + shown) == list(range(1, 9))


def test_tabs_one_per_line_in_a_narrow_column():
    L = _rt()
    plan = 'map_tabs_plan({90, 90, 90}, 120, 6, { vertical = true, add_w = 22 })'
    assert L.eval(f'lines_of({plan})') == "1|2|3|add"
    L.execute('P = map_tabs_plan({90, 90, 90, 90, 90}, 120, 3, { vertical = true, add_w = 22, active = 5 })')
    assert L.eval('lines_of(P)') == "1|5|more,add"


def test_path_folds_middle_folders_until_it_fits():
    L = _rt()
    # five folders of 60 px plus a 120 px file on 300 px lines
    L.execute('P = map_path_plan({60, 60, 60, 60, 60}, 120, const(300), 1, { gap = 2, more_w = 26 })')
    kinds = L.eval('(function() local t = {} for i, it in ipairs(P.items) do t[i] = it.kind .. (it.i or "") end return table.concat(t, " ") end)()')
    assert kinds.startswith("seg1 more")
    assert kinds.endswith("file")
    assert L.eval('#P.lines') == 1
    # with two lines nothing needs folding
    L.execute('P = map_path_plan({60, 60, 60, 60, 60}, 120, const(300), 2, { gap = 2 })')
    assert L.eval('#P.hidden') == 0 and L.eval('#P.lines') == 2


def test_path_tree_mode_puts_one_item_per_line():
    L = _rt()
    L.execute('P = map_path_plan({60, 60, 60}, 120, const(180), 4, { one_per_line = true })')
    assert L.eval('lines_of(P)') == "1|2|3|4"
    L.execute('P = map_path_plan({60, 60, 60, 60}, 120, const(180), 3, { one_per_line = true })')
    assert L.eval('#P.lines') == 3 and L.eval('P.items[2].kind') == "more"


def test_path_shortens_the_file_name_as_a_last_resort():
    L = _rt()
    L.execute('P = map_path_plan({60, 60}, 900, const(200), 1, { gap = 2, more_w = 26 })')
    assert L.eval('#P.lines') == 1
    file_w = L.eval('P.widths[#P.items]')
    assert file_w < 200


def test_text_fit_shortens_with_ellipsis():
    L = _rt()
    full = L.eval('map_module_text_fit("Acoustic", 1000)')
    assert full == "Acoustic"
    short = L.eval('map_module_text_fit("Acoustic Kicks Folder", 40)')
    assert short.endswith("...") and len(short) < len("Acoustic Kicks Folder")


def test_tab_actions_rename_duplicate_reorder_close_others():
    L = _rt()
    L.execute('''
      state.map_tabs = {}
      ensure_map_tabs()
      add_map_tab(); add_map_tab()
    ''')
    ids = lambda: [L.eval(f'state.map_tabs[{i}].id') for i in range(1, L.eval('#state.map_tabs') + 1)]
    a, b, c = ids()
    L.execute(f'rename_map_tab({b}, "  Drums  ")')
    assert L.eval(f'find_map_tab({b}).title') == "Drums"
    L.execute(f'rename_map_tab({b}, "")')
    assert L.eval(f'find_map_tab({b}).title') is None
    L.execute(f'duplicate_map_tab({a})')
    assert len(ids()) == 4 and ids()[0] == a and L.eval('state.map_tab_active_id') == ids()[1]
    L.execute(f'move_map_tab({c}, 1)')
    assert ids()[0] == c
    L.execute(f'close_other_map_tabs({b})')
    assert ids() == [b] and L.eval('state.map_tab_active_id') == b


def test_column_without_a_stretchy_module_gives_spare_room_to_the_waveform():
    L = _rt()
    L.execute('''
      state.map_ui_fit_h = {}
      COL = { type = "col", children = { { type = "leaf", id = "tabs" }, { type = "leaf", id = "path" }, { type = "leaf", id = "wave", h = 80 } } }
      HS = map_ui_col_heights(COL.children, 500)
    ''')
    assert L.eval('HS[1]') == 28 and L.eval('HS[2]') == 30
    assert L.eval('HS[1] + HS[2] + HS[3]') == 500 - 2 * L.eval('MAP_UI_GAP')


def test_tabs_module_height_follows_its_content():
    L = _rt()
    L.execute('state.map_ui_fit_h = { tabs = 53 }')
    assert L.eval('map_ui_pref_h({ type = "leaf", id = "tabs" })') == 53
    # a height set by dragging wins
    assert L.eval('map_ui_pref_h({ type = "leaf", id = "tabs", h = 40 })') == 40
    # only the tabs module follows its content
    assert L.eval('map_ui_auto_h("path")') is None

"""Sample Map layout edit logic (browser/42_map_tabs.lua): dragging the grip
between two modules trades space between those two only, snapping, swapping
two modules by dropping on the middle, and layout undo / redo."""
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
reaper.ShowMessageBox = function() return 6 end
MOUSE, ACTIVE, RELEASED, MODS = { 0, 0 }, false, false, 0
rawset(reaper, "ImGui_GetMousePos", function() return MOUSE[1], MOUSE[2] end)
rawset(reaper, "ImGui_IsItemActive", function() return ACTIVE end)
rawset(reaper, "ImGui_IsItemHovered", function() return false end)
rawset(reaper, "ImGui_IsMouseReleased", function() return RELEASED end)
rawset(reaper, "ImGui_GetKeyMods", function() return MODS end)
rawset(reaper, "ImGui_Mod_Shift", function() return 2 end)

-- Lays the tree out like map_ui_render_node does, without drawing.
function layout(w, h)
  state.map_ui_leaf_info, state.map_ui_rects = {}, {}
  local function walk(node, x, y, w, h, row_ctx, col_ctx)
    if node.type == "leaf" then
      state.map_ui_leaf_info[node.id] = { row = row_ctx, col = col_ctx, w = w, h = h }
      state.map_ui_rects[node.id] = { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
      return
    end
    if node.type == "row" then
      local ws = map_ui_row_widths(node.children, w)
      local cx = x
      for i, c in ipairs(node.children) do
        c._alloc_w, c._alloc_h = ws[i], h
        walk(c, cx, y, ws[i], h, { node = node, index = i }, col_ctx)
        cx = cx + ws[i] + MAP_UI_GAP
      end
    else
      local hs = map_ui_col_heights(node.children, h)
      local cy = y
      for i, c in ipairs(node.children) do
        c._alloc_w, c._alloc_h = w, hs[i]
        walk(c, x, cy, w, hs[i], row_ctx, { node = node, index = i })
        cy = cy + hs[i] + MAP_UI_GAP
      end
    end
  end
  walk(state.map_ui_layout, 0, 0, w, h)
end

function drag_edge(id, edge, dx, dy, mods)
  state.map_ui_edit = true
  state.map_ui_split_drag = nil
  layout(1200, 700)
  MODS = mods or 0
  MOUSE = { 500, 300 }
  ACTIVE, RELEASED = true, false
  map_ui_handle_edge(id, edge)
  MOUSE = { 500 + dx, 300 + dy }
  map_ui_handle_edge(id, edge)
  ACTIVE, RELEASED = false, true
  map_ui_handle_edge(id, edge)
  RELEASED = false
end

function rect(id)
  local r = state.map_ui_rects[id]
  return r.x1 - r.x0, r.y1 - r.y0
end
'''


def _rt():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO, g.RES, g.FRAMES = REPO, tempfile.mkdtemp(), 1
    L.execute(STUB + HARNESS)
    L.execute('state.map_ui_layout = default_map_ui_layout(); state.seq_panel_width = 240; layout(1200, 700)')
    return L


def _size(L, id_):
    L.execute('layout(1200, 700)')
    return tuple(L.eval(f'{{rect("{id_}")}}').values())


def test_grip_between_tabs_and_path_only_moves_those_two():
    L = _rt()
    wave0, map0 = _size(L, "wave"), _size(L, "map")
    L.execute('drag_edge("path", "top", 0, 4, 2)')  # Shift: no snap
    assert _size(L, "tabs")[1] == 32 and _size(L, "path")[1] == 26
    assert _size(L, "wave") == wave0 and _size(L, "map") == map0


def test_grip_respects_minimum_of_the_shrinking_module():
    L = _rt()
    L.execute('drag_edge("path", "top", 0, 40)')
    assert _size(L, "path")[1] == 24  # MAP_UI_SPEC.path.min_h
    assert _size(L, "tabs")[1] == 28 + 30 - 24


def test_flexible_neighbour_stays_flexible():
    L = _rt()
    L.execute('drag_edge("wave", "bottom", 0, 60)')
    assert _size(L, "wave")[1] == 140
    assert L.eval('state.map_ui_layout.children[2].children[4].h') is None
    # The map still fills the window when it grows.
    L.execute('layout(1200, 900)')
    assert L.eval('select(2, rect("map"))') > _size(L, "wave")[1]


def test_tracks_width_and_snap_to_default():
    L = _rt()
    L.execute('drag_edge("tracks", "right", 100, 0)')
    assert L.eval('state.seq_panel_width') == 340
    # Back to within the snap distance of 240 lands exactly on it ...
    L.execute('drag_edge("tracks", "right", -96, 0)')
    assert L.eval('state.seq_panel_width') == 240
    # ... unless Shift is held.
    L.execute('drag_edge("tracks", "right", 4, 0, 2)')
    assert L.eval('state.seq_panel_width') == 244


def test_snap_to_another_modules_edge():
    L = _rt()
    # Put Waveform beside Sample Map so the column has a vertical edge at
    # Waveform's right side; then drag Tracks' grip near it.
    L.execute('map_ui_dock("wave", "map", "left"); layout(1200, 700)')
    wave_x1 = L.eval('state.map_ui_rects.wave.x1')
    tracks_x1 = L.eval('state.map_ui_rects.tracks.x1')
    L.execute(f'drag_edge("tracks", "right", {wave_x1 - tracks_x1 - 4}, 0)')
    L.execute('layout(1200, 700)')
    assert L.eval('state.map_ui_rects.tracks.x1') == wave_x1


def test_drop_on_middle_swaps_and_undo_redo():
    L = _rt()
    L.execute('map_ui_dock("tracks", "map", "center")')
    assert L.eval('state.map_ui_layout.children[1].id') == "map"
    assert L.eval('state.map_ui_layout.children[2].children[4].id') == "tracks"
    L.execute('map_ui_undo()')
    assert L.eval('state.map_ui_layout.children[1].id') == "tracks"
    L.execute('map_ui_redo()')
    assert L.eval('state.map_ui_layout.children[1].id') == "map"


def test_resize_and_reset_are_undoable_and_a_click_adds_no_step():
    L = _rt()
    L.execute('drag_edge("tracks", "right", 0, 0)')
    assert L.eval('#(state.map_ui_undo or {})') == 0
    L.execute('drag_edge("tracks", "right", 100, 0)')
    L.execute('reset_map_ui_layout()')
    assert L.eval('state.seq_panel_width') == 240
    L.execute('map_ui_undo()')
    assert L.eval('state.map_ui_layout.children[1].w') == 340
    L.execute('map_ui_undo()')
    assert L.eval('state.map_ui_layout.children[1].w') == 240

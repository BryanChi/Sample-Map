"""Drum layering window (browser/28_drum_layering.lua, browser/28b_drum_layering_ui.lua):
model helpers, mix peaks, and the window driven with a stub ReaImGui that has a
mouse (hover, click, drag) so blend drags, the split handle and menus run for
real. Requires `pip install lupa`."""
import os
import tempfile

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

STUB = r'''
EXT = {}
local deferred = {}
MOUSE = { x = -1000, y = -1000, down = false, clicked = false, rclicked = false, dbl = false, dx = 0, dy = 0, shift = false }
ARRAYS = false
CALLS = 0
local cur = { 52, 50 }
local item, claimed, active_id, item_id = nil, nil, nil, nil
local popup_open, menu_pick = {}, nil
local special = {
  APIExists = function() return true end,
  get_action_context = function() return false, REPO .. "/Sample Map Browser.lua", 0, 0, 0, 0, 0 end,
  GetResourcePath = function() return RES end,
  GetOS = function() return "macOS-arm64" end,
  GetExtState = function(s, k) return EXT[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) EXT[s .. "/" .. k] = tostring(v) end,
  DeleteExtState = function(s, k) EXT[s .. "/" .. k] = nil end,
  HasExtState = function(s, k) return EXT[s .. "/" .. k] ~= nil end,
  GetProjExtState = function() return 0, "" end,
  EnumProjects = function() return "PROJ", "" end,
  GetProjectStateChangeCount = function() return 1 end,
  time_precise = function() return os.clock() end,
  defer = function(f) deferred[#deferred + 1] = f end,
  atexit = function() end,
  ShowMessageBox = function() return 1 end,
  ShowConsoleMsg = function() end,
  ImGui_CreateContext = function() return {} end,
  ImGui_ValidatePtr = function() return true end,
  ValidatePtr = function() return false end, ValidatePtr2 = function() return false end,
  ImGui_GetVersion = function() return "0.9.3", 0, "0.9.3" end,
  CountTracks = function() return 0 end, CountMediaItems = function() return 0 end,
  CountSelectedMediaItems = function() return 0 end, CountSelectedTracks = function() return 0 end,
  GetPlayState = function() return 0 end, GetCursorPosition = function() return 0 end,
  ExecProcess = function() return "1\n" end,
  EnumerateFiles = function() return nil end, EnumerateSubdirectories = function() return nil end,
  file_exists = function() return false end,
  RecursiveCreateDirectory = function() return 1 end,
  GetAppVersion = function() return "7.20/macOS-arm64" end,
  JS_VKeys_GetState = function() return string.rep("\0", 255) end,
  JS_Mouse_GetState = function() return 0 end,
  GetMousePosition = function() return 0, 0 end,
  TimeMap2_QNToTime = function(_, q) return q * 0.5 end, TimeMap2_timeToQN = function(_, t) return t * 2 end,
  GetProjectTimeSignature2 = function() return 120, 4 end, Master_GetTempo = function() return 120 end,
  TimeMap_GetDividedBpmAtTime = function() return 120 end,
  GetSetProjectInfo_String = function() return false, "" end, GetSetMediaTrackInfo_String = function() return false, "" end,
  GetProjectPath = function() return RES end, GetProjectName = function() return "" end,
  ImGui_GetVersion = function() return "0.9.3", 0, "0.9.3" end,
  ImGui_Begin = function() return true, true end, ImGui_BeginChild = function() return true end,
  ImGui_GetWindowPos = function() return 40, 40 end,
  ImGui_GetWindowSize = function() return 800, 600 end,
  ImGui_GetContentRegionAvail = function() return 776, 560 end,
  ImGui_GetCursorScreenPos = function() return cur[1], cur[2] end,
  ImGui_SetCursorScreenPos = function(_, x, y) cur[1], cur[2] = x, y end,
  ImGui_GetMousePos = function() return MOUSE.x, MOUSE.y end,
  ImGui_GetMouseDelta = function() return MOUSE.dx, MOUSE.dy end,
  ImGui_CalcTextSize = function(_, s) return #tostring(s) * 7, 14 end,
  ImGui_GetStyleVar = function() return 8, 4 end,
  ImGui_GetWindowDrawList = function() return {} end,
  ImGui_GetForegroundDrawList = function() return {} end,
  ImGui_IsWindowHovered = function() return MOUSE.x >= 40 and MOUSE.y >= 40 and MOUSE.x <= 840 and MOUSE.y <= 640 end,
  ImGui_IsMouseDown = function() return MOUSE.down end,
  ImGui_IsMouseClicked = function(_, b) if b == 1 then return MOUSE.rclicked end return MOUSE.clicked end,
  ImGui_IsMouseDoubleClicked = function() return MOUSE.dbl end,
  ImGui_IsMouseDragging = function() return MOUSE.down and (MOUSE.dx ~= 0 or MOUSE.dy ~= 0) end,
  ImGui_IsKeyDown = function() return MOUSE.shift end,
  ImGui_InvisibleButton = function(_, id, w, h)
    item = { cur[1], cur[2], cur[1] + w, cur[2] + h }
    item_id = id
    local over = MOUSE.x >= item[1] and MOUSE.x <= item[3] and MOUSE.y >= item[2] and MOUSE.y <= item[4]
    if over and not claimed then claimed = id end
    if claimed == id and MOUSE.clicked then active_id = id end
    if not MOUSE.down then
      local was = active_id == id
      if was then active_id = nil end
    end
    return claimed == id and MOUSE.clicked
  end,
  ImGui_IsItemHovered = function() return claimed ~= nil and claimed == item_id end,
  ImGui_IsItemActive = function() return active_id ~= nil and active_id == item_id end,
  ImGui_IsItemClicked = function(_, b)
    if claimed ~= item_id then return false end
    if b == 1 then return MOUSE.rclicked end
    return MOUSE.clicked
  end,
  ImGui_GetItemRectMin = function() return item[1], item[2] end,
  ImGui_GetItemRectMax = function() return item[3], item[4] end,
  ImGui_OpenPopup = function(_, id) popup_open[id] = true end,
  ImGui_BeginPopup = function(_, id) return popup_open[id] == true end,
  ImGui_EndPopup = function() end,
  ImGui_MenuItem = function(_, label) return menu_pick ~= nil and tostring(label):find(menu_pick, 1, true) == 1 end,
  ImGui_SetNextWindowSize = function(_, w, h) NEXT_SIZE = { w, h } end,
  new_array = function(t) if ARRAYS then return { pts = t } end return nil end,
}
function frame_begin() claimed = nil end
function set_menu_pick(label) menu_pick = label end
function close_popups() popup_open = {} end
function popup_is_open(id) return popup_open[id] == true end
local function default_for(name)
  if name:match("^ImGui_[A-Z]%w*Flags_") or name:match("^ImGui_Col_") or name:match("^ImGui_Key_")
     or name:match("^ImGui_Mod_") or name:match("^ImGui_StyleVar_") or name:match("^ImGui_Cond_")
     or name:match("^ImGui_MouseButton_") or name:match("^ImGui_Dir_") or name:match("^ImGui_MouseCursor_")
     or name:match("^ImGui_ConfigVar_") or name:match("^ImGui_DrawFlags_") or name:match("^ImGui_TableFlags_") then
    return function() return 0 end
  end
  if name:match("^ImGui_Is") or name:match("^ImGui_Begin") then return function() return false end end
  if name:match("^ImGui_Get") or name:match("^ImGui_Calc") then return function() return 0, 0 end end
  if name:match("^Count") then return function() return 0 end end
  return function() return nil end
end
reaper = setmetatable({}, { __index = function(t, k)
  local f = special[k] or default_for(k)
  local w = function(...) CALLS = CALLS + 1; return f(...) end
  rawset(t, k, w)
  return w
end })
gfx = setmetatable({}, { __index = function() return function() return 0 end end })
io.popen = function() return { read = function() return nil end, close = function() return true end, lines = function() return function() return nil end end } end
os.execute = function() return true end
local chunk = assert(loadfile(REPO .. "/Sample Map Browser.lua"))
chunk()
LOGS = {}
log = function(m) LOGS[#LOGS + 1] = tostring(m) end
for i = 1, 3 do local q = deferred; deferred = {}; for _, f in ipairs(q) do f() end end
LOGS = {}  -- the main window's startup frames don't concern this window
SAVES = 0
save_config = function() SAVES = SAVES + 1 end
SYNCS = 0
seq_layering_sync_arrange = function() SYNCS = SYNCS + 1 end
PREVIEWS = {}
preview_sample = function(s) PREVIEWS[#PREVIEWS + 1] = s and s.path end

function mk_sample(path, decay, tag)
  local s = { path = path, name = path:match("[^/]+$"), duration = 0.5, onset = 0.002, transient_end = 0.03, tags = { tag or "kick" } }
  state.samples[#state.samples + 1] = s
  local pk = {}
  for i = 1, 256 do pk[i] = math.exp(-i / decay) end
  seq_env_wave_cache[path] = { peaks = pk, duration = 0.5, width = 256, resized = {} }
  return s
end
A = mk_sample("/s/kick.wav", 40, "kick")
B = mk_sample("/s/click.wav", 6, "perc")
C = mk_sample("/s/sub.wav", 150, "808")
D = mk_sample("/s/other.wav", 30, "kick")
rebuild_samples_path_index()
SLOT = { id = 77, name = "Kick", sample_path = A.path, sample_name = A.name }
state.seq_tracks = { SLOT }
seq_layering_seed_from_track(SLOT)
SLOT.layers.transient.verts[2].path = B.path
SLOT.layers.transient.verts[3].path = C.path
SLOT.layers.sustain.verts[2].path = C.path
SLOT.layers.transient.blend = { 0.5, 0.3, 0.2 }
state.seq_layering_slot_id = 77

function frame()
  frame_begin()
  render_seq_layering_window()
  MOUSE.clicked, MOUSE.rclicked, MOUSE.dbl, MOUSE.dx, MOUSE.dy = false, false, false, 0, 0
end

function frame_picker()
  frame_begin()
  render_seq_minimap_popup()
  MOUSE.clicked, MOUSE.rclicked, MOUSE.dbl, MOUSE.dx, MOUSE.dy = false, false, false, 0, 0
end

-- Control row of a bottom corner: x, y of the row and the type chip width.
function corner_row(side_key, i)
  local ax, ay, bx, by, cx, cy = table.unpack(tri(side_key))
  local vx, vy = (i == 2) and bx or cx, (i == 2) and by or cy
  local col_w = seq_layering_col_w(776)
  local card_x = 52 + (side_key == "sustain" and (col_w + SEQ_LAYER_LINK_W) or 0)
  local label = seq_layering_rand_label(SLOT, side_key, i)
  local text = seq_truncate_text_to_width and seq_truncate_text_to_width(label, 74) or label
  local type_w = math.min(96, #text * 7 + 22)
  local row_w = 18 * 4 + 3 * 4 + type_w
  local row_x = math.max(card_x + 8.0, math.min(card_x + col_w - 8.0 - row_w, vx - row_w * 0.5))
  return row_x, vy + 26.0 + 13.0, type_w
end

-- Triangle corners of a side, as laid out this frame.
function tri(side_key)
  local avail = 776
  local col_w = seq_layering_col_w(avail)
  local x = 52 + (side_key == "sustain" and (col_w + SEQ_LAYER_LINK_W) or 0)
  local y = 50 + SEQ_LAYER_HEADER_H + 8.0 + SEQ_LAYER_WAVE_H
  local ax, ay, bx, by, cx, cy = seq_layering_tri_geom(x, y, col_w, seq_layering_card_h(col_w))
  return { ax, ay, bx, by, cx, cy }
end
'''


def _runtime(arrays=False):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    L.execute(STUB)
    g.ARRAYS = arrays
    return L


def test_bias_for_trans_inverts_apply_bias():
    L = _runtime()
    worst = L.execute(r'''
      local worst = 0
      for _, base in ipairs({ 0.006, 0.02, 0.03, 0.08 }) do
        for _, dur in ipairs({ 0.1, 0.5, 2.0 }) do
          for k = -10, 10 do
            local bias = k / 10
            local t = seq_layering_apply_bias(base, 0.002, dur, bias)
            local back = seq_layering_bias_for_trans(base, 0.002, dur, t)
            local again = seq_layering_apply_bias(base, 0.002, dur, back)
            worst = math.max(worst, math.abs(again - t))
          end
        end
      end
      return worst
    ''')
    assert worst < 1e-9


def test_split_time_round_trip_through_bias():
    L = _runtime()
    got = L.execute(r'''
      seq_layering_set_split_time(SLOT, 0.05)
      local t1 = seq_layering_split_time(SLOT)
      seq_layering_set_split_time(SLOT, 0.0)  -- clamps to the shortest transient
      local t2 = seq_layering_split_time(SLOT)
      return t1, t2, SLOT.layers.bias
    ''')
    assert abs(got[0] - 0.05) < 1e-6
    assert got[1] < 0.01 and got[2] == -1.0


def test_normalize_keeps_tables_and_clamps():
    L = _runtime()
    same, a, b, c = L.execute(r'''
      local blend = SLOT.layers.transient.blend
      blend[1], blend[2], blend[3] = 2, -1, 2
      seq_normalize_slot_layers(SLOT)
      local b = SLOT.layers.transient.blend
      return b == blend, b[1], b[2], b[3]
    ''')
    assert same and abs(a - 0.5) < 1e-9 and b == 0 and abs(c - 0.5) < 1e-9


def test_side_helpers():
    L = _runtime()
    out = L.execute(r'''
      local t = SLOT.layers.transient
      local r = {}
      seq_layering_solo_vert(SLOT, "transient", 3)
      r.solo = string.format("%.2f %.2f %.2f", t.blend[1], t.blend[2], t.blend[3])
      seq_layering_even_mix(SLOT, "transient")
      r.even = string.format("%.3f %.3f %.3f", t.blend[1], t.blend[2], t.blend[3])
      -- Sustain has an empty right corner: even mix skips it.
      seq_layering_even_mix(SLOT, "sustain")
      local s = SLOT.layers.sustain
      r.even_sus = string.format("%.2f %.2f %.2f", s.blend[1], s.blend[2], s.blend[3])
      r.cleared = seq_layering_clear_vert(SLOT, "transient", 2)
      r.clear_path = tostring(t.verts[2].path)
      r.clear_top = seq_layering_clear_vert(SLOT, "transient", 1)
      r.blend_sum = t.blend[1] + t.blend[2] + t.blend[3]
      t.verts[3].vol = 2.0
      seq_layering_reset_side(SLOT, "transient")
      r.reset = string.format("%.1f %.1f %.1f %.1f", t.blend[1], t.blend[2], t.blend[3], t.verts[3].vol)
      seq_layering_copy_side_to_other(SLOT, "transient")
      r.copied = tostring(SLOT.layers.sustain.verts[3].path)
      SLOT.layers.sustain.verts[2].path = "/s/other.wav"
      seq_layering_swap_sides(SLOT)
      r.swapped = tostring(SLOT.layers.transient.verts[2].path)
      return r
    ''')
    assert out.solo == "0.00 0.00 1.00"
    assert out.even == "0.333 0.333 0.333"
    assert out.even_sus == "0.50 0.50 0.00"
    assert out.cleared is True and out.clear_path == "nil" and out.clear_top is False
    assert abs(out.blend_sum - 1.0) < 1e-9
    assert out.reset == "1.0 0.0 0.0 1.0"
    assert out.copied == "/s/sub.wav"
    assert out.swapped == "/s/other.wav"


def test_snap_point():
    L = _runtime()
    got = L.execute(r'''
      local ax, ay, bx, by, cx, cy = 100, 0, 0, 173.2, 200, 173.2
      local mx, my = (ax + bx + cx) / 3, (ay + by + cy) / 3
      local x1, y1, t1 = seq_layering_snap_point(mx + 3, my - 2, ax, ay, bx, by, cx, cy, 7)
      local x2, y2, t2 = seq_layering_snap_point(mx + 30, my, ax, ay, bx, by, cx, cy, 7)
      local x3, y3 = seq_layering_snap_point(103, 4, ax, ay, bx, by, cx, cy, 7)
      return x1 - mx, y1 - my, t2 == nil, x2 - (mx + 30), x3, y3
    ''')
    assert abs(got[0]) < 1e-9 and abs(got[1]) < 1e-9
    assert got[2] is True and got[3] == 0
    assert got[4] == 100 and got[5] == 0


def test_mix_peaks_ribbon_names_dominant_corner():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.linked = true
      seq_layering_sync_linked(SLOT, "transient")
      local peaks, dur, ribbon = seq_layering_mix_peaks(SLOT, 200)
      local p2 = seq_layering_mix_peaks(SLOT, 200)
      local colors = {}
      for _, s in ipairs({ A, B, C }) do colors[get_sample_dot_color(s)] = s.path end
      local first, last = ribbon[1], ribbon[#ribbon]
      local max = 0
      for i = 1, #peaks do max = math.max(max, peaks[i]) end
      return #peaks, p2 == peaks, colors[first.color] ~= nil, first.u0, last.u1, max
    ''')
    n, cached, known_color, u0, u1, peak = got
    assert n == 200 and cached and known_color
    assert u0 == 0 and abs(u1 - 1.0) < 1e-9
    assert abs(peak - 1.0) < 1e-9


def _render_ok(L, frames=3):
    for _ in range(frames):
        L.execute("frame()")
    logs = list(L.globals().LOGS.values())
    assert not [m for m in logs if "error" in m.lower() or "failed" in m.lower()], logs


def test_window_renders_with_and_without_arrays():
    for arrays in (False, True):
        L = _runtime(arrays)
        _render_ok(L)
        # Hover each card, the panes and the header.
        for x, y in ((150, 380), (600, 380), (300, 110), (300, 170), (300, 60), (440, 330)):
            L.execute(f"MOUSE.x, MOUSE.y = {x}, {y}")
            _render_ok(L, 2)
        L.execute("seq_layering_set_linked(SLOT, true)")
        _render_ok(L, 2)


def test_draw_call_budget():
    # In REAPER reaper.new_array exists, so shapes go out as cached polylines.
    L = _runtime(True)
    _render_ok(L, 2)
    per_frame = L.execute(r'''
      CALLS = 0
      for i = 1, 10 do frame() end
      return CALLS / 10
    ''')
    # The previous window issued ~1800 calls a frame in this setup.
    assert per_frame < 800, per_frame


def test_blend_drag_snaps_and_commits():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local t = tri("transient")
      local ax, ay, bx, by, cx, cy = table.unpack(t)
      local mx, my = (ax + bx + cx) / 3, (ay + by + cy) / 3
      MOUSE.x, MOUSE.y = mx + 2, my + 3
      frame()  -- hover
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      local b = SLOT.layers.transient.blend
      local snapped = string.format("%.3f %.3f %.3f", b[1], b[2], b[3])
      local saves0 = SAVES
      -- Drag toward the bottom-left corner.
      MOUSE.x, MOUSE.y = bx + 20, by - 8
      frame()
      local mid = SLOT.layers.transient.blend[2]
      MOUSE.down = false
      frame()
      return snapped, mid, SAVES > saves0, state.seq_layering_drag == nil
    ''')
    snapped, mid, saved, released = got
    assert snapped == "0.333 0.333 0.333"
    assert mid > 0.7
    assert saved and released


def test_double_click_corner_solos_it():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local ax, ay, bx, by, cx, cy = table.unpack(tri("transient"))
      MOUSE.x, MOUSE.y = cx, cy
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.down = false
      frame()
      local previewed = PREVIEWS[#PREVIEWS]
      MOUSE.down, MOUSE.clicked, MOUSE.dbl = true, true, true
      frame()
      MOUSE.down = false
      frame()
      local b = SLOT.layers.transient.blend
      return previewed, string.format("%.1f %.1f %.1f", b[1], b[2], b[3])
    ''')
    assert got[0] == "/s/sub.wav"
    assert got[1] == "0.0 0.0 1.0"


def test_split_handle_drag_sets_bias():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      -- Original pane inner rect.
      local x, y, w = 52, 50 + SEQ_LAYER_HEADER_H + 8.0, 776
      local ix, iy, iw = x + 10, y + 22, w - 20
      local split_t = seq_layering_split_time(SLOT)
      local sx = ix + split_t / 0.5 * iw
      MOUSE.x, MOUSE.y = sx, iy + 10
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.x = ix + 0.1 / 0.5 * iw  -- drag to 100 ms
      frame()
      local during = seq_layering_split_time(SLOT)
      local syncs0 = SYNCS
      MOUSE.down = false
      frame()
      return split_t, during, SLOT.layers.bias, SYNCS > syncs0, state.seq_layering_bias_drag == nil
    ''')
    before, during, bias, synced, released = got
    assert abs(during - 0.1) < 0.003 and during > before
    assert bias > 0 and synced and released


def test_corner_menu_clear_and_side_menu_swap():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local ax, ay, bx, by = table.unpack(tri("transient"))
      MOUSE.x, MOUSE.y = bx, by
      frame()
      MOUSE.rclicked = true
      frame()
      local opened = popup_is_open("##seq_layer_vert_menu")
      set_menu_pick("Clear")
      frame()
      set_menu_pick(nil)
      close_popups()
      local cleared = SLOT.layers.transient.verts[2].path == nil
      -- Right-click inside the sustain triangle opens the side menu.
      local sax, say, sbx, sby, scx, scy = table.unpack(tri("sustain"))
      MOUSE.x, MOUSE.y = (sax + sbx + scx) / 3, (say + sby + scy) / 3
      frame()
      MOUSE.rclicked = true
      frame()
      local side_open = popup_is_open("##seq_layer_side_menu")
      set_menu_pick("Swap transient")
      frame()
      set_menu_pick(nil)
      return opened, cleared, side_open, SLOT.layers.sustain.verts[3].path
    ''')
    opened, cleared, side_open, swapped_path = got
    assert opened and cleared and side_open
    assert swapped_path == "/s/sub.wav"


def test_auto_audition_plays_mix_after_edit():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local played = 0
      seq_layering_preview_layered = function() played = played + 1 end
      seq_layering_set_auto_audition(true)
      seq_layering_commit(SLOT)
      seq_layering_set_auto_audition(false)
      seq_layering_commit(SLOT)
      return played, EXT["SampleMapBrowser/layering_auto_audition"]
    ''')
    assert got[0] == 1 and got[1] == "0"


def test_close_button_and_header_drag_move():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      -- Drag on empty header space moves the window.
      MOUSE.x, MOUSE.y = 260, 60
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.dx, MOUSE.dy = 15, 7
      frame()
      local mv = state.seq_layering_move
      MOUSE.down = false
      frame()
      -- Close button (top right).
      MOUSE.x, MOUSE.y = 52 + 776 - 10, 50 + 13
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.down = false
      frame()
      return mv and mv.x, mv and mv.y, state.seq_layering_slot_id
    ''')
    assert got[0] == 55 and got[1] == 47
    assert got[2] is None


def test_shift_drag_moves_point_slowly_without_snapping():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local ax, ay, bx, by, cx, cy = table.unpack(tri("transient"))
      local mx, my = (ax + bx + cx) / 3, (ay + by + cy) / 3
      MOUSE.x, MOUSE.y = mx + 1, my
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      local px0, py0 = seq_layer_point_from_bary(SLOT.layers.transient.blend, ax, ay, bx, by, cx, cy)
      MOUSE.shift = true
      MOUSE.x, MOUSE.dx = mx + 41, 40
      frame()
      local px1 = seq_layer_point_from_bary(SLOT.layers.transient.blend, ax, ay, bx, by, cx, cy)
      MOUSE.shift, MOUSE.down = false, false
      frame()
      return px1 - px0
    ''')
    assert abs(got - 40 * 0.25) < 1e-6


def test_corner_drag_out_starts_a_sample_drag():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local ax, ay, bx, by, cx, cy = table.unpack(tri("transient"))
      MOUSE.x, MOUSE.y = cx, cy
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.x, MOUSE.dx = cx + 12, 12
      frame()
      local drop = state.pending_waveform_drop
      MOUSE.down = false
      state.pending_waveform_drop = nil
      frame()
      return drop and drop.path, SLOT.layers.transient.blend[3]
    ''')
    assert got[0] == "/s/sub.wav"
    # Pressing a corner never starts a blend drag.
    assert abs(got[1] - 0.2) < 1e-9


def test_crossfade_window_is_centred_on_the_split():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.transient.blend = { 1.0, 0.0, 0.0 }
      SLOT.layers.sustain.verts[1].path = C.path  -- different top sample per side
      SLOT.layers.sustain.blend = { 1.0, 0.0, 0.0 }
      seq_layering_set_xfade(SLOT, 0.02)
      local split = seq_layering_split_sec(SLOT)
      local pieces = seq_layering_build_pieces(SLOT)
      local t, s
      for _, p in ipairs(pieces) do
        if p.time_offset_sec == 0 then t = p else s = p end
      end
      local clamp_lo = seq_layering_set_xfade(SLOT, 0) and SLOT.layers.xfade
      local clamp_hi = seq_layering_set_xfade(SLOT, 9) and SLOT.layers.xfade
      return split, t.length_sec, t.fade_out, s.time_offset_sec, s.fade_in, clamp_lo, clamp_hi
    ''')
    split, t_len, t_out, s_off, s_in, lo, hi = got
    assert abs(t_len - (split + 0.01)) < 1e-9 and abs(t_out - 0.02) < 1e-9
    assert abs(s_off - (split - 0.01)) < 1e-9 and abs(s_in - 0.02) < 1e-9
    assert lo == 0.001 and hi == 0.25


def test_crossfade_changes_the_mix_peaks_and_persists_in_copies():
    L = _runtime()
    got = L.execute(r'''
      local p1 = seq_layering_mix_peaks(SLOT, 200)
      seq_layering_set_xfade(SLOT, 0.12)
      local p2 = seq_layering_mix_peaks(SLOT, 200)
      local other = { id = 78, sample_path = A.path }
      seq_layering_copy_to_slot(other, SLOT)
      return p1 ~= p2, other.layers.xfade
    ''')
    assert got[0] is True and abs(got[1] - 0.12) < 1e-9


def test_layered_hit_lasts_until_the_longest_piece_ends():
    L = _runtime()
    got = L.execute(r'''
      local long = mk_sample("/s/tail.wav", 300, "kick")
      long.duration = 1.4
      rebuild_samples_path_index()
      SLOT.layers.sustain.verts[2].path = long.path
      SLOT.layers.sustain.blend = { 0.5, 0.5, 0.0 }
      SLOT.layers.output = "layered"
      return seq_layering_mix_duration(SLOT), A.duration
    ''')
    mix, track = got
    # The 1.4 s sustain plays out instead of stopping with the 0.5 s track sample.
    assert mix > 1.3 and track == 0.5


def test_player_layers_carry_split_blend_and_fades():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.output = "layered"
      seq_layering_set_xfade(SLOT, 0.03)
      local layers = seq_player_collect_layers(SLOT)
      local pieces = seq_layering_build_pieces(SLOT)
      local sus = nil
      for _, l in ipairs(layers) do if l.delay > 0 then sus = l end end
      return #layers, #pieces, sus and sus.fade_in, layers[1].vol
    ''')
    n, npieces, fade_in, vol = got
    assert n == npieces and n > 1
    assert fade_in and fade_in > 0.02
    assert vol < 1.0  # blend weight, not the corner's raw volume



def _pane_geom(L, kind):
    return L.execute(f'''
      local x, y, w = 52, 50 + SEQ_LAYER_HEADER_H + 8.0, 776
      if "{kind}" == "layered" then y = y + SEQ_LAYER_PANE_H + SEQ_LAYER_WAVE_GAP end
      return x + 10, y + 22, w - 20, SEQ_LAYER_PANE_H - 28
    ''')


def test_split_drags_in_the_layered_pane_too():
    L = _runtime()
    _render_ok(L, 1)
    ix, iy, iw, ih = _pane_geom(L, "layered")
    got = L.execute(f'''
      local _, dur = seq_layering_mix_peaks(SLOT, math.floor({iw}))
      local onset = seq_layering_trans_base(A)
      local split_t = seq_layering_split_time(SLOT)
      local sx = {ix} + (split_t - onset) / dur * {iw}
      MOUSE.x, MOUSE.y = sx, {iy} + 5
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.x = {ix} + (0.08 - onset) / dur * {iw}
      frame()
      local during = seq_layering_split_time(SLOT)
      local syncs0 = SYNCS
      MOUSE.down = false
      frame()
      return split_t, during, SYNCS > syncs0
    ''')
    before, during, synced = got
    assert during > before and abs(during - 0.08) < 0.01
    assert synced


def test_crossfade_handle_drag_sets_the_fade():
    L = _runtime()
    _render_ok(L, 1)
    ix, iy, iw, ih = _pane_geom(L, "original")
    got = L.execute(f'''
      local split_t = seq_layering_split_time(SLOT)
      local _, post = seq_layering_xfade_window(SLOT)
      local xb = {ix} + (split_t + post) / 0.5 * {iw}
      local sx = {ix} + split_t / 0.5 * {iw}
      local fx = math.max(xb, sx + 9.0)
      MOUSE.x, MOUSE.y = fx, {iy} + {ih} - 4
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.x = {ix} + (split_t + 0.03) / 0.5 * {iw}
      frame()
      local during = SLOT.layers.xfade
      local syncs0 = SYNCS
      MOUSE.down = false
      frame()
      return during, SYNCS > syncs0, math.abs(seq_layering_split_time(SLOT) - split_t) < 1e-9
    ''')
    xf, synced, split_kept = got
    assert abs(xf - 0.06) < 0.003
    assert synced and split_kept


def test_xfade_pill_drag_and_reset():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local col_w = seq_layering_col_w(776)
      local y = 50 + SEQ_LAYER_HEADER_H + 8.0 + SEQ_LAYER_WAVE_H
      local card_h = seq_layering_card_h(col_w)
      local link_sz, bias_h = 30.0, 16.0
      local cluster_h = link_sz + 22.0 + (bias_h + 40.0) * 2.0
      local link_y = y + math.max(8.0, (card_h - cluster_h) * 0.5)
      local px = 52 + col_w + (SEQ_LAYER_LINK_W - 62.0) * 0.5
      local py = link_y + link_sz + 26.0 + bias_h + 40.0
      MOUSE.x, MOUSE.y = px + 31, py + 8
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.dx = 40
      frame()
      local longer = SLOT.layers.xfade
      MOUSE.down = false
      frame()
      MOUSE.down, MOUSE.clicked, MOUSE.dbl = true, true, true
      frame()
      MOUSE.down = false
      frame()
      return longer, SLOT.layers.xfade
    ''')
    assert got[0] > 0.02
    assert abs(got[1] - 0.008) < 1e-9



def test_each_corner_draws_from_its_own_type_and_tags():
    L = _runtime()
    got = L.execute(r'''
      local s1 = mk_sample("/s/snare_dry.wav", 20, "snare"); s1.tags = { "snare", "dry" }
      local s2 = mk_sample("/s/snare_wet.wav", 20, "snare"); s2.tags = { "snare", "wet" }
      local s3 = mk_sample("/s/snare_dry2.wav", 20, "snare"); s3.tags = { "snare", "dry", "tight" }
      for _, s in ipairs({ s1, s2, s3 }) do s.x, s.y = 0.5, 0.5 end
      rebuild_samples_path_index()
      state.tag_index_epoch = (state.tag_index_epoch or 0) + 1
      local idx = seq_layering_role_index()
      local tag_names = {}
      for _, t in ipairs(idx.tags.snare or {}) do tag_names[#tag_names + 1] = t.tag end
      seq_layering_set_rand_role(SLOT, "sustain", 3, "snare")
      seq_layering_toggle_rand_tag(SLOT, "sustain", 3, "dry")
      local pool = seq_layering_corner_samples(SLOT, "sustain", 3)
      local picks, bad = {}, false
      for i = 1, 12 do
        seq_layering_randomize_vert(SLOT, "sustain", 3)
        local p = SLOT.layers.sustain.verts[3].path
        if p ~= s1.path and p ~= s3.path then bad = p end
      end
      local label, own = seq_layering_rand_label(SLOT, "sustain", 3)
      local other_label, other_own = seq_layering_rand_label(SLOT, "sustain", 2)
      -- Changing the type drops the old type's tags; the track's own type clears it.
      seq_layering_set_rand_role(SLOT, "sustain", 3, "808")
      local tags_after = #SLOT.layers.sustain.verts[3].rand.tags
      seq_layering_set_rand_role(SLOT, "sustain", 3, "kick")
      return table.concat(tag_names, ","), #pool, bad, label, own, other_label, other_own,
        tags_after, SLOT.layers.sustain.verts[3].rand == nil
    ''')
    tags, pool_n, bad, label, own, other_label, other_own, tags_after, cleared = got
    assert "dry" in tags.split(",") and "snare" not in tags.split(",")
    assert pool_n == 2 and bad is False
    assert label == "Snare · dry" and own is True
    assert other_label == "Kick" and other_own is False
    assert tags_after == 0 and cleared


def test_side_filter_from_older_layouts_moves_to_corners():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.transient.rand = { role = "snare", tags = { "dry" } }
      seq_normalize_slot_layers(SLOT)
      local t = SLOT.layers.transient
      return t.rand == nil, t.verts[2].rand.role, t.verts[3].rand.tags[1], t.verts[1].rand == nil
    ''')
    assert got[0] and got[1] == "snare" and got[2] == "dry" and got[3]


def test_type_chip_and_dice_right_click_open_the_corner_picker():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local row_x, row_y, type_w = corner_row("sustain", 3)
      MOUSE.x, MOUSE.y = row_x + 2 * 21 + type_w * 0.5, row_y + 9
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.down = false
      frame()
      local pop = state.seq_minimap_popup
      local first = pop and (pop.mode .. ":" .. pop.layer.side .. ":" .. pop.layer.idx)
      -- Right-click the transient left corner's dice: the picker moves there.
      local trow_x, trow_y = corner_row("transient", 2)
      MOUSE.x, MOUSE.y = trow_x + 9, trow_y + 9
      frame()
      MOUSE.rclicked = true
      frame()
      pop = state.seq_minimap_popup
      local second = pop and (pop.layer.side .. ":" .. pop.layer.idx)
      -- Clicking the transient chip again closes it.
      local _, _, ttype_w = corner_row("transient", 2)
      MOUSE.x = trow_x + 2 * 21 + ttype_w * 0.5
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.down = false
      frame()
      return first, second, state.seq_minimap_popup == nil
    ''')
    assert got[0] == "layer:sustain:3"
    assert got[1] == "transient:2"
    assert got[2] is True


def test_picker_tags_type_roll_and_map_pick():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local s1 = mk_sample("/s/kick_dry.wav", 20, "kick"); s1.tags = { "kick", "dry" }; s1.x, s1.y = 0.5, 0.5
      local s2 = mk_sample("/s/kick_wet.wav", 20, "kick"); s2.tags = { "kick", "wet" }; s2.x, s2.y = 0.52, 0.5
      for _, s in ipairs(state.samples) do s.x = s.x or 0.4; s.y = s.y or 0.4 end
      rebuild_samples_path_index()
      state.tag_index_epoch = (state.tag_index_epoch or 0) + 1
      seq_layering_open_vert_chooser(SLOT, "sustain", 3)
      frame_picker()
      local pop = state.seq_minimap_popup
      local n_all = #pop.samples
      -- Picker window at (40, 40) in the stub; content starts 8 px in.
      local x, y = 48, 48
      local chip_y = y + 24 + 8
      -- Tag chips are the role's tags, most common first: click the first.
      MOUSE.x, MOUSE.y = x + 5, chip_y + 9
      frame_picker()
      MOUSE.down, MOUSE.clicked = true, true
      frame_picker()
      MOUSE.down = false
      frame_picker()
      local rand = SLOT.layers.sustain.verts[3].rand
      local tag = rand and rand.tags[1]
      local n_tag = #state.seq_minimap_popup.samples
      -- Roll picks from what the map shows.
      MOUSE.x, MOUSE.y = x + 20, y + 10
      frame_picker()
      MOUSE.down, MOUSE.clicked = true, true
      frame_picker()
      MOUSE.down = false
      frame_picker()
      local rolled = SLOT.layers.sustain.verts[3].path
      -- Type menu: open and pick 808 (the stub's MenuItem picks by label).
      MOUSE.x, MOUSE.y = x + 22 + 42 + 10, y + 10
      frame_picker()
      MOUSE.down, MOUSE.clicked = true, true
      set_menu_pick("808")
      frame_picker()
      MOUSE.down = false
      set_menu_pick(nil)
      close_popups()
      local role = SLOT.layers.sustain.verts[3].rand and SLOT.layers.sustain.verts[3].rand.role
      -- A map click (via the map's assign path) sets the corner.
      seq_minimap_assign(SLOT, C)
      return n_all, tag, n_tag, rolled, role, SLOT.layers.sustain.verts[3].path, state.seq_minimap_popup.hint
    ''')
    n_all, tag, n_tag, rolled, role, picked, _ = got
    assert n_all >= 4
    assert tag in ("dry", "wet") and n_tag == 1
    assert rolled in ("/s/kick_dry.wav", "/s/kick_wet.wav")
    assert role == "808"
    assert picked == "/s/sub.wav"


def test_picker_sits_beside_the_window():
    L = _runtime()
    got = L.execute(r'''
      state.seq_layering_rect = { x = 300, y = 100, w = 800, h = 600 }
      state.seq_layering_vert_hits = { { side = "sustain", idx = 3, x = 900, y = 500 },
                                        { side = "transient", idx = 2, x = 400, y = 500 } }
      state.main_window_rect = { x = 0, y = 0, w = 1600, h = 1000 }
      local rx, ry = seq_layering_picker_pos({ layer = { side = "sustain", idx = 3 } }, 264, 380)
      local lx = seq_layering_picker_pos({ layer = { side = "transient", idx = 2 } }, 264, 380)
      -- Too narrow for either side: below the window.
      state.main_window_rect = { x = 250, y = 0, w = 900, h = 1200 }
      local bx, by = seq_layering_picker_pos({ layer = { side = "sustain", idx = 3 } }, 264, 380)
      return rx, ry, lx, bx, by
    ''')
    rx, ry, lx, bx, by = got
    assert rx == 1110 and ry == 500 - 190
    assert lx == 300 - 264 - 10
    assert by == 710 and 250 <= bx <= 1150 - 264


def test_hints_go_to_the_bottom_bar_not_tooltips():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      TIPS = 0
      reaper.ImGui_SetTooltip = function() TIPS = TIPS + 1 end
      -- Knob of the sustain right corner.
      local row_x, row_y, type_w = corner_row("sustain", 3)
      local kx = row_x + 2 * 21 + type_w + 3 + 9
      MOUSE.x, MOUSE.y = kx, row_y + 9
      frame()
      local hover_hint = state.seq_layering_hint
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.dy = -20
      frame()
      local drag_hint = state.seq_layering_hint
      MOUSE.down = false
      frame()
      -- Hover every area of the window too.
      for _, p in ipairs({ { 150, 380 }, { 600, 380 }, { 300, 110 }, { 300, 170 }, { 300, 60 }, { 440, 330 } }) do
        MOUSE.x, MOUSE.y = p[1], p[2]
        frame()
      end
      MOUSE.x, MOUSE.y = -1000, -1000
      frame()
      return TIPS, hover_hint, drag_hint, SLOT.layers.sustain.verts[3].vol, state.seq_layering_hint
    ''')
    tips, hover_hint, drag_hint, vol, idle = got
    assert tips == 0
    assert hover_hint and "volume" in hover_hint
    assert drag_hint and "%" in drag_hint and "dB" in drag_hint
    assert vol > 1.0 and idle is None


def test_side_gain_scales_every_piece_of_that_side():
    L = _runtime()
    got = L.execute(r'''
      local function weights()
        local t, s = 0, 0
        for _, p in ipairs(seq_layering_build_pieces(SLOT)) do
          if p.time_offset_sec == 0 then t = t + p.weight else s = s + p.weight end
        end
        return t, s
      end
      local t0, s0 = weights()
      seq_layering_set_side_gain(SLOT, "sustain", 2.0)
      local t1, s1 = weights()
      local clamped = seq_layering_set_side_gain(SLOT, "transient", 100) and SLOT.layers.transient.gain
      -- Gain alone makes a plain track layered.
      local plain = { id = 90, sample_path = A.path, sample_name = A.name }
      seq_layering_seed_from_track(plain)
      local before = seq_layering_geometry_active(plain)
      seq_layering_set_side_gain(plain, "transient", 0.5)
      return t0, s0, t1, s1, clamped, before, seq_layering_geometry_active(plain)
    ''')
    t0, s0, t1, s1, clamped, before, after = got
    assert abs(t1 - t0) < 1e-9 and abs(s1 - 2 * s0) < 1e-9
    assert abs(clamped - 10 ** (12 / 20)) < 1e-6
    assert before is False and after is True


def test_link_keeps_the_sustain_and_unlink_brings_it_back():
    L = _runtime()
    got = L.execute(r'''
      local s = SLOT.layers.sustain
      s.verts[3].path = D.path
      s.verts[3].vol = 1.7
      s.blend = { 0.2, 0.3, 0.5 }
      seq_layering_set_linked(SLOT, true)
      local mirrored = s.verts[3].path == SLOT.layers.transient.verts[3].path
      -- Edit while linked (through either side).
      SLOT.layers.transient.verts[2].vol = 0.4
      seq_layering_sync_linked(SLOT, "transient")
      seq_layering_set_linked(SLOT, false)
      s = SLOT.layers.sustain
      return mirrored, s.verts[3].path, s.verts[3].vol, string.format("%.1f %.1f %.1f", s.blend[1], s.blend[2], s.blend[3]),
        s.verts[2].vol, SLOT.layers.transient.verts[2].vol, SLOT.layers.unlinked_sustain == nil
    ''')
    mirrored, path, vol, blend, s2vol, t2vol, stash_gone = got
    assert mirrored
    assert path == "/s/other.wav" and abs(vol - 1.7) < 1e-9 and blend == "0.2 0.3 0.5"
    assert s2vol == 1.0 and abs(t2vol - 0.4) < 1e-9 and stash_gone


def test_corner_length_and_fade_cut_its_pieces():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.sustain.blend = { 0.5, 0.5, 0.0 }
      local t0, t1 = seq_layering_corner_span(SLOT, "sustain", 2)
      seq_layering_set_corner_cut(SLOT, "sustain", 2, 0.2, 0.05)
      local cut = nil
      for _, p in ipairs(seq_layering_build_pieces(SLOT)) do
        if p.path == C.path and p.time_offset_sec > 0 then cut = p end
      end
      local _, _, _, t_off, len = seq_layering_piece_span(cut)
      -- Fade without a length: fades out before the natural end.
      seq_layering_set_corner_cut(SLOT, "sustain", 2, nil, 0.1)
      local faded
      for _, p in ipairs(seq_layering_build_pieces(SLOT)) do
        if p.path == C.path and p.time_offset_sec > 0 then faded = p end
      end
      return t1, t_off + len, cut.fade_out, faded.fade_out, SLOT.layers.sustain.verts[2].len
    ''')
    t1, end_t, fade, fade_only, length = got
    assert t1 > 0.4
    assert abs(end_t - 0.2) < 1e-9 and abs(fade - 0.05) < 1e-9
    assert abs(fade_only - 0.1) < 1e-9 and length is None


def test_tail_end_and_fade_apply_to_the_whole_hit():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.output = "layered"
      local natural = seq_layering_natural_end(SLOT)
      seq_layering_set_tail(SLOT, 0.25, 0.1)
      local latest, faded_ok = 0, true
      for _, p in ipairs(seq_layering_build_pieces(SLOT)) do
        local _, _, _, t_off, len = seq_layering_piece_span(p)
        latest = math.max(latest, t_off + len)
        if t_off + len > 0.15 + 1e-9 and (p.fade_out or 0) < (t_off + len) - math.max(t_off, 0.15) - 1e-9 then
          faded_ok = false
        end
      end
      local _, axis = seq_layering_mix_peaks(SLOT, 200)
      local hit = seq_layering_mix_duration(SLOT)
      -- Past the natural end means no cut.
      seq_layering_set_tail(SLOT, natural + 1, nil)
      return natural, latest, faded_ok, axis, hit, SLOT.layers.tail_end
    ''')
    natural, latest, faded_ok, axis, hit, cleared = got
    assert abs(latest - 0.25) < 1e-9 and faded_ok
    assert abs(axis - natural) < 1e-6 and abs(hit - 0.25) < 1e-9
    assert cleared is None


def test_tail_handle_drag_on_the_layered_pane():
    L = _runtime()
    _render_ok(L, 1)
    ix, iy, iw, ih = _pane_geom(L, "layered")
    got = L.execute(f'''
      local _, dur = seq_layering_mix_peaks(SLOT, math.floor({iw}))
      local ex = {ix} + {iw}  -- no tail yet: the end sits at the natural end
      MOUSE.x, MOUSE.y = ex, {iy} + {ih} * 0.7
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.x = {ix} + 0.3 / dur * {iw}
      frame()
      local during = SLOT.layers.tail_end
      local syncs0 = SYNCS
      MOUSE.down = false
      frame()
      -- Fade grip sits on top at the end: drag it 80 ms left.
      local ex2 = {ix} + 0.3 / dur * {iw}
      MOUSE.x, MOUSE.y = ex2 - 7, {iy} + 2
      frame()
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.x = {ix} + 0.22 / dur * {iw}
      frame()
      MOUSE.down = false
      frame()
      return during, SYNCS > syncs0, SLOT.layers.tail_fade
    ''')
    end_t, synced, fade = got
    assert abs(end_t - 0.3) < 0.01 and synced
    assert fade and abs(fade - 0.08) < 0.01


def test_gain_fader_drag_in_the_card_header():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local col_w = seq_layering_col_w(776)
      local x, y = 52, 50 + SEQ_LAYER_HEADER_H + 8.0 + SEQ_LAYER_WAVE_H
      local bx = x + col_w - 8.0 - 20.0 - 2 * 24.0  -- dice
      local bar_x1 = bx - 10.0
      MOUSE.x, MOUSE.y = bar_x1 - 20, y + SEQ_LAYER_CARD_HEAD_H * 0.5
      frame()
      local hint = state.seq_layering_hint
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.dx = 40
      frame()
      local g = SLOT.layers.transient.gain
      MOUSE.down = false
      frame()
      return hint, g, SLOT.layers.transient.blend[1]
    ''')
    hint, g, b1 = got
    assert hint and "Gain" in hint
    assert g > 1.5
    assert abs(b1 - 0.5) < 1e-9  # the blend point didn't move



def _fake_render(L):
    os.makedirs(os.path.join(L.globals().RES, "lib", "Layered Renders"), exist_ok=True)
    L.execute(r'''
      RENDERS = {}
      seq_layering_render_mix = function(slot, path)
        RENDERS[#RENDERS + 1] = path
        return seq_layering_write_wav(path, 48000, 2, { { 0.1, -0.1, 0.2, -0.2 } })
      end
      SCANS = {}
      start_scan = function(folder) SCANS[#SCANS + 1] = folder end
      enqueue_scan = start_scan
      reaper.PCM_Source_CreateFromFile = function() return {} end
      reaper.GetMediaSourceLength = function() return 0.6, false end
      LAYOUTS = 0
      layout_samples = function() LAYOUTS = LAYOUTS + 1 end
      state.folders = { RES .. "/lib" }
    ''')


def test_wav_writer_writes_a_float_wav():
    L = _runtime()
    path = os.path.join(L.globals().RES, "t.wav")
    L.execute(f'return seq_layering_write_wav([[{path}]], 44100, 2, {{ {{ 0.5, -0.5, 1.5, 0 }}, {{ 0.25, 0.25 }} }})')
    import struct
    data = open(path, "rb").read()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE"
    fmt, ch, sr = struct.unpack("<HHI", data[20:28])
    assert (fmt, ch, sr) == (3, 2, 44100)
    i = data.index(b"data")
    size = struct.unpack("<I", data[i + 4:i + 8])[0]
    assert size == 6 * 4 and len(data) == i + 8 + size
    assert struct.unpack("<6f", data[i + 8:])[2] == 1.5
    assert struct.unpack("<I", data[4:8])[0] == len(data) - 8


def test_render_mix_reads_the_temp_track_and_removes_it():
    L = _runtime()
    path = os.path.join(L.globals().RES, "r.wav")
    got = L.execute(f'''
      local tracks, deleted = 0, 0
      reaper.CountTracks = function() return tracks end
      reaper.InsertTrackAtIndex = function() tracks = tracks + 1 end
      reaper.GetTrack = function() return {{ fake = true }} end
      reaper.DeleteTrack = function() deleted = deleted + 1; tracks = tracks - 1 end
      seq_layering_insert_mix_at_position = function(s, pos, tr) return tr and tr.fake end
      reaper.CreateTrackAudioAccessor = function() return {{}} end
      reaper.DestroyAudioAccessor = function() end
      reaper.GetSetProjectInfo = function() return 44100 end
      reaper.new_array = function(n)
        local a = {{ data = {{}} }}
        a.clear = function() a.data = {{}} end
        a.table = function(o, sz) local t = {{}} for i = 1, sz do t[i] = a.data[i] or 0 end return t end
        return a
      end
      reaper.GetAudioAccessorSamples = function(acc, sr, ch, t, n, buf)
        for i = 1, n * ch do buf.data[i] = 0.25 end
        return 1
      end
      SLOT.layers.output = "layered"
      local ok, err = seq_layering_render_mix(SLOT, [[{path}]])
      return ok, err, deleted, tracks, seq_layering_mix_duration(SLOT)
    ''')
    ok, err, deleted, tracks, dur = got
    assert ok is True and err is None and deleted == 1 and tracks == 0
    import struct
    data = open(path, "rb").read()
    i = data.index(b"data")
    frames = struct.unpack("<I", data[i + 4:i + 8])[0] // 8
    assert frames == round((dur + 0.005) * 44100)
    assert struct.unpack("<f", data[i + 8:i + 12])[0] == 0.25


def test_commit_glues_starts_a_fresh_stack_and_keeps_versions():
    L = _runtime()
    _fake_render(L)
    got = L.execute(r'''
      local folder = seq_layering_render_folder()
      local entry = seq_layering_commit_glue(SLOT)
      local first = {
        folder = folder, scans = #SCANS, file_ok = io.open(entry.path, "rb") ~= nil,
        track = SLOT.sample_path, fresh = not seq_layering_geometry_active(SLOT),
        top = SLOT.layers.transient.verts[1].path, stack_b = entry.stack.layers.transient.verts[2].path,
        stack_sample = entry.stack.sample_path,
      }
      -- Nothing to glue on a fresh stack.
      local again, why = seq_layering_commit_glue(SLOT)
      -- Tweak and commit again.
      SLOT.layers.sustain.verts[2].path = D.path
      SLOT.layers.sustain.blend = { 0.5, 0.5, 0.0 }
      local entry2 = seq_layering_commit_glue(SLOT)
      local v = SLOT.layer_versions
      -- Back to glue 1, then to the stack glue 1 was made from.
      seq_layering_use_version(SLOT, 1)
      local on_g1 = SLOT.sample_path == entry.path and v.current == 1
      seq_layering_use_version(SLOT, 1, true)
      local t = SLOT.layers.transient
      return first, again == nil and why ~= nil, #v.glues, entry2.stack.sample_path == entry.path, on_g1,
        SLOT.sample_path, t.verts[2].path, t.verts[3].path, v.current
    ''')
    first, refused, n, chained, on_g1, sample, b, c, cur = got
    assert first.folder.endswith("/lib/Layered Renders")
    assert first.scans == 0 and first.file_ok
    assert first.track.startswith(first.folder) and first.top == first.track and first.fresh
    assert first.stack_b == "/s/click.wav" and first.stack_sample == "/s/kick.wav"
    assert refused and n == 2 and chained and on_g1
    assert sample == "/s/kick.wav" and b == "/s/click.wav" and c == "/s/sub.wav"
    assert cur == "stack:1"


def test_commit_is_one_undo_step():
    L = _runtime()
    _fake_render(L)
    _render_ok(L, 1)
    got = L.execute(r'''
      local before = SLOT.sample_path
      seq_layering_do_commit(SLOT)
      local after = find_seq_track_by_id(77).sample_path
      seq_undo()
      local slot = find_seq_track_by_id(77)
      return before, after, slot.sample_path, slot.layers.transient.verts[2].path,
        slot.layer_versions == nil or #slot.layer_versions.glues == 0
    ''')
    before, after, undone, b, no_versions = got
    assert after != before and after.endswith(".wav")
    assert undone == before and b == "/s/click.wav" and no_versions


def test_versions_menu_switches_versions():
    L = _runtime()
    _fake_render(L)
    _render_ok(L, 1)
    got = L.execute(r'''
      local e = seq_layering_commit_glue(SLOT)
      frame()
      reaper.ImGui_OpenPopup(ctx, "##seq_layer_versions_menu")
      set_menu_pick("Stack before Glue 1")
      frame()
      set_menu_pick(nil)
      close_popups()
      local unglued = SLOT.sample_path
      reaper.ImGui_OpenPopup(ctx, "##seq_layer_versions_menu")
      set_menu_pick("Glue 1")
      frame()
      set_menu_pick(nil)
      return unglued, SLOT.sample_path == e.path, SLOT.layer_versions.current
    ''')
    assert got[0] == "/s/kick.wav" and got[1] is True and got[2] == 1
    _render_ok(L, 2)


def test_render_folder_setting():
    L = _runtime()
    got = L.execute(r'''
      state.folders = { "/lib/drums/" }
      local d = seq_layering_render_folder()
      seq_layering_set_render_folder("/elsewhere/glues")
      local custom = seq_layering_render_folder()
      settings_render_drum_layering()
      seq_layering_set_render_folder(nil)
      return d, custom, seq_layering_render_folder()
    ''')
    assert got[0] == "/lib/drums/Layered Renders"
    assert got[1] == "/elsewhere/glues"
    assert got[2] == "/lib/drums/Layered Renders"



def test_glue_joins_the_library_quietly():
    L = _runtime()
    _fake_render(L)
    got = L.execute(r'''
      A.x, A.y = 0.3, 0.6
      local n0 = #state.samples
      local entry = seq_layering_commit_glue(SLOT)
      local s = find_sample_by_path(entry.path)
      local has_kick = false
      for _, t in ipairs(s and s.tags or {}) do if t == "kick" then has_kick = true end end
      local queued = false
      for _, p in ipairs(state.analyzer_queue) do if p == s.path then queued = true end end
      local pending = sm_quiet_analysis_pending()
      -- A worker takes the job off the queue, then its result lands.
      for i = #state.analyzer_queue, 1, -1 do
        if state.analyzer_queue[i] == s.path then table.remove(state.analyzer_queue, i) end
      end
      sm_quiet_analysis_landed(s.path)
      return #state.samples - n0, has_kick, math.abs(s.x - 0.3) < 0.01 and math.abs(s.y - 0.6) < 0.01,
        queued, pending, LAYOUTS, sm_quiet_analysis_pending(), #SCANS, state.scan_session == nil
    ''')
    added, has_kick, near, queued, pending, layouts, still, scans, no_session = got
    assert added == 1 and has_kick and near
    assert queued and pending is True
    assert layouts == 1 and still is False
    assert scans == 0 and no_session


def test_corner_env_button_opens_the_envelope_editor_on_that_corner():
    L = _runtime()
    _render_ok(L, 1)
    got = L.execute(r'''
      local row_x, row_y, type_w = corner_row("sustain", 2)
      -- dice, lock, type chip, volume, envelope
      MOUSE.x, MOUSE.y = row_x + 2 * 21 + type_w + 3 + 21 + 9, row_y + 9
      frame()
      local hint = state.seq_layering_hint
      MOUSE.down, MOUSE.clicked = true, true
      frame()
      MOUSE.down = false
      frame()
      local t = state.seq_env_popup_target
      local proxy = seq_env_popup_custom_target()
      -- The editor writes the corner's envelope through the proxy.
      proxy.env = { points = { { t = 0, amp = 1, curve = 0 }, { t = 0.1, amp = 1, curve = 0 }, { t = 0.12, amp = 0, curve = 0 }, { t = 0.5, amp = 0, curve = 0 } } }
      local v = SLOT.layers.sustain.verts[2]
      -- The editor card draws for the corner, beside the layering window.
      state.seq_layering_rect = { x = 40, y = 40, w = 800, h = 600 }
      state.main_window_rect = { x = 0, y = 0, w = 2000, h = 1200 }
      reaper.ImGui_GetIO = function() return nil end  -- the stub has no IO object
      local ok, err = pcall(render_seq_env_editor_popup)
      local px, py = proxy.popup_anchor(300, 200)
      seq_close_env_editor_popup()
      return hint, t and (t.side .. ":" .. t.idx), proxy.sample_path, proxy.id, v.env ~= nil and #v.env.points,
        ok, tostring(err), px, state.seq_env_popup_target == nil and state.seq_env_popup_slot_id == nil
    ''')
    hint, target, path, pid, npoints, ok, err, px, closed = got
    assert hint and "envelope" in hint
    assert target == "sustain:2" and path == "/s/sub.wav" and pid == "layer:77:sustain:2"
    assert npoints == 4
    assert ok, err
    assert px == 40 + 800 + 10  # right of the window (sustain side)
    assert closed


def test_corner_env_shapes_pieces_preview_and_player():
    L = _runtime()
    got = L.execute(r'''
      SLOT.layers.output = "layered"
      SLOT.layers.sustain.blend = { 0.5, 0.5, 0.0 }
      local v = SLOT.layers.sustain.verts[2]
      local before = seq_layering_mix_peaks(SLOT, 200)
      v.env = { points = {
        { t = 0.0, amp = 1.0, curve = 0.0 }, { t = 0.2, amp = 1.0, curve = 0.0 },
        { t = 0.25, amp = 0.0, curve = 0.0 }, { t = 0.5, amp = 0.0, curve = 0.0 } } }
      local piece
      for _, p in ipairs(seq_layering_build_pieces(SLOT)) do
        if p.path == C.path and p.time_offset_sec > 0 then piece = p end
      end
      local _, _, startoffs, t_off, len = seq_layering_piece_span(piece)
      local after = seq_layering_mix_peaks(SLOT, 200)
      -- Track envelope (fade 1 -> 0.5 over 0.5 s) x corner envelope, in item time.
      local tenv = { points = { { t = 0.0, amp = 1.0, curve = 0.0 }, { t = 0.5, amp = 0.5, curve = 0.0 } } }
      local comp = seq_layering_piece_env(tenv, v.env, t_off, startoffs, len)
      local function at(t) return seq_env_levels_at_norm(comp, t) end
      local layers = seq_player_collect_layers(SLOT)
      local fo = 0
      for _, l in ipairs(layers) do if l.path == C.path and l.delay > 0 then fo = l.fade_out end end
      return piece.env ~= nil, startoffs + len, before ~= after,
        at(0.0), seq_env_levels_at_norm(tenv, t_off) * 1.0, at(len - 0.0001) < 0.05, fo
    ''')
    has_env, src_end, peaks_changed, a0, want0, silent_end, player_fade = got
    assert has_env
    assert abs(src_end - 0.25) < 1e-6  # the piece stops where the envelope goes silent
    assert peaks_changed
    assert abs(a0 - want0) < 1e-6
    assert silent_end
    assert abs(player_fade - 0.05) < 1e-6


def test_corner_env_follows_link_and_copies():
    L = _runtime()
    got = L.execute(r'''
      seq_layering_set_linked(SLOT, true)
      SLOT.layers.transient.verts[3].env = { points = { { t = 0, amp = 0, curve = 0 }, { t = 0.01, amp = 1, curve = 0 }, { t = 0.5, amp = 1, curve = 0 } } }
      seq_layering_sync_linked(SLOT, "transient")
      local mirrored = SLOT.layers.sustain.verts[3].env and #SLOT.layers.sustain.verts[3].env.points
      local other = { id = 92, sample_path = A.path }
      seq_layering_copy_to_slot(other, SLOT)
      return mirrored, other.layers.transient.verts[3].env ~= SLOT.layers.transient.verts[3].env,
        #other.layers.transient.verts[3].env.points, seq_layering_geometry_active(SLOT)
    ''')
    assert got[0] == 3 and got[1] is True and got[2] == 3 and got[3] is True

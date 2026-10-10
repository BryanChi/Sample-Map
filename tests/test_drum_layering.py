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

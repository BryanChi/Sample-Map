-- Sample Map Browser module: drum_layering_ui
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- ===== Drum layering window =============================================
-- Header (output switch, auto-play, close), A/B cards for the original and the
-- layered mix, then one triangle card per side (transient, sustain). The point
-- inside a triangle sets the barycentric blend of its three corner samples.
--
-- Drawing cost: shapes that only depend on layout (triangle outline, waveform
-- strokes) are built once per rect and drawn as polylines from cached arrays,
-- so a steady frame issues a small, fixed number of draw calls.

SEQ_LAYER_SIDE_COLORS = { transient = 0xFF8A4CFF, sustain = 0x4FA8FFFF }
SEQ_LAYER_SIDE_LABELS = { transient = "TRANSIENT", sustain = "SUSTAIN" }
SEQ_LAYER_HEADER_H = 26.0
SEQ_LAYER_PANE_H = 58.0
SEQ_LAYER_WAVE_GAP = 6.0
SEQ_LAYER_WAVE_H = SEQ_LAYER_PANE_H * 2.0 + SEQ_LAYER_WAVE_GAP + 10.0
SEQ_LAYER_LINK_W = 78.0
SEQ_LAYER_CARD_HEAD_H = 28.0
SEQ_LAYER_PAD_TOP = 20.0
SEQ_LAYER_PAD_BOT = 64.0
SEQ_LAYER_PAD_SIDE = 74.0
SEQ_LAYER_FOOTER_H = 22.0
SEQ_LAYER_VERT_DROP_R = 24.0
SEQ_LAYER_SNAP_PX = 7.0
SEQ_LAYER_FINE_SCALE = 0.25
SEQ_LAYER_MIN_W = 640.0
SEQ_LAYER_EXT_SECTION = "SampleMapBrowser"

seq_layer_geo_cache = {}
seq_layer_poly_broken = false

local SQRT3 = math.sqrt(3.0)

-- ---------------------------------------------------------------------------
-- Colour and drawing helpers

function seq_layer_col_alpha(color, alpha_value)
  color = tonumber(color) or 0x1EFF5EFF
  alpha_value = tonumber(alpha_value) or 1.0
  local rr = math.floor((color / 16777216) % 256)
  local gg = math.floor((color / 65536) % 256)
  local bb = math.floor((color / 256) % 256)
  local aa = math.max(0, math.min(255, math.floor(alpha_value * 255)))
  return rr * 16777216 + gg * 65536 + bb * 256 + aa
end

-- t = 0 gives a, t = 1 gives b (alpha included).
function seq_layer_col_mix(a, b, t)
  local function ch(c, shift)
    return math.floor(c / shift) % 256
  end
  local out = 0
  for _, shift in ipairs({ 16777216, 65536, 256, 1 }) do
    local v = ch(a, shift) + (ch(b, shift) - ch(a, shift)) * t
    out = out + math.max(0, math.min(255, math.floor(v + 0.5))) * shift
  end
  return out
end

local closed_flag = nil
local function flags_closed()
  if not closed_flag then
    closed_flag = r.ImGui_DrawFlags_Closed and r.ImGui_DrawFlags_Closed() or 1
  end
  return closed_flag
end

-- reaper.array of a flat { x1, y1, x2, y2, ... } list, or nil when arrays or
-- polylines are unavailable (the callers then draw line by line).
local function make_array(pts)
  if seq_layer_poly_broken or not r.new_array or #pts < 4 then
    return nil
  end
  local ok, arr = pcall(r.new_array, pts)
  if ok and arr then
    return arr
  end
  return nil
end

function seq_layering_polyline(dl, pts, arr, col, closed, thick)
  if arr and not seq_layer_poly_broken then
    local ok = pcall(r.ImGui_DrawList_AddPolyline, dl, arr, col, closed and flags_closed() or 0, thick or 1.0)
    if ok then
      return
    end
    seq_layer_poly_broken = true
  end
  local n = #pts
  for i = 1, n - 3, 2 do
    r.ImGui_DrawList_AddLine(dl, pts[i], pts[i + 1], pts[i + 2], pts[i + 3], col, thick or 1.0)
  end
  if closed and n >= 6 then
    r.ImGui_DrawList_AddLine(dl, pts[n - 1], pts[n], pts[1], pts[2], col, thick or 1.0)
  end
end

function seq_layering_convex_fill(dl, pts, arr, col)
  if arr and not seq_layer_poly_broken and r.ImGui_DrawList_AddConvexPolyFilled then
    local ok = pcall(r.ImGui_DrawList_AddConvexPolyFilled, dl, arr, col)
    if ok then
      return
    end
    seq_layer_poly_broken = true
  end
  if r.ImGui_DrawList_PathLineTo and r.ImGui_DrawList_PathFillConvex then
    if r.ImGui_DrawList_PathClear then r.ImGui_DrawList_PathClear(dl) end
    for i = 1, #pts - 1, 2 do
      r.ImGui_DrawList_PathLineTo(dl, pts[i], pts[i + 1])
    end
    r.ImGui_DrawList_PathFillConvex(dl, col)
  end
end

-- Arc from angle a0 to a1 (radians, 0 = right, clockwise on screen).
function seq_layering_arc(dl, cx, cy, radius, a0, a1, col, thick)
  if a1 - a0 < 0.01 then
    return
  end
  if r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke then
    if r.ImGui_DrawList_PathClear then r.ImGui_DrawList_PathClear(dl) end
    r.ImGui_DrawList_PathArcTo(dl, cx, cy, radius, a0, a1, math.max(6, math.floor((a1 - a0) * 6)))
    r.ImGui_DrawList_PathStroke(dl, col, 0, thick or 1.5)
    return
  end
  local steps = math.max(4, math.floor((a1 - a0) * 4))
  local px, py = cx + math.cos(a0) * radius, cy + math.sin(a0) * radius
  for i = 1, steps do
    local a = a0 + (a1 - a0) * (i / steps)
    local nx, ny = cx + math.cos(a) * radius, cy + math.sin(a) * radius
    r.ImGui_DrawList_AddLine(dl, px, py, nx, ny, col, thick or 1.5)
    px, py = nx, ny
  end
end

local function point_in(mx, my, x0, y0, x1, y1)
  return mx >= x0 and mx <= x1 and my >= y0 and my <= y1
end

local function mouse_pos()
  local mx, my = r.ImGui_GetMousePos(ctx)
  return tonumber(mx) or -1e9, tonumber(my) or -1e9
end

-- Label widths and truncations repeat every frame; memoize them (bounded).
seq_layer_text_cache = { n = 0, w = {}, t = {} }

local function text_cache()
  local c = seq_layer_text_cache
  if c.n > 600 then
    c = { n = 0, w = {}, t = {} }
    seq_layer_text_cache = c
  end
  return c
end

local function text_w(text)
  local c = text_cache()
  local w = c.w[text]
  if not w then
    w = tonumber((r.ImGui_CalcTextSize(ctx, text))) or (#text * 7)
    c.w[text] = w
    c.n = c.n + 1
  end
  return w
end

local function truncate(text, max_w)
  if not seq_truncate_text_to_width then
    return text
  end
  local c = text_cache()
  local key = text .. "\0" .. math.floor(max_w)
  local out = c.t[key]
  if not out then
    out = seq_truncate_text_to_width(text, max_w)
    c.t[key] = out
    c.n = c.n + 1
  end
  return out
end

local function tooltip(text)
  if r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, text)
  end
end

-- Drag-out of a sample from this window. Armed per control (the shared
-- waveform_drag_armed flag would let one press start a drag on every control
-- that asks in the same frame).
local function drag_out_should_start(key, hovered)
  if state.map_ui_edit or state.map_ui_drag or state.pending_waveform_drop then
    return false
  end
  if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
    state.seq_layering_drag_arm = key
  end
  if not r.ImGui_IsMouseDown(ctx, 0) then
    state.seq_layering_drag_arm = nil
    return false
  end
  if state.seq_layering_drag_arm ~= key then
    return false
  end
  if r.ImGui_IsMouseDragging and r.ImGui_IsMouseDragging(ctx, 0, 6.0) then
    state.seq_layering_drag_arm = nil
    return true
  end
  return false
end

local function dbl_clicked()
  return r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
end

-- Text pill; returns its width.
local function draw_pill(dl, x, cy, text, bg, border, text_col, h)
  h = h or 18.0
  local tw = text_w(text)
  local w = tw + 14.0
  local y = cy - h * 0.5
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, h * 0.5)
  if border and border ~= 0 then
    r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, border, h * 0.5, 0, 1.0)
  end
  r.ImGui_DrawList_AddText(dl, x + 7.0, cy - 7.0, text_col, text)
  return w
end

-- Small glyphs the shared icon set doesn't have.
function seq_layering_draw_glyph(dl, kind, cx, cy, s, col)
  if kind == "triangle" then
    local h = s * 0.30
    local ax, ay = cx, cy - h * 1.05
    local bx, by = cx - h * 1.15, cy + h * 0.85
    local qx, qy = cx + h * 1.15, cy + h * 0.85
    r.ImGui_DrawList_AddTriangle(dl, ax, ay, bx, by, qx, qy, col, 1.6)
    r.ImGui_DrawList_AddCircleFilled(dl, cx - h * 0.12, cy + h * 0.25, s * 0.07, col, 8)
  elseif kind == "reset" then
    local rad = s * 0.24
    seq_layering_arc(dl, cx, cy, rad, -math.pi * 0.35, math.pi * 1.25, col, 1.5)
    local tx, ty = cx + math.cos(-math.pi * 0.35) * rad, cy + math.sin(-math.pi * 0.35) * rad
    r.ImGui_DrawList_AddTriangleFilled(dl, tx - s * 0.13, ty - s * 0.05, tx + s * 0.06, ty - s * 0.14, tx + s * 0.03, ty + s * 0.08, col)
  elseif kind == "dots" then
    for i = -1, 1 do
      r.ImGui_DrawList_AddCircleFilled(dl, cx + i * s * 0.2, cy, s * 0.065, col, 8)
    end
  elseif kind == "lock" or kind == "unlock" then
    -- Same shape as the shared "lock" icon; open = shackle lifted aside.
    local stroke = math.max(1.2, s * 0.08)
    local bw, top = s * 0.20, cy - s * 0.02
    local open = kind == "unlock"
    local sx = open and s * 0.11 or 0.0
    local lift = open and s * 0.09 or 0.0
    r.ImGui_DrawList_AddRect(dl, cx - s * 0.12 + sx, cy - s * 0.28 - lift, cx + s * 0.12 + sx, top + s * 0.08 - lift,
      col, s * 0.12, 0, stroke)
    r.ImGui_DrawList_AddRectFilled(dl, cx - bw, top, cx + bw, cy + s * 0.27, col, 2.0)
  end
end

-- Square icon button drawn like the toolbar buttons. kind: an icon of the
-- shared set, or a glyph above (prefix "g:").
function seq_layering_icon_button(id, dl, x, y, w, h, kind, active, opts)
  opts = opts or {}
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg, _, text_col, border = ui_button_colors(opts.style or "default", hovered, pressed, active)
  ui_draw_panel(dl, x, y, x + w, y + h, opts.rounding or 5.0, bg, border, hovered, pressed)
  local col = opts.color or ((hovered or pressed) and 0xFFFFFFFF or text_col)
  local cx, cy = x + w * 0.5, y + h * 0.5 + (pressed and 1.0 or 0.0)
  if kind:sub(1, 2) == "g:" then
    seq_layering_draw_glyph(dl, kind:sub(3), cx, cy, math.min(w, h), col)
  else
    ui_button_draw_icon(dl, kind, cx, cy, math.min(w, h) * (opts.icon_scale or 0.95), col)
  end
  return clicked, hovered
end

-- ---------------------------------------------------------------------------
-- Preferences

function seq_layering_auto_audition()
  if state.seq_layering_auto == nil then
    local raw = r.GetExtState and r.GetExtState(SEQ_LAYER_EXT_SECTION, "layering_auto_audition") or ""
    state.seq_layering_auto = raw == "1"
  end
  return state.seq_layering_auto == true
end

function seq_layering_set_auto_audition(on)
  state.seq_layering_auto = on == true
  if r.SetExtState then
    r.SetExtState(SEQ_LAYER_EXT_SECTION, "layering_auto_audition", on and "1" or "0", true)
  end
end

-- Persist, rebuild the arrange items and (with auto-play on) play the mix.
function seq_layering_commit(slot, opts)
  opts = opts or {}
  save_config()
  seq_layering_sync_arrange(slot, { force_rebuild = opts.force_rebuild })
  if opts.audition ~= false and seq_layering_auto_audition() then
    seq_layering_preview_layered(slot, 0)
  end
end

-- Runs fn inside its own undo step unless one is already open.
function seq_layering_with_undo(label, fn)
  local owned = seq_undo_own_begin and seq_undo_own_begin(label, { lazy_reaper = true })
  local ok, res = pcall(fn)
  if owned and seq_undo_is_open() then
    end_seq_undo()
  end
  if not ok then
    error(res, 0)
  end
  return res
end

-- ---------------------------------------------------------------------------
-- Geometry

-- (x, y, w, h) is a triangle card; the triangle sits below the card header.
function seq_layering_tri_geom(x, y, w, h)
  local top = SEQ_LAYER_CARD_HEAD_H + SEQ_LAYER_PAD_TOP
  local avail_w = math.max(72.0, w - SEQ_LAYER_PAD_SIDE * 2.0)
  local avail_h = math.max(72.0, h - top - SEQ_LAYER_PAD_BOT)
  local side = math.min(avail_w, avail_h * 2.0 / SQRT3)
  local tri_h = side * (SQRT3 * 0.5)
  local ax = x + w * 0.5
  local ay = y + top + math.max(0.0, (avail_h - tri_h) * 0.5)
  local bx = ax - side * 0.5
  local by = ay + tri_h
  local cx = ax + side * 0.5
  local cy = by
  return ax, ay, bx, by, cx, cy, side, tri_h
end

function seq_layering_card_h(col_w)
  local avail_w = math.max(72.0, col_w - SEQ_LAYER_PAD_SIDE * 2.0)
  return SEQ_LAYER_CARD_HEAD_H + SEQ_LAYER_PAD_TOP + avail_w * SQRT3 * 0.5 + SEQ_LAYER_PAD_BOT
end

function seq_layering_col_w(content_w)
  return math.max(190.0, (content_w - SEQ_LAYER_LINK_W) * 0.5)
end

function seq_layering_ideal_content_h(content_w)
  return SEQ_LAYER_HEADER_H + 8.0 + SEQ_LAYER_WAVE_H
      + seq_layering_card_h(seq_layering_col_w(content_w)) + SEQ_LAYER_FOOTER_H
end

function seq_layering_rounded_tri_points(ax, ay, bx, by, cx, cy, radius)
  local V = { { ax, ay }, { bx, by }, { cx, cy } }
  local pts = {}
  local steps = 7
  for i = 1, 3 do
    local p0 = V[i == 1 and 3 or (i - 1)]
    local p1 = V[i]
    local p2 = V[i == 3 and 1 or (i + 1)]
    local e1x, e1y = p0[1] - p1[1], p0[2] - p1[2]
    local e2x, e2y = p2[1] - p1[1], p2[2] - p1[2]
    local l1 = math.sqrt(e1x * e1x + e1y * e1y)
    local l2 = math.sqrt(e2x * e2x + e2y * e2y)
    if l1 < 1e-4 or l2 < 1e-4 then
      pts[#pts + 1] = p1[1]
      pts[#pts + 1] = p1[2]
    else
      e1x, e1y = e1x / l1, e1y / l1
      e2x, e2y = e2x / l2, e2y / l2
      local dot = math.max(-1.0, math.min(1.0, e1x * e2x + e1y * e2y))
      local ang = math.acos(dot)
      local d = radius / math.max(0.18, math.tan(ang * 0.5))
      d = math.min(d, l1 * 0.42, l2 * 0.42)
      local rad = d * math.tan(ang * 0.5)
      local a1x, a1y = p1[1] + e1x * d, p1[2] + e1y * d
      local a2x, a2y = p1[1] + e2x * d, p1[2] + e2y * d
      local bisx, bisy = e1x + e2x, e1y + e2y
      local bl = math.sqrt(bisx * bisx + bisy * bisy)
      local sin_h = math.sin(ang * 0.5)
      local clen = (sin_h > 1e-4) and (rad / sin_h) or rad
      local ocx = p1[1] + (bisx / bl) * clen
      local ocy = p1[2] + (bisy / bl) * clen
      local t0 = math.atan(a1y - ocy, a1x - ocx)
      local t1 = math.atan(a2y - ocy, a2x - ocx)
      local sweep = t1 - t0
      while sweep > math.pi do sweep = sweep - 2.0 * math.pi end
      while sweep < -math.pi do sweep = sweep + 2.0 * math.pi end
      for s = 0, steps do
        local t = t0 + sweep * (s / steps)
        pts[#pts + 1] = ocx + math.cos(t) * rad
        pts[#pts + 1] = ocy + math.sin(t) * rad
      end
    end
  end
  return pts
end

function seq_layering_expand_tri(ax, ay, bx, by, cx, cy, amt)
  local mx = (ax + bx + cx) / 3.0
  local my = (ay + by + cy) / 3.0
  local function push(px, py)
    local dx, dy = px - mx, py - my
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1e-4 then return px, py end
    return px + dx / l * amt, py + dy / l * amt
  end
  local ax2, ay2 = push(ax, ay)
  local bx2, by2 = push(bx, by)
  local cx2, cy2 = push(cx, cy)
  return ax2, ay2, bx2, by2, cx2, cy2
end

-- Rounded outline, glow rings and fill polygon for one triangle, rebuilt only
-- when the triangle moves or resizes.
function seq_layering_tri_shapes(key, ax, ay, bx, by, cx, cy)
  local e = seq_layer_geo_cache[key]
  if e and e.ax == ax and e.ay == ay and e.bx == bx and e.by == by and e.cx == cx and e.cy == cy then
    return e
  end
  e = { ax = ax, ay = ay, bx = bx, by = by, cx = cx, cy = cy, glow = {} }
  -- A small rounding keeps the corners under the corner nodes, where the
  -- blend reaches 100%.
  local radius = 6.0
  -- Clockwise on screen (top, right, left): ImGui's anti-aliased fill needs it.
  e.body = seq_layering_rounded_tri_points(ax, ay, cx, cy, bx, by, radius)
  e.body_arr = make_array(e.body)
  for i = 1, 3 do
    local ea, ey, eb, eby, ec, ecy = seq_layering_expand_tri(ax, ay, bx, by, cx, cy, i * 3.2)
    local pts = seq_layering_rounded_tri_points(ea, ey, ec, ecy, eb, eby, radius + i * 2.0)
    e.glow[i] = { pts = pts, arr = make_array(pts) }
  end
  seq_layer_geo_cache[key] = e
  return e
end

-- Snap a point to the corners, edge midpoints or centre when within radius.
-- Returns x, y and the snap target (or nil).
function seq_layering_snap_point(px, py, ax, ay, bx, by, cx, cy, radius)
  local targets = {
    { ax, ay }, { bx, by }, { cx, cy },
    { (ax + bx) * 0.5, (ay + by) * 0.5 },
    { (bx + cx) * 0.5, (by + cy) * 0.5 },
    { (cx + ax) * 0.5, (cy + ay) * 0.5 },
    { (ax + bx + cx) / 3.0, (ay + by + cy) / 3.0 },
  }
  local best, best_d = nil, (radius or SEQ_LAYER_SNAP_PX) ^ 2
  for i = 1, #targets do
    local t = targets[i]
    local dx, dy = px - t[1], py - t[2]
    local d = dx * dx + dy * dy
    if d <= best_d then
      best, best_d = t, d
    end
  end
  if best then
    return best[1], best[2], best
  end
  return px, py, nil
end

-- ---------------------------------------------------------------------------
-- Waveforms

-- A waveform as one zig-zag stroke (the body) plus an envelope line. Points
-- are rebuilt only when the rect or the peaks table changes.
function seq_layering_draw_wave(dl, key, x, y, w, h, peaks, fill_col, line_col)
  if not peaks or #peaks == 0 or w < 4 or h < 4 then
    return
  end
  local n = #peaks
  local e = seq_layer_geo_cache[key]
  if not (e and e.peaks == peaks and e.x == x and e.y == y and e.w == w and e.h == h) then
    e = { peaks = peaks, x = x, y = y, w = w, h = h }
    local mid, amp = y + h * 0.5, h * 0.48
    local step = w / n
    local zig, top, bot = {}, {}, {}
    for i = 1, n do
      local v = tonumber(peaks[i]) or 0.0
      if v > 1.0 then v = 1.0 elseif v < 0.0 then v = 0.0 end
      local px = x + (i - 0.5) * step
      local half = math.max(0.5, v * amp)
      local ty, by = mid - half, mid + half
      local k = #zig
      if i % 2 == 1 then
        zig[k + 1], zig[k + 2], zig[k + 3], zig[k + 4] = px, ty, px, by
      else
        zig[k + 1], zig[k + 2], zig[k + 3], zig[k + 4] = px, by, px, ty
      end
      top[#top + 1] = px
      top[#top + 1] = ty
      bot[#bot + 1] = px
      bot[#bot + 1] = by
    end
    e.zig, e.top, e.bot = zig, top, bot
    e.step = step
    e.zig_arr, e.top_arr, e.bot_arr = make_array(zig), make_array(top), make_array(bot)
    seq_layer_geo_cache[key] = e
  end
  if e.zig_arr and not seq_layer_poly_broken then
    seq_layering_polyline(dl, e.zig, e.zig_arr, fill_col, false, math.max(1.0, e.step))
  else
    -- No arrays: about one bar per 3 px.
    local stride = math.max(1, math.ceil(n / math.max(8.0, w / 3.0)))
    local half_w = math.max(0.5, e.step * stride * 0.32)
    for i = 1, n, stride do
      local px = e.top[i * 2 - 1]
      r.ImGui_DrawList_AddRectFilled(dl, px - half_w, e.top[i * 2], px + half_w, e.bot[i * 2], fill_col, 1.0)
    end
  end
  if line_col then
    seq_layering_polyline(dl, e.top, e.top_arr, line_col, false, 1.0)
    if e.bot_arr and not seq_layer_poly_broken then
      seq_layering_polyline(dl, e.bot, e.bot_arr, seq_layer_col_alpha(line_col, 0.35), false, 1.0)
    end
  end
end

function seq_layering_wave_peaks(sample, width)
  if not sample then
    return nil, nil
  end
  local peaks, dur = seq_env_get_wave_peaks(sample, width)
  return peaks, dur or tonumber(sample.duration)
end

-- Original pane: transient / sustain shading and a draggable split handle.
-- Returns true while the handle owns the mouse.
local function draw_split_handle(dl, slot, sample, ix, iy, iw, ih, dur, hover_side)
  local split_t = seq_layering_split_time(slot)
  local onset = seq_layering_trans_base(sample)
  local function t2x(t)
    return ix + (math.max(0.0, math.min(dur, t)) / dur) * iw
  end
  local ox, sx, ex = t2x(onset), t2x(split_t), ix + iw
  local t_col = SEQ_LAYER_SIDE_COLORS.transient
  local s_col = SEQ_LAYER_SIDE_COLORS.sustain
  if sx > ox + 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, ox, iy, sx, iy + ih,
      seq_layer_col_alpha(t_col, hover_side == "transient" and 0.30 or 0.17), 2.0)
  end
  if ex > sx + 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, sx, iy, ex, iy + ih,
      seq_layer_col_alpha(s_col, hover_side == "sustain" and 0.20 or 0.09), 2.0)
  end

  local grab_w = 12.0
  r.ImGui_SetCursorScreenPos(ctx, sx - grab_w * 0.5, iy - 6.0)
  r.ImGui_InvisibleButton(ctx, "##seq_layer_split_" .. tostring(slot.id), grab_w, ih + 8.0)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  if hovered or active then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    end
  end
  if hovered and dbl_clicked() then
    slot.layers.bias = 0.0
    state.seq_layering_bias_drag = nil
    seq_layering_commit(slot, { force_rebuild = true })
  elseif active then
    local mx = mouse_pos()
    local t = ((mx - ix) / math.max(1.0, iw)) * dur
    if seq_layering_set_split_time(slot, t) then
      state.seq_layering_bias_drag = true
    end
  elseif state.seq_layering_bias_drag and not r.ImGui_IsMouseDown(ctx, 0) then
    state.seq_layering_bias_drag = nil
    seq_layering_commit(slot, { force_rebuild = true })
  end

  local hot = hovered or active
  local line_col = hot and 0xFFFFFFFF or 0xC8FFD8DD
  r.ImGui_DrawList_AddLine(dl, sx, iy - 2.0, sx, iy + ih, line_col, hot and 2.0 or 1.4)
  r.ImGui_DrawList_AddTriangleFilled(dl, sx - 5.0, iy - 6.0, sx + 5.0, iy - 6.0, sx, iy, line_col)
  if hot then
    local label = string.format("%.0f ms", math.max(0.0, split_t - onset) * 1000.0)
    local lw = text_w(label)
    local lx = math.min(ix + iw - lw - 10.0, math.max(ix, sx + 6.0))
    r.ImGui_DrawList_AddRectFilled(dl, lx - 4.0, iy + 1.0, lx + lw + 4.0, iy + 17.0, 0x0B0E0CE8, 4.0)
    r.ImGui_DrawList_AddText(dl, lx, iy + 2.0, 0xFFFFFFFF, label)
    tooltip("Split between transient and sustain\nDrag to move  ·  Double-click to reset")
  end
  return hot
end

function seq_layering_draw_wave_pane(dl, slot, x, y, w, h, kind, hover_side)
  local is_orig = kind == "original"
  local using = seq_layering_output(slot) == kind
  local playing = seq_layering_ab_playing(slot, kind)
  local linked = slot.layers and slot.layers.linked
  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  local ix, iy, iw, ih = x + 10.0, y + 22.0, w - 20.0, h - 28.0

  local peaks, dur, ribbon = nil, nil, nil
  if not is_orig then
    peaks, dur, ribbon = seq_layering_mix_peaks(slot, math.floor(iw))
  elseif sample then
    peaks, dur = seq_layering_wave_peaks(sample, math.floor(iw))
  end
  dur = tonumber(dur) or 0

  -- Panel first so the shading and handle draw on top of it.
  local mx, my = mouse_pos()
  local over = point_in(mx, my, x, y, x + w, y + h) and state.seq_layering_hovered
  local hot = playing or state.seq_layering_ab == kind
  local bg = hot and 0x112619FF or UI_THEME.bg_panel
  if over then bg = hot and 0x163322FF or UI_THEME.surface end
  local edge = using and 0x1EFF5E99 or (over and UI_THEME.border_hvr or UI_THEME.border_soft)
  ui_draw_panel(dl, x, y, x + w, y + h, 8.0, bg, edge, over, false)
  if using then
    r.ImGui_DrawList_AddRectFilled(dl, x + 1.0, y + 9.0, x + 4.0, y + h - 9.0, UI_THEME.accent, 1.5)
  end

  local handle_hot = false
  if is_orig and sample and dur > 0 and not linked then
    handle_hot = draw_split_handle(dl, slot, sample, ix, iy, iw, ih, dur, hover_side)
  end

  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##seq_layer_ab_" .. kind .. "_" .. tostring(slot.id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx) and not handle_hot
  local clicked = hovered and r.ImGui_IsItemClicked(ctx, 0)

  -- Title row: letter badge, name, OUTPUT tag, length.
  local badge = is_orig and "A" or "B"
  local bx0, by0 = x + 10.0, y + 4.0
  r.ImGui_DrawList_AddRectFilled(dl, bx0, by0, bx0 + 15.0, by0 + 15.0, hot and UI_THEME.accent or UI_THEME.elevated, 4.0)
  r.ImGui_DrawList_AddText(dl, bx0 + 4.0, by0 + 0.5, hot and 0x07140BFF or UI_THEME.text_dim, badge)
  local label = is_orig and "ORIGINAL" or "LAYERED"
  r.ImGui_DrawList_AddText(dl, bx0 + 22.0, by0 + 0.5, hot and 0xFFFFFFFF or UI_THEME.text, label)
  local meta_x = bx0 + 22.0 + text_w(label) + 10.0
  if using then
    meta_x = meta_x + draw_pill(dl, meta_x, by0 + 7.5, "OUTPUT", 0x145028FF, 0, 0xD8FFE4FF, 15.0) + 8.0
  end
  if not is_orig and not seq_layering_geometry_active(slot) then
    r.ImGui_DrawList_AddText(dl, meta_x, by0 + 0.5, UI_THEME.text_mute, "same as original")
  end
  local right_x = x + w - 10.0
  if dur > 0 then
    local dtext = string.format("%.0f ms", dur * 1000.0)
    local dw = text_w(dtext)
    right_x = right_x - dw
    r.ImGui_DrawList_AddText(dl, right_x, by0 + 0.5, UI_THEME.text_mute, dtext)
  end
  if playing then
    ui_button_draw_icon(dl, "play", right_x - 12.0, by0 + 7.5, 14.0, UI_THEME.accent)
  end

  -- Waveform.
  if peaks and iw > 4 and ih > 4 then
    if is_orig then
      seq_layering_draw_wave(dl, "orig", ix, iy, iw, ih, peaks, 0x7F9DB86A, 0xA9C4DCC0)
    else
      -- Faint outline of the original on the same time scale, for comparison.
      local orig_peaks, orig_dur = seq_layering_wave_peaks(sample, math.floor(iw))
      if orig_peaks and orig_dur and orig_dur > 0 and dur > 0 and seq_layering_geometry_active(slot) then
        local gw = math.max(8.0, math.min(iw, iw * orig_dur / dur))
        seq_layering_draw_wave(dl, "ghost", ix, iy, gw, ih, orig_peaks, 0xFFFFFF0E, nil)
      end
      seq_layering_draw_wave(dl, "mix", ix, iy, iw, ih, peaks, 0x1EFF5E50, 0x7CFFA2D8)
      if ribbon and #ribbon > 0 then
        local ry = y + h - 5.0
        for i = 1, #ribbon do
          local seg = ribbon[i]
          local sx0, sx1 = ix + seg.u0 * iw, ix + seg.u1 * iw
          if sx1 - sx0 >= 1.0 then
            r.ImGui_DrawList_AddRectFilled(dl, sx0, ry, sx1 - 1.0, ry + 2.5, seq_layer_col_alpha(seg.color, 0.9), 1.0)
          end
        end
      end
    end
  elseif not sample then
    r.ImGui_DrawList_AddText(dl, ix, iy + ih * 0.5 - 7.0, UI_THEME.text_mute, "Assign a sample to this track")
  end

  if playing and dur > 0 then
    local pos = get_preview_position() or state.preview_position or 0.0
    local px = ix + (math.max(0.0, math.min(dur, pos)) / dur) * iw
    r.ImGui_DrawList_AddLine(dl, px, iy - 2.0, px, iy + ih + 2.0, 0xFFFF88FF, 1.6)
    r.ImGui_DrawList_AddCircleFilled(dl, px, iy - 2.0, 3.0, 0xFFFF88FF, 10)
  end

  if hovered then
    tooltip(is_orig
      and "Click: play the original\nDrag: drop the original sample"
      or "Click: play the layered mix\nDrag: drop the layered mix on a track or the arrange")
  end
  local drag_sample = nil
  if is_orig then
    drag_sample = sample
  elseif slot.sample_path then
    drag_sample = seq_layering_drag_sample(slot)
  end
  if drag_sample and not handle_hot and drag_out_should_start("pane_" .. kind, hovered) then
    begin_waveform_sample_drag(drag_sample)
  end
  if drag_sample and sample_is_waveform_drag_source(drag_sample) then
    draw_waveform_drag_source_cue(dl, x, y, w, h)
  end
  if clicked and not state.pending_waveform_drop then
    if is_orig then
      seq_layering_preview_original(slot)
    else
      seq_layering_preview_layered(slot, 0)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Corner controls

function seq_layering_vol_knob(id, dl, x, y, size, vert)
  if type(vert) ~= "table" then
    return false, false
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local vol = seq_layer_vert_vol(vert)
  local changed = false
  if active then
    local _, dy = r.ImGui_GetMouseDelta(ctx)
    if dy and dy ~= 0.0 then
      local step = ((SEQ_LAYER_VOL_MAX or 4.0) / 180.0) * (seq_fine_drag_down() and SEQ_FINE_DRAG_SCALE or 1.0)
      vol = seq_layer_vert_vol({ vol = vol + (-dy) * step })
      vert.vol = vol
      changed = true
    end
  end
  if r.ImGui_IsItemClicked(ctx, 0) and dbl_clicked() then
    vert.vol = 1.0
    vol = 1.0
    changed = true
  end
  local cx, cy = x + size * 0.5, y + size * 0.5 + (active and 1.0 or 0.0)
  local radius = size * 0.5
  local fill = active and UI_THEME.accent_fill_h or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, fill, 16)
  -- Track ring, value arc (amber above 100%), centre dot.
  local amin, amax = math.pi * 0.75, math.pi * 2.25
  local ang = amin + (amax - amin) * (vol / (SEQ_LAYER_VOL_MAX or 4.0))
  local arc_r = radius - 2.6
  seq_layering_arc(dl, cx, cy, arc_r, amin, amax, (hovered or active) and UI_THEME.border_hvr or UI_THEME.border, 2.0)
  seq_layering_arc(dl, cx, cy, arc_r, amin, ang, vol > 1.001 and 0xFFC870FF or UI_THEME.accent, 2.0)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 1.6, (hovered or active) and 0xFFFFFFFF or UI_THEME.text_dim, 8)
  if hovered then
    local db = vol > 0.0001 and (20.0 * math.log(vol, 10)) or -math.huge
    local db_text = db == -math.huge and "-inf dB" or string.format("%+.1f dB", db)
    tooltip(string.format("Corner volume  %.0f%%  (%s)\nDrag up or down  ·  Shift: fine  ·  Double-click: 100%%", vol * 100.0, db_text))
  end
  return changed, hovered
end

function seq_layering_vert_can_drop(hit)
  if not hit then
    return false
  end
  return (not hit.locked) or (hit.idx == 1)
end

function seq_layering_store_vert_hit(side_key, idx, vx, vy, locked)
  state.seq_layering_vert_hits = state.seq_layering_vert_hits or {}
  state.seq_layering_vert_hits[#state.seq_layering_vert_hits + 1] = {
    side = side_key,
    idx = idx,
    x = vx,
    y = vy,
    locked = locked == true,
  }
end

function seq_layering_hit_vert(mx, my)
  local hits = state.seq_layering_vert_hits
  mx, my = tonumber(mx), tonumber(my)
  if not hits or not mx or not my then
    return nil
  end
  local rad = SEQ_LAYER_VERT_DROP_R or 24.0
  local best, best_d = nil, rad * rad
  for i = 1, #hits do
    local h = hits[i]
    if seq_layering_vert_can_drop(h) then
      local dx, dy = mx - h.x, my - h.y
      local d = dx * dx + dy * dy
      if d <= best_d then
        best_d = d
        best = h
      end
    end
  end
  return best
end

function seq_layering_pointer_over_window()
  local rect = state.seq_layering_rect
  if not rect then
    return false
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  mx, my = tonumber(mx), tonumber(my)
  if not mx or not my then
    return false
  end
  return mx >= (rect.x or 0) and my >= (rect.y or 0)
    and mx <= (rect.x or 0) + (rect.w or 0)
    and my <= (rect.y or 0) + (rect.h or 0)
end

function seq_layering_resolve_drop_vert()
  if not sample_drag_active() then
    state.seq_layering_drop_vert = nil
    return nil
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hit = seq_layering_hit_vert(mx, my)
  if hit then
    state.seq_layering_drop_vert = { side = hit.side, idx = hit.idx }
    return hit
  end
  state.seq_layering_drop_vert = nil
  return nil
end

function seq_layering_draw_vert_drop_cues(dl)
  if not dl or not sample_drag_active() then
    return
  end
  local hits = state.seq_layering_vert_hits
  if not hits then
    return
  end
  local drop = state.seq_layering_drop_vert
  local pulse = (drag_pulse and drag_pulse()) or 0.5
  for i = 1, #hits do
    local h = hits[i]
    if seq_layering_vert_can_drop(h) then
      local is_hot = drop and drop.side == h.side and drop.idx == h.idx
      if is_hot then
        r.ImGui_DrawList_AddCircleFilled(dl, h.x, h.y, 17.0, seq_layer_col_alpha(UI_THEME.accent, 0.30 + 0.22 * pulse), 24)
        r.ImGui_DrawList_AddCircle(dl, h.x, h.y, 17.0, 0x7CFF4AFF, 24, 2.4)
        r.ImGui_DrawList_AddCircle(dl, h.x, h.y, 23.0 + 2.0 * pulse, seq_layer_col_alpha(UI_THEME.accent, 0.55), 24, 1.5)
      else
        r.ImGui_DrawList_AddCircle(dl, h.x, h.y, 14.0, seq_layer_col_alpha(UI_THEME.accent, 0.40 + 0.18 * pulse), 20, 1.6)
      end
    end
  end
end

local function vert_display_name(vert)
  if vert.path and vert.path ~= "" then
    return basename(vert.path)
  elseif vert.name and vert.name ~= "" then
    return tostring(vert.name)
  end
  return nil
end

-- The last sample auditioned from the map, when it can go on a corner.
function seq_layering_last_auditioned()
  local s = preview_sample_obj or state.history_head
  if not s or not s.path or s.is_layering_mix then
    return nil
  end
  if tostring(s.path):sub(1, 13) == "layering-mix:" then
    return nil
  end
  return find_sample_by_path(s.path) or s
end

-- Sample chip: name and weight. Returns its rect.
local function draw_vert_chip(dl, x, cy, max_w, vert, pct, color, hot)
  local name = vert_display_name(vert)
  local h = 20.0
  local y = cy - h * 0.5
  local pct_text = name and string.format("%d%%", pct) or ""
  local pw = name and text_w(pct_text) or 0.0
  local label = name and truncate(name, math.max(24.0, max_w - pw - 24.0)) or "Drop a sample"
  local lw = text_w(label)
  local w = lw + 16.0 + (name and (pw + 8.0) or 0.0)
  local active = name and pct > 0
  local bg = hot and UI_THEME.surface_hvr or UI_THEME.surface
  local border = active and seq_layer_col_alpha(color, hot and 0.95 or 0.55) or UI_THEME.border
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, h * 0.5)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, border, h * 0.5, 0, 1.0)
  r.ImGui_DrawList_AddText(dl, x + 8.0, cy - 7.0, name and (active and 0xF4F7FCFF or UI_THEME.text_dim) or UI_THEME.text_mute, label)
  if name then
    r.ImGui_DrawList_AddText(dl, x + 8.0 + lw + 8.0, cy - 7.0, active and color or UI_THEME.text_mute, pct_text)
  end
  return x, y, w, h
end

local function chip_width(vert, pct, max_w)
  local name = vert_display_name(vert)
  if not name then
    return text_w("Drop a sample") + 16.0
  end
  local pw = text_w(string.format("%d%%", pct))
  local label = truncate(name, math.max(24.0, max_w - pw - 24.0))
  return text_w(label) + 16.0 + pw + 8.0
end

-- ---------------------------------------------------------------------------
-- Menus

function seq_layering_open_vert_menu(slot, side_key, idx)
  state.seq_layering_menu = { slot_id = slot.id, side = side_key, idx = idx }
  r.ImGui_OpenPopup(ctx, "##seq_layer_vert_menu")
end

function seq_layering_open_side_menu(slot, side_key)
  state.seq_layering_side_menu = { slot_id = slot.id, side = side_key }
  r.ImGui_OpenPopup(ctx, "##seq_layer_side_menu")
end

function seq_layering_render_menus(slot)
  if r.ImGui_BeginPopup and r.ImGui_BeginPopup(ctx, "##seq_layer_vert_menu") then
    local m = state.seq_layering_menu
    if m and m.slot_id == slot.id then
      local side_key, idx = m.side, m.idx
      local side = slot.layers[side_key]
      local vert = side.verts[idx]
      local sample = vert.path and find_sample_by_path(vert.path) or nil
      local name = vert_display_name(vert)
      ui_group_caption((SEQ_LAYER_SIDE_LABELS[side_key] or "") .. "  ·  " .. (idx == 1 and "TOP" or (idx == 2 and "LEFT" or "RIGHT")))
      if name then
        r.ImGui_TextColored(ctx, UI_THEME.text, truncate(name, 240))
      else
        r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Empty corner")
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Preview", nil, false, sample ~= nil) and sample then
        state.seq_layering_ab = nil
        preview_sample(sample)
      end
      if r.ImGui_MenuItem(ctx, "Solo this corner", nil, false, vert.path ~= nil) then
        seq_layering_with_undo("Solo drum layer", function()
          seq_layering_solo_vert(slot, side_key, idx)
        end)
        seq_layering_commit(slot)
      end
      local last = seq_layering_last_auditioned()
      local can_take = last and (not vert.locked or idx == 1)
          and (not vert.path or normalize_path(vert.path) ~= normalize_path(last.path))
      local take_label = (idx == 1 and vert.locked) and "Replace track sample with " or "Use "
      take_label = take_label .. (last and truncate(last.name or basename(last.path), 170) or "last auditioned sample")
      if r.ImGui_MenuItem(ctx, take_label, nil, false, can_take and true or false) and can_take then
        seq_layering_with_undo("Set drum layer sample", function()
          seq_layering_set_vert(slot, side_key, idx, last)
        end)
        seq_layering_commit(slot, { force_rebuild = idx == 1 })
      end
      if r.ImGui_MenuItem(ctx, "Randomize", nil, false, not vert.locked) then
        local changed = false
        seq_layering_with_undo("Randomize drum layer", function()
          changed = seq_layering_randomize_vert(slot, side_key, idx)
        end)
        if changed then seq_layering_commit(slot) end
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Locked", nil, vert.locked) then
        seq_layering_with_undo("Lock drum layer", function()
          vert.locked = not vert.locked
          seq_layering_sync_linked(slot, side_key)
        end)
        save_config()
      end
      if r.ImGui_MenuItem(ctx, "Reset volume to 100%", nil, false, math.abs(seq_layer_vert_vol(vert) - 1.0) > 0.001) then
        seq_layering_with_undo("Reset drum layer volume", function()
          vert.vol = 1.0
          seq_layering_sync_linked(slot, side_key)
        end)
        seq_layering_commit(slot)
      end
      if idx > 1 and r.ImGui_MenuItem(ctx, "Clear", nil, false, vert.path ~= nil and not vert.locked) then
        seq_layering_with_undo("Clear drum layer", function()
          seq_layering_clear_vert(slot, side_key, idx)
        end)
        seq_layering_commit(slot)
      end
      if sample and seq_reveal_sample_in_explorer then
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Show in Finder") then
          seq_reveal_sample_in_explorer(sample)
        end
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  if r.ImGui_BeginPopup and r.ImGui_BeginPopup(ctx, "##seq_layer_side_menu") then
    local m = state.seq_layering_side_menu
    if m and m.slot_id == slot.id then
      local side_key = m.side
      local other = side_key == "transient" and "sustain" or "transient"
      local linked = slot.layers.linked
      ui_group_caption(SEQ_LAYER_SIDE_LABELS[side_key] or "")
      if r.ImGui_MenuItem(ctx, "Even mix") then
        seq_layering_with_undo("Even drum layer mix", function()
          seq_layering_even_mix(slot, side_key)
        end)
        seq_layering_commit(slot)
      end
      if r.ImGui_MenuItem(ctx, "Reset to original") then
        seq_layering_with_undo("Reset drum layering", function()
          seq_layering_reset_side(slot, side_key)
        end)
        seq_layering_commit(slot)
      end
      if r.ImGui_MenuItem(ctx, "Randomize unlocked corners") then
        local changed = false
        seq_layering_with_undo("Randomize drum layers", function()
          changed = seq_layering_randomize_side(slot, side_key)
        end)
        if changed then seq_layering_commit(slot) end
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Copy to " .. string.lower(SEQ_LAYER_SIDE_LABELS[other]), nil, false, not linked) then
        seq_layering_with_undo("Copy drum layering", function()
          seq_layering_copy_side_to_other(slot, side_key)
        end)
        seq_layering_commit(slot)
      end
      if r.ImGui_MenuItem(ctx, "Swap transient and sustain", nil, false, not linked) then
        seq_layering_with_undo("Swap drum layering", function()
          seq_layering_swap_sides(slot)
        end)
        seq_layering_commit(slot)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

-- ---------------------------------------------------------------------------
-- Triangle card

local function draw_weight_bar(dl, x, y, w, h, side, colors)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x0000004A, h * 0.5)
  local cur = x
  for i = 1, 3 do
    local wt = side.blend[i] or 0.0
    if wt > 0.004 and side.verts[i].path then
      local seg = w * wt
      r.ImGui_DrawList_AddRectFilled(dl, cur, y, math.min(x + w, cur + seg), y + h, seq_layer_col_alpha(colors[i], 0.92), h * 0.5)
      cur = cur + seg
    end
  end
end

function seq_layering_draw_triangle(dl, slot, side_key, x, y, w, h)
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  local linked = slot.layers.linked == true
  local side_col = SEQ_LAYER_SIDE_COLORS[side_key] or UI_THEME.accent
  local hot_side = state.seq_layering_prev_hover == side_key
  local dragging = state.seq_layering_drag and state.seq_layering_drag.side == side_key
      and state.seq_layering_drag.slot_id == slot.id
  local mx, my = mouse_pos()
  local changed, audition = false, true

  -- Card.
  ui_draw_panel(dl, x, y, x + w, y + h, UI_METRICS.radius_panel, UI_THEME.bg_panel,
    (hot_side or dragging) and seq_layer_col_alpha(side_col, 0.45) or UI_THEME.border_soft, false, false)

  -- Card header: side dot, label, weight bar, dice / reset / menu.
  local hy = y + SEQ_LAYER_CARD_HEAD_H * 0.5
  r.ImGui_DrawList_AddCircleFilled(dl, x + 14.0, hy, 4.0, side_col, 12)
  local label = SEQ_LAYER_SIDE_LABELS[side_key]
  r.ImGui_DrawList_AddText(dl, x + 24.0, hy - 7.0, UI_THEME.text, label)
  local after_label = x + 24.0 + text_w(label) + 10.0
  if linked then
    after_label = after_label + draw_pill(dl, after_label, hy, "LINKED", UI_THEME.accent_fill, 0x1EFF5E55, UI_THEME.accent, 16.0) + 8.0
  end
  local btn = 20.0
  local bx = x + w - 8.0 - btn
  local by = hy - btn * 0.5
  local id = tostring(slot.id) .. "_" .. side_key
  local menu_clicked, menu_hovered = seq_layering_icon_button("##seq_layer_menu_" .. id, dl, bx, by, btn, btn, "g:dots", false)
  if menu_hovered then tooltip("More: even mix, copy, swap") end
  if menu_clicked then seq_layering_open_side_menu(slot, side_key) end
  bx = bx - btn - 4.0
  local reset_clicked, reset_hovered = seq_layering_icon_button("##seq_layer_reset_" .. id, dl, bx, by, btn, btn, "g:reset", false)
  if reset_hovered then tooltip("Reset to the original sample") end
  if reset_clicked then
    seq_layering_reset_side(slot, side_key)
    changed = true
  end
  bx = bx - btn - 4.0
  local dice_clicked, dice_hovered = seq_layering_icon_button("##seq_layer_dice_all_" .. id, dl, bx, by, btn, btn, "dice5", false, { style = "accent" })
  if dice_hovered then tooltip("Randomize all unlocked " .. side_key .. " corners") end
  if dice_clicked and seq_layering_randomize_side(slot, side_key) then
    changed = true
  end
  local verts_xy = {}
  local ax, ay, bx2, by2, cx, cy = seq_layering_tri_geom(x, y, w, h)
  verts_xy[1], verts_xy[2], verts_xy[3] = { ax, ay }, { bx2, by2 }, { cx, cy }

  -- Active blend drag, before drawing so the point tracks the mouse this
  -- frame. Shift moves it slowly; otherwise it snaps to the corners, edge
  -- midpoints and centre.
  if dragging then
    local drag = state.seq_layering_drag
    if r.ImGui_IsMouseDown(ctx, 0) then
      local tx, ty
      if seq_fine_drag_down() then
        local dx, dy = r.ImGui_GetMouseDelta(ctx)
        local opx, opy = seq_layer_point_from_bary(side.blend, ax, ay, bx2, by2, cx, cy)
        tx = (drag.px or opx) + (tonumber(dx) or 0) * SEQ_LAYER_FINE_SCALE
        ty = (drag.py or opy) + (tonumber(dy) or 0) * SEQ_LAYER_FINE_SCALE
        drag.snap = nil
      else
        tx, ty, drag.snap = seq_layering_snap_point(mx, my, ax, ay, bx2, by2, cx, cy, SEQ_LAYER_SNAP_PX)
      end
      local b = side.blend
      b[1], b[2], b[3] = seq_layer_barycentric(tx, ty, ax, ay, bx2, by2, cx, cy)
      drag.px, drag.py = seq_layer_point_from_bary(b, ax, ay, bx2, by2, cx, cy)
      seq_layering_sync_linked(slot, side_key)
      state.seq_layering_hover_side = side_key
      hot_side = true
    else
      state.seq_layering_drag = nil
      seq_layering_sync_linked(slot, side_key)
      changed = true
      dragging = false
    end
  end
  local colors, samples = {}, {}
  for i = 1, 3 do
    local vert = side.verts[i]
    samples[i] = vert.path and find_sample_by_path(vert.path) or nil
    colors[i] = vert.path and get_sample_dot_color(samples[i] or { path = vert.path }) or 0x5A6660FF
  end
  local bar_x1 = bx - 10.0
  local bar_w = math.min(96.0, bar_x1 - after_label)
  if bar_w > 24.0 then
    draw_weight_bar(dl, bar_x1 - bar_w, hy - 3.0, bar_w, 6.0, side, colors)
  end

  -- Triangle body: tinted with the blend of the corner colours, and each
  -- corner glows as strongly as its weight.
  local shapes = seq_layering_tri_shapes("tri_" .. side_key, ax, ay, bx2, by2, cx, cy)
  local mix_r, mix_g, mix_b, mix_w = 0.0, 0.0, 0.0, 0.0
  for i = 1, 3 do
    local wt = side.verts[i].path and (side.blend[i] or 0.0) or 0.0
    if wt > 0.0 then
      local c = colors[i]
      mix_r = mix_r + math.floor(c / 16777216) % 256 * wt
      mix_g = mix_g + math.floor(c / 65536) % 256 * wt
      mix_b = mix_b + math.floor(c / 256) % 256 * wt
      mix_w = mix_w + wt
    end
  end
  local body_col = 0x0D1611FF
  if mix_w > 0.001 then
    local tint = math.floor(mix_r / mix_w) * 16777216 + math.floor(mix_g / mix_w) * 65536 + math.floor(mix_b / mix_w) * 256 + 255
    body_col = seq_layer_col_mix(0x0D1611FF, tint, (hot_side or dragging) and 0.16 or 0.11)
  end
  seq_layering_convex_fill(dl, shapes.body, shapes.body_arr, body_col)
  for i = 1, 3 do
    local wt = side.blend[i] or 0.0
    if side.verts[i].path and wt > 0.002 then
      local j, k = (i % 3) + 1, ((i + 1) % 3) + 1
      local vi, vj, vk = verts_xy[i], verts_xy[j], verts_xy[k]
      for _, layer in ipairs({ { 0.66, 0.025 + 0.05 * wt }, { 0.44, 0.04 + 0.09 * wt }, { 0.24, 0.05 + 0.15 * wt } }) do
        local f = layer[1]
        r.ImGui_DrawList_AddTriangleFilled(dl, vi[1], vi[2],
          vi[1] + (vj[1] - vi[1]) * f, vi[2] + (vj[2] - vi[2]) * f,
          vi[1] + (vk[1] - vi[1]) * f, vi[2] + (vk[2] - vi[2]) * f,
          seq_layer_col_alpha(colors[i], layer[2]))
      end
    end
  end
  local px, py = seq_layer_point_from_bary(side.blend, ax, ay, bx2, by2, cx, cy)
  local glow_a = (hot_side or dragging) and 0.12 or 0.06
  for i = 3, 1, -1 do
    local g = shapes.glow[i]
    seq_layering_polyline(dl, g.pts, g.arr, seq_layer_col_alpha(side_col, glow_a * (4 - i)), true, 2.0 + i)
  end
  seq_layering_polyline(dl, shapes.body, shapes.body_arr,
    seq_layer_col_alpha(side_col, (hot_side or dragging) and 0.95 or 0.7), true, 1.8)

  -- Magnet points while the point is in play.
  if hot_side or dragging then
    local dot = seq_layer_col_alpha(0xFFFFFFFF, 0.22)
    r.ImGui_DrawList_AddCircleFilled(dl, (ax + bx2 + cx) / 3.0, (ay + by2 + cy) / 3.0, 2.2, dot, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, (ax + bx2) * 0.5, (ay + by2) * 0.5, 1.8, dot, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, (bx2 + cx) * 0.5, (by2 + cy) * 0.5, 1.8, dot, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, (cx + ax) * 0.5, (cy + ay) * 0.5, 1.8, dot, 8)
  end

  -- Blend point: weighted spokes to the corners, then the puck.
  for i = 1, 3 do
    local wt = side.blend[i] or 0.0
    if wt > 0.01 and side.verts[i].path then
      r.ImGui_DrawList_AddLine(dl, px, py, verts_xy[i][1], verts_xy[i][2],
        seq_layer_col_alpha(colors[i], 0.25 + 0.55 * wt), 1.0 + 3.0 * wt)
    end
  end
  local snap = dragging and state.seq_layering_drag.snap
  if snap then
    r.ImGui_DrawList_AddCircle(dl, snap[1], snap[2], 13.0, 0xFFFFFF66, 20, 1.2)
  end
  r.ImGui_DrawList_AddCircleFilled(dl, px, py, dragging and 17.0 or 13.0, seq_layer_col_alpha(side_col, dragging and 0.22 or 0.14), 24)
  r.ImGui_DrawList_AddCircleFilled(dl, px, py, 7.5, 0x0B0E0CFF, 18)
  r.ImGui_DrawList_AddCircle(dl, px, py, 7.5, 0xFFFFFFFF, 18, 2.0)
  r.ImGui_DrawList_AddCircleFilled(dl, px, py, 3.2, side_col, 12)

  -- Corners: node, weight arc, chip and the dice / lock / volume row.
  local controls_hot = dice_hovered or reset_hovered or menu_hovered
  local mini = 18.0
  local mini_gap = 3.0
  local row_w = mini * 3 + mini_gap * 2
  for i = 1, 3 do
    local vx, vy = verts_xy[i][1], verts_xy[i][2]
    local vert = side.verts[i]
    local wt = side.blend[i] or 0.0
    local pct = math.floor(wt * 100.0 + 0.5)
    local sample = samples[i]
    local col = colors[i]
    local vid = id .. "_" .. i

    -- Hit area for the node (preview, solo, menu, drag out).
    r.ImGui_SetCursorScreenPos(ctx, vx - 14.0, vy - 14.0)
    r.ImGui_InvisibleButton(ctx, "##seq_layer_vert_" .. vid, 28.0, 28.0)
    local node_hovered = r.ImGui_IsItemHovered(ctx)
    local node_clicked = r.ImGui_IsItemClicked(ctx, 0)
    local node_rclicked = r.ImGui_IsItemClicked(ctx, 1)

    -- Chip.
    -- Bottom chips each keep to their half of the card, centred under the
    -- corner when they fit.
    local base_mid = (bx2 + cx) * 0.5
    local lo, hi
    if i == 1 then
      lo, hi = x + 8.0, vx - 18.0
    elseif i == 2 then
      lo, hi = x + 8.0, base_mid - 5.0
    else
      lo, hi = base_mid + 5.0, x + w - 8.0
    end
    local chip_max = math.max(60.0, math.min(240.0, hi - lo))
    local cw = chip_width(vert, pct, chip_max)
    local chip_x, chip_cy
    if i == 1 then
      chip_x, chip_cy = hi - cw, vy
    else
      chip_x = math.max(lo, math.min(hi - cw, vx - cw * 0.5))
      chip_cy = vy + 26.0
    end
    r.ImGui_SetCursorScreenPos(ctx, chip_x, chip_cy - 10.0)
    r.ImGui_InvisibleButton(ctx, "##seq_layer_chip_" .. vid, cw, 20.0)
    local chip_hovered = r.ImGui_IsItemHovered(ctx)
    local chip_clicked = r.ImGui_IsItemClicked(ctx, 0)
    local chip_rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local item_hot = node_hovered or chip_hovered

    -- Node.
    local node_r = item_hot and 8.5 or 7.0
    r.ImGui_DrawList_AddCircle(dl, vx, vy, 12.0, 0xFFFFFF1C, 24, 2.4)
    if vert.path then
      seq_layering_arc(dl, vx, vy, 12.0, -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2.0 * wt, col, 2.6)
      r.ImGui_DrawList_AddCircleFilled(dl, vx, vy, node_r, col, 18)
      r.ImGui_DrawList_AddCircle(dl, vx, vy, node_r, 0xFFFFFFCC, 18, 1.3)
    else
      r.ImGui_DrawList_AddCircleFilled(dl, vx, vy, node_r, UI_THEME.surface, 18)
      r.ImGui_DrawList_AddCircle(dl, vx, vy, node_r, UI_THEME.text_mute, 18, 1.2)
      r.ImGui_DrawList_AddLine(dl, vx - 3.0, vy, vx + 3.0, vy, UI_THEME.text_dim, 1.2)
      r.ImGui_DrawList_AddLine(dl, vx, vy - 3.0, vx, vy + 3.0, UI_THEME.text_dim, 1.2)
    end
    if vert.locked then
      seq_layering_draw_glyph(dl, "lock", vx + 9.0, vy - 9.0, 11.0, 0xE8C070FF)
    end
    draw_vert_chip(dl, chip_x, chip_cy, chip_max, vert, pct, col, item_hot)

    -- Mini buttons.
    local row_x, row_y
    if i == 1 then
      row_x, row_y = vx + 18.0, vy - mini * 0.5
    else
      row_x = math.max(x + 8.0, math.min(x + w - 8.0 - row_w, vx - row_w * 0.5))
      row_y = chip_cy + 13.0
    end
    local d_clicked, d_hovered = seq_layering_icon_button("##seq_layer_dice_" .. vid, dl, row_x, row_y, mini, mini, "dice5", false,
      { rounding = 4.0, icon_scale = 1.05, color = vert.locked and UI_THEME.text_mute or nil })
    local l_clicked, l_hovered = seq_layering_icon_button("##seq_layer_lock_" .. vid, dl, row_x + mini + mini_gap, row_y, mini, mini,
      vert.locked and "g:lock" or "g:unlock", false,
      { rounding = 4.0, color = vert.locked and 0xE8C070FF or nil })
    local v_changed, v_hovered = seq_layering_vol_knob("##seq_layer_vol_" .. vid, dl, row_x + (mini + mini_gap) * 2, row_y, mini, vert)
    if d_hovered then
      tooltip(vert.locked and "Locked: unlock to randomize" or "Randomize this corner")
    elseif l_hovered then
      tooltip(vert.locked and "Unlock this corner" or "Lock this corner")
    end
    if d_clicked and seq_layering_randomize_vert(slot, side_key, i) then
      changed = true
    end
    if l_clicked then
      vert.locked = not vert.locked
      seq_layering_sync_linked(slot, side_key)
      changed = true
      audition = false
    end
    if v_changed then
      seq_layering_sync_linked(slot, side_key)
      state.seq_layering_vol_drag = true
    end
    if d_hovered or l_hovered or v_hovered or item_hot then
      controls_hot = true
    end

    -- Node / chip actions.
    if item_hot then
      local lines = {}
      lines[#lines + 1] = vert_display_name(vert) or "Empty corner: drag a sample here"
      if vert.path then
        lines[#lines + 1] = string.format("%d%% of the %s", pct, side_key)
        lines[#lines + 1] = "Click: play  ·  Double-click: solo  ·  Drag: drop elsewhere"
      end
      lines[#lines + 1] = "Right-click: more"
      tooltip(table.concat(lines, "\n"))
    end
    if (node_clicked or chip_clicked) and not sample_drag_active() then
      if dbl_clicked() and vert.path then
        seq_layering_solo_vert(slot, side_key, i)
        changed = true
      elseif sample then
        state.seq_layering_ab = nil
        preview_sample(sample)
      end
    end
    if node_rclicked or chip_rclicked then
      seq_layering_open_vert_menu(slot, side_key, i)
    end
    if sample and drag_out_should_start("vert_" .. vid, item_hot) then
      begin_waveform_sample_drag(sample)
    end

    -- Sample drops use screen-space hit tests so they still work when the
    -- map (or another window) has captured the mouse.
    seq_layering_store_vert_hit(side_key, i, vx, vy, vert.locked == true)
  end

  -- Start a blend drag (or even mix / side menu) inside the triangle.
  local inside = false
  do
    local rw, rv, ru = seq_layer_barycentric_raw(mx, my, ax, ay, bx2, by2, cx, cy)
    inside = rw >= -0.03 and rv >= -0.03 and ru >= -0.03
  end
  local win_hovered = state.seq_layering_hovered
  if not dragging and win_hovered and inside and not controls_hot and not sample_drag_active() then
    state.seq_layering_hover_side = side_key
    if r.ImGui_IsMouseClicked(ctx, 0) then
      if dbl_clicked() then
        seq_layering_even_mix(slot, side_key)
        changed = true
      else
        local tx, ty, snap = seq_layering_snap_point(mx, my, ax, ay, bx2, by2, cx, cy, SEQ_LAYER_SNAP_PX)
        local b = side.blend
        b[1], b[2], b[3] = seq_layer_barycentric(tx, ty, ax, ay, bx2, by2, cx, cy)
        local npx, npy = seq_layer_point_from_bary(b, ax, ay, bx2, by2, cx, cy)
        state.seq_layering_drag = { side = side_key, slot_id = slot.id, px = npx, py = npy, snap = snap }
        seq_layering_sync_linked(slot, side_key)
      end
    end
    if r.ImGui_IsMouseClicked(ctx, 1) then
      seq_layering_open_side_menu(slot, side_key)
    end
  end

  if state.seq_layering_vol_drag and not r.ImGui_IsMouseDown(ctx, 0) then
    state.seq_layering_vol_drag = nil
    changed = true
  end

  if changed then
    seq_layering_commit(slot, { audition = audition })
  end
end

-- ---------------------------------------------------------------------------
-- Centre column: link and split

function seq_layering_draw_bias(dl, slot, x, y, w, h, linked)
  if not slot or not dl then return end
  seq_normalize_slot_layers(slot)
  local bias = slot.layers.bias or 0.0
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##seq_layer_bias_" .. tostring(slot.id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local disabled = linked == true

  if not disabled then
    if hovered and dbl_clicked() then
      slot.layers.bias = 0.0
      state.seq_layering_bias_drag = nil
      seq_layering_commit(slot, { force_rebuild = true })
    elseif active then
      local dx = select(1, r.ImGui_GetMouseDelta(ctx))
      if dx and dx ~= 0.0 then
        state.seq_layering_bias_drag = true
        -- Left shortens the transient; right lengthens it.
        local scale = seq_fine_drag_down() and SEQ_FINE_DRAG_SCALE or 1.0
        bias = bias + dx * scale / math.max(36.0, w * 0.85)
        if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
        slot.layers.bias = bias
      end
    end
  end

  local mid_x = x + w * 0.5
  local u = ((slot.layers.bias or 0.0) + 1.0) * 0.5
  local thumb_x = x + 5.0 + u * math.max(1.0, w - 10.0)
  local t_col = SEQ_LAYER_SIDE_COLORS.transient
  local fill_col = disabled and 0x3A4A40FF or t_col
  local bg = (hovered or active) and not disabled and UI_THEME.surface_hvr or UI_THEME.surface
  local edge = (hovered or active) and not disabled and seq_layer_col_alpha(t_col, 0.8) or UI_THEME.border
  ui_draw_panel(dl, x, y, x + w, y + h, h * 0.5, bg, edge, hovered and not disabled, active and not disabled)
  r.ImGui_DrawList_AddLine(dl, mid_x, y + 4.0, mid_x, y + h - 4.0, 0xFFFFFF28, 1.0)
  if math.abs(thumb_x - mid_x) > 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, math.min(thumb_x, mid_x), y + h * 0.5 - 1.5, math.max(thumb_x, mid_x), y + h * 0.5 + 1.5,
      seq_layer_col_alpha(fill_col, 0.75), 1.5)
  end
  r.ImGui_DrawList_AddCircleFilled(dl, thumb_x, y + h * 0.5, h * 0.36, disabled and 0x3A4A40FF or 0xFFFFFFFF, 14)
  r.ImGui_DrawList_AddCircle(dl, thumb_x, y + h * 0.5, h * 0.36, fill_col, 14, 1.5)

  local caption = "SPLIT"
  r.ImGui_DrawList_AddText(dl, x + (w - text_w(caption)) * 0.5, y + h + 4.0,
    disabled and UI_THEME.text_mute or UI_THEME.text_dim, caption)
  if not disabled then
    local ms = string.format("%.0f ms", (seq_layering_split_sec(slot) or 0.0) * 1000.0)
    r.ImGui_DrawList_AddText(dl, x + (w - text_w(ms)) * 0.5, y + h + 19.0, t_col, ms)
  end

  if hovered then
    if disabled then
      tooltip("Unlink to split transient / sustain")
    else
      tooltip("Transient length\nLeft: shorter  ·  Right: longer  ·  Shift: fine\nDouble-click to reset  ·  Or drag the marker on the original")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Window

-- Drum-layering edits (blend drag, dice, lock, volume knobs, bias, link,
-- A/B output) mutate slot.layers directly. Open one undo session when a click
-- lands in the layering window (before any widget mutates) and close it once
-- all mouse buttons are released; unchanged sessions are dropped by end_seq_undo.
function seq_layering_undo_maybe_begin()
  if state.seq_layering_undo_owned or not state.seq_layering_hovered then
    return
  end
  if not r.ImGui_IsMouseClicked then
    return
  end
  if r.ImGui_IsMouseClicked(ctx, 0) or r.ImGui_IsMouseClicked(ctx, 1) then
    if seq_undo_own_begin("Edit drum layering", { lazy_reaper = true }) then
      state.seq_layering_undo_owned = true
    end
  end
end

function seq_layering_undo_maybe_end(force)
  if not state.seq_layering_undo_owned then
    return
  end
  if not force and r.ImGui_IsMouseDown
      and (r.ImGui_IsMouseDown(ctx, 0) or r.ImGui_IsMouseDown(ctx, 1)) then
    return
  end
  state.seq_layering_undo_owned = nil
  if seq_undo_is_open() then
    end_seq_undo()
  end
end

function seq_layering_close()
  state.seq_layering_slot_id = nil
  state.seq_layering_drag = nil
  state.seq_layering_hover_side = nil
  state.seq_layering_hovered = false
  state.seq_layering_rect = nil
  state.seq_layering_vert_hits = nil
  state.seq_layering_drop_vert = nil
  state.seq_layering_bias_drag = nil
  state.seq_layering_vol_drag = nil
  state.seq_layering_move = nil
end

-- Segmented two-way switch; returns the clicked key, if any.
local function draw_segmented(dl, id, x, y, h, items, current)
  local widths, total = {}, 0.0
  for i, it in ipairs(items) do
    widths[i] = text_w(it.label) + 18.0
    total = total + widths[i]
  end
  ui_draw_panel(dl, x, y, x + total + 4.0, y + h, h * 0.5, UI_THEME.surface, UI_THEME.border, false, false)
  local cx = x + 2.0
  local picked = nil
  for i, it in ipairs(items) do
    local sw = widths[i]
    r.ImGui_SetCursorScreenPos(ctx, cx, y + 2.0)
    local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id .. "_" .. it.key, sw, h - 4.0)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local sel = current == it.key
    if sel then
      r.ImGui_DrawList_AddRectFilled(dl, cx, y + 2.0, cx + sw, y + h - 2.0, 0x145028FF, (h - 4.0) * 0.5)
      r.ImGui_DrawList_AddRect(dl, cx + 0.5, y + 2.5, cx + sw - 0.5, y + h - 2.5, UI_THEME.accent, (h - 4.0) * 0.5, 0, 1.0)
    elseif hovered then
      r.ImGui_DrawList_AddRectFilled(dl, cx, y + 2.0, cx + sw, y + h - 2.0, UI_THEME.surface_hvr, (h - 4.0) * 0.5)
    end
    r.ImGui_DrawList_AddText(dl, cx + 9.0, y + h * 0.5 - 7.0, sel and 0xFFFFFFFF or (hovered and UI_THEME.text or UI_THEME.text_dim), it.label)
    if hovered and it.tip then
      tooltip(it.tip)
    end
    if clicked then
      picked = it.key
    end
    cx = cx + sw
  end
  return picked, total + 4.0
end

-- Title row: icon tile, title, track chip, output switch, auto-play, close.
-- Dragging empty header space moves the window.
function seq_layering_header(dl, slot, x, y, w)
  local h = SEQ_LAYER_HEADER_H
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + h, y + h, UI_THEME.accent_fill, UI_METRICS.radius_ctrl)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + h - 0.5, y + h - 0.5, 0x1EFF5E44, UI_METRICS.radius_ctrl, 0, 1.0)
  seq_layering_draw_glyph(dl, "triangle", x + h * 0.5, y + h * 0.5 + 1.0, h, UI_THEME.accent)
  local title = "Drum Layering"
  local tw = text_w(title)
  local tx = x + h + 9.0
  r.ImGui_DrawList_AddText(dl, tx, y + h * 0.5 - 7.0, UI_THEME.text, title)
  r.ImGui_DrawList_AddText(dl, tx + 0.5, y + h * 0.5 - 7.0, UI_THEME.text, title)

  -- Right side, right to left.
  local close_s = 20.0
  local rx = x + w - close_s
  r.ImGui_SetCursorScreenPos(ctx, rx, y + (h - close_s) * 0.5)
  if draw_ui_button("seq_layer_close", nil, close_s, close_s, { icon = "close", compact = true }) then
    seq_layering_close()
    return
  end
  if r.ImGui_IsItemHovered(ctx) then tooltip("Close (Esc)") end

  local auto = seq_layering_auto_audition()
  local auto_w = text_w("Auto-play") + 34.0
  rx = rx - 8.0 - auto_w
  r.ImGui_SetCursorScreenPos(ctx, rx, y + 3.0)
  if draw_ui_button("seq_layer_auto", "Auto-play", auto_w, h - 6.0, {
    compact = true, pill = true, selected = auto, lead_icon = "play",
    lead_color = auto and UI_THEME.accent or nil,
  }) then
    seq_layering_set_auto_audition(not auto)
  end
  if r.ImGui_IsItemHovered(ctx) then
    tooltip(auto and "Auto-play is on: the layered mix plays after each change" or "Play the layered mix after each change")
  end

  local items = {
    { key = "original", label = "Original", tip = "The track plays its own sample" },
    { key = "layered", label = "Layered", tip = "The track plays the layered mix" },
  }
  local seg_w = 0.0
  for _, it in ipairs(items) do seg_w = seg_w + text_w(it.label) + 18.0 end
  seg_w = seg_w + 4.0
  rx = rx - 10.0 - seg_w
  local out_caption = "OUTPUT"
  local ocw = text_w(out_caption)
  local picked = draw_segmented(dl, "seq_layer_output", rx, y + 2.0, h - 4.0, items, seq_layering_output(slot))
  r.ImGui_DrawList_AddText(dl, rx - 8.0 - ocw, y + h * 0.5 - 7.0, UI_THEME.text_mute, out_caption)
  if picked and picked ~= seq_layering_output(slot) then
    seq_layering_set_output(slot, picked)
  end

  -- Track chip between the title and the controls.
  local chip_x = tx + tw + 12.0
  local chip_max = (rx - 16.0 - ocw) - chip_x - 14.0
  if chip_max > 30.0 then
    draw_pill(dl, chip_x, y + h * 0.5, truncate(slot.name or "Track", chip_max), UI_THEME.surface, UI_THEME.border, UI_THEME.text_dim, 20.0)
  end

  -- Move handle over the whole row, submitted last so the controls keep their
  -- clicks (the first item under the mouse owns the hover).
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##seq_layer_move", w, h)
  if r.ImGui_IsItemActive(ctx) then
    local dx, dy = r.ImGui_GetMouseDelta(ctx)
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    local rect = state.seq_layering_rect
    if rect and (dx ~= 0 or dy ~= 0) then
      state.seq_layering_move = { x = rect.x + dx, y = rect.y + dy }
    end
  end
end

function render_seq_layering_window()
  seq_layering_undo_maybe_end()
  if not state.seq_layering_slot_id then
    state.seq_layering_hover_side = nil
    state.seq_layering_hovered = false
    state.seq_layering_rect = nil
    state.seq_layering_vert_hits = nil
    state.seq_layering_drop_vert = nil
    return
  end
  local slot = find_seq_track_by_id(state.seq_layering_slot_id)
  if not slot then
    state.seq_layering_slot_id = nil
    state.seq_layering_vert_hits = nil
    state.seq_layering_drop_vert = nil
    return
  end
  seq_layering_seed_from_track(slot)

  local pad_x, pad_y = 12.0, 10.0
  local stored_w = tonumber(state.seq_layering_win_w) or 800
  stored_w = math.max(SEQ_LAYER_MIN_W, math.min(1240, stored_w))
  local ideal_h = seq_layering_ideal_content_h(stored_w - pad_x * 2.0) + pad_y * 2.0
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, SEQ_LAYER_MIN_W, 360.0, 1240.0, 1400.0)
  end
  r.ImGui_SetNextWindowSize(ctx, stored_w, ideal_h,
    r.ImGui_Cond_Always and r.ImGui_Cond_Always() or r.ImGui_Cond_FirstUseEver())
  local move = state.seq_layering_move
  if move and r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, move.x, move.y, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
    state.seq_layering_move = nil
  end

  local flags = 0
  for _, getter in ipairs({
    r.ImGui_WindowFlags_NoTitleBar, r.ImGui_WindowFlags_NoCollapse, r.ImGui_WindowFlags_NoDocking,
    r.ImGui_WindowFlags_NoScrollbar, r.ImGui_WindowFlags_NoScrollWithMouse,
  }) do
    if getter then flags = flags | getter() end
  end
  local pushed_pad = false
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), pad_x, pad_y)
    pushed_pad = true
  end
  local title = "Drum Layering — " .. (slot.name or "Track")
  local began_ok, visible, open = pcall(r.ImGui_Begin, ctx, title .. "###seq_layering_window", true, flags)
  if pushed_pad then
    r.ImGui_PopStyleVar(ctx, 1)
  end
  if not began_ok then
    if log then log("Drum layering Begin failed: " .. tostring(visible)) end
    return
  end
  if open == false then
    seq_layering_close()
  end

  if visible then
    if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize then
      local x, y = r.ImGui_GetWindowPos(ctx)
      local w, h = r.ImGui_GetWindowSize(ctx)
      state.seq_layering_rect = {
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        w = tonumber(w) or 0,
        h = tonumber(h) or 0,
      }
    end
    local hover_flags = 0
    if r.ImGui_HoveredFlags_RootAndChildWindows then
      hover_flags = r.ImGui_HoveredFlags_RootAndChildWindows()
    end
    state.seq_layering_hovered = r.ImGui_IsWindowHovered
        and r.ImGui_IsWindowHovered(ctx, hover_flags)
        or false
    seq_layering_undo_maybe_begin()
    local body_ok, body_err = pcall(seq_layering_render_body, slot)
    if not body_ok and log then
      log("Drum layering draw error: " .. tostring(body_err))
    end
    seq_layering_undo_maybe_end()

    -- Esc closes unless a text field or popup has the keyboard.
    if state.seq_layering_slot_id and r.ImGui_IsWindowFocused
        and r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0)
        and not (r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx))
        and not (r.ImGui_IsPopupOpen and r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId and r.ImGui_PopupFlags_AnyPopupId() or 0))
        and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      seq_layering_close()
    end
    pcall(r.ImGui_End, ctx)
  else
    state.seq_layering_hovered = false
  end
end

function seq_layering_render_body(slot)
  local prev_hover = state.seq_layering_hover_side
  state.seq_layering_prev_hover = prev_hover
  state.seq_layering_hover_side = nil
  state.seq_layering_vert_hits = {}
  if not sample_drag_active() then
    state.seq_layering_drop_vert = nil
  end

  seq_normalize_slot_layers(slot)
  local linked = slot.layers.linked == true
  local dl = r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx)
  if not dl and r.ImGui_GetForegroundDrawList then
    dl = r.ImGui_GetForegroundDrawList(ctx)
  end
  if not dl then
    return
  end
  local avail_w = tonumber((r.ImGui_GetContentRegionAvail(ctx))) or 700
  if avail_w < 300 then avail_w = 300 end
  if r.ImGui_GetWindowSize then
    local win_w = tonumber((r.ImGui_GetWindowSize(ctx)))
    if win_w and win_w > 0 then
      state.seq_layering_win_w = win_w
    end
  end
  local wx, wy = r.ImGui_GetCursorScreenPos(ctx)
  wx, wy = tonumber(wx) or 0, tonumber(wy) or 0

  seq_layering_header(dl, slot, wx, wy, avail_w)
  if not state.seq_layering_slot_id then
    return
  end
  local y = wy + SEQ_LAYER_HEADER_H + 8.0

  -- A/B cards.
  seq_layering_draw_wave_pane(dl, slot, wx, y, avail_w, SEQ_LAYER_PANE_H, "original", prev_hover)
  seq_layering_draw_wave_pane(dl, slot, wx, y + SEQ_LAYER_PANE_H + SEQ_LAYER_WAVE_GAP, avail_w, SEQ_LAYER_PANE_H, "layered", prev_hover)
  y = y + SEQ_LAYER_WAVE_H

  -- Triangle cards with the link / split column between them.
  local col_w = seq_layering_col_w(avail_w)
  local card_h = seq_layering_card_h(col_w)
  for _, spec in ipairs({ { "transient", wx }, { "sustain", wx + col_w + SEQ_LAYER_LINK_W } }) do
    local ok, err = pcall(seq_layering_draw_triangle, dl, slot, spec[1], spec[2], y, col_w, card_h)
    if not ok and log then
      log("Drum layering triangle error: " .. tostring(err))
    end
  end
  if sample_drag_active() then
    seq_layering_resolve_drop_vert()
    seq_layering_draw_vert_drop_cues(dl)
  end

  local mid_x = wx + col_w
  local link_sz = 30.0
  local bias_w, bias_h = 62.0, 16.0
  local cluster_h = link_sz + 22.0 + bias_h + 36.0
  local link_y = y + math.max(8.0, (card_h - cluster_h) * 0.5)
  local link_x = mid_x + (SEQ_LAYER_LINK_W - link_sz) * 0.5
  -- Rails from the link to each card.
  local rail_y = link_y + link_sz * 0.5
  local rail_col = linked and seq_layer_col_alpha(UI_THEME.accent, 0.6) or UI_THEME.border
  r.ImGui_DrawList_AddLine(dl, mid_x + 2.0, rail_y, link_x - 3.0, rail_y, rail_col, 1.0)
  r.ImGui_DrawList_AddLine(dl, link_x + link_sz + 3.0, rail_y, mid_x + SEQ_LAYER_LINK_W - 2.0, rail_y, rail_col, 1.0)
  r.ImGui_SetCursorScreenPos(ctx, link_x, link_y)
  if draw_ui_button("seq_layer_link_" .. slot.id, nil, link_sz, link_sz, {
    icon = "link",
    style = linked and "accent" or "default",
    selected = linked,
  }) then
    seq_layering_set_linked(slot, not linked)
    seq_layering_commit(slot)
    linked = not linked
  end
  if r.ImGui_IsItemHovered(ctx) then
    tooltip(linked
      and "Unlink transient and sustain"
      or "Link transient and sustain: use whole samples, no split")
  end
  local link_caption = linked and "LINKED" or "LINK"
  r.ImGui_DrawList_AddText(dl, mid_x + (SEQ_LAYER_LINK_W - text_w(link_caption)) * 0.5, link_y + link_sz + 4.0,
    linked and UI_THEME.accent or UI_THEME.text_dim, link_caption)
  local bias_x = mid_x + (SEQ_LAYER_LINK_W - bias_w) * 0.5
  local bias_y = link_y + link_sz + 26.0
  seq_layering_draw_bias(dl, slot, bias_x, bias_y, bias_w, bias_h, linked)
  if state.seq_layering_bias_drag and not r.ImGui_IsMouseDown(ctx, 0) then
    state.seq_layering_bias_drag = nil
    seq_layering_commit(slot, { force_rebuild = true })
  end

  -- Footer.
  local foot_y = y + card_h + 6.0
  r.ImGui_DrawList_AddText(dl, wx + 2.0, foot_y, UI_THEME.text_mute, truncate(
    "Drag the point to blend  ·  Shift: fine  ·  Double-click: even mix  ·  Double-click a corner: solo  ·  Right-click: more",
    avail_w - 4.0))

  r.ImGui_SetCursorScreenPos(ctx, wx, wy)
  r.ImGui_Dummy(ctx, avail_w, (foot_y + 16.0) - wy)

  seq_layering_render_menus(slot)
end

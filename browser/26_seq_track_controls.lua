-- Sample Map Browser module: seq_track_controls
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- Horizontal rectangular drag control (volume / pan style).
-- Drag vertically to adjust (like a compact fader); shows fill for volume or
-- a bipolar marker for pan when bipolar=true.
function seq_rect_drag_control(id, dl, x, y, w, h, value, min_v, max_v, opts)
  opts = opts or {}
  w = math.max(18.0, w or 44.0)
  h = math.max(12.0, h or 16.0)
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if max_v <= min_v then max_v = min_v + 1.0 end
  value = math.max(min_v, math.min(max_v, value or min_v))
  local entry_value = value

  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, w, h)
  local active = r.ImGui_IsItemActive(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local fine = seq_fine_drag_down()
  local changed = false
  local reset = opts.reset
  if reset == nil then
    reset = opts.unity
  end

  local drag = state.seq_rect_drag
  if reset ~= nil and hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    value = math.max(min_v, math.min(max_v, reset))
    changed = math.abs(value - entry_value) > (max_v - min_v) * 1e-7
    -- Hold the reset value until the button is released, so the second
    -- click of the double-click doesn't start a drag away from it.
    state.seq_rect_drag = { id = id, hold = true }
  elseif active and drag and drag.id == id and drag.hold then
    -- Reset done; ignore the rest of this press.
  elseif active then
    local mx, my = r.ImGui_GetMousePos(ctx)
    mx, my = mx or x, my or y
    if (not drag) or drag.id ~= id then
      state.seq_rect_drag = { id = id, start_value = value, start_my = my, start_mx = mx, fine = fine }
      drag = state.seq_rect_drag
    end
    if drag.fine ~= fine then
      drag.start_value = value
      drag.start_my = my
      drag.start_mx = mx
      drag.fine = fine
    end
    local span = max_v - min_v
    local scale = fine and SEQ_FINE_DRAG_SCALE or 1.0
    if opts.horizontal then
      -- Relative drag: a click alone never moves the value, so clicks and
      -- double-clicks don't jump the fader to the pointer.
      local start_t = opts.to_pos and opts.to_pos(drag.start_value or value)
        or (((drag.start_value or value) - min_v) / span)
      local t = start_t + (mx - (drag.start_mx or mx)) / math.max(1.0, w) * scale
      t = math.max(0.0, math.min(1.0, t))
      if math.abs(mx - (drag.start_mx or mx)) < 0.5 then
        value = drag.start_value or value
      elseif opts.from_pos then
        value = opts.from_pos(t)
      else
        value = min_v + t * span
      end
      value = math.max(min_v, math.min(max_v, value))
    else
      local sensitivity = span / 120.0 * scale
      local drag_y = my - (drag.start_my or my)
      value = (drag.start_value or value) - drag_y * sensitivity
      value = math.max(min_v, math.min(max_v, value))
    end
    -- Only report a change when the value actually moved this frame.
    changed = math.abs(value - entry_value) > (max_v - min_v) * 1e-7
  elseif state.seq_rect_drag and state.seq_rect_drag.id == id then
    state.seq_rect_drag = nil
  end

  seq_draw_fader(dl, x, y, w, h, value, min_v, max_v, opts, hovered, active)
  return changed, value, active or hovered
end

-- Fader look shared by the track volume / pan bars and the MIDI range bars:
-- a dark well, a translucent fill with a bright cap at the value, and the
-- value text (right-aligned next to an optional leading icon).
function seq_draw_fader(dl, x, y, w, h, value, min_v, max_v, opts, hovered, active)
  local fill = opts.fill_color or UI_THEME.accent
  local fr, fg, fb = extract_rgb_rrgbbaa(fill)
  local rounding = math.min(5.0, h * 0.32)
  local well = active and ui_tc(0x08090CFF) or (hovered and ui_tc(0x141518FF) or ui_tc(0x0C0D10FF))
  local edge = active and fill or (hovered and UI_THEME.border_hvr or UI_THEME.border)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, well, rounding)

  local t
  if opts.to_pos then
    t = opts.to_pos(value)
  else
    t = (value - min_v) / (max_v - min_v)
  end
  if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
  local ix0, ix1 = x + 1.5, x + w - 1.5
  local iy0, iy1 = y + 1.5, y + h - 1.5
  local iw = ix1 - ix0
  local fill_a = (hovered or active) and 92 or 64
  local body = build_color_rrgbbaa(fr, fg, fb, fill_a)
  local sheen = build_color_rrgbbaa(fr, fg, fb, math.floor(fill_a * 0.55))
  local cap = build_color_rrgbbaa(fr, fg, fb, (hovered or active) and 255 or 215)
  local vx = ix0 + t * iw
  local f0, f1
  if opts.bipolar then
    local mid = ix0 + iw * 0.5
    f0, f1 = math.min(mid, vx), math.max(mid, vx)
    r.ImGui_DrawList_AddLine(dl, mid, iy0 + 1.0, mid, iy1 - 1.0, 0xFFFFFF30, 1.0)
  else
    f0, f1 = ix0, vx
  end
  if f1 - f0 > 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, f0, iy0, f1, iy1, body, math.max(0.0, rounding - 1.5))
    r.ImGui_DrawList_AddRectFilled(dl, f0, iy0, f1, iy0 + (iy1 - iy0) * 0.45, sheen, math.max(0.0, rounding - 1.5))
  end
  if not opts.bipolar and opts.unity and opts.unity >= min_v and opts.unity <= max_v then
    local ut = opts.to_pos and opts.to_pos(opts.unity) or ((opts.unity - min_v) / (max_v - min_v))
    local ux = ix0 + math.max(0.0, math.min(1.0, ut)) * iw
    r.ImGui_DrawList_AddLine(dl, ux, y + 1.0, ux, y + 3.5, 0xFFFFFF70, 1.0)
    r.ImGui_DrawList_AddLine(dl, ux, y + h - 3.5, ux, y + h - 1.0, 0xFFFFFF70, 1.0)
  end
  local cap_w = (hovered or active) and 2.5 or 2.0
  local cx0 = math.max(ix0, math.min(ix1 - cap_w, vx - cap_w * 0.5))
  r.ImGui_DrawList_AddRectFilled(dl, cx0, iy0, cx0 + cap_w, iy1, cap, 1.0)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, edge, rounding, 0, 1.0)

  local display = nil
  if opts.format_value then
    display = opts.format_value(value)
  elseif opts.value_text and opts.value_text ~= "" then
    display = opts.value_text
  end
  local icon_w = 0.0
  if opts.icon and w >= 54.0 and h >= 12.0 then
    icon_w = math.min(h, 16.0)
    local icon_col = (hovered or active) and UI_THEME.text or UI_THEME.text_dim
    ui_button_draw_icon(dl, opts.icon, x + 2.0 + icon_w * 0.5, y + h * 0.5, icon_w, icon_col)
  end
  if display and display ~= "" then
    if opts.unit and w >= (opts.unit_min_w or 74.0) then
      display = display .. opts.unit
    end
    local tw, th = r.ImGui_CalcTextSize(ctx, display)
    local tx
    if icon_w > 0 then
      tx = x + w - tw - 5.0
      tx = math.max(x + icon_w + 3.0, tx)
    else
      tx = x + (w - tw) * 0.5
    end
    local ty = y + (h - th) * 0.5
    local txt = (hovered or active) and 0xFFFFFFFF or ui_tc(0xE0E1E5FF)
    r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x00000099, display)
    r.ImGui_DrawList_AddText(dl, tx, ty, txt, display)
  end
end

function seq_layout_hit(box, mx, my)
  return box and (box.w or 0) > 0.5 and (box.h or 0) > 0.5
    and mx >= box.x and mx < box.x1 and my >= box.y and my < box.y1
end

function seq_set_candidate_drop(slot, idx)
  idx = tonumber(idx)
  if not slot or not idx then
    return
  end
  state.seq_candidate_drop = { slot_id = slot.id, idx = idx }
  state.seq_drop_target_idx = nil
  state.seq_drum_drop = nil
  state.seq_timeline_drop_time = nil
  state.seq_timeline_drop_track_idx = nil
end

function seq_track_nav_width(lane_h)
  local icon_size = seq_icon_size_for_lane_h(lane_h)
  return get_seq_track_sample_controls_width(seq_ctrl_size_for_icon(icon_size), icon_size)
end

-- Space between control groups ([M S] | vol pan | MIDI layering overlap).
-- Buttons inside a group touch, so the groups read as segmented pills.
SEQ_TCP_GROUP_GAP = 6.0

function seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
  return (btn or 14) * 4 + (vol_w or 52) + (pan_w or 40) + (midi_w or 28)
    + (gap or 3) + SEQ_TCP_GROUP_GAP * 2
end

-- Hundreds of these are built per frame. `if not (w > 0) then w = 0 end` is
-- math.max(0, w or 0) without the library calls: it keeps w when positive and
-- gives the integer 0 otherwise (also for 0.0, -0.0 and NaN), as math.max(0, w)
-- returns its first argument unless the second is larger.
function seq_box(x, y, w, h)
  w = w or 0
  if not (w > 0) then w = 0 end
  h = h or 0
  if not (h > 0) then h = 0 end
  return { x = x, y = y, w = w, h = h, x1 = x + w, y1 = y + h }
end

function seq_fit_mix_strip(avail_w, btn, gap, vol_w, pan_w, midi_w)
  vol_w = vol_w or 52.0
  pan_w = pan_w or 40.0
  midi_w = midi_w or 28.0
  btn = btn or 14.0
  gap = gap or 3.0
  while seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w) > avail_w do
    if vol_w > 34 then
      vol_w = vol_w - 2
    elseif pan_w > 26 then
      pan_w = pan_w - 2
    elseif midi_w > 22 then
      midi_w = midi_w - 2
    elseif btn > 12 then
      btn = btn - 1
    else
      break
    end
  end
  return btn, vol_w, pan_w, midi_w, seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
end

-- One row: [M S]  [vol] [pan]  [MIDI layering overlap]
function seq_place_mix_strip(layout, x, y, btn, gap, vol_w, pan_w, midi_w, row_h)
  local by = y + (row_h - btn) * 0.5
  layout.mute = seq_box(x, by, btn, btn)
  x = x + btn
  layout.solo = seq_box(x, by, btn, btn)
  x = x + btn + SEQ_TCP_GROUP_GAP
  layout.vol = seq_box(x, y, vol_w, row_h)
  x = x + vol_w + gap
  layout.pan = seq_box(x, y, pan_w, row_h)
  x = x + pan_w + SEQ_TCP_GROUP_GAP
  layout.midi = seq_box(x, by, midi_w, btn)
  x = x + midi_w
  layout.gear = seq_box(x, by, btn, btn)
  x = x + btn
  layout.overlap = seq_box(x, by, btn, btn)
  return layout.overlap.x1
end

function seq_candidate_log_unit(value, lo, hi)
  lo = lo or 0.03
  hi = hi or 1.0
  if type(value) ~= "number" or value <= 0 or hi <= lo then
    return 0.5
  end
  value = math.max(lo, math.min(hi, value))
  return (math.log(value) - math.log(lo)) / (math.log(hi) - math.log(lo))
end

function seq_candidate_freq_hue(freq)
  -- Log map so kick-band differences (60 vs 180 vs 400 Hz) actually move hue.
  freq = tonumber(freq) or 440.0
  freq = math.max(40.0, math.min(10000.0, freq))
  return seq_candidate_log_unit(freq, 40.0, 10000.0) * 210.0
end

function seq_candidate_unit_in_range(value, lo, hi, fallback)
  if type(value) ~= "number" or type(lo) ~= "number" or type(hi) ~= "number" then
    return fallback or 0.5
  end
  if hi - lo < 1e-6 then
    return fallback or 0.5
  end
  return math.max(0.0, math.min(1.0, (value - lo) / (hi - lo)))
end

local function chip_num(sample, entry, key, fallback)
  if sample and type(sample[key]) == "number" then
    return sample[key]
  end
  if entry and type(entry[key]) == "number" then
    return entry[key]
  end
  return fallback
end

-- seq_candidate_chip_props as four values (freq, brightness, weight,
-- duration), without building the table.
local function candidate_chip_props4(entry)
  local sample = entry and entry.path and find_sample_by_path(entry.path) or nil
  local dur = nil
  if sample and sample_map_duration then
    dur = sample_map_duration(sample)
  end
  if type(dur) ~= "number" or dur <= 0 then
    dur = chip_num(sample, entry, "effective_duration", chip_num(sample, entry, "duration", nil))
  end
  return chip_num(sample, entry, "dominant_freq", 440.0),
    chip_num(sample, entry, "brightness", nil),
    math.max(0.0, math.min(1.0, chip_num(sample, entry, "sub_weight", 0.45))),
    dur
end

function seq_candidate_chip_props(entry)
  local freq, brightness, weight, duration = candidate_chip_props4(entry)
  return {
    freq = freq,
    brightness = brightness,
    weight = weight,
    duration = duration,
  }
end

-- seq_candidate_slot_scale after its seq_normalize_slot_candidates.
local function candidate_slot_scale_normalized(slot)
  local n = 0
  local b_lo, b_hi = 1e9, -1e9
  local w_lo, w_hi = 1e9, -1e9
  local d_lo, d_hi = 1e9, -1e9
  local list = slot.sample_candidates
  if type(list) ~= "table" then
    return nil
  end
  for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
    local entry = list[i]
    if seq_candidate_entry_taken(entry) then
      local freq, brightness, weight, duration = candidate_chip_props4(entry)
      local bright = brightness or freq
      n = n + 1
      if type(bright) == "number" then
        b_lo = math.min(b_lo, bright)
        b_hi = math.max(b_hi, bright)
      end
      w_lo = math.min(w_lo, weight)
      w_hi = math.max(w_hi, weight)
      if type(duration) == "number" and duration > 0 then
        d_lo = math.min(d_lo, duration)
        d_hi = math.max(d_hi, duration)
      end
    end
  end
  if n < 2 then
    return nil
  end
  return {
    bright_lo = b_lo, bright_hi = b_hi,
    weight_lo = w_lo, weight_hi = w_hi,
    dur_lo = d_lo, dur_hi = d_hi,
  }
end

function seq_candidate_slot_scale(slot)
  if not slot then
    return nil
  end
  seq_normalize_slot_candidates(slot)
  return candidate_slot_scale_normalized(slot)
end

function seq_candidate_hsv_to_color(h, s, v, a)
  h = ((tonumber(h) or 0) % 360.0 + 360.0) % 360.0
  s = math.max(0.0, math.min(1.0, tonumber(s) or 0.7))
  v = math.max(0.0, math.min(1.0, tonumber(v) or 0.7))
  a = math.max(0, math.min(255, math.floor((tonumber(a) or 1.0) * 255 + 0.5)))
  local c = v * s
  local hp = h / 60.0
  local x = c * (1.0 - math.abs(hp % 2.0 - 1.0))
  local m = v - c
  local r, g, b = 0, 0, 0
  if hp < 1 then
    r, g, b = c, x, 0
  elseif hp < 2 then
    r, g, b = x, c, 0
  elseif hp < 3 then
    r, g, b = 0, c, x
  elseif hp < 4 then
    r, g, b = 0, x, c
  elseif hp < 5 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end
  return build_color_rrgbbaa(
    math.floor((r + m) * 255 + 0.5),
    math.floor((g + m) * 255 + 0.5),
    math.floor((b + m) * 255 + 0.5),
    a
  )
end

function seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, top_y, name_h, expand_w, gap)
  layout.expand = seq_box(inner_x0, top_y, expand_w, name_h)
  local name_x = inner_x0 + expand_w
  local name_w = math.max(0.0, inner_x1 - name_x)
  local cand = seq_place_sample_candidates(slot, inner_x1, top_y, top_y + name_h, math.max(0.0, name_w - 36.0))
  if cand.w > 0 then
    layout.candidates = cand.hit
    layout.candidate_boxes = cand.boxes
    name_w = math.max(0.0, cand.hit.x - (gap or 3.0) - name_x)
  end
  layout.name = seq_box(name_x, top_y, name_w, name_h)
end

local function candidate_grid_dims(size, n, r, gap)
  r = math.max(1, r)
  local c = math.ceil(n / r)
  return r, c, c * size + (c - 1) * gap, math.min(n, r) * size + (math.min(n, r) - 1) * gap
end

local function candidate_place_empty()
  return { boxes = {}, w = 0, hit = seq_box(0, 0, 0, 0), sq = 0 }
end

function seq_place_sample_candidates(slot, x1, y0, y1, max_w)
  x1, y0, y1 = x1 or 0, y0 or 0, y1 or 0
  max_w = max_w or 0
  local avail_h = y1 - y0
  if avail_h < 12.0 or max_w < 12.0 then
    return candidate_place_empty()
  end
  local gap = 2.0
  local count = seq_candidate_visible_count(slot)
  local sq = math.max(12.0, math.min(avail_h, 24.0))
  local rows = 1
  local cols = count
  local _, _, grid_w, grid_h = candidate_grid_dims(sq, count, rows, gap)
  if grid_w > max_w then
    local rows_fit = math.max(1, math.floor((avail_h + gap) / (sq + gap)))
    if rows_fit > 1 then
      rows = math.min(rows_fit, count)
      _, cols, grid_w, grid_h = candidate_grid_dims(sq, count, rows, gap)
    end
  end
  while grid_w > max_w and sq > 12.0 do
    sq = sq - 1.0
    _, cols, grid_w, grid_h = candidate_grid_dims(sq, count, rows, gap)
  end
  if grid_w > max_w then
    local fit_cols = math.max(1, math.floor((max_w + gap) / (sq + gap)))
    count = math.max(1, math.min(count, fit_cols * rows))
    rows, cols, grid_w, grid_h = candidate_grid_dims(sq, count, rows, gap)
  end
  if grid_w > max_w or grid_w <= 0 then
    return candidate_place_empty()
  end
  local left = x1 - grid_w
  local top = y0 + (avail_h - grid_h) * 0.5
  local boxes = {}
  local i = 1
  for row = 1, rows do
    for col = 1, cols do
      if i > count then
        break
      end
      boxes[i] = seq_box(left + (col - 1) * (sq + gap), top + (row - 1) * (sq + gap), sq, sq)
      i = i + 1
    end
  end
  return {
    boxes = boxes,
    w = grid_w,
    hit = seq_box(left, top, grid_w, grid_h),
    sq = sq,
  }
end

-- Candidate chip colours are pure functions of a few numbers that stay the
-- same frame after frame, so they are memoized (bounded; cleared when full).
-- Only non-NaN float inputs and integer colours are used as keys, so a hit
-- is the value the function returns for exactly those arguments. (0.0 and
-- -0.0 share a key; every memoized function clamps both to the same value.)
local math_type = math.type
local cand_color_memo = { hsv = {}, bands = {}, hue = {}, bright = {}, n = 0 }

local function candidate_memo_room()
  local m = cand_color_memo
  if m.n >= 2048 then
    m.hsv, m.bands, m.hue, m.bright, m.n = {}, {}, {}, {}, 0
  end
  m.n = m.n + 1
end

-- = seq_candidate_freq_hue(freq)
local function candidate_freq_hue(freq)
  if math_type(freq) ~= "float" or freq ~= freq then
    return seq_candidate_freq_hue(freq)
  end
  local hue = cand_color_memo.hue[freq]
  if hue == nil then
    hue = seq_candidate_freq_hue(freq)
    candidate_memo_room()
    cand_color_memo.hue[freq] = hue
  end
  return hue
end

-- = seq_candidate_log_unit(value, 100.0, 2500.0)
local function candidate_bright_unit(value)
  if math_type(value) ~= "float" or value ~= value then
    return seq_candidate_log_unit(value, 100.0, 2500.0)
  end
  local u = cand_color_memo.bright[value]
  if u == nil then
    u = seq_candidate_log_unit(value, 100.0, 2500.0)
    candidate_memo_room()
    cand_color_memo.bright[value] = u
  end
  return u
end

-- = seq_candidate_hsv_to_color(h, s, v, a)
local function candidate_hsv_color(h, s, v, a)
  if math_type(h) ~= "float" or math_type(s) ~= "float" or math_type(v) ~= "float" or math_type(a) ~= "float"
      or h ~= h or s ~= s or v ~= v or a ~= a then
    return seq_candidate_hsv_to_color(h, s, v, a)
  end
  local m1 = cand_color_memo.hsv[h]
  local m2 = m1 and m1[s]
  local m3 = m2 and m2[v]
  local col = m3 and m3[a]
  if col then
    return col
  end
  col = seq_candidate_hsv_to_color(h, s, v, a)
  candidate_memo_room()
  local memo = cand_color_memo.hsv
  m1 = memo[h]
  if not m1 then m1 = {}; memo[h] = m1 end
  m2 = m1[s]
  if not m2 then m2 = {}; m1[s] = m2 end
  m3 = m2[v]
  if not m3 then m3 = {}; m2[v] = m3 end
  m3[a] = col
  return col
end

-- The gradient bands: band i (0-based) is blend_colors(top, bottom,
-- (i + 0.5) / bands). nil (draw unmemoized) unless the inputs are integers
-- in the ranges that make col_bot * 16 + bands a unique key.
local function candidate_band_colors(col_top, col_bot, bands)
  if math_type(col_top) ~= "integer" or math_type(col_bot) ~= "integer" or math_type(bands) ~= "integer"
      or bands < 1 or bands > 15 or col_bot < 0 or col_bot > 0xFFFFFFFF then
    return nil
  end
  local key = col_bot * 16 + bands
  local by_top = cand_color_memo.bands[col_top]
  local cols = by_top and by_top[key]
  if cols then
    return cols
  end
  cols = {}
  for i = 0, bands - 1 do
    cols[i + 1] = blend_colors(col_top, col_bot, (i + 0.5) / bands)
  end
  candidate_memo_room()
  by_top = cand_color_memo.bands[col_top]
  if not by_top then by_top = {}; cand_color_memo.bands[col_top] = by_top end
  by_top[key] = cols
  return cols
end

-- A colour with its alpha scaled by a (0..1).
local function candidate_color_alpha(col, a)
  if not col then
    return col
  end
  local orig_a = (col % 256) / 255.0
  return change_color_alpha(col, orig_a * a)
end

function seq_draw_sample_candidate_square(dl, box, entry, is_active, is_hovered, scale, slot_n, alpha)
  if not dl or not box or box.w < 4 then
    return
  end
  local x, y, w, h = box.x, box.y, box.w, box.h
  local rounding = math.min(3.5, w * 0.22)
  local taken = seq_candidate_entry_taken(entry)
  local a = math.max(0.0, math.min(1.0, tonumber(alpha) or 1.0))
  local ca = candidate_color_alpha
  local bg = is_active and (taken and 0x122016FF or UI_THEME.accent_fill) or (is_hovered and ui_tc(0x1A1B1EFF) or ui_tc(0x0F1013FF))
  local edge = UI_THEME.border
  local edge_w = 1.0
  if is_active then
    edge = 0xFFFFFF80
    edge_w = 1.8
  elseif is_hovered then
    edge = ui_tc(0xEBECF0FF)
  elseif taken then
    edge = UI_THEME.border_hvr
  end

  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, ca(bg, a), rounding)

  if taken then
    local p_freq, p_brightness, p_weight = candidate_chip_props4(entry)
    local hue = candidate_freq_hue(p_freq)
    local bright_src = p_brightness or p_freq
    local bright_g = candidate_bright_unit(bright_src)
    local bright_t = bright_g
    local weight_t = p_weight
    if scale then
      bright_t = seq_candidate_unit_in_range(bright_src, scale.bright_lo, scale.bright_hi, bright_g)
      weight_t = seq_candidate_unit_in_range(p_weight, scale.weight_lo, scale.weight_hi, p_weight)
    end
    local sat = 0.55 + weight_t * 0.40
    if is_hovered then
      bright_t = math.min(1.0, bright_t + 0.08)
    end
    if is_active then
      bright_t = math.min(1.0, bright_t + 0.10)
    end
    local col_top = candidate_hsv_color(hue, sat, 0.52 + bright_t * 0.46, a)
    local col_bot = candidate_hsv_color(hue, math.min(1.0, sat + 0.08), 0.22 + bright_t * 0.28, a)

    -- MultiColor fills are square; clip rounded rects per band so the chip
    -- follows the same corner radius as the outline.
    local bands = math.max(4, math.min(10, math.floor(h + 0.5)))
    if r.ImGui_DrawList_PushClipRect then
      local band_cols = candidate_band_colors(col_top, col_bot, bands)
      for i = 0, bands - 1 do
        local col = band_cols and band_cols[i + 1] or blend_colors(col_top, col_bot, (i + 0.5) / bands)
        local y0 = y + (h * i) / bands
        local y1 = y + (h * (i + 1) / bands)
        r.ImGui_DrawList_PushClipRect(dl, x, y0, x + w, math.min(y + h, y1 + 0.5), true)
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, col, rounding)
        r.ImGui_DrawList_PopClipRect(dl)
      end
    else
      r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, col_top, rounding)
    end
  end

  if is_active then
    r.ImGui_DrawList_AddRect(dl, x - 1.2, y - 1.2, x + w + 1.2, y + h + 1.2,
      ca(0xFFFFFF40, a), rounding + 1.0, 0, 2.0)
  end
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, ca(edge, a), rounding, 0, edge_w)

  if state.seq_candidate_show_numbers ~= false and slot_n then
    local label = tostring(slot_n)
    local font = r.ImGui_GetFont and r.ImGui_GetFont(ctx) or nil
    local base_sz = (r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx)) or 13.0
    local sz = base_sz * 0.58
    local tw, th = r.ImGui_CalcTextSize(ctx, label)
    tw = (tw or 6) * (sz / math.max(1.0, base_sz))
    th = (th or 10) * (sz / math.max(1.0, base_sz))
    local tx = x + (w - tw) * 0.5
    local ty = y + (h - th) * 0.5
    local num_col = ca(taken and 0xFFFFFF72 or ui_tc(0xCCCDD150), a)
    local sh_col = ca(0x00000044, a)
    if r.ImGui_DrawList_AddTextEx then
      r.ImGui_DrawList_AddTextEx(dl, font, sz, tx + 0.5, ty + 0.5, sh_col, label)
      r.ImGui_DrawList_AddTextEx(dl, font, sz, tx, ty, num_col, label)
    else
      r.ImGui_DrawList_AddText(dl, tx + 0.5, ty + 0.5, sh_col, label)
      r.ImGui_DrawList_AddText(dl, tx, ty, num_col, label)
    end
  end
end

function seq_draw_candidate_delete_x(dl, box, alpha)
  if not dl or not box or box.w < 4 then
    return
  end
  alpha = math.max(0.0, math.min(1.0, tonumber(alpha) or 1.0))
  if alpha <= 0.01 then
    return
  end
  local x, y, w, h = box.x, box.y, box.w, box.h
  local rounding = math.min(3.5, w * 0.22)
  local pulse = 0.5 + 0.5 * math.sin(r.time_precise() * 8.0)
  r.ImGui_DrawList_AddRectFilled(
    dl, x, y, x + w, y + h,
    build_color_rrgbbaa(18, 6, 6, math.floor((70 + pulse * 24) * alpha)),
    rounding
  )
  local inset = math.max(2.2, math.min(w, h) * 0.24)
  local x0, y0 = x + inset, y + inset
  local x1, y1 = x + w - inset, y + h - inset
  local thick = math.max(1.5, math.min(w, h) * 0.13)
  local col = build_color_rrgbbaa(255, 92, 92, math.floor((200 + pulse * 40) * alpha))
  local sh = build_color_rrgbbaa(0, 0, 0, math.floor(90 * alpha))
  r.ImGui_DrawList_AddLine(dl, x0 + 0.6, y0 + 0.6, x1 + 0.6, y1 + 0.6, sh, thick)
  r.ImGui_DrawList_AddLine(dl, x1 + 0.6, y0 + 0.6, x0 + 0.6, y1 + 0.6, sh, thick)
  r.ImGui_DrawList_AddLine(dl, x0, y0, x1, y1, col, thick)
  r.ImGui_DrawList_AddLine(dl, x1, y0, x0, y1, col, thick)
end

function seq_select_sample_candidate(slot, idx, persist)
  if not slot then
    return false
  end
  seq_normalize_slot_candidates(slot)
  idx = tonumber(idx)
  if not idx or idx < 1 or idx > SEQ_SAMPLE_CANDIDATES_MAX then
    return false
  end
  slot.sample_candidate_idx = idx
  if persist then
    save_config()
    if save_seq_project_state then
      save_seq_project_state()
    end
  end
  return true
end

function seq_apply_sample_candidate(slot, idx)
  if not slot then
    return false
  end
  seq_normalize_slot_candidates(slot)
  local persist = not seq_slot_in_swap_mode(slot)
  local entry = slot.sample_candidates and slot.sample_candidates[idx]
  if seq_candidate_entry_taken(entry) then
    local sample = find_sample_by_path(entry.path)
    if not sample then
      sample = { path = entry.path, name = entry.name, x = entry.x, y = entry.y }
    end
    local own = persist and seq_undo_own_begin and seq_undo_own_begin("Recall sample candidate")
    slot.sample_candidate_idx = idx
    seq_assign_sample_for_context(slot, sample, persist)
    if preview_seq_track_sample then
      preview_seq_track_sample(slot)
    elseif preview_sample and find_sample_by_path(entry.path) then
      preview_sample(find_sample_by_path(entry.path))
    end
    if own and end_seq_undo then
      end_seq_undo("Recall sample candidate")
    end
    return true
  end

  slot.sample_candidate_idx = idx
  if slot.sample_path and slot.sample_path ~= "" then
    local sample = find_sample_by_path(slot.sample_path) or {
      path = slot.sample_path,
      name = slot.sample_name,
    }
    seq_remember_sample_candidate(slot, sample)
  end
  if persist then
    save_config()
    if save_seq_project_state then
      save_seq_project_state()
    end
  end
  return true
end

function seq_drop_sample_on_candidate(slot, idx, sample, persist)
  if not slot or not sample then
    return false
  end
  seq_normalize_slot_candidates(slot)
  idx = tonumber(idx)
  if not idx or idx < 1 or idx > SEQ_SAMPLE_CANDIDATES_MAX then
    return false
  end
  slot.sample_candidate_idx = idx
  if apply_dragged_sample_to_seq_track then
    return apply_dragged_sample_to_seq_track(slot, sample, persist)
  end
  return assign_sample_to_seq_track(slot, sample, persist)
end

function render_seq_track_sample_candidates(dl, slot, layout)
  if not slot or not layout or not layout.candidate_boxes then
    return false
  end
  seq_normalize_slot_candidates(slot)
  local boxes = layout.candidate_boxes
  if #boxes == 0 then
    return false
  end
  -- = seq_candidate_slot_scale(slot): its normalize would be a no-op repeat
  -- (a normalized candidate list has no holes, so compacting finds none).
  local scale = candidate_slot_scale_normalized(slot)
  local hovered = false
  local changed = false
  local dragging = sample_drag_active()
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hover_flags = 0
  if dragging and r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
    hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
  end
  local anim, _, ease = seq_candidate_slide_anim(slot)
  if anim and anim.fade then
    local fade = anim.fade
    local s = 1.0 - ease * 0.58
    local cx = fade.x + fade.w * 0.5
    local cy = fade.y + fade.h * 0.5 - ease * 7.0
    local fw, fh = fade.w * s, fade.h * s
    local fade_box = seq_box(cx - fw * 0.5, cy - fh * 0.5, fw, fh)
    seq_draw_sample_candidate_square(dl, fade_box,
      fade.entry, false, false, scale, nil, 1.0 - ease)
    seq_draw_candidate_delete_x(dl, fade_box, (1.0 - ease) * (1.0 - ease * 0.35))
  end
  local id_prefix = nil
  for i = 1, #boxes do
    local box = boxes[i]
    if box and box.w > 0 and box.h > 0 then
      r.ImGui_SetCursorScreenPos(ctx, box.x, box.y)
      id_prefix = id_prefix or ("##seq_cand_" .. tostring(slot.id) .. "_")
      r.ImGui_InvisibleButton(ctx, id_prefix .. i, box.w, box.h)
      local hot = r.ImGui_IsItemHovered(ctx, hover_flags)
      local is_source = seq_candidate_is_drag_source(slot, i)
      if dragging and seq_layout_hit(box, mx, my) then
        hot = true
        seq_set_candidate_drop(slot, i)
      end
      if hot then
        hovered = true
      end
      local entry = slot.sample_candidates[i]
      local is_active = slot.sample_candidate_idx == i
      local draw_box = box
      if anim and anim.moves and anim.moves[i] then
        local move = anim.moves[i]
        draw_box = seq_box(
          move.from_x + (box.x - move.from_x) * ease,
          move.from_y + (box.y - move.from_y) * ease,
          box.w, box.h
        )
      end
      seq_draw_sample_candidate_square(dl, draw_box, entry, is_active, hot, scale, i)
      local alt_delete = (not dragging) and hot and is_alt_down() and seq_candidate_entry_taken(entry)
      if alt_delete then
        seq_draw_candidate_delete_x(dl, draw_box, 1.0)
      end
      if is_source and dl then
        draw_waveform_drag_source_cue(dl, box.x, box.y, box.w, box.h)
      elseif dragging and state.seq_candidate_drop
          and state.seq_candidate_drop.slot_id == slot.id
          and state.seq_candidate_drop.idx == i
          and dl then
        draw_drop_target_highlight(dl, box.x, box.y, box.x + box.w, box.y + box.h, 3)
      end
      if hot and r.ImGui_SetTooltip then
        if dragging then
          r.ImGui_SetTooltip(ctx, is_source
            and "Drop anywhere to place this sample"
            or "Drop to save in this slot")
        elseif alt_delete then
          r.ImGui_SetTooltip(ctx, "Click to remove")
        elseif seq_candidate_entry_taken(entry) then
          r.ImGui_SetTooltip(ctx, (entry.name or "Sample")
            .. (is_active and "\nSelected — samples you pick or drop save here" or "\nClick to recall")
            .. "\nDrag to drop · Alt-click to remove")
        else
          r.ImGui_SetTooltip(ctx, "Click to copy the current sample here")
        end
      end
      if (not dragging) and r.ImGui_IsItemClicked(ctx, 0) then
        if is_alt_down() and seq_candidate_entry_taken(entry) then
          state.seq_candidate_press = nil
          local persist = not seq_slot_in_swap_mode(slot)
          local own = persist and seq_undo_own_begin and seq_undo_own_begin("Remove sample candidate")
          seq_begin_candidate_slide(slot, i, boxes)
          if seq_remove_sample_candidate(slot, i) then
            changed = true
            if persist then
              save_config()
              if save_seq_project_state then
                save_seq_project_state()
              end
            end
          else
            if state.seq_candidate_slide then
              state.seq_candidate_slide[slot.id] = nil
            end
          end
          if own and end_seq_undo then
            end_seq_undo("Remove sample candidate")
          end
          break
        elseif seq_candidate_entry_taken(entry) then
          state.seq_candidate_press = { slot_id = slot.id, idx = i }
        elseif seq_apply_sample_candidate(slot, i) then
          changed = true
        end
      end
    end
  end
  local press = state.seq_candidate_press
  if press and press.slot_id == slot.id and not dragging then
    if not is_alt_down()
        and r.ImGui_IsMouseDragging and r.ImGui_IsMouseDragging(ctx, 0, 6.0) then
      local drag_sample = seq_candidate_sample_from_entry(slot.sample_candidates[press.idx])
      if drag_sample and begin_waveform_sample_drag(drag_sample) then
        state.seq_candidate_drag_source = { slot_id = press.slot_id, idx = press.idx }
        state.seq_candidate_press = nil
      end
    end
  end
  return changed, hovered
end

-- Height-aware TCP layout for the sequencer label column (left of the sample nav).
-- tiny  (<38): one centered row, shrink mix, hide env if it would crush the name
-- split (38-63): name on its own row, mix+env share the second row
-- stack (64-99): name, full-width mix, full-width envelope
-- mixer (>=100): name, button row, stacked wide vol/pan, tall envelope
function seq_get_track_control_layout(x0, y0, x1, y1, slot, opts)
  x0, y0, x1, y1 = x0 or 0, y0 or 0, x1 or 0, y1 or 0
  if x1 < x0 then x1 = x0 end
  if y1 < y0 then y1 = y0 end
  opts = opts or {}
  local lane_h = y1 - y0
  local pad = (lane_h >= 64.0) and 4.0 or 3.0
  local gap = 3.0
  local expand_w = opts.hide_expand and 0.0 or 18.0
  local inner_x0 = x0 + pad
  local inner_x1 = x1 - pad
  local inner_w = math.max(0.0, inner_x1 - inner_x0)
  local mode = "tiny"
  if lane_h >= 100.0 then
    mode = "mixer"
  elseif lane_h >= 64.0 then
    mode = "stack"
  elseif lane_h >= 38.0 then
    mode = "split"
  end

  -- Every mode below sets expand, name, gear, vol, pan, midi, mute, solo,
  -- overlap and mix_hit (and env in stack and mixer) before anything reads
  -- them, so they start as false placeholders rather than empty boxes that
  -- would be thrown away; env (tiny, split) and the candidates may stay empty.
  local layout = {
    mode = mode,
    lane_h = lane_h,
    expand = false,
    name = false,
    gear = false,
    vol = false,
    pan = false,
    midi = false,
    mute = false,
    solo = false,
    overlap = false,
    env = (mode == "stack" or mode == "mixer") and false or seq_box(0, 0, 0, 0),
    mix_hit = false,
    candidates = seq_box(0, 0, 0, 0),
    candidate_boxes = {},
  }

  if mode == "tiny" then
    local btn = math.max(12.0, math.min(15.0, lane_h - 8.0))
    local row_h = btn
    local mid_y = y0 + (lane_h - row_h) * 0.5
    local name_min = 28.0
    local btn2, vol_w, pan_w, midi_w, mix_w = seq_fit_mix_strip(
      math.max(80.0, inner_w - expand_w - name_min - gap), btn, gap, 48.0, 36.0, 26.0
    )
    btn = btn2
    row_h = btn
    mid_y = y0 + (lane_h - row_h) * 0.5
    local mix_x = inner_x1 - mix_w
    local name_x = inner_x0 + expand_w
    local mid_space = math.max(0.0, mix_x - gap - name_x)
    local env_w = 0.0
    if mid_space >= name_min + gap + 40.0 then
      env_w = math.min(SEQ_ENV_PREVIEW_W or 80.0, mid_space - name_min - gap)
      if env_w < 36.0 then env_w = 0.0 end
    end
    local name_w = math.max(0.0, mid_space - (env_w > 0 and (env_w + gap) or 0.0))
    layout.expand = seq_box(inner_x0, mid_y, expand_w, row_h)
    layout.name = seq_box(name_x, mid_y, name_w, row_h)
    if env_w > 0 then
      layout.env = seq_box(name_x + name_w + gap, mid_y, env_w, row_h)
    end
    seq_place_mix_strip(layout, mix_x, mid_y, btn, gap, vol_w, pan_w, midi_w, row_h)
    local hit_x0 = (env_w > 0) and layout.env.x or layout.mute.x
    layout.mix_hit = seq_box(hit_x0, mid_y, inner_x1 - hit_x0, row_h)

  elseif mode == "split" then
    local name_h = math.max(14.0, math.min(17.0, 14.0 + (lane_h - 38.0) * 0.12))
    local btn = math.max(13.0, math.min(17.0, 13.0 + (lane_h - 38.0) * 0.16))
    local row_h = btn
    local gap_v = 2.0
    local block_h = name_h + gap_v + row_h
    local top_y = y0 + math.max(pad, (lane_h - block_h) * 0.5)
    local ctrl_y = top_y + name_h + gap_v
    seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, top_y, name_h, expand_w, gap)

    local env_reserve = 0.0
    if inner_w >= 210.0 then
      env_reserve = math.max(40.0, math.min(88.0, inner_w * 0.24))
    end
    local mix_avail = inner_w - (env_reserve > 0 and (env_reserve + gap) or 0.0)
    local btn2, vol_w, pan_w, midi_w, mix_w = seq_fit_mix_strip(mix_avail, btn, gap, 52.0, 40.0, 28.0)
    btn = btn2
    row_h = math.max(row_h, btn)
    ctrl_y = top_y + name_h + gap_v
    local leftover = inner_w - mix_w - gap
    local env_w = 0.0
    if leftover >= 36.0 then
      if leftover > 92.0 then
        local grow = leftover - 92.0
        vol_w = vol_w + grow * 0.62
        pan_w = pan_w + grow * 0.38
        mix_w = seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
        leftover = inner_w - mix_w - gap
      end
      env_w = leftover
    end
    seq_place_mix_strip(layout, inner_x0, ctrl_y, btn, gap, vol_w, pan_w, midi_w, row_h)
    if env_w >= 36.0 then
      layout.env = seq_box(layout.overlap.x1 + gap, ctrl_y, env_w, row_h)
    end
    layout.mix_hit = seq_box(inner_x0, ctrl_y, inner_w, row_h)

  elseif mode == "stack" then
    local name_h = 16.0
    local rest = lane_h - pad * 2 - name_h - 4.0
    local row_h = math.max(14.0, math.min(20.0, rest * 0.42))
    local env_h = math.max(12.0, rest - row_h - 3.0)
    local btn = math.max(14.0, math.min(row_h, 18.0))
    local top_y = y0 + pad
    local mix_y = top_y + name_h + 3.0
    local env_y = mix_y + row_h + 3.0
    if env_y + env_h > y1 - pad then
      env_h = math.max(12.0, (y1 - pad) - env_y)
    end
    seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, top_y, name_h, expand_w, gap)

    local btn2, vol_w, pan_w, midi_w, mix_w = seq_fit_mix_strip(inner_w, btn, gap, 56.0, 42.0, 30.0)
    btn = btn2
    if inner_w > mix_w then
      local grow = inner_w - mix_w
      vol_w = vol_w + grow * 0.62
      pan_w = pan_w + grow * 0.38
    end
    seq_place_mix_strip(layout, inner_x0, mix_y, btn, gap, vol_w, pan_w, midi_w, row_h)
    layout.env = seq_box(inner_x0, env_y, inner_w, env_h)
    layout.mix_hit = seq_box(inner_x0, mix_y, inner_w, (y1 - pad) - mix_y)

  else
    local name_h = math.max(15.0, math.min(20.0, 15.0 + (lane_h - 100.0) * 0.05))
    local btn = math.max(15.0, math.min(20.0, 15.0 + (lane_h - 100.0) * 0.05))
    local rest = lane_h - pad * 2 - name_h - btn - 9.0
    local bar_h = math.max(15.0, math.min(26.0, (rest - 6.0) / 3.0))
    local env_h = math.max(14.0, rest - bar_h * 2.0 - 6.0)
    local y = y0 + pad
    seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, y, name_h, expand_w, gap)
    y = y + name_h + 3.0
    local midi_w = math.max(32.0, math.min(52.0, btn * 2.4))
    local cx = inner_x0
    layout.mute = seq_box(cx, y, btn, btn); cx = cx + btn
    layout.solo = seq_box(cx, y, btn, btn); cx = cx + btn + SEQ_TCP_GROUP_GAP
    layout.midi = seq_box(cx, y, midi_w, btn); cx = cx + midi_w
    layout.gear = seq_box(cx, y, btn, btn); cx = cx + btn
    layout.overlap = seq_box(cx, y, btn, btn)
    y = y + btn + 3.0
    layout.vol = seq_box(inner_x0, y, inner_w, bar_h)
    y = y + bar_h + 3.0
    layout.pan = seq_box(inner_x0, y, inner_w, bar_h)
    y = y + bar_h + 3.0
    env_h = math.max(12.0, (y1 - pad) - y)
    layout.env = seq_box(inner_x0, y, inner_w, env_h)
    layout.mix_hit = seq_box(inner_x0, layout.mute.y, inner_w, (y1 - pad) - layout.mute.y)
  end

  return layout
end

function seq_draw_track_name_and_expand(dl, slot, layout, expanded, name_alpha, expand_color, fallback_name)
  if not layout or not slot then
    return
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  local exp = layout.expand
  if exp and exp.w > 0 then
    -- Chevron in a small hover pad: right = collapsed, down = parameter lanes shown.
    local size = math.min(exp.w, exp.h, 16.0)
    local cx, cy = exp.x + exp.w * 0.5, exp.y + exp.h * 0.5
    local hot = seq_layout_hit(exp, mx, my) and not sample_drag_active()
    if hot or expanded then
      r.ImGui_DrawList_AddRectFilled(dl, cx - size * 0.5, cy - size * 0.5, cx + size * 0.5, cy + size * 0.5,
        hot and UI_THEME.surface_hvr or 0xFFFFFF0C, 4.0)
    end
    local col = expand_color or UI_THEME.accent
    if not hot and not expanded then
      col = UI_THEME.text_dim
    end
    ui_button_draw_icon(dl, expanded and "chev_down" or "chev_right", cx, cy, size * 1.1, col)
  end
  local name_box = layout.name
  if name_box and name_box.w > 4 and seq_track_rename_active(slot, not (exp and exp.w > 0)) then
    seq_render_track_rename_input(slot, name_box)
  elseif name_box and name_box.w > 4 then
    local name_txt = seq_truncate_text_to_width(slot.name or fallback_name or "Track", name_box.w - 2.0)
    local _, nh = r.ImGui_CalcTextSize(ctx, name_txt)
    local a = name_alpha or 255
    local col = slot.mute and build_color_rrgbbaa(150, 160, 153, math.floor(a * 0.75))
      or build_color_rrgbbaa(240, 245, 241, a)
    local tx, ty = name_box.x + 2.0, name_box.y + (name_box.h - (nh or 12)) * 0.5
    r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x00000080, name_txt)
    r.ImGui_DrawList_AddText(dl, tx, ty, col, name_txt)
  end
end

function seq_lane_mix_controls_hit(row_pos, mx, my, x0, timeline_x0, map_nav_w)
  if not row_pos or not row_pos.row or row_pos.row.type ~= "note" then
    return false
  end
  local layout = row_pos.ctrl
  if not layout and x0 and timeline_x0 then
    -- Offscreen rows have no cached layout. Control boxes sit inside their
    -- row, so a pointer more than a row height away cannot hit them; skip
    -- building a throwaway layout for every offscreen row every frame.
    local row_h = (row_pos.y1 or 0) - (row_pos.y0 or 0)
    if my and (my < row_pos.y0 - row_h or my > row_pos.y1 + row_h) then
      return false
    end
    local nav_w = map_nav_w or seq_track_nav_width(row_pos.y1 - row_pos.y0)
    layout = seq_get_track_control_layout(
      x0, row_pos.y0, timeline_x0 - nav_w - 6.0, row_pos.y1,
      row_pos.row and row_pos.row.slot
    )
  end
  return seq_layout_hit(layout and layout.mix_hit, mx, my)
    or seq_layout_hit(layout and layout.candidates, mx, my)
    or (seq_track_rename_active(row_pos.row.slot, false) and seq_layout_hit(layout and layout.name, mx, my))
end

-- ===== Inline track rename =============================================
-- Double-clicking a track name swaps it for a text field. Enter or clicking
-- away keeps the new name; Esc cancels. panel = the tracks side panel row
-- (it draws the same track separately from the sequencer lane).

function seq_track_rename_active(slot, panel)
  local ren = state.seq_track_rename
  return ren ~= nil and slot ~= nil and ren.slot_id == slot.id and ren.panel == (panel == true)
end

function seq_begin_track_rename(slot, panel)
  if not slot or seq_track_rename_active(slot, panel) then
    return
  end
  state.seq_track_rename = {
    slot_id = slot.id,
    text = slot.name or "",
    focus = true,
    panel = panel == true,
    frames = 0,
  }
end

function seq_render_track_rename_input(slot, box)
  local ren = state.seq_track_rename
  if not ren then
    return
  end
  local vars, cols = 0, 0
  if r.ImGui_StyleVar_FramePadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 1); vars = vars + 1
  end
  if r.ImGui_StyleVar_FrameRounding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4); vars = vars + 1
  end
  if r.ImGui_StyleVar_FrameBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 1); vars = vars + 1
  end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), ui_tc(0x0C0D10FF)); cols = cols + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), UI_THEME.accent); cols = cols + 1
  local fh = (r.ImGui_GetFrameHeight and r.ImGui_GetFrameHeight(ctx)) or box.h
  r.ImGui_SetCursorScreenPos(ctx, box.x, box.y + (box.h - fh) * 0.5)
  r.ImGui_SetNextItemWidth(ctx, math.max(40.0, box.w))
  if ren.focus and r.ImGui_SetKeyboardFocusHere then
    r.ImGui_SetKeyboardFocusHere(ctx)
    ren.focus = false
  end
  local flags = 0
  if r.ImGui_InputTextFlags_EnterReturnsTrue then flags = flags | r.ImGui_InputTextFlags_EnterReturnsTrue() end
  if r.ImGui_InputTextFlags_AutoSelectAll then flags = flags | r.ImGui_InputTextFlags_AutoSelectAll() end
  local entered, text = r.ImGui_InputText(ctx, "##seq_track_rename", ren.text, flags)
  if type(text) == "string" then
    ren.text = text
  end
  local active = r.ImGui_IsItemActive(ctx)
  r.ImGui_PopStyleColor(ctx, cols)
  r.ImGui_PopStyleVar(ctx, vars)
  ren.frames = (ren.frames or 0) + 1

  local escape = r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
    and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
  if escape then
    state.seq_track_rename = nil
  elseif entered or (ren.frames > 2 and not active) then
    state.seq_track_rename = nil
    seq_rename_track(slot, ren.text)
  end
end

-- ===== Track control buttons ===========================================
-- Buttons in one group touch and share a frame (segmented pill); state shows
-- through the fill color so a row of tracks scans quickly.

local tcp_round_flag_cache = {}

local function tcp_round_flag(name)
  local v = tcp_round_flag_cache[name]
  if v == nil then
    local fn = r["ImGui_DrawFlags_" .. name]
    v = fn and fn() or 0
    tcp_round_flag_cache[name] = v
  end
  return v
end

local function tcp_seg_flags(seg)
  if seg == "first" then
    return tcp_round_flag("RoundCornersLeft")
  elseif seg == "last" then
    return tcp_round_flag("RoundCornersRight")
  elseif seg == "mid" then
    return tcp_round_flag("RoundCornersNone")
  end
  return 0
end

function seq_tcp_rounding(h)
  return math.max(2.0, math.min(5.0, (h or 14) * 0.3))
end

-- Draws the shared frame around a group of touching buttons plus hairline
-- dividers between them. boxes are left to right.
function seq_tcp_group_frame(dl, boxes, hovered)
  local first, last = boxes[1], boxes[#boxes]
  if not first or not last or first.w <= 0 then
    return
  end
  local x0, y0 = first.x, first.y
  local x1, y1 = last.x1, math.max(first.y1, last.y1)
  local edge = hovered and UI_THEME.border_hvr or UI_THEME.border
  for i = 2, #boxes do
    local b = boxes[i]
    if b and b.w > 0 then
      r.ImGui_DrawList_AddLine(dl, b.x, y0 + 2.0, b.x, y1 - 2.0, 0x00000070, 1.0)
    end
  end
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, edge,
    seq_tcp_rounding(y1 - y0), 0, 1.0)
end

-- One segment of a group. opts: active, on_fill, on_text, label, icon, glyph
-- (function(dl, cx, cy, size, col)), badge (small dot, top right).
-- Returns clicked, hovered, pressed.
function seq_tcp_seg_button(id, dl, box, seg, opts)
  opts = opts or {}
  local x, y, w, h = box.x, box.y, box.w, box.h
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local active = opts.active
  local bg
  if active then
    bg = opts.on_fill or UI_THEME.accent_fill
    if hovered and not pressed then
      bg = blend_colors(bg, 0xFFFFFFFF, 0.12)
    end
  elseif pressed then
    bg = UI_THEME.surface_act
  elseif hovered then
    bg = UI_THEME.surface_hvr
  else
    bg = UI_THEME.surface
  end
  local rounding = seq_tcp_rounding(h)
  local flags = tcp_seg_flags(seg)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, rounding, flags)
  if not active and not pressed then
    r.ImGui_DrawList_AddLine(dl, x + ((seg == "first" or seg == nil) and rounding or 0.0), y + 1.0,
      x + w - ((seg == "last" or seg == nil) and rounding or 0.0), y + 1.0, 0xFFFFFF12, 1.0)
  end

  local col
  if active then
    col = opts.on_text or 0xFFFFFFFF
  else
    col = hovered and UI_THEME.text or UI_THEME.text_dim
  end
  local cx, cy = x + w * 0.5, y + h * 0.5 + (pressed and 0.5 or 0.0)
  local size = math.min(w, h)
  if opts.glyph then
    opts.glyph(dl, cx, cy, size, col)
  elseif opts.icon then
    ui_button_draw_icon(dl, opts.icon, cx, cy, size * (opts.icon_scale or 1.0), col)
  elseif opts.label then
    local tw, th = r.ImGui_CalcTextSize(ctx, opts.label)
    r.ImGui_DrawList_AddText(dl, cx - tw * 0.5, cy - th * 0.5, col, opts.label)
  end
  if opts.badge then
    local br = math.max(1.6, size * 0.11)
    r.ImGui_DrawList_AddCircleFilled(dl, x + w - br - 1.5, y + br + 1.5, br, opts.badge, 10)
  end
  return clicked, hovered, pressed
end

-- Drum layering: triangle with a dot on each corner (three blended samples).
function seq_tcp_glyph_layering(dl, cx, cy, size, col)
  local rad = size * 0.30
  local ax, ay = cx, cy - rad
  local bx, by = cx - rad * 0.95, cy + rad * 0.62
  local qx, qy = cx + rad * 0.95, cy + rad * 0.62
  local stroke = math.max(1.0, size * 0.07)
  r.ImGui_DrawList_AddTriangle(dl, ax, ay, bx, by, qx, qy, col, stroke)
  local dot = math.max(1.3, size * 0.085)
  r.ImGui_DrawList_AddCircleFilled(dl, ax, ay, dot, col, 8)
  r.ImGui_DrawList_AddCircleFilled(dl, bx, by, dot, col, 8)
  r.ImGui_DrawList_AddCircleFilled(dl, qx, qy, dot, col, 8)
end

-- Overlap: two hits whose tails overlap (on) or sit side by side, the first
-- cropped where the next starts (off).
function seq_tcp_glyph_overlap(dl, cx, cy, size, col, on)
  local stroke = math.max(1.0, size * 0.07)
  local hh = size * 0.17
  if on then
    local hw = size * 0.17
    local off = size * 0.10
    r.ImGui_DrawList_AddRect(dl, cx - off - hw, cy - off - hh, cx - off + hw, cy - off + hh, col, 2.0, 0, stroke)
    r.ImGui_DrawList_AddRectFilled(dl, cx + off - hw, cy + off - hh, cx + off + hw, cy + off + hh, col, 2.0)
  else
    local hw = size * 0.13
    local gap = size * 0.05
    r.ImGui_DrawList_AddRect(dl, cx - gap - hw * 2, cy - hh, cx - gap, cy + hh, col, 2.0, 0, stroke)
    r.ImGui_DrawList_AddRectFilled(dl, cx + gap, cy - hh, cx + gap + hw * 2, cy + hh, col, 2.0)
  end
end

-- MIDI note chip: 5-pin icon when there is room, then the note name.
local midi_glyph_label, midi_glyph_box = nil, nil
local midi_button_opts = { active = false, on_fill = false, on_text = 0xDFFFE8FF, glyph = false }

local function tcp_midi_glyph(gdl, cx, cy, size, col)
  local label, box = midi_glyph_label, midi_glyph_box
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local icon_w = (box.w >= tw + box.h + 4.0) and box.h * 0.9 or 0.0
  local total = tw + (icon_w > 0 and (icon_w + 1.0) or 0.0)
  local lx = cx - total * 0.5
  if icon_w > 0 then
    ui_button_draw_icon(gdl, "midi", lx + icon_w * 0.5, cy, icon_w, col)
    lx = lx + icon_w + 1.0
  end
  r.ImGui_DrawList_AddText(gdl, lx, cy - th * 0.5, col, label)
end

function seq_tcp_midi_button(id, dl, box, seg, slot, open)
  local learning = state.seq_midi_learn_slot_id == (slot and slot.id)
  local label = learning and "…" or seq_midi_slot_label(slot)
  midi_glyph_label, midi_glyph_box = label, box
  local opts = midi_button_opts
  opts.active = open or learning
  opts.on_fill = UI_THEME.accent_fill_h
  opts.glyph = tcp_midi_glyph
  local clicked, hovered, pressed = seq_tcp_seg_button(id, dl, box, seg, opts)
  midi_glyph_label, midi_glyph_box = nil, nil
  if learning then
    local pulse = 0.5 + 0.5 * math.sin(r.time_precise() * 8.0)
    r.ImGui_DrawList_AddRect(dl, box.x - 0.5, box.y - 0.5, box.x1 + 0.5, box.y1 + 0.5,
      build_color_rrgbbaa(30, 255, 94, math.floor(80 + pulse * 150)), seq_tcp_rounding(box.h),
      tcp_seg_flags(seg), 1.5)
  end
  return clicked, hovered, pressed
end

-- Open the undo session before mutating slot fields so the "before"
-- snapshot holds the old value (callers' begin_seq_undo is then a no-op).
local function begin_mix_undo()
  if not seq_undo_is_open() then
    begin_seq_undo("Adjust sequencer mix")
  end
  seq_undo_commit_on_release = true
end

-- Option tables for the mix row, refilled field by field before each use
-- (seq_tcp_seg_button / seq_rect_drag_control only read them), so a frame
-- doesn't build a dozen tables and closures per track.
local mix_opts = {
  mute = { label = "M", active = false, on_fill = 0xB8383CFF },
  solo = { label = "S", active = false, on_fill = 0xE0A028FF, on_text = 0x1C1404FF },
  vol = {
    fill_color = 0x6AA0E0FF, unity = 1.0, reset = 1.0, horizontal = true,
    to_pos = false, from_pos = false, format_value = false,
    icon = "gain", unit = " dB",
  },
  pan = {
    bipolar = true, fill_color = ui_tc(0x9FE3B5FF), horizontal = true, reset = 0.0,
    format_value = false, icon = "pan",
  },
  layering = { active = false, on_fill = false, on_text = 0xC8FF9AFF, glyph = false, badge = nil },
  overlap = { active = false, on_fill = 0x175052FF, on_text = 0x8FF2F2FF, glyph = false },
  ms_group = { false, false },
  tools_group = {},
}

local overlap_glyph_slot = nil

local function tcp_overlap_glyph(gdl, cx, cy, size, col)
  seq_tcp_glyph_overlap(gdl, cx, cy, size, col, overlap_glyph_slot.overlap)
end

-- Compact mixer + envelope preview in the sequencer track label column.
-- Layout is computed by seq_get_track_control_layout so widgets reflow with lane height.
-- Returns changed_mix, overlap_changed, hovered
function render_seq_track_mix_controls(dl, slot, x0, y0, x1, y1, layout)
  if not slot then return false, false, false end
  seq_normalize_slot_mix(slot)
  if type(x0) == "table" then
    layout = x0
  else
    layout = layout or seq_get_track_control_layout(x0, y0, x1, y1, slot)
  end
  if not layout then return false, false, false end

  local changed_mix = false
  local hovered = false
  local overlap_changed = false

  -- [M S] group
  local mute, solo = layout.mute, layout.solo
  local ms_hot = false
  if mute and mute.w > 0 then
    local opts = mix_opts.mute
    opts.active = slot.mute
    local clicked, hot = seq_tcp_seg_button("##seq_mute_" .. slot.id, dl, mute, "first", opts)
    if clicked then
      begin_mix_undo()
      slot.mute = not slot.mute
      changed_mix = true
    end
    if hot then
      hovered = true
      ms_hot = true
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, slot.mute and "Click: unmute track" or "Click: mute track")
      end
    end
  end
  if solo and solo.w > 0 then
    local opts = mix_opts.solo
    opts.active = slot.solo
    local clicked, hot = seq_tcp_seg_button("##seq_solo_" .. slot.id, dl, solo, "last", opts)
    if clicked then
      begin_mix_undo()
      slot.solo = not slot.solo
      changed_mix = true
    end
    if hot then
      hovered = true
      ms_hot = true
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, slot.solo and "Click: unsolo track" or "Click: solo track")
      end
    end
  end
  if mute and mute.w > 0 and solo and solo.w > 0 then
    local group = mix_opts.ms_group
    group[1], group[2] = mute, solo
    seq_tcp_group_frame(dl, group, ms_hot)
    group[1], group[2] = false, false
  end

  local vol = layout.vol
  if vol and vol.w > 0 then
    local opts = mix_opts.vol
    opts.to_pos = seq_vol_amp_to_pos
    opts.from_pos = seq_vol_pos_to_amp
    opts.format_value = seq_format_track_volume
    local vol_changed, vol_val, vol_hot = seq_rect_drag_control(
      "##seq_track_vol_" .. slot.id, dl, vol.x, vol.y, vol.w, vol.h,
      slot.volume, 0.0, 4.0, opts
    )
    if vol_hot then
      hovered = true
      if r.ImGui_IsItemHovered(ctx) and not r.ImGui_IsItemActive(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Drag: volume · Shift+drag: fine · Double-click: 0 dB")
      end
    end
    if vol_changed then
      begin_mix_undo()
      slot.volume = vol_val
      changed_mix = true
    end
  end

  local pan = layout.pan
  if pan and pan.w > 0 then
    local opts = mix_opts.pan
    opts.format_value = seq_format_track_pan
    local pan_changed, pan_val, pan_hot = seq_rect_drag_control(
      "##seq_track_pan_" .. slot.id, dl, pan.x, pan.y, pan.w, pan.h,
      slot.pan, -1.0, 1.0, opts
    )
    if pan_hot then
      hovered = true
      if r.ImGui_IsItemHovered(ctx) and not r.ImGui_IsItemActive(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Drag: pan · Shift+drag: fine · Double-click: center")
      end
    end
    if pan_changed then
      begin_mix_undo()
      slot.pan = pan_val
      changed_mix = true
    end
  end

  -- [MIDI layering overlap] group
  local tools_hot = false
  local midi = layout.midi
  if midi and midi.w > 0 then
    local midi_learning = state.seq_midi_learn_slot_id == slot.id
    local midi_open = state.seq_midi_popup_slot_id == slot.id
    if seq_tcp_midi_button("##seq_midi_" .. slot.id, dl, midi, "first", slot, midi_open) then
      seq_midi_ensure_jsfx()
      if is_alt_down and is_alt_down() then
        local def = seq_midi_default_note_for_slot(slot)
        seq_midi_set_range(slot, def, def)
        save_config()
        if save_seq_project_state then save_seq_project_state() end
      else
        state.seq_midi_popup_slot_id = slot.id
        r.ImGui_OpenPopup(ctx, "seq_midi_assign_popup")
      end
    end
    if r.ImGui_IsItemClicked(ctx, 1) then
      if midi_learning then
        seq_midi_end_learn()
      else
        seq_midi_begin_learn(slot, false, "rclick")
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      hovered = true
      tools_hot = true
      if r.ImGui_SetTooltip then
        seq_normalize_slot_midi(slot)
        local lo, hi = slot.midi_lo, slot.midi_hi
        local range = (lo == hi)
            and (seq_midi_note_name(lo) .. "  (" .. tostring(lo) .. ")")
            or (seq_midi_note_name(lo) .. "–" .. seq_midi_note_name(hi)
                .. "  (" .. tostring(lo) .. "–" .. tostring(hi) .. ")")
        r.ImGui_SetTooltip(ctx, "MIDI " .. range
          .. "\nClick: assign notes · Right-click: learn (Esc or click to stop) · Alt+click: GM default")
      end
    end
  end

  local gear = layout.gear
  if gear and gear.w > 0 then
    local layering_open = state.seq_layering_slot_id == slot.id
    local layered = seq_layering_is_active and seq_layering_is_active(slot)
    local opts = mix_opts.layering
    opts.active = layering_open
    opts.on_fill = UI_THEME.accent_fill_h
    opts.glyph = seq_tcp_glyph_layering
    opts.badge = layered and not layering_open and UI_THEME.accent or nil
    local clicked, hot = seq_tcp_seg_button("##seq_layering_" .. slot.id, dl, gear,
      (midi and midi.w > 0) and "mid" or "first", opts)
    if clicked then
      if layering_open then
        state.seq_layering_slot_id = nil
      else
        state.seq_layering_slot_id = slot.id
        seq_layering_seed_from_track(slot)
      end
    end
    if hot then
      hovered = true
      tools_hot = true
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, layered
          and "Drum layering (on)\nClick: open the layering window"
          or "Drum layering\nClick: open the layering window")
      end
    end
  end

  local overlap = layout.overlap
  if overlap and overlap.w > 0 then
    local opts = mix_opts.overlap
    opts.active = slot.overlap
    opts.glyph = tcp_overlap_glyph
    overlap_glyph_slot = slot
    local clicked, hot = seq_tcp_seg_button("##seq_overlap_" .. slot.id, dl, overlap, "last", opts)
    overlap_glyph_slot = nil
    if clicked then
      begin_mix_undo()
      slot.overlap = not slot.overlap
      changed_mix = true
      overlap_changed = true
    end
    if hot then
      hovered = true
      tools_hot = true
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, slot.overlap
          and "Overlap on: hits ring out over the next note\nClick: crop at the next hit"
          or "Overlap off: hits crop at the next note\nClick: let hits overlap")
      end
    end
  end
  do
    local group = mix_opts.tools_group
    local n = 0
    if midi and midi.w > 0 then n = n + 1; group[n] = midi end
    if gear and gear.w > 0 then n = n + 1; group[n] = gear end
    if overlap and overlap.w > 0 then n = n + 1; group[n] = overlap end
    for i = n + 1, 3 do group[i] = nil end
    if n > 0 then
      seq_tcp_group_frame(dl, group, tools_hot)
    end
  end

  local env = layout.env
  if env and env.w > 4 and env.h > 4 then
    local env_live = seq_env_is_active(slot.env) or (state.seq_env_popup_slot_id == slot.id)
    r.ImGui_SetCursorScreenPos(ctx, env.x, env.y)
    local env_clicked = r.ImGui_InvisibleButton(ctx, "##seq_env_preview_" .. tostring(slot.id), env.w, env.h)
    local env_hovered = r.ImGui_IsItemHovered(ctx)
    if env_hovered then
      hovered = true
    end
    seq_draw_env_sparkline(dl, env.x, env.y, env.w, env.h, slot.env, env_live, env_hovered)
    if state.seq_env_popup_slot_id == slot.id then
      state.seq_env_popup_preview_rect = {
        x = env.x, y = env.y, w = env.w, h = env.h, x1 = env.x1, y1 = env.y1,
      }
    end
    if env_clicked then
      if is_alt_down() then
        local label = begin_seq_undo("Reset sequencer envelope")
        slot.env = seq_default_track_env()
        seq_normalize_slot_mix(slot)
        seq_on_slot_mix_changed(slot, { resync = true })
        end_seq_undo(label)
      else
        if state.seq_env_popup_slot_id == slot.id then
          state.seq_env_popup_slot_id = nil
          state.seq_env_popup_just_opened = nil
          state.seq_env_popup_preview_rect = nil
          if seq_env_view_reset then seq_env_view_reset() end
        else
          state.seq_env_popup_slot_id = slot.id
          state.seq_env_popup_just_opened = true
          state.seq_env_popup_preview_rect = {
            x = env.x, y = env.y, w = env.w, h = env.h, x1 = env.x1, y1 = env.y1,
          }
        end
      end
    end
  end

  local _, cand_hovered = render_seq_track_sample_candidates(dl, slot, layout)
  if cand_hovered then
    hovered = true
  end

  return changed_mix, overlap_changed, hovered
end

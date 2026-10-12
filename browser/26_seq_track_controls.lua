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

  if reset ~= nil and hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    value = math.max(min_v, math.min(max_v, reset))
    changed = true
    state.seq_rect_drag = nil
  elseif active then
    local mx, my = r.ImGui_GetMousePos(ctx)
    mx, my = mx or x, my or y
    if (not state.seq_rect_drag) or state.seq_rect_drag.id ~= id then
      state.seq_rect_drag = { id = id, start_value = value, start_my = my, start_mx = mx, fine = fine }
    end
    local drag = state.seq_rect_drag
    if drag.fine ~= fine then
      drag.start_value = value
      drag.start_my = my
      drag.start_mx = mx
      drag.fine = fine
    end
    local span = max_v - min_v
    local scale = fine and SEQ_FINE_DRAG_SCALE or 1.0
    if opts.horizontal then
      if fine then
        local start_t = opts.to_pos and opts.to_pos(drag.start_value or value)
          or (((drag.start_value or value) - min_v) / span)
        local t = start_t + (mx - (drag.start_mx or mx)) / math.max(1.0, w) * scale
        t = math.max(0.0, math.min(1.0, t))
        if opts.from_pos then
          value = opts.from_pos(t)
        else
          value = min_v + t * span
        end
      else
        local t = (mx - x) / math.max(1.0, w)
        t = math.max(0.0, math.min(1.0, t))
        if opts.from_pos then
          value = opts.from_pos(t)
        else
          value = min_v + t * span
        end
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

  local bg = hovered and UI_THEME.surface_hvr or UI_THEME.surface
  local edge = (hovered or active) and UI_THEME.accent or UI_THEME.border
  local fill = opts.fill_color or UI_THEME.accent
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered, active)

  local t
  if opts.to_pos then
    t = opts.to_pos(value)
  else
    t = (value - min_v) / (max_v - min_v)
  end
  if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
  if opts.bipolar then
    local mid = x + w * 0.5
    r.ImGui_DrawList_AddLine(dl, mid, y + 2, mid, y + h - 2, 0xFFFFFF55, 1.0)
    local mx = x + t * w
    r.ImGui_DrawList_AddRectFilled(dl, mx - 2.0, y + 2, mx + 2.0, y + h - 2, fill, 1.5)
    if t >= 0.5 then
      r.ImGui_DrawList_AddRectFilled(dl, mid, y + 3, mx, y + h - 3, build_color_rrgbbaa(106, 160, 224, 90), 1.0)
    else
      r.ImGui_DrawList_AddRectFilled(dl, mx, y + 3, mid, y + h - 3, build_color_rrgbbaa(106, 160, 224, 90), 1.0)
    end
  else
    local fill_w = math.max(2.0, t * (w - 4))
    r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 2, x + 2 + fill_w, y + h - 2, fill, 2.0)
    if opts.unity and opts.unity >= min_v and opts.unity <= max_v then
      local ut = opts.to_pos and opts.to_pos(opts.unity) or ((opts.unity - min_v) / (max_v - min_v))
      local ux = x + math.max(0.0, math.min(1.0, ut)) * w
      r.ImGui_DrawList_AddLine(dl, ux, y + 1, ux, y + h - 1, 0xFFFFFF66, 1.0)
    end
  end

  local display = nil
  if opts.format_value then
    display = opts.format_value(value)
  elseif opts.value_text and opts.value_text ~= "" then
    display = opts.value_text
  end
  if display and display ~= "" then
    local tw, th = r.ImGui_CalcTextSize(ctx, display)
    local tx = x + (w - tw) * 0.5
    local ty = y + (h - th) * 0.5
    r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x000000AA, display)
    r.ImGui_DrawList_AddText(dl, tx, ty, 0xF0F4FAFF, display)
  end

  return changed, value, active or hovered
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

function seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
  return (btn or 14) * 4 + (vol_w or 52) + (pan_w or 40) + (midi_w or 28) + (gap or 3) * 6
end

function seq_box(x, y, w, h)
  w = math.max(0, w or 0)
  h = math.max(0, h or 0)
  return { x = x, y = y, w = w, h = h, x1 = x + w, y1 = y + h }
end

function seq_fit_mix_strip(avail_w, btn, gap, vol_w, pan_w, midi_w)
  vol_w = vol_w or 52.0
  pan_w = pan_w or 40.0
  midi_w = midi_w or 28.0
  btn = btn or 14.0
  gap = gap or 3.0
  local function width()
    return seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
  end
  while width() > avail_w do
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
  return btn, vol_w, pan_w, midi_w, width()
end

function seq_place_mix_strip(layout, x, y, btn, gap, vol_w, pan_w, midi_w, row_h)
  layout.gear = seq_box(x, y, btn, btn)
  x = x + btn + gap
  layout.vol = seq_box(x, y, vol_w, row_h)
  x = x + vol_w + gap
  layout.pan = seq_box(x, y, pan_w, row_h)
  x = x + pan_w + gap
  layout.midi = seq_box(x, y, midi_w, row_h)
  x = x + midi_w + gap
  layout.mute = seq_box(x, y, btn, btn)
  x = x + btn + gap
  layout.solo = seq_box(x, y, btn, btn)
  x = x + btn + gap
  layout.overlap = seq_box(x, y, btn, btn)
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

function seq_candidate_slot_scale(slot)
  if not slot then
    return nil
  end
  seq_normalize_slot_candidates(slot)
  local n = 0
  local b_lo, b_hi = 1e9, -1e9
  local w_lo, w_hi = 1e9, -1e9
  local d_lo, d_hi = 1e9, -1e9
  local list = slot.sample_candidates
  if type(list) ~= "table" then
    return nil
  end
  for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
    if seq_candidate_entry_taken(list[i]) then
      local p = seq_candidate_chip_props(list[i])
      local bright = p.brightness or p.freq
      n = n + 1
      if type(bright) == "number" then
        b_lo = math.min(b_lo, bright)
        b_hi = math.max(b_hi, bright)
      end
      w_lo = math.min(w_lo, p.weight)
      w_hi = math.max(w_hi, p.weight)
      if type(p.duration) == "number" and p.duration > 0 then
        d_lo = math.min(d_lo, p.duration)
        d_hi = math.max(d_hi, p.duration)
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

function seq_candidate_chip_props(entry)
  local sample = entry and entry.path and find_sample_by_path(entry.path) or nil
  local function num(key, fallback)
    if sample and type(sample[key]) == "number" then
      return sample[key]
    end
    if entry and type(entry[key]) == "number" then
      return entry[key]
    end
    return fallback
  end
  local dur = nil
  if sample and sample_map_duration then
    dur = sample_map_duration(sample)
  end
  if type(dur) ~= "number" or dur <= 0 then
    dur = num("effective_duration", num("duration", nil))
  end
  return {
    freq = num("dominant_freq", 440.0),
    brightness = num("brightness", nil),
    weight = math.max(0.0, math.min(1.0, num("sub_weight", 0.45))),
    duration = dur,
  }
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

function seq_place_sample_candidates(slot, x1, y0, y1, max_w)
  local empty = { boxes = {}, w = 0, hit = seq_box(0, 0, 0, 0), sq = 0 }
  x1, y0, y1 = x1 or 0, y0 or 0, y1 or 0
  max_w = max_w or 0
  local avail_h = y1 - y0
  if avail_h < 12.0 or max_w < 12.0 then
    return empty
  end
  local gap = 2.0
  local count = seq_candidate_visible_count(slot)
  local sq = math.max(12.0, math.min(avail_h, 24.0))
  local rows = 1
  local cols = count
  local function dims(size, n, r)
    r = math.max(1, r)
    local c = math.ceil(n / r)
    return r, c, c * size + (c - 1) * gap, math.min(n, r) * size + (math.min(n, r) - 1) * gap
  end
  local _, _, grid_w, grid_h = dims(sq, count, rows)
  if grid_w > max_w then
    local rows_fit = math.max(1, math.floor((avail_h + gap) / (sq + gap)))
    if rows_fit > 1 then
      rows = math.min(rows_fit, count)
      _, cols, grid_w, grid_h = dims(sq, count, rows)
    end
  end
  while grid_w > max_w and sq > 12.0 do
    sq = sq - 1.0
    _, cols, grid_w, grid_h = dims(sq, count, rows)
  end
  if grid_w > max_w then
    local fit_cols = math.max(1, math.floor((max_w + gap) / (sq + gap)))
    count = math.max(1, math.min(count, fit_cols * rows))
    rows, cols, grid_w, grid_h = dims(sq, count, rows)
  end
  if grid_w > max_w or grid_w <= 0 then
    return empty
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

function seq_draw_sample_candidate_square(dl, box, entry, is_active, is_hovered, scale, slot_n, alpha)
  if not dl or not box or box.w < 4 then
    return
  end
  local x, y, w, h = box.x, box.y, box.w, box.h
  local rounding = math.min(3.5, w * 0.22)
  local taken = seq_candidate_entry_taken(entry)
  local a = math.max(0.0, math.min(1.0, tonumber(alpha) or 1.0))
  local function ca(col, mul)
    if not col then
      return col
    end
    local orig_a = (col % 256) / 255.0
    return change_color_alpha(col, orig_a * a * (mul or 1.0))
  end
  local bg = is_active and (taken and 0x122016FF or UI_THEME.accent_fill) or (is_hovered and 0x161E1AFF or 0x0C1210FF)
  local edge = UI_THEME.border
  local edge_w = 1.0
  if is_active then
    edge = 0xFFFFFF80
    edge_w = 1.8
  elseif is_hovered then
    edge = 0xE8EEEAFF
  elseif taken then
    edge = UI_THEME.border_hvr
  end

  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, ca(bg), rounding)

  if taken then
    local props = seq_candidate_chip_props(entry)
    local hue = seq_candidate_freq_hue(props.freq)
    local bright_src = props.brightness or props.freq
    local bright_g = seq_candidate_log_unit(bright_src, 100.0, 2500.0)
    local bright_t = bright_g
    local weight_t = props.weight
    if scale then
      bright_t = seq_candidate_unit_in_range(bright_src, scale.bright_lo, scale.bright_hi, bright_g)
      weight_t = seq_candidate_unit_in_range(props.weight, scale.weight_lo, scale.weight_hi, props.weight)
    end
    local sat = 0.55 + weight_t * 0.40
    if is_hovered then
      bright_t = math.min(1.0, bright_t + 0.08)
    end
    if is_active then
      bright_t = math.min(1.0, bright_t + 0.10)
    end
    local col_top = seq_candidate_hsv_to_color(hue, sat, 0.52 + bright_t * 0.46, a)
    local col_bot = seq_candidate_hsv_to_color(hue, math.min(1.0, sat + 0.08), 0.22 + bright_t * 0.28, a)

    -- MultiColor fills are square; clip rounded rects per band so the chip
    -- follows the same corner radius as the outline.
    local bands = math.max(4, math.min(10, math.floor(h + 0.5)))
    if r.ImGui_DrawList_PushClipRect then
      for i = 0, bands - 1 do
        local t = (i + 0.5) / bands
        local col = blend_colors(col_top, col_bot, t)
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
      ca(0xFFFFFF40), rounding + 1.0, 0, 2.0)
  end
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, ca(edge), rounding, 0, edge_w)

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
    local num_col = ca(taken and 0xFFFFFF72 or 0xC8D0C850)
    local sh_col = ca(0x00000044)
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
  local scale = seq_candidate_slot_scale(slot)
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
  for i = 1, #boxes do
    local box = boxes[i]
    if box and box.w > 0 and box.h > 0 then
      r.ImGui_SetCursorScreenPos(ctx, box.x, box.y)
      r.ImGui_InvisibleButton(ctx, "##seq_cand_" .. tostring(slot.id) .. "_" .. i, box.w, box.h)
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
            .. (is_active and "\nSelected — sample changes save here" or "\nClick to recall")
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
  local expand_w = opts.hide_expand and 0.0 or 26.0
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

  local layout = {
    mode = mode,
    lane_h = lane_h,
    expand = seq_box(0, 0, 0, 0),
    name = seq_box(0, 0, 0, 0),
    gear = seq_box(0, 0, 0, 0),
    vol = seq_box(0, 0, 0, 0),
    pan = seq_box(0, 0, 0, 0),
    midi = seq_box(0, 0, 0, 0),
    mute = seq_box(0, 0, 0, 0),
    solo = seq_box(0, 0, 0, 0),
    overlap = seq_box(0, 0, 0, 0),
    env = seq_box(0, 0, 0, 0),
    mix_hit = seq_box(0, 0, 0, 0),
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
    local hit_x0 = (env_w > 0) and layout.env.x or layout.gear.x
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
    layout.gear = seq_box(cx, y, btn, btn); cx = cx + btn + gap
    layout.mute = seq_box(cx, y, btn, btn); cx = cx + btn + gap
    layout.solo = seq_box(cx, y, btn, btn); cx = cx + btn + gap
    layout.overlap = seq_box(cx, y, btn, btn); cx = cx + btn + gap
    layout.midi = seq_box(cx, y, midi_w, btn)
    y = y + btn + 3.0
    layout.vol = seq_box(inner_x0, y, inner_w, bar_h)
    y = y + bar_h + 3.0
    layout.pan = seq_box(inner_x0, y, inner_w, bar_h)
    y = y + bar_h + 3.0
    env_h = math.max(12.0, (y1 - pad) - y)
    layout.env = seq_box(inner_x0, y, inner_w, env_h)
    layout.mix_hit = seq_box(inner_x0, layout.gear.y, inner_w, (y1 - pad) - layout.gear.y)
  end

  return layout
end

function seq_draw_track_name_and_expand(dl, slot, layout, expanded, name_alpha, expand_color, fallback_name)
  if not layout or not slot then
    return
  end
  local exp = layout.expand
  if exp and exp.w > 0 then
    local exp_label = expanded and "[-]" or "[+]"
    local tw, th = r.ImGui_CalcTextSize(ctx, exp_label)
    r.ImGui_DrawList_AddText(
      dl,
      exp.x + (exp.w - (tw or 16)) * 0.5,
      exp.y + (exp.h - (th or 12)) * 0.5,
      expand_color or 0xFFDFAAFF,
      exp_label
    )
  end
  local name_box = layout.name
  if name_box and name_box.w > 4 then
    local name_txt = seq_truncate_text_to_width(slot.name or fallback_name or "Track", name_box.w)
    local _, nh = r.ImGui_CalcTextSize(ctx, name_txt)
    r.ImGui_DrawList_AddText(
      dl,
      name_box.x,
      name_box.y + (name_box.h - (nh or 12)) * 0.5,
      build_color_rrgbbaa(255, 255, 255, name_alpha or 255),
      name_txt
    )
  end
end

function seq_lane_mix_controls_hit(row_pos, mx, my, x0, timeline_x0, map_nav_w)
  if not row_pos or not row_pos.row or row_pos.row.type ~= "note" then
    return false
  end
  local layout = row_pos.ctrl
  if not layout and x0 and timeline_x0 then
    local nav_w = map_nav_w or seq_track_nav_width(row_pos.y1 - row_pos.y0)
    layout = seq_get_track_control_layout(
      x0, row_pos.y0, timeline_x0 - nav_w - 6.0, row_pos.y1,
      row_pos.row and row_pos.row.slot
    )
  end
  return seq_layout_hit(layout and layout.mix_hit, mx, my)
    or seq_layout_hit(layout and layout.candidates, mx, my)
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

  local function mark_hover()
    if r.ImGui_IsItemHovered(ctx) then
      hovered = true
    end
  end

  -- Open the undo session before mutating slot fields so the "before"
  -- snapshot holds the old value (callers' begin_seq_undo is then a no-op).
  local function begin_mix_undo()
    if not seq_undo_is_open() then
      begin_seq_undo("Adjust sequencer mix")
    end
    seq_undo_commit_on_release = true
  end

  local gear = layout.gear
  if gear and gear.w > 0 then
    local layering_open = state.seq_layering_slot_id == slot.id
    if seq_layering_button("##seq_layering_" .. slot.id, dl, gear.x, gear.y, gear.w, layering_open) then
      if layering_open then
        state.seq_layering_slot_id = nil
      else
        state.seq_layering_slot_id = slot.id
        seq_layering_seed_from_track(slot)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      hovered = true
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Drum layering")
      end
    end
  end

  local vol = layout.vol
  if vol and vol.w > 0 then
    local vol_changed, vol_val, vol_hot = seq_rect_drag_control(
      "##seq_track_vol_" .. slot.id, dl, vol.x, vol.y, vol.w, vol.h,
      slot.volume, 0.0, 4.0,
      {
        fill_color = 0x6AA0E0FF,
        unity = 1.0,
        reset = 1.0,
        horizontal = true,
        to_pos = seq_vol_amp_to_pos,
        from_pos = seq_vol_pos_to_amp,
        format_value = seq_format_track_volume,
      }
    )
    if vol_hot then hovered = true end
    if vol_changed then
      begin_mix_undo()
      slot.volume = vol_val
      changed_mix = true
    end
  end

  local pan = layout.pan
  if pan and pan.w > 0 then
    local pan_changed, pan_val, pan_hot = seq_rect_drag_control(
      "##seq_track_pan_" .. slot.id, dl, pan.x, pan.y, pan.w, pan.h,
      slot.pan, -1.0, 1.0,
      {
        bipolar = true,
        fill_color = 0x9FE3B5FF,
        horizontal = true,
        reset = 0.0,
        format_value = seq_format_track_pan,
      }
    )
    if pan_hot then hovered = true end
    if pan_changed then
      begin_mix_undo()
      slot.pan = pan_val
      changed_mix = true
    end
  end

  local midi = layout.midi
  if midi and midi.w > 0 then
    local midi_learning = state.seq_midi_learn_slot_id == slot.id
    local midi_open = state.seq_midi_popup_slot_id == slot.id
    if seq_midi_note_button("##seq_midi_" .. slot.id, dl, midi.x, midi.y, midi.w, midi.h, slot, midi_learning or midi_open) then
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
      seq_midi_ensure_jsfx()
      if state.seq_midi_learn_slot_id == slot.id then
        state.seq_midi_learn_slot_id = nil
      else
        state.seq_midi_learn_slot_id = slot.id
        state.seq_midi_learn_range = false
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      hovered = true
      if r.ImGui_SetTooltip then
        seq_normalize_slot_midi(slot)
        local lo, hi = slot.midi_lo, slot.midi_hi
        local range = (lo == hi)
            and (seq_midi_note_name(lo) .. "  (" .. tostring(lo) .. ")")
            or (seq_midi_note_name(lo) .. "–" .. seq_midi_note_name(hi)
                .. "  (" .. tostring(lo) .. "–" .. tostring(hi) .. ")")
        r.ImGui_SetTooltip(ctx, "MIDI " .. range
          .. "\nClick to assign notes  ·  Right-click: learn  ·  Alt-click: GM default")
      end
    end
  end

  local mute = layout.mute
  if mute and mute.w > 0 then
    if seq_ms_button("##seq_mute_" .. slot.id, dl, mute.x, mute.y, mute.w, "M", slot.mute, 0xE05050FF) then
      begin_mix_undo()
      slot.mute = not slot.mute
      changed_mix = true
    end
    mark_hover()
  end
  local solo = layout.solo
  if solo and solo.w > 0 then
    if seq_ms_button("##seq_solo_" .. slot.id, dl, solo.x, solo.y, solo.w, "S", slot.solo, 0xE8A020FF) then
      begin_mix_undo()
      slot.solo = not slot.solo
      changed_mix = true
    end
    mark_hover()
  end
  local overlap = layout.overlap
  if overlap and overlap.w > 0 then
    if seq_ms_button("##seq_overlap_" .. slot.id, dl, overlap.x, overlap.y, overlap.w, "O", slot.overlap, 0x40C8C8FF) then
      begin_mix_undo()
      slot.overlap = not slot.overlap
      changed_mix = true
      overlap_changed = true
    end
    if r.ImGui_IsItemHovered(ctx) then
      hovered = true
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, slot.overlap
          and "Overlap on — hits can overlap the next note"
          or "Overlap off — crop to the next hit")
      end
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

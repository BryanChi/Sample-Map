-- Sample Map Browser module: seq_generate
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_dim_color_rrgbbaa(color, dim)
  if not dim then
    return color
  end
  local cr, cg, cb = extract_rgb_rrgbbaa(color or 0xFFFFFFFF)
  local alpha = math.max(20, math.floor((color or 0xFF) % 256 * 0.38))
  return build_color_rrgbbaa(cr, cg, cb, alpha)
end

function seq_note_sustain_split_x(cell_x1, draw_x0, draw_x1)
  local cell_content_end = cell_x1 - 2
  if draw_x1 > cell_content_end + 1.0 and draw_x0 < cell_content_end - 0.5 then
    return cell_content_end
  end
  return nil
end

-- High-contrast palette so different variant samples stay easy to tell apart.
SEQ_VARY_COLOR_PALETTE = {
  {230, 25, 75},
  {60, 180, 75},
  {0, 130, 200},
  {245, 130, 48},
  {145, 30, 180},
  {70, 240, 240},
  {240, 50, 230},
  {210, 245, 60},
  {0, 128, 128},
  {255, 225, 25},
  {128, 0, 0},
  {0, 0, 128},
  {170, 255, 195},
  {255, 99, 146},
  {139, 92, 246},
  {249, 115, 22},
}

-- Stable color keyed by sample path (not frequency).
-- Same file always gets the same RGB so copies match the source note.
function seq_sample_vary_rgb(path)
  if type(path) == "table" then
    path = path.path
  end
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local h = 2166136261
  for i = 1, #path do
    h = (h + string.byte(path, i)) * 16777619
    h = h % 2147483647
  end
  local pal = SEQ_VARY_COLOR_PALETTE
  local rgb = pal[(h % #pal) + 1]
  return rgb[1], rgb[2], rgb[3]
end

function seq_note_vary_origin_path(note, slot, region)
  if note and type(note.vary_origin_path) == "string" and note.vary_origin_path ~= "" then
    return note.vary_origin_path
  end
  local path = seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, region))
  return path or (slot and slot.sample_path) or (note and note.sample_path)
end

function seq_note_vary_rgb(note, sounding_path)
  local stored = note and note.vary_rgb
  if type(stored) == "table" and stored[1] and stored[2] and stored[3] then
    return stored[1], stored[2], stored[3]
  end
  return seq_sample_vary_rgb(sounding_path)
end

function seq_stamp_vary_visual(target, sounding_path, origin_path)
  if type(target) ~= "table" or type(sounding_path) ~= "string" or sounding_path == "" then
    return
  end
  if type(origin_path) == "string" and origin_path ~= "" and origin_path ~= sounding_path then
    if type(target.vary_origin_path) ~= "string" or target.vary_origin_path == "" then
      target.vary_origin_path = origin_path
    end
    if type(target.vary_rgb) ~= "table" then
      local vr, vg, vb = seq_sample_vary_rgb(sounding_path)
      if vr then
        target.vary_rgb = { vr, vg, vb }
      end
    end
  end
end

function draw_seq_note_vary_marks(dl, draw_x0, draw_x1, block_y0, block_y1, vr, vg, vb, note_alpha)
  local w = draw_x1 - draw_x0
  local h = block_y1 - block_y0
  if w < 6.0 or h < 6.0 then
    return
  end
  local mark_a = math.max(90, math.min(255, math.floor(note_alpha)))
  local col = build_color_rrgbbaa(vr, vg, vb, mark_a)
  local stripe_w = math.min(2.5, w * 0.18)
  r.ImGui_DrawList_AddRectFilled(dl, draw_x0, block_y0, draw_x0 + stripe_w, block_y1, col, 0)
  local pip = math.min(6.0, w * 0.35, h * 0.45)
  r.ImGui_DrawList_AddTriangleFilled(
    dl,
    draw_x0, block_y0,
    draw_x0 + pip, block_y0,
    draw_x0, block_y0 + pip,
    col
  )
end

function draw_seq_note_body(dl, draw_x0, draw_x1, block_y0, block_y1, br, bg, bb, note_alpha, border_alpha, sustain_split_x, vr, vg, vb)
  local varied = vr ~= nil
  local fill_x1 = sustain_split_x or draw_x1
  if varied and r.ImGui_DrawList_AddRectFilledMultiColor and (fill_x1 - draw_x0) >= 4.0 then
    local c_l = build_color_rrgbbaa(br, bg, bb, note_alpha)
    local c_r = build_color_rrgbbaa(vr, vg, vb, note_alpha)
    r.ImGui_DrawList_AddRectFilledMultiColor(dl, draw_x0, block_y0, fill_x1, block_y1, c_l, c_r, c_r, c_l)
  else
    r.ImGui_DrawList_AddRectFilled(
      dl, draw_x0, block_y0, fill_x1, block_y1,
      build_color_rrgbbaa(br, bg, bb, note_alpha), 0
    )
  end
  r.ImGui_DrawList_AddRect(
    dl, draw_x0, block_y0, fill_x1, block_y1,
    build_color_rrgbbaa(255, 255, 255, border_alpha), 0, 0, 1.0
  )

  if sustain_split_x then
    -- Tail is a thinner faded bar so grid lines stay readable under long samples.
    local tail_inset = (block_y1 - block_y0) * 0.32
    local ty0 = block_y0 + tail_inset
    local ty1 = block_y1 - tail_inset
    local tail_a0 = math.max(6, math.floor(note_alpha * 0.18))
    local tail_a1 = math.max(0, math.floor(note_alpha * 0.04))
    local tr, tg, tb = br, bg, bb
    if varied then
      tr, tg, tb = vr, vg, vb
    end
    if r.ImGui_DrawList_AddRectFilledMultiColor then
      local c0 = build_color_rrgbbaa(tr, tg, tb, tail_a0)
      local c1 = build_color_rrgbbaa(tr, tg, tb, tail_a1)
      r.ImGui_DrawList_AddRectFilledMultiColor(dl, sustain_split_x, ty0, draw_x1, ty1, c0, c1, c1, c0)
    else
      r.ImGui_DrawList_AddRectFilled(
        dl, sustain_split_x, ty0, draw_x1, ty1,
        build_color_rrgbbaa(tr, tg, tb, tail_a0), 0
      )
    end
  end

end

function draw_seq_stutter_note_hits(dl, qn_to_x, note, note_qn, step_qn, draw_x0, draw_x1, block_y0, block_y1, br, bg, bb, note_alpha, border_alpha, vr, vg, vb)
  local count = seq_stutter_count(note)
  if count <= 1 or not qn_to_x then
    draw_seq_note_body(dl, draw_x0, draw_x1, block_y0, block_y1, br, bg, bb, note_alpha, border_alpha, nil, vr, vg, vb)
    return
  end
  local h = block_y1 - block_y0
  local span_a = math.max(12, math.floor(note_alpha * 0.18))
  local inset = h * 0.30
  r.ImGui_DrawList_AddRectFilled(
    dl, draw_x0, block_y0 + inset, draw_x1, block_y1 - inset,
    build_color_rrgbbaa(br, bg, bb, span_a), 0
  )

  local attack_a = math.min(255, math.max(160, note_alpha + 50))
  local tail_a = math.max(28, math.floor(note_alpha * 0.38))
  local start_a = math.min(255, math.max(170, border_alpha + 90))
  local note_off = (note and note.offset_qn) or 0.0
  local has_mc = r.ImGui_DrawList_AddRectFilledMultiColor ~= nil

  for hi = 1, count do
    local hit_off = seq_note_param_value(note, "offset_qn", hi)
    if hit_off == nil then
      hit_off = note_off
    end
    local off0, off1, slice_qn = seq_stutter_hit_span(note, hi, step_qn)
    local s0 = note_qn + hit_off + off0
    local sx0 = (hi == 1) and draw_x0 or qn_to_x(s0)
    if sx0 < draw_x0 then sx0 = draw_x0 end
    if sx0 < draw_x1 then
    local slice_px = qn_to_x(s0 + slice_qn) - qn_to_x(s0)
    if slice_px < 1.0 then slice_px = 1.0 end
    local gap = (slice_px >= 5.0) and math.max(1.4, math.min(3.2, slice_px * 0.20)) or 0.8
    local sx1 = math.min(draw_x1, qn_to_x(s0 + slice_qn) - gap)
    if sx1 < sx0 + 1.0 then
      sx1 = math.min(draw_x1, sx0 + 1.0)
    end

    local tr = (vr ~= nil) and vr or br
    local tg = (vg ~= nil) and vg or bg
    local tb = (vb ~= nil) and vb or bb
    if has_mc and (sx1 - sx0) >= 3.5 then
      local c0 = build_color_rrgbbaa(br, bg, bb, note_alpha)
      local c1 = build_color_rrgbbaa(tr, tg, tb, tail_a)
      r.ImGui_DrawList_AddRectFilledMultiColor(dl, sx0, block_y0, sx1, block_y1, c0, c1, c1, c0)
    else
      r.ImGui_DrawList_AddRectFilled(
        dl, sx0, block_y0, sx1, block_y1,
        build_color_rrgbbaa(br, bg, bb, note_alpha), 0
      )
    end

    local aw = math.min(3.0, math.max(1.2, (sx1 - sx0) * 0.30))
    local ar = math.floor(br * 0.28 + 255 * 0.72)
    local ag = math.floor(bg * 0.28 + 255 * 0.72)
    local ab = math.floor(bb * 0.28 + 255 * 0.72)
    r.ImGui_DrawList_AddRectFilled(dl, sx0, block_y0, sx0 + aw, block_y1, build_color_rrgbbaa(ar, ag, ab, attack_a), 0)
    r.ImGui_DrawList_AddLine(dl, sx0, block_y0, sx0, block_y1, build_color_rrgbbaa(255, 255, 255, start_a), 1.4)
    if h >= 8.0 and (sx1 - sx0) >= 4.0 then
      local pip = math.min(4.5, h * 0.38, (sx1 - sx0) * 0.45)
      r.ImGui_DrawList_AddTriangleFilled(
        dl,
        sx0, block_y0,
        sx0 + pip, block_y0,
        sx0, block_y0 + pip,
        build_color_rrgbbaa(255, 255, 255, start_a)
      )
    end
    end
  end
end

function draw_seq_note_hover(dl, mx, my, draw_x0, block_y0, draw_x1, block_y1, trigger_x1)
  local x1 = trigger_x1 or draw_x1
  if mx < draw_x0 - 2.0 or mx > x1 + 2.0 or my < block_y0 - 2.0 or my > block_y1 + 2.0 then
    return
  end
  r.ImGui_DrawList_AddRectFilled(dl, draw_x0, block_y0, x1, block_y1, 0xFFFFFF38, 2.0)
  r.ImGui_DrawList_AddRect(dl, draw_x0 - 1.0, block_y0 - 1.0, x1 + 1.0, block_y1 + 1.0, 0xFFFFFFF0, 2.0, 0, 1.6)
end

SEQ_DECAY_CIRCLE_R = 5.0
SEQ_DECAY_CIRCLE_HIT_R = 9.0
SEQ_DECAY_LINE_HIT = 7.0
SEQ_DECAY_CURVE_HIT = 10.0
seq_decay_hits = {}

function seq_decay_clear_hits()
  seq_decay_hits = {}
end

function seq_decay_add_hit(hit)
  seq_decay_hits[#seq_decay_hits + 1] = hit
end

function seq_decay_kind_is_circle(kind)
  return kind == "fade_in" or kind == "fade_out"
end

function seq_decay_kind_is_curve(kind)
  return kind == "curve_in" or kind == "curve_out"
end

function seq_decay_hit_at(mx, my)
  local hits = seq_decay_hits
  if not hits or #hits == 0 then
    return nil
  end
  local best, best_d = nil, 1e9
  for i = 1, #hits do
    local h = hits[i]
    if seq_decay_kind_is_circle(h.kind) then
      local dx = mx - h.cx
      local dy = my - h.cy
      local d = dx * dx + dy * dy
      local rad = h.hit_r or SEQ_DECAY_CIRCLE_HIT_R
      if d <= rad * rad and d < best_d then
        best = h
        best_d = d
      end
    end
  end
  if best then
    return best
  end
  best, best_d = nil, 1e9
  for i = 1, #hits do
    local h = hits[i]
    if seq_decay_kind_is_curve(h.kind) and h.cx then
      local dx = mx - h.cx
      local dy = my - h.cy
      local d = dx * dx + dy * dy
      local rad = (h.hit_r or SEQ_DECAY_CIRCLE_HIT_R)
      if d <= rad * rad and d < best_d then
        best = h
        best_d = d
      end
    end
  end
  if best then
    return best
  end
  best, best_d = nil, 1e9
  for i = 1, #hits do
    local h = hits[i]
    if seq_decay_kind_is_curve(h.kind) and h.x0 and mx >= h.x0 - 1 and mx <= h.x1 + 1 then
      local y = seq_fade_curve_y_at(mx, h.x0, h.x1, h.y0, h.y1, h.shape, h.curve, h.fade_out)
      local d = math.abs(my - y)
      if d <= SEQ_DECAY_CURVE_HIT and d < best_d then
        best = h
        best_d = d
      end
    end
  end
  if best then
    return best
  end
  for i = 1, #hits do
    local h = hits[i]
    if h.kind == "end" and mx >= h.x0 and mx <= h.x1 and my >= h.y0 and my <= h.y1 then
      return h
    end
  end
  return nil
end

function seq_fade_curve_y_at(x, x0, x1, y0, y1, shape, curve, fade_out)
  local span = math.max(1.0, x1 - x0)
  local u = (x - x0) / span
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local t = fade_out and (1.0 - u) or u
  local gain = seq_native_fade_gain(t, shape, curve)
  return y1 - (y1 - y0) * gain
end

function seq_draw_native_fade_curve(dl, x0, x1, y0, y1, shape, fade_out, col, fill_col, curve)
  if x1 - x0 < 2.0 then
    return nil, nil
  end
  local h = y1 - y0
  if h < 2.0 then
    return nil, nil
  end
  local steps = math.max(6, math.min(24, math.floor((x1 - x0) / 3.0)))
  local prev_x, prev_y = nil, nil
  local mid_x, mid_y = nil, nil
  for i = 0, steps do
    local u = i / steps
    local t = fade_out and (1.0 - u) or u
    local gain = seq_native_fade_gain(t, shape, curve)
    local x = x0 + (x1 - x0) * u
    local y = y1 - h * gain
    if fill_col then
      r.ImGui_DrawList_AddLine(dl, x, y, x, y1, fill_col, 1.0)
    end
    if prev_x then
      r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, x, y, col, 1.6)
    end
    if i == math.floor(steps * 0.5) then
      mid_x, mid_y = x, y
    end
    prev_x, prev_y = x, y
  end
  return mid_x, mid_y
end

function draw_seq_decay_handles(dl, note, slot, region, pattern, step_key, note_qn, step_qn, qn_to_x, draw_x0, draw_x1, block_y0, block_y1, mx, my, accent, selected)
  if not note then
    return
  end
  local line_col = selected and 0xFFFFFFF0 or 0xFFFFFFAA
  local circle_fill = (accent and seq_lane_color_with_alpha(accent, 255)) or 0xFFD166FF
  local circle_r = SEQ_DECAY_CIRCLE_R
  local cy = block_y0
  local start_x = draw_x0
  local end_x = draw_x1
  local fade_in_qn = seq_note_fade_qn(note, "in")
  local fade_out_qn = seq_note_fade_qn(note, "out")
  local note_off = note.offset_qn or 0.0
  local note_len = seq_note_draw_length_qn(region, pattern, slot, slot and slot.id, step_key, note, nil, step_qn)
  local note_w = math.max(1.0, end_x - start_x)
  local curve_hits = {}
  if fade_in_qn > 1e-6 and note_len > 1e-9 then
    local fade_x1 = start_x + note_w * math.min(1.0, fade_in_qn / note_len)
    local shape = seq_note_fade_shape(note, "in")
    local curve = seq_note_fade_curve(note, "in")
    local mxh, myh = seq_draw_native_fade_curve(
      dl, start_x, math.min(end_x, fade_x1), block_y0, block_y1,
      shape, false,
      seq_lane_color_with_alpha(circle_fill, 220),
      0x00000033,
      curve
    )
    curve_hits[#curve_hits + 1] = {
      kind = "curve_in",
      cx = mxh,
      cy = myh,
      x0 = start_x,
      x1 = math.min(end_x, fade_x1),
      y0 = block_y0,
      y1 = block_y1,
      shape = shape,
      curve = curve,
      fade_out = false,
    }
  end
  if fade_out_qn > 1e-6 and note_len > 1e-9 then
    local fade_x0 = end_x - note_w * math.min(1.0, fade_out_qn / note_len)
    local shape = seq_note_fade_shape(note, "out")
    local curve = seq_note_fade_curve(note, "out")
    local mxh, myh = seq_draw_native_fade_curve(
      dl, math.max(start_x, fade_x0), end_x, block_y0, block_y1,
      shape, true,
      seq_lane_color_with_alpha(circle_fill, 220),
      0x00000033,
      curve
    )
    curve_hits[#curve_hits + 1] = {
      kind = "curve_out",
      cx = mxh,
      cy = myh,
      x0 = math.max(start_x, fade_x0),
      x1 = end_x,
      y0 = block_y0,
      y1 = block_y1,
      shape = shape,
      curve = curve,
      fade_out = true,
    }
  end

  local last_grid_x0 = end_x
  if qn_to_x and note_len and note_len > 1e-9 then
    last_grid_x0 = qn_to_x(note_qn + note_off + math.max(0.0, note_len - (step_qn or 0.25)))
  end
  if last_grid_x0 > end_x - 8.0 then
    last_grid_x0 = end_x - 8.0
  end
  if last_grid_x0 < start_x then
    last_grid_x0 = start_x
  end

  local start_hit = {
    kind = "fade_in",
    cx = start_x,
    cy = cy,
    hit_r = SEQ_DECAY_CIRCLE_HIT_R,
    note = note,
    region_id = region and region.id,
    track_id = slot and slot.id,
    step_key = step_key,
    note_qn = note_qn,
    note_len = note_len,
  }
  local end_line_hit = {
    kind = "end",
    x0 = last_grid_x0,
    x1 = end_x + SEQ_DECAY_LINE_HIT,
    y0 = block_y0 - 2.0,
    y1 = block_y1 + 2.0,
    note = note,
    region_id = region and region.id,
    track_id = slot and slot.id,
    step_key = step_key,
    note_qn = note_qn,
    note_len = note_len,
  }
  local end_hit = {
    kind = "fade_out",
    cx = end_x,
    cy = cy,
    hit_r = SEQ_DECAY_CIRCLE_HIT_R,
    note = note,
    region_id = region and region.id,
    track_id = slot and slot.id,
    step_key = step_key,
    note_qn = note_qn,
    note_len = note_len,
  }
  seq_decay_add_hit(start_hit)
  seq_decay_add_hit(end_hit)
  for i = 1, #curve_hits do
    local ch = curve_hits[i]
    ch.note = note
    ch.region_id = region and region.id
    ch.track_id = slot and slot.id
    ch.step_key = step_key
    ch.note_qn = note_qn
    ch.note_len = note_len
    ch.hit_r = SEQ_DECAY_CIRCLE_HIT_R
    seq_decay_add_hit(ch)
  end
  seq_decay_add_hit(end_line_hit)

  local hover = nil
  if mx and my then
    local dxs = mx - start_x
    local dys = my - cy
    local dxe = mx - end_x
    local dye = my - cy
    if dxs * dxs + dys * dys <= SEQ_DECAY_CIRCLE_HIT_R * SEQ_DECAY_CIRCLE_HIT_R then
      hover = "fade_in"
    elseif dxe * dxe + dye * dye <= SEQ_DECAY_CIRCLE_HIT_R * SEQ_DECAY_CIRCLE_HIT_R then
      hover = "fade_out"
    else
      local best_d = 1e9
      for i = 1, #curve_hits do
        local ch = curve_hits[i]
        if ch.cx then
          local dx = mx - ch.cx
          local dcy = my - ch.cy
          local d = dx * dx + dcy * dcy
          if d <= SEQ_DECAY_CIRCLE_HIT_R * SEQ_DECAY_CIRCLE_HIT_R and d < best_d then
            hover = ch.kind
            best_d = d
          end
        end
        if not hover and ch.x0 and mx >= ch.x0 - 1 and mx <= ch.x1 + 1 then
          local y = seq_fade_curve_y_at(mx, ch.x0, ch.x1, ch.y0, ch.y1, ch.shape, ch.curve, ch.fade_out)
          local d = math.abs(my - y)
          if d <= SEQ_DECAY_CURVE_HIT and d < best_d then
            hover = ch.kind
            best_d = d
          end
        end
      end
      if not hover and mx >= end_line_hit.x0 and mx <= end_line_hit.x1 and my >= end_line_hit.y0 and my <= end_line_hit.y1 then
        hover = "end"
      end
    end
  end

  r.ImGui_DrawList_AddLine(dl, start_x, block_y0, start_x, block_y1, hover == "fade_in" and 0xFFFFFFFF or line_col, 1.6)
  r.ImGui_DrawList_AddLine(dl, end_x, block_y0, end_x, block_y1, hover == "end" and 0xFFFFFFFF or 0xFFFFFFF8, hover == "end" and 3.0 or 2.4)
  if hover == "end" then
    r.ImGui_DrawList_AddRectFilled(dl, last_grid_x0, block_y0, end_x, block_y1, 0xFFFFFF22, 0)
  end

  local function draw_circle(cx, hovered, radius)
    if not cx then
      return
    end
    radius = radius or circle_r
    local r_vis = hovered and (radius + 1.2) or radius
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, r_vis, hovered and 0xFFFFFFFF or circle_fill, 16)
    r.ImGui_DrawList_AddCircle(dl, cx, cy, r_vis, 0xFFFFFFF0, 16, 1.4)
  end
  draw_circle(start_x, hover == "fade_in")
  draw_circle(end_x, hover == "fade_out")
  for i = 1, #curve_hits do
    local ch = curve_hits[i]
    if ch.cx and ch.cy then
      local hovered = hover == ch.kind
      local r_vis = hovered and 4.2 or 3.2
      r.ImGui_DrawList_AddCircleFilled(dl, ch.cx, ch.cy, r_vis, hovered and 0xFFFFFFFF or circle_fill, 12)
      r.ImGui_DrawList_AddCircle(dl, ch.cx, ch.cy, r_vis, 0xFFFFFFF0, 12, 1.2)
    end
  end
end

function draw_seq_note_probability_skip(dl, x0, y0, x1, y1, alpha)
  if x1 - x0 < 6.0 or y1 - y0 < 6.0 then
    return
  end
  alpha = math.max(40, math.min(220, alpha or 160))
  local pad = 3.0
  local color = build_color_rrgbbaa(255, 196, 92, alpha)
  r.ImGui_DrawList_AddLine(dl, x0 + pad, y0 + pad, x1 - pad, y1 - pad, color, 1.6)
  r.ImGui_DrawList_AddLine(dl, x1 - pad, y0 + pad, x0 + pad, y1 - pad, color, 1.6)
end

function seq_draw_unfocused_note_marks(dl, active, row_y0, row_y1, selected_region_id, step_qn, qn_to_x, start_qn, col, base_color)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return
  end
  local cell_qn = (start_qn or 0.0) + (col or 0) * (step_qn or 0.25)
  local cell_end = cell_qn + (step_qn or 0.25)
  local br, bg, bb = extract_rgb_rrgbbaa(base_color or get_sample_dot_color(nil))
  local mark = build_color_rrgbbaa(br, bg, bb, 88)
  local y0 = row_y0 + 4.0
  local y1 = row_y1 - 4.0
  for pi = 1, #pack do
    local entry = pack[pi]
    if type(entry) == "table" and type(entry.note) == "table"
        and entry.region_id ~= selected_region_id then
      local vis = seq_entry_vis_qn(entry)
      if vis + 1e-9 >= cell_qn and vis < cell_end + 1e-9 then
        local x0 = qn_to_x(vis) + 1.0
        local x1 = qn_to_x(cell_end) - 1.0
        if x1 > x0 + 1.0 then
          r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, mark, 0)
        end
      end
    end
  end
end

function seq_draw_lane_notes_lod(dl, active, row_y0, row_y1, selected_region_id, step_qn, qn_to_x, start_qn, col, base_color)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return
  end
  local cell_qn = (start_qn or 0.0) + (col or 0) * (step_qn or 0.25)
  local cell_end = cell_qn + (step_qn or 0.25)
  local br, bg, bb = extract_rgb_rrgbbaa(base_color or get_sample_dot_color(nil))
  local block_y0 = row_y0 + 4.0
  local block_y1 = row_y1 - 4.0
  for pi = 1, #pack do
    local entry = pack[pi]
    local note = entry and entry.note
    if type(note) == "table" and entry.region_id == selected_region_id then
      local vis = seq_entry_vis_qn(entry)
      if vis + 1e-9 >= cell_qn and vis < cell_end + 1e-9 then
        local draw_x0 = qn_to_x(vis)
        local draw_x1 = math.max(draw_x0 + 1.0, qn_to_x(vis + seq_note_lod_length_qn(note, step_qn)))
        r.ImGui_DrawList_AddRectFilled(
          dl, draw_x0, block_y0, draw_x1, block_y1,
          build_color_rrgbbaa(br, bg, bb, 220), 0
        )
      end
    end
  end
end

function seq_draw_lane_packed_notes(dl, slot, active, row_y0, row_y1, cx0, cx1, selected_region_id, now_t, step_qn, qn_to_x, edit_def, edit_style, mx, my, hover_on_razor, hover_qn, start_qn, col)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return
  end
  local hover_pick = nil
  if (not hover_on_razor) and type(hover_qn) == "number" and my >= row_y0 and my <= row_y1 then
    hover_pick = seq_pick_packed_note(active, hover_qn, start_qn, col, step_qn)
  end
  for pi = 1, #pack do
    local entry = pack[pi]
    local note = entry.note
    if type(note) == "table" and entry.region_id == selected_region_id then
      local note_qn = entry.abs_qn or 0.0
      local note_off = note.offset_qn or 0.0
      -- Occupancy cells exist so hit-testing can find spanning stutter notes.
      -- Draw the note only from the cell that contains its visual start.
      local vis_x = qn_to_x(note_qn + note_off)
      if vis_x + 2 >= cx0 - 1.0 and vis_x < cx1 + 1.0 then
      local cell_selected = entry.region_id == selected_region_id
      local note_fx = get_seq_note_anim(entry.region_id, slot.id, entry.key, now_t)
      -- Delete ghosts are drawn from the anim snapshot after the cell loop.
      -- Skip the live copy so the click frame does not draw both.
      if not (note_fx and note_fx.kind == "delete") then
      local fx_t = note_fx and note_fx.t or 1.0
      local prob_region = get_seq_region_by_id(entry.region_id)
      local draw_note = (seq_stutter_count(note) > 1) and seq_note_for_stutter_hit(note, 1) or note
      local vary_amt = seq_random_vary_amount(note, prob_region, slot.id, entry.key, 1)
      local resolved_path, resolved_sample = seq_resolve_note_sample(draw_note, slot, vary_amt, prob_region, slot.id, entry.key)
      local origin_path = seq_note_vary_origin_path(note, slot, prob_region)
      local origin_sample = find_sample_by_path(origin_path)
      local base = get_sample_dot_color(origin_sample or resolved_sample or find_sample_by_path(resolved_path or origin_path))
      local vary_r, vary_g, vary_b = nil, nil, nil
      if resolved_path and origin_path and resolved_path ~= origin_path then
        vary_r, vary_g, vary_b = seq_note_vary_rgb(note, resolved_path)
      end
      if prob_region then
      local pattern = get_seq_pattern(prob_region.pattern_id, false)
      local track_settings = get_seq_track_settings(pattern, slot.id, false)
      local skipped = not seq_note_passes_probability(
        prob_region,
        slot.id,
        entry.key,
        track_settings and track_settings.probability,
        track_settings and (track_settings.probability_seed or track_settings.seed)
      )
      local note_len = seq_note_draw_length_qn(
        prob_region, pattern, slot, slot.id, entry.key, note, resolved_sample, step_qn
      )
      local draw_x0 = qn_to_x(note_qn + note_off) + 2
      local draw_x1 = math.max(draw_x0 + 6.0, qn_to_x(note_qn + note_off + note_len) - 2)
      local row_pad = 4.0
      local block_y0 = row_y0 + row_pad
      local block_y1 = row_y1 - row_pad
      local note_alpha = cell_selected and 235 or 70
      local border_alpha = cell_selected and 205 or 52
      if note_fx and (note_fx.kind == "add" or note_fx.kind == "delete") then
        local scale_x, scale_y = seq_note_anim_pop_scale(note_fx.kind, fx_t)
        draw_x0, block_y0, draw_x1, block_y1 = scale_rect_about_center(draw_x0, block_y0, draw_x1, block_y1, scale_x, scale_y, 0.0)
        note_alpha, border_alpha = seq_note_anim_pop_alphas(note_fx.kind, fx_t, cell_selected)
      elseif note_fx and note_fx.kind == "sync" then
        local boost = math.floor(55 * (1.0 - fx_t))
        note_alpha = math.min(255, note_alpha + boost)
        border_alpha = math.min(255, border_alpha + boost)
      end
      if skipped then
        note_alpha = math.max(28, math.floor(note_alpha * 0.32))
        border_alpha = math.max(40, math.floor(border_alpha * 0.42))
      end
      local block_h = block_y1 - block_y0
      local br, bg, bb = extract_rgb_rrgbbaa(base)
      local stutter_count = seq_stutter_count(note)
      local is_stutter = seq_note_has_stutter_span(note, step_qn)
      local decay_mode = seq_is_decay_def(edit_def)
      local head_x1 = seq_note_head_end_x(qn_to_x, note_qn, note, step_qn)
      local sustain_split_x = nil
      if not is_stutter and not decay_mode and head_x1 and draw_x1 > head_x1 + 1.0 then
        sustain_split_x = math.max(draw_x0 + 6.0, head_x1)
      end
      local trigger_x1 = sustain_split_x or draw_x1
      if is_stutter then
        draw_seq_stutter_note_hits(
          dl, qn_to_x, note, note_qn, step_qn,
          draw_x0, draw_x1, block_y0, block_y1,
          br, bg, bb, note_alpha, border_alpha, vary_r, vary_g, vary_b
        )
      else
        draw_seq_note_body(dl, draw_x0, draw_x1, block_y0, block_y1, br, bg, bb, note_alpha, border_alpha, sustain_split_x, vary_r, vary_g, vary_b)
      end

      local gauges_fit = (trigger_x1 - draw_x0) >= 14.0
      if skipped then
        draw_seq_note_probability_skip(
          dl,
          math.max(draw_x0, cx0 + 1),
          block_y0,
          math.min(trigger_x1, cx1 - 1),
          block_y1,
          cell_selected and 210 or 95
        )
      elseif seq_is_span_overlay_def(edit_def) then
        -- Lock / vary-filter spans are drawn once per contiguous range on the lane.
      elseif seq_is_decay_def(edit_def) then
        local overlay_accent = (edit_style and edit_style.accent) or 0xFFD166FF
        draw_seq_decay_handles(
          dl, note, slot, prob_region, pattern, entry.key, note_qn, step_qn, qn_to_x,
          draw_x0, draw_x1, block_y0, block_y1, mx, my, overlay_accent, cell_selected
        )
      elseif edit_def then
        local overlay_accent = (edit_style and edit_style.accent) or 0xFFD166FF
        if not seq_draw_stutter_param_slices(
          dl, note, note_qn, edit_def, step_qn, qn_to_x, block_y0, block_y1, overlay_accent, cell_selected, hover_qn
        ) then
          draw_seq_note_param_mode_overlay(
            dl, ctx, edit_def, note[edit_def.key], draw_x0, trigger_x1, row_y0, row_y1, step_qn,
            overlay_accent, cell_selected
          )
        end
      elseif not is_stutter then
        local vol = math.max(0.0, math.min(2.0, note.volume or 1.0))
        local vol_t = vol / 2.0
        local gx0 = draw_x0 + 2
        local gx1 = gx0 + 3
        r.ImGui_DrawList_AddRectFilled(dl, gx0, block_y0 + 2, gx1, block_y1 - 2, 0x00000055, 1.0)
        local vol_top = block_y1 - 2 - vol_t * math.max(1.0, (block_h - 4))
        r.ImGui_DrawList_AddRectFilled(dl, gx0, vol_top, gx1, block_y1 - 2, 0xFFFFFFFF, 1.0)
        if gauges_fit then
          local pitch = math.max(-24.0, math.min(24.0, note.pitch or 0.0))
          local pitch_t = (pitch + 24.0) / 48.0
          local px1 = trigger_x1 - 2
          local px0 = px1 - 3
          local mid_y = (block_y0 + block_y1) * 0.5
          r.ImGui_DrawList_AddRectFilled(dl, px0, block_y0 + 2, px1, block_y1 - 2, 0x00000055, 1.0)
          r.ImGui_DrawList_AddLine(dl, px0, mid_y, px1, mid_y, 0xFFFFFF66, 1.0)
          local pitch_y = (block_y1 - 2) - pitch_t * math.max(1.0, (block_h - 4))
          local pitch_color = pitch >= 0.0 and 0xFFB84DFF or 0x58B7FFFF
          if pitch >= 0 then
            r.ImGui_DrawList_AddRectFilled(dl, px0, pitch_y, px1, mid_y, pitch_color, 1.0)
          else
            r.ImGui_DrawList_AddRectFilled(dl, px0, mid_y, px1, pitch_y, pitch_color, 1.0)
          end
        end
        local pan = math.max(-1.0, math.min(1.0, note.pan or 0.0))
        local pan_track_x0 = draw_x0 + 6
        local pan_track_x1 = trigger_x1 - (gauges_fit and 6 or 2)
        if pan_track_x1 > pan_track_x0 + 2 then
          local pan_y = block_y0 + 3
          r.ImGui_DrawList_AddLine(dl, pan_track_x0, pan_y, pan_track_x1, pan_y, 0x00000077, 1.0)
          local pan_cx = (pan_track_x0 + pan_track_x1) * 0.5
          r.ImGui_DrawList_AddLine(dl, pan_cx, pan_y - 2, pan_cx, pan_y + 2, 0xFFFFFF66, 1.0)
          local pan_x = pan_track_x0 + ((pan + 1.0) * 0.5) * (pan_track_x1 - pan_track_x0)
          r.ImGui_DrawList_AddRectFilled(dl, pan_x - 1.5, pan_y - 2.5, pan_x + 1.5, pan_y + 2.5, 0xFFFFFFFF, 1.0)
        end
      end
      if vary_r and not is_stutter then
        draw_seq_note_vary_marks(dl, draw_x0, trigger_x1, block_y0, block_y1, vary_r, vary_g, vary_b, note_alpha)
      end
      if is_stutter then
        local bx0, by0, bx1, by1 = draw_seq_stutter_count_badge(
          dl, ctx, draw_x0, block_y0, draw_x1, block_y1, stutter_count, 0xC9A8FFFF
        )
        if not edit_def then
          seq_register_stutter_badge_hit(bx0, by0, bx1, by1, slot.id, entry.region_id, entry.key)
        end
      end
      if note_fx and note_fx.kind == "sync" then
        draw_seq_note_sync_flash(dl, draw_x0, block_y0, draw_x1, block_y1, fx_t)
      end
      if hover_pick and hover_pick.key == entry.key and hover_pick.region_id == entry.region_id
         and not seq_note_is_locked(note) then
        -- Decay can hover the full body. Otherwise only the originating cell
        -- counts as the note; spilled min-grid / sustain tails look empty.
        -- Locked notes use the lock-span hover instead of this cell outline.
        local hover_x1 = seq_is_decay_def(edit_def) and draw_x1 or math.min(trigger_x1, cx1)
        draw_seq_note_hover(dl, mx, my, draw_x0, block_y0, draw_x1, block_y1, hover_x1)
      end
      end
      end
      end
    end
  end
end

function make_default_seq_note(slot, step_key, qn_offset)
  local sample = slot and slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if not sample then
    return nil
  end
  return {
    enabled = true,
    step = tonumber(step_key) or 0,
    qn_offset = qn_offset or 0.0,
    sample_path = sample.path,
    sample_name = sample.name or basename(sample.path),
    volume = 1.0,
    pan = 0.0,
    pitch = 0.0,
    length_qn = state.seq_grid_qn or 0.25,
    offset_qn = 0.0,
    stretch = 1.0,
    start = 0.0,
    sample_vary = 0.0,
    stutter = 1,
  }
end

function seq_apply_frozen_sample(target, path, sample, origin_path)
  if type(target) ~= "table" or not path or path == "" then
    return
  end
  target.frozen_sample_path = path
  target.frozen_sample_name = (sample and (sample.name or sample.path)) or basename(path)
  seq_stamp_vary_visual(target, path, origin_path)
end

-- Clone a note and freeze the sample it is currently sounding, including
-- region-random variation. The copy then keeps that file even at a new step.
function seq_clone_note_keeping_sample(note, region, track_id, step_key, slot)
  local copy = clone_table_deep(note)
  if type(copy) ~= "table" then
    return copy
  end
  local function freeze_into(target, hit_idx)
    local vary = seq_random_vary_amount(note, region, track_id, step_key, hit_idx)
    local hit_note = seq_note_for_stutter_hit(note, hit_idx)
    local path, sample = seq_resolve_note_sample(hit_note, slot, vary, region, track_id, step_key)
    if path then
      seq_apply_frozen_sample(target, path, sample, seq_note_vary_origin_path(note, slot, region))
    end
    if vary and vary > 0.000001 and (tonumber(target.sample_vary) or 0) <= 0.000001 then
      target.sample_vary = vary
    end
  end
  freeze_into(copy, 1)
  local count = seq_stutter_count(copy)
  if count > 1 then
    copy.stutter_hits = copy.stutter_hits or {}
    for i = 1, count do
      local hit = seq_stutter_hit_table(copy, i)
      if type(hit) ~= "table" then
        hit = {}
        copy.stutter_hits[i] = hit
      end
      freeze_into(hit, i)
    end
  end
  return copy
end

function seq_template_step_to_grid_step(template_step, steps_per_bar)
  local raw = (template_step or 0) * steps_per_bar / 16.0
  local rounded = math.floor(raw + 0.5)
  if math.abs(raw - rounded) > 0.000001 then
    return nil
  end
  return rounded
end

function seq_pattern_rand(seed)
  return math.abs(math.sin(seed or 0) * 10000.0) % 1.0
end

function seq_pattern_clamp(v, min_v, max_v)
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

function seq_role_anchor_hit(role, template_step)
  local fam = seq_role_family(role)
  if fam == "kick" then
    return template_step == 0 or template_step == 8
  end
  if fam == "backbeat" then
    return template_step == 4 or template_step == 12
  end
  return false
end

-- Each dice roll produces an independent random intensity (0..strength*10) for
-- every randomization type. So dice 1 yields 0..10, dice 2 yields 0..20, etc.
-- The rolled values are derived from the seed so a stored variation reproduces
-- exactly. Returns displacement %, density %, and stutter %.
function seq_dice_intensities(strength, seed)
  local s = math.max(0, math.min(6, strength or 0))
  if s <= 0 then
    return 0.0, 0.0, 0.0
  end
  local maxv = s * 10.0
  local disp = seq_pattern_rand((seed or 0) + 1234.5) * maxv
  local dens = seq_pattern_rand((seed or 0) + 6789.0) * maxv
  local stut = seq_pattern_rand((seed or 0) + 2468.0) * maxv
  return disp, dens, stut
end

-- Decides how far (in grid steps) a template hit is nudged from its position.
-- disp_pct is the rolled displacement intensity (0..60). Returns a signed step
-- delta, or 0 to stay put.
function seq_random_step_displacement(disp_pct, is_anchor, fam, rnd_gate, rnd_dir)
  if not disp_pct or disp_pct <= 0 then
    return 0
  end
  local p = disp_pct / 100.0
  if is_anchor then
    p = p * 0.55
  end
  if fam == "kick" then
    p = p * 0.8
  end
  if rnd_gate >= p then
    return 0
  end
  local span = rnd_gate / math.max(p, 1e-6)
  local mag = 1
  if disp_pct >= 25 and span > 0.5 then
    mag = 2
  end
  if disp_pct >= 45 and span > 0.8 then
    mag = 3
  end
  local dir = (rnd_dir < 0.5) and -1 or 1
  return dir * mag
end

-- Stutter/roll, intentionally rare even at high dice.
function apply_seq_random_note_shape(note, stut_pct, rnd_b)
  if not note or not stut_pct or stut_pct <= 0 then
    return
  end
  local stut_prob = (stut_pct / 100.0) * 0.10
  if rnd_b < stut_prob then
    note.stutter = math.min(6, 2 + math.floor(seq_pattern_rand(rnd_b * 10000.0 + stut_pct * 13.0) * 3))
  end
end

function seq_has_generatable_track(style_key)
  local template = SEQ_GEN_TEMPLATES[normalize_seq_gen_style(style_key)]
  if not template then
    return false
  end
  for _, slot in ipairs(state.seq_tracks) do
    if slot.sample_path then
      local role = infer_seq_track_role(slot)
      if template[role] then
        return true
      end
    end
  end
  return false
end

function seq_collect_locked_notes(pattern, grid_qn)
  local locked = {}
  if not pattern or type(pattern.notes) ~= "table" then
    return locked
  end
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  for track_id, notes in pairs(pattern.notes) do
    if type(notes) == "table" then
      for step_key, note in pairs(notes) do
        if seq_note_is_locked(note) then
          local qn = seq_note_qn_offset(note, step_key, grid_qn) or 0.0
          locked[#locked + 1] = {
            track_id = track_id,
            step_key = tostring(step_key),
            note = clone_table_deep(note),
            step_idx = math.floor((qn / math.max(1e-9, grid_qn)) + 1e-9),
          }
        end
      end
    end
  end
  return locked
end

function seq_restore_locked_notes(region, locked)
  local n = 0
  for i = 1, #(locked or {}) do
    local item = locked[i]
    set_seq_note(region, item.track_id, item.step_key, item.note)
    n = n + 1
  end
  return n
end

function seq_locked_step_seen(locked, track_id)
  local seen = {}
  for i = 1, #(locked or {}) do
    local item = locked[i]
    if tostring(item.track_id) == tostring(track_id) and item.step_idx then
      seen[item.step_idx] = true
    end
  end
  return seen
end

-- Clear only the tracks a generator writes to (role present in role_lookup);
-- other tracks (bass, loops, roles the generator doesn't cover) keep their notes.
function seq_clear_generated_role_tracks(pattern, role_lookup)
  if not pattern or type(pattern.notes) ~= "table" or type(role_lookup) ~= "table" then
    return
  end
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.sample_path and slot.id ~= nil then
      local role = infer_seq_track_role(slot)
      if type(role_lookup[role]) == "table" then
        pattern.notes[tostring(slot.id)] = nil
      end
    end
  end
end

function generate_seq_pattern(region, style_key, opts)
  if not region then
    return 0
  end
  opts = opts or {}

  style_key = normalize_seq_gen_style(style_key)
  local template = SEQ_GEN_TEMPLATES[style_key] or SEQ_GEN_TEMPLATES.basic
  local pattern = get_seq_pattern(region.pattern_id, true)
  if not pattern then
    return 0
  end

  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local region_len_qn = get_seq_region_length_qn(region)
  -- Bars follow the time signature; template 16ths past a short bar's end
  -- (e.g. 13-16 in 3/4) are dropped so every bar starts on its bar line.
  local steps_per_bar, bar_count, steps_per_4qn = seq_region_bar_grid(region, grid_qn)
  local max_steps = math.max(1, math.floor((region_len_qn / grid_qn) + 0.5))
  local strength = type(opts.random_strength) == "number" and math.max(0, math.min(6, math.floor(opts.random_strength + 0.5))) or 0
  local random_seed = opts.random_seed or seq_new_seed()

  -- One random intensity per randomization type for this dice roll.
  local disp_pct, dens_pct, stut_pct = seq_dice_intensities(strength, random_seed)
  -- Density randomization: drop some existing hits and/or add new ones.
  local drop_prob = (dens_pct / 100.0) * 0.5
  local add_prob = (dens_pct / 100.0) * 0.4

  local locked_notes = seq_collect_locked_notes(pattern, grid_qn)
  seq_clear_generated_role_tracks(pattern, template)
  state.selected_seq_note = nil
  local hit_count = seq_restore_locked_notes(region, locked_notes)

  local skipped_unassigned = false
  local cycle_bars = seq_template_cycle_bars(template)
  for _, slot in ipairs(state.seq_tracks) do
    if slot.sample_path then
      local role = infer_seq_track_role(slot)
      local role_steps = template[role]
      if role_steps then
        local seen = seq_merge_locked_cell_seen(seq_locked_step_seen(locked_notes, slot.id), pattern, slot.id)
        local fam = seq_role_family(role)
        local template_step_lookup = {}
        for _, template_step in ipairs(role_steps) do
          template_step_lookup[template_step] = true
        end

        local function add_pattern_note(step_idx)
          if step_idx >= 0 and step_idx < max_steps and not seen[step_idx] then
            local note = make_default_seq_note(slot, step_idx, step_idx * grid_qn)
            if note then
              local pos16 = steps_per_bar > 0
                and math.floor(((step_idx % steps_per_bar) * 16.0 / steps_per_4qn) + 0.5)
                or step_idx
              note.offset_qn = seq_pattern_base_offset(role, pos16, style_key, grid_qn)
              local rnd_stut = seq_pattern_rand(random_seed + step_idx * 733 + (slot.id or 0) * 41)
              apply_seq_random_note_shape(note, stut_pct, rnd_stut)
              if (step_idx % steps_per_bar) == 0 and note.offset_qn < 0.0 then
                note.offset_qn = 0.0
              end
              set_seq_note(region, slot.id, step_idx, note)
              seen[step_idx] = true
              hit_count = hit_count + 1
              return true
            end
          end
          return false
        end

        for bar = 0, bar_count - 1 do
          local bar_lo = bar * steps_per_bar
          local bar_hi = bar_lo + steps_per_bar - 1
          -- Two-bar presets alternate: this bar takes steps from its half.
          local cycle_lo = (bar % cycle_bars) * 16

          -- Place template hits, applying density-drop and displacement.
          for _, raw_step in ipairs(role_steps) do
            local template_step = raw_step - cycle_lo
            local grid_step = (template_step >= 0 and template_step < 16)
              and seq_template_step_to_grid_step(template_step, steps_per_4qn) or nil
            if grid_step and grid_step < steps_per_bar then
              local base_idx = bar_lo + grid_step
              local is_anchor = seq_role_anchor_hit(role, template_step)

              local dropped = false
              if drop_prob > 0 and not is_anchor then
                local rnd_drop = seq_pattern_rand(random_seed + base_idx * 211 + (slot.id or 0) * 13)
                if rnd_drop < drop_prob then
                  dropped = true
                end
              end

              if not dropped then
                local target_idx = base_idx
                if disp_pct > 0 then
                  local rnd_gate = seq_pattern_rand(random_seed + base_idx * 331 + (slot.id or 0) * 7)
                  local rnd_dir = seq_pattern_rand(random_seed + base_idx * 521 + (slot.id or 0) * 29)
                  local delta = seq_random_step_displacement(disp_pct, is_anchor, fam, rnd_gate, rnd_dir)
                  if delta ~= 0 then
                    local dir = (delta > 0) and 1 or -1
                    local mag = math.abs(delta)
                    local candidates = {}
                    candidates[#candidates + 1] = dir * mag
                    candidates[#candidates + 1] = -dir * mag
                    for m = mag - 1, 1, -1 do
                      candidates[#candidates + 1] = dir * m
                      candidates[#candidates + 1] = -dir * m
                    end
                    for _, d in ipairs(candidates) do
                      local cand = base_idx + d
                      if cand >= bar_lo and cand <= bar_hi and cand >= 0 and cand < max_steps and not seen[cand] then
                        target_idx = cand
                        break
                      end
                    end
                  end
                end
                if not add_pattern_note(target_idx) and target_idx ~= base_idx then
                  add_pattern_note(base_idx)
                end
              end
            end
          end

          -- Density-add: sprinkle new hits onto empty 16th steps in this bar.
          if add_prob > 0 then
            for template_step = 0, 15 do
              if not template_step_lookup[cycle_lo + template_step] then
                local grid_step = seq_template_step_to_grid_step(template_step, steps_per_4qn)
                if grid_step and grid_step < steps_per_bar then
                  local idx = bar_lo + grid_step
                  if not seen[idx] then
                    local rnd_add = seq_pattern_rand(random_seed + idx * 617 + (slot.id or 0) * 23 + template_step * 5)
                    if rnd_add < add_prob then
                      add_pattern_note(idx)
                    end
                  end
                end
              end
            end
          end
        end
      end
    else
      skipped_unassigned = true
    end
  end

  save_config()
  sync_seq_pattern_regions(region.pattern_id)
  if skipped_unassigned then
    sm_notify("Skipped tracks without a sample", "info")
  end
  if strength > 0 then
    log(string.format("Randomized %s pattern at dice %d (disp %.0f / dens %.0f / stut %.0f, %d hits)",
      get_seq_gen_style_label(style_key), strength, disp_pct, dens_pct, stut_pct, hit_count))
  else
    log("Generated " .. get_seq_gen_style_label(style_key) .. " pattern (" .. tostring(hit_count) .. " hits)")
  end
  return hit_count
end

function seq_template_roles(style_key)
  local template = SEQ_GEN_TEMPLATES[normalize_seq_gen_style(style_key)] or {}
  local roles = {}
  for _, role in ipairs(SEQ_ROLE_ORDER) do
    if template[role] then
      roles[#roles + 1] = role
    end
  end
  return roles
end

function find_sample_for_role(role)
  local candidates = SEQ_ROLE_TAG_CANDIDATES[role] or { role }
  for _, tag in ipairs(candidates) do
    local sample = find_sample_for_tag(tag)
    if sample then
      return sample, tag
    end
  end
  return nil
end

-- A preset can generate if any of its roles is already on an assigned track,
-- or a matching sample exists in the library to auto-create the track from.
function seq_preset_can_generate(style_key)
  local roles = seq_template_roles(style_key)
  if #roles == 0 then
    return false
  end
  local assigned_roles = {}
  local fp_parts = { tostring(state.tag_index_epoch or 0), tostring(#(state.samples or {})) }
  for _, slot in ipairs(state.seq_tracks) do
    if slot.sample_path then
      local role = infer_seq_track_role(slot)
      assigned_roles[role] = true
      fp_parts[#fp_parts + 1] = role
    end
  end
  local fp = table.concat(fp_parts, "|")
  local cache = state.seq_preset_can_generate_cache
  local key = tostring(style_key or "")
  if cache and cache.fp == fp and cache[key] ~= nil then
    return cache[key]
  end
  if not cache or cache.fp ~= fp then
    cache = { fp = fp }
    state.seq_preset_can_generate_cache = cache
  end
  local ok = false
  for _, role in ipairs(roles) do
    if assigned_roles[role] or find_sample_for_role(role) then
      ok = true
      break
    end
  end
  cache[key] = ok
  return ok
end

-- Ensure a sequencer track exists for each role the preset needs. Missing roles
-- get a new track (named for the role, stamped with the role's primary tag) and,
-- when available, an auto-assigned sample from the library.
function ensure_seq_tracks_for_roles(roles)
  local present = {}
  for _, slot in ipairs(state.seq_tracks) do
    present[infer_seq_track_role(slot)] = true
  end
  local created = 0
  for _, role in ipairs(roles) do
    if not present[role] then
      local label = SEQ_ROLE_LABELS[role] or role
      local slot = create_seq_track_with_name(label)
      if slot then
        local candidates = SEQ_ROLE_TAG_CANDIDATES[role] or { role }
        slot.sample_tag = candidates[1] or role
        local sample = find_sample_for_role(role)
        if sample then
          assign_sample_to_seq_track(slot, sample, false)
        end
        present[role] = true
        created = created + 1
      end
    end
  end
  return created
end

-- Infer library genre tags from free text (pattern style names, GMD labels, etc.).
function seq_library_genres_from_text(text)
  local haystack = tostring(text or ""):lower()
  if haystack == "" then
    return {}
  end
  local found, out = {}, {}
  for _, entry in ipairs(GENRE_KEYWORDS) do
    local tag = entry.tag
    if not found[tag] then
      for _, key in ipairs(entry.keys) do
        if genre_key_matches(haystack, key) then
          found[tag] = true
          out[#out + 1] = tag
          break
        end
      end
    end
  end
  return out
end

function seq_style_to_library_genres(style_key)
  style_key = tostring(style_key or "")
  local mapped = SEQ_STYLE_LIBRARY_GENRES[style_key]
  if mapped and #mapped > 0 then
    local out = {}
    for _, tag in ipairs(mapped) do
      out[#out + 1] = tag
    end
    return out
  end
  return seq_library_genres_from_text(style_key)
end

function stamp_seq_region_kit_genres(region, style_key, style_source, genres)
  if not region then
    return
  end
  region.style_key = style_key and tostring(style_key) or region.style_key
  region.style_source = style_source or region.style_source
  if type(genres) == "table" then
    region.kit_genres = genres
  elseif region.style_key then
    if region.style_source == "gmd" then
      region.kit_genres = seq_library_genres_from_text(region.style_key)
    else
      region.kit_genres = seq_style_to_library_genres(region.style_key)
    end
  end
end

function get_seq_region_kit_genres(region)
  if not region then
    return {}
  end
  if type(region.kit_genres) == "table" and #region.kit_genres > 0 then
    return region.kit_genres
  end
  if region.style_key and region.style_key ~= "" then
    if region.style_source == "gmd" or not seq_gen_style_exists(region.style_key) then
      return seq_library_genres_from_text(region.style_key)
    end
    return seq_style_to_library_genres(region.style_key)
  end
  return {}
end

-- Genres present in the scanned library (for Randomize Kit popup).
function collect_library_genre_tags()
  sm_tag_index_rebuild_if_stale()
  local out = {}
  for _, entry in ipairs(state.tag_list or {}) do
    local tag = tostring(entry.tag or "")
    if tag ~= "" and GENRE_TAG_SET[tag:lower()] then
      out[#out + 1] = { tag = tag, count = entry.count or 0 }
    end
  end
  return out
end

-- Genres corresponding to patterns already used in project regions (priority list).
function collect_project_kit_genre_priority()
  local seen, ordered = {}, {}
  local function push(tag)
    local key = tostring(tag or ""):lower()
    if key == "" or seen[key] or not GENRE_TAG_SET[key] then
      return
    end
    -- Prefer the canonical casing from GENRE_KEYWORDS when available.
    local canonical = key
    for _, entry in ipairs(GENRE_KEYWORDS) do
      if entry.tag:lower() == key then
        canonical = entry.tag
        break
      end
    end
    seen[key] = true
    ordered[#ordered + 1] = canonical
  end

  for _, region in ipairs(state.seq_regions or {}) do
    for _, tag in ipairs(get_seq_region_kit_genres(region)) do
      push(tag)
    end
  end

  -- Soft fallbacks for sessions that haven't stamped region genres yet.
  if #ordered == 0 then
    for _, tag in ipairs(seq_style_to_library_genres(state.seq_gen_style)) do
      push(tag)
    end
    if state.seq_gmd_selected_style then
      for _, tag in ipairs(seq_library_genres_from_text(state.seq_gmd_selected_style)) do
        push(tag)
      end
    end
  end

  return ordered
end

function sample_matches_kit_keyword(sample, keyword)
  local needle = seq_trim_text(keyword):lower()
  if needle == "" or not sample then
    return needle == ""
  end
  if sample_has_tag(sample, needle) then
    return true
  end
  if type(sample.tags) == "table" then
    for _, tag in ipairs(sample.tags) do
      if tostring(tag):lower():find(needle, 1, true) then
        return true
      end
    end
  end
  local hay = (
    tostring(sample.path or "") .. " "
    .. tostring(sample.folder or "") .. " "
    .. tostring(sample.name or "")
  ):lower()
  return hay:find(needle, 1, true) ~= nil
end

function sample_matches_seq_role_tags(sample, role)
  if not sample or not role or role == "other" then
    return false
  end
  local candidates = SEQ_ROLE_TAG_CANDIDATES[role] or { role }
  for _, tag in ipairs(candidates) do
    if sample_has_tag(sample, tag) then
      return true, tag
    end
  end
  return false
end

-- Melodic sequencer roles may use loops; drum / other non-melodic roles may not.
function seq_kit_role_is_melodic(role)
  if not role or role == "" or role == "other" then
    return false
  end
  return categorize_tags(role) == "melodic"
end

function sample_is_loop(sample)
  if not sample then
    return false
  end
  if sample_has_tag(sample, "loop") then
    return true
  end
  return detect_loop_or_oneshot(sample.path or "", sample.folder or "", sample.playback_type) == "loop"
end

-- Collect role-matching samples, optionally constrained by genre/custom keywords (OR).
-- Drum / non-melodic roles use one-shots only; melodic roles may include loops.
-- exact_tag: require an exact genre/tag match (genre chips).
function collect_samples_for_role_with_keywords(role, keywords, opts)
  opts = opts or {}
  local exact_tag = opts.exact_tag == true
  local oneshot_only = not seq_kit_role_is_melodic(role)
  local out = {}
  local has_keywords = type(keywords) == "table" and #keywords > 0

  for _, sample in ipairs(state.samples or {}) do
    if not sample_scan_folder_unavailable(sample)
        and (not oneshot_only or not sample_is_loop(sample))
        and sample_matches_seq_role_tags(sample, role) then
      local keyword_ok = not has_keywords
      if has_keywords then
        for _, kw in ipairs(keywords) do
          if exact_tag then
            if sample_has_tag(sample, kw) then
              keyword_ok = true
              break
            end
          elseif sample_matches_kit_keyword(sample, kw) then
            keyword_ok = true
            break
          end
        end
      end
      if keyword_ok then
        out[#out + 1] = sample
      end
    end
  end

  return out
end

SEQ_KIT_HISTORY_MAX = 24

function seq_kit_history_label(keywords)
  if type(keywords) == "table" and #keywords > 0 then
    return table.concat(keywords, ", ")
  end
  return "Any genre"
end

-- Per-region samples on this track, so a Recent kit can put them back.
function seq_kit_collect_region_samples(slot)
  local out = nil
  for _, region in ipairs(state.seq_regions or {}) do
    local rec = seq_region_own_track_sample and seq_region_own_track_sample(region, slot.id)
    if rec and region.id ~= nil then
      out = out or {}
      out[#out + 1] = { region_id = region.id, path = rec.path, name = rec.name }
    end
  end
  return out
end

function collect_seq_kit_elements()
  local by_role = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    local role = infer_seq_track_role(slot)
    if role ~= "other" and slot.sample_path then
      by_role[role] = {
        role = role,
        track_id = slot.id,
        sample_path = slot.sample_path,
        sample_name = slot.sample_name or basename(slot.sample_path),
        sample_tag = slot.sample_tag,
        region_samples = seq_kit_collect_region_samples(slot),
      }
    end
  end
  local elements = {}
  for _, role in ipairs(SEQ_ROLE_ORDER) do
    if by_role[role] then
      elements[#elements + 1] = by_role[role]
      by_role[role] = nil
    end
  end
  for _, elem in pairs(by_role) do
    elements[#elements + 1] = elem
  end
  return elements
end

function seq_kit_signature(elements)
  local parts = {}
  for _, elem in ipairs(elements or {}) do
    parts[#parts + 1] = tostring(elem.role or "") .. "=" .. tostring(elem.sample_path or "")
  end
  return table.concat(parts, "|")
end

function seq_kit_history_has_signature(sig)
  if not sig or sig == "" then
    return false
  end
  for _, entry in ipairs(state.seq_kit_history or {}) do
    if seq_kit_signature(entry.elements) == sig then
      return true
    end
  end
  return false
end

function snapshot_seq_kit_history(keywords, opts)
  opts = opts or {}
  local elements = opts.elements or collect_seq_kit_elements()
  if #elements == 0 then
    return nil
  end
  local sig = seq_kit_signature(elements)
  if opts.skip_duplicate ~= false and seq_kit_history_has_signature(sig) then
    -- Same main samples: store the current per-region samples on that entry
    -- so going back restores them. Never clear ones it already has.
    for _, entry in ipairs(state.seq_kit_history or {}) do
      if seq_kit_signature(entry.elements) == sig then
        for i, elem in ipairs(elements) do
          local old = entry.elements[i]
          if old and elem.region_samples then
            old.region_samples = elem.region_samples
          end
        end
        break
      end
    end
    return nil
  end

  state.seq_kit_history = state.seq_kit_history or {}
  local id = state.seq_kit_history_next_id or 1
  state.seq_kit_history_next_id = id + 1
  local kw_copy = {}
  if type(keywords) == "table" then
    for _, kw in ipairs(keywords) do
      kw_copy[#kw_copy + 1] = kw
    end
  end
  local entry = {
    id = id,
    label = opts.label or seq_kit_history_label(kw_copy),
    keywords = kw_copy,
    elements = elements,
    is_original = opts.is_original == true,
    created_at = (r.time_precise and r.time_precise()) or os.clock(),
  }
  if opts.append then
    state.seq_kit_history[#state.seq_kit_history + 1] = entry
  else
    table.insert(state.seq_kit_history, 1, entry)
  end
  while #state.seq_kit_history > SEQ_KIT_HISTORY_MAX do
    local removed = false
    for i = #state.seq_kit_history, 1, -1 do
      if not state.seq_kit_history[i].is_original then
        table.remove(state.seq_kit_history, i)
        removed = true
        break
      end
    end
    if not removed then
      break
    end
  end
  return entry
end

-- Keep the pre-randomize / pre-replace kit so it remains restorable.
function preserve_current_seq_kit_in_history()
  local elements = collect_seq_kit_elements()
  if #elements == 0 then
    return nil
  end
  local has_original = false
  for _, entry in ipairs(state.seq_kit_history or {}) do
    if entry.is_original then
      has_original = true
      break
    end
  end
  if not has_original then
    return snapshot_seq_kit_history(nil, {
      elements = elements,
      label = "Original",
      is_original = true,
      append = true,
    })
  end
  return snapshot_seq_kit_history(nil, {
    elements = elements,
    label = "Previous",
  })
end

function find_seq_track_for_kit_element(element)
  if not element then
    return nil
  end
  local by_id = element.track_id and find_seq_track_by_id(element.track_id) or nil
  if by_id and (not element.role or infer_seq_track_role(by_id) == element.role) then
    return by_id
  end
  if element.role then
    for _, slot in ipairs(state.seq_tracks or {}) do
      if infer_seq_track_role(slot) == element.role then
        return slot
      end
    end
  end
  return by_id
end

function preview_seq_kit_history_element(element)
  if not element or not element.sample_path then
    return false
  end
  local sample = find_sample_by_path(element.sample_path)
  if not sample then
    log("Sample not found in library: " .. tostring(element.sample_name or element.sample_path))
    return false
  end
  preview_sample(sample)
  local slot = find_seq_track_for_kit_element(element)
  if slot then
    state.seq_track_play_anims = state.seq_track_play_anims or {}
    state.seq_track_play_anims[tostring(slot.id)] = {
      start_time = r.time_precise(),
      duration = 0.35,
    }
  end
  return true
end

function apply_seq_kit_history_element(element, opts)
  opts = opts or {}
  if not element or not element.sample_path then
    return false
  end
  local sample = find_sample_by_path(element.sample_path)
  if not sample then
    local msg = "Sample not found in library: " .. tostring(element.sample_name or element.sample_path)
    if opts.silent then log(msg) else sm_notify(msg, "warn") end
    return false
  end
  local slot = find_seq_track_for_kit_element(element)
  if not slot then
    local msg = "No sequencer track for " .. tostring(SEQ_ROLE_LABELS[element.role] or element.role or "sample")
    if opts.silent then log(msg) else sm_notify(msg, "warn") end
    return false
  end
  local own_undo = opts.undo ~= false
  local label = own_undo and begin_seq_undo("Apply kit sample") or nil
  -- A kit change is not a pick into the selected candidate square.
  local ok = seq_without_candidate_save(seq_kit_assign_sample, slot, sample)
  if seq_kit_restore_slot_extras(slot, element) then
    ok = true
  end
  if ok then
    if element.sample_tag and seq_trim_text(element.sample_tag) ~= "" then
      slot.sample_tag = element.sample_tag
    elseif element.role and SEQ_ROLE_TAG_CANDIDATES[element.role] then
      slot.sample_tag = SEQ_ROLE_TAG_CANDIDATES[element.role][1]
    end
    if opts.preview ~= false then
      preview_sample(sample)
      state.seq_track_play_anims = state.seq_track_play_anims or {}
      state.seq_track_play_anims[tostring(slot.id)] = {
        start_time = r.time_precise(),
        duration = 0.35,
      }
    end
    if opts.silent ~= true then
      log(string.format(
        "Applied %s: %s",
        tostring(SEQ_ROLE_LABELS[element.role] or element.role or "sample"),
        tostring(sample.name or basename(sample.path))
      ))
    end
  end
  if own_undo then
    save_config()
    end_seq_undo(label)
  end
  return ok
end

function seq_kit_heard_sample_path(slot)
  if not slot then
    return nil
  end
  local region = seq_sample_assign_region and seq_sample_assign_region() or nil
  if not region and get_seq_region_by_id then
    region = get_seq_region_by_id(state.selected_seq_region_id)
  end
  local path = seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, region)) or nil
  if path and path ~= "" then
    return path
  end
  return slot.sample_path
end

function seq_kit_paths_same(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then
    return false
  end
  if seq_paths_same then
    return seq_paths_same(a, b)
  end
  return a == b
end

function seq_kit_clear_slot_region_samples(slot)
  if not slot then
    return false
  end
  local cleared = false
  for _, region in ipairs(state.seq_regions or {}) do
    if seq_region_own_track_sample and seq_region_own_track_sample(region, slot.id) then
      seq_set_region_own_track_sample(region, slot, nil)
      cleared = true
    end
  end
  return cleared
end

-- Shift+V picks and locked notes are explicit choices: a kit change leaves
-- their pinned sample alone.
function seq_kit_note_pinned(note)
  if type(note) ~= "table" then
    return false
  end
  if note.picked_sample or (seq_note_is_locked and seq_note_is_locked(note)) then
    return true
  end
  if type(note.stutter_hits) == "table" then
    for _, hit in pairs(note.stutter_hits) do
      if type(hit) == "table" and hit.picked_sample then
        return true
      end
    end
  end
  return false
end

-- Stem-imported notes carry their hit strength. While they play their slice
-- of the stem the dynamics are in the audio; once the slice is released for
-- another sample, the strength becomes the note volume (unless edited).
function seq_note_release_stem_velocity(note)
  if type(note) ~= "table" or type(note.stem_velocity) ~= "number" then
    return
  end
  local vol = tonumber(note.volume) or 1.0
  if math.abs(vol - 1.0) < 1e-6 then
    note.volume = note.stem_velocity
  end
  note.stem_velocity = nil
end

-- Remember a note's slice / frozen file before a kit change releases it, so
-- applying the Recent kit that used `kit_path` again can bring it back.
function seq_kit_stash_note(note, kit_path)
  if type(note) ~= "table" or type(kit_path) ~= "string" or kit_path == "" then
    return
  end
  local has_slice = type(note.source_offset) == "number"
  local has_frozen = seq_note_has_frozen_sample and seq_note_has_frozen_sample(note)
  if not has_slice and not has_frozen then
    return
  end
  local stash = {
    path = kit_path,
    sample_path = note.sample_path,
    sample_name = note.sample_name,
    source_offset = note.source_offset,
    frozen_sample_path = note.frozen_sample_path,
    frozen_sample_name = note.frozen_sample_name,
    volume = note.volume,
    stem_velocity = note.stem_velocity,
  }
  if type(note.stutter_hits) == "table" then
    for k, hit in pairs(note.stutter_hits) do
      if type(hit) == "table" and (type(hit.source_offset) == "number" or hit.frozen_sample_path) then
        stash.hits = stash.hits or {}
        stash.hits[tostring(k)] = {
          source_offset = hit.source_offset,
          frozen_sample_path = hit.frozen_sample_path,
          frozen_sample_name = hit.frozen_sample_name,
        }
      end
    end
  end
  note.kit_stash = stash
end

function seq_kit_unstash_note(note, kit_path)
  local stash = type(note) == "table" and note.kit_stash
  if type(stash) ~= "table" or not seq_kit_paths_same(stash.path, kit_path) then
    return false
  end
  note.kit_stash = nil
  -- Only when nothing else pinned or sliced the note since.
  if type(note.source_offset) == "number"
      or (seq_note_has_frozen_sample and seq_note_has_frozen_sample(note)) then
    return false
  end
  local file = stash.frozen_sample_path or stash.sample_path
  if file and seq_path_exists and not seq_path_exists(file) then
    return false
  end
  note.source_offset = stash.source_offset
  note.frozen_sample_path = stash.frozen_sample_path
  note.frozen_sample_name = stash.frozen_sample_name
  if type(stash.stem_velocity) == "number" then
    if math.abs((tonumber(note.volume) or 1.0) - stash.stem_velocity) < 1e-6 then
      note.volume = stash.volume or 1.0
    end
    note.stem_velocity = stash.stem_velocity
  end
  if stash.sample_path then
    note.sample_path = stash.sample_path
    note.sample_name = stash.sample_name
  end
  if type(stash.hits) == "table" and type(note.stutter_hits) == "table" then
    for k, hit in pairs(note.stutter_hits) do
      local h = stash.hits[tostring(k)]
      if type(hit) == "table" and type(h) == "table" then
        hit.source_offset = h.source_offset
        hit.frozen_sample_path = h.frozen_sample_path
        hit.frozen_sample_name = h.frozen_sample_name
      end
    end
  end
  return true
end

-- Put back what a Recent kit had on this track besides the main sample:
-- per-region samples and the slices / frozen files of released notes.
-- Returns true when anything was restored (and rebuilt).
function seq_kit_restore_slot_extras(slot, element)
  if not slot or slot.id == nil or type(element) ~= "table" then
    return false
  end
  local regions_touched = {}
  local any = false
  if type(element.region_samples) == "table" and seq_set_region_own_track_sample then
    for _, rec in ipairs(element.region_samples) do
      local region = type(rec) == "table" and get_seq_region_by_id(rec.region_id)
      if region and type(rec.path) == "string" and rec.path ~= ""
          and (not seq_path_exists or seq_path_exists(rec.path))
          and not seq_region_own_track_sample(region, slot.id) then
        seq_set_region_own_track_sample(region, slot, { path = rec.path, name = rec.name })
        regions_touched[region.id] = region
        any = true
      end
    end
  end
  local patterns_touched = {}
  local track_key = tostring(slot.id)
  for pattern_id, pattern in pairs(state.seq_patterns or {}) do
    local track_notes = type(pattern) == "table" and type(pattern.notes) == "table" and pattern.notes[track_key]
    if type(track_notes) == "table" then
      for _, note in pairs(track_notes) do
        if seq_kit_unstash_note(note, element.sample_path) then
          patterns_touched[tostring(pattern_id)] = true
          any = true
        end
      end
    end
  end
  if not any then
    return false
  end
  for _, region in ipairs(state.seq_regions or {}) do
    if patterns_touched[tostring(region.pattern_id)] then
      regions_touched[region.id] = region
    end
  end
  if clear_seq_vary_rank_cache then
    clear_seq_vary_rank_cache()
  end
  if sync_seq_region_track then
    seq_pcm_take_src_begin()
    if r.PreventUIRefresh then r.PreventUIRefresh(1) end
    for _, region in pairs(regions_touched) do
      sync_seq_region_track(region, slot, { skip_arrange = true, force_rebuild = true })
    end
    if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
    seq_pcm_take_src_end()
    r.UpdateArrange()
  end
  return true
end

function seq_kit_unfreeze_slot_notes(slot)
  if not slot or slot.id == nil then
    return false
  end
  local track_key = tostring(slot.id)
  local cleared = false
  for _, pattern in pairs(state.seq_patterns or {}) do
    local track_notes = type(pattern) == "table" and type(pattern.notes) == "table" and pattern.notes[track_key]
    if type(track_notes) == "table" then
      for _, note in pairs(track_notes) do
        if seq_kit_note_pinned(note) then
          note = nil
        else
          seq_kit_stash_note(note, slot.sample_path)
        end
        if type(note) == "table" and type(note.source_offset) == "number" then
          note.source_offset = nil
          seq_note_release_stem_velocity(note)
          if type(note.stutter_hits) == "table" then
            for _, hit in pairs(note.stutter_hits) do
              if type(hit) == "table" then
                hit.source_offset = nil
              end
            end
          end
          cleared = true
        end
        if seq_note_has_frozen_sample and seq_note_has_frozen_sample(note) then
          seq_clear_frozen_sample(note)
          cleared = true
        end
      end
    end
  end
  return cleared
end

function seq_release_sliced_notes_for_sample_change(slot, regions, sample)
  if not slot or slot.id == nil then
    return 0
  end
  local new_path = sample and sample.path
  local new_name = sample and (sample.name or (new_path and basename(new_path)))
  local n_sliced = 0
  local n_locked = 0
  local track_key = tostring(slot.id)

  local function visit(note)
    if type(note) ~= "table" then
      return
    end
    if type(note.source_offset) ~= "number" then
      return
    end
    if seq_note_is_locked and seq_note_is_locked(note) then
      n_locked = n_locked + 1
      return
    end
    note.source_offset = nil
    seq_note_release_stem_velocity(note)
    if type(note.stutter_hits) == "table" then
      for _, hit in pairs(note.stutter_hits) do
        if type(hit) == "table" then
          hit.source_offset = nil
        end
      end
    end
    if not note.picked_sample then
      seq_clear_frozen_sample(note)
    end
    if new_path and new_path ~= "" then
      note.sample_path = new_path
      note.sample_name = new_name
    end
    n_sliced = n_sliced + 1
  end

  if type(regions) == "table" and #regions > 0 then
    for i = 1, #regions do
      local region = regions[i]
      local pattern = get_seq_pattern(region and region.pattern_id, false)
      local track_notes = get_track_note_table(pattern, slot.id, false)
      if type(track_notes) == "table" then
        for step_key, note in pairs(track_notes) do
          if seq_note_in_region(region, note, step_key) then
            visit(note)
          end
        end
      end
    end
  else
    for _, pattern in pairs(state.seq_patterns or {}) do
      local track_notes = type(pattern) == "table" and type(pattern.notes) == "table"
        and pattern.notes[track_key]
      if type(track_notes) == "table" then
        for _, note in pairs(track_notes) do
          visit(note)
        end
      end
    end
  end

  return n_sliced
end

function seq_kit_assign_sample(slot, sample)
  if not slot or not sample or not sample.path then
    return false
  end
  local heard = seq_kit_heard_sample_path(slot)
  local had_override = seq_kit_clear_slot_region_samples(slot)
  local had_frozen = seq_kit_unfreeze_slot_notes(slot)
  local old_path = slot.sample_path
  local ok = assign_sample_to_seq_track(slot, sample, false)
  if not ok then
    return false
  end
  -- Slot path can stay the same while a region override or frozen hit was
  -- what you were actually hearing. Force a rebuild so the new kit plays.
  if (had_override or had_frozen or seq_kit_paths_same(old_path, sample.path))
      and update_seq_track_sample_assignments then
    update_seq_track_sample_assignments(slot, sample.path, slot.sample_name, false, {
      force_rebuild = true,
    })
  end
  if seq_kit_paths_same(heard, sample.path) and not had_override and not had_frozen then
    return false
  end
  return true
end

function apply_seq_kit_history_entry(entry)
  if not entry or type(entry.elements) ~= "table" or #entry.elements == 0 then
    return 0
  end
  preserve_current_seq_kit_in_history()
  local label = begin_seq_undo("Apply kit")
  local changed = 0
  local last_sample = nil
  for _, element in ipairs(entry.elements) do
    if apply_seq_kit_history_element(element, { undo = false, preview = false, silent = true }) then
      changed = changed + 1
      last_sample = find_sample_by_path(element.sample_path) or last_sample
    end
  end
  if last_sample then
    preview_sample(last_sample)
  end
  save_config()
  end_seq_undo(label)
  if changed > 0 then
    log(string.format("Applied kit \"%s\" (%d sound%s)", entry.label or "Kit", changed, changed == 1 and "" or "s"))
  else
    sm_notify("Kit \"" .. tostring(entry.label or "Kit") .. "\" changed nothing (already in use or samples missing)", "warn")
  end
  return changed
end

function randomize_seq_kit(keywords, opts)
  opts = opts or {}
  if not state.seq_tracks or #state.seq_tracks == 0 then
    sm_notify("No sequencer tracks to randomize", "warn")
    return 0
  end

  preserve_current_seq_kit_in_history()

  local label = begin_seq_undo("Randomize kit")
  local seed = seq_new_seed()
  math.randomseed(seed)

  local changed = 0
  local stuck = 0
  for _, slot in ipairs(state.seq_tracks) do
    local role = infer_seq_track_role(slot)
    if role == "other" then
      local tag = seq_trim_text(slot.sample_tag):lower()
      local cat = tag ~= "" and categorize_tags(tag) or nil
      if cat == "drum" or cat == "melodic" then
        role = tag
      end
    end
    if role ~= "other" then
      local pool = collect_samples_for_role_with_keywords(role, keywords, opts)
      local heard = seq_kit_heard_sample_path(slot)
      local alt = {}
      for _, sample in ipairs(pool) do
        if sample.path and not seq_kit_paths_same(sample.path, heard) then
          alt[#alt + 1] = sample
        end
      end
      if #alt > 0 then
        local pick = alt[math.random(1, #alt)]
        if pick and seq_without_candidate_save(seq_kit_assign_sample, slot, pick) then
          local candidates = SEQ_ROLE_TAG_CANDIDATES[role]
          if candidates and candidates[1] then
            slot.sample_tag = candidates[1]
          end
          changed = changed + 1
        end
      elseif #pool > 0 then
        stuck = stuck + 1
      end
    end
  end

  if changed > 0 then
    snapshot_seq_kit_history(keywords)
  end
  save_config()
  end_seq_undo(label)

  local constraint = ""
  if keywords and #keywords > 0 then
    constraint = " (" .. table.concat(keywords, ", ") .. ")"
  end
  if changed > 0 then
    local msg = string.format("Randomized kit: %d track(s)%s", changed, constraint)
    if stuck > 0 then
      msg = msg .. string.format(" (%d kept — no other matches)", stuck)
    end
    log(msg)
  else
    if stuck > 0 then
      sm_notify("No other matching samples to randomize kit" .. constraint, "warn")
    else
      sm_notify("No matching samples found to randomize kit" .. constraint, "warn")
    end
  end
  return changed
end

function open_seq_kit_random_popup()
  state.seq_kit_random_query = state.seq_kit_random_query or ""
  sm_tag_index_rebuild_if_stale()
  r.ImGui_OpenPopup(ctx, "seq_kit_random_popup")
end

SEQ_PATTERN_POPUP_W = 380.0

function seq_truncate_text_to_width(text, max_w)
  if not text or text == "" then return "" end
  if max_w <= 0 then return "" end
  local tw = select(1, r.ImGui_CalcTextSize(ctx, text))
  if tw <= max_w then return text end
  local ell = "..."
  local lo, hi = 0, #text
  local best = ell
  while lo <= hi do
    local mid = math.floor((lo + hi) * 0.5)
    local candidate = text:sub(1, mid) .. ell
    tw = select(1, r.ImGui_CalcTextSize(ctx, candidate))
    if tw <= max_w then
      best = candidate
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return best
end

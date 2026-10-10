-- Sample Map Browser module: sequencer_view
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function render_sequencer_map()
  seq_sec_per_qn = nil
  seq_decay_clear_hits()
  local region = get_selected_seq_region()
  local avail_x, avail_y = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(720.0, avail_x)
  seq_update_track_lane_h_drag()
  seq_sync_track_order_from_arrange()
  local lane_zoom = seq_lane_zoom_clamped()
  state.seq_lane_zoom = lane_zoom
  local note_lane_h = seq_default_note_lane_h()
  local param_lane_h = seq_default_param_lane_h()
  local region_lane_h = 22.0
  local ruler_lane_h = 30.0
  local header_h = region_lane_h + ruler_lane_h
  local visual_rows = {}
  for _, slot in ipairs(state.seq_tracks) do
    seq_normalize_slot_mix(slot)
    visual_rows[#visual_rows + 1] = { type = "note", slot = slot, h = seq_note_lane_h_for_slot(slot) }
    if state.seq_expanded_tracks[tostring(slot.id)] then
      for _, def in ipairs(SEQ_PARAM_LANES) do
        if def.key ~= "length_qn" and def.key ~= "decay" and def.key ~= "locked" and def.key ~= "vary_filter" then
          visual_rows[#visual_rows + 1] = { type = "param", slot = slot, param = def, h = param_lane_h }
        end
      end
    end
  end
  if #visual_rows == 0 then
    visual_rows[#visual_rows + 1] = { type = "empty", h = note_lane_h }
  end
  local rows_h = 0.0
  for _, row in ipairs(visual_rows) do
    rows_h = rows_h + row.h
  end
  local add_track_row_h = 28.0
  local map_body_h = rows_h + add_track_row_h

  local child_flags = 0
  child_flags = sm_child_border_flag()
  local no_scroll_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if not r.ImGui_BeginChild(ctx, "sequencer_map_area", 0, math.max(0, avail_y), child_flags, no_scroll_flags) then
    state.seq_link_hover_region_id = nil
    return
  end

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  -- Timeline zoom uses Shift+horizontal wheel; keep this child from also
  -- panning horizontally so track controls / header stay fixed in screen space.
  if r.ImGui_SetScrollX then
    r.ImGui_SetScrollX(ctx, 0)
    x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  end
  local header_y1 = y0 + header_h
  -- Pin region lane + ruler at the top (outside the scrollable track list).
  -- Move the cursor without a Dummy so the header stays click-through for
  -- extras flyouts that draw into the ruler.
  r.ImGui_SetCursorScreenPos(ctx, x0, header_y1)

  local _, tracks_avail_y = r.ImGui_GetContentRegionAvail(ctx)
  local body_viewport_y1 = header_y1 + math.max(0, tracks_avail_y)

  -- Popup clicks must not fall through into sequencer geometry hit-testing.
  local popup_blocks_input = imgui_any_popup_open()
  local left_clicked = (not popup_blocks_input) and r.ImGui_IsMouseClicked(ctx, 0)
  local right_clicked = (not popup_blocks_input) and r.ImGui_IsMouseClicked(ctx, 1)
  local left_down = (not popup_blocks_input) and r.ImGui_IsMouseDown(ctx, 0)
  local right_down = (not popup_blocks_input) and r.ImGui_IsMouseDown(ctx, 1)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local header_hovered = (not popup_blocks_input) and mx >= x0 and mx <= x0 + width and my >= y0 and my <= header_y1
  local body_hovered = (not popup_blocks_input) and mx >= x0 and mx <= x0 + width and my >= header_y1 and my <= body_viewport_y1
  local over_random_flyout = seq_random_flyout_hit(mx, my) or (state.seq_random_knob_drag ~= nil)
  if over_random_flyout then
    header_hovered = false
    body_hovered = false
    right_clicked = false
  end
  local hovered = header_hovered or body_hovered
  local body_y0, body_y1

  local view_start, view_end = get_arrange_view_range()
  local arrange_start_qn = time_to_qn(view_start) or 0.0
  local arrange_end_qn = time_to_qn(view_end) or (arrange_start_qn + (state.seq_grid_qn or 0.25) * 16.0)
  local arrange_span_qn = math.max(state.seq_grid_qn or 0.25, arrange_end_qn - arrange_start_qn)
  if (state.seq_follow_arrange or not state.seq_view_start_qn) and not seq_view_is_driving_arrange() then
    state.seq_view_start_qn = arrange_start_qn
    state.seq_view_span_qn = arrange_span_qn
    seq_timeline_scroll_stop()
  elseif not state.seq_view_span_qn or state.seq_view_span_qn <= 0 then
    state.seq_view_span_qn = get_seq_region_length_qn(region)
  end

  local start_qn, end_qn, step_qn, step_count = get_visible_qn_grid_range(
    state.seq_view_start_qn,
    state.seq_view_start_qn + (state.seq_view_span_qn or get_seq_region_length_qn(region))
  )
  -- Continuous view window (smooth scroll). Grid-aligned start_qn/end_qn are only
  -- used for cell indexing; rendering and hit-testing use the raw view coords.
  local view_start_qn = state.seq_view_start_qn or start_qn
  local view_span_qn = state.seq_view_span_qn or math.max(step_qn, end_qn - start_qn)
  local qn_span = view_span_qn
  local scroll_now = r.time_precise()
  local scroll_dt = math.min(0.05, math.max(0.001, scroll_now - (state.seq_scroll_last_t or scroll_now)))
  state.seq_scroll_last_t = scroll_now
  local label_w = math.min(340.0, math.max(268.0, width * 0.34))
  local timeline_x0 = x0 + label_w
  local timeline_w = math.max(120.0, width - label_w)
  state.seq_map_rect = {
    x = x0,
    y = y0,
    w = width,
    h = math.max(0.0, (body_viewport_y1 or y0) - y0),
    timeline_x = timeline_x0,
    timeline_w = timeline_w,
    header_y1 = header_y1,
  }

  -- Floating "keep pattern?" confirmation bar geometry. Computed up-front so we
  -- can suppress grid interactions underneath it (otherwise clicking the tick
  -- would also toggle a note in the cell below).
  local show_confirm = state.seq_pattern_confirm and state.seq_pattern_confirm.active
  local cb_x0, cb_y0, cb_x1, cb_y1
  if show_confirm then
    local cb_h = 34.0
    local cb_w = 240.0
    local confirm_region = region
    if state.seq_pattern_confirm.region_id then
      confirm_region = get_seq_region_by_id(state.seq_pattern_confirm.region_id) or region
    end
    if confirm_region then
      local reg_start = confirm_region.start_qn or 0.0
      local reg_end = reg_start + get_seq_region_length_qn(confirm_region)
      local rx0 = math.max(timeline_x0, timeline_x0 + ((reg_start - view_start_qn) / qn_span) * timeline_w)
      local rx1 = math.min(timeline_x0 + timeline_w, timeline_x0 + ((reg_end - view_start_qn) / qn_span) * timeline_w)
      if rx1 > rx0 + 48.0 then
        cb_w = math.min(cb_w, rx1 - rx0 - 8.0)
        cb_x0 = rx0 + math.max(0.0, (rx1 - rx0 - cb_w) * 0.5)
      else
        cb_x0 = timeline_x0 + math.max(0.0, (timeline_w - cb_w) * 0.5)
      end
    else
      cb_x0 = timeline_x0 + math.max(0.0, (timeline_w - cb_w) * 0.5)
    end
    -- Sit just above the region's note grid (below the ruler), centered on the region span.
    cb_y0 = header_y1 - cb_h - 6.0
    cb_x1 = cb_x0 + cb_w
    cb_y1 = cb_y0 + cb_h
    if mx >= cb_x0 and mx <= cb_x1 and my >= cb_y0 and my <= cb_y1 then
      hovered = false
    end
  end

  local over_header_wave = mx >= (x0 + 4) and mx <= (timeline_x0 - 4)
      and my >= (y0 + 3) and my <= header_y1
  if hovered and not over_header_wave then
    -- ReaImGui returns vertical and horizontal wheel as two values from one call.
    local wheel, wheel_h = r.ImGui_GetMouseWheel(ctx)
    wheel_h = wheel_h or 0.0
    local natural_scroll = (state.seq_scroll_mode == "natural")
    -- In natural mode the vertical wheel is left for ImGui to scroll the track
    -- list vertically; the horizontal wheel (trackpad/Magic Mouse) pans the
    -- timeline. In legacy mode the vertical wheel pans the timeline.
    local pan_wheel = natural_scroll and wheel_h or wheel
    -- Zoom gestures keep using the vertical wheel together with their modifier.
    -- Shift + horizontal wheel/trackpad scroll zooms the timeline.
    local shift_hzoom = wheel_h ~= 0 and is_shift_down()
    if wheel ~= 0 and mod_active("lane_zoom") and (not shift_hzoom or math.abs(wheel) >= math.abs(wheel_h)) then
      local zoom = state.seq_lane_zoom or 1.0
      local new_zoom = math.max(0.5, math.min(3.0, zoom * math.exp(wheel * 0.15)))
      if math.abs(new_zoom - zoom) > 1e-4 then
        state.seq_lane_zoom = new_zoom
        seq_reset_track_lane_heights()
        state.seq_lane_h_drag = nil
        save_config()
      end
    elseif (wheel ~= 0 and mod_active("time_zoom")) or shift_hzoom then
      local zoom_delta = shift_hzoom and -wheel_h or wheel
      if seq_apply_time_zoom(zoom_delta, mx, timeline_x0, timeline_w, view_start_qn, qn_span, step_qn) then
        start_qn, end_qn, step_qn, step_count = get_visible_qn_grid_range(state.seq_view_start_qn, state.seq_view_start_qn + state.seq_view_span_qn)
        view_start_qn = state.seq_view_start_qn
        view_span_qn = state.seq_view_span_qn
        qn_span = view_span_qn
      end
    elseif pan_wheel ~= 0 then
      if state.seq_follow_arrange then
        state.seq_drive_arrange = true
      end
      seq_timeline_scroll_impulse(pan_wheel, view_span_qn)
    end
  end

  if seq_timeline_scroll_apply_inertia(view_span_qn, scroll_dt) then
    start_qn, end_qn, step_qn, step_count = get_visible_qn_grid_range(
      state.seq_view_start_qn,
      state.seq_view_start_qn + (state.seq_view_span_qn or view_span_qn)
    )
    view_start_qn = state.seq_view_start_qn
  end

  if seq_view_is_driving_arrange() then
    seq_push_view_to_arrange()
    if not seq_timeline_scroll_is_active() then
      state.seq_drive_arrange = false
    end
  end


  local approx_measure_px = (4.0 / math.max(qn_span, 0.001)) * timeline_w
  local measure_guides = collect_measure_guides_qn(start_qn, end_qn, 256, seq_measure_guide_step(approx_measure_px))
  local active_cells = seq_build_visible_active_cells(start_qn, end_qn, step_qn, step_count)
  local selected_region_id = region.id
  local pattern = get_seq_pattern(region.pattern_id, true)
  local random_edit_region = state.seq_random_edit_region_id and get_seq_region_by_id(state.seq_random_edit_region_id) or nil
  local random_edit_pattern = random_edit_region and get_seq_pattern(random_edit_region.pattern_id, true) or nil
  local random_focus_prev = state.seq_random_active_key
  local random_focus_effective = random_focus_prev
  local random_focus_next = nil
  local random_overlay_text = nil
  local random_overlay_y = nil
  local random_overlay_x = nil
  if state.seq_random_edit_region_id and not random_edit_region then
    state.seq_random_edit_region_id = nil
    state.seq_random_active_key = nil
  end
  local now_t = r.time_precise()
  prune_seq_note_anims(now_t)
  prune_seq_track_play_anims(now_t)

  local function qn_to_x(qn) return timeline_x0 + ((qn - view_start_qn) / qn_span) * timeline_w end
  -- Cell edges must use the same continuous QN mapping as grid/region lines.
  -- Using col*cell_w drifts whenever view_start_qn is not grid-aligned.
  local function col_x0(col) return qn_to_x(start_qn + col * step_qn) end
  local function col_x1(col) return qn_to_x(start_qn + (col + 1) * step_qn) end
  local timeline_x1 = timeline_x0 + timeline_w
  local cell_px = (qn_span > 0 and step_qn > 0) and ((step_qn / qn_span) * timeline_w) or 32.0
  local seq_lod_skip_cell_grid = cell_px < 8.0
  local seq_lod_simple_notes = cell_px < 24.0
  local seq_grid_stride = 1
  if cell_px > 0 and cell_px < 12.0 then
    seq_grid_stride = math.max(1, math.floor(6.0 / cell_px + 0.5))
  end
  local vis_col0 = 0
  local vis_col1 = step_count - 1
  if step_qn > 0 then
    vis_col0 = math.max(0, math.floor((view_start_qn - start_qn) / step_qn) - 1)
    vis_col1 = math.min(step_count - 1, math.floor((view_start_qn + qn_span - start_qn) / step_qn) + 1)
  end
  local function push_timeline_clip(clip_y0, clip_y1)
    if r.ImGui_DrawList_PushClipRect then
      r.ImGui_DrawList_PushClipRect(dl, timeline_x0, clip_y0, timeline_x1, clip_y1, true)
      return true
    end
    return false
  end
  local function pop_timeline_clip(pushed)
    if pushed and r.ImGui_DrawList_PopClipRect then
      r.ImGui_DrawList_PopClipRect(dl)
    end
  end
  local function label_for_step(step)
    local denom = math.floor((4.0 / step) + 0.5)
    if denom > 0 and math.abs(step - (4.0 / denom)) < 0.0001 then return "1/" .. tostring(denom) end
    return string.format("%.3f QN", step)
  end

  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, header_y1, UI_THEME.bg, 6.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + width, header_y1, 0x40516AFF, 6.0, 0, 1.2)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, header_y1, UI_THEME.surface, 0)
  r.ImGui_DrawList_AddRectFilled(dl, timeline_x0, y0, timeline_x0 + timeline_w, y0 + region_lane_h, UI_THEME.bg_panel, 0)
  r.ImGui_DrawList_AddLine(dl, timeline_x0, y0 + region_lane_h, timeline_x0 + timeline_w, y0 + region_lane_h, 0x40516AFF, 1.0)
  r.ImGui_DrawList_AddLine(dl, timeline_x0, y0, timeline_x0, header_y1, 0x70829CFF, 1.5)
  r.ImGui_DrawList_AddLine(dl, timeline_x0, header_y1, timeline_x0 + timeline_w, header_y1, 0x607086FF, 2.0)
  draw_seq_header_preview_waveform(
    dl,
    x0 + 4,
    y0 + 3,
    math.max(16.0, timeline_x0 - x0 - 8),
    math.max(10.0, header_y1 - y0 - 6),
    mx, my, left_down, left_clicked
  )

  local measure_y0 = y0 + region_lane_h
  local measure_line_clr = 0x5A7A9840
  local measure_label_clr = 0x90A8C888
  local measure_header_clip = push_timeline_clip(measure_y0, header_y1)
  for i, guide in ipairs(measure_guides) do
    local px = qn_to_x(guide.qn_start)
    if px >= timeline_x0 and px <= timeline_x1 then
      local measure_num = guide.display_measure or (guide.measure + 1)
      r.ImGui_DrawList_AddLine(dl, px, measure_y0, px, header_y1, measure_line_clr, 1.0)
      r.ImGui_DrawList_AddText(dl, px + 4, measure_y0 + 7, measure_label_clr, tostring(measure_num))
    end
  end
  pop_timeline_clip(measure_header_clip)

  local link_hover = seq_update_link_hover(mx, my, y0, region_lane_h, timeline_x0, timeline_w, view_start_qn, qn_span, qn_to_x)

  -- Region blocks live above the ruler and align to the sequencer timeline.
  for _, reg in ipairs(state.seq_regions) do
    local reg_start = reg.start_qn or 0.0
    local reg_end = reg_start + get_seq_region_length_qn(reg)
    if reg_end >= start_qn and reg_start <= end_qn then
      local rx0 = math.max(timeline_x0, qn_to_x(reg_start))
      local rx1 = math.min(timeline_x0 + timeline_w, qn_to_x(reg_end))
      local selected = region and reg.id == region.id
      local linked = seq_region_is_linked(reg)
      local link_hl = seq_region_in_link_group(reg, link_hover)
      local swap_target = state.seq_region_drag and state.seq_region_drag.swap_region_id == reg.id
      local fill = seq_region_pool_color(reg.pool_id, selected and 220 or (link_hl and 210 or 78))
      if swap_target then
        fill = seq_region_pool_color(reg.pool_id, 90)
      end
      local edge = selected and 0xFFFFFFFF or seq_region_pool_color(reg.pool_id, link_hl and 230 or 120)
      if swap_target or link_hl then
        edge = 0xFFE599FF
      end
      r.ImGui_DrawList_AddRectFilled(dl, rx0 + 1, y0 + 3, rx1 - 1, y0 + region_lane_h - 3, fill, 4.0)
      r.ImGui_DrawList_AddRect(dl, rx0 + 1, y0 + 3, rx1 - 1, y0 + region_lane_h - 3, edge, 4.0, 0, (selected or link_hl) and 1.6 or 1.0)
      if link_hl then
        r.ImGui_DrawList_AddRect(dl, rx0, y0 + 1, rx1, y0 + region_lane_h - 1, 0xFFE599AA, 4.0, 0, 1.2)
      end
      local link_fits = linked and (rx1 - rx0) >= (SEQ_LINK_ICON_SIZE + SEQ_LINK_HIT_PAD * 2 + 8)
      local label_x = rx0 + 6
      if link_fits then
        label_x = rx0 + 6 + SEQ_LINK_ICON_SIZE + SEQ_LINK_HIT_PAD
      end
      local _, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after = seq_collect_region_random_entries(reg)
      local chips_x0 = link_fits and (rx0 + SEQ_LINK_ICON_SIZE + SEQ_LINK_HIT_PAD + 8) or rx0
      local random_labels = seq_region_random_label_layout(chips_x0, rx1, y0, region_lane_h, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after)
      local name_right = rx1 - 6
      if #random_labels > 0 then
        name_right = random_labels[1].x0 - 4
      end
      local region_clipped = false
      if r.ImGui_DrawList_PushClipRect then
        r.ImGui_DrawList_PushClipRect(dl, rx0, y0, rx1, y0 + region_lane_h, true)
        region_clipped = true
      end
      if link_fits then
        local icon_x, icon_y = seq_region_link_icon_xy(rx0, y0, region_lane_h)
        local lx0, ly0, lx1, ly1 = seq_region_link_hit_rect(rx0, y0, region_lane_h)
        local link_hovered = mx >= lx0 and mx <= lx1 and my >= ly0 and my <= ly1
        seq_draw_link_icon(dl, icon_x, icon_y, selected and 0xFFFFFFFF or 0xFFFFFF96, link_hovered or link_hl)
      end
      if name_right - label_x > 16 then
        local label = reg.name or ("Region " .. reg.id)
        r.ImGui_DrawList_AddText(dl, label_x, y0 + 5, selected and 0xFFFFFFFF or 0xFFFFFF96, label)
      end
      seq_draw_region_random_labels(dl, random_labels, mx, my)
      if region_clipped then
        r.ImGui_DrawList_PopClipRect(dl)
      end
      r.ImGui_DrawList_AddLine(dl, rx0, y0, rx0, header_y1, edge, (selected or link_hl) and 2.5 or 1.5)
    end
  end

  if state.seq_region_drag and left_down then
    local drag = state.seq_region_drag
    local current_qn_raw = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
    local current_qn = seq_snap_qn_for_region_drag(current_qn_raw, step_qn)
    local function begin_region_drag_undo()
      if not drag.undo_started then
        begin_seq_undo(drag.undo_label or "Edit sequencer region")
        drag.undo_started = true
      end
    end
    if drag.mode == "move" then
      local reg = get_seq_region_by_id(drag.region_id)
      if reg then
        local anchor_qn_raw = drag.anchor_qn_raw or drag.anchor_qn or current_qn_raw
        local desired = drag.orig_start_qn + (current_qn_raw - anchor_qn_raw)
        desired = math.max(0.0, seq_snap_qn_for_region_move(desired, step_qn))
        drag.preview_start_qn = desired
        local over = seq_region_containing_qn(current_qn_raw, drag.region_id)
        drag.swap_region_id = over and over.id or nil
      end
    elseif drag.mode == "pool_copy" then
      local desired = math.max(0.0, seq_snap_qn_for_region_drag(current_qn_raw - (drag.anchor_offset_qn or 0.0), step_qn))
      local insert_qn, over = seq_region_insert_qn(current_qn_raw, drag.source_region_id)
      if over then
        drag.current_start_qn = insert_qn
        drag.insert_qn = insert_qn
        drag.insert_target_id = over.id
      else
        drag.current_start_qn = desired
        drag.insert_qn = desired
        drag.insert_target_id = nil
      end
    elseif drag.mode == "resize_left" then
      local reg = get_seq_region_by_id(drag.region_id)
      if reg then
        begin_region_drag_undo()
        if seq_resize_region_start(reg, current_qn, step_qn) then
          seq_select_region(reg)
          region = reg
        end
      end
    elseif drag.mode == "resize_right" then
      local reg = get_seq_region_by_id(drag.region_id)
      if reg then
        begin_region_drag_undo()
        if seq_resize_region_end(reg, current_qn, step_qn) then
          seq_select_region(reg)
          region = reg
        end
      end
    elseif drag.mode == "create" then
      drag.current_qn = current_qn
    end
  end

  if state.seq_region_drag then
    local drag = state.seq_region_drag
    if drag.mode == "move" then
      local reg = get_seq_region_by_id(drag.region_id)
      if reg then
        local swap = drag.swap_region_id and get_seq_region_by_id(drag.swap_region_id)
        local orig_start = drag.orig_start_qn or (reg.start_qn or 0.0)
        if swap then
          -- Same layout the swap applies on release (regions in between
          -- shift when the lengths differ).
          local starts = seq_region_swap_layout(reg, swap) or {}
          for _, other in ipairs(state.seq_regions or {}) do
            local new_start = starts[other.id]
            if new_start and other.id ~= reg.id and other.id ~= swap.id then
              seq_draw_region_ghost(dl, new_start, new_start + get_seq_region_length_qn(other), y0, region_lane_h,
                timeline_x0, timeline_w, qn_to_x, seq_region_pool_color(other.pool_id, 50), seq_region_pool_color(other.pool_id, 160), nil)
            end
          end
          local reg_new = starts[reg.id] or (swap.start_qn or 0.0)
          local swap_new = starts[swap.id] or orig_start
          seq_draw_region_ghost(dl, reg_new, reg_new + get_seq_region_length_qn(reg), y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
            seq_region_pool_color(reg.pool_id, 110), 0xFFE599FF, (reg.name or "Region") .. "  ·  swap")
          seq_draw_region_ghost(dl, swap_new, swap_new + get_seq_region_length_qn(swap), y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
            seq_region_pool_color(swap.pool_id, 80), seq_region_pool_color(swap.pool_id, 210), (swap.name or "Region") .. "  ·  swap")
        elseif drag.preview_start_qn then
          local ghost_start = drag.preview_start_qn
          local ghost_end = ghost_start + get_seq_region_length_qn({ start_qn = ghost_start, length_bars = reg.length_bars })
          seq_draw_region_ghost(dl, ghost_start, ghost_end, y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
            seq_region_pool_color(reg.pool_id, 100), seq_region_pool_color(reg.pool_id, 220), reg.name or "Region")
        end
        if r.ImGui_SetTooltip then
          if swap then
            r.ImGui_SetTooltip(ctx, "Release to swap region positions")
          else
            r.ImGui_SetTooltip(ctx, "Release to move region")
          end
        end
      end
    elseif drag.mode == "pool_copy" and drag.current_start_qn then
      local src = get_seq_region_by_id(drag.source_region_id)
      if src then
        local ghost_start = drag.current_start_qn
        local ghost_end = ghost_start + get_seq_region_length_qn({ start_qn = ghost_start, length_bars = src.length_bars })
        seq_draw_region_ghost(dl, ghost_start, ghost_end, y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
          seq_region_pool_color(src.pool_id, 90), seq_region_pool_color(src.pool_id, 200),
          (src.name or "Region") .. "  ·  insert")
        if r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, "Release to insert a copy — later regions shift right")
        end
      end
    elseif drag.mode == "create" and drag.start_qn and drag.current_qn then
      local create_start = math.min(drag.start_qn, drag.current_qn)
      local create_end = math.max(drag.start_qn, drag.current_qn)
      if create_end - create_start < step_qn then
        create_end = create_start + (drag.default_length_qn or get_seq_region_length_qn({ start_qn = create_start, length_bars = 4 }))
      end
      seq_draw_region_ghost(dl, create_start, create_end, y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
        0x4A8BD688, 0x4A8BD6FF, nil)
    end
  end

  if hovered and not state.seq_region_drag and mx >= timeline_x0 and mx <= timeline_x0 + timeline_w and my >= y0 and my <= y0 + region_lane_h then
    local hover_hit = seq_hit_test_region_at(mx, my, y0, region_lane_h, timeline_x0, timeline_w, view_start_qn, qn_span, qn_to_x)
    if hover_hit and hover_hit.part == "link" then
      if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
      end
      if r.ImGui_SetTooltip then
        local names = seq_linked_region_names(hover_hit.region)
        local tip = "Linked region — click to unlink"
        if #names > 0 then
          tip = tip .. "\nLinked with " .. table.concat(names, ", ")
        end
        r.ImGui_SetTooltip(ctx, tip)
      end
    elseif hover_hit and (hover_hit.part == "rand_all" or hover_hit.part == "rand_prob" or hover_hit.part == "rand_human" or hover_hit.part == "rand_vel" or hover_hit.part == "rand_vary" or hover_hit.part == "rand_stut" or hover_hit.part == "rand_ghost" or hover_hit.part == "rand_grace" or hover_hit.part == "rand_after") then
      if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
      end
      if r.ImGui_SetTooltip then
        local tip = "Humanize — click to edit, double-click to reset"
        if hover_hit.part == "rand_all" then
          tip = "Randomization — click to edit, double-click to reset all"
        elseif hover_hit.part == "rand_prob" then
          tip = "Probability — click to edit, double-click to reset"
        elseif hover_hit.part == "rand_vel" then
          tip = "Velocity humanize — click to edit, double-click to reset"
        elseif hover_hit.part == "rand_vary" then
          tip = "Sample variation — click to edit, double-click to reset"
        elseif hover_hit.part == "rand_stut" then
          tip = "Stutter probability — click to edit, double-click to reset"
        elseif hover_hit.part == "rand_ghost" then
          tip = "Ghost notes — click to edit, double-click to reset"
        elseif hover_hit.part == "rand_grace" then
          tip = "Grace notes — click to edit, double-click to reset"
        elseif hover_hit.part == "rand_after" then
          tip = "After notes — click to edit, double-click to reset"
        end
        r.ImGui_SetTooltip(ctx, tip)
      end
    elseif hover_hit and is_shift_down() and (hover_hit.part == "left_edge" or hover_hit.part == "right_edge") then
      local insert_qn = hover_hit.region.start_qn or 0.0
      if hover_hit.part == "right_edge" then
        insert_qn = insert_qn + get_seq_region_length_qn(hover_hit.region)
      end
      local insert_len = get_seq_region_length_qn({ start_qn = insert_qn, length_bars = 4 })
      seq_draw_region_ghost(dl, insert_qn, insert_qn + insert_len, y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
        0x4A8BD655, 0x4A8BD6DD, "Insert")
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Shift+click to insert an empty region — later regions shift right")
      end
    elseif hover_hit and is_shift_down() and hover_hit.part ~= "left_edge" and hover_hit.part ~= "right_edge" and hover_hit.part ~= "link" then
      local hover_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
      local split_qn = seq_split_qn_for_region(hover_hit.region, hover_qn, step_qn)
      if split_qn then
        local sx = qn_to_x(split_qn)
        if sx >= timeline_x0 and sx <= timeline_x0 + timeline_w then
          r.ImGui_DrawList_AddLine(dl, sx, y0 + 2, sx, y0 + region_lane_h - 2, 0xFFE599FF, 2.0)
          r.ImGui_DrawList_AddLine(dl, sx, y0 + region_lane_h, sx, header_y1, 0xFFE599AA, 1.2)
        end
        if r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, "Shift+click to split region")
        end
      end
    elseif hover_hit and hover_hit.region and (hover_hit.part == "left_edge" or hover_hit.part == "right_edge") then
      if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
      end
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Drag to resize region\nShift+click to insert a region here")
      end
    elseif hover_hit and hover_hit.region then
      if r.ImGui_SetTooltip then
        local tip = "Drag to move · Ctrl+drag for a linked copy · Shift+click to split\n"
          .. "Double-click to rename · Alt+click or Delete to delete"
        if seq_region_is_linked(hover_hit.region) then
          local names = seq_linked_region_names(hover_hit.region)
          if #names > 0 then
            tip = "Linked with " .. table.concat(names, ", ") .. "\n" .. tip
          else
            tip = "Linked region\n" .. tip
          end
        end
        r.ImGui_SetTooltip(ctx, tip)
      end
    elseif not hover_hit then
      local hover_qn = seq_snap_qn_for_region_drag(seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span), step_qn)
      if is_shift_down() then
        local insert_qn = seq_region_insert_qn(hover_qn, nil)
        local insert_len = get_seq_region_length_qn({ start_qn = insert_qn, length_bars = 4 })
        seq_draw_region_ghost(dl, insert_qn, insert_qn + insert_len, y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
          0x4A8BD655, 0x4A8BD6DD, "Insert")
        if r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, "Shift+click to insert an empty region — later regions shift right")
        end
      else
        local preview_start_qn, preview_len_qn = seq_get_default_create_region_qn(hover_qn, step_qn)
        seq_draw_region_ghost(dl, preview_start_qn, preview_start_qn + preview_len_qn, y0, region_lane_h, timeline_x0, timeline_w, qn_to_x,
          0x4A8BD655, 0x4A8BD6DD, nil)
      end
    end
  end

  if left_clicked and not hovered then
    state.seq_random_popup_pending = nil
  end
  if r.ImGui_IsMouseClicked(ctx, 0) then
    state.seq_region_key_target = nil
  end

  if hovered and left_clicked and mx >= timeline_x0 and mx <= timeline_x0 + timeline_w and not over_random_flyout then
    local clicked_qn_raw = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
    local clicked_qn = seq_snap_qn_for_region_drag(clicked_qn_raw, step_qn)
    if my >= y0 and my <= y0 + region_lane_h then
      local hit = seq_hit_test_region_at(mx, my, y0, region_lane_h, timeline_x0, timeline_w, view_start_qn, qn_span, qn_to_x)
      if hit and (hit.part == "rand_all" or hit.part == "rand_prob" or hit.part == "rand_human" or hit.part == "rand_vel" or hit.part == "rand_vary" or hit.part == "rand_stut" or hit.part == "rand_ghost" or hit.part == "rand_grace" or hit.part == "rand_after") then
        local kind = "human"
        if hit.part == "rand_all" then
          kind = "all"
        elseif hit.part == "rand_prob" then
          kind = "prob"
        elseif hit.part == "rand_vel" then
          kind = "vel"
        elseif hit.part == "rand_vary" then
          kind = "vary"
        elseif hit.part == "rand_stut" then
          kind = "stut"
        elseif hit.part == "rand_grace" then
          kind = "grace"
        elseif hit.part == "rand_after" then
          kind = "after"
        elseif hit.part == "rand_ghost" then
          kind = "ghost"
        end
        seq_handle_region_random_label_click(hit.region, kind)
        region = hit.region
      else
        state.seq_random_popup_pending = nil
        -- Delete removes the region last clicked in this lane (see
        -- handle_seq_razor_keys); any other click disarms it.
        state.seq_region_key_target = (hit and hit.region and not is_alt_down()) and hit.region.id or nil
        if hit then
          if hit.part == "link" then
          local label = begin_seq_undo("Unlink sequencer region")
          seq_unpool_region(hit.region)
          end_seq_undo(label)
        elseif hit.part == "body" and is_alt_down() then
          local label = begin_seq_undo("Delete sequencer region")
          seq_delete_region_by_id(hit.region.id)
          end_seq_undo(label)
          region = get_selected_seq_region()
          if region then
            selected_region_id = region.id
            pattern = get_seq_pattern(region.pattern_id, true)
          end
          active_cells = seq_build_visible_active_cells(start_qn, end_qn, step_qn, step_count)
        elseif hit.part == "body" and is_shift_down() then
          seq_select_region(hit.region)
          region = hit.region
          if seq_split_qn_for_region(hit.region, clicked_qn_raw, step_qn) then
            local label = begin_seq_undo("Split sequencer region")
            local right = seq_split_region(hit.region, clicked_qn_raw, step_qn)
            if right then
              seq_select_region(right)
              region = right
            end
            end_seq_undo(label)
          end
        elseif (hit.part == "left_edge" or hit.part == "right_edge") and is_shift_down() then
          local insert_qn = hit.region.start_qn or 0.0
          if hit.part == "right_edge" then
            insert_qn = insert_qn + get_seq_region_length_qn(hit.region)
          end
          local label = begin_seq_undo("Insert sequencer region")
          create_seq_region(4, nil, false, insert_qn, true)
          region = get_selected_seq_region()
          end_seq_undo(label)
        elseif hit.part == "left_edge" then
          seq_select_region(hit.region)
          region = hit.region
          state.seq_region_drag = {
            mode = "resize_left",
            region_id = hit.region.id,
            undo_label = "Resize sequencer region",
            undo_started = false,
          }
        elseif hit.part == "right_edge" then
          seq_select_region(hit.region)
          region = hit.region
          state.seq_region_drag = {
            mode = "resize_right",
            region_id = hit.region.id,
            undo_label = "Resize sequencer region",
            undo_started = false,
          }
        elseif hit.part == "body" then
          if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            -- Double-click renames (the toolbar chip shows the field);
            -- clicking the toolbar chip zooms to the region.
            state.seq_region_drag = nil
            state.seq_region_key_target = nil
            seq_select_region(hit.region)
            seq_begin_region_rename(hit.region)
            region = hit.region
          else
            seq_select_region(hit.region)
            region = hit.region
            if is_ctrl_down() then
              state.seq_region_drag = {
                mode = "pool_copy",
                source_region_id = hit.region.id,
                anchor_offset_qn = clicked_qn - (hit.region.start_qn or 0.0),
                current_start_qn = hit.region.start_qn,
                length_bars = hit.region.length_bars,
                undo_label = "Pool copy sequencer region",
                start_mx = mx,
                start_my = my,
              }
            else
              state.seq_region_drag = {
                mode = "move",
                region_id = hit.region.id,
                anchor_qn = clicked_qn,
                anchor_qn_raw = clicked_qn_raw,
                orig_start_qn = hit.region.start_qn or 0.0,
                undo_label = "Move sequencer region",
                undo_started = false,
              }
            end
          end
        end
      else
        if is_shift_down() then
          local insert_qn = seq_region_insert_qn(clicked_qn, nil)
          local label = begin_seq_undo("Insert sequencer region")
          create_seq_region(4, nil, false, insert_qn, true)
          region = get_selected_seq_region()
          end_seq_undo(label)
        else
          local create_start_qn, create_length_qn, create_insert = seq_get_default_create_region_qn(clicked_qn, step_qn)
          state.seq_region_drag = {
            mode = "create",
            start_qn = create_start_qn,
            current_qn = create_start_qn,
            default_length_qn = create_length_qn,
            insert = create_insert,
            undo_label = "Create sequencer region",
            start_mx = mx,
            start_my = my,
          }
        end
      end
      end
    elseif my > y0 + region_lane_h and my <= header_y1 then
      state.seq_random_popup_pending = nil
      seq_set_playhead_qn(clicked_qn)
    end
  end

  if hovered and right_clicked and mx >= timeline_x0 and mx <= timeline_x0 + timeline_w and my >= y0 and my <= y0 + region_lane_h and not over_random_flyout then
    state.seq_random_popup_pending = nil
    local right_hit = seq_hit_test_region_at(mx, my, y0, region_lane_h, timeline_x0, timeline_w, start_qn, qn_span, qn_to_x)
    if right_hit and right_hit.region then
      if state.seq_random_edit_region_id == right_hit.region.id then
        state.seq_random_edit_region_id = nil
      else
        seq_select_region(right_hit.region)
        region = right_hit.region
        state.seq_random_edit_region_id = right_hit.region.id
      end
    end
  end

  render_seq_region_random_popup()

  local playhead_time = seq_get_playhead_time()
  if playhead_time then
    local playhead_qn = time_to_qn(playhead_time)
    if playhead_qn and playhead_qn >= start_qn and playhead_qn <= end_qn then
      local playhead_x = qn_to_x(playhead_qn)
      if playhead_x >= timeline_x0 - 1 and playhead_x <= timeline_x0 + timeline_w + 1 then
        local playing = r.GetPlayState and (r.GetPlayState() & 1) == 1
        local playhead_color = playing and 0xFFFF88EE or 0xFFFF8866
        local playhead_thickness = playing and 2.0 or 1.5
        r.ImGui_DrawList_AddLine(dl, playhead_x, y0, playhead_x, header_y1, playhead_color, playhead_thickness)
        r.ImGui_DrawList_AddCircleFilled(dl, playhead_x, y0 + region_lane_h + 6, 4.0, playhead_color, 12)
      end
    end
  end

  if show_confirm then
    render_seq_pattern_confirm_bar(dl, cb_x0, cb_y0, cb_x1, cb_y1)
  end

  if not r.ImGui_BeginChild(ctx, "sequencer_map_tracks", 0, math.max(0, tracks_avail_y), child_flags) then
    -- Tracks child did not open (no EndChild for it); close sequencer_map_area.
    r.ImGui_Dummy(ctx, 0, 0)
    r.ImGui_EndChild(ctx)
    return
  end
  -- Allow vertical track scrolling, but never keep a horizontal pan — Shift+wheel
  -- is reserved for timeline zoom and must not slide chrome sideways.
  if r.ImGui_SetScrollX then
    r.ImGui_SetScrollX(ctx, 0)
  end

  body_y0 = select(2, r.ImGui_GetCursorScreenPos(ctx))
  r.ImGui_Dummy(ctx, width, map_body_h)
  if r.ImGui_SetItemAllowOverlap then
    r.ImGui_SetItemAllowOverlap(ctx)
  end
  body_y1 = body_y0 + map_body_h

  local hover_on_razor, razor_hover_track_id, razor_hover_qn = seq_compute_razor_hover(
    mx, my, visual_rows, body_y0, body_y1, timeline_x0, timeline_w, view_start_qn, qn_span
  )

  r.ImGui_DrawList_AddRectFilled(dl, x0, body_y0, x0 + width, body_y1, UI_THEME.bg, 0)
  r.ImGui_DrawList_AddRect(dl, x0, body_y0, x0 + width, body_y1, 0x40516AFF, 0, 0, 1.2)
  r.ImGui_DrawList_AddLine(dl, timeline_x0, body_y0, timeline_x0, body_y1, 0x70829CFF, 1.5)

  for _, guide in ipairs(measure_guides) do
    local px = qn_to_x(guide.qn_start)
    if px >= timeline_x0 and px <= timeline_x1 then
      r.ImGui_DrawList_AddLine(dl, px, body_y0, px, body_y1, measure_line_clr, 1.0)
    end
  end

  if playhead_time then
    local playhead_qn = time_to_qn(playhead_time)
    if playhead_qn and playhead_qn >= start_qn and playhead_qn <= end_qn then
      local playhead_x = qn_to_x(playhead_qn)
      if playhead_x >= timeline_x0 - 1 and playhead_x <= timeline_x0 + timeline_w + 1 then
        local playing = r.GetPlayState and (r.GetPlayState() & 1) == 1
        local playhead_color = playing and 0xFFFF88EE or 0xFFFF8866
        local playhead_thickness = playing and 2.0 or 1.5
        r.ImGui_DrawList_AddLine(dl, playhead_x, body_y0, playhead_x, body_y1, playhead_color, playhead_thickness)
        r.ImGui_DrawList_AddCircleFilled(dl, playhead_x, body_y1 - 6, 3.0, playhead_color, 10)
      end
    end
  end

  -- Region ownership cues in the sequencer grid.
  for _, reg in ipairs(state.seq_regions) do
    local reg_start = reg.start_qn or 0.0
    local reg_end = reg_start + get_seq_region_length_qn(reg)
    if reg_end >= start_qn and reg_start <= end_qn then
      local rx0 = math.max(timeline_x0, qn_to_x(reg_start))
      local rx1 = math.min(timeline_x0 + timeline_w, qn_to_x(reg_end))
      local selected = region and reg.id == region.id
      local link_hl = seq_region_in_link_group(reg, link_hover)
      local fill = seq_region_pool_color(reg.pool_id, selected and 42 or (link_hl and 52 or 10))
      local edge = link_hl and 0xFFE599FF or seq_region_pool_color(reg.pool_id, selected and 255 or 90)
      r.ImGui_DrawList_AddRectFilled(dl, rx0, body_y0, rx1, body_y1, fill, 0)
      r.ImGui_DrawList_AddLine(dl, rx0, body_y0, rx0, body_y1, edge, (selected or link_hl) and 2.5 or 1.5)
      r.ImGui_DrawList_AddLine(dl, rx1, body_y0, rx1, body_y1, edge, (selected or link_hl) and 2.0 or 1.0)
    end
  end

  local edit_def = get_seq_note_edit_mode_def()
  local edit_style = edit_def and get_seq_row_lane_style({ type = "param", param = edit_def }) or nil
  seq_clear_stutter_badge_hits()
  local row_positions = {}
  local cursor_y = body_y0
  -- Row drawing only reads notes: memoize next-trigger lookups until it ends.
  seq_trigger_memo = {}
  for row_idx, row in ipairs(visual_rows) do
    local row_y0 = cursor_y
    local row_y1 = row_y0 + row.h
    row_positions[row_idx] = { y0 = row_y0, y1 = row_y1, row = row }
    cursor_y = row_y1
    local row_visible = row_y1 >= (header_y1 - 24.0) and row_y0 <= (body_viewport_y1 + 24.0)
    row_positions[row_idx].visible = row_visible
    if row_visible then

    local lane_style = get_seq_row_lane_style(row)
    if row.type == "note" and edit_style then
      lane_style = {
        bg = lane_style.bg,
        label_bg = edit_style.label_bg,
        timeline_bg = edit_style.timeline_bg,
        edge = edit_style.edge,
        accent = edit_style.accent,
      }
    end
    local track_boundary = row.type == "note" and row_idx > 1

    r.ImGui_DrawList_AddRectFilled(dl, x0, row_y0, x0 + width, row_y1, lane_style.bg, 0)
    r.ImGui_DrawList_AddRectFilled(dl, timeline_x0, row_y0, timeline_x0 + timeline_w, row_y1, lane_style.timeline_bg or lane_style.bg, 0)
    r.ImGui_DrawList_AddRectFilled(dl, x0, row_y0, timeline_x0 - 1, row_y1, lane_style.label_bg or lane_style.bg, 0)
    r.ImGui_DrawList_AddRectFilled(dl, x0, row_y0, x0 + 4, row_y1, lane_style.accent or UI_THEME.accent, 0)
    if row.type == "note" and row.slot then
      if row.slot.mute then
        r.ImGui_DrawList_AddRectFilled(dl, x0, row_y0, x0 + width, row_y1, 0x00000055, 0)
      elseif row.slot.solo then
        r.ImGui_DrawList_AddRectFilled(dl, x0, row_y0, x0 + 4, row_y1, 0xE8A020FF, 0)
      end
    end
    r.ImGui_DrawList_AddLine(dl, x0, row_y0, x0 + width, row_y0, lane_style.edge, 1.0)
    r.ImGui_DrawList_AddLine(dl, timeline_x0, row_y0, timeline_x0 + timeline_w, row_y0, lane_style.edge, 1.0)
    r.ImGui_DrawList_AddLine(dl, x0, row_y1, x0 + width, row_y1, lane_style.edge, 1.5)
    r.ImGui_DrawList_AddLine(dl, timeline_x0, row_y1, timeline_x0 + timeline_w, row_y1, lane_style.edge, 1.5)
    if track_boundary then
      r.ImGui_DrawList_AddLine(dl, x0, row_y0, x0 + width, row_y0, 0x8090A8FF, 2.5)
    end
    if row.type == "note" then
      local next_row = visual_rows[row_idx + 1]
      if next_row and next_row.type == "param" then
        r.ImGui_DrawList_AddLine(dl, x0, row_y1, x0 + width, row_y1, 0x607088FF, 2.0)
      end
    end

    local slot = row.slot
    if row.type == "note" and slot then
      local expanded = state.seq_expanded_tracks[tostring(slot.id)] == true
      local play_anim = get_seq_track_play_anim(slot.id, now_t)
      local cue_reg = random_edit_region or region
      local has_override = seq_slot_has_region_sample(slot, cue_reg)
      if has_override and cue_reg then
        local stripe = seq_region_pool_color(cue_reg.pool_id, 220)
        r.ImGui_DrawList_AddRectFilled(dl, x0, row_y0, x0 + 3.5, row_y1, stripe)
        local sr, sg, sb = extract_rgb_rrgbbaa(stripe)
        r.ImGui_DrawList_AddRectFilled(
          dl, x0, row_y0, timeline_x0 - 1, row_y1,
          build_color_rrgbbaa(sr, sg, sb, 26)
        )
      end
      if play_anim then
        local assigned_sample = seq_effective_slot_sample(slot, cue_reg)
          or (slot.sample_path and find_sample_by_path(slot.sample_path)) or nil
        draw_seq_track_play_row_fx(dl, x0, row_y0, timeline_x0 - 1, row_y1, play_anim.t, assigned_sample)
      end
      local name_alpha = play_anim and math.floor(180 + math.sin(play_anim.t * math.pi) * 75) or 255
      local ctrl = seq_get_track_control_layout(
        x0, row_y0, timeline_x0 - seq_track_nav_width(row.h) - 6.0, row_y1, slot
      )
      row_positions[row_idx].ctrl = ctrl
      seq_draw_track_name_and_expand(
        dl, slot, ctrl, expanded, name_alpha,
        (edit_style and edit_style.accent) or 0xFFDFAAFF,
        "Track " .. row_idx
      )

      local note_clip = push_timeline_clip(row_y0, row_y1)
      if not seq_lod_skip_cell_grid then
        for col = vis_col0, vis_col1 do
          if col % 2 == 1 then
            local cx0 = col_x0(col)
            local cx1 = col_x1(col)
            r.ImGui_DrawList_AddRectFilled(dl, cx0, row_y0, cx1, row_y1, seq_lane_color_with_alpha(lane_style.accent, 16), 0)
          end
        end
      end
      -- Shift insert preview is drawn under notes so a later hit stays on top.
      if seq_note_slip_modifier() and not edit_def
          and hovered and mx >= timeline_x0 and mx <= timeline_x0 + timeline_w
          and my >= row_y0 and my <= row_y1
          and not hover_on_razor and not seq_razor_gesture_active() and not state.seq_razor_drag
          and not (seq_param_drag_button_down(state.seq_param_drag, left_down, right_down)
            and state.seq_param_drag and state.seq_param_drag.region_id == region.id)
          and not seq_lane_random_controls_hit({ y0 = row_y0, y1 = row_y1, row = row }, mx, my, timeline_x0, header_y1, body_viewport_y1) then
        local slip_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
        local slip_col = math.max(0, math.min(step_count - 1, math.floor((slip_qn - start_qn) / step_qn + 1e-9)))
        local region_end_qn = (region.start_qn or 0.0) + get_seq_region_length_qn(region)
        local slip_in_region = slip_qn >= (region.start_qn or 0.0) and slip_qn < region_end_qn
        local slip_on_note = seq_resolve_hover_note(
          active_cells[slot.id] and active_cells[slot.id][slip_col],
          slip_qn, start_qn, slip_col, step_qn
        )
        if slip_in_region and not slip_on_note
            and not seq_visible_cell_is_locked(slot, slip_col, start_qn, step_qn, active_cells) then
          local highlight_end = math.min(region_end_qn, slip_qn + step_qn, seq_next_note_vis_qn_after(region, slot.id, slip_qn, step_qn))
          local hx0 = math.max(timeline_x0, qn_to_x(slip_qn))
          local hx1 = math.min(timeline_x1, qn_to_x(highlight_end))
          if hx1 > hx0 then
            local hover_fill = (edit_style and seq_lane_color_with_alpha(edit_style.accent, 51)) or 0xFFE59933
            local hover_edge = (edit_style and seq_lane_color_with_alpha(edit_style.accent, 255)) or 0xFFE599FF
            r.ImGui_DrawList_AddRectFilled(dl, hx0, row_y0, hx1, row_y1, hover_fill, 0)
            r.ImGui_DrawList_AddRect(dl, hx0, row_y0, hx1, row_y1, hover_edge, 0, 0, 1.5)
          end
        end
      end
      local row_hover_qn = nil
      if hovered and mx >= timeline_x0 and mx <= timeline_x1 and my >= row_y0 and my <= row_y1 then
        row_hover_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
      end
      local track_note_color = get_sample_dot_color(
        (slot.sample_path and find_sample_by_path(slot.sample_path))
        or seq_effective_slot_sample(slot, region)
      )
      local slot_cells = active_cells[slot.id]
      for col = vis_col0, vis_col1 do
        local active = slot_cells and slot_cells[col]
        if active and seq_active_cell_has_visual_start(active, start_qn, col, step_qn) then
          seq_draw_unfocused_note_marks(
            dl, active, row_y0, row_y1, selected_region_id, step_qn, qn_to_x, start_qn, col, track_note_color
          )
          if seq_lod_simple_notes then
            seq_draw_lane_notes_lod(
              dl, active, row_y0, row_y1, selected_region_id, step_qn, qn_to_x, start_qn, col, track_note_color
            )
          else
            seq_draw_lane_packed_notes(
              dl, slot, active, row_y0, row_y1, col_x0(col), col_x1(col),
              selected_region_id, now_t, step_qn, qn_to_x,
              edit_def, edit_style, mx, my, hover_on_razor,
              row_hover_qn, start_qn, col
            )
          end
        end
      end
      seq_draw_lane_delete_anims(
        dl, slot, row_y0, row_y1, now_t, step_qn, qn_to_x,
        timeline_x0, timeline_x1, selected_region_id
      )
      local lock_hover_col = nil
      local filter_hover_col = nil
      local draw_locks = (not seq_lod_skip_cell_grid) or seq_is_lock_def(edit_def)
      local draw_filters = (not seq_lod_skip_cell_grid) or seq_is_vary_filter_def(edit_def)
      if (draw_locks or draw_filters) and hovered and mx >= timeline_x0 and mx <= timeline_x0 + timeline_w
          and my >= row_y0 and my <= row_y1 and not hover_on_razor then
        local lock_hover_qn = row_hover_qn or seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
        lock_hover_col = math.max(0, math.min(step_count - 1, math.floor((lock_hover_qn - start_qn) / step_qn + 1e-9)))
        filter_hover_col = lock_hover_col
        if draw_locks and not seq_visible_cell_is_locked(slot, lock_hover_col, start_qn, step_qn, active_cells) then
          lock_hover_col = nil
        end
        if draw_filters and not seq_vary_filter_cell_key(slot, filter_hover_col, start_qn, step_qn) then
          filter_hover_col = nil
        end
      end
      if draw_locks then
        draw_seq_lock_spans(dl, slot, row_y0, row_y1, start_qn, step_qn, step_count, col_x0, col_x1, timeline_x0, timeline_x1, active_cells, seq_is_lock_def(edit_def), lock_hover_col)
      end
      if draw_filters then
        draw_seq_vary_filter_spans(dl, ctx, slot, row_y0, row_y1, start_qn, step_qn, step_count, col_x0, col_x1, timeline_x0, timeline_x1, seq_is_vary_filter_def(edit_def), filter_hover_col)
      end
      pop_timeline_clip(note_clip)
    elseif row.type == "param" and slot and row.param then
      local def = row.param
      local lane_top = row_y0 + 2
      local lane_bot = row_y1 - 2
      local is_stutter_lane = def.key == "stutter"
      local bipolar = def.min < 0
      local lane_label = def.label
      local hotkey = def.shortcut_id and shortcut_display(def.shortcut_id)
      if hotkey and hotkey ~= "" and hotkey ~= "None" then
        lane_label = string.format("%s  %s", def.label, hotkey)
      end
      r.ImGui_DrawList_AddText(dl, x0 + 36, row_y0 + 3, lane_style.accent or UI_THEME.accent, lane_label)

      -- Baseline / zero reference for the lane.
      local base_y = lane_bot
      if not is_stutter_lane then
        if bipolar then
          base_y = seq_param_y_from_value(def, 0.0, lane_top, lane_bot, step_qn)
          r.ImGui_DrawList_AddLine(dl, timeline_x0, base_y, timeline_x0 + timeline_w, base_y, seq_lane_color_with_alpha(lane_style.accent, 90), 1.0)
        else
          r.ImGui_DrawList_AddLine(dl, timeline_x0, lane_bot, timeline_x0 + timeline_w, lane_bot, seq_lane_color_with_alpha(lane_style.accent, 90), 1.0)
        end
      end

      local param_clip = push_timeline_clip(row_y0, row_y1)
      local slot_cells = active_cells[slot.id]
      for col = vis_col0, vis_col1 do
        local cx0 = col_x0(col)
        local cx1 = col_x1(col)
        if not seq_lod_skip_cell_grid and col % 2 == 1 then
          r.ImGui_DrawList_AddRectFilled(dl, cx0, row_y0, cx1, row_y1, seq_lane_color_with_alpha(lane_style.accent, 16), 0)
        end
        local active = slot_cells and slot_cells[col]
        if active and seq_active_cell_has_visual_start(active, start_qn, col, step_qn) then
          if seq_lod_simple_notes then
            seq_draw_param_lane_notes_lod(
              dl, ctx, active, def, selected_region_id, start_qn, col, step_qn,
              qn_to_x, lane_top, lane_bot, is_stutter_lane, lane_style
            )
          else
            seq_draw_param_lane_packed_notes(
              dl, ctx, slot, active, def, selected_region_id, start_qn, col, step_qn,
              qn_to_x, cx0, cx1, lane_top, lane_bot, base_y, bipolar, is_stutter_lane, lane_style, region
            )
          end
        end
      end
      pop_timeline_clip(param_clip)
    else
      r.ImGui_DrawList_AddText(dl, x0 + 8, row_y0 + 8, UI_THEME.text_dim, "No sequencer tracks configured")
    end
    end
  end

  seq_trigger_memo = nil
  render_seq_vary_filter_input()

  local slot_id_to_idx = {}
  for track_idx, track_slot in ipairs(state.seq_tracks) do
    slot_id_to_idx[track_slot.id] = track_idx
  end
  local map_icon_size = seq_icon_size_for_lane_h(note_lane_h)
  local map_ctrl_size = seq_ctrl_size_for_icon(map_icon_size)
  local map_nav_w = get_seq_track_sample_controls_width(map_ctrl_size, map_icon_size)
  local over_lane_mix_controls = false
  local mix_env_resync = false
  local env_resync_slot = nil

  local add_row_y0 = body_y0 + rows_h
  local add_row_y1 = add_row_y0 + add_track_row_h
  local label_col_w = timeline_x0 - x0
  r.ImGui_DrawList_AddRectFilled(dl, x0, add_row_y0, timeline_x0 - 1, add_row_y1, UI_THEME.bg_panel, 0)
  r.ImGui_DrawList_AddRectFilled(dl, timeline_x0, add_row_y0, timeline_x0 + timeline_w, add_row_y1, UI_THEME.bg, 0)
  r.ImGui_DrawList_AddLine(dl, x0, add_row_y0, x0 + width, add_row_y0, 0x607086FF, 1.5)
  r.ImGui_DrawList_AddLine(dl, x0, add_row_y1, x0 + width, add_row_y1, 0x40516AFF, 1.0)

  -- Draw visible region ownership again over row backgrounds so users can see which
  -- cells belong to each selected/copy/pooled region.
  local body_clip = push_timeline_clip(body_y0, body_y1)
  for _, reg in ipairs(state.seq_regions) do
    local reg_start = reg.start_qn or 0.0
    local reg_end = reg_start + get_seq_region_length_qn(reg)
    if reg_end >= start_qn and reg_start <= end_qn then
      local rx0 = math.max(timeline_x0, qn_to_x(reg_start))
      local rx1 = math.min(timeline_x1, qn_to_x(reg_end))
      local selected = region and reg.id == region.id
      local link_hl = seq_region_in_link_group(reg, link_hover)
      local fill = seq_region_pool_color(reg.pool_id, selected and 32 or (link_hl and 40 or 8))
      local edge = link_hl and 0xFFE599FF or seq_region_pool_color(reg.pool_id, selected and 255 or 100)
      r.ImGui_DrawList_AddRectFilled(dl, rx0, body_y0, rx1, body_y1, fill, 0)
      r.ImGui_DrawList_AddLine(dl, rx0, body_y0, rx0, body_y1, edge, (selected or link_hl) and 2.5 or 1.5)
      r.ImGui_DrawList_AddLine(dl, rx1, body_y0, rx1, body_y1, edge, (selected or link_hl) and 2.0 or 1.0)
    end
  end

  if not seq_lod_skip_cell_grid then
    for col = vis_col0, vis_col1 + 1, seq_grid_stride do
      local qn = start_qn + col * step_qn
      local px = qn_to_x(qn)
      if px >= timeline_x0 and px <= timeline_x1 then
        local clr = (math.abs(qn - math.floor(qn + 0.5)) < 0.0001) and 0x45505EFF or 0x2A303AFF
        r.ImGui_DrawList_AddLine(dl, px, body_y0, px, body_y1, clr, 1.0)
      end
    end
  end
  pop_timeline_clip(body_clip)
  -- Keep a hard edge so timeline graphics never read as overlapping track controls.
  r.ImGui_DrawList_AddLine(dl, timeline_x0, body_y0, timeline_x0, body_y1, 0x70829CFF, 1.5)

  seq_apply_track_lane_resize_interaction(row_positions, mx, my, x0, width, left_clicked, dl)
  seq_update_track_reorder_drag(row_positions, mx, my, left_down, left_clicked, x0, timeline_x0)
  seq_draw_track_reorder_overlay(dl, row_positions, x0, x0 + width)

  local hovered_slot, hovered_col, hovered_qn, hovered_row = nil, nil, nil, nil
  local param_drag_active = seq_param_drag_button_down(state.seq_param_drag, left_down, right_down)
      and state.seq_param_drag.region_id == region.id
  if hovered and mx >= x0 and mx <= timeline_x0 + timeline_w and my >= body_y0 and my <= body_y1 then
    for _, row_pos in ipairs(row_positions) do
      if my >= row_pos.y0 and my <= row_pos.y1 then
        hovered_row = row_pos
        hovered_slot = row_pos.row.slot
        break
      end
    end
    if mx >= timeline_x0 then
      hovered_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
      hovered_col = math.max(0, math.min(step_count - 1, math.floor((hovered_qn - start_qn) / step_qn + 1e-9)))
    end
    local over_rand = random_edit_region
      and hovered_row and hovered_row.row and hovered_row.row.type == "note"
      and seq_lane_random_controls_hit(hovered_row, mx, my, timeline_x0, header_y1, body_viewport_y1)
    if hovered_slot and hovered_qn ~= nil and not over_rand then
      local hover_in_selected = hovered_qn >= region.start_qn and hovered_qn < region.start_qn + get_seq_region_length_qn(region)
      if not param_drag_active and hover_in_selected and not seq_razor_gesture_active() and not state.seq_razor_drag
          and not hover_on_razor then
        local hx0 = math.max(timeline_x0, col_x0(hovered_col))
        local hx1 = math.min(timeline_x1, col_x1(hovered_col))
        local hover_edge = (edit_style and seq_lane_color_with_alpha(edit_style.accent, 255)) or 0xFFE599FF
        local hover_active = seq_resolve_hover_note(
          active_cells[hovered_slot.id] and active_cells[hovered_slot.id][hovered_col],
          hovered_qn, start_qn, hovered_col, step_qn
        )
        local slip_empty = seq_note_slip_modifier() and not edit_def
          and hovered_row.row.type == "note" and not hover_active
        if slip_empty then
          local region_end_qn = (region.start_qn or 0.0) + get_seq_region_length_qn(region)
          hx0 = qn_to_x(hovered_qn)
          hx1 = qn_to_x(math.min(region_end_qn, hovered_qn + step_qn))
          hx0 = math.max(timeline_x0, hx0)
          hx1 = math.min(timeline_x1, hx1)
        end
        local hover_locked = hovered_row.row.type == "note"
          and seq_visible_cell_is_locked(hovered_slot, hovered_col, start_qn, step_qn, active_cells)
        local hover_filter = hovered_row.row.type == "note"
          and seq_vary_filter_cell_key(hovered_slot, hovered_col, start_qn, step_qn)
        if hx1 > hx0 and not (hover_active and hovered_row.row.type == "note") and not slip_empty and not hover_locked
            and not hover_filter
            and not state.seq_over_lane_resize then
          local hover_fill = (edit_style and seq_lane_color_with_alpha(edit_style.accent, 51)) or 0xFFE59933
          r.ImGui_DrawList_AddRectFilled(dl, hx0, hovered_row.y0, hx1, hovered_row.y1, hover_fill, 0)
          r.ImGui_DrawList_AddRect(dl, hx0, hovered_row.y0, hx1, hovered_row.y1, hover_edge, 0, 0, 1.5)
        end
        if edit_def and hovered_row.row.type == "note" and not seq_is_decay_def(edit_def)
            and not seq_is_span_overlay_def(edit_def) then
          if hover_active then
            local hit_idx = seq_stutter_hit_param_key(edit_def.key) and seq_stutter_hit_index_at_qn(hover_active.note, hover_active.abs_qn, hovered_qn, step_qn) or nil
            local hover_val = seq_note_param_value(hover_active.note, edit_def.key, hit_idx)
            local value_text = format_seq_param_value(edit_def, hover_val)
            if seq_is_stutter_def(edit_def) then
              local skew = seq_stutter_skew(hover_active.note)
              if math.abs(skew) > 0.001 then
                value_text = string.format("%s  ·  skew %+.2f", value_text, skew)
              end
            elseif hit_idx then
              value_text = string.format("%s  ·  %d/%d", value_text, hit_idx, seq_stutter_count(hover_active.note))
            end
            local text_size = { r.ImGui_CalcTextSize(ctx, value_text) }
            local text_w = text_size[1] or 0
            local text_h = text_size[2] or 0
            local text_x = hx0 + 4
            local text_y = hovered_row.y0 - 16
            r.ImGui_DrawList_AddRectFilled(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0x000000CC, 3.0)
            r.ImGui_DrawList_AddRect(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, hover_edge, 3.0, 0, 1.0)
            r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, value_text)
          end
        end
      end
    end
  end

  local over_lane_random_controls = seq_random_flyout_hit(mx, my)
  if random_edit_region and hovered_row and hovered_row.row and hovered_row.row.type == "note" then
    over_lane_random_controls = over_lane_random_controls or seq_lane_random_controls_hit(hovered_row, mx, my, timeline_x0, header_y1, body_viewport_y1)
  end
  if state.seq_random_knob_drag then
    over_lane_random_controls = true
  end
  if hover_on_razor or over_lane_random_controls then
    state.seq_grid_hover = nil
  else
    seq_set_grid_hover(hovered_slot, hovered_col, active_cells, start_qn, step_qn, hovered_qn)
  end

  over_lane_mix_controls = false
  if hovered_row and hovered_row.row and hovered_row.row.type == "note" then
    over_lane_mix_controls = seq_lane_mix_controls_hit(hovered_row, mx, my, x0, timeline_x0, map_nav_w)
  end
  if not over_lane_mix_controls then
    for _, row_pos in ipairs(row_positions) do
      if seq_lane_mix_controls_hit(row_pos, mx, my, x0, timeline_x0, map_nav_w) then
        over_lane_mix_controls = true
        break
      end
    end
  end

  if state.seq_over_lane_resize then
    -- Cursor and divider highlight are handled by seq_apply_track_lane_resize_interaction.
  elseif state.seq_razor_drag and state.seq_razor_drag.mode == "move" then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeAll then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
    end
  elseif state.seq_note_drag and state.seq_note_drag.mode == "stutter_edit"
      and r.ImGui_SetMouseCursor then
    local axis = state.seq_note_drag.axis
    if axis == "count" and r.ImGui_MouseCursor_ResizeNS then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    elseif axis == "skew" and r.ImGui_MouseCursor_ResizeEW then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    elseif r.ImGui_MouseCursor_ResizeAll then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
    end
  elseif (not edit_def) and seq_stutter_badge_at(mx, my) then
    local badge = seq_stutter_badge_at(mx, my)
    if badge and dl then
      r.ImGui_DrawList_AddRect(dl, badge.x0, badge.y0, badge.x1, badge.y1, 0xC9A8FFFF, 2.0, 0, 1.4)
    end
    if r.ImGui_SetMouseCursor then
      if r.ImGui_MouseCursor_ResizeAll then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
      elseif r.ImGui_MouseCursor_Hand then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
      end
    end
    if r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "Drag vertically = hits\nDrag horizontally = skew")
    end
  elseif (state.seq_note_drag and (state.seq_note_drag.mode == "copy" or state.seq_note_drag.mode == "move"))
      and r.ImGui_SetMouseCursor then
    if state.seq_note_drag.mode == "move" and r.ImGui_MouseCursor_ResizeAll then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
    elseif r.ImGui_MouseCursor_Hand then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
  elseif seq_note_copy_modifier() and not edit_def and hovered_slot and hovered_qn ~= nil
      and mx >= timeline_x0 and hovered_row and hovered_row.row and hovered_row.row.type == "note"
      and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
    local hover_copy = seq_resolve_hover_note(
      active_cells[hovered_slot.id] and active_cells[hovered_slot.id][hovered_col],
      hovered_qn, start_qn, hovered_col, step_qn
    )
    if hover_copy then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
  elseif seq_note_slip_modifier() and not edit_def and hovered_slot and hovered_qn ~= nil
      and mx >= timeline_x0 and hovered_row and hovered_row.row and hovered_row.row.type == "note"
      and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeAll then
    local hover_move = seq_resolve_hover_note(
      active_cells[hovered_slot.id] and active_cells[hovered_slot.id][hovered_col],
      hovered_qn, start_qn, hovered_col, step_qn
    )
    if hover_move then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
    end
  elseif seq_razor_gesture_active() and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNWSE then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNWSE())
  elseif hovered_slot and hovered_qn ~= nil and mx >= timeline_x0
      and seq_cell_in_any_razor(hovered_slot.id, hovered_qn)
      and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeAll then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
  elseif seq_is_decay_def(edit_def) then
    local decay_kind = nil
    if state.seq_note_drag and state.seq_note_drag.mode == "decay" then
      decay_kind = state.seq_note_drag.handle
    else
      local decay_hit = seq_decay_hit_at(mx, my)
      decay_kind = decay_hit and decay_hit.kind
    end
    if decay_kind == "end" and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    elseif seq_decay_kind_is_curve(decay_kind) and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNS then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    elseif decay_kind and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
  end
  if seq_razor_gesture_active() and right_clicked and hovered_slot and hovered_qn ~= nil
      and mx >= timeline_x0 and not over_lane_mix_controls and not over_lane_random_controls
      and not state.seq_region_drag and not state.pending_waveform_drop then
    seq_begin_razor_drag(hovered_slot.id, hovered_qn, seq_razor_additive_gesture())
  elseif left_clicked and seq_has_razors() and hovered_slot and hovered_qn ~= nil
      and mx >= timeline_x0 and not over_lane_mix_controls and not over_lane_random_controls
      and not state.seq_over_lane_resize
      and not state.seq_region_drag and not state.pending_waveform_drop
      and not state.seq_razor_drag
      and seq_cell_in_any_razor(hovered_slot.id, hovered_qn) then
    seq_begin_razor_move(hovered_slot.id, hovered_qn, step_qn, seq_razor_copy_modifier())
  end
  if state.seq_razor_drag then
    seq_update_razor_drag(hovered_slot and hovered_slot.id, hovered_qn, row_positions, my)
    if state.seq_razor_drag.mode == "move" then
      seq_razor_apply_move(state.seq_razor_drag, step_qn)
    end
  end

  if hovered and left_clicked and not over_lane_mix_controls and not state.seq_over_lane_resize
      and not state.seq_track_reorder_drag then
    for _, row_pos in ipairs(row_positions) do
      local ctrl = row_pos.ctrl
      if row_pos.row.type == "note" and row_pos.row.slot and ctrl then
        if seq_layout_hit(ctrl.expand, mx, my) then
          local key = tostring(row_pos.row.slot.id)
          state.seq_expanded_tracks[key] = not state.seq_expanded_tracks[key] or nil
          save_config()
          break
        elseif (not state.pending_waveform_drop) and seq_layout_hit(ctrl.name, mx, my) then
          local track_idx = slot_id_to_idx[row_pos.row.slot.id]
          if track_idx then
            select_seq_track(track_idx)
          end
          break
        end
      end
    end
  end

  if hovered and right_clicked and not over_lane_mix_controls and not state.seq_over_lane_resize
      and not state.seq_track_reorder_drag and not state.pending_waveform_drop then
    for _, row_pos in ipairs(row_positions) do
      if seq_track_control_context_hit(row_pos, mx, my, x0, timeline_x0) then
        seq_open_track_context_menu(row_pos.row.slot.id)
        break
      end
    end
  end

  if hovered_slot and hovered_qn ~= nil and hovered_row and not state.seq_region_drag
      and not over_lane_random_controls and not over_lane_mix_controls
      and not state.seq_over_lane_resize and not state.seq_track_reorder_drag and not seq_razor_blocks_grid_edit() then
    local step_idx = math.floor(((hovered_qn - region.start_qn) / step_qn) + 1e-9)
    local in_region = hovered_qn >= region.start_qn and hovered_qn < region.start_qn + get_seq_region_length_qn(region)
    local step_key = tostring(step_idx)
    local cell_id = tostring(hovered_slot.id) .. ":" .. step_key
    local cell_active = active_cells[hovered_slot.id] and active_cells[hovered_slot.id][hovered_col]
    local active = seq_resolve_hover_note(cell_active, hovered_qn, start_qn, hovered_col, step_qn)

    local decay_hit = seq_is_decay_def(edit_def) and (left_clicked or right_clicked) and mx >= timeline_x0
      and not (r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0))
      and seq_decay_hit_at(mx, my)
    if decay_hit and decay_hit.note then
      local hit_region = get_seq_region_by_id(decay_hit.region_id) or region
      local hit_note = get_seq_note(hit_region, decay_hit.track_id, decay_hit.step_key) or decay_hit.note
      if right_clicked then
        local label = begin_seq_undo("Reset sequencer decay")
        local changed = false
        if decay_hit.kind == "end" then
          if seq_note_has_stutter_span(hit_note, step_qn) or seq_stutter_count(hit_note) > 1 then
            if math.abs((hit_note.length_qn or 0.0) - step_qn) > 1e-9 then
              hit_note.length_qn = step_qn
              changed = true
            end
          elseif hit_note.decay_qn ~= nil then
            hit_note.decay_qn = nil
            changed = true
          end
          seq_clamp_note_fades(hit_note, seq_note_current_decay_length_qn(hit_region, seq_find_slot_by_id(decay_hit.track_id), hit_note, decay_hit.step_key, step_qn))
        elseif decay_hit.kind == "fade_in" then
          changed = seq_note_clear_fade_side(hit_note, "in")
        elseif decay_hit.kind == "fade_out" then
          changed = seq_note_clear_fade_side(hit_note, "out")
        elseif decay_hit.kind == "curve_in" then
          changed = seq_note_set_fade_curve(hit_note, "in", 0)
        elseif decay_hit.kind == "curve_out" then
          changed = seq_note_set_fade_curve(hit_note, "out", 0)
        end
        if changed then
          local hit_slot = seq_find_slot_by_id(decay_hit.track_id)
          if hit_region and hit_slot then
            sync_seq_pattern_track(hit_region.pattern_id, hit_slot, { force_rebuild = true })
          end
          save_config()
        end
        end_seq_undo(label)
        state.selected_seq_note = { region_id = hit_region.id, track_id = decay_hit.track_id, step_key = decay_hit.step_key }
      else
        local label = begin_seq_undo("Edit sequencer decay")
        local which = (decay_hit.kind == "fade_in" or decay_hit.kind == "curve_in") and "in"
          or ((decay_hit.kind == "fade_out" or decay_hit.kind == "curve_out") and "out" or nil)
        local origin_shape = 1
        local origin_curve = 0.0
        local origin_fade_qn = 0.0
        if which then
          origin_fade_qn = seq_note_fade_qn(hit_note, which)
          if origin_fade_qn > 1e-6 then
            origin_shape = seq_note_fade_shape(hit_note, which)
            origin_curve = seq_note_fade_curve(hit_note, which)
          end
        end
        state.seq_note_drag = {
          mode = "decay",
          handle = decay_hit.kind,
          track_id = decay_hit.track_id,
          region_id = hit_region.id,
          step_key = decay_hit.step_key,
          origin_x = mx,
          origin_y = my,
          origin_shape = origin_shape,
          origin_curve = origin_curve,
          origin_fade_qn = origin_fade_qn,
          note_start_qn = seq_note_abs_qn(hit_region, hit_note, decay_hit.step_key, step_qn) + (hit_note.offset_qn or 0.0),
          max_length_qn = seq_note_decay_max_qn(hit_region, seq_find_slot_by_id(decay_hit.track_id), hit_note, decay_hit.step_key, step_qn),
          undo_label = label,
          undo_open = true,
          dirty = false,
        }
        apply_seq_decay_drag(
          state.seq_note_drag, hit_region, step_qn,
          mx, my, timeline_x0, timeline_w, view_start_qn, qn_span
        )
      end
    elseif hovered_row.row.type == "param" and hovered_row.row.param and in_region and left_clicked and mx >= timeline_x0 then
      local def = hovered_row.row.param
      local start_value = def.default
      if active then
        start_value = seq_note_param_value(active.note, def.key, seq_stutter_hit_index_at_qn(active.note, active.abs_qn, hovered_qn, step_qn))
        if start_value == nil then
          start_value = def.default
        end
      else
        start_value = seq_param_value_for_drag(def, seq_param_value_from_y(def, my, hovered_row.y0 + 2, hovered_row.y1 - 2, step_qn), step_qn)
      end
      state.seq_param_drag = {
        track_id = hovered_slot.id,
        param = def.key,
        region_id = region.id,
        step_key = active and active.key or step_key,
        col = hovered_col,
        end_col = hovered_col,
        ramp = mod_active("velocity_ramp"),
        unify = mod_active("unify") and not mod_active("velocity_ramp"),
        start_value = start_value,
        origin_y = my,
        origin_count = (def.key == "stutter") and seq_clamp_stutter_count(start_value) or nil,
        button = 0,
      }
      if active then
        state.selected_seq_note = { region_id = region.id, track_id = hovered_slot.id, step_key = active.key }
      end
    elseif state.pending_waveform_drop then
      local track_idx = hovered_slot and slot_id_to_idx[hovered_slot.id]
      local drop_qn = (hovered_col ~= nil)
        and (start_qn + hovered_col * step_qn)
        or hovered_qn
      state.seq_timeline_drop_track_idx = track_idx
      state.seq_timeline_drop_time = qn_to_time(drop_qn)
      state.seq_drop_target_idx = nil
      -- Highlight the cell under the cursor and draw an insertion marker so the
      -- exact drop position on the timeline is obvious.
      local cell_x0 = col_x0(hovered_col)
      local cell_x1 = col_x1(hovered_col)
      draw_drop_target_highlight(dl, cell_x0, hovered_row.y0, cell_x1, hovered_row.y1, 2)
      local pulse = drag_pulse()
      local line_col = build_color_rrgbbaa(120, 200, 255, math.floor(170 + 85 * pulse))
      r.ImGui_DrawList_AddLine(dl, cell_x0, body_y0, cell_x0, body_y1, line_col, 2.0)
      r.ImGui_DrawList_AddTriangleFilled(dl, cell_x0 - 5, body_y0, cell_x0 + 5, body_y0, cell_x0, body_y0 + 7, line_col)
    elseif hovered_row.row.type == "note" and not in_region and left_clicked and mx >= timeline_x0 then
      local hover_reg = seq_region_at_qn(hovered_qn)
      if hover_reg then
        seq_select_region(hover_reg)
        region = hover_reg
        selected_region_id = region.id
      end
    elseif hovered_row.row.type == "note" and in_region and left_clicked and mx >= timeline_x0
        and is_alt_down() and not edit_def
        and not (r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)) then
      local label = begin_seq_undo("Create sequencer stutter")
      state.seq_note_drag = {
        mode = "stutter",
        track_id = hovered_slot.id,
        region_id = region.id,
        start_col = hovered_col,
        end_col = hovered_col,
        origin_y = my,
        undo_label = label,
        undo_open = true,
        dirty = false,
      }
      if apply_seq_stutter_lane_drag(
        state.seq_note_drag, region, step_qn, start_qn, step_count,
        mx, my, timeline_x0, timeline_w, view_start_qn, qn_span
      ) then
        state.seq_note_drag.dirty = true
      elseif not state.seq_note_drag.step_key then
        if state.seq_note_drag.undo_open then
          end_seq_undo(label)
        end
        state.seq_note_drag = nil
      end
    elseif hovered_row.row.type == "note" and in_region and left_clicked and mx >= timeline_x0
        and seq_note_copy_modifier() and not edit_def and not is_alt_down()
        and not (r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0))
        and active and active.note then
      local picked = seq_pick_packed_note(active, hovered_qn, start_qn, hovered_col, step_qn) or active
      local src_region = get_seq_region_by_id(picked.region_id) or region
      local src_key = tostring(picked.key)
      local src_note = get_seq_note(src_region, hovered_slot.id, src_key) or picked.note
      local src_abs = seq_note_abs_qn(src_region, src_note, src_key, step_qn)
      -- Plain clone: the note keeps following the track sample unless it
      -- was already pinned (an existing frozen sample stays in the copy).
      local baked = clone_table_deep(src_note)
      local label = begin_seq_undo("Copy sequencer note")
      state.selected_seq_note = { region_id = src_region.id, track_id = hovered_slot.id, step_key = src_key }
      state.seq_note_drag = {
        mode = "copy",
        track_id = hovered_slot.id,
        region_id = src_region.id,
        src_step_key = src_key,
        src_abs_qn = src_abs,
        src_snap_qn = math.floor((src_abs / step_qn) + 1e-9) * step_qn,
        src_note = baked,
        src_length_qn = seq_note_length_qn_for_copy(src_region, hovered_slot, src_note, src_key, step_qn),
        patterns_backup = clone_table_deep(state.seq_patterns),
        origin_x = mx,
        origin_y = my,
        undo_label = label,
        undo_open = true,
        dirty = false,
      }
    elseif hovered_row.row.type == "note" and in_region and left_clicked and mx >= timeline_x0
        and seq_note_slip_modifier() and not edit_def and not is_alt_down()
        and not seq_note_copy_modifier()
        and not (r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0))
        and active and active.note then
      local picked = seq_pick_packed_note(active, hovered_qn, start_qn, hovered_col, step_qn) or active
      local src_region = get_seq_region_by_id(picked.region_id) or region
      local src_key = tostring(picked.key)
      local src_note = get_seq_note(src_region, hovered_slot.id, src_key) or picked.note
      local src_abs = seq_note_abs_qn(src_region, src_note, src_key, step_qn)
      -- Plain clone: the note keeps following the track sample unless it
      -- was already pinned (an existing frozen sample stays in the copy).
      local baked = clone_table_deep(src_note)
      local label = begin_seq_undo("Move sequencer note")
      state.selected_seq_note = { region_id = src_region.id, track_id = hovered_slot.id, step_key = src_key }
      state.seq_note_drag = {
        mode = "move",
        snap = false,
        track_id = hovered_slot.id,
        region_id = src_region.id,
        src_step_key = src_key,
        src_abs_qn = src_abs,
        grab_qn = hovered_qn,
        src_note = baked,
        src_length_qn = seq_note_length_qn_for_copy(src_region, hovered_slot, src_note, src_key, step_qn),
        patterns_backup = clone_table_deep(state.seq_patterns),
        origin_x = mx,
        origin_y = my,
        undo_label = label,
        undo_open = true,
        dirty = false,
      }
    elseif hovered_row.row.type == "note" and in_region and left_clicked and mx >= timeline_x0
        and seq_note_slip_modifier() and not edit_def and not is_alt_down()
        and not seq_note_copy_modifier()
        and not (r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0))
        and not active
        and not seq_visible_cell_is_locked(hovered_slot, hovered_col, start_qn, step_qn, active_cells) then
      local insert_rel = seq_quantize_free_qn(hovered_qn - (region.start_qn or 0.0))
      local insert_step = tostring(math.floor((insert_rel / step_qn) + 1e-9))
      local note = make_default_seq_note(hovered_slot, insert_step, insert_rel)
      if note then
        local label = begin_seq_undo("Insert sequencer note")
        state.seq_note_drag = {
          mode = "move",
          snap = false,
          place_new = true,
          track_id = hovered_slot.id,
          region_id = region.id,
          src_abs_qn = hovered_qn,
          grab_qn = hovered_qn,
          src_note = note,
          patterns_backup = clone_table_deep(state.seq_patterns),
          origin_x = mx,
          origin_y = my,
          undo_label = label,
          undo_open = true,
          dirty = false,
        }
        if apply_seq_note_copy_drag(
          state.seq_note_drag, step_qn, start_qn, step_count,
          mx, my, timeline_x0, timeline_w, view_start_qn, qn_span, row_positions
        ) then
          state.seq_note_drag.dirty = true
        end
      else
        log("Sequencer slot has no assigned sample")
      end
    elseif hovered_row.row.type == "note" and in_region and left_clicked and mx >= timeline_x0
        and not edit_def and not is_alt_down()
        and not seq_note_copy_modifier() and not seq_note_slip_modifier()
        and not (r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0))
        and seq_stutter_badge_at(mx, my)
        and tostring(seq_stutter_badge_at(mx, my).track_id) == tostring(hovered_slot.id) then
      local badge = seq_stutter_badge_at(mx, my)
      local badge_region = get_seq_region_by_id(badge.region_id) or region
      local badge_note = get_seq_note(badge_region, badge.track_id, badge.step_key)
      if badge_note then
        seq_begin_stutter_edit_drag(badge_region, hovered_slot, badge.step_key, badge_note, mx, my, "Edit sequencer stutter")
      end
    elseif hovered_row.row.type == "note" and in_region and (left_clicked or right_clicked) and mx >= timeline_x0
        and not seq_vary_filter_edit_blocks_clicks() then
      if seq_is_decay_def(edit_def) then
        -- Clicks that miss decay handles do not paint or edit params.
      elseif seq_is_lock_def(edit_def) then
        local started_on_lock = seq_visible_cell_is_locked(
          hovered_slot, hovered_col, start_qn, step_qn, active_cells
        )
        local reset = right_clicked or (left_clicked and started_on_lock)
        local label = begin_seq_undo(reset and "Unlock sequencer cells" or "Lock sequencer cells")
        local changed = false
        if not reset then
          changed = seq_apply_lock_range(
            region, hovered_slot.id, hovered_col, hovered_col, start_qn, step_qn, true, active_cells
          )
        end
        state.seq_param_drag = {
          track_id = hovered_slot.id,
          param = edit_def.key,
          region_id = region.id,
          step_key = (active and active.key) or step_key,
          col = hovered_col,
          end_col = hovered_col,
          ramp = false,
          unify = true,
          start_value = reset and 0.0 or 1.0,
          source = "note",
          reset = reset,
          lock_click_span = reset and true or nil,
          button = right_clicked and 1 or 0,
          undo_label = label,
          undo_open = true,
          dirty = changed,
        }
        if active then
          state.selected_seq_note = { region_id = region.id, track_id = hovered_slot.id, step_key = active.key }
        end
      elseif seq_is_vary_filter_def(edit_def) then
        local started_on = seq_visible_cell_vary_filter(hovered_slot, hovered_col, start_qn, step_qn)
        local reset = right_clicked
        if reset then
          if started_on then
            seq_cancel_vary_filter_edit()
            local label = begin_seq_undo("Clear sequencer vary filter")
            state.seq_param_drag = {
              track_id = hovered_slot.id,
              param = edit_def.key,
              region_id = region.id,
              step_key = (active and active.key) or step_key,
              col = hovered_col,
              end_col = hovered_col,
              ramp = false,
              unify = true,
              start_value = 0.0,
              source = "note",
              reset = true,
              filter_click_span = true,
              button = 1,
              undo_label = label,
              undo_open = true,
              dirty = false,
            }
          end
        else
          local edit = state.seq_vary_filter_edit
          local in_current = edit and tostring(edit.track_id) == tostring(hovered_slot.id)
            and type(edit.col_min) == "number" and type(edit.col_max) == "number"
            and hovered_col >= edit.col_min and hovered_col <= edit.col_max
          if edit and not in_current then
            seq_commit_vary_filter_edit()
          end
          state.seq_param_drag = {
            track_id = hovered_slot.id,
            param = edit_def.key,
            region_id = region.id,
            step_key = (active and active.key) or step_key,
            col = hovered_col,
            end_col = hovered_col,
            ramp = false,
            unify = true,
            start_value = 1.0,
            source = "note",
            reset = false,
            filter_click_span = started_on and true or nil,
            button = 0,
            undo_open = false,
            dirty = false,
          }
          if not started_on and not in_current then
            seq_begin_vary_filter_edit(region, hovered_slot.id, hovered_col, hovered_col, start_qn, step_qn, "", nil)
            if state.seq_vary_filter_edit then
              state.seq_vary_filter_edit.focus = false
            end
          end
        end
        if active then
          state.selected_seq_note = { region_id = region.id, track_id = hovered_slot.id, step_key = active.key }
        end
      elseif seq_is_stutter_def(edit_def) then
        if active and active.note then
          if right_clicked then
            local label = begin_seq_undo("Reset sequencer stutter")
            local changed = seq_reset_note_param_value(active.note, "stutter", nil, 1)
            if changed then
              sync_seq_pattern_track(region.pattern_id, hovered_slot, { force_rebuild = true })
              if seq_schedule_ingest_save then
                seq_schedule_ingest_save()
              else
                save_config()
              end
            end
            end_seq_undo(label)
            state.selected_seq_note = { region_id = region.id, track_id = hovered_slot.id, step_key = active.key }
          elseif left_clicked and not is_alt_down() then
            seq_begin_stutter_edit_drag(
              region, hovered_slot, active.key, active.note, mx, my, "Edit sequencer stutter"
            )
          end
        end
      elseif edit_def then
        if active then
          local reset = right_clicked
          local ramp = (not reset) and mod_active("velocity_ramp")
          local label = begin_seq_undo(reset
            and ("Reset sequencer " .. (edit_def.mode_name or edit_def.label))
            or ("Edit sequencer " .. (edit_def.mode_name or edit_def.label)))
          local start_value = seq_note_param_value(active.note, edit_def.key, seq_stutter_hit_index_at_qn(active.note, active.abs_qn, hovered_qn, step_qn))
          if start_value == nil then
            start_value = edit_def.default
          end
          state.seq_param_drag = {
            track_id = hovered_slot.id,
            param = edit_def.key,
            region_id = region.id,
            step_key = active.key or step_key,
            col = hovered_col,
            end_col = hovered_col,
            ramp = ramp,
            unify = (not reset) and mod_active("unify") and not ramp,
            start_value = start_value,
            source = "note",
            reset = reset,
            button = right_clicked and 1 or 0,
            undo_label = label,
            undo_open = true,
          }
          state.selected_seq_note = { region_id = region.id, track_id = hovered_slot.id, step_key = active.key }
        end
      else
        local hover_locked = left_clicked and seq_visible_cell_is_locked(
          hovered_slot, hovered_col, start_qn, step_qn, active_cells
        )
        if hover_locked then
          local label = begin_seq_undo("Unlock sequencer cells")
          local lo, hi = seq_lock_span_cols(
            hovered_slot, hovered_col, start_qn, step_qn, step_count, active_cells
          )
          local changed = seq_apply_lock_range(
            region, hovered_slot.id, lo, hi, start_qn, step_qn, false, active_cells
          )
          if changed then
            sync_seq_pattern_track(region.pattern_id, hovered_slot, { force_rebuild = true })
            if seq_schedule_ingest_save then
              seq_schedule_ingest_save()
            else
              save_config()
            end
          end
          end_seq_undo(label)
        else
          local click_key = step_key
          local click_qn = step_idx * step_qn
          local picked = seq_pick_packed_note(active, hovered_qn, start_qn, hovered_col, step_qn)
          if picked and picked.note then
            click_key = picked.key
            click_qn = seq_note_qn_offset(picked.note, picked.key, step_qn)
          end
          local mode = right_clicked and "erase" or "paint"
          local label = begin_seq_undo(left_clicked and "Paint sequencer notes" or "Erase sequencer notes")
          local painted = toggle_seq_note(region, hovered_slot, click_key, click_qn, right_clicked and "erase" or nil, {
            defer_save = true,
          })
          state.seq_note_drag = {
            track_id = hovered_slot.id,
            region_id = region.id,
            start_col = hovered_col,
            end_col = hovered_col,
            applied_min = hovered_col,
            applied_max = hovered_col,
            mode = mode,
            undo_label = label,
            undo_open = true,
            dirty = painted,
          }
        end
      end
    end
  end

  local note_drag_active = state.seq_note_drag and state.seq_note_drag.region_id == region.id
  if note_drag_active and not state.seq_region_drag then
    local drag = state.seq_note_drag
    if drag.mode == "stutter" then
      if left_down then
        if apply_seq_stutter_lane_drag(
          drag, region, step_qn, start_qn, step_count,
          mx, my, timeline_x0, timeline_w, view_start_qn, qn_span
        ) then
          drag.dirty = true
        end
      end
    elseif drag.mode == "stutter_edit" then
      if left_down then
        local drag_region = get_seq_region_by_id(drag.region_id) or region
        if apply_seq_stutter_edit_drag(drag, drag_region, mx, my) then
          drag.dirty = true
        end
      end
    elseif drag.mode == "decay" then
      if left_down then
        local drag_region = get_seq_region_by_id(drag.region_id) or region
        if apply_seq_decay_drag(
          drag, drag_region, step_qn,
          mx, my, timeline_x0, timeline_w, view_start_qn, qn_span
        ) then
          drag.dirty = true
        end
      end
    elseif drag.mode == "copy" or drag.mode == "move" then
      if left_down and mx >= timeline_x0 then
        if apply_seq_note_copy_drag(
          drag, step_qn, start_qn, step_count,
          mx, my, timeline_x0, timeline_w, view_start_qn, qn_span, row_positions
        ) then
          drag.dirty = true
        end
      end
    else
      local drag_down = (drag.mode == "paint" and left_down) or (drag.mode == "erase" and right_down)
      if drag_down and mx >= timeline_x0 then
        local prev_min = drag.applied_min or drag.start_col
        local prev_max = drag.applied_max or drag.start_col
        local end_col = seq_param_mouse_col(mx, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, step_qn, step_count)
        local col_min = math.min(drag.start_col, end_col)
        local col_max = math.max(drag.start_col, end_col)
        if col_min < prev_min or col_max > prev_max then
          if apply_seq_note_lane_drag(drag, region, step_qn, start_qn, step_count, mx, timeline_x0, timeline_w, view_start_qn, qn_span) then
            drag.dirty = true
          end
        else
          drag.end_col = end_col
        end
      end
    end
  end

  param_drag_active = seq_param_drag_button_down(state.seq_param_drag, left_down, right_down)
      and state.seq_param_drag.region_id == region.id
  if param_drag_active then
    local drag = state.seq_param_drag
    local def = get_param_lane_def(drag.param)
    local lane_y0, lane_y1, lane_row
    if drag.source == "note" then
      lane_y0, lane_y1, lane_row = find_seq_note_lane_bounds(row_positions, drag.track_id)
    else
      lane_y0, lane_y1, lane_row = find_seq_param_lane_bounds(row_positions, drag.track_id, drag.param)
    end
    if def and lane_y0 and lane_row and not seq_is_decay_def(def) then
      if not drag.reset then
        if mod_active("velocity_ramp") and not drag.ramp then
          drag.ramp = true
          drag.unify = false
          local anchor = active_cells[drag.track_id] and active_cells[drag.track_id][drag.col]
          if anchor then
            drag.start_value = seq_note_param_value(anchor.note, def.key, seq_stutter_hit_index_at_qn(anchor.note, anchor.abs_qn, start_qn + drag.col * step_qn + step_qn * 0.5, step_qn))
            if drag.start_value == nil then
              drag.start_value = def.default
            end
          end
        elseif mod_active("unify") and not drag.ramp and not drag.unify then
          drag.unify = true
        end
      end

      local changed, current_value, highlight_col_min, highlight_col_max, mouse_col
      if drag.reset then
        changed, current_value, highlight_col_min, highlight_col_max, mouse_col = apply_seq_param_reset_drag(
          drag, def, mx, step_qn, step_count, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, active_cells
        )
      else
        changed, current_value, highlight_col_min, highlight_col_max, mouse_col = apply_seq_param_lane_drag(
          drag, def, lane_y0, lane_y1, mx, my, step_qn, step_count, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, active_cells
        )
      end
      if changed then
        drag.dirty = true
      end

      if not seq_is_span_overlay_def(def) then
      local hx0 = math.max(timeline_x0, col_x0(highlight_col_min))
      local hx1 = math.min(timeline_x1, col_x1(highlight_col_max))
      if hx1 > hx0 then
        r.ImGui_DrawList_AddRectFilled(dl, hx0, lane_row.y0, hx1, lane_row.y1, 0xFFB84D44, 0)
        r.ImGui_DrawList_AddRect(dl, hx0, lane_row.y0, hx1, lane_row.y1, 0xFFB84DFF, 0, 0, 2.0)
      end

      if drag.ramp then
        local lane_top = lane_row.y0 + 2
        local lane_bot = lane_row.y1 - 2
        local start_val = drag.start_value or def.default
        local x0 = (col_x0(drag.col) + col_x1(drag.col)) * 0.5
        local x1 = (col_x0(drag.end_col) + col_x1(drag.end_col)) * 0.5
        local y0 = seq_param_y_from_value(def, start_val, lane_top, lane_bot, step_qn)
        local y1 = seq_param_y_from_value(def, current_value, lane_top, lane_bot, step_qn)
        r.ImGui_DrawList_AddLine(dl, x0, y0, x1, y1, 0xFFFFFFFF, 2.0)
        r.ImGui_DrawList_AddCircleFilled(dl, x0, y0, 3.0, 0xFFFFFFFF, 12)
        r.ImGui_DrawList_AddCircleFilled(dl, x1, y1, 3.0, 0xFFFFFFFF, 12)
      end

      local value_text
      if drag.reset then
        value_text = string.format("%s reset %s", def.label, string.format(def.fmt, def.default))
      elseif drag.ramp and drag.end_col ~= drag.col then
        value_text = string.format("%s ramp %s -> %s",
          def.label,
          string.format(def.fmt, drag.start_value or def.default),
          string.format(def.fmt, current_value))
      elseif drag.unify then
        value_text = string.format("%s unify %s", def.label, string.format(def.fmt, current_value))
      else
        local hover_active = active_cells[drag.track_id] and active_cells[drag.track_id][mouse_col]
        if hover_active then
          local hit_idx = seq_stutter_hit_index_at_qn(
            hover_active.note, hover_active.abs_qn,
            seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span),
            step_qn
          )
          local hover_val = seq_note_param_value(hover_active.note, def.key, hit_idx)
          value_text = format_seq_param_value(def, hover_val ~= nil and hover_val or current_value)
          if hit_idx then
            value_text = string.format("%s  ·  %d/%d", value_text, hit_idx, seq_stutter_count(hover_active.note))
          end
        else
          value_text = format_seq_param_value(def, current_value)
        end
      end
      local text_x = col_x0(mouse_col) + 4
      local text_y = lane_row.y0 - 16
      local text_size = { r.ImGui_CalcTextSize(ctx, value_text) }
      local text_w = text_size[1] or 0
      local text_h = text_size[2] or 0
      r.ImGui_DrawList_AddRectFilled(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0x000000CC, 3.0)
      r.ImGui_DrawList_AddRect(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0xFFB84DFF, 3.0, 0, 1.0)
      r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, value_text)
      end
    end
  end

  if note_drag_active and state.seq_note_drag and state.seq_note_drag.mode == "stutter_edit" then
    local drag = state.seq_note_drag
    local value_text
    if drag.axis == "skew" then
      value_text = string.format("Skew %+.2f", drag.skew or 0.0)
    elseif drag.axis == "count" then
      value_text = string.format("Stutter ×%d", drag.stutter or 1)
    else
      value_text = "Stutter  ·  drag vertically or horizontally"
    end
    local text_size = { r.ImGui_CalcTextSize(ctx, value_text) }
    local text_w = text_size[1] or 0
    local text_h = text_size[2] or 0
    local text_x = mx + 12
    local text_y = my - 22
    r.ImGui_DrawList_AddRectFilled(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0x000000CC, 3.0)
    r.ImGui_DrawList_AddRect(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0xC9A8FFFF, 3.0, 0, 1.0)
    r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, value_text)
  end

  if note_drag_active and state.seq_note_drag and state.seq_note_drag.mode == "stutter" then
    local drag = state.seq_note_drag
    local count = drag.stutter or SEQ_STUTTER_MIN
    local length_qn = drag.length_qn or step_qn
    local value_text = string.format("Stutter ×%d over %.3g beats", count, length_qn)
    local text_size = { r.ImGui_CalcTextSize(ctx, value_text) }
    local text_w = text_size[1] or 0
    local text_h = text_size[2] or 0
    local text_x = mx + 12
    local text_y = my - 22
    r.ImGui_DrawList_AddRectFilled(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0x000000CC, 3.0)
    r.ImGui_DrawList_AddRect(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0xC9A8FFFF, 3.0, 0, 1.0)
    r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, value_text)
  end

  local decay_readout = nil
  if note_drag_active and state.seq_note_drag and state.seq_note_drag.mode == "decay" then
    local drag = state.seq_note_drag
    if drag.handle == "end" then
      decay_readout = string.format("Length %.3g beats%s", drag.length_qn or 0, is_shift_down() and "  ·  free" or "")
    elseif drag.handle == "curve_in" or drag.handle == "curve_out" then
      local side = (drag.handle == "curve_in") and "in" or "out"
      decay_readout = string.format("Fade %s curve %+.2f  ·  %s", side, drag.fade_curve or 0, seq_fade_shape_name(drag.fade_shape))
    elseif drag.handle == "fade_in" then
      decay_readout = string.format("Fade in %.3g beats  ·  %s", drag.fade_qn or 0, seq_fade_shape_name(drag.fade_shape))
    else
      decay_readout = string.format("Fade out %.3g beats  ·  %s", drag.fade_qn or 0, seq_fade_shape_name(drag.fade_shape))
    end
  elseif seq_is_decay_def(edit_def) and not note_drag_active then
    local hit = seq_decay_hit_at(mx, my)
    if hit and hit.note then
      if hit.kind == "end" then
        decay_readout = string.format("Length %.3g beats", hit.note_len or 0)
      elseif hit.kind == "curve_in" then
        decay_readout = string.format("Fade in curve %+.2f  ·  %s", seq_note_fade_curve(hit.note, "in"), seq_fade_shape_name(seq_note_fade_shape(hit.note, "in")))
      elseif hit.kind == "curve_out" then
        decay_readout = string.format("Fade out curve %+.2f  ·  %s", seq_note_fade_curve(hit.note, "out"), seq_fade_shape_name(seq_note_fade_shape(hit.note, "out")))
      elseif hit.kind == "fade_in" then
        decay_readout = string.format("Fade in %.3g beats  ·  %s", seq_note_fade_qn(hit.note, "in"), seq_fade_shape_name(seq_note_fade_shape(hit.note, "in")))
      else
        decay_readout = string.format("Fade out %.3g beats  ·  %s", seq_note_fade_qn(hit.note, "out"), seq_fade_shape_name(seq_note_fade_shape(hit.note, "out")))
      end
    end
  end
  if decay_readout then
    local text_size = { r.ImGui_CalcTextSize(ctx, decay_readout) }
    local text_w = text_size[1] or 0
    local text_h = text_size[2] or 0
    local text_x = mx + 12
    local text_y = my - 22
    r.ImGui_DrawList_AddRectFilled(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0x000000CC, 3.0)
    r.ImGui_DrawList_AddRect(dl, text_x - 3, text_y - 2, text_x + text_w + 3, text_y + text_h + 2, 0xFFD166FF, 3.0, 0, 1.0)
    r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, decay_readout)
  end

  draw_seq_razors(dl, row_positions, timeline_x0, timeline_x1, view_start_qn, qn_span, step_qn, razor_hover_track_id, razor_hover_qn)

  local mouse_released = r.ImGui_IsMouseReleased(ctx, 0) or r.ImGui_IsMouseReleased(ctx, 1)
  if r.ImGui_IsMouseReleased(ctx, 1) and state.seq_razor_drag and state.seq_razor_drag.mode ~= "move" then
    seq_commit_razor_drag(step_qn)
  end
  if r.ImGui_IsMouseReleased(ctx, 0) and state.seq_razor_drag and state.seq_razor_drag.mode == "move" then
    seq_commit_razor_drag(step_qn)
  end
  if r.ImGui_IsMouseReleased(ctx, 0) and state.seq_region_drag then
    local drag = state.seq_region_drag
    if drag.mode == "move" then
      local reg = get_seq_region_by_id(drag.region_id)
      local swap = drag.swap_region_id and get_seq_region_by_id(drag.swap_region_id)
      if reg and swap then
        local label = begin_seq_undo("Swap sequencer regions")
        if seq_swap_region_positions(reg, swap) then
          seq_select_region(reg)
          region = reg
        end
        end_seq_undo(label)
      elseif reg and drag.preview_start_qn then
        local moved = math.abs((drag.preview_start_qn or 0.0) - (drag.orig_start_qn or 0.0)) >= step_qn * 0.25
        if moved then
          local label = begin_seq_undo(drag.undo_label or "Move sequencer region")
          if seq_move_region_to(reg, drag.preview_start_qn) then
            seq_select_region(reg)
            region = reg
          end
          end_seq_undo(label)
        end
      end
    elseif drag.mode == "pool_copy" then
      local src = get_seq_region_by_id(drag.source_region_id)
      if src and drag.current_start_qn then
        local moved_qn = math.abs(drag.current_start_qn - (src.start_qn or 0.0)) >= step_qn * 0.25
        local moved_px = drag.start_mx and (math.abs(mx - drag.start_mx) > 4 or math.abs(my - drag.start_my) > 4)
        if moved_qn or moved_px then
          local label = begin_seq_undo(drag.undo_label or "Pool copy sequencer region")
          create_seq_region(drag.length_bars or src.length_bars, src, true, drag.insert_qn or drag.current_start_qn, true)
          region = get_selected_seq_region()
          end_seq_undo(label)
        end
      end
    elseif drag.mode == "create" and drag.start_qn and drag.current_qn then
      local create_start = seq_snap_qn_for_region_drag(math.min(drag.start_qn, drag.current_qn), step_qn)
      local create_end = seq_snap_qn_for_region_drag(math.max(drag.start_qn, drag.current_qn), step_qn)
      local moved_px = drag.start_mx and (math.abs(mx - drag.start_mx) > 4 or math.abs(my - drag.start_my) > 4)
      local label = begin_seq_undo(drag.undo_label or "Create sequencer region")
      if not moved_px then
        create_seq_region(4, nil, false, drag.start_qn, drag.insert)
      elseif create_end - create_start < step_qn * 2 then
        create_seq_region(4, nil, false, create_start, drag.insert)
      else
        local bars = seq_qn_length_to_bars(create_start, create_end - create_start)
        create_seq_region(bars, nil, false, create_start, drag.insert)
      end
      region = get_selected_seq_region()
      end_seq_undo(label)
    elseif drag.undo_label and (drag.undo_started or seq_undo_is_open()) then
      end_seq_undo(drag.undo_label)
    end
    state.seq_region_drag = nil
  end
  if mouse_released then
    local note_drag = state.seq_note_drag
    if note_drag then
      if note_drag.dirty then
        if note_drag.mode == "stutter" or note_drag.mode == "stutter_edit"
            or note_drag.mode == "decay" or note_drag.mode == "copy" or note_drag.mode == "move" then
          local seen = {}
          local function sync_one(region_id, track_id)
            local key = tostring(region_id or "") .. ":" .. tostring(track_id or "")
            if seen[key] then
              return
            end
            seen[key] = true
            local sync_region = get_seq_region_by_id(region_id) or region
            local sync_slot = seq_find_slot_by_id(track_id)
            if sync_region and sync_slot then
              sync_seq_pattern_track(sync_region.pattern_id, sync_slot, { force_rebuild = true })
            elseif sync_region then
              sync_seq_pattern_regions(sync_region.pattern_id)
            end
          end
          if note_drag.mode == "copy" or note_drag.mode == "move" then
            state.seq_force_item_crop = true
          end
          sync_one(note_drag.region_id, note_drag.track_id)
          if note_drag.mode == "copy" or note_drag.mode == "move" then
            sync_one(note_drag.dest_region_id, note_drag.dest_track_id)
            state.seq_force_item_crop = nil
          end
        end
        if seq_schedule_ingest_save then
          seq_schedule_ingest_save()
        else
          save_config()
        end
      end
      if note_drag.undo_open then
        local default_label = "Paint sequencer notes"
        if note_drag.mode == "erase" then
          default_label = "Erase sequencer notes"
        elseif note_drag.mode == "stutter" then
          default_label = "Create sequencer stutter"
        elseif note_drag.mode == "stutter_edit" then
          default_label = "Edit sequencer stutter"
        elseif note_drag.mode == "decay" then
          default_label = "Edit sequencer decay"
        elseif note_drag.mode == "copy" then
          default_label = "Copy sequencer note"
        elseif note_drag.mode == "move" then
          default_label = note_drag.place_new and "Insert sequencer note" or "Move sequencer note"
        end
        end_seq_undo(note_drag.undo_label or default_label)
      end
    end
    local param_drag = state.seq_param_drag
    if param_drag then
      if param_drag.lock_click_span and param_drag.reset then
        local param_region = get_seq_region_by_id(param_drag.region_id) or region
        local param_slot = seq_find_slot_by_id(param_drag.track_id)
        if param_region and param_slot then
          local lo, hi = seq_lock_span_cols(
            param_slot, param_drag.col, start_qn, step_qn, step_count, active_cells
          )
          if seq_apply_lock_range(param_region, param_drag.track_id, lo, hi, start_qn, step_qn, false, active_cells) then
            param_drag.dirty = true
          end
        end
      end
      if param_drag.param == "vary_filter" then
        local param_region = get_seq_region_by_id(param_drag.region_id) or region
        local param_slot = seq_find_slot_by_id(param_drag.track_id)
        if param_drag.reset then
          if param_drag.filter_click_span and param_region and param_slot then
            local lo, hi = seq_vary_filter_span_cols(
              param_slot, param_drag.col, start_qn, step_qn, step_count
            )
            if seq_apply_vary_filter_range(param_region, param_drag.track_id, lo, hi, start_qn, step_qn, "") then
              param_drag.dirty = true
            end
          end
        elseif param_slot and param_region then
          local col_min = math.min(param_drag.col or 0, param_drag.end_col or param_drag.col or 0)
          local col_max = math.max(param_drag.col or 0, param_drag.end_col or param_drag.col or 0)
          if param_drag.filter_click_span then
            local lo, hi = seq_vary_filter_span_cols(
              param_slot, param_drag.col, start_qn, step_qn, step_count
            )
            local text = seq_visible_cell_vary_filter(param_slot, param_drag.col, start_qn, step_qn) or ""
            seq_begin_vary_filter_edit(param_region, param_drag.track_id, lo, hi, start_qn, step_qn, text, text)
          elseif state.seq_vary_filter_edit then
            local edit = state.seq_vary_filter_edit
            edit.col_min = col_min
            edit.col_max = col_max
            edit.start_qn = start_qn
            edit.step_qn = step_qn
            edit.focus = true
          else
            seq_begin_vary_filter_edit(param_region, param_drag.track_id, col_min, col_max, start_qn, step_qn, "", nil)
          end
        end
      end
      if param_drag.dirty then
        local param_region = get_seq_region_by_id(param_drag.region_id) or region
        local param_slot = seq_find_slot_by_id(param_drag.track_id)
        if param_region and param_slot then
          sync_seq_pattern_track(param_region.pattern_id, param_slot, { force_rebuild = true })
        elseif param_region then
          sync_seq_pattern_regions(param_region.pattern_id)
        end
        if seq_schedule_ingest_save then
          seq_schedule_ingest_save()
        else
          save_config()
        end
      end
      if param_drag.undo_open then
        end_seq_undo(param_drag.undo_label or "Edit sequencer parameter")
      end
    end
    state.seq_note_drag = nil
    state.seq_param_drag = nil
  end

  for _, row_pos in ipairs(row_positions) do
    local row = row_pos.row
    if row.type == "note" and row.slot then
      local track_idx = slot_id_to_idx[row.slot.id]
      if track_idx and row_pos.ctrl then
        local mix_changed, overlap_changed, mix_hovered = render_seq_track_mix_controls(
          dl, row.slot, row_pos.ctrl
        )
        if mix_hovered then
          over_lane_mix_controls = true
        end
        if mix_changed then
          begin_seq_undo("Adjust sequencer mix")
          seq_undo_commit_on_release = true
          seq_on_slot_mix_changed(row.slot, { resync = overlap_changed })
        end
      end
    end
  end

  render_seq_track_context_menu()
  if render_seq_midi_assign_popup() then
    save_config()
    if save_seq_project_state then save_seq_project_state() end
  end

  seq_random_flyout_begin_frame("lane")
  if not random_edit_region and state.seq_random_flyout and state.seq_random_flyout.host == "lane" then
    state.seq_random_flyout = nil
  end
  for _, row_pos in ipairs(row_positions) do
    local row = row_pos.row
    if row_pos.visible and row.type == "note" and row.slot then
      local track_idx = slot_id_to_idx[row.slot.id]
      if track_idx then
        if random_edit_region and random_edit_pattern then
          local random_settings = get_seq_track_settings(random_edit_pattern, row.slot.id, true)
          if random_settings then
            local changed, active_key, overlay_text, panel_x1, reseeded = seq_render_lane_random_controls(dl, row_pos, row.slot.id, random_settings, random_focus_effective, timeline_x0, header_y1, body_viewport_y1)
            if active_key then
              random_focus_next = active_key
              random_focus_effective = active_key
              random_overlay_text = overlay_text
              random_overlay_y = row_pos.y0
              random_overlay_x = panel_x1
            end
            if reseeded or changed then
              seq_queue_random_sync(random_edit_region.pattern_id, row.slot.id)
            end
            if changed then
              begin_seq_undo("Edit sequencer random")
              seq_undo_commit_on_release = true
            end
          end
        end
        local lane_h = row_pos.y1 - row_pos.y0
        r.ImGui_SetCursorScreenPos(ctx, timeline_x0 - map_nav_w - 4, row_pos.y0)
        r.ImGui_PushID(ctx, "seq_lane_nav_" .. row.slot.id)
        local nav = render_seq_track_sample_controls(row.slot, track_idx, {
          id_suffix = "seq_map_" .. row.slot.id,
          ctrl_size = map_ctrl_size,
          icon_size = map_icon_size,
          container_h = lane_h,
          y0 = row_pos.y0,
          y1 = row_pos.y1,
        })
        r.ImGui_PopID(ctx)
        if state.pending_waveform_drop or sample_drag_active() then
          if not seq_candidate_drag_from_slot(row.slot) then
          local row_drop_hovered = nav.row_drop_hovered
          if not row_drop_hovered and hovered and mx >= x0 and mx < timeline_x0
              and my >= row_pos.y0 and my <= row_pos.y1 then
            row_drop_hovered = true
          end
          if row_drop_hovered and not state.seq_candidate_drop and not state.seq_drum_drop
              and not seq_drag_is_from_candidate() then
            state.seq_drop_target_idx = track_idx
            state.seq_timeline_drop_time = nil
            state.seq_timeline_drop_track_idx = nil
            draw_drop_target_highlight(dl, x0 + 1, row_pos.y0, timeline_x0 - 1, row_pos.y1, 3)
          end
          end
        end
      end
    end
  end

  if mix_env_resync then
    -- Rebuild take envelopes after the drag frame so we don't resync every pixel.
    if not (state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id) then
      local slot = env_resync_slot
      if not slot and state.seq_env_pending_resync_slot_id then
        slot = seq_find_slot_by_id(state.seq_env_pending_resync_slot_id)
      end
      if slot then
        sync_seq_slot_all_regions(slot, { force_rebuild = true })
      else
        seq_resync_all_regions()
      end
      state.seq_env_pending_resync = nil
      state.seq_env_pending_resync_slot_id = nil
    else
      state.seq_env_pending_resync = true
    end
  elseif state.seq_env_pending_resync
      and not (state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id) then
    local slot = nil
    if state.seq_env_pending_resync_slot_id then
      slot = seq_find_slot_by_id(state.seq_env_pending_resync_slot_id)
    end
    if slot then
      sync_seq_slot_all_regions(slot, { force_rebuild = true })
    else
      seq_resync_all_regions()
    end
    state.seq_env_pending_resync = nil
    state.seq_env_pending_resync_slot_id = nil
  end

  state.seq_random_active_key = random_focus_next
  if not random_edit_region then
    state.seq_random_active_key = nil
  end
  if random_overlay_text and random_overlay_y then
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, random_overlay_text)
    local text_x = (random_overlay_x or (timeline_x0 + 8)) + 8
    local text_y = random_overlay_y + 2
    r.ImGui_DrawList_AddRectFilled(dl, text_x - 3, text_y - 2, text_x + text_w + 4, text_y + text_h + 2, 0x000000CC, 3.0)
    r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFE7A6DD, random_overlay_text)
  end

  if mouse_released or (state.seq_random_sync_pending and not state.seq_random_knob_drag) then
    state.seq_random_sync_run = true
  end
  if mouse_released and seq_undo_commit_on_release then
    if seq_undo_is_open() then
      end_seq_undo()
    end
    seq_undo_commit_on_release = false
  end

  r.ImGui_SetCursorScreenPos(ctx, x0, add_row_y0)
  if draw_ui_button("seq_add_track_popup_open_sequencer", nil, label_col_w, add_track_row_h, { icon = "plus", style = "primary" }) then
    open_seq_add_track_popup()
  end

  r.ImGui_Dummy(ctx, width, 0)

  render_seq_add_track_popup()
  r.ImGui_EndChild(ctx)

  -- Envelope editor + extras flyouts must live in the parent map window.
  -- Opening them inside the tracks child made ImGui treat the screen-space
  -- anchor as child-relative, so the editor jumped to a random place.
  seq_render_env_editor_host()
  if seq_undo_commit_on_release and r.ImGui_IsMouseReleased and
      (r.ImGui_IsMouseReleased(ctx, 0) or r.ImGui_IsMouseReleased(ctx, 1)) then
    if seq_undo_is_open() then
      end_seq_undo()
    end
    seq_undo_commit_on_release = false
  end

  -- Flyout items must live in the parent map window. The tracks child clips
  -- mouse hits, so extras that overlap the pinned ruler would otherwise be inert.
  if random_edit_region and random_edit_pattern then
    local fly_slot = state.seq_random_flyout and state.seq_random_flyout.slot_id
    if seq_render_random_flyout(dl, random_edit_pattern, "lane") then
      begin_seq_undo("Edit sequencer random extras")
      seq_undo_commit_on_release = true
      seq_queue_random_sync(random_edit_region.pattern_id, fly_slot)
    end
    if r.ImGui_IsMouseReleased(ctx, 0) or r.ImGui_IsMouseReleased(ctx, 1) then
      if state.seq_random_sync_pending and not state.seq_random_knob_drag then
        state.seq_random_sync_run = true
      end
      if seq_undo_commit_on_release then
        if seq_undo_is_open() then
          end_seq_undo()
        end
        seq_undo_commit_on_release = false
      end
    end
  end

  render_seq_pattern_popup(region)
  r.ImGui_Dummy(ctx, 0, 0)
  r.ImGui_EndChild(ctx)
  seq_stem_import_accept_file_drop()
  seq_stem_import_draw_overlay(dl, x0, y0, x0 + width, body_viewport_y1 or (y0 + 120))
end

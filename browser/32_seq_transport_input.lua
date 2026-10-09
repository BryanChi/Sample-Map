-- Sample Map Browser module: seq_transport_input
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_zoom_to_region(reg)
  if not reg then
    return
  end
  state.seq_view_start_qn = reg.start_qn or 0.0
  state.seq_view_span_qn = get_seq_region_length_qn(reg)
  seq_timeline_scroll_stop()
  if state.seq_follow_arrange then
    state.seq_drive_arrange = true
    seq_push_view_to_arrange()
  end
  save_config()
end

function seq_get_playhead_time()
  local play_state = r.GetPlayState and r.GetPlayState() or 0
  if play_state & 1 == 1 and r.GetPlayPosition then
    return r.GetPlayPosition()
  end
  if r.GetCursorPosition then
    return r.GetCursorPosition()
  end
  return nil
end

function seq_set_playhead_qn(qn)
  if type(qn) ~= "number" then
    return
  end
  local time_pos = qn_to_time(qn)
  if type(time_pos) ~= "number" then
    return
  end
  if r.SetEditCurPos then
    r.SetEditCurPos(time_pos, true, true)
  elseif r.SetEditCurPos2 then
    r.SetEditCurPos2(0, time_pos, true, true)
  end
end

function imgui_text_input_active()
  if state.seq_vary_filter_edit or state.seq_region_rename then
    return true
  end
  if state._text_input_item_active then
    return true
  end
  if r.ImGui_GetIO then
    local io = r.ImGui_GetIO(ctx)
    if io then
      local want = io.WantTextInput
      if type(want) == "function" then
        want = want(io)
      end
      if want == true or want == 1 then
        return true
      end
    end
  end
  return false
end

function seq_mark_text_input_item()
  if not ctx then
    return
  end
  local active = (r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx))
    or (r.ImGui_IsItemFocused and r.ImGui_IsItemFocused(ctx))
  if active then
    state._text_input_item_active = true
    state._text_input_item_active_now = true
  end
end

-- True while any ImGui popup is open (kit randomize, groove, add-track, etc.).
-- Sequencer uses raw mouse geometry, so it must ignore clicks while popups own input.
function seq_layering_blocks_input()
  if not state.seq_layering_slot_id then
    return false
  end
  if state.pending_waveform_drop then
    return false
  end
  if state.seq_layering_hovered or state.seq_layering_drag
      or state.seq_layering_vol_drag or state.seq_layering_bias_drag then
    return true
  end
  local rect = state.seq_layering_rect
  if rect and r.ImGui_GetMousePos then
    local mx, my = r.ImGui_GetMousePos(ctx)
    mx, my = tonumber(mx), tonumber(my)
    if mx and my
        and mx >= (rect.x or 0) and my >= (rect.y or 0)
        and mx <= (rect.x or 0) + (rect.w or 0)
        and my <= (rect.y or 0) + (rect.h or 0) then
      return true
    end
  end
  return false
end

function imgui_any_popup_open()
  if seq_layering_blocks_input() then
    return true
  end
  if state.seq_region_rename then
    return true
  end
  if state.seq_neighbor_popup and state.seq_neighbor_popup.hovered then
    return true
  end
  if state.seq_minimap_popup and state.seq_minimap_popup.hovered then
    return true
  end
  if state.preview_history_popup and state.preview_history_popup.hovered then
    return true
  end
  if state.seq_env_popup_slot_id then
    return true
  end
  if r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopup then
    return r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopup())
  end
  if not r.ImGui_IsPopupOpen then
    return false
  end
  return r.ImGui_IsPopupOpen(ctx, "seq_kit_random_popup")
      or r.ImGui_IsPopupOpen(ctx, "seq_groove_popup")
      or r.ImGui_IsPopupOpen(ctx, "seq_add_track_popup")
      or r.ImGui_IsPopupOpen(ctx, "##seq_track_context_menu")
      or r.ImGui_IsPopupOpen(ctx, "seq_pattern_variations_popup")
      or r.ImGui_IsPopupOpen(ctx, "seq_env_editor_popup")
      or r.ImGui_IsPopupOpen(ctx, "seq_region_random_popup")
      or r.ImGui_IsPopupOpen(ctx, "tag_color_picker")
      or r.ImGui_IsPopupOpen(ctx, "select_tag_preset")
      or r.ImGui_IsPopupOpen(ctx, "save_tag_preset")
end

function handle_script_keyboard_shortcuts()
  if state.shortcut_capture_id then
    if not state.settings_open then
      state.shortcut_capture_id = nil
      return
    end
    seq_capture_shortcut_key()
    local key = shortcut_poll_pressed_key()
    if key then
      shortcut_assign(state.shortcut_capture_id, shortcut_spec_from_press(key))
      state.shortcut_capture_id = nil
      state.shortcut_capture_click_cancel = false
    end
    return
  end
  if handle_seq_undo_keys() then
    return
  end
  if imgui_text_input_active() then
    if state.seq_vary_filter_edit and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      seq_cancel_vary_filter_edit()
    end
    return
  end
  if shortcut_pressed("play_stop") then
    r.Main_OnCommand(40044, 0)
  end
  handle_seq_note_edit_mode_keys()
  handle_seq_playback_and_split_keys()
  handle_map_arrow_keys()
end

function seq_unpool_region(region, opts)
  if not region then
    return
  end
  opts = opts or {}
  local own = (not opts.skip_undo) and seq_undo_own_begin("Unlink sequencer region")
  local old_pattern_id = region.pattern_id
  local old_pattern = get_seq_pattern(old_pattern_id, false)
  local new_pattern_id = alloc_seq_pattern()
  state.seq_patterns[tostring(new_pattern_id)] = clone_table_deep(old_pattern or { notes = {} })
  region.pattern_id = new_pattern_id
  region.pool_id = alloc_seq_pool()
  save_config()
  local item = region.parent_item_guid and seq_find_item_by_guid(region.parent_item_guid)
  if item then
    seq_write_parent_item_ext(item, region)
  end
  if opts.skip_sync then
    for _, slot in ipairs(state.seq_tracks or {}) do
      local tr = get_seq_slot_target_track(slot)
      if tr then
        for i = 0, r.CountTrackMediaItems(tr) - 1 do
          local it = r.GetTrackMediaItem(tr, i)
          if it and seq_item_is_owned(it, region.id) then
            set_item_ext(it, SEQ_EXT_PATTERN, region.pattern_id)
            set_item_ext(it, SEQ_EXT_POOL, region.pool_id)
          end
        end
      end
    end
  else
    sync_seq_region(region)
    if old_pattern_id then
      sync_seq_pattern_regions(old_pattern_id)
    end
  end
  if own then
    end_seq_undo("Unlink sequencer region")
  end
end

function seq_delete_region_by_id(region_id)
  state.selected_seq_region_id = region_id
  delete_selected_seq_region()
end

function seq_region_containing_qn(qn, ignore_id)
  qn = qn or 0.0
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id then
      local reg_start = reg.start_qn or 0.0
      local reg_end = reg_start + get_seq_region_length_qn(reg)
      if qn >= reg_start - 0.000001 and qn < reg_end - 0.000001 then
        return reg
      end
    end
  end
  return nil
end

function seq_region_insert_qn(hover_qn, ignore_id)
  hover_qn = math.max(0.0, hover_qn or 0.0)
  local inside = seq_region_containing_qn(hover_qn, ignore_id)
  if inside then
    return inside.start_qn or 0.0, inside
  end
  local prev_end, next_reg = nil, nil
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id then
      local reg_start = reg.start_qn or 0.0
      local reg_end = reg_start + get_seq_region_length_qn(reg)
      if reg_end <= hover_qn + 0.000001 and (not prev_end or reg_end > prev_end) then
        prev_end = reg_end
      end
      if reg_start >= hover_qn - 0.000001 and (not next_reg or reg_start < (next_reg.start_qn or 0.0)) then
        next_reg = reg
      end
    end
  end
  local four_qn = 16.0
  if prev_end then
    four_qn = get_seq_region_length_qn({ start_qn = prev_end, length_bars = 4 })
  elseif next_reg then
    four_qn = get_seq_region_length_qn({ start_qn = next_reg.start_qn or 0.0, length_bars = 4 })
  end
  if next_reg and ((next_reg.start_qn or 0.0) - hover_qn) <= four_qn + 0.000001 then
    return next_reg.start_qn or 0.0, next_reg
  end
  if prev_end and (hover_qn - prev_end) <= four_qn + 0.000001 then
    return prev_end, nil
  end
  return hover_qn, nil
end

function seq_shift_regions_from(from_qn, delta_qn, ignore_id)
  from_qn = from_qn or 0.0
  delta_qn = delta_qn or 0.0
  if math.abs(delta_qn) < 0.000001 then
    return false
  end
  local affected = {}
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id and (reg.start_qn or 0.0) >= from_qn - 0.000001 then
      table.insert(affected, reg)
    end
  end
  if #affected == 0 then
    return false
  end
  for _, reg in ipairs(affected) do
    remove_seq_rendered_items(reg)
    reg.start_qn = (reg.start_qn or 0.0) + delta_qn
  end
  sort_seq_regions()
  for _, reg in ipairs(affected) do
    sync_seq_region(reg)
  end
  return true
end

function seq_pack_overlapping_regions()
  sort_seq_regions()
  local changed = false
  for i = 2, #(state.seq_regions or {}) do
    local prev = state.seq_regions[i - 1]
    local cur = state.seq_regions[i]
    local prev_end = (prev.start_qn or 0.0) + get_seq_region_length_qn(prev)
    if (cur.start_qn or 0.0) < prev_end - 0.000001 then
      remove_seq_rendered_items(cur)
      cur.start_qn = prev_end
      sync_seq_region(cur)
      changed = true
    end
  end
  return changed
end

-- After an arrange edit, keep the edited region(s) pinned to the user's drop
-- position and push any overlapping *other* regions out of the way. The old
-- pack-all path moved the edited region itself, then sync yanked the parent
-- item away from where it was dropped.
function seq_evict_overlaps_keeping(keep_regions)
  local keep = {}
  for _, reg in ipairs(keep_regions or {}) do
    if reg and reg.id ~= nil then
      keep[reg.id] = true
    end
  end
  if next(keep) == nil then
    return false
  end
  local changed = false
  for _ = 1, 64 do
    sort_seq_regions()
    local moved = false
    local regs = state.seq_regions or {}
    for i = 1, #regs do
      local a = regs[i]
      local a_start = a.start_qn or 0.0
      local a_end = a_start + get_seq_region_length_qn(a)
      for j = i + 1, #regs do
        local b = regs[j]
        local b_start = b.start_qn or 0.0
        local b_end = b_start + get_seq_region_length_qn(b)
        if a_start < b_end - 1e-4 and a_end > b_start + 1e-4 then
          local victim, anchor_end
          if keep[a.id] and not keep[b.id] then
            victim, anchor_end = b, a_end
          elseif keep[b.id] and not keep[a.id] then
            victim, anchor_end = a, b_end
          elseif not keep[a.id] and not keep[b.id] then
            -- Neither was arrange-edited: classic pack (later moves).
            victim, anchor_end = b, a_end
          else
            -- Both pinned from a multi-select arrange move: leave alone.
            victim = nil
          end
          if victim and math.abs((victim.start_qn or 0.0) - anchor_end) > 1e-4 then
            remove_seq_rendered_items(victim)
            victim.start_qn = math.max(0.0, anchor_end)
            sync_seq_region(victim)
            moved = true
            changed = true
            break
          end
        end
      end
      if moved then
        break
      end
    end
    if not moved then
      break
    end
  end
  sort_seq_regions()
  return changed
end

function seq_swap_region_positions(a, b)
  if not a or not b or a.id == b.id then
    return false
  end
  local a_start = a.start_qn or 0.0
  local b_start = b.start_qn or 0.0
  if math.abs(a_start - b_start) < 0.000001 then
    return false
  end
  remove_seq_rendered_items(a)
  remove_seq_rendered_items(b)
  a.start_qn = b_start
  b.start_qn = a_start
  sort_seq_regions()
  seq_pack_overlapping_regions()
  save_config()
  sync_seq_region(a)
  sync_seq_region(b)
  return true
end

function seq_draw_region_ghost(dl, start_qn, end_qn, y0, h, timeline_x0, timeline_w, qn_to_x, fill, edge, label)
  if not dl or not qn_to_x then
    return
  end
  local gx0 = math.max(timeline_x0, qn_to_x(start_qn or 0.0))
  local gx1 = math.min(timeline_x0 + timeline_w, qn_to_x(end_qn or start_qn or 0.0))
  if gx1 <= gx0 + 1.0 then
    return
  end
  r.ImGui_DrawList_AddRectFilled(dl, gx0 + 1, y0 + 3, gx1 - 1, y0 + h - 3, fill or 0x4A8BD688, 4.0)
  r.ImGui_DrawList_AddRect(dl, gx0 + 1, y0 + 3, gx1 - 1, y0 + h - 3, edge or 0x4A8BD6FF, 4.0, 0, 1.4)
  if label and label ~= "" then
    local tw = select(1, r.ImGui_CalcTextSize(ctx, label)) or 24.0
    if gx1 - gx0 > tw + 10.0 then
      r.ImGui_DrawList_AddText(dl, gx0 + 6, y0 + 5, 0xFFFFFFFF, label)
    end
  end
end

function seq_move_region_to(region, desired_start_qn)
  if not region then
    return false
  end
  local length_qn = get_seq_region_length_qn(region)
  desired_start_qn = math.max(0.0, desired_start_qn)
  local delta = desired_start_qn - (region.start_qn or 0.0)
  local old_start = region.start_qn or 0.0
  local new_start
  if delta < 0 then
    new_start = find_prev_non_overlapping_region_start(desired_start_qn, length_qn, region.id)
  else
    new_start = find_non_overlapping_region_start(desired_start_qn, length_qn, region.id)
  end
  if math.abs(new_start - (region.start_qn or 0.0)) < 0.000001 then
    return false
  end
  remove_seq_rendered_items(region)
  region.start_qn = new_start
  sort_seq_regions()
  save_config()
  sync_seq_region(region)
  return true
end

function seq_resize_region_end(region, new_end_qn, step_qn)
  if not region then
    return false
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local req_end = new_end_qn
  new_end_qn = seq_snap_qn_for_region_drag(new_end_qn, step_qn)
  local reg_start = region.start_qn or 0.0
  local old_bars = region.length_bars
  local old_len = get_seq_region_length_qn(region)
  new_end_qn = math.max(new_end_qn, reg_start + step_qn)
  local clipped_by = nil
  for _, other in ipairs(state.seq_regions) do
    if other.id ~= region.id then
      local other_start = other.start_qn or 0.0
      if other_start > reg_start and other_start < new_end_qn then
        new_end_qn = other_start
        clipped_by = other.id
      end
    end
  end
  local length_qn = new_end_qn - reg_start
  if length_qn < step_qn then
    return false
  end
  local bars = seq_qn_length_to_bars(reg_start, length_qn)
  if bars == region.length_bars then
    return false
  end
  remove_seq_rendered_items(region)
  region.length_bars = bars
  save_config()
  sync_seq_region(region)
  return true
end

function seq_resize_region_start(region, new_start_qn, step_qn)
  if not region then
    return false
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local req_start = new_start_qn
  local reg_end = (region.start_qn or 0.0) + get_seq_region_length_qn(region)
  local old_start = region.start_qn or 0.0
  local old_bars = region.length_bars
  new_start_qn = seq_snap_qn_for_region_drag(math.max(0.0, new_start_qn), step_qn)
  new_start_qn = math.min(new_start_qn, reg_end - step_qn)
  local clipped_by = nil
  for _, other in ipairs(state.seq_regions) do
    if other.id ~= region.id then
      local other_end = (other.start_qn or 0.0) + get_seq_region_length_qn(other)
      if other_end > new_start_qn and other_end <= reg_end then
        new_start_qn = math.max(new_start_qn, other_end)
        clipped_by = other.id
      end
    end
  end
  local length_qn = reg_end - new_start_qn
  if length_qn < step_qn then
    return false
  end
  local bars = seq_qn_length_to_bars(new_start_qn, length_qn)
  if math.abs(new_start_qn - (region.start_qn or 0.0)) < 0.000001 and bars == region.length_bars then
    return false
  end
  remove_seq_rendered_items(region)
  region.start_qn = new_start_qn
  region.length_bars = bars
  sort_seq_regions()
  save_config()
  sync_seq_region(region)
  return true
end

function seq_split_qn_for_region(region, split_qn, step_qn)
  if not region then
    return nil
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  split_qn = seq_snap_qn_to_bar(split_qn, step_qn)
  local reg_start = region.start_qn or 0.0
  local reg_end = reg_start + get_seq_region_length_qn(region)
  if split_qn <= reg_start + 0.0001 or split_qn >= reg_end - 0.0001 then
    return nil
  end
  local left_bars = seq_qn_length_to_bars(reg_start, split_qn - reg_start)
  local right_bars = seq_qn_length_to_bars(split_qn, reg_end - split_qn)
  if left_bars < 1 or right_bars < 1 then
    return nil
  end
  local left_len = get_seq_region_length_qn({ start_qn = reg_start, length_bars = left_bars })
  local right_len = get_seq_region_length_qn({ start_qn = split_qn, length_bars = right_bars })
  if left_len < step_qn or right_len < step_qn then
    return nil
  end
  return split_qn, left_bars, right_bars
end

function seq_remap_pattern_notes_from_step(pattern, split_step, grid_qn)
  if not pattern or type(pattern.notes) ~= "table" then
    return
  end
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  local split_qn = split_step * grid_qn
  for track_id, notes in pairs(pattern.notes) do
    if type(notes) == "table" then
      local remapped = {}
      for step_key, note in pairs(notes) do
        if type(note) == "table" then
          local qn = seq_note_qn_offset(note, step_key, grid_qn)
          if qn >= split_qn - 1e-9 then
            local new_note = clone_table_deep(note)
            new_note.qn_offset = qn - split_qn
            new_note.step = math.floor((new_note.qn_offset / grid_qn) + 1e-9)
            remapped[seq_storage_key_from_qn(new_note.qn_offset)] = new_note
          end
        end
      end
      pattern.notes[track_id] = remapped
    end
  end
end

function seq_prune_pattern_notes_from_step(pattern, split_step, grid_qn)
  if not pattern or type(pattern.notes) ~= "table" then
    return
  end
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  local split_qn = split_step * grid_qn
  for _, notes in pairs(pattern.notes) do
    if type(notes) == "table" then
      for step_key, note in pairs(notes) do
        local qn = seq_note_qn_offset(note, step_key, grid_qn)
        if qn >= split_qn - 1e-9 then
          notes[step_key] = nil
        end
      end
    end
  end
end

function seq_split_region(region, split_qn, step_qn)
  local snapped_qn, left_bars, right_bars = seq_split_qn_for_region(region, split_qn, step_qn)
  if not snapped_qn then
    return nil
  end
  local own = seq_undo_own_begin("Split sequencer region")
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local grid_qn = state.seq_grid_qn or 0.25
  local split_step = math.max(1, math.floor(((snapped_qn - (region.start_qn or 0.0)) / grid_qn) + 0.5))
  local linked = seq_region_is_linked(region) and true or false
  local src_pattern = get_seq_pattern(region.pattern_id, false)
  local note_count_before = 0
  if src_pattern and type(src_pattern.notes) == "table" then
    for _, notes in pairs(src_pattern.notes) do
      if type(notes) == "table" then
        for _ in pairs(notes) do note_count_before = note_count_before + 1 end
      end
    end
  end

  local new_pattern_id = alloc_seq_pattern()
  local cloned = clone_table_deep(src_pattern or { notes = {} })
  seq_remap_pattern_notes_from_step(cloned, split_step, grid_qn)
  state.seq_patterns[tostring(new_pattern_id)] = cloned

  if not linked then
    seq_prune_pattern_notes_from_step(src_pattern, split_step, grid_qn)
  end

  remove_seq_rendered_items(region)
  local old_bars = region.length_bars
  region.length_bars = left_bars

  local right = {
    id = state.seq_region_next_id,
    name = seq_auto_name_new_region(snapped_qn, region.id),
    start_qn = snapped_qn,
    length_bars = right_bars,
    pool_id = alloc_seq_pool(),
    pattern_id = new_pattern_id,
    style_key = region.style_key,
    style_source = region.style_source,
    kit_genres = region.kit_genres and clone_table_deep(region.kit_genres) or nil,
    groove = normalize_seq_groove(region.groove),
    track_samples = seq_clone_region_track_samples(region),
  }
  state.seq_region_next_id = state.seq_region_next_id + 1
  table.insert(state.seq_regions, right)
  sort_seq_regions()
  save_config()
  sync_seq_region(region)
  sync_seq_region(right)
  if own then
    end_seq_undo("Split sequencer region")
  end
  return right
end

function seq_draw_link_icon(dl, icon_x0, icon_y0, color, hovered)
  local sz = SEQ_LINK_ICON_SIZE
  if hovered then
    local pad = 2.0
    r.ImGui_DrawList_AddRectFilled(dl, icon_x0 - pad, icon_y0 - pad, icon_x0 + sz + pad, icon_y0 + sz + pad, 0xFFFFFF22, 3.0)
    color = 0xF2F7FCDD
  else
    color = 0xE4EEF698
  end
  local img = get_vfx_icon("Link")
  if img and r.ImGui_DrawList_AddImage then
    if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(img, "ImGui_Image*") then
      vfx_icon_images.attached_ctx = nil
      img = get_vfx_icon("Link")
    end
    if img then
      r.ImGui_DrawList_AddImage(dl, img, icon_x0, icon_y0, icon_x0 + sz, icon_y0 + sz, nil, nil, nil, nil, color)
      return
    end
  end
  local cx0 = icon_x0 + 2.5
  local cy = icon_y0 + sz * 0.5
  local cx1 = icon_x0 + sz - 2.5
  r.ImGui_DrawList_AddCircle(dl, cx0, cy, 2.2, color, 10, 1.1)
  r.ImGui_DrawList_AddCircle(dl, cx1, cy, 2.2, color, 10, 1.1)
  r.ImGui_DrawList_AddLine(dl, cx0 + 1.6, cy, cx1 - 1.6, cy, color, 1.1)
end

function seq_hit_test_region_at(mx, my, y0, region_lane_h, timeline_x0, timeline_w, start_qn, qn_span, qn_to_x_fn)
  if my < y0 or my > y0 + region_lane_h or mx < timeline_x0 or mx > timeline_x0 + timeline_w then
    return nil
  end
  local clicked_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, start_qn, qn_span)
  for i = #state.seq_regions, 1, -1 do
    local reg = state.seq_regions[i]
    local reg_start = reg.start_qn or 0.0
    local reg_end = reg_start + get_seq_region_length_qn(reg)
    if clicked_qn >= reg_start and clicked_qn <= reg_end then
      local raw_rx0 = qn_to_x_fn(reg_start)
      local raw_rx1 = qn_to_x_fn(reg_end)
      local rx0 = math.max(timeline_x0, raw_rx0)
      local rx1 = math.min(timeline_x0 + timeline_w, raw_rx1)
      if seq_region_is_linked(reg) and (rx1 - rx0) >= (SEQ_LINK_ICON_SIZE + SEQ_LINK_HIT_PAD * 2 + 8) then
        local icon_x0, icon_y0, icon_x1, icon_y1 = seq_region_link_hit_rect(rx0, y0, region_lane_h)
        if mx >= icon_x0 and mx <= icon_x1 and my >= icon_y0 and my <= icon_y1 then
          return { region = reg, part = "link" }
        end
      end
      local _, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after = seq_collect_region_random_entries(reg)
      if has_prob or has_human or has_vel or has_vary or has_stut or has_ghost then
        local vis_x0 = rx0
        if seq_region_is_linked(reg) and (rx1 - rx0) >= (SEQ_LINK_ICON_SIZE + SEQ_LINK_HIT_PAD * 2 + 8) then
          vis_x0 = rx0 + SEQ_LINK_ICON_SIZE + SEQ_LINK_HIT_PAD + 8
        end
        local vis_x1 = rx1
        local labels = seq_region_random_label_layout(vis_x0, vis_x1, y0, region_lane_h, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after)
        for _, lab in ipairs(labels) do
          if mx >= lab.x0 and mx <= lab.x1 and my >= lab.y0 and my <= lab.y1 then
            local part = "rand_human"
            if lab.kind == "all" then
              part = "rand_all"
            elseif lab.kind == "prob" then
              part = "rand_prob"
            elseif lab.kind == "vel" then
              part = "rand_vel"
            elseif lab.kind == "vary" then
              part = "rand_vary"
            elseif lab.kind == "stut" then
              part = "rand_stut"
            elseif lab.kind == "grace" then
              part = "rand_grace"
            elseif lab.kind == "after" then
              part = "rand_after"
            elseif lab.kind == "ghost" then
              part = "rand_ghost"
            end
            return { region = reg, part = part }
          end
        end
      end
      if mx - raw_rx0 <= SEQ_REGION_EDGE_PX then
        return { region = reg, part = "left_edge" }
      elseif raw_rx1 - mx <= SEQ_REGION_EDGE_PX then
        return { region = reg, part = "right_edge" }
      end
      return { region = reg, part = "body" }
    end
  end
  return nil
end

function seq_get_default_create_region_qn(hover_qn, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  hover_qn = seq_snap_qn_for_region_drag(hover_qn or 0.0, step_qn)

  local create_start_qn, next_reg = seq_region_insert_qn(hover_qn, nil)
  local create_length_qn = get_seq_region_length_qn({ start_qn = create_start_qn, length_bars = 4 })
  local insert = next_reg ~= nil or seq_region_overlaps(create_start_qn, create_length_qn, nil)
  if not insert then
    create_start_qn = find_non_overlapping_region_start(create_start_qn, create_length_qn, nil)
  end
  return create_start_qn, create_length_qn, insert
end

function seq_region_is_linked(reg)
  if not reg then
    return false
  end
  if seq_region_pool_count(reg.pool_id) > 1 then
    return true
  end
  for _, other in ipairs(state.seq_regions) do
    if other.id ~= reg.id and other.pattern_id == reg.pattern_id then
      return true
    end
  end
  return false
end

function seq_region_in_link_group(reg, hover)
  if not reg or not hover then
    return false
  end
  if seq_region_pool_count(hover.pool_id) > 1
      and tonumber(reg.pool_id) == tonumber(hover.pool_id) then
    return true
  end
  if hover.pattern_id and reg.pattern_id == hover.pattern_id and seq_region_is_linked(hover) then
    return true
  end
  return false
end

function seq_linked_region_names(region)
  local names = {}
  if not region then
    return names
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= region.id and seq_region_in_link_group(reg, region) then
      names[#names + 1] = (reg.name and reg.name ~= "" and reg.name) or ("Region " .. tostring(reg.id))
    end
  end
  return names
end

function seq_mouse_over_script_ui()
  if not r.ImGui_IsWindowHovered then
    return false
  end
  local flags = 0
  if r.ImGui_HoveredFlags_AnyWindow then
    flags = r.ImGui_HoveredFlags_AnyWindow()
  elseif r.ImGui_HoveredFlags_RootAndChildWindows then
    flags = r.ImGui_HoveredFlags_RootAndChildWindows()
  end
  return r.ImGui_IsWindowHovered(ctx, flags)
end

function seq_region_from_arrange_parent_geometry()
  if not r.GetMousePosition then
    return nil
  end
  local mx, my = r.GetMousePosition()
  local geo = seq_get_arrange_geometry()
  if not geo or not geo.l then
    return nil
  end
  if mx < geo.l or mx > geo.r or my < geo.t or my > geo.b then
    return nil
  end
  local t0, t1 = get_arrange_view_range()
  if not t0 or not t1 or t1 <= t0 then
    return nil
  end
  local view_w = geo.r - geo.l
  if view_w < 4 then
    return nil
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    local item = reg.parent_item_guid and seq_find_item_by_guid(reg.parent_item_guid)
    local track = item and r.GetMediaItemTrack and r.GetMediaItemTrack(item)
    if item and track then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
      local x0 = geo.l + ((pos - t0) / (t1 - t0)) * view_w
      local x1 = geo.l + ((pos + len - t0) / (t1 - t0)) * view_w
      local tcp_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0
      local last_y = r.GetMediaItemInfo_Value(item, "I_LASTY") or 0
      local last_h = r.GetMediaItemInfo_Value(item, "I_LASTH") or 0
      if last_h <= 1 then
        last_h = r.GetMediaTrackInfo_Value(track, "I_TCPH") or 24
      end
      local y0 = geo.t + tcp_y + last_y
      local y1 = y0 + last_h
      if mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
        return reg
      end
    end
  end
  return nil
end

function seq_region_from_arrange_parent_hover()
  if seq_mouse_over_script_ui() or not seq_mouse_over_reaper() then
    return nil
  end
  if r.GetItemFromPoint and r.GetMousePosition then
    local x, y = r.GetMousePosition()
    local item = r.GetItemFromPoint(x, y, true)
    if item and seq_item_is_parent_marker(item) then
      local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
      local reg = get_seq_region_by_id(rid)
      if reg then
        return reg
      end
    end
  end
  return seq_region_from_arrange_parent_geometry()
end

function seq_update_link_hover(mx, my, y0, region_lane_h, timeline_x0, timeline_w, start_qn, qn_span, qn_to_x)
  state.seq_link_hover_region_id = nil
  local hover_reg = nil
  if seq_mouse_over_script_ui() and my >= y0 and my <= y0 + region_lane_h and mx >= timeline_x0 and mx <= timeline_x0 + timeline_w then
    local hit = seq_hit_test_region_at(mx, my, y0, region_lane_h, timeline_x0, timeline_w, start_qn, qn_span, qn_to_x)
    if hit and hit.region then
      hover_reg = hit.region
    end
  elseif seq_mouse_over_reaper() then
    hover_reg = seq_region_from_arrange_parent_hover()
  end
  if hover_reg and seq_region_is_linked(hover_reg) then
    state.seq_link_hover_region_id = hover_reg.id
  end
  return get_seq_region_by_id(state.seq_link_hover_region_id)
end

function seq_region_at_qn(qn)
  for _, reg in ipairs(state.seq_regions) do
    local reg_start = reg.start_qn or 0.0
    local reg_end = reg_start + get_seq_region_length_qn(reg)
    if qn >= reg_start and qn < reg_end then
      return reg
    end
  end
  return nil
end

function seq_build_visible_active_cells(start_qn, end_qn, step_qn, step_count)
  local active_cells = {}
  for _, slot in ipairs(state.seq_tracks) do
    active_cells[slot.id] = {}
  end
  for _, reg in ipairs(state.seq_regions) do
    local reg_start = reg.start_qn or 0.0
    local reg_end = reg_start + get_seq_region_length_qn(reg)
    if reg_end >= start_qn and reg_start <= end_qn then
      local pattern = get_seq_pattern(reg.pattern_id, false)
      if pattern then
        for _, slot in ipairs(state.seq_tracks) do
          local notes = get_track_note_table(pattern, slot.id, false)
          if notes then
            for step_key, note in pairs(notes) do
              if type(note) == "table" and note.enabled ~= false
                 and seq_note_in_region(reg, note, step_key, step_qn) then
                local abs_qn = seq_note_abs_qn(reg, note, step_key, step_qn)
                local vis_qn = seq_note_visual_abs_qn(reg, note, step_key, step_qn)
                -- Hit-testing occupies the start cell (and stutter span). Head
                -- and sustain that draw into later cells stay empty so those
                -- grids can be painted.
                local span = seq_stutter_span_qn(note, step_qn) or 0.0
                local occupy_end = vis_qn + math.max(span, 1e-9)
                if occupy_end > start_qn - step_qn and vis_qn < end_qn + step_qn then
                  local entry = {
                    key = step_key,
                    note = note,
                    region_id = reg.id,
                    abs_qn = abs_qn,
                  }
                  local col0 = math.floor(((vis_qn - start_qn) / step_qn) + 1e-9)
                  local col1 = math.floor(((occupy_end - 1e-9 - start_qn) / step_qn) + 1e-9)
                  for col = math.max(0, col0), math.min(step_count - 1, col1) do
                    seq_active_cells_put(active_cells, slot.id, col, entry, start_qn, step_qn, step_count)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  seq_finish_active_cells(active_cells)
  return active_cells
end

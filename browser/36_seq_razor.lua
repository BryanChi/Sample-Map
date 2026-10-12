-- Sample Map Browser module: seq_razor
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_clear_razors()
  local drag = state.seq_razor_drag
  if drag and drag.mode == "move" then
    if drag.patterns_backup then
      state.seq_patterns = clone_table_deep(drag.patterns_backup)
    end
    if drag.undo_open then
      end_seq_undo(drag.undo_label or (drag.copy and "Copy razor notes" or "Move razor notes"))
    end
  end
  local had = seq_has_razors() or state.seq_razor_drag ~= nil
  state.seq_razors = {}
  state.seq_razor_drag = nil
  return had
end

function seq_razor_has_track(razor, track_id)
  if not razor or not razor.track_ids then
    return false
  end
  for _, id in ipairs(razor.track_ids) do
    if id == track_id then
      return true
    end
  end
  return false
end

function seq_cell_in_any_razor(track_id, qn)
  if not seq_has_razors() then
    return false
  end
  for _, razor in ipairs(state.seq_razors) do
    if qn >= (razor.start_qn or 0) and qn < (razor.end_qn or 0) and seq_razor_has_track(razor, track_id) then
      return true
    end
  end
  return false
end

function seq_razor_hovered_at(track_id, qn)
  if not track_id or type(qn) ~= "number" or not seq_has_razors() then
    return false
  end
  for _, razor in ipairs(state.seq_razors) do
    if qn >= (razor.start_qn or 0) and qn < (razor.end_qn or 0) and seq_razor_has_track(razor, track_id) then
      return true
    end
  end
  return false
end

function seq_compute_razor_hover(mx, my, visual_rows, body_y0, body_y1, timeline_x0, timeline_w, view_start_qn, qn_span)
  if not seq_has_razors() or mx < timeline_x0 or mx > timeline_x0 + timeline_w
      or my < body_y0 or my > body_y1 then
    return false, nil, nil
  end
  local track_id = nil
  local cursor_y = body_y0
  for _, row in ipairs(visual_rows) do
    local row_y0 = cursor_y
    local row_y1 = row_y0 + row.h
    if my >= row_y0 and my <= row_y1 and row.slot then
      track_id = row.slot.id
      break
    end
    cursor_y = row_y1
  end
  if not track_id then
    return false, nil, nil
  end
  local qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  if seq_razor_hovered_at(track_id, qn) then
    return true, track_id, qn
  end
  return false, nil, nil
end

function seq_track_id_at_y(row_positions, my)
  if not row_positions or #row_positions == 0 then
    return nil
  end
  for _, row_pos in ipairs(row_positions) do
    if my >= row_pos.y0 and my <= row_pos.y1 and row_pos.row and row_pos.row.slot then
      return row_pos.row.slot.id
    end
  end
  local first = row_positions[1]
  if my < first.y0 and first.row and first.row.slot then
    return first.row.slot.id
  end
  for i = #row_positions, 1, -1 do
    local row_pos = row_positions[i]
    if row_pos.row and row_pos.row.slot then
      return row_pos.row.slot.id
    end
  end
  return nil
end

function seq_normalize_razor_area(start_qn, end_qn, track_id_a, track_id_b, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  if type(start_qn) ~= "number" or type(end_qn) ~= "number" then
    return nil
  end
  local q0 = math.min(start_qn, end_qn)
  local q1 = math.max(start_qn, end_qn)
  q0 = math.max(0.0, math.floor(q0 / step_qn + 1e-9) * step_qn)
  q1 = math.ceil(q1 / step_qn - 1e-9) * step_qn
  if q1 <= q0 then
    q1 = q0 + step_qn
  end
  local _, ia = find_seq_track_by_id(track_id_a)
  local _, ib = find_seq_track_by_id(track_id_b)
  if not ia or not ib then
    return nil
  end
  if ia > ib then
    ia, ib = ib, ia
  end
  local track_ids = {}
  for i = ia, ib do
    local slot = state.seq_tracks[i]
    if slot then
      track_ids[#track_ids + 1] = slot.id
    end
  end
  if #track_ids == 0 then
    return nil
  end
  return { start_qn = q0, end_qn = q1, track_ids = track_ids }
end

function seq_begin_razor_drag(track_id, qn, additive)
  if not track_id or type(qn) ~= "number" then
    return
  end
  if not additive then
    state.seq_razors = {}
  end
  state.seq_razor_drag = {
    mode = "draw",
    additive = additive and true or false,
    start_qn = qn,
    start_track_id = track_id,
    current_qn = qn,
    current_track_id = track_id,
  }
end

function seq_razor_collect_notes(step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local items = {}
  local seen = {}
  for _, razor in ipairs(state.seq_razors or {}) do
    for _, track_id in ipairs(razor.track_ids or {}) do
      for _, region in ipairs(state.seq_regions) do
        local reg_start = region.start_qn or 0.0
        local reg_end = reg_start + get_seq_region_length_qn(region)
        if reg_end > (razor.start_qn or 0) and reg_start < (razor.end_qn or 0) then
          local notes = get_track_note_table(get_seq_pattern(region.pattern_id, false), track_id, false)
          if notes then
            for step_key, note in pairs(notes) do
              if type(note) == "table" then
                local abs_qn = seq_note_abs_qn(region, note, step_key, step_qn)
                if abs_qn >= (razor.start_qn or 0) and abs_qn < (razor.end_qn or 0) then
                    local uniq = tostring(region.id) .. ":" .. tostring(track_id) .. ":" .. tostring(step_key)
                    if not seen[uniq] then
                      seen[uniq] = true
                      local slot = seq_find_slot_by_id(track_id)
                      items[#items + 1] = {
                        region_id = region.id,
                        track_id = track_id,
                        step_key = tostring(step_key),
                        step_idx = tonumber(step_key) or tonumber(note.step) or 0,
                        abs_qn = abs_qn,
                        note = clone_table_deep(note),
                        length_qn = seq_note_length_qn_for_copy(region, slot, note, step_key, step_qn),
                      }
                    end
                end
              end
            end
          end
        end
      end
    end
  end
  return items
end

function seq_razor_track_index_bounds(track_ids)
  local min_idx, max_idx = nil, nil
  for _, track_id in ipairs(track_ids or {}) do
    local _, idx = find_seq_track_by_id(track_id)
    if idx then
      min_idx = min_idx and math.min(min_idx, idx) or idx
      max_idx = max_idx and math.max(max_idx, idx) or idx
    end
  end
  return min_idx, max_idx
end

function seq_shift_track_ids(track_ids, delta_tracks)
  if not track_ids or delta_tracks == 0 then
    return track_ids
  end
  local shifted = {}
  for _, track_id in ipairs(track_ids) do
    local _, idx = find_seq_track_by_id(track_id)
    local slot = idx and state.seq_tracks[idx + delta_tracks]
    if not slot then
      return nil
    end
    shifted[#shifted + 1] = slot.id
  end
  return shifted
end

function seq_razor_clear_notes_in_areas(razors, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  for _, razor in ipairs(razors or {}) do
    for _, track_id in ipairs(razor.track_ids or {}) do
      for _, region in ipairs(state.seq_regions) do
        local reg_start = region.start_qn or 0.0
        local reg_end = reg_start + get_seq_region_length_qn(region)
        if reg_end > (razor.start_qn or 0) and reg_start < (razor.end_qn or 0) then
          local notes = get_track_note_table(get_seq_pattern(region.pattern_id, false), track_id, false)
          if notes then
            local to_delete = {}
            for step_key, note in pairs(notes) do
              if type(note) == "table" then
                local abs_qn = seq_note_abs_qn(region, note, step_key, step_qn)
                if abs_qn >= (razor.start_qn or 0) and abs_qn < (razor.end_qn or 0) then
                    to_delete[#to_delete + 1] = step_key
                end
              end
            end
            for _, step_key in ipairs(to_delete) do
              delete_seq_note(region, track_id, step_key)
            end
          end
        end
      end
    end
  end
end

function seq_begin_razor_move(track_id, qn, step_qn, copy)
  if not seq_has_razors() or not track_id or type(qn) ~= "number" then
    return
  end
  copy = copy and true or false
  local label = begin_seq_undo(copy and "Copy razor notes" or "Move razor notes")
  state.seq_razor_drag = {
    mode = "move",
    copy = copy,
    start_qn = qn,
    start_track_id = track_id,
    current_qn = qn,
    current_track_id = track_id,
    payload = seq_razor_collect_notes(step_qn),
    patterns_backup = clone_table_deep(state.seq_patterns),
    razors_orig = clone_table_deep(state.seq_razors),
    applied_delta_qn = 0,
    applied_delta_tracks = 0,
    undo_label = label,
    undo_open = true,
    dirty = false,
  }
end

function seq_razor_clamped_move_delta(drag, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local raw_qn = (drag.current_qn or drag.start_qn) - (drag.start_qn or 0)
  local delta_qn = math.floor((raw_qn / step_qn) + 0.5) * step_qn
  local _, start_idx = find_seq_track_by_id(drag.start_track_id)
  local _, cur_idx = find_seq_track_by_id(drag.current_track_id)
  local delta_tracks = 0
  if start_idx and cur_idx then
    delta_tracks = cur_idx - start_idx
  end

  local min_qn = nil
  local min_idx, max_idx = nil, nil
  for _, razor in ipairs(drag.razors_orig or {}) do
    min_qn = min_qn and math.min(min_qn, razor.start_qn or 0) or (razor.start_qn or 0)
    local rmin, rmax = seq_razor_track_index_bounds(razor.track_ids)
    if rmin then
      min_idx = min_idx and math.min(min_idx, rmin) or rmin
      max_idx = max_idx and math.max(max_idx, rmax) or rmax
    end
  end
  for _, item in ipairs(drag.payload or {}) do
    min_qn = min_qn and math.min(min_qn, item.abs_qn) or item.abs_qn
    local _, idx = find_seq_track_by_id(item.track_id)
    if idx then
      min_idx = min_idx and math.min(min_idx, idx) or idx
      max_idx = max_idx and math.max(max_idx, idx) or idx
    end
  end
  if min_qn then
    delta_qn = math.max(delta_qn, -min_qn)
  end
  local track_count = #(state.seq_tracks or {})
  if min_idx and max_idx and track_count > 0 then
    delta_tracks = math.max(1 - min_idx, math.min(track_count - max_idx, delta_tracks))
  else
    delta_tracks = 0
  end
  return delta_qn, delta_tracks
end

function seq_razor_apply_move(drag, step_qn)
  if not drag or drag.mode ~= "move" then
    return
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local delta_qn, delta_tracks = seq_razor_clamped_move_delta(drag, step_qn)
  if drag.applied_delta_qn == delta_qn and drag.applied_delta_tracks == delta_tracks then
    return
  end

  state.seq_patterns = clone_table_deep(drag.patterns_backup)
  if delta_qn ~= 0 or delta_tracks ~= 0 then
    local dest_razors = {}
    for _, orig in ipairs(drag.razors_orig or {}) do
      dest_razors[#dest_razors + 1] = {
        start_qn = (orig.start_qn or 0) + delta_qn,
        end_qn = (orig.end_qn or 0) + delta_qn,
        track_ids = seq_shift_track_ids(orig.track_ids, delta_tracks) or orig.track_ids,
      }
    end
    if not drag.copy then
      for _, item in ipairs(drag.payload or {}) do
        local region = get_seq_region_by_id(item.region_id)
        delete_seq_note(region, item.track_id, item.step_key)
      end
    end
    seq_razor_clear_notes_in_areas(dest_razors, step_qn)
    for _, item in ipairs(drag.payload or {}) do
      local _, orig_idx = find_seq_track_by_id(item.track_id)
      local dest_slot = orig_idx and state.seq_tracks[orig_idx + delta_tracks]
      local dest_qn = item.abs_qn + delta_qn
      local dest_region = seq_region_at_qn(dest_qn)
      if dest_slot and dest_region and dest_qn >= 0 then
        local rel = dest_qn - (dest_region.start_qn or 0.0)
        if rel >= -1e-9 and rel < get_seq_region_length_qn(dest_region) - 1e-9 then
          local note = clone_table_deep(item.note)
          note.qn_offset = rel
          note.step = math.floor((rel / step_qn) + 1e-9)
          seq_keep_copied_note_over_region(note, item.length_qn, dest_region, rel)
          local key = seq_alloc_note_key(dest_region, dest_slot.id, rel)
          set_seq_note(dest_region, dest_slot.id, key, note)
        end
      end
    end
  end

  local moved_razors = {}
  for _, orig in ipairs(drag.razors_orig or {}) do
    local track_ids = seq_shift_track_ids(orig.track_ids, delta_tracks) or orig.track_ids
    moved_razors[#moved_razors + 1] = {
      start_qn = (orig.start_qn or 0) + delta_qn,
      end_qn = (orig.end_qn or 0) + delta_qn,
      track_ids = track_ids,
    }
  end
  state.seq_razors = moved_razors
  drag.applied_delta_qn = delta_qn
  drag.applied_delta_tracks = delta_tracks
  drag.dirty = (delta_qn ~= 0 or delta_tracks ~= 0)
end

function seq_razor_mark_pattern_ids_for_razors(razors, pattern_ids)
  for _, razor in ipairs(razors or {}) do
    for _, region in ipairs(state.seq_regions) do
      local rs = region.start_qn or 0.0
      local re = rs + get_seq_region_length_qn(region)
      if re > (razor.start_qn or 0) and rs < (razor.end_qn or 0) and region.pattern_id then
        pattern_ids[region.pattern_id] = true
      end
    end
  end
end

function seq_razor_sync_moved_items(drag, step_qn)
  local track_ids = {}
  local pattern_ids = {}

  local function mark_track(id)
    if id then
      track_ids[id] = true
    end
  end

  for _, item in ipairs(drag.payload or {}) do
    mark_track(item.track_id)
    local src_region = get_seq_region_by_id(item.region_id)
    if src_region and src_region.pattern_id then
      pattern_ids[src_region.pattern_id] = true
    end
    local _, orig_idx = find_seq_track_by_id(item.track_id)
    local dest_slot = orig_idx and state.seq_tracks[orig_idx + (drag.applied_delta_tracks or 0)]
    if dest_slot then
      mark_track(dest_slot.id)
    end
    local dest_qn = (item.abs_qn or 0) + (drag.applied_delta_qn or 0)
    local dest_region = seq_region_at_qn(dest_qn)
    if dest_region and dest_region.pattern_id then
      pattern_ids[dest_region.pattern_id] = true
    end
  end
  for _, razor in ipairs(drag.razors_orig or {}) do
    for _, tid in ipairs(razor.track_ids or {}) do
      mark_track(tid)
    end
  end
  for _, razor in ipairs(state.seq_razors or {}) do
    for _, tid in ipairs(razor.track_ids or {}) do
      mark_track(tid)
    end
  end
  seq_razor_mark_pattern_ids_for_razors(drag.razors_orig, pattern_ids)
  seq_razor_mark_pattern_ids_for_razors(state.seq_razors, pattern_ids)

  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  for _, region in ipairs(state.seq_regions) do
    if pattern_ids[region.pattern_id] then
      for _, slot in ipairs(state.seq_tracks) do
        if track_ids[slot.id] then
          sync_seq_region_track(region, slot, { skip_arrange = true })
        end
      end
    end
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  r.UpdateArrange()
end

function seq_update_razor_drag(track_id, qn, row_positions, my)
  local drag = state.seq_razor_drag
  if not drag then
    return
  end
  if type(qn) == "number" then
    drag.current_qn = qn
  end
  if track_id then
    drag.current_track_id = track_id
  elseif row_positions and my then
    local id = seq_track_id_at_y(row_positions, my)
    if id then
      drag.current_track_id = id
    end
  end
end

function seq_commit_razor_drag(step_qn)
  local drag = state.seq_razor_drag
  state.seq_razor_drag = nil
  if not drag then
    return
  end
  if drag.mode == "move" then
    if drag.dirty then
      seq_razor_sync_moved_items(drag, step_qn)
      save_config()
    end
    if drag.undo_open then
      end_seq_undo(drag.undo_label or (drag.copy and "Copy razor notes" or "Move razor notes"))
    end
    return
  end
  local area = seq_normalize_razor_area(
    drag.start_qn, drag.current_qn, drag.start_track_id, drag.current_track_id, step_qn
  )
  if not area then
    return
  end
  state.seq_razors = state.seq_razors or {}
  if not drag.additive then
    state.seq_razors = {}
  end
  state.seq_razors[#state.seq_razors + 1] = area
end

function seq_razor_y_bounds(razor, row_positions)
  if not razor or not row_positions then
    return nil, nil
  end
  local y0, y1 = nil, nil
  for _, row_pos in ipairs(row_positions) do
    local slot = row_pos.row and row_pos.row.slot
    if slot and seq_razor_has_track(razor, slot.id) then
      y0 = y0 and math.min(y0, row_pos.y0) or row_pos.y0
      y1 = y1 and math.max(y1, row_pos.y1) or row_pos.y1
    end
  end
  return y0, y1
end

function draw_seq_razor_area(dl, razor, row_positions, timeline_x0, timeline_x1, view_start_qn, qn_span, preview, hovered)
  if not razor or not dl then
    return
  end
  local y0, y1 = seq_razor_y_bounds(razor, row_positions)
  if not y0 or not y1 or y1 <= y0 then
    return
  end
  local timeline_w = math.max(1.0, timeline_x1 - timeline_x0)
  local function qn_to_x(qn)
    return timeline_x0 + ((qn - view_start_qn) / math.max(0.0001, qn_span)) * timeline_w
  end
  local rx0 = math.max(timeline_x0, qn_to_x(razor.start_qn or 0))
  local rx1 = math.min(timeline_x1, qn_to_x(razor.end_qn or 0))
  if rx1 <= rx0 then
    return
  end
  local fill = preview and SEQ_RAZOR_PREVIEW_FILL or (hovered and SEQ_RAZOR_HOVER_FILL or SEQ_RAZOR_FILL)
  local edge = preview and SEQ_RAZOR_PREVIEW_EDGE or (hovered and SEQ_RAZOR_HOVER_EDGE or SEQ_RAZOR_EDGE)
  local thickness = preview and 2.0 or (hovered and 2.4 or 1.6)
  r.ImGui_DrawList_AddRectFilled(dl, rx0, y0, rx1, y1, fill, 0)
  r.ImGui_DrawList_AddRect(dl, rx0, y0, rx1, y1, edge, 0, 0, thickness)
end

function draw_seq_razors(dl, row_positions, timeline_x0, timeline_x1, view_start_qn, qn_span, step_qn, hover_track_id, hover_qn)
  for _, razor in ipairs(state.seq_razors or {}) do
    local hovered = hover_track_id and hover_qn
      and seq_razor_has_track(razor, hover_track_id)
      and hover_qn >= (razor.start_qn or 0) and hover_qn < (razor.end_qn or 0)
    draw_seq_razor_area(dl, razor, row_positions, timeline_x0, timeline_x1, view_start_qn, qn_span, false, hovered)
  end
  local drag = state.seq_razor_drag
  if drag and drag.mode ~= "move" then
    local preview = seq_normalize_razor_area(
      drag.start_qn, drag.current_qn, drag.start_track_id, drag.current_track_id, step_qn
    )
    if preview then
      draw_seq_razor_area(dl, preview, row_positions, timeline_x0, timeline_x1, view_start_qn, qn_span, true)
    end
  end
end

function seq_delete_notes_in_razors()
  if not seq_has_razors() then
    return false
  end
  local step_qn = state.seq_grid_qn or 0.25
  local label = begin_seq_undo("Delete razor notes")
  local changed = false
  local synced = {}
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  for _, razor in ipairs(state.seq_razors) do
    for _, track_id in ipairs(razor.track_ids or {}) do
      local slot = find_seq_track_by_id(track_id)
      if slot then
        for _, region in ipairs(state.seq_regions) do
          local reg_start = region.start_qn or 0.0
          local reg_end = reg_start + get_seq_region_length_qn(region)
          if reg_end > (razor.start_qn or 0) and reg_start < (razor.end_qn or 0) then
            local pattern = get_seq_pattern(region.pattern_id, false)
            local notes = get_track_note_table(pattern, track_id, false)
            if notes then
              local to_delete = {}
              for step_key, note in pairs(notes) do
                if type(note) == "table" then
                  local abs_qn = seq_note_abs_qn(region, note, step_key, step_qn)
                  if abs_qn >= (razor.start_qn or 0) and abs_qn < (razor.end_qn or 0) then
                    to_delete[#to_delete + 1] = { key = step_key, qn = seq_note_qn_offset(note, step_key, step_qn) }
                  end
                end
              end
              for _, rec in ipairs(to_delete) do
                if toggle_seq_note(region, slot, rec.key, rec.qn, "erase", {
                  defer_save = true,
                  defer_arrange = true,
                  defer_sync = true,
                }) then
                  changed = true
                  synced[region.pattern_id] = true
                end
              end
            end
          end
        end
      end
    end
  end
  -- One full resync per touched pattern, inside the PreventUIRefresh block.
  if changed then
    for pattern_id in pairs(synced) do
      sync_seq_pattern_regions(pattern_id)
    end
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  if changed then
    r.UpdateArrange()
    save_config()
  end
  end_seq_undo(label)
  return changed
end

function handle_seq_razor_keys()
  if shortcut_pressed("cancel") then
    if seq_clear_razors() then
      return true
    end
  end
  if seq_ingest_busy() then
    return false
  end
  local delete_pressed = shortcut_pressed("delete_razor") or shortcut_pressed("delete_razor_alt")
  if delete_pressed and seq_has_razors() then
    if r.ImGui_SetNextFrameWantCaptureKeyboard then
      r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
    end
    seq_delete_notes_in_razors()
    return true
  end
  return false
end

function find_seq_note_lane_bounds(row_positions, track_id)
  for _, row_pos in ipairs(row_positions) do
    local row = row_pos.row
    if row.type == "note" and row.slot and row.slot.id == track_id then
      return row_pos.y0 + 2, row_pos.y1 - 2, row_pos
    end
  end
  return nil, nil, nil
end

function seq_param_drag_button_down(drag, left_down, right_down)
  if not drag then
    return false
  end
  if drag.button == 1 then
    return right_down
  end
  return left_down
end

function apply_seq_param_reset_drag(drag, def, mx, step_qn, step_count, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, active_cells)
  drag.end_col = seq_param_mouse_col(mx, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, step_qn, step_count)
  local col_min = math.min(drag.col, drag.end_col)
  local col_max = math.max(drag.col, drag.end_col)
  local mouse_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  if seq_is_lock_def(def) then
    if drag.lock_click_span then
      if drag.end_col == drag.col then
        return false, 0.0, col_min, col_max, drag.end_col
      end
      drag.lock_click_span = false
    end
    local region = get_seq_region_by_id(drag.region_id)
    local changed = seq_apply_lock_range(region, drag.track_id, col_min, col_max, start_qn, step_qn, false, active_cells)
    return changed, 0.0, col_min, col_max, drag.end_col
  end
  if seq_is_vary_filter_def(def) then
    if drag.filter_click_span then
      if drag.end_col == drag.col then
        return false, 0.0, col_min, col_max, drag.end_col
      end
      drag.filter_click_span = false
    end
    seq_cancel_vary_filter_edit()
    local region = get_seq_region_by_id(drag.region_id)
    local changed = seq_apply_vary_filter_range(region, drag.track_id, col_min, col_max, start_qn, step_qn, "")
    return changed, 0.0, col_min, col_max, drag.end_col
  end
  local changed = false
  for col = col_min, col_max do
    local active = active_cells[drag.track_id] and active_cells[drag.track_id][col]
    if active then
      local qn0 = start_qn + col * step_qn
      local qn1 = qn0 + step_qn
      seq_for_each_active_note(active, function(entry)
        if seq_apply_param_to_note(
          entry.note, entry.abs_qn, def, def.default, mouse_qn, step_qn, true, true, qn0, qn1
        ) then
          changed = true
        end
      end)
    end
  end
  return changed, def.default, col_min, col_max, drag.end_col
end

function seq_note_item_x_range(note, slot, region, pattern, step_idx, cell_qn, step_qn, qn_to_x, cell_x1)
  if not note or not qn_to_x then
    return nil, nil
  end
  local _, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot and slot.id, step_idx)
  local note_qn = cell_qn
  if region then
    note_qn = seq_note_abs_qn(region, note, step_idx, step_qn)
  end
  local note_len = seq_note_draw_length_qn(
    region, pattern, slot, slot and slot.id, step_idx, note, resolved_sample, step_qn
  ) or step_qn
  local note_off = note.offset_qn or 0.0
  local draw_x0 = qn_to_x(note_qn + note_off) + 2
  local draw_x1 = math.max(draw_x0 + 6.0, qn_to_x(note_qn + note_off + note_len) - 2)
  local trigger_x1 = draw_x1
  if not seq_note_has_stutter_span(note, step_qn) then
    local head_x1 = seq_note_head_end_x(qn_to_x, note_qn, note, step_qn)
    if head_x1 and draw_x1 > head_x1 + 1.0 then
      trigger_x1 = math.max(draw_x0 + 6.0, head_x1)
    end
  end
  return draw_x0, trigger_x1
end

function draw_seq_param_value_bar(dl, x0, x1, lane_top, lane_bot, def, value, step_qn, accent, selected)
  if not def then
    return
  end
  if value == nil then
    value = def.default
  end
  value = seq_param_value_for_drag(def, value, step_qn)
  local bipolar = def.min < 0
  local py = seq_param_y_from_value(def, value, lane_top, lane_bot, step_qn)
  local base_y = lane_bot
  if bipolar then
    base_y = seq_param_y_from_value(def, 0.0, lane_top, lane_bot, step_qn)
  end
  local fill_x0 = x0
  local fill_x1 = x1
  if fill_x1 <= fill_x0 then
    fill_x1 = fill_x0 + 1
  end
  local top_y = math.min(py, base_y)
  local bot_y = math.max(py, base_y)
  if math.abs(bot_y - top_y) < 2 then
    top_y = math.min(top_y, bot_y - 2)
  end
  local fill_col, cap_col = seq_lane_param_fill_colors(accent, bipolar, value)
  if not selected then
    fill_col = seq_dim_color_rrgbbaa(fill_col, true)
    cap_col = seq_dim_color_rrgbbaa(cap_col, true)
  end
  r.ImGui_DrawList_AddRectFilled(dl, fill_x0, top_y, fill_x1, bot_y, fill_col, 2.0)
  local cap_y = (py <= base_y) and top_y or bot_y
  r.ImGui_DrawList_AddRectFilled(dl, fill_x0, cap_y - 1, fill_x1, cap_y + 1, cap_col, 1.0)
end

function seq_draw_stutter_param_slices(dl, note, note_qn, def, step_qn, qn_to_x, lane_top, lane_bot, accent, selected, hover_qn)
  local count = seq_stutter_count(note)
  if count <= 1 or not seq_stutter_hit_param_key(def.key) then
    return false
  end
  local note_off = (note and note.offset_qn) or 0.0
  local hover_idx = hover_qn and seq_stutter_hit_index_at_qn(note, note_qn, hover_qn, step_qn) or nil
  for hi = 1, count do
    local off0, off1 = seq_stutter_hit_span(note, hi, step_qn)
    local s0 = note_qn + note_off + off0
    local s1 = note_qn + note_off + off1
    local sx0 = qn_to_x(s0) + 1.0
    local sx1 = qn_to_x(s1) - 1.0
    if sx1 <= sx0 then
      sx1 = sx0 + 1.0
    end
    local value = seq_note_param_value(note, def.key, hi)
    if value == nil then
      value = def.default
    end
    draw_seq_param_value_bar(dl, sx0, sx1, lane_top, lane_bot, def, value, step_qn, accent, selected)
    if hover_idx == hi then
      r.ImGui_DrawList_AddRect(dl, sx0, lane_top, sx1, lane_bot, seq_lane_color_with_alpha(accent, 220), 1.0, 0, 1.2)
    end
    if hi > 1 then
      local dx = qn_to_x(s0)
      r.ImGui_DrawList_AddLine(dl, dx, lane_top, dx, lane_bot, 0xFFFFFF55, 1.0)
    end
  end
  return true
end

function seq_draw_param_lane_notes_lod(dl, ctx, active, def, selected_region_id, start_qn, col, step_qn, qn_to_x, lane_top, lane_bot, is_stutter_lane, lane_style)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return
  end
  local cell_qn = (start_qn or 0.0) + (col or 0) * (step_qn or 0.25)
  local cell_end = cell_qn + (step_qn or 0.25)
  for pi = 1, #pack do
    local entry = pack[pi]
    local note = entry and entry.note
    if type(note) == "table" and entry.region_id == selected_region_id then
      local vis = seq_entry_vis_qn(entry)
      if vis + 1e-9 >= cell_qn and vis < cell_end + 1e-9 then
        local value = note[def.key]
        if value == nil then value = def.default end
        local item_x0 = qn_to_x(vis)
        local item_x1 = math.max(item_x0 + 1.0, qn_to_x(vis + seq_note_lod_length_qn(note, step_qn)))
        local selected = true
        local accent = lane_style.accent
        if is_stutter_lane then
          draw_seq_stutter_lane_cell(dl, ctx, item_x0, item_x1, lane_top, lane_bot, seq_param_value_for_drag(def, value, step_qn), accent)
        else
          draw_seq_param_value_bar(dl, item_x0, item_x1, lane_top, lane_bot, def, value, step_qn, accent, selected)
        end
      end
    end
  end
end

function seq_draw_param_lane_packed_notes(dl, ctx, slot, active, def, selected_region_id, start_qn, col, step_qn, qn_to_x, cx0, cx1, lane_top, lane_bot, base_y, bipolar, is_stutter_lane, lane_style, region)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return
  end
  for pi = 1, #pack do
    local entry = pack[pi]
    local note = entry.note
    if type(note) == "table" and entry.region_id == selected_region_id then
      local cell_selected = true
      local value = note[def.key]
      if value == nil then value = def.default end
      if def.key == "length_qn" then
        value = snap_seq_length_qn(value, step_qn)
      elseif def.key == "stutter" then
        value = seq_param_value_for_drag(def, value, step_qn)
      end
      local note_qn = entry.abs_qn or (start_qn + col * step_qn)
      local cell_qn = start_qn + col * step_qn
      if note_qn < cell_qn - 1e-9 then
        -- Occupancy-only cell for a spanning stutter; draw from the start cell.
      else
      local cell_reg = get_seq_region_by_id(entry.region_id) or seq_region_at_qn(note_qn) or region
      local pattern = get_seq_pattern(cell_reg and cell_reg.pattern_id, false)
      local item_x0, item_x1 = seq_note_item_x_range(
        note, slot, cell_reg, pattern, entry.key, note_qn, step_qn, qn_to_x, qn_to_x(note_qn + step_qn)
      )
      if not item_x0 then
        item_x0, item_x1 = cx0 + 2, cx1 - 2
      end
      if item_x1 <= item_x0 then
        item_x1 = item_x0 + 1
      end
      if is_stutter_lane then
        local accent = cell_selected and lane_style.accent or seq_lane_color_with_alpha(lane_style.accent, 58)
        draw_seq_stutter_lane_cell(dl, ctx, item_x0, item_x1, lane_top, lane_bot, value, accent)
      else
        local accent = cell_selected and lane_style.accent or seq_lane_color_with_alpha(lane_style.accent, 58)
        if not seq_draw_stutter_param_slices(
          dl, note, note_qn, def, step_qn, qn_to_x, lane_top, lane_bot, accent, cell_selected, nil
        ) then
          draw_seq_param_value_bar(dl, item_x0, item_x1, lane_top, lane_bot, def, value, step_qn, accent, cell_selected)
        end
      end
      local anims = state.seq_note_anims
      local note_fx = (anims and next(anims) ~= nil)
        and get_seq_note_anim(entry.region_id, slot.id, entry.key, r.time_precise()) or nil
      if note_fx and note_fx.kind == "sync" then
        draw_seq_note_sync_flash(dl, item_x0, lane_top, item_x1, lane_bot, note_fx.t)
      end
      end
    end
  end
end

function seq_visible_cell_is_locked(slot, col, start_qn, step_qn, active_cells)
  if not slot then
    return false
  end
  local active = active_cells and active_cells[slot.id] and active_cells[slot.id][col]
  if active then
    local pack = seq_active_cell_notes(active)
    for i = 1, #pack do
      if seq_note_is_locked(pack[i].note) then
        return true
      end
    end
  end
  local cell_qn = start_qn + col * step_qn
  local lock_reg = seq_region_at_qn(cell_qn)
  if not lock_reg then
    return false
  end
  return seq_cell_is_locked(
    get_seq_pattern(lock_reg.pattern_id, false),
    slot.id,
    seq_region_step_key(lock_reg, cell_qn, step_qn)
  )
end

function seq_lock_span_cols(slot, col, start_qn, step_qn, step_count, active_cells)
  col = math.max(0, math.min((step_count or 1) - 1, col or 0))
  if not seq_visible_cell_is_locked(slot, col, start_qn, step_qn, active_cells) then
    return col, col
  end
  local lo, hi = col, col
  while lo > 0 and seq_visible_cell_is_locked(slot, lo - 1, start_qn, step_qn, active_cells) do
    lo = lo - 1
  end
  while hi < step_count - 1 and seq_visible_cell_is_locked(slot, hi + 1, start_qn, step_qn, active_cells) do
    hi = hi + 1
  end
  return lo, hi
end

function draw_seq_lock_icon(dl, cx, cy, size)
  size = math.max(12.0, size or 18.0)
  local half = size * 0.5
  r.ImGui_DrawList_AddRectFilled(dl, cx - half, cy - half, cx + half, cy + half, 0x10141CF5, 4.0)
  r.ImGui_DrawList_AddRect(dl, cx - half, cy - half, cx + half, cy + half, 0xF7FBFFFF, 4.0, 0, 1.5)
  local body_w = size * 0.44
  local body_h = size * 0.34
  local body_y = cy + size * 0.02
  r.ImGui_DrawList_AddRectFilled(dl, cx - body_w * 0.5, body_y, cx + body_w * 0.5, body_y + body_h, 0xFFFFFFFF, 1.8)
  local shackle_r = size * 0.16
  r.ImGui_DrawList_AddCircle(dl, cx, body_y, shackle_r, 0xFFFFFFFF, 14, 2.0)
end

function draw_seq_lock_span(dl, x0, y0, x1, y1, edit_mode, hovered)
  local pad = 3.0
  local sx0 = x0 + 1.0
  local sx1 = x1 - 1.0
  local sy0 = y0 + pad
  local sy1 = y1 - pad
  if sx1 <= sx0 + 2.0 then
    return
  end
  local fill = edit_mode and 0x0B1220B8 or 0x0B122096
  local wash = 0xF4F8FF28
  local outline = 0xF7FBFFFF
  local outline_w = 1.7
  if hovered then
    fill = 0x1A2438E0
    wash = 0xFFFFFF58
    outline = 0xFFFFFFFF
    outline_w = 2.3
  end
  r.ImGui_DrawList_AddRectFilled(dl, sx0, sy0, sx1, sy1, fill, 5.0)
  r.ImGui_DrawList_AddRectFilled(dl, sx0, sy0, sx1, sy1, wash, 5.0)
  if hovered then
    r.ImGui_DrawList_AddRect(dl, sx0 - 1.0, sy0 - 1.0, sx1 + 1.0, sy1 + 1.0, 0xFFFFFFF0, 5.0, 0, 1.6)
  end
  r.ImGui_DrawList_AddRect(dl, sx0, sy0, sx1, sy1, outline, 5.0, 0, outline_w)
  local w = sx1 - sx0
  local h = sy1 - sy0
  local icon = math.min(28.0, math.max(16.0, h * 0.64))
  if w < icon + 6.0 then
    icon = math.max(12.0, w - 6.0)
  end
  draw_seq_lock_icon(dl, (sx0 + sx1) * 0.5, (sy0 + sy1) * 0.5, icon)
end

function draw_seq_lock_spans(dl, slot, row_y0, row_y1, start_qn, step_qn, step_count, col_x0, col_x1, timeline_x0, timeline_x1, active_cells, edit_mode, hover_col)
  local run_start = nil
  local function flush(run_end)
    if not run_start then
      return
    end
    local x0 = math.max(timeline_x0, col_x0(run_start))
    local x1 = math.min(timeline_x1, col_x1(run_end))
    if x1 > x0 + 1.0 then
      local hovered = hover_col ~= nil and hover_col >= run_start and hover_col <= run_end
      draw_seq_lock_span(dl, x0, row_y0, x1, row_y1, edit_mode, hovered)
    end
    run_start = nil
  end
  for col = 0, step_count - 1 do
    if seq_visible_cell_is_locked(slot, col, start_qn, step_qn, active_cells) then
      if not run_start then
        run_start = col
      end
    else
      flush(col - 1)
    end
  end
  flush(step_count - 1)
end

function seq_visible_cell_vary_filter(slot, col, start_qn, step_qn)
  if not slot then
    return nil
  end
  local cell_qn = (start_qn or 0.0) + (col or 0) * (step_qn or 0.25)
  local reg = seq_region_at_qn(cell_qn)
  if not reg then
    return nil
  end
  return seq_cell_vary_filter(reg, slot.id, seq_region_step_key(reg, cell_qn, step_qn))
end

function seq_vary_filter_cell_key(slot, col, start_qn, step_qn)
  local edit = state.seq_vary_filter_edit
  if edit and slot and tostring(edit.track_id) == tostring(slot.id)
      and type(edit.col_min) == "number" and type(edit.col_max) == "number"
      and col >= edit.col_min and col <= edit.col_max then
    return "\0e:" .. seq_trim_text(edit.text or ""), true, seq_trim_text(edit.text or "")
  end
  local text = seq_visible_cell_vary_filter(slot, col, start_qn, step_qn)
  if text and text ~= "" then
    return text, false, text
  end
  return nil, false, nil
end

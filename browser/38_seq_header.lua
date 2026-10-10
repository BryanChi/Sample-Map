-- Sample Map Browser module: seq_header
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_reveal_sample_in_explorer(sample)
  local path = sample and sample.path
  if not path or path == "" then
    return
  end
  if r.CF_LocateInExplorer then
    r.CF_LocateInExplorer(path)
  elseif r.CF_ShellExecute then
    r.CF_ShellExecute(path)
  else
    os.execute("open -R " .. shell_escape(path))
  end
end

function draw_seq_header_sample_menu(sample)
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, "##seq_header_sample_menu") then
    return
  end
  local menu_sample = state.seq_header_menu_sample or sample
  if not menu_sample then
    r.ImGui_EndPopup(ctx)
    return
  end
  local saved = sample_start_is_saved(menu_sample)
  local vol_saved = sample_gain_is_saved(menu_sample)
  if r.ImGui_MenuItem(ctx, "Save start to sample") then
    save_sample_start_offset(menu_sample)
  end
  if r.ImGui_MenuItem(ctx, "Clear saved start", nil, false, saved) then
    clear_sample_start_offset_saved(menu_sample)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Save volume to sample") then
    save_sample_gain(menu_sample)
  end
  if r.ImGui_MenuItem(ctx, "Clear saved volume", nil, false, vol_saved) then
    clear_sample_gain_saved(menu_sample)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Save all") then
    save_sample_header_settings(menu_sample)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Copy path") then
    if r.ImGui_SetClipboardText then
      r.ImGui_SetClipboardText(ctx, menu_sample.path or "")
    end
  end
  if r.ImGui_MenuItem(ctx, "Show in Finder") then
    seq_reveal_sample_in_explorer(menu_sample)
  end
  r.ImGui_EndPopup(ctx)
end

-- Mini preview waveform in the sequencer's "Track / Mix / Env" header corner.
-- Stays on the last hovered/previewed sample until a new note is hovered.
-- Click the waveform to play from the mouse position; click again while playing to stop.
-- Drag the start marker to set a project-only start; "..." saves it globally.
function draw_seq_header_preview_waveform(dl, x, y, w, h, mx, my, left_down, left_clicked)
  local playing = preview_proc ~= nil and preview_sample_obj ~= nil
  local hover_sample = resolve_seq_hovered_grid_sample()
  if hover_sample then
    state.seq_header_wave_sample = hover_sample
  elseif playing or (state.preview_paused and preview_sample_obj) then
    state.seq_header_wave_sample = preview_sample_obj
  end
  local sample = hover_sample or state.seq_header_wave_sample or preview_sample_obj
  if not sample or w < 16 or h < 10 then
    r.ImGui_DrawList_AddText(dl, x + 4, y + math.max(0, (h - 14) * 0.5), 0xE8E8E8FF, "Track / Mix / Env")
    state.seq_preview_wave_scrub = nil
    state.seq_header_start_drag = nil
    state.seq_header_vol_drag = nil
    state.seq_header_wave_press = nil
    state.seq_header_wave_press_t = nil
    return false
  end

  local is_live = playing and preview_sample_obj and preview_sample_obj.path == sample.path
  local hovered = mx >= x and mx <= x + w and my >= y and my <= y + h
  local bg = hovered and UI_THEME.surface_hvr or UI_THEME.bg_panel
  local edge = hovered and UI_THEME.border_hvr or UI_THEME.border
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 4.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, edge, 4.0, 0, 1.0)

  local inner_x = x + 3
  local inner_y = y + 2
  local inner_w = w - 6
  local inner_h = h - 4
  local peaks, duration = nil, nil
  if waveform_data and waveform_data.sample_path == sample.path
      and waveform_data.data and #waveform_data.data > 0 then
    peaks = seq_env_downsample_peaks(waveform_data.data, math.max(48, math.floor(inner_w)))
    duration = tonumber(waveform_data.duration) or tonumber(sample.duration)
  else
    peaks, duration = seq_env_get_wave_peaks(sample, math.floor(inner_w))
  end
  duration = duration or sample.duration or 0.0
  local view0, view1 = wave_view_ensure(sample, duration)
  if peaks then
    seq_draw_env_waveform(dl, inner_x, inner_y, inner_w, inner_h, peaks, view0, view1, duration)
  end

  if is_live then
    local pos = get_preview_position() or state.preview_position or 0.0
    if duration > 0 and pos >= view0 and pos <= view1 then
      local playhead_x = wave_time_to_x(pos, inner_x, inner_w, view0, view1)
      r.ImGui_DrawList_AddLine(dl, playhead_x, y + 1, playhead_x, y + h - 1, 0xFFFF88FF, 1.6)
      r.ImGui_DrawList_AddCircleFilled(dl, playhead_x, y + 3, 3.0, 0xFFFF88FF, 10)
    end
  end

  local ctl = draw_sample_wave_controls(
    dl, sample, x, y, w, h, duration, view0, view1,
    mx, my, left_down, left_clicked, "header", { show_name = true }
  )

  local alt = false
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftAlt then
    alt = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt())
        or (r.ImGui_Key_RightAlt and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt()))
  end
  local mid_down = r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 2)
  if hovered and not (ctl and ctl.over_vol) then
    local wheel = r.ImGui_GetMouseWheel and select(1, r.ImGui_GetMouseWheel(ctx)) or 0
    if wheel and wheel ~= 0 then
      wave_view_zoom(sample, duration, mx, inner_x, inner_w, wheel)
    end
  end
  if hovered and (mid_down or (alt and left_down)) and not (ctl and ctl.consumed) then
    local dx = select(1, r.ImGui_GetMouseDelta(ctx)) or 0
    state.wave_view_pan = true
    wave_view_pan(sample, duration, dx, inner_w)
  elseif state.wave_view_pan and not mid_down and not (alt and left_down) then
    state.wave_view_pan = nil
  end
  if hovered and left_clicked and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
      and not (ctl and ctl.consumed) then
    wave_view_reset(sample, duration)
  end

  local blocking = (ctl and ctl.consumed) or state.wave_view_pan
  if sample.path and not blocking and waveform_drag_should_start(hovered) then
    begin_waveform_sample_drag(sample)
    state.seq_header_wave_press = nil
    state.seq_header_wave_press_t = nil
  end
  if sample_is_waveform_drag_source(sample) then
    draw_waveform_drag_source_cue(dl, x, y, w, h)
  end

  local dbl = hovered and left_clicked and r.ImGui_IsMouseDoubleClicked
      and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local playing_now = preview_proc ~= nil and preview_sample_obj ~= nil
  if hovered and left_clicked and not blocking and not dbl then
    if playing_now then
      -- Click-to-stop while preview is already running.
      stop_preview()
      state.preview_paused = false
      state.seq_header_wave_press = nil
      state.seq_header_wave_press_t = nil
    else
      state.seq_header_wave_press = sample
      state.seq_header_wave_press_t = wave_x_to_time(mx, inner_x, inner_w, view0, view1)
    end
  end
  if state.seq_header_start_drag or state.seq_header_vol_drag or state.wave_view_pan
      or state.pending_waveform_drop then
    state.seq_header_wave_press = nil
    state.seq_header_wave_press_t = nil
  end
  if state.seq_header_wave_press and not left_down then
    local press_sample = state.seq_header_wave_press
    local press_t = state.seq_header_wave_press_t
    state.seq_header_wave_press = nil
    state.seq_header_wave_press_t = nil
    if press_sample and press_sample.path then
      preview_sample(press_sample, press_t)
    end
  end

  return hovered or (ctl and ctl.consumed)
end

SEQ_NOTE_LANE_H_BASE = 48.0
SEQ_PARAM_LANE_H_BASE = 22.0
SEQ_NOTE_LANE_H_MIN = 24.0
SEQ_NOTE_LANE_H_MAX = 480.0
SEQ_LANE_RESIZE_HIT = 5.0

function seq_lane_zoom_clamped()
  return math.max(0.5, math.min(3.0, state.seq_lane_zoom or 1.0))
end

function seq_default_note_lane_h()
  return SEQ_NOTE_LANE_H_BASE * seq_lane_zoom_clamped()
end

function seq_default_param_lane_h()
  return SEQ_PARAM_LANE_H_BASE * seq_lane_zoom_clamped()
end

function seq_clamp_note_lane_h(h)
  h = tonumber(h) or seq_default_note_lane_h()
  if h < SEQ_NOTE_LANE_H_MIN then
    h = SEQ_NOTE_LANE_H_MIN
  elseif h > SEQ_NOTE_LANE_H_MAX then
    h = SEQ_NOTE_LANE_H_MAX
  end
  return h
end

function seq_note_lane_h_for_slot(slot)
  if slot and type(slot.lane_h) == "number" and slot.lane_h > 0 then
    return seq_clamp_note_lane_h(slot.lane_h)
  end
  return seq_default_note_lane_h()
end

function seq_reset_track_lane_heights()
  for _, slot in ipairs(state.seq_tracks or {}) do
    slot.lane_h = nil
    slot.lane_h_enlarged = nil
  end
end

function seq_visible_param_lane_count()
  local n = 0
  for _, def in ipairs(SEQ_PARAM_LANES) do
    if def.key ~= "length_qn" and def.key ~= "decay" and def.key ~= "locked" and def.key ~= "vary_filter" then
      n = n + 1
    end
  end
  return n
end

function seq_enlarged_note_lane_h(slot)
  local default_h = seq_default_note_lane_h()
  local param_h = seq_default_param_lane_h()
  local param_n = seq_visible_param_lane_count()
  local others = 28.0
  for _, s in ipairs(state.seq_tracks or {}) do
    local expanded = state.seq_expanded_tracks and state.seq_expanded_tracks[tostring(s.id)]
    local extra = expanded and (param_n * param_h) or 0.0
    if slot and s.id == slot.id then
      others = others + extra
    else
      others = others + seq_note_lane_h_for_slot(s) + extra
    end
  end
  local viewport = 240.0
  local rect = state.seq_map_rect
  if rect and type(rect.h) == "number" then
    local header = 0.0
    if type(rect.header_y1) == "number" and type(rect.y) == "number" then
      header = math.max(0.0, rect.header_y1 - rect.y)
    end
    viewport = math.max(80.0, rect.h - header)
  end
  return math.max(default_h * 3.0, viewport - others)
end

function seq_toggle_enlarge_hovered_track()
  local slot = seq_hover_slot and seq_hover_slot() or nil
  if not slot then
    return false
  end
  if slot.lane_h_enlarged then
    slot.lane_h = nil
    slot.lane_h_enlarged = nil
  else
    slot.lane_h = seq_clamp_note_lane_h(seq_enlarged_note_lane_h(slot))
    slot.lane_h_enlarged = true
  end
  save_config()
  return true
end

function seq_update_track_lane_h_drag()
  local drag = state.seq_lane_h_drag
  if not drag or not ctx then
    return
  end
  local down = r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0)
  if not down then
    state.seq_lane_h_drag = nil
    save_config()
    return
  end
  local _, my = r.ImGui_GetMousePos(ctx)
  local slot = seq_find_slot_by_id(drag.slot_id)
  if not slot then
    state.seq_lane_h_drag = nil
    return
  end
  local new_h = drag.start_h + (my - drag.start_my)
  if math.abs(my - drag.start_my) >= 1.0 then
    drag.moved = true
  end
  if drag.moved then
    slot.lane_h = seq_clamp_note_lane_h(new_h)
    slot.lane_h_enlarged = nil
  end
end

function seq_hit_track_lane_resize(row_positions, mx, my, x0, x1)
  if not row_positions or not mx or not my then
    return nil, nil, nil
  end
  if mx < x0 or mx > x1 then
    return nil, nil, nil
  end
  local best_slot, best_h, best_y, best_dist = nil, nil, nil, SEQ_LANE_RESIZE_HIT + 1.0
  local i = 1
  while i <= #row_positions do
    local pos = row_positions[i]
    local slot = pos.row and pos.row.slot
    if slot then
      local j = i
      local note_h = (pos.row.type == "note") and (pos.y1 - pos.y0) or nil
      while j + 1 <= #row_positions do
        local nxt = row_positions[j + 1]
        if not nxt.row or nxt.row.slot ~= slot then
          break
        end
        j = j + 1
        if nxt.row.type == "note" then
          note_h = nxt.y1 - nxt.y0
        end
      end
      local divider_y = row_positions[j].y1
      local dist = math.abs(my - divider_y)
      if note_h and dist <= SEQ_LANE_RESIZE_HIT and dist < best_dist then
        best_slot, best_h, best_y, best_dist = slot, note_h, divider_y, dist
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  return best_slot, best_h, best_y
end

function seq_track_divider_y(row_positions, slot_id)
  local y = nil
  if not row_positions or not slot_id then
    return nil
  end
  for _, pos in ipairs(row_positions) do
    if pos.row and pos.row.slot and pos.row.slot.id == slot_id then
      y = pos.y1
    end
  end
  return y
end

function seq_track_reorder_hit_row(row_pos, mx, my, x0, timeline_x0)
  if not row_pos or not row_pos.row or row_pos.row.type ~= "note" or not row_pos.row.slot then
    return false
  end
  if my < row_pos.y0 or my > row_pos.y1 then
    return false
  end
  if mx < x0 or mx >= timeline_x0 then
    return false
  end
  local ctrl = row_pos.ctrl
  if seq_layout_hit(ctrl and ctrl.expand, mx, my) then
    return false
  end
  if seq_lane_mix_controls_hit(row_pos, mx, my, x0, timeline_x0) then
    return false
  end
  local nav_w = seq_track_nav_width(row_pos.y1 - row_pos.y0)
  if mx >= timeline_x0 - nav_w - 6.0 then
    return false
  end
  return true
end

-- Track control column minus mix knobs and sample nav (includes name/expand).
function seq_track_control_context_hit(row_pos, mx, my, x0, timeline_x0)
  if not row_pos or not row_pos.row or row_pos.row.type ~= "note" or not row_pos.row.slot then
    return false
  end
  if my < row_pos.y0 or my > row_pos.y1 then
    return false
  end
  if mx < x0 or mx >= timeline_x0 then
    return false
  end
  if seq_lane_mix_controls_hit(row_pos, mx, my, x0, timeline_x0) then
    return false
  end
  local nav_w = seq_track_nav_width(row_pos.y1 - row_pos.y0)
  if mx >= timeline_x0 - nav_w - 6.0 then
    return false
  end
  return true
end

function seq_open_track_context_menu(slot_id)
  if not slot_id then
    return false
  end
  local idx = nil
  for i, slot in ipairs(state.seq_tracks or {}) do
    if slot.id == slot_id then
      idx = i
      break
    end
  end
  if not idx then
    return false
  end
  state.seq_track_menu_id = slot_id
  state.seq_track_menu_want_open = true
  select_seq_track(idx, { preview = false })
  return true
end

-- Ask before deleting a track whose REAPER track holds items or FX.
function seq_confirm_delete_track(slot)
  local tr = slot and slot.reaper_track_guid and get_track_by_guid(slot.reaper_track_guid)
  if not tr or not r.ShowMessageBox then
    return true
  end
  local items = r.CountTrackMediaItems and r.CountTrackMediaItems(tr) or 0
  local fx = r.TrackFX_GetCount and r.TrackFX_GetCount(tr) or 0
  if items == 0 and fx == 0 then
    return true
  end
  local parts = {}
  if items > 0 then
    parts[#parts + 1] = string.format("%d item%s", items, items == 1 and "" or "s")
  end
  if fx > 0 then
    parts[#parts + 1] = string.format("%d FX", fx)
  end
  local msg = string.format('Delete "%s"?\n\nThis also deletes its REAPER track with %s.',
    tostring(slot.name or "Track"), table.concat(parts, " and "))
  return r.ShowMessageBox(msg, "Delete sequencer track", 4) == 6
end

function seq_prompt_rename_track(slot)
  if not slot or not r.GetUserInputs then
    return false
  end
  local cur = tostring(slot.name or ""):gsub(",", ";")
  local ok, value = r.GetUserInputs("Rename track", 1, "Name:,extrawidth=180", cur)
  if not ok then
    return false
  end
  return seq_rename_track(slot, value)
end

function render_seq_track_context_menu()
  if seq_sync_track_names then
    seq_sync_track_names()
  end
  if state.seq_track_menu_want_open and r.ImGui_OpenPopup then
    state.seq_track_menu_want_open = nil
    r.ImGui_OpenPopup(ctx, "##seq_track_context_menu")
  end
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, "##seq_track_context_menu") then
    return false
  end
  local menu_id = state.seq_track_menu_id
  local slot, idx = nil, nil
  for i, s in ipairs(state.seq_tracks or {}) do
    if s.id == menu_id then
      slot, idx = s, i
      break
    end
  end
  if not slot then
    r.ImGui_EndPopup(ctx)
    return false
  end
  local label = "Delete track"
  if slot.name and slot.name ~= "" then
    label = 'Delete "' .. tostring(slot.name) .. '"'
  end
  local rename = false
  if r.ImGui_MenuItem(ctx, "Rename...") then
    r.ImGui_CloseCurrentPopup(ctx)
    rename = true
  end
  local delete = false
  if r.ImGui_MenuItem(ctx, label) then
    r.ImGui_CloseCurrentPopup(ctx)
    delete = true
  end
  r.ImGui_EndPopup(ctx)
  -- Modal dialogs run after the popup is closed.
  if rename then
    seq_prompt_rename_track(slot)
  elseif delete and seq_confirm_delete_track(slot) then
    seq_delete_seq_track_at(idx)
  end
  return true
end

function seq_track_index_at_lane_y(row_positions, my)
  local last_idx = nil
  for _, pos in ipairs(row_positions or {}) do
    if pos.row and pos.row.type == "note" and pos.row.slot then
      local _, idx = find_seq_track_by_id(pos.row.slot.id)
      if idx then
        last_idx = idx
        if my <= pos.y1 then
          return idx
        end
      end
    end
  end
  return last_idx
end

function seq_track_row_y_span(row_positions, slot_id)
  local y0, y1 = nil, nil
  for _, pos in ipairs(row_positions or {}) do
    if pos.row and pos.row.slot and pos.row.slot.id == slot_id then
      y0 = y0 and math.min(y0, pos.y0) or pos.y0
      y1 = y1 and math.max(y1, pos.y1) or pos.y1
    end
  end
  return y0, y1
end

function seq_finish_track_reorder_drag()
  local drag = state.seq_track_reorder_drag
  state.seq_track_reorder_drag = nil
  if not drag then
    return
  end
  if drag.moved then
    seq_apply_seq_order_to_arrange()
    save_config()
    if drag.undo_open then
      end_seq_undo("Reorder sequencer tracks")
    end
  elseif drag.undo_open then
    end_seq_undo("Reorder sequencer tracks")
  end
end

function seq_update_track_reorder_drag(row_positions, mx, my, left_down, left_clicked, x0, timeline_x0)
  local drag = state.seq_track_reorder_drag
  if drag then
    if not left_down then
      seq_finish_track_reorder_drag()
      return
    end
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
    if not drag.moved then
      if math.abs((my or 0) - (drag.start_my or 0)) >= 6.0 then
        drag.moved = true
        if not drag.undo_open then
          drag.undo_open = seq_undo_own_begin("Reorder sequencer tracks") and true or nil
        end
      else
        return
      end
    end
    local dest = seq_track_index_at_lane_y(row_positions, my)
    local _, src = find_seq_track_by_id(drag.slot_id)
    if dest and src and dest ~= src then
      seq_move_slot_index(src, dest)
    end
    return
  end
  local hover_row = nil
  for _, pos in ipairs(row_positions or {}) do
    if seq_track_reorder_hit_row(pos, mx, my, x0, timeline_x0) then
      hover_row = pos
      break
    end
  end
  if hover_row and not state.seq_over_lane_resize and #(state.seq_tracks or {}) >= 2 then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
    if r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "Drag to reorder tracks")
    end
  end
  if not left_clicked or state.seq_over_lane_resize or state.seq_lane_h_drag
      or state.seq_note_drag or state.seq_param_drag or state.seq_region_drag
      or state.seq_razor_drag or state.pending_waveform_drop then
    return
  end
  if #(state.seq_tracks or {}) < 2 then
    return
  end
  if hover_row then
    local slot = hover_row.row.slot
    local _, idx = find_seq_track_by_id(slot.id)
    if idx then
      state.seq_track_reorder_drag = {
        slot_id = slot.id,
        start_idx = idx,
        start_my = my,
        moved = false,
      }
      select_seq_track(idx, { preview = false })
    end
  end
end

function seq_draw_track_reorder_overlay(dl, row_positions, x0, x1)
  local drag = state.seq_track_reorder_drag
  if not drag or not drag.moved or not dl then
    return
  end
  local y0, y1 = seq_track_row_y_span(row_positions, drag.slot_id)
  if not y0 or not y1 then
    return
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, 0x4DE8FF33, 0)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, 0x4DE8FFCC, 0, 0, 2.0)
end

function seq_apply_track_lane_resize_interaction(row_positions, mx, my, x0, width, left_clicked, dl)
  state.seq_over_lane_resize = false
  if state.seq_note_drag or state.seq_param_drag or state.seq_region_drag
      or state.seq_razor_drag or state.pending_waveform_drop or state.seq_track_reorder_drag then
    return
  end
  local slot, note_h, divider_y = seq_hit_track_lane_resize(row_positions, mx, my, x0, x0 + width)
  if state.seq_lane_h_drag then
    slot = seq_find_slot_by_id(state.seq_lane_h_drag.slot_id) or slot
    divider_y = seq_track_divider_y(row_positions, state.seq_lane_h_drag.slot_id) or divider_y
    note_h = note_h or state.seq_lane_h_drag.start_h
  end
  if not slot then
    return
  end
  state.seq_over_lane_resize = true
  if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNS then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
  end
  if dl and divider_y then
    r.ImGui_DrawList_AddLine(dl, x0, divider_y, x0 + width, divider_y, 0xFFE599FF, 3.0)
  end
  if left_clicked and not state.seq_lane_h_drag then
    state.seq_lane_h_drag = {
      slot_id = slot.id,
      start_my = my,
      start_h = note_h or seq_note_lane_h_for_slot(slot),
    }
  end
  if r.ImGui_SetTooltip and not state.seq_lane_h_drag then
    r.ImGui_SetTooltip(ctx, "Drag to resize track height")
  end
end

function seq_stem_import_register_sample(path, name, tag, duration)
  if not path or path == "" then
    return nil
  end
  path = normalize_path(path)
  local existing = find_sample_by_path(path)
  if existing then
    if duration and (not existing.duration or existing.duration <= 0) then
      existing.duration = duration
    end
    return existing
  end
  local sample = {
    path = path,
    name = name or basename(path),
    duration = duration,
    tags = tag and { tag } or {},
  }
  samples_by_path[path] = sample
  return sample
end

SEQ_STEM_IMPORT_ROLE = {
  kick = "kick", snare = "snare", toms = "tom", hh = "hat",
  ride = "ride", crash = "crash", drums = "perc",
}
SEQ_STEM_IMPORT_LABEL = {
  kick = "Kick", snare = "Snare", toms = "Toms", hh = "Hats",
  ride = "Ride", crash = "Crash", drums = "Drums",
}
SEQ_STEM_IMPORT_RGB = {
  kick = {200, 60, 60},
  snare = {230, 200, 80},
  tom = {180, 100, 50},
  hat = {200, 220, 90},
  ride = {120, 200, 160},
  crash = {90, 180, 220},
  perc = {230, 180, 50},
}

function seq_stem_import_color_track(slot, role)
  if not slot or not slot.reaper_track_guid then
    return
  end
  local rgb = SEQ_STEM_IMPORT_RGB[role]
  if not rgb then
    return
  end
  local tr = get_track_by_guid(slot.reaper_track_guid)
  if not tr then
    return
  end
  local col
  if r.ColorToNative then
    col = r.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000
  else
    col = 0x1000000 | (rgb[1] + rgb[2] * 256 + rgb[3] * 65536)
  end
  r.SetTrackColor(tr, col)
end

function seq_stem_import_slot_for_role(role, label)
  for _, slot in ipairs(state.seq_tracks or {}) do
    if classify_seq_role_text(slot.sample_tag) == role
        or classify_seq_role_text(slot.name) == role then
      return slot
    end
  end
  local slot = create_seq_track_with_name(label)
  if slot then
    local tag = SEQ_ROLE_TAG_CANDIDATES[role] and SEQ_ROLE_TAG_CANDIDATES[role][1] or role
    slot.sample_tag = tag
    seq_stem_import_color_track(slot, role)
  end
  return slot
end

SEQ_STEM_HIT_DETECT = {
  kick = {
    peak_floor = 0.09,
    novelty_percentile = 62,
    percentile_mult = 1.28,
    local_bar_mult = 1.5,
    min_hit_gap = 0.085,
  },
  toms = {
    peak_floor = 0.14,
    novelty_percentile = 70,
    percentile_mult = 1.4,
    local_bar_mult = 1.65,
    min_weight_frac = 0.55,
  },
  ride = {
    peak_floor = 0.16,
    novelty_percentile = 72,
    percentile_mult = 1.45,
    local_bar_mult = 1.7,
    min_weight_frac = 0.52,
  },
  crash = {
    peak_floor = 0.18,
    novelty_percentile = 75,
    percentile_mult = 1.5,
    local_bar_mult = 1.8,
    min_weight_frac = 0.48,
  },
}

SEQ_STEM_QUIET_PEAK_RATIO = {
  toms = 0.24,
  ride = 0.22,
  crash = 0.18,
}

SEQ_STEM_QUIET_ABS_PEAK = 0.0035

function seq_stem_filter_weak_hits(onsets, key)
  local cfg = SEQ_STEM_HIT_DETECT and SEQ_STEM_HIT_DETECT[key]
  if type(cfg) ~= "table" or type(onsets) ~= "table" or #onsets == 0 then
    return onsets
  end
  local frac = tonumber(cfg.min_weight_frac)
  local min_w = tonumber(cfg.min_weight)
  if not frac and not min_w then
    return onsets
  end
  local max_w = 0.0
  for i = 1, #onsets do
    local w = tonumber(onsets[i].weight) or 0.0
    if w > max_w then
      max_w = w
    end
  end
  local bar = 0.0
  if frac then
    bar = max_w * frac
  end
  if min_w and min_w > bar then
    bar = min_w
  end
  local out = {}
  for i = 1, #onsets do
    if (tonumber(onsets[i].weight) or 0.0) >= bar then
      out[#out + 1] = onsets[i]
    end
  end
  if #out == 0 then
    return onsets
  end
  return out
end

function seq_stem_kit_ref_peak(stats_by_key, key)
  if type(stats_by_key) ~= "table" then
    return 0.0
  end
  local function peak_of(name)
    return stats_by_key[name] and tonumber(stats_by_key[name].peak) or 0.0
  end
  -- Toms leak from kick/snare. Cymbals leak from hats/snare.
  if key == "toms" then
    local kick = peak_of("kick")
    local sn = peak_of("snare")
    if kick > sn then
      return kick
    end
    return sn
  end
  local hh = peak_of("hh")
  local sn = peak_of("snare")
  if hh > 1e-8 or sn > 1e-8 then
    if hh > sn then
      return hh
    end
    return sn
  end
  return peak_of("kick")
end

function seq_stem_cymbal_is_bleed(key, stats, ref_peak)
  local ratio = SEQ_STEM_QUIET_PEAK_RATIO and SEQ_STEM_QUIET_PEAK_RATIO[key]
  if not ratio or type(stats) ~= "table" then
    return false
  end
  local peak = tonumber(stats.peak) or 0.0
  local abs_floor = tonumber(SEQ_STEM_QUIET_ABS_PEAK) or 0.0035
  if peak < abs_floor then
    return true
  end
  ref_peak = tonumber(ref_peak) or 0.0
  if ref_peak <= 1e-8 then
    return false
  end
  return peak < ref_peak * ratio
end

function seq_stem_merge_close_hits(onsets, key)
  if type(onsets) ~= "table" or #onsets == 0 then
    return onsets or {}, 0, 0
  end
  local sorted = {}
  for i = 1, #onsets do
    sorted[i] = onsets[i]
  end
  table.sort(sorted, function(a, b)
    return (a.time or 0) < (b.time or 0)
  end)
  local gaps = {
    kick = 0.100,
    snare = 0.070,
    toms = 0.080,
    hh = 0.040,
    ride = 0.070,
    crash = 0.120,
    drums = 0.070,
  }
  local gap = gaps[key] or 0.070
  local weak_gap, weak_frac = 0, 0
  if key == "kick" then
    weak_gap = 0.112
    weak_frac = 0.82
  end
  local min_dt = 0
  local close_n = 0
  if #sorted >= 2 then
    min_dt = 1e9
    for i = 2, #sorted do
      local dt = (sorted[i].time or 0) - (sorted[i - 1].time or 0)
      if dt < min_dt then
        min_dt = dt
      end
      if dt < gap then
        close_n = close_n + 1
      end
    end
  end
  local out = { sorted[1] }
  local merged = 0
  for i = 2, #sorted do
    local cur = sorted[i]
    local prev = out[#out]
    local dt = (cur.time or 0) - (prev.time or 0)
    if dt < gap then
      merged = merged + 1
      local cw = tonumber(cur.weight) or tonumber(cur.raw) or 0
      local pw = tonumber(prev.weight) or tonumber(prev.raw) or 0
      if cw > pw then
        prev.weight = cw
      end
    elseif weak_gap > 0 and dt < weak_gap then
      local cw = tonumber(cur.weight) or tonumber(cur.raw) or 0
      local pw = tonumber(prev.weight) or tonumber(prev.raw) or 0
      local lo = cw
      local hi = pw
      if lo > hi then
        lo = pw
        hi = cw
      end
      if hi > 1e-9 and lo < hi * weak_frac then
        merged = merged + 1
        if cw > pw then
          prev.weight = cw
        end
      else
        out[#out + 1] = cur
      end
    else
      out[#out + 1] = cur
    end
  end
  local out_min = 0
  if #out >= 2 then
    out_min = 1e9
    for i = 2, #out do
      local dt = (out[i].time or 0) - (out[i - 1].time or 0)
      if dt < out_min then
        out_min = dt
      end
    end
  end
  return out, merged, min_dt
end

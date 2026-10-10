-- Sample Map Browser module: seq_midi_env_popups
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_midi_draw_keyboard(dl, x, y, w, h, slot, octave)
  octave = math.max(-2, math.min(8, math.floor(tonumber(octave) or 1)))
  local start_note = (octave + 2) * 12
  if start_note < 0 then start_note = 0 end
  local n_keys = 24
  local is_black = {
    [1] = true, [3] = true, [6] = true, [8] = true, [10] = true,
  }
  local whites = 0
  for i = 0, n_keys - 1 do
    if not is_black[i % 12] then whites = whites + 1 end
  end
  local ww = w / math.max(1, whites)
  local bh = h * 0.58
  local bw = ww * 0.62
  seq_normalize_slot_midi(slot)
  local lo, hi = slot.midi_lo, slot.midi_hi
  local changed = false
  local hovered_note = nil

  local function in_range(n)
    return n >= lo and n <= hi
  end

  local function paint_key(note, kx0, ky0, kx1, ky1, black)
    if note < 0 or note > 127 then return end
    r.ImGui_SetCursorScreenPos(ctx, kx0, ky0)
    r.ImGui_InvisibleButton(ctx, "##seq_midi_key_" .. note, kx1 - kx0, ky1 - ky0)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local pressed = r.ImGui_IsItemActive(ctx)
    if hovered then hovered_note = note end
    local selected = in_range(note)
    local fill
    if black then
      fill = selected and 0x1EFF5EFF or (hovered and 0x3A4A40FF or 0x121816FF)
    else
      fill = selected and 0x174A24FF or (hovered and 0xE8EEEAFF or 0xD8DED8FF)
    end
    local edge = selected and UI_THEME.accent or (black and 0x000000FF or 0x2A342EFF)
    r.ImGui_DrawList_AddRectFilled(dl, kx0, ky0, kx1, ky1, fill, 2.0)
    r.ImGui_DrawList_AddRect(dl, kx0, ky0, kx1, ky1, edge, 2.0, 0, 1.0)
    if r.ImGui_IsItemClicked(ctx, 0) then
      local shift = false
      if r.ImGui_IsKeyDown then
        local lshift = r.ImGui_Key_LeftShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift())
        local rshift = r.ImGui_Key_RightShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
        shift = lshift or rshift
      end
      seq_midi_set_note(slot, note, shift)
      seq_midi_trigger_slot(slot, 110, note)
      changed = true
    end
    if pressed and state.seq_midi_key_drag and state.seq_midi_key_drag.origin then
      local a = state.seq_midi_key_drag.origin
      if note ~= a then
        seq_midi_set_range(slot, a, note)
        changed = true
      end
    elseif r.ImGui_IsItemActivated and r.ImGui_IsItemActivated(ctx) then
      state.seq_midi_key_drag = { origin = note }
    end
  end

  local wx = x
  for i = 0, n_keys - 1 do
    local pc = i % 12
    if not is_black[pc] then
      paint_key(start_note + i, wx, y, wx + ww - 1.0, y + h, false)
      wx = wx + ww
    end
  end
  wx = x
  for i = 0, n_keys - 1 do
    local pc = i % 12
    if not is_black[pc] then
      if is_black[(i + 1) % 12] then
        local bx0 = wx + ww - bw * 0.5
        paint_key(start_note + i + 1, bx0, y, bx0 + bw, y + bh, true)
      end
      wx = wx + ww
    end
  end

  if r.ImGui_IsMouseReleased and r.ImGui_IsMouseReleased(ctx, 0) then
    state.seq_midi_key_drag = nil
  end
  return changed, hovered_note
end

function render_seq_midi_assign_popup()
  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_AlwaysAutoResize then flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize() end

  local style_colors, style_vars = 0, 0
  if r.ImGui_Col_PopupBg then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), UI_THEME.popup_bg)
    style_colors = style_colors + 1
  end
  if r.ImGui_Col_Border then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), UI_THEME.border)
    style_colors = style_colors + 1
  end
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
    style_vars = style_vars + 1
  end
  local function pop_style()
    if style_vars > 0 then r.ImGui_PopStyleVar(ctx, style_vars) end
    if style_colors > 0 then r.ImGui_PopStyleColor(ctx, style_colors) end
  end

  local open = r.ImGui_BeginPopup(ctx, "seq_midi_assign_popup", flags)
  if not open then
    pop_style()
    if not r.ImGui_IsPopupOpen or not r.ImGui_IsPopupOpen(ctx, "seq_midi_assign_popup") then
      if state.seq_midi_popup_slot_id then
        local dirty = state.seq_midi_assign_dirty == true
        state.seq_midi_popup_slot_id = nil
        state.seq_midi_key_drag = nil
        state.seq_midi_assign_dirty = nil
        -- Disarm learn so the next incoming note can't silently reassign a track.
        state.seq_midi_learn_slot_id = nil
        state.seq_midi_kb_octave = nil
        return dirty
      end
    end
    return false
  end

  local slot = seq_find_track_slot_by_id(state.seq_midi_popup_slot_id)
  if not slot then
    r.ImGui_CloseCurrentPopup(ctx)
    r.ImGui_EndPopup(ctx)
    pop_style()
    state.seq_midi_popup_slot_id = nil
    state.seq_midi_learn_slot_id = nil
    state.seq_midi_kb_octave = nil
    return false
  end
  seq_midi_ensure_jsfx()
  seq_normalize_slot_midi(slot)

  local changed = false
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local name = slot.name or ("Track " .. tostring(slot.id))
  r.ImGui_TextColored(ctx, UI_THEME.text, name)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "MIDI trigger")

  local learning = state.seq_midi_learn_slot_id == slot.id
  if draw_ui_button("seq_midi_learn", learning and "Listening…" or "Learn", 88, 22, {
    style = learning and "success" or "default",
    compact = true,
  }) then
    if learning then
      seq_midi_end_learn()
    else
      seq_midi_begin_learn(slot, is_shift_down and is_shift_down() or false, "popup")
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Click, then play a note to assign it\nShift-click: extend the range to the next note")
  end
  r.ImGui_SameLine(ctx)
  if draw_ui_button("seq_midi_reset", "GM", 36, 22, { compact = true }) then
    local def = seq_midi_default_note_for_slot(slot)
    seq_midi_set_range(slot, def, def)
    changed = true
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Reset to General MIDI default for this drum")
  end

  if not seq_midi_parent_is_armed() then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute,
      "MIDI input is off. Learn arms it while listening;\nturn on the MIDI button to play live.")
  end

  r.ImGui_Dummy(ctx, 1, 4)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Notes in this range trigger the sample")

  local lo, hi = slot.midi_lo, slot.midi_hi
  local lo_changed, lo_val, lo_hot = seq_rect_drag_control(
    "##seq_midi_lo", dl, select(1, r.ImGui_GetCursorScreenPos(ctx)), select(2, r.ImGui_GetCursorScreenPos(ctx)),
    120, 18, lo, 0, 127,
    {
      horizontal = true,
      fill_color = 0x1EFF5EFF,
      format_value = function(v)
        v = seq_midi_clamp_note(v)
        return "Lo " .. seq_midi_note_name(v) .. "  " .. tostring(v)
      end,
    }
  )
  r.ImGui_Dummy(ctx, 120, 18)
  r.ImGui_SameLine(ctx)
  local hi_x, hi_y = r.ImGui_GetCursorScreenPos(ctx)
  local hi_changed, hi_val, hi_hot = seq_rect_drag_control(
    "##seq_midi_hi", dl, hi_x, hi_y, 120, 18, hi, 0, 127,
    {
      horizontal = true,
      fill_color = 0x62FF8AFF,
      format_value = function(v)
        v = seq_midi_clamp_note(v)
        return "Hi " .. seq_midi_note_name(v) .. "  " .. tostring(v)
      end,
    }
  )
  r.ImGui_Dummy(ctx, 120, 18)
  if lo_changed then
    seq_midi_set_range(slot, lo_val, math.max(lo_val, slot.midi_hi))
    changed = true
  end
  if hi_changed then
    seq_midi_set_range(slot, math.min(slot.midi_lo, hi_val), hi_val)
    changed = true
  end

  r.ImGui_Dummy(ctx, 1, 6)
  local oct = state.seq_midi_kb_octave
  if not oct then
    oct = math.floor((slot.midi_lo or 36) / 12) - 2
    state.seq_midi_kb_octave = oct
  end
  if draw_ui_button("seq_midi_oct_l", "<", 22, 22, { compact = true }) then
    state.seq_midi_kb_octave = math.max(-2, oct - 1)
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text, "C" .. tostring(state.seq_midi_kb_octave))
  r.ImGui_SameLine(ctx)
  if draw_ui_button("seq_midi_oct_r", ">", 22, 22, { compact = true }) then
    state.seq_midi_kb_octave = math.min(7, oct + 1)
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Shift-click / drag for a range")

  local kb_x, kb_y = r.ImGui_GetCursorScreenPos(ctx)
  local kb_w, kb_h = 248.0, 56.0
  local kb_changed = seq_midi_draw_keyboard(dl, kb_x, kb_y, kb_w, kb_h, slot, state.seq_midi_kb_octave)
  r.ImGui_Dummy(ctx, kb_w, kb_h)
  if kb_changed then changed = true end
  if changed then
    state.seq_midi_assign_dirty = true
  end

  r.ImGui_EndPopup(ctx)
  pop_style()
  return false
end

-- Transparent popup containing only the envelope graph (with sample waveform).
-- Returns true when the envelope was changed this frame.
function seq_env_popup_anchor_pos(graph_w, graph_h)
  -- Sit next to the envelope sparkline that opened the editor.
  local gap = 6.0
  local preview = state.seq_env_popup_preview_rect
  local map = state.seq_map_rect
  local px, py = nil, nil
  if preview and preview.x1 then
    px = preview.x1 + gap
    py = (preview.y or 0) + (preview.h or 0) * 0.5 - graph_h * 0.5
  elseif map and map.timeline_x then
    px = map.timeline_x + gap
    py = (map.header_y1 or map.y or 0) + gap
  else
    local rect = state.main_window_rect
    if rect and rect.w then
      px = rect.x + gap
      py = (rect.y or 0) + 80.0
    end
  end
  if not px or not py then
    return nil, nil
  end

  if map then
    local min_x = (map.x or px) + gap
    local max_x = ((map.x or px) + (map.w or graph_w) ) - graph_w - gap
    if preview and preview.x and px > max_x then
      px = preview.x - graph_w - gap
    end
    if max_x >= min_x then
      px = math.max(min_x, math.min(px, max_x))
    end
    local min_y = (map.y or py) + gap
    local map_bottom = (map.y or py) + (map.h or graph_h)
    local max_y = map_bottom - graph_h - gap
    if max_y >= min_y then
      py = math.max(min_y, math.min(py, max_y))
    else
      py = min_y
    end
  end
  return px, py
end

function seq_close_env_editor_popup()
  state.seq_env_popup_slot_id = nil
  state.seq_env_popup_just_opened = nil
  state.seq_env_popup_preview_rect = nil
  state.seq_env_graph_drag = nil
  if seq_env_view_reset then
    seq_env_view_reset()
  end
end

function render_seq_env_editor_popup()
  if not state.seq_env_popup_slot_id then
    return false
  end

  local slot = seq_find_slot_by_id and seq_find_slot_by_id(state.seq_env_popup_slot_id)
  if not slot then
    for _, s in ipairs(state.seq_tracks or {}) do
      if s.id == state.seq_env_popup_slot_id then
        slot = s
        break
      end
    end
  end
  if not slot then
    seq_close_env_editor_popup()
    return false
  end

  local graph_w, graph_h = 380.0, 168.0
  local px, py = seq_env_popup_anchor_pos(graph_w, graph_h)
  if not px or not py then
    return false
  end

  -- Same overlay pattern as the extras flyout: top-level window so the tracks
  -- child cannot steal hits or reinterpret the screen-space anchor.
  local cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 1
  if not cond or cond == 0 then cond = 1 end
  r.ImGui_SetNextWindowPos(ctx, px, py, cond)
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, graph_w, graph_h, cond)
  end
  if r.ImGui_SetNextWindowBgAlpha then
    r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
  end

  local style_colors = 0
  local style_vars = 0
  if r.ImGui_Col_WindowBg then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    style_colors = style_colors + 1
  end
  if r.ImGui_Col_Border then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
    style_colors = style_colors + 1
  end
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    style_vars = style_vars + 1
  end
  if r.ImGui_StyleVar_WindowBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    style_vars = style_vars + 1
  end

  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoMove then flags = flags | r.ImGui_WindowFlags_NoMove() end
  if r.ImGui_WindowFlags_NoCollapse then flags = flags | r.ImGui_WindowFlags_NoCollapse() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  if r.ImGui_WindowFlags_NoSavedSettings then flags = flags | r.ImGui_WindowFlags_NoSavedSettings() end
  if r.ImGui_WindowFlags_NoFocusOnAppearing then flags = flags | r.ImGui_WindowFlags_NoFocusOnAppearing() end
  if r.ImGui_WindowFlags_NoNav then flags = flags | r.ImGui_WindowFlags_NoNav() end
  if r.ImGui_WindowFlags_NoBackground then flags = flags | r.ImGui_WindowFlags_NoBackground() end

  local visible = r.ImGui_Begin(ctx, "##seq_env_editor", true, flags)
  local popup_dl = (r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx))
    or (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx))
  local gx, gy = px, py
  if r.ImGui_GetCursorScreenPos then
    gx, gy = r.ImGui_GetCursorScreenPos(ctx)
  end

  local changed = false
  if visible then
    seq_normalize_slot_mix(slot)
    local env_hot, tip
    changed, env_hot, tip = seq_render_env_graph_editor(
      popup_dl, slot, gx, gy, graph_w, graph_h, { show_waveform = true }
    )
    if (env_hot or tip) and tip and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, tip)
    end
    r.ImGui_Dummy(ctx, graph_w, graph_h)

    local dragging = state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id
    local win_hovered = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx)
    local escape = r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
    local clicked_outside = r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
      and not win_hovered and not env_hot
    if state.seq_env_popup_just_opened then
      state.seq_env_popup_just_opened = nil
    elseif escape or (clicked_outside and not dragging) then
      seq_close_env_editor_popup()
    end
  end

  end_window(visible, true)
  if style_vars > 0 then r.ImGui_PopStyleVar(ctx, style_vars) end
  if style_colors > 0 then r.ImGui_PopStyleColor(ctx, style_colors) end
  return changed and true or false
end

function seq_render_env_editor_host()
  if not render_seq_env_editor_popup() then
    return false
  end
  begin_seq_undo("Edit sequencer envelope")
  seq_undo_commit_on_release = true
  local popup_slot = seq_find_slot_by_id and seq_find_slot_by_id(state.seq_env_popup_slot_id)
  if not popup_slot then
    for _, s in ipairs(state.seq_tracks or {}) do
      if s.id == state.seq_env_popup_slot_id then
        popup_slot = s
        break
      end
    end
  end
  if popup_slot then
    seq_normalize_slot_mix(popup_slot)
  end
  if seq_schedule_ingest_save then
    seq_schedule_ingest_save()
  end
  if not (state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id) then
    if popup_slot then
      sync_seq_slot_all_regions(popup_slot, { force_rebuild = true })
    else
      seq_resync_all_regions()
    end
    state.seq_env_pending_resync = nil
    state.seq_env_pending_resync_slot_id = nil
  else
    state.seq_env_pending_resync = true
    if popup_slot then
      state.seq_env_pending_resync_slot_id = popup_slot.id
    end
  end
  return true
end

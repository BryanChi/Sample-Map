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
      fill = selected and UI_THEME.accent or (hovered and 0x434447FF or 0x151619FF)
    else
      fill = selected and 0x174A24FF or (hovered and 0xEBECF0FF or 0xDBDCE0FF)
    end
    local edge = selected and UI_THEME.accent or (black and 0x000000FF or 0x2F3033FF)
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
      fill_color = UI_THEME.accent,
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

-- ===== Envelope editor window ==========================================
-- A card with a title row, the graph (dB rows, ms columns, the waveform as the
-- envelope shapes it) and a row of shape presets.

SEQ_ENV_POPUP = {
  w = 470.0,
  pad = 8.0,
  header_h = 22.0,
  graph_h = 190.0,
  footer_h = 18.0,
  gap = 6.0,
}

SEQ_ENV_PRESETS = {
  { key = "flat",  label = "Flat",  tip = "Flat\nNo shaping: the whole hit at 0 dB", hint = "Flat: no shaping, 0 dB" },
  { key = "punch", label = "Punch", tip = "Punch\nBoost the transient, then settle at 0 dB", hint = "Punch: boost the transient" },
  { key = "tight", label = "Tight", tip = "Tight\nKeep the body, then gate the tail", hint = "Tight: keep the body, gate the tail" },
  { key = "fade",  label = "Fade",  tip = "Fade\nFast exponential fade over the whole hit", hint = "Fade: fast fade over the hit" },
  { key = "swell", label = "Swell", tip = "Swell\nSoften the attack", hint = "Swell: soft attack" },
}

-- One line of hint text: "Key: action" pieces separated by " · ", keys a
-- little brighter, clipped to the line.
function seq_env_draw_hint_line(dl, x, y, w, h, text)
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  end
  local cx = x
  local first = true
  for piece in (text .. " · "):gmatch("(.-) · ") do
    if not first then
      local sw, sh = r.ImGui_CalcTextSize(ctx, "  ·  ")
      r.ImGui_DrawList_AddText(dl, cx, y + (h - sh) * 0.5, UI_THEME.text_mute, "  ·  ")
      cx = cx + sw
    end
    first = false
    local key, rest = piece:match("^([^:]+:)(.*)$")
    if key then
      local kw, kh = r.ImGui_CalcTextSize(ctx, key)
      r.ImGui_DrawList_AddText(dl, cx, y + (h - kh) * 0.5, UI_THEME.text, key)
      cx = cx + kw
      piece = rest
    end
    local pw, ph = r.ImGui_CalcTextSize(ctx, piece)
    r.ImGui_DrawList_AddText(dl, cx, y + (h - ph) * 0.5, UI_THEME.text_dim, piece)
    cx = cx + pw
    if cx > x + w then
      break
    end
  end
  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
end

function seq_env_popup_height()
  local P = SEQ_ENV_POPUP
  return P.pad * 2 + P.header_h + P.gap + P.graph_h + P.gap + P.footer_h
end

-- Points for a preset over a hit of length len (seconds). trans is the
-- sample's transient end when known.
function seq_env_preset_points(kind, len, trans)
  len = math.max(0.01, tonumber(len) or 1.0)
  trans = tonumber(trans)
  if not trans or trans <= 0.0 or trans >= len * 0.8 then
    trans = math.min(0.03, len * 0.15)
  end
  if kind == "punch" then
    local settle = math.min(len * 0.6, math.max(trans * 2.0, 0.02))
    return {
      { t = 0.0, amp = 2.0, curve = -0.35 },
      { t = settle, amp = 1.0, curve = 0.0 },
      { t = len, amp = 1.0, curve = 0.0 },
    }
  elseif kind == "tight" then
    local hold = math.min(len * 0.45, math.max(trans * 3.0, 0.05))
    local stop = math.min(len, hold + math.max(0.02, len * 0.18))
    local pts = {
      { t = 0.0, amp = 1.0, curve = 0.0 },
      { t = hold, amp = 1.0, curve = -0.45 },
      { t = stop, amp = 0.0, curve = 0.0 },
    }
    if stop < len - 0.0005 then
      pts[#pts + 1] = { t = len, amp = 0.0, curve = 0.0 }
    end
    return pts
  elseif kind == "fade" then
    return {
      { t = 0.0, amp = 1.0, curve = -0.55 },
      { t = len, amp = 0.0, curve = 0.0 },
    }
  elseif kind == "swell" then
    local atk = math.min(len * 0.3, math.max(trans * 2.5, 0.025))
    return {
      { t = 0.0, amp = 0.0, curve = -0.4 },
      { t = atk, amp = 1.0, curve = 0.0 },
      { t = len, amp = 1.0, curve = 0.0 },
    }
  end
  return {
    { t = 0.0, amp = 1.0, curve = 0.0 },
    { t = len, amp = 1.0, curve = 0.0 },
  }
end

function seq_env_apply_preset(slot, preset)
  if not slot or not preset then
    return false
  end
  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  local len = state.seq_env_graph_len or (sample and tonumber(sample.duration)) or 1.0
  local label = begin_seq_undo("Envelope preset: " .. preset.label)
  slot.env = seq_normalize_track_env({
    points = seq_env_preset_points(preset.key, len, sample and sample.transient_end),
  })
  seq_normalize_slot_mix(slot)
  seq_on_slot_mix_changed(slot, { resync = true })
  end_seq_undo(label)
  if seq_schedule_ingest_save then
    seq_schedule_ingest_save()
  end
  if seq_env_view_reset then
    seq_env_view_reset()
  end
  return true
end

-- Small text chip / icon button drawn on dl. Returns clicked, hovered.
function seq_env_popup_button(id, dl, x, y, w, h, opts)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg, _, text_col, border = ui_button_colors(opts.style or "default", hovered, pressed, opts.selected)
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, border, hovered, pressed)
  local cx, cy = x + w * 0.5, y + h * 0.5 + (pressed and 0.5 or 0.0)
  if opts.icon then
    ui_button_draw_icon(dl, opts.icon, cx, cy, math.min(w, h), hovered and 0xFFFFFFFF or text_col)
  end
  if opts.glyph then
    opts.glyph(dl, cx, cy, h, hovered and 0xFFFFFFFF or text_col)
  end
  if opts.label then
    local tw, th = r.ImGui_CalcTextSize(ctx, opts.label)
    r.ImGui_DrawList_AddText(dl, cx - tw * 0.5, cy - th * 0.5, hovered and 0xFFFFFFFF or text_col, opts.label)
  end
  return clicked, hovered
end

-- Tiny curve drawn on each preset chip so the shape reads before the name.
function seq_env_preset_glyph(dl, kind, x, y, w, h, col)
  local pts = seq_env_preset_points(kind, 1.0, 0.08)
  local env = { points = pts }
  local steps = 10
  local prev_x, prev_y
  for i = 0, steps do
    local t = i / steps
    local a = seq_env_levels_at_norm(env, t)
    local px = x + t * w
    local py = y + h - math.min(1.0, a / 2.0) * h
    if prev_x then
      r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, px, py, col, 1.2)
    end
    prev_x, prev_y = px, py
  end
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
  if seq_env_popup_on_close then
    seq_env_popup_on_close()
  end
end

function render_seq_env_editor_popup()
  if not state.seq_env_popup_slot_id then
    return false
  end

  -- Another target (a drum layering corner) may stand in for the track: a
  -- table with id, name, env and sample_path, plus optional popup_anchor and
  -- keep_open callbacks.
  local slot = seq_env_popup_custom_target and seq_env_popup_custom_target() or nil
  if not slot then
    slot = seq_find_slot_by_id and seq_find_slot_by_id(state.seq_env_popup_slot_id)
  end
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

  local P = SEQ_ENV_POPUP
  local graph_w, graph_h = P.w, seq_env_popup_height()
  local px, py = nil, nil
  if slot.popup_anchor then
    px, py = slot.popup_anchor(graph_w, graph_h)
  end
  if not px then
    px, py = seq_env_popup_anchor_pos(graph_w, graph_h)
  end
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
  if r.ImGui_WindowFlags_TopMost then flags = flags | r.ImGui_WindowFlags_TopMost() end

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
    local dl = popup_dl
    local x0, y0 = gx, gy
    local x1, y1 = gx + graph_w, gy + graph_h
    -- Card
    r.ImGui_DrawList_AddRectFilled(dl, x0 + 2, y0 + 5, x1 + 2, y1 + 5, 0x00000050, 10.0)
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, UI_THEME.popup_bg, 8.0)
    r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, UI_THEME.border, 8.0, 0, 1.0)

    -- Top row: shape presets, close. No hover tooltips in the card: the
    -- bottom line says what the hovered control does.
    local hx, hy = x0 + P.pad, y0 + P.pad
    local hh = P.header_h
    local hint = nil
    local close_x = x1 - P.pad - hh
    local close_clicked, close_hot = seq_env_popup_button("##seq_env_close", dl, close_x, hy, hh, hh,
      { icon = "close" })
    if close_hot then
      hint = "Close · Esc"
    end
    local fx = hx
    local preset_hit = nil
    for i, preset in ipairs(SEQ_ENV_PRESETS) do
      local lw = r.ImGui_CalcTextSize(ctx, preset.label)
      local bw = lw + 30.0
      if fx + bw > close_x - 6.0 then
        break
      end
      local clicked, hot = seq_env_popup_button("##seq_env_preset_" .. i, dl, fx, hy, bw, hh, {
        glyph = function(gdl, cx, cy, size, col)
          local gw, gh = 14.0, size * 0.42
          local gx0 = cx - bw * 0.5 + 7.0
          seq_env_preset_glyph(gdl, preset.key, gx0, cy - gh * 0.5, gw, gh, col)
          local _, lh = r.ImGui_CalcTextSize(ctx, preset.label)
          r.ImGui_DrawList_AddText(gdl, gx0 + gw + 5.0, cy - lh * 0.5, col, preset.label)
        end,
      })
      if hot then
        hint = preset.hint
      end
      if clicked then
        preset_hit = preset
      end
      fx = fx + bw + 4.0
    end

    -- Graph
    local graph_x = x0 + P.pad
    local graph_y = hy + hh + P.gap
    local env_hot, tip
    changed, env_hot, tip = seq_render_env_graph_editor(
      dl, slot, graph_x, graph_y, graph_w - P.pad * 2, P.graph_h,
      { show_waveform = true, shaped_waveform = true }
    )
    if env_hot and tip then
      hint = tip
    end

    -- Bottom line: hint for whatever is hovered.
    local fy = graph_y + P.graph_h + P.gap
    seq_env_draw_hint_line(dl, x0 + P.pad, fy, graph_w - P.pad * 2, P.footer_h,
      hint or "Click: add point · Scroll: zoom · Shift+scroll: pan · Dbl-click: full view")

    r.ImGui_SetCursorScreenPos(ctx, x0, y0)
    r.ImGui_Dummy(ctx, graph_w, graph_h)

    if preset_hit then
      seq_env_apply_preset(slot, preset_hit)
      -- Applied with its own undo point and resync; don't report it to the host.
      changed = false
    end
    if close_clicked then
      seq_close_env_editor_popup()
    end

    local dragging = state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id
    -- Test the pointer against the card itself: IsWindowHovered turns false as
    -- soon as any item is pressed, which made a click on the editor's own
    -- buttons count as a click outside and close it before the click landed.
    local pmx, pmy = r.ImGui_GetMousePos(ctx)
    local win_hovered = pmx and pmy and pmx >= x0 and pmx < x1 and pmy >= y0 and pmy < y1
    local escape = r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
    local clicked_outside = r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
      and not win_hovered and not env_hot and not (slot.keep_open and slot.keep_open())
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
  -- The host is called from both the map layout and the sequencer view; draw
  -- the editor once per frame so its buttons aren't submitted twice.
  local frame = r.ImGui_GetFrameCount and r.ImGui_GetFrameCount(ctx)
  if frame and state.seq_env_host_frame == frame then
    return false
  end
  state.seq_env_host_frame = frame
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

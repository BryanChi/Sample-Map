-- Sample Map Browser module: seq_arrange_overlay
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_scroll_track_vertically_into_view(track)
  if not track then
    return
  end
  local tcp_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0
  local tcp_h = r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0
  if tcp_h <= 1 then
    tcp_h = r.GetMediaTrackInfo_Value(track, "I_WNDH") or 24
  end
  local pad = 16
  local geo = seq_get_arrange_geometry()
  local hwnd = geo and geo.hwnd
  local view_h = geo and geo.view_h
  local pos = geo and geo.scroll_pos or 0

  if hwnd and view_h and view_h > 8 and r.JS_Window_SetScrollPos then
    local top_ok = tcp_y >= pad
    local bot_ok = (tcp_y + tcp_h) <= (view_h - pad)
    if top_ok and bot_ok then
      return
    end
    local delta = 0
    if not top_ok then
      delta = tcp_y - pad
    else
      delta = (tcp_y + tcp_h) - (view_h - pad)
    end
    r.JS_Window_SetScrollPos(hwnd, "v", math.max(0, math.floor(pos + delta + 0.5)))
    seq_request_script_refocus(10)
    return
  end

  -- Fallback: REAPER's scroll-selected-tracks-into-view works in both directions.
  local out_of_view = tcp_y < 0 or (view_h and (tcp_y + tcp_h) > view_h)
  if not out_of_view and view_h then
    return
  end
  if not out_of_view and not view_h and tcp_y >= 0 then
    -- Without a known arrange height, still scroll when the track sits far below the top.
    if tcp_y < 240 then
      return
    end
  end
  local sel = {}
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    local tr = r.GetTrack(0, i)
    sel[i] = r.IsTrackSelected(tr)
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  r.SetOnlyTrackSelected(track)
  r.Main_OnCommand(40913, 0)
  for i = 0, n - 1 do
    r.SetTrackSelected(r.GetTrack(0, i), sel[i] and true or false)
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  seq_request_script_refocus(10)
end

function seq_item_imgui_rect(octx, item, track, ar_x0, ar_y0, ar_x1, ar_y1, t0, t1)
  if not item or not track or not t0 or not t1 or t1 <= t0 then
    return nil
  end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local ar_w = ar_x1 - ar_x0
  local x0 = ar_x0 + ((pos - t0) / (t1 - t0)) * ar_w
  local x1 = ar_x0 + ((pos + len - t0) / (t1 - t0)) * ar_w
  local tcp_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0
  local tcp_h = r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0
  if tcp_h <= 1 then
    tcp_h = r.GetMediaTrackInfo_Value(track, "I_WNDH") or 24
  end
  local last_y = r.GetMediaItemInfo_Value(item, "I_LASTY") or 0
  local last_h = r.GetMediaItemInfo_Value(item, "I_LASTH") or 0
  if last_h <= 1 then
    last_h = tcp_h
  end
  local y0 = ar_y0 + tcp_y + last_y
  local y1 = y0 + last_h
  x0 = math.max(ar_x0, x0)
  x1 = math.min(ar_x1, x1)
  y0 = math.max(ar_y0, y0)
  y1 = math.min(ar_y1, y1)
  if x1 - x0 < 2 or y1 - y0 < 2 then
    return nil
  end
  return x0, y0, x1, y1
end

function seq_union_item_imgui_rect(octx, items, track, ar_x0, ar_y0, ar_x1, ar_y1, t0, t1)
  local ux0, uy0, ux1, uy1 = nil, nil, nil, nil
  if items then
    for i = 1, #items do
      local x0, y0, x1, y1 = seq_item_imgui_rect(octx, items[i], track, ar_x0, ar_y0, ar_x1, ar_y1, t0, t1)
      if x0 then
        ux0 = ux0 and math.min(ux0, x0) or x0
        uy0 = uy0 and math.min(uy0, y0) or y0
        ux1 = ux1 and math.max(ux1, x1) or x1
        uy1 = uy1 and math.max(uy1, y1) or y1
      end
    end
  end
  if ux0 then
    return ux0, uy0, ux1, uy1
  end
  -- No tagged item: still highlight the track lane at the hovered note's time.
  local nt0, nt1 = seq_hover_note_time_span()
  if not nt0 or not track then
    return nil
  end
  local tcp_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0
  local tcp_h = r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0
  if tcp_h <= 1 then
    tcp_h = r.GetMediaTrackInfo_Value(track, "I_WNDH") or 24
  end
  local span = t1 - t0
  if span <= 0 then
    return nil
  end
  local x0 = ar_x0 + ((nt0 - t0) / span) * (ar_x1 - ar_x0)
  local x1 = ar_x0 + ((nt1 - t0) / span) * (ar_x1 - ar_x0)
  local y0 = ar_y0 + tcp_y
  local y1 = y0 + tcp_h
  x0 = math.max(ar_x0, x0)
  x1 = math.min(ar_x1, x1)
  y0 = math.max(ar_y0, y0)
  y1 = math.min(ar_y1, y1)
  if x1 - x0 < 2 or y1 - y0 < 2 then
    return nil
  end
  return x0, y0, x1, y1
end

function seq_native_to_imgui(octx, x, y)
  if r.ImGui_PointConvertNative then
    local nx, ny = r.ImGui_PointConvertNative(octx, x, y)
    if type(nx) == "number" and type(ny) == "number" then
      return nx, ny
    end
  end
  return x, y
end

function seq_get_script_hwnd()
  if r.ImGui_GetNativeHwnd and ctx and r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    local hwnd = r.ImGui_GetNativeHwnd(ctx)
    if hwnd then
      return hwnd
    end
  end
  if r.JS_Window_Find then
    return r.JS_Window_Find(SCRIPT_NAME, true)
  end
  return nil
end

function seq_focus_is_overlay(focused)
  if not focused then
    return false
  end
  if seq_arrange_overlay_hwnd then
    if focused == seq_arrange_overlay_hwnd then
      return true
    end
    if r.JS_Window_IsChild and r.JS_Window_IsChild(seq_arrange_overlay_hwnd, focused) then
      return true
    end
  end
  if r.JS_Window_GetTitle then
    local title = r.JS_Window_GetTitle(focused)
    if title == "Sample Map Item Highlight" or title == "Sample Map Link Highlight" then
      return true
    end
  end
  return false
end

function seq_focus_is_arrange(focused)
  if not focused then
    return false
  end
  local arrange = seq_get_arrange_hwnd and seq_get_arrange_hwnd() or nil
  if arrange then
    if focused == arrange then
      return true
    end
    if r.JS_Window_IsChild and r.JS_Window_IsChild(arrange, focused) then
      return true
    end
  end
  local main = r.GetMainHwnd and r.GetMainHwnd() or nil
  if main and focused == main then
    return true
  end
  return false
end

function seq_hwnd_is_reaper(hwnd)
  if not hwnd then
    return false
  end
  if seq_focus_is_overlay(hwnd) or seq_focus_is_arrange(hwnd) then
    return true
  end
  local main = r.GetMainHwnd and r.GetMainHwnd() or nil
  local script = seq_get_script_hwnd()
  local h = hwnd
  local guard = 0
  while h and guard < 24 do
    if h == main or h == script then
      return true
    end
    h = r.JS_Window_GetParent and r.JS_Window_GetParent(h) or nil
    guard = guard + 1
  end
  return false
end

function seq_reaper_is_active()
  if not r.JS_Window_GetForeground then
    return true
  end
  -- On macOS GetForeground often stays on a REAPER window even when another
  -- app is in front. Arrange highlights are painted into the arrange itself.
  return seq_hwnd_is_reaper(r.JS_Window_GetForeground())
end

function seq_mouse_over_reaper()
  if r.JS_Window_FromPoint and r.GetMousePosition then
    local x, y = r.GetMousePosition()
    local hwnd = r.JS_Window_FromPoint(x, y)
    if hwnd and seq_focus_is_overlay(hwnd) then
      return true
    end
    if hwnd then
      return seq_hwnd_is_reaper(hwnd)
    end
    return false
  end
  return seq_reaper_is_active()
end

seq_script_refocus_frames = 0

function seq_restore_script_keyboard_focus(force)
  if not r.JS_Window_SetFocus then
    return
  end
  local script = seq_get_script_hwnd()
  if not script then
    return
  end
  local focused = r.JS_Window_GetFocus and r.JS_Window_GetFocus() or nil
  if focused == script then
    return
  end
  if focused and r.JS_Window_IsChild and r.JS_Window_IsChild(script, focused) then
    return
  end
  if not force and focused and not seq_focus_is_overlay(focused) and not seq_focus_is_arrange(focused) then
    return
  end
  if r.JS_Window_SetForeground then
    r.JS_Window_SetForeground(script)
  end
  r.JS_Window_SetFocus(script)
end

function seq_request_script_refocus(frames)
  seq_script_refocus_frames = math.max(seq_script_refocus_frames or 0, tonumber(frames) or 8)
  seq_restore_script_keyboard_focus(true)
end

function seq_pump_script_refocus()
  if (seq_script_refocus_frames or 0) <= 0 then
    return
  end
  seq_restore_script_keyboard_focus(true)
  seq_script_refocus_frames = seq_script_refocus_frames - 1
end

function seq_lice_color(rr, gg, bb)
  return (0xFF << 24) | ((rr & 0xFF) << 16) | ((gg & 0xFF) << 8) | (bb & 0xFF)
end

function seq_destroy_stale_overlay_windows()
  if not r.JS_Window_Find then
    return
  end
  for _, title in ipairs({ "Sample Map Item Highlight", "Sample Map Link Highlight" }) do
    local hwnd = r.JS_Window_Find(title, true)
    if hwnd then
      if r.JS_Window_Show then
        pcall(r.JS_Window_Show, hwnd, "HIDE")
      end
      if r.JS_Window_Move then
        pcall(r.JS_Window_Move, hwnd, -8000, -8000)
      end
    end
  end
end

function seq_arrange_hl_unlink()
  if seq_arrange_hl_linked and seq_arrange_hl_hwnd and seq_arrange_hl_bm and r.JS_Composite_Unlink then
    pcall(r.JS_Composite_Unlink, seq_arrange_hl_hwnd, seq_arrange_hl_bm, true)
  end
  seq_arrange_hl_linked = false
end

function seq_destroy_arrange_overlay_ctx()
  seq_arrange_hl_unlink()
  if seq_arrange_hl_bm and r.JS_LICE_DestroyBitmap then
    pcall(r.JS_LICE_DestroyBitmap, seq_arrange_hl_bm)
  end
  seq_arrange_hl_bm = nil
  seq_arrange_hl_bm_w = 0
  seq_arrange_hl_bm_h = 0
  seq_arrange_hl_hwnd = nil
  seq_arrange_hl_pending = nil
  if seq_arrange_overlay_ctx and r.ImGui_ValidatePtr(seq_arrange_overlay_ctx, "ImGui_Context*") then
    if r.APIExists("ImGui_DestroyContext") then
      pcall(r.ImGui_DestroyContext, seq_arrange_overlay_ctx)
    end
  end
  seq_arrange_overlay_ctx = nil
  seq_arrange_overlay_hwnd = nil
  seq_destroy_stale_overlay_windows()
end

function seq_arrange_hl_reset()
  seq_arrange_hl_pending = {}
end

function seq_arrange_hl_add(x0, y0, x1, y1, fill_rgb, fill_a, edge_rgb)
  if not seq_arrange_hl_pending then
    seq_arrange_hl_pending = {}
  end
  seq_arrange_hl_pending[#seq_arrange_hl_pending + 1] = {
    x0 = x0, y0 = y0, x1 = x1, y1 = y1,
    fill_rgb = fill_rgb, fill_a = fill_a, edge_rgb = edge_rgb
  }
end

function seq_arrange_hl_draw_rect(bm, rect)
  local x = math.floor(rect.x0 + 0.5)
  local y = math.floor(rect.y0 + 0.5)
  local w = math.floor(rect.x1 - rect.x0 + 0.5)
  local h = math.floor(rect.y1 - rect.y0 + 0.5)
  if w < 2 or h < 2 then
    return
  end
  if r.JS_LICE_FillRect then
    r.JS_LICE_FillRect(bm, x, y, w, h, rect.fill_rgb, rect.fill_a or 0.3, "COPY")
  end
  if r.JS_LICE_RoundRect then
    pcall(r.JS_LICE_RoundRect, bm, x, y, w - 1, h - 1, 3, rect.edge_rgb, 1.0, "COPY", true)
  elseif r.JS_LICE_Line then
    local x2, y2 = x + w - 1, y + h - 1
    r.JS_LICE_Line(bm, x, y, x2, y, rect.edge_rgb, 1.0, "COPY", true)
    r.JS_LICE_Line(bm, x2, y, x2, y2, rect.edge_rgb, 1.0, "COPY", true)
    r.JS_LICE_Line(bm, x2, y2, x, y2, rect.edge_rgb, 1.0, "COPY", true)
    r.JS_LICE_Line(bm, x, y2, x, y, rect.edge_rgb, 1.0, "COPY", true)
  end
end

function seq_arrange_hl_flush()
  local pending = seq_arrange_hl_pending
  seq_arrange_hl_pending = nil
  if not pending or #pending == 0 then
    seq_arrange_hl_unlink()
    return
  end
  if not (r.JS_LICE_CreateBitmap and r.JS_LICE_Clear and r.JS_Composite) then
    seq_arrange_hl_unlink()
    return
  end
  local hwnd = seq_get_arrange_hwnd()
  local geo = seq_get_arrange_geometry()
  if not hwnd or not geo or not geo.view_w or not geo.view_h then
    seq_arrange_hl_unlink()
    return
  end
  local w = math.max(1, math.floor((geo.view_w or 0) + 0.5))
  local h = math.max(1, math.floor((geo.view_h or 0) + 0.5))
  if seq_arrange_hl_hwnd and seq_arrange_hl_hwnd ~= hwnd then
    seq_arrange_hl_unlink()
  end
  if seq_arrange_hl_bm and (seq_arrange_hl_bm_w ~= w or seq_arrange_hl_bm_h ~= h) then
    seq_arrange_hl_unlink()
    if r.JS_LICE_Resize then
      r.JS_LICE_Resize(seq_arrange_hl_bm, w, h)
      seq_arrange_hl_bm_w = w
      seq_arrange_hl_bm_h = h
    else
      pcall(r.JS_LICE_DestroyBitmap, seq_arrange_hl_bm)
      seq_arrange_hl_bm = nil
    end
  end
  if not seq_arrange_hl_bm then
    seq_arrange_hl_bm = r.JS_LICE_CreateBitmap(true, w, h)
    seq_arrange_hl_bm_w = w
    seq_arrange_hl_bm_h = h
  end
  if not seq_arrange_hl_bm then
    return
  end
  -- Skip clear/redraw/composite when the same rects are already composited.
  local sig_parts = { tostring(w), tostring(h) }
  for i = 1, #pending do
    local p = pending[i]
    sig_parts[#sig_parts + 1] = string.format("%s,%s,%s,%s,%s,%s,%s",
      math.floor(p.x0 + 0.5), math.floor(p.y0 + 0.5),
      math.floor(p.x1 - p.x0 + 0.5), math.floor(p.y1 - p.y0 + 0.5),
      tostring(p.fill_rgb), tostring(p.fill_a), tostring(p.edge_rgb))
  end
  local sig = table.concat(sig_parts, ";")
  if seq_arrange_hl_linked and seq_arrange_hl_hwnd == hwnd and state.seq_arrange_hl_last_sig == sig then
    return
  end
  r.JS_LICE_Clear(seq_arrange_hl_bm, 0)
  for i = 1, #pending do
    seq_arrange_hl_draw_rect(seq_arrange_hl_bm, pending[i])
  end
  seq_arrange_hl_hwnd = hwnd
  r.JS_Composite(hwnd, 0, 0, w, h, seq_arrange_hl_bm, 0, 0, w, h, true)
  seq_arrange_hl_linked = true
  state.seq_arrange_hl_last_sig = sig
end

function seq_update_arrange_item_follow()
  if not state.seq_follow_hovered_item then
    return nil
  end
  if state.active_view ~= "sequencer" and not state.sequencer_floating then
    return nil
  end
  if state.seq_note_drag or state.seq_param_drag or state.seq_region_drag or state.seq_razor_drag or state.seq_lane_h_drag or state.seq_track_reorder_drag then
    return nil
  end
  local items, track = seq_find_hovered_arrange_items()
  if not track then
    return nil
  end
  seq_scroll_track_vertically_into_view(track)
  return items, track
end

function seq_render_arrange_item_overlay()
  if not seq_arrange_hl_killed_stale then
    seq_arrange_hl_killed_stale = true
    seq_destroy_stale_overlay_windows()
  end
  seq_arrange_hl_reset()
  if not state.seq_follow_hovered_item or not sequencer_is_open()
      or state.seq_note_drag or state.seq_param_drag or state.seq_region_drag or state.seq_razor_drag or state.seq_lane_h_drag or state.seq_track_reorder_drag then
    return
  end
  local items, track = seq_find_hovered_arrange_items()
  if not track then
    return
  end
  local geo = seq_get_arrange_geometry()
  if not geo or not geo.view_w or not geo.view_h then
    return
  end
  local t0, t1 = get_arrange_view_range()
  local x0, y0, x1, y1 = seq_union_item_imgui_rect(nil, items, track, 0, 0, geo.view_w, geo.view_h, t0, t1)
  if not x0 then
    return
  end
  seq_arrange_hl_add(x0, y0, x1, y1, seq_lice_color(255, 255, 136), 0.16, seq_lice_color(255, 255, 136))
end

function seq_render_link_parent_overlay()
  if not sequencer_is_open() then
    state.seq_link_hover_region_id = nil
    seq_arrange_hl_flush()
    return
  end
  local hover = get_seq_region_by_id(state.seq_link_hover_region_id)
  if hover and seq_region_is_linked(hover) then
    local geo = seq_get_arrange_geometry()
    local t0, t1 = get_arrange_view_range()
    if geo and geo.view_w and geo.view_h and t0 and t1 then
      for _, reg in ipairs(state.seq_regions or {}) do
        if seq_region_in_link_group(reg, hover) and reg.parent_item_guid then
          local item = seq_find_item_by_guid(reg.parent_item_guid)
          local track = item and r.GetMediaItemTrack and r.GetMediaItemTrack(item)
          if item and track then
            local x0, y0, x1, y1 = seq_item_imgui_rect(nil, item, track, 0, 0, geo.view_w, geo.view_h, t0, t1)
            if x0 then
              seq_arrange_hl_add(x0, y0, x1, y1, seq_lice_color(255, 229, 153), 0.33, seq_lice_color(255, 229, 153))
            end
          end
        end
      end
    end
  end
  seq_arrange_hl_flush()
end

-- Internal sequencer undo/redo. REAPER's undo cannot restore Lua sequencer
-- state (ProjExtState is not in the undo history), so Sample Map keeps its
-- own snapshot stack. Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z drive it.
SEQ_UNDO_MAX = 80
seq_undo_stack = {}
seq_redo_stack = {}
seq_undo_session = nil
seq_undo_applying = false
seq_undo_commit_on_release = false

function seq_undo_is_open()
  return seq_undo_session ~= nil
end

function seq_undo_clear_history()
  state.seq_pattern_confirm = nil
  seq_undo_stack = {}
  seq_redo_stack = {}
  -- Close a REAPER undo block still open from an interrupted session.
  if seq_undo_session and not seq_undo_session.lazy_reaper then
    seq_undo_end_reaper(seq_undo_session.label)
  end
  seq_undo_session = nil
  seq_undo_applying = false
  seq_undo_commit_on_release = false
end

function seq_undo_values_equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    if type(a) == "number" and type(b) == "number" then
      if a ~= a or b ~= b then
        return a ~= a and b ~= b
      end
      return math.abs(a - b) < 0.000000001
    end
    return a == b
  end
  for k, v in pairs(a) do
    if not seq_undo_values_equal(v, b[k]) then
      return false
    end
  end
  for k, v in pairs(b) do
    if a[k] == nil and v ~= nil then
      return false
    end
  end
  return true
end

function capture_seq_document_snapshot()
  return {
    seq_tracks = clone_table_deep(state.seq_tracks),
    selected_seq_track = state.selected_seq_track,
    seq_track_next_id = state.seq_track_next_id,
    seq_regions = clone_table_deep(state.seq_regions),
    seq_patterns = clone_table_deep(state.seq_patterns),
    seq_region_next_id = state.seq_region_next_id,
    seq_pattern_next_id = state.seq_pattern_next_id,
    seq_pool_next_id = state.seq_pool_next_id,
    selected_seq_region_id = state.selected_seq_region_id,
    seq_kit_history = clone_table_deep(state.seq_kit_history),
    seq_kit_history_next_id = state.seq_kit_history_next_id,
    seq_razors = clone_table_deep(state.seq_razors) or {},
  }
end

function restore_seq_document_snapshot(snap)
  if type(snap) ~= "table" then
    return
  end
  -- Clone field-by-field so later edits cannot mutate the stacked snapshot.
  state.seq_tracks = clone_table_deep(snap.seq_tracks) or {}
  state.selected_seq_track = snap.selected_seq_track
  state.seq_track_next_id = snap.seq_track_next_id or 1
  state.seq_regions = clone_table_deep(snap.seq_regions) or {}
  state.seq_patterns = clone_table_deep(snap.seq_patterns) or {}
  state.seq_region_next_id = snap.seq_region_next_id or 1
  state.seq_pattern_next_id = snap.seq_pattern_next_id or 1
  state.seq_pool_next_id = snap.seq_pool_next_id or 1
  state.selected_seq_region_id = snap.selected_seq_region_id
  state.seq_kit_history = clone_table_deep(snap.seq_kit_history) or {}
  state.seq_kit_history_next_id = snap.seq_kit_history_next_id or 1
  state.seq_razors = clone_table_deep(snap.seq_razors) or {}
  state.selected_seq_note = nil
  state.seq_note_drag = nil
  state.seq_param_drag = nil
  state.seq_region_drag = nil
  state.seq_region_rename = nil
  state.seq_vary_filter_edit = nil
  state.seq_rect_drag = nil
  state.seq_random_knob_drag = nil
  state.seq_random_sync_pending = nil
  state.seq_random_sync_run = false
  state.seq_env_graph_drag = nil
  state.seq_razor_drag = nil
  state.seq_track_reorder_drag = nil
  state.seq_pattern_confirm = nil
  seq_undo_commit_on_release = false
  if seq_normalize_slot_mix then
    for _, slot in ipairs(state.seq_tracks) do
      seq_normalize_slot_mix(slot)
    end
  end
end

function seq_undo_index_by_id(list)
  local by_id = {}
  if type(list) ~= "table" then
    return by_id
  end
  for _, entry in ipairs(list) do
    if type(entry) == "table" and entry.id then
      by_id[entry.id] = entry
    end
  end
  return by_id
end

function seq_undo_track_needs_item_resync(a, b)
  if not a or not b then
    return true
  end
  if a.sample_path ~= b.sample_path or a.reaper_track_guid ~= b.reaper_track_guid then
    return true
  end
  if (a.overlap and true or false) ~= (b.overlap and true or false) then
    return true
  end
  return not seq_undo_values_equal(a.env, b.env)
end

function seq_undo_track_needs_mix(a, b)
  if not a or not b then
    return true
  end
  if math.abs((a.volume or 1.0) - (b.volume or 1.0)) > 0.000000001 then
    return true
  end
  if math.abs((a.pan or 0.0) - (b.pan or 0.0)) > 0.000000001 then
    return true
  end
  if (a.mute and true or false) ~= (b.mute and true or false) then
    return true
  end
  if (a.solo and true or false) ~= (b.solo and true or false) then
    return true
  end
  return false
end

-- Compare live sequencer state to a snapshot and return the cheapest arrange update.
-- full: rebuild every region. Otherwise delete items for remove_ids and recreate sync_ids.
function seq_undo_plan_resync(from_state, to_snap)
  local remove_ids = {}
  local sync_ids = {}
  local mix = false
  if type(from_state) ~= "table" or type(to_snap) ~= "table" then
    return remove_ids, sync_ids, true, true
  end

  local from_tracks = seq_undo_index_by_id(from_state.seq_tracks)
  local to_tracks = seq_undo_index_by_id(to_snap.seq_tracks)
  for id, from_slot in pairs(from_tracks) do
    local to_slot = to_tracks[id]
    if not to_slot or seq_undo_track_needs_item_resync(from_slot, to_slot) then
      return remove_ids, sync_ids, true, true
    end
    if seq_undo_track_needs_mix(from_slot, to_slot) then
      mix = true
    end
  end
  for id, _ in pairs(to_tracks) do
    if not from_tracks[id] then
      return remove_ids, sync_ids, true, true
    end
  end

  local from_regs = seq_undo_index_by_id(from_state.seq_regions)
  local to_regs = seq_undo_index_by_id(to_snap.seq_regions)
  local changed_patterns = {}
  local function consider_pattern(pid)
    if not pid or changed_patterns[pid] then
      return
    end
    local key = tostring(pid)
    local from_pat = from_state.seq_patterns and from_state.seq_patterns[key]
    local to_pat = to_snap.seq_patterns and to_snap.seq_patterns[key]
    if not seq_undo_values_equal(from_pat, to_pat) then
      changed_patterns[pid] = true
    end
  end
  for _, reg in ipairs(from_state.seq_regions or {}) do
    consider_pattern(reg.pattern_id)
  end
  for _, reg in ipairs(to_snap.seq_regions or {}) do
    consider_pattern(reg.pattern_id)
  end

  for id, _ in pairs(from_regs) do
    if not to_regs[id] then
      remove_ids[id] = true
    end
  end
  for id, to_reg in pairs(to_regs) do
    local from_reg = from_regs[id]
    if not from_reg then
      sync_ids[id] = true
    elseif math.abs((from_reg.start_qn or 0) - (to_reg.start_qn or 0)) > 0.000000001
        or from_reg.length_bars ~= to_reg.length_bars
        or from_reg.pattern_id ~= to_reg.pattern_id
        or from_reg.pool_id ~= to_reg.pool_id
        or changed_patterns[to_reg.pattern_id] then
      remove_ids[id] = true
      sync_ids[id] = true
    end
  end
  return remove_ids, sync_ids, mix, false
end

function seq_undo_set_has_ids(id_set)
  if type(id_set) ~= "table" then
    return false
  end
  for _ in pairs(id_set) do
    return true
  end
  return false
end

function seq_undo_begin_reaper()
  if r.Undo_BeginBlock2 then
    r.Undo_BeginBlock2(0)
  elseif r.Undo_BeginBlock then
    r.Undo_BeginBlock()
  end
end

function seq_undo_end_reaper(label)
  if r.Undo_EndBlock2 then
    r.Undo_EndBlock2(0, label or "Sample Map Sequencer edit", -1)
  elseif r.Undo_EndBlock then
    r.Undo_EndBlock(label or "Sample Map Sequencer edit", -1)
  end
end

function apply_seq_undo_snapshot(snap, label)
  if type(snap) ~= "table" then
    return
  end
  -- Run the body under xpcall so the REAPER undo block, PreventUIRefresh and
  -- seq_undo_applying are always released, even if a resync step errors.
  local guard = { block = false, refresh = false }
  seq_undo_applying = true
  local ok, err = xpcall(seq_apply_undo_snapshot_body, function(e)
    return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
  end, snap, label, guard)
  if guard.refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if guard.block then
    seq_undo_end_reaper(label or "Sample Map undo")
  end
  seq_undo_applying = false
  if not ok then
    if r.ShowConsoleMsg then
      r.ShowConsoleMsg("Sample Map: error while applying sequencer undo:\n" .. tostring(err) .. "\n")
    end
    error(err, 0)
  end
end

function seq_apply_undo_snapshot_body(snap, label, guard)
  local remove_ids, sync_ids, mix, full = seq_undo_plan_resync(state, snap)
  restore_seq_document_snapshot(snap)
  seq_undo_begin_reaper()
  guard.block = true
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
    guard.refresh = true
  end
  if seq_ensure_slot_reaper_tracks then
    seq_ensure_slot_reaper_tracks()
  end
  if full then
    if remove_seq_rendered_items then
      remove_seq_rendered_items(nil)
    end
    if seq_resync_all_regions then
      seq_resync_all_regions({ skip_remove = true, skip_arrange = true, skip_mix = true })
    end
    mix = true
  else
    if seq_undo_set_has_ids(remove_ids) and remove_seq_rendered_items_by_ids then
      remove_seq_rendered_items_by_ids(remove_ids)
    end
    if seq_undo_set_has_ids(sync_ids) then
      if clear_seq_vary_rank_cache then
        clear_seq_vary_rank_cache()
      end
      for _, region in ipairs(state.seq_regions or {}) do
        if sync_ids[region.id] then
          sync_seq_region(region, {
            skip_remove = true,
            skip_mix = true,
            skip_arrange = true,
            skip_cache_clear = true,
          })
        end
      end
    end
  end
  if mix and seq_apply_all_slot_mix_to_reaper then
    seq_apply_all_slot_mix_to_reaper()
  end
  if seq_apply_seq_order_to_arrange then
    seq_apply_seq_order_to_arrange()
  end
  if guard.refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  guard.refresh = false
  r.UpdateArrange()
  guard.block = false
  seq_undo_end_reaper(label or "Sample Map undo")
  if save_seq_project_state then
    save_seq_project_state()
  end
  if seq_mark_self_arrange_write then
    seq_mark_self_arrange_write()
  end
  if r.GetProjectStateChangeCount then
    state.seq_last_proj_change = r.GetProjectStateChangeCount(0)
  end
end

function seq_undo_own_begin(label, opts)
  if seq_undo_applying or seq_undo_is_open() then
    return false
  end
  begin_seq_undo(label, opts)
  return true
end

-- opts.lazy_reaper: don't open a REAPER undo block up front (the session may
-- end without changes); a REAPER undo point is added only if something changed.
function begin_seq_undo(label, opts)
  label = label or "Sample Map Sequencer edit"
  if seq_undo_applying then
    return label
  end
  if seq_undo_session then
    return seq_undo_session.label or label
  end
  if state.seq_pattern_confirm and seq_undo_label_is_manual_note_edit(label) then
    -- A manual note edit keeps the auditioned pattern; reverting afterwards
    -- would silently discard the user's edit.
    state.seq_pattern_confirm = nil
  end
  -- Capture under xpcall: a failure must not leave a half-open session.
  local ok, before = xpcall(seq_undo_capture_before_snapshot, function(e)
    return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
  end)
  if not ok then
    seq_undo_session = nil
    if r.ShowConsoleMsg then
      r.ShowConsoleMsg("Sample Map: error while starting sequencer undo:\n" .. tostring(before) .. "\n")
    end
    error(before, 0)
  end
  local lazy = type(opts) == "table" and opts.lazy_reaper == true
  seq_undo_session = {
    label = label,
    before = before,
    lazy_reaper = lazy,
  }
  if not lazy then
    seq_undo_begin_reaper()
  end
  return label
end

function seq_undo_label_is_manual_note_edit(label)
  local l = string.lower(tostring(label or ""))
  return l:find("note", 1, true) ~= nil
    or l:find("stutter", 1, true) ~= nil
    or l:find("decay", 1, true) ~= nil
    or l:find("cells", 1, true) ~= nil
end

-- Snapshots are never mutated after capture (restore clones field-by-field),
-- so when nothing changed since the last committed edit, reuse its `after`
-- as this session's `before` instead of storing another deep clone.
function seq_undo_capture_before_snapshot()
  local last = seq_undo_stack[#seq_undo_stack]
  if last and type(last.after) == "table" then
    local live = {
      seq_tracks = state.seq_tracks,
      selected_seq_track = state.selected_seq_track,
      seq_track_next_id = state.seq_track_next_id,
      seq_regions = state.seq_regions,
      seq_patterns = state.seq_patterns,
      seq_region_next_id = state.seq_region_next_id,
      seq_pattern_next_id = state.seq_pattern_next_id,
      seq_pool_next_id = state.seq_pool_next_id,
      selected_seq_region_id = state.selected_seq_region_id,
      seq_kit_history = state.seq_kit_history,
      seq_kit_history_next_id = state.seq_kit_history_next_id,
      seq_razors = state.seq_razors or {},
    }
    if seq_undo_values_equal(last.after, live) then
      return last.after
    end
  end
  return capture_seq_document_snapshot()
end

function end_seq_undo(label)
  if seq_undo_applying or not seq_undo_session then
    return
  end
  label = label or seq_undo_session.label or "Sample Map Sequencer edit"
  local before = seq_undo_session.before
  local lazy = seq_undo_session.lazy_reaper
  seq_undo_session = nil
  if not lazy then
    seq_undo_end_reaper(label)
  end
  local after = capture_seq_document_snapshot()
  if seq_undo_values_equal(before, after) then
    return
  end
  if lazy and r.Undo_OnStateChange2 then
    r.Undo_OnStateChange2(0, label)
  end
  seq_undo_stack[#seq_undo_stack + 1] = {
    label = label,
    before = before,
    after = after,
  }
  while #seq_undo_stack > SEQ_UNDO_MAX do
    table.remove(seq_undo_stack, 1)
  end
  seq_redo_stack = {}
end

function seq_undo()
  if seq_undo_applying or seq_undo_is_open() then
    return false
  end
  if state.seq_region_drag or state.seq_note_drag or state.seq_param_drag or state.seq_razor_drag or state.seq_lane_h_drag or state.seq_track_reorder_drag then
    return false
  end
  if #seq_undo_stack == 0 then
    return false
  end
  local entry = table.remove(seq_undo_stack)
  seq_redo_stack[#seq_redo_stack + 1] = entry
  apply_seq_undo_snapshot(entry.before, "Undo: " .. (entry.label or "Sample Map edit"))
  log("Undo: " .. (entry.label or "Sample Map edit"))
  return true
end

function seq_redo()
  if seq_undo_applying or seq_undo_is_open() then
    return false
  end
  if state.seq_region_drag or state.seq_note_drag or state.seq_param_drag or state.seq_razor_drag or state.seq_lane_h_drag or state.seq_track_reorder_drag then
    return false
  end
  if #seq_redo_stack == 0 then
    return false
  end
  local entry = table.remove(seq_redo_stack)
  seq_undo_stack[#seq_undo_stack + 1] = entry
  apply_seq_undo_snapshot(entry.after, "Redo: " .. (entry.label or "Sample Map edit"))
  log("Redo: " .. (entry.label or "Sample Map edit"))
  return true
end

function handle_seq_undo_keys()
  if imgui_text_input_active and imgui_text_input_active() then
    return false
  end
  local redo = shortcut_pressed("redo")
  local undo = shortcut_pressed("undo")
  if not redo and not undo then
    return false
  end
  if r.ImGui_SetNextFrameWantCaptureKeyboard then
    r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
  end
  if redo then
    seq_redo()
  else
    seq_undo()
  end
  return true
end

function alloc_seq_pattern()
  local id = state.seq_pattern_next_id
  state.seq_pattern_next_id = state.seq_pattern_next_id + 1
  state.seq_patterns[tostring(id)] = state.seq_patterns[tostring(id)] or { notes = {} }
  return id
end

function alloc_seq_pool()
  local id = state.seq_pool_next_id
  state.seq_pool_next_id = state.seq_pool_next_id + 1
  return id
end

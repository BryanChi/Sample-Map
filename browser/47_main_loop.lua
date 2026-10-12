-- Sample Map Browser module: main_loop
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Main loop ---------------------------------------------------------------
-- The whole frame runs under xpcall so one error never kills the defer loop.
function loop()
  if SampleMapInstance.shutdown_done then
    return
  end
  local ok, err = xpcall(sm_loop_frame, sm_error_traceback)
  if not ok then
    sm_report_error("main loop", err)
    state.sm_imgui_recover_pending = true
  end
  if SampleMapInstance.shutdown_done then
    return
  end
  if running then
    r.defer(loop)
  else
    shutdown_script("stop")
  end
end

function sm_loop_frame()
  local stop_requested = (not running)
    or (r.GetExtState(SampleMapInstance.section, SampleMapInstance.key) ~= SampleMapInstance.token)
  if ctx and r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    if not sm_imgui_try_recover_context() then
      log("ImGui context invalid; stopping loop")
      stop_requested = true
    end
  else
    -- Context survived the last error (or there was none): nothing to recover.
    state.sm_imgui_recover_pending = false
  end
  if stop_requested then
    shutdown_script(running and "shortcut" or "stop")
    return
  end

  -- UI-side calls: an error here may leave the ImGui stack unbalanced.
  local function ui_call(site, fn)
    local ok = sm_pcall(site, fn)
    if not ok then
      state.sm_imgui_recover_pending = true
    end
  end
  
  sm_pcall("stop_preview_if_transport_started", stop_preview_if_transport_started)
  sm_pcall("sync_project_state_if_needed", sync_project_state_if_needed)
  sm_pcall("ingest_seq_from_arrange", ingest_seq_from_arrange)
  sm_pcall("seq_stem_import_poll_external_request", seq_stem_import_poll_external_request)
  sm_pcall("seq_stem_import_tick", seq_stem_import_tick)
  if state.seq_random_sync_run and not state.seq_random_knob_drag then
    state.seq_random_sync_run = false
    sm_pcall("seq_flush_pending_random_sync", seq_flush_pending_random_sync)
  end

  local loading = is_library_loading()
  if loading then
    sm_pcall("process_library_load_slice", process_library_load_slice, LIBRARY_LOAD_SLICE_MS)
    loading = is_library_loading()
  end

  -- Start scan after a miss, but defer cache rewrite until after first interactive frame.
  if state._enqueue_scan_after_load then
    local scan_folders = state._enqueue_scan_after_load
    state._enqueue_scan_after_load = false
    sm_pcall("enqueue_scan", enqueue_scan, type(scan_folders) == "table" and scan_folders or nil)
  end

  if not loading then
    if SampleMapAutoCheckForUpdates then
      sm_pcall("update check", SampleMapAutoCheckForUpdates)
    end
    sm_pcall("seq_gmd_bg_tick", seq_gmd_bg_tick)
    sm_pcall("process_scan_slice", process_scan_slice)
    sm_pcall("process_waveform_slice", process_waveform_slice, 6.0)

    -- Poll removable-drive mount state so dots gray/restore without restarting.
    local now = r.time_precise()
    if (now - (state.last_volume_check_time or 0)) >= 1.5 then
      sm_pcall("refresh_scan_folder_availability", refresh_scan_folder_availability)
    end
    sm_pcall("seq_midi_poll", seq_midi_poll)
  end
  
  ui_push_theme()
  local visible, open, began = false, true, false
  local ui_ok, ui_err = xpcall(function()
  visible, open, began = begin_window()
  if visible then
    if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize then
      local wx, wy = r.ImGui_GetWindowPos(ctx)
      local ww, wh = r.ImGui_GetWindowSize(ctx)
      state.main_window_rect = { x = wx, y = wy, w = ww, h = wh }
    end
    state.block_swap_bar_input = false
    state.seq_drop_target_idx = nil
    state.seq_candidate_drop = nil
    state.seq_drum_drop = nil
    state.seq_timeline_drop_track_idx = nil
    state.seq_timeline_drop_time = nil

    if loading then
      render_library_loading_view()
    else
      -- Handle keyboard input for history navigation (only when window is visible)
      if not state.shortcut_capture_id
          and not (imgui_text_input_active and imgui_text_input_active())
          and not state.seq_region_rename then
        if shortcut_pressed("history_back") then
          navigate_history(1)   -- Go back in history to older samples (up arrow increases index)
          seq_open_history_popup()
        elseif shortcut_pressed("history_forward") then
          navigate_history(-1)  -- Go forward in history to newer samples (down arrow decreases index)
          seq_open_history_popup()
        end
      end

      render_header()

      handle_script_keyboard_shortcuts()

      local _, avail_y = r.ImGui_GetContentRegionAvail(ctx)

      local child_flags = 0
      child_flags = sm_child_border_flag()
      local child_win_flags = 0
      if r.ImGui_WindowFlags_NoNav then
        child_win_flags = child_win_flags | r.ImGui_WindowFlags_NoNav()
      end
      -- Toolbar + sequencer/map live in this child. Shift+horizontal wheel is used
      -- for timeline zoom and must not pan the whole chrome sideways.
      if r.ImGui_WindowFlags_NoScrollbar then
        child_win_flags = child_win_flags | r.ImGui_WindowFlags_NoScrollbar()
      end
      if r.ImGui_WindowFlags_NoScrollWithMouse then
        child_win_flags = child_win_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
      end

      local main_open = r.ImGui_BeginChild(ctx, "main_content", 0, avail_y, child_flags, child_win_flags)
      if main_open then
        if r.ImGui_SetScrollX then
          r.ImGui_SetScrollX(ctx, 0)
        end
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 5, 3)
        render_view_tab_switcher()
        if state.scan_running then
          r.ImGui_SameLine(ctx, 0, UI_METRICS.toolbar_gap)
          if draw_ui_button("scan_stop_toolbar", "Stop scan", nil, UI_METRICS.toolbar_h, { style = "danger", compact = true }) then
            stop_scan()
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Stop scanning and save progress.\nThe next scan will continue from here — you won't start over.")
          end
        end

        local map_in_main = state.active_view == "sample_map" and not state.sample_map_floating
        local seq_in_main = state.active_view == "sequencer" and not state.sequencer_floating

        if map_in_main then
          ui_toolbar_divider()
          render_sample_map_toolbar()
        elseif seq_in_main then
          ui_toolbar_divider()
          render_seq_top_toolbar()
        end
        r.ImGui_PopStyleVar(ctx, 2)

        if map_in_main then
          render_sample_map_body()
        elseif seq_in_main then
          render_sequencer_with_explorer()
          seq_stem_import_install_os_drop_overlay()
        else
          local empty_x, empty_y = r.ImGui_GetContentRegionAvail(ctx)
          local line1 = "Sample Map and Sequencer are in separate windows."
          local line2 = "Close a window or click its tab to dock it back."
          local base_x = r.ImGui_GetCursorPosX(ctx)
          r.ImGui_Dummy(ctx, 1, math.max(12, empty_y * 0.32))
          r.ImGui_SetCursorPosX(ctx, base_x + math.max(0, (empty_x - (r.ImGui_CalcTextSize(ctx, line1))) * 0.5))
          r.ImGui_TextColored(ctx, UI_THEME.text_dim, line1)
          r.ImGui_SetCursorPosX(ctx, base_x + math.max(0, (empty_x - (r.ImGui_CalcTextSize(ctx, line2))) * 0.5))
          r.ImGui_TextColored(ctx, UI_THEME.text_mute, line2)
        end
      end
      imgui_end_child(main_open)

    end
  end
  end, sm_error_traceback)
  end_window(visible, began)
  if ui_ok and not loading then
    ui_call("render_seq_neighbor_popup", render_seq_neighbor_popup)
    ui_call("render_seq_minimap_popup", render_seq_minimap_popup)
    ui_call("render_preview_history_popup", render_preview_history_popup)
    ui_call("render_seq_layering_window", render_seq_layering_window)
    ui_call("render_sample_map_float_window", render_sample_map_float_window)
    ui_call("render_sequencer_float_window", render_sequencer_float_window)
    ui_call("render_settings", render_settings)
    ui_call("render_scan_complete_dialog", render_scan_complete_dialog)
    ui_call("seq_stem_import_render_dialog", seq_stem_import_render_dialog)
    ui_call("render_explorer_window", render_explorer_window)
  elseif not ui_ok then
    sm_report_error("main window", ui_err)
    state.sm_imgui_recover_pending = true
  end
  if ui_ok then
    ui_call("draw_sample_drag_ghost", draw_sample_drag_ghost)
    sm_pcall("complete_pending_sample_drop", complete_pending_sample_drop)
  end
  pcall(ui_pop_theme)

  if not state._text_input_item_active_now
      and not state.seq_vary_filter_edit
      and not state.seq_region_rename then
    state._text_input_item_active = false
  end
  state._text_input_item_active_now = false

  if (not loading) and running then
    sm_pcall("seq_update_arrange_item_follow", seq_update_arrange_item_follow)
    sm_pcall("seq_render_arrange_item_overlay", seq_render_arrange_item_overlay)
    sm_pcall("seq_render_link_parent_overlay", seq_render_link_parent_overlay)
    sm_pcall("seq_pump_script_refocus", seq_pump_script_refocus)
  end

  -- Migrate/stamp cache after the first ready frame so load UI stays smooth.
  if (not loading) and state._save_library_after_load then
    state._save_library_after_load = false
    if sm_pcall("save_samples", save_samples) then
      state.tag_schema_dirty = false
    end
  end
  
  if not ((open ~= false) and running) then
    shutdown_script(open == false and "window" or "stop")
  end
end

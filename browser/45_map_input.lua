-- Sample Map Browser module: map_input
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function clear_map_left_press()
  state.map_press_x = nil
  state.map_press_y = nil
  state.map_press_pending = false
  state.map_audition_rearm = false
end

function update_map_audition_drag(mx, my)
  if not r.ImGui_IsMouseDown(ctx, 0) then
    if not state.is_left_dragging and not state.pending_waveform_drop then
      clear_map_left_press()
    end
    return
  end
  if state.is_left_dragging or state.pending_waveform_drop or state.is_dragging then
    return
  end
  -- After a blocking preview, recapture origin on the next frame so mouse
  -- movement during disk load does not start a drag-audition.
  if state.map_audition_rearm then
    state.map_press_x = mx
    state.map_press_y = my
    state.map_press_pending = true
    state.map_audition_rearm = false
    return
  end
  if not state.map_press_pending then
    return
  end
  local dx = mx - (state.map_press_x or mx)
  local dy = my - (state.map_press_y or my)
  if dx * dx + dy * dy >= MAP_AUDITION_DRAG_THRESHOLD_SQ then
    state.is_left_dragging = true
  end
end

function handle_map_view_input(hovered, mx, my, width, height, x0, y0)
  if state.map_ui_edit or state.map_ui_drag then
    return
  end
  local right_clicked = r.ImGui_IsMouseClicked(ctx, 1)  -- Right mouse button
  local right_down = r.ImGui_IsMouseDown(ctx, 1)
  local right_released = r.ImGui_IsMouseReleased(ctx, 1)
  -- Note: left_clicked detection moved to sample selection logic to prevent double detection
  
  -- Handle right-click drag for panning
  if hovered and right_clicked then
    -- Start right drag
    state.is_dragging = true
    state.is_left_dragging = false  -- Cancel left drag if right drag starts
    clear_map_left_press()
    map_zoom_snap_target()
    state.drag_start_x = mx
    state.drag_start_y = my
    state.drag_start_pan_x = state.pan_x
    state.drag_start_pan_y = state.pan_y
  elseif state.is_dragging and right_down then
    -- Continue right drag
    local dx = mx - state.drag_start_x
    local dy = my - state.drag_start_y
    state.pan_x = state.drag_start_pan_x + dx
    state.pan_y = state.drag_start_pan_y + dy

    clamp_map_pan(width, height)
    -- Don't save during drag - only save when drag ends
  elseif right_released then
    -- End right drag
    state.is_dragging = false
    state.drag_start_x = nil
    state.drag_start_y = nil
    -- Pan position not saved
  end
  
  -- Handle left-click: preview on click, drag-audition only after movement threshold
  local left_clicked = r.ImGui_IsMouseClicked(ctx, 0)  -- Left mouse button (detected here for drag logic)
  local left_released = r.ImGui_IsMouseReleased(ctx, 0)

  if hovered and left_clicked and not state.is_dragging then
    -- Arm a press; do not start drag-audition until the mouse actually moves
    state.map_press_x = mx
    state.map_press_y = my
    state.map_press_pending = true
    state.map_audition_rearm = false
    state.is_left_dragging = false
    state.last_dragged_sample_path = nil
  elseif left_released then
    -- End left drag; cleanup happens in complete_pending_sample_drop()
  end

  update_map_audition_drag(mx, my)
  
  -- Handle mouse wheel / trackpad zoom (velocity + light direct step)
  if hovered and not state.is_dragging then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then
      map_zoom_add_wheel(wheel, mx, my, width, height, x0, y0)
    end
  end

  if not state.is_dragging then
    map_zoom_update_smooth(mx, my, width, height, x0, y0)
  end
end

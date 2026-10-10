-- Sample Map Browser module: seq_popups
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_open_minimap_popup(slot, recenter, opts)
  if not slot then
    return
  end
  opts = opts or {}
  local mode = opts.mode or "track"
  local now = r.time_precise()
  local prev = state.seq_minimap_popup
  local same = prev and prev.slot_id == slot.id and (prev.mode or "track") == mode
  local anchors = state.seq_nav_anchors
  local anchor = opts.anchor
    or ((not opts.pin_anchor) and anchors and anchors[slot.id])
    or (same and prev.anchor)
    or nil
  if (not anchor or not anchor.x) and r.ImGui_GetMousePos then
    local mx, my = r.ImGui_GetMousePos(ctx)
    anchor = { x = (mx or 0) - 100, y = (my or 0) + 16, w = 200, h = 24 }
  end
  local pop = same and prev or {
    zoom = SEQ_MINIMAP_ZOOM,
    pan_x = 0,
    pan_y = 0,
  }
  pop.slot_id = slot.id
  pop.mode = mode
  pop.targets = opts.targets
  pop.origin_path = opts.origin_path
  pop.place_at_mouse = opts.place_at_mouse and true or nil
  pop.pin_anchor = opts.pin_anchor and true or nil
  pop.anchor = anchor
  pop.hovered = true
  pop.opened_at = now
  pop.idle_since = now
  pop.need_center = (not same) or (recenter ~= false)
  if opts.place_at_mouse then
    -- Force a fresh at-cursor place; don't reuse a prior fixed spot.
    pop.fixed_wx = nil
    pop.fixed_wy = nil
  end
  if not same then
    pop.samples = nil
    pop.tag = nil
    pop.zoom = SEQ_MINIMAP_ZOOM
    pop.press_x = nil
    pop.dragging = false
    pop.pan_drag = false
    pop.fixed_wx = nil
    pop.fixed_wy = nil
  end
  if mode ~= "notes" then
    pop.targets = nil
    pop.origin_path = nil
    pop.place_at_mouse = nil
    pop.pin_anchor = nil
  end
  state.seq_minimap_popup = pop
  state.seq_neighbor_popup = nil
end

function render_seq_minimap_popup()
  local pop = state.seq_minimap_popup
  if not pop then
    return
  end
  local slot = nil
  for _, s in ipairs(state.seq_tracks or {}) do
    if s.id == pop.slot_id then
      slot = s
      break
    end
  end
  if not slot then
    state.seq_minimap_popup = nil
    return
  end

  if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
    state.seq_minimap_popup = nil
    return
  end

  local anchors = state.seq_nav_anchors
  if (not pop.pin_anchor) and anchors and anchors[pop.slot_id] then
    pop.anchor = anchors[pop.slot_id]
  end
  local anchor = pop.anchor
  if not anchor or not anchor.x then
    local mx, my = r.ImGui_GetMousePos(ctx)
    anchor = { x = (mx or 40) - 100, y = (my or 40) + 16, w = 200, h = 24 }
    pop.anchor = anchor
  end

  pcall(seq_minimap_ensure_samples, pop, slot)

  local now = r.time_precise()
  local keep = pop.hovered or pop.pan_drag or pop.dragging or pop.press_x
  if keep then
    pop.idle_since = now
  end
  local age = now - (pop.idle_since or pop.opened_at or now)
  local hold = SEQ_MINIMAP_FADE_HOLD
  local fade_dur = SEQ_MINIMAP_FADE_DUR
  if (not keep) and age >= hold + fade_dur then
    state.seq_minimap_popup = nil
    return
  end
  local alpha = 1.0
  if (not keep) and age > hold then
    alpha = math.max(0.0, 1.0 - (age - hold) / fade_dur)
  end

  local map_w, map_h = SEQ_MINIMAP_SIZE, SEQ_MINIMAP_SIZE
  local pad = 6.0
  local win_w = map_w + pad * 2
  local win_h = map_h + pad * 2
  local wr = state.main_window_rect
  local wx, wy
  if pop.fixed_wx and pop.fixed_wy then
    -- Stay put after the first place_at_mouse / pinned open.
    wx, wy = pop.fixed_wx, pop.fixed_wy
  else
    wx = (anchor.x or 0) + (anchor.w or 0) * 0.5 - win_w * 0.5
    wy = (anchor.y or 0) + (anchor.h or 0) + 8.0
    if wr then
      wx = math.max(wr.x + 8, math.min(wx, wr.x + wr.w - win_w - 8))
      if wy + win_h > wr.y + wr.h - 8 then
        wy = (anchor.y or wy) - win_h - 8
      end
      wy = math.max(wr.y + 8, math.min(wy, wr.y + wr.h - win_h - 8))
    end

    if pop.place_at_mouse and r.ImGui_GetMousePos then
      local mx, my = r.ImGui_GetMousePos(ctx)
      wx = (mx or wx) - win_w * 0.5
      wy = (my or wy) - 24
      if wr then
        wx = math.max(wr.x + 8, math.min(wx, wr.x + wr.w - win_w - 8))
        wy = math.max(wr.y + 8, math.min(wy, wr.y + wr.h - win_h - 8))
      end
      pop.place_at_mouse = nil
    end
    if pop.pin_anchor or pop.mode == "notes" then
      pop.fixed_wx, pop.fixed_wy = wx, wy
    end
  end

  if pop.need_center then
    seq_minimap_center_on(pop, find_sample_by_path(pop.origin_path or (seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, seq_sample_assign_region and seq_sample_assign_region()))) or slot.sample_path), map_w, map_h)
    seq_minimap_clamp_pan(pop, map_w, map_h)
    pop.need_center = false
  end

  if r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, wx, wy, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, win_w, win_h, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end
  if r.ImGui_SetNextWindowCollapsed then
    r.ImGui_SetNextWindowCollapsed(ctx, false, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end

  local pushed_vars = 0
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_Alpha then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), alpha)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowRounding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    pushed_vars = pushed_vars + 1
  end
  local function pop_minimap_alpha()
    if pushed_vars > 0 and r.ImGui_PopStyleVar then
      r.ImGui_PopStyleVar(ctx, pushed_vars)
      pushed_vars = 0
    end
  end

  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoCollapse then flags = flags | r.ImGui_WindowFlags_NoCollapse() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  if r.ImGui_WindowFlags_NoSavedSettings then flags = flags | r.ImGui_WindowFlags_NoSavedSettings() end
  if r.ImGui_WindowFlags_NoDocking then flags = flags | r.ImGui_WindowFlags_NoDocking() end
  if r.ImGui_WindowFlags_NoNav then flags = flags | r.ImGui_WindowFlags_NoNav() end
  if r.ImGui_WindowFlags_NoFocusOnAppearing then flags = flags | r.ImGui_WindowFlags_NoFocusOnAppearing() end
  if r.ImGui_WindowFlags_NoMove then flags = flags | r.ImGui_WindowFlags_NoMove() end
  if r.ImGui_WindowFlags_NoBackground then flags = flags | r.ImGui_WindowFlags_NoBackground() end
  if r.ImGui_WindowFlags_TopMost then flags = flags | r.ImGui_WindowFlags_TopMost() end

  local began_ok, visible = pcall(r.ImGui_Begin, ctx, "##seq_minimap_popup", nil, flags)
  if not began_ok then
    pop_minimap_alpha()
    log("Mini map window failed: " .. tostring(visible))
    return
  end
  if not visible then
    pop_minimap_alpha()
    return
  end

  local hover_flags = 0
  if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
    hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
  end
  pop.hovered = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx, hover_flags) or false

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local wx0, wy0 = r.ImGui_GetWindowPos(ctx)
  local mx0 = wx0 + pad
  local my0 = wy0 + pad
  if r.ImGui_SetCursorScreenPos then
    r.ImGui_SetCursorScreenPos(ctx, mx0, my0)
  end
  r.ImGui_InvisibleButton(ctx, "##seq_minimap_area", map_w, map_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)

  local frame_bg = seq_minimap_fade_col(UI_THEME.surface or 0x121816FF, alpha)
  local frame_border = seq_minimap_fade_col(UI_THEME.border or 0x2A3830FF, alpha)
  r.ImGui_DrawList_AddRectFilled(dl, wx0, wy0, wx0 + win_w, wy0 + win_h, frame_bg, 8.0)
  r.ImGui_DrawList_AddRect(dl, wx0 + 0.5, wy0 + 0.5, wx0 + win_w - 0.5, wy0 + win_h - 0.5, frame_border, 8.0, 0, 1.0)
  r.ImGui_DrawList_AddRectFilled(dl, mx0, my0, mx0 + map_w, my0 + map_h, seq_minimap_fade_col(UI_THEME.bg or 0x0A0E0CFF, alpha), 5.0)

  local zoom = pop.zoom or SEQ_MINIMAP_ZOOM
  local pan_x = pop.pan_x or 0
  local pan_y = pop.pan_y or 0
  local samples = pop.samples or {}
  local current_path = (pop.mode == "notes" and pop.origin_path)
    or (seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, seq_sample_assign_region and seq_sample_assign_region())))
    or slot.sample_path
  local playing_path = preview_sample_obj and preview_sample_obj.path or nil
  local dot_r = 3.6
  local hit_r_sq = (dot_r * 5.0) * (dot_r * 5.0)
  local margin = dot_r * 4
  local closest, current_e, playing_e = nil, nil, nil

  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, mx0, my0, mx0 + map_w, my0 + map_h, true)
  end
  draw_seq_minimap_rulers(dl, pop, mx0, my0, map_w, map_h, alpha, false)

  for i = 1, #samples do
    local s = samples[i]
    local sx = mx0 + map_w * 0.5 + pan_x + map_w * ((s.x or 0.5) - 0.5) * zoom
    local sy = my0 + map_h * 0.5 + pan_y + map_h * ((s.y or 0.5) - 0.5) * zoom
    if sx >= mx0 - margin and sx <= mx0 + map_w + margin
        and sy >= my0 - margin and sy <= my0 + map_h + margin then
      local col = seq_minimap_fade_col(s._render_color or get_sample_dot_color(s), alpha)
      local is_current = current_path and s.path == current_path
      local is_playing = playing_path and s.path == playing_path
      if is_current then
        current_e = { s = s, px = sx, py = sy, color = col }
      elseif is_playing then
        playing_e = { s = s, px = sx, py = sy, color = col }
      else
        r.ImGui_DrawList_AddCircleFilled(dl, sx, sy, dot_r, col, 8)
      end
      if hovered then
        local dx = mx - sx
        local dy = my - sy
        local dist_sq = dx * dx + dy * dy
        if dist_sq <= hit_r_sq and (not closest or dist_sq < closest.dist_sq) then
          closest = { sample = s, px = sx, py = sy, dist_sq = dist_sq, color = col }
        end
      end
    end
  end

  local function draw_focus(e, radius, ring)
    if not e then
      return
    end
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, radius, e.color, 12)
    r.ImGui_DrawList_AddCircle(dl, e.px, e.py, radius + 2.4, seq_minimap_fade_col(ring, alpha), 12, 1.6)
  end
  draw_focus(playing_e, dot_r * 1.7, 0xE8F4FFFF)
  draw_focus(current_e, dot_r * 2.0, 0x4DE8FFFF)

  if closest then
    r.ImGui_DrawList_AddCircle(dl, closest.px, closest.py, dot_r + 2.0, closest.color, 12, 1.6)
    if r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, closest.sample.name or closest.sample.path or "")
    end
  end

  draw_seq_minimap_rulers(dl, pop, mx0, my0, map_w, map_h, alpha, true)

  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
  r.ImGui_DrawList_AddRect(dl, mx0 + 0.5, my0 + 0.5, mx0 + map_w - 0.5, my0 + map_h - 0.5,
    seq_minimap_fade_col(UI_THEME.border or 0x2A3830FF, alpha), 5.0, 0, 1.0)

  -- Right-drag pan
  if hovered and r.ImGui_IsMouseClicked(ctx, 1) then
    pop.pan_drag = true
    pop.drag_mx = mx
    pop.drag_my = my
    pop.drag_pan_x = pop.pan_x
    pop.drag_pan_y = pop.pan_y
    pop.dragging = false
    pop.press_x = nil
  elseif pop.pan_drag and r.ImGui_IsMouseDown(ctx, 1) then
    pop.pan_x = (pop.drag_pan_x or 0) + (mx - (pop.drag_mx or mx))
    pop.pan_y = (pop.drag_pan_y or 0) + (my - (pop.drag_my or my))
    seq_minimap_clamp_pan(pop, map_w, map_h)
  elseif pop.pan_drag and r.ImGui_IsMouseReleased(ctx, 1) then
    pop.pan_drag = false
  end

  -- Left click / drag-audition
  if hovered and not pop.pan_drag and r.ImGui_IsMouseClicked(ctx, 0) then
    pop.press_x = mx
    pop.press_y = my
    pop.press_sample = closest and closest.sample or nil
    pop.dragging = false
    pop.last_preview_path = nil
  elseif pop.press_x and r.ImGui_IsMouseDown(ctx, 0) then
    local dx = mx - pop.press_x
    local dy = my - pop.press_y
    if (not pop.dragging) and (dx * dx + dy * dy) > 16 then
      pop.dragging = true
    end
    if pop.dragging and closest and closest.sample
        and closest.sample.path ~= pop.last_preview_path then
      pop.last_preview_path = closest.sample.path
      preview_sample(closest.sample)
    end
  elseif pop.press_x and r.ImGui_IsMouseReleased(ctx, 0) then
    if not pop.dragging and pop.press_sample then
      seq_minimap_assign(slot, pop.press_sample)
    elseif pop.dragging and closest and closest.sample then
      seq_minimap_assign(slot, closest.sample)
    end
    pop.press_x = nil
    pop.press_sample = nil
    pop.dragging = false
  end

  -- Wheel zoom toward cursor
  if hovered and not pop.pan_drag then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then
      local old_zoom = pop.zoom or SEQ_MINIMAP_ZOOM
      local new_zoom = math.max(SEQ_MINIMAP_ZOOM_MIN, math.min(SEQ_MINIMAP_ZOOM_MAX, old_zoom * math.exp(wheel * 0.15)))
      local center_x = mx0 + map_w * 0.5 + (pop.pan_x or 0)
      local center_y = my0 + map_h * 0.5 + (pop.pan_y or 0)
      local map_norm_x = ((mx - center_x) / (map_w * old_zoom)) + 0.5
      local map_norm_y = ((my - center_y) / (map_h * old_zoom)) + 0.5
      pop.zoom = new_zoom
      pop.pan_x = mx - map_w * (map_norm_x - 0.5) * new_zoom - (mx0 + map_w * 0.5)
      pop.pan_y = my - map_h * (map_norm_y - 0.5) * new_zoom - (my0 + map_h * 0.5)
      seq_minimap_clamp_pan(pop, map_w, map_h)
    end
  end

  r.ImGui_End(ctx)
  pop_minimap_alpha()
end

PREVIEW_HISTORY_ROW_H = 20
PREVIEW_HISTORY_MAX_ROWS = 10
PREVIEW_HISTORY_WIDTH = 228

function seq_open_history_popup()
  history_compact_unique()
  if not preview_sample_obj and #(state.played_history or {}) == 0 then
    return
  end
  if not state.history_head then
    state.history_head = preview_sample_obj
  end
  local now = r.time_precise()
  local pop = state.preview_history_popup
  local reuse = pop ~= nil
  pop = pop or {}
  pop.hovered = true
  pop.opened_at = now
  pop.idle_since = now
  if not reuse or not pop.x then
    local mx, my = 40, 40
    if r.ImGui_GetMousePos then
      mx, my = r.ImGui_GetMousePos(ctx)
    end
    pop.x = (mx or 40) + 16
    pop.y = (my or 40) + 16
  end
  state.preview_history_popup = pop
end

function history_preview_item(sample)
  if not sample or not sample.path then
    return
  end
  local head = state.history_head
  if head and head.path == sample.path then
    state.history_index = 0
  else
    local idx = 0
    local hist = state.played_history or {}
    for i = 1, #hist do
      if hist[i] and hist[i].path == sample.path then
        idx = i
        break
      end
    end
    if idx == 0 then
      return
    end
    state.history_index = idx
  end
  preview_sample_from_history(sample)
end

function render_preview_history_popup()
  local pop = state.preview_history_popup
  if not pop then
    return
  end

  if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
    state.preview_history_popup = nil
    return
  end

  local now = r.time_precise()
  local keep = pop.hovered
  if keep then
    pop.idle_since = now
  end
  local age = now - (pop.idle_since or pop.opened_at or now)
  local hold = SEQ_MINIMAP_FADE_HOLD
  local fade_dur = SEQ_MINIMAP_FADE_DUR
  if (not keep) and age >= hold + fade_dur then
    state.preview_history_popup = nil
    return
  end
  local alpha = 1.0
  if (not keep) and age > hold then
    alpha = math.max(0.0, 1.0 - (age - hold) / fade_dur)
  end

  local items = history_build_items()
  if #items == 0 then
    state.preview_history_popup = nil
    return
  end

  local current_path = preview_sample_obj and preview_sample_obj.path or nil
  local sel = 1
  for i = 1, #items do
    if items[i].path == current_path then
      sel = i
      break
    end
  end

  local row_h = PREVIEW_HISTORY_ROW_H
  local max_rows = PREVIEW_HISTORY_MAX_ROWS
  local vis = math.min(max_rows, #items)
  local start_i = 1
  if #items > vis then
    start_i = math.max(1, math.min(sel - math.floor((vis - 1) * 0.5), #items - vis + 1))
  end
  local pad = 6.0
  local win_w = PREVIEW_HISTORY_WIDTH
  local win_h = pad * 2 + vis * row_h

  local wx = pop.x or 40
  local wy = pop.y or 40
  local wr = state.main_window_rect
  if wr then
    wx = math.max(wr.x + 8, math.min(wx, wr.x + wr.w - win_w - 8))
    wy = math.max(wr.y + 8, math.min(wy, wr.y + wr.h - win_h - 8))
  end
  pop.x, pop.y = wx, wy

  if r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, wx, wy, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, win_w, win_h, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end

  local pushed_vars = 0
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_Alpha then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), alpha)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowRounding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    pushed_vars = pushed_vars + 1
  end
  local function pop_hist_style()
    if pushed_vars > 0 and r.ImGui_PopStyleVar then
      r.ImGui_PopStyleVar(ctx, pushed_vars)
      pushed_vars = 0
    end
  end

  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  if r.ImGui_WindowFlags_NoCollapse then flags = flags | r.ImGui_WindowFlags_NoCollapse() end
  if r.ImGui_WindowFlags_NoSavedSettings then flags = flags | r.ImGui_WindowFlags_NoSavedSettings() end
  if r.ImGui_WindowFlags_NoDocking then flags = flags | r.ImGui_WindowFlags_NoDocking() end
  if r.ImGui_WindowFlags_NoNav then flags = flags | r.ImGui_WindowFlags_NoNav() end
  if r.ImGui_WindowFlags_NoFocusOnAppearing then flags = flags | r.ImGui_WindowFlags_NoFocusOnAppearing() end
  if r.ImGui_WindowFlags_NoMove then flags = flags | r.ImGui_WindowFlags_NoMove() end
  if r.ImGui_WindowFlags_NoBackground then flags = flags | r.ImGui_WindowFlags_NoBackground() end
  if r.ImGui_WindowFlags_TopMost then flags = flags | r.ImGui_WindowFlags_TopMost() end

  local began_ok, visible = pcall(r.ImGui_Begin, ctx, "##preview_history_popup", nil, flags)
  if not began_ok then
    pop_hist_style()
    log("History list failed: " .. tostring(visible))
    return
  end
  if not visible then
    pop_hist_style()
    return
  end

  local hover_flags = 0
  if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
    hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
  end
  pop.hovered = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx, hover_flags) or false

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local px, py = r.ImGui_GetWindowPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##preview_history_hit", win_w, win_h)
  local mx2, my2 = r.ImGui_GetMousePos(ctx)

  r.ImGui_DrawList_AddRectFilled(dl, px, py, px + win_w, py + win_h, seq_minimap_fade_col(UI_THEME.surface or 0x121816FF, alpha), 8.0)
  r.ImGui_DrawList_AddRect(dl, px + 0.5, py + 0.5, px + win_w - 0.5, py + win_h - 0.5,
    seq_minimap_fade_col(UI_THEME.border or 0x2A3830FF, alpha), 8.0, 0, 1.0)

  local clicked = nil
  for row = 0, vis - 1 do
    local i = start_i + row
    local sample = items[i]
    if sample then
      local ry = py + pad + row * row_h
      local hovered_row = mx2 >= px and mx2 <= px + win_w and my2 >= ry and my2 <= ry + row_h
      local is_cur = current_path and sample.path == current_path
      if is_cur then
        r.ImGui_DrawList_AddRectFilled(dl, px + 3, ry, px + win_w - 3, ry + row_h,
          seq_minimap_fade_col(0x1EFF5E44, alpha), 4.0)
      elseif hovered_row then
        r.ImGui_DrawList_AddRectFilled(dl, px + 3, ry, px + win_w - 3, ry + row_h,
          seq_minimap_fade_col(0xFFFFFF18, alpha), 4.0)
      end
      local col = sample._render_color or get_sample_dot_color(sample)
      local dot_x = px + 14
      local dot_y = ry + row_h * 0.5
      r.ImGui_DrawList_AddCircleFilled(dl, dot_x, dot_y, 4.0, seq_minimap_fade_col(col, alpha), 10)
      if is_cur then
        r.ImGui_DrawList_AddCircle(dl, dot_x, dot_y, 6.0, seq_minimap_fade_col(0x4DE8FFFF, alpha), 10, 1.4)
      end
      local name = sample.name
      if not name or name == "" then
        name = (sample.path and sample.path:match("([^/\\]+)$")) or sample.path or "Sample"
      end
      local text_x = px + 24
      local text_w = win_w - 32
      if seq_truncate_text_to_width then
        name = seq_truncate_text_to_width(name, text_w)
      end
      local tw, th = 0, 12
      if r.ImGui_CalcTextSize then
        tw, th = r.ImGui_CalcTextSize(ctx, name)
      end
      r.ImGui_DrawList_AddText(dl, text_x, ry + (row_h - (th or 12)) * 0.5,
        seq_minimap_fade_col(is_cur and 0xF4FFF8FF or (UI_THEME.text or 0xE8EEE8FF), alpha), name)
      if hovered_row and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then
        clicked = sample
      end
    end
  end

  r.ImGui_End(ctx)
  pop_hist_style()

  if clicked then
    history_preview_item(clicked)
    pop.idle_since = r.time_precise()
  end
end

function render_swap_mode_bar()
  if not state.seq_swap_track_id then
    return
  end

  local slot, idx = get_active_swap_slot()
  if not slot then
    clear_seq_swap_mode_state()
    return
  end
  state.seq_swap_track_idx = idx

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), UI_THEME.accent_fill)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 10, 8)

  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Swap sample")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.accent_hvr, slot.name)
  r.ImGui_SameLine(ctx)

  if state.block_swap_bar_input then
    r.ImGui_BeginDisabled(ctx)
  end

  if draw_ui_button("swap_cancel", nil, 28, 26, { icon = "close", style = "danger" }) then
    end_seq_swap_mode(false)
  end

  r.ImGui_SameLine(ctx)
  if draw_ui_button("swap_confirm", nil, 28, 26, { icon = "check", style = "success" }) then
    end_seq_swap_mode(true)
  end

  if state.block_swap_bar_input then
    r.ImGui_EndDisabled(ctx)
  end

  r.ImGui_PopStyleVar(ctx, 2)
  r.ImGui_PopStyleColor(ctx, 1)
  r.ImGui_Separator(ctx)
end

SEQ_SAMPLE_DOT_SIZE = 34.0 -- default/fallback when lane height is unknown
SEQ_TRACK_PLAY_ANIM_DURATION = 0.35
SEQ_PANEL_TRACK_ROW_H = 70.0   -- tall enough for name + mix + envelope (no [+] expand)
SEQ_PANEL_ICON_SIZE = 20.0     -- smaller icons in Sample Map track sidebar
SEQ_MIX_BTN = 14.0
SEQ_MIX_VOL_W = 52.0
SEQ_MIX_PAN_W = 40.0
SEQ_MIX_MIDI_W = 30.0
SEQ_MIX_GAP = 3.0
SEQ_MIDI_GMEM_NAME = "SampleMapMIDI"
SEQ_MIDI_JSFX_NAMES = {
  "Sample Map MIDI",
  "JS: Sample Map MIDI",
  "JS: SampleMapMIDI",
  "SampleMapMIDI",
}
SEQ_PLAYER_JSFX_NAMES = {
  "Sample Map Player",
  "JS: Sample Map Player",
  "JS: SampleMapPlayer",
  "SampleMapPlayer",
}
SEQ_PLAYER_PARAM = {
  midi_lo = 0,
  midi_hi = 1,
  pitch = 2,
  gain = 3,
  trigger = 4,
  reload = 5,
  instance_id = 6,
  vel = 7,
  overlap = 8,
  root = 9,
}
seq_player_runtime = {}
-- Ableton/Yamaha octave names so GM kick 36 displays as C1.
SEQ_MIDI_PC_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
SEQ_MIDI_ROLE_NOTES = {
  kick = 36, ["808"] = 35, snare = 38, clap = 39, rim = 37,
  tom = 45, hat = 42, ride = 51, crash = 49, perc = 54,
  bass = 48, fx = 60, vocal = 72, drum = 40,
  pad = 64, lead = 76, pluck = 67, keys = 60, guitar = 62,
}
seq_midi_voices = {}

function seq_icon_size_for_lane_h(lane_h)
  lane_h = tonumber(lane_h) or SEQ_SAMPLE_DOT_SIZE
  -- Fill most of the lane, with a little padding so the ring/pulse still fits.
  local size = lane_h - 8.0
  if size < 14.0 then size = 14.0 end
  if size > 56.0 then size = 56.0 end
  return size
end

function seq_ctrl_size_for_icon(icon_size)
  icon_size = tonumber(icon_size) or SEQ_SAMPLE_DOT_SIZE
  local ctrl = icon_size * 0.55
  if ctrl < 14.0 then ctrl = 14.0 end
  if ctrl > 22.0 then ctrl = 22.0 end
  return ctrl
end

function seq_sample_controls_item_spacing()
  local item_spacing = 8.0
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local spacing_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
    if spacing_x and spacing_x > 0 then
      item_spacing = spacing_x
    end
  end
  return item_spacing
end

-- Role -> PNG filename from the Behringer icon kit (white glyphs, tinted at draw time).
SEQ_ROLE_ICON_FILES = {
  kick = "kick.png",
  ["808"] = "808.png",
  bass = "bass.png",
  snare = "snare.png",
  clap = "clap.png",
  snap = "snap.png",
  rim = "rim.png",
  tom = "tom.png",
  hat = "hat.png",
  ride = "ride.png",
  crash = "crash.png",
  perc = "perc.png",
  fx = "fx.png",
  vocal = "vocal.png",
  drum = "drum.png",
  pad = "pad.png",
  lead = "lead.png",
  pluck = "pluck.png",
  keys = "keys.png",
  guitar = "guitar.png",
  loop = "loop.png",
  default = "default.png",
}

seq_icon_images = {
  by_role = {},
  attached_ctx = nil,
}

VFX_ICON_FILES = {
  StarHollow = "starHollow.png",
  Star = "star.png",
  Send = "send.png",
  Recv = "receive.png",
  Show = "show.png",
  Hide = "hide.png",
  Link = "link.png",
  Snapshot = "snapshot.png",
  Camera = "camera.png",
  Folder = "folder.png",
  FolderOpen = "folder_open.png",
  Settings = "settings.png",
  Update = "update.png",
  Copy = "copy.png",
  Search = "search.png",
  Trash = "trash.png",
  Graph = "graph.png",
  Undo = "undo.png",
  Volume = "volume.png",
}

vfx_icon_images = {
  by_name = {},
  attached_ctx = nil,
}

-- Icons copied from BryanChi FX Devices (src/Images).
FXD_ICON_FILES = {
  Expand = "expand.png",
  OpenInNewWin = "open-in-new-window.png",
  AddList = "add-list.png",
  Copy = "copy.png",
  Paste = "paste.png",
  Save = "save.png",
  Trash = "trash.png",
  Undo = "undo.png",
  Pin = "pin.png",
  Pinned = "pinned.png",
  Folder = "folder.png",
  FolderOpen = "folder_open.png",
  FolderAdd = "folder_add.png",
  FolderList = "folder_list.png",
  Sine = "sinewave.png",
  SmallScale = "small_scale_white.png",
  ModIcon = "Modulation Icon.png",
  ModIconHollow = "Modulation Icon hollow.png",
  ModulationArrow = "ModulationArrow.png",
  MouseL = "MouseL.png",
  MouseR = "MouseR.png",
}

fxd_icon_images = {
  by_name = {},
  attached_ctx = nil,
}

function ensure_vfx_icons()
  if not ctx or not r.ImGui_CreateImage or not r.ImGui_Attach then
    return false
  end
  local cached = vfx_icon_images.by_name.Link
  if vfx_icon_images.attached_ctx == ctx
      and cached
      and r.ImGui_ValidatePtr
      and r.ImGui_ValidatePtr(cached, "ImGui_Image*") then
    return true
  end

  vfx_icon_images.by_name = {}
  for name, filename in pairs(VFX_ICON_FILES) do
    local path = VFX_ICON_DIR .. "/" .. filename
    local ok, img = pcall(r.ImGui_CreateImage, path)
    if ok and img then
      local ok_attach = pcall(r.ImGui_Attach, ctx, img)
      if ok_attach then
        vfx_icon_images.by_name[name] = img
      end
    end
  end
  vfx_icon_images.attached_ctx = ctx
  return vfx_icon_images.by_name.Link ~= nil
end

function get_vfx_icon(name)
  ensure_vfx_icons()
  return vfx_icon_images.by_name[name]
end

function ensure_fxd_icons()
  if not ctx or not r.ImGui_CreateImage or not r.ImGui_Attach then
    return false
  end
  local cached = fxd_icon_images.by_name.Expand
  if fxd_icon_images.attached_ctx == ctx
      and cached
      and r.ImGui_ValidatePtr
      and r.ImGui_ValidatePtr(cached, "ImGui_Image*") then
    return true
  end

  fxd_icon_images.by_name = {}
  for name, filename in pairs(FXD_ICON_FILES) do
    local path = FXD_ICON_DIR .. "/" .. filename
    local ok, img = pcall(r.ImGui_CreateImage, path)
    if ok and img then
      local ok_attach = pcall(r.ImGui_Attach, ctx, img)
      if ok_attach then
        fxd_icon_images.by_name[name] = img
      end
    end
  end
  fxd_icon_images.attached_ctx = ctx
  return fxd_icon_images.by_name.Expand ~= nil
end

function get_fxd_icon(name)
  ensure_fxd_icons()
  return fxd_icon_images.by_name[name]
end

function draw_fxd_icon(dl, name, cx, cy, size, tint)
  if not dl or not name or not r.ImGui_DrawList_AddImage then
    return false
  end
  local img = get_fxd_icon(name)
  if not img then
    return false
  end
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(img, "ImGui_Image*") then
    fxd_icon_images.attached_ctx = nil
    img = get_fxd_icon(name)
    if not img then
      return false
    end
  end
  local half = (size or 12) * 0.5
  r.ImGui_DrawList_AddImage(
    dl, img,
    cx - half, cy - half, cx + half, cy + half,
    0.0, 0.0, 1.0, 1.0,
    tint or 0xFFFFFFFF
  )
  return true
end

function ensure_seq_role_icons()
  if not ctx or not r.ImGui_CreateImage or not r.ImGui_Attach then
    return false
  end
  local cached = seq_icon_images.by_role.default or seq_icon_images.by_role.kick
  if seq_icon_images.attached_ctx == ctx
      and cached
      and r.ImGui_ValidatePtr
      and r.ImGui_ValidatePtr(cached, "ImGui_Image*") then
    return true
  end

  seq_icon_images.by_role = {}
  for role, filename in pairs(SEQ_ROLE_ICON_FILES) do
    local path = SEQ_ICON_DIR .. "/" .. filename
    local ok, img = pcall(r.ImGui_CreateImage, path)
    if ok and img then
      local ok_attach = pcall(r.ImGui_Attach, ctx, img)
      if ok_attach then
        seq_icon_images.by_role[role] = img
      end
    end
  end
  seq_icon_images.attached_ctx = ctx
  return next(seq_icon_images.by_role) ~= nil
end

-- Sample Map Browser module: map_layout
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function map_ui_render_leaf(id, w, h)
  local spec = MAP_UI_SPEC[id]
  if not spec then
    return
  end
  local win_flags = map_ui_leaf_flags(spec)
  local open = r.ImGui_BeginChild(ctx, "map_ui_" .. id, math.max(1, w), math.max(1, h), 0, win_flags)
  if open then
    if id == "tracks" then
      render_seq_tracks_panel()
    elseif id == "tabs" then
      render_sample_map_tab_bar()
    elseif id == "path" then
      render_sample_path_line()
    elseif id == "wave" then
      render_waveform()
    elseif id == "map" then
      render_swap_mode_bar()
      local _, remain_y = r.ImGui_GetContentRegionAvail(ctx)
      local map_flags = map_ui_leaf_flags({ scroll = false })
      if r.ImGui_BeginChild(ctx, "sample_map_area", 0, math.max(0, remain_y), 0, map_flags) then
        render_map()
        r.ImGui_EndChild(ctx)
      end
    end
    local wx, wy = r.ImGui_GetWindowPos(ctx)
    local ww, wh = r.ImGui_GetWindowSize(ctx)
    state.map_ui_rects[id] = { x0 = wx, y0 = wy, x1 = wx + ww, y1 = wy + wh }
    map_ui_edit_overlay(id, ww, wh)
    r.ImGui_Dummy(ctx, 0, 0)
  end
  imgui_end_child(open)
end

function map_ui_render_node(node, w, h, path, row_ctx, col_ctx)
  if type(node) ~= "table" or w < 1 or h < 1 then
    return
  end
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  if node.type == "leaf" then
    state.map_ui_leaf_info[node.id] = {
      row = row_ctx,
      col = col_ctx,
      w = w,
      h = h,
    }
    map_ui_render_leaf(node.id, w, h)
    map_ui_commit_rect(x, y, w, h)
    return
  end
  if node.type == "row" then
    local widths = map_ui_row_widths(node.children or {}, w)
    local cx = x
    for i, child in ipairs(node.children or {}) do
      child._alloc_w = widths[i]
      child._alloc_h = h
      r.ImGui_SetCursorScreenPos(ctx, cx, y)
      map_ui_render_node(child, widths[i], h, path .. "r" .. i, { node = node, index = i, alloc = widths[i] }, col_ctx)
      cx = cx + widths[i]
      if i < #node.children then
        cx = cx + MAP_UI_GAP
      end
    end
  else
    local heights = map_ui_col_heights(node.children or {}, h)
    local cy = y
    for i, child in ipairs(node.children or {}) do
      child._alloc_w = w
      child._alloc_h = heights[i]
      r.ImGui_SetCursorScreenPos(ctx, x, cy)
      map_ui_render_node(child, w, heights[i], path .. "c" .. i, row_ctx, { node = node, index = i, alloc = heights[i] })
      cy = cy + heights[i]
      if i < #node.children then
        cy = cy + MAP_UI_GAP
      end
    end
  end
  map_ui_commit_rect(x, y, w, h)
end

function map_ui_update_drop()
  state.map_ui_drop = nil
  local drag = state.map_ui_drag
  if not drag then
    return
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  for id, rect in pairs(state.map_ui_rects) do
    if id ~= drag.id and mx >= rect.x0 and mx <= rect.x1 and my >= rect.y0 and my <= rect.y1 then
      local rw = math.max(1, rect.x1 - rect.x0)
      local rh = math.max(1, rect.y1 - rect.y0)
      local rel_x = (mx - rect.x0) / rw
      local rel_y = (my - rect.y0) / rh
      local edge
      -- Middle of a module swaps the two; near an edge docks beside it.
      if math.abs(rel_x - 0.5) < 0.2 and math.abs(rel_y - 0.5) < 0.2 then
        edge = "center"
      elseif math.min(rel_x, 1 - rel_x) < math.min(rel_y, 1 - rel_y) then
        edge = rel_x < 0.5 and "left" or "right"
      else
        edge = rel_y < 0.5 and "top" or "bottom"
      end
      state.map_ui_drop = { id = id, edge = edge }
    end
  end
end

function map_ui_draw_drop_preview()
  local drop = state.map_ui_drop
  if not drop then
    return
  end
  local rect = state.map_ui_rects[drop.id]
  if not rect then
    return
  end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if r.ImGui_GetForegroundDrawList then
    dl = r.ImGui_GetForegroundDrawList(ctx)
  end
  local x0, y0, x1, y1 = rect.x0, rect.y0, rect.x1, rect.y1
  local t = 0.38
  local hx0, hy0, hx1, hy1 = x0, y0, x1, y1
  if drop.edge == "center" then
    hx0, hy0, hx1, hy1 = x0 + 6, y0 + 6, x1 - 6, y1 - 6
  elseif drop.edge == "left" then
    hx1 = x0 + (x1 - x0) * t
  elseif drop.edge == "right" then
    hx0 = x1 - (x1 - x0) * t
  elseif drop.edge == "top" then
    hy1 = y0 + (y1 - y0) * t
  else
    hy0 = y1 - (y1 - y0) * t
  end
  r.ImGui_DrawList_AddRectFilled(dl, hx0, hy0, hx1, hy1, ui_accent_a(0x40), 5)
  r.ImGui_DrawList_AddRect(dl, hx0 + 1, hy0 + 1, hx1 - 1, hy1 - 1, UI_THEME.accent, 5, 0, 2)
end

-- Name of the module being moved, following the mouse.
function map_ui_draw_drag_ghost()
  local drag = state.map_ui_drag
  if not drag then
    return
  end
  local dl = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx) or r.ImGui_GetWindowDrawList(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local label = MAP_UI_LABELS[drag.id] or drag.id
  local drop = state.map_ui_drop
  if drop then
    local where = ({ left = "left of", right = "right of", top = "above", bottom = "below", center = "swap with" })[drop.edge] or ""
    label = label .. " \u{2192} " .. where .. " " .. (MAP_UI_LABELS[drop.id] or drop.id)
  else
    label = label .. "  \u{00B7}  drop on an edge to dock, the middle to swap"
  end
  map_ui_draw_badge(dl, mx + 16 + select(1, r.ImGui_CalcTextSize(ctx, label)) * 0.5, my + 20, label,
    UI_THEME.text, UI_THEME.popup_bg, UI_THEME.border_hvr)
end

function map_ui_finish_drag()
  if not state.map_ui_drag then
    return
  end
  if r.ImGui_SetMouseCursor then
    local cursor = r.ImGui_MouseCursor_ResizeAll and r.ImGui_MouseCursor_ResizeAll() or r.ImGui_MouseCursor_Hand()
    r.ImGui_SetMouseCursor(ctx, cursor)
  end
  if r.ImGui_IsMouseReleased and r.ImGui_IsMouseReleased(ctx, 0) then
    if state.map_ui_drop then
      map_ui_dock(state.map_ui_drag.id, state.map_ui_drop.id, state.map_ui_drop.edge)
      save_config()
    end
    state.map_ui_drag = nil
    state.map_ui_drop = nil
  end
end

function render_sample_map_body()
  state.map_ui_rects = {}
  state.map_ui_leaf_info = {}
  map_ui_ensure_layout()

  local origin_x, origin_y = r.ImGui_GetCursorScreenPos(ctx)
  local avail_x, tab_avail_y = r.ImGui_GetContentRegionAvail(ctx)
  tab_avail_y = math.max(0, tab_avail_y)
  local dock_explorer = explorer_is_docked_in("sample_map")
  local split_w = dock_explorer and EXPLORER_SPLIT_W or 0
  local explorer_w = dock_explorer and explorer_dock_width() or 0
  local layout_w = avail_x
  if dock_explorer then
    layout_w = math.max(180, avail_x - explorer_w - split_w)
  end
  map_ui_render_node(state.map_ui_layout, layout_w, tab_avail_y, "root")
  if state.map_ui_edit then
    map_ui_draw_edit_chrome()
    map_ui_update_drop()
    map_ui_draw_drop_preview()
    map_ui_draw_drag_ghost()
    map_ui_finish_drag()
    -- Escape leaves edit mode (cancels a move first).
    if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and not imgui_text_input_active()
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      if state.map_ui_drag then
        state.map_ui_drag = nil
        state.map_ui_drop = nil
      else
        state.map_ui_edit = false
        state.map_ui_split_drag = nil
      end
    end
  else
    state.map_ui_chrome = nil
    state.map_ui_drag = nil
    state.map_ui_drop = nil
    state.map_ui_split_drag = nil
  end
  local total_w = layout_w
  if dock_explorer then
    r.ImGui_SetCursorScreenPos(ctx, origin_x + layout_w, origin_y)
    explorer_draw_dock_splitter("sample_map", tab_avail_y, avail_x)
    r.ImGui_SetCursorScreenPos(ctx, origin_x + layout_w + split_w, origin_y)
    render_explorer_docked_panel(tab_avail_y)
    total_w = layout_w + split_w + explorer_w
  end
  map_ui_commit_rect(origin_x, origin_y, total_w, tab_avail_y)
  seq_render_env_editor_host()
end

function begin_view_float_window(title, id, default_w, default_h, ox, oy)
  local wr = state.main_window_rect
  r.ImGui_SetNextWindowSize(ctx, default_w, default_h, r.ImGui_Cond_FirstUseEver())
  if wr and r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, (wr.x or 0) + (ox or 48), (wr.y or 0) + (oy or 64), r.ImGui_Cond_FirstUseEver())
  end
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 520, 360, 4000, 3000)
  end
  local flags = 0
  if r.ImGui_WindowFlags_NoCollapse then
    flags = flags | r.ImGui_WindowFlags_NoCollapse()
  end
  if r.ImGui_WindowFlags_NoDocking then
    flags = flags | r.ImGui_WindowFlags_NoDocking()
  end
  if r.ImGui_WindowFlags_NoScrollbar then
    flags = flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  if r.ImGui_WindowFlags_NoNav then
    flags = flags | r.ImGui_WindowFlags_NoNav()
  end
  local ok, visible, open = pcall(r.ImGui_Begin, ctx, title .. "###" .. id, true, flags)
  if not ok then
    return false, true, false
  end
  if open == nil then
    open = true
  end
  return visible and true or false, open, true
end

function render_sample_map_float_window()
  if not state.sample_map_floating then
    state.sample_map_window_rect = nil
    return
  end
  local visible, open, began = begin_view_float_window("Sample Map", "sample_map_float", 980, 720, 48, 64)
  if began and visible then
    sm_mono_space_backdrop()
    if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize then
      local wx, wy = r.ImGui_GetWindowPos(ctx)
      local ww, wh = r.ImGui_GetWindowSize(ctx)
      state.sample_map_window_rect = { x = wx, y = wy, w = ww, h = wh }
    end
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 5, 3)
    render_sample_map_toolbar()
    r.ImGui_PopStyleVar(ctx, 2)
    render_sample_map_body()
    pcall(r.ImGui_End, ctx)
  end
  if open == false then
    dock_floating_view("sample_map")
  end
end

function render_sequencer_with_explorer()
  local origin_x, origin_y = r.ImGui_GetCursorScreenPos(ctx)
  local avail_x, avail_y = r.ImGui_GetContentRegionAvail(ctx)
  avail_y = math.max(0, avail_y)
  local dock_explorer = explorer_is_docked_in("sequencer")
  if not dock_explorer then
    render_sequencer_map()
    return
  end
  local split_w = EXPLORER_SPLIT_W
  local explorer_w = explorer_dock_width()
  local content_w = math.max(180, avail_x - explorer_w - split_w)
  local child_flags = 0
  if r.ImGui_ChildFlags_None then
    child_flags = r.ImGui_ChildFlags_None()
  end
  local win_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  local seq_host_open = r.ImGui_BeginChild(ctx, "seq_host_content", content_w, avail_y, child_flags, win_flags)
  if seq_host_open then
    render_sequencer_map()
  end
  imgui_end_child(seq_host_open)
  r.ImGui_SetCursorScreenPos(ctx, origin_x + content_w, origin_y)
  explorer_draw_dock_splitter("sequencer", avail_y, avail_x)
  r.ImGui_SetCursorScreenPos(ctx, origin_x + content_w + split_w, origin_y)
  render_explorer_docked_panel(avail_y)
end

function render_sequencer_float_window()
  if not state.sequencer_floating then
    state.sequencer_window_rect = nil
    return
  end
  local visible, open, began = begin_view_float_window("Sequencer", "sequencer_float", 1100, 640, 88, 108)
  if began and visible then
    sm_mono_space_backdrop()
    if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize then
      local wx, wy = r.ImGui_GetWindowPos(ctx)
      local ww, wh = r.ImGui_GetWindowSize(ctx)
      state.sequencer_window_rect = { x = wx, y = wy, w = ww, h = wh }
    end
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 5, 3)
    render_seq_top_toolbar()
    r.ImGui_PopStyleVar(ctx, 2)
    render_sequencer_with_explorer()
    seq_stem_import_install_os_drop_overlay()
    pcall(r.ImGui_End, ctx)
  end
  if open == false then
    dock_floating_view("sequencer")
  end
end

function render_map_y_axis_combo()
  local axis = map_y_axis_id()
  local changed, choice = draw_ui_combo(
    "map_y_axis",
    "Y axis",
    map_y_axis_label(axis),
    MAP_Y_AXIS_OPTIONS,
    axis,
    map_y_axis_label
  )
  if changed then
    apply_map_y_axis(choice)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "What the map Y axis uses.\nBrightness = dark vs clicky.\nDominant frequency = pitch.\nWeight = heavy (sub/body) vs light (thin/clicky).")
  end
end

function render_filter_input(reserve_right)
  local function draw_search_icon(dl, x, y, height, color)
    local size = math.min(height - 4, 16)
    local lens_r = size * 0.32
    local cx = x + size * 0.45
    local cy = y + height * 0.5
    r.ImGui_DrawList_AddCircle(dl, cx, cy, lens_r, color, 16, 1.4)
    local hx = cx + lens_r * 0.62
    local hy = cy + lens_r * 0.62
    r.ImGui_DrawList_AddLine(dl, hx, hy, hx + size * 0.30, hy + size * 0.30, color, 1.6)
  end

  local function collect_active_tags_in_display_order()
    local ordered = {}
    if not state.active_tags or next(state.active_tags) == nil then
      return ordered
    end

    for tag, active in pairs(state.active_tags) do
      if active then
        ordered[#ordered + 1] = tag
      end
    end

    sm_sort_ci(ordered)

    return ordered
  end

  -- "+N" overflow labels draw as the dotless "__hidden_tags__" chip.
  -- Measured with the same compact padding they are drawn with.
  local function calc_tag_button_width(label)
    tag_chips_compact_push()
    local w = tag_chip_width(label, label:sub(1, 1) == "+" and "__hidden_tags__" or label)
    tag_chips_compact_pop()
    return w
  end

  local function calc_compact_button_width(label)
    local text_w = r.ImGui_CalcTextSize(ctx, label)
    local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
    return text_w + ((pad_x or 4) * 0.65) * 2
  end

  local avail_x = r.ImGui_GetContentRegionAvail(ctx)
  local loop_reserve = 132
  if reserve_right and reserve_right > 0 then
    -- The caller keeps room on this row for controls pinned to the right.
    avail_x = math.max(220, avail_x - reserve_right)
    loop_reserve = 0
  end
  local filter_height = UI_METRICS.toolbar_h
  local icon_pad = 22
  local right_pad = 6
  local min_input_width = 72
  local spacing = 4
  local input_target
  if avail_x > 300 then
    input_target = math.max(180, math.min(280, avail_x - loop_reserve))
  else
    input_target = math.max(140, math.min(280, avail_x - 8))
  end
  local max_bar = avail_x > 300 and math.max(140, avail_x - loop_reserve) or math.max(140, avail_x - 8)
  local all_active_tags = collect_active_tags_in_display_order()
  local has_active_tags = #all_active_tags > 0
  local active_tags = {}
  for _, tag in ipairs(all_active_tags) do
    if not should_hide_active_tag_in_search_bar(tag) then
      active_tags[#active_tags + 1] = tag
    end
  end
  local clear_label = "Clear"
  local clear_width = has_active_tags and calc_compact_button_width(clear_label) or 0

  local function tags_block_width(tags)
    local w = 0
    for i, tag in ipairs(tags) do
      if i > 1 then
        w = w + spacing
      end
      w = w + calc_tag_button_width(tag)
    end
    return w
  end

  local function trailing_width(tags_w)
    local w = 0
    if tags_w > 0 then
      w = w + spacing + tags_w
    end
    if has_active_tags then
      w = w + spacing + clear_width
    end
    return w
  end

  local desired_tags_w = tags_block_width(active_tags)
  local desired = icon_pad + input_target + trailing_width(desired_tags_w) + right_pad
  local filter_width = math.min(desired, max_bar)
  local tag_budget = filter_width - icon_pad - min_input_width - right_pad
  if has_active_tags then
    tag_budget = tag_budget - spacing - clear_width
  end
  tag_budget = math.max(0, tag_budget)

  local visible_tags = {}
  local used_width = 0
  for _, tag in ipairs(active_tags) do
    local tag_width = calc_tag_button_width(tag)
    local extra_spacing = (#visible_tags > 0) and spacing or 0
    if used_width + extra_spacing + tag_width <= tag_budget then
      visible_tags[#visible_tags + 1] = tag
      used_width = used_width + extra_spacing + tag_width
    else
      break
    end
  end

  local hidden_count = #active_tags - #visible_tags
  if hidden_count > 0 then
    local hidden_label = "+" .. tostring(hidden_count)
    local hidden_width = calc_tag_button_width(hidden_label)
    local extra_spacing = (#visible_tags > 0) and spacing or 0
    while #visible_tags > 0 and used_width + extra_spacing + hidden_width > tag_budget do
      local removed = table.remove(visible_tags)
      used_width = used_width - calc_tag_button_width(removed)
      if #visible_tags > 0 then
        used_width = used_width - spacing
      end
      hidden_count = hidden_count + 1
      hidden_label = "+" .. tostring(hidden_count)
      hidden_width = calc_tag_button_width(hidden_label)
      extra_spacing = (#visible_tags > 0) and spacing or 0
    end
    if used_width + extra_spacing + hidden_width <= tag_budget then
      visible_tags[#visible_tags + 1] = hidden_label
      used_width = used_width + extra_spacing + hidden_width
    end
  end

  filter_width = math.min(max_bar, icon_pad + math.max(min_input_width, input_target) + trailing_width(used_width) + right_pad)
  local input_width = math.max(min_input_width, filter_width - icon_pad - trailing_width(used_width) - right_pad)

  local child_flags = 0
  child_flags = sm_child_border_flag()
  local child_window_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  if r.ImGui_BeginChild(ctx, "sample_filter_field", filter_width, filter_height, 0, child_window_flags) then
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x0, y0 = r.ImGui_GetWindowPos(ctx)
    local hovered_field = r.ImGui_IsWindowHovered(ctx)
    ui_draw_panel(
      dl, x0, y0, x0 + filter_width, y0 + filter_height, filter_height * 0.5,
      hovered_field and UI_THEME.surface_hvr or UI_THEME.surface,
      hovered_field and UI_THEME.border_hvr or UI_THEME.border,
      hovered_field, false
    )
    draw_search_icon(dl, x0 + 6, y0 + 3, filter_height - 6, hovered_field and UI_THEME.text_dim or UI_THEME.text_mute)

    r.ImGui_SetCursorPosX(ctx, icon_pad)
    r.ImGui_SetCursorPosY(ctx, 4)
    r.ImGui_SetNextItemWidth(ctx, input_width)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)

    local ret, input
    if r.ImGui_InputTextWithHint then
      local hint = "Search samples..."
      if has_active_tags then
        hint = "Type to refine..."
      elseif state.tags_hide_until_search and not state.tag_band_open then
        hint = "Search or pick tags..."
      end
      ret, input = r.ImGui_InputTextWithHint(
        ctx, "##sample_filter",
        hint,
        state.filter or ""
      )
    else
      ret, input = r.ImGui_InputText(ctx, "##sample_filter", state.filter or "", 256)
    end
    seq_mark_text_input_item()
    r.ImGui_PopStyleColor(ctx, 4)

    if ret or input ~= nil then
      state.filter = input or ""
    end
    local input_active = (r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx))
      or (r.ImGui_IsItemDeactivated and r.ImGui_IsItemDeactivated(ctx))
      or (r.ImGui_IsItemFocused and r.ImGui_IsItemFocused(ctx))
    -- Escape clears whatever filter is applied: search text, tags, folders.
    -- Left alone while another field, a popup or layout edit wants the key.
    if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
        and not state.map_ui_edit
        and (input_active or not imgui_text_input_active())
        and not (r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopup
          and r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopup()))
        and (not r.ImGui_IsWindowFocused or not r.ImGui_FocusedFlags_RootAndChildWindows
          or r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())) then
      if (state.filter or "") ~= "" or has_active_tags or #folder_filter_list() > 0 then
        state.filter = ""
        state.active_tags = {}
        state.selected_tag_parents = {}
        state.folder_filter_paths = {}
      end
    end
    local input_hovered = r.ImGui_IsItemHovered(ctx)
    -- Only while typing: focus can linger on the field after a click elsewhere.
    state.sample_filter_focused = (r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx)) and true or false
    local _, input_y1 = r.ImGui_GetItemRectMax(ctx)
    local _, input_y0 = r.ImGui_GetItemRectMin(ctx)

    tag_chips_compact_push()
    for _, tag in ipairs(visible_tags) do
      r.ImGui_SameLine(ctx, 0, spacing)
      -- Compact pills are shorter than the field; centre them on it.
      local _, th = r.ImGui_CalcTextSize(ctx, tag)
      local chip_h = th + TAG_CHIP_COMPACT_PAD_Y * 2
      local _, wy = r.ImGui_GetWindowPos(ctx)
      r.ImGui_SetCursorPosY(ctx, (input_y0 + input_y1) * 0.5 - chip_h * 0.5 - wy)
      if tag:sub(1, 1) == "+" then
        draw_tag_button(ctx, tag, false, "__hidden_tags__", "filter_active_", { allow_delete = false })
      else
        if draw_tag_button(ctx, tag, true, tag, "filter_active_") then
          state.active_tags[tag] = nil
        end
      end
    end
    tag_chips_compact_pop()

    if has_active_tags then
      r.ImGui_SameLine(ctx, 0, spacing)
      r.ImGui_SetCursorPosY(ctx, 4)
      if draw_ui_button("filter_clear_active_tags", clear_label, nil, nil, { compact = true, style = "danger" }) then
        state.active_tags = {}
        state.selected_tag_parents = {}
      end
    end

    local enter_pressed = false
    if r.ImGui_IsKeyPressed and r.ImGui_Key_Enter
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false) then
      enter_pressed = true
    elseif r.ImGui_IsKeyPressed and r.ImGui_Key_KeypadEnter
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter(), false) then
      enter_pressed = true
    end
    if enter_pressed and input_active then
      preview_random_filtered_sample()
    end
    if input_hovered then
      r.ImGui_SetTooltip(ctx, "Matches file names and folder paths.\nPress Enter to play a random result.")
    end

    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopStyleVar(ctx)
end

-- Copies every sample's coordinates and summary ranges to the clipboard
-- (Tools → Debug). log() only feeds an in-memory buffer nobody can read.
function debug_log_sample_coordinates()
  local out = {}
  local function add(line)
    out[#out + 1] = line
  end
  add("=== DEBUG: Sample Coordinates ===")
  add("Total samples: " .. #state.samples)
  if #state.samples > 0 then
    local x_min, x_max = state.samples[1].x or 0.5, state.samples[1].x or 0.5
    local y_min, y_max = state.samples[1].y or 0.5, state.samples[1].y or 0.5
    local freq_min, freq_max = state.samples[1].dominant_freq or 440.0, state.samples[1].dominant_freq or 440.0
    local rms_min, rms_max = state.samples[1].rms_energy or 0.0, state.samples[1].rms_energy or 0.0
    local size_min, size_max = state.samples[1].file_size or 0, state.samples[1].file_size or 0
    for i, s in ipairs(state.samples) do
      local x = s.x or 0.5
      local y = s.y or 0.5
      local freq = s.dominant_freq or 440.0
      local rms = s.rms_energy or 0.0
      local size = s.file_size or 0
      add(string.format("Sample %d: name='%s', freq=%.1f Hz, bright=%.1f, weight=%.2f, rms=%.6f, size=%d bytes, x=%.6f, y=%.6f",
          i, s.name or "unknown", freq, s.brightness or 0, s.sub_weight or 0, rms, size, x, y))
      x_min = math.min(x_min, x)
      x_max = math.max(x_max, x)
      y_min = math.min(y_min, y)
      y_max = math.max(y_max, y)
      freq_min = math.min(freq_min, freq)
      freq_max = math.max(freq_max, freq)
      rms_min = math.min(rms_min, rms)
      rms_max = math.max(rms_max, rms)
      size_min = math.min(size_min, size)
      size_max = math.max(size_max, size)
    end
    add("--- Summary ---")
    add(string.format("X range: %.6f to %.6f (span: %.6f)", x_min, x_max, x_max - x_min))
    add(string.format("Y range: %.6f to %.6f (span: %.6f)", y_min, y_max, y_max - y_min))
    add(string.format("Frequency range: %.1f Hz to %.1f Hz", freq_min, freq_max))
    add(string.format("RMS range: %.6f to %.6f", rms_min, rms_max))
    add(string.format("File size range: %d to %d bytes", size_min, size_max))
  else
    add("No samples to debug")
  end
  add("=== End Debug ===")
  if r.ImGui_SetClipboardText then
    r.ImGui_SetClipboardText(ctx, table.concat(out, "\n"))
    sm_notify(string.format("Copied coordinates of %d sample%s to the clipboard", #state.samples, #state.samples == 1 and "" or "s"))
  end
end

function clear_all_folders_and_samples()
  local msg = "Remove every scan folder and clear the sample index?\n\n"
    .. "Your audio files are not touched, but the map will be empty until you add folders and rescan."
  if r.ShowMessageBox(msg, "Clear library", 4) ~= 6 then
    return
  end
  state.folders = {}
  filter_samples_by_folders()  -- This will clear samples and tag data
  state.scan_enum = nil
  state.scan_queue = {}
  state.scan_running = false
  state.scan_started = 0
  clear_sample_cache()
  save_config()
  sm_notify("Cleared folders and samples")
end

function menu_item_tooltip(text)
  if text and r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, text)
  end
end

function render_header()
  if not r.ImGui_BeginMenuBar(ctx) then
    return
  end
  -- Monolith Space: Barlow caps on the bar, Inter Tight in the dropdowns.
  local bar_font = ui_push_font("cond")

  -- Library: scanning and the index itself.
  if r.ImGui_BeginMenu(ctx, ui_menu_label("Library")) then
    local menu_font = ui_push_font("body")
    if state.scan_running then
      if r.ImGui_MenuItem(ctx, "Stop Scan") then
        stop_scan()
      end
      menu_item_tooltip("Stop scanning and save progress.\nThe next scan will continue from here — you won't start over.")
    else
      local label = (#state.scan_queue > 0) and "Resume Scan" or "Rescan"
      if r.ImGui_MenuItem(ctx, label) then
        start_scan()
      end
      if #state.scan_queue > 0 then
        menu_item_tooltip(string.format(
          "Continue the unfinished scan (%d file(s) left).\nAlready indexed samples are kept.",
          #state.scan_queue
        ))
      else
        menu_item_tooltip("Scan folders for new, changed and removed files.\nAlready indexed samples are skipped.")
      end
      if #state.scan_queue == 0 then
        if r.ImGui_MenuItem(ctx, "Quick Rescan") then
          start_scan(nil, true)
        end
        menu_item_tooltip("Only look for new and removed files (faster on big libraries).\nA file edited in place keeps its old analysis until a full Rescan.")
      end
    end
    if r.ImGui_MenuItem(ctx, "Scan in Background (slower)", nil, scan_in_background()) then
      set_scan_background(not scan_in_background())
    end
    menu_item_tooltip("Scans use less of the computer so REAPER and the map stay quick to use.\nThey take longer. Progress shows in the toolbar either way.")
    if r.ImGui_MenuItem(ctx, "Re-tag Library…", nil, false, not retag_running() and not state.scan_running) then
      sm_start_retag()
    end
    menu_item_tooltip("Work out every sample's tags again from its name, folders and saved analysis\n(no rescan). Shows what would change before anything is applied.")
    if r.ImGui_MenuItem(ctx, "Manage Scan Folders…") then
      state.settings_open = true
      state.settings_section_open = state.settings_section_open or {}
      state.settings_section_open["Scan Folders"] = true
    end

    r.ImGui_Separator(ctx)
    if r.ImGui_BeginMenu(ctx, "Re-analyze") then
      if r.ImGui_MenuItem(ctx, "Incomplete Samples") then
        enqueue_incomplete_analysis()
      end
      menu_item_tooltip("Analyze samples that are missing any analysis data.")
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Effective Range") then
        enqueue_effective_range_analysis()
      end
      menu_item_tooltip("Recompute the audible length (trailing silence cropped) of every sample.\nRuns the full analysis, so loop/one-shot is refreshed too.")
      if r.ImGui_MenuItem(ctx, "Transient / Sustain") then
        enqueue_transient_sustain_analysis()
      end
      menu_item_tooltip("Recompute the transient/sustain split of every drum one-shot.")
      if r.ImGui_MenuItem(ctx, "Loop / One-shot") then
        enqueue_playback_type_analysis()
      end
      menu_item_tooltip("Reclassify every sample as loop or one-shot.\nRuns the full analysis, so the effective range is refreshed too.")
      if r.ImGui_MenuItem(ctx, "Weight") then
        enqueue_weight_analysis()
      end
      menu_item_tooltip("Recompute weight for every sample (skips crop, loop/one-shot, and transients).\nUse this after the weight formula changes.")
      if state.analyzer_numpy_missing and not state.analyzer_numpy_install_started then
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Install numpy…") then
          sm_install_numpy()
        end
        menu_item_tooltip("numpy was not found for the analyzer's Python.\nInstalling it makes analysis faster.")
      end
      r.ImGui_EndMenu(ctx)
    end

    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Clear All Folders and Samples…") then
      clear_all_folders_and_samples()
    end
    ui_pop_font(menu_font)
    r.ImGui_EndMenu(ctx)
  end

  -- View: which panels are visible and how tags are laid out.
  if r.ImGui_BeginMenu(ctx, ui_menu_label("View")) then
    local menu_font = ui_push_font("body")
    local map_floating = state.sample_map_floating
    local seq_floating = state.sequencer_floating
    if r.ImGui_MenuItem(ctx, "Sample Map", nil, state.active_view == "sample_map" and not map_floating) then
      if map_floating then
        dock_floating_view("sample_map")
      end
      state.active_view = "sample_map"
      save_config()
    end
    if r.ImGui_MenuItem(ctx, "Sequencer", nil, state.active_view == "sequencer" and not seq_floating) then
      if seq_floating then
        dock_floating_view("sequencer")
      end
      state.active_view = "sequencer"
      save_config()
    end
    if r.ImGui_MenuItem(ctx, "File Explorer", nil, state.explorer_open) then
      state.explorer_open = not state.explorer_open
      save_config()
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Sample Map in Separate Window", nil, map_floating and true or false) then
      if map_floating then dock_floating_view("sample_map") else pop_out_view("sample_map") end
    end
    if r.ImGui_MenuItem(ctx, "Sequencer in Separate Window", nil, seq_floating and true or false) then
      if seq_floating then dock_floating_view("sequencer") else pop_out_view("sequencer") end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Tag Groups on Search Row", nil, tag_groups_on_search_row()) then
      set_tag_groups_on_search_row(not tag_groups_on_search_row())
    end
    menu_item_tooltip("Drum, Melodic, Library and Loop / One shot sit on the search row.\nClick a group to show its tags.\nTurn off to list every tag in rows under the search field.")
    if r.ImGui_MenuItem(ctx, "Show Guessed Drum Tags", nil, show_guessed_tags()) then
      set_show_guessed_tags(not show_guessed_tags())
    end
    menu_item_tooltip("One-shots whose names don't say what they are get a drum type guessed from the sound\n(kick, snare, clap, hat, crash, tom, perc). Guesses count in tag filters and dot colours.")
    if r.ImGui_MenuItem(ctx, "Map: Frequency Bands and Length Zones", nil, map_guides_enabled()) then
      state.map_bands = not map_guides_enabled()
      save_config()
    end
    menu_item_tooltip("Shade the map into SUB ... AIR bands and mark HITS / ONE-SHOTS / PHRASES / LOOPS by length.")
    if r.ImGui_MenuItem(ctx, "Map: Tag Labels", nil, map_atlas_enabled()) then
      state.map_atlas = not map_atlas_enabled()
      save_config()
    end
    menu_item_tooltip("Name each tag's cluster (KICKS, HATS ...) with its count.\nClick a label to show only that tag; hover it to highlight its stars.")
    if r.ImGui_MenuItem(ctx, "Map: Constellation Lines When Zoomed In", nil, map_constellations_enabled()) then
      state.map_constellations = not map_constellations_enabled()
      save_config()
    end
    menu_item_tooltip("Join nearby samples of the same tag with faint lines once you zoom in.")
    if r.ImGui_MenuItem(ctx, "Map: Overview When Zoomed In", nil, map_overview_enabled()) then
      state.map_overview = not map_overview_enabled()
      save_config()
    end
    menu_item_tooltip("A small map of the whole library with your view boxed.\nClick or drag in it to move around.")
    if r.ImGui_MenuItem(ctx, "Hide Tags Until Search Is Clicked", nil, state.tags_hide_until_search == true) then
      set_tags_hide_until_search(not state.tags_hide_until_search)
    end
    menu_item_tooltip("Keep the Sample Map tag rows hidden.\nClick the search field to show them.")
    if r.ImGui_BeginMenu(ctx, "Collapse Children Tags", not tag_groups_on_search_row()) then
      local mode = state.collapse_children_tags or "off"
      if r.ImGui_MenuItem(ctx, "Off", nil, mode == "off") then
        set_collapse_children_tags_mode("off")
      end
      if r.ImGui_MenuItem(ctx, "On", nil, mode == "on") then
        set_collapse_children_tags_mode("on")
      end
      if r.ImGui_MenuItem(ctx, "Dynamic", nil, mode == "dynamic") then
        set_collapse_children_tags_mode("dynamic")
      end
      if r.ImGui_IsItemHovered(ctx) then
        local threshold = state.collapse_children_tags_width or 1100
        r.ImGui_SetTooltip(ctx, string.format(
          "On when the window is %.0f px wide or narrower.\nChange this width in Settings.",
          threshold
        ))
      end
      r.ImGui_EndMenu(ctx)
    end
    ui_pop_font(menu_font)
    r.ImGui_EndMenu(ctx)
  end

  -- Tools: diagnostics.
  if r.ImGui_BeginMenu(ctx, ui_menu_label("Tools")) then
    local menu_font = ui_push_font("body")
    if r.ImGui_MenuItem(ctx, "Copy Scan Logs") then
      local logs_text = get_scan_logs_text()
      if logs_text and logs_text ~= "" then
        r.ImGui_SetClipboardText(ctx, logs_text)
        sm_notify("Scan logs copied to clipboard (" .. tostring(#state.scan_logs) .. " entries)")
      else
        sm_notify("No scan logs to copy yet", "warn")
      end
    end
    if r.ImGui_BeginMenu(ctx, "Debug") then
      if r.ImGui_MenuItem(ctx, "Copy Sample Coordinates") then
        debug_log_sample_coordinates()
      end
      r.ImGui_EndMenu(ctx)
    end
    ui_pop_font(menu_font)
    r.ImGui_EndMenu(ctx)
  end

  if r.ImGui_MenuItem(ctx, ui_menu_label("Song Starter"), nil, state.song_starter and state.song_starter.open) then
    ss_toggle_window()
  end
  menu_item_tooltip("Pick loops for drums, bass, chords... matched to one key and tempo.\nPreview them together, re-roll parts, add them to the project.")

  if r.ImGui_MenuItem(ctx, ui_menu_label("Settings"), nil, state.settings_open) then
    state.settings_open = not state.settings_open
  end

  if r.ImGui_MenuItem(ctx, ui_menu_label("Feedback")) then
    sm_open_feedback()
  end
  -- green count on its corner: bug recordings waiting to be sent
  local fb_saved = SM_FEEDBACK and SM_FEEDBACK.RecordingCount and SM_FEEDBACK.RecordingCount() or 0
  if fb_saved > 0 then
    local _, fy = r.ImGui_GetItemRectMin(ctx)
    local fx = r.ImGui_GetItemRectMax(ctx)
    local n = fb_saved > 9 and "9+" or tostring(fb_saved)
    local tw, th = r.ImGui_CalcTextSize(ctx, n)
    local fdl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddCircleFilled(fdl, fx - 3, fy + 5, 7, 0x49CC85FF)
    r.ImGui_DrawList_AddText(fdl, fx - 3 - tw / 2, fy + 5 - th / 2, 0x000000FF, n)
  end
  menu_item_tooltip("Report a bug or suggest an idea.\nYou can add pictures and the usage log; it goes to the developer on GitHub.")

  if SampleMapUpdateState and SampleMapUpdateState.show_update_icon then
    r.ImGui_SameLine(ctx)
    local update_img = get_vfx_icon and get_vfx_icon("Update")
    local clicked = false
    if update_img and r.ImGui_ImageButton then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFFFFFF22)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFFFFFF18)
      local ok_img, img_clicked = pcall(r.ImGui_ImageButton, ctx, "##sample_map_update_icon", update_img, 16, 16)
      r.ImGui_PopStyleColor(ctx, 3)
      clicked = ok_img and img_clicked
    elseif r.ImGui_MenuItem(ctx, "Update") then
      clicked = true
    end
    if r.ImGui_IsItemHovered(ctx) then
      local latest = SampleMapUpdateState.latest_release_tag or "new version"
      r.ImGui_SetTooltip(ctx, "Update available: " .. tostring(latest) .. "\nOpen Settings → Updates")
    end
    if clicked and SampleMapOpenUpdateSettings then
      SampleMapOpenUpdateSettings()
    end
  end

  local midi_h = 18
  local midi_w = seq_midi_arm_button_width(midi_h)
  local knob_sz = 16
  local knob_gap = 8
  local right_w = knob_sz + knob_gap + midi_w
  local remain = r.ImGui_GetContentRegionAvail(ctx)
  if type(remain) == "number" and remain > right_w + 16 then
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, remain - right_w - 10, 1)
  end
  r.ImGui_SameLine(ctx)
  draw_preview_volume_knob(knob_sz)
  r.ImGui_SameLine(ctx, 0, knob_gap)
  render_seq_midi_arm_icon_button("seq_midi_arm_menubar", midi_h)

  ui_pop_font(bar_font)
  r.ImGui_EndMenuBar(ctx)
end


function settings_search_query()
  local q = tostring(state.settings_search or "")
  q = string.lower((string.match(q, "^%s*(.-)%s*$")) or "")
  return q
end

function settings_search_active()
  return settings_search_query() ~= ""
end

function settings_matches(...)
  local q = settings_search_query()
  if q == "" then
    return true
  end
  local n = select("#", ...)
  local i
  for i = 1, n do
    local s = select(i, ...)
    if type(s) == "string" and s ~= "" then
      if string.find(string.lower(s), q, 1, true) then
        return true
      end
    end
  end
  return false
end

function settings_show(...)
  if not settings_search_active() then
    return true
  end
  if state.settings_filter_section_title_hit then
    return true
  end
  return settings_matches(...)
end

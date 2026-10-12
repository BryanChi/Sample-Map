-- Sample Map Browser module: map_tabs
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function render_view_tab_switcher()
  local icon_size = 15
  local btn_h = UI_METRICS.toolbar_h
  local pad_x = 10
  local icon_text_gap = 6
  local tab_gap = 3
  local track_pad = 3

  local function draw_sample_map_icon(dl, x0, y0, sz, color, accent)
    local pad = sz * 0.16
    local ix0 = x0 + pad
    local iy0 = y0 + pad
    local ix1 = x0 + sz - pad
    local iy1 = y0 + sz - pad
    local w = ix1 - ix0
    local h = iy1 - iy0
    r.ImGui_DrawList_AddRect(dl, ix0, iy0, ix1, iy1, color, 3.0, 0, 1.2)
    local mid_x = ix0 + w * 0.5
    local mid_y = iy0 + h * 0.5
    local cr, cg, cb = extract_rgb_rrgbbaa(color)
    local axis_color = build_color_rrgbbaa(cr, cg, cb, 70)
    r.ImGui_DrawList_AddLine(dl, mid_x, iy0 + 2, mid_x, iy1 - 2, axis_color, 1.0)
    r.ImGui_DrawList_AddLine(dl, ix0 + 2, mid_y, ix1 - 2, mid_y, axis_color, 1.0)
    local dots = {
      {0.20, 0.24, 2.2, accent},
      {0.58, 0.18, 1.6, color},
      {0.34, 0.56, 2.4, accent},
      {0.76, 0.58, 1.5, color},
      {0.16, 0.70, 1.8, color},
      {0.52, 0.80, 2.0, accent},
    }
    for _, dot in ipairs(dots) do
      r.ImGui_DrawList_AddCircleFilled(dl, ix0 + w * dot[1], iy0 + h * dot[2], dot[3], dot[4], 12)
    end
  end

  local function draw_sequencer_icon(dl, x0, y0, sz, color, accent)
    local pad = sz * 0.14
    local ix0 = x0 + pad
    local iy0 = y0 + pad
    local ix1 = x0 + sz - pad
    local iy1 = y0 + sz - pad
    local w = ix1 - ix0
    local h = iy1 - iy0
    local cols, rows, gap = 4, 3, 1.6
    local cell_w = (w - gap * (cols - 1)) / cols
    local cell_h = (h - gap * (rows - 1)) / rows
    local cr, cg, cb = extract_rgb_rrgbbaa(color)
    local inactive_color = build_color_rrgbbaa(cr, cg, cb, 90)
    local active_steps = { {1, 3}, {2, 1, 4}, {2, 3} }
    for row = 1, rows do
      for col = 1, cols do
        local cx0 = ix0 + (col - 1) * (cell_w + gap)
        local cy0 = iy0 + (row - 1) * (cell_h + gap)
        local is_active = false
        for _, active_col in ipairs(active_steps[row] or {}) do
          if active_col == col then is_active = true break end
        end
        if is_active then
          r.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx0 + cell_w, cy0 + cell_h, accent, 2.0)
        else
          r.ImGui_DrawList_AddRect(dl, cx0, cy0, cx0 + cell_w, cy0 + cell_h, inactive_color, 2.0, 0, 1.0)
        end
      end
    end
  end

  local tabs = {
    { id = "sample_map", label = "Sample Map", icon = draw_sample_map_icon },
    { id = "sequencer", label = "Sequencer", icon = draw_sequencer_icon },
  }
  local expand_w = 16
  local expand_gap = 4
  local widths = {}
  local total_w = track_pad * 2 + tab_gap * (#tabs - 1)
  for i, tab in ipairs(tabs) do
    local text_w = r.ImGui_CalcTextSize(ctx, tab.label)
    widths[i] = pad_x + icon_size + icon_text_gap + text_w + expand_gap + expand_w + pad_x
    total_w = total_w + widths[i]
  end

  local track_x, track_y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  ui_draw_panel(dl, track_x, track_y, track_x + total_w, track_y + btn_h, 9.0, UI_THEME.bg_panel, UI_THEME.border, false, false)
  local inner_h = btn_h
  r.ImGui_SetCursorScreenPos(ctx, track_x + track_pad, track_y)

  for i, tab in ipairs(tabs) do
    if i > 1 then
      r.ImGui_SameLine(ctx, 0, tab_gap)
    end
    local floating = (tab.id == "sample_map" and state.sample_map_floating)
      or (tab.id == "sequencer" and state.sequencer_floating)
    local active = state.active_view == tab.id and not floating
    local clicked = r.ImGui_InvisibleButton(ctx, "##view_tab_" .. tab.id, widths[i], inner_h)
    local x0, y0 = r.ImGui_GetItemRectMin(ctx)
    local x1, y1 = r.ImGui_GetItemRectMax(ctx)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local pressed = r.ImGui_IsItemActive(ctx)
    local expand_x0 = x1 - pad_x - expand_w
    local mx = select(1, r.ImGui_GetMousePos(ctx))
    local on_expand = hovered and mx and mx >= (expand_x0 - 2)

    if clicked then
      if on_expand then
        if floating then
          dock_floating_view(tab.id)
        else
          pop_out_view(tab.id)
        end
      elseif floating then
        dock_floating_view(tab.id)
      elseif state.active_view ~= tab.id then
        state.active_view = tab.id
        save_config()
      end
    end
    if on_expand then
      if floating then
        r.ImGui_SetTooltip(ctx, "Dock " .. tab.label .. " back into this window")
      else
        r.ImGui_SetTooltip(ctx, "Open " .. tab.label .. " in a separate window")
      end
    elseif hovered and floating then
      r.ImGui_SetTooltip(ctx, "Dock " .. tab.label .. " back into this window")
    end

    local bg, border, icon_color, accent_color, text_color
    if active then
      bg = UI_THEME.accent_fill
      border = UI_THEME.accent
      icon_color = 0xF2F6FAFF
      accent_color = UI_THEME.accent_hvr
      text_color = 0xF2F6FAFF
    elseif hovered then
      bg = UI_THEME.surface_hvr
      border = UI_THEME.border_hvr
      icon_color = UI_THEME.text
      accent_color = UI_THEME.accent
      text_color = UI_THEME.text
    else
      bg = 0x00000000
      border = 0x00000000
      icon_color = UI_THEME.text_mute
      accent_color = 0x148A3AFF
      text_color = UI_THEME.text_dim
    end

    if active or hovered then
      ui_draw_panel(dl, x0, y0, x1, y1, inner_h * 0.5, bg, border, hovered, pressed)
    end

    local icon_x0 = x0 + pad_x
    local icon_y0 = y0 + (inner_h - icon_size) * 0.5 + (pressed and 1.0 or 0.0)
    tab.icon(dl, icon_x0, icon_y0, icon_size, icon_color, accent_color)
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, tab.label)
    local text_x = icon_x0 + icon_size + icon_text_gap
    local text_y = y0 + (inner_h - text_h) * 0.5 + (pressed and 1.0 or 0.0)
    r.ImGui_DrawList_AddText(dl, text_x, text_y, text_color, tab.label)

    local expand_cx = expand_x0 + expand_w * 0.5
    local expand_cy = y0 + inner_h * 0.5 + (pressed and 1.0 or 0.0)
    local expand_color = text_color
    if on_expand then
      expand_color = active and 0xFFFFFFFF or UI_THEME.text
    elseif not (active or floating or hovered) then
      expand_color = UI_THEME.text_mute
    end
    ui_button_draw_icon(dl, "popout", expand_cx, expand_cy, 11, expand_color)
  end
end

function render_sample_map_tab_bar()
  ensure_map_tabs()
  local btn_h = 22
  local plus_w = 22
  local close_w = 14
  local pad_x = 8
  local gap = 3

  for i, tab in ipairs(state.map_tabs or {}) do
    local active = tab.id == state.map_tab_active_id
    local label = map_tab_display_label(tab)
    local text_w = select(1, r.ImGui_CalcTextSize(ctx, label)) or 0
    local can_close = #(state.map_tabs) > 1
    local tab_w = pad_x + text_w + (can_close and (4 + close_w) or 0) + pad_x
    if i > 1 then
      imgui_same_line_if_fits(tab_w, gap)
    end
    local clicked = r.ImGui_InvisibleButton(ctx, "##map_tab_" .. tostring(tab.id), tab_w, btn_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local pressed = r.ImGui_IsItemActive(ctx)
    local x0, y0 = r.ImGui_GetItemRectMin(ctx)
    local x1, y1 = r.ImGui_GetItemRectMax(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    -- Segmented tabs: quiet text when idle, a raised surface on hover, and
    -- the active tab gets a tinted fill and an accent underline.
    local text_col
    if active then
      text_col = UI_THEME.text
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, UI_THEME.accent_fill, UI_METRICS.radius_ctrl)
      r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, 0x1EFF5E40, UI_METRICS.radius_ctrl, 0, 1.0)
      r.ImGui_DrawList_AddLine(dl, x0 + 6, y1 - 1.0, x1 - 6, y1 - 1.0, UI_THEME.accent, 2.0)
    elseif hovered then
      text_col = UI_THEME.text
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, UI_THEME.surface_hvr, UI_METRICS.radius_ctrl)
    else
      text_col = UI_THEME.text_dim
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, UI_THEME.surface, UI_METRICS.radius_ctrl)
    end
    local text_y = y0 + (btn_h - select(2, r.ImGui_CalcTextSize(ctx, label))) * 0.5 + (pressed and 1.0 or 0.0)
    r.ImGui_DrawList_AddText(dl, x0 + pad_x, text_y, text_col, label)
    if can_close then
      local cx = x1 - pad_x - close_w * 0.5
      local cy = y0 + btn_h * 0.5 + (pressed and 1.0 or 0.0)
      if hovered or active then
        ui_button_draw_icon(dl, "close", cx, cy, 11, text_col)
      end
    end
    if clicked then
      local mx = select(1, r.ImGui_GetMousePos(ctx))
      if can_close and mx and mx >= (x1 - pad_x - close_w - 2) then
        close_map_tab(tab.id)
      else
        switch_map_tab(tab.id)
      end
    end
    if hovered then
      r.ImGui_SetTooltip(ctx, "Stores this tab's filter, tags, folders, zoom, and pan")
    end
  end

  if #(state.map_tabs or {}) < MAP_TAB_MAX then
    imgui_same_line_if_fits(plus_w, gap)
    if draw_ui_button("map_tab_add", nil, plus_w, btn_h, { icon = "plus", compact = true }) then
      add_map_tab()
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "New Sample Map tab")
    end
  end
end

-- Sample Map toolbar, two rows:
--   1. search (with active tags and folder chips) on the left; the view
--      controls (Y axis, layout edit) pinned to the right edge.
--   2. a hairline, then the tag filters (loop/one-shot, Drum, Melodic, ...).
MAP_Y_AXIS_SHORT = {
  brightness = "Bright",
  dominant_freq = "Pitch",
  weight = "Weight",
}

function map_toolbar_right_cluster_width()
  local seg_pad = 10
  local w = 0
  local caption_w = select(1, r.ImGui_CalcTextSize(ctx, "Y")) or 8
  w = w + 3 + caption_w + 10
  for _, id in ipairs(MAP_Y_AXIS_OPTIONS) do
    w = w + (select(1, r.ImGui_CalcTextSize(ctx, MAP_Y_AXIS_SHORT[id] or id)) or 30) + seg_pad * 2 + 2
  end
  w = w + 3
  if state.map_ui_edit then
    w = w + UI_METRICS.toolbar_gap + map_layout_reset_button_width()
  end
  return w + UI_METRICS.toolbar_gap + UI_METRICS.toolbar_h
end

function map_layout_reset_button_width()
  return (select(1, r.ImGui_CalcTextSize(ctx, "Reset layout")) or 70) + 20
end

function reset_map_ui_layout()
  -- No undo for layouts, so ask first.
  if r.ShowMessageBox("Reset the map layout to the default arrangement?", "Reset layout", 4) == 6 then
    state.map_ui_layout = default_map_ui_layout()
    state.map_ui_drag = nil
    state.map_ui_drop = nil
    state.map_ui_split_drag = nil
    save_config()
  end
end

-- Y-axis picker as a segmented control: one click per axis instead of a
-- combo, with the active axis lit like the view tabs.
function render_map_y_axis_segmented()
  local h = UI_METRICS.toolbar_h
  local seg_pad = 10
  local track_pad = 3
  local axis = map_y_axis_id()
  local caption = "Y"
  local cap_w = select(1, r.ImGui_CalcTextSize(ctx, caption)) or 8
  local widths, total = {}, track_pad + cap_w + 10
  for i, id in ipairs(MAP_Y_AXIS_OPTIONS) do
    widths[i] = (select(1, r.ImGui_CalcTextSize(ctx, MAP_Y_AXIS_SHORT[id] or id)) or 30) + seg_pad * 2
    total = total + widths[i] + (i > 1 and 2 or 0)
  end
  total = total + track_pad
  local tx, ty = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  ui_draw_panel(dl, tx, ty, tx + total, ty + h, 9.0, UI_THEME.bg_panel, UI_THEME.border, false, false)
  local _, th = r.ImGui_CalcTextSize(ctx, caption)
  -- Muted "Y" caption so the control names its axis.
  local cx = tx + track_pad + 4
  r.ImGui_DrawList_AddText(dl, cx, ty + (h - th) * 0.5, UI_THEME.text_mute, caption)
  r.ImGui_SetCursorScreenPos(ctx, tx + track_pad + cap_w + 10, ty)
  for i, id in ipairs(MAP_Y_AXIS_OPTIONS) do
    if i > 1 then
      r.ImGui_SameLine(ctx, 0, 2)
    end
    local label = MAP_Y_AXIS_SHORT[id] or id
    local clicked = r.ImGui_InvisibleButton(ctx, "##map_y_axis_" .. id, widths[i], h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local pressed = r.ImGui_IsItemActive(ctx)
    local x0, y0 = r.ImGui_GetItemRectMin(ctx)
    local x1, y1 = r.ImGui_GetItemRectMax(ctx)
    local active = id == axis
    local text_col = UI_THEME.text_dim
    if active then
      ui_draw_panel(dl, x0, y0 + 3, x1, y1 - 3, (h - 6) * 0.5, UI_THEME.accent_fill, UI_THEME.accent, hovered, pressed)
      text_col = UI_THEME.text
    elseif hovered then
      ui_draw_panel(dl, x0, y0 + 3, x1, y1 - 3, (h - 6) * 0.5, UI_THEME.surface_hvr, UI_THEME.border_hvr, hovered, pressed)
      text_col = UI_THEME.text
    end
    local lw, lh = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x0 + (widths[i] - lw) * 0.5, y0 + (h - lh) * 0.5 + (pressed and 1 or 0), text_col, label)
    if clicked and not active then
      apply_map_y_axis(id)
    end
    if hovered then
      local tips = {
        brightness = "Y axis: brightness (dark at the bottom, clicky at the top)",
        dominant_freq = "Y axis: dominant frequency (pitch)",
        weight = "Y axis: weight (heavy sub/body at the bottom, thin/clicky at the top)",
      }
      r.ImGui_SetTooltip(ctx, tips[id] or map_y_axis_label(id))
    end
  end
end

function render_map_layout_toggle()
  local h = UI_METRICS.toolbar_h
  if state.map_ui_edit then
    if draw_ui_button("map_layout_reset", "Reset layout", map_layout_reset_button_width(), h, { compact = true }) then
      reset_map_ui_layout()
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Put every module back in the default arrangement (asks first).")
    end
    r.ImGui_SameLine(ctx, 0, UI_METRICS.toolbar_gap)
  end
  if draw_ui_button("map_layout_edit", nil, h, h, {
    icon = "layout",
    compact = true,
    selected = state.map_ui_edit == true,
    style = state.map_ui_edit and "primary" or "default",
  }) then
    state.map_ui_edit = not state.map_ui_edit
    state.map_ui_drag = nil
    state.map_ui_drop = nil
    state.map_ui_split_drag = nil
  end
  if r.ImGui_IsItemHovered(ctx) then
    if state.map_ui_edit then
      r.ImGui_SetTooltip(ctx, "Editing the layout.\nDrag a module by its name to move it; drag the grips between modules to resize.\nClick here or press Esc to finish.")
    else
      r.ImGui_SetTooltip(ctx, "Edit Sample Map layout.\nMove modules and resize their edges.")
    end
  end
end

function render_sample_map_toolbar()
  local cluster_w = map_toolbar_right_cluster_width()
  local row_x0 = r.ImGui_GetCursorScreenPos(ctx)
  local row_y0 = select(2, r.ImGui_GetCursorScreenPos(ctx))
  render_filter_input(cluster_w + UI_METRICS.toolbar_gap)
  render_folder_filter_chips()

  -- Right cluster: pinned to the window's right edge on the search row when
  -- it fits there, otherwise it wraps onto its own line.
  local right_x = imgui_window_right_x()
  local last_x1 = select(1, r.ImGui_GetItemRectMax(ctx))
  local cluster_x = right_x - cluster_w
  if cluster_x >= last_x1 + UI_METRICS.toolbar_gap then
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorScreenPos(ctx, cluster_x, row_y0)
  end
  render_map_y_axis_segmented()
  r.ImGui_SameLine(ctx, 0, UI_METRICS.toolbar_gap)
  render_map_layout_toggle()

  -- Tag filters get their own band under a hairline.
  local show_tags = sample_map_tag_band_visible()
  if show_tags and state.tag_list and #state.tag_list > 0 then
    r.ImGui_Dummy(ctx, 1, 1)
    local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddLine(dl, math.min(lx, row_x0), ly + 0.5, right_x, ly + 0.5, UI_THEME.border_soft, 1.0)
    r.ImGui_Dummy(ctx, 1, 3)
  end
  r.ImGui_Dummy(ctx, 0, 0)
  if show_tags then
    render_tag_filters()
    -- Search row + band, so moving from the search field to a tag (and the
    -- click on it, which takes focus from the field) keeps the band open.
    local by1 = select(2, r.ImGui_GetCursorScreenPos(ctx))
    state.tag_band_rect = { x0 = row_x0, y0 = row_y0, x1 = right_x, y1 = by1 }
  else
    state.hovered_tag = nil
    state.tag_band_rect = nil
  end
  render_tag_delete_popup()
  render_library_tag_path_menu()
end

-- "Hide tags until search is clicked" (Settings, View menu). Off by default.
-- Clicking the search field opens the tag band; it stays open while the
-- field is focused, the mouse is over the search row or the band, a tag is
-- being clicked, or a popup is open, and closes once none of those hold.
function sample_map_tag_band_visible()
  if not state.tags_hide_until_search then
    state.tag_band_open = nil
    return true
  end
  if state.sample_filter_focused then
    state.tag_band_open = true
    return true
  end
  if not state.tag_band_open then
    return false
  end
  local keep = false
  local rect = state.tag_band_rect
  if rect and r.ImGui_GetMousePos then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local m = 6
    if mx and my and mx >= rect.x0 - m and mx <= rect.x1 + m and my >= rect.y0 - m and my <= rect.y1 + m then
      keep = true
    end
  end
  if not keep and r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) and rect then
    keep = true
  end
  if not keep and r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopupId then
    local ok, open = pcall(r.ImGui_IsPopupOpen, ctx, "", r.ImGui_PopupFlags_AnyPopupId())
    keep = ok and open == true
  end
  if not keep then
    state.tag_band_open = false
  end
  return keep
end

function set_tags_hide_until_search(on)
  on = on == true
  if (state.tags_hide_until_search == true) ~= on then
    state.tags_hide_until_search = on
    state.tag_band_open = nil
    save_config()
  end
end

MAP_UI_GAP = 4
MAP_UI_EDGE = 7
MAP_UI_IDS = { "tracks", "tabs", "path", "wave", "map" }
MAP_UI_SPEC = {
  tracks = { flex_h = true, min_w = 140, min_h = 80, scroll = true },
  tabs = { flex_h = false, h = 28, min_w = 80, min_h = 24, scroll = false },
  path = { flex_h = false, h = 30, min_w = 80, min_h = 24, scroll = false },
  wave = { flex_h = false, h = 80, min_w = 160, min_h = 70, scroll = false },
  map = { flex_h = true, min_w = 120, min_h = 80, scroll = false },
}

function default_map_ui_layout()
  return {
    type = "row",
    children = {
      { type = "leaf", id = "tracks", w = state.seq_panel_width or 240 },
      { type = "col", children = {
        { type = "leaf", id = "tabs" },
        { type = "leaf", id = "path" },
        { type = "leaf", id = "wave" },
        { type = "leaf", id = "map" },
      } },
    },
  }
end

function map_ui_consider_drag(id)
  if not state.map_ui_edit or not id then
    return
  end
  if sample_drag_active() or state.pending_waveform_drop or state.map_ui_split_drag then
    return
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    state.map_ui_drag = nil
    state.map_ui_drop = nil
    reset_map_ui_layout()
    return
  end
  if state.map_ui_drag then
    return
  end
  local dragging = r.ImGui_IsMouseDragging and r.ImGui_IsMouseDragging(ctx, 0, 6.0)
  if dragging and (r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)) then
    state.map_ui_drag = { id = id }
  end
end

function map_ui_clone(node)
  if type(node) ~= "table" then
    return nil
  end
  local copy = { type = node.type, id = node.id, w = node.w, h = node.h, size = node.size }
  if type(node.children) == "table" then
    copy.children = {}
    for i, child in ipairs(node.children) do
      copy.children[i] = map_ui_clone(child)
    end
  end
  return copy
end

function map_ui_collect_ids(node, into)
  if type(node) ~= "table" then
    return
  end
  if node.type == "leaf" then
    if node.id then
      into[node.id] = (into[node.id] or 0) + 1
    end
    return
  end
  for _, child in ipairs(node.children or {}) do
    map_ui_collect_ids(child, into)
  end
end

function map_ui_validate(node)
  if type(node) ~= "table" then
    return false
  end
  local counts = {}
  map_ui_collect_ids(node, counts)
  for _, id in ipairs(MAP_UI_IDS) do
    if counts[id] ~= 1 then
      return false
    end
  end
  for id, n in pairs(counts) do
    if n ~= 1 or not MAP_UI_SPEC[id] then
      return false
    end
  end
  return true
end

function map_ui_flatten(node)
  if type(node) ~= "table" then
    return nil
  end
  if node.type == "leaf" then
    return node
  end
  local kids = {}
  for _, child in ipairs(node.children or {}) do
    local flat = map_ui_flatten(child)
    if flat then
      if flat.type == node.type and type(flat.children) == "table" then
        for _, grand in ipairs(flat.children) do
          kids[#kids + 1] = grand
        end
      else
        kids[#kids + 1] = flat
      end
    end
  end
  if #kids == 0 then
    return nil
  end
  if #kids == 1 then
    local only = kids[1]
    if node.w and not only.w then
      only.w = node.w
    end
    if node.h and not only.h then
      only.h = node.h
    end
    if node.size and not only.size and not only.w then
      only.size = node.size
    end
    return only
  end
  node.children = kids
  return node
end

function map_ui_detach(node, id)
  if type(node) ~= "table" then
    return nil, nil
  end
  if node.type == "leaf" then
    if node.id == id then
      return nil, node
    end
    return node, nil
  end
  local found = nil
  local kids = {}
  for _, child in ipairs(node.children or {}) do
    local kept, detached = map_ui_detach(child, id)
    if detached then
      found = detached
    end
    if kept then
      kids[#kids + 1] = kept
    end
  end
  node.children = kids
  return node, found
end

function map_ui_wrap_pair(kind, a, b, src)
  local wrap = { type = kind, children = { a, b } }
  if kind == "row" then
    wrap.w = src and (src.w or src.size) or nil
  else
    wrap.h = src and src.h or nil
  end
  return wrap
end

function map_ui_insert(node, target_id, incoming, edge)
  if type(node) ~= "table" then
    return node, false
  end
  local want = (edge == "left" or edge == "right") and "row" or "col"
  if node.type == "leaf" then
    if node.id ~= target_id then
      return node, false
    end
    local a, b = incoming, node
    if edge == "right" or edge == "bottom" then
      a, b = node, incoming
    end
    return map_ui_wrap_pair(want, a, b, node), true
  end
  for i, child in ipairs(node.children or {}) do
    if child.type == "leaf" and child.id == target_id then
      if node.type == want then
        local idx = i
        if edge == "right" or edge == "bottom" then
          idx = i + 1
        end
        table.insert(node.children, idx, incoming)
        return node, true
      end
      local a, b = incoming, child
      if edge == "right" or edge == "bottom" then
        a, b = child, incoming
      end
      node.children[i] = map_ui_wrap_pair(want, a, b, child)
      return node, true
    end
    local updated, done = map_ui_insert(child, target_id, incoming, edge)
    node.children[i] = updated
    if done then
      return node, true
    end
  end
  return node, false
end

function map_ui_sync_tracks_width(node)
  if type(node) ~= "table" then
    return
  end
  if node.type == "leaf" and node.id == "tracks" then
    local w = tonumber(node.w) or tonumber(node.size)
    if type(w) == "number" then
      state.seq_panel_width = w
    end
    return
  end
  for _, child in ipairs(node.children or {}) do
    map_ui_sync_tracks_width(child)
  end
end

function map_ui_dock(source_id, target_id, edge)
  if not source_id or not target_id or source_id == target_id then
    return
  end
  local root = map_ui_clone(state.map_ui_layout)
  local kept, detached = map_ui_detach(root, source_id)
  if not detached then
    return
  end
  kept = map_ui_flatten(kept)
  if detached.id == "tracks" and not detached.w and not detached.size then
    detached.w = state.seq_panel_width or 240
  end
  local inserted, ok = map_ui_insert(kept, target_id, detached, edge)
  if not ok then
    return
  end
  inserted = map_ui_flatten(inserted)
  if map_ui_validate(inserted) then
    state.map_ui_layout = inserted
    map_ui_sync_tracks_width(inserted)
  end
end

function map_ui_ensure_layout()
  if not map_ui_validate(state.map_ui_layout) then
    state.map_ui_layout = default_map_ui_layout()
    state.map_ui_layout_sanitized = true
  elseif not state.map_ui_layout_sanitized then
    map_ui_sanitize_sizes(state.map_ui_layout)
    state.map_ui_layout_sanitized = true
  end
  return state.map_ui_layout
end

function map_ui_sanitize_sizes(node)
  if type(node) ~= "table" then
    return
  end
  node._alloc_w = nil
  node._alloc_h = nil
  if type(node.w) == "number" then
    if node.w > 4000 then node.w = 4000 end
    if node.w < 1 then node.w = nil end
  end
  if type(node.size) == "number" then
    if node.size > 4000 then node.size = 4000 end
    if node.size < 1 then node.size = nil end
  end
  if type(node.h) == "number" then
    if node.h > 3000 then node.h = 3000 end
    if node.h < 1 then node.h = nil end
  end
  for _, child in ipairs(node.children or {}) do
    map_ui_sanitize_sizes(child)
  end
end

function map_ui_get_w(node)
  if type(node) ~= "table" then
    return nil
  end
  return tonumber(node.w) or tonumber(node.size)
end

function map_ui_get_h(node)
  if type(node) ~= "table" then
    return nil
  end
  return tonumber(node.h)
end

function map_ui_min_w(node)
  if type(node) == "table" and node.type == "leaf" and MAP_UI_SPEC[node.id] then
    return MAP_UI_SPEC[node.id].min_w or 80
  end
  return 80
end

function map_ui_min_h(node)
  if type(node) == "table" and node.type == "leaf" and MAP_UI_SPEC[node.id] then
    return MAP_UI_SPEC[node.id].min_h or 24
  end
  return 24
end

function map_ui_pref_h(node)
  if type(node) ~= "table" then
    return 40
  end
  local fixed = map_ui_get_h(node)
  if type(fixed) == "number" and fixed > 0 then
    return fixed
  end
  if node.type == "leaf" then
    local spec = MAP_UI_SPEC[node.id]
    if not spec then
      return 40
    end
    if spec.flex_h then
      return spec.min_h
    end
    return spec.h
  end
  if node.type == "col" then
    local h = 0
    for i, child in ipairs(node.children or {}) do
      if i > 1 then
        h = h + MAP_UI_GAP
      end
      h = h + map_ui_pref_h(child)
    end
    return h
  end
  local h = 0
  for _, child in ipairs(node.children or {}) do
    h = math.max(h, map_ui_pref_h(child))
  end
  return h
end

function map_ui_is_flex_h(node)
  if type(node) ~= "table" then
    return false
  end
  if node.type == "leaf" then
    local spec = MAP_UI_SPEC[node.id]
    return spec and spec.flex_h or false
  end
  for _, child in ipairs(node.children or {}) do
    if map_ui_is_flex_h(child) then
      return true
    end
  end
  return false
end

function map_ui_fit_sizes(sizes, mins, inner)
  local n = #sizes
  local sum = 0
  for i = 1, n do
    local minv = mins[i] or 0
    sizes[i] = math.max(minv, sizes[i] or 0)
    sum = sum + sizes[i]
  end
  if sum <= inner or sum <= 0 then
    return sizes
  end
  local extra = 0
  for i = 1, n do
    extra = extra + math.max(0, sizes[i] - (mins[i] or 0))
  end
  if extra <= 0 or (sum - inner) > extra then
    local scale = inner / sum
    for i = 1, n do
      sizes[i] = sizes[i] * scale
    end
    return sizes
  end
  local frac = (sum - inner) / extra
  for i = 1, n do
    local room = sizes[i] - (mins[i] or 0)
    if room > 0 then
      sizes[i] = sizes[i] - room * frac
    end
  end
  return sizes
end

function map_ui_col_heights(children, total)
  local n = #children
  local inner = math.max(0, total - MAP_UI_GAP * math.max(0, n - 1))
  local heights = {}
  local flex = {}
  local used = 0
  for i, child in ipairs(children) do
    local fixed = map_ui_get_h(child)
    if type(fixed) == "number" and fixed > 0 then
      heights[i] = math.max(map_ui_min_h(child), fixed)
      used = used + heights[i]
    elseif map_ui_is_flex_h(child) then
      flex[#flex + 1] = i
      heights[i] = 0
    else
      heights[i] = map_ui_pref_h(child)
      used = used + heights[i]
    end
  end
  local leftover = inner - used
  if #flex == 0 then
    local mins = {}
    for i, child in ipairs(children) do
      mins[i] = map_ui_min_h(child)
    end
    return map_ui_fit_sizes(heights, mins, inner)
  end
  local each = leftover / #flex
  for _, i in ipairs(flex) do
    heights[i] = math.max(map_ui_min_h(children[i]), each)
  end
  local mins = {}
  for i, child in ipairs(children) do
    mins[i] = map_ui_min_h(child)
  end
  return map_ui_fit_sizes(heights, mins, inner)
end

function map_ui_row_widths(children, total)
  local n = #children
  local inner = math.max(0, total - MAP_UI_GAP * math.max(0, n - 1))
  local widths = {}
  local flex = {}
  local used = 0
  for i, child in ipairs(children) do
    local sized = map_ui_get_w(child)
    if (not sized or sized <= 0) and child.type == "leaf" and child.id == "tracks" then
      child.w = state.seq_panel_width or 240
      sized = child.w
    end
    if type(sized) == "number" and sized > 0 then
      widths[i] = sized
      used = used + sized
    else
      flex[#flex + 1] = i
      widths[i] = 0
    end
  end
  if #flex == 0 then
    local mins = {}
    for i, child in ipairs(children) do
      mins[i] = map_ui_min_w(child)
    end
    return map_ui_fit_sizes(widths, mins, inner)
  end
  local leftover = math.max(0, inner - used)
  local each = leftover / #flex
  for _, i in ipairs(flex) do
    widths[i] = math.max(map_ui_min_w(children[i]), each)
  end
  local mins = {}
  for i, child in ipairs(children) do
    mins[i] = map_ui_min_w(child)
  end
  return map_ui_fit_sizes(widths, mins, inner)
end

function map_ui_leaf_flags(spec)
  local win_flags = 0
  if r.ImGui_WindowFlags_NoNav then
    win_flags = r.ImGui_WindowFlags_NoNav()
  end
  if not spec.scroll then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  return win_flags
end

function map_ui_commit_rect(x, y, w, h)
  r.ImGui_SetCursorScreenPos(ctx, x + math.max(0, w), y + math.max(0, h))
  r.ImGui_Dummy(ctx, 0, 0)
end

MAP_UI_LABELS = {
  tracks = "Tracks",
  tabs = "Tabs",
  path = "Path",
  wave = "Waveform",
  map = "Sample Map",
}

function map_ui_edge_target(id, edge)
  local info = state.map_ui_leaf_info and state.map_ui_leaf_info[id]
  if not info then
    return nil
  end
  if edge == "left" or edge == "right" then
    local row = info.row
    if not row or type(row.node) ~= "table" then
      return nil
    end
    local node = row.node
    local i = row.index
    if edge == "right" then
      local child = node.children[i]
      return { node = node, index = i, axis = "w", sign = 1, size0 = child._alloc_w or map_ui_get_w(child) or info.w }
    end
    if i > 1 then
      local child = node.children[i - 1]
      return { node = node, index = i - 1, axis = "w", sign = 1, size0 = child._alloc_w or map_ui_get_w(child) or 0 }
    end
    local child = node.children[i]
    return { node = node, index = i, axis = "w", sign = -1, size0 = child._alloc_w or info.w }
  end
  local col = info.col
  if not col or type(col.node) ~= "table" then
    return nil
  end
  local node = col.node
  local i = col.index
  if edge == "bottom" then
    local child = node.children[i]
    return { node = node, index = i, axis = "h", sign = 1, size0 = child._alloc_h or map_ui_get_h(child) or info.h }
  end
  if i > 1 then
    local child = node.children[i - 1]
    return { node = node, index = i - 1, axis = "h", sign = 1, size0 = child._alloc_h or map_ui_get_h(child) or 0 }
  end
  local child = node.children[i]
  return { node = node, index = i, axis = "h", sign = -1, size0 = child._alloc_h or info.h }
end

function map_ui_handle_edge(id, edge)
  if not state.map_ui_edit or state.map_ui_drag then
    return
  end
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  if (hovered or active) and r.ImGui_SetMouseCursor then
    if edge == "left" or edge == "right" then
      if r.ImGui_MouseCursor_ResizeEW then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
      end
    elseif r.ImGui_MouseCursor_ResizeNS then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    end
  end
  local key = tostring(id) .. "_" .. edge
  local mx, my = r.ImGui_GetMousePos(ctx)
  if active then
    if not state.map_ui_split_drag or state.map_ui_split_drag.key ~= key then
      local target = map_ui_edge_target(id, edge)
      if not target then
        return
      end
      state.map_ui_split_drag = {
        key = key,
        node = target.node,
        index = target.index,
        axis = target.axis,
        sign = target.sign,
        start = target.axis == "w" and mx or my,
        size0 = target.size0,
      }
    else
      local drag = state.map_ui_split_drag
      local child = drag.node.children[drag.index]
      if not child then
        return
      end
      local pos = drag.axis == "w" and mx or my
      local minv = drag.axis == "w" and map_ui_min_w(child) or map_ui_min_h(child)
      local newv = math.max(minv, drag.size0 + drag.sign * (pos - drag.start))
      local host = state.sample_map_window_rect or state.main_window_rect
      if drag.axis == "w" then
        local maxv = math.max(minv + 40, ((host and host.w) or 900) - 120)
        newv = math.min(maxv, newv)
        child.w = newv
        child.size = nil
        if child.type == "leaf" and child.id == "tracks" then
          state.seq_panel_width = newv
        end
      else
        local maxv = math.max(minv + 24, ((host and host.h) or 700) - 80)
        newv = math.min(maxv, newv)
        child.h = newv
      end
    end
  elseif state.map_ui_split_drag and state.map_ui_split_drag.key == key
      and r.ImGui_IsMouseReleased and r.ImGui_IsMouseReleased(ctx, 0) then
    state.map_ui_split_drag = nil
    save_config()
  end
end

-- True when this edge is shared with a neighbouring module, so dragging it
-- trades space between the two. Outer edges get no handle: dragging them
-- did nothing visible, which made the whole tool feel broken.
function map_ui_edge_has_neighbor(id, edge)
  local info = state.map_ui_leaf_info and state.map_ui_leaf_info[id]
  if not info then
    return false
  end
  local ctx_ = (edge == "left" or edge == "right") and info.row or info.col
  if not ctx_ or type(ctx_.node) ~= "table" then
    return false
  end
  if edge == "left" or edge == "top" then
    return ctx_.index > 1
  end
  return ctx_.index < #(ctx_.node.children or {})
end

-- Grip handles and labels are queued here and painted by
-- map_ui_draw_edit_chrome() on the body's draw list, so they can sit in
-- the gap between modules instead of being clipped to one module.
function map_ui_queue_chrome(item)
  state.map_ui_chrome = state.map_ui_chrome or {}
  state.map_ui_chrome[#state.map_ui_chrome + 1] = item
end

function map_ui_edit_overlay(id, w, h)
  if not state.map_ui_edit then
    return
  end
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww = math.max(1, w or select(1, r.ImGui_GetWindowSize(ctx)) or 1)
  local wh = math.max(1, h or select(2, r.ImGui_GetWindowSize(ctx)) or 1)
  local flags = map_ui_leaf_flags({ scroll = false })
  r.ImGui_SetCursorScreenPos(ctx, wx, wy)
  local open = r.ImGui_BeginChild(ctx, "map_ui_edit_" .. id, ww, wh, 0, flags)
  if open then
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local moving = state.map_ui_drag and state.map_ui_drag.id == id
    -- Scrim keeps the module's content faintly visible but out of the way.
    r.ImGui_DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + wh, moving and 0x0B0E0CE6 or 0x0B0E0CB4, 5)

    local t = MAP_UI_EDGE
    local edge_hot = false
    local edges = {
      { "left", wx, wy, t, wh },
      { "right", wx + ww - t, wy, t, wh },
      { "top", wx, wy, ww, t },
      { "bottom", wx, wy + wh - t, ww, t },
    }
    for _, e in ipairs(edges) do
      local edge = e[1]
      if map_ui_edge_has_neighbor(id, edge) then
        r.ImGui_SetCursorScreenPos(ctx, e[2], e[3])
        r.ImGui_InvisibleButton(ctx, "##map_ui_e_" .. edge .. "_" .. id, e[4], e[5])
        local hot = r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx)
        map_ui_handle_edge(id, edge)
        local drag = state.map_ui_split_drag
        if drag and drag.key == tostring(id) .. "_" .. edge then
          hot = true
        end
        edge_hot = edge_hot or hot
        -- One grip per shared edge: the right / bottom owner draws it.
        if edge == "right" or edge == "bottom" or hot then
          map_ui_queue_chrome({ kind = "edge", id = id, edge = edge, hot = hot,
            x0 = wx, y0 = wy, x1 = wx + ww, y1 = wy + wh })
        end
      end
    end

    r.ImGui_SetCursorScreenPos(ctx, wx + t, wy + t)
    r.ImGui_InvisibleButton(ctx, "##map_ui_move_" .. id, math.max(1, ww - t * 2), math.max(1, wh - t * 2))
    map_ui_consider_drag(id)
    local body_hot = r.ImGui_IsItemHovered(ctx) and not state.map_ui_split_drag and not state.map_ui_drag
    if body_hot and r.ImGui_SetMouseCursor then
      local cursor = r.ImGui_MouseCursor_ResizeAll and r.ImGui_MouseCursor_ResizeAll() or nil
      if cursor then
        r.ImGui_SetMouseCursor(ctx, cursor)
      end
    end
    if body_hot and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "Drag to move this module next to another.\nDrag the grips between modules to resize.")
    end
    local border = UI_THEME.border_hvr
    local thick = 1.0
    if moving then
      border = UI_THEME.text_mute
    elseif body_hot then
      border, thick = UI_THEME.accent, 1.5
    end
    r.ImGui_DrawList_AddRect(dl, wx + 0.5, wy + 0.5, wx + ww - 0.5, wy + wh - 0.5, border, 5, 0, thick)
    map_ui_draw_module_label(dl, { id = id, hot = body_hot, moving = moving,
      x0 = wx, y0 = wy, x1 = wx + ww, y1 = wy + wh })
    r.ImGui_Dummy(ctx, 0, 0)
  end
  imgui_end_child(open)
end

-- Six-dot grip, horizontal or vertical.
function map_ui_draw_grip(dl, cx, cy, vertical, color)
  for i = -1, 1 do
    for j = 0, 1 do
      local dx, dy
      if vertical then
        dx, dy = (j - 0.5) * 3.5, i * 4.0
      else
        dx, dy = i * 4.0, (j - 0.5) * 3.5
      end
      r.ImGui_DrawList_AddCircleFilled(dl, cx + dx, cy + dy, 1.1, color, 6)
    end
  end
end

-- Small rounded badge with centred text.
function map_ui_draw_badge(dl, cx, cy, text, fg, bg, border)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local px, py = 8, 3
  local x0, y0 = cx - tw * 0.5 - px, cy - th * 0.5 - py
  local x1, y1 = cx + tw * 0.5 + px, cy + th * 0.5 + py
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, bg, (y1 - y0) * 0.5)
  if border then
    r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, border, (y1 - y0) * 0.5, 0, 1.0)
  end
  r.ImGui_DrawList_AddText(dl, x0 + px, y0 + py, fg, text)
  return x0, y0, x1, y1
end

function map_ui_draw_module_label(dl, it)
  local T = UI_THEME
  local w, h = it.x1 - it.x0, it.y1 - it.y0
  local label = MAP_UI_LABELS[it.id] or it.id
  local cx, cy = (it.x0 + it.x1) * 0.5, (it.y0 + it.y1) * 0.5
  local _, th = r.ImGui_CalcTextSize(ctx, label)
  local show_size = h >= th * 2 + 22
  if show_size then
    cy = cy - th * 0.5 - 1
  end
  local fg = it.moving and T.text_mute or (it.hot and T.text or T.text_dim)
  local bg = it.hot and T.accent_fill or T.elevated
  local border = it.hot and T.accent or T.border_hvr
  local text = it.moving and (label .. " (moving)") or label
  -- Badge: move grip, then the module name.
  local tw = r.ImGui_CalcTextSize(ctx, text)
  local grip_w, pad_x, pad_y = 14, 9, 3
  local bw = pad_x + grip_w + tw + pad_x
  local x0, y0 = cx - bw * 0.5, cy - th * 0.5 - pad_y
  local x1, y1 = cx + bw * 0.5, cy + th * 0.5 + pad_y
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, bg, (y1 - y0) * 0.5)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, border, (y1 - y0) * 0.5, 0, 1.0)
  map_ui_draw_grip(dl, x0 + pad_x + 3, cy, true, fg)
  r.ImGui_DrawList_AddText(dl, x0 + pad_x + grip_w, y0 + pad_y, fg, text)
  if show_size then
    local size = string.format("%d \u{00D7} %d", math.floor(w + 0.5), math.floor(h + 0.5))
    local sw = r.ImGui_CalcTextSize(ctx, size)
    r.ImGui_DrawList_AddText(dl, cx - sw * 0.5, cy + th * 0.5 + 6, T.text_mute, size)
  end
end

function map_ui_draw_edit_chrome()
  local items = state.map_ui_chrome
  state.map_ui_chrome = nil
  if not state.map_ui_edit or not items then
    return
  end
  -- Foreground: the module overlays are child windows and would cover
  -- anything drawn on the body itself.
  local dl = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx) or r.ImGui_GetWindowDrawList(ctx)
  local T = UI_THEME
  local half_gap = MAP_UI_GAP * 0.5
  for _, it in ipairs(items) do
    if it.kind == "edge" then
      local vertical = it.edge == "left" or it.edge == "right"
      local col = it.hot and T.accent or T.text_dim
      if vertical then
        local x = it.edge == "right" and (it.x1 + half_gap) or (it.x0 - half_gap)
        local cy = (it.y0 + it.y1) * 0.5
        if it.hot then
          r.ImGui_DrawList_AddLine(dl, x, it.y0 + 4, x, it.y1 - 4, T.accent, 2.0)
        end
        r.ImGui_DrawList_AddRectFilled(dl, x - 4, cy - 11, x + 4, cy + 11, it.hot and T.accent_fill_h or T.elevated, 4)
        r.ImGui_DrawList_AddRect(dl, x - 4, cy - 11, x + 4, cy + 11, it.hot and T.accent or T.border_hvr, 4, 0, 1.0)
        map_ui_draw_grip(dl, x, cy, true, col)
      else
        local y = it.edge == "bottom" and (it.y1 + half_gap) or (it.y0 - half_gap)
        local cx = (it.x0 + it.x1) * 0.5
        if it.hot then
          r.ImGui_DrawList_AddLine(dl, it.x0 + 4, y, it.x1 - 4, y, T.accent, 2.0)
        end
        r.ImGui_DrawList_AddRectFilled(dl, cx - 11, y - 4, cx + 11, y + 4, it.hot and T.accent_fill_h or T.elevated, 4)
        r.ImGui_DrawList_AddRect(dl, cx - 11, y - 4, cx + 11, y + 4, it.hot and T.accent or T.border_hvr, 4, 0, 1.0)
        map_ui_draw_grip(dl, cx, y, false, col)
      end
    end
  end
  -- Live size while resizing.
  local drag = state.map_ui_split_drag
  if drag and drag.node and drag.node.children then
    local child = drag.node.children[drag.index]
    local v = child and (drag.axis == "w" and child.w or child.h)
    if v then
      local mx, my = r.ImGui_GetMousePos(ctx)
      map_ui_draw_badge(dl, mx + 18, my + 18, string.format("%d px", math.floor(v + 0.5)),
        T.text, T.popup_bg, T.accent)
    end
  end
end

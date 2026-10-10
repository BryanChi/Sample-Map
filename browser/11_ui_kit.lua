-- Sample Map Browser module: ui_kit
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- UI kit: modern minimal custom-drawn controls ---------------------------
-- Palette keyed to accent #1EFF5E (hue ~137°). Neutrals are charcoal with a
-- faint forest cast so the UI never reads as blue-gray. Surfaces step up in
-- small, even increments (bg → panel → surface → elevated) so nested areas
-- read as layers without needing heavy borders.
UI_THEME = {
  bg            = 0x0E120FFF,
  bg_panel      = 0x131915FF,
  surface       = 0x19201BFF,
  surface_hvr   = 0x232C26FF,
  surface_act   = 0x141A16FF,
  elevated      = 0x1E2621FF,
  border        = 0x26302AFF,
  border_soft   = 0x1E2622FF,
  border_hvr    = 0x3D5446FF,
  text          = 0xE8EEEAFF,
  text_dim      = 0x95A098FF,
  text_mute     = 0x5F6962FF,
  popup_bg      = 0x151B17F8,
  title_bg      = 0x0B0E0CFF,
  title_bg_act  = 0x101411FF,
  accent        = 0x1EFF5EFF,
  accent_hvr    = 0x62FF8AFF,
  accent_fill   = 0x0E2A18FF,
  accent_fill_h = 0x174A24FF,
  danger        = 0xE07070FF,
  danger_fill   = 0x3A1E1EFF,
  danger_hvr    = 0x4A2828FF,
  success       = 0x5EDC8AFF,
  success_fill  = 0x1A3224FF,
  success_hvr   = 0x244830FF,
  folder        = 0x2A5A34FF,
  folder_hvr    = 0x3A7544FF,
  grid_line     = 0x8FB39A1C,
  grid_text     = 0x8FA396A0,
}

-- Shared sizing so toolbars, tabs and section headers line up across views.
UI_METRICS = {
  toolbar_h     = 28,
  toolbar_gap   = 10,
  section_h     = 30,
  radius_panel  = 8,
  radius_ctrl   = 6,
}

-- Thin vertical rule between toolbar groups; keeps related controls visually
-- clustered without spending horizontal room on labels.
function ui_toolbar_divider(h, gap)
  h = h or UI_METRICS.toolbar_h
  gap = gap or UI_METRICS.toolbar_gap
  r.ImGui_SameLine(ctx, 0, gap)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local inset = math.floor(h * 0.22)
  r.ImGui_DrawList_AddLine(dl, x + 0.5, y + inset, x + 0.5, y + h - inset, UI_THEME.border, 1.0)
  r.ImGui_Dummy(ctx, 1, h)
  r.ImGui_SameLine(ctx, 0, gap)
end

-- Small uppercase caption used to group related settings / menu sections.
function ui_group_caption(text)
  r.ImGui_Dummy(ctx, 1, 2)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local label = string.upper(text or "")
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, x + 2, y, UI_THEME.text_mute, label)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local line_x0 = x + tw + 12
  local line_x1 = x + (avail or 0) - 2
  if line_x1 > line_x0 then
    local ly = y + th * 0.5
    r.ImGui_DrawList_AddLine(dl, line_x0, ly, line_x1, ly, UI_THEME.border_soft, 1.0)
  end
  r.ImGui_Dummy(ctx, 1, th + 2)
end

-- Popup title row: accent icon tile, bold title, dim meta text on the right.
function ui_popup_header(icon, title, meta)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 0
  local tw, th = r.ImGui_CalcTextSize(ctx, title or "")
  local h = math.max(24, th + 8)
  local text_x = x
  if icon then
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + h, y + h, UI_THEME.accent_fill, UI_METRICS.radius_ctrl)
    r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + h - 0.5, y + h - 0.5, 0x1EFF5E44, UI_METRICS.radius_ctrl, 0, 1.0)
    ui_button_draw_icon(dl, icon, x + h * 0.5, y + h * 0.5, h, UI_THEME.accent)
    text_x = x + h + 9
  end
  local ty = y + (h - th) * 0.5
  r.ImGui_DrawList_AddText(dl, text_x, ty, UI_THEME.text, title or "")
  r.ImGui_DrawList_AddText(dl, text_x + 0.5, ty, UI_THEME.text, title or "")
  if meta and meta ~= "" then
    local mw, mh = r.ImGui_CalcTextSize(ctx, meta)
    local mx = math.max(text_x + tw + 12, x + avail - mw)
    r.ImGui_DrawList_AddText(dl, mx, y + (h - mh) * 0.5, UI_THEME.text_dim, meta)
  end
  r.ImGui_Dummy(ctx, math.max(1, avail), h)
  r.ImGui_Dummy(ctx, 1, 2)
end

-- Full-width search field for popups. Focused when the popup appears;
-- returns (submitted_with_enter, text).
function ui_popup_search(id, hint, value)
  if r.ImGui_IsWindowAppearing and r.ImGui_IsWindowAppearing(ctx) and r.ImGui_SetKeyboardFocusHere then
    r.ImGui_SetKeyboardFocusHere(ctx)
  end
  r.ImGui_SetNextItemWidth(ctx, -1)
  local flags = r.ImGui_InputTextFlags_EnterReturnsTrue and r.ImGui_InputTextFlags_EnterReturnsTrue() or 0
  local submitted, text
  if r.ImGui_InputTextWithHint then
    submitted, text = r.ImGui_InputTextWithHint(ctx, "##" .. tostring(id), hint or "", value or "", flags)
  else
    submitted, text = r.ImGui_InputText(ctx, "##" .. tostring(id), value or "", flags)
  end
  seq_mark_text_input_item()
  return submitted == true, text or value or ""
end

function ui_popup_close_on_escape()
  if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
    r.ImGui_CloseCurrentPopup(ctx)
    return true
  end
  return false
end

-- Outline around the last drawn pill-shaped chip.
function ui_draw_chip_ring(color)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local rounding = (y1 - y0) * 0.5
  r.ImGui_DrawList_AddRect(dl, x0 - 0.5, y0 - 0.5, x1 + 0.5, y1 + 0.5, color, rounding + 0.5, 0, 1.35)
end

-- One-line muted hint at the bottom of a popup.
function ui_popup_footer(text)
  r.ImGui_Dummy(ctx, 1, 2)
  r.ImGui_TextColored(ctx, UI_THEME.text_mute, text or "")
end

-- Left-to-right wrapping layout for chips: call ui_flow_place(flow, w) before
-- drawing each item of width w.
function ui_flow_begin(gap)
  return { x = 0.0, first = true, gap = gap or 6.0, wrap = r.ImGui_GetContentRegionAvail(ctx) or 0 }
end

function ui_flow_place(flow, w)
  if not flow.first then
    if flow.x + flow.gap + w > flow.wrap then
      flow.x = 0.0
    else
      r.ImGui_SameLine(ctx, 0, flow.gap)
      flow.x = flow.x + flow.gap
    end
  end
  flow.first = false
  flow.x = flow.x + w
end

-- Scrolling children sized to their content (measured last frame), clamped to
-- [min_h, max_h], so auto-sizing popups don't jump or grow off screen.
-- Pass several keys to give side-by-side children the tallest one's height.
function ui_fit_child_height(keys, min_h, max_h)
  local measured = state.ui_fit_child_h or {}
  if type(keys) ~= "table" then
    keys = { keys }
  end
  local h = nil
  for _, key in ipairs(keys) do
    local v = measured[key]
    if v and (not h or v > h) then
      h = v
    end
  end
  return math.max(min_h, math.min(max_h, h or max_h))
end

-- Returns opened; call ui_fit_child_end(key, opened) afterwards.
function ui_fit_child_begin(key, w, h)
  return r.ImGui_BeginChild(ctx, key, w, h, 0, 0)
end

function ui_fit_child_end(key, opened)
  if not opened then
    return
  end
  local cy = r.ImGui_GetCursorPosY and r.ImGui_GetCursorPosY(ctx)
  if type(cy) == "number" then
    state.ui_fit_child_h = state.ui_fit_child_h or {}
    state.ui_fit_child_h[key] = cy + 2
  end
  imgui_end_child(true)
end

function ui_push_theme()
  local n_col, n_var = 0, 0
  local function col(getter, value)
    if getter then
      r.ImGui_PushStyleColor(ctx, getter(), value)
      n_col = n_col + 1
    end
  end
  local function var1(getter, value)
    if getter then
      r.ImGui_PushStyleVar(ctx, getter(), value)
      n_var = n_var + 1
    end
  end
  local function var2(getter, a, b)
    if getter then
      r.ImGui_PushStyleVar(ctx, getter(), a, b)
      n_var = n_var + 1
    end
  end

  local T = UI_THEME
  col(r.ImGui_Col_WindowBg, T.bg)
  col(r.ImGui_Col_ChildBg, 0x00000000)
  col(r.ImGui_Col_PopupBg, T.popup_bg)
  col(r.ImGui_Col_Border, T.border)
  col(r.ImGui_Col_BorderShadow, 0x00000000)
  col(r.ImGui_Col_Text, T.text)
  col(r.ImGui_Col_TextDisabled, T.text_mute)
  col(r.ImGui_Col_TextSelectedBg, 0x1EFF5E40)
  col(r.ImGui_Col_TitleBg, T.title_bg)
  col(r.ImGui_Col_TitleBgActive, T.title_bg_act)
  col(r.ImGui_Col_TitleBgCollapsed, T.title_bg)
  col(r.ImGui_Col_MenuBarBg, T.title_bg_act)
  col(r.ImGui_Col_FrameBg, T.surface)
  col(r.ImGui_Col_FrameBgHovered, T.surface_hvr)
  col(r.ImGui_Col_FrameBgActive, T.accent_fill)
  col(r.ImGui_Col_Button, T.surface)
  col(r.ImGui_Col_ButtonHovered, T.surface_hvr)
  col(r.ImGui_Col_ButtonActive, T.surface_act)
  col(r.ImGui_Col_Header, T.accent_fill)
  col(r.ImGui_Col_HeaderHovered, T.accent_fill_h)
  col(r.ImGui_Col_HeaderActive, 0x1A5A2CFF)
  col(r.ImGui_Col_Separator, T.border)
  col(r.ImGui_Col_SeparatorHovered, T.border_hvr)
  col(r.ImGui_Col_SeparatorActive, T.accent)
  col(r.ImGui_Col_CheckMark, T.accent)
  col(r.ImGui_Col_SliderGrab, T.accent)
  col(r.ImGui_Col_SliderGrabActive, T.accent_hvr)
  col(r.ImGui_Col_ResizeGrip, 0x1EFF5E22)
  col(r.ImGui_Col_ResizeGripHovered, 0x1EFF5E66)
  col(r.ImGui_Col_ResizeGripActive, T.accent)
  col(r.ImGui_Col_ScrollbarBg, 0x0C0F0D00)
  col(r.ImGui_Col_ScrollbarGrab, 0x3A4A4070)
  col(r.ImGui_Col_ScrollbarGrabHovered, 0x5A6A60AA)
  col(r.ImGui_Col_ScrollbarGrabActive, T.accent)
  col(r.ImGui_Col_Tab, T.surface)
  col(r.ImGui_Col_TabHovered, T.surface_hvr)
  col(r.ImGui_Col_TabActive, T.accent_fill)
  col(r.ImGui_Col_TableHeaderBg, T.elevated)
  col(r.ImGui_Col_TableBorderStrong, T.border)
  col(r.ImGui_Col_TableBorderLight, T.border_soft)
  col(r.ImGui_Col_TableRowBgAlt, 0xFFFFFF06)
  col(r.ImGui_Col_DragDropTarget, T.accent)
  col(r.ImGui_Col_ModalWindowDimBg, 0x000000A0)
  col(r.ImGui_Col_PlotHistogram, T.accent)
  col(r.ImGui_Col_NavHighlight, 0x00000000)

  var1(r.ImGui_StyleVar_WindowRounding, 10)
  var1(r.ImGui_StyleVar_ChildRounding, UI_METRICS.radius_panel)
  var1(r.ImGui_StyleVar_PopupRounding, UI_METRICS.radius_panel)
  var1(r.ImGui_StyleVar_FrameRounding, UI_METRICS.radius_ctrl)
  var1(r.ImGui_StyleVar_GrabRounding, 4)
  var1(r.ImGui_StyleVar_TabRounding, UI_METRICS.radius_ctrl)
  var1(r.ImGui_StyleVar_ScrollbarRounding, 8)
  var1(r.ImGui_StyleVar_WindowBorderSize, 1)
  var1(r.ImGui_StyleVar_ChildBorderSize, 0)
  var1(r.ImGui_StyleVar_PopupBorderSize, 1)
  var1(r.ImGui_StyleVar_FrameBorderSize, 0)
  var2(r.ImGui_StyleVar_WindowPadding, 10, 8)
  var2(r.ImGui_StyleVar_FramePadding, 8, 4)
  var2(r.ImGui_StyleVar_ItemSpacing, 6, 5)
  var2(r.ImGui_StyleVar_ItemInnerSpacing, 6, 4)
  var1(r.ImGui_StyleVar_GrabMinSize, 10)
  var1(r.ImGui_StyleVar_ScrollbarSize, 10)

  state._ui_theme_cols = n_col
  state._ui_theme_vars = n_var
end

function ui_pop_theme()
  local cols = state._ui_theme_cols or 0
  local vars = state._ui_theme_vars or 0
  state._ui_theme_cols = 0
  state._ui_theme_vars = 0
  if cols <= 0 and vars <= 0 then
    return
  end
  -- Docker float/dock can invalidate the context mid-frame. Never let a
  -- style-stack unwind take the script down with it.
  if not (ctx and r.ImGui_ValidatePtr(ctx, "ImGui_Context*")) then
    return
  end
  if cols > 0 then
    pcall(r.ImGui_PopStyleColor, ctx, cols)
  end
  if vars > 0 then
    pcall(r.ImGui_PopStyleVar, ctx, vars)
  end
end

function ui_draw_panel(dl, x0, y0, x1, y1, rounding, bg, border, hovered, active)
  rounding = rounding or 7.0
  if hovered and not active then
    r.ImGui_DrawList_AddRectFilled(dl, x0 - 0.5, y0 - 0.5, x1 + 0.5, y1 + 0.5, 0xFFFFFF10, rounding + 0.5)
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, bg, rounding)
  if not active then
    r.ImGui_DrawList_AddLine(dl, x0 + rounding, y0 + 1.0, x1 - rounding, y0 + 1.0, 0xFFFFFF16, 1.0)
  end
  if border and border ~= 0 then
    r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, border, rounding, 0, 1.0)
  end
end

function ui_button_colors_from_accent(accent, hovered, pressed)
  local cr, cg, cb = extract_rgb_rrgbbaa(accent or UI_THEME.accent)
  local function tone(t, a)
    return build_color_rrgbbaa(
      math.max(0, math.min(255, math.floor(cr * t))),
      math.max(0, math.min(255, math.floor(cg * t))),
      math.max(0, math.min(255, math.floor(cb * t))),
      a or 255
    )
  end
  if pressed then
    return tone(0.18), 0x00000000, 0xFFFFFFFF, tone(1.0), 1.2
  end
  if hovered then
    return tone(0.40), tone(1.0, 0x33), 0xFFFFFFFF, tone(1.0), 1.2
  end
  return tone(0.26), 0x00000000, 0xFFFFFFFF, tone(0.90), 1.0
end

function ui_button_colors(style, hovered, active, selected)
  local T = UI_THEME
  if style == "danger" then
    if active then return T.danger_fill, 0x00000000, 0xFFFFFFFF, T.danger, 1.0 end
    if hovered then return T.danger_hvr, 0xE0707028, 0xFFFFFFFF, 0xE0707055, 1.0 end
    return 0x2C1818FF, 0x00000000, 0xF0C4C4FF, 0xE0707033, 1.0
  elseif style == "ghost_arrow" then
    if active then return 0x00000000, 0x00000000, 0xB6FFD0FF, 0x1EFF5E33, 0.0 end
    if hovered then return 0x00000000, 0x00000000, 0xFFFFFFFF, 0x1EFF5E28, 0.0 end
    return 0x00000000, 0x00000000, 0x8AA898FF, 0x00000000, 0.0
  elseif style == "success" then
    if active then return T.success_fill, 0x00000000, 0xFFFFFFFF, T.success, 1.0 end
    if hovered then return T.success_hvr, 0x5EDC8A28, 0xFFFFFFFF, 0x5EDC8A55, 1.0 end
    return 0x173022FF, 0x00000000, 0xD4F5E0FF, 0x5EDC8A33, 1.0
  elseif style == "primary" or selected then
    if active then return 0x0A2212FF, 0x00000000, 0xFFFFFFFF, T.accent, 1.2 end
    if hovered then return T.accent_fill_h, 0x1EFF5E28, 0xFFFFFFFF, T.accent_hvr, 1.2 end
    return T.accent_fill, 0x00000000, 0xE8F8EEFF, 0x1EFF5E66, 1.0
  elseif style == "accent" then
    if active then return 0x0F3018FF, 0x00000000, 0xFFFFFFFF, T.accent_hvr, 1.2 end
    if hovered then return 0x1A5A2CFF, 0x1EFF5E33, 0xFFFFFFFF, T.accent_hvr, 1.2 end
    return 0x145028FF, 0x00000000, 0xF0FFF4FF, T.accent, 1.0
  end
  if active then return T.surface_act, 0x00000000, 0xFFFFFFFF, T.border_hvr, 1.0 end
  if hovered then return T.surface_hvr, 0xFFFFFF10, 0xFFFFFFFF, T.border_hvr, 1.0 end
  return T.surface, 0x00000000, T.text_dim, T.border, 1.0
end

function ui_button_draw_icon(dl, icon, cx, cy, size, color)
  local arm = size * 0.32
  local stroke = math.max(1.4, size * 0.08)
  if icon == "plus" then
    r.ImGui_DrawList_AddLine(dl, cx - arm, cy, cx + arm, cy, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx, cy - arm, cx, cy + arm, color, stroke)
  elseif icon == "minus" then
    r.ImGui_DrawList_AddLine(dl, cx - arm, cy, cx + arm, cy, color, stroke)
  elseif icon == "close" then
    r.ImGui_DrawList_AddLine(dl, cx - arm, cy - arm, cx + arm, cy + arm, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + arm, cy - arm, cx - arm, cy + arm, color, stroke)
  elseif icon == "check" then
    r.ImGui_DrawList_AddLine(dl, cx - arm * 0.85, cy + arm * 0.05, cx - arm * 0.12, cy + arm * 0.78, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - arm * 0.12, cy + arm * 0.78, cx + arm * 0.95, cy - arm * 0.70, color, stroke)
  elseif icon == "chev_left" then
    r.ImGui_DrawList_AddLine(dl, cx + arm * 0.28, cy - arm * 0.72, cx - arm * 0.38, cy, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - arm * 0.38, cy, cx + arm * 0.28, cy + arm * 0.72, color, stroke)
  elseif icon == "chev_right" then
    r.ImGui_DrawList_AddLine(dl, cx - arm * 0.28, cy - arm * 0.72, cx + arm * 0.38, cy, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + arm * 0.38, cy, cx - arm * 0.28, cy + arm * 0.72, color, stroke)
  elseif icon == "chev_down" then
    r.ImGui_DrawList_AddLine(dl, cx - arm * 0.72, cy - arm * 0.22, cx, cy + arm * 0.42, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx, cy + arm * 0.42, cx + arm * 0.72, cy - arm * 0.22, color, stroke)
  elseif icon == "chev_right_small" then
    r.ImGui_DrawList_AddTriangleFilled(dl, cx + arm * 0.28, cy, cx - arm * 0.42, cy - arm * 0.62, cx - arm * 0.42, cy + arm * 0.62, color)
  elseif icon == "play" then
    local h = size * 0.30
    r.ImGui_DrawList_AddTriangleFilled(dl, cx - h * 0.38, cy - h, cx - h * 0.38, cy + h, cx + h * 0.82, cy, color)
  elseif icon == "pause" then
    local h = size * 0.28
    local bar_w = size * 0.10
    local gap = size * 0.08
    r.ImGui_DrawList_AddRectFilled(dl, cx - gap - bar_w, cy - h, cx - gap, cy + h, color, 1.6)
    r.ImGui_DrawList_AddRectFilled(dl, cx + gap, cy - h, cx + gap + bar_w, cy + h, color, 1.6)
  elseif icon == "stop" then
    local s = size * 0.24
    r.ImGui_DrawList_AddRectFilled(dl, cx - s, cy - s, cx + s, cy + s, color, 2.2)
  elseif icon == "list" then
    local lw = size * 0.28
    local dot = math.max(1.0, size * 0.05)
    for i = -1, 1 do
      local ly = cy + i * (size * 0.20)
      r.ImGui_DrawList_AddCircleFilled(dl, cx - lw - dot * 1.4, ly, dot, color, 8)
      r.ImGui_DrawList_AddLine(dl, cx - lw, ly, cx + lw, ly, color, 1.6)
    end
  elseif icon == "midi" then
    local rad = size * 0.36
    r.ImGui_DrawList_AddCircle(dl, cx, cy, rad, color, 18, stroke)
    local pr = math.max(1.05, size * 0.055)
    local s = size * 0.22
    r.ImGui_DrawList_AddCircleFilled(dl, cx - s * 0.55, cy - s * 0.42, pr, color, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, cx + s * 0.55, cy - s * 0.42, pr, color, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, cx - s * 0.88, cy + s * 0.22, pr, color, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, cx + s * 0.88, cy + s * 0.22, pr, color, 8)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy + s * 0.72, pr, color, 8)
  elseif type(icon) == "string" and icon:match("^dice[1-6]$") then
    local count = tonumber(icon:match("(%d)$")) or 1
    local half = size * 0.26
    r.ImGui_DrawList_AddRect(dl, cx - half, cy - half, cx + half, cy + half, color, 3.0, 0, 1.4)
    local p = half * 0.48
    local pip_r = math.max(1.2, size * 0.045)
    local function pip(dx, dy)
      r.ImGui_DrawList_AddCircleFilled(dl, cx + dx, cy + dy, pip_r, color, 10)
    end
    if count == 1 or count == 3 or count == 5 then pip(0, 0) end
    if count >= 2 then pip(-p, -p) pip(p, p) end
    if count >= 4 then pip(p, -p) pip(-p, p) end
    if count == 6 then pip(-p, 0) pip(p, 0) end
  elseif icon == "link" then
    local rr = size * 0.15
    local gap = size * 0.13
    r.ImGui_DrawList_AddCircle(dl, cx - gap, cy, rr, color, 12, stroke)
    r.ImGui_DrawList_AddCircle(dl, cx + gap, cy, rr, color, 12, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - gap + rr * 0.35, cy, cx + gap - rr * 0.35, cy, color, stroke)
  elseif icon == "folder" then
    local hw, hh = size * 0.34, size * 0.24
    r.ImGui_DrawList_AddRectFilled(dl, cx - hw, cy - hh * 0.15, cx + hw, cy + hh, color, 1.8)
    r.ImGui_DrawList_AddRectFilled(dl, cx - hw, cy - hh, cx - hw * 0.05, cy - hh * 0.05, color, 1.6)
  elseif icon == "filter" then
    local hw, hh = size * 0.32, size * 0.26
    r.ImGui_DrawList_AddTriangleFilled(dl, cx - hw, cy - hh, cx + hw, cy - hh, cx, cy + hh * 0.18, color)
    r.ImGui_DrawList_AddRectFilled(dl, cx - size * 0.05, cy + hh * 0.02, cx + size * 0.05, cy + hh * 0.95, color)
  elseif icon == "hide" then
    local hw, hh = size * 0.34, size * 0.20
    r.ImGui_DrawList_AddCircle(dl, cx, cy, size * 0.11, color, 10, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - hw, cy, cx - hw * 0.35, cy - hh, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - hw * 0.35, cy - hh, cx + hw * 0.35, cy - hh, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + hw * 0.35, cy - hh, cx + hw, cy, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + hw, cy, cx + hw * 0.35, cy + hh, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + hw * 0.35, cy + hh, cx - hw * 0.35, cy + hh, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - hw * 0.35, cy + hh, cx - hw, cy, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - hw * 0.95, cy + hh * 1.25, cx + hw * 0.95, cy - hh * 1.25, color, stroke)
  elseif icon == "file" then
    local hw, hh = size * 0.22, size * 0.30
    r.ImGui_DrawList_AddRect(dl, cx - hw, cy - hh, cx + hw, cy + hh, color, 1.6, 0, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + hw * 0.05, cy - hh, cx + hw, cy - hh * 0.35, color, stroke)
  elseif icon == "audio" then
    local h = size * 0.28
    r.ImGui_DrawList_AddLine(dl, cx - h * 0.85, cy + h * 0.15, cx - h * 0.35, cy - h * 0.55, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - h * 0.35, cy - h * 0.55, cx + h * 0.05, cy + h * 0.45, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + h * 0.05, cy + h * 0.45, cx + h * 0.85, cy - h * 0.20, color, stroke)
  elseif icon == "popout" then
    if draw_fxd_icon and draw_fxd_icon(dl, "Expand", cx, cy, size, color) then
      return
    end
    local hw, hh = size * 0.28, size * 0.28
    r.ImGui_DrawList_AddRect(dl, cx - hw, cy - hh * 0.10, cx + hw * 0.42, cy + hh, color, 1.5, 0, stroke)
    r.ImGui_DrawList_AddLine(dl, cx - hw * 0.02, cy - hh * 0.08, cx + hw * 0.88, cy - hh * 0.88, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + hw * 0.22, cy - hh * 0.88, cx + hw * 0.88, cy - hh * 0.88, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx + hw * 0.88, cy - hh * 0.88, cx + hw * 0.88, cy - hh * 0.22, color, stroke)
  elseif icon == "layout" then
    local hw, hh = size * 0.30, size * 0.28
    local gap = math.max(1.2, size * 0.06)
    r.ImGui_DrawList_AddRect(dl, cx - hw, cy - hh, cx - gap * 0.2, cy + hh, color, 1.4, 0, stroke)
    r.ImGui_DrawList_AddRect(dl, cx + gap * 0.2, cy - hh, cx + hw, cy - gap * 0.15, color, 1.4, 0, stroke)
    r.ImGui_DrawList_AddRect(dl, cx + gap * 0.2, cy + gap * 0.15, cx + hw, cy + hh, color, 1.4, 0, stroke)
  else
    ui_draw_extra_icon(dl, icon, cx, cy, size, color, stroke)
  end
end

-- Sequencer toolbar glyphs. All are drawn inside roughly +-0.3 * size so they
-- sit at the same optical weight as the icons above.
local function ui_icon_polyline(dl, pts, color, stroke)
  for i = 1, #pts - 1 do
    r.ImGui_DrawList_AddLine(dl, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], color, stroke)
  end
end

function ui_draw_extra_icon(dl, icon, cx, cy, size, color, stroke)
  local s = size
  stroke = stroke or math.max(1.4, s * 0.08)
  if icon == "note" then
    local hx, hy = cx - s * 0.10, cy + s * 0.17
    r.ImGui_DrawList_AddCircleFilled(dl, hx, hy, s * 0.095, color, 12)
    local sx = hx + s * 0.085
    r.ImGui_DrawList_AddLine(dl, sx, hy, sx, cy - s * 0.27, color, stroke)
    r.ImGui_DrawList_AddLine(dl, sx, cy - s * 0.27, sx + s * 0.17, cy - s * 0.10, color, stroke)
  elseif icon == "gain" then
    local bw = s * 0.085
    local base = cy + s * 0.26
    local heights = { 0.22, 0.36, 0.52 }
    for i, hgt in ipairs(heights) do
      local bx = cx + (i - 2) * s * 0.18
      r.ImGui_DrawList_AddRectFilled(dl, bx - bw * 0.5, base - s * hgt, bx + bw * 0.5, base, color, 1.0)
    end
  elseif icon == "pan" then
    r.ImGui_DrawList_AddLine(dl, cx - s * 0.30, cy, cx + s * 0.30, cy, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx, cy - s * 0.12, cx, cy + s * 0.12, color, math.max(1.0, stroke * 0.7))
    r.ImGui_DrawList_AddCircleFilled(dl, cx + s * 0.16, cy, s * 0.085, color, 12)
  elseif icon == "pitch" then
    ui_icon_polyline(dl, { { cx - s * 0.18, cy - s * 0.06 }, { cx, cy - s * 0.26 }, { cx + s * 0.18, cy - s * 0.06 } }, color, stroke)
    ui_icon_polyline(dl, { { cx - s * 0.18, cy + s * 0.06 }, { cx, cy + s * 0.26 }, { cx + s * 0.18, cy + s * 0.06 } }, color, stroke)
  elseif icon == "start" then
    r.ImGui_DrawList_AddLine(dl, cx - s * 0.24, cy - s * 0.26, cx - s * 0.24, cy + s * 0.26, color, stroke)
    r.ImGui_DrawList_AddTriangleFilled(dl, cx - s * 0.10, cy - s * 0.20, cx - s * 0.10, cy + s * 0.20, cx + s * 0.24, cy, color)
  elseif icon == "stretch" then
    local hw, ah = s * 0.30, s * 0.11
    r.ImGui_DrawList_AddLine(dl, cx - hw, cy, cx + hw, cy, color, stroke)
    ui_icon_polyline(dl, { { cx - hw + ah, cy - ah }, { cx - hw, cy }, { cx - hw + ah, cy + ah } }, color, stroke)
    ui_icon_polyline(dl, { { cx + hw - ah, cy - ah }, { cx + hw, cy }, { cx + hw - ah, cy + ah } }, color, stroke)
    r.ImGui_DrawList_AddLine(dl, cx, cy - s * 0.22, cx, cy - s * 0.10, color, math.max(1.0, stroke * 0.7))
    r.ImGui_DrawList_AddLine(dl, cx, cy + s * 0.10, cx, cy + s * 0.22, color, math.max(1.0, stroke * 0.7))
  elseif icon == "decay" then
    local x0, x1 = cx - s * 0.28, cx + s * 0.30
    local top, bot = cy - s * 0.26, cy + s * 0.24
    local pts = { { x0, bot } }
    for i = 0, 8 do
      local t = i / 8
      pts[#pts + 1] = { x0 + (x1 - x0) * t, top + (bot - top) * (1.0 - math.exp(-4.0 * t)) }
    end
    ui_icon_polyline(dl, pts, color, stroke)
  elseif icon == "stutter" then
    local bw, hh = s * 0.075, s * 0.20
    for i = -1, 1 do
      local bx = cx + i * s * 0.17
      local scale = 1.0 - (i + 1) * 0.22
      r.ImGui_DrawList_AddRectFilled(dl, bx - bw * 0.5, cy + hh - hh * 2 * scale, bx + bw * 0.5, cy + hh, color, 1.0)
    end
  elseif icon == "vary" then
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, s * 0.075, color, 12)
    local dots = { { -0.22, -0.15 }, { 0.23, -0.10 }, { -0.04, 0.25 }, { 0.20, 0.18 } }
    for _, d in ipairs(dots) do
      r.ImGui_DrawList_AddCircleFilled(dl, cx + d[1] * s, cy + d[2] * s, s * 0.045, color, 8)
    end
    r.ImGui_DrawList_AddCircle(dl, cx, cy, s * 0.30, color, 20, math.max(1.0, stroke * 0.6))
  elseif icon == "lock" then
    local bw, top = s * 0.20, cy - s * 0.02
    r.ImGui_DrawList_AddRect(dl, cx - s * 0.12, cy - s * 0.28, cx + s * 0.12, top + s * 0.08, color, s * 0.12, 0, stroke)
    r.ImGui_DrawList_AddRectFilled(dl, cx - bw, top, cx + bw, cy + s * 0.27, color, 2.0)
  elseif icon == "grid" then
    local h = s * 0.26
    r.ImGui_DrawList_AddRect(dl, cx - h, cy - h, cx + h, cy + h, color, 2.0, 0, math.max(1.0, stroke * 0.8))
    local t = h * 2 / 3
    for i = 1, 2 do
      r.ImGui_DrawList_AddLine(dl, cx - h + t * i, cy - h, cx - h + t * i, cy + h, color, 1.0)
      r.ImGui_DrawList_AddLine(dl, cx - h, cy - h + t * i, cx + h, cy - h + t * i, color, 1.0)
    end
  elseif icon == "eye" then
    local hw, hh = s * 0.32, s * 0.18
    ui_icon_polyline(dl, {
      { cx - hw, cy }, { cx - hw * 0.45, cy - hh }, { cx + hw * 0.45, cy - hh }, { cx + hw, cy },
      { cx + hw * 0.45, cy + hh }, { cx - hw * 0.45, cy + hh }, { cx - hw, cy },
    }, color, stroke)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, s * 0.09, color, 12)
  elseif icon == "steps" then
    local cell, gap = s * 0.125, s * 0.045
    local total = cell * 4 + gap * 3
    local on = { [1] = { 1, 3 }, [2] = { 2, 4 } }
    for row = 1, 2 do
      local y = cy - cell - gap * 0.5 + (row - 1) * (cell + gap)
      for col = 1, 4 do
        local x = cx - total * 0.5 + (col - 1) * (cell + gap)
        local filled = false
        for _, c in ipairs(on[row]) do
          if c == col then filled = true end
        end
        if filled then
          r.ImGui_DrawList_AddRectFilled(dl, x, y, x + cell, y + cell, color, 1.0)
        else
          r.ImGui_DrawList_AddRect(dl, x, y, x + cell, y + cell, color, 1.0, 0, 1.0)
        end
      end
    end
  elseif icon == "star" or icon == "star_fill" then
    local outer = s * 0.33
    local inner = outer * 0.43
    local pts = {}
    for i = 0, 9 do
      local a = -math.pi * 0.5 + i * math.pi / 5
      local rad = (i % 2 == 0) and outer or inner
      pts[#pts + 1] = { cx + math.cos(a) * rad, cy + 0.03 * s + math.sin(a) * rad }
    end
    if icon == "star_fill" then
      for i = 1, 10 do
        local p, q = pts[i], pts[(i % 10) + 1]
        r.ImGui_DrawList_AddTriangleFilled(dl, cx, cy + 0.03 * s, p[1], p[2], q[1], q[2], color)
      end
    else
      pts[#pts + 1] = pts[1]
      ui_icon_polyline(dl, pts, color, math.max(1.0, stroke * 0.75))
    end
  elseif icon == "fill" then
    -- A run of hits getting taller into the downbeat.
    local bw = s * 0.07
    local base = cy + s * 0.24
    local heights = { 0.14, 0.22, 0.31, 0.42 }
    for i, hgt in ipairs(heights) do
      local bx = cx - s * 0.27 + (i - 1) * s * 0.15
      r.ImGui_DrawList_AddRectFilled(dl, bx - bw * 0.5, base - s * hgt, bx + bw * 0.5, base, color, 1.0)
    end
    r.ImGui_DrawList_AddCircleFilled(dl, cx + s * 0.30, cy - s * 0.20, s * 0.065, color, 10)
  elseif icon == "groove" then
    local pts = {}
    for i = 0, 12 do
      local t = i / 12
      pts[#pts + 1] = { cx - s * 0.30 + s * 0.60 * t, cy + math.sin(t * math.pi * 3.0) * s * 0.14 }
    end
    ui_icon_polyline(dl, pts, color, stroke)
  end
end

function draw_ui_button(id, label, w, h, opts)
  opts = opts or {}
  local style = opts.style or "default"
  local icon = opts.icon
  local trailing = opts.trailing_icon
  local display = label or ""
  if icon and not trailing then
    display = ""
  end
  local frame_padding = { r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding()) }
  local frame_pad_x = frame_padding[1]
  local frame_pad_y = frame_padding[2]
  if opts.compact then
    frame_pad_x = frame_pad_x * 0.65
    frame_pad_y = frame_pad_y * 0.65
  end

  local text_size = { r.ImGui_CalcTextSize(ctx, (display ~= "" and display) or "Ay") }
  local trail_w = trailing and 14 or 0
  -- Leading glyph drawn before the label (icon + text buttons).
  local lead = opts.lead_icon
  local lead_w = (lead and display ~= "") and 16 or 0
  if not w or w == 0 then
    if opts.full_width then
      w = r.ImGui_GetContentRegionAvail(ctx)
    elseif display ~= "" then
      w = text_size[1] + frame_pad_x * 2 + trail_w + lead_w
    else
      w = h or 26
    end
  end
  if not h or h == 0 then
    if display ~= "" then
      h = text_size[2] + frame_pad_y * 2
    else
      h = 26
    end
  end

  r.ImGui_InvisibleButton(ctx, "##ui_" .. tostring(id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local press = active and 1.0 or 0.0
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5 + press
  local rounding = opts.pill and (h * 0.5) or (opts.compact and 6.0 or 7.0)
  local tint = opts.color
  local bg, glow, text_col, border, border_w
  if tint and opts.selected then
    bg, glow, text_col, border, border_w = ui_button_colors_from_accent(tint, hovered, active)
  else
    bg, glow, text_col, border, border_w = ui_button_colors(style, hovered, active, opts.selected)
  end
  local is_ghost_arrow = style == "ghost_arrow"

  if is_ghost_arrow then
    if hovered or active then
      r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, active and math.min(w, h) * 0.40 or math.min(w, h) * 0.34, border, 22)
    end
  else
    if glow ~= 0 and hovered then
      r.ImGui_DrawList_AddRectFilled(dl, x0 - 1, y0 - 1, x1 + 1, y1 + 1, glow, rounding + 1)
    end
    ui_draw_panel(dl, x0, y0, x1, y1, rounding, bg, border, hovered, active)
    if opts.selected then
      r.ImGui_DrawList_AddRectFilled(dl, x0 + 6, y1 - 3, x1 - 6, y1 - 1.5, tint or UI_THEME.accent, 1.5)
    end
  end

  if icon and not trailing then
    local icon_size = math.min(w, h)
    local icon_color = (hovered or active) and 0xFFFFFFFF or text_col
    if is_ghost_arrow then
      if active then
        icon_size = icon_size * 1.12
        icon_color = 0xB6FFD0FF
      elseif hovered then
        icon_size = icon_size * 1.08
        icon_color = 0xFFFFFFFF
      end
    end
    ui_button_draw_icon(dl, icon, cx, cy, icon_size, icon_color)
  elseif display ~= "" then
    local text_x = x0 + (w - text_size[1] - trail_w - lead_w) * 0.5 + lead_w
    local text_y = y0 + (h - text_size[2]) * 0.5 + press
    if lead_w > 0 then
      local lead_col = opts.lead_color or ((hovered or active) and 0xFFFFFFFF or text_col)
      ui_button_draw_icon(dl, lead, text_x - lead_w * 0.5 - 1, cy, math.min(h, 24), lead_col)
    end
    r.ImGui_DrawList_AddText(dl, text_x, text_y, text_col, display)
    if trailing then
      ui_button_draw_icon(dl, trailing, x1 - 10, cy, 14, text_col)
    end
  end

  return clicked
end

function tag_is_suppressed(tag)
  local low = string.lower(tostring(tag or ""))
  return low ~= "" and state.deleted_tags and state.deleted_tags[low] == true
end

function tag_delete_modifier_down()
  if r.JS_Mouse_GetState then
    local cap = r.JS_Mouse_GetState(0)
    if cap & 16 == 16 then
      return true
    end
  end
  if r.ImGui_GetIO then
    local io = r.ImGui_GetIO(ctx)
    if io and io.KeyAlt then
      return true
    end
  end
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftAlt and r.ImGui_Key_RightAlt then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt())
  end
  return false
end

function request_tag_delete(tag)
  tag = tostring(tag or "")
  if tag == "" or tag:sub(1, 2) == "__" then
    return
  end
  state.tag_delete_pending = tag
  state.tag_delete_open_popup = true
end

function confirm_delete_tag(tag)
  tag = tostring(tag or "")
  if tag == "" then
    return
  end
  local needle = string.lower(tag)
  state.deleted_tags = state.deleted_tags or {}
  state.deleted_tags[needle] = true

  local function drop_from_list(list)
    if type(list) ~= "table" then
      return list, false
    end
    local kept, changed = {}, false
    for _, existing in ipairs(list) do
      if string.lower(tostring(existing)) == needle then
        changed = true
      else
        kept[#kept + 1] = existing
      end
    end
    return kept, changed
  end

  for _, sample in ipairs(state.samples or {}) do
    local kept, changed = drop_from_list(sample.tags)
    if changed then
      sample.tags = kept
    end
  end
  if preview_sample_obj then
    local kept, changed = drop_from_list(preview_sample_obj.tags)
    if changed then
      preview_sample_obj.tags = kept
    end
  end

  if type(state.custom_tags) == "table" then
    for path, tags in pairs(state.custom_tags) do
      local kept, changed = drop_from_list(tags)
      if changed then
        if #kept > 0 then
          state.custom_tags[path] = kept
        else
          state.custom_tags[path] = nil
        end
      end
    end
  end

  if state.active_tags then
    for key, _ in pairs(state.active_tags) do
      if string.lower(tostring(key)) == needle then
        state.active_tags[key] = nil
      end
    end
  end
  if state.tag_parent_map then
    state.tag_parent_map[needle] = nil
  end
  if state.discovered_library_tag_set then
    state.discovered_library_tag_set[needle] = nil
  end
  state.tag_category_rev = (state.tag_category_rev or 0) + 1
  if state.tag_colors then
    for key, _ in pairs(state.tag_colors) do
      if string.lower(tostring(key)) == needle then
        state.tag_colors[key] = nil
      end
    end
  end

  rebuild_tag_index()
  save_samples()
  save_config()
end

function render_tag_delete_popup()
  if state.tag_delete_open_popup and r.ImGui_OpenPopup then
    r.ImGui_OpenPopup(ctx, "Delete tag##tag_delete")
    state.tag_delete_open_popup = false
  end
  local tag = state.tag_delete_pending
  if not tag or tag == "" then
    return
  end
  if not r.ImGui_BeginPopupModal then
    return
  end
  local modal_flags = 0
  if r.ImGui_WindowFlags_AlwaysAutoResize then
    modal_flags = modal_flags | r.ImGui_WindowFlags_AlwaysAutoResize()
  end
  if r.ImGui_WindowFlags_NoMove then
    modal_flags = modal_flags | r.ImGui_WindowFlags_NoMove()
  end
  if r.ImGui_WindowFlags_NoCollapse then
    modal_flags = modal_flags | r.ImGui_WindowFlags_NoCollapse()
  end
  if r.ImGui_SetNextWindowPos and state.main_window_rect then
    local rect = state.main_window_rect
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    r.ImGui_SetNextWindowPos(ctx, rect.x + (rect.w or 0) * 0.5, rect.y + (rect.h or 0) * 0.42, cond, 0.5, 0.5)
  end
  local visible, keep = r.ImGui_BeginPopupModal(ctx, "Delete tag##tag_delete", true, modal_flags)
  if visible then
    local count = 0
    local needle = string.lower(tag)
    for _, sample in ipairs(state.samples or {}) do
      if type(sample.tags) == "table" then
        for _, existing in ipairs(sample.tags) do
          if string.lower(tostring(existing)) == needle then
            count = count + 1
            break
          end
        end
      end
    end
    r.ImGui_TextColored(ctx, UI_THEME.danger, string.format('Delete the "%s" tag?', tag))
    r.ImGui_Spacing(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, count == 1
      and "It will be removed from 1 sample."
      or string.format("It will be removed from %d samples.", count))
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "It will stay hidden unless you add it back by hand.")
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    if draw_ui_button("tag_delete_yes", "Delete", 90, 26, { compact = true, style = "danger" }) then
      confirm_delete_tag(tag)
      state.tag_delete_pending = nil
      if r.ImGui_CloseCurrentPopup then
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_SameLine(ctx)
    if draw_ui_button("tag_delete_no", "Cancel", 90, 26, { compact = true }) then
      state.tag_delete_pending = nil
      if r.ImGui_CloseCurrentPopup then
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_EndPopup(ctx)
  elseif keep == false then
    state.tag_delete_pending = nil
  end
end

function library_tag_sample_dir(sample)
  if not sample then
    return ""
  end
  local folder = normalize_path(sample.folder or "")
  if folder ~= "" then
    return folder
  end
  local path = normalize_path(sample.path or "")
  if path == "" then
    return ""
  end
  local dir = path:match("^(.*)/[^/]+$")
  return dir or path
end

function library_tag_highlight_needles(tag)
  local needles, seen = {}, {}
  local function add(n)
    n = string.lower(tostring(n or ""))
    if n == "" or seen[n] then
      return
    end
    seen[n] = true
    needles[#needles + 1] = n
  end
  add(tag)
  local tag_low = string.lower(tostring(tag or ""))
  for _, entry in ipairs(GENRE_KEYWORDS or {}) do
    if string.lower(entry.tag or "") == tag_low then
      for _, key in ipairs(entry.keys or {}) do
        add(key)
      end
    end
  end
  table.sort(needles, function(a, b)
    if #a == #b then
      return a < b
    end
    return #a > #b
  end)
  return needles
end

function collect_library_tag_unique_paths(tag)
  local out, seen = {}, {}
  local list = state.samples_by_tag and state.samples_by_tag[tag]
  if not list then
    local needle = string.lower(tostring(tag or ""))
    for _, sample in ipairs(state.samples or {}) do
      local set = sample._tag_set
      if set and set[tag] then
        local dir = library_tag_sample_dir(sample)
        if dir ~= "" and not seen[dir] then
          seen[dir] = true
          out[#out + 1] = dir
        end
      elseif type(sample.tags) == "table" then
        for _, existing in ipairs(sample.tags) do
          if string.lower(tostring(existing)) == needle then
            local dir = library_tag_sample_dir(sample)
            if dir ~= "" and not seen[dir] then
              seen[dir] = true
              out[#out + 1] = dir
            end
            break
          end
        end
      end
    end
  else
    for i = 1, #list do
      local dir = library_tag_sample_dir(list[i])
      if dir ~= "" and not seen[dir] then
        seen[dir] = true
        out[#out + 1] = dir
      end
    end
  end
  table.sort(out)
  return out
end

function open_library_tag_path_menu(tag)
  tag = tostring(tag or "")
  if tag == "" or categorize_tags(tag) ~= "genre" then
    return
  end
  state.library_tag_menu_tag = tag
  state.library_tag_menu_neg = ""
  state.library_tag_menu_status = nil
  state.library_tag_menu_paths = collect_library_tag_unique_paths(tag)
  state.library_tag_menu_needles = library_tag_highlight_needles(tag)
  state.library_tag_menu_open = true
end

function drop_tag_from_sample_list(sample, tag_needle)
  if not sample or type(sample.tags) ~= "table" then
    return false
  end
  local kept, changed = {}, false
  for _, existing in ipairs(sample.tags) do
    if string.lower(tostring(existing)) == tag_needle then
      changed = true
    else
      kept[#kept + 1] = existing
    end
  end
  if changed then
    sample.tags = kept
    sample._render_color = nil
  end
  return changed
end

-- One-shot: strip this library tag from samples whose path contains neg.
-- Not persisted as a rule — just cleans the current library membership.
function apply_library_tag_negative_string(tag, neg)
  tag = tostring(tag or "")
  neg = tostring(neg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if tag == "" or neg == "" then
    return 0
  end
  local tag_needle = string.lower(tag)
  local neg_low = string.lower(neg)
  local changed_n = 0

  local function path_hits(path)
    return path and path ~= "" and string.find(string.lower(path), neg_low, 1, true) ~= nil
  end

  for _, sample in ipairs(state.samples or {}) do
    local path = sample.path or ""
    local folder = sample.folder or ""
    if path_hits(path) or path_hits(folder) then
      if drop_tag_from_sample_list(sample, tag_needle) then
        changed_n = changed_n + 1
      end
    end
  end
  if preview_sample_obj then
    local path = preview_sample_obj.path or ""
    local folder = preview_sample_obj.folder or ""
    if path_hits(path) or path_hits(folder) then
      drop_tag_from_sample_list(preview_sample_obj, tag_needle)
    end
  end

  if type(state.custom_tags) == "table" then
    for path, tags in pairs(state.custom_tags) do
      if path_hits(path) and type(tags) == "table" then
        local kept, changed = {}, false
        for _, existing in ipairs(tags) do
          if string.lower(tostring(existing)) == tag_needle then
            changed = true
          else
            kept[#kept + 1] = existing
          end
        end
        if changed then
          if #kept > 0 then
            state.custom_tags[path] = kept
          else
            state.custom_tags[path] = nil
          end
        end
      end
    end
  end

  if changed_n > 0 then
    rebuild_tag_index()
    save_samples()
  end
  return changed_n
end

function draw_highlighted_path_text(path, needles)
  path = tostring(path or "")
  if path == "" then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "(empty)")
    return
  end
  needles = needles or {}
  local lower = string.lower(path)
  local pos = 1
  local first = true
  while pos <= #path do
    local match_at, match_len = nil, 0
    for i = 1, #needles do
      local n = needles[i]
      if n and #n > 0 then
        local a = string.find(lower, n, pos, true)
        if a and (not match_at or a < match_at or (a == match_at and #n > match_len)) then
          match_at = a
          match_len = #n
        end
      end
    end
    if not match_at then
      local rest = path:sub(pos)
      if rest ~= "" then
        if not first then
          r.ImGui_SameLine(ctx, 0, 0)
        end
        r.ImGui_TextColored(ctx, UI_THEME.text_dim, rest)
      end
      break
    end
    if match_at > pos then
      if not first then
        r.ImGui_SameLine(ctx, 0, 0)
      end
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, path:sub(pos, match_at - 1))
      first = false
    end
    if not first then
      r.ImGui_SameLine(ctx, 0, 0)
    end
    r.ImGui_TextColored(ctx, UI_THEME.accent_hvr, path:sub(match_at, match_at + match_len - 1))
    first = false
    pos = match_at + match_len
  end
end

function render_library_tag_path_menu()
  if state.library_tag_menu_open and r.ImGui_OpenPopup then
    r.ImGui_OpenPopup(ctx, "Library tag paths##lib_tag_paths")
    state.library_tag_menu_open = false
  end
  local tag = state.library_tag_menu_tag
  if not tag or tag == "" then
    return
  end
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 480, 360, 860, 720)
  end
  if r.ImGui_SetNextWindowSize then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    r.ImGui_SetNextWindowSize(ctx, 560, 420, cond)
  end
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, "Library tag paths##lib_tag_paths") then
    if r.ImGui_IsPopupOpen and not r.ImGui_IsPopupOpen(ctx, "Library tag paths##lib_tag_paths") then
      state.library_tag_menu_tag = nil
      state.library_tag_menu_paths = nil
      state.library_tag_menu_status = nil
    end
    return
  end

  r.ImGui_Text(ctx, "Library tag")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.accent_hvr, tag)
  local paths = state.library_tag_menu_paths or {}
  r.ImGui_TextColored(ctx, UI_THEME.text_mute, string.format("%d unique folder path(s)", #paths))
  r.ImGui_Spacing(ctx)

  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Negative string")
  r.ImGui_SetNextItemWidth(ctx, -1)
  local _, neg = r.ImGui_InputText(ctx, "##lib_tag_neg", state.library_tag_menu_neg or "")
  seq_mark_text_input_item()
  if neg ~= nil then
    state.library_tag_menu_neg = neg
  end
  r.ImGui_TextColored(ctx, UI_THEME.text_mute,
    'Paths containing this text lose the tag (e.g. "big fish" for tag "big"). One-time — not saved.')
  r.ImGui_Spacing(ctx)
  local can_apply = (state.library_tag_menu_neg or ""):match("%S") ~= nil
  if draw_ui_button("lib_tag_neg_apply", "Remove from matching paths", nil, 26, {
    compact = true,
    style = "danger",
  }) and can_apply then
    local n = apply_library_tag_negative_string(tag, state.library_tag_menu_neg)
    state.library_tag_menu_status = n == 0
      and "No samples matched."
      or string.format("Removed from %d sample(s).", n)
    state.library_tag_menu_neg = ""
    state.library_tag_menu_paths = collect_library_tag_unique_paths(tag)
    if #(state.library_tag_menu_paths or {}) == 0 then
      state.library_tag_menu_tag = nil
      if r.ImGui_CloseCurrentPopup then
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
  end
  if state.library_tag_menu_status then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, state.library_tag_menu_status)
  end

  r.ImGui_Spacing(ctx)
  r.ImGui_Separator(ctx)
  r.ImGui_Spacing(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Paths (matched words highlighted)")

  -- Popups auto-resize; leftover-height children shrink the window every frame.
  local opened = r.ImGui_BeginChild(ctx, "##lib_tag_path_list", 0, 260, 1)
  if opened then
    local needles = state.library_tag_menu_needles or library_tag_highlight_needles(tag)
    if #paths == 0 then
      r.ImGui_TextColored(ctx, UI_THEME.text_mute, "No paths for this tag.")
    else
      for i = 1, #paths do
        draw_highlighted_path_text(paths[i], needles)
      end
    end
  end
  imgui_end_child(opened)

  r.ImGui_EndPopup(ctx)
end

function draw_tag_button(ctx, label, active, tag, id_prefix, opts)
  id_prefix = id_prefix or ""
  opts = opts or {}
  local text_size = {r.ImGui_CalcTextSize(ctx, label)}
  local frame_padding = {r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())}
  local button_width = text_size[1] + frame_padding[1] * 2
  local button_height = text_size[2] + frame_padding[2] * 2
  local tag_color = state.tag_colors[tag] or 0x336699
  local base_r, base_g, base_b = extract_rgb(tag_color)
  local allow_delete = opts.allow_delete ~= false
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id_prefix .. "tag_" .. label, button_width, button_height)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  if hovered then
    state.hovered_tag = tag
  end
  local alt_delete = allow_delete and hovered and tag_delete_modifier_down()
    and type(tag) == "string" and tag ~= "" and tag:sub(1, 2) ~= "__"

  local factor, alpha, text_color
  if alt_delete then
    factor = hovered and 0.42 or 0.32
    alpha = hovered and 255 or 210
    text_color = 0xFFB0B0FF
  elseif active then
    factor = hovered and 0.82 or 0.70
    alpha = 255
    text_color = 0xFFFFFFFF
  elseif hovered then
    factor = 0.55
    alpha = 220
    text_color = 0xF4F4F4FF
  else
    factor = 0.38
    alpha = 160
    text_color = 0xD0D0D0FF
  end
  if pressed then
    factor = factor * 0.88
  end

  local bg = build_color_rrgbbaa(
    math.floor(base_r * factor),
    math.floor(base_g * factor),
    math.floor(base_b * factor),
    alpha
  )
  local border = build_color_rrgbbaa(
    math.min(255, math.floor(base_r * (active and 0.95 or 0.70))),
    math.min(255, math.floor(base_g * (active and 0.95 or 0.70))),
    math.min(255, math.floor(base_b * (active and 0.95 or 0.70))),
    hovered and 220 or 140
  )
  if alt_delete then
    bg = build_color_rrgbbaa(120, 28, 28, hovered and 230 or 190)
    border = build_color_rrgbbaa(255, 92, 92, hovered and 230 or 180)
  end
  local rounding = button_height * 0.5
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local press = pressed and 1.0 or 0.0
  ui_draw_panel(dl, x0, y0, x1, y1, rounding, bg, border, hovered, pressed)
  local text_x = x0 + frame_padding[1]
  local text_y = y0 + frame_padding[2] + press
  r.ImGui_DrawList_AddText(dl, text_x, text_y, text_color, label)
  if active and not alt_delete then
    r.ImGui_DrawList_AddText(dl, text_x + 0.4, text_y, text_color, label)
  end
  if alt_delete then
    local cx = (x0 + x1) * 0.5
    local cy = (y0 + y1) * 0.5 + press
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, build_color_rrgbbaa(18, 6, 6, 90), rounding)
    ui_button_draw_icon(dl, "close", cx, cy, math.min(button_width, button_height) * 0.78, 0xFF5C5CFF)
  end
  if hovered and alt_delete and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Delete tag from library")
  end
  if clicked and alt_delete then
    request_tag_delete(tag)
    return false
  end
  if hovered and type(tag) == "string" and tag ~= "" and tag:sub(1, 2) ~= "__"
      and r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
      and categorize_tags(tag) == "genre" then
    open_library_tag_path_menu(tag)
  end
  return clicked
end

function draw_ui_checkbox(id, label, checked)
  local box = 15.0
  local gap = 8.0
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local h = math.max(box, th + 2)
  local w = box + gap + tw
  r.ImGui_InvisibleButton(ctx, "##chk_" .. tostring(id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local bx0 = x0
  local by0 = y0 + (h - box) * 0.5 + (active and 1.0 or 0.0)
  local bx1, by1 = bx0 + box, by0 + box
  local bg = checked and UI_THEME.accent_fill or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)
  local border = checked and UI_THEME.accent or (hovered and UI_THEME.border_hvr or UI_THEME.border)
  ui_draw_panel(dl, bx0, by0, bx1, by1, 4.0, bg, border, hovered, active)
  if checked then
    ui_button_draw_icon(dl, "check", bx0 + box * 0.5, by0 + box * 0.5, box, 0xFFFFFFFF)
  end
  r.ImGui_DrawList_AddText(dl, x0 + box + gap, y0 + (h - th) * 0.5, UI_THEME.text, label)
  if clicked then
    return true, not checked
  end
  return false, checked
end

function draw_ui_radio(id, label, selected)
  local rad = 7.5
  local gap = 8.0
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local h = math.max(rad * 2 + 2, th + 2)
  local w = rad * 2 + gap + tw
  r.ImGui_InvisibleButton(ctx, "##rad_" .. tostring(id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local cx = x0 + rad
  local cy = y0 + h * 0.5 + (active and 1.0 or 0.0)
  local ring = selected and UI_THEME.accent or (hovered and UI_THEME.border_hvr or UI_THEME.border)
  local fill = hovered and UI_THEME.surface_hvr or UI_THEME.surface
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, fill, 20)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, rad, ring, 20, selected and 1.6 or 1.2)
  if selected then
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad * 0.42, UI_THEME.accent, 16)
  elseif hovered then
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad * 0.22, 0x1EFF5E66, 12)
  end
  r.ImGui_DrawList_AddText(dl, x0 + rad * 2 + gap, y0 + (h - th) * 0.5, UI_THEME.text, label)
  return clicked
end

function draw_ui_combo(id, label, preview, choices, current, stringify)
  stringify = stringify or tostring
  local btn_w = 150
  if draw_ui_button(id, preview, btn_w, 24, { compact = true, trailing_icon = "chev_down" }) then
    r.ImGui_OpenPopup(ctx, "##combo_" .. tostring(id))
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, label)

  local changed = false
  local value = current
  if r.ImGui_BeginPopup(ctx, "##combo_" .. tostring(id)) then
    for _, choice in ipairs(choices) do
      local choice_label = stringify(choice)
      local is_sel = (choice == current)
      if draw_ui_button(id .. "_opt_" .. tostring(choice), choice_label, 180, 22, {
        compact = true,
        style = is_sel and "accent" or "default",
        selected = is_sel,
      }) then
        changed = true
        value = choice
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  return changed, value
end

function draw_ui_number(id, label, value, step, step_fast, format, min_v, max_v)
  step = step or 0.1
  step_fast = step_fast or (step * 10)
  format = format or "%.1f"
  local h = 24
  local changed = false
  local coarse = is_shift_down and is_shift_down()
  local delta = coarse and step_fast or step
  if draw_ui_button(id .. "_minus", nil, h, h, { icon = "minus", compact = true }) then
    value = value - delta
    changed = true
  end
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 88)
  local ret, v = r.ImGui_InputDouble(ctx, "##num_" .. tostring(id), value, 0, 0, format)
  if ret then
    value = v
    changed = true
  end
  r.ImGui_SameLine(ctx, 0, 4)
  if draw_ui_button(id .. "_plus", nil, h, h, { icon = "plus", compact = true }) then
    value = value + delta
    changed = true
  end
  if changed then
    if min_v then value = math.max(min_v, value) end
    if max_v then value = math.min(max_v, value) end
  end
  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, label)
  return changed, value
end

function draw_ui_color(id, label, rgb24, inline)
  local cr, cg, cb = extract_rgb(rgb24 or 0x336699)
  local fill = build_color_rrgbbaa(cr, cg, cb, 255)
  local size = 18
  r.ImGui_InvisibleButton(ctx, "##swatch_" .. tostring(id), size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  ui_draw_panel(dl, x0, y0, x1, y1, 5.0, fill, hovered and 0xFFFFFFFF or UI_THEME.border, hovered, active)
  if clicked and not inline then
    r.ImGui_OpenPopup(ctx, "##color_" .. tostring(id))
  end
  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, label)

  local changed = false
  local new_color = rgb24
  local function run_picker()
    local picker = r.ImGui_ColorPicker3 or r.ImGui_ColorEdit3
    if picker then
      local ok, result = picker(ctx, "##picker_" .. tostring(id), (rgb24 or 0) | 0xFF000000, 0)
      if ok then
        changed = true
        new_color = result & 0xFFFFFF
      end
    end
  end
  if inline then
    run_picker()
  elseif r.ImGui_BeginPopup(ctx, "##color_" .. tostring(id)) then
    run_picker()
    r.ImGui_EndPopup(ctx)
  end
  return changed, new_color
end


-- Function to save tag colors to current preset
function save_tag_color_to_preset(tag, color)
  -- Load current presets (cached in memory)
  local tag_presets = sm_get_tag_presets()
  
  -- Ensure current preset exists
  if not tag_presets[state.current_preset_name] then
    tag_presets[state.current_preset_name] = {}
  end
  
  -- Update the tag color in the preset
  tag_presets[state.current_preset_name][tag] = color
  
  -- Save presets back to file
  sm_save_tag_presets(tag_presets)
end

-- Persist a tag colour edited in the picker once the edit finishes (not on every drag frame).
function sm_flush_tag_color_save()
  local pending = state.tag_color_pending_save
  if not pending then
    return
  end
  state.tag_color_pending_save = nil
  save_tag_color_to_preset(pending.tag, pending.color)
  save_config()
end

-- Built-in tag categories (case-insensitive keys).
SM_TAG_CATEGORY_DRUM = {
  kick = true, snare = true, clap = true, snap = true, rim = true, hat = true,
  tom = true, ride = true, crash = true, perc = true, fx = true,
  bass = true, ["808"] = true, ["808s"] = true, drum = true
}
SM_TAG_CATEGORY_MELODIC = {
  vocal = true, pluck = true, lead = true, pad = true,
  keys = true, guitar = true, swell = true  -- Swell is melodic
}
-- Loop/oneshot category tags (handle both "One shot" and "oneshot")
SM_TAG_CATEGORY_LOOP = {
  loop = true, ["one shot"] = true, oneshot = true
}

-- Per-tag category memo. Dropped when tag_parent_map / the discovered library
-- tags are replaced, or when state.tag_category_rev is bumped (in-place edits,
-- rebuild_tag_index).
function sm_tag_category_cache()
  local c = state.tag_category_cache
  if not c or c.parent_map ~= state.tag_parent_map
      or c.discovered ~= state.discovered_library_tag_set
      or c.rev ~= (state.tag_category_rev or 0) then
    c = {
      parent_map = state.tag_parent_map,
      discovered = state.discovered_library_tag_set,
      rev = state.tag_category_rev or 0,
      map = {},
    }
    state.tag_category_cache = c
  end
  return c.map
end

function sm_compute_tag_category(tag)
  -- Normalize tag to lowercase for comparison (but preserve original for display)
  local tag_lower = string.lower(tostring(tag or ""))
  if tag_lower == "" then
    return nil
  end
  if state.tag_parent_map and state.tag_parent_map[tag_lower] then
    return state.tag_parent_map[tag_lower]
  end
  if SM_TAG_CATEGORY_DRUM[tag_lower] then
    return "drum"
  elseif SM_TAG_CATEGORY_MELODIC[tag_lower] then
    return "melodic"
  elseif GENRE_TAG_SET[tag_lower] or (state.discovered_library_tag_set and state.discovered_library_tag_set[tag_lower]) then
    return "genre"
  elseif SM_TAG_CATEGORY_LOOP[tag_lower] then
    return "loop"
  end
  return nil
end

-- Helper function to categorize tags
function categorize_tags(tag)
  if tag == nil then
    return nil
  end
  local map = sm_tag_category_cache()
  local cat = map[tag]
  if cat == nil then
    cat = sm_compute_tag_category(tag) or false
    map[tag] = cat
  end
  return cat or nil
end

-- Tags of the current tag_list grouped by category (rebuilt with the tag index).
function sm_tag_category_lists()
  local map = sm_tag_category_cache()
  local c = state.tag_category_lists
  if not c or c.map ~= map or c.list ~= state.tag_list or c.epoch ~= state.tag_index_epoch then
    c = { map = map, list = state.tag_list, epoch = state.tag_index_epoch, by_cat = {} }
    for _, entry in ipairs(state.tag_list or {}) do
      local cat = categorize_tags(entry.tag)
      if cat then
        local list = c.by_cat[cat]
        if not list then
          list = {}
          c.by_cat[cat] = list
        end
        list[#list + 1] = entry.tag
      end
    end
    state.tag_category_lists = c
  end
  return c.by_cat
end

function builtin_tag_parents()
  return {
    { id = "drum", label = "Drums" },
    { id = "melodic", label = "Melodic" },
    { id = "genre", label = "Library" },
    { id = "loop", label = "Loop" },
  }
end

function list_tag_parents()
  local out = {}
  for _, parent in ipairs(builtin_tag_parents()) do
    out[#out + 1] = parent
  end
  for _, parent in ipairs(state.custom_tag_parents or {}) do
    if parent and parent.id and parent.label then
      out[#out + 1] = parent
    end
  end
  return out
end

function tag_parent_display_name(id)
  if not id then
    return nil
  end
  for _, parent in ipairs(list_tag_parents()) do
    if parent.id == id then
      return parent.label
    end
  end
  return id
end

function tag_candidate_label(tag)
  local child = tostring(tag or "")
  local pretty = SEQ_ROLE_LABELS and SEQ_ROLE_LABELS[string.lower(child)]
  if pretty then
    child = pretty
  end
  local parent = categorize_tags(tag)
  if parent then
    return tag_parent_display_name(parent) .. " : " .. child
  end
  return child
end

function assign_tag_parent(tag, parent_id)
  tag = explorer_normalize_tag(tag)
  if tag == "" or not parent_id or parent_id == "" then
    return false
  end
  state.tag_parent_map = state.tag_parent_map or {}
  state.tag_parent_map[string.lower(tag)] = parent_id
  state.tag_category_rev = (state.tag_category_rev or 0) + 1
  return true
end

function create_custom_tag_parent(label)
  label = explorer_normalize_tag(label)
  if label == "" then
    return nil
  end
  state.custom_tag_parents = state.custom_tag_parents or {}
  for _, parent in ipairs(list_tag_parents()) do
    if string.lower(parent.label) == string.lower(label) or parent.id == string.lower(label) then
      return parent.id
    end
  end
  local id = string.lower(label):gsub("%s+", "_"):gsub("[^%w_]", "")
  if id == "" then
    id = "parent"
  end
  local base, n = id, 2
  local used = {}
  for _, parent in ipairs(list_tag_parents()) do
    used[parent.id] = true
  end
  while used[id] do
    id = base .. "_" .. tostring(n)
    n = n + 1
  end
  state.custom_tag_parents[#state.custom_tag_parents + 1] = { id = id, label = label }
  return id
end

function tag_add_open_for(path)
  path = normalize_path(path or "")
  state.tag_add_target_path = path
  state.tag_add_query = ""
  state.tag_add_new_name = ""
  state.tag_add_parent_name = ""
  state.tag_add_create_open = false
  state.tag_add_parent_prompt = false
end

function tag_add_apply_existing(tag)
  local path = state.tag_add_target_path
  if not path or path == "" or not tag then
    return
  end
  explorer_add_tag(path, tag)
  state.tag_add_query = ""
  state.tag_add_should_close = true
  if r.ImGui_CloseCurrentPopup then
    r.ImGui_CloseCurrentPopup(ctx)
  end
end

function tag_add_create_under_parent(parent_id)
  local name = explorer_normalize_tag(state.tag_add_new_name)
  local path = state.tag_add_target_path
  if name == "" or not parent_id or not path or path == "" then
    return
  end
  assign_tag_parent(name, parent_id)
  explorer_add_tag(path, name)
  state.tag_add_create_open = false
  state.tag_add_parent_prompt = false
  state.tag_add_query = ""
  state.tag_add_new_name = ""
  state.tag_add_should_close = true
  save_config()
  if r.ImGui_CloseCurrentPopup then
    r.ImGui_CloseCurrentPopup(ctx)
  end
end

function tag_add_match_candidates(query, exclude_set)
  query = string.lower(explorer_normalize_tag(query))
  if query == "" then
    return {}
  end
  local seen, out = {}, {}
  local function consider(tag)
    if not tag or tag == "" then
      return
    end
    local key = string.lower(tag)
    if seen[key] or (exclude_set and exclude_set[key]) then
      return
    end
    local hay = string.lower(tag .. " " .. (tag_candidate_label(tag) or ""))
    if string.find(hay, query, 1, true) then
      seen[key] = true
      out[#out + 1] = tag
    end
  end
  for _, tag in ipairs(explorer_known_tags()) do
    consider(tag)
    if #out >= 10 then
      return out
    end
  end
  for child, _ in pairs(state.tag_parent_map or {}) do
    consider(child)
    if #out >= 10 then
      return out
    end
  end
  return out
end

function render_tag_add_create_popup()
  if not r.ImGui_BeginPopup(ctx, "##tag_add_create") then
    return
  end
  r.ImGui_Text(ctx, "Create new tag")
  r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Name the tag, then choose a parent")
  r.ImGui_SetNextItemWidth(ctx, 260)
  local _, name = r.ImGui_InputText(ctx, "##tag_add_new_name", state.tag_add_new_name or "")
  seq_mark_text_input_item()
  if name ~= nil then
    state.tag_add_new_name = name
  end
  r.ImGui_Spacing(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Put under")
  local ready = explorer_normalize_tag(state.tag_add_new_name) ~= ""
  for i, parent in ipairs(list_tag_parents()) do
    if i > 1 then
      imgui_same_line_if_fits(calc_tag_chip_width(parent.label), 4)
    end
    local clicked = draw_ui_button("tag_add_parent_" .. parent.id, parent.label, nil, nil, {
      compact = true,
      style = ready and "primary" or "default",
    })
    if clicked and ready then
      tag_add_create_under_parent(parent.id)
    end
  end
  r.ImGui_Spacing(ctx)
  if draw_ui_button("tag_add_new_parent", "Create new parent tag", nil, nil, { compact = true }) then
    state.tag_add_parent_prompt = true
    state.tag_add_parent_name = ""
  end
  if state.tag_add_parent_prompt then
    r.ImGui_SetNextItemWidth(ctx, 200)
    local _, parent_name = r.ImGui_InputText(ctx, "##tag_add_parent_name", state.tag_add_parent_name or "")
    seq_mark_text_input_item()
    if parent_name ~= nil then
      state.tag_add_parent_name = parent_name
    end
    r.ImGui_SameLine(ctx)
    if draw_ui_button("tag_add_parent_save", "Save", nil, nil, { compact = true, style = "primary" }) then
      local parent_id = create_custom_tag_parent(state.tag_add_parent_name)
      if parent_id and ready then
        tag_add_create_under_parent(parent_id)
      elseif parent_id then
        save_config()
        state.tag_add_parent_prompt = false
      end
    end
  end
  r.ImGui_EndPopup(ctx)
end

function render_tag_add_popup()
  if not r.ImGui_BeginPopup(ctx, "##tag_add_popup") then
    render_tag_add_create_popup()
    return
  end
  if state.tag_add_should_close then
    state.tag_add_should_close = false
    r.ImGui_CloseCurrentPopup(ctx)
    r.ImGui_EndPopup(ctx)
    return
  end
  r.ImGui_Text(ctx, "Add tag")
  if r.ImGui_IsWindowAppearing and r.ImGui_IsWindowAppearing(ctx) and r.ImGui_SetKeyboardFocusHere then
    r.ImGui_SetKeyboardFocusHere(ctx)
  end
  r.ImGui_SetNextItemWidth(ctx, 280)
  local enter_flags = 0
  if r.ImGui_InputTextFlags_EnterReturnsTrue then
    enter_flags = r.ImGui_InputTextFlags_EnterReturnsTrue()
  end
  local submitted, text
  if r.ImGui_InputTextWithHint then
    submitted, text = r.ImGui_InputTextWithHint(ctx, "##tag_add_query", "Type to find a tag…", state.tag_add_query or "", enter_flags)
  else
    submitted, text = r.ImGui_InputText(ctx, "##tag_add_query", state.tag_add_query or "", enter_flags)
  end
  seq_mark_text_input_item()
  if text ~= nil then
    state.tag_add_query = text
  end

  local path = state.tag_add_target_path
  local current = {}
  if path and path ~= "" then
    for _, tag in ipairs(explorer_get_tags(path)) do
      current[string.lower(tag)] = true
    end
  end
  local query = explorer_normalize_tag(state.tag_add_query)
  local matches = tag_add_match_candidates(query, current)

  if query ~= "" and #matches > 0 then
    r.ImGui_Spacing(ctx)
    for _, tag in ipairs(matches) do
      local label = tag_candidate_label(tag)
      if r.ImGui_Selectable(ctx, label .. "##cand_" .. tag) then
        tag_add_apply_existing(tag)
      end
    end
    if submitted then
      tag_add_apply_existing(matches[1])
    end
  elseif query ~= "" then
    r.ImGui_Spacing(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "No matching tags")
    if draw_ui_button("tag_add_create", "Create new tag", nil, nil, { style = "primary", compact = true }) then
      state.tag_add_new_name = query
      r.ImGui_OpenPopup(ctx, "##tag_add_create")
    end
  else
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Start typing to see candidates like Drums : Kick")
  end

  render_tag_add_create_popup()
  r.ImGui_EndPopup(ctx)
end

function is_loop_oneshot_filter_tag(tag)
  local lower = string.lower(tostring(tag or ""))
  return lower == "loop" or lower == "one shot" or lower == "oneshot"
end

function clear_loop_oneshot_filters(except_tag)
  local except_lower = except_tag and string.lower(tostring(except_tag)) or nil
  for tag, active in pairs(state.active_tags or {}) do
    if active and is_loop_oneshot_filter_tag(tag) then
      if not except_lower or string.lower(tostring(tag)) ~= except_lower then
        state.active_tags[tag] = nil
      end
    end
  end
end

function toggle_sample_map_tag_filter(tag)
  if not tag then
    return
  end
  state.active_tags = state.active_tags or {}
  local active = state.active_tags[tag]
  if is_loop_oneshot_filter_tag(tag) then
    if active then
      state.active_tags[tag] = nil
    else
      clear_loop_oneshot_filters(tag)
      state.active_tags[tag] = true
    end
    return
  end
  if active then
    state.active_tags[tag] = nil
  else
    state.active_tags[tag] = true
  end
end

-- Helper function to draw a larger category tag
function draw_category_tag(ctx, label, id_prefix, active)
  id_prefix = id_prefix or ""
  local text_size = {r.ImGui_CalcTextSize(ctx, label)}
  local frame_padding = {r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())}
  local button_width = text_size[1] + frame_padding[1] * 2
  local button_height = text_size[2] + frame_padding[2] * 2

  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id_prefix .. "cat_" .. label, button_width, button_height)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg, border, text
  if active then
    bg = hovered and UI_THEME.accent_fill_h or UI_THEME.accent_fill
    border = UI_THEME.accent
    text = 0xFFFFFFFF
  elseif hovered then
    bg = UI_THEME.surface_hvr
    border = UI_THEME.border_hvr
    text = UI_THEME.text
  else
    bg = UI_THEME.surface
    border = UI_THEME.border
    text = UI_THEME.text_dim
  end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  ui_draw_panel(dl, x0, y0, x1, y1, button_height * 0.5, bg, border, hovered, pressed)
  local text_x = x0 + (button_width - text_size[1]) * 0.5
  local text_y = y0 + (button_height - text_size[2]) * 0.5 + (pressed and 1.0 or 0.0)
  r.ImGui_DrawList_AddText(dl, text_x, text_y, text, label)
  return clicked
end

function imgui_window_right_x()
  local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_WindowPadding())
  local win_x = r.ImGui_GetWindowPos(ctx)
  local win_w = select(1, r.ImGui_GetWindowSize(ctx))
  return win_x + win_w - (pad_x or 8)
end

-- Child border flag: ReaImGui 0.9.2+ names it ChildFlags_Borders, older
-- builds ChildFlags_Border. Both are functions and must be called.
-- The old code passed the function itself, which on current ReaImGui meant
-- no borders; SM_CHILD_BORDERS stays false so the look doesn't change.
SM_CHILD_BORDERS = false
function sm_child_border_flag()
  if not SM_CHILD_BORDERS then
    return 0
  end
  local getter = r.ImGui_ChildFlags_Borders or r.ImGui_ChildFlags_Border
  if type(getter) == "function" then
    local ok, v = pcall(getter)
    if ok and type(v) == "number" then
      return v
    end
  end
  return 0
end

-- ReaImGui convention (0.9+), used for every window/child in this script:
-- End()/EndChild() only when the matching Begin()/BeginChild() returned true
-- (see also end_window()).
function imgui_end_child(opened)
  if opened then
    -- Trailing SetCursorScreenPos() without an item asserts on EndChild.
    r.ImGui_Dummy(ctx, 0, 0)
    r.ImGui_EndChild(ctx)
  end
end


function imgui_same_line_if_fits(needed_w, gap)
  gap = gap or select(1, r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing()))
  local last_x2 = r.ImGui_GetItemRectMax(ctx)
  if last_x2 + gap + needed_w <= imgui_window_right_x() then
    r.ImGui_SameLine(ctx, 0, gap)
    return true
  end
  return false
end

function calc_tag_chip_width(label)
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
  return text_w + pad_x * 2
end

function calc_compact_chip_width(label)
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
  return text_w + pad_x * 0.65 * 2
end

function measure_tag_group_width(cat_label, entries)
  local spacing = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
  local w = 0
  if cat_label and cat_label ~= "" then
    w = calc_tag_chip_width(cat_label) + spacing + r.ImGui_CalcTextSize(ctx, ":")
  end
  for _, entry in ipairs(entries or {}) do
    w = w + spacing + calc_tag_chip_width(entry.tag)
  end
  return w
end

function tag_group_all_active(entries)
  if not entries or #entries == 0 then
    return false
  end
  for _, entry in ipairs(entries) do
    if not state.active_tags[entry.tag] then
      return false
    end
  end
  return true
end

function toggle_tag_group(entries)
  local all_active = tag_group_all_active(entries)
  for _, entry in ipairs(entries) do
    if all_active then
      state.active_tags[entry.tag] = nil
    else
      state.active_tags[entry.tag] = true
    end
  end
end

function parent_category_fully_active(cat)
  if cat ~= "drum" and cat ~= "melodic" and cat ~= "genre" then
    return false
  end
  local tags = sm_tag_category_lists()[cat]
  if not tags or #tags == 0 then
    return false
  end
  for i = 1, #tags do
    if not state.active_tags[tags[i]] then
      return false
    end
  end
  return true
end

function should_hide_active_tag_in_search_bar(tag)
  local cat = categorize_tags(tag)
  if cat ~= "drum" and cat ~= "melodic" and cat ~= "genre" then
    return false
  end
  return parent_category_fully_active(cat)
end

function tag_group_has_active(entries)
  for _, entry in ipairs(entries or {}) do
    if state.active_tags[entry.tag] then
      return true
    end
  end
  return false
end

function collapse_children_tags_active()
  local mode = state.collapse_children_tags or "off"
  if mode == "on" then
    return true
  end
  if mode ~= "dynamic" then
    return false
  end
  local win_w = state.main_window_rect and state.main_window_rect.w
  if not win_w and r.ImGui_GetWindowSize then
    win_w = select(1, r.ImGui_GetWindowSize(ctx))
  end
  local threshold = state.collapse_children_tags_width or 1100
  return (win_w or 0) <= threshold
end

function set_collapse_children_tags_mode(mode)
  if mode ~= "on" and mode ~= "off" and mode ~= "dynamic" then
    return
  end
  if state.collapse_children_tags ~= mode then
    state.collapse_children_tags = mode
    save_config()
  end
end

function is_tag_parent_selected(key)
  return state.selected_tag_parents and state.selected_tag_parents[key] == true
end

function toggle_tag_parent_selected(key)
  state.selected_tag_parents = state.selected_tag_parents or {}
  if state.selected_tag_parents[key] then
    state.selected_tag_parents[key] = nil
  else
    state.selected_tag_parents[key] = true
  end
end

function tag_group_paint_bg(minx, miny, maxx, maxy)
  if not (maxx > minx and maxy > miny) then
    return
  end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local pad_x, pad_y = 5.0, 3.0
  r.ImGui_DrawList_AddRectFilled(
    dl, minx - pad_x, miny - pad_y, maxx + pad_x, maxy + pad_y,
    0x1C1C1CFF, 10.0)
end

-- Per-row rects so a wrapped group does not cover neighbors on the line above.
-- Fill is painted from last frame before any parent chips, so it stays behind.
function tag_group_paint_cached()
  local cache = state.tag_group_bg
  if not cache then
    return
  end
  for _, rows in pairs(cache) do
    for i = 1, #rows do
      local row = rows[i]
      tag_group_paint_bg(row.minx, row.miny, row.maxx, row.maxy)
    end
  end
end

function tag_group_begin(key)
  return {
    key = key or "",
    rows = {},
    child_count = 0,
  }
end

function tag_group_include_last_item(g)
  if not g then
    return
  end
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  g.rows = g.rows or {}
  local row = g.rows[#g.rows]
  if not row or y0 >= row.maxy - 2 then
    g.rows[#g.rows + 1] = { minx = x0, miny = y0, maxx = x1, maxy = y1 }
  else
    row.minx = math.min(row.minx, x0)
    row.miny = math.min(row.miny, y0)
    row.maxx = math.max(row.maxx, x1)
    row.maxy = math.max(row.maxy, y1)
  end
end

function tag_group_mark_parent(g)
  tag_group_include_last_item(g)
end

function tag_group_draw(g)
  state.tag_group_bg = state.tag_group_bg or {}
  if not g or not g.rows or #g.rows == 0 or (g.child_count or 0) < 1 then
    if g and g.key then
      state.tag_group_bg[g.key] = nil
    end
    return
  end
  state.tag_group_bg[g.key] = g.rows
end

function render_collapsed_parent_chip(label, key, entries, g)
  if not entries or #entries == 0 then
    return
  end
  imgui_same_line_if_fits(calc_tag_chip_width(label), 8)
  -- Highlight when expanded, or when a child filter is on while collapsed.
  local selected = is_tag_parent_selected(key) or tag_group_has_active(entries)
  if draw_category_tag(ctx, label, "collapse_cat_", selected) then
    toggle_tag_parent_selected(key)
  end
  if g then
    tag_group_mark_parent(g)
  end
end

-- In collapsed mode, child tags sit to the right of the parent chips on the
-- first line when they fit, then wrap onto the next line.
function render_collapsed_child_tags(entries, g)
  if not entries or #entries == 0 then
    return
  end

  local spacing = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
  for idx, entry in ipairs(entries) do
    local tag = entry.tag
    imgui_same_line_if_fits(calc_tag_chip_width(tag), idx == 1 and 12 or spacing)
    if draw_tag_button(ctx, tag, state.active_tags[tag], tag) then
      toggle_sample_map_tag_filter(tag)
    end
    if g then
      tag_group_include_last_item(g)
      g.child_count = (g.child_count or 0) + 1
    end
  end
end

function render_wrapping_tag_entries(entries, g)
  local item_spacing_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
  local window_visible_x2 = imgui_window_right_x()

  for idx, entry in ipairs(entries) do
    local tag = entry.tag
    local tag_w = calc_tag_chip_width(tag)
    if idx == 1 then
      r.ImGui_SameLine(ctx)
    else
      local last_button_x2 = r.ImGui_GetItemRectMax(ctx)
      if last_button_x2 + item_spacing_x + tag_w < window_visible_x2 then
        r.ImGui_SameLine(ctx)
      end
    end

    local active = state.active_tags[tag]
    if draw_tag_button(ctx, tag, active, tag) then
      toggle_sample_map_tag_filter(tag)
    end
    if g then
      tag_group_include_last_item(g)
      g.child_count = (g.child_count or 0) + 1
    end
  end
end

function render_tag_category(label, entries, opts)
  opts = opts or {}
  if not entries or #entries == 0 then
    return
  end
  if opts.same_line then
    r.ImGui_SameLine(ctx, 0, opts.gap or 12)
  end
  local g = tag_group_begin(opts.key or label)
  if draw_category_tag(ctx, label, "cat_", tag_group_has_active(entries)) then
    toggle_tag_group(entries)
  end
  tag_group_mark_parent(g)
  r.ImGui_SameLine(ctx)
  if r.ImGui_AlignTextToFramePadding then
    r.ImGui_AlignTextToFramePadding(ctx)
  end
  r.ImGui_Text(ctx, ":")
  render_wrapping_tag_entries(entries, g)
  tag_group_draw(g)
end

function render_parent_with_children(label, key, entries)
  if not entries or #entries == 0 then
    return
  end
  local expanded = is_tag_parent_selected(key)
  local g = tag_group_begin(key)
  render_collapsed_parent_chip(label, key, entries, g)
  if expanded then
    render_collapsed_child_tags(entries, g)
  end
  tag_group_draw(g)
end

function render_tag_filters()
  if not state.tag_list or #state.tag_list == 0 then
    return
  end

  -- Reset hovered tag at start of frame
  state.hovered_tag = nil

  -- Categorize tags
  local drum_tags = {}
  local melodic_tags = {}
  local genre_tags = {}
  local loop_tags = {}
  local extra_groups = {}
  for _, parent in ipairs(state.custom_tag_parents or {}) do
    if parent and parent.id then
      extra_groups[parent.id] = { parent = parent, entries = {} }
    end
  end

  for _, entry in ipairs(state.tag_list) do
    local tag = entry.tag
    local category = categorize_tags(tag)
    if category == "drum" then
      table.insert(drum_tags, entry)
    elseif category == "melodic" then
      table.insert(melodic_tags, entry)
    elseif category == "genre" then
      table.insert(genre_tags, entry)
    elseif category == "loop" then
      table.insert(loop_tags, entry)
    elseif category and extra_groups[category] then
      table.insert(extra_groups[category].entries, entry)
    end
  end

  -- Loop / one-shot sit on the search row when there is room.
  if #loop_tags > 0 then
    for idx, entry in ipairs(loop_tags) do
      local tag_w = calc_tag_chip_width(entry.tag)
      if idx == 1 then
        imgui_same_line_if_fits(tag_w, 8)
      else
        imgui_same_line_if_fits(tag_w, 4)
      end
      local tag = entry.tag
      local active = state.active_tags[tag]
      if draw_tag_button(ctx, tag, active, tag) then
        toggle_sample_map_tag_filter(tag)
      end
    end
  end

  tag_group_paint_cached()

  if collapse_children_tags_active() then
    render_parent_with_children("Drum", "drum", drum_tags)
    render_parent_with_children("Melodic", "melodic", melodic_tags)
    render_parent_with_children("Library", "genre", genre_tags)
    for _, parent in ipairs(state.custom_tag_parents or {}) do
      local group = extra_groups[parent.id]
      if group then
        render_parent_with_children(parent.label, parent.id, group.entries)
      end
    end
  else
    local combine_drum_melodic = false
    if #drum_tags > 0 and #melodic_tags > 0 then
      local cursor_x = r.ImGui_GetCursorScreenPos(ctx)
      local avail_w = imgui_window_right_x() - cursor_x
      local combined_w = measure_tag_group_width("Drum", drum_tags)
        + 12
        + measure_tag_group_width("Melodic", melodic_tags)
      combine_drum_melodic = combined_w <= avail_w
    end

    render_tag_category("Drum", drum_tags)
    render_tag_category("Melodic", melodic_tags, { same_line = combine_drum_melodic, gap = 12 })
    -- Library parent is accordion-only: selecting every pack/genre tag matches
    -- almost the whole library, so the chip never applies a group filter.
    render_parent_with_children("Library", "genre", genre_tags)
    for _, parent in ipairs(state.custom_tag_parents or {}) do
      local group = extra_groups[parent.id]
      if group then
        render_tag_category(parent.label, group.entries)
      end
    end
  end

  -- Check for shortcut when hovering over a tag
  if state.hovered_tag and shortcut_pressed("tag_color") then
    state.tag_color_picker_tag = state.hovered_tag
    r.ImGui_OpenPopup(ctx, "tag_color_picker")
  end

  -- Color picker popup
  if r.ImGui_BeginPopup(ctx, "tag_color_picker") then
    if state.tag_color_picker_tag then
      r.ImGui_Text(ctx, "Edit color")
      r.ImGui_SameLine(ctx)
      r.ImGui_TextColored(ctx, UI_THEME.accent_hvr, state.tag_color_picker_tag)
      local tag_color = state.tag_colors[state.tag_color_picker_tag] or 0x336699
      local color_changed, new_color = draw_ui_color("tag_picker", "Color", tag_color, true)
      if color_changed then
        local rgb_color = new_color & 0xFFFFFF  -- Extract RGB part only
        state.tag_colors[state.tag_color_picker_tag] = rgb_color
        -- Persisted by sm_flush_tag_color_save() when the drag/edit ends.
        state.tag_color_pending_save = { tag = state.tag_color_picker_tag, color = rgb_color }
        invalidate_sample_render_colors(state.tag_color_picker_tag)
      end
      
      r.ImGui_Spacing(ctx)
      if draw_ui_button("tag_picker_done", "Done") then
        r.ImGui_CloseCurrentPopup(ctx)
        state.tag_color_picker_tag = nil
      end
      
      -- Close popup if clicked outside (ImGui handles this automatically, but we can also check for escape)
      if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape then
        local escape_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
        if escape_pressed then
          r.ImGui_CloseCurrentPopup(ctx)
          state.tag_color_picker_tag = nil
        end
      end
    else
      -- Tag was cleared, close popup
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end
  if state.tag_color_pending_save and not (r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0)) then
    sm_flush_tag_color_save()
  end

  r.ImGui_Separator(ctx)
end


function begin_window()
  r.ImGui_SetNextWindowSize(ctx, 1024, 720, r.ImGui_Cond_FirstUseEver())
  if r.ImGui_SetConfigVar and r.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly then
    r.ImGui_SetConfigVar(ctx, r.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly(), 1)
  end
  -- Arrow keys navigate samples; ImGui nav would otherwise steal them and
  -- relocate the sample tooltip to the focused widget.
  if r.ImGui_SetConfigVar and r.ImGui_GetConfigVar and r.ImGui_ConfigVar_Flags then
    local flags = r.ImGui_GetConfigVar(ctx, r.ImGui_ConfigVar_Flags())
    if r.ImGui_ConfigFlags_NavEnableKeyboard then
      flags = flags & ~r.ImGui_ConfigFlags_NavEnableKeyboard()
    end
    if r.ImGui_ConfigFlags_NavEnableSetMousePos then
      flags = flags & ~r.ImGui_ConfigFlags_NavEnableSetMousePos()
    end
    r.ImGui_SetConfigVar(ctx, r.ImGui_ConfigVar_Flags(), flags)
  end
  local flags = r.ImGui_WindowFlags_NoCollapse() |
                r.ImGui_WindowFlags_NoScrollbar() |
                r.ImGui_WindowFlags_NoScrollWithMouse() |
                r.ImGui_WindowFlags_NoNav() |
                r.ImGui_WindowFlags_MenuBar()
  -- ReaImGui docker attach/detach can fail Begin for a frame without
  -- pushing a window. Treat that as "not visible, still open".
  local ok, visible, open = pcall(r.ImGui_Begin, ctx, SCRIPT_NAME, true, flags)
  if not ok then
    return false, true, false
  end
  if open == nil then
    open = true
  end
  return visible and true or false, open, true
end

function end_window(visible, began)
  -- ReaImGui docker attach/detach can return not-visible without pushing a
  -- window. Calling End() in that state asserts and poisons the context.
  if not began or not visible then
    return
  end
  if not (ctx and r.ImGui_ValidatePtr(ctx, "ImGui_Context*")) then
    return
  end
  pcall(r.ImGui_End, ctx)
end

-- Build peaks for a specific item while preserving user selection
function rebuild_peaks_for_item(item)
  if not item then return end

  -- Save current selection
  local selected = {}
  local sel_count = r.CountSelectedMediaItems(0)
  for i = 0, sel_count - 1 do
    selected[#selected + 1] = r.GetSelectedMediaItem(0, i)
  end

  -- Select only the target item
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)

  -- Rebuild peaks for selected items
  r.Main_OnCommand(40047, 0) -- Peaks: Rebuild peaks for selected items

  -- Restore previous selection
  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(selected) do
    if r.ValidatePtr(it, "MediaItem*") then
      r.SetMediaItemSelected(it, true)
    end
  end
end

-- Insert a sample at the current cursor position in the arrange window
function insert_sample_at_cursor(sample)
  if not sample or not sample.path then
    log("No sample to insert")
    return false
  end

  -- Check if file exists
  if not r.file_exists(sample.path) then
    log("Sample file does not exist: " .. sample.path)
    return false
  end

  -- Prevent UI refresh during operations
  r.PreventUIRefresh(1)

  -- Get cursor position
  local cursor_pos = r.GetCursorPosition()
  log("Cursor position: " .. string.format("%.3f", cursor_pos))

  -- Get selected track (or first track if none selected)
  local num_tracks = r.CountTracks(0)
  log("Total tracks in project: " .. num_tracks)

  local track = r.GetSelectedTrack(0, 0)
  if not track then
    log("No selected track, trying first track...")
    if num_tracks > 0 then
      track = r.GetTrack(0, 0)  -- Get first track (0-indexed)
    end
  end

  if not track then
    log("No track available for inserting sample (project has " .. num_tracks .. " tracks)")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Get track info for debugging
  local _, track_name = r.GetTrackName(track)
  log("Using track: " .. (track_name or "unnamed"))

  -- Create media item
  local item = r.AddMediaItemToTrack(track)
  if not item then
    log("Failed to create media item")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Set item position and length
  r.SetMediaItemPosition(item, cursor_pos, false)
  local startoffs = get_sample_start_offset(sample)
  local duration = math.max(0.001, (sample.duration or 1.0) - startoffs)
  r.SetMediaItemLength(item, duration, false)
  log("Set item position to " .. string.format("%.3f", cursor_pos) .. " and length to " .. string.format("%.3f", duration))

  -- Create take and set source
  local take = r.AddTakeToMediaItem(item)
  if take then
    local src = r.PCM_Source_CreateFromFile(sample.path)
    if src then
      local retval = r.SetMediaItemTake_Source(take, src)
      log("SetMediaItemTake_Source result: " .. tostring(retval))

      -- Verify the source was set
      local take_src = r.GetMediaItemTake_Source(take)
      if take_src then
        log("Take source successfully set")
      else
        log("WARNING: Take source not set properly")
      end

      -- Name the item after the filename (with debug)
      set_item_name(item, take, sample.path)
      if startoffs > 0 then
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startoffs)
      end
      local gain = get_sample_gain(sample)
      if gain ~= 1.0 then
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", gain)
      end

      log("Inserted sample '" .. sample.name .. "' at position " .. string.format("%.3f", cursor_pos))

      -- Build peaks for the newly created item
      rebuild_peaks_for_item(item)

      -- Update arrange view and allow UI refresh
      r.UpdateArrange()
      r.PreventUIRefresh(-1)

      return true
    else
      log("Failed to create PCM source for: " .. sample.path)
      r.PreventUIRefresh(-1)
      return false
    end
  else
    log("Failed to create take for media item")
    r.PreventUIRefresh(-1)
    return false
  end
end

-- Get the drop position from mouse cursor context (using SWS extension)
function get_drop_position()
  if not r.BR_GetMouseCursorContext then
    log("SWS functions not available; cannot get mouse position")
    return nil, nil
  end

  -- Refresh mouse context; returns window/segment/details strings
  local window, segment, details = r.BR_GetMouseCursorContext()

  -- Only proceed when mouse is over arrange view (window == "arrange")
  if window == "arrange" then
    local time_pos = r.BR_GetMouseCursorContext_Position()
    local track = r.BR_GetMouseCursorContext_Track()
    if time_pos then
      return time_pos, track
    end
  end

  -- No position available (mouse not over arrange)
  return nil, nil
end

-- Insert sample at specific position and track
function insert_sample_at_position(sample, time_pos, target_track)
  if not sample or not sample.path then
    log("No sample to insert")
    return false
  end
  if sample.is_layering_mix and seq_layering_insert_mix_at_position then
    return seq_layering_insert_mix_at_position(sample, time_pos, target_track)
  end

  -- Check if file exists
  if not r.file_exists(sample.path) then
    log("Sample file does not exist: " .. sample.path)
    return false
  end

  -- Prevent UI refresh during operations
  r.PreventUIRefresh(1)

  -- Use target track if provided, otherwise fallback to selected/first track
  local track = target_track
  if not track then
    track = r.GetSelectedTrack(0, 0)
    if not track then
      local num_tracks = r.CountTracks(0)
      if num_tracks > 0 then
        track = r.GetTrack(0, 0)
      end
    end
  end

  if not track then
    log("No track available for inserting sample")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Get track info for debugging
  local _, track_name = r.GetTrackName(track)
  log("Using track: " .. (track_name or "unnamed"))

  -- Create media item
  local item = r.AddMediaItemToTrack(track)
  if not item then
    log("Failed to create media item")
    r.PreventUIRefresh(-1)
    return false
  end

  -- Set item position and length
  r.SetMediaItemPosition(item, time_pos, false)
  local startoffs = get_sample_start_offset(sample)
  local duration = math.max(0.001, (sample.duration or 1.0) - startoffs)
  r.SetMediaItemLength(item, duration, false)
  log("Set item position to " .. string.format("%.3f", time_pos) .. " and length to " .. string.format("%.3f", duration))

  -- Create take and set source
  local take = r.AddTakeToMediaItem(item)
  if take then
    local src = r.PCM_Source_CreateFromFile(sample.path)
    if src then
      local retval = r.SetMediaItemTake_Source(take, src)
      log("SetMediaItemTake_Source result: " .. tostring(retval))

      -- Verify the source was set
      local take_src = r.GetMediaItemTake_Source(take)
      if take_src then
        log("Take source successfully set")
      else
        log("WARNING: Take source not set properly")
      end

      -- Name the item after the filename (with debug)
      set_item_name(item, take, sample.path)
      if startoffs > 0 then
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startoffs)
      end
      local gain = get_sample_gain(sample)
      if gain ~= 1.0 then
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", gain)
      end

      log("Inserted sample '" .. sample.name .. "' at position " .. string.format("%.3f", time_pos))

      -- Build peaks for the newly created item
      rebuild_peaks_for_item(item)

      -- Update arrange view and allow UI refresh
      r.UpdateArrange()
      r.PreventUIRefresh(-1)

      return true
    else
      log("Failed to create PCM source for: " .. sample.path)
      r.PreventUIRefresh(-1)
      return false
    end
  else
    log("Failed to create take for media item")
    r.PreventUIRefresh(-1)
    return false
  end
end

-- Wrap a single committed insert in one undo point (prefer the project-scoped API).
-- NOTE: declared as globals (not locals) to avoid exceeding Lua's 200 local-per-chunk limit.
function arrange_undo_begin()
  if r.Undo_BeginBlock2 then
    r.Undo_BeginBlock2(0)
  elseif r.Undo_BeginBlock then
    r.Undo_BeginBlock()
  end
end

function arrange_undo_end(label)
  label = label or "Insert sample"
  if r.Undo_EndBlock2 then
    r.Undo_EndBlock2(0, label, -1)
  elseif r.Undo_EndBlock then
    r.Undo_EndBlock(label, -1)
  end
end

-- Snap to grid only when REAPER snapping is enabled, mirroring native drag behavior.
function maybe_snap_drop_time(t)
  if not t then
    return t
  end
  if r.GetToggleCommandState and r.SnapToGrid and r.GetToggleCommandState(1157) == 1 then
    local snapped = r.SnapToGrid(0, t)
    if snapped and snapped == snapped then
      return snapped
    end
  end
  return t
end

-- Remove the live "provisional" preview item without touching the undo history.
function remove_provisional_drop()
  local p = state.provisional_drop
  state.provisional_drop = nil
  if not p or not p.item then
    return
  end
  if not r.ValidatePtr(p.item, "MediaItem*") then
    return
  end
  local track = p.track
  if not (track and r.ValidatePtr(track, "MediaTrack*")) then
    track = r.GetMediaItemTrack(p.item)
  end
  if not track then
    return
  end
  r.PreventUIRefresh(1)
  r.DeleteTrackMediaItem(track, p.item)
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
end

-- Create/move a real media item under the cursor while dragging over the arrange,
-- so the user gets REAPER's own drop preview. Created outside any undo block; the
-- final commit (or cancel) is what manages the undo history.
function update_provisional_drop(sample)
  if not sample or not sample.path then
    remove_provisional_drop()
    return
  end
  -- Layered mix is several overlapping items; skip the single-file preview.
  if sample.is_layering_mix then
    remove_provisional_drop()
    if state.seq_drop_target_idx or state.seq_timeline_drop_track_idx or state.seq_candidate_drop
        or state.seq_drum_drop then
      return
    end
    local drop_time, drop_track = get_drop_position()
    if drop_time then
      state.last_mouse_time_pos = maybe_snap_drop_time(drop_time)
      state.last_mouse_track = drop_track
    end
    return
  end

  -- In-window drop targets (sequencer track row / candidate / timeline / layering) are not arrange inserts.
  if state.seq_drop_target_idx or state.seq_timeline_drop_track_idx or state.seq_candidate_drop
      or state.seq_drum_drop
      or state.seq_layering_drop_vert
      or (seq_layering_pointer_over_window and seq_layering_pointer_over_window()) then
    remove_provisional_drop()
    return
  end

  local drop_time, drop_track = get_drop_position()
  if not drop_time or not drop_track then
    -- Cursor is not over an arrange track; hide the preview but keep dragging.
    remove_provisional_drop()
    return
  end

  drop_time = maybe_snap_drop_time(drop_time)
  state.last_mouse_time_pos = drop_time
  state.last_mouse_track = drop_track

  local p = state.provisional_drop
  local valid = p and p.item and r.ValidatePtr(p.item, "MediaItem*") and p.sample_path == sample.path
  if not valid then
    remove_provisional_drop()
    if not r.file_exists(sample.path) then
      return
    end
    r.PreventUIRefresh(1)
    local item = r.AddMediaItemToTrack(drop_track)
    if item then
      local take = r.AddTakeToMediaItem(item)
      local src = take and r.PCM_Source_CreateFromFile(sample.path)
      if src then
        r.SetMediaItemTake_Source(take, src)
        set_item_name(item, take, sample.path)
      end
      r.SetMediaItemLength(item, sample.duration or 1.0, false)
      r.SetMediaItemPosition(item, drop_time, false)
      -- Tint the preview so it reads as provisional, not a committed item.
      if r.ColorToNative then
        r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", r.ColorToNative(120, 170, 255) | 0x1000000)
      end
      r.SetMediaItemInfo_Value(item, "B_UISEL", 0)
      -- Peaks build lazily for the visible preview; the committed item rebuilds them.
      state.provisional_drop = { item = item, track = drop_track, time = drop_time, sample_path = sample.path }
    end
    r.UpdateArrange()
    r.PreventUIRefresh(-1)
    return
  end

  -- Reposition the existing preview (cheap: no source/peak rebuild).
  r.PreventUIRefresh(1)
  if drop_track ~= p.track and r.ValidatePtr(drop_track, "MediaTrack*") then
    r.MoveMediaItemToTrack(p.item, drop_track)
    p.track = drop_track
  end
  r.SetMediaItemPosition(p.item, drop_time, false)
  p.time = drop_time
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
end

-- Hide REAPER's floating drag tooltip window if it is currently shown.
function clear_drag_tooltip()
  if state.drag_tooltip_active and r.TrackCtl_SetToolTip then
    r.TrackCtl_SetToolTip("", 0, 0, true)
  end
  state.drag_tooltip_active = false
end

function is_alt_down()
  if r.JS_Mouse_GetState then
    local cap = r.JS_Mouse_GetState(0)
    if cap & 16 == 16 then
      return true
    end
  end
  if r.ImGui_GetIO then
    local io = r.ImGui_GetIO(ctx)
    if io and io.KeyAlt then
      return io.KeyAlt
    end
  end
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftAlt and r.ImGui_Key_RightAlt then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt())
  end
  return false
end

function is_cmd_down()
  if not r.ImGui_IsKeyDown then
    return false
  end
  if r.ImGui_Key_LeftSuper and r.ImGui_Key_RightSuper then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftSuper()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightSuper())
  end
  return false
end

function is_shift_down()
  if not r.ImGui_IsKeyDown then
    return false
  end
  if r.ImGui_Key_LeftShift and r.ImGui_Key_RightShift then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
  end
  return false
end

function is_ctrl_down()
  if r.JS_Mouse_GetState then
    local cap = r.JS_Mouse_GetState(0)
    if cap & 4 == 4 then
      return true
    end
  end
  if r.ImGui_GetIO then
    local io = r.ImGui_GetIO(ctx)
    if io and io.KeyCtrl then
      return io.KeyCtrl
    end
  end
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftCtrl and r.ImGui_Key_RightCtrl then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl())
  end
  return false
end

function is_r_down()
  if not r.ImGui_IsKeyDown or not r.ImGui_Key_R then
    return false
  end
  return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_R())
end

-- Customizable mouse-modifier support for sequencer gestures.
-- These are declared as globals (not locals) to avoid the per-chunk local limit,
-- matching the existing pattern used by is_ctrl_down().
MOUSE_MOD_DEFAULTS = {
  lane_zoom = "shift",
  time_zoom = "cmd",
  velocity_ramp = "shift",
  unify = "alt",
}

-- Ordered list used by the settings editor (id, label, hint).
MOUSE_MOD_ACTIONS = {
  { id = "time_zoom",     label = "Timeline zoom",   hint = "Wheel over the sequencer zooms the timeline horizontally. Shift+horizontal scroll also zooms." },
  { id = "lane_zoom",     label = "Lane height zoom", hint = "Wheel over the sequencer zooms note/parameter lane height. Changing zoom resets all tracks to the same height." },
  { id = "velocity_ramp", label = "Value ramp",      hint = "Drag in a parameter lane ramps values across cells." },
  { id = "unify",         label = "Unify values",    hint = "Drag in a parameter lane sets every cell to the same value." },
}

MOUSE_MOD_CHOICES = { "none", "shift", "alt", "ctrl", "cmd" }

function modifier_is_down(mod)
  if mod == "shift" then return is_shift_down() end
  if mod == "alt" then return is_alt_down() end
  if mod == "ctrl" then return is_ctrl_down() end
  if mod == "cmd" then return is_cmd_down() end
  if mod == "none" then return true end
  return false
end

-- Returns true if the modifier currently configured for `action` is held.
function mod_active(action)
  local mods = state.mouse_mods or MOUSE_MOD_DEFAULTS
  local mod = mods[action] or MOUSE_MOD_DEFAULTS[action] or "none"
  return modifier_is_down(mod)
end

function mouse_mod_label(mod)
  if mod == "shift" then return "Shift" end
  if mod == "alt" then return "Alt/Option" end
  if mod == "ctrl" then return "Ctrl" end
  if mod == "cmd" then return "Cmd/Win" end
  return "None"
end

-- Customizable keyboard shortcuts. Globals to stay under the main-chunk local limit.
KEYBOARD_SHORTCUT_DEFAULTS = {
  play_stop = { key = "Space" },
  undo = { key = "Z", cmdctrl = true },
  redo = { key = "Z", cmdctrl = true, shift = true },
  cancel = { key = "Escape" },
  tag_color = { key = "C" },
  map_prev_sample = { key = "LeftArrow" },
  map_next_sample = { key = "RightArrow" },
  history_back = { key = "UpArrow" },
  history_forward = { key = "DownArrow" },
  preview_hover = { key = "Z" },
  solo_play = { key = "2" },
  unsolo_play = { key = "3" },
  split_snap = { key = "4" },
  split_free = { key = "5" },
  delete_razor = { key = "Delete" },
  delete_razor_alt = { key = "Backspace" },
  edit_gain = { key = "G" },
  edit_vary = { key = "V" },
  pick_note_sample = { key = "V", shift = true },
  edit_stutter = { key = "S" },
  edit_pan = { key = "P" },
  edit_pitch = { key = "T" },
  edit_decay = { key = "D" },
  edit_stretch = { key = "R" },
  edit_start = { key = "A" },
  edit_lock = { key = "L" },
  edit_vary_filter = { key = "F" },
  enlarge_track = { key = "A", shift = true },
}

KEYBOARD_SHORTCUT_ACTIONS = {
  { id = "play_stop", group = "General", label = "Play / stop transport", hint = "Toggles REAPER playback." },
  { id = "undo", group = "General", label = "Undo", hint = "Undo the last sequencer edit." },
  { id = "redo", group = "General", label = "Redo", hint = "Redo the last undone sequencer edit." },
  { id = "cancel", group = "General", label = "Cancel / clear", hint = "Exit note-edit mode and clear razor selections." },
  { id = "tag_color", group = "Sample Map", label = "Edit hovered tag color", hint = "Opens the color picker while a tag chip is hovered." },
  { id = "map_prev_sample", group = "Sample Map", label = "Previous neighboring sample", hint = "Select the previous nearby sample on the map, or swap the selected sequencer track sample." },
  { id = "map_next_sample", group = "Sample Map", label = "Next neighboring sample", hint = "Select the next nearby sample on the map, or swap the selected sequencer track sample." },
  { id = "history_back", group = "Sample Map", label = "Preview history back", hint = "Go to an older previewed sample." },
  { id = "history_forward", group = "Sample Map", label = "Preview history forward", hint = "Go to a newer previewed sample." },
  { id = "preview_hover", group = "Sequencer", label = "Preview hovered grid", hint = "Play the sample at the hovered sequencer cell. Double-tap to stop." },
  { id = "solo_play", group = "Sequencer", label = "Solo track and play", hint = "Solo the hovered track and start playback from the hovered grid." },
  { id = "unsolo_play", group = "Sequencer", label = "Unsolo and play", hint = "Clear all track solos and start playback from the hovered grid." },
  { id = "split_snap", group = "Sequencer", label = "Split note (snap)", hint = "Split the hovered note at the grid." },
  { id = "split_free", group = "Sequencer", label = "Split note (free)", hint = "Split the hovered note at the mouse, without snapping." },
  { id = "delete_razor", group = "Sequencer", label = "Delete razor notes", hint = "Delete notes inside the current razor selection." },
  { id = "delete_razor_alt", group = "Sequencer", label = "Delete razor notes (alt)", hint = "Alternate key for deleting notes inside razors." },
  { id = "edit_gain", group = "Sequencer", label = "Gain edit mode", hint = "Toggle per-note gain editing." },
  { id = "edit_vary", group = "Sequencer", label = "Variation edit mode", hint = "Toggle per-note sample-variation editing." },
  { id = "pick_note_sample", group = "Sequencer", label = "Pick note sample", hint = "Open the mini sample map and swap the hovered note, or all notes in a razor, with the sample you click." },
  { id = "edit_stutter", group = "Sequencer", label = "Stutter edit mode", hint = "Toggle per-note stutter editing." },
  { id = "edit_pan", group = "Sequencer", label = "Pan edit mode", hint = "Toggle per-note pan editing." },
  { id = "edit_pitch", group = "Sequencer", label = "Pitch edit mode", hint = "Toggle per-note pitch editing." },
  { id = "edit_decay", group = "Sequencer", label = "Decay edit mode", hint = "Toggle per-note decay / length editing." },
  { id = "edit_stretch", group = "Sequencer", label = "Stretch edit mode", hint = "Toggle per-note stretch editing." },
  { id = "edit_start", group = "Sequencer", label = "Start edit mode", hint = "Toggle per-note start-offset editing." },
  { id = "edit_lock", group = "Sequencer", label = "Lock edit mode", hint = "Toggle note/grid lock editing." },
  { id = "edit_vary_filter", group = "Sequencer", label = "Vary filter edit mode", hint = "Paint grid areas that restrict sample variation to matching filenames and tags." },
  { id = "enlarge_track", group = "Sequencer", label = "Enlarge hovered track", hint = "Toggle a larger height for the hovered sequencer track. Drag track borders to set custom heights. Vertical zoom resets all tracks to the same height." },
}

SHORTCUT_KEY_LABELS = {
  LeftArrow = "Left",
  RightArrow = "Right",
  UpArrow = "Up",
  DownArrow = "Down",
  PageUp = "Page Up",
  PageDown = "Page Down",
  Backspace = "Backspace",
  Delete = "Delete",
  Space = "Space",
  Escape = "Esc",
  Enter = "Enter",
  Tab = "Tab",
  Insert = "Insert",
  Home = "Home",
  End = "End",
  Minus = "-",
  Equal = "=",
  LeftBracket = "[",
  RightBracket = "]",
  Backslash = "\\",
  Semicolon = ";",
  Apostrophe = "'",
  Comma = ",",
  Period = ".",
  Slash = "/",
  GraveAccent = "`",
  KeypadDecimal = "Num .",
  KeypadDivide = "Num /",
  KeypadMultiply = "Num *",
  KeypadSubtract = "Num -",
  KeypadAdd = "Num +",
  KeypadEnter = "Num Enter",
  KeypadEqual = "Num =",
}

SHORTCUT_CAPTURE_KEY_IDS = nil

function shortcut_capture_key_ids()
  if SHORTCUT_CAPTURE_KEY_IDS then
    return SHORTCUT_CAPTURE_KEY_IDS
  end
  local keys = {
    "Tab", "LeftArrow", "RightArrow", "UpArrow", "DownArrow",
    "PageUp", "PageDown", "Home", "End", "Insert", "Delete",
    "Backspace", "Space", "Enter", "Escape",
    "Minus", "Equal", "LeftBracket", "RightBracket", "Backslash",
    "Semicolon", "Apostrophe", "Comma", "Period", "Slash", "GraveAccent",
    "KeypadDecimal", "KeypadDivide", "KeypadMultiply", "KeypadSubtract",
    "KeypadAdd", "KeypadEnter", "KeypadEqual",
  }
  local i
  for i = 0, 9 do
    keys[#keys + 1] = tostring(i)
  end
  for i = 0, 9 do
    keys[#keys + 1] = "Keypad" .. tostring(i)
  end
  for i = 1, 12 do
    keys[#keys + 1] = "F" .. tostring(i)
  end
  for i = 65, 90 do
    keys[#keys + 1] = string.char(i)
  end
  SHORTCUT_CAPTURE_KEY_IDS = keys
  return keys
end

function shortcut_key_label(key)
  if not key or key == "" then
    return "None"
  end
  if SHORTCUT_KEY_LABELS[key] then
    return SHORTCUT_KEY_LABELS[key]
  end
  local kp = string.match(key, "^Keypad(%d)$")
  if kp then
    return "Num " .. kp
  end
  return key
end

function clone_shortcut_spec(spec)
  if type(spec) ~= "table" then
    return nil
  end
  return {
    key = spec.key,
    shift = spec.shift and true or nil,
    alt = spec.alt and true or nil,
    ctrl = spec.ctrl and true or nil,
    cmd = spec.cmd and true or nil,
    cmdctrl = spec.cmdctrl and true or nil,
  }
end

function get_shortcut(action)
  local custom = state.keyboard_shortcuts and state.keyboard_shortcuts[action]
  if type(custom) == "table" then
    if type(custom.key) ~= "string" or custom.key == "" then
      return nil
    end
    return custom
  end
  return KEYBOARD_SHORTCUT_DEFAULTS[action]
end

function shortcut_would_fire(spec, shift, alt, ctrl, cmd)
  if not spec or not spec.key or spec.key == "" then
    return false
  end
  if (spec.shift and true or false) ~= (shift and true or false) then
    return false
  end
  if (spec.alt and true or false) ~= (alt and true or false) then
    return false
  end
  if spec.cmdctrl then
    return (ctrl and true or false) or (cmd and true or false)
  end
  if (spec.ctrl and true or false) ~= (ctrl and true or false) then
    return false
  end
  if (spec.cmd and true or false) ~= (cmd and true or false) then
    return false
  end
  return true
end

function shortcuts_conflict(a, b)
  if not a or not b or a.key == "" or b.key == "" or a.key ~= b.key then
    return false
  end
  local si, ai, ci, mi
  for si = 0, 1 do
    for ai = 0, 1 do
      for ci = 0, 1 do
        for mi = 0, 1 do
          if shortcut_would_fire(a, si == 1, ai == 1, ci == 1, mi == 1)
              and shortcut_would_fire(b, si == 1, ai == 1, ci == 1, mi == 1) then
            return true
          end
        end
      end
    end
  end
  return false
end

function shortcut_display(action_or_spec)
  local spec = action_or_spec
  if type(action_or_spec) == "string" then
    spec = get_shortcut(action_or_spec)
  end
  if not spec or not spec.key or spec.key == "" then
    return "None"
  end
  local parts = {}
  if spec.cmdctrl then
    parts[#parts + 1] = "Ctrl/Cmd"
  else
    if spec.ctrl then
      parts[#parts + 1] = "Ctrl"
    end
    if spec.cmd then
      parts[#parts + 1] = "Cmd"
    end
  end
  if spec.alt then
    parts[#parts + 1] = "Alt"
  end
  if spec.shift then
    parts[#parts + 1] = "Shift"
  end
  parts[#parts + 1] = shortcut_key_label(spec.key)
  return table.concat(parts, "+")
end

function shortcut_conflict_label(action)
  local spec = get_shortcut(action)
  if not spec then
    return nil
  end
  local i
  for i = 1, #KEYBOARD_SHORTCUT_ACTIONS do
    local other = KEYBOARD_SHORTCUT_ACTIONS[i]
    if other.id ~= action and shortcuts_conflict(spec, get_shortcut(other.id)) then
      return other.label
    end
  end
  return nil
end

function shortcut_key_pressed(key_id)
  if not key_id or key_id == "" or not r.ImGui_IsKeyPressed then
    return false
  end
  local fn = r["ImGui_Key_" .. key_id]
  if not fn then
    return false
  end
  return r.ImGui_IsKeyPressed(ctx, fn(), false)
end

function shortcut_pressed(action)
  if state.shortcut_capture_id then
    return false
  end
  if imgui_text_input_active and imgui_text_input_active() then
    return false
  end
  local spec = get_shortcut(action)
  if not spec then
    return false
  end
  if not shortcut_would_fire(spec, is_shift_down(), is_alt_down(), is_ctrl_down(), is_cmd_down()) then
    return false
  end
  return shortcut_key_pressed(spec.key)
end

function shortcut_poll_pressed_key()
  if not r.ImGui_IsKeyPressed then
    return nil
  end
  local keys = shortcut_capture_key_ids()
  local i
  for i = 1, #keys do
    if shortcut_key_pressed(keys[i]) then
      return keys[i]
    end
  end
  return nil
end

function shortcut_spec_from_press(key)
  local spec = { key = key }
  if is_shift_down() then
    spec.shift = true
  end
  if is_alt_down() then
    spec.alt = true
  end
  if is_ctrl_down() then
    spec.ctrl = true
  end
  if is_cmd_down() then
    spec.cmd = true
  end
  return spec
end

function shortcut_assign(action, spec)
  state.keyboard_shortcuts = state.keyboard_shortcuts or {}
  spec = clone_shortcut_spec(spec) or { key = "" }
  local i
  for i = 1, #KEYBOARD_SHORTCUT_ACTIONS do
    local other = KEYBOARD_SHORTCUT_ACTIONS[i]
    if other.id ~= action and shortcuts_conflict(spec, get_shortcut(other.id)) then
      state.keyboard_shortcuts[other.id] = { key = "" }
    end
  end
  state.keyboard_shortcuts[action] = spec
  save_config()
end

function shortcut_reset_one(action)
  state.keyboard_shortcuts = state.keyboard_shortcuts or {}
  state.keyboard_shortcuts[action] = nil
  save_config()
end

function shortcut_reset_all()
  state.keyboard_shortcuts = {}
  state.shortcut_capture_id = nil
  save_config()
end

function update_pending_drop_tracking()
  if not state.pending_waveform_drop then
    return
  end
  local time_pos, track = get_drop_position()
  if time_pos then
    state.last_mouse_time_pos = time_pos
    state.last_mouse_track = track
  end
end

function clamp_effective_duration(sample, seconds)
  local file_dur = (sample and type(sample.duration) == "number" and sample.duration > 0) and sample.duration or nil
  seconds = tonumber(seconds) or 0
  if file_dur then
    return math.max(0.001, math.min(file_dur, seconds))
  end
  return math.max(0.001, seconds)
end

function render_waveform_overlay_tags(x0, y0, width, height, layout_x, layout_y)
  local consumed = false
  local path = preview_sample_obj and preview_sample_obj.path
  local tags = (preview_sample_obj and type(preview_sample_obj.tags) == "table") and preview_sample_obj.tags or {}
  local pad = 4
  local gap = 3
  local plus_w, plus_h = 22, 22

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 3, 2)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 3, 1)
  local pad_x, pad_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
  pad_x = pad_x or 3
  pad_y = pad_y or 1

  local chips = {}
  for _, tag in ipairs(tags) do
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, tag)
    chips[#chips + 1] = {
      kind = "tag",
      tag = tag,
      w = (text_w or 0) + pad_x * 2,
      h = (text_h or 14) + pad_y * 2,
    }
  end
  if path and path ~= "" then
    chips[#chips + 1] = { kind = "plus", w = plus_w, h = plus_h }
  end

  local max_w = math.max(plus_w, (width or 0) - pad * 2)
  local rows = {}
  local cur = { items = {}, w = 0, h = 0 }
  local function flush_row()
    if #cur.items > 0 then
      rows[#rows + 1] = cur
      cur = { items = {}, w = 0, h = 0 }
    end
  end
  for _, chip in ipairs(chips) do
    local need = chip.w + ((#cur.items > 0) and gap or 0)
    if #cur.items > 0 and cur.w + need > max_w then
      flush_row()
    end
    cur.items[#cur.items + 1] = chip
    cur.w = cur.w + need
    cur.h = math.max(cur.h, chip.h)
  end
  flush_row()

  local total_h = 0
  for i, row in ipairs(rows) do
    if i > 1 then
      total_h = total_h + 2
    end
    total_h = total_h + row.h
  end
  local y = math.max(y0 + pad, y0 + (height or 0) - pad - total_h)
  for _, row in ipairs(rows) do
    local x = x0 + (width or 0) - pad - row.w
    for _, chip in ipairs(row.items) do
      r.ImGui_SetCursorScreenPos(ctx, x, y + math.max(0, (row.h - chip.h) * 0.5))
      if chip.kind == "tag" then
        local active = state.active_tags[chip.tag] or false
        if draw_tag_button(ctx, chip.tag, active, chip.tag, "waveform_") then
          if active then
            state.active_tags[chip.tag] = nil
          else
            toggle_sample_map_tag_filter(chip.tag)
          end
        end
      else
        if draw_ui_button("wave_add_tag", "+", plus_w, plus_h, { compact = true, pill = true }) then
          tag_add_open_for(path)
          r.ImGui_OpenPopup(ctx, "##tag_add_popup")
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, "Add a tag")
        end
      end
      if r.ImGui_IsItemHovered(ctx) then
        consumed = true
      end
      x = x + chip.w + gap
    end
    y = y + row.h + 2
  end

  r.ImGui_PopStyleVar(ctx, 2)
  render_tag_add_popup()
  r.ImGui_SetCursorPos(ctx, layout_x, layout_y)
  r.ImGui_Dummy(ctx, 0, 0)
  return consumed
end

function path_explorer_button_width()
  local tw = select(1, r.ImGui_CalcTextSize(ctx, "Explorer"))
  return tw + 18
end

function render_path_explorer_button(x, y)
  local label = "Explorer"
  local btn_w = path_explorer_button_width()
  local btn_h = 22
  if x and y then
    r.ImGui_SetCursorScreenPos(ctx, x, y)
  end
  if draw_ui_button("path_open_explorer", label, btn_w, btn_h, {
    style = state.explorer_open and "primary" or "default",
    compact = true,
    selected = state.explorer_open,
  }) then
    state.explorer_open = not state.explorer_open
    save_config()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Browse scan folders and set custom tags.\nDock the window on the right of the sample map, or leave it floating.")
  end
end

function render_sample_path_line()
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww, wh = r.ImGui_GetWindowSize(ctx)
  local pad = 4
  local ox, oy = wx + pad, wy + pad
  local avail_w = math.max(1, (ww or 1) - pad * 2)
  local avail_h = math.max(1, (wh or 1) - pad * 2)
  local explorer_w = path_explorer_button_width()
  local explorer_gap = 8
  local inner_w = math.max(40, avail_w - explorer_w - explorer_gap)
  local wrap = avail_h >= 46

  render_path_explorer_button(ox + avail_w - explorer_w, oy)

  local crumb_flags = 0
  local extra_pop = 0
  if not wrap then
    crumb_flags = r.ImGui_WindowFlags_HorizontalScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    if r.ImGui_StyleVar_ScrollbarSize then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0.01)
      extra_pop = 1
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, ox, oy)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 2)
  local crumbs_open = r.ImGui_BeginChild(ctx, "path_crumbs", inner_w, wrap and avail_h or math.max(avail_h, 22), 0, crumb_flags)
  if crumbs_open then
    local function path_advance(needed_w, first)
      if first then
        return
      end
      if wrap then
        imgui_same_line_if_fits(needed_w, 2)
      else
        r.ImGui_SameLine(ctx, 0, 2)
      end
    end

    if not preview_sample_obj then
      r.ImGui_Text(ctx, "(No sample selected)")
    else
      local full_path = preview_sample_obj.path or ""
      local path_segments = {}
      local filename = preview_sample_obj.name or "Unknown"
      if full_path ~= "" then
        local normalized_path = normalize_path(full_path)
        local scanned_root = nil
        for _, scanned_folder in ipairs(state.folders) do
          local norm_scanned = normalize_path(scanned_folder)
          if normalized_path:sub(1, #norm_scanned) == norm_scanned then
            if not scanned_root or #norm_scanned > #scanned_root then
              scanned_root = norm_scanned
            end
          end
        end
        local dir_path = normalized_path:match("(.+)/[^/]+$") or ""
        if scanned_root and dir_path ~= "" then
          local root_name = scanned_root:match("([^/]+)/?$") or scanned_root
          table.insert(path_segments, { name = root_name, path = scanned_root })
          local relative_path = dir_path
          if dir_path:sub(1, #scanned_root) == scanned_root then
            relative_path = dir_path:sub(#scanned_root + 1)
            if relative_path:sub(1, 1) == "/" then
              relative_path = relative_path:sub(2)
            end
          end
          if relative_path ~= "" then
            local current_path = scanned_root
            for segment in relative_path:gmatch("([^/]+)") do
              current_path = current_path .. "/" .. segment
              table.insert(path_segments, { name = segment, path = current_path })
            end
          end
        elseif dir_path ~= "" then
          local is_absolute = dir_path:sub(1, 1) == "/"
          local current_path = is_absolute and "/" or ""
          for segment in dir_path:gmatch("([^/]+)") do
            if is_absolute then
              current_path = current_path .. segment
            else
              current_path = current_path .. (current_path == "" and "" or "/") .. segment
            end
            table.insert(path_segments, { name = segment, path = current_path })
            if is_absolute then
              current_path = current_path .. "/"
            end
          end
        end
      end

      for i, seg in ipairs(path_segments) do
        local text_size = { r.ImGui_CalcTextSize(ctx, seg.name) }
        local frame_padding = 6.0
        local button_width = text_size[1] + frame_padding * 2
        local button_height = text_size[2] + 6.0
        local chevron_w = 10
        if i > 1 then
          path_advance(chevron_w + 2 + button_width, false)
          local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
          local sep_h = 18
          r.ImGui_Dummy(ctx, chevron_w, sep_h)
          ui_button_draw_icon(r.ImGui_GetWindowDrawList(ctx), "chev_right", cx + 5, cy + sep_h * 0.5, 12, UI_THEME.text_mute)
          path_advance(button_width, false)
        end

        local is_filtered = folder_filter_has(seg.path)
        local clicked = r.ImGui_InvisibleButton(ctx, "##path_btn_" .. i .. "_" .. seg.name, button_width, button_height)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local pressed = r.ImGui_IsItemActive(ctx)
        local x0, y0 = r.ImGui_GetItemRectMin(ctx)
        local x1, y1 = r.ImGui_GetItemRectMax(ctx)
        local bg, border, text_col
        if is_filtered then
          bg = hovered and UI_THEME.accent_fill_h or UI_THEME.accent_fill
          border = UI_THEME.accent
          text_col = 0xFFFFFFFF
        elseif hovered then
          bg = UI_THEME.surface_hvr
          border = UI_THEME.border_hvr
          text_col = UI_THEME.text
        else
          bg = UI_THEME.surface
          border = UI_THEME.border
          text_col = UI_THEME.text_dim
        end
        local dl = r.ImGui_GetWindowDrawList(ctx)
        ui_draw_panel(dl, x0, y0, x1, y1, button_height * 0.5, bg, border, hovered, pressed)
        local text_x = x0 + frame_padding
        local text_y = y0 + (button_height - text_size[2]) * 0.5 + (pressed and 1.0 or 0.0)
        r.ImGui_DrawList_AddText(dl, text_x, text_y, text_col, seg.name)
        if clicked then
          folder_filter_toggle(seg.path)
        end
      end

      local slash = " / "
      local name_w = (select(1, r.ImGui_CalcTextSize(ctx, slash)) or 8)
        + (select(1, r.ImGui_CalcTextSize(ctx, filename)) or 40)
      path_advance(name_w, #path_segments == 0)
      if #path_segments > 0 then
        r.ImGui_Text(ctx, slash)
        path_advance(select(1, r.ImGui_CalcTextSize(ctx, filename)) or 40, false)
      end
      r.ImGui_TextColored(ctx, 0xFFCCCCCC, filename)
    end

    if not wrap and r.ImGui_SetScrollX and r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx) then
      local wheel, wheel_h = 0, 0
      if r.ImGui_GetMouseWheel then
        wheel, wheel_h = r.ImGui_GetMouseWheel(ctx)
      end
      local dx = (wheel_h or 0) - (wheel or 0)
      if dx ~= 0 then
        r.ImGui_SetScrollX(ctx, (r.ImGui_GetScrollX(ctx) or 0) - dx * 48)
      end
    end
    r.ImGui_Dummy(ctx, 0, 0)
  end
  imgui_end_child(crumbs_open)
  r.ImGui_PopStyleVar(ctx, 2 + extra_pop)
  r.ImGui_Dummy(ctx, 0, 0)
end

function map_waveform_handle_preview_click(sample, hovered, clicked, left_down, mx, x0, width, view0, view1, blocked)
  if blocked or not sample or not sample.path then
    if blocked then
      state.map_wave_press = nil
      state.map_wave_press_t = nil
    end
    return
  end
  local dbl = hovered and clicked and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local playing_now = preview_proc ~= nil and preview_sample_obj ~= nil
      and preview_sample_obj.path == sample.path
  if hovered and clicked and not dbl then
    if playing_now then
      stop_preview()
      state.preview_paused = false
      state.map_wave_press = nil
      state.map_wave_press_t = nil
    else
      state.map_wave_press = sample
      state.map_wave_press_t = wave_x_to_time(mx, x0, width, view0, view1)
    end
  end
  if state.waveform_eff_drag or state.wave_view_pan or state.pending_waveform_drop then
    state.map_wave_press = nil
    state.map_wave_press_t = nil
  end
  if state.map_wave_press and not left_down then
    local press_sample = state.map_wave_press
    local press_t = state.map_wave_press_t
    state.map_wave_press = nil
    state.map_wave_press_t = nil
    if press_sample and press_sample.path then
      preview_sample(press_sample, press_t)
    end
  end
end

function render_waveform()
  local wh = select(2, r.ImGui_GetWindowSize(ctx))
  local height = math.max(48, (wh or 80) - 8)
  if preview_sample_obj then
    if not waveform_data or waveform_data.sample_path ~= preview_sample_obj.path then
      ensure_waveform_for_sample(preview_sample_obj)
    end
  end

  local width = r.ImGui_GetContentRegionAvail(ctx)
  local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
  local x0, y0 = pos_x, pos_y

  r.ImGui_InvisibleButton(ctx, "waveform_area", width, height)
  local layout_x, layout_y = r.ImGui_GetCursorPos(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  if state.pending_waveform_drop then
    if hovered then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
    update_pending_drop_tracking()
  end

  ui_draw_panel(dl, x0, y0, x0 + width, y0 + height, 6.0, UI_THEME.bg_panel, UI_THEME.border, false, false)

  if not preview_sample_obj or not waveform_data then
    local msg = preview_sample_obj and "Loading waveform…" or "No sample selected"
    local tw = select(1, r.ImGui_CalcTextSize(ctx, msg)) or 0
    r.ImGui_DrawList_AddText(dl, x0 + (width - tw) * 0.5, y0 + height * 0.5 - 7, UI_THEME.text_mute, msg)
    render_waveform_overlay_tags(x0, y0, width, height, layout_x, layout_y)
    return
  end

  local waveform = waveform_data.data
  local file_dur = (waveform_data.duration or (preview_sample_obj and preview_sample_obj.duration) or 0.0)
  local view0, view1 = wave_view_ensure(preview_sample_obj, file_dur)
  local view_span = math.max(0.001, view1 - view0)
  local function map_x(t)
    return x0 + (((t or 0) - view0) / view_span) * width
  end
  if not waveform or #waveform == 0 then
    -- Show message if no waveform data
    r.ImGui_DrawList_AddText(dl, x0 + width * 0.5 - 50, y0 + height * 0.5, 0xFFFFFFFF, "No waveform data")
    local mx, my = r.ImGui_GetMousePos(ctx)
    local ctl = draw_sample_wave_controls(
      dl, preview_sample_obj, x0, y0, width, height, file_dur, view0, view1,
      mx, my, r.ImGui_IsMouseDown(ctx, 0), clicked, "map", { show_name = false }
    )
    local tags_hit = render_waveform_overlay_tags(x0, y0, width, height, layout_x, layout_y)
    local blocked = tags_hit or (ctl and ctl.consumed) or state.wave_view_pan or state.pending_waveform_drop
    if preview_sample_obj and preview_sample_obj.path
        and not blocked
        and waveform_drag_should_start(hovered) then
      begin_waveform_sample_drag(preview_sample_obj)
      state.map_wave_press = nil
      state.map_wave_press_t = nil
    end
    if sample_is_waveform_drag_source(preview_sample_obj) then
      draw_waveform_drag_source_cue(dl, x0, y0, width, height)
    end
    map_waveform_handle_preview_click(
      preview_sample_obj, hovered, clicked, r.ImGui_IsMouseDown(ctx, 0),
      mx, x0, width, view0, view1, blocked
    )
    return
  end
  
  if waveform and #waveform > 0 then
    if r.ImGui_DrawList_PushClipRect then
      r.ImGui_DrawList_PushClipRect(dl, x0, y0, x0 + width, y0 + height, true)
    end
    local channels = waveform_data.channels or 1
    local channel_data = waveform_data.channel_data
    local frequency_data = waveform_data.frequency_data
    local frequency_channel_data = waveform_data.frequency_channel_data
    
    -- For mono: draw centered waveform (backward compatible)
    -- For stereo+: draw separate waveforms per channel
    if channels == 1 or not channel_data then
      -- Mono waveform: centered display
      local center_y = y0 + height * 0.5
      local half_height = height * 0.4
      
      -- Draw center line
      r.ImGui_DrawList_AddLine(dl, x0, center_y, x0 + width, center_y, 0x444444FF, 1.0)
      
      -- Draw waveform
      local n = #waveform
      local i0 = math.max(1, math.floor((view0 / math.max(file_dur, 0.0001)) * n) - 1)
      local i1 = math.min(n, math.ceil((view1 / math.max(file_dur, 0.0001)) * n) + 1)
      local prev_x = nil
      local prev_y_top = center_y
      local prev_y_bot = center_y
      local prev_color = nil
      
      for i = i0, i1 do
        local x = map_x(((i - 1) / n) * file_dur)
        local value = waveform[i] or 0.0
        local y_top = center_y - value * half_height
        local y_bot = center_y + value * half_height
        
        -- Get frequency-based color for this pixel
        local freq = frequency_data and frequency_data[i]
        local color = frequency_to_color(freq)
        
        -- Draw vertical line for this sample
        r.ImGui_DrawList_AddLine(dl, x, y_top, x, y_bot, color, 1.5)
        
        -- Draw connecting line to previous sample (use average color for smooth transition)
        if prev_x then
          local prev_freq = frequency_data and frequency_data[i - 1]
          local prev_color_val = frequency_to_color(prev_freq)
          -- Blend colors for smooth transition
          local avg_color = color
          if prev_color_val ~= color then
            -- Simple average of RGB components
            local r1 = (color >> 16) & 0xFF
            local g1 = (color >> 8) & 0xFF
            local b1 = color & 0xFF
            local r2 = (prev_color_val >> 16) & 0xFF
            local g2 = (prev_color_val >> 8) & 0xFF
            local b2 = prev_color_val & 0xFF
            local r_avg = math.floor((r1 + r2) / 2)
            local g_avg = math.floor((g1 + g2) / 2)
            local b_avg = math.floor((b1 + b2) / 2)
            avg_color = (0xFF << 24) | (r_avg << 16) | (g_avg << 8) | b_avg
          end
          r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_top, x, y_top, avg_color, 1.0)
          r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_bot, x, y_bot, avg_color, 1.0)
        end
        
        prev_x = x
        prev_y_top = y_top
        prev_y_bot = y_bot
        prev_color = color
      end
    else
      -- Multi-channel waveform: draw separate waveforms per channel
      -- For stereo: left channel on top half, right channel on bottom half
      local channel_height = height / channels
      
      for ch = 0, channels - 1 do
        local ch_data = channel_data[ch]
        local ch_freq_data = frequency_channel_data and frequency_channel_data[ch]
        if ch_data and #ch_data > 0 then
          -- Calculate channel-specific parameters
          local ch_y0 = y0 + ch * channel_height
          local ch_y1 = y0 + (ch + 1) * channel_height
          local ch_center_y = (ch_y0 + ch_y1) * 0.5
          local ch_half_height = channel_height * 0.4
          
          -- Draw center line for this channel
          r.ImGui_DrawList_AddLine(dl, x0, ch_center_y, x0 + width, ch_center_y, 0x444444FF, 1.0)
          
          -- Draw waveform for this channel
          local n = #ch_data
          local i0 = math.max(1, math.floor((view0 / math.max(file_dur, 0.0001)) * n) - 1)
          local i1 = math.min(n, math.ceil((view1 / math.max(file_dur, 0.0001)) * n) + 1)
          local prev_x = nil
          local prev_y_top = ch_center_y
          local prev_y_bot = ch_center_y
          
          for i = i0, i1 do
            local x = map_x(((i - 1) / n) * file_dur)
            local value = ch_data[i] or 0.0
            local y_top = ch_center_y - value * ch_half_height
            local y_bot = ch_center_y + value * ch_half_height
            
            -- Get frequency-based color for this pixel/channel
            local freq = ch_freq_data and ch_freq_data[i]
            local color = frequency_to_color(freq)
            
            -- Draw vertical line for this sample
            r.ImGui_DrawList_AddLine(dl, x, y_top, x, y_bot, color, 1.5)
            
            -- Draw connecting line to previous sample (use average color for smooth transition)
            if prev_x then
              local prev_freq = ch_freq_data and ch_freq_data[i - 1]
              local prev_color_val = frequency_to_color(prev_freq)
              -- Blend colors for smooth transition
              local avg_color = color
              if prev_color_val ~= color then
                -- Simple average of RGB components
                local r1 = (color >> 16) & 0xFF
                local g1 = (color >> 8) & 0xFF
                local b1 = color & 0xFF
                local r2 = (prev_color_val >> 16) & 0xFF
                local g2 = (prev_color_val >> 8) & 0xFF
                local b2 = prev_color_val & 0xFF
                local r_avg = math.floor((r1 + r2) / 2)
                local g_avg = math.floor((g1 + g2) / 2)
                local b_avg = math.floor((b1 + b2) / 2)
                avg_color = (0xFF << 24) | (r_avg << 16) | (g_avg << 8) | b_avg
              end
              r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_top, x, y_top, avg_color, 1.0)
              r.ImGui_DrawList_AddLine(dl, prev_x, prev_y_bot, x, y_bot, avg_color, 1.0)
            end
            
            prev_x = x
            prev_y_top = y_top
            prev_y_bot = y_bot
          end
          
          -- Draw separator line between channels (except after last channel)
          if ch < channels - 1 then
            r.ImGui_DrawList_AddLine(dl, x0, ch_y1, x0 + width, ch_y1, 0x333333FF, 1.0)
          end
        end
      end
    end
    
    -- Effective length marker (draggable) + dim cropped tail
    if preview_sample_obj and file_dur > 0 and width > 1 then
      if state.waveform_eff_drag and state.waveform_eff_drag_path
          and state.waveform_eff_drag_path ~= preview_sample_obj.path then
        state.waveform_eff_drag = false
        state.waveform_eff_drag_path = nil
      end

      local eff = sample_map_duration(preview_sample_obj)
      if eff <= 0 then
        eff = file_dur
      end
      local eff_x = math.max(x0, math.min(x0 + width, map_x(eff)))

      if eff < file_dur - 0.0005 then
        r.ImGui_DrawList_AddRectFilled(dl, eff_x, y0, x0 + width, y0 + height, 0x00000099, 0)
      end

      local handle_color = 0xFF9A3CFF  -- Orange (RRGGBBAA)
      local handle_hover = 0xFFC070FF
      local mx, my = r.ImGui_GetMousePos(ctx)
      local handle_hit = 8.0
      local near_handle = math.abs(mx - eff_x) <= handle_hit and my >= y0 - 4 and my <= y0 + height + 4
      local color = (near_handle or state.waveform_eff_drag) and handle_hover or handle_color

      r.ImGui_DrawList_AddLine(dl, eff_x, y0, eff_x, y0 + height, color, 2.0)
      local tri = 7.0
      r.ImGui_DrawList_AddTriangleFilled(dl,
        eff_x, y0 + 1,
        eff_x - tri, y0 + tri + 1,
        eff_x + tri, y0 + tri + 1,
        color)
      r.ImGui_DrawList_AddTriangleFilled(dl,
        eff_x, y0 + height - 1,
        eff_x - tri, y0 + height - tri - 1,
        eff_x + tri, y0 + height - tri - 1,
        color)

      local label = string.format("%.2fs", eff)
      local label_w = select(1, r.ImGui_CalcTextSize(ctx, label)) or 36
      local label_x = math.min(eff_x + 6, x0 + width - label_w - 4)
      if label_x < x0 + 4 then
        label_x = x0 + 4
      end
      r.ImGui_DrawList_AddText(dl, label_x + 1, y0 + 8, 0x000000AA, label)
      r.ImGui_DrawList_AddText(dl, label_x, y0 + 7, color, label)

      if (hovered and near_handle) or state.waveform_eff_drag then
        if r.ImGui_MouseCursor_ResizeEW then
          r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
        else
          r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
        end
      end

      if hovered and near_handle and not state.waveform_eff_drag then
        hint_tooltip("Effective length\nDrag to crop trailing silence\nDouble-click to reset to full file")
      end

      if hovered and near_handle and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        preview_sample_obj.effective_duration = file_dur
        state.waveform_eff_drag = false
        state.waveform_eff_drag_path = nil
        save_samples()
        layout_samples()
        clicked = false
      elseif (clicked and near_handle) or state.waveform_eff_drag then
        if r.ImGui_IsMouseDown(ctx, 0) then
          state.waveform_eff_drag = true
          state.waveform_eff_drag_path = preview_sample_obj.path
          preview_sample_obj.effective_duration = clamp_effective_duration(
            preview_sample_obj, wave_x_to_time(mx, x0, width, view0, view1)
          )
          clicked = false
        elseif state.waveform_eff_drag then
          state.waveform_eff_drag = false
          state.waveform_eff_drag_path = nil
          save_samples()
          layout_samples()
          clicked = false
        end
      end
    end

    -- Transient / sustain split (drum one-shots)
    if preview_sample_obj and type(preview_sample_obj.transient_end) == "number"
        and preview_sample_obj.transient_end > 0 and width > 1 then
      local ts_dur = waveform_data.duration or preview_sample_obj.duration or 0.0
      if ts_dur > 0 then
        local function time_to_x(t)
          return math.max(x0, math.min(x0 + width, map_x(t)))
        end
        local onset_t = preview_sample_obj.onset
        if type(onset_t) ~= "number" or onset_t < 0 then
          onset_t = 0.0
        end
        local trans_t = preview_sample_obj.transient_end
        local sustain_t = sample_map_duration(preview_sample_obj)
        if sustain_t <= 0 then
          sustain_t = ts_dur
        end
        local onset_x = time_to_x(onset_t)
        local trans_x = time_to_x(trans_t)
        local sustain_x = time_to_x(sustain_t)

        if trans_x > onset_x + 0.5 then
          r.ImGui_DrawList_AddRectFilled(dl, onset_x, y0, trans_x, y0 + height, 0xFF6B3C33, 0)
        end
        if sustain_x > trans_x + 0.5 then
          r.ImGui_DrawList_AddRectFilled(dl, trans_x, y0, sustain_x, y0 + height, 0x4A9CFF28, 0)
        end

        local ts_color = 0x7CFF4AFF  -- Lime (RRGGBBAA)
        r.ImGui_DrawList_AddLine(dl, trans_x, y0, trans_x, y0 + height, ts_color, 2.0)
        local tri = 5.5
        r.ImGui_DrawList_AddTriangleFilled(dl,
          trans_x, y0,
          trans_x - tri, y0 + tri,
          trans_x + tri, y0 + tri,
          ts_color)
        r.ImGui_DrawList_AddTriangleFilled(dl,
          trans_x, y0 + height,
          trans_x - tri, y0 + height - tri,
          trans_x + tri, y0 + height - tri,
          ts_color)
        if (trans_x - onset_x) >= 10.0 then
          r.ImGui_DrawList_AddText(dl, onset_x + 3, y0 + 2, ts_color, "T")
        end
        if (sustain_x - trans_x) >= 10.0 then
          r.ImGui_DrawList_AddText(dl, trans_x + 4, y0 + 2, 0xA8D4FFFF, "S")
        end
      end
    end

    -- Draw snap offset marker if available
    if preview_sample_obj and preview_sample_obj.snap_offset then
      local snap_time = preview_sample_obj.snap_offset
      local duration = waveform_data.duration or preview_sample_obj.duration or 1.0
      if duration > 0 and snap_time >= 0 and snap_time <= duration then
        local snap_x = math.max(x0, math.min(x0 + width, map_x(snap_time)))
        
        -- Draw snap offset line (bright yellow/green, distinct from playhead)
        local snap_color = 0x00FFFFFF  -- Cyan (RRGGBBAA format)
        local snap_thickness = 2.5
        r.ImGui_DrawList_AddLine(dl, snap_x, y0, snap_x, y0 + height, snap_color, snap_thickness)
        
        -- Draw snap offset indicators at top and bottom (triangles pointing down/up)
        local triangle_size = 6.0
        -- Top triangle (pointing down)
        r.ImGui_DrawList_AddTriangleFilled(dl, 
          snap_x, y0, 
          snap_x - triangle_size, y0 + triangle_size, 
          snap_x + triangle_size, y0 + triangle_size, 
          snap_color)
        -- Bottom triangle (pointing up)
        r.ImGui_DrawList_AddTriangleFilled(dl, 
          snap_x, y0 + height, 
          snap_x - triangle_size, y0 + height - triangle_size, 
          snap_x + triangle_size, y0 + height - triangle_size, 
          snap_color)
      end
    end
    
    -- Draw playhead when playing or paused
    local current_pos = get_preview_position()
    local duration = waveform_data.duration or 1.0
    if (preview_proc ~= nil or state.preview_paused) and current_pos ~= nil and duration > 0
        and current_pos >= view0 and current_pos <= view1 then
      local playhead_x = math.max(x0, math.min(x0 + width, map_x(current_pos)))
      
      -- Draw playhead line (bright yellow, thicker for visibility)
      local playhead_color = 0xFFFF88FF  -- Yellow (RRGGBBAA format)
      local playhead_thickness = 2.0
      r.ImGui_DrawList_AddLine(dl, playhead_x, y0, playhead_x, y0 + height, playhead_color, playhead_thickness)
      
      -- Draw playhead indicators at top and bottom (filled circles for better visibility)
      local indicator_radius = 5.0
      r.ImGui_DrawList_AddCircleFilled(dl, playhead_x, y0, indicator_radius, playhead_color, 16)
    end
    if r.ImGui_DrawList_PopClipRect then
      r.ImGui_DrawList_PopClipRect(dl)
    end
  end
  
  local mx, my = r.ImGui_GetMousePos(ctx)
  local left_down = r.ImGui_IsMouseDown(ctx, 0)
  local ctl = draw_sample_wave_controls(
    dl, preview_sample_obj, x0, y0, width, height, file_dur, view0, view1,
    mx, my, left_down, clicked, "map", { show_name = false }
  )
  local tags_hit = render_waveform_overlay_tags(x0, y0, width, height, layout_x, layout_y)

  local alt = false
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftAlt then
    alt = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt())
        or (r.ImGui_Key_RightAlt and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt()))
  end
  local mid_down = r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 2)
  if hovered and not tags_hit and not (ctl and ctl.over_vol) then
    local wheel = r.ImGui_GetMouseWheel and select(1, r.ImGui_GetMouseWheel(ctx)) or 0
    if wheel and wheel ~= 0 then
      wave_view_zoom(preview_sample_obj, file_dur, mx, x0, width, wheel)
    end
  end
  if hovered and not tags_hit and (mid_down or (alt and left_down)) and not (ctl and ctl.consumed) and not state.waveform_eff_drag then
    local dx = select(1, r.ImGui_GetMouseDelta(ctx)) or 0
    state.wave_view_pan = true
    wave_view_pan(preview_sample_obj, file_dur, dx, width)
    clicked = false
  elseif state.wave_view_pan and not mid_down and not (alt and left_down) then
    state.wave_view_pan = nil
  end
  if hovered and clicked and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
      and not tags_hit and not (ctl and ctl.consumed) and not state.waveform_eff_drag then
    wave_view_reset(preview_sample_obj, file_dur)
    clicked = false
  end

  -- Handle click to play / click-again to stop (same as sequencer header preview)
  local blocked = tags_hit or state.waveform_eff_drag or (ctl and ctl.consumed)
      or state.wave_view_pan or state.pending_waveform_drop
  if preview_sample_obj and preview_sample_obj.path
      and not blocked
      and waveform_drag_should_start(hovered) then
    begin_waveform_sample_drag(preview_sample_obj)
    state.map_wave_press = nil
    state.map_wave_press_t = nil
  end
  if sample_is_waveform_drag_source(preview_sample_obj) then
    draw_waveform_drag_source_cue(dl, x0, y0, width, height)
  end
  map_waveform_handle_preview_click(
    preview_sample_obj, hovered, clicked, left_down,
    mx, x0, width, view0, view1, blocked
  )
end

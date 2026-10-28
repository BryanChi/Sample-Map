-- Sample Map Browser module: monolith
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Monolith look -----------------------------------------------------------
-- Shared Monolith palette and helpers (hairline borders, square corners, green
-- corner ticks), plus the "Monolith Space" look: the same design on a deep
-- blue-violet canvas with a little star dust, cyan accent and green ticks,
-- to sit with the galaxy map. Settings > General > Look picks it; Classic
-- (the default) draws exactly as before.
--
-- SM_MONO_SPACE is the one switch. sm_look_set(on) changes and saves it;
-- ui_push_theme applies it before the next frame. A test can set the global
-- (or ExtState SampleMapBrowser/look = "monolith_space") before the first frame.

SM_LOOK_EXT_SECTION = "SampleMapBrowser"
SM_LOOK_EXT_KEY = "look"

-- Plain Monolith (neutral black), as Song Starter uses it.
MONO_COL = {
  bg       = 0x050505FF,
  body     = 0x0C0C0DFF,
  panel    = 0x0B0B0BFF,
  line     = 0xFFFFFF1F,
  line_hi  = 0xFFFFFF40,
  text     = 0xE8E8E8FF,
  dim      = 0x8A8A8AFF,
  mute     = 0x555555FF,
  accent   = 0x49CC85FF,
  accent_d = 0x49CC8526,
  accent_m = 0x49CC8560,
  warn     = 0xE0A060FF,
}

-- Monolith Space: near-black with a blue-violet cast, cool hairlines, ice
-- cyan accent, violet nebula, Monolith green kept for selection ticks.
MONO_SPACE_COL = {
  bg       = 0x06070EFF,
  body     = 0x0B0C17FF,
  panel    = 0x0D0F1BFF,
  line     = 0xB4C0FF26,
  line_hi  = 0xC8D2FF52,
  text     = 0xE6E9F6FF,
  dim      = 0x9CA3C4FF,
  mute     = 0x6E7598FF,
  accent   = 0x6FD3FFFF,
  accent_d = 0x6FD3FF26,
  accent_m = 0x6FD3FF60,
  tick     = 0x49CC85FF,
  nebula   = 0x8C7CFFFF,
  warn     = 0xE8B070FF,
}

-- UI_THEME values for Monolith Space. Borders are opaque (some callers fill
-- with them); text stays at Classic contrast or better.
UI_THEME_SPACE = {
  bg            = 0x06070EFF,
  bg_panel      = 0x0A0B15FF,
  surface       = 0x0E1020FF,
  surface_hvr   = 0x171A30FF,
  surface_act   = 0x0B0D1AFF,
  elevated      = 0x121426FF,
  border        = 0x23273FFF,
  border_soft   = 0x181B2EFF,
  border_hvr    = 0x454C78FF,
  text          = 0xE6E9F6FF,
  text_dim      = 0x9CA3C4FF,
  text_mute     = 0x6E7598FF,
  popup_bg      = 0x080915FA,
  title_bg      = 0x05060CFF,
  title_bg_act  = 0x080A14FF,
  accent        = 0x6FD3FFFF,
  accent_hvr    = 0xA2E4FFFF,
  accent_fill   = 0x0E2234FF,
  accent_fill_h = 0x163650FF,
  accent_press  = 0x0A1826FF,
  accent_strong = 0x154A66FF,
  accent_strong_h = 0x1C5C7EFF,
  accent_strong_a = 0x0F3448FF,
  danger        = 0xE87884FF,
  danger_fill   = 0x341A26FF,
  danger_hvr    = 0x46222FFF,
  success       = 0x49CC85FF,
  success_fill  = 0x10291FFF,
  success_hvr   = 0x183C2CFF,
  folder        = 0x1E3656FF,
  folder_hvr    = 0x2A4A72FF,
  grid_line     = 0xA8B4FF1C,
  grid_text     = 0x9CA3C4A0,
}

UI_METRICS_SPACE = { radius_panel = 0, radius_ctrl = 0 }

-- Classic values, snapshotted on first apply so Monolith Space can switch back.
local classic_theme, classic_metrics, classic_mono = nil, nil, nil

-- Set up in the Fonts and Title bar sections below.
local install_cond_wrappers, install_title_bars

-- Rect draws with rounding forced to 0 while Monolith Space is on.
local orig_add_rect, orig_add_rect_filled = nil, nil

local function install_square_rects(on)
  if not orig_add_rect then
    orig_add_rect = r.ImGui_DrawList_AddRect
    orig_add_rect_filled = r.ImGui_DrawList_AddRectFilled
  end
  if on and orig_add_rect and orig_add_rect_filled then
    local add_rect, add_fill = orig_add_rect, orig_add_rect_filled
    r.ImGui_DrawList_AddRect = function(dl, x0, y0, x1, y1, col, rounding, flags, thickness)
      return add_rect(dl, x0, y0, x1, y1, col, 0, flags, thickness)
    end
    r.ImGui_DrawList_AddRectFilled = function(dl, x0, y0, x1, y1, col, rounding, flags)
      return add_fill(dl, x0, y0, x1, y1, col, 0, flags)
    end
  else
    r.ImGui_DrawList_AddRect = orig_add_rect
    r.ImGui_DrawList_AddRectFilled = orig_add_rect_filled
  end
end

local function copy_into(dst, src)
  for k, v in pairs(src) do
    dst[k] = v
  end
end

function sm_look_load()
  if SM_MONO_SPACE == nil then
    local v = r.GetExtState and r.GetExtState(SM_LOOK_EXT_SECTION, SM_LOOK_EXT_KEY) or ""
    SM_MONO_SPACE = v == "monolith_space"
  end
  return SM_MONO_SPACE
end

-- Make UI_THEME / UI_METRICS / MONO_COL (and SS_COL) match SM_MONO_SPACE.
-- Tables are changed in place: callers read them at draw time.
function sm_look_apply()
  local on = sm_look_load() and true or false
  if not classic_theme then
    classic_theme, classic_metrics, classic_mono = {}, {}, {}
    copy_into(classic_theme, UI_THEME)
    copy_into(classic_metrics, UI_METRICS)
    copy_into(classic_mono, MONO_COL)
  end
  copy_into(UI_THEME, on and UI_THEME_SPACE or classic_theme)
  copy_into(UI_METRICS, on and UI_METRICS_SPACE or classic_metrics)
  copy_into(MONO_COL, on and MONO_SPACE_COL or classic_mono)
  MONO_COL.tick = on and MONO_SPACE_COL.tick or classic_mono.accent
  if SS_COL then
    copy_into(SS_COL, MONO_COL)
  end
  install_square_rects(on)
  install_cond_wrappers(on)
  install_title_bars(on)
  sm_look_applied = on
  if sm_mono_stars_reset then
    sm_mono_stars_reset()
  end
end

function sm_look_set(on)
  SM_MONO_SPACE = on and true or false
  if r.SetExtState then
    r.SetExtState(SM_LOOK_EXT_SECTION, SM_LOOK_EXT_KEY, SM_MONO_SPACE and "monolith_space" or "classic", true)
  end
  sm_look_apply()
end

-- Called by ui_push_theme every frame; applies only when the switch changed.
function sm_look_sync()
  if sm_look_applied ~= (sm_look_load() and true or false) then
    sm_look_apply()
  end
end

-- L ticks on the corners of a rect (Monolith selection mark).
function mono_corner_ticks(dl, x0, y0, x1, y1, col, k)
  k = k or 6
  local add_line = r.ImGui_DrawList_AddLine
  add_line(dl, x0, y0, x0 + k, y0, col, 1)
  add_line(dl, x0, y0, x0, y0 + k, col, 1)
  add_line(dl, x1, y0, x1 - k, y0, col, 1)
  add_line(dl, x1, y0, x1, y0 + k, col, 1)
  add_line(dl, x0, y1, x0 + k, y1, col, 1)
  add_line(dl, x0, y1, x0, y1 - k, col, 1)
  add_line(dl, x1, y1, x1 - k, y1, col, 1)
  add_line(dl, x1, y1, x1, y1 - k, col, 1)
end

-- Uppercase caption in letter-spaced Barlow Semi Condensed. -> width drawn.
function mono_caps_text(dl, x, y, col, text, spacing)
  spacing = spacing or 1.5
  local s = string.upper(text or "")
  local pushed = sm_mono_push_font("cond")
  local cx = x
  local add_text, calc = r.ImGui_DrawList_AddText, r.ImGui_CalcTextSize
  for i = 1, #s do
    local ch = s:sub(i, i)
    add_text(dl, cx, y, col, ch)
    cx = cx + (calc(ctx, ch) or 7) + spacing
  end
  if pushed then
    r.ImGui_PopFont(ctx)
  end
  return cx - x - spacing
end

-- Width of mono_caps_text(text) without drawing it.
function mono_caps_width(text, spacing)
  spacing = spacing or 1.5
  local s = string.upper(text or "")
  local pushed = sm_mono_push_font("cond")
  local w = (r.ImGui_CalcTextSize(ctx, s) or (#s * 7)) + math.max(0, #s - 1) * spacing
  if pushed then
    r.ImGui_PopFont(ctx)
  end
  return w
end

-- Big title in Anton at `size` (default the title font size). Falls back to
-- the current font, drawn twice for weight. -> width, height.
function mono_title_text(dl, x, y, col, text, size)
  local f = SM_MONO_SPACE and SM_MONO_FONTS.title
  local spec = SM_FONT_SPECS.title
  size = size or spec[2]
  if f and r.ImGui_DrawList_AddTextEx then
    r.ImGui_DrawList_AddTextEx(dl, f, size, x, y, col, text)
    local pushed = sm_mono_push_font("title")
    local w, h = r.ImGui_CalcTextSize(ctx, text)
    if pushed then
      r.ImGui_PopFont(ctx)
    end
    local k = size / spec[2]
    return (w or 0) * k, (h or size) * k
  end
  r.ImGui_DrawList_AddText(dl, x, y, col, text)
  r.ImGui_DrawList_AddText(dl, x + 0.5, y, col, text)
  return r.ImGui_CalcTextSize(ctx, text)
end

-- --- Fonts --------------------------------------------------------------------
-- Monolith Space type (assets/fonts): Inter Tight for body text, Barlow Semi
-- Condensed for tight places (tag chips, top bar, toolbars, Song Starter,
-- map labels, small caps), Anton for big titles. Created and attached at
-- startup next to the Classic font; used only while the look is on.
SM_FONT_SPECS = {
  body  = { "InterTight-VariableFont_wght.ttf", 14 },
  bold  = { "InterTight-SemiBold.ttf", 14 },
  cond  = { "BarlowSemiCondensed-Medium.ttf", 14 },
  title = { "Anton-Regular.ttf", 20 },
}
SM_MONO_FONTS = {}

local function reaimgui_ge(major, minor)
  if not r.ImGui_GetVersion then
    return false
  end
  local _, _, rv = r.ImGui_GetVersion()
  local a, b = tostring(rv or ""):match("^(%d+)%.(%d+)")
  a, b = tonumber(a), tonumber(b)
  if not a then
    return false
  end
  return a > major or (a == major and b >= minor)
end

SM_IMGUI_FONT_SIZE_ARG = reaimgui_ge(0, 10)

local function create_font(file, size)
  local path = (SCRIPT_DIR or ".") .. "/assets/fonts/" .. file
  local exists = r.file_exists and r.file_exists(path)
  local ok, f
  if exists and SM_IMGUI_FONT_SIZE_ARG and r.ImGui_CreateFontFromFile then
    ok, f = pcall(r.ImGui_CreateFontFromFile, path)
  elseif exists then
    ok, f = pcall(r.ImGui_CreateFont, path, size)
  end
  if not (ok and f) then
    ok, f = pcall(r.ImGui_CreateFont, "sans-serif", size)
  end
  return ok and f or nil
end

-- Call right after the ImGui context is created (before its first frame).
function sm_mono_fonts_create(ctx_)
  SM_MONO_FONTS = {}
  if not (ctx_ and r.ImGui_Attach) then
    return
  end
  for key, spec in pairs(SM_FONT_SPECS) do
    local f = create_font(spec[1], spec[2])
    if f and pcall(r.ImGui_Attach, ctx_, f) then
      SM_MONO_FONTS[key] = f
    end
  end
end

-- Push a Monolith Space font ("body", "bold", "cond" or "title").
-- -> true when pushed (then PopFont).
function sm_mono_push_font(kind)
  if not SM_MONO_SPACE or not r.ImGui_PushFont then
    return false
  end
  kind = kind or "body"
  local f = SM_MONO_FONTS[kind]
  if not f then
    return false
  end
  if SM_IMGUI_FONT_SIZE_ARG then
    r.ImGui_PushFont(ctx, f, SM_FONT_SPECS[kind][2])
  else
    r.ImGui_PushFont(ctx, f)
  end
  return true
end

-- Tight places drawn by whole functions: run them under Barlow while the
-- look is on (wrappers installed by sm_look_apply, removed when it is off).
SM_COND_FUNCS = {
  "render_view_tab_switcher", "render_map_y_axis_segmented", "render_map_layout_toggle",
  "render_sample_map_tab_bar", "render_sample_path_line", "render_seq_top_toolbar",
  "render_seq_gmd_toolbar", "draw_map_atlas_labels", "render_song_starter_window",
}
local cond_orig = {}

local function pop_after(pushed, ...)
  if pushed then
    r.ImGui_PopFont(ctx)
  end
  return ...
end

install_cond_wrappers = function(on)
  for _, name in ipairs(SM_COND_FUNCS) do
    local cur = _G[name]
    if on and type(cur) == "function" and not cond_orig[name] then
      cond_orig[name] = cur
      _G[name] = function(...)
        return pop_after(sm_mono_push_font("cond"), cur(...))
      end
    elseif not on and cond_orig[name] then
      _G[name] = cond_orig[name]
      cond_orig[name] = nil
    end
  end
end

-- --- Space recolour -----------------------------------------------------------
local function hsv_from_rgb(rr, gg, bb)
  local mx, mn = math.max(rr, gg, bb), math.min(rr, gg, bb)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == rr then
      h = ((gg - bb) / d) % 6
    elseif mx == gg then
      h = (bb - rr) / d + 2
    else
      h = (rr - gg) / d + 4
    end
    h = h * 60
  end
  return h, (mx > 0) and d / mx or 0, mx
end

local function rgb_from_hsv(h, s, v)
  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c
  local rr, gg, bb
  if h < 60 then rr, gg, bb = c, x, 0
  elseif h < 120 then rr, gg, bb = x, c, 0
  elseif h < 180 then rr, gg, bb = 0, c, x
  elseif h < 240 then rr, gg, bb = 0, x, c
  elseif h < 300 then rr, gg, bb = x, 0, c
  else rr, gg, bb = c, 0, x end
  return rr + m, gg + m, bb + m
end

local function clamp_byte(v)
  return math.max(0, math.min(255, math.floor(v + 0.5)))
end

-- Classic fixed colour -> Monolith Space: neutral grays take the blue-violet
-- cast of the space palette, accent greens turn toward the cyan accent.
-- Anything else (amber, red, lime role colours...) is returned unchanged.
function sm_space_tone(c)
  if type(c) ~= "number" then
    return c
  end
  local rr, gg, bb, a = (c >> 24) & 0xFF, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
  local mx, mn = math.max(rr, gg, bb), math.min(rr, gg, bb)
  local nr, ng, nb
  if mx - mn <= 10 and mx >= 0x08 and mx <= 0xF4 then
    local l = (rr + gg + bb) / 3
    if l < 0x80 then
      nr, ng, nb = l * 0.86, l * 0.9, l * 1.3 + 3
    else
      nr, ng, nb = l * 0.97, l * 0.985, l * 1.04 + 4
    end
  elseif gg >= rr + 30 and gg >= bb + 20 and gg >= 0x30 and bb >= rr then
    local h, s, v = hsv_from_rgb(rr / 255, gg / 255, bb / 255)
    nr, ng, nb = rgb_from_hsv((h + 62) % 360, s * 0.72, v)
    nr, ng, nb = nr * 255, ng * 255, nb * 255
  else
    return c
  end
  return (clamp_byte(nr) << 24) | (clamp_byte(ng) << 16) | (clamp_byte(nb) << 8) | a
end

-- --- Tick-ring knob -----------------------------------------------------------
-- Monolith knob (as FX Devices' MONO.Knob): thin track, ticks between ring
-- and cap that light up to the value, accent value arc, dark cap + pointer.
-- o: hovered, active, arc (colour), bipolar.
function mono_knob(dl, cx, cy, rad, t, o)
  o = o or {}
  t = math.max(0, math.min(1, t or 0))
  local A0, A1 = math.pi * 0.75, math.pi * 2.25
  local acc = o.arc or MONO_COL.accent
  local seg = math.max(18, math.floor(rad * 1.8))
  local arc_w = rad >= 16 and 2 or 1.6
  local arc_r = rad - arc_w / 2
  local ticks = rad >= 11
  local cap_r = rad - (ticks and math.max(5, rad * 0.3) or math.max(3, rad * 0.24))
  local add_line = r.ImGui_DrawList_AddLine
  local has_path = r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke
  local function arc(a0, a1, col)
    if has_path then
      r.ImGui_DrawList_PathArcTo(dl, cx, cy, arc_r, a0, a1, seg)
      r.ImGui_DrawList_PathStroke(dl, col, 0, arc_w)
    else
      local n = math.max(6, math.floor(seg * (a1 - a0) / (A1 - A0)))
      local px, py
      for i = 0, n do
        local a = a0 + (a1 - a0) * i / n
        local ax, ay = cx + math.cos(a) * arc_r, cy + math.sin(a) * arc_r
        if px then add_line(dl, px, py, ax, ay, col, arc_w) end
        px, py = ax, ay
      end
    end
  end
  arc(A0, A1, o.hovered and 0xC8D2FF38 or 0xB4C0FF22)
  if ticks then
    local n = 10
    local r1, r2 = cap_r + 2, arc_r - arc_w / 2 - 1.5
    for i = 0, n do
      local a = A0 + (A1 - A0) * i / n
      local lit = (i / n) <= t + 0.001
      local col = lit and (o.hovered and 0xE6E9F6B8 or 0xE6E9F678) or 0xB4C0FF2A
      local ca, sa = math.cos(a), math.sin(a)
      add_line(dl, cx + ca * r1, cy + sa * r1, cx + ca * r2, cy + sa * r2, col, 1)
    end
  end
  local a = A0 + (A1 - A0) * t
  local from = o.bipolar and (A0 + A1) / 2 or A0
  if math.abs(a - from) > 0.01 then
    arc(math.min(from, a), math.max(from, a), o.active and 0xFFFFFFFF or acc)
  end
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, cap_r, o.active and 0x161A2CFF or 0x0A0B15FF, seg)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, cap_r, o.hovered and 0xC8D2FF60 or 0xB4C0FF33, seg, 1)
  local ca, sa = math.cos(a), math.sin(a)
  add_line(dl, cx + ca * cap_r * 0.2, cy + sa * cap_r * 0.2, cx + ca * (cap_r - 1.5), cy + sa * (cap_r - 1.5),
    o.hovered and 0xFFFFFFFF or MONO_COL.text, rad >= 16 and 1.8 or 1.5)
end

-- --- Title bar ---------------------------------------------------------------
-- Monolith Space replaces ReaImGui's title bar on every titled Sample Map
-- window (as Vertical FX List's Settings window): Anton title, hairline under
-- it, square X on the right; drag the bar (or any empty spot) to move. ImGui_Begin and
-- ImGui_BeginPopupModal are wrapped while the look is on; windows that already
-- have NoTitleBar, or a "##..." name, are left alone, and docked windows keep
-- their dock tab.
SM_TITLE_BAR_H = 34
local orig_begin, orig_begin_modal = nil, nil
local modal_closed = {}

local function title_of(name)
  local s = tostring(name or "")
  local t = s:match("^(.-)###") or s:match("^(.-)##") or s
  return t
end

-- Draws the bar in the current window. -> true when its X was clicked.
function sm_title_bar(title, closable, id)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetWindowPos(ctx)
  local w = r.ImGui_GetWindowSize(ctx)
  if not (dl and x and w) then
    return false
  end
  local h = SM_TITLE_BAR_H
  local pad_x, pad_y = 10, 8
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_WindowPadding then
    pad_x, pad_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_WindowPadding())
    pad_x, pad_y = pad_x or 10, pad_y or 8
  end
  r.ImGui_PushClipRect(ctx, x, y, x + w, y + h + 1, false)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, MONO_COL.body, 0)
  r.ImGui_DrawList_AddLine(dl, x, y + h, x + w, y + h, MONO_COL.line, 1)
  local text = string.upper(title or "")
  -- Anton 16: its line box is about 1.25x the size.
  mono_title_text(dl, x + 14, y + (h - 16 * 1.25) * 0.5, MONO_COL.text, text, 16)

  local clicked = false
  local cs = 22
  local cx, cy = x + w - 10 - cs, y + (h - cs) * 0.5
  -- No item on the rest of the bar: a press there hits the window itself, and
  -- ImGui moves a title-less window natively (in step with its OS window;
  -- moving it from Lua with SetWindowPos lags a frame behind).
  if closable then
    r.ImGui_SetCursorScreenPos(ctx, cx, cy)
    clicked = r.ImGui_InvisibleButton(ctx, "##sm_title_close" .. tostring(id or title), cs, cs)
    local hov = r.ImGui_IsItemHovered(ctx)
    r.ImGui_DrawList_AddRect(dl, cx, cy, cx + cs, cy + cs, hov and 0xFFFFFF80 or MONO_COL.line_hi, 0, 0, 1)
    local cc, k = hov and MONO_COL.text or MONO_COL.dim, 4.5
    local mx, my = cx + cs * 0.5, cy + cs * 0.5
    r.ImGui_DrawList_AddLine(dl, mx - k, my - k, mx + k, my + k, cc, 1.4)
    r.ImGui_DrawList_AddLine(dl, mx + k, my - k, mx - k, my + k, cc, 1.4)
    if hov then
      r.ImGui_SetTooltip(ctx, "Close")
    end
  end
  r.ImGui_PopClipRect(ctx)
  -- Content starts under the bar.
  r.ImGui_SetCursorScreenPos(ctx, x + pad_x, y + h + pad_y)
  return clicked and true or false
end

local function wants_bar(name, flags)
  if type(name) ~= "string" or name:sub(1, 2) == "##" or title_of(name) == "" then
    return false
  end
  local ntb = r.ImGui_WindowFlags_NoTitleBar and r.ImGui_WindowFlags_NoTitleBar() or 0
  return ntb ~= 0 and ((flags or 0) & ntb) == 0, ntb
end

local function docked()
  return r.ImGui_IsWindowDocked and r.ImGui_IsWindowDocked(ctx) or false
end

local begin_wrapper, modal_wrapper = nil, nil

install_title_bars = function(on)
  if not on then
    if begin_wrapper and r.ImGui_Begin == begin_wrapper then
      r.ImGui_Begin = orig_begin
    end
    if modal_wrapper and r.ImGui_BeginPopupModal == modal_wrapper then
      r.ImGui_BeginPopupModal = orig_begin_modal
    end
    return
  end
  if r.ImGui_Begin ~= begin_wrapper then
    orig_begin = r.ImGui_Begin
  end
  if r.ImGui_BeginPopupModal ~= modal_wrapper then
    orig_begin_modal = r.ImGui_BeginPopupModal
  end
  if not orig_begin then
    return
  end
  local begin, begin_modal = orig_begin, orig_begin_modal
  begin_wrapper = function(c, name, p_open, flags)
    local bar, ntb = wants_bar(name, flags)
    if not bar or c ~= ctx or not SM_MONO_SPACE then
      return begin(c, name, p_open, flags)
    end
    local visible, open = begin(c, name, p_open, (flags or 0) | ntb)
    if visible and not docked() then
      if sm_title_bar(title_of(name), p_open ~= nil, name) then
        open = false
      end
    end
    return visible, open
  end
  r.ImGui_Begin = begin_wrapper
  if begin_modal then
    modal_wrapper = function(c, name, p_open, flags)
      local bar, ntb = wants_bar(name, flags)
      if not bar or c ~= ctx or not SM_MONO_SPACE then
        return begin_modal(c, name, p_open, flags)
      end
      local visible, open = begin_modal(c, name, p_open, (flags or 0) | ntb)
      if not visible then
        if modal_closed[name] then
          modal_closed[name] = nil
          return false, false
        end
        return visible, open
      end
      if sm_title_bar(title_of(name), p_open ~= nil, name) then
        modal_closed[name] = true
        r.ImGui_CloseCurrentPopup(c)
        open = false
      end
      return visible, open
    end
    r.ImGui_BeginPopupModal = modal_wrapper
  end
end

-- --- Star dust backdrop -----------------------------------------------------
-- A fixed set of points in unit space (seeded, so it never shimmers), scaled
-- to the window. Drawn first on a window's draw list, under its content.
local stars = nil
local STAR_COUNT = 90

function sm_mono_stars_reset()
  stars = nil
end

local function build_stars()
  local seed = 0x5EED
  local function rnd()
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed / 0x7FFFFFFF
  end
  local list = {}
  for i = 1, STAR_COUNT do
    local bright = rnd()
    local a = math.floor(0x18 + bright * bright * 0x60)
    local tint = rnd() < 0.25 and 0xC8B8FF00 or 0xD8E2FF00
    list[i] = { x = rnd(), y = rnd(), r = bright > 0.92 and 1.3 or 0.8, col = tint | a }
  end
  stars = list
end

-- Faint nebula glow and star dust over the current window. No-op in Classic.
function sm_mono_space_backdrop()
  if not SM_MONO_SPACE or not ctx then
    return
  end
  if not stars then
    build_stars()
  end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww, wh = r.ImGui_GetWindowSize(ctx)
  if not (dl and wx and ww and ww > 0 and wh and wh > 0) then
    return
  end
  local add_circle = r.ImGui_DrawList_AddCircleFilled
  if add_circle then
    -- Two soft glows (violet low-left, cyan high-right): stacked circles at
    -- alpha 1-2 so the edge fades out instead of showing a hard disc.
    local gx, gy, gr = wx + ww * 0.18, wy + wh * 0.82, math.max(ww, wh) * 0.45
    local hx, hy, hr = wx + ww * 0.86, wy + wh * 0.12, math.max(ww, wh) * 0.32
    for k = 0, 13 do
      local f = 1 - k / 14
      add_circle(dl, gx, gy, gr * f, k < 7 and 0x8C7CFF01 or 0x8C7CFF02, 48)
      add_circle(dl, hx, hy, hr * f, 0x6FD3FF01, 40)
    end
    for i = 1, #stars do
      local s = stars[i]
      add_circle(dl, wx + s.x * ww, wy + s.y * wh, s.r, s.col, 6)
    end
  end
end

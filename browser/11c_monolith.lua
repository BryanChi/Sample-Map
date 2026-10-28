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

-- Uppercase caption with a little letter spacing. -> width drawn.
function mono_caps_text(dl, x, y, col, text, spacing)
  spacing = spacing or 1.5
  local s = string.upper(text or "")
  local cx = x
  local add_text, calc = r.ImGui_DrawList_AddText, r.ImGui_CalcTextSize
  for i = 1, #s do
    local ch = s:sub(i, i)
    add_text(dl, cx, y, col, ch)
    cx = cx + (calc(ctx, ch) or 7) + spacing
  end
  return cx - x - spacing
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
    -- Two soft glows: violet low-left, cyan high-right.
    local gx, gy, gr = wx + ww * 0.18, wy + wh * 0.82, math.max(ww, wh) * 0.45
    add_circle(dl, gx, gy, gr, 0x8C7CFF0C, 48)
    add_circle(dl, gx, gy, gr * 0.6, 0x8C7CFF08, 40)
    local hx, hy, hr = wx + ww * 0.86, wy + wh * 0.12, math.max(ww, wh) * 0.32
    add_circle(dl, hx, hy, hr, 0x6FD3FF08, 40)
    for i = 1, #stars do
      local s = stars[i]
      add_circle(dl, wx + s.x * ww, wy + s.y * wh, s.r, s.col, 6)
    end
  end
end

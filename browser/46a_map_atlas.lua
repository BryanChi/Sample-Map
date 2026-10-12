-- Sample Map Browser module: map_atlas
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Map atlas: axes, guides, galaxy look, overview ------------------------------
-- Everything here is drawn behind or around the dots by render_map():
--   * axis bounds read from the library the same way layout_samples() places
--     dots, so grid labels line up with the dots they describe
--   * an adaptive grid: decades, then 2 / 5, then every step fade in as the
--     zoom gives them room (instead of stretching ten fixed lines)
--   * optional frequency bands (SUB ... AIR) and length zones (HITS ... LOOPS)
--   * the galaxy: deep-space backdrop with parallax star dust, a nebula glow
--     in the tag colours where samples crowd together, samples drawn as stars,
--     and (zoomed in) constellation lines between close samples of one tag
--   * an atlas of the filtered samples, built a slice per frame: the nebula
--     grid, one label per colour tag, the overview map and off-screen counts
-- The atlas grid is in map space (0..1), so it never rebuilds while panning or
-- zooming; only filter, library or layout changes rebuild it.

MAP_ATLAS_COLS = 96
MAP_ATLAS_ROWS = 64
MAP_ATLAS_SLICE = 6000          -- samples binned per frame while building
MAP_ATLAS_MIN_TAG = 25          -- smallest tag that gets a label
MAP_ATLAS_MAX_LABELS = 14
MAP_OVERVIEW_ZOOM = 1.25        -- overview map shows above this zoom
MAP_STAR_HALO_MAX = 7000        -- stars get a glow halo when at most this many are drawn
MAP_LINK_ZOOM = 3.0             -- constellation lines from this zoom
MAP_LINK_MAX_STARS = 4000       -- ... while at most this many stars are drawn
MAP_LINK_CELL = 0.01            -- longest constellation link, in map units
MAP_LINK_BUDGET = 900           -- samples whose links are found per frame
MAP_STAR_DUST_N = 420

MAP_BANDS = {
  { 40, 60, "SUB" }, { 60, 250, "LOW" }, { 250, 500, "LOW MID" }, { 500, 2000, "MID" },
  { 2000, 4000, "HIGH MID" }, { 4000, 8000, "PRESENCE" }, { 8000, 20000, "AIR" },
}
MAP_ZONES = {
  { 0.0, 0.5, "HITS" }, { 0.5, 2.5, "ONE-SHOTS" }, { 2.5, 6.0, "PHRASES" }, { 6.0, nil, "LOOPS & BEDS" },
}

MAP_ATLAS_COL = {
  bg          = 0x06070DFF,     -- gutters and frame fill
  space_mid   = 0x15112BFF,     -- plot centre
  space_edge  = 0x04050CFF,     -- plot corners
  nebula_dim  = 0x3A4280FF,     -- colour of empty nebula cells (alpha 0)
  dust        = 0xC8D2FF00,
  band_fill   = 0xFFFFFF04,
  band_edge   = 0xFFFFFF09,
  guide_text  = 0xB4BEF02E,
  zone_edge   = 0xFFFFFF0E,
  label_count = 0xC4CAF0A0,
  label_shadow = 0x000000B0,
  chip_text   = 0xB9C0E6D8,
  view_box    = 0xFFFFFFD8,
  view_fill   = 0xFFFFFF14,
  overview_bg = 0x05060EF0,
}

map_atlas = {
  key = nil,          -- filter + layout key the finished atlas was built for
  job = nil,          -- build in progress
  ready = false,
  done = {},          -- recent finished atlases { key, res }, newest first
}
MAP_ATLAS_KEEP = 6

local log10 = math.log(10)

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- Tag colour lifted towards white so dark tags (kick purple) stay readable
-- as text and thin lines on the dark canvas.
local function lift(col, t)
  local rr, gg, bb = (col >> 24) & 0xFF, (col >> 16) & 0xFF, (col >> 8) & 0xFF
  rr = math.floor(rr + (255 - rr) * t)
  gg = math.floor(gg + (255 - gg) * t)
  bb = math.floor(bb + (255 - bb) * t)
  return (rr << 24) | (gg << 16) | (bb << 8) | (col & 0xFF)
end

local function with_alpha(col, a)
  a = math.floor(math.max(0, math.min(255, a)) + 0.5)
  return (col & 0xFFFFFF00) | a
end

-- --- Axis bounds (mirrors layout_samples) ---------------------------------------

-- Score ranges layout_samples() normalised against: x = log10 seconds over the
-- whole library (5% padding), y = log10 Hz (or 0..1 weight) over the whole
-- library, no padding, inverted. Mode "other" = the layout fell back to RMS or
-- file size, which has no meaningful axis labels.
function map_axis_bounds()
  local samples = state.samples or {}
  local axis = map_y_axis_id()
  local key = tostring(#samples) .. "|" .. tostring(state.map_layout_version or 0) .. "|" .. axis
  local b = map_atlas.bounds
  if b and b.key == key then
    return b
  end
  local len_min, len_max, y_min, y_max = nil, nil, nil, nil
  for i = 1, #samples do
    local s = samples[i]
    local ls = math.log(math.max(sample_map_duration(s), 0.01)) / log10
    if not len_min or ls < len_min then len_min = ls end
    if not len_max or ls > len_max then len_max = ls end
    local ys
    if axis == "weight" then
      local w = s.sub_weight
      if type(w) ~= "number" then w = 0.0 end
      ys = math.max(0.0, math.min(1.0, w))
    else
      local hz
      if axis == "dominant_freq" then
        hz = s.dominant_freq or 440.0
      else
        hz = s.brightness or s.dominant_freq or 440.0
      end
      ys = math.log(math.max(40.0, math.min(20000.0, hz))) / log10
    end
    if not y_min or ys < y_min then y_min = ys end
    if not y_max or ys > y_max then y_max = ys end
  end
  local mode = axis == "weight" and "weight" or "hz"
  if not y_min or (y_max - y_min) < 0.01 then
    mode = "other"
  end
  b = {
    key = key,
    len_min = len_min or -2.0, len_max = len_max or 1.8,
    y_min = y_min or 0.0, y_max = y_max or 1.0,
    y_mode = mode,
  }
  map_atlas.bounds = b
  return b
end

-- log10 seconds <-> map x (0..1)
function map_x_for_len_score(b, ls)
  local span = b.len_max - b.len_min
  if span < 1e-9 then return 0.5 end
  return 0.05 + (ls - b.len_min) / span * 0.9
end

function map_len_score_for_x(b, nx)
  return b.len_min + (nx - 0.05) / 0.9 * (b.len_max - b.len_min)
end

-- y score (log10 Hz or weight) <-> map y (0..1, top = high)
function map_y_for_score(b, ys)
  local span = b.y_max - b.y_min
  if span < 1e-9 then return 0.5 end
  return 1.0 - (ys - b.y_min) / span
end

function map_score_for_y(b, ny)
  return b.y_min + (1.0 - ny) * (b.y_max - b.y_min)
end

-- --- Screen mapping ------------------------------------------------------------

-- v = { x0, y0, w, h (plot), cx, cy (padded centre), z }
local function sx_of(v, nx) return v.cx + (nx * v.w - v.w * 0.5) * v.z end
local function sy_of(v, ny) return v.cy + (ny * v.h - v.h * 0.5) * v.z end
local function nx_of(v, sx) return (sx - v.cx) / (v.w * v.z) + 0.5 end
local function ny_of(v, sy) return (sy - v.cy) / (v.h * v.z) + 0.5 end

function map_view_frame(padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  return {
    x0 = padded_x0, y0 = padded_y0, w = padded_width, h = padded_height,
    x1 = padded_x0 + padded_width, y1 = padded_y0 + padded_height,
    cx = padded_center_x, cy = padded_center_y, z = state.zoom or 1.0,
  }
end

-- Stars are small when zoomed out (0.5x the dot size) and grow as you zoom
-- in (~1x at 4x, 1.7x at 16x).
function map_dot_zoom_scale()
  local d = map_zoom_depth()
  return 0.5 + 1.1 * d * math.sqrt(d)
end

-- Star brightness: faint when zoomed right out, where the nebula carries
-- the picture, full from about 3x.
function map_star_alpha_scale()
  local d = map_zoom_depth()
  return 0.35 + 0.65 * math.min(1.0, d / 0.4)
end

-- --- Formatting ----------------------------------------------------------------

local function trim_num(fmt, v)
  local s = string.format(fmt, v)
  s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
  return s
end

function map_tick_hz_text(hz)
  if hz >= 1000 then
    return trim_num("%.1f", hz / 1000) .. "k"
  end
  return trim_num("%.0f", hz)
end

function map_tick_seconds_text(sec)
  if sec < 1.0 then
    return trim_num("%.0f", sec * 1000) .. "ms"
  elseif sec < 10.0 then
    return trim_num("%.1f", sec) .. "s"
  elseif sec < 120 then
    return trim_num("%.0f", sec) .. "s"
  end
  return trim_num("%.0f", sec / 60) .. "m"
end

local function count_text(n)
  if n >= 10000 then
    return string.format("%.0fk", n / 1000)
  elseif n >= 1000 then
    return trim_num("%.1f", n / 1000) .. "k"
  end
  return tostring(math.floor(n + 0.5))
end

-- --- Adaptive ticks ------------------------------------------------------------

-- Mantissas per level: 1 = decades, 2 = 2 and 5, 3 = other integers, 4 = halves,
-- 5 = tenths between 1 and 2 (the widest gap on a log scale).
local LOG_MANTISSAS = {
  { 1, 1 }, { 1.1, 5 }, { 1.2, 5 }, { 1.3, 5 }, { 1.4, 5 }, { 1.5, 4 }, { 1.6, 5 }, { 1.7, 5 }, { 1.8, 5 }, { 1.9, 5 },
  { 2, 2 }, { 2.5, 4 }, { 3, 3 }, { 3.5, 4 }, { 4, 3 }, { 4.5, 4 }, { 5, 2 }, { 5.5, 4 },
  { 6, 3 }, { 6.5, 4 }, { 7, 3 }, { 7.5, 4 }, { 8, 3 }, { 8.5, 4 }, { 9, 3 }, { 9.5, 4 },
}

-- Log ticks between lo and hi (log10 values) with ppd pixels per decade.
-- Returns { {score, value, alpha, level}, ... }; finer levels fade in as the
-- decade gets wide enough to hold them.
function map_log_ticks(lo, hi, ppd)
  local fade = {
    1.0,
    clamp01((ppd - 90) / 80),
    clamp01((ppd - 320) / 200),
    clamp01((ppd - 1300) / 600),
    clamp01((ppd - 2600) / 900),
  }
  local out = {}
  if hi < lo then lo, hi = hi, lo end
  for e = math.floor(lo) - 1, math.ceil(hi) do
    for k = 1, #LOG_MANTISSAS do
      local m, level = LOG_MANTISSAS[k][1], LOG_MANTISSAS[k][2]
      local a = fade[level]
      if a > 0 then
        local val = m * 10 ^ e
        local lv = math.log(val) / log10
        if lv >= lo and lv <= hi then
          out[#out + 1] = { lv, val, a, level }
        end
      end
    end
  end
  return out
end

-- Linear ticks (weight axis, 0..1). ppu = pixels per 1.0.
function map_linear_ticks(lo, hi, ppu)
  local steps = { { 0.1, 1, 1.0 }, { 0.05, 2, clamp01((ppu * 0.05 - 18) / 16) }, { 0.01, 3, clamp01((ppu * 0.01 - 14) / 12) } }
  local out, seen = {}, {}
  for _, st in ipairs(steps) do
    local step, level, a = st[1], st[2], st[3]
    if a > 0 then
      for i = math.ceil(math.max(0, lo) / step - 1e-9), math.floor(math.min(1, hi) / step + 1e-9) do
        local v = i * step
        local key = math.floor(v * 1000 + 0.5)
        if not seen[key] then
          seen[key] = true
          out[#out + 1] = { v, v, a, level }
        end
      end
    end
  end
  return out
end

local function grid_line_col(major, a)
  local base = major and 0x1C or 0x0B
  return with_alpha(0x8C9EE600, base * a)
end

local function label_col(level, a)
  if level == 1 then
    return with_alpha(0xB4BCE600, 0xE6 * a)
  end
  return with_alpha(0x7C83A8FF, 0xB8 * a)
end

-- Places labels in priority order (coarse levels first) and skips any that
-- would overlap one already placed. spans: list of {lo, hi}.
local function span_free(spans, lo, hi)
  for i = 1, #spans do
    local s = spans[i]
    if hi > s[1] and lo < s[2] then
      return false
    end
  end
  return true
end

-- --- Background, guides, grid --------------------------------------------------

-- Bands and zones are off by default in the galaxy look (map_bands, not the
-- older map_guides key, so earlier saved settings don't turn them on).
function map_guides_enabled()
  return state.map_bands == true
end

function map_atlas_enabled()
  return state.map_atlas ~= false
end

function map_constellations_enabled()
  return state.map_constellations ~= false
end

function map_overview_enabled()
  return state.map_overview ~= false
end

-- Bands across the plot (Hz axis only) and length zones down it.
function draw_map_guides(dl, v, b)
  if not map_guides_enabled() then
    return
  end
  local C = MAP_ATLAS_COL
  local _, th = r.ImGui_CalcTextSize(ctx, "A")
  if b.y_mode == "hz" then
    for k, band in ipairs(MAP_BANDS) do
      local ya = sy_of(v, map_y_for_score(b, math.log(band[2]) / log10))
      local yb = sy_of(v, map_y_for_score(b, math.log(band[1]) / log10))
      local top, bot = math.max(ya, v.y0), math.min(yb, v.y1)
      if bot > top then
        if k % 2 == 0 then
          r.ImGui_DrawList_AddRectFilled(dl, v.x0, top, v.x1, bot, C.band_fill)
        end
        if ya > v.y0 + 0.5 and ya < v.y1 then
          r.ImGui_DrawList_AddLine(dl, v.x0, ya, v.x1, ya, C.band_edge, 1.0)
        end
        if bot - top > th + 8 then
          r.ImGui_DrawList_AddText(dl, v.x0 + 8, (top + bot - th) * 0.5, C.guide_text, band[3])
        end
      end
    end
  end
  local lmin, lmax = b.len_min, b.len_max
  for _, zone in ipairs(MAP_ZONES) do
    local a = math.max(zone[1], 10 ^ lmin)
    local z1 = zone[2] and math.min(zone[2], 10 ^ lmax) or 10 ^ lmax
    if z1 > a then
      local xa = sx_of(v, map_x_for_len_score(b, math.log(a) / log10))
      local xb = sx_of(v, map_x_for_len_score(b, math.log(z1) / log10))
      if zone[1] > 0 and xa > v.x0 + 1 and xa < v.x1 then
        -- Dashed edge so it reads as a guide, not a grid line
        local y = v.y0
        while y < v.y1 do
          r.ImGui_DrawList_AddLine(dl, xa, y, xa, math.min(v.y1, y + 3), C.zone_edge, 1.0)
          y = y + 7
        end
      end
      local left, right = math.max(xa, v.x0), math.min(xb, v.x1)
      local tw = r.ImGui_CalcTextSize(ctx, zone[3])
      if right - left > tw + 24 then
        r.ImGui_DrawList_AddText(dl, (left + right - tw) * 0.5, v.y0 + 6, C.guide_text, zone[3])
      end
    end
  end
end

-- Grid lines in the plot plus labels in the gutters. Replaces the old ten
-- fixed lines that only stretched when zooming.
function draw_map_adaptive_grid(dl, x0, y0, v, b)
  local C = MAP_CANVAS
  local _, th = r.ImGui_CalcTextSize(ctx, "0")
  local plot_x1, plot_y1 = v.x1, v.y1

  -- Y axis
  local yticks = {}
  local ny_top, ny_bot = ny_of(v, v.y0), ny_of(v, plot_y1)
  if b.y_mode == "hz" then
    local s_hi = math.min(b.y_max, map_score_for_y(b, ny_top))
    local s_lo = math.max(b.y_min, map_score_for_y(b, ny_bot))
    local ppd = v.h * v.z / math.max(1e-6, b.y_max - b.y_min)
    yticks = map_log_ticks(s_lo, s_hi, ppd)
  elseif b.y_mode == "weight" then
    local s_hi = math.min(b.y_max, map_score_for_y(b, ny_top))
    local s_lo = math.max(b.y_min, map_score_for_y(b, ny_bot))
    local ppu = v.h * v.z / math.max(1e-6, b.y_max - b.y_min)
    yticks = map_linear_ticks(s_lo, s_hi, ppu)
  end
  table.sort(yticks, function(a, c) return a[4] < c[4] end)
  local spans = {}
  for i = 1, #yticks do
    local t = yticks[i]
    local py = sy_of(v, map_y_for_score(b, t[1]))
    if py >= v.y0 - 1 and py <= plot_y1 + 1 then
      local major = t[4] == 1
      if py > v.y0 + 0.5 then
        r.ImGui_DrawList_AddLine(dl, v.x0, py, plot_x1, py, grid_line_col(major, t[3]), 1.0)
      end
      r.ImGui_DrawList_AddLine(dl, v.x0 - (major and 5 or 3), py, v.x0 - 1, py, with_alpha(C.tick, 0xFF * t[3]), 1.0)
      local text
      if b.y_mode == "weight" then
        text = string.format("%.0f%%", t[2] * 100)
      else
        text = map_tick_hz_text(t[2])
      end
      local ty = math.max(v.y0 + 1, math.min(plot_y1 - th - 2, py - th * 0.5))
      if t[3] > 0.25 and span_free(spans, ty - 2, ty + th + 2) then
        spans[#spans + 1] = { ty - 2, ty + th + 2 }
        local tw = r.ImGui_CalcTextSize(ctx, text)
        r.ImGui_DrawList_AddText(dl, v.x0 - 9 - tw, ty, label_col(t[4], t[3]), text)
      end
    end
  end

  -- X axis (log seconds)
  local nx_l, nx_r = nx_of(v, v.x0), nx_of(v, plot_x1)
  local l_lo = math.max(b.len_min - 0.05, map_len_score_for_x(b, nx_l))
  local l_hi = math.min(b.len_max + 0.05, map_len_score_for_x(b, nx_r))
  local ppdx = v.w * v.z * 0.9 / math.max(1e-6, b.len_max - b.len_min)
  local xticks = map_log_ticks(l_lo, l_hi, ppdx)
  table.sort(xticks, function(a, c) return a[4] < c[4] end)
  spans = {}
  for i = 1, #xticks do
    local t = xticks[i]
    local px = sx_of(v, map_x_for_len_score(b, t[1]))
    if px >= v.x0 - 1 and px <= plot_x1 + 1 then
      local major = t[4] == 1
      r.ImGui_DrawList_AddLine(dl, px, v.y0, px, plot_y1, grid_line_col(major, t[3]), 1.0)
      r.ImGui_DrawList_AddLine(dl, px, v.y0 - (major and 5 or 3), px, v.y0 - 1, with_alpha(C.tick, 0xFF * t[3]), 1.0)
      local text = map_tick_seconds_text(t[2])
      local tw = r.ImGui_CalcTextSize(ctx, text)
      local tx = math.max(v.x0 + 2, math.min(plot_x1 - tw - 4, px - tw * 0.5))
      if t[3] > 0.25 and span_free(spans, tx - 5, tx + tw + 5) then
        spans[#spans + 1] = { tx - 5, tx + tw + 5 }
        r.ImGui_DrawList_AddText(dl, tx, y0 + (v.y0 - y0 - th) * 0.5 - 1, label_col(t[4], t[3]), text)
      end
    end
  end
end

-- --- Atlas build -----------------------------------------------------------------

-- The tag that gives a sample its dot colour (same rule as get_sample_dot_color).
function map_atlas_tag_of(s)
  local best, best_w = nil, 0
  local tags = s.tags
  if tags then
    for i = 1, #tags do
      local t = tags[i]
      local w = TAG_KEYWORD_WEIGHT[t]
      if w and w > best_w then
        best, best_w = t, w
      end
    end
  end
  if not best and sample_shown_guess_tag then
    best = sample_shown_guess_tag(s)
  end
  if best and state.tag_colors and state.tag_colors[best] then
    return best
  end
  return nil
end

function map_atlas_build_key()
  local b = map_axis_bounds()
  return tostring(map_cache.filter_key) .. "|" .. b.key .. "|" .. tostring(map_cache.filtered_count or 0)
end

local function new_grid(n)
  local g = {}
  for i = 1, n do g[i] = 0 end
  return g
end

-- Starts (or restarts) a build when the filter or layout changed. Called each
-- frame by render_map before drawing.
function map_atlas_update()
  local key = map_atlas_build_key()
  local job = map_atlas.job
  if map_atlas.key == key and (map_atlas.ready or (job and job.key == key)) then
    if job and job.key == key then
      map_atlas_step(job)
    end
    return
  end
  if job and job.key == key then
    map_atlas_step(job)
    return
  end
  -- Built before (a tag turned off again): show it at once, no rebuild.
  local done = map_atlas.done or {}
  for i = 1, #done do
    if done[i].key == key then
      map_atlas.res = done[i].res
      map_atlas.res_key = key
      map_atlas.key = key
      map_atlas.ready = true
      map_atlas.job = nil
      return
    end
  end
  local n = MAP_ATLAS_COLS * MAP_ATLAS_ROWS
  map_atlas.job = {
    key = key,
    list = map_cache.filtered or state.samples or {},
    i = 1,
    phase = "bin",
    tot = new_grid(n),
    rs = new_grid(n), gs = new_grid(n), bs = new_grid(n),
    tags = {},        -- tag -> sparse { [cell] = count }
    tag_total = {},
    link_hash = map_atlas_new_link_hash(),
    finish = nil,
  }
  map_atlas.key = key
  map_atlas.ready = map_atlas.ready and true or false
  map_atlas_step(map_atlas.job)
end

local function blur_grid(src, cols, rows, passes)
  local a = src
  for _ = 1, passes do
    local tmp = {}
    for row = 0, rows - 1 do
      local base = row * cols
      for c = 0, cols - 1 do
        local i = base + c + 1
        local l = c > 0 and a[i - 1] or 0
        local rr = c < cols - 1 and a[i + 1] or 0
        tmp[i] = (l + 2 * a[i] + rr) * 0.25
      end
    end
    local out = {}
    for row = 0, rows - 1 do
      local base = row * cols
      for c = 0, cols - 1 do
        local i = base + c + 1
        local u = row > 0 and tmp[i - cols] or 0
        local d = row < rows - 1 and tmp[i + cols] or 0
        out[i] = (u + 2 * tmp[i] + d) * 0.25
      end
    end
    a = out
  end
  return a
end

-- Summed-area table with a zero row/column: sat[(row)*(cols+1) + c + 1] for
-- row 0..rows, c 0..cols = count in cells [0, c) x [0, row).
local function build_sat(g, cols, rows)
  local w = cols + 1
  local sat = {}
  for c = 0, cols do sat[c + 1] = 0 end
  for row = 1, rows do
    local acc = 0
    sat[row * w + 1] = 0
    for c = 1, cols do
      acc = acc + (g[(row - 1) * cols + c] or 0)
      sat[row * w + c + 1] = sat[(row - 1) * w + c + 1] + acc
    end
  end
  return sat
end

-- Count in the map-space rectangle [nx0, nx1] x [ny0, ny1], interpolated
-- inside cells.
local function sat_lookup(sat, cols, rows, gx, gy)
  local w = cols + 1
  gx = math.max(0, math.min(cols, gx))
  gy = math.max(0, math.min(rows, gy))
  local c0, r0 = math.floor(gx), math.floor(gy)
  local c1, r1 = math.min(cols, c0 + 1), math.min(rows, r0 + 1)
  local fx, fy = gx - c0, gy - r0
  local a = sat[r0 * w + c0 + 1]
  local b = sat[r0 * w + c1 + 1]
  local c = sat[r1 * w + c0 + 1]
  local d = sat[r1 * w + c1 + 1]
  return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
end

function map_atlas_count_in(sat, nx0, ny0, nx1, ny1)
  if not sat then return 0 end
  local cols, rows = MAP_ATLAS_COLS, MAP_ATLAS_ROWS
  local x0, x1 = nx0 * cols, nx1 * cols
  local y0, y1 = ny0 * rows, ny1 * rows
  local v = sat_lookup(sat, cols, rows, x1, y1) - sat_lookup(sat, cols, rows, x0, y1)
    - sat_lookup(sat, cols, rows, x1, y0) + sat_lookup(sat, cols, rows, x0, y0)
  return math.max(0, v)
end

-- Nebula grid: the average dot colour of each cell, blurred wide and close and
-- mixed, so crowded areas glow in their tags' colours. Brightness is measured
-- against the brightest cells (99th percentile), so a whole library and a
-- filtered handful both glow; the very densest cores go towards white.
-- Returns { [cell] = RRGGBBAA } at cell centres.
function map_atlas_build_nebula(job)
  local cols, rows = MAP_ATLAS_COLS, MAP_ATLAS_ROWS
  local n = cols * rows
  local wt = blur_grid(job.tot, cols, rows, 6)
  local mt = blur_grid(job.tot, cols, rows, 2)
  local wr, wg, wb = blur_grid(job.rs, cols, rows, 6), blur_grid(job.gs, cols, rows, 6), blur_grid(job.bs, cols, rows, 6)
  local mr, mg, mb = blur_grid(job.rs, cols, rows, 2), blur_grid(job.gs, cols, rows, 2), blur_grid(job.bs, cols, rows, 2)
  local inten = {}
  local sorted = {}
  for i = 1, n do
    local v = wt[i] * 0.6 + mt[i] * 0.4
    inten[i] = v
    if v > 1e-6 then sorted[#sorted + 1] = v end
  end
  table.sort(sorted)
  local ref = sorted[math.max(1, math.floor(#sorted * 0.99))] or 1
  if ref <= 0 then ref = 1 end
  local dim_r, dim_g, dim_b = (MAP_ATLAS_COL.nebula_dim >> 24) & 0xFF, (MAP_ATLAS_COL.nebula_dim >> 16) & 0xFF, (MAP_ATLAS_COL.nebula_dim >> 8) & 0xFF
  local out = {}
  for i = 1, n do
    local d = wt[i] * 0.6 + mt[i] * 0.4
    local rr, gg, bb = dim_r, dim_g, dim_b
    if d > 1e-6 then
      rr = (wr[i] * 0.6 + mr[i] * 0.4) / d
      gg = (wg[i] * 0.6 + mg[i] * 0.4) / d
      bb = (wb[i] * 0.6 + mb[i] * 0.4) / d
    end
    local t = inten[i] / ref
    local a = 1 - math.exp(-1.5 * t)
    local hot = math.max(0, math.min(1, (t - 0.75) * 0.8))
    rr = rr + (255 - rr) * hot
    gg = gg + (255 - gg) * hot
    bb = bb + (255 - bb) * hot
    local ab = math.floor(math.min(1, a) * 0xA8 + 0.5)
    out[i] = (math.floor(rr) << 24) | (math.floor(gg) << 16) | (math.floor(bb) << 8) | ab
  end
  return out
end

-- Samples by tag and MAP_LINK_CELL-sized map cell (x scaled by the plot's
-- aspect so links are measured as they look on screen). Filled while binning.
function map_atlas_new_link_hash()
  local aspect = (state.map_view_w and state.map_view_h and state.map_view_h > 0)
    and (state.map_view_w / state.map_view_h) or 1.6
  return { aspect = aspect, cell = MAP_LINK_CELL, buckets = {} }
end

function map_atlas_link_hash_add(hash, s, tag)
  local cell = hash.cell
  local key = tag .. ":" .. math.floor(s.x * hash.aspect / cell) .. ":" .. math.floor(s.y / cell)
  local b = hash.buckets[key]
  if not b then
    b = {}
    hash.buckets[key] = b
  end
  b[#b + 1] = s
end

-- The two nearest samples of the same tag within MAP_LINK_CELL (or false).
function map_atlas_links_for(res, s)
  local hash = res.link_hash
  local tag = map_atlas_tag_of(s)
  if not tag or not hash then
    return false
  end
  local aspect, cell = hash.aspect, hash.cell
  local sx, sy = s.x * aspect, s.y
  local gx, gy = math.floor(sx / cell), math.floor(sy / cell)
  local lim = cell * cell
  local b1, d1, b2, d2 = nil, lim, nil, lim
  for cy = gy - 1, gy + 1 do
    for cx = gx - 1, gx + 1 do
      local b = hash.buckets[tag .. ":" .. cx .. ":" .. cy]
      if b then
        for k = 1, #b do
          local o = b[k]
          if o ~= s then
            local dx, dy = o.x * aspect - sx, o.y - sy
            local d = dx * dx + dy * dy
            if d < d1 then
              b2, d2 = b1, d1
              b1, d1 = o, d
            elseif d < d2 then
              b2, d2 = o, d
            end
          end
        end
      end
    end
  end
  if not b1 then
    return false
  end
  return { b1, math.sqrt(d1), b2, b2 and math.sqrt(d2) or nil }
end

-- One build step: bin a slice of samples, then finish one tag per frame.
function map_atlas_step(job)
  local cols, rows = MAP_ATLAS_COLS, MAP_ATLAS_ROWS
  if job.phase == "bin" then
    local list = job.list
    local last = math.min(#list, job.i + MAP_ATLAS_SLICE - 1)
    local floor = math.floor
    local tot, rs, gs, bs = job.tot, job.rs, job.gs, job.bs
    local link_hash = job.link_hash
    for k = job.i, last do
      local s = list[k]
      local x, y = s and s.x, s and s.y
      if x and y and not s._folder_unavailable then
        local c = floor(x * cols)
        if c < 0 then c = 0 elseif c >= cols then c = cols - 1 end
        local row = floor(y * rows)
        if row < 0 then row = 0 elseif row >= rows then row = rows - 1 end
        local cell = row * cols + c + 1
        tot[cell] = tot[cell] + 1
        local col = s._render_color or get_sample_dot_color(s)
        rs[cell] = rs[cell] + ((col >> 24) & 0xFF)
        gs[cell] = gs[cell] + ((col >> 16) & 0xFF)
        bs[cell] = bs[cell] + ((col >> 8) & 0xFF)
        local tag = map_atlas_tag_of(s)
        if tag then
          local g = job.tags[tag]
          if not g then
            g = {}
            job.tags[tag] = g
          end
          g[cell] = (g[cell] or 0) + 1
          job.tag_total[tag] = (job.tag_total[tag] or 0) + 1
          map_atlas_link_hash_add(link_hash, s, tag)
        end
      end
    end
    job.i = last + 1
    if job.i > #list then
      job.phase = "total"
    end
    return
  end

  if job.phase == "total" then
    local res = { tags = {}, tag_order = {} }
    res.total_sat = build_sat(job.tot, cols, rows)
    res.total_count = 0
    for i = 1, #job.tot do res.total_count = res.total_count + job.tot[i] end
    job.res = res
    job.phase = "nebula"
    return
  end

  if job.phase == "nebula" then
    job.res.nebula = map_atlas_build_nebula(job)
    job.phase = "order"
    return
  end

  if job.phase == "order" then
    local res = job.res
    -- Overview: 2x2 blocks with the average dot colour
    local ocols, orows = cols // 2, rows // 2
    local ov = { cols = ocols, rows = orows, cells = {} }
    local omax = 0
    for orow = 0, orows - 1 do
      for oc = 0, ocols - 1 do
        local n, rr, gg, bb = 0, 0, 0, 0
        for dy = 0, 1 do
          for dx = 0, 1 do
            local i = (orow * 2 + dy) * cols + oc * 2 + dx + 1
            n = n + job.tot[i]
            rr, gg, bb = rr + job.rs[i], gg + job.gs[i], bb + job.bs[i]
          end
        end
        if n > 0 then
          ov.cells[#ov.cells + 1] = { oc, orow, n, rr / n, gg / n, bb / n }
          if n > omax then omax = n end
        end
      end
    end
    ov.max = omax
    res.overview = ov
    for tag, total in pairs(job.tag_total) do
      if total >= MAP_ATLAS_MIN_TAG then
        res.tag_order[#res.tag_order + 1] = tag
      end
    end
    table.sort(res.tag_order, function(a, b2)
      local ta, tb = job.tag_total[a], job.tag_total[b2]
      if ta ~= tb then return ta > tb end
      return a < b2
    end)
    job.tag_i = 1
    job.phase = "tags"
    return
  end

  if job.phase == "tags" then
    local res = job.res
    local tag = res.tag_order[job.tag_i]
    if tag then
      local sparse = job.tags[tag]
      local g = new_grid(cols * rows)
      for cell, n in pairs(sparse) do g[cell] = n end
      local f = blur_grid(g, cols, rows, 3)
      local mx, mi = 0, 1
      for i = 1, #f do
        if f[i] > mx then mx, mi = f[i], i end
      end
      local prow, pc = (mi - 1) // cols, (mi - 1) % cols
      res.tags[tag] = {
        tag = tag,
        total = job.tag_total[tag],
        sat = build_sat(g, cols, rows),
        peak_x = (pc + 0.5) / cols,
        peak_y = (prow + 0.5) / rows,
      }
      job.tag_i = job.tag_i + 1
      return
    end
    -- Constellation links are found lazily per visible star, through the
    -- tag/cell index filled while binning.
    res.link_hash = job.link_hash
    res.links = setmetatable({}, { __mode = "k" })
    map_atlas.res = res
    map_atlas.res_key = job.key
    map_atlas.ready = true
    map_atlas.job = nil
    -- Keep the last few finished atlases (newest first) for map_atlas_update.
    local done = map_atlas.done or {}
    for i = #done, 1, -1 do
      if done[i].key == job.key then
        table.remove(done, i)
      end
    end
    table.insert(done, 1, { key = job.key, res = res })
    for i = #done, MAP_ATLAS_KEEP + 1, -1 do
      done[i] = nil
    end
    map_atlas.done = done
  end
end

-- --- Atlas drawing -------------------------------------------------------------

-- Regions and labels belong to one filter; hide them while a new filter's
-- atlas is still being built so they never describe the wrong dots.
function map_atlas_current()
  local res = map_atlas.ready and map_atlas.res
  if res and map_atlas.res_key == map_atlas.key then
    return res
  end
  return nil
end

-- Fixed background stars in a field three times the map's size; they move
-- at sqrt(zoom) so zooming in feels like flying past them.
function map_star_dust()
  local dust = map_atlas.dust
  if dust then
    return dust
  end
  dust = {}
  local seed = 12345
  local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  end
  for i = 1, MAP_STAR_DUST_N do
    local b = rnd()
    dust[i] = { rnd() * 3 - 1, rnd() * 3 - 1, b * b * b }
  end
  map_atlas.dust = dust
  return dust
end

-- Deep-space plot background: vignette, parallax star dust, then the nebula.
function draw_map_galaxy_backdrop(dl, v)
  local C = MAP_ATLAS_COL
  local add_multi = r.ImGui_DrawList_AddRectFilledMultiColor
  local mx, my = (v.x0 + v.x1) * 0.5, v.y0 + (v.y1 - v.y0) * 0.55
  local mid, edge = C.space_mid, C.space_edge
  local side_x = map_lerp_color(edge, mid, 0.45)
  add_multi(dl, v.x0, v.y0, mx, my, edge, side_x, mid, side_x)
  add_multi(dl, mx, v.y0, v.x1, my, side_x, edge, side_x, mid)
  add_multi(dl, mx, my, v.x1, v.y1, mid, side_x, edge, side_x)
  add_multi(dl, v.x0, my, mx, v.y1, side_x, mid, side_x, edge)

  local pz = math.sqrt(v.z)
  local add_rect = r.ImGui_DrawList_AddRectFilled
  local dust = map_star_dust()
  local half_w, half_h = v.w * 0.5, v.h * 0.5
  -- Same parallax centre as the map: the map point at the plot centre.
  local ncx, ncy = nx_of(v, v.x0 + half_w), ny_of(v, v.y0 + half_h)
  for i = 1, #dust do
    local d = dust[i]
    local x = v.x0 + half_w + (d[1] - ncx) * v.w * pz
    local y = v.y0 + half_h + (d[2] - ncy) * v.h * pz
    if x >= v.x0 and x <= v.x1 and y >= v.y0 and y <= v.y1 then
      local sz = 0.8 + d[3] * 1.0
      add_rect(dl, x, y, x + sz, y + sz, with_alpha(C.dust, 0x22 + d[3] * 0x80))
    end
  end

  local res = map_atlas.ready and map_atlas.res
  if res and res.nebula then
    draw_map_nebula(dl, v, res.nebula)
  end
end

-- The nebula grid drawn as smooth quads between cell centres (each corner
-- takes its cell's colour). It fades a little as you zoom in, where the
-- stars carry the picture.
function draw_map_nebula(dl, v, neb)
  local cols, rows = MAP_ATLAS_COLS, MAP_ATLAS_ROWS
  -- Faded colours, cached per (nebula, fade step).
  local fade = 1.0 - 0.5 * math.min(1.0, map_zoom_depth() * 1.2)
  local fq = math.floor(fade * 32 + 0.5)
  local fc = map_atlas.neb_fade
  if not fc or fc.neb ~= neb or fc.q ~= fq then
    fc = { neb = neb, q = fq, cols = {} }
    local f = fq / 32
    for i = 1, #neb do
      local cc = neb[i]
      fc.cols[i] = (cc & 0xFFFFFF00) | math.floor((cc & 0xFF) * f + 0.5)
    end
    map_atlas.neb_fade = fc
  end
  local faded = fc.cols
  local edge_col = MAP_ATLAS_COL.nebula_dim & 0xFFFFFF00
  local cw, ch = v.w * v.z / cols, v.h * v.z / rows
  -- The field is heavily blurred, so when cells are small on screen every
  -- other cell centre is enough (a quarter of the quads).
  local st = (cw < 16 and ch < 16) and 2 or 1
  local add_multi = r.ImGui_DrawList_AddRectFilledMultiColor
  local nx0, nx1 = nx_of(v, v.x0), nx_of(v, v.x1)
  local ny0, ny1 = ny_of(v, v.y0), ny_of(v, v.y1)
  local function snap(i) return i - (i % st) end
  local c0 = snap(math.max(-st, math.floor(nx0 * cols - 0.5)))
  local c1 = math.min(cols - 1, math.floor(nx1 * cols - 0.5) + 1)
  local r0 = snap(math.max(-st, math.floor(ny0 * rows - 0.5)))
  local r1 = math.min(rows - 1, math.floor(ny1 * rows - 0.5) + 1)
  local function col_at(row, c)
    if row < 0 or c < 0 or row >= rows or c >= cols then
      return edge_col
    end
    return faded[row * cols + c + 1]
  end
  local ox = v.cx - v.w * 0.5 * v.z
  local oy = v.cy - v.h * 0.5 * v.z
  local qw, qh = cw * st, ch * st
  for row = r0, r1, st do
    local y0 = oy + (row + 0.5) * ch
    local y1 = y0 + qh
    local tl, bl = col_at(row, c0), col_at(row + st, c0)
    for c = c0, c1, st do
      local tr, br = col_at(row, c + st), col_at(row + st, c + st)
      if ((tl | tr | bl | br) & 0xFF) ~= 0 then
        local x0 = ox + (c + 0.5) * cw
        add_multi(dl, x0, y0, x0 + qw, y1, tl, tr, br, bl)
      end
      tl, bl = tr, br
    end
  end
end

-- Constellation lines between each visible star and its nearest same-tag
-- neighbours, once zoomed in. Links are found lazily (a budget per frame)
-- and kept for the life of the atlas.
function draw_map_constellations(dl, entries, n, dot_radius)
  local res = map_atlas_current()
  if not res or not map_constellations_enabled() or (state.zoom or 1) < MAP_LINK_ZOOM or n > MAP_LINK_MAX_STARS then
    return
  end
  local v = map_atlas.frame_view
  if not v then return end
  local links = res.links
  local budget = MAP_LINK_BUDGET
  local reach = math.min(26 + 4 * v.z, MAP_LINK_CELL * v.h * v.z)
  local add_line = r.ImGui_DrawList_AddLine
  local half_w, half_h = v.w * 0.5, v.h * 0.5
  local fade_in = math.min(1, (v.z - MAP_LINK_ZOOM) / 1.5 + 0.35)
  local tag_col = {}
  for i = 1, n do
    local e = entries[i]
    local s = e.s
    local l = links[s]
    if l == nil and budget > 0 then
      l = map_atlas_links_for(res, s)
      links[s] = l
      budget = budget - 1
    end
    if l then
      for k = 1, 3, 2 do
        local o = l[k]
        if o then
          local ox = v.cx + (o.x * v.w - half_w) * v.z
          local oy = v.cy + (o.y * v.h - half_h) * v.z
          local dx, dy = ox - e.px, oy - e.py
          local d = math.sqrt(dx * dx + dy * dy)
          -- Mutual links are drawn once (from the sample with the lower path).
          local lo = links[o]
          local mutual = lo and (lo[1] == s or lo[3] == s)
          if d < reach and d > dot_radius * 2 and (not mutual or (s.path or "") < (o.path or "")) then
            local tag = map_atlas_tag_of(s)
            local col = tag_col[tag]
            if not col then
              col = lift(build_color_rrgbbaa(extract_rgb(state.tag_colors[tag] or 0x8899CC)), 0.25)
              tag_col[tag] = col
            end
            local a = (1 - d / reach) * 0x70 * fade_in
            -- Stop short of both stars so lines join halos, not cores
            local ux, uy = dx / d, dy / d
            local inset = dot_radius + 1.5
            add_line(dl, e.px + ux * inset, e.py + uy * inset, ox - ux * inset, oy - uy * inset, with_alpha(col, a), 1.0)
          end
        end
      end
    end
  end
end

-- Star colours: dot colours lifted towards white (and the hovered label's
-- tag kept bright while other tags dim). Cached per entry list.
function map_star_colors(cache, n)
  local tag = state.map_atlas_hot_tag
  local aq = math.floor(map_star_alpha_scale() * 16 + 0.5)
  local memo = map_atlas.star_memo
  if memo and memo.tag == tag and memo.gen == cache.entries_gen and memo.n == n and memo.aq == aq then
    return memo.cols
  end
  local af = aq / 16
  local keep = tag and map_atlas_tag_dot_colors(tag) or nil
  local src = cache.draw_col
  local out = {}
  local lifted = {}
  for i = 1, n do
    local c = src[i]
    local l = lifted[c]
    if not l then
      l = lift(c, 0.35)
      l = (l & 0xFFFFFF00) | math.floor((l & 0xFF) * af + 0.5)
      lifted[c] = l
    end
    if keep and not keep[c] then
      l = (l & 0xFFFFFF00) | 0x26
    end
    out[i] = l
  end
  map_atlas.star_memo = { tag = tag, gen = cache.entries_gen, n = n, aq = aq, cols = out }
  return out
end

-- Soft glow behind each star once few enough are drawn.
function draw_map_star_halos(dl, n, pxs, pys, cols, dot_radius)
  if n > MAP_STAR_HALO_MAX or (state.zoom or 1) < 1.5 then
    return
  end
  local add_circle_filled = r.ImGui_DrawList_AddCircleFilled
  local hr = dot_radius * 2.6
  for i = 1, n do
    local c = cols[i]
    if (c & 0xFF) > 0x80 then
      add_circle_filled(dl, pxs[i], pys[i], hr, (c & 0xFFFFFF00) | 0x22, 10)
    end
  end
end

-- Cross-shaped flare on the hovered star.
function draw_map_star_flare(dl, px, py, color, size)
  local col = lift(color, 0.5)
  local add_line = r.ImGui_DrawList_AddLine
  for k = 1, 3 do
    local len = size * (1 - (k - 1) * 0.3)
    local a = 0x30 + (k - 1) * 0x38
    add_line(dl, px - len, py, px + len, py, with_alpha(col, a), 1.0)
    add_line(dl, px, py - len, px, py + len, with_alpha(col, a), 1.0)
  end
  local d = size * 0.4
  add_line(dl, px - d, py - d, px + d, py + d, with_alpha(col, 0x40), 1.0)
  add_line(dl, px - d, py + d, px + d, py - d, with_alpha(col, 0x40), 1.0)
  r.ImGui_DrawList_AddCircleFilled(dl, px, py, size * 0.35, with_alpha(col, 0x30), 16)
end

-- Colours a tag's dots take (stereo and the brighter mono variant).
function map_atlas_tag_dot_colors(tag)
  local base = state.tag_colors and state.tag_colors[tag]
  if not base then return {} end
  local set = {}
  set[get_sample_dot_color({ tags = { tag }, channels = 2 })] = true
  set[get_sample_dot_color({ tags = { tag }, channels = 1 })] = true
  return set
end

-- Plural, upper-case tag names for labels ("KICKS", "808S", "FX").
local LABEL_AS_IS = { fx = true, bass = true, perc = true, keys = true, sfx = true }
function map_label_text(tag)
  tag = tostring(tag)
  if LABEL_AS_IS[tag] or tag:sub(-1) == "s" then
    return string.upper(tag)
  end
  if tag:sub(-1) == "h" then
    return string.upper(tag .. "es")
  end
  return string.upper(tag .. "s")
end
local label_text = map_label_text

-- Letter-spaced, like names on a star chart.
local function spaced(text)
  return (text:gsub("(.)", "%1 "):gsub(" $", ""))
end

-- Star-chart labels over each tag's densest spot, or pinned to the nearest
-- view edge (with an arrow) when that spot is off-screen but some of the tag
-- is in view. Click toggles the tag filter; hover dims the other tags.
function draw_map_atlas_labels(dl, v, hits, keep_clear)
  local res = map_atlas_current()
  state.map_atlas_hot_tag_next = nil
  if not res or not map_atlas_enabled() then
    return
  end
  local nx0, nx1 = clamp01(nx_of(v, v.x0)), clamp01(nx_of(v, v.x1))
  local ny0, ny1 = clamp01(ny_of(v, v.y0)), clamp01(ny_of(v, v.y1))
  local in_view_total = map_atlas_count_in(res.total_sat, nx0, ny0, nx1, ny1)
  local min_count = math.max(12, in_view_total * 0.004)
  local cands = {}
  for _, tag in ipairs(res.tag_order) do
    local t = res.tags[tag]
    if t then
      local cnt = map_atlas_count_in(t.sat, nx0, ny0, nx1, ny1)
      if cnt >= min_count then
        cands[#cands + 1] = { t = t, cnt = cnt }
      end
    end
  end
  table.sort(cands, function(a, b) return a.cnt > b.cnt end)

  local _, th = r.ImGui_CalcTextSize(ctx, "A")
  -- Card: padding, then a colour dot, then the name over the count.
  local pad_x, pad_y, dot_w = 8, 5, 12
  local h = th * 2 + 2 + pad_y * 2
  -- Other controls (edge counts, overview) and the status card / zoom chip
  -- strip along the bottom stay clear of labels.
  local placed = {}
  for i = 1, #(keep_clear or {}) do
    local k = keep_clear[i]
    placed[#placed + 1] = { k[1], k[2], k[3], k[4] }
  end
  placed[#placed + 1] = { v.x0, v.y1 - 40, v.x1, v.y1 }
  local function free(x0, y0, x1, y1)
    for i = 1, #placed do
      local p = placed[i]
      if x1 > p[1] and x0 < p[3] and y1 > p[2] and y0 < p[4] then return false end
    end
    return true
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hot_tag = state.map_atlas_hot_tag
  local shown = 0
  local add_text = r.ImGui_DrawList_AddText
  -- Ticks are drawn first and cards after, so no tick crosses another card.
  local ticks, cards = {}, {}
  for _, cand in ipairs(cands) do
    if shown >= MAP_ATLAS_MAX_LABELS then break end
    local t = cand.t
    local name = spaced(label_text(t.tag))
    local total = t.total
    local cnt = math.floor(cand.cnt + 0.5)
    local sub = (cnt >= total * 0.97) and count_text(total) or (count_text(cnt) .. " of " .. count_text(total))
    local nw = r.ImGui_CalcTextSize(ctx, name)
    local sw = r.ImGui_CalcTextSize(ctx, sub)
    local px, py = sx_of(v, t.peak_x), sy_of(v, t.peak_y)
    local margin = 8
    local pinned = px < v.x0 + 30 or px > v.x1 - 30 or py < v.y0 + 14 or py > v.y1 - 14
    local w = math.max(nw, sw) + pad_x * 2 + dot_w
    -- The label sits above its spot, with a short tick down to it.
    local cx = math.max(v.x0 + w * 0.5 + margin, math.min(v.x1 - w * 0.5 - margin, px))
    local cy = math.max(v.y0 + h * 0.5 + margin + 18, math.min(v.y1 - h * 0.5 - margin, py - h * 0.5 - 8))
    local x0, y0 = cx - w * 0.5, cy - h * 0.5
    local ok = free(x0, y0, x0 + w, y0 + h)
    if not ok then
      for _, dy in ipairs({ -(h + 3), h + 3, -2 * (h + 3), 2 * (h + 3) }) do
        if free(x0, y0 + dy, x0 + w, y0 + dy + h) and y0 + dy > v.y0 + 18 and y0 + dy + h < v.y1 - 4 then
          y0 = y0 + dy
          ok = true
          break
        end
      end
    end
    if ok then
      shown = shown + 1
      placed[#placed + 1] = { x0 - 3, y0 - 3, x0 + w + 3, y0 + h + 4 }
      local base = lift(build_color_rrgbbaa(extract_rgb(state.tag_colors[t.tag] or 0x888888)), 0.5)
      local over = mx >= x0 and mx <= x0 + w and my >= y0 and my <= y0 + h
      local active = state.active_tags and state.active_tags[t.tag]
      local dim = hot_tag and hot_tag ~= t.tag
      local a = dim and 0x50 or ((over or active) and 0xFF or 0xE0)
      local x1, y1 = x0 + w, y0 + h
      local rad = 6
      if not pinned and math.abs(cy - (py - h * 0.5 - 8)) < 1 then
        ticks[#ticks + 1] = { px, y1 + 1, py - 3, with_alpha(base, a * 0.5) }
      end
      cards[#cards + 1] = function()
        -- Drop shadow, dark glassy plate with a faint tint of the tag colour,
        -- a thin coloured border and a soft top highlight.
        r.ImGui_DrawList_AddRectFilled(dl, x0 + 1, y0 + 2, x1 + 1, y1 + 3, with_alpha(0x000000FF, dim and 0x30 or 0x60), rad + 1)
        r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, with_alpha(MAP_ATLAS_COL.space_edge, dim and 0x78 or 0xD0), rad)
        r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, with_alpha(base, (over or active) and 0x2C or (dim and 0x08 or 0x12)), rad)
        r.ImGui_DrawList_AddLine(dl, x0 + rad, y0 + 1, x1 - rad, y0 + 1, with_alpha(0xFFFFFFFF, dim and 0x08 or 0x18), 1.0)
        r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5,
          with_alpha(base, dim and 0x20 or ((over or active) and 0xC0 or 0x50)), rad, 0, (over or active) and 1.5 or 1.0)
        -- Colour dot with a small glow; a ring when this tag is the filter.
        local dx0, dy0 = x0 + pad_x + 3, y0 + h * 0.5
        r.ImGui_DrawList_AddCircleFilled(dl, dx0, dy0, 6.5, with_alpha(base, dim and 0x10 or ((over or active) and 0x50 or 0x28)), 16)
        r.ImGui_DrawList_AddCircleFilled(dl, dx0, dy0, 3.2, with_alpha(base, a), 12)
        if active then
          r.ImGui_DrawList_AddCircle(dl, dx0, dy0, 5.8, with_alpha(base, 0xE0), 16, 1.2)
        end
        local tx = x0 + pad_x + dot_w
        if pinned then
          -- Arrow towards the tag's densest spot
          local ax, ay = x0 - 6, y0 + h * 0.5
          local dx, dy = px - cx, py - cy
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 0 then
            dx, dy = dx / len, dy / len
            r.ImGui_DrawList_AddTriangleFilled(dl,
              ax + dx * 4, ay + dy * 4,
              ax - dx * 3 - dy * 3, ay - dy * 3 + dx * 3,
              ax - dx * 3 + dy * 3, ay - dy * 3 - dx * 3,
              with_alpha(base, a))
          end
        end
        local ny = y0 + pad_y
        add_text(dl, tx + 1, ny + 1, MAP_ATLAS_COL.label_shadow, name)
        add_text(dl, tx, ny, with_alpha(base, a), name)
        add_text(dl, tx + 0.5, ny, with_alpha(base, a), name)
        add_text(dl, tx, ny + th + 2, with_alpha(MAP_ATLAS_COL.label_count, dim and 0x50 or ((over or active) and 0xE0 or 0xA0)), sub)
      end
      hits[#hits + 1] = { x0, y0, x0 + w, y0 + h, kind = "label", tag = t.tag }
      if over then
        state.map_atlas_hot_tag_next = t.tag
      end
    end
  end
  for i = 1, #ticks do
    local k = ticks[i]
    r.ImGui_DrawList_AddLine(dl, k[1], k[2], k[1], k[3], k[4], 1.0)
  end
  for i = 1, #cards do
    cards[i]()
  end
end

-- Off-screen counts on the four edges; click one to pan that way.
function draw_map_edge_counts(dl, v, hits)
  local res = map_atlas.ready and map_atlas.res
  if not res or (state.zoom or 1.0) < 1.05 then
    return
  end
  local nx0, nx1 = nx_of(v, v.x0), nx_of(v, v.x1)
  local ny0, ny1 = ny_of(v, v.y0), ny_of(v, v.y1)
  local sat = res.total_sat
  local left = nx0 > 0 and map_atlas_count_in(sat, 0, 0, clamp01(nx0), 1) or 0
  local right = nx1 < 1 and map_atlas_count_in(sat, clamp01(nx1), 0, 1, 1) or 0
  local up = ny0 > 0 and map_atlas_count_in(sat, 0, 0, 1, clamp01(ny0)) or 0
  local down = ny1 < 1 and map_atlas_count_in(sat, 0, clamp01(ny1), 1, 1) or 0
  local _, th = r.ImGui_CalcTextSize(ctx, "0")
  local h = th + 4
  local mx, my = r.ImGui_GetMousePos(ctx)
  local function pill(n, dir, cx, cy)
    if n < 1 then return end
    local text = count_text(n)
    local tw = r.ImGui_CalcTextSize(ctx, text)
    local w = tw + 20
    local x0 = math.max(v.x0 + 2, math.min(v.x1 - w - 2, cx - w * 0.5))
    local y0 = math.max(v.y0 + 2, math.min(v.y1 - h - 2, cy - h * 0.5))
    local over = mx >= x0 and mx <= x0 + w and my >= y0 and my <= y0 + h
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, over and 0x1B1E3AF0 or 0x07081AC8, h * 0.5)
    r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + w - 0.5, y0 + h - 0.5, over and UI_THEME.accent or 0x2C3256FF, h * 0.5, 0, 1.0)
    local col = over and 0xE6F2EAFF or MAP_ATLAS_COL.chip_text
    local ax, ay = x0 + 8, y0 + h * 0.5
    if dir == "left" then
      r.ImGui_DrawList_AddTriangleFilled(dl, ax - 3, ay, ax + 2, ay - 3, ax + 2, ay + 3, col)
    elseif dir == "right" then
      r.ImGui_DrawList_AddTriangleFilled(dl, ax + 3, ay, ax - 2, ay - 3, ax - 2, ay + 3, col)
    elseif dir == "up" then
      r.ImGui_DrawList_AddTriangleFilled(dl, ax, ay - 3, ax - 3, ay + 2, ax + 3, ay + 2, col)
    else
      r.ImGui_DrawList_AddTriangleFilled(dl, ax, ay + 3, ax - 3, ay - 2, ax + 3, ay - 2, col)
    end
    r.ImGui_DrawList_AddText(dl, x0 + 14, y0 + 2, col, text)
    hits[#hits + 1] = { x0, y0, x0 + w, y0 + h, kind = "edge", dir = dir }
  end
  local mid_x, mid_y = (v.x0 + v.x1) * 0.5, (v.y0 + v.y1) * 0.5
  pill(left, "left", v.x0 + 30, mid_y)
  pill(right, "right", v.x1 - 30, mid_y)
  pill(up, "up", mid_x, v.y0 + h * 0.5 + 4)
  pill(down, "down", mid_x, v.y1 - h * 0.5 - 4)
end

-- Overview of the whole map with the current view boxed; shown once zoomed
-- in. Click or drag inside it to move the view.
function draw_map_overview(dl, v, hits, bottom_reserved)
  local res = map_atlas.ready and map_atlas.res
  if not res or not map_overview_enabled() or (state.zoom or 1.0) < MAP_OVERVIEW_ZOOM then
    state.map_overview_rect = nil
    return
  end
  local ov = res.overview
  local ow = math.min(170, math.max(90, v.w * 0.2))
  local oh = math.max(56, math.min(120, ow * v.h / math.max(1, v.w)))
  local x1 = v.x1 - 10
  local y1 = v.y1 - 10 - (bottom_reserved or 0)
  local x0, y0 = x1 - ow, y1 - oh
  if x0 < v.x0 + 40 or y0 < v.y0 + 30 then
    state.map_overview_rect = nil
    return
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0 - 3, y0 - 3, x1 + 3, y1 + 3, MAP_ATLAS_COL.overview_bg, 6)
  r.ImGui_DrawList_AddRect(dl, x0 - 2.5, y0 - 2.5, x1 + 2.5, y1 + 2.5, 0x2C3256FF, 6, 0, 1.0)
  local cw, ch = ow / ov.cols, oh / ov.rows
  local lm = math.log(1 + (ov.max or 1))
  local add_rect = r.ImGui_DrawList_AddRectFilled
  for i = 1, #ov.cells do
    local c = ov.cells[i]
    local a = lm > 0 and math.log(1 + c[3]) / lm or 0
    local col = (math.floor(c[4]) << 24) | (math.floor(c[5]) << 16) | (math.floor(c[6]) << 8) | math.floor(40 + 200 * a)
    local cx0, cy0 = x0 + c[1] * cw, y0 + c[2] * ch
    add_rect(dl, cx0, cy0, cx0 + cw + 0.25, cy0 + ch + 0.25, col)
  end
  local vx0 = x0 + clamp01(nx_of(v, v.x0)) * ow
  local vx1 = x0 + clamp01(nx_of(v, v.x1)) * ow
  local vy0 = y0 + clamp01(ny_of(v, v.y0)) * oh
  local vy1 = y0 + clamp01(ny_of(v, v.y1)) * oh
  r.ImGui_DrawList_AddRectFilled(dl, vx0, vy0, vx1, vy1, MAP_ATLAS_COL.view_fill)
  r.ImGui_DrawList_AddRect(dl, vx0, vy0, vx1, vy1, MAP_ATLAS_COL.view_box, 0, 0, 1.2)
  state.map_overview_rect = { x0, y0, x1, y1 }
  hits[#hits + 1] = { x0 - 3, y0 - 3, x1 + 3, y1 + 3, kind = "overview" }
end

-- --- Input on the overlays ------------------------------------------------------

local function hit_at(hits, mx, my)
  if not hits then return nil end
  for i = #hits, 1, -1 do
    local h = hits[i]
    if mx >= h[1] and mx <= h[3] and my >= h[2] and my <= h[4] then
      return h
    end
  end
  return nil
end

-- True when the mouse is over one of last frame's overlay controls (labels,
-- edge counts, overview, zoom chip), so the map should not hover or click dots.
function map_overlay_hovered(mx, my)
  if state.map_overview_drag then
    return true
  end
  return hit_at(state.map_overlay_hits, mx, my) ~= nil
end

function map_center_view_on(nx, ny, width, height)
  local pw = width - (MAP_GUTTER_LEFT or 0)
  local ph = height - (MAP_GUTTER_TOP or 0)
  local z = state.zoom or 1.0
  state.pan_x = -(nx - 0.5) * pw * z
  state.pan_y = -(ny - 0.5) * ph * z
  clamp_map_pan(width, height)
  map_zoom_snap_target()
end

-- Handles clicks on last frame's overlay controls. Returns true when it used
-- the mouse this frame.
function handle_map_overlay_input(hovered, mx, my, width, height)
  local hits = state.map_overlay_hits
  if state.map_overview_drag then
    local rc = state.map_overview_rect
    if rc and r.ImGui_IsMouseDown(ctx, 0) then
      map_center_view_on(clamp01((mx - rc[1]) / (rc[3] - rc[1])), clamp01((my - rc[2]) / (rc[4] - rc[2])), width, height)
      return true
    end
    state.map_overview_drag = false
    return true
  end
  if not hovered then
    return false
  end
  local h = hit_at(hits, mx, my)
  if not h then
    return false
  end
  if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
  end
  if h.kind == "zoom" then
    r.ImGui_SetTooltip(ctx, "Click to zoom all the way out")
  end
  if not r.ImGui_IsMouseClicked(ctx, 0) then
    return true
  end
  if h.kind == "label" then
    toggle_sample_map_tag_filter(h.tag)
    state.map_atlas_hot_tag = nil
  elseif h.kind == "edge" then
    local pw = width - (MAP_GUTTER_LEFT or 0)
    local ph = height - (MAP_GUTTER_TOP or 0)
    if h.dir == "left" then state.pan_x = state.pan_x + pw * 0.6
    elseif h.dir == "right" then state.pan_x = state.pan_x - pw * 0.6
    elseif h.dir == "up" then state.pan_y = state.pan_y + ph * 0.6
    else state.pan_y = state.pan_y - ph * 0.6 end
    clamp_map_pan(width, height)
    map_zoom_snap_target()
  elseif h.kind == "overview" then
    state.map_overview_drag = true
    local rc = state.map_overview_rect
    if rc then
      map_center_view_on(clamp01((mx - rc[1]) / (rc[3] - rc[1])), clamp01((my - rc[2]) / (rc[4] - rc[2])), width, height)
    end
  elseif h.kind == "zoom" then
    state.zoom = MAP_ZOOM_MIN or 1.0
    state.pan_x, state.pan_y = 0.0, 0.0
    map_zoom_snap_target()
  end
  return true
end

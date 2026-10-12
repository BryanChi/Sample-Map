-- Sample Map Browser module: map_atlas
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Map atlas: axes, guides, tag regions, overview -----------------------------
-- Everything here is drawn behind or around the dots by render_map():
--   * axis bounds read from the library the same way layout_samples() places
--     dots, so grid labels line up with the dots they describe
--   * an adaptive grid: decades, then 2 / 5, then every step fade in as the
--     zoom gives them room (instead of stretching ten fixed lines)
--   * frequency bands (SUB ... AIR) and length zones (HITS ... LOOPS)
--   * the atlas: a coarse density grid of the filtered samples, built a slice
--     per frame, giving one outlined region and label per colour tag, density
--     contours, the overview map and the off-screen counts
-- The atlas grid is in map space (0..1), so it never rebuilds while panning or
-- zooming; only filter, library or layout changes rebuild it.

MAP_ATLAS_COLS = 96
MAP_ATLAS_ROWS = 64
MAP_ATLAS_SLICE = 6000          -- samples binned per frame while building
MAP_ATLAS_MIN_TAG = 25          -- smallest tag that gets a region
MAP_ATLAS_REGION_LEVEL = 0.30   -- region edge, as a share of the tag's peak density
MAP_ATLAS_MAX_LABELS = 14
MAP_OVERVIEW_ZOOM = 1.25        -- overview map shows above this zoom

MAP_BANDS = {
  { 40, 60, "SUB" }, { 60, 250, "LOW" }, { 250, 500, "LOW MID" }, { 500, 2000, "MID" },
  { 2000, 4000, "HIGH MID" }, { 4000, 8000, "PRESENCE" }, { 8000, 20000, "AIR" },
}
MAP_ZONES = {
  { 0.0, 0.5, "HITS" }, { 0.5, 2.5, "ONE-SHOTS" }, { 2.5, 6.0, "PHRASES" }, { 6.0, nil, "LOOPS & BEDS" },
}

MAP_ATLAS_COL = {
  bg          = 0x0B0F0DFF,
  band_fill   = 0xFFFFFF05,
  band_edge   = 0xFFFFFF0B,
  guide_text  = 0xB4D2C433,
  zone_edge   = 0xFFFFFF10,
  topo        = 0x99E6B300,     -- alpha added per level
  label_bg    = 0x080B09E8,
  label_count = 0xC8D4CCB0,
  chip_bg     = 0x090C0AE0,
  chip_text   = 0xB9C9BFD8,
  view_box    = 0xFFFFFFD8,
  view_fill   = 0xFFFFFF14,
  overview_bg = 0x050706F0,
}

map_atlas = {
  key = nil,          -- filter + layout key the finished atlas was built for
  job = nil,          -- build in progress
  ready = false,
}

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

-- Dots grow a little as you zoom in (1x at the widest view, ~1.25x at 4x,
-- 1.75x at 16x).
function map_dot_zoom_scale()
  local d = map_zoom_depth()
  return 1.0 + 0.75 * d * math.sqrt(d)
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
  local base = major and 0x22 or 0x0E
  return with_alpha(0x8FB39A00, base * a)
end

local function label_col(level, a)
  if level == 1 then
    return with_alpha(0xB4C6BA00, 0xE6 * a)
  end
  return with_alpha(0x7F8B83FF, 0xB8 * a)
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

function map_guides_enabled()
  return state.map_guides ~= false
end

function map_atlas_enabled()
  return state.map_atlas ~= false
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
  if not map_atlas_enabled() and not map_overview_enabled() then
    return
  end
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

-- Marching squares on a grid sampled at cell centres. Returns a flat list of
-- segments in map space {x1, y1, x2, y2, ...}. Outside the grid counts as 0,
-- so regions touching the edge still close.
function map_atlas_contour(f, cols, rows, thr)
  local segs = {}
  local function val(row, c)
    if row < 0 or c < 0 or row >= rows or c >= cols then return 0 end
    return f[row * cols + c + 1]
  end
  local function px(gx) return (gx + 0.5) / cols end
  local function py(gy) return (gy + 0.5) / rows end
  local n = 0
  local function seg(ax, ay, bx, by)
    segs[n + 1], segs[n + 2], segs[n + 3], segs[n + 4] = px(ax), py(ay), px(bx), py(by)
    n = n + 4
  end
  for row = -1, rows - 1 do
    for c = -1, cols - 1 do
      local a = val(row, c)          -- top left
      local b = val(row, c + 1)      -- top right
      local cc = val(row + 1, c + 1) -- bottom right
      local d = val(row + 1, c)      -- bottom left
      local idx = (a >= thr and 8 or 0) + (b >= thr and 4 or 0) + (cc >= thr and 2 or 0) + (d >= thr and 1 or 0)
      if idx ~= 0 and idx ~= 15 then
        local function lerp(v0, v1) local dv = v1 - v0 if dv == 0 then return 0.5 end return (thr - v0) / dv end
        local Tx, Ty = c + lerp(a, b), row
        local Rx, Ry = c + 1, row + lerp(b, cc)
        local Bx, By = c + lerp(d, cc), row + 1
        local Lx, Ly = c, row + lerp(a, d)
        if idx == 1 or idx == 14 then seg(Lx, Ly, Bx, By)
        elseif idx == 2 or idx == 13 then seg(Bx, By, Rx, Ry)
        elseif idx == 3 or idx == 12 then seg(Lx, Ly, Rx, Ry)
        elseif idx == 4 or idx == 11 then seg(Tx, Ty, Rx, Ry)
        elseif idx == 6 or idx == 9 then seg(Tx, Ty, Bx, By)
        elseif idx == 7 or idx == 8 then seg(Tx, Ty, Lx, Ly)
        elseif idx == 5 then seg(Tx, Ty, Rx, Ry) seg(Lx, Ly, Bx, By)
        elseif idx == 10 then seg(Lx, Ly, Tx, Ty) seg(Bx, By, Rx, Ry)
        end
      end
    end
  end
  return segs
end

local function segs_bounds(segs)
  local x0, y0, x1, y1 = 1, 1, 0, 0
  for i = 1, #segs, 2 do
    local x, y = segs[i], segs[i + 1]
    if x < x0 then x0 = x end
    if x > x1 then x1 = x end
    if y < y0 then y0 = y end
    if y > y1 then y1 = y end
  end
  return x0, y0, x1, y1
end

-- Joins contour segments into polylines ({x1, y1, x2, y2, ...} in map space)
-- so drawing can skip points when zoomed out.
function map_atlas_chain(segs)
  local function key(x, y)
    return math.floor(x * 1e6 + 0.5) * 4000000 + math.floor(y * 1e6 + 0.5)
  end
  local n = #segs // 4
  local ends = {}
  for i = 0, n - 1 do
    local b = i * 4
    for e = 0, 1 do
      local k = key(segs[b + 1 + e * 2], segs[b + 2 + e * 2])
      local list = ends[k]
      if not list then
        list = {}
        ends[k] = list
      end
      list[#list + 1] = i
    end
  end
  local used = {}
  local lines = {}
  local function other_end(i, k)
    local b = i * 4
    if key(segs[b + 1], segs[b + 2]) == k then
      return segs[b + 3], segs[b + 4]
    end
    return segs[b + 1], segs[b + 2]
  end
  local function next_seg(k)
    local list = ends[k]
    if not list then return nil end
    for j = 1, #list do
      if not used[list[j]] then return list[j] end
    end
    return nil
  end
  for i = 0, n - 1 do
    if not used[i] then
      used[i] = true
      local b = i * 4
      local pts = { segs[b + 1], segs[b + 2], segs[b + 3], segs[b + 4] }
      -- forward from the second point, then backward from the first
      for dir = 1, 2 do
        while true do
          local lx, ly
          if dir == 1 then lx, ly = pts[#pts - 1], pts[#pts] else lx, ly = pts[1], pts[2] end
          local k = key(lx, ly)
          local j = next_seg(k)
          if not j then break end
          used[j] = true
          local nx, ny = other_end(j, k)
          if dir == 1 then
            pts[#pts + 1], pts[#pts + 2] = nx, ny
          else
            table.insert(pts, 1, ny)
            table.insert(pts, 1, nx)
          end
        end
      end
      lines[#lines + 1] = pts
    end
  end
  return lines
end

-- One build step: bin a slice of samples, then finish one tag per frame.
function map_atlas_step(job)
  local cols, rows = MAP_ATLAS_COLS, MAP_ATLAS_ROWS
  if job.phase == "bin" then
    local list = job.list
    local last = math.min(#list, job.i + MAP_ATLAS_SLICE - 1)
    local floor = math.floor
    local tot, rs, gs, bs = job.tot, job.rs, job.gs, job.bs
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
    -- Density for contours: blurred, log-scaled to 0..1
    local blur = blur_grid(job.tot, cols, rows, 2)
    local mx = 0
    for i = 1, #blur do if blur[i] > mx then mx = blur[i] end end
    local dens = {}
    local lm = math.log(1 + mx)
    for i = 1, #blur do dens[i] = lm > 0 and math.log(1 + blur[i]) / lm or 0 end
    res.topo = {
      coarse = {}, fine = {},
    }
    for _, lv in ipairs({ 0.35, 0.55, 0.75 }) do
      res.topo.coarse[#res.topo.coarse + 1] = { level = lv, lines = map_atlas_chain(map_atlas_contour(dens, cols, rows, lv)) }
    end
    for _, lv in ipairs({ 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85 }) do
      res.topo.fine[#res.topo.fine + 1] = { level = lv, lines = map_atlas_chain(map_atlas_contour(dens, cols, rows, lv)) }
    end
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
    job.res = res
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
      local segs = map_atlas_contour(f, cols, rows, mx * MAP_ATLAS_REGION_LEVEL)
      local bx0, by0, bx1, by1 = segs_bounds(segs)
      local prow, pc = (mi - 1) // cols, (mi - 1) % cols
      res.tags[tag] = {
        tag = tag,
        total = job.tag_total[tag],
        sat = build_sat(g, cols, rows),
        segs = segs,
        lines = map_atlas_chain(segs),
        bounds = { bx0, by0, bx1, by1 },
        peak_x = (pc + 0.5) / cols,
        peak_y = (prow + 0.5) / rows,
      }
      job.tag_i = job.tag_i + 1
      return
    end
    map_atlas.res = res
    map_atlas.res_key = job.key
    map_atlas.ready = true
    map_atlas.job = nil
  end
end

-- --- Atlas drawing -------------------------------------------------------------

-- Draws chained contour lines. Zoomed out, contours are many small steps for
-- a few pixels each, so every other (or every third) point is skipped; the
-- shape stays smooth and it costs a third of the lines.
local function draw_lines(dl, v, lines, col, thick)
  local add_line = r.ImGui_DrawList_AddLine
  local vx0, vy0, vx1, vy1 = v.x0 - 2, v.y0 - 2, v.x1 + 2, v.y1 + 2
  local cell_px = v.w * v.z / MAP_ATLAS_COLS
  local step = cell_px >= 18 and 1 or (cell_px >= 9 and 2 or 3)
  local cx, cy, w, h, z = v.cx, v.cy, v.w, v.h, v.z
  local hw, hh = w * 0.5, h * 0.5
  for li = 1, #lines do
    local pts = lines[li]
    local n = #pts // 2
    local ax = cx + (pts[1] * w - hw) * z
    local ay = cy + (pts[2] * h - hh) * z
    local i = 1 + step
    while true do
      if i > n then
        if i - step < n then i = n else break end
      end
      local bx = cx + (pts[i * 2 - 1] * w - hw) * z
      local by = cy + (pts[i * 2] * h - hh) * z
      if not ((ax < vx0 and bx < vx0) or (ax > vx1 and bx > vx1) or (ay < vy0 and by < vy0) or (ay > vy1 and by > vy1)) then
        add_line(dl, ax, ay, bx, by, col, thick)
      end
      ax, ay = bx, by
      i = i + step
    end
  end
end

-- Density contours, under the dots. They stay while a rebuild runs.
function draw_map_atlas_under(dl, v)
  local res = map_atlas.ready and map_atlas.res
  if not res or not map_atlas_enabled() then
    return
  end
  local levels = v.z > 2.2 and res.topo.fine or res.topo.coarse
  for _, lv in ipairs(levels) do
    local a = 0x0B + lv.level * 0x14
    draw_lines(dl, v, lv.lines, with_alpha(MAP_ATLAS_COL.topo, a), 1.0)
  end
end

-- Regions and labels belong to one filter; hide them while a new filter's
-- atlas is still being built so they never describe the wrong dots.
function map_atlas_current()
  local res = map_atlas.ready and map_atlas.res
  if res and map_atlas.res_key == map_atlas.key then
    return res
  end
  return nil
end

-- One outline per tag region, over the dots so dense areas don't hide it.
function draw_map_atlas_over(dl, v)
  local res = map_atlas_current()
  if not res or not map_atlas_enabled() then
    return
  end
  local hot = state.map_atlas_hot_tag
  for _, tag in ipairs(res.tag_order) do
    local t = res.tags[tag]
    if t and #t.segs > 0 then
      local base = lift(build_color_rrgbbaa(extract_rgb(state.tag_colors[tag] or 0x888888)), 0.3)
      local is_hot = hot == tag
      local a = hot and (is_hot and 0xF0 or 0x22) or 0x8C
      draw_lines(dl, v, t.lines, with_alpha(base, a), is_hot and 2.2 or 1.5)
    end
  end
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

-- Dimmed colour array for the hovered label's tag, cached per entry list.
function map_atlas_hot_colors(cache, n)
  local tag = state.map_atlas_hot_tag
  if not tag then return nil end
  local memo = map_atlas.hot_memo
  if memo and memo.tag == tag and memo.gen == cache.entries_gen and memo.n == n then
    return memo.cols
  end
  local keep = map_atlas_tag_dot_colors(tag)
  local src = cache.draw_col
  local out = {}
  for i = 1, n do
    local c = src[i]
    out[i] = keep[c] and c or ((c & 0xFFFFFF00) | 0x2C)
  end
  map_atlas.hot_memo = { tag = tag, gen = cache.entries_gen, n = n, cols = out }
  return out
end

local function label_text(tag)
  return string.upper(tostring(tag))
end

-- Labels on top of the dots: at each region's peak, or pinned to the nearest
-- view edge (with an arrow) when the peak is off-screen but part of the region
-- is in view. Click toggles the tag filter; hover highlights the region.
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
  local h = th + 6
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
  for _, cand in ipairs(cands) do
    if shown >= MAP_ATLAS_MAX_LABELS then break end
    local t = cand.t
    local name = label_text(t.tag)
    local total = t.total
    local cnt = math.floor(cand.cnt + 0.5)
    local sub = (cnt >= total * 0.97) and count_text(total) or (count_text(cnt) .. " of " .. count_text(total))
    local nw = r.ImGui_CalcTextSize(ctx, name)
    local sw = r.ImGui_CalcTextSize(ctx, sub)
    local px, py = sx_of(v, t.peak_x), sy_of(v, t.peak_y)
    local margin = 8
    local pinned = px < v.x0 + 30 or px > v.x1 - 30 or py < v.y0 + 14 or py > v.y1 - 14
    local arrow_w = pinned and 10 or 0
    local w = nw + sw + 22 + arrow_w
    local cx = math.max(v.x0 + w * 0.5 + margin, math.min(v.x1 - w * 0.5 - margin, px))
    local cy = math.max(v.y0 + h * 0.5 + margin + 18, math.min(v.y1 - h * 0.5 - margin, py))
    local x0, y0 = cx - w * 0.5, cy - h * 0.5
    local ok = free(x0, y0, x0 + w, y0 + h)
    if not ok then
      for _, dy in ipairs({ h + 3, -(h + 3), 2 * (h + 3), -2 * (h + 3) }) do
        if free(x0, y0 + dy, x0 + w, y0 + dy + h) and y0 + dy > v.y0 + 18 and y0 + dy + h < v.y1 - 4 then
          y0 = y0 + dy
          ok = true
          break
        end
      end
    end
    if ok then
      shown = shown + 1
      placed[#placed + 1] = { x0 - 2, y0 - 2, x0 + w + 2, y0 + h + 2 }
      local base = lift(build_color_rrgbbaa(extract_rgb(state.tag_colors[t.tag] or 0x888888)), 0.35)
      local over = mx >= x0 and mx <= x0 + w and my >= y0 and my <= y0 + h
      local active = state.active_tags and state.active_tags[t.tag]
      local dim = hot_tag and hot_tag ~= t.tag
      local bg = MAP_ATLAS_COL.label_bg
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, dim and with_alpha(bg, 0x90) or bg, h * 0.5)
      if over or active then
        r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, with_alpha(base, 0x38), h * 0.5)
      end
      r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + w - 0.5, y0 + h - 0.5,
        with_alpha(base, dim and 0x50 or (over and 0xFF or 0xC8)), h * 0.5, 0, (over or active) and 1.6 or 1.0)
      local tx = x0 + 9
      if pinned then
        -- Arrow towards the region's centre
        local ax, ay = tx + 3, y0 + h * 0.5
        local dx, dy = px - cx, py - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
          dx, dy = dx / len, dy / len
          r.ImGui_DrawList_AddTriangleFilled(dl,
            ax + dx * 4, ay + dy * 4,
            ax - dx * 3 - dy * 3, ay - dy * 3 + dx * 3,
            ax - dx * 3 + dy * 3, ay - dy * 3 - dx * 3,
            with_alpha(base, dim and 0x60 or 0xE0))
        end
        tx = tx + arrow_w
      end
      r.ImGui_DrawList_AddText(dl, tx, y0 + 3, with_alpha(base, dim and 0x70 or 0xFF), name)
      r.ImGui_DrawList_AddText(dl, tx + 0.5, y0 + 3, with_alpha(base, dim and 0x70 or 0xFF), name)
      r.ImGui_DrawList_AddText(dl, tx + nw + 5, y0 + 3, with_alpha(MAP_ATLAS_COL.label_count, dim and 0x60 or 0xB0), sub)
      hits[#hits + 1] = { x0, y0, x0 + w, y0 + h, kind = "label", tag = t.tag }
      if over then
        state.map_atlas_hot_tag_next = t.tag
      end
    end
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
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, over and 0x1B2620F0 or 0x090C0AC8, h * 0.5)
    r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + w - 0.5, y0 + h - 0.5, over and UI_THEME.accent or 0x2C3A31FF, h * 0.5, 0, 1.0)
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
  r.ImGui_DrawList_AddRect(dl, x0 - 2.5, y0 - 2.5, x1 + 2.5, y1 + 2.5, 0x2C3A31FF, 6, 0, 1.0)
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
  if h.kind == "label" then
    r.ImGui_SetTooltip(ctx, "Click to show only " .. label_text(h.tag) .. " (click again to clear)")
  elseif h.kind == "zoom" then
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

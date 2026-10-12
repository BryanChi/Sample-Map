-- Sample Map Browser module: map_render
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function round_to_nice_map_freq(freq)
  if freq < 100.0 then
    return math.floor((freq + 5) / 10) * 10
  elseif freq < 500.0 then
    return math.floor((freq + 10) / 20) * 20
  elseif freq < 1000.0 then
    return math.floor((freq + 20) / 40) * 40
  elseif freq < 5000.0 then
    return math.floor((freq + 50) / 100) * 100
  else
    return math.floor((freq + 100) / 200) * 200
  end
end

-- Map canvas palette: deep-space navy. The axis gutters are a shade darker
-- than the plot and carry the scale labels, so the plot itself stays clean.
MAP_CANVAS = {
  plot_bg      = 0x070A16FF,
  plot_bg_deep = 0x050713FF,
  gutter_bg    = 0x05070FFF,
  gutter_edge  = 0x1A2038FF,
  frame        = 0x1D2440FF,
  glow         = 0x6A7CFF06,
  glow_deep    = 0x9A6CFF0C,
  grid_major   = 0x9FB0E01A,
  grid_minor   = 0x9FB0E00A,
  tick         = 0x5A6280FF,
  label_major  = 0xA4AECED8,
  label_minor  = 0x6E7696B0,
  axis_caption = 0x5A6280FF,
  guide        = 0xE6EAFF30,
  readout_bg   = 0x161C3CF0,
  readout_text = 0xE6EBFFFF,
}
MAP_GUTTER_LEFT = 70
MAP_GUTTER_TOP = 25

function map_format_hz(hz)
  if type(hz) ~= "number" then
    return "?"
  end
  if hz >= 1000.0 then
    return string.format("%.1fkHz", hz / 1000.0)
  end
  return string.format("%.0fHz", hz)
end

function map_format_seconds(sec)
  if type(sec) ~= "number" then
    return "?"
  end
  if sec < 1.0 then
    return string.format("%.0fms", sec * 1000.0)
  elseif sec < 10.0 then
    return string.format("%.2fs", sec)
  end
  return string.format("%.1fs", sec)
end

function map_lerp_color(a, b, t)
  local function ch(c, shift)
    return (c >> shift) & 0xFF
  end
  local out = 0
  for _, shift in ipairs({ 24, 16, 8, 0 }) do
    local v = math.floor(ch(a, shift) + (ch(b, shift) - ch(a, shift)) * t + 0.5)
    out = out | (math.max(0, math.min(255, v)) << shift)
  end
  return out
end

-- 0 at the widest view, 1 at full zoom (log scale, so each doubling of the
-- zoom moves the look by the same amount).
function map_zoom_depth()
  local z = math.max(MAP_ZOOM_MIN or 1.0, state.zoom or 1.0)
  local zmin = MAP_ZOOM_MIN or 1.0
  local zmax = MAP_ZOOM_MAX or 16.0
  if zmax <= zmin then
    return 0.0
  end
  return math.max(0.0, math.min(1.0, math.log(z / zmin) / math.log(zmax / zmin)))
end

-- Rounded canvas fill, drawn before the guides and grid. Flat on purpose:
-- zoom depth is shown by the grid, the overview map and the dot size rather
-- than by tinting the whole canvas.
function draw_map_canvas_backdrop(dl, x0, y0, width, height, padded_x0, padded_y0)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height, MAP_ATLAS_COL and MAP_ATLAS_COL.bg or MAP_CANVAS.plot_bg, UI_METRICS.radius_panel)
end

-- Axis gutters: darker strips on the left (Y scale) and top (X scale), split
-- from the plot by a hairline, with the axis names in the corner.
function draw_map_gutters(dl, x0, y0, width, height, padded_x0, padded_y0)
  local C = MAP_CANVAS
  local rounding = UI_METRICS.radius_panel
  local corner_tl = r.ImGui_DrawFlags_RoundCornersTopLeft and r.ImGui_DrawFlags_RoundCornersTopLeft() or 0
  local corner_bl = r.ImGui_DrawFlags_RoundCornersBottomLeft and r.ImGui_DrawFlags_RoundCornersBottomLeft() or 0
  local corner_tr = r.ImGui_DrawFlags_RoundCornersTopRight and r.ImGui_DrawFlags_RoundCornersTopRight() or 0
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, padded_x0, y0 + height, C.gutter_bg, rounding, corner_tl | corner_bl)
  r.ImGui_DrawList_AddRectFilled(dl, padded_x0, y0, x0 + width, padded_y0, C.gutter_bg, rounding, corner_tr)
  r.ImGui_DrawList_AddLine(dl, padded_x0 - 0.5, padded_y0, padded_x0 - 0.5, y0 + height, C.gutter_edge, 1.0)
  r.ImGui_DrawList_AddLine(dl, padded_x0, padded_y0 - 0.5, x0 + width, padded_y0 - 0.5, C.gutter_edge, 1.0)

  -- Corner: Y axis name over X axis name, each with a small direction arrow.
  local y_name = map_y_axis_id() == "weight" and "Wt" or "Hz"
  local _, th = r.ImGui_CalcTextSize(ctx, "Hz")
  local cx = x0 + 8
  local cy = y0 + (padded_y0 - y0 - th) * 0.5
  local ax = cx + 3
  r.ImGui_DrawList_AddTriangleFilled(dl, ax, cy + 2, ax - 3, cy + 7, ax + 3, cy + 7, C.axis_caption)
  r.ImGui_DrawList_AddText(dl, cx + 9, cy, C.axis_caption, y_name)
  local s_label = "s"
  local sw = select(1, r.ImGui_CalcTextSize(ctx, s_label)) or 6
  local sx = padded_x0 - 8 - sw - 8
  r.ImGui_DrawList_AddText(dl, sx, cy, C.axis_caption, s_label)
  local tx = sx + sw + 3
  local ty = cy + th * 0.5
  r.ImGui_DrawList_AddTriangleFilled(dl, tx + 5, ty, tx, ty - 3, tx, ty + 3, C.axis_caption)
end

function draw_map_grid(dl, x0, y0, width, height, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  draw_map_gutters(dl, x0, y0, width, height, padded_x0, padded_y0)
  if #state.samples > 0 and state.samples[1].x then
    local v = map_view_frame(padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
    local b = map_axis_bounds()
    if r.ImGui_DrawList_PushClipRect then
      r.ImGui_DrawList_PushClipRect(dl, padded_x0, padded_y0, x0 + width, y0 + height, true)
    end
    draw_map_galaxy_backdrop(dl, v)
    draw_map_guides(dl, v, b)
    if r.ImGui_DrawList_PopClipRect then
      r.ImGui_DrawList_PopClipRect(dl)
    end
    draw_map_adaptive_grid(dl, x0, y0, v, b)
  end
end

-- Hovered dot: thin guides out to both gutters, with the dot's own values
-- shown as accent pills in the gutters (read from the sample, not the grid).
function draw_map_hover_guides(dl, sample, px, py, x0, y0, padded_x0, padded_y0, plot_x1, plot_y1)
  if not sample then
    return
  end
  local C = MAP_CANVAS
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, x0, y0, plot_x1, plot_y1, true)
  end
  -- Dotted guides (short dashes) so they read as helpers, not grid lines
  local dash, gap = 3, 3
  local xx = px - 6
  while xx > padded_x0 do
    r.ImGui_DrawList_AddLine(dl, math.max(padded_x0, xx - dash), py, xx, py, C.guide, 1.0)
    xx = xx - dash - gap
  end
  local yy = py - 6
  while yy > padded_y0 do
    r.ImGui_DrawList_AddLine(dl, px, math.max(padded_y0, yy - dash), px, yy, C.guide, 1.0)
    yy = yy - dash - gap
  end

  local y_text
  local axis = map_y_axis_id()
  if axis == "weight" then
    local w = type(sample.sub_weight) == "number" and sample.sub_weight or 0.0
    y_text = string.format("%.0f%%", w * 100.0)
  elseif axis == "dominant_freq" then
    y_text = map_format_hz(sample.dominant_freq)
  else
    y_text = map_format_hz(sample.brightness or sample.dominant_freq)
  end
  local x_text = map_format_seconds(sample_map_duration(sample))

  local function pill(text, cx, cy, align_right)
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    local w, h = tw + 10, th + 4
    local bx0 = align_right and (cx - w) or (cx - w * 0.5)
    local by0 = cy - h * 0.5
    r.ImGui_DrawList_AddRectFilled(dl, bx0, by0, bx0 + w, by0 + h, C.readout_bg, h * 0.5)
    r.ImGui_DrawList_AddRect(dl, bx0 + 0.5, by0 + 0.5, bx0 + w - 0.5, by0 + h - 0.5, UI_THEME.accent, h * 0.5, 0, 1.0)
    r.ImGui_DrawList_AddText(dl, bx0 + 5, by0 + 2, C.readout_text, text)
  end
  local _, th = r.ImGui_CalcTextSize(ctx, "0")
  local pill_cy = math.max(padded_y0 + th * 0.5 + 3, math.min(plot_y1 - th * 0.5 - 3, py))
  pill(y_text, padded_x0 - 4, pill_cy, true)
  local tw = select(1, r.ImGui_CalcTextSize(ctx, x_text)) or 30
  local pill_cx = math.max(padded_x0 + tw * 0.5 + 8, math.min(plot_x1 - tw * 0.5 - 8, px))
  pill(x_text, pill_cx, y0 + (padded_y0 - y0) * 0.5, false)
  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
end

function map_sample_screen_pos(sample, padded_width, padded_height, padded_center_x, padded_center_y, zoom)
  if not sample or not sample.x then
    return nil, nil
  end
  zoom = zoom or state.zoom or 1.0
  local px = padded_center_x + ((sample.x or 0.5) * padded_width - padded_width * 0.5) * zoom
  local py = padded_center_y + ((sample.y or 0.5) * padded_height - padded_height * 0.5) * zoom
  return px, py
end

function map_play_trace_push(sample)
  if not sample or not sample.path or not sample.x then
    return
  end
  local t = state.map_play_trace
  if type(t) ~= "table" then
    t = {}
    state.map_play_trace = t
  end
  if t[#t] and t[#t].path == sample.path then
    return
  end
  for i = #t, 1, -1 do
    if t[i].path == sample.path then
      table.remove(t, i)
    end
  end
  t[#t + 1] = sample
  while #t > MAP_PLAY_TRACE_COUNT do
    table.remove(t, 1)
  end
end

function collect_map_play_trace()
  local t = state.map_play_trace
  if type(t) ~= "table" then
    return {}
  end
  return t
end

function draw_map_play_trace(dl, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  local samples = collect_map_play_trace()
  if #samples < 2 then
    return
  end
  local zoom = state.zoom or 1.0
  local pts = {}
  for i = 1, #samples do
    local px, py = map_sample_screen_pos(
      samples[i], padded_width, padded_height, padded_center_x, padded_center_y, zoom
    )
    if px then
      pts[#pts + 1] = { px = px, py = py, s = samples[i] }
    end
  end
  if #pts < 2 then
    return
  end

  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, padded_x0, padded_y0, padded_x0 + padded_width, padded_y0 + padded_height, true)
  end
  local current_path = preview_sample_obj and preview_sample_obj.path or nil
  local nseg = #pts - 1
  for i = 1, nseg do
    local t = i / nseg
    local alpha = math.floor(28 + t * 70 + 0.5)
    local col = (0xBFD2FF00) | alpha
    r.ImGui_DrawList_AddLine(dl, pts[i].px, pts[i].py, pts[i + 1].px, pts[i + 1].py, col, 1.15)
  end
  for i = 1, #pts do
    local t = (#pts == 1) and 1.0 or ((i - 1) / (#pts - 1))
    local alpha = math.floor(40 + t * 90 + 0.5)
    local r0 = 2.2 + t * 1.4
    local is_current = current_path and pts[i].s.path == current_path
    if not is_current then
      r.ImGui_DrawList_AddCircle(dl, pts[i].px, pts[i].py, r0, (0xBFD2FF00) | alpha, 10, 1.1)
    end
  end
  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
end

-- Closest available dot within snap_r of the mouse; ties go to the lower entry
-- index (the first strictly-closer entry wins, as a linear scan would).
-- Memoized while the mouse and the entry list are unchanged. Once the entry
-- list has been stable for a frame (not panning/zooming), lookups use a
-- screen-space bucket grid with snap_r cells, so only the 3x3 cells around the
-- mouse are tested.
function map_find_hover_entry(cache, entries, mx, my, snap_r)
  local gen = cache.entries_gen or 0
  local memo = cache.hover_memo
  if memo and memo.gen == gen and memo.mx == mx and memo.my == my and memo.snap_r == snap_r then
    return memo.result
  end
  local snap_r_sq = snap_r * snap_r
  local best_i, best_d = nil, nil
  local grid = cache.hover_grid
  local use_grid = grid and grid.gen == gen and grid.cell == snap_r
  if not use_grid and cache.hover_last_gen == gen then
    -- Second frame with the same entries: worth building the grid.
    grid = { gen = gen, cell = snap_r, buckets = {} }
    local buckets = grid.buckets
    local floor = math.floor
    for i = 1, #entries do
      local e = entries[i]
      if not e.unavailable then
        local key = (floor(e.py / snap_r) + 1048576) * 2097152 + (floor(e.px / snap_r) + 1048576)
        local b = buckets[key]
        if b then
          b[#b + 1] = i
        else
          buckets[key] = { i }
        end
      end
    end
    cache.hover_grid = grid
    use_grid = true
  end
  cache.hover_last_gen = gen
  if use_grid then
    local buckets = grid.buckets
    local gx = math.floor(mx / snap_r)
    local gy = math.floor(my / snap_r)
    for cy = gy - 1, gy + 1 do
      for cx = gx - 1, gx + 1 do
        local b = buckets[(cy + 1048576) * 2097152 + (cx + 1048576)]
        if b then
          for k = 1, #b do
            local i = b[k]
            local e = entries[i]
            local dx = mx - e.px
            local dy = my - e.py
            local dist_sq = dx * dx + dy * dy
            if dist_sq <= snap_r_sq and (not best_d or dist_sq < best_d or (dist_sq == best_d and i < best_i)) then
              best_i, best_d = i, dist_sq
            end
          end
        end
      end
    end
  else
    local n = #entries
    local pxs, pys = cache.draw_px, cache.draw_py
    if pxs and cache.draw_arrays_for == entries and cache.draw_arrays_n == n then
      -- Same scan over the flat position arrays; the availability test only
      -- runs for dots within reach.
      for i = 1, n do
        local dx = mx - pxs[i]
        local dy = my - pys[i]
        local dist_sq = dx * dx + dy * dy
        if dist_sq <= snap_r_sq and (not best_d or dist_sq < best_d) and not entries[i].unavailable then
          best_i, best_d = i, dist_sq
        end
      end
    else
      for i = 1, n do
        local e = entries[i]
        if not e.unavailable then
          local dx = mx - e.px
          local dy = my - e.py
          local dist_sq = dx * dx + dy * dy
          if dist_sq <= snap_r_sq and (not best_d or dist_sq < best_d) then
            best_i, best_d = i, dist_sq
          end
        end
      end
    end
  end
  local result = nil
  if best_i then
    local e = entries[best_i]
    result = { sample = e.s, px = e.px, py = e.py, dist_sq = best_d, color = e.color }
  end
  cache.hover_memo = { gen = gen, mx = mx, my = my, snap_r = snap_r, result = result }
  return result
end

-- Hover card header: colour dot + bold name, then a dim facts line
-- (length · brightness · channels).
function draw_map_dot_tooltip_header(s, color)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local name = s.name or "?"
  local nw, nh = r.ImGui_CalcTextSize(ctx, name)
  r.ImGui_DrawList_AddCircleFilled(dl, x + 5, y + nh * 0.5, 4.0, color or UI_THEME.accent, 12)
  r.ImGui_DrawList_AddText(dl, x + 15, y, UI_THEME.text, name)
  r.ImGui_DrawList_AddText(dl, x + 15.5, y, UI_THEME.text, name)
  local facts = { map_format_seconds(sample_map_duration(s)) }
  local hz = s.brightness or s.dominant_freq
  if type(hz) == "number" then
    facts[#facts + 1] = map_format_hz(hz)
  end
  if s.channels == 1 then
    facts[#facts + 1] = "mono"
  elseif type(s.channels) == "number" and s.channels >= 2 then
    facts[#facts + 1] = "stereo"
  end
  local line = table.concat(facts, "  ·  ")
  local lw, lh = r.ImGui_CalcTextSize(ctx, line)
  r.ImGui_DrawList_AddText(dl, x + 15, y + nh + 2, UI_THEME.text_dim, line)
  r.ImGui_Dummy(ctx, math.max(nw, lw) + 16, nh + lh + 2)
end

function render_map_samples(dl, hovered, mx, my, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  local base_dot_radius = state.dot_radius or 2.0
  -- Dots grow a little with zoom so close-ups read as beads, not specks.
  local dot_radius = base_dot_radius * map_dot_zoom_scale()
  local clicked_sample = nil
  local click_handled_this_frame = false

  local hover_color = build_color_rrgbbaa(extract_rgb(state.dot_hover_color or 0xC84D))
  local outline_size = state.dot_outline_size or 4.0

  if #state.samples > 0 and not state.samples[1].x then
    log("WARNING: Samples found but not laid out yet. Count: " .. #state.samples)
    return nil
  end

  local max_radius = math.max(dot_radius * 5.0 + dot_radius * 5.0 * 0.3, dot_radius + outline_size)
  -- render_map computed the filter key this frame; reuse it.
  local frame_filter_key = state._map_frame_filter_key
  state._map_frame_filter_key = nil
  local _, _, cache = ensure_map_render_cache(
    padded_x0, padded_y0, padded_width, padded_height,
    padded_center_x, padded_center_y, max_radius + 8.0, frame_filter_key
  )
  local entries = cache.draw_entries or {}
  local playing_path = preview_sample_obj and preview_sample_obj.path or nil
  local zoom = state.zoom or 1.0
  -- Fewer polygon segments when zoomed out (many dots); smoother when zoomed in
  local segments = (zoom < 1.4) and 6 or 10

  local playing_entry = nil
  local assigned_entries = {}
  local highlight_info = seq_map_highlight_sample_info()
  local add_circle_filled = r.ImGui_DrawList_AddCircleFilled
  -- Keep dots inside the plot so they never spill over the axis gutters.
  local clip_dots = r.ImGui_DrawList_PushClipRect ~= nil
  if clip_dots then
    r.ImGui_DrawList_PushClipRect(dl, padded_x0, padded_y0, padded_x0 + padded_width, padded_y0 + padded_height, true)
  end
  local n_entries = #entries
  local pxs, pys, cols = cache.draw_px, cache.draw_py, cache.draw_col
  -- The flat arrays mirror these entries unless something rebuilt one without
  -- the other; then use the entries directly.
  local flat = pxs ~= nil and cache.draw_arrays_for == entries and cache.draw_arrays_n == n_entries
  if flat then
    -- Dot colours lifted towards white like stars; hovering a label dims
    -- every other tag.
    cols = map_star_colors(cache, n_entries)
    draw_map_star_halos(dl, n_entries, pxs, pys, cols, dot_radius)
  end
  draw_map_constellations(dl, entries, n_entries, dot_radius)
  if flat and not playing_path and next(highlight_info) == nil then
    -- Common case (nothing playing, no hovered track): plain dot loop.
    for i = 1, n_entries do
      add_circle_filled(dl, pxs[i], pys[i], dot_radius, cols[i], segments)
    end
  elseif flat and not cache.draw_dup_paths then
    -- Same result as the scan below: the playing dot is skipped here and drawn
    -- last; highlighted dots are drawn here and again (bigger) afterwards, in
    -- entry order. Paths are unique, so both are found through the index.
    local by_path = cache.draw_index_by_path
    local skip = 0
    if playing_path then
      local pi = by_path[playing_path]
      if pi and not entries[pi].unavailable then
        skip = pi
        playing_entry = entries[pi]
      end
    end
    if next(highlight_info) ~= nil then
      local idxs = {}
      for path, info in pairs(highlight_info) do
        local i = info and by_path[path]
        if i and i ~= skip and not entries[i].unavailable then
          idxs[#idxs + 1] = i
        end
      end
      table.sort(idxs)
      for k = 1, #idxs do
        local e = entries[idxs[k]]
        assigned_entries[k] = { e = e, info = highlight_info[e.s.path] }
      end
    end
    for i = 1, skip - 1 do
      add_circle_filled(dl, pxs[i], pys[i], dot_radius, cols[i], segments)
    end
    for i = skip + 1, n_entries do
      add_circle_filled(dl, pxs[i], pys[i], dot_radius, cols[i], segments)
    end
  elseif not playing_path and next(highlight_info) == nil then
    for i = 1, #entries do
      local e = entries[i]
      add_circle_filled(dl, e.px, e.py, dot_radius, e.color, segments)
    end
  else
    for i = 1, #entries do
      local e = entries[i]
      local s = e.s
      local is_playing = playing_path and s.path == playing_path and not e.unavailable
      local highlighted = highlight_info[s.path]
      if is_playing then
        playing_entry = e
      else
        add_circle_filled(dl, e.px, e.py, dot_radius, e.color, segments)
        if highlighted and not e.unavailable then
          assigned_entries[#assigned_entries + 1] = { e = e, info = highlighted }
        end
      end
    end
  end

  draw_map_play_trace(dl, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)

  -- Samples used by the hovered track: larger fill + ring (idle assigned dots stay normal)
  local assigned_ring = 0xE8F4FFFF
  local selected_ring = 0x4DE8FFFF
  for i = 1, #assigned_entries do
    local item = assigned_entries[i]
    local e = item.e
    local assigned_r = dot_radius * 1.85
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, assigned_r, e.color, 12)
    r.ImGui_DrawList_AddCircle(dl, e.px, e.py, assigned_r + 2.4, assigned_ring, 12, 1.8)
    if item.info.selected then
      r.ImGui_DrawList_AddCircle(dl, e.px, e.py, assigned_r + 5.0, selected_ring, 12, 2.0)
    end
  end

  -- Selected / playing sample drawn last (cheap pulse: 2 rings, not concentric glow stack)
  if playing_entry then
    local e = playing_entry
    local selected_dot_radius = dot_radius * 2
    if not state.breathing_start_time then
      state.breathing_start_time = r.time_precise()
    end
    local elapsed = r.time_precise() - state.breathing_start_time
    local pulse = 0.85 + 0.15 * math.sin((elapsed % 1.5) / 1.5 * 2.0 * math.pi)
    -- Playing star: soft glow in its colour, a bright core, a thin white
    -- ring that breathes, and a small flare.
    local ring_r = math.max(9.0, selected_dot_radius + 5.0) * pulse
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, math.max(18.0, selected_dot_radius * 3.2), (e.color & 0xFFFFFF00) | 0x22, 24)
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, math.max(9.0, selected_dot_radius * 1.9), (e.color & 0xFFFFFF00) | 0x40, 20)
    draw_map_star_flare(dl, e.px, e.py, e.color, math.max(22.0, selected_dot_radius + 16.0))
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, selected_dot_radius, e.color, 16)
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, selected_dot_radius * 0.45, 0xFFFFFFE6, 12)
    local playing_assigned = highlight_info[e.s.path]
    if playing_assigned then
      r.ImGui_DrawList_AddCircle(dl, e.px, e.py, selected_dot_radius + 3.0, assigned_ring, 16, 1.8)
      if playing_assigned.selected then
        r.ImGui_DrawList_AddCircle(dl, e.px, e.py, selected_dot_radius + 6.0, selected_ring, 16, 2.0)
      end
    end
    r.ImGui_DrawList_AddCircle(dl, e.px, e.py, ring_r, 0xFFFFFFC8, 24, 1.5)
    r.ImGui_DrawList_AddCircle(dl, e.px, e.py, ring_r * 1.45, (e.color & 0xFFFFFF00) | math.floor(0x50 * pulse), 24, 1.0)
  end
  if clip_dots then
    r.ImGui_DrawList_PopClipRect(dl)
  end

  local closest = nil
  if hovered then
    local detect = state.dot_detection_multiplier or 16.0
    local snap_r = math.max(MAP_CLICK_SNAP_MIN, base_dot_radius * detect)
    closest = map_find_hover_entry(cache, entries, mx, my, snap_r)
  end

  if closest then
    local s = closest.sample
    local px, py = closest.px, closest.py
    local is_currently_playing = playing_path and playing_path == s.path

    draw_map_hover_guides(
      dl, s, px, py, padded_x0 - MAP_GUTTER_LEFT, padded_y0 - MAP_GUTTER_TOP,
      padded_x0, padded_y0, padded_x0 + padded_width, padded_y0 + padded_height
    )
    -- Wide soft glow in the dot's colour, a bright core, then a crisp ring
    local glow_col = closest.color & 0xFFFFFF00
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, dot_radius + 14.0, glow_col | 0x18, 24)
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, dot_radius + 8.0, glow_col | 0x38, 20)
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, dot_radius + 4.0, glow_col | 0x66, 16)
    if not is_currently_playing then
      r.ImGui_DrawList_AddCircleFilled(dl, px, py, math.max(3.0, dot_radius * 1.7), closest.color | 0xFF, 12)
      r.ImGui_DrawList_AddCircleFilled(dl, px, py, math.max(1.5, dot_radius * 0.75), 0xFFFFFFE0, 10)
    end
    r.ImGui_DrawList_AddCircle(dl, px, py, dot_radius + 4.0, s.hot_color or hover_color, 16, 1.8)
    draw_map_star_flare(dl, px, py, closest.color, dot_radius + 16.0)

    -- Pin to the hovered dot so ImGui nav cannot relocate this tooltip.
    if r.ImGui_SetNextWindowPos then
      local tip_cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
      r.ImGui_SetNextWindowPos(ctx, px + 14, py + 14, tip_cond)
    end
    r.ImGui_BeginTooltip(ctx)
    draw_map_dot_tooltip_header(s, closest.color)
    if s.tags and #s.tags > 0 then
      r.ImGui_Dummy(ctx, 1, 2)
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 3)
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
      local max_row_w = 280
      local row_w = 0
      for idx, tag in ipairs(s.tags) do
        local chip_w = calc_tag_chip_width(tag)
        if idx > 1 then
          local spacing = 4
          if row_w + spacing + chip_w <= max_row_w then
            r.ImGui_SameLine(ctx, 0, spacing)
            row_w = row_w + spacing + chip_w
          else
            row_w = chip_w
          end
        else
          row_w = chip_w
        end
        draw_tag_button(ctx, tag, true, tag, "map_dot_tip_" .. tostring(idx) .. "_")
      end
      r.ImGui_PopStyleVar(ctx, 2)
    end
    local guess = sample_shown_guess_tag(s)
    if guess then
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Sounds like a " .. guess .. " (guessed from the audio)")
    end
    r.ImGui_EndTooltip(ctx)

    if not click_handled_this_frame and r.ImGui_IsMouseClicked(ctx, 0) then
      if is_alt_down() then
        state.pending_waveform_drop = s
        state.is_left_dragging = false
        state.last_dragged_sample_path = nil
        clear_map_left_press()
        click_handled_this_frame = true
      elseif state.seq_swap_track_id then
        local slot = get_active_swap_slot()
        if slot and seq_assign_sample_for_context(slot, s, false) then
          preview_sample(s)
        end
        state.block_swap_bar_input = true
        click_handled_this_frame = true
      else
        clicked_sample = s
        click_handled_this_frame = true
        state.last_dragged_sample_path = s.path
      end
    elseif state.is_left_dragging and not state.pending_waveform_drop and s.path ~= state.last_dragged_sample_path then
      clicked_sample = s
      state.last_dragged_sample_path = s.path
    end
  end

  return clicked_sample
end

function begin_scan_session(kind, stats)
  stats = stats or {}
  state.scan_session = {
    kind = kind or "Scan",
    detail = stats.detail,
    started_at = r.time_precise(),
    elapsed_so_far = 0,
    new_files = stats.new_files or 0,
    changed_files = stats.changed_files or 0,
    incomplete_files = stats.incomplete_files or 0,
    unchanged_files = stats.unchanged_files or 0,
    queued = stats.queued or 0,
    indexed = 0,
    analyzed = 0,
    analyze_errors = 0,
    workers = state.max_concurrent_analyzers or 0,
    cores = state.cpu_core_count or 0,
  }
end

function note_scan_session_analyzer(ok)
  local session = state.scan_session
  if type(session) ~= "table" then
    return
  end
  if ok then
    session.analyzed = (session.analyzed or 0) + 1
  else
    session.analyze_errors = (session.analyze_errors or 0) + 1
  end
end

function scan_session_did_work(session)
  if type(session) ~= "table" then
    return false
  end
  return (session.new_files or 0) > 0
    or (session.changed_files or 0) > 0
    or (session.incomplete_files or 0) > 0
    or (session.queued or 0) > 0
    or (session.indexed or 0) > 0
    or (session.analyzed or 0) > 0
end

function play_scan_complete_sound()
  if SM_IS_WINDOWS then
    -- ExecProcess with -1 returns at once and opens no console window.
    local wav = "C:\\Windows\\Media\\chimes.wav"
    if r.ExecProcess and r.file_exists(wav) then
      pcall(r.ExecProcess, 'powershell -NoProfile -WindowStyle Hidden -Command "(New-Object Media.SoundPlayer \'' .. wav .. '\').PlaySync()"', -1)
    end
    return
  end
  local players = {
    { "afplay", "/System/Library/Sounds/Glass.aiff" },
    { "afplay", "/System/Library/Sounds/Hero.aiff" },
    { "paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga" },
    { "aplay", "/usr/share/sounds/alsa/Front_Center.wav" },
  }
  for i = 1, #players do
    local cmd, sound = players[i][1], players[i][2]
    if r.file_exists(sound) and (cmd == "afplay") == (SM_IS_MAC and true or false) then
      os.execute(cmd .. " " .. shell_escape(sound) .. " >/dev/null 2>&1 &")
      return
    end
  end
end

-- finish_scan_session and the Scan complete window live in 46b_scan_report.lua.

function format_scan_clock(sec)
  if type(sec) ~= "number" or sec < 0 or sec ~= sec then
    return "0 sec"
  end
  if sec == math.huge then
    return "…"
  end
  local s = math.floor(sec + 0.5)
  if s < 60 then
    return string.format("%d sec", s)
  end
  local m = math.floor(s / 60)
  s = s % 60
  if m < 60 then
    if s == 0 then
      return string.format("%d min", m)
    end
    return string.format("%d min %d sec", m, s)
  end
  local h = math.floor(m / 60)
  m = m % 60
  if m == 0 then
    return string.format("%d hr", h)
  end
  return string.format("%d hr %d min", h, m)
end

function update_scan_eta(phase, done, remaining, now)
  local eta = state.scan_eta
  if type(eta) ~= "table" or eta.phase ~= phase then
    eta = {
      phase = phase,
      t0 = now,
      last_done = done,
      last_t = now,
      rate = 0,
      remain = nil,
      marks = {},
    }
    state.scan_eta = eta
  end

  if done > (eta.last_done or 0) then
    local marks = eta.marks or {}
    marks[#marks + 1] = { t = now, done = done }
    eta.marks = marks
    eta.last_done = done
    eta.last_t = now
    local cutoff = now - 12.0
    while #marks > 2 and marks[1].t < cutoff do
      table.remove(marks, 1)
    end
    while #marks > 16 do
      table.remove(marks, 1)
    end
  end

  if remaining <= 0 then
    eta.remain = 0
    return 0
  end

  local phase_elapsed = now - (eta.t0 or now)
  local warmup = phase_elapsed < 1.8 or done < 4
  local recent = 0
  local marks = eta.marks or {}
  if #marks >= 2 then
    local first = marks[1]
    local last = marks[#marks]
    local dt = last.t - first.t
    local dd = last.done - first.done
    if dt > 0.25 and dd > 0 then
      recent = dd / dt
    end
  end

  local overall = 0
  if done >= 2 and phase_elapsed > 0.4 then
    overall = done / phase_elapsed
  end

  local rate = 0
  if warmup then
    rate = recent > 0 and recent or overall
  elseif recent > 0 and overall > 0 then
    rate = recent * 0.6 + overall * 0.4
  else
    rate = recent > 0 and recent or overall
  end

  if rate <= 1e-6 then
    return eta.remain
  end

  local raw = remaining / rate
  if eta.remain then
    eta.remain = eta.remain * 0.72 + raw * 0.28
  else
    eta.remain = raw
  end
  return eta.remain
end

-- "12,345"
function sm_format_count(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- What the running scan is doing, for the progress bars (nil when no scan runs):
-- { phase, label, done, total, fraction, eta, elapsed, detail, indeterminate }.
function sm_compute_scan_progress(now)
  if not state.scan_running then
    return nil
  end
  local session = state.scan_session
  local started = (type(session) == "table" and session.started_at)
    or (state.scan_started and state.scan_started > 0 and state.scan_started) or now
  local elapsed = math.max(0, now - started + ((type(session) == "table" and session.elapsed_so_far) or 0))
  local p = { elapsed = elapsed }
  local enum = state.scan_enum
  if enum then
    p.phase = "list"
    p.label = "Looking for files"
    p.short = "Finding files"
    p.indeterminate = true
    p.detail = string.format("%s folders checked  ·  %s new files found",
      sm_format_count(enum.dirs_done or 0), sm_format_count(#(enum.paths or {})))
    return p
  end
  local remaining
  if #state.scan_queue > 0 then
    local total = math.max(state.scan_total or 0, #state.scan_queue)
    remaining = #state.scan_queue
    p.phase = "index"
    p.label = "Adding new files"
    p.short = "Adding files"
    p.done, p.total = total - remaining, total
  else
    remaining = #state.analyzer_queue + #state.active_processes
    if remaining == 0 then
      p.phase = "finish"
      p.label = "Finishing up"
      p.short = "Finishing"
      p.indeterminate = true
      p.detail = "Saving the library"
      return p
    end
    local done = 0
    if type(session) == "table" then
      done = (session.analyzed or 0) + (session.analyze_errors or 0)
    end
    p.phase = "analyze"
    p.label = (state.analyzer_job_label and state.analyzer_job_label ~= "") and state.analyzer_job_label or "Analyzing sounds"
    p.short = "Analyzing"
    p.done, p.total = done, done + remaining
  end
  p.fraction = p.total > 0 and math.max(0, math.min(1, p.done / p.total)) or 0
  p.eta = update_scan_eta(p.phase, p.done, remaining, now)
  p.detail = string.format("%s of %s files", sm_format_count(p.done), sm_format_count(p.total))
  return p
end

-- Once per frame: the map card and the toolbar bar both read it.
function sm_scan_progress()
  local frame = (ctx and r.ImGui_GetFrameCount and r.ImGui_GetFrameCount(ctx)) or 0
  local c = state._scan_progress_cache
  if c and frame ~= 0 and c.frame == frame then
    return c.p
  end
  local p = sm_compute_scan_progress(r.time_precise())
  state._scan_progress_cache = { frame = frame, p = p }
  return p
end

-- "About 3 min left", "Estimating time left…" or nil.
function sm_scan_eta_text(p)
  if not p or p.indeterminate then
    return nil
  end
  if type(p.eta) == "number" and p.eta > 0.5 then
    return "About " .. format_scan_clock(p.eta) .. " left"
  end
  if (p.done or 0) < 4 and (p.total or 0) > (p.done or 0) then
    return "Estimating time left…"
  end
  return nil
end

-- Slim progress bar; an indeterminate bar shows a sliding segment.
function sm_draw_progress_bar(dl, x0, y0, x1, y1, fraction, indeterminate, track_col, fill_col)
  local h = y1 - y0
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, track_col or 0x1E2621FF, h * 0.5)
  local w = x1 - x0
  if indeterminate then
    local seg = math.max(h * 2, w * 0.28)
    local t = (r.time_precise() * 0.55) % 1.0
    local sx = x0 - seg + (w + seg) * t
    local a, b = math.max(x0, sx), math.min(x1, sx + seg)
    if b - a > 1 then
      r.ImGui_DrawList_AddRectFilled(dl, a, y0, b, y1, fill_col or UI_THEME.accent, h * 0.5)
    end
    return
  end
  local fw = w * math.max(0.0, math.min(1.0, fraction or 0))
  if fw > 1 then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + math.max(fw, h), y1, fill_col or UI_THEME.accent, h * 0.5)
  end
end

-- Hit-tested button drawn over the map (the map's InvisibleButton sits under
-- the card and would steal a normal item click).
local function overlay_button(id, label, x, y, w, h, style, tip)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local over = mx >= x and mx <= (x + w) and my >= y and my <= (y + h)
  if over and r.ImGui_IsWindowHovered then
    local hover_flags = 0
    if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
      hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
    end
    over = r.ImGui_IsWindowHovered(ctx, hover_flags) and true or false
  end
  local clicked = over and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  draw_ui_button(id, label, w, h, { style = style, compact = true })
  if over and tip then
    r.ImGui_SetTooltip(ctx, tip)
  end
  return clicked
end

-- Card across the top of the map while a full-speed scan runs. Hidden while
-- scanning in the background (the toolbar bar still shows progress).
function draw_map_scan_progress_overlay(dl, x0, y0, width, height)
  local p = sm_scan_progress()
  if not p or scan_in_background() then
    return 0
  end

  local overlay_height = 108.0
  local card_margin = 10.0
  local card_x0 = x0 + card_margin
  local card_x1 = x0 + width - card_margin
  local card_y0 = y0 + 6.0
  local card_y1 = y0 + overlay_height - 4.0
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + overlay_height, 0x00000066, UI_METRICS.radius_panel)
  r.ImGui_DrawList_AddRectFilled(dl, card_x0, card_y0, card_x1, card_y1, 0x111612F4, UI_METRICS.radius_panel)
  r.ImGui_DrawList_AddRect(dl, card_x0 + 0.5, card_y0 + 0.5, card_x1 - 0.5, card_y1 - 0.5, UI_THEME.border, UI_METRICS.radius_panel, 0, 1.0)

  local pad = 26.0
  local bar_w = width - pad * 2
  local text_y = y0 + 16.0
  local _, head_h = r.ImGui_CalcTextSize(ctx, p.label)
  local pulse = 0.55 + 0.45 * math.sin(r.time_precise() * 4.0)
  r.ImGui_DrawList_AddCircleFilled(dl, x0 + pad + 3, text_y + head_h * 0.5, 3.5,
    (UI_THEME.accent & 0xFFFFFF00) | math.floor(120 + 135 * pulse), 12)
  r.ImGui_DrawList_AddText(dl, x0 + pad + 12, text_y, UI_THEME.text, p.label)
  r.ImGui_DrawList_AddText(dl, x0 + pad + 12.5, text_y, UI_THEME.text, p.label)
  if not p.indeterminate then
    local pct_text = string.format("%.0f%%", (p.fraction or 0) * 100.0)
    local pct_w = select(1, r.ImGui_CalcTextSize(ctx, pct_text)) or 30
    r.ImGui_DrawList_AddText(dl, x0 + pad + bar_w - pct_w, text_y, UI_THEME.accent, pct_text)
  end

  local bar_y = y0 + 40.0
  sm_draw_progress_bar(dl, x0 + pad, bar_y, x0 + pad + bar_w, bar_y + 6.0, p.fraction, p.indeterminate)

  local row_y = bar_y + 14.0
  local left = (p.detail or "") .. "  ·  " .. format_scan_clock(p.elapsed) .. " elapsed"
  r.ImGui_DrawList_AddText(dl, x0 + pad, row_y, UI_THEME.text_dim, left)
  local eta_text = sm_scan_eta_text(p)
  if eta_text then
    local rw = select(1, r.ImGui_CalcTextSize(ctx, eta_text)) or 0
    r.ImGui_DrawList_AddText(dl, x0 + pad + bar_w - rw, row_y, UI_THEME.text_dim, eta_text)
  end

  local btn_h = 22
  local stop_w, bg_w = 64, 150
  local btn_y = y0 + overlay_height - btn_h - 12.0
  local total_w = stop_w + 8 + bg_w
  local bx = x0 + (width - total_w) * 0.5
  if overlay_button("scan_bg", "Run in background", bx, btn_y, bg_w, btn_h, nil,
      "Keep scanning, slower, so REAPER and the map stay quick to use.\nProgress stays in the toolbar. Library > Scan in Background changes it back.") then
    set_scan_background(true)
  end
  if overlay_button("scan_stop", "Stop", bx + bg_w + 8, btn_y, stop_w, btn_h, "danger",
      "Stop scanning and save progress.\nThe next scan will continue from here — you won't start over.") then
    stop_scan()
  end

  return overlay_height
end

-- Compact progress in the toolbar, shown during every scan in every view:
-- what it's doing, a bar, the time left, and a stop button.
SM_SCAN_CHIP_W = 250

function draw_scan_progress_chip()
  local p = sm_scan_progress()
  if not p then
    return false
  end
  local h = UI_METRICS.toolbar_h
  local w = SM_SCAN_CHIP_W
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##scan_chip", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, hovered and 0x1A221DFF or 0x141A16FF, h * 0.5)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, UI_THEME.border, h * 0.5, 0, 1.0)

  local pulse = 0.55 + 0.45 * math.sin(r.time_precise() * 4.0)
  local _, th = r.ImGui_CalcTextSize(ctx, "Ag")
  local ty = y + (h - th) * 0.5 - 3
  r.ImGui_DrawList_AddCircleFilled(dl, x + 13, ty + th * 0.5, 3.2,
    (UI_THEME.accent & 0xFFFFFF00) | math.floor(120 + 135 * pulse), 12)
  local right
  if p.indeterminate then
    right = ""
  else
    right = string.format("%.0f%%", (p.fraction or 0) * 100)
    if type(p.eta) == "number" and p.eta > 0.5 then
      local sec = math.floor(p.eta + 0.5)
      local clock = sec >= 3600 and string.format("%d:%02d:%02d", sec // 3600, (sec // 60) % 60, sec % 60)
        or string.format("%d:%02d", sec // 60, sec % 60)
      right = right .. "  ·  " .. clock .. " left"
    end
  end
  local label = p.short or p.label
  if scan_in_background() then
    label = label .. " (bg)"
  end
  local rw = right ~= "" and (select(1, r.ImGui_CalcTextSize(ctx, right)) or 0) or 0
  local text_x0, text_x1 = x + 22, x + w - 12
  r.ImGui_DrawList_PushClipRect(dl, text_x0, y, text_x1 - rw - 8, y + h, true)
  r.ImGui_DrawList_AddText(dl, text_x0, ty, UI_THEME.text, label)
  r.ImGui_DrawList_PopClipRect(dl)
  if rw > 0 then
    r.ImGui_DrawList_AddText(dl, text_x1 - rw, ty, UI_THEME.accent, right)
  end
  local bar_y = y + h - 8
  sm_draw_progress_bar(dl, x + 22, bar_y, x + w - 12, bar_y + 3, p.fraction, p.indeterminate)

  if hovered then
    local lines = { p.label }
    if p.detail and p.detail ~= "" then lines[#lines + 1] = p.detail end
    lines[#lines + 1] = format_scan_clock(p.elapsed) .. " elapsed"
    local eta_text = sm_scan_eta_text(p)
    if eta_text then lines[#lines + 1] = eta_text end
    lines[#lines + 1] = ""
    lines[#lines + 1] = scan_in_background()
      and "Scanning in the background (slower). Click for full speed."
      or "Click to keep scanning in the background (slower, REAPER stays quick)."
    r.ImGui_SetTooltip(ctx, table.concat(lines, "\n"))
  end
  if r.ImGui_IsItemClicked(ctx, 0) then
    set_scan_background(not scan_in_background())
  end
  r.ImGui_SameLine(ctx, 0, 4)
  if draw_ui_button("scan_stop_toolbar", "Stop", nil, h, { style = "danger", compact = true }) then
    stop_scan()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Stop scanning and save progress.\nThe next scan will continue from here — you won't start over.")
  end
  return true
end


function render_map()
  local avail_x, avail_y = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(0, avail_x)
  local height = math.max(0, avail_y)
  if width <= 0 or height <= 0 then
    return
  end

  if state.map_restore_view_cx and state.map_restore_view_cy then
    state.pan_x, state.pan_y = map_pan_from_view_center(
      width, height, state.zoom, state.map_restore_view_cx, state.map_restore_view_cy
    )
    state.map_restore_view_cx = nil
    state.map_restore_view_cy = nil
    clamp_map_pan(width, height)
  end
  state.map_view_w = width
  state.map_view_h = height

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)

  r.ImGui_InvisibleButton(ctx, "map_area", width, height)
  if r.ImGui_SetItemAllowOverlap then
    r.ImGui_SetItemAllowOverlap(ctx)
  end
  local hovered = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  -- Previous frame's drawn overlay height (0 when the overlay is hidden).
  local overlay_h = (state.scan_running and not scan_in_background() and (state.map_scan_overlay_h or 108)) or 0
  local over_scan_overlay = overlay_h > 0 and my >= y0 and my <= (y0 + overlay_h)

  -- Region labels, edge counts, the overview map and the zoom chip sit on
  -- the map; clicks on them (last frame's positions) never reach the dots.
  local over_controls = hovered and not over_scan_overlay and map_overlay_hovered(mx, my)
  local used_controls = handle_map_overlay_input(hovered and not over_scan_overlay, mx, my, width, height)
  handle_map_view_input(hovered and not over_scan_overlay, mx, my, width, height, x0, y0)
  if used_controls and r.ImGui_IsMouseClicked(ctx, 0) then
    clear_map_left_press()
  end

  local label_padding_left = MAP_GUTTER_LEFT
  local label_padding_top = MAP_GUTTER_TOP
  local padded_x0 = x0 + label_padding_left
  local padded_y0 = y0 + label_padding_top
  local padded_width = width - label_padding_left
  local padded_height = height - label_padding_top
  local padded_center_x = padded_x0 + padded_width * 0.5 + state.pan_x
  local padded_center_y = padded_y0 + padded_height * 0.5 + state.pan_y

  local map_filter_key = compute_map_filter_key()
  if map_cache.filter_key ~= map_filter_key or not map_cache.spatial then
    rebuild_map_filtered_cache()
  end
  state._map_frame_filter_key = map_filter_key
  map_atlas_update()

  if #state.samples > 0 and state.samples[1].x then
    map_atlas.frame_view = map_view_frame(padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  else
    map_atlas.frame_view = nil
  end
  draw_map_canvas_backdrop(dl, x0, y0, width, height, padded_x0, padded_y0)
  draw_map_grid(dl, x0, y0, width, height, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)

  local clicked_sample = render_map_samples(dl, hovered and not over_scan_overlay and not over_controls, mx, my, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  if clicked_sample and not over_scan_overlay and not sample_scan_folder_unavailable(clicked_sample) then
    local was_drag_audition = state.is_left_dragging
    preview_sample(clicked_sample)
    if not was_drag_audition then
      -- preview_sample can block on a slow disk. Recapture the drag origin on
      -- the next frame so movement during that wait is not treated as a drag.
      state.map_audition_rearm = true
      state.is_left_dragging = false
    end
  end

  if state.pending_waveform_drop then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    update_pending_drop_tracking()
  end

  local hits = {}
  if #state.samples > 0 and state.samples[1].x then
    local v = map_view_frame(padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
    if r.ImGui_DrawList_PushClipRect then
      r.ImGui_DrawList_PushClipRect(dl, padded_x0, padded_y0, x0 + width, y0 + height, true)
    end
    draw_map_edge_counts(dl, v, hits)
    draw_map_overview(dl, v, hits, 30)
    local controls = {}
    for i = 1, #hits do controls[i] = hits[i] end
    draw_map_atlas_labels(dl, v, hits, controls)
    if r.ImGui_DrawList_PopClipRect then
      r.ImGui_DrawList_PopClipRect(dl)
    end
  end
  state.map_atlas_hot_tag = state.map_atlas_hot_tag_next
  state.map_overlay_hits = hits

  state.map_scan_overlay_h = tonumber(draw_map_scan_progress_overlay(dl, x0, y0, width, height)) or 0
  draw_map_status_overlay(dl, x0, y0, width, height)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + width - 0.5, y0 + height - 0.5, MAP_CANVAS.frame, UI_METRICS.radius_panel, 0, 1.0)
end


function render_library_loading_view()
  local job = state.library_load
  local msg = (job and job.message) or "Loading sample library…"
  local progress = (job and job.progress) or 0

  local _, avail_y = r.ImGui_GetContentRegionAvail(ctx)
  local child_flags = 0
  child_flags = sm_child_border_flag()

  local loading_open = r.ImGui_BeginChild(ctx, "library_loading", 0, avail_y, child_flags)
  if loading_open then
    local avail_x, inner_y = r.ImGui_GetContentRegionAvail(ctx)
    local bar_w = math.min(420, math.max(180, avail_x - 80))
    local bar_h = 8
    local text_w = select(1, r.ImGui_CalcTextSize(ctx, msg))
    local block_h = 54
    local start_y = math.max(24, (inner_y - block_h) * 0.35)
    r.ImGui_SetCursorPos(ctx, math.max(20, (avail_x - text_w) * 0.5), start_y)
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, msg)
    r.ImGui_SetCursorPos(ctx, math.max(20, (avail_x - bar_w) * 0.5), start_y + 28)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    ui_draw_panel(dl, bx, by, bx + bar_w, by + bar_h, 4.0, UI_THEME.surface, UI_THEME.border, false, false)
    local fill_w = math.max(0, math.min(bar_w, bar_w * progress))
    if fill_w > 2 then
      r.ImGui_DrawList_AddRectFilled(dl, bx + 1, by + 1, bx + fill_w - 1, by + bar_h - 1, UI_THEME.accent, 3.0)
    end
    r.ImGui_Dummy(ctx, bar_w, bar_h)
    local pct = string.format("%d%%", math.floor(math.max(0, math.min(1, progress)) * 100 + 0.5))
    local pct_h = select(2, r.ImGui_CalcTextSize(ctx, pct))
    r.ImGui_DrawList_AddText(dl, bx + bar_w + 10, by + (bar_h - pct_h) * 0.5, UI_THEME.text_mute, pct)
    local sub = "Preparing the map — first run builds a faster cache for next launch"
    local sub_w = select(1, r.ImGui_CalcTextSize(ctx, sub))
    r.ImGui_SetCursorPos(ctx, math.max(20, (avail_x - sub_w) * 0.5), start_y + 48)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, sub)
  end
  imgui_end_child(loading_open)
end


function shutdown_script(reason)
  if SampleMapInstance.shutdown_done then
    return
  end
  SampleMapInstance.shutdown_done = true
  running = false
  pcall(function()
    -- Only clear the key while it still holds this instance's token; a newer
    -- instance may already have claimed it.
    local cur = r.GetExtState(SampleMapInstance.section, SampleMapInstance.key)
    if SampleMapInstance.token and cur == SampleMapInstance.token then
      r.DeleteExtState(SampleMapInstance.section, SampleMapInstance.key, false)
    end
  end)

  pcall(stop_preview)
  pcall(seq_midi_stop_all_voices)
  pcall(remove_provisional_drop)
  pcall(clear_drag_tooltip)

  pcall(stop_analyzer_workers, true)

  if #state.samples > 0 or #state.scan_queue > 0 or #(state.analyzer_queue or {}) > 0 then
    pcall(save_samples)
    log(string.format(
      "Saved library on exit (%s): %d sample(s), %d file(s) still queued",
      reason or "close",
      #state.samples,
      #state.scan_queue
    ))
  end

  if ctx and r.ImGui_ValidatePtr and r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    if r.APIExists("ImGui_DestroyContext") then
      pcall(r.ImGui_DestroyContext, ctx)
    end
  end
  ctx = nil
  pcall(seq_destroy_arrange_overlay_ctx)
  pcall(save_config_now)
end

-- After a UI error left the ImGui stack unbalanced, ReaImGui may invalidate
-- the context. Recreate it (at most 3 times per 30 s) instead of quitting.
function sm_imgui_try_recover_context()
  if not state.sm_imgui_recover_pending then
    return false
  end
  state.sm_imgui_recover_pending = false
  local now = r.time_precise()
  local recent = {}
  for _, t in ipairs(state.sm_imgui_recreate_times or {}) do
    if now - t < 30.0 then
      recent[#recent + 1] = t
    end
  end
  state.sm_imgui_recreate_times = recent
  if #recent >= 3 then
    return false
  end
  local ok_new, new_ctx = pcall(r.ImGui_CreateContext, SCRIPT_NAME, r.ImGui_ConfigFlags_DockingEnable())
  if not ok_new or not new_ctx then
    return false
  end
  recent[#recent + 1] = now
  ctx = new_ctx
  font = nil
  local ok_font, new_font = pcall(r.ImGui_CreateFont, "sans-serif", 16)
  if ok_font and new_font then
    font = new_font
    pcall(r.ImGui_Attach, ctx, font)
  end
  pcall(ensure_seq_role_icons)
  pcall(ensure_vfx_icons)
  log("ImGui context recreated after an error")
  return true
end

-- Sample Map Browser module: map_index
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Map spatial index + cached draw lists -----------------------------------
-- map_base_cache: text + folder filters only (no tags). Clearing tags restores
-- from this instead of rescanning the whole library.
map_cache = {
  filter_key = nil,
  spatial = nil,
  filtered = nil,
  filtered_count = 0,
  view_key = nil,
  draw_list = nil,
  hover_list = nil,
  visible_total = 0,
  draw_count = 0,
  dots_capped = false,
}

map_base_cache = {
  key = nil,
  spatial = nil,
  filtered = nil,
  filtered_set = nil,
  filtered_count = 0,
  duration_min = nil,
  duration_max = nil,
}

function invalidate_sample_render_colors(tag)
  if tag then
    local list = state.samples_by_tag and state.samples_by_tag[tag]
    if list then
      for i = 1, #list do
        list[i]._render_color = nil
      end
    else
      for _, s in ipairs(state.samples or {}) do
        s._render_color = nil
      end
    end
  else
    for _, s in ipairs(state.samples or {}) do
      s._render_color = nil
    end
  end
  map_cache.view_key = nil
  map_cache.draw_list = nil
  map_cache.draw_entries = nil
end

function compute_map_base_filter_key()
  return string.format(
    "%s|%s|%d|%d|%d|%d",
    state.filter or "",
    folder_filter_key(),
    #state.samples,
    state.map_layout_version or 0,
    state.map_availability_epoch or 0,
    state.tag_index_epoch or 0
  )
end

function compute_map_filter_key()
  local tags = {}
  for tag, active in pairs(state.active_tags or {}) do
    if active then
      tags[#tags + 1] = tag
    end
  end
  table.sort(tags)
  return string.format(
    "%s|%s|%s|%d|%d|%d|%d",
    state.filter or "",
    table.concat(tags, ","),
    folder_filter_key(),
    #state.samples,
    state.map_layout_version or 0,
    state.map_availability_epoch or 0,
    state.tag_index_epoch or 0
  )
end

function compute_map_view_key(padded_x0, padded_y0, padded_width, padded_height)
  local playing_path = preview_sample_obj and preview_sample_obj.path or ""
  -- High zoom precision so trackpad deltas update positions every frame
  return string.format(
    "%.5f|%.1f|%.1f|%d|%d|%d|%d|%s|%s",
    state.zoom or 1.0,
    state.pan_x or 0.0,
    state.pan_y or 0.0,
    math.floor(padded_width or 0),
    math.floor(padded_height or 0),
    math.floor(padded_x0 or 0),
    math.floor(padded_y0 or 0),
    playing_path,
    seq_assigned_view_fingerprint()
  )
end

function map_spatial_cell_key(cell_x, cell_y)
  return cell_y * MAP_GRID_RES + cell_x
end

function build_map_spatial(filtered)
  local spatial = {}
  for i = 1, #filtered do
    local s = filtered[i]
    local cell_x = math.max(0, math.min(MAP_GRID_RES - 1, math.floor((s.x or 0.5) * MAP_GRID_RES)))
    local cell_y = math.max(0, math.min(MAP_GRID_RES - 1, math.floor((s.y or 0.5) * MAP_GRID_RES)))
    local key = map_spatial_cell_key(cell_x, cell_y)
    local bucket = spatial[key]
    if not bucket then
      bucket = {}
      spatial[key] = bucket
    end
    bucket[#bucket + 1] = s
  end
  return spatial
end

function map_duration_bounds(filtered)
  local duration_min, duration_max = nil, nil
  for i = 1, #filtered do
    local map_dur = sample_map_duration(filtered[i])
    if map_dur > 0 then
      if not duration_min then
        duration_min = map_dur
        duration_max = map_dur
      else
        duration_min = math.min(duration_min, map_dur)
        duration_max = math.max(duration_max, map_dur)
      end
    end
  end
  return duration_min, duration_max
end

function rebuild_map_base_cache()
  local filtered = {}
  local filtered_set = {}
  local needle = (state.filter ~= "" and string.lower(state.filter)) or ""
  local samples = state.samples or {}
  for i = 1, #samples do
    local s = samples[i]
    -- skip_tags: base cache ignores active tag filters
    if type(s) == "table" and s.x and sample_passes_filters(s, needle, true) then
      if not s._render_color then
        s._render_color = get_sample_dot_color(s)
      end
      s._folder_unavailable = sample_scan_folder_unavailable(s)
      filtered[#filtered + 1] = s
      filtered_set[s] = true
    end
  end

  map_base_cache.filtered = filtered
  map_base_cache.filtered_set = filtered_set
  map_base_cache.filtered_count = #filtered
  map_base_cache.spatial = build_map_spatial(filtered)
  map_base_cache.duration_min, map_base_cache.duration_max = map_duration_bounds(filtered)
  map_base_cache.key = compute_map_base_filter_key()
end

function ensure_map_base_cache()
  local key = compute_map_base_filter_key()
  if map_base_cache.key ~= key or not map_base_cache.filtered then
    rebuild_map_base_cache()
  end
end

function collect_tag_filter_candidates()
  local active = state.active_tags
  if not active or next(active) == nil then
    return nil, false
  end
  local by_tag = state.samples_by_tag
  if not by_tag then
    return nil, false
  end
  local seen, out = {}, {}
  for tag, on in pairs(active) do
    if on then
      local list = by_tag[tag]
      if list then
        for i = 1, #list do
          local s = list[i]
          if not seen[s] then
            seen[s] = true
            out[#out + 1] = s
          end
        end
      end
    end
  end
  return out, true
end

function rebuild_map_filtered_cache()
  ensure_map_base_cache()
  local filter_key = compute_map_filter_key()
  local candidates, has_tags = collect_tag_filter_candidates()

  if not has_tags then
    -- Clearing tags: reuse the base scan (no full-library walk)
    map_cache.filtered = map_base_cache.filtered
    map_cache.filtered_count = map_base_cache.filtered_count
    map_cache.spatial = map_base_cache.spatial
    map_cache.duration_min = map_base_cache.duration_min
    map_cache.duration_max = map_base_cache.duration_max
    map_cache.filter_key = filter_key
    map_cache.view_key = nil
    map_cache.lod_key = nil
    map_cache.draw_list = nil
    map_cache.draw_entries = nil
    map_cache.draw_path_set = nil
    return
  end

  local base_set = map_base_cache.filtered_set or {}
  local filtered = {}
  for i = 1, #candidates do
    local s = candidates[i]
    if base_set[s] then
      if not s._render_color then
        s._render_color = get_sample_dot_color(s)
      end
      filtered[#filtered + 1] = s
    end
  end

  map_cache.filtered = filtered
  map_cache.filtered_count = #filtered
  map_cache.spatial = build_map_spatial(filtered)
  map_cache.duration_min, map_cache.duration_max = map_duration_bounds(filtered)
  map_cache.filter_key = filter_key
  map_cache.view_key = nil
  map_cache.lod_key = nil
  map_cache.draw_list = nil
  map_cache.draw_entries = nil
  map_cache.draw_path_set = nil
end

function preview_random_filtered_sample()
  if map_cache.filter_key ~= compute_map_filter_key() or not map_cache.filtered then
    rebuild_map_filtered_cache()
  end
  local filtered = map_cache.filtered
  if not filtered or #filtered == 0 then
    return
  end

  local current_path = preview_sample_obj and preview_sample_obj.path
  local pool = {}
  for i = 1, #filtered do
    local s = filtered[i]
    if s and s.path and not sample_scan_folder_unavailable(s) and s.path ~= current_path then
      pool[#pool + 1] = s
    end
  end
  if #pool == 0 then
    for i = 1, #filtered do
      local s = filtered[i]
      if s and s.path and not sample_scan_folder_unavailable(s) then
        pool[#pool + 1] = s
      end
    end
  end
  if #pool == 0 then
    return
  end

  local pick = pool[math.random(1, #pool)]
  if pick then
    preview_sample(pick)
  end
end

function get_viewport_norm_bounds(padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y, margin)
  local zoom = state.zoom or 1.0
  local inv_x = 1.0 / math.max(padded_width * zoom, 1e-6)
  local inv_y = 1.0 / math.max(padded_height * zoom, 1e-6)
  local x_min = ((padded_x0 - margin - padded_center_x) * inv_x) + 0.5
  local x_max = ((padded_x0 + padded_width + margin - padded_center_x) * inv_x) + 0.5
  local y_min = ((padded_y0 - margin - padded_center_y) * inv_y) + 0.5
  local y_max = ((padded_y0 + padded_height + margin - padded_center_y) * inv_y) + 0.5
  return x_min, x_max, y_min, y_max
end

function collect_viewport_samples(spatial, x_min, x_max, y_min, y_max)
  local seen = {}
  local out = {}
  local cx0 = math.max(0, math.floor(x_min * MAP_GRID_RES) - 1)
  local cx1 = math.min(MAP_GRID_RES - 1, math.floor(x_max * MAP_GRID_RES) + 1)
  local cy0 = math.max(0, math.floor(y_min * MAP_GRID_RES) - 1)
  local cy1 = math.min(MAP_GRID_RES - 1, math.floor(y_max * MAP_GRID_RES) + 1)

  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      local bucket = spatial[map_spatial_cell_key(cx, cy)]
      if bucket then
        for _, s in ipairs(bucket) do
          local path = s.path
          local sx, sy = s.x or 0.5, s.y or 0.5
          if path and not seen[path] and sx >= x_min and sx <= x_max and sy >= y_min and sy <= y_max then
            seen[path] = true
            out[#out + 1] = s
          end
        end
      end
    end
  end

  return out
end

function sample_lod_rank(sample)
  local rank = sample and sample._lod_rank
  if rank then
    return rank
  end
  local path = sample and sample.path or ""
  local h = 2166136261
  for i = 1, #path do
    h = (h * 16777619 + path:byte(i)) % 2147483647
  end
  rank = h
  if sample then
    sample._lod_rank = rank
  end
  return rank
end

function apply_map_dot_cap(candidates, max_dots, playing_path, x_min, x_max, y_min, y_max, prefer_set)
  if #candidates <= max_dots then
    return candidates, #candidates, false
  end

  -- Viewport-relative grid: ~sqrt(budget)² cells across the visible area.
  -- Stable hash picks the cell winner; prefer_set keeps prior dots from popping.
  local vw = math.max(1e-6, (x_max or 1) - (x_min or 0))
  local vh = math.max(1e-6, (y_max or 1) - (y_min or 0))
  local subgrid = math.max(8, math.floor(math.sqrt(max_dots) + 0.5))
  local x0 = x_min or 0
  local y0 = y_min or 0
  local cells = {}
  local cell_rank = {}
  local playing = nil
  prefer_set = prefer_set or {}

  for i = 1, #candidates do
    local s = candidates[i]
    if playing_path and s.path == playing_path then
      playing = s
    else
      local gx = math.max(0, math.min(subgrid - 1, math.floor(((s.x or 0.5) - x0) / vw * subgrid)))
      local gy = math.max(0, math.min(subgrid - 1, math.floor(((s.y or 0.5) - y0) / vh * subgrid)))
      local key = gy * subgrid + gx
      local rank = sample_lod_rank(s)
      if prefer_set[s.path] then
        -- Mild bias keeps prior dots from thrashing without blocking new cells
        rank = rank - 200000000
      end
      local best = cell_rank[key]
      if not best or rank < best then
        cells[key] = s
        cell_rank[key] = rank
      end
    end
  end

  local draw_list = {}
  if playing then
    draw_list[#draw_list + 1] = playing
  end
  for _, s in pairs(cells) do
    draw_list[#draw_list + 1] = s
  end

  if #draw_list > max_dots then
    table.sort(draw_list, function(a, b)
      local ra = (playing and a.path == playing.path) and -1 or sample_lod_rank(a)
      local rb = (playing and b.path == playing.path) and -1 or sample_lod_rank(b)
      if prefer_set[a.path] then ra = ra - 200000000 end
      if prefer_set[b.path] then rb = rb - 200000000 end
      if ra == rb then
        return (a.path or "") < (b.path or "")
      end
      return ra < rb
    end)
    local trimmed = {}
    for i = 1, math.min(max_dots, #draw_list) do
      trimmed[i] = draw_list[i]
    end
    draw_list = trimmed
  end

  return draw_list, #candidates, true
end

function map_build_draw_entries(draw_list, padded_width, padded_height, padded_center_x, padded_center_y, zoom)
  local half_w = padded_width * 0.5
  local half_h = padded_height * 0.5
  local entries = {}
  for i = 1, #draw_list do
    local s = draw_list[i]
    local px = padded_center_x + ((s.x or 0.5) * padded_width - half_w) * zoom
    local py = padded_center_y + ((s.y or 0.5) * padded_height - half_h) * zoom
    entries[i] = {
      s = s,
      px = px,
      py = py,
      color = s._folder_unavailable and build_color_rrgbbaa(136, 136, 136, 90) or (s._render_color or get_sample_dot_color(s)),
      unavailable = s._folder_unavailable and true or false,
    }
  end
  return entries
end

function ensure_map_render_cache(padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y, margin)
  margin = margin or 24.0

  local filter_key = compute_map_filter_key()
  if map_cache.filter_key ~= filter_key or not map_cache.spatial then
    rebuild_map_filtered_cache()
  end

  local view_key = compute_map_view_key(padded_x0, padded_y0, padded_width, padded_height)
  if map_cache.view_key == view_key and map_cache.draw_list and map_cache.draw_entries then
    return map_cache.draw_list, map_cache.hover_list, map_cache
  end

  local zoom = state.zoom or 1.0
  local x_min, x_max, y_min, y_max = get_viewport_norm_bounds(
    padded_x0, padded_y0, padded_width, padded_height,
    padded_center_x, padded_center_y, margin
  )
  local hover_list = collect_viewport_samples(map_cache.spatial, x_min, x_max, y_min, y_max)

  local playing_path = preview_sample_obj and preview_sample_obj.path or nil
  local max_dots = MAP_DOT_BUDGET
  local prefer_set = map_cache.draw_path_set or {}

  local draw_list, visible_total, capped = apply_map_dot_cap(
    hover_list, max_dots, playing_path, x_min, x_max, y_min, y_max, prefer_set
  )

  if playing_path then
    local playing_in_draw = false
    for i = 1, #draw_list do
      if draw_list[i].path == playing_path then
        playing_in_draw = true
        break
      end
    end
    if not playing_in_draw then
      local playing = samples_by_path[playing_path]
      if playing and playing.x then
        draw_list[#draw_list + 1] = playing
      end
    end
  end

  local assigned_info = seq_assigned_sample_info()
  for path, _ in pairs(assigned_info) do
    local already = false
    for i = 1, #draw_list do
      if draw_list[i].path == path then
        already = true
        break
      end
    end
    if not already then
      local sample = samples_by_path[path]
      if sample and sample.x
          and sample.x >= x_min and sample.x <= x_max
          and sample.y >= y_min and sample.y <= y_max then
        draw_list[#draw_list + 1] = sample
      end
    end
  end

  local path_set = {}
  for i = 1, #draw_list do
    local p = draw_list[i].path
    if p then
      path_set[p] = true
    end
  end

  map_cache.view_key = view_key
  map_cache.hover_list = hover_list
  map_cache.draw_list = draw_list
  map_cache.draw_path_set = path_set
  map_cache.draw_entries = map_build_draw_entries(
    draw_list, padded_width, padded_height, padded_center_x, padded_center_y, zoom
  )
  map_cache.visible_total = visible_total
  map_cache.draw_count = #draw_list
  map_cache.dots_capped = capped
  map_cache.lod_budget = max_dots

  return draw_list, hover_list, map_cache
end

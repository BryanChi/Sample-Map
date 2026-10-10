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

function draw_map_grid(dl, x0, y0, width, height, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  -- Draw grid lines for frequency (horizontal) and time (vertical)
  if #state.samples > 0 and state.samples[1].x then
    local log10 = math.log(10)
    
    -- Brightness / pitch floor is 40 Hz (analyzer does not report below that)
    local freq_min_log = math.log(40.0) / log10
    local freq_max_log = math.log(20000.0) / log10
    
    -- Calculate duration range from samples for X-axis grid (cached with filter rebuild)
    local len_min_log, len_max_log = nil, nil
    if map_cache.duration_min and map_cache.duration_max then
      len_min_log = math.log(math.max(map_cache.duration_min, 0.01)) / log10
      len_max_log = math.log(math.max(map_cache.duration_max, 0.01)) / log10
    end
    
    -- Use reasonable defaults for duration if no samples
    if not len_min_log then
      len_min_log = math.log(0.01) / log10  -- 10ms
      len_max_log = math.log(60.0) / log10   -- 60 seconds
    end
    
    -- Subtle theme-tinted grid so it sits behind the dots without competing
    local grid_color = UI_THEME.grid_line
    local text_color = UI_THEME.grid_text
    
    -- Draw evenly spaced horizontal Y-axis grid lines
    local y_axis = map_y_axis_id()
    local num_freq_lines = 10  -- 10 evenly spaced lines
    for i = 0, num_freq_lines do
      local normalized_y = i / num_freq_lines  -- 0.0 to 1.0, evenly spaced
      
      -- Convert normalized Y back to the selected axis (inverse of layout transform)
      -- normalized_y = 1.0 - y_normalized, so y_normalized = 1.0 - normalized_y
      local y_normalized = 1.0 - normalized_y
      local freq_log = freq_min_log + y_normalized * (freq_max_log - freq_min_log)
      local freq_val = 10 ^ freq_log
      
      -- Convert normalized Y to screen coordinate (using padded area)
      local base_y = normalized_y * padded_height
      local py = padded_center_y + (base_y - padded_height * 0.5) * state.zoom
      
      -- Only draw if line is visible in viewport
      if py >= padded_y0 - 1 and py <= padded_y0 + padded_height + 1 then
        -- Draw line across padded area (from label padding to right edge)
        r.ImGui_DrawList_AddLine(dl, padded_x0, py, x0 + width, py, grid_color, 1.0)
        
        local freq_text
        if y_axis == "weight" then
          if i == 0 then
            freq_text = "Heavy"
          elseif i == num_freq_lines then
            freq_text = "Light"
          else
            freq_text = string.format("%.0f%%", y_normalized * 100.0)
          end
        else
          local rounded_freq = round_to_nice_map_freq(freq_val)
          if rounded_freq >= 1000.0 then
            freq_text = string.format("%.1fkHz", rounded_freq / 1000.0)
          else
            freq_text = string.format("%.0fHz", rounded_freq)
          end
        end
        -- Draw text at left edge, slightly offset from line
        r.ImGui_DrawList_AddText(dl, x0 + 4, py - 7, text_color, freq_text)
      end
    end
    
    -- Draw vertical time/duration grid lines (seconds)
    local duration_min, duration_max = map_cache.duration_min, map_cache.duration_max
    
    if duration_min and duration_max then
      -- Draw evenly spaced vertical time/duration grid lines
      -- Generate evenly spaced normalized X positions (every 10% = 0.1, accounting for 5% padding)
      local padding = 0.05
      local num_time_lines = 10  -- 10 evenly spaced lines
      for i = 0, num_time_lines do
        -- Map i from 0-num_time_lines to normalized_x accounting for padding
        local normalized_x = padding + (i / num_time_lines) * (1.0 - 2.0 * padding)
        
        -- Convert normalized X back to duration (inverse of layout transform)
        local len_log = len_min_log + ((normalized_x - padding) / (1.0 - 2.0 * padding)) * (len_max_log - len_min_log)
        local time_val = 10 ^ len_log
        
        -- Convert normalized X to screen coordinate (using padded area)
        local base_x = normalized_x * padded_width
        local px = padded_center_x + (base_x - padded_width * 0.5) * state.zoom
        
        -- Only draw if line is visible in viewport
        if px >= padded_x0 - 1 and px <= padded_x0 + padded_width + 1 then
          -- Draw line across padded area (from label padding to bottom edge)
          r.ImGui_DrawList_AddLine(dl, px, padded_y0, px, y0 + height, grid_color, 1.0)
          
          -- Add text label for time
          local time_text
          if time_val < 1.0 then
            time_text = string.format("%.1fs", time_val)
          elseif time_val < 10.0 then
            time_text = string.format("%.1fs", time_val)
          else
            time_text = string.format("%.0fs", time_val)
          end
          -- Draw text at top edge, slightly offset from line
          r.ImGui_DrawList_AddText(dl, px + 4, y0 + 4, text_color, time_text)
        end
      end
    end
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
    local col = (0x1EFF5E00) | alpha
    r.ImGui_DrawList_AddLine(dl, pts[i].px, pts[i].py, pts[i + 1].px, pts[i + 1].py, col, 1.15)
  end
  for i = 1, #pts do
    local t = (#pts == 1) and 1.0 or ((i - 1) / (#pts - 1))
    local alpha = math.floor(40 + t * 90 + 0.5)
    local r0 = 2.2 + t * 1.4
    local is_current = current_path and pts[i].s.path == current_path
    if not is_current then
      r.ImGui_DrawList_AddCircle(dl, pts[i].px, pts[i].py, r0, (0x1EFF5E00) | alpha, 10, 1.1)
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
    for i = 1, #entries do
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
  local result = nil
  if best_i then
    local e = entries[best_i]
    result = { sample = e.s, px = e.px, py = e.py, dist_sq = best_d, color = e.color }
  end
  cache.hover_memo = { gen = gen, mx = mx, my = my, snap_r = snap_r, result = result }
  return result
end

function render_map_samples(dl, hovered, mx, my, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
  local dot_radius = state.dot_radius or 2.0
  local clicked_sample = nil
  local click_handled_this_frame = false

  local outline_color = build_color_rrgbbaa(extract_rgb(state.dot_outline_color or 0xFF00FF))
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
  if not playing_path and next(highlight_info) == nil then
    -- Common case (nothing playing, no hovered track): plain dot loop.
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
    local ring_r = (selected_dot_radius + outline_size) * pulse
    r.ImGui_DrawList_AddCircleFilled(dl, e.px, e.py, selected_dot_radius, e.color, 16)
    local playing_assigned = highlight_info[e.s.path]
    if playing_assigned then
      r.ImGui_DrawList_AddCircle(dl, e.px, e.py, selected_dot_radius + 3.0, assigned_ring, 16, 1.8)
      if playing_assigned.selected then
        r.ImGui_DrawList_AddCircle(dl, e.px, e.py, selected_dot_radius + 6.0, selected_ring, 16, 2.0)
      end
    end
    r.ImGui_DrawList_AddCircle(dl, e.px, e.py, ring_r, outline_color, 16, state.dot_outline_thickness or 3.0)
    r.ImGui_DrawList_AddCircle(dl, e.px, e.py, ring_r * 1.35, (e.color & 0xFFFFFF00) | 0x55, 12, 1.5)
  end

  local closest = nil
  if hovered then
    local detect = state.dot_detection_multiplier or 16.0
    local snap_r = math.max(MAP_CLICK_SNAP_MIN, dot_radius * detect)
    closest = map_find_hover_entry(cache, entries, mx, my, snap_r)
  end

  if closest then
    local s = closest.sample
    local px, py = closest.px, closest.py
    local is_currently_playing = playing_path and playing_path == s.path

    if not is_currently_playing then
      r.ImGui_DrawList_AddCircle(dl, px, py, dot_radius + 2.0, closest.color, 12, 1.5)
    end
    r.ImGui_DrawList_AddCircle(dl, px, py, dot_radius + 1.5, s.hot_color or hover_color, 12, 1.5)

    -- Pin to the hovered dot so ImGui nav cannot relocate this tooltip.
    if r.ImGui_SetNextWindowPos then
      local tip_cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
      r.ImGui_SetNextWindowPos(ctx, px + 14, py + 14, tip_cond)
    end
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_Text(ctx, s.name)
    if s.tags and #s.tags > 0 then
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
  local sounds = {
    "/System/Library/Sounds/Glass.aiff",
    "/System/Library/Sounds/Hero.aiff",
    "/System/Library/Sounds/Ping.aiff",
  }
  for i = 1, #sounds do
    if r.file_exists(sounds[i]) then
      os.execute("afplay " .. shell_escape(sounds[i]) .. " >/dev/null 2>&1 &")
      return
    end
  end
  os.execute('printf "\\a" >/dev/null 2>&1 &')
end

function finish_scan_session(still_incomplete)
  local session = state.scan_session
  local now = r.time_precise()
  local elapsed = 0
  if type(session) == "table" then
    elapsed = session.elapsed_so_far or 0
    if type(session.started_at) == "number" then
      elapsed = elapsed + (now - session.started_at)
    end
  elseif state.scan_started and state.scan_started > 0 then
    elapsed = now - state.scan_started
  end
  if type(session) ~= "table" then
    session = { kind = state.analyzer_job_label or "Scan" }
  end
  if not scan_session_did_work(session) and elapsed < 0.5 then
    state.scan_session = nil
    return
  end

  local kind = session.kind or "Scan"
  local is_folder_scan = (kind == "Library scan" or kind == "Folder rescan" or kind == "Continued scan")
  local lines = {}
  lines[#lines + 1] = "Time: " .. format_scan_clock(elapsed)
  if session.detail and session.detail ~= "" then
    lines[#lines + 1] = "Folder: " .. tostring(session.detail)
  end
  if is_folder_scan then
    lines[#lines + 1] = string.format("New files indexed: %d", session.indexed or session.new_files or 0)
    lines[#lines + 1] = string.format("Changed files re-analyzed: %d", session.changed_files or 0)
    lines[#lines + 1] = string.format("Incomplete files analyzed: %d", session.incomplete_files or 0)
    lines[#lines + 1] = string.format("Unchanged files skipped: %d", session.unchanged_files or 0)
  else
    lines[#lines + 1] = string.format("Files processed: %d", math.max(session.queued or 0, session.analyzed or 0))
  end
  lines[#lines + 1] = string.format("Analyzer completed: %d", session.analyzed or 0)
  local error_count = session.analyze_errors or 0
  if (session.workers or 0) > 0 then
    lines[#lines + 1] = string.format("Workers: %d  ·  CPU cores: %d", session.workers, session.cores or 0)
  end
  lines[#lines + 1] = string.format("Library size: %d samples", #state.samples)

  local note = nil
  local debug_lines = {}
  local debug_samples = {}
  if type(still_incomplete) == "number" and still_incomplete > 0 then
    note = string.format("%d sample(s) still missing analyzer fields.", still_incomplete)
    if (session.merge_misses or 0) > 0 then
      note = note .. string.format(" %d result(s) did not match a library path.", session.merge_misses)
    end
    local reason_counts = {}
    local ext_counts = {}
    local logged = 0
    for _, s in ipairs(state.samples) do
      if sample_analysis_incomplete(s) then
        local missing = sample_analysis_missing_fields(s)
        local why = s._analyze_fail
        if type(why) ~= "string" or why == "" then
          if #missing > 0 then
            why = "never analyzed — missing " .. table.concat(missing, ", ")
          else
            why = "unknown"
          end
        end
        reason_counts[why] = (reason_counts[why] or 0) + 1
        local name = (s.path and s.path:match("([^/]+)$")) or s.path or "?"
        local ext = (name:match("(%.[^%.]+)$") or "(no ext)"):lower()
        ext_counts[ext] = (ext_counts[ext] or 0) + 1
        debug_samples[#debug_samples + 1] = {
          path = s.path,
          name = name,
          why = why,
        }
        if logged < 20 then
          add_scan_log(string.format("Still incomplete: %s (%s)", name, why))
          logged = logged + 1
        end
      end
    end
    debug_lines[#debug_lines + 1] = "Why they are still incomplete:"
    local reasons = {}
    for why, count in pairs(reason_counts) do
      reasons[#reasons + 1] = { why = why, count = count }
    end
    table.sort(reasons, function(a, b)
      if a.count == b.count then
        return a.why < b.why
      end
      return a.count > b.count
    end)
    for i = 1, #reasons do
      debug_lines[#debug_lines + 1] = string.format("  %d  %s", reasons[i].count, reasons[i].why)
    end
    debug_lines[#debug_lines + 1] = "By file type:"
    local exts = {}
    for ext, count in pairs(ext_counts) do
      exts[#exts + 1] = { ext = ext, count = count }
    end
    table.sort(exts, function(a, b)
      if a.count == b.count then
        return a.ext < b.ext
      end
      return a.count > b.count
    end)
    for i = 1, #exts do
      debug_lines[#debug_lines + 1] = string.format("  %d  %s", exts[i].count, exts[i].ext)
    end
  end

  for _, row in ipairs(debug_samples) do
    if tostring(row.why or ""):find("no audio decoder", 1, true) then
      local hint = "No audio decoder found: install ffmpeg to analyze mp3, flac, ogg and m4a files, then rescan."
      note = note and (note .. "\n" .. hint) or hint
      break
    end
  end

  local error_tooltip = nil
  if #debug_lines > 0 then
    error_tooltip = table.concat(debug_lines, "\n")
  end

  local clip = { kind, "" }
  for i = 1, #lines do
    clip[#clip + 1] = lines[i]
  end
  if error_count > 0 then
    clip[#clip + 1] = string.format("Analyzer errors: %d", error_count)
  end
  if note then
    clip[#clip + 1] = note
  end
  if #debug_lines > 0 then
    clip[#clip + 1] = ""
    for i = 1, #debug_lines do
      clip[#clip + 1] = debug_lines[i]
    end
  end
  if #debug_samples > 0 then
    clip[#clip + 1] = ""
    for i = 1, #debug_samples do
      local row = debug_samples[i]
      clip[#clip + 1] = string.format("%s — %s", row.name or "?", row.why or "")
      if row.path and row.path ~= "" then
        clip[#clip + 1] = "  " .. row.path
      end
    end
  end

  state.scan_complete_dialog = {
    title = "Scan complete",
    subtitle = kind,
    lines = lines,
    note = note,
    debug_lines = debug_lines,
    error_count = error_count,
    error_tooltip = error_tooltip,
    samples = debug_samples,
    clipboard = table.concat(clip, "\n"),
  }
  play_scan_complete_sound()
  add_scan_log(string.format("%s finished in %s", kind, format_scan_clock(elapsed)))
  state.scan_session = nil
end

function reveal_path_in_finder(path)
  if not path or path == "" then
    return
  end
  seq_reveal_sample_in_explorer({ path = path })
end

function sample_row_is_unreadable(entry)
  if type(entry) ~= "table" then
    return false
  end
  -- Only failures that point at the file itself. "no audio decoder found"
  -- (ffmpeg/sox missing) and "empty analyzer output" (worker trouble) are not
  -- the file's fault, so they are never offered for deletion.
  local why = tostring(entry.why or "")
  if why:find("no audio decoder", 1, true) then
    return false
  end
  return why:find("could not decode", 1, true) ~= nil
    or why:find("file not found", 1, true) ~= nil
end

function scan_complete_unreadable_paths(dlg)
  local paths = {}
  if type(dlg) ~= "table" or type(dlg.samples) ~= "table" then
    return paths
  end
  local seen = {}
  for i = 1, #dlg.samples do
    local entry = dlg.samples[i]
    if sample_row_is_unreadable(entry) and entry.path and entry.path ~= "" and not seen[entry.path] then
      seen[entry.path] = true
      paths[#paths + 1] = entry.path
    end
  end
  return paths
end

function remove_samples_and_files(paths)
  local drop = {}
  for i = 1, #(paths or {}) do
    local p = paths[i]
    if p and p ~= "" then
      drop[p] = true
      drop[path_index_key(p)] = true
    end
  end
  local kept = {}
  local removed = 0
  local failed = 0
  for _, sample in ipairs(state.samples) do
    local p = sample.path
    local key = p and path_index_key(p) or ""
    if p and (drop[p] or (key ~= "" and drop[key])) then
      local gone = false
      if r.file_exists(p) then
        gone = os.remove(p) and true or false
      else
        gone = true
      end
      if gone then
        removed = removed + 1
      else
        failed = failed + 1
        kept[#kept + 1] = sample
      end
    else
      kept[#kept + 1] = sample
    end
  end
  state.samples = kept
  rebuild_samples_path_index()
  if rebuild_tag_index then
    rebuild_tag_index()
  end
  if #state.samples > 0 then
    layout_samples()
  end
  save_samples()
  return removed, failed
end

function apply_scan_complete_file_deletes(dlg, paths)
  local removed, failed = remove_samples_and_files(paths)
  local drop = {}
  for i = 1, #(paths or {}) do
    if paths[i] then
      drop[paths[i]] = true
      drop[path_index_key(paths[i])] = true
    end
  end
  if type(dlg) == "table" and type(dlg.samples) == "table" then
    local kept = {}
    for i = 1, #dlg.samples do
      local entry = dlg.samples[i]
      local p = entry.path
      local key = p and path_index_key(p) or ""
      if not (p and (drop[p] or drop[key])) then
        kept[#kept + 1] = entry
      end
    end
    dlg.samples = kept
  end
  dlg.confirm_delete = nil
  add_scan_log(string.format("Deleted %d unreadable file(s)%s", removed, failed > 0 and (", " .. failed .. " failed") or ""))
  return removed, failed
end

function draw_scan_complete_sample_menu_items(path, name, why)
  name = name or (path and path:match("([^/]+)$")) or "Sample"
  r.ImGui_TextColored(ctx, UI_THEME.text, name)
  if why and why ~= "" then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, why)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Show in Finder") then
    reveal_path_in_finder(path)
  end
  if r.ImGui_MenuItem(ctx, "Open file") then
    if path and path ~= "" then
      os.execute("open " .. shell_escape(path) .. " >/dev/null 2>&1 &")
    end
  end
  if r.ImGui_MenuItem(ctx, "Preview") then
    local sample = lookup_sample_by_path(path)
    if sample then
      preview_sample(sample)
    end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Copy filename") then
    if r.ImGui_SetClipboardText then
      r.ImGui_SetClipboardText(ctx, name)
    end
  end
  if r.ImGui_MenuItem(ctx, "Copy path") then
    if r.ImGui_SetClipboardText then
      r.ImGui_SetClipboardText(ctx, path or "")
    end
  end
  -- Deletion is only offered for files the analyzer could not read, which is
  -- what the confirmation text promises.
  if path and path ~= "" and sample_row_is_unreadable({ why = why }) then
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Delete this file…") then
      local dlg = state.scan_complete_dialog
      if type(dlg) == "table" then
        dlg.confirm_delete = { path }
        dlg.open_delete_modal = true
      end
    end
  end
end

function render_scan_complete_dialog()
  local dlg = state.scan_complete_dialog
  if type(dlg) ~= "table" then
    return
  end
  local rect = state.main_window_rect
  if rect and r.ImGui_SetNextWindowPos then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    r.ImGui_SetNextWindowPos(ctx, rect.x + (rect.w or 0) * 0.5, rect.y + (rect.h or 0) * 0.38, cond, 0.5, 0.5)
  end
  local has_debug = (type(dlg.debug_lines) == "table" and #dlg.debug_lines > 0)
    or (type(dlg.samples) == "table" and #dlg.samples > 0)
  if r.ImGui_SetNextWindowSize then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    if has_debug then
      r.ImGui_SetNextWindowSize(ctx, 560, 560, cond)
    else
      r.ImGui_SetNextWindowSize(ctx, 400, 0, cond)
    end
  end
  local flags = 0
  if (not has_debug) and r.ImGui_WindowFlags_AlwaysAutoResize then
    flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize()
  end
  if r.ImGui_WindowFlags_NoCollapse then
    flags = flags | r.ImGui_WindowFlags_NoCollapse()
  end
  if r.ImGui_WindowFlags_NoDocking then
    flags = flags | r.ImGui_WindowFlags_NoDocking()
  end
  local visible, open = r.ImGui_Begin(ctx, "Scan complete##scan_done", true, flags)
  if visible then
    r.ImGui_TextColored(ctx, UI_THEME.success, dlg.title or "Scan complete")
    if dlg.subtitle and dlg.subtitle ~= "" then
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, dlg.subtitle)
    end
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    local lines = dlg.lines or {}
    for i = 1, #lines do
      r.ImGui_Text(ctx, lines[i])
    end
    local error_count = dlg.error_count or 0
    local error_tip = dlg.error_tooltip
    if error_count > 0 or (type(error_tip) == "string" and error_tip ~= "") then
      r.ImGui_Text(ctx, string.format("Analyzer errors: %d", error_count))
      local line_hover = r.ImGui_IsItemHovered(ctx)
      r.ImGui_SameLine(ctx, 0, 6)
      local help_dl = r.ImGui_GetWindowDrawList(ctx)
      r.ImGui_InvisibleButton(ctx, "##scan_done_err_help", 16, 16)
      local hx0, hy0 = r.ImGui_GetItemRectMin(ctx)
      local hx1, hy1 = r.ImGui_GetItemRectMax(ctx)
      local hcx = (hx0 + hx1) * 0.5
      local hcy = (hy0 + hy1) * 0.5
      local help_hover = r.ImGui_IsItemHovered(ctx)
      local bubble = (line_hover or help_hover) and UI_THEME.accent or UI_THEME.text_dim
      r.ImGui_DrawList_AddCircle(help_dl, hcx, hcy, 7, bubble, 18, 1.3)
      local qw, qh = r.ImGui_CalcTextSize(ctx, "?")
      r.ImGui_DrawList_AddText(help_dl, hcx - qw * 0.5, hcy - qh * 0.5 - 1, bubble, "?")
      if (line_hover or help_hover) and type(error_tip) == "string" and error_tip ~= "" and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, error_tip)
      end
    end
    if dlg.note and dlg.note ~= "" then
      r.ImGui_Spacing(ctx)
      r.ImGui_TextColored(ctx, 0xFFB870FF, dlg.note)
    end
    if has_debug then
      r.ImGui_Spacing(ctx)
      r.ImGui_Separator(ctx)
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Files that failed scanning")
      local child_flags = 0
      child_flags = sm_child_border_flag()
      if r.ImGui_BeginChild(ctx, "scan_done_debug", 0, 260, child_flags) then
        local rows = dlg.samples or {}
        if #rows > 0 then
          for i = 1, #rows do
            local entry = rows[i]
            local label = (entry.name or "?") .. "##scd" .. tostring(i)
            local picked = dlg.menu_path and entry.path == dlg.menu_path
            r.ImGui_Selectable(ctx, label, picked)
            if r.ImGui_IsItemClicked(ctx, 0) then
              local sample = lookup_sample_by_path(entry.path)
              if sample then
                preview_sample(sample)
              end
            end
            if r.ImGui_BeginPopupContextItem and r.ImGui_BeginPopupContextItem(ctx, "##scd_ctx" .. tostring(i)) then
              dlg.menu_path = entry.path
              dlg.menu_name = entry.name
              dlg.menu_why = entry.why
              draw_scan_complete_sample_menu_items(entry.path, entry.name, entry.why)
              r.ImGui_EndPopup(ctx)
            elseif r.ImGui_IsItemClicked(ctx, 1) then
              dlg.menu_path = entry.path
              dlg.menu_name = entry.name
              dlg.menu_why = entry.why
              if r.ImGui_OpenPopup then
                r.ImGui_OpenPopup(ctx, "##scan_done_sample_menu")
              end
            end
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
              r.ImGui_SetTooltip(ctx, (entry.why or "") .. "\n" .. (entry.path or ""))
            end
          end
        end
        r.ImGui_EndChild(ctx)
      end
      if r.ImGui_BeginPopup and r.ImGui_BeginPopup(ctx, "##scan_done_sample_menu") then
        draw_scan_complete_sample_menu_items(dlg.menu_path, dlg.menu_name, dlg.menu_why)
        r.ImGui_EndPopup(ctx)
      end
    end
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    if draw_ui_button("scan_done_copy", "Copy", 80, 26, { compact = true }) then
      if r.ImGui_SetClipboardText then
        r.ImGui_SetClipboardText(ctx, dlg.clipboard or "")
      end
    end
    local unreadable = scan_complete_unreadable_paths(dlg)
    if #unreadable > 0 then
      r.ImGui_SameLine(ctx)
      if draw_ui_button("scan_done_delete_bad", "Delete unreadable", 140, 26, { compact = true, style = "danger" }) then
        dlg.confirm_delete = unreadable
        dlg.open_delete_modal = true
      end
    end
    r.ImGui_SameLine(ctx)
    if draw_ui_button("scan_done_ok", "OK", 80, 26, { compact = true, style = "success" }) then
      state.scan_complete_dialog = nil
    end
    if dlg.open_delete_modal and r.ImGui_OpenPopup then
      r.ImGui_OpenPopup(ctx, "Delete files##scan_done_delete")
      dlg.open_delete_modal = nil
    end
    local delete_modal_open = false
    if r.ImGui_BeginPopupModal and type(dlg.confirm_delete) == "table" and #dlg.confirm_delete > 0 then
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
      local modal_visible, modal_keep = r.ImGui_BeginPopupModal(ctx, "Delete files##scan_done_delete", true, modal_flags)
      if modal_visible then
        delete_modal_open = true
        local n = #dlg.confirm_delete
        r.ImGui_TextColored(ctx, UI_THEME.danger, string.format(
          "Delete %d unreadable file%s from disk and the library?",
          n, n == 1 and "" or "s"
        ))
        r.ImGui_Spacing(ctx)
        r.ImGui_TextColored(ctx, UI_THEME.text_dim, "This cannot be undone.")
        r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Playable files are not included.")
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        if draw_ui_button("scan_done_delete_yes", "Delete", 90, 26, { compact = true, style = "danger" }) then
          apply_scan_complete_file_deletes(dlg, dlg.confirm_delete)
          if r.ImGui_CloseCurrentPopup then
            r.ImGui_CloseCurrentPopup(ctx)
          end
        end
        r.ImGui_SameLine(ctx)
        if draw_ui_button("scan_done_delete_no", "Cancel", 90, 26, { compact = true }) then
          dlg.confirm_delete = nil
          if r.ImGui_CloseCurrentPopup then
            r.ImGui_CloseCurrentPopup(ctx)
          end
        end
        r.ImGui_EndPopup(ctx)
      elseif modal_keep == false then
        dlg.confirm_delete = nil
      end
    end
    if (not delete_modal_open) and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      state.scan_complete_dialog = nil
    end
  end
  end_window(visible, true)
  if open == false then
    state.scan_complete_dialog = nil
  end
end

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

function draw_map_scan_progress_overlay(dl, x0, y0, width, height)
  if not state.scan_running then
    return 0
  end
  local file_scanning = #state.scan_queue > 0
  local analyzing = (state.incomplete_analysis_total or 0) > 0
      and state.scan_started > 0
      and #state.scan_queue == 0
      and (#state.analyzer_queue > 0 or #state.active_processes > 0)

  if not file_scanning and not analyzing then
    return 0
  end

  local done, total, elapsed, label
  if file_scanning then
    done = state.scan_total - #state.scan_queue
    total = state.scan_total
    elapsed = r.time_precise() - state.scan_started
    label = "Scanning"
  else
    local remaining = #state.analyzer_queue + #state.active_processes
    total = math.max(state.incomplete_analysis_total or 0, remaining)
    done = math.max(0, total - remaining)
    elapsed = r.time_precise() - state.scan_started
    label = state.analyzer_job_label or "Analyzing incomplete"
  end
  local progress = total > 0 and (done / total) or 0.0

  -- Draw semi-transparent overlay background at the top of the map
  local overlay_height = 118.0
  local overlay_y = y0
  local overlay_bg_color = 0x000000CC  -- Semi-transparent black (RRGGBBAA format, last two digits are alpha)
  r.ImGui_DrawList_AddRectFilled(dl, x0, overlay_y, x0 + width, overlay_y + overlay_height, overlay_bg_color, 0, 0)

  -- Draw progress bar at the top of the map
  local bar_padding = 20.0
  local bar_y = overlay_y + 25.0
  local bar_width = width - (bar_padding * 2)
  local bar_height = 8.0

  -- Progress text (centered above bar)
  local text = string.format("%s: %.1f%% (%d/%d) — %s", label, progress * 100.0, done, total, format_scan_clock(elapsed))
  local text_size_x, text_size_y = r.ImGui_CalcTextSize(ctx, text)
  local text_x = x0 + (width - text_size_x) * 0.5
  local text_y = overlay_y + 8.0
  -- Draw text with shadow for better visibility
  r.ImGui_DrawList_AddText(dl, text_x + 1, text_y + 1, 0x000000FF, text)
  r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, text)

  -- Background bar (dark gray)
  local bar_bg_color = 0x2A2A2AFF
  r.ImGui_DrawList_AddRectFilled(dl, x0 + bar_padding, bar_y, x0 + bar_padding + bar_width, bar_y + bar_height, bar_bg_color, 4.0, 0)

  -- Progress fill (bright green)
  local fill_width = bar_width * math.max(0.0, math.min(1.0, progress))
  if fill_width > 2.0 then
    local fill_color = 0x00FF00FF
    r.ImGui_DrawList_AddRectFilled(dl, x0 + bar_padding + 2, bar_y + 2, x0 + bar_padding + fill_width - 2, bar_y + bar_height - 2, fill_color, 2.0, 0)
  end

  -- Border (white)
  local border_color = 0xFFFFFFFF
  r.ImGui_DrawList_AddRect(dl, x0 + bar_padding, bar_y, x0 + bar_padding + bar_width, bar_y + bar_height, border_color, 4.0, 0, 1.5)

  -- Estimate time remaining (below bar)
  local remaining_count = file_scanning and #state.scan_queue or (#state.analyzer_queue + #state.active_processes)
  local remaining_y = bar_y + bar_height + 6.0
  local phase = file_scanning and "scan" or "analyze"
  local eta_sec = update_scan_eta(phase, done, remaining_count, r.time_precise())
  if remaining_count > 0 and type(eta_sec) == "number" and eta_sec > 0.5 then
    local remaining_text = "Estimated time remaining: " .. format_scan_clock(eta_sec)
    local remaining_size_x, remaining_size_y = r.ImGui_CalcTextSize(ctx, remaining_text)
    local remaining_x = x0 + (width - remaining_size_x) * 0.5
    r.ImGui_DrawList_AddText(dl, remaining_x + 1, remaining_y + 1, 0x000000FF, remaining_text)
    r.ImGui_DrawList_AddText(dl, remaining_x, remaining_y, 0xCCCCCCFF, remaining_text)
  elseif remaining_count > 0 and done < 4 then
    local remaining_text = "Estimated time remaining: calculating…"
    local remaining_size_x, remaining_size_y = r.ImGui_CalcTextSize(ctx, remaining_text)
    local remaining_x = x0 + (width - remaining_size_x) * 0.5
    r.ImGui_DrawList_AddText(dl, remaining_x + 1, remaining_y + 1, 0x000000FF, remaining_text)
    r.ImGui_DrawList_AddText(dl, remaining_x, remaining_y, 0xCCCCCCFF, remaining_text)
  end

  local btn_w, btn_h = 72, 22
  local btn_x = x0 + (width - btn_w) * 0.5
  local btn_y = overlay_y + overlay_height - btn_h - 8.0
  local mx, my = r.ImGui_GetMousePos(ctx)
  local over_btn = mx >= btn_x and mx <= (btn_x + btn_w) and my >= btn_y and my <= (btn_y + btn_h)
  -- Ignore the rect while another window/popup covers the map.
  if over_btn and r.ImGui_IsWindowHovered then
    local hover_flags = 0
    if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
      hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
    end
    over_btn = r.ImGui_IsWindowHovered(ctx, hover_flags) and true or false
  end
  -- The map InvisibleButton sits under this overlay and steals ImGui item clicks.
  -- Hit-test the Stop rect directly so the button always works.
  if over_btn and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then
    stop_scan()
  end
  r.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
  draw_ui_button("scan_stop", "Stop", btn_w, btn_h, { style = "danger", compact = true })
  if over_btn then
    r.ImGui_SetTooltip(ctx, "Stop scanning and save progress.\nThe next scan will continue from here — you won't start over.")
  end

  return overlay_height
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
  local overlay_h = (state.scan_running and (state.map_scan_overlay_h or 118)) or 0
  local over_scan_overlay = overlay_h > 0 and my >= y0 and my <= (y0 + overlay_h)

  handle_map_view_input(hovered and not over_scan_overlay, mx, my, width, height, x0, y0)

  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height, UI_THEME.bg, 6)

  local label_padding_left = 70
  local label_padding_top = 25
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

  draw_map_grid(dl, x0, y0, width, height, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)

  local clicked_sample = render_map_samples(dl, hovered and not over_scan_overlay, mx, my, padded_x0, padded_y0, padded_width, padded_height, padded_center_x, padded_center_y)
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

  state.map_scan_overlay_h = tonumber(draw_map_scan_progress_overlay(dl, x0, y0, width, height)) or 0
  draw_map_status_overlay(dl, x0, y0, width, height)
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

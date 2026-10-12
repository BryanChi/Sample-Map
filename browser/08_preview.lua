-- Sample Map Browser module: preview
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Preview handling --------------------------------------------------------
function release_preview_source()
  if not preview_source then
    preview_source_engine_owned = false
    return
  end

  if preview_source_engine_owned then
    preview_source = nil
    preview_source_engine_owned = false
    return
  end

  if r.PCM_Source_Destroy then
    local can_destroy = false

    if r.GetMediaSourceLength then
      local ok = pcall(function() return r.GetMediaSourceLength(preview_source) end)
      if ok then
        can_destroy = true
      end
    end

    if not can_destroy and r.ValidatePtr2 then
      local ok, valid = pcall(function() return r.ValidatePtr2(0, preview_source, "PCM_source*") end)
      if ok and valid then
        can_destroy = true
      end
    end

    if not can_destroy and r.ValidatePtr then
      local ok, valid = pcall(function() return r.ValidatePtr(preview_source, "PCM_source*") end)
      if ok and valid then
        can_destroy = true
      end
    end

    if can_destroy then
      pcall(function() r.PCM_Source_Destroy(preview_source) end)
    end
  end

  preview_source = nil
  preview_source_engine_owned = false
end

function stop_preview()
  local mix = seq_layer_mix_preview
  seq_layer_mix_preview = nil
  if mix and mix.voices then
    for i = 1, #mix.voices do
      local v = mix.voices[i]
      if v then
        if v.obj and r.CF_Preview_Stop then
          pcall(r.CF_Preview_Stop, v.obj)
        elseif v.xen_id and type(v.xen_id) == "number" and r.Xen_StopSourcePreview then
          pcall(r.Xen_StopSourcePreview, v.xen_id)
        end
        if v.src and r.PCM_Source_Destroy then
          pcall(r.PCM_Source_Destroy, v.src)
        end
        v.obj = nil
        v.xen_id = nil
        v.src = nil
        v.started = false
      end
    end
  end

  -- Stop CF_Preview instances first (uses objects, not IDs)
  if cf_preview_obj then
    if r.CF_Preview_StopAll then
      r.CF_Preview_StopAll()
    elseif r.CF_Preview_Stop then
      r.CF_Preview_Stop(cf_preview_obj)
    end
    cf_preview_obj = nil
  elseif r.CF_Preview_StopAll then
    -- Stop all CF_Preview instances even if we don't have a handle
    r.CF_Preview_StopAll()
  end

  -- Stop preview using Xen_StopSourcePreview if we have an integer preview ID
  if preview_proc and type(preview_proc) == "number" and r.Xen_StopSourcePreview then
    r.Xen_StopSourcePreview(preview_proc)
    preview_proc = nil
  elseif preview_proc and type(preview_proc) == "number" and r.StopSourcePreview then
    r.StopSourcePreview(preview_proc)
    preview_proc = nil
  elseif preview_source then
    -- Stop track preview style APIs
    if r.StopTrackPreview2 and preview_track then
      r.StopTrackPreview2(preview_source, preview_track)
    elseif r.StopTrackPreview then
      r.StopTrackPreview(preview_source)
    end
    preview_proc = nil
  end

  release_preview_source()

  cancel_waveform_generation()

  preview_start_time = 0.0
  preview_proc = nil
end

function preview_output_volume(sample)
  return (state.preview_volume or 1.0) * get_sample_gain(sample)
end

function get_sample_gain(sample)
  if not sample then
    return 1.0
  end
  local path = sample.path and normalize_path(sample.path) or nil
  local session = path and state.seq_sample_vol_session and state.seq_sample_vol_session[path]
  local g = nil
  if type(session) == "number" then
    g = session
  else
    g = tonumber(sample.gain)
    if g == nil and path and find_sample_by_path then
      local lib = find_sample_by_path(path)
      g = lib and tonumber(lib.gain)
    end
  end
  g = tonumber(g) or 1.0
  if g < 0.05 then
    g = 0.05
  elseif g > 4 then
    g = 4
  end
  return g
end

-- Stop sample preview when REAPER transport starts (space, arrange play, etc).
function stop_preview_if_transport_started()
  local playing = false
  if r.GetPlayState then
    playing = (r.GetPlayState() & 1) == 1
  end
  if playing and not state.seq_last_reaper_playing and preview_proc then
    stop_preview()
    state.preview_paused = false
  end
  state.seq_last_reaper_playing = playing
  if seq_layering_update_mix_preview then
    seq_layering_update_mix_preview()
  end
end


function start_preview_audio(sample, start_time)
  start_time = math.max(0.0, start_time or 0.0)
  if not sample or not sample.path or tostring(sample.path):find("^layering%-mix:") then
    return false
  end
  if preview_source then
    release_preview_source()
  end

  preview_source = r.PCM_Source_CreateFromFile(sample.path)
  preview_source_engine_owned = false
  if not preview_source then
    return false
  end

  if r.CF_CreatePreview and r.CF_Preview_SetValue and r.CF_Preview_Play then
    cf_preview_obj = r.CF_CreatePreview(preview_source)
    if cf_preview_obj then
      r.CF_Preview_SetValue(cf_preview_obj, "D_VOLUME", preview_output_volume(sample))
      if start_time > 0 then
        r.CF_Preview_SetValue(cf_preview_obj, "D_POSITION", start_time)
      end
      if r.CF_Preview_Play(cf_preview_obj) then
        preview_proc = true
        preview_start_time = r.time_precise() - start_time
        state.pop_start_time = r.time_precise()
        return true
      end
      cf_preview_obj = nil
    end
  elseif r.PlayTrackPreview2 then
    local track = ensure_preview_track()
    if track then
      local preview = {
        src = preview_source,
        startpos = start_time,
        volume = preview_output_volume(sample),
        pan = 0.0,
        loop = false,
        length = -1.0,
        fadein = 0.0,
        fadeout = 0.0,
        pitch = 0.0,
        mode = 0,
      }
      if r.PlayTrackPreview2(0, preview, track) then
        preview_proc = true
        preview_start_time = r.time_precise() - start_time
        state.pop_start_time = r.time_precise()
        return true
      end
    end
  elseif r.Xen_StartSourcePreview then
    local preview_id = r.Xen_StartSourcePreview(preview_source, preview_output_volume(sample), false)
    if preview_id and preview_id ~= 0 then
      preview_proc = preview_id
      preview_source_engine_owned = true
      preview_start_time = r.time_precise() - start_time
      state.pop_start_time = r.time_precise()
      return true
    end
  end

  release_preview_source()
  return false
end


function history_remove_by_path(path)
  if not path then
    return
  end
  local hist = state.played_history
  if not hist then
    return
  end
  for i = #hist, 1, -1 do
    local entry = hist[i]
    if entry and entry.path == path then
      table.remove(hist, i)
    end
  end
end

function history_compact_unique()
  local hist = state.played_history or {}
  local seen = {}
  local out = {}
  local head_path = state.history_head and state.history_head.path or nil
  if (state.history_index or 0) == 0 and preview_sample_obj and preview_sample_obj.path then
    head_path = preview_sample_obj.path
  end
  for i = 1, #hist do
    local s = hist[i]
    local p = s and s.path
    if p and not seen[p] and p ~= head_path then
      seen[p] = true
      out[#out + 1] = s
    end
  end
  state.played_history = out
  local idx = state.history_index or 0
  if idx > #out then
    state.history_index = #out
  end
end

function history_build_items()
  local items = {}
  local seen = {}
  local hist = state.played_history or {}
  for i = #hist, 1, -1 do
    local s = hist[i]
    if s and s.path and not seen[s.path] then
      seen[s.path] = true
      items[#items + 1] = s
    end
  end
  local head = state.history_head
  if (state.history_index or 0) == 0 then
    head = preview_sample_obj or head
  end
  if (not head or not head.path) and preview_sample_obj and preview_sample_obj.path then
    head = preview_sample_obj
  end
  if head and head.path and not seen[head.path] then
    items[#items + 1] = head
  end
  return items
end

-- False (with a short on-screen note) when the sample cannot be played:
-- its drive/scan folder is offline, or the file was moved or deleted.
function sample_preview_file_ok(sample)
  if sample_scan_folder_unavailable(sample) then
    sm_notify("Sample's drive or folder is offline", "warn")
    return false
  end
  local path = tostring(sample.path)
  if not path:find("^layering%-mix:") and not r.file_exists(path) then
    sm_notify("File not found: " .. (path:match("([^/\\]+)$") or path) .. " (moved or deleted? Rescan to remove it)", "warn")
    return false
  end
  return true
end

-- --- History navigation --------------------------------------------------------
function preview_sample_from_history(sample)
  local start_time = get_sample_start_offset(sample)

  if not sample or not sample.path then
    return
  end

  if not sample_preview_file_ok(sample) then
    return
  end

  stop_preview()

  preview_sample_obj = sample
  preview_start_time = r.time_precise() - start_time
  state.preview_position = start_time
  state.preview_paused = false
  state.breathing_start_time = r.time_precise()

  -- Play immediately; waveform builds across subsequent frames
  start_preview_audio(sample, start_time)
  ensure_waveform_for_sample(sample)
end


function navigate_history(direction)
  -- direction: -1 for back (up arrow), 1 for forward (down arrow)
  -- history_index: 0 = current sample, 1+ = index in played_history array
  
  local new_index = state.history_index + direction
  
  -- Clamp to valid range
  if new_index < 0 then
    return  -- Can't go back further than current
  elseif new_index > #state.played_history then
    return  -- Can't go forward past oldest
  end
  
  -- If going back from current (index 0) to history, need at least one item
  if new_index > 0 and #state.played_history == 0 then
    return
  end
  
  state.history_index = new_index
  
  local sample = nil
  if new_index == 0 then
    -- Back to the sample that was current when history browsing started
    sample = state.history_head or preview_sample_obj
  else
    -- Navigate to history entry
    sample = state.played_history[new_index]  -- Lua arrays are 1-indexed
  end
  
  if sample and sample.path then
    preview_sample_from_history(sample)
  end
end


function preview_sample(sample, start_time)
  if start_time == nil then
    start_time = get_sample_start_offset(sample)
  end
  start_time = math.max(0.0, start_time or 0.0)

  if not sample or not sample.path then
    return
  end

  if not sample_preview_file_ok(sample) then
    return
  end

  if preview_sample_obj and preview_sample_obj.path and preview_sample_obj.path ~= sample.path then
    history_remove_by_path(preview_sample_obj.path)
    table.insert(state.played_history, 1, preview_sample_obj)
    if #state.played_history > 100 then
      table.remove(state.played_history, #state.played_history)
    end
  end
  history_remove_by_path(sample.path)

  state.history_index = 0
  state.history_head = sample
  map_play_trace_push(sample)

  stop_preview()

  preview_sample_obj = sample
  preview_start_time = r.time_precise() - start_time
  state.preview_position = start_time
  state.preview_paused = false
  state.breathing_start_time = r.time_precise()

  -- Start audio first so click feels instant; waveform fills in over the next frames
  start_preview_audio(sample, start_time)
  ensure_waveform_for_sample(sample)
end


function get_preview_position()
  if preview_proc and preview_sample_obj then
    local pos = nil

    if cf_preview_obj and r.CF_Preview_GetValue then
      local ret, cf_pos = r.CF_Preview_GetValue(cf_preview_obj, "D_POSITION")
      if ret and cf_pos then
        pos = cf_pos
      end
    end

    if not pos then
      local elapsed = r.time_precise() - preview_start_time
      local duration = preview_sample_obj.duration or 0.0
      pos = math.min(elapsed, duration)
      if elapsed >= duration then
        stop_preview()
        state.preview_paused = false
        state.preview_position = duration
        return duration
      end
    end

    state.preview_position = pos
    return pos
  end

  if preview_sample_obj then
    return state.preview_position or 0.0
  end

  return nil
end

function seek_preview(time)
  if not preview_sample_obj then
    return
  end
  local duration = preview_sample_obj.duration or 0.0
  time = tonumber(time) or 0.0
  if duration > 0 then
    time = math.max(0.0, math.min(duration, time))
  else
    time = math.max(0.0, time)
  end
  if preview_proc and cf_preview_obj and r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(cf_preview_obj, "D_POSITION", time)
    preview_start_time = r.time_precise() - time
    state.preview_position = time
    state.preview_paused = false
    return
  end
  preview_sample(preview_sample_obj, time)
end

-- defer_save: the knob drag calls this every frame; it saves once on release
-- (shutdown also saves) instead of rewriting the config file per mouse move.
function apply_preview_volume(vol, defer_save)
  vol = math.max(0.0, math.min(1.0, vol))
  state.preview_volume = vol
  if defer_save then
    state._preview_volume_save_pending = true
  else
    state._preview_volume_save_pending = nil
    save_config()
  end

  if cf_preview_obj and r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(cf_preview_obj, "D_VOLUME", vol * get_sample_gain(preview_sample_obj))
    return
  end

  if preview_proc and preview_sample_obj then
    local resume_pos = state.preview_position or 0.0
    local sample = preview_sample_obj
    stop_preview()
    preview_sample(sample, resume_pos)
  end
end

function draw_preview_volume_knob(knob_size)
  local vol = state.preview_volume or 1.0
  local radius = knob_size * 0.5

  r.ImGui_InvisibleButton(ctx, "##preview_vol_knob", knob_size, knob_size)
  local active = r.ImGui_IsItemActive(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)

  local fine = seq_fine_drag_down()
  if active then
    local _, dy = r.ImGui_GetMouseDelta(ctx)
    if dy ~= 0.0 then
      local step = (1.0 / 200.0) * (fine and SEQ_FINE_DRAG_SCALE or 1.0)
      vol = vol + (-dy) * step
      apply_preview_volume(vol, true)
      vol = state.preview_volume or vol
    end
  elseif state._preview_volume_save_pending then
    state._preview_volume_save_pending = nil
    save_config()
  end

  if r.ImGui_IsItemClicked(ctx, 0) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    apply_preview_volume(1.0)
    vol = state.preview_volume or 1.0
  end

  if hovered or active then
    r.ImGui_SetTooltip(ctx, string.format("Volume: %.0f%% (double-click reset)", vol * 100))
  end

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local cx = x0 + radius
  local cy = y0 + radius
  local ANGLE_MIN = math.pi * 0.75
  local ANGLE_MAX = math.pi * 2.25
  local angle = ANGLE_MIN + (ANGLE_MAX - ANGLE_MIN) * vol
  local accent = active and UI_THEME.accent_hvr or (hovered and UI_THEME.accent or 0x148A3AFF)
  local fill = active and UI_THEME.accent_fill_h or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)

  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius - 0.5, fill, 22)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, radius - 0.5, accent, 22, hovered and 1.8 or 1.3)
  if hovered or active then
    r.ImGui_DrawList_AddCircle(dl, cx, cy, radius + 1.5, 0x1EFF5E33, 22, 1.0)
  end
  local arc_r = radius - 3.0
  local n = 18
  local prev_x, prev_y
  for i = 0, n do
    local t = i / n
    local a = ANGLE_MIN + (angle - ANGLE_MIN) * t
    local ax = cx + math.cos(a) * arc_r
    local ay = cy + math.sin(a) * arc_r
    if prev_x then
      r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, ax, ay, accent, 2.0)
    end
    prev_x, prev_y = ax, ay
  end
  local lx = cx + math.cos(angle) * (radius - 5.0)
  local ly = cy + math.sin(angle) * (radius - 5.0)
  r.ImGui_DrawList_AddLine(dl, cx, cy, lx, ly, 0xFFFFFFFF, 1.8)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 2.0, 0xFFFFFFFF, 10)
end


-- Helper function to change color alpha (set alpha value 0.0-1.0)
function change_color_alpha(color, alpha_value)
  if not color then return color end
  local r, g, b = extract_rgb_rrgbbaa(color)
  local new_alpha = math.max(0, math.min(255, math.floor(alpha_value * 255)))
  return build_color_rrgbbaa(r, g, b, new_alpha)
end

-- Helper function to blend two colors
function blend_colors(color1, color2, t)
  t = math.max(0.0, math.min(1.0, t))
  local r1, g1, b1 = extract_rgb_rrgbbaa(color1)
  local r2, g2, b2 = extract_rgb_rrgbbaa(color2)
  local r = math.floor(r1 * (1.0 - t) + r2 * t)
  local g = math.floor(g1 * (1.0 - t) + g2 * t)
  local b = math.floor(b1 * (1.0 - t) + b2 * t)
  local a1 = color1 % 256
  local a2 = color2 % 256
  local a = math.floor(a1 * (1.0 - t) + a2 * t)
  return build_color_rrgbbaa(r, g, b, a)
end

-- Helper function to brighten a color while preserving hue
-- brightness_factor: 0.0 = no change, 1.0 = maximum brightness (toward white but preserving hue)
function brighten_color_preserve_hue(color, brightness_factor)
  brightness_factor = math.max(0.0, math.min(1.0, brightness_factor))
  local r, g, b = extract_rgb_rrgbbaa(color)
  
  -- Find the maximum component to determine the current brightness
  local max_component = math.max(r, g, b)
  if max_component == 0 then
    -- Black color - return a gray based on brightness
    local gray = math.floor(brightness_factor * 255)
    return build_color_rrgbbaa(gray, gray, gray, 255)
  end
  
  -- Calculate how much to scale each component toward 255 while preserving ratios
  -- This preserves hue while increasing brightness
  local scale_factor = 1.0 + brightness_factor * (255.0 / max_component - 1.0)
  
  local new_r = math.min(255, math.floor(r * scale_factor))
  local new_g = math.min(255, math.floor(g * scale_factor))
  local new_b = math.min(255, math.floor(b * scale_factor))
  
  return build_color_rrgbbaa(new_r, new_g, new_b, 255)
end

-- Draw glowing circle effect (adapted from provided pattern)
function draw_glowing_circle(dl, x, y, glow_in, glow_out, solid_rad, clr, center_clr)
  -- Draw solid center circle if specified
  if solid_rad then
    local center_color = center_clr or clr
    r.ImGui_DrawList_AddCircleFilled(dl, x, y, solid_rad, center_color, 32)
  end
  
  -- Draw concentric circles for glow effect
  -- Use step size based on radius to balance quality and performance
  local step = math.max(1.5, (glow_out - glow_in) / 8.0)  -- ~8 rings (cheap glow)
  for i = glow_in, glow_out, step do
    local range = glow_out - glow_in
    if range > 0 then
      -- Calculate normalized position (1.0 at glow_in, 0.0 at glow_out)
      local n = (glow_out - i) / range
      
      -- Opacity decreases as we go outward
      local opacity = n
      
      -- Blend colors if center color is provided
      local circle_color = clr
      if center_clr then
        circle_color = blend_colors(clr, center_clr, n)
      end
      
      -- Apply opacity
      local final_color = change_color_alpha(circle_color, opacity)
      
      -- Draw circle outline (not filled for glow effect)
      r.ImGui_DrawList_AddCircle(dl, x, y, i, final_color, 32, 1.0)
    end
  end
end

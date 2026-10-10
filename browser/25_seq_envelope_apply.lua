-- Sample Map Browser module: seq_envelope_apply
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_env_levels_at(env, t, length)
  return seq_env_levels_at_norm(seq_normalize_track_env(env), t)
end

-- Same as seq_env_levels_at for an env already passed through seq_normalize_track_env.
function seq_env_levels_at_norm(env, t)
  local pts = env and env.points
  if not pts or #pts == 0 then
    return 1.0
  end
  t = t or 0.0
  if t <= (pts[1].t or 0.0) then
    return pts[1].amp or 1.0
  end
  local last = pts[#pts]
  if t >= (last.t or 0.0) then
    return last.amp or 1.0
  end
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    if t <= (b.t or 0.0) then
      local span = math.max(0.0000001, (b.t or 0.0) - (a.t or 0.0))
      local u = (t - (a.t or 0.0)) / span
      return seq_env_seg_eval(a.amp or 1.0, b.amp or 1.0, u, a.curve)
    end
  end
  return last.amp or 1.0
end

function seq_build_env_amp_points(item_len, env, env_offset)
  env = seq_normalize_track_env(env)
  item_len = math.max(0.001, item_len or 0.25)
  env_offset = math.max(0.0, env_offset or 0.0)
  local pts = {}
  local function add(t, amp)
    t = math.max(0.0, math.min(item_len, t))
    amp = math.max(0.00001, math.min(4.0, amp or 1.0))
    local last = pts[#pts]
    if last and math.abs(last.t - t) < 0.00005 then
      last.amp = amp
      return
    end
    pts[#pts + 1] = { t = t, amp = amp }
  end

  add(0.0, seq_env_levels_at_norm(env, env_offset))
  local src = env.points
  for i, p in ipairs(src) do
    local local_t = (p.t or 0.0) - env_offset
    if local_t > 0.00005 and local_t < item_len - 0.00005 then
      add(local_t, p.amp)
    end
    local nxt = src[i + 1]
    local curve = p.curve or 0.0
    if nxt and math.abs(curve) > 0.001 then
      local t0, t1 = p.t or 0.0, nxt.t or 0.0
      local span = t1 - t0
      if span > 0.0002 then
        local steps = math.max(6, math.min(16, math.floor(span * 80.0 + 0.5)))
        for k = 1, steps - 1 do
          local u = k / steps
          local t = t0 + span * u - env_offset
          if t > 0.00005 and t < item_len - 0.00005 then
            add(t, seq_env_seg_eval(p.amp, nxt.amp, u, curve))
          end
        end
      end
    end
  end
  add(item_len, seq_env_levels_at_norm(env, env_offset + item_len))
  return pts
end

function seq_apply_envelope_fades_fallback(item, take, item_len, env, env_offset)
  -- Audible fallback when take envelopes can't be created.
  env = seq_normalize_track_env(env)
  env_offset = math.max(0.0, env_offset or 0.0)
  if item then
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
  end
  if not take then
    return
  end
  local amp = seq_env_levels_at_norm(env, env_offset)
  local max_amp = amp
  local win_end = env_offset + (item_len or 0.0)
  for _, p in ipairs(env.points) do
    local pt = p.t or 0.0
    if pt >= env_offset - 0.0001 and pt <= win_end + 0.0001 then
      if (p.amp or 0.0) > max_amp then
        max_amp = p.amp
      end
    end
  end
  local shaped = math.max(0.05, math.min(4.0, amp * 0.4 + max_amp * 0.6))
  local base = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
  if not base or base <= 0 then
    base = 1.0
  end
  r.SetMediaItemTakeInfo_Value(take, "D_VOL", base * math.min(1.0, shaped))
end

function seq_apply_item_edge_fades(item, item_len, env)
  if not item then
    return
  end
  r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
end

function seq_apply_take_volume_envelope(take, item_len, env, env_offset)
  if not take or not item_len or item_len <= 0.0001 then
    return false
  end
  env = seq_normalize_track_env(env)
  env_offset = math.max(0.0, env_offset or 0.0)
  local item = r.GetMediaItemTake_Item(take)
  if not seq_env_shape_active_norm(env) then
    if item then
      r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
      r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
    end
    return false
  end

  local pts = seq_build_env_amp_points(item_len, env, env_offset)
  local tenv = seq_ensure_take_volume_envelope(take)
  if tenv then
    r.DeleteEnvelopePointRange(tenv, -0.01, item_len + 1.0)
    local scaling = r.GetEnvelopeScalingMode(tenv)
    for _, p in ipairs(pts) do
      local y = r.ScaleToEnvelopeMode(scaling, p.amp)
      r.InsertEnvelopePoint(tenv, p.t, y, 0, 0, false, true)
    end
    r.Envelope_SortPoints(tenv)
    if item then
      r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
      r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
    end
    return true
  elseif item then
    seq_apply_envelope_fades_fallback(item, take, item_len, env, env_offset)
  end
  return false
end

function seq_resync_all_regions(opts)
  opts = opts or {}
  local own_refresh = not opts.skip_arrange
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  if not opts.skip_remove then
    remove_seq_rendered_items(nil)
  end
  clear_seq_vary_rank_cache()
  for _, region in ipairs(state.seq_regions) do
    sync_seq_region(region, {
      skip_remove = true,
      skip_mix = true,
      skip_arrange = true,
      skip_cache_clear = true,
    })
  end
  if not opts.skip_mix then
    seq_apply_all_slot_mix_to_reaper()
  end
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if own_refresh then
    r.UpdateArrange()
  end
end

function seq_on_slot_mix_changed(slot, opts)
  opts = opts or {}
  state.seq_player_rev = (state.seq_player_rev or 0) + 1
  seq_normalize_slot_mix(slot)
  seq_apply_slot_mix_to_reaper_track(slot)
  if seq_player_sync_slot then
    seq_player_sync_slot(slot)
  end
  if seq_schedule_ingest_save then
    seq_schedule_ingest_save()
  elseif save_seq_project_state then
    save_seq_project_state()
  end
  if opts.resync then
    seq_resync_all_regions()
  end
end

-- Lightweight peak cache for envelope popup (does not clobber the main preview waveform).
-- Global (not local) to stay under Lua's 200-local main-chunk limit.
seq_env_wave_cache = {}
seq_layer_mix_preview = nil
seq_layer_mix_wave_cache = nil

function seq_env_downsample_peaks(src_peaks, width)
  if not src_peaks or #src_peaks == 0 or width < 2 then return nil end
  local out = {}
  local n = #src_peaks
  for i = 1, width do
    local a = math.floor((i - 1) * n / width) + 1
    local b = math.floor(i * n / width)
    if b < a then b = a end
    local peak = 0.0
    for j = a, math.min(n, b) do
      local v = src_peaks[j] or 0.0
      if v > peak then peak = v end
    end
    out[i] = peak
  end
  return out
end

function seq_env_build_wave_peaks(path, width)
  -- Reads peaks straight from a PCM source, so nothing is added to the project.
  if not path or path == "" or not r.PCM_Source_CreateFromFile
      or not r.PCM_Source_GetPeaks or not r.new_array then
    return nil, nil
  end
  width = math.max(48, math.min(320, math.floor(width or 200)))
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then return nil, nil end
  local ok, peaks, duration = pcall(function()
    local dur = pick_number({ r.GetMediaSourceLength(src) }, 0.0)
    local channels = math.floor(pick_number({ r.GetMediaSourceNumChannels(src) }, 1))
    channels = math.max(1, math.min(8, channels))
    if dur <= 0.0001 then
      return nil, nil
    end
    if r.PCM_Source_BuildPeaks and r.PCM_Source_BuildPeaks(src, 0) ~= 0 then
      -- Bounded busy-wait on the UI thread; a slow build is retried later.
      local deadline = r.time_precise() + 0.15
      while r.PCM_Source_BuildPeaks(src, 1) ~= 0 do
        if r.time_precise() > deadline then break end
      end
      r.PCM_Source_BuildPeaks(src, 2)
    end
    -- One peak per bin: peakrate = bins per second, so every frame of the bin is covered.
    local buf = r.new_array(channels * width * 2)
    buf.clear()
    local ret = r.PCM_Source_GetPeaks(src, width / dur, 0.0, channels, width, 0, buf)
    local got = math.floor(tonumber(ret) or 0) % 1048576
    if got <= 0 then
      return nil, nil
    end
    if got > width then got = width end
    -- buf holds a block of maxima (frame-major, channel-interleaved), then a block of minima.
    local min_off = channels * width
    local out = {}
    local max_v = 0.0
    for i = 0, width - 1 do
      local peak = 0.0
      if i < got then
        for c = 0, channels - 1 do
          local hi = math.abs(buf[i * channels + c + 1] or 0.0)
          local lo = math.abs(buf[min_off + i * channels + c + 1] or 0.0)
          if hi > peak then peak = hi end
          if lo > peak then peak = lo end
        end
      end
      out[i + 1] = peak
      if peak > max_v then max_v = peak end
    end
    if max_v > 0.0001 then
      for i = 1, #out do out[i] = out[i] / max_v end
    end
    return out, dur
  end)
  r.PCM_Source_Destroy(src)
  if not ok then
    return nil, nil
  end
  return peaks, duration
end

function seq_env_wave_peaks_for_width(cached, width)
  if cached.width == width then
    return cached.peaks
  end
  cached.resized = cached.resized or {}
  local resized = cached.resized[width]
  if not resized then
    resized = seq_env_downsample_peaks(cached.peaks, width) or cached.peaks
    cached.resized[width] = resized
  end
  return resized
end

function seq_env_get_wave_peaks(sample, width)
  if not sample or not sample.path then return nil, nil end
  width = math.max(48, math.min(320, math.floor(width or 200)))
  local cached = seq_env_wave_cache[sample.path]
  if cached and cached.peaks and #cached.peaks > 0 and cached.duration and cached.duration > 0 then
    return seq_env_wave_peaks_for_width(cached, width), cached.duration
  end

  -- Prefer PCM-built peaks so duration and waveform share one timeline.
  -- Fall back to downsampling the preview waveform only when PCM build fails.
  -- A failed build (e.g. offline file) is not retried for 30 s.
  local build_w = 256
  local peaks, duration = nil, nil
  local now = r.time_precise()
  -- After three failed builds the file is not retried this session.
  local recently_failed = cached and cached.failed
      and ((cached.fails or 1) >= 3 or ((now - (cached.at or 0)) >= 0 and (now - (cached.at or 0)) < 30.0))
  if not recently_failed then
    peaks, duration = seq_env_build_wave_peaks(sample.path, build_w)
    if not peaks or not duration or duration <= 0 then
      peaks, duration = nil, nil
      local fails = ((cached and cached.failed and cached.fails) or 0) + 1
      seq_env_wave_cache[sample.path] = { failed = true, at = now, fails = fails }
    end
  end
  if not peaks
      and waveform_data
      and waveform_data.sample_path == sample.path
      and waveform_data.data
      and #waveform_data.data > 0 then
    peaks = seq_env_downsample_peaks(waveform_data.data, build_w)
    duration = tonumber(waveform_data.duration) or tonumber(sample.duration)
  end
  if peaks and duration and duration > 0 then
    local entry = { peaks = peaks, duration = duration, width = build_w }
    seq_env_wave_cache[sample.path] = entry
    return seq_env_wave_peaks_for_width(entry, width), duration
  end
  return peaks, duration or tonumber(sample.duration)
end

-- Draw waveform peaks across [x, x+w]. bins are evenly spaced over the sample duration.
-- Optional t0, t1, duration zoom the same time window as the envelope editor.
function seq_draw_env_waveform(dl, x, y, w, h, peaks, t0, t1, duration)
  if not peaks or #peaks == 0 or w < 2 or h < 2 then return end
  local mid = y + h * 0.5
  local amp = h * 0.42
  local n = #peaks
  local dur = (duration and duration > 0.0001) and duration or 1.0
  local view0 = t0 or 0.0
  local view1 = t1 or dur
  if view1 <= view0 then view1 = view0 + 0.001 end
  local span = view1 - view0
  local col_fill = 0x5A7A9855
  local col_line = 0x8AA8C888
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  end
  local prev_x, prev_y = nil, nil
  for i = 1, n do
    local v = peaks[i] or 0.0
    local bin0 = ((i - 1) / n) * dur
    local bin1 = (i / n) * dur
    if bin1 >= view0 and bin0 <= view1 then
      local x0 = x + ((bin0 - view0) / span) * w
      local x1 = x + ((bin1 - view0) / span) * w
      local px = (x0 + x1) * 0.5
      local half = v * amp
      r.ImGui_DrawList_AddLine(dl, px, mid - half, px, mid + half, col_fill, math.max(1.0, x1 - x0))
      local py = mid - v * amp
      if prev_x then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, px, py, col_line, 1.0)
      end
      prev_x, prev_y = px, py
    end
  end
  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
end

function seq_draw_env_sparkline(dl, x, y, w, h, env, active, hovered)
  -- Compact non-interactive preview; click handling lives in the lane controls.
  env = seq_normalize_track_env(env)
  local bg = UI_THEME.bg_panel
  local edge = UI_THEME.border
  local edge_w = 1.0
  if active then
    bg = UI_THEME.accent_fill
    edge = UI_THEME.accent
  end
  if hovered then
    bg = active and UI_THEME.accent_fill_h or UI_THEME.surface_hvr
    edge = active and UI_THEME.accent_hvr or UI_THEME.border_hvr
    edge_w = 1.4
  end
  local shaped = seq_env_shape_active_norm(env)
  local line = shaped and 0x9FE3B5FF or 0x6A849EFF
  if hovered then
    line = shaped and 0xC8FFD8FF or 0x9EC0E0FF
  end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3.0)
  if hovered then
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0xFFFFFF18, 3.0)
  end
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, edge, 3.0, 0, edge_w)

  local pts = env.points
  local t1 = 1.0
  if pts and #pts > 0 then
    t1 = math.max(0.001, pts[#pts].t or 1.0)
  end
  local max_y = 1.0
  if pts then
    for i = 1, #pts do
      local a = pts[i].amp or 0.0
      if a > max_y then max_y = a end
    end
  end
  local steps = math.max(12, math.floor(w / 2))
  local xs, ys = seq_env_sparkline_points(env, x, y, w, h, t1, max_y, steps)
  if r.ImGui_DrawList_AddPolyline and r.new_array then
    -- One polyline instead of `steps` AddLine calls; the array is reused while
    -- the envelope and rect are unchanged (the usual case between frames).
    local cache = seq_env_sparkline_arrays
    local key = xs
    local arr = cache[key]
    if not arr then
      arr = r.new_array(#xs * 2)
      if arr then
        for i = 1, #xs do
          arr[i * 2 - 1] = xs[i]
          arr[i * 2] = ys[i]
        end
        cache[key] = arr
      end
    end
    if arr then
      r.ImGui_DrawList_AddPolyline(dl, arr, line, 0, 1.4)
      return
    end
  end
  for i = 2, #xs do
    r.ImGui_DrawList_AddLine(dl, xs[i - 1], ys[i - 1], xs[i], ys[i], line, 1.4)
  end
end

-- Sparkline geometry cache: last result per (x, y, w, h, steps) rect, reused
-- while the normalized envelope points match. Weak keys let stale point lists
-- (and their reaper.array) be collected.
seq_env_sparkline_geom = {}
seq_env_sparkline_arrays = setmetatable({}, { __mode = "k" })

function seq_env_points_equal(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local p, q = a[i], b[i]
    if p.t ~= q.t or p.amp ~= q.amp or p.curve ~= q.curve then
      return false
    end
  end
  return true
end

-- Samples the envelope at steps+1 evenly spaced times in [0, t1], walking the
-- segments once (times only increase) instead of searching per sample. Values
-- match seq_env_levels_at_norm exactly.
function seq_env_sparkline_points(env, x, y, w, h, t1, max_y, steps)
  local pts = env.points
  local rect_key = string.format("%.2f|%.2f|%.2f|%.2f|%d", x, y, w, h, steps)
  local hit = seq_env_sparkline_geom[rect_key]
  if hit and hit.t1 == t1 and hit.max_y == max_y and seq_env_points_equal(hit.pts, pts) then
    return hit.xs, hit.ys
  end
  local xs, ys = {}, {}
  local n = #pts
  local seg = 2
  for i = 0, steps do
    local t = (i / steps) * t1
    local amp
    if n == 0 then
      amp = 1.0
    elseif t <= (pts[1].t or 0.0) then
      amp = pts[1].amp or 1.0
    elseif t >= (pts[n].t or 0.0) then
      amp = pts[n].amp or 1.0
    else
      while seg < n and t > (pts[seg].t or 0.0) do
        seg = seg + 1
      end
      local a, b = pts[seg - 1], pts[seg]
      local span = math.max(0.0000001, (b.t or 0.0) - (a.t or 0.0))
      local u = (t - (a.t or 0.0)) / span
      amp = seq_env_seg_eval(a.amp or 1.0, b.amp or 1.0, u, a.curve)
    end
    xs[i + 1] = x + 2 + (i / steps) * (w - 4)
    ys[i + 1] = y + h - 2 - (amp / max_y) * (h - 4)
  end
  -- Bound the cache: one entry per sparkline on screen, reset if rects churn.
  seq_env_sparkline_geom_count = (seq_env_sparkline_geom_count or 0) + (hit and 0 or 1)
  if seq_env_sparkline_geom_count > 256 then
    seq_env_sparkline_geom = {}
    seq_env_sparkline_geom_count = 1
  end
  seq_env_sparkline_geom[rect_key] = { pts = pts, t1 = t1, max_y = max_y, xs = xs, ys = ys }
  return xs, ys
end

function seq_draw_env_trans_sustain_markers(dl, sample, time_to_x, iy0, iy1)
  if not sample or type(sample.transient_end) ~= "number" or sample.transient_end <= 0 then
    return
  end
  local trans_t = sample.transient_end
  local onset_t = (type(sample.onset) == "number" and sample.onset >= 0) and sample.onset or 0.0
  local sustain_t = sample_map_duration(sample)
  if not sustain_t or sustain_t <= 0 then
    sustain_t = tonumber(sample.duration) or trans_t
  end
  local ox = time_to_x(onset_t)
  local tx = time_to_x(trans_t)
  local sx = time_to_x(sustain_t)
  if tx > ox + 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, ox, iy0, tx, iy1, 0xFF6B3C33, 0)
  end
  if sx > tx + 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, tx, iy0, sx, iy1, 0x4A9CFF28, 0)
  end
  local col = 0x7CFF4AFF
  r.ImGui_DrawList_AddLine(dl, tx, iy0, tx, iy1, col, 1.6)
  local tri = 4.5
  r.ImGui_DrawList_AddTriangleFilled(dl, tx, iy0, tx - tri, iy0 + tri, tx + tri, iy0 + tri, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, tx, iy1, tx - tri, iy1 - tri, tx + tri, iy1 - tri, col)
  if (tx - ox) >= 12.0 then
    r.ImGui_DrawList_AddText(dl, ox + 3, iy0 + 2, 0xFFB08AFF, "T")
  end
  if (sx - tx) >= 12.0 then
    r.ImGui_DrawList_AddText(dl, tx + 4, iy0 + 2, 0xA8D4FFFF, "S")
  end
end

function seq_env_view_min_span(duration)
  duration = math.max(0.001, duration or 1.0)
  return math.max(0.02, duration * 0.02)
end

function seq_env_view_clamp(t0, t1, duration)
  duration = math.max(0.001, duration or 1.0)
  local min_span = seq_env_view_min_span(duration)
  local span = math.max(min_span, (t1 or duration) - (t0 or 0.0))
  if span > duration then span = duration end
  t0 = t0 or 0.0
  t1 = t0 + span
  if t0 < 0.0 then
    t1 = t1 - t0
    t0 = 0.0
  end
  if t1 > duration then
    t0 = t0 - (t1 - duration)
    t1 = duration
    if t0 < 0.0 then t0 = 0.0 end
  end
  return t0, t1
end

function seq_env_view_get(slot_id, duration)
  duration = math.max(0.001, duration or 1.0)
  local v = state.seq_env_view
  if not v or v.slot_id ~= slot_id then
    return 0.0, duration
  end
  return seq_env_view_clamp(v.t0 or 0.0, v.t1 or duration, duration)
end

function seq_env_view_set(slot_id, t0, t1, duration)
  t0, t1 = seq_env_view_clamp(t0, t1, duration)
  if (t1 - t0) >= (duration or 1.0) - 0.0001 then
    state.seq_env_view = nil
    return t0, t1
  end
  state.seq_env_view = { slot_id = slot_id, t0 = t0, t1 = t1 }
  return t0, t1
end

function seq_env_view_reset()
  state.seq_env_view = nil
  state.seq_env_view_pan = nil
end

-- Interactive free envelope editor. Click empty space to add a point, drag to
-- move, drag a segment to bow the curve. Alt-click or right-click a point to
-- delete; double-click a segment to reset it to linear.
-- Scroll zooms (waveform follows); Shift+scroll or middle-drag pans.
-- opts: { show_waveform = bool }
-- Returns changed, hovered, tip_text
function seq_render_env_graph_editor(dl, slot, x, y, w, h, opts)
  if not slot then return false, false, nil end
  opts = opts or {}
  seq_normalize_slot_mix(slot)
  local env = slot.env
  local changed = false
  local tip = nil

  local pad = 2.0
  local ix0, iy0 = x + pad, y + pad
  local ix1, iy1 = x + w - pad, y + h - pad
  local iw = math.max(8.0, ix1 - ix0)
  local ih = math.max(8.0, iy1 - iy0)

  local sample = nil
  local wave_peaks, wave_dur = nil, nil
  if opts.show_waveform and slot.sample_path then
    sample = find_sample_by_path(slot.sample_path)
    if not sample then
      sample = { path = slot.sample_path }
    end
    wave_peaks, wave_dur = seq_env_get_wave_peaks(sample, math.floor(iw))
  end
  local PREVIEW_LEN = 1.0
  if wave_dur and wave_dur > 0.0001 then
    PREVIEW_LEN = wave_dur
  else
    local sample_dur = sample and tonumber(sample.duration) or nil
    if sample_dur and sample_dur > 0.0001 then
      PREVIEW_LEN = sample_dur
    end
  end
  local AMP_MAX = SEQ_ENV_AMP_MAX or 3.0
  local view_t0, view_t1 = seq_env_view_get(slot.id, PREVIEW_LEN)
  local view_span = math.max(0.001, view_t1 - view_t0)

  local dragging = state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id == slot.id
  if not dragging then
    env = seq_env_sync_to_length(env, PREVIEW_LEN)
    slot.env = env
  end
  local points = env.points

  local function time_to_x(t)
    return ix0 + ((t - view_t0) / view_span) * iw
  end
  local function amp_to_y(a)
    return iy1 - (math.max(0.0, math.min(AMP_MAX, a)) / AMP_MAX) * ih
  end
  local function x_to_time(px)
    return view_t0 + math.max(0.0, math.min(1.0, (px - ix0) / iw)) * view_span
  end
  local function y_to_amp(py)
    return math.max(0.0, math.min(AMP_MAX, (iy1 - py) / ih * AMP_MAX))
  end

  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##seq_env_graph_" .. tostring(slot.id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  mx, my = mx or x, my or y
  if hovered and r.ImGui_SetItemUsingMouseWheel then
    r.ImGui_SetItemUsingMouseWheel(ctx)
  end

  -- Zoom / pan the shared envelope+waveform time window.
  local panning = state.seq_env_view_pan and state.seq_env_view_pan.slot_id == slot.id
  if hovered and not dragging then
    local wheel, wheel_h = 0.0, 0.0
    if r.ImGui_GetMouseWheel then
      wheel, wheel_h = r.ImGui_GetMouseWheel(ctx)
      wheel_h = wheel_h or 0.0
    end
    local shift = is_shift_down()
    if wheel ~= 0.0 and not shift then
      local pivot = x_to_time(mx)
      local new_span = view_span * math.exp(-wheel * 0.18)
      new_span = math.max(seq_env_view_min_span(PREVIEW_LEN), math.min(PREVIEW_LEN, new_span))
      local u = (pivot - view_t0) / view_span
      view_t0 = pivot - u * new_span
      view_t1 = view_t0 + new_span
      view_t0, view_t1 = seq_env_view_set(slot.id, view_t0, view_t1, PREVIEW_LEN)
      view_span = math.max(0.001, view_t1 - view_t0)
    elseif (shift and wheel ~= 0.0) or wheel_h ~= 0.0 then
      local pan = ((shift and wheel ~= 0.0) and -wheel or -wheel_h) * view_span * 0.12
      view_t0, view_t1 = seq_env_view_set(slot.id, view_t0 + pan, view_t1 + pan, PREVIEW_LEN)
      view_span = math.max(0.001, view_t1 - view_t0)
    end
    if r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 2) then
      state.seq_env_view_pan = { slot_id = slot.id, mx = mx, t0 = view_t0, t1 = view_t1 }
      panning = true
    end
  end
  if panning then
    local pan = state.seq_env_view_pan
    if pan and r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 2) then
      local dt = -(mx - pan.mx) / iw * (pan.t1 - pan.t0)
      view_t0, view_t1 = seq_env_view_set(slot.id, pan.t0 + dt, pan.t1 + dt, PREVIEW_LEN)
      view_span = math.max(0.001, view_t1 - view_t0)
    else
      state.seq_env_view_pan = nil
      panning = false
    end
  end

  local live = seq_env_is_active(env) or active or hovered
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, live and 0x15241AEE or 0x121814EE, 4.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, (active or hovered) and UI_THEME.accent or UI_THEME.border, 4.0, 0, 1.2)
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, ix0, iy0, ix1, iy1, true)
  end
  if wave_peaks then
    seq_draw_env_waveform(dl, ix0, iy0, iw, ih, wave_peaks, view_t0, view_t1, PREVIEW_LEN)
  end
  if sample and sample.path then
    local grip_w, grip_h = 16, 14
    local gx, gy = ix1 - grip_w - 1, iy0 + 1
    r.ImGui_SetCursorScreenPos(ctx, gx, gy)
    r.ImGui_InvisibleButton(ctx, "##seq_env_wave_drag_" .. tostring(slot.id), grip_w, grip_h)
    local grip_hov = r.ImGui_IsItemHovered(ctx)
    local grip_col = grip_hov and UI_THEME.accent or UI_THEME.text_dim
    for row = 0, 1 do
      for col = 0, 2 do
        r.ImGui_DrawList_AddCircleFilled(dl,
          gx + 4 + col * 4, gy + 5 + row * 5, 1.2, grip_col, 6)
      end
    end
    if grip_hov and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "Drag to drop this sample")
    end
    if waveform_drag_should_start(grip_hov) then
      begin_waveform_sample_drag(sample)
    end
  end
  seq_draw_env_trans_sustain_markers(dl, sample, time_to_x, iy0, iy1)
  local unity_y = amp_to_y(1.0)
  r.ImGui_DrawList_AddLine(dl, ix0, unity_y, ix1, unity_y, 0xFFFFFF22, 1.0)

  local line_col = live and 0x9FE3B5FF or 0x6A849EFF
  local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
  end
  local function dist_point_seg(px, py, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local l2 = dx * dx + dy * dy
    if l2 < 0.0001 then
      return math.sqrt(dist2(px, py, x0, y0)), 0.0
    end
    local u = ((px - x0) * dx + (py - y0) * dy) / l2
    if u < 0.0 then u = 0.0 elseif u > 1.0 then u = 1.0 end
    local qx, qy = x0 + dx * u, y0 + dy * u
    return math.sqrt(dist2(px, py, qx, qy)), u
  end
  local function seg_sample_count(t0, t1)
    local px_span = math.abs(time_to_x(t1) - time_to_x(t0))
    return math.max(8, math.min(28, math.floor(px_span / 6.0 + 0.5)))
  end
  local function draw_env_segment(x0, y0, t0, amp0, t1, amp1, curve, col, thickness)
    local steps = seg_sample_count(t0, t1)
    local prev_x, prev_y = x0, y0
    for k = 1, steps do
      local u = k / steps
      local sx = time_to_x(t0 + (t1 - t0) * u)
      local sy = amp_to_y(seq_env_seg_eval(amp0, amp1, u, curve))
      r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, sx, sy, col, thickness)
      prev_x, prev_y = sx, sy
    end
  end

  local hit_r = 8.0
  local hit_r2 = hit_r * hit_r
  local nearest_idx, nearest_d = nil, hit_r2
  for i = 1, #points do
    local hx = time_to_x(points[i].t or 0.0)
    if hx >= ix0 - 6 and hx <= ix1 + 6 then
      local d = dist2(mx, my, hx, amp_to_y(points[i].amp or 1.0))
      if d <= nearest_d then
        nearest_d = d
        nearest_idx = i
      end
    end
  end

  local seg_hit_px = 10.0
  local nearest_seg, nearest_seg_d, nearest_seg_u = nil, seg_hit_px, 0.5
  if not nearest_idx then
    for i = 1, #points - 1 do
      local a, b = points[i], points[i + 1]
      local t0, t1 = a.t or 0.0, b.t or 0.0
      local steps = seg_sample_count(t0, t1)
      local px0 = time_to_x(t0)
      local py0 = amp_to_y(a.amp or 1.0)
      for k = 1, steps do
        local u1 = k / steps
        local px1 = time_to_x(t0 + (t1 - t0) * u1)
        local py1 = amp_to_y(seq_env_seg_eval(a.amp, b.amp, u1, a.curve))
        local d, _ = dist_point_seg(mx, my, px0, py0, px1, py1)
        if d <= nearest_seg_d then
          nearest_seg_d = d
          nearest_seg = i
          nearest_seg_u = (k - 0.5) / steps
        end
        px0, py0 = px1, py1
      end
    end
  end
  if nearest_seg then
    nearest_seg_u = math.max(0.08, math.min(0.92, (mx - time_to_x(points[nearest_seg].t or 0.0))
      / math.max(1.0, time_to_x(points[nearest_seg + 1].t or 0.0) - time_to_x(points[nearest_seg].t or 0.0))))
  end

  local alt = is_alt_down()
  local shift = is_shift_down()
  local right_clicked = hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 1)
  local left_clicked = hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
  local dbl = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local drag = state.seq_env_graph_drag
  local deleting = (not panning) and nearest_idx and #points > 1 and (right_clicked or (left_clicked and alt))
  local reset_curve = (not panning) and dbl and nearest_seg and not nearest_idx

  if hovered and not dragging and dbl and not nearest_seg and not nearest_idx then
    seq_env_view_reset()
    view_t0, view_t1 = 0.0, PREVIEW_LEN
    view_span = PREVIEW_LEN
  end

  if panning or (dbl and not reset_curve) then
    -- Pan / double-click zoom owns this click.
  elseif reset_curve then
    points[nearest_seg].curve = 0.0
    env.points = points
    slot.env = seq_normalize_track_env(env)
    env = slot.env
    points = env.points
    changed = true
    tip = "Linear"
    state.seq_env_graph_drag = { slot_id = slot.id, handle = "none" }
    drag = state.seq_env_graph_drag
  elseif deleting then
    table.remove(points, nearest_idx)
    env.points = points
    slot.env = seq_normalize_track_env(env)
    env = slot.env
    points = env.points
    changed = true
    tip = "Delete point"
    state.seq_env_graph_drag = { slot_id = slot.id, handle = "none" }
    drag = state.seq_env_graph_drag
  elseif active and not alt then
    if drag and drag.slot_id == slot.id and drag.handle == "none" then
      -- Swallow the rest of the click that deleted a point or reset a curve.
    else
      if (not drag) or drag.slot_id ~= slot.id then
        if nearest_idx then
          state.seq_env_graph_drag = { slot_id = slot.id, handle = nearest_idx }
        elseif nearest_seg then
          state.seq_env_graph_drag = {
            slot_id = slot.id, handle = "curve", seg = nearest_seg, u = nearest_seg_u,
          }
        else
          local idx = nil
          if #points < SEQ_ENV_POINT_LIMIT then
            idx = seq_env_insert_point(points, x_to_time(mx), y_to_amp(my))
            changed = true
          else
            local best_d = 1e12
            for i = 1, #points do
              local d = dist2(mx, my, time_to_x(points[i].t or 0.0), amp_to_y(points[i].amp or 1.0))
              if d < best_d then
                best_d = d
                idx = i
              end
            end
          end
          state.seq_env_graph_drag = { slot_id = slot.id, handle = idx or 1 }
        end
        drag = state.seq_env_graph_drag
      end
      if drag and drag.handle == "curve" then
        local idx = tonumber(drag.seg)
        local a = idx and points[idx]
        local b = idx and points[idx + 1]
        if a and b then
          local t0, t1 = a.t or 0.0, b.t or 0.0
          local span_x = math.max(1.0, time_to_x(t1) - time_to_x(t0))
          local u = drag.u or 0.5
          if span_x > 1.0 then
            u = math.max(0.08, math.min(0.92, (mx - time_to_x(t0)) / span_x))
          end
          a.curve = seq_env_seg_curve_for_amp(a.amp, b.amp, u, y_to_amp(my))
          tip = string.format("Curve %+.2f  ·  double-click to flatten", a.curve)
          changed = true
        end
      else
        local idx = tonumber(drag and drag.handle)
        local p = idx and points[idx]
        if p then
          local tmin = 0.0
          local tmax = PREVIEW_LEN
          if idx > 1 then
            tmin = (points[idx - 1].t or 0.0) + 0.0005
          end
          if idx < #points then
            tmax = (points[idx + 1].t or PREVIEW_LEN) - 0.0005
          end
          if tmax < tmin then tmax = tmin end
          p.t = math.max(tmin, math.min(tmax, x_to_time(mx)))
          p.amp = shift and 1.0 or y_to_amp(my)
          tip = seq_env_format_point_tip(p.t, p.amp)
          changed = true
        end
      end
    end
  elseif drag and drag.slot_id == slot.id then
    slot.env = seq_normalize_track_env(env)
    state.seq_env_graph_drag = nil
  end

  env = slot.env
  points = env.points
  local drag_now = state.seq_env_graph_drag
  local curve_idx = nil
  if drag_now and drag_now.slot_id == slot.id and drag_now.handle == "curve" then
    curve_idx = tonumber(drag_now.seg)
  elseif nearest_seg then
    curve_idx = nearest_seg
  end
  if points and #points > 0 then
    local hold_y = amp_to_y(points[1].amp or 1.0)
    if (points[1].t or 0.0) > 0.0005 then
      r.ImGui_DrawList_AddLine(dl, time_to_x(0.0), hold_y, time_to_x(points[1].t), hold_y, line_col, 1.8)
    end
    for i = 1, #points - 1 do
      local a, b = points[i], points[i + 1]
      local hot = (curve_idx == i)
      draw_env_segment(
        time_to_x(a.t or 0.0), amp_to_y(a.amp or 1.0),
        a.t or 0.0, a.amp or 1.0,
        b.t or 0.0, b.amp or 1.0,
        a.curve,
        hot and (UI_THEME.accent_hvr or 0xC8FFD8FF) or line_col,
        hot and 2.4 or 1.8
      )
    end
    local last = points[#points]
    if (last.t or 0.0) < PREVIEW_LEN - 0.0005 then
      local ly = amp_to_y(last.amp or 1.0)
      r.ImGui_DrawList_AddLine(dl, time_to_x(last.t or 0.0), ly, time_to_x(PREVIEW_LEN), ly, line_col, 1.8)
    end
  end
  if curve_idx and points[curve_idx] and points[curve_idx + 1] then
    local a, b = points[curve_idx], points[curve_idx + 1]
    local mid_t = (a.t or 0.0) + ((b.t or 0.0) - (a.t or 0.0)) * 0.5
    local mid_amp = seq_env_seg_eval(a.amp, b.amp, 0.5, a.curve)
    local mxh, myh = time_to_x(mid_t), amp_to_y(mid_amp)
    r.ImGui_DrawList_AddCircleFilled(dl, mxh, myh, 3.2, 0xFFFFFFFF, 10)
    r.ImGui_DrawList_AddCircle(dl, mxh, myh, 4.4, UI_THEME.accent_hvr or 0xC8FFD8FF, 10, 1.2)
  end

  local active_idx = (drag_now and drag_now.slot_id == slot.id)
      and tonumber(drag_now.handle) or nearest_idx

  for i = 1, #points do
    local p = points[i]
    local hx = time_to_x(p.t or 0.0)
    if hx >= ix0 - 4 and hx <= ix1 + 4 then
      local hy = amp_to_y(p.amp or 1.0)
      local hot = active_idx == i
      local rad = hot and 4.5 or 3.5
      r.ImGui_DrawList_AddCircleFilled(dl, hx, hy, rad, hot and 0xFFFFFFFF or UI_THEME.text, 12)
      r.ImGui_DrawList_AddCircle(dl, hx, hy, rad + 1.2, hot and UI_THEME.accent_hvr or UI_THEME.accent, 12, 1.1)
    end
  end
  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end

  if view_span < PREVIEW_LEN - 0.0005 then
    local bar_h = 3.0
    local by = iy1 - bar_h
    r.ImGui_DrawList_AddRectFilled(dl, ix0, by, ix1, iy1, 0xFFFFFF14, 1.0)
    local bx0 = ix0 + (view_t0 / PREVIEW_LEN) * iw
    local bx1 = ix0 + (view_t1 / PREVIEW_LEN) * iw
    r.ImGui_DrawList_AddRectFilled(dl, bx0, by, bx1, iy1, 0x9FE3B5AA, 1.0)
    local label = string.format("%.0f–%.0f ms", view_t0 * 1000.0, view_t1 * 1000.0)
    r.ImGui_DrawList_AddText(dl, ix0 + 4, iy0 + 2, UI_THEME.text_dim, label)
  end

  if not tip and hovered then
    if nearest_idx then
      local p = points[nearest_idx]
      tip = seq_env_format_point_tip(p.t, p.amp) .. "  ·  Alt/RMB delete"
    elseif nearest_seg then
      local c = points[nearest_seg].curve or 0.0
      if math.abs(c) > 0.001 then
        tip = string.format("Drag to reshape  ·  %.2f  ·  double-click: flatten", c)
      else
        tip = "Drag segment to change curve  ·  double-click: flatten"
      end
    else
      tip = "Click: add point  ·  Drag segment: curve  ·  Scroll: zoom"
    end
  end

  return changed, hovered or active or panning, tip
end

function seq_ms_button(id, dl, x, y, size, label, active, color_on)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg = active and (color_on or UI_THEME.accent_fill) or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)
  local edge = hovered and UI_THEME.accent_hvr or (active and (color_on or UI_THEME.accent) or UI_THEME.border)
  local text = active and 0xFFFFFFFF or (hovered and UI_THEME.text or UI_THEME.text_dim)
  ui_draw_panel(dl, x, y, x + size, y + size, 6.0, bg, edge, hovered, pressed)
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, x + (size - tw) * 0.5, y + (size - th) * 0.5 + (pressed and 1.0 or 0.0), text, label)
  return clicked
end

function seq_midi_note_button(id, dl, x, y, w, h, slot, active)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local learning = state.seq_midi_learn_slot_id == (slot and slot.id)
  local pulse = learning and (0.5 + 0.5 * math.sin(r.time_precise() * 8.0)) or 0.0
  local bg = (active or learning) and UI_THEME.accent_fill or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)
  local edge = learning and UI_THEME.accent_hvr or ((hovered or active) and UI_THEME.accent or UI_THEME.border)
  if learning then
    local a = math.floor(80 + pulse * 140)
    edge = build_color_rrgbbaa(30, 255, 94, a)
  end
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered, pressed)
  local label = learning and "…" or seq_midi_slot_label(slot)
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local text = (active or learning) and 0xFFFFFFFF or (hovered and UI_THEME.text or UI_THEME.text_dim)
  r.ImGui_DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - th) * 0.5 + (pressed and 1.0 or 0.0), text, label)
  return clicked
end

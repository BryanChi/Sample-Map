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
-- With env (normalized), the original is drawn faint and the waveform as the
-- envelope shapes it is drawn on top, so edits show what the hit will sound like.
function seq_draw_env_waveform(dl, x, y, w, h, peaks, t0, t1, duration, env)
  if not peaks or #peaks == 0 or w < 2 or h < 2 then return end
  local mid = y + h * 0.5
  local amp = h * 0.42
  local n = #peaks
  local dur = (duration and duration > 0.0001) and duration or 1.0
  local view0 = t0 or 0.0
  local view1 = t1 or dur
  if view1 <= view0 then view1 = view0 + 0.001 end
  local span = view1 - view0
  local col_fill = env and 0x5A7A9826 or 0x5A7A9855
  local col_line = env and 0x8AA8C830 or 0x8AA8C888
  local shaped_fill = 0x7FB4E070
  local shaped_line = 0xB4D6F4C0
  local max_half = h * 0.5 - 1.0
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  end
  local prev_x, prev_y, prev_sy = nil, nil, nil
  for i = 1, n do
    local v = peaks[i] or 0.0
    local bin0 = ((i - 1) / n) * dur
    local bin1 = (i / n) * dur
    if bin1 >= view0 and bin0 <= view1 then
      local x0 = x + ((bin0 - view0) / span) * w
      local x1 = x + ((bin1 - view0) / span) * w
      local px = (x0 + x1) * 0.5
      local half = v * amp
      local bar_w = math.max(1.0, x1 - x0)
      r.ImGui_DrawList_AddLine(dl, px, mid - half, px, mid + half, col_fill, bar_w)
      local py = mid - v * amp
      if prev_x then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, px, py, col_line, 1.0)
      end
      if env then
        local g = seq_env_levels_at_norm(env, (bin0 + bin1) * 0.5)
        local sh = math.min(max_half, half * g)
        if sh > 0.25 then
          r.ImGui_DrawList_AddLine(dl, px, mid - sh, px, mid + sh, shaped_fill, bar_w)
        end
        py = mid - sh
        if prev_x and prev_sy then
          r.ImGui_DrawList_AddLine(dl, prev_x, prev_sy, px, py, shaped_line, 1.0)
        end
        prev_sy = py
        py = mid - v * amp
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
  if not seq_env_is_normalized(env) then
    env = seq_normalize_track_env(env)
  end
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
  local line = shaped and ui_tc(0x9FE3B5FF) or 0x6A849EFF
  if hovered then
    line = shaped and ui_tc(0xC8FFD8FF) or 0x9EC0E0FF
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
  -- Copy the points: env may be the live slot.env, which is edited in place.
  local snap = {}
  for i = 1, n do
    local p = pts[i]
    snap[i] = { t = p.t, amp = p.amp, curve = p.curve }
  end
  seq_env_sparkline_geom[rect_key] = { pts = snap, t1 = t1, max_y = max_y, xs = xs, ys = ys }
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

-- dB rows and millisecond columns behind the envelope. Labels sit inside the
-- plot edges so the graph keeps its full width.
SEQ_ENV_GRID_DB = { { 2.0, "+6" }, { 1.0, "0 dB" }, { 0.5, "-6" }, { 0.25, "-12" } }
SEQ_ENV_GRID_MS = { 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 }

function seq_draw_env_grid(dl, ix0, iy0, ix1, iy1, t0, t1, amp_max)
  local ih = iy1 - iy0
  local iw = ix1 - ix0
  if iw < 20 or ih < 20 then
    return
  end
  local line_col = 0xFFFFFF0D
  local text_col = ui_tc(0x9B9CA0A0)
  for _, row in ipairs(SEQ_ENV_GRID_DB) do
    local y = iy1 - (row[1] / amp_max) * ih
    if y > iy0 + 8 and y < iy1 - 8 then
      if row[1] ~= 1.0 then
        r.ImGui_DrawList_AddLine(dl, ix0, y, ix1, y, line_col, 1.0)
      end
      local _, th = r.ImGui_CalcTextSize(ctx, row[2])
      r.ImGui_DrawList_AddText(dl, ix0 + 3, y - (th or 12) - 1, text_col, row[2])
    end
  end
  local span_ms = math.max(0.001, (t1 - t0) * 1000.0)
  local step = SEQ_ENV_GRID_MS[#SEQ_ENV_GRID_MS]
  for _, s in ipairs(SEQ_ENV_GRID_MS) do
    if span_ms / s <= math.max(2, math.floor(iw / 70)) then
      step = s
      break
    end
  end
  local first = math.ceil((t0 * 1000.0) / step) * step
  local ms = first
  local guard = 0
  while ms <= t1 * 1000.0 and guard < 64 do
    guard = guard + 1
    local x = ix0 + ((ms / 1000.0 - t0) / (t1 - t0)) * iw
    if x > ix0 + 1 then
      r.ImGui_DrawList_AddLine(dl, x, iy0, x, iy1, line_col, 1.0)
      local label = (ms >= 1000) and string.format("%g s", ms / 1000.0) or string.format("%g ms", ms)
      local tw, th = r.ImGui_CalcTextSize(ctx, label)
      if x + 3 + (tw or 0) < ix1 - 2 then
        r.ImGui_DrawList_AddText(dl, x + 3, iy1 - (th or 12) - 2, text_col, label)
      end
    end
    ms = ms + step
  end
end

-- ===== Envelope edges: fade in, end position, fade out ======================
-- These live in the ordinary points so every player (arrange items, live MIDI)
-- hears them: a fade in is a first point at 0 amp rising to the next point;
-- the end is where the envelope drops to 0 and stays there, and the fade out
-- is the segment that leads into it.

SEQ_ENV_SILENT = 0.0001
SEQ_ENV_CUT = 0.0008   -- a "hard" end: hold point this far before the end

function seq_env_edges(points, len)
  local e = { len = len, end_t = len }
  local n = #points
  if n >= 2 and (points[1].t or 0.0) <= 0.0005 and (points[1].amp or 1.0) <= SEQ_ENV_SILENT
      and (points[2].amp or 0.0) > SEQ_ENV_SILENT then
    e.fi = true
    e.fi_len = points[2].t or 0.0
  end
  local k = nil
  for i = n, 1, -1 do
    if (points[i].amp or 1.0) <= SEQ_ENV_SILENT then
      k = i
    else
      break
    end
  end
  if k and k >= 2 then
    e.k = k
    e.end_t = points[k].t or len
    e.fo_start = points[k - 1].t or e.end_t
    e.fo_len = e.end_t - e.fo_start
    if e.fo_len <= SEQ_ENV_CUT + 0.0002 then
      e.fo_len = 0.0
    end
  end
  return e
end

-- Cut the envelope at t_end: hold the current level, drop to 0, silent to len.
function seq_env_make_end(points, t_end, len)
  t_end = math.max(SEQ_ENV_CUT * 2, math.min(len, t_end))
  local lvl = seq_env_levels_at_norm({ points = points }, t_end - SEQ_ENV_CUT)
  for i = #points, 1, -1 do
    if (points[i].t or 0.0) >= t_end - SEQ_ENV_CUT - 0.0002 then
      table.remove(points, i)
    end
  end
  points[#points + 1] = { t = t_end - SEQ_ENV_CUT, amp = lvl, curve = 0.0 }
  points[#points + 1] = { t = t_end, amp = 0.0, curve = 0.0 }
  if t_end < len - 0.0005 then
    points[#points + 1] = { t = len, amp = 0.0, curve = 0.0 }
  end
end

-- Remove the end: the level before the cut carries on to the end of the sample.
function seq_env_clear_end(points, len)
  local e = seq_env_edges(points, len)
  if not e.k then
    return false
  end
  local lvl = points[e.k - 1].amp or 1.0
  for i = #points, e.k, -1 do
    table.remove(points, i)
  end
  points[#points + 1] = { t = len, amp = lvl, curve = 0.0 }
  return true
end

function seq_env_set_fade_in(points, fi_len, len)
  local e = seq_env_edges(points, len)
  local limit = (e.k and (points[e.k - 1].t or len) or len) - 0.0005
  if e.fi then
    if points[3] then
      limit = math.min(limit, (points[3].t or len) - 0.0005)
    end
    if fi_len <= 0.0008 then
      points[1].amp = points[2].amp or 1.0
      return
    end
    points[2].t = math.max(0.0008, math.min(limit, fi_len))
    return
  end
  if fi_len <= 0.0008 then
    return
  end
  -- New fade: silence at 0, rising to the level the envelope had there.
  local first_t = points[1] and (points[1].t or 0.0) or len
  if first_t <= 0.0005 and points[2] then
    limit = math.min(limit, (points[2].t or len) - 0.0005)
  elseif first_t > 0.0005 then
    limit = math.min(limit, first_t - 0.0005)
  end
  local t = math.max(0.0008, math.min(limit, fi_len))
  local lvl = seq_env_levels_at_norm({ points = points }, t)
  if first_t <= 0.0005 then
    points[1].amp = 0.0
  else
    table.insert(points, 1, { t = 0.0, amp = 0.0, curve = 0.0 })
  end
  table.insert(points, 2, { t = t, amp = lvl, curve = 0.0 })
end

function seq_env_set_fade_out(points, fo_start, len)
  local e = seq_env_edges(points, len)
  if not e.k then
    seq_env_make_end(points, len, len)
    e = seq_env_edges(points, len)
    if not e.k then
      return
    end
  end
  local k = e.k
  local tmin = (k >= 3 and (points[k - 2].t or 0.0) or 0.0) + 0.0005
  if e.fi and k - 1 == 2 then
    tmin = math.max(tmin, 0.0008)
  end
  local tmax = e.end_t - SEQ_ENV_CUT
  points[k - 1].t = math.max(tmin, math.min(tmax, fo_start))
end

function seq_env_move_end(points, t_end, len)
  local e = seq_env_edges(points, len)
  if not e.k then
    if t_end < len - 0.002 then
      seq_env_make_end(points, t_end, len)
    end
    return
  end
  local k = e.k
  local tmin = (points[k - 1].t or 0.0) + SEQ_ENV_CUT
  if t_end >= len - 0.0005 then
    t_end = len
  end
  t_end = math.max(tmin, math.min(len, t_end))
  points[k].t = t_end
  for i = #points, k + 1, -1 do
    if (points[i].t or 0.0) <= t_end + 0.0002 then
      table.remove(points, i)
    end
  end
  if t_end < len - 0.0005 and (points[#points].t or 0.0) < len - 0.0005 then
    points[#points + 1] = { t = len, amp = 0.0, curve = 0.0 }
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
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, live and 0x15241AEE or ui_tc(0x151619EE), 4.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, (active or hovered) and UI_THEME.accent or UI_THEME.border, 4.0, 0, 1.2)
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, ix0, iy0, ix1, iy1, true)
  end
  seq_draw_env_grid(dl, ix0, iy0, ix1, iy1, view_t0, view_t1, AMP_MAX)
  if wave_peaks then
    seq_draw_env_waveform(dl, ix0, iy0, iw, ih, wave_peaks, view_t0, view_t1, PREVIEW_LEN,
      opts.shaped_waveform and env or nil)
  end
  seq_draw_env_trans_sustain_markers(dl, sample, time_to_x, iy0, iy1)
  local unity_y = amp_to_y(1.0)
  r.ImGui_DrawList_AddLine(dl, ix0, unity_y, ix1, unity_y, 0xFFFFFF30, 1.0)

  local line_col = live and ui_tc(0x9FE3B5FF) or 0x6A849EFF
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
  local area_col = live and ui_tc(0x9FE3B51C) or 0x6A849E14
  local function draw_env_segment(x0, y0, t0, amp0, t1, amp1, curve, col, thickness)
    local steps = seg_sample_count(t0, t1)
    local prev_x, prev_y = x0, y0
    for k = 1, steps do
      local u = k / steps
      local sx = time_to_x(t0 + (t1 - t0) * u)
      local sy = amp_to_y(seq_env_seg_eval(amp0, amp1, u, curve))
      if r.ImGui_DrawList_AddQuadFilled and sx > prev_x then
        r.ImGui_DrawList_AddQuadFilled(dl, prev_x, prev_y, sx, sy, sx, iy1, prev_x, iy1, area_col)
      end
      r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, sx, sy, col, thickness)
      prev_x, prev_y = sx, sy
    end
  end
  local function draw_hold(t0, t1, amp)
    local hx0, hx1 = time_to_x(t0), time_to_x(t1)
    local hy = amp_to_y(amp)
    if hx1 > hx0 then
      r.ImGui_DrawList_AddRectFilled(dl, hx0, hy, hx1, iy1, area_col, 0)
      r.ImGui_DrawList_AddLine(dl, hx0, hy, hx1, hy, line_col, 1.8)
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

  -- Edge handles: fade-in knob, fade-out knob (top) and the end line.
  local edges = seq_env_edges(points, PREVIEW_LEN)
  local knob_y = iy0 + 8.0
  local fi_x = time_to_x(edges.fi and edges.fi_len or 0.0)
  local end_x = time_to_x(edges.end_t)
  local fo_x = time_to_x(edges.k and edges.fo_start or edges.end_t)
  local edge_hot = nil
  if hovered and not dragging and not panning then
    if dist2(mx, my, fo_x, knob_y) <= 49.0 then
      edge_hot = "fo"
    elseif dist2(mx, my, fi_x, knob_y) <= 49.0 then
      edge_hot = "fi"
    elseif math.abs(mx - end_x) <= 4.0 and my > knob_y + 7.0 then
      edge_hot = "end"
    end
  elseif dragging and state.seq_env_graph_drag then
    local hnd = state.seq_env_graph_drag.handle
    if hnd == "fi" or hnd == "fo" or hnd == "end" then
      edge_hot = hnd
    end
  end
  if edge_hot then
    nearest_idx = nil
    nearest_seg = nil
  end

  local alt = is_alt_down()
  local shift = is_shift_down()
  local right_clicked = hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 1)
  local left_clicked = hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
  local dbl = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local drag = state.seq_env_graph_drag
  local deleting = (not panning) and nearest_idx and #points > 1 and (right_clicked or (left_clicked and alt))
  local reset_curve = (not panning) and dbl and nearest_seg and not nearest_idx

  if hovered and not dragging and dbl and edge_hot then
    -- Double-click a knob or the end line to remove that fade or the end.
    if edge_hot == "fi" then
      seq_env_set_fade_in(points, 0.0, PREVIEW_LEN)
    elseif edge_hot == "fo" then
      local e = seq_env_edges(points, PREVIEW_LEN)
      if e.k then
        seq_env_make_end(points, e.end_t, PREVIEW_LEN)
      end
    else
      seq_env_clear_end(points, PREVIEW_LEN)
    end
    slot.env = seq_normalize_track_env({ points = points })
    env = slot.env
    points = env.points
    changed = true
    state.seq_env_graph_drag = { slot_id = slot.id, handle = "none" }
    drag = state.seq_env_graph_drag
  elseif hovered and not dragging and dbl and not nearest_seg and not nearest_idx then
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
        if edge_hot then
          state.seq_env_graph_drag = { slot_id = slot.id, handle = edge_hot }
        elseif nearest_idx then
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
      if drag and (drag.handle == "fi" or drag.handle == "fo" or drag.handle == "end") then
        local t = x_to_time(mx)
        if drag.handle == "fi" then
          seq_env_set_fade_in(points, t, PREVIEW_LEN)
        elseif drag.handle == "fo" then
          seq_env_set_fade_out(points, t, PREVIEW_LEN)
        else
          seq_env_move_end(points, t, PREVIEW_LEN)
        end
        changed = true
      elseif drag and drag.handle == "curve" then
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
          tip = string.format("Curve: %+.2f", a.curve)
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
    if (points[1].t or 0.0) > 0.0005 then
      draw_hold(0.0, points[1].t, points[1].amp or 1.0)
    end
    for i = 1, #points - 1 do
      local a, b = points[i], points[i + 1]
      local hot = (curve_idx == i)
      draw_env_segment(
        time_to_x(a.t or 0.0), amp_to_y(a.amp or 1.0),
        a.t or 0.0, a.amp or 1.0,
        b.t or 0.0, b.amp or 1.0,
        a.curve,
        hot and (UI_THEME.accent_hvr or ui_tc(0xC8FFD8FF)) or line_col,
        hot and 2.4 or 1.8
      )
    end
    local last = points[#points]
    if (last.t or 0.0) < PREVIEW_LEN - 0.0005 then
      draw_hold(last.t or 0.0, PREVIEW_LEN, last.amp or 1.0)
    end
  end
  if curve_idx and points[curve_idx] and points[curve_idx + 1] then
    local a, b = points[curve_idx], points[curve_idx + 1]
    local mid_t = (a.t or 0.0) + ((b.t or 0.0) - (a.t or 0.0)) * 0.5
    local mid_amp = seq_env_seg_eval(a.amp, b.amp, 0.5, a.curve)
    local mxh, myh = time_to_x(mid_t), amp_to_y(mid_amp)
    r.ImGui_DrawList_AddCircleFilled(dl, mxh, myh, 3.2, 0xFFFFFFFF, 10)
    r.ImGui_DrawList_AddCircle(dl, mxh, myh, 4.4, UI_THEME.accent_hvr or ui_tc(0xC8FFD8FF), 10, 1.2)
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
  -- Edges: silence after the end, the end line with its grab tab, and the
  -- two fade knobs with a bar showing each fade's length.
  local ed = seq_env_edges(points, PREVIEW_LEN)
  local e_end_x = time_to_x(ed.end_t)
  local e_fi_x = time_to_x(ed.fi and ed.fi_len or 0.0)
  local e_fo_x = time_to_x(ed.k and ed.fo_start or ed.end_t)
  local end_col = ed.k and 0xFFB84DFF or 0xFFB84D70
  if ed.k and e_end_x < ix1 then
    r.ImGui_DrawList_AddRectFilled(dl, e_end_x, iy0, ix1, iy1, 0x00000070, 0)
  end
  r.ImGui_DrawList_AddLine(dl, e_end_x, iy0, e_end_x, iy1, end_col, edge_hot == "end" and 2.4 or 1.5)
  local tab_hot = edge_hot == "end"
  r.ImGui_DrawList_AddRectFilled(dl, e_end_x - 4, iy1 - 16, e_end_x + 4, iy1 - 2,
    tab_hot and 0xFFD699FF or end_col, 2.0)
  r.ImGui_DrawList_AddLine(dl, ix0 + 0.5, iy0, ix0 + 0.5, iy1, 0x7FD7FF70, 1.5)
  local fade_col = 0x7FD7FFFF
  if ed.fi and e_fi_x > ix0 + 1 then
    r.ImGui_DrawList_AddLine(dl, ix0, knob_y, e_fi_x, knob_y, 0x7FD7FF80, 2.0)
  end
  if ed.k and ed.fo_len > 0 and e_end_x > e_fo_x + 1 then
    r.ImGui_DrawList_AddLine(dl, e_fo_x, knob_y, e_end_x, knob_y, 0xFFB84D90, 2.0)
  end
  local function knob(kx, hot, col)
    local rr = hot and 5.5 or 4.5
    r.ImGui_DrawList_AddRectFilled(dl, kx - rr, knob_y - rr, kx + rr, knob_y + rr, hot and 0xFFFFFFFF or col, 2.0)
    r.ImGui_DrawList_AddRect(dl, kx - rr, knob_y - rr, kx + rr, knob_y + rr, 0x000000AA, 2.0, 0, 1.0)
  end
  knob(e_fi_x, edge_hot == "fi", fade_col)
  knob(e_fo_x, edge_hot == "fo", end_col)

  -- Value readouts show only while dragging; hover hints go to the caller's tip.
  local drag_live = state.seq_env_graph_drag and state.seq_env_graph_drag.slot_id == slot.id
    and r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0)
  local edge_label = nil
  if not drag_live then
    edge_label = nil
  elseif edge_hot == "fi" then
    edge_label = string.format("Fade in %.0f ms", (ed.fi and ed.fi_len or 0.0) * 1000.0)
  elseif edge_hot == "fo" then
    edge_label = string.format("Fade out %.0f ms", (ed.k and ed.fo_len or 0.0) * 1000.0)
  elseif edge_hot == "end" then
    edge_label = ed.k and string.format("End %.0f ms", ed.end_t * 1000.0) or "End: sample end"
  end
  if edge_label then
    local tw, th = r.ImGui_CalcTextSize(ctx, edge_label)
    local ax = (edge_hot == "fi") and e_fi_x or ((edge_hot == "fo") and e_fo_x or e_end_x)
    local bw, bh = tw + 10.0, th + 4.0
    local bx = math.max(ix0 + 2.0, math.min(ix1 - bw - 2.0, ax - bw * 0.5))
    local by = knob_y + 9.0
    r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, ui_tc(0x0C0D10E8), 4.0)
    r.ImGui_DrawList_AddRect(dl, bx, by, bx + bw, by + bh, edge_hot == "fi" and fade_col or end_col, 4.0, 0, 1.0)
    r.ImGui_DrawList_AddText(dl, bx + 5.0, by + 2.0, UI_THEME.text, edge_label)
  end

  -- Value readout on the point being dragged, kept inside the graph.
  local readout_p = drag_live and (not edge_hot) and active_idx and points[active_idx]
  if readout_p and not panning then
    local label = seq_env_format_point_tip(readout_p.t, readout_p.amp)
    local tw, th = r.ImGui_CalcTextSize(ctx, label)
    local hx, hy = time_to_x(readout_p.t or 0.0), amp_to_y(readout_p.amp or 1.0)
    local bw, bh = tw + 10.0, th + 4.0
    local bx = math.max(ix0 + 2.0, math.min(ix1 - bw - 2.0, hx - bw * 0.5))
    local by = hy - bh - 9.0
    if by < iy0 + 2.0 then
      by = hy + 9.0
    end
    r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, ui_tc(0x0C0D10E8), 4.0)
    r.ImGui_DrawList_AddRect(dl, bx, by, bx + bw, by + bh, UI_THEME.accent, 4.0, 0, 1.0)
    r.ImGui_DrawList_AddText(dl, bx + 5.0, by + 2.0, UI_THEME.text, label)
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
    r.ImGui_DrawList_AddRectFilled(dl, bx0, by, bx1, iy1, ui_tc(0x9FE3B5AA), 1.0)
    local label = string.format("%.0f–%.0f ms", view_t0 * 1000.0, view_t1 * 1000.0)
    local lw = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, ix0 + (iw - (lw or 0)) * 0.5, iy0 + 2, UI_THEME.text_dim, label)
  end

  if not tip and edge_hot and not dragging then
    if edge_hot == "fi" then
      tip = "Drag: fade in · Dbl-click: remove"
    elseif edge_hot == "fo" then
      tip = "Drag: fade out · Dbl-click: hard cut"
    else
      tip = "Drag: end of hit · Dbl-click: full length"
    end
  end
  if not tip and hovered then
    if nearest_idx then
      local p = points[nearest_idx]
      tip = "Drag: move · Shift: 0 dB · Alt/Right-click: delete"
    elseif nearest_seg then
      local c = points[nearest_seg].curve or 0.0
      if math.abs(c) > 0.001 then
        tip = "Drag: bend · Dbl-click: straighten"
      else
        tip = "Drag: bend · Dbl-click: straighten"
      end
    else
      tip = "Click: add point · Scroll: zoom · Shift+scroll: pan · Dbl-click: full view"
    end
  end

  state.seq_env_graph_len = PREVIEW_LEN
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

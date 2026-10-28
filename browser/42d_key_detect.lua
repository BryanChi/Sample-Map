-- Key detection from audio, for melodic samples with no key in their name or
-- tags. Song Starter asks for one file at a time (sm_key_detect_request); the
-- audio is read in one go on the main defer frame (an audio accessor returns
-- silence inside a coroutine), then the analysis runs a few frames per tick so
-- REAPER stays responsive.
--
-- Method: mono audio at 11025 Hz -> 4096-point FFT frames -> spectral peaks ->
-- pitch-class profile (tuning-corrected, bass notes weighted up) ->
-- correlation with 24 key profiles. Results: { key = "Am", pc = 9,
-- minor = true, conf = 0..1, tonal = bool, alt = "C" }.

SM_KEYDET_SR = 11025
SM_KEYDET_N = 4096
SM_KEYDET_HOP = 2048
SM_KEYDET_MAX_SEC = 30
SM_KEYDET_MIN_CONF = 0.25          -- below this the key is not trusted
SM_KEYDET_H3 = 0.3
SM_KEYDET_H5 = 0.5
SM_KEYDET_FRAME_POW = 0.5        -- louder frames count more
SM_KEYDET_NAMES = { "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

-- Temperley (Kostka-Payne) and Krumhansl profiles, averaged after scaling.
local PROF_MAJ, PROF_MIN
do
  local tm = { 0.748, 0.060, 0.488, 0.082, 0.670, 0.460, 0.096, 0.715, 0.104, 0.366, 0.057, 0.400 }
  local tn = { 0.712, 0.084, 0.474, 0.618, 0.049, 0.460, 0.105, 0.747, 0.404, 0.067, 0.133, 0.330 }
  local km = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
  local kn = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }
  PROF_MAJ, PROF_MIN = {}, {}
  for i = 1, 12 do
    PROF_MAJ[i] = tm[i] / 0.748 + km[i] / 6.35
    PROF_MIN[i] = tn[i] / 0.747 + kn[i] / 6.33
  end
end

local function corr(x, prof, rot)
  local mx, mp = 0, 0
  for i = 1, 12 do mx = mx + x[i]; mp = mp + prof[i] end
  mx, mp = mx / 12, mp / 12
  local sxy, sxx, syy = 0, 0, 0
  for i = 1, 12 do
    local a = x[((i - 1 + rot) % 12) + 1] - mx
    local b = prof[i] - mp
    sxy, sxx, syy = sxy + a * b, sxx + a * a, syy + b * b
  end
  if sxx <= 0 or syy <= 0 then return 0 end
  return sxy / math.sqrt(sxx * syy)
end

-- Key from a 12-bin pitch-class profile (index 1 = C). -> result table.
-- Measured on 200 of bryan's loops with a key in their name (2026-10-28):
-- 56% same key or its relative, 27% a fifth off (one note differs), 17%
-- further off. Bass weighting and learned profiles did not do better.
function sm_keydet_from_chroma(chroma)
  local total, peak = 0, 0
  for i = 1, 12 do
    total = total + chroma[i]
    if chroma[i] > peak then peak = chroma[i] end
  end
  if total <= 0 then return { tonal = false, conf = 0 } end
  -- Square root evens out one loud note against the rest of the scale.
  local x = {}
  for i = 1, 12 do x[i] = math.sqrt(chroma[i] / total) end
  local scores = {}
  for pc = 0, 11 do
    for m = 0, 1 do
      scores[#scores + 1] = { pc = pc, minor = m == 1, s = corr(x, m == 1 and PROF_MIN or PROF_MAJ, pc) }
    end
  end
  table.sort(scores, function(a, b) return a.s > b.s end)
  local best = scores[1]
  -- Runner-up with a different key signature (the relative key shares one, and
  -- Song Starter treats relatives as the same key).
  local sig = function(e) return e.minor and (e.pc + 3) % 12 or e.pc end
  local second, rel
  for i = 2, #scores do
    local e = scores[i]
    if sig(e) ~= sig(best) then second = second or e else rel = rel or e end
  end
  local margin = best.s - (second and second.s or 0)
  -- Flatness: a near-even profile (noise, drums) has no key.
  local flat = (total / 12) / peak
  local tonal = best.s >= 0.5 and flat < 0.75
  local conf = math.max(0, math.min(1, margin / 0.1))
  if not tonal then conf = conf * 0.3 end
  local name = function(e) return e and (SM_KEYDET_NAMES[e.pc + 1] .. (e.minor and "m" or "")) end
  return {
    key = name(best), pc = best.pc, minor = best.minor, conf = conf, tonal = tonal,
    score = best.s, margin = margin, alt = name(second), relative = name(rel),
  }
end

---------------------------------------------------------------------------
-- FFT + chroma, incremental
---------------------------------------------------------------------------

local fft_cache = {}
local function fft_tables(n)
  local t = fft_cache[n]
  if t then return t end
  local bits = math.floor(math.log(n, 2) + 0.5)
  local rev = {}
  for i = 0, n - 1 do
    local r, x = 0, i
    for _ = 1, bits do r = r * 2 + (x % 2); x = x // 2 end
    rev[i + 1] = r + 1
  end
  local cs, sn = {}, {}
  for i = 0, n // 2 - 1 do
    cs[i] = math.cos(-2 * math.pi * i / n)
    sn[i] = math.sin(-2 * math.pi * i / n)
  end
  local win = {}
  for i = 1, n do win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * (i - 1) / (n - 1)) end
  t = { rev = rev, cs = cs, sn = sn, win = win, re = {}, im = {} }
  fft_cache[n] = t
  return t
end

-- Magnitudes of bins 1..n/2 of frame x[off+1 .. off+n] (Hann window) into mag.
local function frame_mag(x, off, n, mag)
  local T = fft_tables(n)
  local rev, cs, sn, win, re, im = T.rev, T.cs, T.sn, T.win, T.re, T.im
  for i = 1, n do
    local j = rev[i]
    re[j] = (x[off + i] or 0) * win[i]
    im[j] = 0
  end
  local size = 2
  while size <= n do
    local half = size // 2
    local step = n // size
    for start = 1, n, size do
      local k = 0
      for j = start, start + half - 1 do
        local wr, wi = cs[k], sn[k]
        local l = j + half
        local tr = wr * re[l] - wi * im[l]
        local ti = wr * im[l] + wi * re[l]
        re[l] = re[j] - tr
        im[l] = im[j] - ti
        re[j] = re[j] + tr
        im[j] = im[j] + ti
        k = k + step
      end
    end
    size = size * 2
  end
  for i = 1, n // 2 do
    mag[i] = math.sqrt(re[i] * re[i] + im[i] * im[i])
  end
end

local LOG2 = math.log(2)

-- New analysis job for mono samples x at rate sr.
function sm_keydet_job(x, sr)
  return {
    x = x, sr = sr or SM_KEYDET_SR, n = SM_KEYDET_N, hop = SM_KEYDET_HOP,
    pos = 0, mag = {}, peaks = {}, tune = {}, frames = 0, fm = {}, fw = {},
  }
end

-- Runs frames until `deadline` (time_precise) or the end; true when finished.
function sm_keydet_step(job, deadline, clock)
  clock = clock or (reaper and reaper.time_precise) or os.clock
  local x, n, hop, sr, mag = job.x, job.n, job.hop, job.sr, job.mag
  local lo_bin = math.max(2, math.floor(55 * n / sr))
  local hi_bin = math.min(n // 2 - 1, math.floor(2000 * n / sr))
  local peaks, tune = job.peaks, job.tune
  while job.pos + n <= #x or (job.frames == 0 and job.pos < #x) do
    frame_mag(x, job.pos, n, mag)
    local fmax = 0
    for k = lo_bin, hi_bin do if mag[k] > fmax then fmax = mag[k] end end
    if fmax > 1e-5 then
      local thr = fmax * 0.03
      local fm, fw = job.fm, job.fw
      local np = 0
      for k = lo_bin, hi_bin do
        local m = mag[k]
        if m > thr and m >= mag[k - 1] and m > mag[k + 1] then
          -- Parabolic interpolation of the peak position (bin k = (k-1)*sr/n Hz).
          local a, b, c = mag[k - 1], m, mag[k + 1]
          local d = a - 2 * b + c
          local p = d ~= 0 and 0.5 * (a - c) / d or 0
          local f = (k - 1 + p) * sr / n
          if f > 50 then
            np = np + 1
            fm[np] = 69 + 12 * math.log(f / 440) / LOG2
            fw[np] = m
          end
        end
      end
      -- Overtones: a peak that sits a 12th (3rd harmonic) or two octaves and a
      -- third (5th harmonic) above a real peak is mostly that note's overtone,
      -- and would pull the key a fifth / third away.
      local fe = SM_KEYDET_FRAME_POW
      for i = 1, np do
        local mi, wi = fm[i], fw[i]
        local damp = 1
        for j = 1, i - 1 do
          local dm = mi - fm[j]
          if dm > 18.6 and dm < 19.45 and fw[j] >= 0.15 * wi then
            damp = damp * SM_KEYDET_H3
          elseif dm > 27.4 and dm < 28.3 and fw[j] >= 0.15 * wi then
            damp = damp * SM_KEYDET_H5
          elseif dm > 30.6 and dm < 31.45 and fw[j] >= 0.15 * wi then
            damp = damp * SM_KEYDET_H3
          end
        end
        local w = (wi / fmax) ^ 0.5 * (fmax ^ fe) * damp
        peaks[#peaks + 1] = mi
        peaks[#peaks + 1] = w
        local frac = mi - math.floor(mi + 0.5)       -- -0.5 .. 0.5
        local tb = math.floor((frac + 0.5) * 20) % 20 + 1
        tune[tb] = (tune[tb] or 0) + w
      end
    end
    job.pos = job.pos + hop
    job.frames = job.frames + 1
    if deadline and clock() >= deadline then
      return false
    end
  end
  return true
end

-- Result of a finished job.
function sm_keydet_finish(job)
  -- Tuning: the 5-cent bin where most peak energy sits.
  local best_b, best_w = 11, -1
  for b = 1, 20 do
    local w = (job.tune[b] or 0) + 0.5 * ((job.tune[(b - 2) % 20 + 1] or 0) + (job.tune[b % 20 + 1] or 0))
    if w > best_w then best_b, best_w = b, w end
  end
  local offset = (best_b - 0.5) / 20 - 0.5
  local chroma, bass = {}, {}
  for i = 1, 12 do chroma[i], bass[i] = 0, 0 end
  local peaks = job.peaks
  local count = 0
  for i = 1, #peaks, 2 do
    local midi = peaks[i] - offset
    local note = math.floor(midi + 0.5)
    local dev = math.abs(midi - note)
    local w = peaks[i + 1] * math.max(0, 1 - dev * 2.5)
    if w > 0 then
      local pc = note % 12 + 1
      chroma[pc] = chroma[pc] + w
      if note < 60 then bass[pc] = bass[pc] + w * (note < 48 and 1 or 0.5) end
      count = count + 1
    end
  end
  local res = sm_keydet_from_chroma(chroma)
  res.tuning_cents = math.floor(offset * 100 + 0.5)
  res.peaks = count
  res.chroma = chroma
  res.bass = bass
  if count < 20 then
    res.tonal, res.conf = false, 0
  end
  return res
end

-- Whole analysis in one call (tests, offline use).
function sm_keydet_analyze(x, sr)
  local job = sm_keydet_job(x, sr)
  sm_keydet_step(job)
  return sm_keydet_finish(job)
end

---------------------------------------------------------------------------
-- Reading a file and the per-file queue
---------------------------------------------------------------------------

-- Mono samples of `path` at SM_KEYDET_SR, at most SM_KEYDET_MAX_SEC long.
-- Uses a temporary track + item + take accessor (removed again). Main
-- defer frame only. -> array or nil, err.
function sm_keydet_read(path)
  local r = reaper
  if not (r.PCM_Source_CreateFromFile and r.CreateTakeAudioAccessor and r.GetAudioAccessorSamples and r.new_array) then
    return nil, "This REAPER can't read audio from a script"
  end
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then return nil, "Couldn't open the file" end
  local len = r.GetMediaSourceLength(src)
  if type(len) ~= "number" or len <= 0 then
    if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, src) end
    return nil, "The file has no audio"
  end
  local dur = math.min(len, SM_KEYDET_MAX_SEC)
  local chans = math.max(1, math.min(2, math.floor(tonumber(r.GetMediaSourceNumChannels(src)) or 2)))
  local out, err = {}, nil
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, false)
  local tr = r.GetTrack(0, idx)
  if not tr then
    err = "Couldn't create a reading track"
    if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, src) end
  else
    local item = r.AddMediaItemToTrack(tr)
    local take = item and r.AddTakeToMediaItem(item)
    if take then
      r.SetMediaItemTake_Source(take, src)    -- the take owns src now
      r.SetMediaItemInfo_Value(item, "D_POSITION", 0)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", dur)
      local acc = r.CreateTakeAudioAccessor(take)
      if acc then
        local ok, e = pcall(function()
          local sr = SM_KEYDET_SR
          local total = math.floor(dur * sr)
          local block = 8192
          local buf = r.new_array(block * chans)
          local pos = 0
          while pos < total do
            local nread = math.min(block, total - pos)
            buf.clear()
            r.GetAudioAccessorSamples(acc, sr, chans, pos / sr, nread, buf)
            local t = buf.table(1, nread * chans)
            if chans == 2 then
              for i = 1, nread do
                out[pos + i] = (t[2 * i - 1] + t[2 * i]) * 0.5
              end
            else
              for i = 1, nread do out[pos + i] = t[i] end
            end
            pos = pos + nread
          end
        end)
        r.DestroyAudioAccessor(acc)
        if not ok then err = "Couldn't read the audio: " .. tostring(e) end
      else
        err = "Couldn't read the audio"
      end
    else
      err = "Couldn't create a reading item"
      if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, src) end
    end
    r.DeleteTrack(tr)
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  if err then return nil, err end
  return out
end

-- path -> result, kept for the session. A result with .failed means it could
-- not be read.
SM_KEYDET_RESULTS = SM_KEYDET_RESULTS or {}
SM_KEYDET_QUEUE = SM_KEYDET_QUEUE or {}
SM_KEYDET_ACTIVE = nil

-- Detected key of path: result table, "pending", or nil (not asked yet).
function sm_key_detect_get(path)
  if not path then return nil end
  local res = SM_KEYDET_RESULTS[path]
  if res then return res end
  if SM_KEYDET_ACTIVE and SM_KEYDET_ACTIVE.path == path then return "pending" end
  for _, p in ipairs(SM_KEYDET_QUEUE) do
    if p == path then return "pending" end
  end
  return nil
end

-- Queue path for analysis (once). `cb(result)` runs when it finishes.
function sm_key_detect_request(path, cb)
  if not path or path == "" then return end
  local res = SM_KEYDET_RESULTS[path]
  if res then
    if cb then cb(res) end
    return res
  end
  SM_KEYDET_CALLBACKS = SM_KEYDET_CALLBACKS or {}
  if cb then
    local list = SM_KEYDET_CALLBACKS[path] or {}
    list[#list + 1] = cb
    SM_KEYDET_CALLBACKS[path] = list
  end
  if sm_key_detect_get(path) ~= "pending" then
    SM_KEYDET_QUEUE[#SM_KEYDET_QUEUE + 1] = path
  end
  return "pending"
end

local function keydet_done(path, res)
  SM_KEYDET_RESULTS[path] = res
  local list = SM_KEYDET_CALLBACKS and SM_KEYDET_CALLBACKS[path]
  if list then
    SM_KEYDET_CALLBACKS[path] = nil
    for _, cb in ipairs(list) do pcall(cb, res) end
  end
end

-- Call once per defer frame. Spends at most budget_ms (default 6) on analysis.
function sm_key_detect_tick(budget_ms)
  local clock = reaper.time_precise
  local job = SM_KEYDET_ACTIVE
  if not job then
    local path = table.remove(SM_KEYDET_QUEUE, 1)
    if not path then return end
    -- Reading happens here, on the defer frame itself.
    local ok, x, err = pcall(sm_keydet_read, path)
    if not ok then x, err = nil, tostring(x) end
    if not x then
      keydet_done(path, { failed = true, err = err, tonal = false, conf = 0 })
      return
    end
    job = sm_keydet_job(x, SM_KEYDET_SR)
    job.path = path
    SM_KEYDET_ACTIVE = job
    return   -- reading used this frame's budget
  end
  local done = sm_keydet_step(job, clock() + (budget_ms or 6) / 1000, clock)
  if done then
    SM_KEYDET_ACTIVE = nil
    local ok, res = pcall(sm_keydet_finish, job)
    if not ok then res = { failed = true, err = tostring(res), tonal = false, conf = 0 } end
    keydet_done(job.path, res)
  end
end

-- True while something is queued or being analysed.
function sm_key_detect_busy()
  return SM_KEYDET_ACTIVE ~= nil or #SM_KEYDET_QUEUE > 0
end

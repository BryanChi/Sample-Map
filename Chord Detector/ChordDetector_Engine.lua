-- @description Chord Detector engine: key-aware chord recognition for audio
-- @author Bryan Chi
-- @version 1.0
--
-- Reusable module. Pure Lua 5.4 (no math.pow / sinh / cosh / tanh), no REAPER
-- calls except in the optional take helpers at the bottom.
--
--   local CD = dofile(path .. "ChordDetector_Engine.lua")
--   local res = CD.analyze(samples, samplerate, opts)   -- mono samples, 1-based
--   local res = CD.analyze_take(take, opts)             -- REAPER take
--
-- Result:
--   res.key     = { tonic = 0-11, mode = "major"|"minor", name = "Eb major", short = "Eb", confidence = 0-1 }
--   res.keys    = { { start, stop, tonic, mode, name, short }, ... }  (key areas, modulations)
--   res.chords  = { { start, stop, root, quality, bass, name, confidence, key }, ... }
--                 root/bass are pitch classes (0 = C), nil for "no chord"
--   res.tempo, res.beats (seconds), res.tuning_cents, res.duration
--
-- How it works: peak-picked spectrum -> tuning estimate -> treble and bass
-- chroma -> beat tracking -> beat-synchronous chroma -> key areas (profile
-- correlation + harmonic function, minimum-duration HMM) -> chord decoding
-- (minimum-duration HMM with key-aware priors, root-motion preferences and a
-- change penalty) -> second key pass from the decoded chords -> second chord
-- pass -> boundary refinement -> spelling in the local key.

local M = {}
M.VERSION = "1.0"

local floor, ceil, sqrt, log, exp = math.floor, math.ceil, math.sqrt, math.log, math.exp
local cos, sin, pi, abs, atan = math.cos, math.sin, math.pi, math.abs, math.atan
local NEG = -1e30
local LOG2 = log(2)

---------------------------------------------------------------------------
-- Vocabulary
---------------------------------------------------------------------------

M.QUALITIES = {
  { id = "maj",  suffix = "",     tones = { 0, 4, 7 },     prior = 0.0  },
  { id = "min",  suffix = "m",    tones = { 0, 3, 7 },     prior = 0.0  },
  { id = "7",    suffix = "7",    tones = { 0, 4, 7, 10 }, prior = -0.6, beat = -0.08 },
  { id = "maj7", suffix = "maj7", tones = { 0, 4, 7, 11 }, prior = -0.8, beat = -0.15 },
  { id = "m7",   suffix = "m7",   tones = { 0, 3, 7, 10 }, prior = -0.8, beat = -0.12 },
  { id = "dim",  suffix = "dim",  tones = { 0, 3, 6 },     prior = -1.2, beat = -0.15 },
  { id = "aug",  suffix = "aug",  tones = { 0, 4, 8 },     prior = -1.8, beat = -0.25 },
  { id = "sus2", suffix = "sus2", tones = { 0, 2, 7 },     prior = -1.5, beat = -0.3 },
  { id = "sus4", suffix = "sus4", tones = { 0, 5, 7 },     prior = -1.3, beat = -0.25 },
  { id = "m7b5", suffix = "m7b5", tones = { 0, 3, 6, 10 }, prior = -1.4, beat = -0.2 },
}
local QBYID = {}
for i, q in ipairs(M.QUALITIES) do
  QBYID[q.id] = q; q.index = i
  q.seventh = #q.tones == 4 or nil
  q.sus = (q.id == "sus2" or q.id == "sus4") or nil
  q.fifth_idx = 3
end

M.VOCABULARIES = {
  triads = { "maj", "min" },
  basic  = { "maj", "min", "dim", "aug", "sus2", "sus4" },
  full   = { "maj", "min", "7", "maj7", "m7", "dim", "aug", "sus2", "sus4", "m7b5" },
}

M.DEFAULTS = {
  vocabulary     = "full",   -- "triads" | "basic" | "full" | list of quality ids
  min_beats      = 2,        -- shortest chord, in beats (beat_sync = true)
  beat_sync      = true,     -- chords change on beats (or half beats with refine)
  min_seconds    = 0.6,      -- shortest chord when beat_sync = false
  change_penalty = 2.0,      -- cost of every chord change (higher = fewer changes)
  key_weight     = 1.0,      -- how strongly the key steers chord choice (0 = off)
  key_changes    = true,     -- allow modulations
  min_key_beats  = 24,       -- shortest key area, in beats
  slash_chords   = false,    -- name inversions as C/E
  nnls           = false,    -- overtone-free NNLS chroma: "key" (key finding only), true (also chords), false (off)
  refine         = true,     -- allow changes a half beat early/late (pushes)
  no_chord       = "N.C.",   -- label for silence / noise, false = drop
  tuning         = nil,      -- force tuning offset in cents (nil = estimate)
  progress       = nil,      -- function(fraction 0-1, stage_label)
}

---------------------------------------------------------------------------
-- Spelling
---------------------------------------------------------------------------

local LETTERS = { [0] = "C", "D", "E", "F", "G", "A", "B" }
local LETTER_PC = { [0] = 0, 2, 4, 5, 7, 9, 11 }
local LETTER_INDEX = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }

-- Conventional tonic names (fewest accidentals; F#/Eb minor for the 6-accidental ties)
local MAJOR_TONIC = { [0] = "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local MINOR_TONIC = { [0] = "C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B" }
-- Scale degree (letter steps above the tonic) for each chromatic interval.
-- b2 b3 #4 b6 b7 in major; b2 #3 #4 #6 #7 in minor, which lands on the same letters.
local DEGREE_OF = { [0] = 0, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6 }
-- Letter steps above a chord root for each chord-tone interval.
local CHORD_DEGREE = { [0] = 0, 1, 1, 2, 2, 3, 4, 4, 4, 5, 6, 6 }

local function wrap_acc(a)
  a = a % 12
  if a > 6 then a = a - 12 end
  return a
end

local function acc_text(a, opts)
  local sh = (opts and opts.sharp_symbol) or "#"
  local fl = (opts and opts.flat_symbol) or "b"
  if a > 0 then return string.rep(sh, a) end
  if a < 0 then return string.rep(fl, -a) end
  return ""
end

local function parse_note(name)
  local l = LETTER_INDEX[name:sub(1, 1)]
  local a = 0
  for c in name:sub(2):gmatch(".") do
    if c == "#" then a = a + 1 elseif c == "b" then a = a - 1 end
  end
  return l, a
end

-- Returns letter index and accidental for pitch class pc written `steps`
-- letters above the reference letter.
local function spell_from(ref_letter, steps, pc)
  local letter = (ref_letter + steps) % 7
  return letter, wrap_acc(pc - LETTER_PC[letter])
end

local WEIRD = { ["B#"] = true, ["E#"] = true, ["Cb"] = true, ["Fb"] = true }

local function key_prefers_flats(key)
  local tname = (key.mode == "minor" and MINOR_TONIC or MAJOR_TONIC)[key.tonic]
  if tname:find("b") then return true end
  if tname:find("#") then return false end
  -- naturals: flat keys are F major and D/G/C/F minor
  if key.mode == "major" then return key.tonic == 5 end
  return key.tonic == 2 or key.tonic == 7 or key.tonic == 0 or key.tonic == 5
end

local SHARP_NAMES = { [0] = "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLAT_NAMES  = { [0] = "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }

local function plain_name(pc, flats, opts)
  local n = (flats and FLAT_NAMES or SHARP_NAMES)[pc % 12]
  if opts and (opts.sharp_symbol or opts.flat_symbol) then
    local l, a = parse_note(n)
    return LETTERS[l] .. acc_text(a, opts)
  end
  return n
end

--- Tonic name of a key, e.g. key_tonic_name({tonic=3, mode="major"}) -> "Eb"
function M.key_tonic_name(key, opts)
  local n = (key.mode == "minor" and MINOR_TONIC or MAJOR_TONIC)[key.tonic % 12]
  local l, a = parse_note(n)
  return LETTERS[l] .. acc_text(a, opts)
end

--- Name of a key, e.g. "Eb major", and its short form "Eb" / "Cm".
function M.key_name(key, opts)
  local t = M.key_tonic_name(key, opts)
  return t .. " " .. key.mode, t .. (key.mode == "minor" and "m" or "")
end

--- Spell a pitch class inside a key: spell_note(1, {tonic=0,mode="major"}) -> "Db"
-- Diatonic notes use the key's letters (E# in F# major); chromatic notes are
-- spelled as altered scale degrees (Bb, Eb, Ab, Db, F# in C major; C#, F#,
-- G#, D#, Bb in A minor), falling back to a plain name for double accidentals
-- and B#/E#/Cb/Fb on chromatic notes.
function M.spell_note(pc, key, opts)
  pc = pc % 12
  if not key then return plain_name(pc, false, opts) end
  local tl, ta = parse_note((key.mode == "minor" and MINOR_TONIC or MAJOR_TONIC)[key.tonic % 12])
  local interval = (pc - key.tonic) % 12
  local letter, a = spell_from(tl, DEGREE_OF[interval], pc)
  local raw = LETTERS[letter] .. acc_text(a)
  local scale = key.mode == "minor" and { [0] = true, [2] = true, [3] = true, [5] = true, [7] = true, [8] = true, [10] = true }
                                     or { [0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true, [11] = true }
  if abs(a) >= 2 or (WEIRD[raw] and not scale[interval]) then
    return plain_name(pc, key_prefers_flats(key), opts)
  end
  return LETTERS[letter] .. acc_text(a, opts)
end

--- Chord name, spelled in `key`: chord_name(10, "7", {tonic=3,mode="major"}) -> "Bb7"
function M.chord_name(root, quality, key, bass, opts)
  if root == nil then return (opts and opts.no_chord) or "N.C." end
  local q = QBYID[quality] or QBYID.maj
  local rname = M.spell_note(root, key, opts)
  local s = rname .. q.suffix
  if bass and bass % 12 ~= root % 12 then
    local rl, ra = parse_note(M.spell_note(root, key))
    local iv = (bass - root) % 12
    local bl, ba = spell_from(rl, CHORD_DEGREE[iv], bass % 12)
    local bn = LETTERS[bl] .. acc_text(ba)
    if abs(ba) >= 2 or WEIRD[bn] then
      bn = M.spell_note(bass, key, opts)
    else
      bn = LETTERS[bl] .. acc_text(ba, opts)
    end
    s = s .. "/" .. bn
  end
  return s
end

---------------------------------------------------------------------------
-- DSP helpers
---------------------------------------------------------------------------

local function make_fft(n)
  local bits = 0
  while (1 << bits) < n do bits = bits + 1 end
  local rev = {}
  for i = 0, n - 1 do
    local r, x = 0, i
    for _ = 1, bits do r = (r << 1) | (x & 1); x = x >> 1 end
    rev[i + 1] = r + 1
  end
  local cr, ci = {}, {}
  for i = 0, n // 2 - 1 do cr[i + 1] = cos(2 * pi * i / n); ci[i + 1] = -sin(2 * pi * i / n) end
  return function(re, im)
    for i = 1, n do
      local j = rev[i]
      if j > i then re[i], re[j] = re[j], re[i]; im[i], im[j] = im[j], im[i] end
    end
    local size = 2
    while size <= n do
      local half, step = size // 2, n // size
      for start = 1, n, size do
        local k = 1
        for j = start, start + half - 1 do
          local wr, wi = cr[k], ci[k]
          local l = j + half
          local xr, xi = re[l], im[l]
          local tr = wr * xr - wi * xi
          local ti = wr * xi + wi * xr
          local ar, ai = re[j], im[j]
          re[l] = ar - tr; im[l] = ai - ti
          re[j] = ar + tr; im[j] = ai + ti
          k = k + step
        end
      end
      size = size * 2
    end
  end
end

-- Magnitude spectrum of a real frame of size N via one N/2 complex FFT.
-- mag[k+1] = |X[k]| for k = 0 .. N/2-1
local function make_rfft_mag(N)
  local H = N // 2
  local fft = make_fft(H)
  local re, im, tr, ti = {}, {}, {}, {}
  for k = 0, H - 1 do tr[k + 1] = cos(2 * pi * k / N); ti[k + 1] = -sin(2 * pi * k / N) end
  return function(x, mag)
    for n = 1, H do re[n] = x[2 * n - 1]; im[n] = x[2 * n] end
    fft(re, im)
    for k = 0, H - 1 do
      local a = k + 1
      local b = (k == 0) and 1 or (H - k + 1)
      local zr, zi = re[a], im[a]
      local cr_, ci_ = re[b], -im[b]
      local er, ei = (zr + cr_) * 0.5, (zi + ci_) * 0.5
      local orr, oi = (zi - ci_) * 0.5, -(zr - cr_) * 0.5
      local wr, wi = tr[a], ti[a]
      local xr = er + wr * orr - wi * oi
      local xi = ei + wr * oi + wi * orr
      mag[a] = sqrt(xr * xr + xi * xi)
    end
  end
end
M._make_rfft_mag = make_rfft_mag -- exposed for tests

local function hann(n)
  local w = {}
  for i = 1, n do w[i] = 0.5 - 0.5 * cos(2 * pi * (i - 0.5) / n) end
  return w
end

local function downsample(x, sr, target)
  local D = floor(sr / target)
  if D <= 1 then return x, sr end
  local taps = 8 * D + 1
  local half = (taps - 1) // 2
  local fc = 0.45 / D
  local h, sum = {}, 0
  for i = -half, half do
    local v = (i == 0) and 2 * fc or sin(2 * pi * fc * i) / (pi * i)
    local t = (i + half) / (taps - 1)
    v = v * (0.42 - 0.5 * cos(2 * pi * t) + 0.08 * cos(4 * pi * t))
    h[i + half + 1] = v; sum = sum + v
  end
  for i = 1, taps do h[i] = h[i] / sum end
  local n, out, j = #x, {}, 0
  for c = 1, n, D do
    local acc = 0
    local lo = c - half
    local k0 = lo < 1 and (2 - lo) or 1
    local k1 = (lo + taps - 1 > n) and (n - lo + 1) or taps
    for k = k0, k1 do acc = acc + h[k] * x[lo + k - 1] end
    j = j + 1; out[j] = acc
  end
  return out, sr / D
end

local function median_of(t, n)
  table.sort(t, function(a, b) return a < b end)
  if n % 2 == 1 then return t[(n + 1) // 2] end
  return 0.5 * (t[n // 2] + t[n // 2 + 1])
end

local function percentile(list, p)
  local t, n = {}, #list
  if n == 0 then return 0 end
  for i = 1, n do t[i] = list[i] end
  table.sort(t)
  local idx = floor(p * (n - 1) + 0.5) + 1
  return t[idx]
end

---------------------------------------------------------------------------
-- Feature extraction
---------------------------------------------------------------------------

local NOTE_LO, NOTE_HI = 28, 100           -- E1 .. E7 (MIDI)
local NNOTES = NOTE_HI - NOTE_LO + 1

local function extract_features(x, sr, opts, report)
  local n = #x
  -- normalise to peak 1
  local peak = 0
  for i = 1, n do local v = abs(x[i]); if v > peak then peak = v end end
  local gain = peak > 0 and 1 / peak or 1

  local N = 1 << floor(log(0.37 * sr) / LOG2 + 0.5)
  local hop = N // 8
  local No = N // 4
  local hop_o = hop // 2
  local win, win_o = hann(N), hann(No)
  local rmag, rmag_o = make_rfft_mag(N), make_rfft_mag(No)
  local buf, mag, buf_o, mag_o = {}, {}, {}, {}

  local nframes = floor(n / hop) + 1
  local nframes_o = floor(n / hop_o) + 1
  local kmin = floor(36 * N / sr) + 2
  local kmax = math.min(N // 2 - 1, floor(2400 * N / sr))
  local mag_scale = 4 / N          -- Hann: full-scale sine -> ~1

  -- pass 1: spectral peaks
  local pk_off, pk_f, pk_a = {}, {}, {}
  local np = 0
  local tc, ts = 0, 0              -- tuning accumulators
  for f = 1, nframes do
    local c = (f - 1) * hop        -- centre sample (0-based)
    local s0 = c - N // 2
    for k = 1, N do
      local idx = s0 + k
      buf[k] = (idx >= 1 and idx <= n) and x[idx] * gain * win[k] or 0
    end
    rmag(buf, mag)
    local fmax = 0
    for k = kmin, kmax do if mag[k] > fmax then fmax = mag[k] end end
    pk_off[f] = np
    local thr = math.max(fmax * 0.003, 1e-5 * N)
    if fmax > thr then
      for k = kmin, kmax do
        local b = mag[k]
        if b > thr and b > mag[k - 1] and b >= mag[k + 1] then
          local la, lb, lc = log(mag[k - 1] + 1e-12), log(b + 1e-12), log(mag[k + 1] + 1e-12)
          local den = la - 2 * lb + lc
          local d = den ~= 0 and 0.5 * (la - lc) / den or 0
          if d > 0.5 then d = 0.5 elseif d < -0.5 then d = -0.5 end
          local freq = (k - 1 + d) * sr / N
          local amp = exp(lb - 0.25 * (la - lc) * d) * mag_scale
          np = np + 1
          pk_f[np] = freq; pk_a[np] = amp
          if freq > 90 and freq < 2000 then
            local p = 12 * log(freq / 440) / LOG2
            local dev = p - floor(p + 0.5)
            local w = sqrt(amp)
            tc = tc + w * cos(2 * pi * dev); ts = ts + w * sin(2 * pi * dev)
          end
        end
      end
    end
    if f % 128 == 0 then report(0.45 * f / nframes, "Reading spectrum") end
  end
  pk_off[nframes + 1] = np

  -- onset envelope (short frames, log spectral flux)
  local onset = {}
  local prev = {}
  for k = 1, No // 2 do prev[k] = 0 end
  local oscale = 4 / No
  for f = 1, nframes_o do
    local c = (f - 1) * hop_o
    local s0 = c - No // 2
    for k = 1, No do
      local idx = s0 + k
      buf_o[k] = (idx >= 1 and idx <= n) and x[idx] * gain * win_o[k] or 0
    end
    rmag_o(buf_o, mag_o)
    local flux = 0
    for k = 2, No // 2 do
      local v = log(1 + 100 * mag_o[k] * oscale)
      local d = v - prev[k]
      if d > 0 then flux = flux + d end
      prev[k] = v
    end
    onset[f] = flux
    if f % 256 == 0 then report(0.45 + 0.15 * f / nframes_o, "Finding beats") end
  end

  local tuning = opts.tuning and (opts.tuning / 100) or atan(ts, tc) / (2 * pi)

  -- pass 2: semitone spectrum -> log -> whitening -> chroma
  local notes = {}                  -- [f] = {NNOTES}
  local lin = {}                    -- linear copy for the NNLS transcription
  local fmaxes = {}
  for f = 1, nframes do
    local S = {}
    for m = 1, NNOTES do S[m] = 0 end
    for p = pk_off[f] + 1, pk_off[f + 1] do
      local midi = 69 + 12 * log(pk_f[p] / 440) / LOG2 - tuning
      local m = floor(midi + 0.5)
      if m >= NOTE_LO and m <= NOTE_HI then
        local i = m - NOTE_LO + 1
        S[i] = S[i] + pk_a[p]
      end
    end
    local mx = 0
    for m = 1, NNOTES do if S[m] > mx then mx = S[m] end end
    notes[f] = S; fmaxes[f] = mx
    local L = {}
    for m = 1, NNOTES do L[m] = S[m] end
    lin[f] = L
  end
  local ref = percentile(fmaxes, 0.95)
  if ref <= 0 then ref = 1 end

  local tre, bas, energy = {}, {}, {}
  local wt, wb = {}, {}
  for i = 1, NNOTES do
    local m = NOTE_LO + i - 1
    local d = (m - 64) / 15
    wt[i] = (m >= 40) and exp(-0.5 * d * d) or 0
    local e = (m - 40) / 8
    wb[i] = (m <= 57) and exp(-0.5 * e * e) or 0
  end
  local tmp = {}
  local medc = {}
  for f = 1, nframes do
    local S = notes[f]
    for i = 1, NNOTES do S[i] = log(1 + 30 * S[i] / ref) end
    -- local noise floor: medians of 25-note windows every 6 notes, interpolated
    local centers = {}
    local ci = 0
    for c = 1, NNOTES, 6 do
      local cnt = 0
      for i = math.max(1, c - 12), math.min(NNOTES, c + 12) do cnt = cnt + 1; tmp[cnt] = S[i] end
      for i = cnt + 1, #tmp do tmp[i] = nil end
      ci = ci + 1; centers[ci] = c; medc[ci] = median_of(tmp, cnt)
    end
    local t, b = {}, {}
    for pc = 1, 12 do t[pc] = 0; b[pc] = 0 end
    local e = 0
    local seg = 1
    for i = 1, NNOTES do
      while seg < ci and centers[seg + 1] <= i do seg = seg + 1 end
      local floorv
      if seg >= ci then floorv = medc[ci]
      else
        local u = (i - centers[seg]) / (centers[seg + 1] - centers[seg])
        floorv = medc[seg] * (1 - u) + medc[seg + 1] * u
      end
      local v = S[i] - floorv
      if v > 0 then
        local pc = (NOTE_LO + i - 1) % 12 + 1
        t[pc] = t[pc] + wt[i] * v
        b[pc] = b[pc] + wb[i] * v
        e = e + v
      end
    end
    tre[f], bas[f], energy[f] = t, b, e
    notes[f] = nil
    if f % 256 == 0 then report(0.6 + 0.1 * f / nframes, "Building chroma") end
  end

  return {
    sr = sr, hop = hop, N = N, nframes = nframes, frame_dt = hop / sr,
    tre = tre, bas = bas, energy = energy, lin = lin, wt = wt, wb = wb,
    onset = onset, onset_dt = hop_o / sr,
    tuning = tuning, duration = n / sr,
    input_peak = peak, peaks_per_frame = np / math.max(1, nframes),
  }
end

---------------------------------------------------------------------------
-- Beat tracking (tempo by autocorrelation, beats by dynamic programming)
---------------------------------------------------------------------------

local function track_beats(F)
  local o = F.onset
  local n = #o
  local fps = 1 / F.onset_dt
  -- detrend with a ~1 s moving mean, rectify, normalise by std
  local w = floor(fps * 0.5)
  local pre, s = {}, 0
  pre[0] = 0
  for i = 1, n do s = s + o[i]; pre[i] = s end
  local env = {}
  local sum2, cnt = 0, 0
  for i = 1, n do
    local a, b = math.max(1, i - w), math.min(n, i + w)
    local mean = (pre[b] - pre[a - 1]) / (b - a + 1)
    local v = o[i] - mean
    env[i] = v > 0 and v or 0
    sum2 = sum2 + env[i] * env[i]; cnt = cnt + 1
  end
  local sd = sqrt(sum2 / math.max(1, cnt))
  if sd <= 0 then sd = 1 end
  for i = 1, n do env[i] = env[i] / sd end

  -- tempo
  local minL = math.max(2, floor(fps * 60 / 220))
  local maxL = math.min(n - 1, ceil(fps * 60 / 45))
  local ac = {}
  local bestL, bestV = nil, -1
  for L = minL, maxL do
    local acc = 0
    for i = 1, n - L do acc = acc + env[i] * env[i + L] end
    ac[L] = acc / (n - L)
  end
  for L = minL, maxL do
    local bpm = 60 * fps / L
    local z = (log(bpm / 115) / LOG2) / 0.9
    local v = ac[L] * exp(-0.5 * z * z)
    if v > bestV then bestV, bestL = v, L end
  end
  if not bestL then
    return nil
  end
  local period = bestL
  if bestL > minL and bestL < maxL then
    local a, b, c = ac[bestL - 1], ac[bestL], ac[bestL + 1]
    local den = a - 2 * b + c
    if den < 0 then period = bestL + 0.5 * (a - c) / den end
  end

  -- dynamic programming (Ellis 2007)
  local tight = 100
  local C, P = {}, {}
  local lo_off, hi_off = floor(period / 2 + 0.5), floor(2 * period + 0.5)
  local pen = {}
  for d = lo_off, hi_off do local r = log(d / period); pen[d] = -tight * r * r end
  for t = 1, n do
    local best, bi = NEG, 0
    for d = lo_off, hi_off do
      local tau = t - d
      if tau < 1 then break end
      local v = C[tau] + pen[d]
      if v > best then best, bi = v, tau end
    end
    if bi > 0 and best > 0 then C[t] = env[t] + best; P[t] = bi
    else C[t] = env[t]; P[t] = 0 end
  end
  local lastStart = math.max(1, n - ceil(period))
  local bt, bv = n, NEG
  for t = lastStart, n do if C[t] > bv then bv, bt = C[t], t end end
  local rev = {}
  local t = bt
  while t and t > 0 do rev[#rev + 1] = t; t = P[t] end
  local beats = {}
  for i = #rev, 1, -1 do beats[#beats + 1] = (rev[i] - 1) * F.onset_dt end
  local pdt = period * F.onset_dt
  -- extend to cover the whole file
  local first = beats[1] or 0
  local pre_b = {}
  local tt = first - pdt
  while tt > -0.5 * pdt do table.insert(pre_b, 1, math.max(0, tt)); tt = tt - pdt end
  for i = #pre_b, 1, -1 do table.insert(beats, 1, pre_b[i]) end
  if beats[1] > 0.02 then table.insert(beats, 1, 0) end
  while beats[#beats] + pdt < F.duration + 0.5 * pdt do beats[#beats + 1] = beats[#beats] + pdt end
  -- drop duplicates / too-close pairs
  local clean = { beats[1] }
  for i = 2, #beats do
    if beats[i] - clean[#clean] > 0.25 * pdt then clean[#clean + 1] = beats[i] end
  end
  return clean, 60 / pdt, pdt
end

---------------------------------------------------------------------------
-- Templates, emissions and priors
---------------------------------------------------------------------------

local function chord_template(root, tones, harm)
  harm = harm or 1
  local t = {}
  for i = 1, 12 do t[i] = 0 end
  for idx, iv in ipairs(tones) do
    local pc = (root + iv) % 12
    local w = (idx == 1) and 1.1 or 1.0
    t[pc + 1] = t[pc + 1] + w
    t[(pc + 7) % 12 + 1] = t[(pc + 7) % 12 + 1] + 0.12 * w * harm    -- 3rd harmonic
    t[(pc + 4) % 12 + 1] = t[(pc + 4) % 12 + 1] + 0.04 * w * harm    -- 5th harmonic
  end
  local s = 0
  for i = 1, 12 do s = s + t[i] * t[i] end
  s = sqrt(s)
  for i = 1, 12 do t[i] = t[i] / s end
  return t
end

local function build_states(opts)
  local vocab = opts.vocabulary
  if type(vocab) == "string" then vocab = M.VOCABULARIES[vocab] or M.VOCABULARIES.full end
  local states = {}
  for _, qid in ipairs(vocab) do
    local q = QBYID[qid]
    if q then
      for root = 0, 11 do
        local tones = {}
        for i, iv in ipairs(q.tones) do tones[i] = (root + iv) % 12 end
        states[#states + 1] = { root = root, quality = q.id, q = q, tones = tones,
                                template = chord_template(root, q.tones, opts.nnls == true and 0.3 or 1) }
      end
    end
  end
  states[#states + 1] = { root = nil, quality = "N" }
  return states
end

local MAJOR_SCALE = { [0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true, [11] = true }
local MINOR_SCALE = { [0] = true, [2] = true, [3] = true, [5] = true, [7] = true, [8] = true, [10] = true, [11] = true }

-- How well a chord fits a key (0 = diatonic, negative = foreign), plus
-- function bonuses for tonic and dominant.
local function chord_key_fit(st, tonic, mode)
  if not st.root then return 0 end
  local scale = mode == "minor" and MINOR_SCALE or MAJOR_SCALE
  local out = 0
  for _, pc in ipairs(st.tones) do
    if not scale[(pc - tonic) % 12] then out = out + 1 end
  end
  -- natural minor plus raised 7th: forbid the raised 7th outside V / vii
  local rel = (st.root - tonic) % 12
  if mode == "minor" then
    for _, pc in ipairs(st.tones) do
      if (pc - tonic) % 12 == 11 and rel ~= 7 and rel ~= 11 then out = out + 1 end
    end
  end
  local q = st.quality
  local score = -1.0 * out
  if out == 0 then
    if rel == 0 and ((mode == "major" and (q == "maj" or q == "maj7")) or (mode == "minor" and (q == "min" or q == "m7"))) then
      score = score + 0.4
    elseif rel == 7 and (q == "maj" or q == "7") then
      score = score + 0.25
    end
  else
    -- secondary dominants: major / 7 chords a fifth above a diatonic root
    if (q == "maj" or q == "7") and scale[(rel + 5) % 12] and (rel + 5) % 12 ~= 6 then
      if score < -0.8 then score = -0.8 end
    end
    -- borrowed chords in major: bVII, bVI, bIII, iv
    if mode == "major" and ((q == "maj" and (rel == 10 or rel == 8 or rel == 3)) or (q == "min" and rel == 5)) then
      if score < -0.9 then score = -0.9 end
    end
  end
  return score
end

local function is_tonic_chord(st, tonic, mode)
  if not st.root or st.root ~= tonic then return false end
  if mode == "major" then return st.quality == "maj" or st.quality == "maj7" end
  return st.quality == "min" or st.quality == "m7"
end

-- root motion preferences between chords
local function chord_pair(a, b)
  if not a.root or not b.root then return 0 end
  local d = (b.root - a.root) % 12
  if d == 5 then return (a.quality == "7") and 0.6 or 0.4 end   -- down a fifth (V-I)
  if d == 7 then return 0.2 end
  if d == 2 or d == 10 then return 0.1 end
  if d == 0 then return -0.3 end                                 -- C -> C7 is allowed but not free
  return 0
end

-- Key profiles (Temperley / Kostka-Payne)
local KP_MAJ = { 0.748, 0.060, 0.488, 0.082, 0.670, 0.460, 0.096, 0.715, 0.104, 0.366, 0.057, 0.400 }
local KP_MIN = { 0.712, 0.084, 0.474, 0.618, 0.049, 0.460, 0.105, 0.747, 0.404, 0.067, 0.133, 0.330 }

local function corr12(x, prof, rot)
  local mx, mp = 0, 0
  for i = 1, 12 do mx = mx + x[i]; mp = mp + prof[i] end
  mx, mp = mx / 12, mp / 12
  local sxy, sxx, spp = 0, 0, 0
  for i = 1, 12 do
    local a = x[i] - mx
    local b = prof[(i - 1 - rot) % 12 + 1] - mp
    sxy = sxy + a * b; sxx = sxx + a * a; spp = spp + b * b
  end
  if sxx <= 0 or spp <= 0 then return 0 end
  return sxy / sqrt(sxx * spp)
end

local KEYS = {}
for t = 0, 11 do KEYS[#KEYS + 1] = { tonic = t, mode = "major" } end
for t = 0, 11 do KEYS[#KEYS + 1] = { tonic = t, mode = "minor" } end

local function fifths_distance(a, b)
  -- distance on the circle of fifths between key signatures
  local function sig(k)
    local t = k.mode == "minor" and (k.tonic + 3) % 12 or k.tonic
    return (t * 7) % 12
  end
  local d = (sig(a) - sig(b)) % 12
  if d > 6 then d = 12 - d end
  return d
end

---------------------------------------------------------------------------
-- Minimum-duration Viterbi
--   E[t][s]   emission score, t = 1..T
--   enter(t,s) score for a segment of state s starting at t
--   pair(a,b) transition bonus a -> b (a ~= b)
--   minLen    shortest segment
--   pen       cost of each change
-- Returns state per step.
---------------------------------------------------------------------------

local function viterbi_mindur(T, S, E, enter, pair, minLen, pen, full_last)
  local K = math.max(1, minLen)
  local d = {}
  for k = 1, K do d[k] = {} for s = 1, S do d[k][s] = NEG end end
  for s = 1, S do d[1][s] = E[1][s] + enter(1, s) end
  local bp1, bpst = {}, {}
  local PAIR = {}
  for a = 1, S do
    PAIR[a] = {}
    for b = 1, S do PAIR[a][b] = (a ~= b) and pair(a, b) or NEG end
  end
  for t = 2, T do
    local nd = {}
    for k = 1, K do nd[k] = {} end
    local b1, bs = {}, {}
    local dK = d[K]
    local Et = E[t]
    for s = 1, S do
      local best, bi = NEG, 0
      for a = 1, S do
        local v = dK[a] + PAIR[a][s]
        if v > best then best, bi = v, a end
      end
      local sw = best - pen + enter(t, s)
      b1[s] = bi
      if K == 1 then
        local stay = dK[s]
        if stay >= sw then nd[1][s] = stay + Et[s]; bs[s] = true
        else nd[1][s] = sw + Et[s]; bs[s] = false end
      else
        nd[1][s] = sw + Et[s]
        for k = 2, K - 1 do nd[k][s] = d[k - 1][s] + Et[s] end
        local stay, up = dK[s], d[K - 1][s]
        if stay >= up then nd[K][s] = stay + Et[s]; bs[s] = true
        else nd[K][s] = up + Et[s]; bs[s] = false end
      end
    end
    d = nd
    bp1[t], bpst[t] = b1, bs
  end
  -- best end state (allow an unfinished last segment)
  local bs_, bk, bv = 1, K, NEG
  for k = full_last and K or 1, K do for s = 1, S do if d[k][s] > bv then bv, bs_, bk = d[k][s], s, k end end end
  if bv <= NEG / 2 then
    for k = 1, K do for s = 1, S do if d[k][s] > bv then bv, bs_, bk = d[k][s], s, k end end end
  end
  local path = {}
  local s, k = bs_, bk
  for t = T, 1, -1 do
    path[t] = s
    if t > 1 then
      if K == 1 then
        if not bpst[t][s] then s = bp1[t][s] end
      elseif k == 1 then
        s = bp1[t][s]; k = K
      elseif k < K then
        k = k - 1
      else
        if not bpst[t][s] then k = K - 1 end
      end
    end
  end
  return path
end
M._viterbi_mindur = viterbi_mindur

---------------------------------------------------------------------------
-- Analysis
---------------------------------------------------------------------------

local function merge_opts(opts)
  local o = {}
  for k, v in pairs(M.DEFAULTS) do o[k] = v end
  if opts then for k, v in pairs(opts) do o[k] = v end end
  return o
end

local function cosine(x, xn, tpl)
  if xn <= 0 then return 0 end
  local s = 0
  for i = 1, 12 do s = s + x[i] * tpl[i] end
  return s / xn
end

local function norm(x)
  local s = 0
  for i = 1, 12 do s = s + x[i] * x[i] end
  return sqrt(s)
end

--- Analyse mono audio. samples: 1-based array, samplerate in Hz.
function M.analyze(samples, samplerate, user_opts)
  local opts = merge_opts(user_opts)
  local last_p = -1
  local function report(p, label)
    if opts.progress and p - last_p >= 0.01 then last_p = p; opts.progress(p, label) end
  end

  local x, sr = downsample(samples, samplerate, 11025)
  if #x < sr * 0.5 then
    return { key = nil, keys = {}, chords = {}, beats = {}, tempo = nil, duration = #x / sr, error = "too short" }
  end
  local F = extract_features(x, sr, opts, report)
  report(0.7, "Finding beats")

  -- grid: beats, or fixed steps when beat_sync is off
  local beats, tempo, period
  if opts.beat_sync then beats, tempo, period = track_beats(F) end
  local minLen
  if not beats then
    beats, period = {}, 4 * F.frame_dt
    local t = 0
    while t < F.duration do beats[#beats + 1] = t; t = t + period end
    minLen = math.max(1, floor(opts.min_seconds / period + 0.5))
    tempo = nil
  else
    minLen = math.max(1, floor(opts.min_beats + 0.5))
  end
  local T = #beats
  local bounds = {}
  for j = 1, T do bounds[j] = beats[j] end
  bounds[T + 1] = F.duration

  -- beat-synchronous chroma
  local btre, bbas, benergy = {}, {}, {}
  local fdt = F.frame_dt
  for j = 1, T do
    local t0, t1 = bounds[j], bounds[j + 1]
    local f0 = math.max(1, ceil(t0 / fdt - 1e-9) + 1)
    local f1 = math.min(F.nframes, ceil(t1 / fdt - 1e-9))
    if f1 < f0 then f0 = math.min(F.nframes, floor(0.5 * (t0 + t1) / fdt + 0.5) + 1); f1 = f0 end
    local t, b = {}, {}
    for i = 1, 12 do t[i] = 0; b[i] = 0 end
    local e = 0
    for f = f0, f1 do
      local ft, fb = F.tre[f], F.bas[f]
      for i = 1, 12 do t[i] = t[i] + ft[i]; b[i] = b[i] + fb[i] end
      e = e + F.energy[f]
    end
    local cnt = f1 - f0 + 1
    for i = 1, 12 do t[i] = t[i] / cnt; b[i] = b[i] / cnt end
    btre[j], bbas[j], benergy[j] = t, b, e / cnt
  end
  -- approximate transcription per beat (non-negative least squares, as in
  -- Mauch & Dixon's NNLS Chroma): explain the spectrum as notes with decaying
  -- overtones, so a note's 3rd/5th harmonics stop looking like chord tones
  local ktre, kbas = btre, bbas      -- chroma used for key finding
  if opts.nnls then
    local ntre, nbas = {}, {}
    local H = { 0, 12, 19, 24, 28, 31, 34, 36 }
    local D = {}                       -- D[note] = list of {bin, weight}
    for i = 1, NNOTES do
      local col, w = {}, 1
      for _, off in ipairs(H) do
        if i + off <= NNOTES then col[#col + 1] = { i + off, w } end
        w = w * 0.6
      end
      D[i] = col
    end
    local DtD = {}
    for i = 1, NNOTES do
      local row = {}
      for k = 1, NNOTES do row[k] = 0 end
      local acc = {}
      for _, e in ipairs(D[i]) do acc[e[1]] = e[2] end
      for k = 1, NNOTES do
        local v = 0
        for _, e in ipairs(D[k]) do local a = acc[e[1]]; if a then v = v + a * e[2] end end
        row[k] = v
      end
      DtD[i] = row
    end
    for j = 1, T do
      local t0, t1 = bounds[j], bounds[j + 1]
      local f0 = math.max(1, ceil(t0 / fdt - 1e-9) + 1)
      local f1 = math.min(F.nframes, ceil(t1 / fdt - 1e-9))
      if f1 < f0 then f0 = math.min(F.nframes, floor(0.5 * (t0 + t1) / fdt + 0.5) + 1); f1 = f0 end
      local v = {}
      for i = 1, NNOTES do v[i] = 0 end
      for f = f0, f1 do local L = F.lin[f]; for i = 1, NNOTES do v[i] = v[i] + L[i] end end
      local vmax = 0
      for i = 1, NNOTES do if v[i] > vmax then vmax = v[i] end end
      local tc, bc = {}, {}
      for i = 1, 12 do tc[i] = 0; bc[i] = 0 end
      if vmax > 0 then
        -- remove the broadband floor (drums, noise): median of the surrounding octave
        local w, tmpm = {}, {}
        for i = 1, NNOTES do
          local cnt = 0
          for k = math.max(1, i - 12), math.min(NNOTES, i + 12) do cnt = cnt + 1; tmpm[cnt] = v[k] end
          for k = cnt + 1, #tmpm do tmpm[k] = nil end
          local fl = median_of(tmpm, cnt)
          w[i] = v[i] > fl and (v[i] - fl) / vmax or 0
        end
        v = w
        local Dtv, a = {}, {}
        for i = 1, NNOTES do
          local x = 0
          for _, e in ipairs(D[i]) do x = x + e[2] * v[e[1]] end
          Dtv[i] = x; a[i] = v[i] + 1e-3
        end
        for _ = 1, 40 do              -- multiplicative updates keep a >= 0
          for i = 1, NNOTES do
            local row, den = DtD[i], 1e-9
            for k = 1, NNOTES do den = den + row[k] * a[k] end
            a[i] = a[i] * Dtv[i] / den
          end
        end
        for i = 1, NNOTES do
          local x = sqrt(a[i])
          local pc = (NOTE_LO + i - 1) % 12 + 1
          tc[pc] = tc[pc] + F.wt[i] * x
          bc[pc] = bc[pc] + F.wb[i] * x
        end
      end
      ntre[j], nbas[j] = tc, bc
      if j % 32 == 0 then report(0.7 + 0.05 * j / T, "Finding notes") end
    end
    -- key chroma: blend of the plain and the overtone-free chroma
    ktre, kbas = {}, {}
    for j = 1, T do
      local a, b, c, d = btre[j], ntre[j], bbas[j], nbas[j]
      local sa, sb, sc, sd = 0, 0, 0, 0
      for i = 1, 12 do sa = sa + a[i]; sb = sb + b[i]; sc = sc + c[i]; sd = sd + d[i] end
      local kt, kb = {}, {}
      for i = 1, 12 do
        kt[i] = (sa > 0 and a[i] / sa or 0) + (sb > 0 and b[i] / sb or 0)
        kb[i] = (sc > 0 and c[i] / sc or 0) + (sd > 0 and d[i] / sd or 0)
      end
      ktre[j], kbas[j] = kt, kb
    end
    if opts.nnls == true then btre, bbas = ntre, nbas end
  end

  local e90 = percentile(benergy, 0.9)
  local silent = {}
  for j = 1, T do silent[j] = benergy[j] < 0.06 * e90 end

  -- chord emissions
  local states = build_states(opts)
  local S = #states
  local NSTATE = S
  local KAPPA, BETA, TAU_N = 10, 2.5, 0.5
  local E = {}
  local bnorm = {}
  local dbg_best, dbg_n, dbg_flat = {}, {}, {}
  for j = 1, T do
    local row = {}
    local tj = btre[j]
    local tn = norm(tj)
    local bj = bbas[j]
    local bs = 0
    for i = 1, 12 do bs = bs + bj[i] end
    local bn = nil
    if bs > 1e-9 and not silent[j] then
      bn = {}
      for i = 1, 12 do bn[i] = bj[i] / bs end
    end
    bnorm[j] = bn
    for s = 1, S - 1 do
      local st = states[s]
      local v = silent[j] and 0 or KAPPA * cosine(tj, tn, st.template)
      if bn then
        local bt = bn[st.root + 1]
        for i = 2, #st.tones do bt = bt + 0.35 * bn[st.tones[i] + 1] end
        v = v + BETA * (bt - 0.3)
      end
      -- extensions need their own evidence: a 7th must be nearly as strong as
      -- the triad tones, a sus chord needs a weak third
      local q = st.q
      if not silent[j] and tn > 0 and (q.seventh or q.sus) then
        local r = tj[st.root + 1]
        local fifth = tj[st.tones[q.fifth_idx] + 1]
        if q.seventh then
          local tri = (r + tj[st.tones[2] + 1] + fifth) / 3
          local ext = tri > 0 and tj[st.tones[4] + 1] / tri or 0
          if ext < 0.6 then v = v - 1.5 * (0.6 - ext) / 0.6 end
        else
          local third = math.max(tj[(st.root + 3) % 12 + 1], tj[(st.root + 4) % 12 + 1])
          local rf = 0.5 * (r + fifth)
          local th = rf > 0 and third / rf or 0
          if th > 0.3 then v = v - 2.0 * (th - 0.3) end
        end
      end
      row[s] = v + (q.beat or 0)
    end
    -- no-chord gets stronger the flatter (noisier) the chroma is
    local flat = 0
    if not silent[j] and tn > 0 then
      local am, lg, ok = 0, 0, true
      for i = 1, 12 do
        local v = tj[i] / tn + 1e-3
        am = am + v; lg = lg + log(v)
      end
      flat = exp(lg / 12) / (am / 12)
    end
    -- dense mixes are fairly flat too, so only clearly noise-like chroma (> 0.75) favours it
    local nf = flat > 0.75 and (flat - 0.75) * 2.4 or 0
    row[NSTATE] = silent[j] and KAPPA * 0.3 or KAPPA * (TAU_N + nf)
    E[j] = row
    local bc = NEG
    for s = 1, S - 1 do if row[s] > bc then bc = row[s] end end
    dbg_best[j], dbg_n[j], dbg_flat[j] = bc / KAPPA, row[NSTATE] / KAPPA, flat
  end
  report(0.75, "Finding the key")

  -- key areas
  local KW = 8
  local key_chroma = {}
  for j = 1, T do
    local v = {}
    for i = 1, 12 do v[i] = 0 end
    for jj = math.max(1, j - KW), math.min(T, j + KW) do
      if not silent[jj] then
        local t, b = ktre[jj], kbas[jj]
        local s = 0
        for i = 1, 12 do s = s + t[i] + 0.7 * b[i] end
        if s > 0 then for i = 1, 12 do v[i] = v[i] + (t[i] + 0.7 * b[i]) / s end end
      end
    end
    key_chroma[j] = v
  end
  local KCORR = {}
  for j = 1, T do
    local row = {}
    for k, key in ipairs(KEYS) do
      row[k] = corr12(key_chroma[j], key.mode == "major" and KP_MAJ or KP_MIN, key.tonic)
    end
    KCORR[j] = row
  end

  local function decode_keys(chord_path)
    local KE = {}
    for j = 1, T do
      local row = {}
      for k, key in ipairs(KEYS) do
        local v = 3 * KCORR[j][k]
        if chord_path then
          local st = states[chord_path[j]]
          if st.root then
            v = v + 0.8 * chord_key_fit(st, key.tonic, key.mode)
            if is_tonic_chord(st, key.tonic, key.mode) then v = v + 0.5 end
          end
        end
        row[k] = v
      end
      KE[j] = row
    end
    local path
    local min_key = math.max(opts.min_key_beats, ceil(16 / period))
    if opts.key_changes and T > 2 * min_key then
      path = viterbi_mindur(T, #KEYS, KE, function() return 0 end,
        function(a, b)
          local d = fifths_distance(KEYS[a], KEYS[b])
          return -0.3 * d - (d == 0 and 4 or 0)   -- relative major/minor flips are usually ambiguity
        end,
        min_key, 10, true)
    else
      local tot = {}
      for k = 1, #KEYS do tot[k] = 0 end
      for j = 1, T do for k = 1, #KEYS do tot[k] = tot[k] + KE[j][k] end end
      -- first and last chords lean towards the tonic
      local bk, bv = 1, NEG
      for k = 1, #KEYS do if tot[k] > bv then bv, bk = tot[k], k end end
      path = {}
      for j = 1, T do path[j] = bk end
    end
    return path, KE
  end

  local function decode_chords(key_path)
    local kw = opts.key_weight
    local fit_cache = {}
    local function enter(j, s)
      local st = states[s]
      if not st.root then return -0.5 end
      local kp = key_path[j]
      local c = fit_cache[kp]
      if not c then c = {}; fit_cache[kp] = c end
      local v = c[s]
      if not v then
        local key = KEYS[kp]
        v = st.q.prior + kw * chord_key_fit(st, key.tonic, key.mode)
        c[s] = v
      end
      return v
    end
    local function pair(a, b) return chord_pair(states[a], states[b]) end
    return viterbi_mindur(T, S, E, enter, pair, minLen, opts.change_penalty)
  end

  local key_path = decode_keys(nil)
  report(0.8, "Decoding chords")
  local chord_path = decode_chords(key_path)
  report(0.88, "Checking the key")
  local KE
  key_path, KE = decode_keys(chord_path)
  report(0.9, "Decoding chords")
  chord_path = decode_chords(key_path)
  report(0.97, "Writing names")

  -- segments
  local segs = {}
  for j = 1, T do
    local s = chord_path[j]
    local last = segs[#segs]
    if last and last.state == s then last.j1 = j
    else segs[#segs + 1] = { state = s, j0 = j, j1 = j } end
  end

  -- boundary refinement: a change may land half a beat early or late
  if opts.refine and #segs > 1 then
    local function frame_score(st, f)
      local x = F.tre[f]
      return cosine(x, norm(x), st.template)
    end
    for i = 2, #segs do
      local A, B = states[segs[i - 1].state], states[segs[i].state]
      local tb = bounds[segs[i].j0]
      segs[i].t0 = tb
      if A.root and B.root and not (segs[i - 1].j1 == segs[i - 1].j0 and opts.beat_sync and minLen <= 1) then
        local half = 0.5 * period
        local lo, hi = tb - half, tb + half
        local f0 = math.max(1, floor(lo / fdt) + 1)
        local f1 = math.min(F.nframes, ceil(hi / fdt) + 1)
        local best_t, best_v = tb, NEG
        for _, cand in ipairs(opts.beat_sync and { tb, tb - half, tb + half } or { tb }) do
          if cand > bounds[segs[i - 1].j0] + 0.25 * period and cand < bounds[segs[i].j1 + 1] - 0.25 * period then
            local v = 0
            for f = f0, f1 do
              local ft = (f - 1) * fdt
              v = v + ((ft < cand) and frame_score(A, f) or frame_score(B, f))
            end
            if cand ~= tb then v = v - 0.6 end
            if v > best_v then best_v, best_t = v, cand end
          end
        end
        if not opts.beat_sync then
          -- continuous refinement on the frame grid
          for f = f0, f1 do
            local cand = (f - 1) * fdt
            if cand > bounds[segs[i - 1].j0] and cand < bounds[segs[i].j1 + 1] then
              local v = 0
              for g = f0, f1 do
                local gt = (g - 1) * fdt
                v = v + ((gt < cand) and frame_score(A, g) or frame_score(B, g))
              end
              if v > best_v then best_v, best_t = v, cand end
            end
          end
        end
        segs[i].t0 = best_t
      end
    end
  end

  -- results
  local function key_at(j) return KEYS[key_path[j]] end
  local chords = {}
  for i, sg in ipairs(segs) do
    local st = states[sg.state]
    local t0 = sg.t0 or bounds[sg.j0]
    local t1 = (segs[i + 1] and (segs[i + 1].t0 or bounds[segs[i + 1].j0])) or F.duration
    local key = key_at(sg.j0)
    -- confidence: average margin of the chosen chord over the runner-up
    local margin, cnt = 0, 0
    for j = sg.j0, sg.j1 do
      local row = E[j]
      local mine = row[sg.state]
      local other = NEG
      for s = 1, S do if s ~= sg.state and row[s] > other then other = row[s] end end
      margin = margin + (mine - other); cnt = cnt + 1
    end
    margin = margin / math.max(1, cnt)
    local conf = 1 / (1 + exp(-(margin + 0.5)))
    -- bass for slash chords
    local bass = st.root
    if st.root and opts.slash_chords then
      local acc = {}
      for i2 = 1, 12 do acc[i2] = 0 end
      for j = sg.j0, sg.j1 do
        local bn = bnorm[j]
        if bn then for i2 = 1, 12 do acc[i2] = acc[i2] + bn[i2] end end
      end
      local bi, bvv = st.root, acc[st.root + 1]
      for ti = 2, #st.tones do
        local pc = st.tones[ti]
        if acc[pc + 1] > bvv * 1.6 then bi, bvv = pc, acc[pc + 1] end
      end
      bass = bi
    end
    local name
    if st.root then name = M.chord_name(st.root, st.quality, key, bass, opts)
    else name = opts.no_chord or "N.C." end
    chords[#chords + 1] = {
      start = t0, stop = t1, root = st.root, quality = st.root and st.quality or nil,
      bass = st.root and bass or nil, name = name, confidence = conf,
      key = M.key_name(key, opts),
    }
  end
  if opts.no_chord == false then
    local kept = {}
    for _, c in ipairs(chords) do if c.root then kept[#kept + 1] = c end end
    chords = kept
  end

  -- key areas
  local keys = {}
  local key_beats = {}
  for j = 1, T do
    local kp = key_path[j]
    if not silent[j] then key_beats[kp] = (key_beats[kp] or 0) + 1 end
    local last = keys[#keys]
    if last and last.k == kp then last.stop = bounds[j + 1]
    else
      local key = KEYS[kp]
      local name, short = M.key_name(key, opts)
      keys[#keys + 1] = { k = kp, start = bounds[j], stop = bounds[j + 1], tonic = key.tonic, mode = key.mode, name = name, short = short }
    end
  end
  local main_k, main_n = key_path[1], -1
  for k, cnt in pairs(key_beats) do if cnt > main_n then main_n, main_k = cnt, k end end
  -- key confidence: how clearly the winner beats the runner-up overall
  local tot = {}
  for k = 1, #KEYS do tot[k] = 0 end
  for j = 1, T do if not silent[j] then for k = 1, #KEYS do tot[k] = tot[k] + KE[j][k] end end end
  local second = NEG
  for k = 1, #KEYS do if k ~= main_k and tot[k] > second then second = tot[k] end end
  local nb = math.max(1, main_n)
  local kconf = 1 / (1 + exp(-4 * ((tot[main_k] - second) / nb)))
  local mk = KEYS[main_k]
  local mname, mshort = M.key_name(mk, opts)
  for _, k in ipairs(keys) do k.k = nil end

  local nsil = 0
  for j = 1, T do if silent[j] then nsil = nsil + 1 end end
  report(1, "Done")
  return {
    key = { tonic = mk.tonic, mode = mk.mode, name = mname, short = mshort, confidence = kconf },
    keys = keys,
    chords = chords,
    beats = beats,
    tempo = tempo,
    tuning_cents = floor(F.tuning * 100 + 0.5),
    stats = {
      input_peak = F.input_peak, beats = T, silent = nsil / math.max(1, T),
      best_chord = percentile(dbg_best, 0.5), no_chord = percentile(dbg_n, 0.5),
      flatness = percentile(dbg_flat, 0.5), peaks_per_frame = F.peaks_per_frame,
    },
    duration = F.duration,
  }
end

---------------------------------------------------------------------------
-- REAPER helpers
---------------------------------------------------------------------------

-- NOTE: REAPER's GetAudioAccessorSamples returns silence when it is called
-- inside a Lua coroutine. Read audio from the main script body or from a
-- reaper.defer callback (take_reader below), then analyse in a coroutine.

--- Incremental take reader for defer loops.
--   local rd = CD.take_reader(take)        -- sr defaults to 11025
--   repeat local done, frac = rd:step(0.03) until done   (one step per defer cycle)
--   rd.samples, rd.sr, rd.t_start
function M.take_reader(take, sr)
  local r = reaper
  sr = sr or 11025
  local src = r.GetMediaItemTake_Source(take)
  local nch = math.max(1, math.floor(r.GetMediaSourceNumChannels(src)))
  local acc = r.CreateTakeAudioAccessor(take)
  local t_start = r.GetAudioAccessorStartTime(acc)
  local t_end = r.GetAudioAccessorEndTime(acc)
  local block = 8192
  local rd = {
    samples = {}, sr = sr, t_start = t_start, nch = nch,
    total = math.max(0, math.floor((t_end - t_start) * sr)), pos = 0, n = 0,
    acc = acc, buf = r.new_array(block * nch), block = block,
  }
  function rd:step(budget)
    local t0 = r.time_precise()
    local out, nch_, buf = self.samples, self.nch, self.buf
    while self.pos < self.total do
      local cnt = math.min(self.block, self.total - self.pos)
      buf.clear()
      r.GetAudioAccessorSamples(self.acc, self.sr, nch_, self.t_start + self.pos / self.sr, cnt, buf)
      local t = buf.table(1, cnt * nch_)
      local n = self.n
      if nch_ == 1 then
        for i = 1, cnt do n = n + 1; out[n] = t[i] end
      else
        local inv = 1 / nch_
        for i = 0, cnt - 1 do
          local s = 0
          for c = 1, nch_ do s = s + t[i * nch_ + c] end
          n = n + 1; out[n] = s * inv
        end
      end
      self.n = n
      self.pos = self.pos + cnt
      if budget and r.time_precise() - t0 > budget then break end
    end
    local done = self.pos >= self.total
    if done and self.acc then r.DestroyAudioAccessor(self.acc); self.acc = nil end
    return done, self.pos / math.max(1, self.total)
  end
  function rd:cancel()
    if self.acc then r.DestroyAudioAccessor(self.acc); self.acc = nil end
  end
  return rd
end

--- Read a whole take as mono samples at `sr` (default 11025 Hz), blocking.
-- Returns samples, sr, t_start (item time). Not inside a coroutine (see above).
function M.read_take(take, sr)
  local rd = M.take_reader(take, sr)
  rd:step(nil)
  return rd.samples, rd.sr, rd.t_start
end

--- Move result times by `offset` seconds (e.g. accessor start time).
function M.shift_result(res, offset)
  if not offset or offset == 0 then return res end
  for _, c in ipairs(res.chords) do c.start = c.start + offset; c.stop = c.stop + offset end
  for _, k in ipairs(res.keys) do k.start = k.start + offset; k.stop = k.stop + offset end
  for i, b in ipairs(res.beats) do res.beats[i] = b + offset end
  return res
end

--- Analyse a REAPER take, blocking. Times in the result are item time.
-- Call it from the main script body, not from a coroutine (see above).
function M.analyze_take(take, opts)
  local samples, sr, t_start = M.read_take(take, 11025)
  return M.shift_result(M.analyze(samples, sr, opts), t_start)
end

--- Convert item time to take source time for take markers.
function M.item_to_source_time(take, t)
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  return offs + t * rate
end

return M

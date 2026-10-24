-- Bloom Study Signals.lua
-- Pure Lua test-signal generator for the black-box study of an adaptive tone shaper.
-- No REAPER calls in here, so it also runs under plain Lua 5.4 (`lua5.4 run_signals.lua <dir>`).
-- Every stationary signal is a periodic noise built in the frequency domain
-- (random phase, exact magnitude shape), so Welch analysis of the output is clean.

local S = {}

S.SR    = 48000
S.N     = 2 ^ 19          -- 524288 samples = 10.92 s at 48 kHz, one period
S.RMS   = -18             -- dBFS RMS of every stationary signal

---------------------------------------------------------------- random
local seed = 1
local function rnd()      -- deterministic LCG, [0,1)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end
function S.Seed(s) seed = s end

---------------------------------------------------------------- FFT (in place, radix 2)
local function fft(re, im, n, inv)
  local j = 1
  for i = 1, n do
    if i < j then
      re[i], re[j] = re[j], re[i]
      im[i], im[j] = im[j], im[i]
    end
    local m = n // 2
    while m >= 1 and j > m do j = j - m; m = m // 2 end
    j = j + m
  end
  local len = 2
  local sgn = inv and 1 or -1
  while len <= n do
    local ang = sgn * 2 * math.pi / len
    local wr, wi = math.cos(ang), math.sin(ang)
    local half = len // 2
    for i = 1, n, len do
      local cr, ci = 1, 0
      for k = 0, half - 1 do
        local a, b = i + k, i + k + half
        local tr = re[b] * cr - im[b] * ci
        local ti = re[b] * ci + im[b] * cr
        re[b], im[b] = re[a] - tr, im[a] - ti
        re[a], im[a] = re[a] + tr, im[a] + ti
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len = len * 2
  end
end
S.fft = fft

---------------------------------------------------------------- spectral shapes (dB at frequency f)
local function log2(x) return math.log(x) / math.log(2) end
local function bump(f, fc, oct_sigma, db)
  local d = log2(f / fc) / oct_sigma
  return db * math.exp(-0.5 * d * d)
end
S.bump = bump

S.Shapes = {
  white  = function(f) return 0 end,
  pink   = function(f) return -10 * math.log(f / 1000, 10) end,              -- -3 dB/oct
  brown  = function(f) return -20 * math.log(f / 1000, 10) end,              -- -6 dB/oct
  bright = function(f) return -1.5 * log2(f / 1000) end,                     -- pink +1.5 dB/oct
  dark   = function(f) return -4.5 * log2(f / 1000) end,                     -- pink -1.5 dB/oct
  bumps  = function(f) return -10 * math.log(f / 1000, 10) + bump(f, 250, 0.5, 9) + bump(f, 4000, 0.5, 9) end,
  hole   = function(f) return -10 * math.log(f / 1000, 10) + bump(f, 1000, 0.5, -12) end,
  band1k = function(f) return 40 * (math.exp(-0.5 * (log2(f / 1000) / 0.17) ^ 2) - 1) end,  -- 1/3-oct band
}

-- periodic noise of length n with magnitude |H(f)| = 10^(shape/20), band-limited 20 Hz .. 20 kHz
function S.ShapedNoise(shape, n, sr, rms_db)
  n, sr, rms_db = n or S.N, sr or S.SR, rms_db or S.RMS
  local re, im = {}, {}
  for i = 1, n do re[i] = 0; im[i] = 0 end
  for k = 1, n // 2 - 1 do
    local f = k * sr / n
    local mag = 0
    if f >= 20 and f <= 20000 then
      mag = 10 ^ (shape(f) / 20)
      local fade = 1
      if f < 30 then fade = (f - 20) / 10 end
      if f > 19000 then fade = (20000 - f) / 1000 end
      mag = mag * fade
    end
    local ph = 2 * math.pi * rnd()
    re[k + 1] = mag * math.cos(ph); im[k + 1] = mag * math.sin(ph)
    re[n - k + 1] = re[k + 1];      im[n - k + 1] = -im[k + 1]
  end
  fft(re, im, n, true)
  local sum = 0
  for i = 1, n do sum = sum + re[i] * re[i] end
  local g = 10 ^ (rms_db / 20) / math.sqrt(sum / n)
  for i = 1, n do re[i] = re[i] * g end
  return re
end

---------------------------------------------------------------- helpers
local function db(x) return 10 ^ (x / 20) end
local function ramp_concat(segs, sr)             -- {buf, from, len, gain_db}, 2 ms crossfades
  local out, fade = {}, math.floor(0.002 * sr)
  for _, s in ipairs(segs) do
    local buf, from, len, g = s[1], s[2], s[3], db(s[4] or 0)
    local n0 = #out
    for i = 0, len - 1 do
      local w = 1
      if i < fade then w = i / fade elseif i >= len - fade then w = (len - 1 - i) / fade end
      local idx = ((from + i) % #buf) + 1
      out[n0 + i + 1] = buf[idx] * g * w
    end
  end
  return out
end

---------------------------------------------------------------- the signal set
-- Each entry: id, file name, description, channels {L, R}
function S.Build(progress)
  local sr, N = S.SR, S.N
  local P = progress or function() end
  local list = {}
  local function add(id, desc, L, R) list[#list + 1] = { id = id, desc = desc, L = L, R = R } end

  S.Seed(11); P('pink');   local pink   = S.ShapedNoise(S.Shapes.pink)
  S.Seed(12); P('white');  local white  = S.ShapedNoise(S.Shapes.white)
  S.Seed(13); P('brown');  local brown  = S.ShapedNoise(S.Shapes.brown)
  S.Seed(14); P('bright'); local bright = S.ShapedNoise(S.Shapes.bright)
  S.Seed(15); P('dark');   local dark   = S.ShapedNoise(S.Shapes.dark)
  S.Seed(16); P('bumps');  local bumps  = S.ShapedNoise(S.Shapes.bumps)
  S.Seed(17); P('hole');   local hole   = S.ShapedNoise(S.Shapes.hole)
  S.Seed(18); P('band');   local band   = S.ShapedNoise(S.Shapes.band1k, N, sr, -18)
  S.Seed(19); P('pinkR');  local pinkR  = S.ShapedNoise(S.Shapes.bright)

  add('S01_pink',   'Pink noise, -18 dBFS RMS, periodic 10.9 s', pink)
  add('S02_white',  'White noise, -18 dBFS RMS', white)
  add('S03_brown',  'Brown noise (-6 dB/oct), -18 dBFS RMS', brown)
  add('S04_bright', 'Pink tilted +1.5 dB/oct', bright)
  add('S05_dark',   'Pink tilted -1.5 dB/oct', dark)
  add('S06_bumps',  'Pink + 9 dB bumps at 250 Hz and 4 kHz (1 oct wide)', bumps)
  add('S07_hole',   'Pink with a -12 dB dip at 1 kHz (1 oct wide)', hole)

  -- level ladder: does the curve depend on level? 5 s each
  local L5 = 5 * sr
  add('S08_ladder', 'Pink at -42, -30, -18, -12, -6 dBFS RMS, 5 s each', ramp_concat({
    { pink, 0, L5, -24 }, { pink, L5, L5, -12 }, { pink, 2 * L5, L5, 0 }, { pink, 3 * L5, L5, 6 }, { pink, 4 * L5, L5, 12 } }, sr))

  -- spectral switch: dark <-> bright every 3 s, equal RMS (attack/release of the tonal correction)
  local segs, L3 = {}, 3 * sr
  for i = 0, 7 do segs[#segs + 1] = { (i % 2 == 0) and brown or white, i * L3, L3, 0 } end
  add('S09_switch', 'Brown and white noise alternating every 3 s (4 cycles), equal RMS', ramp_concat(segs, sr))

  -- band burst: pink bed + 1 kHz 1/3-oct noise burst (+~12 dB in band), 1 s on / 2 s off
  local burst, fade = {}, math.floor(0.002 * sr)
  local bed_g, band_g = db(-6), db(-9)     -- band about +12 dB over the bed's 1 kHz third-octave
  local total = 21 * sr
  for i = 0, total - 1 do
    local t = i % (3 * sr)
    local w = 0
    if t < sr then
      w = 1
      if t < fade then w = t / fade elseif t >= sr - fade then w = (sr - 1 - t) / fade end
    end
    burst[i + 1] = pink[(i % N) + 1] * bed_g + band[(i % N) + 1] * band_g * w
  end
  add('S10_burst', 'Pink bed -24 dBFS + 1 kHz third-octave noise bursts, 1 s on / 2 s off', burst)

  -- clicks on a quiet pink bed: transient response, latency, pre-ring
  local clicks = {}
  for i = 0, 16 * sr - 1 do
    clicks[i + 1] = pink[(i % N) + 1] * db(-18)
    if i % sr == sr // 2 then clicks[i + 1] = clicks[i + 1] + 0.5 end
  end
  add('S11_clicks', 'Pink bed -36 dBFS + one 0.5 impulse every second', clicks)

  -- stereo: L pink, R bright (uncorrelated) - link / split behaviour
  add('S12_stereo', 'L = pink, R = bright pink (+1.5 dB/oct), uncorrelated', pink, pinkR)
  return list
end

---------------------------------------------------------------- WAV writer (32-bit float)
function S.WriteWav(path, L, R, sr)
  sr = sr or S.SR
  local ch = R and 2 or 1
  local n = #L
  local f = assert(io.open(path, 'wb'))
  local data_bytes = n * ch * 4
  f:write('RIFF', string.pack('<I4', 36 + data_bytes), 'WAVE')
  f:write('fmt ', string.pack('<I4I2I2I4I4I2I2', 16, 3, ch, sr, sr * ch * 4, ch * 4, 32))
  f:write('data', string.pack('<I4', data_bytes))
  local chunk, CH = {}, 4096
  for i = 1, n do
    if ch == 2 then chunk[#chunk + 1] = string.pack('<ff', L[i], R[i])
    else chunk[#chunk + 1] = string.pack('<f', L[i]) end
    if #chunk >= CH then f:write(table.concat(chunk)); chunk = {} end
  end
  f:write(table.concat(chunk))
  f:close()
end

function S.WriteAll(dir, progress)
  local list = S.Build(progress)
  for _, s in ipairs(list) do
    s.file = dir .. '/' .. s.id .. '.wav'
    S.WriteWav(s.file, s.L, s.R)
    s.channels = s.R and 2 or 1
    s.length = #s.L / S.SR
    s.L, s.R = nil, nil
  end
  return list
end

return S

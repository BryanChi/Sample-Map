-- Offline tests for the Chord Detector engine.
-- lua run_tests.lua WAVDIR [song ...]
-- WAVDIR holds <song>.wav + <song>.truth.lua from synth_songs.py.

-- REAPER's Lua lacks these: make sure the engine never uses them
math.pow, math.sinh, math.cosh, math.tanh = nil, nil, nil, nil

local here = arg[0]:match("^(.*)/") or "."
local CD = dofile(here .. "/../ChordDetector_Engine.lua")
local dir = arg[1] or "/tmp/cdtest"

local fails = 0
local function check(cond, msg)
  if not cond then fails = fails + 1; print("  FAIL " .. msg) end
end

-- 1. FFT against a naive DFT
do
  local N = 64
  local x = {}
  for i = 1, N do x[i] = math.sin(i * 0.37) + 0.5 * math.cos(i * 1.9) + (i % 7) * 0.1 end
  local mag = {}
  CD._make_rfft_mag(N)(x, mag)
  local worst = 0
  for k = 0, N / 2 - 1 do
    local re, im = 0, 0
    for n = 0, N - 1 do re = re + x[n + 1] * math.cos(2 * math.pi * k * n / N); im = im - x[n + 1] * math.sin(2 * math.pi * k * n / N) end
    worst = math.max(worst, math.abs(math.sqrt(re * re + im * im) - mag[k + 1]))
  end
  check(worst < 1e-9, "rfft matches DFT (err " .. worst .. ")")
end

-- 2. Spelling
do
  local function K(t, m) return { tonic = t, mode = m } end
  local cases = {
    { 10, "7", K(3, "major"), nil, "Bb7" }, { 3, "maj", K(3, "major"), nil, "Eb" },
    { 8, "maj", K(0, "major"), nil, "Ab" }, { 10, "maj", K(0, "major"), nil, "Bb" },
    { 1, "maj", K(0, "major"), nil, "Db" }, { 2, "7", K(0, "major"), nil, "D7" },
    { 4, "7", K(9, "minor"), nil, "E7" }, { 1, "maj", K(9, "minor"), nil, "C#" },
    { 3, "min", K(6, "major"), nil, "D#m" }, { 1, "7", K(6, "major"), nil, "C#7" },
    { 5, "dim", K(6, "major"), nil, "E#dim" }, { 6, "maj", K(10, "minor"), nil, "Gb" },
    { 5, "7", K(10, "minor"), nil, "F7" }, { 3, "min", K(10, "minor"), nil, "Ebm" },
    { 6, "maj7", K(1, "major"), nil, "Gbmaj7" }, { 8, "7", K(1, "major"), nil, "Ab7" },
    { 0, "maj", K(0, "major"), 4, "C/E" }, { 3, "maj", K(3, "major"), 7, "Eb/G" },
    { 6, "maj", K(6, "major"), 10, "F#/A#" }, { 7, "7", K(0, "major"), 5, "G7/F" },
    { 11, "dim", K(0, "major"), nil, "Bdim" }, { 8, "7", K(4, "major"), nil, "G#7" },
    { 0, "maj", K(6, "major"), nil, "C" },  -- chromatic B# falls back to C
  }
  for _, c in ipairs(cases) do
    local got = CD.chord_name(c[1], c[2], c[3], c[4])
    check(got == c[5], ("spell %s, got %s"):format(c[5], got))
  end
  check(select(1, CD.key_name({ tonic = 3, mode = "minor" })) == "Eb minor", "Eb minor name")
  check(select(2, CD.key_name({ tonic = 8, mode = "minor" })) == "G#m", "G#m short")
end

-- 3. Min-duration Viterbi on a toy problem
do
  local E = {}
  local seq = { 1, 1, 1, 2, 1, 1, 1, 2, 2, 2 }  -- the lone 2 is a blip
  for t = 1, #seq do E[t] = { seq[t] == 1 and 1 or 0, seq[t] == 2 and 1 or 0 } end
  local p = CD._viterbi_mindur(#seq, 2, E, function() return 0 end, function() return 0 end, 2, 0.1)
  check(table.concat(p) == "1111111222", "viterbi min length removes blips: " .. table.concat(p))
  local p1 = CD._viterbi_mindur(#seq, 2, E, function() return 0 end, function() return 0 end, 1, 0.1)
  check(table.concat(p1) == "1112111222", "viterbi minLen 1 keeps them: " .. table.concat(p1))
end

-- 4. Songs
local function read_wav(path)
  local f = assert(io.open(path, "rb"))
  local d = f:read("a"); f:close()
  local ch = string.unpack("<I2", d, 23)
  local sr = string.unpack("<I4", d, 25)
  local pos = 13
  while pos < #d do
    local id, sz = d:sub(pos, pos + 3), string.unpack("<I4", d, pos + 4)
    if id == "data" then pos = pos + 8; break end
    pos = pos + 8 + sz
  end
  local x, n = {}, 0
  local count = (#d - pos + 1) // (2 * ch)
  for i = 0, count - 1 do
    local s = 0
    for c = 0, ch - 1 do s = s + string.unpack("<i2", d, pos + (i * ch + c) * 2) end
    n = n + 1; x[n] = s / (32768 * ch)
  end
  return x, sr
end

local REDUCE = { maj = "maj", ["7"] = "maj", maj7 = "maj", min = "min", m7 = "min", dim = "dim", m7b5 = "dim", aug = "aug", sus2 = "sus", sus4 = "sus" }

local songs = {}
if #arg >= 2 then for i = 2, #arg do songs[#songs + 1] = arg[i] end
else
  for _, s in ipairs({ "pop_C", "eb_ballad", "a_minor", "fsharp", "jazz_C", "modulate", "bb_minor", "detuned_fast", "silence_noise", "db_mixed", "hard_pop", "arpeggio", "rubato", "push", "waltz", "wet_mix", "wet_pad" }) do songs[#songs + 1] = s end
end

local total_exact, total_mm, total_t = 0, 0, 0
for _, song in ipairs(songs) do
  local x, sr = read_wav(dir .. "/" .. song .. ".wav")
  local truth = dofile(dir .. "/" .. song .. ".truth.lua")
  local t0 = os.clock()
  local res = CD.analyze(x, sr, { vocabulary = os.getenv("CD_VOCAB") or "full", slash_chords = os.getenv("CD_SLASH") and true })
  local el = os.clock() - t0
  local function truth_at(t)
    for _, c in ipairs(truth.chords) do if t >= c[1] and t < c[2] then return c end end
  end
  local function det_at(t)
    for _, c in ipairs(res.chords) do if t >= c.start and t < c.stop then return c end end
  end
  local exact, mm, cnt, names_ok, names_n = 0, 0, 0, 0, 0
  local t = 0
  while t < res.duration do
    local tr, de = truth_at(t), det_at(t)
    if tr then
      cnt = cnt + 1
      if de and de.root == tr[3] and de.quality == tr[4] then exact = exact + 1 end
      if de and de.root == tr[3] and REDUCE[de.quality] == REDUCE[tr[4]] then mm = mm + 1 end
    end
    t = t + 0.01
  end
  -- spelling: every detected chord whose midpoint matches the truth must have the truth's name
  local bad_names = {}
  for _, c in ipairs(res.chords) do
    local tr = truth_at(0.5 * (c.start + c.stop))
    if tr and c.root == tr[3] and c.quality == tr[4] then
      names_n = names_n + 1
      local want = tr[5]
      if not os.getenv("CD_SLASH") then want = want:gsub("/.*", "") end
      if c.name == want then names_ok = names_ok + 1 else bad_names[#bad_names + 1] = c.name .. "~" .. want end
    end
  end
  local seq = {}
  for _, c in ipairs(res.chords) do seq[#seq + 1] = c.name end
  local keyseq = {}
  for _, k in ipairs(res.keys) do keyseq[#keyseq + 1] = ("%s@%.1f"):format(k.name, k.start) end
  print(("%-14s key %-9s (want %-9s) conf %.2f  tempo %5.1f  tune %+3dc  exact %5.1f%%  majmin %5.1f%%  names %d/%d  %.1fs  chords %d")
    :format(song, res.key.name, truth.key, res.key.confidence, res.tempo or 0, res.tuning_cents, 100 * exact / cnt, 100 * mm / cnt, names_ok, names_n, el, #res.chords))
  if os.getenv("CD_VERBOSE") then
    print("   keys: " .. table.concat(keyseq, ", "))
    print("   " .. table.concat(seq, " "))
  end
  if #bad_names > 0 then print("   bad names: " .. table.concat(bad_names, " ")) end
  local key_ok = false
  for _, k in ipairs(truth.keys) do if k == res.key.name then key_ok = true end end
  check(key_ok, song .. " key " .. res.key.name)
  local areas = {}
  for _, k in ipairs(res.keys) do areas[#areas + 1] = k.name end
  check(table.concat(areas, ",") == table.concat(truth.keys, ","), song .. " key areas " .. table.concat(areas, ","))
  check(mm / cnt > 0.85, song .. " majmin accuracy")
  check(names_ok == names_n, song .. " spelling")
  total_exact, total_mm, total_t = total_exact + exact, total_mm + mm, total_t + cnt
end
if total_t > 0 then print(("TOTAL exact %.1f%%  majmin %.1f%%"):format(100 * total_exact / total_t, 100 * total_mm / total_t)) end
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)

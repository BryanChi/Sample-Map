-- Print what the engine sees in a WAV file (16/24-bit PCM or 32-bit float).
-- lua diagnose.lua file.wav
local here = arg[0]:match("^(.*)/") or "."
local CD = dofile(here .. "/../ChordDetector_Engine.lua")
local f = assert(io.open(arg[1], "rb")); local d = f:read("a"); f:close()
local fmt, ch, sr = string.unpack("<I2", d, 21), string.unpack("<I2", d, 23), string.unpack("<I4", d, 25)
local bits = string.unpack("<I2", d, 35)
local pos = 13
while pos < #d do
  local id, sz = d:sub(pos, pos + 3), string.unpack("<I4", d, pos + 4)
  if id == "data" then pos = pos + 8; break end
  pos = pos + 8 + sz + (sz % 2)
end
local bps = bits // 8
local x, n = {}, 0
local frames = (#d - pos + 1) // (bps * ch)
for i = 0, frames - 1 do
  local s = 0
  for c = 0, ch - 1 do
    local o = pos + (i * ch + c) * bps
    local v
    if fmt == 3 then v = string.unpack("<f", d, o)
    elseif bps == 2 then v = string.unpack("<i2", d, o) / 32768
    elseif bps == 3 then v = string.unpack("<i3", d, o) / 8388608
    else v = string.unpack("<i4", d, o) / 2147483648 end
    s = s + v
  end
  n = n + 1; x[n] = s / ch
end
local t0 = os.clock()
local btc
if os.getenv("CD_BTC") == "1" then
  local lib = dofile(here .. "/../ChordDetector_BTC.lua")
  btc = { lib = lib, weights = lib.load(here .. "/../ChordDetector_BTC.bin") }
end
local res = CD.analyze(x, sr, { btc = btc, nnls = ({ ["0"] = false, ["1"] = true })[os.getenv("CD_NNLS") or ""] or (os.getenv("CD_NNLS") == "key" and "key" or nil), vocabulary = os.getenv("CD_VOCAB") })
local st = res.stats
print(("file: %d ch, %d Hz, %d bit, %.1f s, analysed in %.1f s"):format(ch, sr, bits, n / sr, os.clock() - t0))
print(("key %s (conf %.2f), tempo %.1f, tuning %+d c"):format(res.key and res.key.name or "?", res.key and res.key.confidence or 0, res.tempo or 0, res.tuning_cents or 0))
print(("input peak %.3f  beats %d  silent %.0f%%  peaks/frame %.1f"):format(st.input_peak, st.beats, 100 * st.silent, st.peaks_per_frame))
print(("median per beat: best chord %.3f  no-chord %.3f  flatness %.3f"):format(st.best_chord, st.no_chord, st.flatness))
local names = {}
for i, c in ipairs(res.chords) do if i <= 40 then names[#names + 1] = c.name end end
print("chords: " .. table.concat(names, " "))

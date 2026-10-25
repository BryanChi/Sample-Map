-- Runs the REAPER action against a mocked REAPER API.
-- lua mock_reaper_test.lua WAVDIR
math.pow, math.sinh, math.cosh, math.tanh = nil, nil, nil, nil
local here = arg[0]:match("^(.*)/") or "."
local dir = arg[1] or "/tmp/cdtest"
local fails = 0
local function check(c, m) if not c then fails = fails + 1; print("FAIL " .. m) else print("ok   " .. m) end end

local function read_wav(path)
  local f = assert(io.open(path, "rb")); local d = f:read("a"); f:close()
  local x, n = {}, 0
  for i = 45, #d - 1, 2 do n = n + 1; x[n] = string.unpack("<i2", d, i) / 32768 end
  return x, string.unpack("<I4", d, 25)
end
local src, src_sr = read_wav(dir .. "/eb_ballad.wav")
local truth = dofile(dir .. "/eb_ballad.truth.lua")

local OFFS, LEN = 4.0, 30.0   -- item starts 4 s into the file and lasts 30 s
local take = { markers = { { pos = 10.0, name = "my own marker", color = 123 } }, ext = {}, name = "Ballad.wav" }
local item = { take = take }
local ext = {}
local deferred = {}
coroutine_reads = 0

reaper = {
  ColorToNative = function(r, g, b) return r | (g << 8) | (b << 16) end,
  GetExtState = function(s, k) return ext[s .. k] or "" end,
  CountSelectedMediaItems = function() return 1 end,
  GetSelectedMediaItem = function() return item end,
  GetActiveTake = function(it) return it.take end,
  TakeIsMIDI = function() return false end,
  GetSetMediaItemTakeInfo_String = function(t, k, v, set)
    if k == "P_NAME" then return true, t.name end
    if set then t.ext[k] = v; return true, v end
    return true, t.ext[k] or ""
  end,
  MB = function(m) print("MB: " .. m) end,
  GetNumTakeMarkers = function(t) return #t.markers end,
  GetTakeMarker = function(t, i) local m = t.markers[i + 1]; return m.pos, m.name, m.color end,
  DeleteTakeMarker = function(t, i) table.remove(t.markers, i + 1); return true end,
  SetTakeMarker = function(t, idx, name, pos, color)
    assert(idx == -1); t.markers[#t.markers + 1] = { pos = pos, name = name, color = color }; return #t.markers - 1
  end,
  GetMediaItemTakeInfo_Value = function(t, k)
    if k == "D_STARTOFFS" then return OFFS end
    if k == "D_PLAYRATE" then return 1 end
  end,
  GetMediaItemTake_Source = function() return "src" end,
  GetMediaSourceNumChannels = function() return 2 end,
  CreateTakeAudioAccessor = function() return "acc" end,
  GetAudioAccessorStartTime = function() return 0 end,
  GetAudioAccessorEndTime = function() return LEN end,
  DestroyAudioAccessor = function() end,
  new_array = function(n)
    local a = { n = n, d = {} }
    a.clear = function() for i = 1, n do a.d[i] = 0 end end
    a.table = function(o, s) local t = {}; for i = 1, s do t[i] = a.d[o + i - 1] end; return t end
    return a
  end,
  GetAudioAccessorSamples = function(acc, sr, nch, t, cnt, buf)
    -- like REAPER 7.79: inside a coroutine the call returns nil and the buffer stays zero
    if coroutine.isyieldable() then coroutine_reads = coroutine_reads + 1; return nil end
    for i = 0, cnt - 1 do
      local si = math.floor((OFFS + t + i / sr) * src_sr) + 1
      local v = src[si] or 0
      buf.d[i * nch + 1] = v; buf.d[i * nch + 2] = 0.5 * v
    end
    return 1
  end,
  time_precise = os.clock,
  Undo_BeginBlock = function() end, Undo_EndBlock = function(n) print("undo: " .. n) end,
  UpdateArrange = function() end,
  Help_Set = function(s) print(s) end,
  ShowConsoleMsg = function(s) io.write(s) end,
  defer = function(f) deferred[#deferred + 1] = f end,
}
gfx = setmetatable({ getchar = function() return 0 end }, { __index = function() return function() end end })

local function run()
  dofile(here .. "/../CRS_Chord Detector - Insert chord take markers.lua")
  local steps = 0
  while #deferred > 0 do local f = table.remove(deferred, 1); f(); steps = steps + 1 end
  return steps
end

local steps = run()
check(coroutine_reads == 0, "audio is never read inside a coroutine")
check(steps > 5, "analysis ran in the background (" .. steps .. " defer cycles)")
local ours = 0
for _, m in ipairs(take.markers) do if m.color ~= 123 then ours = ours + 1 end end
check(take.markers[1].name == "my own marker", "user marker kept")
for i, m in ipairs(take.markers) do if i <= 6 then print(("     %.2f  %s"):format(m.pos, m.name)) end end
-- markers are source positions: compare against the truth (file time)
local good, total = 0, 0
for _, m in ipairs(take.markers) do
  if m.color ~= 123 and not m.name:find("N.C.") then
    total = total + 1
    for _, c in ipairs(truth.chords) do
      if math.abs(c[1] - m.pos) < 0.15 and m.name:match("^(%S+)") == c[5] then good = good + 1 end
    end
  end
end
check(total > 4 and good >= total - 1, ("markers at true source positions and names (%d/%d)"):format(good, total))
check(take.markers[2].name:find("key Eb major"), "first chord carries the key")
local real = 0
for _, m in ipairs(take.markers) do if m.color ~= 123 and not m.name:find("N.C.") then real = real + 1 end end
check(real >= 8, "found real chords, not only N.C. (" .. real .. ")")
check(take.ext["P_EXT:CRS_ChordDetector"]:find("key\tEb major"), "result stored in take P_EXT")
run()
local ours2 = 0
for _, m in ipairs(take.markers) do if m.color ~= 123 then ours2 = ours2 + 1 end end
check(ours2 == ours, "re-run replaces its own markers (" .. ours .. " -> " .. ours2 .. ")")
ext["CRS_ChordDetectormark_no_chord"] = "0"
ext["CRS_ChordDetectorkey_in_marker"] = "0"
run()
local nc = false
for _, m in ipairs(take.markers) do if m.name:find("N.C.") or m.name:find("key") then nc = true end end
check(not nc, "settings: no N.C. and no key text")
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)

"""Rough frame profiler: loads Sample Map Browser with the stub REAPER API from
load_browser.py, seeds a fake library (samples) and a fake sequencer project,
then times every global Lua function and counts REAPER API calls per frame in
the Sample Map and Sequencer views. Numbers are relative (stub ImGui calls cost
almost nothing), so use it to compare before/after a change, not as absolute
frame times. Requires `pip install lupa`.

usage: python3 tests/profile_browser.py [repo_dir] [frames] [samples] [tracks] [top]"""
import sys, os, re, tempfile
from lupa import lua54

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, ".."))
frames = int(sys.argv[2]) if len(sys.argv) > 2 else 60
n_samples = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
n_tracks = int(sys.argv[4]) if len(sys.argv) > 4 else 12
top = int(sys.argv[5]) if len(sys.argv) > 5 else 25

src = open(os.path.join(here, "load_browser.py"), encoding="utf-8").read()
stub = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)

L = lua54.LuaRuntime(unpack_returned_tuples=True)
g = L.globals()
g.REPO = repo; g.RES = tempfile.mkdtemp(); g.FRAMES = frames
g.NSAMPLES = n_samples; g.NTRACKS = n_tracks; g.TOP = top

out = L.execute(stub + r'''
-- Fake project: NTRACKS tracks with stable GUIDs and names; no items.
local tracks, guid_of, name_of = {}, {}, {}
for i = 1, NTRACKS do
  local t = "TRK" .. i
  tracks[i] = t; guid_of[t] = ("{%08d-0000-0000-0000-000000000000}"):format(i); name_of[t] = "Drum " .. i
end
special.CountTracks = function() return #tracks end
special.GetTrack = function(_, i) return tracks[i + 1] end
special.GetTrackGUID = function(t) return guid_of[t] or "{0}" end
special.ValidatePtr = function(p) return type(p) == "string" and (guid_of[p] ~= nil) end
special.ValidatePtr2 = function(_, p) return type(p) == "string" and (guid_of[p] ~= nil) end
special.BR_GetMediaTrackByGUID = function(_, g) for t, gg in pairs(guid_of) do if gg == g then return t end end end
special.GetTrackName = function(t) return true, name_of[t] or "" end
special.GetSetMediaTrackInfo_String = function(t, k, v, set)
  if k == "P_NAME" then return true, name_of[t] or "" end
  if k == "GUID" then return true, guid_of[t] or "" end
  return false, ""
end
special.GetMediaTrackInfo_Value = function() return 0 end
special.CountTrackMediaItems = function() return 0 end
special.ImGui_IsWindowHovered = function() return true end
local img_n = 0
special.ImGui_CreateImage = function() img_n = img_n + 1; return { img = img_n } end
special.ImGui_Attach = function() end
special.new_array = function(n) return {} end
special.ImGui_GetMousePos = function() return 400, 300 end
for k, f in pairs(special) do rawset(reaper, k, f) end

local apicount = {}
local real_index = getmetatable(reaper).__index
-- Count every reaper.* call (functions are cached as locals `r` in modules, so
-- wrap the table entries themselves).
setmetatable(reaper, { __index = function(t, k)
  local f = real_index(t, k)
  local w = function(...) apicount[k] = (apicount[k] or 0) + 1; return f(...) end
  rawset(t, k, w); return w end })
for k, f in pairs(special) do
  rawset(reaper, k, function(...) apicount[k] = (apicount[k] or 0) + 1; return f(...) end)
end

local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
if not chunk then return "LOADFAIL " .. err end
local ok, e = xpcall(chunk, debug.traceback)
if not ok then return "MAIN ERROR " .. tostring(e) end
if rawget(_G, "log") then log = function(m) msgs[#msgs+1] = "LOG " .. tostring(m) end end

local function run_frames(n)
  for i = 1, n do
    local q = deferred; deferred = {}
    if #q == 0 then return "no deferred fn at frame " .. i end
    for _, f in ipairs(q) do
      local ok2, e2 = xpcall(f, debug.traceback)
      if not ok2 then return ("FRAME %d ERROR %s"):format(i, tostring(e2)) end
    end
  end
end
local r0 = run_frames(10); if r0 then return r0 end

-- Seed library.
math.randomseed(7)
local tag_pool = { "kick", "snare", "clap", "hat", "tom", "ride", "crash", "perc", "fx", "bass", "vocal", "loop", "pad", "lead" }
local samples = {}
for i = 1, NSAMPLES do
  local t1 = tag_pool[(i % #tag_pool) + 1]
  local t2 = tag_pool[((i * 7) % #tag_pool) + 1]
  samples[i] = {
    path = ("/lib/pack%d/%s/%s_%05d.wav"):format(i % 40, t1, t1, i),
    name = ("%s_%05d.wav"):format(t1, i),
    x = math.random(), y = math.random(), tags = { t1, t2 }, duration = 0.1 + math.random() * 2,
    brightness = math.random(), weight = math.random(), dominant_freq = 100 + math.random() * 5000,
  }
end
state.samples = samples
rebuild_samples_path_index()
state.map_layout_version = (state.map_layout_version or 0) + 1
if sm_tag_index_rebuild_if_stale then pcall(sm_tag_index_rebuild_if_stale) end
if rebuild_tag_index then pcall(rebuild_tag_index) end

-- Seed sequencer: one track per fake REAPER track, 4 regions of 2 bars, notes on most steps.
local cfg = { seq_tracks = {}, seq_regions = {}, seq_patterns = {} }
for i = 1, NTRACKS do
  local s = samples[i]
  cfg.seq_tracks[i] = { id = i, name = "Drum " .. i, reaper_track_guid = guid_of[tracks[i]],
    sample_path = s.path, sample_name = s.name, sample_tag = s.tags[1],
    sample_candidates = { s.path, samples[i + 20].path, samples[i + 40].path } }
end
for r_i = 1, 4 do
  local notes = {}
  for tid = 1, NTRACKS do
    local row = {}
    for st = 0, 31 do if (st + tid) % 3 ~= 0 then row[tostring(st)] = { vel = 100, volume = 1.0 } end end
    notes[tostring(tid)] = row
  end
  cfg.seq_patterns[tostring(r_i)] = { notes = notes }
  cfg.seq_regions[r_i] = { id = r_i, name = "R" .. r_i, start_qn = (r_i - 1) * 8, length_bars = 2, pool_id = r_i, pattern_id = r_i }
end
cfg.seq_pattern_next_id = 5; cfg.seq_pool_next_id = 5
apply_seq_project_state(cfg)
state.seq_view_start_qn = 0; state.seq_view_span_qn = 32
state.seq_expanded_tracks = { ["1"] = true, ["2"] = true }

-- Time every global function (self + inclusive), keyed by name.
local clock = os.clock
local stat = {}
local stack, sp = {}, 0
local skip = { loop = false }
local function wrap(name, f)
  local st = { name = name, calls = 0, self = 0, incl = 0 }
  stat[name] = st
  return function(...)
    sp = sp + 1
    local my = sp
    local fr = stack[my]; if not fr then fr = {}; stack[my] = fr end
    fr.child = 0
    local t0 = clock()
    local res = table.pack(f(...))
    local dt = clock() - t0
    sp = my - 1
    st.calls = st.calls + 1
    st.incl = st.incl + dt
    st.self = st.self + dt - fr.child
    if my > 1 then stack[my - 1].child = stack[my - 1].child + dt end
    return table.unpack(res, 1, res.n)
  end
end
local libs = { string = 1, table = 1, math = 1, io = 1, os = 1, coroutine = 1, debug = 1, utf8 = 1, package = 1 }
for k, v in pairs(_G) do
  if type(v) == "function" and type(k) == "string" and not libs[k]
     and not ({ print=1, pairs=1, ipairs=1, next=1, type=1, tostring=1, tonumber=1, select=1, error=1,
        pcall=1, xpcall=1, rawget=1, rawset=1, rawequal=1, rawlen=1, setmetatable=1, getmetatable=1,
        assert=1, require=1, load=1, loadfile=1, dofile=1, collectgarbage=1, unpack=1, run_frames=1 })[k] then
    _G[k] = wrap(k, v)
  end
end

local report = {}
local function profile(label, view)
  state.active_view = view
  local warm = run_frames(5); if warm then report[#report+1] = label .. " " .. warm; return end
  for _, st in pairs(stat) do st.calls, st.self, st.incl = 0, 0, 0 end
  for k in pairs(apicount) do apicount[k] = 0 end
  collectgarbage("collect")
  local mem0 = collectgarbage("count")
  collectgarbage("stop")
  local t0 = clock()
  local e2 = run_frames(FRAMES)
  local total = clock() - t0
  local alloc = collectgarbage("count") - mem0
  collectgarbage("restart")
  if e2 then report[#report+1] = label .. " " .. e2 end
  report[#report+1] = ("== %s: %.3f ms/frame CPU, %.0f KB allocated/frame (%d frames)"):format(
    label, total * 1000 / FRAMES, alloc / FRAMES, FRAMES)
  local rows = {}
  for _, st in pairs(stat) do if st.calls > 0 then rows[#rows+1] = st end end
  table.sort(rows, function(a, b) return a.self > b.self end)
  report[#report+1] = "  self ms/f  incl ms/f  calls/f  function"
  for i = 1, math.min(TOP, #rows) do
    local st = rows[i]
    report[#report+1] = ("  %9.3f  %9.3f  %7.1f  %s"):format(st.self * 1000 / FRAMES, st.incl * 1000 / FRAMES, st.calls / FRAMES, st.name)
  end
  local api = {}
  local api_total = 0
  for k, n in pairs(apicount) do if n > 0 then api[#api+1] = { k, n }; api_total = api_total + n end end
  table.sort(api, function(a, b) return a[2] > b[2] end)
  report[#report+1] = ("  REAPER/ImGui calls per frame: %.0f; top:"):format(api_total / FRAMES)
  for i = 1, math.min(15, #api) do
    report[#report+1] = ("    %8.1f  %s"):format(api[i][2] / FRAMES, api[i][1])
  end
end
profile("Sample Map", "sample_map")
profile("Sequencer", "sequencer")
-- Zoom in (arrange shows 4 QN) so cells are wide enough for full note drawing,
-- lock/filter spans and the cell grid.
rawset(reaper, "GetSet_ArrangeView2", function() return 0, 2 end)
profile("Sequencer zoomed in", "sequencer")
for _, m in ipairs(msgs) do if m:find("ERROR") or m:find("rror") then report[#report+1] = m:sub(1, 400) end end
return table.concat(report, "\n")
''')
print(out)

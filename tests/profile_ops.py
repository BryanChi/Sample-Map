"""Edit-operation profiler: loads the browser modules on the in-memory REAPER
project from tests/fake_reaper.lua, renders a sequencer song to arrange items,
then counts REAPER API calls and Lua time for single user edits (paint a note,
erase a note, finish a gain drag, move a note, move a region, undo) and for the
sync work on the frames that follow. In REAPER each API call crosses into C
and item edits trigger REAPER's own bookkeeping, so the call counts matter
more than the Lua time. Requires `pip install lupa`.

usage: python3 tests/profile_ops.py [repo_dir] [regions] [tracks]"""
import os
import sys

from lupa import lua54

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, ".."))
n_regions = int(sys.argv[2]) if len(sys.argv) > 2 else 16
n_tracks = int(sys.argv[3]) if len(sys.argv) > 3 else 8

sys.path.insert(0, here)
import test_seq_sync as T  # noqa: E402  (reuses its SETUP helpers)

L = lua54.LuaRuntime(unpack_returned_tuples=True)
g = L.globals()
import tempfile  # noqa: E402
g.FAKE_RES = tempfile.mkdtemp()
with open(os.path.join(repo, "tests", "fake_reaper.lua"), "rb") as fh:
    L.execute(fh.read())
# Count every reaper.* call. Modules cache `local r = reaper`, so wrap before
# loading them.
L.execute(r'''
CNT = {}
API_T = 0
local real = reaper
reaper = setmetatable({}, { __index = function(t, k)
  local f = real[k]
  if f == nil then return nil end
  local w = function(...)
    CNT[k] = (CNT[k] or 0) + 1
    local t0 = os.clock()
    local res = table.pack(f(...))
    API_T = API_T + (os.clock() - t0)
    return table.unpack(res, 1, res.n)
  end
  rawset(t, k, w)
  return w
end })
''')
for name in sorted(os.listdir(os.path.join(repo, "browser"))):
    if name.endswith(".lua") and name not in T.SKIP:
        with open(os.path.join(repo, "browser", name), "rb") as fh:
            L.execute(fh.read())
L.execute("REAL_SAVE_CONFIG = save_config")
L.execute(T.SETUP)
g.NREG = n_regions
g.NTRK = n_tracks

out = L.execute(r'''
local names = {}
for i = 1, NTRK do names[i] = "T" .. i end
local regions = {}
for i = 1, NREG do
  -- Two-bar regions; every fourth one shares pattern 1 (pooled copies).
  regions[i] = { start_qn = (i - 1) * 8, bars = 2, pattern = (i % 4 == 1) and 1 or i }
end
setup({ tracks = names, regions = regions })
for i = 4, NTRK do fake_add_file("/s/t" .. i .. ".wav", 1.0); state.seq_tracks[i].sample_path = "/s/t" .. i .. ".wav" end
state.samples = {}
for i, slot in ipairs(state.seq_tracks) do
  state.samples[i] = { path = slot.sample_path, name = "s" .. i .. ".wav", duration = 1.0 }
end
rebuild_samples_path_index()
local seen = {}
for _, reg in ipairs(state.seq_regions) do
  if not seen[reg.pattern_id] then
    seen[reg.pattern_id] = true
    for tid = 1, NTRK do
      for st = 0, 31 do
        if (st + tid) % 3 ~= 0 then note_at(reg.pattern_id, tid, st * 0.25) end
      end
    end
  end
end
render_all()
FAKE.now = 1000; frame(); FAKE.now = 1001; frame()
-- An earlier edit in the session: undo snapshots then share unchanged parts.
local warm = begin_seq_undo("warm up"); end_seq_undo(warm)
save_config = REAL_SAVE_CONFIG

local clock = os.clock
local report = {}
-- Cost of the counting wrapper itself per call, taken out of script time.
local WRAP_COST
do
  rawset(reaper, "__noop", nil)
  local real_noop = function() end
  local w = function(...)
    CNT.__noop = (CNT.__noop or 0) + 1
    local t0 = os.clock()
    local res = table.pack(real_noop(...))
    API_T = API_T + (os.clock() - t0)
    return table.unpack(res, 1, res.n)
  end
  collectgarbage("collect"); collectgarbage("stop")
  local t0 = clock()
  for i = 1, 200000 do w(i) end
  local t1 = clock()
  for i = 1, 200000 do real_noop(i) end
  local t2 = clock()
  collectgarbage("restart")
  WRAP_COST = math.max(0, ((t1 - t0) - (t2 - t1)) / 200000)
  CNT.__noop = nil
end
local items = 0
for _, tr in ipairs(TR) do items = items + #fake_items(tr) end
report[#report + 1] = ("Project: %d tracks, %d two-bar regions, %d items"):format(NTRK, NREG, items)

local function measure(label, fn)
  for k in pairs(CNT) do CNT[k] = nil end
  -- Garbage collection is paused while timing so its pauses don't land on
  -- whichever operation happens to trigger them.
  collectgarbage("collect")
  collectgarbage("stop")
  API_T = 0
  local t0 = clock()
  fn()
  -- What the main loop does after every frame.
  if seq_sync_frame_end then seq_sync_frame_end() end
  -- Script time only: the fake REAPER API is Lua too, so its time is taken out.
  local dt = clock() - t0 - API_T
  collectgarbage("restart")
  local ncalls = 0
  for _, n in pairs(CNT) do ncalls = ncalls + n end
  -- API_T already holds the inner part of each wrapper; take out the rest.
  dt = math.max(0, dt - ncalls * WRAP_COST * 0.5)
  local total, rows = 0, {}
  for k, n in pairs(CNT) do total = total + n; rows[#rows + 1] = { k, n } end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  local top = {}
  for i = 1, math.min(6, #rows) do top[#top + 1] = rows[i][1] .. " " .. rows[i][2] end
  report[#report + 1] = ("%-34s %7d API calls %8.2f ms script   %s"):format(label, total, dt * 1000, table.concat(top, ", "))
end

local function settle()
  FAKE.now = (FAKE.now or 0) + 1; frame()
  FAKE.now = FAKE.now + 1; frame()
end

local reg = state.seq_regions[2]
local slot = state.seq_tracks[1]
measure("idle frame (nothing changed)", function() FAKE.now = FAKE.now + 0.05; frame() end)

measure("paint one note", function()
  local label = begin_seq_undo("Paint sequencer notes")
  toggle_seq_note(reg, slot, nil, 0.25 * 2, "paint", { defer_save = true })
  end_seq_undo(label)
  seq_schedule_ingest_save()
end)
measure("  frames after it", settle)

measure("erase one note", function()
  local label = begin_seq_undo("Erase sequencer notes")
  toggle_seq_note(reg, slot, nil, 0.25 * 2, "erase", { defer_save = true })
  end_seq_undo(label)
  seq_schedule_ingest_save()
end)
measure("  frames after it", settle)

measure("paint a note in a pooled region", function()
  local label = begin_seq_undo("Paint sequencer notes")
  toggle_seq_note(state.seq_regions[1], slot, nil, 0.25 * 2, "paint", { defer_save = true })
  end_seq_undo(label)
end)
measure("  frames after it", settle)

measure("gain drag release (8 notes)", function()
  local label = begin_seq_undo("Edit sequencer Gain")
  local n = 0
  for _, note in pairs(get_track_note_table(get_seq_pattern(reg.pattern_id), slot.id)) do
    if type(note) == "table" and n < 8 then note.volume = 0.5; n = n + 1 end
  end
  sync_seq_pattern_track(reg.pattern_id, slot, { force_rebuild = true })
  end_seq_undo(label)
  seq_schedule_ingest_save()
end)
measure("  frames after it", settle)

measure("move region by one bar", function()
  local label = begin_seq_undo("Move sequencer region")
  local last = state.seq_regions[#state.seq_regions]
  last.start_qn = last.start_qn + 4
  sync_seq_region(last)
  end_seq_undo(label)
end)
measure("  frames after it", settle)

measure("undo", function() seq_undo() end)
measure("  frames after it", settle)

measure("undo bookkeeping alone (begin+end)", function()
  local label = begin_seq_undo("Paint sequencer notes"); end_seq_undo(label)
end)
measure("save project state", function() save_seq_project_state() end)
measure("save config (file + project state)", function() save_config() end)
return table.concat(report, "\n")
''')
print(out)

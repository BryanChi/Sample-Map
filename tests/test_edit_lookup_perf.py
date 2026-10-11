"""Sequencer edits find their arrange items through an edit-scoped index
(seq_item_scope, browser/23_seq_render_items.lua) that enumerates each track
and reads each tag at most once per edit, and can take a track's tags from the
arrange baseline when that baseline is current. These tests check that the
indexed lookups delete exactly the items, in exactly the order, that the old
full scans did, also after the user edits, duplicates or deletes items behind
the script's back. Uses the in-memory REAPER project from
tests/fake_reaper.lua via test_seq_sync. Requires `pip install lupa`."""
import os
import sys
import tempfile

from lupa import lua54

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_seq_sync import ROOT, SETUP, SKIP, run  # noqa: E402

# The full-scan implementations the index replaced, verbatim. Loading them
# (plus a plain-scan seq_scope_track_matches for the retarget path) turns a
# runtime into the reference.
OLD_SCANS = r'''
function remove_seq_rendered_items(region)
  local removed = 0
  local region_id = region and region.id or nil
  local tr_count = reaper.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = reaper.GetTrack(0, tr_idx)
    local removed_here = removed
    for item_idx = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item, region_id) then
        if reaper.DeleteTrackMediaItem(tr, item) then
          removed = removed + 1
        end
      end
    end
    if removed > removed_here then
      seq_mark_self_arrange_write(tr, region_id)
    end
  end
  return removed
end

function remove_seq_rendered_items_by_ids(id_set)
  if type(id_set) ~= "table" then
    return 0
  end
  local removed = 0
  local tr_count = reaper.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = reaper.GetTrack(0, tr_idx)
    for item_idx = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(tr, item_idx)
      if item and get_item_ext(item, SEQ_EXT_FLAG) == "1" then
        local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
        if rid and id_set[rid] then
          if reaper.DeleteTrackMediaItem(tr, item) then
            removed = removed + 1
            seq_mark_self_arrange_write(tr, rid)
          end
        end
      end
    end
  end
  return removed
end

function remove_seq_rendered_items_for_track(region, slot, track_id)
  if not region then
    return 0
  end
  local region_id = region.id
  local track_key = tostring(track_id)
  local removed = 0
  local function scan_track(tr)
    if not tr then
      return
    end
    for item_idx = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item, region_id)
         and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == track_key then
        if reaper.DeleteTrackMediaItem(tr, item) then
          removed = removed + 1
          seq_mark_self_arrange_write(tr, region_id)
        end
      end
    end
  end
  local tr = slot and seq_ingest_slot_track(slot)
  if tr then
    scan_track(tr)
  else
    for tr_idx = 0, reaper.CountTracks(0) - 1 do
      scan_track(reaper.GetTrack(0, tr_idx))
    end
  end
  return removed
end

function remove_seq_rendered_items_for_step(region, slot, track_id, step_key)
  if not region then
    return 0
  end
  local region_id = region.id
  local track_key = tostring(track_id)
  local step = tostring(step_key)
  local removed = 0
  local function scan_track(tr)
    if not tr then
      return
    end
    for item_idx = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(tr, item_idx)
      if item and tostring(get_item_ext(item, SEQ_EXT_STEP) or "") == step
         and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == track_key
         and seq_item_is_owned(item, region_id) then
        if reaper.DeleteTrackMediaItem(tr, item) then
          removed = removed + 1
          seq_mark_self_arrange_write(tr, region_id)
        end
      end
    end
  end
  local tr = slot and seq_ingest_slot_track(slot)
  if tr then
    scan_track(tr)
  else
    for tr_idx = 0, reaper.CountTracks(0) - 1 do
      scan_track(reaper.GetTrack(0, tr_idx))
    end
  end
  return removed
end

function seq_scope_track_matches(tr, match)
  local out = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local item = reaper.GetTrackMediaItem(tr, i)
    if item then
      local e = { item = item }
      if match(e) then
        out[#out + 1] = e
      end
    end
  end
  return out, { n = 0 }
end
'''

# Logs every REAPER write (items by GUID) and counts every call. pairs()
# visits keys in sorted order so two runtimes make the same calls in the same
# order (the real order depends on a per-runtime hash seed).
LOGGER = r'''
do
  local raw_next, rawget, sort, type, tostring = next, rawget, table.sort, type, tostring
  local rank = { number = 1, string = 2, boolean = 3 }
  local function lt(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return (rank[ta] or 9) < (rank[tb] or 9) end
    if ta == "number" or ta == "string" then return a < b end
    if ta == "boolean" then return (not a) and b end
    local ga = ta == "table" and rawget(a, "guid") or nil
    local gb = tb == "table" and rawget(b, "guid") or nil
    if ga and gb then return ga < gb end
    return tostring(a) < tostring(b)
  end
  pairs = function(t)
    local keys, n = {}, 0
    for k in raw_next, t do n = n + 1; keys[n] = k end
    sort(keys, lt)
    local i = 0
    return function()
      while true do
        i = i + 1
        local k = keys[i]
        if k == nil then return nil end
        local v = rawget(t, k)
        if v ~= nil then return k, v end
      end
    end, t, nil
  end
end
WLOG, NCALL = {}, {}
local real = reaper
local function norm(v)
  if type(v) == "table" then
    if v.kind == "item" then return "I" .. v.guid end
    if v.kind == "take" then return "K" .. v.item.guid end
    if v.kind == "track" then return "T" .. v.guid end
    if v.kind == "source" then return "S" .. tostring(v.file or v.typ) end
  elseif type(v) == "number" then
    return math.type(v) .. string.format("%.17g", v)
  end
  return tostring(v)
end
local function read_only(k)
  for _, p in ipairs({ "^Get[^S]", "^Count", "^Validate", "^Enum", "^TimeMap", "^JS_" }) do
    if k:match(p) then return true end
  end
  return k == "TakeIsMIDI" or k == "time_precise" or k == "file_exists" or k == "ColorToNative"
    or k == "Undo_CanUndo2"
end
reaper = setmetatable({}, { __index = function(t, k)
  local f = real[k]
  if f == nil then return nil end
  local is_read = read_only(k)
  local w = function(...)
    NCALL[k] = (NCALL[k] or 0) + 1
    local set = k:match("^GetSet") and select(4, ...)
    if (not is_read and not k:match("^GetSet")) or set then
      local parts = { k }
      for i = 1, select("#", ...) do parts[#parts + 1] = norm((select(i, ...))) end
      WLOG[#WLOG + 1] = table.concat(parts, " ")
    end
    return f(...)
  end
  rawset(t, k, w)
  return w
end })
'''

SCENARIO = r'''
function library_for_tracks()
  state.samples = {}
  for i, slot in ipairs(state.seq_tracks) do
    state.samples[i] = { path = slot.sample_path, name = "s" .. i .. ".wav", duration = 1.0 }
  end
  rebuild_samples_path_index()
end
function dump_items()
  local out = {}
  for ti, tr in ipairs(FAKE.P.tracks) do
    for _, it in ipairs(tr.items) do
      local keys = {}
      for k in pairs(it.strs) do keys[#keys + 1] = k .. "=" .. it.strs[k] end
      table.sort(keys)
      out[#out + 1] = ti .. " " .. it.guid .. string.format(" %.6f ", it.vals.D_POSITION) .. table.concat(keys, ",")
    end
  end
  return table.concat(out, "\n")
end
function build_song(seed)
  math.randomseed(seed)
  setup({ tracks = { "Kick", "Snare", "Hat", "Clap" },
          regions = { { start_qn = 0, bars = 2 }, { start_qn = 8, bars = 2, pattern = 1 },
                      { start_qn = 16 }, { start_qn = 20, bars = 2, pattern = 1 }, { start_qn = 32, bars = 2 } } })
  state.seq_tracks[4].sample_path = "/s/clap.wav"
  library_for_tracks()
  for _, pid in ipairs({ 1, 3, 5 }) do
    for tid = 1, 4 do
      for st = 0, 31 do
        if (st + tid + pid) % 3 ~= 0 then
          local _, n = note_at(pid, tid, st * 0.25)
          if tid == 1 and st % 5 == 0 then n.stutter = 3 end
        end
      end
    end
  end
  render_all()
  FAKE.now = 100; frame(); FAKE.now = 101; frame()
end
-- Random sequencer edits with arrange edits behind the script's back.
function run_ops(seed, steps)
  math.randomseed(seed)
  local snaps = {}
  for step = 1, steps do
    local op = math.random(1, 14)
    local reg = state.seq_regions[math.random(1, #state.seq_regions)]
    local slot = state.seq_tracks[math.random(1, #state.seq_tracks)]
    local all = fake_items()
    local victim = all[math.random(1, math.max(1, #all))]
    if op <= 4 then
      local label = begin_seq_undo("Paint sequencer notes")
      toggle_seq_note(reg, slot, nil, math.random(0, 15) * 0.25, ({ "paint", "erase" })[math.random(1, 2)], { defer_save = true })
      end_seq_undo(label)
    elseif op == 5 then
      local label = begin_seq_undo("Edit sequencer Gain")
      for _, note in pairs(get_track_note_table(get_seq_pattern(reg.pattern_id, true), slot.id, true)) do
        if type(note) == "table" and math.random() < 0.4 then note.volume = math.random(0, 15) / 10 end
      end
      sync_seq_pattern_track(reg.pattern_id, slot, { force_rebuild = true })
      end_seq_undo(label)
    elseif op == 6 then
      local label = begin_seq_undo("Move sequencer region")
      local last = state.seq_regions[#state.seq_regions]
      last.start_qn = math.max(32, last.start_qn + (math.random() < 0.5 and -4 or 4))
      sync_seq_region(last)
      end_seq_undo(label)
    elseif op == 7 then
      seq_undo()
    elseif op == 8 then
      seq_redo()
    elseif op == 9 and victim then
      fake_user_delete_item(victim)
    elseif op == 10 and victim and victim.active then
      -- The user duplicates a hit: the copy carries the same tags.
      local copy = fake_user_add_item(victim.track, victim.vals.D_POSITION, victim.vals.D_LENGTH, victim.active.src.file or KICK)
      for k, v in pairs(victim.strs) do copy.strs[k] = v end
    elseif op == 11 and victim then
      fake_user_move_item(victim, victim.vals.D_POSITION + 0.125)
    elseif op == 12 then
      snaps[#snaps + 1] = fake_snapshot()
    elseif op == 13 and #snaps > 0 then
      fake_restore(table.remove(snaps))
    elseif op == 14 then
      local label = begin_seq_undo("Swap sample")
      slot.sample_path = (slot.sample_path == HAT) and SNARE or HAT
      library_for_tracks()
      sync_seq_pattern_track(reg.pattern_id, slot)
      end_seq_undo(label)
    end
    seq_sync_frame_end()
    WLOG[#WLOG + 1] = "-- step " .. step .. " op " .. op
    FAKE.now = FAKE.now + ((math.random() < 0.3) and 0.05 or 1)
    frame()
    FAKE.now = FAKE.now + 1
    frame()
    WLOG[#WLOG + 1] = dump_items()
  end
end
'''


def _runtime(reference):
    # As test_seq_sync.runtime, with the call logger installed before the
    # modules load (they keep `local r = reaper`).
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.globals().FAKE_RES = tempfile.mkdtemp()
    with open(os.path.join(ROOT, "tests", "fake_reaper.lua"), "rb") as fh:
        L.execute(fh.read())
    L.execute(LOGGER)
    for name in sorted(os.listdir(os.path.join(ROOT, "browser"))):
        if name.endswith(".lua") and name not in SKIP:
            with open(os.path.join(ROOT, "browser", name), "rb") as fh:
                L.execute(fh.read())
    L.execute(SETUP)
    if reference:
        L.execute(OLD_SCANS)
    L.execute(SCENARIO)
    return L


def _writes(reference, seed, steps):
    L = _runtime(reference)
    run(L, "build_song(%d); WLOG = {}; run_ops(%d, %d)" % (seed, seed, steps))
    return list(L.globals().WLOG.values())


def test_edits_write_exactly_what_full_scans_wrote():
    for seed in (3, 11):
        old = _writes(True, seed, 60)
        new = _writes(False, seed, 60)
        assert len(old) == len(new)
        for i, (a, b) in enumerate(zip(old, new)):
            assert a == b, "first difference at write %d:\nold: %s\nnew: %s" % (i, a[:300], b[:300])


def test_single_edits_read_far_less_than_full_scans():
    counts = {}
    for reference in (True, False):
        L = _runtime(reference)
        counts[reference] = run(L, r'''
          build_song(5)
          local function calls()
            local n = 0
            for _, v in pairs(NCALL) do n = n + v end
            return n
          end
          local out = {}
          local function measure(fn)
            for k in pairs(NCALL) do NCALL[k] = nil end
            fn()
            out[#out + 1] = calls()
            seq_sync_frame_end(); FAKE.now = FAKE.now + 1; frame(); FAKE.now = FAKE.now + 1; frame()
          end
          local reg, slot = state.seq_regions[3], state.seq_tracks[2]
          measure(function()
            local l = begin_seq_undo("Paint sequencer notes")
            toggle_seq_note(reg, slot, nil, 0.25, "paint", { defer_save = true })
            end_seq_undo(l)
          end)
          measure(function()
            -- Pattern 1 is shared by three regions.
            local l = begin_seq_undo("Paint sequencer notes")
            toggle_seq_note(state.seq_regions[1], slot, nil, 0.75, "paint", { defer_save = true })
            end_seq_undo(l)
          end)
          measure(function()
            local l = begin_seq_undo("Move sequencer region")
            local last = state.seq_regions[#state.seq_regions]
            last.start_qn = last.start_qn + 4
            sync_seq_region(last)
            end_seq_undo(l)
          end)
          measure(function() seq_undo() end)
          return table.concat(out, ",")
        ''')
    old = [int(x) for x in counts[True].split(",")]
    new = [int(x) for x in counts[False].split(",")]
    # Paints: the track scans were nearly all of it. Region move and undo:
    # one scan of every item, next to rebuilding the region.
    assert new[0] * 4 < old[0] and new[1] * 4 < old[1], (old, new)
    assert new[2] + 500 < old[2] and new[3] + 500 < old[3], (old, new)


LOOKUP = r'''
-- Brute force: what a scan of every item on tr says, in track order.
function brute(tr, pred)
  local out = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local item = reaper.GetTrackMediaItem(tr, i)
    if pred(item) then out[#out + 1] = item.guid end
  end
  return table.concat(out, ",")
end
function scoped(tr, match)
  local hits = seq_scope_track_matches(tr, match)
  local out = {}
  for i = 1, #hits do out[#out + 1] = hits[i].item.guid end
  return table.concat(out, ",")
end
function owned_in(region_id)
  return function(item) return seq_item_is_owned(item, region_id) end,
    function(e) return seq_scope_item_owned(e, region_id) end
end
'''


def test_baseline_index_is_used_when_current_and_checked_on_hits():
    L = _runtime(False)
    out = run(L, LOOKUP + r'''
      build_song(7)
      FAKE.now = 300; frame()
      local p, m = owned_in(3)
      local res = {}
      -- Current baseline: no enumeration, tags read only on the hits.
      for k in pairs(NCALL) do NCALL[k] = nil end
      local own = seq_item_scope_open()
      local got = scoped(TR[2], m)
      seq_item_scope_close(own)
      local tag_reads, enum = NCALL.GetSetMediaItemInfo_String or 0, NCALL.GetTrackMediaItem or 0
      res[#res + 1] = tostring(got == brute(TR[2], p) and got ~= "")
      res[#res + 1] = tostring(tag_reads == 3 * #owned_items(TR[2], 3))
      res[#res + 1] = tostring(enum == 0)
      -- A tag changed behind the baseline without moving the change count:
      -- the hit is re-read, disagrees, and the whole track is read again.
      local it = owned_items(TR[2], 3)[1]
      it.strs[SEQ_EXT_REGION] = "4"
      local own2 = seq_item_scope_open()
      res[#res + 1] = tostring(scoped(TR[2], m) == brute(TR[2], p))
      res[#res + 1] = tostring(seq_item_scope.base_ok == false)
      seq_item_scope_close(own2)
      return table.concat(res, " ")
    ''')
    assert out == "true true true true true"


def test_baseline_index_is_not_used_after_arrange_edits():
    L = _runtime(False)
    out = run(L, LOOKUP + r'''
      build_song(8)
      FAKE.now = 300; frame()
      local res = {}
      local p, m = owned_in(1)
      -- The user duplicates a hit (same tags): the change count moves and
      -- the duplicate must be found.
      local src = owned_items(TR[1], 1)[2]
      local copy = fake_user_add_item(TR[1], src.vals.D_POSITION, 0.1, KICK)
      for k, v in pairs(src.strs) do copy.strs[k] = v end
      local own = seq_item_scope_open()
      res[#res + 1] = tostring(seq_scope_baseline_current())
      res[#res + 1] = tostring(scoped(TR[1], m) == brute(TR[1], p))
      seq_item_scope_close(own)
      FAKE.now = 301; frame(); FAKE.now = 302; frame()
      -- An item slipped in without moving the change count: the item count
      -- no longer matches the baseline, so the track is enumerated.
      local sneak = fake_user_add_item(TR[1], 0.0, 0.1, KICK)
      FAKE.P.changes = FAKE.P.changes - 1
      for k, v in pairs(src.strs) do sneak.strs[k] = v end
      own = seq_item_scope_open()
      res[#res + 1] = tostring(seq_scope_baseline_current())
      res[#res + 1] = tostring(scoped(TR[1], m) == brute(TR[1], p))
      seq_item_scope_close(own)
      -- Deleted behind the script's back, same count rules.
      fake_user_delete_item(owned_items(TR[1], 1)[1])
      own = seq_item_scope_open()
      res[#res + 1] = tostring(scoped(TR[1], m) == brute(TR[1], p))
      seq_item_scope_close(own)
      return table.concat(res, " ")
    ''')
    assert out == "false true true true true"


def test_scope_tracks_own_inserts_and_deletes():
    L = _runtime(False)
    out = run(L, LOOKUP + r'''
      build_song(9)
      FAKE.now = 300; frame()
      local res = {}
      local reg, slot = state.seq_regions[3], state.seq_tracks[1]
      local own = seq_item_scope_open()
      -- Index track 1, then delete through it and insert behind it.
      local p, m = owned_in(reg.id)
      res[#res + 1] = tostring(scoped(TR[1], m) == brute(TR[1], p))
      remove_seq_rendered_items_for_step(reg, slot, slot.id, "0")
      local key = note_at(reg.pattern_id, slot.id, 0.0)
      insert_seq_note_item(reg, slot, slot.id, key, get_seq_note(reg, slot.id, key))
      -- The insert matches this lookup: REAPER's order is taken again.
      local ps = function(item)
        return tostring(get_item_ext(item, SEQ_EXT_STEP) or "") == key and seq_item_is_owned(item, reg.id)
      end
      local ms = function(e)
        return seq_scope_item_step(e) == key and seq_scope_item_owned(e, reg.id)
      end
      res[#res + 1] = tostring(scoped(TR[1], ms) == brute(TR[1], ps) and brute(TR[1], ps) ~= "")
      -- An insert that doesn't match: index order plus current item numbers.
      local key2 = note_at(reg.pattern_id, slot.id, 0.5, { stutter = 3 })
      insert_seq_note_item(reg, slot, slot.id, key2, get_seq_note(reg, slot.id, key2))
      res[#res + 1] = tostring(scoped(TR[1], m) == brute(TR[1], p))
      local n = remove_seq_rendered_items_for_track(reg, slot, slot.id)
      res[#res + 1] = tostring(n > 0 and brute(TR[1], p) == "" and scoped(TR[1], m) == "")
      seq_item_scope_close(own)
      -- The scope never outlives the frame.
      seq_item_scope_open()
      seq_sync_frame_end()
      res[#res + 1] = tostring(seq_item_scope == nil)
      return table.concat(res, " ")
    ''')
    assert out == "true true true true true"


def test_index_lookups_match_full_scans_under_random_edits():
    L = _runtime(False)
    out = run(L, LOOKUP + r'''
      build_song(12)
      math.randomseed(12)
      local bad = {}
      for step = 1, 60 do
        run_ops(1000 + step, 1)
        local own = seq_item_scope_open()
        for t = 1, #TR do
          for rid = 1, #state.seq_regions + 1 do
            local p, m = owned_in(rid)
            if scoped(TR[t], m) ~= brute(TR[t], p) then bad[#bad + 1] = step .. ":" .. t .. ":" .. rid end
            local step_key = tostring(math.random(0, 7))
            local ps = function(item)
              return tostring(get_item_ext(item, SEQ_EXT_STEP) or "") == step_key
                and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == tostring(t)
                and seq_item_is_owned(item, rid)
            end
            local ms = function(e)
              return seq_scope_item_step(e) == step_key and seq_scope_item_track_tag(e) == tostring(t)
                and seq_scope_item_owned(e, rid)
            end
            if scoped(TR[t], ms) ~= brute(TR[t], ps) then bad[#bad + 1] = step .. ":" .. t .. ":" .. rid .. "s" end
          end
        end
        seq_item_scope_close(own)
      end
      return table.concat(bad, " ")
    ''')
    assert out == ""

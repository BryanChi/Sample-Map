"""The baseline arrange fingerprint is refreshed incrementally after the
script's own writes (only the items of the regions it wrote are read again).
These tests check that the incremental baseline always equals a full re-read,
and that arrange edits made after an incremental refresh are still picked up.
Uses the in-memory REAPER project from tests/fake_reaper.lua via
test_seq_sync. Requires `pip install lupa`."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_seq_sync import run, runtime  # noqa: E402

COMPARE = r'''
function fp_equal(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false, k end end
  for k, v in pairs(b) do if a[k] ~= v then return false, k end end
  return true
end
function library_for_tracks()
  state.samples = {}
  for i, slot in ipairs(state.seq_tracks) do
    state.samples[i] = { path = slot.sample_path, name = "s" .. i .. ".wav", duration = 1.0 }
  end
  rebuild_samples_path_index()
end
'''


def test_incremental_baseline_matches_full_read():
    L = runtime()
    out = run(L, COMPARE + r'''
      setup({ tracks = { "Kick", "Snare", "Hat", "Clap" },
              regions = { { start_qn = 0 }, { start_qn = 4, pattern = 1 }, { start_qn = 8 }, { start_qn = 24, bars = 2 } } })
      state.seq_tracks[4].sample_path = "/s/clap.wav"
      library_for_tracks()
      for _, pid in ipairs({ 1, 3, 4 }) do
        for tid = 1, (pid == 1) and 4 or 3 do
          for st = 0, 15 do
            if (st + tid + pid) % 3 ~= 0 then note_at(pid, tid, st * 0.25) end
          end
        end
      end
      -- A user item outside every region on a track the moving region never
      -- writes; region moves carry the region over it.
      fake_user_add_item(TR[4], qn_to_time(21), 0.2, "/s/clap.wav")
      render_all()
      FAKE.now = 100; frame()
      math.randomseed(21)
      local bad, incremental = {}, 0
      for step = 1, 120 do
        local op = math.random(1, 6)
        local reg = state.seq_regions[math.random(1, #state.seq_regions)]
        local slot = state.seq_tracks[math.random(1, #state.seq_tracks)]
        local label = begin_seq_undo("test edit")
        if op == 1 then
          toggle_seq_note(reg, slot, nil, math.random(0, 15) * 0.25, nil, { defer_save = true })
        elseif op == 2 then
          for _, note in pairs(get_track_note_table(get_seq_pattern(reg.pattern_id, true), slot.id, true)) do
            if type(note) == "table" and math.random() < 0.4 then note.volume = math.random() * 1.5 end
          end
          sync_seq_pattern_track(reg.pattern_id, slot, { force_rebuild = true })
        elseif op == 3 then
          -- Move the last region by a bar (stays clear of the others).
          local last = state.seq_regions[#state.seq_regions]
          last.start_qn = math.min(28, math.max(16, last.start_qn + (math.random() < 0.5 and -4 or 4)))
          sync_seq_region(last)
        elseif op == 4 then
          sync_seq_region(reg)
        elseif op == 6 then
          -- Swap the slot's sample: existing items get the new source in place.
          slot.sample_path = (slot.sample_path == HAT) and SNARE or HAT
          library_for_tracks()
          sync_seq_pattern_track(reg.pattern_id, slot)
        end
        end_seq_undo(label)
        if op == 5 then seq_undo() end
        seq_sync_frame_end()
        if type(state.seq_fp_touched) == "table" then incremental = incremental + 1 end
        FAKE.now = FAKE.now + 1
        frame()
        local full = seq_arrange_fingerprints()
        local ok, rid = fp_equal(state.seq_arrange_fp, full)
        if not ok then
          bad[#bad + 1] = ("step %d op %d: region %s differs"):format(step, op, tostring(rid))
          state.seq_arrange_fp, state.seq_arrange_fp_meta = full, nil
        end
      end
      return table.concat(bad, "\n") .. "|" .. incremental
    ''')
    problems, incremental = out.rsplit("|", 1)
    assert problems == ""
    # Most steps must have gone through the incremental path.
    assert int(incremental) > 60


def test_arrange_edits_after_incremental_refresh_are_ingested():
    L = runtime()
    out = run(L, COMPARE + r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      library_for_tracks()
      note_at(1, 1, 0); note_at(1, 1, 1); note_at(2, 1, 0); note_at(2, 1, 2)
      render_all()
      FAKE.now = 200; frame()
      -- A sequencer edit in region 1 on track 1: the baseline refresh re-reads
      -- only region 1's items there and reuses region 2's.
      local label = begin_seq_undo("Paint sequencer notes")
      toggle_seq_note(state.seq_regions[1], state.seq_tracks[1], nil, 0.5, "paint", { defer_save = true })
      end_seq_undo(label)
      seq_sync_frame_end()
      FAKE.now = 201; frame()
      local reused = type(state.seq_arrange_fp_meta) == "table"
      -- Now the user moves a region-2 item and changes a region-1 item's volume.
      local it2 = owned_items(TR[1], 2)[2]
      fake_user_move_item(it2, qn_to_time(4 + 3))
      local it1 = owned_items(TR[1], 1)[1]
      fake_user_set_take(it1, "D_VOL", 0.5)
      FAKE.now = 202; frame(); FAKE.now = 203; frame()
      local v = notes_of(1, 1)[1].volume
      return qns_of(1, 1) .. "|" .. qns_of(2, 1) .. "|" .. string.format("%.2f", v) .. "|" .. tostring(reused)
    ''')
    assert out == "0,0.5,1|0,3|0.50|true"


def test_undo_snapshots_share_unchanged_patterns():
    L = runtime()
    out = run(L, COMPARE + r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      library_for_tracks()
      note_at(1, 1, 0); note_at(2, 1, 0)
      render_all()
      local label = begin_seq_undo("Paint sequencer notes")
      toggle_seq_note(state.seq_regions[1], state.seq_tracks[1], nil, 0.5, "paint", { defer_save = true })
      end_seq_undo(label)
      local e = seq_undo_stack[#seq_undo_stack]
      local function pat(snap, pid)
        return snap.seq_patterns[pid] or snap.seq_patterns[tostring(pid)]
      end
      local shared = pat(e.before, 2) ~= nil and pat(e.before, 2) == pat(e.after, 2)
      local separate = pat(e.before, 1) ~= nil and pat(e.before, 1) ~= pat(e.after, 1)
      local live = pat(e.after, 1) ~= pat(state, 1)
      -- A session that changes nothing adds no entry.
      local n = #seq_undo_stack
      local l2 = begin_seq_undo("noop"); end_seq_undo(l2)
      seq_undo()
      return tostring(shared) .. tostring(separate) .. tostring(live) .. "|" .. (#seq_undo_stack - n + 1)
        .. "|" .. qns_of(1, 1)
    ''')
    assert out == "truetruetrue|0|0"

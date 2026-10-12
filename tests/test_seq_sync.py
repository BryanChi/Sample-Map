"""Arrange <-> sequencer sync scenarios against an in-memory REAPER project
(tests/fake_reaper.lua). Each test builds sequencer state, renders it to
arrange items, makes the kind of edit a user would make in REAPER, and checks
what the sequencer ends up with. Requires `pip install lupa`."""
import os
import tempfile

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

SKIP = {"48_main_entry.lua"}

SETUP = r'''
ctx = {}
log = function(m) LOGS[#LOGS + 1] = tostring(m) end
save_config = function() end
LOGS = {}

KICK, SNARE, HAT = "/s/kick.wav", "/s/snare.wav", "/s/hat.wav"

-- One bar = 4 QN = 2 s. Regions are 1 bar unless a test says otherwise.
function setup(opts)
  opts = opts or {}
  fake_reset()
  for _, p in ipairs({ KICK, SNARE, HAT, "/s/clap.wav" }) do fake_add_file(p, 1.0) end
  reset_seq_project_state()
  seq_path_exists_cache = {}
  seq_sample_len_sec_cache = {}
  seq_item_guid_lookup_cache = nil
  state.seq_grid_qn = 0.25
  state.seq_tracks = {}
  local names = opts.tracks or { "Kick", "Snare" }
  local paths = { KICK, SNARE, HAT }
  TR = {}
  for i, name in ipairs(names) do
    local tr = fake_add_track(name)
    TR[i] = tr
    state.seq_tracks[i] = { id = i, name = name, reaper_track_guid = tr.guid, sample_path = paths[i], sample_name = name }
    seq_normalize_slot_mix(state.seq_tracks[i])
  end
  state.seq_track_next_id = #names + 1
  state.seq_regions = {}
  state.seq_patterns = {}
  local regions = opts.regions or { { start_qn = 0 } }
  for i, spec in ipairs(regions) do
    state.seq_regions[i] = {
      id = i, name = "R" .. i, start_qn = spec.start_qn, length_bars = spec.bars or 1,
      pattern_id = spec.pattern or i, pool_id = spec.pool or spec.pattern or i, groove = "off",
    }
    get_seq_pattern(spec.pattern or i, true)
  end
  state.seq_region_next_id = #regions + 1
  state.seq_pattern_next_id = 10
  state.seq_pool_next_id = 10
  state.selected_seq_region_id = 1
  for _, region in ipairs(state.seq_regions) do
    seq_sync_region_parent_item(region)
  end
end

function note_at(pattern_id, track_id, qn, extra)
  local key = seq_storage_key_from_qn(qn)
  local n = {
    enabled = true, step = math.floor(qn / 0.25 + 1e-9), qn_offset = qn,
    volume = 1.0, pan = 0.0, pitch = 0.0, offset_qn = 0.0, stutter = 1, sample_vary = 0.0,
  }
  for k, v in pairs(extra or {}) do n[k] = v end
  local notes = get_track_note_table(get_seq_pattern(pattern_id, true), track_id, true)
  notes[key] = n
  return key, n
end

function render_all()
  for _, region in ipairs(state.seq_regions) do
    sync_seq_region(region)
  end
  -- Settle: what the main loop does on the frames after a script write.
  frame()
end

-- One main-loop tick as far as sync is concerned.
function frame()
  ingest_seq_from_arrange()
  if seq_sync_frame_end then seq_sync_frame_end() end
end

function notes_of(pattern_id, track_id)
  local out = {}
  local notes = get_track_note_table(get_seq_pattern(pattern_id, false), track_id, false) or {}
  for key, n in pairs(notes) do
    if type(n) == "table" then
      out[#out + 1] = n
    end
  end
  table.sort(out, function(a, b)
    return (a.qn_offset + (a.offset_qn or 0)) < (b.qn_offset + (b.offset_qn or 0))
  end)
  return out
end

function qns_of(pattern_id, track_id)
  local parts = {}
  for _, n in ipairs(notes_of(pattern_id, track_id)) do
    parts[#parts + 1] = string.format("%g", n.qn_offset + (n.offset_qn or 0))
  end
  return table.concat(parts, ",")
end

function owned_items(tr, region_id)
  local out = {}
  for _, it in ipairs(fake_items(tr)) do
    if seq_item_is_owned(it, region_id) then
      out[#out + 1] = it
    end
  end
  return out
end

function item_qns(tr, region_id)
  local parts = {}
  for _, it in ipairs(owned_items(tr, region_id)) do
    parts[#parts + 1] = string.format("%g", time_to_qn(it.vals.D_POSITION))
  end
  table.sort(parts, function(a, b) return tonumber(a) < tonumber(b) end)
  return table.concat(parts, ",")
end
'''


def runtime():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    res = tempfile.mkdtemp()
    L.globals().FAKE_RES = res
    with open(os.path.join(ROOT, "tests", "fake_reaper.lua"), "rb") as fh:
        L.execute(fh.read())
    for name in sorted(os.listdir(os.path.join(ROOT, "browser"))):
        if not name.endswith(".lua") or name in SKIP:
            continue
        with open(os.path.join(ROOT, "browser", name), "rb") as fh:
            L.execute(fh.read())
    L.execute(SETUP)
    return L


def run(L, code):
    return L.execute(code)


def test_render_then_ingest_changes_nothing():
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 1, 1); note_at(1, 1, 2.5)
      note_at(1, 2, 1); note_at(1, 2, 3)
      render_all()
      -- An unrelated project change forces a full ingest of the region.
      fake_user_set_track(TR[1], "I_FOLDERDEPTH", 0)
      frame()
      return qns_of(1, 1) .. "|" .. qns_of(1, 2) .. "|" .. item_qns(TR[1], 1) .. "|" .. item_qns(TR[2], 1)
    ''')
    assert out == "0,1,2.5|1,3|0,1,2.5|1,3"


def test_arrange_move_is_ingested():
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 1, 1)
      render_all()
      local it = owned_items(TR[1], 1)[2]
      fake_select_only({ it })
      fake_user_move_item(it, qn_to_time(2))
      FAKE.now = 100; frame(); FAKE.now = 101; frame()
      return qns_of(1, 1)
    ''')
    assert out == "0,2"


def test_delete_in_unselected_region_is_ingested():
    # Region 2 is not the selected one and the deleted item can't stay
    # selected, so only a whole-project check can notice it.
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 0); note_at(2, 1, 0); note_at(2, 1, 2)
      render_all()
      local victim = owned_items(TR[1], 2)[2]
      fake_user_delete_item(victim)
      frame()
      return qns_of(2, 1) .. "|" .. qns_of(1, 1)
    ''')
    assert out == "0|0"


def test_volume_edit_in_unselected_region_is_ingested():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 0); note_at(2, 1, 1)
      render_all()
      local it = owned_items(TR[1], 2)[1]
      fake_user_set_take(it, "D_VOL", 0.5)
      frame()
      return string.format("%.2f", notes_of(2, 1)[1].volume)
    ''')
    assert out == "0.50"


def test_user_edit_right_after_script_write_is_not_swallowed():
    # The script writes arrange items in one frame; the user edits arrange
    # before the next frame. The next ingest must still see the user's edit.
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 1, 1); note_at(1, 2, 2)
      render_all()
      -- Frame N: a sequencer edit re-renders the snare track.
      note_at(1, 2, 3)
      sync_seq_pattern_track(1, state.seq_tracks[2])
      if seq_sync_frame_end then seq_sync_frame_end() end
      -- Between frames: the user deletes a kick hit in arrange.
      fake_user_delete_item(owned_items(TR[1], 1)[2])
      -- Frame N+1
      frame()
      return qns_of(1, 1) .. "|" .. qns_of(1, 2)
    ''')
    assert out == "0|2,3"


def test_missing_sample_does_not_delete_notes():
    # Notes whose file is offline render no item. An arrange edit elsewhere
    # in the region must not read that as "the user deleted these notes".
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 2, 1); note_at(1, 2, 3)
      fake_remove_file(SNARE)
      render_all()
      fake_user_set_take(owned_items(TR[1], 1)[1], "D_VOL", 0.8)
      frame()
      return qns_of(1, 2) .. "|" .. #owned_items(TR[2], 1)
    ''')
    assert out == "1,3|0"


def test_pooled_copy_follows_volume_edit():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0, pattern = 1, pool = 1 }, { start_qn = 4, pattern = 1, pool = 1 } } })
      note_at(1, 1, 0); note_at(1, 1, 2)
      render_all()
      local it = owned_items(TR[1], 1)[2]
      fake_select_only({ it })
      fake_user_set_take(it, "D_VOL", 0.25)
      FAKE.now = 200; frame(); FAKE.now = 201; frame()
      local other = owned_items(TR[1], 2)
      local vols = {}
      for _, o in ipairs(other) do vols[#vols + 1] = string.format("%.2f", o.active.vals.D_VOL) end
      table.sort(vols)
      return string.format("%.2f", notes_of(1, 1)[2].volume) .. "|" .. table.concat(vols, ",")
    ''')
    assert out == "0.25|0.25,1.00"


def test_reaper_undo_in_unselected_region_is_ingested():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 0); note_at(2, 1, 0); note_at(2, 1, 1)
      render_all()
      local snap = fake_snapshot()
      fake_user_delete_item(owned_items(TR[1], 2)[2])
      frame()
      local after_delete = qns_of(2, 1)
      fake_restore(snap) -- Ctrl+Z in REAPER
      frame()
      return after_delete .. "|" .. qns_of(2, 1)
    ''')
    assert out == "0|0,1"


def test_track_volume_change_in_reaper_is_kept():
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0)
      render_all()
      fake_user_set_track(TR[1], "D_VOL", 0.5)
      frame()
      -- Anything that re-applies the sequencer mix must not undo the fader move.
      seq_apply_all_slot_mix_to_reaper()
      return string.format("%.2f|%.2f", state.seq_tracks[1].volume, TR[1].vals.D_VOL)
    ''')
    assert out == "0.50|0.50"


def test_unlinked_slot_does_not_steal_items():
    # A slot with no arrange track renders on the selected track. Ingest must
    # not claim another slot's items through that fallback.
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 1, 2)
      render_all()
      state.seq_tracks[3] = { id = 3, name = "Loose", sample_path = HAT }
      seq_normalize_slot_mix(state.seq_tracks[3])
      reaper.GetSelectedTrack = function() return TR[1] end
      fake_user_set_take(owned_items(TR[1], 1)[1], "D_VOL", 0.9)
      frame()
      return qns_of(1, 1) .. "|" .. qns_of(1, 3)
    ''')
    assert out == "0,2|"


def test_stuck_mix_drag_session_does_not_block_sync():
    # A mix-knob drag commits its undo step on mouse release, but only while
    # the sequencer view is drawn. If the view went away mid-drag, the open
    # session must not block arrange sync forever.
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 1, 1)
      render_all()
      begin_seq_undo("Adjust sequencer mix")
      seq_undo_commit_on_release = true
      FAKE.now = 300
      frame()
      fake_user_delete_item(owned_items(TR[1], 1)[2])
      FAKE.now = 301; frame(); FAKE.now = 302; frame()
      return qns_of(1, 1) .. "|" .. tostring(seq_undo_is_open())
    ''')
    assert out == "0|false"


IDEMPOTENT_CASES = {
    "plain": "",
    "groove": 'state.seq_regions[1].groove = "swing16_62"',
    "humanize": 'local st = get_seq_track_settings(get_seq_pattern(1), 1, true); st.humanize_ms = 15',
    "stutter": 'notes_of(1, 1)[2].stutter = 3',
    "ghosts": 'local st = get_seq_track_settings(get_seq_pattern(1), 1, true); st.ghost_grace = 1.0; st.ghost_after = 1.0',
    "probability": 'local st = get_seq_track_settings(get_seq_pattern(1), 1, true); st.probability = 0.5',
    "nudged": 'notes_of(1, 1)[2].offset_qn = 0.07',
    "params": 'local n = notes_of(1, 1)[1]; n.volume = 0.6; n.pitch = -3; n.pan = 0.4',
    "decay": 'notes_of(1, 1)[3].decay_qn = 0.5',
}


def test_fresh_render_reads_back_unchanged():
    # Ingest of a region the script just rendered must be a no-op, whatever
    # the note features. Dirty-region ingest relies on this.
    L = runtime()
    bad = []
    for name, tweak in IDEMPOTENT_CASES.items():
        out = run(L, r'''
          setup()
          note_at(1, 1, 0); note_at(1, 1, 1); note_at(1, 1, 2.5); note_at(1, 2, 1); note_at(1, 2, 3)
          %s
          sync_seq_region(state.seq_regions[1])
          local before = json_encode(get_seq_pattern(1).notes)
          local changed = seq_ingest_region_from_arrange(state.seq_regions[1])
          local after = json_encode(get_seq_pattern(1).notes)
          return tostring(changed) .. (before == after and "" or ("\n" .. before .. "\n" .. after))
        ''' % tweak)
        if out != "false":
            bad.append(name + ": " + out)
    assert bad == []


def test_region_delete_then_reaper_undo_has_no_duplicate_hits():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 0); note_at(2, 1, 0); note_at(2, 1, 1)
      render_all()
      local snap = fake_snapshot()
      local parent = select(1, seq_find_item_by_guid(state.seq_regions[2].parent_item_guid))
      fake_user_delete_item(parent)
      frame(); frame()
      local regions_after_delete = #state.seq_regions
      fake_restore(snap)
      frame(); frame(); frame()
      local r2 = state.seq_regions[2]
      return regions_after_delete .. "|" .. #state.seq_regions .. "|" .. tostring(r2 and r2.id) .. "|"
        .. #owned_items(TR[1]) .. "|" .. qns_of(r2 and r2.pattern_id or 0, 1)
    ''')
    assert out == "1|2|2|3|0,1"


def test_sample_dropped_on_track_in_unselected_region_becomes_a_note():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 0); note_at(2, 1, 0)
      render_all()
      fake_user_add_item(TR[1], qn_to_time(4 + 2), 0.2, "/s/clap.wav")
      frame()
      local n = notes_of(2, 1)
      return qns_of(2, 1) .. "|" .. tostring(n[2] and n[2].frozen_sample_path)
    ''')
    assert out == "0,2|/s/clap.wav"


def test_unselected_move_between_regions_updates_both():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 0); note_at(1, 1, 1); note_at(2, 1, 0)
      render_all()
      fake_user_move_item(owned_items(TR[1], 1)[2], qn_to_time(4 + 3))
      frame()
      return qns_of(1, 1) .. "|" .. qns_of(2, 1)
    ''')
    assert out == "0|0,3"


def test_only_own_writes_refresh_the_baseline_without_ingest():
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0)
      render_all()
      local calls = 0
      local real = seq_ingest_region_from_arrange
      seq_ingest_region_from_arrange = function(...) calls = calls + 1; return real(...) end
      note_at(1, 1, 2)
      FAKE.now = 500
      sync_seq_pattern_track(1, state.seq_tracks[1])
      seq_sync_frame_end()
      frame(); frame()
      -- Unrelated project change: nothing in any region changed.
      fake_user_set_track(TR[2], "I_FOLDERDEPTH", 0)
      frame()
      return calls .. "|" .. qns_of(1, 1) .. "|" .. item_qns(TR[1], 1)
    ''')
    assert out == "0|0,2|0,2"


def test_solo_in_place_is_not_rewritten():
    L = runtime()
    out = run(L, r'''
      setup()
      render_all()
      fake_user_set_track(TR[1], "I_SOLO", 2)
      frame()
      seq_apply_all_slot_mix_to_reaper()
      return tostring(state.seq_tracks[1].solo) .. "|" .. TR[1].vals.I_SOLO
    ''')
    assert out == "true|2"


def test_project_load_reads_faders_instead_of_overwriting_them():
    L = runtime()
    out = run(L, r'''
      setup()
      render_all()
      save_seq_project_state()
      -- Fader moved while the script was closed.
      TR[2].vals.D_VOL = 0.3
      load_seq_project_state()
      return string.format("%.2f|%.2f", state.seq_tracks[2].volume, TR[2].vals.D_VOL)
    ''')
    assert out == "0.30|0.30"


def test_pushed_downbeat_stays_in_its_region():
    # "Pushed" groove renders a region's downbeat a few ms before the region
    # starts, inside the previous region. Reading either region back must
    # neither drop that hit nor hand it to the previous region.
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      state.seq_regions[2].groove = "pushed"
      note_at(1, 1, 0); note_at(1, 1, 2); note_at(2, 1, 0); note_at(2, 1, 2)
      render_all()
      local c1 = seq_ingest_region_from_arrange(state.seq_regions[1])
      local c2 = seq_ingest_region_from_arrange(state.seq_regions[2])
      -- A user edit on that early hit lands on its own region.
      local early = owned_items(TR[1], 2)[1]
      fake_user_set_take(early, "D_VOL", 0.5)
      frame()
      return tostring(c1) .. tostring(c2) .. "|" .. qns_of(1, 1) .. "|" .. qns_of(2, 1)
        .. "|" .. string.format("%.2f", notes_of(2, 1)[1].volume)
    ''')
    assert out == "falsefalse|0,2|0,2|0.50"


def test_new_region_keeps_pushed_downbeats_of_others():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      state.seq_regions[2].groove = "pushed"
      note_at(2, 1, 0)
      render_all()
      seq_remove_orphaned_region_items()
      return item_qns(TR[1], 2)
    ''')
    assert out == "3.985"


def test_continuous_script_writes_defer_the_baseline_refresh():
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0)
      render_all()
      local n = 0
      local real = seq_arrange_fingerprints
      seq_arrange_fingerprints = function() n = n + 1; return real() end
      -- A header drag rebuilds the track every frame for ten frames.
      for i = 1, 10 do
        FAKE.now = 400 + i * 0.03
        sync_seq_pattern_track(1, state.seq_tracks[1], { force_rebuild = true })
        seq_sync_frame_end()
        frame()
      end
      local during = n
      FAKE.now = 401; frame()
      return during .. "|" .. n
    ''')
    assert out == "1|2"


def test_first_pass_without_baseline_still_reads_selected_edits():
    # Right after a project loads there is no fingerprint yet; the old
    # selection/razor heuristics still pick up the edit.
    L = runtime()
    out = run(L, r'''
      setup()
      note_at(1, 1, 0); note_at(1, 1, 1)
      render_all()
      state.seq_arrange_fp = nil
      local it = owned_items(TR[1], 1)[2]
      fake_select_only({ it })
      fake_user_move_item(it, qn_to_time(3))
      FAKE.now = 600; frame(); FAKE.now = 601; frame()
      return qns_of(1, 1) .. "|" .. tostring(state.seq_arrange_fp ~= nil)
    ''')
    assert out == "0,3|true"


def test_hit_dragged_into_pooled_copy_moves_the_note():
    # Region 3 is a pooled copy of region 1. Dragging region 1's downbeat to
    # beat 2.75 of region 3 moves the pattern note; both copies show it there.
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 }, { start_qn = 8, pattern = 1, pool = 1 } } })
      note_at(1, 1, 0); note_at(1, 1, 2)
      render_all()
      local it = owned_items(TR[1], 1)[1]
      FAKE.now = 100
      fake_user_move_item(it, qn_to_time(9.75))
      frame(); FAKE.now = 101; frame()
      return qns_of(1, 1) .. " / " .. item_qns(TR[1], 1) .. " / " .. item_qns(TR[1], 3)
    ''')
    assert out == "1.75,2 / 1.75,2 / 9.75,10"


def test_hit_moved_onto_another_patterns_step_key_is_kept():
    # The moved hit is tagged with region 1's step key for beat 3, which is
    # also the key of region 2's own beat-3 note. It must not merge into it.
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 } } })
      note_at(1, 1, 2); note_at(2, 1, 2)
      render_all()
      local it = owned_items(TR[1], 1)[1]
      FAKE.now = 100
      fake_select_only({ it })
      fake_user_move_item(it, qn_to_time(4))
      frame(); FAKE.now = 101; frame()
      return qns_of(1, 1) .. " / " .. qns_of(2, 1) .. " / " .. item_qns(TR[1], 2)
    ''')
    assert out == " / 0,2 / 4,6"


def test_random_arrange_edits_keep_notes_and_items_in_step():
    # Fuzz: random user edits in arrange interleaved with sequencer edits.
    # After each step every region's notes must match its hits one to one.
    L = runtime()
    out = run(L, r'''
      local fails = {}
      for seed = 1, 100 do
        math.randomseed(seed)
        setup({ regions = { { start_qn = 0 }, { start_qn = 4 }, { start_qn = 8, pattern = 1, pool = 1 } } })
        state.seq_tracks[1].overlap = true
        state.seq_tracks[2].overlap = true
        for p = 1, 2 do
          for t = 1, 2 do
            for _, q in ipairs({ 0, 1, 2, 3 }) do
              if math.random() < 0.5 then note_at(p, t, q) end
            end
          end
        end
        render_all()
        local snap = fake_snapshot()
        local clock = 1000 + seed * 100
        local log = {}
        for step = 1, 16 do
          clock = clock + 1
          FAKE.now = clock
          local op = math.random(1, 7)
          local t = math.random(1, 2)
          local items = owned_items(TR[t])
          if op == 1 and #items > 0 then
            local it = items[math.random(#items)]
            log[#log + 1] = "del"
            fake_user_delete_item(it)
          elseif op == 2 and #items > 0 then
            local it = items[math.random(#items)]
            local q = math.random(0, 47) * 0.25
            log[#log + 1] = "move" .. q
            fake_select_only(math.random() < 0.5 and { it } or {})
            fake_user_move_item(it, qn_to_time(q))
          elseif op == 3 and #items > 0 then
            local it = items[math.random(#items)]
            log[#log + 1] = "vol"
            fake_user_set_take(it, "D_VOL", math.random(1, 9) / 10)
          elseif op == 4 then
            local q = math.random(0, 47) * 0.25
            log[#log + 1] = "add" .. q
            fake_user_add_item(TR[t], qn_to_time(q), 0.1, t == 1 and KICK or SNARE)
          elseif op == 5 then
            local reg = state.seq_regions[math.random(1, 3)]
            local q = math.random(0, 15) * 0.25
            log[#log + 1] = "seq" .. reg.id .. "@" .. q
            local key = note_at(reg.pattern_id, t, q)
            sync_seq_pattern_note(reg.pattern_id, state.seq_tracks[t], key)
            seq_sync_frame_end()
          elseif op == 7 then
            log[#log + 1] = "undo"
            fake_restore(snap)
          else
            log[#log + 1] = "noop"
            fake_user_set_track(TR[3 - t], "I_FOLDERDEPTH", 0)
          end
          fake_select_only({})
          frame(); clock = clock + 1; FAKE.now = clock; frame()
          -- Invariant: per region and track, note positions == hit positions.
          for _, reg in ipairs(state.seq_regions) do
            for tt = 1, 2 do
              local nq = {}
              for _, n in ipairs(notes_of(reg.pattern_id, tt)) do
                nq[#nq + 1] = string.format("%.3f", reg.start_qn + n.qn_offset + (n.offset_qn or 0))
              end
              local iq = {}
              for _, it in ipairs(owned_items(TR[tt], reg.id)) do
                iq[#iq + 1] = string.format("%.3f", time_to_qn(it.vals.D_POSITION))
              end
              table.sort(nq); table.sort(iq)
              local a, b = table.concat(nq, ","), table.concat(iq, ",")
              if a ~= b then
                fails[#fails + 1] = string.format("seed %d step %d [%s] region %d track %d notes {%s} items {%s}",
                  seed, step, table.concat(log, " "), reg.id, tt, a, b)
              end
            end
          end
          if #fails > 0 then break end
        end
        if #fails > 0 then break end
      end
      return table.concat(fails, "\n")
    ''')
    assert out == ""

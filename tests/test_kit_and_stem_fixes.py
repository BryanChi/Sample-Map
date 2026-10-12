"""Tests for kit randomize / Recent kits note handling, the candidate-square
guard, stem-import hit volumes and Groove MIDI hit detail. Requires lupa."""
import os
import tempfile

from lupa import lua54

from test_pattern_library import STUB

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

MODULES = [
    "01_state.lua", "02_helpers.lua", "03_json.lua", "09_ui_helpers.lua", "11_ui_kit.lua",
    "12_seq_tracks.lua", "18_seq_regions.lua", "19_seq_random.lua", "23_seq_render_items.lua",
    "29_groove.lua", "33_seq_generate.lua", "39_seq_stem_import.lua",
]


def _runtime():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    tmp = tempfile.mkdtemp()
    L.globals().RES = tmp
    L.globals().SCRIPT_PATH = os.path.join(tmp, "Sample Map Browser.lua")
    L.globals().HOVER = False
    L.execute(STUB)
    for name in MODULES:
        with open(os.path.join(ROOT, "browser", name), "rb") as fh:
            L.execute(fh.read())
    L.execute("ctx = {}; log = function() end; save_config = function() end")
    return L


def test_stem_weight_to_volume_curve():
    L = _runtime()
    f = L.globals().seq_stem_weight_to_volume
    assert f(1.0, 1.0) == 1.0
    assert abs(f(0.0, 1.0) - L.globals().SEQ_STEM_VELOCITY_FLOOR) < 1e-9
    assert f(0.25, 1.0) < f(0.5, 1.0) < f(0.9, 1.0) < 1.0
    assert f(None, 1.0) == 1.0 and f(0.5, 0) == 1.0


def test_groove_hit_detail_sets_volume_and_timing():
    L = _runtime()
    vol, off = L.execute(r'''
      local note = { volume = 1.0, offset_qn = 0.05 }
      seq_apply_role_hit_detail(note, "hat", 1, {
        velocities = { hat = { ["1"] = 40 } },
        offsets = { hat = { ["1"] = 0.3 } },
      })
      return note.volume, note.offset_qn
    ''')
    assert abs(vol - 40 / 127.0) < 1e-9
    assert abs(off - 0.3 * 0.25) < 1e-9


def test_automatic_change_keeps_saved_candidate():
    L = _runtime()
    saved, filled, explicit = L.execute(r'''
      find_sample_by_path = function(p) return { path = p, name = p } end
      local slot = { id = 1, sample_path = "/fav.wav", sample_candidate_idx = 1,
        sample_candidates = { { path = "/fav.wav", name = "fav" } } }
      seq_without_candidate_save(seq_remember_sample_candidate, slot, { path = "/rand.wav" })
      local saved = slot.sample_candidates[1].path
      slot.sample_candidate_idx = 2
      seq_without_candidate_save(seq_remember_sample_candidate, slot, { path = "/rand.wav" })
      local filled = slot.sample_candidates[2] and slot.sample_candidates[2].path
      slot.sample_candidate_idx = 1
      seq_remember_sample_candidate(slot, { path = "/pick.wav" })
      return saved, filled, slot.sample_candidates[1].path
    ''')
    assert saved == "/fav.wav"
    assert filled == "/rand.wav"
    assert explicit == "/pick.wav"
    assert L.globals().SEQ_CANDIDATE_SAVE_BLOCK == 0


def test_kit_change_keeps_pins_and_recent_kit_restores_slices():
    L = _runtime()
    out = L.execute(r'''
      seq_path_exists = function() return true end
      local stem = { enabled = true, sample_path = "/stem.wav", frozen_sample_path = "/stem.wav",
        frozen_sample_name = "Kick", source_offset = 1.5, volume = 1.0, stem_velocity = 0.6 }
      local pinned = { enabled = true, sample_path = "/pick.wav", frozen_sample_path = "/pick.wav",
        picked_sample = true }
      state.seq_patterns = { ["1"] = { notes = { ["7"] = { a = stem, b = pinned } } } }
      local slot = { id = 7, sample_path = "/stem.wav" }
      seq_kit_unfreeze_slot_notes(slot)
      local released = stem.source_offset == nil and stem.frozen_sample_path == nil
      local vol_after = stem.volume
      local pin_kept = pinned.frozen_sample_path == "/pick.wav" and pinned.picked_sample == true
      local wrong = seq_kit_unstash_note(stem, "/other.wav")
      return released, vol_after, pin_kept, wrong
    ''')
    released, vol_after, pin_kept, wrong = out
    assert released
    assert abs(vol_after - 0.6) < 1e-9
    assert pin_kept
    assert wrong is False

    restored = L.execute(r'''
      seq_path_exists = function() return true end
      local stem = { enabled = true, sample_path = "/stem.wav", frozen_sample_path = "/stem.wav",
        source_offset = 1.5, volume = 1.0, stem_velocity = 0.6 }
      seq_kit_stash_note(stem, "/stem.wav")
      stem.source_offset = nil
      stem.frozen_sample_path = nil
      seq_note_release_stem_velocity(stem)
      stem.sample_path = "/new.wav"
      local ok = seq_kit_unstash_note(stem, "/stem.wav")
      return ok, stem.source_offset, stem.frozen_sample_path, stem.sample_path, stem.volume, stem.stem_velocity
    ''')
    ok, offs, frozen, path, vol, vel = restored
    assert ok
    assert offs == 1.5 and frozen == "/stem.wav" and path == "/stem.wav"
    assert vol == 1.0 and abs(vel - 0.6) < 1e-9

"""Sequencer track names stay in sync with their REAPER tracks: renaming in
the sequencer renames the REAPER track, a REAPER rename reaches the slot, and
undoing a rename restores both."""
from test_seq_sync import run, runtime


def test_rename_renames_reaper_track_and_undo_restores_it():
    L = runtime()
    out = run(L, r'''
      setup()
      seq_sync_track_names()
      seq_rename_track(state.seq_tracks[1], "  Big Kick ")
      local a = state.seq_tracks[1].name .. "/" .. TR[1].name
      seq_sync_track_names()
      seq_undo()
      seq_sync_track_names()
      local b = state.seq_tracks[1].name .. "/" .. TR[1].name
      seq_redo()
      seq_sync_track_names()
      local c = state.seq_tracks[1].name .. "/" .. TR[1].name
      return a .. "|" .. b .. "|" .. c
    ''')
    assert out == "Big Kick/Big Kick|Kick/Kick|Big Kick/Big Kick"


def test_reaper_rename_reaches_slot():
    L = runtime()
    out = run(L, r'''
      setup()
      seq_sync_track_names()
      reaper.GetSetMediaTrackInfo_String(TR[2], "P_NAME", "Snare Top", true)
      seq_sync_track_names()
      return state.seq_tracks[2].name .. "/" .. state.seq_tracks[1].name
    ''')
    assert out == "Snare Top/Kick"


def test_first_sight_never_renames():
    L = runtime()
    out = run(L, r'''
      setup()
      reaper.GetSetMediaTrackInfo_String(TR[1], "P_NAME", "Other", true)
      seq_sync_track_names()
      return state.seq_tracks[1].name .. "/" .. TR[1].name
    ''')
    assert out == "Kick/Other"

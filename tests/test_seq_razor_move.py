"""Razor move keeps notes whose destination has no region instead of
deleting them."""
from test_seq_sync import run, runtime


def test_razor_move_into_gap_keeps_notes():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 8 } } })
      note_at(1, 1, 0); note_at(1, 1, 2)
      render_all()
      state.seq_razors = { { start_qn = 0, end_qn = 4, track_ids = { 1 } } }
      seq_begin_razor_move(1, 1, 0.25, false)
      local drag = state.seq_razor_drag
      drag.current_qn = 5 -- 0..4 -> 4..8: the gap between the regions
      seq_razor_apply_move(drag, 0.25)
      local kept = drag.kept_in_place
      seq_commit_razor_drag(0.25)
      return qns_of(1, 1) .. "|" .. qns_of(2, 1) .. "|" .. tostring(kept) .. "|" .. tostring(state.sm_toast and state.sm_toast.text)
    ''')
    assert out == "0,2||2|2 notes had no region to land in and stayed put"


def test_razor_move_into_region_still_moves():
    L = runtime()
    out = run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 8 } } })
      note_at(1, 1, 0); note_at(1, 1, 2)
      render_all()
      state.seq_razors = { { start_qn = 0, end_qn = 4, track_ids = { 1 } } }
      seq_begin_razor_move(1, 1, 0.25, false)
      local drag = state.seq_razor_drag
      drag.current_qn = 7 -- 0..4 -> 6..10: 2 lands in region 2, 0 in the gap
      seq_razor_apply_move(drag, 0.25)
      seq_commit_razor_drag(0.25)
      return qns_of(1, 1) .. "|" .. qns_of(2, 1)
    ''')
    assert out == "0|0"

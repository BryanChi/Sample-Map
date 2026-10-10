"""Swapping regions of different lengths: the two swap places, regions in
between shift by the length difference, and nothing else moves."""
from test_seq_sync import run, runtime


def _layout(L):
    return run(L, r'''
      local parts = {}
      for _, reg in ipairs(state.seq_regions) do
        parts[#parts + 1] = reg.name .. "@" .. string.format("%g", reg.start_qn)
      end
      return table.concat(parts, ",")
    ''')


def test_swap_different_lengths_keeps_outside_regions():
    L = runtime()
    # R1: 1 bar at 0, R2: 1 bar at 4, R3: 2 bars at 8, R4: 1 bar at 16.
    run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 }, { start_qn = 8, bars = 2 }, { start_qn = 16 } } })
      PREVIEW = seq_region_swap_layout(state.seq_regions[1], state.seq_regions[3])
      seq_swap_region_positions(state.seq_regions[1], state.seq_regions[3])
    ''')
    # R3 takes R1's start, R2 shifts by +4, R1 ends where R3 ended, R4 stays.
    assert _layout(L) == "R3@0,R2@8,R1@12,R4@16"
    # The preview layout is what was applied.
    assert run(L, 'return string.format("%g,%g,%g", PREVIEW[1], PREVIEW[2], PREVIEW[3])') == "12,8,0"


def test_swap_equal_lengths_is_plain_exchange():
    L = runtime()
    run(L, r'''
      setup({ regions = { { start_qn = 0 }, { start_qn = 4 }, { start_qn = 8 } } })
      seq_swap_region_positions(state.seq_regions[3], state.seq_regions[1])
    ''')
    assert _layout(L) == "R3@0,R2@4,R1@8"

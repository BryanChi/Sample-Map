"""Pattern generation follows the project time signature: bars start on
their bar lines in 3/4 and 7/8, and 4/4 output is unchanged."""
from test_seq_sync import run, runtime

METER = r'''
function set_meter(num, denom)
  local bar = num * 4 / denom
  reaper.TimeMap_GetTimeSigAtTime = function() return num, denom, 120 end
  reaper.TimeMap2_timeToBeats = function(_, t)
    local qn = t / 0.5
    local m = math.floor(qn / bar + 1e-9)
    return qn - m * bar, m, num, qn, denom
  end
  reaper.TimeMap_GetMeasureInfo = function(_, m)
    return m * bar * 0.5, m * bar, m * bar + bar, num, denom, 120
  end
  seq_region_len_cache_reset()
end

function kick_offsets()
  local parts = {}
  for _, n in ipairs(notes_of(1, 1)) do parts[#parts + 1] = string.format("%g", n.qn_offset) end
  return table.concat(parts, ",")
end

function gen(num, denom, bars)
  setup({ tracks = { "Kick" }, regions = { { start_qn = 0, bars = bars } } })
  state.seq_tracks[1].sample_tag = "kick"
  samples_by_path[KICK] = { path = KICK, name = "kick" }
  set_meter(num, denom)
  generate_seq_pattern(state.seq_regions[1], "house", { random_strength = 0 })
  return kick_offsets()
end
'''


def _gen(num, denom, bars):
    L = runtime()
    L.execute(METER)
    return run(L, "return gen(%d, %d, %d)" % (num, denom, bars))


def test_four_four_unchanged():
    assert _gen(4, 4, 2) == "0,1,2,3,4,5,6,7"


def test_three_four_bars_start_on_bar_lines():
    # 3-QN bars: beats 1-3 of the template in each of the three bars (the
    # old 4-QN assumption only found two bars here).
    assert _gen(3, 4, 3) == "0,1,2,3,4,5,6,7,8"


def test_seven_eight_uses_real_bar_length():
    # 7/8 = 3.5 QN per bar: second bar's downbeat is at 3.5, not 4.
    assert _gen(7, 8, 2) == "0,1,2,3,3.5,4.5,5.5,6.5"


def test_bar_grid_helper():
    L = runtime()
    L.execute(METER)
    out = run(L, r'''
      setup({ regions = { { start_qn = 0, bars = 2 } } })
      local res = {}
      for _, m in ipairs({ {4, 4}, {3, 4}, {6, 8}, {7, 8} }) do
        set_meter(m[1], m[2])
        local spb, bars, s4 = seq_region_bar_grid(state.seq_regions[1], 0.25)
        res[#res + 1] = spb .. "/" .. bars .. "/" .. s4
      end
      return table.concat(res, " ")
    ''')
    assert out == "16/2/16 12/2/16 12/2/16 14/2/16"

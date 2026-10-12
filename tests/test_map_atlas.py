"""Sample Map atlas (browser/46a_map_atlas.lua): axis bounds match where
layout_samples() puts the dots, adaptive ticks, tag regions and counts."""
import math
import os
import re
import tempfile

from lupa import lua54

here = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(here, ".."))
src = open(os.path.join(here, "load_browser.py"), encoding="utf-8").read()
STUB = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)

HARNESS = r'''
local chunk = assert(loadfile(REPO .. "/Sample Map Browser.lua"))
assert(xpcall(chunk, debug.traceback))
save_config = function() end
sample_scan_folder_unavailable = function() return false end

local seed = 3
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
-- Kicks: short and low. Hats: short and high. Pads: long and mid. Plus untagged.
function make_lib()
  local samples = {}
  local function add(tag, n, d0, d1, f0, f1)
    for i = 1, n do
      local d = d0 * (d1 / d0) ^ rnd()
      local f = f0 * (f1 / f0) ^ rnd()
      local p = "/lib/" .. (tag or "x") .. i .. ".wav"
      samples[#samples + 1] = { path = p, name = p, folder = "/lib", duration = d, effective_duration = d,
        channels = 2, brightness = f, dominant_freq = f, sub_weight = rnd(), rms_energy = 0.2,
        tags = tag and { tag } or {} }
    end
  end
  add("kick", 400, 0.2, 0.6, 50, 150)
  add("hat", 300, 0.05, 0.2, 6000, 14000)
  add("pad", 200, 4.0, 12.0, 400, 1500)
  add(nil, 100, 0.05, 12.0, 50, 14000)
  state.samples = samples
  state.map_seed = 1
  layout_samples()
  rebuild_tag_index()
  rebuild_samples_path_index()
  state.active_tags = {}
end

function build_atlas()
  rebuild_map_filtered_cache()
  map_atlas.ready, map_atlas.job, map_atlas.key = false, nil, nil
  for _ = 1, 200 do
    map_atlas_update()
    if map_atlas.ready and not map_atlas.job then break end
  end
  return map_atlas.res
end
'''


def _rt():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO, g.RES, g.FRAMES = REPO, tempfile.mkdtemp(), 1
    L.execute(STUB + HARNESS)
    L.execute("make_lib()")
    return L


def test_axis_bounds_match_dot_positions():
    L = _rt()
    worst = L.execute(r'''
      local b = map_axis_bounds()
      local worst = 0
      for _, s in ipairs(state.samples) do
        local nx = map_x_for_len_score(b, math.log(math.max(sample_map_duration(s), 0.01), 10))
        local ny = map_y_for_score(b, math.log(s.brightness, 10))
        worst = math.max(worst, math.abs(nx - s.x), math.abs(ny - s.y))
      end
      return worst''')
    # layout_samples adds +-0.02 jitter; nothing else may differ.
    assert worst <= 0.0201


def test_log_ticks_add_detail_as_decades_widen():
    L = _rt()
    count = L.eval("function(ppd) local n = 0 for _, t in ipairs(map_log_ticks(1, 4, ppd)) do if t[3] > 0 then n = n + 1 end end return n end")
    narrow, mid, wide = count(60), count(400), count(4000)
    assert narrow == 4          # 10, 100, 1k, 10k
    assert narrow < mid < wide
    labels = [L.eval("map_tick_hz_text")(v) for v in (40, 100, 1500, 2000, 20000)]
    assert labels == ["40", "100", "1.5k", "2k", "20k"]
    secs = [L.eval("map_tick_seconds_text")(v) for v in (0.05, 0.5, 1.5, 20)]
    assert secs == ["50ms", "500ms", "1.5s", "20s"]


def test_regions_and_labels_follow_tags():
    L = _rt()
    L.execute("res = build_atlas()")
    order = list(L.eval("res.tag_order").values())
    assert order == ["kick", "hat", "pad"]
    assert L.eval("res.total_count") == 1000
    # Kick region sits low and left of the hat region (y grows downwards).
    kx, ky = L.eval("res.tags.kick.peak_x"), L.eval("res.tags.kick.peak_y")
    hx, hy = L.eval("res.tags.hat.peak_x"), L.eval("res.tags.hat.peak_y")
    assert ky > 0.6 and hy < 0.4 and hx < kx
    # Closed outline: every segment end is shared by another segment.
    open_ends = L.execute(r'''
      local segs = res.tags.kick.segs
      local seen = {}
      local function key(x, y) return string.format("%.5f,%.5f", x, y) end
      for i = 1, #segs, 4 do
        for _, k in ipairs({ key(segs[i], segs[i + 1]), key(segs[i + 2], segs[i + 3]) }) do
          seen[k] = (seen[k] or 0) + 1
        end
      end
      local odd = 0
      for _, n in pairs(seen) do if n % 2 == 1 then odd = odd + 1 end end
      return odd''')
    assert L.eval("#res.tags.kick.segs") > 0
    assert open_ends == 0


def test_counts_in_view_and_off_screen():
    L = _rt()
    L.execute("res = build_atlas()")
    whole = L.eval("map_atlas_count_in(res.total_sat, 0, 0, 1, 1)")
    assert abs(whole - 1000) < 1e-6
    left = L.eval("map_atlas_count_in(res.total_sat, 0, 0, 0.5, 1)")
    right = L.eval("map_atlas_count_in(res.total_sat, 0.5, 0, 1, 1)")
    assert abs(left + right - 1000) < 1e-6
    exact = L.execute(r'''
      local n = 0
      for _, s in ipairs(state.samples) do if s.x < 0.5 then n = n + 1 end end
      return n''')
    # Interpolated inside one column of cells, so close but not exact.
    assert abs(left - exact) <= 0.04 * 1000
    kicks = L.eval("map_atlas_count_in(res.tags.kick.sat, 0, 0, 1, 1)")
    assert abs(kicks - 400) < 1e-6


def test_filter_change_rebuilds_and_hides_stale_regions():
    L = _rt()
    L.execute("res = build_atlas()")
    assert L.eval("map_atlas_current() ~= nil")
    L.execute("state.active_tags = { kick = true }; rebuild_map_filtered_cache(); map_atlas_update()")
    # Building again for the new filter: old regions are not shown meanwhile.
    assert L.eval("map_atlas_current() == nil")
    L.execute("for _ = 1, 200 do map_atlas_update() if not map_atlas.job then break end end")
    order = list(L.eval("map_atlas.res.tag_order").values())
    assert order == ["kick"]


def test_hot_label_dims_other_tags():
    L = _rt()
    out = L.execute(r'''
      local kick = get_sample_dot_color({ tags = { "kick" }, channels = 2 })
      local hat = get_sample_dot_color({ tags = { "hat" }, channels = 2 })
      local cache = { entries_gen = 1, draw_col = { kick, hat } }
      state.map_atlas_hot_tag = "kick"
      local cols = map_atlas_hot_colors(cache, 2)
      state.map_atlas_hot_tag = nil
      return cols[1] == kick, cols[2] & 0xFF''')
    assert out[0] is True
    assert out[1] < 0x40


def test_overview_click_centres_view():
    L = _rt()
    L.execute("state.zoom = 4; state.pan_x, state.pan_y = 0, 0; map_center_view_on(0.25, 0.75, 1070, 600)")
    pw, ph = 1070 - L.eval("MAP_GUTTER_LEFT"), 600 - L.eval("MAP_GUTTER_TOP")
    assert math.isclose(L.eval("state.pan_x"), 0.25 * pw * 4)
    assert math.isclose(L.eval("state.pan_y"), -0.25 * ph * 4)

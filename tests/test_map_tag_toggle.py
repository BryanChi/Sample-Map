"""Turning map tag filters on and off (browser/10_map_index.lua): the filtered
set, spatial index and duration range match a plain scan, and going back to
a filter seen recently reuses its result, its view and its atlas."""
import os
import re
import tempfile

from lupa import lua54

here = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(here, ".."))
src = open(os.path.join(here, "load_browser.py"), encoding="utf-8").read()
STUB = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)
atlas_src = open(os.path.join(here, "test_map_atlas.py"), encoding="utf-8").read()
HARNESS = re.search(r"HARNESS = r'''(.*?)'''", atlas_src, re.S).group(1)

CHECK = r'''
-- Plain scan of the library with sample_passes_filters, as reference.
function check_filter()
  rebuild_map_filtered_cache()
  local needle = (state.filter ~= "" and string.lower(state.filter)) or ""
  local want, n = {}, 0
  local dmin, dmax
  for _, s in ipairs(state.samples) do
    if s.x and sample_passes_filters(s, needle, false) then
      want[s] = true
      n = n + 1
      local d = sample_map_duration(s)
      if d > 0 then
        dmin = dmin and math.min(dmin, d) or d
        dmax = dmax and math.max(dmax, d) or d
      end
    end
  end
  local got = map_cache.filtered
  if #got ~= n or map_cache.filtered_count ~= n then return "count " .. #got .. " vs " .. n end
  local seen = {}
  for _, s in ipairs(got) do
    if not want[s] then return "extra " .. s.path end
    if seen[s] then return "twice " .. s.path end
    seen[s] = true
  end
  if map_cache.duration_min ~= dmin or map_cache.duration_max ~= dmax then return "durations" end
  local res, in_index = MAP_GRID_RES, 0
  for key, bucket in pairs(map_cache.spatial) do
    for _, s in ipairs(bucket) do
      local cx = math.max(0, math.min(res - 1, math.floor((s.x or 0.5) * res)))
      local cy = math.max(0, math.min(res - 1, math.floor((s.y or 0.5) * res)))
      if key ~= cy * res + cx or not seen[s] then return "cell " .. s.path end
      in_index = in_index + 1
    end
  end
  if in_index ~= n then return "index " .. in_index end
  return "ok"
end
'''


def _rt():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO, g.RES, g.FRAMES = REPO, tempfile.mkdtemp(), 1
    L.execute(STUB + HARNESS + CHECK)
    L.execute("make_lib()")
    return L


def test_tag_filters_match_a_plain_scan():
    L = _rt()
    for tags in ("{}", "{ kick = true }", "{ kick = true, hat = true }",
                 "{ kick = true, hat = true, pad = true }", "{ hat = true }", "{ nope = true }"):
        for text in ("", "1", "kick1"):
            L.execute(f'state.active_tags = {tags}; state.filter = "{text}"')
            assert L.eval("check_filter()") == "ok", (tags, text)
    # Same filter twice in a row (union stamps from the last call left behind).
    L.execute('state.active_tags = { kick = true, pad = true }; state.filter = ""')
    assert L.eval("check_filter()") == "ok"
    L.execute('map_filter_memo_clear()')
    assert L.eval("check_filter()") == "ok"


def test_turning_a_tag_off_again_reuses_the_earlier_result():
    L = _rt()
    view = "100, 100, 600, 400, 400, 300, 10"
    L.execute(f'''
      state.filter = ""
      state.active_tags = {{}}
      ensure_map_render_cache({view})
      BASE_LIST, BASE_DRAW = map_cache.filtered, map_cache.draw_list
      state.active_tags = {{ kick = true }}
      ensure_map_render_cache({view})
      KICK_LIST, KICK_DRAW = map_cache.filtered, map_cache.draw_list
      state.active_tags = {{}}
      ensure_map_render_cache({view})
    ''')
    assert L.eval("map_cache.filtered == BASE_LIST and map_cache.draw_list == BASE_DRAW")
    assert L.eval("#map_cache.draw_entries == #BASE_DRAW and map_cache.draw_entries[1].s == BASE_DRAW[1]")
    L.execute(f'state.active_tags = {{ kick = true }}; ensure_map_render_cache({view})')
    assert L.eval("map_cache.filtered == KICK_LIST and map_cache.draw_list == KICK_DRAW")
    assert L.eval("map_cache.draw_index_by_path[KICK_DRAW[1].path] == 1")
    # Moving the map builds a new view for the same filter.
    L.execute(f'state.pan_x = (state.pan_x or 0) + 0.1; ensure_map_render_cache({view})')
    assert L.eval("map_cache.filtered == KICK_LIST and map_cache.draw_list ~= KICK_DRAW")
    L.execute("state.pan_x = state.pan_x - 0.1")
    # Library changes give new keys, so nothing stale comes back.
    L.execute('state.tag_index_epoch = state.tag_index_epoch + 1; '
              f'state.active_tags = {{}}; ensure_map_render_cache({view})')
    assert L.eval("map_cache.filtered ~= BASE_LIST")


def test_memo_keeps_only_recent_filters():
    L = _rt()
    L.execute('''
      state.filter = ""
      for i = 1, MAP_FILTER_MEMO_SIZE + 3 do
        state.filter = tostring(i)
        rebuild_map_filtered_cache()
      end
    ''')
    assert L.eval("#map_filter_memo") == L.eval("MAP_FILTER_MEMO_SIZE")
    assert L.eval("map_filter_memo[1].key == map_cache.filter_key")


def test_atlas_comes_back_without_a_rebuild():
    L = _rt()
    L.execute('''
      state.active_tags = {}
      A = build_atlas()
      state.active_tags = { kick = true }
      rebuild_map_filtered_cache()
      for _ = 1, 200 do map_atlas_update(); if map_atlas.ready and not map_atlas.job then break end end
      K = map_atlas.res
      state.active_tags = {}
      rebuild_map_filtered_cache()
      map_atlas_update()
    ''')
    assert L.eval("K ~= A and map_atlas.res == A and map_atlas.job == nil and map_atlas_current() == A")

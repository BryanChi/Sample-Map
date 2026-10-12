"""The per-frame caches and fast paths added for performance must give the same
answers as the code they replace. Each test compares a cached/fast result with
a direct computation on randomized inputs. Loads the whole browser with the
stub REAPER API from load_browser.py. Requires `pip install lupa`."""
import os
import re
import tempfile

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def _runtime():
    src = open(os.path.join(HERE, "load_browser.py"), encoding="utf-8").read()
    stub = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    g.FRAMES = 0
    err = L.execute(stub + r'''
      local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
      if not chunk then return err end
      local ok, e = xpcall(chunk, debug.traceback)
      if not ok then return e end
      log = function() end
      save_config = function() end
      return nil
    ''')
    assert err is None, err
    return L


def test_sparkline_points_match_envelope_levels():
    L = _runtime()
    bad = L.execute(r'''
      math.randomseed(3)
      local out = {}
      for trial = 1, 200 do
        local pts = {}
        local n = math.random(1, 8)
        local t = math.random() * 0.1
        for i = 1, n do
          pts[i] = { t = t, amp = math.random() * 4, curve = (math.random() * 2 - 1) * (math.random() < 0.5 and 1 or 0) }
          t = t + 0.0001 + math.random() * 0.5
        end
        local env = seq_normalize_track_env({ points = pts })
        local t1 = math.max(0.001, env.points[#env.points].t or 1.0)
        local max_y = 1.0
        for i = 1, #env.points do max_y = math.max(max_y, env.points[i].amp) end
        local steps = math.random(12, 300)
        seq_env_sparkline_geom = {}
        local xs, ys = seq_env_sparkline_points(env, 10, 20, 2 * steps, 30, t1, max_y, steps)
        for i = 0, steps do
          local amp = seq_env_levels_at_norm(env, (i / steps) * t1)
          local want = 20 + 30 - 2 - (amp / max_y) * (30 - 4)
          if ys[i + 1] ~= want then
            out[#out + 1] = ("trial %d step %d: %s ~= %s"):format(trial, i, ys[i + 1], want)
            break
          end
        end
        -- Second call must hit the cache and return the same arrays.
        local xs2, ys2 = seq_env_sparkline_points(env, 10, 20, 2 * steps, 30, t1, max_y, steps)
        if xs2 ~= xs or ys2 ~= ys then out[#out + 1] = "cache miss on trial " .. trial end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_normalized_envelope_check_agrees_with_normalize():
    L = _runtime()
    bad = L.execute(r'''
      math.randomseed(5)
      local function same(a, b)
        if #a.points ~= #b.points then return false end
        for i = 1, #a.points do
          local p, q = a.points[i], b.points[i]
          if p.t ~= q.t or p.amp ~= q.amp or p.curve ~= q.curve then return false end
        end
        return true
      end
      local out = {}
      for trial = 1, 300 do
        local pts = {}
        for i = 1, math.random(0, 10) do
          pts[i] = { t = math.random() * 2 - 0.2, amp = math.random() * 5 - 0.5, curve = math.random() * 3 - 1.5 }
        end
        local raw = { points = pts }
        if math.random() < 0.2 then raw.atk = 0.01 end
        local norm = seq_normalize_track_env(raw)
        if not seq_env_is_normalized(norm) then
          out[#out + 1] = "normalized env rejected on trial " .. trial
        end
        if not same(seq_normalize_track_env(norm), norm) then
          out[#out + 1] = "normalize not idempotent on trial " .. trial
        end
        if seq_env_is_normalized(raw) and not same(seq_normalize_track_env(raw), raw) then
          out[#out + 1] = "accepted an env normalize would change, trial " .. trial
        end
      end
      if seq_env_is_normalized({ points = { { t = 0, amp = 1, curve = 0, extra = 1 } } }) then
        out[#out + 1] = "accepted a point with extra keys"
      end
      if seq_env_is_normalized({ points = { { t = 0, amp = 1, curve = 0 }, { t = 0.00001, amp = 1, curve = 0 } } }) then
        out[#out + 1] = "accepted points closer than the merge gap"
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_next_trigger_memo_matches_scan():
    L = _runtime()
    bad = L.execute(r'''
      math.randomseed(11)
      local grooves = { "off", "swing16_58", "swing8_56", "human_tight", nil, "bogus" }
      local out = {}
      for trial = 1, 100 do
        local notes = {}
        for i = 1, math.random(1, 24) do
          local step = math.random(0, 31)
          notes[tostring(step)] = { enabled = math.random() < 0.9, offset_qn = (math.random() < 0.3) and (math.random() * 0.2 - 0.1) or nil,
            qn_offset = (math.random() < 0.2) and math.random() * 8 or nil }
        end
        local pattern = { notes = { ["1"] = notes } }
        local region = { id = trial, start_qn = math.random(0, 16), length_bars = 2, groove = grooves[math.random(1, #grooves)] }
        local grid = ({ 0.25, 0.125, 0.5 })[math.random(1, 3)]
        seq_trigger_memo = nil
        local want = {}
        for key, note in pairs(notes) do
          want[key] = seq_next_note_trigger_qn(region, pattern, 1, key, grid, note)
        end
        seq_trigger_memo = {}
        for key, note in pairs(notes) do
          local got = seq_next_note_trigger_qn(region, pattern, 1, key, grid, note)
          if got ~= want[key] then
            out[#out + 1] = ("trial %d key %s: %s ~= %s"):format(trial, key, tostring(got), tostring(want[key]))
          end
        end
        seq_trigger_memo = nil
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_hover_grid_matches_linear_scan():
    L = _runtime()
    bad = L.execute(r'''
      math.randomseed(13)
      local out = {}
      for trial = 1, 60 do
        local entries = {}
        for i = 1, math.random(0, 600) do
          -- Coarse coordinates make exact distance ties common.
          entries[i] = { s = { path = "p" .. i }, px = math.random(-50, 850), py = math.random(-50, 650),
            color = 0xFFFFFFFF, unavailable = math.random() < 0.1 }
        end
        local snap = ({ 96, 40, 150 })[math.random(1, 3)]
        local cache = { entries_gen = trial }
        for k = 1, 40 do
          local mx, my = math.random(-60, 860), math.random(-60, 660)
          local best_i, best_d
          for i = 1, #entries do
            local e = entries[i]
            if not e.unavailable then
              local d = (mx - e.px) ^ 2 + (my - e.py) ^ 2
              if d <= snap * snap and (not best_d or d < best_d) then best_i, best_d = i, d end
            end
          end
          -- First call scans, second call builds the grid, later calls use it.
          for rep = 1, 3 do
            cache.hover_memo = nil
            local got = map_find_hover_entry(cache, entries, mx, my, snap)
            local want = best_i and entries[best_i].s or nil
            if (got and got.sample) ~= want then
              out[#out + 1] = ("trial %d probe %d rep %d mismatch"):format(trial, k, rep)
            end
          end
        end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_case_insensitive_sort_matches_lower_sort():
    L = _runtime()
    bad = L.execute(r'''
      math.randomseed(17)
      local letters = { "a", "B", "c", "D", "e", "_", "1", "Z" }
      for trial = 1, 100 do
        local list = {}
        for i = 1, math.random(0, 50) do
          local s = ""
          for j = 1, math.random(1, 4) do s = s .. letters[math.random(1, #letters)] end
          list[i] = s
        end
        local a, b = {}, {}
        for i, s in ipairs(list) do a[i] = s; b[i] = s end
        sm_sort_ci(a)
        table.sort(b, function(x, y) return string.lower(x) < string.lower(y) end)
        for i = 1, #a do
          if string.lower(a[i]) ~= string.lower(b[i]) then return "order differs on trial " .. trial end
        end
      end
      return ""
    ''')
    assert bad == ""


def test_region_length_cache_and_sample_miss_cache():
    L = _runtime()
    bad = L.execute(r'''
      local out = {}
      seq_region_len_cache_reset()
      for bars = 1, 8 do
        for start = 0, 40, 3 do
          local reg = { start_qn = start, length_bars = bars }
          local first = get_seq_region_length_qn(reg)
          local again = get_seq_region_length_qn(reg)
          local direct = seq_region_length_qn_uncached(start, bars)
          if first ~= direct or again ~= direct then out[#out + 1] = ("bars %d start %d"):format(bars, start) end
        end
      end
      -- A miss is remembered, but an added sample is still found.
      state.samples = { { path = "/lib/a.wav", name = "a.wav" } }
      rebuild_samples_path_index()
      if find_sample_by_path("/lib/B.wav") ~= nil then out[#out + 1] = "unexpected hit" end
      if find_sample_by_path("/lib/B.wav") ~= nil then out[#out + 1] = "unexpected cached hit" end
      local b = { path = "/lib/b.wav", name = "b.wav" }
      state.samples[#state.samples + 1] = b
      if find_sample_by_path("/lib/B.wav") ~= b then out[#out + 1] = "added sample not found after a miss" end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


# The encoder json_encode replaced, kept here as the reference.
OLD_JSON_ENCODE = r'''
function old_json_encode(val)
  if type(val) == "table" then
    local parts = {}
    local is_array = true
    local max_idx = 0
    for k, v in pairs(val) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      max_idx = math.max(max_idx, k)
    end
    if is_array then
      for i = 1, max_idx do
        table.insert(parts, old_json_encode(val[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(val) do
        table.insert(parts, json_encode_string(tostring(k)) .. ":" .. old_json_encode(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  elseif type(val) == "string" then
    return json_encode_string(val)
  elseif type(val) == "number" then
    if val ~= val or val == math.huge or val == -math.huge then
      return "null"
    end
    return tostring(val)
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  else
    return "null"
  end
end
'''


def test_json_encode_matches_old_encoder():
    L = _runtime()
    bad = L.execute(OLD_JSON_ENCODE + r'''
      math.randomseed(23)
      local chars = { "a", "b", "\"", "\\", "\n", "\t", "\1", "z", "é", "/" }
      local function rstr()
        local s = ""
        for i = 1, math.random(0, 6) do s = s .. chars[math.random(1, #chars)] end
        return s
      end
      local function rval(depth)
        local p = math.random()
        if depth > 3 or p < 0.3 then
          local q = math.random(1, 7)
          if q == 1 then return math.random(-1000, 1000) end
          if q == 2 then return (math.random() - 0.5) * 1e6 end
          if q == 3 then return rstr() end
          if q == 4 then return math.random() < 0.5 end
          if q == 5 then return ({ 0.0, -0.0, 1.0, 0.25, 0/0, math.huge, -math.huge })[math.random(1, 7)] end
          if q == 6 then return math.random(0, 3) end
          return 1e-7 * math.random()
        end
        local t = {}
        if math.random() < 0.5 then
          for i = 1, math.random(0, 5) do t[i] = rval(depth + 1) end
          if math.random() < 0.2 then t[math.random(7, 9)] = rval(depth + 1) end
        else
          for i = 1, math.random(0, 5) do
            local k = math.random() < 0.7 and rstr() or math.random(-3, 40)
            t[k] = rval(depth + 1)
          end
        end
        return t
      end
      for trial = 1, 400 do
        local v = rval(0)
        local a, b = json_encode(v), old_json_encode(v)
        -- Key order follows pairs() in both, so the text must match exactly.
        if a ~= b then return ("trial %d:\n%s\n%s"):format(trial, a, b) end
      end
      return ""
    ''')
    assert bad == ""

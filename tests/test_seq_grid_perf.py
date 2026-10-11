"""Sequencer grid drawing (timeline rows) perf work: every cache, fast path and
refactor must give the same answers as the code it replaced. Each test builds
random sequencer projects (regions with gaps, linked patterns, grooves, notes
with offsets / stutter / decay / locks / filters, track settings, region sample
overrides) and compares the new code with the original composition or with the
uncached path. Loads the whole browser with the stub REAPER API from
load_browser.py. Requires `pip install lupa`."""
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


# Random project builder shared by the tests: make_project(rnd) applies a new
# project and returns the grid size it picked. rnd is a private LCG so the app's
# own math.random use cannot shift the data.
GEN = r'''
local function new_rnd(seed)
  local s = seed
  return function(a, b)
    s = (s * 1103515245 + 12345) % 2147483648
    local f = s / 2147483648
    if a == nil then return f end
    if b == nil then a, b = 1, a end
    return a + math.floor(f * (b - a + 1))
  end
end
local function fmt(v)
  if type(v) == "number" then
    if v ~= v then return "nan" end
    return (math.type(v) or "?") .. ":" .. string.format("%.17g", v)
  end
  return tostring(v)
end
local samples = {}
for i = 1, 120 do
  samples[i] = { path = "/lib/s" .. i .. ".wav", name = "s" .. i .. ".wav", x = (i * 37 % 100) / 100,
    y = (i * 53 % 100) / 100, tags = { (i % 3 == 0) and "kick" or "snare" },
    duration = (i % 5 == 0) and 0 or (0.05 + (i % 17) * 0.11) }
end
state.samples = samples
rebuild_samples_path_index()
local words = { "kick", "snare", "zzzz", " hat ", "" }
local function make_project(rnd)
  local grooves = { "off", "swing16_58", "mpc_60", "linn", "bogus" }
  local cfg = { seq_tracks = {}, seq_regions = {}, seq_patterns = {} }
  local ntr = rnd(1, 4)
  for t = 1, ntr do
    cfg.seq_tracks[t] = { id = t, name = "T" .. t, sample_path = samples[rnd(1, 120)].path,
      sample_tag = (rnd() < 0.3) and "pad" or "kick", overlap = rnd() < 0.3 or nil }
  end
  local nreg = rnd(1, 4)
  local qn = rnd(0, 2) * 0.5
  for r_i = 1, nreg do
    local notes = {}
    for t = 1, ntr do
      local row = {}
      for _ = 1, rnd(0, 14) do
        local st = rnd(0, 40)
        local n = { vel = 100, volume = rnd() * 2 }
        if rnd() < 0.2 then n.offset_qn = (rnd() - 0.5) * 0.3 end
        if rnd() < 0.15 then n.qn_offset = rnd(0, 60) * 0.125 end
        if rnd() < 0.15 then n.stutter = rnd(1, 5) end
        if rnd() < 0.2 then n.length_qn = rnd(0, 8) * 0.25 end
        if rnd() < 0.1 then n.decay_qn = rnd() * 2 end
        if rnd() < 0.05 then n.enabled = false end
        if rnd() < 0.15 then n.locked = true end
        if rnd() < 0.1 then n.step = rnd(0, 30) end
        if rnd() < 0.1 then n.sample_path = samples[rnd(1, 120)].path end
        if rnd() < 0.1 then n.stretch = 0.5 + rnd() * 2; n.start = rnd() * 0.5 end
        if rnd() < 0.08 then n.vary_filter = words[rnd(1, #words)] end
        row[(rnd() < 0.1) and (tostring(st * 48) .. "_1") or tostring(st)] = n
      end
      notes[tostring(t)] = row
    end
    local pat = { notes = notes }
    if rnd() < 0.6 then
      pat.locked_cells = {}
      for t = 1, ntr do
        if rnd() < 0.5 then
          local c, a = {}, rnd(0, 30)
          for k = a, a + rnd(0, 5) do c[tostring(k)] = true end
          pat.locked_cells[tostring(t)] = c
        end
      end
    end
    if rnd() < 0.6 then
      pat.vary_filters = {}
      for t = 1, ntr do
        if rnd() < 0.5 then
          local c, a = {}, rnd(0, 30)
          for k = a, a + rnd(0, 5) do c[tostring(k)] = words[rnd(1, #words)] end
          pat.vary_filters[tostring(t)] = c
        end
      end
    end
    cfg.seq_patterns[tostring(r_i)] = pat
    local pid = (rnd() < 0.2 and r_i > 1) and (r_i - 1) or r_i
    cfg.seq_regions[r_i] = { id = r_i, name = "R" .. r_i, start_qn = qn, length_bars = rnd(1, 3),
      pool_id = pid, pattern_id = pid, groove = grooves[rnd(1, #grooves)] }
    if rnd() < 0.3 then
      cfg.seq_regions[r_i].track_samples = { [tostring(rnd(1, ntr))] = { path = samples[rnd(1, 120)].path, name = "ov" } }
    end
    qn = qn + cfg.seq_regions[r_i].length_bars * 4 + ((rnd() < 0.4) and rnd(1, 6) * 0.5 or 0)
  end
  cfg.seq_pattern_next_id = nreg + 1; cfg.seq_pool_next_id = nreg + 1
  apply_seq_project_state(cfg)
  seq_region_len_cache_reset()
  state.seq_force_item_crop = rnd() < 0.2 or nil
  local grid = ({ 0.25, 0.125, 0.5, 1 / 3 })[rnd(1, 4)]
  state.seq_grid_qn = grid
  return grid
end
local function each_note(fn)
  for _, reg in ipairs(state.seq_regions) do
    local pattern = get_seq_pattern(reg.pattern_id, false)
    for _, slot in ipairs(state.seq_tracks) do
      local tn = get_track_note_table(pattern, slot.id, false)
      local keys = {}
      for k in pairs(tn or {}) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do fn(reg, pattern, slot, k, tn[k]) end
    end
  end
end
'''


def _check(lua_body):
    L = _runtime()
    out = L.execute(GEN + lua_body)
    assert out == "", out


def test_note_trigger_matches_original_composition():
    _check(r'''
      local function ref(region, step_idx, note, grid_qn)
        local cell_start_qn = seq_note_abs_qn(region, note, step_idx, grid_qn)
        local offset_qn = (note and note.offset_qn) or 0.0
        local groove_qn = seq_groove_offset_qn(cell_start_qn, get_seq_region_groove(region))
        local qn = cell_start_qn + groove_qn + offset_qn
        if qn < 0.0 then qn = 0.0 end
        return qn
      end
      local rnd = new_rnd(11)
      local bad = {}
      for it = 1, 120 do
        local grid = make_project(rnd)
        each_note(function(reg, pattern, slot, k, n)
          for _, g in ipairs({ grid, false }) do
            g = g or nil
            for _, args in ipairs({ { reg, k, n }, { reg, nil, n }, { nil, k, n }, { reg, k, nil } }) do
              local a = seq_note_trigger_qn(args[1], args[2], args[3], g)
              local b = ref(args[1], args[2], args[3], g)
              if fmt(a) ~= fmt(b) then bad[#bad + 1] = ("trigger %s: %s vs %s"):format(k, fmt(a), fmt(b)) end
            end
          end
        end)
        if #bad > 0 then break end
      end
      return table.concat(bad, "\n", 1, math.min(#bad, 5))
    ''')


def test_lengths_match_original_composition():
    # Original (pre-refactor) seq_next_note_trigger_qn scan, seq_gap_to_next_hit_qn,
    # seq_effective_note_length_qn and seq_note_draw_length_qn_uncached.
    _check(r'''
      local function ref_next(region, pattern, track_id, step_idx, grid_qn, note)
        if not region then return 0.0 end
        local track_notes = get_track_note_table(pattern, track_id, false)
        if not track_notes then return (region.start_qn or 0.0) + get_seq_region_length_qn(region) end
        local start_qn = seq_note_trigger_qn(region, step_idx, note, grid_qn)
        local next_qn, next_key = nil, nil
        for sk, nnote in pairs(track_notes) do
          if type(nnote) == "table" and nnote.enabled ~= false then
            local qn = seq_note_trigger_qn(region, sk, nnote, grid_qn)
            if qn > start_qn + 1e-9 and (not next_qn or qn < next_qn) then next_qn = qn; next_key = sk end
          end
        end
        if next_key then
          return seq_note_trigger_qn(region, next_key, track_notes[next_key] or track_notes[tostring(next_key)], grid_qn)
        end
        return (region.start_qn or 0.0) + get_seq_region_length_qn(region)
      end
      local function ref_gap(region, pattern, track_id, step_idx, note, grid_qn)
        if not region then return nil end
        local start_qn = seq_note_trigger_qn(region, step_idx, note, grid_qn)
        local end_qn = ref_next(region, pattern, track_id, step_idx, grid_qn, note)
        local region_end = (region.start_qn or 0.0) + get_seq_region_length_qn(region)
        if math.abs(end_qn - region_end) <= 1e-9 then return nil end
        return math.max((grid_qn or 0.25) * 0.05, end_qn - start_qn)
      end
      local function ref_eff(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn, hit_idx)
        grid_qn = grid_qn or state.seq_grid_qn or 0.25
        local resolved_path = (resolved_sample and resolved_sample.path) or (note and note.frozen_sample_path)
          or (note and note.sample_path) or (slot and slot.sample_path)
        local stutter_count = seq_stutter_count(note)
        if stutter_count > 1 then
          local _, _, slice_qn = seq_stutter_hit_span(note, hit_idx or 1, grid_qn)
          if not slice_qn or slice_qn <= 1e-9 then
            slice_qn = (seq_stutter_span_qn(note, grid_qn) or grid_qn) / stutter_count
          end
          return seq_cap_length_to_sample_qn(slice_qn * 0.98, resolved_path, resolved_sample, note)
        end
        local at_qn = region and step_idx ~= nil and seq_note_trigger_qn(region, step_idx, note, grid_qn) or nil
        local sample_qn = seq_sample_length_qn(resolved_path, resolved_sample, at_qn)
        if not sample_qn or sample_qn <= 0 then sample_qn = grid_qn end
        local decay_qn = tonumber(note and note.decay_qn)
        if type(decay_qn) == "number" and decay_qn > 1e-9 then
          return seq_cap_length_to_sample_qn(math.max(grid_qn * 0.05, decay_qn), resolved_path, resolved_sample, note, nil, at_qn)
        end
        if state.seq_force_item_crop or not (slot and slot.overlap) then
          local gap_qn = ref_gap(region, pattern, track_id, step_idx, note, grid_qn)
          if gap_qn then sample_qn = math.min(sample_qn, gap_qn) end
        end
        sample_qn = seq_cap_length_to_region_end_qn(sample_qn, region, step_idx, note, grid_qn)
        return seq_cap_length_to_sample_qn(sample_qn, resolved_path, resolved_sample, note, nil, at_qn)
      end
      local function ref_draw(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
        local len = ref_eff(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
        local decay_qn = tonumber(note and note.decay_qn)
        if type(decay_qn) == "number" and decay_qn > 1e-9 then return len end
        local resolved_path = (resolved_sample and resolved_sample.path) or (note and note.frozen_sample_path)
          or (note and note.sample_path) or (slot and slot.sample_path)
        local sample_qn = seq_sample_length_qn(resolved_path, resolved_sample)
        if sample_qn and sample_qn > grid_qn + 1e-9 then len = math.max(len or 0, grid_qn) end
        return seq_cap_length_to_region_end_qn(len, region, step_idx, note, grid_qn)
      end
      -- seq_note_draw_length_qn: a stutter span wins, else the (memoized) draw length.
      local function ref_draw_full(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
        grid_qn = grid_qn or state.seq_grid_qn or 0.25
        local span = seq_stutter_span_qn(note, grid_qn)
        if span then return span end
        return ref_draw(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
      end
      local rnd = new_rnd(23)
      local bad = {}
      local function cmp(what, k, a, b)
        if fmt(a) ~= fmt(b) then bad[#bad + 1] = ("%s %s: %s vs %s"):format(what, k, fmt(a), fmt(b)) end
      end
      for it = 1, 120 do
        local grid = make_project(rnd)
        for pass = 1, 2 do
          -- pass 2 with the row memo set, as while the sequencer rows draw
          seq_trigger_memo = (pass == 2) and {} or nil
          each_note(function(reg, pattern, slot, k, n)
            local _, rs = seq_resolve_note_sample(n, slot, nil, reg, slot.id, k)
            local saved = seq_trigger_memo
            seq_trigger_memo = nil
            local want_next = ref_next(reg, pattern, slot.id, k, grid, n)
            local want_gap = ref_gap(reg, pattern, slot.id, k, n, grid)
            local want_eff = ref_eff(reg, pattern, slot, slot.id, k, n, rs, grid)
            local want_eff2 = ref_eff(reg, pattern, slot, slot.id, nil, n, rs, grid, 2)
            local want_eff3 = ref_eff(nil, pattern, slot, slot.id, k, n, rs, grid)
            local want_draw = ref_draw(reg, pattern, slot, slot.id, k, n, rs, grid)
            local want_draw_full = ref_draw_full(reg, pattern, slot, slot.id, k, n, rs, grid)
            seq_trigger_memo = saved
            cmp("next", k, seq_next_note_trigger_qn(reg, pattern, slot.id, k, grid, n), want_next)
            cmp("gap", k, seq_gap_to_next_hit_qn(reg, pattern, slot.id, k, n, grid), want_gap)
            cmp("eff", k, seq_effective_note_length_qn(reg, pattern, slot, slot.id, k, n, rs, grid), want_eff)
            cmp("eff hit", k, seq_effective_note_length_qn(reg, pattern, slot, slot.id, nil, n, rs, grid, 2), want_eff2)
            cmp("eff noreg", k, seq_effective_note_length_qn(nil, pattern, slot, slot.id, k, n, rs, grid), want_eff3)
            cmp("draw", k, seq_note_draw_length_qn(reg, pattern, slot, slot.id, k, n, rs, grid), want_draw_full)
            cmp("draw again", k, seq_note_draw_length_qn(reg, pattern, slot, slot.id, k, n, rs, grid), want_draw_full)
            cmp("draw uncached", k, seq_note_draw_length_qn_uncached(reg, pattern, slot, slot.id, k, n, rs, grid), want_draw)
          end)
          seq_trigger_memo = nil
        end
        if #bad > 0 then break end
      end
      return table.concat(bad, "\n", 1, math.min(#bad, 5))
    ''')


def test_row_memos_match_uncached_path():
    # seq_note_item_x_range and seq_effective_slot_sample_path memoize in
    # seq_trigger_memo while rows draw; answers must equal the uncached path.
    _check(r'''
      local rnd = new_rnd(37)
      local bad = {}
      local qx = function(q) return 100 + q * 13.7 end
      local qx2 = function(q) return 3 + q * 40.25 end
      for it = 1, 120 do
        local grid = make_project(rnd)
        local want = {}
        seq_trigger_memo = nil
        each_note(function(reg, pattern, slot, k, n)
          local a0, a1 = seq_note_item_x_range(n, slot, reg, pattern, k, 3.0, grid, qx, 0)
          local b0, b1 = seq_note_item_x_range(n, slot, nil, pattern, k, 3.0, grid, qx2, 0)
          local d0, d1 = seq_note_item_x_range(n, slot, nil, pattern, k, 3.0, grid, qx, 0)
          want[#want + 1] = fmt(a0) .. " " .. fmt(a1) .. " " .. fmt(b0) .. " " .. fmt(b1) .. " " .. fmt(d0) .. " " .. fmt(d1)
          local p, nm = seq_effective_slot_sample_path(slot, reg)
          want[#want + 1] = tostring(p) .. " " .. tostring(nm)
        end)
        for pass = 1, 2 do
          seq_trigger_memo = {}
          local i = 0
          each_note(function(reg, pattern, slot, k, n)
            local a0, a1 = seq_note_item_x_range(n, slot, reg, pattern, k, 3.0, grid, qx, 0)
            local b0, b1 = seq_note_item_x_range(n, slot, nil, pattern, k, 3.0, grid, qx2, 0)
            local d0, d1 = seq_note_item_x_range(n, slot, nil, pattern, k, 3.0, grid, qx, 0)
            -- Asked again with the same arguments: must hit and still agree.
            local c0, c1 = seq_note_item_x_range(n, slot, reg, pattern, k, 3.0, grid, qx, 99)
            i = i + 1
            local got = fmt(a0) .. " " .. fmt(a1) .. " " .. fmt(b0) .. " " .. fmt(b1) .. " " .. fmt(d0) .. " " .. fmt(d1)
            if got ~= want[i] or fmt(c0) ~= fmt(a0) or fmt(c1) ~= fmt(a1) then
              bad[#bad + 1] = ("item_x %s: %s vs %s"):format(k, got, want[i])
            end
            local other = state.seq_tracks[1]
            local p0 = seq_effective_slot_sample_path(other, nil)
            local p, nm = seq_effective_slot_sample_path(slot, reg)
            i = i + 1
            if tostring(p) .. " " .. tostring(nm) ~= want[i] then
              bad[#bad + 1] = ("eff path %s: %s %s vs %s"):format(k, tostring(p), tostring(nm), want[i])
            end
            if p0 ~= seq_effective_slot_sample_path_uncached(other, nil) then
              bad[#bad + 1] = "eff path (no region) differs"
            end
          end)
          seq_trigger_memo = nil
        end
        if #bad > 0 then break end
      end
      return table.concat(bad, "\n", 1, math.min(#bad, 5))
    ''')


def test_visible_active_cells_match_original_builder():
    _check(r'''
      -- The builder as it was: one cell table per occupied column with a pack,
      -- filled by seq_active_cells_put and finished by seq_finish_active_cells.
      local function ref_build(start_qn, end_qn, step_qn, step_count)
        local active_cells = {}
        for _, slot in ipairs(state.seq_tracks) do active_cells[slot.id] = {} end
        for _, reg in ipairs(state.seq_regions) do
          local reg_start = reg.start_qn or 0.0
          local reg_len = get_seq_region_length_qn(reg)
          local reg_end = reg_start + reg_len
          if reg_end >= start_qn and reg_start <= end_qn then
            local pattern = get_seq_pattern(reg.pattern_id, false)
            if pattern then
              local in_lo = reg_start - 1e-9
              local in_hi = reg_start + reg_len - 1e-9
              for _, slot in ipairs(state.seq_tracks) do
                local notes = get_track_note_table(pattern, slot.id, false)
                if notes then
                  for step_key, note in pairs(notes) do
                    local abs_qn = (type(note) == "table" and note.enabled ~= false)
                      and seq_note_abs_qn(reg, note, step_key, step_qn) or nil
                    if abs_qn and abs_qn >= in_lo and abs_qn < in_hi then
                      local vis_qn = abs_qn + (note.offset_qn or 0.0)
                      local span = seq_stutter_span_qn(note, step_qn) or 0.0
                      local occupy_end = vis_qn + math.max(span, 1e-9)
                      if occupy_end > start_qn - step_qn and vis_qn < end_qn + step_qn then
                        local entry = { key = step_key, note = note, region_id = reg.id, abs_qn = abs_qn }
                        local col0 = math.floor(((vis_qn - start_qn) / step_qn) + 1e-9)
                        local col1 = math.floor(((occupy_end - 1e-9 - start_qn) / step_qn) + 1e-9)
                        for col = math.max(0, col0), math.min(step_count - 1, col1) do
                          seq_active_cells_put(active_cells, slot.id, col, entry, start_qn, step_qn, step_count)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        seq_finish_active_cells(active_cells)
        return active_cells
      end
      local function describe(c, s0, col, stq)
        if not c then return "-" end
        local parts = { tostring(c.key), fmt(c.abs_qn), tostring(c.region_id), tostring(c.note) }
        local pack = seq_active_cell_notes(c)
        parts[#parts + 1] = "#" .. #pack
        for i = 1, #pack do
          parts[#parts + 1] = tostring(pack[i].key) .. "@" .. tostring(pack[i].region_id) .. "@"
            .. fmt(pack[i].abs_qn) .. "@" .. tostring(pack[i].note)
        end
        parts[#parts + 1] = tostring(seq_active_cell_has_visual_start(c, s0, col, stq))
        local hv = seq_resolve_hover_note(c, s0 + col * stq + stq * 0.3, s0, col, stq)
        parts[#parts + 1] = hv and (tostring(hv.key) .. "#" .. tostring(hv.region_id)) or "none"
        return table.concat(parts, " ")
      end
      local rnd = new_rnd(41)
      local bad = {}
      for it = 1, 200 do
        make_project(rnd)
        local view0 = rnd(-4, 40) * 0.5
        local s0, e0, stq, sc = get_visible_qn_grid_range(view0, view0 + rnd(1, 40))
        local want = ref_build(s0, e0, stq, sc)
        local got = seq_build_visible_active_cells(s0, e0, stq, sc)
        for _, slot in ipairs(state.seq_tracks) do
          for col = -2, sc + 1 do
            local a = describe(got[slot.id][col], s0, col, stq)
            local b = describe(want[slot.id][col], s0, col, stq)
            if a ~= b then bad[#bad + 1] = ("cell %s/%d: %s vs %s"):format(slot.id, col, a, b) end
          end
          for col in pairs(got[slot.id]) do
            if want[slot.id][col] == nil then bad[#bad + 1] = ("extra cell %s/%s"):format(slot.id, tostring(col)) end
          end
        end
        if #bad > 0 then break end
      end
      return table.concat(bad, "\n", 1, math.min(#bad, 5))
    ''')


def test_lane_fill_colors_and_styles_match_direct():
    _check(r'''
      local bad = {}
      local function direct(accent, bipolar, value)
        local ar, ag, ab = extract_rgb_rrgbbaa(accent or 0xFFD166FF)
        local fill = build_color_rrgbbaa(ar, ag, ab, 205)
        local cap = build_color_rrgbbaa(math.min(255, ar + 45), math.min(255, ag + 45), math.min(255, ab + 45), 255)
        local fill_neg = build_color_rrgbbaa(math.max(0, ar - 70), math.max(0, ag - 35), math.min(255, ab + 40), 205)
        if bipolar and value ~= nil and value < 0 then return fill_neg, cap end
        return fill, cap
      end
      local accents = { 0xFFD166FF, 0x6EC8FFFF, 0, 0xFFFFFFFF, 4291913471.0, 4291913471, 123.5, -1, -1.0, 0 / 0 }
      local rnd = new_rnd(5)
      for i = 1, 600 do accents[#accents + 1] = rnd(0, 4294967295) end
      for round = 1, 2 do
        for _, acc in ipairs(accents) do
          for _, bv in ipairs({ { true, -1 }, { true, 1 }, { false, -1 }, { true, nil }, { nil, -0.5 }, { true, 0 } }) do
            local a1, a2 = seq_lane_param_fill_colors(acc, bv[1], bv[2])
            local b1, b2 = direct(acc, bv[1], bv[2])
            if fmt(a1) ~= fmt(b1) or fmt(a2) ~= fmt(b2) then
              bad[#bad + 1] = ("fill %s: %s %s vs %s %s"):format(fmt(acc), fmt(a1), fmt(a2), fmt(b1), fmt(b2))
            end
          end
        end
        local a1, a2 = seq_lane_param_fill_colors(nil, true, -1)
        local b1, b2 = direct(nil, true, -1)
        if a1 ~= b1 or a2 ~= b2 then bad[#bad + 1] = "fill nil accent" end
      end
      local accent_of = { volume = 0xFFD166FF, sample_vary = 0x8FD98FFF, vary_filter = 0x7ECFA6FF,
        stutter = 0xC9A8FFFF, pan = 0x6EC8FFFF, pitch = 0xFFB84DFF, length_qn = 0x88DDAAFF,
        decay = 0xFFD166FF, stretch = 0x7ED0C8FF, start = 0xA8E0C0FF, locked = 0xE8C070FF }
      local function same_style(s, accent)
        return s.bg == UI_THEME.bg_panel and s.label_bg == UI_THEME.bg and s.timeline_bg == UI_THEME.surface
          and s.edge == UI_THEME.border and s.accent == accent
      end
      for _, key in ipairs({ "volume", "sample_vary", "vary_filter", "stutter", "pan", "pitch", "length_qn",
          "decay", "stretch", "start", "locked", "zzz" }) do
        local s1 = get_seq_row_lane_style({ type = "param", param = { key = key } })
        local s2 = get_seq_row_lane_style({ type = "param", param = { key = key } })
        if not same_style(s1, accent_of[key] or UI_THEME.text_dim) then bad[#bad + 1] = "style " .. key end
        if s1 == s2 then bad[#bad + 1] = "style table shared for " .. key end
      end
      if not same_style(get_seq_row_lane_style({ type = "note" }), UI_THEME.accent) then bad[#bad + 1] = "style note" end
      if not same_style(get_seq_row_lane_style({ type = "param" }), UI_THEME.text_mute) then bad[#bad + 1] = "style param0" end
      if not same_style(get_seq_row_lane_style({ type = "empty" }), UI_THEME.text_mute) then bad[#bad + 1] = "style empty" end
      return table.concat(bad, "\n", 1, math.min(#bad, 5))
    ''')


def test_lock_and_filter_spans_match_per_cell_loops():
    # draw_seq_lock_spans / draw_seq_vary_filter_spans look each region's lock
    # and filter tables up once per row; the draw calls must equal the original
    # per-column loops over seq_visible_cell_is_locked / seq_vary_filter_cell_key.
    _check(r'''
      local r = reaper
      local function ref_lock(dl, slot, row_y0, row_y1, start_qn, step_qn, step_count, col_x0, col_x1, timeline_x0, timeline_x1, active_cells, edit_mode, hover_col)
        local run_start = nil
        local function flush(run_end)
          if not run_start then return end
          local x0 = math.max(timeline_x0, col_x0(run_start))
          local x1 = math.min(timeline_x1, col_x1(run_end))
          if x1 > x0 + 1.0 then
            local hovered = hover_col ~= nil and hover_col >= run_start and hover_col <= run_end
            draw_seq_lock_span(dl, x0, row_y0, x1, row_y1, edit_mode, hovered)
          end
          run_start = nil
        end
        for col = 0, step_count - 1 do
          if seq_visible_cell_is_locked(slot, col, start_qn, step_qn, active_cells) then
            if not run_start then run_start = col end
          else
            flush(col - 1)
          end
        end
        flush(step_count - 1)
      end
      local function ref_filter(dl, ctx, slot, row_y0, row_y1, start_qn, step_qn, step_count, col_x0, col_x1, timeline_x0, timeline_x1, edit_mode, hover_col)
        local edit = state.seq_vary_filter_edit
        if edit and slot and tostring(edit.track_id) == tostring(slot.id) then
          edit.x0, edit.y0, edit.x1, edit.y1 = nil, nil, nil, nil
        end
        local run_start, run_key, run_text, run_editing = nil, nil, nil, false
        local function flush(run_end)
          if not run_start then return end
          local x0 = math.max(timeline_x0, col_x0(run_start))
          local x1 = math.min(timeline_x1, col_x1(run_end))
          if x1 > x0 + 1.0 then
            local hovered = hover_col ~= nil and hover_col >= run_start and hover_col <= run_end
            local sx0, sy0, sx1, sy1 = draw_seq_vary_filter_span(dl, ctx, x0, row_y0, x1, row_y1, run_text, edit_mode, hovered, run_editing)
            if hovered and not run_editing and seq_vary_filter_has_no_hits(run_text) and r.ImGui_SetTooltip then
              r.ImGui_SetTooltip(ctx, "No samples match this filter")
            end
            local edit = state.seq_vary_filter_edit
            if run_editing and edit and tostring(edit.track_id) == tostring(slot.id) then
              edit.x0, edit.y0, edit.x1, edit.y1 = sx0, sy0, sx1, sy1
            end
          end
          run_start, run_key, run_text, run_editing = nil, nil, nil, false
        end
        for col = 0, step_count - 1 do
          local key, editing, text = seq_vary_filter_cell_key(slot, col, start_qn, step_qn)
          if key then
            if run_start and key ~= run_key then flush(col - 1) end
            if not run_start then run_start = col; run_key = key; run_text = text; run_editing = editing end
          else
            flush(col - 1)
          end
        end
        flush(step_count - 1)
      end
      local log = {}
      local function rec(name)
        return function(...)
          local parts = { name }
          for i = 1, select("#", ...) do parts[#parts + 1] = fmt((select(i, ...))) end
          log[#log + 1] = table.concat(parts, " ")
        end
      end
      for _, name in ipairs({ "ImGui_DrawList_AddRectFilled", "ImGui_DrawList_AddRect", "ImGui_DrawList_AddCircle",
          "ImGui_DrawList_AddText", "ImGui_DrawList_AddLine", "ImGui_SetTooltip" }) do
        rawset(reaper, name, rec(name))
      end
      rawset(reaper, "ImGui_CalcTextSize", function(_, s) return #tostring(s) * 7.0, 13.0 end)
      local rnd = new_rnd(53)
      local bad = {}
      local function run(fn, ...)
        log = {}
        fn(...)
        local e = state.seq_vary_filter_edit
        if e then log[#log + 1] = "edit " .. fmt(e.x0) .. fmt(e.y0) .. fmt(e.x1) .. fmt(e.y1) end
        return table.concat(log, "\n")
      end
      for it = 1, 150 do
        local grid = make_project(rnd)
        local view0 = rnd(-4, 40) * 0.5
        local s0, e0, stq, sc = get_visible_qn_grid_range(view0, view0 + rnd(1, 24))
        local cells = seq_build_visible_active_cells(s0, e0, stq, sc)
        local tx0, tw, span = 272.0, 528.0, (e0 - s0)
        local function qn_to_x(q) return tx0 + ((q - s0) / span) * tw end
        local function cx0(c) return qn_to_x(s0 + c * stq) end
        local function cx1(c) return qn_to_x(s0 + (c + 1) * stq) end
        state.seq_vary_filter_edit = nil
        if rnd() < 0.3 then
          local c0 = rnd(-1, 10)
          state.seq_vary_filter_edit = { track_id = (rnd() < 0.5) and rnd(1, 3) or tostring(rnd(1, 3)),
            region_id = (rnd() < 0.5) and rnd(1, 3) or nil, col_min = (rnd() < 0.9) and c0 or nil,
            col_max = c0 + rnd(0, 4), text = words[rnd(1, #words)], start_qn = s0, step_qn = stq }
        end
        seq_trigger_memo = (rnd() < 0.5) and {} or nil
        for _, slot in ipairs(state.seq_tracks) do
          local hover = (rnd() < 0.5) and rnd(0, sc) or nil
          local edit_mode = rnd() < 0.5
          local a = run(draw_seq_lock_spans, "DL", slot, 10, 40, s0, stq, sc, cx0, cx1, tx0, tx0 + tw, cells, edit_mode, hover)
          local b = run(ref_lock, "DL", slot, 10, 40, s0, stq, sc, cx0, cx1, tx0, tx0 + tw, cells, edit_mode, hover)
          if a ~= b then bad[#bad + 1] = ("lock spans slot %s it %d:\n%s\nvs\n%s"):format(slot.id, it, a, b) end
          a = run(draw_seq_vary_filter_spans, "DL", "CTX", slot, 10, 40, s0, stq, sc, cx0, cx1, tx0, tx0 + tw, edit_mode, hover)
          b = run(ref_filter, "DL", "CTX", slot, 10, 40, s0, stq, sc, cx0, cx1, tx0, tx0 + tw, edit_mode, hover)
          if a ~= b then bad[#bad + 1] = ("filter spans slot %s it %d:\n%s\nvs\n%s"):format(slot.id, it, a, b) end
        end
        seq_trigger_memo = nil
        if #bad > 0 then break end
      end
      return table.concat(bad, "\n", 1, math.min(#bad, 3))
    ''')

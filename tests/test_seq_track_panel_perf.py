"""Performance rewrites in the sequencer track panel area (track mix column,
per-track normalizers, layering state checks, sample candidates) must have
exactly the effects of the code they replaced. Each test runs the previous
implementation (kept here verbatim as reference Lua, renamed ref_*) and the
current one on randomized, often malformed, inputs and compares return values
and the resulting data bit for bit (number subtypes, NaN, table aliasing).
Loads the whole browser with the stub REAPER API from load_browser.py.
Requires `pip install lupa`."""
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
    L.execute(HELPERS)
    return L


# Deep comparison that also checks number subtypes, NaN and that both values
# share tables in the same pattern; and a deep copy that keeps aliasing.
HELPERS = r'''
function T_deep_copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local c = {}
  seen[v] = c
  for k, x in pairs(v) do c[T_deep_copy(k, seen)] = T_deep_copy(x, seen) end
  return c
end

function T_same(a, b, path, map)
  path = path or "root"
  map = map or {}
  if type(a) ~= type(b) then return path .. ": type " .. type(a) .. " vs " .. type(b) end
  if type(a) == "number" then
    if math.type(a) ~= math.type(b) then return path .. ": subtype " .. math.type(a) .. " vs " .. math.type(b) end
    if a ~= a and b ~= b then return nil end
    if a ~= b then return path .. (": %.17g vs %.17g"):format(a, b) end
    return nil
  end
  if type(a) ~= "table" then
    if a ~= b then return path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
    return nil
  end
  if map[a] ~= nil then
    if map[a] ~= b then return path .. ": aliasing differs" end
    return nil
  end
  map[a] = b
  for k, x in pairs(a) do
    local e = T_same(x, rawget(b, k), path .. "." .. tostring(k), map)
    if e then return e end
  end
  for k in pairs(b) do
    if rawget(a, k) == nil then return path .. "." .. tostring(k) .. ": extra key" end
  end
  return nil
end

function T_pick(list) return list[math.random(1, #list)] end
'''

REF_LAYERS = r'''
function ref_seq_layer_clamp_gain(g)
  g = tonumber(g)
  if g == nil or g ~= g then return 1.0 end
  local lo = 10 ^ (SEQ_LAYER_GAIN_MIN_DB / 20.0)
  local hi = 10 ^ (SEQ_LAYER_GAIN_MAX_DB / 20.0)
  if g < lo then return lo end
  if g > hi then return hi end
  return g
end

function ref_seq_layer_normalize_side(side)
  if type(side) ~= "table" then
    return seq_layer_default_side()
  end
  if type(side.verts) ~= "table" then
    side.verts = seq_layer_default_side().verts
  end
  for i = 1, 3 do
    local v = side.verts[i]
    if type(v) ~= "table" then
      side.verts[i] = { path = nil, name = nil, locked = (i == 1), vol = 1.0 }
    else
      v.locked = v.locked == true
      v.vol = seq_layer_vert_vol(v)
      if v.path == "" then v.path = nil end
      v.len = seq_layer_clamp_len(v.len)
      v.fade = seq_layer_clamp_fade(v.fade)
    end
  end
  side.gain = ref_seq_layer_clamp_gain(side.gain)
  local b = side.blend
  if type(b) ~= "table" then
    side.blend = { 1.0, 0.0, 0.0 }
  else
    b[1], b[2], b[3] = seq_layer_clamp_bary(tonumber(b[1]) or 0, tonumber(b[2]) or 0, tonumber(b[3]) or 0)
  end
  if type(side.rand) == "table" then
    for i = 2, 3 do
      local v = side.verts[i]
      if v.rand == nil then
        local tags = {}
        for k, t in ipairs(side.rand.tags or {}) do tags[k] = t end
        v.rand = { role = side.rand.role, tags = tags }
      end
    end
  end
  side.rand = nil
  for i = 1, 3 do
    seq_layer_normalize_rand(side.verts[i])
  end
  return side
end

function ref_seq_normalize_slot_layers(slot)
  if not slot then return end
  if type(slot.layers) ~= "table" then
    slot.layers = {}
  end
  slot.layers.transient = ref_seq_layer_normalize_side(slot.layers.transient)
  slot.layers.sustain = ref_seq_layer_normalize_side(slot.layers.sustain)
  slot.layers.linked = slot.layers.linked == true
  if slot.layers.output ~= "original" and slot.layers.output ~= "layered" then
    slot.layers.output = nil
  end
  local bias = tonumber(slot.layers.bias)
  if bias == nil then
    slot.layers.bias = 0.0
  else
    if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
    slot.layers.bias = bias
  end
  slot.layers.xfade = seq_layering_clamp_xfade(slot.layers.xfade)
  slot.layers.tail_end = seq_layer_clamp_len(slot.layers.tail_end)
  slot.layers.tail_fade = seq_layer_clamp_fade(slot.layers.tail_fade)
  if not slot.layers.tail_end and not slot.layers.tail_fade then
    slot.layers.tail_fade = nil
  end
  if type(slot.layers.unlinked_sustain) == "table" then
    slot.layers.unlinked_sustain = ref_seq_layer_normalize_side(slot.layers.unlinked_sustain)
  else
    slot.layers.unlinked_sustain = nil
  end
  if slot.layers.top_locked_inited ~= true then
    slot.layers.transient.verts[1].locked = true
    slot.layers.sustain.verts[1].locked = true
    slot.layers.top_locked_inited = true
  end
end

function ref_seq_layering_geometry_active(slot)
  if not slot then
    return false
  end
  ref_seq_normalize_slot_layers(slot)
  if slot.layers.tail_end or slot.layers.tail_fade then
    return true
  end
  local sides = { slot.layers.transient, slot.layers.sustain }
  for s = 1, 2 do
    local side = sides[s]
    if math.abs((side.blend[1] or 1.0) - 1.0) > 0.02 then
      return true
    end
    if math.abs((side.gain or 1.0) - 1.0) > 0.001 then
      return true
    end
    for i = 1, 3 do
      local v = side.verts[i]
      if v.path and (v.len or v.fade or seq_layer_corner_env(v)) and (side.blend[i] or 0) >= 0.02 then
        return true
      end
    end
    for i = 2, 3 do
      if (side.blend[i] or 0.0) >= 0.02 and side.verts[i] and side.verts[i].path then
        return true
      end
    end
    local v1 = side.verts[1]
    if v1 and v1.path and slot.sample_path and v1.path ~= slot.sample_path then
      return true
    end
  end
  return false
end

function ref_seq_layering_output(slot)
  if not slot then
    return "original"
  end
  ref_seq_normalize_slot_layers(slot)
  local out = slot.layers.output
  if out == "original" or out == "layered" then
    return out
  end
  return ref_seq_layering_geometry_active(slot) and "layered" or "original"
end

function ref_seq_layering_is_active(slot)
  return ref_seq_layering_output(slot) == "layered" and ref_seq_layering_geometry_active(slot)
end
'''

# Random, often malformed, slot.layers (and a few other slot fields).
GEN_LAYERS = r'''
local NUMS = { 0, 0.0, -0.0, 1, 1.0, -1, 0.5, 0.004, 0.005, 0.0050001, 0.0005, 0.0004, 0.0006,
  29.9, 30, 30.0, 31, 1e9, -1e9, 0/0, 1/0, -1/0, 0.25, 2, 4, 4.0, 4.5, 3.9999,
  0.0630957344480193, 0.06309573444801932, 3.9810717055349722, 3.98107170553497, 0.001, 0.25, 0.26, 0.008 }
local function num() return T_pick(NUMS) end
local function rnd_val()
  local r = math.random(1, 10)
  if r <= 5 then return num() end
  if r == 6 then return nil end
  if r == 7 then return tostring(num()) end
  if r == 8 then return math.random() * 3 - 1 end
  if r == 9 then return T_pick({ true, false, "", "x" }) end
  return math.random(-3, 5)
end
local function rnd_env()
  local r = math.random(1, 4)
  if r == 1 then return nil end
  if r == 2 then return { points = { { t = 0.0, amp = 1.0, curve = 0.0 }, { t = 1.0, amp = 1.0, curve = 0.0 } } } end
  if r == 3 then return { points = { { t = 0.0, amp = 0.5 }, { t = 0.2, amp = 1.5, curve = 0.3 }, { t = 1.0, amp = 0.0 } } } end
  return { atk = 0.01, decay = 0.05 }
end
local function rnd_rand()
  local r = math.random(1, 5)
  if r == 1 then return { role = T_pick({ "kick", "", 3, nil }), tags = T_pick({ {}, { "a", "b" }, "x" }) } end
  if r == 2 then return "junk" end
  return nil
end
local PATHS = { "/a.wav", "/b.wav", "/c.wav", "", nil }
local function rnd_vert()
  if math.random(1, 8) == 1 then return T_pick({ "v", 3, false }) end
  return {
    path = T_pick(PATHS), name = "n", locked = T_pick({ true, false, nil, 1, "yes" }),
    vol = rnd_val(), len = rnd_val(), fade = rnd_val(), env = rnd_env(), rand = rnd_rand(),
  }
end
local function rnd_blend()
  local r = math.random(1, 9)
  if r == 1 then return nil end
  if r == 2 then return "b" end
  if r == 3 then return { 1 / 3, 1 / 3, 1 / 3 } end
  if r == 4 then return { 0.1, 0.2, 0.7 } end
  if r == 5 then return { rnd_val(), rnd_val(), rnd_val() } end
  local a, b, c = math.random(), math.random(), math.random()
  if r == 6 then return { a, b, c } end
  if r == 7 then return { a / (a + b + c), b / (a + b + c), c / (a + b + c) } end
  if r == 8 then return { 1.0, 0.0, 0.0 } end
  return { 0, 0, 0 }
end
local function rnd_side()
  if math.random(1, 10) == 1 then return T_pick({ nil, "s", 5 }) end
  local side = { verts = {}, blend = rnd_blend(), gain = rnd_val() }
  if math.random(1, 10) == 1 then side.verts = T_pick({ nil, "v" }) else
    for i = 1, 3 do
      if math.random(1, 10) > 1 then side.verts[i] = rnd_vert() end
    end
  end
  if math.random(1, 6) == 1 then side.rand = { role = T_pick({ "snare", nil }), tags = T_pick({ { "t1" }, nil }) } end
  return side
end
function T_rnd_slot()
  local slot = { id = 1, sample_path = T_pick(PATHS) }
  local r = math.random(1, 12)
  if r == 1 then return slot end
  if r == 2 then slot.layers = "bad"; return slot end
  local layers = {
    transient = rnd_side(), sustain = rnd_side(),
    linked = T_pick({ true, false, nil, 1 }),
    output = T_pick({ "original", "layered", nil, "x" }),
    bias = rnd_val(), xfade = rnd_val(), tail_end = rnd_val(), tail_fade = rnd_val(),
    top_locked_inited = T_pick({ true, nil, false }),
  }
  if math.random(1, 3) == 1 then layers.unlinked_sustain = rnd_side() end
  if math.random(1, 12) == 1 then layers.sustain = layers.transient end
  if math.random(1, 12) == 1 and type(layers.sustain) == "table" then layers.unlinked_sustain = layers.sustain end
  if math.random(1, 12) == 1 and type(layers.transient) == "table" and type(layers.sustain) == "table" then
    layers.sustain.blend = layers.transient.blend
  end
  slot.layers = layers
  return slot
end
'''


def test_layer_normalizers_match_previous_implementation():
    L = _runtime()
    L.execute(REF_LAYERS)
    L.execute(GEN_LAYERS)
    bad = L.execute(r'''
      math.randomseed(11)
      local out = {}
      local fns = {
        { "seq_normalize_slot_layers", seq_normalize_slot_layers, ref_seq_normalize_slot_layers },
        { "seq_layering_geometry_active", seq_layering_geometry_active, ref_seq_layering_geometry_active },
        { "seq_layering_output", seq_layering_output, ref_seq_layering_output },
        { "seq_layering_is_active", seq_layering_is_active, ref_seq_layering_is_active },
        { "seq_layer_normalize_side", function(s) return seq_layer_normalize_side(s.layers and s.layers.transient) end,
          function(s) return ref_seq_layer_normalize_side(s.layers and s.layers.transient) end },
      }
      for trial = 1, 4000 do
        local seed_slot = T_rnd_slot()
        for _, f in ipairs(fns) do
          local a, b = T_deep_copy(seed_slot), T_deep_copy(seed_slot)
          -- Repeat calls too: a repeat normalize can still move blends by an ulp.
          local reps = math.random(1, 4)
          for rep = 1, reps do
            local okn, rn = pcall(f[2], a)
            local okr, rr = pcall(f[3], b)
            if okn ~= okr then
              out[#out + 1] = ("%s trial %d: error mismatch %s / %s"):format(f[1], trial, tostring(rn), tostring(rr))
              break
            end
            local e = T_same(rr, rn, "ret") or T_same(b, a, "slot")
            if e then
              out[#out + 1] = ("%s trial %d rep %d: %s"):format(f[1], trial, rep, e)
              break
            end
          end
          if #out > 10 then return table.concat(out, "\n") end
        end
      end
      -- nil slot
      if T_same(ref_seq_layering_is_active(nil), seq_layering_is_active(nil)) then out[#out + 1] = "nil slot is_active" end
      if T_same(ref_seq_layering_output(nil), seq_layering_output(nil)) then out[#out + 1] = "nil slot output" end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_layer_gain_clamp_follows_globals():
    L = _runtime()
    L.execute(REF_LAYERS)
    bad = L.execute(r'''
      local out = {}
      local saved_lo, saved_hi = SEQ_LAYER_GAIN_MIN_DB, SEQ_LAYER_GAIN_MAX_DB
      for _, lim in ipairs({ { -24.0, 12.0 }, { -6, 6 }, { -24.0, 12.0 }, { -48.0, 0.0 } }) do
        SEQ_LAYER_GAIN_MIN_DB, SEQ_LAYER_GAIN_MAX_DB = lim[1], lim[2]
        for _, g in ipairs({ 0, 0.001, 0.05, 0.5, 1, 1.0, 2, 3.98, 5, 100, "2", 0/0, nil, -1 }) do
          local e = T_same(ref_seq_layer_clamp_gain(g), seq_layer_clamp_gain(g), "gain " .. tostring(g))
          if e then out[#out + 1] = e end
        end
      end
      SEQ_LAYER_GAIN_MIN_DB, SEQ_LAYER_GAIN_MAX_DB = saved_lo, saved_hi
      return table.concat(out, "\n")
    ''')
    assert bad == ""


REF_CANDIDATES = r'''
function ref_seq_compact_sample_candidates(slot)
  local src = slot and slot.sample_candidates
  if type(src) ~= "table" then
    return false
  end
  local old_idx = tonumber(slot.sample_candidate_idx)
  local dense = {}
  local mapped = nil
  local had_hole = false
  local seen_empty = false
  for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
    local entry = src[i]
    if seq_candidate_entry_taken(entry) then
      if seen_empty then
        had_hole = true
      end
      dense[#dense + 1] = entry
      if old_idx and i == old_idx then
        mapped = #dense
      end
    elseif #dense > 0 then
      seen_empty = true
    end
  end
  if not had_hole then
    return false
  end
  slot.sample_candidates = dense
  if mapped then
    slot.sample_candidate_idx = mapped
  else
    local idx = old_idx or 1
    if idx < 1 then
      idx = 1
    end
    slot.sample_candidate_idx = math.max(1, math.min(idx, math.max(1, #dense)))
  end
  return true
end

function ref_seq_candidate_highest_taken(slot)
  local list = slot and slot.sample_candidates
  local high = 0
  if type(list) == "table" then
    for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
      if seq_candidate_entry_taken(list[i]) then
        high = i
      end
    end
  end
  return high
end

function ref_seq_candidate_visible_count(slot)
  local visible = SEQ_SAMPLE_CANDIDATES_MIN
  local high = ref_seq_candidate_highest_taken(slot)
  visible = math.max(visible, high)
  local list = slot and slot.sample_candidates
  local all_taken = high > 0
  if all_taken then
    for i = 1, visible do
      if not seq_candidate_entry_taken(list and list[i]) then
        all_taken = false
        break
      end
    end
  end
  if all_taken then
    visible = math.min(SEQ_SAMPLE_CANDIDATES_MAX, visible + 1)
  end
  return visible
end

function ref_seq_normalize_slot_candidates(slot)
  if not slot then
    return
  end
  if slot._cand_norm and type(slot.sample_candidates) == "table" then
    ref_seq_compact_sample_candidates(slot)
    return
  end
  local src = slot.sample_candidates
  local list = {}
  local old_idx = tonumber(slot.sample_candidate_idx)
  local mapped = nil
  if type(src) == "table" then
    for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
      local entry = src[i]
      if type(entry) == "table" and type(entry.path) == "string" and entry.path ~= "" then
        list[#list + 1] = {
          path = entry.path,
          name = (type(entry.name) == "string" and entry.name ~= "" and entry.name) or basename(entry.path),
          x = tonumber(entry.x) or 0.5,
          y = tonumber(entry.y) or 0.5,
          dominant_freq = tonumber(entry.dominant_freq),
          brightness = tonumber(entry.brightness),
          sub_weight = tonumber(entry.sub_weight),
          effective_duration = tonumber(entry.effective_duration),
        }
        if old_idx and i == old_idx then
          mapped = #list
        end
      end
    end
  end
  slot.sample_candidates = list
  local idx = mapped
  if not idx then
    idx = old_idx
    if not idx or idx < 1 or idx > SEQ_SAMPLE_CANDIDATES_MAX then
      idx = 1
    end
    idx = math.max(1, math.min(idx, math.max(1, #list)))
  end
  slot.sample_candidate_idx = idx
  if not seq_candidate_entry_taken(list[1]) and type(slot.sample_path) == "string" and slot.sample_path ~= "" then
    local sample = find_sample_by_path(slot.sample_path) or {
      path = slot.sample_path,
      name = slot.sample_name,
    }
    list[1] = seq_candidate_entry_from_sample(sample)
  end
  slot._cand_norm = true
end


function ref_seq_box(x, y, w, h)
  w = math.max(0, w or 0)
  h = math.max(0, h or 0)
  return { x = x, y = y, w = w, h = h, x1 = x + w, y1 = y + h }
end

function ref_seq_fit_mix_strip(avail_w, btn, gap, vol_w, pan_w, midi_w)
  vol_w = vol_w or 52.0
  pan_w = pan_w or 40.0
  midi_w = midi_w or 28.0
  btn = btn or 14.0
  gap = gap or 3.0
  local function width()
    return seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
  end
  while width() > avail_w do
    if vol_w > 34 then
      vol_w = vol_w - 2
    elseif pan_w > 26 then
      pan_w = pan_w - 2
    elseif midi_w > 22 then
      midi_w = midi_w - 2
    elseif btn > 12 then
      btn = btn - 1
    else
      break
    end
  end
  return btn, vol_w, pan_w, midi_w, width()
end

function ref_seq_place_mix_strip(layout, x, y, btn, gap, vol_w, pan_w, midi_w, row_h)
  local by = y + (row_h - btn) * 0.5
  layout.mute = ref_seq_box(x, by, btn, btn)
  x = x + btn
  layout.solo = ref_seq_box(x, by, btn, btn)
  x = x + btn + SEQ_TCP_GROUP_GAP
  layout.vol = ref_seq_box(x, y, vol_w, row_h)
  x = x + vol_w + gap
  layout.pan = ref_seq_box(x, y, pan_w, row_h)
  x = x + pan_w + SEQ_TCP_GROUP_GAP
  layout.midi = ref_seq_box(x, by, midi_w, btn)
  x = x + midi_w
  layout.gear = ref_seq_box(x, by, btn, btn)
  x = x + btn
  layout.overlap = ref_seq_box(x, by, btn, btn)
  return layout.overlap.x1
end

function ref_seq_place_sample_candidates(slot, x1, y0, y1, max_w)
  local empty = { boxes = {}, w = 0, hit = ref_seq_box(0, 0, 0, 0), sq = 0 }
  x1, y0, y1 = x1 or 0, y0 or 0, y1 or 0
  max_w = max_w or 0
  local avail_h = y1 - y0
  if avail_h < 12.0 or max_w < 12.0 then
    return empty
  end
  local gap = 2.0
  local count = ref_seq_candidate_visible_count(slot)
  local sq = math.max(12.0, math.min(avail_h, 24.0))
  local rows = 1
  local cols = count
  local function dims(size, n, r)
    r = math.max(1, r)
    local c = math.ceil(n / r)
    return r, c, c * size + (c - 1) * gap, math.min(n, r) * size + (math.min(n, r) - 1) * gap
  end
  local _, _, grid_w, grid_h = dims(sq, count, rows)
  if grid_w > max_w then
    local rows_fit = math.max(1, math.floor((avail_h + gap) / (sq + gap)))
    if rows_fit > 1 then
      rows = math.min(rows_fit, count)
      _, cols, grid_w, grid_h = dims(sq, count, rows)
    end
  end
  while grid_w > max_w and sq > 12.0 do
    sq = sq - 1.0
    _, cols, grid_w, grid_h = dims(sq, count, rows)
  end
  if grid_w > max_w then
    local fit_cols = math.max(1, math.floor((max_w + gap) / (sq + gap)))
    count = math.max(1, math.min(count, fit_cols * rows))
    rows, cols, grid_w, grid_h = dims(sq, count, rows)
  end
  if grid_w > max_w or grid_w <= 0 then
    return empty
  end
  local left = x1 - grid_w
  local top = y0 + (avail_h - grid_h) * 0.5
  local boxes = {}
  local i = 1
  for row = 1, rows do
    for col = 1, cols do
      if i > count then
        break
      end
      boxes[i] = ref_seq_box(left + (col - 1) * (sq + gap), top + (row - 1) * (sq + gap), sq, sq)
      i = i + 1
    end
  end
  return {
    boxes = boxes,
    w = grid_w,
    hit = ref_seq_box(left, top, grid_w, grid_h),
    sq = sq,
  }
end

function ref_seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, top_y, name_h, expand_w, gap)
  layout.expand = ref_seq_box(inner_x0, top_y, expand_w, name_h)
  local name_x = inner_x0 + expand_w
  local name_w = math.max(0.0, inner_x1 - name_x)
  local cand = ref_seq_place_sample_candidates(slot, inner_x1, top_y, top_y + name_h, math.max(0.0, name_w - 36.0))
  if cand.w > 0 then
    layout.candidates = cand.hit
    layout.candidate_boxes = cand.boxes
    name_w = math.max(0.0, cand.hit.x - (gap or 3.0) - name_x)
  end
  layout.name = ref_seq_box(name_x, top_y, name_w, name_h)
end

function ref_seq_get_track_control_layout(x0, y0, x1, y1, slot, opts)
  x0, y0, x1, y1 = x0 or 0, y0 or 0, x1 or 0, y1 or 0
  if x1 < x0 then x1 = x0 end
  if y1 < y0 then y1 = y0 end
  opts = opts or {}
  local lane_h = y1 - y0
  local pad = (lane_h >= 64.0) and 4.0 or 3.0
  local gap = 3.0
  local expand_w = opts.hide_expand and 0.0 or 18.0
  local inner_x0 = x0 + pad
  local inner_x1 = x1 - pad
  local inner_w = math.max(0.0, inner_x1 - inner_x0)
  local mode = "tiny"
  if lane_h >= 100.0 then
    mode = "mixer"
  elseif lane_h >= 64.0 then
    mode = "stack"
  elseif lane_h >= 38.0 then
    mode = "split"
  end

  local layout = {
    mode = mode,
    lane_h = lane_h,
    expand = ref_seq_box(0, 0, 0, 0),
    name = ref_seq_box(0, 0, 0, 0),
    gear = ref_seq_box(0, 0, 0, 0),
    vol = ref_seq_box(0, 0, 0, 0),
    pan = ref_seq_box(0, 0, 0, 0),
    midi = ref_seq_box(0, 0, 0, 0),
    mute = ref_seq_box(0, 0, 0, 0),
    solo = ref_seq_box(0, 0, 0, 0),
    overlap = ref_seq_box(0, 0, 0, 0),
    env = ref_seq_box(0, 0, 0, 0),
    mix_hit = ref_seq_box(0, 0, 0, 0),
    candidates = ref_seq_box(0, 0, 0, 0),
    candidate_boxes = {},
  }

  if mode == "tiny" then
    local btn = math.max(12.0, math.min(15.0, lane_h - 8.0))
    local row_h = btn
    local mid_y = y0 + (lane_h - row_h) * 0.5
    local name_min = 28.0
    local btn2, vol_w, pan_w, midi_w, mix_w = ref_seq_fit_mix_strip(
      math.max(80.0, inner_w - expand_w - name_min - gap), btn, gap, 48.0, 36.0, 26.0
    )
    btn = btn2
    row_h = btn
    mid_y = y0 + (lane_h - row_h) * 0.5
    local mix_x = inner_x1 - mix_w
    local name_x = inner_x0 + expand_w
    local mid_space = math.max(0.0, mix_x - gap - name_x)
    local env_w = 0.0
    if mid_space >= name_min + gap + 40.0 then
      env_w = math.min(SEQ_ENV_PREVIEW_W or 80.0, mid_space - name_min - gap)
      if env_w < 36.0 then env_w = 0.0 end
    end
    local name_w = math.max(0.0, mid_space - (env_w > 0 and (env_w + gap) or 0.0))
    layout.expand = ref_seq_box(inner_x0, mid_y, expand_w, row_h)
    layout.name = ref_seq_box(name_x, mid_y, name_w, row_h)
    if env_w > 0 then
      layout.env = ref_seq_box(name_x + name_w + gap, mid_y, env_w, row_h)
    end
    ref_seq_place_mix_strip(layout, mix_x, mid_y, btn, gap, vol_w, pan_w, midi_w, row_h)
    local hit_x0 = (env_w > 0) and layout.env.x or layout.mute.x
    layout.mix_hit = ref_seq_box(hit_x0, mid_y, inner_x1 - hit_x0, row_h)

  elseif mode == "split" then
    local name_h = math.max(14.0, math.min(17.0, 14.0 + (lane_h - 38.0) * 0.12))
    local btn = math.max(13.0, math.min(17.0, 13.0 + (lane_h - 38.0) * 0.16))
    local row_h = btn
    local gap_v = 2.0
    local block_h = name_h + gap_v + row_h
    local top_y = y0 + math.max(pad, (lane_h - block_h) * 0.5)
    local ctrl_y = top_y + name_h + gap_v
    ref_seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, top_y, name_h, expand_w, gap)

    local env_reserve = 0.0
    if inner_w >= 210.0 then
      env_reserve = math.max(40.0, math.min(88.0, inner_w * 0.24))
    end
    local mix_avail = inner_w - (env_reserve > 0 and (env_reserve + gap) or 0.0)
    local btn2, vol_w, pan_w, midi_w, mix_w = ref_seq_fit_mix_strip(mix_avail, btn, gap, 52.0, 40.0, 28.0)
    btn = btn2
    row_h = math.max(row_h, btn)
    ctrl_y = top_y + name_h + gap_v
    local leftover = inner_w - mix_w - gap
    local env_w = 0.0
    if leftover >= 36.0 then
      if leftover > 92.0 then
        local grow = leftover - 92.0
        vol_w = vol_w + grow * 0.62
        pan_w = pan_w + grow * 0.38
        mix_w = seq_mix_strip_width(btn, gap, vol_w, pan_w, midi_w)
        leftover = inner_w - mix_w - gap
      end
      env_w = leftover
    end
    ref_seq_place_mix_strip(layout, inner_x0, ctrl_y, btn, gap, vol_w, pan_w, midi_w, row_h)
    if env_w >= 36.0 then
      layout.env = ref_seq_box(layout.overlap.x1 + gap, ctrl_y, env_w, row_h)
    end
    layout.mix_hit = ref_seq_box(inner_x0, ctrl_y, inner_w, row_h)

  elseif mode == "stack" then
    local name_h = 16.0
    local rest = lane_h - pad * 2 - name_h - 4.0
    local row_h = math.max(14.0, math.min(20.0, rest * 0.42))
    local env_h = math.max(12.0, rest - row_h - 3.0)
    local btn = math.max(14.0, math.min(row_h, 18.0))
    local top_y = y0 + pad
    local mix_y = top_y + name_h + 3.0
    local env_y = mix_y + row_h + 3.0
    if env_y + env_h > y1 - pad then
      env_h = math.max(12.0, (y1 - pad) - env_y)
    end
    ref_seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, top_y, name_h, expand_w, gap)

    local btn2, vol_w, pan_w, midi_w, mix_w = ref_seq_fit_mix_strip(inner_w, btn, gap, 56.0, 42.0, 30.0)
    btn = btn2
    if inner_w > mix_w then
      local grow = inner_w - mix_w
      vol_w = vol_w + grow * 0.62
      pan_w = pan_w + grow * 0.38
    end
    ref_seq_place_mix_strip(layout, inner_x0, mix_y, btn, gap, vol_w, pan_w, midi_w, row_h)
    layout.env = ref_seq_box(inner_x0, env_y, inner_w, env_h)
    layout.mix_hit = ref_seq_box(inner_x0, mix_y, inner_w, (y1 - pad) - mix_y)

  else
    local name_h = math.max(15.0, math.min(20.0, 15.0 + (lane_h - 100.0) * 0.05))
    local btn = math.max(15.0, math.min(20.0, 15.0 + (lane_h - 100.0) * 0.05))
    local rest = lane_h - pad * 2 - name_h - btn - 9.0
    local bar_h = math.max(15.0, math.min(26.0, (rest - 6.0) / 3.0))
    local env_h = math.max(14.0, rest - bar_h * 2.0 - 6.0)
    local y = y0 + pad
    ref_seq_layout_place_name_candidates(layout, slot, inner_x0, inner_x1, y, name_h, expand_w, gap)
    y = y + name_h + 3.0
    local midi_w = math.max(32.0, math.min(52.0, btn * 2.4))
    local cx = inner_x0
    layout.mute = ref_seq_box(cx, y, btn, btn); cx = cx + btn
    layout.solo = ref_seq_box(cx, y, btn, btn); cx = cx + btn + SEQ_TCP_GROUP_GAP
    layout.midi = ref_seq_box(cx, y, midi_w, btn); cx = cx + midi_w
    layout.gear = ref_seq_box(cx, y, btn, btn); cx = cx + btn
    layout.overlap = ref_seq_box(cx, y, btn, btn)
    y = y + btn + 3.0
    layout.vol = ref_seq_box(inner_x0, y, inner_w, bar_h)
    y = y + bar_h + 3.0
    layout.pan = ref_seq_box(inner_x0, y, inner_w, bar_h)
    y = y + bar_h + 3.0
    env_h = math.max(12.0, (y1 - pad) - y)
    layout.env = ref_seq_box(inner_x0, y, inner_w, env_h)
    layout.mix_hit = ref_seq_box(inner_x0, layout.mute.y, inner_w, (y1 - pad) - layout.mute.y)
  end

  return layout
end

function ref_seq_candidate_chip_props(entry)
  local sample = entry and entry.path and find_sample_by_path(entry.path) or nil
  local function num(key, fallback)
    if sample and type(sample[key]) == "number" then
      return sample[key]
    end
    if entry and type(entry[key]) == "number" then
      return entry[key]
    end
    return fallback
  end
  local dur = nil
  if sample and sample_map_duration then
    dur = sample_map_duration(sample)
  end
  if type(dur) ~= "number" or dur <= 0 then
    dur = num("effective_duration", num("duration", nil))
  end
  return {
    freq = num("dominant_freq", 440.0),
    brightness = num("brightness", nil),
    weight = math.max(0.0, math.min(1.0, num("sub_weight", 0.45))),
    duration = dur,
  }
end

function ref_seq_candidate_slot_scale(slot)
  if not slot then
    return nil
  end
  ref_seq_normalize_slot_candidates(slot)
  local n = 0
  local b_lo, b_hi = 1e9, -1e9
  local w_lo, w_hi = 1e9, -1e9
  local d_lo, d_hi = 1e9, -1e9
  local list = slot.sample_candidates
  if type(list) ~= "table" then
    return nil
  end
  for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
    if seq_candidate_entry_taken(list[i]) then
      local p = ref_seq_candidate_chip_props(list[i])
      local bright = p.brightness or p.freq
      n = n + 1
      if type(bright) == "number" then
        b_lo = math.min(b_lo, bright)
        b_hi = math.max(b_hi, bright)
      end
      w_lo = math.min(w_lo, p.weight)
      w_hi = math.max(w_hi, p.weight)
      if type(p.duration) == "number" and p.duration > 0 then
        d_lo = math.min(d_lo, p.duration)
        d_hi = math.max(d_hi, p.duration)
      end
    end
  end
  if n < 2 then
    return nil
  end
  return {
    bright_lo = b_lo, bright_hi = b_hi,
    weight_lo = w_lo, weight_hi = w_hi,
    dur_lo = d_lo, dur_hi = d_hi,
  }
end

'''

# A few library samples (so chip props read the library) and random,
# often malformed, candidate lists.
GEN_CANDIDATES = r'''
state.samples = {}
for i = 1, 6 do
  state.samples[i] = { path = "/lib/s" .. i .. ".wav", name = "s" .. i .. ".wav", x = 0.1 * i, y = 0.5,
    dominant_freq = (i % 2 == 0) and 80 * i or nil, brightness = (i % 3 == 0) and nil or 0.15 * i,
    sub_weight = (i == 4) and 1.7 or 0.1 * i, effective_duration = (i == 5) and 0 or 0.05 * i, duration = 0.3 }
end
rebuild_samples_path_index()
local ENTRIES = {
  function() return nil end,
  function() return {} end,
  function() return { path = "" } end,
  function() return "x" end,
  function() return { path = 5 } end,
  function() return { path = "/lib/s" .. math.random(1, 6) .. ".wav" } end,
  function() return { path = "/ext/e" .. math.random(1, 4) .. ".wav", dominant_freq = math.random() * 9000,
    brightness = T_pick({ 0.2, nil, 0.9 }), sub_weight = T_pick({ -0.5, 0.3, 2 }),
    effective_duration = T_pick({ 0.1, 0, nil }), duration = T_pick({ 0.4, nil }) } end,
}
function T_rnd_cand_slot()
  local slot = { id = math.random(1, 50), sample_path = T_pick({ "/lib/s1.wav", "/ext/x.wav", "", nil }) }
  if math.random(1, 8) > 1 then
    local list = {}
    local n = math.random(0, 14)
    for i = 1, n do list[i] = T_pick(ENTRIES)() end
    slot.sample_candidates = list
  else
    slot.sample_candidates = T_pick({ nil, "bad" })
  end
  slot.sample_candidate_idx = T_pick({ nil, 0, 1, 2, 3, 5, 12, 13, "3", 2.0, -1 })
  slot._cand_norm = T_pick({ true, nil })
  return slot
end
'''


def test_candidate_helpers_match_previous_implementation():
    L = _runtime()
    L.execute(REF_CANDIDATES)
    L.execute(GEN_CANDIDATES)
    bad = L.execute(r'''
      math.randomseed(17)
      local out = {}
      local fns = {
        { "compact", seq_compact_sample_candidates, ref_seq_compact_sample_candidates },
        { "highest", seq_candidate_highest_taken, ref_seq_candidate_highest_taken },
        { "visible", seq_candidate_visible_count, ref_seq_candidate_visible_count },
        { "normalize", seq_normalize_slot_candidates, ref_seq_normalize_slot_candidates },
        { "scale", seq_candidate_slot_scale, ref_seq_candidate_slot_scale },
        { "props", function(s) return seq_candidate_chip_props(type(s.sample_candidates) == "table" and s.sample_candidates[1] or nil) end,
          function(s) return ref_seq_candidate_chip_props(type(s.sample_candidates) == "table" and s.sample_candidates[1] or nil) end },
      }
      for trial = 1, 3000 do
        local seed_slot = T_rnd_cand_slot()
        for _, f in ipairs(fns) do
          local a, b = T_deep_copy(seed_slot), T_deep_copy(seed_slot)
          local okn, rn = pcall(f[2], a)
          local okr, rr = pcall(f[3], b)
          local e = (okn ~= okr) and ("error mismatch " .. tostring(rn) .. " / " .. tostring(rr))
            or T_same(rr, rn, "ret") or T_same(b, a, "slot")
          if e then
            out[#out + 1] = ("%s trial %d: %s"):format(f[1], trial, e)
            if #out > 10 then return table.concat(out, "\n") end
          end
        end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_track_control_layout_matches_previous_implementation():
    L = _runtime()
    L.execute(REF_CANDIDATES)
    L.execute(GEN_CANDIDATES)
    bad = L.execute(r'''
      math.randomseed(23)
      local out = {}
      -- seq_box on odd sizes (number subtypes matter: x1 = x + w).
      for _, w in ipairs({ 0, 0.0, -0.0, -3, 5, 5.5, 0/0, 1/0, -1/0, nil, false }) do
        for _, h in ipairs({ 0, 2.0, -1.5, nil }) do
          local e = T_same(ref_seq_box(1, 2.5, w, h), seq_box(1, 2.5, w, h), "box " .. tostring(w) .. "," .. tostring(h))
          if e then out[#out + 1] = e end
        end
      end
      for trial = 1, 3000 do
        local slot = T_rnd_cand_slot()
        if math.random(1, 4) > 1 then ref_seq_normalize_slot_candidates(slot) end
        local x0 = T_pick({ 0, 3.5, 100, nil })
        local y0 = T_pick({ 0, 10.25, 200 })
        local lane_h = T_pick({ 14, 20, 30, 37.9, 38, 45, 50.5, 63.9, 64, 80, 99.9, 100, 120, 160, math.random() * 180 })
        local width = T_pick({ 40, 120, 180, 209, 210, 260, 400, 734, math.random() * 900 })
        local x1 = x0 and (x0 + width) or width
        local y1 = y0 + lane_h
        if math.random(1, 20) == 1 then x1 = (x0 or 0) - 5 end
        local opts = T_pick({ nil, { hide_expand = true }, {} })
        local a, b = T_deep_copy(slot), T_deep_copy(slot)
        local okn, ln = pcall(seq_get_track_control_layout, x0, y0, x1, y1, a, opts)
        local okr, lr = pcall(ref_seq_get_track_control_layout, x0, y0, x1, y1, b, opts)
        local e = (okn ~= okr) and ("error mismatch " .. tostring(ln) .. " / " .. tostring(lr))
          or T_same(lr, ln, "layout") or T_same(b, a, "slot")
        if e then
          out[#out + 1] = ("trial %d (h %s w %s): %s"):format(trial, tostring(lane_h), tostring(width), e)
          if #out > 10 then break end
        end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


REF_SQUARE = r'''
function ref_seq_draw_sample_candidate_square(dl, box, entry, is_active, is_hovered, scale, slot_n, alpha)
  if not dl or not box or box.w < 4 then
    return
  end
  local x, y, w, h = box.x, box.y, box.w, box.h
  local rounding = math.min(3.5, w * 0.22)
  local taken = seq_candidate_entry_taken(entry)
  local a = math.max(0.0, math.min(1.0, tonumber(alpha) or 1.0))
  local function ca(col, mul)
    if not col then
      return col
    end
    local orig_a = (col % 256) / 255.0
    return change_color_alpha(col, orig_a * a * (mul or 1.0))
  end
  local bg = is_active and (taken and 0x122016FF or UI_THEME.accent_fill) or (is_hovered and 0x1A1B1EFF or 0x0F1013FF)
  local edge = UI_THEME.border
  local edge_w = 1.0
  if is_active then
    edge = 0xFFFFFF80
    edge_w = 1.8
  elseif is_hovered then
    edge = 0xEBECF0FF
  elseif taken then
    edge = UI_THEME.border_hvr
  end

  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, ca(bg), rounding)

  if taken then
    local props = ref_seq_candidate_chip_props(entry)
    local hue = seq_candidate_freq_hue(props.freq)
    local bright_src = props.brightness or props.freq
    local bright_g = seq_candidate_log_unit(bright_src, 100.0, 2500.0)
    local bright_t = bright_g
    local weight_t = props.weight
    if scale then
      bright_t = seq_candidate_unit_in_range(bright_src, scale.bright_lo, scale.bright_hi, bright_g)
      weight_t = seq_candidate_unit_in_range(props.weight, scale.weight_lo, scale.weight_hi, props.weight)
    end
    local sat = 0.55 + weight_t * 0.40
    if is_hovered then
      bright_t = math.min(1.0, bright_t + 0.08)
    end
    if is_active then
      bright_t = math.min(1.0, bright_t + 0.10)
    end
    local col_top = seq_candidate_hsv_to_color(hue, sat, 0.52 + bright_t * 0.46, a)
    local col_bot = seq_candidate_hsv_to_color(hue, math.min(1.0, sat + 0.08), 0.22 + bright_t * 0.28, a)

    -- MultiColor fills are square; clip rounded rects per band so the chip
    -- follows the same corner radius as the outline.
    local bands = math.max(4, math.min(10, math.floor(h + 0.5)))
    if r.ImGui_DrawList_PushClipRect then
      for i = 0, bands - 1 do
        local t = (i + 0.5) / bands
        local col = blend_colors(col_top, col_bot, t)
        local y0 = y + (h * i) / bands
        local y1 = y + (h * (i + 1) / bands)
        r.ImGui_DrawList_PushClipRect(dl, x, y0, x + w, math.min(y + h, y1 + 0.5), true)
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, col, rounding)
        r.ImGui_DrawList_PopClipRect(dl)
      end
    else
      r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, col_top, rounding)
    end
  end

  if is_active then
    r.ImGui_DrawList_AddRect(dl, x - 1.2, y - 1.2, x + w + 1.2, y + h + 1.2,
      ca(0xFFFFFF40), rounding + 1.0, 0, 2.0)
  end
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, ca(edge), rounding, 0, edge_w)

  if state.seq_candidate_show_numbers ~= false and slot_n then
    local label = tostring(slot_n)
    local font = r.ImGui_GetFont and r.ImGui_GetFont(ctx) or nil
    local base_sz = (r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx)) or 13.0
    local sz = base_sz * 0.58
    local tw, th = r.ImGui_CalcTextSize(ctx, label)
    tw = (tw or 6) * (sz / math.max(1.0, base_sz))
    th = (th or 10) * (sz / math.max(1.0, base_sz))
    local tx = x + (w - tw) * 0.5
    local ty = y + (h - th) * 0.5
    local num_col = ca(taken and 0xFFFFFF72 or 0xCCCDD150)
    local sh_col = ca(0x00000044)
    if r.ImGui_DrawList_AddTextEx then
      r.ImGui_DrawList_AddTextEx(dl, font, sz, tx + 0.5, ty + 0.5, sh_col, label)
      r.ImGui_DrawList_AddTextEx(dl, font, sz, tx, ty, num_col, label)
    else
      r.ImGui_DrawList_AddText(dl, tx + 0.5, ty + 0.5, sh_col, label)
      r.ImGui_DrawList_AddText(dl, tx, ty, num_col, label)
    end
  end
end

'''

# Records every draw-list call (name and all arguments) into T_DRAWS.
DRAW_RECORDER = r'''
T_DRAWS = {}
for _, name in ipairs({ "ImGui_DrawList_AddRectFilled", "ImGui_DrawList_AddRect", "ImGui_DrawList_PushClipRect",
    "ImGui_DrawList_PopClipRect", "ImGui_DrawList_AddTextEx", "ImGui_DrawList_AddText" }) do
  local f = r[name]
  rawset(r, name, function(...)
    T_DRAWS[#T_DRAWS + 1] = table.pack(name, ...)
    return f(...)
  end)
end

-- A local function reachable from fn through upvalues (depth-first).
function T_upvalue(fn, name, seen)
  seen = seen or {}
  if seen[fn] then return nil end
  seen[fn] = true
  for i = 1, 255 do
    local n, v = debug.getupvalue(fn, i)
    if n == nil then break end
    if n == name then return v end
    if type(v) == "function" then
      local found = T_upvalue(v, name, seen)
      if found ~= nil then return found end
    end
  end
  return nil
end
'''


def test_candidate_colour_memos_match_direct_calls():
    # The memoized colour helpers must return exactly what the functions they
    # wrap return, on hits, misses and after the memo is cleared when full,
    # for every number subtype (non-float and NaN inputs bypass the memo).
    L = _runtime()
    L.execute(DRAW_RECORDER)
    bad = L.execute(r'''
      math.randomseed(31)
      local sq = seq_draw_sample_candidate_square
      local hue = T_upvalue(sq, "candidate_freq_hue")
      local bright = T_upvalue(sq, "candidate_bright_unit")
      local hsv = T_upvalue(sq, "candidate_hsv_color")
      local bands = T_upvalue(sq, "candidate_band_colors")
      local memo = T_upvalue(hsv, "cand_color_memo")
      assert(hue and bright and hsv and bands and memo, "memo functions not found")
      local out = {}
      local function check(e, what)
        if e then
          out[#out + 1] = what .. ": " .. e
        end
      end
      local POOL = { 0.0, -0.0, 0, 1, 1.0, 0.5, 2.0, -3.0, 60.0, 120.0, 359.9, 360.0, 440.0, 440,
        1e9, 1/0, -1/0, 0/0, 100.0, 2500.0, 0.03, 9999.5, 20000.0, "7.5", "x", nil, true }
      local function num()
        local k = math.random(1, 4)
        if k == 1 then return POOL[math.random(1, #POOL)] end
        if k == 2 then return math.random() * 3 end
        if k == 3 then return math.random() * 12000 - 500 end
        return math.floor(math.random() * 40) / 8
      end
      local resets, peak, prev_n = 0, 0, memo.n
      for trial = 1, 12000 do
        local f = num()
        check(T_same(seq_candidate_freq_hue(f), hue(f), "hue"), "hue(" .. tostring(f) .. ")")
        local v = num()
        check(T_same(seq_candidate_log_unit(v, 100.0, 2500.0), bright(v), "bright"), "bright(" .. tostring(v) .. ")")
        local h, s_, v_, a = num(), num(), num(), num()
        local okd, d = pcall(seq_candidate_hsv_to_color, h, s_, v_, a)
        local okm, m = pcall(hsv, h, s_, v_, a)
        check((okd ~= okm) and "error mismatch" or (okd and T_same(d, m, "hsv")),
          ("hsv(%s, %s, %s, %s)"):format(tostring(h), tostring(s_), tostring(v_), tostring(a)))
        local top = T_pick({ 0x80A0C0FF, 0x00000000, 0xFFFFFFFF, math.random(0, 0xFFFFFFFF), 255.0, -5 })
        local bot = T_pick({ 0x203040FF, 0xFFFFFF00, math.random(0, 0xFFFFFFFF), 1 << 61, 4096.0 })
        local nb = T_pick({ 4, 7, 10, 0, 16, 4.0, math.random(1, 15) })
        local okb, cols = pcall(bands, top, bot, nb)
        if not okb then
          check(pcall(blend_colors, top, bot, 0.5 / nb) and "memo errors, direct call does not" or nil,
            ("bands(%s, %s, %s)"):format(tostring(top), tostring(bot), tostring(nb)))
        elseif cols ~= nil then
          for i = 0, nb - 1 do
            check(T_same(blend_colors(top, bot, (i + 0.5) / nb), cols[i + 1], "band"),
              ("bands(%s, %s, %s)[%d]"):format(tostring(top), tostring(bot), tostring(nb), i))
          end
          check(cols[nb + 1] ~= nil and "extra band" or nil, "bands")
        end
        if memo.n < prev_n then resets = resets + 1 end
        prev_n = memo.n
        if memo.n > peak then peak = memo.n end
        if #out > 10 then break end
      end
      check(resets < 3 and ("memo cleared only " .. resets .. " times") or nil, "reset")
      check(peak > 2048 and ("memo grew to " .. peak) or nil, "bound")
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_candidate_square_draws_match_previous_implementation():
    L = _runtime()
    L.execute(REF_CANDIDATES)
    L.execute(GEN_CANDIDATES)
    L.execute(REF_SQUARE)
    L.execute(DRAW_RECORDER)
    bad = L.execute(r'''
      math.randomseed(37)
      local out = {}
      local FIXED = {}
      for i = 1, 8 do
        FIXED[i] = { path = "/ext/f" .. i .. ".wav", dominant_freq = 50.0 * i * i, brightness = T_pick({ 0.3, nil }),
          sub_weight = 0.1 * i, effective_duration = 0.2 }
      end
      local function rnd_entry()
        local k = math.random(1, 4)
        if k == 1 then return T_pick(FIXED) end
        if k == 2 then return T_pick({ nil, {}, { path = "" }, { path = "/lib/s" .. math.random(1, 6) .. ".wav" } }) end
        return { path = "/ext/r.wav", dominant_freq = T_pick({ math.random() * 12000, math.random(1, 9000), 0, -1.0, 0/0, nil }),
          brightness = T_pick({ math.random() * 3000, math.random(), 0, 7, nil }),
          sub_weight = T_pick({ math.random() * 2 - 0.5, 1, nil }), effective_duration = 0.1 }
      end
      local function rnd_scale()
        if math.random(1, 3) == 1 then return nil end
        return { bright_lo = T_pick({ 100.0, 0.1, nil }), bright_hi = T_pick({ 2500.0, 0.9, 0.1, nil }),
          weight_lo = T_pick({ 0.0, 0.5, nil }), weight_hi = T_pick({ 1.0, 0.5, 2 }) }
      end
      local saved_numbers = state.seq_candidate_show_numbers
      for trial = 1, 6000 do
        local box = seq_box(math.random() * 400, T_pick({ 3.0, 10.5, math.random() * 50 }),
          T_pick({ 3.5, 4, 12.0, math.random() * 30 }), T_pick({ 3.0, 4.4, 9.6, 12.0, 24, math.random() * 30 }))
        local entry = rnd_entry()
        local active, hovered = math.random(1, 3) == 1, math.random(1, 3) == 1
        local scale = rnd_scale()
        local slot_n = T_pick({ nil, 1, 7, 12 })
        local alpha = T_pick({ nil, 1.0, 1, 0, 0.35, math.random(), 1.7, -2, "0.5", "x" })
        state.seq_candidate_show_numbers = T_pick({ true, false, nil })
        T_DRAWS = {}
        local okr, er = pcall(ref_seq_draw_sample_candidate_square, {}, box, T_deep_copy(entry), active, hovered,
          T_deep_copy(scale), slot_n, alpha)
        local want = T_DRAWS
        T_DRAWS = {}
        local okn, en = pcall(seq_draw_sample_candidate_square, {}, box, T_deep_copy(entry), active, hovered,
          T_deep_copy(scale), slot_n, alpha)
        local e = (okr ~= okn) and ("error mismatch " .. tostring(er) .. " / " .. tostring(en))
          or T_same(want, T_DRAWS, "draws")
        if e then
          out[#out + 1] = ("trial %d: %s"):format(trial, e)
          if #out > 10 then break end
        end
      end
      state.seq_candidate_show_numbers = saved_numbers
      return table.concat(out, "\n")
    ''')
    assert bad == ""


REF_ROLES = r'''
function ref_classify_seq_role_text(text)
  local s = tostring(text or ""):lower()
  if s == "" then
    return nil
  end
  if s:find("kick", 1, true) or s:find("kck", 1, true) then
    return "kick"
  end
  if s:find("snare", 1, true) or s:find("snr", 1, true) then
    return "snare"
  end
  if s:find("clap", 1, true) then
    return "clap"
  end
  if s:find("rim", 1, true) or s:find("snap", 1, true) then
    return "rim"
  end
  if s:find("tom", 1, true) then
    return "tom"
  end
  if s:find("ride", 1, true) then
    return "ride"
  end
  if s:find("crash", 1, true) or s:find("cymbal", 1, true) then
    return "crash"
  end
  if s:find("hihat", 1, true) or s:find("hi hat", 1, true) or s:find("hat", 1, true)
      or s:find("hh", 1, true) then
    return "hat"
  end
  if s:find("808", 1, true) then
    return "808"
  end
  if s:find("sub", 1, true) or s:find("bass", 1, true) then
    return "bass"
  end
  if s:find("perc", 1, true) or s:find("percussion", 1, true) or s:find("shaker", 1, true)
      or s:find("tamb", 1, true) or s:find("cowbell", 1, true) then
    return "perc"
  end
  if s:find("riser", 1, true) or s:find("impact", 1, true) or s:find("sweep", 1, true)
      or s:find("whoosh", 1, true) or s:find("sfx", 1, true) or s:find("fx", 1, true) then
    return "fx"
  end
  if s:find("vocal", 1, true) or s:find("vox", 1, true) or s:find("voice", 1, true) then
    return "vocal"
  end
  if s:find("swell", 1, true) then
    return "swell"
  end
  return nil
end

function ref_infer_seq_track_role(slot)
  if not slot then
    return "other"
  end

  local role = ref_classify_seq_role_text(slot.sample_tag)
  if role then
    return role
  end

  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if sample and type(sample.tags) == "table" then
    for _, tag in ipairs(sample.tags) do
      role = ref_classify_seq_role_text(tag)
      if role then
        return role
      end
    end
  end

  role = ref_classify_seq_role_text(sample and sample.name)
      or ref_classify_seq_role_text(sample and sample.path)
      or ref_classify_seq_role_text(slot.sample_name)
      or ref_classify_seq_role_text(slot.name)

  return role or "other"
end

'''


def test_role_text_memo_matches_previous_implementation():
    # classify_seq_role_text memoizes by the lowered text: hits, misses,
    # clears (more than 1024 distinct texts), non-string inputs and
    # __tostring tables (called every time, like before) must all behave
    # as the previous implementation did.
    L = _runtime()
    L.execute(REF_ROLES)
    bad = L.execute(r'''
      math.randomseed(41)
      local out = {}
      local WORDS = { "Kick", "KCK", "snare", "SNR", "clap", "Rim", "snap", "TOM", "ride", "Crash", "cymbal",
        "HiHat", "hi hat", "hat", "HH", "808", "sub", "BASS", "perc", "Percussion", "shaker", "tamb", "cowbell",
        "riser", "impact", "sweep", "whoosh", "SFX", "fx", "vocal", "vox", "voice", "swell", "drum", "loop",
        "", " ", "/", "_", "-", "01", "\0", "\xC4\xB1", "I", "\xFF" }
      local calls = 0
      local meta = { __tostring = function(t) calls = calls + 1; return t.label end }
      local function rnd_text()
        local k = math.random(1, 9)
        if k == 1 then return ({ nil, false, true, 0, 808, -1.5, 1e300, 0/0 })[math.random(1, 8)] end
        if k == 2 then return setmetatable({ label = T_pick(WORDS) .. T_pick(WORDS) }, meta) end
        local parts = {}
        for i = 1, math.random(0, 4) do parts[i] = T_pick(WORDS) end
        if math.random(1, 3) == 1 then parts[#parts + 1] = tostring(math.random(1, 3000)) end
        return table.concat(parts, T_pick({ "", " ", "_", "/" }))
      end
      for trial = 1, 20000 do
        local text = rnd_text()
        local c0 = calls
        local okr, want = pcall(ref_classify_seq_role_text, text)
        local c1 = calls
        local okn, got = pcall(classify_seq_role_text, text)
        local e = (okr ~= okn) and ("error mismatch " .. tostring(want) .. " / " .. tostring(got))
          or ((c1 - c0) ~= (calls - c1) and "__tostring call count differs")
          or T_same(want, got, "role")
        if e then
          out[#out + 1] = ("trial %d (%q): %s"):format(trial, tostring(text), e)
          if #out > 10 then break end
        end
      end
      -- infer_seq_track_role is built on it.
      state.samples = {
        { path = "/lib/Kicks/BD 01.wav", name = "BD 01.wav", tags = { "Drum", "Kick" } },
        { path = "/lib/Loops/fx riser.wav", name = "Rise.wav" },
        { path = "/lib/x/y.wav", name = "y.wav", tags = "bad" },
      }
      rebuild_samples_path_index()
      for trial = 1, 3000 do
        local function maybe(v) if math.random(1, 3) > 1 then return v end end
        local slot = maybe({})
        if slot then
          slot.sample_tag = maybe(rnd_text())
          slot.sample_path = maybe(T_pick({ "/lib/Kicks/BD 01.wav", "/lib/Loops/fx riser.wav", "/lib/x/y.wav", "/none.wav" }))
          slot.sample_name = maybe(rnd_text())
          slot.name = maybe(rnd_text())
        end
        local e = T_same(ref_infer_seq_track_role(slot), infer_seq_track_role(slot), "infer")
        if e then
          out[#out + 1] = ("infer trial %d: %s"):format(trial, e)
          if #out > 10 then break end
        end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


# Previous seq_layering_rand_role / _rand_label / _build_pieces. They used
# file-local helpers of 28_drum_layering.lua: corner() is restated here on the
# reference normalizer; env_key and piece_end_at are taken from the module.
REF_LAYER_USERS = r'''
local function corner(slot, side_key, idx)
  ref_seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  return side and side.verts[idx], side
end
local env_key = seq_layer_corner_env_key
local piece_end_at
for i = 1, 255 do
  local n, v = debug.getupvalue(seq_layering_build_pieces, i)
  if n == nil then break end
  if n == "piece_end_at" then piece_end_at = v end
end
assert(env_key and piece_end_at, "module helpers not found")
function ref_seq_layering_rand_role(slot, side_key, idx)
  local v = corner(slot, side_key, idx)
  if v and v.rand and v.rand.role then
    return v.rand.role, true
  end
  return seq_layering_track_role(slot), false
end

function ref_seq_layering_rand_label(slot, side_key, idx)
  local v = corner(slot, side_key, idx)
  local labels = SEQ_ROLE_LABELS or {}
  local role, own = ref_seq_layering_rand_role(slot, side_key, idx)
  local bits = { role and (labels[role] or role) or "Any" }
  local tags = v and v.rand and v.rand.tags or {}
  if #tags > 0 then
    bits[#bits + 1] = table.concat(tags, ", ")
  end
  return table.concat(bits, " · "), own or #tags > 0
end

function ref_seq_layering_build_pieces(slot, opts)
  ref_seq_normalize_slot_layers(slot)
  opts = opts or {}
  if not opts.all and not ref_seq_layering_geometry_active(slot) then
    return {}
  end
  local pieces = {}
  local function add(path, v, weight, fields, owners)
    local p = {
      path = path,
      sample = find_sample_by_path(path) or { path = path, name = v and v.name },
      weight = weight,
      startoffs = 0.0,
      time_offset_sec = 0.0,
      length_sec = nil,
      fade_in = 0.0,
      fade_out = 0.0,
      owners = owners,
    }
    for k, val in pairs(fields or {}) do p[k] = val end
    pieces[#pieces + 1] = p
    return p
  end

  if slot.layers.linked then
    local side = slot.layers.transient
    for i = 1, 3 do
      local v, w = side.verts[i], side.blend[i] or 0.0
      local path = (w >= 0.02 and v and v.path) and normalize_path(v.path) or nil
      if path then
        add(path, v, w * seq_layer_vert_vol(v) * side.gain, { lane = i - 1 },
          { { side = "transient", idx = i }, { side = "sustain", idx = i } })
      end
    end
  else
    local tside = slot.layers.transient
    local sside = slot.layers.sustain
    local split = seq_layering_split_sec(slot)
    local pre, post = seq_layering_xfade_window(slot, split)
    for i = 1, 3 do
      local tv, tw = tside.verts[i], tside.blend[i] or 0.0
      local sv, sw = sside.verts[i], sside.blend[i] or 0.0
      local tpath = (tw >= 0.02 and tv and tv.path) and normalize_path(tv.path) or nil
      local spath = (sw >= 0.02 and sv and sv.path) and normalize_path(sv.path) or nil
      local tgain = tw * seq_layer_vert_vol(tv) * tside.gain
      local sgain = sw * seq_layer_vert_vol(sv) * sside.gain
      if tpath and spath and tpath == spath and math.abs(tgain - sgain) < 0.05
          and tv.len == sv.len and tv.fade == sv.fade and env_key(tv) == env_key(sv) then
        -- Same sample at the same level on both sides: play it whole.
        add(tpath, tv, (tgain + sgain) * 0.5, { lane = i - 1 },
          { { side = "transient", idx = i }, { side = "sustain", idx = i } })
      else
        if tpath then
          local sample = find_sample_by_path(tpath) or { path = tpath, name = tv and tv.name }
          local offs = seq_layering_piece_times(sample, "transient", slot)
          add(tpath, tv, tgain, {
            sample = sample,
            lane = i - 1,
            startoffs = offs or 0.0,
            length_sec = split + post,
            fade_out = pre + post,
          }, { { side = "transient", idx = i } })
        end
        if spath then
          local sample = find_sample_by_path(spath) or { path = spath, name = sv and sv.name }
          local offs, slen = seq_layering_piece_times(sample, "sustain", slot)
          offs = offs or 0.0
          -- Start early by the fade's lead-in (as far as the sample allows).
          local lead = math.min(pre, offs)
          add(spath, sv, sgain, {
            sample = sample,
            lane = i - 1,
            startoffs = offs - lead,
            time_offset_sec = split - lead,
            length_sec = slen + lead,
            fade_in = lead + post,
          }, { { side = "sustain", idx = i } })
        end
      end
    end
  end

  -- Corner lengths / fades, then the whole-hit tail.
  local layers = slot.layers
  local tail_on = not opts.no_tail and (layers.tail_end or layers.tail_fade)
  local natural_end = nil
  if tail_on and not layers.tail_end then
    natural_end = seq_layering_natural_end(slot)
  end
  local kept = {}
  for _, p in ipairs(pieces) do
    local o = p.owners[#p.owners]
    local cv = layers[p.owners[1].side].verts[p.owners[1].idx]
    p.env = seq_layer_corner_env(cv)
    if p.env and not opts.no_corner_cut then
      -- Silence after the envelope's end: the piece stops there.
      local e = seq_layering_env_edges(p.env)
      if e and e.end_t then
        local _, _, startoffs, t_off = seq_layering_piece_span(p)
        piece_end_at(p, t_off + math.max(0.001, e.end_t - startoffs), nil)
      end
    end
    if not opts.no_corner_cut then
      local v = layers[o.side].verts[o.idx]
      if v.len or v.fade then
        local _, _, _, t_off, len = seq_layering_piece_span(p)
        local end_t = v.len or (t_off + len)
        piece_end_at(p, v.len, v.fade and (math.min(end_t, t_off + len) - v.fade) or nil)
      end
    end
    local keep = true
    if tail_on then
      local _, _, _, t_off, len = seq_layering_piece_span(p)
      local end_t = layers.tail_end or natural_end or (t_off + len)
      if t_off >= end_t - 0.0005 then
        keep = false
      else
        piece_end_at(p, layers.tail_end, layers.tail_fade and (end_t - layers.tail_fade) or nil)
      end
    end
    if keep then kept[#kept + 1] = p end
  end
  return seq_layering_remap_piece_lanes(kept)
end

'''


def test_layer_repeat_normalize_lemma():
    # layers_renormalize_repeat must do exactly what a second
    # seq_normalize_slot_layers does right after a first one.
    L = _runtime()
    L.execute(REF_LAYERS)
    L.execute(GEN_LAYERS)
    bad = L.execute(r'''
      math.randomseed(43)
      local repeat_fn
      for i = 1, 255 do
        local n, v = debug.getupvalue(seq_layering_is_active, i)
        if n == nil then break end
        if n == "layers_renormalize_repeat" then repeat_fn = v end
      end
      assert(repeat_fn, "layers_renormalize_repeat not found")
      local out = {}
      for trial = 1, 6000 do
        local a = T_rnd_slot()
        local b = T_deep_copy(a)
        local ok_a = pcall(ref_seq_normalize_slot_layers, a)
        local ok_b = pcall(ref_seq_normalize_slot_layers, b)
        if ok_a and ok_b then
          for rep = 1, math.random(1, 3) do
            ref_seq_normalize_slot_layers(a)
            repeat_fn(b.layers)
          end
          local e = T_same(a, b, "slot")
          if e then
            out[#out + 1] = ("trial %d: %s"):format(trial, e)
            if #out > 10 then break end
          end
        elseif ok_a ~= ok_b then
          out[#out + 1] = ("trial %d: error mismatch"):format(trial)
        end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""


def test_layer_users_match_previous_implementation():
    L = _runtime()
    L.execute(REF_LAYERS)
    L.execute(GEN_LAYERS)
    L.execute(REF_LAYER_USERS)
    bad = L.execute(r'''
      math.randomseed(47)
      local out = {}
      local SIDES = { "transient", "sustain", "unlinked_sustain", "nope" }
      local fns = {
        { "rand_role", function(s, k, i) return seq_layering_rand_role(s, k, i) end,
          function(s, k, i) return ref_seq_layering_rand_role(s, k, i) end },
        { "rand_label", function(s, k, i) return seq_layering_rand_label(s, k, i) end,
          function(s, k, i) return ref_seq_layering_rand_label(s, k, i) end },
        { "build_pieces", function(s, k, i, o) return seq_layering_build_pieces(s, o) end,
          function(s, k, i, o) return ref_seq_layering_build_pieces(s, o) end },
      }
      local OPTS = { false, {}, { all = true }, { no_tail = true }, { no_corner_cut = true }, { all = true, no_tail = true } }
      for trial = 1, 3000 do
        local seed_slot = T_rnd_slot()
        if math.random(1, 3) == 1 and type(seed_slot.layers) == "table" then
          -- Some corners with their own drum type.
          local side = seed_slot.layers.transient
          if type(side) == "table" and type(side.verts) == "table" and type(side.verts[2]) == "table" then
            side.verts[2].rand = { role = T_pick({ "clap", "hat" }), tags = T_pick({ {}, { "dry" } }) }
          end
        end
        local side_key = T_pick(SIDES)
        local idx = T_pick({ 1, 2, 3, 4 })
        local opts = T_pick(OPTS) or nil
        for _, f in ipairs(fns) do
          local a, b = T_deep_copy(seed_slot), T_deep_copy(seed_slot)
          local okn, n1, n2 = pcall(f[2], a, side_key, idx, opts)
          local okr, r1, r2 = pcall(f[3], b, side_key, idx, opts)
          local e = (okn ~= okr) and ("error mismatch " .. tostring(n1) .. " / " .. tostring(r1))
            or T_same({ r1, r2 }, { n1, n2 }, "ret") or T_same(b, a, "slot")
          if e then
            out[#out + 1] = ("%s trial %d (%s %s): %s"):format(f[1], trial, tostring(side_key), tostring(idx), e)
            if #out > 10 then return table.concat(out, "\n") end
          end
        end
      end
      return table.concat(out, "\n")
    ''')
    assert bad == ""

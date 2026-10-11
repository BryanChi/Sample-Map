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

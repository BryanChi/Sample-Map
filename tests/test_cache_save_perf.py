"""The library cache writers (browser/03_json.lua) were sped up for save_samples.

Their output must stay byte-for-byte what the original code wrote. REF_LUA below is
the original code, verbatim apart from REF_ names; each test feeds the same values
to both versions in one Lua state (so map iteration order is shared) and compares.
"""
import os

from lupa import lua54

ROOT = os.path.join(os.path.dirname(__file__), "..")

REF_LUA = r'''
function REF_lua_is_array(t)
  local n = #t
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
      return false
    end
  end
  return true
end

function REF_serialize_lua_value(val, out)
  local tv = type(val)
  if tv == "nil" then
    out[#out + 1] = "nil"
  elseif tv == "boolean" then
    out[#out + 1] = val and "true" or "false"
  elseif tv == "number" then
    if val ~= val then
      out[#out + 1] = "0"
    elseif val == math.huge then
      out[#out + 1] = "math.huge"
    elseif val == -math.huge then
      out[#out + 1] = "-math.huge"
    elseif val == math.floor(val) and math.abs(val) < 9007199254740992 then
      out[#out + 1] = string.format("%d", val)
    elseif math.abs(val) < 1000000 then
      out[#out + 1] = string.format("%.6g", val)
    else
      out[#out + 1] = string.format("%.17g", val)
    end
  elseif tv == "string" then
    out[#out + 1] = string.format("%q", val)
  elseif tv == "table" then
    out[#out + 1] = "{"
    if REF_lua_is_array(val) then
      for i = 1, #val do
        if i > 1 then out[#out + 1] = "," end
        REF_serialize_lua_value(val[i], out)
      end
    else
      local first = true
      for k, v in pairs(val) do
        if not first then out[#out + 1] = "," end
        first = false
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          out[#out + 1] = k
          out[#out + 1] = "="
        else
          out[#out + 1] = "["
          REF_serialize_lua_value(k, out)
          out[#out + 1] = "]="
        end
        REF_serialize_lua_value(v, out)
      end
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function REF_encode_lua_cache(payload)
  local out = {"return "}
  REF_serialize_lua_value(payload, out)
  out[#out + 1] = "\n"
  return table.concat(out)
end

function REF_round(n, places)
  if type(n) ~= "number" or n ~= n then
    return nil
  end
  if n == math.huge or n == -math.huge then
    return nil
  end
  local f = 10 ^ (places or 5)
  return math.floor(n * f + (n >= 0 and 0.5 or -0.5)) / f
end

function REF_split_dir_name(path)
  path = normalize_path(path or "")
  if path == "" then
    return "", ""
  end
  local name = path:match("([^/]+)$") or path
  local dir = path:match("(.+)/[^/]+$") or ""
  return dir, name
end

function REF_compact_sample(sample, intern_dir, intern_tag)
  if type(sample) ~= "table" then
    return nil
  end
  local path = sample.path or SampleCacheCodec.join_dir_name(sample.folder, sample.name)
  local dir, name = REF_split_dir_name(path)
  if name == "" then
    return nil
  end
  local tag_idxs = {}
  if type(sample.tags) == "table" then
    for i = 1, #sample.tags do
      local tag = sample.tags[i]
      if tag and tag ~= "" then
        tag_idxs[#tag_idxs + 1] = intern_tag(tag)
      end
    end
  end
  local pt = false
  if sample.playback_type ~= nil then
    pt = SampleCacheCodec.PT[sample.playback_type] or 0
  end
  local extra
  if sample.sample_type ~= nil or sample.snap_offset ~= nil
      or sample.start_pos ~= nil or sample.gain ~= nil
      or sample.brightness ~= nil or sample.sub_weight ~= nil
      or sample.mtime ~= nil or sample.file_id_size ~= nil then
    extra = {}
    if sample.sample_type ~= nil then extra.st = sample.sample_type end
    if type(sample.snap_offset) == "number" then extra.so = REF_round(sample.snap_offset, 5) end
    if type(sample.start_pos) == "number" then extra.sp = REF_round(sample.start_pos, 5) end
    if type(sample.gain) == "number" then extra.g = REF_round(sample.gain, 5) end
    if type(sample.brightness) == "number" then extra.br = REF_round(sample.brightness, 2) end
    if type(sample.sub_weight) == "number" then extra.sw = REF_round(sample.sub_weight, 5) end
    if sample.mtime ~= nil and tostring(sample.mtime) ~= "" then
      extra.mt = tostring(sample.mtime)
    end
    if type(sample.file_id_size) == "number" then
      extra.fs = math.floor(sample.file_id_size + 0.5)
    end
  end
  local row = {
    intern_dir(dir),
    name,
    tag_idxs,
    REF_round(sample.x or 0.5, 5) or 0.5,
    REF_round(sample.y or 0.5, 5) or 0.5,
    REF_round(sample.duration, 5) or false,
    REF_round(sample.effective_duration, 5) or false,
    sample.channels or false,
    REF_round(sample.rms_energy, 5) or false,
    REF_round(sample.dominant_freq, 2) or false,
    pt,
    (type(sample.bps) == "number" and math.floor(sample.bps + 0.5)) or false,
    REF_round(sample.onset, 5) or false,
    REF_round(sample.transient_end, 5) or false,
    extra or false,
  }
  while #row > 6 and row[#row] == false do
    row[#row] = nil
  end
  return row
end

function REF_encode_row_json(row)
  local parts = {}
  for i = 1, #row do
    local v = row[i]
    local tv = type(v)
    if tv == "number" then
      if v == math.floor(v) and math.abs(v) < 1e15 then
        parts[i] = string.format("%d", v)
      else
        parts[i] = string.format("%.5f", v):gsub("(%..-)0+$", "%1"):gsub("%.$", "")
      end
    elseif tv == "string" then
      parts[i] = json_encode_string(v)
    elseif tv == "boolean" then
      parts[i] = v and "true" or "false"
    elseif tv == "table" then
      parts[i] = json_encode(v)
    else
      parts[i] = "false"
    end
  end
  return "[" .. table.concat(parts, ",") .. "]"
end
'''

FUZZ_HELPERS = r'''
R = math.random
local NUMS = { 0, -0.0, 1, -1, 0.5, -0.5, 1e-300, 5e-324, 1e15, 1e15 - 1, -1e15, 1e15 + 0.5,
  2^53, 2^53 - 1, -2^53, 2^63, 1e300, -1e300, 999999.5, 1000000, 999999.999995, 0.000005,
  -0.000004, 0.1, 0.123455, 123.45, 1234.5678, 0/0, -(0/0), math.huge, -math.huge,
  math.maxinteger, math.mininteger, 3, 2.0, -7.0, 1e-5, 9.999995, 99999.995 }
function rand_number()
  local k = R(1, 9)
  if k == 1 then return NUMS[R(1, #NUMS)] end
  if k == 2 then return R(-100000, 100000) end
  if k == 3 then return R(-100000, 100000) / 100000 end
  if k == 4 then return math.floor(R() * 1e5 + 0.5) / 1e5 end
  if k == 5 then return math.floor(R() * 1e7 + 0.5) / 100 end
  if k == 6 then return (R() - 0.5) * 10 ^ R(-12, 20) end
  if k == 7 then return R(-5, 5) + 0.0 end
  if k == 8 then return R(0, 999999) / 10 ^ R(0, 9) end
  return R()
end
local CHARS = { "a", "Z", "_", "9", ".", ",", "0", "]", "[", "/", "\\", '"', "\n", "\r", "\0", "\t", " ", "é", "%", "=", "-", "e" }
function rand_string(maxlen)
  local n = R(0, maxlen or 8)
  local p = {}
  for i = 1, n do p[i] = CHARS[R(1, #CHARS)] end
  if R(1, 6) == 1 then return ({ "end", "and", "x1", "_", "1abc", "a.000,b", "0.50000,", "", "nil" })[R(1, 9)] end
  return table.concat(p)
end
function rand_scalar()
  local k = R(1, 10)
  if k <= 5 then return rand_number() end
  if k <= 7 then return rand_string() end
  if k == 8 then return R(1, 2) == 1 end
  if k == 9 then return print end
  return nil
end
function rand_value(depth)
  if depth <= 0 or R(1, 3) > 1 then return rand_scalar() end
  local t = {}
  local kind = R(1, 4)
  if kind == 1 then
    for i = 1, R(0, 16) do t[i] = rand_value(depth - 1) end
  elseif kind == 2 then
    for i = 1, R(0, 16) do t[i] = rand_scalar() end
    if R(1, 2) == 1 then t[R(1, 20)] = rand_value(depth - 1) end
  elseif kind == 3 then
    for i = 1, R(0, 8) do
      local key = R(1, 3) == 1 and rand_number() or rand_string()
      if key ~= nil and key == key then t[key] = rand_value(depth - 1) end
    end
  else
    for i = 1, R(0, 8) do t[i] = rand_scalar() end
    t[({ "st", "so", "br", "x", "end", "a b" })[R(1, 6)]] = rand_value(depth - 1)
  end
  return t
end
function serialize_both(v)
  local a, b = { "return " }, { "return " }
  REF_serialize_lua_value(v, a)
  serialize_lua_value(v, b)
  return table.concat(a), table.concat(b), #a == #a
end
function rand_sample(i)
  local tags = { "kick", "snare", "", "ünï", "tag with space", 'q"t' }
  local s = {
    path = R(1, 8) > 1 and ("/lib/pack" .. R(1, 40) .. "/" .. rand_string(6) .. "_" .. i .. ".wav") or nil,
    folder = ({ "/lib", "C:\\lib\\x\\", "", "/a//b/" })[R(1, 4)],
    name = rand_string(10) .. ".wav",
    tags = R(1, 6) > 1 and { tags[R(1, 6)], tags[R(1, 6)] } or nil,
  }
  local fields = { "x", "y", "duration", "effective_duration", "channels", "rms_energy", "dominant_freq",
    "bps", "onset", "transient_end", "snap_offset", "start_pos", "gain", "brightness", "sub_weight", "file_id_size" }
  for _, f in ipairs(fields) do
    if R(1, 4) > 1 then s[f] = R(1, 12) == 1 and rand_scalar() or rand_number() end
  end
  if R(1, 3) == 1 then s.playback_type = ({ "oneshot", "loop", "unknown", "weird", 5 })[R(1, 5)] end
  if R(1, 3) == 1 then s.sample_type = rand_scalar() end
  if R(1, 3) == 1 then s.mtime = R(1, 2) == 1 and tostring(1700000000 + i) or R(1, 1e6) end
  if R(1, 40) == 1 then s.path = ({ "", "/", "x", "/x.wav", "a/", "a\\b\\c.wav", "//x", "a//b" })[R(1, 8)] end
  return s
end
'''


def _runtime(seed):
    L = lua54.LuaRuntime(encoding=None)
    L.execute(b"reaper = setmetatable({}, {__index = function() return function() end end})")
    L.execute(b"log = function() end")
    for name in ("02_helpers.lua", "03_json.lua"):
        with open(os.path.join(ROOT, "browser", name), "rb") as fh:
            L.execute(fh.read())
    L.execute(REF_LUA.encode("utf-8"))
    L.execute(FUZZ_HELPERS.encode("utf-8"))
    L.execute(("math.randomseed(%d)" % seed).encode())
    return L


def test_lua_literals_match_original():
    L = _runtime(1)
    bad = L.execute(r"""
      local bad = 0
      for i = 1, 30000 do
        local v = rand_value(4)
        local a, b = serialize_both(v)
        if a ~= b then bad = bad + 1 end
        -- Appending into a buffer that already holds text, as the global API allows.
        local x, y = { "a", "b" }, { "a", "b" }
        REF_serialize_lua_value(v, x)
        serialize_lua_value(v, y)
        if table.concat(x) ~= table.concat(y) then bad = bad + 1 end
      end
      for i = 1, 2000 do
        local t = rand_value(1)
        if type(t) == "table" and REF_lua_is_array(t) ~= lua_is_array(t) then bad = bad + 1 end
      end
      return bad
    """.encode("utf-8"))
    assert bad == 0


def test_round_and_split_match_original():
    L = _runtime(2)
    bad = L.execute(r"""
      local bad = 0
      local function same(a, b)
        if a ~= a and b ~= b then return true end
        return a == b and math.type(a) == math.type(b)
      end
      for i = 1, 100000 do
        local v = R(1, 20) == 1 and rand_scalar() or rand_number()
        for _, p in ipairs({ 5, 2, nil, 3, 5.0, 0, "5" }) do
          if not same(REF_round(v, p), SampleCacheCodec.round(v, p)) then bad = bad + 1 end
        end
      end
      local paths = { "", "/", "//", "x", "/x", "x/", "/x/", "a/b", "a//b", "//a", "a\\b", "C:\\a\\b.wav",
        "/a/b/", "/a/b//", "a/b/c.wav", "/Volumes/D/x y/z.wav", "é/ü.wav", "a\0b/c" }
      for i = 1, 20000 do paths[#paths + 1] = rand_string(12) end
      for _, p in ipairs(paths) do
        local d1, n1 = REF_split_dir_name(p)
        local d2, n2 = SampleCacheCodec.split_dir_name(p)
        if d1 ~= d2 or n1 ~= n2 then bad = bad + 1 end
      end
      local d1, n1 = REF_split_dir_name(nil)
      local d2, n2 = SampleCacheCodec.split_dir_name(nil)
      if d1 ~= d2 or n1 ~= n2 then bad = bad + 1 end
      return bad
    """.encode("utf-8"))
    assert bad == 0


def test_rows_and_cache_files_match_original():
    L = _runtime(3)
    result = L.execute(r"""
      local codec = SampleCacheCodec
      local samples = {}
      for i = 1, 4000 do samples[i] = rand_sample(i) end
      local bad = 0
      local function eq(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then
          if a ~= a and b ~= b then return true end
          return a == b and math.type(a) == math.type(b)
        end
        for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
      end
      local d1, i1 = codec.interner(); local t1, it1 = codec.interner()
      local d2, i2 = codec.interner(); local t2, it2 = codec.interner()
      for i = 1, #samples do
        local a = REF_compact_sample(samples[i], i1, it1)
        local b = codec.compact_sample(samples[i], i2, it2)
        if not eq(a, b) then bad = bad + 1 end
      end
      if not eq(d1, d2) or not eq(t1, t2) then bad = bad + 1 end
      local state_tbl = { scan_queue = { "/a/b.wav", "" }, analyzer_queue = {}, analyzer_results = { ["/a.wav"] = { x = 0.25 } },
        analyzer_mode = "full", scan_total = 12, scan_started = 3.5, map_seed = 42 }
      local payload = codec.build_payload(state_tbl, { "/lib" }, samples)
      if REF_encode_lua_cache(payload) ~= encode_lua_cache(payload) then bad = bad + 1 end
      for i = 1, #payload.samples do
        local row = payload.samples[i]
        if REF_encode_row_json(row) ~= codec.encode_row_json(row) then bad = bad + 1 end
        local buf = { "x" }
        local n = codec.encode_row_json_into(row, buf, 1)
        if table.concat(buf, "", 1, n) ~= "x" .. REF_encode_row_json(row) then bad = bad + 1 end
      end
      for i = 1, 30000 do
        local row = {}
        for k = 1, R(0, 18) do
          local x = R(1, 10)
          if x <= 6 then row[k] = rand_number()
          elseif x == 7 then row[k] = rand_string()
          elseif x == 8 then row[k] = R(1, 2) == 1
          elseif x == 9 then row[k] = { R(1, 9), rand_number() }
          else row[k] = print end
        end
        if REF_encode_row_json(row) ~= codec.encode_row_json(row) then bad = bad + 1 end
      end
      return bad, #payload.samples
    """.encode("utf-8"))
    bad, rows = result
    assert rows > 3000
    assert bad == 0

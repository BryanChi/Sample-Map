-- Sample Map Browser module: json
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- JSON helpers (improved) ----------------------------------------------------
SM_JSON_ESCAPE_MAP = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
for code = 0, 31 do
  local ch = string.char(code)
  if not SM_JSON_ESCAPE_MAP[ch] then
    SM_JSON_ESCAPE_MAP[ch] = string.format("\\u%04x", code)
  end
end

function json_encode_string(s)
  -- Escape quotes, backslashes and every control character.
  return '"' .. s:gsub('[%z\1-\31"\\]', SM_JSON_ESCAPE_MAP) .. '"'
end

-- Encoded object keys ('"key":'), reused across calls; step keys and field
-- names repeat on every save.
SM_JSON_KEY_CACHE = {}
SM_JSON_KEY_CACHE_N = 0

local function json_key(k)
  local cached = SM_JSON_KEY_CACHE[k]
  if cached then
    return cached
  end
  local s = tostring(k)
  if s:find('[%z\1-\31"\\]') then
    cached = json_encode_string(s) .. ":"
  else
    cached = '"' .. s .. '":'
  end
  if SM_JSON_KEY_CACHE_N >= 8192 then
    SM_JSON_KEY_CACHE = {}
    SM_JSON_KEY_CACHE_N = 0
  end
  SM_JSON_KEY_CACHE[k] = cached
  SM_JSON_KEY_CACHE_N = SM_JSON_KEY_CACHE_N + 1
  return cached
end

-- Appends val's JSON to buf after index n; returns the new last index.
local function json_encode_into(val, buf, n)
  local t = type(val)
  if t == "table" then
    local is_array = true
    local max_idx = 0
    for k in pairs(val) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      if k > max_idx then
        max_idx = k
      end
    end
    if is_array then
      n = n + 1
      buf[n] = "["
      for i = 1, max_idx do
        if i > 1 then
          n = n + 1
          buf[n] = ","
        end
        n = json_encode_into(val[i], buf, n)
      end
      n = n + 1
      buf[n] = "]"
    else
      n = n + 1
      buf[n] = "{"
      local first = true
      for k, v in pairs(val) do
        if first then
          first = false
        else
          n = n + 1
          buf[n] = ","
        end
        n = n + 1
        buf[n] = json_key(k)
        n = json_encode_into(v, buf, n)
      end
      n = n + 1
      buf[n] = "}"
    end
  elseif t == "string" then
    n = n + 1
    if val:find('[%z\1-\31"\\]') then
      buf[n] = json_encode_string(val)
    else
      buf[n] = '"' .. val .. '"'
    end
  elseif t == "number" then
    n = n + 1
    if val ~= val or val == math.huge or val == -math.huge then
      buf[n] = "null"
    else
      buf[n] = tostring(val)
    end
  elseif t == "boolean" then
    n = n + 1
    buf[n] = val and "true" or "false"
  else
    n = n + 1
    buf[n] = "null"
  end
  return n
end

function json_encode(val)
  local buf = {}
  local n = json_encode_into(val, buf, 0)
  return table.concat(buf, "", 1, n)
end


function json_decode(str)
  -- Single-pass recursive-descent JSON decoder.
  -- Returns the decoded value, or nil, err on malformed/truncated input.
  -- `null` decodes to nil; arrays keep the positions of later elements.
  if type(str) ~= "string" then
    return nil, "json_decode: expected string, got " .. type(str)
  end
  local byte, sub, find = string.byte, string.sub, string.find
  local len = #str
  local pos = 1
  local escapes = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t" }

  local function fail(msg)
    error({ json_decode_error = string.format("%s at position %d", msg, pos) }, 0)
  end

  local function skip_ws()
    pos = find(str, "[^ \t\r\n]", pos) or (len + 1)
  end

  local function parse_string()
    -- pos is on the opening quote
    local i = pos + 1
    local parts, n = nil, 0
    while true do
      local j = find(str, '["\\]', i)
      if not j then
        pos = len + 1
        fail("unterminated string")
      end
      if byte(str, j) == 34 then
        pos = j + 1
        if parts then
          n = n + 1
          parts[n] = sub(str, i, j - 1)
          return table.concat(parts, "", 1, n)
        end
        return sub(str, i, j - 1)
      end
      parts = parts or {}
      n = n + 1
      parts[n] = sub(str, i, j - 1)
      local e = byte(str, j + 1)
      if e == 117 then -- \uXXXX
        local hex = sub(str, j + 2, j + 5)
        if not find(hex, "^%x%x%x%x$") then
          pos = j
          fail("invalid \\u escape")
        end
        local cp = tonumber(hex, 16)
        local next_i = j + 6
        if cp >= 0xD800 and cp <= 0xDBFF and sub(str, next_i, next_i + 1) == "\\u" then
          local hex2 = sub(str, next_i + 2, next_i + 5)
          local lo = find(hex2, "^%x%x%x%x$") and tonumber(hex2, 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            next_i = next_i + 6
          end
        end
        n = n + 1
        parts[n] = utf8.char(cp)
        i = next_i
      else
        local rep = e and escapes[e]
        if not rep then
          pos = j
          fail(e and "invalid escape" or "unterminated string")
        end
        n = n + 1
        parts[n] = rep
        i = j + 2
      end
    end
  end

  local parse_value

  local function parse_array()
    pos = pos + 1
    local arr, n = {}, 0
    skip_ws()
    if byte(str, pos) == 93 then
      pos = pos + 1
      return arr
    end
    while true do
      n = n + 1
      arr[n] = parse_value()
      skip_ws()
      local b = byte(str, pos)
      if b == 44 then
        pos = pos + 1
      elseif b == 93 then
        pos = pos + 1
        return arr
      else
        fail(b and "expected ',' or ']'" or "unexpected end of input in array")
      end
    end
  end

  local function parse_object()
    pos = pos + 1
    local obj = {}
    skip_ws()
    if byte(str, pos) == 125 then
      pos = pos + 1
      return obj
    end
    while true do
      skip_ws()
      if byte(str, pos) ~= 34 then
        fail(pos > len and "unexpected end of input in object" or "expected string key")
      end
      local key = parse_string()
      skip_ws()
      if byte(str, pos) ~= 58 then
        fail("expected ':'")
      end
      pos = pos + 1
      obj[key] = parse_value()
      skip_ws()
      local b = byte(str, pos)
      if b == 44 then
        pos = pos + 1
      elseif b == 125 then
        pos = pos + 1
        return obj
      else
        fail(b and "expected ',' or '}'" or "unexpected end of input in object")
      end
    end
  end

  -- Non-finite numbers written by older versions (tostring: nan, -nan(ind), inf)
  -- or by Python (NaN, Infinity) decode as nil, like a null.
  local NONFINITE = { "-Infinity", "Infinity", "NaN", "-nan", "nan", "-inf", "inf" }
  local function parse_nonfinite()
    for _, lit in ipairs(NONFINITE) do
      if sub(str, pos, pos + #lit - 1) == lit then
        pos = pos + #lit
        local _, e = find(str, "^%(%a*%)", pos)
        if e then pos = e + 1 end
        return true
      end
    end
    return false
  end

  parse_value = function()
    skip_ws()
    local b = byte(str, pos)
    if (b == 45 or b == 73 or b == 78 or b == 105 or b == 110) and parse_nonfinite() then
      return nil
    end
    if b == 123 then
      return parse_object()
    elseif b == 91 then
      return parse_array()
    elseif b == 34 then
      return parse_string()
    elseif b == 116 then
      if sub(str, pos, pos + 3) ~= "true" then fail("invalid literal") end
      pos = pos + 4
      return true
    elseif b == 102 then
      if sub(str, pos, pos + 4) ~= "false" then fail("invalid literal") end
      pos = pos + 5
      return false
    elseif b == 110 then
      if sub(str, pos, pos + 3) ~= "null" then fail("invalid literal") end
      pos = pos + 4
      return nil
    elseif b == 45 or (b and b >= 48 and b <= 57) then
      local s, e = find(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      local num = s and tonumber(sub(str, s, e))
      if not num then fail("invalid number") end
      pos = e + 1
      return num
    elseif not b then
      fail("unexpected end of input")
    end
    fail("unexpected character '" .. string.char(b) .. "'")
  end

  local ok, result = pcall(function()
    local value = parse_value()
    skip_ws()
    if pos <= len then
      fail("trailing characters")
    end
    return value
  end)
  if ok then
    return result
  end
  if type(result) == "table" and result.json_decode_error then
    return nil, result.json_decode_error
  end
  return nil, tostring(result)
end


-- Compact Lua value serializer for SampleMapData.cache.lua (loadfile-friendly).
function lua_is_array(t)
  local n = #t
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
      return false
    end
  end
  return true
end

function serialize_lua_value(val, out)
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
    if lua_is_array(val) then
      for i = 1, #val do
        if i > 1 then out[#out + 1] = "," end
        serialize_lua_value(val[i], out)
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
          serialize_lua_value(k, out)
          out[#out + 1] = "]="
        end
        serialize_lua_value(v, out)
      end
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function encode_lua_cache(payload)
  local out = {"return "}
  serialize_lua_value(payload, out)
  out[#out + 1] = "\n"
  return table.concat(out)
end

-- Compact on-disk sample cache (v2).
-- Dirs and tags are interned once; each sample is a short array:
-- [dir_idx, name, tag_idxs, x, y, dur, ed, ch, rms, freq, pt, bps, onset, te, extra]
-- In-memory samples stay as full {path, folder, name, ...} tables.
SampleCacheCodec = {
  VERSION = 2,
  PT = { oneshot = 1, loop = 2, unknown = 0 },
  PT_NAME = { [0] = "unknown", [1] = "oneshot", [2] = "loop" },
}

function SampleCacheCodec.round(n, places)
  if type(n) ~= "number" or n ~= n then
    return nil
  end
  if n == math.huge or n == -math.huge then
    return nil
  end
  local f = 10 ^ (places or 5)
  return math.floor(n * f + (n >= 0 and 0.5 or -0.5)) / f
end

function SampleCacheCodec.split_dir_name(path)
  path = normalize_path(path or "")
  if path == "" then
    return "", ""
  end
  local name = path:match("([^/]+)$") or path
  local dir = path:match("(.+)/[^/]+$") or ""
  return dir, name
end

function SampleCacheCodec.join_dir_name(dir, name)
  name = name or ""
  if not dir or dir == "" then
    return name
  end
  if name == "" then
    return dir
  end
  return dir .. "/" .. name
end

function SampleCacheCodec.interner()
  local list, index = {}, {}
  local function intern(s)
    if s == nil then
      return 0
    end
    s = tostring(s)
    local i = index[s]
    if i then
      return i
    end
    i = #list + 1
    list[i] = s
    index[s] = i
    return i
  end
  return list, intern
end

function SampleCacheCodec.compact_sample(sample, intern_dir, intern_tag)
  if type(sample) ~= "table" then
    return nil
  end
  local path = sample.path or SampleCacheCodec.join_dir_name(sample.folder, sample.name)
  local dir, name = SampleCacheCodec.split_dir_name(path)
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
    if type(sample.snap_offset) == "number" then extra.so = SampleCacheCodec.round(sample.snap_offset, 5) end
    if type(sample.start_pos) == "number" then extra.sp = SampleCacheCodec.round(sample.start_pos, 5) end
    if type(sample.gain) == "number" then extra.g = SampleCacheCodec.round(sample.gain, 5) end
    if type(sample.brightness) == "number" then extra.br = SampleCacheCodec.round(sample.brightness, 2) end
    if type(sample.sub_weight) == "number" then extra.sw = SampleCacheCodec.round(sample.sub_weight, 5) end
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
    SampleCacheCodec.round(sample.x or 0.5, 5) or 0.5,
    SampleCacheCodec.round(sample.y or 0.5, 5) or 0.5,
    SampleCacheCodec.round(sample.duration, 5) or false,
    SampleCacheCodec.round(sample.effective_duration, 5) or false,
    sample.channels or false,
    SampleCacheCodec.round(sample.rms_energy, 5) or false,
    SampleCacheCodec.round(sample.dominant_freq, 2) or false,
    pt,
    (type(sample.bps) == "number" and math.floor(sample.bps + 0.5)) or false,
    SampleCacheCodec.round(sample.onset, 5) or false,
    SampleCacheCodec.round(sample.transient_end, 5) or false,
    extra or false,
  }
  while #row > 6 and row[#row] == false do
    row[#row] = nil
  end
  return row
end

function SampleCacheCodec.expand_sample(row, dirs, tag_dict)
  if type(row) ~= "table" then
    return nil
  end
  if type(row.path) == "string" and row.path ~= "" then
    return row
  end
  local dir_idx, name = row[1], row[2]
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local dir = ""
  if type(dir_idx) == "number" and dirs then
    dir = dirs[dir_idx] or ""
  end
  local path = SampleCacheCodec.join_dir_name(dir, name)
  local tags = {}
  local tag_idxs = row[3]
  if type(tag_idxs) == "table" and tag_dict then
    for i = 1, #tag_idxs do
      local tag = tag_dict[tag_idxs[i]]
      if tag and tag ~= "" then
        tags[#tags + 1] = tag
      end
    end
  end
  local function num(v)
    if type(v) == "number" then return v end
    return nil
  end
  local pt = row[11]
  local playback_type = nil
  if type(pt) == "number" then
    playback_type = SampleCacheCodec.PT_NAME[pt] or "unknown"
  end
  local extra = row[15]
  local sample = {
    path = path,
    name = name,
    folder = dir,
    tags = tags,
    x = num(row[4]) or 0.5,
    y = num(row[5]) or 0.5,
    duration = num(row[6]),
    effective_duration = num(row[7]),
    channels = num(row[8]),
    rms_energy = num(row[9]),
    dominant_freq = num(row[10]),
    playback_type = playback_type,
    bps = num(row[12]),
    onset = num(row[13]),
    transient_end = num(row[14]),
  }
  if type(extra) == "table" then
    if extra.st ~= nil then sample.sample_type = extra.st end
    if type(extra.so) == "number" then sample.snap_offset = extra.so end
    if type(extra.sp) == "number" then sample.start_pos = extra.sp end
    if type(extra.g) == "number" then sample.gain = extra.g end
    if type(extra.br) == "number" then sample.brightness = extra.br end
    if type(extra.sw) == "number" then sample.sub_weight = extra.sw end
    if extra.mt ~= nil then sample.mtime = tostring(extra.mt) end
    if type(extra.fs) == "number" then
      sample.file_id_size = extra.fs
      sample.file_size = extra.fs
    end
  end
  return sample
end

function SampleCacheCodec.compact_path(path, intern_dir)
  local dir, name = SampleCacheCodec.split_dir_name(path)
  if name == "" then
    return nil
  end
  return { intern_dir(dir), name }
end

function SampleCacheCodec.expand_path(ref, dirs)
  if type(ref) == "string" then
    return normalize_path(ref)
  end
  if type(ref) ~= "table" then
    return nil
  end
  local dir = ""
  if type(ref[1]) == "number" and dirs then
    dir = dirs[ref[1]] or ""
  end
  local name = ref[2]
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return SampleCacheCodec.join_dir_name(dir, name)
end

function SampleCacheCodec.compact_path_list(list, intern_dir)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  for i = 1, #list do
    local ref = SampleCacheCodec.compact_path(list[i], intern_dir)
    if ref then
      out[#out + 1] = ref
    end
  end
  return out
end

function SampleCacheCodec.expand_path_list(list, dirs)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  for i = 1, #list do
    local path = SampleCacheCodec.expand_path(list[i], dirs)
    if path and path ~= "" then
      out[#out + 1] = path
    end
  end
  return out
end

function SampleCacheCodec.build_payload(state_tbl, folders, samples)
  local dirs, intern_dir = SampleCacheCodec.interner()
  local tag_dict, intern_tag = SampleCacheCodec.interner()
  local compact_samples = {}
  for i = 1, #samples do
    local row = SampleCacheCodec.compact_sample(samples[i], intern_dir, intern_tag)
    if row then
      compact_samples[#compact_samples + 1] = row
    end
  end
  return {
    v = SampleCacheCodec.VERSION,
    tag_schema_version = TAG_SCHEMA_VERSION,
    folders = folders,
    dirs = dirs,
    tag_dict = tag_dict,
    map_seed = state_tbl.map_seed,
    samples = compact_samples,
    scan_queue = SampleCacheCodec.compact_path_list(state_tbl.scan_queue, intern_dir),
    scan_total = state_tbl.scan_total,
    scan_started = state_tbl.scan_started,
    analyzer_queue = SampleCacheCodec.compact_path_list(state_tbl.analyzer_queue, intern_dir),
    analyzer_pending = state_tbl.active_processes and #state_tbl.active_processes > 0,
    analyzer_results = state_tbl.analyzer_results,
    analyzer_mode = state_tbl.analyzer_mode,
  }
end

function SampleCacheCodec.extract_json_array(content, key)
  if type(content) ~= "string" or not key then
    return nil
  end
  local key_pos = content:find('"' .. key .. '"%s*:', 1)
  if not key_pos then
    return nil
  end
  local colon = content:find(":", key_pos, true)
  if not colon then
    return nil
  end
  local i = colon + 1
  local n = #content
  local byte = string.byte
  while i <= n do
    local b = byte(content, i)
    if b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 then
      break
    end
    i = i + 1
  end
  if byte(content, i) ~= 91 then
    return nil
  end
  local start = i
  local depth = 1
  i = i + 1
  local in_str, esc = false, false
  while i <= n and depth > 0 do
    local ch = byte(content, i)
    if in_str then
      if esc then
        esc = false
      elseif ch == 92 then
        esc = true
      elseif ch == 34 then
        in_str = false
      end
    else
      if ch == 34 then
        in_str = true
      elseif ch == 91 then
        depth = depth + 1
      elseif ch == 93 then
        depth = depth - 1
      end
    end
    i = i + 1
  end
  return content:sub(start, i - 1)
end

function SampleCacheCodec.encode_row_json(row)
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

-- Fast path for SampleMapData.json: decode each sample object individually instead of
-- handing the entire multi‑MB samples array to the recursive json_decode.
function json_decode_sample_cache(content)
  if type(content) ~= "string" or content == "" then
    return nil
  end
  local data = {}

  local folders_json = SampleCacheCodec.extract_json_array(content, "folders")
  if folders_json then
    local ok, folders = pcall(json_decode, folders_json)
    if ok and type(folders) == "table" then
      data.folders = folders
    end
  end

  local map_seed = content:match('"map_seed"%s*:%s*([%-%d%.eE+]+)')
  if map_seed then
    data.map_seed = tonumber(map_seed)
  end

  local schema = content:match('"tag_schema_version"%s*:%s*([%-%d]+)')
  if schema then
    data.tag_schema_version = tonumber(schema)
  end

  local cache_v = content:match('"v"%s*:%s*([%-%d]+)')
  if cache_v then
    data.v = tonumber(cache_v)
  end

  local scan_total = content:match('"scan_total"%s*:%s*([%-%d%.eE+]+)')
  if scan_total then
    data.scan_total = tonumber(scan_total)
  end

  local scan_started = content:match('"scan_started"%s*:%s*([%-%d%.eE+]+)')
  if scan_started then
    data.scan_started = tonumber(scan_started)
  end

  local pending = content:match('"analyzer_pending"%s*:%s*(true|false)')
  if pending == "true" then
    data.analyzer_pending = true
  elseif pending == "false" then
    data.analyzer_pending = false
  end

  local function decode_field_array(key)
    local json = SampleCacheCodec.extract_json_array(content, key)
    if not json then return nil end
    local ok, decoded = pcall(json_decode, json)
    if ok and type(decoded) == "table" then
      return decoded
    end
    return nil
  end

  local function decode_field_object(key)
    local pattern = '"' .. key .. '"%s*:%s*(%b{})'
    local json = content:match(pattern)
    if not json then return nil end
    local ok, decoded = pcall(json_decode, json)
    if ok and type(decoded) == "table" then
      return decoded
    end
    return nil
  end

  data.dirs = decode_field_array("dirs") or {}
  data.tag_dict = decode_field_array("tag_dict") or {}
  data.scan_queue = decode_field_array("scan_queue") or {}
  data.analyzer_queue = decode_field_array("analyzer_queue") or {}
  data.analyzer_results = decode_field_object("analyzer_results") or {}
  local analyzer_mode = content:match('"analyzer_mode"%s*:%s*"([^"]*)"')
  if analyzer_mode and analyzer_mode ~= "" then
    data.analyzer_mode = analyzer_mode
  end

  local key_pos = content:find('"samples"%s*:', 1)
  if not key_pos then
    return nil
  end
  local arr_pos = content:find("%[", key_pos, true)
  if not arr_pos then
    return nil
  end
  -- Samples are decoded incrementally by the library loader (see next_json_sample).
  data._samples_pos = arr_pos + 1
  data._samples_content = content
  data.samples = {} -- filled during sliced process phase for JSON
  return data
end

-- Extract the next sample value from a SampleMapData.json samples array.
-- Supports v1 objects and v2 compact arrays. Returns table, next_pos; or nil when finished.
function next_json_sample(content, pos)
  if not content or not pos then
    return nil, pos
  end
  local n = #content
  local byte = string.byte
  local sub = string.sub
  local i = pos
  while i <= n do
    local b = byte(content, i)
    if b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 and b ~= 44 then
      break
    end
    i = i + 1
  end
  if i > n then
    return nil, i
  end
  local b = byte(content, i)
  if b == 93 then -- ]
    return nil, i + 1
  end
  local open_b, close_b
  if b == 123 then -- {
    open_b, close_b = 123, 125
  elseif b == 91 then -- [
    open_b, close_b = 91, 93
  else
    return nil, i
  end
  local start = i
  local depth = 1
  i = i + 1
  local in_str = false
  local esc = false
  while i <= n and depth > 0 do
    local ch = byte(content, i)
    if in_str then
      if esc then
        esc = false
      elseif ch == 92 then
        esc = true
      elseif ch == 34 then
        in_str = false
      end
    else
      if ch == 34 then
        in_str = true
      elseif ch == open_b then
        depth = depth + 1
      elseif ch == close_b then
        depth = depth - 1
      end
    end
    i = i + 1
  end
  local ok, obj = pcall(json_decode, sub(content, start, i - 1))
  if ok and type(obj) == "table" then
    return obj, i
  end
  return nil, i
end

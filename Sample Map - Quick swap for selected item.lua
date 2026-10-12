-- @description Sample Map - Quick swap for selected item
-- @version 0.1.0
-- @author bryan
-- @about
--   Companion to "Sample Map Browser". Run with a single audio item selected.
--   Opens ONLY the sample map filtered to samples sharing the same tags as the
--   selected item's current sample. Click any dot to instantly replace the
--   selected item's take source. Press Esc to close.
-- @requires ReaImGui

local r = reaper

-- --- Dependency check --------------------------------------------------------
if not r.APIExists('ImGui_GetVersion') then
  r.ShowMessageBox("ReaImGui is required for this script.", "Missing dependency", 0)
  return
end

-- --- Paths (resolve from this script's location) -----------------------------
local SCRIPT_NAME = "Sample Map - Quick Swap"
local _, script_path = r.get_action_context()
local SCRIPT_DIR = (script_path and script_path:match("^(.+)[/\\][^/\\]+$"))
  or (r.GetResourcePath() .. "/Scripts/Bryan's Scripts")
local DATA_PATH = SCRIPT_DIR .. "/SampleMapData.json"
local CONFIG_PATH = SCRIPT_DIR .. "/SampleMapBrowser.json"

-- --- Small helpers (mirrored from Sample Map Browser) ------------------------
local function normalize_path(path)
  if not path or path == "" then return path end
  path = path:gsub("\\", "/")
  path = path:gsub("/+$", "")
  return path
end

local function basename(path)
  if not path then return "" end
  local norm = normalize_path(path)
  return norm:match("([^/]+)$") or norm
end

local function extract_rgb(color)
  if not color then return 0, 0, 0 end
  local rr = math.floor((color / 65536) % 256)
  local gg = math.floor((color / 256) % 256)
  local bb = math.floor(color % 256)
  return rr, gg, bb
end

local function build_color_rrgbbaa(rr, gg, bb, a)
  a = a or 255
  return (math.floor(rr) * 16777216) + (math.floor(gg) * 65536) + (math.floor(bb) * 256) + math.floor(a)
end

-- Meta tags (loop/oneshot) are ignored when matching — they appear on almost every sample.
local META_TAGS = { loop = true, ["one shot"] = true, oneshot = true }

local TAG_KEYWORDS = {
  {tag = "kick",   keys = {"kick", "kck"}, weight = 100},
  {tag = "snare",  keys = {"snare", "snr"}, weight = 95},
  {tag = "clap",   keys = {"clap"}, weight = 92},
  {tag = "snap",   keys = {"snap", "finger", "finger snap", "finger snaps", "fingersnap", "fingersnaps"}, weight = 91},
  {tag = "rim",    keys = {"rim", "rimshot"}, weight = 90},
  {tag = "hat",    keys = {"hat", "hihat", "oh", "ch", "hh"}, weight = 88},
  {tag = "tom",    keys = {"tom"}, weight = 82},
  {tag = "ride",   keys = {"ride"}, weight = 80},
  {tag = "crash",  keys = {"crash", "cymbal"}, weight = 79},
  {tag = "perc",   keys = {"perc", "percussion", "shaker", "tamb", "cowbell"}, weight = 76},
  {tag = "fx",     keys = {"fx", "sfx", "impact", "whoosh", "sweep", "riser", "uplift", "downlift"}, weight = 74},
  {tag = "bass",   keys = {"bass", "sub"}, weight = 70},
  {tag = "808",    keys = {"808"}, weight = 69},
  {tag = "vocal",  keys = {"vocal", "vox", "voice"}, weight = 65},
  {tag = "drum",   keys = {"drum", "beat", "break"}, weight = 58},
  {tag = "pad",    keys = {"pad"}, weight = 55},
  {tag = "lead",   keys = {"lead"}, weight = 54},
  {tag = "pluck",  keys = {"pluck"}, weight = 53},
  {tag = "keys",   keys = {"keys", "piano"}, weight = 52},
  {tag = "guitar", keys = {"guitar"}, weight = 50},
}

-- Words of a name, lowercased: split on punctuation, letter/digit runs and
-- camelCase, so "BigKick_02" gives big, kick, 02 and "Synth Chords" gives
-- synth, chords (never "ch").
local function text_tokens(text)
  local list = {}
  for word in (text or ""):gmatch("%w+") do
    word = word:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
    for part in word:gmatch("%S+") do
      list[#list + 1] = part:lower()
    end
  end
  return list
end

local function infer_tags_from_text(text)
  local list = text_tokens(text)
  local tokens = {}
  for _, token in ipairs(list) do
    tokens[token] = true
  end
  -- Space-joined words, for multi-word keys such as "finger snap".
  local joined = " " .. table.concat(list, " ") .. " "

  local scored = {}
  for _, entry in ipairs(TAG_KEYWORDS) do
    for _, key in ipairs(entry.keys) do
      local key_l = key:lower()
      local matched = false
      if key_l:find(" ", 1, true) then
        matched = joined:find(" " .. key_l .. " ", 1, true) ~= nil
      else
        -- Whole words only ("tom" must not match "custom"); a plural counts.
        matched = tokens[key_l] or tokens[key_l .. "s"] or false
      end
      if matched then
        local current = scored[entry.tag] or 0
        if entry.weight > current then
          scored[entry.tag] = entry.weight
        end
        break
      end
    end
  end

  local sorted = {}
  for tag, weight in pairs(scored) do
    sorted[#sorted + 1] = { tag = tag, weight = weight }
  end
  table.sort(sorted, function(a, b)
    if a.weight == b.weight then return a.tag < b.tag end
    return a.weight > b.weight
  end)

  local tags = {}
  for _, entry in ipairs(sorted) do
    tags[#tags + 1] = entry.tag
    if #tags >= 6 then break end
  end
  return tags
end

local function infer_tags_from_path(path, folder)
  local joined = ((path or "") .. " " .. (folder or "")):gsub("%s+", " ")
  return infer_tags_from_text(joined)
end

local function tags_to_filter_set(tags)
  local out = {}
  for _, tag in ipairs(tags or {}) do
    if not META_TAGS[tag] then
      out[tag] = true
    end
  end
  return out
end

local function sample_tags(sample)
  if not sample then return {} end
  if sample._quickswap_tags and #sample._quickswap_tags > 0 then
    return sample._quickswap_tags
  end

  local merged = {}
  local seen = {}

  if sample.tags and type(sample.tags) == "table" then
    for _, tag in ipairs(sample.tags) do
      if tag and tag ~= "" and not seen[tag] then
        seen[tag] = true
        merged[#merged + 1] = tag
      end
    end
  end

  -- Always enrich with filename/path inference so older sparse caches
  -- (e.g. only "loop") still match category searches like "snare".
  local folder = sample.folder or sample.path:match("(.+)/[^/]+$") or ""
  for _, tag in ipairs(infer_tags_from_path(sample.path or "", folder)) do
    if tag and tag ~= "" and not seen[tag] then
      seen[tag] = true
      merged[#merged + 1] = tag
    end
  end

  sample._quickswap_tags = merged
  return merged
end

local function sample_shares_tags(sample, filter_tags)
  if not sample or not next(filter_tags) then return false end
  for _, tag in ipairs(sample_tags(sample)) do
    if filter_tags[tag] then return true end
  end
  return false
end

-- --- JSON decoder (mirrored from Sample Map Browser) -------------------------
local function json_decode(str)
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

  parse_value = function()
    skip_ws()
    local b = byte(str, pos)
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

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*all")
  f:close()
  if content then
    content = content:gsub("^\239\187\191", "") -- strip UTF-8 BOM if present
  end
  return content
end

local function extract_json_array(content, key)
  local key_pos = content:find('"' .. key .. '"%s*:', 1)
  if not key_pos then return nil end
  local colon = content:find(":", key_pos, true)
  if not colon then return nil end
  local i = colon + 1
  local n = #content
  local byte = string.byte
  while i <= n do
    local b = byte(content, i)
    if b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 then break end
    i = i + 1
  end
  if byte(content, i) ~= 91 then return nil end
  local start = i
  local depth = 1
  i = i + 1
  local in_str, esc = false, false
  while i <= n and depth > 0 do
    local ch = byte(content, i)
    if in_str then
      if esc then esc = false
      elseif ch == 92 then esc = true
      elseif ch == 34 then in_str = false end
    else
      if ch == 34 then in_str = true
      elseif ch == 91 then depth = depth + 1
      elseif ch == 93 then depth = depth - 1 end
    end
    i = i + 1
  end
  return content:sub(start, i - 1)
end

local function decode_json_array_field(content, key)
  local json = extract_json_array(content, key)
  if not json then return {} end
  local ok, decoded = pcall(json_decode, json)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return {}
end

local function expand_compact_sample(row, dirs, tag_dict)
  if type(row) ~= "table" then return nil end
  if type(row.path) == "string" and row.path ~= "" then
    row.path = normalize_path(row.path)
    if not row.x then row.x = 0.5 end
    if not row.y then row.y = 0.5 end
    return row
  end
  local name = row[2]
  if type(name) ~= "string" or name == "" then return nil end
  local dir = ""
  if type(row[1]) == "number" and dirs then
    dir = dirs[row[1]] or ""
  end
  local path = (dir ~= "" and (dir .. "/" .. name)) or name
  local tags = {}
  if type(row[3]) == "table" and tag_dict then
    for i = 1, #row[3] do
      local tag = tag_dict[row[3][i]]
      if tag and tag ~= "" then
        tags[#tags + 1] = tag
      end
    end
  end
  return {
    path = normalize_path(path),
    name = name,
    folder = dir,
    tags = tags,
    x = (type(row[4]) == "number" and row[4]) or 0.5,
    y = (type(row[5]) == "number" and row[5]) or 0.5,
  }
end

-- SampleMapBrowser saves one sample per line; parse those directly instead
-- of decoding the entire cache file (which can fail on large nested JSON).
-- v2 rows are compact arrays; v1 rows are objects with a "path" field.
local function load_samples_from_cache(content)
  local loaded = {}
  local dirs = decode_json_array_field(content, "dirs")
  local tag_dict = decode_json_array_field(content, "tag_dict")
  local is_v2 = content:find('"v"%s*:%s*2') ~= nil or #dirs > 0

  for line in content:gmatch("[^\r\n]+") do
    if is_v2 then
      local arr_str = line:match("^%s*(%b[])%s*,?%s*$")
      if arr_str and #arr_str > 8 then
        local ok, row = pcall(json_decode, arr_str)
        if ok and type(row) == "table" and type(row[2]) == "string" and #row >= 5 then
          local s = expand_compact_sample(row, dirs, tag_dict)
          if s then
            loaded[#loaded + 1] = s
          end
        end
      end
    else
      for obj_str in line:gmatch("%b{}") do
        if obj_str:find('"path"%s*:') and not obj_str:find('"folders"%s*:') then
          local ok, s = pcall(json_decode, obj_str)
          if ok and type(s) == "table" and s.path then
            s.path = normalize_path(s.path)
            if not s.x then s.x = 0.5 end
            if not s.y then s.y = 0.5 end
            loaded[#loaded + 1] = s
          end
        end
      end
    end
  end
  return loaded
end

-- --- Load config (tag colors / dot color) -----------------------------------
local cfg = {
  dot_color = 0x44AA55,
  tag_colors = {},
}
do
  local content = read_file(CONFIG_PATH)
  if content and content ~= "" then
    local ok, data = pcall(json_decode, content)
    if ok and type(data) == "table" then
      if type(data.dot_color) == "number" then cfg.dot_color = data.dot_color end
      if type(data.tag_colors) == "table" then cfg.tag_colors = data.tag_colors end
    end
  end
end

-- --- Load all samples from cache ---------------------------------------------
local all_samples = {}
local sample_by_path = {}
do
  local content = read_file(DATA_PATH)
  if not content or content == "" then
    r.ShowMessageBox(
      "No sample map data found at:\n" .. DATA_PATH ..
      "\n\nOpen 'Sample Map Browser' first and let it scan your folders.",
      SCRIPT_NAME, 0)
    return
  end

  all_samples = load_samples_from_cache(content)

  -- Fallback: try full-file decode (older/minified cache format)
  if #all_samples == 0 then
    local ok, data = pcall(json_decode, content)
    if ok and type(data) == "table" and type(data.samples) == "table" then
      for _, s in ipairs(data.samples) do
        if type(s) == "table" and s.path then
          s.path = normalize_path(s.path)
          if not s.x then s.x = 0.5 end
          if not s.y then s.y = 0.5 end
          all_samples[#all_samples + 1] = s
        end
      end
    end
  end

  for _, s in ipairs(all_samples) do
    sample_by_path[s.path] = s
  end
end

if #all_samples == 0 then
  r.ShowMessageBox(
    "Sample map is empty or could not be read.\n\nData file:\n" .. DATA_PATH,
    SCRIPT_NAME, 0)
  return
end

-- --- Selected item & its current source --------------------------------------
local target_item = r.GetSelectedMediaItem(0, 0)
if not target_item then
  r.ShowMessageBox("Select an audio item first, then run this script.", SCRIPT_NAME, 0)
  return
end

local function get_item_source_path(item)
  if not item or not r.ValidatePtr(item, "MediaItem*") then return nil end
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return nil end
  local src = r.GetMediaItemTake_Source(take)
  if not src then return nil end
  local _, path = r.GetMediaSourceFileName(src, "")
  if not path or path == "" then return nil end
  return normalize_path(path)
end

local function get_item_track_name(item)
  if not item or not r.ValidatePtr(item, "MediaItem*") then return "" end
  local track = r.GetMediaItemTrack(item)
  if not track then return "" end
  local _, name = r.GetTrackName(track, "")
  return name or ""
end

local cur_path = get_item_source_path(target_item)
local cur_sample = cur_path and sample_by_path[cur_path] or nil

-- Build tag filter priority:
-- 1) tags from track name, 2) tags parsed from selected item's source filename/path.
local track_name = get_item_track_name(target_item)
local filter_tags = tags_to_filter_set(infer_tags_from_text(track_name))
local filter_source = "track name"
if not next(filter_tags) and cur_path then
  filter_source = "source filename"
  local file_name = basename(cur_path)
  filter_tags = tags_to_filter_set(infer_tags_from_text(file_name))
  if not next(filter_tags) then
    filter_source = "source path"
    local folder = cur_path:match("(.+)/[^/]+$") or ""
    filter_tags = tags_to_filter_set(infer_tags_from_path(file_name, folder))
  end
end
if not next(filter_tags) and cur_sample then
  filter_source = "selected sample tags"
  filter_tags = tags_to_filter_set(sample_tags(cur_sample))
end

local filter_tag_names = {}
for tag in pairs(filter_tags) do
  filter_tag_names[#filter_tag_names + 1] = tag
end
table.sort(filter_tag_names)

if not next(filter_tags) then
  r.ShowMessageBox(
    "Could not determine tags.\n\n" ..
    "Track name: " .. (track_name ~= "" and track_name or "(empty)") .. "\n" ..
    "Source file: " .. (cur_path and basename(cur_path) or "(none)") .. "\n\n" ..
    "Rename the track with a tag keyword (kick, snare, clap, etc.) or use a filename containing one.",
    SCRIPT_NAME, 0)
  return
end

-- Keep only samples that share at least one tag (always include current sample)
local samples = {}
for _, s in ipairs(all_samples) do
  if (cur_path and s.path == cur_path) or sample_shares_tags(s, filter_tags) then
    samples[#samples + 1] = s
  end
end

if #samples == 0 then
  r.ShowMessageBox(
    "No samples found with matching tags: " .. table.concat(filter_tag_names, ", "),
    SCRIPT_NAME, 0)
  return
end

-- --- Initial view center (selected item's sample position) -------------------
local view_zoom = 2.0  -- 2.0 = 50% of the map visible (zoomed in)
local view_x, view_y = 0.5, 0.5
if cur_sample then
  view_x, view_y = cur_sample.x, cur_sample.y
end

local status_line = string.format(
  "Showing %d samples matching tags (%s): %s  |  Click a dot to swap  |  Right-drag pan, wheel zoom, Esc close",
  #samples, filter_source, table.concat(filter_tag_names, ", "))

-- --- Replace the selected item's source --------------------------------------
local function rebuild_peaks_for_item(item)
  if not item then return end
  local selected = {}
  local sel_count = r.CountSelectedMediaItems(0)
  for i = 0, sel_count - 1 do selected[#selected + 1] = r.GetSelectedMediaItem(0, i) end
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)
  r.Main_OnCommand(40047, 0) -- Peaks: Rebuild peaks for selected items
  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(selected) do
    if r.ValidatePtr(it, "MediaItem*") then r.SetMediaItemSelected(it, true) end
  end
end

local function replace_source(item, path)
  if not item or not r.ValidatePtr(item, "MediaItem*") or not path then return false end
  if not r.file_exists(path) then return false end
  local take = r.GetActiveTake(item)
  if not take then
    take = r.AddTakeToMediaItem(item)
  end
  if not take then return false end
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then return false end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.SetMediaItemTake_Source(take, src)
  local name = basename(path)
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  rebuild_peaks_for_item(item)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Replace sample source from Sample Map", -1)
  return true
end

-- --- Dot color ---------------------------------------------------------------
local function sample_color(s)
  if s.tags and type(s.tags) == "table" then
    for _, tag in ipairs(s.tags) do
      local tc = cfg.tag_colors[tag]
      if tc then
        local rr, gg, bb = extract_rgb(tc)
        return build_color_rrgbbaa(rr, gg, bb, 255)
      end
    end
  end
  local rr, gg, bb = extract_rgb(cfg.dot_color)
  return build_color_rrgbbaa(rr, gg, bb, 255)
end

-- --- ImGui -------------------------------------------------------------------
local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local font = r.ImGui_CreateFont("sans-serif", 14)
if font then r.ImGui_Attach(ctx, font) end

local DOT_RADIUS = 3.5
local first_frame = true

local function draw_map()
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local width, height = r.ImGui_GetContentRegionAvail(ctx)
  if width < 10 or height < 10 then return end

  -- Background + input region
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height, 0x1A1A1AFF, 4.0)
  r.ImGui_InvisibleButton(ctx, "##map", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)

  local cx = x0 + width * 0.5
  local cy = y0 + height * 0.5

  local function to_screen(nx, ny)
    local px = cx + (nx - view_x) * width * view_zoom
    local py = cy + (ny - view_y) * height * view_zoom
    return px, py
  end

  -- Pan with right-drag
  if hovered and r.ImGui_IsMouseDown(ctx, 1) then
    local dx, dy = r.ImGui_GetMouseDelta(ctx)
    view_x = view_x - dx / (width * view_zoom)
    view_y = view_y - dy / (height * view_zoom)
  end

  -- Zoom with wheel (anchored on mouse)
  if hovered then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then
      local before_nx = (mx - cx) / (width * view_zoom) + view_x
      local before_ny = (my - cy) / (height * view_zoom) + view_y
      view_zoom = math.max(1.0, math.min(8.0, view_zoom * (1.0 + wheel * 0.1)))
      view_x = before_nx - (mx - cx) / (width * view_zoom)
      view_y = before_ny - (my - cy) / (height * view_zoom)
    end
  end

  local cur_path = get_item_source_path(target_item)

  -- Find nearest dot under the mouse
  local hover_sample, hover_px, hover_py = nil, nil, nil
  local best_dist = 1e18
  local hit_r = DOT_RADIUS * 4.0

  for _, s in ipairs(samples) do
    local px, py = to_screen(s.x, s.y)
    if px >= x0 - 8 and px <= x0 + width + 8 and py >= y0 - 8 and py <= y0 + height + 8 then
      if hovered then
        local ddx, ddy = mx - px, my - py
        local d = ddx * ddx + ddy * ddy
        if d <= hit_r * hit_r and d < best_dist then
          best_dist = d
          hover_sample, hover_px, hover_py = s, px, py
        end
      end
    end
  end

  -- Draw dots
  for _, s in ipairs(samples) do
    local px, py = to_screen(s.x, s.y)
    if px >= x0 - 8 and px <= x0 + width + 8 and py >= y0 - 8 and py <= y0 + height + 8 then
      local col = sample_color(s)
      r.ImGui_DrawList_AddCircleFilled(dl, px, py, DOT_RADIUS, col, 12)
      -- Outline the dot that matches the item's current source
      if cur_path and s.path == cur_path then
        r.ImGui_DrawList_AddCircle(dl, px, py, DOT_RADIUS + 4.0, 0xFF00FFFF, 20, 2.5)
      end
    end
  end

  -- Hover highlight + tooltip + click to swap
  if hover_sample then
    r.ImGui_DrawList_AddCircle(dl, hover_px, hover_py, DOT_RADIUS + 2.5, 0xFFFF66FF, 16, 2.0)
    if r.ImGui_BeginTooltip(ctx) then
      r.ImGui_Text(ctx, hover_sample.name or basename(hover_sample.path))
      r.ImGui_EndTooltip(ctx)
    end
    if r.ImGui_IsMouseClicked(ctx, 0) then
      replace_source(target_item, hover_sample.path)
    end
  end
end

local function loop()
  -- Close if the target item disappears
  if not r.ValidatePtr(target_item, "MediaItem*") then return end

  if first_frame then
    r.ImGui_SetNextWindowSize(ctx, 720, 600, r.ImGui_Cond_FirstUseEver())
    first_frame = false
  end

  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true)
  if visible then
    r.ImGui_Text(ctx, status_line)
    r.ImGui_Separator(ctx)
    draw_map()
    r.ImGui_End(ctx)
  end

  local esc = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape())
  if open and not esc then
    r.defer(loop)
  end
end

r.defer(loop)

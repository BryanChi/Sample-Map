"""Library load passes (apply_discovered_library_tags, rebuild_tag_index,
rebuild_samples_path_index) were sped up by memoizing per-directory and per-tag
work. REF_LUA is the original code (renamed); both versions run on identical
random libraries in one Lua state and must leave identical state behind.
Loads the whole browser with the stub REAPER API from load_browser.py."""
import os
import re
import tempfile

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))

REF_LUA = r'''
function REF_apply_discovered_library_tags()
  local samples = state.samples
  if type(samples) ~= "table" or #samples == 0 then
    state.discovered_library_tag_set = {}
    return
  end

  local skip = {
    pack = true, packs = true, kit = true, kits = true, bundle = true, bundles = true,
    collection = true, collections = true, sample = true, samples = true, sampler = true,
    sound = true, sounds = true, audio = true, wav = true, wave = true, aiff = true,
    flac = true, mp3 = true, ogg = true, loop = true, loops = true, looping = true,
    oneshot = true, oneshots = true, one = true, shot = true, shots = true,
    drum = true, drums = true, drumkit = true, perc = true, percussion = true,
    fx = true, sfx = true, vocal = true, vocals = true, vox = true, voice = true,
    kick = true, kicks = true, snare = true, snares = true, clap = true, claps = true,
    snap = true, snaps = true, hat = true, hats = true, hihat = true, hihats = true,
    tom = true, toms = true, ride = true, rides = true, crash = true, crashes = true,
    cymbal = true, cymbals = true, rim = true, rims = true, bass = true, basses = true,
    lead = true, leads = true, pad = true, pads = true, pluck = true, plucks = true,
    key = true, keys = true, piano = true, pianos = true, guitar = true, guitars = true,
    inst = true, instrument = true, instruments = true, folder = true, folders = true,
    file = true, files = true, library = true, libraries = true, lib = true,
    download = true, downloads = true, new = true, final = true, demo = true, demos = true,
    bonus = true, extra = true, extras = true, preview = true, previews = true,
    stem = true, stems = true, midi = true, preset = true, presets = true,
    vol = true, volume = true, pt = true, part = true, version = true, ver = true,
    stereo = true, mono = true, multi = true, bpm = true, hz = true, khz = true,
    bit = true, bits = true, rate = true, the = true, ["and"] = true, ["for"] = true,
    from = true, with = true, you = true, your = true,
    this = true, that = true, all = true, any = true, untitled = true, copy = true,
    backup = true, old = true, temp = true, tmp = true, misc = true, other = true,
    various = true, users = true, user = true, documents = true, desktop = true,
    music = true, volumes = true, applications = true, application = true,
    support = true, reaper = true, scripts = true, home = true, content = true,
    contents = true, media = true, imported = true, import = true, export = true,
    project = true, projects = true, session = true, sessions = true,
    swell = true, ones = true, wavs = true, audiofiles = true,
    scene = true, discover = true,
  }
  for _, entry in ipairs(TAG_KEYWORDS) do
    skip[string.lower(entry.tag)] = true
    for _, key in ipairs(entry.keys) do
      skip[string.lower(key)] = true
    end
  end
  for _, entry in ipairs(GENRE_KEYWORDS) do
    skip[string.lower(entry.tag)] = true
    for _, key in ipairs(entry.keys) do
      if #key >= 3 then
        skip[string.lower(key)] = true
      end
    end
  end
  for tag, on in pairs(state.deleted_tags or {}) do
    if on then
      skip[string.lower(tostring(tag))] = true
    end
  end

  local core_keep = {
    loop = true, oneshot = true, ["one shot"] = true, drum = true, swell = true,
  }
  for _, entry in ipairs(TAG_KEYWORDS) do
    core_keep[string.lower(entry.tag)] = true
  end
  for tag, _ in pairs(GENRE_TAG_SET) do
    core_keep[tag] = true
  end

  local function is_junk_token(token)
    if not token or token == "" or skip[token] or core_keep[token] then
      return true
    end
    if #token < 3 or #token > 64 then
      return true
    end
    if token:match("^%d+$") or token:match("^v%d+$") or token:match("^vol%d+$") then
      return true
    end
    if token:match("^%d+bpm$") or token:match("^%d+k$") or token:match("^%d+hz$") or token:match("^%d+bit$") then
      return true
    end
    if token:match("^[a-g][#b]?min$") or token:match("^[a-g][#b]?maj$")
        or token:match("^[a-g]minor$") or token:match("^[a-g]major$") then
      return true
    end
    return false
  end

  local function scan_root_and_relative(path)
    path = normalize_path(path or "")
    local dir = path:match("(.+)/[^/]+$") or ""
    local best = ""
    for _, folder in ipairs(state.folders or {}) do
      local root = normalize_path(folder)
      if root ~= "" and (dir == root or dir:sub(1, #root + 1) == root .. "/") then
        if #root > #best then
          best = root
        end
      end
    end
    if best == "" then
      return "", dir
    end
    if dir == best then
      return best, ""
    end
    return best, dir:sub(#best + 2)
  end

  local function tokens_from_library_path(rel, root)
    local found = {}
    local function consider(token)
      token = tostring(token or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
      if is_junk_token(token) or found[token] then
        return
      end
      found[token] = true
    end
    local function add_segment(segment)
      local phrase = tostring(segment or ""):lower():gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
      if phrase == "" then
        return
      end
      local kept_words = {}
      for word in phrase:gmatch("%w+") do
        consider(word)
        if not is_junk_token(word) then
          kept_words[#kept_words + 1] = word
        end
      end
      -- Keep the original folder name when it has a distinctive word, so
      -- "Cymatics Lofi Pack" stays one chip instead of a stitched fragment.
      if phrase:find(" ", 1, true) and #kept_words >= 1 then
        consider(phrase)
      end
    end
    if root and root ~= "" then
      add_segment(root:match("([^/]+)$") or "")
    end
    for segment in tostring(rel or ""):gmatch("[^/]+") do
      add_segment(segment)
    end
    return found
  end

  local function library_haystack(rel, root)
    local leaf = ""
    if root and root ~= "" then
      leaf = root:match("([^/]+)$") or ""
    end
    return (leaf .. " " .. tostring(rel or "")):lower():gsub("[^%w]+", " ")
  end

  local dir_counts = {}
  local dir_tokens = {}
  local dir_meta = {}
  local n = #samples
  for i = 1, n do
    local sample = samples[i]
    local root, rel = scan_root_and_relative(sample and sample.path)
    local key = (root .. "\t" .. rel):lower()
    dir_counts[key] = (dir_counts[key] or 0) + 1
    if not dir_tokens[key] then
      dir_tokens[key] = tokens_from_library_path(rel, root)
      dir_meta[key] = { root = root, rel = rel }
    end
  end

  local function pack_id_for(root, rel)
    local first = tostring(rel or ""):match("^([^/]+)")
    if first and first ~= "" then
      return tostring(root or "") .. "\t" .. first:lower()
    end
    local leaf = tostring(root or ""):match("([^/]+)$") or ""
    return tostring(root or "") .. "\t" .. leaf:lower()
  end

  local token_counts = {}
  local token_packs = {}
  for key, count in pairs(dir_counts) do
    local meta = dir_meta[key] or {}
    local pack = pack_id_for(meta.root, meta.rel)
    for token, _ in pairs(dir_tokens[key] or {}) do
      token_counts[token] = (token_counts[token] or 0) + count
      local packs = token_packs[token]
      if not packs then
        packs = {}
        token_packs[token] = packs
      end
      packs[pack] = true
    end
  end

  local min_count = 5
  if n >= 40 then
    min_count = math.max(8, math.min(24, math.floor(n * 0.012)))
  end

  local function pack_count(token)
    local packs = token_packs[token]
    if not packs then
      return 0
    end
    local c = 0
    for _ in pairs(packs) do
      c = c + 1
    end
    return c
  end

  local ranked = {}
  for token, count in pairs(token_counts) do
    if count >= min_count and pack_count(token) >= 2 then
      ranked[#ranked + 1] = { tag = token, count = count }
    end
  end
  table.sort(ranked, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
  local cap = 50
  if #ranked > cap then
    for i = cap + 1, #ranked do
      ranked[i] = nil
    end
  end

  local new_set = {}
  for i = 1, #ranked do
    new_set[ranked[i].tag] = true
  end

  local dir_match_cache = {}
  local function matching_tags_for_path(path)
    local root, rel = scan_root_and_relative(path)
    local hay = library_haystack(rel, root)
    local cached = dir_match_cache[hay]
    if cached then
      return cached
    end
    local extra = {}
    for i = 1, #ranked do
      local tag = ranked[i].tag
      if genre_key_matches(hay, tag) then
        extra[#extra + 1] = tag
      end
    end
    dir_match_cache[hay] = extra
    return extra
  end

  for i = 1, n do
    local sample = samples[i]
    if sample then
      local custom = {}
      local path = sample.path or ""
      local custom_list = state.custom_tags and (state.custom_tags[path] or state.custom_tags[normalize_path(path)])
      if type(custom_list) == "table" then
        for _, tag in ipairs(custom_list) do
          custom[tostring(tag):lower()] = true
        end
      end
      local kept = {}
      for _, tag in ipairs(sample.tags or {}) do
        local low = tostring(tag):lower()
        if (core_keep[low] or custom[low]) and not (tag_is_suppressed and tag_is_suppressed(low)) then
          kept[#kept + 1] = tag
        end
      end
      sample.tags = append_unique_tags(kept, matching_tags_for_path(path))
    end
  end

  state.discovered_library_tag_set = new_set
end

function REF_rebuild_tag_index()
  local counts = {}
  local by_tag = {}
  for _, s in ipairs(state.samples) do
    s._render_color = nil
    local set = {}
    if s.tags and type(s.tags) == "table" then
      local tags, seen = {}, {}
      for _, tag in ipairs(s.tags) do
        if tag == "808" then
          tag = "808s"
        end
        if tag and not seen[tag] then
          seen[tag] = true
          tags[#tags + 1] = tag
        end
      end
      s.tags = tags
      for _, tag in ipairs(tags) do
        if not (tag_is_suppressed and tag_is_suppressed(tag)) then
          set[tag] = true
          counts[tag] = (counts[tag] or 0) + 1
          local list = by_tag[tag]
          if not list then
            list = {}
            by_tag[tag] = list
          end
          list[#list + 1] = s
        end
      end
    end
    s._tag_set = set
  end

  state.samples_by_tag = by_tag
  state.tag_counts = counts
  state.tag_index_epoch = (state.tag_index_epoch or 0) + 1
  state.tag_index_samples_ref = state.samples
  state.tag_index_sample_count = #state.samples
  state.tag_category_rev = (state.tag_category_rev or 0) + 1
  state.tag_list = {}
  for tag, count in pairs(counts) do
    table.insert(state.tag_list, {tag = tag, count = count})
  end
  table.sort(state.tag_list, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
end

function REF_rebuild_samples_path_index()
  samples_by_path = {}
  sample_path_miss = {}
  for _, s in ipairs(state.samples) do
    if s.path then
      samples_by_path[s.path] = s
      -- Also index forward-slash normalized form for analyzer path lookups
      local norm = tostring(s.path):gsub("\\", "/"):gsub("/+$", "")
      if norm ~= s.path then
        samples_by_path[norm] = s
      end
      -- External volumes (ExFAT/HFS) often change spelling/case on remount.
      local key = path_index_key(s.path)
      if key ~= "" and key ~= s.path and key ~= norm then
        samples_by_path[key] = s
      end
    end
  end
end
'''

REF_MAP_LUA = r'''
function REF_get_sample_dot_color(sample)
  if not sample then
    return build_color_rrgbbaa(96, 96, 96, 255)
  end
  if sample._render_color then
    return sample._render_color
  end

  local color = build_color_rrgbbaa(extract_rgb(state.dot_color or 0x44AA55))
  if sample.tags and type(sample.tags) == "table" and #sample.tags > 0 then
    local best_tag = nil
    local best_weight = 0
    for _, tag_name in ipairs(sample.tags) do
      local weight = TAG_KEYWORD_WEIGHT[tag_name]
      if weight and weight > best_weight then
        best_weight = weight
        best_tag = tag_name
      end
    end
    if best_tag and state.tag_colors[best_tag] then
      local tr, tg, tb = extract_rgb(state.tag_colors[best_tag])
      color = build_color_rrgbbaa(tr, tg, tb, 255)
    end
  end

  if sample.channels == 1 then
    local base_r, base_g, base_b = extract_rgb_rrgbbaa(color)
    color = build_color_rrgbbaa(
      math.min(255, math.floor(base_r * 1.5)),
      math.min(255, math.floor(base_g * 1.5)),
      math.min(255, math.floor(base_b * 1.5)),
      255
    )
  end

  sample._render_color = color
  return color
end

function REF_sample_passes_filters(sample, needle, skip_tags)
  if not sample then return false end

  if needle == nil then
    needle = (state.filter ~= "" and string.lower(state.filter)) or ""
  end
  if needle ~= "" then
    -- Lowercased name/path are memoized on the sample (underscore fields are
    -- never written to the library cache) and refreshed if either changes.
    local src_name, src_path = sample.name or "", sample.path or ""
    if sample._lc_src_name ~= src_name or sample._lc_src_path ~= src_path then
      sample._lc_src_name = src_name
      sample._lc_src_path = src_path
      sample._lc_name = string.lower(src_name)
      sample._lc_path = string.lower(src_path)
    end
    if not string.find(sample._lc_name, needle, 1, true) and not string.find(sample._lc_path, needle, 1, true) then
      return false
    end
  end

  if not skip_tags and state.active_tags and next(state.active_tags) ~= nil then
    local matched = false
    local set = sample._tag_set
    if set then
      for tag, on in pairs(state.active_tags) do
        if on and set[tag] then
          matched = true
          break
        end
      end
    elseif sample.tags then
      for _, tag in ipairs(sample.tags) do
        if state.active_tags[tag] then
          matched = true
          break
        end
      end
    end
    if not matched then
      return false
    end
  end

  -- Check folder path filter (sample matches if it is under any selected folder)
  if not folder_filter_matches_sample(sample.path) then
    return false
  end

  return true
end

function REF_build_map_spatial(filtered)
  local spatial = {}
  for i = 1, #filtered do
    local s = filtered[i]
    local cell_x = math.max(0, math.min(MAP_GRID_RES - 1, math.floor((s.x or 0.5) * MAP_GRID_RES)))
    local cell_y = math.max(0, math.min(MAP_GRID_RES - 1, math.floor((s.y or 0.5) * MAP_GRID_RES)))
    local key = map_spatial_cell_key(cell_x, cell_y)
    local bucket = spatial[key]
    if not bucket then
      bucket = {}
      spatial[key] = bucket
    end
    bucket[#bucket + 1] = s
  end
  return spatial
end
function REF_map_duration_bounds(filtered)
  local duration_min, duration_max = nil, nil
  for i = 1, #filtered do
    local map_dur = sample_map_duration(filtered[i])
    if map_dur > 0 then
      if not duration_min then
        duration_min = map_dur
        duration_max = map_dur
      else
        duration_min = math.min(duration_min, map_dur)
        duration_max = math.max(duration_max, map_dur)
      end
    end
  end
  return duration_min, duration_max
end
function REF_rebuild_map_base_cache()
  local filtered = {}
  local filtered_set = {}
  local needle = (state.filter ~= "" and string.lower(state.filter)) or ""
  local samples = state.samples or {}
  for i = 1, #samples do
    local s = samples[i]
    -- skip_tags: base cache ignores active tag filters
    if type(s) == "table" and s.x and REF_sample_passes_filters(s, needle, true) then
      if not s._render_color then
        s._render_color = get_sample_dot_color(s)
      end
      s._folder_unavailable = sample_scan_folder_unavailable(s)
      filtered[#filtered + 1] = s
      filtered_set[s] = true
    end
  end

  map_base_cache.filtered = filtered
  map_base_cache.filtered_set = filtered_set
  map_base_cache.filtered_count = #filtered
  map_base_cache.spatial = REF_build_map_spatial(filtered)
  map_base_cache.duration_min, map_base_cache.duration_max = REF_map_duration_bounds(filtered)
  map_base_cache.key = compute_map_base_filter_key()
end
'''

COMPARE_LUA = r'''
local R = math.random
local WORDS = { "Cymatics", "Lofi", "Pack", "Drums", "KICKS", "snare", "Splice", "vendor", "Deep House",
  "trap", "Vintage Keys", "808", "Vol 2", "120bpm", "Am", "Hats", "FX", "Melodic Techno", "Ambient",
  "Garage", "Jersey Club", "Future Bass", "Kicks & Snares", "one-shots", "Cymatics", "Lofi" }
local TAGS = { "kick", "Kick", "snare", "hat", "loop", "oneshot", "808", "808s", "deep house", "techno",
  "Lofi", "custom one", "Trap", "cymatics", "fx", "", "pad" }
local ROOTS = { "/Users/me/Samples", "/Users/me/Samples/Packs", "D:\\Libs", "/Volumes/Drive/Loops/", "/Users/me/Samples" }

local function rand_dir(root)
  local parts = { root }
  for i = 1, R(0, 3) do parts[#parts + 1] = WORDS[R(1, #WORDS)] .. (R(1, 4) == 1 and (" " .. R(1, 9)) or "") end
  local dir = table.concat(parts, "/")
  if R(1, 15) == 1 then dir = dir:gsub("/", "\\") end
  return dir
end

function make_library(n, seed)
  math.randomseed(seed)
  local dirs = {}
  for i = 1, math.max(3, n // 12) do dirs[i] = rand_dir(ROOTS[R(1, #ROOTS)]) end
  local samples = {}
  for i = 1, n do
    local dir = dirs[R(1, #dirs)]
    local name = WORDS[R(1, #WORDS)] .. "_" .. i .. ".wav"
    local path = dir .. "/" .. name
    if R(1, 30) == 1 then path = path .. "/" end
    if R(1, 40) == 1 then path = name end
    if R(1, 60) == 1 then path = "" end
    local s = { path = (R(1, 80) == 1) and nil or path, name = name, x = R(), y = R() }
    if R(1, 6) > 1 then
      s.tags = {}
      for k = 1, R(0, 4) do s.tags[#s.tags + 1] = TAGS[R(1, #TAGS)] end
    end
    samples[i] = s
  end
  return samples
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

-- Compares two libraries' state after the passes; sample identity is mapped by index.
local function same_state(a_samples, a_extra, b_samples, b_extra)
  local idx_a, idx_b = {}, {}
  for i, s in ipairs(a_samples) do idx_a[s] = i end
  for i, s in ipairs(b_samples) do idx_b[s] = i end
  local function eq(x, y)
    if type(x) ~= type(y) then return false end
    if type(x) ~= "table" then return x == y end
    if idx_a[x] or idx_b[y] then return idx_a[x] == idx_b[y] end
    for k, v in pairs(x) do if not eq(v, y[k]) then return false end end
    for k in pairs(y) do if x[k] == nil then return false end end
    return true
  end
  if #a_samples ~= #b_samples then return false, "count" end
  for i = 1, #a_samples do
    local sa, sb = a_samples[i], b_samples[i]
    for k, v in pairs(sa) do
      if not eq(v, sb[k]) then return false, "sample " .. i .. " field " .. tostring(k) end
    end
    for k in pairs(sb) do if sa[k] == nil then return false, "sample " .. i .. " extra field " .. tostring(k) end end
  end
  for k, v in pairs(a_extra) do
    if not eq(v, b_extra[k]) then return false, "state " .. k end
  end
  return true
end

function run_both(n, seed, opts)
  local base = make_library(n, seed)
  state.folders = opts.folders
  state.custom_tags = opts.custom_tags
  state.deleted_tags = opts.deleted_tags
  local results = {}
  for pass = 1, 2 do
    local samples = copy(base)
    state.samples = samples
    state.tag_index_epoch = 0
    state.tag_category_rev = 0
    if pass == 1 then
      if not opts.index_only then REF_apply_discovered_library_tags() end
      REF_rebuild_samples_path_index(); REF_rebuild_tag_index()
    else
      if not opts.index_only then apply_discovered_library_tags() end
      rebuild_samples_path_index(); rebuild_tag_index()
    end
    results[pass] = { samples = samples, extra = {
      discovered = state.discovered_library_tag_set, by_path = samples_by_path, by_tag = state.samples_by_tag,
      counts = state.tag_counts, tag_list = state.tag_list, epoch = state.tag_index_epoch, rev = state.tag_category_rev,
      n = state.tag_index_sample_count } }
  end
  local ok, why = same_state(results[1].samples, results[1].extra, results[2].samples, results[2].extra)
  return ok, why or ""
end
'''


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
    L.execute(REF_LUA)
    L.execute(REF_MAP_LUA)
    L.execute(COMPARE_LUA)
    return L


def test_load_passes_match_original():
    L = _runtime()
    run = L.eval("function(n, seed, folders, custom, deleted, index_only) return run_both(n, seed, { folders = folders, custom_tags = custom, deleted_tags = deleted, index_only = index_only }) end")
    tbl = L.eval("function(...) return { ... } end")
    folder_sets = [
        tbl("/Users/me/Samples", "/Users/me/Samples/Packs", "D:\\Libs", "/Volumes/Drive/Loops/"),
        tbl("/Users/me/Samples"),
        tbl(),
    ]
    for i, folders in enumerate(folder_sets):
        for seed in range(1, 6):
            customs = L.eval("{}") if seed % 2 else L.eval('{ ["/Users/me/Samples/Lofi/Lofi_3.wav"] = { "Custom One", "Trap" }, ["x"] = { "kick" } }')
            deleted = L.eval("{}") if seed % 3 else L.eval('{ cymatics = true, kick = true, lofi = true }')
            ok, why = run(400 + seed * 137, seed * 7 + i, folders, customs, deleted, False)
            assert ok, (i, seed, why)
            # Tag index on its own, with deleted tags still present on samples.
            ok, why = run(300 + seed * 53, seed * 11 + i, folders, customs, deleted, True)
            assert ok, (i, seed, "index only", why)
    discovered = L.execute("""
      local samples = make_library(1500, 99)
      state.samples = samples
      state.folders = { "/Users/me/Samples", "/Users/me/Samples/Packs" }
      state.custom_tags, state.deleted_tags = {}, {}
      apply_discovered_library_tags()
      local n = 0
      for _ in pairs(state.discovered_library_tag_set) do n = n + 1 end
      return n
    """)
    assert discovered > 0  # the ranking/matching path is exercised


def test_map_filter_rebuild_matches_original():
    L = _runtime()
    bad = L.execute(r'''
      local function snapshot(samples)
        local idx = {}
        for i, s in ipairs(samples) do idx[s] = i end
        local f = {}
        for i, s in ipairs(map_base_cache.filtered) do f[i] = idx[s] end
        local set_n = 0
        for s in pairs(map_base_cache.filtered_set) do set_n = set_n + 1 end
        local cells = {}
        for key, bucket in pairs(map_base_cache.spatial) do
          local b = {}
          for i, s in ipairs(bucket) do b[i] = idx[s] end
          cells[#cells + 1] = key .. ":" .. table.concat(b, ",")
        end
        table.sort(cells)
        local side = {}
        for i, s in ipairs(samples) do
          side[i] = table.concat({ tostring(s._render_color), tostring(s._folder_unavailable), tostring(s._lc_name),
            tostring(s._lc_path), tostring(s._lc_src_name), tostring(s._lc_src_path) }, "|")
        end
        return table.concat(f, ",") .. "#" .. set_n .. "#" .. map_base_cache.filtered_count .. "#" ..
          tostring(map_base_cache.duration_min) .. "#" .. tostring(map_base_cache.duration_max) .. "#" ..
          table.concat(cells, ";") .. "#" .. table.concat(side, ";") .. "#" .. tostring(map_base_cache.key)
      end
      local bad = 0
      local filters = { "", "k", "KICK", "ick_1", "/pack", "zzz", "é", ".wav" }
      for seed = 1, 6 do
        local base = make_library(700, seed)
        for i, s in ipairs(base) do
          if i % 9 == 0 then s.x = nil end
          if i % 5 == 0 then s.effective_duration = (i % 3) * 0.4 end
          if i % 4 == 0 then s.duration = i * 0.01 end
          if i % 13 == 0 then s.x = -1 elseif i % 17 == 0 then s.y = 2 end
          if i % 23 == 0 then s.channels = 1 end
        end
        state.folders = { "/Users/me/Samples" }
        state.folder_filter_paths = (seed % 2 == 0) and { "/Users/me/Samples/Lofi" } or nil
        state.missing_volumes = (seed % 3 == 0) and { ["/Volumes/Drive"] = true } or {}
        state.missing_scan_folders = (seed == 5) and { ["/Users/me/Samples"] = true } or {}
        for _, f in ipairs(filters) do
          local snaps = {}
          for pass = 1, 2 do
            local samples = {}
            for i, s in ipairs(base) do
              local c = {}
              for k, v in pairs(s) do c[k] = v end
              samples[i] = c
            end
            -- Stale memo fields on some samples, as after a rename.
            for i = 1, #samples, 7 do samples[i]._lc_src_name = "old"; samples[i]._lc_name = "old" end
            state.samples = samples
            state.filter = f
            if pass == 1 then REF_rebuild_map_base_cache() else rebuild_map_base_cache() end
            snaps[pass] = snapshot(samples)
          end
          if snaps[1] ~= snaps[2] then bad = bad + 1 end
        end
      end
      return bad
    ''')
    assert bad == 0


def test_dot_colors_match_original():
    L = _runtime()
    bad = L.execute(r'''
      local R = math.random
      math.randomseed(5)
      local tags = { "kick", "snare", "hat", "loop", "pad", "808s", "fx", "other", "Kick" }
      local bad = 0
      for round = 1, 6 do
        state.dot_color = ({ nil, 0x44AA55, 0xFF00FF, 0x123456, 16777215, 0 })[round]
        state.tag_colors = {}
        for _, t in ipairs(tags) do
          if R(1, 4) > 1 then state.tag_colors[t] = ({ R(0, 0xFFFFFF), R(0, 0xFFFFFF) + 0.5, 0xFFFFFF, 0, 1e7 })[R(1, 5)] end
        end
        for _, t in ipairs(tags) do TAG_KEYWORD_WEIGHT[t] = R(1, 3) == 1 and nil or R(1, 5) end
        for i = 1, 3000 do
          local s = { channels = ({ 1, 2, nil, 1.0 })[R(1, 4)] }
          if R(1, 5) > 1 then
            s.tags = {}
            for k = 1, R(0, 3) do s.tags[k] = tags[R(1, #tags)] end
          end
          local c = { channels = s.channels, tags = s.tags }
          local a, b = REF_get_sample_dot_color(s), get_sample_dot_color(c)
          if a ~= b or math.type(a) ~= math.type(b) or s._render_color ~= c._render_color then bad = bad + 1 end
        end
      end
      -- Many distinct base colours (memo eviction), mono and stereo.
      for i = 1, 5000 do
        state.dot_color = R(0, 0xFFFFFF)
        local s = { channels = (i % 2) + 1 }
        local c = { channels = s.channels }
        if REF_get_sample_dot_color(s) ~= get_sample_dot_color(c) then bad = bad + 1 end
      end
      if REF_get_sample_dot_color(nil) ~= get_sample_dot_color(nil) then bad = bad + 1 end
      return bad
    ''')
    assert bad == 0

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

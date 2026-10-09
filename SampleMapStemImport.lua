-- Stem-split backend used by Sample Map's sequencer file-drop import.
-- Finds StemSplit.py + .venv-stems, runs mix/drum split, and wraps the
-- drum-stem tempo-map / hit detector. Sequencer placement lives in the browser.

if not r then r = reaper end

SampleMapStemImport = SampleMapStemImport or {}

local AUDIO_EXTS = {
  wav = true, wave = true, aif = true, aiff = true,
  flac = true, mp3 = true, ogg = true, m4a = true, wv = true,
}

local MIX_ORDER = { "vocals", "drums", "bass", "guitar", "piano", "other" }
local DRUM_ORDER = { "kick", "snare", "toms", "hh", "ride", "crash" }

local function join_path(a, b)
  if not a or a == "" then return b end
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then
    return a .. b
  end
  return a .. "/" .. b
end

local function dirname(p)
  if not p or p == "" then return "" end
  return p:match("^(.*)[/\\][^/\\]-$") or ""
end

local function basename_no_ext(p)
  local name = p:match("([^/\\]+)$") or p
  return name:match("^(.*)%.[^%.]+$") or name
end

local function file_exists(path)
  if not path or path == "" then return false end
  if r.file_exists then
    return r.file_exists(path)
  end
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    return true
  end
  return false
end

local function shell_quote(s)
  s = tostring(s or ""):gsub("'", "'\\''")
  return "'" .. s .. "'"
end

local function sanitize_dir_name(s)
  s = tostring(s or "stems")
  s = s:gsub("[<>:\"/\\|?*]", "_")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then s = "stems" end
  return s
end

function SampleMapStemImport.is_audio_path(path)
  if not path or path == "" then return false end
  local ext = tostring(path):match("%.([^%.]+)$")
  if not ext then return false end
  return AUDIO_EXTS[ext:lower()] == true
end

local MIX_HINTS = {
  "vocal", "vocals", "vox", "voice", "acapella", "a cappella",
  "guitar", "gtr", "piano", "keys", "synth", "pad", "lead",
  "mixdown", "master", "full mix", "fullmix", "song",
  "instrumental", "instro",
}
local DRUM_LOOP_HINTS = {
  "drumloop", "drum-loop", "drum_loop", "drum loop",
  "drumkit", "drum-kit", "drum kit", "fullkit", "full kit",
  "breakbeat", "break beat", "perc loop", "percussion loop",
  "tops loop", "kit loop", "drums only", "drumsonly",
}

local function path_haystack(path)
  return tostring(path or ""):lower():gsub("\\", "/")
end

local function hay_has(hay, needle)
  if not hay or not needle or needle == "" then
    return false
  end
  if needle:find(" ", 1, true) then
    local compact = needle:gsub(" ", "")
    if hay:find(needle, 1, true) or hay:find(needle:gsub(" ", "_"), 1, true)
        or hay:find(needle:gsub(" ", "-"), 1, true) or hay:find(compact, 1, true) then
      return true
    end
    return false
  end
  return hay:find(needle, 1, true) ~= nil
end

function SampleMapStemImport.classify_source(path, opts)
  opts = opts or {}
  local hay = path_haystack(path)
  for i = 1, #MIX_HINTS do
    if hay_has(hay, MIX_HINTS[i]) then
      return "mix"
    end
  end
  for i = 1, #DRUM_LOOP_HINTS do
    if hay_has(hay, DRUM_LOOP_HINTS[i]) then
      return "drums"
    end
  end
  local tags = opts.tags
  if type(tags) == "table" then
    local drum, melodic, loopish = false, false, false
    for _, tag in ipairs(tags) do
      local t = tostring(tag or ""):lower()
      if t == "vocal" or t == "guitar" or t == "keys" or t == "lead"
          or t == "pad" or t == "pluck" or t == "piano" then
        melodic = true
      end
      if t == "drum" or t == "kick" or t == "snare" or t == "hat"
          or t == "tom" or t == "perc" or t == "ride" or t == "crash" then
        drum = true
      end
      if t == "loop" then
        loopish = true
      end
    end
    if melodic then
      return "mix"
    end
    if drum and (loopish or (opts.sample_type == "Drum")) then
      return "drums"
    end
    if opts.sample_type == "Drum" and not melodic then
      return "drums"
    end
  end
  local dur = tonumber(opts.duration) or 0.0
  if dur > 75.0 then
    return "mix"
  end
  return "auto"
end

function SampleMapStemImport.mix_order()
  return MIX_ORDER
end

function SampleMapStemImport.drum_order()
  return DRUM_ORDER
end

function SampleMapStemImport.find_backend()
  local scripts = join_path(r.GetResourcePath(), "Scripts")
  local dirs = {
    join_path(scripts, "Stem Split"),
    join_path(scripts, "Bryan's Scripts"),
    join_path(scripts, "BryanChi/Stem-Split"),
  }
  local sidecar, py, tempo
  for i = 1, #dirs do
    local dir = dirs[i]
    if not sidecar then
      local cand = join_path(dir, "StemSplit.py")
      if file_exists(cand) then sidecar = cand end
    end
    if not py then
      local cand = join_path(dir, ".venv-stems/bin/python")
      if file_exists(cand) then py = cand end
    end
    if not tempo then
      for _, name in ipairs({
        "Tempo map from drum stem.lua",
        "CRS_Tempo map from drum stem.lua",
      }) do
        local cand = join_path(dir, name)
        if file_exists(cand) then
          tempo = cand
          break
        end
      end
    end
  end
  return sidecar, py, tempo
end

function SampleMapStemImport.load_tempo_lib()
  -- Always re-load from disk. REAPER keeps Bryan_* globals across script
  -- restarts, so a cached detector/tempo-map would ignore file edits.
  Bryan_ApplyDrumStemTempoMap = nil
  Bryan_DetectDrumStemHits = nil
  local already = false
  local tempo_path = ""
  local loaded_ok = false
  local err_s = ""
  local _, _, tempo = SampleMapStemImport.find_backend()
  tempo_path = tostring(tempo or "")
  if not tempo then
    err_s = "Tempo map from drum stem.lua not found (install Stem Split)."
  else
    Bryan_DrumStemTempoMap_AsLib = true
    local ok, err = pcall(dofile, tempo)
    Bryan_DrumStemTempoMap_AsLib = nil
    if not ok then
      err_s = tostring(err)
    elseif type(Bryan_ApplyDrumStemTempoMap) ~= "function" then
      err_s = "Tempo map function was not exported."
    else
      loaded_ok = true
    end
  end
  if loaded_ok then
    return true
  end
  return false, err_s ~= "" and err_s or "Tempo map load failed."
end

function SampleMapStemImport.source_length(src)
  if not src then return 0.0 end
  local a, b = r.GetMediaSourceLength(src)
  if type(a) == "number" and a > 0 then return a end
  if type(b) == "number" and b > 0 then return b end
  return 0.0
end

function SampleMapStemImport.file_duration(path)
  if not path or not file_exists(path) then return 0.0 end
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then return 0.0 end
  local len = SampleMapStemImport.source_length(src)
  if r.PCM_Source_Destroy then
    r.PCM_Source_Destroy(src)
  end
  return len
end

function SampleMapStemImport.parse_manifest(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil, "Could not read manifest:\n" .. tostring(path)
  end
  local info = {
    ok = false,
    engine = "",
    model = "",
    warning = "",
    stems = {},
    drum_stems = {},
  }
  for line in fh:lines() do
    local kind, a, b = line:match("^([^|]+)|([^|]*)|(.*)$")
    if not kind then
      kind, a = line:match("^([^|]+)|(.*)$")
    end
    if kind == "OK" then
      info.ok = a == "1"
    elseif kind == "ENGINE" then
      info.engine = a or ""
    elseif kind == "MODEL" then
      info.model = a or ""
    elseif kind == "WARNING" then
      info.warning = a or ""
    elseif kind == "STEM" and a and b then
      info.stems[a] = b
    elseif kind == "DRUM" and a and b then
      info.drum_stems[a] = b
    end
  end
  fh:close()
  return info
end

local function read_progress(path)
  local f = io.open(path, "r")
  if not f then
    return 0, ""
  end
  local pct = tonumber((f:read("*l") or "0"):match("%d+")) or 0
  local msg = f:read("*l") or ""
  f:close()
  if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
  return pct, msg:gsub("[\r\n]", "")
end

local function read_done(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read("*a") or ""
  f:close()
  return tonumber(s:match("%-?%d+"))
end

local function spawn_detached(cmd)
  local line = "/bin/sh -c " .. shell_quote(cmd .. " >/dev/null 2>&1") .. " &"
  local rc = os.execute(line)
  return rc == true or rc == 0 or rc == nil
end

function SampleMapStemImport.job_paths(input_path)
  local parent = dirname(input_path)
  if parent == "" then
    parent = os.getenv("HOME") or "/tmp"
  end
  local out_dir = join_path(parent, sanitize_dir_name(basename_no_ext(input_path)) .. " stems")
  return {
    out_dir = out_dir,
    manifest = join_path(out_dir, "manifest.txt"),
    progress = join_path(out_dir, "_progress.txt"),
    done = join_path(out_dir, "_done.txt"),
    log = join_path(out_dir, "_run.log"),
  }
end

function SampleMapStemImport.start_split(input_path, opts)
  opts = opts or {}
  if (r.GetOS() or ""):match("Win") then
    return nil, "Stem split uses Demucs-MLX and is Mac / Apple Silicon only."
  end
  if not SampleMapStemImport.is_audio_path(input_path) then
    return nil, "Not an audio file."
  end
  if not file_exists(input_path) then
    return nil, "File not found:\n" .. tostring(input_path)
  end
  local sidecar, py = SampleMapStemImport.find_backend()
  if not py then
    return nil, "Stem-split Python environment not found (.venv-stems).\nInstall Stem Split, then create the venv next to StemSplit.py."
  end
  if not sidecar then
    return nil, "StemSplit.py not found. Install Stem Split into REAPER's Scripts folder."
  end

  local model = opts.model
  if not model or model == "" then
    model = r.GetExtState("BRYAN_STEM_SPLIT", "MODEL")
  end
  if not model or model == "" then
    model = "good"
  end

  local paths = SampleMapStemImport.job_paths(input_path)
  pcall(os.remove, paths.done)
  pcall(os.remove, paths.progress)
  if r.RecursiveCreateDirectory then
    r.RecursiveCreateDirectory(paths.out_dir, 0)
  end

  local duration = tonumber(opts.duration) or 0.0
  if duration <= 0 then
    duration = SampleMapStemImport.file_duration(input_path)
  end
  local start_off = tonumber(opts.start) or 0.0
  local shifts = math.floor(tonumber(opts.shifts) or 1)
  if shifts < 0 then shifts = 0 end
  if shifts > 8 then shifts = 8 end
  local overlap = tonumber(opts.overlap) or 0.25
  if overlap < 0 then overlap = 0.0 end
  if overlap >= 1 then overlap = 0.5 end

  local parts = {
    shell_quote(py),
    shell_quote(sidecar),
    "--input", shell_quote(input_path),
    "--output-dir", shell_quote(paths.out_dir),
    "--model", shell_quote(model),
    "--shifts", tostring(shifts),
    "--overlap", string.format("%.3f", overlap),
    "--start", string.format("%.6f", start_off),
    "--duration", string.format("%.6f", duration),
    "--progress-file", shell_quote(paths.progress),
    "--done-flag", shell_quote(paths.done),
    "--manifest", shell_quote(paths.manifest),
  }
  if opts.split_drums ~= false then
    parts[#parts + 1] = "--split-drums"
  end
  if opts.drums_only then
    parts[#parts + 1] = "--drums-only"
  elseif opts.auto_skip_mix ~= false then
    parts[#parts + 1] = "--auto-skip-mix"
  end
  local cmd = table.concat(parts, " ") .. " > " .. shell_quote(paths.log) .. " 2>&1"
  if not spawn_detached(cmd) then
    return nil, "Could not start StemSplit.py."
  end

  return {
    path = input_path,
    name = basename_no_ext(input_path),
    duration = duration,
    start = start_off,
    model = model,
    shifts = shifts,
    overlap = overlap,
    drums_only = opts.drums_only and true or false,
    auto_skip_mix = (opts.auto_skip_mix ~= false) and not opts.drums_only,
    split_drums = opts.split_drums ~= false,
    paths = paths,
    t0 = r.time_precise(),
    max_wait = 20 * 60,
  }
end

function SampleMapStemImport.poll(job)
  if not job or not job.paths then
    return "error", "No stem-split job."
  end
  if r.time_precise() - (job.t0 or 0) > (job.max_wait or 1200) then
    return "error", "Stem split timed out. The Python process may still be running."
  end
  local code = read_done(job.paths.done)
  if code == nil then
    local pct, msg = read_progress(job.paths.progress)
    return "running", pct, msg
  end
  if code ~= 0 then
    local log = ""
    local lf = io.open(job.paths.log, "r")
    if lf then
      log = lf:read("*a") or ""
      lf:close()
    end
    local tail = log ~= "" and log:sub(-2000) or ("See log:\n" .. job.paths.log)
    return "error", "Stem split failed (exit " .. tostring(code) .. ").\n\n" .. tail
  end
  local info, err = SampleMapStemImport.parse_manifest(job.paths.manifest)
  if not info or not info.ok then
    return "error", err or (info and info.warning) or "Stem split produced no output."
  end
  return "done", info
end

function SampleMapStemImport.insert_wav(track, wav_path, position)
  if not track or not wav_path or not file_exists(wav_path) then
    return nil, 0.0
  end
  local item = r.AddMediaItemToTrack(track)
  if not item then
    return nil, 0.0
  end
  local src = r.PCM_Source_CreateFromFile(wav_path)
  if not src then
    r.DeleteTrackMediaItem(track, item)
    return nil, 0.0
  end
  local take = r.AddTakeToMediaItem(item)
  if not take then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(src) end
    r.DeleteTrackMediaItem(track, item)
    return nil, 0.0
  end
  r.SetMediaItemTake_Source(take, src)
  local len = SampleMapStemImport.source_length(src)
  if len <= 0 then
    len = SampleMapStemImport.file_duration(wav_path)
  end
  if len <= 0 then len = 1.0 end
  r.SetMediaItemPosition(item, position or 0.0, false)
  r.SetMediaItemLength(item, len, false)
  r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  r.SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", 0)
  if r.SetMediaItemTakeInfo_Value then
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.0)
  end
  return item, len
end

local MIX_STEM_LABEL = {
  vocals = "Vocals",
  drums = "Drums",
  bass = "Bass",
  guitar = "Guitar",
  piano = "Piano",
  other = "Other",
}

function SampleMapStemImport.item_guid(item)
  if not item or not r.GetSetMediaItemInfo_String then
    return nil
  end
  local ok, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
  if type(guid) == "string" and guid ~= "" then
    return guid
  end
  if ok and type(ok) == "string" and ok ~= "" then
    return ok
  end
  return nil
end

function SampleMapStemImport.find_item_by_guid(guid)
  if not guid or guid == "" then
    return nil
  end
  local n = r.CountMediaItems(0)
  for i = 0, n - 1 do
    local item = r.GetMediaItem(0, i)
    if item and SampleMapStemImport.item_guid(item) == guid then
      return item
    end
  end
  return nil
end

function SampleMapStemImport.mute_item(item)
  if not item then
    return false
  end
  r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
  if r.UpdateItemInProject then
    r.UpdateItemInProject(item)
  end
  return true
end

-- Place mix stems (vocals/bass/guitar/piano/other) on new tracks after the
-- source item. Skip drums when the sequencer already reconstructed the kit.
function SampleMapStemImport.place_instrument_stems(stems, opts)
  opts = opts or {}
  if type(stems) ~= "table" then
    return 0
  end
  local skip_drums = opts.skip_drums == true
  local place_time = tonumber(opts.place_time) or 0.0
  local source_item = opts.source_item
  local order = SampleMapStemImport.mix_order()
  local to_place = {}
  for i = 1, #order do
    local key = order[i]
    if not (skip_drums and key == "drums") then
      local wav = stems[key]
      if wav and file_exists(wav) then
        to_place[#to_place + 1] = { key = key, path = wav }
      end
    end
  end
  if #to_place == 0 then
    return 0
  end

  local insert_at = r.CountTracks(0)
  if source_item then
    local src_tr = r.GetMediaItem_Track(source_item)
    if src_tr then
      local num = tonumber(r.GetMediaTrackInfo_Value(src_tr, "IP_TRACKNUMBER")) or 0
      if num > 0 then
        insert_at = math.floor(num)
      end
    end
  end

  local placed = 0
  for i = 1, #to_place do
    local rec = to_place[i]
    r.InsertTrackAtIndex(insert_at, true)
    local tr = r.GetTrack(0, insert_at)
    if tr then
      local label = MIX_STEM_LABEL[rec.key] or rec.key
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", label, true)
      local item = SampleMapStemImport.insert_wav(tr, rec.path, place_time)
      if item then
        placed = placed + 1
      end
      insert_at = insert_at + 1
    end
  end
  if r.TrackList_AdjustWindows then
    r.TrackList_AdjustWindows(false)
  end
  return placed
end

function SampleMapStemImport.merge_close_hits(onsets, key)
  if type(onsets) ~= "table" or #onsets == 0 then
    return onsets or {}, 0, 0
  end
  local sorted = {}
  for i = 1, #onsets do
    sorted[i] = onsets[i]
  end
  table.sort(sorted, function(a, b)
    return (a.time or 0) < (b.time or 0)
  end)
  -- At ~143 BPM a 16th is ~105ms; hard-merge stays under that.
  -- Click+body doubles on this kit were ~87–96ms with equal weights, so
  -- weight-ratio gating alone missed them (lo/hi ≈ 1.0).
  local gaps = {
    kick = 0.100,
    snare = 0.070,
    toms = 0.080,
    hh = 0.040,
    ride = 0.070,
    crash = 0.120,
    drums = 0.070,
  }
  local gap = gaps[key] or 0.070
  local weak_gap, weak_frac = 0, 0
  if key == "kick" then
    weak_gap = 0.112
    weak_frac = 0.82
  end
  local min_dt = 0
  local close_n = 0
  if #sorted >= 2 then
    min_dt = 1e9
    for i = 2, #sorted do
      local dt = (sorted[i].time or 0) - (sorted[i - 1].time or 0)
      if dt < min_dt then
        min_dt = dt
      end
      if dt < gap then
        close_n = close_n + 1
      end
    end
  end
  local out = { sorted[1] }
  local merged = 0
  for i = 2, #sorted do
    local cur = sorted[i]
    local prev = out[#out]
    local dt = (cur.time or 0) - (prev.time or 0)
    if dt < gap then
      merged = merged + 1
      local cw = tonumber(cur.weight) or tonumber(cur.raw) or 0
      local pw = tonumber(prev.weight) or tonumber(prev.raw) or 0
      if cw > pw then
        prev.weight = cw
      end
    elseif weak_gap > 0 and dt < weak_gap then
      local cw = tonumber(cur.weight) or tonumber(cur.raw) or 0
      local pw = tonumber(prev.weight) or tonumber(prev.raw) or 0
      local lo = cw
      local hi = pw
      if lo > hi then
        lo = pw
        hi = cw
      end
      if hi > 1e-9 and lo < hi * weak_frac then
        merged = merged + 1
        if cw > pw then
          prev.weight = cw
        end
      else
        out[#out + 1] = cur
      end
    else
      out[#out + 1] = cur
    end
  end
  local out_min = 0
  if #out >= 2 then
    out_min = 1e9
    for i = 2, #out do
      local dt = (out[i].time or 0) - (out[i - 1].time or 0)
      if dt < out_min then
        out_min = dt
      end
    end
  end
  return out, merged, min_dt
end

function SampleMapStemImport.install_browser_hooks()
  seq_stem_merge_close_hits = SampleMapStemImport.merge_close_hits
end

function SampleMapStemImport.detect_hits(item, opts)
  local ok, err = SampleMapStemImport.load_tempo_lib()
  if not ok then
    return nil, err
  end
  if type(Bryan_DetectDrumStemHits) ~= "function" then
    return nil, "Hit detector was not exported."
  end
  local onsets, extra = Bryan_DetectDrumStemHits(item, opts)
  if not onsets then
    return nil, extra
  end
  local stats = (type(extra) == "table") and extra or nil
  return onsets, stats
end

function SampleMapStemImport.tempo_map(item)
  local ok, err = SampleMapStemImport.load_tempo_lib()
  if not ok then
    return false, err
  end
  return Bryan_ApplyDrumStemTempoMap(item, { quiet = true })
end

SampleMapStemImport.EXT_SECTION = "SampleMapStemImport"
SampleMapStemImport.EXT_REQUEST = "request"
SampleMapStemImport.EXT_PREFS = "BRYAN_STEM_SPLIT"

local function stem_pref_get(key, default)
  local v = r.GetExtState(SampleMapStemImport.EXT_PREFS, key)
  if v and v ~= "" then
    return v
  end
  v = r.GetExtState(SampleMapStemImport.EXT_SECTION, key)
  if v and v ~= "" then
    return v
  end
  return default
end

local function stem_pref_set(key, value)
  r.SetExtState(SampleMapStemImport.EXT_PREFS, key, tostring(value or ""), true)
  r.SetExtState(SampleMapStemImport.EXT_SECTION, key, tostring(value or ""), true)
end

function SampleMapStemImport.yn(s, default_true)
  if s == true then
    return true
  end
  if s == false then
    return false
  end
  if s == nil or s == "" then
    return default_true ~= false
  end
  s = tostring(s):lower()
  if s == "y" or s == "yes" or s == "1" or s == "true" then
    return true
  end
  if s == "n" or s == "no" or s == "0" or s == "false" then
    return false
  end
  return default_true ~= false
end

function SampleMapStemImport.load_prefs()
  local source = stem_pref_get("SOURCE", "auto")
  if source ~= "auto" and source ~= "mix" and source ~= "drums" then
    source = "auto"
  end
  local model = stem_pref_get("MODEL", "good")
  if model ~= "fast" and model ~= "good" and model ~= "6stem"
      and model ~= "htdemucs" and model ~= "htdemucs_ft" and model ~= "htdemucs_6s" then
    model = "good"
  end
  local nshifts = math.floor(tonumber(stem_pref_get("SHIFTS", "2")) or 2)
  if nshifts < 1 then nshifts = 1 end
  if nshifts > 4 then nshifts = 4 end
  local noverlap = tonumber(stem_pref_get("OVERLAP", "0.25")) or 0.25
  if noverlap < 0 then noverlap = 0.0 end
  if noverlap > 0.5 then noverlap = 0.5 end
  return {
    model = model,
    source = source,
    shifts = nshifts,
    overlap = noverlap,
    split_drums = SampleMapStemImport.yn(stem_pref_get("SPLIT_DRUMS", "y"), true),
    place_mix_stems = SampleMapStemImport.yn(stem_pref_get("PLACE_STEMS", "y"), true),
    mute_original = SampleMapStemImport.yn(stem_pref_get("MUTE_ORIGINAL", "y"), true),
    tempo_map = SampleMapStemImport.yn(stem_pref_get("TEMPO_MAP", "y"), true),
    drums_only = source == "drums",
    auto_skip_mix = source == "auto",
  }
end

function SampleMapStemImport.save_prefs(opts)
  if type(opts) ~= "table" then
    return
  end
  if opts.model then
    stem_pref_set("MODEL", opts.model)
  end
  if opts.source then
    stem_pref_set("SOURCE", opts.source)
  end
  if opts.shifts then
    stem_pref_set("SHIFTS", tostring(opts.shifts))
  end
  if opts.overlap then
    stem_pref_set("OVERLAP", string.format("%.2f", opts.overlap))
  end
  if opts.split_drums ~= nil then
    stem_pref_set("SPLIT_DRUMS", opts.split_drums and "y" or "n")
  end
  if opts.place_mix_stems ~= nil then
    stem_pref_set("PLACE_STEMS", opts.place_mix_stems and "y" or "n")
  end
  if opts.mute_original ~= nil then
    stem_pref_set("MUTE_ORIGINAL", opts.mute_original and "y" or "n")
  end
  if opts.tempo_map ~= nil then
    stem_pref_set("TEMPO_MAP", opts.tempo_map and "y" or "n")
  end
end

function SampleMapStemImport.ask_options()
  return SampleMapStemImport.load_prefs()
end

function SampleMapStemImport.encode_request(fields)
  local keys = {}
  for k, v in pairs(fields or {}) do
    if v ~= nil and v ~= "" then
      keys[#keys + 1] = tostring(k)
    end
  end
  table.sort(keys)
  local lines = {}
  for i = 1, #keys do
    local k = keys[i]
    local v = tostring(fields[k]):gsub("[\r\n]", " ")
    lines[#lines + 1] = k .. "=" .. v
  end
  return table.concat(lines, "\n")
end

function SampleMapStemImport.decode_request(raw)
  local fields = {}
  for line in tostring(raw or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k and k ~= "" then
      fields[k] = v
    end
  end
  return fields
end

function SampleMapStemImport.write_request(fields)
  r.SetExtState(
    SampleMapStemImport.EXT_SECTION,
    SampleMapStemImport.EXT_REQUEST,
    SampleMapStemImport.encode_request(fields),
    false
  )
end

function SampleMapStemImport.take_request()
  local raw = r.GetExtState(SampleMapStemImport.EXT_SECTION, SampleMapStemImport.EXT_REQUEST)
  if not raw or raw == "" then
    return nil
  end
  r.DeleteExtState(SampleMapStemImport.EXT_SECTION, SampleMapStemImport.EXT_REQUEST, false)
  local fields = SampleMapStemImport.decode_request(raw)
  if not fields.path or fields.path == "" then
    return nil
  end
  fields.start = tonumber(fields.start) or 0.0
  fields.duration = tonumber(fields.duration) or 0.0
  fields.place_time = tonumber(fields.place_time)
  fields.shifts = tonumber(fields.shifts)
  fields.overlap = tonumber(fields.overlap)
  if fields.model == "" then
    fields.model = nil
  end
  if fields.source == "" then
    fields.source = nil
  end
  if fields.split_drums ~= nil then
    fields.split_drums = SampleMapStemImport.yn(fields.split_drums, true)
  end
  if fields.place_mix_stems ~= nil then
    fields.place_mix_stems = SampleMapStemImport.yn(fields.place_mix_stems, true)
  end
  if fields.mute_original ~= nil then
    fields.mute_original = SampleMapStemImport.yn(fields.mute_original, true)
  end
  if fields.tempo_map ~= nil then
    fields.tempo_map = SampleMapStemImport.yn(fields.tempo_map, true)
  end
  if fields.source == "drums" then
    fields.drums_only = true
    fields.auto_skip_mix = false
  elseif fields.source == "mix" then
    fields.drums_only = false
    fields.auto_skip_mix = false
  elseif fields.source == "auto" then
    fields.auto_skip_mix = true
  end
  return fields
end

function SampleMapStemImport.take_source_file(take)
  if not take then
    return nil
  end
  if r.TakeIsMIDI and r.TakeIsMIDI(take) then
    return nil
  end
  local src = r.GetMediaItemTake_Source(take)
  if not src then
    return nil
  end
  if r.GetMediaSourceParent then
    local guard = 0
    while src and guard < 8 do
      local parent = r.GetMediaSourceParent(src)
      if not parent then
        break
      end
      src = parent
      guard = guard + 1
    end
  end
  if not r.GetMediaSourceFileName then
    return nil
  end
  local a, b = r.GetMediaSourceFileName(src, "")
  if type(b) == "string" and b ~= "" then
    return b
  end
  if type(a) == "string" and a ~= "" then
    return a
  end
  return nil
end

function SampleMapStemImport.selected_item_audio()
  local item = r.GetSelectedMediaItem(0, 0)
  if not item then
    return nil, "Select an audio item first."
  end
  local take = r.GetActiveTake(item)
  if not take then
    return nil, "The selected item has no take."
  end
  if r.TakeIsMIDI and r.TakeIsMIDI(take) then
    return nil, "The selected item is MIDI. Select an audio item."
  end
  local path = SampleMapStemImport.take_source_file(take)
  if not path or path == "" then
    return nil, "Could not read the selected item's audio file."
  end
  if not SampleMapStemImport.is_audio_path(path) then
    return nil, "The selected item is not a supported audio file."
  end
  local start_off = 0.0
  if r.GetMediaItemTakeInfo_Value then
    start_off = tonumber(r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")) or 0.0
  end
  local item_len = tonumber(r.GetMediaItemInfo_Value(item, "D_LENGTH")) or 0.0
  local playrate = 1.0
  if r.GetMediaItemTakeInfo_Value then
    playrate = tonumber(r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")) or 1.0
  end
  if playrate < 0.0001 then
    playrate = 1.0
  end
  local duration = item_len * playrate
  if duration <= 0 then
    duration = SampleMapStemImport.file_duration(path)
  end
  local place_time = tonumber(r.GetMediaItemInfo_Value(item, "D_POSITION")) or 0.0
  local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local name = (take_name and take_name ~= "" and take_name)
    or basename_no_ext(path)
  return {
    path = path,
    start = math.max(0.0, start_off),
    duration = math.max(0.05, duration),
    place_time = place_time,
    name = name,
    item = item,
    take = take,
    guid = SampleMapStemImport.item_guid(item),
  }
end

function SampleMapStemImport.sample_map_is_running()
  -- The browser stores a per-instance token (formerly "1") while running.
  local alive = r.GetExtState("SampleMapBrowser", "alive")
  if not alive or alive == "" then
    return false
  end
  if r.JS_Window_Find then
    local hwnd = r.JS_Window_Find("Sample Map Browser", true)
    if hwnd then
      return true
    end
    -- Flag can linger after a crash; treat missing window as not running.
    return false
  end
  return true
end

function SampleMapStemImport.launch_sample_map(script_dir)
  local browser = join_path(script_dir, "Sample Map Browser.lua")
  if not file_exists(browser) then
    return false, "Sample Map Browser.lua was not found next to this script."
  end
  if not r.AddRemoveReaScript then
    return false, "Could not register Sample Map Browser (AddRemoveReaScript missing)."
  end
  local cmd = r.AddRemoveReaScript(true, 0, browser, true)
  if not cmd or cmd == 0 then
    return false, "Could not add Sample Map Browser to the action list."
  end
  r.Main_OnCommand(cmd, 0)
  return true
end

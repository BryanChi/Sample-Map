-- Sample Map Browser module: scanning
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Scanning and analysis ---------------------------------------------------
function sample_analysis_incomplete(sample)
  if not sample or not sample.path then
    return false
  end
  -- Full analyzer pass fills freq, brightness, weight, rms, audible length, and loop/one-shot together.
  if sample.dominant_freq == nil or sample.rms_energy == nil then
    return true
  end
  if sample.brightness == nil or sample.sub_weight == nil then
    return true
  end
  if type(sample.effective_duration) ~= "number" or sample.effective_duration <= 0 then
    return true
  end
  if sample.playback_type == nil then
    return true
  end
  return false
end

function sample_analysis_missing_fields(sample)
  local missing = {}
  if not sample then
    return missing
  end
  if sample.dominant_freq == nil then missing[#missing + 1] = "dominant_freq" end
  if sample.rms_energy == nil then missing[#missing + 1] = "rms_energy" end
  if sample.brightness == nil then missing[#missing + 1] = "brightness" end
  if sample.sub_weight == nil then missing[#missing + 1] = "sub_weight" end
  if type(sample.effective_duration) ~= "number" or sample.effective_duration <= 0 then
    missing[#missing + 1] = "effective_duration"
  end
  if sample.playback_type == nil then missing[#missing + 1] = "playback_type" end
  return missing
end

function analyzer_data_has_fields(data)
  if type(data) ~= "table" then
    return false
  end
  return data.dominant_freq ~= nil
    or data.rms_energy ~= nil
    or data.brightness ~= nil
    or data.sub_weight ~= nil
    or data.effective_duration ~= nil
    or data.playback_type ~= nil
    or data.onset ~= nil
    or data.transient_end ~= nil
end

-- Drum one-shots only (not loops, FX, or melodic instruments).
-- Global: main chunk is near Lua's 200-local limit (see header comment).
DRUM_TRANSIENT_TAGS = {
  kick = true, snare = true, clap = true, snap = true, rim = true,
  hat = true, tom = true, ride = true, crash = true, perc = true,
  drum = true, ["808"] = true, ["808s"] = true,
}

function sample_is_drum_oneshot(sample)
  if not sample then
    return false
  end
  local tags = sample.tags or {}
  local has_drum = sample.sample_type == "Drum"
  local has_loop = false
  for _, tag in ipairs(tags) do
    local lower = string.lower(tostring(tag))
    if lower == "loop" then
      has_loop = true
    end
    if DRUM_TRANSIENT_TAGS[lower] then
      has_drum = true
    end
  end
  if has_loop then
    return false
  end
  local loopish = detect_loop_or_oneshot(sample.path or "", sample.folder or "", sample.playback_type)
  if loopish == "loop" then
    return false
  end
  return has_drum
end

function sample_transient_incomplete(sample)
  if not sample_is_drum_oneshot(sample) then
    return false
  end
  return type(sample.transient_end) ~= "number" or sample.transient_end <= 0
end

function enqueue_analyzer_paths(predicate, empty_msg, queued_log)
  state.external_disabled = false
  state.analyzer_warned = false
  state.analyzer_path_mode = state.analyzer_path_mode or {}

  local already = {}
  for _, path in ipairs(state.analyzer_queue) do
    already[path] = true
  end
  for _, proc in ipairs(state.active_processes) do
    if proc.path then
      already[proc.path] = true
    end
  end

  local added = 0
  for _, sample in ipairs(state.samples) do
    if predicate(sample) then
      local path = normalize_path(sample.path)
      if path ~= "" and not already[path] and not sample_scan_folder_unavailable(sample) then
        table.insert(state.analyzer_queue, path)
        already[path] = true
        if state.analyzer_path_mode then
          state.analyzer_path_mode[path] = state.analyzer_mode
        end
        added = added + 1
      end
    end
  end

  local pending = #state.analyzer_queue + #state.active_processes
  if pending == 0 then
    sm_notify(empty_msg)
    add_scan_log(queued_log .. ": nothing to analyze")
    return 0
  end

  state.incomplete_analysis_total = pending
  if state.scan_started <= 0 then
    state.scan_started = r.time_precise()
  end
  state.scan_running = true
  state._pending_layout = true

  log(string.format("Queued %d sample(s) for analysis (%d total pending)", added, pending))
  add_scan_log(string.format("%s: queued %d sample(s)", queued_log, added))
  begin_scan_session(state.analyzer_job_label or queued_log or "Analysis", {
    queued = pending,
  })
  return added
end

function enqueue_incomplete_analysis()
  state.analyzer_job_label = "Analyzing incomplete"
  state.external_disabled = false
  state.analyzer_warned = false
  state.analyzer_path_mode = state.analyzer_path_mode or {}
  state.analyzer_mode = nil

  local already = {}
  for _, path in ipairs(state.analyzer_queue) do
    already[path] = true
  end
  for _, proc in ipairs(state.active_processes) do
    if proc.path then
      already[proc.path] = true
    end
  end

  local added = 0
  for _, sample in ipairs(state.samples) do
    if sample.path and not sample_scan_folder_unavailable(sample) then
      local path = normalize_path(sample.path)
      if path ~= "" and not already[path] then
        local mode = nil
        local need = false
        if sample_analysis_incomplete(sample) then
          need = true
          mode = nil
        elseif sample_transient_incomplete(sample) then
          need = true
          mode = "transient"
        end
        if need then
          table.insert(state.analyzer_queue, path)
          already[path] = true
          state.analyzer_path_mode[path] = mode
          added = added + 1
        end
      end
    end
  end

  local pending = #state.analyzer_queue + #state.active_processes
  if pending == 0 then
    sm_notify("No incomplete samples: everything is analyzed")
    add_scan_log("Incomplete scan: nothing to analyze")
    return 0
  end

  state.incomplete_analysis_total = pending
  if state.scan_started <= 0 then
    state.scan_started = r.time_precise()
  end
  state.scan_running = true
  state._pending_layout = true
  log(string.format("Queued %d sample(s) for analysis (%d total pending)", added, pending))
  add_scan_log(string.format("Incomplete scan: queued %d sample(s)", added))
  begin_scan_session("Incomplete analysis", {
    queued = pending,
    incomplete_files = added,
  })
  return added
end

-- The per-field Re-analyze items all recompute that data for every sample
-- they apply to (use them after an analyzer change); "Incomplete Samples"
-- is the one that only fills in what is missing.
function sample_has_path(sample)
  return sample and sample.path and true or false
end

function enqueue_effective_range_analysis()
  state.analyzer_job_label = "Scanning effective range"
  state.analyzer_mode = nil
  return enqueue_analyzer_paths(
    sample_has_path,
    "No samples to re-analyze",
    "Effective range scan"
  )
end

function enqueue_transient_sustain_analysis()
  state.analyzer_job_label = "Scanning transient/sustain"
  state.analyzer_mode = "transient"
  return enqueue_analyzer_paths(
    function(sample)
      return sample_has_path(sample) and sample_is_drum_oneshot(sample)
    end,
    "No drum one-shots to re-analyze (none tagged as drums)",
    "Transient/sustain scan"
  )
end

function enqueue_playback_type_analysis()
  state.analyzer_job_label = "Classifying loop / one-shot"
  state.analyzer_mode = nil
  return enqueue_analyzer_paths(
    sample_has_path,
    "No samples to re-analyze",
    "Loop/one-shot scan"
  )
end

function enqueue_weight_analysis()
  state.analyzer_job_label = "Scanning weight"
  state.analyzer_mode = "weight"
  return enqueue_analyzer_paths(
    sample_has_path,
    "No samples to re-analyze",
    "Weight scan"
  )
end

-- Folder enumeration for scans is time-sliced (see sm_scan_enum_step) so large
-- libraries don't freeze the UI. process_scan_slice waits until it has finished.
function sm_scan_enum_file(enum, dir, file)
  local ext = file:match("%.([^%.]+)$")
  if not ext or not AUDIO_EXTS["." .. ext:lower()] then
    return
  end
  local normalized_full_path = normalize_path(dir .. "/" .. file)
  enum.seen[normalized_full_path] = true
  local existing = samples_by_path[normalized_full_path]
  if not existing then
    existing = samples_by_path[path_index_key(normalized_full_path)]
  end
  if not existing then
    if not enum.queued[normalized_full_path] then
      enum.queued[normalized_full_path] = true
      enum.paths[#enum.paths + 1] = normalized_full_path
    end
    return
  end
  local function queue_existing(sample, mode)
    local path = normalize_path(sample.path)
    if path == "" or enum.already[path] then
      return false
    end
    table.insert(state.analyzer_queue, path)
    enum.already[path] = true
    state.analyzer_path_mode = state.analyzer_path_mode or {}
    state.analyzer_path_mode[path] = mode
    return true
  end
  local size, mtime = file_identity(normalized_full_path)
  if sample_file_changed(existing, size, mtime) then
    stamp_sample_file_id(existing, size, mtime)
    clear_sample_analysis_fields(existing)
    refresh_sample_file_meta(existing, normalized_full_path)
    if queue_existing(existing, nil) then
      enum.reanalyze = enum.reanalyze + 1
    else
      enum.skipped = enum.skipped + 1
    end
  else
    stamp_sample_file_id(existing, size, mtime)
    if sample_analysis_incomplete(existing) then
      if queue_existing(existing, nil) then
        enum.incomplete = enum.incomplete + 1
      else
        enum.skipped = enum.skipped + 1
      end
    elseif sample_transient_incomplete(existing) then
      if queue_existing(existing, "transient") then
        enum.incomplete = enum.incomplete + 1
      else
        enum.skipped = enum.skipped + 1
      end
    else
      enum.skipped = enum.skipped + 1
    end
  end
end

function sm_scan_enum_error(enum, where, err)
  enum.errors = (enum.errors or 0) + 1
  if enum.errors <= 20 then
    add_scan_log(string.format("Scan error (%s): %s", tostring(where), tostring(err)))
  end
end

-- Process queued directories until the time budget runs out.
-- Returns true when enumeration has finished (or none is running).
function sm_scan_enum_step(max_ms)
  local enum = state.scan_enum
  if not enum then
    return true
  end
  local deadline = r.time_precise() + (max_ms or 12.0) / 1000.0
  repeat
    if not enum.cur_dir then
      local dir = table.remove(enum.stack)
      if not dir then
        sm_scan_enum_finish()
        return true
      end
      enum.dirs_done = (enum.dirs_done or 0) + 1
      -- Index -1 makes REAPER drop its cached listing so new files show up.
      local ok, err = pcall(function()
        r.EnumerateFiles(dir, -1)
        r.EnumerateSubdirectories(dir, -1)
        local subs = {}
        local i = 0
        local sub = r.EnumerateSubdirectories(dir, i)
        while sub do
          subs[#subs + 1] = dir .. "/" .. sub
          i = i + 1
          sub = r.EnumerateSubdirectories(dir, i)
        end
        for k = #subs, 1, -1 do
          enum.stack[#enum.stack + 1] = subs[k]
        end
      end)
      if not ok then
        sm_scan_enum_error(enum, dir, err)
      end
      enum.cur_dir = dir
      enum.file_idx = 0
    else
      local dir = enum.cur_dir
      local ok_enum, file = pcall(r.EnumerateFiles, dir, enum.file_idx)
      if not ok_enum then
        sm_scan_enum_error(enum, dir, file)
        file = nil
      end
      if not file then
        enum.cur_dir = nil
      else
        enum.file_idx = enum.file_idx + 1
        local ok, err = pcall(sm_scan_enum_file, enum, dir, file)
        if not ok then
          sm_scan_enum_error(enum, dir .. "/" .. tostring(file), err)
        end
      end
    end
  until r.time_precise() >= deadline
  return false
end

-- Drop library entries whose files are gone, but only under scan folders that
-- were listed in full just now and are reachable (an unmounted drive or an
-- offline folder never loses its samples). Each candidate is also checked with
-- file_exists, so a path the listing spelled differently is never dropped.
function sm_scan_prune_missing(enum)
  local roots = {}
  for _, root in ipairs(enum.roots or {}) do
    if scan_folder_path_exists(root) then
      roots[#roots + 1] = root
    end
  end
  if #roots == 0 then
    return 0
  end
  local kept, gone = {}, {}
  for _, sample in ipairs(state.samples) do
    local p = sample.path and normalize_path(sample.path)
    local drop = false
    if p and p ~= "" and not enum.seen[p] then
      for i = 1, #roots do
        if sample_under_scan_folder(p, roots[i]) then
          drop = not r.file_exists(p)
          break
        end
      end
    end
    if drop then
      gone[#gone + 1] = p
    else
      kept[#kept + 1] = sample
    end
  end
  if #gone == 0 then
    return 0
  end
  state.samples = kept
  rebuild_samples_path_index()
  rebuild_tag_index()
  state._pending_layout = true
  for i = 1, math.min(#gone, 20) do
    add_scan_log("Removed missing file: " .. gone[i])
  end
  add_scan_log(string.format("Removed %d missing file(s) from the library", #gone))
  sm_notify(string.format("Removed %d missing file%s from the library", #gone, #gone == 1 and "" or "s"))
  return #gone
end

function sm_scan_enum_finish()
  local enum = state.scan_enum
  if not enum then
    return
  end
  state.scan_enum = nil
  local paths = enum.paths
  local base_total = 0
  if #state.scan_queue > 0 then
    base_total = math.max(tonumber(state.scan_total) or 0, #state.scan_queue)
  end
  for i = 1, #paths do
    state.scan_queue[#state.scan_queue + 1] = paths[i]
  end
  local skipped_count, reanalyze_count, incomplete_count = enum.skipped, enum.reanalyze, enum.incomplete
  state.scan_total = base_total + #paths + skipped_count + reanalyze_count + incomplete_count
  if not (state.scan_started and state.scan_started > 0) then
    state.scan_started = r.time_precise()
  end
  state.scan_running = true
  state.last_save_time = r.time_precise()
  if enum.errors and enum.errors > 0 then
    add_scan_log(string.format("Folder enumeration hit %d error(s)", enum.errors))
  else
    sm_scan_prune_missing(enum)
  end

  local folder_label = enum.folder_label
  if folder_label then
    add_scan_log(string.format(
      "Folder rescan: %s (%d new, %d changed, %d incomplete, %d unchanged)",
      folder_label, #paths, reanalyze_count, incomplete_count, skipped_count
    ))
    log(string.format("Rescanning folder (%d new file(s)): %s", #paths, folder_label))
  else
    add_scan_log(string.format(
      "Scan started: %d new, %d changed, %d incomplete, %d unchanged",
      #paths, reanalyze_count, incomplete_count, skipped_count
    ))
    log(string.format("Scan started: %d new file(s), %d already indexed", #paths, skipped_count))
  end
  local session = state.scan_session
  if enum.appending and type(session) == "table" then
    session.new_files = (session.new_files or 0) + #paths
    session.changed_files = (session.changed_files or 0) + reanalyze_count
    session.incomplete_files = (session.incomplete_files or 0) + incomplete_count
    session.unchanged_files = (session.unchanged_files or 0) + skipped_count
    session.queued = (session.queued or 0) + reanalyze_count + incomplete_count
    if not session.started_at then
      session.started_at = r.time_precise()
    end
  else
    begin_scan_session(folder_label and "Folder rescan" or "Library scan", {
      detail = folder_label,
      new_files = #paths,
      changed_files = reanalyze_count,
      incomplete_files = incomplete_count,
      unchanged_files = skipped_count,
      queued = reanalyze_count + incomplete_count,
    })
  end
end

-- folder_only: nil (all folders), one folder path, or a list of folder paths.
-- New files are appended (deduplicated) to any pending scan_queue.
function enqueue_scan(folder_only)
  local folders_to_scan = state.folders
  local folder_label = nil
  if type(folder_only) == "table" then
    folders_to_scan = folder_only
    if #folder_only == 1 then
      folder_label = normalize_path(folder_only[1])
    elseif #folder_only > 1 then
      folder_label = string.format("%d new folder(s)", #folder_only)
    end
  elseif folder_only and folder_only ~= "" then
    folders_to_scan = { normalize_path(folder_only) }
    folder_label = folder_only
  end

  local enum = state.scan_enum
  if not enum then
    state.debug_count = 0  -- Reset debug counter for new scan
    state.external_disabled = false
    state.analyzer_warned = false
    state.analyzer_path_mode = state.analyzer_path_mode or {}
    rebuild_samples_path_index()

    enum = {
      stack = {},
      paths = {},
      queued = {},
      already = {},
      seen = {},
      roots = {},
      skipped = 0,
      reanalyze = 0,
      incomplete = 0,
      errors = 0,
      folder_label = folder_label,
      appending = #state.scan_queue > 0
        or (state.scan_running and (#state.analyzer_queue > 0 or #state.active_processes > 0)),
    }
    for _, path in ipairs(state.analyzer_queue) do
      enum.already[path] = true
    end
    for _, w in ipairs(state.analyzer_workers or {}) do
      if w.path then
        enum.already[w.path] = true
      end
    end
    for _, path in ipairs(state.scan_queue) do
      enum.queued[path] = true
    end
    state.scan_enum = enum
    add_scan_log(folder_label and ("Listing files in " .. folder_label .. "…") or "Listing files in library folders…")
  elseif enum.folder_label ~= folder_label then
    enum.folder_label = (enum.folder_label and folder_label) and "several folders" or nil
  end

  for i = #folders_to_scan, 1, -1 do
    local folder = normalize_path(folders_to_scan[i])
    if folder and folder ~= "" then
      enum.stack[#enum.stack + 1] = folder
      enum.roots[#enum.roots + 1] = folder
    end
  end

  -- Keep the menu in "scanning" state while files are listed; process_scan_slice
  -- does no queue work or finalize until sm_scan_enum_finish has run.
  state.scan_running = true
end

function scan_is_active()
  if not state.scan_running then
    return false
  end
  if #state.scan_queue > 0 then
    return true
  end
  if (state.incomplete_analysis_total or 0) > 0
      and (#state.analyzer_queue > 0 or #state.active_processes > 0) then
    return true
  end
  return false
end

function start_scan(folder_only)
  if state.scan_enum and (not folder_only or folder_only == "") then
    return -- already listing library folders
  end
  local resume = (not folder_only or folder_only == "")
    and (#state.scan_queue > 0 or #state.analyzer_queue > 0 or #state.active_processes > 0)
  if resume then
    state.scan_running = true
    state.scan_started = r.time_precise()
    state.external_disabled = false
    local msg = string.format(
      "Continuing scan: %d file(s) left, %d already indexed",
      #state.scan_queue,
      #state.samples
    )
    add_scan_log(msg)
    log(msg)
    if state.scan_session then
      state.scan_session.started_at = r.time_precise()
    else
      begin_scan_session("Continued scan", {
        queued = #state.scan_queue + #state.analyzer_queue + #state.active_processes,
      })
    end
    return
  end
  enqueue_scan(folder_only)
end

function stop_scan()
  -- Abandon an in-progress folder listing; files already found are not queued.
  state.scan_enum = nil
  local remaining_files = #state.scan_queue
  local remaining_analyzer = #state.analyzer_queue + #state.active_processes
  if not state.scan_running and remaining_files == 0 and remaining_analyzer == 0 then
    return
  end

  state.scan_running = false
  state.scan_started = 0
  state.scan_eta = nil
  if state.scan_session and type(state.scan_session.started_at) == "number" then
    state.scan_session.elapsed_so_far = (state.scan_session.elapsed_so_far or 0)
      + (r.time_precise() - state.scan_session.started_at)
    state.scan_session.started_at = nil
  end

  -- Keep the Python pool warm. In-flight jobs finish and merge; no new jobs start.

  if #state.samples > 0 then
    layout_samples()
    state._pending_layout = nil
    apply_discovered_library_tags()
    rebuild_tag_index()
    rebuild_samples_path_index()
  end

  save_samples()
  local msg = string.format(
    "Scan stopped and saved (%d sample(s) indexed, %d file(s) left). Analyzer workers stay ready. Next scan continues from here — you won't start over.",
    #state.samples,
    #state.scan_queue
  )
  add_scan_log(msg)
  sm_notify(string.format("Scan stopped and saved; %d file(s) left for next time", #state.scan_queue))
end


function analyze_file(path)
  local file_start_time = r.time_precise()
  local timings = {}
  
  -- PCM_Source creation
  local t0 = r.time_precise()
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then
    return nil
  end
  timings.pcm_create = (r.time_precise() - t0) * 1000  -- Convert to ms
  
  -- Get metadata from PCM_Source
  local t1 = r.time_precise()
  local length_ret = {r.GetMediaSourceLength(src)}
  local duration = pick_number(length_ret, 0.0)
  
  local sr_ret = {r.GetMediaSourceSampleRate(src)}
  local sr = pick_number(sr_ret, 44100.0)
  
  local ch_ret = {r.GetMediaSourceNumChannels(src)}
  local ch = math.floor(pick_number(ch_ret, 2))
  timings.pcm_metadata = (r.time_precise() - t1) * 1000

  local t2 = r.time_precise()
  local size, mtime = file_identity(path)
  if type(size) ~= "number" then
    size = 0
  end
  timings.file_size = (r.time_precise() - t2) * 1000
  
  -- Queue analyzer request instead of blocking (analyzer data will be merged later)
  -- Normalize path before queuing
  local normalized_path = normalize_path(path)
  if not state.external_disabled then
    -- Add to analyzer queue for parallel processing
    table.insert(state.analyzer_queue, normalized_path)
    add_scan_log(string.format("Queued analyzer for: %s", path:match("([^/]+)$") or path))
  else
    add_scan_log(string.format("Analyzer disabled, skipping: %s", path:match("([^/]+)$") or path))
  end
  
  local t4 = r.time_precise()
  r.PCM_Source_Destroy(src)
  timings.pcm_destroy = (r.time_precise() - t4) * 1000
  
  local avg_bps = size / math.max(duration, 0.01)
  -- Normalize path to use forward slashes
  path = normalize_path(path)
  
  -- Get tags from path first
  local t5 = r.time_precise()
  local tags = infer_tags_from_path(path, path:match("(.+)/[^/]+$") or "")
  timings.tags = (r.time_precise() - t5) * 1000
  
  -- File timing logs removed - happens during scanning
  
  -- Note: Analyzer tags (Drum/Swell) will be added later when analyzer data is merged
  
  -- Detect Loop or One shot from filename/path (audio classification merged later)
  local sample_folder = path:match("(.+)/[^/]+$") or ""
  local tags_sample = { tags = tags }
  apply_loop_oneshot_tag(tags_sample, detect_loop_or_oneshot(path, sample_folder, nil))
  tags = tags_sample.tags

  -- Detect genre words from path/folder names in the user's library
  tags = append_unique_tags(tags, infer_genre_tags_from_path(path, sample_folder))

  -- Keep user-assigned explorer tags across rescans
  tags = append_unique_tags(tags, (state.custom_tags and state.custom_tags[normalized_path]) or {})
  
  -- Return sample without analyzer data initially (will be merged later)
  return {
    path = normalized_path,
    name = normalized_path:match("([^/]+)$"),  -- macOS uses forward slashes only
    folder = normalized_path:match("(.+)/[^/]+$") or "",
    duration = duration,
    samplerate = sr,
    channels = ch,
    bps = avg_bps,
    file_size = size,  -- Store file size for Y axis fallback
    file_id_size = size,
    mtime = mtime,
    dominant_freq = nil,  -- Will be set when analyzer completes
    brightness = nil,     -- Spectral centroid (Hz); set by analyzer
    sub_weight = nil,     -- Low-frequency weight 0-1; set by analyzer
    rms_energy = nil,     -- Will be set when analyzer completes
    sample_type = nil,    -- Will be set when analyzer completes
    snap_offset = nil,    -- Will be set when analyzer completes
    effective_duration = nil, -- Audible end (trailing silence cropped); set by analyzer
    onset = nil,          -- First audible time; set by transient scan
    transient_end = nil,  -- Attack/click end, sustain start; set by transient scan
    playback_type = nil,  -- "oneshot"|"loop"|"unknown"; set by analyzer
    tags = tags
  }
end


function file_identity(path)
  if not path or path == "" then
    return nil, nil
  end
  if r.APIExists and r.APIExists("JS_File_Stat") then
    local ok, size, _accessed, modified = r.JS_File_Stat(path)
    if ok and ok ~= false and ok ~= 0 then
      local nsize = tonumber(size)
      local mt = modified and tostring(modified) or nil
      if mt == "" then mt = nil end
      if nsize then
        return nsize, mt
      end
    end
  end
  local f = io.open(path, "rb")
  if not f then
    return nil, nil
  end
  f:seek("end")
  local size = f:seek()
  f:close()
  return size, nil
end

function sample_file_changed(sample, size, mtime)
  if not sample then
    return false
  end
  local have_id = (type(sample.file_id_size) == "number")
    or (sample.mtime ~= nil and tostring(sample.mtime) ~= "")
  if not have_id then
    return false
  end
  if type(sample.file_id_size) == "number" and type(size) == "number" and sample.file_id_size ~= size then
    return true
  end
  if sample.mtime and mtime and tostring(sample.mtime) ~= tostring(mtime) then
    return true
  end
  return false
end

function stamp_sample_file_id(sample, size, mtime)
  if not sample then
    return
  end
  if type(size) == "number" then
    sample.file_id_size = size
    sample.file_size = size
  end
  if mtime and tostring(mtime) ~= "" then
    sample.mtime = tostring(mtime)
  end
end

function clear_sample_analysis_fields(sample)
  if not sample then
    return
  end
  sample.dominant_freq = nil
  sample.brightness = nil
  sample.sub_weight = nil
  sample.rms_energy = nil
  sample.effective_duration = nil
  sample.playback_type = nil
  sample.onset = nil
  sample.transient_end = nil
  sample.sample_type = nil
  sample.snap_offset = nil
end

function refresh_sample_file_meta(sample, path)
  if not sample or not path then
    return
  end
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then
    return
  end
  local duration = pick_number({r.GetMediaSourceLength(src)}, sample.duration or 0)
  local sr = pick_number({r.GetMediaSourceSampleRate(src)}, sample.samplerate or 44100)
  local ch = math.floor(pick_number({r.GetMediaSourceNumChannels(src)}, sample.channels or 2))
  r.PCM_Source_Destroy(src)
  sample.duration = duration
  sample.samplerate = sr
  sample.channels = ch
  if type(sample.file_size) == "number" and duration and duration > 0 then
    sample.bps = sample.file_size / math.max(duration, 0.01)
  end
end

function process_scan_slice(max_ms)
  max_ms = max_ms or 12.0

  -- Folder listing runs first, time-sliced; nothing else proceeds until it is done.
  if state.scan_enum then
    sm_scan_enum_step(max_ms)
    return
  end

  local analyzer_complete = (#state.analyzer_queue == 0 and #state.active_processes == 0)
  local workers_busy = false
  for _, w in ipairs(state.analyzer_workers or {}) do
    if w.path then
      workers_busy = true
      break
    end
  end

  if not state.scan_running then
    if not workers_busy and not next(state.analyzer_results or {}) then
      return
    end
  elseif state.scan_started <= 0 and #state.scan_queue == 0 and analyzer_complete
      and not next(state.analyzer_results) then
    return
  end

  -- Manage analyzer process pool (start new processes, check for completed ones)
  process_analyzer_queue()
  analyzer_complete = (#state.analyzer_queue == 0 and #state.active_processes == 0)

  -- Merge completed analyzer results into samples (O(1) path lookup)
  local merged_count = 0
  for path, result in pairs(state.analyzer_results) do
    local sample = lookup_sample_by_path(path)
    if sample and result.data then
      -- Only write fields the analyzer actually produced (don't clobber with nil)
      local data = result.data
      local wrote = false
      if data.dominant_freq ~= nil then
        sample.dominant_freq = data.dominant_freq
        wrote = true
      end
      if data.brightness ~= nil then
        sample.brightness = data.brightness
        wrote = true
      end
      if data.sub_weight ~= nil then
        sample.sub_weight = data.sub_weight
        wrote = true
      end
      if data.rms_energy ~= nil then
        sample.rms_energy = data.rms_energy
        wrote = true
      end
      if data.sample_type ~= nil then
        sample.sample_type = data.sample_type
        wrote = true
      end
      if data.snap_offset ~= nil then
        sample.snap_offset = data.snap_offset
        wrote = true
      end
      if data.effective_duration ~= nil then
        sample.effective_duration = data.effective_duration
        wrote = true
      end
      if data.onset ~= nil then
        sample.onset = data.onset
        wrote = true
      end
      if data.transient_end ~= nil then
        sample.transient_end = data.transient_end
        wrote = true
      end
      if data.playback_type ~= nil then
        sample.playback_type = data.playback_type
        apply_loop_oneshot_tag(sample, detect_loop_or_oneshot(sample.path, sample.folder or "", data.playback_type))
        wrote = true
      end
      -- Full analysis just landed: if this is a drum one-shot, queue transient/sustain next.
      if (data.playback_type ~= nil or data.dominant_freq ~= nil or data.effective_duration ~= nil)
          and sample_transient_incomplete(sample) then
        local npath = normalize_path(sample.path)
        local queued = false
        for _, p in ipairs(state.analyzer_queue) do
          if p == npath then
            queued = true
            break
          end
        end
        if not queued then
          for _, proc in ipairs(state.active_processes) do
            if proc.path == npath then
              queued = true
              break
            end
          end
        end
        if not queued and npath ~= "" then
          table.insert(state.analyzer_queue, npath)
          state.analyzer_path_mode = state.analyzer_path_mode or {}
          state.analyzer_path_mode[npath] = "transient"
        end
      end
      if data.sample_type and (data.sample_type == "Drum" or data.sample_type == "Swell") then
        local has_tag = false
        for _, tag in ipairs(sample.tags or {}) do
          if tag == data.sample_type then
            has_tag = true
            break
          end
        end
        if not has_tag and not (tag_is_suppressed and tag_is_suppressed(data.sample_type)) then
          sample.tags = sample.tags or {}
          table.insert(sample.tags, data.sample_type)
          wrote = true
        end
      end
      if wrote then
        merged_count = merged_count + 1
      end
      if sample_analysis_incomplete(sample) then
        local missing = sample_analysis_missing_fields(sample)
        sample._analyze_fail = "partial result: missing " .. table.concat(missing, ", ")
      else
        sample._analyze_fail = nil
      end
    elseif sample then
      sample._analyze_fail = (result and result.err and tostring(result.err)) or "analyzer returned no fields"
    elseif state.scan_session then
      state.scan_session.merge_misses = (state.scan_session.merge_misses or 0) + 1
    end
    state.analyzer_results[path] = nil
  end

  if merged_count > 0 then
    -- Defer full layout until scan/analyzers settle — per-result layout is too expensive
    state._pending_layout = true
    state.scan_unsaved_results = true
  end

  if not state.scan_running then
    return
  end

  if state._pending_layout and analyzer_complete and #state.scan_queue == 0 then
    layout_samples()
    state._pending_layout = nil
    if state.scan_started <= 0 then
      rebuild_tag_index()
    end
  end

  -- Finalize only once when an active scan session is done (files + analyzers).
  local function try_finalize_scan()
    if state.scan_started <= 0 then
      return false
    end
    if #state.scan_queue > 0 or not analyzer_complete then
      return false
    end
    if state._pending_layout then
      layout_samples()
      state._pending_layout = nil
    else
      layout_samples()
    end
    apply_discovered_library_tags()
    rebuild_tag_index()
    rebuild_samples_path_index()
    save_samples()
    state.last_save_time = r.time_precise()
    state.scan_started = 0
    state.scan_running = false
    state.scan_eta = nil
    state.incomplete_analysis_total = 0
    state.analyzer_job_label = nil
    state.analyzer_mode = nil
    state.analyzer_path_mode = {}
    local still_incomplete = 0
    for _, s in ipairs(state.samples) do
      if sample_analysis_incomplete(s) then
        still_incomplete = still_incomplete + 1
      end
    end
    if still_incomplete > 0 then
      add_scan_log(string.format(
        "Scan finished with %d sample(s) still missing analyzer fields — try Library > Re-analyze > Incomplete Samples",
        still_incomplete
      ))
      log(string.format("%d samples still incomplete after analysis", still_incomplete))
    else
      add_scan_log("Scan finished: all samples have analyzer fields")
    end
    finish_scan_session(still_incomplete)
    return true
  end

  -- Save progress every few minutes during long scans so a crash loses little.
  if state.scan_unsaved_results and state.scan_started > 0
      and (r.time_precise() - (state.last_save_time or 0)) >= 180.0 then
    save_samples()
    add_scan_log("Scan progress saved")
  end

  if #state.scan_queue == 0 and not analyzer_complete then
    return
  end

  local deadline = r.time_precise() + (max_ms / 1000.0)
  math.randomseed(state.map_seed)

  while #state.scan_queue > 0 and r.time_precise() < deadline do
    local path = table.remove(state.scan_queue)
    local sample = analyze_file(path)
    if sample then
      table.insert(state.samples, sample)
      state.scan_unsaved_results = true
      if sample.path then
        samples_by_path[sample.path] = sample
      end
      explorer_index_sample(sample)
      if state.scan_session then
        state.scan_session.indexed = (state.scan_session.indexed or 0) + 1
      end
    end
  end

  try_finalize_scan()
end

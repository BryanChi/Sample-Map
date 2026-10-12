-- Re-tag the library from saved data (no rescan), with a preview of what
-- changes, and drum types guessed from the sound for one-shots whose names
-- don't say what they are.

-- --- Guessed drum tags --------------------------------------------------------
-- A nearest-neighbour vote on numbers the analyzer already measured (length,
-- pitch, brightness, weight, attack, loudness). The library's own one-shots
-- whose file names name exactly one drum type are the examples. A guess is kept
-- only when 11 of the 15 closest examples agree (about 87% right on a real
-- library, for 45% of the unnamed one-shots).
SM_GUESS_CLASSES = { "kick", "snare", "clap", "hat", "crash", "tom", "perc" }
SM_GUESS_CLASS_SET = {}
for _, c in ipairs(SM_GUESS_CLASSES) do SM_GUESS_CLASS_SET[c] = true end
SM_GUESS_LABEL_ALIAS = { ride = "crash", rim = "snare", snap = "clap" }
SM_GUESS_K = 15
SM_GUESS_MIN_VOTES = 11
SM_GUESS_TRAIN_MAX = 2500
SM_GUESS_MIN_EXAMPLES = 200
SM_GUESS_MAX_SECONDS = 3.0

function show_guessed_tags()
  return state.show_guessed_tags ~= false
end

function set_show_guessed_tags(on)
  on = on == true
  if show_guessed_tags() ~= on then
    state.show_guessed_tags = on
    for _, s in ipairs(state.samples or {}) do
      s._render_color = nil
    end
    rebuild_tag_index()
    save_config()
  end
end

-- The guessed tag shown for a sample (nil when hidden or none).
function sample_shown_guess_tag(sample)
  if sample and show_guessed_tags() and type(sample.guess_tag) == "string" and sample.guess_tag ~= "" then
    return sample.guess_tag
  end
  return nil
end

function sm_guess_features(s)
  local e = s.effective_duration
  if type(e) ~= "number" or e <= 0 then
    e = s.duration
  end
  local f, b, w, rms = s.dominant_freq, s.brightness, s.sub_weight, s.rms_energy
  if type(e) ~= "number" or e <= 0 or type(f) ~= "number" or f <= 0 or type(b) ~= "number"
      or type(w) ~= "number" or type(rms) ~= "number" or rms <= 0 then
    return nil
  end
  local on = type(s.onset) == "number" and s.onset or 0.0
  local te = s.transient_end
  local att = (type(te) == "number" and te > on) and (te - on) or 0.01
  local log, max = math.log, math.max
  return { log(max(e, 0.01)), log(max(f, 20)), log(max(b, 40)), w, log(max(att, 0.001)), log(max(rms, 1e-4)) }
end

-- One-shot short enough to be a drum hit.
function sm_guess_is_hit(s, tags)
  if s.playback_type == "loop" then
    return false
  end
  local len = s.effective_duration or s.duration or 9
  if type(len) ~= "number" or len > SM_GUESS_MAX_SECONDS then
    return false
  end
  for _, tag in ipairs(tags or {}) do
    if tag == "loop" then
      return false
    end
  end
  return true
end

-- Drum type the file name alone names (exactly one), or nil.
function sm_guess_label_from_name(path)
  local name = tostring(path or ""):match("([^/\\]+)$") or ""
  name = name:gsub("%.%w+$", "")
  local label
  for _, tag in ipairs(sm_instrument_tags(name)) do
    tag = SM_GUESS_LABEL_ALIAS[tag] or tag
    if SM_GUESS_CLASS_SET[tag] then
      if label and label ~= tag then
        return nil
      end
      label = tag
    end
  end
  return label
end

function sm_tags_have_instrument(tags)
  for _, tag in ipairs(tags or {}) do
    if TAG_KEYWORD_WEIGHT[tag] then
      return true
    end
  end
  return false
end

-- True when tags name what the sound is (anything more specific than "drum").
function sm_tags_name_sound(tags)
  for _, tag in ipairs(tags or {}) do
    if tag ~= "drum" and TAG_KEYWORD_WEIGHT[tag] then
      return true
    end
  end
  return false
end

-- Time-sliced guess pass. items: { { sample = s, tags = tags }, ... } where
-- tags are the tags the sample will have. Results land in job.guesses[i]
-- (a class or false) once job.done.
function sm_guess_job_new(items)
  return { items = items, phase = "collect", i = 1, examples = {}, queries = {}, guesses = {} }
end

local function guess_lcg(seed)
  local x = seed
  return function(n)
    x = (x * 1103515245 + 12345) % 2147483648
    return (x % n) + 1
  end
end

function sm_guess_job_step(job, budget_ms)
  local clock = r.time_precise
  local deadline = clock() + (budget_ms or 8) / 1000.0
  local items = job.items
  if job.phase == "collect" then
    local n = #items
    while job.i <= n do
      local item = items[job.i]
      local s = item.sample
      job.guesses[job.i] = false
      if sm_guess_is_hit(s, item.tags) then
        local x = sm_guess_features(s)
        if x then
          local label = sm_guess_label_from_name(s.path)
          if label then
            job.examples[#job.examples + 1] = { x = x, y = label }
          elseif not sm_tags_name_sound(item.tags) then
            job.queries[#job.queries + 1] = { idx = job.i, x = x }
          end
        end
      end
      job.i = job.i + 1
      if job.i % 512 == 0 and clock() > deadline then
        return false
      end
    end
    job.phase = "fit"
  end
  if job.phase == "fit" then
    local ex = job.examples
    local classes = {}
    for _, e in ipairs(ex) do classes[e.y] = true end
    local nclasses = 0
    for _ in pairs(classes) do nclasses = nclasses + 1 end
    if #ex < SM_GUESS_MIN_EXAMPLES or nclasses < 2 or #job.queries == 0 then
      job.phase = "done"
      job.done = true
      return true
    end
    -- Same examples every run (seeded shuffle), at most SM_GUESS_TRAIN_MAX.
    local pick = guess_lcg(7)
    for i = #ex, 2, -1 do
      local j = pick(i)
      ex[i], ex[j] = ex[j], ex[i]
    end
    local train = {}
    for i = 1, math.min(#ex, SM_GUESS_TRAIN_MAX) do
      train[i] = ex[i]
    end
    local dim = #train[1].x
    local mu, sd = {}, {}
    for d = 1, dim do
      local sum = 0
      for i = 1, #train do sum = sum + train[i].x[d] end
      mu[d] = sum / #train
      local var = 0
      for i = 1, #train do
        local v = train[i].x[d] - mu[d]
        var = var + v * v
      end
      sd[d] = math.max(1e-6, math.sqrt(var / #train))
    end
    -- Flat z-scored training matrix for the distance loop.
    local flat, labels = {}, {}
    for i = 1, #train do
      local x = train[i].x
      for d = 1, dim do
        flat[(i - 1) * dim + d] = (x[d] - mu[d]) / sd[d]
      end
      labels[i] = train[i].y
    end
    job.mu, job.sd, job.dim, job.flat, job.labels, job.ntrain = mu, sd, dim, flat, labels, #train
    job.phase = "predict"
    job.q = 1
    job.examples = nil
    if clock() > deadline then
      return false
    end
  end
  if job.phase == "predict" then
    local mu, sd, dim, flat, labels, ntrain = job.mu, job.sd, job.dim, job.flat, job.labels, job.ntrain
    local k = math.min(SM_GUESS_K, ntrain)
    local queries = job.queries
    local best_d, best_y = {}, {}
    while job.q <= #queries do
      local query = queries[job.q]
      local z = {}
      for d = 1, dim do
        z[d] = (query.x[d] - mu[d]) / sd[d]
      end
      local count = 0
      for i = 1, ntrain do
        local base = (i - 1) * dim
        local dist = 0
        for d = 1, dim do
          local v = flat[base + d] - z[d]
          dist = dist + v * v
        end
        if count < k or dist < best_d[count] then
          -- Insert into the sorted top-k list.
          local pos = count < k and count + 1 or count
          while pos > 1 and best_d[pos - 1] > dist do
            best_d[pos] = best_d[pos - 1]
            best_y[pos] = best_y[pos - 1]
            pos = pos - 1
          end
          best_d[pos] = dist
          best_y[pos] = labels[i]
          if count < k then
            count = count + 1
          end
        end
      end
      local votes, top, top_n = {}, nil, 0
      for i = 1, count do
        local y = best_y[i]
        local v = (votes[y] or 0) + 1
        votes[y] = v
        if v > top_n then
          top, top_n = y, v
        end
      end
      if top and top_n >= SM_GUESS_MIN_VOTES then
        job.guesses[query.idx] = top
      end
      job.q = job.q + 1
      if job.q % 16 == 0 and clock() > deadline then
        return false
      end
    end
    job.phase = "done"
    job.done = true
  end
  return job.done == true
end

-- --- Re-tag -------------------------------------------------------------------

-- Tags a sample gets from its path and saved analysis, as a fresh scan would
-- give it (before the Library pass): instrument, Drum / Swell, loop / one shot,
-- genre, tempo, key, then the user's own tags.
function sm_retag_sample_tags(s)
  local path = normalize_path(s.path or "")
  local folder = path:match("(.+)/[^/]+$") or ""
  local tags = infer_tags_from_path(path, folder)
  if s.sample_type == "Drum" or s.sample_type == "Swell" then
    tags = append_unique_tags(tags, { s.sample_type })
  end
  local holder = { tags = tags }
  apply_loop_oneshot_tag(holder, detect_loop_or_oneshot(path, folder, s.playback_type, s.duration))
  tags = append_unique_tags(holder.tags, infer_genre_tags_from_path(path, folder))
  local bpm, key = sm_sample_bpm_key(path)
  local extra = {}
  if bpm then extra[#extra + 1] = sm_tempo_tag(bpm) end
  if key then extra[#extra + 1] = key end
  tags = append_unique_tags(tags, extra)
  local custom = state.custom_tags and (state.custom_tags[s.path] or state.custom_tags[path])
  if type(custom) == "table" then
    tags = append_unique_tags(tags, custom)
  end
  return tags, bpm, key
end

function retag_running()
  return state.retag_job ~= nil
end

function sm_start_retag()
  if state.retag_job then
    return
  end
  if state.scan_running or is_library_loading() then
    sm_notify("Re-tag can start once the scan or library load has finished")
    return
  end
  if #state.samples == 0 then
    sm_notify("The library is empty: add a scan folder first")
    return
  end
  state.retag_preview = nil
  state.retag_job = {
    phase = "tags",
    i = 1,
    samples = state.samples,
    count = #state.samples,
    shadows = {},
    started = r.time_precise(),
  }
  add_scan_log(string.format("Re-tag: working out new tags for %d sample(s)", #state.samples))
end

function sm_cancel_retag()
  state.retag_job = nil
  state.retag_preview = nil
end

local function retag_coverage(list, pick)
  local n = 0
  for i = 1, #list do
    if pick(list[i]) then n = n + 1 end
  end
  return n
end

local function retag_tags_have_loop_kind(tags)
  for _, tag in ipairs(tags or {}) do
    local low = string.lower(tostring(tag))
    if low == "loop" or low == "one shot" or low == "oneshot" then
      return true
    end
  end
  return false
end

-- Builds the preview from the finished job: per tag how many samples gain or
-- lose it, plus coverage numbers.
function sm_retag_build_preview(job)
  local samples, shadows = job.samples, job.shadows
  local before, after = {}, {}
  local changed = 0
  for i = 1, #samples do
    local old_set = {}
    for _, tag in ipairs(samples[i].tags or {}) do
      if not old_set[tag] then
        old_set[tag] = true
        before[tag] = (before[tag] or 0) + 1
      end
    end
    local new_set = {}
    local differs = false
    for _, tag in ipairs(shadows[i].tags or {}) do
      if not new_set[tag] then
        new_set[tag] = true
        after[tag] = (after[tag] or 0) + 1
        if not old_set[tag] then differs = true end
      end
    end
    if not differs then
      for tag in pairs(old_set) do
        if not new_set[tag] then
          differs = true
          break
        end
      end
    end
    if differs or (samples[i].guess_tag or false) ~= (shadows[i].guess_tag or false) then
      changed = changed + 1
    end
  end
  local rows = {}
  local seen = {}
  local function add_row(tag)
    if seen[tag] then return end
    seen[tag] = true
    local b, a = before[tag] or 0, after[tag] or 0
    if a ~= b then
      rows[#rows + 1] = { tag = tag, before = b, after = a }
    end
  end
  for tag in pairs(before) do add_row(tag) end
  for tag in pairs(after) do add_row(tag) end
  table.sort(rows, function(x, y)
    local dx, dy = math.abs(x.after - x.before), math.abs(y.after - y.before)
    if dx == dy then
      return x.tag < y.tag
    end
    return dx > dy
  end)
  local guess_counts = {}
  local guessed = 0
  for i = 1, #shadows do
    local g = shadows[i].guess_tag
    if g then
      guessed = guessed + 1
      guess_counts[g] = (guess_counts[g] or 0) + 1
    end
  end
  local guess_rows = {}
  for tag, count in pairs(guess_counts) do
    guess_rows[#guess_rows + 1] = { tag = tag, count = count }
  end
  table.sort(guess_rows, function(x, y)
    if x.count == y.count then return x.tag < y.tag end
    return x.count > y.count
  end)
  local n = #samples
  local function has_instr(item) return sm_tags_have_instrument(item.tags) end
  local function has_kind(item) return retag_tags_have_loop_kind(item.tags) end
  local function has_tempo(item) return item.bpm ~= nil end
  local function has_key(item) return item.key ~= nil end
  return {
    samples = samples,
    count = n,
    changed = changed,
    rows = rows,
    guess_rows = guess_rows,
    guessed = guessed,
    instrument_before = retag_coverage(samples, has_instr),
    instrument_after = retag_coverage(shadows, has_instr),
    kind_before = retag_coverage(samples, has_kind),
    kind_after = retag_coverage(shadows, has_kind),
    tempo_after = retag_coverage(shadows, has_tempo),
    key_after = retag_coverage(shadows, has_key),
    shadows = shadows,
    discovered = job.discovered,
    seconds = r.time_precise() - (job.started or r.time_precise()),
  }
end

-- Advances the running re-tag a few milliseconds per frame.
function process_retag_slice(budget_ms)
  local job = state.retag_job
  if not job then
    return
  end
  if job.samples ~= state.samples or job.count ~= #state.samples then
    state.retag_job = nil
    sm_notify("The library changed while re-tagging; run Re-tag Library again")
    return
  end
  local clock = r.time_precise
  local deadline = clock() + (budget_ms or 8) / 1000.0
  if job.phase == "tags" then
    local samples, shadows = job.samples, job.shadows
    while job.i <= job.count do
      local s = samples[job.i]
      local tags, bpm, key = sm_retag_sample_tags(s)
      shadows[job.i] = { path = s.path, tags = tags, bpm = bpm, key = key, src = s }
      job.i = job.i + 1
      if job.i % 256 == 0 and clock() > deadline then
        return
      end
    end
    job.phase = "library"
    return
  end
  if job.phase == "library" then
    -- The Library pass works on state.samples: run it on the shadows.
    local real_samples, real_set = state.samples, state.discovered_library_tag_set
    state.samples = job.shadows
    local ok, err = pcall(apply_discovered_library_tags)
    job.discovered = state.discovered_library_tag_set
    state.samples, state.discovered_library_tag_set = real_samples, real_set
    if not ok then
      state.retag_job = nil
      sm_report_error("re-tag library pass", err)
      return
    end
    local items = {}
    for i, sh in ipairs(job.shadows) do
      items[i] = { sample = sh.src, tags = sh.tags }
    end
    job.guess = sm_guess_job_new(items)
    job.phase = "guess"
    return
  end
  if job.phase == "guess" then
    if not sm_guess_job_step(job.guess, budget_ms) then
      return
    end
    for i, sh in ipairs(job.shadows) do
      sh.guess_tag = job.guess.guesses[i] or nil
    end
    job.guess = nil
    state.retag_preview = sm_retag_build_preview(job)
    state.retag_job = nil
    add_scan_log(string.format("Re-tag: %d of %d sample(s) would change (%.1f s)",
      state.retag_preview.changed, state.retag_preview.count, state.retag_preview.seconds))
  end
end

function sm_apply_retag(preview)
  preview = preview or state.retag_preview
  if not preview then
    return false
  end
  if preview.samples ~= state.samples or preview.count ~= #state.samples then
    state.retag_preview = nil
    sm_notify("The library changed since the preview; run Re-tag Library again")
    return false
  end
  for i, s in ipairs(state.samples) do
    local sh = preview.shadows[i]
    s.tags = sh.tags
    s.bpm, s.key = sh.bpm, sh.key
    s.guess_tag = sh.guess_tag
    s._render_color = nil
  end
  state.discovered_library_tag_set = preview.discovered or {}
  if clear_genre_tag_dir_cache then
    clear_genre_tag_dir_cache()
  end
  state.retag_done_version = SM_RETAG_VERSION
  state.retag_preview = nil
  rebuild_tag_index()
  save_samples()
  save_config()
  sm_notify(string.format("Re-tagged %d sample(s)", preview.changed))
  return true
end

-- --- Guesses for newly scanned samples -----------------------------------------
-- After a scan, one-shots without an instrument tag get a guess (no preview:
-- guesses are only shown, never written into a sample's tags).
function sm_start_guess_refresh()
  if state.retag_job or #state.samples == 0 then
    return
  end
  local items = {}
  for i, s in ipairs(state.samples) do
    items[i] = { sample = s, tags = s.tags }
  end
  state.guess_refresh = { job = sm_guess_job_new(items), samples = state.samples, count = #state.samples }
end

function process_guess_refresh_slice(budget_ms)
  local g = state.guess_refresh
  if not g then
    return
  end
  if g.samples ~= state.samples or g.count ~= #state.samples or state.scan_running then
    state.guess_refresh = nil
    return
  end
  if not sm_guess_job_step(g.job, budget_ms) then
    return
  end
  local changed = 0
  for i, s in ipairs(state.samples) do
    local guess = g.job.guesses[i] or nil
    if s.guess_tag ~= guess then
      s.guess_tag = guess
      s._render_color = nil
      changed = changed + 1
    end
  end
  state.guess_refresh = nil
  if changed > 0 then
    rebuild_tag_index()
    save_samples()
  end
end

-- --- One-time hint after this update -------------------------------------------
SM_RETAG_VERSION = 1

function sm_maybe_hint_retag()
  if state.retag_hint_shown or (state.retag_done_version or 0) >= SM_RETAG_VERSION then
    return
  end
  if #state.samples == 0 or state.scan_running or is_library_loading() then
    return
  end
  state.retag_hint_shown = true
  save_config()
  sm_notify("Tagging got smarter: Library > Re-tag Library shows what would change before applying it")
end

-- --- Preview window -------------------------------------------------------------
local function pct(a, n)
  if not n or n <= 0 then return "0%" end
  return string.format("%.1f%%", 100.0 * a / n)
end

function render_retag_window()
  local job, pv = state.retag_job, state.retag_preview
  if not job and not pv then
    return
  end
  local rect = state.main_window_rect
  local appearing = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
  if rect and r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, rect.x + (rect.w or 0) * 0.5, rect.y + (rect.h or 0) * 0.4, appearing, 0.5, 0.5)
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, 520, pv and 560 or 0, appearing)
  end
  local flags = 0
  if r.ImGui_WindowFlags_NoCollapse then flags = flags | r.ImGui_WindowFlags_NoCollapse() end
  if r.ImGui_WindowFlags_NoDocking then flags = flags | r.ImGui_WindowFlags_NoDocking() end
  local visible, open = r.ImGui_Begin(ctx, "Re-tag Library##retag", true, flags)
  if visible then
    if job then
      local label
      if job.phase == "tags" then
        label = string.format("Working out tags: %d / %d", math.min(job.i, job.count), job.count)
      elseif job.phase == "library" then
        label = "Finding Library tags"
      else
        local gj = job.guess
        if gj and gj.phase == "predict" then
          label = string.format("Guessing drum types: %d / %d", math.min(gj.q or 1, #gj.queries), #gj.queries)
        else
          label = "Guessing drum types"
        end
      end
      r.ImGui_Text(ctx, label)
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Nothing changes until you press Apply.")
      r.ImGui_Spacing(ctx)
      if draw_ui_button("retag_cancel_run", "Cancel", 90, 26, { compact = true }) then
        sm_cancel_retag()
      end
    else
      local n = pv.count
      r.ImGui_TextColored(ctx, UI_THEME.success, string.format("%d of %d samples would change", pv.changed, n))
      r.ImGui_Spacing(ctx)
      r.ImGui_Text(ctx, string.format("Instrument tag: %s  >  %s", pct(pv.instrument_before, n), pct(pv.instrument_after, n)))
      r.ImGui_Text(ctx, string.format("Loop / One shot known: %s  >  %s", pct(pv.kind_before, n), pct(pv.kind_after, n)))
      r.ImGui_Text(ctx, string.format("Tempo found: %s   Key found: %s", pct(pv.tempo_after, n), pct(pv.key_after, n)))
      if pv.guessed > 0 then
        local parts = {}
        for i = 1, math.min(#pv.guess_rows, 7) do
          parts[#parts + 1] = pv.guess_rows[i].tag .. " " .. pv.guess_rows[i].count
        end
        r.ImGui_Text(ctx, string.format("Guessed drum type for %d unnamed one-shot(s)", pv.guessed))
        r.ImGui_TextColored(ctx, UI_THEME.text_dim, "  " .. table.concat(parts, ", ")
          .. (show_guessed_tags() and "" or "  (hidden: View > Show Guessed Drum Tags)"))
      end
      r.ImGui_Spacing(ctx)
      r.ImGui_Separator(ctx)
      local cols = { 290, 350, 420 }
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Tag")
      r.ImGui_SameLine(ctx, cols[1])
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Now")
      r.ImGui_SameLine(ctx, cols[2])
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "After")
      r.ImGui_SameLine(ctx, cols[3])
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Change")
      local avail_h = select(2, r.ImGui_GetContentRegionAvail(ctx)) - 40
      if r.ImGui_BeginChild(ctx, "retag_rows", 0, math.max(120, avail_h), sm_child_border_flag()) then
        for i = 1, math.min(#pv.rows, 400) do
          local row = pv.rows[i]
          local diff = row.after - row.before
          local group = categorize_tags(row.tag)
          local name = row.tag
          if group then
            name = name .. "  (" .. (tag_parent_display_name(group) or group) .. ")"
          end
          r.ImGui_Text(ctx, name)
          r.ImGui_SameLine(ctx, cols[1])
          r.ImGui_Text(ctx, tostring(row.before))
          r.ImGui_SameLine(ctx, cols[2])
          r.ImGui_Text(ctx, tostring(row.after))
          r.ImGui_SameLine(ctx, cols[3])
          r.ImGui_TextColored(ctx, diff > 0 and UI_THEME.success or UI_THEME.danger,
            (diff > 0 and "+" or "") .. tostring(diff))
        end
        if #pv.rows == 0 then
          r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No tag changes.")
        end
        r.ImGui_EndChild(ctx)
      end
      if draw_ui_button("retag_apply", "Apply", 90, 26, { compact = true, style = "success" }) then
        sm_apply_retag(pv)
      end
      r.ImGui_SameLine(ctx)
      if draw_ui_button("retag_cancel", "Cancel", 90, 26, { compact = true }) then
        sm_cancel_retag()
      end
    end
  end
  end_window(visible, true)
  if open == false then
    sm_cancel_retag()
  end
end

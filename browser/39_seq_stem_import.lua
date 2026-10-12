-- Sample Map Browser module: seq_stem_import
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_stem_import_write_notes(region, slot, rec, place_time)
  if not region or not slot or not rec or not rec.onsets then
    return 0
  end
  local onsets = rec.onsets
  local src_dur = rec.duration or 0.0
  local region_start = region.start_qn or 0.0
  local grid_qn = state.seq_grid_qn or 0.25
  local n = 0
  for i = 1, #onsets do
    local t = onsets[i].time or 0.0
    if t < 0 then t = 0.0 end
    local next_t
    if i < #onsets then
      next_t = onsets[i + 1].time or (t + 0.12)
    else
      next_t = math.max(t + 0.12, src_dur)
    end
    if next_t <= t + 0.008 then
      next_t = t + 0.08
    end
    local abs_qn = time_to_qn(place_time + t)
    local next_qn = time_to_qn(place_time + next_t)
    if abs_qn then
      local qn_offset = abs_qn - region_start
      if qn_offset < 0 then qn_offset = 0.0 end
      local decay_qn = grid_qn
      if next_qn and next_qn > abs_qn then
        decay_qn = next_qn - abs_qn
      end
      local region_end = region_start + get_seq_region_length_qn(region)
      if abs_qn + decay_qn > region_end then
        decay_qn = math.max(grid_qn * 0.05, region_end - abs_qn)
      end
      local step_key = seq_alloc_note_key(region, slot.id, qn_offset)
      set_seq_note(region, slot.id, step_key, {
        enabled = true,
        qn_offset = qn_offset,
        step = math.floor((qn_offset / grid_qn) + 1e-9),
        sample_path = rec.path,
        sample_name = slot.sample_name or SEQ_STEM_IMPORT_LABEL[rec.key] or basename(rec.path),
        frozen_sample_path = rec.path,
        frozen_sample_name = slot.sample_name,
        volume = 1.0,
        pan = 0.0,
        pitch = 0.0,
        offset_qn = 0.0,
        stretch = 1.0,
        start = 0.0,
        source_offset = t,
        sample_vary = 0.0,
        stutter = 1,
        decay_qn = decay_qn,
      })
      n = n + 1
    end
  end
  return n
end

function seq_stem_import_place(job, info)
  local SM = SampleMapStemImport
  if not SM or not job or not info then
    return false, "Stem import backend missing."
  end
  local place_time = job.place_time or 0.0
  local drums_path = info.stems and info.stems.drums
  local drum_stems = info.drum_stems or {}
  state._stem_dbg_n = 0

  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  local own = seq_undo_own_begin("Import drums from audio")

  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, true)
  local temp = r.GetTrack(0, idx)
  if temp then
    r.GetSetMediaTrackInfo_String(temp, "P_NAME", "Sample Map Stem Import", true)
    r.SetMediaTrackInfo_Value(temp, "B_SHOWINMIXER", 0)
    r.SetMediaTrackInfo_Value(temp, "B_SHOWINTCP", 0)
  end

  local drums_item, drums_len = nil, 0.0
  if temp and drums_path then
    drums_item, drums_len = SM.insert_wav(temp, drums_path, place_time)
    if drums_item and job.tempo_map ~= false then
      SM.tempo_map(drums_item)
    end
  end

  local duration = (drums_len and drums_len > 0) and drums_len or (job.duration or 0.0)
  local hits_by_key = {}
  local kit_stats = {}
  local order = SM.drum_order and SM.drum_order() or { "kick", "snare", "toms", "hh", "ride", "crash" }
  if temp then
    for _, key in ipairs(order) do
      local wav = drum_stems[key]
      if wav then
        local item, item_len = SM.insert_wav(temp, wav, place_time)
        if item then
          local detect_opts = SEQ_STEM_HIT_DETECT and SEQ_STEM_HIT_DETECT[key] or nil
          local onsets, stats = SM.detect_hits(item, detect_opts)
          if type(stats) == "table" then
            kit_stats[key] = stats
          end
          if onsets and #onsets > 0 then
            if seq_stem_filter_weak_hits then
              onsets = seq_stem_filter_weak_hits(onsets, key)
            end
            if seq_stem_merge_close_hits then
              onsets = seq_stem_merge_close_hits(onsets, key)
            end
            if onsets and #onsets > 0 then
              hits_by_key[key] = {
                key = key,
                path = wav,
                onsets = onsets,
                duration = (item_len and item_len > 0) and item_len or SM.file_duration(wav),
                peak = stats and tonumber(stats.peak) or nil,
              }
            end
          end
          r.DeleteTrackMediaItem(temp, item)
        end
      end
    end
  end
  if seq_stem_cymbal_is_bleed then
    for _, key in ipairs({ "toms", "ride", "crash" }) do
      local ref_peak = seq_stem_kit_ref_peak(kit_stats, key)
      if hits_by_key[key] and seq_stem_cymbal_is_bleed(key, kit_stats[key], ref_peak) then
        hits_by_key[key] = nil
      end
    end
  end
  if not next(hits_by_key) and drums_path and drums_item then
    local onsets = SM.detect_hits(drums_item)
    if onsets and #onsets > 0 then
      if seq_stem_merge_close_hits then
        onsets = seq_stem_merge_close_hits(onsets, "drums")
      end
      hits_by_key.drums = {
        key = "drums",
        path = drums_path,
        onsets = onsets,
        duration = duration,
      }
    end
  end

  if temp then
    r.DeleteTrack(temp)
  end

  local source_item = nil
  if job.item_guid and SM.find_item_by_guid then
    source_item = SM.find_item_by_guid(job.item_guid)
  end
  local have_hits = next(hits_by_key) ~= nil
  local n_stems = 0
  if job.place_mix_stems ~= false and SM.place_instrument_stems then
    n_stems = SM.place_instrument_stems(info.stems, {
      place_time = place_time,
      source_item = source_item,
      skip_drums = have_hits,
    }) or 0
  end
  if source_item and SM.mute_item and job.mute_original ~= false
      and (have_hits or n_stems > 0) then
    SM.mute_item(source_item)
  end

  if not have_hits then
    if own then end_seq_undo("Import drums from audio") end
    if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
    r.UpdateArrange()
    if n_stems > 0 then
      return false, "No drum hits detected. Instrument stems were still placed."
    end
    return false, "No drum hits detected on the split stems."
  end

  local end_time = place_time + math.max(duration, 0.25)
  local start_qn = time_to_qn(place_time) or 0.0
  local bars = 4
  if r.TimeMap2_timeToBeats then
    local _, start_meas = r.TimeMap2_timeToBeats(0, place_time)
    local _, end_meas = r.TimeMap2_timeToBeats(0, end_time)
    if start_meas and end_meas and end_meas > start_meas then
      bars = math.max(1, math.ceil(end_meas - start_meas + 0.05))
    end
  end
  local region = create_seq_region(bars, nil, false, start_qn, true)
  if region then
    region.name = job.name or "Drums"
    region.groove = "off"
    state.selected_seq_region_id = region.id
  end

  local placed = 0
  local keys = { "kick", "snare", "toms", "hh", "ride", "crash", "drums" }
  for _, key in ipairs(keys) do
    local rec = hits_by_key[key]
    if rec then
      local role = SEQ_STEM_IMPORT_ROLE[key] or "perc"
      local label = SEQ_STEM_IMPORT_LABEL[key] or key
      local slot = seq_stem_import_slot_for_role(role, label)
      if slot then
        local tag = SEQ_ROLE_TAG_CANDIDATES[role] and SEQ_ROLE_TAG_CANDIDATES[role][1] or role
        local sample = seq_stem_import_register_sample(rec.path, label, tag, rec.duration)
        if sample then
          if region and slot.sample_path and slot.sample_path ~= "" and slot.sample_path ~= sample.path then
            seq_assign_region_track_sample(region, slot, sample, false)
          else
            assign_sample_to_seq_track(slot, sample, false)
          end
        end
        if region then
          placed = placed + seq_stem_import_write_notes(region, slot, rec, place_time)
        end
      end
    end
  end

  if region then
    sync_seq_region(region)
  end
  save_config()
  if save_seq_project_state then
    save_seq_project_state()
  end
  if own then
    end_seq_undo("Import drums from audio")
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  r.UpdateArrange()
  if info.warning and info.warning ~= "" then
    return true, placed, info.warning
  end
  return true, placed
end

function seq_stem_import_file_drag_active()
  if state.seq_stem_import then
    return false
  end
  if sample_drag_active and sample_drag_active() then
    return false
  end
  return state.seq_stem_import_hover == true
end

function seq_stem_import_classify_path(path)
  local sample = find_sample_by_path(path) or lookup_sample_by_path(path)
  local dur = 0.0
  if SampleMapStemImport and SampleMapStemImport.file_duration then
    dur = SampleMapStemImport.file_duration(path) or 0.0
  end
  if sample and type(sample.duration) == "number" and sample.duration > 0 then
    dur = sample.duration
  end
  if not SampleMapStemImport or not SampleMapStemImport.classify_source then
    return "auto", dur
  end
  local kind = SampleMapStemImport.classify_source(path, {
    tags = sample and sample.tags,
    sample_type = sample and sample.sample_type,
    duration = dur,
  })
  return kind or "auto", dur
end

SEQ_STEM_IMPORT_DROP_LABEL = "Drop here to dissect drum pattern"

function seq_stem_import_help_mark(id, tip)
  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_InvisibleButton(ctx, "##stem_help_" .. tostring(id), 18, 18)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5
  local hovered = r.ImGui_IsItemHovered(ctx)
  local col = hovered and (UI_THEME.accent or 0xFF4C8DFF) or (UI_THEME.text_dim or 0xFF8A93A3)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, 7.2, col, 20, hovered and 1.6 or 1.25)
  local qw, qh = r.ImGui_CalcTextSize(ctx, "?")
  r.ImGui_DrawList_AddText(dl, cx - qw * 0.5, cy - qh * 0.5 - 1, col, "?")
  if hovered and tip and tip ~= "" then
    if r.ImGui_BeginTooltip then
      r.ImGui_BeginTooltip(ctx)
      if r.ImGui_PushTextWrapPos then
        r.ImGui_PushTextWrapPos(ctx, 340)
      end
      r.ImGui_Text(ctx, tip)
      if r.ImGui_PopTextWrapPos then
        r.ImGui_PopTextWrapPos(ctx)
      end
      r.ImGui_EndTooltip(ctx)
    elseif r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, tip)
    end
  end
end

function seq_stem_import_radio_row(id, choices, current)
  for i = 1, #choices do
    local choice = choices[i]
    if i > 1 then
      r.ImGui_SameLine(ctx, 0, 14)
    end
    if draw_ui_radio(id .. "_" .. tostring(choice.id), choice.label, current == choice.id) then
      current = choice.id
    end
  end
  return current
end

function seq_stem_import_offer(path, extra)
  extra = extra or {}
  if not path or path == "" then
    return false
  end
  if state.seq_stem_import then
    r.ShowMessageBox("A stem import is already running.", "Sequencer stem import", 0)
    return false
  end
  local form = SampleMapStemImport and SampleMapStemImport.load_prefs
    and SampleMapStemImport.load_prefs() or {}
  if extra.model and extra.model ~= "" then
    form.model = extra.model
  end
  if extra.source and extra.source ~= "" then
    form.source = extra.source
  end
  if extra.shifts then
    form.shifts = tonumber(extra.shifts) or form.shifts
  end
  if extra.overlap then
    form.overlap = tonumber(extra.overlap) or form.overlap
  end
  if extra.split_drums ~= nil then
    form.split_drums = extra.split_drums
  end
  if extra.place_mix_stems ~= nil then
    form.place_mix_stems = extra.place_mix_stems
  end
  if extra.mute_original ~= nil then
    form.mute_original = extra.mute_original
  end
  if extra.tempo_map ~= nil then
    form.tempo_map = extra.tempo_map
  end
  state.seq_stem_import_dialog = {
    path = path,
    name = extra.name,
    place_time = extra.place_time,
    start = extra.start,
    duration = extra.duration,
    item_guid = extra.item_guid,
    form = form,
  }
  if state.active_view ~= "sequencer" and not state.sequencer_floating then
    state.active_view = "sequencer"
  end
  return true
end

function seq_stem_import_close_dialog()
  state.seq_stem_import_dialog = nil
end

function seq_stem_import_commit_dialog()
  local dlg = state.seq_stem_import_dialog
  if not dlg or not dlg.path then
    return false
  end
  local form = dlg.form or {}
  form.source = form.source or "auto"
  form.drums_only = form.source == "drums"
  form.auto_skip_mix = form.source == "auto"
  if SampleMapStemImport and SampleMapStemImport.save_prefs then
    SampleMapStemImport.save_prefs(form)
  end
  local opts = {
    name = dlg.name,
    place_time = dlg.place_time,
    start = dlg.start,
    duration = dlg.duration,
    item_guid = dlg.item_guid,
    model = form.model,
    source = form.source,
    shifts = form.shifts,
    overlap = form.overlap,
    split_drums = form.split_drums,
    place_mix_stems = form.place_mix_stems,
    mute_original = form.mute_original,
    tempo_map = form.tempo_map,
    drums_only = form.drums_only,
    auto_skip_mix = form.auto_skip_mix,
  }
  state.seq_stem_import_dialog = nil
  return seq_stem_import_begin(dlg.path, opts)
end

function seq_stem_import_render_dialog()
  local dlg = state.seq_stem_import_dialog
  if not dlg or not ctx then
    return
  end
  local form = dlg.form
  if type(form) ~= "table" then
    return
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, 430, 0, r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0)
  end
  if r.ImGui_SetNextWindowPos and state.main_window_rect then
    local rect = state.main_window_rect
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    r.ImGui_SetNextWindowPos(ctx, rect.x + (rect.w or 0) * 0.5, rect.y + (rect.h or 0) * 0.42, cond, 0.5, 0.5)
  end
  local flags = 0
  if r.ImGui_WindowFlags_AlwaysAutoResize then
    flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize()
  end
  if r.ImGui_WindowFlags_NoCollapse then
    flags = flags | r.ImGui_WindowFlags_NoCollapse()
  end
  if r.ImGui_WindowFlags_NoDocking then
    flags = flags | r.ImGui_WindowFlags_NoDocking()
  end
  local visible, open = r.ImGui_Begin(ctx, "Dissect drum pattern##stem_opts", true, flags)
  if visible then
    local file_name = dlg.name
    if not file_name or file_name == "" then
      file_name = tostring(dlg.path or ""):match("([^/\\]+)$") or dlg.path or ""
    end
    r.ImGui_TextColored(ctx, UI_THEME.text_dim or 0xFF8A93A3, file_name)
    r.ImGui_Spacing(ctx)

    r.ImGui_Text(ctx, "Model")
    form.model = seq_stem_import_radio_row("stem_model", {
      { id = "fast", label = "Fast" },
      { id = "good", label = "Good" },
      { id = "6stem", label = "6-stem" },
    }, form.model or "good")
    seq_stem_import_help_mark("model",
      "Fast: quick split. Other can sound metallic.\n"
        .. "Good: cleaner leftover stem. Best first try for ringing.\n"
        .. "6-stem: also pulls guitar and piano out of Other.")

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Source")
    form.source = seq_stem_import_radio_row("stem_src", {
      { id = "auto", label = "Auto" },
      { id = "mix", label = "Mix" },
      { id = "drums", label = "Drums" },
    }, form.source or "auto")
    seq_stem_import_help_mark("source",
      "Auto: skip mix split when this already sounds like a drum loop.\n"
        .. "Mix: always run Demucs (vocals, drums, bass, other).\n"
        .. "Drums: treat the file as drums and only split the kit.")

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Quality")
    local shift_id = tostring(form.shifts or 2)
    if shift_id ~= "1" and shift_id ~= "2" and shift_id ~= "4" then
      shift_id = "2"
    end
    shift_id = seq_stem_import_radio_row("stem_shifts", {
      { id = "1", label = "1" },
      { id = "2", label = "2" },
      { id = "4", label = "4" },
    }, shift_id)
    form.shifts = tonumber(shift_id) or 2
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute or 0xFF6B7380, "shifts")
    seq_stem_import_help_mark("shifts",
      "Extra Demucs passes, then averaged.\n"
        .. "1: fastest.\n"
        .. "2: less high, metallic ringing in Other. Recommended.\n"
        .. "4: cleaner still, much slower.")

    r.ImGui_Dummy(ctx, 1, 2)
    local ov = tonumber(form.overlap) or 0.25
    local ov_id = (ov >= 0.42) and "0.50" or ((ov >= 0.30) and "0.35" or "0.25")
    ov_id = seq_stem_import_radio_row("stem_overlap", {
      { id = "0.25", label = "0.25" },
      { id = "0.35", label = "0.35" },
      { id = "0.50", label = "0.50" },
    }, ov_id)
    form.overlap = tonumber(ov_id) or 0.25
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute or 0xFF6B7380, "overlap")
    seq_stem_import_help_mark("overlap",
      "How much adjacent chunks overlap.\n"
        .. "0.25: default.\n"
        .. "0.35–0.50: can soften metallic edges, a bit slower.")

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "After split")
    r.ImGui_Dummy(ctx, 1, 2)

    local hit, val
    hit, val = draw_ui_checkbox("stem_kit", "Split kit pieces", form.split_drums ~= false)
    if hit then form.split_drums = val end
    seq_stem_import_help_mark("kit",
      "Split the drums stem into kick, snare, toms, hats, ride, and crash for the sequencer.")

    hit, val = draw_ui_checkbox("stem_place", "Place mix stems", form.place_mix_stems ~= false)
    if hit then form.place_mix_stems = val end
    seq_stem_import_help_mark("place",
      "Add vocals, bass, guitar, piano, and other as new tracks next to the original. Drums stay on the sequencer.")

    hit, val = draw_ui_checkbox("stem_mute", "Mute original item", form.mute_original ~= false)
    if hit then form.mute_original = val end
    seq_stem_import_help_mark("mute",
      "Mute the source audio item so you hear the stems and sequenced drums instead of the mix.")

    hit, val = draw_ui_checkbox("stem_tempo", "Tempo map from drums", form.tempo_map ~= false)
    if hit then form.tempo_map = val end
    seq_stem_import_help_mark("tempo",
      "Write project tempo from the drums stem so sequencer hits line up with the audio.")

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    if draw_ui_button("stem_opts_cancel", "Cancel", 100, 28, { compact = true }) then
      seq_stem_import_close_dialog()
    end
    r.ImGui_SameLine(ctx)
    if draw_ui_button("stem_opts_go", "Start", 120, 28, { compact = true, style = "primary" }) then
      seq_stem_import_commit_dialog()
    end
  end
  end_window(visible, true)
  if open == false then
    seq_stem_import_close_dialog()
  end
end

function seq_stem_import_begin(path, opts)
  opts = opts or {}
  if state.seq_stem_import then
    r.ShowMessageBox("A stem import is already running.", "Sequencer stem import", 0)
    return false
  end
  if not SampleMapStemImport or not SampleMapStemImport.start_split then
    r.ShowMessageBox("Stem import backend failed to load (SampleMapStemImport.lua).", "Sequencer stem import", 0)
    return false
  end
  if not opts.model or opts.model == "" then
    local prefs = SampleMapStemImport.load_prefs and SampleMapStemImport.load_prefs()
    if prefs then
      for k, v in pairs(prefs) do
        if opts[k] == nil then
          opts[k] = v
        end
      end
    end
  end
  local place_time = tonumber(opts.place_time)
  if not place_time then
    place_time = 0.0
    if state.seq_view_start_qn then
      place_time = qn_to_time(state.seq_view_start_qn) or 0.0
    end
  end
  local kind, file_dur = seq_stem_import_classify_path(path)
  if opts.source == "mix" then
    kind = "mix"
  elseif opts.source == "drums" then
    kind = "drums"
  end
  local dur = tonumber(opts.duration) or 0.0
  if dur <= 0 then
    dur = file_dur
  end
  local backend, err = SampleMapStemImport.start_split(path, {
    model = opts.model,
    shifts = opts.shifts,
    overlap = opts.overlap,
    drums_only = kind == "drums",
    auto_skip_mix = kind == "auto",
    split_drums = opts.split_drums,
    duration = dur,
    start = tonumber(opts.start) or 0.0,
  })
  if not backend then
    r.ShowMessageBox(err or "Could not start stem split.", "Sequencer stem import", 0)
    return false
  end
  local msg = "Starting stem split…"
  if kind == "drums" then
    msg = "Drum loop — splitting kit pieces…"
  elseif kind == "auto" then
    msg = "Checking source, then splitting…"
  end
  if state.active_view ~= "sequencer" and not state.sequencer_floating then
    state.active_view = "sequencer"
  end
  state.seq_stem_import = {
    phase = "split",
    backend = backend,
    place_time = place_time,
    name = (opts.name and opts.name ~= "" and opts.name) or backend.name,
    duration = backend.duration or dur,
    source_kind = kind,
    item_guid = opts.item_guid,
    mute_original = opts.mute_original ~= false,
    place_mix_stems = opts.place_mix_stems ~= false,
    tempo_map = opts.tempo_map ~= false,
    pct = 0,
    msg = msg,
  }
  return true
end

-- SampleMapStemImport.lua is loaded once at startup. Developer hot-reload is
-- opt-in: set ExtState SampleMapBrowser/stem_hot_reload=1 (or the global
-- SAMPLE_MAP_STEM_HOT_RELOAD = true); the file is then re-read at most once a
-- second and re-run only when its contents changed.
function seq_stem_import_hot_reload_if_changed()
  local now = r.time_precise()
  if now - (state.seq_stem_hot_reload_checked or 0) < 1.0 then
    return
  end
  state.seq_stem_hot_reload_checked = now
  if not (SAMPLE_MAP_STEM_HOT_RELOAD or r.GetExtState("SampleMapBrowser", "stem_hot_reload") == "1") then
    return
  end
  local path = SCRIPT_DIR .. "/SampleMapStemImport.lua"
  local fh = io.open(path, "rb")
  if not fh then
    return
  end
  local src = fh:read("*a")
  fh:close()
  if not src or src == state.seq_stem_hot_reload_src then
    return
  end
  local first = state.seq_stem_hot_reload_src == nil
  state.seq_stem_hot_reload_src = src
  if first then
    return -- baseline: the startup dofile already ran this version
  end
  local ok, err = pcall(dofile, path)
  if not ok then
    log("Stem import hot-reload failed: " .. tostring(err))
    return
  end
  state.seq_stem_hooks_installed = false
end

function seq_stem_import_tick()
  seq_stem_import_hot_reload_if_changed()
  -- Hooks reference browser functions defined after the startup dofile, so
  -- install them lazily on the first tick (and again after a hot-reload).
  if not state.seq_stem_hooks_installed then
    state.seq_stem_hooks_installed = true
    if SampleMapStemImport and SampleMapStemImport.install_browser_hooks then
      SampleMapStemImport.install_browser_hooks()
    end
  end
  local job = state.seq_stem_import
  if not job then
    return
  end
  if not SampleMapStemImport then
    state.seq_stem_import = nil
    return
  end
  if job.phase == "place" then
    local ok, a, b = pcall(seq_stem_import_place, job, job.info)
    state.seq_stem_import = nil
    if not ok then
      r.ShowMessageBox("Stem import failed:\n" .. tostring(a), "Sequencer stem import", 0)
    elseif a == false then
      r.ShowMessageBox(tostring(b or "Import produced no drum hits."), "Sequencer stem import", 0)
    elseif type(b) == "string" and b ~= "" then
      -- warning from drum split; still succeeded
    end
    return
  end
  if job.phase ~= "split" then
    return
  end
  local status, a, b = SampleMapStemImport.poll(job.backend)
  if status == "running" then
    job.pct = a or 0
    job.msg = (b and b ~= "" and b) or "Splitting stems…"
    return
  end
  if status == "error" then
    state.seq_stem_import = nil
    r.ShowMessageBox(tostring(a or "Stem split failed."), "Sequencer stem import", 0)
    return
  end
  job.phase = "place"
  job.info = a
  job.pct = 100
  if a and a.engine == "drums-only" then
    job.source_kind = "drums"
  end
  job.msg = "Detecting transients and mapping tempo…"
end

function seq_stem_import_poll_external_request()
  if state.seq_stem_import then
    return
  end
  if state.seq_stem_import_dialog then
    return
  end
  if not SampleMapStemImport or not SampleMapStemImport.take_request then
    return
  end
  local req = SampleMapStemImport.take_request()
  if not req then
    return
  end
  seq_stem_import_offer(req.path, req)
end

function seq_stem_import_draw_overlay(dl, x0, y0, x1, y1)
  local job = state.seq_stem_import
  if not job or not dl or not x0 then
    return
  end
  local w = (x1 or x0) - x0
  local h = (y1 or y0) - y0
  if w < 40 or h < 24 then
    return
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, 0xCC10141C, 0)
  local pct = math.max(0, math.min(100, tonumber(job.pct) or 0)) / 100.0
  local bar_w = math.min(360, w - 48)
  local bar_x0 = x0 + (w - bar_w) * 0.5
  local bar_y0 = y0 + h * 0.5 - 8
  r.ImGui_DrawList_AddRectFilled(dl, bar_x0, bar_y0, bar_x0 + bar_w, bar_y0 + 16, 0xFF2A3140, 4)
  r.ImGui_DrawList_AddRectFilled(dl, bar_x0, bar_y0, bar_x0 + bar_w * pct, bar_y0 + 16, UI_THEME.accent or 0xFF4C8DFF, 4)
  local title = "Dissecting drum pattern"
  if job.phase == "place" then
    title = "Detecting transients and mapping tempo"
  elseif job.source_kind == "drums" or (job.backend and job.backend.drums_only) then
    title = "Splitting drum kit"
  end
  local tw = select(1, r.ImGui_CalcTextSize(ctx, title)) or 0
  r.ImGui_DrawList_AddText(dl, x0 + (w - tw) * 0.5, bar_y0 - 28, 0xF2F6FAFF, title)
  local msg = tostring(job.msg or "")
  if msg ~= "" then
    local mw = select(1, r.ImGui_CalcTextSize(ctx, msg)) or 0
    r.ImGui_DrawList_AddText(dl, x0 + (w - mw) * 0.5, bar_y0 + 24, 0xAAB3C4FF, msg)
  end
end

function seq_stem_import_payload_is_audio(path)
  if not path or path == "" then
    return false
  end
  if SampleMapStemImport and SampleMapStemImport.is_audio_path then
    return SampleMapStemImport.is_audio_path(path)
  end
  local ext = tostring(path):match("%.([^%.]+)$")
  ext = ext and ext:lower() or ""
  return ext == "wav" or ext == "aif" or ext == "aiff" or ext == "flac"
    or ext == "mp3" or ext == "ogg" or ext == "m4a" or ext == "wv"
end

function seq_stem_import_first_audio_from_payload(count)
  local n = tonumber(count) or 0
  if n < 1 then
    n = 32
  end
  local i = 0
  while i < n do
    local ok, filename = r.ImGui_GetDragDropPayloadFile(ctx, i)
    if not ok then
      break
    end
    if seq_stem_import_payload_is_audio(filename) then
      return filename
    end
    i = i + 1
  end
  return nil
end

function seq_stem_import_accept_file_drop()
  if sample_drag_active and sample_drag_active() then
    return
  end
  if state.seq_stem_import then
    return
  end
  if not r.ImGui_BeginDragDropTarget or not r.ImGui_AcceptDragDropPayloadFiles then
    return
  end
  if not r.ImGui_BeginDragDropTarget(ctx) then
    return
  end
  local peek = 0
  if r.ImGui_DragDropFlags_AcceptBeforeDelivery then
    peek = peek | r.ImGui_DragDropFlags_AcceptBeforeDelivery()
  end
  if r.ImGui_DragDropFlags_AcceptNoDrawDefaultRect then
    peek = peek | r.ImGui_DragDropFlags_AcceptNoDrawDefaultRect()
  end
  if r.ImGui_Col_DragDropTarget then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_DragDropTarget(), 0x00000000)
  end
  local hovering, count = r.ImGui_AcceptDragDropPayloadFiles(ctx, peek)
  if hovering then
    state.seq_stem_import_hover = true
    local delivered, dcount = r.ImGui_AcceptDragDropPayloadFiles(ctx)
    if delivered then
      local picked = seq_stem_import_first_audio_from_payload(dcount or count)
      if picked then
        seq_stem_import_offer(picked)
      end
    end
  end
  if r.ImGui_Col_DragDropTarget then
    r.ImGui_PopStyleColor(ctx, 1)
  end
  r.ImGui_EndDragDropTarget(ctx)
end

-- ReaImGui only delivers OS file drops to an item that called BeginDragDropTarget.
-- A click-through child covering the current window is the documented way to
-- catch Finder/Explorer drops anywhere, while the pattern chip stays the visual.
function seq_stem_import_install_os_drop_overlay()
  if sample_drag_active and sample_drag_active() then
    return
  end
  if state.seq_stem_import then
    return
  end
  if state.seq_stem_import_dialog then
    return
  end
  if not (r.ImGui_BeginChild and r.ImGui_GetWindowPos and r.ImGui_GetWindowSize) then
    return
  end
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww, wh = r.ImGui_GetWindowSize(ctx)
  if not wx or not ww or ww < 8 or wh < 8 then
    return
  end
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local win_flags = 0
  if r.ImGui_WindowFlags_NoMouseInputs then
    win_flags = win_flags | r.ImGui_WindowFlags_NoMouseInputs()
  else
    return
  end
  if r.ImGui_WindowFlags_NoScrollbar then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  r.ImGui_SetCursorScreenPos(ctx, wx + 1, wy + 1)
  local opened = r.ImGui_BeginChild(ctx, "##seq_os_file_drop", math.max(1, ww - 2), math.max(1, wh - 2), 0, win_flags)
  if opened then
    r.ImGui_EndChild(ctx)
  end
  seq_stem_import_accept_file_drop()
  r.ImGui_SetCursorScreenPos(ctx, cx, cy)
end

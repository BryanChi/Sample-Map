-- Sample Map Browser module: seq_sync
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_apply_vary_filter_range(region, track_id, col_min, col_max, start_qn, step_qn, filter_text)
  if not region or track_id == nil then
    return false
  end
  local pattern = get_seq_pattern(region.pattern_id, true)
  if not pattern then
    return false
  end
  local region_start = region.start_qn or 0.0
  local region_end = region_start + get_seq_region_length_qn(region)
  local changed = false
  for col = col_min, col_max do
    local cell_qn = start_qn + col * step_qn
    if cell_qn >= region_start - 1e-9 and cell_qn < region_end - 1e-9 then
      local step_key = seq_region_step_key(region, cell_qn, step_qn)
      if seq_set_cell_vary_filter(pattern, track_id, step_key, filter_text) then
        changed = true
      end
    end
  end
  if seq_stamp_notes_in_filter_range(region, track_id, col_min, col_max, start_qn, step_qn, filter_text) then
    changed = true
  end
  return changed
end

function seq_cancel_vary_filter_edit()
  state.seq_vary_filter_edit = nil
end

function seq_begin_vary_filter_edit(region, track_id, col_min, col_max, start_qn, step_qn, text, orig)
  if not region or track_id == nil then
    return
  end
  col_min = math.min(col_min or 0, col_max or 0)
  col_max = math.max(col_min, col_max or col_min)
  state.seq_vary_filter_edit = {
    region_id = region.id,
    track_id = track_id,
    col_min = col_min,
    col_max = col_max,
    start_qn = start_qn,
    step_qn = step_qn,
    text = text or "",
    orig = orig,
    focus = true,
    hovered = false,
  }
end

function seq_commit_vary_filter_edit()
  local edit = state.seq_vary_filter_edit
  if not edit then
    return false
  end
  local region = get_seq_region_by_id(edit.region_id)
  local text = seq_trim_text(edit.text)
  state.seq_vary_filter_edit = nil
  if not region then
    return false
  end
  if text == (edit.orig or "") then
    return false
  end
  local label = begin_seq_undo(text ~= "" and "Set sequencer vary filter" or "Clear sequencer vary filter")
  local changed = seq_apply_vary_filter_range(
    region, edit.track_id, edit.col_min, edit.col_max, edit.start_qn, edit.step_qn, text
  )
  if changed then
    local slot = seq_find_slot_by_id(edit.track_id)
    if slot then
      sync_seq_pattern_track(region.pattern_id, slot, { force_rebuild = true })
    else
      sync_seq_pattern_regions(region.pattern_id)
    end
    if seq_schedule_ingest_save then
      seq_schedule_ingest_save()
    else
      save_config()
    end
  end
  end_seq_undo(label)
  return changed
end

function seq_vary_filter_edit_blocks_clicks()
  local edit = state.seq_vary_filter_edit
  return edit and edit.hovered == true
end

function seq_apply_lock_range(region, track_id, col_min, col_max, start_qn, step_qn, lock, active_cells)
  if not region or track_id == nil then
    return false
  end
  local region_start = region.start_qn or 0.0
  local region_end = region_start + get_seq_region_length_qn(region)
  local changed = false
  for col = col_min, col_max do
    local cell_qn = start_qn + col * step_qn
    if cell_qn >= region_start - 1e-9 and cell_qn < region_end - 1e-9 then
      local active = active_cells and active_cells[track_id] and active_cells[track_id][col]
      local applied_note = false
      if active then
        seq_for_each_active_note(active, function(entry)
          if entry.region_id and entry.region_id ~= region.id then
            return
          end
          if seq_apply_lock_to_step(region, track_id, entry.key, lock, entry.note) then
            changed = true
          end
          applied_note = true
        end)
      end
      if not applied_note then
        local step_key = seq_region_step_key(region, cell_qn, step_qn)
        if seq_apply_lock_to_step(region, track_id, step_key, lock, nil) then
          changed = true
        end
      end
    end
  end
  return changed
end

function insert_seq_note_hit(tr, region, track_id, step_key, note, resolved_path, hit_start_qn, hit_length_qn, humanize_ms, random_seed, resolved_sample, opts)
  opts = opts or {}
  local start_time = qn_to_time(hit_start_qn)
  local end_time = qn_to_time(hit_start_qn + hit_length_qn)
  if not start_time or not end_time or end_time <= start_time then
    return nil
  end

  local item_len = end_time - start_time
  local dt = seq_humanize_time_offset_sec(region, track_id, step_key, humanize_ms, random_seed)
  if dt ~= 0.0 then
    start_time = math.max(0.0, start_time + dt)
  end
  local time_offset = opts.time_offset_sec or 0.0
  if time_offset > 0.0 then
    start_time = start_time + time_offset
    item_len = item_len - time_offset
  end
  if opts.length_sec and opts.length_sec > 0 then
    item_len = math.min(item_len, opts.length_sec)
  end
  local max_len_sec = seq_sample_source_length_sec(resolved_path, resolved_sample)
  local startoffs = opts.startoffs
  if startoffs == nil and note and type(note.source_offset) == "number" then
    startoffs = note.source_offset
  end
  if startoffs == nil then
    startoffs = get_sample_start_offset(resolved_sample)
  end
  local stretch = seq_note_stretch_amount(note)
  if not opts.ghost then
    stretch = stretch * seq_humanize_stretch_mul(region, track_id, step_key, opts.hit_idx)
    if stretch < SEQ_STRETCH_MIN then stretch = SEQ_STRETCH_MIN end
    if stretch > SEQ_STRETCH_MAX then stretch = SEQ_STRETCH_MAX end
  end
  if max_len_sec and max_len_sec > 0 then
    local remaining0 = math.max(0.001, max_len_sec - startoffs)
    startoffs = startoffs + seq_note_start_frac(note) * remaining0
    if startoffs > max_len_sec - 0.001 then
      startoffs = max_len_sec - 0.001
    end
    local remaining = math.max(0.001, max_len_sec - startoffs)
    -- Stretch longer keeps the current end; stretch shorter may pull it in.
    item_len = math.min(item_len, remaining, remaining * stretch)
  end
  local len_mul = 1.0
  if not opts.ghost then
    len_mul = seq_humanize_length_mul(region, track_id, step_key, opts.hit_idx)
    if len_mul < 0.9995 then
      item_len = math.max(0.002, item_len * len_mul)
    end
  end
  local fade_in = opts.fade_in or 0.0
  local fade_out = opts.fade_out or 0.0
  if item_len < fade_in + fade_out + 0.001 then
    local need = fade_in + fade_out + 0.001
    if item_len < 0.002 then
      return nil
    end
    if need > item_len then
      local scale = item_len / need
      fade_in = fade_in * scale
      fade_out = fade_out * scale
    end
  end
  if item_len <= 0.000001 then
    return nil
  end

  local item = r.AddMediaItemToTrack(tr)
  if not item then
    return nil
  end
  r.SetMediaItemPosition(item, start_time, false)
  r.SetMediaItemLength(item, item_len, false)

  local take = r.AddTakeToMediaItem(item)
  if take then
    local src = seq_pcm_take_src_get(resolved_path)
    if src then
      r.SetMediaItemTake_Source(take, src)
      set_item_name(item, take, resolved_path)
      apply_seq_note_params(item, take, note)
      if not opts.ghost then
        local pitch = (tonumber(note.pitch) or 0.0) + seq_humanize_pitch_offset(region, track_id, step_key, opts.hit_idx)
        if pitch < -24.0 then pitch = -24.0 elseif pitch > 24.0 then pitch = 24.0 end
        r.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch)
        r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0 / stretch)
      end
      seq_apply_drum_rubber_band_stretch(take, stretch, resolved_sample, find_seq_track_by_id(track_id))
      if startoffs > 0 then
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startoffs)
      end
    end
  end

  set_item_ext(item, SEQ_EXT_FLAG, "1")
  set_item_ext(item, SEQ_EXT_REGION, region.id)
  set_item_ext(item, SEQ_EXT_PATTERN, region.pattern_id)
  set_item_ext(item, SEQ_EXT_TRACK, track_id)
  set_item_ext(item, SEQ_EXT_STEP, step_key)
  if opts.layer_piece then
    set_item_ext(item, SEQ_EXT_LAYER, "1")
  end
  if opts.ghost then
    set_item_ext(item, SEQ_EXT_GHOST, tostring(opts.ghost))
  end
  -- Assigning source / stretching item length can re-enable loop; force off last.
  r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  if not seq_defer_item_updates and r.UpdateItemInProject then
    r.UpdateItemInProject(item)
  end
  seq_mark_self_arrange_write()

  -- Apply drum envelope last so earlier item/chunk writes can't wipe it.
  if take then
    local slot = find_seq_track_by_id(track_id)
    if slot then
      seq_normalize_slot_mix(slot)
      seq_apply_take_volume_envelope(take, item_len, slot.env, opts.time_offset_sec or 0.0)
    end
  end
  -- Volume last: item stays at 1, take is note velocity * blend.
  local scale = opts.vol_scale
  if scale == nil then scale = 1.0 end
  if take then
    local vel = tonumber(note.volume) or 1.0
    if not opts.ghost then
      vel = seq_humanize_note_velocity(vel, region, track_id, step_key, hit_start_qn, opts.hit_idx)
    end
    r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
    r.SetMediaItemTakeInfo_Value(take, "D_VOL", vel * scale * get_sample_gain(resolved_sample))
  end
  if opts.layer_piece then
    seq_item_apply_layer_fades(item, fade_in, fade_out)
  end
  local apply_in = opts.note_fade_in
  local apply_out = opts.note_fade_out
  if apply_in == nil then apply_in = true end
  if apply_out == nil then apply_out = true end
  if apply_in or apply_out then
    seq_apply_note_native_fades(
      item, item_len, note, hit_start_qn, apply_in, apply_out,
      { keep_existing = opts.layer_piece and true or false }
    )
  end
  if not opts.ghost and len_mul < 0.9995 then
    local fade_sec = seq_humanize_fade_out_sec(region, track_id, step_key, opts.hit_idx)
    if fade_sec > 0.0005 then
      local cur_in = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0.0
      seq_apply_native_item_fades(
        item, item_len, cur_in, fade_sec,
        r.GetMediaItemInfo_Value(item, "C_FADEINSHAPE"),
        r.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE"),
        { keep_existing = true }
      )
    end
  end
  return item
end

function seq_insert_note_ghosts(tr, region, slot, track_id, step_key, note, path, sample, settings, first_qn, first_len, last_qn, last_len)
  if not tr or not first_qn then
    return
  end
  last_qn = last_qn or first_qn
  first_len = first_len or (state.seq_grid_qn or 0.25)
  last_len = last_len or first_len
  local function place(which, start_qn, close_qn, vary_amt, frozen_path, frozen_name, vol_mul)
    local ghost_len = math.max(0.03, math.min(close_qn * 1.35, first_len * 0.45))
    vary_amt = tonumber(vary_amt) or 0.0
    local gpath, gsample = path, sample
    if type(frozen_path) == "string" and frozen_path ~= "" and seq_path_exists(frozen_path) then
      gpath = frozen_path
      gsample = find_sample_by_path(frozen_path) or { name = frozen_name, path = frozen_path }
    elseif vary_amt > 0.000001 then
      local vpath, vsample = seq_resolve_note_sample(note, slot, vary_amt, region, track_id, step_key)
      if vpath then
        gpath, gsample = vpath, vsample
      end
    end
    local mul = tonumber(vol_mul)
    if mul == nil then
      mul = seq_ghost_pick_volume(settings, which, region, track_id, step_key)
    end
    local ghost_note = {
      volume = math.max(0.0, (tonumber(note.volume) or 1.0) * mul),
      pan = note.pan or 0.0,
      pitch = note.pitch or 0.0,
      sample_path = note.sample_path,
      sample_vary = vary_amt,
      stutter = 1,
    }
    insert_seq_note_hit(
      tr, region, track_id, step_key, ghost_note, gpath,
      start_qn, ghost_len,
      0.0, 0,
      gsample,
      {
        ghost = which,
        vol_scale = 1.0,
        note_fade_in = true,
        note_fade_out = true,
        hit_idx = (which == "after") and 90 or 0,
      }
    )
  end
  if seq_note_is_locked(note) then
    local g = note.locked_ghosts
    if type(g) ~= "table" then
      return
    end
    if g.grace then
      place("grace", first_qn - g.grace, g.grace, g.grace_vary, g.grace_path, g.grace_name, g.grace_vol)
    end
    if g.after then
      place("after", last_qn + math.max(0.02, g.after * 0.35), g.after, g.after_vary, g.after_path, g.after_name, g.after_vol)
    end
    return
  end
  if not seq_settings_ghost_active(settings) then
    return
  end
  local abs_qn = seq_note_abs_qn(region, note, step_key, state.seq_grid_qn or 0.25) or first_qn
  local do_grace, grace_qn = seq_ghost_should_place(settings, "grace", region, track_id, step_key, abs_qn)
  if do_grace then
    place("grace", first_qn - grace_qn, grace_qn, seq_ghost_vary_amount(settings, "grace", region, track_id, step_key))
  end
  local do_after, after_qn = seq_ghost_should_place(settings, "after", region, track_id, step_key, abs_qn)
  if do_after then
    place("after", last_qn + math.max(0.02, after_qn * 0.35), after_qn, seq_ghost_vary_amount(settings, "after", region, track_id, step_key))
  end
end

function insert_seq_note_item(region, slot, track_id, step_key, note)
  if not region or not slot or not note then
    return nil
  end

  local resolved_path, resolved_sample = seq_resolve_note_sample(
    note, slot, seq_random_vary_amount(note, region, track_id, step_key, 1),
    region, track_id, step_key
  )
  if not resolved_path then
    return nil
  end
  if not seq_path_exists(resolved_path) then
    log("Sequencer sample missing: " .. tostring(resolved_path))
    return nil
  end

  local tr = get_seq_slot_target_track(slot)
  if not tr then
    log("No target track for sequencer note")
    return nil
  end

  local pattern = get_seq_pattern(region.pattern_id, false)
  local track_settings = get_seq_track_settings(pattern, track_id, false) or {}
  local probability = track_settings.probability or 1.0
  local probability_seed = track_settings.probability_seed or track_settings.seed or 0
  local humanize_seed = track_settings.humanize_seed or track_settings.seed or 0
  if not seq_note_passes_probability(region, track_id, step_key, probability, probability_seed) then
    return nil
  end

  local grid_qn = state.seq_grid_qn or 0.25
  local stutter_count = seq_random_stutter_count(note, region, track_id, step_key)
  -- Random stutter must drive hit offsets/lengths; painted note.stutter stays 1
  -- until lock-bake, so span math on the raw note stacks every hit at t0.
  local span_note = seq_note_for_stutter_render(note, stutter_count)
  local step_idx = tonumber(step_key) or 0
  if not seq_note_in_region(region, note, step_key, grid_qn) then
    return nil
  end
  local cell_start_qn = seq_note_abs_qn(region, note, step_key, grid_qn)
  local groove_qn = seq_groove_offset_qn(cell_start_qn, get_seq_region_groove(region))
  local humanize_ms = track_settings.humanize_ms or 0.0

  local first_item = nil
  local first_start_qn, first_len_qn, last_start_qn, last_len_qn
  local pieces = (seq_layering_is_active and seq_layering_is_active(slot))
    and seq_layering_build_pieces(slot) or {}
  for i = 0, stutter_count - 1 do
    local hit_idx = i + 1
    local hit_note = seq_note_for_stutter_hit(note, hit_idx)
    local vary_amt = seq_random_vary_amount(hit_note, region, track_id, step_key, hit_idx)
    local hit_path, hit_sample = seq_resolve_note_sample(hit_note, slot, vary_amt, region, track_id, step_key)
    if not hit_path then
      hit_path, hit_sample = resolved_path, resolved_sample
    end
    local hit_len_qn = seq_effective_note_length_qn(
      region, pattern, slot, track_id, step_idx, span_note, hit_sample, grid_qn, hit_idx
    )
    local hit_offset = hit_note.offset_qn or 0.0
    local off0 = seq_stutter_hit_span(span_note, hit_idx, grid_qn)
    local hit_start_qn = cell_start_qn + groove_qn + hit_offset + (off0 or 0.0)
    if hit_start_qn < 0.0 then hit_start_qn = 0.0 end
    local apply_fade_in = (i == 0)
    local apply_fade_out = (i == stutter_count - 1)
    if #pieces > 0 then
      for p = 1, #pieces do
        local piece = pieces[p]
        if piece.path and seq_path_exists(piece.path) then
          local item = insert_seq_note_hit(
            tr, region, track_id, step_key, hit_note, piece.path,
            hit_start_qn, hit_len_qn,
            (i == 0) and humanize_ms or 0.0,
            humanize_seed,
            piece.sample,
            {
              layer_piece = true,
              startoffs = piece.startoffs or 0.0,
              length_sec = piece.length_sec,
              vol_scale = piece.weight or 1.0,
              time_offset_sec = piece.time_offset_sec or 0.0,
              fade_in = piece.fade_in or 0.0,
              fade_out = piece.fade_out or 0.0,
              note_fade_in = apply_fade_in and (p == 1),
              note_fade_out = apply_fade_out and (p == #pieces),
              hit_idx = hit_idx,
            }
          )
          if item and not first_item then
            first_item = item
          end
        end
      end
    else
      local item = insert_seq_note_hit(
        tr, region, track_id, step_key, hit_note, hit_path,
        hit_start_qn, hit_len_qn,
        (i == 0) and humanize_ms or 0.0,
        humanize_seed,
        hit_sample,
        {
          note_fade_in = apply_fade_in,
          note_fade_out = apply_fade_out,
          hit_idx = hit_idx,
        }
      )
      if item and not first_item then
        first_item = item
      end
    end
    if i == 0 then
      first_start_qn = hit_start_qn
      first_len_qn = hit_len_qn
    end
    last_start_qn = hit_start_qn
    last_len_qn = hit_len_qn
  end
  seq_insert_note_ghosts(
    tr, region, slot, track_id, step_key, note,
    resolved_path, resolved_sample, track_settings,
    first_start_qn, first_len_qn, last_start_qn, last_len_qn
  )
  return first_item
end

function remove_seq_rendered_items_for_track(region, slot, track_id)
  if not region then
    return 0
  end
  local region_id = region.id
  local track_key = tostring(track_id)
  local removed = 0
  local function scan_track(tr)
    if not tr then
      return
    end
    for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item, region_id)
         and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == track_key then
        if r.DeleteTrackMediaItem(tr, item) then
          removed = removed + 1
        end
      end
    end
  end
  -- An unlinked slot renders on whichever track was selected at the time,
  -- so find its items by tag on every track.
  local tr = slot and seq_ingest_slot_track(slot)
  if tr then
    scan_track(tr)
  else
    for tr_idx = 0, r.CountTracks(0) - 1 do
      scan_track(r.GetTrack(0, tr_idx))
    end
  end
  if removed > 0 then
    seq_mark_self_arrange_write()
  end
  return removed
end

function remove_seq_rendered_items_for_step(region, slot, track_id, step_key)
  if not region then
    return 0
  end
  local region_id = region.id
  local track_key = tostring(track_id)
  local step = tostring(step_key)
  local removed = 0
  local function scan_track(tr)
    if not tr then
      return
    end
    for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item, region_id)
         and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == track_key
         and tostring(get_item_ext(item, SEQ_EXT_STEP) or "") == step then
        if r.DeleteTrackMediaItem(tr, item) then
          removed = removed + 1
        end
      end
    end
  end
  -- An unlinked slot renders on whichever track was selected at the time,
  -- so find its items by tag on every track.
  local tr = slot and seq_ingest_slot_track(slot)
  if tr then
    scan_track(tr)
  else
    for tr_idx = 0, r.CountTracks(0) - 1 do
      scan_track(r.GetTrack(0, tr_idx))
    end
  end
  if removed > 0 then
    seq_mark_self_arrange_write()
  end
  return removed
end

function seq_prune_stale_region_items(region)
  if not region then
    return 0
  end
  local region_id = region.id
  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local removed = 0
  local tr_count = r.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = r.GetTrack(0, tr_idx)
    for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item, region_id) then
        local step = tostring(get_item_ext(item, SEQ_EXT_STEP) or "")
        local track_id = tonumber(get_item_ext(item, SEQ_EXT_TRACK) or "")
          or get_item_ext(item, SEQ_EXT_TRACK)
        local note = (step ~= "" and track_id) and get_seq_note(region, track_id, step) or nil
        if not note or not seq_note_in_region(region, note, step, grid_qn) then
          if r.DeleteTrackMediaItem(tr, item) then
            removed = removed + 1
          end
        end
      end
    end
  end
  if removed > 0 then
    seq_mark_self_arrange_write()
  end
  return removed
end

-- Swap take sources on existing hits when the item layout is unchanged.
-- Returns false if the track must be deleted and rebuilt instead.
function seq_retarget_region_track_sources(region, slot)
  if not region or not slot or not slot.sample_path then
    return false
  end
  if seq_layering_is_active and seq_layering_is_active(slot) then
    return false
  end
  local tr = get_seq_slot_target_track(slot)
  if not tr then
    return false
  end
  local pattern = get_seq_pattern(region.pattern_id, false)
  if not pattern then
    return false
  end
  local track_notes = get_track_note_table(pattern, slot.id, false)
  if not track_notes then
    return false
  end

  local region_id = region.id
  local track_key = tostring(slot.id)
  local items_by_step = {}
  local item_n = 0
  for item_idx = 0, r.CountTrackMediaItems(tr) - 1 do
    local item = r.GetTrackMediaItem(tr, item_idx)
    if item and seq_item_is_owned(item, region_id)
       and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == track_key then
      if seq_item_is_aux_piece(item) then
        return false
      end
      local step = tostring(get_item_ext(item, SEQ_EXT_STEP) or "")
      local list = items_by_step[step]
      if not list then
        list = {}
        items_by_step[step] = list
      end
      list[#list + 1] = item
      item_n = item_n + 1
    end
  end

  local track_settings = get_seq_track_settings(pattern, slot.id, false) or {}
  if seq_settings_vary_active(track_settings) or seq_settings_stutter_active(track_settings)
     or seq_settings_ghost_active(track_settings) then
    return false
  end
  local probability = track_settings.probability or 1.0
  local probability_seed = track_settings.probability_seed or track_settings.seed or 0
  local expected = {}
  local expected_hits = 0
  for step_key, note in pairs(track_notes) do
    if type(note) == "table" and note.enabled ~= false
       and seq_note_in_region(region, note, step_key)
       and seq_note_passes_probability(region, slot.id, step_key, probability, probability_seed) then
      if seq_note_has_hit_sample_vary(note) then
        return false
      end
      local stutter = seq_stutter_count(note)
      expected[tostring(step_key)] = { note = note, hits = stutter }
      expected_hits = expected_hits + stutter
    end
  end
  if expected_hits ~= item_n then
    return false
  end
  for step, info in pairs(expected) do
    local items = items_by_step[step]
    if not items or #items ~= info.hits then
      return false
    end
  end
  for step, _ in pairs(items_by_step) do
    if not expected[step] then
      return false
    end
  end

  local grid_qn = state.seq_grid_qn or 0.25
  if seq_normalize_slot_mix then
    seq_normalize_slot_mix(slot)
  end

  seq_pcm_take_src_begin()
  local ok = true
  for step, info in pairs(expected) do
    if not ok then
      break
    end
    local note = info.note
    local resolved_path, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot.id, step)
    if not resolved_path or not seq_path_exists(resolved_path) then
      ok = false
      break
    end
    local max_len = seq_sample_source_length_sec(resolved_path, resolved_sample)
    local step_idx = tonumber(step) or 0
    local hit_len_qn = seq_effective_note_length_qn(
      region, pattern, slot, slot.id, step_idx, note, resolved_sample, grid_qn
    )
    local items = items_by_step[step]
    for i = 1, #items do
      local item = items[i]
      local take = r.GetActiveTake(item)
      local src = take and seq_pcm_take_src_get(resolved_path)
      if not take or not src then
        ok = false
        break
      end
      r.SetMediaItemTake_Source(take, src)
      set_item_name(item, take, resolved_path)
      r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.0)
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local old_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local pos_qn = time_to_qn(pos)
      local item_len = nil
      if pos_qn and hit_len_qn then
        local end_time = qn_to_time(pos_qn + hit_len_qn)
        if end_time and end_time > pos then
          item_len = end_time - pos
        end
      end
      if item_len and max_len and max_len > 0 then
        item_len = math.min(item_len, max_len)
      end
      if item_len and item_len > 0.000001 then
        r.SetMediaItemLength(item, item_len, false)
        if math.abs((old_len or 0) - item_len) > 0.0001 then
          seq_apply_take_volume_envelope(take, item_len, slot.env, 0.0)
        end
      end
      seq_apply_note_native_fades(
        item, item_len or old_len, note, pos_qn or 0.0, i == 1, i == #items
      )
      r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
      if r.UpdateItemInProject then
        r.UpdateItemInProject(item)
      end
    end
  end
  seq_pcm_take_src_end()
  if not ok then
    return false
  end
  seq_mark_self_arrange_write()
  return true
end

function sync_seq_region_track(region, slot, opts)
  opts = opts or {}
  if not region or not slot then
    return
  end
  local own_refresh = not opts.skip_arrange
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  local retargeted = (not opts.force_rebuild) and seq_retarget_region_track_sources(region, slot)
  if not retargeted then
    remove_seq_rendered_items_for_track(region, slot, slot.id)
    local pattern = get_seq_pattern(region.pattern_id, false)
    local track_notes = pattern and get_track_note_table(pattern, slot.id, false)
    if track_notes then
      seq_pcm_take_src_begin()
      local prev_defer = seq_defer_item_updates
      seq_defer_item_updates = true
      for step_key, note in pairs(track_notes) do
        if type(note) == "table" and note.enabled ~= false
           and seq_note_in_region(region, note, step_key) then
          insert_seq_note_item(region, slot, slot.id, step_key, note)
        end
      end
      seq_defer_item_updates = prev_defer
      seq_pcm_take_src_end()
    end
  end
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if not opts.skip_arrange then
    r.UpdateArrange()
  end
end

function sync_seq_pattern_track(pattern_id, slot, opts)
  if not pattern_id or not slot then
    return
  end
  opts = opts or {}
  local own_refresh = not opts.skip_arrange
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  for _, region in ipairs(state.seq_regions) do
    if region.pattern_id == pattern_id then
      sync_seq_region_track(region, slot, {
        skip_arrange = true,
        force_rebuild = opts.force_rebuild,
      })
    end
  end
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if not opts.skip_arrange then
    r.UpdateArrange()
  end
end

function sync_seq_slot_all_regions(slot, opts)
  if not slot then
    return
  end
  opts = opts or {}
  local own_refresh = not opts.skip_arrange
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  for _, region in ipairs(state.seq_regions or {}) do
    sync_seq_region_track(region, slot, {
      skip_arrange = true,
      force_rebuild = opts.force_rebuild,
    })
  end
  if own_refresh and r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if not opts.skip_arrange then
    r.UpdateArrange()
  end
end

function seq_previous_step_key(pattern, track_id, step_key, region)
  local track_notes = get_track_note_table(pattern, track_id, false)
  if not track_notes then
    return nil
  end
  local target = track_notes[tostring(step_key)]
  local target_qn = seq_note_qn_offset(target, step_key)
  local prev_key = nil
  local prev_qn = nil
  for sk, nnote in pairs(track_notes) do
    if type(nnote) == "table" and nnote.enabled ~= false then
      local qn = seq_note_qn_offset(nnote, sk)
      if qn < target_qn - 1e-9 and (not prev_qn or qn > prev_qn) then
        prev_qn = qn
        prev_key = tostring(sk)
      end
    end
  end
  return prev_key
end

function sync_seq_single_note(region, slot, step_key, opts)
  opts = opts or {}
  if not region or not slot then
    return
  end
  step_key = tostring(step_key)
  local note = get_seq_note(region, slot.id, step_key)
  remove_seq_rendered_items_for_step(region, slot, slot.id, step_key)
  if note and note.enabled ~= false and seq_note_in_region(region, note, step_key) then
    insert_seq_note_item(region, slot, slot.id, step_key, note)
  end
  if not opts.skip_neighbor and (state.seq_force_item_crop or not slot.overlap) then
    local pattern = get_seq_pattern(region.pattern_id, false)
    local prev_key = seq_previous_step_key(pattern, slot.id, step_key, region)
    if prev_key and prev_key ~= step_key then
      local prev_note = get_seq_note(region, slot.id, prev_key)
      remove_seq_rendered_items_for_step(region, slot, slot.id, prev_key)
      if prev_note and prev_note.enabled ~= false and seq_note_in_region(region, prev_note, prev_key) then
        insert_seq_note_item(region, slot, slot.id, prev_key, prev_note)
      end
    end
  end
end

function sync_seq_pattern_note(pattern_id, slot, step_key, opts)
  if not pattern_id or not slot then
    return
  end
  for _, region in ipairs(state.seq_regions) do
    if region.pattern_id == pattern_id then
      sync_seq_single_note(region, slot, step_key, opts)
    end
  end
end

function sync_seq_region(region, opts)
  if not region then
    return
  end
  opts = opts or {}
  if not opts.skip_cache_clear then
    clear_seq_vary_rank_cache()
  end
  if not opts.skip_remove then
    remove_seq_rendered_items(region)
  end

  local pattern = get_seq_pattern(region.pattern_id, false)
  if not pattern or type(pattern.notes) ~= "table" then
    seq_sync_region_parent_item(region)
    if not opts.skip_arrange then
      r.UpdateArrange()
    end
    return
  end

  local own_refresh = not opts.skip_arrange
  if own_refresh and r.PreventUIRefresh then r.PreventUIRefresh(1) end
  local prev_defer = seq_defer_item_updates
  seq_defer_item_updates = true
  seq_pcm_take_src_begin()
  for _, slot in ipairs(state.seq_tracks) do
    seq_normalize_slot_mix(slot)
    if not opts.skip_mix then
      seq_apply_slot_mix_to_reaper_track(slot)
    end
    local track_notes = get_track_note_table(pattern, slot.id, false)
    if track_notes then
      for step_key, note in pairs(track_notes) do
        if type(note) == "table" and note.enabled ~= false
           and seq_note_in_region(region, note, step_key) then
          insert_seq_note_item(region, slot, slot.id, step_key, note)
        end
      end
    end
  end
  seq_pcm_take_src_end()
  seq_defer_item_updates = prev_defer
  if own_refresh and r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  seq_sync_region_parent_item(region)
  if not opts.skip_arrange then
    r.UpdateArrange()
  end
end

function sync_seq_pattern_regions(pattern_id)
  local pid = tonumber(pattern_id) or pattern_id
  for _, region in ipairs(state.seq_regions) do
    if (tonumber(region.pattern_id) or region.pattern_id) == pid then
      sync_seq_region(region)
    end
  end
end

function seq_sync_linked_arrange_from(region, changed_slots)
  if not region or not region.pattern_id then
    return
  end
  local pid = tonumber(region.pattern_id) or region.pattern_id
  local others = {}
  for _, other in ipairs(state.seq_regions or {}) do
    if other.id ~= region.id and (tonumber(other.pattern_id) or other.pattern_id) == pid then
      others[#others + 1] = other
    end
  end
  if #others == 0 then
    return
  end
  -- The ingested copy already updated shared notes from arrange. Push those
  -- notes onto the other pooled copies so they stay linked, but never rewrite
  -- the copy that was just ingested.
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  local touched = false
  if type(changed_slots) == "table" then
    -- Rebuild the tracks whose notes changed. Counting items missed edits
    -- that keep the count (volume, pitch, a nudge inside the cell).
    for _, slot in ipairs(state.seq_tracks or {}) do
      if changed_slots[slot.id] then
        for i = 1, #others do
          sync_seq_region_track(others[i], slot, { skip_arrange = true, force_rebuild = true })
        end
        touched = true
      end
    end
  else
    local rebuild = {}
    for i = 1, #others do
      if seq_prune_stale_region_items(others[i]) > 0 then
        touched = true
      end
    end
    -- Pruning only touches each region's own items, so count all regions in
    -- one scan afterwards instead of rescanning every track per region.
    local owned_counts = seq_count_owned_primary_items_by_region()
    for i = 1, #others do
      local item_n = owned_counts[others[i].id] or 0
      local note_n = seq_region_expected_primary_notes(others[i])
      if item_n ~= note_n then
        rebuild[#rebuild + 1] = others[i]
      end
    end
    for i = 1, #rebuild do
      sync_seq_region(rebuild[i], { skip_cache_clear = true, skip_arrange = true })
      touched = true
    end
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if touched then
    r.UpdateArrange()
  end
end

-- Sample Map Browser module: seq_tracks
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Sequencer track helpers -------------------------------------------------
-- guid -> MediaTrack from the last full scan. A hit is only trusted after
-- checking the pointer is a live track in the current project with that GUID;
-- anything else rescans (and refreshes the whole map), so results match a scan.
seq_track_by_guid_cache = {}

function get_track_by_guid(track_guid)
  if not track_guid or track_guid == "" then
    return nil
  end
  -- Cached as { track, index }: the track must still sit at that index in the
  -- current project (catches deletes, reorders and project switches).
  local cached = seq_track_by_guid_cache[track_guid]
  if cached and r.GetTrack(0, cached[2]) == cached[1]
      and r.GetTrackGUID(cached[1]) == track_guid then
    return cached[1]
  end
  local map = {}
  local found = nil
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    local tr = r.GetTrack(0, i)
    local guid = r.GetTrackGUID(tr)
    if guid and map[guid] == nil then
      map[guid] = { tr, i }
    end
    if not found and guid == track_guid then
      found = tr
    end
  end
  seq_track_by_guid_cache = map
  return found
end

function get_project_tracks_list()
  local tracks = {}
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    local tr = r.GetTrack(0, i)
    local _, name = r.GetTrackName(tr)
    tracks[#tracks + 1] = {
      track = tr,
      guid = r.GetTrackGUID(tr),
      name = name ~= "" and name or ("Track " .. (i + 1)),
    }
  end
  return tracks
end

function get_reaper_track_display_name(track_guid)
  if not track_guid then
    return nil
  end
  local tr = get_track_by_guid(track_guid)
  if not tr then
    return "(missing track)"
  end
  local _, name = r.GetTrackName(tr)
  if name and name ~= "" then
    return name
  end
  return "(unnamed track)"
end

function find_sample_by_path(path)
  if not path or path == "" then
    return nil
  end
  local hit = samples_by_path[path]
  if hit then
    return hit
  end
  local norm = normalize_path(path)
  if norm ~= path then
    hit = samples_by_path[norm]
    if hit then
      samples_by_path[path] = hit
      return hit
    end
  end
  local key = path_index_key(norm)
  if key ~= "" and key ~= norm then
    hit = samples_by_path[key]
    if hit then
      samples_by_path[path] = hit
      samples_by_path[norm] = hit
      return hit
    end
  end
  -- Fallback once if index is stale (then cache). Case-insensitive for
  -- external volumes whose enumeration casing does not match the cache.
  -- Misses are remembered until the library changes (explorer rows for files
  -- not in the library would otherwise rescan every sample every frame).
  if sample_path_miss_list ~= state.samples then
    sample_path_miss = {}
    sample_path_miss_list = state.samples
  end
  local lib_n = #state.samples
  if sample_path_miss[path] == lib_n then
    return nil
  end
  for _, s in ipairs(state.samples) do
    if s.path == path or s.path == norm then
      samples_by_path[path] = s
      return s
    end
    if s.path and key ~= "" and path_index_key(s.path) == key then
      samples_by_path[path] = s
      samples_by_path[norm] = s
      samples_by_path[key] = s
      return s
    end
  end
  sample_path_miss[path] = lib_n
  return nil
end

function sample_drag_active()
  return state.pending_waveform_drop ~= nil
    or (state.is_left_dragging and state.last_dragged_sample_path ~= nil)
end

function get_active_dragged_sample()
  if state.pending_waveform_drop then
    return state.pending_waveform_drop
  end
  if state.last_dragged_sample_path then
    return find_sample_by_path(state.last_dragged_sample_path)
  end
  return nil
end

function begin_waveform_sample_drag(sample)
  if not sample or not sample.path or state.pending_waveform_drop then
    return false
  end
  state.pending_waveform_drop = sample
  state.waveform_drag_armed = nil
  state.is_left_dragging = false
  state.last_dragged_sample_path = nil
  if r.ImGui_SetMouseCursor then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
  end
  return true
end

function waveform_drag_should_start(hovered)
  if state.map_ui_edit or state.map_ui_drag then
    return false
  end
  if state.pending_waveform_drop then
    return false
  end
  if hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then
    state.waveform_drag_armed = true
  end
  if not (r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0)) then
    state.waveform_drag_armed = nil
    return false
  end
  if not (hovered or state.waveform_drag_armed) then
    return false
  end
  if r.ImGui_IsMouseDragging then
    return r.ImGui_IsMouseDragging(ctx, 0, 6.0)
  end
  return false
end

function seq_track_has_guid(guid)
  if not guid then
    return false
  end
  for _, slot in ipairs(state.seq_tracks) do
    if slot.reaper_track_guid == guid then
      return true
    end
  end
  return false
end

function clamp_selected_seq_track()
  if state.selected_seq_track and state.selected_seq_track > #state.seq_tracks then
    state.selected_seq_track = #state.seq_tracks > 0 and #state.seq_tracks or nil
  end
  if state.selected_seq_track and state.selected_seq_track < 1 then
    state.selected_seq_track = nil
  end
  if state.seq_swap_track_idx and state.seq_swap_track_idx > #state.seq_tracks then
    state.seq_swap_track_idx = nil
  end
end

function add_seq_track_from_reaper_track(tr)
  if not tr then
    return nil
  end
  local guid = r.GetTrackGUID(tr)
  if seq_track_has_guid(guid) then
    return nil
  end
  local _, name = r.GetTrackName(tr)
  local slot = {
    id = state.seq_track_next_id,
    name = name ~= "" and name or ("Track " .. (#state.seq_tracks + 1)),
    reaper_track_guid = guid,
    sample_path = nil,
    sample_name = nil,
  }
  seq_normalize_slot_mix(slot)
  state.seq_track_next_id = state.seq_track_next_id + 1
  table.insert(state.seq_tracks, slot)
  state.selected_seq_track = #state.seq_tracks
  return slot
end

function add_empty_seq_track()
  local slot = {
    id = state.seq_track_next_id,
    name = "Track " .. (#state.seq_tracks + 1),
    reaper_track_guid = nil,
    sample_path = nil,
    sample_name = nil,
  }
  seq_normalize_slot_mix(slot)
  state.seq_track_next_id = state.seq_track_next_id + 1
  table.insert(state.seq_tracks, slot)
  state.selected_seq_track = #state.seq_tracks
  return slot
end

function seq_clear_track_document_data(track_id)
  if track_id == nil then
    return
  end
  local key = tostring(track_id)

  for _, pattern in pairs(state.seq_patterns or {}) do
    if type(pattern) == "table" then
      if type(pattern.notes) == "table" then
        pattern.notes[key] = nil
      end
      if type(pattern.track_settings) == "table" then
        pattern.track_settings[key] = nil
      end
    end
  end

  for _, region in ipairs(state.seq_regions or {}) do
    if type(region.track_samples) == "table" then
      region.track_samples[key] = nil
      if next(region.track_samples) == nil then
        region.track_samples = nil
      end
    end
  end

  if state.seq_expanded_tracks then
    state.seq_expanded_tracks[key] = nil
  end
  if state.seq_track_play_anims then
    state.seq_track_play_anims[key] = nil
  end
  if state.seq_candidate_slide then
    state.seq_candidate_slide[track_id] = nil
  end
  if state.seq_nav_anchors then
    state.seq_nav_anchors[track_id] = nil
  end
  if state.seq_note_anims then
    for anim_key, anim in pairs(state.seq_note_anims) do
      if anim and anim.track_id == track_id then
        state.seq_note_anims[anim_key] = nil
      end
    end
  end

  if state.seq_razors then
    local kept = {}
    for _, razor in ipairs(state.seq_razors) do
      if type(razor) == "table" and type(razor.track_ids) == "table" then
        local ids = {}
        for _, id in ipairs(razor.track_ids) do
          if id ~= track_id then
            ids[#ids + 1] = id
          end
        end
        razor.track_ids = ids
        if #ids > 0 then
          kept[#kept + 1] = razor
        end
      else
        kept[#kept + 1] = razor
      end
    end
    state.seq_razors = kept
  end

  seq_random_sync_pending_forget_track(track_id)
  if state.seq_layering_slot_id == track_id then
    state.seq_layering_slot_id = nil
  end
  if state.seq_midi_popup_slot_id == track_id then
    state.seq_midi_popup_slot_id = nil
  end
  if state.seq_midi_learn_slot_id == track_id then
    state.seq_midi_learn_slot_id = nil
  end
  if state.seq_env_popup_slot_id == track_id then
    state.seq_env_popup_slot_id = nil
  end
  if state.map_hover_track_id == track_id then
    state.map_hover_track_id = nil
  end
  if state.seq_track_menu_id == track_id then
    state.seq_track_menu_id = nil
    state.seq_track_menu_want_open = nil
  end
  if state.seq_grid_hover and state.seq_grid_hover.slot_id == track_id then
    state.seq_grid_hover = nil
  end
  if state.seq_lane_h_drag and state.seq_lane_h_drag.slot_id == track_id then
    state.seq_lane_h_drag = nil
  end
  if state.seq_track_reorder_drag and state.seq_track_reorder_drag.slot_id == track_id then
    state.seq_track_reorder_drag = nil
  end
end

-- Remove a sequencer slot from the document. Does not touch REAPER tracks or undo.
function seq_remove_seq_track_slot(idx)
  if not idx or idx < 1 or idx > #(state.seq_tracks or {}) then
    return nil
  end
  local removed_slot = state.seq_tracks[idx]
  local removed_id = removed_slot and removed_slot.id
  table.remove(state.seq_tracks, idx)
  if removed_id then
    seq_clear_track_document_data(removed_id)
  end
  if state.seq_swap_track_id and removed_id and state.seq_swap_track_id == removed_id then
    if seq_clear_swap_mode_if_track then
      seq_clear_swap_mode_if_track(removed_id)
    else
      state.seq_swap_track_idx = nil
      state.seq_swap_track_id = nil
    end
  elseif state.seq_swap_track_idx then
    if state.seq_swap_track_idx == idx then
      state.seq_swap_track_idx = nil
    elseif state.seq_swap_track_idx > idx then
      state.seq_swap_track_idx = state.seq_swap_track_idx - 1
    end
  end
  if state.selected_seq_track then
    if #state.seq_tracks == 0 then
      state.selected_seq_track = nil
    elseif state.selected_seq_track == idx then
      state.selected_seq_track = math.min(idx, #state.seq_tracks)
    elseif state.selected_seq_track > idx then
      state.selected_seq_track = state.selected_seq_track - 1
    end
  end
  clamp_selected_seq_track()
  return removed_slot
end

function seq_delete_reaper_track_for_slot(slot)
  if not slot or not slot.reaper_track_guid or slot.reaper_track_guid == "" then
    return false
  end
  local tr = get_track_by_guid(slot.reaper_track_guid)
  if not tr or not r.DeleteTrack then
    return false
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  r.DeleteTrack(tr)
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if r.TrackList_AdjustWindows then
    r.TrackList_AdjustWindows(false)
  end
  r.UpdateArrange()
  seq_mark_self_arrange_write()
  return true
end

-- User-facing delete: drop the sequencer slot, its notes, and the linked arrange track.
function seq_delete_seq_track_at(idx, opts)
  opts = opts or {}
  local slot = state.seq_tracks and state.seq_tracks[idx]
  if not slot then
    return false
  end
  local own = false
  if opts.undo ~= false then
    own = seq_undo_own_begin("Delete sequencer track")
  end
  local delete_reaper = opts.delete_reaper ~= false
  if delete_reaper then
    seq_delete_reaper_track_for_slot(slot)
  end
  seq_remove_seq_track_slot(idx)
  if opts.persist ~= false then
    save_config()
    if save_seq_project_state then
      save_seq_project_state()
    end
  end
  if own then
    end_seq_undo("Delete sequencer track")
  end
  return true
end

function remove_selected_seq_track()
  if not state.selected_seq_track then
    return
  end
  seq_delete_seq_track_at(state.selected_seq_track)
end

SEQ_SAMPLE_CANDIDATES_MIN = 3
SEQ_SAMPLE_CANDIDATES_MAX = 12

function seq_candidate_entry_taken(entry)
  return type(entry) == "table" and type(entry.path) == "string" and entry.path ~= ""
end

function seq_compact_sample_candidates(slot)
  local src = slot and slot.sample_candidates
  if type(src) ~= "table" then
    return false
  end
  local old_idx = tonumber(slot.sample_candidate_idx)
  local dense = {}
  local mapped = nil
  local had_hole = false
  local seen_empty = false
  for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
    local entry = src[i]
    if seq_candidate_entry_taken(entry) then
      if seen_empty then
        had_hole = true
      end
      dense[#dense + 1] = entry
      if old_idx and i == old_idx then
        mapped = #dense
      end
    elseif #dense > 0 then
      seen_empty = true
    end
  end
  if not had_hole then
    return false
  end
  slot.sample_candidates = dense
  if mapped then
    slot.sample_candidate_idx = mapped
  else
    local idx = old_idx or 1
    if idx < 1 then
      idx = 1
    end
    slot.sample_candidate_idx = math.max(1, math.min(idx, math.max(1, #dense)))
  end
  return true
end

function seq_normalize_slot_candidates(slot)
  if not slot then
    return
  end
  if slot._cand_norm and type(slot.sample_candidates) == "table" then
    seq_compact_sample_candidates(slot)
    return
  end
  local src = slot.sample_candidates
  local list = {}
  local old_idx = tonumber(slot.sample_candidate_idx)
  local mapped = nil
  if type(src) == "table" then
    for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
      local entry = src[i]
      if type(entry) == "table" and type(entry.path) == "string" and entry.path ~= "" then
        list[#list + 1] = {
          path = entry.path,
          name = (type(entry.name) == "string" and entry.name ~= "" and entry.name) or basename(entry.path),
          x = tonumber(entry.x) or 0.5,
          y = tonumber(entry.y) or 0.5,
          dominant_freq = tonumber(entry.dominant_freq),
          brightness = tonumber(entry.brightness),
          sub_weight = tonumber(entry.sub_weight),
          effective_duration = tonumber(entry.effective_duration),
        }
        if old_idx and i == old_idx then
          mapped = #list
        end
      end
    end
  end
  slot.sample_candidates = list
  local idx = mapped
  if not idx then
    idx = old_idx
    if not idx or idx < 1 or idx > SEQ_SAMPLE_CANDIDATES_MAX then
      idx = 1
    end
    idx = math.max(1, math.min(idx, math.max(1, #list)))
  end
  slot.sample_candidate_idx = idx
  if not seq_candidate_entry_taken(list[1]) and type(slot.sample_path) == "string" and slot.sample_path ~= "" then
    local sample = find_sample_by_path(slot.sample_path) or {
      path = slot.sample_path,
      name = slot.sample_name,
    }
    list[1] = seq_candidate_entry_from_sample(sample)
  end
  slot._cand_norm = true
end

function seq_candidate_highest_taken(slot)
  local list = slot and slot.sample_candidates
  local high = 0
  if type(list) == "table" then
    for i = 1, SEQ_SAMPLE_CANDIDATES_MAX do
      if seq_candidate_entry_taken(list[i]) then
        high = i
      end
    end
  end
  return high
end

function seq_candidate_visible_count(slot)
  local visible = SEQ_SAMPLE_CANDIDATES_MIN
  local high = seq_candidate_highest_taken(slot)
  visible = math.max(visible, high)
  local list = slot and slot.sample_candidates
  local all_taken = high > 0
  if all_taken then
    for i = 1, visible do
      if not seq_candidate_entry_taken(list and list[i]) then
        all_taken = false
        break
      end
    end
  end
  if all_taken then
    visible = math.min(SEQ_SAMPLE_CANDIDATES_MAX, visible + 1)
  end
  return visible
end

function seq_candidate_entry_from_sample(sample)
  if not sample or not sample.path or sample.path == "" then
    return nil
  end
  local live = find_sample_by_path(sample.path) or sample
  local dur = nil
  if sample_map_duration then
    dur = sample_map_duration(live)
  end
  if type(dur) ~= "number" or dur <= 0 then
    dur = tonumber(live.effective_duration) or tonumber(live.duration)
  end
  return {
    path = live.path or sample.path,
    name = live.name or sample.name or basename(sample.path),
    x = tonumber(live.x) or 0.5,
    y = tonumber(live.y) or 0.5,
    dominant_freq = tonumber(live.dominant_freq),
    brightness = tonumber(live.brightness),
    sub_weight = tonumber(live.sub_weight),
    effective_duration = dur,
  }
end

function seq_candidate_sample_from_entry(entry)
  if not seq_candidate_entry_taken(entry) then
    return nil
  end
  return find_sample_by_path(entry.path) or {
    path = entry.path,
    name = entry.name,
    x = entry.x,
    y = entry.y,
    dominant_freq = entry.dominant_freq,
    brightness = entry.brightness,
    sub_weight = entry.sub_weight,
    effective_duration = entry.effective_duration,
    duration = entry.duration,
  }
end

function seq_drag_is_from_candidate()
  return state.seq_candidate_drag_source ~= nil
end

function seq_candidate_drag_from_slot(slot)
  local src = state.seq_candidate_drag_source
  return src ~= nil and slot ~= nil and src.slot_id == slot.id
end

function seq_candidate_is_drag_source(slot, idx)
  local src = state.seq_candidate_drag_source
  return src ~= nil and slot ~= nil
    and src.slot_id == slot.id
    and src.idx == idx
end

function seq_clear_candidate_drag_state()
  state.seq_candidate_press = nil
  state.seq_candidate_drag_source = nil
end

-- Automatic sample changes (randomize kit, Recent kits, arrow-key browsing,
-- stem import) run inside this so they don't overwrite the sample saved in
-- the selected candidate square. Only an explicit pick saves there.
SEQ_CANDIDATE_SAVE_BLOCK = 0

function seq_without_candidate_save(fn, ...)
  SEQ_CANDIDATE_SAVE_BLOCK = SEQ_CANDIDATE_SAVE_BLOCK + 1
  local res = table.pack(pcall(fn, ...))
  SEQ_CANDIDATE_SAVE_BLOCK = SEQ_CANDIDATE_SAVE_BLOCK - 1
  if not res[1] then
    error(res[2], 0)
  end
  return table.unpack(res, 2, res.n)
end

function seq_remember_sample_candidate(slot, sample)
  if not slot then
    return nil
  end
  seq_normalize_slot_candidates(slot)
  local idx = tonumber(slot.sample_candidate_idx)
  if not idx or idx < 1 or idx > SEQ_SAMPLE_CANDIDATES_MAX then
    return nil
  end
  local entry = seq_candidate_entry_from_sample(sample)
  if not entry then
    return nil
  end
  if (SEQ_CANDIDATE_SAVE_BLOCK or 0) > 0 and seq_candidate_entry_taken(slot.sample_candidates[idx]) then
    -- An automatic change may fill an empty square, never replace a saved one.
    return nil
  end
  slot.sample_candidates[idx] = entry
  return idx
end

function seq_begin_candidate_slide(slot, deleted_idx, boxes)
  if not slot or not slot.id or type(boxes) ~= "table" then
    return
  end
  deleted_idx = tonumber(deleted_idx)
  if not deleted_idx then
    return
  end
  local fade = nil
  local db = boxes[deleted_idx]
  local fade_entry = slot.sample_candidates and slot.sample_candidates[deleted_idx]
  if db and seq_candidate_entry_taken(fade_entry) then
    fade = {
      x = db.x, y = db.y, w = db.w, h = db.h,
      entry = fade_entry,
    }
  end
  local moves = {}
  for old_i = 1, #boxes do
    local box = boxes[old_i]
    if box and old_i ~= deleted_idx then
      local new_i = old_i > deleted_idx and (old_i - 1) or old_i
      moves[new_i] = { from_x = box.x, from_y = box.y }
    end
  end
  state.seq_candidate_slide = state.seq_candidate_slide or {}
  state.seq_candidate_slide[slot.id] = {
    start = r.time_precise(),
    duration = 0.28,
    moves = moves,
    fade = fade,
  }
end

function seq_candidate_slide_anim(slot)
  local anims = state.seq_candidate_slide
  if not anims or not slot or not slot.id then
    return nil
  end
  local anim = anims[slot.id]
  if not anim then
    return nil
  end
  local dur = anim.duration or 0.28
  if dur <= 0 then
    anims[slot.id] = nil
    return nil
  end
  local t = (r.time_precise() - (anim.start or r.time_precise())) / dur
  if t >= 1 then
    anims[slot.id] = nil
    return nil
  end
  t = math.max(0.0, t)
  local ease = 1.0 - (1.0 - t) ^ 3
  return anim, t, ease
end

function seq_remove_sample_candidate(slot, idx)
  if not slot then
    return false
  end
  seq_normalize_slot_candidates(slot)
  idx = tonumber(idx)
  if not idx or idx < 1 or idx > SEQ_SAMPLE_CANDIDATES_MAX then
    return false
  end
  if not seq_candidate_entry_taken(slot.sample_candidates[idx]) then
    return false
  end
  table.remove(slot.sample_candidates, idx)
  local sel = tonumber(slot.sample_candidate_idx) or 1
  if sel > idx then
    slot.sample_candidate_idx = sel - 1
  elseif sel == idx then
    if not seq_candidate_entry_taken(slot.sample_candidates[idx]) then
      slot.sample_candidate_idx = math.max(1, idx - 1)
    end
  end
  return true
end

function assign_sample_to_seq_track(slot, sample, persist)
  if not slot or not sample or not sample.path then
    return false
  end
  local old_path = slot.sample_path
  local path_changed = old_path ~= sample.path
  slot.sample_path = sample.path
  slot.sample_name = sample.name or basename(sample.path)
  if slot.sample_candidate_idx then
    seq_remember_sample_candidate(slot, sample)
  end
  if path_changed and seq_layering_follow_track_sample then
    seq_layering_follow_track_sample(slot, old_path, sample)
  end
  local should_persist = persist == nil or persist
  if path_changed and update_seq_track_sample_assignments then
    local force_rebuild = seq_layering_geometry_active
      and seq_layering_geometry_active(slot)
    if not force_rebuild and slot.layers and slot.layers.output then
      force_rebuild = true
    end
    -- update_seq_track_sample_assignments persists when asked, so skip a second save_config.
    update_seq_track_sample_assignments(slot, sample.path, slot.sample_name, should_persist, {
      force_rebuild = force_rebuild,
    })
    if seq_player_sync_slot then
      seq_player_sync_slot(slot)
    end
    return true
  end
  if should_persist then
    save_config()
  end
  if seq_player_sync_slot then
    seq_player_sync_slot(slot)
  end
  return true
end

function seq_slot_in_swap_mode(slot)
  if not state.seq_swap_track_id or not slot then
    return false
  end
  return slot.id == state.seq_swap_track_id
end

function find_seq_track_by_id(track_id)
  if not track_id then
    return nil, nil
  end
  for idx, slot in ipairs(state.seq_tracks) do
    if slot.id == track_id then
      return slot, idx
    end
  end
  return nil, nil
end

function seq_region_sample_edit_region()
  local id = state.seq_random_edit_region_id
  if not id then
    return nil
  end
  return get_seq_region_by_id(id)
end

function seq_sample_assign_region()
  if state.seq_swap_track_id and state.seq_swap_region_id then
    return get_seq_region_by_id(state.seq_swap_region_id)
  end
  return seq_region_sample_edit_region()
end

function seq_region_own_track_sample(region, track_id)
  if not region or track_id == nil then
    return nil
  end
  local map = region.track_samples
  if type(map) ~= "table" then
    return nil
  end
  local rec = map[tostring(track_id)]
  if type(rec) ~= "table" or type(rec.path) ~= "string" or rec.path == "" then
    return nil
  end
  return rec
end

function seq_linked_regions(region)
  local out = {}
  if not region then
    return out
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id == region.id
        or (seq_region_in_link_group and seq_region_in_link_group(reg, region)) then
      out[#out + 1] = reg
    end
  end
  if #out == 0 then
    out[1] = region
  end
  return out
end

function seq_get_region_track_sample(region, track_id)
  local rec = seq_region_own_track_sample(region, track_id)
  if rec then
    return rec
  end
  if not region then
    return nil
  end
  -- Only a linked region has link-group members; skip the O(R^2) scan below
  -- for the usual unlinked region.
  if seq_region_is_linked and not seq_region_is_linked(region) then
    return nil
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= region.id
        and seq_region_in_link_group
        and seq_region_in_link_group(reg, region) then
      rec = seq_region_own_track_sample(reg, track_id)
      if rec then
        return rec
      end
    end
  end
  return nil
end

function seq_clone_region_track_samples(src)
  if not src or type(src.track_samples) ~= "table" then
    return nil
  end
  return clone_table_deep(src.track_samples)
end

function seq_effective_slot_sample_path(slot, region)
  local rec = seq_get_region_track_sample(region, slot and slot.id)
  if rec then
    return rec.path, rec.name
  end
  if slot then
    return slot.sample_path, slot.sample_name
  end
  return nil, nil
end

function seq_effective_slot_sample(slot, region)
  local path, name = seq_effective_slot_sample_path(slot, region)
  if not path or path == "" then
    return nil
  end
  return find_sample_by_path(path) or { path = path, name = name or basename(path) }
end

function seq_slot_has_region_sample(slot, region)
  return seq_get_region_track_sample(region, slot and slot.id) ~= nil
end

function seq_slot_region_sample_cue(slot)
  local focus = seq_region_sample_edit_region() or get_seq_region_by_id(state.selected_seq_region_id)
  if seq_get_region_track_sample(focus, slot and slot.id) then
    return focus, true
  end
  return focus, false
end

function seq_set_region_own_track_sample(region, slot, rec)
  if not region or not slot then
    return
  end
  local key = tostring(slot.id)
  if not rec or not rec.path or rec.path == "" then
    if type(region.track_samples) == "table" then
      region.track_samples[key] = nil
      if next(region.track_samples) == nil then
        region.track_samples = nil
      end
    end
    return
  end
  region.track_samples = region.track_samples or {}
  region.track_samples[key] = {
    path = rec.path,
    name = rec.name or basename(rec.path),
  }
end

function seq_assign_region_track_sample(region, slot, sample, persist)
  if not region or not slot then
    return false
  end
  local rec = nil
  if sample and sample.path and sample.path ~= ""
      and not (slot.sample_path and seq_paths_same and seq_paths_same(sample.path, slot.sample_path)) then
    rec = {
      path = sample.path,
      name = sample.name or basename(sample.path),
    }
  end
  local targets = seq_linked_regions(region)
  for i = 1, #targets do
    seq_set_region_own_track_sample(targets[i], slot, rec)
  end
  if seq_release_sliced_notes_for_sample_change then
    seq_release_sliced_notes_for_sample_change(slot, targets, sample)
  end
  if clear_seq_vary_rank_cache then
    clear_seq_vary_rank_cache()
  end
  if sync_seq_region_track then
    seq_pcm_take_src_begin()
    if r.PreventUIRefresh then
      r.PreventUIRefresh(1)
    end
    for i = 1, #targets do
      sync_seq_region_track(targets[i], slot, { skip_arrange = true })
    end
    if r.PreventUIRefresh then
      r.PreventUIRefresh(-1)
    end
    seq_pcm_take_src_end()
    r.UpdateArrange()
  end
  if persist ~= false then
    save_config()
  end
  return true
end

function seq_assign_sample_for_context(slot, sample, persist)
  local region = seq_sample_assign_region()
  if region then
    return seq_assign_region_track_sample(region, slot, sample, persist)
  end
  return assign_sample_to_seq_track(slot, sample, persist)
end

function seq_swap_restore_slot(slot)
  if not slot then
    return
  end
  local region = state.seq_swap_region_id and get_seq_region_by_id(state.seq_swap_region_id) or nil
  if region then
    if state.seq_swap_backup_was_override and state.seq_swap_backup_path then
      seq_assign_region_track_sample(region, slot, {
        path = state.seq_swap_backup_path,
        name = state.seq_swap_backup_name or basename(state.seq_swap_backup_path),
      }, true)
    else
      seq_assign_region_track_sample(region, slot, nil, true)
    end
    return
  end
  if state.seq_swap_backup_path then
    assign_sample_to_seq_track(slot, {
      path = state.seq_swap_backup_path,
      name = state.seq_swap_backup_name or basename(state.seq_swap_backup_path),
    }, true)
  else
    slot.sample_path = nil
    slot.sample_name = nil
    save_config()
  end
end

function clone_active_tags(tags)
  local copy = {}
  if type(tags) ~= "table" then
    return copy
  end
  for tag, active in pairs(tags) do
    if active then
      copy[tag] = true
    end
  end
  return copy
end

function clone_string_list(list)
  local copy = {}
  if type(list) ~= "table" then
    return copy
  end
  for _, value in ipairs(list) do
    if type(value) == "string" and value ~= "" then
      copy[#copy + 1] = value
    end
  end
  return copy
end

MAP_TAB_MAX = 12

function sample_map_is_open()
  return state.sample_map_floating or state.active_view == "sample_map"
end

function sequencer_is_open()
  return state.sequencer_floating or state.active_view == "sequencer"
end

function map_view_center_from_pan(w, h, zoom, pan_x, pan_y)
  zoom = tonumber(zoom) or 1.0
  if zoom < 1e-6 then
    zoom = 1.0
  end
  local cx, cy = 0.5, 0.5
  if type(w) == "number" and w > 1 then
    cx = 0.5 - (tonumber(pan_x) or 0.0) / (w * zoom)
  end
  if type(h) == "number" and h > 1 then
    cy = 0.5 - (tonumber(pan_y) or 0.0) / (h * zoom)
  end
  return cx, cy
end

function map_pan_from_view_center(w, h, zoom, cx, cy)
  zoom = tonumber(zoom) or 1.0
  local pan_x, pan_y = 0.0, 0.0
  if type(w) == "number" and w > 1 and type(cx) == "number" then
    pan_x = (0.5 - cx) * w * zoom
  end
  if type(h) == "number" and h > 1 and type(cy) == "number" then
    pan_y = (0.5 - cy) * h * zoom
  end
  return pan_x, pan_y
end

function capture_map_tab_view()
  local parents = {}
  if type(state.selected_tag_parents) == "table" then
    for key, on in pairs(state.selected_tag_parents) do
      if on then
        parents[key] = true
      end
    end
  end
  local cx, cy = map_view_center_from_pan(
    state.map_view_w, state.map_view_h, state.zoom, state.pan_x, state.pan_y
  )
  return {
    filter = state.filter or "",
    active_tags = clone_active_tags(state.active_tags),
    folder_filter_paths = clone_string_list(state.folder_filter_paths),
    zoom = state.zoom or 1.0,
    pan_x = state.pan_x or 0.0,
    pan_y = state.pan_y or 0.0,
    view_cx = cx,
    view_cy = cy,
    map_y_axis = map_y_axis_id(),
    selected_tag_parents = parents,
  }
end

function apply_map_tab_view(tab)
  if type(tab) ~= "table" then
    return
  end
  state.filter = type(tab.filter) == "string" and tab.filter or ""
  state.active_tags = clone_active_tags(tab.active_tags)
  state.folder_filter_paths = clone_string_list(tab.folder_filter_paths)
  state.zoom = math.max(MAP_ZOOM_MIN, math.min(MAP_ZOOM_MAX, tonumber(tab.zoom) or 1.0))
  map_zoom_snap_target()
  local view_cx = tonumber(tab.view_cx)
  local view_cy = tonumber(tab.view_cy)
  if view_cx and view_cy then
    state.map_restore_view_cx = view_cx
    state.map_restore_view_cy = view_cy
    if (state.map_view_w or 0) > 1 and (state.map_view_h or 0) > 1 then
      state.pan_x, state.pan_y = map_pan_from_view_center(
        state.map_view_w, state.map_view_h, state.zoom, view_cx, view_cy
      )
    else
      state.pan_x = tonumber(tab.pan_x) or 0.0
      state.pan_y = tonumber(tab.pan_y) or 0.0
    end
  else
    state.map_restore_view_cx = nil
    state.map_restore_view_cy = nil
    state.pan_x = tonumber(tab.pan_x) or 0.0
    state.pan_y = tonumber(tab.pan_y) or 0.0
  end
  state.selected_tag_parents = clone_active_tags(tab.selected_tag_parents)
  local axis = tab.map_y_axis
  if axis == "brightness" or axis == "dominant_freq" or axis == "weight" then
    if state.map_y_axis ~= axis then
      state.map_y_axis = axis
      if #state.samples > 0 then
        layout_samples()
      end
    end
  end
end

function map_tab_label(tab)
  if type(tab) ~= "table" then
    return "All"
  end
  if type(tab.title) == "string" and tab.title ~= "" then
    return tab.title
  end
  local parts = {}
  if type(tab.filter) == "string" and tab.filter ~= "" then
    parts[#parts + 1] = tab.filter
  end
  local tags = {}
  for tag, on in pairs(tab.active_tags or {}) do
    if on and type(tag) == "string" then
      tags[#tags + 1] = tag
    end
  end
  table.sort(tags, function(a, b)
    return string.lower(a) < string.lower(b)
  end)
  for _, tag in ipairs(tags) do
    parts[#parts + 1] = tag
  end
  for _, path in ipairs(tab.folder_filter_paths or {}) do
    if folder_filter_chip_label then
      parts[#parts + 1] = folder_filter_chip_label(path)
    else
      parts[#parts + 1] = path:match("([^/]+)$") or path
    end
  end
  if #parts == 0 then
    return "All"
  end
  local label = table.concat(parts, " · ")
  if #label > 22 then
    return label:sub(1, 20) .. "…"
  end
  return label
end

function find_map_tab(id)
  id = tonumber(id)
  if not id then
    return nil, nil
  end
  for i, tab in ipairs(state.map_tabs or {}) do
    if tab.id == id then
      return tab, i
    end
  end
  return nil, nil
end

function snapshot_active_map_tab()
  local tab = find_map_tab(state.map_tab_active_id)
  if not tab then
    return
  end
  local view = capture_map_tab_view()
  if state.seq_swap_saved_active_tags ~= nil then
    view.active_tags = clone_active_tags(state.seq_swap_saved_active_tags)
  end
  tab.filter = view.filter
  tab.active_tags = view.active_tags
  tab.folder_filter_paths = view.folder_filter_paths
  tab.zoom = view.zoom
  tab.pan_x = view.pan_x
  tab.pan_y = view.pan_y
  tab.view_cx = view.view_cx
  tab.view_cy = view.view_cy
  tab.map_y_axis = view.map_y_axis
  tab.selected_tag_parents = view.selected_tag_parents
end

function ensure_map_tabs()
  state.map_tabs = state.map_tabs or {}
  if #state.map_tabs == 0 then
    local tab = capture_map_tab_view()
    tab.id = 1
    state.map_tabs[1] = tab
    state.map_tab_active_id = 1
    state.map_tab_next_id = 2
    return
  end
  if not find_map_tab(state.map_tab_active_id) then
    state.map_tab_active_id = state.map_tabs[1].id
  end
  local max_id = 0
  for _, tab in ipairs(state.map_tabs) do
    if type(tab.id) == "number" and tab.id > max_id then
      max_id = tab.id
    end
  end
  state.map_tab_next_id = math.max(state.map_tab_next_id or 1, max_id + 1)
end

function switch_map_tab(id)
  if id == state.map_tab_active_id then
    return
  end
  local tab = find_map_tab(id)
  if not tab then
    return
  end
  snapshot_active_map_tab()
  state.map_tab_active_id = id
  apply_map_tab_view(tab)
  save_config()
end

function add_map_tab()
  ensure_map_tabs()
  if #(state.map_tabs or {}) >= MAP_TAB_MAX then
    return
  end
  snapshot_active_map_tab()
  local tab = {
    id = state.map_tab_next_id or 1,
    filter = "",
    active_tags = {},
    folder_filter_paths = {},
    zoom = 1.0,
    pan_x = 0.0,
    pan_y = 0.0,
    view_cx = 0.5,
    view_cy = 0.5,
    map_y_axis = map_y_axis_id(),
    selected_tag_parents = {},
  }
  state.map_tab_next_id = tab.id + 1
  state.map_tabs[#state.map_tabs + 1] = tab
  state.map_tab_active_id = tab.id
  apply_map_tab_view(tab)
  save_config()
end

function close_map_tab(id)
  ensure_map_tabs()
  if #(state.map_tabs or {}) <= 1 then
    return
  end
  local tab, idx = find_map_tab(id)
  if not tab then
    return
  end
  if id == state.map_tab_active_id then
    snapshot_active_map_tab()
  end
  table.remove(state.map_tabs, idx)
  if id == state.map_tab_active_id then
    local next_tab = state.map_tabs[math.min(idx, #state.map_tabs)]
    state.map_tab_active_id = next_tab.id
    apply_map_tab_view(next_tab)
  end
  save_config()
end

function map_tab_display_label(tab)
  if not tab then
    return "All"
  end
  if tab.id == state.map_tab_active_id then
    local live = capture_map_tab_view()
    live.title = tab.title
    if state.seq_swap_saved_active_tags ~= nil then
      live.active_tags = clone_active_tags(state.seq_swap_saved_active_tags)
    end
    return map_tab_label(live)
  end
  return map_tab_label(tab)
end

function pop_out_view(view)
  if view == "sample_map" then
    if state.sample_map_floating then
      return
    end
    snapshot_active_map_tab()
    state.sample_map_floating = true
    if state.active_view == "sample_map" and not state.sequencer_floating then
      state.active_view = "sequencer"
    end
  elseif view == "sequencer" then
    if state.sequencer_floating then
      return
    end
    state.sequencer_floating = true
    if state.active_view == "sequencer" and not state.sample_map_floating then
      state.active_view = "sample_map"
    end
  else
    return
  end
  save_config()
end

function pop_out_active_view()
  pop_out_view(state.active_view)
end

function dock_floating_view(view)
  if view == "sample_map" then
    if not state.sample_map_floating then
      return
    end
    state.sample_map_floating = false
    state.active_view = "sample_map"
  elseif view == "sequencer" then
    if not state.sequencer_floating then
      return
    end
    state.sequencer_floating = false
    state.active_view = "sequencer"
  else
    return
  end
  save_config()
end

function find_library_tag(tag)
  local needle = seq_trim_text(tag)
  if needle == "" or not state.tag_list then
    return nil
  end
  needle = needle:lower()
  for _, entry in ipairs(state.tag_list) do
    local lib_tag = tostring(entry.tag or "")
    if lib_tag:lower() == needle then
      return lib_tag
    end
  end
  return nil
end

function resolve_seq_swap_filter_tag(slot)
  if not slot then
    return nil
  end
  local tag = slot.sample_tag and seq_trim_text(slot.sample_tag) or ""
  if tag ~= "" then
    return tag
  end
  local role = infer_seq_track_role(slot)
  if role and role ~= "other" and SEQ_ROLE_TAG_CANDIDATES[role] then
    return SEQ_ROLE_TAG_CANDIDATES[role][1]
  end
  return nil
end

function restore_seq_swap_map_filter()
  if state.seq_swap_saved_active_tags ~= nil then
    state.active_tags = clone_active_tags(state.seq_swap_saved_active_tags)
    state.seq_swap_saved_active_tags = nil
  end
end

function apply_seq_swap_map_filter(slot)
  local tag = find_library_tag(resolve_seq_swap_filter_tag(slot))
  if not tag then
    restore_seq_swap_map_filter()
    return
  end
  if state.seq_swap_saved_active_tags == nil then
    state.seq_swap_saved_active_tags = clone_active_tags(state.active_tags)
  end
  state.active_tags = { [tag] = true }
end

function clear_seq_swap_mode_state()
  restore_seq_swap_map_filter()
  local return_view = state.seq_swap_return_view
  state.seq_swap_track_idx = nil
  state.seq_swap_track_id = nil
  state.seq_swap_backup_path = nil
  state.seq_swap_backup_name = nil
  state.seq_swap_region_id = nil
  state.seq_swap_backup_was_override = false
  state.seq_swap_return_view = nil
  if return_view == "sequencer" and not sequencer_is_open() then
    state.active_view = "sequencer"
    save_config()
  end
end

function seq_clear_swap_mode_if_track(track_id)
  if state.seq_swap_track_id and track_id and state.seq_swap_track_id == track_id then
    clear_seq_swap_mode_state()
  end
end

function begin_seq_swap_mode(idx)
  local slot = state.seq_tracks[idx]
  if not slot then
    return
  end
  if state.seq_swap_track_id == slot.id then
    state.seq_swap_track_idx = idx
    return
  end
  if state.seq_swap_track_id and state.seq_swap_track_id ~= slot.id then
    local prev_slot = find_seq_track_by_id(state.seq_swap_track_id)
    if prev_slot then
      seq_swap_restore_slot(prev_slot)
    end
    state.seq_swap_track_idx = nil
    state.seq_swap_track_id = nil
    state.seq_swap_backup_path = nil
    state.seq_swap_backup_name = nil
    state.seq_swap_region_id = nil
    state.seq_swap_backup_was_override = false
    if seq_undo_is_open() then
      end_seq_undo("Swap sequencer sample")
    end
  end
  begin_seq_undo("Swap sequencer sample")
  state.seq_swap_track_idx = idx
  state.seq_swap_track_id = slot.id
  state.selected_seq_track = idx
  local region = seq_region_sample_edit_region()
  local rec = region and seq_get_region_track_sample(region, slot.id)
  state.seq_swap_region_id = region and region.id or nil
  state.seq_swap_backup_was_override = rec ~= nil
  if rec then
    state.seq_swap_backup_path = rec.path
    state.seq_swap_backup_name = rec.name
  else
    state.seq_swap_backup_path = slot.sample_path
    state.seq_swap_backup_name = slot.sample_name
  end
  if not state.seq_swap_return_view then
    state.seq_swap_return_view = state.active_view
  end
  apply_seq_swap_map_filter(slot)
  if not state.sample_map_floating then
    state.active_view = "sample_map"
  end
  save_config()
end

function end_seq_swap_mode(confirmed)
  local slot, idx = find_seq_track_by_id(state.seq_swap_track_id)
  if not slot then
    clear_seq_swap_mode_state()
    return
  end
  state.seq_swap_track_idx = idx
  if confirmed then
    -- Arrange items were already retargeted while browsing candidates.
    save_config()
  else
    seq_swap_restore_slot(slot)
    local region = state.seq_swap_region_id and get_seq_region_by_id(state.seq_swap_region_id) or nil
    local restored = seq_effective_slot_sample(slot, region)
    if restored then
      preview_sample(restored)
    end
  end
  if seq_undo_is_open() then
    end_seq_undo("Swap sequencer sample")
  end
  clear_seq_swap_mode_state()
end

function get_active_swap_slot()
  local slot, idx = find_seq_track_by_id(state.seq_swap_track_id)
  if not slot then
    return nil, nil
  end
  state.seq_swap_track_idx = idx
  return slot, idx
end

function complete_pending_sample_drop()
  local sample = get_active_dragged_sample()
  local mouse_down = r.ImGui_IsMouseDown(ctx, 0)

  if mouse_down then
    if state.pending_waveform_drop then
      -- Escape during the drag cancels everything (no insert, no undo point).
      if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
          and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
        remove_provisional_drop()
        clear_drag_tooltip()
        state.pending_waveform_drop = nil
        state.waveform_drag_armed = nil
        state.last_mouse_time_pos = nil
        state.last_mouse_track = nil
        state.seq_drop_target_idx = nil
        state.seq_candidate_drop = nil
        state.seq_drum_drop = nil
        state.seq_timeline_drop_track_idx = nil
        state.seq_timeline_drop_time = nil
        state.is_left_dragging = false
        state.last_dragged_sample_path = nil
        state.map_press_x = nil
        state.map_press_y = nil
        state.map_press_pending = false
        state.map_audition_rearm = false
        if seq_clear_candidate_drag_state then
          seq_clear_candidate_drag_state()
        end
        log("Drag cancelled via Escape")
        return
      end
      update_provisional_drop(sample)
    end
    return
  end

  if state.seq_candidate_press then
    local press = state.seq_candidate_press
    state.seq_candidate_press = nil
    if not state.pending_waveform_drop then
      local pslot = seq_find_slot_by_id and seq_find_slot_by_id(press.slot_id)
      if pslot and seq_apply_sample_candidate then
        seq_apply_sample_candidate(pslot, press.idx)
      end
    end
  end

  if not sample and not state.pending_waveform_drop and not state.is_left_dragging then
    return
  end

  if sample then
    log("Mouse released globally, completing drag operation")

    if seq_layering_resolve_drop_vert then
      seq_layering_resolve_drop_vert()
    end
    if state.seq_layering_drop_vert and state.seq_layering_slot_id then
      local layer_slot = find_seq_track_by_id(state.seq_layering_slot_id)
      if layer_slot then
        local vert_sample = sample
        if sample.is_layering_mix then
          vert_sample = find_sample_by_path(sample.path) or sample
        end
        seq_layering_set_vert(layer_slot, state.seq_layering_drop_vert.side, state.seq_layering_drop_vert.idx, vert_sample)
        preview_sample(vert_sample)
        save_config()
        if save_seq_project_state then save_seq_project_state() end
        seq_layering_sync_arrange(layer_slot)
      end
      state.seq_layering_drop_vert = nil
      state.pending_waveform_drop = nil
      state.waveform_drag_armed = nil
      state.seq_drop_target_idx = nil
      state.seq_candidate_drop = nil
      state.seq_drum_drop = nil
      state.seq_timeline_drop_track_idx = nil
      state.seq_timeline_drop_time = nil
      state.is_left_dragging = false
      state.last_dragged_sample_path = nil
      state.map_press_x = nil
      state.map_press_y = nil
      state.map_press_pending = false
      state.map_audition_rearm = false
      if seq_clear_candidate_drag_state then
        seq_clear_candidate_drag_state()
      end
      remove_provisional_drop()
      clear_drag_tooltip()
      return
    end

    if seq_layering_pointer_over_window and seq_layering_pointer_over_window() then
      state.seq_layering_drop_vert = nil
      state.pending_waveform_drop = nil
      state.waveform_drag_armed = nil
      state.seq_drop_target_idx = nil
      state.seq_candidate_drop = nil
      state.seq_drum_drop = nil
      state.seq_timeline_drop_track_idx = nil
      state.seq_timeline_drop_time = nil
      state.is_left_dragging = false
      state.last_dragged_sample_path = nil
      state.map_press_x = nil
      state.map_press_y = nil
      state.map_press_pending = false
      state.map_audition_rearm = false
      if seq_clear_candidate_drag_state then
        seq_clear_candidate_drag_state()
      end
      remove_provisional_drop()
      clear_drag_tooltip()
      return
    end

    if state.seq_drum_drop then
      remove_provisional_drop()
      local drop = state.seq_drum_drop
      local slot = seq_find_slot_by_id and seq_find_slot_by_id(drop.slot_id)
      if not slot and find_seq_track_by_id then
        slot = select(1, find_seq_track_by_id(drop.slot_id))
      end
      local region = seq_region_sample_edit_region and seq_region_sample_edit_region()
      if slot and sample.path and region and not sample.is_layering_mix
          and not seq_candidate_drag_from_slot(slot) then
        local own = seq_undo_own_begin("Set region sample")
        seq_assign_region_track_sample(region, slot, sample, true)
        for ti, s in ipairs(state.seq_tracks or {}) do
          if s.id == slot.id then
            state.selected_seq_track = ti
            break
          end
        end
        preview_sample(sample)
        preview_seq_track_sample(slot)
        log("Set '" .. (sample.name or sample.path) .. "' as region sample on " .. (slot.name or "track"))
        if own then
          end_seq_undo("Set region sample")
        end
      end
    elseif state.seq_candidate_drop then
      remove_provisional_drop()
      local drop = state.seq_candidate_drop
      local src = state.seq_candidate_drag_source
      local slot = seq_find_slot_by_id and seq_find_slot_by_id(drop.slot_id)
      if not slot then
        slot = seq_find_track_slot_by_id and seq_find_track_slot_by_id(drop.slot_id)
      end
      if src and src.slot_id == drop.slot_id and src.idx == drop.idx then
        log("Candidate drag released on source")
      elseif slot and sample.path and seq_drop_sample_on_candidate then
        local in_swap = state.seq_swap_track_id and slot.id == state.seq_swap_track_id
        local own = (not in_swap) and seq_undo_own_begin("Assign sample candidate")
        seq_drop_sample_on_candidate(slot, drop.idx, sample, not in_swap)
        if own then
          end_seq_undo("Assign sample candidate")
        end
        for ti, s in ipairs(state.seq_tracks or {}) do
          if s.id == slot.id then
            state.selected_seq_track = ti
            break
          end
        end
        if sample.is_layering_mix and seq_layering_preview_layered then
          seq_layering_preview_layered(slot, 0)
        else
          preview_sample(sample)
        end
        log("Dropped '" .. (sample.name or sample.path) .. "' onto candidate " .. tostring(drop.idx) .. " of " .. (slot.name or "track"))
      end
    elseif state.seq_drop_target_idx and not seq_drag_is_from_candidate() then
      remove_provisional_drop()
      local slot = state.seq_tracks[state.seq_drop_target_idx]
      if slot and sample.path then
        local in_swap = state.seq_swap_track_id and slot.id == state.seq_swap_track_id
        local own = (not in_swap) and seq_undo_own_begin("Assign sequencer sample")
        if apply_dragged_sample_to_seq_track then
          apply_dragged_sample_to_seq_track(slot, sample, not in_swap)
        else
          seq_assign_sample_for_context(slot, sample, not in_swap)
        end
        if own then
          end_seq_undo("Assign sequencer sample")
        end
        state.selected_seq_track = state.seq_drop_target_idx
        if sample.is_layering_mix and seq_layering_preview_layered then
          seq_layering_preview_layered(slot, 0)
        else
          preview_sample(sample)
        end
        log("Swapped '" .. (sample.name or sample.path) .. "' onto " .. slot.name)
      end
    elseif state.pending_waveform_drop then
      local sample_label = sample.name or basename(sample.path or "") or "sample"
      if state.seq_timeline_drop_track_idx and state.seq_timeline_drop_time then
        remove_provisional_drop()
        local slot = state.seq_tracks[state.seq_timeline_drop_track_idx]
        local target_track = nil
        if slot and slot.reaper_track_guid then
          local n = r.CountTracks(0)
          for i = 0, n - 1 do
            local tr = r.GetTrack(0, i)
            if r.GetTrackGUID(tr) == slot.reaper_track_guid then
              target_track = tr
              break
            end
          end
        end
        arrange_undo_begin()
        local success = insert_sample_at_position(sample, state.seq_timeline_drop_time, target_track)
        arrange_undo_end("Insert sample: " .. sample_label)
        if success then
          state.selected_seq_track = state.seq_timeline_drop_track_idx
          log("Inserted '" .. sample_label .. "' via sequencer timeline")
        else
          log("Failed sequencer timeline insertion")
        end
      else
        -- Arrange drop: commit the provisional preview position as one undo point.
        local commit_time, commit_track
        local p = state.provisional_drop
        if p and p.item and r.ValidatePtr(p.item, "MediaItem*") then
          commit_time = p.time or state.last_mouse_time_pos
          if p.track and r.ValidatePtr(p.track, "MediaTrack*") then
            commit_track = p.track
          end
        end
        if not commit_time then
          local dt, dtr = get_drop_position()
          if dt then
            commit_time = maybe_snap_drop_time(dt)
            commit_track = commit_track or dtr
          end
        end
        if not commit_time and state.last_mouse_time_pos then
          commit_time = state.last_mouse_time_pos
          commit_track = commit_track or state.last_mouse_track
        end

        -- Clear the preview before committing so the undo block captures exactly
        -- one media item creation (project returns to clean state first).
        remove_provisional_drop()

        if commit_time then
          arrange_undo_begin()
          local success = insert_sample_at_position(sample, commit_time, commit_track)
          arrange_undo_end("Insert sample: " .. sample_label)
          if success then
            log(string.format("Committed arrange insert at %.3f", commit_time))
          else
            log("Failed to commit arrange insert")
          end
        else
          log("Drag released away from the arrange; insert cancelled")
        end
      end
    end
  end

  remove_provisional_drop()
  clear_drag_tooltip()
  state.pending_waveform_drop = nil
  state.waveform_drag_armed = nil
  state.last_mouse_time_pos = nil
  state.last_mouse_track = nil
  state.seq_drop_target_idx = nil
  state.seq_candidate_drop = nil
  state.seq_drum_drop = nil
  state.seq_timeline_drop_track_idx = nil
  state.seq_timeline_drop_time = nil
  state.is_left_dragging = false
  state.last_dragged_sample_path = nil
  state.map_press_x = nil
  state.map_press_y = nil
  state.map_press_pending = false
  state.map_audition_rearm = false
  if seq_clear_candidate_drag_state then
    seq_clear_candidate_drag_state()
  end
end

function clear_seq_track_sample(slot)
  if not slot then
    return
  end
  slot.sample_path = nil
  slot.sample_name = nil
  save_config()
end

function add_seq_tracks_from_selection()
  local own = seq_undo_own_begin("Add sequencer track")
  local count = r.CountSelectedTracks(0)
  if count == 0 then
    add_empty_seq_track()
    save_config()
    if own then
      end_seq_undo("Add sequencer track")
    end
    return
  end
  local added = 0
  for i = 0, count - 1 do
    local tr = r.GetSelectedTrack(0, i)
    if add_seq_track_from_reaper_track(tr) then
      added = added + 1
    end
  end
  if added == 0 then
    log("Selected project tracks are already in the sequencer track list")
  else
    save_config()
  end
  if own then
    end_seq_undo("Add sequencer track")
  end
end

function seq_trim_text(value)
  local text = tostring(value or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

function find_sample_for_tag(tag_name)
  local needle = seq_trim_text(tag_name):lower()
  if needle == "" then
    return nil
  end
  local by_tag = state.samples_by_tag
  if type(by_tag) == "table" and next(by_tag) ~= nil then
    local lib_tag = find_library_tag and find_library_tag(needle)
    local list = (lib_tag and by_tag[lib_tag]) or by_tag[needle] or by_tag[tag_name]
    if type(list) == "table" then
      for i = 1, #list do
        local sample = list[i]
        if not sample_scan_folder_unavailable(sample) then
          return sample
        end
      end
    end
    return nil
  end
  for _, sample in ipairs(state.samples) do
    if sample_has_tag(sample, needle) and not sample_scan_folder_unavailable(sample) then
      return sample
    end
  end
  return nil
end

function sample_has_tag(sample, tag_name)
  if not sample or not sample.tags or type(sample.tags) ~= "table" then
    return false
  end
  local needle = seq_trim_text(tag_name):lower()
  if needle == "" then
    return false
  end
  for _, sample_tag in ipairs(sample.tags) do
    if tostring(sample_tag):lower() == needle then
      return true
    end
  end
  return false
end

function seq_get_media_track_index(tr)
  if not tr then
    return nil
  end
  local num = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  if num and num > 0 then
    return math.floor(num + 0.5) - 1
  end
  return nil
end

function seq_slot_arrange_index(slot)
  if not slot or not slot.reaper_track_guid then
    return nil
  end
  return seq_get_media_track_index(get_track_by_guid(slot.reaper_track_guid))
end

function seq_remap_track_index_after_move(idx, from_idx, to_idx)
  if not idx then
    return idx
  end
  if idx == from_idx then
    return to_idx
  end
  if from_idx < to_idx then
    if idx > from_idx and idx <= to_idx then
      return idx - 1
    end
  elseif to_idx < from_idx then
    if idx >= to_idx and idx < from_idx then
      return idx + 1
    end
  end
  return idx
end

function seq_move_slot_index(from_idx, to_idx)
  local tracks = state.seq_tracks
  if not tracks then
    return false
  end
  local n = #tracks
  if from_idx == to_idx or from_idx < 1 or to_idx < 1 or from_idx > n or to_idx > n then
    return false
  end
  local slot = table.remove(tracks, from_idx)
  table.insert(tracks, to_idx, slot)
  state.selected_seq_track = seq_remap_track_index_after_move(state.selected_seq_track, from_idx, to_idx)
  state.seq_swap_track_idx = seq_remap_track_index_after_move(state.seq_swap_track_idx, from_idx, to_idx)
  return true
end

function seq_reaper_track_guid_set()
  local set = {}
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    local tr = r.GetTrack(0, i)
    if tr then
      set[r.GetTrackGUID(tr)] = true
    end
  end
  return set
end

-- Drop sequencer slots whose linked arrange tracks were deleted.
function seq_prune_missing_reaper_tracks()
  if seq_undo_applying or state.seq_track_reorder_drag then
    return false
  end
  if seq_undo_is_open and seq_undo_is_open() then
    return false
  end
  if seq_ingest_busy and seq_ingest_busy() then
    return false
  end
  local tracks = state.seq_tracks
  if not tracks or #tracks == 0 then
    return false
  end
  local live = seq_reaper_track_guid_set()
  local removed = false
  for i = #tracks, 1, -1 do
    local slot = tracks[i]
    local guid = slot and slot.reaper_track_guid
    if guid and guid ~= "" and not live[guid] then
      seq_remove_seq_track_slot(i)
      removed = true
    end
  end
  if not removed then
    return false
  end
  save_config()
  if save_seq_project_state then
    save_seq_project_state()
  end
  if find_seq_parent_folder_track then
    find_seq_parent_folder_track()
  end
  return true
end

function seq_sync_track_order_from_arrange(force)
  if state.seq_track_reorder_drag or seq_undo_applying then
    return false
  end
  local now = r.time_precise and r.time_precise() or 0
  if not force then
    if (now - (state.seq_order_sync_last_t or 0)) < 0.12 then
      return false
    end
  end
  state.seq_order_sync_last_t = now
  seq_prune_missing_reaper_tracks()
  if state.seq_skip_order_sync then
    state.seq_skip_order_sync = nil
    return false
  end
  local tracks = state.seq_tracks
  if not tracks or #tracks < 2 then
    return false
  end
  local linked = {}
  for i = 1, #tracks do
    local arr = seq_slot_arrange_index(tracks[i])
    if arr then
      linked[#linked + 1] = { pos = i, slot = tracks[i], arr = arr }
    end
  end
  if #linked < 2 then
    return false
  end
  local by_pos = {}
  for i = 1, #linked do
    by_pos[i] = linked[i]
  end
  table.sort(by_pos, function(a, b) return a.pos < b.pos end)
  table.sort(linked, function(a, b)
    if a.arr ~= b.arr then
      return a.arr < b.arr
    end
    return a.pos < b.pos
  end)
  local changed = false
  for i = 1, #linked do
    if by_pos[i].slot.id ~= linked[i].slot.id then
      changed = true
      break
    end
  end
  if not changed then
    return false
  end
  local selected_id = state.selected_seq_track and tracks[state.selected_seq_track] and tracks[state.selected_seq_track].id
  local swap_id = state.seq_swap_track_id
  for i = 1, #linked do
    tracks[by_pos[i].pos] = linked[i].slot
  end
  if selected_id then
    local _, idx = find_seq_track_by_id(selected_id)
    state.selected_seq_track = idx
  end
  if swap_id then
    local _, idx = find_seq_track_by_id(swap_id)
    state.seq_swap_track_idx = idx
  end
  save_config()
  return true
end

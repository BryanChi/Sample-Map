-- Sample Map Browser module: seq_ingest
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function sync_all_seq_regions()
  for _, region in ipairs(state.seq_regions) do
    sync_seq_region(region)
  end
end

function seq_mark_self_arrange_write()
  state.seq_skip_ingest = true
  if r.GetProjectStateChangeCount then
    local count = r.GetProjectStateChangeCount(0)
    state.seq_self_write_count = count
    state.seq_last_proj_change = count
  end
end

function seq_schedule_ingest_save()
  state.seq_ingest_save_due = (r.time_precise and r.time_precise() or os.clock()) + 0.4
end

function seq_flush_ingest_save()
  if not state.seq_ingest_save_due then
    return
  end
  local now = r.time_precise and r.time_precise() or os.clock()
  if now < state.seq_ingest_save_due then
    return
  end
  state.seq_ingest_save_due = nil
  if save_seq_project_state then
    save_seq_project_state()
  end
end

function seq_ingest_busy()
  return state.seq_note_drag ~= nil or state.seq_param_drag ~= nil or state.seq_region_drag ~= nil
    or state.seq_razor_drag ~= nil
    or state.seq_lane_h_drag ~= nil
    or state.seq_track_reorder_drag ~= nil
    or state.pending_waveform_drop ~= nil
    or seq_undo_is_open()
    or state.seq_random_knob_drag ~= nil
    or state.seq_random_sync_pending ~= nil
    or state.seq_stem_import ~= nil
end

function seq_item_take_params(item)
  local vol, pan, pitch = 1.0, 0.0, 0.0
  if not item then
    return vol, pan, pitch
  end
  local take = r.GetActiveTake(item)
  if take then
    vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1.0
    pan = r.GetMediaItemTakeInfo_Value(take, "D_PAN") or 0.0
    pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH") or 0.0
  else
    vol = r.GetMediaItemInfo_Value(item, "D_VOL") or 1.0
  end
  if vol < 0 then vol = 0 end
  if vol > 2 then vol = 2 end
  if pan < -1 then pan = -1 elseif pan > 1 then pan = 1 end
  if pitch < -24 then pitch = -24 elseif pitch > 24 then pitch = 24 end
  return vol, pan, pitch, take
end

function seq_item_length_qn(item)
  if not item then
    return nil
  end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  if not pos or not len or len <= 1e-9 then
    return nil
  end
  local q0 = time_to_qn(pos)
  local q1 = time_to_qn(pos + len)
  if q0 and q1 and q1 > q0 then
    return q1 - q0
  end
  return nil
end

function seq_ingest_item_end_qn(item)
  if not item then
    return nil
  end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  if not pos or not len or len <= 1e-9 then
    return nil
  end
  return time_to_qn(pos + len)
end

function seq_ingest_items_contiguous(items, slop)
  slop = slop or 0.02
  local metas = {}
  for i = 1, #(items or {}) do
    if not seq_item_is_aux_piece(items[i]) then
      local q0 = seq_ingest_item_qn(items[i])
      local q1 = seq_ingest_item_end_qn(items[i])
      if q0 and q1 then
        metas[#metas + 1] = { q0 = q0, q1 = q1 }
      end
    end
  end
  if #metas < 2 then
    return false
  end
  table.sort(metas, function(a, b) return a.q0 < b.q0 end)
  for i = 2, #metas do
    if math.abs(metas[i].q0 - metas[i - 1].q1) > slop then
      return false
    end
  end
  return true
end

-- Earliest start to latest end across a stitched cluster (layers / ghosts).
function seq_ingest_cluster_span_qn(rec)
  local items = rec and rec.items
  if type(items) ~= "table" or #items == 0 then
    items = rec and rec.item and { rec.item } or nil
  end
  if not items then
    return nil
  end
  local t0, t1 = nil, nil
  for i = 1, #items do
    local item = items[i]
    if item then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if pos and len and len > 1e-9 then
        local q0 = time_to_qn(pos)
        local q1 = time_to_qn(pos + len)
        if q0 and (not t0 or q0 < t0) then
          t0 = q0
        end
        if q1 and (not t1 or q1 > t1) then
          t1 = q1
        end
      end
    end
  end
  if t0 and t1 and t1 > t0 then
    return t1 - t0
  end
  return nil
end

function seq_ingest_length_qn_from_rec(rec, item)
  local items = rec and rec.items
  if type(items) == "table" then
    local slop = math.max(0.02, (state.seq_grid_qn or 0.25) * 0.08)
    if seq_ingest_items_contiguous(items, slop) then
      return seq_ingest_cluster_span_qn(rec)
    end
    local best = nil
    for i = 1, #items do
      if not seq_item_is_aux_piece(items[i]) then
        local qn = seq_item_length_qn(items[i])
        if qn and (not best or qn > best) then
          best = qn
        end
      end
    end
    if best then
      return best
    end
    return seq_ingest_cluster_span_qn(rec)
  end
  if item and not seq_item_is_aux_piece(item) then
    return seq_item_length_qn(item)
  end
  return nil
end

-- How far past the trigger a same-step stitch (layer/ghost/sustain) may start
-- and still belong to this note. Off-grid heads plus a replaced transient can
-- put the sustain item a long way after the stored qn_offset.
function seq_ingest_note_cover_end_qn(region, track_id, step_key, note, grid_qn)
  local home = seq_note_trigger_qn(region, step_key, note, grid_qn)
  grid_qn = grid_qn or 0.25
  local cover = grid_qn
  local span = seq_stutter_span_qn(note, grid_qn)
  if span and span > cover then
    cover = span
  end
  local decay = tonumber(note and note.decay_qn)
  if type(decay) == "number" and decay > cover then
    cover = decay
  end
  local len = tonumber(note and note.length_qn)
  if type(len) == "number" and len > cover then
    cover = len
  end
  -- One beat covers long drum transients at typical tempos.
  if cover < 1.0 then
    cover = 1.0
  end
  return home + cover
end

-- Trimmed arrange items keep the full source file; D_LENGTH is the audible
-- length. Store that as decay_qn so the sequencer draws and rebuilds it.
-- Layer slices are not the note length — use the primary item or the full
-- stitch span so a short transient does not collapse the hit.
function seq_ingest_apply_item_length(note, item, region, pattern, slot, step_key, grid_qn, rec)
  if not note or seq_stutter_count(note) > 1 then
    return false
  end
  local item_qn = seq_ingest_length_qn_from_rec(rec, item)
  if not item_qn or item_qn <= 1e-9 then
    return false
  end
  local saved = note.decay_qn
  note.decay_qn = nil
  local _, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot and slot.id, step_key)
  local auto_qn = seq_effective_note_length_qn(
    region, pattern, slot, slot and slot.id, step_key, note, resolved_sample, grid_qn
  ) or 0.0
  note.decay_qn = saved
  local slop = math.max(0.015, (grid_qn or 0.25) * 0.06)
  if math.abs(item_qn - auto_qn) <= slop then
    if saved ~= nil then
      note.decay_qn = nil
      return true
    end
    return false
  end
  if math.abs((tonumber(saved) or 0.0) - item_qn) > slop then
    note.decay_qn = item_qn
    return true
  end
  return false
end

function seq_note_from_arrange_item(slot, step_key, step_qn, src_note, vol, pan, pitch, qn_offset)
  local note
  if src_note and type(src_note) == "table" then
    note = clone_table_deep(src_note)
  else
    local fallback_qn = qn_offset
    if type(fallback_qn) ~= "number" then
      fallback_qn = 0.0
    end
    note = make_default_seq_note(slot, step_key, fallback_qn)
  end
  if not note then
    note = {
      enabled = true,
      sample_path = slot and slot.sample_path,
      sample_name = slot and slot.sample_name,
      sample_vary = 0.0,
      stutter = 1,
    }
  end
  note.enabled = true
  if type(qn_offset) == "number" then
    note.qn_offset = qn_offset
    note.step = math.floor((qn_offset / (step_qn or 0.25)) + 1e-9)
  elseif type(note.qn_offset) ~= "number" then
    note.step = tonumber(step_key) or 0
    note.qn_offset = note.step * (step_qn or 0.25)
  end
  note.volume = vol
  note.pan = pan
  note.pitch = pitch
  return note
end

function seq_note_capture_source_offset(note, item)
  if type(note) ~= "table" or not item then
    return
  end
  local take = r.GetActiveTake(item)
  if not take then
    return
  end
  local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  if type(offs) == "number" and offs > 0.0000005 then
    note.source_offset = offs
  end
end

function seq_ingest_timing_slop_qn(region, track_id, grid_qn)
  local slop = math.max(0.02, (grid_qn or 0.25) * 0.04)
  local settings = get_seq_track_settings(get_seq_pattern(region and region.pattern_id, false), track_id, false)
  local t_lo, t_hi = seq_humanize_effective_time_ms(settings, settings and settings.humanize_ms)
  local max_ms = math.max(math.abs(t_lo), math.abs(t_hi))
  if max_ms > 0.05 then
    local sec_per = seq_sec_per_qn
    if not sec_per or sec_per <= 0 then
      local t0 = qn_to_time(0)
      local t1 = qn_to_time(1)
      if t0 and t1 and t1 > t0 then
        sec_per = t1 - t0
      end
    end
    if sec_per and sec_per > 0 then
      slop = math.max(slop, (max_ms / 1000.0) / sec_per * 1.25)
    end
  end
  return slop
end

-- Arrange item QN after groove + timing humanize, matching insert_seq_note_hit.
function seq_note_expected_item_qn(region, track_id, step_key, note, grid_qn)
  local qn = seq_note_trigger_qn(region, step_key, note, grid_qn)
  local settings = get_seq_track_settings(get_seq_pattern(region and region.pattern_id, false), track_id, false)
  local ms = settings and tonumber(settings.humanize_ms) or 0.0
  local t_lo, t_hi = seq_humanize_effective_time_ms(settings, ms)
  if math.abs(t_lo) < 0.05 and math.abs(t_hi) < 0.05 then
    return qn
  end
  local t = qn_to_time(qn)
  if not t then
    return qn
  end
  local dt = seq_humanize_time_offset_sec(
    region, track_id, step_key, ms, settings.humanize_seed or settings.seed
  )
  local q2 = time_to_qn(math.max(0.0, t + dt))
  return q2 or qn
end

function seq_ingest_humanize_delta_qn(region, track_id, step_key, base_qn)
  local settings = get_seq_track_settings(get_seq_pattern(region and region.pattern_id, false), track_id, false)
  local ms = settings and tonumber(settings.humanize_ms) or 0.0
  local t_lo, t_hi = seq_humanize_effective_time_ms(settings, ms)
  if type(base_qn) ~= "number" or (math.abs(t_lo) < 0.05 and math.abs(t_hi) < 0.05) then
    return 0.0
  end
  local t = qn_to_time(base_qn)
  if not t then
    return 0.0
  end
  local dt = seq_humanize_time_offset_sec(
    region, track_id, step_key, ms, settings.humanize_seed or settings.seed
  )
  if not dt or dt == 0.0 then
    return 0.0
  end
  local q2 = time_to_qn(math.max(0.0, t + dt))
  if not q2 then
    return 0.0
  end
  return q2 - base_qn
end

-- True if this arrange item is this note's first hit (plus humanize) or a
-- later stutter / layer piece in the same home span. Used so follow-up hits
-- are not treated as moves.
function seq_ingest_item_explained_by_note(item_qn, region, track_id, step_key, note, grid_qn, item)
  if not note or type(item_qn) ~= "number" then
    return false
  end
  local slop = seq_ingest_timing_slop_qn(region, track_id, grid_qn)
  local ghost_pad = 0.0
  if item and seq_item_is_aux_piece(item) then
    ghost_pad = SEQ_GHOST_CLOSE_MAX + 0.04
  else
    local pattern = region and get_seq_pattern(region.pattern_id, false)
    local settings = get_seq_track_settings(pattern, track_id, false)
    if seq_settings_ghost_active(settings) then
      local _, grace_hi = seq_ghost_close_range(settings, "grace")
      local _, after_hi = seq_ghost_close_range(settings, "after")
      ghost_pad = math.max(grace_hi or 0.0, after_hi or 0.0) + 0.04
    end
  end
  local expected = seq_note_expected_item_qn(region, track_id, step_key, note, grid_qn)
  if math.abs(item_qn - expected) <= slop + ghost_pad then
    return true
  end
  local home = seq_note_trigger_qn(region, step_key, note, grid_qn)
  local span = seq_stutter_span_qn(note, grid_qn)
  if (not span or span <= 0) and seq_random_stutter_count(note, region, track_id, step_key) > 1 then
    span = grid_qn or 0.25
  end
  if span and span > 0 then
    local lo = math.min(expected, home) - slop - ghost_pad
    local hi = home + span + slop + ghost_pad
    if item_qn >= lo and item_qn <= hi then
      return true
    end
  end
  -- Stitched layer / sustain pieces start after the trigger. Keep them on
  -- this note so off-grid hits do not spawn extra notes in arrange ingest.
  -- Primary copies (Ctrl+drag between grids) must become their own notes;
  -- the 1-beat cover is only for aux layer/ghost slices.
  if item and seq_item_is_aux_piece(item) then
    local cover_end = seq_ingest_note_cover_end_qn(region, track_id, step_key, note, grid_qn)
    local lo = math.min(expected, home) - slop - ghost_pad
    if item_qn >= lo and item_qn <= cover_end + slop + ghost_pad then
      return true
    end
  end
  return false
end

function seq_ingest_rec_matches_note(rec, region, track_id, step_key, note, grid_qn)
  if not rec or not note then
    return false
  end
  if rec.qn and seq_ingest_item_explained_by_note(rec.qn, region, track_id, step_key, note, grid_qn, rec.item) then
    return true
  end
  for i = 1, #(rec.items or {}) do
    local qn = seq_ingest_item_qn(rec.items[i])
    if qn and seq_ingest_item_explained_by_note(qn, region, track_id, step_key, note, grid_qn, rec.items[i]) then
      return true
    end
  end
  return false
end

-- First-hit item in a cluster: closest to the note's expected arrange position.
-- rec.qn is the earliest piece, which can be a later stutter hit or a layer
-- with a negative time offset.
function seq_ingest_rec_anchor_qn(rec, region, track_id, step_key, note, grid_qn)
  if not rec then
    return nil
  end
  if note then
    local expected = seq_note_expected_item_qn(region, track_id, step_key, note, grid_qn)
    local best_qn, best_d = rec.qn, math.huge
    for i = 1, #(rec.items or {}) do
      local item = rec.items[i]
      if not seq_item_is_aux_piece(item) then
        local qn = seq_ingest_item_qn(item)
        if qn then
          local d = math.abs(qn - expected)
          if d < best_d then
            best_d = d
            best_qn = qn
          end
        end
      end
    end
    return best_qn
  end
  return rec.qn
end

-- Map an arrange item's absolute QN to sequencer qn_offset + offset_qn.
-- Large moves retarget the note's cell instead of clamping a micro-offset.
-- The cell is the one that CONTAINS the item (floor), not the nearest cell.
-- Rounding to nearest made notes vanish past the halfway point: occupancy
-- sat on the next 16th while the note was still drawn in the previous one.
function seq_ingest_resolve_position(region, item_qn, grid_qn, track_id, existing, old_step_key)
  grid_qn = (type(grid_qn) == "number" and grid_qn > 0) and grid_qn or 0.25
  local region_start = region and region.start_qn or 0.0
  local region_len = get_seq_region_length_qn(region)
  local rel = item_qn - region_start

  if existing and seq_ingest_item_explained_by_note(item_qn, region, track_id, old_step_key, existing, grid_qn) then
    return seq_note_qn_offset(existing, old_step_key, grid_qn), existing.offset_qn or 0.0, true
  end

  local function containing_cell(rel_qn)
    local snapped = math.floor((rel_qn / grid_qn) + 1e-9) * grid_qn
    if snapped < 0 then
      snapped = 0.0
    end
    local max_start = math.max(0.0, region_len - 1e-9)
    if snapped >= max_start then
      snapped = math.floor((max_start / grid_qn) - 1e-9) * grid_qn
      if snapped < 0 then
        snapped = 0.0
      end
    end
    return snapped
  end

  local guess = containing_cell(rel)
  local groove_key = get_seq_region_groove(region)
  local groove = seq_groove_offset_qn(region_start + guess, groove_key)
  local ungrooved = rel - groove
  local snapped = containing_cell(ungrooved)
  groove = seq_groove_offset_qn(region_start + snapped, groove_key)
  -- Timing humanize is an arrange-only jitter. Do not bake it into offset_qn
  -- or the GUI shifts off-grid and the next ingest double-counts it.
  local hum = 0.0
  if old_step_key and old_step_key ~= "" then
    local base_qn = region_start + snapped + groove
    hum = seq_ingest_humanize_delta_qn(region, track_id, old_step_key, base_qn)
  end
  return snapped, rel - snapped - groove - hum, false
end

function seq_ingest_alloc_note_key(notes, qn_offset, existing)
  local base = seq_storage_key_from_qn(qn_offset)
  if not notes or not notes[base] or notes[base] == existing then
    return base
  end
  local n = 0
  local key = base
  while notes[key] and notes[key] ~= existing do
    n = n + 1
    key = base .. "_" .. tostring(n)
  end
  return key
end

function seq_add_ingest_region(out, region)
  if out and region and region.id then
    out[region.id] = region
  end
end

function seq_add_ingest_regions_overlapping_qn(out, q0, q1)
  if not out or type(q0) ~= "number" then
    return
  end
  q1 = (type(q1) == "number") and q1 or q0
  for _, region in ipairs(state.seq_regions or {}) do
    local rs = region.start_qn or 0.0
    local re = rs + get_seq_region_length_qn(region)
    if q0 < re and q1 > rs then
      seq_add_ingest_region(out, region)
    end
  end
end

-- Native arrange razors: "START END \"guid\" ..." (P_RAZOREDITS / _EXT).
function seq_track_razor_time_ranges(tr)
  local ranges = {}
  if not tr or not r.GetSetMediaTrackInfo_String then
    return ranges
  end
  local a, b = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  local s = (type(b) == "string" and b ~= "" and b) or (type(a) == "string" and a ~= "" and a) or ""
  if s == "" then
    a, b = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
    s = (type(b) == "string" and b ~= "" and b) or (type(a) == "string" and a ~= "" and a) or ""
  end
  if s == "" then
    return ranges
  end
  for a, b in s:gmatch("([%-%d%.eE]+)%s+([%-%d%.eE]+)%s+\"") do
    local t0, t1 = tonumber(a), tonumber(b)
    if t0 and t1 and t1 > t0 then
      ranges[#ranges + 1] = { t0, t1 }
    end
  end
  return ranges
end

function seq_linked_track_guid_set()
  local set = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.reaper_track_guid then
      set[slot.reaper_track_guid] = true
    end
  end
  return set
end

function seq_ingest_item_qn(item)
  if not item then
    return nil
  end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return time_to_qn(pos)
end

function seq_ingest_consider_item(rec, item, item_qn)
  if not rec or not item or not item_qn then
    return
  end
  local is_aux = seq_item_is_aux_piece(item)
  local vol, pan, pitch = seq_item_take_params(item)
  if not rec.item then
    rec.item = item
    rec.qn = item_qn
    rec.vol = vol
    rec.pan = pan
    rec.pitch = pitch
    rec.is_layer = is_aux
    return
  end
  if rec.is_layer and not is_aux then
    rec.item = item
    rec.qn = item_qn
    rec.vol = vol
    rec.pan = pan
    rec.pitch = pitch
    rec.is_layer = false
    return
  end
  if is_aux == rec.is_layer and item_qn < rec.qn then
    rec.item = item
    rec.qn = item_qn
    rec.vol = vol
    rec.pan = pan
    rec.pitch = pitch
    rec.is_layer = is_aux
  end
end

function seq_ingest_primary_item_count(items)
  local n = 0
  for i = 1, #(items or {}) do
    if not seq_item_is_aux_piece(items[i]) then
      n = n + 1
    end
  end
  return n
end

function seq_ingest_rec_from_items(items, template)
  local rec = {
    items = items or {},
    old_step = template and template.old_step or "",
    old_track = template and template.old_track or "",
    source_path = template and template.source_path or nil,
    claim_existing = false,
  }
  for i = 1, #(rec.items) do
    local item = rec.items[i]
    seq_ingest_consider_item(rec, item, seq_ingest_item_qn(item))
  end
  return rec
end

-- Razor splits copy P_EXT tags, so leftover + moved pieces share one step key.
-- Keep layers / stutter hits that still occupy the original window as one note;
-- pieces that landed elsewhere become their own notes.
function seq_ingest_split_tagged_clusters(rec, notes, region, track_id, grid_qn)
  local items = rec and rec.items or {}
  local old_key = rec and rec.old_step or ""
  local existing = notes and (notes[tostring(old_key)] or notes[old_key]) or nil
  if #items <= 1 or old_key == "" then
    rec.claim_existing = existing ~= nil
    return { rec }
  end

  -- Drum layering writes several items (transient / sustain / ghosts) that
  -- share one step key. Keep them as a single note even when the sustain
  -- starts later — ingest must not invent extra off-grid hits.
  if not existing or seq_stutter_count(existing) <= 1 then
    local stitched = false
    for i = 1, #items do
      if seq_item_is_aux_piece(items[i]) then
        stitched = true
        break
      end
    end
    if stitched then
      rec.claim_existing = existing ~= nil
      return { rec }
    end
  end

  local same_slop = math.max(0.02, (grid_qn or 0.25) * 0.08)
  local metas = {}
  for i = 1, #items do
    local qn = seq_ingest_item_qn(items[i])
    if qn then
      metas[#metas + 1] = { item = items[i], qn = qn }
    end
  end
  table.sort(metas, function(a, b) return a.qn < b.qn end)

  local buckets = {}
  for i = 1, #metas do
    local m = metas[i]
    local last = buckets[#buckets]
    local same_start = last and math.abs(m.qn - last.qn) <= same_slop
    if same_start then
      local last_aux = seq_item_is_aux_piece(last.items[1])
      local this_aux = seq_item_is_aux_piece(m.item)
      if not last_aux and not this_aux then
        same_start = false
      end
    end
    local last_end = last and seq_ingest_item_end_qn(last.items[#last.items])
    local contiguous = last_end and math.abs(m.qn - last_end) <= same_slop
    if same_start or contiguous then
      last.items[#last.items + 1] = m.item
      if m.qn < last.qn then
        last.qn = m.qn
      end
    else
      buckets[#buckets + 1] = { qn = m.qn, items = { m.item } }
    end
  end

  if #buckets <= 1 then
    rec.claim_existing = existing ~= nil
    return { rec }
  end

  local merge_gap = same_slop
  if existing and seq_stutter_count(existing) > 1 then
    local span = seq_stutter_span_qn(existing, grid_qn) or grid_qn
    local count = seq_stutter_count(existing)
    merge_gap = (span / math.max(1, count)) + same_slop
  end
  local has_stitch = false
  for i = 1, #items do
    if seq_item_is_aux_piece(items[i]) then
      has_stitch = true
      break
    end
  end
  if has_stitch then
    merge_gap = math.max(merge_gap, (grid_qn or 0.25) + same_slop)
  end

  local home_buckets, other_buckets = {}, {}
  for i = 1, #buckets do
    local b = buckets[i]
    if existing and seq_ingest_item_explained_by_note(b.qn, region, track_id, old_key, existing, grid_qn, b.items and b.items[1]) then
      home_buckets[#home_buckets + 1] = b
    else
      other_buckets[#other_buckets + 1] = b
    end
  end

  local function merge_buckets(list, gap)
    local runs = {}
    for i = 1, #list do
      local b = list[i]
      local last = runs[#runs]
      if last and (b.qn - last.last_qn) <= gap then
        for j = 1, #b.items do
          last.items[#last.items + 1] = b.items[j]
        end
        last.last_qn = b.qn
      else
        local copy = {}
        for j = 1, #b.items do
          copy[j] = b.items[j]
        end
        runs[#runs + 1] = { qn = b.qn, last_qn = b.qn, items = copy }
      end
    end
    local recs = {}
    for i = 1, #runs do
      recs[i] = seq_ingest_rec_from_items(runs[i].items, rec)
    end
    return recs
  end

  local clusters = {}
  if #home_buckets > 0 then
    local home_items = {}
    for i = 1, #home_buckets do
      for j = 1, #home_buckets[i].items do
        home_items[#home_items + 1] = home_buckets[i].items[j]
      end
    end
    local home_rec = seq_ingest_rec_from_items(home_items, rec)
    home_rec.claim_existing = existing ~= nil
    clusters[#clusters + 1] = home_rec
  end

  local other_recs = merge_buckets(other_buckets, merge_gap)
  for i = 1, #other_recs do
    clusters[#clusters + 1] = other_recs[i]
  end

  if existing and #home_buckets == 0 and #clusters > 0 then
    local best = 1
    for i = 2, #clusters do
      local ni = #(clusters[i].items or {})
      local nb = #(clusters[best].items or {})
      if ni > nb or (ni == nb and (clusters[i].qn or 0) < (clusters[best].qn or 0)) then
        best = i
      end
    end
    clusters[best].claim_existing = true
  end

  return clusters
end

function seq_ingest_expand_razor_groups(by_group, notes, region, track_id, grid_qn)
  local out = {}
  for _, rec in pairs(by_group or {}) do
    local clusters = seq_ingest_split_tagged_clusters(rec, notes, region, track_id, grid_qn)
    for i = 1, #clusters do
      out[#out + 1] = clusters[i]
    end
  end
  table.sort(out, function(a, b)
    if a.claim_existing and not b.claim_existing then
      return true
    end
    if b.claim_existing and not a.claim_existing then
      return false
    end
    return (a.qn or 0) < (b.qn or 0)
  end)
  for i = 1, #out do
    local rec = out[i]
    local old_key = rec.old_step
    rec.src_note = (old_key ~= "" and notes and (notes[tostring(old_key)] or notes[old_key])) or nil
    if rec.claim_existing and not rec.src_note then
      rec.claim_existing = false
    end
  end
  return out
end

function seq_count_owned_primary_items(region)
  local n = 0
  if not region then
    return 0
  end
  for _, slot in ipairs(state.seq_tracks or {}) do
    local tr = get_seq_slot_target_track(slot)
    if tr then
      for i = 0, r.CountTrackMediaItems(tr) - 1 do
        local item = r.GetTrackMediaItem(tr, i)
        if item and not seq_item_is_aux_piece(item) and seq_item_is_owned(item, region.id) then
          n = n + 1
        end
      end
    end
  end
  return n
end

-- Same counting as seq_count_owned_primary_items, for every region in one pass:
-- region_id -> number of owned non-aux items on the slots' target tracks.
function seq_count_owned_primary_items_by_region()
  local counts = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    local tr = get_seq_slot_target_track(slot)
    if tr then
      for i = 0, r.CountTrackMediaItems(tr) - 1 do
        local item = r.GetTrackMediaItem(tr, i)
        if item and not seq_item_is_aux_piece(item) and seq_item_is_owned(item) then
          local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
          if rid then
            counts[rid] = (counts[rid] or 0) + 1
          end
        end
      end
    end
  end
  return counts
end

function seq_region_expected_primary_notes(region)
  local n = 0
  if not region then
    return 0
  end
  local pattern = get_seq_pattern(region.pattern_id, false)
  if not pattern then
    return 0
  end
  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  for _, slot in ipairs(state.seq_tracks or {}) do
    local notes = get_track_note_table(pattern, slot.id, false)
    if notes then
      local st = get_seq_track_settings(pattern, slot.id, false)
      for step_key, note in pairs(notes) do
        if type(note) == "table" and note.enabled ~= false
            and seq_note_in_region(region, note, step_key, grid_qn)
            and seq_note_passes_probability(
              region,
              slot.id,
              step_key,
              st and st.probability,
              st and (st.probability_seed or st.seed)
            ) then
          n = n + seq_stutter_count(note)
        end
      end
    end
  end
  return n
end

function seq_regions_for_ingest()
  local out = {}
  local has_sel_item = {}
  local selected = get_selected_seq_region()
  if selected then
    out[selected.id] = selected
  end
  local sel_count = r.CountSelectedMediaItems and r.CountSelectedMediaItems(0) or 0
  local sel_linked = nil
  for i = 0, sel_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if item and seq_item_is_parent_marker(item) then
      local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
      local tagged = get_seq_region_by_id(rid)
      if tagged then
        out[tagged.id] = tagged
      end
    elseif item then
      local tr = r.GetMediaItemTrack and r.GetMediaItemTrack(item)
      local on_seq = false
      if tr then
        sel_linked = sel_linked or seq_linked_track_guid_set()
        on_seq = sel_linked[r.GetTrackGUID(tr)] == true
      end
      if on_seq then
        if seq_item_is_owned(item) then
          local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
          local tagged = get_seq_region_by_id(rid)
          if tagged then
            out[tagged.id] = tagged
          end
        end
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_qn = time_to_qn(pos)
        local dest = item_qn and seq_region_at_qn(item_qn)
        if dest then
          out[dest.id] = dest
          has_sel_item[dest.id] = true
        end
      end
    end
  end

  -- Arrange razor edits don't select items, so also follow native razors and
  -- tagged items that actually moved (wrong region, track, or time).
  local linked = seq_linked_track_guid_set()
  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local tr_count = r.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = r.GetTrack(0, tr_idx)
    local guid = tr and r.GetTrackGUID(tr)
    if guid and linked[guid] then
      local razors = seq_track_razor_time_ranges(tr)
      for i = 1, #razors do
        local t0, t1 = razors[i][1], razors[i][2]
        local q0 = time_to_qn(t0)
        local q1 = time_to_qn(t1)
        if q0 and q1 then
          seq_add_ingest_regions_overlapping_qn(out, q0, q1)
        end
      end
      for item_idx = 0, r.CountTrackMediaItems(tr) - 1 do
        local item = r.GetTrackMediaItem(tr, item_idx)
        if item and seq_item_is_owned(item) then
          local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
          local tagged = get_seq_region_by_id(rid)
          local item_qn = seq_ingest_item_qn(item)
          local dest = item_qn and seq_region_at_qn(item_qn)
          local displaced = tagged and dest and tagged.id ~= dest.id
          if not displaced and tagged and item_qn then
            local step = tostring(get_item_ext(item, SEQ_EXT_STEP) or "")
            local track_id = tonumber(get_item_ext(item, SEQ_EXT_TRACK) or "")
              or get_item_ext(item, SEQ_EXT_TRACK)
            local slot = find_seq_track_by_id(track_id)
            if slot and slot.reaper_track_guid and slot.reaper_track_guid ~= guid then
              displaced = true
            elseif step ~= "" then
              local note = get_seq_note(tagged, track_id, step)
              if not note or not seq_ingest_item_explained_by_note(item_qn, tagged, track_id, step, note, grid_qn, item) then
                displaced = true
              end
            end
          end
          if displaced then
            seq_add_ingest_region(out, tagged)
            seq_add_ingest_region(out, dest)
          end
        end
      end
    end
  end

  -- Pooled copies share pattern.notes. Ingesting two copies in one pass
  -- fights: each copy's humanize/items rewrite the same notes. Keep one
  -- region per pattern, preferring the copy that actually has the edit.
  local add = {}
  for _, region in pairs(out) do
    local pid = tonumber(region.pattern_id) or region.pattern_id
    if pid ~= nil then
      for _, other in ipairs(state.seq_regions or {}) do
        if (tonumber(other.pattern_id) or other.pattern_id) == pid then
          add[other.id] = other
        end
      end
    end
  end
  for id, region in pairs(add) do
    out[id] = region
  end
  local mismatch = {}
  local owned_counts = seq_count_owned_primary_items_by_region()
  for _, region in pairs(out) do
    mismatch[region.id] = (owned_counts[region.id] or 0) ~= seq_region_expected_primary_notes(region)
  end
  local best = {}
  for _, region in pairs(out) do
    local pid = tonumber(region.pattern_id) or region.pattern_id
    local cur = best[pid]
    if not cur then
      best[pid] = region
    else
      local r_hit = has_sel_item[region.id]
      local c_hit = has_sel_item[cur.id]
      local r_mis = mismatch[region.id]
      local c_mis = mismatch[cur.id]
      if r_hit and not c_hit then
        best[pid] = region
      elseif r_hit == c_hit and r_mis and not c_mis then
        best[pid] = region
      elseif r_hit == c_hit and r_mis == c_mis and selected then
        if region.id == selected.id then
          best[pid] = region
        end
      end
    end
  end
  return best
end

function seq_ingest_item_selected(item)
  if item and r.IsMediaItemSelected then
    return r.IsMediaItemSelected(item)
  end
  return false
end

function seq_ingest_tagged_region_owns(tagged_reg, item_qn)
  if not tagged_reg or not item_qn then
    return false
  end
  local rs = tagged_reg.start_qn or 0.0
  local re = rs + get_seq_region_length_qn(tagged_reg)
  return item_qn >= rs - 1e-9 and item_qn < re - 1e-9
end

function seq_paths_same(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then
    return false
  end
  if a == b then
    return true
  end
  return normalize_path(a) == normalize_path(b)
end

-- Pin a hit to the file currently on the arrange item when that file is not
-- the track assignment (or the sample this note would already play).
function seq_ingest_freeze_foreign_source(note, slot, source_path, region, track_id, step_key)
  if type(note) ~= "table" or not source_path or source_path == "" then
    return false
  end
  if seq_paths_same(note.frozen_sample_path, source_path) then
    return false
  end
  -- Live vary notes keep re-picking. Pinning the last roll is what made a
  -- second filter edit (or another vary stroke) stick on one file.
  if not seq_note_is_locked(note) and seq_note_has_hit_sample_vary(note) then
    return false
  end
  local vary = 0.0
  if region and track_id and step_key and seq_random_vary_amount then
    vary = seq_random_vary_amount(note, region, track_id, step_key, 1) or 0.0
  end
  local resolved = seq_resolve_note_sample and select(1, seq_resolve_note_sample(note, slot, vary, region, track_id, step_key)) or nil
  if seq_paths_same(resolved, source_path) then
    return false
  end
  local region_path = seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, region))
  if region_path and seq_paths_same(source_path, region_path) then
    if seq_note_has_frozen_sample(note) then
      seq_clear_frozen_sample(note)
      return true
    end
    return false
  end
  if slot and slot.sample_path and slot.sample_path ~= "" and seq_paths_same(source_path, slot.sample_path) then
    if seq_note_has_frozen_sample(note) then
      seq_clear_frozen_sample(note)
      return true
    end
    return false
  end
  local sample = find_sample_by_path(source_path)
  seq_apply_frozen_sample(note, source_path, sample, slot and slot.sample_path)
  note.sample_path = source_path
  note.sample_name = (sample and sample.name) or basename(source_path)
  return true
end

function seq_ingest_region_from_arrange(region)
  if not region or not state.seq_tracks or #state.seq_tracks == 0 then
    return false
  end
  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local region_start = region.start_qn or 0.0
  local region_len = get_seq_region_length_qn(region)
  local pattern = get_seq_pattern(region.pattern_id, true)
  if not pattern then
    return false
  end

  local present = {}
  local wrote_ext = false

  for _, slot in ipairs(state.seq_tracks) do
    local tr = seq_ingest_slot_track(slot) or get_seq_slot_target_track(slot)
    local linked_tr = seq_ingest_slot_track(slot)
    if tr then
      local by_group = {}
      local razor_ranges = seq_track_razor_time_ranges(tr)
      for item_idx = 0, r.CountTrackMediaItems(tr) - 1 do
        local item = r.GetTrackMediaItem(tr, item_idx)
        if item then
          local owned = seq_item_is_owned(item)
          local source_path = seq_item_source_path(item)
          -- Untagged audio is claimed on a slot's linked REAPER track. A
          -- different file is frozen onto the note so later syncs keep it.
          if owned or (source_path and linked_tr and tr == linked_tr) then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local item_qn = time_to_qn(pos)
          if item_qn then
            local dest = seq_region_at_qn(item_qn)
            local tagged_rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
            local tagged_reg = tagged_rid and get_seq_region_by_id(tagged_rid) or nil
            local rel = item_qn - region_start
            local in_this_span = rel >= -1e-9 and rel < region_len - 1e-9
            local belongs = false
            local in_native_razor = false
            if #razor_ranges > 0 then
              local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
              for ri = 1, #razor_ranges do
                local t0, t1 = razor_ranges[ri][1], razor_ranges[ri][2]
                if pos < t1 and (pos + len) > t0 then
                  in_native_razor = true
                  break
                end
              end
            end
            if not in_this_span then
              belongs = false
            elseif owned and tagged_rid == region.id then
              belongs = (not dest) or dest.id == region.id
            elseif owned and dest and dest.id == region.id then
              -- Incoming move. Ignore unselected leftovers still tagged to
              -- another living region that owns this time (e.g. after a shorten).
              -- Arrange razor moves don't select items, so treat razor hits
              -- as selected.
              if not tagged_reg or not seq_ingest_tagged_region_owns(tagged_reg, item_qn)
                 or seq_ingest_item_selected(item) or in_native_razor then
                belongs = true
              end
            elseif (not owned) and source_path then
              belongs = (not dest) or dest.id == region.id
            end
            if belongs then
              local tagged_step = tostring(get_item_ext(item, SEQ_EXT_STEP) or "")
              local group_key
              if tagged_step ~= "" then
                group_key = "t:" .. tagged_step
              elseif owned then
                group_key = "u:" .. tostring(math.floor((rel / grid_qn) + 0.5))
              else
                group_key = "n:" .. tostring(item)
              end
              local rec = by_group[group_key]
              if not rec then
                rec = {
                  items = {},
                  qn = item_qn,
                  old_step = tagged_step,
                  old_track = tostring(get_item_ext(item, SEQ_EXT_TRACK) or ""),
                  source_path = source_path,
                }
                by_group[group_key] = rec
              end
              rec.items[#rec.items + 1] = item
              seq_ingest_consider_item(rec, item, item_qn)
              rec.old_step = tagged_step
              rec.old_track = tostring(get_item_ext(item, SEQ_EXT_TRACK) or "")
              if source_path and source_path ~= "" and not seq_item_is_aux_piece(item) then
                rec.source_path = source_path
              end
            end
          end
          end
        end
      end
      present[slot.id] = by_group
    end
  end

  local changed = false
  for _, slot in ipairs(state.seq_tracks) do
    local by_group = present[slot.id]
    if by_group then
    local notes = get_track_note_table(pattern, slot.id, true)
    if notes then
      local kept = {}
      local recs = seq_ingest_expand_razor_groups(by_group, notes, region, slot.id, grid_qn)

      for _, rec in ipairs(recs) do
        if rec.qn then
        local old_key = rec.old_step
        local existing = (rec.claim_existing and rec.src_note) or nil
        local near = existing and seq_ingest_rec_matches_note(rec, region, slot.id, old_key, existing, grid_qn)
        local qn_offset, offset_qn
        if near then
          qn_offset = seq_note_qn_offset(existing, old_key, grid_qn)
          offset_qn = existing.offset_qn or 0.0
        else
          local anchor_qn = seq_ingest_rec_anchor_qn(rec, region, slot.id, old_key, existing, grid_qn) or rec.qn
          qn_offset, offset_qn, near = seq_ingest_resolve_position(
            region, anchor_qn, grid_qn, slot.id, existing, old_key
          )
        end
        local new_key = seq_ingest_alloc_note_key(notes, qn_offset, existing)

        if not existing then
          local src = rec.src_note
          local vol = rec.vol
          if rec.is_layer then
            vol = 1.0
          else
            local vel_key = (old_key ~= "" and old_key) or new_key
            vol = select(1, seq_ingest_resolve_volume(rec.vol, src, region, slot.id, vel_key))
          end
          local pitch_key = (old_key ~= "" and old_key) or new_key
          local pitch = select(1, seq_ingest_resolve_pitch(rec.pitch, src, region, slot.id, pitch_key))
          local note = seq_note_from_arrange_item(slot, new_key, grid_qn, src, vol, rec.pan, pitch, qn_offset)
          note.qn_offset = qn_offset
          note.offset_qn = offset_qn
          note.step = math.floor((qn_offset / grid_qn) + 1e-9)
          seq_note_capture_source_offset(note, rec.item)
          if rec.source_path and rec.source_path ~= "" then
            if not slot.sample_path or slot.sample_path == "" then
              note.sample_path = rec.source_path
              note.sample_name = basename(rec.source_path)
              slot.sample_path = rec.source_path
              slot.sample_name = note.sample_name
            else
              seq_ingest_freeze_foreign_source(note, slot, rec.source_path, region, slot.id, new_key)
            end
          end
          local piece_count = seq_ingest_primary_item_count(rec.items)
          if seq_stutter_count(note) > 1 then
            if piece_count <= 1 then
              note.stutter = 1
              note.stutter_hits = nil
              note.length_qn = nil
            elseif piece_count ~= seq_stutter_count(note) then
              note.stutter = piece_count
              seq_prune_stutter_hits(note)
            end
          end
          seq_ingest_apply_item_length(note, rec.item, region, pattern, slot, new_key, grid_qn, rec)
          notes[new_key] = note
          register_seq_note_anim(region.id, slot.id, new_key, note, "add")
          changed = true
        else
          local note_changed = false
          if not near then
            if math.abs((existing.qn_offset or 0) - qn_offset) > 0.0005 then
              existing.qn_offset = qn_offset
              existing.step = math.floor((qn_offset / grid_qn) + 1e-9)
              note_changed = true
            end
            if math.abs((existing.offset_qn or 0) - offset_qn) > 0.0005 then
              existing.offset_qn = offset_qn
              note_changed = true
            end
          end
          if not rec.is_layer then
            local vel_key = (old_key ~= "" and old_key) or new_key
            local new_vol, vol_changed = seq_ingest_resolve_volume(rec.vol, existing, region, slot.id, vel_key)
            if vol_changed then
              existing.volume = new_vol
              note_changed = true
            end
          end
          if math.abs((existing.pan or 0) - rec.pan) > 0.001 then
            existing.pan = rec.pan
            note_changed = true
          end
          local new_pitch, pitch_changed = seq_ingest_resolve_pitch(rec.pitch, existing, region, slot.id, vel_key)
          if pitch_changed then
            existing.pitch = new_pitch
            note_changed = true
          end
          if seq_ingest_apply_item_length(existing, rec.item, region, pattern, slot, new_key, grid_qn, rec) then
            note_changed = true
          end
          do
            local prev_off = existing.source_offset
            seq_note_capture_source_offset(existing, rec.item)
            if existing.source_offset ~= prev_off then
              note_changed = true
            end
          end
          if rec.source_path and rec.source_path ~= ""
             and seq_ingest_freeze_foreign_source(existing, slot, rec.source_path, region, slot.id, new_key) then
            note_changed = true
          end
          if old_key ~= "" and old_key ~= new_key and (notes[old_key] == existing or notes[tostring(old_key)] == existing) then
            notes[old_key] = nil
            notes[tostring(old_key)] = nil
            notes[new_key] = existing
            if state.selected_seq_note and state.selected_seq_note.region_id == region.id
               and state.selected_seq_note.track_id == slot.id
               and tostring(state.selected_seq_note.step_key) == tostring(old_key) then
              state.selected_seq_note.step_key = new_key
            end
            note_changed = true
          elseif not notes[new_key] then
            notes[new_key] = existing
            note_changed = true
          end
          if note_changed then
            register_seq_note_anim(region.id, slot.id, new_key, existing, "sync")
            changed = true
          end
        end

        kept[tostring(new_key)] = true

        for i = 1, #(rec.items or {}) do
          local item = rec.items[i]
          if get_item_ext(item, SEQ_EXT_FLAG) ~= "1"
             or tostring(get_item_ext(item, SEQ_EXT_STEP) or "") ~= tostring(new_key)
             or tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") ~= tostring(slot.id)
             or tonumber(get_item_ext(item, SEQ_EXT_REGION) or "") ~= region.id then
            set_item_ext(item, SEQ_EXT_FLAG, "1")
            set_item_ext(item, SEQ_EXT_REGION, region.id)
            set_item_ext(item, SEQ_EXT_PATTERN, region.pattern_id)
            set_item_ext(item, SEQ_EXT_TRACK, slot.id)
            set_item_ext(item, SEQ_EXT_STEP, new_key)
            wrote_ext = true
          end
        end
        end
      end

      for step_key, note in pairs(notes) do
        if type(note) == "table" and not kept[tostring(step_key)]
           and seq_note_in_region(region, note, step_key, grid_qn) then
          local st = get_seq_track_settings(pattern, slot.id, false)
          local skipped = not seq_note_passes_probability(
            region,
            slot.id,
            step_key,
            st and st.probability,
            st and (st.probability_seed or st.seed)
          )
          if not skipped then
            register_seq_note_anim(region.id, slot.id, step_key, note, "delete")
            notes[step_key] = nil
            if state.selected_seq_note and state.selected_seq_note.region_id == region.id
               and state.selected_seq_note.track_id == slot.id
               and tostring(state.selected_seq_note.step_key) == tostring(step_key) then
              state.selected_seq_note = nil
            end
            changed = true
          end
        end
      end
    end
    end
  end

  if wrote_ext then
    seq_mark_self_arrange_write()
  end
  return changed
end

function ingest_seq_from_arrange()
  seq_flush_ingest_save()
  if not r.GetProjectStateChangeCount then
    return
  end

  -- Keep seq_skip_ingest while a sequencer edit is in progress. Consuming it
  -- here used to drop the flag on the click frame, then a full arrange ingest
  -- (~150ms) ran on mouse-up during the note animation.
  if seq_ingest_busy() then
    return
  end

  local count = r.GetProjectStateChangeCount(0)
  if state.seq_skip_ingest then
    state.seq_skip_ingest = false
    state.seq_self_write_count = nil
    state.seq_ingest_pending_count = nil
    state.seq_ingest_pending_at = nil
    state.seq_last_proj_change = count
    return
  end
  -- Hold arrange ingest while the user is actively dragging selected items
  -- (LMB down). After mouse-up, settle briefly then sync even if the item
  -- stays selected — requiring a deselect click felt broken.
  local selected_items = r.CountSelectedMediaItems and r.CountSelectedMediaItems(0) or 0
  local now_t = (r.time_precise and r.time_precise()) or 0
  local have_lmb, lmb_down = false, false
  if r.JS_Mouse_GetState then
    have_lmb = true
    lmb_down = (r.JS_Mouse_GetState(1) & 1) ~= 0
  end
  if selected_items > 0 then
    if state.seq_ingest_pending_count ~= count then
      state.seq_ingest_pending_count = count
      state.seq_ingest_pending_at = now_t
      state.seq_ingest_hold_parent = true
    end
    if have_lmb and lmb_down then
      state.seq_ingest_hold_parent = true
      return
    end
    local waited = now_t - (state.seq_ingest_pending_at or now_t)
    local settle = have_lmb and 0.15 or 0.40
    if waited < settle then
      state.seq_ingest_hold_parent = true
      return
    end
    if state.seq_last_proj_change == count then
      -- Already applied this arrange revision while selection remained.
      state.seq_ingest_hold_parent = false
      return
    end
    -- Mouse up + settled: fall through and ingest with selection still active.
  end
  local force_after_hold = state.seq_ingest_hold_parent == true
  if force_after_hold then
    state.seq_ingest_hold_parent = false
  end
  if state.seq_last_proj_change == count and not force_after_hold then
    state.seq_ingest_pending_count = nil
    state.seq_ingest_pending_at = nil
    if not state.seq_parent_items_ensured then
      state.seq_parent_items_ensured = true
      seq_ensure_all_region_parent_items()
    end
    return
  end
  state.seq_ingest_pending_count = nil
  state.seq_ingest_pending_at = nil
  state.seq_last_proj_change = count

  seq_sync_track_order_from_arrange(true)

  local parent_changed, parent_synced = seq_ingest_parent_items()
  if parent_changed then
    seq_schedule_ingest_save()
    if parent_synced then
      if r.GetProjectStateChangeCount then
        state.seq_last_proj_change = r.GetProjectStateChangeCount(0)
      end
      return
    end
  end

  if not state.seq_tracks or #state.seq_tracks == 0 or not state.seq_regions or #state.seq_regions == 0 then
    return
  end

  local changed = false
  local ingested = {}
  local targets = seq_regions_for_ingest()
  for _, region in pairs(targets) do
    if seq_ingest_region_from_arrange(region) then
      changed = true
      ingested[#ingested + 1] = region
    end
  end
  if changed then
    for i = 1, #ingested do
      seq_sync_linked_arrange_from(ingested[i])
    end
    seq_schedule_ingest_save()
  end
  -- Retag writes bump the change count; keep last in sync so the skip
  -- snapshot matches even if UpdateArrange ran during this ingest pass.
  if state.seq_skip_ingest and r.GetProjectStateChangeCount then
    state.seq_last_proj_change = r.GetProjectStateChangeCount(0)
  end
end

update_seq_track_sample_assignments = function(slot, sample_path, sample_name, persist, opts)
  if not slot or not slot.id or not sample_path then
    return
  end
  opts = opts or {}

  clear_seq_vary_rank_cache()
  if seq_release_sliced_notes_for_sample_change then
    seq_release_sliced_notes_for_sample_change(slot, nil, {
      path = sample_path,
      name = sample_name or basename(sample_path),
    })
  end

  local touched_patterns = {}
  local track_key = tostring(slot.id)
  local skipped_frozen = 0
  local updated_notes = 0
  for pattern_id, pattern in pairs(state.seq_patterns) do
    if type(pattern) == "table" and type(pattern.notes) == "table" then
      local track_notes = pattern.notes[track_key]
      if type(track_notes) == "table" then
        local touched = false
        for _, note in pairs(track_notes) do
          if type(note) == "table" and not seq_note_has_frozen_sample(note) then
            note.sample_path = sample_path
            note.sample_name = sample_name or basename(sample_path)
            touched = true
            updated_notes = updated_notes + 1
          elseif type(note) == "table" then
            skipped_frozen = skipped_frozen + 1
          end
        end
        if touched then
          touched_patterns[tonumber(pattern_id) or pattern_id] = true
        end
      end
    end
  end

  if next(touched_patterns) then
    seq_pcm_take_src_begin()
    if r.PreventUIRefresh then
      r.PreventUIRefresh(1)
    end
    for pattern_id, _ in pairs(touched_patterns) do
      -- Only rewrite the swapped track. Rebuilding every sequencer track in
      -- the region is what made even sparse kits feel slow.
      sync_seq_pattern_track(pattern_id, slot, {
        skip_arrange = true,
        force_rebuild = opts.force_rebuild,
      })
    end
    if r.PreventUIRefresh then
      r.PreventUIRefresh(-1)
    end
    seq_pcm_take_src_end()
    r.UpdateArrange()
  end

  if persist then
    save_config()
  end
end

function sync_selected_seq_region()
  local region = get_selected_seq_region()
  if region then
    sync_seq_pattern_regions(region.pattern_id)
  end
end

function create_seq_region(length_bars, copy_from, pooled, preferred_start_qn, insert)
  local own = seq_undo_own_begin(pooled and copy_from and "Pool copy sequencer region" or "Create sequencer region")
  seq_remove_orphaned_region_items()
  local start_qn = 0.0
  local region_length_bars = length_bars or (copy_from and copy_from.length_bars) or 4
  if preferred_start_qn then
    start_qn = preferred_start_qn
  elseif copy_from then
    start_qn = (copy_from.start_qn or 0.0) + get_seq_region_length_qn(copy_from)
  else
    local arrange_start = select(1, get_arrange_view_range())
    start_qn = time_to_qn(arrange_start) or 0.0
  end
  local length_qn = get_seq_region_length_qn({ start_qn = start_qn, length_bars = region_length_bars })
  start_qn = math.max(0.0, start_qn)
  local did_insert = insert or (preferred_start_qn and seq_region_overlaps(start_qn, length_qn, nil))
  if did_insert then
    seq_shift_regions_from(start_qn, length_qn, nil)
  else
    start_qn = find_non_overlapping_region_start(start_qn, length_qn, nil)
  end

  local pattern_id
  local pool_id
  if copy_from and pooled then
    pattern_id = copy_from.pattern_id
    pool_id = copy_from.pool_id or alloc_seq_pool()
    copy_from.pool_id = pool_id
  else
    pattern_id = alloc_seq_pattern()
    pool_id = alloc_seq_pool()
    if copy_from then
      local src_pattern = get_seq_pattern(copy_from.pattern_id, false)
      state.seq_patterns[tostring(pattern_id)] = clone_table_deep(src_pattern or { notes = {} })
    end
  end

  local region = {
    id = state.seq_region_next_id,
    name = seq_auto_name_new_region(start_qn),
    start_qn = start_qn,
    length_bars = region_length_bars,
    pool_id = pool_id,
    pattern_id = pattern_id,
    groove = copy_from and normalize_seq_groove(copy_from.groove) or "off",
    style_key = copy_from and copy_from.style_key or nil,
    style_source = copy_from and copy_from.style_source or nil,
    kit_genres = copy_from and copy_from.kit_genres and clone_table_deep(copy_from.kit_genres) or nil,
    track_samples = copy_from and seq_clone_region_track_samples(copy_from) or nil,
  }
  state.seq_region_next_id = state.seq_region_next_id + 1
  table.insert(state.seq_regions, region)
  table.sort(state.seq_regions, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
  state.selected_seq_region_id = region.id
  save_config()
  if copy_from and pooled then
    sync_seq_pattern_regions(pattern_id)
    seq_parent_sync_pool(pool_id)
  else
    sync_seq_region(region)
  end
  if own then
    end_seq_undo(pooled and copy_from and "Pool copy sequencer region" or "Create sequencer region")
  end
  return region
end

function unpool_selected_seq_region()
  seq_unpool_region(get_selected_seq_region())
end

function clear_selected_seq_region()
  local region = get_selected_seq_region()
  if not region then
    return
  end
  local own = seq_undo_own_begin("Clear sequencer region")
  local pattern = get_seq_pattern(region.pattern_id, true)
  pattern.notes = {}
  pattern.locked_cells = nil
  pattern.vary_filters = nil
  state.selected_seq_note = nil
  save_config()
  sync_seq_pattern_regions(region.pattern_id)
  if own then
    end_seq_undo("Clear sequencer region")
  end
end

function delete_selected_seq_region()
  local own = seq_undo_own_begin("Delete sequencer region")
  local region = get_selected_seq_region()
  if not region then
    if own then
      end_seq_undo("Delete sequencer region")
    end
    return
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  remove_seq_rendered_items(region)
  seq_remove_region_parent_item(region)
  local removed_idx = nil
  for i, reg in ipairs(state.seq_regions) do
    if reg.id == region.id then
      removed_idx = i
      break
    end
  end
  if removed_idx then
    table.remove(state.seq_regions, removed_idx)
  end

  local pattern_still_used = false
  for _, reg in ipairs(state.seq_regions) do
    if reg.pattern_id == region.pattern_id then
      pattern_still_used = true
      break
    end
  end
  if not pattern_still_used then
    state.seq_patterns[tostring(region.pattern_id)] = nil
  end
  local pending_confirm = state.seq_pattern_confirm
  if pending_confirm and (pending_confirm.region_id == region.id
      or tostring(pending_confirm.pattern_id) == tostring(region.pattern_id)) then
    state.seq_pattern_confirm = nil
  end

  if #state.seq_regions == 0 then
    state.selected_seq_region_id = nil
    state.selected_seq_note = nil
    ensure_default_seq_region()
  else
    local next_region = state.seq_regions[math.min(removed_idx or 1, #state.seq_regions)] or state.seq_regions[1]
    state.selected_seq_region_id = next_region.id
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  seq_refresh_arrange()
  save_config()
  if own then
    end_seq_undo("Delete sequencer region")
  end
end

function move_selected_seq_region(delta_qn)
  local region = get_selected_seq_region()
  if not region then
    return
  end
  local length_qn = get_seq_region_length_qn(region)
  local desired = math.max(0.0, (region.start_qn or 0.0) + delta_qn)
  local new_start
  if delta_qn < 0 then
    new_start = find_prev_non_overlapping_region_start(desired, length_qn, region.id)
  else
    new_start = find_non_overlapping_region_start(desired, length_qn, region.id)
  end
  if math.abs(new_start - (region.start_qn or 0.0)) < 0.000001 then
    return
  end
  local own = seq_undo_own_begin("Move sequencer region")
  remove_seq_rendered_items(region)
  region.start_qn = new_start
  sort_seq_regions()
  state.seq_view_start_qn = new_start
  state.seq_view_span_qn = length_qn
  save_config()
  sync_seq_region(region)
  if own then
    end_seq_undo("Move sequencer region")
  end
end

SEQ_REGION_EDGE_PX = 6
SEQ_LINK_ICON_SIZE = 12
SEQ_LINK_HIT_PAD = 3

function seq_region_link_icon_xy(rx0, y0, region_lane_h)
  local lane_h = region_lane_h or 22.0
  return (rx0 or 0) + 4, (y0 or 0) + (lane_h - SEQ_LINK_ICON_SIZE) * 0.5
end

function seq_region_link_hit_rect(rx0, y0, region_lane_h)
  local ix, iy = seq_region_link_icon_xy(rx0, y0, region_lane_h)
  local pad = SEQ_LINK_HIT_PAD
  return ix - pad, iy - pad, ix + SEQ_LINK_ICON_SIZE + pad, iy + SEQ_LINK_ICON_SIZE + pad
end

function seq_snap_qn(qn, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  return math.floor((qn / step_qn) + 0.5) * step_qn
end

function seq_get_measure_end_qn(measure)
  if not r.TimeMap_GetMeasureInfo then
    return nil
  end
  local _, qn_start, qn_end, ts_num, ts_den = r.TimeMap_GetMeasureInfo(0, measure)
  if not qn_start then
    return nil
  end
  if type(qn_end) == "number" and qn_end > qn_start then
    return qn_end
  end
  local out_num = (type(ts_num) == "number" and ts_num > 0) and ts_num or 4
  local out_den = (type(ts_den) == "number" and ts_den > 0) and ts_den or 4
  return qn_start + out_num * (4.0 / out_den)
end

function seq_get_measure_start_qn(measure)
  if not r.TimeMap_GetMeasureInfo then
    return nil
  end
  local _, qn_start = r.TimeMap_GetMeasureInfo(0, measure)
  if type(qn_start) == "number" then
    return qn_start
  end
  return nil
end

function seq_snap_qn_to_measure_end(qn)
  qn = math.max(0.0, qn or 0.0)
  if not r.TimeMap_GetMeasureInfo or not r.TimeMap2_timeToBeats then
    return seq_snap_qn(qn, state.seq_grid_qn or 0.25)
  end
  local time = qn_to_time(qn)
  if not time then
    return qn
  end
  local _, measure = r.TimeMap2_timeToBeats(0, time)
  if measure == nil then
    return qn
  end

  local measure_idx = math.max(0, math.floor((tonumber(measure) or 0) + 0.5))
  local best = seq_snap_qn(qn, state.seq_grid_qn or 0.25)
  local best_dist = math.abs(qn - best)
  for m = math.max(0, measure_idx - 1), measure_idx + 2 do
    local end_qn = seq_get_measure_end_qn(m)
    if end_qn then
      local dist = math.abs(qn - end_qn)
      if dist < best_dist then
        best_dist = dist
        best = end_qn
      end
    end
  end
  return best
end

function seq_snap_qn_to_bar(qn, step_qn)
  qn = math.max(0.0, qn or 0.0)
  if not r.TimeMap_GetMeasureInfo or not r.TimeMap2_timeToBeats then
    return seq_snap_qn(qn, step_qn or state.seq_grid_qn or 0.25)
  end
  local time = qn_to_time(qn)
  if not time then
    return qn
  end
  local _, measure = r.TimeMap2_timeToBeats(0, time)
  if measure == nil then
    return qn
  end

  local measure_idx = math.max(0, math.floor(tonumber(measure) or 0))
  local start_qn = seq_get_measure_start_qn(measure_idx)
  if start_qn then
    return start_qn
  end
  return seq_snap_qn(qn, step_qn or state.seq_grid_qn or 0.25)
end

function seq_snap_qn_for_region_drag(qn, step_qn)
  if is_shift_down() then
    return seq_snap_qn(qn, step_qn)
  end
  return seq_snap_qn_to_bar(qn, step_qn)
end

function seq_snap_qn_for_region_move(qn, step_qn)
  if is_shift_down() then
    return seq_snap_qn(qn, step_qn)
  end
  return seq_snap_qn_to_bar(qn, step_qn)
end

function seq_x_to_qn(mx, timeline_x0, timeline_w, start_qn, qn_span)
  return start_qn + ((mx - timeline_x0) / math.max(1.0, timeline_w)) * qn_span
end

-- Timeline pan inertia (QN velocity, runtime only — not saved to config).
SEQ_TIMELINE_SCROLL_GAIN = 0.0062
SEQ_TIMELINE_SCROLL_FRICTION = 0.84
SEQ_TIMELINE_SCROLL_MAX_VEL_RATIO = 0.13

function seq_timeline_scroll_stop()
  state.seq_view_scroll_vel_qn = 0.0
  state.seq_scroll_last_t = nil
end

function seq_timeline_scroll_is_active()
  local vel = state.seq_view_scroll_vel_qn or 0.0
  local span = state.seq_view_span_qn or 4.0
  return math.abs(vel) >= span * 0.00022
end

function seq_view_is_driving_arrange()
  return state.seq_follow_arrange and (state.seq_drive_arrange or seq_timeline_scroll_is_active())
end

function seq_timeline_scroll_impulse(pan_wheel, view_span_qn)
  if not pan_wheel or pan_wheel == 0 then
    return
  end
  local impulse = -pan_wheel * view_span_qn * SEQ_TIMELINE_SCROLL_GAIN
  local vel = (state.seq_view_scroll_vel_qn or 0.0) + impulse
  local max_vel = view_span_qn * SEQ_TIMELINE_SCROLL_MAX_VEL_RATIO
  state.seq_view_scroll_vel_qn = math.max(-max_vel, math.min(max_vel, vel))
end

function seq_timeline_scroll_apply_inertia(view_span_qn, dt)
  local vel = state.seq_view_scroll_vel_qn or 0.0
  local min_vel = view_span_qn * 0.00022
  if math.abs(vel) < min_vel then
    if vel ~= 0.0 then
      state.seq_view_scroll_vel_qn = 0.0
    end
    return false
  end
  state.seq_view_start_qn = math.max(0.0, (state.seq_view_start_qn or 0.0) + vel)
  state.seq_view_scroll_vel_qn = vel * (SEQ_TIMELINE_SCROLL_FRICTION ^ (dt * 60.0))
  return true
end

function seq_apply_time_zoom(wheel_delta, mx, timeline_x0, timeline_w, view_start_qn, qn_span, step_qn)
  if not wheel_delta or wheel_delta == 0 then
    return false
  end
  if state.seq_follow_arrange then
    state.seq_drive_arrange = true
  end
  local base_span = state.seq_view_span_qn or qn_span
  local ratio = math.max(0.0, math.min(1.0, (mx - timeline_x0) / math.max(1.0, timeline_w)))
  local anchor = (view_start_qn or 0.0) + base_span * ratio
  local step = step_qn or state.seq_grid_qn or 0.25
  local new_span = math.max(step * 8.0, math.min(step * 4096.0, base_span * math.exp(-wheel_delta * 0.2)))
  state.seq_view_start_qn = math.max(0.0, anchor - new_span * ratio)
  state.seq_view_span_qn = new_span
  seq_timeline_scroll_stop()
  return true
end

function seq_region_pool_count(pool_id)
  pool_id = tonumber(pool_id)
  local count = 0
  if not pool_id then
    return 0
  end
  for _, reg in ipairs(state.seq_regions) do
    if tonumber(reg.pool_id) == pool_id then
      count = count + 1
    end
  end
  return count
end

function seq_qn_length_to_bars(start_qn, length_qn)
  length_qn = math.max(state.seq_grid_qn or 0.25, length_qn)
  local bars = 1
  while bars < 512 do
    local test = { start_qn = start_qn, length_bars = bars }
    if get_seq_region_length_qn(test) >= length_qn - 0.0001 then
      return bars
    end
    bars = bars + 1
  end
  return bars
end

function seq_select_region(reg)
  if not reg then
    return
  end
  if state.selected_seq_region_id == reg.id then
    return
  end
  state.selected_seq_region_id = reg.id
  save_config()
end

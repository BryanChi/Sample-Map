-- Sample Map Browser module: seq_render_items
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_item_source_path(item)
  if not item then
    return nil
  end
  local take = r.GetActiveTake(item)
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
    local parent = r.GetMediaSourceParent(src)
    local guard = 0
    while parent and guard < 8 do
      src = parent
      parent = r.GetMediaSourceParent(src)
      guard = guard + 1
    end
  end
  if not r.GetMediaSourceFileName then
    return nil
  end
  local a, b = r.GetMediaSourceFileName(src, "")
  local path = nil
  if type(b) == "string" and b ~= "" then
    path = b
  elseif type(a) == "string" and a ~= "" then
    path = a
  end
  if not path or path == "" then
    return nil
  end
  return normalize_path(path)
end

function seq_ingest_slot_track(slot)
  if not slot or not slot.reaper_track_guid then
    return nil
  end
  return get_track_by_guid(slot.reaper_track_guid)
end

function remove_seq_rendered_items(region)
  local removed = 0
  local region_id = region and region.id or nil
  local tr_count = r.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = r.GetTrack(0, tr_idx)
    local removed_here = removed
    for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item, region_id) then
        if r.DeleteTrackMediaItem(tr, item) then
          removed = removed + 1
        end
      end
    end
    if removed > removed_here then
      seq_mark_self_arrange_write(tr, region_id)
    end
  end
  return removed
end

function remove_seq_rendered_items_by_ids(id_set)
  if type(id_set) ~= "table" then
    return 0
  end
  local removed = 0
  local tr_count = r.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = r.GetTrack(0, tr_idx)
    for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and get_item_ext(item, SEQ_EXT_FLAG) == "1" then
        local rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
        if rid and id_set[rid] then
          if r.DeleteTrackMediaItem(tr, item) then
            removed = removed + 1
            seq_mark_self_arrange_write(tr, rid)
          end
        end
      end
    end
  end
  return removed
end

function seq_remove_orphaned_region_items()
  local removed = 0
  local tr_count = r.CountTracks(0)
  for tr_idx = 0, tr_count - 1 do
    local tr = r.GetTrack(0, tr_idx)
    for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_owned(item) then
        local tagged_rid = tonumber(get_item_ext(item, SEQ_EXT_REGION) or "")
        local tagged_reg = tagged_rid and get_seq_region_by_id(tagged_rid)
        if tagged_reg then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local item_qn = time_to_qn(pos)
          if item_qn then
            local rs = tagged_reg.start_qn or 0.0
            local re = rs + get_seq_region_length_qn(tagged_reg)
            if (item_qn < rs - 0.000001 or item_qn >= re - 0.000001)
                and not seq_item_rendered_at_home(item, item_qn, tagged_reg) then
              if r.DeleteTrackMediaItem(tr, item) then
                removed = removed + 1
              end
            end
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

SEQ_STUTTER_MIN = 2
SEQ_STUTTER_MAX = 256
SEQ_STUTTER_DRAG_PX = 8.0
SEQ_STUTTER_AXIS_PX = 6.0
SEQ_STUTTER_SKEW_MIN = -2.0
SEQ_STUTTER_SKEW_MAX = 2.0
SEQ_STUTTER_SKEW_PX = 70.0
SEQ_STUTTER_LANE_STACK_MAX = 32

function seq_stutter_count(note)
  return math.max(1, math.floor((note and note.stutter or 1) + 0.5))
end

-- Shallow note view with an effective stutter count for span/length math.
-- Used when region humanize stutter expands a note without baking note.stutter.
function seq_note_for_stutter_render(note, count)
  count = math.max(1, math.floor((tonumber(count) or 1) + 0.5))
  if type(note) ~= "table" or seq_stutter_count(note) == count then
    return note
  end
  local view = {}
  for k, v in pairs(note) do
    view[k] = v
  end
  view.stutter = count
  return view
end

function seq_stutter_span_qn(note, grid_qn)
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  local span = tonumber(note and note.length_qn)
  local has_span = type(span) == "number" and span > 1e-9
  if seq_stutter_count(note) <= 1 then
    -- Keep a painted multi-grid span after count returns to 1 so the block
    -- stays occupied and the amount can be dragged back up. Default one-grid
    -- length_qn is only a placeholder and must not replace sample sustain.
    if has_span and span > grid_qn + 1e-9 then
      return math.max(grid_qn * 0.25, span)
    end
    return nil
  end
  if has_span then
    return math.max(grid_qn * 0.25, span)
  end
  return grid_qn
end

function seq_note_lod_length_qn(note, step_qn)
  local span = seq_stutter_span_qn(note, step_qn)
  if span then
    return span
  end
  local len = tonumber(note and note.length_qn)
  if type(len) == "number" and len > 1e-9 then
    return len
  end
  return step_qn or 0.25
end

function seq_active_cell_has_visual_start(active, start_qn, col, step_qn)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return false
  end
  step_qn = step_qn or 0.25
  local cell_qn = (start_qn or 0.0) + (col or 0) * step_qn
  local cell_end = cell_qn + step_qn
  for i = 1, #pack do
    local vis = seq_entry_vis_qn(pack[i])
    if vis + 1e-9 >= cell_qn and vis < cell_end + 1e-9 then
      return true
    end
  end
  return false
end

function seq_note_has_stutter_span(note, grid_qn)
  local span = seq_stutter_span_qn(note, grid_qn)
  return type(span) == "number" and span > 1e-9
end

function seq_clamp_stutter_count(n)
  n = math.floor((tonumber(n) or 1) + 0.5)
  if n < 1 then n = 1 end
  if n > SEQ_STUTTER_MAX then n = SEQ_STUTTER_MAX end
  return n
end

function seq_stutter_skew(note)
  local s = tonumber(note and note.stutter_skew) or 0.0
  if s < SEQ_STUTTER_SKEW_MIN then return SEQ_STUTTER_SKEW_MIN end
  if s > SEQ_STUTTER_SKEW_MAX then return SEQ_STUTTER_SKEW_MAX end
  return s
end

function seq_stutter_hit_start_frac(count, hit_idx, skew)
  count = math.max(1, math.floor((count or 1) + 0.5))
  local i = math.max(1, math.min(count, math.floor((hit_idx or 1) + 0.5)))
  if count <= 1 or i <= 1 then
    return 0.0
  end
  local u = (i - 1) / count
  skew = tonumber(skew) or 0.0
  if math.abs(skew) < 1e-6 then
    return u
  end
  -- Positive skew bunches hits toward the end (drag right).
  return u ^ (2 ^ (-skew))
end

function seq_stutter_hit_end_frac(count, hit_idx, skew)
  count = math.max(1, math.floor((count or 1) + 0.5))
  local i = math.max(1, math.min(count, math.floor((hit_idx or 1) + 0.5)))
  if i >= count then
    return 1.0
  end
  return seq_stutter_hit_start_frac(count, i + 1, skew)
end

function seq_stutter_hit_span(note, hit_idx, grid_qn)
  local count = seq_stutter_count(note)
  local span = seq_stutter_span_qn(note, grid_qn) or (grid_qn or 0.25)
  local skew = seq_stutter_skew(note)
  local f0 = seq_stutter_hit_start_frac(count, hit_idx, skew)
  local f1 = seq_stutter_hit_end_frac(count, hit_idx, skew)
  return span * f0, span * f1, span * math.max(0.0, f1 - f0)
end

function seq_stutter_count_from_relative_dy(origin_count, origin_y, my)
  local dy = (origin_y or my or 0) - (my or origin_y or 0)
  local steps = dy / SEQ_STUTTER_DRAG_PX
  if steps >= 0 then
    steps = math.floor(steps)
  else
    steps = math.ceil(steps)
  end
  return seq_clamp_stutter_count((origin_count or 1) + steps)
end

function seq_stutter_skew_from_dx(origin_skew, origin_x, mx)
  local dx = (mx or origin_x or 0) - (origin_x or mx or 0)
  local skew = (origin_skew or 0.0) + dx / SEQ_STUTTER_SKEW_PX
  if skew < SEQ_STUTTER_SKEW_MIN then return SEQ_STUTTER_SKEW_MIN end
  if skew > SEQ_STUTTER_SKEW_MAX then return SEQ_STUTTER_SKEW_MAX end
  if math.abs(skew) < 0.001 then return 0.0 end
  return skew
end

function seq_set_stutter_skew(note, skew)
  if type(note) ~= "table" then
    return false
  end
  skew = seq_stutter_skew({ stutter_skew = skew })
  local cur = tonumber(note.stutter_skew) or 0.0
  if math.abs(cur - skew) < 1e-6 then
    return false
  end
  note.stutter_skew = (math.abs(skew) < 1e-4) and nil or skew
  return true
end

function seq_clear_stutter_badge_hits()
  state.seq_stutter_badge_hits = {}
end

function seq_register_stutter_badge_hit(x0, y0, x1, y1, track_id, region_id, step_key)
  if not x0 or not y0 or not x1 or not y1 then
    return
  end
  state.seq_stutter_badge_hits = state.seq_stutter_badge_hits or {}
  state.seq_stutter_badge_hits[#state.seq_stutter_badge_hits + 1] = {
    x0 = x0 - 3, y0 = y0 - 3, x1 = x1 + 3, y1 = y1 + 3,
    track_id = track_id, region_id = region_id, step_key = step_key,
  }
end

function seq_stutter_badge_at(mx, my)
  local hits = state.seq_stutter_badge_hits
  if not hits or mx == nil or my == nil then
    return nil
  end
  for i = #hits, 1, -1 do
    local h = hits[i]
    if mx >= h.x0 and mx <= h.x1 and my >= h.y0 and my <= h.y1 then
      return h
    end
  end
  return nil
end

function seq_note_draw_length_qn(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  local span = seq_stutter_span_qn(note, grid_qn)
  if span then
    return span
  end
  -- While rows draw (seq_trigger_memo set; notes are read-only there) the same
  -- note's length is asked for by its note lane and every parameter lane.
  local memo = seq_trigger_memo
  if memo and type(note) == "table" then
    local by_note = memo.draw_len
    if not by_note then
      by_note = {}
      memo.draw_len = by_note
    end
    local list = by_note[note]
    if list then
      for i = 1, #list do
        local e = list[i]
        if e[1] == region and e[2] == pattern and e[3] == slot and e[4] == track_id
            and e[5] == step_idx and e[6] == resolved_sample and e[7] == grid_qn then
          return e[8]
        end
      end
    else
      list = {}
      by_note[note] = list
    end
    local len = seq_note_draw_length_qn_uncached(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
    list[#list + 1] = { region, pattern, slot, track_id, step_idx, resolved_sample, grid_qn, len }
    return len
  end
  return seq_note_draw_length_qn_uncached(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
end

function seq_note_draw_length_qn_uncached(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
  local len = seq_effective_note_length_qn(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn)
  local decay_qn = tonumber(note and note.decay_qn)
  if type(decay_qn) == "number" and decay_qn > 1e-9 then
    return len
  end
  local resolved_path = (resolved_sample and resolved_sample.path)
    or (note and note.frozen_sample_path)
    or (note and note.sample_path)
    or (slot and slot.sample_path)
  local sample_qn = seq_sample_length_qn(resolved_path, resolved_sample)
  -- Long samples stay at least one full grid cell so a nearby next hit
  -- cannot collapse the block into a sliver.
  if sample_qn and sample_qn > grid_qn + 1e-9 then
    len = math.max(len or 0, grid_qn)
  end
  return seq_cap_length_to_region_end_qn(len, region, step_idx, note, grid_qn)
end

function seq_note_head_end_x(qn_to_x, note_abs_qn, note, step_qn)
  if not qn_to_x then
    return nil
  end
  local vis = (note_abs_qn or 0.0) + ((note and note.offset_qn) or 0.0)
  return qn_to_x(vis + (step_qn or 0.25)) - 2.0
end

-- True when this occupied cell is the note's start cell (or a stutter span).
-- Head/sustain that draws into the next grid is not playable: that cell stays
-- empty so hover shows the grid and a click paints a new note.
function seq_active_cell_is_playable(active, start_qn, col, step_qn)
  if not active or type(active.note) ~= "table" then
    return false
  end
  if seq_note_has_stutter_span(active.note, step_qn) then
    return true
  end
  local vis = (active.abs_qn or 0.0) + (active.note.offset_qn or 0.0)
  local cell_qn = (start_qn or 0.0) + (col or 0) * (step_qn or 0.25)
  return vis >= cell_qn - 1e-9 and vis < cell_qn + (step_qn or 0.25) - 1e-9
end

function seq_stutter_count_from_drag_dy(origin_y, my)
  local dy = math.abs((my or origin_y or 0) - (origin_y or 0))
  return seq_clamp_stutter_count(SEQ_STUTTER_MIN + math.floor(dy / SEQ_STUTTER_DRAG_PX))
end

SEQ_STUTTER_HIT_KEYS = {
  volume = true,
  pan = true,
  pitch = true,
  sample_vary = true,
  offset_qn = true,
  stretch = true,
  start = true,
}

function seq_stutter_hit_param_key(key)
  return (key and SEQ_STUTTER_HIT_KEYS[key]) and key or nil
end

function seq_stutter_hit_table(note, hit_idx)
  if type(note) ~= "table" or type(note.stutter_hits) ~= "table" or not hit_idx then
    return nil
  end
  local hit = note.stutter_hits[hit_idx]
  if type(hit) ~= "table" then
    hit = note.stutter_hits[tostring(hit_idx)]
  end
  if type(hit) == "table" then
    return hit
  end
  return nil
end

function seq_note_has_hit_sample_vary(note)
  if type(note) ~= "table" then
    return false
  end
  if (tonumber(note.sample_vary) or 0) > 0.000001 then
    return true
  end
  if type(note.stutter_hits) ~= "table" then
    return false
  end
  for _, hit in pairs(note.stutter_hits) do
    if type(hit) == "table" and (tonumber(hit.sample_vary) or 0) > 0.000001 then
      return true
    end
  end
  return false
end

function seq_note_has_frozen_sample(note)
  if type(note) ~= "table" then
    return false
  end
  if type(note.frozen_sample_path) == "string" and note.frozen_sample_path ~= "" then
    return true
  end
  if type(note.stutter_hits) ~= "table" then
    return false
  end
  for _, hit in pairs(note.stutter_hits) do
    if type(hit) == "table" and type(hit.frozen_sample_path) == "string" and hit.frozen_sample_path ~= "" then
      return true
    end
  end
  return false
end

function seq_clear_frozen_sample(note, hit_idx)
  if type(note) ~= "table" then
    return
  end
  if hit_idx then
    local hit = seq_stutter_hit_table(note, hit_idx)
    if type(hit) == "table" then
      hit.frozen_sample_path = nil
      hit.frozen_sample_name = nil
      hit.vary_origin_path = nil
      hit.vary_rgb = nil
      hit.picked_sample = nil
    end
    return
  end
  note.frozen_sample_path = nil
  note.frozen_sample_name = nil
  note.vary_origin_path = nil
  note.vary_rgb = nil
  note.picked_sample = nil
  if type(note.stutter_hits) ~= "table" then
    return
  end
  for _, hit in pairs(note.stutter_hits) do
    if type(hit) == "table" then
      hit.frozen_sample_path = nil
      hit.frozen_sample_name = nil
      hit.vary_origin_path = nil
      hit.vary_rgb = nil
      hit.picked_sample = nil
    end
  end
end

function seq_prune_stutter_hits(note)
  if type(note) ~= "table" then
    return
  end
  local count = seq_stutter_count(note)
  if type(note.stutter_hits) ~= "table" then
    return
  end
  if count <= 1 then
    note.stutter_hits = nil
    return
  end
  local stale = {}
  for k, _ in pairs(note.stutter_hits) do
    local i = tonumber(k)
    if i and i > count then
      stale[#stale + 1] = k
    end
  end
  for i = 1, #stale do
    note.stutter_hits[stale[i]] = nil
  end
  local any = false
  for _, hit in pairs(note.stutter_hits) do
    if type(hit) == "table" then
      any = true
      break
    end
  end
  if not any then
    note.stutter_hits = nil
  end
end

function seq_note_param_value(note, key, hit_idx)
  if not note or not key then
    return nil
  end
  if key == "locked" then
    return seq_note_is_locked(note) and 1.0 or 0.0
  end
  if hit_idx and SEQ_STUTTER_HIT_KEYS[key] then
    local hit = seq_stutter_hit_table(note, hit_idx)
    if type(hit) == "table" and hit[key] ~= nil then
      return hit[key]
    end
  end
  return note[key]
end

function seq_set_note_param_value(note, key, value, hit_idx)
  if not note or not key then
    return false
  end
  if key == "locked" then
    local locked = value == true or (tonumber(value) or 0) >= 0.5
    if seq_note_is_locked(note) == locked then
      return false
    end
    note.locked = locked or nil
    return true
  end
  if key == "stutter" then
    local new_count = seq_clamp_stutter_count(value)
    if note.stutter == new_count then
      seq_prune_stutter_hits(note)
      return false
    end
    note.stutter = new_count
    seq_prune_stutter_hits(note)
    return true
  end
  if hit_idx and SEQ_STUTTER_HIT_KEYS[key] and seq_stutter_count(note) > 1 then
    note.stutter_hits = note.stutter_hits or {}
    local hit = seq_stutter_hit_table(note, hit_idx)
    if type(hit) ~= "table" then
      hit = {}
      note.stutter_hits[hit_idx] = hit
    end
    if hit[key] == value then
      return false
    end
    hit[key] = value
    if key == "sample_vary" then
      seq_clear_frozen_sample(note, hit_idx)
      -- Parent pins are inherited by hits without their own freeze. Clear the
      -- note-level pin so live per-hit vary can resolve a new sample.
      if (tonumber(value) or 0) > 0.000001 then
        note.frozen_sample_path = nil
        note.frozen_sample_name = nil
        note.vary_origin_path = nil
        note.vary_rgb = nil
        note.picked_sample = nil
      end
    end
    return true
  end
  if note[key] == value then
    return false
  end
  note[key] = value
  if key == "sample_vary" then
    seq_clear_frozen_sample(note)
  end
  return true
end

function seq_reset_note_param_value(note, key, hit_idx, default_value)
  if not note or not key then
    return false
  end
  if key == "locked" then
    return seq_set_note_param_value(note, "locked", 0)
  end
  if hit_idx and SEQ_STUTTER_HIT_KEYS[key] and seq_stutter_count(note) > 1 then
    return seq_set_note_param_value(note, key, default_value, hit_idx)
  end
  local changed = false
  if note[key] ~= default_value then
    note[key] = default_value
    changed = true
  end
  if note.stutter_hits and SEQ_STUTTER_HIT_KEYS[key] then
    for _, hit in pairs(note.stutter_hits) do
      if type(hit) == "table" and hit[key] ~= nil then
        hit[key] = nil
        changed = true
      end
    end
  end
  if key == "stutter" then
    seq_prune_stutter_hits(note)
    if seq_set_stutter_skew(note, 0) then
      changed = true
    end
  end
  if key == "sample_vary" and seq_note_has_frozen_sample(note) then
    seq_clear_frozen_sample(note, hit_idx)
    changed = true
  end
  return changed
end

function seq_stutter_hit_index_at_qn(note, note_abs_qn, qn, grid_qn)
  local count = seq_stutter_count(note)
  if count <= 1 then
    return nil
  end
  local span = seq_stutter_span_qn(note, grid_qn) or grid_qn
  if not span or span <= 1e-9 then
    return 1
  end
  local start = (note_abs_qn or 0.0) + ((note and note.offset_qn) or 0.0)
  local t = ((qn or start) - start) / span
  if t < 0 then t = 0 end
  if t >= 1 then t = 0.999999 end
  local skew = seq_stutter_skew(note)
  if math.abs(skew) > 1e-6 then
    local exp = 2 ^ (-skew)
    if exp > 1e-6 then
      t = t ^ (1.0 / exp)
    end
  end
  return math.max(1, math.min(count, math.floor(t * count) + 1))
end

function seq_stutter_hits_overlapping_qn_range(note, note_abs_qn, qn0, qn1, grid_qn)
  local count = seq_stutter_count(note)
  if count <= 1 then
    return nil
  end
  local start = (note_abs_qn or 0.0) + ((note and note.offset_qn) or 0.0)
  local hits = {}
  for hi = 1, count do
    local off0, off1 = seq_stutter_hit_span(note, hi, grid_qn)
    local s0 = start + off0
    local s1 = start + off1
    if s0 < (qn1 or s0) - 1e-9 and s1 > (qn0 or s0) + 1e-9 then
      hits[#hits + 1] = hi
    end
  end
  return hits
end

function seq_note_for_stutter_hit(note, hit_idx)
  if type(note) ~= "table" then
    return note
  end
  local hit = seq_stutter_hit_table(note, hit_idx)
  local sample_vary = seq_note_param_value(note, "sample_vary", hit_idx) or 0.0
  local hit_has_own_pin = hit and type(hit.frozen_sample_path) == "string" and hit.frozen_sample_path ~= ""
  -- Live per-hit variation must not inherit the parent note's pinned sample;
  -- that pin would win in resolve_seq_note_sample and ignore sample_vary.
  local inherit_pin = hit_has_own_pin or not (sample_vary > 0.000001)
  return {
    enabled = note.enabled ~= false,
    sample_path = note.sample_path,
    sample_name = note.sample_name,
    frozen_sample_path = hit_has_own_pin and hit.frozen_sample_path
      or (inherit_pin and note.frozen_sample_path or nil),
    frozen_sample_name = hit_has_own_pin and hit.frozen_sample_name
      or (inherit_pin and note.frozen_sample_name or nil),
    vary_origin_path = hit_has_own_pin and hit.vary_origin_path
      or (inherit_pin and note.vary_origin_path or nil),
    vary_rgb = hit_has_own_pin and hit.vary_rgb
      or (inherit_pin and note.vary_rgb or nil),
    picked_sample = (hit and hit.picked_sample)
      or (inherit_pin and note.picked_sample or nil),
    volume = seq_note_param_value(note, "volume", hit_idx) or 1.0,
    pan = seq_note_param_value(note, "pan", hit_idx) or 0.0,
    pitch = seq_note_param_value(note, "pitch", hit_idx) or 0.0,
    sample_vary = sample_vary,
    offset_qn = seq_note_param_value(note, "offset_qn", hit_idx) or 0.0,
    stretch = seq_note_param_value(note, "stretch", hit_idx) or 1.0,
    start = seq_note_param_value(note, "start", hit_idx) or 0.0,
    source_offset = (hit and type(hit.source_offset) == "number" and hit.source_offset)
      or note.source_offset,
    length_qn = note.length_qn,
    decay_qn = note.decay_qn,
    fade_in_qn = note.fade_in_qn,
    fade_out_qn = note.fade_out_qn,
    fade_in_shape = note.fade_in_shape,
    fade_out_shape = note.fade_out_shape,
    fade_in_curve = note.fade_in_curve,
    fade_out_curve = note.fade_out_curve,
    stutter = 1,
    locked = note.locked,
  }
end

function seq_apply_param_to_note(note, abs_qn, def, value, qn, step_qn, reset, all_hits_in_range, range_qn0, range_qn1)
  if not note or not def then
    return false
  end
  local key = def.key
  if key == "decay" then
    return false
  end
  if key == "locked" or def.boolean then
    return seq_set_note_param_value(note, "locked", reset and 0 or 1)
  end
  if reset and not seq_stutter_hit_param_key(key) then
    return seq_reset_note_param_value(note, key, nil, def.default)
  end
  if all_hits_in_range and seq_stutter_hit_param_key(key) then
    local hits = seq_stutter_hits_overlapping_qn_range(note, abs_qn, range_qn0, range_qn1, step_qn)
    if hits and #hits > 0 then
      local changed = false
      for i = 1, #hits do
        if reset then
          if seq_reset_note_param_value(note, key, hits[i], def.default) then
            changed = true
          end
        elseif seq_set_note_param_value(note, key, value, hits[i]) then
          changed = true
        end
      end
      return changed
    end
  end
  local hit_idx = seq_stutter_hit_param_key(key) and seq_stutter_hit_index_at_qn(note, abs_qn, qn, step_qn) or nil
  if reset then
    return seq_reset_note_param_value(note, key, hit_idx, def.default)
  end
  return seq_set_note_param_value(note, key, value, hit_idx)
end

function seq_note_qn_range(note, step_key, grid_qn)
  local start_qn = seq_note_qn_offset(note, step_key, grid_qn)
  local span = seq_stutter_span_qn(note, grid_qn)
  if span then
    return start_qn, start_qn + span
  end
  return start_qn, start_qn
end

function seq_find_slot_by_id(track_id)
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.id == track_id then
      return slot
    end
  end
  return nil
end

function seq_delete_notes_overlapping_span(region, slot, span_start, span_end, keep_key, grid_qn, opts)
  if not region or not slot then
    return false
  end
  opts = opts or {}
  local notes = get_track_note_table(get_seq_pattern(region.pattern_id, false), slot.id, false)
  if not notes then
    return false
  end
  keep_key = tostring(keep_key or "")
  local slop = opts.slop or 1e-4
  local to_delete = {}
  for key, note in pairs(notes) do
    if tostring(key) ~= keep_key and type(note) == "table" then
      local n_start, n_end = seq_note_qn_range(note, key, grid_qn)
      local overlaps
      if opts.same_start then
        -- Off-grid inserts keep later grid hits even when sustain draws over them.
        overlaps = math.abs(n_start - (span_start or 0.0)) <= slop
      elseif n_end > n_start + 1e-9 then
        overlaps = n_start < span_end - 1e-9 and n_end > span_start + 1e-9
      else
        overlaps = n_start >= span_start - 1e-9 and n_start < span_end - 1e-9
      end
      if overlaps then
        to_delete[#to_delete + 1] = { key = key, note = note }
      end
    end
  end
  if #to_delete == 0 then
    return false
  end
  for i = 1, #to_delete do
    local item = to_delete[i]
    register_seq_note_anim(region.id, slot.id, item.key, item.note, "delete")
    delete_seq_note(region, slot.id, item.key)
    if not opts.defer_arrange then
      remove_seq_rendered_items_for_step(region, slot, slot.id, item.key)
    end
  end
  return true
end

function seq_active_cells_put(active_cells, slot_id, col, entry, start_qn, step_qn, step_count)
  if not active_cells or not active_cells[slot_id] or col < 0 or col >= step_count then
    return
  end
  local cell = active_cells[slot_id][col]
  if not cell then
    active_cells[slot_id][col] = {
      key = entry.key,
      note = entry.note,
      region_id = entry.region_id,
      abs_qn = entry.abs_qn,
      pack = { entry },
    }
    return
  end
  cell.pack[#cell.pack + 1] = entry
end

function seq_finish_active_cells(active_cells)
  if not active_cells then
    return
  end
  for _, cells in pairs(active_cells) do
    for _, cell in pairs(cells) do
      local pack = cell.pack
      if pack and #pack >= 2 then
        seq_pack_sort_later_on_top(pack)
      end
      local top = pack and pack[#pack]
      if top then
        cell.key = top.key
        cell.note = top.note
        cell.region_id = top.region_id
        cell.abs_qn = top.abs_qn
      end
    end
  end
end

function apply_seq_note_params(item, take, note)
  if item then
    -- Item vol and take vol multiply. Keep the item at unity and put
    -- note velocity on the take so 1.0 stays 0 dB.
    r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  end
  if take then
    r.SetMediaItemTakeInfo_Value(take, "D_VOL", note.volume or 1.0)
    r.SetMediaItemTakeInfo_Value(take, "D_PAN", note.pan or 0.0)
    r.SetMediaItemTakeInfo_Value(take, "D_PITCH", note.pitch or 0.0)
    local stretch = seq_note_stretch_amount(note)
    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0 / stretch)
    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
  end
end

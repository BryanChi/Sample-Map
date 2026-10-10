-- Sample Map Browser module: drum_layering
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- ===== Drum layering ====================================================
-- Each sequencer track can blend three samples for the transient and three
-- for the sustain. Blend weights are barycentric coordinates in a triangle.

function seq_layering_button(id, dl, x, y, size, active)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local bg = active and UI_THEME.accent_fill or UI_THEME.surface
  local edge = hovered and 0xFFFFFFFF or (active and UI_THEME.accent or UI_THEME.border)
  local col = active and 0xC8FF9AFF or 0xD0D8E8FF
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + size, y + size, bg, 3.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + size, y + size, edge, 3.0, 0, 1.0)
  local pad = size * 0.22
  local ax = x + size * 0.5
  local ay = y + pad
  local bx = x + pad
  local by = y + size - pad
  local cx_pt = x + size - pad
  local cy_pt = by
  r.ImGui_DrawList_AddTriangleFilled(dl, ax, ay, bx, by, cx_pt, cy_pt, col)
  r.ImGui_DrawList_AddLine(dl, ax, ay, bx, by, edge, 1.0)
  r.ImGui_DrawList_AddLine(dl, bx, by, cx_pt, cy_pt, edge, 1.0)
  r.ImGui_DrawList_AddLine(dl, cx_pt, cy_pt, ax, ay, edge, 1.0)
  return clicked
end

function seq_layer_vert_vol(vert)
  local v = tonumber(vert and vert.vol)
  if v == nil then return 1.0 end
  if v < 0.0 then return 0.0 end
  local max_v = SEQ_LAYER_VOL_MAX or 4.0
  if v > max_v then return max_v end
  return v
end

function seq_layer_default_side()
  return {
    verts = {
      { path = nil, name = nil, locked = true, vol = 1.0 },
      { path = nil, name = nil, locked = false, vol = 1.0 },
      { path = nil, name = nil, locked = false, vol = 1.0 },
    },
    blend = { 1.0, 0.0, 0.0 },
  }
end

-- Normalizes in place (no new tables once a side is well formed): this runs
-- many times per frame while the layering window is open.
function seq_layer_normalize_side(side)
  if type(side) ~= "table" then
    return seq_layer_default_side()
  end
  if type(side.verts) ~= "table" then
    side.verts = seq_layer_default_side().verts
  end
  for i = 1, 3 do
    local v = side.verts[i]
    if type(v) ~= "table" then
      side.verts[i] = { path = nil, name = nil, locked = (i == 1), vol = 1.0 }
    else
      v.locked = v.locked == true
      v.vol = seq_layer_vert_vol(v)
      if v.path == "" then v.path = nil end
    end
  end
  local b = side.blend
  if type(b) ~= "table" then
    side.blend = { 1.0, 0.0, 0.0 }
  else
    b[1], b[2], b[3] = seq_layer_clamp_bary(tonumber(b[1]) or 0, tonumber(b[2]) or 0, tonumber(b[3]) or 0)
  end
  return side
end

function seq_normalize_slot_layers(slot)
  if not slot then return end
  if type(slot.layers) ~= "table" then
    slot.layers = {}
  end
  slot.layers.transient = seq_layer_normalize_side(slot.layers.transient)
  slot.layers.sustain = seq_layer_normalize_side(slot.layers.sustain)
  slot.layers.linked = slot.layers.linked == true
  if slot.layers.output ~= "original" and slot.layers.output ~= "layered" then
    slot.layers.output = nil
  end
  local bias = tonumber(slot.layers.bias)
  if bias == nil then
    slot.layers.bias = 0.0
  else
    if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
    slot.layers.bias = bias
  end
  if slot.layers.top_locked_inited ~= true then
    slot.layers.transient.verts[1].locked = true
    slot.layers.sustain.verts[1].locked = true
    slot.layers.top_locked_inited = true
  end
end

function seq_layering_copy_side(dst, src)
  if not dst or not src then return end
  if type(dst.verts) ~= "table" then
    dst.verts = seq_layer_default_side().verts
  end
  local sb = src.blend or { 1.0, 0.0, 0.0 }
  dst.blend = { sb[1] or 1.0, sb[2] or 0.0, sb[3] or 0.0 }
  for i = 1, 3 do
    local sv = src.verts and src.verts[i]
    if type(dst.verts[i]) ~= "table" then
      dst.verts[i] = { path = nil, name = nil, locked = (i == 1), vol = 1.0 }
    end
    if sv then
      dst.verts[i].path = sv.path
      dst.verts[i].name = sv.name
      dst.verts[i].locked = sv.locked == true
      dst.verts[i].vol = seq_layer_vert_vol(sv)
    end
  end
end

function seq_layering_copy_to_slot(dst, src)
  if not dst or not src then return end
  seq_normalize_slot_layers(src)
  seq_normalize_slot_layers(dst)
  dst.layers.linked = src.layers.linked == true
  dst.layers.output = src.layers.output
  dst.layers.bias = src.layers.bias or 0.0
  dst.layers.top_locked_inited = true
  seq_layering_copy_side(dst.layers.transient, src.layers.transient)
  seq_layering_copy_side(dst.layers.sustain, src.layers.sustain)
end

function seq_layering_sync_linked(slot, from_key)
  if not slot then return end
  seq_normalize_slot_layers(slot)
  if not slot.layers.linked then return end
  from_key = from_key or "transient"
  local src = slot.layers[from_key]
  local dst = slot.layers[from_key == "transient" and "sustain" or "transient"]
  seq_layering_copy_side(dst, src)
end

function seq_layering_set_linked(slot, linked)
  if not slot then return end
  seq_normalize_slot_layers(slot)
  linked = linked == true
  if slot.layers.linked == linked then return end
  slot.layers.linked = linked
  if linked then
    seq_layering_sync_linked(slot, "transient")
  end
end

function seq_layering_follow_track_sample(slot, old_path, sample)
  if not slot or not sample or not sample.path then
    return
  end
  seq_normalize_slot_layers(slot)
  local old_norm = old_path and normalize_path(old_path) or nil
  local new_path = sample.path
  local new_name = sample.name or basename(new_path)
  for _, side_key in ipairs({ "transient", "sustain" }) do
    local side = slot.layers[side_key]
    local v = side and side.verts and side.verts[1]
    if type(v) == "table" then
      local vp = v.path and normalize_path(v.path) or nil
      -- Locked top is the track original and must follow a swap.
      -- Also replace empty verts or verts that still point at the old sample.
      if v.locked or not vp or (old_norm and vp == old_norm) then
        v.path = new_path
        v.name = new_name
        v.vol = 1.0
        if v.locked or not vp then
          v.locked = true
        end
      end
    end
  end
  if slot.layers.linked then
    seq_layering_sync_linked(slot, "transient")
  end
end

function seq_layering_seed_from_track(slot)
  if not slot then return end
  seq_normalize_slot_layers(slot)
  if not slot.sample_path then return end
  local sides = { slot.layers.transient, slot.layers.sustain }
  for i = 1, 2 do
    local v = sides[i] and sides[i].verts and sides[i].verts[1]
    if type(v) == "table" and not v.path then
      v.path = slot.sample_path
      v.name = slot.sample_name or basename(slot.sample_path)
      v.locked = true
    end
  end
  if slot.layers.linked then
    seq_layering_sync_linked(slot, "transient")
  end
end

function seq_layering_set_vert(slot, side_key, idx, sample)
  if not slot or not sample or not sample.path then return end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  if not side or idx < 1 or idx > 3 then return end
  local v = side.verts[idx]
  if v.locked then
    if idx == 1 then
      assign_sample_to_seq_track(slot, sample, true)
    end
    return
  end
  v.path = sample.path
  v.name = sample.name or basename(sample.path)
  v.vol = 1.0
  seq_layering_ensure_audible(side, idx)
  seq_layering_sync_linked(slot, side_key)
end

function seq_layer_clamp_bary(a, b, c)
  a = math.max(0.0, a or 0.0)
  b = math.max(0.0, b or 0.0)
  c = math.max(0.0, c or 0.0)
  local s = a + b + c
  if s < 1e-9 then
    return 1.0, 0.0, 0.0
  end
  return a / s, b / s, c / s
end

function seq_layer_barycentric_raw(px, py, ax, ay, bx, by, cx, cy)
  local v0x, v0y = cx - ax, cy - ay
  local v1x, v1y = bx - ax, by - ay
  local v2x, v2y = px - ax, py - ay
  local dot00 = v0x * v0x + v0y * v0y
  local dot01 = v0x * v1x + v0y * v1y
  local dot02 = v0x * v2x + v0y * v2y
  local dot11 = v1x * v1x + v1y * v1y
  local dot12 = v1x * v2x + v1y * v2y
  local denom = dot00 * dot11 - dot01 * dot01
  if math.abs(denom) < 1e-12 then
    return 1.0, 0.0, 0.0
  end
  local u = (dot11 * dot02 - dot01 * dot12) / denom
  local v = (dot00 * dot12 - dot01 * dot02) / denom
  local w = 1.0 - u - v
  return w, v, u
end

function seq_layer_barycentric(px, py, ax, ay, bx, by, cx, cy)
  local w, v, u = seq_layer_barycentric_raw(px, py, ax, ay, bx, by, cx, cy)
  return seq_layer_clamp_bary(w, v, u)
end

function seq_layer_point_from_bary(blend, ax, ay, bx, by, cx, cy)
  local a = blend[1] or 1.0
  local b = blend[2] or 0.0
  local c = blend[3] or 0.0
  return ax * a + bx * b + cx * c, ay * a + by * b + cy * c
end

function seq_layering_collect_pool(slot, side, vert_idx)
  local pool = {}
  local used = {}
  seq_normalize_slot_layers(slot)
  local verts = slot.layers[side].verts
  for i = 1, 3 do
    if verts[i] and verts[i].path then
      used[verts[i].path] = true
    end
  end
  if slot.sample_path then
    used[slot.sample_path] = true
  end
  local origin = (verts[vert_idx] and verts[vert_idx].path and find_sample_by_path(verts[vert_idx].path))
      or find_sample_by_path(slot.sample_path)
  local role = seq_vary_role_for_origin(slot, origin)

  local function consider(s, drums_only)
    if not s or not s.path or used[s.path] then
      return
    end
    if sample_scan_folder_unavailable(s) then
      return
    end
    if drums_only and not sample_is_drum_oneshot(s) then
      return
    end
    if role and not seq_sample_matches_vary_role(s, role) then
      return
    end
    pool[#pool + 1] = s
    used[s.path] = true
  end

  local ranked = {}
  if origin and collect_map_samples_by_distance then
    ranked = collect_map_samples_by_distance(origin, role)
  end
  for i = 1, #ranked do
    consider(ranked[i].sample, true)
    if #pool >= 48 then return pool end
  end
  if #pool < 8 then
    for i = 1, #ranked do
      consider(ranked[i].sample, false)
      if #pool >= 48 then return pool end
    end
  end
  if #pool < 4 then
    for _, s in ipairs(state.samples) do
      consider(s, true)
      if #pool >= 48 then return pool end
    end
  end
  if #pool < 2 then
    for _, s in ipairs(state.samples) do
      consider(s, false)
      if #pool >= 48 then return pool end
    end
  end
  return pool
end

function seq_layering_ensure_audible(side, idx)
  if not side or not side.blend then return end
  local b = side.blend
  if (b[idx] or 0) >= 0.08 then
    return
  end
  local pull = 0.34
  b[1] = (b[1] or 0) * (1.0 - pull)
  b[2] = (b[2] or 0) * (1.0 - pull)
  b[3] = (b[3] or 0) * (1.0 - pull)
  b[idx] = (b[idx] or 0) + pull
  local a, bb, c = seq_layer_clamp_bary(b[1], b[2], b[3])
  side.blend = { a, bb, c }
end

function seq_layering_repair_note_volumes(slot)
  if not slot or not slot.id then
    return
  end
  for _, pattern in pairs(state.seq_patterns or {}) do
    if type(pattern) == "table" then
      local notes = get_track_note_table(pattern, slot.id, false)
      if notes then
        for _, note in pairs(notes) do
          -- Older layering wrote item*take*blend into note.volume (~0.08 and down).
          if type(note) == "table" and type(note.volume) == "number"
             and note.volume > 0.0 and note.volume < 0.1 then
            note.volume = 1.0
          end
        end
      end
    end
  end
end

function seq_layering_sync_arrange(slot, opts)
  if not slot or not slot.id then
    return
  end
  opts = opts or {}
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  for _, region in ipairs(state.seq_regions or {}) do
    sync_seq_region_track(region, slot, {
      skip_arrange = true,
      force_rebuild = opts.force_rebuild,
    })
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if r.UpdateArrange then
    r.UpdateArrange()
  end
end

function seq_layering_get_bias(slot)
  if not slot then return 0.0 end
  seq_normalize_slot_layers(slot)
  return slot.layers.bias or 0.0
end

function seq_layering_apply_bias(base_trans, onset, dur, bias)
  onset = math.max(0.0, onset or 0.0)
  dur = math.max(onset + 0.02, dur or 0.2)
  local base_len = math.max(0.004, (base_trans or (onset + 0.02)) - onset)
  local min_len = 0.004
  local max_len = math.min(math.max(0.02, dur - onset - 0.012), math.max(base_len * 4.0, 0.12))
  if max_len < base_len then
    max_len = math.min(math.max(0.02, dur - onset - 0.012), base_len * 2.0)
  end
  bias = tonumber(bias) or 0.0
  if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
  local len
  if bias <= 0.0 then
    len = min_len + (base_len - min_len) * (bias + 1.0)
  else
    len = base_len + (max_len - base_len) * bias
  end
  return onset + math.max(min_len, len)
end

-- Onset, unbiased transient end and length (seconds) of a sample, as the
-- transient / sustain split uses them.
function seq_layering_trans_base(sample)
  local dur = seq_sample_source_length_sec(sample and sample.path, sample)
      or (sample and tonumber(sample.duration)) or 0.2
  if dur <= 0.001 then dur = 0.2 end
  local onset = (sample and type(sample.onset) == "number" and sample.onset > 0) and sample.onset or 0.0
  local trans = (sample and type(sample.transient_end) == "number" and sample.transient_end > 0)
      and sample.transient_end or math.min(0.024, dur * 0.18)
  trans = math.max(onset + 0.003, math.min(trans, dur * 0.9))
  return onset, trans, dur
end

-- Inverse of seq_layering_apply_bias: the bias that puts the split at t.
function seq_layering_bias_for_trans(base_trans, onset, dur, t)
  onset = math.max(0.0, onset or 0.0)
  dur = math.max(onset + 0.02, dur or 0.2)
  local base_len = math.max(0.004, (base_trans or (onset + 0.02)) - onset)
  local min_len = 0.004
  local max_len = math.min(math.max(0.02, dur - onset - 0.012), math.max(base_len * 4.0, 0.12))
  if max_len < base_len then
    max_len = math.min(math.max(0.02, dur - onset - 0.012), base_len * 2.0)
  end
  local len = (tonumber(t) or (onset + base_len)) - onset
  local bias
  if len <= base_len then
    bias = (base_len > min_len) and ((len - min_len) / (base_len - min_len) - 1.0) or 0.0
  else
    bias = (max_len > base_len) and ((len - base_len) / (max_len - base_len)) or 0.0
  end
  if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
  return bias
end

function seq_layering_piece_times(sample, side_key, slot)
  local onset, trans, dur = seq_layering_trans_base(sample)
  if slot then
    trans = seq_layering_apply_bias(trans, onset, dur, seq_layering_get_bias(slot))
    trans = math.max(onset + 0.003, math.min(trans, dur * 0.9))
  end
  if side_key == "transient" then
    return onset, math.max(0.004, trans - onset)
  end
  return trans, math.max(0.012, dur - trans)
end

SEQ_LAYER_XFADE_SEC = 0.008
SEQ_LAYER_VOL_MAX = 4.0

function seq_layering_geometry_active(slot)
  if not slot then
    return false
  end
  seq_normalize_slot_layers(slot)
  local sides = { slot.layers.transient, slot.layers.sustain }
  for s = 1, 2 do
    local side = sides[s]
    if math.abs((side.blend[1] or 1.0) - 1.0) > 0.02 then
      return true
    end
    for i = 2, 3 do
      if (side.blend[i] or 0.0) >= 0.02 and side.verts[i] and side.verts[i].path then
        return true
      end
    end
    local v1 = side.verts[1]
    if v1 and v1.path and slot.sample_path and v1.path ~= slot.sample_path then
      return true
    end
  end
  return false
end

function seq_layering_output(slot)
  if not slot then
    return "original"
  end
  seq_normalize_slot_layers(slot)
  local out = slot.layers.output
  if out == "original" or out == "layered" then
    return out
  end
  return seq_layering_geometry_active(slot) and "layered" or "original"
end

function seq_layering_set_output(slot, kind)
  if not slot or (kind ~= "original" and kind ~= "layered") then
    return false
  end
  seq_normalize_slot_layers(slot)
  if slot.layers.output == kind then
    return false
  end
  slot.layers.output = kind
  state.seq_layering_ab = kind
  seq_layering_sync_arrange(slot, { force_rebuild = true })
  save_config()
  return true
end

function seq_layering_is_active(slot)
  return seq_layering_output(slot) == "layered" and seq_layering_geometry_active(slot)
end

function seq_layering_drag_sample(slot)
  if not slot or not slot.sample_path then
    return nil
  end
  local src = find_sample_by_path(slot.sample_path)
  local name = slot.sample_name or (src and src.name) or basename(slot.sample_path)
  return {
    path = slot.sample_path,
    name = name .. " (layered)",
    duration = src and src.duration,
    is_layering_mix = true,
    layering_slot_id = slot.id,
  }
end

function apply_dragged_sample_to_seq_track(slot, sample, persist)
  if not slot or not sample then
    return false
  end
  if sample.is_layering_mix then
    local src = find_seq_track_by_id(sample.layering_slot_id)
    if src and src.id ~= slot.id then
      local base = find_sample_by_path(src.sample_path)
        or { path = src.sample_path, name = src.sample_name }
      assign_sample_to_seq_track(slot, base, persist)
      seq_layering_copy_to_slot(slot, src)
    elseif (not src) and sample.path then
      assign_sample_to_seq_track(slot, find_sample_by_path(sample.path) or sample, persist)
    end
    seq_normalize_slot_layers(slot)
    slot.layers.output = "layered"
    seq_layering_sync_arrange(slot)
    if persist ~= false then
      save_config()
    end
    return true
  end
  return seq_assign_sample_for_context(slot, sample, persist)
end

function seq_layering_insert_mix_at_position(sample, time_pos, target_track)
  if not sample or not time_pos then
    return false
  end
  local slot = sample.layering_slot_id and find_seq_track_by_id(sample.layering_slot_id)
  local pieces = slot and seq_layering_build_pieces(slot) or {}
  if #pieces == 0 then
    local fallback = (slot and slot.sample_path and find_sample_by_path(slot.sample_path))
      or find_sample_by_path(sample.path)
      or sample
    local clean = {
      path = fallback.path,
      name = fallback.name,
      duration = fallback.duration,
    }
    return insert_sample_at_position(clean, time_pos, target_track)
  end

  local track = target_track
  if not track then
    track = r.GetSelectedTrack(0, 0)
    if not track then
      local num_tracks = r.CountTracks(0)
      if num_tracks > 0 then
        track = r.GetTrack(0, 0)
      end
    end
  end
  if not track then
    return false
  end

  r.PreventUIRefresh(1)
  local any = false
  for i = 1, #pieces do
    local piece = pieces[i]
    if piece.path and r.file_exists(piece.path) then
      local item = r.AddMediaItemToTrack(track)
      local item_ok = false
      if item then
        local src_sample = piece.sample or find_sample_by_path(piece.path)
        local pdur = (seq_sample_source_length_sec and seq_sample_source_length_sec(piece.path, src_sample))
          or (src_sample and tonumber(src_sample.duration))
          or (sample.duration or 1.0)
        local startoffs = piece.startoffs or 0.0
        local len = piece.length_sec
        if not len or len <= 0 then
          len = math.max(0.001, pdur - startoffs)
        end
        r.SetMediaItemPosition(item, time_pos + (piece.time_offset_sec or 0.0), false)
        r.SetMediaItemLength(item, len, false)
        local take = r.AddTakeToMediaItem(item)
        if take then
          local src = r.PCM_Source_CreateFromFile(piece.path)
          if src then
            r.SetMediaItemTake_Source(take, src)
            set_item_name(item, take, piece.path)
            if startoffs > 0 then
              r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startoffs)
            end
            local gain = (piece.weight or 1.0) * get_sample_gain(src_sample)
            if gain ~= 1.0 then
              r.SetMediaItemTakeInfo_Value(take, "D_VOL", gain)
            end
            seq_item_apply_layer_fades(item, piece.fade_in, piece.fade_out)
            rebuild_peaks_for_item(item)
            any = true
            item_ok = true
          end
        end
        if not item_ok and r.DeleteTrackMediaItem then
          -- Source failed to load: don't leave an empty item behind.
          r.DeleteTrackMediaItem(track, item)
        end
      end
    end
  end
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  return any
end

-- The sample whose transient sets the split: the track sample, else the first
-- transient corner that resolves.
function seq_layering_split_sample(slot)
  local sample = slot and find_sample_by_path(slot.sample_path)
  if not sample and slot then
    seq_normalize_slot_layers(slot)
    for i = 1, 3 do
      local v = slot.layers.transient.verts[i]
      if v and v.path then
        sample = find_sample_by_path(v.path)
        if sample then
          break
        end
      end
    end
  end
  return sample
end

function seq_layering_split_sec(slot)
  local _, tlen = seq_layering_piece_times(seq_layering_split_sample(slot), "transient", slot)
  return math.max(0.004, tlen or 0.02)
end

-- Split position in the split sample's own time (seconds from its start).
function seq_layering_split_time(slot)
  local sample = seq_layering_split_sample(slot)
  local onset, tlen = seq_layering_piece_times(sample, "transient", slot)
  return onset + tlen, sample
end

-- Moves the split to time t (seconds into the split sample) by setting the bias.
function seq_layering_set_split_time(slot, t)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local onset, trans, dur = seq_layering_trans_base(seq_layering_split_sample(slot))
  local bias = seq_layering_bias_for_trans(trans, onset, dur, t)
  if math.abs((slot.layers.bias or 0.0) - bias) < 1e-6 then
    return false
  end
  slot.layers.bias = bias
  return true
end

function seq_layering_remap_piece_lanes(pieces)
  local used = {}
  for p = 1, #pieces do
    used[pieces[p].lane] = true
  end
  local map = {}
  local n = 0
  for i = 0, 2 do
    if used[i] then
      map[i] = n
      n = n + 1
    end
  end
  for p = 1, #pieces do
    pieces[p].lane = map[pieces[p].lane] or 0
  end
  return pieces
end

function seq_layering_build_pieces(slot)
  seq_normalize_slot_layers(slot)
  if not seq_layering_geometry_active(slot) then
    return {}
  end
  if slot.layers.linked then
    local side = slot.layers.transient
    local pieces = {}
    for i = 1, 3 do
      local v, w = side.verts[i], side.blend[i] or 0.0
      local path = (w >= 0.02 and v and v.path) and normalize_path(v.path) or nil
      if path then
        pieces[#pieces + 1] = {
          path = path,
          sample = find_sample_by_path(path) or { path = path, name = v and v.name },
          weight = w * seq_layer_vert_vol(v),
          lane = i - 1,
          startoffs = 0.0,
          time_offset_sec = 0.0,
          length_sec = nil,
          fade_in = 0.0,
          fade_out = 0.0,
        }
      end
    end
    return seq_layering_remap_piece_lanes(pieces)
  end
  local tside = slot.layers.transient
  local sside = slot.layers.sustain
  local split = seq_layering_split_sec(slot)
  local xf = SEQ_LAYER_XFADE_SEC
  if split < xf * 2.0 then
    xf = math.max(0.002, split * 0.35)
  end
  local pieces = {}
  for i = 1, 3 do
    local tv, tw = tside.verts[i], tside.blend[i] or 0.0
    local sv, sw = sside.verts[i], sside.blend[i] or 0.0
    local tpath = (tw >= 0.02 and tv and tv.path) and normalize_path(tv.path) or nil
    local spath = (sw >= 0.02 and sv and sv.path) and normalize_path(sv.path) or nil
    if tpath and spath and tpath == spath and math.abs(tw - sw) < 0.05 then
      pieces[#pieces + 1] = {
        path = tpath,
        sample = find_sample_by_path(tpath) or { path = tpath, name = tv and tv.name },
        weight = (tw * seq_layer_vert_vol(tv) + sw * seq_layer_vert_vol(sv)) * 0.5,
        lane = i - 1,
        startoffs = 0.0,
        time_offset_sec = 0.0,
        length_sec = nil,
        fade_in = 0.0,
        fade_out = 0.0,
      }
    else
      if tpath then
        local sample = find_sample_by_path(tpath) or { path = tpath, name = tv and tv.name }
        local offs = seq_layering_piece_times(sample, "transient", slot)
        pieces[#pieces + 1] = {
          path = tpath,
          sample = sample,
          weight = tw * seq_layer_vert_vol(tv),
          lane = i - 1,
          startoffs = offs or 0.0,
          time_offset_sec = 0.0,
          length_sec = split + xf,
          fade_in = 0.0,
          fade_out = xf,
        }
      end
      if spath then
        local sample = find_sample_by_path(spath) or { path = spath, name = sv and sv.name }
        local offs, slen = seq_layering_piece_times(sample, "sustain", slot)
        pieces[#pieces + 1] = {
          path = spath,
          sample = sample,
          weight = sw * seq_layer_vert_vol(sv),
          lane = i - 1,
          startoffs = offs or 0.0,
          time_offset_sec = split,
          length_sec = slen,
          fade_in = xf,
          fade_out = 0.0,
        }
      end
    end
  end
  return seq_layering_remap_piece_lanes(pieces)
end

function seq_item_apply_layer_fades(item, fade_in, fade_out)
  if not item then
    return
  end
  fade_in = math.max(0.0, fade_in or 0.0)
  fade_out = math.max(0.0, fade_out or 0.0)
  r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out)
  if fade_in > 0.0 then
    pcall(function()
      r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 1)
    end)
  end
  if fade_out > 0.0 then
    pcall(function()
      r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 1)
    end)
  end
  pcall(function()
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", 0)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", 0)
  end)
end

function seq_layering_randomize_vert(slot, side, vert_idx)
  seq_normalize_slot_layers(slot)
  local v = slot.layers[side].verts[vert_idx]
  if not v or v.locked then
    return false
  end
  local pool = seq_layering_collect_pool(slot, side, vert_idx)
  if #pool == 0 then
    log("No other samples available to layer")
    return false
  end
  local pick = pool[math.random(1, #pool)]
  if not pick then
    return false
  end
  v.path = pick.path
  v.name = pick.name or basename(pick.path)
  v.vol = 1.0
  seq_layering_ensure_audible(slot.layers[side], vert_idx)
  seq_layering_sync_linked(slot, side)
  state.seq_layering_ab = nil
  preview_sample(pick)
  return true
end

function seq_layering_randomize_side(slot, side)
  seq_normalize_slot_layers(slot)
  local changed = false
  for i = 1, 3 do
    if seq_layering_randomize_vert(slot, side, i) then
      changed = true
    end
  end
  return changed
end

-- Puts the whole blend on one corner.
function seq_layering_solo_vert(slot, side_key, idx)
  if not slot or idx < 1 or idx > 3 then return false end
  seq_normalize_slot_layers(slot)
  local b = slot.layers[side_key].blend
  b[1], b[2], b[3] = 0.0, 0.0, 0.0
  b[idx] = 1.0
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Equal weights across the corners that hold a sample.
function seq_layering_even_mix(slot, side_key)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  local w = { 0.0, 0.0, 0.0 }
  local n = 0
  for i = 1, 3 do
    if side.verts[i].path then
      w[i] = 1.0
      n = n + 1
    end
  end
  if n == 0 then
    w = { 1.0, 1.0, 1.0 }
  end
  side.blend[1], side.blend[2], side.blend[3] = seq_layer_clamp_bary(w[1], w[2], w[3])
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Back to the track sample alone: blend on the top corner, volumes at 100%.
function seq_layering_reset_side(slot, side_key)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  side.blend[1], side.blend[2], side.blend[3] = 1.0, 0.0, 0.0
  for i = 1, 3 do
    side.verts[i].vol = 1.0
  end
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Empties an unlocked side corner (the top corner is the track sample).
function seq_layering_clear_vert(slot, side_key, idx)
  if not slot or idx < 2 or idx > 3 then return false end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  local v = side.verts[idx]
  if v.locked or not v.path then return false end
  v.path = nil
  v.name = nil
  v.vol = 1.0
  local b = side.blend
  b[idx] = 0.0
  b[1], b[2], b[3] = seq_layer_clamp_bary(b[1], b[2], b[3])
  seq_layering_sync_linked(slot, side_key)
  return true
end

function seq_layering_copy_side_to_other(slot, from_key)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local to_key = (from_key == "transient") and "sustain" or "transient"
  seq_layering_copy_side(slot.layers[to_key], slot.layers[from_key])
  return true
end

function seq_layering_swap_sides(slot)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  slot.layers.transient, slot.layers.sustain = slot.layers.sustain, slot.layers.transient
  return true
end

function seq_layering_mix_fingerprint(slot)
  seq_normalize_slot_layers(slot)
  local bits = { tostring(slot.id or 0), slot.layers.linked and "1" or "0" }
  for _, side_key in ipairs({ "transient", "sustain" }) do
    local side = slot.layers[side_key]
    bits[#bits + 1] = string.format("%.3f,%.3f,%.3f", side.blend[1] or 0, side.blend[2] or 0, side.blend[3] or 0)
    for i = 1, 3 do
      local v = side.verts[i]
      bits[#bits + 1] = (v and v.path) or ""
      bits[#bits + 1] = string.format("%.3f", seq_layer_vert_vol(v))
    end
  end
  bits[#bits + 1] = slot.sample_path or ""
  bits[#bits + 1] = string.format("%.3f", slot.layers.bias or 0.0)
  return table.concat(bits, "|")
end

-- Peaks of the layered mix (normalized to 1), its duration, and "ribbon"
-- segments { u0, u1, color } (fractions of the width) naming the corner sample
-- that dominates each stretch. Cached until the layering changes.
function seq_layering_mix_peaks(slot, width)
  width = math.max(48, math.min(320, math.floor(width or 200)))
  local fp = seq_layering_mix_fingerprint(slot) .. "#" .. tostring(width)
  local cache = seq_layer_mix_wave_cache
  if cache and cache.fp == fp and cache.peaks then
    return cache.peaks, cache.dur, cache.ribbon
  end
  local pieces = seq_layering_build_pieces(slot)
  local orig = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if #pieces == 0 then
    if not orig then
      return nil, nil, nil
    end
    local peaks, dur = seq_env_get_wave_peaks(orig, width)
    seq_layer_mix_wave_cache = { fp = fp, peaks = peaks, dur = dur }
    return peaks, dur, nil
  end
  local dur = 0.0
  local resolved = {}
  for i = 1, #pieces do
    local p = pieces[i]
    local sample = p.sample or find_sample_by_path(p.path)
    local pdur = seq_sample_source_length_sec(p.path, sample)
        or (sample and tonumber(sample.duration)) or 0.2
    local startoffs = p.startoffs or 0.0
    local t_off = p.time_offset_sec or 0.0
    local len = p.length_sec
    if not len or len <= 0 then
      len = math.max(0.01, pdur - startoffs)
    end
    local end_t = t_off + len
    if end_t > dur then dur = end_t end
    resolved[#resolved + 1] = {
      sample = sample,
      startoffs = startoffs,
      t_off = t_off,
      len = len,
      weight = p.weight or 1.0,
      pdur = pdur,
    }
  end
  if dur <= 0.001 then dur = 0.2 end
  local out, best, best_v = {}, {}, {}
  for i = 1, width do
    out[i] = 0.0
    best_v[i] = 0.0
  end
  for i = 1, #resolved do
    local rp = resolved[i]
    if rp.sample then
      local peaks, pd = seq_env_get_wave_peaks(rp.sample, width)
      pd = pd or rp.pdur
      if peaks and pd and pd > 0 then
        local n = #peaks
        -- Only the bins this piece covers.
        local b0 = math.max(1, math.floor(rp.t_off / dur * width + 0.5))
        local b1 = math.min(width, math.ceil((rp.t_off + rp.len) / dur * width + 0.5))
        for b = b0, b1 do
          local t = ((b - 0.5) / width) * dur
          if t >= rp.t_off and t <= rp.t_off + rp.len then
            local src_t = rp.startoffs + (t - rp.t_off)
            local si = math.floor((src_t / pd) * n) + 1
            if si >= 1 and si <= n then
              local v = (peaks[si] or 0) * rp.weight
              out[b] = out[b] + v
              if v > best_v[b] then
                best_v[b] = v
                best[b] = i
              end
            end
          end
        end
      end
    end
  end
  local max_v = 0.0
  for i = 1, width do
    if out[i] > max_v then max_v = out[i] end
  end
  if max_v > 0.0001 then
    for i = 1, width do out[i] = out[i] / max_v end
  end
  -- Merge runs of the same dominant piece; quiet bins extend the current run.
  local ribbon = {}
  local cur, run0 = nil, 1
  for b = 1, width + 1 do
    local who = best[b]
    if b <= width and (not who or best_v[b] < 0.02 * max_v) then
      who = cur
    end
    if who ~= cur or b > width then
      if cur then
        local rs = resolved[cur].sample
        ribbon[#ribbon + 1] = {
          u0 = (run0 - 1) / width,
          u1 = (b - 1) / width,
          color = get_sample_dot_color(rs),
        }
      end
      cur, run0 = who, b
    end
  end
  seq_layer_mix_wave_cache = { fp = fp, peaks = out, dur = dur, ribbon = ribbon }
  return out, dur, ribbon
end

function seq_layering_start_mix_voice(v, into)
  if not v or not v.path or v.started then
    return
  end
  local src = r.PCM_Source_CreateFromFile(v.path)
  if not src then
    return
  end
  local vol = (state.preview_volume or 1.0) * (v.volume or 1.0)
  local pos = (v.startoffs or 0.0) + (into or 0.0)
  if r.CF_CreatePreview and r.CF_Preview_SetValue and r.CF_Preview_Play then
    local obj = r.CF_CreatePreview(src)
    if obj then
      r.CF_Preview_SetValue(obj, "D_VOLUME", vol)
      if pos > 0 then
        r.CF_Preview_SetValue(obj, "D_POSITION", pos)
      end
      if r.CF_Preview_Play(obj) then
        v.started = true
        v.obj = obj
        v.src = src
        return
      end
    end
  elseif r.Xen_StartSourcePreview then
    local preview_id = r.Xen_StartSourcePreview(src, vol, false)
    if preview_id and preview_id ~= 0 then
      v.started = true
      v.xen_id = preview_id
      v.src = src
      v.engine_owned = true
      return
    end
  end
  if r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, src)
  end
end

function seq_layering_stop_mix_voice(v)
  if not v or not v.started then
    return
  end
  if v.obj and r.CF_Preview_Stop then
    pcall(r.CF_Preview_Stop, v.obj)
  elseif v.xen_id and r.Xen_StopSourcePreview then
    pcall(r.Xen_StopSourcePreview, v.xen_id)
  end
  if v.src and not v.engine_owned and r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, v.src)
  end
  v.obj = nil
  v.xen_id = nil
  v.src = nil
  v.started = false
end

function seq_layering_update_mix_preview()
  local mix = seq_layer_mix_preview
  if not mix then
    return
  end
  local now = r.time_precise()
  local elapsed = now - (mix.t0 or now)
  if elapsed >= (mix.duration or 0) + 0.04 then
    stop_preview()
    return
  end
  for i = 1, #(mix.voices or {}) do
    local v = mix.voices[i]
    if v and not v.started and elapsed >= (v.start_at or 0) - 0.001 then
      seq_layering_start_mix_voice(v, math.max(0.0, elapsed - (v.start_at or 0)))
    end
    if v and v.started and v.stop_at and elapsed >= v.stop_at then
      seq_layering_stop_mix_voice(v)
    end
  end
end

function seq_layering_preview_original(slot, start_time)
  if not slot then return end
  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if not sample then return end
  state.seq_layering_ab = "original"
  preview_sample(sample, start_time)
end

function seq_layering_preview_layered(slot, start_time)
  if not slot then return end
  start_time = math.max(0.0, start_time or 0.0)
  state.seq_layering_ab = "layered"
  local pieces = seq_layering_build_pieces(slot)
  local _, dur = seq_layering_mix_peaks(slot, 200)
  dur = dur or 0.2
  if #pieces == 0 then
    seq_layering_preview_original(slot, start_time)
    state.seq_layering_ab = "layered"
    return
  end
  stop_preview()
  local voices = {}
  for i = 1, #pieces do
    local piece = pieces[i]
    local t_off = piece.time_offset_sec or 0.0
    local len = piece.length_sec
    voices[#voices + 1] = {
      path = piece.path,
      startoffs = piece.startoffs or 0.0,
      volume = piece.weight or 1.0,
      start_at = t_off,
      stop_at = (len and len > 0) and (t_off + len) or nil,
      started = false,
    }
  end
  seq_layer_mix_preview = {
    slot_id = slot.id,
    t0 = r.time_precise() - start_time,
    duration = dur,
    voices = voices,
  }
  preview_sample_obj = {
    path = "layering-mix:" .. tostring(slot.id),
    name = (slot.name or "Track") .. " (layered)",
    duration = dur,
  }
  preview_proc = true
  preview_start_time = seq_layer_mix_preview.t0
  state.preview_position = start_time
  state.preview_paused = false
  seq_layering_update_mix_preview()
end

function seq_layering_ab_playing(slot, kind)
  if not slot then return false end
  if kind == "layered" then
    return seq_layer_mix_preview ~= nil and seq_layer_mix_preview.slot_id == slot.id
  end
  return seq_layer_mix_preview == nil
      and preview_sample_obj
      and slot.sample_path
      and preview_sample_obj.path == slot.sample_path
end

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
    local a = tonumber(b[1]) or 0
    local bb = tonumber(b[2]) or 0
    local c = tonumber(b[3]) or 0
    a, bb, c = seq_layer_clamp_bary(a, bb, c)
    side.blend = { a, bb, c }
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

function seq_layering_piece_times(sample, side_key, slot)
  local dur = seq_sample_source_length_sec(sample and sample.path, sample)
      or (sample and tonumber(sample.duration)) or 0.2
  if dur <= 0.001 then dur = 0.2 end
  local onset = (sample and type(sample.onset) == "number" and sample.onset > 0) and sample.onset or 0.0
  local trans = (sample and type(sample.transient_end) == "number" and sample.transient_end > 0)
      and sample.transient_end or math.min(0.024, dur * 0.18)
  trans = math.max(onset + 0.003, math.min(trans, dur * 0.9))
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

function seq_layering_split_sec(slot)
  local sample = slot and find_sample_by_path(slot.sample_path)
  if not sample then
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
  local _, tlen = seq_layering_piece_times(sample, "transient", slot)
  return math.max(0.004, tlen or 0.02)
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

function seq_layering_draw_lock(dl, x, y, w, h, locked, hovered)
  local col = locked and 0xE8C070FF or (hovered and 0xFFFFFFFF or UI_THEME.text_dim)
  local cx = x + w * 0.5
  local body_y = y + h * 0.48
  local body_h = h * 0.38
  local body_w = w * 0.46
  r.ImGui_DrawList_AddRectFilled(dl, cx - body_w * 0.5, body_y, cx + body_w * 0.5, body_y + body_h, col, 1.5)
  local shackle_r = w * 0.16
  local shackle_y = body_y
  if locked then
    r.ImGui_DrawList_AddCircle(dl, cx, shackle_y, shackle_r, col, 10, 1.4)
  else
    r.ImGui_DrawList_AddCircle(dl, cx + w * 0.08, shackle_y, shackle_r, col, 10, 1.4)
  end
end

function seq_layering_icon_button(id, dl, x, y, w, h, kind, active)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg = active and UI_THEME.accent_fill or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)
  local edge = hovered and UI_THEME.accent_hvr or (active and UI_THEME.accent or UI_THEME.border)
  ui_draw_panel(dl, x, y, x + w, y + h, 6.0, bg, edge, hovered, pressed)
  if kind == "dice" then
    ui_button_draw_icon(dl, "dice5", x + w * 0.5, y + h * 0.5 + (pressed and 1.0 or 0.0), math.min(w, h) * 0.9, hovered and 0xFFFFFFFF or UI_THEME.text)
  else
    seq_layering_draw_lock(dl, x, y + (pressed and 1.0 or 0.0), w, h, active, hovered)
  end
  return clicked, hovered
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

function seq_layering_mix_peaks(slot, width)
  width = math.max(48, math.min(320, math.floor(width or 200)))
  local fp = seq_layering_mix_fingerprint(slot) .. "#" .. tostring(width)
  local cache = seq_layer_mix_wave_cache
  if cache and cache.fp == fp and cache.peaks then
    return cache.peaks, cache.dur
  end
  local pieces = seq_layering_build_pieces(slot)
  local orig = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if #pieces == 0 then
    if not orig then
      return nil, nil
    end
    local peaks, dur = seq_env_get_wave_peaks(orig, width)
    seq_layer_mix_wave_cache = { fp = fp, peaks = peaks, dur = dur }
    return peaks, dur
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
  local out = {}
  for i = 1, width do out[i] = 0.0 end
  for i = 1, #resolved do
    local rp = resolved[i]
    if rp.sample then
      local peaks, pd = seq_env_get_wave_peaks(rp.sample, width)
      pd = pd or rp.pdur
      if peaks and pd and pd > 0 then
        local n = #peaks
        for b = 1, width do
          local t = ((b - 0.5) / width) * dur
          if t >= rp.t_off and t <= rp.t_off + rp.len then
            local src_t = rp.startoffs + (t - rp.t_off)
            local si = math.floor((src_t / pd) * n) + 1
            if si >= 1 and si <= n then
              out[b] = out[b] + (peaks[si] or 0) * rp.weight
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
  seq_layer_mix_wave_cache = { fp = fp, peaks = out, dur = dur }
  return out, dur
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

function seq_layering_draw_wave_pane(dl, slot, x, y, w, h, kind, hover_side)
  local selected = state.seq_layering_ab == kind
  local playing = seq_layering_ab_playing(slot, kind)
  local using = seq_layering_output(slot) == kind
  local hovered_btn = false
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##seq_layer_ab_" .. kind .. "_" .. tostring(slot.id), w, h)
  hovered_btn = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)

  local bg = (selected or playing or using) and UI_THEME.accent_fill or (hovered_btn and UI_THEME.surface_hvr or UI_THEME.bg_panel)
  local edge = (selected or playing or using) and UI_THEME.accent or (hovered_btn and UI_THEME.accent_hvr or UI_THEME.border)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 4.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, edge, 4.0, 0, (selected or playing or using) and 1.6 or 1.0)

  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  local ix, iy, iw, ih = x + 6, y + 16, w - 12, h - 22
  local peaks, dur = nil, nil
  if kind == "layered" then
    peaks, dur = seq_layering_mix_peaks(slot, math.floor(iw))
  elseif sample then
    peaks, dur = seq_env_get_wave_peaks(sample, math.floor(iw))
  end
  if peaks and iw > 4 and ih > 4 then
    seq_draw_env_waveform(dl, ix, iy, iw, ih, peaks, nil, nil, dur)
  elseif not sample then
    r.ImGui_DrawList_AddText(dl, x + 10, y + h * 0.5 - 7, UI_THEME.text_mute, "Assign a sample to this track")
  end

  dur = dur or (sample and tonumber(sample.duration)) or 0
  local label = (kind == "original") and "Original" or "Layered"
  local label_col = (selected or playing or using) and 0xFFFFFFFF or UI_THEME.text
  r.ImGui_DrawList_AddText(dl, x + 8, y + 2, label_col, label)
  if playing then
    ui_button_draw_icon(dl, "play", x + w - 14, y + 10, 14, 0x7CFF4AFF)
  end

  local btn_w, btn_h = 52, 16
  local play_pad = playing and 16 or 0
  local btn_x = x + w - 6 - btn_w - play_pad
  local btn_y = y + 2
  local mx, my = r.ImGui_GetMousePos(ctx)
  mx, my = tonumber(mx) or -1, tonumber(my) or -1
  local over_use = mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h
  r.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
  local use_clicked = draw_ui_button(
    "seq_layer_use_" .. kind .. "_" .. tostring(slot.id),
    using and "USING" or "USE",
    btn_w, btn_h,
    { compact = true, selected = using, style = using and "accent" or "default" }
  )
  local use_hovered = over_use or r.ImGui_IsItemHovered(ctx)
  if use_hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, using
      and "This is the track output"
      or "Use this as the track output")
  end
  if (use_clicked or (over_use and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)))
      and not using then
    seq_layering_set_output(slot, kind)
  end

  if kind == "original" and sample and dur > 0 and not (slot.layers and slot.layers.linked) then
    local onset = (type(sample.onset) == "number" and sample.onset > 0) and sample.onset or 0.0
    local trans = seq_layering_apply_bias(
      (type(sample.transient_end) == "number" and sample.transient_end > 0)
        and sample.transient_end or math.min(0.024, dur * 0.18),
      onset, dur, seq_layering_get_bias(slot)
    )
    local sustain_end = sample_map_duration(sample)
    if sustain_end <= 0 then sustain_end = dur end
    local function t2x(t)
      return ix + (math.max(0.0, math.min(dur, t)) / dur) * iw
    end
    if trans then
      local ox, tx, sx = t2x(onset), t2x(trans), t2x(sustain_end)
      local t_alpha = (hover_side == "transient") and 0xFF6B3C55 or 0xFF6B3C33
      local s_alpha = (hover_side == "sustain") and 0x4A9CFF44 or 0x4A9CFF28
      if tx > ox + 0.5 then
        r.ImGui_DrawList_AddRectFilled(dl, ox, iy, tx, iy + ih, t_alpha, 0)
      end
      if sx > tx + 0.5 then
        r.ImGui_DrawList_AddRectFilled(dl, tx, iy, sx, iy + ih, s_alpha, 0)
      end
      r.ImGui_DrawList_AddLine(dl, tx, iy, tx, iy + ih, 0x7CFF4AFF, 1.6)
    end
  end

  if playing and dur > 0 then
    local pos = get_preview_position() or state.preview_position or 0.0
    local playhead_x = ix + (math.max(0.0, math.min(dur, pos)) / dur) * iw
    r.ImGui_DrawList_AddLine(dl, playhead_x, y + 1, playhead_x, y + h - 1, 0xFFFF88FF, 1.6)
    r.ImGui_DrawList_AddCircleFilled(dl, playhead_x, y + 4, 3.0, 0xFFFF88FF, 10)
  end

  if hovered_btn and not use_hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, kind == "original"
      and "Click to play · Drag to drop original sample"
      or "Click to play · Drag to drop layered mix")
  end
  local drag_sample = nil
  if kind == "original" then
    drag_sample = sample
  elseif slot.sample_path then
    drag_sample = seq_layering_drag_sample(slot)
  end
  if drag_sample and not use_hovered
      and waveform_drag_should_start(hovered_btn) then
    begin_waveform_sample_drag(drag_sample)
  end
  if drag_sample and sample_is_waveform_drag_source(drag_sample) then
    draw_waveform_drag_source_cue(dl, x, y, w, h)
  end
  if clicked and not use_hovered and not state.pending_waveform_drop then
    if kind == "original" then
      seq_layering_preview_original(slot)
    else
      seq_layering_preview_layered(slot, 0)
    end
  end
end

function seq_layering_draw_waveforms(dl, slot, x, y, w, h, hover_side)
  local gap = 6.0
  local pane_h = (h - gap) * 0.5
  seq_layering_draw_wave_pane(dl, slot, x, y, w, pane_h, "original", hover_side)
  seq_layering_draw_wave_pane(dl, slot, x, y + pane_h + gap, w, pane_h, "layered", hover_side)
end

SEQ_LAYER_WAVE_H = 148.0
SEQ_LAYER_WAVE_GAP = 0.0
SEQ_LAYER_LINK_W = 44.0
SEQ_LAYER_PAD_TOP = 36.0
SEQ_LAYER_PAD_BOT = 36.0
SEQ_LAYER_PAD_SIDE = 72.0
SEQ_LAYER_VERT_DROP_R = 24.0

function seq_layering_tri_geom(x, y, w, h)
  local pad_top, pad_bot, pad_side = SEQ_LAYER_PAD_TOP, SEQ_LAYER_PAD_BOT, SEQ_LAYER_PAD_SIDE
  local avail_w = math.max(72.0, w - pad_side * 2.0)
  local avail_h = math.max(72.0, h - pad_top - pad_bot)
  local side = math.min(avail_w, avail_h * 2.0 / math.sqrt(3.0))
  local tri_h = side * (math.sqrt(3.0) * 0.5)
  local ax = x + w * 0.5
  local ay = y + pad_top
  local bx = ax - side * 0.5
  local by = ay + tri_h
  local cx = ax + side * 0.5
  local cy = by
  return ax, ay, bx, by, cx, cy, side, tri_h
end

function seq_layering_ideal_content_h(content_w)
  local col_w = math.max(160.0, (content_w - SEQ_LAYER_LINK_W) * 0.5)
  local avail_w = math.max(72.0, col_w - SEQ_LAYER_PAD_SIDE * 2.0)
  local tri_h = avail_w * (math.sqrt(3.0) * 0.5)
  return SEQ_LAYER_WAVE_H + SEQ_LAYER_WAVE_GAP + SEQ_LAYER_PAD_TOP + tri_h + SEQ_LAYER_PAD_BOT
end

function seq_layering_rounded_tri_points(ax, ay, bx, by, cx, cy, radius)
  local V = { { ax, ay }, { bx, by }, { cx, cy } }
  local pts = {}
  local steps = 7
  for i = 1, 3 do
    local p0 = V[i == 1 and 3 or (i - 1)]
    local p1 = V[i]
    local p2 = V[i == 3 and 1 or (i + 1)]
    local e1x, e1y = p0[1] - p1[1], p0[2] - p1[2]
    local e2x, e2y = p2[1] - p1[1], p2[2] - p1[2]
    local l1 = math.sqrt(e1x * e1x + e1y * e1y)
    local l2 = math.sqrt(e2x * e2x + e2y * e2y)
    if l1 < 1e-4 or l2 < 1e-4 then
      pts[#pts + 1] = { p1[1], p1[2] }
    else
      e1x, e1y = e1x / l1, e1y / l1
      e2x, e2y = e2x / l2, e2y / l2
      local dot = math.max(-1.0, math.min(1.0, e1x * e2x + e1y * e2y))
      local ang = math.acos(dot)
      local d = radius / math.max(0.18, math.tan(ang * 0.5))
      d = math.min(d, l1 * 0.42, l2 * 0.42)
      local a1x, a1y = p1[1] + e1x * d, p1[2] + e1y * d
      local a2x, a2y = p1[1] + e2x * d, p1[2] + e2y * d
      local bisx, bisy = e1x + e2x, e1y + e2y
      local bl = math.sqrt(bisx * bisx + bisy * bisy)
      local sin_h = math.sin(ang * 0.5)
      local clen = (sin_h > 1e-4) and (radius / sin_h) or radius
      local ocx = p1[1] + (bisx / bl) * clen
      local ocy = p1[2] + (bisy / bl) * clen
      local t0 = math.atan2(a1y - ocy, a1x - ocx)
      local t1 = math.atan2(a2y - ocy, a2x - ocx)
      local sweep = t1 - t0
      while sweep > math.pi do sweep = sweep - 2.0 * math.pi end
      while sweep < -math.pi do sweep = sweep + 2.0 * math.pi end
      local mid = t0 + sweep * 0.5
      local mx = ocx + math.cos(mid) * radius
      local my = ocy + math.sin(mid) * radius
      if (mx - p1[1]) * (mx - p1[1]) + (my - p1[2]) * (my - p1[2]) < (radius * 0.55) * (radius * 0.55) then
        if sweep > 0 then sweep = sweep - 2.0 * math.pi else sweep = sweep + 2.0 * math.pi end
      end
      for s = 0, steps do
        local t = t0 + sweep * (s / steps)
        pts[#pts + 1] = { ocx + math.cos(t) * radius, ocy + math.sin(t) * radius }
      end
    end
  end
  return pts
end

function seq_layering_draw_poly(dl, pts, fill, stroke, stroke_w)
  if not pts or #pts < 3 or not dl then return end
  if fill and r.ImGui_DrawList_PathLineTo and r.ImGui_DrawList_PathFillConvex then
    pcall(function()
      if r.ImGui_DrawList_PathClear then r.ImGui_DrawList_PathClear(dl) end
      for i = 1, #pts do
        local p = pts[i]
        if p and p[1] and p[2] then
          r.ImGui_DrawList_PathLineTo(dl, p[1], p[2])
        end
      end
      r.ImGui_DrawList_PathFillConvex(dl, fill)
    end)
  end
  if stroke and stroke_w and stroke_w > 0 then
    local n = #pts
    for i = 1, n do
      local a, b = pts[i], pts[i == n and 1 or (i + 1)]
      if a and b then
        r.ImGui_DrawList_AddLine(dl, a[1], a[2], b[1], b[2], stroke, stroke_w)
      end
    end
  end
end

function seq_layering_expand_tri(ax, ay, bx, by, cx, cy, amt)
  local mx = (ax + bx + cx) / 3.0
  local my = (ay + by + cy) / 3.0
  local function push(px, py)
    local dx, dy = px - mx, py - my
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1e-4 then return px, py end
    return px + dx / l * amt, py + dy / l * amt
  end
  local ax2, ay2 = push(ax, ay)
  local bx2, by2 = push(bx, by)
  local cx2, cy2 = push(cx, cy)
  return ax2, ay2, bx2, by2, cx2, cy2
end

function seq_layer_col_alpha(color, alpha_value)
  color = tonumber(color) or 0x1EFF5EFF
  alpha_value = tonumber(alpha_value) or 1.0
  local rr = math.floor((color / 16777216) % 256)
  local gg = math.floor((color / 65536) % 256)
  local bb = math.floor((color / 256) % 256)
  local aa = math.max(0, math.min(255, math.floor(alpha_value * 255)))
  return rr * 16777216 + gg * 65536 + bb * 256 + aa
end

function seq_layering_draw_polished_tri(dl, ax, ay, bx, by, cx, cy, hot)
  if not dl then return end
  ax, ay = tonumber(ax), tonumber(ay)
  bx, by = tonumber(bx), tonumber(by)
  cx, cy = tonumber(cx), tonumber(cy)
  if not (ax and ay and bx and by and cx and cy) then return end
  local accent = (hot and UI_THEME.accent_hvr) or UI_THEME.accent or 0x1EFF5EFF
  local fill = UI_THEME.accent_fill or 0x0E2A18FF
  r.ImGui_DrawList_AddTriangleFilled(dl, ax, ay, bx, by, cx, cy, fill)
  local outlined = pcall(function()
    local radius = 14.0
    for i = 4, 1, -1 do
      local grow = i * 2.4
      local ea, ey, eb, eby, ec, ecy = seq_layering_expand_tri(ax, ay, bx, by, cx, cy, grow)
      local pts = seq_layering_rounded_tri_points(ea, ey, eb, eby, ec, ecy, radius + i)
      local alpha = hot and (0.10 * (5 - i)) or (0.055 * (5 - i))
      seq_layering_draw_poly(dl, pts, nil, seq_layer_col_alpha(accent, alpha), 3.0 + i * 0.8)
    end
    local pts = seq_layering_rounded_tri_points(ax, ay, bx, by, cx, cy, radius)
    seq_layering_draw_poly(dl, pts, fill, nil, 0)
    seq_layering_draw_poly(dl, pts, nil, seq_layer_col_alpha(accent, 0.95), 2.6)
  end)
  if not outlined then
    r.ImGui_DrawList_AddLine(dl, ax, ay, bx, by, accent, 2.2)
    r.ImGui_DrawList_AddLine(dl, bx, by, cx, cy, accent, 2.2)
    r.ImGui_DrawList_AddLine(dl, cx, cy, ax, ay, accent, 2.2)
  end
end

function seq_layering_draw_pct_badge(dl, cx, cy, pct)
  local text = string.format("%d%%", pct)
  local tw = select(1, r.ImGui_CalcTextSize(ctx, text)) or 24
  local w, h = tw + 10, 16
  local x0, y0 = cx - w * 0.5, cy - h * 0.5
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, 0x0C100EFF, 3.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, 0x1EFF5E55, 3.0, 0, 1.0)
  r.ImGui_DrawList_AddText(dl, x0 + 5, y0 + 1, 0xE8EEEAFF, text)
end

function seq_layering_vol_knob(id, dl, x, y, size, vert)
  if type(vert) ~= "table" then
    return false, false
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local vol = seq_layer_vert_vol(vert)
  local changed = false
  local fine = seq_fine_drag_down()
  if active then
    local _, dy = r.ImGui_GetMouseDelta(ctx)
    if dy and dy ~= 0.0 then
      local step = ((SEQ_LAYER_VOL_MAX or 4.0) / 180.0) * (fine and SEQ_FINE_DRAG_SCALE or 1.0)
      vol = seq_layer_vert_vol({ vol = vol + (-dy) * step })
      vert.vol = vol
      changed = true
    end
  end
  if r.ImGui_IsItemClicked(ctx, 0) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    vert.vol = 1.0
    vol = 1.0
    changed = true
  end
  local cx, cy = x + size * 0.5, y + size * 0.5 + (active and 1.0 or 0.0)
  local radius = size * 0.46
  local fill = active and UI_THEME.accent_fill_h or (hovered and UI_THEME.surface_hvr or UI_THEME.surface)
  local edge = (hovered or active) and UI_THEME.accent or UI_THEME.border
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, fill, 18)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, radius, edge, 18, hovered and 1.5 or 1.2)
  local amin, amax = math.pi * 0.75, math.pi * 2.25
  local t = vol / (SEQ_LAYER_VOL_MAX or 4.0)
  local ang = amin + (amax - amin) * t
  local ar = radius - 2.6
  local prevx, prevy
  for i = 0, 12 do
    local a = amin + (ang - amin) * (i / 12)
    local px = cx + math.cos(a) * ar
    local py = cy + math.sin(a) * ar
    if prevx then
      r.ImGui_DrawList_AddLine(dl, prevx, prevy, px, py, UI_THEME.accent, 1.6)
    end
    prevx, prevy = px, py
  end
  if hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, string.format("Sample volume  %.0f%%\nDrag to adjust, double-click to reset", vol * 100.0))
  end
  return changed, hovered
end

function seq_layering_vert_can_drop(hit)
  if not hit then
    return false
  end
  return (not hit.locked) or (hit.idx == 1)
end

function seq_layering_store_vert_hit(side_key, idx, vx, vy, locked)
  state.seq_layering_vert_hits = state.seq_layering_vert_hits or {}
  state.seq_layering_vert_hits[#state.seq_layering_vert_hits + 1] = {
    side = side_key,
    idx = idx,
    x = vx,
    y = vy,
    locked = locked == true,
  }
end

function seq_layering_hit_vert(mx, my)
  local hits = state.seq_layering_vert_hits
  mx, my = tonumber(mx), tonumber(my)
  if not hits or not mx or not my then
    return nil
  end
  local rad = SEQ_LAYER_VERT_DROP_R or 24.0
  local r2 = rad * rad
  local best, best_d = nil, r2
  for i = 1, #hits do
    local h = hits[i]
    if seq_layering_vert_can_drop(h) then
      local dx, dy = mx - h.x, my - h.y
      local d = dx * dx + dy * dy
      if d <= best_d then
        best_d = d
        best = h
      end
    end
  end
  return best
end

function seq_layering_pointer_over_window()
  local rect = state.seq_layering_rect
  if not rect then
    return false
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  mx, my = tonumber(mx), tonumber(my)
  if not mx or not my then
    return false
  end
  return mx >= (rect.x or 0) and my >= (rect.y or 0)
    and mx <= (rect.x or 0) + (rect.w or 0)
    and my <= (rect.y or 0) + (rect.h or 0)
end

function seq_layering_resolve_drop_vert()
  if not sample_drag_active() then
    state.seq_layering_drop_vert = nil
    return nil
  end
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hit = seq_layering_hit_vert(mx, my)
  if hit then
    state.seq_layering_drop_vert = { side = hit.side, idx = hit.idx }
    return hit
  end
  state.seq_layering_drop_vert = nil
  return nil
end

function seq_layering_draw_vert_drop_cues(dl)
  if not dl or not sample_drag_active() then
    return
  end
  local hits = state.seq_layering_vert_hits
  if not hits then
    return
  end
  local drop = state.seq_layering_drop_vert
  local pulse = (drag_pulse and drag_pulse()) or 0.5
  for i = 1, #hits do
    local h = hits[i]
    if seq_layering_vert_can_drop(h) then
      local is_hot = drop and drop.side == h.side and drop.idx == h.idx
      if is_hot then
        r.ImGui_DrawList_AddCircleFilled(dl, h.x, h.y, 16.0, seq_layer_col_alpha(UI_THEME.accent, 0.32 + 0.22 * pulse), 20)
        r.ImGui_DrawList_AddCircle(dl, h.x, h.y, 16.0, 0x7CFF4AFF, 20, 2.4)
        r.ImGui_DrawList_AddCircle(dl, h.x, h.y, 21.0, seq_layer_col_alpha(UI_THEME.accent, 0.55), 20, 1.5)
      else
        r.ImGui_DrawList_AddCircle(dl, h.x, h.y, 13.0, seq_layer_col_alpha(UI_THEME.accent, 0.40 + 0.18 * pulse), 18, 1.6)
      end
    end
  end
end

function seq_layering_draw_triangle(dl, slot, side_key, x, y, w, h)
  seq_normalize_slot_layers(slot)
  local side = slot and slot.layers and slot.layers[side_key]
  if type(side) ~= "table" then
    side = seq_layer_default_side()
    if slot and type(slot.layers) == "table" then
      slot.layers[side_key] = side
    end
  end
  if type(side.verts) ~= "table" then
    side.verts = seq_layer_default_side().verts
  end
  if type(side.blend) ~= "table" then
    side.blend = { 1.0, 0.0, 0.0 }
  end
  x, y, w, h = tonumber(x) or 0, tonumber(y) or 0, tonumber(w) or 200, tonumber(h) or 200
  local ax, ay, bx, by, cx, cy = seq_layering_tri_geom(x, y, w, h)
  local hot = state.seq_layering_hover_side == side_key
  seq_layering_draw_polished_tri(dl, ax, ay, bx, by, cx, cy, hot)
  local side_label = (side_key == "transient") and "TRANSIENT" or "SUSTAIN"
  local slw = select(1, r.ImGui_CalcTextSize(ctx, side_label)) or 60
  local dice_sz = 18.0
  local label_x = x + (w - slw) * 0.5
  r.ImGui_SetCursorScreenPos(ctx, label_x - dice_sz - 5, y + 1)
  if draw_ui_button("seq_layer_global_" .. slot.id .. "_" .. side_key, nil, dice_sz, dice_sz, { icon = "dice5", style = "accent" }) then
    if seq_layering_randomize_side(slot, side_key) then
      save_config()
      seq_layering_sync_arrange(slot)
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Randomize all unlocked " .. side_key .. " samples")
  end
  r.ImGui_DrawList_AddText(dl, label_x, y + 3, UI_THEME.accent, side_label)

  local mx, my = r.ImGui_GetMousePos(ctx)
  local inside = false
  if mx and my then
    local rw, rv, ru = seq_layer_barycentric_raw(mx, my, ax, ay, bx, by, cx, cy)
    inside = rw >= -0.02 and rv >= -0.02 and ru >= -0.02
  end

  local px, py = seq_layer_point_from_bary(side.blend, ax, ay, bx, by, cx, cy)
  local mabx, maby = (ax + bx) * 0.5, (ay + by) * 0.5
  local mbcx, mbcy = (bx + cx) * 0.5, (by + cy) * 0.5
  local mcax, mcay = (cx + ax) * 0.5, (cy + ay) * 0.5
  local div = seq_layer_col_alpha(UI_THEME.accent, hot and 0.45 or 0.28)
  r.ImGui_DrawList_AddLine(dl, px, py, mabx, maby, div, 1.1)
  r.ImGui_DrawList_AddLine(dl, px, py, mbcx, mbcy, div, 1.1)
  r.ImGui_DrawList_AddLine(dl, px, py, mcax, mcay, div, 1.1)
  local hs = 7.5
  local hax, hay = px, py - hs * 0.72
  local hbx, hby = px - hs * 0.62, py + hs * 0.42
  local hcx, hcy = px + hs * 0.62, py + hs * 0.42
  r.ImGui_DrawList_AddTriangleFilled(dl, hax, hay, hbx, hby, hcx, hcy, UI_THEME.accent)
  r.ImGui_DrawList_AddLine(dl, hax, hay, hbx, hby, 0xE8FFEEFF, 1.2)
  r.ImGui_DrawList_AddLine(dl, hbx, hby, hcx, hcy, 0xE8FFEEFF, 1.2)
  r.ImGui_DrawList_AddLine(dl, hcx, hcy, hax, hay, 0xE8FFEEFF, 1.2)

  local verts_xy = { { ax, ay }, { bx, by }, { cx, cy } }
  local btn = 18.0
  local btn_gap = 3.0
  local changed = false
  local controls_hot = false

  for i = 1, 3 do
    local vx, vy = verts_xy[i][1], verts_xy[i][2]
    local vert = side.verts[i]
    if type(vert) ~= "table" then
      vert = { path = nil, name = nil, locked = (i == 1), vol = 1.0 }
      side.verts[i] = vert
    end
    local sample = vert.path and find_sample_by_path(vert.path) or nil
    local color = sample and get_sample_dot_color(sample) or 0x667788FF
    r.ImGui_DrawList_AddCircleFilled(dl, vx, vy, 6.5, color, 16)
    r.ImGui_DrawList_AddCircle(dl, vx, vy, 6.5, 0xE8FFEECC, 16, 1.3)

    local cluster_w = btn * 3 + btn_gap * 2
    local cluster_x, cluster_y
    if i == 1 then
      cluster_x = vx + 18
      cluster_y = vy - btn * 0.5
    elseif i == 2 then
      cluster_x = vx - cluster_w - 14
      cluster_y = vy + 10
    else
      cluster_x = vx + 14
      cluster_y = vy + 10
    end

    local dice_id = "##seq_layer_dice_" .. slot.id .. "_" .. side_key .. "_" .. i
    local lock_id = "##seq_layer_lock_" .. slot.id .. "_" .. side_key .. "_" .. i
    local vol_id = "##seq_layer_vol_" .. slot.id .. "_" .. side_key .. "_" .. i
    local dice_clicked, dice_hovered = seq_layering_icon_button(dice_id, dl, cluster_x, cluster_y, btn, btn, "dice", false)
    local lock_clicked, lock_hovered = seq_layering_icon_button(lock_id, dl, cluster_x + btn + btn_gap, cluster_y, btn, btn, "lock", vert.locked)
    local vol_changed, vol_hovered = seq_layering_vol_knob(vol_id, dl, cluster_x + (btn + btn_gap) * 2, cluster_y, btn, vert)
    if dice_clicked then
      if seq_layering_randomize_vert(slot, side_key, i) then
        changed = true
      end
    end
    if lock_clicked then
      vert.locked = not vert.locked
      seq_layering_sync_linked(slot, side_key)
      changed = true
    end
    if vol_changed then
      seq_layering_sync_linked(slot, side_key)
      state.seq_layering_vol_drag = true
    end
    if dice_hovered or lock_hovered or vol_hovered then
      controls_hot = true
    end
    if dice_hovered and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, vert.locked and "Unlock to randomize" or "Randomize this sample")
    elseif lock_hovered and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, vert.locked and "Unlock this sample" or "Lock this sample")
    end

    local name = "empty"
    if vert.path and vert.path ~= "" then
      name = basename(vert.path)
    elseif vert.name and vert.name ~= "" then
      name = tostring(vert.name)
    end
    name = name:upper()
    if #name > 18 then
      name = name:sub(1, 14) .. "..."
    end
    local nw = select(1, r.ImGui_CalcTextSize(ctx, name)) or 40
    local nx, ny
    if i == 1 then
      nx = vx - 12 - nw
      ny = vy - 7
    else
      nx = cluster_x
      ny = cluster_y + btn + 2
    end
    r.ImGui_DrawList_AddText(dl, nx, ny, sample and 0xF4F7FCFF or UI_THEME.text_mute, name)

    local pct = math.floor(((side.blend[i] or 0) * 100) + 0.5)
    local ptx, pty
    if i == 1 then
      ptx, pty = vx, vy + 20
    elseif i == 2 then
      ptx, pty = vx + 20, vy - 14
    else
      ptx, pty = vx - 20, vy - 14
    end
    seq_layering_draw_pct_badge(dl, ptx, pty, pct)

    -- Vertex hit for preview. Sample drops use screen-space hit tests so they
    -- still work when the map (or another window) has captured the mouse.
    seq_layering_store_vert_hit(side_key, i, vx, vy, vert.locked == true)
    r.ImGui_SetCursorScreenPos(ctx, vx - 14, vy - 14)
    r.ImGui_InvisibleButton(ctx, "##seq_layer_vert_" .. slot.id .. "_" .. side_key .. "_" .. i, 28, 28)
    if r.ImGui_IsItemHovered(ctx) then
      controls_hot = true
    end
    if r.ImGui_IsItemClicked(ctx, 0) and sample and not sample_drag_active() then
      state.seq_layering_ab = nil
      preview_sample(sample)
    end
  end

  local drag_id = side_key
  local dragging = state.seq_layering_drag and state.seq_layering_drag.side == drag_id
      and state.seq_layering_drag.slot_id == slot.id
  local win_hovered = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx) or true
  if dragging then
    if r.ImGui_IsMouseDown(ctx, 0) then
      local ba, bb, bc = seq_layer_barycentric(mx, my, ax, ay, bx, by, cx, cy)
      side.blend = { ba, bb, bc }
      seq_layering_sync_linked(slot, side_key)
    else
      state.seq_layering_drag = nil
      seq_layering_sync_linked(slot, side_key)
      changed = true
    end
  elseif win_hovered and inside and not controls_hot and not sample_drag_active() then
    state.seq_layering_hover_side = side_key
    if r.ImGui_IsMouseClicked(ctx, 0) then
      state.seq_layering_drag = { side = drag_id, slot_id = slot.id }
      local ba, bb, bc = seq_layer_barycentric(mx, my, ax, ay, bx, by, cx, cy)
      side.blend = { ba, bb, bc }
      seq_layering_sync_linked(slot, side_key)
    end
  end

  if state.seq_layering_vol_drag and not r.ImGui_IsMouseDown(ctx, 0) then
    state.seq_layering_vol_drag = nil
    changed = true
  end

  if changed then
    save_config()
    seq_layering_sync_arrange(slot)
  end
end

-- Drum-layering edits (blend drag, dice, lock, volume knobs, bias, link,
-- A/B output) mutate slot.layers directly. Open one undo session when a click
-- lands in the layering window (before any widget mutates) and close it once
-- all mouse buttons are released; unchanged sessions are dropped by end_seq_undo.
function seq_layering_undo_maybe_begin()
  if state.seq_layering_undo_owned or not state.seq_layering_hovered then
    return
  end
  if not r.ImGui_IsMouseClicked then
    return
  end
  if r.ImGui_IsMouseClicked(ctx, 0) or r.ImGui_IsMouseClicked(ctx, 1) then
    if seq_undo_own_begin("Edit drum layering") then
      state.seq_layering_undo_owned = true
    end
  end
end

function seq_layering_undo_maybe_end(force)
  if not state.seq_layering_undo_owned then
    return
  end
  if not force and r.ImGui_IsMouseDown
      and (r.ImGui_IsMouseDown(ctx, 0) or r.ImGui_IsMouseDown(ctx, 1)) then
    return
  end
  state.seq_layering_undo_owned = nil
  if seq_undo_is_open() then
    end_seq_undo()
  end
end

function render_seq_layering_window()
  seq_layering_undo_maybe_end()
  if not state.seq_layering_slot_id then
    state.seq_layering_hover_side = nil
    state.seq_layering_hovered = false
    state.seq_layering_rect = nil
    state.seq_layering_vert_hits = nil
    state.seq_layering_drop_vert = nil
    return
  end
  local slot = find_seq_track_by_id(state.seq_layering_slot_id)
  if not slot then
    state.seq_layering_slot_id = nil
    state.seq_layering_vert_hits = nil
    state.seq_layering_drop_vert = nil
    return
  end
  seq_layering_seed_from_track(slot)

  local stored_w = tonumber(state.seq_layering_win_w) or 760
  stored_w = math.max(620, math.min(1200, stored_w))
  local ideal_h = seq_layering_ideal_content_h(math.max(400, stored_w - 20)) + 36
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 620.0, 360.0, 1400.0, 1200.0)
  end
  if r.ImGui_Cond_Always then
    r.ImGui_SetNextWindowSize(ctx, stored_w, ideal_h, r.ImGui_Cond_Always())
  else
    r.ImGui_SetNextWindowSize(ctx, stored_w, ideal_h, r.ImGui_Cond_FirstUseEver())
  end

  local title = "Drum Layering — " .. (slot.name or "Track")
  local flags = 0
  if r.ImGui_WindowFlags_NoCollapse then
    flags = flags | r.ImGui_WindowFlags_NoCollapse()
  end
  if r.ImGui_WindowFlags_NoDocking then
    flags = flags | r.ImGui_WindowFlags_NoDocking()
  end
  if r.ImGui_SetNextWindowCollapsed then
    r.ImGui_SetNextWindowCollapsed(ctx, false, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end
  local began_ok, visible, open = pcall(r.ImGui_Begin, ctx, title .. "###seq_layering_window", true, flags)
  if not began_ok then
    if log then log("Drum layering Begin failed: " .. tostring(visible)) end
    return
  end
  if open == false then
    state.seq_layering_slot_id = nil
    state.seq_layering_drag = nil
    state.seq_layering_hover_side = nil
    state.seq_layering_hovered = false
    state.seq_layering_rect = nil
  end

  if visible then
    if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize then
      local x, y = r.ImGui_GetWindowPos(ctx)
      local w, h = r.ImGui_GetWindowSize(ctx)
      state.seq_layering_rect = {
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        w = tonumber(w) or 0,
        h = tonumber(h) or 0,
      }
    end
    local hover_flags = 0
    if r.ImGui_HoveredFlags_RootAndChildWindows then
      hover_flags = r.ImGui_HoveredFlags_RootAndChildWindows()
    end
    state.seq_layering_hovered = r.ImGui_IsWindowHovered
        and r.ImGui_IsWindowHovered(ctx, hover_flags)
        or false
    seq_layering_undo_maybe_begin()
    local body_ok, body_err = pcall(seq_layering_render_body, slot)
    if not body_ok and log then
      log("Drum layering draw error: " .. tostring(body_err))
    end
    seq_layering_undo_maybe_end()
    pcall(r.ImGui_End, ctx)
  else
    state.seq_layering_hovered = false
  end
end

function seq_layering_draw_bias(dl, slot, x, y, w, h, linked)
  if not slot or not dl then return end
  seq_normalize_slot_layers(slot)
  local bias = slot.layers.bias or 0.0
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##seq_layer_bias_" .. tostring(slot.id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local disabled = linked == true

  if not disabled then
    if hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      slot.layers.bias = 0.0
      state.seq_layering_bias_drag = nil
      save_config()
      seq_layering_sync_arrange(slot, { force_rebuild = true })
    elseif active then
      local dx = select(1, r.ImGui_GetMouseDelta(ctx))
      if dx and dx ~= 0.0 then
        state.seq_layering_bias_drag = true
        -- Left shortens the transient; right lengthens it.
        bias = bias + dx / math.max(36.0, w * 0.85)
        if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
        slot.layers.bias = bias
      end
    elseif state.seq_layering_bias_drag and not (r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0)) then
      state.seq_layering_bias_drag = nil
      save_config()
      seq_layering_sync_arrange(slot, { force_rebuild = true })
    end
  elseif state.seq_layering_bias_drag then
    state.seq_layering_bias_drag = nil
  end

  local mid_x = x + w * 0.5
  local u = ((slot.layers.bias or 0.0) + 1.0) * 0.5
  local thumb_x = x + 4 + u * math.max(1.0, w - 8)
  local fill_col = disabled and 0x3A4A40FF or UI_THEME.accent
  local bg = (hovered or active) and not disabled and UI_THEME.surface_hvr or UI_THEME.surface
  local edge = (hovered or active) and not disabled and UI_THEME.accent or UI_THEME.border
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered and not disabled, active and not disabled)
  r.ImGui_DrawList_AddLine(dl, mid_x, y + 3, mid_x, y + h - 3, 0xFFFFFF28, 1.0)
  if thumb_x < mid_x then
    r.ImGui_DrawList_AddRectFilled(dl, thumb_x, y + 4, mid_x, y + h - 4, fill_col, 2.0)
  elseif thumb_x > mid_x then
    r.ImGui_DrawList_AddRectFilled(dl, mid_x, y + 4, thumb_x, y + h - 4, fill_col, 2.0)
  end
  r.ImGui_DrawList_AddRectFilled(dl, thumb_x - 3, y + 2, thumb_x + 3, y + h - 2, fill_col, 2.0)

  local label = "BIAS"
  local lw = select(1, r.ImGui_CalcTextSize(ctx, label)) or 22
  r.ImGui_DrawList_AddText(dl, x + (w - lw) * 0.5, y + h + 3,
    disabled and UI_THEME.text_mute or UI_THEME.text_dim, label)

  if hovered and r.ImGui_SetTooltip then
    if disabled then
      r.ImGui_SetTooltip(ctx, "Unlink to split transient / sustain")
    else
      local split = seq_layering_split_sec(slot)
      r.ImGui_SetTooltip(ctx, string.format(
        "Transient  %.0f ms\nLeft: shorter   Right: longer\nDouble-click to reset",
        (split or 0.0) * 1000.0
      ))
    end
  end
end

function seq_layering_render_body(slot)
  local prev_hover = state.seq_layering_hover_side
  state.seq_layering_hover_side = nil
  state.seq_layering_vert_hits = {}
  if not sample_drag_active() then
    state.seq_layering_drop_vert = nil
  end

  seq_normalize_slot_layers(slot)
  local linked = slot.layers and slot.layers.linked == true
  local dl = r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx)
  if not dl and r.ImGui_GetForegroundDrawList then
    dl = r.ImGui_GetForegroundDrawList(ctx)
  end
  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 700
  avail_w = tonumber(avail_w) or 700
  if avail_w < 200 then avail_w = 200 end
  if r.ImGui_GetWindowSize then
    local win_w = select(1, r.ImGui_GetWindowSize(ctx))
    win_w = tonumber(win_w)
    if win_w and win_w > 0 then
      state.seq_layering_win_w = win_w
    end
  end

  local wave_h = SEQ_LAYER_WAVE_H
  local col_w = (avail_w - SEQ_LAYER_LINK_W) * 0.5
  if col_w < 160 then col_w = 160 end
  local tri_h = select(8, seq_layering_tri_geom(0, 0, col_w, 800)) or 180
  local block_h = SEQ_LAYER_PAD_TOP + tri_h + SEQ_LAYER_PAD_BOT
  local wx, wy = 0, 0
  if r.ImGui_GetCursorScreenPos then
    wx, wy = r.ImGui_GetCursorScreenPos(ctx)
  end
  wx, wy = tonumber(wx) or 0, tonumber(wy) or 0
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_ItemSpacing then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
  end
  if dl then
    seq_layering_draw_waveforms(dl, slot, wx, wy, avail_w, wave_h, prev_hover)
  end
  r.ImGui_Dummy(ctx, avail_w, wave_h)

  local left_x, left_y = wx, wy + wave_h
  r.ImGui_Dummy(ctx, avail_w, block_h)
  if r.ImGui_PopStyleVar then
    r.ImGui_PopStyleVar(ctx, 1)
  end

  if dl then
    pcall(seq_layering_draw_triangle, dl, slot, "transient", left_x, left_y, col_w, block_h)
    pcall(seq_layering_draw_triangle, dl, slot, "sustain", left_x + col_w + SEQ_LAYER_LINK_W, left_y, col_w, block_h)
    if sample_drag_active() then
      seq_layering_resolve_drop_vert()
      seq_layering_draw_vert_drop_cues(dl)
    end
  end

  local link_sz = 28.0
  local bias_w, bias_h = 80.0, 18.0
  local link_x = left_x + col_w + (SEQ_LAYER_LINK_W - link_sz) * 0.5
  local cluster_h = link_sz + 22 + bias_h + 14
  local link_y = left_y + math.max(8.0, (block_h - cluster_h) * 0.5)
  r.ImGui_SetCursorScreenPos(ctx, link_x, link_y)
  if draw_ui_button("seq_layer_link_" .. slot.id, nil, link_sz, link_sz, {
    icon = "link",
    style = linked and "accent" or "default",
    selected = linked,
  }) then
    seq_layering_set_linked(slot, not linked)
    save_config()
    seq_layering_sync_arrange(slot)
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, linked
      and "Unlink transient and sustain"
      or "Link transient and sustain — use whole samples, no split")
  end
  local link_caption = linked and "LINKED" or "LINK"
  local cap_w = select(1, r.ImGui_CalcTextSize(ctx, link_caption)) or 28
  if dl then
    r.ImGui_DrawList_AddText(dl, left_x + col_w + (SEQ_LAYER_LINK_W - cap_w) * 0.5, link_y + link_sz + 4,
      linked and UI_THEME.accent or UI_THEME.text_dim, link_caption)
  end

  local bias_x = left_x + col_w + (SEQ_LAYER_LINK_W - bias_w) * 0.5
  local bias_y = link_y + link_sz + 22
  if dl then
    seq_layering_draw_bias(dl, slot, bias_x, bias_y, bias_w, bias_h, linked)
  end
end

-- Sample Map Browser module: seq_parent_items
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_parent_source_is_midi(src)
  if not seq_parent_source_valid(src) then
    return false
  end
  local typ = seq_source_type(src):upper()
  return typ:find("MIDI", 1, true) ~= nil
end

function seq_parent_item_is_midi(item)
  local take = item and r.GetActiveTake and r.GetActiveTake(item)
  if not take then
    return false, nil
  end
  if r.TakeIsMIDI then
    local ok, is_midi = pcall(r.TakeIsMIDI, take)
    if ok and is_midi then
      return true, take
    end
    if is_midi == true then
      return true, take
    end
  end
  local src = r.GetMediaItemTake_Source and r.GetMediaItemTake_Source(take)
  return seq_parent_source_is_midi(src), take
end

function seq_parent_take_source(item)
  local take = item and r.GetActiveTake and r.GetActiveTake(item)
  if not take or not r.GetMediaItemTake_Source then
    return nil, take
  end
  return r.GetMediaItemTake_Source(take), take
end

function seq_parent_takes_share_source(item_a, item_b)
  local sa = select(1, seq_parent_take_source(item_a))
  local sb = select(1, seq_parent_take_source(item_b))
  return sa and sb and sa == sb
end

function seq_parent_midi_source(pool_id, prefer_src)
  pool_id = tonumber(pool_id) or 0
  local cached = seq_parent_pcm_by_pool[pool_id]
  if seq_parent_source_is_midi(cached) then
    return cached
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    if (tonumber(reg.pool_id) or 0) == pool_id and reg.parent_item_guid then
      local item = seq_find_item_by_guid(reg.parent_item_guid)
      local src = select(1, seq_parent_take_source(item))
      if seq_parent_source_is_midi(src) then
        seq_parent_pcm_by_pool[pool_id] = src
        return src
      end
    end
  end
  if seq_parent_source_is_midi(prefer_src) then
    seq_parent_pcm_by_pool[pool_id] = prefer_src
    return prefer_src
  end
  return nil
end

function seq_media_item_ptr(item)
  if item == nil then
    return nil
  end
  if r.ValidatePtr2 then
    if r.ValidatePtr2(0, item, "MediaItem*") then
      return item
    end
    return nil
  end
  if r.ValidatePtr then
    if r.ValidatePtr(item, "MediaItem*") then
      return item
    end
    return nil
  end
  return item
end

function seq_parent_item_take_count(item)
  item = seq_media_item_ptr(item)
  if not item then
    return 0
  end
  if r.GetMediaItemNumTakes then
    local ok, n = pcall(r.GetMediaItemNumTakes, item)
    if ok then
      return tonumber(n) or 0
    end
  end
  if r.GetActiveTake then
    local ok, take = pcall(r.GetActiveTake, item)
    if ok and take then
      return 1
    end
  end
  return 0
end

function seq_create_parent_midi_item(track, region)
  if not track then
    return nil
  end
  local start_qn = (region and region.start_qn) or 0.0
  local length_qn = region and get_seq_region_length_qn(region) or 16.0
  local start_pos = qn_to_time(start_qn)
  local end_pos = qn_to_time(start_qn + length_qn)
  if not start_pos or not end_pos or end_pos <= start_pos then
    start_pos = start_pos or 0.0
    end_pos = start_pos + 2.0
  end
  local item = r.CreateNewMIDIItemInProj(track, start_pos, end_pos)
  return item
end

function seq_new_reaper_guid()
  if r.genGuid then
    local g = r.genGuid("")
    if type(g) == "string" and g ~= "" then
      if g:sub(1, 1) ~= "{" then
        g = "{" .. g .. "}"
      end
      return g
    end
  end
  return string.format("{%08X-%04X-%04X-%04X-%08X%04X}",
    math.random(0, 0xFFFFFFFF),
    math.random(0, 0xFFFF),
    math.random(0, 0xFFFF),
    math.random(0, 0xFFFF),
    math.random(0, 0xFFFFFFFF),
    math.random(0, 0xFFFF))
end

function seq_normalize_pool_guid(guid)
  if type(guid) ~= "string" or guid == "" then
    return nil
  end
  if guid:sub(1, 1) ~= "{" then
    guid = "{" .. guid .. "}"
  end
  return guid
end

function seq_source_pooledevts_guid(state)
  if type(state) ~= "string" then
    return nil
  end
  return state:match("POOLEDEVTS%s+(%b{})")
end

function seq_source_set_pooledevts(state, pool_guid)
  if type(state) ~= "string" or state == "" then
    return nil
  end
  pool_guid = seq_normalize_pool_guid(pool_guid)
  if pool_guid then
    if state:find("POOLEDEVTS", 1, true) then
      return (state:gsub("POOLEDEVTS%s+%b{}", "POOLEDEVTS " .. pool_guid, 1))
    end
    local has = state:find("HASDATA", 1, true)
    local src = state:find("<SOURCE MIDI", 1, true)
    local at = has or src
    local nl = at and state:find("\n", at, true)
    if not nl then
      return state .. "\nPOOLEDEVTS " .. pool_guid
    end
    return state:sub(1, nl) .. "POOLEDEVTS " .. pool_guid .. "\n" .. state:sub(nl + 1)
  end
  return (state:gsub("[\r\n]*POOLEDEVTS%s+%b{}", ""))
end

function seq_chunk_midi_source_span(chunk)
  if type(chunk) ~= "string" then
    return nil
  end
  local start = chunk:find("<SOURCE MIDI", 1, true)
  if not start then
    return nil
  end
  local depth = 0
  for i = start, #chunk do
    local c = chunk:sub(i, i)
    if c == "<" then
      depth = depth + 1
    elseif c == ">" then
      depth = depth - 1
      if depth == 0 then
        return start, i
      end
    end
  end
  return nil
end

function seq_snm_take_source_state(take, new_state)
  if not take or not r.SNM_GetSetSourceState2 or not r.SNM_CreateFastString then
    return nil
  end
  local fs = r.SNM_CreateFastString("")
  if not fs then
    return nil
  end
  local out = nil
  if new_state then
    if not r.SNM_SetFastString then
      if r.SNM_DeleteFastString then
        r.SNM_DeleteFastString(fs)
      end
      return nil
    end
    r.SNM_SetFastString(fs, new_state)
    if r.SNM_GetSetSourceState2(take, fs, true) then
      out = new_state
    end
  else
    if r.SNM_GetSetSourceState2(take, fs, false) and r.SNM_GetFastString then
      local state = r.SNM_GetFastString(fs)
      if type(state) == "string" and state ~= "" then
        out = state
      end
    end
  end
  if r.SNM_DeleteFastString then
    r.SNM_DeleteFastString(fs)
  end
  return out
end

function seq_midi_item_source_state(item)
  local is_midi, take = seq_parent_item_is_midi(item)
  if not is_midi or not take then
    return nil, take
  end
  local state = seq_snm_take_source_state(take)
  if state then
    return state, take
  end
  local chunk = seq_item_state_chunk(item)
  local a, b = seq_chunk_midi_source_span(chunk)
  if a and b then
    return chunk:sub(a, b), take
  end
  return nil, take
end

function seq_midi_item_set_source_state(item, state)
  item = seq_media_item_ptr(item) or item
  if not item or type(state) ~= "string" or state == "" then
    return false
  end
  local take = select(2, seq_parent_item_is_midi(item))
  if take and seq_snm_take_source_state(take, state) then
    if r.UpdateItemInProject then
      r.UpdateItemInProject(item)
    end
    return true
  end
  local chunk = seq_item_state_chunk(item)
  local a, b = seq_chunk_midi_source_span(chunk)
  if not a then
    return false
  end
  chunk = chunk:sub(1, a - 1) .. state .. chunk:sub(b + 1)
  if not r.SetItemStateChunk(item, chunk, false) then
    return false
  end
  if r.UpdateItemInProject then
    r.UpdateItemInProject(item)
  end
  return true
end

function seq_midi_item_pool_guid(item)
  local is_midi, take = seq_parent_item_is_midi(item)
  if not is_midi or not take then
    return nil
  end
  if r.BR_GetMidiTakePoolGUID then
    local a, b = r.BR_GetMidiTakePoolGUID(take)
    if type(a) == "string" and a ~= "" then
      return a
    end
    if a and type(b) == "string" and b ~= "" then
      return b
    end
  end
  local state = seq_midi_item_source_state(item)
  return seq_source_pooledevts_guid(state)
end

function seq_midi_item_set_pooledevts(item, pool_guid)
  local state = seq_midi_item_source_state(item)
  if not state then
    return false
  end
  local next_state = seq_source_set_pooledevts(state, pool_guid)
  if not next_state or next_state == state then
    return next_state ~= nil
  end
  return seq_midi_item_set_source_state(item, next_state)
end

function seq_parent_midi_copy_events(from_take, to_take)
  if not from_take or not to_take or from_take == to_take then
    return
  end
  if not r.MIDI_GetAllEvts or not r.MIDI_SetAllEvts then
    return
  end
  local a, b = r.MIDI_GetAllEvts(from_take, "")
  local evts = nil
  if type(b) == "string" then
    evts = b
  elseif type(a) == "string" then
    evts = a
  end
  if evts then
    r.MIDI_SetAllEvts(to_take, evts)
    if r.MIDI_Sort then
      r.MIDI_Sort(to_take)
    end
  end
end

function seq_parent_unpool_midi_item(item)
  local is_midi, take = seq_parent_item_is_midi(item)
  if not is_midi or not take then
    return
  end
  local evts = nil
  if r.MIDI_GetAllEvts then
    local a, b = r.MIDI_GetAllEvts(take, "")
    if type(b) == "string" then
      evts = b
    elseif type(a) == "string" then
      evts = a
    end
  end
  local neu = r.PCM_Source_CreateFromType and r.PCM_Source_CreateFromType("MIDI")
  if neu and r.SetMediaItemTake_Source then
    r.SetMediaItemTake_Source(take, neu)
  end
  if evts and r.MIDI_SetAllEvts then
    r.MIDI_SetAllEvts(take, evts)
    if r.MIDI_Sort then
      r.MIDI_Sort(take)
    end
  end
  local state = seq_midi_item_source_state(item)
  if state then
    seq_midi_item_set_source_state(item, seq_source_set_pooledevts(state, nil))
  else
    seq_midi_item_set_pooledevts(item, nil)
  end
end

function seq_parent_sync_native_midi_pool(item, region)
  item = seq_media_item_ptr(item) or item
  if not item or not region then
    return
  end
  if not select(1, seq_parent_item_is_midi(item)) then
    return
  end
  local pool_id = tonumber(region.pool_id) or 0
  local linked = seq_region_pool_count(pool_id) > 1
  if not linked then
    if seq_midi_item_pool_guid(item) then
      seq_parent_unpool_midi_item(item)
    end
    return
  end
  local members = {}
  local proto_item, proto_state = nil, nil
  for _, reg in ipairs(state.seq_regions or {}) do
    if (tonumber(reg.pool_id) or 0) == pool_id and reg.parent_item_guid then
      local it = seq_find_item_by_guid(reg.parent_item_guid)
      if it and select(1, seq_parent_item_is_midi(it)) then
        members[#members + 1] = it
        if not proto_item then
          proto_item = it
          proto_state = seq_midi_item_source_state(it)
        end
      end
    end
  end
  if #members < 2 then
    members[#members + 1] = item
  end
  local majority = seq_parent_pool_majority_guid(pool_id, nil)
  if majority then
    for i = 1, #members do
      if seq_parent_native_guid(members[i]) == majority then
        proto_item = members[i]
        proto_state = seq_midi_item_source_state(members[i])
        break
      end
    end
  end
  if not proto_state then
    proto_item = item
    proto_state = seq_midi_item_source_state(item)
  end
  if not proto_state then
    return
  end
  local guid = majority
      or seq_source_pooledevts_guid(proto_state)
      or seq_midi_item_pool_guid(proto_item)
      or seq_midi_item_pool_guid(item)
      or seq_new_reaper_guid()
  guid = seq_normalize_pool_guid(guid) or guid
  proto_state = seq_source_set_pooledevts(proto_state, guid)
  for i = 1, #members do
    local it = members[i]
    local owner = region
    for _, reg in ipairs(state.seq_regions or {}) do
      if (tonumber(reg.pool_id) or 0) == pool_id and reg.parent_item_guid then
        if seq_find_item_by_guid(reg.parent_item_guid) == it then
          owner = reg
          break
        end
      end
    end
    if seq_parent_item_should_join_pool(it, owner) then
      seq_midi_item_set_source_state(it, proto_state)
    end
  end
end

function seq_parent_sync_pool(pool_id)
  pool_id = tonumber(pool_id) or 0
  if pool_id <= 0 or seq_region_pool_count(pool_id) < 2 then
    return
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    if (tonumber(reg.pool_id) or 0) == pool_id and reg.parent_item_guid then
      local item = seq_find_item_by_guid(reg.parent_item_guid)
      if item then
        seq_parent_sync_native_midi_pool(item, reg)
        return
      end
    end
  end
end

function seq_ensure_parent_item_take(item, region)
  item = seq_media_item_ptr(item)
  if not item or not region then
    return nil
  end
  local is_midi, take = seq_parent_item_is_midi(item)
  if not is_midi or not take then
    return nil
  end
  local cur_src = r.GetMediaItemTake_Source and r.GetMediaItemTake_Source(take)
  local pool_id = tonumber(region.pool_id) or 0
  if seq_parent_item_should_join_pool(item, region) then
    local pooled = seq_parent_midi_source(pool_id, seq_parent_source_is_midi(cur_src) and cur_src or nil)
    if pooled and cur_src ~= pooled and r.SetMediaItemTake_Source then
      r.SetMediaItemTake_Source(take, pooled)
    elseif seq_parent_source_is_midi(cur_src) then
      seq_parent_pcm_by_pool[pool_id] = cur_src
    end
  elseif seq_parent_source_is_midi(cur_src) then
    seq_parent_pcm_by_pool[pool_id] = nil
  end
  local label = seq_region_parent_label(region)
  if r.GetSetMediaItemTakeInfo_String then
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", label, true)
  end
  return take
end

function seq_region_native_color(region)
  local palette = {
    {0x4A, 0x8B, 0xD6},
    {0x7D, 0xD6, 0x70},
    {0xD6, 0xA4, 0x4A},
    {0xC7, 0x6D, 0xD6},
    {0x4A, 0xD6, 0xC1},
    {0xD6, 0x6D, 0x6D},
  }
  local idx = ((math.floor((region and region.pool_id) or 1) - 1) % #palette) + 1
  local rgb = palette[idx]
  if r.ColorToNative then
    return r.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000
  end
  return 0
end

-- GUID -> item map built lazily by one project scan. Hits are validated
-- (pointer still valid and GUID unchanged); a miss or stale hit rebuilds the
-- map, so a lookup never costs more than one scan. Validation makes hits safe
-- across edits, so the map is not dropped on every project change (pool sync
-- edits items between lookups); it is dropped when the active project changes.
seq_item_guid_lookup_cache = nil

function seq_item_guid_lookup_rebuild()
  local map = {}
  local n = r.CountTracks(0)
  for tr_idx = 0, n - 1 do
    local tr = r.GetTrack(0, tr_idx)
    for item_idx = 0, r.CountTrackMediaItems(tr) - 1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      local g = item and seq_item_guid(item)
      if g and map[g] == nil then
        map[g] = item
      end
    end
  end
  seq_item_guid_lookup_cache = {
    map = map,
    proj = r.EnumProjects and r.EnumProjects(-1) or nil,
  }
  return map
end

function seq_find_item_by_guid(guid)
  if not guid or guid == "" then
    return nil, nil
  end
  local cache = seq_item_guid_lookup_cache
  if cache and r.EnumProjects and cache.proj ~= r.EnumProjects(-1) then
    cache = nil
  end
  if cache then
    local item = cache.map[guid]
    if item and (not r.ValidatePtr2 or r.ValidatePtr2(0, item, "MediaItem*"))
        and seq_item_guid(item) == guid then
      return item, r.GetMediaItem_Track(item)
    end
  end
  local item = seq_item_guid_lookup_rebuild()[guid]
  if item then
    return item, r.GetMediaItem_Track(item)
  end
  return nil, nil
end

function seq_write_parent_item_ext(item, region)
  item = seq_media_item_ptr(item)
  if not item or not region then
    return
  end
  set_item_ext(item, SEQ_EXT_PARENT, "1")
  set_item_ext(item, SEQ_EXT_REGION, region.id)
  set_item_ext(item, SEQ_EXT_PATTERN, region.pattern_id)
  set_item_ext(item, SEQ_EXT_POOL, region.pool_id)
end

function seq_apply_parent_item_props(item, region)
  item = seq_media_item_ptr(item)
  if not item or not region then
    return nil
  end
  local start_qn = region.start_qn or 0.0
  local length_qn = get_seq_region_length_qn(region)
  local t0 = qn_to_time(start_qn)
  local t1 = qn_to_time(start_qn + length_qn)
  if t0 and t1 and t1 > t0 then
    r.SetMediaItemPosition(item, t0, false)
    r.SetMediaItemLength(item, t1 - t0, false)
  end
  local label = seq_region_parent_label(region)
  if r.GetSetMediaItemInfo_String then
    r.GetSetMediaItemInfo_String(item, "P_NAME", label, true)
  end
  seq_ensure_parent_item_take(item, region)
  if r.ColorToNative then
    r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", seq_region_native_color(region))
  end
  if r.SetMediaItemInfo_Value then
    r.SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", 1)
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
  end
  seq_write_parent_item_ext(item, region)
  seq_attach_parent_item_image(item)
  seq_parent_sync_native_midi_pool(item, region)
  if r.UpdateItemInProject then
    r.UpdateItemInProject(item)
  end
  return item
end

function seq_sync_region_parent_item(region)
  if not region then
    return false
  end
  local parent_tr = find_seq_parent_folder_track() or create_seq_parent_folder_track()
  if not parent_tr then
    return false
  end
  local item = nil
  local item_tr = nil
  if region.parent_item_guid and region.parent_item_guid ~= "" then
    item, item_tr = seq_find_item_by_guid(region.parent_item_guid)
    item = seq_media_item_ptr(item)
  end
  if not item then
    local n = r.CountTrackMediaItems(parent_tr)
    for i = 0, n - 1 do
      local cand = r.GetTrackMediaItem(parent_tr, i)
      if cand and seq_item_is_parent_marker(cand)
          and tonumber(get_item_ext(cand, SEQ_EXT_REGION) or "") == region.id then
        item = cand
        item_tr = parent_tr
        break
      end
    end
  end
  local created = false
  if not item then
    item = seq_create_parent_midi_item(parent_tr, region)
    if not item then
      return false
    end
    created = true
    item_tr = parent_tr
  elseif item_tr and item_tr ~= parent_tr and r.MoveMediaItemToTrack then
    r.MoveMediaItemToTrack(item, parent_tr)
    item_tr = parent_tr
  end
  local guid = seq_item_guid(item)
  local already = false
  if item and not created then
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0.0
    local have_start = time_to_qn(pos)
    local have_end = time_to_qn(pos + len)
    local want_start = region.start_qn or 0.0
    local want_len = get_seq_region_length_qn(region)
    already = have_start and have_end
      and math.abs(have_start - want_start) <= 0.0005
      and math.abs((have_end - have_start) - want_len) <= 0.0005
      and seq_item_name(item) == seq_region_parent_label(region)
      and seq_parent_item_has_image(item)
      and tonumber(get_item_ext(item, SEQ_EXT_REGION) or "") == region.id
      and tonumber(get_item_ext(item, SEQ_EXT_PATTERN) or "") == region.pattern_id
      and tonumber(get_item_ext(item, SEQ_EXT_POOL) or "") == region.pool_id
      and guid and guid == region.parent_item_guid
  end
  if not already then
    item = seq_apply_parent_item_props(item, region) or item
    seq_mark_self_arrange_write()
  else
    seq_parent_sync_native_midi_pool(item, region)
  end
  region.parent_item_guid = seq_item_guid(item) or guid or region.parent_item_guid
  return created
end

function seq_remove_region_parent_item(region)
  if not region then
    return false
  end
  local item = nil
  if region.parent_item_guid and region.parent_item_guid ~= "" then
    item = seq_find_item_by_guid(region.parent_item_guid)
  end
  if not item then
    local parent_tr = find_seq_parent_folder_track()
    if parent_tr then
      for i = r.CountTrackMediaItems(parent_tr) - 1, 0, -1 do
        local cand = r.GetTrackMediaItem(parent_tr, i)
        if cand and seq_item_is_parent_marker(cand)
            and tonumber(get_item_ext(cand, SEQ_EXT_REGION) or "") == region.id then
          item = cand
          break
        end
      end
    end
  end
  if not item then
    return false
  end
  local tr = r.GetMediaItemTrack and r.GetMediaItemTrack(item)
  if tr and r.DeleteTrackMediaItem(tr, item) then
    region.parent_item_guid = nil
    seq_mark_self_arrange_write()
    return true
  end
  return false
end

function seq_ensure_all_region_parent_items()
  local any = false
  for _, region in ipairs(state.seq_regions or {}) do
    seq_sync_region_parent_item(region)
    local item = region.parent_item_guid and select(1, seq_find_item_by_guid(region.parent_item_guid))
    if item then
      seq_attach_parent_item_image(item)
    end
    any = true
  end
  if any then
    seq_refresh_arrange()
  end
  return any
end

function seq_collect_parent_items()
  local out = {}
  local n = r.CountTracks(0)
  for tr_idx = 0, n - 1 do
    local tr = r.GetTrack(0, tr_idx)
    for item_idx = 0, r.CountTrackMediaItems(tr) - 1 do
      local item = r.GetTrackMediaItem(tr, item_idx)
      if item and seq_item_is_parent_marker(item) then
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
        local start_qn = time_to_qn(pos)
        table.insert(out, {
          item = item,
          track = tr,
          guid = seq_item_guid(item),
          region_id = tonumber(get_item_ext(item, SEQ_EXT_REGION) or ""),
          pattern_id = tonumber(get_item_ext(item, SEQ_EXT_PATTERN) or ""),
          pool_id = tonumber(get_item_ext(item, SEQ_EXT_POOL) or ""),
          start_qn = start_qn,
          length_qn = seq_item_length_qn(item),
          name = seq_item_name(item),
        })
      end
    end
  end
  return out
end

function seq_arrange_parent_copy_unique()
  if not r.Undo_CanUndo2 then
    return false
  end
  local desc = tostring(r.Undo_CanUndo2(0) or ""):lower()
  return desc:find("unpool", 1, true) ~= nil
      or desc:find("not pooling", 1, true) ~= nil
      or desc:find("make unique", 1, true) ~= nil
end

function seq_parent_native_guid(item)
  return seq_normalize_pool_guid(seq_midi_item_pool_guid(item))
end

function seq_parent_pool_majority_guid(pool_id, ignore_item)
  pool_id = tonumber(pool_id) or 0
  local counts = {}
  for _, reg in ipairs(state.seq_regions or {}) do
    if (tonumber(reg.pool_id) or 0) == pool_id and reg.parent_item_guid then
      local it = seq_find_item_by_guid(reg.parent_item_guid)
      if it and it ~= ignore_item then
        local g = seq_parent_native_guid(it)
        if g then
          counts[g] = (counts[g] or 0) + 1
        end
      end
    end
  end
  local best, n = nil, 0
  for g, c in pairs(counts) do
    if c > n then
      best, n = g, c
    end
  end
  return best, n
end

function seq_parent_item_should_join_pool(item, region)
  if not item or not region then
    return false
  end
  local pool_id = tonumber(region.pool_id) or 0
  if seq_region_pool_count(pool_id) < 2 then
    return false
  end
  local mine = seq_parent_native_guid(item)
  local majority, majority_n = seq_parent_pool_majority_guid(pool_id, item)
  if mine and majority and mine ~= majority then
    return false
  end
  if seq_arrange_parent_copy_unique() then
    return mine ~= nil and majority ~= nil and mine == majority
  end
  if not mine and majority and majority_n >= 1 then
    -- A new linked copy has no POOLEDEVTS yet; an arrange unpool often
    -- strips it. Only auto-join when we are the ones creating the copy.
    local desc = r.Undo_CanUndo2 and tostring(r.Undo_CanUndo2(0) or ""):lower() or ""
    if desc:find("pool copy", 1, true) or desc:find("link", 1, true) then
      return true
    end
    return false
  end
  return true
end

function seq_ingest_parent_native_unpool()
  local desc = r.Undo_CanUndo2 and tostring(r.Undo_CanUndo2(0) or ""):lower() or ""
  if desc:find("pool copy", 1, true) then
    return false
  end
  local by_pool = {}
  for _, region in ipairs(state.seq_regions or {}) do
    local pid = tonumber(region.pool_id)
    if pid then
      by_pool[pid] = by_pool[pid] or {}
      by_pool[pid][#by_pool[pid] + 1] = region
    end
  end
  local any = false
  for pid, regs in pairs(by_pool) do
    if #regs >= 2 then
      local keys = {}
      local native_any = false
      for i = 1, #regs do
        local item = regs[i].parent_item_guid and seq_find_item_by_guid(regs[i].parent_item_guid)
        local g = item and seq_parent_native_guid(item) or nil
        keys[i] = g
        if g then
          native_any = true
        end
      end
      if native_any then
        local majority = seq_parent_pool_majority_guid(pid, nil)
        local keep_id = regs[1].id
        if majority then
          for i = 1, #regs do
            if keys[i] == majority then
              keep_id = regs[i].id
              break
            end
          end
        end
        local to_unpool = {}
        for i = 1, #regs do
          local left
          if majority then
            left = keys[i] ~= majority
          else
            left = regs[i].id ~= keep_id
          end
          if left then
            to_unpool[#to_unpool + 1] = regs[i]
          end
        end
        for i = 1, #to_unpool do
          seq_unpool_region(to_unpool[i], { skip_undo = true, skip_sync = true })
          any = true
        end
      elseif seq_arrange_parent_copy_unique() then
        for i = 2, #regs do
          seq_unpool_region(regs[i], { skip_undo = true, skip_sync = true })
          any = true
        end
      end
    end
  end
  return any
end

function seq_delete_region_keep_pattern(region)
  if not region then
    return false
  end
  remove_seq_rendered_items(region)
  seq_refresh_arrange()
  for i, reg in ipairs(state.seq_regions) do
    if reg.id == region.id then
      table.remove(state.seq_regions, i)
      break
    end
  end
  if state.selected_seq_region_id == region.id then
    state.selected_seq_region_id = state.seq_regions[1] and state.seq_regions[1].id or nil
  end
  return true
end

function seq_create_region_from_parent_item(rec, src, pooled)
  if not rec or not rec.start_qn then
    return nil
  end
  local length_qn = rec.length_qn or 16.0
  local length_bars = seq_qn_length_to_bars(rec.start_qn, length_qn)
  local pattern_id
  local pool_id
  if src and pooled then
    pattern_id = src.pattern_id
    pool_id = src.pool_id or alloc_seq_pool()
    src.pool_id = pool_id
  elseif src then
    pattern_id = alloc_seq_pattern()
    pool_id = alloc_seq_pool()
    local src_pattern = get_seq_pattern(src.pattern_id, false)
    state.seq_patterns[tostring(pattern_id)] = clone_table_deep(src_pattern or { notes = {} })
  else
    pattern_id = rec.pattern_id
    if not pattern_id or not get_seq_pattern(pattern_id, false) then
      pattern_id = alloc_seq_pattern()
    end
    pool_id = rec.pool_id or alloc_seq_pool()
  end
  -- REAPER undo of a region delete brings back its parent item and its hits,
  -- still tagged with the old region id. Reuse that id so the region claims
  -- them back instead of rendering a second copy of every hit beside them.
  local region_id = state.seq_region_next_id
  local old_id = math.tointeger(tonumber(rec.region_id) or 0)
  if old_id and old_id > 0 and not get_seq_region_by_id(old_id) then
    region_id = old_id
    if old_id >= state.seq_region_next_id then
      state.seq_region_next_id = old_id + 1
    end
  else
    state.seq_region_next_id = state.seq_region_next_id + 1
  end
  local region = {
    id = region_id,
    name = (rec.name and rec.name ~= "" and rec.name) or seq_auto_name_new_region(rec.start_qn),
    start_qn = rec.start_qn,
    length_bars = length_bars,
    pool_id = pool_id,
    pattern_id = pattern_id,
    groove = src and normalize_seq_groove(src.groove) or "off",
    style_key = src and src.style_key or nil,
    style_source = src and src.style_source or nil,
    kit_genres = src and src.kit_genres and clone_table_deep(src.kit_genres) or nil,
    parent_item_guid = rec.guid,
    track_samples = src and seq_clone_region_track_samples(src) or nil,
  }
  table.insert(state.seq_regions, region)
  sort_seq_regions()
  state.selected_seq_region_id = region.id
  if rec.item then
    seq_apply_parent_item_props(rec.item, region)
  end
  seq_remove_orphaned_region_items()
  sync_seq_region(region)
  if pooled then
    seq_parent_sync_pool(pool_id)
  end
  return region
end

function seq_ingest_parent_items()
  local items = seq_collect_parent_items()
  local by_guid = {}
  for _, rec in ipairs(items) do
    if rec.guid then
      by_guid[rec.guid] = rec
    end
  end

  local claimed = {}
  for _, rec in ipairs(items) do
    rec.matched = nil
  end
  for _, region in ipairs(state.seq_regions or {}) do
    local guid = region.parent_item_guid
    local rec = guid and by_guid[guid]
    if rec and not rec.matched then
      rec.matched = region
      claimed[region.id] = rec
    end
  end
  for _, rec in ipairs(items) do
    if not rec.matched and rec.region_id then
      local region = get_seq_region_by_id(rec.region_id)
      if region and not claimed[region.id] then
        region.parent_item_guid = rec.guid
        rec.matched = region
        claimed[region.id] = rec
      end
    end
  end

  local changed = false
  local needs_note_sync = false

  for _, rec in ipairs(items) do
    if not rec.matched then
      local src = rec.region_id and get_seq_region_by_id(rec.region_id) or nil
      if not src and rec.pattern_id then
        for _, region in ipairs(state.seq_regions or {}) do
          if region.pattern_id == rec.pattern_id then
            src = region
            break
          end
        end
      end
      local unique = seq_arrange_parent_copy_unique()
      local src_item = src and src.parent_item_guid and select(1, seq_find_item_by_guid(src.parent_item_guid))
      local shared = rec.item and src_item and (
        seq_parent_takes_share_source(rec.item, src_item)
        or (seq_midi_item_pool_guid(rec.item) ~= nil
            and seq_midi_item_pool_guid(rec.item) == seq_midi_item_pool_guid(src_item))
      )
      local pooled
      if shared == true then
        pooled = true
      elseif shared == false and rec.item and r.GetActiveTake and r.GetActiveTake(rec.item) then
        pooled = false
      else
        pooled = src and not unique
      end
      if seq_create_region_from_parent_item(rec, src, pooled) then
        changed = true
        needs_note_sync = true
      end
    end
  end

  local touched = {}
  for _, region in ipairs(state.seq_regions or {}) do
    local rec = claimed[region.id]
    if rec and rec.start_qn then
      local new_start = rec.start_qn
      local new_len = rec.length_qn or get_seq_region_length_qn(region)
      local new_bars = seq_qn_length_to_bars(new_start, new_len)
      local old_start = region.start_qn or 0.0
      local moved = math.abs(new_start - old_start) > 0.0005
      local resized = new_bars ~= region.length_bars
      local renamed = rec.name and rec.name ~= "" and rec.name ~= (region.name or "")
      if moved or resized or renamed then
        if moved then
          region.start_qn = new_start
        end
        if resized then
          region.length_bars = new_bars
        end
        if renamed then
          region.name = rec.name
        end
        if moved or resized then
          touched[#touched + 1] = region
        elseif rec.item then
          seq_write_parent_item_ext(rec.item, region)
        end
        changed = true
      end
    end
  end
  if #touched > 0 then
    sort_seq_regions()
    -- Keep arrange-dropped positions; only shift other regions on conflict.
    seq_evict_overlaps_keeping(touched)
    for _, region in ipairs(touched) do
      local rec = claimed[region.id]
      if rec and rec.item then
        -- Pin parent item to the arrange-authored start (evict must not move it).
        seq_apply_parent_item_props(rec.item, region)
      end
      sync_seq_region(region)
    end
    seq_mark_self_arrange_write()
  end

  local to_delete = {}
  for _, region in ipairs(state.seq_regions or {}) do
    if region.parent_item_guid and region.parent_item_guid ~= "" and not by_guid[region.parent_item_guid]
        and not claimed[region.id] then
      table.insert(to_delete, region)
    end
  end
  for _, region in ipairs(to_delete) do
    seq_delete_region_keep_pattern(region)
    changed = true
    needs_note_sync = true
  end

  if not changed then
    for _, region in ipairs(state.seq_regions or {}) do
      if not region.parent_item_guid or region.parent_item_guid == "" then
        seq_sync_region_parent_item(region)
        changed = true
      end
    end
  end

  return changed, needs_note_sync
end

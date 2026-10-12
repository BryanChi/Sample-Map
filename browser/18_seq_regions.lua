-- Sample Map Browser module: seq_regions
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function get_seq_pattern(pattern_id, create)
  if not pattern_id then
    return nil
  end
  local key = tostring(pattern_id)
  if not state.seq_patterns[key] and create then
    state.seq_patterns[key] = { notes = {} }
  end
  local pattern = state.seq_patterns[key]
  if pattern and type(pattern.notes) ~= "table" then
    pattern.notes = {}
  end
  return pattern
end

function get_seq_region_by_id(region_id)
  if not region_id then
    return nil
  end
  for _, region in ipairs(state.seq_regions) do
    if region.id == region_id then
      return region
    end
  end
  return nil
end

-- Region lengths depend only on start_qn, bar count and the project tempo map.
-- The draw loop asks for them once per note per frame (four TimeMap calls each),
-- so results are memoized for the current frame; sm_loop_frame clears the cache
-- before any work, so tempo/time-signature edits show up on the next frame.
seq_region_len_cache = {}

function seq_region_len_cache_reset()
  seq_region_len_cache = {}
  seq_sample_qn_at_cache = {}
  seq_trigger_memo = nil
end

function get_seq_region_length_qn(region)
  if not region then
    return 16.0
  end
  local bars = math.max(1, math.floor(region.length_bars or 4))
  local start_qn = region.start_qn or 0.0
  if start_qn ~= start_qn then
    return seq_region_length_qn_uncached(start_qn, bars) -- NaN can't be a table key
  end
  local by_start = seq_region_len_cache[bars]
  if by_start then
    local cached = by_start[start_qn]
    if cached then
      return cached
    end
  else
    by_start = {}
    seq_region_len_cache[bars] = by_start
  end
  local len = seq_region_length_qn_uncached(start_qn, bars)
  by_start[start_qn] = len
  return len
end

function seq_region_length_qn_uncached(start_qn, bars)
  if r.TimeMap_GetMeasureInfo and r.TimeMap2_timeToBeats and qn_to_time then
    local start_time = qn_to_time(start_qn)
    if start_time then
      local _, measure = r.TimeMap2_timeToBeats(0, start_time)
      if measure then
        local _, qn_start = r.TimeMap_GetMeasureInfo(0, measure)
        local _, qn_end = r.TimeMap_GetMeasureInfo(0, measure + bars)
        if qn_start and qn_end and qn_end > qn_start then
          return qn_end - qn_start
        end
      end
    end
  end
  return bars * 4.0
end

-- Length of one bar (in QN) at the region start, from the project time
-- signature: 4/4 -> 4, 3/4 -> 3, 6/8 -> 3, 7/8 -> 3.5.
function seq_region_bar_qn(region)
  if region and r.TimeMap_GetTimeSigAtTime and qn_to_time then
    local start_time = qn_to_time(region.start_qn or 0.0)
    if start_time then
      local num, denom = r.TimeMap_GetTimeSigAtTime(0, start_time)
      num, denom = tonumber(num), tonumber(denom)
      if num and denom and num > 0 and denom > 0 then
        return num * 4.0 / denom
      end
    end
  end
  if region then
    local bars = math.max(1, math.floor(region.length_bars or 4))
    return get_seq_region_length_qn(region) / bars
  end
  return 4.0
end

-- Grid layout for pattern writers. Patterns are written in 16ths of a 4/4 bar
-- (template step s sits at s * 0.25 QN); steps_per_4qn (grid steps in 4 QN)
-- converts those to grid steps. steps_per_bar is the real bar length in grid steps, so a 3/4 bar uses
-- the first 12 sixteenths and every bar starts on its bar line. 4/4 is
-- unchanged: steps_per_bar == steps_per_4qn.
function seq_region_bar_grid(region, grid_qn)
  if not grid_qn or grid_qn <= 0 then
    grid_qn = 0.25
  end
  local bar_qn = seq_region_bar_qn(region)
  if not bar_qn or bar_qn <= 0 then
    bar_qn = 4.0
  end
  local region_len_qn = get_seq_region_length_qn(region)
  local steps_per_4qn = math.max(1, math.floor((4.0 / grid_qn) + 0.5))
  local steps_per_bar = math.max(1, math.floor((bar_qn / grid_qn) + 0.5))
  local bar_count = math.max(1, math.floor((region_len_qn / bar_qn) + 0.5))
  return steps_per_bar, bar_count, steps_per_4qn, bar_qn
end

function seq_region_max_step(region, grid_qn)
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  if not grid_qn or grid_qn <= 0 then
    grid_qn = 0.25
  end
  local length_qn = get_seq_region_length_qn(region)
  return math.max(0, math.floor((length_qn / grid_qn) - 1e-9))
end

function seq_step_in_region(region, step_idx, grid_qn)
  step_idx = tonumber(step_idx)
  if not step_idx or step_idx < 0 then
    return false
  end
  return step_idx <= seq_region_max_step(region, grid_qn)
end

-- Musical position is stored on the note (qn_offset) so grid changes never
-- re-index or hide hits that were painted on a finer grid.
function seq_note_qn_offset(note, step_key, grid_qn)
  if note and type(note.qn_offset) == "number" then
    return note.qn_offset
  end
  local step_idx = tonumber(step_key) or (note and tonumber(note.step)) or 0
  return step_idx * (grid_qn or state.seq_grid_qn or 0.25)
end

function seq_note_abs_qn(region, note, step_key, grid_qn)
  return (region and region.start_qn or 0.0) + seq_note_qn_offset(note, step_key, grid_qn)
end

function seq_note_visual_abs_qn(region, note, step_key, grid_qn)
  return seq_note_abs_qn(region, note, step_key, grid_qn) + ((note and note.offset_qn) or 0.0)
end

function seq_next_note_vis_qn_after(region, track_id, after_qn, grid_qn)
  local region_end = (region and region.start_qn or 0.0) + get_seq_region_length_qn(region)
  if not region or type(after_qn) ~= "number" then
    return region_end
  end
  local notes = get_track_note_table(get_seq_pattern(region.pattern_id, false), track_id, false)
  if not notes then
    return region_end
  end
  local next_qn = region_end
  for key, note in pairs(notes) do
    if type(note) == "table" and note.enabled ~= false then
      local vis = seq_note_visual_abs_qn(region, note, key, grid_qn)
      if vis > after_qn + 1e-9 and vis < next_qn then
        next_qn = vis
      end
    end
  end
  return next_qn
end

function seq_note_in_region(region, note, step_key, grid_qn)
  if not region then
    return false
  end
  local abs_qn = seq_note_abs_qn(region, note, step_key, grid_qn)
  local start = region.start_qn or 0.0
  local length = get_seq_region_length_qn(region)
  return abs_qn >= start - 1e-9 and abs_qn < start + length - 1e-9
end

function seq_storage_key_from_qn(qn_offset)
  return tostring(math.floor((qn_offset or 0.0) * 192.0 + 0.5))
end

function seq_quantize_free_qn(qn)
  return math.floor((qn or 0.0) * 192.0 + 0.5) / 192.0
end

function seq_find_note_key_at_qn(region, track_id, qn_offset, slop)
  slop = slop or 1e-4
  local notes = get_track_note_table(get_seq_pattern(region and region.pattern_id, false), track_id, false)
  if not notes or type(qn_offset) ~= "number" then
    return nil, nil
  end
  for key, note in pairs(notes) do
    if type(note) == "table" and math.abs(seq_note_qn_offset(note, key) - qn_offset) <= slop then
      return tostring(key), note
    end
  end
  return nil, nil
end

function seq_alloc_note_key(region, track_id, qn_offset)
  local found_key = seq_find_note_key_at_qn(region, track_id, qn_offset)
  if found_key then
    return found_key
  end
  local notes = get_track_note_table(get_seq_pattern(region and region.pattern_id, false), track_id, false)
  local base = seq_storage_key_from_qn(qn_offset)
  local key = base
  local n = 0
  while notes and notes[key] do
    n = n + 1
    key = base .. "_" .. tostring(n)
  end
  return key
end

function seq_active_cell_notes(active)
  if not active then
    return nil
  end
  return active.pack or { active }
end

function seq_for_each_active_note(active, fn)
  local pack = seq_active_cell_notes(active)
  if not pack then
    return
  end
  for i = 1, #pack do
    fn(pack[i])
  end
end

function seq_note_playable_head_span(note, abs_qn, step_qn)
  step_qn = step_qn or 0.25
  local vis = (abs_qn or 0.0) + ((note and note.offset_qn) or 0.0)
  local span = seq_stutter_span_qn(note, step_qn)
  local head = (type(span) == "number" and span > 1e-9) and span or step_qn
  return vis, vis + head
end

function seq_entry_vis_qn(entry)
  if not entry then
    return 0.0
  end
  return (entry.abs_qn or 0.0) + ((entry.note and entry.note.offset_qn) or 0.0)
end

function seq_pack_sort_later_on_top(pack)
  if type(pack) ~= "table" or #pack < 2 then
    return pack
  end
  table.sort(pack, function(a, b)
    local av, bv = seq_entry_vis_qn(a), seq_entry_vis_qn(b)
    if math.abs(av - bv) > 1e-9 then
      return av < bv
    end
    return tostring(a and a.key or "") < tostring(b and b.key or "")
  end)
  return pack
end

function seq_pick_packed_note(active, hovered_qn, start_qn, col, step_qn)
  local pack = seq_active_cell_notes(active)
  if not pack or #pack == 0 then
    return nil
  end
  step_qn = step_qn or 0.25
  local hover = hovered_qn
  if type(hover) ~= "number" then
    return pack[#pack]
  end
  local cell_qn = (start_qn or 0.0) + (col or 0) * step_qn
  local cell_end = cell_qn + step_qn
  local top, top_vis = nil, -math.huge
  for i = 1, #pack do
    local entry = pack[i]
    if type(entry) == "table" and type(entry.note) == "table"
       and seq_active_cell_is_playable(entry, start_qn, col, step_qn) then
      local vis, head_end = seq_note_playable_head_span(entry.note, entry.abs_qn, step_qn)
      -- Only the part of the head that sits in this cell is the note.
      -- Overflow / sustain in the next grid stays empty so a click paints.
      local cover_hi = math.min(head_end, cell_end)
      if hover >= vis - 1e-9 and hover < cover_hi - 1e-9 and vis >= top_vis then
        top, top_vis = entry, vis
      end
    end
  end
  return top
end

function seq_resolve_hover_note(active, hovered_qn, start_qn, col, step_qn)
  if not active or not seq_active_cell_is_playable(active, start_qn, col, step_qn) then
    return nil
  end
  return seq_pick_packed_note(active, hovered_qn, start_qn, col, step_qn)
end

function seq_erase_notes_starting_in_span(region, slot, abs0, abs1, opts)
  if not region or not slot or type(abs0) ~= "number" or type(abs1) ~= "number" then
    return false
  end
  local notes = get_track_note_table(get_seq_pattern(region.pattern_id, false), slot.id, false)
  if not notes then
    return false
  end
  local region_start = region.start_qn or 0.0
  local to_erase = {}
  for key, note in pairs(notes) do
    if type(note) == "table" then
      local abs = region_start + seq_note_qn_offset(note, key)
      local vis = abs + (note.offset_qn or 0.0)
      if vis >= abs0 - 1e-9 and vis < abs1 - 1e-9 then
        to_erase[#to_erase + 1] = { key = tostring(key), qn = abs - region_start }
      end
    end
  end
  local changed = false
  for i = 1, #to_erase do
    local item = to_erase[i]
    if toggle_seq_note(region, slot, item.key, item.qn, "erase", opts) then
      changed = true
    end
  end
  return changed
end

function snap_seq_length_qn(length_qn, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local steps = math.max(1, math.floor(((length_qn or step_qn) / step_qn) + 0.5))
  return steps * step_qn
end

SEQ_REGION_POOL_PALETTE = {
  {0x4A, 0x8B, 0xD6},
  {0x7D, 0xD6, 0x70},
  {0xD6, 0xA4, 0x4A},
  {0xC7, 0x6D, 0xD6},
  {0x4A, 0xD6, 0xC1},
  {0xD6, 0x6D, 0x6D},
}

function seq_region_pool_color(pool_id, alpha)
  local palette = SEQ_REGION_POOL_PALETTE
  local idx = ((math.floor(pool_id or 1) - 1) % #palette) + 1
  local rgb = palette[idx]
  return build_color_rrgbbaa(rgb[1], rgb[2], rgb[3], alpha or 160)
end

function seq_region_overlaps(start_qn, length_qn, ignore_region_id)
  local end_qn = start_qn + length_qn
  for _, reg in ipairs(state.seq_regions) do
    if reg.id ~= ignore_region_id then
      local reg_start = reg.start_qn or 0.0
      local reg_end = reg_start + get_seq_region_length_qn(reg)
      if start_qn < reg_end - 0.000001 and end_qn > reg_start + 0.000001 then
        return true
      end
    end
  end
  return false
end

function find_non_overlapping_region_start(preferred_start_qn, length_qn, ignore_region_id)
  local start_qn = math.max(0.0, preferred_start_qn or 0.0)
  local guard = 0
  while seq_region_overlaps(start_qn, length_qn, ignore_region_id) and guard < 256 do
    local next_start = nil
    local end_qn = start_qn + length_qn
    for _, reg in ipairs(state.seq_regions) do
      if reg.id ~= ignore_region_id then
        local reg_start = reg.start_qn or 0.0
        local reg_end = reg_start + get_seq_region_length_qn(reg)
        if start_qn < reg_end - 0.000001 and end_qn > reg_start + 0.000001 then
          if not next_start or reg_end > next_start then
            next_start = reg_end
          end
        end
      end
    end
    if not next_start or next_start <= start_qn then
      start_qn = start_qn + length_qn
    else
      start_qn = next_start
    end
    guard = guard + 1
  end
  return start_qn
end

function find_prev_non_overlapping_region_start(preferred_start_qn, length_qn, ignore_region_id)
  local start_qn = math.max(0.0, preferred_start_qn or 0.0)
  local guard = 0
  while seq_region_overlaps(start_qn, length_qn, ignore_region_id) and guard < 256 do
    local prev_start = nil
    local end_qn = start_qn + length_qn
    for _, reg in ipairs(state.seq_regions) do
      if reg.id ~= ignore_region_id then
        local reg_start = reg.start_qn or 0.0
        local reg_end = reg_start + get_seq_region_length_qn(reg)
        if start_qn < reg_end - 0.000001 and end_qn > reg_start + 0.000001 then
          local candidate = reg_start - length_qn
          if candidate >= 0 and (not prev_start or candidate < prev_start) then
            prev_start = candidate
          end
        end
      end
    end
    if prev_start == nil then
      return find_non_overlapping_region_start(preferred_start_qn, length_qn, ignore_region_id)
    end
    start_qn = math.max(0.0, prev_start)
    guard = guard + 1
  end
  return start_qn
end

function sort_seq_regions()
  table.sort(state.seq_regions, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
end

SEQ_REGION_SECTION_DEFS = {
  { key = "intro", display = "Intro", aliases = { "intro" } },
  { key = "verse", display = "Verse", aliases = { "verse", "vrs" } },
  { key = "prechorus", display = "Pre-Chorus", aliases = { "pre-chorus", "prechorus", "pre chorus", "pre" } },
  { key = "chorus", display = "Chorus", aliases = { "chorus", "chs" } },
  { key = "postchorus", display = "Post-Chorus", aliases = { "post-chorus", "postchorus", "post chorus" } },
  { key = "refrain", display = "Refrain", aliases = { "refrain" } },
  { key = "bridge", display = "Bridge", aliases = { "bridge", "brg" } },
  { key = "breakdown", display = "Breakdown", aliases = { "breakdown", "break down", "break" } },
  { key = "solo", display = "Solo", aliases = { "solo" } },
  { key = "interlude", display = "Interlude", aliases = { "interlude" } },
  { key = "instrumental", display = "Instrumental", aliases = { "instrumental" } },
  { key = "build", display = "Build", aliases = { "build", "buildup", "build-up", "riser" } },
  { key = "drop", display = "Drop", aliases = { "drop" } },
  { key = "outro", display = "Outro", aliases = { "outro", "ending", "coda" } },
  { key = "tag", display = "Tag", aliases = { "tag" } },
}

function seq_region_section_def(key)
  for _, def in ipairs(SEQ_REGION_SECTION_DEFS) do
    if def.key == key then
      return def
    end
  end
  return nil
end

function seq_parse_region_section(name)
  local raw = seq_trim_text(name):lower()
  if raw == "" then
    return nil, 1
  end
  local word, num = raw:match("^(.-)%s*(%d+)$")
  if not word or seq_trim_text(word) == "" then
    word, num = raw:match("^([%a%-%s]+)%s*(%d+)$")
  end
  if not word or seq_trim_text(word) == "" then
    word = raw
    num = 1
  else
    word = seq_trim_text(word)
    num = tonumber(num) or 1
  end
  local compact = word:gsub("[%s%-_]+", "")
  local spaced = word:gsub("[%s%-_]+", " ")
  local best, best_len = nil, -1
  for _, def in ipairs(SEQ_REGION_SECTION_DEFS) do
    for _, alias in ipairs(def.aliases) do
      local a_compact = alias:gsub("[%s%-_]+", "")
      local a_spaced = alias:gsub("[%s%-_]+", " ")
      if compact == a_compact or spaced == a_spaced then
        if #a_compact > best_len then
          best = def.key
          best_len = #a_compact
        end
      end
    end
  end
  return best, num
end

function seq_format_region_section_name(key, number)
  local def = seq_region_section_def(key)
  if not def then
    return "Region"
  end
  number = math.max(1, math.floor(tonumber(number) or 1))
  return def.display .. " " .. tostring(number)
end

function seq_region_section_number_used(key, number, ignore_id)
  number = tonumber(number) or 1
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id then
      local k, n = seq_parse_region_section(reg.name)
      if k == key and n == number then
        return true
      end
    end
  end
  return false
end

function seq_next_section_number(key, ignore_id)
  local n = 1
  while seq_region_section_number_used(key, n, ignore_id) do
    n = n + 1
  end
  return n
end

function seq_region_neighbors_at(start_qn, ignore_id)
  start_qn = start_qn or 0.0
  local prev_reg, next_reg = nil, nil
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id then
      local qn = reg.start_qn or 0.0
      if qn < start_qn - 1e-9 then
        if not prev_reg or qn > (prev_reg.start_qn or 0.0) then
          prev_reg = reg
        end
      elseif qn > start_qn + 1e-9 then
        if not next_reg or qn < (next_reg.start_qn or 0.0) then
          next_reg = reg
        end
      end
    end
  end
  return prev_reg, next_reg
end

function seq_region_section_counts(ignore_id)
  local counts = {}
  for _, def in ipairs(SEQ_REGION_SECTION_DEFS) do
    counts[def.key] = 0
  end
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id then
      local key = seq_parse_region_section(reg.name)
      if key then
        counts[key] = (counts[key] or 0) + 1
      end
    end
  end
  return counts
end

function seq_auto_name_new_region(start_qn, ignore_id)
  local prev_reg, next_reg = seq_region_neighbors_at(start_qn, ignore_id)
  local counts = seq_region_section_counts(ignore_id)
  local prev_key, prev_num = seq_parse_region_section(prev_reg and prev_reg.name)
  local next_key = seq_parse_region_section(next_reg and next_reg.name)
  local existing = 0
  for _, reg in ipairs(state.seq_regions or {}) do
    if reg.id ~= ignore_id then
      existing = existing + 1
    end
  end

  local key
  if not prev_reg then
    key = (counts.intro or 0) == 0 and "intro" or "verse"
  elseif prev_key == "intro" then
    key = "verse"
  elseif prev_key == "verse" then
    key = (next_key == "chorus") and "prechorus" or "chorus"
  elseif prev_key == "prechorus" then
    key = "chorus"
  elseif prev_key == "chorus" then
    if next_key == "verse" then
      key = "verse"
    elseif next_key == "outro" or next_key == "tag" then
      key = ((counts.bridge or 0) == 0) and "bridge" or "outro"
    elseif not next_reg and (counts.chorus or 0) >= 2 and (counts.bridge or 0) == 0 then
      key = "bridge"
    elseif not next_reg and (counts.chorus or 0) >= 2 then
      key = "outro"
    else
      key = "verse"
    end
  elseif prev_key == "postchorus" then
    key = "verse"
  elseif prev_key == "refrain" then
    key = "chorus"
  elseif prev_key == "bridge" or prev_key == "breakdown" or prev_key == "solo" then
    key = (not next_reg and (counts.chorus or 0) >= 2) and "outro" or "chorus"
  elseif prev_key == "interlude" or prev_key == "instrumental" then
    key = "verse"
  elseif prev_key == "build" then
    key = "drop"
  elseif prev_key == "drop" then
    key = "chorus"
  elseif prev_key == "outro" or prev_key == "tag" then
    key = "outro"
  elseif existing <= 0 then
    key = "intro"
  elseif existing == 1 then
    key = "verse"
  elseif existing == 2 then
    key = "chorus"
  elseif existing % 2 == 1 then
    key = "verse"
  else
    key = "chorus"
  end

  local num = seq_next_section_number(key, ignore_id)
  if key == "chorus" and prev_key == "verse" and prev_num and not seq_region_section_number_used("chorus", prev_num, ignore_id) then
    num = prev_num
  end
  return seq_format_region_section_name(key, num)
end

function seq_region_name_suggestions(region, typed)
  local start_qn = region and (region.start_qn or 0.0) or 0.0
  local ignore_id = region and region.id or nil
  local current = seq_trim_text(region and region.name or "")
  local current_l = current:lower()
  local typed_trim = seq_trim_text(typed)
  local typed_l = typed_trim:lower()
  -- Only filter after the user changes the prefilled current name.
  local filter_active = typed_l ~= "" and typed_l ~= current_l
  local prev_reg, next_reg = seq_region_neighbors_at(start_qn, ignore_id)
  local prev_key = seq_parse_region_section(prev_reg and prev_reg.name)
  local next_key = seq_parse_region_section(next_reg and next_reg.name)
  local scores = {
    intro = 40, verse = 55, prechorus = 48, chorus = 55, postchorus = 36,
    refrain = 42, bridge = 44, breakdown = 32, solo = 30, interlude = 26,
    instrumental = 22, build = 22, drop = 24, outro = 46, tag = 28,
  }
  if not prev_reg then
    scores.intro = 95
    scores.verse = 72
  elseif prev_key == "intro" then
    scores.verse = 90
    scores.chorus = 60
    scores.prechorus = 50
  elseif prev_key == "verse" then
    scores.chorus = 90
    scores.prechorus = 82
    scores.refrain = 64
    scores.verse = 58
  elseif prev_key == "prechorus" then
    scores.chorus = 92
    scores.verse = 50
  elseif prev_key == "chorus" then
    scores.verse = 86
    scores.chorus = 70
    scores.bridge = 68
    scores.postchorus = 62
    scores.outro = 60
  elseif prev_key == "bridge" then
    scores.chorus = 88
    scores.outro = 70
    scores.solo = 50
  elseif prev_key == "outro" then
    scores.outro = 80
    scores.tag = 60
  end
  if not next_reg then
    scores.outro = math.max(scores.outro or 0, 58)
  elseif next_key == "chorus" then
    scores.prechorus = math.max(scores.prechorus or 0, 80)
    scores.verse = math.max(scores.verse or 0, 70)
  elseif next_key == "outro" then
    scores.bridge = math.max(scores.bridge or 0, 74)
    scores.chorus = math.max(scores.chorus or 0, 66)
  end

  local score_by_name = {}
  local function add(name, score)
    name = seq_trim_text(name)
    if name == "" or name:lower() == current_l then
      return
    end
    local prev = score_by_name[name]
    if not prev or score > prev then
      score_by_name[name] = score
    end
  end

  add(seq_auto_name_new_region(start_qn, ignore_id), 100)
  local cur_key, cur_num = seq_parse_region_section(region and region.name)
  if cur_key then
    if cur_num > 1 then
      add(seq_format_region_section_name(cur_key, cur_num - 1), 56)
    end
    add(seq_format_region_section_name(cur_key, cur_num + 1), 64)
  end
  -- Count this region too so "next unused" is not the name it already has.
  for _, def in ipairs(SEQ_REGION_SECTION_DEFS) do
    local n = seq_next_section_number(def.key, nil)
    add(seq_format_region_section_name(def.key, n), scores[def.key] or 20)
    if def.key == "verse" or def.key == "chorus" or def.key == "intro" then
      add(seq_format_region_section_name(def.key, n + 1), (scores[def.key] or 20) - 14)
    end
  end

  local function collect(filter)
    local list = {}
    for name, score in pairs(score_by_name) do
      if not filter_active or name:lower():find(filter, 1, true) then
        list[#list + 1] = { name = name, score = score }
      end
    end
    table.sort(list, function(a, b)
      if a.score ~= b.score then
        return a.score > b.score
      end
      return a.name < b.name
    end)
    return list
  end

  local ranked = collect(typed_l)
  if #ranked == 0 then
    ranked = collect("")
  end
  local out = {}
  for _, item in ipairs(ranked) do
    out[#out + 1] = item.name
    if #out >= 12 then
      break
    end
  end
  return out
end

function seq_begin_region_rename(region)
  if not region then
    return
  end
  state.seq_region_rename = {
    region_id = region.id,
    text = region.name or "",
    orig = region.name or "",
    typed_prefix = nil,
    completed = false,
    apply_sel = false,
    select_from = 0,
    suggest_index = nil,
    arrow_pick = false,
    focus = true,
    over_suggest = false,
  }
end

function seq_cancel_region_rename()
  state.seq_region_rename = nil
end

function seq_region_autocomplete_match(region, typed)
  if type(typed) ~= "string" or typed == "" then
    return nil
  end
  local current_l = seq_trim_text(region and region.name or ""):lower()
  local typed_l = typed:lower()
  if typed_l == current_l then
    return nil
  end
  local function first_prefix(list)
    for _, name in ipairs(list or {}) do
      if type(name) == "string" and name:lower():sub(1, #typed_l) == typed_l then
        return name
      end
    end
    return nil
  end
  return first_prefix(seq_region_name_suggestions(region, typed))
    or first_prefix(seq_region_name_suggestions(region, ""))
end

function seq_ensure_region_rename_callback()
  if not r.ImGui_CreateFunctionFromEEL then
    return nil
  end
  local valid = seq_region_rename_cb
    and r.ImGui_ValidatePtr
    and r.ImGui_ValidatePtr(seq_region_rename_cb, "ImGui_Function*")
  if not valid then
    seq_region_rename_cb = r.ImGui_CreateFunctionFromEEL([[
      EventFlag == InputTextFlags_CallbackAlways ? (
        apply_sel ? (
          InputTextCallback_DeleteChars(0, strlen(#Buf));
          InputTextCallback_InsertChars(0, #complete);
          SelectionStart = sel_from;
          SelectionEnd = strlen(#Buf);
          CursorPos = sel_from;
          apply_sel = 0;
        );
      );
      EventFlag == InputTextFlags_CallbackCompletion ? (
        SelectionStart = strlen(#Buf);
        SelectionEnd = strlen(#Buf);
        CursorPos = strlen(#Buf);
      );
    ]])
    if seq_region_rename_cb and r.ImGui_Attach and ctx then
      pcall(r.ImGui_Attach, ctx, seq_region_rename_cb)
    end
    if seq_region_rename_cb and r.ImGui_Function_SetValue then
      if r.ImGui_InputTextFlags_CallbackAlways then
        r.ImGui_Function_SetValue(seq_region_rename_cb, "InputTextFlags_CallbackAlways", r.ImGui_InputTextFlags_CallbackAlways())
      end
      if r.ImGui_InputTextFlags_CallbackCompletion then
        r.ImGui_Function_SetValue(seq_region_rename_cb, "InputTextFlags_CallbackCompletion", r.ImGui_InputTextFlags_CallbackCompletion())
      end
    end
  end
  return seq_region_rename_cb
end

function seq_region_rename_suggestion_list(edit, region)
  local filter_text = edit and edit.typed_prefix
  if filter_text == nil or filter_text == (edit.orig or "") then
    filter_text = ""
  end
  return seq_region_name_suggestions(region, filter_text)
end

function seq_region_rename_index_of(list, name)
  if not name then
    return nil
  end
  for i, item in ipairs(list or {}) do
    if item == name then
      return i
    end
  end
  return nil
end

function seq_region_rename_apply_pick(edit, name, keep_prefix)
  if not edit or type(name) ~= "string" or name == "" then
    return
  end
  edit.text = name
  edit.completed = true
  local prefix = keep_prefix and (edit.typed_prefix or "") or ""
  if prefix ~= "" and name:lower():sub(1, #prefix) == prefix:lower() then
    edit.select_from = #prefix
  else
    edit.select_from = 0
  end
end

function seq_region_rename_move_candidate(edit, region, delta)
  if not edit then
    return
  end
  local list = seq_region_rename_suggestion_list(edit, region)
  if #list == 0 then
    return
  end
  local idx = edit.suggest_index
  if type(idx) ~= "number" then
    idx = seq_region_rename_index_of(list, edit.text) or 0
  end
  idx = idx + (delta or 1)
  if idx < 1 then
    idx = #list
  elseif idx > #list then
    idx = 1
  end
  edit.suggest_index = idx
  edit.arrow_pick = true
  seq_region_rename_apply_pick(edit, list[idx], true)
end

function seq_apply_region_rename_autocomplete(edit, new_text, region)
  if not edit or type(new_text) ~= "string" then
    return
  end
  if edit.arrow_pick and new_text == (edit.typed_prefix or "") then
    return
  end
  if edit.arrow_pick then
    edit.arrow_pick = false
  end
  edit.typed_prefix = new_text
  local match = seq_region_autocomplete_match(region, new_text)
  if match and #match > #new_text then
    seq_region_rename_apply_pick(edit, match, true)
    edit.suggest_index = seq_region_rename_index_of(seq_region_rename_suggestion_list(edit, region), match)
  else
    edit.text = new_text
    edit.completed = false
    edit.select_from = 0
    edit.suggest_index = nil
  end
end

function seq_draw_region_rename_completion(edit, x0, y0, x1, y1)
  if not edit or not edit.completed or type(edit.text) ~= "string" or edit.text == "" then
    return
  end
  local prefix_len = math.max(0, math.min(#edit.text, edit.select_from or 0))
  local prefix = edit.text:sub(1, prefix_len)
  local suffix = edit.text:sub(prefix_len + 1)
  if suffix == "" then
    return
  end
  local dl = (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx))
    or r.ImGui_GetWindowDrawList(ctx)
  if not dl then
    return
  end
  local pad_x = 4
  local tw_prefix, th = r.ImGui_CalcTextSize(ctx, prefix ~= "" and prefix or " ")
  if prefix == "" then
    tw_prefix = 0
  end
  local tw_suffix = select(1, r.ImGui_CalcTextSize(ctx, suffix)) or 0
  th = th or (y1 - y0)
  local text_x = x0 + pad_x
  local text_y = y0 + math.max(0, (y1 - y0 - th) * 0.5)
  local sx0 = text_x + tw_prefix
  local sy0 = text_y - 1
  local sx1 = math.min(x1 - 2, sx0 + tw_suffix + 1)
  local sy1 = text_y + th + 1
  r.ImGui_DrawList_AddRectFilled(dl, sx0, sy0, sx1, sy1, 0x1EFF5E99, 2.0)
  r.ImGui_DrawList_AddText(dl, text_x, text_y, 0xFFFFFFFF, prefix)
  r.ImGui_DrawList_AddText(dl, sx0, text_y, 0xFFFFFFFF, suffix)
end

function seq_commit_region_rename(forced_name)
  local edit = state.seq_region_rename
  if not edit then
    return
  end
  local region = get_seq_region_by_id(edit.region_id)
  local new_name = seq_trim_text(forced_name or edit.text)
  state.seq_region_rename = nil
  if not region then
    return
  end
  if new_name == "" then
    new_name = edit.orig or ""
  end
  if new_name == (region.name or "") then
    return
  end
  local label = begin_seq_undo("Rename sequencer region")
  region.name = new_name
  seq_sync_region_parent_item(region)
  save_config()
  end_seq_undo(label)
end

function render_seq_region_name_suggest_popup(edit_x, edit_y, edit_w)
  local edit = state.seq_region_rename
  if not edit then
    return
  end
  local region = get_seq_region_by_id(edit.region_id)
  local filter_text = edit.typed_prefix
  if filter_text == nil or filter_text == (edit.orig or "") then
    filter_text = ""
  end
  local suggestions = seq_region_name_suggestions(region, filter_text)
  local candidate = nil
  if type(edit.suggest_index) == "number" then
    candidate = suggestions[edit.suggest_index]
  end
  if not candidate then
    candidate = seq_region_autocomplete_match(region, edit.typed_prefix or "")
  end
  if not candidate and edit.completed then
    candidate = edit.text
  end
  if candidate then
    edit.suggest_index = seq_region_rename_index_of(suggestions, candidate) or edit.suggest_index
  end
  if #suggestions == 0 then
    edit.over_suggest = false
    return
  end
  local row_h = 20.0
  local pad_x, pad_y = 6.0, 4.0
  local popup_w = math.max(edit_w or 150, 168)
  for _, name in ipairs(suggestions) do
    local tw = select(1, r.ImGui_CalcTextSize(ctx, name)) or 0
    popup_w = math.max(popup_w, tw + pad_x * 2 + 8)
  end
  local popup_h = pad_y * 2 + #suggestions * row_h
  local popup_x = edit_x
  local popup_y = edit_y - popup_h
  if popup_y < 0 then
    popup_y = 0
  end

  local mx, my = r.ImGui_GetMousePos(ctx)
  edit.over_suggest = mx and my
    and mx >= popup_x and mx <= popup_x + popup_w
    and my >= popup_y and my <= popup_y + popup_h

  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoMove then flags = flags | r.ImGui_WindowFlags_NoMove() end
  if r.ImGui_WindowFlags_NoCollapse then flags = flags | r.ImGui_WindowFlags_NoCollapse() end
  if r.ImGui_WindowFlags_NoSavedSettings then flags = flags | r.ImGui_WindowFlags_NoSavedSettings() end
  if r.ImGui_WindowFlags_NoFocusOnAppearing then flags = flags | r.ImGui_WindowFlags_NoFocusOnAppearing() end
  if r.ImGui_WindowFlags_NoNav then flags = flags | r.ImGui_WindowFlags_NoNav() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_AlwaysAutoResize then flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize() end

  local cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
  if r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, popup_x, popup_y, cond)
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, popup_w, popup_h, cond)
  end
  local style_vars, style_cols = 0, 0
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), pad_x, pad_y)
    style_vars = style_vars + 1
  end
  if r.ImGui_StyleVar_WindowRounding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
    style_vars = style_vars + 1
  end
  if r.ImGui_StyleVar_ItemSpacing then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
    style_vars = style_vars + 1
  end
  if r.ImGui_Col_WindowBg then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), UI_THEME.popup_bg or 0x161C18F5)
    style_cols = style_cols + 1
  end
  if r.ImGui_Col_Border then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), UI_THEME.border_hvr or 0x3D5446FF)
    style_cols = style_cols + 1
  end

  local visible = r.ImGui_Begin(ctx, "##seq_region_name_suggest", true, flags)
  if visible then
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local chosen = nil
    for i, name in ipairs(suggestions) do
      r.ImGui_InvisibleButton(ctx, "##seq_region_sug_" .. tostring(i), popup_w - pad_x * 2, row_h)
      local x0, y0 = r.ImGui_GetItemRectMin(ctx)
      local x1, y1 = r.ImGui_GetItemRectMax(ctx)
      local hovered = r.ImGui_IsItemHovered(ctx)
      local selected = candidate and name == candidate
      if hovered or selected then
        local fill = hovered and (UI_THEME.accent_fill_h or 0x174A24FF) or (UI_THEME.accent_fill or 0x0E2A18FF)
        r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, 3.0)
        if selected then
          r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, UI_THEME.accent or 0x1EFF5EFF, 3.0, 0, 1.4)
        end
      end
      local tw, th = r.ImGui_CalcTextSize(ctx, name)
      local text_col = selected and (UI_THEME.accent_hvr or 0x62FF8AFF) or (UI_THEME.text or 0xE8EEEAFF)
      r.ImGui_DrawList_AddText(dl, x0 + 4, y0 + (row_h - th) * 0.5, text_col, name)
      if r.ImGui_IsItemClicked(ctx, 0) then
        chosen = name
      end
    end
    if chosen then
      seq_commit_region_rename(chosen)
    end
    r.ImGui_End(ctx)
  end
  if style_cols > 0 then
    r.ImGui_PopStyleColor(ctx, style_cols)
  end
  if style_vars > 0 then
    r.ImGui_PopStyleVar(ctx, style_vars)
  end
end

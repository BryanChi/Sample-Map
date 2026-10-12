-- Sample Map Browser module: groove
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- ===== Groove templates =================================================
-- A groove nudges each grid cell off the rigid metronomic grid so beats feel
-- more human. Each preset is a 16-slot table (one bar of 1/16 notes in 4/4).
-- Each slot value is a timing offset expressed as a FRACTION OF A 1/16 NOTE:
--   positive = lay the hit back (behind the beat), negative = push it ahead.
-- The values are grounded in the classic "swing %" convention used by the
-- LinnDrum / Akai MPC / Logic / Ableton groove pools, where 50% is straight
-- and a given % delays the off-beat. Converting that to a fraction of a 1/16:
--   1/16 swing off-note delay  = (pct - 50) / 50      (delays the e & a)
--   1/8  swing off-note delay  = (pct - 50) / 25      (delays the "and")
SEQ_SIXTEENTH_QN = 0.25

function seq_groove_swing16(amount)
  -- Delay every other 1/16 (the "e" and "a" of each beat).
  local t = {}
  for i = 0, 15 do
    t[i + 1] = (i % 2 == 1) and amount or 0.0
  end
  return t
end

function seq_groove_swing8(amount)
  -- Delay the off-8th (the "and") of each beat.
  local t = {}
  for i = 0, 15 do
    t[i + 1] = (i % 4 == 2) and amount or 0.0
  end
  return t
end

function seq_groove_uniform(amount)
  local t = {}
  for i = 0, 15 do t[i + 1] = amount end
  return t
end

-- Deterministic per-slot jitter so "humanized" feels are stable across renders
-- (same groove always produces the same offsets) yet uneven like a real player.
function seq_groove_jitter(base, seed, depth)
  local t = {}
  local s = (seed or 1) % 2147483648
  for i = 0, 15 do
    s = (s * 1103515245 + 12345) % 2147483648
    local centered = (s / 2147483648.0) * 2.0 - 1.0
    local b = base and base[i + 1] or 0.0
    t[i + 1] = b + centered * depth
  end
  return t
end

-- Hand-built lopsided "drunk" feel inspired by J Dilla's off-grid timing:
-- swung 1/16s with the backbeats laid back and a few subdivisions pulled early.
SEQ_GROOVE_DILLA = {
  0.00, 0.30, -0.04, 0.22,
  0.06, 0.34,  0.02, 0.20,
 -0.02, 0.32,  0.04, 0.24,
  0.08, 0.30,  0.00, 0.18,
}

-- Boom-bap: moderate 1/16 swing with the snare backbeats (beats 2 & 4) dragged.
SEQ_GROOVE_BOOM_BAP = {
  0.00, 0.18, 0.00, 0.18,
  0.07, 0.18, 0.00, 0.18,
  0.00, 0.18, 0.00, 0.18,
  0.07, 0.18, 0.00, 0.18,
}

SEQ_GROOVE_PRESETS = {
  off              = { steps = nil },
  swing16_54       = { steps = seq_groove_swing16(0.08) },
  swing16_58       = { steps = seq_groove_swing16(0.16) },
  swing16_60       = { steps = seq_groove_swing16(0.20) },
  swing16_62       = { steps = seq_groove_swing16(0.24) },
  swing16_66       = { steps = seq_groove_swing16(0.333) },
  swing16_71       = { steps = seq_groove_swing16(0.42) },
  swing8_56        = { steps = seq_groove_swing8(0.24) },
  swing8_62        = { steps = seq_groove_swing8(0.48) },
  mpc_60           = { steps = seq_groove_jitter(seq_groove_swing16(0.20), 7321, 0.04) },
  mpc_66           = { steps = seq_groove_jitter(seq_groove_swing16(0.333), 5189, 0.05) },
  linn             = { steps = seq_groove_jitter(seq_groove_swing16(0.16), 2654, 0.03) },
  dilla            = { steps = SEQ_GROOVE_DILLA },
  boom_bap         = { steps = SEQ_GROOVE_BOOM_BAP },
  laid_back        = { steps = seq_groove_uniform(0.06) },
  pushed           = { steps = seq_groove_uniform(-0.06) },
  quintuplet       = { steps = seq_groove_swing16(0.20) },
  septuplet        = { steps = seq_groove_swing16(0.14) },
  shuffle_triplet  = { steps = seq_groove_swing8(0.667) },
  human_tight      = { steps = seq_groove_jitter(nil, 9001, 0.05) },
  human_loose      = { steps = seq_groove_jitter(nil, 4242, 0.13) },
}

-- Display order for the groove picker (headers + selectable rows).
SEQ_GROOVE_ORDER = {
  { key = "off",             label = "Straight (no groove)",        desc = "Rigid grid, no timing offset." },
  { header = "1/16 Swing" },
  { key = "swing16_54",      label = "1/16 Swing 54% (subtle)",     desc = "Barely-there bounce on the off 1/16s." },
  { key = "swing16_58",      label = "1/16 Swing 58% (light)",      desc = "Light, modern 1/16 swing." },
  { key = "swing16_60",      label = "1/16 Swing 60% (medium)",     desc = "Classic medium 1/16 swing." },
  { key = "swing16_62",      label = "1/16 Swing 62% (classic)",    desc = "The classic Logic 16D feel." },
  { key = "swing16_66",      label = "1/16 Swing 66% (triplet)",    desc = "Hard, triplet-based 1/16 swing." },
  { key = "swing16_71",      label = "1/16 Swing 71% (extreme)",    desc = "Heavily lopsided, near dotted feel." },
  { header = "1/8 Swing" },
  { key = "swing8_56",       label = "1/8 Swing 56% (light)",       desc = "Light jazz/house 1/8 swing." },
  { key = "swing8_62",       label = "1/8 Swing 62% (medium)",      desc = "Stronger 1/8 swing." },
  { header = "Hardware Feel" },
  { key = "mpc_60",          label = "MPC 60% (humanized)",         desc = "MPC-style 1/16 swing with hardware jitter." },
  { key = "mpc_66",          label = "MPC 66% (humanized)",         desc = "Harder MPC triplet swing with jitter." },
  { key = "linn",            label = "LinnDrum 1/16",               desc = "Vintage LinnDrum-style light swing + slop." },
  { header = "Hip-Hop / Pocket" },
  { key = "dilla",           label = "Dilla (drunk / lopsided)",    desc = "Off-grid, backbeats dragged, subdivisions pulled early." },
  { key = "boom_bap",        label = "Boom Bap (laid-back snare)",  desc = "Swung 1/16s with the snare dragged behind." },
  { key = "laid_back",       label = "Laid Back (behind the beat)", desc = "Everything nudged slightly late for a relaxed pocket." },
  { key = "pushed",          label = "Pushed (ahead of the beat)",  desc = "Everything nudged slightly early for urgency." },
  { header = "Exotic" },
  { key = "quintuplet",      label = "Quintuplet 3:2 (60%)",        desc = "Angular quintuplet-based swing." },
  { key = "septuplet",       label = "Septuplet 4:3 (57%)",         desc = "Hip, subtle lopsided septuplet feel." },
  { key = "shuffle_triplet", label = "Triplet Shuffle (swung 1/8)", desc = "Full triplet shuffle on the 1/8s." },
  { header = "Human" },
  { key = "human_tight",     label = "Humanize (tight)",            desc = "Small random offsets, hand-played but tight." },
  { key = "human_loose",     label = "Humanize (loose)",            desc = "Looser random offsets, sloppier human feel." },
}

function seq_groove_exists(groove_key)
  return type(groove_key) == "string" and SEQ_GROOVE_PRESETS[groove_key] ~= nil
end

function normalize_seq_groove(groove_key)
  if seq_groove_exists(groove_key) then
    return groove_key
  end
  return "off"
end

function get_seq_groove_label(groove_key)
  groove_key = normalize_seq_groove(groove_key)
  for _, entry in ipairs(SEQ_GROOVE_ORDER) do
    if entry.key == groove_key then
      return entry.label
    end
  end
  return "Straight"
end

function get_seq_groove_chip_label(groove_key)
  groove_key = normalize_seq_groove(groove_key)
  if groove_key == "off" then
    return "Straight"
  end
  local label = get_seq_groove_label(groove_key)
  return (label:gsub("%s*%b()%s*$", ""))
end

function get_seq_region_groove(region)
  if type(region) == "table" then
    return normalize_seq_groove(region.groove)
  end
  return "off"
end

function get_seq_region_pattern_label(region)
  if region and type(region.style_key) == "string" and region.style_key ~= "" then
    if seq_gen_style_exists(region.style_key) then
      return get_seq_gen_style_label(region.style_key)
    end
    return seq_gmd_pretty_label(region.style_key)
  end
  return get_seq_gen_style_label(state.seq_gen_style)
end

-- Old projects stored one groove for the whole sequencer. Copy that onto any
-- region that does not yet have its own feel so existing timing is preserved.
function migrate_seq_region_grooves()
  local fallback = normalize_seq_groove(state.seq_groove)
  for _, region in ipairs(state.seq_regions or {}) do
    if type(region) == "table" then
      if region.groove == nil or region.groove == "" then
        region.groove = fallback
      else
        region.groove = normalize_seq_groove(region.groove)
      end
    end
  end
end

function set_seq_region_groove(region, groove_key)
  if not region then
    return false
  end
  groove_key = normalize_seq_groove(groove_key)
  if get_seq_region_groove(region) == groove_key then
    return false
  end
  local own = seq_undo_own_begin("Set region groove")
  region.groove = groove_key
  state.seq_groove = groove_key
  save_config()
  sync_seq_region(region)
  if own then
    end_seq_undo("Set region groove")
  end
  return true
end

-- Timing offset (in QN) for a grid cell at the given absolute musical position.
-- The bar is treated as 16 x 1/16 in 4/4; the cell is mapped to its nearest
-- 1/16 slot so the groove lines up with project bars regardless of grid size.
-- groove_key is the region's feel; omitting it applies no groove.
function seq_groove_offset_qn(abs_qn, groove_key)
  local preset = SEQ_GROOVE_PRESETS[normalize_seq_groove(groove_key)]
  if not preset or not preset.steps then
    return 0.0
  end
  local sixteenth = math.floor((abs_qn / SEQ_SIXTEENTH_QN) + 0.5)
  local idx = sixteenth % 16
  if idx < 0 then idx = idx + 16 end
  local frac = preset.steps[idx + 1] or 0.0
  return frac * SEQ_SIXTEENTH_QN
end


function seq_tag_uses_sustain_length(tag)
  if not tag then
    return false
  end
  local tl = string.lower(tostring(tag))
  if SEQ_SUSTAIN_TAGS[tl] then
    return true
  end
  local cat = categorize_tags(tag)
  return cat == "melodic" or cat == "loop"
end

function seq_note_uses_sustain_length(slot, resolved_sample)
  if slot and SEQ_SUSTAIN_ROLES[infer_seq_track_role(slot)] then
    return true
  end
  if slot and seq_tag_uses_sustain_length(slot.sample_tag) then
    return true
  end
  if resolved_sample and type(resolved_sample.tags) == "table" then
    for _, tag in ipairs(resolved_sample.tags) do
      if seq_tag_uses_sustain_length(tag) then
        return true
      end
    end
  end
  if resolved_sample and resolved_sample.path then
    if detect_loop_or_oneshot(resolved_sample.path, resolved_sample.folder or "", resolved_sample.playback_type) == "loop" then
      return true
    end
  end
  return false
end

function seq_note_trigger_qn(region, step_idx, note, grid_qn)
  local cell_start_qn = seq_note_abs_qn(region, note, step_idx, grid_qn)
  local offset_qn = (note and note.offset_qn) or 0.0
  local groove_qn = seq_groove_offset_qn(cell_start_qn, get_seq_region_groove(region))
  local qn = cell_start_qn + groove_qn + offset_qn
  if qn < 0.0 then
    qn = 0.0
  end
  return qn
end

function seq_next_note_trigger_qn(region, pattern, track_id, step_idx, grid_qn, note)
  if not region then
    return 0.0
  end
  local track_notes = get_track_note_table(pattern, track_id, false)
  if not track_notes then
    return (region.start_qn or 0.0) + get_seq_region_length_qn(region)
  end

  local start_qn = seq_note_trigger_qn(region, step_idx, note, grid_qn)
  local next_qn = nil
  local next_key = nil
  for sk, nnote in pairs(track_notes) do
    if type(nnote) == "table" and nnote.enabled ~= false then
      local qn = seq_note_trigger_qn(region, sk, nnote, grid_qn)
      if qn > start_qn + 1e-9 and (not next_qn or qn < next_qn) then
        next_qn = qn
        next_key = sk
      end
    end
  end

  if next_key then
    return seq_note_trigger_qn(region, next_key, track_notes[next_key] or track_notes[tostring(next_key)], grid_qn)
  end

  return (region.start_qn or 0.0) + get_seq_region_length_qn(region)
end

function seq_sustain_note_length_qn(region, pattern, track_id, step_idx, note, grid_qn)
  local start_qn = seq_note_trigger_qn(region, step_idx, note, grid_qn)
  local end_qn = seq_next_note_trigger_qn(region, pattern, track_id, step_idx, grid_qn, note)
  return math.max((grid_qn or 0.25) * 0.25, end_qn - start_qn)
end

seq_sample_len_sec_cache = {}
seq_defer_item_updates = false

-- Shared PCM prototypes while rewriting many takes of the same file (swap, region sync).
seq_pcm_take_src_cache = nil
seq_pcm_take_src_depth = 0
seq_path_exists_cache = {}

function seq_path_exists(path)
  if not path or path == "" then
    return false
  end
  local cached = seq_path_exists_cache[path]
  if cached ~= nil then
    return cached
  end
  local ok = r.file_exists(path) and true or false
  seq_path_exists_cache[path] = ok
  return ok
end

function seq_pcm_take_src_begin()
  seq_pcm_take_src_depth = (seq_pcm_take_src_depth or 0) + 1
  if seq_pcm_take_src_depth == 1 then
    seq_pcm_take_src_cache = {}
  end
end

function seq_pcm_take_src_end()
  local depth = (seq_pcm_take_src_depth or 1) - 1
  if depth < 0 then
    depth = 0
  end
  seq_pcm_take_src_depth = depth
  if depth > 0 then
    return
  end
  local cache = seq_pcm_take_src_cache
  seq_pcm_take_src_cache = nil
  if type(cache) ~= "table" or not r.PCM_Source_Destroy then
    return
  end
  for _, proto in pairs(cache) do
    if proto then
      r.PCM_Source_Destroy(proto)
    end
  end
end

function seq_pcm_take_src_get(path)
  if not path or path == "" then
    return nil
  end
  local cache = seq_pcm_take_src_cache
  if type(cache) == "table" and r.PCM_Source_Duplicate then
    local proto = cache[path]
    if proto == nil then
      proto = r.PCM_Source_CreateFromFile(path)
      cache[path] = proto or false
    end
    if proto then
      local copy = r.PCM_Source_Duplicate(proto)
      if copy then
        return copy
      end
    elseif proto == false then
      return nil
    end
  end
  return r.PCM_Source_CreateFromFile(path)
end

function seq_sample_source_length_sec(path, sample)
  local map_dur = sample_map_duration(sample)
  if map_dur > 0 then
    return map_dur
  end
  if not path or path == "" then
    return nil
  end
  -- Lengths are cached; a failed lookup (offline/unreadable file) is cached as
  -- a negative number holding its time and retried after 5 s. The cache is
  -- cleared when folder availability changes.
  local cached = seq_sample_len_sec_cache[path]
  local now = r.time_precise()
  if cached ~= nil then
    if cached > 0 then
      return cached
    end
    if now - (-cached) < 5.0 then
      return nil
    end
  end
  local length_sec = nil
  if seq_path_exists(path) then
    local src = r.PCM_Source_CreateFromFile(path)
    if src then
      length_sec = pick_number({ r.GetMediaSourceLength(src) }, 0.0)
      if r.PCM_Source_Destroy then
        r.PCM_Source_Destroy(src)
      end
    end
  end
  if length_sec and length_sec > 0 then
    seq_sample_len_sec_cache[path] = length_sec
    return length_sec
  end
  seq_sample_len_sec_cache[path] = -math.max(now, 1e-6)
  return nil
end

-- at_qn (optional): project QN where the sample starts; converts through the
-- tempo map at that position instead of assuming the tempo at QN 0.
function seq_sample_length_qn(path, sample, at_qn)
  local length_sec = seq_sample_source_length_sec(path, sample)
  if not length_sec or length_sec <= 0 then
    return nil
  end
  if type(at_qn) == "number" and r.TimeMap2_timeToQN then
    local t0 = qn_to_time(at_qn)
    if t0 then
      local end_qn = r.TimeMap2_timeToQN(0, t0 + length_sec)
      if end_qn and end_qn > at_qn then
        return end_qn - at_qn
      end
    end
  end
  local sec_per = seq_sec_per_qn
  if not sec_per or sec_per <= 0 then
    local t0 = qn_to_time(0)
    local t1 = qn_to_time(1)
    if not t0 or not t1 or t1 <= t0 then
      return nil
    end
    sec_per = t1 - t0
    seq_sec_per_qn = sec_per
  end
  return length_sec / sec_per
end

SEQ_STRETCH_MIN = 0.25
SEQ_STRETCH_MAX = 4.0
SEQ_START_MAX = 0.99

SEQ_DRUM_STRETCH_ROLES = {
  kick = true, snare = true, clap = true, rim = true, tom = true,
  hat = true, perc = true, ["808"] = true, crash = true, ride = true,
}

function seq_sample_is_drum_sound(sample)
  if not sample then
    return false
  end
  if sample.sample_type == "Drum" then
    return true
  end
  local tags = sample.tags
  if type(tags) == "table" then
    for _, tag in ipairs(tags) do
      if DRUM_TRANSIENT_TAGS[string.lower(tostring(tag))] then
        return true
      end
    end
  end
  return false
end

function seq_stretch_target_is_drum(sample, slot)
  if seq_sample_is_drum_sound(sample) then
    return true
  end
  if slot and SEQ_DRUM_STRETCH_ROLES[infer_seq_track_role(slot)] then
    return true
  end
  return false
end

function seq_rubber_band_pitch_mode()
  if state.seq_rb_pitch_mode_ready then
    return state.seq_rb_pitch_mode
  end
  state.seq_rb_pitch_mode_ready = true
  state.seq_rb_pitch_mode = nil
  if not r.EnumPitchShiftModes then
    return nil
  end
  local best_mode, best_score = nil, -1
  local i = 0
  while i < 64 do
    local a, b = r.EnumPitchShiftModes(i)
    if a == false and (b == nil or b == "") then
      break
    end
    local name = (type(a) == "string" and a) or (type(b) == "string" and b) or nil
    if name then
      local lower = string.lower(name)
      if lower:find("rubber band", 1, true) then
        local score = 1
        if lower:find("library", 1, true) then
          score = 3
        end
        if score > best_score then
          best_mode, best_score = i, score
        end
      end
    end
    i = i + 1
  end
  if best_mode then
    -- Default Rubber Band Library submode (0).
    state.seq_rb_pitch_mode = (best_mode << 16)
  end
  return state.seq_rb_pitch_mode
end

function seq_apply_drum_rubber_band_stretch(take, stretch, sample, slot)
  if not take then
    return
  end
  stretch = tonumber(stretch) or 1.0
  if math.abs(stretch - 1.0) <= 0.0001 then
    return
  end
  if not seq_stretch_target_is_drum(sample, slot) then
    return
  end
  local mode = seq_rubber_band_pitch_mode()
  if not mode then
    return
  end
  r.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", mode)
end

function seq_note_stretch_amount(note, hit_idx)
  local v = tonumber(seq_note_param_value(note, "stretch", hit_idx) or (note and note.stretch)) or 1.0
  if v < SEQ_STRETCH_MIN then return SEQ_STRETCH_MIN end
  if v > SEQ_STRETCH_MAX then return SEQ_STRETCH_MAX end
  return v
end

function seq_note_start_frac(note, hit_idx)
  local v = tonumber(seq_note_param_value(note, "start", hit_idx) or (note and note.start)) or 0.0
  if v < 0.0 then return 0.0 end
  if v > SEQ_START_MAX then return SEQ_START_MAX end
  return v
end

-- Remaining source after Start, then Stretch can shrink it but not grow past
-- the unstretched remaining length (so a longer stretch never pushes the end).
function seq_source_play_cap_qn(length_qn, path, sample, note, hit_idx, at_qn)
  local src_qn = seq_sample_length_qn(path, sample, at_qn)
  if not src_qn or src_qn <= 0 then
    return length_qn
  end
  local remaining = src_qn * (1.0 - seq_note_start_frac(note, hit_idx))
  local stretch = seq_note_stretch_amount(note, hit_idx)
  local cap = math.min(remaining, remaining * stretch)
  if not length_qn then
    return math.max(0.001, cap)
  end
  return math.min(length_qn, math.max(0.001, cap))
end

function seq_cap_length_to_sample_qn(length_qn, path, sample, note, hit_idx, at_qn)
  if note then
    return seq_source_play_cap_qn(length_qn, path, sample, note, hit_idx, at_qn)
  end
  local cap_qn = seq_sample_length_qn(path, sample, at_qn)
  if cap_qn and cap_qn > 0 then
    return math.min(length_qn, cap_qn)
  end
  return length_qn
end

function seq_region_end_qn(region)
  return (region and region.start_qn or 0.0) + get_seq_region_length_qn(region)
end

-- Auto sample sustain stops at the region end. Explicit decay_qn may pass it.
function seq_cap_length_to_region_end_qn(length_qn, region, step_idx, note, grid_qn)
  if not region or not length_qn or length_qn <= 0 then
    return length_qn
  end
  local start_qn = seq_note_trigger_qn(region, step_idx, note, grid_qn)
  local remain = seq_region_end_qn(region) - start_qn
  if remain <= 0 then
    return length_qn
  end
  return math.min(length_qn, remain)
end

function seq_note_length_qn_for_copy(region, slot, note, step_key, grid_qn)
  if type(note) ~= "table" then
    return nil
  end
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  if seq_note_has_stutter_span(note, grid_qn) then
    return seq_stutter_span_qn(note, grid_qn)
  end
  local decay_qn = tonumber(note.decay_qn)
  if type(decay_qn) == "number" and decay_qn > 1e-9 then
    return decay_qn
  end
  if not region or not slot then
    return nil
  end
  local _, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot.id, step_key)
  local pattern = get_seq_pattern(region.pattern_id, false)
  return seq_effective_note_length_qn(
    region, pattern, slot, slot.id, step_key, note, resolved_sample, grid_qn
  )
end

-- Copy/move keeps the source length when that placement would cross the region end.
function seq_keep_copied_note_over_region(note, length_qn, dest_region, dest_rel)
  if type(note) ~= "table" or not dest_region then
    return
  end
  length_qn = tonumber(length_qn)
  if not length_qn or length_qn <= 1e-9 or seq_note_has_stutter_span(note) then
    return
  end
  local decay_qn = tonumber(note.decay_qn)
  if type(decay_qn) == "number" and decay_qn > 1e-9 then
    return
  end
  local dest_start = (dest_region.start_qn or 0.0) + (tonumber(dest_rel) or 0.0) + (note.offset_qn or 0.0)
  if dest_start + length_qn > seq_region_end_qn(dest_region) + 1e-9 then
    note.decay_qn = length_qn
  end
end

function seq_gap_to_next_hit_qn(region, pattern, track_id, step_idx, note, grid_qn)
  if not region then
    return nil
  end
  local start_qn = seq_note_trigger_qn(region, step_idx, note, grid_qn)
  local end_qn = seq_next_note_trigger_qn(region, pattern, track_id, step_idx, grid_qn, note)
  local region_end = (region.start_qn or 0.0) + get_seq_region_length_qn(region)
  if math.abs(end_qn - region_end) <= 1e-9 then
    return nil
  end
  return math.max((grid_qn or 0.25) * 0.05, end_qn - start_qn)
end

function seq_effective_note_length_qn(region, pattern, slot, track_id, step_idx, note, resolved_sample, grid_qn, hit_idx)
  grid_qn = grid_qn or state.seq_grid_qn or 0.25
  local resolved_path = (resolved_sample and resolved_sample.path)
    or (note and note.frozen_sample_path)
    or (note and note.sample_path)
    or (slot and slot.sample_path)
  local stutter_count = seq_stutter_count(note)
  if stutter_count > 1 then
    local _, _, slice_qn = seq_stutter_hit_span(note, hit_idx or 1, grid_qn)
    if not slice_qn or slice_qn <= 1e-9 then
      slice_qn = (seq_stutter_span_qn(note, grid_qn) or grid_qn) / stutter_count
    end
    return seq_cap_length_to_sample_qn(slice_qn * 0.98, resolved_path, resolved_sample, note)
  end

  local at_qn = region and step_idx ~= nil and seq_note_trigger_qn(region, step_idx, note, grid_qn) or nil
  local sample_qn = seq_sample_length_qn(resolved_path, resolved_sample, at_qn)
  if not sample_qn or sample_qn <= 0 then
    sample_qn = grid_qn
  end
  -- Decay mode stores an explicit playback length. Ignore the default
  -- length_qn (one grid cell) which is only a stutter-span placeholder.
  local decay_qn = tonumber(note and note.decay_qn)
  if type(decay_qn) == "number" and decay_qn > 1e-9 then
    return seq_cap_length_to_sample_qn(math.max(grid_qn * 0.05, decay_qn), resolved_path, resolved_sample, note, nil, at_qn)
  end
  -- Default: full effective length, cropped so it does not overlap the next hit.
  -- Per-track overlap lets the sample ring out over later notes, unless a
  -- copy/move asked to keep items butted against the next start.
  if state.seq_force_item_crop or not (slot and slot.overlap) then
    local gap_qn = seq_gap_to_next_hit_qn(region, pattern, track_id, step_idx, note, grid_qn)
    if gap_qn then
      sample_qn = math.min(sample_qn, gap_qn)
    end
  end
  -- Auto sustain stays inside the region. Explicit decay_qn may cross it.
  sample_qn = seq_cap_length_to_region_end_qn(sample_qn, region, step_idx, note, grid_qn)
  return seq_cap_length_to_sample_qn(sample_qn, resolved_path, resolved_sample, note, nil, at_qn)
end

SEQ_FADE_SHAPE_COUNT = 7
SEQ_FADE_SHAPE_PX = 14.0
SEQ_FADE_SHAPE_NAMES = {
  [0] = "Linear",
  [1] = "Equal power",
  [2] = "Fast start",
  [3] = "Fast end",
  [4] = "Slow start",
  [5] = "Slow end",
  [6] = "Bezier",
}

function seq_fade_shape_clamp(shape)
  shape = math.floor(tonumber(shape) or 0)
  if shape < 0 then return 0 end
  if shape > 6 then return 6 end
  return shape
end

function seq_fade_shape_name(shape)
  return SEQ_FADE_SHAPE_NAMES[seq_fade_shape_clamp(shape)] or "Linear"
end

SEQ_FADE_CURVE_PX = 52.0
SEQ_FADE_AXIS_PX = 8.0

function seq_fade_curve_clamp(curve)
  curve = tonumber(curve) or 0.0
  if curve < -1.0 then return -1.0 end
  if curve > 1.0 then return 1.0 end
  return curve
end

-- Warp 0..1 by native D_FADEINDIR / D_FADEOUTDIR (-1..1).
function seq_fade_apply_dir(t, dir)
  if t <= 0 then return 0.0 end
  if t >= 1 then return 1.0 end
  dir = seq_fade_curve_clamp(dir)
  if math.abs(dir) < 0.0001 then
    return t
  end
  local k = dir * 2.4
  if k > 0 then
    local e = math.exp(k)
    return (math.exp(k * t) - 1.0) / (e - 1.0)
  end
  k = -k
  local e = math.exp(k)
  return 1.0 - (math.exp(k * (1.0 - t)) - 1.0) / (e - 1.0)
end

-- Native REAPER item-fade shapes (C_FADEINSHAPE / C_FADEOUTSHAPE 0..6).
-- t is 0 at the silent edge and 1 at full level. dir is D_FADEINDIR / D_FADEOUTDIR.
function seq_native_fade_gain(t, shape, dir)
  if t <= 0 then return 0.0 end
  if t >= 1 then return 1.0 end
  shape = seq_fade_shape_clamp(shape)
  local g
  if shape == 1 then
    g = math.sin(t * math.pi * 0.5)
  elseif shape == 2 then
    g = math.sqrt(t)
  elseif shape == 3 then
    g = t * t
  elseif shape == 4 then
    g = t * t * t
  elseif shape == 5 then
    g = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
  elseif shape == 6 then
    g = t * t * (3.0 - 2.0 * t)
  else
    g = t
  end
  return seq_fade_apply_dir(g, dir)
end

function seq_qn_delta_to_sec(start_qn, delta_qn)
  delta_qn = tonumber(delta_qn) or 0.0
  if delta_qn <= 0 then
    return 0.0
  end
  local t0 = qn_to_time(start_qn or 0.0)
  local t1 = qn_to_time((start_qn or 0.0) + delta_qn)
  if t0 and t1 and t1 > t0 then
    return t1 - t0
  end
  local spq = seq_sec_per_qn
  if not spq or spq <= 0 then
    local a = qn_to_time(0)
    local b = qn_to_time(1)
    if a and b and b > a then
      spq = b - a
    end
  end
  return delta_qn * (spq or 0.5)
end

function seq_note_fade_qn(note, which)
  if type(note) ~= "table" then
    return 0.0
  end
  local v = tonumber(which == "in" and note.fade_in_qn or note.fade_out_qn) or 0.0
  if v < 0 then return 0.0 end
  return v
end

function seq_note_fade_shape(note, which)
  if type(note) ~= "table" then
    return 0
  end
  return seq_fade_shape_clamp(which == "in" and note.fade_in_shape or note.fade_out_shape)
end

function seq_note_fade_curve(note, which)
  if type(note) ~= "table" then
    return 0.0
  end
  return seq_fade_curve_clamp(which == "in" and note.fade_in_curve or note.fade_out_curve)
end

function seq_note_clear_fade_side(note, which)
  if type(note) ~= "table" then
    return false
  end
  local key_qn = (which == "in") and "fade_in_qn" or "fade_out_qn"
  local key_shape = (which == "in") and "fade_in_shape" or "fade_out_shape"
  local key_curve = (which == "in") and "fade_in_curve" or "fade_out_curve"
  local changed = false
  if note[key_qn] ~= nil then note[key_qn] = nil; changed = true end
  if note[key_shape] ~= nil then note[key_shape] = nil; changed = true end
  if note[key_curve] ~= nil then note[key_curve] = nil; changed = true end
  return changed
end

function seq_clamp_note_fades(note, length_qn)
  if type(note) ~= "table" then
    return
  end
  length_qn = math.max(0.0, tonumber(length_qn) or 0.0)
  local fade_in = seq_note_fade_qn(note, "in")
  local fade_out = seq_note_fade_qn(note, "out")
  if fade_in + fade_out > length_qn and (fade_in + fade_out) > 1e-9 then
    local scale = math.max(0.0, length_qn * 0.98) / (fade_in + fade_out)
    fade_in = fade_in * scale
    fade_out = fade_out * scale
  end
  if fade_in < 1e-6 then
    seq_note_clear_fade_side(note, "in")
  else
    note.fade_in_qn = fade_in
  end
  if fade_out < 1e-6 then
    seq_note_clear_fade_side(note, "out")
  else
    note.fade_out_qn = fade_out
  end
end

-- Grow `prefer` ("in"/"out") and shrink the opposite fade if they collide.
function seq_push_note_fades(note, length_qn, prefer)
  if type(note) ~= "table" then
    return
  end
  length_qn = math.max(0.0, tonumber(length_qn) or 0.0)
  local min_keep = math.max(0.0, math.min(0.02, length_qn * 0.02))
  local fade_in = seq_note_fade_qn(note, "in")
  local fade_out = seq_note_fade_qn(note, "out")
  if prefer == "in" then
    fade_in = math.min(fade_in, math.max(0.0, length_qn - min_keep))
    local room = math.max(0.0, length_qn - fade_in - min_keep)
    if fade_out > room then
      fade_out = room
    end
  else
    fade_out = math.min(fade_out, math.max(0.0, length_qn - min_keep))
    local room = math.max(0.0, length_qn - fade_out - min_keep)
    if fade_in > room then
      fade_in = room
    end
  end
  if fade_in < 1e-6 then
    seq_note_clear_fade_side(note, "in")
  else
    note.fade_in_qn = fade_in
  end
  if fade_out < 1e-6 then
    seq_note_clear_fade_side(note, "out")
  else
    note.fade_out_qn = fade_out
  end
end

function seq_note_set_fade(note, which, fade_qn, shape)
  if type(note) ~= "table" then
    return false
  end
  fade_qn = math.max(0.0, tonumber(fade_qn) or 0.0)
  local key_qn = (which == "in") and "fade_in_qn" or "fade_out_qn"
  local key_shape = (which == "in") and "fade_in_shape" or "fade_out_shape"
  local changed = false
  if fade_qn < 1e-6 then
    if seq_note_clear_fade_side(note, which) then
      changed = true
    end
  elseif math.abs((tonumber(note[key_qn]) or 0.0) - fade_qn) > 1e-9 then
    note[key_qn] = fade_qn
    changed = true
  end
  if fade_qn >= 1e-6 and shape ~= nil then
    shape = seq_fade_shape_clamp(shape)
    if note[key_shape] ~= shape then
      note[key_shape] = shape
      changed = true
    end
  end
  return changed
end

function seq_note_set_fade_curve(note, which, curve)
  if type(note) ~= "table" then
    return false
  end
  if seq_note_fade_qn(note, which) < 1e-6 then
    return false
  end
  curve = seq_fade_curve_clamp(curve)
  local key = (which == "in") and "fade_in_curve" or "fade_out_curve"
  local prev = seq_fade_curve_clamp(note[key])
  if math.abs(prev - curve) < 0.0001 then
    return false
  end
  if math.abs(curve) < 0.0001 then
    note[key] = nil
  else
    note[key] = curve
  end
  return true
end

function seq_apply_native_item_fades(item, item_len, fade_in_sec, fade_out_sec, fade_in_shape, fade_out_shape, opts)
  if not item or not item_len or item_len <= 0.0001 then
    return
  end
  opts = opts or {}
  fade_in_sec = math.max(0.0, tonumber(fade_in_sec) or 0.0)
  fade_out_sec = math.max(0.0, tonumber(fade_out_sec) or 0.0)
  if fade_in_sec + fade_out_sec > item_len - 0.0005 then
    local need = fade_in_sec + fade_out_sec + 0.0005
    if need > 0 then
      local scale = math.max(0.0, (item_len - 0.0005) / need)
      fade_in_sec = fade_in_sec * scale
      fade_out_sec = fade_out_sec * scale
    end
  end
  if opts.keep_existing then
    local cur_in = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0.0
    local cur_out = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") or 0.0
    if fade_in_sec < cur_in then fade_in_sec = cur_in end
    if fade_out_sec < cur_out then fade_out_sec = cur_out end
  end
  r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in_sec)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out_sec)
  pcall(function()
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", 0)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", 0)
  end)
  if fade_in_sec > 0 then
    pcall(function()
      r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", seq_fade_shape_clamp(fade_in_shape))
      r.SetMediaItemInfo_Value(item, "D_FADEINDIR", seq_fade_curve_clamp(opts.fade_in_curve))
    end)
  end
  if fade_out_sec > 0 then
    pcall(function()
      r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", seq_fade_shape_clamp(fade_out_shape))
      r.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", seq_fade_curve_clamp(opts.fade_out_curve))
    end)
  end
end

function seq_apply_note_native_fades(item, item_len, note, hit_start_qn, apply_in, apply_out, opts)
  if not item then
    return
  end
  local fade_in_qn = (apply_in ~= false) and seq_note_fade_qn(note, "in") or 0.0
  local fade_out_qn = (apply_out ~= false) and seq_note_fade_qn(note, "out") or 0.0
  local fade_in_sec = seq_qn_delta_to_sec(hit_start_qn, fade_in_qn)
  local fade_out_sec = 0.0
  if fade_out_qn > 0 then
    local hit_len_qn = 0.0
    local t0 = qn_to_time(hit_start_qn)
    local t1 = t0 and (t0 + (item_len or 0))
    if t0 and t1 then
      local q1 = time_to_qn(t1)
      if q1 then
        hit_len_qn = math.max(0.0, q1 - (hit_start_qn or 0.0))
      end
    end
    fade_out_sec = seq_qn_delta_to_sec((hit_start_qn or 0.0) + math.max(0.0, hit_len_qn - fade_out_qn), fade_out_qn)
  end
  seq_apply_native_item_fades(
    item, item_len, fade_in_sec, fade_out_sec,
    seq_note_fade_shape(note, "in"), seq_note_fade_shape(note, "out"),
    {
      keep_existing = opts and opts.keep_existing,
      fade_in_curve = (apply_in ~= false) and seq_note_fade_curve(note, "in") or 0.0,
      fade_out_curve = (apply_out ~= false) and seq_note_fade_curve(note, "out") or 0.0,
    }
  )
end

function seq_is_decay_mode()
  return state.seq_note_edit_mode == "decay"
end

function seq_is_decay_def(def)
  return def and def.key == "decay"
end

function seq_is_lock_def(def)
  return def and def.key == "locked"
end

function seq_is_vary_def(def)
  return def and def.key == "sample_vary"
end

function seq_is_vary_filter_def(def)
  return def and def.key == "vary_filter"
end

function seq_is_span_overlay_def(def)
  return seq_is_lock_def(def) or seq_is_vary_filter_def(def)
end

function seq_is_stutter_def(def)
  return def and def.key == "stutter"
end

function seq_note_is_locked(note)
  if type(note) ~= "table" then
    return false
  end
  local v = note.locked
  return v == true or v == 1 or v == 1.0
end

function seq_region_step_key(region, cell_qn, step_qn)
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local rel = (cell_qn or 0.0) - ((region and region.start_qn) or 0.0)
  return tostring(math.floor((rel / math.max(1e-9, step_qn)) + 0.5))
end

function seq_pattern_locked_cells(pattern, create)
  if not pattern then
    return nil
  end
  if type(pattern.locked_cells) ~= "table" then
    if not create then
      return nil
    end
    pattern.locked_cells = {}
  end
  return pattern.locked_cells
end

function seq_track_locked_cells(pattern, track_id, create)
  local all = seq_pattern_locked_cells(pattern, create)
  if not all then
    return nil
  end
  local key = tostring(track_id)
  if not all[key] then
    if not create then
      return nil
    end
    all[key] = {}
  end
  return all[key]
end

function seq_cell_is_locked(pattern, track_id, step_key)
  local cells = seq_track_locked_cells(pattern, track_id, false)
  return cells and cells[tostring(step_key)] == true
end

function seq_set_cell_locked(pattern, track_id, step_key, locked)
  if not pattern or track_id == nil or step_key == nil then
    return false
  end
  step_key = tostring(step_key)
  if locked then
    local cells = seq_track_locked_cells(pattern, track_id, true)
    if cells[step_key] then
      return false
    end
    cells[step_key] = true
    return true
  end
  local cells = seq_track_locked_cells(pattern, track_id, false)
  if not cells or not cells[step_key] then
    return false
  end
  cells[step_key] = nil
  local empty = true
  for _ in pairs(cells) do
    empty = false
    break
  end
  if empty then
    local all = seq_pattern_locked_cells(pattern, false)
    if all then
      all[tostring(track_id)] = nil
    end
  end
  return true
end

function seq_merge_locked_cell_seen(seen, pattern, track_id)
  seen = seen or {}
  local cells = seq_track_locked_cells(pattern, track_id, false)
  if not cells then
    return seen
  end
  for step_key, v in pairs(cells) do
    if v then
      local idx = tonumber(step_key)
      if idx then
        seen[idx] = true
      end
    end
  end
  return seen
end

function seq_clear_lock_overlays(note)
  if type(note) ~= "table" then
    return
  end
  note.locked_skip = nil
  note.locked_ghosts = nil
  note.locked_humanize_sec = nil
  note.locked_humanize_pitch = nil
  note.locked_humanize_stretch = nil
  note.locked_humanize_len = nil
  note.locked_humanize_fade = nil
  note.locked_vel = nil
  if type(note.stutter_hits) == "table" then
    for _, hit in pairs(note.stutter_hits) do
      if type(hit) == "table" then
        hit.locked_vel = nil
      end
    end
  end
end

-- Snapshot the current live random result so lock keeps that roll instead of
-- falling back to the unvaried painted note.
function seq_bake_note_random(region, track_id, step_key, note)
  if type(note) ~= "table" then
    return false
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false) or {}
  local slot = seq_find_slot_by_id(track_id)

  local plays = seq_note_probability_roll(
    region, track_id, step_key,
    settings.probability or 1.0,
    settings.probability_seed or settings.seed or 0
  )
  if plays then
    note.locked_skip = nil
  else
    note.locked_skip = true
  end

  local stut = seq_random_stutter_count(note, region, track_id, step_key)
  if stut > (seq_stutter_count(note) or 1) then
    note.stutter = stut
  end

  local count = math.max(1, seq_stutter_count(note))
  local varies = {}
  for i = 1, count do
    varies[i] = seq_random_vary_amount(note, region, track_id, step_key, i)
  end
  local function freeze_into(target, hit_idx, vary)
    if not (vary and vary > 0.000001) then
      return
    end
    local hit_note = seq_note_for_stutter_hit(note, hit_idx)
    local path, sample = seq_resolve_note_sample(hit_note, slot, vary, region, track_id, step_key)
    if path then
      seq_apply_frozen_sample(target, path, sample, seq_note_vary_origin_path(note, slot, region))
    end
    if (tonumber(target.sample_vary) or 0) <= 0.000001 then
      target.sample_vary = vary
    end
  end
  freeze_into(note, 1, varies[1])
  if count > 1 then
    note.stutter_hits = note.stutter_hits or {}
    for i = 1, count do
      local hit = seq_stutter_hit_table(note, i)
      if type(hit) ~= "table" then
        hit = {}
        note.stutter_hits[i] = hit
      end
      freeze_into(hit, i, varies[i])
    end
  end

  for i = 1, count do
    local base = seq_note_param_value(note, "volume", i) or 1.0
    local abs_qn = seq_note_humanize_abs_qn(region, note, step_key, i)
    local vel = seq_humanize_note_velocity(base, region, track_id, step_key, abs_qn, i)
    if count > 1 then
      local hit = seq_stutter_hit_table(note, i)
      if type(hit) ~= "table" then
        note.stutter_hits = note.stutter_hits or {}
        hit = {}
        note.stutter_hits[i] = hit
      end
      hit.locked_vel = vel
    else
      note.locked_vel = vel
    end
  end

  local ms = tonumber(settings.humanize_ms) or 0.0
  local t_lo, t_hi = seq_humanize_effective_time_ms(settings, ms)
  if math.abs(t_lo) > 0.05 or math.abs(t_hi) > 0.05 then
    note.locked_humanize_sec = seq_humanize_time_offset_sec(
      region, track_id, step_key, ms, settings.humanize_seed or settings.seed
    )
  else
    note.locked_humanize_sec = nil
  end
  if seq_settings_humanize_pitch_active(settings) then
    note.locked_humanize_pitch = seq_humanize_pitch_offset(region, track_id, step_key, 1, { force = true })
  else
    note.locked_humanize_pitch = nil
  end
  if seq_settings_humanize_stretch_active(settings) then
    note.locked_humanize_stretch = seq_humanize_stretch_mul(region, track_id, step_key, 1, { force = true })
  else
    note.locked_humanize_stretch = nil
  end
  if seq_settings_humanize_len_active(settings) then
    note.locked_humanize_len = seq_humanize_length_mul(region, track_id, step_key, 1, { force = true })
    if seq_settings_humanize_fade_active(settings) then
      note.locked_humanize_fade = seq_humanize_fade_out_sec(region, track_id, step_key, 1, { force = true })
    else
      note.locked_humanize_fade = nil
    end
  else
    note.locked_humanize_len = nil
    note.locked_humanize_fade = nil
  end

  if seq_settings_ghost_active(settings) then
    local abs_qn = seq_note_abs_qn(region, note, step_key, state.seq_grid_qn or 0.25)
    local ghosts = {}
    local function bake_ghost(which)
      local do_place, close_qn = seq_ghost_should_place(settings, which, region, track_id, step_key, abs_qn)
      if not do_place then
        return
      end
      ghosts[which] = close_qn
      ghosts[which .. "_vol"] = seq_ghost_pick_volume(settings, which, region, track_id, step_key)
      local vary = seq_ghost_vary_amount(settings, which, region, track_id, step_key)
      if vary > 0.000001 then
        ghosts[which .. "_vary"] = vary
        local gpath, gsample = seq_resolve_note_sample(note, slot, vary, region, track_id, step_key)
        if gpath then
          ghosts[which .. "_path"] = gpath
          ghosts[which .. "_name"] = (gsample and (gsample.name or gsample.path)) or basename(gpath)
        end
      end
    end
    bake_ghost("grace")
    bake_ghost("after")
    if ghosts.grace or ghosts.after then
      note.locked_ghosts = ghosts
    else
      note.locked_ghosts = false
    end
  else
    note.locked_ghosts = nil
  end
  return true
end

function seq_apply_lock_to_step(region, track_id, step_key, lock, note)
  if not region or track_id == nil or step_key == nil then
    return false
  end
  step_key = tostring(step_key)
  local pattern = get_seq_pattern(region.pattern_id, true)
  local changed = false
  note = note or get_seq_note(region, track_id, step_key)
  if type(note) == "table" then
    if lock then
      if not seq_note_is_locked(note) then
        seq_bake_note_random(region, track_id, step_key, note)
      end
    elseif seq_note_is_locked(note) then
      seq_clear_lock_overlays(note)
    end
    if seq_set_note_param_value(note, "locked", lock and 1 or 0) then
      changed = true
    end
    if seq_set_cell_locked(pattern, track_id, step_key, false) then
      changed = true
    end
    return changed
  end
  return seq_set_cell_locked(pattern, track_id, step_key, lock and true or false)
end

function seq_pattern_vary_filters(pattern, create)
  if not pattern then
    return nil
  end
  if type(pattern.vary_filters) ~= "table" then
    if not create then
      return nil
    end
    pattern.vary_filters = {}
  end
  return pattern.vary_filters
end

function seq_track_vary_filters(pattern, track_id, create)
  local all = seq_pattern_vary_filters(pattern, create)
  if not all then
    return nil
  end
  local key = tostring(track_id)
  if not all[key] then
    if not create then
      return nil
    end
    all[key] = {}
  end
  return all[key]
end

function seq_get_cell_vary_filter(pattern, track_id, step_key)
  local cells = seq_track_vary_filters(pattern, track_id, false)
  if not cells then
    return nil
  end
  local text = cells[tostring(step_key)]
  if type(text) ~= "string" then
    return nil
  end
  text = seq_trim_text(text)
  if text == "" then
    return nil
  end
  return text
end

function seq_cell_vary_filter(region, track_id, step_key, note)
  if not region or track_id == nil then
    return nil
  end

  local edit = state.seq_vary_filter_edit
  if edit and tostring(edit.track_id) == tostring(track_id)
      and (edit.region_id == nil or edit.region_id == region.id) then
    local live = seq_trim_text(edit.text)
    if live ~= "" and type(edit.start_qn) == "number" and type(edit.step_qn) == "number" then
      local abs_qn = note and seq_note_abs_qn(region, note, step_key, edit.step_qn) or nil
      if type(abs_qn) == "number" then
        local col = math.floor(((abs_qn - edit.start_qn) / math.max(1e-9, edit.step_qn)) + 1e-9)
        if col >= (edit.col_min or 0) and col <= (edit.col_max or 0) then
          return live
        end
      end
    end
  end

  if note and type(note.vary_filter) == "string" then
    local stamped = seq_trim_text(note.vary_filter)
    if stamped ~= "" then
      return stamped
    end
  end

  local pattern = get_seq_pattern(region.pattern_id, false)
  local cells = seq_track_vary_filters(pattern, track_id, false)
  if not cells then
    return nil
  end

  local function hit(key)
    if key == nil then
      return nil
    end
    local text = cells[tostring(key)]
    if type(text) ~= "string" then
      return nil
    end
    text = seq_trim_text(text)
    if text == "" then
      return nil
    end
    return text
  end

  local text = hit(step_key)
  if text then
    return text
  end

  local grid_qn = state.seq_grid_qn or 0.25
  local offsets = {}
  if note and type(note.qn_offset) == "number" then
    offsets[#offsets + 1] = note.qn_offset
    if type(note.offset_qn) == "number" and math.abs(note.offset_qn) > 1e-9 then
      offsets[#offsets + 1] = note.qn_offset + note.offset_qn
    end
  else
    local n = tonumber(step_key)
    if n then
      offsets[#offsets + 1] = n / 192.0
      offsets[#offsets + 1] = n * grid_qn
    end
  end

  for i = 1, #offsets do
    local qn_off = offsets[i]
    text = hit(math.floor(qn_off / grid_qn + 1e-9)) or hit(math.floor(qn_off / grid_qn + 0.5))
    if text then
      return text
    end
    for key, raw in pairs(cells) do
      local idx = tonumber(key)
      if idx and type(raw) == "string" then
        local lo = idx * grid_qn
        if qn_off >= lo - 1e-9 and qn_off < lo + grid_qn - 1e-9 then
          local found = seq_trim_text(raw)
          if found ~= "" then
            return found
          end
        end
      end
    end
  end

  return nil
end

function seq_set_cell_vary_filter(pattern, track_id, step_key, filter_text)
  if not pattern or track_id == nil or step_key == nil then
    return false
  end
  step_key = tostring(step_key)
  filter_text = seq_trim_text(filter_text)
  if filter_text == "" then
    local cells = seq_track_vary_filters(pattern, track_id, false)
    if not cells or cells[step_key] == nil then
      return false
    end
    cells[step_key] = nil
    local empty = true
    for _ in pairs(cells) do
      empty = false
      break
    end
    if empty then
      local all = seq_pattern_vary_filters(pattern, false)
      if all then
        all[tostring(track_id)] = nil
      end
    end
    return true
  end
  local cells = seq_track_vary_filters(pattern, track_id, true)
  if cells[step_key] == filter_text then
    return false
  end
  cells[step_key] = filter_text
  return true
end

function seq_stamp_notes_in_filter_range(region, track_id, col_min, col_max, start_qn, step_qn, filter_text)
  if not region or track_id == nil then
    return false
  end
  local pattern = get_seq_pattern(region.pattern_id, false)
  local notes = get_track_note_table(pattern, track_id, false)
  if not notes then
    return false
  end
  filter_text = seq_trim_text(filter_text)
  if filter_text == "" then
    filter_text = nil
  end
  local changed = false
  for step_key, note in pairs(notes) do
    if type(note) == "table" then
      local qn_off = (type(note.qn_offset) == "number") and note.qn_offset
        or ((tonumber(step_key) or 0) / 192.0)
      local vis = (region.start_qn or 0.0) + qn_off + (note.offset_qn or 0.0)
      local col = math.floor(((vis - (start_qn or 0.0)) / math.max(1e-9, step_qn or 0.25)) + 1e-9)
      if col >= col_min and col <= col_max then
        if note.vary_filter ~= filter_text then
          note.vary_filter = filter_text
          changed = true
        end
        if not seq_note_is_locked(note) and seq_note_has_frozen_sample(note) then
          seq_clear_frozen_sample(note)
          changed = true
        end
      end
    end
  end
  return changed
end

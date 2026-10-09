-- Sample Map Browser module: seq_random
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function ensure_default_seq_region()
  if #state.seq_regions > 0 then
    if not get_seq_region_by_id(state.selected_seq_region_id) then
      state.selected_seq_region_id = state.seq_regions[1].id
    end
    return state.seq_regions[1]
  end

  local arrange_start, arrange_end = get_arrange_view_range()
  local start_qn = time_to_qn(arrange_start) or 0.0
  local pattern_id = alloc_seq_pattern()
  local temp_region = { start_qn = start_qn, length_bars = 4 }
  start_qn = find_non_overlapping_region_start(start_qn, get_seq_region_length_qn(temp_region), nil)
  local region = {
    id = state.seq_region_next_id,
    name = seq_auto_name_new_region(start_qn),
    start_qn = start_qn,
    length_bars = 4,
    pool_id = alloc_seq_pool(),
    pattern_id = pattern_id,
    groove = "off",
  }
  state.seq_region_next_id = state.seq_region_next_id + 1
  table.insert(state.seq_regions, region)
  state.selected_seq_region_id = region.id
  state.seq_view_start_qn = start_qn
  local span_qn = math.max(get_project_grid_step_qn(), (time_to_qn(arrange_end) or (start_qn + 16.0)) - start_qn)
  state.seq_view_span_qn = span_qn
  save_config()
  return region
end

function get_selected_seq_region()
  ensure_default_seq_region()
  return get_seq_region_by_id(state.selected_seq_region_id) or state.seq_regions[1]
end

function get_seq_region_display_name(region)
  if not region then
    return "Region"
  end
  if type(region.name) == "string" and region.name ~= "" then
    return region.name
  end
  return "Region " .. tostring(region.id or "?")
end

function get_track_note_table(pattern, track_id, create)
  if not pattern then
    return nil
  end
  pattern.notes = pattern.notes or {}
  local key = tostring(track_id)
  if not pattern.notes[key] and create then
    pattern.notes[key] = {}
  end
  return pattern.notes[key]
end

function seq_new_seed()
  local t = (r.time_precise and r.time_precise()) or os.clock()
  return math.floor(t * 1000000 + math.random(0, 1000000)) % 2147483647
end

function seq_apply_reseed_with_undo(reseed_fn)
  if type(reseed_fn) ~= "function" then
    return false
  end
  local already_open = seq_undo_is_open()
  local label = begin_seq_undo("Reseed sequencer random")
  reseed_fn()
  if already_open then
    return false
  end
  end_seq_undo(label)
  if save_config then
    save_config()
  end
  return true
end

function get_seq_track_settings(pattern, track_id, create)
  if not pattern then
    return nil
  end
  pattern.track_settings = pattern.track_settings or {}
  local key = tostring(track_id)
  if not pattern.track_settings[key] and create then
    pattern.track_settings[key] = {
      probability = 1.0,
      humanize_ms = 0.0,
      humanize_pitch_min = 0.0,
      humanize_pitch_max = 0.0,
      humanize_stretch_min = 1.0,
      humanize_stretch_max = 1.0,
      humanize_len_min = 1.0,
      humanize_len_max = 1.0,
      humanize_fade_min = 0.0,
      humanize_fade_max = 0.0,
      humanize_time_min = 0.0,
      humanize_time_max = 0.0,
      humanize_time_is_ms = true,
      humanize_vel = 0.0,
      humanize_vel_beat = 0.0,
      vary_prob = 0.0,
      vary_beat = 0.0,
      stutter_prob = 0.0,
      stutter_beat = 0.0,
      stutter_min = 2.0,
      stutter_max = 4.0,
      ghost_grace = 0.0,
      ghost_after = 0.0,
      ghost_grace_beat = 0.0,
      ghost_after_beat = 0.0,
      ghost_grace_close_min = 0.0625,
      ghost_grace_close_max = 0.125,
      ghost_after_close_min = 0.0625,
      ghost_after_close_max = 0.125,
      ghost_grace_vary = 0.0,
      ghost_after_vary = 0.0,
      ghost_grace_vol_min = 0.20,
      ghost_grace_vol_max = 0.40,
      ghost_after_vol_min = 0.20,
      ghost_after_vol_max = 0.40,
      probability_seed = seq_new_seed(),
      humanize_seed = seq_new_seed(),
      humanize_vel_seed = seq_new_seed(),
      vary_seed = seq_new_seed(),
      vary_swap_seed = seq_new_seed(),
      stutter_seed = seq_new_seed(),
      ghost_grace_seed = seq_new_seed(),
      ghost_after_seed = seq_new_seed(),
    }
  end
  local settings = pattern.track_settings[key]
  if settings then
    if type(settings.probability) ~= "number" then
      settings.probability = 1.0
    end
    if type(settings.humanize_ms) ~= "number" then
      settings.humanize_ms = 0.0
    end
    if type(settings.humanize_pitch_min) ~= "number" then
      settings.humanize_pitch_min = 0.0
    end
    if type(settings.humanize_pitch_max) ~= "number" then
      settings.humanize_pitch_max = settings.humanize_pitch_min
    end
    if type(settings.humanize_stretch_min) ~= "number" then
      settings.humanize_stretch_min = 1.0
    end
    if type(settings.humanize_stretch_max) ~= "number" then
      settings.humanize_stretch_max = settings.humanize_stretch_min
    end
    if type(settings.humanize_len_min) ~= "number" then
      settings.humanize_len_min = 1.0
    end
    if type(settings.humanize_len_max) ~= "number" then
      settings.humanize_len_max = settings.humanize_len_min
    end
    if type(settings.humanize_fade_min) ~= "number" then
      settings.humanize_fade_min = 0.0
    end
    if type(settings.humanize_fade_max) ~= "number" then
      settings.humanize_fade_max = settings.humanize_fade_min
    end
    if settings.humanize_time_is_ms ~= true then
      local lo = tonumber(settings.humanize_time_min)
      local hi = tonumber(settings.humanize_time_max)
      local ms = tonumber(settings.humanize_ms) or 0.0
      if lo ~= nil and hi ~= nil and math.abs(lo) <= 1.0001 and math.abs(hi) <= 1.0001 then
        settings.humanize_time_min = lo * ms
        settings.humanize_time_max = hi * ms
      else
        settings.humanize_time_min = lo or 0.0
        settings.humanize_time_max = hi or settings.humanize_time_min or 0.0
      end
      settings.humanize_time_is_ms = true
    end
    if type(settings.humanize_time_min) ~= "number" then
      settings.humanize_time_min = 0.0
    end
    if type(settings.humanize_time_max) ~= "number" then
      settings.humanize_time_max = 0.0
    end
    if type(settings.humanize_vel) ~= "number" then
      settings.humanize_vel = 0.0
    end
    if type(settings.humanize_vel_beat) ~= "number" then
      settings.humanize_vel_beat = 0.0
    end
    if type(settings.vary_prob) ~= "number" then
      settings.vary_prob = 0.0
    end
    if type(settings.vary_beat) ~= "number" then
      settings.vary_beat = 0.0
    end
    if type(settings.stutter_prob) ~= "number" then
      settings.stutter_prob = 0.0
    end
    if type(settings.stutter_beat) ~= "number" then
      settings.stutter_beat = 0.0
    end
    if type(settings.stutter_min) ~= "number" then
      settings.stutter_min = 2.0
    end
    if type(settings.stutter_max) ~= "number" then
      settings.stutter_max = math.max(settings.stutter_min, 4.0)
    end
    if type(settings.ghost_grace) ~= "number" then
      settings.ghost_grace = 0.0
    end
    if type(settings.ghost_after) ~= "number" then
      settings.ghost_after = 0.0
    end
    if type(settings.ghost_beat) ~= "number" then
      settings.ghost_beat = 0.0
    end
    if type(settings.ghost_close_min) ~= "number" then
      settings.ghost_close_min = 0.0625
    end
    if type(settings.ghost_close_max) ~= "number" then
      settings.ghost_close_max = 0.125
    end
    if type(settings.ghost_grace_beat) ~= "number" then
      settings.ghost_grace_beat = settings.ghost_beat or 0.0
    end
    if type(settings.ghost_after_beat) ~= "number" then
      settings.ghost_after_beat = settings.ghost_beat or 0.0
    end
    if type(settings.ghost_grace_close_min) ~= "number" then
      settings.ghost_grace_close_min = settings.ghost_close_min or 0.0625
    end
    if type(settings.ghost_grace_close_max) ~= "number" then
      settings.ghost_grace_close_max = settings.ghost_close_max or 0.125
    end
    if type(settings.ghost_after_close_min) ~= "number" then
      settings.ghost_after_close_min = settings.ghost_close_min or 0.0625
    end
    if type(settings.ghost_after_close_max) ~= "number" then
      settings.ghost_after_close_max = settings.ghost_close_max or 0.125
    end
    if type(settings.ghost_grace_vary) ~= "number" then
      settings.ghost_grace_vary = 0.0
    end
    if type(settings.ghost_after_vary) ~= "number" then
      settings.ghost_after_vary = 0.0
    end
    if type(settings.ghost_grace_vol_min) ~= "number" then
      settings.ghost_grace_vol_min = 0.20
    end
    if type(settings.ghost_grace_vol_max) ~= "number" then
      settings.ghost_grace_vol_max = math.max(settings.ghost_grace_vol_min, 0.40)
    end
    if type(settings.ghost_after_vol_min) ~= "number" then
      settings.ghost_after_vol_min = 0.20
    end
    if type(settings.ghost_after_vol_max) ~= "number" then
      settings.ghost_after_vol_max = math.max(settings.ghost_after_vol_min, 0.40)
    end
    if type(settings.probability_seed) ~= "number" then
      settings.probability_seed = settings.seed or seq_new_seed()
    end
    if type(settings.humanize_seed) ~= "number" then
      settings.humanize_seed = settings.seed or settings.probability_seed or seq_new_seed()
    end
    if type(settings.humanize_vel_seed) ~= "number" then
      settings.humanize_vel_seed = settings.humanize_seed or settings.seed or seq_new_seed()
    end
    if type(settings.vary_seed) ~= "number" then
      settings.vary_seed = settings.humanize_seed or settings.seed or seq_new_seed()
    end
    if type(settings.vary_swap_seed) ~= "number" then
      settings.vary_swap_seed = settings.vary_seed or seq_new_seed()
    end
    if type(settings.stutter_seed) ~= "number" then
      settings.stutter_seed = settings.vary_seed or settings.humanize_seed or settings.seed or seq_new_seed()
    end
    if type(settings.ghost_seed) ~= "number" then
      settings.ghost_seed = settings.stutter_seed or settings.vary_seed or seq_new_seed()
    end
    if type(settings.ghost_grace_seed) ~= "number" then
      settings.ghost_grace_seed = settings.ghost_seed or seq_new_seed()
    end
    if type(settings.ghost_after_seed) ~= "number" then
      settings.ghost_after_seed = settings.ghost_seed or seq_new_seed()
    end
  end
  return settings
end

function seq_settings_probability_active(settings)
  return settings and (tonumber(settings.probability) or 1.0) < 0.9995
end

function seq_settings_humanize_pitch_active(settings)
  if not settings then
    return false
  end
  local lo, hi = seq_normalize_range(settings.humanize_pitch_min, settings.humanize_pitch_max, -12.0, 12.0)
  return math.abs(lo) > 0.02 or math.abs(hi) > 0.02
end

function seq_settings_humanize_stretch_active(settings)
  if not settings then
    return false
  end
  local lo, hi = seq_normalize_range(settings.humanize_stretch_min, settings.humanize_stretch_max, 0.5, 2.0)
  return math.abs(lo - 1.0) > 0.01 or math.abs(hi - 1.0) > 0.01
end

function seq_settings_humanize_len_active(settings)
  if not settings then
    return false
  end
  local lo, hi = seq_normalize_range(settings.humanize_len_min, settings.humanize_len_max, SEQ_HUMANIZE_LEN_MIN, 1.0)
  return lo < 0.995 or hi < 0.995
end

function seq_settings_humanize_fade_active(settings)
  if not settings or not seq_settings_humanize_len_active(settings) then
    return false
  end
  local lo, hi = seq_normalize_range(settings.humanize_fade_min, settings.humanize_fade_max, 0.0, SEQ_HUMANIZE_FADE_MS)
  return lo > 0.05 or hi > 0.05
end

function seq_settings_humanize_time_active(settings)
  if not settings then
    return false
  end
  local lo, hi = seq_humanize_time_ms_range(settings)
  return math.abs(lo) > 0.05 or math.abs(hi) > 0.05
end

function seq_settings_humanize_active(settings)
  return settings and (
    (tonumber(settings.humanize_ms) or 0.0) > 0.05
    or seq_settings_humanize_time_active(settings)
    or seq_settings_humanize_pitch_active(settings)
    or seq_settings_humanize_stretch_active(settings)
    or seq_settings_humanize_len_active(settings)
  )
end

function seq_settings_vel_humanize_active(settings)
  return settings and (tonumber(settings.humanize_vel) or 0.0) > 0.01
end

function seq_settings_vary_active(settings)
  return settings and (tonumber(settings.vary_prob) or 0.0) > 0.005
end

function seq_settings_stutter_active(settings)
  return settings and (tonumber(settings.stutter_prob) or 0.0) > 0.005
end

function seq_settings_grace_active(settings)
  return settings and (tonumber(settings.ghost_grace) or 0.0) > 0.005
end

function seq_settings_after_active(settings)
  return settings and (tonumber(settings.ghost_after) or 0.0) > 0.005
end

function seq_settings_ghost_active(settings)
  return seq_settings_grace_active(settings) or seq_settings_after_active(settings)
end

function seq_ghost_which_keys(which)
  if which == "after" then
    return {
      prob = "ghost_after",
      beat = "ghost_after_beat",
      close_min = "ghost_after_close_min",
      close_max = "ghost_after_close_max",
      vary = "ghost_after_vary",
      vol_min = "ghost_after_vol_min",
      vol_max = "ghost_after_vol_max",
      seed = "ghost_after_seed",
    }
  end
  return {
    prob = "ghost_grace",
    beat = "ghost_grace_beat",
    close_min = "ghost_grace_close_min",
    close_max = "ghost_grace_close_max",
    vary = "ghost_grace_vary",
    vol_min = "ghost_grace_vol_min",
    vol_max = "ghost_grace_vol_max",
    seed = "ghost_grace_seed",
  }
end

-- bias +1 favors quarter-note downbeats, -1 favors 8th-note offbeats.
function seq_beat_weighted_prob(base_p, abs_qn, bias)
  base_p = tonumber(base_p) or 0.0
  if base_p <= 0.0 then
    return 0.0
  end
  bias = tonumber(bias) or 0.0
  if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
  local weight = 1.0 + bias * seq_qn_onbeat_signed(abs_qn)
  if weight < 0.0 then weight = 0.0 end
  local p = base_p * weight
  if p > 1.0 then p = 1.0 end
  return p
end

function seq_random_vary_amount(note, region, track_id, step_key, hit_idx)
  local painted = seq_note_param_value(note, "sample_vary", hit_idx) or 0.0
  if painted > 0.000001 then
    return painted
  end
  local hit = hit_idx and seq_stutter_hit_table(note, hit_idx) or nil
  if (hit and type(hit.frozen_sample_path) == "string" and hit.frozen_sample_path ~= "")
     or (note and type(note.frozen_sample_path) == "string" and note.frozen_sample_path ~= "") then
    return 0.0
  end
  if seq_note_is_locked(note) or seq_note_is_locked(get_seq_note(region, track_id, step_key)) then
    return 0.0
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  if not seq_settings_vary_active(settings) then
    return 0.0
  end
  local abs_qn = seq_note_humanize_abs_qn(region, note, step_key, hit_idx)
  local p = seq_beat_weighted_prob(settings.vary_prob, abs_qn, settings.vary_beat)
  local seed = (tonumber(settings.vary_seed) or 0)
    + (region and region.id or 1) * 1597334677
    + (tonumber(track_id) or 1) * 3812423773
    + (tonumber(step_key) or 1) * 274177
    + (tonumber(hit_idx) or 1) * 668265263
  if seq_stable_unit_rand(seed) > p then
    return 0.0
  end
  local swap = tonumber(settings.vary_swap_seed) or 0
  return 0.40 + seq_stable_unit_rand(seed + 99991 + swap) * 0.60
end

function seq_random_stutter_count(note, region, track_id, step_key)
  local painted = seq_stutter_count(note)
  if painted > 1 then
    return painted
  end
  if seq_note_is_locked(note) or seq_note_is_locked(get_seq_note(region, track_id, step_key)) then
    return painted
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  if not seq_settings_stutter_active(settings) then
    return 1
  end
  local abs_qn = seq_note_humanize_abs_qn(region, note, step_key, 1)
  local p = seq_beat_weighted_prob(settings.stutter_prob, abs_qn, settings.stutter_beat)
  local seed = (tonumber(settings.stutter_seed) or 0)
    + (region and region.id or 1) * 2246822519
    + (tonumber(track_id) or 1) * 3266489917
    + (tonumber(step_key) or 1) * 668265263
  if seq_stable_unit_rand(seed) > p then
    return 1
  end
  local min_n = math.max(2, math.floor((tonumber(settings.stutter_min) or 2) + 0.5))
  local max_n = math.max(min_n, math.floor((tonumber(settings.stutter_max) or 4) + 0.5))
  max_n = math.min(16, max_n)
  if max_n <= min_n then
    return min_n
  end
  return min_n + math.floor(seq_stable_unit_rand(seed + 17) * (max_n - min_n + 1))
end

function seq_normalize_range(lo, hi, min_v, max_v)
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  lo = tonumber(lo)
  hi = tonumber(hi)
  if lo == nil then lo = min_v end
  if hi == nil then hi = lo end
  if lo > hi then lo, hi = hi, lo end
  if lo < min_v then lo = min_v end
  if hi > max_v then hi = max_v end
  if hi < lo then hi = lo end
  return lo, hi
end

function seq_range_is_single(lo, hi, eps)
  lo, hi = tonumber(lo) or 0.0, tonumber(hi) or 0.0
  return math.abs(hi - lo) <= (eps or 1e-4)
end

function seq_pick_range_value(lo, hi, seed)
  lo = tonumber(lo) or 0.0
  hi = tonumber(hi) or lo
  if hi < lo then lo, hi = hi, lo end
  if hi - lo <= 1e-9 then
    return lo
  end
  return lo + seq_stable_unit_rand(seed) * (hi - lo)
end

SEQ_GHOST_CLOSE_MIN = 1.0 / 128.0
SEQ_GHOST_CLOSE_MAX = 0.25
SEQ_GHOST_CLOSE_STEPS = {
  1.0 / 128.0,   -- 512th
  1.0 / 96.0,    -- 256th triplet
  1.0 / 64.0,    -- 256th
  1.0 / 48.0,    -- 128th triplet
  1.0 / 32.0,    -- 128th
  1.0 / 24.0,    -- 64th triplet
  1.0 / 16.0,    -- 64th
  1.0 / 12.0,    -- 32nd triplet
  0.125,         -- 32nd
  1.0 / 6.0,     -- 16th triplet
  0.25,          -- 16th
}

function seq_snap_close_qn(qn)
  qn = tonumber(qn) or SEQ_GHOST_CLOSE_MIN
  local best, best_d = SEQ_GHOST_CLOSE_STEPS[1], math.abs(qn - SEQ_GHOST_CLOSE_STEPS[1])
  for i = 2, #SEQ_GHOST_CLOSE_STEPS do
    local step = SEQ_GHOST_CLOSE_STEPS[i]
    local d = math.abs(qn - step)
    if d < best_d then
      best, best_d = step, d
    end
  end
  if best < SEQ_GHOST_CLOSE_MIN then best = SEQ_GHOST_CLOSE_MIN end
  if best > SEQ_GHOST_CLOSE_MAX then best = SEQ_GHOST_CLOSE_MAX end
  return best
end

function seq_ghost_close_range(settings, which)
  local keys = seq_ghost_which_keys(which)
  local lo, hi = seq_normalize_range(
    settings and settings[keys.close_min] or 0.0625,
    settings and settings[keys.close_max] or 0.125,
    SEQ_GHOST_CLOSE_MIN,
    SEQ_GHOST_CLOSE_MAX
  )
  return lo, hi
end

function seq_ghost_should_place(settings, which, region, track_id, step_key, abs_qn)
  local keys = seq_ghost_which_keys(which)
  local base_p = tonumber(settings and settings[keys.prob]) or 0.0
  if base_p <= 0.005 then
    return false, 0.0
  end
  local p = seq_beat_weighted_prob(base_p, abs_qn, settings and settings[keys.beat] or 0.0)
  local salt = (which == "after") and 7919 or 104729
  local seed = (tonumber(settings and settings[keys.seed]) or 0)
    + (region and region.id or 1) * 198491317
    + (tonumber(track_id) or 1) * 12582917
    + (tonumber(step_key) or 1) * 16127
    + salt
  if seq_stable_unit_rand(seed) > p then
    return false, 0.0
  end
  local lo, hi = seq_ghost_close_range(settings, which)
  local close_qn = seq_pick_range_value(lo, hi, seed + 409)
  return true, close_qn
end

function seq_ghost_vol_range(settings, which)
  local keys = seq_ghost_which_keys(which)
  return seq_normalize_range(
    settings and settings[keys.vol_min] or 0.20,
    settings and settings[keys.vol_max] or 0.40,
    0.0,
    1.0
  )
end

function seq_ghost_pick_volume(settings, which, region, track_id, step_key)
  local lo, hi = seq_ghost_vol_range(settings, which)
  local keys = seq_ghost_which_keys(which)
  local salt = (which == "after") and 3371 or 2741
  local seed = (tonumber(settings and settings[keys.seed]) or 0)
    + (region and region.id or 1) * 2246822519
    + (tonumber(track_id) or 1) * 3267000013
    + (tonumber(step_key) or 1) * 668265263
    + salt
  return seq_pick_range_value(lo, hi, seed)
end

function seq_format_vol_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, 0.0, 1.0)
  local function pct(v)
    return string.format("%.0f%%", v * 100.0)
  end
  if seq_range_is_single(lo, hi, 0.008) then
    return pct((lo + hi) * 0.5)
  end
  return pct(lo) .. " – " .. pct(hi)
end

function seq_ghost_vary_amount(settings, which, region, track_id, step_key)
  local keys = seq_ghost_which_keys(which)
  local p = tonumber(settings and settings[keys.vary]) or 0.0
  if p <= 0.005 then
    return 0.0
  end
  local salt = (which == "after") and 4243 or 6151
  local seed = (tonumber(settings and settings[keys.seed]) or 0)
    + (region and region.id or 1) * 2654435761
    + (tonumber(track_id) or 1) * 40503
    + (tonumber(step_key) or 1) * 8543
    + salt
  if seq_stable_unit_rand(seed) > p then
    return 0.0
  end
  return 0.40 + seq_stable_unit_rand(seed + 91) * 0.60
end

function seq_stable_unit_rand(seed)
  return math.abs(math.sin(tonumber(seed) or 0) * 10000.0) % 1.0
end

SEQ_HUMANIZE_TIME_MS = 500.0
SEQ_HUMANIZE_LEN_MIN = 0.05
SEQ_HUMANIZE_FADE_MS = 200.0
SEQ_PITCH_HUMANIZE = 12.0
SEQ_PITCH_CURVE = 2.25

function seq_humanize_time_ms_range(settings)
  return seq_normalize_range(
    settings and settings.humanize_time_min or 0.0,
    settings and settings.humanize_time_max or 0.0,
    -SEQ_HUMANIZE_TIME_MS, SEQ_HUMANIZE_TIME_MS
  )
end

function seq_humanize_effective_time_ms(settings, humanize_ms)
  local lo, hi = seq_humanize_time_ms_range(settings)
  if math.abs(lo) > 0.05 or math.abs(hi) > 0.05 then
    return lo, hi
  end
  humanize_ms = tonumber(humanize_ms) or (settings and tonumber(settings.humanize_ms)) or 0.0
  if humanize_ms > 0.05 then
    return -humanize_ms, humanize_ms
  end
  return 0.0, 0.0
end

function seq_humanize_sync_time_from_knob(settings, ms)
  if not settings then
    return
  end
  ms = tonumber(ms) or 0.0
  if ms < 0.0 then ms = 0.0 end
  settings.humanize_ms = ms
  settings.humanize_time_min = -ms
  settings.humanize_time_max = ms
  settings.humanize_time_is_ms = true
end

function seq_pitch_range_from_norm(t)
  if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
  local u = t * 2.0 - 1.0
  local s = (u < 0.0) and -1.0 or 1.0
  return s * SEQ_PITCH_HUMANIZE * (math.abs(u) ^ SEQ_PITCH_CURVE)
end

function seq_pitch_range_to_norm(v)
  v = tonumber(v) or 0.0
  local a = math.abs(v) / SEQ_PITCH_HUMANIZE
  if a > 1.0 then a = 1.0 end
  local u = ((v < 0.0) and -1.0 or 1.0) * (a ^ (1.0 / SEQ_PITCH_CURVE))
  return (u + 1.0) * 0.5
end

function seq_humanize_time_offset_sec(region, track_id, step_key, humanize_ms, random_seed)
  local note = get_seq_note(region, track_id, step_key)
  if seq_note_is_locked(note) then
    return tonumber(note.locked_humanize_sec) or 0.0
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  local lo, hi = seq_humanize_effective_time_ms(settings, humanize_ms)
  if math.abs(lo) < 0.05 and math.abs(hi) < 0.05 then
    return 0.0
  end
  local seed = (tonumber(random_seed) or 0)
    + (region and region.id or 1) * 2654435761
    + (tonumber(track_id) or 1) * 1013904223
    + (tonumber(step_key) or 1) * 374761393
  return seq_pick_range_value(lo, hi, seed) / 1000.0
end

function seq_humanize_pitch_offset(region, track_id, step_key, hit_idx, opts)
  opts = opts or {}
  local note = get_seq_note(region, track_id, step_key)
  if (not opts.force) and seq_note_is_locked(note) then
    return tonumber(note.locked_humanize_pitch) or 0.0
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  if not seq_settings_humanize_pitch_active(settings) then
    return 0.0
  end
  local lo, hi = seq_normalize_range(settings.humanize_pitch_min, settings.humanize_pitch_max, -12.0, 12.0)
  local seed = (tonumber(settings.humanize_seed) or 0)
    + (region and region.id or 1) * 2246822519
    + (tonumber(track_id) or 1) * 3266489917
    + (tonumber(step_key) or 1) * 668265263
    + (tonumber(hit_idx) or 1) * 7919
    + 17
  return seq_pick_range_value(lo, hi, seed)
end

function seq_humanize_stretch_mul(region, track_id, step_key, hit_idx, opts)
  opts = opts or {}
  local note = get_seq_note(region, track_id, step_key)
  if (not opts.force) and seq_note_is_locked(note) then
    return tonumber(note.locked_humanize_stretch) or 1.0
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  if not seq_settings_humanize_stretch_active(settings) then
    return 1.0
  end
  local lo, hi = seq_normalize_range(settings.humanize_stretch_min, settings.humanize_stretch_max, 0.5, 2.0)
  local seed = (tonumber(settings.humanize_seed) or 0)
    + (region and region.id or 1) * 2654435761
    + (tonumber(track_id) or 1) * 1013904223
    + (tonumber(step_key) or 1) * 374761393
    + (tonumber(hit_idx) or 1) * 104729
    + 31
  local mul = seq_pick_range_value(lo, hi, seed)
  if mul < 0.5 then mul = 0.5 elseif mul > 2.0 then mul = 2.0 end
  return mul
end

function seq_humanize_length_mul(region, track_id, step_key, hit_idx, opts)
  opts = opts or {}
  local note = get_seq_note(region, track_id, step_key)
  if (not opts.force) and seq_note_is_locked(note) then
    local locked = tonumber(note.locked_humanize_len)
    if locked then
      if locked < SEQ_HUMANIZE_LEN_MIN then locked = SEQ_HUMANIZE_LEN_MIN end
      if locked > 1.0 then locked = 1.0 end
      return locked
    end
    return 1.0
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  if not seq_settings_humanize_len_active(settings) then
    return 1.0
  end
  local lo, hi = seq_normalize_range(settings.humanize_len_min, settings.humanize_len_max, SEQ_HUMANIZE_LEN_MIN, 1.0)
  local seed = (tonumber(settings.humanize_seed) or 0)
    + (region and region.id or 1) * 2654435761
    + (tonumber(track_id) or 1) * 1013904223
    + (tonumber(step_key) or 1) * 374761393
    + (tonumber(hit_idx) or 1) * 2246822519
    + 47
  local mul = seq_pick_range_value(lo, hi, seed)
  if mul < SEQ_HUMANIZE_LEN_MIN then mul = SEQ_HUMANIZE_LEN_MIN elseif mul > 1.0 then mul = 1.0 end
  return mul
end

function seq_humanize_fade_out_sec(region, track_id, step_key, hit_idx, opts)
  opts = opts or {}
  local note = get_seq_note(region, track_id, step_key)
  if (not opts.force) and seq_note_is_locked(note) then
    return math.max(0.0, tonumber(note.locked_humanize_fade) or 0.0)
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  if not seq_settings_humanize_fade_active(settings) then
    return 0.0
  end
  local lo, hi = seq_normalize_range(settings.humanize_fade_min, settings.humanize_fade_max, 0.0, SEQ_HUMANIZE_FADE_MS)
  local seed = (tonumber(settings.humanize_seed) or 0)
    + (region and region.id or 1) * 2246822519
    + (tonumber(track_id) or 1) * 3266489917
    + (tonumber(step_key) or 1) * 668265263
    + (tonumber(hit_idx) or 1) * 2654435761
    + 59
  return seq_pick_range_value(lo, hi, seed) / 1000.0
end

-- +1 on a quarter-note downbeat, -1 on the 8th-note offbeat.
function seq_qn_onbeat_signed(abs_qn)
  local frac = (tonumber(abs_qn) or 0.0) % 1.0
  if frac < 0.0 then
    frac = frac + 1.0
  end
  local dist = math.min(frac, 1.0 - frac)
  local on_beat = 1.0 - (dist / 0.5)
  if on_beat < 0.0 then on_beat = 0.0 end
  if on_beat > 1.0 then on_beat = 1.0 end
  return on_beat * 2.0 - 1.0
end

SEQ_VEL_HUMANIZE_FLOOR = 0.05

function seq_note_locked_vel(note, hit_idx)
  if type(note) ~= "table" then
    return nil
  end
  if hit_idx then
    local hit = seq_stutter_hit_table(note, hit_idx)
    if type(hit) == "table" and hit.locked_vel ~= nil then
      return tonumber(hit.locked_vel)
    end
  end
  return tonumber(note.locked_vel)
end

function seq_humanize_note_velocity(base_vel, region, track_id, step_key, abs_qn, hit_idx)
  base_vel = tonumber(base_vel) or 1.0
  local note = get_seq_note(region, track_id, step_key)
  if seq_note_is_locked(note) then
    return seq_note_locked_vel(note, hit_idx) or base_vel
  end
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local settings = get_seq_track_settings(pattern, track_id, false)
  local amount = settings and tonumber(settings.humanize_vel) or 0.0
  if not amount or amount <= 0.0005 then
    return base_vel
  end
  local bias = tonumber(settings.humanize_vel_beat) or 0.0
  if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
  local seed = (tonumber(settings.humanize_vel_seed) or 0)
    + (region and region.id or 1) * 2246822519
    + (tonumber(track_id) or 1) * 3266489917
    + (tonumber(step_key) or 1) * 668265263
    + (tonumber(hit_idx) or 1) * 374761393
  local rand = seq_stable_unit_rand(seed) * 2.0 - 1.0
  local directed = seq_qn_onbeat_signed(abs_qn)
  local mix = 1.0 - math.abs(bias) * 0.65
  local vel = base_vel + rand * amount * mix + directed * amount * bias
  if base_vel > 0.001 then
    if vel < SEQ_VEL_HUMANIZE_FLOOR then vel = SEQ_VEL_HUMANIZE_FLOOR end
  elseif vel < 0.0 then
    vel = 0.0
  end
  if vel > 2.0 then vel = 2.0 end
  return vel
end

function seq_note_humanize_abs_qn(region, note, step_key, hit_idx)
  local grid_qn = state.seq_grid_qn or 0.25
  local start_qn = seq_note_trigger_qn(region, step_key, note, grid_qn)
  local idx = tonumber(hit_idx) or 1
  if idx > 1 then
    local stutter = seq_stutter_count(note)
    if stutter > 1 then
      local off0 = seq_stutter_hit_span(note, idx, grid_qn)
      start_qn = start_qn + (off0 or 0.0)
    end
  end
  return start_qn
end

function seq_expected_humanized_velocity(note, region, track_id, step_key, hit_idx)
  local base = tonumber(note and note.volume) or 1.0
  local abs_qn = seq_note_humanize_abs_qn(region, note, step_key, hit_idx)
  return seq_humanize_note_velocity(base, region, track_id, step_key, abs_qn, hit_idx)
end

-- Compare arrange take-vol to the *humanized* output. Never store that
-- output as the note's base, or the next humanize pass compounds toward 0.
function seq_ingest_resolve_volume(rec_vol, note, region, track_id, step_key)
  rec_vol = tonumber(rec_vol)
  local base = tonumber(note and note.volume)
  if base == nil then
    base = 1.0
  end
  if rec_vol == nil then
    return base, false
  end
  local expected = seq_expected_humanized_velocity(note or { volume = base }, region, track_id, step_key, 1)
  local settings = get_seq_track_settings(get_seq_pattern(region and region.pattern_id, false), track_id, false)
  local amount = settings and tonumber(settings.humanize_vel) or 0.0
  local slop = 0.03
  if amount > 0.0 then
    slop = math.max(slop, amount * 1.6 + 0.08)
  end
  if math.abs(rec_vol - expected) <= slop then
    -- Heal notes already collapsed by baked-in humanize.
    if amount > 0.0 and base < 0.08 then
      return 1.0, true
    end
    return base, false
  end
  local stored = rec_vol - (expected - base)
  if stored < 0.0 then stored = 0.0 end
  if stored > 2.0 then stored = 2.0 end
  return stored, true
end

function seq_ingest_resolve_pitch(rec_pitch, note, region, track_id, step_key)
  rec_pitch = tonumber(rec_pitch)
  local base = tonumber(note and note.pitch) or 0.0
  if rec_pitch == nil then
    return base, false
  end
  local offset = seq_humanize_pitch_offset(region, track_id, step_key, 1)
  local expected = base + offset
  local slop = 0.08
  if math.abs(offset) > 0.01 then
    slop = math.max(slop, math.abs(offset) * 0.35 + 0.12)
  end
  if math.abs(rec_pitch - expected) <= slop then
    return base, false
  end
  local stored = rec_pitch - offset
  if stored < -24.0 then stored = -24.0 elseif stored > 24.0 then stored = 24.0 end
  return stored, true
end

function seq_format_beat_drag(bias)
  bias = tonumber(bias) or 0.0
  if bias > 1.0 then bias = 1.0 elseif bias < -1.0 then bias = -1.0 end
  local pct = math.floor(math.abs(bias) * 100.0 + 0.5)
  if pct < 3 then
    return "Even"
  elseif bias > 0.0 then
    return string.format("%d%% down beat", pct)
  end
  return string.format("%d%% up beat", pct)
end

function seq_format_vel_beat(bias)
  return seq_format_beat_drag(bias)
end

function seq_format_close_qn(qn)
  qn = tonumber(qn) or 0.0
  local marks = {
    { 1.0 / 128.0, "512th" },
    { 1.0 / 96.0, "256th T" },
    { 1.0 / 64.0, "256th" },
    { 1.0 / 48.0, "128th T" },
    { 1.0 / 32.0, "128th" },
    { 1.0 / 24.0, "64th T" },
    { 1.0 / 16.0, "64th" },
    { 1.0 / 12.0, "32nd T" },
    { 0.125, "32nd" },
    { 1.0 / 6.0, "16th T" },
    { 0.25, "16th" },
  }
  local best, best_d = marks[1][2], math.abs(qn - marks[1][1])
  for i = 2, #marks do
    local d = math.abs(qn - marks[i][1])
    if d < best_d then
      best, best_d = marks[i][2], d
    end
  end
  if best_d > 0.004 then
    return string.format("%.0f ticks", qn * 960.0)
  end
  return best
end

function seq_format_close_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, SEQ_GHOST_CLOSE_MIN, SEQ_GHOST_CLOSE_MAX)
  if seq_range_is_single(lo, hi, 0.008) then
    return seq_format_close_qn((lo + hi) * 0.5)
  end
  return seq_format_close_qn(lo) .. " – " .. seq_format_close_qn(hi)
end

function seq_format_stutter_range(lo, hi)
  lo = math.max(2, math.floor((tonumber(lo) or 2) + 0.5))
  hi = math.max(lo, math.floor((tonumber(hi) or lo) + 0.5))
  if lo == hi then
    return tostring(lo)
  end
  return string.format("%d–%d", lo, hi)
end

function seq_format_pitch_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, -12.0, 12.0)
  local function fmt(v)
    if math.abs(v) < 0.05 then
      return "0"
    elseif v > 0.0 then
      return string.format("+%.1f", v)
    end
    return string.format("%.1f", v)
  end
  if seq_range_is_single(lo, hi, 0.05) then
    return fmt((lo + hi) * 0.5) .. " st"
  end
  return fmt(lo) .. "–" .. fmt(hi) .. " st"
end

function seq_format_stretch_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, 0.5, 2.0)
  if seq_range_is_single(lo, hi, 0.012) then
    return string.format("%.2fx", (lo + hi) * 0.5)
  end
  return string.format("%.2f–%.2fx", lo, hi)
end

function seq_format_len_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, SEQ_HUMANIZE_LEN_MIN, 1.0)
  local function pct(v)
    return string.format("%.0f%%", v * 100.0)
  end
  if seq_range_is_single(lo, hi, 0.008) then
    return pct((lo + hi) * 0.5)
  end
  return pct(lo) .. "–" .. pct(hi)
end

function seq_format_fade_ms_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, 0.0, SEQ_HUMANIZE_FADE_MS)
  local function fmt(v)
    if v < 0.5 then
      return "0"
    end
    return string.format("%.0f", v)
  end
  if seq_range_is_single(lo, hi, 0.6) then
    return fmt((lo + hi) * 0.5) .. " ms"
  end
  return fmt(lo) .. "–" .. fmt(hi) .. " ms"
end

function seq_format_time_ms_range(lo, hi)
  lo, hi = seq_normalize_range(lo, hi, -SEQ_HUMANIZE_TIME_MS, SEQ_HUMANIZE_TIME_MS)
  local function fmt(v)
    if math.abs(v) < 0.5 then
      return "0"
    elseif v > 0.0 then
      return string.format("+%.0f", v)
    end
    return string.format("%.0f", v)
  end
  if seq_range_is_single(lo, hi, 0.6) then
    local v = (lo + hi) * 0.5
    if math.abs(v) < 0.5 then
      return "0 ms"
    elseif v < 0.0 then
      return string.format("%.0f ms early", -v)
    end
    return string.format("%.0f ms late", v)
  end
  return fmt(lo) .. "–" .. fmt(hi) .. " ms"
end

function seq_queue_random_sync(pattern_id, track_id)
  if not pattern_id then
    return
  end
  -- Pending syncs are keyed by pattern so rapid edits across patterns all flush.
  local all = state.seq_random_sync_pending
  if not all then
    all = { by_pattern = {} }
    state.seq_random_sync_pending = all
  end
  local pending = all.by_pattern[pattern_id]
  if not pending then
    pending = { pattern_id = pattern_id, track_ids = {} }
    all.by_pattern[pattern_id] = pending
  end
  if track_id then
    pending.track_ids[track_id] = true
  else
    pending.all_tracks = true
  end
end

function seq_random_sync_pending_forget_track(track_id)
  local all = state.seq_random_sync_pending
  if not (all and all.by_pattern) then
    return
  end
  for _, pending in pairs(all.by_pattern) do
    if pending.track_ids then
      pending.track_ids[track_id] = nil
    end
  end
end

function seq_repair_collapsed_note_velocities(pattern, track_id)
  local notes = get_track_note_table(pattern, track_id, false)
  if not notes then
    return
  end
  for _, note in pairs(notes) do
    if type(note) == "table" and (tonumber(note.volume) or 1.0) < 0.08 then
      note.volume = 1.0
    end
  end
end

function seq_flush_pending_random_sync()
  local all = state.seq_random_sync_pending
  if not all then
    return
  end
  state.seq_random_sync_pending = nil
  state.seq_random_sync_run = false
  -- Note: quiet notes are no longer forced back to 1.0 here (that wiped
  -- deliberate ghost notes on every random-setting edit).
  if seq_schedule_ingest_save then
    seq_schedule_ingest_save()
  elseif save_seq_project_state then
    save_seq_project_state()
  end
  local need_arrange = false
  for _, pending in pairs(all.by_pattern or {}) do
    local any = false
    if not pending.all_tracks and pending.track_ids then
      for _ in pairs(pending.track_ids) do
        any = true
        break
      end
    end
    if not any then
      sync_seq_pattern_regions(pending.pattern_id)
    else
      if r.PreventUIRefresh then r.PreventUIRefresh(1) end
      for track_id, _ in pairs(pending.track_ids) do
        local slot = seq_find_track_slot_by_id(track_id) or seq_find_slot_by_id(track_id)
        if slot then
          sync_seq_pattern_track(pending.pattern_id, slot, { skip_arrange = true, force_rebuild = true })
        end
      end
      if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
      need_arrange = true
    end
  end
  if need_arrange and r.UpdateArrange then
    r.UpdateArrange()
  end
end

function seq_collect_region_random_entries(region)
  local entries = {}
  local has_prob = false
  local has_human = false
  local has_vel = false
  local has_vary = false
  local has_stut = false
  local has_ghost = false
  local has_grace = false
  local has_after = false
  if not region then
    return entries, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after
  end
  local pattern = get_seq_pattern(region.pattern_id, false)
  if not pattern then
    return entries, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after
  end
  for _, slot in ipairs(state.seq_tracks or {}) do
    local settings = get_seq_track_settings(pattern, slot.id, false)
    local show_prob = seq_settings_probability_active(settings)
    local show_human = seq_settings_humanize_active(settings)
    local show_vel = seq_settings_vel_humanize_active(settings)
    local show_vary = seq_settings_vary_active(settings)
    local show_stut = seq_settings_stutter_active(settings)
    local show_grace = seq_settings_grace_active(settings)
    local show_after = seq_settings_after_active(settings)
    local show_ghost = show_grace or show_after
    if show_prob or show_human or show_vel or show_vary or show_stut or show_ghost then
      entries[#entries + 1] = {
        slot = slot,
        settings = settings,
        show_prob = show_prob,
        show_human = show_human,
        show_vel = show_vel,
        show_vary = show_vary,
        show_stut = show_stut,
        show_grace = show_grace,
        show_after = show_after,
        show_ghost = show_ghost,
      }
      has_prob = has_prob or show_prob
      has_human = has_human or show_human
      has_vel = has_vel or show_vel
      has_vary = has_vary or show_vary
      has_stut = has_stut or show_stut
      has_ghost = has_ghost or show_ghost
      has_grace = has_grace or show_grace
      has_after = has_after or show_after
    end
  end
  return entries, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after
end

function seq_snapshot_region_random_popup(region)
  local entries = seq_collect_region_random_entries(region)
  local snapshot = {}
  for _, entry in ipairs(entries) do
    snapshot[#snapshot + 1] = {
      track_id = entry.slot.id,
      show_prob = entry.show_prob,
      show_human = entry.show_human,
      show_vel = entry.show_vel,
      show_vary = entry.show_vary,
      show_stut = entry.show_stut,
      show_grace = entry.show_grace,
      show_after = entry.show_after,
      show_ghost = entry.show_ghost,
    }
  end
  return snapshot
end

function seq_reset_region_random_settings(region, kind)
  if not region then
    return false
  end
  local pattern = get_seq_pattern(region.pattern_id, false)
  if not pattern then
    return false
  end
  local changed = false
  for _, slot in ipairs(state.seq_tracks or {}) do
    local settings = get_seq_track_settings(pattern, slot.id, false)
    if settings then
      if (kind == "prob" or kind == "all") and seq_settings_probability_active(settings) then
        settings.probability = 1.0
        changed = true
      end
      if (kind == "human" or kind == "all") and seq_settings_humanize_active(settings) then
        settings.humanize_ms = 0.0
        settings.humanize_pitch_min = 0.0
        settings.humanize_pitch_max = 0.0
        settings.humanize_stretch_min = 1.0
        settings.humanize_stretch_max = 1.0
        settings.humanize_len_min = 1.0
        settings.humanize_len_max = 1.0
        settings.humanize_fade_min = 0.0
        settings.humanize_fade_max = 0.0
        settings.humanize_time_min = 0.0
        settings.humanize_time_max = 0.0
        settings.humanize_time_is_ms = true
        changed = true
      end
      if (kind == "vel" or kind == "all") and seq_settings_vel_humanize_active(settings) then
        settings.humanize_vel = 0.0
        settings.humanize_vel_beat = 0.0
        changed = true
      end
      if (kind == "vary" or kind == "all") and seq_settings_vary_active(settings) then
        settings.vary_prob = 0.0
        settings.vary_beat = 0.0
        changed = true
      end
      if (kind == "stut" or kind == "all") and seq_settings_stutter_active(settings) then
        settings.stutter_prob = 0.0
        settings.stutter_beat = 0.0
        changed = true
      end
      if (kind == "grace" or kind == "ghost" or kind == "all") and seq_settings_grace_active(settings) then
        settings.ghost_grace = 0.0
        settings.ghost_grace_beat = 0.0
        settings.ghost_grace_vary = 0.0
        settings.ghost_grace_vol_min = 0.20
        settings.ghost_grace_vol_max = 0.40
        changed = true
      end
      if (kind == "after" or kind == "ghost" or kind == "all") and seq_settings_after_active(settings) then
        settings.ghost_after = 0.0
        settings.ghost_after_beat = 0.0
        settings.ghost_after_vary = 0.0
        settings.ghost_after_vol_min = 0.20
        settings.ghost_after_vol_max = 0.40
        changed = true
      end
    end
  end
  return changed
end

function seq_note_probability_roll(region, track_id, step_key, probability, probability_seed)
  probability = tonumber(probability)
  if not probability or probability >= 1.0 then
    return true
  end
  if probability <= 0.0 then
    return false
  end
  local seed = (tonumber(probability_seed) or 0)
    + (region and region.id or 1) * 73856093
    + (tonumber(track_id) or 1) * 19349663
    + (tonumber(step_key) or 1) * 83492791
  local pseudo = math.abs(math.sin(seed) * 10000.0) % 1.0
  return pseudo <= probability
end

function seq_note_passes_probability(region, track_id, step_key, probability, probability_seed)
  local note = get_seq_note(region, track_id, step_key)
  if seq_note_is_locked(note) then
    return note.locked_skip ~= true
  end
  return seq_note_probability_roll(region, track_id, step_key, probability, probability_seed)
end

SEQ_GEN_STYLE_ORDER = {
  { header = "Genres" },
  { key = "house", label = "House" },
  { key = "techno", label = "Techno" },
  { key = "disco", label = "Disco" },
  { key = "basic", label = "Pop Backbeat" },
  { key = "rock", label = "Rock" },
  { key = "hiphop", label = "Boom Bap" },
  { key = "trap", label = "Trap" },
  { key = "funk", label = "Funk" },
  { key = "dnb", label = "Drum & Bass" },
  { key = "breakbeat", label = "Breakbeat" },
  { key = "reggaeton", label = "Reggaeton" },
  { key = "afrobeat", label = "Afrobeat" },
  { header = "Abstract" },
  { key = "dust_motes", label = "Dust Motes" },
  { key = "glass_steps", label = "Glass Steps" },
  { key = "crooked_neon", label = "Crooked Neon" },
  { key = "soft_alarm", label = "Soft Alarm" },
  { key = "tiny_machines", label = "Tiny Machines" },
  { key = "low_gravity", label = "Low Gravity" },
  { key = "ritual_drift", label = "Ritual Drift" },
  { key = "broken_lantern", label = "Broken Lantern" },
  { key = "afterimage", label = "Afterimage" },
  { key = "rain_on_plastic", label = "Rain On Plastic" },
  { key = "velvet_push", label = "Velvet Push" },
  { key = "static_bloom", label = "Static Bloom" },
}

-- Map sequencer pattern style keys to library genre tags used for kit randomization.
SEQ_STYLE_LIBRARY_GENRES = {
  house = { "house" },
  techno = { "techno" },
  disco = { "disco", "nu disco" },
  basic = { "pop" },
  rock = { "rock" },
  hiphop = { "boom bap", "hip hop" },
  trap = { "trap" },
  funk = { "funk" },
  dnb = { "drum and bass" },
  breakbeat = { "breakbeat" },
  reggaeton = { "reggaeton" },
  afrobeat = { "afrobeat" },
}

-- Each preset declares its own palette of sample-type roles. Picking a preset
-- auto-adds any missing track types it needs (see ensure_seq_tracks_for_roles).
SEQ_GEN_TEMPLATES = {
  -- Four-on-the-floor; clap doubles beats 2 & 4; open hats on the offbeats.
  house = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    bass = {2, 6, 10, 14},
  },
  -- Driving 4/4; offbeat open hats; syncopated perc stabs.
  techno = {
    kick = {0, 4, 8, 12},
    hat = {2, 6, 10, 14},
    clap = {12},
    perc = {3, 11},
  },
  -- Disco: four-on-the-floor with steady 8th hats and offbeat open ride.
  disco = {
    kick = {0, 4, 8, 12},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    ride = {2, 6, 10, 14},
  },
  -- Straight pop backbeat; clap layered on the snare.
  basic = {
    kick = {0, 8},
    snare = {4, 12},
    clap = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  -- Rock: kick on 1 and the & of 3, backbeat snare, crash on the downbeat.
  rock = {
    kick = {0, 8, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    crash = {0},
  },
  -- Boom bap: kick on 1 and the & of 2, classic backbeat, swung 8th hats.
  hiphop = {
    kick = {0, 6, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  -- Trap: half-time snare on beat 3, syncopated 808/kick, rapid 16th hats.
  trap = {
    kick = {0, 7, 10},
    snare = {8},
    hat = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    ["808"] = {0, 7, 10},
  },
  -- Funk: syncopated kick, backbeat snare, 16th hats, perc ghost on the &-a.
  funk = {
    kick = {0, 3, 10},
    snare = {4, 12},
    hat = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    perc = {7, 14},
  },
  -- Drum & bass two-step: kick on 1 and the & of 3, snare backbeat, sub on kicks.
  dnb = {
    kick = {0, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    bass = {0, 10},
  },
  -- Breakbeat: amen-style kick/snare interplay with a perc tail.
  breakbeat = {
    kick = {0, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    perc = {7, 15},
  },
  -- Reggaeton dembow: kick on 1 & 3, rimshot on the boom-ch-boom-chick.
  reggaeton = {
    kick = {0, 8},
    rim = {3, 6, 11, 14},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  -- Afrobeat: son-clave (3-2) rimshot, rolling perc, lilting kick.
  afrobeat = {
    kick = {0, 6, 10},
    rim = {0, 3, 6, 10, 12},
    perc = {2, 5, 8, 11, 14},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  dust_motes = {
    kick = {0, 10},
    rim = {4, 12},
    perc = {3, 7, 11, 13},
    vocal = {2, 10},
  },
  glass_steps = {
    kick = {0, 6, 11},
    snare = {4, 12},
    hat = {1, 3, 5, 7, 9, 11, 13, 15},
    perc = {6, 10, 14},
    fx = {0},
  },
  crooked_neon = {
    ["808"] = {0, 5, 10, 14},
    clap = {4, 11},
    hat = {0, 2, 5, 7, 8, 10, 13, 15},
    perc = {3, 9, 12},
  },
  soft_alarm = {
    kick = {0, 9},
    snare = {4, 12},
    hat = {2, 6, 10, 14},
    fx = {8, 15},
  },
  tiny_machines = {
    kick = {0, 4, 9, 12},
    rim = {6, 14},
    perc = {2, 5, 10, 13},
    hat = {0, 1, 3, 4, 6, 8, 9, 11, 12, 14},
  },
  low_gravity = {
    kick = {0, 11},
    snare = {6, 13},
    bass = {0, 8},
    ride = {0, 4, 8, 12},
  },
  ritual_drift = {
    kick = {0, 7, 12},
    tom = {5, 13},
    perc = {2, 4, 6, 10, 12, 14},
    vocal = {1, 8, 15},
  },
  broken_lantern = {
    kick = {0, 3, 10},
    snare = {4, 12, 15},
    hat = {1, 4, 6, 9, 11, 14},
    fx = {0},
    perc = {2, 7, 13},
  },
  afterimage = {
    kick = {0, 8, 15},
    clap = {4, 12},
    hat = {2, 3, 6, 7, 10, 11, 14, 15},
    ride = {0, 4, 8, 12},
    fx = {15},
  },
  rain_on_plastic = {
    kick = {0, 6, 12},
    rim = {4, 10},
    hat = {0, 2, 3, 5, 7, 8, 10, 12, 13, 15},
    perc = {1, 6, 11, 14},
    vocal = {3, 11},
  },
  velvet_push = {
    kick = {0, 8, 10},
    snare = {4, 12},
    hat = {2, 6, 9, 10, 14},
    bass = {0, 8},
    clap = {12},
  },
  static_bloom = {
    ["808"] = {0, 4, 10},
    snare = {7, 12},
    hat = {1, 2, 4, 5, 7, 8, 10, 11, 13, 14},
    perc = {3, 6, 9, 15},
    fx = {0, 8},
  },
}

-- Per-preset groove. swing delays odd 16th positions (fraction of a 16th note)
-- to push the pattern off the grid and into a more human pocket.
SEQ_GEN_GROOVE = {
  house      = { swing = 0.0 },
  techno     = { swing = 0.0 },
  disco      = { swing = 0.04 },
  basic      = { swing = 0.04 },
  rock       = { swing = 0.0 },
  hiphop     = { swing = 0.16 },
  trap       = { swing = 0.0 },
  funk       = { swing = 0.10 },
  dnb        = { swing = 0.0 },
  breakbeat  = { swing = 0.08 },
  reggaeton  = { swing = 0.0 },
  afrobeat   = { swing = 0.06 },
}

-- Canonical ordering for deterministic track creation.
SEQ_ROLE_ORDER = { "kick", "808", "bass", "snare", "clap", "rim", "tom", "hat", "ride", "crash", "perc", "fx", "vocal" }

SEQ_ROLE_LABELS = {
  kick = "Kick", ["808"] = "808", bass = "Bass", snare = "Snare", clap = "Clap",
  rim = "Rim", tom = "Tom", hat = "Hat", ride = "Ride", crash = "Crash",
  perc = "Perc", fx = "FX", vocal = "Vocal",
}

-- Candidate library tags to search when auto-assigning a sample to a role track.
-- First entry is the primary tag stamped on the slot (drives role detection).
SEQ_ROLE_TAG_CANDIDATES = {
  kick  = { "kick" },
  ["808"] = { "808s", "808", "kick", "bass" },
  bass  = { "bass", "808s", "808" },
  snare = { "snare" },
  clap  = { "clap", "snap" },
  rim   = { "rim", "snap", "clap" },
  tom   = { "tom", "perc" },
  hat   = { "hat" },
  ride  = { "ride", "hat" },
  crash = { "crash", "hat" },
  perc  = { "perc", "rim", "tom" },
  fx    = { "fx" },
  vocal = { "vocal" },
}

-- Roles/tags that sustain until the next note on the same track (or region end).
SEQ_SUSTAIN_ROLES = {
  ["808"] = true, bass = true, fx = true, vocal = true,
  crash = true, ride = true, swell = true,
}

SEQ_SUSTAIN_TAGS = {
  ["808"] = true, bass = true, fx = true, vocal = true,
  crash = true, ride = true, swell = true, loop = true,
  pluck = true, lead = true, pad = true, keys = true, guitar = true,
}

-- Group roles into rhythmic families that drive the randomizer behavior.
function seq_role_family(role)
  if role == "kick" or role == "808" or role == "bass" then
    return "kick"
  elseif role == "snare" or role == "clap" or role == "rim" then
    return "backbeat"
  elseif role == "hat" or role == "ride" then
    return "hat"
  end
  return "perc"
end

-- Baseline groove offset (in QN) so hits sit in the pocket rather than dead on
-- the grid: per-preset swing on odd 16ths, a small family lay-back, and a tiny
-- stable humanize. pos16 is the step position within the bar at 16th resolution.
function seq_pattern_base_offset(role, pos16, style_key, grid_qn)
  local groove = SEQ_GEN_GROOVE[style_key]
  local swing = (groove and groove.swing) or 0.0
  local sixteenth_qn = 0.25
  local off = 0.0

  -- Swing pushes the "e" and "a" (odd 16th positions) later.
  if (pos16 % 2) == 1 then
    off = off + swing * sixteenth_qn
  end

  -- Family lay-back: backbeat sits furthest behind, hats just a hair late.
  local fam = seq_role_family(role)
  if fam == "backbeat" then
    off = off + 0.015
  elseif fam == "hat" then
    off = off + 0.006
  elseif fam == "perc" then
    off = off + 0.010
  end

  -- Tiny deterministic humanize so repeated steps aren't identical.
  off = off + (seq_pattern_rand(pos16 * 13.7 + 3.0) - 0.5) * 0.008
  return off
end

function seq_gen_style_exists(style_key)
  if type(style_key) ~= "string" then
    return false
  end
  return SEQ_GEN_TEMPLATES[style_key] ~= nil
end

function normalize_seq_gen_style(style_key)
  if seq_gen_style_exists(style_key) then
    return style_key
  end
  return "basic"
end

function get_seq_gen_style_label(style_key)
  style_key = normalize_seq_gen_style(style_key)
  for _, style in ipairs(SEQ_GEN_STYLE_ORDER) do
    if style.key and style.key == style_key then
      return style.label
    end
  end
  return "Basic"
end

function classify_seq_role_text(text)
  local s = tostring(text or ""):lower()
  if s == "" then
    return nil
  end
  if s:find("kick", 1, true) or s:find("kck", 1, true) then
    return "kick"
  end
  if s:find("snare", 1, true) or s:find("snr", 1, true) then
    return "snare"
  end
  if s:find("clap", 1, true) then
    return "clap"
  end
  if s:find("rim", 1, true) or s:find("snap", 1, true) then
    return "rim"
  end
  if s:find("tom", 1, true) then
    return "tom"
  end
  if s:find("ride", 1, true) then
    return "ride"
  end
  if s:find("crash", 1, true) or s:find("cymbal", 1, true) then
    return "crash"
  end
  if s:find("hihat", 1, true) or s:find("hi hat", 1, true) or s:find("hat", 1, true)
      or s:find("hh", 1, true) then
    return "hat"
  end
  if s:find("808", 1, true) then
    return "808"
  end
  if s:find("sub", 1, true) or s:find("bass", 1, true) then
    return "bass"
  end
  if s:find("perc", 1, true) or s:find("percussion", 1, true) or s:find("shaker", 1, true)
      or s:find("tamb", 1, true) or s:find("cowbell", 1, true) then
    return "perc"
  end
  if s:find("riser", 1, true) or s:find("impact", 1, true) or s:find("sweep", 1, true)
      or s:find("whoosh", 1, true) or s:find("sfx", 1, true) or s:find("fx", 1, true) then
    return "fx"
  end
  if s:find("vocal", 1, true) or s:find("vox", 1, true) or s:find("voice", 1, true) then
    return "vocal"
  end
  if s:find("swell", 1, true) then
    return "swell"
  end
  return nil
end

function infer_seq_track_role(slot)
  if not slot then
    return "other"
  end

  local role = classify_seq_role_text(slot.sample_tag)
  if role then
    return role
  end

  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if sample and type(sample.tags) == "table" then
    for _, tag in ipairs(sample.tags) do
      role = classify_seq_role_text(tag)
      if role then
        return role
      end
    end
  end

  role = classify_seq_role_text(sample and sample.name)
      or classify_seq_role_text(sample and sample.path)
      or classify_seq_role_text(slot.sample_name)
      or classify_seq_role_text(slot.name)

  return role or "other"
end

function seq_random_control_alpha(active_key, control_key, related)
  if active_key and active_key ~= "" then
    if active_key == control_key then
      return 128
    end
    if related then
      for i = 1, #related do
        if active_key == related[i] then
          return 128
        end
      end
    end
    return 38
  end
  return 170
end

function seq_imgui_right_clicked()
  return ctx and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 1)
end

function seq_imgui_right_released()
  return ctx and r.ImGui_IsMouseReleased and r.ImGui_IsMouseReleased(ctx, 1)
end

SEQ_FINE_DRAG_SCALE = 0.12

function seq_fine_drag_down()
  return is_shift_down and is_shift_down() or false
end

function seq_random_knob_control(id, dl, x, y, size, value, min_v, max_v, alpha, tooltip, opts)
  opts = opts or {}
  size = math.max(12.0, size or 24.0)
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if max_v <= min_v then
    max_v = min_v + 1.0
  end
  local caption = opts.caption
  local h = opts.h or size
  local w = opts.w or size

  value = math.max(min_v, math.min(max_v, value or min_v))
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, w, h)
  local active = r.ImGui_IsItemActive(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local fine = seq_fine_drag_down()
  if hovered and tooltip and tooltip ~= "" and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, tooltip)
  end
  local changed = false
  local released = false

  if active then
    local mx, my = r.ImGui_GetMousePos(ctx)
    my = my or 0.0
    if (not state.seq_random_knob_drag) or state.seq_random_knob_drag.id ~= id then
      state.seq_random_knob_drag = { id = id, start_value = value, start_my = my, fine = fine }
    end
    local drag = state.seq_random_knob_drag
    if drag.fine ~= fine then
      drag.start_value = value
      drag.start_my = my
      drag.fine = fine
    end
    local sensitivity = (max_v - min_v) / 160.0
    if fine then
      sensitivity = sensitivity * SEQ_FINE_DRAG_SCALE
    end
    local start_my = drag.start_my or my
    local drag_y = my - start_my
    local new_value = (drag.start_value or value) - drag_y * sensitivity
    new_value = math.max(min_v, math.min(max_v, new_value))
    if math.abs(new_value - value) > 1e-9 then
      value = new_value
      changed = true
    end
  elseif state.seq_random_knob_drag and state.seq_random_knob_drag.id == id then
    state.seq_random_knob_drag = nil
    released = true
  end

  local knob_x, knob_y = x, y
  if caption and caption ~= "" then
    local pill_bg = build_color_rrgbbaa(28, 34, 46, alpha)
    local edge = hovered and UI_THEME.accent or build_color_rrgbbaa(90, 108, 132, math.min(255, alpha + 40))
    ui_draw_panel(dl, x, y, x + w, y + h, 5.0, pill_bg, edge, hovered, active)
    local ctw = select(1, r.ImGui_CalcTextSize(ctx, caption)) or 24.0
    local cap_w = math.max(34.0, ctw + 14.0)
    r.ImGui_DrawList_AddRectFilled(dl, x + 3.0, y + 3.0, x + cap_w - 2.0, y + h - 3.0, 0x000000AA, 4.0)
    local cth = select(2, r.ImGui_CalcTextSize(ctx, caption)) or 12.0
    r.ImGui_DrawList_AddText(dl, x + (cap_w - ctw) * 0.5, y + (h - cth) * 0.5, 0xF4F0E8FF, caption)
    knob_x = x + w - size - 3.0
    knob_y = y + (h - size) * 0.5
  end

  local cx = knob_x + size * 0.5
  local cy = knob_y + size * 0.5
  local radius = size * 0.5 - 1.5
  local bg = build_color_rrgbbaa(33, 40, 54, alpha)
  local ring = build_color_rrgbbaa(120, 145, 176, math.min(255, alpha + 35))
  local tip = build_color_rrgbbaa(255, 221, 132, math.min(255, alpha + 70))
  local hover_ring = build_color_rrgbbaa(255, 255, 255, math.min(255, alpha + 40))

  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, bg, 24)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, radius, ring, 24, 1.4)
  if hovered or active then
    r.ImGui_DrawList_AddCircle(dl, cx, cy, radius + 1.5, hover_ring, 24, 1.0)
  end

  local t = (value - min_v) / (max_v - min_v)
  -- Classic rotary: 7:30 (min) clockwise through 12:00 to 4:30 (max).
  local angle_min = math.pi * 0.75
  local angle_max = math.pi * 2.25
  local angle = angle_min + t * (angle_max - angle_min)
  local arc_r = radius - 1.0
  local function stroke_arc(a0, a1, color, thickness, segments)
    local n = math.max(6, segments or 14)
    local prev_x, prev_y = nil, nil
    for i = 0, n do
      local a = a0 + (a1 - a0) * (i / n)
      local ax = cx + math.cos(a) * arc_r
      local ay = cy + math.sin(a) * arc_r
      if prev_x then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, ax, ay, color, thickness)
      end
      prev_x, prev_y = ax, ay
    end
  end
  stroke_arc(angle_min, angle_max, build_color_rrgbbaa(70, 84, 104, math.min(255, alpha + 20)), 2.0, 16)
  if t > 0.001 then
    stroke_arc(angle_min, angle, tip, 2.2, math.max(6, math.floor(16 * t)))
  end
  local tip_r = radius - 4.0
  local tx = cx + math.cos(angle) * tip_r
  local ty = cy + math.sin(angle) * tip_r
  r.ImGui_DrawList_AddLine(dl, cx, cy, tx, ty, tip, 2.2)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 2.0, tip, 8)

  return changed, value, active, released
end

function seq_random_seed_button(id, dl, x, y, w, h, alpha)
  w = math.max(10.0, w or 16.0)
  h = math.max(10.0, h or 14.0)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg = hovered and UI_THEME.surface_hvr or UI_THEME.surface
  local edge = hovered and UI_THEME.accent or UI_THEME.border
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered, pressed)

  local pip = hovered and 0xFFFFFFFF or UI_THEME.text_dim
  local px0 = x + w * 0.28
  local px1 = x + w * 0.72
  local py0 = y + h * 0.30
  local py1 = y + h * 0.70
  r.ImGui_DrawList_AddCircleFilled(dl, px0, py0, 1.2, pip, 8)
  r.ImGui_DrawList_AddCircleFilled(dl, px1, py0, 1.2, pip, 8)
  r.ImGui_DrawList_AddCircleFilled(dl, (px0 + px1) * 0.5, (py0 + py1) * 0.5, 1.2, pip, 8)
  r.ImGui_DrawList_AddCircleFilled(dl, px0, py1, 1.2, pip, 8)
  r.ImGui_DrawList_AddCircleFilled(dl, px1, py1, 1.2, pip, 8)

  return clicked
end

function seq_random_refresh_button(id, dl, x, y, w, h, alpha)
  w = math.max(10.0, w or 16.0)
  h = math.max(10.0, h or 14.0)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local bg = hovered and UI_THEME.surface_hvr or UI_THEME.surface
  local edge = hovered and UI_THEME.accent or UI_THEME.border
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered, pressed)
  local col = hovered and 0xFFFFFFFF or UI_THEME.text_dim
  local cx, cy = x + w * 0.5, y + h * 0.5
  local rad = math.min(w, h) * 0.28
  local function arc(a0, a1)
    local prev_x, prev_y = nil, nil
    for i = 0, 7 do
      local a = a0 + (a1 - a0) * (i / 7)
      local ax = cx + math.cos(a) * rad
      local ay = cy + math.sin(a) * rad
      if prev_x then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, ax, ay, col, 1.3)
      end
      prev_x, prev_y = ax, ay
    end
  end
  arc(-0.2, 2.2)
  arc(math.pi - 0.2, math.pi + 2.2)
  r.ImGui_DrawList_AddTriangleFilled(
    dl, cx + rad + 1.2, cy - 1.6, cx + rad - 2.4, cy + 1.8, cx + rad + 2.2, cy + 1.8, col
  )
  if hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Swap varied samples, keep which notes vary")
  end
  return clicked
end

function seq_random_beat_drag(id, dl, x, y, w, h, value, alpha, tooltip)
  w = math.max(70.0, w or 108.0)
  h = math.max(16.0, h or 20.0)
  alpha = alpha or 170
  value = math.max(-1.0, math.min(1.0, tonumber(value) or 0.0))
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, w, h)
  local active = r.ImGui_IsItemActive(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local fine = seq_fine_drag_down()
  if hovered and tooltip and tooltip ~= "" and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, tooltip)
  end
  local changed = false
  if active then
    local mx = r.ImGui_GetMousePos(ctx)
    mx = mx or x
    if (not state.seq_random_knob_drag) or state.seq_random_knob_drag.id ~= id then
      state.seq_random_knob_drag = { id = id, start_value = value, start_mx = mx, fine = fine }
    end
    local drag = state.seq_random_knob_drag
    if drag.fine ~= fine then
      drag.start_value = value
      drag.start_mx = mx
      drag.fine = fine
    end
    local dx = mx - (drag.start_mx or mx)
    local scale = fine and SEQ_FINE_DRAG_SCALE or 1.0
    local new_value = (drag.start_value or value) + dx / math.max(36.0, w * 0.48) * scale
    new_value = math.max(-1.0, math.min(1.0, new_value))
    if math.abs(new_value - value) > 1e-6 then
      value = new_value
      changed = true
    end
  elseif state.seq_random_knob_drag and state.seq_random_knob_drag.id == id then
    state.seq_random_knob_drag = nil
  end

  local bg = build_color_rrgbbaa(28, 34, 46, alpha)
  local edge = hovered and UI_THEME.accent or build_color_rrgbbaa(90, 108, 132, math.min(255, alpha + 40))
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered, active)
  local mid = x + w * 0.5
  r.ImGui_DrawList_AddLine(dl, mid, y + 3.0, mid, y + h - 3.0, 0xFFFFFF28, 1.0)
  local t = (value + 1.0) * 0.5
  local fill_x = x + 3.0 + t * (w - 6.0)
  local fill_col = value >= 0.0 and 0xFFE7A6AA or 0xA8C8F0AA
  if math.abs(value) > 0.03 then
    if fill_x >= mid then
      r.ImGui_DrawList_AddRectFilled(dl, mid, y + 3.0, fill_x, y + h - 3.0, fill_col, 3.0)
    else
      r.ImGui_DrawList_AddRectFilled(dl, fill_x, y + 3.0, mid, y + h - 3.0, fill_col, 3.0)
    end
  end
  local text = seq_format_beat_drag(value)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  tw, th = tw or 40.0, th or 12.0
  local tx = x + (w - tw) * 0.5
  local ty = y + (h - th) * 0.5
  r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x00000099, text)
  r.ImGui_DrawList_AddText(dl, tx, ty, 0xF4F0E8FF, text)
  return changed, value, active
end

function seq_random_range_control(id, dl, x, y, w, h, lo, hi, min_v, max_v, alpha, opts)
  opts = opts or {}
  w = math.max(64.0, w or 120.0)
  h = math.max(16.0, h or 20.0)
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if max_v <= min_v then max_v = min_v + 1.0 end
  alpha = alpha or 170
  local step = opts.step
  local snap = opts.snap
  local snap_free = opts.shift_free and is_shift_down and is_shift_down()
  local function apply_snap(v)
    if snap and (not snap_free) then
      v = snap(v)
    elseif step and step > 0 then
      v = min_v + math.floor((v - min_v) / step + 0.5) * step
    end
    if v < min_v then v = min_v elseif v > max_v then v = max_v end
    return v
  end
  lo, hi = seq_normalize_range(lo, hi, min_v, max_v)
  if (step and step > 0) or (snap and not snap_free) then
    lo, hi = apply_snap(lo), apply_snap(hi)
    lo, hi = seq_normalize_range(lo, hi, min_v, max_v)
  end

  local caption = opts.caption
  local cap_w = 0.0
  if caption and caption ~= "" then
    local ctw = select(1, r.ImGui_CalcTextSize(ctx, caption)) or 24.0
    cap_w = math.max(34.0, ctw + 14.0)
  end
  local ctrl_x = x + cap_w
  local ctrl_w = math.max(28.0, w - cap_w)

  r.ImGui_SetCursorScreenPos(ctx, ctrl_x, y)
  r.ImGui_InvisibleButton(ctx, id, ctrl_w, h)
  local active = r.ImGui_IsItemActive(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local over = mx and my and mx >= x and mx <= x + w and my >= y and my <= y + h
  local fine = seq_fine_drag_down()
  if (hovered or over) and opts.tooltip and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, opts.tooltip)
  end
  local changed = false
  local span = max_v - min_v
  local to_norm = opts.to_norm
  local from_norm = opts.from_norm
  local function norm_at(px)
    local t = (px - ctrl_x) / math.max(1.0, ctrl_w)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return t
  end
  local function value_from_norm(t, skip_snap)
    local v = from_norm and from_norm(t) or (min_v + t * span)
    if skip_snap then
      if v < min_v then v = min_v elseif v > max_v then v = max_v end
      return v
    end
    return apply_snap(v)
  end
  local function value_at(px)
    return value_from_norm(norm_at(px))
  end
  local function norm_from_value(v)
    if to_norm then
      local t = to_norm(v)
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      return t
    end
    return (v - min_v) / span
  end
  local function x_at(v)
    return ctrl_x + norm_from_value(v) * ctrl_w
  end

  -- Geometric hit: InvisibleButton is left-click only, and mouse-down can hitch.
  local right_reset = over and (seq_imgui_right_released() or seq_imgui_right_clicked())
  if right_reset then
    local rlo = opts.reset_lo
    local rhi = opts.reset_hi
    if rlo == nil then rlo = min_v end
    if rhi == nil then rhi = rlo end
    lo, hi = seq_normalize_range(rlo, rhi, min_v, max_v)
    if (step and step > 0) or (snap and not snap_free) then
      lo, hi = apply_snap(lo), apply_snap(hi)
      lo, hi = seq_normalize_range(lo, hi, min_v, max_v)
    end
    changed = true
    state.seq_random_knob_drag = nil
  elseif active and not (r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 1)) then
    local mx = r.ImGui_GetMousePos(ctx)
    mx = mx or x
    if (not state.seq_random_knob_drag) or state.seq_random_knob_drag.id ~= id then
      local lo_x, hi_x = x_at(lo), x_at(hi)
      local unified = seq_range_is_single(lo, hi, (step or span * 0.02) * 0.6)
      local handle = "body"
      if unified then
        -- First move away from the collapsed value opens the range again.
        handle = "split"
      elseif math.abs(mx - lo_x) <= 8.0 and math.abs(mx - lo_x) <= math.abs(mx - hi_x) then
        handle = "lo"
      elseif math.abs(mx - hi_x) <= 8.0 then
        handle = "hi"
      end
      state.seq_random_knob_drag = {
        id = id, handle = handle, start_lo = lo, start_hi = hi, start_mx = mx, fine = fine,
      }
    end
    local drag = state.seq_random_knob_drag
    if drag.fine ~= fine then
      drag.start_lo, drag.start_hi = lo, hi
      drag.start_mx = mx
      drag.fine = fine
    end
    local scale = fine and SEQ_FINE_DRAG_SCALE or 1.0
    local function fine_or_abs(start_v)
      if fine then
        local dt = (norm_at(mx) - norm_at(drag.start_mx or mx)) * scale
        return value_from_norm(norm_from_value(start_v) + dt, true)
      end
      return value_at(mx)
    end
    local v = fine_or_abs((drag.handle == "hi") and (drag.start_hi or hi) or (drag.start_lo or lo))
    if drag.handle == "split" then
      local start = drag.start_lo or lo
      if v < start then
        lo, hi = v, start
        drag.handle = "lo"
      elseif v > start then
        lo, hi = start, v
        drag.handle = "hi"
      else
        lo, hi = start, start
      end
    elseif drag.handle == "lo" then
      lo = math.min(v, hi)
    elseif drag.handle == "hi" then
      hi = math.max(v, lo)
    elseif to_norm and from_norm then
      local dt = (norm_at(mx) - norm_at(drag.start_mx or mx)) * scale
      local width_t = norm_from_value(drag.start_hi or hi) - norm_from_value(drag.start_lo or lo)
      local nlo_t = norm_from_value(drag.start_lo or lo) + dt
      if nlo_t < 0.0 then nlo_t = 0.0 end
      if nlo_t + width_t > 1.0 then nlo_t = 1.0 - width_t end
      lo, hi = value_from_norm(nlo_t, fine), value_from_norm(nlo_t + width_t, fine)
    else
      local dv
      if fine then
        dv = (norm_at(mx) - norm_at(drag.start_mx or mx)) * span * scale
      else
        dv = value_at(mx) - value_at(drag.start_mx or mx)
      end
      local nlo = (drag.start_lo or lo) + dv
      local nhi = (drag.start_hi or hi) + dv
      local width = (drag.start_hi or hi) - (drag.start_lo or lo)
      if nlo < min_v then nlo, nhi = min_v, min_v + width end
      if nhi > max_v then nhi, nlo = max_v, max_v - width end
      lo, hi = seq_normalize_range(nlo, nhi, min_v, max_v)
    end
    if not fine then
      lo, hi = apply_snap(lo), apply_snap(hi)
    end
    lo, hi = seq_normalize_range(lo, hi, min_v, max_v)
    changed = true
  elseif state.seq_random_knob_drag and state.seq_random_knob_drag.id == id then
    state.seq_random_knob_drag = nil
  end

  local bg = build_color_rrgbbaa(28, 34, 46, alpha)
  local edge = hovered and UI_THEME.accent or build_color_rrgbbaa(90, 108, 132, math.min(255, alpha + 40))
  ui_draw_panel(dl, x, y, x + w, y + h, 5.0, bg, edge, hovered, active)
  if cap_w > 0 then
    r.ImGui_DrawList_AddRectFilled(dl, x + 3.0, y + 3.0, x + cap_w - 2.0, y + h - 3.0, 0x000000AA, 4.0)
    local ctw, cth = r.ImGui_CalcTextSize(ctx, caption)
    ctw, cth = ctw or 20.0, cth or 12.0
    r.ImGui_DrawList_AddText(dl, x + (cap_w - ctw) * 0.5, y + (h - cth) * 0.5, 0xF4F0E8FF, caption)
  end
  local lo_x, hi_x = x_at(lo), x_at(hi)
  r.ImGui_DrawList_AddRectFilled(dl, lo_x, y + 4.0, math.max(lo_x + 2.0, hi_x), y + h - 4.0, 0xFFE7A688, 3.0)
  local unified = seq_range_is_single(lo, hi, (step or span * 0.02) * 0.6)
  local function thumb(px)
    r.ImGui_DrawList_AddRectFilled(dl, px - 3.0, y + 2.0, px + 3.0, y + h - 2.0, 0xFFE7A6FF, 2.0)
  end
  thumb(lo_x)
  if not unified then
    thumb(hi_x)
  end
  local label = opts.format and opts.format(lo, hi) or string.format("%.2f–%.2f", lo, hi)
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  tw, th = tw or 24.0, th or 12.0
  local tx = ctrl_x + (ctrl_w - tw) * 0.5
  local ty = y + (h - th) * 0.5
  r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x00000099, label)
  r.ImGui_DrawList_AddText(dl, tx, ty, 0xF4F0E8FF, label)
  return changed, lo, hi, active
end

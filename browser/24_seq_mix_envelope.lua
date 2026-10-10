-- Sample Map Browser module: seq_mix_envelope
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- ===== Sequencer track mix + drum volume envelope ========================
-- Per-track volume/pan/mute/solo control the linked REAPER track. A free
-- breakpoint envelope (arbitrary points in sample time) is stamped onto every
-- synced hit as a take volume envelope so it shapes each drum instance.

SEQ_ENV_AMP_MAX = 3.0
SEQ_ENV_POINT_LIMIT = 64
SEQ_ENV_PREVIEW_W = 100.0
SEQ_ENV_CURVE_KMAX = 7.0

function seq_default_track_env()
  return {
    points = {
      { t = 0.0, amp = 1.0 },
      { t = 1.0, amp = 1.0 },
    },
  }
end

function seq_env_clamp_amp(amp)
  amp = tonumber(amp) or 1.0
  if amp < 0.0 then return 0.0 end
  if amp > 4.0 then return 4.0 end
  return amp
end

function seq_env_sort_points(points)
  table.sort(points, function(a, b)
    return (a.t or 0.0) < (b.t or 0.0)
  end)
  return points
end

-- Convert the previous ADSR + item-fade envelope into free points.
function seq_legacy_adsr_to_points(env, length)
  env = env or {}
  length = math.max(0.001, length or 0.25)
  local atk = math.max(0.0, math.min(0.25, tonumber(env.atk) or 0.0))
  local dec = math.max(0.0, math.min(0.40, tonumber(env.decay) or 0.02))
  local rel = math.max(0.0, math.min(0.80, tonumber(env.release) or 0.0))
  local peak = math.min(4.0, 1.0 + math.max(0.0, math.min(2.0, tonumber(env.transient) or 0.0)))
  local sus = math.max(0.0, math.min(peak, tonumber(env.sustain) or 1.0))
  local fade_in = math.max(0.0, tonumber(env.fade_in) or 0.0)
  local fade_out = math.max(0.0, tonumber(env.fade_out) or 0.0)
  local has_shape = atk > 0.0005
      or (tonumber(env.transient) or 0.0) > 0.001
      or sus < 0.999
      or rel > 0.0005
  local has_fade = fade_in > 0.0005 or fade_out > 0.0005
  if not has_shape and not has_fade then
    return { { t = 0.0, amp = 1.0 }, { t = length, amp = 1.0 } }
  end

  atk = math.min(atk, length * 0.49)
  rel = math.min(rel, length * 0.49)
  local t_dec = math.min(length, atk + dec)
  local t_rel = math.max(t_dec, length - rel)
  local pts = {}
  local function add(t, amp)
    t = math.max(0.0, math.min(length, t))
    amp = seq_env_clamp_amp(amp)
    local last = pts[#pts]
    if last and math.abs(last.t - t) < 0.00005 then
      last.amp = amp
      return
    end
    pts[#pts + 1] = { t = t, amp = amp }
  end

  if has_shape then
    if atk > 0.0005 then
      add(0.0, 0.00001)
      add(atk, peak)
    else
      add(0.0, peak)
    end
    if t_dec > atk + 0.00005 then
      add(t_dec, sus)
    elseif math.abs(peak - sus) > 0.001 then
      add(math.min(length, atk + 0.001), sus)
    end
    if t_rel > t_dec + 0.00005 then
      add(t_rel, sus)
    end
    if rel > 0.0005 then
      add(length, 0.00001)
    else
      add(length, sus)
    end
  else
    add(0.0, 1.0)
    add(length, 1.0)
  end

  if fade_in > 0.0005 then
    add(0.0, 0.00001)
    add(math.min(length, fade_in), seq_env_levels_at({ points = pts }, fade_in, length))
  end
  if fade_out > 0.0005 then
    local t_fo = math.max(0.0, length - fade_out)
    add(t_fo, seq_env_levels_at({ points = pts }, t_fo, length))
    add(length, 0.00001)
  end
  seq_env_sort_points(pts)
  return pts
end

function seq_normalize_track_env(env)
  if type(env) ~= "table" then
    return seq_default_track_env()
  end
  local pts = {}
  if type(env.points) == "table" then
    for _, p in ipairs(env.points) do
      if type(p) == "table" then
        pts[#pts + 1] = {
          t = math.max(0.0, tonumber(p.t) or 0.0),
          amp = seq_env_clamp_amp(p.amp),
          curve = seq_env_clamp_curve(p.curve),
        }
      end
    end
  end
  if #pts == 0 then
    local atk = tonumber(env.atk) or 0.0
    local dec = tonumber(env.decay) or 0.0
    local rel = tonumber(env.release) or 0.0
    local fi = tonumber(env.fade_in) or 0.0
    local fo = tonumber(env.fade_out) or 0.0
    local length = math.max(0.25, atk + dec + rel + 0.10, fi + fo + 0.05)
    pts = seq_legacy_adsr_to_points(env, length)
  end
  if #pts == 0 then
    pts = { { t = 0.0, amp = 1.0 }, { t = 1.0, amp = 1.0 } }
  end
  seq_env_sort_points(pts)
  local merged = {}
  for _, p in ipairs(pts) do
    local last = merged[#merged]
    if last and math.abs(last.t - p.t) < 0.00005 then
      last.amp = p.amp
      last.curve = p.curve
    else
      merged[#merged + 1] = p
    end
  end
  if #merged > SEQ_ENV_POINT_LIMIT then
    local kept = { merged[1] }
    local extra = SEQ_ENV_POINT_LIMIT - 2
    local inner = #merged - 2
    if extra > 0 and inner > 0 then
      for i = 1, extra do
        local idx = 1 + math.floor(i * inner / (extra + 1) + 0.5)
        kept[#kept + 1] = merged[math.max(2, math.min(#merged - 1, idx + 1))]
      end
    end
    kept[#kept + 1] = merged[#merged]
    merged = kept
  end
  for i = 1, #merged - 1 do
    merged[i].curve = seq_env_seg_clamp_curve(merged[i].amp, merged[i + 1].amp, merged[i].curve)
  end
  if #merged > 0 then
    merged[#merged].curve = 0.0
  end
  return { points = merged }
end

function seq_env_insert_point(points, t, amp)
  points = points or {}
  t = math.max(0.0, tonumber(t) or 0.0)
  amp = seq_env_clamp_amp(amp)
  local idx = #points + 1
  for i, p in ipairs(points) do
    if t < (p.t or 0.0) then
      idx = i
      break
    end
  end
  table.insert(points, idx, { t = t, amp = amp, curve = 0.0 })
  return idx
end

function seq_env_clamp_curve(curve)
  curve = tonumber(curve) or 0.0
  if curve < -1.0 then return -1.0 end
  if curve > 1.0 then return 1.0 end
  if math.abs(curve) < 0.0005 then return 0.0 end
  return curve
end

-- curve is signed ease strength in [-1, 1], independent of amplitude span.
-- Power eases stay between the two endpoints, so they cannot overshoot.
function seq_env_seg_clamp_curve(amp0, amp1, curve)
  return seq_env_clamp_curve(curve)
end

function seq_env_seg_ease(u, curve)
  u = tonumber(u) or 0.0
  if u < 0.0 then u = 0.0 elseif u > 1.0 then u = 1.0 end
  curve = seq_env_clamp_curve(curve)
  if math.abs(curve) < 0.0005 then
    return u
  end
  local kmax = SEQ_ENV_CURVE_KMAX or 7.0
  local k = 1.0 + math.abs(curve) * (kmax - 1.0)
  if curve > 0.0 then
    return u ^ k
  end
  return 1.0 - (1.0 - u) ^ k
end

-- Positive curve holds the first point longer; negative jumps toward the second.
-- Always stays between amp0 and amp1.
function seq_env_seg_eval(amp0, amp1, u, curve)
  amp0 = amp0 or 1.0
  amp1 = amp1 or 1.0
  return amp0 + (amp1 - amp0) * seq_env_seg_ease(u, curve)
end

function seq_env_seg_curve_for_amp(amp0, amp1, u, amp)
  amp0 = amp0 or 1.0
  amp1 = amp1 or 1.0
  u = tonumber(u) or 0.5
  if u < 0.08 then u = 0.08 elseif u > 0.92 then u = 0.92 end
  local span = amp1 - amp0
  if math.abs(span) < 0.0001 then
    return 0.0
  end
  local lo, hi = amp0, amp1
  if hi < lo then lo, hi = hi, lo end
  amp = tonumber(amp) or (amp0 + span * u)
  if amp < lo then amp = lo elseif amp > hi then amp = hi end
  local n = (amp - amp0) / span
  if n < 0.0001 then n = 0.0001 elseif n > 0.9999 then n = 0.9999 end
  local kmax = SEQ_ENV_CURVE_KMAX or 7.0
  local function k_to_curve(k, sign)
    k = math.max(1.0, math.min(kmax, k))
    return seq_env_clamp_curve(sign * (k - 1.0) / (kmax - 1.0))
  end
  if math.abs(n - u) < 0.002 then
    return 0.0
  end
  if n < u then
    local lu = math.log(u)
    if math.abs(lu) < 1e-8 then return 0.0 end
    return k_to_curve(math.log(n) / lu, 1.0)
  end
  local l1 = math.log(1.0 - u)
  if math.abs(l1) < 1e-8 then return 0.0 end
  return k_to_curve(math.log(1.0 - n) / l1, -1.0)
end

function seq_env_format_point_tip(t, amp)
  local db = seq_format_track_volume(amp or 1.0)
  if db == "-inf" then
    db = "-inf dB"
  else
    db = db .. " dB"
  end
  return string.format("%.0f ms · %s", (t or 0.0) * 1000.0, db)
end

function seq_env_sync_to_length(env, length)
  env = seq_normalize_track_env(env)
  length = math.max(0.001, length or 1.0)
  if not seq_env_shape_active_norm(env) then
    env.points = {
      { t = 0.0, amp = 1.0 },
      { t = length, amp = 1.0 },
    }
    return env
  end
  for _, p in ipairs(env.points) do
    if (p.t or 0.0) > length then
      p.t = length
    end
  end
  seq_env_sort_points(env.points)
  return env
end

-- REAPER track volume: linear amplitude → dB (1.0 = 0 dB, 4.0 ≈ +12 dB).
-- Global helpers (not local) to stay under Lua's 200-local main-chunk limit.
function seq_format_track_volume(v)
  if not v or v < 0.0000000298023223876953125 then return "-inf" end
  local db = math.log(v) * 8.6858896380650365530225783783321
  if db >= -0.05 and db <= 0.05 then return "0.0" end
  if db > 0 then return string.format("+%.1f", db) end
  return string.format("%.1f", db)
end

-- Compact volume bar: linear in dB from -48 to +12 so 0 dB sits at 80%.
SEQ_VOL_FADER_MIN_DB = -48.0
SEQ_VOL_FADER_MAX_DB = 12.0

function seq_vol_amp_to_pos(amp)
  if not amp or amp < 0.0000000298023223876953125 then
    return 0.0
  end
  local db = math.log(amp) * 8.6858896380650365530225783783321
  local t = (db - SEQ_VOL_FADER_MIN_DB) / (SEQ_VOL_FADER_MAX_DB - SEQ_VOL_FADER_MIN_DB)
  if t < 0.0 then return 0.0 end
  if t > 1.0 then return 1.0 end
  return t
end

function seq_vol_pos_to_amp(pos)
  pos = math.max(0.0, math.min(1.0, pos or 0.0))
  if pos <= 0.0 then
    return 0.0
  end
  local db = SEQ_VOL_FADER_MIN_DB + pos * (SEQ_VOL_FADER_MAX_DB - SEQ_VOL_FADER_MIN_DB)
  local amp = math.exp(db * 0.11512925464970228420089957273422)
  if amp > 4.0 then
    return 4.0
  end
  return amp
end

function seq_format_track_pan(v)
  local pct = math.floor(math.abs(v or 0) * 100.0 + 0.5)
  if pct == 0 then return "C" end
  if (v or 0) < 0 then return tostring(pct) .. "L" end
  return tostring(pct) .. "R"
end

function seq_normalize_slot_mix(slot)
  if not slot then return end
  if type(slot.volume) ~= "number" then slot.volume = 1.0 end
  -- Match REAPER track fader range: 0 (-inf) .. 4 (+12 dB), unity at 1.0
  slot.volume = math.max(0.0, math.min(4.0, slot.volume))
  if type(slot.pan) ~= "number" then slot.pan = 0.0 end
  slot.pan = math.max(-1.0, math.min(1.0, slot.pan))
  slot.mute = slot.mute == true
  slot.solo = slot.solo == true
  slot.overlap = slot.overlap == true
  slot.env = seq_normalize_track_env(slot.env)
  seq_normalize_slot_layers(slot)
  seq_normalize_slot_midi(slot)
  seq_normalize_slot_candidates(slot)
end

function seq_midi_clamp_note(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then return 0 end
  if n > 127 then return 127 end
  return n
end

function seq_midi_note_name(n)
  n = seq_midi_clamp_note(n)
  return (SEQ_MIDI_PC_NAMES[(n % 12) + 1] or "?") .. tostring(math.floor(n / 12) - 2)
end

function seq_midi_slot_label(slot)
  if not slot then return "--" end
  local lo = seq_midi_clamp_note(slot.midi_lo or 36)
  local hi = seq_midi_clamp_note(slot.midi_hi or lo)
  if lo > hi then lo, hi = hi, lo end
  if lo == hi then
    return seq_midi_note_name(lo)
  end
  return seq_midi_note_name(lo) .. "+"
end

function seq_midi_used_notes(ignore_slot)
  local used = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot ~= ignore_slot then
      local lo = tonumber(slot.midi_lo)
      if lo then
        local hi = tonumber(slot.midi_hi) or lo
        if lo > hi then lo, hi = hi, lo end
        for n = lo, hi do
          used[n] = true
        end
      end
    end
  end
  return used
end

function seq_midi_default_note_for_slot(slot)
  local role = infer_seq_track_role(slot)
  local preferred = SEQ_MIDI_ROLE_NOTES[role] or 36
  local used = seq_midi_used_notes(slot)
  if not used[preferred] then
    return preferred
  end
  for delta = 1, 127 do
    local up, down = preferred + delta, preferred - delta
    if up <= 127 and not used[up] then return up end
    if down >= 0 and not used[down] then return down end
  end
  return preferred
end

function seq_normalize_slot_midi(slot)
  if not slot then return end
  local lo = tonumber(slot.midi_lo)
  local hi = tonumber(slot.midi_hi)
  if not lo then
    lo = seq_midi_default_note_for_slot(slot)
    hi = lo
  elseif not hi then
    hi = lo
  end
  lo = seq_midi_clamp_note(lo)
  hi = seq_midi_clamp_note(hi)
  if lo > hi then lo, hi = hi, lo end
  slot.midi_lo = lo
  slot.midi_hi = hi
end

function seq_midi_set_note(slot, note, as_range)
  if not slot then return false end
  note = seq_midi_clamp_note(note)
  seq_normalize_slot_midi(slot)
  if as_range then
    if note < slot.midi_lo then
      slot.midi_lo = note
    elseif note > slot.midi_hi then
      slot.midi_hi = note
    else
      slot.midi_lo = note
      slot.midi_hi = note
    end
  else
    slot.midi_lo = note
    slot.midi_hi = note
  end
  return true
end

function seq_midi_set_range(slot, lo, hi)
  if not slot then return false end
  lo = seq_midi_clamp_note(lo)
  hi = seq_midi_clamp_note(hi)
  if lo > hi then lo, hi = hi, lo end
  slot.midi_lo = lo
  slot.midi_hi = hi
  return true
end

function seq_midi_slot_matches(slot, note)
  if not slot then return false end
  note = tonumber(note)
  if not note then return false end
  seq_normalize_slot_midi(slot)
  return note >= slot.midi_lo and note <= slot.midi_hi
end

function seq_midi_any_solo()
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.solo then return true end
  end
  return false
end

function seq_midi_slot_audible(slot)
  if not slot or slot.mute then return false end
  if seq_midi_any_solo() and not slot.solo then return false end
  return true
end

function seq_midi_stop_voice(slot_id)
  if slot_id == nil then return end
  local key = tostring(slot_id)
  local voice = seq_midi_voices[key]
  if not voice then return end
  if voice.preview and r.CF_Preview_Stop then
    pcall(r.CF_Preview_Stop, voice.preview)
  end
  if voice.source and r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, voice.source)
  end
  seq_midi_voices[key] = nil
end

function seq_midi_stop_all_voices()
  for slot_id in pairs(seq_midi_voices) do
    seq_midi_stop_voice(slot_id)
  end
end

function seq_midi_trigger_slot(slot, vel)
  if not slot or not seq_midi_slot_audible(slot) then
    return false
  end
  vel = tonumber(vel) or 100
  if vel <= 0 then
    return false
  end
  if not slot.sample_path then
    return false
  end

  seq_midi_stop_voice(slot.id)
  local started = seq_player_trigger(slot, vel)
  if started then
    state.seq_track_play_anims = state.seq_track_play_anims or {}
    state.seq_track_play_anims[tostring(slot.id)] = {
      start_time = r.time_precise(),
      duration = 0.35,
    }
    return true
  end
  preview_seq_track_sample(slot)
  return true
end

function seq_midi_handle_note_on(note, vel)
  seq_midi_ensure_jsfx()
  note = seq_midi_clamp_note(note)
  vel = math.max(1, math.min(127, math.floor(tonumber(vel) or 100)))
  local now = r.time_precise()
  state.seq_midi_recent = state.seq_midi_recent or {}
  local last_t = state.seq_midi_recent[note]
  if last_t and (now - last_t) < 0.03 then
    return false
  end
  state.seq_midi_recent[note] = now
  local learn_id = state.seq_midi_learn_slot_id
  if learn_id then
    local slot = seq_find_track_slot_by_id(learn_id)
    if slot then
      seq_midi_set_note(slot, note, state.seq_midi_learn_range == true)
      state.seq_midi_learn_slot_id = nil
      state.seq_midi_learn_range = false
      save_config()
      if save_seq_project_state then save_seq_project_state() end
      seq_midi_trigger_slot(slot, vel)
      return true
    end
    state.seq_midi_learn_slot_id = nil
  end

  -- SampleMapPlayer plays via its trigger slider so the kit tracks meter.
  local hit = false
  for _, slot in ipairs(state.seq_tracks or {}) do
    if seq_midi_slot_matches(slot, note) then
      if seq_midi_trigger_slot(slot, vel) then
        hit = true
      end
    end
  end
  return hit
end

-- MIDI All devices / all channels. bits 0-4 = channel (0=all), bits 5-10 = device (63=all).
SEQ_MIDI_RECINPUT_ALL = 4096 + (63 * 32)
SEQ_MIDI_RECMODE_MONITOR = 2

function seq_midi_parent_track(create_if_missing)
  local tr = find_seq_parent_folder_track and find_seq_parent_folder_track() or nil
  if tr then
    return tr
  end
  if create_if_missing and create_seq_parent_folder_track then
    return create_seq_parent_folder_track()
  end
  return nil
end

function seq_midi_find_jsfx(tr)
  if not tr or not r.TrackFX_GetCount then
    return -1
  end
  local n = r.TrackFX_GetCount(tr) or 0
  for i = 0, n - 1 do
    local retval, name = r.TrackFX_GetFXName(tr, i, "")
    if type(retval) == "string" then
      name = retval
    end
    name = tostring(name or "")
    if name:find("Sample Map MIDI", 1, true) or name:find("SampleMapMIDI", 1, true) then
      return i
    end
  end
  return -1
end

function seq_midi_delete_jsfx(tr)
  if not tr or not r.TrackFX_Delete then
    return
  end
  local fx = seq_midi_find_jsfx(tr)
  if fx >= 0 then
    r.TrackFX_Delete(tr, fx)
  end
end

function seq_midi_strip_preview_jsfx()
  local tr = nil
  if preview_track then
    local valid = false
    if r.ValidatePtr2 then
      valid = r.ValidatePtr2(0, preview_track, "MediaTrack*") and true or false
    elseif r.ValidatePtr then
      valid = r.ValidatePtr(preview_track, "MediaTrack*") and true or false
    end
    if valid then
      tr = preview_track
    end
  end
  if not tr then
    for i = 0, r.CountTracks(0) - 1 do
      local cand = r.GetTrack(0, i)
      local _, name = r.GetTrackName(cand, "")
      if name == PREVIEW_TRACK_NAME then
        tr = cand
        break
      end
    end
  end
  if tr then
    seq_midi_delete_jsfx(tr)
  end
end

function seq_midi_ensure_jsfx()
  if not r.TrackFX_AddByName then
    state.seq_midi_jsfx_ready = false
    return false
  end
  local tr = seq_midi_parent_track(true)
  if not tr then
    state.seq_midi_jsfx_ready = false
    return false
  end
  local fx = seq_midi_find_jsfx(tr)
  if fx < 0 then
    -- Retry a failed add (e.g. JSFX not installed) at most every 2 s, not every call.
    local now = r.time_precise()
    local failed_at = state.seq_midi_jsfx_fail_at
    if failed_at and (now - failed_at) >= 0 and (now - failed_at) < 2.0 then
      state.seq_midi_jsfx_ready = false
      return false
    end
    for _, name in ipairs(SEQ_MIDI_JSFX_NAMES) do
      fx = r.TrackFX_AddByName(tr, name, false, 1)
      if fx and fx >= 0 then
        if r.TrackFX_SetOpen then
          r.TrackFX_SetOpen(tr, fx, false)
        end
        break
      end
    end
    state.seq_midi_jsfx_fail_at = (not fx or fx < 0) and now or nil
  end
  if fx and fx >= 0 then
    state.seq_midi_jsfx_ready = true
    seq_midi_strip_preview_jsfx()
    return true
  end
  state.seq_midi_jsfx_ready = false
  return false
end

function seq_player_find_jsfx(tr)
  if not tr or not r.TrackFX_GetCount then
    return -1
  end
  local n = r.TrackFX_GetCount(tr) or 0
  for i = 0, n - 1 do
    local retval, name = r.TrackFX_GetFXName(tr, i, "")
    if type(retval) == "string" then
      name = retval
    end
    name = tostring(name or "")
    if name:find("Sample Map Player", 1, true) or name:find("SampleMapPlayer", 1, true) then
      return i
    end
  end
  return -1
end

function seq_player_set_param(tr, fx, param, value)
  if not tr or not fx or fx < 0 or not r.TrackFX_SetParam then
    return
  end
  r.TrackFX_SetParam(tr, fx, param, value)
  if r.TrackFX_EndParamEdit then
    r.TrackFX_EndParamEdit(tr, fx, param)
  end
end

-- Slot ids are unique within a project; the JSFX instance slider goes to 999999.
function seq_player_instance_id(slot)
  local id = math.floor(tonumber(slot and slot.id) or 0)
  if id < 1 then
    id = 1
  elseif id > 999999 then
    id = ((id - 1) % 999999) + 1
  end
  return id
end

-- Random per-project key (1..999999) kept in ProjExtState. The JSFX reads
-- SampleMapPlayerData/<key>_<instance>.txt, so projects don't share config files.
function seq_player_project_key()
  local proj = get_current_project and get_current_project() or nil
  local now = r.time_precise()
  local cache = state.seq_player_proj_key_cache
  -- Re-read every 2 s (a project tab can be reused); without a project, keep the cached key.
  if cache and cache.proj == proj
      and (proj == nil or ((now - cache.at) >= 0 and (now - cache.at) < 2.0)) then
    return cache.key
  end
  local key = nil
  if proj and r.GetProjExtState then
    local ok, val = r.GetProjExtState(proj, PROJ_EXT_SECTION, "player_proj_key")
    if ok and ok ~= 0 then
      key = math.floor(tonumber(val) or 0)
    end
  end
  if not key or key < 1 or key > 999999 then
    -- Hash clock + addresses instead of math.random: the script reseeds the RNG
    -- with fixed seeds elsewhere, and this must not disturb that sequence.
    local seed = string.format("%s|%.6f|%d|%s", tostring(proj), now, os.time(), tostring({}))
    local h = 5381
    for i = 1, #seed do
      h = (h * 33 + seed:byte(i)) % 2147483647
    end
    key = (h % 999999) + 1
    if proj and r.SetProjExtState then
      pcall(r.SetProjExtState, proj, PROJ_EXT_SECTION, "player_proj_key", tostring(key))
    end
  end
  state.seq_player_proj_key_cache = { proj = proj, key = key, at = now }
  return key
end

-- True when the player JSFX on (tr, fx) has the proj_key slider (param 11).
-- Older copies of the JSFX don't; they only read the legacy <instance>.txt file.
function seq_player_fx_has_key(tr, fx)
  if not tr or not fx or fx < 0 or not r.TrackFX_GetParamName then
    return false
  end
  local ok, name = r.TrackFX_GetParamName(tr, fx, 11, "")
  if type(ok) == "string" then
    name = ok
  end
  return type(name) == "string" and name:find("Project key", 1, true) ~= nil
end

-- Write via a temp file and rename, so the JSFX never reads a half-written file.
function seq_player_write_file_atomic(path, body)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then
    return false
  end
  local wrote = f:write(body)
  f:close()
  if not wrote then
    os.remove(tmp)
    return false
  end
  if os.rename(tmp, path) then
    return true
  end
  -- Windows can't rename over an existing file.
  os.remove(path)
  if os.rename(tmp, path) then
    return true
  end
  os.remove(tmp)
  return false
end

function seq_player_collect_layers(slot)
  local layers = {}
  if slot and seq_layering_is_active and seq_layering_is_active(slot) then
    seq_normalize_slot_layers(slot)
    local function add_side(side)
      if type(side) ~= "table" or type(side.verts) ~= "table" then
        return
      end
      for i = 1, 3 do
        local vert = side.verts[i]
        if vert and type(vert.path) == "string" and vert.path ~= "" then
          layers[#layers + 1] = {
            path = vert.path,
            vol = math.max(0.0, tonumber(vert.vol) or 1.0),
          }
          if #layers >= 6 then
            return
          end
        end
      end
    end
    add_side(slot.layers.transient)
    if #layers < 6 then
      add_side(slot.layers.sustain)
    end
  end
  if #layers == 0 and slot and type(slot.sample_path) == "string" and slot.sample_path ~= "" then
    layers[1] = { path = slot.sample_path, vol = 1.0 }
  end
  return layers
end

function seq_player_config_sig(slot)
  if not slot then
    return ""
  end
  seq_normalize_slot_midi(slot)
  local parts = {
    tostring(slot.id or ""),
    tostring(slot.reaper_track_guid or ""),
    tostring(slot.sample_path or ""),
    tostring(slot.midi_lo or 36),
    tostring(slot.midi_hi or slot.midi_lo or 36),
    slot.overlap and "1" or "0",
  }
  local layers = seq_player_collect_layers(slot)
  parts[#parts + 1] = tostring(#layers)
  for i = 1, #layers do
    parts[#parts + 1] = layers[i].path
    parts[#parts + 1] = string.format("%.5f", layers[i].vol or 1)
  end
  local env = seq_normalize_track_env(slot.env)
  local pts = env.points or {}
  parts[#parts + 1] = tostring(#pts)
  for i = 1, #pts do
    local p = pts[i]
    parts[#parts + 1] = string.format(
      "%.5f:%.5f:%.5f", p.t or 0, p.amp or 1, p.curve or 0)
  end
  return table.concat(parts, "\n")
end

-- The JSFX opens "SampleMapPlayerData/<name>" relative to a base folder that
-- may be the resource, Data or Effects folder, so write each candidate.
function seq_player_cfg_paths(instance_id, proj_key)
  local res = (r.GetResourcePath and r.GetResourcePath()) or ""
  local name = string.format("%d.txt", instance_id)
  if proj_key then
    name = string.format("%d_%d.txt", proj_key, instance_id)
  end
  return {
    res .. "/Effects/SampleMapPlayerData/" .. name,
    res .. "/SampleMapPlayerData/" .. name,
    res .. "/Data/SampleMapPlayerData/" .. name,
  }
end

function seq_player_write_cfg(slot, proj_key)
  local id = seq_player_instance_id(slot)
  if not proj_key and id > 4095 then
    -- Legacy JSFX: instance slider stops at 4095.
    id = (id % 4095) + 1
  end
  seq_normalize_slot_midi(slot)
  local layers = seq_player_collect_layers(slot)
  local env = seq_normalize_track_env(slot.env)
  local pts = env.points or {}
  if #pts < 1 then
    pts = { { t = 0, amp = 1, curve = 0 }, { t = 1, amp = 1, curve = 0 } }
  end
  if #pts > 32 then
    local trimmed = {}
    for i = 1, 32 do
      trimmed[i] = pts[i]
    end
    pts = trimmed
  end
  if #layers > 6 then
    local trimmed = {}
    for i = 1, 6 do
      trimmed[i] = layers[i]
    end
    layers = trimmed
  end
  local lo = slot.midi_lo or 36
  local hi = slot.midi_hi or lo
  local lines = {
    "SMP1",
    string.format(
      "%.9g %.9g %.9g %.9g %.9g %.9g %d %d",
      0, lo, hi, lo, 1, slot.overlap and 1 or 0, #pts, #layers
    ),
  }
  for i = 1, #pts do
    local p = pts[i]
    lines[#lines + 1] = string.format(
      "%.9g %.9g %.9g", p.t or 0, p.amp or 1, p.curve or 0)
  end
  for i = 1, #layers do
    local layer = layers[i]
    lines[#lines + 1] = string.format(
      "%.9g %.9g %.9g %.9g %.9g %.9g", 0, 0, 0, 0, 0, layer.vol or 1)
    lines[#lines + 1] = tostring(layer.path or ""):gsub("[\r\n]", "")
  end
  local body = table.concat(lines, "\n") .. "\n"
  local paths = seq_player_cfg_paths(id, proj_key)
  for i = 1, #paths do
    local path = paths[i]
    local dir = path:match("^(.*)/[^/]+$")
    if dir and r.RecursiveCreateDirectory then
      r.RecursiveCreateDirectory(dir, 0)
    end
    seq_player_write_file_atomic(path, body)
  end
  return id
end

function seq_player_ensure_fx(slot)
  if not slot or not slot.reaper_track_guid or not r.TrackFX_AddByName then
    return nil, -1
  end
  local tr = get_track_by_guid(slot.reaper_track_guid)
  if not tr then
    return nil, -1
  end
  local fx = seq_player_find_jsfx(tr)
  if fx < 0 then
    -- Retry a failed add on this track at most every 2 s, not every frame.
    local fails = state.seq_player_fx_fail_at or {}
    state.seq_player_fx_fail_at = fails
    local guid = slot.reaper_track_guid
    local now = r.time_precise()
    local failed_at = fails[guid]
    if failed_at and (now - failed_at) >= 0 and (now - failed_at) < 2.0 then
      return tr, -1
    end
    for _, name in ipairs(SEQ_PLAYER_JSFX_NAMES) do
      fx = r.TrackFX_AddByName(tr, name, false, 1)
      if fx and fx >= 0 then
        if r.TrackFX_SetOpen then
          r.TrackFX_SetOpen(tr, fx, false)
        end
        break
      end
    end
    fails[guid] = (not fx or fx < 0) and now or nil
  end
  if not fx or fx < 0 then
    return tr, -1
  end
  return tr, fx
end

function seq_player_sync_slot(slot, force)
  if not slot then
    return false
  end
  local id = slot.id
  local proj_key = seq_player_project_key()
  local sig = tostring(proj_key) .. "\n" .. seq_player_config_sig(slot)
  local rt = seq_player_runtime[id]
  if not force and rt and rt.sig == sig then
    return true
  end
  local tr, fx = seq_player_ensure_fx(slot)
  if not tr or fx < 0 then
    return false
  end
  local has_key = seq_player_fx_has_key(tr, fx)
  local instance_id = seq_player_write_cfg(slot, has_key and proj_key or nil)
  local P = SEQ_PLAYER_PARAM
  if has_key then
    seq_player_set_param(tr, fx, 11, proj_key)
  end
  seq_player_set_param(tr, fx, P.instance_id, instance_id)
  seq_player_set_param(tr, fx, P.midi_lo, slot.midi_lo or 36)
  seq_player_set_param(tr, fx, P.midi_hi, slot.midi_hi or slot.midi_lo or 36)
  seq_player_set_param(tr, fx, P.root, slot.midi_lo or 36)
  seq_player_set_param(tr, fx, P.gain, 1)
  seq_player_set_param(tr, fx, P.pitch, 0)
  seq_player_set_param(tr, fx, P.overlap, slot.overlap and 1 or 0)
  -- The JSFX only checks for a change, so wrap below the slider max (1000000).
  local cur = math.floor(tonumber((r.TrackFX_GetParam(tr, fx, P.reload))) or 0)
  seq_player_set_param(tr, fx, P.reload, (cur + 1) % 1000000)
  seq_player_runtime[id] = { sig = sig }
  return true
end

-- Runs every frame: rebuild signatures only when state.seq_player_rev moved,
-- the track list or project changed, or every 0.5 s as a safety net for edits
-- that don't bump the revision.
function seq_player_sync_all()
  local tracks = state.seq_tracks or {}
  local now = r.time_precise()
  local rev = state.seq_player_rev or 0
  local proj = get_current_project and get_current_project() or nil
  local last = state.seq_player_sync_mark
  if last
      and last.rev == rev
      and last.tracks == tracks
      and last.n == #tracks
      and last.proj == proj
      and (now - last.at) >= 0 and (now - last.at) < 0.5 then
    return
  end
  for _, slot in ipairs(tracks) do
    seq_player_sync_slot(slot)
  end
  state.seq_player_sync_mark = { rev = rev, tracks = tracks, n = #tracks, proj = proj, at = now }
end

function seq_player_trigger(slot, vel)
  if not slot then
    return false
  end
  seq_player_sync_slot(slot)
  local tr, fx = seq_player_ensure_fx(slot)
  if not tr or fx < 0 then
    return false
  end
  vel = math.max(1, math.min(127, math.floor(tonumber(vel) or 100)))
  local P = SEQ_PLAYER_PARAM
  seq_player_set_param(tr, fx, P.vel, vel)
  local cur = math.floor(tonumber((r.TrackFX_GetParam(tr, fx, P.trigger))) or 0)
  seq_player_set_param(tr, fx, P.trigger, (cur + 1) % 1000000)
  return true
end

function seq_midi_parent_is_armed()
  local tr = seq_midi_parent_track(false)
  if not tr then
    return false
  end
  return (r.GetMediaTrackInfo_Value(tr, "I_RECARM") or 0) > 0.5
end

function seq_midi_apply_parent_input(tr)
  if not tr then
    return
  end
  r.SetMediaTrackInfo_Value(tr, "I_RECINPUT", SEQ_MIDI_RECINPUT_ALL)
  r.SetMediaTrackInfo_Value(tr, "I_RECMODE", SEQ_MIDI_RECMODE_MONITOR)
  r.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
end

function seq_midi_set_parent_arm(on)
  local tr = seq_midi_parent_track(on and true or false)
  if not tr then
    return false
  end
  seq_midi_ensure_jsfx()
  if on then
    seq_midi_apply_parent_input(tr)
    r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  else
    r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  end
  return true
end

function seq_midi_toggle_parent_arm()
  return seq_midi_set_parent_arm(not seq_midi_parent_is_armed())
end

function seq_midi_arm_button_width(h)
  h = h or 18
  local tw = select(1, r.ImGui_CalcTextSize(ctx, "MIDI")) or 28
  return 6 + (h - 2) + 4 + tw + 7
end

function render_seq_midi_arm_icon_button(id, h)
  h = h or 18
  local label = "MIDI"
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local icon_sz = h - 2
  local w = seq_midi_arm_button_width(h)
  local armed = seq_midi_parent_is_armed()

  r.ImGui_InvisibleButton(ctx, "##ui_" .. tostring(id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local press = pressed and 1.0 or 0.0

  local bg, border, line
  if armed then
    bg = hovered and 0x4A1414FF or 0x2C1010FF
    border = hovered and 0xFF6A6AFF or 0xFF3A3AFF
    line = 0xFF4A4AFF
  else
    bg = hovered and UI_THEME.surface_hvr or UI_THEME.surface
    border = hovered and UI_THEME.border_hvr or UI_THEME.border
    line = hovered and UI_THEME.text or UI_THEME.text_dim
  end
  ui_draw_panel(dl, x0, y0, x1, y1, 5.0, bg, border, hovered, pressed)

  local icon_cx = x0 + 6 + icon_sz * 0.5
  local icon_cy = (y0 + y1) * 0.5 + press
  ui_button_draw_icon(dl, "midi", icon_cx, icon_cy, icon_sz, line)
  r.ImGui_DrawList_AddText(dl, x0 + 6 + icon_sz + 4, y0 + (h - th) * 0.5 + press, line, label)

  if clicked then
    seq_midi_toggle_parent_arm()
  end
  if hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, armed
      and "MIDI arm on — Sample Map folder is receiving MIDI"
      or "MIDI arm — record-arm the Sample Map folder for live MIDI")
  end
end

function seq_midi_poll_gmem()
  if not r.gmem_attach or not r.gmem_read then
    return
  end
  r.gmem_attach(SEQ_MIDI_GMEM_NAME)
  local serial = tonumber(r.gmem_read(0)) or 0
  if serial <= 0 then
    return
  end
  local last = state.seq_midi_gmem_serial
  if last == nil or serial < last then
    state.seq_midi_gmem_serial = serial
    return
  end
  if serial == last then
    return
  end
  local pending = {}
  for i = 0, 63 do
    local base = 16 + i * 4
    local evt_serial = tonumber(r.gmem_read(base + 3)) or 0
    if evt_serial > last and evt_serial <= serial then
      local on = (tonumber(r.gmem_read(base + 2)) or 0) > 0.5
      if on then
        pending[#pending + 1] = {
          serial = evt_serial,
          note = tonumber(r.gmem_read(base)) or 0,
          vel = tonumber(r.gmem_read(base + 1)) or 0,
        }
      end
    end
  end
  table.sort(pending, function(a, b) return a.serial < b.serial end)
  for _, evt in ipairs(pending) do
    seq_midi_handle_note_on(evt.note, evt.vel)
  end
  state.seq_midi_gmem_serial = serial
end

function seq_midi_poll()
  if not state.seq_midi_jsfx_ready and seq_midi_parent_track(false) then
    seq_midi_ensure_jsfx()
  end
  seq_player_sync_all()
  seq_midi_poll_gmem()
end

function seq_mix_controls_inner_w()
  local btn = SEQ_MIX_BTN or 14.0
  local gap = SEQ_MIX_GAP or 3.0
  local ms_w = btn * 3 + 6
  return btn + gap
      + (SEQ_MIX_VOL_W or 52.0) + gap
      + (SEQ_MIX_PAN_W or 40.0) + gap
      + (SEQ_MIX_MIDI_W or 30.0) + gap
      + ms_w
end


function seq_env_shape_active(env)
  return seq_env_shape_active_norm(seq_normalize_track_env(env))
end

-- Same as seq_env_shape_active for an env already passed through seq_normalize_track_env.
function seq_env_shape_active_norm(env)
  local pts = env and env.points
  if not pts or #pts == 0 then
    return false
  end
  if #pts > 2 then
    return true
  end
  for _, p in ipairs(pts) do
    if math.abs((p.amp or 1.0) - 1.0) > 0.001 then
      return true
    end
    if math.abs(p.curve or 0.0) > 0.001 then
      return true
    end
  end
  return (pts[1].t or 0.0) > 0.0005
end

function seq_env_is_active(env)
  return seq_env_shape_active(env)
end

function seq_apply_slot_mix_to_reaper_track(slot)
  if not slot then return end
  seq_normalize_slot_mix(slot)
  if not slot.reaper_track_guid then return end
  local tr = get_track_by_guid(slot.reaper_track_guid)
  if not tr then return end
  -- Write only what differs: rewriting equal values still dirties the
  -- project, and forcing I_SOLO to 1 would turn solo-in-place into plain solo.
  local function differs(key, value)
    local cur = r.GetMediaTrackInfo_Value(tr, key)
    return type(cur) ~= "number" or math.abs(cur - value) > 0.0000001
  end
  if differs("D_VOL", slot.volume or 1.0) then
    r.SetMediaTrackInfo_Value(tr, "D_VOL", slot.volume or 1.0)
  end
  if differs("D_PAN", slot.pan or 0.0) then
    r.SetMediaTrackInfo_Value(tr, "D_PAN", slot.pan or 0.0)
  end
  if ((tonumber(r.GetMediaTrackInfo_Value(tr, "B_MUTE")) or 0) ~= 0) ~= (slot.mute == true) then
    r.SetMediaTrackInfo_Value(tr, "B_MUTE", slot.mute and 1 or 0)
  end
  if ((tonumber(r.GetMediaTrackInfo_Value(tr, "I_SOLO")) or 0) ~= 0) ~= (slot.solo == true) then
    r.SetMediaTrackInfo_Value(tr, "I_SOLO", slot.solo and 1 or 0)
  end
end

function seq_apply_all_slot_mix_to_reaper()
  for _, slot in ipairs(state.seq_tracks) do
    seq_apply_slot_mix_to_reaper_track(slot)
  end
end

function seq_ensure_take_volume_envelope(take)
  if not take then return nil end
  local env = r.GetTakeEnvelopeByName(take, "Volume")
  if env then return env end

  local item = r.GetMediaItemTake_Item(take)
  if not item then return nil end

  -- 1) Chunk inject after the SOURCE block (Lua '.' does not match newlines, so
  --    find the first "\n>" that closes <SOURCE ...>).
  local retval, chunk = r.GetItemStateChunk(item, "", false)
  if type(retval) == "string" then
    chunk = retval
    retval = chunk ~= ""
  end
  if type(chunk) == "string" and chunk ~= "" and not chunk:find("<VOLENV[%s\r\n]") then
    local src_at = chunk:find("<SOURCE", 1, true)
    local insert_at = nil
    if src_at then
      -- Walk lines counting nested "<..." / ">" so a <SOURCE SECTION> that
      -- wraps an inner <SOURCE WAVE> closes at its own matching ">".
      local depth = 0
      local pos = src_at
      local len = #chunk
      while pos <= len do
        local nl = chunk:find("\n", pos, true)
        local line_end = nl and (nl - 1) or len
        local trimmed = chunk:sub(pos, line_end):match("^%s*(.-)%s*$") or ""
        if trimmed:sub(1, 1) == "<" then
          depth = depth + 1
        elseif trimmed == ">" then
          depth = depth - 1
          if depth <= 0 then
            if nl then insert_at = nl end
            break
          end
        end
        if not nl then break end
        pos = nl + 1
      end
    end
    if not insert_at then
      local last = nil
      local search_from = 1
      while true do
        local a, b = chunk:find("\n>", search_from, true)
        if not a then break end
        last = b
        search_from = b + 1
      end
      if last then insert_at = last + 1 end
    end
    if insert_at then
      local block = "<VOLENV\nACT 1\nVIS 0 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE 0\nVOLTYPE 1\n>\n"
      local patched = chunk:sub(1, insert_at) .. block .. chunk:sub(insert_at + 1)
      if r.SetItemStateChunk(item, patched, false) then
        env = r.GetTakeEnvelopeByName(take, "Volume")
        if env then return env end
      end
    end
  end

  -- 2) Action-based create (SWS preferred; else native toggle).
  local selected = {}
  local sel_count = r.CountSelectedMediaItems(0)
  for i = 0, sel_count - 1 do
    selected[#selected + 1] = r.GetSelectedMediaItem(0, i)
  end
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)

  local sws = 0
  if r.NamedCommandLookup then
    sws = r.NamedCommandLookup("_S&M_TAKEENV1") or 0
  end
  if sws ~= 0 then
    r.Main_OnCommand(sws, 0)
  else
    r.Main_OnCommand(40693, 0) -- Take: Toggle take volume envelope
  end

  env = r.GetTakeEnvelopeByName(take, "Volume")

  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(selected) do
    if r.ValidatePtr2 and not r.ValidatePtr2(0, it, "MediaItem*") then
      -- skip invalidated
    else
      r.SetMediaItemSelected(it, true)
    end
  end

  return env
end

-- Sample Map Browser module: seq_fill_designer
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Fill designer ---------------------------------------------------------------
-- Drops drum fills into a region at phrase ends and before the region ends, or
-- into razor areas. A fill comes from the fill library below, from any pattern
-- preset (the span switches to that groove), or from the random generator.
-- Several fills can be mixed; spots then take them in turn or shuffled.
--
-- Library lanes are one character per 16th: "." rest, "x" hit, "X" accent,
-- "g" ghost, "r" two-stroke (32nds), "t" three-stroke, "R" four-stroke.
-- tom_hi / tom_mid / tom_lo / tom_floor all play the tom track, pitched apart,
-- so a single tom sample still runs down the kit. ohat is a louder hat hit.
-- clear_all: every drum track drops out under the fill (stops, unison hits).
-- ramp: hits swell from soft to full over the fill.

SEQ_FILL_CATEGORIES = {
  { key = "snare",  label = "Snare Runs" },
  { key = "toms",   label = "Tom Runs" },
  { key = "kick",   label = "Kicks, Hits & Stops" },
  { key = "cymbal", label = "Hats & Cymbals" },
  { key = "build",  label = "Builds" },
  { key = "glitch", label = "Breaks & Glitch" },
}

SEQ_FILL_LIBRARY = {
  -- Snare runs
  { key = "snare_beat", label = "Snare Sixteenths", cat = "snare", len = 4,
    lanes = { snare = "xxxX" } },
  { key = "snare_two", label = "Two-Beat Snare Run", cat = "snare", len = 8, ramp = true,
    lanes = { snare = "x.xxxxxX", kick = "x...x..." } },
  { key = "snare_drag", label = "Ghost Drag", cat = "snare", len = 8,
    lanes = { snare = "g.gx.ggX", kick = "x.....x." } },
  { key = "snare_roll_end", label = "Roll Into One", cat = "snare", len = 8, ramp = true,
    lanes = { snare = "x.x.rrRR" } },
  { key = "snare_flams", label = "Flam Pickups", cat = "snare", len = 8,
    lanes = { snare = "..r..r.X", kick = "x..x..x." } },
  { key = "snare_bar", label = "Bar of Sixteenths", cat = "snare", len = 16, ramp = true,
    lanes = { snare = "xxxxxxxxxxxxXXXX", kick = "x...x...x...x..." } },
  -- Tom runs
  { key = "tom_beat", label = "Quick Tom Drop", cat = "toms", len = 4,
    lanes = { tom_hi = "x...", tom_mid = ".x..", tom_lo = "..x.", tom_floor = "...X" } },
  { key = "tom_two", label = "Around the Kit", cat = "toms", len = 8,
    lanes = { snare = "xx......", tom_hi = "..xx....", tom_mid = "....xx..", tom_floor = "......xX" } },
  { key = "tom_bar", label = "Classic Rock Fill", cat = "toms", len = 16,
    lanes = { snare = "xxxx............", tom_hi = "....xxxx........", tom_mid = "........xxxx....", tom_floor = "............xxxX" } },
  { key = "tom_bounce", label = "Tom Bounce", cat = "toms", len = 8,
    lanes = { tom_hi = "x..x....", tom_lo = ".x..x.x.", tom_floor = "..x....X", kick = "x...x..." } },
  { key = "tom_call", label = "Snare & Tom Call", cat = "toms", len = 8,
    lanes = { snare = "x.x.....", tom_mid = "...x.x..", tom_floor = "......xX", kick = "x...x..." } },
  { key = "tom_triplets", label = "Rolling Toms", cat = "toms", len = 8, ramp = true,
    lanes = { tom_hi = "t..t....", tom_mid = "..t..t..", tom_floor = "......tX" } },
  -- Kicks, hits and stops
  { key = "kick_run", label = "Kick Run", cat = "kick", len = 4,
    lanes = { kick = "xxxX" } },
  { key = "unison_hits", label = "Unison Hits", cat = "kick", len = 8, clear_all = true,
    lanes = { kick = "X..X..X.", snare = "X..X..X.", crash = "X......." } },
  { key = "push_hits", label = "Push Into One", cat = "kick", len = 8, clear_all = true,
    lanes = { kick = "x.....xX", snare = "..x.x..X" } },
  { key = "stop_beat", label = "One-Beat Stop", cat = "kick", len = 4, clear_all = true,
    lanes = {} },
  { key = "stop_hit", label = "Hit and Stop", cat = "kick", len = 8, clear_all = true,
    lanes = { kick = "X.......", crash = "X......." } },
  { key = "half_drop", label = "Half-Time Drop", cat = "kick", len = 8, clear_all = true,
    lanes = { kick = "x.......", snare = "....X..." } },
  -- Hats and cymbals
  { key = "hat_roll", label = "Hat Roll", cat = "cymbal", len = 4,
    lanes = { hat = "rrRR" } },
  { key = "open_hat_lift", label = "Open Hat Lift", cat = "cymbal", len = 8,
    lanes = { hat = "xx.xx...", ohat = "..x...X.", snare = ".......X" } },
  { key = "ride_bell", label = "Ride Bell Pickup", cat = "cymbal", len = 8,
    lanes = { ride = "x.x.xxxX", kick = "x...x..." } },
  { key = "crash_swell", label = "Crash Swell", cat = "cymbal", len = 8, ramp = true,
    lanes = { crash = "x.x.x.xX", kick = "x.......", snare = "....x.xX" } },
  -- Builds
  { key = "snare_build", label = "Snare Build", cat = "build", len = 16, ramp = true,
    lanes = { snare = "x...x...x.x.xxrr", kick = "x...x...x...x..." } },
  { key = "clap_build", label = "Clap Build", cat = "build", len = 16, ramp = true,
    lanes = { clap = "x.x.x.x.xxxxrrRR" } },
  { key = "riser_two_bars", label = "Two-Bar Riser", cat = "build", len = 32, ramp = true,
    lanes = {
      snare = "x...x...x...x...x.x.x.x.xxxxrrRR",
      kick = "x...x...x...x...x...x...x...x...",
    } },
  { key = "tom_build", label = "Tom Build", cat = "build", len = 16, ramp = true,
    lanes = { tom_floor = "x...x...x...x...", tom_lo = "..x...x...x.x...", tom_mid = "............x.x.", snare = "............xxrR" } },
  -- Breaks and glitch
  { key = "stutter_glitch", label = "Stutter Glitch", cat = "glitch", len = 4,
    lanes = { snare = "R.r.", kick = ".x.x" } },
  { key = "break_chop", label = "Break Chop", cat = "glitch", len = 8, clear_all = true,
    lanes = { kick = "x..x..x.", snare = "..x..x.X", hat = "x.x.x.x." } },
  { key = "perc_scatter", label = "Perc Scatter", cat = "glitch", len = 8,
    lanes = { perc = "x..x.x..", rim = ".x....x.", snare = ".......X" } },
  { key = "reverse_pull", label = "Reverse Pull", cat = "glitch", len = 8, ramp = true, clear_all = true,
    lanes = { snare = "....rrRR", crash = "......xX" } },
}

-- Library lane -> track role, pitch (semitones) and volume scale.
SEQ_FILL_LANE_DEFS = {
  kick = { role = "kick" }, snare = { role = "snare" }, clap = { role = "clap" },
  rim = { role = "rim" }, hat = { role = "hat" }, ohat = { role = "hat", vol = 1.15 },
  ride = { role = "ride" }, crash = { role = "crash" }, perc = { role = "perc" },
  tom_hi = { role = "tom", pitch = 7 }, tom_mid = { role = "tom", pitch = 2 },
  tom_lo = { role = "tom", pitch = -3 }, tom_floor = { role = "tom", pitch = -8 },
}
SEQ_FILL_LANE_ORDER = { "crash", "ride", "ohat", "hat", "tom_hi", "tom_mid", "tom_lo", "tom_floor", "perc", "rim", "clap", "snare", "kick" }

-- When a fill needs a drum the kit doesn't have, the hit moves to the next one.
SEQ_FILL_ROLE_FALLBACK = {
  tom = { "perc", "snare" },
  perc = { "rim", "tom", "snare" },
  rim = { "snare", "clap" },
  clap = { "snare", "rim" },
  snare = { "clap", "rim" },
  crash = { "ride", "hat" },
  ride = { "hat", "crash" },
  hat = { "ride", "perc" },
  kick = { "808" },
}

-- Drum roles a fill may clear; bass, 808, FX and vocals keep playing.
SEQ_FILL_DRUM_ROLES = {
  kick = true, snare = true, clap = true, rim = true, tom = true,
  hat = true, ride = true, crash = true, perc = true,
}

SEQ_FILL_LENGTHS = {
  { key = "auto", label = "Auto", sixteenths = nil },
  { key = "beat", label = "1 beat", sixteenths = 4 },
  { key = "half", label = "2 beats", sixteenths = 8 },
  { key = "bar", label = "1 bar", sixteenths = 16 },
  { key = "two_bars", label = "2 bars", sixteenths = 32 },
}
SEQ_FILL_PHRASE_CHOICES = { 2, 4, 8, 16 }
SEQ_FILL_COLOR = 0xFFC857FF
SEQ_FILL_ICON_SIZE = 12
SEQ_FILL_RANDOM_LEN = 8
SEQ_FILL_VOL = { x = 0.85, X = 1.0, g = 0.45, r = 0.85, t = 0.85, R = 0.9 }
SEQ_FILL_STUTTER = { r = 2, t = 3, R = 4 }

-- --- Settings --------------------------------------------------------------------

local SEQ_FILL_OPT_KEYS = { "phrase_bars", "phrase_on", "end_on", "len", "crash", "clear_others", "unlink", "pick", "source" }

function seq_fill_state()
  local f = state.seq_fill
  if f then
    return f
  end
  f = {
    open = false,
    mode = "region",       -- "region" or "razor"
    scope = "region",      -- "region" (the target region) or "all"
    region_id = nil,
    phrase_bars = 4,
    phrase_on = true,
    end_on = true,
    len = "auto",
    crash = true,
    clear_others = false,
    unlink = true,
    pick = "cycle",        -- how a mix of several fills is spread: "cycle" / "shuffle"
    source = "fills",      -- list shown: "fills" / "patterns"
    mix = {},              -- chosen picks, in order: { kind = "fill"|"pattern", key = ... }
    energy = 3,
    seed = 1,
  }
  local raw = r.GetExtState and r.GetExtState(SEQ_PATTERN_EXT_SECTION, "fill_options") or ""
  for k, v in tostring(raw or ""):gmatch("([%w_]+)=([%w_]+)") do
    if v == "true" then
      f[k] = true
    elseif v == "false" then
      f[k] = false
    elseif tonumber(v) then
      f[k] = tonumber(v)
    else
      f[k] = v
    end
  end
  state.seq_fill = f
  return f
end

function seq_fill_save_options()
  local f = seq_fill_state()
  local parts = {}
  for _, k in ipairs(SEQ_FILL_OPT_KEYS) do
    parts[#parts + 1] = k .. "=" .. tostring(f[k])
  end
  if r.SetExtState then
    r.SetExtState(SEQ_PATTERN_EXT_SECTION, "fill_options", table.concat(parts, ";"), true)
  end
end

function seq_fill_set(key, value)
  local f = seq_fill_state()
  if f[key] ~= value then
    f[key] = value
    seq_fill_save_options()
  end
end

function seq_fill_len_def(key)
  for _, d in ipairs(SEQ_FILL_LENGTHS) do
    if d.key == key then
      return d
    end
  end
  return SEQ_FILL_LENGTHS[1]
end

function seq_fill_def(key)
  if not SEQ_FILL_DEFS then
    SEQ_FILL_DEFS = {}
    for _, def in ipairs(SEQ_FILL_LIBRARY) do
      SEQ_FILL_DEFS[def.key] = def
    end
  end
  return SEQ_FILL_DEFS[key]
end

function seq_fill_category_label(key)
  for _, c in ipairs(SEQ_FILL_CATEGORIES) do
    if c.key == key then
      return c.label
    end
  end
  return "Other"
end

function seq_fill_len_label(sixteenths)
  if sixteenths == 4 then return "1 beat" end
  if sixteenths % 16 == 0 then
    local bars = sixteenths // 16
    return bars == 1 and "1 bar" or (tostring(bars) .. " bars")
  end
  if sixteenths % 4 == 0 then return tostring(sixteenths // 4) .. " beats" end
  return tostring(sixteenths) .. " sixteenths"
end

-- --- Hits ------------------------------------------------------------------------
-- A fill resolves to hits: { role, pos (16ths from the fill start), vol, pitch, stutter }.

local function seq_fill_rng(seed)
  local s = math.floor(math.abs(tonumber(seed) or 1) * 9973) % 2147483646 + 1
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end

function seq_fill_library_hits(def)
  local hits = {}
  if not def then
    return hits
  end
  for lane, pattern in pairs(def.lanes or {}) do
    local ld = SEQ_FILL_LANE_DEFS[lane]
    if ld then
      for i = 1, #pattern do
        local ch = pattern:sub(i, i)
        if ch ~= "." then
          local pos = i - 1
          local vol = (SEQ_FILL_VOL[ch] or 0.85) * (ld.vol or 1.0)
          if def.ramp and ch ~= "X" then
            vol = vol * (0.6 + 0.4 * (pos / math.max(1, def.len - 1)))
          end
          hits[#hits + 1] = {
            role = ld.role, lane = lane, pos = pos, vol = math.min(1.0, vol),
            pitch = ld.pitch or 0, stutter = SEQ_FILL_STUTTER[ch] or 1,
          }
        end
      end
    end
  end
  table.sort(hits, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    return a.lane < b.lane
  end)
  return hits
end

-- Fit hits written for `native` 16ths into a span of `len` 16ths: a longer
-- fill keeps its ending, a shorter one sits at the end of the span.
function seq_fill_fit_hits(hits, native, len)
  local out = {}
  local shift = len - native
  for _, h in ipairs(hits) do
    local pos = h.pos + shift
    if pos >= 0 and pos < len then
      local copy = {}
      for k, v in pairs(h) do copy[k] = v end
      copy.pos = pos
      out[#out + 1] = copy
    end
  end
  return out
end

-- Random fill of exactly `len` 16ths. energy 1..6: 1 sparse and plain, 6 dense
-- with rolls. Same seed, same fill.
SEQ_FILL_RANDOM_SHAPES = { "snare_run", "tom_run", "mixed", "unison", "hat_build", "glitch" }

function seq_fill_random_hits(len, seed, energy)
  len = math.max(1, math.floor(len or SEQ_FILL_RANDOM_LEN))
  energy = math.max(1, math.min(6, math.floor(energy or 3)))
  local rnd = seq_fill_rng(seed)
  local hits = {}
  local clear_all = false
  local weights = { 3, 3, 3, 1 + energy * 0.3, 1.5, 0.5 + energy * 0.35 }
  local total = 0
  for _, w in ipairs(weights) do total = total + w end
  local pick, shape = rnd() * total, SEQ_FILL_RANDOM_SHAPES[1]
  for i, w in ipairs(weights) do
    pick = pick - w
    if pick <= 0 then
      shape = SEQ_FILL_RANDOM_SHAPES[i]
      break
    end
  end

  local function t(i) return len > 1 and (i / (len - 1)) or 1.0 end
  local function density(i) return math.min(0.97, 0.18 + energy * 0.09 + 0.35 * t(i)) end
  local function roll(i)
    if rnd() < (energy - 1) * 0.05 * (0.3 + t(i)) then
      return energy >= 5 and (rnd() < 0.5 and 4 or 3) or 2
    end
    return 1
  end
  local function vol(i, accent)
    if accent then return 1.0 end
    return math.min(1.0, 0.55 + 0.4 * t(i))
  end
  local function add(role, pos, v, pitch, stutter)
    hits[#hits + 1] = { role = role, pos = pos, vol = v, pitch = pitch or 0, stutter = stutter or 1 }
  end
  local tom_pitches = { 7, 3, -1, -5, -9 }
  local function tom_pitch(i)
    local idx = math.min(#tom_pitches, math.floor(t(i) * #tom_pitches) + 1)
    return tom_pitches[idx]
  end

  if shape == "snare_run" then
    for i = 0, len - 1 do
      if i == 0 or i == len - 1 or rnd() < density(i) then
        local ghost = i < len - 4 and rnd() < 0.15
        add("snare", i, ghost and 0.45 or vol(i, i % 4 == 0 and energy >= 4), 0, roll(i))
      end
      if i % 4 == 0 and rnd() < 0.5 then add("kick", i, 0.9) end
    end
  elseif shape == "tom_run" then
    add("snare", 0, vol(0, true))
    for i = 1, len - 1 do
      if i == len - 1 or rnd() < density(i) then
        add("tom", i, vol(i, i == len - 1), tom_pitch(i), roll(i))
      end
      if energy >= 3 and i % 4 == 0 and rnd() < 0.5 then add("kick", i, 0.9) end
    end
  elseif shape == "mixed" then
    for i = 0, len - 1 do
      if i == 0 or i == len - 1 or rnd() < density(i) then
        if rnd() < t(i) * 0.9 then
          add("tom", i, vol(i, i == len - 1), tom_pitch(i), roll(i))
        else
          add("snare", i, vol(i, false), 0, roll(i))
        end
      end
      if i % 4 == 0 and rnd() < 0.4 then add("kick", i, 0.9) end
    end
  elseif shape == "unison" then
    clear_all = true
    local placed = false
    for i = 0, len - 1 do
      local synco = (i % 3 == 0) or (i % 4 == 3)
      local p = (synco and 0.45 or 0.12) + energy * 0.05
      if i == len - 1 or (i < len - 1 and rnd() < p) then
        add("kick", i, 1.0)
        add("snare", i, 1.0)
        if not placed and energy >= 4 then add("crash", i, 0.9) end
        placed = true
      end
    end
  elseif shape == "hat_build" then
    add("kick", 0, 0.9)
    for i = 0, len - 1 do
      local stut = 1
      if t(i) > 0.66 then
        stut = energy >= 4 and 4 or 2
      elseif t(i) > 0.33 and energy >= 3 then
        stut = 2
      end
      add("hat", i, vol(i, false), 0, stut)
      if len >= 8 and i >= len - 4 then add("snare", i, vol(i, i == len - 1)) end
    end
  else -- glitch
    local cell = ({ 1, 2, 2, 4 })[math.floor(rnd() * 4) + 1]
    local roles = { "snare", "kick", "hat", "perc" }
    local motif = {}
    for c = 0, cell - 1 do
      motif[c] = { role = roles[math.floor(rnd() * #roles) + 1], stut = (rnd() < 0.5 + energy * 0.06) and 4 or 1 }
    end
    for i = 0, len - 1 do
      local m = motif[i % cell]
      if rnd() < 0.85 then
        add(m.role, i, vol(i, i == len - 1), 0, i == len - 1 and 1 or m.stut)
      end
    end
    add("snare", len - 1, 1.0)
  end

  -- One hit per role and position; the later one wins.
  local seen, out = {}, {}
  for idx = #hits, 1, -1 do
    local h = hits[idx]
    local k = h.role .. ":" .. h.pos
    if not seen[k] then
      seen[k] = true
      table.insert(out, 1, h)
    end
  end
  table.sort(out, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    return a.role < b.role
  end)
  return out, clear_all, shape
end

-- A pattern preset over the span: the preset's own steps at their bar
-- positions, so the span switches groove in time with the rest of the bar.
function seq_fill_pattern_hits(style_key, span_start_qn, len)
  local hits = {}
  local template = SEQ_GEN_TEMPLATES[style_key]
  if not template then
    return hits
  end
  local cycle = seq_template_cycle_bars(template)
  local lookup = {}
  for role, steps in pairs(template) do
    for _, s in ipairs(steps) do
      lookup[role .. ":" .. tostring(math.floor(s))] = true
    end
  end
  for i = 0, len - 1 do
    local rel = (span_start_qn or 0.0) + i * 0.25
    local bar = math.floor(rel / 4.0 + 1e-6)
    local pos16 = math.floor((rel - bar * 4.0) * 4.0 + 0.5) % 16
    local key16 = (bar % cycle) * 16 + pos16
    for role in pairs(template) do
      if lookup[role .. ":" .. tostring(key16)] then
        hits[#hits + 1] = { role = role, pos = i, vol = (pos16 % 4 == 0) and 1.0 or 0.85, pitch = 0, stutter = 1, pos16 = pos16 }
      end
    end
  end
  return hits
end

-- Native length of a pick in 16ths (nil = takes the span as given).
function seq_fill_pick_native_len(pick)
  if pick and pick.kind == "fill" then
    local def = seq_fill_def(pick.key)
    return def and def.len or nil
  elseif pick and pick.kind == "pattern" then
    return 16
  end
  return SEQ_FILL_RANDOM_LEN
end

-- Hits for one pick across `len` 16ths starting at span_start_qn (region-relative).
function seq_fill_resolve_pick(pick, span_start_qn, len, seed, energy)
  if pick.kind == "fill" then
    local def = seq_fill_def(pick.key)
    if not def then
      return {}, false, "rock"
    end
    return seq_fill_fit_hits(seq_fill_library_hits(def), def.len, len), def.clear_all == true, "rock"
  elseif pick.kind == "pattern" then
    return seq_fill_pattern_hits(pick.key, span_start_qn, len), true, pick.key
  end
  local hits, clear_all = seq_fill_random_hits(len, seed, energy)
  return hits, clear_all, "rock"
end

-- --- Where fills go ----------------------------------------------------------------

function seq_fill_pick_label(pick)
  if not pick then return "Random" end
  if pick.kind == "fill" then
    local def = seq_fill_def(pick.key)
    return def and def.label or pick.key
  elseif pick.kind == "pattern" then
    return get_seq_gen_style_label(pick.key)
  end
  return "Random"
end

-- Spot ends (region-relative QN) for a region: each phrase end and the region end.
function seq_fill_region_spot_ends(region, opts)
  local ends = {}
  if not region then
    return ends
  end
  local len_qn = get_seq_region_length_qn(region)
  local phrase_qn = math.max(1, math.floor(opts.phrase_bars or 4)) * 4.0
  if opts.phrase_on then
    local e = phrase_qn
    while e < len_qn - 1e-6 do
      ends[#ends + 1] = e
      e = e + phrase_qn
    end
  end
  if opts.end_on or opts.phrase_on and math.abs((len_qn / phrase_qn) - math.floor(len_qn / phrase_qn + 0.5)) < 1e-6 then
    ends[#ends + 1] = len_qn
  end
  return ends
end

local function seq_fill_slot_set(track_ids)
  if not track_ids then return nil end
  local set = {}
  for _, id in ipairs(track_ids) do set[tostring(id)] = true end
  return set
end

-- Razor areas from the sequencer, or REAPER's own razor edits when there are none.
function seq_fill_native_razor_areas()
  local now = r.time_precise and r.time_precise() or 0
  local cache = state.seq_fill_native_razor_cache
  if cache and now - cache.t < 0.3 then
    return cache.areas
  end
  local areas = {}
  local slot_by_guid = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.reaper_track_guid then
      slot_by_guid[tostring(slot.reaper_track_guid)] = slot.id
    end
  end
  local by_range = {}
  local count = (r.CountTracks and r.CountTracks(0)) or 0
  for i = 0, count - 1 do
    local tr = r.GetTrack(0, i)
    local ok, s = false, ""
    if tr and r.GetSetMediaTrackInfo_String then
      ok, s = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    end
    if ok and type(s) == "string" and s ~= "" then
      local guid = r.GetTrackGUID and r.GetTrackGUID(tr) or nil
      local slot_id = guid and slot_by_guid[tostring(guid)] or nil
      for t0, t1, env in s:gmatch("([%d%.%-]+)%s+([%d%.%-]+)%s+(%S+)") do
        if env == '""' then
          local q0, q1 = time_to_qn(tonumber(t0)), time_to_qn(tonumber(t1))
          if q0 and q1 and q1 > q0 then
            local key = string.format("%.4f:%.4f", q0, q1)
            local area = by_range[key]
            if not area then
              area = { start_qn = q0, end_qn = q1, track_ids = {}, native = true }
              by_range[key] = area
              areas[#areas + 1] = area
            end
            if slot_id then
              area.track_ids[#area.track_ids + 1] = slot_id
            else
              area.all_tracks = true -- razor on a track the sequencer doesn't own
            end
          end
        end
      end
    end
  end
  for _, area in ipairs(areas) do
    if area.all_tracks or #area.track_ids == 0 then
      area.track_ids = nil
    end
  end
  state.seq_fill_native_razor_cache = { t = now, areas = areas }
  return areas
end

function seq_fill_razor_areas()
  if seq_has_razors() then
    return state.seq_razors, false
  end
  return seq_fill_native_razor_areas(), true
end

function seq_fill_any_razor()
  if seq_has_razors() then
    return true
  end
  return #seq_fill_native_razor_areas() > 0
end

-- Spots: { region, end_qn (region-relative), span_qn (nil = from the pick),
-- track_set (nil = every track), razor }. In region mode each pattern is filled
-- once, since linked copies share notes.
function seq_fill_compute_spots()
  local f = seq_fill_state()
  local spots = {}
  if f.mode == "razor" then
    local areas = seq_fill_razor_areas()
    for _, area in ipairs(areas or {}) do
      for _, region in ipairs(state.seq_regions or {}) do
        local rs = region.start_qn or 0.0
        local re = rs + get_seq_region_length_qn(region)
        local a0 = math.max(rs, area.start_qn or 0)
        local a1 = math.min(re, area.end_qn or 0)
        if a1 - a0 >= 0.25 - 1e-6 then
          spots[#spots + 1] = {
            region = region,
            end_qn = a1 - rs,
            span_qn = math.floor((a1 - a0) * 4.0 + 0.5) / 4.0,
            track_set = seq_fill_slot_set(area.track_ids),
            razor = true,
          }
        end
      end
    end
    return spots
  end
  local regions = {}
  if f.scope == "all" then
    local seen = {}
    for _, region in ipairs(state.seq_regions or {}) do
      local key = tostring(region.pattern_id)
      if not seen[key] then
        seen[key] = true
        regions[#regions + 1] = region
      end
    end
  else
    local region = get_seq_region_by_id(f.region_id) or get_selected_seq_region()
    if region then
      regions[1] = region
    end
  end
  for _, region in ipairs(regions) do
    for _, e in ipairs(seq_fill_region_spot_ends(region, f)) do
      spots[#spots + 1] = { region = region, end_qn = e }
    end
  end
  return spots
end

-- Span length in 16ths for a pick at a spot.
function seq_fill_spot_len(spot, pick)
  if spot.span_qn then
    local span = math.max(1, math.floor(spot.span_qn * 4.0 + 0.5))
    local forced = seq_fill_len_def(seq_fill_state().len).sixteenths
    return forced and math.min(forced, span) or span
  end
  local forced = seq_fill_len_def(seq_fill_state().len).sixteenths
  return forced or seq_fill_pick_native_len(pick) or SEQ_FILL_RANDOM_LEN
end

-- --- Writing ---------------------------------------------------------------------

-- role -> slots that play it, limited to track_set when given.
function seq_fill_role_slots(track_set)
  local map = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.sample_path and slot.id ~= nil and (not track_set or track_set[tostring(slot.id)]) then
      local role = infer_seq_track_role(slot)
      map[role] = map[role] or {}
      map[role][#map[role] + 1] = slot
    end
  end
  return map
end

function seq_fill_slots_for_role(role_slots, role)
  if role_slots[role] then
    return role_slots[role], role
  end
  for _, alt in ipairs(SEQ_FILL_ROLE_FALLBACK[role] or {}) do
    if role_slots[alt] then
      return role_slots[alt], alt
    end
  end
  return nil, nil
end

-- Remove unlocked notes on the slot starting in [q0, q1) (region-relative).
function seq_fill_clear_span(region, slot, q0, q1)
  local pattern = get_seq_pattern(region.pattern_id, false)
  local notes = get_track_note_table(pattern, slot.id, false)
  if not notes then return 0 end
  local grid_qn = state.seq_grid_qn or 0.25
  local doomed = {}
  for key, note in pairs(notes) do
    if type(note) == "table" and not seq_note_is_locked(note) then
      local q = seq_note_qn_offset(note, key, grid_qn)
      if q >= q0 - 1e-6 and q < q1 - 1e-6 then
        doomed[#doomed + 1] = key
      end
    end
  end
  for _, key in ipairs(doomed) do
    notes[key] = nil
  end
  return #doomed
end

function seq_fill_write_hit(region, slot, qn, hit, style_key)
  local pattern = get_seq_pattern(region.pattern_id, true)
  local grid_qn = state.seq_grid_qn or 0.25
  if qn < -1e-9 or qn >= get_seq_region_length_qn(region) - 1e-9 then
    return false
  end
  if seq_cell_is_locked(pattern, slot.id, seq_region_step_key(region, (region.start_qn or 0.0) + qn, grid_qn)) then
    return false
  end
  local existing_key, existing = seq_find_note_key_at_qn(region, slot.id, qn)
  if existing and seq_note_is_locked(existing) then
    return false
  end
  local key = existing_key or seq_alloc_note_key(region, slot.id, qn)
  local note = make_default_seq_note(slot, key, qn)
  if not note then
    return false
  end
  note.step = math.floor(qn / math.max(1e-9, grid_qn) + 1e-6)
  note.volume = hit.vol or 1.0
  note.pitch = hit.pitch or 0.0
  if (hit.stutter or 1) > 1 then
    note.stutter = hit.stutter
    note.length_qn = 0.25
  end
  local pos16 = hit.pos16 or (math.floor(qn * 4.0 + 0.5) % 16)
  note.offset_qn = seq_pattern_base_offset(infer_seq_track_role(slot), pos16, style_key or "rock", grid_qn)
  if pos16 == 0 and note.offset_qn < 0 then
    note.offset_qn = 0.0
  end
  note.fill = true
  set_seq_note(region, slot.id, key, note)
  return true
end

-- Crash on the downbeat right after a fill: inside the region, or at the start
-- of the region that begins where this one ends.
function seq_fill_crash_after(region, end_qn, role_slots, touched)
  local target, at = region, end_qn
  if end_qn >= get_seq_region_length_qn(region) - 1e-6 then
    local abs_end = (region.start_qn or 0.0) + get_seq_region_length_qn(region)
    target = nil
    for _, other in ipairs(state.seq_regions or {}) do
      if other.id ~= region.id and math.abs((other.start_qn or 0.0) - abs_end) < 1e-4 then
        target = other
        break
      end
    end
    at = 0.0
  end
  if not target then return false end
  local slots = seq_fill_slots_for_role(role_slots, "crash")
  if not slots then return false end
  local wrote = false
  for _, slot in ipairs(slots) do
    local _, existing = seq_find_note_key_at_qn(target, slot.id, at, 0.02)
    if not existing then
      seq_fill_capture_pattern(target.pattern_id)
      if seq_fill_write_hit(target, slot, at, { vol = 0.95, pitch = 0, stutter = 1, pos16 = 0 }, "rock") then
        wrote = true
        touched[tostring(target.pattern_id)] = target.pattern_id
      end
    end
  end
  return wrote
end

-- Write one fill. Returns the number of hits written.
function seq_fill_write_spot(spot, pick, opts)
  local region = spot.region
  local len = seq_fill_spot_len(spot, pick)
  local span_qn = len * 0.25
  local start_qn = math.max(0.0, spot.end_qn - span_qn)
  local hits, clear_all, style_key = seq_fill_resolve_pick(pick, start_qn, len, opts.seed, opts.energy)
  local role_slots = seq_fill_role_slots(spot.track_set)

  -- Which tracks lose their groove under the fill.
  local clear = {}
  local function mark(slot) clear[tostring(slot.id)] = slot end
  for _, h in ipairs(hits) do
    for _, slot in ipairs((seq_fill_slots_for_role(role_slots, h.role)) or {}) do
      mark(slot)
    end
  end
  if clear_all or spot.razor or opts.clear_others then
    for role, slots in pairs(role_slots) do
      if SEQ_FILL_DRUM_ROLES[role] then
        for _, slot in ipairs(slots) do mark(slot) end
      end
    end
  end
  for _, slot in pairs(clear) do
    seq_fill_clear_span(region, slot, start_qn, spot.end_qn)
  end

  local written = 0
  for _, h in ipairs(hits) do
    local slots = seq_fill_slots_for_role(role_slots, h.role)
    for _, slot in ipairs(slots or {}) do
      if seq_fill_write_hit(region, slot, start_qn + h.pos * 0.25, h, style_key) then
        written = written + 1
      end
    end
  end
  if opts.crash and (written > 0 or clear_all) then
    seq_fill_crash_after(region, spot.end_qn, role_slots, opts.touched)
  end
  return written
end

-- --- Audition session --------------------------------------------------------------
-- Inserting again with the same target first puts back what was there before
-- the first insert, so trying fills one after another never stacks them.
-- Any other edit in between (a new undo step) starts a fresh session.

function seq_fill_capture_pattern(pattern_id)
  local s = state.seq_fill_session
  if not s or pattern_id == nil then return end
  local key = tostring(pattern_id)
  if s.snapshots[key] == nil then
    local pat = state.seq_patterns[key]
    s.snapshots[key] = pat and clone_table_deep(pat) or false
  end
end

function seq_fill_target_sig(spots)
  local f = seq_fill_state()
  local parts = { f.mode }
  for _, spot in ipairs(spots) do
    parts[#parts + 1] = tostring(spot.region.id) .. "@" .. string.format("%.3f", spot.end_qn)
  end
  return table.concat(parts, "|")
end

function seq_fill_session_active()
  local s = state.seq_fill_session
  return s ~= nil and s.undo_top ~= nil and s.undo_top == seq_undo_stack[#seq_undo_stack]
end

function seq_fill_restore_session()
  local s = state.seq_fill_session
  if not s then return {} end
  local restored = {}
  for key, snap in pairs(s.snapshots) do
    if snap == false then
      state.seq_patterns[key] = nil
    else
      state.seq_patterns[key] = clone_table_deep(snap)
    end
    restored[key] = tonumber(key) or key
  end
  return restored
end

-- Undo the whole audition session (back to before the first insert).
function seq_fill_revert()
  if not seq_fill_session_active() then
    state.seq_fill_session = nil
    return false
  end
  local label = begin_seq_undo("Revert drum fills")
  local restored = seq_fill_restore_session()
  state.selected_seq_note = nil
  save_config()
  for _, pid in pairs(restored) do
    sync_seq_pattern_regions(pid)
  end
  end_seq_undo(label)
  state.seq_fill_session = nil
  return true
end

function seq_fill_keep()
  state.seq_fill_session = nil
end

-- --- Insert ------------------------------------------------------------------------

-- picks: list of picks (nil entries = random). Returns hits written, spots used.
function seq_fill_insert(picks, opts)
  opts = opts or {}
  local f = seq_fill_state()
  local spots = seq_fill_compute_spots()
  if #spots == 0 then
    log("Fill designer: no spots to fill")
    return 0, 0
  end
  local label = begin_seq_undo("Insert drum fills")
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end

  -- Linked copies share notes; unlink the target first when asked.
  if f.mode == "region" and f.scope ~= "all" and f.unlink then
    local region = spots[1].region
    if region and seq_region_is_linked(region) then
      if seq_fill_session_active() then
        seq_fill_restore_session()
      end
      state.seq_fill_session = nil
      seq_unpool_region(region, { skip_undo = true })
    end
  end

  local sig = seq_fill_target_sig(spots)
  local touched = {}
  if seq_fill_session_active() and state.seq_fill_session.sig == sig then
    touched = seq_fill_restore_session()
  else
    state.seq_fill_session = { sig = sig, snapshots = {} }
  end
  for _, spot in ipairs(spots) do
    seq_fill_capture_pattern(spot.region.pattern_id)
  end

  local base_seed = opts.seed or seq_new_seed()

  local written = 0
  local wopts = { energy = opts.energy or f.energy, crash = f.crash, clear_others = f.clear_others, touched = touched }
  for i, spot in ipairs(spots) do
    local pick = nil
    if #picks > 0 then
      if f.pick == "shuffle" then
        local rnd = seq_fill_rng(base_seed + i * 131)
        pick = picks[math.floor(rnd() * #picks) + 1]
      else
        pick = picks[((i - 1) % #picks) + 1]
      end
    end
    wopts.seed = base_seed + i * 7919
    written = written + seq_fill_write_spot(spot, pick or { kind = "random" }, wopts)
    touched[tostring(spot.region.pattern_id)] = spot.region.pattern_id
  end

  state.selected_seq_note = nil
  save_config()
  for _, pid in pairs(touched) do
    sync_seq_pattern_regions(pid)
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  r.UpdateArrange()
  end_seq_undo(label)
  state.seq_fill_session.undo_top = seq_undo_stack[#seq_undo_stack]
  local names = {}
  for _, p in ipairs(picks) do names[#names + 1] = seq_fill_pick_label(p) end
  log(string.format("Inserted %d fill(s) (%s, %d hits)", #spots,
    #names > 0 and table.concat(names, ", ") or "random", written))
  return written, #spots
end

-- --- Opening -----------------------------------------------------------------------

function seq_fill_open_for_region(region)
  local f = seq_fill_state()
  if region then
    seq_select_region(region)
    f.region_id = region.id
  end
  if f.mode ~= "region" then
    f.mode = "region"
  end
  if f.scope == "all" then
    f.scope = "region"
  end
  f.open = true
  state.seq_pattern_window_open = false
end

function seq_fill_open_for_razor()
  local f = seq_fill_state()
  state.seq_fill_native_razor_cache = nil
  f.mode = "razor"
  f.open = true
  state.seq_pattern_window_open = false
end

-- Toolbar button: razor areas win when there are any.
function seq_fill_toggle_window(region)
  local f = seq_fill_state()
  if f.open then
    f.open = false
    seq_fill_keep()
    return
  end
  state.seq_fill_native_razor_cache = nil
  if seq_fill_any_razor() then
    seq_fill_open_for_razor()
  else
    seq_fill_open_for_region(region or get_selected_seq_region())
  end
end

-- --- Region item and razor entry points --------------------------------------------

-- Fill button on the right end of a region block in the region lane.
function seq_fill_region_icon_fits(rx0, rx1)
  return (rx1 - rx0) >= 64
end

function seq_fill_region_icon_rect(rx1, y0, lane_h)
  local s = SEQ_FILL_ICON_SIZE
  local x0 = rx1 - 6 - s
  local iy = y0 + (lane_h - s) * 0.5
  return x0 - 3, iy - 3, x0 + s + 3, iy + s + 3
end

function seq_fill_draw_region_icon(dl, rx1, y0, lane_h, mx, my, region)
  local hx0, hy0, hx1, hy1 = seq_fill_region_icon_rect(rx1, y0, lane_h)
  local hovered = mx >= hx0 and mx <= hx1 and my >= hy0 and my <= hy1
  local f = seq_fill_state()
  local active = f.open and f.mode == "region" and (f.scope == "all" or f.region_id == (region and region.id))
  if hovered or active then
    r.ImGui_DrawList_AddRectFilled(dl, hx0, hy0, hx1, hy1, active and 0xFFC85740 or 0xFFFFFF22, 3.0)
  end
  local col = (hovered or active) and SEQ_FILL_COLOR or 0xFFFFFF80
  ui_button_draw_icon(dl, "fill", (hx0 + hx1) * 0.5, (hy0 + hy1) * 0.5, SEQ_FILL_ICON_SIZE + 4, col)
  return hovered
end

-- "Fill" chip on the top-right corner of the last razor area. The rect is kept
-- for the next frame's click test.
function seq_fill_draw_razor_chip(dl, row_positions, timeline_x0, timeline_x1, view_start_qn, qn_span, mx, my)
  state.seq_fill_razor_chip = nil
  local razors = state.seq_razors
  if not razors or #razors == 0 or (state.seq_razor_drag and state.seq_razor_drag.mode ~= "move") then
    return
  end
  local razor = razors[#razors]
  local y0 = seq_razor_y_bounds(razor, row_positions)
  if not y0 then return end
  local timeline_w = math.max(1.0, timeline_x1 - timeline_x0)
  local x1 = timeline_x0 + (((razor.end_qn or 0) - view_start_qn) / math.max(0.0001, qn_span)) * timeline_w
  if x1 < timeline_x0 + 40 or x1 > timeline_x1 + 1 then return end
  local label = "Fill"
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local w, h = tw + 26, th + 6
  local cx0, cy0 = x1 - w - 3, y0 + 3
  local hovered = mx >= cx0 and mx <= cx0 + w and my >= cy0 and my <= cy0 + h
  r.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx0 + w, cy0 + h, hovered and 0x3A2E12F2 or 0x241D0EE6, h * 0.5)
  r.ImGui_DrawList_AddRect(dl, cx0, cy0, cx0 + w, cy0 + h, hovered and SEQ_FILL_COLOR or 0xFFC857AA, h * 0.5, 0, 1.2)
  ui_button_draw_icon(dl, "fill", cx0 + 11, cy0 + h * 0.5, 14, SEQ_FILL_COLOR)
  r.ImGui_DrawList_AddText(dl, cx0 + 20, cy0 + 3, 0xFFF2D6FF, label)
  state.seq_fill_razor_chip = { x0 = cx0, y0 = cy0, x1 = cx0 + w, y1 = cy0 + h }
  if hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Click: design fills for the razor areas")
  end
end

function seq_fill_razor_chip_hit(mx, my)
  local c = state.seq_fill_razor_chip
  return c ~= nil and mx >= c.x0 and mx <= c.x1 and my >= c.y0 and my <= c.y1
end

-- Amber bands where fills will land, while the designer is open.
function seq_fill_draw_spot_markers(dl, qn_to_x, timeline_x0, timeline_x1, body_y0, body_y1)
  local f = seq_fill_state()
  if not f.open then return end
  local spots = seq_fill_compute_spots()
  local preview_pick = f.mix[1]
  -- Linked copies share notes, so they get the fill too (unless the target
  -- is unlinked first).
  local mirror = f.mode == "region"
  if mirror and f.scope ~= "all" and f.unlink and spots[1] and seq_region_is_linked(spots[1].region) then
    mirror = false
  end
  local function band(region, end_qn, len)
    local abs_end = (region.start_qn or 0.0) + end_qn
    local abs_start = math.max(region.start_qn or 0.0, abs_end - len * 0.25)
    local x0 = math.max(timeline_x0, qn_to_x(abs_start))
    local x1 = math.min(timeline_x1, qn_to_x(abs_end))
    if x1 > x0 then
      r.ImGui_DrawList_AddRectFilled(dl, x0, body_y0, x1, body_y1, 0xFFC8571A, 0)
      r.ImGui_DrawList_AddLine(dl, x1, body_y0, x1, body_y1, 0xFFC857AA, 1.5)
      r.ImGui_DrawList_AddRectFilled(dl, x0, body_y0, x1, body_y0 + 3, 0xFFC857CC, 0)
    end
  end
  for _, spot in ipairs(spots) do
    local len = seq_fill_spot_len(spot, preview_pick)
    if mirror then
      for _, region in ipairs(state.seq_regions or {}) do
        if region.pattern_id == spot.region.pattern_id and spot.end_qn <= get_seq_region_length_qn(region) + 1e-6 then
          band(region, spot.end_qn, len)
        end
      end
    else
      band(spot.region, spot.end_qn, len)
    end
  end
end

-- --- Window ------------------------------------------------------------------------

function seq_fill_preview_data(pick)
  SEQ_FILL_PREVIEW_CACHE = SEQ_FILL_PREVIEW_CACHE or {}
  local ck = pick.kind .. ":" .. tostring(pick.key)
  local data = SEQ_FILL_PREVIEW_CACHE[ck]
  if data then return data end
  if pick.kind == "pattern" then
    data = seq_pattern_preview_data(pick.key)
  else
    local def = seq_fill_def(pick.key)
    data = { cols = def and def.len or 8, lanes = {} }
    for _, lane in ipairs(SEQ_FILL_LANE_ORDER) do
      local s = def and def.lanes[lane]
      if s then
        local steps = {}
        for i = 1, #s do
          if s:sub(i, i) ~= "." then steps[#steps + 1] = i - 1 end
        end
        local ld = SEQ_FILL_LANE_DEFS[lane]
        data.lanes[#data.lanes + 1] = { role = ld.role, steps = steps, color = SEQ_PATTERN_ROLE_COLORS[ld.role] or UI_THEME.text_dim }
      end
    end
  end
  SEQ_FILL_PREVIEW_CACHE[ck] = data
  return data
end

function seq_fill_mix_index(kind, key)
  for i, p in ipairs(seq_fill_state().mix) do
    if p.kind == kind and p.key == key then
      return i
    end
  end
  return nil
end

function seq_fill_toggle_mix(kind, key)
  local f = seq_fill_state()
  local idx = seq_fill_mix_index(kind, key)
  if idx then
    table.remove(f.mix, idx)
  else
    f.mix[#f.mix + 1] = { kind = kind, key = key }
  end
end

function seq_fill_target_label()
  local f = seq_fill_state()
  if f.mode == "razor" then
    local areas, native = seq_fill_razor_areas()
    local n = #(areas or {})
    return (native and "REAPER razor" or "Razor") .. "  \xC2\xB7  " .. tostring(n) .. (n == 1 and " area" or " areas")
  end
  if f.scope == "all" then
    return "All regions"
  end
  return get_seq_region_display_name(get_seq_region_by_id(f.region_id) or get_selected_seq_region())
end

local function seq_fill_point_in(mx, my, x0, y0, x1, y1)
  return mx >= x0 and mx <= x1 and my >= y0 and my <= y1
end

function seq_fill_window_header()
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 0
  local h = 26
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + h, y + h, 0x3A2E12FF, UI_METRICS.radius_ctrl)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + h - 0.5, y + h - 0.5, 0xFFC85744, UI_METRICS.radius_ctrl, 0, 1.0)
  ui_button_draw_icon(dl, "fill", x + h * 0.5, y + h * 0.5, h, SEQ_FILL_COLOR)
  local title = "Fills"
  local tw, th = r.ImGui_CalcTextSize(ctx, title)
  local tx = x + h + 9
  r.ImGui_DrawList_AddText(dl, tx, y + (h - th) * 0.5, UI_THEME.text, title)
  r.ImGui_DrawList_AddText(dl, tx + 0.5, y + (h - th) * 0.5, UI_THEME.text, title)
  local close_s = 20
  local chip_x = tx + tw + 10
  local chip_max = (x + avail - close_s - 8) - chip_x - 14
  if chip_max > 30 then
    draw_ui_pill_label(dl, chip_x, y + h * 0.5, seq_truncate_text_to_width(seq_fill_target_label(), chip_max), {
      bg = UI_THEME.surface, border = UI_THEME.border, text_col = UI_THEME.text_dim,
      pad_x = 7.0, pad_y = 2.0, rounding = 9.0,
    })
  end
  r.ImGui_SetCursorScreenPos(ctx, x + avail - close_s, y + (h - close_s) * 0.5)
  if draw_ui_button("seq_fill_window_close", nil, close_s, close_s, { icon = "close", compact = true, style = "default" }) then
    seq_fill_state().open = false
    seq_fill_keep()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Close (Esc)")
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + h)
  r.ImGui_Dummy(ctx, math.max(1, avail), 6)
end

-- One wrapping row of pill chips. items: { key, label, selected, tip }.
-- Returns the clicked item's key.
function seq_fill_chip_row(id, items)
  local flow = ui_flow_begin(4.0)
  local clicked = nil
  for _, item in ipairs(items) do
    local w = select(1, r.ImGui_CalcTextSize(ctx, item.label)) + 16 + (item.icon and 16 or 0)
    ui_flow_place(flow, w)
    if draw_ui_button("seq_fill_" .. id .. "_" .. tostring(item.key), item.label, w, 22, {
      compact = true, pill = true, selected = item.selected, lead_icon = item.icon,
      color = item.selected and item.color or nil,
    }) then
      clicked = item.key
    end
    if item.tip and r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, item.tip)
    end
  end
  return clicked
end

function seq_fill_render_where(f)
  ui_group_caption("Where")
  if f.mode == "razor" then
    local areas, native = seq_fill_razor_areas()
    local n = #(areas or {})
    local text
    if n == 0 then
      text = "No razor areas. Alt + right-drag in the grid, or use REAPER's razor tool."
    elseif native then
      text = "REAPER razor edits: each area becomes one fill on the tracks it covers."
    else
      text = "Each razor area becomes one fill on the tracks it covers."
    end
    r.ImGui_PushTextWrapPos(ctx, 0)
    r.ImGui_TextColored(ctx, n == 0 and 0xFFB870FF or UI_THEME.text_dim, text)
    r.ImGui_PopTextWrapPos(ctx)
    local hit = seq_fill_chip_row("razor_mode", {
      { key = "region", label = "Use region instead", tip = "Fill at phrase ends of the focused region" },
      { key = "refresh", label = "Re-read razors", tip = "Pick up razor areas drawn since the window opened" },
    })
    if hit == "region" then
      seq_fill_open_for_region(get_selected_seq_region())
    elseif hit == "refresh" then
      state.seq_fill_native_razor_cache = nil
    end
  else
    local scope_hit = seq_fill_chip_row("scope", {
      { key = "region", label = "This region", selected = f.scope ~= "all" },
      { key = "all", label = "All regions", selected = f.scope == "all", tip = "Every region; linked copies share one fill" },
    })
    if scope_hit then seq_fill_set("scope", scope_hit) end
    if seq_fill_any_razor() then
      r.ImGui_SameLine(ctx, 0, 4)
      if draw_ui_button("seq_fill_use_razor", "Razor", nil, 22, { compact = true, pill = true, lead_icon = "fill" }) then
        seq_fill_open_for_razor()
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Fill the razor areas instead")
      end
    end
    local items = {
      { key = "phrase", label = "Phrase ends", selected = f.phrase_on, tip = "Last bars of every phrase" },
    }
    for _, n in ipairs(SEQ_FILL_PHRASE_CHOICES) do
      items[#items + 1] = { key = n, label = tostring(n), selected = f.phrase_on and f.phrase_bars == n,
        tip = "Phrase every " .. tostring(n) .. " bars" }
    end
    items[#items + 1] = { key = "end", label = "Region end", selected = f.end_on, tip = "Right before the region ends" }
    local hit = seq_fill_chip_row("where", items)
    if hit == "phrase" then
      seq_fill_set("phrase_on", not f.phrase_on)
    elseif hit == "end" then
      seq_fill_set("end_on", not f.end_on)
    elseif type(hit) == "number" then
      seq_fill_set("phrase_bars", hit)
      seq_fill_set("phrase_on", true)
    end
  end

  local len_items = {}
  for _, d in ipairs(SEQ_FILL_LENGTHS) do
    len_items[#len_items + 1] = { key = d.key, label = d.label, selected = f.len == d.key,
      tip = d.key == "auto" and "Each fill keeps its own length (razor: the area)" or nil }
  end
  local len_hit = seq_fill_chip_row("len", len_items)
  if len_hit then seq_fill_set("len", len_hit) end

  local opt_items = {
    { key = "crash", label = "Crash after", selected = f.crash, tip = "Crash on the downbeat after each fill" },
  }
  if f.mode == "region" then
    opt_items[#opt_items + 1] = { key = "clear_others", label = "Drop other drums", selected = f.clear_others,
      tip = "Every drum track goes quiet under the fill, not just the ones it plays" }
    local region = get_seq_region_by_id(f.region_id) or get_selected_seq_region()
    if f.scope ~= "all" and region and seq_region_is_linked(region) then
      opt_items[#opt_items + 1] = { key = "unlink", label = "Only this copy", selected = f.unlink,
        tip = "Unlink this region first so its linked copies keep their pattern" }
    end
  end
  local opt_hit = seq_fill_chip_row("opts", opt_items)
  if opt_hit then seq_fill_set(opt_hit, not f[opt_hit]) end

  local spots = seq_fill_compute_spots()
  local note = (#spots == 0) and "No spots: turn on phrase ends or region end."
    or (tostring(#spots) .. (#spots == 1 and " spot" or " spots") .. ", marked in amber on the grid")
  r.ImGui_Dummy(ctx, 1, 2)
  r.ImGui_TextColored(ctx, #spots == 0 and 0xFFB870FF or UI_THEME.text_mute, note)
  r.ImGui_Dummy(ctx, 1, 2)
  return spots
end

-- Random generator card: dice 1..6 insert a fresh random fill at every spot.
function seq_fill_render_random_strip(f, can_insert)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 0
  local h = 32
  ui_draw_panel(dl, x, y, x + avail, y + h, UI_METRICS.radius_ctrl, 0x241D0EFF, 0xFFC85733, false, false)
  local dice_s, gap = 20, 3
  local dice_x = x + avail - 6 - (6 * dice_s + 5 * gap)
  r.ImGui_InvisibleButton(ctx, "##seq_fill_random_label", math.max(1, dice_x - x - 4), h)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "A new random fill at every spot.\nDice 1 is sparse and plain, 6 is dense with rolls.")
  end
  ui_button_draw_icon(dl, "dice" .. tostring(f.energy or 3), x + 16, y + h * 0.5, 20, SEQ_FILL_COLOR)
  local label = "Random fills"
  local _, lh = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, x + 30, y + (h - lh) * 0.5, 0xFFF2D6FF, label)
  for s = 1, 6 do
    r.ImGui_SetCursorScreenPos(ctx, dice_x + (s - 1) * (dice_s + gap), y + (h - dice_s) * 0.5)
    if draw_ui_button("seq_fill_dice_" .. s, nil, dice_s, dice_s, { icon = "dice" .. s, compact = true, style = "default", selected = f.energy == s })
        and can_insert then
      f.energy = s
      f.mix = {}
      seq_fill_insert({}, { energy = s })
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + h)
  r.ImGui_Dummy(ctx, math.max(1, avail), 6)
end

-- One list row: mix checkbox, name, meta, and a step preview on the right.
-- Click inserts it alone; Ctrl/Cmd+click or the box adds it to the mix.
function seq_fill_render_row(kind, key, label, meta, tip, can_insert)
  local row_w = math.max(1.0, (r.ImGui_GetContentRegionAvail(ctx)))
  local row_h = 40.0
  local after_gap = 4.0
  if not seq_pattern_list_item_visible(row_h + after_gap) then
    r.ImGui_Dummy(ctx, 0, row_h + after_gap)
    return
  end
  local f = seq_fill_state()
  local in_mix = seq_fill_mix_index(kind, key)
  r.ImGui_InvisibleButton(ctx, "##seq_fill_row_" .. kind .. "_" .. key, row_w, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local mx, my = r.ImGui_GetMousePos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local selected = in_mix ~= nil

  local fill = selected and 0x2A2412FF or UI_THEME.bg_panel
  local edge = selected and 0xFFC85788 or UI_THEME.border_soft
  if hovered then
    fill = selected and 0x342C16FF or UI_THEME.surface_hvr
    edge = selected and SEQ_FILL_COLOR or UI_THEME.border_hvr
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, 6.0)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, edge, 6.0, 0, 1.0)

  local pad = 8.0
  local box = 14.0
  local bx, by = x0 + pad, y0 + (row_h - box) * 0.5
  local over_box = hovered and seq_fill_point_in(mx, my, bx - 3, by - 3, bx + box + 3, by + box + 3)
  r.ImGui_DrawList_AddRect(dl, bx, by, bx + box, by + box, (selected or over_box) and SEQ_FILL_COLOR or UI_THEME.text_mute, 3.0, 0, 1.2)
  if selected then
    r.ImGui_DrawList_AddRectFilled(dl, bx + 2, by + 2, bx + box - 2, by + box - 2, SEQ_FILL_COLOR, 2.0)
    if #f.mix > 1 then
      local n = tostring(in_mix)
      local nw, nh = r.ImGui_CalcTextSize(ctx, n)
      r.ImGui_DrawList_AddText(dl, bx + (box - nw) * 0.5, by + (box - nh) * 0.5, 0x1A1408FF, n)
    end
  end
  local text_x = bx + box + 8.0
  local grid_w = math.floor(math.min(120.0, row_w * 0.34))
  local grid_x1 = x1 - pad - 2.0
  local grid_x0 = grid_x1 - grid_w
  r.ImGui_DrawList_AddText(dl, text_x, y0 + 5.0, can_insert and UI_THEME.text or UI_THEME.text_dim,
    seq_truncate_text_to_width(label, grid_x0 - text_x - 10.0))
  if meta and meta ~= "" then
    r.ImGui_DrawList_AddText(dl, text_x, y0 + 21.0, UI_THEME.text_mute, seq_truncate_text_to_width(meta, grid_x0 - text_x - 10.0))
  end
  seq_pattern_draw_step_preview(dl, grid_x0, y0 + 7.0, grid_x1, y1 - 7.0, seq_fill_preview_data({ kind = kind, key = key }), 1.0)

  if hovered then
    local lines = {}
    if tip and tip ~= "" then lines[#lines + 1] = tip end
    if over_box then
      lines = { selected and "Click: take out of the mix" or "Click: add to the mix" }
    else
      lines[#lines + 1] = "Click: insert at every spot \xC2\xB7 Ctrl+click: add to the mix"
    end
    r.ImGui_SetTooltip(ctx, table.concat(lines, "\n"))
  end
  if clicked then
    if over_box or is_ctrl_down() or is_cmd_down() then
      seq_fill_toggle_mix(kind, key)
    else
      f.mix = { { kind = kind, key = key } }
      if can_insert then
        seq_fill_insert(f.mix)
      end
    end
  end
end

function seq_fill_render_list(f, can_insert)
  if f.source == "patterns" then
    for _, c in ipairs(SEQ_PATTERN_CATEGORIES) do
      local caption_done = false
      for _, style in ipairs(SEQ_GEN_STYLE_ORDER) do
        if style.key and style.cat == c.key then
          if not caption_done then
            ui_group_caption(c.label)
            caption_done = true
          end
          local meta = style.bpm and (tostring(style.bpm) .. " BPM groove") or "Groove switch"
          seq_fill_render_row("pattern", style.key, style.label or style.key, meta,
            (style.desc and (style.desc .. "\n") or "") .. "The span switches to this groove.", can_insert)
        end
      end
    end
    return
  end
  for _, c in ipairs(SEQ_FILL_CATEGORIES) do
    ui_group_caption(c.label)
    for _, def in ipairs(SEQ_FILL_LIBRARY) do
      if def.cat == c.key then
        local meta = { seq_fill_len_label(def.len) }
        if def.clear_all then meta[#meta + 1] = "kit drops out" end
        if def.ramp then meta[#meta + 1] = "swells" end
        seq_fill_render_row("fill", def.key, def.label, table.concat(meta, "  \xC2\xB7  "), nil, can_insert)
      end
    end
  end
end

-- Mix bar: shown once two or more fills are chosen.
function seq_fill_render_mix_bar(f, can_insert)
  if #f.mix < 2 then return end
  local flow_hit = seq_fill_chip_row("pick", {
    { key = "insert", label = "Insert mix of " .. tostring(#f.mix), selected = true, color = SEQ_FILL_COLOR,
      tip = "Spread the chosen fills over every spot" },
    { key = "cycle", label = "In turn", selected = f.pick ~= "shuffle", tip = "Spot 1 gets fill 1, spot 2 fill 2, ..." },
    { key = "shuffle", label = "Shuffle", selected = f.pick == "shuffle", tip = "Each spot gets one of the chosen fills at random" },
    { key = "clear", label = "Clear", tip = "Empty the mix" },
  })
  if flow_hit == "insert" and can_insert then
    seq_fill_insert(f.mix)
  elseif flow_hit == "cycle" or flow_hit == "shuffle" then
    seq_fill_set("pick", flow_hit)
  elseif flow_hit == "clear" then
    f.mix = {}
  end
  r.ImGui_Dummy(ctx, 1, 2)
end

function seq_fill_render_footer()
  if seq_fill_session_active() then
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local avail = r.ImGui_GetContentRegionAvail(ctx) or 0
    local h = 30
    ui_draw_panel(dl, x, y, x + avail, y + h, UI_METRICS.radius_ctrl, 0x0E2A18F8, UI_THEME.accent, false, false)
    local txt = "Keep these fills?"
    local _, th = r.ImGui_CalcTextSize(ctx, txt)
    r.ImGui_DrawList_AddText(dl, x + 10, y + (h - th) * 0.5, UI_THEME.text, txt)
    local btn, gap = 22, 6
    local bx = x + avail - 8 - btn * 2 - gap
    r.ImGui_SetCursorScreenPos(ctx, bx, y + (h - btn) * 0.5)
    if draw_ui_button("seq_fill_keep", nil, btn, btn, { icon = "check", style = "success", compact = true }) then
      seq_fill_keep()
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Keep") end
    r.ImGui_SetCursorScreenPos(ctx, bx + btn + gap, y + (h - btn) * 0.5)
    if draw_ui_button("seq_fill_revert", nil, btn, btn, { icon = "close", style = "danger", compact = true }) then
      seq_fill_revert()
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Put back what was there before") end
    r.ImGui_SetCursorScreenPos(ctx, x, y + h)
    r.ImGui_Dummy(ctx, math.max(1, avail), 2)
  else
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Click: insert  \xC2\xB7  Ctrl+click: mix  \xC2\xB7  Esc: close")
  end
end

function render_seq_fill_window()
  local f = seq_fill_state()
  if not f.open then
    return
  end
  seq_position_pattern_popup()

  local win_flags = 0
  local function add_flag(getter)
    if getter then win_flags = win_flags | getter() end
  end
  add_flag(r.ImGui_WindowFlags_NoTitleBar)
  add_flag(r.ImGui_WindowFlags_NoCollapse)
  add_flag(r.ImGui_WindowFlags_NoDocking)
  add_flag(r.ImGui_WindowFlags_NoScrollbar)
  add_flag(r.ImGui_WindowFlags_NoScrollWithMouse)

  local visible, keep_open = r.ImGui_Begin(ctx, "Fill Designer##seq_fill_window", true, win_flags)
  if keep_open == false then
    f.open = false
    seq_fill_keep()
  end
  if visible then
    seq_fill_window_header()
    local spots = seq_fill_render_where(f)
    local can_insert = #spots > 0

    ui_group_caption("What")
    seq_fill_render_random_strip(f, can_insert)
    local src_hit = seq_fill_chip_row("source", {
      { key = "fills", label = "Fills", selected = f.source ~= "patterns", tip = "Snare runs, tom runs, hits, stops and builds" },
      { key = "patterns", label = "From patterns", selected = f.source == "patterns", tip = "Switch the span to another pattern preset" },
    })
    if src_hit then seq_fill_set("source", src_hit) end
    r.ImGui_Dummy(ctx, 1, 2)
    seq_fill_render_mix_bar(f, can_insert)

    local footer_h = seq_fill_session_active() and 36 or 22
    local list_flags = 0
    if r.ImGui_WindowFlags_NoBackground then
      list_flags = r.ImGui_WindowFlags_NoBackground()
    end
    if r.ImGui_BeginChild(ctx, "seq_fill_list", 0, -footer_h, 0, list_flags) then
      seq_fill_render_list(f, can_insert)
      r.ImGui_EndChild(ctx)
    end
    seq_fill_render_footer()

    if r.ImGui_IsWindowFocused and r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0)
        and not (r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx))
        and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      f.open = false
      seq_fill_keep()
    end
  end

  end_window(visible, true)
end

-- Sample Map Browser module: song_starter
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
-- Song Starter window: picks loops from the library for a few roles (drums,
-- bass, chords...), matches them to one key and tempo (playrate with preserve
-- pitch + semitone shift), previews them together in sync and adds them to
-- the project as a folder of tracks. Re-roll one part, lock the ones you like,
-- and a Safe <-> Chaos slider sets how far the picks may stray.
-- Settings, slots and the last starters live in SampleMapSongStarter.json.
local r = reaper

SS_FILE = (CONFIG_DIR or SCRIPT_DIR or ".") .. "/SampleMapSongStarter.json"
SS_HISTORY_MAX = 20
SS_RECENT_PER_SLOT = 8

-- Monolith look, this window only.
SS_COL = {
  bg       = 0x050505FF,
  panel    = 0x0B0B0BFF,
  line     = 0xFFFFFF1F,
  line_hi  = 0xFFFFFF40,
  text     = 0xE8E8E8FF,
  dim      = 0x8A8A8AFF,
  mute     = 0x555555FF,
  accent   = 0x49CC85FF,
  accent_d = 0x49CC8526,
  accent_m = 0x49CC8560,
  warn     = 0xE0A060FF,
}

-- Roles. tags: library tags (see TAG_KEYWORDS); words: name words.
-- 2 = clearly this role, 1 = could be. pitched: semitone shift to the key;
-- melodic: wants a known key in Safe mode.
SS_ROLES = {
  { key = "drums", label = "Drums",
    tags = { drum = 2, kick = 1, snare = 1, clap = 1 },
    words = { drum = 2, drums = 2, beat = 2, beats = 2, ["break"] = 2, breaks = 2, breakbeat = 2,
              groove = 1, full = 1, kit = 1 } },
  { key = "top", label = "Top / Perc",
    tags = { hat = 2, perc = 2, ride = 2, crash = 1, snap = 1, rim = 1 },
    words = { top = 2, tops = 2, perc = 2, percussion = 2, hat = 2, hats = 2, hihat = 2, hihats = 2,
              shaker = 2, shakers = 2, ride = 2, tambourine = 2, conga = 2, congas = 2, bongo = 2, bongos = 2 } },
  { key = "bass", label = "Bass", pitched = true, melodic = true,
    tags = { bass = 2, ["808s"] = 2, ["808"] = 2 },
    words = { bass = 2, bassline = 2, basslines = 2, sub = 2, reese = 2, ["808"] = 2 } },
  { key = "chords", label = "Chords / Keys", pitched = true, melodic = true,
    tags = { keys = 2, pad = 1, guitar = 1 },
    words = { chord = 2, chords = 2, keys = 2, piano = 2, rhodes = 2, organ = 2, stab = 2, stabs = 2,
              progression = 2, epiano = 2, wurli = 2, guitar = 1, pad = 1 } },
  { key = "lead", label = "Lead / Melody", pitched = true, melodic = true,
    tags = { lead = 2, pluck = 2, guitar = 1, vocal = 1 },
    words = { lead = 2, leads = 2, melody = 2, melodies = 2, melodic = 1, arp = 2, arps = 2, hook = 2,
              pluck = 2, plucks = 2, riff = 2, riffs = 2, synth = 1, bell = 1, bells = 1, flute = 1 } },
  { key = "texture", label = "Texture / FX", pitched = true,
    tags = { pad = 2, fx = 2 },
    words = { texture = 2, textures = 2, atmos = 2, atmosphere = 2, ambience = 2, ambient = 2, drone = 2,
              pad = 2, pads = 2, foley = 2, vinyl = 2, noise = 1, fx = 2, sfx = 2 } },
}
SS_ROLE = {}
for i, role in ipairs(SS_ROLES) do
  role.index = i
  SS_ROLE[role.key] = role
end
SS_NEIGHBOURS = {
  drums = { "top" }, top = { "drums", "texture" }, bass = { "lead" },
  chords = { "lead", "texture" }, lead = { "chords", "texture" }, texture = { "chords", "top" },
}
SS_DEFAULT_ROLES = { "drums", "top", "bass", "chords", "lead", "texture" }

SS_NOTE_NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local SS_LETTER_PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

-- Random source; tests replace it for repeatable picks.
ss_rand = math.random

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------

-- "C#m", "Bb", "F# minor", "Ebmaj" -> pitch class 0..11, minor (bool). nil when unreadable.
function ss_parse_key(key)
  if type(key) ~= "string" then
    return nil
  end
  local s = key:gsub("^%s+", ""):gsub("%s+$", "")
  local letter, rest = s:match("^([A-Ga-g])(.*)$")
  if not letter then
    return nil
  end
  local pc = SS_LETTER_PC[letter:upper()]
  local acc = rest:sub(1, 1)
  if acc == "#" then
    pc, rest = pc + 1, rest:sub(2)
  elseif acc == "b" then
    pc, rest = pc - 1, rest:sub(2)
  end
  rest = rest:gsub("^[%s_%-]+", "")
  local low = rest:lower()
  local minor = false
  if rest == "m" or low:find("^min") or (rest:sub(1, 1) == "m" and not low:find("^maj")) then
    minor = true
  end
  return pc % 12, minor
end

function ss_key_name(pc, minor)
  if pc == nil then
    return nil
  end
  return SS_NOTE_NAMES[(pc % 12) + 1] .. (minor and "m" or "")
end

-- Same key spelled the house way ("A#min" -> "Bbm"); nil when unreadable.
function ss_norm_key(key)
  local pc, minor = ss_parse_key(key)
  return ss_key_name(pc, minor)
end

-- Smallest semitone move (-6..+5) that takes src_key to target_key. A key of
-- the other mode goes to the target's relative (A minor -> C major is 0).
-- nil when either key is unknown.
function ss_pitch_shift(src_key, target_key)
  local spc, sminor = ss_parse_key(src_key)
  local tpc, tminor = ss_parse_key(target_key)
  if not spc or not tpc then
    return nil
  end
  if sminor and not tminor then
    spc = spc + 3
  elseif tminor and not sminor then
    spc = spc + 9
  end
  return ((tpc - spc + 6) % 12) - 6
end

-- Tempo for a loop of `duration` seconds with no tempo in its name: a whole
-- number of 4/4 bars at 70..180 bpm, 1/2/4/8/16 bars first (then 3/6/12),
-- the one nearest `near_bpm` (default 120) when several fit. -> bpm, bars.
function ss_bpm_from_length(duration, near_bpm)
  if type(duration) ~= "number" or duration <= 0.2 then
    return nil
  end
  near_bpm = tonumber(near_bpm) or 120
  for _, set in ipairs({ { 1, 2, 4, 8, 16 }, { 3, 6, 12 } }) do
    local best, best_bars, best_d = nil, nil, nil
    for _, bars in ipairs(set) do
      local bpm = bars * 240.0 / duration
      if bpm >= 70 and bpm <= 180 then
        local d = math.abs(math.log(bpm / near_bpm))
        if not best_d or d < best_d then
          best, best_bars, best_d = bpm, bars, d
        end
      end
    end
    if best then
      return best, best_bars
    end
  end
  return nil
end

-- Tempo and key of a library sample: from the analyzer/name fields, else the
-- name, else (tempo only) its length. -> bpm, estimated (bool), key or nil.
local ss_named_memo = setmetatable({}, { __mode = "k" })

function ss_sample_tempo_key(s, near_bpm)
  if not s then
    return nil
  end
  local memo = ss_named_memo[s]
  if not memo or memo.path ~= s.path or memo.sbpm ~= s.bpm or memo.skey ~= s.key then
    local bpm, key = tonumber(s.bpm), s.key
    if (not bpm or type(key) ~= "string" or key == "") and sm_sample_bpm_key then
      local nb, nk = sm_sample_bpm_key(s.path)
      bpm = bpm or tonumber(nb)
      if type(key) ~= "string" or key == "" then
        key = nk
      end
    end
    if type(key) ~= "string" or key == "" then
      key = nil
    end
    memo = { path = s.path, sbpm = s.bpm, skey = s.key, bpm = bpm, key = key }
    ss_named_memo[s] = memo
  end
  local bpm, key = memo.bpm, memo.key
  if bpm and bpm > 0 then
    return bpm, false, key
  end
  local est = ss_bpm_from_length(tonumber(s.duration), near_bpm)
  if est then
    return est, true, key
  end
  return nil, false, key
end

-- Playrate that takes src_bpm to target_bpm; with allow_hd the source may count
-- as half or double time when that keeps the rate nearer 1. -> rate, mult.
function ss_stretch(src_bpm, target_bpm, allow_hd)
  src_bpm, target_bpm = tonumber(src_bpm), tonumber(target_bpm)
  if not src_bpm or src_bpm <= 0 or not target_bpm or target_bpm <= 0 then
    return 1.0, 1
  end
  local best_rate, best_mult, best_d = nil, 1, nil
  for _, mult in ipairs(allow_hd and { 1, 2, 0.5 } or { 1 }) do
    local rate = target_bpm / (src_bpm * mult)
    local d = math.abs(math.log(rate))
    if not best_d or d < best_d - 1e-9 then
      best_rate, best_mult, best_d = rate, mult, d
    end
  end
  return best_rate, best_mult
end

-- How far the picks may stray, from the Safe (0) <-> Chaos (1) slider.
function ss_chaos_params(c)
  c = math.max(0.0, math.min(1.0, tonumber(c) or 0.0))
  return {
    chaos = c,
    max_dev = 0.08 + 0.32 * c,                 -- stretch ratio within 1 +- this
    allow_hd = c >= 0.3,                       -- half / double time
    allow_est_bpm = c >= 0.25,                 -- tempo guessed from the length
    max_shift = math.floor(2 + 4 * c + 0.5),   -- semitones
    allow_unknown_key = c >= 0.5,              -- melodic parts with no key
    min_strength = (c < 0.35) and 2 or 1,      -- how clearly it must be the role
    neighbour_p = 0.3 * c,                     -- pick from a neighbouring role
  }
end

function ss_is_loop(s)
  if not s or not s.path then
    return false
  end
  if s.playback_type == "loop" then
    return true
  end
  if type(s.tags) == "table" then
    for _, t in ipairs(s.tags) do
      if tostring(t):lower() == "loop" then
        return true
      end
    end
  end
  return false
end

-- Role scores of a sample: { drums = 2, bass = 0, ... } from its tags, name
-- words (full weight) and folder words (at most 1). Memoized per sample table.
local ss_role_memo = setmetatable({}, { __mode = "k" })

function ss_role_scores(s)
  local hit = ss_role_memo[s]
  if hit then
    return hit
  end
  local tags = {}
  for _, t in ipairs(type(s.tags) == "table" and s.tags or {}) do
    tags[tostring(t):lower()] = true
  end
  local path = tostring(s.path or ""):gsub("\\", "/")
  local file = (path:match("([^/]+)$") or path):gsub("%.%w+$", "")
  local folder = path:match("([^/]+)/[^/]+$") or ""
  local name_words, folder_words = {}, {}
  for _, w in ipairs(sm_name_words and sm_name_words(file) or {}) do name_words[w] = true end
  for _, w in ipairs(sm_name_words and sm_name_words(folder) or {}) do folder_words[w] = true end
  local out = {}
  for _, role in ipairs(SS_ROLES) do
    local best = 0
    for t, v in pairs(role.tags) do
      if tags[t] and v > best then best = v end
    end
    for w, v in pairs(role.words) do
      if name_words[w] and v > best then best = v end
      if folder_words[w] and best < 1 then best = 1 end
    end
    out[role.key] = best
  end
  ss_role_memo[s] = out
  return out
end

-- How clearly `s` is `role_key`: 0 when it isn't, or when another role
-- describes it better (a "Bass Loop" is not a drum loop).
function ss_role_strength(s, role_key)
  local scores = ss_role_scores(s)
  local mine = scores[role_key] or 0
  if mine <= 0 then
    return 0
  end
  for k, v in pairs(scores) do
    if k ~= role_key and v > mine then
      return 0
    end
  end
  return mine
end

-- Candidate entry for sample s in role_key at the target, or nil when the
-- params rule it out.
function ss_eval_candidate(s, role_key, target_bpm, target_key, P)
  local role = SS_ROLE[role_key]
  if not role then
    return nil
  end
  local strength = ss_role_strength(s, role_key)
  if strength < P.min_strength then
    return nil
  end
  local bpm, est, key = ss_sample_tempo_key(s, target_bpm)
  if not bpm or (est and not P.allow_est_bpm) then
    return nil
  end
  local rate, mult = ss_stretch(bpm, target_bpm, P.allow_hd)
  local dev = math.abs(rate - 1.0)
  if dev > P.max_dev + 1e-9 then
    return nil
  end
  local shift = 0
  if role.pitched and key and target_key then
    shift = ss_pitch_shift(key, target_key) or 0
    if math.abs(shift) > P.max_shift then
      return nil
    end
  end
  if role.melodic and not key and not P.allow_unknown_key then
    return nil
  end
  local score = strength
    + (1.0 - dev / math.max(0.01, P.max_dev))
    + (role.pitched and key and target_key and (1.0 - math.abs(shift) / 7.0) or 0)
    + (mult == 1 and 0.3 or 0)
    + (est and 0 or 0.3)
  return {
    sample = s, path = s.path, role = role_key, bpm = bpm, est = est, key = key,
    rate = rate, mult = mult, shift = shift, strength = strength, score = score,
  }
end

-- Candidates for role_key from pool, skipping paths in `exclude`.
function ss_candidates(pool, role_key, target_bpm, target_key, P, exclude)
  local out = {}
  for i = 1, #pool do
    local s = pool[i]
    if s and s.path and not (exclude and exclude[s.path]) then
      local c = ss_eval_candidate(s, role_key, target_bpm, target_key, P)
      if c then
        out[#out + 1] = c
      end
    end
  end
  return out
end

-- Weighted random pick: Safe leans hard on the best scores, Chaos is near uniform.
function ss_weighted_pick(cands, chaos)
  if #cands == 0 then
    return nil
  end
  local sharp = 2.5 * (1.0 - (chaos or 0))
  local total, w = 0, {}
  for i, c in ipairs(cands) do
    w[i] = math.exp(c.score * sharp)
    total = total + w[i]
  end
  local x = ss_rand() * total
  for i, c in ipairs(cands) do
    x = x - w[i]
    if x <= 0 then
      return c
    end
  end
  return cands[#cands]
end

-- Pick a loop for `slot`. ctx: pool, target_bpm, target_key, chaos, used
-- (paths taken by other slots). Relaxes toward Chaos when nothing fits.
-- -> candidate entry or nil.
function ss_pick_for_slot(slot, ctx)
  local recent = {}
  for _, p in ipairs(slot.recent or {}) do recent[p] = true end
  if slot.path then recent[slot.path] = true end
  local levels = { ctx.chaos or 0 }
  if (ctx.chaos or 0) < 0.65 then levels[#levels + 1] = math.min(1.0, (ctx.chaos or 0) + 0.35) end
  if levels[#levels] < 1.0 then levels[#levels + 1] = 1.0 end
  for li, c in ipairs(levels) do
    local P = ss_chaos_params(c)
    local role_key = slot.role
    if li == 1 and ss_rand() < P.neighbour_p then
      local nb = SS_NEIGHBOURS[slot.role]
      if nb and #nb > 0 then
        role_key = nb[math.floor(ss_rand() * #nb) + 1] or slot.role
      end
    end
    local exclude = {}
    for p in pairs(ctx.used or {}) do exclude[p] = true end
    for p in pairs(recent) do exclude[p] = true end
    local cands = ss_candidates(ctx.pool, role_key, ctx.target_bpm, ctx.target_key, P, exclude)
    if #cands == 0 and role_key ~= slot.role then
      role_key = slot.role
      cands = ss_candidates(ctx.pool, role_key, ctx.target_bpm, ctx.target_key, P, exclude)
    end
    if #cands == 0 then
      -- Everything fitting was heard lately: allow repeats (not other slots' files).
      cands = ss_candidates(ctx.pool, role_key, ctx.target_bpm, ctx.target_key, P, ctx.used)
      if #cands > 1 and slot.path then
        for i = #cands, 1, -1 do
          if cands[i].path == slot.path then table.remove(cands, i) end
        end
      end
    end
    local pick = ss_weighted_pick(cands, c)
    if pick then
      pick.relaxed = li > 1
      return pick
    end
  end
  return nil
end

-- Copy a candidate's numbers into a slot.
function ss_slot_take(slot, c)
  local s = c.sample
  slot.path = c.path
  slot.name = s and s.name or (c.path and c.path:match("([^/\\]+)$")) or "?"
  slot.src_bpm = c.bpm
  slot.bpm_est = c.est and true or false
  slot.src_key = c.key
  slot.rate = c.rate
  slot.mult = c.mult
  slot.shift = c.shift
  slot.dur = s and tonumber(s.duration) or slot.dur
  slot.from_role = (c.role ~= slot.role) and c.role or nil
  slot.relaxed = c.relaxed or nil
  slot.no_match = nil
  slot.recent = slot.recent or {}
  table.insert(slot.recent, 1, c.path)
  while #slot.recent > SS_RECENT_PER_SLOT do
    table.remove(slot.recent)
  end
end

-- Recompute a slot's rate / shift for the target (after a key or tempo change).
-- Half / double time is always open here, so a big tempo move stays playable.
function ss_slot_retarget(slot, target_bpm, target_key)
  if not slot.path or not slot.src_bpm then
    return
  end
  slot.rate, slot.mult = ss_stretch(slot.src_bpm, target_bpm, true)
  local role = SS_ROLE[slot.role]
  local pitched = role and role.pitched
  if slot.from_role and SS_ROLE[slot.from_role] then
    pitched = SS_ROLE[slot.from_role].pitched
  end
  slot.shift = (pitched and slot.src_key and target_key) and (ss_pitch_shift(slot.src_key, target_key) or 0) or 0
end

-- Key of the first melodic slot (in order) that has one.
function ss_first_melodic_key(slots, only_locked)
  for _, slot in ipairs(slots) do
    local role = SS_ROLE[slot.role]
    if role and role.melodic and slot.path and slot.src_key and (slot.locked or not only_locked) then
      return ss_norm_key(slot.src_key)
    end
  end
  return nil
end

-- Re-pick slots. which: "unlocked" (every unlocked slot), "batch" (the same,
-- and with an automatic key the key comes from the new melodic picks), or a
-- slot table. Melodic slots go first so an automatic key exists before the
-- rest are pitched. st: the Song Starter state. -> number of slots changed.
function ss_reroll(st, pool, which)
  local slots = st.slots
  local todo = {}
  if type(which) == "table" then
    todo[1] = which
  else
    for _, slot in ipairs(slots) do
      if not slot.locked then todo[#todo + 1] = slot end
    end
  end
  if which == "batch" and st.key_auto then
    st.target_key = ss_first_melodic_key(slots, true)
  end
  table.sort(todo, function(a, b)
    local am = SS_ROLE[a.role] and SS_ROLE[a.role].melodic and 0 or 1
    local bm = SS_ROLE[b.role] and SS_ROLE[b.role].melodic and 0 or 1
    if am ~= bm then return am < bm end
    return (a.order or 0) < (b.order or 0)
  end)
  local redo = {}
  for _, slot in ipairs(todo) do redo[slot] = true end
  local used = {}
  for _, slot in ipairs(slots) do
    if slot.path and not redo[slot] then used[slot.path] = true end
  end
  local changed = 0
  for _, slot in ipairs(todo) do
    local pick = ss_pick_for_slot(slot, {
      pool = pool, target_bpm = st.target_bpm, target_key = st.target_key, chaos = st.chaos, used = used,
    })
    if pick then
      ss_slot_take(slot, pick)
      used[pick.path] = true
      changed = changed + 1
      if not st.target_key and pick.key and SS_ROLE[slot.role] and SS_ROLE[slot.role].melodic then
        st.target_key = ss_norm_key(pick.key)
        slot.shift = 0
      end
    elseif ss_search_active(st) then
      -- the search found nothing for this slot: keep what it has, say so
      slot.no_match = true
    else
      slot.path, slot.name, slot.src_bpm, slot.src_key = nil, nil, nil, nil
    end
  end
  return changed
end

-- Slots that sound: unmuted, and soloed when any slot is.
function ss_slot_audible(slots, slot)
  if not slot.path or slot.muted then
    return false
  end
  for _, o in ipairs(slots) do
    if o.solo and o.path then
      return slot.solo == true
    end
  end
  return true
end

-- Loop length in seconds at the target tempo.
function ss_slot_len(slot)
  local dur = tonumber(slot.dur)
  if not dur or dur <= 0 then
    return nil
  end
  return dur / math.max(0.05, tonumber(slot.rate) or 1.0)
end

-- Length of a slot's loop in bars at bpm (its own length, not the set's):
-- whole bars, or quarters below one bar. nil when the length is unknown.
function ss_slot_bars(slot, bpm)
  local len = ss_slot_len(slot)
  bpm = tonumber(bpm)
  if not len or not bpm or bpm <= 0 then
    return nil
  end
  local bars = len * bpm / 240.0
  if bars >= 0.875 then
    return math.max(1, math.floor(bars + 0.5))
  end
  return math.max(0.25, math.floor(bars * 4 + 0.5) / 4)
end

-- Source position (seconds) at which a loop rejoins playback `elapsed` seconds
-- in. With bpm: global bar position mod the loop's own bar count, so a 4-bar
-- loop repeats inside an 8-bar set and a 16-bar loop runs on across cycles,
-- locked to the bar grid even when the file is a hair off its bar length.
function ss_loop_phase(slot, elapsed, bpm)
  local dur = tonumber(slot.dur)
  if not dur or dur <= 0 then
    return 0
  end
  elapsed = math.max(0, elapsed or 0)
  local own = ss_slot_bars(slot, bpm)
  if own then
    local bar = elapsed * bpm / 240.0
    return ((bar % own) / own) * dur
  end
  local rate = tonumber(slot.rate) or 1.0
  return (elapsed * rate) % dur
end

-- Bar (0-based, fractional) within the loop's own length `elapsed` seconds in. -> bar, own bars.
function ss_slot_bar_at(slot, elapsed, bpm)
  local own = ss_slot_bars(slot, bpm)
  if not own then
    return nil
  end
  return (math.max(0, elapsed or 0) * bpm / 240.0) % own, own
end

---------------------------------------------------------------------------
-- Arrangement: song sections and which roles play in each
---------------------------------------------------------------------------

-- Section types. color: region / strip tick (0xRRGGBB). drop: everything plays
-- and the section before it gets a gap for impact.
SS_SECTION_TYPES = {
  intro     = { label = "Intro",     color = 0x4A6FA5 },
  verse     = { label = "Verse",     color = 0x5A8FBF },
  pre       = { label = "Pre",       color = 0xD9A441, rise = true },
  build     = { label = "Build",     color = 0xD9A441, rise = true },
  chorus    = { label = "Chorus",    color = 0x49CC85, drop = true },
  hook      = { label = "Hook",      color = 0x49CC85, drop = true },
  drop      = { label = "Drop",      color = 0x49CC85, drop = true },
  breakdown = { label = "Breakdown", color = 0x8E6CC9 },
  outro     = { label = "Outro",     color = 0x6B6B6B },
}

SS_TEMPLATES = {
  { key = "club", label = "Club", sections = { { "intro", 8 }, { "build", 8 }, { "drop", 16 }, { "breakdown", 8 },
    { "build", 8 }, { "drop", 16 }, { "outro", 8 } } },
  { key = "pop", label = "Pop", sections = { { "intro", 4 }, { "verse", 8 }, { "pre", 4 }, { "chorus", 8 },
    { "verse", 8 }, { "pre", 4 }, { "chorus", 8 }, { "outro", 4 } } },
  { key = "hiphop", label = "Hip-hop", sections = { { "intro", 4 }, { "verse", 16 }, { "hook", 8 }, { "verse", 16 },
    { "hook", 8 }, { "outro", 4 } } },
  { key = "short", label = "Short", sections = { { "intro", 4 }, { "build", 4 }, { "drop", 8 }, { "outro", 4 } } },
  { key = "random", label = "Random" },
}
SS_TEMPLATE = {}
for _, t in ipairs(SS_TEMPLATES) do SS_TEMPLATE[t.key] = t end

-- Textbook role presence per section type. Per role: from / to as fractions
-- of the section (enter late / leave early), vol, rise (volume rises to the
-- next section). Roles not listed are out. "*" = every role.
SS_PRESENCE = {
  intro     = { texture = {}, chords = {}, top = { from = 0.5 } },
  build     = { drums = { rise = true }, top = { rise = true }, texture = { rise = true }, chords = {},
                lead = { from = 0.5, vol = 0.6 } },
  pre       = { drums = { rise = true }, top = { rise = true }, texture = { rise = true }, chords = {}, bass = {},
                lead = { from = 0.5, vol = 0.6 } },
  verse     = { drums = {}, top = {}, bass = {}, chords = {} },
  chorus    = { ["*"] = {} },
  hook      = { ["*"] = {} },
  drop      = { ["*"] = {} },
  breakdown = { chords = {}, lead = {}, texture = {} },
  outro     = { texture = {}, chords = { to = 0.75 }, top = { to = 0.75 }, drums = { to = 0.5 }, bass = { to = 0.5 } },
}
SS_GAP_ROLES = { drums = true, bass = true, top = true }

-- Section list { {type, bars}, ... } for a template; Random builds one
-- (more unusual with chaos).
function ss_template_sections(template_key, chaos)
  local t = SS_TEMPLATE[template_key] or SS_TEMPLATE.club
  if t.sections then
    local out = {}
    for i, s in ipairs(t.sections) do out[i] = { s[1], s[2] } end
    return out
  end
  chaos = tonumber(chaos) or 0
  local function pick(list) return list[math.floor(ss_rand() * #list) + 1] end
  local function len(a, b) return (ss_rand() < 0.5) and a or b end
  local out = {}
  if ss_rand() >= chaos * 0.4 then out[#out + 1] = { "intro", len(4, 8) } end
  local style = pick({ "club", "song" })
  local cycles = (ss_rand() < 0.3 + chaos * 0.3) and 3 or 2
  for c = 1, cycles do
    if style == "club" then
      out[#out + 1] = { "build", len(4, 8) }
      out[#out + 1] = { "drop", len(8, 16) }
    else
      out[#out + 1] = { "verse", len(8, 16) }
      if ss_rand() < 0.6 then out[#out + 1] = { "pre", 4 } end
      out[#out + 1] = { pick({ "chorus", "hook" }), 8 }
    end
    if c < cycles and ss_rand() < 0.45 then out[#out + 1] = { "breakdown", len(4, 8) } end
  end
  out[#out + 1] = { "outro", len(4, 8) }
  -- Chaos: swap some sections for another type, odd lengths.
  if chaos > 0 then
    local types = { "intro", "verse", "pre", "build", "chorus", "drop", "breakdown" }
    for i = 2, #out - 1 do
      if ss_rand() < chaos * 0.3 then out[i][1] = pick(types) end
      if ss_rand() < chaos * 0.25 then out[i][2] = pick({ 2, 6, 12 }) end
    end
  end
  return out
end

-- Arrangement for the role list: { template, sections = { { type, name, bars,
-- start, parts = { [role] = { from, to, vol, rise } } } }, total }. Bars are
-- 4/4 bars; from / to are bars into the section. Safe (chaos 0) is textbook;
-- chaos adds random entries, dropouts and gap changes.
function ss_build_arrangement(template_key, chaos, roles)
  chaos = math.max(0, math.min(1, tonumber(chaos) or 0))
  local list = ss_template_sections(template_key, chaos)
  local p = chaos * 0.4
  local function roll(prob) return prob > 0 and ss_rand() < prob end
  roles = roles or SS_DEFAULT_ROLES
  local counts, seen = {}, {}
  for _, s in ipairs(list) do counts[s[1]] = (counts[s[1]] or 0) + 1 end
  local arr = { template = template_key, sections = {}, total = 0 }
  local start = 0
  for i, s in ipairs(list) do
    local typ, bars = s[1], s[2]
    local def = SS_SECTION_TYPES[typ] or SS_SECTION_TYPES.verse
    seen[typ] = (seen[typ] or 0) + 1
    local name = def.label .. ((counts[typ] or 0) > 1 and (" " .. seen[typ]) or "")
    local rules = SS_PRESENCE[typ] or {}
    local parts = {}
    for _, role in ipairs(roles) do
      local rule = rules[role] or rules["*"]
      if def.drop then
        -- Chaos: one part sits out the first half of a drop now and then.
        if rule and roll(p * 0.3) and role ~= "drums" then
          rule = { from = 0.5 }
        end
      elseif roll(p * 0.5) then
        -- Chaos: flip a part in or out.
        rule = (not rule) and { vol = 0.8 } or nil
      end
      if rule then
        local from = math.floor((rule.from or 0) * bars + 0.5)
        local to = math.floor((rule.to or 1) * bars + 0.5)
        if from == 0 and bars >= 8 and not def.drop and roll(p) then
          from = math.floor(bars / 2)
        end
        local vol = rule.vol or 1.0
        if typ == "verse" and role == "lead" then vol = 0.5 end
        if to > from then
          parts[role] = { from = from, to = to, vol = vol, rise = rule.rise or nil }
        end
      end
    end
    if typ == "verse" and not parts.lead and roll(p) then
      parts.lead = { from = 0, to = bars, vol = 0.5 }
    end
    if next(parts) == nil then
      parts[roles[1] or "drums"] = { from = 0, to = bars, vol = 1.0 }
    end
    arr.sections[i] = { type = typ, name = name, bars = bars, start = start, parts = parts }
    start = start + bars
  end
  -- Pre-drop gap: drums / bass / top drop out at the end of the section
  -- before a drop / chorus / hook.
  for i = 1, #arr.sections - 1 do
    local sec, nxt = arr.sections[i], arr.sections[i + 1]
    local ndef = SS_SECTION_TYPES[nxt.type]
    if ndef and ndef.drop and not (SS_SECTION_TYPES[sec.type] or {}).drop and not roll(p * 0.3) then
      local gap = sec.bars >= 8 and 1 or 0.5
      if roll(p * 0.5) then gap = (ss_rand() < 0.5) and 0.5 or 2 end
      gap = math.min(gap, sec.bars / 2)
      sec.gap = gap
      for role, part in pairs(sec.parts) do
        if SS_GAP_ROLES[role] and part.to > sec.bars - gap then
          part.to = sec.bars - gap
          if part.to <= part.from then sec.parts[role] = nil end
        end
      end
    end
  end
  arr.total = start
  return arr
end

-- Section holding bar (0-based bars from the start), and its index.
function ss_arr_section_at(arr, bar)
  for i, sec in ipairs(arr and arr.sections or {}) do
    if bar >= sec.start and bar < sec.start + sec.bars then
      return sec, i
    end
  end
  return nil
end

-- Gain of role at `bar` in the arrangement (0 = out). A rising part climbs
-- from silence like the item fade-in it becomes (fast-start curve).
function ss_arr_gain(arr, role, bar)
  local sec = ss_arr_section_at(arr, bar)
  local part = sec and sec.parts[role]
  if not part then
    return 0.0
  end
  local rel = bar - sec.start
  if rel < part.from or rel >= part.to then
    return 0.0
  end
  local g = part.vol or 1.0
  if part.rise then
    g = g * math.sqrt(math.max(0, (rel - part.from) / math.max(0.001, part.to - part.from)))
  end
  return g
end

-- Arrangement for st, rebuilt when missing or for another template.
function ss_arrangement(st, rebuild)
  if rebuild or type(st.arr) ~= "table" or type(st.arr.sections) ~= "table" or #st.arr.sections == 0
      or st.arr.template ~= st.template then
    st.arr = ss_build_arrangement(st.template or "club", st.chaos, SS_DEFAULT_ROLES)
  end
  return st.arr
end

---------------------------------------------------------------------------
-- State and persistence
---------------------------------------------------------------------------

local SS_SLOT_KEYS = { "id", "role", "path", "name", "locked", "muted", "solo", "vol", "src_bpm", "bpm_est",
  "src_key", "rate", "mult", "shift", "dur", "from_role" }

local function ss_copy_slot(slot, keys)
  local out = {}
  for _, k in ipairs(keys or SS_SLOT_KEYS) do
    out[k] = slot[k]
  end
  return out
end

function ss_new_slot(st, role_key)
  st.next_id = (st.next_id or 0) + 1
  return { id = st.next_id, role = role_key, vol = 1.0, recent = {} }
end

function ss_state()
  local st = state.song_starter
  if st then
    return st
  end
  st = {
    open = false, target_bpm = nil, target_key = nil, key_auto = true, chaos = 0.25, scope = "library",
    bars = 8, set_tempo = false, slots = {}, history = {}, next_id = 0,
    mode = "loop", template = "club", arr = nil, hist_filter = "all",
    search_chips = {}, search_mode = "any",
  }
  state.song_starter = st
  local content = sm_read_nonempty_file and sm_read_nonempty_file(SS_FILE)
  local ok, cfg = false, nil
  if content then
    ok, cfg = pcall(json_decode, content)
  end
  if ok and type(cfg) == "table" then
    st.open = cfg.open == true
    st.target_bpm = tonumber(cfg.target_bpm)
    st.target_key = ss_norm_key(cfg.target_key)
    st.key_auto = cfg.key_auto ~= false
    st.chaos = math.max(0, math.min(1, tonumber(cfg.chaos) or 0.25))
    st.scope = (cfg.scope == "map") and "map" or "library"
    st.bars = (cfg.bars == 4 or cfg.bars == 16) and cfg.bars or 8
    st.set_tempo = cfg.set_tempo == true
    st.mode = (cfg.mode == "arrange") and "arrange" or "loop"
    st.hist_filter = (cfg.hist_filter == "liked") and "liked" or "all"
    st.search_mode = (cfg.search_mode == "all") and "all" or "any"
    st.search_chips = {}
    for _, q in ipairs(type(cfg.search_chips) == "table" and cfg.search_chips or {}) do
      if type(q) == "string" and q ~= "" then st.search_chips[#st.search_chips + 1] = q end
    end
    st.template = SS_TEMPLATE[cfg.template] and cfg.template or "club"
    if ss_arr_valid(cfg.arr) then st.arr = cfg.arr end
    for _, sl in ipairs(type(cfg.slots) == "table" and cfg.slots or {}) do
      if type(sl) == "table" and SS_ROLE[sl.role] then
        local slot = ss_new_slot(st, sl.role)
        for _, k in ipairs(SS_SLOT_KEYS) do
          if k ~= "id" and sl[k] ~= nil then slot[k] = sl[k] end
        end
        if slot.path then slot.recent = { slot.path } end
        st.slots[#st.slots + 1] = slot
      end
    end
    for _, h in ipairs(type(cfg.history) == "table" and cfg.history or {}) do
      if type(h) == "table" and type(h.slots) == "table" then
        if h.pinned then
          -- pins became likes
          h.liked, h.pinned = true, nil
        end
        st.history[#st.history + 1] = h
      end
    end
  end
  if #st.slots == 0 then
    for _, k in ipairs(SS_DEFAULT_ROLES) do
      st.slots[#st.slots + 1] = ss_new_slot(st, k)
    end
  end
  return st
end

function ss_save_now()
  local st = state.song_starter
  if not st or not json_encode or not sm_atomic_write then
    return
  end
  st._save_due = nil
  local slots = {}
  for _, slot in ipairs(st.slots) do
    slots[#slots + 1] = ss_copy_slot(slot)
  end
  local cfg = {
    v = 1, open = st.open == true, target_bpm = st.target_bpm, target_key = st.target_key,
    key_auto = st.key_auto ~= false, chaos = st.chaos, scope = st.scope, bars = st.bars,
    set_tempo = st.set_tempo == true, slots = slots, history = st.history,
    mode = st.mode, template = st.template, arr = st.arr, hist_filter = st.hist_filter,
    search_chips = st.search_chips, search_mode = st.search_mode,
  }
  local ok, json = pcall(json_encode, cfg)
  if ok and type(json) == "string" then
    sm_atomic_write(SS_FILE, json)
  end
end

function ss_save()
  local st = ss_state()
  st._save_due = r.time_precise() + 0.5
end

-- Snapshot of the current starter for the history list.
function ss_snapshot(st)
  local slots = {}
  for _, slot in ipairs(st.slots) do
    if slot.path then
      slots[#slots + 1] = ss_copy_slot(slot, { "role", "path", "name", "vol", "muted", "src_bpm", "bpm_est",
        "src_key", "dur", "from_role" })
    end
  end
  if #slots == 0 then
    return nil
  end
  local h = { t = os.time(), bpm = st.target_bpm, key = st.target_key, slots = slots, mode = st.mode,
    template = st.template }
  if ss_search_active(st) then
    h.search_chips = { table.unpack(st.search_chips) }
    h.search_mode = st.search_mode
  end
  if st.mode == "arrange" and ss_arr_valid(st.arr) then
    h.arr = st.arr
  end
  return h
end

-- Saved arrangement looks usable (from the settings file or history).
function ss_arr_valid(arr)
  if type(arr) ~= "table" or type(arr.sections) ~= "table" or #arr.sections == 0 then
    return false
  end
  for _, sec in ipairs(arr.sections) do
    if type(sec) ~= "table" or not SS_SECTION_TYPES[sec.type] or type(sec.bars) ~= "number"
        or type(sec.start) ~= "number" or type(sec.parts) ~= "table" then
      return false
    end
  end
  return true
end

function ss_snapshot_sig(h)
  local parts = { tostring(h.key), string.format("%.2f", tonumber(h.bpm) or 0), tostring(h.mode),
    tostring(h.template) }
  for _, s in ipairs(h.slots or {}) do parts[#parts + 1] = tostring(s.role) .. "=" .. tostring(s.path) end
  return table.concat(parts, "|")
end

-- Add the current starter to history (liked = LIKE). Unliked entries past
-- SS_HISTORY_MAX drop off the end; liked ones stay.
function ss_history_push(st, liked)
  local h = ss_snapshot(st)
  if not h then
    return nil
  end
  local sig = ss_snapshot_sig(h)
  for i, old in ipairs(st.history) do
    if ss_snapshot_sig(old) == sig then
      table.remove(st.history, i)
      h.liked = old.liked
      break
    end
  end
  if liked then
    h.liked = true
  end
  table.insert(st.history, 1, h)
  local unliked = 0
  for i = 1, #st.history do
    if not st.history[i].liked then unliked = unliked + 1 end
  end
  for i = #st.history, 1, -1 do
    if unliked <= SS_HISTORY_MAX then break end
    if not st.history[i].liked then
      table.remove(st.history, i)
      unliked = unliked - 1
    end
  end
  ss_save()
  return h
end

function ss_history_recall(st, h)
  st.slots = {}
  for _, hs in ipairs(h.slots or {}) do
    if SS_ROLE[hs.role] then
      local slot = ss_new_slot(st, hs.role)
      for k, v in pairs(hs) do slot[k] = v end
      slot.recent = { slot.path }
      st.slots[#st.slots + 1] = slot
    end
  end
  st.target_bpm = tonumber(h.bpm) or st.target_bpm
  st.target_key = ss_norm_key(h.key)
  st.key_auto = false
  if h.mode == "arrange" or h.mode == "loop" then
    st.mode = h.mode
  end
  if SS_TEMPLATE[h.template] then
    st.template = h.template
  end
  if type(h.search_chips) == "table" then
    st.search_chips = { table.unpack(h.search_chips) }
    st.search_mode = (h.search_mode == "all") and "all" or "any"
    st._search_count = nil
  end
  if ss_arr_valid(h.arr) then
    st.arr = h.arr
  end
  ss_retarget_all(st)
  ss_save()
end

function ss_retarget_all(st)
  for _, slot in ipairs(st.slots) do
    ss_slot_retarget(slot, st.target_bpm, st.target_key)
  end
end

function ss_project_bpm()
  local bpm = r.Master_GetTempo and tonumber(r.Master_GetTempo()) or nil
  if not bpm or bpm <= 0 then
    bpm = 120
  end
  return bpm
end

-- Loops in scope: the whole library, or what the map shows now.
-- --- Search chips: rolls pick only loops matching them ------------------------

function ss_search_active(st)
  return type(st.search_chips) == "table" and #st.search_chips > 0
end

-- One query: every word in the name, folder path or tags (case-insensitive).
function ss_query_matches(s, q)
  local any = false
  for w in tostring(q or ""):lower():gmatch("%S+") do
    any = true
    local hit = sample_matches_filter_text and sample_matches_filter_text(s, w)
    if not hit then
      for _, t in ipairs(type(s.tags) == "table" and s.tags or {}) do
        if tostring(t):lower():find(w, 1, true) then hit = true break end
      end
    end
    if not hit then return false end
  end
  return any
end

-- The chips together: ANY (default) or ALL of them.
function ss_search_match(st, s)
  if not ss_search_active(st) then return true end
  local all = st.search_mode == "all"
  for _, q in ipairs(st.search_chips) do
    local m = ss_query_matches(s, q)
    if m and not all then return true end
    if not m and all then return false end
  end
  return all
end

-- Add / remove chips (Enter / x or Backspace on an empty field).
function ss_search_add(st, q)
  q = tostring(q or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then return false end
  st.search_chips = st.search_chips or {}
  for _, c in ipairs(st.search_chips) do
    if c:lower() == q:lower() then return false end
  end
  st.search_chips[#st.search_chips + 1] = q
  st._search_count = nil
  ss_save()
  return true
end

function ss_search_remove(st, i)
  if not (st.search_chips and st.search_chips[i]) then return false end
  table.remove(st.search_chips, i)
  st._search_count = nil
  ss_save()
  return true
end

-- Loops in scope matching the search, cached until chips / scope / library change.
function ss_search_count(st)
  local sig = table.concat(st.search_chips or {}, "\1") .. "|" .. tostring(st.search_mode) .. "|" .. tostring(st.scope)
    .. "|" .. tostring(#(state.samples or {}))
  if st._search_count and st._search_count_sig == sig then
    return st._search_count
  end
  st._search_count = #ss_loop_pool(st)
  st._search_count_sig = sig
  return st._search_count
end

function ss_loop_pool(st)
  local list = state.samples or {}
  if st.scope == "map" and map_cache and rebuild_map_filtered_cache then
    pcall(function()
      if map_cache.filter_key ~= compute_map_filter_key() or not map_cache.filtered then
        rebuild_map_filtered_cache()
      end
    end)
    if map_cache.filtered then
      list = map_cache.filtered
    end
  end
  local out = {}
  for i = 1, #list do
    local s = list[i]
    if ss_is_loop(s) and not (sample_scan_folder_unavailable and sample_scan_folder_unavailable(s))
        and ss_search_match(st, s) then
      out[#out + 1] = s
    end
  end
  return out
end

local function ss_number_slots(st)
  for i, slot in ipairs(st.slots) do slot.order = i end
end

-- Button actions. which: "unlocked", "batch" or a slot.
function ss_do_reroll(which)
  local st = ss_state()
  st.target_bpm = st.target_bpm or ss_project_bpm()
  ss_number_slots(st)
  local pool = ss_loop_pool(st)
  if #pool == 0 then
    if ss_search_active(st) then
      for _, slot in ipairs(st.slots) do
        if type(which) ~= "table" and not slot.locked or slot == which then slot.no_match = true end
      end
      sm_notify("Song Starter: no loops match the search.", "warn")
      return 0
    end
    sm_notify(st.scope == "map" and "Song Starter: no loops in the current map view." or
      "Song Starter: no loops in the library yet (loops are files tagged Loop).", "warn")
    return 0
  end
  local n = ss_reroll(st, pool, which)
  if type(which) ~= "table" then
    ss_retarget_all(st)
    ss_history_push(st, false)
  end
  local empty = {}
  for _, slot in ipairs(st.slots) do
    if (not slot.path or slot.no_match) and (type(which) ~= "table" or slot == which) then
      empty[#empty + 1] = SS_ROLE[slot.role] and SS_ROLE[slot.role].label or slot.role
    end
  end
  if #empty > 0 then
    sm_notify("Song Starter: no matching loops for " .. table.concat(empty, ", ") .. ".", "warn")
  end
  ss_preview_resync(type(which) == "table" and which or nil)
  ss_save()
  return n
end

---------------------------------------------------------------------------
-- Folder browsing: the other files next to a slot's loop
---------------------------------------------------------------------------

function ss_path_dir(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$")
end

-- Candidate entry for any file, fitting or not: the relaxed (Chaos) limits
-- first; failing those, an entry with its own tempo (or none: rate 1) and
-- fit -1 so it sorts after everything that fits.
function ss_candidate_any(s, role_key, target_bpm, target_key)
  local c = ss_eval_candidate(s, role_key, target_bpm, target_key, ss_chaos_params(1))
  if c then
    c.fit = c.score
    return c
  end
  local bpm, est, key = ss_sample_tempo_key(s, target_bpm)
  local rate, mult = 1.0, 1
  if bpm then
    rate, mult = ss_stretch(bpm, target_bpm, true)
  end
  local role = SS_ROLE[role_key]
  local shift = 0
  if role and role.pitched and key and target_key then
    shift = ss_pitch_shift(key, target_key) or 0
  end
  return { sample = s, path = s.path, role = role_key, bpm = bpm or target_bpm, est = est or not bpm, key = key,
    rate = rate, mult = mult, shift = shift, strength = 0, score = -1, fit = -1 }
end

-- Library samples in dir, plus audio files there the library hasn't scanned
-- (bare tables: path, name, unscanned = true).
function ss_folder_files(dir)
  local out, seen = {}, {}
  if not dir then
    return out
  end
  for _, s in ipairs(state.samples or {}) do
    if s.path and ss_path_dir(s.path) == dir and not seen[s.path] then
      seen[s.path] = true
      out[#out + 1] = s
    end
  end
  if r.EnumerateFiles then
    local i = 0
    while i < 4000 do
      local ok, f = pcall(r.EnumerateFiles, dir, i)
      if not ok or not f or f == "" then break end
      local ext = (f:match("(%.[^.]+)$") or ""):lower()
      local p = dir .. "/" .. f
      if AUDIO_EXTS and AUDIO_EXTS[ext] and not seen[p] then
        seen[p] = true
        out[#out + 1] = { path = p, name = f, unscanned = true }
      end
      i = i + 1
    end
  end
  return out
end

-- Every file in the slot's folder as candidates, best fit first (loops before
-- one-shots, then by fit, then by name).
function ss_folder_ranked(st, slot)
  local dir = ss_path_dir(slot.path)
  local out = {}
  for _, s in ipairs(ss_folder_files(dir)) do
    local c = ss_candidate_any(s, slot.role, st.target_bpm or 120, st.target_key)
    c.loop = ss_is_loop(s) or (s.unscanned and detect_loop_or_oneshot
      and detect_loop_or_oneshot(s.path, dir, nil, nil) == "loop") or false
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    if a.loop ~= b.loop then return a.loop end
    if math.abs(a.fit - b.fit) > 1e-9 then return a.fit > b.fit end
    return tostring(a.path) < tostring(b.path)
  end)
  return out, dir
end

-- Stepping list for ◀ / ▶: the current loop first, then the folder's other
-- loops by fit. Rebuilt when the slot's loop changed by other means.
function ss_folder_nav(st, slot)
  local nav = slot.folder_nav
  if nav and nav.paths[nav.pos] == slot.path then
    return nav
  end
  local ranked = ss_folder_ranked(st, slot)
  local paths = { slot.path }
  for _, c in ipairs(ranked) do
    if c.loop and c.path ~= slot.path then paths[#paths + 1] = c.path end
  end
  nav = { paths = paths, pos = 1 }
  slot.folder_nav = nav
  return nav
end

-- Put file `s` (library sample or bare table) into the slot; locks stay.
function ss_slot_swap_to(st, slot, s)
  if s.unscanned and not s.duration and r.PCM_Source_CreateFromFile then
    local src = r.PCM_Source_CreateFromFile(s.path)
    if src then
      s.duration = tonumber((r.GetMediaSourceLength(src)))
      if r.PCM_Source_Destroy then r.PCM_Source_Destroy(src) end
    end
  end
  local c = ss_candidate_any(s, slot.role, st.target_bpm or 120, st.target_key)
  local nav = slot.folder_nav
  ss_slot_take(slot, c)
  slot.dur = tonumber(s.duration) or slot.dur
  slot.relaxed = nil
  if nav then
    for i, p in ipairs(nav.paths) do
      if p == s.path then nav.pos = i end
    end
  end
  ss_preview_resync(slot)
  ss_save()
end

-- ◀ (dir -1) / ▶ (dir 1) through the folder, wrapping. -> new position, count.
function ss_folder_step(st, slot, dir)
  if not slot.path then
    return nil
  end
  local nav = ss_folder_nav(st, slot)
  local n = #nav.paths
  if n < 2 then
    sm_notify("No other loops in this folder.", "warn")
    return nav.pos, n
  end
  local pos = ((nav.pos - 1 + dir) % n) + 1
  local path = nav.paths[pos]
  local s = find_sample_by_path and find_sample_by_path(path)
  if not s then
    for _, f in ipairs(ss_folder_files(ss_path_dir(path))) do
      if f.path == path then s = f end
    end
  end
  if s then
    nav.pos = pos
    ss_slot_swap_to(st, slot, s)
    nav.pos = pos
  end
  return pos, n
end

---------------------------------------------------------------------------
-- Drag and drop: samples / files in, loops out to the arrange
---------------------------------------------------------------------------

-- Role a dropped file most looks like (tags, name and folder words).
function ss_role_guess(s)
  local best, best_v = "texture", 0
  local scores = ss_role_scores(s)
  for _, role in ipairs(SS_ROLES) do
    local v = scores[role.key] or 0
    if v > best_v then best, best_v = role.key, v end
  end
  return best
end

-- Library sample for path, or a bare table for a file the library hasn't got.
function ss_sample_for_path(path)
  local s = find_sample_by_path and find_sample_by_path(path)
  if s then return s end
  return { path = path, name = tostring(path):match("([^/\\]+)$") or path, unscanned = true }
end

-- Drop files: the first into `slot` (nil = a new slot), the rest into the
-- following rows, past the end into new slots with a guessed role. -> count.
function ss_drop_files(st, paths, slot)
  local start = nil
  for i, s in ipairs(st.slots) do
    if s == slot then start = i end
  end
  local n = 0
  for k, p in ipairs(paths) do
    local s = ss_sample_for_path(p)
    local target = start and st.slots[start + k - 1] or nil
    if not target then
      target = ss_new_slot(st, ss_role_guess(s))
      st.slots[#st.slots + 1] = target
    end
    ss_slot_swap_to(st, target, s)
    n = n + 1
  end
  return n
end

-- Audio paths in the OS drop payload (Finder / Explorer).
function ss_payload_audio_files(count)
  local out = {}
  for i = 0, (count or 0) - 1 do
    local ok, f = r.ImGui_GetDragDropPayloadFile(ctx, i)
    local ext = type(f) == "string" and (f:match("(%.[^.]+)$") or ""):lower() or ""
    if ok and AUDIO_EXTS and AUDIO_EXTS[ext] then
      out[#out + 1] = f
    end
  end
  return out
end

-- Make the last item a target for OS file drops. -> true while files hover it.
function ss_os_drop_target(st, slot)
  if not (r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayloadFiles) then
    return false
  end
  if not r.ImGui_BeginDragDropTarget(ctx) then
    return false
  end
  local peek = 0
  if r.ImGui_DragDropFlags_AcceptBeforeDelivery then peek = peek | r.ImGui_DragDropFlags_AcceptBeforeDelivery() end
  if r.ImGui_DragDropFlags_AcceptNoDrawDefaultRect then peek = peek | r.ImGui_DragDropFlags_AcceptNoDrawDefaultRect() end
  local hovering, count = r.ImGui_AcceptDragDropPayloadFiles(ctx, peek)
  if hovering then
    local delivered, dcount = r.ImGui_AcceptDragDropPayloadFiles(ctx)
    if delivered then
      local files = ss_payload_audio_files(dcount or count)
      if #files > 0 then
        ss_drop_files(st, files, slot)
      end
    end
  end
  r.ImGui_EndDragDropTarget(ctx)
  return hovering and true or false
end

-- Clear Sample Map's own sample drag (map / explorer / waveform) after we took it.
function ss_clear_sample_drag()
  if remove_provisional_drop then remove_provisional_drop() end
  if clear_drag_tooltip then clear_drag_tooltip() end
  state.pending_waveform_drop = nil
  state.waveform_drag_armed = nil
  state.last_mouse_time_pos = nil
  state.last_mouse_track = nil
  state.seq_drop_target_idx = nil
  state.seq_candidate_drop = nil
  state.seq_drum_drop = nil
  state.seq_timeline_drop_track_idx = nil
  state.seq_timeline_drop_time = nil
  state.is_left_dragging = false
  state.last_dragged_sample_path = nil
  state.map_press_x = nil
  state.map_press_y = nil
  state.map_press_pending = false
  state.map_audition_rearm = false
  if seq_clear_candidate_drag_state then seq_clear_candidate_drag_state() end
end

-- A Sample Map drag released over a row (or the add zone): take it.
-- Runs before Sample Map completes the drag later in the frame.
function ss_take_sample_drop(st)
  if not (sample_drag_active and sample_drag_active()) or SS_DRAG then
    return false
  end
  if r.ImGui_IsMouseDown(ctx, 0) then
    return false
  end
  local target_id, new = st._drop_hover_id, st._drop_new_hover
  if not target_id and not new then
    return false
  end
  local sample = get_active_dragged_sample and get_active_dragged_sample()
  if not sample or not sample.path or sample.is_layering_mix then
    return false
  end
  local slot
  for _, s in ipairs(st.slots) do
    if s.id == target_id then slot = s end
  end
  ss_drop_files(st, { sample.path }, slot)
  ss_clear_sample_drag()
  return true
end

-- --- Drag a row's loop out into the arrange ---------------------------------

SS_DRAG = nil -- { slot_id, raw, sample = { path, name, duration } }

-- Length of the item a drag-out inserts: the bar setting at the target tempo
-- (raw: the file's own length).
function ss_drag_item_len(st, slot, raw)
  if raw then
    return tonumber(slot.dur) or 1.0
  end
  return (st.bars or 8) * 240.0 / (st.target_bpm or 120)
end

function ss_begin_drag_out(st, slot, raw)
  if SS_DRAG or not slot.path then
    return false
  end
  SS_DRAG = { slot_id = slot.id, raw = raw and true or false,
    sample = { path = slot.path, name = slot.name, duration = ss_drag_item_len(st, slot, raw) } }
  slot._drag_press = true
  if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
  end
  return true
end

-- Insert the slot's loop on `track` at `time`: the slot's stretch (playrate,
-- preserve pitch), pitch, volume and loop source, the bar setting long; raw =
-- the plain file. -> item.
function ss_insert_slot_item(st, slot, time, track, raw)
  local item = r.AddMediaItemToTrack(track)
  if not item then return nil end
  local take = r.AddTakeToMediaItem(item)
  local src = r.PCM_Source_CreateFromFile(slot.path)
  if take and src then
    r.SetMediaItemTake_Source(take, src)
    if not raw then
      r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", tonumber(slot.rate) or 1.0)
      r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
      r.SetMediaItemTakeInfo_Value(take, "D_PITCH", tonumber(slot.shift) or 0)
      r.SetMediaItemTakeInfo_Value(take, "D_VOL", tonumber(slot.vol) or 1.0)
    end
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", slot.name or "", true)
  end
  r.SetMediaItemInfo_Value(item, "D_POSITION", time)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", ss_drag_item_len(st, slot, raw))
  r.SetMediaItemInfo_Value(item, "B_LOOPSRC", raw and 0 or 1)
  ss_rebuild_peaks({ item })
  return item
end

-- Each frame while a drag-out runs: REAPER's own drop preview under the
-- mouse; on release, insert at the previewed track / time (snapped like
-- Sample Map's drops). Escape cancels.
function ss_drag_out_update(st)
  local d = SS_DRAG
  if not d then return nil end
  local slot
  for _, s in ipairs(st.slots) do
    if s.id == d.slot_id then slot = s end
  end
  if not slot or not slot.path then
    SS_DRAG = nil
    if remove_provisional_drop then remove_provisional_drop() end
    return nil
  end
  if r.ImGui_IsMouseDown(ctx, 0) then
    if r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      SS_DRAG = nil
      slot._drag_press = nil
      if remove_provisional_drop then remove_provisional_drop() end
      return "cancel"
    end
    if update_provisional_drop then update_provisional_drop(d.sample) end
    return "drag"
  end
  SS_DRAG = nil
  local time, track
  local p = state.provisional_drop
  if p and p.item and r.ValidatePtr(p.item, "MediaItem*") then
    time, track = p.time, p.track
  end
  if not time and get_drop_position then
    local t, tr = get_drop_position()
    if t then time, track = maybe_snap_drop_time and maybe_snap_drop_time(t) or t, tr end
  end
  if remove_provisional_drop then remove_provisional_drop() end
  if clear_drag_tooltip then clear_drag_tooltip() end
  if not (time and track) then
    return "none"
  end
  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  local item = ss_insert_slot_item(st, slot, time, track, d.raw)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock2(0, "Song Starter: insert loop", -1)
  return item and "inserted" or "none"
end

---------------------------------------------------------------------------
-- Preview: all audible slots looped together through SWS CF_Preview
---------------------------------------------------------------------------

SS_PLAY = nil -- { t0, voices = { [slot.id] = { obj, src } } }

function ss_preview_available()
  return r.CF_CreatePreview and r.CF_Preview_SetValue and r.CF_Preview_Play and true or false
end

-- Arrange preview: bar position `elapsed` seconds in, wrapping at the end.
function ss_arr_bar_at(st, elapsed)
  local arr = st.arr
  if not arr or (arr.total or 0) <= 0 then
    return 0
  end
  local bar = math.max(0, elapsed or 0) * (st.target_bpm or 120) / 240.0
  return bar % arr.total
end

local function ss_voice_volume(st, slot, elapsed)
  if not ss_slot_audible(st.slots, slot) then
    return 0.0
  end
  local g = (state.preview_volume or 1.0) * (tonumber(slot.vol) or 1.0)
  if st.mode == "arrange" and ss_arr_valid(st.arr) then
    g = g * ss_arr_gain(st.arr, slot.role, ss_arr_bar_at(st, elapsed))
  end
  return g
end

local function ss_voice_stop(v)
  if not v then return end
  if v.obj and r.CF_Preview_Stop then pcall(r.CF_Preview_Stop, v.obj) end
  if v.src and r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, v.src) end
  v.obj, v.src = nil, nil
end

-- Prepared (not yet playing) voice for slot, entering `elapsed` seconds in.
local function ss_voice_make(st, slot, elapsed)
  if not slot.path then return nil end
  local src = r.PCM_Source_CreateFromFile(slot.path)
  if not src then return nil end
  if (not slot.dur or slot.dur <= 0) and r.GetMediaSourceLength then
    slot.dur = tonumber((r.GetMediaSourceLength(src))) or slot.dur
  end
  local obj = r.CF_CreatePreview(src)
  if not obj then
    if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, src) end
    return nil
  end
  -- B_LOOP twice: SWS's setLoop passes the *old* loop state to its source,
  -- so one call leaves the source "not looping"; its first block at time 0
  -- then counts as a wrap and CF_Preview_GetPeak reads 0 from then on
  -- (only some voices metered). The second call sets it for real.
  r.CF_Preview_SetValue(obj, "B_LOOP", 1)
  r.CF_Preview_SetValue(obj, "B_LOOP", 1)
  r.CF_Preview_SetValue(obj, "B_PPITCH", 1)
  r.CF_Preview_SetValue(obj, "D_PLAYRATE", tonumber(slot.rate) or 1.0)
  r.CF_Preview_SetValue(obj, "D_PITCH", tonumber(slot.shift) or 0)
  r.CF_Preview_SetValue(obj, "D_VOLUME", ss_voice_volume(st, slot, elapsed or 0))
  local pos = ss_loop_phase(slot, elapsed or 0, st.target_bpm)
  if pos > 0 then
    r.CF_Preview_SetValue(obj, "D_POSITION", pos)
  end
  return { obj = obj, src = src, path = slot.path }
end

function ss_preview_stop()
  local play = SS_PLAY
  SS_PLAY = nil
  if play then
    for _, v in pairs(play.voices) do ss_voice_stop(v) end
  end
end

-- start_bar: arrange mode starts there (loops join at that bar's phase).
function ss_preview_play(start_bar)
  local st = ss_state()
  if not ss_preview_available() then
    sm_notify("Song Starter preview needs the SWS extension (CF_Preview).", "warn")
    return false
  end
  ss_preview_stop()
  if stop_preview then
    stop_preview() -- the single-sample preview; also stops stray CF previews
    state.preview_paused = false
  end
  local voices, order = {}, {}
  local into = (tonumber(start_bar) or 0) * 240.0 / (st.target_bpm or 120)
  for _, slot in ipairs(st.slots) do
    local v = ss_voice_make(st, slot, into)
    if v then
      voices[slot.id] = v
      order[#order + 1] = v
    end
  end
  if #order == 0 then
    sm_notify("Song Starter: nothing to play yet. Click New Batch.", "warn")
    return false
  end
  -- Start them back to back in one go so they line up.
  for _, v in ipairs(order) do
    r.CF_Preview_Play(v.obj)
  end
  SS_PLAY = { t0 = r.time_precise() - into, voices = voices,
    transport = r.GetPlayState and (r.GetPlayState() & 1) == 1 or false }
  return true
end

function ss_preview_playing()
  return SS_PLAY ~= nil
end

-- After slots change: swap the changed slot in place (at the others' phase),
-- or restart everything when no single slot is named.
function ss_preview_resync(slot)
  if not SS_PLAY then return end
  local st = ss_state()
  if not slot then
    ss_preview_play()
    return
  end
  local old = SS_PLAY.voices[slot.id]
  ss_voice_stop(old)
  SS_PLAY.voices[slot.id] = nil
  local v = ss_voice_make(st, slot, r.time_precise() - SS_PLAY.t0)
  if v then
    r.CF_Preview_Play(v.obj)
    SS_PLAY.voices[slot.id] = v
  end
end

-- Volumes / pitch follow the controls each frame; stops when something else
-- (a normal preview, transport) stopped our voices.
function ss_preview_update()
  local play = SS_PLAY
  if not play then return end
  local st = ss_state()
  local transport = r.GetPlayState and (r.GetPlayState() & 1) == 1 or false
  if transport and not play.transport then
    -- REAPER started playing: stop, like the normal preview does.
    ss_preview_stop()
    return
  end
  play.transport = transport
  local alive = false
  local elapsed = r.time_precise() - play.t0
  for _, slot in ipairs(st.slots) do
    local v = play.voices[slot.id]
    if v and v.obj then
      local ok_get, ret = pcall(r.CF_Preview_GetValue, v.obj, "D_POSITION")
      if r.CF_Preview_GetValue and ok_get and ret ~= false then
        alive = true
      end
      ss_meter_read(v, r.time_precise())
      local vol = ss_voice_volume(st, slot, elapsed)
      if v.vol ~= vol then
        pcall(r.CF_Preview_SetValue, v.obj, "D_VOLUME", vol)
        v.vol = vol
      end
      local shift = tonumber(slot.shift) or 0
      if v.shift ~= shift then
        pcall(r.CF_Preview_SetValue, v.obj, "D_PITCH", shift)
        v.shift = shift
      end
    end
  end
  if not alive and r.CF_Preview_GetValue then
    -- CF_Preview_StopAll (any other preview) ended ours.
    for _, v in pairs(play.voices) do
      if v.src and r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, v.src) end
    end
    SS_PLAY = nil
  end
end

---------------------------------------------------------------------------
-- Add to project
---------------------------------------------------------------------------

SS_EDGE_FADE = 0.008 -- seconds, item edges in arrangements
SS_CMD_REBUILD_PEAKS = 40441 -- Peaks: Rebuild peaks for selected items

-- Rebuild peaks for exactly `items` (REAPER builds them in the background),
-- then put the item selection back as it was.
function ss_rebuild_peaks(items)
  if #items == 0 then
    return
  end
  local prev = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    prev[#prev + 1] = r.GetSelectedMediaItem(0, i)
  end
  r.SelectAllMediaItems(0, false)
  for _, item in ipairs(items) do
    r.SetMediaItemSelected(item, true)
  end
  r.Main_OnCommand(SS_CMD_REBUILD_PEAKS, 0)
  r.SelectAllMediaItems(0, false)
  for _, item in ipairs(prev) do
    if r.ValidatePtr2(0, item, "MediaItem*") then
      r.SetMediaItemSelected(item, true)
    end
  end
end

-- Native region colour from 0xRRGGBB.
local function ss_native_color(rgb)
  local rr, gg, bb = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
  local c = r.ColorToNative and r.ColorToNative(rr, gg, bb) or ((bb << 16) | (gg << 8) | rr)
  return c | 0x1000000
end

-- Items of an arrangement: one per section and part that plays, for each
-- audible slot. -> { { slot, sec, t0, t1 (seconds from the start), offs
-- (source seconds at t0, so the loop stays on the bar grid), rise } }.
function ss_arrangement_items(st, arr, bpm)
  local bar_s = 240.0 / bpm
  local out = {}
  for _, slot in ipairs(st.slots) do
    if ss_slot_audible(st.slots, slot) then
      for _, sec in ipairs(arr.sections) do
        local part = sec.parts[slot.role]
        if part then
          local t0 = (sec.start + part.from) * bar_s
          local t1 = (sec.start + part.to) * bar_s
          out[#out + 1] = { slot = slot, sec = sec, part = part, t0 = t0, t1 = t1,
            offs = ss_loop_phase(slot, t0, bpm), rise = part.rise }
        end
      end
    end
  end
  return out
end

-- Arrange mode Add to project: folder + a track per slot that plays, an item
-- per section, regions per section. One undo step.
-- opts (both Add paths): pos = start time (default edit cursor), index =
-- track index to insert at (default above the selected track, else the end),
-- folder = false for plain tracks without the folder track.
function ss_add_arrangement(opts)
  opts = opts or {}
  local st = ss_state()
  local arr = ss_arrangement(st)
  local bpm = st.target_bpm or ss_project_bpm()
  local items = ss_arrangement_items(st, arr, bpm)
  if #items == 0 then
    sm_notify("Song Starter: nothing to arrange (all slots empty or muted).", "warn")
    return false
  end
  local list, by_slot = {}, {}
  for _, it in ipairs(items) do
    if not by_slot[it.slot] then
      by_slot[it.slot] = {}
      list[#list + 1] = it.slot
    end
    local t = by_slot[it.slot]
    t[#t + 1] = it
  end
  local proj = 0
  local base = opts.pos or r.GetCursorPosition()
  local key = st.target_key
  local tmpl = SS_TEMPLATE[arr.template or st.template]
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  if st.set_tempo and r.SetCurrentBPM then
    r.SetCurrentBPM(proj, bpm, true)
  end
  local idx = r.CountTracks(proj)
  local sel = r.GetSelectedTrack(proj, 0)
  if opts.index then
    idx = math.max(0, math.min(r.CountTracks(proj), opts.index))
  elseif sel then
    idx = math.max(0, math.floor(r.GetMediaTrackInfo_Value(sel, "IP_TRACKNUMBER") + 0.5) - 1)
  end
  local use_folder = opts.folder ~= false
  local folder
  if use_folder then
    r.InsertTrackAtIndex(idx, true)
    folder = r.GetTrack(proj, idx)
  else
    idx = idx - 1 -- children go from idx on
  end
  local title = string.format("Song Starter %s%.0f%s", key and (key .. " ") or "", bpm,
    tmpl and (" " .. tmpl.label) or "")
  if folder then
    r.GetSetMediaTrackInfo_String(folder, "P_NAME", title, true)
    r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  end
  local last
  local added = {}
  for i, slot in ipairs(list) do
    r.InsertTrackAtIndex(idx + i, true)
    local tr = r.GetTrack(proj, idx + i)
    local role = SS_ROLE[slot.role]
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", role and role.label or slot.role, true)
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    for _, it in ipairs(by_slot[slot]) do
      local item = r.AddMediaItemToTrack(tr)
      added[#added + 1] = item
      local take = r.AddTakeToMediaItem(item)
      local src = r.PCM_Source_CreateFromFile(slot.path)
      local len = it.t1 - it.t0
      if take and src then
        r.SetMediaItemTake_Source(take, src)
        r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", tonumber(slot.rate) or 1.0)
        r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
        r.SetMediaItemTakeInfo_Value(take, "D_PITCH", tonumber(slot.shift) or 0)
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", (tonumber(slot.vol) or 1.0) * (it.part.vol or 1.0))
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", it.offs)
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", (slot.name or "") .. " - " .. it.sec.name, true)
      end
      r.SetMediaItemInfo_Value(item, "D_POSITION", base + it.t0)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", len)
      r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
      if it.rise then
        -- Build: the part rises from silence across the item (fast-start curve).
        r.SetMediaItemInfo_Value(item, "D_FADEINLEN", len)
        r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 1)
      else
        r.SetMediaItemInfo_Value(item, "D_FADEINLEN", SS_EDGE_FADE)
      end
      r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", SS_EDGE_FADE)
    end
    last = tr
  end
  if folder then
    r.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", -1)
  end
  local bar_s = 240.0 / bpm
  for _, sec in ipairs(arr.sections) do
    local def = SS_SECTION_TYPES[sec.type] or {}
    r.AddProjectMarker2(proj, true, base + sec.start * bar_s, base + (sec.start + sec.bars) * bar_s, sec.name, -1,
      ss_native_color(def.color or 0x808080))
  end
  ss_rebuild_peaks(added)
  r.PreventUIRefresh(-1)
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  r.UpdateArrange()
  r.Undo_EndBlock2(proj, "Song Starter: arrange", -1)
  ss_history_push(st, false)
  sm_notify(string.format("Arranged %s: %d tracks, %d sections, %d bars.", title, #list, #arr.sections, arr.total))
  return true
end

function ss_add_to_project(opts)
  opts = opts or {}
  local st = ss_state()
  if st.mode == "arrange" then
    return ss_add_arrangement(opts)
  end
  local list = {}
  for _, slot in ipairs(st.slots) do
    if ss_slot_audible(st.slots, slot) then list[#list + 1] = slot end
  end
  if #list == 0 then
    sm_notify("Song Starter: nothing to add (all slots empty or muted).", "warn")
    return false
  end
  local bpm = st.target_bpm or ss_project_bpm()
  local key = st.target_key
  local proj = 0
  local pos = opts.pos or r.GetCursorPosition()
  local length = (st.bars or 8) * 240.0 / bpm
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  if st.set_tempo and r.SetCurrentBPM then
    r.SetCurrentBPM(proj, bpm, true)
  end
  local idx = r.CountTracks(proj)
  local sel = r.GetSelectedTrack(proj, 0)
  if opts.index then
    idx = math.max(0, math.min(r.CountTracks(proj), opts.index))
  elseif sel then
    idx = math.max(0, math.floor(r.GetMediaTrackInfo_Value(sel, "IP_TRACKNUMBER") + 0.5) - 1)
  end
  local use_folder = opts.folder ~= false
  local folder
  if use_folder then
    r.InsertTrackAtIndex(idx, true)
    folder = r.GetTrack(proj, idx)
  else
    idx = idx - 1 -- children go from idx on
  end
  local title = string.format("Song Starter %s%.0f", key and (key .. " ") or "", bpm)
  if folder then
    r.GetSetMediaTrackInfo_String(folder, "P_NAME", title, true)
    r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  end
  local last
  local added = {}
  for i, slot in ipairs(list) do
    r.InsertTrackAtIndex(idx + i, true)
    local tr = r.GetTrack(proj, idx + i)
    local role = SS_ROLE[slot.role]
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", role and role.label or slot.role, true)
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    local item = r.AddMediaItemToTrack(tr)
    added[#added + 1] = item
    local take = r.AddTakeToMediaItem(item)
    local src = r.PCM_Source_CreateFromFile(slot.path)
    if take and src then
      r.SetMediaItemTake_Source(take, src)
      r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", tonumber(slot.rate) or 1.0)
      r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
      r.SetMediaItemTakeInfo_Value(take, "D_PITCH", tonumber(slot.shift) or 0)
      r.SetMediaItemTakeInfo_Value(take, "D_VOL", tonumber(slot.vol) or 1.0)
      r.GetSetMediaItemTakeInfo_String(take, "P_NAME", slot.name or "", true)
    end
    r.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
    last = tr
  end
  if folder then
    r.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", -1)
  end
  ss_rebuild_peaks(added)
  r.PreventUIRefresh(-1)
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  r.UpdateArrange()
  r.Undo_EndBlock2(proj, "Sample Map: add Song Starter", -1)
  ss_history_push(st, false)
  sm_notify(string.format("Added %s: %d track%s, %d bars.", title, #list, #list == 1 and "" or "s", st.bars or 8))
  return true
end

---------------------------------------------------------------------------
-- Drag ADD TO PROJECT into the arrange
---------------------------------------------------------------------------

SS_ADD_DRAG = nil -- { target = { kind = "track" | "folder", time, index, track } }
SS_NEW_FOLDER_H = 26 -- px: the NEW FOLDER strip along the top of the arrange

-- Start of the bar nearest t.
function ss_snap_bar(t)
  if not (r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime) then
    return t
  end
  local beats, measure, cml = r.TimeMap2_timeToBeats(0, t)
  beats, measure, cml = tonumber(beats) or 0, tonumber(measure) or 0, tonumber(cml) or 4
  if beats >= cml * 0.5 then
    measure = measure + 1
  end
  return r.TimeMap2_beatsToTime(0, 0, measure)
end

-- Tracks the starter adds (audible slots that will get items).
function ss_add_track_count(st)
  local n = 0
  if st.mode == "arrange" and ss_arr_valid(st.arr) then
    local seen = {}
    for _, it in ipairs(ss_arrangement_items(st, st.arr, st.target_bpm or 120)) do
      if not seen[it.slot] then seen[it.slot] = true; n = n + 1 end
    end
    return n
  end
  for _, slot in ipairs(st.slots) do
    if ss_slot_audible(st.slots, slot) then n = n + 1 end
  end
  return n
end

-- Length of what Add puts in, in bars.
function ss_add_bars(st)
  if st.mode == "arrange" and ss_arr_valid(st.arr) then
    return st.arr.total
  end
  return st.bars or 8
end

-- Where a release now would put the starter: the NEW FOLDER strip (ruler, or
-- the top strip of the arrange) or a track lane (or below the last track).
-- -> { kind, time, index, track, mx_client, my_client } or nil.
function ss_add_drag_target()
  if not r.BR_GetMouseCursorContext then
    return nil
  end
  local window = r.BR_GetMouseCursorContext()
  if window ~= "arrange" and window ~= "ruler" then
    return nil
  end
  local t = r.BR_GetMouseCursorContext_Position()
  if not t or t < 0 then
    return nil
  end
  local time = ss_snap_bar(t)
  local hwnd = seq_get_arrange_hwnd and seq_get_arrange_hwnd()
  local cy = nil
  if hwnd and r.GetMousePosition and r.JS_Window_ScreenToClient then
    local mx, my = r.GetMousePosition()
    local _, y = r.JS_Window_ScreenToClient(hwnd, mx, my)
    cy = tonumber(y)
  end
  if window == "ruler" or (cy and cy < SS_NEW_FOLDER_H) then
    return { kind = "folder", time = time, index = r.CountTracks(0) }
  end
  local track = r.BR_GetMouseCursorContext_Track()
  local index = r.CountTracks(0)
  if track then
    index = math.max(0, math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") + 0.5) - 1)
  end
  return { kind = "track", time = time, index = index, track = track }
end

-- Rects (arrange client coords) for the overlay: the NEW FOLDER strip and the
-- block where the starter lands. -> list of { x0, y0, x1, y1, kind, text }.
function ss_add_drag_rects(st, target, geo, t0, t1)
  local out = {}
  local w, h = geo.view_w or 0, geo.view_h or 0
  if w <= 0 or h <= 0 or not t0 or not t1 or t1 <= t0 then
    return out
  end
  local hot_folder = target and target.kind == "folder"
  out[#out + 1] = { x0 = 0, y0 = 0, x1 = w, y1 = SS_NEW_FOLDER_H, kind = "strip", hot = hot_folder, text = "NEW FOLDER" }
  if not target then
    return out
  end
  local bpm = st.target_bpm or 120
  local bars = ss_add_bars(st)
  local len = bars * 240.0 / bpm
  local x0 = (target.time - t0) / (t1 - t0) * w
  local x1 = (target.time + len - t0) / (t1 - t0) * w
  local n = math.max(1, ss_add_track_count(st))
  local secs = math.floor(len + 0.5)
  local label = string.format("%d TRACKS · %d BARS · %d:%02d", n, bars, secs // 60, secs % 60)
  if target.kind == "folder" then
    out[#out + 1] = { x0 = x0, y0 = 0, x1 = x1, y1 = SS_NEW_FOLDER_H, kind = "block", text = label }
    return out
  end
  -- one lane per added track, using the real lane heights below the target
  local y = nil
  local ntr = r.CountTracks(0)
  local last_bottom = SS_NEW_FOLDER_H
  if ntr > 0 then
    local tr = r.GetTrack(0, ntr - 1)
    last_bottom = (r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0) + (r.GetMediaTrackInfo_Value(tr, "I_WNDH") or 28)
  end
  for i = 0, n - 1 do
    local tr = (target.index + i < ntr) and r.GetTrack(0, target.index + i) or nil
    local ly, lh
    if tr then
      ly = r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0
      lh = r.GetMediaTrackInfo_Value(tr, "I_WNDH") or 28
    else
      ly = math.max(last_bottom, y or last_bottom)
      lh = 28
    end
    y = ly + lh
    out[#out + 1] = { x0 = x0, y0 = ly, x1 = x1, y1 = ly + lh, kind = "lane", text = (i == 0) and label or nil }
  end
  return out
end

-- Called from seq_arrange_hl_flush (17_seq_arrange_overlay.lua) each frame.
function ss_arrange_overlay_add()
  local d = SS_ADD_DRAG
  if not d then
    return
  end
  local geo = seq_get_arrange_geometry and seq_get_arrange_geometry()
  if not geo or not geo.view_w then
    return
  end
  local t0, t1 = get_arrange_view_range()
  local green = seq_lice_color(0x49, 0xCC, 0x85)
  for _, rc in ipairs(ss_add_drag_rects(ss_state(), d.target, geo, t0, t1)) do
    local a = (rc.kind == "strip") and (rc.hot and 0.32 or 0.12) or 0.22
    seq_arrange_hl_add(rc.x0, rc.y0, rc.x1, rc.y1, green, a, green)
    local pend = seq_arrange_hl_pending
    if pend and rc.text then
      pend[#pend].text = rc.text
    end
  end
end

function ss_add_drag_begin()
  SS_ADD_DRAG = { target = nil }
end

function ss_add_drag_cancel()
  SS_ADD_DRAG = nil
end

-- Each frame while dragging ADD TO PROJECT: follow the target; on release
-- add there (track lane: plain tracks from that track on; NEW FOLDER: a
-- folder at the end of the project), anywhere else cancels.
-- -> "drag" | "added" | "cancel".
function ss_add_drag_update(st)
  local d = SS_ADD_DRAG
  if not d then return nil end
  if r.ImGui_IsMouseDown(ctx, 0) then
    if r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      ss_add_drag_cancel()
      return "cancel"
    end
    d.target = ss_add_drag_target()
    return "drag"
  end
  local target = ss_add_drag_target() or d.target
  SS_ADD_DRAG = nil
  if not target then
    return "cancel"
  end
  if target.kind == "folder" then
    ss_add_to_project({ pos = target.time, index = r.CountTracks(0), folder = true })
  else
    ss_add_to_project({ pos = target.time, index = target.index, folder = false })
  end
  return "added"
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function ss_toggle_window()
  local st = ss_state()
  st.open = not st.open
  if st.open then
    st.target_bpm = st.target_bpm or ss_project_bpm()
  else
    ss_preview_stop()
  end
  ss_save()
end

local function ss_text(dl, x, y, col, s)
  r.ImGui_DrawList_AddText(dl, x, y, col, s)
end

-- Small uppercase caption.
local function ss_label(text)
  r.ImGui_TextColored(ctx, SS_COL.mute, string.upper(text))
end

-- Green L ticks on the corners of a rect.
local function ss_corner_ticks(dl, x0, y0, x1, y1, col)
  local k = 6
  r.ImGui_DrawList_AddLine(dl, x0, y0, x0 + k, y0, col, 1)
  r.ImGui_DrawList_AddLine(dl, x0, y0, x0, y0 + k, col, 1)
  r.ImGui_DrawList_AddLine(dl, x1, y0, x1 - k, y0, col, 1)
  r.ImGui_DrawList_AddLine(dl, x1, y0, x1, y0 + k, col, 1)
  r.ImGui_DrawList_AddLine(dl, x0, y1, x0 + k, y1, col, 1)
  r.ImGui_DrawList_AddLine(dl, x0, y1, x0, y1 - k, col, 1)
  r.ImGui_DrawList_AddLine(dl, x1, y1, x1 - k, y1, col, 1)
  r.ImGui_DrawList_AddLine(dl, x1, y1, x1, y1 - k, col, 1)
end

-- Flat square button: hairline border, green when on. -> clicked.
local function ss_btn(id, label, w, h, on, tip)
  h = h or 22
  local tw = r.ImGui_CalcTextSize(ctx, label)
  w = w or (tw + 16)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local fill = on and SS_COL.accent_d or (active and 0xFFFFFF14 or (hovered and 0xFFFFFF0C or 0))
  if fill ~= 0 then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, fill, 0)
  end
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, on and SS_COL.accent or (hovered and SS_COL.line_hi or SS_COL.line), 0, 0, 1)
  local _, th = r.ImGui_CalcTextSize(ctx, label)
  ss_text(dl, x0 + (w - tw) * 0.5, y0 + (h - (th or 13)) * 0.5, on and SS_COL.accent or (hovered and SS_COL.text or SS_COL.dim), label)
  if tip and hovered then
    r.ImGui_SetTooltip(ctx, tip)
  end
  return clicked
end

-- Monolith line icons (1.25 px strokes), centred on cx, cy.
function ss_draw_icon(dl, kind, cx, cy, col, on)
  cx, cy = math.floor(cx) + 0.5, math.floor(cy) + 0.5
  local closed = r.ImGui_DrawFlags_Closed and r.ImGui_DrawFlags_Closed() or 1
  if kind == "roll" then
    -- circular arrow: three-quarter arc with a head at its end
    local rad = 4.5
    r.ImGui_DrawList_PathArcTo(dl, cx, cy, rad, -math.pi * 0.35, math.pi * 1.25, 14)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.25)
    local a = -math.pi * 0.35
    local ex, ey = cx + math.cos(a) * rad, cy + math.sin(a) * rad
    r.ImGui_DrawList_AddTriangleFilled(dl, ex - 3.2, ey - 1.2, ex + 1.8, ey - 2.6, ex + 0.6, ey + 2.4, col)
  elseif kind == "left" or kind == "right" then
    local d = kind == "left" and -1 or 1
    r.ImGui_DrawList_PathLineTo(dl, cx - d * 2, cy - 4)
    r.ImGui_DrawList_PathLineTo(dl, cx + d * 2, cy)
    r.ImGui_DrawList_PathLineTo(dl, cx - d * 2, cy + 4)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.25)
  elseif kind == "folder" then
    -- folder: tab on the top left, square body
    r.ImGui_DrawList_PathLineTo(dl, cx - 5.5, cy + 4)
    r.ImGui_DrawList_PathLineTo(dl, cx - 5.5, cy - 4)
    r.ImGui_DrawList_PathLineTo(dl, cx - 1.5, cy - 4)
    r.ImGui_DrawList_PathLineTo(dl, cx, cy - 2.5)
    r.ImGui_DrawList_PathLineTo(dl, cx + 5.5, cy - 2.5)
    r.ImGui_DrawList_PathLineTo(dl, cx + 5.5, cy + 4)
    r.ImGui_DrawList_PathStroke(dl, col, closed, 1.25)
  elseif kind == "lock" then
    -- padlock: body + shackle (raised and swung open when unlocked)
    r.ImGui_DrawList_AddRect(dl, cx - 4.5, cy - 0.5, cx + 4.5, cy + 5.5, col, 0, 0, 1.25)
    if on then
      r.ImGui_DrawList_AddRectFilled(dl, cx - 4.5, cy - 0.5, cx + 4.5, cy + 5.5, col, 0)
    end
    local sx, sy = cx, cy - 0.5
    if not on then sx, sy = cx + 3, cy - 2.5 end
    r.ImGui_DrawList_PathLineTo(dl, sx - 2.75, sy)
    r.ImGui_DrawList_PathArcTo(dl, sx, sy - 2.5, 2.75, math.pi, 2 * math.pi, 10)
    r.ImGui_DrawList_PathLineTo(dl, sx + 2.75, on and sy or sy + 0.5)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.25)
  end
end

-- Square icon button (same frame as ss_btn). -> clicked.
local function ss_icon_btn(id, kind, w, h, on, tip)
  local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local fill = on and SS_COL.accent_d or (active and 0xFFFFFF14 or (hovered and 0xFFFFFF0C or 0))
  if fill ~= 0 then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, fill, 0)
  end
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, on and SS_COL.accent or (hovered and SS_COL.line_hi or SS_COL.line), 0, 0, 1)
  ss_draw_icon(dl, kind, x0 + w * 0.5, y0 + h * 0.5, on and SS_COL.accent or (hovered and SS_COL.text or SS_COL.dim), on)
  if tip and hovered then
    r.ImGui_SetTooltip(ctx, tip)
  end
  return clicked
end

local function ss_push_style()
  local cols = {
    { r.ImGui_Col_WindowBg, SS_COL.bg }, { r.ImGui_Col_ChildBg, 0x00000000 }, { r.ImGui_Col_PopupBg, ui_tc(0x0A0A0AFF) },
    { r.ImGui_Col_Border, SS_COL.line }, { r.ImGui_Col_Separator, SS_COL.line },
    { r.ImGui_Col_FrameBg, SS_COL.panel }, { r.ImGui_Col_FrameBgHovered, ui_tc(0x161616FF) }, { r.ImGui_Col_FrameBgActive, ui_tc(0x1C1C1CFF) },
    { r.ImGui_Col_SliderGrab, SS_COL.accent }, { r.ImGui_Col_SliderGrabActive, ui_tc(0x6BE0A0FF) },
    { r.ImGui_Col_CheckMark, SS_COL.accent }, { r.ImGui_Col_Text, SS_COL.text }, { r.ImGui_Col_TextDisabled, SS_COL.mute },
    { r.ImGui_Col_Header, SS_COL.accent_d }, { r.ImGui_Col_HeaderHovered, 0xFFFFFF14 }, { r.ImGui_Col_HeaderActive, SS_COL.accent_m },
    { r.ImGui_Col_Button, 0x00000000 }, { r.ImGui_Col_ButtonHovered, 0xFFFFFF0C }, { r.ImGui_Col_ButtonActive, 0xFFFFFF14 },
    { r.ImGui_Col_TitleBg, SS_COL.bg }, { r.ImGui_Col_TitleBgActive, SS_COL.bg }, { r.ImGui_Col_ScrollbarBg, 0x00000000 },
    { r.ImGui_Col_ScrollbarGrab, 0xFFFFFF1F },
  }
  local nc = 0
  for _, c in ipairs(cols) do
    if c[1] then
      r.ImGui_PushStyleColor(ctx, c[1](), c[2])
      nc = nc + 1
    end
  end
  local vars = {
    { r.ImGui_StyleVar_WindowRounding, 0 }, { r.ImGui_StyleVar_ChildRounding, 0 }, { r.ImGui_StyleVar_FrameRounding, 0 },
    { r.ImGui_StyleVar_PopupRounding, 0 }, { r.ImGui_StyleVar_GrabRounding, 0 }, { r.ImGui_StyleVar_ScrollbarRounding, 0 },
    { r.ImGui_StyleVar_WindowBorderSize, 1 }, { r.ImGui_StyleVar_FrameBorderSize, 1 }, { r.ImGui_StyleVar_PopupBorderSize, 1 },
  }
  local nv = 0
  for _, v in ipairs(vars) do
    if v[1] then
      r.ImGui_PushStyleVar(ctx, v[1](), v[2])
      nv = nv + 1
    end
  end
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
    nv = nv + 1
  end
  if r.ImGui_StyleVar_ItemSpacing then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 6)
    nv = nv + 1
  end
  return nc, nv
end

local function ss_key_combo(st)
  local cur = st.key_auto and ("Auto" .. (st.target_key and (" (" .. st.target_key .. ")") or "")) or (st.target_key or "None")
  r.ImGui_SetNextItemWidth(ctx, 96)
  if r.ImGui_BeginCombo(ctx, "##ss_key", cur) then
    if r.ImGui_Selectable(ctx, "Auto (first melodic loop)", st.key_auto) then
      st.key_auto = true
      st.target_key = ss_first_melodic_key(st.slots, false)
      ss_retarget_all(st)
      ss_save()
    end
    for _, minor in ipairs({ false, true }) do
      r.ImGui_Separator(ctx)
      for pc = 0, 11 do
        local name = ss_key_name(pc, minor)
        if r.ImGui_Selectable(ctx, name .. (minor and " minor" or " major") .. "##k" .. name,
            not st.key_auto and st.target_key == name) then
          st.key_auto = false
          st.target_key = name
          ss_retarget_all(st)
          ss_save()
        end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

-- Bars in the set's cycle: the bar setting (LOOP) or the whole arrangement.
function ss_cycle_bars(st)
  if st.mode == "arrange" and ss_arr_valid(st.arr) then
    return st.arr.total
  end
  return st.bars or 8
end

-- Playback position in bars within the cycle, or nil when stopped.
function ss_cycle_bar_now(st)
  if not SS_PLAY then
    return nil
  end
  local elapsed = r.time_precise() - SS_PLAY.t0
  if st.mode == "arrange" and ss_arr_valid(st.arr) then
    return ss_arr_bar_at(st, elapsed)
  end
  return (math.max(0, elapsed) * (st.target_bpm or 120) / 240.0) % (st.bars or 8)
end

-- Cycle timeline at the top: hairline box, a tick per bar (taller every 4),
-- green playhead while previewing. -> { x0, y0, w, h, bars }.
function ss_draw_cycle_timeline(st, w)
  local bars = math.max(1, ss_cycle_bars(st))
  local h = 12
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Dummy(ctx, math.max(1, w), h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local master
  if ss_meter_available() then
    -- master meter (max of the voices) at the right end
    local mw = 64
    master = ss_master_meter()
    ss_draw_meter(dl, x0 + w - mw, y0, mw, h, master, true)
    w = w - mw - 6
  end
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, SS_COL.line, 0, 0, 1)
  local px = w / bars
  local step = bars > 64 and 4 or 1
  for b = step, bars - 1, step do
    local tx = x0 + b * px
    local tall = b % 4 == 0
    r.ImGui_DrawList_AddLine(dl, tx, y0 + (tall and 2 or 7), tx, y0 + h, tall and SS_COL.line_hi or SS_COL.line, 1)
  end
  local now = ss_cycle_bar_now(st)
  if now then
    local hx = x0 + now * px
    r.ImGui_DrawList_AddRectFilled(dl, x0 + 1, y0 + 1, hx, y0 + h - 1, SS_COL.accent_d, 0)
    r.ImGui_DrawList_AddLine(dl, hx, y0 - 2, hx, y0 + h + 2, SS_COL.accent, 1)
  end
  return { x0 = x0, y0 = y0, w = w, h = h, bars = bars, now = now, master = master }
end

-- Every loaded slot gets its own playhead while previewing.
function ss_slot_shows_own(st, slot)
  return slot.path ~= nil and ss_slot_bars(slot, st.target_bpm) ~= nil
end

-- Row playhead: translucent fill across the whole row height from its left
-- edge to the loop's position in its own length, and a 1px line at the
-- leading edge. Drawn before the row's text and buttons. Muted / silent rows
-- dimmer. -> { own, bar, frac, hx, label } while playing, else nil.
function ss_draw_slot_playhead(st, slot, dl, x0, y0, x1, y1)
  if not (SS_PLAY and SS_PLAY.voices[slot.id]) or not ss_slot_shows_own(st, slot) then
    return nil
  end
  local bar, own = ss_slot_bar_at(slot, r.time_precise() - SS_PLAY.t0, st.target_bpm)
  local frac = bar / own
  local hx = x0 + (x1 - x0) * frac
  local live = ss_slot_audible(st.slots, slot)
  r.ImGui_DrawList_AddRectFilled(dl, x0 + 1, y0 + 1, hx, y1 - 1, live and 0x49CC851C or 0x49CC850A, 0)
  r.ImGui_DrawList_AddLine(dl, hx, y0 + 1, hx, y1 - 1, live and SS_COL.accent or SS_COL.accent_m, 1)
  local label = string.format("%d/%s", math.floor(bar) + 1,
    own == math.floor(own) and tostring(math.floor(own)) or tostring(own))
  return { own = own, bar = bar, frac = frac, hx = hx, label = label }
end

---------------------------------------------------------------------------
-- Meters (SWS CF_Preview_GetPeak, post-volume)
---------------------------------------------------------------------------

SS_METER_W = 11
SS_METER_HOLD = 1.0   -- seconds a peak tick holds before it falls
SS_METER_FALL = 1.0   -- seconds the tick takes to fall the whole scale
SS_METER_DB_MIN = -48

function ss_meter_available()
  return r.CF_Preview_GetPeak and true or false
end

-- Update a voice's meter from the preview peaks (channels 0 / 1).
function ss_meter_read(v, now)
  if not (v and v.obj and r.CF_Preview_GetPeak) then
    return
  end
  local m = v.meter or { 0, 0, hold = { 0, 0 }, hold_t = { 0, 0 } }
  v.meter = m
  for ch = 0, 1 do
    local ok, ok2, peak = pcall(r.CF_Preview_GetPeak, v.obj, ch)
    local p = (ok and ok2 and tonumber(peak)) or 0
    local i = ch + 1
    m[i] = p
    if p >= m.hold[i] then
      m.hold[i], m.hold_t[i] = p, now
    elseif now - m.hold_t[i] > SS_METER_HOLD then
      -- fall in dB so the tick glides down
      local db = ss_meter_db(m.hold[i]) - (-SS_METER_DB_MIN) * (now - m.hold_t[i] - SS_METER_HOLD) / SS_METER_FALL
      m.hold[i] = math.max(p, db <= SS_METER_DB_MIN and 0 or 10 ^ (db / 20))
    end
  end
end

function ss_meter_db(p)
  if not p or p <= 1e-6 then
    return SS_METER_DB_MIN
  end
  return math.max(SS_METER_DB_MIN, 20 * math.log(p, 10))
end

-- 0..1 position on the meter scale (-48 dB .. +6 dB).
function ss_meter_pos(p)
  return math.max(0, math.min(1, (ss_meter_db(p) - SS_METER_DB_MIN) / (6 - SS_METER_DB_MIN)))
end

local function ss_meter_col(db)
  if db > -3 then return 0xE05050FF end
  if db > -12 then return 0xE0A040FF end
  return SS_COL.accent
end

-- Stereo meter in a hairline frame: vertical (two bars side by side) or
-- horizontal (two bars stacked). Colours step green -> amber (-12 dB) -> red (-3 dB).
function ss_draw_meter(dl, x0, y0, w, h, m, horizontal)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, SS_COL.line, 0, 0, 1)
  if not m then
    return
  end
  local stops = { { SS_METER_DB_MIN, -12 }, { -12, -3 }, { -3, 6 } }
  for ch = 1, 2 do
    local pos = ss_meter_pos(m[ch])
    local hold = ss_meter_pos(m.hold and m.hold[ch])
    if horizontal then
      local bh = (h - 3) / 2
      local by = y0 + 1 + (ch - 1) * (bh + 1)
      local span = w - 2
      for _, sgm in ipairs(stops) do
        local a = (sgm[1] - SS_METER_DB_MIN) / (6 - SS_METER_DB_MIN)
        local b = math.min(pos, (sgm[2] - SS_METER_DB_MIN) / (6 - SS_METER_DB_MIN))
        if b > a then
          r.ImGui_DrawList_AddRectFilled(dl, x0 + 1 + span * a, by, x0 + 1 + span * b, by + bh, ss_meter_col(sgm[2] - 0.01), 0)
        end
      end
      if hold > 0 then
        local hx = x0 + 1 + span * hold
        r.ImGui_DrawList_AddLine(dl, hx, by, hx, by + bh, ss_meter_col(ss_meter_db(m.hold[ch])), 1)
      end
    else
      local bw = (w - 3) / 2
      local bx = x0 + 1 + (ch - 1) * (bw + 1)
      local span = h - 2
      local ybot = y0 + h - 1
      for _, sgm in ipairs(stops) do
        local a = (sgm[1] - SS_METER_DB_MIN) / (6 - SS_METER_DB_MIN)
        local b = math.min(pos, (sgm[2] - SS_METER_DB_MIN) / (6 - SS_METER_DB_MIN))
        if b > a then
          r.ImGui_DrawList_AddRectFilled(dl, bx, ybot - span * b, bx + bw, ybot - span * a, ss_meter_col(sgm[2] - 0.01), 0)
        end
      end
      if hold > 0 then
        local hy = ybot - span * hold
        r.ImGui_DrawList_AddLine(dl, bx, hy, bx + bw, hy, ss_meter_col(ss_meter_db(m.hold[ch])), 1)
      end
    end
  end
end

-- Max of all voices' peaks for the master meter.
function ss_master_meter()
  if not SS_PLAY then
    return nil
  end
  local mm = { 0, 0, hold = { 0, 0 } }
  for _, v in pairs(SS_PLAY.voices) do
    local m = v.meter
    if m then
      for ch = 1, 2 do
        mm[ch] = math.max(mm[ch], m[ch] or 0)
        mm.hold[ch] = math.max(mm.hold[ch], m.hold and m.hold[ch] or 0)
      end
    end
  end
  return mm
end

-- Folder popup state for the slot whose folder icon was clicked.
function ss_folder_popup_open(st, slot)
  local list, dir = ss_folder_ranked(st, slot)
  st._folder = { slot_id = slot.id, dir = dir, list = list, search = "", hover_path = nil }
  ss_folder_nav(st, slot)
end

-- Rows of the folder popup after the search filter.
function ss_folder_popup_rows(fs)
  local q = tostring(fs.search or ""):lower()
  local out = {}
  for _, c in ipairs(fs.list or {}) do
    local name = (c.sample and c.sample.name) or tostring(c.path):match("([^/\\]+)$") or ""
    if q == "" or name:lower():find(q, 1, true) then
      out[#out + 1] = c
    end
  end
  return out
end

-- Every file in the slot's folder: name, bars, BPM, key, fit; one-shots
-- greyed. Hover auditions it alone, click swaps it in and closes.
function ss_folder_popup(st, slot)
  local fs = st._folder
  if not (fs and fs.slot_id == slot.id) then
    return nil
  end
  if not r.ImGui_BeginPopup(ctx, "ss_folder_popup") then
    if fs.open_seen then
      st._folder = nil -- it was open and got closed
    end
    return nil
  end
  fs.open_seen = true
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local w = 520
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local folder = tostring(fs.dir or ""):match("([^/\\]+)$") or tostring(fs.dir)
  if seq_truncate_text_to_width then
    folder = seq_truncate_text_to_width(string.upper(folder), w - 80) or folder
  end
  ss_text(dl, x, y, SS_COL.text, folder)
  local cnt = string.format("%d FILES", #(fs.list or {}))
  local cw = r.ImGui_CalcTextSize(ctx, cnt) or 0
  ss_text(dl, x + w - cw, y, SS_COL.mute, cnt)
  r.ImGui_Dummy(ctx, w, 16)
  r.ImGui_SetNextItemWidth(ctx, w)
  local changed, q = r.ImGui_InputTextWithHint(ctx, "##ss_folder_search", "Search this folder", fs.search or "")
  if changed and type(q) == "string" then
    fs.search = q
  end
  local rows = ss_folder_popup_rows(fs)
  local picked = nil
  local row_h = 20
  local list_h = math.min(320, math.max(row_h, #rows * row_h))
  if r.ImGui_BeginChild(ctx, "##ss_folder_list", w, list_h, 0) then
    local cdl = r.ImGui_GetWindowDrawList(ctx)
    local col_bars, col_bpm, col_key, col_fit = w - 196, w - 150, w - 98, w - 52
    for i, c in ipairs(rows) do
      local s = c.sample
      if r.ImGui_InvisibleButton(ctx, "##ss_ff_" .. i, w - 12, row_h) then
        picked = s
      end
      local rx, ry = r.ImGui_GetItemRectMin(ctx)
      local hov = r.ImGui_IsItemHovered(ctx)
      local current = c.path == slot.path
      if hov or current then
        r.ImGui_DrawList_AddRectFilled(cdl, rx, ry, rx + w - 12, ry + row_h, current and SS_COL.accent_d or 0xFFFFFF0C, 0)
      end
      local col = current and SS_COL.accent or (c.loop and SS_COL.text or SS_COL.mute)
      local dim = c.loop and SS_COL.dim or SS_COL.mute
      local name = (s and s.name) or tostring(c.path):match("([^/\\]+)$") or "?"
      if seq_truncate_text_to_width then
        name = seq_truncate_text_to_width(name, col_bars - 10) or name
      end
      local ty = ry + 3
      ss_text(cdl, rx + 4, ty, col, name)
      local bars = ss_slot_bars({ dur = tonumber(s and s.duration), rate = c.rate }, st.target_bpm or 120)
      ss_text(cdl, rx + col_bars, ty, dim, bars and (bars == math.floor(bars) and string.format("%d BAR", bars)
        or string.format("%.2g BAR", bars)) or "--")
      ss_text(cdl, rx + col_bpm, ty, dim, c.bpm and string.format("%s%.0f", c.est and "~" or "", c.bpm) or "--")
      ss_text(cdl, rx + col_key, ty, dim, c.key or "--")
      -- fit: a short bar, full = best fit, empty = doesn't fit
      local fit = math.max(0, math.min(1, ((c.fit or -1) + 0.0) / 5.0))
      r.ImGui_DrawList_AddRect(cdl, rx + col_fit, ry + 7, rx + col_fit + 36, ry + 13, SS_COL.line, 0, 0, 1)
      if fit > 0 then
        r.ImGui_DrawList_AddRectFilled(cdl, rx + col_fit + 1, ry + 8, rx + col_fit + 1 + 34 * fit, ry + 12,
          c.loop and SS_COL.accent or SS_COL.mute, 0)
      end
      if hov and fs.hover_path ~= c.path then
        fs.hover_path = c.path
        if preview_sample and s then
          ss_preview_stop()
          pcall(preview_sample, s)
        end
      end
    end
    r.ImGui_EndChild(ctx)
  end
  if picked then
    ss_slot_swap_to(st, slot, picked)
    r.ImGui_CloseCurrentPopup(ctx)
    st._folder = nil
  end
  r.ImGui_EndPopup(ctx)
  return #rows
end

local function ss_slot_row(st, slot, i, row_w)
  local role = SS_ROLE[slot.role] or SS_ROLES[1]
  local row_h = 40
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local playing = SS_PLAY and SS_PLAY.voices[slot.id] and ss_slot_audible(st.slots, slot)
  local selected = st.selected_id == slot.id
  local role_w = 92
  -- Volume on the right.
  local ctrl_w = 92
  local meter_w = ss_meter_available() and (SS_METER_W + 8) or 0
  local cx = x1 - ctrl_w - 6 - meter_w
  local name_x = x0 + role_w + 8
  local name_w = math.max(40, cx - name_x - 8)
  -- ◀ folder ▶ at the right end of the name column; text stops before it
  local nav_w = slot.path and (3 * 18 + 2 * 3) or 0
  local col_w = name_w
  name_w = math.max(30, col_w - nav_w - (nav_w > 0 and 8 or 0))
  -- playhead backdrop: the name column only (divider to just before ◀ folder ▶)
  local ph = ss_draw_slot_playhead(st, slot, dl, x0 + role_w, y0, name_x + name_w + 4, y1)
  if r.ImGui_IsMouseHoveringRect and r.ImGui_IsMouseHoveringRect(ctx, x0, y0, x1, y1)
      and r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_ChildWindows and r.ImGui_HoveredFlags_ChildWindows() or 0) then
    st._hover_slot_id = slot.id
  end
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, SS_COL.line, 0, 0, 1)
  -- a Sample Map sample dragged over the row: it drops here
  if sample_drag_active and sample_drag_active() and not SS_DRAG
      and r.ImGui_IsMouseHoveringRect and r.ImGui_IsMouseHoveringRect(ctx, x0, y0, x1, y1)
      and r.ImGui_IsWindowHovered(ctx, (r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem
        and r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem() or 0)
        | (r.ImGui_HoveredFlags_ChildWindows and r.ImGui_HoveredFlags_ChildWindows() or 0)) then
    st._drop_hover_id = slot.id
  end
  if st._drop_hover_id == slot.id or st._os_drop_id == slot.id then
    r.ImGui_DrawList_AddRect(dl, x0 + 1, y0 + 1, x1 - 1, y1 - 1, SS_COL.accent, 0, 0, 1.5)
  end
  if playing or selected then
    ss_corner_ticks(dl, x0, y0, x1, y1, SS_COL.accent)
  end
  r.ImGui_PushID(ctx, "ss_slot_" .. tostring(slot.id))

  -- Role label: click to change role or remove the slot.
  r.ImGui_SetCursorScreenPos(ctx, x0 + 1, y0 + 1)
  if r.ImGui_InvisibleButton(ctx, "##role", role_w - 2, 17) then
    r.ImGui_OpenPopup(ctx, "ss_role_menu")
  end
  local role_hover = r.ImGui_IsItemHovered(ctx)
  if role_hover then
    r.ImGui_SetTooltip(ctx, "Change this slot's role or remove it")
  end
  local role_label = string.upper(role.label)
  if seq_truncate_text_to_width then
    role_label = seq_truncate_text_to_width(role_label, role_w - 12) or role_label
  end
  ss_text(dl, x0 + 6, y0 + 3, (slot.locked or playing) and SS_COL.accent or (role_hover and SS_COL.text or SS_COL.dim),
    role_label)
  -- ROLL / LOCK / M / S under the role name
  local bw, bh, gap = 18, 16, 4
  r.ImGui_SetCursorScreenPos(ctx, x0 + 6, y0 + 20)
  if ss_icon_btn("##roll", "roll", bw, bh, false, "Pick another loop for this slot") then
    ss_do_reroll(slot)
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if ss_icon_btn("##lock", "lock", bw, bh, slot.locked, slot.locked and "Locked: Re-roll / New Batch keep this loop"
      or "Lock: keep this loop on Re-roll / New Batch") then
    slot.locked = not slot.locked
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if ss_btn("##mute", "M", bw, bh, slot.muted, "Mute (M key while hovering the row)") then
    slot.muted = not slot.muted
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if ss_btn("##solo", "S", bw, bh, slot.solo, "Solo (S key while hovering the row)") then
    slot.solo = not slot.solo
    ss_save()
  end
  r.ImGui_DrawList_AddLine(dl, x0 + role_w, y0 + 6, x0 + role_w, y1 - 6, SS_COL.line, 1)
  if r.ImGui_BeginPopup(ctx, "ss_role_menu") then
    for _, ro in ipairs(SS_ROLES) do
      if r.ImGui_Selectable(ctx, ro.label, ro.key == slot.role) and ro.key ~= slot.role then
        slot.role = ro.key
        slot.recent = {}
        ss_do_reroll(slot)
      end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_Selectable(ctx, "Remove slot") then
      st._remove_id = slot.id
    end
    r.ImGui_EndPopup(ctx)
  end


  r.ImGui_SetCursorScreenPos(ctx, name_x - 4, y0 + 1)
  local name_clicked = r.ImGui_InvisibleButton(ctx, "##name", name_w + 4, row_h - 2)
  -- drag the name out into the arrange (past a 6 px threshold; Shift = plain file)
  if slot.path and r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, 0, 6.0) and not SS_DRAG then
    ss_begin_drag_out(st, slot, is_shift_down and is_shift_down())
  end
  if ss_os_drop_target(st, slot) then
    st._os_drop_next = slot.id
  end
  if name_clicked and slot._drag_press then
    name_clicked = false
  end
  if not r.ImGui_IsMouseDown(ctx, 0) then
    slot._drag_press = nil
  end
  if name_clicked and slot.path then
    st.selected_id = slot.id
    local s = find_sample_by_path and find_sample_by_path(slot.path)
    if s then
      ss_preview_stop()
      if preview_sample then preview_sample(s) end
      if s.x and s.y then
        state.map_restore_view_cx, state.map_restore_view_cy = s.x, s.y
      end
    else
      sm_notify("That loop is not in the library now.", "warn")
    end
  end
  local name_hover = r.ImGui_IsItemHovered(ctx)
  if r.ImGui_IsItemClicked(ctx, 1) and slot.path then
    r.ImGui_OpenPopup(ctx, "ss_name_menu")
  end
  if name_hover and slot.path and not SS_DRAG then
    r.ImGui_SetTooltip(ctx, tostring(slot.path) .. "\nClick: hear it alone and show it on the map"
      .. "\nDrag: into the arrange, stretched to " .. tostring(st.bars or 8) .. " bars (Shift: plain file)\nRight-click: more")
  end
  if r.ImGui_BeginPopup(ctx, "ss_name_menu") then
    if r.ImGui_Selectable(ctx, "Show in Finder / Explorer") then
      sm_reveal_path(slot.path)
    end
    if r.ImGui_Selectable(ctx, "Copy path") and r.ImGui_SetClipboardText then
      r.ImGui_SetClipboardText(ctx, slot.path or "")
    end
    r.ImGui_EndPopup(ctx)
  end
  local name = slot.path and (slot.name or slot.path:match("([^/\\]+)$")) or "—"
  if seq_truncate_text_to_width then
    -- room for the "11/16" playhead counter
    local nw = ph and (name_w - 44) or name_w
    name = seq_truncate_text_to_width(name, math.max(20, nw)) or name
  end
  ss_text(dl, name_x, y0 + 6, slot.path and (name_hover and SS_COL.accent or SS_COL.text) or SS_COL.mute, name)
  local info
  if slot.path then
    local rate = tonumber(slot.rate) or 1.0
    local shift = tonumber(slot.shift) or 0
    info = string.format("%s%.0f BPM%s  %s  ->  x%.2f%s  %s%d st",
      slot.bpm_est and "~" or "", tonumber(slot.src_bpm) or 0,
      (slot.mult == 2 and " (dbl)") or (slot.mult == 0.5 and " (half)") or "",
      slot.src_key or "no key", rate, "", shift > 0 and "+" or "", shift)
    local own = ss_slot_bars(slot, st.target_bpm)
    if own then
      info = string.format("%s BAR  ", own == math.floor(own) and tostring(math.floor(own)) or tostring(own)) .. info
    end
    if slot.relaxed then
      info = info .. "  (looser match)"
    end
    if slot.no_match then
      info = "(no match for search)  " .. info
    end
    if slot.from_role and SS_ROLE[slot.from_role] then
      info = info .. "  [" .. string.upper(SS_ROLE[slot.from_role].label) .. "]"
    end
  else
    info = slot.no_match and "(no match for search)" or "empty: Re-roll to fill"
  end
  if seq_truncate_text_to_width then
    info = seq_truncate_text_to_width(info, name_w) or info
  end
  ss_text(dl, name_x, y0 + 22, SS_COL.dim, info)
  if ph then
    local lw = r.ImGui_CalcTextSize(ctx, ph.label) or 0
    ss_text(dl, name_x + name_w - lw, y0 + 6, ss_slot_audible(st.slots, slot) and SS_COL.accent or SS_COL.dim, ph.label)
  end
  if meter_w > 0 then
    local v = SS_PLAY and SS_PLAY.voices[slot.id]
    ss_draw_meter(dl, x1 - 6 - SS_METER_W, y0 + 6, SS_METER_W, row_h - 12, v and v.meter or nil, false)
  end
  if nav_w > 0 then
    if r.ImGui_IsMouseHoveringRect and r.ImGui_IsMouseHoveringRect(ctx, name_x + col_w - nav_w, y0, name_x + col_w, y1) then
      ss_folder_nav(st, slot) -- for the "n / N in folder" tooltip
    end
    local nav = slot.folder_nav
    local where = (nav and nav.paths[nav.pos] == slot.path) and string.format("%d / %d in folder", nav.pos, #nav.paths) or nil
    r.ImGui_SetCursorScreenPos(ctx, name_x + col_w - nav_w, y0 + (row_h - 18) * 0.5)
    if ss_icon_btn("##fold_prev", "left", 18, 18, false, "Previous loop in this folder, by fit" .. (where and ("\n" .. where) or "")) then
      ss_folder_step(st, slot, -1)
    end
    r.ImGui_SameLine(ctx, 0, 3)
    if ss_icon_btn("##fold_open", "folder", 18, 18, false, "Every file in this folder: hover to hear, click to swap"
        .. (where and ("\n" .. where) or "")) then
      ss_folder_popup_open(st, slot)
      r.ImGui_OpenPopup(ctx, "ss_folder_popup")
    end
    r.ImGui_SameLine(ctx, 0, 3)
    if ss_icon_btn("##fold_next", "right", 18, 18, false, "Next loop in this folder, by fit" .. (where and ("\n" .. where) or "")) then
      ss_folder_step(st, slot, 1)
    end
    ss_folder_popup(st, slot)
  end

  local by = y0 + (row_h - 22) * 0.5
  r.ImGui_SetCursorScreenPos(ctx, cx, by)
  r.ImGui_SetNextItemWidth(ctx, ctrl_w)
  local changed, v = r.ImGui_SliderDouble(ctx, "##vol", tonumber(slot.vol) or 1.0, 0.0, 1.5, "%.2f")
  if changed and type(v) == "number" then
    slot.vol = v
    ss_save()
  end
  r.ImGui_PopID(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x0, y1 + 4)
  r.ImGui_Dummy(ctx, row_w, 0)
end

-- Role colours for the mini slot bars on recent cards.
SS_ROLE_COL = {
  drums = 0x49CC85FF, top = 0x7FD8B0FF, bass = 0x5A8FBFFF,
  chords = 0xD9A441FF, lead = 0xE07A9AFF, texture = 0x8E6CC9FF,
}
SS_CARD = 96   -- recent card size (square)

function ss_rel_time(t, now)
  local d = math.max(0, (now or os.time()) - (tonumber(t) or 0))
  if d < 60 then return "now" end
  if d < 3600 then return string.format("%dm", d // 60) end
  if d < 86400 then return string.format("%dh", d // 3600) end
  return string.format("%dd", d // 86400)
end

-- Heart outline / fill centred on cx, cy (two arcs + a point), size = width.
-- One continuous heart outline as points (classic parametric heart:
-- x = 16 sin^3 t, y = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t), size = width,
-- centred on cx, cy. -> { x1, y1, x2, y2, ... }
function ss_heart_points(cx, cy, size, n)
  n = n or 28
  local k = size / 32
  local pts = {}
  for i = 0, n - 1 do
    local t = (i / n) * 2 * math.pi
    local sx = 16 * math.sin(t) ^ 3
    local sy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
    pts[#pts + 1] = cx + sx * k
    pts[#pts + 1] = cy - (sy + 2.5) * k
  end
  return pts
end

function ss_draw_heart(dl, cx, cy, size, col, filled)
  cx, cy = math.floor(cx) + 0.5, math.floor(cy) + 0.5
  local pts = ss_heart_points(cx, cy, size)
  if filled then
    if r.ImGui_DrawList_PathFillConcave then
      for i = 1, #pts, 2 do r.ImGui_DrawList_PathLineTo(dl, pts[i], pts[i + 1]) end
      r.ImGui_DrawList_PathFillConcave(dl, col)
    else
      -- the heart is star-shaped around its middle: a triangle fan fills it
      local mx, my = cx, cy - 0.5 * size / 32
      for i = 1, #pts, 2 do
        local j = (i + 2 > #pts) and 1 or (i + 2)
        r.ImGui_DrawList_AddTriangleFilled(dl, mx, my, pts[i], pts[i + 1], pts[j], pts[j + 1], col)
      end
    end
  end
  for i = 1, #pts, 2 do r.ImGui_DrawList_PathLineTo(dl, pts[i], pts[i + 1]) end
  local closed = r.ImGui_DrawFlags_Closed and r.ImGui_DrawFlags_Closed() or 1
  r.ImGui_DrawList_PathStroke(dl, col, closed, 1.25)
end

-- History entries the strip shows (newest first), with the filter applied.
function ss_history_visible(st)
  local out = {}
  for i, h in ipairs(st.history) do
    if st.hist_filter ~= "liked" or h.liked then
      out[#out + 1] = { h = h, index = i }
    end
  end
  return out
end

function ss_liked_count(st)
  local n = 0
  for _, h in ipairs(st.history) do if h.liked then n = n + 1 end end
  return n
end

-- History entry for the current starter, if any.
function ss_history_find_current(st)
  local cur = ss_snapshot(st)
  if not cur then return nil end
  local sig = ss_snapshot_sig(cur)
  for _, h in ipairs(st.history) do
    if ss_snapshot_sig(h) == sig then return h end
  end
  return nil
end

-- LIKE button: like / unlike the current starter (adds it to history if new).
function ss_toggle_like_current(st)
  local h = ss_history_find_current(st)
  if h then
    h.liked = not h.liked or nil
    ss_save()
    return h.liked == true
  end
  h = ss_history_push(st, true)
  return h ~= nil
end

-- One recent card. -> clicked (recall), like toggled.
function ss_draw_card(st, h, idx)
  local sz = SS_CARD
  local clicked = r.ImGui_InvisibleButton(ctx, "##ss_card_" .. idx, sz, sz)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = x0 + sz, y0 + sz
  local hovered = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, hovered and 0x111111FF or 0x0B0B0BFF, 0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, hovered and SS_COL.line_hi or SS_COL.line, 0, 0, 1)
  if hovered then
    ss_corner_ticks(dl, x0, y0, x1, y1, SS_COL.accent)
  end
  -- key + bpm, large-ish (drawn twice for weight)
  local key = h.key or "--"
  ss_text(dl, x0 + 7, y0 + 6, SS_COL.text, key)
  ss_text(dl, x0 + 7.5, y0 + 6, SS_COL.text, key)
  ss_text(dl, x0 + 7, y0 + 22, SS_COL.text, string.format("%.0f BPM", tonumber(h.bpm) or 0))
  local tmpl = SS_TEMPLATE[h.template]
  local mode = (h.mode == "arrange" and tmpl) and string.upper(tmpl.label) or "LOOP"
  ss_text(dl, x0 + 7, y0 + 40, SS_COL.mute, mode)
  -- mini visual: arrangement strip, else one bar per role with a loop
  local vy0, vy1 = y0 + 60, y0 + 76
  local vx0, vx1 = x0 + 7, x1 - 7
  if h.mode == "arrange" and ss_arr_valid(h.arr) and (h.arr.total or 0) > 0 then
    local px = (vx1 - vx0) / h.arr.total
    for _, sec in ipairs(h.arr.sections) do
      local def = SS_SECTION_TYPES[sec.type] or {}
      local n = 0
      for _ in pairs(sec.parts) do n = n + 1 end
      local hh = (vy1 - vy0) * math.min(1, n / 6)
      r.ImGui_DrawList_AddRectFilled(dl, vx0 + sec.start * px + 0.5, vy1 - hh, vx0 + (sec.start + sec.bars) * px - 0.5, vy1,
        ((def.color or 0x808080) << 8) | 0xB0, 0)
    end
  else
    local roles = {}
    for _, s in ipairs(h.slots or {}) do roles[#roles + 1] = s end
    local n = math.max(1, #roles)
    local bh = (vy1 - vy0) / n
    for i, s in ipairs(roles) do
      local by = vy0 + (i - 1) * bh
      local w = (s.muted and 0.35 or 1) * (vx1 - vx0)
      r.ImGui_DrawList_AddRectFilled(dl, vx0, by + 0.5, vx0 + w, by + math.max(1, bh - 1), SS_ROLE_COL[s.role] or SS_COL.dim, 0)
    end
  end
  ss_text(dl, x0 + 7, y1 - 17, SS_COL.mute, ss_rel_time(h.t))
  -- heart, top right: click toggles like instead of recalling
  local hx, hy, hs = x1 - 13, y0 + 12, 12
  ss_draw_heart(dl, hx, hy, hs, h.liked and SS_COL.accent or (hovered and SS_COL.dim or SS_COL.mute), h.liked)
  local liked_click = false
  if clicked then
    local mx, my = r.ImGui_GetMousePos(ctx)
    if mx and my and mx >= hx - hs and mx <= hx + hs and my >= hy - hs and my <= hy + hs then
      liked_click, clicked = true, false
    end
  end
  if hovered then
    local names = {}
    for _, s in ipairs(h.slots or {}) do
      local role = SS_ROLE[s.role]
      names[#names + 1] = string.format("%s: %s", role and role.label or s.role, tostring(s.name or s.path))
    end
    r.ImGui_SetTooltip(ctx, table.concat(names, "\n") .. "\n\nClick: recall  ·  Heart: like  ·  Right-click: more")
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    r.ImGui_OpenPopup(ctx, "ss_card_menu_" .. idx)
  end
  if r.ImGui_BeginPopup(ctx, "ss_card_menu_" .. idx) then
    if r.ImGui_Selectable(ctx, h.liked and "Unlike" or "Like") then
      liked_click = true
    end
    if r.ImGui_Selectable(ctx, "Remove") then
      st._remove_hist = h
    end
    r.ImGui_EndPopup(ctx)
  end
  return clicked, liked_click
end

-- Recent starters as a horizontal strip of square cards, ALL / LIKED filter on
-- the left. -> { shown = n, liked = n } for tests.
function ss_history_cards(st)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or 600
  local filt_w = 64
  r.ImGui_BeginGroup(ctx)
  if ss_btn("##ss_hist_all", "ALL", filt_w, 22, st.hist_filter ~= "liked", "Show every recent starter") then
    st.hist_filter = "all"
    ss_save()
  end
  local nliked = ss_liked_count(st)
  local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
  if ss_btn("##ss_hist_liked", "      " .. nliked, filt_w, 22, st.hist_filter == "liked", "Show only liked starters") then
    st.hist_filter = "liked"
    ss_save()
  end
  ss_draw_heart(r.ImGui_GetWindowDrawList(ctx), lx + 18, ly + 11, 11,
    st.hist_filter == "liked" and SS_COL.accent or SS_COL.dim, st.hist_filter == "liked")
  r.ImGui_EndGroup(ctx)
  r.ImGui_SameLine(ctx, 0, 8)
  local list = ss_history_visible(st)
  local flags = r.ImGui_WindowFlags_HorizontalScrollbar and r.ImGui_WindowFlags_HorizontalScrollbar() or 0
  local child_h = SS_CARD + 16
  if r.ImGui_BeginChild(ctx, "##ss_history", math.max(1, avail_w - filt_w - 8), child_h, 0, flags) then
    if #list == 0 then
      r.ImGui_TextColored(ctx, SS_COL.mute, st.hist_filter == "liked" and "No liked starters yet: click a card's heart."
        or "Starters you make show up here.")
    end
    for i, e in ipairs(list) do
      if i > 1 then r.ImGui_SameLine(ctx, 0, 6) end
      local recall, like = ss_draw_card(st, e.h, e.index)
      if like then
        e.h.liked = not e.h.liked or nil
        ss_save()
      elseif recall then
        ss_history_recall(st, e.h)
        ss_preview_resync(nil)
      end
    end
    -- mouse wheel scrolls the strip sideways
    if r.ImGui_IsWindowHovered(ctx) and r.ImGui_GetMouseWheel and r.ImGui_SetScrollX then
      local wheel = r.ImGui_GetMouseWheel(ctx)
      if type(wheel) == "number" and wheel ~= 0 then
        r.ImGui_SetScrollX(ctx, math.max(0, (r.ImGui_GetScrollX(ctx) or 0) - wheel * 60))
      end
    end
    r.ImGui_EndChild(ctx)
  end
  if st._remove_hist then
    for i, h in ipairs(st.history) do
      if h == st._remove_hist then table.remove(st.history, i) break end
    end
    st._remove_hist = nil
    ss_save()
  end
  return { shown = #list, liked = nliked }
end

SS_STRIP_HEAD_H = 18
SS_STRIP_ROW_H = 5

-- Section strip: a hairline box per section (width by bars), a lane per role
-- showing where it plays, green playhead in arrange preview. Click a section
-- to play from there. -> rect for tests.
function ss_draw_arrangement_strip(st, w)
  local arr = ss_arrangement(st)
  local roles = {}
  local have = {}
  for _, slot in ipairs(st.slots) do
    if slot.path and not slot.muted and not have[slot.role] then
      have[slot.role] = true
      roles[#roles + 1] = slot.role
    end
  end
  local h = SS_STRIP_HEAD_H + math.max(1, #roles) * SS_STRIP_ROW_H + 6
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##ss_arr_strip", math.max(1, w), h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local total = math.max(1, arr.total or 1)
  local px = w / total
  local bar_s = 240.0 / (st.target_bpm or 120)
  local mx = hovered and r.ImGui_GetMousePos(ctx) or nil
  for _, sec in ipairs(arr.sections) do
    local sx0 = x0 + sec.start * px
    local sx1 = x0 + (sec.start + sec.bars) * px
    local def = SS_SECTION_TYPES[sec.type] or {}
    local over = mx and mx >= sx0 and mx < sx1
    if over then
      r.ImGui_DrawList_AddRectFilled(dl, sx0, y0, sx1, y0 + h, 0xFFFFFF0C, 0)
      r.ImGui_SetTooltip(ctx, string.format("%s  ·  %d bars  ·  %.1f s\nClick: play from here", sec.name, sec.bars,
        sec.bars * bar_s))
    end
    r.ImGui_DrawList_AddRect(dl, sx0, y0, sx1, y0 + h, SS_COL.line, 0, 0, 1)
    r.ImGui_DrawList_AddLine(dl, sx0 + 1, y0 + 1, sx1 - 1, y0 + 1, ((def.color or 0x808080) << 8) | 0xFF, 2)
    local label = string.upper(sec.name)
    local lw = r.ImGui_CalcTextSize(ctx, label) or 0
    if lw > sx1 - sx0 - 6 then
      label = string.upper((def.label or sec.type):sub(1, 1)) .. (sec.name:match("%d+$") or "")
      lw = r.ImGui_CalcTextSize(ctx, label) or 0
    end
    if lw <= sx1 - sx0 - 4 then
      ss_text(dl, sx0 + 4, y0 + 3, over and SS_COL.text or SS_COL.dim, label)
    end
    for ri, role in ipairs(roles) do
      local part = sec.parts[role]
      if part then
        local ly = y0 + SS_STRIP_HEAD_H + (ri - 1) * SS_STRIP_ROW_H
        local col = part.rise and SS_COL.accent_m or ((part.vol or 1) < 0.9 and SS_COL.accent_d or SS_COL.accent_m)
        r.ImGui_DrawList_AddRectFilled(dl, x0 + (sec.start + part.from) * px + 1, ly,
          x0 + (sec.start + part.to) * px - 1, ly + SS_STRIP_ROW_H - 1, col, 0)
      end
    end
  end
  local playing_arr = SS_PLAY and st.mode == "arrange"
  if playing_arr then
    local bar = ss_arr_bar_at(st, r.time_precise() - SS_PLAY.t0)
    local hx = x0 + bar * px
    r.ImGui_DrawList_AddLine(dl, hx, y0 - 2, hx, y0 + h + 2, SS_COL.accent, 1)
    local sec = ss_arr_section_at(arr, bar)
    if sec then
      ss_corner_ticks(dl, x0 + sec.start * px, y0, x0 + (sec.start + sec.bars) * px, y0 + h, SS_COL.accent)
    end
  end
  if clicked and mx then
    local bar = math.max(0, math.min(total - 0.001, (mx - x0) / px))
    local sec = ss_arr_section_at(arr, bar)
    if sec then
      ss_preview_play(sec.start)
    end
  end
  return { x0 = x0, y0 = y0, w = w, h = h, roles = roles }
end

local function ss_template_combo(st)
  local t = SS_TEMPLATE[st.template] or SS_TEMPLATE.club
  r.ImGui_SetNextItemWidth(ctx, 92)
  if r.ImGui_BeginCombo(ctx, "##ss_template", t.label) then
    for _, tp in ipairs(SS_TEMPLATES) do
      local desc = tp.label
      if tp.sections then
        local bars = 0
        for _, s in ipairs(tp.sections) do bars = bars + s[2] end
        desc = string.format("%s  (%d bars)", tp.label, bars)
      end
      if r.ImGui_Selectable(ctx, desc .. "##tp_" .. tp.key, tp.key == st.template) then
        st.template = tp.key
        ss_arrangement(st, true)
        if SS_PLAY then ss_preview_play(0) end
        ss_save()
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

-- S / M while hovering a row: solo / mute that slot (no modifiers, not while
-- a field or drag is active). The key is kept from Sample Map's own shortcuts
-- (SS_WINDOW_HOT) and from REAPER.
function ss_handle_row_keys(st)
  local id = st._hover_slot_id
  if not id or not r.ImGui_IsKeyPressed then
    return nil
  end
  if (r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx))
      or (imgui_text_input_active and imgui_text_input_active()) then
    return nil
  end
  if (is_shift_down and is_shift_down()) or (is_ctrl_down and is_ctrl_down())
      or (is_alt_down and is_alt_down()) or (is_cmd_down and is_cmd_down()) then
    return nil
  end
  local slot
  for _, s in ipairs(st.slots) do
    if s.id == id then slot = s end
  end
  if not slot then
    return nil
  end
  local did
  if r.ImGui_Key_S and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_S(), false) then
    slot.solo = not slot.solo
    did = "solo"
  elseif r.ImGui_Key_M and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_M(), false) then
    slot.muted = not slot.muted
    did = "mute"
  end
  if did then
    if r.ImGui_SetNextFrameWantCaptureKeyboard then
      r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
    end
    ss_save()
  end
  return did
end

-- Search field + chips + ANY / ALL + live loop count.
function ss_draw_search_row(st, avail_w)
  ss_label("Search")
  r.ImGui_SameLine(ctx)
  local flags = r.ImGui_InputTextFlags_EnterReturnsTrue and r.ImGui_InputTextFlags_EnterReturnsTrue() or 0
  r.ImGui_SetNextItemWidth(ctx, 160)
  local entered, txt = r.ImGui_InputTextWithHint(ctx, "##ss_search", "Search, then Enter", st._search_text or "", flags)
  if type(txt) == "string" then st._search_text = txt end
  local active = r.ImGui_IsItemActive(ctx)
  if entered then
    if ss_search_add(st, st._search_text) then
      st._search_text = ""
    end
    if r.ImGui_SetKeyboardFocusHere then r.ImGui_SetKeyboardFocusHere(ctx, -1) end
  elseif active and (st._search_text or "") == "" and r.ImGui_Key_Backspace
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Backspace(), false) and ss_search_active(st) then
    ss_search_remove(st, #st.search_chips)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Type and press Enter to add a search: rolls then pick only matching loops."
      .. "\nAll words of a search must appear in the name, folder or tags."
      .. "\nBackspace in the empty field removes the last one.")
  end
  local remove
  for i, q in ipairs(st.search_chips or {}) do
    r.ImGui_SameLine(ctx, 0, 4)
    if ss_btn("##ss_chip_" .. i, string.upper(q) .. "  ×", nil, 20, true, "Remove this search") then
      remove = i
    end
  end
  if remove then ss_search_remove(st, remove) end
  if ss_search_active(st) then
    if #st.search_chips > 1 then
      r.ImGui_SameLine(ctx, 0, 8)
      if ss_btn("##ss_search_mode", st.search_mode == "all" and "ALL" or "ANY", 36, 20, false,
          st.search_mode == "all" and "Loops must match every search (click: any)" or "Loops may match any search (click: all)") then
        st.search_mode = (st.search_mode == "all") and "any" or "all"
        st._search_count = nil
        ss_save()
      end
    end
    r.ImGui_SameLine(ctx, 0, 8)
    local n = ss_search_count(st)
    local txt_n = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    r.ImGui_TextColored(ctx, n > 0 and SS_COL.dim or SS_COL.warn, txt_n .. (n == 1 and " LOOP" or " LOOPS"))
  end
end

local function ss_window_body(st)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or 600
  local dl = r.ImGui_GetWindowDrawList(ctx)

  ss_draw_cycle_timeline(st, avail_w)

  -- Target: key, tempo, bars, scope.
  ss_label("Key")
  r.ImGui_SameLine(ctx)
  ss_key_combo(st)
  r.ImGui_SameLine(ctx, 0, 14)
  ss_label("BPM")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 70)
  local bpm_changed, bpm = r.ImGui_DragDouble(ctx, "##ss_bpm", st.target_bpm or ss_project_bpm(), 0.25, 40, 240, "%.1f")
  if bpm_changed and type(bpm) == "number" then
    st.target_bpm = math.max(40, math.min(240, bpm))
    ss_retarget_all(st)
    st._tempo_dirty = true
    ss_save()
  end
  if st._tempo_dirty and not r.ImGui_IsItemActive(ctx) then
    st._tempo_dirty = nil
    ss_preview_resync(nil)
  end
  r.ImGui_SameLine(ctx, 0, 4)
  if ss_btn("##ss_bpm_proj", "PROJ", 40, 20, false, "Use the project tempo") then
    st.target_bpm = ss_project_bpm()
    ss_retarget_all(st)
    ss_preview_resync(nil)
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, 14)
  ss_label("Bars")
  for _, b in ipairs({ 4, 8, 16 }) do
    r.ImGui_SameLine(ctx, 0, 4)
    if ss_btn("##ss_bars" .. b, tostring(b), 26, 20, st.bars == b, "Item length when added to the project") then
      st.bars = b
      ss_save()
    end
  end
  r.ImGui_SameLine(ctx, 0, 14)
  ss_label("From")
  r.ImGui_SameLine(ctx, 0, 4)
  if ss_btn("##ss_scope_lib", "LIBRARY", nil, 20, st.scope ~= "map", "Pick from every loop in the library") then
    st.scope = "library"
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, 4)
  if ss_btn("##ss_scope_map", "MAP VIEW", nil, 20, st.scope == "map", "Pick only from loops the map shows now (tab, tags, search)") then
    st.scope = "map"
    ss_save()
  end

  -- Search: Enter adds the query as a chip; rolls pick only matching loops.
  ss_draw_search_row(st, avail_w)

  -- Safe <-> Chaos.
  ss_label("Safe")
  r.ImGui_SameLine(ctx)
  local cw = r.ImGui_CalcTextSize(ctx, "CHAOS") or 40
  r.ImGui_SetNextItemWidth(ctx, math.max(80, avail_w - 2 * cw - 30))
  local ch_changed, chaos = r.ImGui_SliderDouble(ctx, "##ss_chaos", st.chaos or 0.25, 0.0, 1.0, "")
  if ch_changed and type(chaos) == "number" then
    st.chaos = chaos
    ss_save()
  end
  if r.ImGui_IsItemHovered(ctx) then
    local P = ss_chaos_params(st.chaos)
    r.ImGui_SetTooltip(ctx, string.format(
      "Stretch within +-%.0f%%%s\nPitch shift up to %d semitones\n%s\n%s%s",
      P.max_dev * 100, P.allow_hd and ", half / double time allowed" or "",
      P.max_shift,
      P.allow_unknown_key and "Melodic loops without a key allowed" or "Melodic loops need a key in the name",
      P.allow_est_bpm and "Tempo may be guessed from the length" or "Tempo must be in the name",
      P.neighbour_p > 0 and string.format("\nSometimes picks from a neighbouring role (%.0f%%)", P.neighbour_p * 100) or ""))
  end
  r.ImGui_SameLine(ctx)
  ss_label("Chaos")
  r.ImGui_Dummy(ctx, 1, 2)

  -- Slots.
  st._hover_slot_id = nil
  st._drop_hover_id, st._drop_new_hover = nil, nil
  st._os_drop_id, st._os_drop_next = st._os_drop_next, nil
  for i, slot in ipairs(st.slots) do
    ss_slot_row(st, slot, i, avail_w)
  end
  ss_handle_row_keys(st)
  if st._remove_id then
    for i, slot in ipairs(st.slots) do
      if slot.id == st._remove_id then
        if SS_PLAY then ss_voice_stop(SS_PLAY.voices[slot.id]); SS_PLAY.voices[slot.id] = nil end
        table.remove(st.slots, i)
        break
      end
    end
    st._remove_id = nil
    ss_save()
  end
  if ss_btn("##ss_add_slot", "+ SLOT", 70, 20, false, "Add a slot") then
    r.ImGui_OpenPopup(ctx, "ss_add_slot_menu")
  end
  -- drop zone: samples or files dropped here become new slots
  r.ImGui_SameLine(ctx, 0, 6)
  local zw = math.max(40, avail_w - 76)
  r.ImGui_InvisibleButton(ctx, "##ss_drop_new", zw, 20)
  local zx, zy = r.ImGui_GetItemRectMin(ctx)
  local dragging_in = sample_drag_active and sample_drag_active() and not SS_DRAG
  if dragging_in and r.ImGui_IsMouseHoveringRect(ctx, zx, zy, zx + zw, zy + 20) then
    st._drop_new_hover = true
  end
  local os_hover = ss_os_drop_target(st, nil)
  if dragging_in or os_hover then
    local hot = st._drop_new_hover or os_hover
    r.ImGui_DrawList_AddRect(dl, zx, zy, zx + zw, zy + 20, hot and SS_COL.accent or SS_COL.line, 0, 0, 1)
    ss_text(dl, zx + 8, zy + 3, hot and SS_COL.accent or SS_COL.mute, "DROP HERE FOR A NEW SLOT")
  end
  ss_take_sample_drop(st)
  if r.ImGui_BeginPopup(ctx, "ss_add_slot_menu") then
    for _, ro in ipairs(SS_ROLES) do
      if r.ImGui_Selectable(ctx, ro.label) then
        local slot = ss_new_slot(st, ro.key)
        st.slots[#st.slots + 1] = slot
        ss_do_reroll(slot)
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  -- Arrangement strip.
  if st.mode == "arrange" then
    r.ImGui_Dummy(ctx, 1, 4)
    ss_draw_arrangement_strip(st, avail_w)
  end

  -- Actions.
  r.ImGui_Dummy(ctx, 1, 2)
  local ax, ay = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddLine(dl, ax, ay, ax + avail_w, ay, SS_COL.line, 1)
  r.ImGui_Dummy(ctx, avail_w, 2)
  if ss_btn("##ss_play", SS_PLAY and "STOP" or "PLAY", 70, 26, SS_PLAY ~= nil, "Play all slots together, looped (Space in this window)") then
    if SS_PLAY then ss_preview_stop() else ss_preview_play() end
  end
  r.ImGui_SameLine(ctx, 0, 6)
  if ss_btn("##ss_reroll", "RE-ROLL UNLOCKED", nil, 26, false, "New loops for every unlocked slot; key and tempo stay") then
    ss_do_reroll("unlocked")
  end
  r.ImGui_SameLine(ctx, 0, 6)
  if ss_btn("##ss_batch", "NEW BATCH", nil, 26, false, "Fresh starter: new loops for unlocked slots, and a new key when Key is Auto") then
    ss_do_reroll("batch")
  end
  r.ImGui_SameLine(ctx, 0, 6)
  local cur_h = ss_history_find_current(st)
  local liked_now = cur_h and cur_h.liked
  local lkx, lky = r.ImGui_GetCursorScreenPos(ctx)
  if ss_btn("##ss_save", "      LIKE", 74, 26, liked_now, "Like this starter: liked ones stay in Recent for good") then
    if ss_toggle_like_current(st) then sm_notify("Song Starter liked.") end
  end
  ss_draw_heart(dl, lkx + 15, lky + 13, 11, liked_now and SS_COL.accent or SS_COL.dim, liked_now)
  r.ImGui_SameLine(ctx, 0, 6)
  local add_clicked = ss_btn("##ss_add", "ADD TO PROJECT", nil, 26, SS_ADD_DRAG ~= nil, (st.mode == "arrange"
      and "Folder track with one track per unmuted slot, an item per section and a region per section, at the edit cursor"
      or "Folder track with one track per unmuted slot, at the edit cursor")
      .. "\nDrag into the arrange: drop on a track (tracks from there on) or on NEW FOLDER at the top")
  -- press and drag past 6 px: drag-to-arrange mode instead of a click
  if r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, 0, 6.0) and not SS_ADD_DRAG and not st._add_dragged then
    st._add_dragged = true
    ss_add_drag_begin()
  end
  if add_clicked and not st._add_dragged then
    ss_add_to_project()
  end
  if not r.ImGui_IsMouseDown(ctx, 0) then
    st._add_dragged = nil
  end
  r.ImGui_SameLine(ctx, 0, 10)
  local tc, tv = r.ImGui_Checkbox(ctx, "Set project tempo", st.set_tempo == true)
  if tc then
    st.set_tempo = tv and true or false
    ss_save()
  end

  -- Mode: LOOP (every slot for N bars) or ARRANGE (sections).
  ss_label("Mode")
  r.ImGui_SameLine(ctx, 0, 6)
  for _, m in ipairs({ { "loop", "LOOP", "Play / add every slot as one loop of N bars" },
                       { "arrange", "ARRANGE", "Build a song: sections where parts come and go" } }) do
    if ss_btn("##ss_mode_" .. m[1], m[2], nil, 22, st.mode == m[1], m[3]) and st.mode ~= m[1] then
      st.mode = m[1]
      if m[1] == "arrange" then ss_arrangement(st) end
      if SS_PLAY then ss_preview_play(0) end
      ss_save()
    end
    r.ImGui_SameLine(ctx, 0, 4)
  end
  if st.mode == "arrange" then
    r.ImGui_SameLine(ctx, 0, 10)
    ss_template_combo(st)
    r.ImGui_SameLine(ctx, 0, 4)
    if ss_btn("##ss_arr_reroll", "VARY", nil, 22, false, "Rebuild the arrangement (Chaos sets how unusual)") then
      ss_arrangement(st, true)
      if SS_PLAY then ss_preview_play(0) end
      ss_save()
    end
    local arr = ss_arrangement(st)
    local secs = math.floor((arr.total or 0) * 240.0 / (st.target_bpm or 120) + 0.5)
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_TextColored(ctx, SS_COL.dim, string.format("%d BARS  ·  %d:%02d", arr.total or 0, secs // 60, secs % 60))
  else
    r.ImGui_NewLine(ctx)
  end

  -- History: recent starters as cards.
  r.ImGui_Dummy(ctx, 1, 4)
  ss_label("Recent")
  ss_history_cards(st)

  -- Space toggles playback while this window has focus and no field is active.
  if r.ImGui_IsWindowFocused and r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0)
      and not (r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx))
      and r.ImGui_Key_Space and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space(), false) then
    if SS_PLAY then ss_preview_stop() else ss_preview_play() end
  end
end

function render_song_starter_window()
  local st = ss_state()
  if st._save_due and r.time_precise() >= st._save_due then
    ss_save_now()
  end
  ss_preview_update()
  ss_drag_out_update(st)
  ss_add_drag_update(st)
  SS_WINDOW_HOT = false
  if not st.open then
    if SS_PLAY then ss_preview_stop() end
    return
  end
  st.target_bpm = st.target_bpm or ss_project_bpm()
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, 760, 560, r.ImGui_Cond_FirstUseEver and r.ImGui_Cond_FirstUseEver() or 0)
  end
  local nc, nv = ss_push_style()
  local flags = 0
  for _, getter in ipairs({ r.ImGui_WindowFlags_NoCollapse, r.ImGui_WindowFlags_NoDocking }) do
    if getter then flags = flags | getter() end
  end
  local began_ok, visible, open = pcall(r.ImGui_Begin, ctx, "Song Starter##song_starter_window", true, flags)
  if not began_ok then
    r.ImGui_PopStyleVar(ctx, nv)
    r.ImGui_PopStyleColor(ctx, nc)
    log("Song Starter Begin failed: " .. tostring(visible))
    return
  end
  if open == false then
    st.open = false
    ss_preview_stop()
    ss_save()
  end
  if visible then
    -- Hovered or focused: Sample Map's own key shortcuts stand down
    -- (handle_script_keyboard_shortcuts) so S / M / Space act here only.
    local flags_rc = r.ImGui_HoveredFlags_RootAndChildWindows and r.ImGui_HoveredFlags_RootAndChildWindows() or 0
    local focus_rc = r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0
    SS_WINDOW_HOT = (r.ImGui_IsWindowHovered(ctx, flags_rc) or r.ImGui_IsWindowFocused(ctx, focus_rc)) and true or false
    sm_mono_space_backdrop()
    -- tooltips from this window are laid out and drawn in its font
    HINT_FONT_KIND = SM_MONO_SPACE and "cond" or nil
    local ok, err = pcall(ss_window_body, st)
    HINT_FONT_KIND = nil
    if not ok and sm_report_error then
      sm_report_error("Song Starter", err)
    end
  end
  end_window(visible, true)
  r.ImGui_PopStyleVar(ctx, nv)
  r.ImGui_PopStyleColor(ctx, nc)
end

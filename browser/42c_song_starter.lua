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

-- Source position (seconds) at which a loop rejoins playback `elapsed` seconds in.
function ss_loop_phase(slot, elapsed)
  local dur = tonumber(slot.dur)
  if not dur or dur <= 0 then
    return 0
  end
  local rate = tonumber(slot.rate) or 1.0
  return (math.max(0, elapsed) * rate) % dur
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
    mode = "loop", template = "club", arr = nil,
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
    mode = st.mode, template = st.template, arr = st.arr,
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

local function ss_snapshot_sig(h)
  local parts = { tostring(h.key), string.format("%.2f", tonumber(h.bpm) or 0), tostring(h.mode),
    tostring(h.template) }
  for _, s in ipairs(h.slots or {}) do parts[#parts + 1] = tostring(s.role) .. "=" .. tostring(s.path) end
  return table.concat(parts, "|")
end

-- Add the current starter to history (pinned = Save). Unpinned entries past
-- SS_HISTORY_MAX drop off the end; pinned ones stay.
function ss_history_push(st, pinned)
  local h = ss_snapshot(st)
  if not h then
    return nil
  end
  local sig = ss_snapshot_sig(h)
  for i, old in ipairs(st.history) do
    if ss_snapshot_sig(old) == sig then
      table.remove(st.history, i)
      h.pinned = old.pinned
      break
    end
  end
  if pinned then
    h.pinned = true
  end
  table.insert(st.history, 1, h)
  local unpinned = 0
  for i = 1, #st.history do
    if not st.history[i].pinned then unpinned = unpinned + 1 end
  end
  for i = #st.history, 1, -1 do
    if unpinned <= SS_HISTORY_MAX then break end
    if not st.history[i].pinned then
      table.remove(st.history, i)
      unpinned = unpinned - 1
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
    if ss_is_loop(s) and not (sample_scan_folder_unavailable and sample_scan_folder_unavailable(s)) then
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
    if not slot.path and (type(which) ~= "table" or slot == which) then
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
  r.CF_Preview_SetValue(obj, "B_LOOP", 1)
  r.CF_Preview_SetValue(obj, "B_PPITCH", 1)
  r.CF_Preview_SetValue(obj, "D_PLAYRATE", tonumber(slot.rate) or 1.0)
  r.CF_Preview_SetValue(obj, "D_PITCH", tonumber(slot.shift) or 0)
  r.CF_Preview_SetValue(obj, "D_VOLUME", ss_voice_volume(st, slot, elapsed or 0))
  local pos = ss_loop_phase(slot, elapsed or 0)
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
            offs = ss_loop_phase(slot, t0), rise = part.rise }
        end
      end
    end
  end
  return out
end

-- Arrange mode Add to project: folder + a track per slot that plays, an item
-- per section, regions per section. One undo step.
function ss_add_arrangement()
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
  local base = r.GetCursorPosition()
  local key = st.target_key
  local tmpl = SS_TEMPLATE[arr.template or st.template]
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  if st.set_tempo and r.SetCurrentBPM then
    r.SetCurrentBPM(proj, bpm, true)
  end
  local idx = r.CountTracks(proj)
  local sel = r.GetSelectedTrack(proj, 0)
  if sel then
    idx = math.max(0, math.floor(r.GetMediaTrackInfo_Value(sel, "IP_TRACKNUMBER") + 0.5) - 1)
  end
  r.InsertTrackAtIndex(idx, true)
  local folder = r.GetTrack(proj, idx)
  local title = string.format("Song Starter %s%.0f%s", key and (key .. " ") or "", bpm,
    tmpl and (" " .. tmpl.label) or "")
  r.GetSetMediaTrackInfo_String(folder, "P_NAME", title, true)
  r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  local last
  for i, slot in ipairs(list) do
    r.InsertTrackAtIndex(idx + i, true)
    local tr = r.GetTrack(proj, idx + i)
    local role = SS_ROLE[slot.role]
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", role and role.label or slot.role, true)
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    for _, it in ipairs(by_slot[slot]) do
      local item = r.AddMediaItemToTrack(tr)
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
  r.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", -1)
  local bar_s = 240.0 / bpm
  for _, sec in ipairs(arr.sections) do
    local def = SS_SECTION_TYPES[sec.type] or {}
    r.AddProjectMarker2(proj, true, base + sec.start * bar_s, base + (sec.start + sec.bars) * bar_s, sec.name, -1,
      ss_native_color(def.color or 0x808080))
  end
  r.PreventUIRefresh(-1)
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  r.UpdateArrange()
  r.Undo_EndBlock2(proj, "Song Starter: arrange", -1)
  ss_history_push(st, false)
  sm_notify(string.format("Arranged %s: %d tracks, %d sections, %d bars.", title, #list, #arr.sections, arr.total))
  return true
end

function ss_add_to_project()
  local st = ss_state()
  if st.mode == "arrange" then
    return ss_add_arrangement()
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
  local pos = r.GetCursorPosition()
  local length = (st.bars or 8) * 240.0 / bpm
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  if st.set_tempo and r.SetCurrentBPM then
    r.SetCurrentBPM(proj, bpm, true)
  end
  local idx = r.CountTracks(proj)
  local sel = r.GetSelectedTrack(proj, 0)
  if sel then
    idx = math.max(0, math.floor(r.GetMediaTrackInfo_Value(sel, "IP_TRACKNUMBER") + 0.5) - 1)
  end
  r.InsertTrackAtIndex(idx, true)
  local folder = r.GetTrack(proj, idx)
  local title = string.format("Song Starter %s%.0f", key and (key .. " ") or "", bpm)
  r.GetSetMediaTrackInfo_String(folder, "P_NAME", title, true)
  r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  local last
  for i, slot in ipairs(list) do
    r.InsertTrackAtIndex(idx + i, true)
    local tr = r.GetTrack(proj, idx + i)
    local role = SS_ROLE[slot.role]
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", role and role.label or slot.role, true)
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    local item = r.AddMediaItemToTrack(tr)
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
  r.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", -1)
  r.PreventUIRefresh(-1)
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  r.UpdateArrange()
  r.Undo_EndBlock2(proj, "Sample Map: add Song Starter", -1)
  ss_history_push(st, false)
  sm_notify(string.format("Added %s: %d track%s, %d bars.", title, #list, #list == 1 and "" or "s", st.bars or 8))
  return true
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

local function ss_slot_row(st, slot, i, row_w)
  local role = SS_ROLE[slot.role] or SS_ROLES[1]
  local row_h = 40
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local playing = SS_PLAY and SS_PLAY.voices[slot.id] and ss_slot_audible(st.slots, slot)
  local selected = st.selected_id == slot.id
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, SS_COL.line, 0, 0, 1)
  if playing or selected then
    ss_corner_ticks(dl, x0, y0, x1, y1, SS_COL.accent)
  end
  r.ImGui_PushID(ctx, "ss_slot_" .. tostring(slot.id))

  -- Role label: click to change role or remove the slot.
  local role_w = 92
  r.ImGui_SetCursorScreenPos(ctx, x0 + 1, y0 + 1)
  if r.ImGui_InvisibleButton(ctx, "##role", role_w, row_h - 2) then
    r.ImGui_OpenPopup(ctx, "ss_role_menu")
  end
  local role_hover = r.ImGui_IsItemHovered(ctx)
  if role_hover then
    r.ImGui_SetTooltip(ctx, "Change this slot's role or remove it")
  end
  ss_text(dl, x0 + 8, y0 + 7, (slot.locked or playing) and SS_COL.accent or (role_hover and SS_COL.text or SS_COL.dim),
    string.upper(role.label))
  ss_text(dl, x0 + 8, y0 + 22, SS_COL.mute, string.format("%02d", i))
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

  -- Controls on the right.
  local ctrl_w = 64 + 38 + 40 + 22 + 22 + 60 + 6 * 5
  local cx = x1 - ctrl_w - 6
  local name_x = x0 + role_w + 8
  local name_w = math.max(40, cx - name_x - 8)

  r.ImGui_SetCursorScreenPos(ctx, name_x - 4, y0 + 1)
  if r.ImGui_InvisibleButton(ctx, "##name", name_w + 4, row_h - 2) and slot.path then
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
  if name_hover and slot.path then
    r.ImGui_SetTooltip(ctx, tostring(slot.path) .. "\nClick: hear it alone and show it on the map\nRight-click: more")
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
    name = seq_truncate_text_to_width(name, name_w) or name
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
    if slot.relaxed then
      info = info .. "  (looser match)"
    end
    if slot.from_role and SS_ROLE[slot.from_role] then
      info = info .. "  [" .. string.upper(SS_ROLE[slot.from_role].label) .. "]"
    end
  else
    info = "empty: Re-roll to fill"
  end
  if seq_truncate_text_to_width then
    info = seq_truncate_text_to_width(info, name_w) or info
  end
  ss_text(dl, name_x, y0 + 22, SS_COL.dim, info)

  local by = y0 + (row_h - 22) * 0.5
  r.ImGui_SetCursorScreenPos(ctx, cx, by)
  if ss_btn("##roll", "ROLL", 64, 22, false, "Pick another loop for this slot") then
    ss_do_reroll(slot)
  end
  r.ImGui_SameLine(ctx, 0, 6)
  if ss_btn("##lock", "LOCK", 38 + 2, 22, slot.locked, "Keep this loop on Re-roll / New Batch") then
    slot.locked = not slot.locked
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, 6)
  if ss_btn("##mute", "M", 22, 22, slot.muted, "Mute") then
    slot.muted = not slot.muted
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, 6)
  if ss_btn("##solo", "S", 22, 22, slot.solo, "Solo") then
    slot.solo = not slot.solo
    ss_save()
  end
  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_SetNextItemWidth(ctx, 60 + 32)
  local changed, v = r.ImGui_SliderDouble(ctx, "##vol", tonumber(slot.vol) or 1.0, 0.0, 1.5, "%.2f")
  if changed and type(v) == "number" then
    slot.vol = v
    ss_save()
  end
  r.ImGui_PopID(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x0, y1 + 4)
  r.ImGui_Dummy(ctx, row_w, 0)
end

local function ss_history_list(st)
  if #st.history == 0 then
    r.ImGui_TextColored(ctx, SS_COL.mute, "Starters you make show up here.")
    return
  end
  for i, h in ipairs(st.history) do
    r.ImGui_PushID(ctx, "ss_hist_" .. i)
    local roles = {}
    for _, s in ipairs(h.slots or {}) do
      roles[#roles + 1] = SS_ROLE[s.role] and SS_ROLE[s.role].label:match("^(%S+)") or s.role
    end
    local label = string.format("%s%s  %.0f BPM  %s  ·  %s", h.pinned and "* " or "  ",
      h.key or "--", tonumber(h.bpm) or 0, os.date("%b %d %H:%M", h.t or 0), table.concat(roles, " "))
    if r.ImGui_Selectable(ctx, label) then
      ss_history_recall(st, h)
      ss_preview_resync(nil)
    end
    if r.ImGui_IsItemClicked(ctx, 1) then
      r.ImGui_OpenPopup(ctx, "ss_hist_menu")
    end
    if r.ImGui_BeginPopup(ctx, "ss_hist_menu") then
      if r.ImGui_Selectable(ctx, h.pinned and "Unpin" or "Pin (keep)") then
        h.pinned = not h.pinned
        ss_save()
      end
      if r.ImGui_Selectable(ctx, "Remove") then
        st._remove_hist = i
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopID(ctx)
  end
  if st._remove_hist then
    table.remove(st.history, st._remove_hist)
    st._remove_hist = nil
    ss_save()
  end
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

local function ss_window_body(st)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or 600
  local dl = r.ImGui_GetWindowDrawList(ctx)

  -- Title row.
  local tx, ty = r.ImGui_GetCursorScreenPos(ctx)
  ss_text(dl, tx, ty, SS_COL.text, "SONG STARTER")
  ss_text(dl, tx + 0.5, ty, SS_COL.text, "SONG STARTER")
  local meta = SS_PLAY and "PLAYING" or "STOPPED"
  local mw = r.ImGui_CalcTextSize(ctx, meta)
  ss_text(dl, tx + avail_w - (mw or 0), ty, SS_PLAY and SS_COL.accent or SS_COL.mute, meta)
  r.ImGui_Dummy(ctx, avail_w, 16)
  local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddLine(dl, lx, ly, lx + avail_w, ly, SS_COL.line, 1)
  r.ImGui_Dummy(ctx, avail_w, 2)

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
  for i, slot in ipairs(st.slots) do
    ss_slot_row(st, slot, i, avail_w)
  end
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

  -- Actions.
  r.ImGui_Dummy(ctx, 1, 2)
  local ax, ay = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddLine(dl, ax, ay, ax + avail_w, ay, SS_COL.line, 1)
  -- Arrangement strip.
  if st.mode == "arrange" then
    r.ImGui_Dummy(ctx, 1, 4)
    ss_draw_arrangement_strip(st, avail_w)
  end

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
  if ss_btn("##ss_save", "SAVE", nil, 26, false, "Pin this starter in the list below") then
    if ss_history_push(st, true) then sm_notify("Song Starter saved.") end
  end
  r.ImGui_SameLine(ctx, 0, 6)
  if ss_btn("##ss_add", "ADD TO PROJECT", nil, 26, false, st.mode == "arrange"
      and "Folder track with one track per unmuted slot, an item per section and a region per section, at the edit cursor"
      or "Folder track with one track per unmuted slot, at the edit cursor") then
    ss_add_to_project()
  end
  r.ImGui_SameLine(ctx, 0, 10)
  local tc, tv = r.ImGui_Checkbox(ctx, "Set project tempo", st.set_tempo == true)
  if tc then
    st.set_tempo = tv and true or false
    ss_save()
  end

  -- History.
  r.ImGui_Dummy(ctx, 1, 4)
  ss_label("Recent")
  local _, rest_h = r.ImGui_GetContentRegionAvail(ctx)
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

  if r.ImGui_BeginChild(ctx, "##ss_history", 0, math.max(60, tonumber(rest_h) or 120), 0) then
    ss_history_list(st)
    r.ImGui_EndChild(ctx)
  end

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
    sm_mono_space_backdrop()
    local ok, err = pcall(ss_window_body, st)
    if not ok and sm_report_error then
      sm_report_error("Song Starter", err)
    end
  end
  end_window(visible, true)
  r.ImGui_PopStyleVar(ctx, nv)
  r.ImGui_PopStyleColor(ctx, nc)
end

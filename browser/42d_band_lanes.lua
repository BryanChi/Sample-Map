-- Sample Map Browser module: band_lanes
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
-- Band lanes: Song Starter's melodic roles (bass, chords, lead...) as lanes
-- under the sequencer's drum tracks. Every sequencer region gets a loop per
-- lane, picked with Song Starter's picker at the project tempo, one band key
-- and the region's kit genres; the section names (Intro, Verse, Chorus...)
-- decide who plays where (SS_PRESENCE). Repeats of a section (Chorus 1,
-- Chorus 2) share their loop unless unlinked. Loops are real looped items on
-- a "Band" folder of tracks and follow the regions; the state lives in the
-- project (ExtState BAND_EXT_KEY) and rides in the sequencer undo snapshots.
local r = reaper

BAND_EXT_KEY = "SequencerBandV1"
BAND_EXT_ITEM = "P_EXT:SampleMapBand"     -- item tag: "<lane id>|<region id>"
BAND_EXT_SIG = "P_EXT:SampleMapBandSig"   -- item signature: path, place, rate, pitch, volume
BAND_EXT_TRACK = "P_EXT:SampleMapBandLane" -- track tag: lane id, or "folder"
BAND_FOLDER_NAME = "Band"
BAND_ROLES = { "bass", "chords", "lead", "texture", "top" }
BAND_DEFAULT_ROLES = { "bass", "chords", "lead" }
BAND_SHORT = { bass = "Bass", chords = "Chords", lead = "Lead", texture = "Texture", top = "Perc" }
BAND_GENRE_BONUS = 1.5 -- score added to loops tagged with the region's kit genre
BAND_HEAD_H = 22
BAND_LANE_H = 44
BAND_ADD_H = 22

-- Sequencer section (seq_parse_region_section) -> Song Starter section type
-- (SS_PRESENCE). Names that are no section (Region 3) let every lane play.
BAND_SECTION_TYPE = {
  intro = "intro", verse = "verse", prechorus = "pre", chorus = "chorus", postchorus = "chorus",
  refrain = "hook", bridge = "breakdown", breakdown = "breakdown", solo = "chorus", interlude = "breakdown",
  instrumental = "chorus", build = "build", drop = "drop", outro = "outro", tag = "outro",
}

BAND_VER = 0          -- bumped by every change to the band state (sync signature)
BAND_SYNC_SIG = nil   -- regions + state the items were last placed for
BAND_LAST_EXT = nil   -- ExtState text last written / read
BAND_TOKEN = nil      -- project the state was loaded from (loaded_project_token)
BAND_SEEN_CC = nil    -- project change count last looked at
BAND_UI = {}          -- menu targets, runtime only

---------------------------------------------------------------------------
-- State and persistence
---------------------------------------------------------------------------

function band_new_state()
  return { v = 1, on = false, key = nil, key_auto = true, next_id = 0, lanes = {}, cells = {}, unlinked = {} }
end

-- Saved state read back: unknown roles and broken entries dropped.
function band_normalize(cfg)
  local b = band_new_state()
  if type(cfg) ~= "table" then
    return b
  end
  b.on = cfg.on == true
  b.key = ss_norm_key(cfg.key)
  b.key_auto = cfg.key_auto ~= false
  b.chaos = tonumber(cfg.chaos)
  b.folder_guid = type(cfg.folder_guid) == "string" and cfg.folder_guid or nil
  b.next_id = tonumber(cfg.next_id) or 0
  for _, lane in ipairs(type(cfg.lanes) == "table" and cfg.lanes or {}) do
    if type(lane) == "table" and tonumber(lane.id) and SS_ROLE[lane.role] and lane.role ~= "drums" then
      lane.id = math.floor(tonumber(lane.id))
      b.lanes[#b.lanes + 1] = lane
      b.next_id = math.max(b.next_id, lane.id)
    end
  end
  for k, cell in pairs(type(cfg.cells) == "table" and cfg.cells or {}) do
    if type(k) == "string" and type(cell) == "table" then
      b.cells[k] = cell
    end
  end
  for k, v in pairs(type(cfg.unlinked) == "table" and cfg.unlinked or {}) do
    if v then b.unlinked[tostring(k)] = true end
  end
  return b
end

function band_state()
  local b = state.seq_band
  if type(b) ~= "table" or type(b.lanes) ~= "table" or type(b.cells) ~= "table" then
    b = band_normalize(b)
    state.seq_band = b
  end
  b.unlinked = b.unlinked or {}
  return b
end

function band_touch()
  BAND_VER = BAND_VER + 1
end

function band_save()
  local b = band_state()
  if not r.SetProjExtState or not json_encode then
    return
  end
  local proj = get_current_project and get_current_project() or 0
  local ok, text = pcall(json_encode, b)
  if not ok or type(text) ~= "string" or text == BAND_LAST_EXT then
    return
  end
  if pcall(r.SetProjExtState, proj, PROJ_EXT_SECTION, BAND_EXT_KEY, text) then
    BAND_LAST_EXT = text
  end
end

function band_read_ext(proj)
  if not r.GetProjExtState then
    return ""
  end
  local ok, text = r.GetProjExtState(proj or 0, PROJ_EXT_SECTION, BAND_EXT_KEY)
  if ok and ok ~= 0 and type(text) == "string" then
    return text
  end
  return ""
end

function band_load(proj)
  local text = band_read_ext(proj)
  local b
  if text ~= "" then
    local ok, cfg = pcall(json_decode, text)
    if ok and type(cfg) == "table" then
      b = band_normalize(cfg)
    end
  end
  state.seq_band = b or band_new_state()
  BAND_LAST_EXT = text ~= "" and text or nil
  BAND_SYNC_SIG = nil
  band_touch()
end

state.seq_band = state.seq_band or band_new_state()

---------------------------------------------------------------------------
-- Pure logic: sections, groups, picks, item placement
---------------------------------------------------------------------------

function band_role_label(role)
  return BAND_SHORT[role] or (SS_ROLE[role] and SS_ROLE[role].label) or tostring(role)
end

-- Song Starter section type for a region name, or nil (no section name).
function band_section_type(name)
  local key = seq_parse_region_section and seq_parse_region_section(name)
  return key and BAND_SECTION_TYPE[key] or nil
end

-- What `role` plays in a section named `name` of `bars` bars, from Song
-- Starter's textbook presence: { from, to (bars into the region), vol, rise },
-- or nil when it sits out.
function band_default_part(role, name, bars)
  bars = math.max(1, math.floor(tonumber(bars) or 4))
  local typ = band_section_type(name)
  local rule = {}
  if typ then
    local rules = SS_PRESENCE[typ] or {}
    rule = rules[role] or rules["*"]
    if not rule then
      return nil
    end
  end
  local from = math.floor((rule.from or 0) * bars + 0.5)
  local to = math.floor((rule.to or 1) * bars + 0.5)
  if to <= from then
    from, to = 0, bars
  end
  return { from = from, to = to, vol = rule.vol or 1.0, rise = rule.rise or nil }
end

-- Loop group of a region: its section ("chorus" for Chorus 1 and Chorus 2),
-- or the region alone ("r<id>") when unlinked or not named as a section.
function band_group_key(b, region)
  if b.unlinked[tostring(region.id)] then
    return "r" .. tostring(region.id)
  end
  local key = seq_parse_region_section and seq_parse_region_section(region.name)
  return key or ("r" .. tostring(region.id))
end

function band_cell_key(b, lane, region)
  return tostring(lane.id) .. ":" .. band_group_key(b, region)
end

-- Part, cell key and cell of lane in region. part nil: the lane sits out
-- (by the section rules, or cleared); cell nil: nothing picked yet.
function band_cell_info(b, lane, region)
  local key = band_cell_key(b, lane, region)
  local cell = b.cells[key]
  if cell and cell.off then
    return nil, key, cell
  end
  local part = band_default_part(lane.role, region.name, region.length_bars)
  if not part and cell and cell.on then
    part = { from = 0, to = math.max(1, math.floor(region.length_bars or 4)), vol = 1.0 }
  end
  return part, key, cell
end

-- Regions whose cell for lane is `key`, in time order.
function band_key_regions(b, lane, key)
  local out = {}
  for _, reg in ipairs(state.seq_regions or {}) do
    if band_cell_key(b, lane, reg) == key then
      out[#out + 1] = reg
    end
  end
  table.sort(out, function(a, c) return (a.start_qn or 0) < (c.start_qn or 0) end)
  return out
end

-- Lanes, melodic roles first (an automatic key comes from their picks).
function band_lanes_melodic_first(b)
  local list = {}
  for i, lane in ipairs(b.lanes) do list[i] = { lane = lane, i = i } end
  table.sort(list, function(a, c)
    local am = SS_ROLE[a.lane.role] and SS_ROLE[a.lane.role].melodic and 0 or 1
    local cm = SS_ROLE[c.lane.role] and SS_ROLE[c.lane.role].melodic and 0 or 1
    if am ~= cm then return am < cm end
    return a.i < c.i
  end)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.lane end
  return out
end

function band_time(qn)
  local t = qn_to_time and qn_to_time(qn)
  if t then
    return t
  end
  return qn * 60.0 / ss_project_bpm()
end

-- Quarter-note tempo across a region (the tempo its loops are stretched to).
function band_region_bpm(region)
  local s = region.start_qn or 0
  local len = get_seq_region_length_qn(region)
  local t0, t1 = band_time(s), band_time(s + len)
  if t0 and t1 and t1 > t0 then
    return len * 60.0 / (t1 - t0)
  end
  return ss_project_bpm()
end

function band_genre_set(region)
  local set, any = {}, false
  for _, g in ipairs(get_seq_region_kit_genres and get_seq_region_kit_genres(region) or {}) do
    set[tostring(g):lower()] = true
    any = true
  end
  return any and set or nil
end

function band_sample_has_genre(s, set)
  for _, t in ipairs(type(s.tags) == "table" and s.tags or {}) do
    if set[tostring(t):lower()] then
      return true
    end
  end
  return false
end

-- Pick a loop for role with Song Starter's candidates and relax levels (as
-- ss_pick_for_slot); loops tagged with the region's kit genre score higher.
-- ctx: pool, bpm, key, chaos, used / recent (path sets), current, genres. -> candidate or nil.
function band_pick(role, ctx)
  local chaos = ctx.chaos or 0
  local levels = { chaos }
  if chaos < 0.65 then levels[#levels + 1] = math.min(1.0, chaos + 0.35) end
  if levels[#levels] < 1.0 then levels[#levels + 1] = 1.0 end
  for li, c in ipairs(levels) do
    local P = ss_chaos_params(c)
    local exclude = {}
    for p in pairs(ctx.used or {}) do exclude[p] = true end
    for p in pairs(ctx.recent or {}) do exclude[p] = true end
    local cands = ss_candidates(ctx.pool, role, ctx.bpm, ctx.key, P, exclude)
    if #cands == 0 then
      -- Everything fitting was heard lately: allow repeats (not other lanes' loops).
      cands = ss_candidates(ctx.pool, role, ctx.bpm, ctx.key, P, ctx.used)
      if #cands > 1 and ctx.current then
        for i = #cands, 1, -1 do
          if cands[i].path == ctx.current then table.remove(cands, i) end
        end
      end
    end
    if ctx.genres then
      for _, cd in ipairs(cands) do
        if cd.sample and band_sample_has_genre(cd.sample, ctx.genres) then
          cd.score = cd.score + BAND_GENRE_BONUS
          cd.genre = true
        end
      end
    end
    local pick = ss_weighted_pick(cands, c)
    if pick then
      pick.relaxed = li > 1 or nil
      return pick
    end
  end
  return nil
end

-- Picking context for one action: the loop pool (Song Starter's scope and
-- search) and the chaos (Song Starter's slider unless the band has its own).
function band_ctx(b)
  local st = ss_state()
  return { pool = ss_loop_pool(st), chaos = b.chaos or st.chaos or 0.25 }
end

-- New loop for cell `key` of lane. Locked cells stay. -> true when it changed.
function band_roll_key(b, lane, key, ctx)
  local cell = b.cells[key]
  if cell and cell.locked then
    return false
  end
  local region = band_key_regions(b, lane, key)[1]
  if not region then
    return false
  end
  local group = key:match("^%d+:(.*)$")
  local used = {}
  for k, c in pairs(b.cells) do
    if k ~= key and c.path and not c.off and k:match("^%d+:(.*)$") == group then
      used[c.path] = true
    end
  end
  cell = cell or {}
  cell.role = lane.role
  b.cells[key] = cell
  local recent = {}
  for _, p in ipairs(cell.recent or {}) do recent[p] = true end
  if cell.path then recent[cell.path] = true end
  local pick = band_pick(lane.role, {
    pool = ctx.pool, bpm = band_region_bpm(region), key = b.key, chaos = ctx.chaos,
    used = used, recent = recent, current = cell.path, genres = band_genre_set(region),
  })
  if not pick then
    cell.no_match = true
    return false
  end
  ss_slot_take(cell, pick)
  cell.genre = pick.genre or nil
  cell.relaxed = pick.relaxed
  if not b.key and pick.key and SS_ROLE[lane.role] and SS_ROLE[lane.role].melodic then
    b.key = ss_norm_key(pick.key)
  end
  return true
end

-- Every unlocked cell of lane that plays somewhere. -> cells changed.
function band_roll_lane(b, lane, ctx)
  local seen, n = {}, 0
  for _, reg in ipairs(state.seq_regions or {}) do
    local part, key = band_cell_info(b, lane, reg)
    if part and not seen[key] then
      seen[key] = true
      if band_roll_key(b, lane, key, ctx) then n = n + 1 end
    end
  end
  return n
end

-- Every unlocked lane. -> cells changed.
function band_roll_all(b, ctx)
  local n = 0
  for _, lane in ipairs(band_lanes_melodic_first(b)) do
    if not lane.locked then
      n = n + band_roll_lane(b, lane, ctx)
    end
  end
  return n
end

-- Pick for every playing cell with no loop yet (new lanes, new sections).
-- ctx is built only when something needs a pick. -> cells picked.
function band_fill_missing(b, ctx)
  local seen, n = {}, 0
  for _, lane in ipairs(band_lanes_melodic_first(b)) do
    for _, reg in ipairs(state.seq_regions or {}) do
      local part, key, cell = band_cell_info(b, lane, reg)
      if part and not seen[key] and not (cell and (cell.path or cell.no_match)) then
        seen[key] = true
        ctx = ctx or band_ctx(b)
        if #ctx.pool == 0 then
          return n -- library not loaded / nothing in scope: try again later
        end
        if band_roll_key(b, lane, key, ctx) then n = n + 1 end
      end
    end
  end
  return n
end

-- Key of the first locked melodic cell, for an automatic key that keeps locks.
function band_locked_key(b)
  for _, lane in ipairs(band_lanes_melodic_first(b)) do
    if SS_ROLE[lane.role] and SS_ROLE[lane.role].melodic then
      for k, cell in pairs(b.cells) do
        if cell.locked and cell.path and cell.src_key and k:match("^(%d+):") == tostring(lane.id) then
          return ss_norm_key(cell.src_key)
        end
      end
    end
  end
  return nil
end

-- Placement of one loop: the part's bars of the region, stretched to the
-- region's tempo (half / double time allowed) and pitched to the band key.
-- -> { pos, len (seconds), rate, shift, vol, rise, path, name, tag, sig } or nil.
function band_item_spec(b, lane, cell, region, part)
  local s = region.start_qn or 0
  local len_qn = get_seq_region_length_qn(region)
  local bars = math.max(1, math.floor(region.length_bars or 4))
  local bar_qn = len_qn / bars
  local q0 = s + math.max(0, part.from or 0) * bar_qn
  local q1 = s + math.min(bars, part.to or bars) * bar_qn
  local t0, t1 = band_time(q0), band_time(q1)
  if not t0 or not t1 or t1 <= t0 + 1e-6 then
    return nil
  end
  local bpm = band_region_bpm(region)
  local rate = ss_stretch(cell.src_bpm, bpm, true)
  local role = SS_ROLE[cell.from_role or lane.role] or SS_ROLE[lane.role]
  local shift = 0
  if role and role.pitched and cell.src_key and b.key then
    shift = ss_pitch_shift(cell.src_key, b.key) or 0
  end
  local vol = (tonumber(lane.vol) or 1.0) * (part.vol or 1.0)
  local tag = tostring(lane.id) .. "|" .. tostring(region.id)
  local sig = string.format("%s|%.6f|%.6f|%.6f|%d|%.4f|%s", tostring(cell.path), t0, t1 - t0, rate, shift, vol,
    part.rise and "rise" or "")
  return { lane = lane, region = region, cell = cell, path = cell.path, name = cell.name, pos = t0, len = t1 - t0,
    rate = rate, shift = shift, vol = vol, rise = part.rise, tag = tag, sig = sig }
end

-- Items the band wants: one per lane and region that plays a loop.
function band_desired_items(b)
  local out = {}
  for _, lane in ipairs(b.lanes) do
    for _, reg in ipairs(state.seq_regions or {}) do
      local part, _, cell = band_cell_info(b, lane, reg)
      if part and cell and cell.path then
        local spec = band_item_spec(b, lane, cell, reg, part)
        if spec then out[#out + 1] = spec end
      end
    end
  end
  return out
end

-- Regions, their times and the band state, as one string: items are placed
-- again when it changes (regions moved / resized / added / deleted, tempo).
function band_regions_sig()
  local parts = { tostring(BAND_VER) }
  for _, reg in ipairs(state.seq_regions or {}) do
    local s = reg.start_qn or 0
    local len = get_seq_region_length_qn(reg)
    parts[#parts + 1] = string.format("%s|%s|%.6f|%.6f|%.6f|%.6f", tostring(reg.id), tostring(reg.name), s, len,
      band_time(s) or 0, band_time(s + len) or 0)
  end
  return table.concat(parts, ";")
end

---------------------------------------------------------------------------
-- Tracks and items
---------------------------------------------------------------------------

local function band_native_color(rgba)
  local rr, gg, bb = (rgba >> 24) & 0xFF, (rgba >> 16) & 0xFF, (rgba >> 8) & 0xFF
  local c = r.ColorToNative and r.ColorToNative(rr, gg, bb) or ((bb << 16) | (gg << 8) | rr)
  return c | 0x1000000
end

function band_lane_track(lane)
  return lane.guid and get_track_by_guid(lane.guid) or nil
end

-- The "Band" folder track, right after the sequencer's drum folder (or at the
-- end); created when `create`.
function band_folder_track(b, create)
  local tr = b.folder_guid and get_track_by_guid(b.folder_guid) or nil
  if tr or not create then
    return tr
  end
  local idx = r.CountTracks(0)
  local seq_folder = find_seq_parent_folder_track and find_seq_parent_folder_track()
  if seq_folder then
    local last = seq_folder_last_child_index(seq_folder)
    if last then idx = last + 1 end
  end
  r.InsertTrackAtIndex(idx, true)
  tr = r.GetTrack(0, idx)
  if not tr then
    return nil
  end
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", BAND_FOLDER_NAME, true)
  r.GetSetMediaTrackInfo_String(tr, BAND_EXT_TRACK, "folder", true)
  r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
  b.folder_guid = r.GetTrackGUID(tr)
  return tr
end

-- New track for lane, last in the Band folder.
function band_make_lane_track(b, lane)
  local folder = band_folder_track(b, true)
  local tr
  if folder then
    local last_idx, has_children = seq_folder_last_child_index(folder)
    local insert_idx = (last_idx or seq_get_media_track_index(folder) or (r.CountTracks(0) - 1)) + 1
    r.InsertTrackAtIndex(insert_idx, true)
    tr = r.GetTrack(0, insert_idx)
    if tr then
      if not has_children then
        r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
      else
        local prev = r.GetTrack(0, last_idx)
        local prev_d = prev and r.GetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH") or 0
        if prev then r.SetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH", prev_d < 0 and prev_d + 1 or 0) end
      end
      r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", -1)
    end
  else
    local idx = r.CountTracks(0)
    r.InsertTrackAtIndex(idx, true)
    tr = r.GetTrack(0, idx)
  end
  if not tr then
    return nil
  end
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", band_role_label(lane.role), true)
  r.GetSetMediaTrackInfo_String(tr, BAND_EXT_TRACK, tostring(lane.id), true)
  if SS_ROLE_COL and SS_ROLE_COL[lane.role] then
    r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", band_native_color(SS_ROLE_COL[lane.role]))
  end
  lane.guid = r.GetTrackGUID(tr)
  return tr
end

function band_add_lane(b, role)
  b.next_id = (b.next_id or 0) + 1
  local lane = { id = b.next_id, role = role, vol = 1.0 }
  b.lanes[#b.lanes + 1] = lane
  band_make_lane_track(b, lane)
  return lane
end

-- Delete a lane track, handing its folder end to the track above.
function band_delete_track(tr)
  if not tr or not r.DeleteTrack then
    return
  end
  local d = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
  local idx = seq_get_media_track_index(tr)
  if d < 0 and idx and idx > 0 then
    local prev = r.GetTrack(0, idx - 1)
    if prev then
      r.SetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH", (r.GetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH") or 0) + d)
    end
  end
  r.DeleteTrack(tr)
end

function band_remove_lane(b, lane)
  for i, l in ipairs(b.lanes) do
    if l == lane then table.remove(b.lanes, i) break end
  end
  local prefix = tostring(lane.id) .. ":"
  for k in pairs(b.cells) do
    if k:sub(1, #prefix) == prefix then b.cells[k] = nil end
  end
  band_delete_track(band_lane_track(lane))
  if #b.lanes == 0 then
    band_delete_track(band_folder_track(b, false))
    b.folder_guid = nil
  end
end

-- A lane whose track was deleted in the arrange goes too. -> true when any went.
function band_prune_lanes(b)
  local gone = false
  for i = #b.lanes, 1, -1 do
    local lane = b.lanes[i]
    if lane.guid and not get_track_by_guid(lane.guid) then
      local prefix = tostring(lane.id) .. ":"
      for k in pairs(b.cells) do
        if k:sub(1, #prefix) == prefix then b.cells[k] = nil end
      end
      table.remove(b.lanes, i)
      gone = true
    end
  end
  return gone
end

function band_place_item(tr, w)
  local item = r.AddMediaItemToTrack(tr)
  if not item then
    return nil
  end
  local take = r.AddTakeToMediaItem(item)
  local src = r.PCM_Source_CreateFromFile(w.path)
  if take and src then
    r.SetMediaItemTake_Source(take, src)
    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", w.rate)
    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
    r.SetMediaItemTakeInfo_Value(take, "D_PITCH", w.shift)
    r.SetMediaItemTakeInfo_Value(take, "D_VOL", w.vol)
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", (w.name or "") .. " - " .. tostring(w.region.name or ""), true)
  end
  r.SetMediaItemInfo_Value(item, "D_POSITION", w.pos)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", w.len)
  r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
  if w.rise then
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN", w.len)
    r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 1)
  else
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN", SS_EDGE_FADE or 0.008)
  end
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", SS_EDGE_FADE or 0.008)
  set_item_ext(item, BAND_EXT_ITEM, w.tag)
  set_item_ext(item, BAND_EXT_SIG, w.sig)
  return item
end

-- Make the lane tracks' band items match band_desired_items: unchanged items
-- stay, changed ones are placed again, items of no lane / region go.
-- Untagged items on the lane tracks are the user's and stay. -> items written.
function band_sync_items(b)
  b = b or band_state()
  if not r.AddMediaItemToTrack or not r.CountTrackMediaItems then
    return 0
  end
  local by_lane = {}
  for _, w in ipairs(band_desired_items(b)) do
    local list = by_lane[w.lane]
    if not list then
      list = {}
      by_lane[w.lane] = list
    end
    list[#list + 1] = w
  end
  local count_before = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0)
  local writes, added = 0, {}
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  for _, lane in ipairs(b.lanes) do
    local tr = band_lane_track(lane)
    if tr then
      local want, have = {}, {}
      for _, w in ipairs(by_lane[lane] or {}) do want[w.tag] = w end
      for i = r.CountTrackMediaItems(tr) - 1, 0, -1 do
        local item = r.GetTrackMediaItem(tr, i)
        local tag = get_item_ext(item, BAND_EXT_ITEM)
        if tag and tag ~= "" then
          local w = want[tag]
          if w and not have[tag] and get_item_ext(item, BAND_EXT_SIG) == w.sig then
            have[tag] = true
          else
            r.DeleteTrackMediaItem(tr, item)
            writes = writes + 1
          end
        end
      end
      for _, w in ipairs(by_lane[lane] or {}) do
        if not have[w.tag] then
          local item = band_place_item(tr, w)
          if item then
            added[#added + 1] = item
            writes = writes + 1
          end
        end
      end
    end
  end
  if #added > 0 and ss_rebuild_peaks then
    ss_rebuild_peaks(added)
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  if writes > 0 then
    r.UpdateArrange()
    -- Our own writes are no arrange edit for the sequencer's ingest to scan
    -- (none of them touch a drum track).
    if seq_mark_self_arrange_write and count_before and state.seq_last_proj_change == count_before then
      seq_mark_self_arrange_write(false)
    end
  end
  return writes
end

-- After a sequencer undo / redo restored state.seq_band: tracks back for
-- lanes that came back, lane tracks of lanes that went removed, items placed.
function seq_band_after_undo()
  local b = band_state()
  local live = {}
  for _, lane in ipairs(b.lanes) do
    if not band_lane_track(lane) then
      band_make_lane_track(b, lane)
    end
    live[tostring(lane.id)] = true
  end
  if r.CountTracks and r.GetSetMediaTrackInfo_String then
    for i = r.CountTracks(0) - 1, 0, -1 do
      local tr = r.GetTrack(0, i)
      local ok, id = r.GetSetMediaTrackInfo_String(tr, BAND_EXT_TRACK, "", false)
      if ok and id ~= "" and id ~= "folder" and not live[id] then
        band_delete_track(tr)
      end
    end
  end
  if #b.lanes == 0 and b.folder_guid then
    band_delete_track(band_folder_track(b, false))
    b.folder_guid = nil
  end
  band_touch()
  band_sync_items(b)
  band_save()
  BAND_SYNC_SIG = band_regions_sig()
end

-- One user action: one undo point "Sample Map: band <label>" (a sequencer
-- undo entry, so Ctrl+Z in Sample Map takes it back too), then items placed
-- and the state saved.
function band_action(label, fn)
  local b = band_state()
  local name = "Sample Map: band " .. label
  local own = seq_undo_own_begin and seq_undo_own_begin(name)
  local native = false
  if not own and not (seq_undo_is_open and seq_undo_is_open()) and r.Undo_BeginBlock2 then
    r.Undo_BeginBlock2(0)
    native = true
  end
  local ok, err = xpcall(fn, function(e)
    return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
  end, b)
  band_touch()
  local ok2, err2 = pcall(band_sync_items, b)
  band_save()
  BAND_SYNC_SIG = band_regions_sig()
  if own then
    end_seq_undo(name)
  elseif native then
    r.Undo_EndBlock2(0, name, -1)
  end
  if not ok then error(err, 0) end
  if not ok2 then error(err2, 0) end
end

-- Each frame (main loop): follow project switches, REAPER undo, deleted lane
-- tracks and region edits; new sections get their loops.
function seq_band_tick()
  local proj = get_current_project and get_current_project()
  if not proj then
    return
  end
  if BAND_TOKEN ~= loaded_project_token then
    BAND_TOKEN = loaded_project_token
    band_load(proj)
  end
  if seq_undo_applying or (seq_undo_is_open and seq_undo_is_open()) or state.seq_region_drag then
    return
  end
  local cc = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0)
  if cc ~= BAND_SEEN_CC then
    BAND_SEEN_CC = cc
    if band_read_ext(proj) ~= (BAND_LAST_EXT or "") then
      -- REAPER's own undo / redo (or another script) changed the saved state.
      band_load(proj)
    end
    if band_prune_lanes(band_state()) then
      band_touch()
      band_save()
    end
  end
  local b = band_state()
  if #b.lanes == 0 then
    return
  end
  local sig = band_regions_sig()
  if sig == BAND_SYNC_SIG then
    return
  end
  local picked = band_fill_missing(b)
  band_sync_items(b)
  if picked > 0 then
    band_touch()
    band_save()
  end
  BAND_SYNC_SIG = band_regions_sig()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function band_region_by_id(id)
  return get_seq_region_by_id and get_seq_region_by_id(id) or nil
end

function band_lane_by_id(b, id)
  for _, lane in ipairs(b.lanes) do
    if lane.id == id then return lane end
  end
  return nil
end

function band_set_on(on)
  band_action(on and "on" or "off", function(b)
    b.on = on and true or false
    if b.on and #b.lanes == 0 then
      for _, role in ipairs(BAND_DEFAULT_ROLES) do band_add_lane(b, role) end
      local ctx = band_ctx(b)
      if #ctx.pool == 0 then
        sm_notify("Band: no loops in the library yet (loops are files tagged Loop).", "warn")
      end
      band_fill_missing(b, ctx)
    end
    local folder = band_folder_track(b, false)
    if folder then
      r.SetMediaTrackInfo_Value(folder, "B_MUTE", b.on and 0 or 1)
    end
  end)
end

function band_ui_add_lane(role)
  band_action("add " .. band_role_label(role), function(b)
    local lane = band_add_lane(b, role)
    local ctx = band_ctx(b)
    band_roll_lane(b, lane, ctx)
  end)
end

function band_ui_remove_lane(lane_id)
  band_action("remove lane", function(b)
    local lane = band_lane_by_id(b, lane_id)
    if lane then band_remove_lane(b, lane) end
  end)
end

function band_ui_roll_cell(lane_id, region_id)
  band_action("roll section", function(b)
    local lane, region = band_lane_by_id(b, lane_id), band_region_by_id(region_id)
    if not lane or not region then return end
    local part, key, cell = band_cell_info(b, lane, region)
    if cell and cell.locked then
      sm_notify("Band: that section is locked.", "warn")
      return
    end
    if not part then
      -- An empty cell: this lane joins the section.
      cell = cell or {}
      cell.off, cell.on = nil, true
      b.cells[key] = cell
    end
    if cell then cell.no_match = nil end
    if not band_roll_key(b, lane, key, band_ctx(b)) then
      sm_notify("Band: no matching " .. band_role_label(lane.role) .. " loop for " .. tostring(region.name) .. ".", "warn")
    end
  end)
end

function band_ui_roll_lane(lane_id)
  band_action("roll lane", function(b)
    local lane = band_lane_by_id(b, lane_id)
    if lane then band_roll_lane(b, lane, band_ctx(b)) end
  end)
end

function band_ui_roll_all()
  band_action("roll all", function(b)
    for _, cell in pairs(b.cells) do cell.no_match = nil end
    band_roll_all(b, band_ctx(b))
  end)
end

function band_ui_lock_cell(lane_id, region_id)
  band_action("lock", function(b)
    local lane, region = band_lane_by_id(b, lane_id), band_region_by_id(region_id)
    if not lane or not region then return end
    local _, key, cell = band_cell_info(b, lane, region)
    if cell and cell.path then cell.locked = not cell.locked or nil end
    b.cells[key] = cell
  end)
end

function band_ui_lock_lane(lane_id)
  band_action("lock lane", function(b)
    local lane = band_lane_by_id(b, lane_id)
    if lane then lane.locked = not lane.locked or nil end
  end)
end

function band_ui_clear_cell(lane_id, region_id)
  band_action("clear section", function(b)
    local lane, region = band_lane_by_id(b, lane_id), band_region_by_id(region_id)
    if not lane or not region then return end
    local _, key, cell = band_cell_info(b, lane, region)
    cell = cell or { role = lane.role }
    cell.off, cell.on, cell.locked = true, nil, nil
    b.cells[key] = cell
  end)
end

-- Repeats of a section share one loop; unlinking gives one region its own
-- copy to change alone, linking drops that copy.
function band_unlink_region(b, region)
  local own = tostring(region.id)
  if b.unlinked[own] then
    return
  end
  for _, lane in ipairs(b.lanes) do
    local cell = b.cells[band_cell_key(b, lane, region)]
    if cell then
      b.cells[tostring(lane.id) .. ":r" .. own] = clone_table_deep(cell)
    end
  end
  b.unlinked[own] = true
end

function band_link_region(b, region)
  local own = tostring(region.id)
  if not b.unlinked[own] then
    return
  end
  b.unlinked[own] = nil
  for _, lane in ipairs(b.lanes) do
    b.cells[tostring(lane.id) .. ":r" .. own] = nil
  end
end

function band_ui_toggle_link(region_id)
  local b = band_state()
  local region = band_region_by_id(region_id)
  if not region then return end
  local unlinked = b.unlinked[tostring(region.id)]
  band_action(unlinked and "link section" or "unlink section", function(bb)
    if unlinked then band_link_region(bb, region) else band_unlink_region(bb, region) end
  end)
end

-- Put file s (library sample or bare table) into the cell; it plays there.
function band_ui_pick_file(lane_id, region_id, s)
  band_action("pick from folder", function(b)
    local lane, region = band_lane_by_id(b, lane_id), band_region_by_id(region_id)
    if not lane or not region or not s then return end
    if s.unscanned and not s.duration and r.PCM_Source_CreateFromFile then
      local src = r.PCM_Source_CreateFromFile(s.path)
      if src then
        s.duration = tonumber((r.GetMediaSourceLength(src)))
        if r.PCM_Source_Destroy then r.PCM_Source_Destroy(src) end
      end
    end
    local part, key, cell = band_cell_info(b, lane, region)
    cell = cell or {}
    cell.role = lane.role
    if not part then cell.off, cell.on = nil, true end
    b.cells[key] = cell
    ss_slot_take(cell, ss_candidate_any(s, lane.role, band_region_bpm(region), b.key))
    cell.dur = tonumber(s.duration) or cell.dur
    cell.relaxed = nil
  end)
end

-- nil key: Auto (a locked loop's key, else from the next picks, which re-roll).
function band_ui_set_key(key)
  band_action("key " .. (key or "auto"), function(b)
    if key then
      b.key, b.key_auto = ss_norm_key(key), false
    else
      b.key_auto = true
      b.key = band_locked_key(b)
      band_roll_all(b, band_ctx(b))
    end
  end)
end

-- Song Starter -> band: one lane per slot (drums stay the sequencer's), its
-- loop in every section the role plays, locked slots locked; the starter's
-- key; then Sample Map shows the Sequencer.
function band_from_song_starter()
  local st = ss_state()
  local slots = {}
  for _, slot in ipairs(st.slots or {}) do
    if slot.role ~= "drums" and SS_ROLE[slot.role] and slot.path and not slot.muted then
      slots[#slots + 1] = slot
    end
  end
  if #slots == 0 then
    sm_notify("Song Starter: no loops to open in the sequencer (drums stay in the sequencer).", "warn")
    return false
  end
  if ensure_default_seq_region then ensure_default_seq_region() end
  band_action("from Song Starter", function(b)
    b.on = true
    if st.target_key then
      b.key, b.key_auto = ss_norm_key(st.target_key), false
    end
    local taken = {}
    for _, slot in ipairs(slots) do
      local lane
      for _, l in ipairs(b.lanes) do
        if l.role == slot.role and not taken[l] then lane = l break end
      end
      lane = lane or band_add_lane(b, slot.role)
      taken[lane] = true
      lane.vol = tonumber(slot.vol) or 1.0
      local prefix = tostring(lane.id) .. ":"
      for k in pairs(b.cells) do
        if k:sub(1, #prefix) == prefix then b.cells[k] = nil end
      end
      for _, reg in ipairs(state.seq_regions or {}) do
        local part, key = band_cell_info(b, lane, reg)
        if part and not b.cells[key] then
          b.cells[key] = {
            role = lane.role, path = slot.path, name = slot.name, src_bpm = slot.src_bpm, bpm_est = slot.bpm_est,
            src_key = slot.src_key, dur = slot.dur, from_role = slot.from_role, rate = slot.rate, mult = slot.mult,
            shift = slot.shift, recent = { slot.path }, locked = slot.locked or nil,
          }
        end
      end
    end
    local folder = band_folder_track(b, false)
    if folder then r.SetMediaTrackInfo_Value(folder, "B_MUTE", 0) end
  end)
  if state.active_view ~= "sequencer" and not state.sequencer_floating then
    state.active_view = "sequencer"
    if save_config then save_config() end
  end
  sm_notify(string.format("Song Starter: %d band lane%s in the sequencer.", #slots, #slots == 1 and "" or "s"))
  return true
end

---------------------------------------------------------------------------
-- Drawing (inside the sequencer's track list, under the drum tracks)
---------------------------------------------------------------------------

function seq_band_height()
  local b = state.seq_band
  if not (type(b) == "table" and b.on and type(b.lanes) == "table") then
    return 0
  end
  return BAND_HEAD_H + #b.lanes * BAND_LANE_H + BAND_ADD_H
end

-- "A min" / "C maj" for "Am" / "C".
function band_key_long(key)
  local pc, minor = ss_parse_key(key)
  if not pc then
    return nil
  end
  return SS_NOTE_NAMES[pc + 1] .. (minor and " min" or " maj")
end

-- "Band fits: 92 BPM · A min · hip-hop kit"
function band_caption(b, region)
  local parts = { string.format("%.0f BPM", ss_project_bpm()), band_key_long(b.key) or "Auto key" }
  local genres = get_seq_region_kit_genres and region and get_seq_region_kit_genres(region) or {}
  if not genres[1] then
    for _, reg in ipairs(state.seq_regions or {}) do
      genres = get_seq_region_kit_genres and get_seq_region_kit_genres(reg) or {}
      if genres[1] then break end
    end
  end
  if genres[1] then
    parts[#parts + 1] = tostring(genres[1]):lower() .. " kit"
  end
  return "Band fits: " .. table.concat(parts, " · ")
end

function band_role_col(role, alpha)
  local c = (SS_ROLE_COL and SS_ROLE_COL[role]) or SS_COL.accent
  return (c & 0xFFFFFF00) | (alpha or 0xFF)
end

-- Waveform thumbnail per path: 64 peak heights 0..1 from REAPER's peak files
-- (false while there are none yet; one read per frame, misses retried).
BAND_PEAKS = {}
BAND_PEAKS_N = 64
local band_peaks_frame = -1

function band_peaks(path)
  local hit = BAND_PEAKS[path]
  local now = r.time_precise and r.time_precise() or 0
  if hit and (hit.peaks or now < hit.retry) then
    return hit.peaks
  end
  local frame = r.ImGui_GetFrameCount and r.ImGui_GetFrameCount(ctx) or now
  if frame == band_peaks_frame or not (r.PCM_Source_CreateFromFile and r.PCM_Source_GetPeaks and r.new_array) then
    return hit and hit.peaks or false
  end
  band_peaks_frame = frame
  local entry = { peaks = false, retry = now + 3.0 }
  BAND_PEAKS[path] = entry
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then
    return false
  end
  local len = tonumber((r.GetMediaSourceLength(src))) or 0
  local n = BAND_PEAKS_N
  if len > 0 then
    local buf = r.new_array(n * 2)
    local ret = r.PCM_Source_GetPeaks(src, n / len, 0, 1, n, 0, buf)
    local got = (tonumber(ret) or 0) & 0xFFFFF
    if got > 0 then
      local t = buf.table and buf.table() or {}
      local peaks, top = {}, 0.0001
      for i = 1, n do
        local v = math.max(math.abs(t[i] or 0), math.abs(t[n + i] or 0))
        peaks[i] = v
        if v > top then top = v end
      end
      for i = 1, n do peaks[i] = peaks[i] / top end
      entry.peaks = peaks
    end
  end
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(src) end
  return entry.peaks
end

local function band_text(dl, x, y, col, s)
  r.ImGui_DrawList_AddText(dl, x, y, col, s)
end

local function band_dashed_rect(dl, x0, y0, x1, y1, col, clip_x0, clip_x1)
  local dash, gap = 4, 3
  local sx = math.max(x0, clip_x0 - ((clip_x0 - x0) % (dash + gap)))
  local ex = math.min(x1, clip_x1)
  local x = sx
  while x < ex do
    local xe = math.min(x + dash, x1)
    r.ImGui_DrawList_AddLine(dl, x, y0, xe, y0, col, 1)
    r.ImGui_DrawList_AddLine(dl, x, y1, xe, y1, col, 1)
    x = x + dash + gap
  end
  local y = y0
  while y < y1 do
    local ye = math.min(y + dash, y1)
    if x0 >= clip_x0 then r.ImGui_DrawList_AddLine(dl, x0, y, x0, ye, col, 1) end
    if x1 <= clip_x1 then r.ImGui_DrawList_AddLine(dl, x1, y, x1, ye, col, 1) end
    y = y + dash + gap
  end
end

-- Small square icon (roll / lock) at cx, cy. -> hovered.
local function band_icon(dl, kind, cx, cy, on, hot, can)
  local s = 8
  local hovered = can and hot
  if hovered then
    r.ImGui_DrawList_AddRectFilled(dl, cx - s, cy - s, cx + s, cy + s, 0xFFFFFF14, 0)
  end
  r.ImGui_DrawList_AddRect(dl, cx - s, cy - s, cx + s, cy + s, on and SS_COL.accent or (hovered and SS_COL.line_hi or SS_COL.line), 0, 0, 1)
  ss_draw_icon(dl, kind, cx, cy - (kind == "lock" and 1.5 or 0), on and SS_COL.accent or (hovered and SS_COL.text or SS_COL.dim), on)
end

local function band_strip_ext(name)
  return (tostring(name or "?"):gsub("%.%w+$", ""))
end

-- g: x0, w, tx0, tx1 (timeline), y0 (band top), view_qn0, qn_span, qn_to_x,
-- region (selected), playhead_qn.
function seq_band_draw(g)
  local b = band_state()
  if not b.on then
    return
  end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local can = r.ImGui_IsWindowHovered(ctx, 0) and not (imgui_any_popup_open and imgui_any_popup_open())
  local lc = can and r.ImGui_IsMouseClicked(ctx, 0)
  local rc = can and r.ImGui_IsMouseClicked(ctx, 1)
  local function hot(x0, y0, x1, y1) return can and mx >= x0 and mx < x1 and my >= y0 and my < y1 end
  local C = SS_COL
  local x0, tx0, tx1 = g.x0, g.tx0, g.tx1
  local x1 = x0 + g.w
  local tw = math.max(1, tx1 - tx0)
  local qn_span = math.max(0.001, g.qn_span)
  local view_qn1 = g.view_qn0 + qn_span
  local function x_to_qn(x) return g.view_qn0 + (x - tx0) / tw * qn_span end
  local y0 = g.y0
  local band_y1 = y0 + seq_band_height()
  local panel_x1 = tx0 - 1
  local action = nil -- run after drawing: { fn, args... }
  local tip = nil

  -- Header: BAND, key chip, roll all | caption.
  local hy1 = y0 + BAND_HEAD_H
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, band_y1, C.bg, 0)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, hy1, C.panel, 0)
  r.ImGui_DrawList_AddLine(dl, x0, y0, x1, y0, C.line_hi, 1)
  r.ImGui_DrawList_AddLine(dl, x0, hy1, x1, hy1, C.line, 1)
  band_text(dl, x0 + 10, y0 + 4, C.accent, "BAND")
  local roll_cx = panel_x1 - 14
  local key_label = "KEY " .. (b.key or "AUTO") .. (b.key_auto and b.key and "*" or "")
  local kw = r.ImGui_CalcTextSize(ctx, key_label) + 12
  local kx1 = roll_cx - 12
  local kx0 = kx1 - kw
  local key_hot = hot(kx0, y0 + 3, kx1, hy1 - 3)
  r.ImGui_DrawList_AddRect(dl, kx0, y0 + 3, kx1, hy1 - 3, key_hot and C.line_hi or C.line, 0, 0, 1)
  band_text(dl, kx0 + 6, y0 + 4, key_hot and C.text or C.dim, key_label)
  if key_hot then
    tip = "Band key: every loop is pitched to it.\nClick to choose (Auto: from the first melodic pick" .. (b.key_auto and b.key and ", * = auto)" or ")")
    if lc then
      r.ImGui_OpenPopup(ctx, "##band_key_menu")
    end
  end
  local roll_hot = hot(roll_cx - 8, y0 + 3, roll_cx + 8, hy1 - 3)
  band_icon(dl, "roll", roll_cx, y0 + BAND_HEAD_H * 0.5, false, roll_hot, can)
  if roll_hot then
    tip = "Roll every unlocked lane"
    if lc then action = { band_ui_roll_all } end
  end
  band_text(dl, tx0 + 8, y0 + 4, C.dim, band_caption(b, g.region))

  -- Lanes.
  local regions = state.seq_regions or {}
  for li, lane in ipairs(b.lanes) do
    local ly0 = hy1 + (li - 1) * BAND_LANE_H
    local ly1 = ly0 + BAND_LANE_H
    local col = band_role_col(lane.role)
    r.ImGui_DrawList_AddRectFilled(dl, x0, ly0, panel_x1, ly1, C.panel, 0)
    r.ImGui_DrawList_AddRectFilled(dl, x0, ly0, x0 + 3, ly1, col, 0)
    r.ImGui_DrawList_AddLine(dl, x0, ly1, x1, ly1, C.line, 1)
    band_text(dl, x0 + 12, ly0 + 7, C.text, band_role_label(lane.role))
    local n_loops, n_locked = 0, 0
    local prefix = tostring(lane.id) .. ":"
    for k, cell in pairs(b.cells) do
      if k:sub(1, #prefix) == prefix and cell.path and not cell.off then
        n_loops = n_loops + 1
        if cell.locked then n_locked = n_locked + 1 end
      end
    end
    band_text(dl, x0 + 12, ly0 + 24, C.mute, lane.locked and "LOCKED" or
      string.format("%d loop%s%s", n_loops, n_loops == 1 and "" or "s", n_locked > 0 and (" · " .. n_locked .. " locked") or ""))
    local lock_cx = panel_x1 - 14
    local lroll_cx = lock_cx - 22
    local icy = ly0 + BAND_LANE_H * 0.5
    local lroll_hot = hot(lroll_cx - 8, icy - 8, lroll_cx + 8, icy + 8)
    local llock_hot = hot(lock_cx - 8, icy - 8, lock_cx + 8, icy + 8)
    band_icon(dl, "roll", lroll_cx, icy, false, lroll_hot, can)
    band_icon(dl, "lock", lock_cx, icy, lane.locked == true, llock_hot, can)
    if lroll_hot then
      tip = "Roll this lane: new loops for its unlocked sections"
      if lc then action = { band_ui_roll_lane, lane.id } end
    elseif llock_hot then
      tip = lane.locked and "Unlock this lane" or "Lock this lane: Roll all leaves it alone"
      if lc then action = { band_ui_lock_lane, lane.id } end
    elseif hot(x0, ly0, panel_x1, ly1) and rc then
      BAND_UI.lane_menu = lane.id
      r.ImGui_OpenPopup(ctx, "##band_lane_menu")
    end

    -- Cells, one per region.
    if r.ImGui_DrawList_PushClipRect then r.ImGui_DrawList_PushClipRect(dl, tx0, ly0, tx1, ly1, true) end
    for _, reg in ipairs(regions) do
      local s = reg.start_qn or 0
      local e = s + get_seq_region_length_qn(reg)
      if e >= g.view_qn0 and s <= view_qn1 then
        local part, key, cell = band_cell_info(b, lane, reg)
        local cx0, cx1 = g.qn_to_x(s), g.qn_to_x(e)
        r.ImGui_DrawList_AddLine(dl, cx0, ly0, cx0, ly1, C.line, 1)
        local cell_hot = hot(math.max(cx0, tx0), ly0, math.min(cx1, tx1), ly1)
        if part and cell and cell.path then
          local bars = math.max(1, math.floor(reg.length_bars or 4))
          local bar_qn = (e - s) / bars
          local q0, q1 = s + (part.from or 0) * bar_qn, s + (part.to or bars) * bar_qn
          local bx0, bx1 = g.qn_to_x(q0) + 2, g.qn_to_x(q1) - 2
          local by0, by1 = ly0 + 4, ly1 - 4
          r.ImGui_DrawList_AddRectFilled(dl, bx0, by0, bx1, by1, band_role_col(lane.role, cell_hot and 0x30 or 0x1C), 0)
          -- waveform, the loop repeated at its stretched length
          local peaks = band_peaks(cell.path)
          local bpm = band_region_bpm(reg)
          local rate = ss_stretch(cell.src_bpm, bpm, true)
          local dur = tonumber(cell.dur)
          if peaks and dur and dur > 0 then
            local loop_qn = (dur / math.max(0.05, rate)) * bpm / 60.0
            local mid, half = (by0 + by1) * 0.5 + 4, (by1 - by0) * 0.32
            local wcol = band_role_col(lane.role, 0x70)
            local px = math.max(bx0 + 1, tx0)
            local pe = math.min(bx1 - 1, tx1)
            while px < pe do
              local ph = ((x_to_qn(px) - q0) % loop_qn) / loop_qn
              local v = peaks[math.min(BAND_PEAKS_N, math.floor(ph * BAND_PEAKS_N) + 1)] or 0
              local hgt = math.max(0.5, v * half)
              r.ImGui_DrawList_AddLine(dl, px, mid - hgt, px, mid + hgt, wcol, 1)
              px = px + 2
            end
          end
          r.ImGui_DrawList_AddRect(dl, bx0, by0, bx1, by1, band_role_col(lane.role, cell_hot and 0xFF or 0xB0), 0, 0, 1)
          -- loop name, clipped to the block
          if r.ImGui_DrawList_PushClipRect then
            r.ImGui_DrawList_PushClipRect(dl, math.max(bx0, tx0), by0, math.min(bx1 - 4, tx1), by1, true)
          end
          local shown_x = math.max(bx0, tx0) + 5
          band_text(dl, shown_x, by0 + 2, C.text, band_strip_ext(cell.name))
          if r.ImGui_DrawList_PopClipRect then r.ImGui_DrawList_PopClipRect(dl) end
          local rx = math.min(bx1, tx1) - 11
          local cy = by0 + 9
          if cell.locked and not cell_hot then
            ss_draw_icon(dl, "lock", rx, cy - 1, C.accent, true)
          end
          if cell_hot and bx1 - bx0 > 46 then
            local roll_hit = hot(rx - 30, cy - 8, rx - 14, cy + 8)
            local lock_hit = hot(rx - 8, cy - 8, rx + 8, cy + 8)
            band_icon(dl, "roll", rx - 22, cy, false, roll_hit, can)
            band_icon(dl, "lock", rx, cy, cell.locked == true, lock_hit, can)
            if roll_hit then
              tip = cell.locked and "Locked: unlock to roll" or "Roll this section: a new loop"
                .. ((#band_key_regions(b, lane, key) > 1) and " (and its repeats)" or "")
              if lc and not cell.locked then action = { band_ui_roll_cell, lane.id, reg.id } end
            elseif lock_hit then
              tip = cell.locked and "Unlock this section" or "Lock this section: rolls leave it alone"
              if lc then action = { band_ui_lock_cell, lane.id, reg.id } end
            end
          end
          if cell_hot and not tip then
            local shift = (SS_ROLE[lane.role] and SS_ROLE[lane.role].pitched and cell.src_key and b.key)
              and (ss_pitch_shift(cell.src_key, b.key) or 0) or 0
            tip = string.format("%s\n%s · %s%s · %s%s\nHover: roll this section / lock · right-click: clear, pick from folder%s",
              band_strip_ext(cell.name), cell.src_bpm and string.format("%.0f BPM x%.2f", cell.src_bpm, rate) or "BPM ?",
              cell.src_key or "no key", shift ~= 0 and string.format(" %+d st", shift) or "",
              tostring(reg.name or ""), cell.genre and " · kit genre" or "",
              (#band_key_regions(b, lane, key) > 1 or b.unlinked[tostring(reg.id)]) and ", unlink" or "")
          end
        else
          -- Sits out here: dashed cell; click adds a loop.
          local ex0, ex1 = cx0 + 2, cx1 - 2
          if cell_hot then
            r.ImGui_DrawList_AddRectFilled(dl, ex0, ly0 + 4, ex1, ly1 - 4, 0xFFFFFF08, 0)
          end
          band_dashed_rect(dl, ex0, ly0 + 4, ex1, ly1 - 4, cell_hot and C.line_hi or C.line, tx0, tx1)
          if part and cell and cell.no_match then
            band_text(dl, math.max(ex0, tx0) + 6, ly0 + 8, C.warn, "NO MATCH")
          end
          if cell_hot then
            local mid_x = (math.max(ex0, tx0) + math.min(ex1, tx1)) * 0.5
            band_text(dl, mid_x - 4, ly0 + BAND_LANE_H * 0.5 - 8, C.dim, "+")
            tip = string.format("%s sits out %s.\nClick to add a loop here · right-click: pick from folder",
              band_role_label(lane.role), tostring(reg.name or "this section"))
            if lc then action = { band_ui_roll_cell, lane.id, reg.id } end
          end
        end
        if cell_hot and rc then
          BAND_UI.cell_menu = { lane_id = lane.id, region_id = reg.id }
          BAND_UI.folder_list = nil
          r.ImGui_OpenPopup(ctx, "##band_cell_menu")
        end
      end
    end
    if r.ImGui_DrawList_PopClipRect then r.ImGui_DrawList_PopClipRect(dl) end
  end

  -- "+ Role" row.
  local ay0 = hy1 + #b.lanes * BAND_LANE_H
  local ay1 = ay0 + BAND_ADD_H
  local add_hot = hot(x0, ay0, panel_x1, ay1)
  r.ImGui_DrawList_AddRectFilled(dl, x0, ay0, panel_x1, ay1, add_hot and 0xFFFFFF0C or C.bg, 0)
  r.ImGui_DrawList_AddLine(dl, x0, ay1, x1, ay1, C.line, 1)
  band_text(dl, x0 + 12, ay0 + 4, add_hot and C.text or C.mute, "+ Role")
  if add_hot then
    tip = "Add a band lane (a Song Starter role)"
    if lc then r.ImGui_OpenPopup(ctx, "##band_role_menu") end
  end

  -- Playhead through the band.
  if g.playhead_qn and g.playhead_qn >= g.view_qn0 and g.playhead_qn <= view_qn1 then
    local px = g.qn_to_x(g.playhead_qn)
    local playing = r.GetPlayState and (r.GetPlayState() & 1) == 1
    r.ImGui_DrawList_AddLine(dl, px, y0, px, band_y1, playing and 0xFFFF88EE or 0xFFFF8866, playing and 2.0 or 1.5)
  end
  r.ImGui_DrawList_AddLine(dl, tx0, y0, tx0, band_y1, C.line_hi, 1)

  if tip then
    r.ImGui_SetTooltip(ctx, tip)
  end
  band_draw_menus(b)
  if action then
    action[1](table.unpack(action, 2))
  end
end

function band_draw_menus(b)
  if r.ImGui_BeginPopup(ctx, "##band_key_menu") then
    if r.ImGui_Selectable(ctx, "Auto (first melodic loop, re-rolls)", b.key_auto == true) then
      band_ui_set_key(nil)
    end
    r.ImGui_Separator(ctx)
    for _, minor in ipairs({ true, false }) do
      for pc = 0, 11 do
        local k = ss_key_name(pc, minor)
        if r.ImGui_Selectable(ctx, band_key_long(k) .. "##band_key_" .. k, (not b.key_auto) and b.key == k) then
          band_ui_set_key(k)
        end
      end
      if minor then r.ImGui_Separator(ctx) end
    end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "##band_role_menu") then
    for _, role in ipairs(BAND_ROLES) do
      if SS_ROLE[role] and r.ImGui_Selectable(ctx, SS_ROLE[role].label) then
        band_ui_add_lane(role)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "##band_lane_menu") then
    local lane = band_lane_by_id(b, BAND_UI.lane_menu)
    if lane then
      if r.ImGui_Selectable(ctx, "Roll lane") then band_ui_roll_lane(lane.id) end
      if r.ImGui_Selectable(ctx, lane.locked and "Unlock lane" or "Lock lane") then band_ui_lock_lane(lane.id) end
      r.ImGui_Separator(ctx)
      if r.ImGui_Selectable(ctx, "Remove lane (deletes its track)") then band_ui_remove_lane(lane.id) end
    end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "##band_cell_menu") then
    local m = BAND_UI.cell_menu or {}
    local lane, region = band_lane_by_id(b, m.lane_id), band_region_by_id(m.region_id)
    if lane and region then
      local part, key, cell = band_cell_info(b, lane, region)
      local playing = part and cell and cell.path
      if r.ImGui_Selectable(ctx, playing and "Roll this section" or "Add a loop here") and not (cell and cell.locked) then
        band_ui_roll_cell(lane.id, region.id)
      end
      if playing then
        if r.ImGui_Selectable(ctx, cell.locked and "Unlock" or "Lock") then band_ui_lock_cell(lane.id, region.id) end
        if r.ImGui_Selectable(ctx, "Clear (sit out this section)") then band_ui_clear_cell(lane.id, region.id) end
      end
      band_folder_menu(b, lane, region, cell, key)
      local unlinked = b.unlinked[tostring(region.id)]
      if unlinked or #band_key_regions(b, lane, key) > 1 then
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, unlinked and "Link to repeats (share their loops)" or "Unlink from repeats (own loops)") then
          band_ui_toggle_link(region.id)
        end
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

-- "Pick from folder" submenu: the files next to this cell's loop (or the
-- lane's other loops), best fit first.
function band_folder_menu(b, lane, region, cell, key)
  local path = cell and cell.path
  if not path then
    for k, c in pairs(b.cells) do
      if c.path and k:match("^(%d+):") == tostring(lane.id) then path = c.path break end
    end
  end
  if not path then
    return
  end
  if not r.ImGui_BeginMenu(ctx, "Pick from folder") then
    return
  end
  local list = BAND_UI.folder_list
  if not list or BAND_UI.folder_for ~= path then
    local probe = { role = lane.role, path = path }
    list = ss_folder_ranked({ target_bpm = band_region_bpm(region), target_key = b.key }, probe)
    BAND_UI.folder_list, BAND_UI.folder_for = list, path
  end
  if #list == 0 then
    r.ImGui_TextDisabled(ctx, "No other files there")
  end
  for i, c in ipairs(list) do
    if i > 40 then
      r.ImGui_TextDisabled(ctx, string.format("... %d more", #list - 40))
      break
    end
    local s = c.sample or c
    local label = band_strip_ext(s.name or tostring(c.path):match("([^/\\]+)$")) .. (c.loop and "" or "  (one-shot)")
    if r.ImGui_Selectable(ctx, label .. "##band_f" .. i, c.path == (cell and cell.path)) then
      band_ui_pick_file(lane.id, region.id, s)
    end
  end
  r.ImGui_EndMenu(ctx)
end

-- Sequencer toolbar: BAND toggle (after Kit).
function seq_band_toolbar_button(btn_h)
  local b = band_state()
  imgui_same_line_if_fits(calc_compact_chip_width("Band") + 16, 6)
  if draw_ui_button("seq_band_toggle", "Band", nil, btn_h, {
    compact = true, lead_icon = "audio", style = "primary", selected = b.on == true,
  }) then
    band_set_on(not b.on)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, b.on and "Band lanes: on\nClick to hide them and mute the Band folder."
      or "Band lanes: Song Starter loops (bass, chords, lead...) per region under the drums")
  end
end

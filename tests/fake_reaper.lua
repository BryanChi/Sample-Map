-- In-memory stand-in for the parts of the REAPER API the sequencer's arrange
-- sync uses: tracks, items, takes, sources, P_EXT tags, selection, razor
-- edits and the project change counter. Constant 120 BPM in 4/4, so
-- 1 QN = 0.5 s and a bar is 4 QN. Used by tests/test_seq_sync.py.
--
-- Everything else falls back to stubs: ImGui getters return zeros, ImGui
-- predicates false, and unknown API calls return nil.

FAKE = {}

local P -- current project

local function bump()
  P.changes = P.changes + 1
end

function fake_reset()
  P = {
    tracks = {},
    changes = 1,
    next_guid = 1,
    files = {},
    ext = {},
    undo_desc = "",
  }
  FAKE.P = P
end

local function new_guid()
  local g = string.format("{00000000-0000-0000-0000-%012d}", P.next_guid)
  P.next_guid = P.next_guid + 1
  return g
end

function fake_add_file(path, length_sec)
  P.files[path] = length_sec or 1.0
end

function fake_remove_file(path)
  P.files[path] = nil
end

function fake_add_track(name)
  local tr = {
    kind = "track",
    guid = new_guid(),
    name = name or "",
    items = {},
    vals = { D_VOL = 1.0, D_PAN = 0.0, B_MUTE = 0, I_SOLO = 0, I_FOLDERDEPTH = 0 },
    strs = {},
    alive = true,
  }
  P.tracks[#P.tracks + 1] = tr
  bump()
  return tr
end

local function sort_items(tr)
  table.sort(tr.items, function(a, b)
    if a.vals.D_POSITION ~= b.vals.D_POSITION then
      return a.vals.D_POSITION < b.vals.D_POSITION
    end
    return a.serial < b.serial
  end)
end

local item_serial = 0

local function new_item(tr)
  item_serial = item_serial + 1
  local item = {
    kind = "item",
    serial = item_serial,
    track = tr,
    guid = new_guid(),
    vals = {
      D_POSITION = 0.0, D_LENGTH = 1.0, D_VOL = 1.0, B_LOOPSRC = 0, B_MUTE = 0,
      D_FADEINLEN = 0.0, D_FADEOUTLEN = 0.0, C_FADEINSHAPE = 0, C_FADEOUTSHAPE = 0,
      D_SNAPOFFSET = 0.0, I_CUSTOMCOLOR = 0, C_BEATATTACHMODE = 0,
    },
    strs = {},
    takes = {},
    selected = false,
    alive = true,
  }
  tr.items[#tr.items + 1] = item
  return item
end

local function new_take(item, src)
  local take = {
    kind = "take",
    item = item,
    src = src,
    vals = { D_VOL = 1.0, D_PAN = 0.0, D_PITCH = 0.0, D_PLAYRATE = 1.0, D_STARTOFFS = 0.0, I_PITCHMODE = -1 },
    strs = {},
    midi = false,
  }
  item.takes[#item.takes + 1] = take
  item.active = take
  return take
end

local function new_source(path)
  return { kind = "source", file = path, typ = "WAVE" }
end

-- Arrange-side helpers for tests: what a user would do by hand.
function fake_items(tr)
  local out = {}
  local tracks = tr and { tr } or P.tracks
  for _, t in ipairs(tracks) do
    for _, it in ipairs(t.items) do
      out[#out + 1] = it
    end
  end
  return out
end

function fake_user_add_item(tr, pos, len, path)
  local item = new_item(tr)
  item.vals.D_POSITION = pos
  item.vals.D_LENGTH = len or 0.25
  new_take(item, new_source(path))
  sort_items(tr)
  bump()
  return item
end

function fake_user_delete_item(item)
  local tr = item.track
  for i, it in ipairs(tr.items) do
    if it == item then
      table.remove(tr.items, i)
      item.alive = false
      bump()
      return true
    end
  end
  return false
end

function fake_user_move_item(item, pos, dest_track)
  item.vals.D_POSITION = pos
  if dest_track and dest_track ~= item.track then
    for i, it in ipairs(item.track.items) do
      if it == item then
        table.remove(item.track.items, i)
        break
      end
    end
    item.track = dest_track
    dest_track.items[#dest_track.items + 1] = item
  end
  sort_items(item.track)
  bump()
end

function fake_user_set_take(item, key, value)
  item.active.vals[key] = value
  bump()
end

function fake_user_set_track(tr, key, value)
  tr.vals[key] = value
  bump()
end

function fake_select_only(items)
  for _, t in ipairs(P.tracks) do
    for _, it in ipairs(t.items) do
      it.selected = false
    end
  end
  for _, it in ipairs(items or {}) do
    it.selected = true
  end
end

function fake_snapshot()
  -- A REAPER undo point: deep copy of tracks and items (sources shared).
  local snap = {}
  for _, t in ipairs(P.tracks) do
    local items = {}
    for _, it in ipairs(t.items) do
      local takes = {}
      for _, tk in ipairs(it.takes) do
        local vals, strs = {}, {}
        for k, v in pairs(tk.vals) do vals[k] = v end
        for k, v in pairs(tk.strs) do strs[k] = v end
        takes[#takes + 1] = { src = tk.src, vals = vals, strs = strs, midi = tk.midi, active = it.active == tk }
      end
      local vals, strs = {}, {}
      for k, v in pairs(it.vals) do vals[k] = v end
      for k, v in pairs(it.strs) do strs[k] = v end
      items[#items + 1] = { serial = it.serial, guid = it.guid, vals = vals, strs = strs, takes = takes, selected = it.selected }
    end
    local vals, strs = {}, {}
    for k, v in pairs(t.vals) do vals[k] = v end
    for k, v in pairs(t.strs) do strs[k] = v end
    snap[#snap + 1] = { tr = t, items = items, vals = vals, strs = strs }
  end
  return snap
end

function fake_restore(snap)
  -- REAPER undo: items come back as new objects with their old GUIDs.
  P.tracks = {}
  for _, s in ipairs(snap) do
    local t = s.tr
    t.items = {}
    t.vals, t.strs = {}, {}
    for k, v in pairs(s.vals) do t.vals[k] = v end
    for k, v in pairs(s.strs) do t.strs[k] = v end
    for _, si in ipairs(s.items) do
      local item = new_item(t)
      item.guid = si.guid
      item.selected = si.selected
      for k, v in pairs(si.vals) do item.vals[k] = v end
      for k, v in pairs(si.strs) do item.strs[k] = v end
      for _, st in ipairs(si.takes) do
        local tk = new_take(item, st.src)
        tk.midi = st.midi
        for k, v in pairs(st.vals) do tk.vals[k] = v end
        for k, v in pairs(st.strs) do tk.strs[k] = v end
        if st.active then item.active = tk end
      end
    end
    sort_items(t)
    P.tracks[#P.tracks + 1] = t
  end
  bump()
end

local function selected_items()
  local out = {}
  for _, t in ipairs(P.tracks) do
    for _, it in ipairs(t.items) do
      if it.selected then
        out[#out + 1] = it
      end
    end
  end
  return out
end

local QN_SEC = 0.5

local api = {}

function api.GetProjectStateChangeCount() return P.changes end
function api.CountTracks() return #P.tracks end
function api.GetTrack(_, idx) return P.tracks[idx + 1] end
function api.GetTrackGUID(tr) return tr and tr.guid or "" end
function api.GetTrackName(tr) return true, tr and tr.name or "" end
function api.GetSelectedTrack() return nil end
function api.CountSelectedTracks() return 0 end
function api.InsertTrackAtIndex(idx)
  local tr = fake_add_track("")
  table.remove(P.tracks, #P.tracks)
  table.insert(P.tracks, math.min(idx + 1, #P.tracks + 1), tr)
end
function api.DeleteTrack(tr)
  for i, t in ipairs(P.tracks) do
    if t == tr then
      table.remove(P.tracks, i)
      tr.alive = false
      bump()
      return
    end
  end
end
function api.GetMediaTrackInfo_Value(tr, key)
  if key == "IP_TRACKNUMBER" then
    for i, t in ipairs(P.tracks) do
      if t == tr then return i end
    end
    return 0
  end
  return tr.vals[key] or 0
end
function api.SetMediaTrackInfo_Value(tr, key, value)
  tr.vals[key] = value
  bump()
  return true
end
function api.GetSetMediaTrackInfo_String(tr, key, value, set)
  if key == "GUID" then return true, tr.guid end
  if key == "P_NAME" then
    if set then tr.name = value; bump() end
    return true, tr.name
  end
  if set then
    tr.strs[key] = value
    bump()
    return true, value
  end
  local v = tr.strs[key]
  return v ~= nil, v or ""
end

function api.CountTrackMediaItems(tr) return tr and #tr.items or 0 end
function api.GetTrackMediaItem(tr, idx) return tr.items[idx + 1] end
function api.CountMediaItems()
  local n = 0
  for _, t in ipairs(P.tracks) do n = n + #t.items end
  return n
end
function api.GetMediaItem(_, idx)
  local all = fake_items()
  return all[idx + 1]
end
function api.AddMediaItemToTrack(tr)
  local item = new_item(tr)
  bump()
  return item
end
function api.CreateNewMIDIItemInProj(tr, t0, t1)
  local item = new_item(tr)
  item.vals.D_POSITION = t0
  item.vals.D_LENGTH = t1 - t0
  local take = new_take(item, { kind = "source", typ = "MIDI" })
  take.midi = true
  sort_items(tr)
  bump()
  return item
end
function api.DeleteTrackMediaItem(tr, item)
  for i, it in ipairs(tr.items) do
    if it == item then
      table.remove(tr.items, i)
      item.alive = false
      bump()
      return true
    end
  end
  return false
end
function api.MoveMediaItemToTrack(item, tr)
  fake_user_move_item(item, item.vals.D_POSITION, tr)
  return true
end
function api.GetMediaItem_Track(item) return item and item.track end
api.GetMediaItemTrack = api.GetMediaItem_Track
function api.GetMediaItemInfo_Value(item, key)
  if key == "B_UISEL" then return item.selected and 1 or 0 end
  return item.vals[key] or 0
end
function api.SetMediaItemInfo_Value(item, key, value)
  if key == "B_UISEL" then
    item.selected = value ~= 0
  else
    item.vals[key] = value
  end
  if key == "D_POSITION" then sort_items(item.track) end
  bump()
  return true
end
function api.SetMediaItemPosition(item, pos)
  return api.SetMediaItemInfo_Value(item, "D_POSITION", pos)
end
function api.SetMediaItemLength(item, len)
  return api.SetMediaItemInfo_Value(item, "D_LENGTH", len)
end
function api.SetMediaItemSelected(item, sel)
  item.selected = sel and true or false
end
function api.IsMediaItemSelected(item) return item.selected end
function api.CountSelectedMediaItems() return #selected_items() end
function api.GetSelectedMediaItem(_, idx) return selected_items()[idx + 1] end
function api.UpdateItemInProject() end
function api.GetSetMediaItemInfo_String(item, key, value, set)
  if key == "GUID" then return true, item.guid end
  if set then
    item.strs[key] = value
    bump()
    return true, value
  end
  local v = item.strs[key]
  return v ~= nil, v or ""
end
function api.GetMediaItemNumTakes(item) return #item.takes end
function api.GetActiveTake(item) return item and item.active end
function api.AddTakeToMediaItem(item)
  local take = new_take(item, nil)
  bump()
  return take
end
function api.GetMediaItemTake_Item(take) return take.item end
function api.GetMediaItemTake_Source(take) return take.src end
function api.SetMediaItemTake_Source(take, src)
  take.src = src
  bump()
  return true
end
function api.TakeIsMIDI(take) return take and take.midi or false end
function api.GetMediaItemTakeInfo_Value(take, key) return take.vals[key] or 0 end
function api.SetMediaItemTakeInfo_Value(take, key, value)
  take.vals[key] = value
  bump()
  return true
end
function api.GetSetMediaItemTakeInfo_String(take, key, value, set)
  if set then
    take.strs[key] = value
    bump()
    return true, value
  end
  local v = take.strs[key]
  return v ~= nil, v or ""
end
function api.GetTakeEnvelopeByName() return nil end
function api.GetItemStateChunk() return false, "" end
function api.SetItemStateChunk() return false end

function api.PCM_Source_CreateFromFile(path) return new_source(path) end
api.PCM_Source_CreateFromFileEx = api.PCM_Source_CreateFromFile
function api.PCM_Source_Duplicate(src)
  local copy = {}
  for k, v in pairs(src) do copy[k] = v end
  return copy
end
function api.PCM_Source_CreateFromType(typ) return { kind = "source", typ = typ } end
function api.PCM_Source_Destroy() end
function api.GetMediaSourceFileName(src) return src and src.file or "" end
function api.GetMediaSourceLength(src) return (src and src.file and P.files[src.file]) or 1.0, false end
function api.GetMediaSourceType(src) return src and src.typ or "" end
function api.GetMediaSourceParent() return nil end
function api.GetMediaSourceNumChannels() return 2 end
function api.file_exists(path) return P.files[path] ~= nil end

function api.TimeMap2_QNToTime(_, qn) return qn * QN_SEC end
function api.TimeMap2_timeToQN(_, t) return t / QN_SEC end
function api.TimeMap_QNToTime(qn) return qn * QN_SEC end
function api.TimeMap_timeToQN(t) return t / QN_SEC end
function api.TimeMap2_timeToBeats(_, t)
  local qn = t / QN_SEC
  local measure = math.floor(qn / 4 + 1e-9)
  return qn - measure * 4, measure, 4, qn, 4
end
function api.TimeMap_GetMeasureInfo(_, measure)
  return measure * 4 * QN_SEC, measure * 4, measure * 4 + 4, 4, 4, 120
end
function api.TimeMap_GetDividedBpmAtTime() return 120 end
function api.Master_GetTempo() return 120 end
function api.GetSetProjectGrid() return 0, 0.25 end

function api.ValidatePtr2(_, ptr, typ)
  if typ == "ReaProject*" then return ptr == "PROJ" end
  return type(ptr) == "table" and ptr.alive == true
end
function api.ValidatePtr(ptr)
  return type(ptr) == "table" and ptr.alive == true
end
function api.EnumProjects() return "PROJ", "" end
function api.GetProjExtState(_, s, k)
  local v = P.ext[s .. "/" .. k]
  return v and 1 or 0, v or ""
end
function api.SetProjExtState(_, s, k, v)
  P.ext[s .. "/" .. k] = v
  return 1
end
function api.Undo_CanUndo2() return P.undo_desc end
function api.genGuid() return new_guid() end
function api.ColorToNative(r_, g, b) return (r_ << 16) | (g << 8) | b end
function api.JS_Mouse_GetState() return FAKE.mouse or 0 end
function api.time_precise() return FAKE.now or os.clock() end

local EXT = {}
function api.GetExtState(s, k) return EXT[s .. "/" .. k] or "" end
function api.SetExtState(s, k, v) EXT[s .. "/" .. k] = tostring(v) end
function api.HasExtState(s, k) return EXT[s .. "/" .. k] ~= nil end
function api.DeleteExtState(s, k) EXT[s .. "/" .. k] = nil end
function api.GetResourcePath() return FAKE_RES end
function api.get_action_context() return false, FAKE_RES .. "/Sample Map Browser.lua", 0, 0, 0, 0, 0 end
function api.GetOS() return "macOS-arm64" end
function api.APIExists() return true end

-- APIs that must be absent so code takes its plain path.
local absent = {
  SNM_GetSetSourceState2 = true, SNM_CreateFastString = true, BR_GetMidiTakePoolGUID = true,
  BR_GetMediaItemGUID = true, BR_SetMediaItemImageResource = true, BR_GetMediaItemImageResource = true,
  CF_GetMediaSourceMetadata = true,
}

local function default_for(name)
  if name:match("^ImGui_[A-Z]%w*Flags_") or name:match("^ImGui_Col_") or name:match("^ImGui_Key_")
      or name:match("^ImGui_Mod_") or name:match("^ImGui_StyleVar_") or name:match("^ImGui_Cond_")
      or name:match("^ImGui_MouseButton_") or name:match("^ImGui_Dir_") or name:match("^ImGui_MouseCursor_") then
    return function() return 0 end
  end
  if name:match("^ImGui_Is") or name:match("^ImGui_Begin") then return function() return false end end
  if name:match("^ImGui_Get") or name:match("^ImGui_Calc") then return function() return 0, 0 end end
  if name:match("^Count") then return function() return 0 end end
  return function() return nil end
end

reaper = setmetatable({}, { __index = function(t, k)
  if absent[k] then return nil end
  local f = api[k] or default_for(k)
  rawset(t, k, f)
  return f
end })
gfx = setmetatable({}, { __index = function() return function() return 0 end end })

io.popen = function()
  return { read = function() return nil end, close = function() return true end,
           lines = function() return function() return nil end end, write = function() end }
end
os.execute = function() return true end

fake_reset()

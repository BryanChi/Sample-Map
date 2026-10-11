"""Draw-trace comparison for performance work: loads two checkouts of Sample Map
Browser on the stub REAPER API from load_browser.py, seeds the same library and
sequencer song in both, runs identical scripted scenarios (both views, hover
positions, zoom levels, a playing sample, the layering window, and in-place
edits between frames), and compares, frame by frame, every effectful ImGui call
(draw-list adds, widgets, push/pop, cursor moves, tooltips) and every REAPER
write. Read-only queries (ImGui_Get*/Is*/Calc*, enum getters, REAPER getters)
are left out, so caching them is allowed; anything that changes what is drawn,
in what order, or what is written is reported with the first differing call.

Time is frozen per frame, pairs() visits keys in sorted order and table
addresses are masked, so the two runs are deterministic. Requires
`pip install lupa`.

usage: python3 tests/trace_compare.py BASE_DIR NEW_DIR [samples] [tracks]
       python3 tests/trace_compare.py --self DIR   (determinism check: DIR vs DIR)"""
import os
import re
import sys
import tempfile

from lupa import lua54

here = os.path.dirname(os.path.abspath(__file__))

src = open(os.path.join(here, "load_browser.py"), encoding="utf-8").read()
STUB = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)

HARNESS = r'''
-- Deterministic pairs: sorted keys (the real order depends on a per-state hash
-- seed, so two runtimes would draw overlapping notes in different orders).
do
  local raw_next, rawget, sort, type, tostring = next, rawget, table.sort, type, tostring
  local tyrank = { number = 1, string = 2, boolean = 3 }
  local function key_lt(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      return (tyrank[ta] or 9) < (tyrank[tb] or 9) or ((tyrank[ta] or 9) == (tyrank[tb] or 9) and ta < tb)
    end
    if ta == "number" or ta == "string" then return a < b end
    if ta == "boolean" then return (not a) and b end
    return tostring(a) < tostring(b)
  end
  pairs = function(t)
    local mt = getmetatable(t)
    if mt and mt.__pairs then return mt.__pairs(t) end
    local keys, n = {}, 0
    for k in raw_next, t do n = n + 1; keys[n] = k end
    sort(keys, key_lt)
    local i = 0
    return function()
      while true do
        i = i + 1
        local k = keys[i]
        if k == nil then return nil end
        local v = rawget(t, k)
        if v ~= nil then return k, v end
      end
    end, t, nil
  end
end

FRAME = 0
local tcalls = 0
local function now()
  tcalls = tcalls + 1
  -- Frozen within a frame; time-budgeted loops still terminate.
  if tcalls > 200000 then return 1000.0 + FRAME / 30.0 + (tcalls - 200000) * 1e-3 end
  return 1000.0 + FRAME / 30.0
end
special.time_precise = now
special.ImGui_GetTime = function() return FRAME / 30.0 end
special.ImGui_GetFrameCount = function() return FRAME end
os.clock = function() return now() end
os.time = function(t) if t then return 0 end return 1700000000 + FRAME end

-- Fake project: NTRACKS tracks with stable GUIDs and names; no items.
local tracks, guid_of, name_of = {}, {}, {}
for i = 1, NTRACKS do
  local t = "TRK" .. i
  tracks[i] = t; guid_of[t] = ("{%08d-0000-0000-0000-000000000000}"):format(i); name_of[t] = "Drum " .. i
end
special.CountTracks = function() return #tracks end
special.GetTrack = function(_, i) return tracks[i + 1] end
special.GetTrackGUID = function(t) return guid_of[t] or "{0}" end
special.ValidatePtr = function(p) return type(p) == "string" and (guid_of[p] ~= nil) end
special.ValidatePtr2 = function(_, p) return type(p) == "string" and (guid_of[p] ~= nil) end
special.BR_GetMediaTrackByGUID = function(_, g) for i = 1, #tracks do if guid_of[tracks[i]] == g then return tracks[i] end end end
special.GetTrackName = function(t) return true, name_of[t] or "" end
special.GetSetMediaTrackInfo_String = function(t, k, v, set)
  if k == "P_NAME" then return true, name_of[t] or "" end
  if k == "GUID" then return true, guid_of[t] or "" end
  return false, ""
end
special.GetMediaTrackInfo_Value = function() return 0 end
special.CountTrackMediaItems = function() return 0 end
special.ImGui_IsWindowHovered = function() return true end
local img_n = 0
special.ImGui_CreateImage = function() img_n = img_n + 1; return { img = img_n } end
special.ImGui_Attach = function() end
special.new_array = function(n) return {} end
ARRANGE_END = 10
special.GetSet_ArrangeView2 = function() return 0, ARRANGE_END end

-- Mouse and last-item rect, so hover branches run.
MOUSE = { x = -100, y = -100, down = false, clicked = false }
local item = { 0, 0, 0, 0 }
local cur_x, cur_y = 0, 0
local function in_item()
  return MOUSE.x >= item[1] and MOUSE.x < item[3] and MOUSE.y >= item[2] and MOUSE.y < item[4]
end
special.ImGui_GetMousePos = function() return MOUSE.x, MOUSE.y end
special.ImGui_SetCursorScreenPos = function(_, x, y) cur_x, cur_y = x, y end
special.ImGui_InvisibleButton = function(_, id, w, h)
  item = { cur_x, cur_y, cur_x + (w or 0), cur_y + (h or 0) }
  return MOUSE.clicked and in_item()
end
special.ImGui_IsItemHovered = function() return in_item() end
special.ImGui_IsItemActive = function() return MOUSE.down and in_item() end
special.ImGui_IsItemClicked = function(_, b) return (b or 0) == 0 and MOUSE.clicked and in_item() end
special.ImGui_GetItemRectMin = function() return item[1], item[2] end
special.ImGui_GetItemRectMax = function() return item[3], item[4] end
special.ImGui_GetItemRectSize = function() return item[3] - item[1], item[4] - item[2] end
special.ImGui_IsMouseDown = function(_, b) return (b or 0) == 0 and MOUSE.down end
special.ImGui_IsMouseClicked = function(_, b) return (b or 0) == 0 and MOUSE.clicked end
special.ImGui_IsMouseHoveringRect = function(_, x0, y0, x1, y1)
  return MOUSE.x >= x0 and MOUSE.x < x1 and MOUSE.y >= y0 and MOUSE.y < y1
end
for k, f in pairs(special) do rawset(reaper, k, f) end

-- Which calls go in the trace.
local function is_enum(name)
  return name:match("^ImGui_[A-Z]%w*Flags_") or name:match("^ImGui_Col_") or name:match("^ImGui_Key_")
     or name:match("^ImGui_Mod_") or name:match("^ImGui_StyleVar_") or name:match("^ImGui_Cond_")
     or name:match("^ImGui_MouseButton_") or name:match("^ImGui_Dir_") or name:match("^ImGui_MouseCursor_")
     or name:match("^ImGui_ConfigVar_") or name:match("^ImGui_DrawFlags_") or name:match("^ImGui_ColorEditFlags_")
     or name:match("^ImGui_TableFlags_") or name:match("^ImGui_TableColumnFlags_")
end
local function traced(name)
  if name:match("^ImGui_") then
    if is_enum(name) then return false end
    if name:match("^ImGui_Get") or name:match("^ImGui_Is") or name:match("^ImGui_Calc")
       or name:match("^ImGui_ValidatePtr") or name:match("^ImGui_Table_Get") then
      return false
    end
    return true
  end
  if name:match("^Get") or name:match("^Count") or name:match("^Enum") or name:match("^Validate")
     or name:match("^TimeMap") or name == "time_precise" or name:match("^Has") or name:match("^BR_Get")
     or name:match("^JS_") or name == "APIExists" or name == "file_exists" or name:match("^gmem_read")
     or name == "defer" or name == "atexit" or name:match("^CF_Get") or name:match("^Master_Get")
     or name:match("^TrackFX_Get") or name:match("^TakeFX_Get") or name:match("^MIDI_Get")
     or name:match("^MIDI_Count") or name:match("^PCM_Source_Get") or name == "ShowConsoleMsg"
     or name:match("^Undo_Can") or name:match("^format_timestr") or name:match("^parse_timestr")
     or name:match("^MIDI_Enum") or name:match("^NF_Get") or name:match("^SNM_Get")
     or name:match("^kbd_get") or name:match("^ImGui_") then
    -- GetSet* are writes only when their set flag is on (checked below).
    return name:match("^GetSet") ~= nil
  end
  return true
end
local function fmt(v)
  local tv = type(v)
  if tv == "number" then
    if v ~= v then return "nan" end
    return string.format("%.4f", v)
  elseif tv == "string" then
    return (v:gsub("0x%x+", "0xADDR"):gsub("\n", "\\n"))
  elseif tv == "boolean" or tv == "nil" then
    return tostring(v)
  end
  return "T"
end
TRACE_ON = false
TRACE = {}
local function record(name, ...)
  local n = select("#", ...)
  if name:match("^GetSet") then
    -- GetSetMediaItemInfo_String(item, key, val, set) etc.: only sets count.
    local last = select(n, ...)
    if last ~= true and last ~= 1 then return end
  end
  local parts = { name }
  for i = 1, n do parts[#parts + 1] = fmt((select(i, ...))) end
  TRACE[#TRACE + 1] = table.concat(parts, " ")
end
local real_index = getmetatable(reaper).__index
local function wrap(k, f)
  if not traced(k) then return f end
  return function(...)
    if TRACE_ON then record(k, ...) end
    return f(...)
  end
end
setmetatable(reaper, { __index = function(t, k)
  local f = real_index(t, k)
  local w = wrap(k, f)
  rawset(t, k, w); return w end })
for k, f in pairs(special) do rawset(reaper, k, wrap(k, f)) end

math.randomseed(7)
local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
if not chunk then return "LOADFAIL " .. err end
local ok, e = xpcall(chunk, debug.traceback)
if not ok then return "MAIN ERROR " .. tostring(e) end
if rawget(_G, "log") then log = function(m) msgs[#msgs+1] = "LOG " .. tostring(m) end end

local function run_frame()
  FRAME = FRAME + 1
  tcalls = 0
  local q = deferred; deferred = {}
  if #q == 0 then return "no deferred fn at frame " .. FRAME end
  for _, f in ipairs(q) do
    local ok2, e2 = xpcall(f, debug.traceback)
    if not ok2 then return ("FRAME %d ERROR %s"):format(FRAME, tostring(e2)) end
  end
end
for i = 1, 10 do local r0 = run_frame(); if r0 then return r0 end end

-- Seed library.
math.randomseed(7)
local tag_pool = { "kick", "snare", "clap", "hat", "tom", "ride", "crash", "perc", "fx", "bass", "vocal", "loop", "pad", "lead" }
local samples = {}
for i = 1, NSAMPLES do
  local t1 = tag_pool[(i % #tag_pool) + 1]
  local t2 = tag_pool[((i * 7) % #tag_pool) + 1]
  samples[i] = {
    path = ("/lib/pack%d/%s/%s_%05d.wav"):format(i % 40, t1, t1, i),
    name = ("%s_%05d.wav"):format(t1, i),
    x = math.random(), y = math.random(), tags = { t1, t2 }, duration = 0.1 + math.random() * 2,
    brightness = math.random(), weight = math.random(), dominant_freq = 100 + math.random() * 5000,
  }
end
state.samples = samples
rebuild_samples_path_index()
state.map_layout_version = (state.map_layout_version or 0) + 1
if sm_tag_index_rebuild_if_stale then pcall(sm_tag_index_rebuild_if_stale) end
if rebuild_tag_index then pcall(rebuild_tag_index) end

-- Seed sequencer: one track per fake REAPER track, 4 regions of 2 bars, notes
-- on most steps, with some per-note params so the lanes draw.
local cfg = { seq_tracks = {}, seq_regions = {}, seq_patterns = {} }
for i = 1, NTRACKS do
  local s = samples[i]
  cfg.seq_tracks[i] = { id = i, name = "Drum " .. i, reaper_track_guid = guid_of[tracks[i]],
    sample_path = s.path, sample_name = s.name, sample_tag = s.tags[1],
    sample_candidates = { { path = s.path }, { path = samples[i + 20].path }, { path = samples[i + 40].path } } }
end
for r_i = 1, 4 do
  local notes = {}
  for tid = 1, NTRACKS do
    local row = {}
    for st = 0, 31 do
      if (st + tid) % 3 ~= 0 then
        local n = { vel = 60 + ((st * 7 + tid) % 60), volume = 1.0 }
        if st % 5 == 0 then n.pan = ((st % 3) - 1) * 0.5 end
        if st % 7 == 0 then n.pitch = (st % 4) - 2 end
        if st % 11 == 0 then n.stutter = 2 end
        if st % 9 == 0 then n.length_qn = 0.5 end
        row[tostring(st)] = n
      end
    end
    notes[tostring(tid)] = row
  end
  cfg.seq_patterns[tostring(r_i)] = { notes = notes }
  cfg.seq_regions[r_i] = { id = r_i, name = "R" .. r_i, start_qn = (r_i - 1) * 8, length_bars = 2, pool_id = r_i, pattern_id = r_i }
end
cfg.seq_pattern_next_id = 5; cfg.seq_pool_next_id = 5
apply_seq_project_state(cfg)
state.seq_view_start_qn = 0; state.seq_view_span_qn = 32
state.seq_expanded_tracks = { ["1"] = true, ["2"] = true }

local frames_out = {}
local function frames(label, positions, opts)
  opts = opts or {}
  for i, p in ipairs(positions) do
    MOUSE.x, MOUSE.y = p[1], p[2]
    MOUSE.down = opts.down or false
    MOUSE.clicked = opts.clicked or false
    TRACE = {}
    TRACE_ON = true
    local e2 = run_frame()
    TRACE_ON = false
    if e2 then frames_out[#frames_out + 1] = label .. "#" .. i .. "\n" .. e2; return end
    frames_out[#frames_out + 1] = label .. "#" .. i .. "\n" .. table.concat(TRACE, "\n")
  end
end
local function grid_positions(n, x0, y0, x1, y1)
  local out = {}
  for i = 0, n - 1 do
    local fx = ((i * 0.618034) % 1.0)
    local fy = ((i * 0.381966 + 0.21) % 1.0)
    out[#out + 1] = { math.floor(x0 + fx * (x1 - x0)) + 0.5, math.floor(y0 + fy * (y1 - y0)) + 0.5 }
  end
  return out
end
local still = { { -100, -100 }, { -100, -100 } }
local pos = grid_positions(POSITIONS, 0, 0, 800, 600)
local function note(pid, tid, st)
  local p = get_seq_pattern(pid, false)
  return p and p.notes[tostring(tid)] and p.notes[tostring(tid)][tostring(st)]
end

-- Sample map view.
state.active_view = "sample_map"
frames("map idle", still)
frames("map hover", pos)
preview_sample_obj = samples[5]
frames("map playing", pos)
state.zoom = 2.5; state.pan_x = 40; state.pan_y = -30
frames("map zoomed", pos)
state.active_tags = { kick = true }
frames("map filtered", pos)
state.active_tags = {}
state.zoom = 1.0; state.pan_x = 0; state.pan_y = 0
preview_sample_obj = nil
frames("map reset", still)

-- Sequencer, zoomed out.
state.active_view = "sequencer"
frames("seq idle", still)
frames("seq hover", pos)
note(1, 1, 1).vel = 20
frames("seq vel edit", still)
local p1 = get_seq_pattern(1, false)
p1.notes["2"]["4"] = nil
frames("seq erase", still)
p1.notes["3"]["0"] = { vel = 90, volume = 0.5, length_qn = 1.0 }
frames("seq paint", still)
state.seq_tracks[2].mute = true
state.seq_tracks[3].volume = 0.4
frames("seq mute/vol", pos)
state.seq_tracks[1].sample_path = samples[33].path
frames("seq sample swap", still)
state.seq_tracks[4].layers = state.seq_tracks[4].layers or {}
if seq_normalize_slot_layers then seq_normalize_slot_layers(state.seq_tracks[4]) end
state.seq_tracks[4].layers.transient.verts[2].path = samples[44].path
state.seq_tracks[4].layers.transient.blend = { 0.5, 0.5, 0.0 }
frames("seq layers edit", pos)
state.seq_expanded_tracks = { ["3"] = true }
frames("seq expand", pos)
state.selected_seq_region_id = 2
frames("seq region 2", still)
state.seq_regions[3].length_bars = 3
frames("seq region len", still)
state.seq_view_start_qn = 4
frames("seq scrolled", pos)

-- Sequencer, zoomed in (cells wide enough for full notes, locks, grid).
ARRANGE_END = 2
frames("seq zoomed", pos)
note(1, 5, 2).vel = 127
note(1, 5, 2).pitch = 3
frames("seq zoomed edit", pos)
p1.notes["6"]["8"] = nil
frames("seq zoomed erase", still)

-- Layering window open on track 4.
state.seq_layering_slot_id = 4
frames("layering open", pos)
state.seq_tracks[4].layers.sustain.blend = { 0.2, 0.3, 0.5 }
frames("layering edit", pos)
-- ==== Track panel block (sequencer track panel perf pass) ================
-- The track label/mix column in both views: hovers, clicks and fader drags
-- on M/S/vol/pan/MIDI/layering/overlap/envelope/candidate squares/nav,
-- candidate rows that are full, have a hole or are missing, solo/overlap,
-- an active envelope, layering forced on/off and malformed, MIDI learn,
-- alt-click removal (slide animation) and a sample dragged over squares.
-- In the stub every panel row sits at the same place, so a click hits that
-- control on every track.
do
  -- Clicks below save the config (after a delay) and the library cache next
  -- to the script; keep those writes in this run's temp folder so the
  -- checkout stays clean and the next run starts the same.
  CONFIG_PATH = RES .. "/SampleMapBrowser.json"
  DATA_PATH = RES .. "/SampleMapData.json"
  DATA_LUA_PATH = RES .. "/SampleMapData.cache.lua"
  state.seq_layering_slot_id = nil
  ALT_DOWN = false
  rawset(reaper, "JS_Mouse_GetState", function() return ALT_DOWN and 16 or 0 end)
  -- SetTooltip goes through the hint card, which the stub never draws; put
  -- the requested text in the trace so tooltips are compared too.
  local raw_hint_request = hint_request
  hint_request = function(c, text, ...)
    if TRACE_ON then TRACE[#TRACE + 1] = "HINT " .. tostring(text):gsub("\n", "\\n") end
    return raw_hint_request(c, text, ...)
  end
  local tr = state.seq_tracks
  tr[5].sample_candidates = {}
  for i = 1, 12 do tr[5].sample_candidates[i] = { path = samples[100 + i].path, brightness = i * 0.07 } end
  tr[5].sample_candidate_idx = 12
  tr[6].sample_candidates = { { path = samples[60].path }, {}, { path = samples[61].path }, { path = "" } }
  tr[6].sample_candidate_idx = 3
  tr[7].sample_candidates = nil
  tr[7]._cand_norm = nil
  tr[3].solo = true
  tr[8].overlap = true
  tr[9].env = { points = { { t = 0.0, amp = 0.2 }, { t = 0.05, amp = 1.4, curve = 0.4 }, { t = 0.4, amp = 0.0 } } }
  tr[10].layers = { output = "layered", linked = true,
    transient = { verts = { {}, { path = samples[70].path, len = 0.2 }, {} }, blend = { 1 / 3, 1 / 3, 1 / 3 }, gain = 2 },
    unlinked_sustain = { blend = { 0.7, 0.2, 0.1 } } }
  tr[9].layers = { output = "original", tail_end = 0.3 }
  tr[8].layers = "bad"
  tr[7].layers = { transient = { verts = { { path = samples[7].path }, { path = samples[71].path } }, blend = { 0.2, 0.8, 0 } } }

  state.active_view = "sample_map"
  local panel = { { 10, 30 }, { 28, 30 }, { 200, 30 }, { 500, 30 }, { 680, 30 }, { 705, 30 }, { 725, 30 },
    { 300, 50 }, { 670, 10 }, { 690, 10 }, { 705, 10 }, { 725, 10 }, { 100, 10 }, { 745, 30 }, { 770, 30 }, { 790, 30 } }
  frames("panel hover", panel)
  frames("panel click mute", { { 10, 30 } }, { clicked = true })
  frames("panel click solo", { { 28, 30 } }, { clicked = true })
  frames("panel click overlap", { { 725, 30 } }, { clicked = true })
  frames("panel click cand", { { 725, 10 } }, { clicked = true })
  frames("panel after clicks", panel)
  frames("panel vol drag", { { 200, 30 }, { 230, 30 }, { 260, 30 }, { 120, 30 } }, { down = true })
  frames("panel vol release", { { 120, 30 } })
  frames("panel pan drag", { { 500, 30 }, { 450, 30 } }, { down = true })
  frames("panel pan release", still)
  state.seq_midi_learn_slot_id = tr[2].id
  frames("panel midi learn", { { 680, 30 }, { -100, -100 } })
  state.seq_midi_learn_slot_id = nil
  ALT_DOWN = true
  frames("panel alt hover", { { 670, 10 } })
  frames("panel alt click", { { 690, 10 } }, { clicked = true })
  ALT_DOWN = false
  frames("panel slide", { { 670, 10 }, { 670, 10 }, { 690, 10 }, { 690, 10 }, { -100, -100 }, { -100, -100 } })
  state.pending_waveform_drop = samples[90]
  frames("panel drag over", { { 690, 10 }, { 705, 10 }, { 770, 30 } })
  state.pending_waveform_drop = nil
  state.seq_candidate_drop = nil
  state.seq_drop_target_idx = nil
  state.seq_drum_drop = nil
  frames("panel click env", { { 300, 50 } }, { clicked = true })
  frames("panel env open", { { 300, 50 } })
  frames("panel click env again", { { 300, 50 } }, { clicked = true })
  frames("panel click layering", { { 705, 30 } }, { clicked = true })
  frames("panel layering open", panel)

  state.active_view = "sequencer"
  local lane = { { 10, 32 }, { 24, 32 }, { 55, 32 }, { 90, 32 }, { 125, 32 }, { 146, 32 }, { 160, 32 },
    { 110, 15 }, { 127, 15 }, { 144, 15 }, { 160, 15 }, { 50, 15 }, { 10, 234 }, { 55, 234 }, { 127, 217 } }
  frames("lane hover", lane)
  frames("lane click mute", { { 10, 32 } }, { clicked = true })
  frames("lane click overlap", { { 160, 32 } }, { clicked = true })
  frames("lane click cand", { { 160, 15 } }, { clicked = true })
  frames("lane vol drag", { { 55, 32 }, { 70, 32 }, { 40, 32 } }, { down = true })
  frames("lane after", lane)
  state.seq_layering_slot_id = nil
  hint_request = raw_hint_request
end
-- ==== end track panel block ==============================================
state.seq_layering_slot_id = nil
ARRANGE_END = 10
state.seq_view_start_qn = 0
state.active_view = "sample_map"
frames("map again", pos)

-- [map view] Hovering a track row in the tracks panel highlights its samples
-- (the stub puts every row at y 0..row height, so a low mouse y hovers one),
-- with and without a playing sample.
local track_rows = { { 120.5, 6.5 }, { 400.5, 12.5 }, { 700.5, 3.5 } }
frames("map track hover", track_rows)
preview_sample_obj = samples[state.seq_tracks[#state.seq_tracks].sample_path and 9 or 9]
frames("map track hover playing", track_rows)
preview_sample_obj = samples[44]
frames("map playing assigned", track_rows)
preview_sample_obj = nil

-- [map view] Panning and zooming every frame with the mouse over the dots:
-- the visible list, entries and hover search are rebuilt each frame.
do
  local hover_pts = grid_positions(6, 200, 120, 760, 580)
  local steps = {
    { 1.0, 0, 0 }, { 1.0, 13.5, -7.25 }, { 1.7, 40, 22 }, { 1.7, -95.5, 60 },
    { 3.0, 210, -140 }, { 3.0, 215.25, -141 }, { 6.0, -480, 300 }, { 6.0, 512.5, -333 },
    { 11.0, 900, 700 }, { 2.2, 0.125, 0.0625 },
  }
  for i, st in ipairs(steps) do
    state.zoom, state.pan_x, state.pan_y = st[1], st[2], st[3]
    frames("map pan " .. i, { hover_pts[(i % #hover_pts) + 1] })
  end
  preview_sample_obj = samples[77]
  for i, st in ipairs(steps) do
    state.zoom, state.pan_x, state.pan_y = st[1], -st[2], -st[3]
    frames("map pan playing " .. i, { hover_pts[((i + 2) % #hover_pts) + 1], { 120.5, 6.5 } })
  end
  preview_sample_obj = nil
  state.zoom, state.pan_x, state.pan_y = 1.0, 0, 0
end
for _, m in ipairs(msgs) do
  if m:find("ERROR") or m:find("rror") then frames_out[#frames_out + 1] = "MSG\n" .. m:sub(1, 400) end
end
return frames_out
'''


def run(repo, n_samples, n_tracks, positions):
    L = lua54.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    g = L.globals()
    g.REPO = os.path.abspath(repo).encode()
    g.RES = tempfile.mkdtemp().encode()
    g.NSAMPLES = n_samples
    g.NTRACKS = n_tracks
    g.POSITIONS = positions
    out = L.execute((STUB + HARNESS).encode())
    if isinstance(out, bytes):
        return [out.decode("utf-8", "replace")]
    return [out[i].decode("utf-8", "replace") for i in range(1, len(out) + 1)]


def compare(base, new):
    problems = 0
    for i in range(max(len(base), len(new))):
        a = base[i] if i < len(base) else "<missing>"
        b = new[i] if i < len(new) else "<missing>"
        if a == b:
            continue
        problems += 1
        la, lb = a.split("\n"), b.split("\n")
        label = la[0]
        j = 0
        while j < min(len(la), len(lb)) and la[j] == lb[j]:
            j += 1
        print(f"MISMATCH in frame '{label}' ({len(la) - 1} vs {len(lb) - 1} calls), first difference at call {j}:")
        for k in range(max(1, j - 3), j):
            print(f"    {la[k]}")
        print(f"  - {la[j] if j < len(la) else '<end>'}")
        print(f"  + {lb[j] if j < len(lb) else '<end>'}")
        if problems >= 8:
            print("  (stopping after 8 mismatching frames)")
            break
    return problems


def main(argv):
    if len(argv) >= 2 and argv[1] == "--self":
        base_dir = new_dir = argv[2]
        rest = argv[3:]
    else:
        if len(argv) < 3:
            print(__doc__)
            return 2
        base_dir, new_dir = argv[1], argv[2]
        rest = argv[3:]
    n_samples = int(rest[0]) if len(rest) > 0 else 3000
    n_tracks = int(rest[1]) if len(rest) > 1 else 10
    positions = int(rest[2]) if len(rest) > 2 else 8
    base = run(base_dir, n_samples, n_tracks, positions)
    new = run(new_dir, n_samples, n_tracks, positions)
    calls = sum(len(f.split("\n")) - 1 for f in base)
    errors = [f for f in base + new if "ERROR" in f.split("\n")[0] or f.startswith("MSG")
              or "\nFRAME" in f or f.startswith(("LOADFAIL", "MAIN ERROR"))]
    for e in errors[:6]:
        print("ERROR:", e[:600])
    problems = compare(base, new)
    print(f"{len(base)} frames, {calls} traced calls; {problems} mismatching frames")
    return 1 if problems or errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

"""Song Starter (browser/42c_song_starter.lua): key / tempo maths, role matching,
Safe <-> Chaos candidate filtering, re-roll with locks, synced preview through
a fake CF_Preview, Add to project through a fake track API, history and
persistence. Runs the browser with a stub REAPER. Requires `pip install lupa`."""
import os
import tempfile

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

STUB = r'''
EXT = {}
NOW = 100.0
local deferred = {}
local special = {
  APIExists = function() return true end,
  get_action_context = function() return false, REPO .. "/Sample Map Browser.lua", 0, 0, 0, 0, 0 end,
  GetResourcePath = function() return RES end,
  GetOS = function() return "macOS-arm64" end,
  GetExtState = function(s, k) return EXT[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) EXT[s .. "/" .. k] = tostring(v) end,
  DeleteExtState = function(s, k) EXT[s .. "/" .. k] = nil end,
  HasExtState = function(s, k) return EXT[s .. "/" .. k] ~= nil end,
  GetProjExtState = function() return 0, "" end,
  EnumProjects = function() return "PROJ", "" end,
  GetProjectStateChangeCount = function() return 1 end,
  time_precise = function() return NOW end,
  defer = function(f) deferred[#deferred + 1] = f end,
  atexit = function() end,
  ShowMessageBox = function() return 1 end,
  ShowConsoleMsg = function() end,
  ImGui_CreateContext = function() return {} end,
  ImGui_ValidatePtr = function() return true end,
  ValidatePtr = function() return false end, ValidatePtr2 = function() return false end,
  ImGui_GetVersion = function() return "0.9.3", 0, "0.9.3" end,
  CountTracks = function() return 0 end, CountMediaItems = function() return 0 end,
  CountSelectedMediaItems = function() return 0 end, CountSelectedTracks = function() return 0 end,
  GetPlayState = function() return 0 end, GetCursorPosition = function() return 0 end,
  ExecProcess = function() return "1\n" end,
  EnumerateFiles = function() return nil end, EnumerateSubdirectories = function() return nil end,
  file_exists = function() return false end,
  RecursiveCreateDirectory = function() return 1 end,
  GetAppVersion = function() return "7.20/macOS-arm64" end,
  JS_VKeys_GetState = function() return string.rep("\0", 255) end,
  JS_Mouse_GetState = function() return 0 end,
  GetMousePosition = function() return 0, 0 end,
  Master_GetTempo = function() return 120 end,
  GetSetProjectInfo_String = function() return false, "" end, GetSetMediaTrackInfo_String = function() return false, "" end,
  GetProjectPath = function() return RES end, GetProjectName = function() return "" end,
  ImGui_Begin = function() return true, true end,
  ImGui_GetWindowPos = function() return 40, 40 end,
  ImGui_GetWindowSize = function() return 800, 600 end,
  ImGui_GetContentRegionAvail = function() return 736, 500 end,
  ImGui_GetCursorScreenPos = function() return 52, 50 end,
  ImGui_GetItemRectMin = function() return 52, 50 end,
  ImGui_GetItemRectMax = function() return 120, 72 end,
  ImGui_CalcTextSize = function(_, s) return #tostring(s) * 7, 14 end,
  ImGui_GetStyleVar = function() return 8, 4 end,
  ImGui_GetWindowDrawList = function() return {} end,
}
local function default_for(name)
  if name:match("^ImGui_[A-Z]%w*Flags_") or name:match("^ImGui_Col_") or name:match("^ImGui_Key_")
     or name:match("^ImGui_Mod_") or name:match("^ImGui_StyleVar_") or name:match("^ImGui_Cond_")
     or name:match("^ImGui_MouseButton_") or name:match("^ImGui_Dir_") or name:match("^ImGui_MouseCursor_")
     or name:match("^ImGui_ConfigVar_") or name:match("^ImGui_DrawFlags_") or name:match("^ImGui_TableFlags_") then
    return function() return 0 end
  end
  if name:match("^ImGui_Is") or name:match("^ImGui_Begin") then return function() return false end end
  if name:match("^ImGui_Get") or name:match("^ImGui_Calc") then return function() return 0, 0 end end
  if name:match("^Count") then return function() return 0 end end
  return function() return nil end
end
reaper = setmetatable({}, { __index = function(t, k)
  local f = special[k] or default_for(k)
  rawset(t, k, f)
  return f
end })
gfx = setmetatable({}, { __index = function() return function() return 0 end end })
io.popen = function() return { read = function() return nil end, close = function() return true end, lines = function() return function() return nil end end } end
os.execute = function() return true end
local chunk = assert(loadfile(REPO .. "/Sample Map Browser.lua"))
chunk()
for i = 1, 3 do local q = deferred; deferred = {}; for _, f in ipairs(q) do f() end end
LOGS = {}
log = function(m) LOGS[#LOGS + 1] = tostring(m) end
NOTES = {}
sm_notify = function(m, kind) NOTES[#NOTES + 1] = tostring(m) end
ERRORS = {}
sm_report_error = function(site, err) ERRORS[#ERRORS + 1] = tostring(site) .. ": " .. tostring(err) end
save_config = function() end

-- Fresh Song Starter state in a temp file.
SS_FILE = RES .. "/SampleMapSongStarter.json"
state.song_starter = nil
SS_PLAY = nil

local seq = 0
ss_rand = function()
  -- small LCG so picks repeat between runs
  seq = (seq * 1103515245 + 12345) % 2147483648
  return seq / 2147483648
end

state.samples = {}
function mk(path, dur, tags, extra)
  local s = { path = path, name = path:match("[^/]+$"), duration = dur, tags = tags }
  for k, v in pairs(extra or {}) do s[k] = v end
  state.samples[#state.samples + 1] = s
  return s
end
mk("/lib/Drums/Drum Loop 120bpm.wav", 8.0, { "drum", "loop" })
mk("/lib/Drums/Beat_124_bpm.wav", 7.742, { "drum", "loop" })
mk("/lib/Drums/Break 90bpm.wav", 10.667, { "drum", "loop" })
mk("/lib/Drums/Drum Groove 60bpm.wav", 16.0, { "drum", "loop" })
mk("/lib/Perc/Shaker Top 120bpm.wav", 4.0, { "perc", "loop" })
mk("/lib/Bass/Bass Loop 120bpm Am.wav", 8.0, { "bass", "loop" })
mk("/lib/Bass/Bassline 118 bpm Cm.wav", 8.136, { "bass", "loop" })
mk("/lib/Bass/Sub Bass 120bpm F#.wav", 8.0, { "bass", "loop" })
mk("/lib/Keys/Piano Chords 120bpm Cmaj.wav", 8.0, { "keys", "loop" })
mk("/lib/Keys/Rhodes Chords 121bpm Dm.wav", 7.934, { "keys", "loop" })
mk("/lib/Lead/Lead Melody 120bpm Bm.wav", 8.0, { "lead", "loop" })
mk("/lib/Lead/Arp Idea 120bpm.wav", 8.0, { "lead", "loop" })
mk("/lib/FX/Texture Atmos.wav", 8.0, { "pad", "loop" })
mk("/lib/OneShots/Kick 120bpm.wav", 0.4, { "kick" })
mk("/lib/Drums/Analyzed Loop 120bpm.wav", 8.0, { "drum" }, { playback_type = "loop" })
rebuild_samples_path_index()

function paths(list)
  local out = {}
  for _, c in ipairs(list) do out[#out + 1] = c.path:match("[^/]+$") end
  table.sort(out)
  return out
end
function cands(role, chaos, bpm, key)
  local pool = ss_loop_pool(ss_state())
  return paths(ss_candidates(pool, role, bpm or 120, key, ss_chaos_params(chaos)))
end
'''


def _runtime():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    L.execute(STUB)
    return L


def _list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t else []


def test_key_parsing_and_pitch_shift():
    L = _runtime()
    f = L.globals().ss_pitch_shift
    assert f("Am", "Am") == 0
    assert f("C", "Am") == 0          # relative major
    assert f("Am", "C") == 0
    assert f("Bm", "Am") == -2
    assert f("Dm", "Am") == -5
    assert f("E", "A") == 5
    assert f("G", "A") == 2
    assert f("F#", "Am") == -6        # F# major -> D#m, a tritone from Am
    assert f(None, "Am") is None and f("Am", None) is None
    norm = L.globals().ss_norm_key
    assert norm("A#min") == "Bbm"
    assert norm("Ebmaj") == "Eb"
    assert norm("C# minor") == "C#m"
    assert norm("Bb") == "Bb"
    assert norm("nope") is None


def test_bpm_from_length_prefers_power_of_two_bars():
    L = _runtime()
    f = L.globals().ss_bpm_from_length
    bpm, bars = f(8.0)
    assert abs(bpm - 120) < 1e-9 and bars == 4
    bpm, bars = f(2.0)
    assert abs(bpm - 120) < 1e-9 and bars == 1
    bpm, bars = f(3.0)                # 80 (1 bar) or 160 (2 bars): nearer 120
    assert abs(bpm - 160) < 1e-9 and bars == 2
    bpm, bars = f(3.0, 85)
    assert abs(bpm - 80) < 1e-9 and bars == 1
    bpm, bars = f(5.0)
    assert abs(bpm - 96) < 1e-9 and bars == 2
    assert f(0.1) is None
    bpm, bars = f(30.0)
    assert abs(bpm - 128) < 1e-9 and bars == 16


def test_stretch_with_half_and_double_time():
    L = _runtime()
    f = L.globals().ss_stretch
    rate, mult = f(120, 124, False)
    assert abs(rate - 124 / 120) < 1e-9 and mult == 1
    rate, mult = f(60, 120, True)
    assert abs(rate - 1.0) < 1e-9 and mult == 2
    rate, mult = f(60, 120, False)
    assert abs(rate - 2.0) < 1e-9 and mult == 1
    rate, mult = f(200, 100, True)
    assert abs(rate - 1.0) < 1e-9 and mult == 0.5


def test_role_matching():
    L = _runtime()
    got = L.execute(r'''
      local function by(name)
        for _, s in ipairs(state.samples) do if s.name == name then return s end end
      end
      return ss_role_strength(by("Bass Loop 120bpm Am.wav"), "bass"),
             ss_role_strength(by("Bass Loop 120bpm Am.wav"), "drums"),
             ss_role_strength(by("Piano Chords 120bpm Cmaj.wav"), "chords"),
             ss_role_strength(by("Texture Atmos.wav"), "texture"),
             ss_role_strength(by("Texture Atmos.wav"), "chords"),
             ss_role_strength(by("Shaker Top 120bpm.wav"), "top"),
             ss_is_loop(by("Kick 120bpm.wav")),
             ss_is_loop(by("Analyzed Loop 120bpm.wav"))
    ''')
    assert got == (2, 0, 2, 2, 0, 2, False, True)


def test_safe_and_chaos_candidate_filtering():
    L = _runtime()
    c = lambda *a: _list(L.globals().cands(*a))
    # Safe: known tempo within 8%, no half/double, key within 2 semitones.
    assert c("drums", 0.0, 120, "Am") == ["Analyzed Loop 120bpm.wav", "Beat_124_bpm.wav", "Drum Loop 120bpm.wav"]
    assert c("bass", 0.0, 120, "Am") == ["Bass Loop 120bpm Am.wav"]
    assert c("chords", 0.0, 120, "Am") == ["Piano Chords 120bpm Cmaj.wav"]
    assert c("lead", 0.0, 120, "Am") == ["Lead Melody 120bpm Bm.wav"]
    assert c("texture", 0.0, 120, "Am") == []   # tempo only guessed from length
    # Chaos: wide stretch, half/double, unknown keys, big shifts, guessed tempo.
    assert c("drums", 1.0, 120, "Am") == ["Analyzed Loop 120bpm.wav", "Beat_124_bpm.wav", "Break 90bpm.wav",
                                          "Drum Groove 60bpm.wav", "Drum Loop 120bpm.wav"]
    assert c("bass", 1.0, 120, "Am") == ["Bass Loop 120bpm Am.wav", "Bassline 118 bpm Cm.wav", "Sub Bass 120bpm F#.wav"]
    assert c("lead", 1.0, 120, "Am") == ["Arp Idea 120bpm.wav", "Lead Melody 120bpm Bm.wav"]
    assert c("texture", 1.0, 120, "Am") == ["Texture Atmos.wav"]
    # One-shots never qualify.
    assert "Kick 120bpm.wav" not in c("drums", 1.0, 120, None)


def test_batch_sets_auto_key_and_reroll_keeps_locks():
    L = _runtime()
    out = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, true, nil
      ss_do_reroll("batch")
      local by = {}
      for _, s in ipairs(st.slots) do by[s.role] = s end
      local key = st.target_key
      local filled = 0
      local seen, dup = {}, false
      for _, s in ipairs(st.slots) do
        if s.path then filled = filled + 1; if seen[s.path] then dup = true end; seen[s.path] = true end
      end
      -- lock bass, reroll unlocked many times
      by.bass.locked = true
      local bass = by.bass.path
      local drums_seen, bass_kept = {}, true
      for i = 1, 12 do
        ss_do_reroll("unlocked")
        if by.bass.path ~= bass then bass_kept = false end
        drums_seen[by.drums.path] = true
      end
      local n = 0
      for _ in pairs(drums_seen) do n = n + 1 end
      -- single-slot reroll never repeats the current file when another fits
      local repeats = 0
      for i = 1, 10 do
        local before = by.drums.path
        ss_do_reroll(by.drums)
        if by.drums.path == before then repeats = repeats + 1 end
      end
      -- melodic slots other than the one that set the key stay within Safe's 2 semitones
      local max_shift = 0
      for _, s in ipairs(st.slots) do max_shift = math.max(max_shift, math.abs(s.shift or 0)) end
      return key, filled, dup, bass_kept, n, repeats, #st.history, ss_norm_key(by.bass.src_key), max_shift
    ''')
    key, filled, dup, bass_kept, n_drums, repeats, n_hist, bass_key, max_shift = out
    # the first melodic pick (bass) sets the automatic key; Safe needs a known key
    assert key is not None and key == bass_key
    assert max_shift <= 2
    assert filled >= 5 and not dup
    assert bass_kept
    assert n_drums >= 2
    assert repeats == 0
    assert n_hist >= 1


def test_relaxes_when_nothing_fits_and_reports_empty():
    L = _runtime()
    out = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      st.slots = { ss_new_slot(st, "texture") }
      ss_do_reroll("unlocked")
      local tex = st.slots[1]
      -- remove every texture loop: slot empties and a note says so
      for i = #state.samples, 1, -1 do
        if state.samples[i].name == "Texture Atmos.wav" then table.remove(state.samples, i) end
      end
      tex.recent = {}
      ss_do_reroll(tex)
      return st.slots[1] == tex and (tex.path == nil), NOTES[#NOTES], tex.relaxed
    ''')
    emptied, note, _ = out
    assert emptied
    assert "Texture" in note


def test_preview_plays_in_sync_and_swaps_in_place():
    L = _runtime()
    out = L.execute(r'''
      VOICES, STOPPED_ALL = {}, 0
      reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
      reaper.PCM_Source_Destroy = function() end
      reaper.GetMediaSourceLength = function() return 8.0, false end
      reaper.CF_CreatePreview = function(src) local v = { src = src, vals = {}, playing = false } ; VOICES[#VOICES + 1] = v; return v end
      reaper.CF_Preview_SetValue = function(o, k, v) o.vals[k] = v; return true end
      reaper.CF_Preview_GetValue = function(o, k) if o.dead then return false, 0 end return true, o.vals[k] or 0 end
      reaper.CF_Preview_Play = function(o) o.playing = true; o.start = NOW; return true end
      reaper.CF_Preview_Stop = function(o) o.playing = false; o.dead = true; return true end
      reaper.CF_Preview_StopAll = function() STOPPED_ALL = STOPPED_ALL + 1; for _, v in ipairs(VOICES) do v.playing = false; v.dead = true end end
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 124, 0.0, false, "Am"
      ss_do_reroll("batch")
      local filled = 0
      for _, s in ipairs(st.slots) do if s.path then filled = filled + 1 end end
      ss_preview_play()
      local n0 = #VOICES
      local same_start, all_loop, ok_vals = true, true, true
      for _, v in ipairs(VOICES) do
        if v.start ~= VOICES[1].start then same_start = false end
        if v.vals.B_LOOP ~= 1 or v.vals.B_PPITCH ~= 1 then all_loop = false end
      end
      for _, s in ipairs(st.slots) do
        local v = SS_PLAY.voices[s.id]
        if v and math.abs(v.obj.vals.D_PLAYRATE - s.rate) > 1e-9 then ok_vals = false end
        if v and v.obj.vals.D_PITCH ~= s.shift then ok_vals = false end
      end
      -- mute: volume goes to 0, voice keeps running
      local drums
      for _, s in ipairs(st.slots) do if s.role == "drums" then drums = s end end
      drums.muted = true
      ss_preview_update()
      local muted_vol = SS_PLAY.voices[drums.id].obj.vals.D_VOLUME
      drums.muted = false
      -- 3.1 s later, re-roll drums: new voice joins at the loop phase
      NOW = NOW + 3.1
      ss_do_reroll(drums)
      local nv = SS_PLAY.voices[drums.id].obj
      local expect = (3.1 * drums.rate) % drums.dur
      local nv_playing = nv.playing
      -- something else stops all previews: we notice and drop our voices
      reaper.CF_Preview_StopAll()
      ss_preview_update()
      return filled, n0, same_start, all_loop, ok_vals, muted_vol, nv.vals.D_POSITION, expect, nv_playing,
             SS_PLAY == nil, STOPPED_ALL
    ''')
    filled, n0, same_start, all_loop, ok_vals, muted_vol, pos, expect, playing, stopped, stop_all = out
    assert n0 == filled and filled >= 4
    assert same_start and all_loop and ok_vals
    assert muted_vol == 0.0
    assert abs(pos - expect) < 1e-9 and pos > 0 and playing
    assert stopped
    assert stop_all >= 2  # once by play (normal preview stopped first), once by the test


def test_add_to_project_builds_folder():
    L = _runtime()
    out = L.execute(r'''
      TRACKS, ITEMS, UNDO = {}, {}, {}
      reaper.CountTracks = function() return #TRACKS end
      reaper.GetSelectedTrack = function() return nil end
      reaper.InsertTrackAtIndex = function(i) table.insert(TRACKS, i + 1, { depth = 0, items = {} }) end
      reaper.GetTrack = function(_, i) return TRACKS[i + 1] end
      reaper.GetSetMediaTrackInfo_String = function(tr, k, v, set) if set then tr[k] = v end return true, tr[k] or "" end
      reaper.SetMediaTrackInfo_Value = function(tr, k, v) if k == "I_FOLDERDEPTH" then tr.depth = v end end
      reaper.AddMediaItemToTrack = function(tr) local it = { tr = tr, take = nil }; tr.items[#tr.items + 1] = it; ITEMS[#ITEMS + 1] = it; return it end
      reaper.AddTakeToMediaItem = function(it) it.take = {}; return it.take end
      reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
      reaper.SetMediaItemTake_Source = function(t, s) t.src = s end
      reaper.SetMediaItemTakeInfo_Value = function(t, k, v) t[k] = v end
      reaper.GetSetMediaItemTakeInfo_String = function(t, k, v) t[k] = v end
      reaper.SetMediaItemInfo_Value = function(it, k, v) it[k] = v end
      reaper.GetCursorPosition = function() return 12.0 end
      reaper.Undo_BeginBlock2 = function() UNDO[#UNDO + 1] = "begin" end
      reaper.Undo_EndBlock2 = function(_, name) UNDO[#UNDO + 1] = name end
      reaper.SetCurrentBPM = function(_, bpm) SET_BPM = bpm end
      TRACKS[1] = { depth = 0, items = {}, P_NAME = "existing" }
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.bars, st.set_tempo = 124, 0.0, false, "Am", 8, true
      ss_do_reroll("batch")
      local audible = 0
      for _, s in ipairs(st.slots) do if s.path then audible = audible + 1 end end
      st.slots[1].muted = true
      audible = audible - 1
      ss_add_to_project()
      local names, depths = {}, {}
      for i, t in ipairs(TRACKS) do names[i] = t.P_NAME; depths[i] = t.depth end
      local it = ITEMS[1]
      local slot2 = st.slots[2]
      return #TRACKS, audible, names[2], depths[2], depths[#TRACKS], it.D_POSITION, it.D_LENGTH, it.B_LOOPSRC,
             it.take.B_PPITCH, math.abs(it.take.D_PLAYRATE - slot2.rate) < 1e-9, UNDO[1], UNDO[2], SET_BPM, names[3]
    ''')
    (n_tracks, audible, folder_name, folder_depth, last_depth, pos, length, loopsrc, ppitch, rate_ok,
     u1, u2, set_bpm, first_child) = out
    assert n_tracks == 1 + 1 + audible
    assert folder_name == "Song Starter Am 124" and folder_depth == 1 and last_depth == -1
    assert pos == 12.0 and abs(length - 8 * 240.0 / 124) < 1e-9
    assert loopsrc == 1 and ppitch == 1 and rate_ok
    assert u1 == "begin" and "Song Starter" in u2
    assert set_bpm == 124
    assert first_child == "Top / Perc"  # drums slot was muted


def test_history_cap_pins_and_persistence():
    L = _runtime()
    out = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 1.0, false, "Am"
      ss_do_reroll("batch")
      ss_history_push(st, true)
      local pinned_sig = st.history[1].slots[1].path
      for i = 1, 30 do
        st.target_bpm = 100 + i
        ss_history_push(st, false)
      end
      local unpinned, pinned = 0, 0
      for _, h in ipairs(st.history) do if h.pinned then pinned = pinned + 1 else unpinned = unpinned + 1 end end
      st.slots[2].locked = true
      st.chaos = 0.7
      ss_save_now()
      local slots_before = #st.slots
      local locked_path = st.slots[2].path
      state.song_starter = nil
      local st2 = ss_state()
      -- recall the pinned one
      local h
      for _, e in ipairs(st2.history) do if e.pinned then h = e end end
      local n_hist = #st2.history
      ss_history_recall(st2, h)
      return unpinned, pinned, n_hist, #st2.slots > 0, st2.chaos, slots_before, locked_path,
             st2.target_bpm, st2.key_auto
    ''')
    unpinned, pinned, n_hist, has_slots, chaos, _, _, bpm, key_auto = out
    assert unpinned == 20 and pinned == 1
    assert n_hist == 21
    assert has_slots and abs(chaos - 0.7) < 1e-9
    assert bpm == 120 and key_auto is False


def test_persisted_slots_survive_reload():
    L = _runtime()
    out = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")
      st.slots[3].locked = true
      st.slots[3].vol = 0.5
      st.open = true
      ss_save_now()
      local p = st.slots[3].path
      state.song_starter = nil
      local st2 = ss_state()
      return st2.open, st2.slots[3].path == p, st2.slots[3].locked, st2.slots[3].vol, st2.target_key, #st2.slots
    ''')
    assert out == (True, True, True, 0.5, "Am", 6)


def test_window_renders_without_errors_and_balances_style():
    L = _runtime()
    out = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos = 120, 0.3
      ss_do_reroll("batch")
      st.open = true
      local pc, ppc, pv, ppv = 0, 0, 0, 0
      reaper.ImGui_PushStyleColor = function() pc = pc + 1 end
      reaper.ImGui_PopStyleColor = function(_, n) ppc = ppc + (n or 1) end
      reaper.ImGui_PushStyleVar = function() pv = pv + 1 end
      reaper.ImGui_PopStyleVar = function(_, n) ppv = ppv + (n or 1) end
      local ids = 0
      reaper.ImGui_PushID = function() ids = ids + 1 end
      reaper.ImGui_PopID = function() ids = ids - 1 end
      render_song_starter_window()
      render_song_starter_window()
      return #ERRORS, pc == ppc and pc > 0, pv == ppv and pv > 0, ids, ERRORS[1]
    ''')
    n_err, colors_ok, vars_ok, ids, first = out
    assert n_err == 0, first
    assert colors_ok and vars_ok and ids == 0

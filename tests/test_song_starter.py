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


def test_history_cap_likes_and_persistence():
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
      for _, h in ipairs(st.history) do if h.liked then pinned = pinned + 1 else unpinned = unpinned + 1 end end
      st.slots[2].locked = true
      st.chaos = 0.7
      ss_save_now()
      local slots_before = #st.slots
      local locked_path = st.slots[2].path
      state.song_starter = nil
      local st2 = ss_state()
      -- recall the liked one
      local h
      for _, e in ipairs(st2.history) do if e.liked then h = e end end
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


# --- Arrangement mode -----------------------------------------------------------

FAKE_PROJECT = r'''
  TRACKS, ITEMS, UNDO, REGIONS = {}, {}, {}, {}
  reaper.CountTracks = function() return #TRACKS end
  reaper.GetSelectedTrack = function() return nil end
  reaper.InsertTrackAtIndex = function(i) table.insert(TRACKS, i + 1, { depth = 0, items = {} }) end
  reaper.GetTrack = function(_, i) return TRACKS[i + 1] end
  reaper.GetSetMediaTrackInfo_String = function(tr, k, v, set) if set then tr[k] = v end return true, tr[k] or "" end
  reaper.SetMediaTrackInfo_Value = function(tr, k, v) if k == "I_FOLDERDEPTH" then tr.depth = v end end
  reaper.AddMediaItemToTrack = function(tr) local it = { tr = tr }; tr.items[#tr.items + 1] = it; ITEMS[#ITEMS + 1] = it; return it end
  reaper.AddTakeToMediaItem = function(it) it.take = {}; return it.take end
  reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
  reaper.SetMediaItemTake_Source = function(t, s) t.src = s end
  reaper.SetMediaItemTakeInfo_Value = function(t, k, v) t[k] = v end
  reaper.GetSetMediaItemTakeInfo_String = function(t, k, v) t[k] = v end
  reaper.SetMediaItemInfo_Value = function(it, k, v) it[k] = v end
  reaper.GetCursorPosition = function() return 10.0 end
  reaper.Undo_BeginBlock2 = function() UNDO[#UNDO + 1] = "begin" end
  reaper.Undo_EndBlock2 = function(_, name) UNDO[#UNDO + 1] = name end
  reaper.SetCurrentBPM = function(_, bpm) SET_BPM = bpm end
  reaper.ColorToNative = function(r, g, b) return r | (g << 8) | (b << 16) end
  reaper.AddProjectMarker2 = function(_, isrgn, a, b, name, idx, color)
    REGIONS[#REGIONS + 1] = { rgn = isrgn, a = a, b = b, name = name, color = color }
    return #REGIONS
  end
'''


def _sections(L, template, chaos):
    arr = L.globals().ss_build_arrangement(template, chaos)
    out = []
    for i in range(1, len(arr.sections) + 1):
        s = arr.sections[i]
        out.append((s.type, s.bars, s.start, s.name))
    return arr, out


def test_templates_expand_in_order_with_bar_positions():
    L = _runtime()
    arr, secs = _sections(L, "club", 0.0)
    assert [(t, b) for t, b, _, _ in secs] == [("intro", 8), ("build", 8), ("drop", 16), ("breakdown", 8),
                                               ("build", 8), ("drop", 16), ("outro", 8)]
    assert [s for _, _, s, _ in secs] == [0, 8, 16, 32, 40, 48, 64]
    assert arr.total == 72
    assert [n for _, _, _, n in secs] == ["Intro", "Build 1", "Drop 1", "Breakdown", "Build 2", "Drop 2", "Outro"]
    for key, total in (("pop", 48), ("hiphop", 56), ("short", 20)):
        arr, _ = _sections(L, key, 0.0)
        assert arr.total == total


def test_safe_presence_is_textbook_and_repeatable():
    L = _runtime()
    got = L.execute(r'''
      local a = ss_build_arrangement("club", 0)
      local b = ss_build_arrangement("club", 0)
      local function roles(sec)
        local t = {}
        for k in pairs(sec.parts) do t[#t + 1] = k end
        table.sort(t)
        return table.concat(t, ",")
      end
      local same = true
      for i, s in ipairs(a.sections) do if roles(s) ~= roles(b.sections[i]) then same = false end end
      local intro, build, drop, brk, outro = a.sections[1], a.sections[2], a.sections[3], a.sections[4], a.sections[7]
      return same, roles(intro), intro.parts.top.from, roles(build), build.parts.drums.rise, build.parts.lead.vol,
             roles(drop), roles(brk), outro.parts.drums.to, outro.parts.chords.to, outro.parts.texture.to
    ''')
    same, intro, top_from, build, rise, lead_vol, drop, brk, drums_to, chords_to, tex_to = got
    assert same
    assert intro == "chords,texture,top" and top_from == 4
    assert build == "chords,drums,lead,texture,top" and rise is True and abs(lead_vol - 0.6) < 1e-9
    assert drop == "bass,chords,drums,lead,texture,top"
    assert brk == "chords,lead,texture"
    assert (drums_to, chords_to, tex_to) == (4, 6, 8)


def test_gap_before_drop_cuts_drums_bass_top():
    L = _runtime()
    got = L.execute(r'''
      local a = ss_build_arrangement("club", 0)
      local build = a.sections[2]
      local s = ss_build_arrangement("short", 0)
      local b4 = s.sections[2]  -- 4-bar build before the drop: half-bar gap
      local p = ss_build_arrangement("pop", 0)
      local pre = p.sections[3]
      return build.gap, build.parts.drums.to, build.parts.top.to, build.parts.chords.to,
             b4.gap, b4.parts.drums.to, pre.gap, pre.parts.bass.to,
             ss_arr_gain(a, "drums", 15.5), ss_arr_gain(a, "chords", 15.5), ss_arr_gain(a, "drums", 16.2)
    ''')
    gap, drums_to, top_to, chords_to, gap4, drums4, pre_gap, pre_bass, g_gap, g_chords, g_drop = got
    assert gap == 1 and drums_to == 7 and top_to == 7 and chords_to == 8
    assert gap4 == 0.5 and drums4 == 3.5
    assert pre_gap == 0.5 and pre_bass == 3.5
    assert g_gap == 0 and g_chords == 1 and g_drop == 1


def test_chaos_and_random_vary():
    L = _runtime()
    got = L.execute(r'''
      local function sig(a)
        local t = {}
        for _, s in ipairs(a.sections) do
          local r = {}
          for k, p in pairs(s.parts) do r[#r + 1] = k .. p.from .. "-" .. p.to end
          table.sort(r)
          t[#t + 1] = s.type .. s.bars .. "[" .. table.concat(r, ",") .. "]"
        end
        return table.concat(t, " ")
      end
      local safe, wild, rnd, rnd_ok = {}, {}, {}, true
      for i = 1, 12 do
        safe[sig(ss_build_arrangement("club", 0))] = true
        wild[sig(ss_build_arrangement("club", 1))] = true
        local a = ss_build_arrangement("random", 0.2)
        rnd[sig(a)] = true
        if a.sections[#a.sections].type ~= "outro" or a.total < 16 then rnd_ok = false end
        local has_peak = false
        for _, s in ipairs(a.sections) do if SS_SECTION_TYPES[s.type].drop then has_peak = true end end
        if not has_peak then rnd_ok = false end
      end
      local n = function(t) local c = 0; for _ in pairs(t) do c = c + 1 end; return c end
      return n(safe), n(wild), n(rnd), rnd_ok
    ''')
    n_safe, n_wild, n_rnd, rnd_ok = got
    assert n_safe == 1
    assert n_wild >= 4
    assert n_rnd >= 4
    assert rnd_ok


def test_add_arrangement_places_items_on_grid_with_regions():
    L = _runtime()
    L.execute(FAKE_PROJECT)
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.set_tempo = 120, 0.0, false, "Am", false
      ss_do_reroll("batch")
      st.mode, st.template = "arrange", "club"
      ss_arrangement(st, true)
      -- give the drums loop an odd length so start offsets matter
      local drums
      for _, s in ipairs(st.slots) do if s.role == "drums" then drums = s end end
      drums.dur, drums.rate = 6.0, 1.0
      ss_add_to_project()
      local bar = 2.0  -- seconds at 120 bpm
      local on_grid, offs_ok, fades_ok, rise_ok = true, true, true, false
      local drum_items = 0
      for _, it in ipairs(ITEMS) do
        local rel = (it.D_POSITION - 10.0) / bar
        if math.abs(rel * 2 - math.floor(rel * 2 + 0.5)) > 1e-6 then on_grid = false end
        if it.tr.P_NAME == "Drums" then
          drum_items = drum_items + 1
          if math.abs(it.take.D_STARTOFFS - ((it.D_POSITION - 10.0) % 6.0)) > 1e-9 then offs_ok = false end
        end
        if not it.D_FADEOUTLEN or it.D_FADEOUTLEN <= 0 or it.D_FADEOUTLEN > 0.05 then fades_ok = false end
        if it.D_FADEINLEN and math.abs(it.D_FADEINLEN - it.D_LENGTH) < 1e-9 and it.C_FADEINSHAPE == 1 then rise_ok = true end
        if it.B_LOOPSRC ~= 1 then on_grid = false end
      end
      local rnames = {}
      for _, g in ipairs(REGIONS) do rnames[#rnames + 1] = g.name end
      local r3 = REGIONS[3]
      return #REGIONS, table.concat(rnames, "|"), r3.a, r3.b, r3.rgn, r3.color == (0x85CC49 | 0x1000000),
             on_grid, offs_ok, fades_ok, rise_ok, drum_items, UNDO[2], TRACKS[1].P_NAME, TRACKS[#TRACKS].depth
    ''')
    (n_reg, names, a, b, is_rgn, color_ok, on_grid, offs_ok, fades_ok, rise_ok, drum_items, undo, folder,
     last_depth) = got
    assert n_reg == 7
    assert names == "Intro|Build 1|Drop 1|Breakdown|Build 2|Drop 2|Outro"
    assert a == 10.0 + 16 * 2.0 and b == 10.0 + 32 * 2.0 and is_rgn and color_ok
    assert on_grid and offs_ok and fades_ok and rise_ok
    # drums: build 1, drop 1, build 2, drop 2, outro (not intro, not breakdown)
    assert drum_items == 5
    assert undo == "Song Starter: arrange"
    assert folder == "Song Starter Am 120 Club" and last_depth == -1


def test_muted_slot_stays_out_of_arrangement():
    L = _runtime()
    L.execute(FAKE_PROJECT)
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")
      st.mode = "arrange"
      for _, s in ipairs(st.slots) do if s.role == "bass" then s.muted = true end end
      ss_add_to_project()
      local bass = false
      for _, t in ipairs(TRACKS) do if t.P_NAME == "Bass" then bass = true end end
      return bass, #TRACKS > 2
    ''')
    assert got == (False, True)


def test_arrange_preview_follows_sections_and_jumps():
    L = _runtime()
    got = L.execute(r'''
      VOICES = {}
      reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
      reaper.PCM_Source_Destroy = function() end
      reaper.CF_CreatePreview = function(src) local v = { src = src, vals = {} }; VOICES[#VOICES + 1] = v; return v end
      reaper.CF_Preview_SetValue = function(o, k, v) o.vals[k] = v; return true end
      reaper.CF_Preview_GetValue = function(o, k) return true, o.vals[k] or 0 end
      reaper.CF_Preview_Play = function(o) o.playing = true; return true end
      reaper.CF_Preview_Stop = function(o) o.playing = false end
      reaper.CF_Preview_StopAll = function() end
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")
      st.mode, st.template = "arrange", "club"
      ss_arrangement(st, true)
      local by = {}
      for _, s in ipairs(st.slots) do by[s.role] = s end
      ss_preview_play()
      local function vol(role) return SS_PLAY.voices[by[role].id].obj.vals.D_VOLUME end
      -- bar 1 (intro): chords on, drums out
      NOW = NOW + 2.0
      ss_preview_update()
      local intro_chords, intro_drums = vol("chords"), vol("drums")
      -- jump to Drop 1 (bar 16): everything on, loops join at that phase
      ss_preview_play(16)
      local drums_pos = SS_PLAY.voices[by.drums.id].obj.vals.D_POSITION
      local expect = ss_loop_phase(by.drums, 32.0)
      NOW = NOW + 0.5
      ss_preview_update()
      return intro_chords, intro_drums, vol("drums"), vol("bass"), math.abs((drums_pos or 0) - expect) < 1e-9,
             math.floor(ss_arr_bar_at(st, NOW - SS_PLAY.t0))
    ''')
    intro_chords, intro_drums, drop_drums, drop_bass, phase_ok, bar = got
    assert intro_chords > 0 and intro_drums == 0
    assert drop_drums > 0 and drop_bass > 0
    assert phase_ok
    assert bar == 16


def test_mode_template_and_arrangement_persist_and_ride_in_history():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")
      st.mode, st.template = "arrange", "hiphop"
      ss_arrangement(st, true)
      local h = ss_history_push(st, true)
      ss_save_now()
      state.song_starter = nil
      local st2 = ss_state()
      local mode, tmpl, total = st2.mode, st2.template, st2.arr and st2.arr.total
      st2.mode, st2.template, st2.arr = "loop", "club", nil
      ss_history_recall(st2, st2.history[1])
      return mode, tmpl, total, h.mode, h.template, st2.mode, st2.template, st2.arr and st2.arr.total
    ''')
    assert got == ("arrange", "hiphop", 56, "arrange", "hiphop", "arrange", "hiphop", 56)


def test_window_draws_arrangement_strip():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos = 120, 0.0
      ss_do_reroll("batch")
      st.open, st.mode, st.template = true, "arrange", "club"
      local rects, texts = 0, {}
      reaper.ImGui_DrawList_AddRect = function() rects = rects + 1 end
      reaper.ImGui_DrawList_AddText = function(_, x, y, c, s) texts[#texts + 1] = s end
      render_song_starter_window()
      local strip = ss_draw_arrangement_strip(st, 720)
      local joined = table.concat(texts, "|")
      return #ERRORS, ERRORS[1], strip.h > SS_STRIP_HEAD_H, #strip.roles, joined:find("DROP 1", 1, true) ~= nil,
             rects > 7
    ''')
    n_err, first, tall, n_roles, has_drop, rects = got
    assert n_err == 0, first
    assert tall and n_roles >= 4 and has_drop and rects


def test_add_to_project_rebuilds_peaks_for_added_items_only():
    L = _runtime()
    L.execute(FAKE_PROJECT)
    got = L.execute(r'''
      -- selection fakes: one existing item selected before
      OLD = { tr = {}, old = true }
      SELECTED = { [OLD] = true }
      ALL = { OLD }
      local add = reaper.AddMediaItemToTrack
      reaper.AddMediaItemToTrack = function(tr) local it = add(tr); ALL[#ALL + 1] = it; return it end
      reaper.CountSelectedMediaItems = function()
        local n = 0; for _, it in ipairs(ALL) do if SELECTED[it] then n = n + 1 end end; return n
      end
      reaper.GetSelectedMediaItem = function(_, i)
        local n = -1
        for _, it in ipairs(ALL) do if SELECTED[it] then n = n + 1; if n == i then return it end end end
      end
      reaper.SelectAllMediaItems = function(_, on) for _, it in ipairs(ALL) do SELECTED[it] = on or nil end end
      reaper.SetMediaItemSelected = function(it, on) SELECTED[it] = on or nil end
      reaper.ValidatePtr2 = function(_, p, t) return t == "MediaItem*" and p ~= nil end
      RUNS = {}
      reaper.Main_OnCommand = function(cmd)
        local sel = {}
        for _, it in ipairs(ALL) do if SELECTED[it] then sel[#sel + 1] = it end end
        RUNS[#RUNS + 1] = { cmd = cmd, sel = sel }
      end
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")
      local function check(n_before)
        local run = RUNS[#RUNS]
        local exact = #run.sel == #ITEMS - n_before
        for i, it in ipairs(run.sel) do if it ~= ITEMS[n_before + i] then exact = false end end
        local restored = SELECTED[OLD] == true
        for i = n_before + 1, #ITEMS do if SELECTED[ITEMS[i]] then restored = false end end
        return run.cmd, exact, restored
      end
      st.mode = "loop"
      ss_add_to_project()
      local c1, e1, r1 = check(0)
      local n = #ITEMS
      st.mode = "arrange"
      ss_add_to_project()
      local c2, e2, r2 = check(n)
      return #RUNS, c1, e1, r1, c2, e2, r2, #ITEMS - n > 6
    ''')
    assert got == (2, 40441, True, True, 40441, True, True, True)


# --- Mixed loop lengths ---------------------------------------------------------

def test_loops_of_other_bar_lengths_are_eligible():
    L = _runtime()
    got = L.execute(r'''
      mk("/lib/Drums/Long Drum Loop 120bpm.wav", 32.0, { "drum", "loop" })   -- 16 bars
      mk("/lib/Drums/Short Drum Loop 120bpm.wav", 2.0, { "drum", "loop" })   -- 1 bar
      local st = ss_state()
      st.bars = 8
      local names = {}
      for _, c in ipairs(ss_candidates(ss_loop_pool(st), "drums", 120, nil, ss_chaos_params(0))) do
        local s = { dur = c.sample.duration, rate = c.rate }
        names[c.sample.name] = ss_slot_bars(s, 120)
      end
      return names["Long Drum Loop 120bpm.wav"], names["Short Drum Loop 120bpm.wav"], names["Drum Loop 120bpm.wav"]
    ''')
    assert got == (16, 1, 4)


def test_per_voice_phase_short_repeats_long_continues():
    L = _runtime()
    got = L.execute(r'''
      local bar = 2.0  -- seconds at 120 bpm
      local short = { dur = 8.0, rate = 1.0 }    -- 4 bars
      local long = { dur = 32.0, rate = 1.0 }    -- 16 bars
      local odd = { dur = 31.9, rate = 1.0 }     -- a hair short of 16 bars: still on the grid
      local out = {}
      -- bar 10 of the song (2nd cycle of an 8-bar set): short is at bar 2 of its 4,
      -- long keeps going at bar 10 of its 16
      out[1] = ss_loop_phase(short, 10 * bar, 120)
      out[2] = ss_loop_phase(long, 10 * bar, 120)
      out[3] = ss_loop_phase(odd, 16 * bar, 120)
      out[4] = select(1, ss_slot_bar_at(long, 10.5 * bar, 120))
      out[5] = ss_slot_bars(long, 120)
      out[6] = ss_slot_bars({ dur = 4.0, rate = 0.5 }, 120)  -- stretched to 8 s = 4 bars
      return table.unpack(out)
    ''')
    short_pos, long_pos, odd_pos, long_bar, long_bars, stretched = got
    assert abs(short_pos - 4.0) < 1e-9
    assert abs(long_pos - 20.0) < 1e-9
    assert abs(odd_pos) < 1e-9
    assert abs(long_bar - 10.5) < 1e-9 and long_bars == 16 and stretched == 4


def test_add_to_project_offsets_for_long_loop():
    L = _runtime()
    L.execute(FAKE_PROJECT)
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.bars = 120, 0.0, false, "Am", 8
      ss_do_reroll("batch")
      local drums
      for _, s in ipairs(st.slots) do if s.role == "drums" then drums = s end end
      drums.dur, drums.rate = 32.0, 1.0      -- 16-bar loop in an 8-bar set
      -- LOOP: one 8-bar item from the start of the loop
      st.mode = "loop"
      ss_add_to_project()
      local loop_item
      for _, it in ipairs(ITEMS) do if it.tr.P_NAME == "Drums" then loop_item = it end end
      local n = #ITEMS
      -- ARRANGE: each drums item starts where the 16-bar loop is at that bar
      st.mode, st.template = "arrange", "club"
      ss_arrangement(st, true)
      ss_add_to_project()
      local ok, count = true, 0
      for i = n + 1, #ITEMS do
        local it = ITEMS[i]
        if it.tr.P_NAME == "Drums" then
          count = count + 1
          local bar = (it.D_POSITION - 10.0) / 2.0
          local expect = ((bar % 16) / 16) * 32.0
          if math.abs((it.take.D_STARTOFFS or -1) - expect) > 1e-9 then ok = false end
        end
      end
      return loop_item.D_LENGTH, loop_item.take.D_STARTOFFS or 0, ok, count
    ''')
    length, offs, ok, count = got
    assert abs(length - 16.0) < 1e-9 and offs == 0
    assert ok and count == 5


def test_draws_cycle_timeline_and_own_playheads():
    L = _runtime()
    got = L.execute(r'''
      reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
      reaper.PCM_Source_Destroy = function() end
      reaper.CF_CreatePreview = function(src) return { vals = {} } end
      reaper.CF_Preview_SetValue = function(o, k, v) o.vals[k] = v; return true end
      reaper.CF_Preview_GetValue = function(o, k) return true, 0 end
      reaper.CF_Preview_Play = function() return true end
      reaper.CF_Preview_Stop = function() end
      reaper.CF_Preview_StopAll = function() end
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.bars, st.open = 120, 0.0, false, "Am", 8, true
      ss_do_reroll("batch")
      local drums, bass
      for _, s in ipairs(st.slots) do
        if s.role == "drums" then drums = s elseif s.role == "bass" then bass = s end
      end
      drums.dur, drums.rate = 32.0, 1.0   -- 16 bars: own playhead
      bass.dur, bass.rate = 16.0, 1.0     -- 8 bars: matches the set, none
      ss_preview_play()
      NOW = NOW + 21.0                     -- bar 10.5
      local texts = {}
      reaper.ImGui_DrawList_AddText = function(_, x, y, c, s) texts[#texts + 1] = s end
      render_song_starter_window()
      local tl = ss_draw_cycle_timeline(st, 720)
      local own = ss_draw_slot_playhead(st, drums, {}, 0, 0, 320, 40)
      local same = ss_draw_slot_playhead(st, bass, {}, 0, 0, 320, 40)
      local joined = table.concat(texts, "|")
      return #ERRORS, ERRORS[1], tl.bars, math.abs(tl.now - 2.5) < 1e-9, own.label, same.label,
             joined:find("11/16", 1, true) ~= nil, joined:find("16 BAR", 1, true) ~= nil,
             joined:find("3/8", 1, true) ~= nil
    ''')
    n_err, first, bars, now_ok, label, same_label, drew_counter, drew_bars, drew_same = got
    assert n_err == 0, first
    assert bars == 8 and now_ok
    assert label == "11/16" and same_label == "3/8"
    assert drew_counter and drew_bars and drew_same


# --- Full-height playheads and meters ------------------------------------------

FAKE_CF = r"""
  reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
  reaper.PCM_Source_Destroy = function() end
  reaper.CF_CreatePreview = function(src) return { vals = {}, path = src.path } end
  reaper.CF_Preview_SetValue = function(o, k, v) o.vals[k] = v; return true end
  reaper.CF_Preview_GetValue = function(o, k) return true, 0 end
  reaper.CF_Preview_Play = function() return true end
  reaper.CF_Preview_Stop = function() end
  reaper.CF_Preview_StopAll = function() end
  PEAK = 0.5
  reaper.CF_Preview_GetPeak = function(o, ch)
    return true, (o.vals.D_VOLUME or 0) > 0 and (ch == 0 and PEAK or PEAK * 0.5) or 0
  end
  local st = ss_state()
  st.target_bpm, st.chaos, st.key_auto, st.target_key, st.bars, st.open = 120, 0.0, false, "Am", 8, true
  ss_do_reroll("batch")
  BY = {}
  for _, s in ipairs(st.slots) do BY[s.role] = s end
  BY.drums.dur, BY.drums.rate = 32.0, 1.0   -- 16 bars
  BY.bass.dur, BY.bass.rate = 16.0, 1.0     -- 8 bars
"""


def test_full_height_playhead_fill_per_loop_length():
    L = _runtime()
    L.execute(FAKE_CF)
    got = L.execute(r'''
      local st = ss_state()
      ss_preview_play()
      NOW = NOW + 21.0                       -- song bar 10.5
      local fills, lines = {}, {}
      local dl = {}
      reaper.ImGui_DrawList_AddRectFilled = function(_, x0, y0, x1, y1) fills[#fills + 1] = { x0, y0, x1, y1 } end
      reaper.ImGui_DrawList_AddLine = function(_, x0, y0, x1, y1) lines[#lines + 1] = { x0, y0, x1, y1 } end
      local long = ss_draw_slot_playhead(st, BY.drums, dl, 0, 100, 400, 140)
      local f1, l1 = fills[#fills], lines[#lines]
      local short = ss_draw_slot_playhead(st, BY.bass, dl, 0, 100, 400, 140)
      local f2 = fills[#fills]
      return long.hx, f1[2], f1[4], l1[1], l1[2], l1[4], short.hx, f2[3], short.label
    ''')
    long_hx, fy0, fy1, lx, ly0, ly1, short_hx, short_fill_x1, short_label = got
    # 16-bar loop at its bar 10.5: 10.5/16 of the row; 8-bar loop at its bar 2.5: 2.5/8
    assert abs(long_hx - 400 * 10.5 / 16) < 1e-9
    assert fy0 == 101 and fy1 == 139 and lx == long_hx and ly0 == 101 and ly1 == 139
    assert abs(short_hx - 400 * 2.5 / 8) < 1e-9 and abs(short_fill_x1 - short_hx) < 1e-9
    assert short_label == "3/8"


def test_every_row_gets_a_playhead_and_a_meter():
    L = _runtime()
    L.execute(FAKE_CF)
    got = L.execute(r'''
      local st = ss_state()
      BY.top.muted = true
      ss_preview_play()
      NOW = NOW + 3.0
      ss_preview_update()
      local labels = {}
      reaper.ImGui_DrawList_AddText = function(_, x, y, c, s) if tostring(s):match("^%d+/%d+$") then labels[#labels + 1] = s end end
      render_song_starter_window()
      local loaded = 0
      for _, s in ipairs(st.slots) do if s.path then loaded = loaded + 1 end end
      local dv = SS_PLAY.voices[BY.drums.id].meter
      local tv = SS_PLAY.voices[BY.top.id].meter
      local mm = ss_master_meter()
      return #ERRORS, ERRORS[1], #labels, loaded, dv[1], dv[2], dv.hold[1], tv[1], mm[1], ss_meter_available()
    ''')
    n_err, first, n_labels, loaded, l, r_, hold, muted_peak, master, avail = got
    assert n_err == 0, first
    assert n_labels == loaded and loaded >= 5
    assert l == 0.5 and r_ == 0.25 and hold == 0.5
    assert muted_peak == 0          # post-volume: muted slot reads silent
    assert master == 0.5 and avail


def test_meter_peak_hold_falls_after_a_second():
    L = _runtime()
    got = L.execute(r'''
      local P = 1.0
      reaper.CF_Preview_GetPeak = function() return true, P end
      local v = { obj = {} }
      ss_meter_read(v, 0.0)
      P = 0.01
      ss_meter_read(v, 0.5)
      local held = v.meter.hold[1]
      ss_meter_read(v, 1.5)            -- 0.5 s past the hold: fell part way
      local falling = v.meter.hold[1]
      ss_meter_read(v, 3.0)            -- fell all the way to the live level
      return held, falling < 1.0 and falling > 0.01, v.meter.hold[1]
    ''')
    held, falling_ok, final = got
    assert held == 1.0 and falling_ok and abs(final - 0.01) < 1e-9


def test_meters_hidden_without_peak_api():
    L = _runtime()
    L.execute(FAKE_CF)
    got = L.execute(r'''
      rawset(reaper, "CF_Preview_GetPeak", false)
      local st = ss_state()
      ss_preview_play()
      ss_preview_update()
      local tl = ss_draw_cycle_timeline(st, 720)
      local any_meter = false
      for _, v in pairs(SS_PLAY.voices) do if v.meter then any_meter = true end end
      render_song_starter_window()
      return ss_meter_available(), tl.master == nil, tl.w == 720, any_meter, #ERRORS
    ''')
    assert got == (False, True, True, False, 0)


# --- S / M keys on the hovered row ----------------------------------------------

KEYS = r"""
  PRESSED = {}
  reaper.ImGui_Key_S = function() return 83 end
  reaper.ImGui_Key_M = function() return 77 end
  reaper.ImGui_Key_Space = function() return 32 end
  reaper.ImGui_IsKeyPressed = function(_, k) return PRESSED[k] == true end
  reaper.ImGui_IsAnyItemActive = function() return ITEM_ACTIVE == true end
  CAPTURED = 0
  reaper.ImGui_SetNextFrameWantCaptureKeyboard = function() CAPTURED = CAPTURED + 1 end
  is_shift_down = function() return SHIFT == true end
  imgui_text_input_active = function() return TEXT_ACTIVE == true end
  is_ctrl_down = function() return false end
  is_alt_down = function() return false end
  is_cmd_down = function() return false end
  local st = ss_state()
  st.target_bpm, st.chaos, st.key_auto, st.target_key, st.open = 120, 0.0, false, "Am", true
  ss_do_reroll("batch")
"""


def test_s_and_m_keys_toggle_the_hovered_row():
    L = _runtime()
    L.execute(KEYS)
    got = L.execute(r'''
      local st = ss_state()
      local slot = st.slots[3]
      st._hover_slot_id = slot.id
      PRESSED[83] = true
      local a = ss_handle_row_keys(st)
      local solo1 = slot.solo
      PRESSED = { [77] = true }
      local b = ss_handle_row_keys(st)
      local muted1 = slot.muted
      -- with Shift held, or while a slider drag is active: nothing
      SHIFT = true
      local c = ss_handle_row_keys(st)
      SHIFT, ITEM_ACTIVE = false, true
      local d = ss_handle_row_keys(st)
      ITEM_ACTIVE, TEXT_ACTIVE = false, true
      d = d or ss_handle_row_keys(st)
      TEXT_ACTIVE = false
      -- no hovered row: nothing
      st._hover_slot_id = nil
      local e = ss_handle_row_keys(st)
      local others = false
      for i, s in ipairs(st.slots) do if i ~= 3 and (s.solo or s.muted) then others = true end end
      return a, solo1, b, muted1, c, d, e, others, CAPTURED, slot.muted
    ''')
    a, solo1, b, muted1, c, d, e, others, captured, still_muted = got
    assert (a, solo1, b, muted1) == ("solo", True, "mute", True)
    assert c is None and d is None and e is None
    assert not others and captured == 2 and still_muted is True


def test_hover_in_window_marks_row_and_blocks_sample_map_shortcuts():
    L = _runtime()
    L.execute(KEYS)
    got = L.execute(r'''
      local st = ss_state()
      reaper.ImGui_IsMouseHoveringRect = function() return true end   -- every row (same rect in the stub)
      reaper.ImGui_IsWindowHovered = function() return true end
      PRESSED = { [77] = true }
      render_song_starter_window()
      local last = st.slots[#st.slots]
      local hot = SS_WINDOW_HOT
      -- Sample Map's shortcut handler stands down while the window is hot
      local ran = 0
      reaper.Main_OnCommand = function() ran = ran + 1 end
      PRESSED = { [32] = true }
      handle_script_keyboard_shortcuts()
      local blocked = ran
      SS_WINDOW_HOT = false
      handle_script_keyboard_shortcuts()
      return #ERRORS, ERRORS[1], last.muted, hot, blocked, ran
    ''')
    n_err, first, muted, hot, blocked, ran = got
    assert n_err == 0, first
    assert muted is True and hot is True
    assert blocked == 0
    assert ran >= 1  # not hot: Space reaches Sample Map's play_stop (REAPER transport)


def test_every_voice_meters_despite_sws_loop_flag_bug():
    # SWS CF_Preview: setLoop hands the OLD loop state to its source, so after a
    # single B_LOOP=1 the source isn't looping, the first block at time 0 counts
    # as a wrap-around and GetPeak reads 0 forever after. Model that and check
    # every voice still meters.
    L = _runtime()
    L.execute(FAKE_CF)
    got = L.execute(r'''
      reaper.CF_CreatePreview = function(src) return { vals = {}, loop = false, src_looping = false } end
      reaper.CF_Preview_SetValue = function(o, k, v)
        if k == "B_LOOP" then
          o.src_looping = o.loop      -- the SWS bug: old value
          o.loop = v == 1 or v == true
        end
        o.vals[k] = v
        return true
      end
      reaper.CF_Preview_Play = function(o)
        o.wrapped = not o.src_looping and not o.vals.D_POSITION   -- first block at 0 = "wrap"
        return true
      end
      reaper.CF_Preview_GetPeak = function(o, ch)
        if o.wrapped or (o.vals.D_VOLUME or 0) <= 0 then return true, 0 end
        return true, 0.5
      end
      local st = ss_state()
      ss_preview_play()
      ss_preview_update()
      local metering, total = 0, 0
      for _, v in pairs(SS_PLAY.voices) do
        total = total + 1
        if v.meter and v.meter[1] > 0 then metering = metering + 1 end
      end
      -- a re-rolled slot swapped in while playing meters too
      NOW = NOW + 1.0
      ss_do_reroll(BY.chords)
      ss_preview_update()
      local swapped = SS_PLAY.voices[BY.chords.id]
      return metering, total, swapped and swapped.meter and swapped.meter[1] or -1
    ''')
    metering, total, swapped = got
    assert total >= 5 and metering == total
    assert swapped == 0.5


# --- Recent cards with likes ----------------------------------------------------

def test_pins_migrate_to_likes_and_filter_persists():
    L = _runtime()
    got = L.execute(r'''
      local f = io.open(SS_FILE, "w")
      f:write('{"v":1,"hist_filter":"liked","history":[' ..
        '{"t":1,"bpm":120,"key":"Am","pinned":true,"slots":[{"role":"drums","path":"/a.wav"}]},' ..
        '{"t":2,"bpm":124,"key":"C","slots":[{"role":"bass","path":"/b.wav"}]}]}')
      f:close()
      state.song_starter = nil
      local st = ss_state()
      local h1, h2 = st.history[1], st.history[2]
      local vis = ss_history_visible(st)
      ss_save_now()
      state.song_starter = nil
      local st2 = ss_state()
      return h1.liked, h1.pinned, h2.liked, st.hist_filter, #vis, vis[1].h == h1, st2.hist_filter, st2.history[1].liked
    ''')
    assert got == (True, None, None, "liked", 1, True, "liked", True)


def test_like_button_toggles_current_and_filter_shows_only_liked():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")          -- pushes an unliked entry
      local n0 = #st.history
      local on = ss_toggle_like_current(st)
      local n1 = #st.history
      local liked1 = ss_history_find_current(st).liked
      ss_do_reroll("unlocked")       -- a new unliked one
      st.hist_filter = "all"
      local all = #ss_history_visible(st)
      st.hist_filter = "liked"
      local liked = #ss_history_visible(st)
      -- unlike via the same button after recalling the liked one
      local lh
      for _, h in ipairs(st.history) do if h.liked then lh = h end end
      ss_history_recall(st, lh)
      ss_toggle_like_current(st)
      return n0, on, n1, liked1, all, liked, lh.liked, ss_liked_count(st)
    ''')
    n0, on, n1, liked1, n_all, n_liked, after, count = got
    assert n0 == 1 and on is True and n1 == 1 and liked1 is True
    assert n_all == 2 and n_liked == 1
    assert after is None and count == 0


def test_cards_draw_recall_and_heart_click():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.open = 120, 0.0, false, "Am", true
      ss_do_reroll("batch")
      st.mode, st.template = "arrange", "club"
      ss_arrangement(st, true)
      ss_history_push(st, false)
      st.mode = "loop"
      st.target_bpm = 98
      ss_do_reroll("unlocked")
      local texts, rects = {}, 0
      reaper.ImGui_DrawList_AddText = function(_, x, y, c, s) texts[#texts + 1] = s end
      reaper.ImGui_DrawList_AddRectFilled = function() rects = rects + 1 end
      reaper.ImGui_BeginChild = function() return true end
      local res = ss_history_cards(st)
      render_song_starter_window()
      local joined = table.concat(texts, "|")
      -- click the arrange card's body: recall; click its heart: like, no recall
      local target
      for i, h in ipairs(st.history) do if h.mode == "arrange" then target = i end end
      local h = st.history[target]
      reaper.ImGui_InvisibleButton = function(_, id) return id == "##ss_card_" .. target end
      reaper.ImGui_GetItemRectMin = function() return 100, 200 end
      reaper.ImGui_GetMousePos = function() return 130, 260 end   -- body
      st.mode = "loop"
      ss_history_cards(st)
      local recalled_mode = st.mode
      reaper.ImGui_GetMousePos = function() return 100 + SS_CARD - 13, 212 end   -- heart
      st.target_bpm = 77
      ss_history_cards(st)
      return #ERRORS, ERRORS[1], res.shown, joined:find("CLUB", 1, true) ~= nil, joined:find("98 BPM", 1, true) ~= nil,
             joined:find("now", 1, true) ~= nil, rects > 10, recalled_mode, h.liked, st.target_bpm
    ''')
    n_err, first, shown, has_club, has_bpm, has_time, drew, recalled_mode, liked, bpm = got
    assert n_err == 0, first
    assert shown == 3 and has_club and has_bpm and has_time and drew
    assert recalled_mode == "arrange"
    assert liked is True and bpm == 77   # heart click liked it without recalling


def test_relative_time_labels():
    L = _runtime()
    f = L.globals().ss_rel_time
    assert f(1000, 1030) == "now"
    assert f(1000, 1000 + 5 * 60) == "5m"
    assert f(1000, 1000 + 3 * 3600) == "3h"
    assert f(1000, 1000 + 2 * 86400) == "2d"


# --- Heart, row controls, themed tooltips --------------------------------------

def test_heart_is_one_symmetric_closed_path():
    L = _runtime()
    got = L.execute(r'''
      local p = ss_heart_points(100, 100, 32, 28)
      local n = #p // 2
      local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
      for i = 1, #p, 2 do
        minx, maxx = math.min(minx, p[i]), math.max(maxx, p[i])
        miny, maxy = math.min(miny, p[i + 1]), math.max(maxy, p[i + 1])
      end
      -- t = 0 is the dip between the lobes, t = pi the point at the bottom
      local dip_y, point_y = p[2], p[n + 2]
      -- mirror symmetry: point i and point n - i
      local sym = 0
      for i = 1, n - 1 do
        local a, b = i + 1, n - i + 1
        sym = math.max(sym, math.abs((p[2 * a - 1] - 100) + (p[2 * b - 1] - 100)), math.abs(p[2 * a] - p[2 * b]))
      end
      local strokes, fills = 0, 0
      reaper.ImGui_DrawList_PathStroke = function(_, col, flags, th) strokes = strokes + 1; CLOSED = flags end
      reaper.ImGui_DrawList_PathFillConcave = function() fills = fills + 1 end
      reaper.ImGui_DrawFlags_Closed = function() return 1 end
      ss_draw_heart({}, 100, 100, 14, 0xFFFFFFFF, false)
      local s1, f1 = strokes, fills
      ss_draw_heart({}, 100, 100, 14, 0xFFFFFFFF, true)
      return n, maxx - minx, dip_y > miny + 3, point_y == maxy, sym < 1e-9, s1, f1, strokes, fills, CLOSED
    ''')
    n, width, dip_ok, point_ok, sym_ok, s1, f1, s2, f2, closed = got
    assert n == 28 and abs(width - 32) < 1.0
    assert dip_ok and point_ok and sym_ok
    assert (s1, f1, s2, f2, closed) == (1, 0, 2, 1, 1)


def test_row_controls_on_the_left_without_index():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.open = 120, 0.0, false, "Am", true
      ss_do_reroll("batch")
      local texts, ids, arcs = {}, {}, 0
      reaper.ImGui_DrawList_AddText = function(_, x, y, c, s) texts[#texts + 1] = s end
      reaper.ImGui_InvisibleButton = function(_, id) ids[#ids + 1] = id; return false end
      reaper.ImGui_DrawList_PathArcTo = function() arcs = arcs + 1 end
      local cursor = {}
      reaper.ImGui_SetCursorScreenPos = function(_, x, y) cursor[#cursor + 1] = { x, y } end
      render_song_starter_window()
      local joined = "|" .. table.concat(texts, "|") .. "|"
      local has_index = joined:find("|01|", 1, true) ~= nil or joined:find("|02|", 1, true) ~= nil
      local have = {}
      for _, id in ipairs(ids) do have[id] = (have[id] or 0) + 1 end
      -- clicking the roll icon re-rolls; the lock icon locks
      local slot = st.slots[1]
      local before = slot.path
      reaper.ImGui_InvisibleButton = function(_, id) return id == "##roll" end
      render_song_starter_window()
      local rolled = slot.path ~= before
      reaper.ImGui_InvisibleButton = function(_, id) return id == "##lock" end
      render_song_starter_window()
      return #ERRORS, ERRORS[1], has_index, have["##roll"], have["##lock"], have["##mute"], have["##solo"],
             arcs >= #st.slots * 2, rolled, slot.locked
    ''')
    n_err, first, has_index, n_roll, n_lock, n_mute, n_solo, icons, rolled, locked = got
    n = 6
    assert n_err == 0, first
    assert not has_index
    assert n_roll == n and n_lock == n and n_mute == n and n_solo == n
    assert icons and rolled and locked is True


def test_song_starter_tooltips_measure_and_draw_in_its_font():
    L = _runtime()
    got = L.execute(r'''
      SM_MONO_SPACE = true
      SM_MONO_FONTS = SM_MONO_FONTS or {}
      SM_MONO_FONTS.cond = { name = "cond" }
      local stack, measured_in, drawn_in = {}, {}, {}
      reaper.ImGui_PushFont = function(_, f) stack[#stack + 1] = f.name or "?" end
      reaper.ImGui_PopFont = function() stack[#stack] = nil end
      local function cur() return stack[#stack] or "body" end
      reaper.ImGui_CalcTextSize = function(_, s)
        measured_in[cur()] = true
        return #tostring(s) * (cur() == "cond" and 6 or 7), 14
      end
      reaper.ImGui_DrawList_AddText = function() drawn_in[cur()] = true end
      reaper.ImGui_BeginTooltip = function() return true end
      reaper.ImGui_GetMousePos = function() return 10, 10 end
      hint_state.layouts, hint_state.layout_count = {}, 0
      hint_state.still_since = NOW - 10
      hint_state.still_x, hint_state.still_y = 10, 10
      HINT_FONT_KIND = "cond"
      hint_request(ctx, "Solo (S key while hovering the row)")
      HINT_FONT_KIND = nil
      hint_card_flush()
      local keys = {}
      for k in pairs(hint_state.layouts) do keys[#keys + 1] = k end
      -- same text from a window in the body font: a separate layout
      hint_state.still_since = NOW - 10
      hint_request(ctx, "Solo (S key while hovering the row)")
      hint_card_flush()
      local n = 0
      for _ in pairs(hint_state.layouts) do n = n + 1 end
      return measured_in.cond == true, drawn_in.cond == true, #stack, keys[1], n
    ''')
    measured, drawn, depth, key, n_layouts = got
    assert measured and drawn and depth == 0
    assert key.startswith("space:cond:")
    assert n_layouts == 2


# --- Browse the loop's folder ---------------------------------------------------

FOLDER = r"""
  -- /lib/Drums holds: Drum Loop 120, Beat 124, Break 90, Drum Groove 60, Analyzed Loop 120
  mk("/lib/Drums/Drum Hit 120bpm.wav", 0.5, { "drum" })   -- a one-shot in the same folder
  rebuild_samples_path_index()
  local st = ss_state()
  st.target_bpm, st.chaos, st.key_auto, st.target_key, st.open = 120, 0.0, false, "Am", true
  ss_do_reroll("batch")
  DR = nil
  for _, s in ipairs(st.slots) do if s.role == "drums" then DR = s end end
  -- start from a known loop
  ss_slot_swap_to(st, DR, find_sample_by_path("/lib/Drums/Drum Loop 120bpm.wav"))
  DR.folder_nav = nil
"""


def test_folder_candidates_rank_by_fit_loops_first():
    L = _runtime()
    L.execute(FOLDER)
    got = L.execute(r'''
      local st = ss_state()
      local ranked = ss_folder_ranked(st, DR)
      local names = {}
      for _, c in ipairs(ranked) do names[#names + 1] = c.path:match("[^/]+$") end
      return table.concat(names, "|"), ranked[#ranked].loop
    ''')
    names, last_loop = got
    order = names.split("|")
    # exact-tempo loops first, the 60 (double time) and 90 bpm ones later, the one-shot last
    assert set(order[:2]) == {"Drum Loop 120bpm.wav", "Analyzed Loop 120bpm.wav"}
    assert order.index("Beat_124_bpm.wav") < order.index("Break 90bpm.wav")
    assert order[-1] == "Drum Hit 120bpm.wav" and last_loop is False


def test_folder_step_forward_back_and_wrap_keeps_lock():
    L = _runtime()
    L.execute(FOLDER)
    got = L.execute(r'''
      local st = ss_state()
      DR.locked = true
      local start = DR.path
      local seen = { DR.path:match("[^/]+$") }
      local pos, n = ss_folder_step(st, DR, 1)
      seen[#seen + 1] = DR.path:match("[^/]+$")
      local p2 = ss_folder_step(st, DR, 1)
      local back = ss_folder_step(st, DR, -1)
      local after_back = DR.path
      -- wrap backwards from the start
      for i = 1, back - 1 do ss_folder_step(st, DR, -1) end
      local at_start = DR.path == start
      local wpos = ss_folder_step(st, DR, -1)
      local hit = DR.path
      local nav = DR.folder_nav
      return pos, n, p2, back, after_back == nav.paths[2], at_start, wpos, hit == nav.paths[n], DR.locked,
             table.concat(seen, "|")
    ''')
    pos, n, p2, back, back_ok, at_start, wpos, wrap_ok, locked, seen = got
    assert n == 5                     # five loops, the one-shot is not stepped through
    assert pos == 2 and p2 == 3 and back == 2 and back_ok
    assert at_start and wpos == n and wrap_ok
    assert locked is True


def test_folder_step_swaps_in_place_while_playing():
    L = _runtime()
    L.execute(FAKE_CF)
    L.execute(FOLDER)
    got = L.execute(r'''
      local st = ss_state()
      ss_preview_play()
      local old = SS_PLAY.voices[DR.id]
      NOW = NOW + 3.0
      ss_folder_step(st, DR, 1)
      local v = SS_PLAY.voices[DR.id]
      return v ~= old, v.obj.vals.B_LOOP, v.obj.vals.D_POSITION ~= nil, SS_PLAY ~= nil
    ''')
    assert got == (True, 1, True, True)


def test_folder_popup_lists_files_and_swaps_on_click():
    L = _runtime()
    L.execute(FOLDER)
    got = L.execute(r'''
      local st = ss_state()
      reaper.EnumerateFiles = function(dir, i)
        if dir == "/lib/Drums" and i == 0 then return "Unscanned Loop 120bpm.wav" end
        if dir == "/lib/Drums" and i == 1 then return "readme.txt" end
        return nil
      end
      reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
      reaper.GetMediaSourceLength = function() return 8.0, false end
      reaper.PCM_Source_Destroy = function() end
      ss_folder_popup_open(st, DR)
      local texts = {}
      reaper.ImGui_BeginPopup = function(_, id) return id == "ss_folder_popup" end
      reaper.ImGui_BeginChild = function() return true end
      reaper.ImGui_DrawList_AddText = function(_, x, y, c, s) texts[#texts + 1] = s end
      local n = ss_folder_popup(st, DR)
      local joined = table.concat(texts, "|")
      -- search narrows the list
      st._folder.search = "unscanned"
      local n2 = #ss_folder_popup_rows(st._folder)
      st._folder.search = ""
      -- click the row of the unscanned file
      local target
      for i, c in ipairs(ss_folder_popup_rows(st._folder)) do
        if c.path:find("Unscanned", 1, true) then target = i end
      end
      local closed = false
      reaper.ImGui_CloseCurrentPopup = function() closed = true end
      reaper.ImGui_InvisibleButton = function(_, id) return id == "##ss_ff_" .. target end
      ss_folder_popup(st, DR)
      return n, joined:find("DRUMS", 1, true) ~= nil, joined:find("7 FILES", 1, true) ~= nil,
             joined:find("readme", 1, true) ~= nil, n2, DR.path, DR.dur, closed, st._folder == nil
    ''')
    n, header, count, readme, n2, path, dur, closed, cleared = got
    assert n == 7 and header and count and not readme
    assert n2 == 1
    assert path == "/lib/Drums/Unscanned Loop 120bpm.wav" and dur == 8.0
    assert closed and cleared


def test_playhead_backdrop_only_in_the_name_column():
    L = _runtime()
    L.execute(FAKE_CF)
    got = L.execute(r'''
      local st = ss_state()
      ss_preview_play()
      NOW = NOW + 21.0                       -- drums (16 bars) at bar 10.5
      local fills = {}
      reaper.ImGui_DrawList_AddRectFilled = function(_, x0, y0, x1, y1, col)
        if col == 0x49CC851C or col == 0x49CC850A then fills[#fills + 1] = { x0, x1 } end
      end
      render_song_starter_window()
      -- stub layout: row 52..788, role column 92, volume 92 + meter 19, nav 60
      local left, right = 52 + 92, 52 + 92 + 8 + (788 - 92 - 6 - 19 - (52 + 92 + 8) - 8 - 68) + 4
      local ok = #fills > 0
      for _, f in ipairs(fills) do
        if f[1] ~= left + 1 or f[2] > right + 1e-9 or f[2] < left then ok = false end
      end
      local dr = ss_draw_slot_playhead(st, BY.drums, {}, left, 0, right, 40)
      return ok, #fills, #ERRORS, math.abs(dr.hx - (left + (right - left) * 10.5 / 16)) < 1e-9
    ''')
    ok, n, n_err, mapped = got
    assert ok and n >= 5 and n_err == 0 and mapped


# --- Drag samples in and out ----------------------------------------------------

def test_sample_map_drag_drops_into_hovered_row():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.open = 120, 0.0, false, "Am", true
      ss_do_reroll("batch")
      local target = st.slots[2]
      target.locked = true
      local s = find_sample_by_path("/lib/Drums/Break 90bpm.wav")
      state.pending_waveform_drop = s
      reaper.ImGui_IsMouseDown = function() return false end
      st._drop_hover_id = target.id
      local took = ss_take_sample_drop(st)
      -- through the window: hovering a row while dragging marks it, release drops
      local other = st.slots[4]
      state.pending_waveform_drop = find_sample_by_path("/lib/Bass/Bassline 118 bpm Cm.wav")
      reaper.ImGui_IsMouseHoveringRect = function() return true end
      reaper.ImGui_IsWindowHovered = function() return true end
      imgui_text_input_active = function() return false end   -- the stub has no ImGui IO
      is_shift_down, is_ctrl_down, is_alt_down, is_cmd_down = function() return false end, function() return false end,
        function() return false end, function() return false end
      render_song_starter_window()
      local last = st.slots[#st.slots]
      return took, target.path, target.locked, state.pending_waveform_drop == nil, #ERRORS, last.path
    ''')
    took, path, locked, cleared, n_err, last_path = got
    assert took and path == "/lib/Drums/Break 90bpm.wav" and locked is True and cleared
    assert n_err == 0
    # the stub draws every row on one rect, so the drop zone (hovered too) wins: a new slot
    assert last_path == "/lib/Bass/Bassline 118 bpm Cm.wav"


def test_finder_files_swap_and_add_slots():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key = 120, 0.0, false, "Am"
      ss_do_reroll("batch")
      reaper.PCM_Source_CreateFromFile = function(p) return { path = p } end
      reaper.GetMediaSourceLength = function() return 8.0, false end
      reaper.PCM_Source_Destroy = function() end
      local files = { "/new/Sub Bass Line 120bpm.wav", "/new/notes.txt", "/new/Shaker Top 120bpm.wav", "/new/Pad Wash.wav" }
      reaper.ImGui_BeginDragDropTarget = function() return true end
      reaper.ImGui_EndDragDropTarget = function() end
      reaper.ImGui_AcceptDragDropPayloadFiles = function() return true, #files end
      reaper.ImGui_GetDragDropPayloadFile = function(_, i) return true, files[i + 1] end
      local n0 = #st.slots
      -- onto the 5th row: 3 audio files -> rows 5, 6, then a new slot
      local hovering = ss_os_drop_target(st, st.slots[5])
      local r5, r6, r7 = st.slots[5].path, st.slots[6].path, st.slots[7] and st.slots[7].path
      local new_role = st.slots[7] and st.slots[7].role
      -- onto the add zone: all new slots, roles guessed
      files = { "/new/Sub Bass Line 120bpm.wav" }
      ss_os_drop_target(st, nil)
      local added = st.slots[#st.slots]
      return hovering, n0, r5, r6, r7, new_role, #st.slots, added.role, added.dur
    ''')
    hovering, n0, r5, r6, r7, new_role, n_slots, added_role, dur = got
    assert hovering and n0 == 6
    assert r5 == "/new/Sub Bass Line 120bpm.wav" and r6 == "/new/Shaker Top 120bpm.wav" and r7 == "/new/Pad Wash.wav"
    assert new_role == "texture" and n_slots == 8
    assert added_role == "bass" and dur == 8.0


def test_drag_out_inserts_stretched_item_at_drop_and_raw_with_shift():
    L = _runtime()
    L.execute(FAKE_PROJECT)
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.bars = 124, 0.0, false, "Am", 8
      ss_do_reroll("batch")
      local slot = st.slots[3]
      local TR = { depth = 0, items = {}, P_NAME = "Arrange track" }
      reaper.ValidatePtr = function(p) return p ~= nil end
      reaper.ValidatePtr2 = function(_, p) return p ~= nil end
      reaper.DeleteTrackMediaItem = function() end
      reaper.ImGui_IsMouseDown = function() return DOWN == true end
      reaper.CountSelectedMediaItems = function() return 0 end
      DOWN = true
      ss_begin_drag_out(st, slot, false)
      local provisional_seen = false
      update_provisional_drop = function(s) provisional_seen = s.path == slot.path and math.abs(s.duration - 8 * 240 / 124) < 1e-9 end
      local a = ss_drag_out_update(st)
      -- release over the arrange: the preview sat on TR at 6.0 s
      DOWN = false
      state.provisional_drop = { item = {}, track = TR, time = 6.0 }
      local b = ss_drag_out_update(st)
      local it = ITEMS[#ITEMS]
      local stretched = { it.tr == TR, it.D_POSITION, it.D_LENGTH, it.B_LOOPSRC, it.take.B_PPITCH,
        math.abs(it.take.D_PLAYRATE - slot.rate) < 1e-9, it.take.D_PITCH == slot.shift }
      -- Shift: the plain file, its own length, no stretch
      DOWN = true
      ss_begin_drag_out(st, slot, true)
      DOWN = false
      state.provisional_drop = { item = {}, track = TR, time = 2.0 }
      ss_drag_out_update(st)
      local raw = ITEMS[#ITEMS]
      return a, provisional_seen, b, UNDO[#UNDO], stretched[1], stretched[2], stretched[3], stretched[4],
             stretched[5], stretched[6], stretched[7], raw.D_LENGTH == slot.dur, raw.take.D_PLAYRATE, raw.B_LOOPSRC,
             SS_DRAG == nil
    ''')
    (a, prov, b, undo, on_tr, pos, length, loopsrc, ppitch, rate_ok, pitch_ok, raw_len, raw_rate, raw_loop,
     done) = got
    assert a == "drag" and prov and b == "inserted" and undo == "Song Starter: insert loop"
    assert on_tr and pos == 6.0 and abs(length - 8 * 240 / 124) < 1e-9 and loopsrc == 1 and ppitch == 1
    assert rate_ok and pitch_ok
    assert raw_len and raw_rate is None and raw_loop == 0 and done


def test_drag_out_does_not_audition_and_needs_threshold():
    L = _runtime()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.chaos, st.key_auto, st.target_key, st.open = 120, 0.0, false, "Am", true
      ss_do_reroll("batch")
      local auditioned = {}
      preview_sample = function(smp) auditioned[smp.path] = true end
      reaper.ImGui_IsItemActive = function() return true end
      DRAGGING = false
      reaper.ImGui_IsMouseDragging = function(_, b, th) return DRAGGING and th == 6.0 end
      reaper.ImGui_IsMouseDown = function() return true end
      render_song_starter_window()
      local before = SS_DRAG ~= nil
      DRAGGING = true
      render_song_starter_window()
      local started = SS_DRAG ~= nil
      -- release over the name: no audition after a drag
      reaper.ImGui_IsMouseDown = function() return false end
      reaper.ImGui_InvisibleButton = function(_, id) return id == "##name" end
      reaper.ImGui_IsItemActive = function() return false end
      render_song_starter_window()
      -- every row reports a click in this stub; only the dragged one must not audition
      local dragged = st.slots[1]
      return before, started, auditioned[dragged.path] == true, #ERRORS
    ''')
    assert got == (False, True, False, 0)

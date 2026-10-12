"""Tagging: filename tagger, tempo / key, loop fill-in, Key / Tempo groups,
Library tag cleanup, guessed drum tags and Re-tag Library with its preview.
Loads the whole browser with the stub REAPER API from load_browser.py.
Requires `pip install lupa`."""
import os
import re
import tempfile

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def _runtime():
    src = open(os.path.join(HERE, "load_browser.py"), encoding="utf-8").read()
    stub = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    g.FRAMES = 0
    err = L.execute(stub + r'''
      local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
      if not chunk then return err end
      local ok, e = xpcall(chunk, debug.traceback)
      if not ok then return e end
      log = function() end
      save_config = function() end
      save_samples = function() end
      state.folders = { "/Users/me/Samples" }
      return nil
    ''')
    assert err is None, err
    return L


def test_filename_tagger():
    L = _runtime()
    tags = lambda p: L.eval('function(p) return table.concat(infer_tags_from_path(p, ""), ",") end')(p)
    root = "/Users/me/Samples/"
    assert tags(root + "Pack/Drum Hits/KickHard01.wav") == "kick,drum"
    assert tags(root + "Pack/Drum Hits/HiHat_Closed_03.wav") == "hat,drum"
    assert tags(root + "Pack/Drum Hits/HHOpen 2.wav") == "hat,drum"
    # The file name wins over its folder: a kick in a "Bass Music" pack is no bass.
    assert tags(root + "Bass Music Vol 2/One Shots/Kick 07.wav") == "kick"
    # Plural folder names and new keywords.
    assert tags(root + "Pack/Snares/Tight 4.wav") == "snare"
    assert tags(root + "Pack/Percussion/Conga Hi.wav") == "perc"
    assert tags(root + "Pack/Keys/Rhodes Chord Am.wav") == "keys"
    assert tags(root + "Pack/BD/x 01.wav") == "kick"
    # "bass drum" is a kick, not bass + drum.
    assert tags(root + "Pack/Bass Drum 3.wav") == "kick"
    # Folders above the scan folder never tag a sample.
    assert tags("/Users/me/Samples/Fx/Loose/Thing 1.wav") == "fx"
    L.execute('state.folders = { "/Volumes/Drums Drive/Library" }')
    assert tags("/Volumes/Drums Drive/Library/Pads/Warm.wav") == "pad"


def test_tempo_and_key_from_names():
    L = _runtime()
    bpm = L.eval("function(s) return sm_bpm_from_name(s) end")
    key = L.eval("function(s) return sm_key_from_name(s) end")
    assert bpm("Groove_120bpm_Am") == 120
    assert bpm("Drums 95 BPM") == 95
    assert bpm("BPM-174 roller") == 174
    assert bpm("Hit 1200bpm") is None
    assert bpm("Hit 40bpm") is None
    assert key("Chord_Am_120") == "Am"
    assert key("Lead F#min") == "F#m"
    assert key("Pad Bb_Major") == "Bb"
    assert key("Pad Fbmin 2") == "Fbm"
    assert key("Bass C# minor") == "C#m"
    assert key("Pluck Asharp minor") == "A#m"
    assert key("Keys Eb 3") == "Eb"
    assert key("Amen Break") is None
    assert key("Bass 01") is None
    assert key("Dm7 stab") is None
    bk = L.eval("function(p) local b, k = sm_sample_bpm_key(p) return tostring(b) .. '|' .. tostring(k) end")
    assert bk("/Users/me/Samples/Pack/Loops 128 BPM/Chord Gm.wav") == "128|Gm"


def test_loop_fill_in_from_tempo_and_length():
    L = _runtime()
    detect = L.eval("function(p, pt, d) return detect_loop_or_oneshot(p, '', pt, d) end")
    p = "/Users/me/Samples/Pack/Groove 120bpm 3.wav"
    assert detect(p, "unknown", 4.0) == "loop"      # 8 beats
    assert detect(p, "unknown", 4.01) == "loop"     # within 0.06 of a beat
    assert detect(p, "unknown", 3.75) is None       # 7.5 beats
    assert detect(p, "unknown", 1.5) is None        # 3 beats: odd
    assert detect(p, "unknown", None) is None
    assert detect("/Users/me/Samples/Pack/Hit 3.wav", "unknown", 4.0) is None
    assert detect(p, "oneshot", 4.0) == "One shot"  # the audio check still wins


def test_key_and_tempo_groups():
    L = _runtime()
    out = L.execute(r'''
      state.samples = {
        { path = "/a/1.wav", tags = { "kick", "120 bpm", "Am" } },
        { path = "/a/2.wav", tags = { "95 bpm", "C" } },
        { path = "/a/3.wav", tags = { "174 bpm", "F#m", "C#" } },
        { path = "/a/4.wav", tags = { "95 bpm", "Am" } },
      }
      rebuild_tag_index()
      local drum, melodic, genre, loop, extra, key, tempo = sm_collect_tag_groups()
      local function names(list) local o = {} for i, e in ipairs(list) do o[i] = e.tag end return table.concat(o, ",") end
      local groups = {}
      for _, g in ipairs(sm_tag_group_list()) do groups[#groups + 1] = g.key end
      return names(key) .. "/" .. names(tempo) .. "/" .. table.concat(groups, ",") .. "/" .. tag_chip_kind("Am") .. "/" .. categorize_tags("kick")
    ''')
    assert out == "C,C#,F#m,Am/95 bpm,120 bpm,174 bpm/drum,key,tempo/attr/drum"


def test_library_tags_drop_pack_names_and_fragments():
    L = _runtime()
    out = L.execute(r'''
      state.folders = { "/S" }
      state.custom_tags, state.deleted_tags = {}, {}
      state.samples = {}
      local function add(dir, n)
        for i = 1, n do
          state.samples[#state.samples + 1] = { path = "/S/" .. dir .. "/s" .. i .. ".wav", tags = {} }
        end
      end
      -- "lofi grit" spans three packs, "lofi" never appears without "grit".
      add("Alpha/Lofi Grit", 20) add("Beta/Lofi Grit", 20) add("Gamma/Lofi Grit", 20)
      -- "vendorx" lives in two packs only: a vendor name.
      add("VendorX One/Kit", 30) add("VendorX Two/Kit", 30)
      -- "dusty" recurs in three packs.
      add("Delta/Dusty", 20) add("Eps/Dusty", 20) add("Zeta/Dusty", 20)
      -- Boom bap fragments and key words never become Library tags.
      add("P1/Boom Bap Minor", 20) add("P2/Boom Bap Minor", 20) add("P3/Boom Bap Minor", 20)
      apply_discovered_library_tags()
      local t = {}
      for tag in pairs(state.discovered_library_tag_set) do t[#t + 1] = tag end
      table.sort(t)
      return table.concat(t, ",")
    ''')
    assert out == "dusty,lofi grit"


def test_cache_keeps_bpm_key_and_guess():
    L = _runtime()
    out = L.execute(r'''
      local dirs, dir_idx = {}, {}
      local function intern_dir(d) if not dir_idx[d] then dirs[#dirs + 1] = d dir_idx[d] = #dirs end return dir_idx[d] end
      local tags, tag_idx = {}, {}
      local function intern_tag(t) if not tag_idx[t] then tags[#tags + 1] = t tag_idx[t] = #tags end return tag_idx[t] end
      local row = SampleCacheCodec.compact_sample({ path = "/a/b.wav", tags = { "120 bpm" }, bpm = 120, key = "Am", guess_tag = "kick" }, intern_dir, intern_tag)
      local s = SampleCacheCodec.expand_sample(row, dirs, tags)
      return tostring(s.bpm) .. "|" .. tostring(s.key) .. "|" .. tostring(s.guess_tag)
    ''')
    assert out == "120|Am|kick"


# Synthetic library: named kicks / hats / snares plus unnamed one-shots.
LIBRARY_LUA = r'''
function make_guess_library()
  state.folders = { "/S" }
  state.custom_tags, state.deleted_tags = {}, {}
  local samples = {}
  local seed = 11
  local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  end
  local kinds = {
    kick = { e = 0.45, f = 55, b = 300, w = 0.85, att = 0.02, rms = 0.30 },
    hat = { e = 0.12, f = 7000, b = 9000, w = 0.02, att = 0.004, rms = 0.08 },
    snare = { e = 0.30, f = 200, b = 3000, w = 0.20, att = 0.010, rms = 0.20 },
  }
  local function add(path, k)
    local p = kinds[k]
    local j = function(v) return v * (0.85 + 0.3 * rnd()) end
    samples[#samples + 1] = {
      path = path, name = path:match("([^/]+)$"), folder = path:match("(.+)/[^/]+$"),
      tags = {}, duration = j(p.e) + 0.05, effective_duration = j(p.e), dominant_freq = j(p.f),
      brightness = j(p.b), sub_weight = math.min(1, j(p.w)), onset = 0.001,
      transient_end = 0.001 + j(p.att), rms_energy = j(p.rms), playback_type = "oneshot",
    }
  end
  for i = 1, 120 do
    add("/S/Pack/Kicks/Kick " .. i .. ".wav", "kick")
    add("/S/Pack/Hats/Hat " .. i .. ".wav", "hat")
    add("/S/Pack/Snares/Snare " .. i .. ".wav", "snare")
  end
  for i = 1, 20 do
    add("/S/Mystery/Hit A" .. i .. ".wav", "kick")
    add("/S/Mystery/Hit B" .. i .. ".wav", "hat")
  end
  -- A loop with a tempo in its name whose loop / one-shot is unknown.
  samples[#samples + 1] = { path = "/S/Loops/Chords 120bpm Am.wav", tags = {}, duration = 8.0, playback_type = "unknown" }
  for _, s in ipairs(samples) do
    s.tags = sm_retag_sample_tags(s)
  end
  state.samples = samples
  rebuild_tag_index()
  return samples
end
'''


def test_guessed_drum_tags_and_filters():
    L = _runtime()
    L.execute(LIBRARY_LUA)
    out = L.execute(r'''
      local samples = make_guess_library()
      sm_start_guess_refresh()
      local n = 0
      while state.guess_refresh and n < 10000 do process_guess_refresh_slice(5) n = n + 1 end
      local right, wrong, named = 0, 0, 0
      for _, s in ipairs(samples) do
        local want = s.path:find("Hit A", 1, true) and "kick" or s.path:find("Hit B", 1, true) and "hat" or nil
        if want then
          if s.guess_tag == want then right = right + 1 elseif s.guess_tag then wrong = wrong + 1 end
        elseif s.guess_tag then
          named = named + 1
        end
      end
      local kicks_shown = #(state.samples_by_tag.kick or {})
      set_show_guessed_tags(false)
      local kicks_hidden = #(state.samples_by_tag.kick or {})
      return right .. "|" .. wrong .. "|" .. named .. "|" .. kicks_shown .. "|" .. kicks_hidden
    ''')
    right, wrong, named, shown, hidden = map(int, out.split("|"))
    assert right >= 36 and wrong == 0 and named == 0, out
    assert shown == hidden + 20, out


def test_retag_preview_then_apply():
    L = _runtime()
    L.execute(LIBRARY_LUA)
    out = L.execute(r'''
      local samples = make_guess_library()
      -- Old-style tags: no tempo / key / loop, a stale fragment tag.
      for _, s in ipairs(samples) do s.tags = { "kick", "min" } end
      local groove = samples[#samples]
      sm_start_retag()
      local n = 0
      while state.retag_job and n < 10000 do process_retag_slice(5) n = n + 1 end
      local pv = state.retag_preview
      assert(pv, "no preview")
      local unchanged = table.concat(groove.tags, ",")
      local rows = {}
      for _, row in ipairs(pv.rows) do rows[row.tag] = row.after - row.before end
      sm_apply_retag(pv)
      return table.concat({ unchanged, tostring(pv.changed), tostring(rows["min"]), tostring(rows["120 bpm"]),
        table.concat(groove.tags, ","), tostring(groove.bpm), tostring(groove.key), tostring(pv.guessed > 0),
        tostring(state.retag_preview), tostring(#(state.samples_by_tag["120 bpm"] or {})) }, "|")
    ''')
    parts = out.split("|")
    assert parts[0] == "kick,min"                     # nothing changes before Apply
    assert int(parts[1]) == 401
    assert parts[2] == "-401" and parts[3] == "1"
    assert parts[4] == "loop,120 bpm,Am", parts[4]
    assert parts[5:] == ["120", "Am", "true", "nil", "1"]


def test_retag_stops_when_library_changes():
    L = _runtime()
    L.execute(LIBRARY_LUA)
    out = L.execute(r'''
      make_guess_library()
      sm_start_retag()
      process_retag_slice(0)
      state.samples = { { path = "/S/x.wav", tags = {} } }
      process_retag_slice(5)
      return tostring(state.retag_job) .. "|" .. tostring(state.retag_preview)
    ''')
    assert out == "nil|nil"

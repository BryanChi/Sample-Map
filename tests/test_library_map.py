"""Library/map fixes: waveform building leaves no project footprint, scan-folder
path matching, rescan pruning. Loads the whole browser with the stub REAPER API
from load_browser.py. Requires `pip install lupa`."""
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
      return nil
    ''')
    assert err is None, err
    return L


def test_waveform_reads_peaks_without_touching_the_project():
    L = _runtime()
    out = L.execute(r'''
      local touched = {}
      for _, name in ipairs({ "AddMediaItemToTrack", "InsertTrackAtIndex", "CreateTakeAudioAccessor" }) do
        reaper[name] = function() touched[#touched + 1] = name end
      end
      reaper.PCM_Source_CreateFromFile = function(p) return { file = p } end
      reaper.GetMediaSourceLength = function() return 2.0, false end
      reaper.GetMediaSourceSampleRate = function() return 44100 end
      reaper.GetMediaSourceNumChannels = function() return 1 end
      local builds = 0
      reaper.PCM_Source_BuildPeaks = function(_, mode)
        if mode == 0 then return 1 end
        if mode == 1 then builds = builds + 1; return builds < 3 and 1 or 0 end
        return 0
      end
      reaper.new_array = function(n)
        local a = { clear = function() end }
        return a
      end
      local destroyed = 0
      reaper.PCM_Source_Destroy = function() destroyed = destroyed + 1 end
      reaper.PCM_Source_GetPeaks = function(_, _, _, nch, n, _, buf)
        for i = 1, nch * n do buf[i] = (i % 7) / 10 end
        for i = nch * n + 1, nch * n * 2 do buf[i] = -(i % 5) / 10 end
        return n
      end
      local sample = { path = "/lib/kick.wav", duration = 2.0, channels = 1 }
      ensure_waveform_for_sample(sample)
      for _ = 1, 20 do
        if not waveform_gen_job then break end
        process_waveform_slice(6.0)
      end
      return table.concat(touched, ","), waveform_is_ready(sample) and "ready" or "not ready",
        #waveform_data.data, destroyed
    ''')
    touched, ready, n, destroyed = out
    assert touched == ""
    assert ready == "ready"
    assert n > 0
    assert destroyed == 1


def test_removing_a_folder_respects_path_separators_and_keeps_tag_filters():
    L = _runtime()
    out = L.execute(r'''
      state.folders = { "/lib/Drums" }
      state.samples = {
        { path = "/lib/Drums2/kick.wav", tags = { "kick" } },
        { path = "/lib/Drums/snare.wav", tags = { "snare" } },
        { path = "/lib/Drums/sub/hat.wav", tags = { "hat" } },
      }
      state.active_tags = { snare = true }
      local removed = filter_samples_by_folders()
      local names = {}
      for _, s in ipairs(state.samples) do names[#names + 1] = s.path end
      return removed, table.concat(names, ","), state.active_tags.snare and "kept" or "cleared",
        state.tag_counts.snare or 0
    ''')
    removed, names, filt, snare = out
    assert removed == 1
    assert names == "/lib/Drums/snare.wav,/lib/Drums/sub/hat.wav"
    assert filt == "kept"
    assert snare == 1


def test_rescan_prunes_missing_files_only_in_reachable_folders():
    L = _runtime()
    out = L.execute(r'''
      local files = {
        ["/lib/A"] = { "kick.wav" },
        ["/lib/A/kick.wav"] = true,
      }
      reaper.EnumerateFiles = function(dir, i)
        local list = files[dir]
        if type(list) ~= "table" or i < 0 then return nil end
        return list[i + 1]
      end
      reaper.EnumerateSubdirectories = function(dir, i)
        if dir == "/lib/A" and i == 0 then return nil end
        return nil
      end
      reaper.file_exists = function(p) return files[p] ~= nil end
      state.folders = { "/lib/A", "/lib/Offline" }
      state.samples = {
        { path = "/lib/A/kick.wav" },
        { path = "/lib/A/deleted.wav" },
        { path = "/lib/Offline/pad.wav" },
      }
      rebuild_samples_path_index()
      enqueue_scan()
      for _ = 1, 50 do
        if sm_scan_enum_step(50) then break end
      end
      local names = {}
      for _, s in ipairs(state.samples) do names[#names + 1] = s.path end
      return table.concat(names, ",")
    ''')
    assert out == "/lib/A/kick.wav,/lib/Offline/pad.wav"

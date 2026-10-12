"""Scan complete window: causes, grouping, Move to Trash and Retry.
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
      layout_samples = function() end
      rawset(reaper, "file_exists", function(p)
        local f = io.open(p, "rb")
        if f then f:close() return true end
        return false
      end)
      return nil
    ''')
    assert err is None, err
    return L


def test_causes():
    L = _runtime()
    out = L.execute(r'''
      local cases = {
        "file starts with empty (zero) bytes: damaged or not fully copied",
        "could not decode audio",
        "file does not start with RIFF id",
        "file not found",
        "no audio decoder found: install ffmpeg (or sox) to analyze this file type",
        "analyzer timeout",
        "invalid analyzer JSON",
        "partial result: missing dominant_freq, sub_weight",
        "never analyzed — missing rms_energy",
        "list index out of range",
        "",
      }
      local o = {}
      for _, w in ipairs(cases) do o[#o + 1] = sm_scan_cause_of(w) end
      o[#o + 1] = sm_scan_row_detail("partial", cases[8])
      o[#o + 1] = sm_scan_row_detail("damaged", cases[1], 0)
      return table.concat(o, "|")
    ''')
    assert out.split("|") == [
        "damaged", "unreadable", "unreadable", "missing", "decoder", "analyzer",
        "analyzer", "partial", "pending", "analyzer", "pending",
        "no pitch, low end", "empty file (0 bytes)",
    ]


def _library(L, d):
    L.globals().D = d
    L.execute(r'''
      local function touch(name)
        local p = D .. "/" .. name
        local f = io.open(p, "wb"); f:write("x"); f:close()
        return p
      end
      local full = { dominant_freq = 100, rms_energy = 0.1, brightness = 0.5, sub_weight = 0.2,
                     effective_duration = 1, playback_type = "oneshot" }
      local function sample(name, fail, fields, size)
        local s = { path = touch(name), tags = {}, file_size = size }
        for k, v in pairs(fields or {}) do s[k] = v end
        s._analyze_fail = fail
        return s
      end
      state.samples = {
        sample("Kick 01.wav", nil, full, 1000),
        sample("LSA_Pad.wav", "file starts with empty (zero) bytes: damaged or not fully copied", nil, 0),
        sample("Broken.aif", "could not decode audio", nil, 5000),
        sample("Song.mp3", "no audio decoder found: install ffmpeg (or sox) to analyze this file type", nil, 9000),
        sample("Half.wav", "partial result: missing sub_weight", { dominant_freq = 1, rms_energy = 1,
          brightness = 1, effective_duration = 1, playback_type = "oneshot" }, 2000),
        sample("Gone.wav", "file not found", nil, nil),
        sample("Quiet.wav", nil, full, 300),
      }
      os.remove(state.samples[6].path)
      rebuild_samples_path_index()
      state.scan_background = false
      begin_scan_session("Library scan", { new_files = 7 })
      state.scan_session.indexed, state.scan_session.analyzed, state.scan_session.analyze_errors = 7, 3, 4
      sm_scan_report_note_quiet(state.samples[7], "silent")
      finish_scan_session(5)
    ''')


def test_report_groups_rows_by_cause():
    L = _runtime()
    _library(L, tempfile.mkdtemp())
    out = L.execute(r'''
      local dlg = state.scan_complete_dialog
      local o = {}
      for _, row in ipairs(dlg.rows) do o[#o + 1] = row.cause .. ":" .. row.name end
      local c = sm_scan_report_counts(dlg)
      return table.concat(o, ",") .. "|" .. c.problems .. "," .. c.broken .. "," .. c.retry
        .. "|" .. tostring(dlg.clipboard:find("Damaged or not fully copied (1)", 1, true) ~= nil)
    ''')
    rows, counts, clip = out.split("|")
    assert rows == ("damaged:LSA_Pad.wav,unreadable:Broken.aif,missing:Gone.wav,"
                    "decoder:Song.mp3,partial:Half.wav,silent:Quiet.wav")
    assert counts == "5,2,2"
    assert clip == "true"


def test_move_to_trash_never_deletes_and_drops_from_library():
    L = _runtime()
    d = tempfile.mkdtemp()
    _library(L, d)
    out = L.execute(r'''
      SM_IS_MAC, SM_IS_WINDOWS = true, false
      local cmds = {}
      local deleted_by_lua = false
      local real_remove = os.remove
      -- The Trash command "moves" every file except Broken.aif.
      sm_run_trash_command = function(cmd)
        cmds[#cmds + 1] = cmd
        for p in cmd:gmatch("'([^']+)'") do
          if p:sub(1, 1) == "/" and not p:find("Broken", 1, true) then real_remove(p) end
        end
      end
      os.remove = function() deleted_by_lua = true; return true end
      local dlg = state.scan_complete_dialog
      local broken = sm_scan_report_paths(dlg, "broken")
      local n, failed = sm_scan_report_apply(dlg, "trash", broken)
      os.remove = real_remove
      local names = {}
      for _, s in ipairs(state.samples) do names[#names + 1] = s.path:match("[^/]+$") end
      return table.concat({
        #broken, n, #failed, tostring(deleted_by_lua),
        tostring(cmds[1]:find("osascript", 1, true) ~= nil),
        tostring(cmds[1]:find("Finder", 1, true) ~= nil),
        table.concat(names, ","),
        tostring(dlg.banner ~= nil),
        tostring(#dlg.rows),
      }, "|")
    ''')
    parts = out.split("|")
    assert parts[0:4] == ["2", "1", "1", "false"]
    assert parts[4] == "true" and parts[5] == "true"
    # LSA_Pad.wav was trashed and left the library; Broken.aif stayed (the move failed).
    assert parts[6] == "Kick 01.wav,Broken.aif,Song.mp3,Half.wav,Gone.wav,Quiet.wav"
    assert parts[7] == "true"
    assert parts[8] == "5"


def test_remove_missing_and_retry():
    L = _runtime()
    _library(L, tempfile.mkdtemp())
    out = L.execute(r'''
      local dlg = state.scan_complete_dialog
      local ran = false
      sm_run_trash_command = function() ran = true end
      sm_scan_report_apply(dlg, "remove", sm_scan_report_paths(dlg, "missing"))
      local left = #state.samples
      state.analyzer_queue, state.active_processes = {}, {}
      local added = sm_scan_report_retry(dlg, sm_scan_report_paths(dlg, "retry"))
      local q = {}
      for _, p in ipairs(state.analyzer_queue) do q[#q + 1] = p:match("[^/]+$") end
      table.sort(q)
      return table.concat({ tostring(ran), left, added, table.concat(q, ","),
        tostring(state.scan_complete_dialog == nil), state.scan_session and state.scan_session.kind or "" }, "|")
    ''')
    assert out == "false|6|2|Half.wav,Song.mp3|true|Retrying files"


def test_trash_commands_quote_paths():
    L = _runtime()
    out = L.execute(r'''
      SM_IS_MAC, SM_IS_WINDOWS = true, false
      local paths = { "/Volumes/4TB/it's a kick.wav" }
      local cli = sm_trash_commands(paths, "cli")[1]
      local finder = sm_trash_commands(paths, "default")[1]
      SM_IS_MAC, SM_IS_WINDOWS = false, true
      local win = sm_trash_commands({ "C:/Samples/it's.wav" })[1]
      local many = #sm_trash_commands((function() local t = {} for i = 1, 85 do t[i] = "/a/" .. i end return t end)(), "cli")
      return table.concat({ cli, finder, win, many }, "\n")
    ''')
    cli, finder, win, many = out.split("\n")
    assert cli == "/usr/bin/trash '/Volumes/4TB/it'\\''s a kick.wav'"
    assert finder.startswith("osascript -e 'on run argv'") and finder.endswith("'/Volumes/4TB/it'\\''s a kick.wav'")
    assert "SendToRecycleBin" in win and "'C:\\Samples\\it''s.wav'" in win
    assert many == "3"

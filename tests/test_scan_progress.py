"""Scan progress (toolbar bar and map card) and background scanning.
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
      return nil
    ''')
    assert err is None, err
    return L


def test_progress_phases():
    L = _runtime()
    out = L.execute(r'''
      local o = {}
      local function show(p)
        if not p then return "nil" end
        return table.concat({ p.phase, p.label, tostring(p.done), tostring(p.total),
          p.fraction and string.format("%.2f", p.fraction) or "-", tostring(p.indeterminate), p.detail or "" }, "|")
      end
      state.scan_running = false
      o[#o + 1] = show(sm_compute_scan_progress(100))
      state.scan_running = true
      state.scan_session = { started_at = 90, analyzed = 0, analyze_errors = 0 }
      state.scan_enum = { dirs_done = 1234, paths = { "a", "b", "c" } }
      o[#o + 1] = show(sm_compute_scan_progress(100))
      state.scan_enum = nil
      state.scan_total = 10
      state.scan_queue = { "x", "y", "z", "w" }
      o[#o + 1] = show(sm_compute_scan_progress(100))
      state.scan_queue = {}
      state.analyzer_queue = { "p1", "p2", "p3" }
      state.active_processes = { { path = "p0" } }
      state.scan_session.analyzed, state.scan_session.analyze_errors = 5, 1
      o[#o + 1] = show(sm_compute_scan_progress(100))
      state.analyzer_queue, state.active_processes = {}, {}
      o[#o + 1] = show(sm_compute_scan_progress(100))
      return table.concat(o, "\n")
    ''')
    lines = out.split("\n")
    assert lines[0] == "nil"
    assert lines[1] == "list|Looking for files|nil|nil|-|true|1,234 folders checked  ·  3 new files found"
    assert lines[2] == "index|Adding new files|6|10|0.60|nil|6 of 10 files"
    assert lines[3] == "analyze|Analyzing sounds|6|10|0.60|nil|6 of 10 files"
    assert lines[4].startswith("finish|Finishing up|")


def test_background_scan_uses_fewer_workers_and_smaller_slices():
    L = _runtime()
    out = L.execute(r'''
      state.cpu_core_count = 14
      state.external_disabled = false
      state.analyzer_workers = {}
      for i = 1, 8 do state.analyzer_workers[i] = { slot = i, batches = {} } end
      ensure_analyzer_workers = function() return true end
      local fed = {}
      assign_worker_jobs = function(w, paths)
        fed[w.slot] = (fed[w.slot] or 0) + #paths
        w.batches[#w.batches + 1] = { jobs = {}, got = 0 }
        return true
      end
      collect_worker_result = function() end
      local function run(bg)
        state.scan_background = bg
        fed = {}
        for _, w in ipairs(state.analyzer_workers) do w.batches = {} end
        state.analyzer_queue = {}
        for i = 1, 200 do state.analyzer_queue[i] = "/s/" .. i .. ".wav" end
        state.scan_running = true
        process_analyzer_queue()
        local n = 0
        for _ in pairs(fed) do n = n + 1 end
        return n .. ":" .. tostring(sm_scan_slice_ms())
      end
      return run(false) .. "|" .. run(true)
    ''')
    assert out == "8:12.0|3:3.0"


def test_background_scan_finishes_with_a_toast():
    L = _runtime()
    out = L.execute(r'''
      state.scan_background = true
      state.scan_complete_dialog = nil
      state.sm_toast = nil
      begin_scan_session("Library scan", { new_files = 3 })
      state.scan_session.indexed, state.scan_session.analyzed = 3, 3
      finish_scan_session(0)
      local a = tostring(state.scan_complete_dialog) .. "|" .. tostring(state.sm_toast and state.sm_toast.text:find("Library scan finished", 1, true) ~= nil)
      -- With problems, the window still opens.
      state.sm_toast = nil
      begin_scan_session("Library scan", { new_files = 3 })
      state.scan_session.indexed, state.scan_session.analyzed, state.scan_session.analyze_errors = 3, 2, 1
      finish_scan_session(0)
      return a .. "|" .. tostring(state.scan_complete_dialog ~= nil)
    ''')
    assert out == "nil|true|true"

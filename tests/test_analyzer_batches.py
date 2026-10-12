"""Analyzer worker batches: real Python workers driven by the browser's Lua side
(stub REAPER from load_browser.py). Each worker gets several files per request and
streams results back; a stuck job fails alone and the rest go back in the queue.
Requires `pip install lupa`."""
import os
import re
import struct
import sys
import tempfile
import time
import math
import subprocess

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


class Clock:
    def __init__(self):
        self.offset = 0.0

    def __call__(self, *args):
        return time.perf_counter() + self.offset


def _runtime(clock):
    src = open(os.path.join(HERE, "load_browser.py"), encoding="utf-8").read()
    stub = re.search(r"L\.execute\(r'''(.*?)local report = \{\}", src, re.S).group(1)
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    g.FRAMES = 0
    procs = []

    def py_popen(cmd):
        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stdin=subprocess.DEVNULL)
        procs.append(p)
        return p

    g.PY_POPEN = py_popen
    g.PY_CLOSE = lambda p: (p.stdout.close(), p.wait(timeout=10)) and True
    g.PY_EXEC = lambda cmd: os.system(cmd) == 0
    err = L.execute(stub + r'''
      io.popen = function(cmd)
        local h = PY_POPEN(cmd)
        return { read = function() return nil end, close = function() return PY_CLOSE(h) end }
      end
      os.execute = function(cmd) return PY_EXEC(cmd) end
      reaper.RecursiveCreateDirectory = function(p) os.execute("mkdir -p '" .. p .. "'") return 1 end
      local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
      if not chunk then return err end
      local ok, e = xpcall(chunk, debug.traceback)
      if not ok then return e end
      log = function() end
      save_config = function() end
      return nil
    ''')
    assert err is None, err
    g.reaper.time_precise = clock
    return L


def _write_wav(path, seconds, freq):
    sr = 22050
    n = int(sr * seconds)
    frames = b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * freq * i / sr) * math.exp(-i / (sr * 0.1)))) for i in range(n))
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(frames)) + frames)


def _setup(L, analyzer, paths, workers=3):
    g = L.globals()
    g.EXTERNAL_ANALYZER = analyzer
    g.PYTHON_BIN = sys.executable
    g.ANALYZER_SCRIPT_OK = True
    g.PATHS = L.table_from(paths)
    g.WORKERS = workers
    L.execute(r'''
      state.python_resolved = true
      state.analyzer_no_python = false
      state.cpu_core_count = 4
      state.max_concurrent_analyzers = WORKERS
      state.analyzer_results = {}
      state.analyzer_queue = {}
      for i = 1, #PATHS do state.analyzer_queue[i] = PATHS[i] end
      state.scan_running = true
    ''')


def _pump(L, want, timeout=60.0):
    end = time.time() + timeout
    count = L.eval("function() local n = 0 for _ in pairs(state.analyzer_results) do n = n + 1 end return n end")
    while time.time() < end:
        L.execute("process_analyzer_queue()")
        if count() >= want:
            return count()
        time.sleep(1 / 60)
    return count()


def test_batches_analyze_every_file_and_return_header_facts():
    d = tempfile.mkdtemp()
    paths = []
    for i in range(30):
        p = os.path.join(d, "hit_%02d.wav" % i)
        _write_wav(p, 0.2 + 0.01 * i, 100 + 10 * i)
        paths.append(p)
    clock = Clock()
    L = _runtime(clock)
    _setup(L, os.path.join(ROOT, "SampleMapAnalyzer.py"), paths)
    try:
        got = _pump(L, len(paths))
        assert got == len(paths)
        out = L.execute(r'''
          local bad, ok = {}, 0
          for path, res in pairs(state.analyzer_results) do
            if res.data and res.data.rms_energy and res.data.file_duration then ok = ok + 1
            else bad[#bad + 1] = path .. " " .. tostring(res.err) end
          end
          return ok, table.concat(bad, "; "), state.analyzer_batch_seq, #state.active_processes
        ''')
        ok, bad, batches, active = out
        assert ok == len(paths), bad
        # 30 files over 3 workers: far fewer requests than files.
        assert batches < len(paths) / 2, batches
        assert active == 0
        dur = L.eval('function(p) return state.analyzer_results[p].data.file_duration end')(paths[10])
        assert abs(dur - 0.30) < 0.001
    finally:
        L.execute("stop_analyzer_workers(false)")


def test_stuck_job_fails_alone_and_the_rest_are_requeued():
    d = tempfile.mkdtemp()
    # A fake analyzer that answers the first job of each batch, then hangs.
    fake = os.path.join(d, "hang.py")
    open(fake, "w").write(r'''
import os, sys, time, json
args = sys.argv[1:]
slot = args[args.index("--slot") + 1]; work = args[args.index("--dir") + 1]
open(os.path.join(work, "pid_" + slot), "w").write(str(os.getpid()))
req = os.path.join(work, "req_" + slot)
while True:
    if os.path.exists(os.path.join(work, "quit_" + slot)): break
    if not os.path.exists(req): time.sleep(0.005); continue
    lines = open(req).read().splitlines(); os.remove(req)
    bid = lines[0].split()[1]
    with open(os.path.join(work, "out_%s_%s" % (slot, bid)), "a") as out:
        mode, path = lines[1].split("\t", 1)
        out.write(json.dumps({"_path": path, "rms_energy": 0.5}) + "\n"); out.flush()
    time.sleep(3600)
''')
    paths = [os.path.join(d, "f%d.wav" % i) for i in range(6)]
    clock = Clock()
    L = _runtime(clock)
    _setup(L, fake, paths, workers=1)
    try:
        assert _pump(L, 1, timeout=20) == 1
        clock.offset += 31.0
        L.execute("process_analyzer_queue()")
        res = L.execute(r'''
          local r1 = state.analyzer_results[PATHS[1]]
          local r2 = state.analyzer_results[PATHS[2]]
          local q = {}
          for i, p in ipairs(state.analyzer_queue) do q[i] = p end
          return r1 and r1.data and r1.data.rms_energy, r2 and r2.err, table.concat(q, "|")
        ''')
        first, second_err, queue = res
        assert first == 0.5
        assert second_err == "analyzer timeout"
        # Jobs 3-6 are back in the queue, in order (some may have been resent to the restarted worker).
        remaining = [p for p in paths[2:]]
        pending = L.execute('local t = {} for _, j in ipairs(state.active_processes) do t[#t+1] = j.path end return table.concat(t, "|")')
        seen = [p for p in (queue.split("|") if queue else [])] + [p for p in (pending.split("|") if pending else [])]
        assert sorted(seen) == sorted(remaining), (queue, pending)
    finally:
        L.execute("stop_analyzer_workers(false)")


def test_queue_take_keeps_order():
    clock = Clock()
    L = _runtime(clock)
    out = L.execute(r'''
      state.analyzer_queue = {}
      for i = 1, 10 do state.analyzer_queue[i] = "p" .. i end
      local a = sm_queue_take(4)
      local b = sm_queue_take(100)
      return table.concat(a, ","), table.concat(b, ","), #state.analyzer_queue
    ''')
    assert out == ("p1,p2,p3,p4", "p5,p6,p7,p8,p9,p10", 0)

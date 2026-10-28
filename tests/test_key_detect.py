"""Key detection from audio (browser/42d_key_detect.lua): synthetic loops in
known keys, detuning, noise/drums with no key, and the per-file queue that
reads on the defer frame and analyses a few frames per tick. Requires
`pip install lupa`."""
import math
import os
import random

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SR = 11025
NAMES = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def runtime():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute("reaper = { time_precise = os.clock }")
    with open(os.path.join(ROOT, "browser", "42d_key_detect.lua"), encoding="utf-8") as f:
        L.execute(f.read())
    return L


def tone(midi, n, cents=0.0, harmonics=5):
    f = 440.0 * 2 ** ((midi - 69 + cents / 100.0) / 12)
    out = [0.0] * n
    for h in range(1, harmonics + 1):
        if f * h >= SR / 2:
            break
        w = 2 * math.pi * f * h / SR
        a = 0.6 / h
        for i in range(n):
            out[i] += a * math.sin(w * i)
    return out


def progression(tonic, minor, cents=0.0, seconds=8):
    """i-iv-v-i (or I-IV-V-I) chords with a scale melody on top."""
    scale = MINOR if minor else MAJOR
    n = SR * seconds
    x = [0.0] * n
    bar = n // 4
    degrees = [0, 3, 4, 0]
    for b, deg in enumerate(degrees):
        root = 48 + tonic + scale[deg]
        third = 48 + tonic + scale[(deg + 2) % 7] + (12 if deg + 2 >= 7 else 0)
        fifth = 48 + tonic + scale[(deg + 4) % 7] + (12 if deg + 4 >= 7 else 0)
        for m, amp in ((root - 12, 0.8), (root, 0.5), (third, 0.5), (fifth, 0.5)):
            t = tone(m, bar, cents)
            for i in range(bar):
                x[b * bar + i] += amp * t[i]
    step = n // 16
    for k in range(16):
        deg = [0, 2, 4, 2, 1, 3, 5, 3, 4, 6, 4, 2, 0, 2, 1, 0][k]
        t = tone(72 + tonic + scale[deg], step, cents, 3)
        for i in range(step):
            x[k * step + i] += 0.4 * t[i] * (1 - i / step)
    return x


def as_lua(L, x):
    return L.table_from(x)


def test_known_keys():
    L = runtime()
    analyze = L.globals().sm_keydet_analyze
    for tonic, minor in ((0, False), (9, True), (7, False), (2, True), (3, False), (6, True)):
        r = analyze(as_lua(L, progression(tonic, minor)), SR)
        want = NAMES[tonic] + ("m" if minor else "")
        assert r.key == want, (want, r.key, r.conf)
        assert r.tonal and r.conf > 0.5


def test_detuned_loop():
    L = runtime()
    r = L.globals().sm_keydet_analyze(as_lua(L, progression(5, False, cents=35)), SR)
    assert r.key == "F"
    assert 20 <= r.tuning_cents <= 50


def test_noise_has_no_key():
    L = runtime()
    random.seed(1)
    n = SR * 4
    x = [random.uniform(-0.5, 0.5) for _ in range(n)]
    # kick-ish thumps on top
    for b in range(8):
        s = b * n // 8
        for i in range(2000):
            x[s + i] += math.sin(2 * math.pi * 55 * i / SR * (1 - i / 4000)) * (1 - i / 2000)
    r = L.globals().sm_keydet_analyze(as_lua(L, x), SR)
    assert not (r.tonal and r.conf >= 0.5), (r.key, r.conf, r.score)


def test_silence():
    L = runtime()
    r = L.globals().sm_keydet_analyze(as_lua(L, [0.0] * (SR * 2)), SR)
    assert not r.tonal and r.conf == 0


def test_queue_reads_once_then_steps():
    L = runtime()
    L.globals().SAMPLE = as_lua(L, progression(9, True))
    L.execute(r'''
      READS = 0
      sm_keydet_read = function(path) READS = READS + 1; return SAMPLE end
      GOT = nil
      sm_key_detect_request("/a.wav", function(res) GOT = res end)
      sm_key_detect_request("/a.wav")
      TICKS = 0
      while sm_key_detect_busy() and TICKS < 10000 do
        sm_key_detect_tick(0.5)
        TICKS = TICKS + 1
      end
    ''')
    g = L.globals()
    assert g.READS == 1
    assert g.TICKS > 3            # spread over several frames
    assert g.GOT.key == "Am"
    assert L.eval('sm_key_detect_get("/a.wav")').key == "Am"
    assert L.eval('sm_key_detect_get("/b.wav")') is None


def test_unreadable_file():
    L = runtime()
    L.execute(r'''
      sm_keydet_read = function() return nil, "Couldn't open the file" end
      sm_key_detect_request("/bad.wav")
      sm_key_detect_tick(5)
    ''')
    r = L.eval('sm_key_detect_get("/bad.wav")')
    assert r.failed and r.err == "Couldn't open the file"
    assert not L.eval("sm_key_detect_busy()")

"""Unit tests for the pure-Python helpers used by the sequencer."""
import os
import random
import struct
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import SampleMapDrumAI as drum_ai  # noqa: E402
import SampleMapGrooveMIDI as groove  # noqa: E402


def test_allowed_steps_follows_grid():
    assert drum_ai.allowed_steps(16) == list(range(16))
    assert drum_ai.allowed_steps(8) == list(range(0, 16, 2))
    assert drum_ai.allowed_steps(4) == [0, 4, 8, 12]
    assert drum_ai.allowed_steps("bad") == list(range(16))


def test_vary_role_stays_on_grid_and_is_deterministic():
    allowed = drum_ai.allowed_steps(8)
    a = drum_ai.vary_role("house", "kick", [0, 4, 8, 12, 16], 0.6, random.Random(7), allowed)
    b = drum_ai.vary_role("house", "kick", [0, 4, 8, 12, 16], 0.6, random.Random(7), allowed)
    assert a == b
    assert a and all(s in allowed for s in a)


def test_vary_role_low_variation_keeps_input():
    hits = [0, 4, 8, 12]
    out = drum_ai.vary_role("house", "kick", hits, 0.0, random.Random(1))
    assert len(out) == len(hits)


def _vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, (n & 0x7F) | 0x80)
        n >>= 7
    return bytes(out)


def _write_midi(path, events, tpq=480):
    track = b""
    for delta, data in events:
        track += _vlq(delta) + data
    track += _vlq(0) + b"\xff\x2f\x00"
    with open(path, "wb") as fh:
        fh.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, tpq))
        fh.write(b"MTrk" + struct.pack(">I", len(track)) + track)


def test_read_vlq():
    assert groove.read_vlq(_vlq(0x0FFFFFFF), 0) == (0x0FFFFFFF, 4)


def test_parse_and_extract_one_bar():
    kick = next(p for p, role in groove.PITCH_TO_ROLE.items() if role == "kick")
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "beat.mid")
        # Kicks on every quarter note of one 4/4 bar (480 ticks per quarter).
        events = [(0, bytes([0x90, kick, 100])), (10, bytes([0x80, kick, 0]))]
        for _ in range(3):
            events += [(470, bytes([0x90, kick, 100])), (10, bytes([0x80, kick, 0]))]
        _write_midi(path, events)
        notes, tpq, _tempos, sigs = groove.parse_midi_notes(path)
    assert tpq == 480
    pattern, velocities, tpb, offsets = groove.extract_bar_pattern(notes, tpq, sigs)
    assert tpb == 1920
    assert pattern["kick"] == [0, 4, 8, 12]
    assert velocities["kick"]["0"] == 100
    assert offsets["kick"]["0"] == 0.0


def test_extract_keeps_micro_timing_and_velocity():
    tpq = 480
    s16 = tpq // 4  # 120 ticks per 16th in 4/4
    # Hat on the "e" of beat 1, played a third of a 16th late (swung), soft.
    notes = [(0, 36, 110), (s16 + 40, 42, 40)]
    pattern, velocities, _tpb, offsets = groove.extract_bar_pattern(notes, tpq, [])
    assert pattern["hat"] == [1]
    assert velocities["hat"]["1"] == 40
    assert abs(offsets["hat"]["1"] - 40 / 120.0) < 1e-3


def test_pick_preview_bar_skips_count_in_and_sparse_bars():
    tpq = 480
    tpb = tpq * 4
    s16 = tpb // 16
    notes = [(0, 42, 90)]  # bar 0: a lone count-in hat
    notes += [(tpb + 4 * s16, 38, 100)]  # bar 1: one snare, too sparse
    for step in (0, 4, 8, 12):  # bar 2: a real groove
        notes.append((2 * tpb + step * s16, 36, 110))
        notes.append((2 * tpb + step * s16 + 2 * s16, 42, 80))
    bar, pattern = groove.pick_preview_bar(notes, tpq, [], 3)
    assert bar == 2
    assert pattern["kick"] == [0, 4, 8, 12]
    assert pattern["hat"] == [2, 6, 10, 14]

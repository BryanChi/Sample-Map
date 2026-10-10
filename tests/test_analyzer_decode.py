"""Analyzer behaviour for compressed files: missing decoder and true duration."""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import SampleMapAnalyzer as an  # noqa: E402


def test_parse_ffmpeg_duration():
    text = "Input #0, mp3\n  Duration: 00:01:02.50, start: 0.000000, bitrate: 320 kb/s"
    assert abs(an._parse_ffmpeg_duration(text) - 62.5) < 1e-9
    assert an._parse_ffmpeg_duration("no duration here") is None


def _payload_for(name, monkeypatch, decoder):
    monkeypatch.setattr(an, "have_decoder", lambda: decoder)
    monkeypatch.setattr(an, "analyze_file", lambda path, mode="full": {})
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, name)
        with open(path, "wb") as fh:
            fh.write(b"\x00" * 64)
        return an.analyze_job_payload(path, "full")


def test_missing_decoder_reports_clear_reason(monkeypatch):
    payload = _payload_for("loop.mp3", monkeypatch, False)
    assert payload["_error"] == an.NO_DECODER_ERROR
    assert "could not decode" not in payload["_error"]


def test_decoder_present_keeps_could_not_decode(monkeypatch):
    payload = _payload_for("broken.flac", monkeypatch, True)
    assert payload["_error"] == "could not decode audio"


def test_broken_wav_without_decoder_is_still_unreadable(monkeypatch):
    payload = _payload_for("broken.wav", monkeypatch, False)
    assert payload["_error"] == "could not decode audio"


def test_apply_full_duration_overrides_excerpt_length():
    sr = 8000
    samples = [0.5 if (i // 400) % 8 == 0 else 0.0 for i in range(sr * 2)]
    result = {"effective_duration": 1.9, "playback_type": "oneshot"}
    out = an.apply_full_duration(dict(result), samples, sr, 12.0, 0.0, 11.5)
    assert out["effective_duration"] == 11.5
    assert out["playback_type"] in ("loop", "oneshot", "unknown")
    no_tail = an.apply_full_duration(dict(result), samples, sr, 12.0, 0.0, None)
    assert no_tail["effective_duration"] == 12.0
    # Short file: nothing changes.
    same = an.apply_full_duration(dict(result), samples, sr, 2.0, 0.0, None)
    assert same == result


def test_parse_trailing_silence():
    text = "silence_start: 3.9\nsilence_end: 10 | silence_duration: 6.1"
    assert abs(an._parse_trailing_silence(text, 10.0) - (3.9 + an._AUDIBLE_HANG_SEC)) < 1e-9
    # Silence in the middle, audio at the end: no trailing silence.
    mid = "silence_start: 2.0\nsilence_end: 3.0 | silence_duration: 1.0"
    assert an._parse_trailing_silence(mid, 10.0) is None
    assert an._parse_trailing_silence("", 10.0) is None

"""Files from report #17: antiphase stereo, silent, tiny, misnamed and zero-filled."""
import os
import random
import shutil
import struct
import subprocess
import sys
import wave

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import SampleMapAnalyzer as an  # noqa: E402


def _write(path, frames, sr=44100):
    w = wave.open(str(path), "wb")
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(b"".join(struct.pack("<hh", int(l * 32767), int(r * 32767)) for l, r in frames))
    w.close()


def _hats(sr=44100, seconds=2):
    random.seed(1)
    out = []
    for i in range(sr * seconds):
        t = i % (sr // 4)
        v = random.uniform(-1, 1) * 0.5 * (0.9995 ** t) if t < 4000 else 0.0
        out.append((v, -v))
    return out


def test_antiphase_stereo_gets_a_spectrum(tmp_path):
    p = tmp_path / "hats.wav"
    _write(p, _hats())
    data = an.analyze_job_payload(str(p), "full")
    assert data.get("dominant_freq") and data.get("brightness") and data.get("sub_weight") is not None
    assert data["rms_energy"] > 0.01


def test_silent_and_tiny_files_get_neutral_values(tmp_path):
    silent, tiny = tmp_path / "silent.wav", tmp_path / "tiny.wav"
    _write(silent, [(0.0, 0.0)] * 44100)
    _write(tiny, [(0.1, 0.1)] * 22)
    for p, note in ((silent, "silent"), (tiny, "too short")):
        data = an.analyze_job_payload(str(p), "full")
        assert data["analysis_note"] == note
        for k in ("dominant_freq", "brightness", "sub_weight", "effective_duration"):
            assert data.get(k) is not None


def test_zero_filled_wav_says_so(tmp_path):
    p = tmp_path / "zeros.wav"
    p.write_bytes(b"\x00" * 5000)
    assert an.analyze_job_payload(str(p), "full")["_error"] == an.ZEROS_ERROR


def test_sniff_audio_ext(tmp_path):
    cases = {
        b"RIFF\x00\x00\x00\x00WAVEfmt ": ".wav",
        b"\x00\x00\x00\x20ftypM4A \x00\x00": ".m4a",
        b"ID3\x04\x00\x00\x00\x00\x00\x00\x00\x00": ".mp3",
        b"\xff\xfb\x90\x00" + b"\x00" * 8: ".mp3",
        b"fLaC" + b"\x00" * 8: ".flac",
    }
    for head, ext in cases.items():
        p = tmp_path / "x.wav"
        p.write_bytes(head + b"\x01" * 64)
        assert an.sniff_audio_ext(str(p)) == ext


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="needs ffmpeg")
def test_mp3_named_wav_is_decoded(tmp_path):
    mp3 = tmp_path / "real.mp3"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", str(mp3)], check=True)
    named = tmp_path / "loop.wav"
    shutil.copyfile(mp3, named)
    data = an.analyze_job_payload(str(named), "full")
    assert "_error" not in data and data.get("dominant_freq")

"""Quick swap infers tags from whole words, not substrings. Runs just the
keyword section of the script in Lua 5.4. Requires `pip install lupa`."""
import os

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "Sample Map - Quick swap for selected item.lua")


def _infer():
    src = open(SCRIPT, encoding="utf-8").read()
    start = src.index("local META_TAGS")
    end = src.index("local function infer_tags_from_path")
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    fn = L.execute(src[start:end] + "\nreturn infer_tags_from_text")

    def infer(text):
        return list(fn(text).values())

    return infer


def test_short_keys_need_whole_words():
    infer = _infer()
    assert "hat" not in infer("Synth Chords")
    assert "hat" not in infer("Punch")
    assert "tom" not in infer("custom pad")
    assert "bass" not in infer("subtle texture")
    assert "rim" not in infer("prime lead")


def test_names_still_match():
    infer = _infer()
    assert infer("BigKick_02")[0] == "kick"
    assert "hat" in infer("HiHat open")
    assert "hat" in infer("closed_hh_01")
    assert "tom" in infer("Toms")
    assert "bass" in infer("Sub 808")
    assert "snap" in infer("finger snap 3")
    assert "kick" in infer("kick01")

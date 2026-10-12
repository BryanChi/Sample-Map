"""Tests for the shared feedback window (feedback/CRS_Feedback.lua) without REAPER."""
import json
import os
import tempfile

from lupa import lua54

ROOT = os.path.join(os.path.dirname(__file__), "..")
MODULE = os.path.join(ROOT, "feedback", "CRS_Feedback.lua")


def _runtime(os_name="macOS-arm64", resource="/Users/jo/Library/Application Support/REAPER"):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    tmp = tempfile.mkdtemp()
    L.execute(
        """
        local os_name, res, tmp = ...
        DEFERRED = {}
        EXT = {}
        reaper = {
          GetOS = function() return os_name end,
          GetAppVersion = function() return "7.22/" .. os_name end,
          GetResourcePath = function() return res end,
          RecursiveCreateDirectory = function() return 1 end,
          GetExtState = function(s, k) return EXT[s .. k] or "" end,
          SetExtState = function(s, k, v) EXT[s .. k] = v end,
          APIExists = function() return false end,
          defer = function(f) DEFERRED[#DEFERRED + 1] = f end,
          ShowConsoleMsg = function() end,
          time_precise = os.clock,
        }
        -- Any ImGui call returns nothing (windows are never visible).
        setmetatable(reaper, { __index = function(_, k)
          if k:match("^ImGui_") then return function() end end
        end })
        """.replace("local os_name, res, tmp = ...", f"local os_name, res, tmp = {os_name!r}, {resource!r}, {tmp!r}")
    )
    # Keep the module's log file in a temp folder.
    L.execute(f"function reaper.GetResourcePath() return {tmp!r} end")
    F = L.execute(f"return dofile({MODULE!r})")
    L.execute(f"function reaper.GetResourcePath() return {resource!r} end")
    F.Setup(L.table_from({"script_id": "sample-map", "script_name": "Sample Map", "version": "1.2.3"}))
    return L, F


def test_scrub_paths_removes_user_names_and_resource_folder():
    L, F = _runtime()
    s = F.ScrubPaths(
        "/Users/jo/Library/Application Support/REAPER/Scripts/x.lua "
        "/Users/jo/Music/kick.wav C:\\Users\\Jo Smith\\Desktop\\a.wav /home/jo/b.wav"
    )
    assert "jo" not in s.replace("<REAPER>", "")
    assert s.startswith("<REAPER>/Scripts/x.lua")
    assert "/Users/<user>/Music/kick.wav" in s
    assert "C:\\Users\\<user>\\Desktop" in s
    assert "/home/<user>/b.wav" in s


def test_json_encoder_escapes_and_round_trips():
    L, F = _runtime()
    t = L.eval('{ a = "q\\"uote\\nline\\t\\1", n = 3, f = 1.5, b = true, list = { 1, "x" } }')
    out = json.loads(F._json_encode(t))
    assert out == {"a": 'q"uote\nline\t\x01', "n": 3, "f": 1.5, "b": True, "list": [1, "x"]}


def test_payload_validation_and_contents():
    L, F = _runtime()
    F.Log("Opened /Users/jo/Music")
    state = L.eval('{ kind = "bug", title = "  Crash  ", note = "hi", contact = "", include_log = true, images = {} }')
    p, err = F._build_payload(state)
    assert p is None and "few words" in err
    state.note = "It crashed when I clicked play."
    p = F._build_payload(state)
    data = json.loads(F._json_encode(p))
    assert data["title"] == "Crash"
    assert data["script_id"] == "sample-map"
    assert data["script_version"] == "1.2.3"
    assert data["env"]["os"] == "macOS-arm64"
    assert "Opened /Users/<user>/Music" in data["log"]
    state.include_log = False
    assert json.loads(F._json_encode(F._build_payload(state)))["log"] == ""


def test_reply_parsing():
    L, F = _runtime()
    res = F._parse_reply(0, "201", '{"ok":true,"url":"https:\\/\\/github.com\\/BryanChi\\/Sample-Map\\/issues\\/7","number":7}')
    assert res.url == "https://github.com/BryanChi/Sample-Map/issues/7" and res.number == 7
    res, err = F._parse_reply(0, "429", '{"error":"Too many reports in a short time."}')
    assert res is None and err == "Too many reports in a short time."
    res, err = F._parse_reply(6, "000", "")
    assert res is None and "Couldn't reach" in err
    res, err = F._parse_reply(0, "502", '{"error":"GitHub didn\'t accept the report."}')
    assert "HTTP 502" in err


def test_defer_catches_errors_and_opens_the_window():
    L, F = _runtime()
    run = L.eval("""function(F)
      F.Defer(function() local t = nil; return t.x end)
      local f = table.remove(DEFERRED, 1)
      f()
      return F.IsOpen()
    end""")
    assert run(F) is True
    assert any("ERROR:" in line for line in F.BuildLogText().split("\n"))


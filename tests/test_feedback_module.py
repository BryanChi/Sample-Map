"""Tests for the shared feedback window (feedback/CRS_Feedback.lua) without REAPER."""
import json
import os
import tempfile

from lupa import lua54

ROOT = os.path.join(os.path.dirname(__file__), "..")
MODULE = os.path.join(ROOT, "feedback", "CRS_Feedback.lua")


def _runtime(os_name="macOS-arm64", resource="/Users/jo/Library/Application Support/REAPER", tmp=None,
             ext=None, setup=None):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    tmp = tmp or tempfile.mkdtemp()
    L.execute(
        """
        local os_name, res, tmp = ...
        DEFERRED = {}
        EXT = {}
        reaper = {
          GetOS = function() return os_name end,
          GetAppVersion = function() return "7.22/" .. os_name end,
          GetResourcePath = function() return res end,
          RecursiveCreateDirectory = function(d) os.execute("mkdir -p '" .. d .. "'"); return 1 end,
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
    for k, v in (ext or {}).items():
        L.execute(f"EXT[{k!r}] = {v!r}")
    F = L.execute(f"return dofile({MODULE!r})")
    if resource is not None:
        L.execute(f"function reaper.GetResourcePath() return {resource!r} end")
    opts = L.table_from({"script_id": "sample-map", "script_name": "Sample Map", "version": "1.2.3"})
    if setup:
        setup(L, opts)
    F.Setup(opts)
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



# --- Bug recording -------------------------------------------------------------

def _rec_runtime(**kw):
    """Runtime whose files stay in a temp folder, with a few fake REAPER calls."""
    tmp = kw.pop("tmp", None) or tempfile.mkdtemp()

    def setup(L, opts):
        L.execute("""
          CALLS = {}
          function reaper.TrackFX_SetParam(tr, fx, p, v) CALLS[#CALLS + 1] = v; return true end
          function reaper.TrackFX_GetParam(tr, fx, p) return 0.5 end
          function reaper.SetExtState(s, k, v) EXT[s .. k] = v end
          function reaper.ExecProcess(cmd) return "ok" end
          IM = {
            Button = function(c, label) return label:match("^Play") ~= nil end,
            SliderDouble = function(c, label, v) return true, v + 1 end,
            InputText = function(c, label, t) return true, "my secret licence" end,
            MenuItem = function(c, label) return true end,
            Text = function() end,
          }
          -- Like the builtin shim: unknown fields raise an error.
          setmetatable(IM, { __index = function(_, k) error("no field " .. tostring(k)) end })
        """)
        opts.imgui = L.eval("IM")

    return _runtime(resource=tmp, tmp=tmp, setup=setup, **kw), tmp


def test_api_classification():
    (L, F), _ = _rec_runtime()
    for name in ["TrackFX_SetParam", "SetMediaItemInfo_Value", "Main_OnCommand", "Undo_BeginBlock",
                 "InsertTrackAtIndex", "TrackFX_AddByName", "GetSetMediaTrackInfo_String", "ExecProcess"]:
        assert F._api_interesting(name), name
    for name in ["TrackFX_GetParam", "CountTracks", "ImGui_Button", "gfx_line", "JS_LICE_Blit",
                 "Undo_CanUndo2", "defer", "time_precise", "GetTrack"]:
        assert not F._api_interesting(name), name


def test_recording_logs_changes_and_ui_and_restores_functions():
    (L, F), _ = _rec_runtime()
    L.execute("ORIG_SET, ORIG_BUTTON = reaper.TrackFX_SetParam, IM.Button")
    F.StartRecording()
    assert F.IsRecording()
    assert L.eval("reaper.TrackFX_SetParam ~= ORIG_SET and IM.Button ~= ORIG_BUTTON")
    L.execute("""
      for i = 1, 3 do reaper.TrackFX_SetParam(nil, 0, 4, i / 10) end
      reaper.TrackFX_GetParam(nil, 0, 4)
      IM.Button("ctx", "Play##transport")
      IM.Button("ctx", "Stop")
      IM.SliderDouble("ctx", "Gain", 0.25)
      IM.InputText("ctx", "License key", "")
      IM.MenuItem("ctx", "Open settings...")
      reaper.SetExtState("FXD", "license", "ABCD-1234-SECRET", true)
      reaper.ExecProcess("/usr/bin/curl -d key=ABCDEFGHIJKLMNOPQRSTUVWXYZ123456 https://x")
    """)
    assert list(L.eval("CALLS").values()) == [0.1, 0.2, 0.3]
    F.StopRecording()
    assert not F.IsRecording() and F.HasRecording()
    assert L.eval("reaper.TrackFX_SetParam == ORIG_SET and IM.Button == ORIG_BUTTON")
    text = F.BuildLogText(L.table_from({"usage": False, "trace": True}))
    assert "-- Bug recording" in text
    assert "API TrackFX_SetParam(<ptr>, 0, 4, 0.3) -> true  (x3)" in text or \
        "API TrackFX_SetParam(nil, 0, 4, 0.3) -> true  (x3)" in text
    assert "TrackFX_GetParam" not in text
    assert 'UI click "Play"' in text and 'UI click "Stop"' not in text
    assert 'UI SliderDouble "Gain" = 1.25' in text
    assert 'UI typing in "License key" (17 chars)' in text
    assert 'UI menu "Open settings..."' in text
    assert "secret" not in text.lower() and "ABCD-1234" not in text and "ABCDEFGHIJ" not in text
    assert 'ExecProcess("curl", ...)' in text
    # After stopping, calls are no longer logged.
    L.execute('reaper.TrackFX_SetParam(nil, 1, 1, 0.9)')
    assert "0.9" not in F.BuildLogText(L.table_from({"usage": False, "trace": True}))


def test_recording_defer_logs_errors_and_reraises():
    (L, F), _ = _rec_runtime()
    F.StartRecording()
    L.execute("DEFERRED = {}")
    ok = L.eval("""function()
      reaper.defer(function() local t = nil; return t.x end)
      local f = table.remove(DEFERRED, 1)
      return pcall(f)
    end""")()
    assert ok[0] is False if isinstance(ok, tuple) else ok is False
    F.StopRecording()
    text = F.BuildLogText(L.table_from({"usage": False, "trace": True}))
    assert "ERROR " in text and "attempt to index" in text


def test_recording_goes_into_the_payload_and_resumes_after_restart():
    (L, F), tmp = _rec_runtime()
    F.StartRecording()
    L.execute("reaper.TrackFX_SetParam(nil, 0, 1, 0.7); CRSFeedback.Trace('before restart')")
    F._frame()  # one frame: flushes the recording file
    assert L.eval('EXT["CRS_Feedbackrecording_sample-map"]') == "1"
    # A restart while recording: the new instance resumes and keeps old lines.
    ext = {"CRS_Feedbackrecording_sample-map": "1"}
    L2, F2 = _runtime(resource=tmp, tmp=tmp, ext=ext)
    assert F2.IsRecording()
    F2.StopRecording()
    state = L2.eval('{ kind = "bug", title = "Knob jumps", note = "It jumps when I drag it.", contact = "", '
                    'include_log = true, include_trace = true, images = {} }')
    data = json.loads(F2._json_encode(F2._build_payload(state)))
    assert "-- Bug recording" in data["log"]
    assert "TrackFX_SetParam" in data["log"]
    assert "resumed after a restart" in data["log"]
    state.include_trace = False
    assert "-- Bug recording" not in json.loads(F2._json_encode(F2._build_payload(state)))["log"]
    F2.DiscardRecording()
    assert not F2.HasRecording()
    assert not os.path.exists(os.path.join(tmp, "Data", "CRS_Feedback", "sample-map.recording.log"))


def test_recording_send_size_is_capped():
    (L, F), _ = _rec_runtime()
    F.StartRecording()
    L.execute('for i = 1, 6000 do CRSFeedback.Trace(("event %d "):format(i) .. string.rep("x", 100)) end')
    F.StopRecording()
    lines = list(F._recording_lines().values())
    assert sum(len(l) + 1 for l in lines) <= F.TRACE_SEND_BYTES + 100
    assert lines[0].endswith("older lines left out)")
    assert "event 6000" in lines[-2] or "event 6000" in "".join(lines[-3:])

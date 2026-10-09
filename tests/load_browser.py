"""Smoke test: load Sample Map Browser in Lua 5.4 with a stub `reaper` API and run
the defer loop for a few frames. Catches load-time errors and nil globals in the
frame path. Requires `pip install lupa`.

usage: python3 tests/load_browser.py [repo_dir] [frames]"""
import sys, os, tempfile
from lupa import lua54
repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
frames = int(sys.argv[2]) if len(sys.argv) > 2 else 30
res = tempfile.mkdtemp()
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.globals().REPO = repo; L.globals().RES = res; L.globals().FRAMES = frames
out = L.execute(r'''
EXT = {}
local deferred, atexits, msgs, calls = {}, {}, {}, {}
local special = {
  APIExists = function() return true end,
  get_action_context = function() return false, REPO .. "/Sample Map Browser.lua", 0, 0, 0, 0, 0 end,
  GetResourcePath = function() return RES end,
  GetOS = function() return "macOS-arm64" end,
  GetExtState = function(s, k) return EXT[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) EXT[s .. "/" .. k] = tostring(v) end,
  DeleteExtState = function(s, k) EXT[s .. "/" .. k] = nil end,
  HasExtState = function(s, k) return EXT[s .. "/" .. k] ~= nil end,
  GetProjExtState = function() return 0, "" end,
  EnumProjects = function() return "PROJ", "" end,
  GetProjectStateChangeCount = function() return 1 end,
  time_precise = function() return os.clock() end,
  defer = function(f) deferred[#deferred+1] = f end,
  atexit = function(f) atexits[#atexits+1] = f end,
  ShowMessageBox = function(m, t) msgs[#msgs+1] = "MSGBOX " .. tostring(t) .. ": " .. tostring(m); return 1 end,
  ShowConsoleMsg = function(m) msgs[#msgs+1] = "CONSOLE " .. tostring(m) end,
  ImGui_CreateContext = function() return {} end,
  ImGui_ValidatePtr = function() return true end,
  ValidatePtr = function() return false end, ValidatePtr2 = function() return false end,
  ImGui_GetVersion = function() return "0.9.3", 0, "0.9.3" end,
  CountTracks = function() return 0 end, CountMediaItems = function() return 0 end,
  CountSelectedMediaItems = function() return 0 end, CountSelectedTracks = function() return 0 end,
  GetPlayState = function() return 0 end, GetCursorPosition = function() return 0 end,
  ExecProcess = function() return "1\n" end,
  EnumerateFiles = function() return nil end, EnumerateSubdirectories = function() return nil end,
  file_exists = function() return false end,
  RecursiveCreateDirectory = function() return 1 end,
  ImGui_GetWindowSize = function() return 800, 600 end, ImGui_GetContentRegionAvail = function() return 800, 600 end,
  ImGui_GetCursorScreenPos = function() return 0, 0 end, ImGui_GetMousePos = function() return 0, 0 end,
  ImGui_GetWindowPos = function() return 0, 0 end, ImGui_GetDisplaySize = function() return 1600, 1000 end,
  ImGui_CalcTextSize = function(_, s) return #tostring(s) * 7, 14 end,
  ImGui_GetFrameHeight = function() return 20 end, ImGui_GetTextLineHeight = function() return 14 end,
  ImGui_GetStyleVar = function() return 4, 4 end, ImGui_GetTime = function() return os.clock() end,
  ImGui_GetDeltaTime = function() return 1/30 end, ImGui_GetCursorPos = function() return 0, 0 end,
  ImGui_GetMouseDelta = function() return 0, 0 end, ImGui_GetMouseWheel = function() return 0, 0 end,
  ImGui_GetCursorPosX = function() return 0 end, ImGui_GetCursorPosY = function() return 0 end,
  ImGui_GetScrollY = function() return 0 end, ImGui_GetScrollX = function() return 0 end,
  ImGui_GetScrollMaxY = function() return 0 end, ImGui_GetWindowWidth = function() return 800 end,
  ImGui_GetWindowHeight = function() return 600 end, ImGui_GetFontSize = function() return 13 end,
  ImGui_GetItemRectMin = function() return 0, 0 end, ImGui_GetItemRectMax = function() return 10, 10 end,
  ImGui_GetItemRectSize = function() return 10, 10 end, ImGui_GetMainViewport = function() return {} end,
  ImGui_Viewport_GetPos = function() return 0, 0 end, ImGui_Viewport_GetSize = function() return 1600, 1000 end,
  ImGui_Viewport_GetWorkPos = function() return 0, 0 end, ImGui_Viewport_GetWorkSize = function() return 1600, 1000 end,
  ImGui_GetColor = function() return 0 end, ImGui_GetStyleColor = function() return 0 end,
  ImGui_GetFrameCount = function() return 1 end, ImGui_GetWindowDrawList = function() return {} end,
  ImGui_GetForegroundDrawList = function() return {} end, ImGui_GetBackgroundDrawList = function() return {} end,
  ImGui_Begin = function() return true, true end, ImGui_BeginChild = function() return true end,
  ImGui_GetWindowDockID = function() return 0 end, ImGui_IsWindowDocked = function() return false end,
  ImGui_GetKeyMods = function() return 0 end, ImGui_GetWindowContentRegionMax = function() return 800, 600 end,
  ImGui_GetMouseClickedPos = function() return 0, 0 end, ImGui_GetMouseDragDelta = function() return 0, 0 end,
  ImGui_GetItemID = function() return 0 end, ImGui_GetID = function() return 1 end,
  GetTrackGUID = function() return "{0}" end, GetMasterTrack = function() return "MASTER" end,
  GetHZoomLevel = function() return 100 end, GetSet_ArrangeView2 = function() return 0, 10 end,
  TimeMap2_QNToTime = function(_, q) return q * 0.5 end, TimeMap2_timeToQN = function(_, t) return t * 2 end,
  TimeMap_GetDividedBpmAtTime = function() return 120 end, Master_GetTempo = function() return 120 end,
  GetProjectTimeSignature2 = function() return 120, 4 end, TimeMap_GetTimeSigAtTime = function() return 4, 4, 120 end,
  GetPlayPosition = function() return 0 end, GetPlayPosition2 = function() return 0 end,
  GetCursorPositionEx = function() return 0 end,
  GetAppVersion = function() return "7.20/macOS-arm64" end,
  JS_Window_Find = function() return nil end, JS_Window_GetClientRect = function() return false end,
  ImGui_TableGetColumnCount = function() return 0 end, ImGui_GetIO = function() return nil end,
  JS_Mouse_GetState = function() return 0 end, JS_VKeys_GetState = function() return string.rep("\0", 255) end,
  GetMousePosition = function() return 0, 0 end, GetCursorContext = function() return -1 end,
  GetCursorContext2 = function() return -1 end, GetToggleCommandState = function() return 0 end,
  GetProjectLength = function() return 0 end, GetProjectPath = function() return RES end,
  GetProjectName = function() return "" end, GetSetProjectInfo = function() return 0 end,
  GetSetProjectInfo_String = function() return false, "" end, GetSetMediaTrackInfo_String = function() return false, "" end,
  CountTempoTimeSigMarkers = function() return 0 end, GetMaxMidiInputs = function() return 0 end,
  ImGui_GetMouseCursor = function() return 0 end, ImGui_GetWindowViewport = function() return {} end,
  gmem_read = function() return 0 end, gmem_attach = function() end,
  GetLastTouchedFX = function() return false end, GetFocusedFX = function() return 0 end,
  GetProjectTimeOffset = function() return 0 end, GetSetRepeat = function() return 0 end,
  GetLoopTimeRange2 = function() return 0, 0 end, GetSet_LoopTimeRange2 = function() return 0, 0 end,
}
local function default_for(name)
  if name:match("^ImGui_[A-Z]%w*Flags_") or name:match("^ImGui_Col_") or name:match("^ImGui_Key_")
     or name:match("^ImGui_Mod_") or name:match("^ImGui_StyleVar_") or name:match("^ImGui_Cond_")
     or name:match("^ImGui_MouseButton_") or name:match("^ImGui_Dir_") or name:match("^ImGui_MouseCursor_")
     or name:match("^ImGui_ConfigVar_") or name:match("^ImGui_DrawFlags_") or name:match("^ImGui_ColorEditFlags_")
     or name:match("^ImGui_TableFlags_") or name:match("^ImGui_TableColumnFlags_") then
    return function() return 0 end
  end
  if name:match("^ImGui_Is") or name:match("^ImGui_Begin") then return function() return false end end
  if name:match("^ImGui_Get") or name:match("^ImGui_Calc") or name:match("^ImGui_Table_Get") then return function() return 0, 0 end end
  if name:match("^ImGui_") then return function() return nil end end
  if name:match("^Count") then return function() return 0 end end
  return function() return nil end
end
reaper = setmetatable({}, { __index = function(t, k)
  calls[k] = (calls[k] or 0) + 1
  local f = special[k] or default_for(k); rawset(t, k, f); return f end })
gfx = setmetatable({}, { __index = function() return function() return 0 end end })
io.popen = function(cmd)
  msgs[#msgs+1] = "POPEN " .. tostring(cmd)
  return { read = function() return nil end, close = function() return true end, lines = function() return function() return nil end end, write = function() end }
end
os.execute = function(cmd) msgs[#msgs+1] = "EXEC " .. tostring(cmd); return true end
local report = {}
local chunk, err = loadfile(REPO .. "/Sample Map Browser.lua")
if not chunk then return "LOADFAIL " .. err end
local ok, e = xpcall(chunk, debug.traceback)
report[#report+1] = ok and "MAIN OK" or ("MAIN ERROR " .. tostring(e))
if rawget(_G, "log") then log = function(m) msgs[#msgs+1] = "LOG " .. tostring(m) end end
for i = 1, FRAMES do
  local q = deferred; deferred = {}
  if #q == 0 then report[#report+1] = "no deferred fn at frame " .. i; break end
  for _, f in ipairs(q) do
    local ok2, e2 = xpcall(f, debug.traceback)
    if not ok2 then report[#report+1] = ("FRAME %d ERROR %s"):format(i, tostring(e2)); break end
  end
end
report[#report+1] = ("frames run; pending deferred=%d atexit=%d"):format(#deferred, #atexits)
for _, f in ipairs(atexits) do local ok3, e3 = xpcall(f, debug.traceback); if not ok3 then report[#report+1] = "ATEXIT ERROR " .. tostring(e3) end end
for _, m in ipairs(msgs) do report[#report+1] = m:sub(1, 300) end
return table.concat(report, "\n")
''')
print(out)
bad = [l for l in out.splitlines() if l.startswith(("LOADFAIL", "MAIN ERROR", "FRAME", "ATEXIT ERROR", "LOG ImGui frame skipped", "MSGBOX"))
       or "error" in l.lower() and l.startswith("LOG")]
if not out.splitlines()[0].startswith("MAIN OK") or bad:
    sys.exit(1)

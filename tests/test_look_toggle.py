"""Look setting (browser/11c_monolith.lua): Classic is the default and leaves the
theme as it was; Monolith Space (ExtState SampleMapBrowser/look) swaps the
palette, squares rect corners, and switching back restores everything.
Runs the browser with a stub REAPER. Requires `pip install lupa`."""
import os
import tempfile

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

STUB = r'''
EXT = { ["SampleMapBrowser/look"] = LOOK_INIT }
NOW = 100.0
local deferred = {}
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
  time_precise = function() return NOW end,
  defer = function(f) deferred[#deferred + 1] = f end,
  atexit = function() end,
  ShowMessageBox = function() return 1 end,
  ShowConsoleMsg = function() end,
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
  GetAppVersion = function() return "7.20/macOS-arm64" end,
  JS_VKeys_GetState = function() return string.rep("\0", 255) end,
  JS_Mouse_GetState = function() return 0 end,
  GetMousePosition = function() return 0, 0 end,
  Master_GetTempo = function() return 120 end,
  GetSetProjectInfo_String = function() return false, "" end, GetSetMediaTrackInfo_String = function() return false, "" end,
  GetProjectPath = function() return RES end, GetProjectName = function() return "" end,
  ImGui_Begin = function() return true, true end,
  ImGui_GetWindowPos = function() return 40, 40 end,
  ImGui_GetWindowSize = function() return 800, 600 end,
  ImGui_GetContentRegionAvail = function() return 736, 500 end,
  ImGui_GetCursorScreenPos = function() return 52, 50 end,
  ImGui_GetItemRectMin = function() return 52, 50 end,
  ImGui_GetItemRectMax = function() return 120, 72 end,
  ImGui_CalcTextSize = function(_, s) return #tostring(s) * 7, 14 end,
  ImGui_GetStyleVar = function() return 8, 4 end,
  ImGui_GetWindowDrawList = function() return {} end,
}
local function default_for(name)
  if name:match("^ImGui_[A-Z]%w*Flags_") or name:match("^ImGui_Col_") or name:match("^ImGui_Key_")
     or name:match("^ImGui_Mod_") or name:match("^ImGui_StyleVar_") or name:match("^ImGui_Cond_")
     or name:match("^ImGui_MouseButton_") or name:match("^ImGui_Dir_") or name:match("^ImGui_MouseCursor_")
     or name:match("^ImGui_ConfigVar_") or name:match("^ImGui_DrawFlags_") or name:match("^ImGui_TableFlags_") then
    return function() return 0 end
  end
  if name:match("^ImGui_Is") or name:match("^ImGui_Begin") then return function() return false end end
  if name:match("^ImGui_Get") or name:match("^ImGui_Calc") then return function() return 0, 0 end end
  if name:match("^Count") then return function() return 0 end end
  return function() return nil end
end
reaper = setmetatable({}, { __index = function(t, k)
  local f = special[k] or default_for(k)
  rawset(t, k, f)
  return f
end })
gfx = setmetatable({}, { __index = function() return function() return 0 end end })
io.popen = function() return { read = function() return nil end, close = function() return true end, lines = function() return function() return nil end end } end
os.execute = function() return true end
local chunk = assert(loadfile(REPO .. "/Sample Map Browser.lua"))
chunk()
for i = 1, 3 do local q = deferred; deferred = {}; for _, f in ipairs(q) do f() end end
'''


def _runtime(look=None):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.REPO = ROOT
    g.RES = tempfile.mkdtemp()
    g.LOOK_INIT = look
    L.execute(STUB)
    return L


def test_classic_is_default_and_unchanged():
    L = _runtime()
    g = L.globals()
    assert g.SM_MONO_SPACE is False
    assert g.UI_THEME.accent == 0x1EFF5EFF
    assert g.UI_THEME.bg == 0x0F1013FF
    assert g.UI_METRICS.radius_ctrl == 6
    assert g.ui_accent_a(0x44) == 0x1EFF5E44
    assert L.eval("reaper.ImGui_DrawList_AddRect == rawget(reaper, 'ImGui_DrawList_AddRect')")


def test_space_from_extstate_then_back_to_classic():
    L = _runtime("monolith_space")
    g = L.globals()
    assert g.SM_MONO_SPACE is True
    assert g.UI_THEME.accent == g.UI_THEME_SPACE.accent
    assert g.UI_THEME.bg == g.UI_THEME_SPACE.bg
    assert g.UI_METRICS.radius_ctrl == 0
    assert g.MONO_COL.tick == 0x49CC85FF
    # rect draws go through the square-corner wrapper while on, and back after
    same = L.execute("""
      local wrapped = reaper.ImGui_DrawList_AddRectFilled
      sm_look_set(false)
      local plain = reaper.ImGui_DrawList_AddRectFilled
      sm_look_set(true)
      return wrapped ~= plain and reaper.ImGui_DrawList_AddRectFilled ~= plain
    """)
    assert same is True
    g.sm_look_set(False)
    assert g.SM_MONO_SPACE is False
    assert g.UI_THEME.accent == 0x1EFF5EFF
    assert g.UI_METRICS.radius_ctrl == 6
    assert L.eval("EXT['SampleMapBrowser/look']") == "classic"


def test_space_frames_run_with_backdrop():
    L = _runtime("monolith_space")
    count = L.execute("""
      local n = 0
      reaper.ImGui_DrawList_AddCircleFilled = function() n = n + 1 end
      sm_mono_space_backdrop()
      return n
    """)
    assert count > 50


def test_fonts_pushed_only_in_space():
    L = _runtime()
    pushes = L.execute("""
      local n = 0
      reaper.ImGui_CreateFont = function(name, sz) return { name = name } end
      reaper.ImGui_CreateFontFromFile = function(name) return { name = name } end
      reaper.ImGui_Attach = function() end
      reaper.ImGui_PushFont = function() n = n + 1 end
      reaper.ImGui_PopFont = function() end
      sm_mono_fonts_create(ctx)
      assert(SM_MONO_FONTS.body and SM_MONO_FONTS.bold and SM_MONO_FONTS.cond and SM_MONO_FONTS.title,
        "fonts not created")
      ui_push_theme(); ui_pop_theme()
      local classic = n
      sm_look_set(true)
      ui_push_theme(); ui_pop_theme()
      return classic, n
    """)
    assert pushes == (0, 1)


def test_space_tone_and_ui_tc():
    L = _runtime()
    g = L.globals()
    assert g.ui_tc(0x0C0D10FF) == 0x0C0D10FF          # Classic: unchanged
    g.sm_look_set(True)
    gray = g.ui_tc(0x0C0D10FF)
    assert gray != 0x0C0D10FF and (gray >> 8) & 0xFF > (gray >> 24) & 0xFF   # blue cast
    assert gray & 0xFF == 0xFF
    assert g.ui_tc(0xFFC870FF) == 0xFFC870FF          # amber stays amber
    cyan = g.ui_tc(0x1EFF5E80)
    rr, gg, bb, a = (cyan >> 24) & 0xFF, (cyan >> 16) & 0xFF, (cyan >> 8) & 0xFF, cyan & 0xFF
    assert bb > gg > rr and a == 0x80                 # accent green turns cyan


def test_tight_places_use_condensed_font_only_in_space():
    L = _runtime()
    got = L.execute("""
      local pushed = {}
      reaper.ImGui_CreateFont = function(name, sz) return { name = name } end
      reaper.ImGui_CreateFontFromFile = function(name) return { name = name } end
      reaper.ImGui_Attach = function() end
      reaper.ImGui_PushFont = function(_, f) pushed[#pushed + 1] = f end
      reaper.ImGui_PopFont = function() end
      sm_mono_fonts_create(ctx)
      local inner = render_view_tab_switcher
      render_view_tab_switcher = function() end
      sm_look_set(true)
      render_view_tab_switcher()
      local on = pushed[#pushed] == SM_MONO_FONTS.cond
      sm_look_set(false)
      local n = #pushed
      render_view_tab_switcher()
      return on, #pushed == n
    """)
    assert got == (True, True)


def test_custom_title_bar_in_space():
    L = _runtime()
    got = L.execute("""
      local seen_flags
      local plain = reaper.ImGui_Begin
      reaper.ImGui_WindowFlags_NoTitleBar = function() return 1 end
      sm_look_set(false)
      local orig = function(c, name, p_open, flags) seen_flags = flags; return true, true end
      reaper.ImGui_Begin = orig
      -- reinstall around the stub Begin
      sm_look_set(false)
      local clicks = 0
      reaper.ImGui_InvisibleButton = function(_, id) if id:find("close") then clicks = clicks + 1; return true end return false end
      sm_look_set(true)
      local v, open = reaper.ImGui_Begin(ctx, "Settings", true, 0)
      local bar_flags = seen_flags
      local v2, open2 = reaper.ImGui_Begin(ctx, "##popup", nil, 0)
      local popup_flags = seen_flags
      sm_look_set(false)
      local v3, open3 = reaper.ImGui_Begin(ctx, "Settings", true, 0)
      return bar_flags, open, popup_flags, seen_flags, open3, reaper.ImGui_Begin == orig
    """)
    bar_flags, open_, popup_flags, classic_flags, open3, restored = got
    assert bar_flags == 1 and open_ is False      # NoTitleBar added; X click closes
    assert popup_flags == 0                        # "##" windows untouched
    assert classic_flags == 0 and open3 is True and restored

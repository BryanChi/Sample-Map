-- @noindex
-- CRS Feedback: an in-script "Send feedback" window shared by BryanChi's REAPER
-- scripts (Sample Map, FX Devices, Vertical FX List).
--
-- A report (title, note, optional contact, optional usage log, up to 5
-- pictures) is posted with curl to a small relay (feedback/relay in the
-- Sample-Map repo). The relay holds the GitHub token and files the report as
-- an issue on the script's repository. No token ever ships with a script.
--
-- Usage from a host script:
--
--   local Feedback = dofile(dir .. "/CRS_Feedback.lua")
--   Feedback.Setup({
--     script_id = "sample-map",          -- must be known to the relay
--     script_name = "Sample Map",
--     version = "0.1.0",
--     get_log = function() return { "line", ... } end, -- optional, extra log lines
--   })
--   Feedback.Log("Scanned 2,400 files")   -- optional usage log lines
--   if ImGui.MenuItem(ctx, "Send feedback...") then Feedback.Open() end
--   Feedback.Defer(loop)                  -- optional: r.defer that reports crashes
--
-- Look: the "Monolith" style (black, square controls, display and mono caps).
-- Optional Setup field fonts = { title = <Anton .ttf>, mono = <JetBrains Mono
-- .ttf>, mono_bold, body, body_bold } loads those files into the window's own
-- context; anything missing falls back to a system font.
--
-- Bug recording (see the "Bug recording" section): the window opens with a
-- "Start bug recording" button; hosts can also call Feedback.StartRecording(),
-- and Feedback.StopAndReport() to stop and open the window with it attached.
-- record_hint = "or ..." in Setup adds where else recording can be stopped.
-- Optional Setup fields for it: imgui = the script's ImGui API table (globals
-- ImGui / im are found on their own), get_state = function returning lines
-- describing the script's state, on_recording = function(on) to switch the
-- script's own debug output. Feedback.Trace("msg") adds a line while recording.
-- Call Setup when the script starts, so a recording left on resumes.
-- private_repo = true in Setup says reports land in a private repo.
--
-- Recorder script: while recording, the badge and the window that sends the
-- recording run in CRS_Feedback_Recorder.lua (next to this file), a separate
-- script with its own Lua state, so they stay up when the host crashes or is
-- closed. The host starts it, and the two talk through ExtState (see the
-- "Recorder script" section). Without that file the host draws the badge.
--
-- The window runs in its own ImGui context and defer loop, so the host only
-- needs to call Open(). This file defines the global CRSFeedback and returns
-- it; loading it twice reuses the first copy.

if CRSFeedback and CRSFeedback.API_VERSION then
  return CRSFeedback
end

local r = reaper
local F = {}
CRSFeedback = F

F.API_VERSION = 1

-- This file's folder (the recorder script sits next to it).
local MODULE_DIR = (debug and debug.getinfo and (debug.getinfo(1, "S").source or "") or ""):match("^@(.+)[/\\][^/\\]+$")
F.RECORDER_FILE = "CRS_Feedback_Recorder.lua"

-- Where reports go. Set this once the relay is deployed (see
-- feedback/README.md). An ExtState override lets testers point at a dev relay:
-- reaper.SetExtState("CRS_Feedback", "endpoint", "https://...", true)
F.ENDPOINT = "https://crs-feedback.brwchi.workers.dev/report"

F.MAX_IMAGES = 5
F.MAX_IMAGE_BYTES = 5 * 1024 * 1024
F.MAX_NOTE_CHARS = 8000
F.MAX_LOG_LINES = 400
F.LOG_FILE_KEEP = 96 * 1024

local cfg = {
  script_id = "unknown",
  script_name = "REAPER script",
  version = "?",
}

local ImGui -- the module's own ImGui API table
local ctx -- the module's own ImGui context (feedback window, recording badge)

-- --- Small utilities -------------------------------------------------------

local function now_s()
  return (r.time_precise and r.time_precise()) or os.clock()
end

local function os_name()
  return (r.GetOS and r.GetOS()) or "?"
end

local function is_windows()
  return os_name():match("^Win") ~= nil
end

local function is_mac()
  local o = os_name()
  return o:match("^OSX") ~= nil or o:match("^macOS") ~= nil
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function file_size(path)
  local fh = io.open(path, "rb")
  if not fh then
    return nil
  end
  local size = fh:seek("end")
  fh:close()
  return size
end

local function read_file(path)
  local fh = io.open(path, "rb")
  if not fh then
    return nil
  end
  local data = fh:read("*a")
  fh:close()
  return data
end

local function write_file(path, data)
  local fh = io.open(path, "wb")
  if not fh then
    return false
  end
  fh:write(data)
  fh:close()
  return true
end

local function data_dir()
  local base = (r.GetResourcePath and r.GetResourcePath()) or "."
  local dir = base .. "/Data/CRS_Feedback"
  if r.RecursiveCreateDirectory then
    r.RecursiveCreateDirectory(dir, 0)
  end
  return dir
end

local function safe_id(s)
  return (tostring(s or "x"):gsub("[^%w%-_]", "_"))
end

-- Minimal JSON encoder for the payload (strings, numbers, booleans, arrays, objects).
local function json_encode(v)
  local t = type(v)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return "null"
    end
    if math.type and math.type(v) == "integer" then
      return tostring(v)
    end
    return string.format("%.14g", v)
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' end
      if c == "\\" then return "\\\\" end
      if c == "\n" then return "\\n" end
      if c == "\r" then return "\\r" end
      if c == "\t" then return "\\t" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for i = 1, #v do
        parts[i] = json_encode(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = json_encode(k) .. ":" .. json_encode(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end
F._json_encode = json_encode

-- Pull a string field out of the relay's (flat) JSON reply.
local function json_field(s, key)
  local v = tostring(s or ""):match('"' .. key .. '"%s*:%s*"(.-[^\\])"')
  if v then
    return (v:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\n", "\n"):gsub("\\\\", "\\"))
  end
  return tostring(s or ""):match('"' .. key .. '"%s*:%s*(%-?%d+)')
end
F._json_field = json_field

-- Replace personal parts of file paths: the REAPER resource folder, the home
-- folder and user names in /Users/<name>, /home/<name> and C:\Users\<name>.
local function lua_pattern_escape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

function F.ScrubPaths(text)
  text = tostring(text or "")
  local res = r.GetResourcePath and r.GetResourcePath() or nil
  if res and #res > 3 then
    text = text:gsub(lua_pattern_escape(res), "<REAPER>")
    text = text:gsub(lua_pattern_escape((res:gsub("/", "\\"))), "<REAPER>")
  end
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
  if home and #home > 3 then
    text = text:gsub(lua_pattern_escape(home), "~")
  end
  text = text:gsub("/Users/[^/%s\"']+", "/Users/<user>")
  text = text:gsub("/home/[^/%s\"']+", "/home/<user>")
  text = text:gsub("([A-Za-z]:[\\/][Uu]sers[\\/])[^\\/\"'\r\n]+", "%1<user>")
  return text
end

-- --- Usage log ---------------------------------------------------------------
-- Lines go to an in-memory ring buffer and to a small file per script, so a
-- report sent after a crash or restart still has the last session's lines.

local log_buf = { lines = {}, next = 1, count = 0 }
local log_path

local function log_file()
  if not log_path then
    log_path = data_dir() .. "/" .. safe_id(cfg.script_id) .. ".log"
    -- Keep the file small: drop the oldest part once it passes twice the limit.
    local size = file_size(log_path)
    if size and size > F.LOG_FILE_KEEP * 2 then
      local data = read_file(log_path) or ""
      local tail = data:sub(-F.LOG_FILE_KEEP)
      tail = tail:gsub("^[^\n]*\n", "")
      write_file(log_path, tail)
    end
  end
  return log_path
end

local function ring_push(line)
  log_buf.lines[log_buf.next] = line
  log_buf.next = (log_buf.next % F.MAX_LOG_LINES) + 1
  if log_buf.count < F.MAX_LOG_LINES then
    log_buf.count = log_buf.count + 1
  end
end

function F.Log(msg)
  local line = os.date("%H:%M:%S ") .. tostring(msg):gsub("[\r\n]+", " | ")
  ring_push(line)
  local fh = io.open(log_file(), "ab")
  if fh then
    fh:write(os.date("%Y-%m-%d ") .. line .. "\n")
    fh:close()
  end
end

local function ring_lines()
  local out = {}
  local start = (log_buf.count < F.MAX_LOG_LINES) and 1 or log_buf.next
  for i = 0, log_buf.count - 1 do
    out[#out + 1] = log_buf.lines[((start - 1 + i) % F.MAX_LOG_LINES) + 1]
  end
  return out
end

local function file_log_tail(max_lines)
  local data = read_file(log_file()) or ""
  local lines = {}
  for line in data:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  local first = math.max(1, #lines - max_lines + 1)
  local out = {}
  for i = first, #lines do
    out[#out + 1] = lines[i]
  end
  return out
end

-- --- Environment -------------------------------------------------------------

local function install_id()
  local id = r.GetExtState and r.GetExtState("CRS_Feedback", "install_id") or ""
  if id == "" then
    -- Not seeded on purpose: reseeding would change the host script's math.random.
    local seed = tostring(now_s()) .. tostring({}) .. tostring(os.time())
    local h = 5381
    for i = 1, #seed do
      h = (h * 33 + seed:byte(i)) % 4294967296
    end
    id = string.format("%08x%02x", h, math.random(0, 255))
    if r.SetExtState then
      r.SetExtState("CRS_Feedback", "install_id", id, true)
    end
  end
  return id
end

local function environment()
  local reaimgui = "?"
  if r.ImGui_GetVersion then
    local ok, imgui_v, _, reaimgui_v = pcall(r.ImGui_GetVersion)
    if ok then
      reaimgui = tostring(reaimgui_v or imgui_v)
    end
  end
  local app = (r.GetAppVersion and r.GetAppVersion()) or "?"
  return {
    reaper = app:match("^([^/]+)") or app,
    os = os_name(),
    reaimgui = reaimgui,
    js_api = r.APIExists and r.APIExists("JS_ReaScriptAPI_Version") or false,
    sws = r.APIExists and r.APIExists("CF_GetSWSVersion") or false,
    install_id = install_id(),
  }
end
F._environment = environment

-- --- Bug recording -----------------------------------------------------------
-- A mode the user switches on while repeating a bug. It writes down much more
-- than the usage log: every REAPER call the script makes that changes
-- something (with its arguments), every button, menu item, checkbox, slider and
-- text field the user touches, shortcut keys and clicks the script reacts to,
-- errors with tracebacks, slow frames, undo points, transport changes and
-- memory use. It slows the script down a little, so it is only on while the
-- small "Recording" badge is showing. It stays on across a restart, so bugs at
-- startup are caught too.
--
-- How: while on, functions in the `reaper` table (and in the host's ImGui
-- table, see Setup's `imgui`) are replaced with thin wrappers that log and
-- then call the original. Stopping puts the originals back; a wrapper a script
-- copied into a local meanwhile just passes calls through.
--
-- Privacy: typed text is never recorded (only its length), ExtState values and
-- shell commands are hidden, long tokens (license keys, hashes) and e-mail
-- addresses are masked, and the report scrubs personal folder names as usual.

F.TRACE_MAX_LINES = 6000
F.TRACE_FILE_KEEP = 1024 * 1024
F.TRACE_SEND_BYTES = 420 * 1024
F.SLOW_FRAME_MS = 50

local T = {
  on = false,
  lines = {}, next = 1, count = 0, -- ring buffer of finished lines
  events = 0, -- lines recorded since the recording started
  pending = nil, -- { key, text, n, t } a line still collecting repeats
  recent = {}, -- dedupe key -> time
  originals = {}, -- [table] = { name = original function }
  is_wrapper = setmetatable({}, { __mode = "k" }),
  busy = false, -- true while the recorder itself runs (no self-logging)
}
F._T = T

local function rec_path()
  return data_dir() .. "/" .. safe_id(cfg.script_id) .. ".recording.log"
end

local function rec_clock()
  local t = now_s()
  return os.date("%H:%M:%S") .. string.format(".%03d", math.floor((t % 1) * 1000))
end

local function rec_write(line)
  T.lines[T.next] = line
  T.next = (T.next % F.TRACE_MAX_LINES) + 1
  if T.count < F.TRACE_MAX_LINES then
    T.count = T.count + 1
  end
  T.events = T.events + 1
  if T.fh then
    T.fh:write(line, "\n")
  end
end

local function rec_flush_pending()
  local p = T.pending
  if p then
    T.pending = nil
    rec_write(p.n > 1 and (p.text .. "  (x" .. p.n .. ")") or p.text)
  end
end

-- Record one line. Lines with the same `key` in a row (a slider being
-- dragged, a parameter set every frame) collapse into one, keeping the
-- latest text and a repeat count.
local function rec(text, key)
  if key and T.pending and T.pending.key == key then
    T.pending.text = rec_clock() .. " " .. text
    T.pending.n = T.pending.n + 1
    return
  end
  rec_flush_pending()
  local line = rec_clock() .. " " .. text
  if key then
    T.pending = { key = key, text = line, n = 1, t = now_s() }
  else
    rec_write(line)
  end
end

-- True when `key` was already seen within `window` seconds (several calls in
-- one frame asking the same question, e.g. IsMouseClicked in many places).
local function rec_seen(key, window)
  local t = now_s()
  local last = T.recent[key]
  T.recent[key] = t
  return last ~= nil and t - last < (window or 0.03)
end

local function mask(s)
  s = s:gsub("[%w%._%%+%-]+@[%w%.%-]+%.%a%a+", "<email>")
  s = s:gsub("[%w%-_]+", function(w)
    if #w >= 24 and w:find("%d") and w:find("%a") then
      return "<hidden>"
    end
  end)
  return s
end

local PTR_TYPES = { "MediaTrack*", "MediaItem*", "MediaItem_Take*", "TrackEnvelope*", "ReaProject*" }

local function describe_ptr(v)
  if not r.ValidatePtr then
    return "<ptr>"
  end
  for _, ty in ipairs(PTR_TYPES) do
    local ok, valid = pcall(r.ValidatePtr, v, ty)
    if ok and valid then
      if ty == "MediaTrack*" then
        local n = r.GetMediaTrackInfo_Value and r.GetMediaTrackInfo_Value(v, "IP_TRACKNUMBER")
        if n == -1 then
          return "<master track>"
        end
        local name = ""
        if r.GetTrackName then
          local _, nm = r.GetTrackName(v)
          name = nm and (" " .. string.format("%q", mask(nm:sub(1, 40)))) or ""
        end
        return "<track " .. math.floor(n or 0) .. name .. ">"
      elseif ty == "MediaItem*" then
        return "<item>"
      elseif ty == "MediaItem_Take*" then
        return "<take>"
      elseif ty == "TrackEnvelope*" then
        return "<envelope>"
      end
      return "<project>"
    end
  end
  return "<ptr>"
end

local function fmt_val(v)
  local t = type(v)
  if t == "string" then
    local s = v
    if #s > 80 then
      s = s:sub(1, 60) .. "... (" .. #v .. " chars)"
    end
    s = mask(s):gsub("[%c]", function(c)
      return c == "\n" and "\\n" or (c == "\t" and "\\t" or "")
    end)
    return '"' .. s .. '"'
  elseif t == "number" then
    if math.type and math.type(v) == "integer" then
      return tostring(v)
    end
    return string.format("%.5g", v)
  elseif t == "userdata" or t == "lightuserdata" then
    return describe_ptr(v)
  elseif t == "function" then
    return "<function>"
  elseif t == "table" then
    return "<table>"
  end
  return tostring(v)
end

local function fmt_args(args, from, to)
  local out = {}
  for i = from, to do
    out[#out + 1] = fmt_val(args[i])
  end
  return table.concat(out, ", ")
end

-- --- REAPER calls ---

-- Calls that change something. A name matches when one of these starts it or
-- follows an underscore (TrackFX_SetParam, SetMediaItemInfo_Value).
local API_VERBS = {
  "Set", "Add", "Delete", "Insert", "Move", "Copy", "Create", "Remove", "Split", "Apply",
  "Show", "Open", "Close", "Load", "Save", "Glue", "Duplicate", "Select", "Unselect",
  "Paste", "Cut", "Clear", "Toggle", "Freeze", "Unfreeze", "Render", "OnCommand",
  "Exec", "ShellExecute", "Undo_", "Begin", "End",
}
local API_SKIP_PREFIX = { "ImGui_", "gfx", "JS_LICE_", "JS_GDI_", "JS_Composite", "JS_Mem", "JS_Double",
  "JS_Int", "JS_Byte", "JS_String", "JS_Va", "time_precise", "defer", "runloop", "atexit" }
local API_SKIP = {
  Undo_CanUndo2 = true, Undo_CanRedo2 = true, PreventUIRefresh = true, SetCursorContext = true,
}
-- Calls whose arguments may hold something private: logged without them.
local API_HIDE_VALUE = {
  SetExtState = 3, SetProjExtState = 4, DeleteExtState = false, GetSetProjectInfo_String = 3,
}

local function api_interesting(name)
  if API_SKIP[name] then
    return false
  end
  for _, p in ipairs(API_SKIP_PREFIX) do
    if name:sub(1, #p) == p then
      return false
    end
  end
  for _, v in ipairs(API_VERBS) do
    if name:sub(1, #v) == v or name:find("_" .. v, 1, true) then
      return true
    end
  end
  return name:sub(1, 6) == "GetSet"
end
F._api_interesting = api_interesting

local function log_api(name, args, ret)
  local text
  if name == "ExecProcess" or name == "CF_ShellExecute" or name == "ExecProcessEx" then
    local cmd = tostring(args[1] or "")
    text = name .. "(" .. fmt_val((cmd:match("^%s*\"?([^%s\"]+)") or ""):match("([^/\\]+)$") or "") .. ", ...)"
  else
    local hide = API_HIDE_VALUE[name]
    if hide then
      local shown = {}
      for i = 1, args.n do
        shown[i] = (i == hide) and ("<" .. #tostring(args[i] or "") .. " chars>") or fmt_val(args[i])
      end
      text = name .. "(" .. table.concat(shown, ", ") .. ")"
    else
      text = name .. "(" .. fmt_args(args, 1, args.n) .. ")"
    end
  end
  if ret ~= nil then
    text = text .. " -> " .. fmt_val(ret)
  end
  -- Same call on the same target in a row (a parameter set every frame)
  -- collapses; the key leaves out the last argument (the new value).
  local key = "api|" .. name .. "|" .. fmt_args(args, 1, args.n == 1 and 1 or args.n - 1)
  rec("API " .. text, key)
end

local function wrap_api(name, orig)
  local getset = name:sub(1, 6) == "GetSet"
  local w = function(...)
    if not T.on or T.busy then
      return orig(...)
    end
    local args = table.pack(...)
    local res = table.pack(orig(...))
    local setting = true
    if getset then
      setting = false
      for i = 1, args.n do
        if args[i] == true then
          setting = true
          break
        end
      end
    end
    if setting then
      T.busy = true
      pcall(log_api, name, args, res[1])
      T.busy = false
    end
    return table.unpack(res, 1, res.n)
  end
  T.is_wrapper[w] = true
  return w
end

-- --- ImGui widgets ---

local function widget_kind(n)
  -- Constants (InputTextFlags_CharsScientific, Key_A...) have an underscore;
  -- widget functions don't.
  if n:find("_", 1, true) then
    return nil
  end
  if n == "Button" or n == "SmallButton" or n == "ArrowButton" or n == "ImageButton" then
    return "click"
  elseif n == "InvisibleButton" then
    return "press"
  elseif n == "Selectable" or n == "MenuItem" or n == "RadioButton" then
    return "select"
  elseif n == "Checkbox" or n == "CheckboxFlags" then
    return "toggle"
  elseif n:sub(1, 9) == "InputText" then
    return "text"
  elseif n:find("DragDrop", 1, true) then
    return n:sub(1, 21) == "AcceptDragDropPayload" and "drop" or nil
  elseif n:match("^V?Slider") or n:match("^Drag") or n:match("^Input") or n:match("^Color[EP]")
    or n == "Combo" or n == "ListBox" or n == "RadioButtonEx" then
    return "value"
  elseif n == "OpenPopup" then
    return "popup"
  elseif n == "IsKeyPressed" or n == "IsKeyChordPressed" or n == "Shortcut" then
    return "key"
  elseif n == "IsMouseClicked" or n == "IsMouseDoubleClicked" then
    return "mouse"
  end
end
F._widget_kind = widget_kind

local function label_of(s)
  s = tostring(s or "")
  local shown = s:match("^(.-)##") or s
  if shown == "" then
    shown = s:match("##+(.*)$") or ""
  end
  if #shown > 60 then
    shown = shown:sub(1, 57) .. "..."
  end
  return '"' .. mask(shown):gsub("[%c]", " ") .. '"'
end

local key_names -- [api table] = { [value] = "A" }

local function key_name(api, prefix, v)
  key_names = key_names or setmetatable({}, { __mode = "k" })
  local names = key_names[api]
  if not names then
    names = {}
    for k, f in pairs(api) do
      local short = type(k) == "string" and k:match("^" .. prefix .. "Key_(.+)$")
      if short then
        local val = f
        if type(f) == "function" then
          local ok, got = pcall(f)
          val = ok and got or nil
        end
        if type(val) == "number" then
          names[val] = short
        end
      end
    end
    key_names[api] = names
  end
  return names[v] or tostring(v)
end

local MOUSE = { [0] = "left", [1] = "right", [2] = "middle" }

local function log_widget(kind, name, api, prefix, extra, a1, a2, r1, r2, r3, r4)
  if kind == "click" then
    if r1 then
      rec("UI click " .. label_of(a1))
    end
  elseif kind == "press" then
    if extra.activated and extra.activated(extra.c) then
      rec("UI press " .. label_of(a1))
    elseif extra.deactivated and extra.deactivated(extra.c) then
      rec("UI release " .. label_of(a1))
    end
  elseif kind == "select" then
    if r1 then
      rec("UI " .. (name == "MenuItem" and "menu " or "select ") .. label_of(a1))
    end
  elseif kind == "toggle" then
    if r1 then
      rec("UI checkbox " .. label_of(a1) .. " = " .. fmt_val(r2))
    end
  elseif kind == "text" then
    if r1 then
      rec("UI typing in " .. label_of(a1) .. " (" .. #tostring(r2 or "") .. " chars)", "text|" .. tostring(a1))
    end
  elseif kind == "value" then
    if r1 then
      local vals = { fmt_val(r2) }
      if r3 ~= nil then vals[#vals + 1] = fmt_val(r3) end
      if r4 ~= nil then vals[#vals + 1] = fmt_val(r4) end
      rec("UI " .. name .. " " .. label_of(a1) .. " = " .. table.concat(vals, ", "), "value|" .. name .. "|" .. tostring(a1))
    end
  elseif kind == "popup" then
    if not rec_seen("popup|" .. tostring(a1), 0.25) then
      rec("UI open popup " .. label_of(a1))
    end
  elseif kind == "drop" then
    if r1 then
      if name == "AcceptDragDropPayloadFiles" then
        rec("UI drop " .. tostring(r2 or "?") .. " file(s)")
      else
        rec("UI drop " .. (a1 and fmt_val(a1) or name:sub(22)))
      end
    end
  elseif kind == "key" then
    if r1 and not rec_seen("key|" .. tostring(a1)) then
      rec("UI key " .. key_name(api, prefix, a1))
    end
  elseif kind == "mouse" then
    if r1 and not rec_seen(name .. "|" .. tostring(a1)) then
      rec("UI mouse " .. (name == "IsMouseDoubleClicked" and "double-click " or "click ") .. (MOUSE[a1] or tostring(a1)))
    end
  end
end

local function wrap_widget(kind, name, orig, api, prefix)
  local extra = {}
  if kind == "press" then
    extra.activated = rawget(api, prefix .. "IsItemActivated")
    extra.deactivated = rawget(api, prefix .. "IsItemDeactivated")
  end
  -- Arguments and results pass through with their exact count: ReaImGui
  -- rejects extra (even nil) arguments.
  local w = function(c, ...)
    if not T.on or T.busy or c == ctx then
      return orig(c, ...)
    end
    -- busy while the original runs, so a shim function that calls a wrapped
    -- reaper.ImGui_* function isn't logged twice.
    T.busy = true
    local res = table.pack(orig(c, ...))
    extra.c = c
    local a1, a2 = ...
    pcall(log_widget, kind, name, api, prefix, extra, a1, a2, res[1], res[2], res[3], res[4])
    T.busy = false
    return table.unpack(res, 1, res.n)
  end
  T.is_wrapper[w] = true
  return w
end

-- Replace the interesting functions of one table (`reaper`, or an ImGui API
-- table where names have no "ImGui_" prefix).
local function wrap_table(tbl, is_reaper)
  if type(tbl) ~= "table" or T.originals[tbl] then
    return
  end
  local saved = {}
  local names = {}
  for k, v in pairs(tbl) do
    if type(k) == "string" and type(v) == "function" and not T.is_wrapper[v] then
      names[#names + 1] = k
    end
  end
  local prefix = is_reaper and "ImGui_" or ""
  for _, k in ipairs(names) do
    local v = rawget(tbl, k)
    local w
    if is_reaper and k:sub(1, 6) == "ImGui_" then
      local kind = widget_kind(k:sub(7))
      if kind then
        w = wrap_widget(kind, k:sub(7), v, tbl, prefix)
      end
    elseif is_reaper then
      if api_interesting(k) then
        w = wrap_api(k, v)
      end
    else
      local kind = widget_kind(k)
      if kind then
        w = wrap_widget(kind, k, v, tbl, prefix)
      end
    end
    if w then
      saved[k] = v
      rawset(tbl, k, w)
    end
  end
  T.originals[tbl] = saved
end

local function unwrap_all()
  for tbl, saved in pairs(T.originals) do
    for k, v in pairs(saved) do
      if T.is_wrapper[rawget(tbl, k)] then
        rawset(tbl, k, v)
      end
    end
  end
  T.originals = {}
end

-- --- Frames, errors and REAPER state ---

local function traceback(e)
  return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
end

-- reaper.defer, timed: slow frames are logged, errors logged with a
-- traceback and raised again so the script behaves as before.
local function wrap_defer(orig)
  local w = function(fn)
    if not T.on or type(fn) ~= "function" then
      return orig(fn)
    end
    T.host_frame_t = now_s()
    return orig(function()
      T.busy = false -- in case an error inside a wrapped call left it set
      local t0 = now_s()
      local ok, err = xpcall(fn, traceback)
      local ms = (now_s() - t0) * 1000
      T.frames = (T.frames or 0) + 1
      if ms > (T.slowest or 0) then
        T.slowest = ms
      end
      if T.on and not T.busy then
        if ms >= F.SLOW_FRAME_MS then
          rec(string.format("FRAME slow: %.0f ms", ms))
        end
        if not ok then
          rec("ERROR " .. tostring(err):gsub("\n", "\n    "))
          -- on disk now: the script is about to stop, the recorder reads the file
          rec_flush_pending()
          if T.fh then
            T.fh:flush()
          end
        end
      end
      if not ok then
        error(err, 0)
      end
    end)
  end
  T.is_wrapper[w] = true
  return w
end

local PLAY = { [0] = "stopped", [1] = "playing", [2] = "paused", [5] = "recording", [6] = "recording paused" }

local function rec_poll_state()
  local t = now_s()
  if T.pending and t - T.pending.t > 1 then
    rec_flush_pending()
  end
  if t - (T.state_t or 0) >= 0.2 then
    T.state_t = t
    if r.GetProjectStateChangeCount then
      local n = r.GetProjectStateChangeCount(0)
      if T.proj_count and n ~= T.proj_count then
        local undo = r.Undo_CanUndo2 and r.Undo_CanUndo2(0) or nil
        if undo ~= T.last_undo then
          T.last_undo = undo
          rec("REAPER undo point: " .. fmt_val(undo or ""))
        else
          rec("REAPER project changed", "projchange")
        end
      end
      T.proj_count = n
    end
    if r.GetPlayState then
      local ps = r.GetPlayState()
      if T.play ~= nil and ps ~= T.play then
        rec("REAPER transport: " .. (PLAY[ps] or tostring(ps)))
      end
      T.play = ps
    end
  end
  if t - (T.stats_t or t) >= 10 then
    rec(string.format("STATS %d frames in %.0f s, slowest %.0f ms, Lua memory %.1f MB",
      T.frames or 0, t - T.stats_t, T.slowest or 0, collectgarbage("count") / 1024))
    T.frames, T.slowest = 0, 0
    T.stats_t = t
  elseif not T.stats_t then
    T.stats_t = t
  end
  if T.fh then
    T.fh:flush()
  end
end

local function host_imgui_tables()
  local list = {}
  local h = cfg.imgui
  -- rawget: the builtin shim raises an error for missing fields.
  if type(h) == "table" and rawget(h, 1) then
    for _, t in ipairs(h) do list[#list + 1] = t end
  elseif type(h) == "table" then
    list[1] = h
  end
  -- Common globals: an ImGui table made with the builtin shim.
  for _, g in ipairs({ "ImGui", "im" }) do
    local t = rawget(_G, g)
    if type(t) == "table" and t ~= r and type(rawget(t, "Button")) == "function" then
      list[#list + 1] = t
    end
  end
  return list
end

local function host_state_lines(why)
  if not cfg.get_state then
    return
  end
  local ok, got = pcall(cfg.get_state)
  if not ok then
    rec("STATE (" .. why .. ") failed: " .. tostring(got))
    return
  end
  if type(got) == "string" then
    local t = {}
    for line in got:gmatch("[^\n]+") do t[#t + 1] = line end
    got = t
  end
  if type(got) == "table" then
    rec("STATE (" .. why .. "):")
    for _, l in ipairs(got) do
      rec("    " .. tostring(l))
    end
  end
end

local function rec_ext_key()
  return "recording_" .. safe_id(cfg.script_id)
end

local ensure_loop -- set further down

local function rec_open_file(fresh)
  local path = rec_path()
  if fresh then
    os.remove(path)
  else
    local size = file_size(path)
    if size and size > F.TRACE_FILE_KEEP * 2 then
      local tail = (read_file(path) or ""):sub(-F.TRACE_FILE_KEEP):gsub("^[^\n]*\n", "")
      write_file(path, tail)
    end
  end
  T.fh = io.open(path, "ab")
end

-- --- Recorder script (host side) ---
-- ExtState keys in section CRS_Feedback, all ending in _<script id>, none saved:
--   rec_hb   host's frame time (time_precise) while it runs and records
--   rec_ev   events recorded so far
--   rec_cmd  "stop" from the recorder; the host stops and sets rec_ack
--   rec_ack  "stopped"
--   comp_hb  the recorder's frame time while it runs
--   comp_cfg the host's Setup fields the recorder needs
--   draft_title / draft_note  what was typed before recording started

local function xkey(name)
  return name .. "_" .. safe_id(cfg.script_id)
end

local function xget(name)
  return r.GetExtState and r.GetExtState("CRS_Feedback", xkey(name)) or ""
end

local function xset(name, v)
  if r.SetExtState then
    r.SetExtState("CRS_Feedback", xkey(name), tostring(v or ""), false)
  end
end

-- True while `name` holds a time_precise stamp newer than `age` seconds.
local function xfresh(name, age)
  local t = tonumber(xget(name))
  return t ~= nil and math.abs(now_s() - t) < age
end

local CFG_KEYS = { "script_id", "script_name", "version", "repo", "repo_label", "record_hint", "private_repo" }
local FONT_KEYS = { "title", "mono", "mono_bold", "body", "body_bold" }

local function encode_cfg()
  local parts = {}
  local function add(k, v)
    if v ~= nil and v ~= "" then
      parts[#parts + 1] = k .. "=" .. tostring(v):gsub("[\r\n\31]", " ")
    end
  end
  for _, k in ipairs(CFG_KEYS) do
    add(k, cfg[k] == true and "1" or (type(cfg[k]) == "string" and cfg[k] or nil))
  end
  if type(cfg.fonts) == "table" then
    for _, k in ipairs(FONT_KEYS) do
      add("font." .. k, cfg.fonts[k])
    end
  end
  return table.concat(parts, "\31")
end

local function decode_cfg(s)
  local out, fonts = {}, {}
  for part in (tostring(s or "") .. "\31"):gmatch("([^\31]*)\31") do
    local k, v = part:match("^([^=]+)=(.*)$")
    if k then
      local fk = k:match("^font%.(.+)$")
      if fk then
        fonts[fk] = v
      elseif k == "private_repo" then
        out[k] = v == "1"
      else
        out[k] = v
      end
    end
  end
  if next(fonts) then
    out.fonts = fonts
  end
  return out
end
F._encode_cfg, F._decode_cfg = encode_cfg, decode_cfg

local function recorder_alive()
  return xfresh("comp_hb", 2)
end

-- The host's own badge is needed when the recorder isn't running (missing
-- file, an old REAPER, or it failed to start).
local function host_badge_needed()
  if recorder_alive() then
    return false
  end
  return not (T.comp_launch_t and now_s() - T.comp_launch_t < 3)
end

-- Start the recorder script (once: a running one just picks the host up again).
local function launch_recorder()
  if F.COMPANION or not MODULE_DIR or not (r.AddRemoveReaScript and r.Main_OnCommand) then
    return false
  end
  if recorder_alive() then
    return true
  end
  local path = MODULE_DIR .. "/" .. F.RECORDER_FILE
  if not file_size(path) then
    return false
  end
  xset("comp_cfg", encode_cfg())
  r.SetExtState("CRS_Feedback", "recorder_launch", cfg.script_id, false)
  local ok, cmd = pcall(r.AddRemoveReaScript, true, 0, path, true)
  if not ok or not cmd or cmd == 0 then
    return false
  end
  T.comp_launch_t = now_s()
  local ran = pcall(r.Main_OnCommand, cmd, 0)
  return ran
end

-- Each host frame while recording: tell the recorder the host is alive, and
-- do what it asks.
local function host_beat()
  xset("rec_hb", now_s())
  xset("rec_ev", T.events)
  if xget("rec_cmd") == "stop" then
    xset("rec_cmd", "")
    T.draft = nil
    F.StopRecording()
    xset("rec_ack", "stopped")
  end
end

-- Turn bug recording on. `resumed` is set when it was left on last time.
function F.StartRecording(resumed)
  if T.on then
    return
  end
  T.lines, T.next, T.count, T.events = {}, 1, 0, 0
  T.ended = nil
  if not resumed then
    T.started = os.time()
  else
    T.started = tonumber(r.GetExtState and r.GetExtState("CRS_Feedback", rec_ext_key() .. "_since") or "") or os.time()
    -- Pick up what was recorded before the restart.
    for line in (read_file(rec_path()) or ""):gmatch("[^\n]+") do
      rec_write(line)
    end
  end
  T.pending, T.recent, T.host_frame_t = nil, {}, nil
  T.proj_count, T.play, T.stats_t, T.frames, T.slowest = nil, nil, nil, 0, 0
  T.on = true
  T.stopped_unsent = false
  rec_open_file(not resumed)
  if r.SetExtState then
    r.SetExtState("CRS_Feedback", rec_ext_key(), "1", true)
    r.SetExtState("CRS_Feedback", rec_ext_key() .. "_since", tostring(T.started), true)
  end
  -- The badge and the send window run as their own script from here on.
  xset("draft_title", T.draft and T.draft.title or "")
  xset("draft_note", T.draft and T.draft.note or "")
  xset("rec_cmd", "")
  xset("rec_ack", "")
  xset("rec_ev", T.events)
  xset("rec_hb", now_s())
  local launched_ok, launched = pcall(launch_recorder)
  local env = environment()
  rec(string.format("RECORDING %s: %s %s, REAPER %s on %s, ReaImGui %s",
    resumed and "resumed after a restart" or "started", cfg.script_name, cfg.version, env.reaper, env.os, env.reaimgui))
  if not (launched_ok and launched) then
    rec("RECORDING badge shown by the script itself (recorder script not started)")
  end
  if r.Undo_CanUndo2 then
    T.last_undo = r.Undo_CanUndo2(0)
  end
  T.busy = true
  wrap_table(r, true)
  for _, t in ipairs(host_imgui_tables()) do
    wrap_table(t, false)
  end
  local d = T.originals[r] and T.originals[r].defer or rawget(r, "defer")
  if d and not T.is_wrapper[rawget(r, "defer")] then
    T.originals[r].defer = d
    rawset(r, "defer", wrap_defer(d))
  end
  T.busy = false
  host_state_lines("at start")
  if cfg.on_recording then
    pcall(cfg.on_recording, true)
  end
  F.Log("Bug recording " .. (resumed and "resumed" or "started"))
  ensure_loop()
end

-- Turn it off. The recording stays in memory (and on disk) until it is sent
-- or discarded, so "Stop and send" can attach it.
function F.StopRecording()
  if not T.on then
    return
  end
  host_state_lines("at stop")
  rec(string.format("RECORDING stopped after %s", F.RecordingDuration()))
  rec_flush_pending()
  T.on = false
  T.ended = os.time()
  T.stopped_unsent = true
  unwrap_all()
  if T.fh then
    T.fh:close()
    T.fh = nil
  end
  if r.SetExtState then
    r.SetExtState("CRS_Feedback", rec_ext_key(), "", true)
  end
  xset("rec_ev", T.events)
  if cfg.on_recording then
    pcall(cfg.on_recording, false)
  end
  F.Log("Bug recording stopped (" .. T.events .. " events)")
end

function F.DiscardRecording()
  if T.on then
    F.StopRecording()
  end
  T.lines, T.next, T.count, T.events = {}, 1, 0, 0
  T.stopped_unsent = false
  os.remove(rec_path())
  -- also when the host stopped without stopping the recording (a crash)
  if r.SetExtState then
    r.SetExtState("CRS_Feedback", rec_ext_key(), "", true)
  end
end

function F.IsRecording()
  return T.on
end

-- A recording that was stopped but not sent yet.
function F.HasRecording()
  if not (T.stopped_unsent and T.count > 0) then
    return false
  end
  -- The recorder script may have sent (and deleted) it meanwhile.
  if not F.COMPANION and not file_size(rec_path()) then
    T.stopped_unsent = false
    return false
  end
  return true
end

function F.RecordingDuration()
  local s = math.max(0, (T.ended or os.time()) - (T.started or os.time()))
  if s >= 3600 then
    return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
  end
  return string.format("%d:%02d", s // 60, s % 60)
end

function F.RecordingEvents()
  return T.events
end

-- Hosts can add their own detail; it costs nothing while recording is off.
function F.Trace(msg, key)
  if T.on then
    T.busy = true
    pcall(rec, "HOST " .. tostring(msg):gsub("[\r\n]+", " | "), key and ("host|" .. tostring(key)) or nil)
    T.busy = false
  end
end

-- The recording as text lines, newest last, at most F.TRACE_SEND_BYTES.
local function recording_lines()
  rec_flush_pending()
  local all = {}
  local start = (T.count < F.TRACE_MAX_LINES) and 1 or T.next
  for i = 0, T.count - 1 do
    all[#all + 1] = T.lines[((start - 1 + i) % F.TRACE_MAX_LINES) + 1]
  end
  if #all == 0 then
    local data = read_file(rec_path()) or ""
    for line in data:gmatch("[^\n]+") do
      all[#all + 1] = line
    end
  end
  local size, first = 0, #all + 1
  for i = #all, 1, -1 do
    size = size + #all[i] + 1
    if size > F.TRACE_SEND_BYTES then
      break
    end
    first = i
  end
  local out = {}
  if first > 1 then
    out[1] = "(" .. (first - 1) .. " older lines left out)"
  end
  for i = first, #all do
    out[#out + 1] = all[i]
  end
  return out
end
F._recording_lines = recording_lines

-- The exact log text a report would include (already scrubbed).
-- opts.usage (default true): the usage log; opts.trace: the bug recording.
function F.BuildLogText(opts)
  opts = opts or {}
  local env = environment()
  local lines = {
    string.format("%s %s", cfg.script_name, cfg.version),
    string.format("REAPER %s on %s, ReaImGui %s, JS API %s, SWS %s",
      env.reaper, env.os, env.reaimgui, env.js_api and "yes" or "no", env.sws and "yes" or "no"),
    "",
  }
  local extra = {}
  if opts.usage == false then
    lines[#lines + 1] = "(usage log not included)"
  elseif cfg.get_log then
    local ok, got = pcall(cfg.get_log)
    if ok and type(got) == "table" then
      extra = got
    elseif ok and type(got) == "string" then
      for line in got:gmatch("[^\n]+") do
        extra[#extra + 1] = line
      end
    end
  end
  local ring = opts.usage == false and {} or ring_lines()
  if #ring == 0 and opts.usage ~= false then
    ring = file_log_tail(150)
    if #ring > 0 then
      lines[#lines + 1] = "-- Usage log (last session) --"
    end
  elseif #ring > 0 then
    lines[#lines + 1] = "-- Usage log --"
  end
  for _, l in ipairs(ring) do
    lines[#lines + 1] = l
  end
  if #extra > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "-- " .. cfg.script_name .. " log --"
    local first = math.max(1, #extra - F.MAX_LOG_LINES + 1)
    for i = first, #extra do
      lines[#lines + 1] = tostring(extra[i])
    end
  end
  if #ring == 0 and #extra == 0 and opts.usage ~= false then
    lines[#lines + 1] = "(no log lines yet)"
  end
  if opts.trace then
    local rl = recording_lines()
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("-- Bug recording (%d events, %s) --", T.events, F.RecordingDuration())
    for _, l in ipairs(rl) do
      lines[#lines + 1] = l
    end
  end
  return F.ScrubPaths(table.concat(lines, "\n"))
end

-- --- Background jobs (curl, screenshots) --------------------------------------
-- Each command runs from a small sh/batch file started without waiting; it
-- writes its exit code to <base>.rc, which the window polls on later frames.

local job_counter = 0

local function sh_quote(s)
  s = tostring(s or "")
  if is_windows() then
    return '"' .. s:gsub('"', ""):gsub("%%", "%%%%") .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function win_path(s)
  return '"' .. tostring(s or ""):gsub("/", "\\"):gsub("%%", "%%%%") .. '"'
end

local function job_base(prefix)
  job_counter = job_counter + 1
  if r.RecursiveCreateDirectory then
    r.RecursiveCreateDirectory(data_dir() .. "/tmp", 0)
  end
  return string.format("%s/tmp/%s_%d_%d_%d", data_dir(), prefix, os.time(), job_counter, math.random(1000, 9999))
end

local function bg_start(cmd, timeout_s, prefix)
  if not r.ExecProcess then
    return nil, "This REAPER version can't run background commands."
  end
  local base = job_base(prefix or "job")
  local job = { base = base, rc_path = base .. ".rc", started = now_s(), timeout = timeout_s or 60 }
  local body, launch, mode
  if is_windows() then
    job.script_path = base .. ".bat"
    body = table.concat({
      "@echo off",
      "chcp 65001 >nul",
      cmd,
      "(echo %ERRORLEVEL%)> " .. win_path(job.rc_path .. ".tmp"),
      "move /Y " .. win_path(job.rc_path .. ".tmp") .. " " .. win_path(job.rc_path) .. " >nul",
      "",
    }, "\r\n")
    launch = 'cmd.exe /C ""' .. job.script_path:gsub("/", "\\") .. '""'
    mode = -2
  else
    job.script_path = base .. ".sh"
    body = table.concat({
      cmd,
      "echo $? > " .. sh_quote(job.rc_path .. ".tmp"),
      "mv -f " .. sh_quote(job.rc_path .. ".tmp") .. " " .. sh_quote(job.rc_path),
      "",
    }, "\n")
    launch = '/bin/sh "' .. job.script_path .. '"'
    mode = -1
  end
  if not write_file(job.script_path, body) then
    return nil, "Couldn't write a temp file in " .. F.ScrubPaths(data_dir())
  end
  local ok = pcall(r.ExecProcess, launch, mode)
  if not ok then
    os.remove(job.script_path)
    return nil, "Couldn't start a background process."
  end
  return job
end

-- Returns "running" | "done", exit_code | "timeout".
local function bg_poll(job)
  local data = read_file(job.rc_path)
  if data then
    os.remove(job.rc_path)
    os.remove(job.script_path)
    return "done", tonumber(data:match("%-?%d+")) or -1
  end
  if now_s() - job.started > job.timeout then
    os.remove(job.script_path)
    return "timeout"
  end
  return "running"
end

local function open_url(url)
  if r.CF_ShellExecute then
    r.CF_ShellExecute(url)
  elseif is_windows() then
    r.ExecProcess('cmd.exe /C start "" "' .. url .. '"', -2)
  elseif is_mac() then
    r.ExecProcess('/usr/bin/open "' .. url .. '"', -1)
  else
    r.ExecProcess('xdg-open "' .. url .. '"', -1)
  end
end
F._open_url = open_url

-- --- Window state ------------------------------------------------------------

local S -- window state; nil while closed
local report_kind -- set further down

local function new_state(opts)
  opts = opts or {}
  return {
    kind = opts.kind, -- sent as "bug" when a recording is attached, else this or "other"
    title = opts.title or "",
    note = opts.note or "",
    contact = r.GetExtState and r.GetExtState("CRS_Feedback", "contact") or "",
    include_log = opts.include_log ~= false,
    include_trace = opts.include_trace ~= false,
    viewer = nil, -- { kind = "trace"|"sent", text, lines }: the separate viewer window
    images = {}, -- { path, name, bytes, img }
    status = nil, -- { kind = "info"|"error"|"ok", text }
    phase = "edit", -- edit | sending | sent
    focus_title = true,
  }
end

local function set_status(kind, text)
  S.status = { kind = kind, text = text }
end

local IMAGE_EXT = { png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif", webp = "image/webp" }

local function add_image(path)
  if #S.images >= F.MAX_IMAGES then
    set_status("error", "You can attach up to " .. F.MAX_IMAGES .. " pictures.")
    return false
  end
  local ext = tostring(path):match("%.([%w]+)$")
  ext = ext and ext:lower()
  if not IMAGE_EXT[ext] then
    set_status("error", "Pictures must be PNG, JPG, GIF or WebP.")
    return false
  end
  local bytes = file_size(path)
  if not bytes or bytes == 0 then
    set_status("error", "Couldn't read that picture.")
    return false
  end
  if bytes > F.MAX_IMAGE_BYTES then
    set_status("error", string.format("That picture is %.1f MB; the limit is %d MB.",
      bytes / 1048576, F.MAX_IMAGE_BYTES // 1048576))
    return false
  end
  for _, im in ipairs(S.images) do
    if im.path == path then
      return false
    end
  end
  local entry = { path = path, name = path:match("([^/\\]+)$") or path, bytes = bytes, ext = ext }
  if ImGui and ImGui.CreateImage then
    local ok, img = pcall(ImGui.CreateImage, path)
    if ok and img then
      entry.img = img
      if ImGui.Attach then
        pcall(ImGui.Attach, ctx, img)
      end
    end
  end
  S.images[#S.images + 1] = entry
  S.status = nil
  return true
end
F._add_image = function(path) return add_image(path) end

local function remove_image(i)
  local im = table.remove(S.images, i)
  if im and im.img and ImGui.Detach then
    pcall(ImGui.Detach, ctx, im.img)
  end
  if im and im.temp then
    os.remove(im.path)
  end
end

local function browse_images()
  if r.JS_Dialog_BrowseForOpenFiles then
    local rv, files = r.JS_Dialog_BrowseForOpenFiles("Add pictures", "", "",
      "Pictures\0*.png;*.jpg;*.jpeg;*.gif;*.webp\0\0", true)
    if rv == 1 and files and files ~= "" then
      local parts = {}
      for p in (files .. "\0"):gmatch("([^\0]*)\0") do
        if p ~= "" then
          parts[#parts + 1] = p
        end
      end
      if #parts == 1 then
        add_image(parts[1])
      else
        local dir = parts[1]
        for i = 2, #parts do
          add_image(dir .. (is_windows() and "\\" or "/") .. parts[i])
        end
      end
    end
  elseif r.GetUserFileNameForRead then
    local ok, path = r.GetUserFileNameForRead("", "Add a picture", "png")
    if ok and path ~= "" then
      add_image(path)
    end
  end
end

-- Screenshot: macOS lets the user drag a region; Windows grabs every screen.
-- The window moves off-screen while the shot is taken.
local function start_screenshot()
  local out = job_base("shot") .. ".png"
  local cmd
  if is_mac() then
    cmd = "/usr/sbin/screencapture -i -x " .. sh_quote(out)
  elseif is_windows() then
    local ps = "Add-Type -AssemblyName System.Windows.Forms,System.Drawing;"
      .. "$b=[System.Windows.Forms.SystemInformation]::VirtualScreen;"
      .. "$m=New-Object System.Drawing.Bitmap $b.Width,$b.Height;"
      .. "$g=[System.Drawing.Graphics]::FromImage($m);"
      .. "$g.CopyFromScreen($b.Left,$b.Top,0,0,$m.Size);"
      .. "$m.Save('" .. out:gsub("/", "\\"):gsub("'", "''") .. "',[System.Drawing.Imaging.ImageFormat]::Png)"
    cmd = 'powershell -NoProfile -WindowStyle Hidden -Command "' .. ps:gsub("%%", "%%%%") .. '"'
  else
    set_status("error", "Screenshots aren't supported here; add a picture file instead.")
    return
  end
  S.shot = { out = out, cmd = cmd, start_at = now_s() + 0.35 }
end

local function poll_screenshot()
  local shot = S.shot
  if not shot then
    return
  end
  if not shot.job then
    if now_s() >= shot.start_at then
      local job, err = bg_start(shot.cmd, 120, "shot")
      if not job then
        S.shot = nil
        set_status("error", err)
        return
      end
      shot.job = job
    end
    return
  end
  local st = bg_poll(shot.job)
  if st == "running" then
    return
  end
  S.shot = nil
  if file_size(shot.out) and file_size(shot.out) > 0 then
    if add_image(shot.out) then
      S.images[#S.images].name = "Screenshot " .. #S.images .. ".png"
      S.images[#S.images].temp = true
    end
  elseif is_mac() then
    set_status("info", "No screenshot taken. If nothing happened, allow REAPER under System Settings > Privacy & Security > Screen Recording.")
  else
    set_status("error", "The screenshot didn't work; add a picture file instead.")
  end
end

-- --- Sending -----------------------------------------------------------------

local function endpoint()
  local o = r.GetExtState and r.GetExtState("CRS_Feedback", "endpoint") or ""
  if o ~= "" then
    return o
  end
  return F.ENDPOINT
end

local function endpoint_ready()
  return not endpoint():find("REPLACE%-ME")
end

local function copy_binary(src, dst)
  local data = read_file(src)
  return data and write_file(dst, data)
end

-- The report as plain text, for "Copy report" when sending fails.
local function report_as_text()
  local env = environment()
  local t = {
    string.format("[%s] %s", report_kind(), trim(S.title)),
    string.format("%s %s - REAPER %s - %s", cfg.script_name, cfg.version, env.reaper, env.os),
    "",
    trim(S.note),
  }
  if trim(S.contact) ~= "" then
    t[#t + 1] = ""
    t[#t + 1] = "Contact: " .. trim(S.contact)
  end
  local trace = S.include_trace and (T.on or F.HasRecording())
  if S.include_log or trace then
    t[#t + 1] = ""
    t[#t + 1] = F.BuildLogText({ usage = S.include_log, trace = trace })
  end
  return table.concat(t, "\n")
end

-- Validate the form; returns the payload table or nil + message.
function F._build_payload(state)
  state = state or S
  local title = trim(state.title)
  local note = trim(state.note)
  if #title < 3 then
    return nil, "Add a short title."
  end
  if #note < 5 then
    return nil, "Add a few words about what happened."
  end
  if #note > F.MAX_NOTE_CHARS then
    return nil, "The note is too long (" .. #note .. " characters, limit " .. F.MAX_NOTE_CHARS .. ")."
  end
  local trace = state.include_trace and F.HasRecording() or false
  local images = {}
  for i, im in ipairs(state.images) do
    images[i] = { field = "image" .. i, name = F.ScrubPaths(im.name):match("([^/\\]+)$") }
  end
  return {
    v = 1,
    script_id = cfg.script_id,
    script_name = cfg.script_name,
    script_version = tostring(cfg.version),
    kind = state.kind,
    title = title,
    note = note,
    contact = trim(state.contact),
    log = (state.include_log or trace) and F.BuildLogText({ usage = state.include_log, trace = trace }) or "",
    env = environment(),
    images = images,
  }
end

local function start_send()
  if T.on and S.include_trace then
    F.StopRecording()
  end
  S.kind = report_kind()
  local payload, err = F._build_payload(S)
  if not payload then
    set_status("error", err)
    return
  end
  if not endpoint_ready() then
    set_status("error", "Reporting isn't set up in this version yet. Use \"Copy report\" and send it to the developer.")
    return
  end
  local base = job_base("send")
  local payload_path = base .. "_payload.json"
  if not write_file(payload_path, json_encode(payload)) then
    set_status("error", "Couldn't write the report to a temp file.")
    return
  end
  local temps = { payload_path }
  local parts = {
    sh_quote(is_windows() and "curl" or "/usr/bin/curl"),
    "-sS", "--connect-timeout", "10", "--max-time", "120",
    "-H", sh_quote("X-CRS-Feedback: 1"),
    "-F", sh_quote("payload=<" .. payload_path .. ";type=application/json"),
  }
  for i, im in ipairs(S.images) do
    -- Copy to a plain name: curl's -F treats ; and , in file names specially,
    -- and the original file name may contain personal details.
    local tmp = string.format("%s_img%d.%s", base, i, im.ext)
    if not copy_binary(im.path, tmp) then
      for _, p in ipairs(temps) do os.remove(p) end
      set_status("error", "Couldn't read picture " .. i .. ".")
      return
    end
    temps[#temps + 1] = tmp
    parts[#parts + 1] = "-F"
    parts[#parts + 1] = sh_quote(string.format("image%d=@%s;type=%s", i, tmp, IMAGE_EXT[im.ext]))
  end
  local resp_path, code_path = base .. "_resp.json", base .. "_code.txt"
  parts[#parts + 1] = "-o"
  parts[#parts + 1] = sh_quote(resp_path)
  parts[#parts + 1] = "-w"
  parts[#parts + 1] = sh_quote("%{http_code}")
  parts[#parts + 1] = sh_quote(endpoint())
  local cmd = table.concat(parts, " ") .. " >" .. sh_quote(code_path) .. (is_windows() and " 2>nul" or " 2>/dev/null")
  local job, jerr = bg_start(cmd, 135, "send")
  if not job then
    for _, p in ipairs(temps) do os.remove(p) end
    set_status("error", jerr)
    return
  end
  temps[#temps + 1] = resp_path
  temps[#temps + 1] = code_path
  S.send = { job = job, resp_path = resp_path, code_path = code_path, temps = temps,
    with_trace = S.include_trace and F.HasRecording() }
  S.phase = "sending"
  set_status("info", "Sending...")
  if r.SetExtState then
    r.SetExtState("CRS_Feedback", "contact", trim(S.contact), true)
  end
end

-- Interpret a finished upload; exposed for tests.
function F._parse_reply(rc, http_code, body)
  http_code = tonumber(http_code) or 0
  if rc ~= 0 and http_code == 0 then
    return nil, "Couldn't reach the report server (curl error " .. tostring(rc) .. "). Check your internet connection and try again."
  end
  if http_code >= 200 and http_code < 300 then
    local url = json_field(body, "url")
    local number = json_field(body, "number")
    if url then
      return { url = url, number = tonumber(number) }
    end
    return nil, "The server answered, but without a report link."
  end
  local msg = json_field(body, "error")
  if http_code == 429 then
    return nil, msg or "Too many reports from this computer. Please try again later."
  end
  return nil, (msg or "The report server returned an error") .. " (HTTP " .. http_code .. ")."
end

local function poll_send()
  local send = S.send
  if not send then
    return
  end
  local st, rc = bg_poll(send.job)
  if st == "running" then
    return
  end
  local code = read_file(send.code_path) or ""
  local body = read_file(send.resp_path) or ""
  for _, p in ipairs(send.temps) do
    os.remove(p)
  end
  S.send = nil
  if st == "timeout" then
    S.phase = "edit"
    set_status("error", "Sending took too long. Check your connection and try again.")
    return
  end
  local result, err = F._parse_reply(rc, code:match("%d+"), body)
  if result and send.with_trace then
    F.DiscardRecording()
  end
  if result then
    S.phase = "sent"
    S.result = result
    F.Log("Feedback sent" .. (result.number and (" as #" .. result.number) or ""))
  else
    S.phase = "edit"
    set_status("error", err)
  end
end

-- --- ImGui -------------------------------------------------------------------

-- Use the versioned API shim when present (ReaImGui 0.9+), otherwise the raw
-- reaper.ImGui_* functions (constants are functions there, so call them once).
local function load_imgui()
  if ImGui then
    return ImGui
  end
  local builtin = r.ImGui_GetBuiltinPath and r.ImGui_GetBuiltinPath()
  if builtin then
    local saved = package.path
    package.path = builtin .. "/?.lua;" .. package.path
    local ok, mod = pcall(require, "imgui")
    package.path = saved
    if ok and type(mod) == "function" then
      local ok2, api = pcall(mod, "0.9")
      if ok2 and api then
        ImGui = api
        return ImGui
      end
    end
  end
  ImGui = setmetatable({}, {
    __index = function(t, k)
      local v = r["ImGui_" .. k]
      local is_const = k:match("^%a*Flags_") or k:match("^Col_") or k:match("^StyleVar_") or k:match("^Cond_")
      if type(v) == "function" and is_const then
        v = v()
      end
      rawset(t, k, v)
      return v
    end,
  })
  return ImGui
end

-- ImGui field that may not exist in this ReaImGui version (the builtin shim
-- raises an error for unknown names).
local function im_opt(name)
  local ok, v = pcall(function() return ImGui[name] end)
  return ok and v or nil
end

-- --- Look: "Monolith" --------------------------------------------------------
-- Black, faint column guides, display caps, letter-spaced mono labels, square
-- controls, one green accent (red for bug recording). Drawn on the draw list
-- over invisible buttons; text boxes are ImGui widgets styled to match.

local P = {
  page = 0x000000FF,
  card = 0x0A0A0AFF,
  acc = 0x49CC85FF,
  acc_hi = 0x5FDA97FF,
  ink = 0xF2F2F2FF,
  ink2 = 0x9A9A9AFF,
  ink3 = 0x5F5F5FFF,
  line = 0xFFFFFF1F,
  line2 = 0xFFFFFF33,
  soft = 0xFFFFFF12,
  guide = 0xFFFFFF0B,
  amber = 0xF6C344FF,
  red = 0xEF5A5AFF,
  red_hi = 0xFF7A7AFF,
}
local COL = { error = P.red, ok = P.acc, mute = P.ink2, rec = P.red }

local function A(c, a)
  return (c & 0xFFFFFF00) | (math.floor(a) & 0xFF)
end

local function mix(a, b, t)
  local function m(s)
    local ca, cb = (a >> s) & 0xFF, (b >> s) & 0xFF
    return math.floor(ca + (cb - ca) * t + 0.5)
  end
  return (m(24) << 24) | (m(16) << 16) | (m(8) << 8) | m(0)
end

-- Smooth 0..1 pulse for the recording dot.
local function pulse()
  return 0.5 + 0.5 * math.sin(now_s() * 4.2)
end

-- Fonts live in the module's own context. Setup's `fonts` may name font files
-- ({ title = Anton, mono = JetBrains Mono, mono_bold, body, body_bold });
-- anything missing or unreadable falls back to a system family.
local FONT_SPECS = {
  title18 = { "title", 18 }, title22 = { "title", 22 }, title30 = { "title", 30 },
  mono10 = { "mono", 10 }, mono11 = { "mono", 11 }, monoB10 = { "mono_bold", 10 }, monoB11 = { "mono_bold", 11 },
  body13 = { "body", 13 }, bold13 = { "body_bold", 13 },
}
local FONT_FALLBACK = {
  title = { "sans-serif", true }, mono = { "monospace" }, mono_bold = { "monospace", true },
  body = { "sans-serif" }, body_bold = { "sans-serif", true },
}
local FONT_FILE_FALLBACK = { mono_bold = "mono", body_bold = "body" }
local FONTS = {}
local char_w_cache = {}

local function load_fonts()
  FONTS, char_w_cache = {}, {}
  local create, attach = im_opt("CreateFont"), im_opt("Attach")
  if not create or not attach then
    return
  end
  local files = type(cfg.fonts) == "table" and cfg.fonts or {}
  local bold = im_opt("FontFlags_Bold")
  for key, spec in pairs(FONT_SPECS) do
    local role, size = spec[1], spec[2]
    local file = files[role] or files[FONT_FILE_FALLBACK[role] or ""]
    local ok, f = false, nil
    if type(file) == "string" and file_size(file) then
      ok, f = pcall(create, file, size)
    end
    if not ok or not f then
      local fb = FONT_FALLBACK[role]
      if fb[2] and bold then
        ok, f = pcall(create, fb[1], size, bold)
      else
        ok, f = pcall(create, fb[1], size)
      end
    end
    if ok and f and pcall(attach, ctx, f) then
      FONTS[key] = f
    end
  end
end

local function text_w(s, f)
  if f then ImGui.PushFont(ctx, f) end
  local w = ImGui.CalcTextSize(ctx, s)
  if f then ImGui.PopFont(ctx) end
  return w or 0
end

local function txt(dl, f, size, x, y, c, s)
  if f then
    ImGui.DrawList_AddTextEx(dl, f, size, x, y, c, s)
  else
    ImGui.DrawList_AddText(dl, x, y, c, s)
  end
end

local function char_w(f, ch)
  local k = f or "default"
  local t = char_w_cache[k]
  if not t then
    t = {}
    char_w_cache[k] = t
  end
  local w = t[ch]
  if not w then
    w = text_w(ch, f)
    t[ch] = w
  end
  return w
end

-- Letter-spaced mono caps (the site's labels).
local function caps_w(size, s, bold)
  local f = FONTS[(bold and "monoB" or "mono") .. size]
  local w, n = 0, 0
  for _, cp in utf8.codes(tostring(s):upper()) do
    w = w + char_w(f, utf8.char(cp))
    n = n + 1
  end
  return w + math.max(0, n - 1) * size * 0.12
end

local function caps(dl, size, x, y, c, s, bold)
  local f = FONTS[(bold and "monoB" or "mono") .. size]
  for _, cp in utf8.codes(tostring(s):upper()) do
    local ch = utf8.char(cp)
    txt(dl, f, size, x, y, c, ch)
    x = x + char_w(f, ch) + size * 0.12
  end
  return x
end

-- Display caps with a chrome sheen, painted in vertical bands.
local CHROME = { { 0, 0x6B6B6BFF }, { .22, 0xF5F5F5FF }, { .38, 0x8A8A8AFF }, { .52, 0xFFFFFFFF }, { .70, 0x707070FF }, { 1, 0xE8E8E8FF } }
local function chrome_at(t)
  for i = 2, #CHROME do
    local a, b = CHROME[i - 1], CHROME[i]
    if t <= b[1] then
      return mix(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
    end
  end
  return CHROME[#CHROME][2]
end

local function chrome_text(dl, f, size, x, y, s)
  local w = text_w(s, f)
  local bands = 28
  local bw = w / bands
  for i = 0, bands - 1 do
    ImGui.DrawList_PushClipRect(dl, x + i * bw, y - 2, x + (i + 1) * bw + 0.5, y + size * 1.5, true)
    txt(dl, f, size, x, y, chrome_at((i + 0.5) / bands), s)
    ImGui.DrawList_PopClipRect(dl)
  end
  return w
end

-- Split s into lines no wider than w (words are never broken).
local function wrap(s, f, w)
  local lines = {}
  for para in (tostring(s) .. "\n"):gmatch("([^\n]*)\n") do
    local cur = ""
    for word in para:gmatch("%S+") do
      local cand = cur == "" and word or (cur .. " " .. word)
      if cur ~= "" and text_w(cand, f) > w then
        lines[#lines + 1] = cur
        cur = word
      else
        cur = cand
      end
    end
    lines[#lines + 1] = cur
  end
  return lines
end

-- Wrapped body text; returns the y under it.
local function para(dl, x, y, w, s, c, f, line_h)
  f = f or FONTS.body13
  line_h = line_h or 18
  for _, l in ipairs(wrap(s, f, w)) do
    txt(dl, f, 13, x, y, c or P.ink2, l)
    y = y + line_h
  end
  return y
end

-- Wrapped mono note (amber in the settings window); returns the y under it.
local function note(dl, x, y, w, s, c)
  local f = FONTS.mono10
  for _, l in ipairs(wrap(s, f, w)) do
    txt(dl, f, 10, x, y, c or P.amber, l)
    y = y + 15
  end
  return y
end

local function hand()
  local set, cur = im_opt("SetMouseCursor"), im_opt("MouseCursor_Hand")
  if set and cur then
    set(ctx, cur)
  end
end

-- Reserve w x h at x, y as an invisible button.
local function hit(id, x, y, w, h)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, math.max(1, w), math.max(1, h))
  local hov, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hov then
    hand()
  end
  return clicked, hov, held
end

local function tip(text)
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, text)
  end
end

-- --- Controls (all square) ---

local BTN_H = 30

local function btn_w(label)
  return caps_w(10, label, true) + 32
end

-- kind "go" = white fill (green on hover), otherwise a ghost button.
local function btn(id, label, x, y, kind, w, disabled)
  local dl = ImGui.GetWindowDrawList(ctx)
  w = w or btn_w(label)
  local clicked, hov, held = hit(id, x, y, w, BTN_H)
  if disabled then
    clicked, hov, held = false, false, false
  end
  local tc
  if kind == "go" then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + BTN_H, disabled and 0xFFFFFF59 or ((hov or held) and P.acc or 0xFFFFFFFF))
    tc = 0x000000FF
  else
    if held then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + BTN_H, 0xFFFFFF14)
    end
    ImGui.DrawList_AddRect(dl, x, y, x + w, y + BTN_H, hov and 0xFFFFFF80 or P.line2)
    tc = disabled and P.ink3 or P.ink
  end
  caps(dl, 10, x + (w - caps_w(10, label, true)) / 2, y + (BTN_H - 10) / 2 - 1 + (held and 1 or 0), tc, label, true)
  return clicked
end

-- The big red "start bug recording" button.
local REC_H = 46
local function rec_button(id, label, x, y, w)
  local dl = ImGui.GetWindowDrawList(ctx)
  local clicked, hov, held = hit(id, x, y, w, REC_H)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + REC_H, A(P.red, held and 0x5A or (hov and 0x3C or 0x24)))
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + REC_H, hov and P.red_hi or A(P.red, 0xB0))
  local cx, cy = x + 24, y + REC_H / 2
  ImGui.DrawList_AddCircle(dl, cx, cy, 10, A(P.red, hov and 0x90 or 0x50), 0, 1)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, 6, hov and P.red_hi or P.red)
  caps(dl, 11, x + 46, y + (REC_H - 11) / 2 - 1 + (held and 1 or 0), P.ink, label, true)
  return clicked
end

local SWITCH_W, SWITCH_H = 40, 20
local function switch(id, x, y, on)
  local dl = ImGui.GetWindowDrawList(ctx)
  local clicked, hov = hit(id, x, y, SWITCH_W, SWITCH_H)
  if on then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + SWITCH_W, y + SWITCH_H, hov and P.acc_hi or P.acc)
    ImGui.DrawList_AddRectFilled(dl, x + SWITCH_W - 17, y + 3, x + SWITCH_W - 3, y + SWITCH_H - 3, 0x000000FF)
  else
    ImGui.DrawList_AddRect(dl, x, y, x + SWITCH_W, y + SWITCH_H, hov and 0xFFFFFF66 or P.line2)
    ImGui.DrawList_AddRectFilled(dl, x + 3, y + 3, x + 17, y + SWITCH_H - 3, hov and P.ink2 or P.ink3)
  end
  if clicked then
    return not on, true
  end
  return on, false
end

-- A switch with a label and a one-line explanation; returns new value, changed, bottom y.
local function switch_row(id, x, y, w, on, label, desc)
  local dl = ImGui.GetWindowDrawList(ctx)
  local v, changed = switch(id, x, y, on)
  local tx = x + SWITCH_W + 14
  txt(dl, FONTS.bold13, 13, tx, y + 1, P.ink, label)
  local by = y + 22
  if desc then
    by = para(dl, tx, by, w - (tx - x), desc, P.ink2, nil, 17)
  end
  return v, changed, math.max(by, y + SWITCH_H)
end

-- Text boxes: black, square, a thin border.
local function push_input_style()
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, P.page)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, P.page)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, P.page)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, P.line2)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
  if FONTS.body13 then ImGui.PushFont(ctx, FONTS.body13) end
end

local function pop_input_style()
  if FONTS.body13 then ImGui.PopFont(ctx) end
  ImGui.PopStyleVar(ctx, 2)
  ImGui.PopStyleColor(ctx, 4)
end

-- Field label in mono caps; returns the y under it.
local function field_label(dl, x, y, s)
  caps(dl, 10, x, y, P.ink2, s)
  return y + 20
end

local function item_bottom()
  local _, b = ImGui.GetItemRectMax(ctx)
  return b
end

-- --- Cards ---
-- "01  CAPTION" kicker, then a card whose background is drawn with last
-- frame's height (the content decides it), with corner ticks.

local CARD_PAD_X, CARD_PAD_Y = 18, 16
local card_h = {}

local function card(id, x, y, w, n, caption, accent, body)
  local dl = ImGui.GetWindowDrawList(ctx)
  accent = accent or P.acc
  local num = string.format("%02d", n)
  txt(dl, FONTS.title18, 18, x, y, accent, num)
  caps(dl, 10, x + text_w(num, FONTS.title18) + 10, y + 5, P.ink2, caption)
  local cy = y + 30
  local h = card_h[id]
  if h then
    ImGui.DrawList_AddRectFilled(dl, x, cy, x + w, cy + h, P.card)
    ImGui.DrawList_AddRect(dl, x, cy, x + w, cy + h, P.line)
    local t = 6
    for _, c in ipairs({ { x, cy, 1, 1 }, { x + w, cy, -1, 1 }, { x, cy + h, 1, -1 }, { x + w, cy + h, -1, -1 } }) do
      ImGui.DrawList_AddLine(dl, c[1], c[2], c[1] + t * c[3], c[2], accent, 1)
      ImGui.DrawList_AddLine(dl, c[1], c[2], c[1], c[2] + t * c[4], accent, 1)
    end
  end
  local bottom = body(dl, x + CARD_PAD_X, cy + CARD_PAD_Y, w - CARD_PAD_X * 2)
  card_h[id] = bottom + CARD_PAD_Y - cy
  return cy + card_h[id]
end

-- --- Window parts ---

local function kind_hint()
  return "What you did and what happened, or the idea you'd like to see."
end

local function fmt_bytes(n)
  if n >= 1048576 then
    return string.format("%.1f MB", n / 1048576)
  end
  return string.format("%d KB", math.max(1, math.floor(n / 1024 + 0.5)))
end

local THUMB = 58

local function draw_pictures(dl, x, y, w)
  local box_h = THUMB + 16
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, P.page)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, P.line2)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, 1)
  if ImGui.BeginChild(ctx, "##pictures", w, box_h, im_opt("ChildFlags_Border") or 1) then
    local cdl = ImGui.GetWindowDrawList(ctx)
    local px, py = ImGui.GetCursorScreenPos(ctx)
    local remove_at
    for i, img in ipairs(S.images) do
      local ix = px + (i - 1) * (THUMB + 8)
      ImGui.SetCursorScreenPos(ctx, ix, py)
      local drew = false
      if img.img and im_opt("Image") then
        local ok, iw, ih = pcall(ImGui.Image_GetSize, img.img)
        if ok and iw and iw > 0 and ih > 0 then
          local s = math.min(THUMB / iw, THUMB / ih)
          ImGui.SetCursorScreenPos(ctx, ix + (THUMB - iw * s) / 2, py + (THUMB - ih * s) / 2)
          drew = pcall(ImGui.Image, ctx, img.img, iw * s, ih * s)
        end
      end
      ImGui.SetCursorScreenPos(ctx, ix, py)
      local clicked, hov = hit("##thumb" .. i, ix, py, THUMB, THUMB)
      ImGui.DrawList_AddRect(cdl, ix, py, ix + THUMB, py + THUMB, hov and 0xFFFFFF80 or P.line2)
      if not drew then
        caps(cdl, 10, ix + (THUMB - caps_w(10, img.ext)) / 2, py + THUMB / 2 - 7, P.ink2, img.ext)
      end
      if hov then
        ImGui.DrawList_AddRectFilled(cdl, ix, py, ix + THUMB, py + THUMB, 0x000000AA)
        local c, k = P.ink, 6
        ImGui.DrawList_AddLine(cdl, ix + THUMB / 2 - k, py + THUMB / 2 - k, ix + THUMB / 2 + k, py + THUMB / 2 + k, c, 1.5)
        ImGui.DrawList_AddLine(cdl, ix + THUMB / 2 + k, py + THUMB / 2 - k, ix + THUMB / 2 - k, py + THUMB / 2 + k, c, 1.5)
        ImGui.SetTooltip(ctx, F.ScrubPaths(img.name) .. "  (" .. fmt_bytes(img.bytes) .. ")\nClick to remove")
      end
      if clicked then
        remove_at = i
      end
    end
    if #S.images == 0 then
      local s = "Drop pictures here, or use the buttons below"
      caps(cdl, 10, px + (w - 16 - caps_w(10, s)) / 2, py + THUMB / 2 - 7, P.ink3, s)
      ImGui.SetCursorScreenPos(ctx, px, py)
      ImGui.Dummy(ctx, 1, THUMB)
    end
    ImGui.EndChild(ctx)
    if remove_at then
      remove_image(remove_at)
    end
  end
  ImGui.PopStyleVar(ctx, 2)
  ImGui.PopStyleColor(ctx, 2)
  -- Accept files dragged from Finder/Explorer onto the picture area.
  if im_opt("BeginDragDropTarget") and ImGui.BeginDragDropTarget(ctx) then
    local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
    if rv then
      for i = 0, (count or 0) - 1 do
        local ok, path = ImGui.GetDragDropPayloadFile(ctx, i)
        if ok and path then
          add_image(path)
        end
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end
  y = y + box_h + 10
  local full = #S.images >= F.MAX_IMAGES
  local bx = x
  if btn("##addpic", "Add picture", bx, y, nil, nil, full) then
    browse_images()
  end
  bx = bx + btn_w("Add picture") + 8
  if is_mac() or is_windows() then
    local label = S.shot and "Taking screenshot..." or "Take screenshot"
    if btn("##shot", label, bx, y, nil, nil, full or S.shot ~= nil) then
      start_screenshot()
    end
  end
  return y + BTN_H
end

local function draw_status(dl, x, y, w)
  if not S.status then
    return y
  end
  local c = S.status.kind == "error" and COL.error or (S.status.kind == "ok" and COL.ok or COL.mute)
  return para(dl, x, y, w, S.status.text, c) + 4
end

-- How stopping is described in the steps; hosts can add where else it's found.
local function stop_hint()
  return "Press Stop and send on the recording badge" .. (cfg.record_hint and (" " .. cfg.record_hint) or "") .. "."
end

-- Window styles shared by the feedback window and the recording badge.
local function push_style()
  local n_col, n_var = 0, 0
  local function col(id, v)
    if id then
      ImGui.PushStyleColor(ctx, id, v)
      n_col = n_col + 1
    end
  end
  local function var(id, a, b)
    if id then
      if b then
        ImGui.PushStyleVar(ctx, id, a, b)
      else
        ImGui.PushStyleVar(ctx, id, a)
      end
      n_var = n_var + 1
    end
  end
  col(im_opt("Col_WindowBg"), P.page)
  col(im_opt("Col_ChildBg"), 0x00000000)
  col(im_opt("Col_PopupBg"), P.page)
  col(im_opt("Col_Border"), P.line2)
  col(im_opt("Col_Text"), P.ink)
  col(im_opt("Col_TextDisabled"), P.ink3)
  col(im_opt("Col_TextSelectedBg"), A(P.acc, 0x55))
  col(im_opt("Col_FrameBg"), P.page)
  col(im_opt("Col_FrameBgHovered"), P.page)
  col(im_opt("Col_FrameBgActive"), P.page)
  col(im_opt("Col_ScrollbarBg"), 0x00000000)
  col(im_opt("Col_ScrollbarGrab"), 0xFFFFFF1F)
  col(im_opt("Col_ScrollbarGrabHovered"), 0xFFFFFF38)
  col(im_opt("Col_ScrollbarGrabActive"), P.acc)
  col(im_opt("Col_NavHighlight"), A(P.acc, 0x80))
  var(im_opt("StyleVar_WindowPadding"), 0, 0)
  var(im_opt("StyleVar_WindowRounding"), 0)
  var(im_opt("StyleVar_WindowBorderSize"), 1)
  var(im_opt("StyleVar_ChildRounding"), 0)
  var(im_opt("StyleVar_FrameRounding"), 0)
  var(im_opt("StyleVar_PopupRounding"), 0)
  var(im_opt("StyleVar_ItemSpacing"), 0, 0)
  var(im_opt("StyleVar_ScrollbarSize"), 8)
  var(im_opt("StyleVar_ScrollbarRounding"), 0)
  return n_col, n_var
end

local WIN_W = 620
local HEADER_H = 56
local PAD = 26

-- --- Viewer: a separate window with the bug recording or what a report sends ---
-- Its text is built when it opens (and on Refresh or an option change), not every frame.

local function viewer_text(kind)
  if kind == "trace" then
    local lines = recording_lines()
    if #lines == 0 then
      return "(Nothing recorded yet.)"
    end
    return F.ScrubPaths(table.concat(lines, "\n"))
  end
  local trace = S.include_trace and (T.on or F.HasRecording())
  if not (S.include_log or trace) then
    return "(No log will be sent with this report: the usage log is off and no bug recording is attached.)"
  end
  return F.BuildLogText({ usage = S.include_log, trace = trace })
end

local function open_viewer(kind)
  local text = viewer_text(kind)
  local _, n = text:gsub("\n", "")
  S.viewer = { kind = kind, text = text, lines = n + 1, built = os.time() }
end

-- Rebuild an open viewer after something it shows changed.
local function refresh_viewer()
  if not (S and S.viewer) then
    return
  end
  if S.viewer.kind == "trace" and not (T.on or F.HasRecording()) then
    S.viewer = nil
  else
    open_viewer(S.viewer.kind)
  end
end

local function draw_viewer()
  local v = S.viewer
  local n_col, n_var = push_style()
  local cond_first, cond_appear = im_opt("Cond_FirstUseEver"), im_opt("Cond_Appearing")
  if cond_first then
    ImGui.SetNextWindowSize(ctx, 720, 520, cond_first)
  end
  if cond_appear and S.win_x and not v.placed then
    ImGui.SetNextWindowPos(ctx, S.win_x + WIN_W + 12, S.win_y, cond_appear)
    v.placed = true
  end
  if im_opt("SetNextWindowSizeConstraints") then
    ImGui.SetNextWindowSizeConstraints(ctx, 440, 260, 4000, 4000)
  end
  local flags = (im_opt("WindowFlags_NoCollapse") or 0) | (im_opt("WindowFlags_NoDocking") or 0)
    | (im_opt("WindowFlags_NoTitleBar") or 0) | (im_opt("WindowFlags_NoScrollbar") or 0)
    | (im_opt("WindowFlags_NoScrollWithMouse") or 0)
  local trace = v.kind == "trace"
  local visible, open = ImGui.Begin(ctx, "Feedback viewer - " .. cfg.script_name .. "###CRS_Viewer", true, flags)
  local close = open == false
  if visible then
    local x, y = ImGui.GetWindowPos(ctx)
    local w, h = ImGui.GetWindowSize(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)
    local hh = 52
    ImGui.DrawList_AddLine(dl, x, y + hh, x + w, y + hh, P.line, 1)
    if trace then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + 2, y + hh, P.red)
      if T.on then
        local a = math.floor((0.35 + 0.65 * pulse()) * 255)
        ImGui.DrawList_AddCircleFilled(dl, x + 24, y + hh / 2, 5, A(P.red, a))
      else
        ImGui.DrawList_AddCircleFilled(dl, x + 24, y + hh / 2, 5, P.red)
      end
    else
      ImGui.DrawList_AddRect(dl, x + 19, y + hh / 2 - 5, x + 29, y + hh / 2 + 5, P.acc)
    end
    local tx = caps(dl, 11, x + 40, y + (hh - 11) / 2 - 1, trace and P.red or P.ink, trace and "Bug recording" or "What's sent", true)
    local sub = string.format("%d lines  /  %s", v.lines, fmt_bytes(#v.text))
    if trace then
      sub = string.format("%d events  /  %s  /  ", T.events, F.RecordingDuration()) .. sub
    end
    caps(dl, 10, tx + 16, y + (hh - 10) / 2 - 1, P.ink3, sub)

    local cs = 28
    local cx, cy = x + w - 14 - cs, y + (hh - cs) / 2
    local cclick, chov = hit("##viewer_close", cx, cy, cs, cs)
    ImGui.DrawList_AddRect(dl, cx, cy, cx + cs, cy + cs, chov and 0xFFFFFF80 or P.line2)
    local cc, k = chov and P.ink or P.ink2, 4.5
    ImGui.DrawList_AddLine(dl, cx + cs / 2 - k, cy + cs / 2 - k, cx + cs / 2 + k, cy + cs / 2 + k, cc, 1.4)
    ImGui.DrawList_AddLine(dl, cx + cs / 2 + k, cy + cs / 2 - k, cx + cs / 2 - k, cy + cs / 2 + k, cc, 1.4)
    if cclick then
      close = true
    end
    local copied = v.copied_t and now_s() - v.copied_t < 1.5
    local cw = btn_w("Copied")
    local bx = cx - 10 - cw
    if btn("##viewer_copy", copied and "Copied" or "Copy", bx, y + (hh - BTN_H) / 2, nil, cw) then
      ImGui.SetClipboardText(ctx, v.text)
      v.copied_t = now_s()
    end
    local rw = btn_w("Refresh")
    bx = bx - 8 - rw
    if btn("##viewer_refresh", "Refresh", bx, y + (hh - BTN_H) / 2, nil, rw) then
      open_viewer(v.kind)
      S.viewer.placed = true
      v = S.viewer
    end
    tip(trace and "Read the recording again (it keeps growing while recording is on)." or "Build the text again.")

    ImGui.SetCursorScreenPos(ctx, x + 12, y + hh + 12)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, P.page)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, P.line)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, P.ink2)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
    if FONTS.mono11 then ImGui.PushFont(ctx, FONTS.mono11) end
    ImGui.InputTextMultiline(ctx, "##viewer_text", v.text, math.max(1, w - 24), math.max(1, h - hh - 24),
      ImGui.InputTextFlags_ReadOnly)
    if FONTS.mono11 then ImGui.PopFont(ctx) end
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx, 3)
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, n_var)
  ImGui.PopStyleColor(ctx, n_col)
  if close then
    S.viewer = nil
  end
end

local STEPS = {
  "Press Start bug recording. This window hides and a small recording badge appears.",
  "Do what causes the problem again.",
  false, -- stop_hint()
  "Describe what went wrong, then send.",
}

local function draw_recording_card(dl, x, y, w)
  if T.on then
    local a = math.floor((0.35 + 0.65 * pulse()) * 255)
    ImGui.DrawList_AddCircleFilled(dl, x + 7, y + 8, 6, A(P.red, a))
    local tx = caps(dl, 11, x + 22, y + 1, P.red, "Recording", true)
    caps(dl, 10, tx + 14, y + 2, P.ink2, F.RecordingDuration() .. "  /  " .. T.events .. " events")
    y = para(dl, x, y + 28, w, "Do what causes the problem again, then stop the recording to attach it to this report.")
    if btn("##recstop", "Stop and attach", x, y + 10, "go") then
      F.StopRecording()
      S.include_trace = true
      refresh_viewer()
    end
    if btn("##recview", "View", x + btn_w("Stop and attach") + 8, y + 10) then
      open_viewer("trace")
    end
    tip("Open what's been recorded so far in a separate window.")
    return y + 10 + BTN_H
  elseif F.HasRecording() then
    local dw, vw = btn_w("Discard"), btn_w("View")
    local v, changed, by = switch_row("##rectoggle", x, y, w - dw - vw - 24, S.include_trace, "Attach the bug recording",
      string.format("%d events, %s long.", T.events, F.RecordingDuration()))
    S.include_trace = v
    if changed then
      refresh_viewer()
    end
    if btn("##recview", "View", x + w - dw - 8 - vw, y - 4, nil, vw) then
      open_viewer("trace")
    end
    tip("Open the recording in a separate window.")
    if btn("##recdiscard", "Discard", x + w - dw, y - 4, nil, dw) then
      F.DiscardRecording()
      refresh_viewer()
    end
    return math.max(by, y + BTN_H)
  end
  if F.COMPANION then
    -- the recorder script only sends; a new recording starts in the script
    return para(dl, x, y, w, "To record a problem, press the red dot next to Send feedback in "
      .. tostring(cfg.script_name) .. ".", P.ink2)
  end
  y = para(dl, x, y, w, "Hard to pin down? Record what the script does while you repeat the problem, "
    .. "and the recording goes with your report.", P.ink2)
  y = y + 10
  if rec_button("##recstart", "Start bug recording", x, y, 260) then
    T.draft = { title = S.title, note = S.note }
    S.close = true
    F.StartRecording()
  end
  tip("Starts recording right away. This window hides until you stop.")
  y = y + REC_H + 16
  local nf = FONTS.mono10
  for i, s in ipairs(STEPS) do
    local num = string.format("%02d", i)
    txt(dl, FONTS.title18, 18, x, y - 3, A(P.red, 0xD0), num)
    y = para(dl, x + 34, y, w - 34, s or stop_hint(), P.ink) + 6
  end
  y = y + 4
  ImGui.DrawList_AddLine(dl, x, y, x + w, y, P.soft, 1)
  y = note(dl, x, y + 12, w, "The script may run a bit slower while recording. It notes clicks, changed values, "
    .. "REAPER actions and errors; never the text you type.")
  return y
end

local function draw_report_card(dl, x, y, w)
  y = field_label(dl, x, y, "Title")
  push_input_style()
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.SetNextItemWidth(ctx, w)
  if S.focus_title then
    ImGui.SetKeyboardFocusHere(ctx)
    S.focus_title = false
  end
  local _
  _, S.title = ImGui.InputTextWithHint(ctx, "##title", "Short summary", S.title)
  y = item_bottom() + 14
  pop_input_style()

  y = field_label(dl, x, y, "What happened, or what would you like?")
  push_input_style()
  ImGui.SetCursorScreenPos(ctx, x, y)
  _, S.note = ImGui.InputTextMultiline(ctx, "##note", S.note, w, 110)
  if S.note == "" and not ImGui.IsItemActive(ctx) then
    -- InputTextMultiline has no hint; draw one over the empty box.
    local ix, iy = ImGui.GetItemRectMin(ctx)
    txt(dl, FONTS.body13, 13, ix + 10, iy + 8, P.ink3, kind_hint())
  end
  y = item_bottom() + 14
  pop_input_style()

  y = field_label(dl, x, y, "Pictures (optional, up to " .. F.MAX_IMAGES .. ")")
  return draw_pictures(dl, x, y, w)
end

report_kind = function()
  local trace = S.include_trace and (T.on or F.HasRecording())
  return trace and "bug" or (S.kind or "other")
end

local function draw_send_card(dl, x, y, w)
  local lw = btn_w("Show what's sent")
  local v, changed, by = switch_row("##uselog", x, y, w - lw - 16, S.include_log, "Include usage log",
    "Script version, REAPER version, OS and recent script messages. Personal folder names are removed.")
  S.include_log = v
  if changed then
    refresh_viewer()
  end
  if btn("##showlog", "Show what's sent", x + w - lw, y - 4, nil, lw) then
    open_viewer("sent")
  end
  tip("Open the exact log this report will send, in a separate window.")
  y = by + 12
  ImGui.DrawList_AddLine(dl, x, y, x + w, y, P.soft, 1)
  y = field_label(dl, x, y + 14, "Contact (optional)")
  push_input_style()
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.SetNextItemWidth(ctx, w)
  local _
  _, S.contact = ImGui.InputTextWithHint(ctx, "##contact", "Email or forum name, if you'd like a reply", S.contact)
  y = item_bottom() + 12
  pop_input_style()
  if cfg.private_repo then
    -- a private repo: reports are issues only the developer sees
    y = note(dl, x, y, w, "Your report goes straight to the developer. It isn't posted publicly.")
  else
    y = note(dl, x, y, w, "Your report is posted publicly as an issue on " .. (cfg.repo_label or "the developer's GitHub page")
      .. ". Don't include anything private.")
  end
  y = draw_status(dl, x, y + 8, w)
  y = y + 10

  local sending = S.phase == "sending"
  local sw = 170
  if btn("##send", sending and "Sending..." or "Send report", x, y, "go", sw, sending) then
    start_send()
  end
  local bx = x + sw + 8
  if btn("##cancel", "Cancel", bx, y, nil, 96) then
    S.close = true
  end
  bx = bx + 96 + 8
  if S.status and S.status.kind == "error" and not sending then
    if btn("##copy", "Copy report", bx, y) then
      ImGui.SetClipboardText(ctx, report_as_text())
      set_status("info", "Copied. You can paste it in an email or forum post.")
    end
  end
  return y + BTN_H
end

local function draw_intro(dl, x, y, w, title, sub)
  caps(dl, 10, x, y, P.ink3, "Feedback  /  " .. tostring(cfg.script_name))
  chrome_text(dl, FONTS.title30, 30, x, y + 16, title)
  return para(dl, x, y + 58, w, sub, P.ink2) + 18
end

local function draw_form(x, y, w)
  local dl = ImGui.GetWindowDrawList(ctx)
  y = draw_intro(dl, x, y, w, "SEND FEEDBACK", "Report a problem or suggest an idea. It goes straight to the developer.")
  y = card("rec", x, y, w, 1, T.on and "Bug recording is on" or "Bug recording", P.red, draw_recording_card) + 24
  y = card("report", x, y, w, 2, "Your report", nil, draw_report_card) + 24
  y = card("send", x, y, w, 3, "Send", nil, draw_send_card)
  return y
end

local function draw_sent(x, y, w)
  local dl = ImGui.GetWindowDrawList(ctx)
  y = draw_intro(dl, x, y, w, "THANK YOU",
    "Your report was sent. It's now " .. (S.result.number and ("issue #" .. S.result.number) or "an issue")
    .. "; you can follow it, or add more details, on GitHub.")
  if btn("##open", "Open on GitHub", x, y, "go", 170) then
    open_url(S.result.url)
  end
  local bx = x + 178
  if btn("##another", "Send another", bx, y) then
    local contact = S.contact
    for i = #S.images, 1, -1 do
      remove_image(i)
    end
    S = new_state()
    S.contact = contact
    return y + BTN_H
  end
  bx = bx + btn_w("Send another") + 8
  if btn("##close", "Close", bx, y) then
    S.close = true
  end
  return y + BTN_H
end



-- Usable screen height, to keep the window on screen (the body scrolls).
local function max_body_h()
  if im_opt("GetMainViewport") and im_opt("Viewport_GetWorkSize") then
    local vp = ImGui.GetMainViewport(ctx)
    local _, h = ImGui.Viewport_GetWorkSize(vp)
    if h and h > 300 then
      return h - HEADER_H - 80
    end
  end
  return 760
end

-- The window header: mark, SCRIPT NAME | SEND FEEDBACK, version, close X.
-- Returns true when the close button was clicked.
local function draw_header(dl, x, y, w)
  ImGui.DrawList_AddLine(dl, x, y + HEADER_H, x + w, y + HEADER_H, P.line, 1)
  local mx, my, ms = x + 20, y + (HEADER_H - 26) / 2, 26
  ImGui.DrawList_AddRect(dl, mx, my, mx + ms, my + ms, P.line2)
  ImGui.DrawList_AddLine(dl, mx + 7, my + 9, mx + ms - 7, my + 9, P.ink2, 1.4)
  ImGui.DrawList_AddLine(dl, mx + 7, my + 14, mx + ms - 11, my + 14, P.ink3, 1.4)
  ImGui.DrawList_AddCircleFilled(dl, mx + ms - 6, my + ms - 6, 3.2, T.on and A(P.red, math.floor((0.35 + 0.65 * pulse()) * 255)) or P.acc)
  local tx = x + 60
  local name = tostring(cfg.script_name):upper()
  txt(dl, FONTS.title22, 22, tx, y + (HEADER_H - 22) / 2 - 3, P.ink, name)
  local sx = tx + text_w(name, FONTS.title22) + 14
  ImGui.DrawList_AddLine(dl, sx, y + 19, sx, y + HEADER_H - 19, P.line2, 1)
  caps(dl, 11, sx + 14, y + (HEADER_H - 11) / 2 - 1, P.ink2, "Send feedback")

  local cs = 28
  local cx, cy = x + w - 16 - cs, y + (HEADER_H - cs) / 2
  local clicked, hov = hit("##crs_close", cx, cy, cs, cs)
  ImGui.DrawList_AddRect(dl, cx, cy, cx + cs, cy + cs, hov and 0xFFFFFF80 or P.line2)
  local cc, k = hov and P.ink or P.ink2, 4.5
  ImGui.DrawList_AddLine(dl, cx + cs / 2 - k, cy + cs / 2 - k, cx + cs / 2 + k, cy + cs / 2 + k, cc, 1.4)
  ImGui.DrawList_AddLine(dl, cx + cs / 2 + k, cy + cs / 2 - k, cx + cs / 2 - k, cy + cs / 2 + k, cc, 1.4)
  local vs = "v" .. tostring(cfg.version):gsub("^[vV]", "")
  caps(dl, 10, cx - 14 - caps_w(10, vs), y + (HEADER_H - 10) / 2 - 1, P.ink3, vs)
  return clicked
end

local function draw_feedback()
  poll_screenshot()
  poll_send()

  local n_col, n_var = push_style()
  local hidden = S.shot ~= nil
  if hidden then
    -- Out of the way while a screenshot is taken.
    ImGui.SetNextWindowPos(ctx, -20000, -20000, ImGui.Cond_Always)
    S.restore_pos = true
  elseif S.restore_pos and S.win_x then
    ImGui.SetNextWindowPos(ctx, S.win_x, S.win_y, ImGui.Cond_Always)
    S.restore_pos = false
  end
  -- Fixed width; the height follows the content (last frame's), up to the screen.
  local body_h = math.min(S.body_h or 640, max_body_h())
  ImGui.SetNextWindowSize(ctx, WIN_W, HEADER_H + body_h + 2, ImGui.Cond_Always)
  local flags = (im_opt("WindowFlags_NoCollapse") or 0) | (im_opt("WindowFlags_NoDocking") or 0)
    | (im_opt("WindowFlags_NoTitleBar") or 0) | (im_opt("WindowFlags_NoScrollbar") or 0)
    | (im_opt("WindowFlags_NoScrollWithMouse") or 0)
  local title = "Send feedback - " .. cfg.script_name .. "###CRS_Feedback"
  local visible, open = ImGui.Begin(ctx, title, true, flags)
  if visible then
    local x, y = ImGui.GetWindowPos(ctx)
    if not hidden then
      S.win_x, S.win_y = x, y
    end
    local dl = ImGui.GetWindowDrawList(ctx)
    -- the site's column guides behind everything
    local wh = HEADER_H + body_h + 2
    for k = 1, 5 do
      local gx = math.floor(x + WIN_W * k / 6) + 0.5
      ImGui.DrawList_AddLine(dl, gx, y + HEADER_H, gx, y + wh, P.guide, 1)
    end
    if draw_header(dl, x, y, WIN_W) then
      S.close = true
    end
    ImGui.SetCursorScreenPos(ctx, x + 1, y + HEADER_H + 1)
    if ImGui.BeginChild(ctx, "##crs_body", WIN_W - 2, body_h) then
      local cx, cy = ImGui.GetCursorScreenPos(ctx)
      local cw = WIN_W - 2 - PAD * 2
      local bottom
      if S.phase == "sent" then
        bottom = draw_sent(cx + PAD, cy + PAD, cw)
      else
        bottom = draw_form(cx + PAD, cy + PAD, cw)
      end
      if S then
        S.body_h = bottom + PAD - cy
      end
      ImGui.SetCursorScreenPos(ctx, cx, bottom)
      ImGui.Dummy(ctx, 1, PAD)
      ImGui.EndChild(ctx)
    end
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, n_var)
  ImGui.PopStyleColor(ctx, n_col)
  if S.viewer and not hidden then
    draw_viewer()
  end

  if open == false or S.close then
    local send = S.send
    if send then
      -- Let the upload finish in the background, then clean up its temp files.
      local function finish()
        if bg_poll(send.job) == "running" then
          r.defer(finish)
        else
          for _, p in ipairs(send.temps) do
            os.remove(p)
          end
        end
      end
      r.defer(finish)
    end
    for i = #S.images, 1, -1 do
      remove_image(i)
    end
    S = nil
  end
end

-- Stop recording and open the window with the recording attached (the
-- badge's "Stop and send"; hosts can call it from their own button).
function F.StopAndReport()
  local draft = T.draft or {}
  T.draft = nil
  F.StopRecording()
  F.Open({ title = draft.title, note = draft.note, include_trace = true })
end

-- The small always-on-top badge shown while bug recording is on.
local BADGE_W, BADGE_H = 340, 92
local function draw_badge()
  local n_col, n_var = push_style()
  local flags = (im_opt("WindowFlags_NoTitleBar") or 0) | (im_opt("WindowFlags_NoResize") or 0)
    | (im_opt("WindowFlags_NoDocking") or 0) | (im_opt("WindowFlags_NoCollapse") or 0)
    | (im_opt("WindowFlags_NoScrollbar") or 0) | (im_opt("WindowFlags_NoFocusOnAppearing") or 0)
    | (im_opt("WindowFlags_TopMost") or 0)
  if im_opt("GetMainViewport") and im_opt("Viewport_GetWorkPos") and im_opt("Viewport_GetWorkSize") then
    local vp = ImGui.GetMainViewport(ctx)
    local x, y = ImGui.Viewport_GetWorkPos(vp)
    local w = vp and ImGui.Viewport_GetWorkSize(vp)
    if x and y and w then
      ImGui.SetNextWindowPos(ctx, x + w - BADGE_W - 60, y + 80, ImGui.Cond_FirstUseEver)
    end
  end
  ImGui.SetNextWindowSize(ctx, BADGE_W, BADGE_H, ImGui.Cond_Always)
  local visible = ImGui.Begin(ctx, "Bug recording###CRS_Recording", nil, flags)
  if visible then
    local x, y = ImGui.GetWindowPos(ctx)
    T.badge_x, T.badge_y = x, y
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + 2, y + BADGE_H, P.red)
    local a = math.floor((0.35 + 0.65 * pulse()) * 255)
    ImGui.DrawList_AddCircle(dl, x + 22, y + 24, 9, A(P.red, a // 3), 0, 1)
    ImGui.DrawList_AddCircleFilled(dl, x + 22, y + 24, 5.5, A(P.red, a))
    local tx = caps(dl, 11, x + 40, y + 18, P.red, "Recording", true)
    caps(dl, 10, tx + 12, y + 19, P.ink2, F.RecordingDuration() .. "  /  " .. T.events .. " events")
    ImGui.SetCursorScreenPos(ctx, x, y)
    ImGui.Dummy(ctx, BADGE_W, 44)
    tip(cfg.script_name .. " is writing down what it does.\nRepeat the problem, then press Stop and send.\n"
      .. "The script may run a little slower until you stop.")
    if btn("##badge_send", "Stop and send", x + 16, y + 48, "go", 170) then
      F.StopAndReport()
    end
    if btn("##badge_stop", "Stop", x + 194, y + 48, nil, 80) then
      F.StopRecording()
      F.ShowStopNote()
    end
    tip("Stops recording. It's kept until you send a report or discard it.")
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, n_var)
  ImGui.PopStyleColor(ctx, n_col)
end

-- After Stop: a short note where the badge was, saying where the recording
-- went. It fades out by itself; a click closes it sooner.
local NOTE_S = 7
local stop_note -- { t = start time }

function F.ShowStopNote()
  stop_note = { t = now_s() }
end

local function draw_stop_note()
  local age = now_s() - stop_note.t
  if age > NOTE_S or stop_note.closed then
    stop_note = nil
    return
  end
  local alpha = math.max(0, math.min(1, age / 0.15, (NOTE_S - age) / 0.6))
  local body = "It's waiting in the Send feedback window, attached and ready. Open Send feedback in "
    .. tostring(cfg.script_name) .. " to say what went wrong and send it."
  local lines = wrap(body, FONTS.body13, BADGE_W - 56)
  local h = 50 + #lines * 17 + 18
  local n_col, n_var = push_style()
  local alpha_var = im_opt("StyleVar_Alpha")
  if alpha_var then
    ImGui.PushStyleVar(ctx, alpha_var, alpha)
  end
  local flags = (im_opt("WindowFlags_NoTitleBar") or 0) | (im_opt("WindowFlags_NoResize") or 0)
    | (im_opt("WindowFlags_NoDocking") or 0) | (im_opt("WindowFlags_NoCollapse") or 0)
    | (im_opt("WindowFlags_NoScrollbar") or 0) | (im_opt("WindowFlags_NoFocusOnAppearing") or 0)
    | (im_opt("WindowFlags_TopMost") or 0) | (im_opt("WindowFlags_NoMove") or 0)
  if T.badge_x then
    ImGui.SetNextWindowPos(ctx, T.badge_x, T.badge_y, ImGui.Cond_Always)
  end
  ImGui.SetNextWindowSize(ctx, BADGE_W, h, ImGui.Cond_Always)
  local visible = ImGui.Begin(ctx, "Recording saved###CRS_StopNote", nil, flags)
  if visible then
    local x, y = ImGui.GetWindowPos(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + 2, y + h, P.acc)
    -- a check mark in a ring
    local cx, cy = x + 22, y + 24
    ImGui.DrawList_AddCircle(dl, cx, cy, 9, A(P.acc, 0x70), 0, 1)
    ImGui.DrawList_AddLine(dl, cx - 4, cy, cx - 1, cy + 3, P.acc, 1.6)
    ImGui.DrawList_AddLine(dl, cx - 1, cy + 3, cx + 4.5, cy - 3.5, P.acc, 1.6)
    local tx = caps(dl, 11, x + 40, y + 18, P.acc, "Recording saved", true)
    caps(dl, 10, tx + 12, y + 19, P.ink2, (tonumber(T.events) or 0) .. " events")
    local ly = y + 46
    for _, l in ipairs(lines) do
      txt(dl, FONTS.body13, 13, x + 40, ly, P.ink, l)
      ly = ly + 17
    end
    -- time left, as a thin line along the bottom
    local left = math.max(0, 1 - age / NOTE_S)
    ImGui.DrawList_AddLine(dl, x + 2, y + h - 1.5, x + 2 + (BADGE_W - 2) * left, y + h - 1.5, A(P.acc, 0x90), 2)
    if hit("##stopnote", x, y, BADGE_W, h) then
      stop_note.closed = true
    end
    tip("Click to close.")
    ImGui.End(ctx)
  end
  if alpha_var then
    ImGui.PopStyleVar(ctx)
  end
  ImGui.PopStyleVar(ctx, n_var)
  ImGui.PopStyleColor(ctx, n_col)
end

local loop_on = false

-- The module's own frames skip the recording's defer wrapper, so that
-- T.host_frame_t only tracks the host script's frames.
local function own_defer(fn)
  local saved = T.originals[r]
  local d = (saved and saved.defer) or r.defer
  d(fn)
end

local companion_tick -- set further down

local function tick()
  if F.COMPANION then
    return companion_tick()
  end
  local badge = T.on
  if T.on then
    T.busy = true
    pcall(rec_poll_state)
    T.busy = false
    -- The host closed its window (its frames stopped): end with it instead
    -- of keeping the script alive for the badge. Recording stays switched
    -- on, so it resumes the next time the script starts (or is sent from
    -- the recorder script, which notices the heartbeat stopped).
    if T.host_frame_t and now_s() - T.host_frame_t > 1.5 then
      badge = false
      rec_flush_pending()
      if T.fh then
        T.fh:close()
        T.fh = nil
      end
    else
      T.busy = true
      local ok, err = pcall(host_beat)
      T.busy = false
      if not ok then
        F.Log("Recorder heartbeat error: " .. tostring(err))
      end
      -- the recorder script draws the badge when it runs
      badge = T.on and host_badge_needed()
    end
  end
  if S then
    -- same Lua state as the host script: an error here must not stop the host
    local ok, err = pcall(draw_feedback)
    if not ok then
      F.Log("Feedback window error: " .. tostring(err))
      S = nil
    end
  end
  if stop_note and not badge then
    if not pcall(draw_stop_note) then
      stop_note = nil
    end
  end
  if badge then
    local ok, err = pcall(draw_badge)
    if not ok and not T.badge_err then
      T.badge_err = true
      F.Log("Recording badge error: " .. tostring(err))
    end
  end
  if S or badge or stop_note or (T.on and not (T.host_frame_t and now_s() - T.host_frame_t > 1.5)) then
    own_defer(tick)
  else
    loop_on = false
  end
end
F._frame = tick

ensure_loop = function()
  load_imgui()
  if not ctx or not (ImGui.ValidatePtr and ImGui.ValidatePtr(ctx, "ImGui_Context*")) then
    ctx = ImGui.CreateContext("CRS Feedback")
    load_fonts()
  end
  if not loop_on then
    loop_on = true
    own_defer(tick)
  end
end

-- --- Recorder script (its side) ----------------------------------------------
-- CRS_Feedback_Recorder.lua loads this file in its own Lua state and calls
-- F.RunCompanion. It never records anything itself: the host writes the
-- recording file, and this side shows the badge, asks the host to stop,
-- and sends the file. When the host's heartbeat stops (it crashed or was
-- closed) the badge offers to send what was recorded up to then.

local C -- recorder state; nil in a host

-- Load the recording the host wrote, for the report window.
local function companion_load_recording(host_gone)
  T.lines, T.next, T.count, T.events = {}, 1, 0, 0
  T.fh = nil
  for line in (read_file(rec_path()) or ""):gmatch("[^\n]+") do
    rec_write(line)
  end
  if host_gone then
    rec_write(rec_clock() .. " RECORDING ended: " .. tostring(cfg.script_name)
      .. " stopped while recording (it crashed or was closed). Sent from the recorder window.")
  end
  T.events = math.max(T.count, tonumber(xget("rec_ev")) or 0)
  T.started = tonumber(r.GetExtState("CRS_Feedback", rec_ext_key() .. "_since")) or T.started or os.time()
  T.ended = os.time()
  T.on = false
  T.stopped_unsent = T.count > 0
end

local function companion_open_report(host_gone)
  companion_load_recording(host_gone)
  local title, note_text = xget("draft_title"), xget("draft_note")
  if host_gone and title == "" then
    title = tostring(cfg.script_name) .. " stopped while recording"
  end
  F.Open({ kind = "bug", title = title, note = note_text, include_trace = true })
  if S and host_gone then
    set_status("info", tostring(cfg.script_name) .. " isn't running. The recording up to when it stopped is attached.")
  end
end

local function companion_finish()
  C.done = true
end

local function companion_badge()
  local n_col, n_var = push_style()
  local flags = (im_opt("WindowFlags_NoTitleBar") or 0) | (im_opt("WindowFlags_NoResize") or 0)
    | (im_opt("WindowFlags_NoDocking") or 0) | (im_opt("WindowFlags_NoCollapse") or 0)
    | (im_opt("WindowFlags_NoScrollbar") or 0) | (im_opt("WindowFlags_NoFocusOnAppearing") or 0)
    | (im_opt("WindowFlags_TopMost") or 0)
  if im_opt("GetMainViewport") and im_opt("Viewport_GetWorkPos") and im_opt("Viewport_GetWorkSize") then
    local vp = ImGui.GetMainViewport(ctx)
    local x, y = ImGui.Viewport_GetWorkPos(vp)
    local w = vp and ImGui.Viewport_GetWorkSize(vp)
    if x and y and w then
      ImGui.SetNextWindowPos(ctx, x + w - BADGE_W - 60, y + 80, ImGui.Cond_FirstUseEver)
    end
  end
  ImGui.SetNextWindowSize(ctx, BADGE_W, BADGE_H, ImGui.Cond_Always)
  local visible = ImGui.Begin(ctx, "Bug recording - " .. tostring(cfg.script_name) .. "###CRS_Recording", nil, flags)
  if visible then
    local x, y = ImGui.GetWindowPos(ctx)
    T.badge_x, T.badge_y = x, y
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + 2, y + BADGE_H, P.red)
    local events = tonumber(xget("rec_ev")) or 0
    local since = tonumber(r.GetExtState("CRS_Feedback", rec_ext_key() .. "_since")) or os.time()
    local secs = math.max(0, os.time() - since)
    local dur = secs >= 3600 and string.format("%d:%02d:%02d", secs // 3600, (secs % 3600) // 60, secs % 60)
      or string.format("%d:%02d", secs // 60, secs % 60)
    if C.host_gone then
      ImGui.DrawList_AddCircleFilled(dl, x + 22, y + 24, 5.5, P.red)
      local tx = caps(dl, 11, x + 40, y + 18, P.red, "Recording saved", true)
      caps(dl, 10, tx + 12, y + 19, P.ink2, events .. " events")
      ImGui.SetCursorScreenPos(ctx, x, y)
      ImGui.Dummy(ctx, BADGE_W, 44)
      tip(tostring(cfg.script_name) .. " stopped while recording (it crashed or was closed).\n"
        .. "Send what was recorded now, or press Later: recording carries on\nthe next time you open "
        .. tostring(cfg.script_name) .. ".")
      if btn("##badge_send", "Send report", x + 16, y + 48, "go", 150) then
        companion_open_report(true)
      end
      if btn("##badge_discard", "Discard", x + 174, y + 48, nil, 80) then
        F.DiscardRecording()
        companion_finish()
      end
      tip("Delete the recording.")
      if btn("##badge_later", "Later", x + 262, y + 48, nil, 62) then
        companion_finish()
      end
      tip("Close this. Recording carries on the next time you open " .. tostring(cfg.script_name) .. ".")
    else
      local a = math.floor((0.35 + 0.65 * pulse()) * 255)
      ImGui.DrawList_AddCircle(dl, x + 22, y + 24, 9, A(P.red, a // 3), 0, 1)
      ImGui.DrawList_AddCircleFilled(dl, x + 22, y + 24, 5.5, A(P.red, a))
      local tx = caps(dl, 11, x + 40, y + 18, P.red, "Recording", true)
      caps(dl, 10, tx + 12, y + 19, P.ink2, dur .. "  /  " .. events .. " events")
      ImGui.SetCursorScreenPos(ctx, x, y)
      ImGui.Dummy(ctx, BADGE_W, 44)
      tip(tostring(cfg.script_name) .. " is writing down what it does.\nRepeat the problem, then press Stop and send.\n"
        .. "This badge stays even if " .. tostring(cfg.script_name) .. " crashes.")
      local stopping = C.stopping ~= nil
      if btn("##badge_send", stopping and "Stopping..." or "Stop and send", x + 16, y + 48, "go", 170, stopping) then
        xset("rec_ack", "")
        xset("rec_cmd", "stop")
        C.stopping = { send = true, t = now_s() }
      end
      if btn("##badge_stop", "Stop", x + 194, y + 48, nil, 80, stopping) then
        xset("rec_ack", "")
        xset("rec_cmd", "stop")
        C.stopping = { send = false, t = now_s() }
      end
      tip("Stops recording. It's kept until you send a report from " .. tostring(cfg.script_name) .. " or discard it.")
    end
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, n_var)
  ImGui.PopStyleColor(ctx, n_col)
end

companion_tick = function()
  r.SetExtState("CRS_Feedback", xkey("comp_hb"), tostring(now_s()), false)
  local host_alive = xfresh("rec_hb", 2.5)
  local recording = r.GetExtState("CRS_Feedback", rec_ext_key()) == "1"
  if C.stopping then
    local acked = xget("rec_ack") == "stopped"
    if acked or not host_alive or now_s() - C.stopping.t > 4 then
      local send = C.stopping.send
      C.stopping = nil
      xset("rec_ack", "")
      if not acked then
        xset("rec_cmd", "")
      end
      if send then
        companion_open_report(not acked)
      else
        companion_finish()
        F.ShowStopNote()
        T.events = tonumber(xget("rec_ev")) or 0
      end
    end
  elseif not S then
    if host_alive and recording then
      C.host_gone = false
    elseif not host_alive and (recording or (C.host_gone and file_size(rec_path()))) then
      if not C.host_gone then
        C.host_gone = true
        F.Log("Recorder: " .. tostring(cfg.script_name) .. " stopped while recording")
      end
    elseif not C.host_gone then
      -- the host stopped the recording itself (and shows its own window)
      companion_finish()
    end
  end
  if S then
    local ok, err = pcall(draw_feedback)
    if not ok then
      F.Log("Recorder window error: " .. tostring(err))
      S = nil
    end
    if not S then
      -- window closed: back to the badge if the host is recording again,
      -- otherwise done (a recording not sent stays on disk)
      if xfresh("rec_hb", 2.5) and r.GetExtState("CRS_Feedback", rec_ext_key()) == "1" then
        C.host_gone = false
      else
        companion_finish()
      end
    end
  elseif not C.done then
    local ok, err = pcall(companion_badge)
    if not ok and not C.badge_err then
      C.badge_err = true
      F.Log("Recorder badge error: " .. tostring(err))
    end
  elseif stop_note then
    if not pcall(draw_stop_note) then
      stop_note = nil
    end
  end
  if S or not C.done or stop_note then
    r.defer(companion_tick)
  else
    r.DeleteExtState("CRS_Feedback", xkey("comp_hb"), false)
    loop_on = false
  end
end

-- Entry point of CRS_Feedback_Recorder.lua.
function F.RunCompanion(script_id)
  F.COMPANION = true
  cfg.script_id = script_id
  local got = decode_cfg(xget("comp_cfg"))
  for k, v in pairs(got) do
    cfg[k] = v
  end
  cfg.script_id = script_id
  log_path = nil
  if not cfg.repo_label and cfg.repo then
    cfg.repo_label = "github.com/" .. cfg.repo
  end
  C = { host_gone = false }
  r.SetExtState("CRS_Feedback", xkey("comp_hb"), tostring(now_s()), false)
  if r.atexit then
    r.atexit(function()
      r.DeleteExtState("CRS_Feedback", xkey("comp_hb"), false)
    end)
  end
  ensure_loop()
end

-- --- Public API --------------------------------------------------------------

function F.Setup(opts)
  for k, v in pairs(opts or {}) do
    cfg[k] = v
  end
  log_path = nil
  if not cfg.repo_label and cfg.repo then
    cfg.repo_label = "github.com/" .. cfg.repo
  end
  -- Bug recording left on last time: carry on (catches bugs at startup).
  if not T.on and not F.COMPANION and r.GetExtState and r.GetExtState("CRS_Feedback", rec_ext_key()) == "1" then
    F.StartRecording(true)
  end
  return F
end

function F.IsOpen()
  return S ~= nil
end

-- Open the window (or bring it back if it's already open).
-- opts: title, note, include_trace, kind (sent as "bug" when a recording is
-- attached, otherwise this or "other").
function F.Open(opts)
  if S then
    if opts and opts.note and S.note == "" then
      S.note = opts.note
    end
    return
  end
  S = new_state(opts)
  ensure_loop()
end

function F.Close()
  if S then
    S.close = true
  end
end

-- Drop-in for reaper.defer(fn) that catches errors: the error and traceback go
-- to the usage log and the feedback window opens with them filled in.
-- Returns true if fn ran without error.
function F.Defer(fn)
  r.defer(function()
    local ok, err = xpcall(fn, function(e)
      return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
    end)
    if not ok then
      F.ReportCrash(err)
    end
  end)
end

function F.ReportCrash(err)
  local text = F.ScrubPaths(tostring(err))
  F.Log("ERROR: " .. text)
  F.Open({
    kind = "bug",
    title = cfg.script_name .. " stopped with an error",
    note = "The script stopped with this error:\n\n" .. text
      .. "\n\nWhat were you doing just before it happened?\n",
  })
  if r.ShowConsoleMsg then
    r.ShowConsoleMsg(cfg.script_name .. " stopped with an error:\n" .. text .. "\n")
  end
end

return F

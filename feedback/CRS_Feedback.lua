-- @noindex
-- CRS Feedback: an in-script "Send feedback" window shared by BryanChi's REAPER
-- scripts (Sample Map, FX Devices, Vertical FX List).
--
-- A report (kind, title, note, optional contact, optional usage log, up to 5
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

-- Where reports go. Set this once the relay is deployed (see
-- feedback/README.md). An ExtState override lets testers point at a dev relay:
-- reaper.SetExtState("CRS_Feedback", "endpoint", "https://...", true)
F.ENDPOINT = "https://crs-feedback.REPLACE-ME.workers.dev/report"

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

-- The exact log text a report would include (already scrubbed).
function F.BuildLogText()
  local env = environment()
  local lines = {
    string.format("%s %s", cfg.script_name, cfg.version),
    string.format("REAPER %s on %s, ReaImGui %s, JS API %s, SWS %s",
      env.reaper, env.os, env.reaimgui, env.js_api and "yes" or "no", env.sws and "yes" or "no"),
    "",
  }
  local extra = {}
  if cfg.get_log then
    local ok, got = pcall(cfg.get_log)
    if ok and type(got) == "table" then
      extra = got
    elseif ok and type(got) == "string" then
      for line in got:gmatch("[^\n]+") do
        extra[#extra + 1] = line
      end
    end
  end
  local ring = ring_lines()
  if #ring == 0 then
    ring = file_log_tail(150)
    if #ring > 0 then
      lines[#lines + 1] = "-- Usage log (last session) --"
    end
  else
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
  if #ring == 0 and #extra == 0 then
    lines[#lines + 1] = "(no log lines yet)"
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

local KINDS = {
  { id = "bug", label = "Bug", hint = "What did you do, what did you expect, and what happened instead?" },
  { id = "idea", label = "Idea", hint = "What would you like the script to do?" },
  { id = "question", label = "Question", hint = "What would you like to know?" },
  { id = "other", label = "Other", hint = "Tell us anything." },
}

local S -- window state; nil while closed
local ImGui
local ctx

local function new_state(opts)
  opts = opts or {}
  return {
    kind = opts.kind or "bug",
    title = opts.title or "",
    note = opts.note or "",
    contact = r.GetExtState and r.GetExtState("CRS_Feedback", "contact") or "",
    include_log = opts.include_log ~= false,
    show_log = false,
    log_text = nil,
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
    string.format("[%s] %s", S.kind, trim(S.title)),
    string.format("%s %s - REAPER %s - %s", cfg.script_name, cfg.version, env.reaper, env.os),
    "",
    trim(S.note),
  }
  if trim(S.contact) ~= "" then
    t[#t + 1] = ""
    t[#t + 1] = "Contact: " .. trim(S.contact)
  end
  if S.include_log then
    t[#t + 1] = ""
    t[#t + 1] = F.BuildLogText()
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
    log = state.include_log and F.BuildLogText() or "",
    env = environment(),
    images = images,
  }
end

local function start_send()
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
  S.send = { job = job, resp_path = resp_path, code_path = code_path, temps = temps }
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

local COL = {
  bg = 0x1E2126FF,
  panel = 0x272B32FF,
  frame = 0x2F343DFF,
  frame_hover = 0x3A404BFF,
  accent = 0x4C8DFFFF,
  accent_hover = 0x6AA0FFFF,
  text = 0xE6E8EBFF,
  mute = 0x9BA3AFFF,
  error = 0xFF7A7AFF,
  ok = 0x6FD98CFF,
  border = 0x3A3F48FF,
}

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
  col(ImGui.Col_WindowBg, COL.bg)
  col(ImGui.Col_ChildBg, COL.panel)
  col(ImGui.Col_FrameBg, COL.frame)
  col(ImGui.Col_FrameBgHovered, COL.frame_hover)
  col(ImGui.Col_FrameBgActive, COL.frame_hover)
  col(ImGui.Col_Button, COL.frame)
  col(ImGui.Col_ButtonHovered, COL.frame_hover)
  col(ImGui.Col_ButtonActive, COL.accent)
  col(ImGui.Col_CheckMark, COL.accent_hover)
  col(ImGui.Col_Text, COL.text)
  col(ImGui.Col_TextDisabled, COL.mute)
  col(ImGui.Col_Border, COL.border)
  col(ImGui.Col_TitleBg, COL.bg)
  col(ImGui.Col_TitleBgActive, COL.panel)
  var(ImGui.StyleVar_WindowPadding, 16, 14)
  var(ImGui.StyleVar_FramePadding, 8, 6)
  var(ImGui.StyleVar_ItemSpacing, 8, 8)
  var(ImGui.StyleVar_FrameRounding, 5)
  var(ImGui.StyleVar_ChildRounding, 6)
  var(ImGui.StyleVar_WindowRounding, 8)
  return n_col, n_var
end

local function primary_button(label, w)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, COL.accent)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, COL.accent_hover)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, COL.accent)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
  local pressed = ImGui.Button(ctx, label, w or 0, 0)
  ImGui.PopStyleColor(ctx, 4)
  return pressed
end

local function caption(text, wrapped)
  if wrapped then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, COL.mute)
    ImGui.TextWrapped(ctx, text)
    ImGui.PopStyleColor(ctx)
  else
    ImGui.TextColored(ctx, COL.mute, text)
  end
end

local function kind_hint()
  for _, k in ipairs(KINDS) do
    if k.id == S.kind then
      return k.hint
    end
  end
  return ""
end

local function draw_kind_tabs()
  for i, k in ipairs(KINDS) do
    if i > 1 then
      ImGui.SameLine(ctx, 0, 4)
    end
    local active = S.kind == k.id
    if active then
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, COL.accent)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, COL.accent_hover)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
    end
    if ImGui.Button(ctx, k.label .. "##kind", 86, 0) then
      S.kind = k.id
    end
    if active then
      ImGui.PopStyleColor(ctx, 3)
    end
  end
end

local function fmt_bytes(n)
  if n >= 1048576 then
    return string.format("%.1f MB", n / 1048576)
  end
  return string.format("%d KB", math.max(1, math.floor(n / 1024 + 0.5)))
end

local THUMB = 84

local function draw_pictures(width)
  caption("Pictures (optional, up to " .. F.MAX_IMAGES .. ")")
  local h = THUMB + 34
  if ImGui.BeginChild(ctx, "##pictures", width, h, ImGui.ChildFlags_Border or 1) then
    local remove_at
    for i, im in ipairs(S.images) do
      if i > 1 then
        ImGui.SameLine(ctx, 0, 8)
      end
      ImGui.BeginGroup(ctx)
      local drew = false
      if im.img and ImGui.Image then
        local ok, iw, ih = pcall(ImGui.Image_GetSize, im.img)
        if ok and iw and iw > 0 and ih > 0 then
          local s = math.min(THUMB / iw, THUMB / ih)
          drew = pcall(ImGui.Image, ctx, im.img, iw * s, ih * s)
        end
      end
      if not drew then
        ImGui.Button(ctx, im.ext:upper() .. "##thumb" .. i, THUMB, THUMB)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, F.ScrubPaths(im.name) .. "  (" .. fmt_bytes(im.bytes) .. ")")
      end
      if ImGui.SmallButton(ctx, "Remove##img" .. i) then
        remove_at = i
      end
      ImGui.EndGroup(ctx)
    end
    if #S.images == 0 then
      ImGui.Dummy(ctx, 1, 18)
      ImGui.TextColored(ctx, COL.mute, "Drop picture files here, or use the buttons below.")
    end
    ImGui.EndChild(ctx)
    if remove_at then
      remove_image(remove_at)
    end
  end
  -- Accept files dragged from Finder/Explorer onto the picture area.
  if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
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
  local full = #S.images >= F.MAX_IMAGES
  if full and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx) end
  if ImGui.Button(ctx, "Add picture...") and not full then
    browse_images()
  end
  if is_mac() or is_windows() then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, S.shot and "Taking screenshot..." or "Take screenshot") and not full and not S.shot then
      start_screenshot()
    end
  end
  if full and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end
end

local function draw_status()
  if not S.status then
    return
  end
  local c = S.status.kind == "error" and COL.error or (S.status.kind == "ok" and COL.ok or COL.mute)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, c)
  ImGui.TextWrapped(ctx, S.status.text)
  ImGui.PopStyleColor(ctx)
end

local function repo_hint()
  return cfg.repo_label or "the developer's GitHub page"
end

local function draw_form(avail_w)
  draw_kind_tabs()
  ImGui.Spacing(ctx)
  caption("Title")
  ImGui.SetNextItemWidth(ctx, avail_w)
  if S.focus_title then
    ImGui.SetKeyboardFocusHere(ctx)
    S.focus_title = false
  end
  local _
  _, S.title = ImGui.InputTextWithHint(ctx, "##title", "Short summary", S.title)
  caption(S.kind == "bug" and "What happened?" or "Details")
  _, S.note = ImGui.InputTextMultiline(ctx, "##note", S.note, avail_w, 130)
  if S.note == "" and not ImGui.IsItemActive(ctx) then
    -- InputTextMultiline has no hint; draw one over the empty box.
    local x, y = ImGui.GetItemRectMin(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddText(dl, x + 8, y + 6, COL.mute, kind_hint())
  end

  ImGui.Spacing(ctx)
  draw_pictures(avail_w)

  ImGui.Spacing(ctx)
  local changed
  changed, S.include_log = ImGui.Checkbox(ctx, "Include usage log", S.include_log)
  if changed then
    S.log_text = nil
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, S.show_log and "Hide what's sent" or "Show what's sent") then
    S.show_log = not S.show_log
    S.log_text = nil
  end
  caption("Script version, REAPER version, OS and recent script messages. Personal folder names are removed.", true)
  if S.show_log then
    if not S.log_text then
      S.log_text = S.include_log and F.BuildLogText() or "(the usage log won't be sent)"
    end
    ImGui.InputTextMultiline(ctx, "##logpreview", S.log_text, avail_w, 120, ImGui.InputTextFlags_ReadOnly)
  end

  ImGui.Spacing(ctx)
  caption("Contact (optional)")
  ImGui.SetNextItemWidth(ctx, avail_w)
  _, S.contact = ImGui.InputTextWithHint(ctx, "##contact", "Email or forum name, if you'd like a reply", S.contact)

  ImGui.Spacing(ctx)
  caption("Your report is posted publicly as an issue on " .. repo_hint()
    .. ". Don't include anything private.", true)
  draw_status()
  ImGui.Spacing(ctx)

  local sending = S.phase == "sending"
  if sending and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx) end
  if primary_button(sending and "Sending..." or "Send report", 130) and not sending then
    start_send()
  end
  if sending and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel", 80) then
    S.close = true
  end
  if S.status and S.status.kind == "error" and not sending then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Copy report") then
      ImGui.SetClipboardText(ctx, report_as_text())
      set_status("info", "Copied. You can paste it in an email or forum post.")
    end
  end
end

local function draw_sent()
  ImGui.Dummy(ctx, 1, 10)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, COL.ok)
  ImGui.Text(ctx, "Thanks! Your report was sent.")
  ImGui.PopStyleColor(ctx)
  ImGui.Spacing(ctx)
  ImGui.TextWrapped(ctx, "It's now " .. (S.result.number and ("issue #" .. S.result.number) or "an issue")
    .. ". You can follow it, or add more details, on GitHub.")
  ImGui.Spacing(ctx)
  if primary_button("Open on GitHub", 140) then
    open_url(S.result.url)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Send another") then
    local contact = S.contact
    for i = #S.images, 1, -1 do
      remove_image(i)
    end
    S = new_state()
    S.contact = contact
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Close") then
    S.close = true
  end
end

local WIN_W = 560

local function frame()
  if not S then
    return
  end
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
  -- Fixed width; a height of 0 auto-fits the content.
  ImGui.SetNextWindowSize(ctx, WIN_W, 0, ImGui.Cond_Always)
  local flags = (ImGui.WindowFlags_NoCollapse or 0) | (ImGui.WindowFlags_NoDocking or 0)
  local title = "Send feedback - " .. cfg.script_name .. "###CRS_Feedback"
  local visible, open = ImGui.Begin(ctx, title, true, flags)
  if visible then
    if not hidden then
      S.win_x, S.win_y = ImGui.GetWindowPos(ctx)
    end
    local avail_w = WIN_W - 32
    if S.phase == "sent" then
      draw_sent()
    else
      draw_form(avail_w)
    end
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, n_var)
  ImGui.PopStyleColor(ctx, n_col)

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
    return
  end
  r.defer(frame)
end
F._frame = frame

-- --- Public API --------------------------------------------------------------

function F.Setup(opts)
  for k, v in pairs(opts or {}) do
    cfg[k] = v
  end
  log_path = nil
  if not cfg.repo_label and cfg.repo then
    cfg.repo_label = "github.com/" .. cfg.repo
  end
  return F
end

function F.IsOpen()
  return S ~= nil
end

-- Open the window (or bring it back if it's already open).
-- opts: kind ("bug"|"idea"|"question"|"other"), title, note.
function F.Open(opts)
  if S then
    if opts and opts.note and S.note == "" then
      S.note = opts.note
    end
    return
  end
  load_imgui()
  if not ctx or not (ImGui.ValidatePtr and ImGui.ValidatePtr(ctx, "ImGui_Context*")) then
    ctx = ImGui.CreateContext("CRS Feedback")
  end
  S = new_state(opts)
  r.defer(frame)
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

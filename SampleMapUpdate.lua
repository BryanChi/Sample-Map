-- Update mechanism for Sample Map Browser (mirrors Vertical FX List's Update.lua).
-- Downloads files from BryanChi/Sample-Map. Uses GitHub releases when present,
-- otherwise the main branch (pinned to the commit seen by the update check).
--
-- All network work runs in background processes and is polled from the
-- script's defer loop (SampleMapAutoCheckForUpdates -> SampleMapUpdateTick),
-- so REAPER's UI never blocks on curl. Updates are all-or-nothing: every file
-- is downloaded to "<file>.new" and validated first, then all are renamed into
-- place (keeping "<file>.bak"), with rollback if any rename fails.
-- Note: assets/ (icons) is not updated by this mechanism.

if not r then r = reaper end

SAMPLE_MAP_UPDATE_REPO = {
  user = "BryanChi",
  repo = "Sample-Map",
  branch = "main",
}

SampleMapUpdateState = SampleMapUpdateState or {
  checking = false,
  downloading = false,
  progress = 0.0,
  status_message = "",
  error_message = "",
  latest_release_tag = nil,
  current_release_tag = nil,
  selected_release_tag = nil,
  latest_commit_sha = nil,
  current_commit_sha = nil,
  releases = {},
  update_available = false,
  auto_checked = false,
  show_update_icon = false,
  using_branch = false,
}

local function path_sep()
  return (r.GetOS() or ""):match("Win") and "\\" or "/"
end

local function normalize_path(path)
  local sep = path_sep()
  return path:gsub("/", sep):gsub("\\", sep)
end

local function dir_of(filepath)
  local sep = path_sep()
  return filepath:match("^(.+)" .. sep .. "[^" .. sep .. "]+$") or ""
end

local function ensure_dir(dir_path)
  if not dir_path or dir_path == "" then
    return true
  end
  return r.RecursiveCreateDirectory(normalize_path(dir_path), 0) ~= nil
end

local function url_encode(str)
  if not str then return "" end
  local parts = {}
  for part in str:gmatch("([^/]+)") do
    part = part:gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    parts[#parts + 1] = part
  end
  return table.concat(parts, "/")
end

local function script_dir()
  return SAMPLE_MAP_SCRIPT_DIR or SCRIPT_DIR or ""
end

local function version_file_path()
  local dir = script_dir()
  if dir == "" then return nil end
  return dir .. path_sep() .. "version.txt"
end

local function is_windows()
  return (r.GetOS() or ""):match("Win") ~= nil
end

local function now_s()
  return (r.time_precise and r.time_precise()) or os.clock()
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

-- --- Background process helper ----------------------------------------------
-- Each command runs from a small sh/batch script launched without waiting
-- (ExecProcess timeout -1 / -2). The script writes the command's exit code to
-- <base>.rc when it finishes; callers poll for that file on later defer ticks.

local bg_counter = 0

local function bg_tmp_dir()
  local base = (r.GetResourcePath and r.GetResourcePath()) or ""
  if base == "" then
    base = script_dir()
  end
  local dir = base .. "/Data/SampleMap/tmp"
  ensure_dir(dir)
  return dir
end

local function bg_unique_base(prefix)
  bg_counter = bg_counter + 1
  local t = now_s()
  return string.format(
    "%s/%s_%d_%06d_%d_%05d",
    bg_tmp_dir(), prefix or "job", os.time(), math.floor((t % 1) * 1000000), bg_counter, math.random(0, 99999)
  )
end

-- Quote one argument for the generated script (sh or cmd batch file).
local function bg_quote(s)
  s = tostring(s or "")
  if is_windows() then
    -- Batch files expand %VAR%; double each % so URLs like %20 survive.
    local q = s:gsub('"', ""):gsub("%%", "%%%%")
    return '"' .. q .. '"'
  end
  local q = s:gsub("'", "'\\''")
  return "'" .. q .. "'"
end

local function bg_win_path(s)
  local q = tostring(s or ""):gsub("/", "\\"):gsub("%%", "%%%%")
  return '"' .. q .. '"'
end

local function curl_bin()
  return is_windows() and "curl" or "/usr/bin/curl"
end

-- Start `cmd` (arguments already quoted with bg_quote) in the background.
-- Returns a job table, or nil + error.
local function bg_start(cmd, timeout_s)
  if not r.ExecProcess then
    return nil, "ExecProcess is unavailable"
  end
  local base = bg_unique_base("upd")
  local job = {
    rc_path = base .. ".rc",
    started = now_s(),
    timeout = timeout_s or 60,
  }
  local body, launch, wait_mode
  if is_windows() then
    job.script_path = base .. ".bat"
    body = table.concat({
      "@echo off",
      "chcp 65001 >nul",
      cmd,
      "(echo %ERRORLEVEL%)> " .. bg_win_path(job.rc_path .. ".tmp"),
      "move /Y " .. bg_win_path(job.rc_path .. ".tmp") .. " " .. bg_win_path(job.rc_path) .. " >nul",
      "",
    }, "\r\n")
    local script_win = job.script_path:gsub("/", "\\")
    launch = 'cmd.exe /C ""' .. script_win .. '""'
    wait_mode = -2 -- no wait, minimized console
  else
    job.script_path = base .. ".sh"
    body = table.concat({
      cmd,
      "echo $? > " .. bg_quote(job.rc_path .. ".tmp"),
      "mv -f " .. bg_quote(job.rc_path .. ".tmp") .. " " .. bg_quote(job.rc_path),
      "",
    }, "\n")
    launch = '/bin/sh "' .. job.script_path .. '"'
    wait_mode = -1 -- no wait
  end
  local fh = io.open(job.script_path, "wb")
  if not fh then
    return nil, "Could not write temp script in " .. bg_tmp_dir()
  end
  fh:write(body)
  fh:close()
  local ok = pcall(r.ExecProcess, launch, wait_mode)
  if not ok then
    os.remove(job.script_path)
    return nil, "Could not start background process"
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

-- Run curl in the background, writing the response body to out_path.
local function bg_curl(url, out_path, opts)
  opts = opts or {}
  local max_time = opts.max_time or 20
  local parts = {
    bg_quote(curl_bin()),
    "-s", "-S",
    "--connect-timeout", tostring(opts.connect_timeout or 8),
    "--max-time", tostring(max_time),
  }
  if opts.follow then
    parts[#parts + 1] = "-L"
  end
  if opts.fail then
    parts[#parts + 1] = "-f"
  end
  if opts.api then
    parts[#parts + 1] = "-H"
    parts[#parts + 1] = bg_quote("Accept: application/vnd.github.v3+json")
  end
  parts[#parts + 1] = "-o"
  parts[#parts + 1] = bg_quote(out_path)
  if opts.code_path then
    -- HTTP status goes to stdout, captured in code_path.
    parts[#parts + 1] = "-w"
    parts[#parts + 1] = bg_quote("%{http_code}")
  end
  parts[#parts + 1] = bg_quote(url)
  local cmd = table.concat(parts, " ")
  local stdout_target = opts.code_path and bg_quote(opts.code_path) or (is_windows() and "nul" or "/dev/null")
  if is_windows() then
    cmd = cmd .. " >" .. stdout_target .. " 2>nul"
  else
    cmd = cmd .. " >" .. stdout_target .. " 2>/dev/null"
  end
  return bg_start(cmd, max_time + 10)
end

local function strip_json_prefix(result)
  if result and result ~= "" then
    local json_start = result:find("[%[%{]")
    if json_start and json_start > 1 then
      result = result:sub(json_start)
    end
  end
  return result
end

-- Downloads use the commit seen by the check in branch mode, so every file in
-- one update comes from the same revision even if main moves meanwhile.
local function raw_base()
  local st = SampleMapUpdateState
  local ref = st.selected_release_tag or st.latest_release_tag or SAMPLE_MAP_UPDATE_REPO.branch
  if st.using_branch and ref == SAMPLE_MAP_UPDATE_REPO.branch
      and type(st.latest_commit_sha) == "string" and st.latest_commit_sha:match("^%x+$")
      and #st.latest_commit_sha >= 7 then
    ref = st.latest_commit_sha
  end
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s",
    SAMPLE_MAP_UPDATE_REPO.user,
    SAMPLE_MAP_UPDATE_REPO.repo,
    ref
  )
end

local function releases_url()
  return string.format(
    "https://api.github.com/repos/%s/%s/releases",
    SAMPLE_MAP_UPDATE_REPO.user,
    SAMPLE_MAP_UPDATE_REPO.repo
  )
end

local function commits_url()
  return string.format(
    "https://api.github.com/repos/%s/%s/commits?sha=%s&per_page=1",
    SAMPLE_MAP_UPDATE_REPO.user,
    SAMPLE_MAP_UPDATE_REPO.repo,
    SAMPLE_MAP_UPDATE_REPO.branch
  )
end

local function parse_releases(result)
  result = strip_json_prefix(result)
  if not result or result == "" then
    return nil, "Failed to fetch releases"
  end
  if result:match('"message"') and result:match('"documentation_url"') then
    return nil, result:match('"message":"([^"]+)"') or "GitHub API error"
  end
  if not result:match("^%s*%[") then
    return nil, "Invalid releases response"
  end

  local releases = {}
  local pos = 1
  while true do
    local tag_start = result:find('"tag_name"', pos)
    if not tag_start then break end
    local colon = result:find(":", tag_start)
    if not colon then break end
    local quote = colon + 1
    while quote <= #result and result:sub(quote, quote):match("%s") do
      quote = quote + 1
    end
    if result:sub(quote, quote) == '"' then
      local tag_end = result:find('"', quote + 1)
      if tag_end then
        local tag = result:sub(quote + 1, tag_end - 1)
        releases[#releases + 1] = {
          tag = tag,
          version = tag:match("^v?(.+)$") or tag,
        }
      end
    end
    pos = tag_start + 10
  end
  return releases, nil
end

local function parse_commit_sha(result)
  result = strip_json_prefix(result)
  if not result or result == "" then
    return nil
  end
  local sha = result:match('"sha"%s*:%s*"([0-9a-fA-F]+)"')
  if sha and #sha >= 7 then
    return sha
  end
  return nil
end

local function read_version_file()
  local path = version_file_path()
  if not path then return nil, nil end
  local file = io.open(path, "r")
  if not file then return nil, nil end
  local content = file:read("*all") or ""
  file:close()
  local tag = content:match("release%s*:%s*([^\n]+)")
  local sha = content:match("commit%s*:%s*([^\n]+)")
  if tag then tag = tag:gsub("%s+$", "") end
  if sha then sha = sha:gsub("%s+$", "") end
  return tag, sha
end

local function save_version_file(tag, sha)
  local path = version_file_path()
  if not path then return false end
  local file = io.open(path, "w")
  if not file then return false end
  file:write("release: " .. tostring(tag or SAMPLE_MAP_UPDATE_REPO.branch) .. "\n")
  if sha and sha ~= "" then
    file:write("commit: " .. sha .. "\n")
  end
  file:close()
  return true
end

-- url_path is relative to the GitHub repo root.
-- dest_path is relative to SCRIPT_DIR unless resource = true (then REAPER resource path).
-- Files that are not required may be missing (HTTP 404) from an older release;
-- they are then skipped instead of failing the whole update.
local FILES_TO_UPDATE = {
  { url = "Sample Map Browser.lua", required = true },
  { url = "Sample Map - Quick swap for selected item.lua" },
  { url = "CRS_Extract drum pattern and put into sample map sequencer.lua" },
  { url = "SampleMapStemImport.lua" },
  { url = "SampleMapAnalyzer.py" },
  { url = "SampleMapDrumAI.py" },
  { url = "SampleMapGrooveMIDI.py" },
  { url = "tag_presets.default.lua" },
  { url = "SampleMapUpdate.lua", required = true },
  { url = "Effects/SampleMapMIDI.jsfx", dest = "Effects/SampleMapMIDI.jsfx", resource = true },
  { url = "Effects/SampleMapPlayer.jsfx", dest = "Effects/SampleMapPlayer.jsfx", resource = true },
  { url = "Effects/SampleMapPreview.jsfx", dest = "Effects/SampleMapPreview.jsfx", resource = true },
}

-- --- Update check (asynchronous) ---------------------------------------------

local function finish_check(st, releases, sha, network_ok)
  if releases and #releases > 0 then
    st.using_branch = false
    st.releases = releases
    st.latest_release_tag = releases[1].tag
    if not st.selected_release_tag then
      st.selected_release_tag = releases[1].tag
    end
    st.update_available = (not st.current_release_tag) or (st.current_release_tag ~= st.latest_release_tag)
  else
    st.using_branch = true
    st.latest_commit_sha = sha
    st.latest_release_tag = SAMPLE_MAP_UPDATE_REPO.branch
    st.releases = {
      {
        tag = SAMPLE_MAP_UPDATE_REPO.branch,
        version = SAMPLE_MAP_UPDATE_REPO.branch,
      },
    }
    st.selected_release_tag = SAMPLE_MAP_UPDATE_REPO.branch
    if not network_ok then
      -- Offline / GitHub unreachable: don't claim an update is available.
      st.update_available = false
    elseif not sha then
      st.update_available = st.current_release_tag == nil
    elseif not st.current_commit_sha then
      st.update_available = true
    else
      st.update_available = st.current_commit_sha:sub(1, 7) ~= sha:sub(1, 7)
    end
  end

  st.show_update_icon = st.update_available and true or false
  if st._check_show_status then
    if not network_ok and not (releases and #releases > 0) then
      st.status_message = "Could not reach GitHub to check for updates."
    elseif st.update_available then
      st.status_message = string.format("Update available (%s)", st.latest_release_tag or "main")
    else
      st.status_message = string.format("You are up to date (%s)", st.current_release_tag or st.latest_release_tag or "main")
    end
  else
    st.status_message = ""
  end
  st.checking = false
  st.progress = 0.0
  st.auto_checked = true
end

local function start_api_job(st, phase, url)
  local out_path = bg_unique_base("api") .. ".json"
  local job, err = bg_curl(url, out_path, { api = true, connect_timeout = 5, max_time = 15 })
  if not job then
    return false, err
  end
  st._job = { kind = "check", phase = phase, bg = job, out_path = out_path }
  return true
end

local function handle_check_job(st, job, status, rc)
  local body = nil
  if status == "done" and rc == 0 then
    body = read_file(job.out_path)
  end
  os.remove(job.out_path)
  if job.phase == "releases" then
    st._check_network_ok = body ~= nil and body ~= ""
    local releases = body and parse_releases(body) or nil
    if releases and #releases > 0 then
      finish_check(st, releases, nil, true)
      return
    end
    local ok = start_api_job(st, "commits", commits_url())
    if not ok then
      finish_check(st, nil, nil, st._check_network_ok)
    end
    return
  end
  -- commits phase
  local sha = body and parse_commit_sha(body) or nil
  local network_ok = (body ~= nil and body ~= "") or st._check_network_ok
  finish_check(st, nil, sha, network_ok)
end

function SampleMapCheckForUpdates(show_status)
  local st = SampleMapUpdateState
  if st.checking or st.downloading then
    return
  end
  st.checking = true
  st.auto_checked = true
  st.error_message = ""
  st.status_message = show_status and "Checking for updates..." or ""
  st.progress = 0.0
  st._check_show_status = show_status and true or false
  st._check_network_ok = false

  local current_tag, current_sha = read_version_file()
  st.current_release_tag = current_tag
  st.current_commit_sha = current_sha

  local ok, err = start_api_job(st, "releases", releases_url())
  if not ok then
    st.checking = false
    if show_status then
      st.error_message = "Could not start update check: " .. tostring(err)
      st.status_message = ""
    end
  end
end

-- --- Update install (asynchronous, one file per job) -------------------------

local function cleanup_new_files(upd)
  for _, f in ipairs(upd.files) do
    os.remove(f.new_path)
    os.remove(f.code_path)
  end
end

local function validate_download(f)
  local size = file_size(f.new_path)
  if not size or size <= 0 then
    return false, "empty or missing download"
  end
  if f.new_path:match("%.lua%.new$") then
    local data = read_file(f.new_path) or ""
    local chunk, err = load(data, "@" .. f.url, "t")
    if not chunk then
      return false, "Lua syntax check failed: " .. tostring(err)
    end
  end
  return true
end

-- Rename every .new file into place, keeping .bak copies. Rolls back on failure.
local function install_downloads(upd)
  local installed = {}
  local failure = nil
  for _, f in ipairs(upd.files) do
    if f.skipped then
      goto continue
    end
    local had_orig = file_size(f.local_path) ~= nil
    if had_orig then
      os.remove(f.bak_path)
      local ok, err = os.rename(f.local_path, f.bak_path)
      if not ok then
        failure = string.format("%s: could not back up (%s)", f.url, tostring(err))
        break
      end
    end
    local ok, err = os.rename(f.new_path, f.local_path)
    if not ok then
      if had_orig then
        os.rename(f.bak_path, f.local_path)
      end
      failure = string.format("%s: could not install (%s)", f.url, tostring(err))
      break
    end
    installed[#installed + 1] = { file = f, had_orig = had_orig }
    ::continue::
  end
  if failure then
    for i = #installed, 1, -1 do
      local e = installed[i]
      if e.had_orig then
        os.remove(e.file.local_path)
        os.rename(e.file.bak_path, e.file.local_path)
      end
    end
    cleanup_new_files(upd)
    return false, failure
  end
  return true
end

local function fail_update(st, upd, msg)
  cleanup_new_files(upd)
  st._update = nil
  st._job = nil
  st.downloading = false
  st.progress = 0.0
  st.error_message = "Update failed; no files were changed.\n" .. tostring(msg)
  st.status_message = "Update failed"
end

local function start_next_download(st, upd)
  upd.index = upd.index + 1
  local total = #upd.files
  local f = upd.files[upd.index]
  if not f then
    st.status_message = "Installing files..."
    local ok, err = install_downloads(upd)
    st._update = nil
    st.downloading = false
    st.progress = 1.0
    if not ok then
      st.error_message = "Update failed; previous files were restored.\n" .. tostring(err)
      st.status_message = "Update failed"
      return
    end
    save_version_file(upd.tag, upd.sha)
    st.current_release_tag = upd.tag
    st.current_commit_sha = upd.sha
    st.update_available = false
    st.show_update_icon = false
    st.status_message = string.format(
      "Update complete (%s). Restart Sample Map Browser to load the new files.",
      tostring(upd.tag)
    )
    return
  end
  st.progress = (upd.index - 1) / total
  st.status_message = string.format("Downloading %d/%d: %s", upd.index, total, f.url)
  ensure_dir(dir_of(f.local_path))
  os.remove(f.new_path)
  local job, err = bg_curl(f.full_url, f.new_path, {
    follow = true,
    fail = true,
    connect_timeout = 10,
    max_time = 60,
    code_path = f.code_path,
  })
  if not job then
    fail_update(st, upd, f.url .. " (" .. tostring(err) .. ")")
    return
  end
  st._job = { kind = "download", bg = job, file = f }
end

local function handle_download_job(st, job, status, rc)
  local upd = st._update
  if not upd then
    return
  end
  local f = job.file
  if status == "timeout" then
    fail_update(st, upd, f.url .. " (timed out)")
    return
  end
  local http_code = tonumber(((read_file(f.code_path) or ""):match("%d+")))
  os.remove(f.code_path)
  if rc ~= 0 and http_code == 404 and not f.required then
    -- Not part of the selected version.
    f.skipped = true
    os.remove(f.new_path)
    start_next_download(st, upd)
    return
  end
  if rc ~= 0 then
    fail_update(st, upd, string.format("%s (curl exit code %s)", f.url, tostring(rc)))
    return
  end
  local ok, err = validate_download(f)
  if not ok then
    fail_update(st, upd, f.url .. " (" .. tostring(err) .. ")")
    return
  end
  start_next_download(st, upd)
end

function SampleMapPerformUpdate()
  local st = SampleMapUpdateState
  if st.downloading or st.checking then
    return
  end
  if not st.selected_release_tag then
    st.error_message = "Please select a version to install"
    return
  end
  local dir = script_dir()
  if dir == "" then
    st.error_message = "Could not determine script path"
    return
  end

  local sep = path_sep()
  local repo_base = raw_base()
  local resource = (r.GetResourcePath and r.GetResourcePath()) or ""
  local files = {}
  for _, entry in ipairs(FILES_TO_UPDATE) do
    local local_path
    if entry.resource then
      local_path = resource .. sep .. (entry.dest or entry.url):gsub("/", sep)
    else
      local rel = (entry.dest or entry.url):gsub("/", sep)
      local_path = dir .. sep .. rel
      -- Installer copies action scripts as CRS_<name>. If that file exists,
      -- update it instead of writing a second unprefixed copy.
      if rel:match("%.lua$") and not rel:match("[/\\]") and not rel:match("^CRS_") then
        local crs_path = dir .. sep .. "CRS_" .. rel
        local fh = io.open(crs_path, "rb")
        if fh then
          fh:close()
          local_path = crs_path
        end
      end
    end
    files[#files + 1] = {
      url = entry.url,
      full_url = repo_base .. "/" .. url_encode(entry.url),
      local_path = local_path,
      new_path = local_path .. ".new",
      code_path = bg_unique_base("http") .. ".txt",
      required = entry.required and true or false,
      bak_path = local_path .. ".bak",
    }
  end

  st.downloading = true
  st.error_message = ""
  st.progress = 0.0
  st.status_message = "Starting update..."
  st._update = {
    files = files,
    index = 0,
    tag = st.selected_release_tag,
    sha = st.using_branch and st.latest_commit_sha or nil,
  }
  start_next_download(st, st._update)
end

-- Poll the running background job (if any). Cheap when idle.
function SampleMapUpdateTick()
  local st = SampleMapUpdateState
  local job = st._job
  if not job then
    return
  end
  local status, rc = bg_poll(job.bg)
  if status == "running" then
    return
  end
  st._job = nil
  if job.kind == "check" then
    handle_check_job(st, job, status, rc)
  elseif job.kind == "download" then
    handle_download_job(st, job, status, rc)
  end
end

SampleMapAutoCheckForUpdates = function()
  local st = SampleMapUpdateState
  if not st.auto_checked and not st.checking and not st.downloading then
    SampleMapCheckForUpdates(false)
  end
  SampleMapUpdateTick()
end

function SampleMapOpenUpdateSettings()
  if not state then
    return
  end
  state.settings_open = true
  state.settings_section_open = state.settings_section_open or {}
  state.settings_section_open["Updates"] = true
end

function DrawSampleMapUpdateSettings(draw_ctx)
  local ctx = draw_ctx
  local st = SampleMapUpdateState
  if not st.current_release_tag and not st.current_commit_sha then
    local tag, sha = read_version_file()
    st.current_release_tag = tag
    st.current_commit_sha = sha
  end

  if st.current_release_tag then
    r.ImGui_Text(ctx, "Current version: " .. st.current_release_tag)
  else
    r.ImGui_Text(ctx, "Current version: unknown (not installed via updater)")
  end
  if st.latest_release_tag then
    local extra = ""
    if st.using_branch and st.latest_commit_sha then
      extra = " (" .. st.latest_commit_sha:sub(1, 7) .. ")"
    end
    r.ImGui_Text(ctx, "Latest: " .. st.latest_release_tag .. extra)
  end

  r.ImGui_Spacing(ctx)
  r.ImGui_Text(ctx, "Version to install:")
  local preview = "Select version…"
  local selected_index = 0
  if #st.releases > 0 then
    local selected = st.selected_release_tag or st.latest_release_tag
    for i, release in ipairs(st.releases) do
      if release.tag == selected then
        selected_index = i - 1
        preview = release.version or release.tag
        break
      end
    end
  elseif st.checking then
    preview = "Loading…"
  end

  r.ImGui_SetNextItemWidth(ctx, 250)
  if r.ImGui_BeginCombo(ctx, "##sample_map_version", preview) then
    for i, release in ipairs(st.releases) do
      local is_selected = (selected_index == i - 1)
      if r.ImGui_Selectable(ctx, release.version or release.tag, is_selected) then
        st.selected_release_tag = release.tag
      end
      if is_selected then
        r.ImGui_SetItemDefaultFocus(ctx)
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  if st.status_message ~= "" then
    r.ImGui_TextWrapped(ctx, st.status_message)
  end
  if st.error_message ~= "" then
    r.ImGui_TextColored(ctx, 0xFF6B6BFF, st.error_message)
  end

  if st.downloading or st.checking then
    r.ImGui_ProgressBar(ctx, st.progress, -1, 0, "")
  end

  r.ImGui_Spacing(ctx)
  if draw_ui_button then
    if draw_ui_button("sample_map_check_updates", "Check for updates", nil, 28, { compact = true }) then
      SampleMapCheckForUpdates(true)
    end
    if st.checking then
      r.ImGui_SameLine(ctx)
      r.ImGui_Text(ctx, "Checking…")
    end
    r.ImGui_Spacing(ctx)
    local can_install = st.selected_release_tag and #st.releases > 0 and not st.downloading and not st.checking
    if can_install then
      local label = st.update_available and "Download and update" or "Download and install"
      if draw_ui_button("sample_map_do_update", label, nil, 28, { compact = true, style = "primary" }) then
        SampleMapPerformUpdate()
      end
    elseif st.downloading then
      r.ImGui_Text(ctx, "Installing…")
    end
  end

  r.ImGui_Spacing(ctx)
  r.ImGui_TextWrapped(
    ctx,
    "Downloads the latest Sample Map files from GitHub. Restart the script after updating. Your sample library and settings are not overwritten."
  )
end

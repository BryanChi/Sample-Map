-- Update mechanism for Sample Map Browser (mirrors Vertical FX List's Update.lua).
-- Downloads files from BryanChi/Sample-Map. Uses GitHub releases when present,
-- otherwise the main branch.

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

local function curl_get(url, timeout_ms)
  local OS = r.GetOS() or ""
  local cmd
  if OS:match("Win") then
    cmd = string.format('curl -s -H "Accept: application/vnd.github.v3+json" "%s"', url)
  else
    cmd = string.format('/usr/bin/curl -s -H "Accept: application/vnd.github.v3+json" "%s"', url)
  end
  local result = r.ExecProcess(cmd, timeout_ms or 10000)
  if not result or result == "" or result == "-999" then
    local handle = io.popen(cmd, "r")
    if handle then
      result = handle:read("*a") or ""
      handle:close()
    end
  end
  if result and result ~= "" then
    local json_start = result:find("[%[%{]")
    if json_start and json_start > 1 then
      result = result:sub(json_start)
    end
  end
  return result
end

local function raw_base()
  local st = SampleMapUpdateState
  local ref = st.selected_release_tag or st.latest_release_tag or SAMPLE_MAP_UPDATE_REPO.branch
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s",
    SAMPLE_MAP_UPDATE_REPO.user,
    SAMPLE_MAP_UPDATE_REPO.repo,
    ref
  )
end

local function fetch_releases()
  local url = string.format(
    "https://api.github.com/repos/%s/%s/releases",
    SAMPLE_MAP_UPDATE_REPO.user,
    SAMPLE_MAP_UPDATE_REPO.repo
  )
  local result = curl_get(url, 10000)
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

local function fetch_latest_commit_sha()
  local url = string.format(
    "https://api.github.com/repos/%s/%s/commits?sha=%s&per_page=1",
    SAMPLE_MAP_UPDATE_REPO.user,
    SAMPLE_MAP_UPDATE_REPO.repo,
    SAMPLE_MAP_UPDATE_REPO.branch
  )
  local result = curl_get(url, 10000)
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

local function download_file(url, output_path)
  local OS = r.GetOS() or ""
  ensure_dir(dir_of(output_path))
  local escaped = output_path:gsub('"', '\\"')
  local cmd
  if OS:match("Win") then
    cmd = string.format('curl -L -f -s -S -o "%s" "%s" 2>&1', escaped, url)
  else
    cmd = string.format('/usr/bin/curl -L -f -s -S -o "%s" "%s" 2>&1', escaped, url)
  end
  local result = r.ExecProcess(cmd, 30000)
  local file = io.open(output_path, "rb")
  if file then
    local size = file:seek("end")
    file:close()
    if size and size > 0 then
      return true, nil
    end
  end
  if result and result ~= "" and result ~= "-999" then
    return false, result
  end
  return false, "Download failed: file not created or empty"
end

-- url_path is relative to the GitHub repo root.
-- dest_path is relative to SCRIPT_DIR unless resource = true (then REAPER resource path).
local FILES_TO_UPDATE = {
  { url = "Sample Map Browser.lua" },
  { url = "Sample Map - Quick swap for selected item.lua" },
  { url = "CRS_Extract drum pattern and put into sample map sequencer.lua" },
  { url = "SampleMapStemImport.lua" },
  { url = "SampleMapAnalyzer.py" },
  { url = "SampleMapDrumAI.py" },
  { url = "SampleMapGrooveMIDI.py" },
  { url = "SampleMapUpdate.lua" },
  { url = "Effects/SampleMapMIDI.jsfx", dest = "Effects/SampleMapMIDI.jsfx", resource = true },
  { url = "Effects/SampleMapPlayer.jsfx", dest = "Effects/SampleMapPlayer.jsfx", resource = true },
  { url = "Effects/SampleMapPreview.jsfx", dest = "Effects/SampleMapPreview.jsfx", resource = true },
}

function SampleMapCheckForUpdates(show_status)
  local st = SampleMapUpdateState
  if st.checking or st.downloading then
    return
  end
  st.checking = true
  st.error_message = ""
  st.status_message = show_status and "Checking for updates..." or ""
  st.progress = 0.0

  local current_tag, current_sha = read_version_file()
  st.current_release_tag = current_tag
  st.current_commit_sha = current_sha

  local releases = fetch_releases()
  if releases and #releases > 0 then
    st.using_branch = false
    st.releases = releases
    st.latest_release_tag = releases[1].tag
    if not st.selected_release_tag then
      st.selected_release_tag = releases[1].tag
    end
    st.update_available = (not current_tag) or (current_tag ~= st.latest_release_tag)
  else
    st.using_branch = true
    local sha = fetch_latest_commit_sha()
    st.latest_commit_sha = sha
    st.latest_release_tag = SAMPLE_MAP_UPDATE_REPO.branch
    st.releases = {
      {
        tag = SAMPLE_MAP_UPDATE_REPO.branch,
        version = SAMPLE_MAP_UPDATE_REPO.branch,
      },
    }
    st.selected_release_tag = SAMPLE_MAP_UPDATE_REPO.branch
    if not sha then
      st.update_available = current_tag == nil
    elseif not current_sha then
      st.update_available = true
    else
      st.update_available = current_sha:sub(1, 7) ~= sha:sub(1, 7)
    end
  end

  st.show_update_icon = st.update_available and true or false
  if show_status then
    if st.update_available then
      st.status_message = string.format("Update available (%s)", st.latest_release_tag or "main")
    else
      st.status_message = string.format("You are up to date (%s)", st.current_release_tag or st.latest_release_tag or "main")
    end
  else
    st.status_message = ""
  end
  st.checking = false
  st.auto_checked = true
end

SampleMapAutoCheckForUpdates = function()
  if SampleMapUpdateState.auto_checked then
    return
  end
  SampleMapCheckForUpdates(false)
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

  st.downloading = true
  st.error_message = ""
  st.progress = 0.0
  st.status_message = "Starting update..."

  local sep = path_sep()
  local repo_base = raw_base()
  local resource = (r.GetResourcePath and r.GetResourcePath()) or ""
  local total = #FILES_TO_UPDATE
  local success_count = 0
  local failed = {}

  for i, entry in ipairs(FILES_TO_UPDATE) do
    st.progress = (i - 1) / total
    st.status_message = string.format("Downloading %d/%d: %s", i, total, entry.url)
    local full_url = repo_base .. "/" .. url_encode(entry.url)
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
    local ok, err = download_file(full_url, local_path)
    if ok then
      success_count = success_count + 1
    else
      failed[#failed + 1] = entry.url .. " (" .. (err or "unknown error") .. ")"
    end
  end

  st.progress = 1.0
  if success_count == total then
    save_version_file(st.selected_release_tag, st.latest_commit_sha)
    st.current_release_tag = st.selected_release_tag
    st.current_commit_sha = st.latest_commit_sha
    st.update_available = false
    st.show_update_icon = false
    st.status_message = string.format(
      "Update complete (%s). Restart Sample Map Browser to load the new files.",
      st.selected_release_tag
    )
  else
    st.error_message = string.format(
      "Update partially completed (%d/%d).\n%s",
      success_count,
      total,
      table.concat(failed, "\n")
    )
    st.status_message = "Update completed with errors"
  end
  st.downloading = false
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
    local can_install = st.selected_release_tag and #st.releases > 0 and not st.downloading
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

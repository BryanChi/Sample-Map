-- Sample Map Browser module: helpers
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Helper functions ---------------------------------------------------------
function log(msg)
  -- Bounded in-memory ring buffer (last 200 lines); read via sm_error_log_lines().
  local buf = state.error_log
  if type(buf) ~= "table" or type(buf.lines) ~= "table" then
    buf = { lines = {}, next = 1, count = 0, max = 200 }
    state.error_log = buf
  end
  buf.lines[buf.next] = tostring(msg)
  buf.next = (buf.next % buf.max) + 1
  if buf.count < buf.max then
    buf.count = buf.count + 1
  end
end

function sm_error_log_lines()
  local buf = state.error_log
  local out = {}
  if type(buf) ~= "table" or type(buf.lines) ~= "table" then
    return out
  end
  local start = (buf.count < buf.max) and 1 or buf.next
  for i = 0, buf.count - 1 do
    out[#out + 1] = buf.lines[((start - 1 + i) % buf.max) + 1]
  end
  return out
end

function sm_error_traceback(err)
  if debug and debug.traceback then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

-- Log every error; show the first one from each site in the REAPER console.
-- Short on-screen message for actions that would otherwise do nothing
-- visibly ("no matching samples", "track has no sample"...). Drawn by
-- sm_draw_toast at the bottom of the main window; also kept in the log.
-- kind: "info" (default), "warn" or "error".
SM_TOAST_SECONDS = 3.2

function sm_notify(msg, kind)
  if msg == nil or msg == "" then
    return
  end
  msg = tostring(msg)
  log(msg)
  local now = (r.time_precise and r.time_precise()) or os.clock()
  local t = state.sm_toast
  if t and t.text == msg and (now - (t.t or 0)) < SM_TOAST_SECONDS then
    -- Same message again: keep it up instead of restarting the fade.
    t.t = now
    t.count = (t.count or 1) + 1
    return
  end
  state.sm_toast = { text = msg, kind = kind or "info", t = now, count = 1 }
end

function sm_draw_toast()
  local t = state.sm_toast
  if not t or not ctx then
    return
  end
  local now = r.time_precise()
  local age = now - (t.t or 0)
  if age >= SM_TOAST_SECONDS then
    state.sm_toast = nil
    return
  end
  local rect = state.main_window_rect
  if not rect or not r.ImGui_GetForegroundDrawList then
    return
  end
  local alpha = 1.0
  if age > SM_TOAST_SECONDS - 0.6 then
    alpha = math.max(0, (SM_TOAST_SECONDS - age) / 0.6)
  end
  local function fade(col)
    local a = col & 0xFF
    return (col & 0xFFFFFF00) | math.floor(a * alpha + 0.5)
  end
  local text = t.text
  if (t.count or 1) > 1 then
    text = text .. string.format("  (x%d)", t.count)
  end
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local pad_x, pad_y = 14, 8
  local w, h = tw + pad_x * 2, th + pad_y * 2
  local x0 = rect.x + math.max(8, (rect.w - w) * 0.5)
  local y0 = rect.y + rect.h - h - 18
  local dl = r.ImGui_GetForegroundDrawList(ctx)
  local accent = (t.kind == "error" and UI_THEME.danger)
    or (t.kind == "warn" and 0xFFB870FF)
    or UI_THEME.accent
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0 + 2, x0 + w, y0 + h + 2, fade(0x00000080), 7)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, fade(UI_THEME.elevated), 7)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, fade(UI_THEME.border_hvr), 7, 0, 1)
  r.ImGui_DrawList_AddRectFilled(dl, x0 + 5, y0 + 6, x0 + 8, y0 + h - 6, fade(accent), 1.5)
  r.ImGui_DrawList_AddText(dl, x0 + pad_x, y0 + pad_y, fade(UI_THEME.text), text)
end

function sm_report_error(site, err)
  site = tostring(site or "?")
  log("[error] " .. site .. ": " .. tostring(err))
  state.sm_error_sites = state.sm_error_sites or {}
  if state.sm_error_sites[site] then
    return
  end
  state.sm_error_sites[site] = true
  if r.ShowConsoleMsg then
    r.ShowConsoleMsg(string.format(
      "[Sample Map] Error in %s (repeats are only logged):\n%s\n\n", site, tostring(err)
    ))
  end
end

-- xpcall with traceback + reporting. Returns ok, results...
function sm_pcall(site, fn, ...)
  if type(fn) ~= "function" then
    return true -- optional hook not defined: nothing to run
  end
  local res = table.pack(xpcall(fn, sm_error_traceback, ...))
  if not res[1] then
    sm_report_error(site, res[2])
  end
  return table.unpack(res, 1, res.n)
end

function add_scan_log(msg)
  local timestamp = os.date("%H:%M:%S")
  local line = string.format("[%s] %s", timestamp, tostring(msg))
  table.insert(state.scan_logs, line)
  if #state.scan_logs > 500 then
    table.remove(state.scan_logs, 1)
  end
end

function get_scan_logs_text()
  return table.concat(state.scan_logs, "\n")
end


SM_IS_WINDOWS = (package and package.config and package.config:sub(1, 1) == "\\") or false

function shell_escape(str)
  str = tostring(str)
  if SM_IS_WINDOWS then
    -- cmd.exe: double quotes; '"' is not a legal filename character on Windows, so drop it.
    return '"' .. str:gsub('"', "") .. '"'
  end
  -- POSIX sh: single quotes disable $(), backticks and every other expansion.
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

-- Write `content` to `path` atomically: write path.tmp, keep the previous file as
-- path.bak, then rename the temp file into place. Returns true or false, err.
function sm_atomic_write(path, content)
  if type(content) ~= "string" then
    return false, "content is not a string"
  end
  local tmp = path .. ".tmp"
  local f, open_err = io.open(tmp, "wb")
  if not f then
    return false, "cannot open " .. tmp .. ": " .. tostring(open_err)
  end
  local ok_w, write_err = f:write(content)
  local ok_c, close_err = f:close()
  if not ok_w or not ok_c then
    os.remove(tmp)
    return false, "write failed: " .. tostring(write_err or close_err)
  end
  local bak = path .. ".bak"
  local cur = io.open(path, "rb")
  if cur then
    local size = cur:seek("end") or 0
    cur:close()
    if size > 0 then
      os.remove(bak)
      os.rename(path, bak)
    end
  end
  local ok_r, rename_err = os.rename(tmp, path)
  if not ok_r then
    -- Windows cannot rename over an existing file.
    os.remove(path)
    ok_r, rename_err = os.rename(tmp, path)
  end
  if not ok_r then
    local chk = io.open(path, "rb")
    if chk then
      chk:close()
    else
      os.rename(bak, path)
    end
    return false, "rename failed: " .. tostring(rename_err)
  end
  return true
end

-- Read a whole file; nil when missing or empty.
function sm_read_nonempty_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    return nil
  end
  return content
end


-- Normalize path separators for macOS (ensure forward slashes)
function normalize_path(path)
  if not path or path == "" then
    return path
  end
  -- Replace backslashes with forward slashes
  path = path:gsub("\\", "/")
  -- Remove trailing slash
  path = path:gsub("/+$", "")
  return path
end

-- Removable / external volume root for a path.
-- macOS: /Volumes/DriveName/...  Windows: E:/...
-- Internal paths (/Users/..., C:/Users/...) return nil — always treated as local.
function volume_root_from_path(path)
  path = normalize_path(path or "")
  if path == "" then
    return nil
  end
  local vol = path:match("^(/Volumes/[^/]+)")
  if vol then
    return vol
  end
  -- Windows drive letters other than C: are commonly removable/external.
  local drive = path:match("^([A-Za-z]):")
  if drive and drive:upper() ~= "C" then
    return drive:upper() .. ":/"
  end
  return nil
end

function volume_is_mounted_scan(vol_name)
  local i = 0
  while true do
    local name = r.EnumerateSubdirectories("/Volumes", i)
    if not name then
      break
    end
    if name == vol_name then
      return true
    end
    i = i + 1
  end
  return false
end

function volume_is_mounted(vol_root)
  vol_root = normalize_path(vol_root or "")
  if vol_root == "" then
    return true
  end

  local vol_name = vol_root:match("^/Volumes/(.+)$")
  if vol_name then
    -- refresh_scan_folder_availability asks once per scan folder and once per
    -- volume; reuse one /Volumes listing for the duration of that refresh.
    local memo = sm_volume_list_memo
    if not memo or (r.time_precise() - memo.t) > 0.25 then
      return volume_is_mounted_scan(vol_name)
    end
    local hit = memo.names[vol_name]
    if hit == nil then
      hit = volume_is_mounted_scan(vol_name)
      memo.names[vol_name] = hit
    end
    return hit
  end

  -- Windows drive root (e.g. "E:/"): present if we can see any entry or rename succeeds.
  local drive = vol_root:match("^([A-Za-z]:)/?$")
  if drive then
    local root = drive:upper() .. ":/"
    if r.file_exists(root) then
      return true
    end
    if r.EnumerateFiles(root, 0) ~= nil or r.EnumerateSubdirectories(root, 0) ~= nil then
      return true
    end
    local ok, _, code = os.rename(root, root)
    if ok or code == 13 then
      return true
    end
    return false
  end

  return true
end

-- True when a folder path is present. Avoids the old pcall(Enumerate*) bug that
-- treated missing paths as existing (Enumerate returns nil, it does not throw).
function scan_folder_path_exists(path)
  if not path or path == "" then
    return false
  end
  path = normalize_path(path)

  local vol = volume_root_from_path(path)
  if vol and not volume_is_mounted(vol) then
    return false
  end

  if r.file_exists(path) then
    return true
  end
  if r.EnumerateFiles(path, 0) ~= nil or r.EnumerateSubdirectories(path, 0) ~= nil then
    return true
  end

  -- Empty-but-present directories: rename-to-self is a portable exists probe.
  local ok, _, code = os.rename(path, path)
  if ok or code == 13 then
    return true
  end
  return false
end

-- Case-insensitive in-place sort of a list of strings. Same order as sorting
-- with string.lower(a) < string.lower(b), but lowercases each name once
-- instead of twice per comparison.
function sm_sort_ci(list)
  if #list < 2 then
    return list
  end
  local key = {}
  for i = 1, #list do
    local s = list[i]
    if key[s] == nil then
      key[s] = string.lower(s)
    end
  end
  table.sort(list, function(a, b) return key[a] < key[b] end)
  return list
end

function sample_under_scan_folder(sample_path, folder_path)
  local norm_sample = normalize_path(sample_path or "")
  local norm_folder = normalize_path(folder_path or "")
  if norm_sample == "" or norm_folder == "" then
    return false
  end
  if norm_sample == norm_folder then
    return true
  end
  return norm_sample:sub(1, #norm_folder + 1) == norm_folder .. "/"
end

function get_sample_scan_root(sample_path)
  local best_root = nil
  local best_len = 0
  for _, folder in ipairs(state.folders) do
    local norm_folder = normalize_path(folder)
    if sample_under_scan_folder(sample_path, norm_folder) and #norm_folder > best_len then
      best_root = norm_folder
      best_len = #norm_folder
    end
  end
  return best_root
end

function availability_signature(missing_folders, missing_volumes)
  local parts = {}
  for folder in pairs(missing_folders or {}) do
    parts[#parts + 1] = "f:" .. folder
  end
  for vol in pairs(missing_volumes or {}) do
    parts[#parts + 1] = "v:" .. vol
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

function refresh_scan_folder_availability()
  local missing_folders = {}
  local missing_volumes = {}
  local volumes = {}
  sm_volume_list_memo = { t = r.time_precise(), names = {} }

  for _, folder in ipairs(state.folders) do
    local norm_folder = normalize_path(folder)
    local vol = volume_root_from_path(norm_folder)
    if vol then
      volumes[vol] = true
    end
    if not scan_folder_path_exists(norm_folder) then
      missing_folders[norm_folder] = true
    end
  end

  for vol in pairs(volumes) do
    if not volume_is_mounted(vol) then
      missing_volumes[vol] = true
    end
  end

  sm_volume_list_memo = nil
  local prev_sig = availability_signature(state.missing_scan_folders, state.missing_volumes)
  local new_sig = availability_signature(missing_folders, missing_volumes)
  state.missing_scan_folders = missing_folders
  state.missing_volumes = missing_volumes
  state.last_volume_check_time = r.time_precise()

  if new_sig ~= prev_sig then
    seq_path_exists_cache = {}
    seq_sample_len_sec_cache = {}
    state.map_availability_epoch = (state.map_availability_epoch or 0) + 1
    local missing_names = {}
    for folder in pairs(missing_folders) do
      missing_names[#missing_names + 1] = folder
    end
    table.sort(missing_names)
    local vol_names = {}
    for vol in pairs(missing_volumes) do
      vol_names[#vol_names + 1] = vol
    end
    table.sort(vol_names)
    if #vol_names > 0 then
      log(string.format(
        "Removable drive(s) offline (%d): %s — graying out dots",
        #vol_names,
        table.concat(vol_names, ", ")
      ))
    elseif #missing_names > 0 then
      log(string.format(
        "Unavailable scan folder(s) (%d): %s",
        #missing_names,
        table.concat(missing_names, ", ")
      ))
    else
      log("All scan folders / removable drives are available again")
    end
    state._clear_vary_rank_cache = true
    return true
  end
  return false
end

function sample_scan_folder_unavailable(sample)
  if not sample or not sample.path then
    return false
  end
  -- Only a missing volume or scan folder can make a sample unavailable; skip
  -- the per-folder path normalization when nothing is missing (the usual case).
  if next(state.missing_volumes) == nil and next(state.missing_scan_folders) == nil then
    return false
  end
  local vol = volume_root_from_path(sample.path)
  if vol and state.missing_volumes[vol] then
    return true
  end
  local root = get_sample_scan_root(sample.path)
  if root and state.missing_scan_folders[root] then
    return true
  end
  return false
end

-- Map X-axis / sequencer cap: audible length when analyzed, else full file length.
function sample_map_duration(sample)
  if sample and type(sample.effective_duration) == "number" and sample.effective_duration > 0 then
    return sample.effective_duration
  end
  if sample and type(sample.duration) == "number" and sample.duration > 0 then
    return sample.duration
  end
  return 0
end

-- Get filename without path
function basename(path)
  if not path then return "" end
  local norm = normalize_path(path)
  return norm:match("([^/]+)$") or norm
end

-- Set media take name with logging (preferred) and fallback to item name
function set_item_name(item, take, sample_path)
  if (not item and not take) or not sample_path then
    log("set_item_name: missing item/take or path")
    return
  end
  local name = basename(sample_path)
  local ok_take = nil
  if take then
    ok_take = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  end
  local ok_item = nil
  if item then
    ok_item = r.GetSetMediaItemInfo_String(item, "P_NAME", name, true)
  end
  log(string.format("Naming to '%s' take_result=%s item_result=%s", name, tostring(ok_take), tostring(ok_item)))
end


-- Build ARGB color from RGB components (0-255)
function build_color(r, g, b, a)
  a = a or 255
  return 0xFF000000 | (math.floor(r) << 16) | (math.floor(g) << 8) | math.floor(b)
end

-- Extract RGB components from RRGGBBAA format color
function extract_rgb_rrgbbaa(color)
  if not color then return 0, 0, 0 end
  local r = math.floor((color / 16777216) % 256)   -- Extract red (first byte)
  local g = math.floor((color / 65536) % 256)     -- Extract green
  local b = math.floor((color / 256) % 256)       -- Extract blue
  return r, g, b
end

-- Build RRGGBBAA color from RGB components (0-255) and alpha (0-255, default 255)
function build_color_rrgbbaa(r, g, b, a)
  a = a or 255
  return (math.floor(r) * 16777216) + (math.floor(g) * 65536) + (math.floor(b) * 256) + math.floor(a)
end

-- Extract RGB from RRGGBB color (24-bit)
function extract_rgb(color)
  if not color then return 0, 0, 0 end
  local r = math.floor((color / 65536) % 256)
  local g = math.floor((color / 256) % 256)
  local b = math.floor(color % 256)
  return r, g, b
end

-- Build RRGGBB color from RGB components (0-255)
function build_rgb(r, g, b)
  return (math.floor(r) * 65536) + (math.floor(g) * 256) + math.floor(b)
end



function pick_number(ret, default)
  default = default or 0.0
  if type(ret) == "number" then
    return ret
  elseif type(ret) == "table" then
    for _, v in ipairs(ret) do
      if type(v) == "number" then
        return v
      end
    end
  end
  return default
end


function pick_bool(ret, default)
  default = default or false
  if type(ret) == "boolean" then
    return ret
  elseif type(ret) == "table" then
    for _, v in ipairs(ret) do
      if type(v) == "boolean" then
        return v
      end
    end
  end
  return default
end


-- Detect loop vs one-shot. Strong filename keywords beat audio; audio beats
-- folder names. playback_type is analyzer output: "oneshot"|"loop"|"unknown"|nil.
-- nil = not analyzed yet (folder hints allowed); "unknown" = analyzed, leave untagged.
function detect_loop_or_oneshot(path, folder, playback_type)
  local path_lower = (path or ""):lower()
  local folder_lower = (folder or ""):lower()
  local filename = path_lower:match("([^/\\]+)$") or path_lower

  local function has_oneshot_keyword(s)
    if not s or s == "" then return false end
    return s:find("oneshot", 1, true)
      or s:find("one%-shot")
      or s:find("one_shot", 1, true)
      or s:find("1shot", 1, true)
      or s:find("one shot", 1, true)
  end

  local function filename_has_explicit_loop(name)
    if not name or name == "" then return false end
    if name:find("looped", 1, true) or name:find("lpd", 1, true) then
      return true
    end
    if name:find("[_%-]loop") or name:find("loop[_%-]") then
      return true
    end
    if name:find("%Wloop%W") or name:find("^loop%W") or name:find("%Wloop%.") or name:find("^loop%.") then
      return true
    end
    return false
  end

  if has_oneshot_keyword(filename) or has_oneshot_keyword(folder_lower) then
    return "One shot"
  end
  if filename_has_explicit_loop(filename) then
    return "loop"
  end

  if playback_type == "oneshot" then
    return "One shot"
  elseif playback_type == "loop" then
    return "loop"
  elseif playback_type == "unknown" then
    return nil
  end

  -- Weak filename hints only (not folders) while waiting for audio.
  if filename:find("%d+bpm") or filename:find("%d+_bpm") or filename:find("%d+%-bpm") then
    return "loop"
  end
  if filename:find("%d+bar") or filename:find("%d+_bar") or filename:find("%d+%-bar") then
    return "loop"
  end

  -- Folder "loop" / BPM packs: last-resort before analysis, never after.
  if folder_lower:find("loop") or folder_lower:find("looped") then
    return "loop"
  end
  if folder_lower:find("construction kit") then
    return "loop"
  end
  if folder_lower:find("%d+%s+bpm") or folder_lower:find("%d+%-bpm") then
    return "loop"
  end

  return nil
end

-- Replace loop/one-shot tags. kind is "loop", "One shot", or nil (strip only).
function apply_loop_oneshot_tag(sample, kind)
  if not sample then
    return false
  end
  sample.tags = sample.tags or {}
  local out = {}
  local changed = false
  for _, tag in ipairs(sample.tags) do
    local lower = string.lower(tostring(tag))
    if lower == "loop" or lower == "one shot" or lower == "oneshot" then
      changed = true
    else
      out[#out + 1] = tag
    end
  end
  if kind then
    local exists = false
    for _, tag in ipairs(out) do
      if tag == kind then
        exists = true
        break
      end
    end
    if not exists and not (tag_is_suppressed and tag_is_suppressed(kind)) then
      out[#out + 1] = kind
      changed = true
    end
  end
  sample.tags = out
  return changed
end


-- Extract meaningful tags from filename and folder tokens
function infer_tags_from_path(path, folder)
  local tokens = {}
  local function collect(str)
    if not str or str == "" then return end
    for token in tostring(str):lower():gmatch("%w+") do
      tokens[token] = true
    end
  end
  collect(path or "")
  collect(folder or "")

  local scored = {}
  for _, entry in ipairs(TAG_KEYWORDS) do
    for _, key in ipairs(entry.keys) do
      if tokens[key] then
        local current = scored[entry.tag] or 0
        if entry.weight > current then
          scored[entry.tag] = entry.weight
        end
        break
      end
    end
  end

  local sorted = {}
  for tag, weight in pairs(scored) do
    table.insert(sorted, {tag = tag, weight = weight})
  end
  table.sort(sorted, function(a, b)
    if a.weight == b.weight then
      return a.tag < b.tag
    end
    return a.weight > b.weight
  end)

  local tags = {}
  for _, entry in ipairs(sorted) do
    if not (tag_is_suppressed and tag_is_suppressed(entry.tag)) then
      tags[#tags + 1] = entry.tag
      if #tags >= 6 then break end -- Keep cache lean
    end
  end

  return tags
end


-- Match a genre key against a lowercased path/folder string using word-ish
-- boundaries so "house" does not match "warehouse".
-- Multi-word keys accept any punctuation/separator between parts:
--   deep house, deep.house, deep_house, deep-house, deep/house, deephouse
function genre_key_matches(haystack, key)
  if not haystack or not key or key == "" then
    return false
  end
  local parts = {}
  for part in tostring(key):lower():gmatch("%w+") do
    parts[#parts + 1] = part
  end
  if #parts == 0 then
    return false
  end

  local function bounded(pat)
    -- Plain substring with alphanumeric word boundaries (works at string ends too)
    local i = 1
    while true do
      local s, e = haystack:find(pat, i)
      if not s then
        return false
      end
      local before = (s == 1) and "" or haystack:sub(s - 1, s - 1)
      local after = (e == #haystack) and "" or haystack:sub(e + 1, e + 1)
      local before_ok = before == "" or not before:match("%w")
      local after_ok = after == "" or not after:match("%w")
      if before_ok and after_ok then
        return true
      end
      i = s + 1
    end
  end

  -- Separated form: deep house / deep.house / deep_house / deep-house / etc.
  -- [^%w]+ matches any run of non-alphanumeric chars (space, ., _, -, /, +, ...)
  if bounded(table.concat(parts, "[^%w]+")) then
    return true
  end

  -- Concatenated form: deephouse, futurebass, jerseyclub
  if #parts > 1 and bounded(table.concat(parts)) then
    return true
  end

  return false
end


-- Detect genre tags from pack/folder names (library-driven).
-- Uses directory context only — not the bare filename — so material words
-- like "metal" / "drill" in foley one-shots don't pollute the Library list.
-- Results are cached per directory path (many samples share the same folder).
_genre_tags_by_dir = {}

function clear_genre_tag_dir_cache()
  _genre_tags_by_dir = {}
end

function infer_genre_tags_from_path(path, folder)
  local dir = folder or ""
  if dir == "" and path and path ~= "" then
    dir = path:match("(.+)/[^/]+$") or ""
  end
  -- Include parent path directories when folder is only the leaf directory
  if path and path ~= "" then
    local parent = path:match("(.+)/[^/]+$")
    if parent and parent ~= "" then
      dir = parent
    end
  end
  local haystack = dir:lower()
  local cached = _genre_tags_by_dir[haystack]
  if cached then
    local copy = {}
    for i = 1, #cached do
      copy[i] = cached[i]
    end
    return copy
  end
  local tags = {}
  local seen = {}
  for _, entry in ipairs(GENRE_KEYWORDS) do
    for _, key in ipairs(entry.keys) do
      if genre_key_matches(haystack, key) then
        if not seen[entry.tag] and not (tag_is_suppressed and tag_is_suppressed(entry.tag)) then
          seen[entry.tag] = true
          tags[#tags + 1] = entry.tag
        end
        break
      end
    end
  end
  _genre_tags_by_dir[haystack] = tags
  local copy = {}
  for i = 1, #tags do
    copy[i] = tags[i]
  end
  return copy
end


-- Append tags that are not already present.
function append_unique_tags(tags, extra)
  if not tags then tags = {} end
  if not extra or #extra == 0 then return tags end
  local existing = {}
  for _, tag in ipairs(tags) do
    existing[tag] = true
  end
  for _, tag in ipairs(extra) do
    if tag and not existing[tag] and not (tag_is_suppressed and tag_is_suppressed(tag)) then
      tags[#tags + 1] = tag
      existing[tag] = true
    end
  end
  return tags
end


-- Recurring pack/vendor/folder tokens from the scanned library.
-- Curated GENRE_KEYWORDS still tag samples directly; this pass adds extra
-- Library chips (company names, pack folders, etc.) without feeding them
-- into sequencer kit-genre matching.
function apply_discovered_library_tags()
  local samples = state.samples
  if type(samples) ~= "table" or #samples == 0 then
    state.discovered_library_tag_set = {}
    return
  end

  local skip = {
    pack = true, packs = true, kit = true, kits = true, bundle = true, bundles = true,
    collection = true, collections = true, sample = true, samples = true, sampler = true,
    sound = true, sounds = true, audio = true, wav = true, wave = true, aiff = true,
    flac = true, mp3 = true, ogg = true, loop = true, loops = true, looping = true,
    oneshot = true, oneshots = true, one = true, shot = true, shots = true,
    drum = true, drums = true, drumkit = true, perc = true, percussion = true,
    fx = true, sfx = true, vocal = true, vocals = true, vox = true, voice = true,
    kick = true, kicks = true, snare = true, snares = true, clap = true, claps = true,
    snap = true, snaps = true, hat = true, hats = true, hihat = true, hihats = true,
    tom = true, toms = true, ride = true, rides = true, crash = true, crashes = true,
    cymbal = true, cymbals = true, rim = true, rims = true, bass = true, basses = true,
    lead = true, leads = true, pad = true, pads = true, pluck = true, plucks = true,
    key = true, keys = true, piano = true, pianos = true, guitar = true, guitars = true,
    inst = true, instrument = true, instruments = true, folder = true, folders = true,
    file = true, files = true, library = true, libraries = true, lib = true,
    download = true, downloads = true, new = true, final = true, demo = true, demos = true,
    bonus = true, extra = true, extras = true, preview = true, previews = true,
    stem = true, stems = true, midi = true, preset = true, presets = true,
    vol = true, volume = true, pt = true, part = true, version = true, ver = true,
    stereo = true, mono = true, multi = true, bpm = true, hz = true, khz = true,
    bit = true, bits = true, rate = true, the = true, ["and"] = true, ["for"] = true,
    from = true, with = true, you = true, your = true,
    this = true, that = true, all = true, any = true, untitled = true, copy = true,
    backup = true, old = true, temp = true, tmp = true, misc = true, other = true,
    various = true, users = true, user = true, documents = true, desktop = true,
    music = true, volumes = true, applications = true, application = true,
    support = true, reaper = true, scripts = true, home = true, content = true,
    contents = true, media = true, imported = true, import = true, export = true,
    project = true, projects = true, session = true, sessions = true,
    swell = true, ones = true, wavs = true, audiofiles = true,
    scene = true, discover = true,
  }
  for _, entry in ipairs(TAG_KEYWORDS) do
    skip[string.lower(entry.tag)] = true
    for _, key in ipairs(entry.keys) do
      skip[string.lower(key)] = true
    end
  end
  for _, entry in ipairs(GENRE_KEYWORDS) do
    skip[string.lower(entry.tag)] = true
    for _, key in ipairs(entry.keys) do
      if #key >= 3 then
        skip[string.lower(key)] = true
      end
    end
  end
  for tag, on in pairs(state.deleted_tags or {}) do
    if on then
      skip[string.lower(tostring(tag))] = true
    end
  end

  local core_keep = {
    loop = true, oneshot = true, ["one shot"] = true, drum = true, swell = true,
  }
  for _, entry in ipairs(TAG_KEYWORDS) do
    core_keep[string.lower(entry.tag)] = true
  end
  for tag, _ in pairs(GENRE_TAG_SET) do
    core_keep[tag] = true
  end

  local function is_junk_token(token)
    if not token or token == "" or skip[token] or core_keep[token] then
      return true
    end
    if #token < 3 or #token > 64 then
      return true
    end
    if token:match("^%d+$") or token:match("^v%d+$") or token:match("^vol%d+$") then
      return true
    end
    if token:match("^%d+bpm$") or token:match("^%d+k$") or token:match("^%d+hz$") or token:match("^%d+bit$") then
      return true
    end
    if token:match("^[a-g][#b]?min$") or token:match("^[a-g][#b]?maj$")
        or token:match("^[a-g]minor$") or token:match("^[a-g]major$") then
      return true
    end
    return false
  end

  local function scan_root_and_relative(path)
    path = normalize_path(path or "")
    local dir = path:match("(.+)/[^/]+$") or ""
    local best = ""
    for _, folder in ipairs(state.folders or {}) do
      local root = normalize_path(folder)
      if root ~= "" and (dir == root or dir:sub(1, #root + 1) == root .. "/") then
        if #root > #best then
          best = root
        end
      end
    end
    if best == "" then
      return "", dir
    end
    if dir == best then
      return best, ""
    end
    return best, dir:sub(#best + 2)
  end

  local function tokens_from_library_path(rel, root)
    local found = {}
    local function consider(token)
      token = tostring(token or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
      if is_junk_token(token) or found[token] then
        return
      end
      found[token] = true
    end
    local function add_segment(segment)
      local phrase = tostring(segment or ""):lower():gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
      if phrase == "" then
        return
      end
      local kept_words = {}
      for word in phrase:gmatch("%w+") do
        consider(word)
        if not is_junk_token(word) then
          kept_words[#kept_words + 1] = word
        end
      end
      -- Keep the original folder name when it has a distinctive word, so
      -- "Cymatics Lofi Pack" stays one chip instead of a stitched fragment.
      if phrase:find(" ", 1, true) and #kept_words >= 1 then
        consider(phrase)
      end
    end
    if root and root ~= "" then
      add_segment(root:match("([^/]+)$") or "")
    end
    for segment in tostring(rel or ""):gmatch("[^/]+") do
      add_segment(segment)
    end
    return found
  end

  local function library_haystack(rel, root)
    local leaf = ""
    if root and root ~= "" then
      leaf = root:match("([^/]+)$") or ""
    end
    return (leaf .. " " .. tostring(rel or "")):lower():gsub("[^%w]+", " ")
  end

  local dir_counts = {}
  local dir_tokens = {}
  local dir_meta = {}
  local n = #samples
  for i = 1, n do
    local sample = samples[i]
    local root, rel = scan_root_and_relative(sample and sample.path)
    local key = (root .. "\t" .. rel):lower()
    dir_counts[key] = (dir_counts[key] or 0) + 1
    if not dir_tokens[key] then
      dir_tokens[key] = tokens_from_library_path(rel, root)
      dir_meta[key] = { root = root, rel = rel }
    end
  end

  local function pack_id_for(root, rel)
    local first = tostring(rel or ""):match("^([^/]+)")
    if first and first ~= "" then
      return tostring(root or "") .. "\t" .. first:lower()
    end
    local leaf = tostring(root or ""):match("([^/]+)$") or ""
    return tostring(root or "") .. "\t" .. leaf:lower()
  end

  local token_counts = {}
  local token_packs = {}
  for key, count in pairs(dir_counts) do
    local meta = dir_meta[key] or {}
    local pack = pack_id_for(meta.root, meta.rel)
    for token, _ in pairs(dir_tokens[key] or {}) do
      token_counts[token] = (token_counts[token] or 0) + count
      local packs = token_packs[token]
      if not packs then
        packs = {}
        token_packs[token] = packs
      end
      packs[pack] = true
    end
  end

  local min_count = 5
  if n >= 40 then
    min_count = math.max(8, math.min(24, math.floor(n * 0.012)))
  end

  local function pack_count(token)
    local packs = token_packs[token]
    if not packs then
      return 0
    end
    local c = 0
    for _ in pairs(packs) do
      c = c + 1
    end
    return c
  end

  local ranked = {}
  for token, count in pairs(token_counts) do
    if count >= min_count and pack_count(token) >= 2 then
      ranked[#ranked + 1] = { tag = token, count = count }
    end
  end
  table.sort(ranked, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
  local cap = 50
  if #ranked > cap then
    for i = cap + 1, #ranked do
      ranked[i] = nil
    end
  end

  local new_set = {}
  for i = 1, #ranked do
    new_set[ranked[i].tag] = true
  end

  local dir_match_cache = {}
  local function matching_tags_for_path(path)
    local root, rel = scan_root_and_relative(path)
    local hay = library_haystack(rel, root)
    local cached = dir_match_cache[hay]
    if cached then
      return cached
    end
    local extra = {}
    for i = 1, #ranked do
      local tag = ranked[i].tag
      if genre_key_matches(hay, tag) then
        extra[#extra + 1] = tag
      end
    end
    dir_match_cache[hay] = extra
    return extra
  end

  for i = 1, n do
    local sample = samples[i]
    if sample then
      local custom = {}
      local path = sample.path or ""
      local custom_list = state.custom_tags and (state.custom_tags[path] or state.custom_tags[normalize_path(path)])
      if type(custom_list) == "table" then
        for _, tag in ipairs(custom_list) do
          custom[tostring(tag):lower()] = true
        end
      end
      local kept = {}
      for _, tag in ipairs(sample.tags or {}) do
        local low = tostring(tag):lower()
        if (core_keep[low] or custom[low]) and not (tag_is_suppressed and tag_is_suppressed(low)) then
          kept[#kept + 1] = tag
        end
      end
      sample.tags = append_unique_tags(kept, matching_tags_for_path(path))
    end
  end

  state.discovered_library_tag_set = new_set
end


-- Build tag list, counts, and inverted tag → samples index for fast filtering
function rebuild_tag_index()
  local counts = {}
  local by_tag = {}
  for _, s in ipairs(state.samples) do
    s._render_color = nil
    local set = {}
    if s.tags and type(s.tags) == "table" then
      local tags, seen = {}, {}
      for _, tag in ipairs(s.tags) do
        if tag == "808" then
          tag = "808s"
        end
        if tag and not seen[tag] then
          seen[tag] = true
          tags[#tags + 1] = tag
        end
      end
      s.tags = tags
      for _, tag in ipairs(tags) do
        if not (tag_is_suppressed and tag_is_suppressed(tag)) then
          set[tag] = true
          counts[tag] = (counts[tag] or 0) + 1
          local list = by_tag[tag]
          if not list then
            list = {}
            by_tag[tag] = list
          end
          list[#list + 1] = s
        end
      end
    end
    s._tag_set = set
  end

  state.samples_by_tag = by_tag
  state.tag_counts = counts
  state.tag_index_epoch = (state.tag_index_epoch or 0) + 1
  state.tag_index_samples_ref = state.samples
  state.tag_index_sample_count = #state.samples
  state.tag_category_rev = (state.tag_category_rev or 0) + 1
  state.tag_list = {}
  for tag, count in pairs(counts) do
    table.insert(state.tag_list, {tag = tag, count = count})
  end
  table.sort(state.tag_list, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
end

-- Rebuild the tag index only when the library changed since the last rebuild
-- (an untagged library would otherwise be re-indexed every frame).
function sm_tag_index_rebuild_if_stale()
  if (not state.tag_list or #state.tag_list == 0) and #state.samples > 0
      and (state.tag_index_samples_ref ~= state.samples
        or state.tag_index_sample_count ~= #state.samples) then
    rebuild_tag_index()
  end
end

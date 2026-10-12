-- Sample Map Browser module: scan_report
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
--
-- The window shown when a scan finishes: summary tiles, then the files that
-- need a look grouped by cause, each group with a plain explanation, a fix and
-- actions (preview, show in Finder, retry, move to the Trash, remove from the
-- library). Files are only ever moved to the Trash, never deleted outright.
local r = reaper

-- Why a file failed, in the order the groups are listed.
-- broken: offered by "Move broken files to Trash". retry: re-analyzing may help.
-- remove: the file is gone, so the action only drops it from the library.
SM_SCAN_CAUSES = {
  {
    id = "damaged", label = "Damaged", color = 0xF06A6AFF, broken = true,
    title = "Damaged or not fully copied",
    explain = "The file is filled with empty bytes, usually from an interrupted copy or a failing drive. It will not play.",
    fix = "Copy it again from the original source, or move it to the Trash.",
  },
  {
    id = "unreadable", label = "Unreadable", color = 0xF0905AFF, broken = true,
    title = "Not valid audio",
    explain = "The audio data could not be read. The file is probably corrupt, or is not really audio.",
    fix = "If it will not play in REAPER either, move it to the Trash.",
  },
  {
    id = "missing", label = "Missing", color = 0xA0A1A5FF, remove = true,
    title = "File not found",
    explain = "The file was moved, renamed or deleted after it was found, or its drive was disconnected.",
    fix = "Reconnect the drive and rescan, or remove these from the library.",
  },
  {
    id = "decoder", label = "Needs ffmpeg", color = 0x6FA8FFFF, retry = true,
    title = "No decoder for this format",
    explain = "Nothing on this computer can decode this format (mp3, flac, ogg, m4a…). The files themselves are fine.",
    fix = "Install ffmpeg (brew install ffmpeg), then press Retry.",
  },
  {
    id = "analyzer", label = "Analyzer", color = 0xB48CFFFF, retry = true,
    title = "Analyzer stopped",
    explain = "The analyzer timed out or crashed on these files. The files may be fine.",
    fix = "Press Retry. If they keep failing, send a report from Help > Send Feedback.",
  },
  {
    id = "partial", label = "Partial", color = 0xE8C060FF, retry = true,
    title = "Partly analyzed",
    explain = "Some sound details could not be measured. These files still play and show on the map.",
    fix = "Usually fine to leave. Press Retry to measure them again.",
  },
  {
    id = "pending", label = "Not analyzed", color = 0x8FB8C8FF, retry = true,
    title = "Not analyzed yet",
    explain = "The scan stopped before these files were analyzed, so they sit at the edge of the map.",
    fix = "Press Retry to analyze them now.",
  },
  {
    id = "silent", label = "Silent", color = 0x5FC8C0FF, info = true,
    title = "Silent or very short",
    explain = "These files play but contain no sound, or last under 20 ms. They are on the map with neutral values.",
    fix = "Keep them if you meant to. Otherwise move them to the Trash.",
  },
}

SM_SCAN_CAUSE_BY_ID = {}
for i, c in ipairs(SM_SCAN_CAUSES) do
  c.order = i
  SM_SCAN_CAUSE_BY_ID[c.id] = c
end

SM_SCAN_FIELD_NAMES = {
  dominant_freq = "pitch",
  rms_energy = "loudness",
  brightness = "brightness",
  sub_weight = "low end",
  effective_duration = "length",
  playback_type = "loop/one-shot",
}

SM_SCAN_REPORT_ROW_CAP = 60      -- rows shown per group before "Show all"
SM_SCAN_REPORT_QUIET_CAP = 5000  -- silent files remembered per scan
SM_TRASH_CHUNK = 40              -- paths per trash command

-- Words in analyzer exceptions that point at a broken file rather than at the analyzer.
local DECODE_HINTS = {
  "riff", "wave", "aiff", "aifc", "header", "chunk", "decode", "invalid data",
  "unpack", "unsupported", "eof", "truncated", "corrupt", "not an audio", "bad file",
}

function sm_scan_cause_of(why)
  local w = string.lower(tostring(why or ""))
  if w == "" then
    return "pending"
  end
  if w:find("zero) bytes", 1, true) or w:find("not fully copied", 1, true) then
    return "damaged"
  end
  if w:find("file not found", 1, true) or w:find("no such file", 1, true) then
    return "missing"
  end
  if w:find("no audio decoder", 1, true) then
    return "decoder"
  end
  if w:find("partial result", 1, true) then
    return "partial"
  end
  if w:find("never analyzed", 1, true) then
    return "pending"
  end
  if w:find("could not decode", 1, true) then
    return "unreadable"
  end
  if w:find("analyzer", 1, true) or w:find("python", 1, true) or w:find("timeout", 1, true) then
    return "analyzer"
  end
  for i = 1, #DECODE_HINTS do
    if w:find(DECODE_HINTS[i], 1, true) then
      return "unreadable"
    end
  end
  return "analyzer"
end

-- "partial result: missing dominant_freq, sub_weight" -> "pitch, low end"
function sm_scan_friendly_fields(text)
  local out = {}
  for field in tostring(text or ""):gmatch("[%a_]+") do
    local name = SM_SCAN_FIELD_NAMES[field]
    if name then
      out[#out + 1] = name
    end
  end
  return table.concat(out, ", ")
end

function sm_format_bytes(n)
  n = tonumber(n)
  if not n or n < 0 then
    return ""
  end
  if n < 1024 then
    return string.format("%d B", n)
  elseif n < 1024 * 1024 then
    return string.format("%.0f KB", n / 1024)
  elseif n < 1024 * 1024 * 1024 then
    return string.format("%.1f MB", n / (1024 * 1024))
  end
  return string.format("%.1f GB", n / (1024 * 1024 * 1024))
end

-- Short "what's wrong" text shown on each row.
function sm_scan_row_detail(cause, why, size)
  why = tostring(why or "")
  if cause == "damaged" then
    if size == 0 then
      return "empty file (0 bytes)"
    end
    return "starts with empty bytes"
  elseif cause == "unreadable" then
    if why:find("could not decode", 1, true) then
      return "no readable audio"
    end
    return (#why > 48) and (why:sub(1, 46) .. "…") or why
  elseif cause == "missing" then
    return "not on disk"
  elseif cause == "decoder" then
    return "needs ffmpeg"
  elseif cause == "analyzer" then
    local w = why:lower()
    if w:find("timeout", 1, true) then return "timed out" end
    if w:find("empty analyzer output", 1, true) then return "no output" end
    if w:find("invalid analyzer json", 1, true) then return "bad output" end
    if w:find("python", 1, true) then return "Python 3 not found" end
    if w:find("no fields", 1, true) then return "nothing measured" end
    return (#why > 48) and (why:sub(1, 46) .. "…") or why
  elseif cause == "partial" then
    local f = sm_scan_friendly_fields(why:match("missing (.*)$"))
    return f ~= "" and ("no " .. f) or "some details missing"
  elseif cause == "pending" then
    return "waiting for analysis"
  elseif cause == "silent" then
    return why == "too short" and "under 20 ms" or "no sound"
  end
  return why
end

-- Called while results merge: remember files the analyzer called silent / too short.
function sm_scan_report_note_quiet(sample, note)
  local session = state.scan_session
  if type(session) ~= "table" or not sample or not sample.path or note == nil or note == "" then
    return
  end
  session.quiet = session.quiet or {}
  session.quiet_seen = session.quiet_seen or {}
  if session.quiet_seen[sample.path] or #session.quiet >= SM_SCAN_REPORT_QUIET_CAP then
    return
  end
  session.quiet_seen[sample.path] = true
  session.quiet[#session.quiet + 1] = { path = sample.path, note = tostring(note) }
end

local function scan_row(sample_path, why, cause, size)
  local name = (sample_path and sample_path:match("([^/\\]+)$")) or sample_path or "?"
  local dir = sample_path and sample_path:match("^(.*)[/\\][^/\\]*$") or ""
  local folder = dir:match("([^/\\]+)$") or dir
  return {
    path = sample_path,
    name = name,
    folder = folder,
    dir = dir,
    why = why,
    cause = cause,
    size = size,
    detail = sm_scan_row_detail(cause, why, size),
  }
end

-- Every file that needs a look after a scan: library samples still missing
-- analyzer fields plus the silent files this scan found.
function sm_scan_report_rows(session, still_incomplete)
  local rows = {}
  local listed = {}
  if type(still_incomplete) == "number" and still_incomplete > 0 then
    local logged = 0
    for _, s in ipairs(state.samples) do
      if sample_analysis_incomplete(s) then
        local why = s._analyze_fail
        if type(why) ~= "string" or why == "" then
          local missing = sample_analysis_missing_fields(s)
          why = #missing > 0 and ("never analyzed — missing " .. table.concat(missing, ", ")) or "unknown"
        end
        local row = scan_row(s.path, why, sm_scan_cause_of(why), s.file_size)
        rows[#rows + 1] = row
        if s.path then
          listed[s.path] = true
        end
        if logged < 20 then
          add_scan_log(string.format("Still incomplete: %s (%s)", row.name, why))
          logged = logged + 1
        end
      end
    end
  end
  if type(session) == "table" and type(session.quiet) == "table" then
    for _, q in ipairs(session.quiet) do
      local s = lookup_sample_by_path(q.path)
      if s and not listed[s.path] then
        listed[s.path] = true
        rows[#rows + 1] = scan_row(s.path, q.note, "silent", s.file_size)
      end
    end
  end
  table.sort(rows, function(a, b)
    local ca, cb = SM_SCAN_CAUSE_BY_ID[a.cause].order, SM_SCAN_CAUSE_BY_ID[b.cause].order
    if ca ~= cb then
      return ca < cb
    end
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then
      return na < nb
    end
    return (a.path or "") < (b.path or "")
  end)
  return rows
end

-- { [cause_id] = count, problems = n (not counting info rows), broken = n }
function sm_scan_report_counts(dlg)
  local counts = { problems = 0, broken = 0, retry = 0 }
  for _, row in ipairs((type(dlg) == "table" and dlg.rows) or {}) do
    local c = SM_SCAN_CAUSE_BY_ID[row.cause]
    counts[row.cause] = (counts[row.cause] or 0) + 1
    if c and not c.info then
      counts.problems = counts.problems + 1
    end
    if c and c.broken then
      counts.broken = counts.broken + 1
    end
    if c and c.retry then
      counts.retry = counts.retry + 1
    end
  end
  return counts
end

-- Paths of the rows matching `which`: a cause id, "broken" or "retry".
function sm_scan_report_paths(dlg, which)
  local paths = {}
  for _, row in ipairs((type(dlg) == "table" and dlg.rows) or {}) do
    local c = SM_SCAN_CAUSE_BY_ID[row.cause]
    local match = row.cause == which
      or (which == "broken" and c and c.broken)
      or (which == "retry" and c and c.retry)
    if match and row.path and row.path ~= "" then
      paths[#paths + 1] = row.path
    end
  end
  return paths
end

local function scan_report_clipboard(dlg)
  local out = { (dlg.kind or "Scan") .. "  ·  " .. (dlg.elapsed_text or "") }
  for _, line in ipairs(dlg.lines or {}) do
    out[#out + 1] = line
  end
  if dlg.footnote then
    out[#out + 1] = dlg.footnote
  end
  local current = nil
  for _, row in ipairs(dlg.rows or {}) do
    if row.cause ~= current then
      current = row.cause
      local c = SM_SCAN_CAUSE_BY_ID[row.cause]
      out[#out + 1] = ""
      out[#out + 1] = string.format("%s (%d)", c.title, sm_scan_report_counts(dlg)[row.cause] or 0)
    end
    out[#out + 1] = string.format("  %s — %s", row.name or "?", row.why or "")
    if row.path and row.path ~= "" then
      out[#out + 1] = "    " .. row.path
    end
  end
  return table.concat(out, "\n")
end

function finish_scan_session(still_incomplete)
  local session = state.scan_session
  local now = r.time_precise()
  local elapsed = 0
  if type(session) == "table" then
    elapsed = session.elapsed_so_far or 0
    if type(session.started_at) == "number" then
      elapsed = elapsed + (now - session.started_at)
    end
  elseif state.scan_started and state.scan_started > 0 then
    elapsed = now - state.scan_started
  end
  if type(session) ~= "table" then
    session = { kind = state.analyzer_job_label or "Scan" }
  end
  if not scan_session_did_work(session) and elapsed < 0.5 then
    state.scan_session = nil
    return
  end

  local kind = session.kind or "Scan"
  local is_folder_scan = (kind == "Library scan" or kind == "Folder rescan" or kind == "Continued scan")
  local tiles
  if is_folder_scan then
    tiles = {
      { value = session.indexed or session.new_files or 0, label = "New files" },
      { value = (session.changed_files or 0) + (session.incomplete_files or 0), label = "Re-analyzed" },
      { value = session.unchanged_files or 0, label = "Unchanged" },
    }
  else
    tiles = {
      { value = math.max(session.queued or 0, session.analyzed or 0), label = "Processed" },
      { value = session.analyzed or 0, label = "Analyzed" },
      { value = #state.samples, label = "In library" },
    }
  end
  local info = { "Library: " .. sm_format_count(#state.samples) .. " samples" }
  if (session.workers or 0) > 0 then
    info[#info + 1] = string.format("%d workers on %d cores", session.workers, session.cores or 0)
  end
  local lines = {
    "Time: " .. format_scan_clock(elapsed),
  }
  if session.detail and session.detail ~= "" then
    lines[#lines + 1] = "Folder: " .. tostring(session.detail)
  end
  for _, t in ipairs(tiles) do
    lines[#lines + 1] = string.format("%s: %d", t.label, t.value)
  end
  lines[#lines + 1] = string.format("Analyzer completed: %d  ·  errors: %d", session.analyzed or 0, session.analyze_errors or 0)
  lines[#lines + 1] = info[1]

  local footnote = nil
  if (session.merge_misses or 0) > 0 then
    footnote = string.format("%d analyzer result(s) did not match a library file.", session.merge_misses)
  end
  local rows = sm_scan_report_rows(session, still_incomplete)

  local dlg = {
    title = "Scan complete",
    kind = kind,
    elapsed_text = format_scan_clock(elapsed),
    detail = session.detail,
    tiles = tiles,
    info = table.concat(info, "  ·  "),
    lines = lines,
    footnote = footnote,
    rows = rows,
    error_count = session.analyze_errors or 0,
    open = {},
    show_all = {},
  }
  dlg.clipboard = scan_report_clipboard(dlg)
  local counts = sm_scan_report_counts(dlg)

  -- Background scans that went fine end with a toast instead of a window.
  if scan_in_background() and counts.problems == 0 and dlg.error_count == 0 and not footnote then
    play_scan_complete_sound()
    local quiet = #rows > 0 and string.format("  ·  %d silent file(s)", #rows) or ""
    sm_notify(string.format("%s finished in %s  ·  library: %s samples%s",
      kind, format_scan_clock(elapsed), sm_format_count(#state.samples), quiet))
    add_scan_log(string.format("%s finished in %s", kind, format_scan_clock(elapsed)))
    state.scan_session = nil
    return
  end

  state.scan_complete_dialog = dlg
  play_scan_complete_sound()
  add_scan_log(string.format("%s finished in %s", kind, format_scan_clock(elapsed)))
  state.scan_session = nil
end

-- --- Actions -------------------------------------------------------------------

function reveal_path_in_finder(path)
  if not path or path == "" then
    return
  end
  seq_reveal_sample_in_explorer({ path = path })
end

function sm_path_exists(path)
  if not path or path == "" then
    return false
  end
  if r.file_exists then
    return r.file_exists(path) and true or false
  end
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function chunks(list, size)
  local out = {}
  for i = 1, #list, size do
    local part = {}
    for j = i, math.min(#list, i + size - 1) do
      part[#part + 1] = list[j]
    end
    out[#out + 1] = part
  end
  return out
end

-- Shell commands that move `paths` to the system Trash / Recycle Bin.
-- `method` (macOS only): "cli" for /usr/bin/trash (macOS 15+), else Finder.
function sm_trash_commands(paths, method)
  local cmds = {}
  for _, part in ipairs(chunks(paths, SM_TRASH_CHUNK)) do
    if SM_IS_WINDOWS then
      local items = {}
      for _, p in ipairs(part) do
        local win = p:gsub("/", "\\"):gsub("'", "''")
        items[#items + 1] = "'" .. win .. "'"
      end
      cmds[#cmds + 1] = 'powershell -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName Microsoft.VisualBasic; foreach ($p in @('
        .. table.concat(items, ",")
        .. ")) { try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') } catch {} }\""
    else
      local args = {}
      for _, p in ipairs(part) do
        args[#args + 1] = shell_escape(p)
      end
      if SM_IS_MAC and method == "cli" then
        cmds[#cmds + 1] = "/usr/bin/trash " .. table.concat(args, " ")
      elseif SM_IS_MAC then
        -- Finder keeps "Put Back" working. Each file in its own try, so one
        -- failure does not stop the rest.
        cmds[#cmds + 1] = "osascript"
          .. " -e 'on run argv' -e 'repeat with p in argv' -e 'try'"
          .. " -e 'set f to (POSIX file (contents of p)) as alias'"
          .. " -e 'tell application \"Finder\" to delete f'"
          .. " -e 'end try' -e 'end repeat' -e 'end run' "
          .. table.concat(args, " ")
      else
        cmds[#cmds + 1] = "gio trash -- " .. table.concat(args, " ")
      end
    end
  end
  return cmds
end

-- Runs one trash command and waits for it. Replaced in tests.
function sm_run_trash_command(cmd)
  if SM_IS_WINDOWS then
    if r.ExecProcess then
      r.ExecProcess(cmd, 120000)
    end
    return
  end
  os.execute(cmd .. " >/dev/null 2>&1")
end

-- Moves files to the Trash. Returns trashed, failed (lists of paths).
-- Files already gone count as trashed. Nothing is ever deleted outright.
function sm_move_paths_to_trash(paths)
  local todo = {}
  local trashed = {}
  for _, p in ipairs(paths or {}) do
    if p and p ~= "" then
      if sm_path_exists(p) then
        todo[#todo + 1] = p
      else
        trashed[#trashed + 1] = p
      end
    end
  end
  local methods = { "default" }
  if SM_IS_MAC and sm_path_exists("/usr/bin/trash") then
    methods = { "cli", "default" }
  end
  for _, method in ipairs(methods) do
    if #todo == 0 then
      break
    end
    for _, cmd in ipairs(sm_trash_commands(todo, method)) do
      sm_run_trash_command(cmd)
    end
    local left = {}
    for _, p in ipairs(todo) do
      if sm_path_exists(p) then
        left[#left + 1] = p
      else
        trashed[#trashed + 1] = p
      end
    end
    todo = left
  end
  return trashed, todo
end

-- Drops samples from the library (files on disk are not touched).
function sm_remove_library_paths(paths)
  local drop = {}
  for _, p in ipairs(paths or {}) do
    if p and p ~= "" then
      drop[p] = true
      drop[path_index_key(p)] = true
    end
  end
  local kept = {}
  local removed = 0
  for _, sample in ipairs(state.samples) do
    local p = sample.path
    if p and (drop[p] or drop[path_index_key(p)]) then
      removed = removed + 1
    else
      kept[#kept + 1] = sample
    end
  end
  if removed == 0 then
    return 0
  end
  state.samples = kept
  rebuild_samples_path_index()
  if rebuild_tag_index then
    rebuild_tag_index()
  end
  if #state.samples > 0 then
    layout_samples()
  end
  save_samples()
  return removed
end

local function drop_rows(dlg, paths)
  local set = {}
  for _, p in ipairs(paths) do
    set[p] = true
  end
  local kept = {}
  for _, row in ipairs(dlg.rows or {}) do
    if not set[row.path] then
      kept[#kept + 1] = row
    end
  end
  dlg.rows = kept
  dlg.clipboard = scan_report_clipboard(dlg)
end

-- action "trash": move to the Trash, then drop from the library.
-- action "remove": only drop from the library (the files are already gone).
function sm_scan_report_apply(dlg, action, paths)
  paths = paths or {}
  local done, failed = paths, {}
  if action == "trash" then
    done, failed = sm_move_paths_to_trash(paths)
  end
  local removed = sm_remove_library_paths(done)
  if type(dlg) == "table" then
    drop_rows(dlg, done)
    dlg.confirm = nil
    dlg.banner = nil
  end
  local n = #done
  if action == "trash" then
    add_scan_log(string.format("Moved %d file(s) to the Trash%s", n, #failed > 0 and (", " .. #failed .. " could not be moved") or ""))
    for i = 1, math.min(#failed, 20) do
      add_scan_log("Could not move to the Trash: " .. failed[i])
    end
    if #failed > 0 and type(dlg) == "table" then
      local why = SM_IS_MAC and " Allow REAPER to control Finder in System Settings > Privacy & Security > Automation, then try again."
        or " Check that the files are not open or read-only."
      dlg.banner = string.format("%d file%s could not be moved to the Trash.%s",
        #failed, #failed == 1 and "" or "s", why)
    end
    if n > 0 then
      sm_notify(string.format("Moved %d file%s to the Trash", n, n == 1 and "" or "s"))
    end
  else
    add_scan_log(string.format("Removed %d missing file(s) from the library", removed))
    if removed > 0 then
      sm_notify(string.format("Removed %d file%s from the library", removed, removed == 1 and "" or "s"))
    end
  end
  return n, failed, removed
end

function sm_scan_report_retry(dlg, paths)
  local set = {}
  for _, p in ipairs(paths or {}) do
    local key = normalize_path(p)
    set[key] = true
    local s = lookup_sample_by_path(p)
    if s then
      s._analyze_fail = nil
    end
  end
  state.analyzer_job_label = "Retrying files"
  state.analyzer_mode = nil
  local added = enqueue_analyzer_paths(function(s)
    return s.path and set[normalize_path(s.path)] or false
  end, "Nothing to retry: those files are no longer in the library", "Retry")
  if added and added > 0 then
    sm_notify(string.format("Retrying %d file%s", added, added == 1 and "" or "s"))
    if state.scan_complete_dialog == dlg then
      state.scan_complete_dialog = nil
    end
  end
  return added or 0
end

-- Kept for the right-click menu: files that are the file's own fault.
function sample_row_is_unreadable(entry)
  if type(entry) ~= "table" then
    return false
  end
  local c = SM_SCAN_CAUSE_BY_ID[entry.cause or sm_scan_cause_of(entry.why)]
  return c ~= nil and (c.broken or c.remove) and true or false
end

local function ask_confirm(dlg, action, paths)
  if #paths == 0 then
    return
  end
  dlg.confirm = { action = action, paths = paths }
  dlg.open_confirm = true
end

-- --- Drawing -------------------------------------------------------------------

local function with_alpha(color, a)
  return (color & 0xFFFFFF00) | (a & 0xFF)
end

local function draw_trash_icon(dl, cx, cy, size, color)
  local s = size * 0.5
  local stroke = math.max(1.2, size * 0.08)
  local top = cy - s * 0.55
  r.ImGui_DrawList_AddLine(dl, cx - s * 0.7, top, cx + s * 0.7, top, color, stroke)
  r.ImGui_DrawList_AddLine(dl, cx - s * 0.22, top - s * 0.22, cx + s * 0.22, top - s * 0.22, color, stroke)
  local bx0, bx1 = cx - s * 0.5, cx + s * 0.5
  local by0, by1 = top + s * 0.18, cy + s * 0.7
  r.ImGui_DrawList_AddLine(dl, bx0, by0, bx0 + s * 0.08, by1, color, stroke)
  r.ImGui_DrawList_AddLine(dl, bx1, by0, bx1 - s * 0.08, by1, color, stroke)
  r.ImGui_DrawList_AddLine(dl, bx0 + s * 0.08, by1, bx1 - s * 0.08, by1, color, stroke)
  r.ImGui_DrawList_AddLine(dl, cx, by0 + s * 0.2, cx, by1 - s * 0.2, color, stroke * 0.8)
end

local function draw_folder_icon(dl, cx, cy, size, color)
  local w, h = size, size * 0.74
  local x0, y0 = cx - w * 0.5, cy - h * 0.5 + 1
  r.ImGui_DrawList_AddRect(dl, x0, y0 + h * 0.18, x0 + w, y0 + h, color, 2, 0, 1.3)
  r.ImGui_DrawList_AddLine(dl, x0 + 1, y0 + h * 0.18, x0 + w * 0.12, y0, color, 1.3)
  r.ImGui_DrawList_AddLine(dl, x0 + w * 0.12, y0, x0 + w * 0.42, y0, color, 1.3)
  r.ImGui_DrawList_AddLine(dl, x0 + w * 0.42, y0, x0 + w * 0.5, y0 + h * 0.18, color, 1.3)
end

local function draw_play_icon(dl, cx, cy, size, color)
  local s = size * 0.5
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - s * 0.6, cy - s * 0.8, cx - s * 0.6, cy + s * 0.8, cx + s * 0.85, cy, color)
end

local function draw_bold_text(dl, x, y, color, text)
  r.ImGui_DrawList_AddText(dl, x, y, color, text)
  r.ImGui_DrawList_AddText(dl, x + 0.5, y, color, text)
end

local function draw_scaled_text(dl, x, y, color, text, scale)
  local font = r.ImGui_GetFont and r.ImGui_GetFont(ctx) or nil
  local base = (r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx)) or 13.0
  if r.ImGui_DrawList_AddTextEx then
    r.ImGui_DrawList_AddTextEx(dl, font, base * scale, x, y, color, text)
    r.ImGui_DrawList_AddTextEx(dl, font, base * scale, x + 0.6, y, color, text)
  else
    draw_bold_text(dl, x, y, color, text)
  end
end

-- Colored pill with the cause label. Returns its width.
local function draw_badge(dl, x, y, h, cause)
  local tw, th = r.ImGui_CalcTextSize(ctx, cause.label)
  local w = tw + 18
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, with_alpha(cause.color, 0x30), h * 0.5)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, with_alpha(cause.color, 0xA0), h * 0.5, 0, 1.0)
  r.ImGui_DrawList_AddCircleFilled(dl, x + 7, y + h * 0.5, 2.5, cause.color)
  r.ImGui_DrawList_AddText(dl, x + 13, y + (h - th) * 0.5, cause.color, cause.label)
  return w
end

-- Small square icon button at an absolute position.
local function icon_button(id, icon, x, y, size, tip, danger)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if hovered then
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + size, y + size,
      danger and UI_THEME.danger_fill or UI_THEME.surface_hvr, 5)
  end
  local col = hovered and (danger and UI_THEME.danger or UI_THEME.text) or UI_THEME.text_dim
  local cx, cy = x + size * 0.5, y + size * 0.5
  if icon == "trash" then
    draw_trash_icon(dl, cx, cy, size * 0.62, col)
  elseif icon == "folder" then
    draw_folder_icon(dl, cx, cy, size * 0.62, col)
  else
    ui_button_draw_icon(dl, icon, cx, cy, size * 0.62, col)
  end
  if hovered and tip and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, tip)
  end
  return clicked
end

local function fit_text(text, max_w)
  if seq_truncate_text_to_width then
    return seq_truncate_text_to_width(text, max_w)
  end
  return text
end

-- Header: status icon, title and what was scanned.
local function draw_report_header(dlg, counts)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 400
  local tone, title
  if counts.broken > 0 then
    tone = SM_SCAN_CAUSE_BY_ID.damaged.color
    title = string.format("Found %d broken file%s", counts.broken, counts.broken == 1 and "" or "s")
  elseif counts.problems > 0 then
    tone = SM_SCAN_CAUSE_BY_ID.partial.color
    title = string.format("Scan finished  ·  %d file%s need%s a look",
      counts.problems, counts.problems == 1 and "" or "s", counts.problems == 1 and "s" or "")
  else
    tone = UI_THEME.success
    title = "Scan finished"
  end
  local h = 40
  local rad = 16
  local cx, cy = x + rad + 2, y + h * 0.5
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, with_alpha(tone, 0x2A), 28)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, rad, with_alpha(tone, 0xC0), 28, 1.5)
  if counts.problems > 0 then
    r.ImGui_DrawList_AddLine(dl, cx, cy - 7, cx, cy + 2, tone, 2.6)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy + 6.5, 1.6, tone)
  else
    ui_button_draw_icon(dl, "check", cx, cy, 24, tone)
  end
  local tx = x + rad * 2 + 14
  local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
  draw_scaled_text(dl, tx, y + 2, UI_THEME.text, title, 1.18)
  local sub = (dlg.kind or "Scan") .. "  ·  " .. (dlg.elapsed_text or "")
  if dlg.detail and dlg.detail ~= "" then
    sub = sub .. "  ·  " .. tostring(dlg.detail)
  end
  r.ImGui_DrawList_AddText(dl, tx, y + h - th - 1, UI_THEME.text_dim, fit_text(sub, avail - (tx - x)))
  r.ImGui_Dummy(ctx, avail, h)
end

local function draw_report_tiles(dlg, counts)
  local tiles = {}
  for _, t in ipairs(dlg.tiles or {}) do
    tiles[#tiles + 1] = t
  end
  local look_col = counts.broken > 0 and SM_SCAN_CAUSE_BY_ID.damaged.color
    or (counts.problems > 0 and SM_SCAN_CAUSE_BY_ID.partial.color) or UI_THEME.success
  tiles[#tiles + 1] = { value = counts.problems, label = "Need a look", color = look_col }
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 400
  local gap, h = 8, 58
  local w = (avail - gap * (#tiles - 1)) / #tiles
  local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
  for i, t in ipairs(tiles) do
    local x0 = x + (i - 1) * (w + gap)
    local hot = t.color and t.value > 0
    r.ImGui_DrawList_AddRectFilled(dl, x0, y, x0 + w, y + h, hot and with_alpha(t.color, 0x18) or UI_THEME.surface, 8)
    r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y + 0.5, x0 + w - 0.5, y + h - 0.5,
      hot and with_alpha(t.color, 0x70) or UI_THEME.border_soft, 8, 0, 1.0)
    draw_scaled_text(dl, x0 + 12, y + 7, t.color or UI_THEME.text, sm_format_count(t.value), 1.55)
    r.ImGui_DrawList_AddText(dl, x0 + 12, y + h - th - 8, UI_THEME.text_dim, t.label)
  end
  r.ImGui_Dummy(ctx, avail, h)
  if dlg.info and dlg.info ~= "" then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, dlg.info)
  end
  if dlg.footnote then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, dlg.footnote)
  end
end

-- One file row. Returns true when the row was hovered.
local function draw_report_row(dlg, row, cause, i, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local h = 26
  local btn = 20
  local right_w = btn * 2 + 10
  local size_w = 64
  local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
  local ty = y + (h - th) * 0.5
  local id = "##scr_row" .. tostring(i)

  -- Click target: everything left of the icon buttons.
  r.ImGui_InvisibleButton(ctx, id, math.max(1, width - right_w), h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  if r.ImGui_IsItemClicked(ctx, 0) then
    local sample = lookup_sample_by_path(row.path)
    if sample and cause.id ~= "missing" then
      preview_sample(sample)
    end
    dlg.selected = row.path
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    dlg.menu_row = row
    if r.ImGui_OpenPopup then
      r.ImGui_OpenPopup(ctx, "##scan_report_row_menu")
    end
  end
  local selected = dlg.selected == row.path
  if hovered or selected then
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + h, selected and 0xFFFFFF12 or 0xFFFFFF0A, 5)
  end
  r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 6, x + 4, y + h - 6, with_alpha(cause.color, 0xC0), 1)

  -- Play glyph (decorative; the whole row previews).
  local play_col = (hovered and cause.id ~= "missing") and UI_THEME.accent or UI_THEME.text_mute
  if cause.id ~= "missing" then
    draw_play_icon(dl, x + 18, y + h * 0.5, 11, play_col)
  end

  local x_name = x + 32
  local x_right = x + width - right_w
  local x_size = x_right - size_w
  local detail = row.detail or ""
  local dw = r.ImGui_CalcTextSize(ctx, detail)
  dw = math.min(dw, 190)
  local x_detail = x_size - dw - 10
  local name_room = x_detail - 12 - x_name
  local name = fit_text(row.name or "?", name_room)
  local nw = r.ImGui_CalcTextSize(ctx, name)
  r.ImGui_DrawList_AddText(dl, x_name, ty, UI_THEME.text, name)
  local folder_room = name_room - nw - 10
  if row.folder and row.folder ~= "" and folder_room > 40 then
    r.ImGui_DrawList_AddText(dl, x_name + nw + 10, ty, UI_THEME.text_mute, fit_text(row.folder, folder_room))
  end
  r.ImGui_DrawList_AddText(dl, x_detail, ty, with_alpha(cause.color, 0xE0), fit_text(detail, 190))
  if row.size then
    local s = sm_format_bytes(row.size)
    local sw = r.ImGui_CalcTextSize(ctx, s)
    r.ImGui_DrawList_AddText(dl, x_right - 8 - sw, ty,
      (row.size == 0) and cause.color or UI_THEME.text_mute, s)
  end

  local by = y + (h - btn) * 0.5
  if cause.id ~= "missing"
      and icon_button("##scr_reveal" .. i, "folder", x_right, by, btn, SM_REVEAL_LABEL) then
    reveal_path_in_finder(row.path)
  end
  if cause.id == "missing" then
    if icon_button("##scr_drop" .. i, "close", x_right + btn + 6, by, btn, "Remove from library", true) then
      ask_confirm(dlg, "remove", { row.path })
    end
  elseif icon_button("##scr_trash" .. i, "trash", x_right + btn + 6, by, btn, "Move to Trash…", true) then
    ask_confirm(dlg, "trash", { row.path })
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + h)
  if hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, (row.why or "") .. "\n" .. (row.path or ""))
  end
  return hovered
end

-- Group header with badge, count, title and the group's action.
local function draw_group_header(dlg, cause, count, width, gi)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local h = 32
  local open = dlg.open[cause.id] ~= false
  if dlg.jump == cause.id and r.ImGui_SetScrollHereY then
    r.ImGui_SetScrollHereY(ctx, 0.0)
    dlg.jump = nil
  end
  local action, action_label
  if cause.broken or cause.info then
    action, action_label = "trash", "Move to Trash"
  elseif cause.remove then
    action, action_label = "remove", "Remove from library"
  elseif cause.retry then
    action, action_label = "retry", "Retry"
  end
  local bw = action_label and (r.ImGui_CalcTextSize(ctx, action_label) + 22) or 0

  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + h, with_alpha(cause.color, 0x14), 7)
  r.ImGui_DrawList_AddRectFilled(dl, x, y + 4, x + 3, y + h - 4, cause.color, 1.5)
  r.ImGui_InvisibleButton(ctx, "##scr_group" .. gi, math.max(1, width - bw - 12), h)
  if r.ImGui_IsItemClicked(ctx, 0) then
    dlg.open[cause.id] = not open
  end
  local hovered = r.ImGui_IsItemHovered(ctx)
  ui_button_draw_icon(dl, open and "chev_down" or "chev_right", x + 16, y + h * 0.5, 14,
    hovered and UI_THEME.text or UI_THEME.text_dim)
  local bx = x + 28
  local bw_badge = draw_badge(dl, bx, y + (h - 20) * 0.5, 20, cause)
  local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
  local tx = bx + bw_badge + 10
  local count_text = string.format("%s file%s", sm_format_count(count), count == 1 and "" or "s")
  draw_bold_text(dl, tx, y + (h - th) * 0.5, UI_THEME.text, count_text)
  local cw = r.ImGui_CalcTextSize(ctx, count_text)
  r.ImGui_DrawList_AddText(dl, tx + cw + 10, y + (h - th) * 0.5, UI_THEME.text_dim,
    fit_text(cause.title, x + width - bw - 20 - (tx + cw + 10)))

  if action_label then
    r.ImGui_SetCursorScreenPos(ctx, x + width - bw - 6, y + (h - 22) * 0.5)
    local style = (action == "retry") and "default" or "danger"
    if draw_ui_button("scr_group_act" .. gi, action_label, bw, 22, { compact = true, style = style }) then
      local paths = sm_scan_report_paths(dlg, cause.id)
      if action == "retry" then
        sm_scan_report_retry(dlg, paths)
      else
        ask_confirm(dlg, action, paths)
      end
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + h)
  return open
end

local function draw_group_explainer(cause, width)
  r.ImGui_Dummy(ctx, 1, 2)
  r.ImGui_Indent(ctx, 14)
  if r.ImGui_PushTextWrapPos then
    r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + width - 28)
  end
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, cause.explain)
  r.ImGui_TextColored(ctx, with_alpha(cause.color, 0xE8), "Fix: " .. cause.fix)
  if r.ImGui_PopTextWrapPos then
    r.ImGui_PopTextWrapPos(ctx)
  end
  r.ImGui_Unindent(ctx, 14)
  r.ImGui_Dummy(ctx, 1, 2)
end

local function draw_report_groups(dlg, counts)
  local width = r.ImGui_GetContentRegionAvail(ctx) or 400
  local row_i = 0
  local gi = 0
  local i = 1
  local rows = dlg.rows or {}
  while i <= #rows do
    local cause_id = rows[i].cause
    local cause = SM_SCAN_CAUSE_BY_ID[cause_id]
    local j = i
    while j <= #rows and rows[j].cause == cause_id do
      j = j + 1
    end
    gi = gi + 1
    if gi > 1 then
      r.ImGui_Dummy(ctx, 1, 6)
    end
    if draw_group_header(dlg, cause, j - i, width, gi) then
      draw_group_explainer(cause, width)
      local last = j - 1
      if not dlg.show_all[cause_id] then
        last = math.min(last, i + SM_SCAN_REPORT_ROW_CAP - 1)
      end
      for k = i, last do
        row_i = row_i + 1
        draw_report_row(dlg, rows[k], cause, row_i, width)
      end
      if last < j - 1 then
        r.ImGui_Dummy(ctx, 28, 1)
        r.ImGui_SameLine(ctx, 0, 0)
        if draw_ui_button("scr_more" .. gi, string.format("Show all %s", sm_format_count(j - i)), 0, 22,
            { compact = true, style = "ghost_arrow" }) then
          dlg.show_all[cause_id] = true
        end
      end
    end
    i = j
  end
  if r.ImGui_BeginPopup and r.ImGui_BeginPopup(ctx, "##scan_report_row_menu") then
    local row = dlg.menu_row
    if row then
      draw_scan_complete_sample_menu_items(row.path, row.name, row.why)
    end
    r.ImGui_EndPopup(ctx)
  end
end

function draw_scan_complete_sample_menu_items(path, name, why)
  name = name or (path and path:match("([^/]+)$")) or "Sample"
  local cause = SM_SCAN_CAUSE_BY_ID[sm_scan_cause_of(why)]
  local dlg = state.scan_complete_dialog
  for _, row in ipairs((type(dlg) == "table" and dlg.rows) or {}) do
    if row.path == path then
      cause = SM_SCAN_CAUSE_BY_ID[row.cause] or cause
      break
    end
  end
  r.ImGui_TextColored(ctx, UI_THEME.text, name)
  if cause then
    r.ImGui_TextColored(ctx, cause.color, cause.title)
  end
  if why and why ~= "" then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, why)
  end
  r.ImGui_Separator(ctx)
  local exists = cause == nil or cause.id ~= "missing"
  if exists and r.ImGui_MenuItem(ctx, "Preview") then
    local sample = lookup_sample_by_path(path)
    if sample then
      preview_sample(sample)
    end
  end
  if exists and r.ImGui_MenuItem(ctx, SM_REVEAL_LABEL) then
    reveal_path_in_finder(path)
  end
  if exists and r.ImGui_MenuItem(ctx, "Open file") then
    sm_open_path(path)
  end
  if cause and cause.retry and r.ImGui_MenuItem(ctx, "Retry") then
    sm_scan_report_retry(dlg, { path })
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Copy filename") and r.ImGui_SetClipboardText then
    r.ImGui_SetClipboardText(ctx, name)
  end
  if r.ImGui_MenuItem(ctx, "Copy path") and r.ImGui_SetClipboardText then
    r.ImGui_SetClipboardText(ctx, path or "")
  end
  if path and path ~= "" and type(dlg) == "table" then
    r.ImGui_Separator(ctx)
    if not exists then
      if r.ImGui_MenuItem(ctx, "Remove from library…") then
        ask_confirm(dlg, "remove", { path })
      end
    elseif r.ImGui_MenuItem(ctx, "Move to Trash…") then
      ask_confirm(dlg, "trash", { path })
    end
  end
end

-- Confirm step listing every file. Returns true while the modal is open.
local function draw_confirm_modal(dlg)
  local popup_id = "Confirm##scan_report_confirm"
  if dlg.open_confirm and r.ImGui_OpenPopup then
    r.ImGui_OpenPopup(ctx, popup_id)
    dlg.open_confirm = nil
  end
  local conf = dlg.confirm
  if not (r.ImGui_BeginPopupModal and type(conf) == "table" and #conf.paths > 0) then
    return false
  end
  local flags = 0
  for _, getter in ipairs({ r.ImGui_WindowFlags_AlwaysAutoResize, r.ImGui_WindowFlags_NoMove,
      r.ImGui_WindowFlags_NoCollapse, r.ImGui_WindowFlags_NoTitleBar }) do
    if getter then
      flags = flags | getter()
    end
  end
  local rect = state.main_window_rect
  if r.ImGui_SetNextWindowPos and rect then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    r.ImGui_SetNextWindowPos(ctx, rect.x + (rect.w or 0) * 0.5, rect.y + (rect.h or 0) * 0.42, cond, 0.5, 0.5)
  end
  local visible, keep = r.ImGui_BeginPopupModal(ctx, popup_id, true, flags)
  if not visible then
    if keep == false then
      dlg.confirm = nil
    end
    return false
  end
  local n = #conf.paths
  local plural = n == 1 and "" or "s"
  local trash = conf.action == "trash"
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  if trash then
    draw_trash_icon(dl, x + 12, y + 12, 18, UI_THEME.danger)
  else
    ui_button_draw_icon(dl, "close", x + 12, y + 12, 18, UI_THEME.danger)
  end
  draw_scaled_text(dl, x + 32, y + 2,
    UI_THEME.text, trash and string.format("Move %d file%s to the Trash?", n, plural)
      or string.format("Remove %d missing file%s from the library?", n, plural), 1.12)
  r.ImGui_Dummy(ctx, 440, 26)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, trash
    and "They are removed from the library too. You can put them back from the Trash."
    or "The files are already gone from disk. Nothing on disk is touched.")
  r.ImGui_Spacing(ctx)

  local by_path = {}
  for _, row in ipairs(dlg.rows or {}) do
    by_path[row.path] = row
  end
  local list_h = math.min(200, n * 22 + 10)
  if r.ImGui_BeginChild(ctx, "##scr_confirm_list", 440, list_h, sm_child_border_flag()) then
    local ldl = r.ImGui_GetWindowDrawList(ctx)
    for i = 1, n do
      local p = conf.paths[i]
      local row = by_path[p]
      local cause = SM_SCAN_CAUSE_BY_ID[(row and row.cause) or "unreadable"]
      local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
      r.ImGui_DrawList_AddCircleFilled(ldl, lx + 6, ly + 9, 3, cause.color)
      local name = (row and row.name) or p:match("([^/\\]+)$") or p
      r.ImGui_SetCursorScreenPos(ctx, lx + 16, ly + 1)
      r.ImGui_Text(ctx, fit_text(name, 250))
      r.ImGui_SameLine(ctx, 0, 10)
      r.ImGui_TextColored(ctx, UI_THEME.text_mute, fit_text((row and row.detail) or "", 150))
      r.ImGui_SetCursorScreenPos(ctx, lx, ly + 22)
    end
    imgui_end_child(true)
  end
  r.ImGui_Spacing(ctx)
  local yes_label = trash and string.format("Move %d to Trash", n) or string.format("Remove %d", n)
  local yes_w = r.ImGui_CalcTextSize(ctx, yes_label) + 26
  if draw_ui_button("scr_confirm_yes", yes_label, yes_w, 28, { compact = true, style = "danger" }) then
    sm_scan_report_apply(dlg, conf.action, conf.paths)
    if r.ImGui_CloseCurrentPopup then
      r.ImGui_CloseCurrentPopup(ctx)
    end
  end
  r.ImGui_SameLine(ctx)
  if draw_ui_button("scr_confirm_no", "Cancel", 90, 28, { compact = true })
      or (r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)) then
    dlg.confirm = nil
    if r.ImGui_CloseCurrentPopup then
      r.ImGui_CloseCurrentPopup(ctx)
    end
  end
  r.ImGui_EndPopup(ctx)
  return true
end

-- One chip per cause with its count; clicking one scrolls to (and opens) its group.
local function draw_cause_chips(dlg, counts)
  local flow = ui_flow_begin(6)
  local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
  local h = 24
  for _, cause in ipairs(SM_SCAN_CAUSES) do
    local n = counts[cause.id] or 0
    if n > 0 then
      local label = cause.label .. "  " .. sm_format_count(n)
      local w = r.ImGui_CalcTextSize(ctx, label) + 26
      ui_flow_place(flow, w)
      r.ImGui_InvisibleButton(ctx, "##scr_chip_" .. cause.id, w, h)
      local hovered = r.ImGui_IsItemHovered(ctx)
      if r.ImGui_IsItemClicked(ctx, 0) then
        dlg.jump = cause.id
        dlg.open[cause.id] = true
      end
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x0, y0 = r.ImGui_GetItemRectMin(ctx)
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, with_alpha(cause.color, hovered and 0x40 or 0x22), h * 0.5)
      r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + w - 0.5, y0 + h - 0.5, with_alpha(cause.color, hovered and 0xE0 or 0x80), h * 0.5, 0, 1.0)
      r.ImGui_DrawList_AddCircleFilled(dl, x0 + 11, y0 + h * 0.5, 3, cause.color)
      r.ImGui_DrawList_AddText(dl, x0 + 19, y0 + (h - th) * 0.5, hovered and UI_THEME.text or cause.color, label)
      if hovered and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, cause.title)
      end
    end
  end
end

function render_scan_complete_dialog()
  local dlg = state.scan_complete_dialog
  if type(dlg) ~= "table" then
    return
  end
  dlg.open = dlg.open or {}
  if dlg.open.silent == nil and sm_scan_report_counts(dlg).problems > 0 then
    dlg.open.silent = false
  end
  dlg.show_all = dlg.show_all or {}
  local counts = sm_scan_report_counts(dlg)
  local has_rows = #(dlg.rows or {}) > 0
  local rect = state.main_window_rect
  local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
  if rect and r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, rect.x + (rect.w or 0) * 0.5, rect.y + (rect.h or 0) * 0.42, cond, 0.5, 0.5)
  end
  if r.ImGui_SetNextWindowSize then
    if has_rows then
      r.ImGui_SetNextWindowSize(ctx, 680, 620, cond)
    else
      r.ImGui_SetNextWindowSize(ctx, 520, 0, cond)
    end
  end
  local flags = 0
  if (not has_rows) and r.ImGui_WindowFlags_AlwaysAutoResize then
    flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize()
  end
  if r.ImGui_WindowFlags_NoCollapse then
    flags = flags | r.ImGui_WindowFlags_NoCollapse()
  end
  if r.ImGui_WindowFlags_NoDocking then
    flags = flags | r.ImGui_WindowFlags_NoDocking()
  end
  local visible, open = r.ImGui_Begin(ctx, "Scan complete##scan_done", true, flags)
  if visible then
    draw_report_header(dlg, counts)
    r.ImGui_Dummy(ctx, 1, 4)
    draw_report_tiles(dlg, counts)

    if dlg.banner then
      r.ImGui_Dummy(ctx, 1, 4)
      if r.ImGui_PushTextWrapPos then
        r.ImGui_PushTextWrapPos(ctx, 0)
      end
      r.ImGui_TextColored(ctx, UI_THEME.danger, dlg.banner)
      if r.ImGui_PopTextWrapPos then
        r.ImGui_PopTextWrapPos(ctx)
      end
    end

    if has_rows then
      r.ImGui_Dummy(ctx, 1, 6)
      -- Section caption with the one-click cleanup on the right.
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      local avail = r.ImGui_GetContentRegionAvail(ctx) or 400
      local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
      r.ImGui_DrawList_AddText(dl, x + 2, y + (26 - th) * 0.5, UI_THEME.text_mute, "FILES TO CHECK")
      if counts.broken > 0 then
        local label = string.format("Move %d broken file%s to Trash", counts.broken, counts.broken == 1 and "" or "s")
        local bw = r.ImGui_CalcTextSize(ctx, label) + 44
        r.ImGui_SetCursorScreenPos(ctx, x + avail - bw, y)
        if draw_ui_button("scr_trash_broken", "", bw, 26, { compact = true, style = "danger" }) then
          ask_confirm(dlg, "trash", sm_scan_report_paths(dlg, "broken"))
        end
        local bx0, by0 = r.ImGui_GetItemRectMin(ctx)
        local hot = r.ImGui_IsItemHovered(ctx)
        draw_trash_icon(dl, bx0 + 16, by0 + 13, 14, hot and 0xFFFFFFFF or 0xF0C4C4FF)
        r.ImGui_DrawList_AddText(dl, bx0 + 30, by0 + (26 - th) * 0.5, hot and 0xFFFFFFFF or 0xF0C4C4FF, label)
      end
      r.ImGui_SetCursorScreenPos(ctx, x, y + 32)
      draw_cause_chips(dlg, counts)
      r.ImGui_Dummy(ctx, 1, 4)

      local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
      local list_h = math.max(160, (avail_h or 300) - 46)
      if r.ImGui_BeginChild(ctx, "scan_report_list", 0, list_h, 0) then
        draw_report_groups(dlg, counts)
        imgui_end_child(true)
      end
    else
      r.ImGui_Dummy(ctx, 1, 6)
      if (dlg.error_count or 0) > 0 then
        r.ImGui_TextColored(ctx, UI_THEME.text_dim, string.format(
          "The analyzer hit %d error%s on the way, but every file has its data now.",
          dlg.error_count, dlg.error_count == 1 and "" or "s"))
      else
        r.ImGui_TextColored(ctx, UI_THEME.success, "Every file was analyzed.")
      end
    end

    -- Footer.
    r.ImGui_Dummy(ctx, 1, 4)
    r.ImGui_Separator(ctx)
    r.ImGui_Dummy(ctx, 1, 4)
    if draw_ui_button("scan_done_copy", "Copy report", 0, 28, { compact = true }) then
      if r.ImGui_SetClipboardText then
        r.ImGui_SetClipboardText(ctx, dlg.clipboard or "")
      end
      sm_notify("Scan report copied")
    end
    if counts.retry > 0 then
      r.ImGui_SameLine(ctx)
      if draw_ui_button("scan_done_retry", string.format("Retry %s file%s", sm_format_count(counts.retry),
          counts.retry == 1 and "" or "s"), 0, 28, { compact = true }) then
        sm_scan_report_retry(dlg, sm_scan_report_paths(dlg, "retry"))
      end
    end
    local done_w = 96
    r.ImGui_SameLine(ctx)
    local room = r.ImGui_GetContentRegionAvail(ctx) or 0
    if room > done_w then
      r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + room - done_w)
    end
    local closing = false
    if draw_ui_button("scan_done_ok", "Done", done_w, 28, { compact = true, style = "success" }) then
      closing = true
    end
    local modal_open = draw_confirm_modal(dlg)
    if (not modal_open) and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      closing = true
    end
    if closing then
      state.scan_complete_dialog = nil
    end
  end
  end_window(visible, true)
  if open == false then
    state.scan_complete_dialog = nil
  end
end

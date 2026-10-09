-- Sample Map Browser module: seq_pattern_popup
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- True when a still-to-be-submitted list row intersects the current clip rect.
function seq_pattern_list_item_visible(row_h)
  local w = math.max(1.0, r.ImGui_GetContentRegionAvail(ctx))
  local h = math.max(1.0, row_h or 1.0)
  if r.ImGui_IsRectVisibleEx then
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    return r.ImGui_IsRectVisibleEx(ctx, x, y, x + w, y + h)
  end
  if r.ImGui_IsRectVisible then
    return r.ImGui_IsRectVisible(ctx, w, h)
  end
  return true
end

-- Small pill label for inline badges (e.g. variation # tags).
function draw_ui_pill_label(dl, x, cy, text, opts)
  opts = opts or {}
  local pad_x = opts.pad_x or 6.0
  local pad_y = opts.pad_y or 2.0
  local rounding = opts.rounding or 5.0
  local bg = opts.bg or UI_THEME.accent_fill
  local border = opts.border or UI_THEME.accent
  local text_col = opts.text_col or UI_THEME.text
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local w = tw + pad_x * 2.0
  local h = th + pad_y * 2.0
  local y = cy - h * 0.5
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, rounding)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, border, rounding, 0, opts.border_w or 1.0)
  r.ImGui_DrawList_AddText(dl, x + pad_x, y + pad_y, text_col, text)
  return w, h
end

function open_seq_pattern_popup()
  state.seq_pattern_window_open = not state.seq_pattern_window_open
end

-- Position the preset popup flush against the left or right edge of the main
-- window (whichever side has room in the viewport) so it never covers the grid.
function seq_position_pattern_popup()
  local popup_w = SEQ_PATTERN_POPUP_W
  local rect = state.main_window_rect
  if not rect then
    if r.ImGui_SetNextWindowSize then
      r.ImGui_SetNextWindowSize(ctx, popup_w, 640.0)
    end
    if r.ImGui_SetNextWindowSizeConstraints then
      r.ImGui_SetNextWindowSizeConstraints(ctx, popup_w, 200.0, popup_w, 10000.0)
    end
    return
  end

  local vp_x, vp_w = nil, nil
  if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetPos and r.ImGui_Viewport_GetSize then
    local vp = r.ImGui_GetMainViewport(ctx)
    if vp then
      vp_x = select(1, r.ImGui_Viewport_GetPos(vp))
      vp_w = select(1, r.ImGui_Viewport_GetSize(vp))
    end
  end

  local right_x = rect.x + rect.w
  local px
  if vp_x and vp_w and (right_x + popup_w) <= (vp_x + vp_w) then
    px = right_x                       -- attach just outside the right edge
  elseif rect.x - popup_w >= (vp_x or 0) then
    px = rect.x - popup_w              -- otherwise attach outside the left edge
  else
    px = right_x - popup_w             -- last resort: overlay the right edge
  end

  if r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, px, rect.y)
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, popup_w, rect.h)
  end
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, popup_w, 200.0, popup_w, 10000.0)
  end
end

function seq_pattern_variation_store(style_key)
  state.seq_pattern_variations = state.seq_pattern_variations or {}
  local store = state.seq_pattern_variations[style_key]
  if not store then
    store = { counter = 0, entries = {} }
    state.seq_pattern_variations[style_key] = store
  end
  return store
end

function seq_pattern_variation_count(style_key)
  local store = state.seq_pattern_variations and state.seq_pattern_variations[style_key]
  if not store then return 0 end
  return #store.entries
end

function seq_record_pattern_variation(style_key, strength, seed)
  local store = seq_pattern_variation_store(style_key)
  store.counter = store.counter + 1
  local entry = {
    id = store.counter,
    name = get_seq_gen_style_label(style_key) .. " #" .. tostring(store.counter),
    seed = seed,
    strength = strength,
  }
  store.entries[#store.entries + 1] = entry
  return entry
end

function seq_record_ai_variation(style_key, variation, role_map)
  local store = seq_pattern_variation_store(style_key)
  store.counter = store.counter + 1
  local entry = {
    id = store.counter,
    name = get_seq_gen_style_label(style_key) .. " #" .. tostring(store.counter),
    ai = true,
    ai_variation = variation,
    ai_pattern = role_map,
  }
  store.entries[#store.entries + 1] = entry
  return entry
end

-- Snapshot the affected pattern before the *first* pattern application of a
-- confirmation session, so the X button can revert all the way back to the
-- state that exmizisted before the user started auditioning patterns.
function seq_pattern_confirm_capture(region)
  if not region then return end
  local c = state.seq_pattern_confirm
  if c and c.active and tostring(c.pattern_id) == tostring(region.pattern_id)
      and c.proj == seq_pattern_confirm_current_proj() then
    return
  end
  -- A different pattern (or project) starts a new confirmation session;
  -- the previous audition is implicitly kept.
  local key = tostring(region.pattern_id)
  state.seq_pattern_confirm = {
    active = true,
    region_id = region.id,
    pattern_id = region.pattern_id,
    proj = seq_pattern_confirm_current_proj(),
    snapshot = clone_table_deep(state.seq_patterns[key]),
  }
end

function seq_pattern_confirm_current_proj()
  if r.EnumProjects then
    local proj = r.EnumProjects(-1)
    return proj
  end
  return nil
end

function seq_pattern_confirm_commit()
  state.seq_pattern_confirm = nil
end

function seq_pattern_confirm_restore()
  local c = state.seq_pattern_confirm
  if not c then return end
  if c.proj ~= seq_pattern_confirm_current_proj() then
    state.seq_pattern_confirm = nil
    return
  end
  local key = tostring(c.pattern_id)
  local label = begin_seq_undo("Revert pattern changes")
  if c.snapshot == nil then
    state.seq_patterns[key] = nil
  else
    state.seq_patterns[key] = clone_table_deep(c.snapshot)
  end
  state.selected_seq_note = nil
  save_config()
  sync_seq_pattern_regions(c.pattern_id)
  end_seq_undo(label)
  state.seq_pattern_confirm = nil
end

function render_seq_pattern_confirm_bar(dl, x0, y0, x1, y1)
  local cy = (y0 + y1) * 0.5
  r.ImGui_DrawList_AddRectFilled(dl, x0 + 2, y0 + 2, x1 + 2, y1 + 2, 0x00000066, 8.0)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, 0x0E2A18F8, 8.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, UI_THEME.accent, 8.0, 0, 1.5)

  local txt = "Keep pattern?"
  local _, th = r.ImGui_CalcTextSize(ctx, txt)
  r.ImGui_DrawList_AddText(dl, x0 + 12.0, cy - th * 0.5, UI_THEME.text, txt)

  local btn = 24.0
  local gap = 6.0
  local bx = x1 - 12.0 - btn * 2.0 - gap
  local by = cy - btn * 0.5
  r.ImGui_SetCursorScreenPos(ctx, bx, by)
  if draw_ui_button("seq_pattern_confirm_apply", nil, btn, btn, { icon = "check", style = "success", compact = true }) then
    seq_pattern_confirm_commit()
  end
  r.ImGui_SetCursorScreenPos(ctx, bx + btn + gap, by)
  if draw_ui_button("seq_pattern_confirm_cancel", nil, btn, btn, { icon = "close", style = "danger", compact = true }) then
    seq_pattern_confirm_restore()
  end
end

function run_seq_pattern_preset(region, style_key, strength)
  state.seq_pattern_source = "template"
  state.seq_gen_style = normalize_seq_gen_style(style_key)
  local style = state.seq_gen_style
  if strength then
    state.seq_pattern_popup_last_style = style
    state.seq_pattern_popup_last_strength = strength
  end

  local label = begin_seq_undo(strength and "Randomize sequencer pattern" or "Generate sequencer pattern")
  local created = ensure_seq_tracks_for_roles(seq_template_roles(style))
  if created > 0 then
    log("Added " .. tostring(created) .. " track type(s) for " .. get_seq_gen_style_label(style))
    if r.TrackList_AdjustWindows then
      r.TrackList_AdjustWindows(false)
    end
    r.UpdateArrange()
  end
  if region and seq_has_generatable_track(style) then
    stamp_seq_region_kit_genres(region, style, "template", seq_style_to_library_genres(style))
    seq_pattern_confirm_capture(region)
    local seed = seq_new_seed()
    generate_seq_pattern(region, style, { random_strength = strength, random_seed = seed })
    if strength then
      seq_record_pattern_variation(style, strength, seed)
    end
  end
  end_seq_undo(label)
  save_config()
end

function seq_apply_pattern_variation(region, style_key, variation)
  if not (region and variation) then return end
  state.seq_gen_style = normalize_seq_gen_style(style_key)
  local style = state.seq_gen_style
  local label = begin_seq_undo("Apply pattern variation")
  local created = ensure_seq_tracks_for_roles(seq_template_roles(style))
  if created > 0 then
    if r.TrackList_AdjustWindows then
      r.TrackList_AdjustWindows(false)
    end
    r.UpdateArrange()
  end
  if seq_has_generatable_track(style) then
    stamp_seq_region_kit_genres(region, style, "template", seq_style_to_library_genres(style))
    seq_pattern_confirm_capture(region)
    if variation.ai_pattern then
      -- AI variations store their resulting role->step map so they reproduce
      -- exactly regardless of the current grid contents.
      seq_write_role_positions(region, style, variation.ai_pattern)
    else
      generate_seq_pattern(region, style, { random_strength = variation.strength, random_seed = variation.seed })
    end
  end
  end_seq_undo(label)
  save_config()
end

-- ===================================================================
-- AI pattern variation (local Python sidecar, SampleMapDrumAI.py)
-- ===================================================================

-- Write a role -> {16th positions} map into the region's pattern, repeating each
-- role's positions across every bar (same contract the built-in templates use).
function seq_write_role_positions(region, style_key, role_map)
  if not region or type(role_map) ~= "table" then return 0 end
  style_key = normalize_seq_gen_style(style_key)
  local pattern = get_seq_pattern(region.pattern_id, true)
  if not pattern then return 0 end

  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local region_len_qn = get_seq_region_length_qn(region)
  local steps_per_bar = math.max(1, math.floor((4.0 / grid_qn) + 0.5))
  local bar_count = math.max(1, math.floor((region_len_qn / 4.0) + 0.5))
  local max_steps = math.max(1, math.floor((region_len_qn / grid_qn) + 0.5))

  local locked_notes = seq_collect_locked_notes(pattern, grid_qn)
  seq_clear_generated_role_tracks(pattern, role_map)
  state.selected_seq_note = nil
  local hit_count = seq_restore_locked_notes(region, locked_notes)

  for _, slot in ipairs(state.seq_tracks) do
    if slot.sample_path then
      local role = infer_seq_track_role(slot)
      local positions = role_map[role]
      if type(positions) == "table" then
        local seen = seq_merge_locked_cell_seen(seq_locked_step_seen(locked_notes, slot.id), pattern, slot.id)
        for bar = 0, bar_count - 1 do
          for _, pos16 in ipairs(positions) do
            local grid_step = seq_template_step_to_grid_step(pos16, steps_per_bar)
            if grid_step then
              local step_idx = bar * steps_per_bar + grid_step
              if step_idx >= 0 and step_idx < max_steps and not seen[step_idx] then
                local note = make_default_seq_note(slot, step_idx, step_idx * grid_qn)
                if note then
                  note.offset_qn = seq_pattern_base_offset(role, pos16, style_key, grid_qn)
                  if (step_idx % steps_per_bar) == 0 and note.offset_qn < 0.0 then
                    note.offset_qn = 0.0
                  end
                  set_seq_note(region, slot.id, step_idx, note)
                  seen[step_idx] = true
                  hit_count = hit_count + 1
                end
              end
            end
          end
        end
      end
    end
  end

  save_config()
  sync_seq_pattern_regions(region.pattern_id)
  return hit_count
end

-- Read the region's current pattern as a role -> {16th positions} map.
function seq_collect_current_role_positions(region)
  local map = {}
  if not region then return map end
  local pattern = get_seq_pattern(region.pattern_id, false)
  local notes_by_track = pattern and pattern.notes or nil

  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local steps_per_bar = math.max(1, math.floor((4.0 / grid_qn) + 0.5))

  for _, slot in ipairs(state.seq_tracks) do
    if slot.sample_path then
      local role = infer_seq_track_role(slot)
      local set = {}
      local notes = notes_by_track and notes_by_track[tostring(slot.id)] or nil
      if notes then
        for step_key, note in pairs(notes) do
          if note and note.enabled ~= false then
            local step_idx = tonumber(note.step) or tonumber(step_key) or 0
            local within = step_idx % steps_per_bar
            local pos16 = math.floor((within * 16.0 / steps_per_bar) + 0.5)
            if pos16 >= 0 and pos16 < 16 then
              set[pos16] = true
            end
          end
        end
      end
      -- Merge (multiple tracks can share a role) and ensure the role exists so
      -- the model also generates for assigned-but-empty tracks.
      local arr = map[role] or {}
      for p in pairs(set) do arr[#arr + 1] = p end
      table.sort(arr)
      map[role] = arr
    end
  end
  return map
end

-- Unique temp file under REAPER's resource path. os.tmpname() points at the
-- drive root on Windows, which is usually not writable.
function sm_temp_path(prefix, ext)
  local base = (r.GetResourcePath and r.GetResourcePath()) or ""
  if base == "" then
    base = SCRIPT_DIR
  end
  local dir = base .. "/Data/SampleMap/tmp"
  if state.sm_temp_dir ~= dir then
    r.RecursiveCreateDirectory(dir, 0)
    state.sm_temp_dir = dir
  end
  state.sm_temp_counter = (state.sm_temp_counter or 0) + 1
  local t = r.time_precise()
  return string.format(
    "%s/%s_%d_%06d_%d_%05d%s",
    dir, prefix or "tmp", os.time(), math.floor((t % 1) * 1000000),
    state.sm_temp_counter, math.random(0, 99999), ext or ".tmp"
  )
end

-- --- Background processes ----------------------------------------------------
-- Run argv without blocking the UI thread: a small sh/batch script is launched
-- with ExecProcess(-1/-2); it captures stdout+stderr to <base>.out and writes
-- the exit code to <base>.rc when done. Poll with sm_bg_poll on later frames.
function sm_bg_is_windows()
  return ((r.GetOS and r.GetOS()) or ""):match("Win") ~= nil
end

function sm_bg_quote(arg)
  arg = tostring(arg or "")
  if sm_bg_is_windows() then
    -- Batch files expand %VAR%; double each % so it stays literal.
    local q = arg:gsub('"', ""):gsub("%%", "%%%%")
    return '"' .. q .. '"'
  end
  local q = arg:gsub("'", "'\\''")
  return "'" .. q .. "'"
end

function sm_bg_start(argv, timeout_s)
  if not r.ExecProcess then
    return nil, "ExecProcess is unavailable"
  end
  local base = sm_temp_path("bg", "")
  local job = {
    out_path = base .. ".out",
    rc_path = base .. ".rc",
    started = r.time_precise(),
    timeout = timeout_s or 60,
  }
  local parts = {}
  for i = 1, #argv do
    parts[i] = sm_bg_quote(argv[i])
  end
  local cmd = table.concat(parts, " ")
  local body, launch, wait_mode
  if sm_bg_is_windows() then
    local function win(path)
      return sm_bg_quote((path:gsub("/", "\\")))
    end
    job.script_path = base .. ".bat"
    body = table.concat({
      "@echo off",
      "chcp 65001 >nul",
      cmd .. " > " .. win(job.out_path) .. " 2>&1",
      "(echo %ERRORLEVEL%)> " .. win(job.rc_path .. ".tmp"),
      "move /Y " .. win(job.rc_path .. ".tmp") .. " " .. win(job.rc_path) .. " >nul",
      "",
    }, "\r\n")
    local script_win = job.script_path:gsub("/", "\\")
    launch = 'cmd.exe /C ""' .. script_win .. '""'
    wait_mode = -2 -- no wait, minimized console
  else
    job.script_path = base .. ".sh"
    body = table.concat({
      cmd .. " > " .. sm_bg_quote(job.out_path) .. " 2>&1",
      "echo $? > " .. sm_bg_quote(job.rc_path .. ".tmp"),
      "mv -f " .. sm_bg_quote(job.rc_path .. ".tmp") .. " " .. sm_bg_quote(job.rc_path),
      "",
    }, "\n")
    launch = '/bin/sh "' .. job.script_path .. '"'
    wait_mode = -1 -- no wait
  end
  local fh = io.open(job.script_path, "wb")
  if not fh then
    return nil, "could not write temp script"
  end
  fh:write(body)
  fh:close()
  if not pcall(r.ExecProcess, launch, wait_mode) then
    os.remove(job.script_path)
    return nil, "could not start background process"
  end
  return job
end

-- Returns "running" | "done", output, exit_code | "timeout".
function sm_bg_poll(job)
  local fh = io.open(job.rc_path, "rb")
  if fh then
    local rc = tonumber((fh:read("*a") or ""):match("%-?%d+")) or -1
    fh:close()
    local output = ""
    local oh = io.open(job.out_path, "rb")
    if oh then
      output = oh:read("*a") or ""
      oh:close()
    end
    os.remove(job.rc_path)
    os.remove(job.out_path)
    os.remove(job.script_path)
    return "done", output, rc
  end
  if r.time_precise() - job.started > job.timeout then
    os.remove(job.script_path)
    return "timeout"
  end
  return "running"
end

function seq_drum_ai_sidecar_path()
  return SCRIPT_DIR .. "/SampleMapDrumAI.py"
end

function seq_drum_ai_available()
  -- Cached: queried every frame by the Pattern Presets window.
  if state.seq_drum_ai_present == nil then
    local fh = io.open(seq_drum_ai_sidecar_path(), "r")
    state.seq_drum_ai_present = fh ~= nil
    if fh then fh:close() end
  end
  return state.seq_drum_ai_present
end

-- Call the local Python model. Returns role_map (table) on success, or nil + err.
function seq_call_drum_ai(style_key, role_positions, variation, seed, steps_per_bar, bars)
  local sidecar = seq_drum_ai_sidecar_path()
  local fh = io.open(sidecar, "r")
  if not fh then return nil, "AI model script not found (SampleMapDrumAI.py)" end
  fh:close()

  local roles = {}
  for _, role in ipairs(SEQ_ROLE_ORDER) do
    if role_positions[role] then roles[#roles + 1] = role end
  end
  if #roles == 0 then return nil, "no assigned tracks to vary" end

  local payload = {
    genre = style_key,
    steps_per_bar = steps_per_bar or 16,
    bars = bars or 4,
    roles = roles,
    pattern = role_positions,
    variation = variation,
    seed = seed,
  }
  local ok_enc, json_payload = pcall(json_encode, payload)
  if not ok_enc then return nil, "failed to encode AI request" end

  local tmp = sm_temp_path("ai_req", ".json")
  local wf = io.open(tmp, "w")
  if not wf then return nil, "could not write temp file" end
  wf:write(json_payload)
  wf:close()

  local cmd = table.concat({
    shell_escape(PYTHON_BIN),
    shell_escape(sidecar),
    shell_escape(tmp),
  }, " ") .. " 2>&1"

  local output = nil
  local pipe = io.popen(cmd, "r")
  if pipe then
    output = pipe:read("*all")
    pipe:close()
  end
  os.remove(tmp)

  if not output or output:match("^%s*$") then
    return nil, "AI model returned no output (is python3 available?)"
  end

  -- Extract the JSON object in case python emitted warnings before it.
  local json_str = output:match("(%b{})")
  if not json_str then
    return nil, "AI model output not understood"
  end
  local ok_dec, decoded = pcall(json_decode, json_str)
  if not ok_dec or type(decoded) ~= "table" or type(decoded.pattern) ~= "table" then
    return nil, "AI model output invalid"
  end

  -- Normalize: ensure each role maps to an array of integers.
  local result = {}
  for role, positions in pairs(decoded.pattern) do
    if type(positions) == "table" then
      local arr = {}
      for _, p in ipairs(positions) do
        local n = tonumber(p)
        if n then arr[#arr + 1] = math.floor(n + 0.5) end
      end
      result[role] = arr
    end
  end
  return result
end

function run_seq_ai_variation(region, style_key, variation)
  state.seq_gen_style = normalize_seq_gen_style(style_key)
  local style = state.seq_gen_style
  variation = math.max(0.0, math.min(1.0, variation or 0.5))

  -- Run the (blocking) model subprocess before opening the undo block, so a
  -- slow or failing Python call never runs inside an open undo session.
  -- Roles the template would add are requested too (with no hits) so tracks
  -- created below still get generated parts.
  local seed = seq_new_seed()
  local role_map, err = nil, "no region"
  if region then
    local pre_grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
    local pre_steps_per_bar = math.max(1, math.floor((4.0 / pre_grid_qn) + 0.5))
    local pre_bar_count = math.max(1, math.floor((get_seq_region_length_qn(region) / 4.0) + 0.5))
    local pre_positions = seq_collect_current_role_positions(region)
    for _, role in ipairs(seq_template_roles(style)) do
      if pre_positions[role] == nil then
        pre_positions[role] = {}
      end
    end
    role_map, err = seq_call_drum_ai(style, pre_positions, variation, seed, pre_steps_per_bar, pre_bar_count)
  end

  local label = begin_seq_undo("AI pattern variation")
  local created = ensure_seq_tracks_for_roles(seq_template_roles(style))
  if created > 0 then
    if r.TrackList_AdjustWindows then
      r.TrackList_AdjustWindows(false)
    end
    r.UpdateArrange()
  end

  if not (region and seq_has_generatable_track(style)) then
    end_seq_undo(label)
    save_config()
    return false
  end

  seq_pattern_confirm_capture(region)
  if not role_map then
    -- Graceful fallback: use the built-in randomizer so the click still does
    -- something musical even when the model can't be reached.
    log("AI variation unavailable (" .. tostring(err) .. "); using built-in randomizer")
    generate_seq_pattern(region, style, { random_strength = 3, random_seed = seed })
    end_seq_undo(label)
    save_config()
    return false
  end

  stamp_seq_region_kit_genres(region, style, "template", seq_style_to_library_genres(style))
  local hits = seq_write_role_positions(region, style, role_map)
  seq_record_ai_variation(style, variation, role_map)
  log(string.format("AI variation (%s, var %.0f%%, %d hits)", get_seq_gen_style_label(style), variation * 100.0, hits))
  end_seq_undo(label)
  save_config()
  return true
end

-- ===================================================================
-- Groove MIDI Dataset (Magenta) — SampleMapGrooveMIDI.py
-- Human drum performances from Google Magenta's Groove MIDI Dataset.
-- ===================================================================

function seq_gmd_sidecar_path()
  return SCRIPT_DIR .. "/SampleMapGrooveMIDI.py"
end

function seq_gmd_available()
  if state.seq_gmd_script_present ~= nil then
    return state.seq_gmd_script_present
  end
  local fh = io.open(seq_gmd_sidecar_path(), "r")
  state.seq_gmd_script_present = fh ~= nil
  if fh then fh:close() end
  return state.seq_gmd_script_present
end

-- Write a Groove MIDI request to a temp JSON file. Returns path or nil + err.
function seq_gmd_write_request(payload)
  local ok_enc, json_payload = pcall(json_encode, payload or {})
  if not ok_enc then return nil, "failed to encode Groove MIDI request" end
  local tmp = sm_temp_path("gmd_req", ".json")
  local wf = io.open(tmp, "w")
  if not wf then return nil, "could not write temp file" end
  wf:write(json_payload)
  wf:close()
  return tmp
end

-- Decode sidecar stdout. Returns decoded table or nil + err.
function seq_gmd_parse_output(output)
  if not output or output:match("^%s*$") then
    return nil, "Groove MIDI returned no output (is python3 / network available?)"
  end
  local json_str = output:match("(%b{})")
  if not json_str then
    return nil, "Groove MIDI output not understood"
  end
  local ok_dec, decoded = pcall(json_decode, json_str)
  if not ok_dec or type(decoded) ~= "table" then
    return nil, "Groove MIDI output invalid"
  end
  if decoded.error then
    return nil, tostring(decoded.error)
  end
  return decoded
end

-- Call the Groove MIDI sidecar synchronously (only for quick local actions
-- such as "get"). Returns decoded table on success, or nil + err.
function seq_call_gmd(payload)
  local sidecar = seq_gmd_sidecar_path()
  local fh = io.open(sidecar, "r")
  if not fh then return nil, "Groove MIDI script not found (SampleMapGrooveMIDI.py)" end
  fh:close()

  local tmp, werr = seq_gmd_write_request(payload)
  if not tmp then return nil, werr end

  local cmd = table.concat({
    shell_escape(PYTHON_BIN),
    shell_escape(sidecar),
    shell_escape(tmp),
  }, " ") .. " 2>&1"

  local output = nil
  local pipe = io.popen(cmd, "r")
  if pipe then
    output = pipe:read("*all")
    pipe:close()
  end
  os.remove(tmp)

  return seq_gmd_parse_output(output)
end

-- --- Background Groove MIDI jobs ("status", "ensure", "list") ----------------
-- These can take long (dataset download) and must not block the UI. One job
-- per kind runs in the background; seq_gmd_bg_tick (called from the main loop)
-- applies the result. Failures back off for SEQ_GMD_RETRY_S unless the user
-- clicks again.
SEQ_GMD_RETRY_S = 60.0

function seq_gmd_job_running(kind)
  return state.seq_gmd_jobs ~= nil and state.seq_gmd_jobs[kind] ~= nil
end

function seq_gmd_start_job(kind, payload, timeout_s)
  state.seq_gmd_jobs = state.seq_gmd_jobs or {}
  if state.seq_gmd_jobs[kind] then
    return state.seq_gmd_jobs[kind]
  end
  if not seq_gmd_available() then
    return nil, "Groove MIDI script not found (SampleMapGrooveMIDI.py)"
  end
  local req, werr = seq_gmd_write_request(payload)
  if not req then
    return nil, werr
  end
  local job, err = sm_bg_start({ PYTHON_BIN, seq_gmd_sidecar_path(), req }, timeout_s)
  if not job then
    os.remove(req)
    return nil, err
  end
  job.req_path = req
  state.seq_gmd_jobs[kind] = job
  return job
end

function seq_gmd_on_job_done(kind, job, result, err)
  local now = r.time_precise()
  if kind == "status" then
    if result and result.ready then
      state.seq_gmd_ready = true
      state.seq_gmd_status_msg = string.format("Ready — %d grooves", tonumber(result.count) or 0)
    else
      state.seq_gmd_ready = false
      state.seq_gmd_status_msg = "Not downloaded yet"
    end
  elseif kind == "ensure" then
    if not result then
      state.seq_gmd_ready = false
      state.seq_gmd_status_msg = tostring(err)
      state.seq_gmd_ensure_failed_at = now
      log("Groove MIDI ensure failed: " .. tostring(err))
      return
    end
    state.seq_gmd_ensure_failed_at = nil
    state.seq_gmd_ready = result.ready == true
    state.seq_gmd_status_msg = string.format(
      "Ready — %d grooves",
      tonumber(result.count) or 0
    )
    state.seq_gmd_list_key = nil
    log("Groove MIDI Dataset ready (" .. tostring(result.count or 0) .. " files)")
  elseif kind == "list" then
    if not result then
      state.seq_gmd_status_msg = tostring(err)
      state.seq_gmd_list_failed_at = now
      state.seq_gmd_list_failed_key = job.list_key
      return
    end
    state.seq_gmd_list_failed_at = nil
    state.seq_gmd_items = result.items or {}
    state.seq_gmd_total = tonumber(result.total) or #state.seq_gmd_items
    state.seq_gmd_list_key = job.list_key
    local groups = seq_gmd_rebuild_groups()
    state.seq_gmd_status_msg = string.format(
      "%d preset%s · %d groove%s",
      #groups,
      #groups == 1 and "" or "s",
      state.seq_gmd_total,
      state.seq_gmd_total == 1 and "" or "s"
    )
  end
end

function seq_gmd_bg_tick()
  local jobs = state.seq_gmd_jobs
  if not jobs or next(jobs) == nil then
    return
  end
  for kind, job in pairs(jobs) do
    local status, output = sm_bg_poll(job)
    if status ~= "running" then
      jobs[kind] = nil
      os.remove(job.req_path)
      local result, err
      if status == "timeout" then
        err = "Groove MIDI request timed out"
      else
        result, err = seq_gmd_parse_output(output)
      end
      seq_gmd_on_job_done(kind, job, result, err)
    end
  end
end

-- Returns true when the dataset is ready. Otherwise starts the download in the
-- background (unless one is running or a recent failure is backing off;
-- force = user click bypasses the back-off) and returns false.
function seq_gmd_ensure(force)
  if state.seq_gmd_ready and not force then
    return true
  end
  if not seq_gmd_available() then
    state.seq_gmd_ready = false
    state.seq_gmd_status_msg = "SampleMapGrooveMIDI.py missing"
    return false
  end
  if seq_gmd_job_running("ensure") then
    return false
  end
  if not force and state.seq_gmd_ensure_failed_at
      and (r.time_precise() - state.seq_gmd_ensure_failed_at) < SEQ_GMD_RETRY_S then
    return false
  end
  local job, err = seq_gmd_start_job("ensure", { action = "ensure" }, 300)
  if not job then
    state.seq_gmd_ready = false
    state.seq_gmd_status_msg = tostring(err)
    state.seq_gmd_ensure_failed_at = r.time_precise()
    log("Groove MIDI ensure failed: " .. tostring(err))
    return false
  end
  state.seq_gmd_status_msg = "Downloading Groove MIDI Dataset…"
  return false
end

function seq_gmd_list_cache_key()
  return tostring(state.seq_gmd_beat_type or "beat")
end

function seq_gmd_pretty_label(style)
  local s = tostring(style or "")
  if s == "" then return "Groove" end
  local parts = {}
  for seg in s:gmatch("[^/]+") do
    seg = seg:gsub("%-", " ")
    local words = {}
    for w in seg:gmatch("%S+") do
      words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
    end
    parts[#parts + 1] = table.concat(words, " ")
  end
  return table.concat(parts, " / ")
end

-- Subgenre tail for flat child labels: jazz/march -> "March", rock -> "Rock".
function seq_gmd_subgenre_short_label(full_style, primary)
  local full = tostring(full_style or "")
  local tail = full
  if full:find("/", 1, true) then
    tail = full:match("/([^/]+)$") or full
  end
  local parts = {}
  for seg in tail:gmatch("[^/]+") do
    seg = seg:gsub("%-", " ")
    local words = {}
    for w in seg:gmatch("%S+") do
      words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
    end
    parts[#parts + 1] = table.concat(words, " ")
  end
  local label = table.concat(parts, " ")
  if label == "" then
    label = seq_gmd_pretty_label(primary or full)
  end
  return label
end

-- Collapse Groove MIDI by primary genre; individual performances are flat children
-- named like "March 1", "March 2" under Jazz.
function seq_gmd_rebuild_groups()
  local items = state.seq_gmd_items or {}
  local by_primary = {}
  local order = {}
  for _, item in ipairs(items) do
    if type(item) == "table" then
      local primary = tostring(item.style_primary or ""):lower()
      if primary == "" then
        local full = tostring(item.style or "")
        primary = (full:match("^([^/]+)") or full):lower()
      end
      if primary == "" then primary = "groove" end

      local full_style = tostring(item.style or primary)
      if full_style == "" then full_style = primary end

      local group = by_primary[primary]
      if not group then
        group = {
          name = primary,
          key = "gmd:" .. primary,
          label = seq_gmd_pretty_label(primary),
          items = {},
          subgenres = {},
          subgenre_by_name = {},
        }
        by_primary[primary] = group
        order[#order + 1] = group
      end

      group.items[#group.items + 1] = item

      local sub = group.subgenre_by_name[full_style]
      if not sub then
        sub = {
          name = full_style,
          label = seq_gmd_pretty_label(full_style),
          items = {},
        }
        group.subgenre_by_name[full_style] = sub
        group.subgenres[#group.subgenres + 1] = sub
      end
      sub.items[#sub.items + 1] = item
    end
  end

  table.sort(order, function(a, b)
    return tostring(a.label):lower() < tostring(b.label):lower()
  end)
  for _, group in ipairs(order) do
    table.sort(group.subgenres, function(a, b)
      return tostring(a.label):lower() < tostring(b.label):lower()
    end)
    for _, sub in ipairs(group.subgenres) do
      table.sort(sub.items, function(a, b)
        local ba = tonumber(a.bpm) or 0
        local bb = tonumber(b.bpm) or 0
        if ba ~= bb then return ba < bb end
        return tostring(a.id or "") < tostring(b.id or "")
      end)
    end
    table.sort(group.items, function(a, b)
      local ba = tonumber(a.bpm) or 0
      local bb = tonumber(b.bpm) or 0
      if ba ~= bb then return ba < bb end
      return tostring(a.id or "") < tostring(b.id or "")
    end)
    group.children = {}
    for _, sub in ipairs(group.subgenres) do
      local short = seq_gmd_subgenre_short_label(sub.name, group.name)
      for i, item in ipairs(sub.items) do
        group.children[#group.children + 1] = {
          item = item,
          label = short .. " " .. tostring(i),
          subgenre = sub.name,
          index = i,
        }
      end
    end
    group.subgenre_by_name = nil
    group.template_style = seq_pattern_match_template_for_gmd(group)
    group.search_hay = seq_gmd_group_search_hay(group)
  end
  state.seq_gmd_groups = order
  state.seq_gmd_group_by_name = by_primary
  state.seq_pattern_browser_cache_key = nil
  state.seq_pattern_browser_cache = nil
  return order
end

function seq_gmd_group_search_hay(group)
  local parts = {
    tostring(group.label or ""),
    tostring(group.name or ""),
    "groove midi",
  }
  local template = group.template_style
  if type(template) == "table" then
    parts[#parts + 1] = tostring(template.label or template.key or "")
    parts[#parts + 1] = tostring(template.key or "")
    for _, role in ipairs(seq_template_roles(template.key)) do
      parts[#parts + 1] = SEQ_ROLE_LABELS[role] or role
    end
  end
  for _, child in ipairs(group.children or {}) do
    parts[#parts + 1] = tostring(child.label or "")
    parts[#parts + 1] = tostring(child.subgenre or "")
    local item = child.item
    if type(item) == "table" then
      parts[#parts + 1] = tostring(item.drummer or "")
      parts[#parts + 1] = tostring(item.bpm or "")
    end
  end
  return table.concat(parts, " "):lower()
end

function seq_gmd_find_group(style_name)
  if not style_name then return nil end
  local by_name = state.seq_gmd_group_by_name
  if type(by_name) == "table" then
    return by_name[style_name]
  end
  return nil
end

function seq_gmd_refresh_list(force)
  if not state.seq_gmd_ready then
    return false
  end
  local key = seq_gmd_list_cache_key()
  if not force and state.seq_gmd_list_key == key
      and type(state.seq_gmd_items) == "table"
      and type(state.seq_gmd_groups) == "table" then
    return true
  end

  -- Listing runs in the background (seq_gmd_bg_tick applies the result);
  -- after a failure, retry only on force or after SEQ_GMD_RETRY_S.
  if seq_gmd_job_running("list") then
    return false
  end
  if not force and state.seq_gmd_list_failed_at
      and state.seq_gmd_list_failed_key == key
      and (r.time_precise() - state.seq_gmd_list_failed_at) < SEQ_GMD_RETRY_S then
    return false
  end
  local job, err = seq_gmd_start_job("list", {
    action = "list",
    style = "all",
    beat_type = state.seq_gmd_beat_type or "beat",
    limit = 0, -- 0 = return every matching groove
    offset = 0,
  }, 60)
  if not job then
    state.seq_gmd_status_msg = tostring(err)
    state.seq_gmd_list_failed_at = r.time_precise()
    state.seq_gmd_list_failed_key = key
    return false
  end
  job.list_key = key
  state.seq_gmd_status_msg = "Loading grooves…"
  return false
end

function seq_gmd_cycle_beat_type()
  local order = { "beat", "fill", "all" }
  local cur = state.seq_gmd_beat_type or "beat"
  local idx = 1
  for i, v in ipairs(order) do
    if v == cur then idx = i break end
  end
  state.seq_gmd_beat_type = order[(idx % #order) + 1]
  state.seq_gmd_list_key = nil
end

-- Pick a variation from a merged Groove MIDI preset. Plain click prefers the
-- current selection / median BPM; dice strength 1..6 samples a BPM band.
function seq_gmd_pick_item(group, strength)
  if not group or type(group.items) ~= "table" or #group.items == 0 then
    return nil
  end
  local items = group.items
  local n = #items
  if not strength then
    if state.seq_gmd_selected_id then
      for _, item in ipairs(items) do
        if tostring(item.id) == tostring(state.seq_gmd_selected_id) then
          return item
        end
      end
    end
    return items[math.floor((n + 1) / 2)]
  end

  strength = math.max(1, math.min(6, math.floor(tonumber(strength) or 1)))
  local lo = math.floor((strength - 1) / 6 * n) + 1
  local hi = math.floor(strength / 6 * n)
  if hi < lo then hi = lo end
  if hi > n then hi = n end
  local seed = seq_new_seed()
  local idx = lo + ((seed - 1) % (hi - lo + 1))
  return items[idx]
end

function seq_gmd_normalize_role_map(pattern)
  local result = {}
  if type(pattern) ~= "table" then return result end
  for role, positions in pairs(pattern) do
    if type(positions) == "table" then
      local arr = {}
      for _, p in ipairs(positions) do
        local n = tonumber(p)
        if n then arr[#arr + 1] = math.floor(n + 0.5) end
      end
      if #arr > 0 then
        result[tostring(role)] = arr
      end
    end
  end
  return result
end

function seq_gmd_apply_result(region, result)
  if not region or type(result) ~= "table" then return false end
  local role_map = seq_gmd_normalize_role_map(result.pattern)
  local roles = {}
  if type(result.roles) == "table" then
    for _, role in ipairs(result.roles) do
      roles[#roles + 1] = tostring(role)
    end
  end
  if #roles == 0 then
    for _, role in ipairs(SEQ_ROLE_ORDER) do
      if role_map[role] then roles[#roles + 1] = role end
    end
  end
  if #roles == 0 then
    log("Groove MIDI pattern had no mappable drum hits")
    return false
  end

  local label = begin_seq_undo("Load Groove MIDI pattern")
  local created = ensure_seq_tracks_for_roles(roles)
  if created > 0 then
    if r.TrackList_AdjustWindows then
      r.TrackList_AdjustWindows(false)
    end
    r.UpdateArrange()
  end

  seq_pattern_confirm_capture(region)
  local style = normalize_seq_gen_style(state.seq_gen_style)
  local hits = seq_write_role_positions(region, style, role_map)

  local meta = result.meta or {}
  state.seq_pattern_source = "gmd"
  state.seq_gmd_selected_id = meta.id
  local primary = tostring(meta.style_primary or ""):lower()
  if primary == "" then
    local style_full = tostring(meta.style or "")
    primary = (style_full:match("^([^/]+)") or style_full):lower()
  end
  if primary ~= "" then
    state.seq_gmd_selected_style = primary
  end
  local gmd_style_label = tostring(meta.style or meta.style_primary or primary)
  stamp_seq_region_kit_genres(
    region,
    gmd_style_label ~= "" and gmd_style_label or primary,
    "gmd",
    seq_library_genres_from_text(gmd_style_label ~= "" and gmd_style_label or primary)
  )
  local style_label = seq_gmd_pretty_label(meta.style or meta.style_primary or state.seq_gmd_selected_style)
  local bpm = tonumber(meta.bpm)
  local beat = tostring(meta.beat_type or "")
  log(string.format(
    "Loaded Groove MIDI: %s%s%s (%d hits, bar %s/%s)",
    style_label,
    bpm and (" @ " .. tostring(bpm) .. " BPM") or "",
    beat ~= "" and (" / " .. beat) or "",
    hits,
    tostring(result.bar_offset or 0),
    tostring(result.total_bars or "?")
  ))
  end_seq_undo(label)
  save_config()
  return hits > 0
end

function run_seq_gmd_load_id(region, entry_id)
  if not region or not entry_id then return false end
  if not seq_gmd_ensure(false) then return false end
  local result, err = seq_call_gmd({
    action = "get",
    id = entry_id,
    bars = 1,
    seed = seq_new_seed(),
  })
  if not result then
    log("Groove MIDI load failed: " .. tostring(err))
    state.seq_gmd_status_msg = tostring(err)
    return false
  end
  return seq_gmd_apply_result(region, result)
end

function run_seq_gmd_preset(region, group, strength)
  if not region or type(group) ~= "table" then return false end
  if not seq_gmd_ensure(false) then return false end
  state.seq_pattern_source = "gmd"
  state.seq_gmd_selected_style = group.name
  local item = seq_gmd_pick_item(group, strength)
  if not item then
    state.seq_gmd_status_msg = "No variations in this preset"
    return false
  end
  return run_seq_gmd_load_id(region, item.id)
end

function seq_gmd_probe_ready()
  if state.seq_gmd_ready ~= nil then
    return state.seq_gmd_ready
  end
  if not seq_gmd_available() then
    state.seq_gmd_ready = false
    state.seq_gmd_status_msg = "SampleMapGrooveMIDI.py not found"
    return false
  end
  -- Probe in the background; seq_gmd_bg_tick sets seq_gmd_ready when done.
  if not seq_gmd_job_running("status") then
    local job = seq_gmd_start_job("status", { action = "status" }, 30)
    if job then
      state.seq_gmd_status_msg = "Checking Groove MIDI…"
    else
      state.seq_gmd_ready = false
      state.seq_gmd_status_msg = "Not downloaded yet"
    end
  end
  return false
end

function seq_pattern_query_matches(query, haystack)
  if not query or query == "" then return true end
  return tostring(haystack or ""):lower():find(query, 1, true) ~= nil
end

-- Match a hard-coded preset to a Groove MIDI parent by exact display name or style key.
function seq_pattern_match_template_for_gmd(group)
  if type(group) ~= "table" then return nil end
  local gname = tostring(group.name or ""):lower()
  local glabel = tostring(group.label or ""):lower()
  for _, style in ipairs(SEQ_GEN_STYLE_ORDER) do
    if style.key then
      local label = tostring(style.label or style.key):lower()
      local key = tostring(style.key):lower()
      if label == glabel or key == gname then
        return style
      end
    end
  end
  return nil
end

function seq_pattern_gmd_child_count(group, template_style)
  local n = type(group) == "table" and type(group.children) == "table" and #group.children or 0
  if template_style then n = n + 1 end
  return n
end

function seq_gmd_group_has_children(group, template_style)
  if template_style then return true end
  local n = type(group) == "table" and type(group.children) == "table" and #group.children or 0
  return n > 1
end

-- One alphabetical list of template presets + Groove MIDI presets.
-- Same-named hard-coded presets are nested as the first child of the GMD parent.
function seq_pattern_browser_entries()
  local raw = tostring(state.seq_pattern_search or "")
  local q = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if state.seq_gmd_ready then
    seq_gmd_refresh_list(false)
  end
  local cache_key = q .. "|" .. tostring(state.seq_gmd_ready) .. "|" .. tostring(state.seq_gmd_list_key or "")
  if state.seq_pattern_browser_cache_key == cache_key and type(state.seq_pattern_browser_cache) == "table" then
    return state.seq_pattern_browser_cache
  end

  local entries = {}
  local used_templates = {}

  if state.seq_gmd_ready then
    for _, group in ipairs(state.seq_gmd_groups or {}) do
      local template = group.template_style
      if not template then
        template = seq_pattern_match_template_for_gmd(group)
        group.template_style = template
      end
      if template then
        used_templates[template.key] = true
      end
      local hay = group.search_hay
      if not hay then
        hay = seq_gmd_group_search_hay(group)
        group.search_hay = hay
      end
      if seq_pattern_query_matches(q, hay) then
        entries[#entries + 1] = {
          kind = "gmd",
          key = group.key,
          label = group.label,
          sort = tostring(group.label or group.name or ""):lower(),
          group = group,
          template = template,
        }
      end
    end
  end

  for _, style in ipairs(SEQ_GEN_STYLE_ORDER) do
    if style.key and not used_templates[style.key] then
      local label = style.label or style.key
      local hay = label .. " " .. style.key
      for _, role in ipairs(seq_template_roles(style.key)) do
        hay = hay .. " " .. (SEQ_ROLE_LABELS[role] or role)
      end
      if seq_pattern_query_matches(q, hay) then
        entries[#entries + 1] = {
          kind = "template",
          key = style.key,
          label = label,
          sort = tostring(label):lower(),
          style_def = style,
        }
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.sort == b.sort then
      if a.kind ~= b.kind then return a.kind == "gmd" end
      return tostring(a.key) < tostring(b.key)
    end
    return a.sort < b.sort
  end)
  state.seq_pattern_browser_cache_key = cache_key
  state.seq_pattern_browser_cache = entries
  return entries
end

function render_seq_gmd_toolbar()
  if not seq_gmd_available() then
    return
  end

  seq_gmd_probe_ready()
  if not state.seq_gmd_ready then
    if seq_gmd_job_running("ensure") or seq_gmd_job_running("status") then
      -- Background download / probe in progress: show its status, no button.
      local dots = string.rep(".", 1 + math.floor(r.time_precise() * 2) % 3)
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, tostring(state.seq_gmd_status_msg or "Working"):gsub("[.…]+$", "") .. dots)
      return
    end
    if draw_ui_button("seq_gmd_download", "Download Groove MIDI (~3 MB)", nil, nil, { style = "success", compact = true }) then
      seq_gmd_ensure(true)
    end
    if state.seq_gmd_status_msg then
      r.ImGui_SameLine(ctx)
      r.ImGui_TextColored(ctx, 0xFFB870FF, tostring(state.seq_gmd_status_msg))
    end
    return
  end

  local beat_label = "Type: " .. tostring(state.seq_gmd_beat_type or "beat")
  if draw_ui_button("seq_gmd_beat", beat_label, nil, nil, { style = "default", compact = true }) then
    seq_gmd_cycle_beat_type()
  end
  if state.seq_gmd_status_msg then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, tostring(state.seq_gmd_status_msg))
  end
end

-- Shared hover-dice strip used by nested child rows.
function seq_pattern_draw_hover_dice(region, id_prefix, x, y, size, gap, on_strength)
  for strength = 1, 6 do
    r.ImGui_SetCursorScreenPos(ctx, x + (strength - 1) * (size + gap), y)
    local dice_clicked = draw_ui_button(
      id_prefix .. "_" .. tostring(strength),
      nil,
      size,
      size,
      { icon = "dice" .. tostring(strength), compact = true, style = "default" }
    )
    if dice_clicked and region and on_strength then
      on_strength(strength)
    end
  end
end

function render_seq_gmd_preset_row(region, group, template_style)
  if type(group) ~= "table" then return end
  local style_key = group.key
  local id_safe = tostring(style_key or group.name or "gmd"):gsub("[^%w]", "_")
  local selected = (state.seq_pattern_source == "gmd" and state.seq_gmd_selected_style == group.name)
    or (template_style and state.seq_pattern_source ~= "gmd" and state.seq_gen_style == template_style.key)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local row_w = math.max(1.0, avail_w)
  local row_h = 34.0
  local left_pad = 10.0
  local right_pad = 8.0
  local item_count = type(group.items) == "table" and #group.items or 0
  local child_count = seq_pattern_gmd_child_count(group, template_style)
  local has_children = seq_gmd_group_has_children(group, template_style)
  state.seq_gmd_expanded = state.seq_gmd_expanded or {}
  local expanded = state.seq_gmd_expanded[group.name] == true
  local after_gap = (expanded and has_children) and 2.0 or 5.0
  if not seq_pattern_list_item_visible(row_h + after_gap) then
    r.ImGui_Dummy(ctx, 0, row_h + after_gap)
    if expanded and has_children then
      if template_style then
        render_seq_pattern_nested_template_row(region, template_style, id_safe)
      end
      for _, child in ipairs(group.children or {}) do
        render_seq_gmd_pattern_row(region, child, id_safe)
      end
      r.ImGui_Dummy(ctx, 0, 4.0)
    end
    return
  end

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hovered = mx >= x0 and mx <= x1 and my >= y0 and my <= y1

  local btn_size = 20.0
  local btn_gap = 3.0
  local list_w = has_children and (btn_size + 6.0) or 0.0
  local list_x = x0 + row_w - right_pad - btn_size

  -- Dice only on leaf parents (single MIDI, no nested hard-coded child).
  local show_parent_dice = hovered and not has_children
  local dice_size = btn_size
  local dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  local right_edge = x0 + row_w - right_pad - list_w
  if show_parent_dice and dice_total_w > (right_edge - x0 - 70.0) then
    dice_size = math.max(13.0, math.floor((right_edge - x0 - 70.0 - btn_gap * 5.0) / 6.0))
    dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  end
  local dice_x = right_edge - dice_total_w

  local interactive_left = right_edge
  if show_parent_dice then
    interactive_left = dice_x
  end
  local row_button_w = math.max(40.0, interactive_left - x0 - 4.0)
  r.ImGui_InvisibleButton(ctx, "##seq_gmd_preset_row_" .. id_safe, row_button_w, row_h)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local fill = selected and UI_THEME.accent_fill or UI_THEME.bg_panel
  local edge = selected and UI_THEME.accent or UI_THEME.border
  if hovered then
    fill = selected and UI_THEME.accent_fill_h or UI_THEME.surface_hvr
    edge = UI_THEME.accent_hvr
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, 5.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, edge, 5.0, 0, selected and 1.5 or 1.0)

  local label_color = selected and 0xFFFFFFFF or UI_THEME.text
  local label_right = show_parent_dice and dice_x or (x0 + row_w - right_pad - list_w)
  local label_max_w = math.max(20.0, label_right - x0 - left_pad - 6.0)
  if not show_parent_dice then
    label_max_w = math.min(label_max_w, row_w * 0.50)
  end
  local label_text = seq_truncate_text_to_width(group.label or group.name, label_max_w)
  r.ImGui_DrawList_AddText(dl, x0 + left_pad, y0 + 9.0, label_color, label_text)

  if not show_parent_dice then
    local meta_text = child_count == 1 and "1 variation" or (tostring(child_count) .. " variations")
    local label_w = select(1, r.ImGui_CalcTextSize(ctx, label_text))
    local meta_right = x0 + row_w - right_pad - list_w
    local meta_max_w = math.max(20.0, meta_right - (x0 + left_pad + label_w) - 12.0)
    meta_text = seq_truncate_text_to_width(meta_text, meta_max_w)
    local meta_w = select(1, r.ImGui_CalcTextSize(ctx, meta_text))
    r.ImGui_DrawList_AddText(dl, meta_right - meta_w, y0 + 9.0, 0x8AA6C8FF, meta_text)
  end

  -- Parent click selects / toggles children — it does not load a variation.
  if clicked then
    state.seq_gmd_selected_style = group.name
    if has_children then
      state.seq_gmd_expanded[group.name] = not expanded
      expanded = state.seq_gmd_expanded[group.name] == true
    elseif region and item_count > 0 then
      state.seq_pattern_source = "gmd"
      run_seq_gmd_load_id(region, group.items[1].id)
    else
      state.seq_pattern_source = "gmd"
    end
  end

  if show_parent_dice then
    seq_pattern_draw_hover_dice(
      region,
      "seq_gmd_dice_" .. id_safe,
      dice_x,
      y0 + (row_h - dice_size) * 0.5,
      dice_size,
      btn_gap,
      function(strength)
        run_seq_gmd_preset(region, group, strength)
      end
    )
  end

  if has_children then
    r.ImGui_SetCursorScreenPos(ctx, list_x, y0 + (row_h - btn_size) * 0.5)
    local list_clicked = draw_ui_button(
      "seq_gmd_expand_" .. id_safe,
      nil,
      btn_size,
      btn_size,
      {
        icon = expanded and "chev_down" or "chev_right",
        compact = true,
        style = expanded and "success" or "default",
      }
    )
    if list_clicked then
      state.seq_gmd_expanded[group.name] = not expanded
      expanded = state.seq_gmd_expanded[group.name] == true
    end
  end

  r.ImGui_SetCursorScreenPos(ctx, x0, y1)
  r.ImGui_Dummy(ctx, 0, expanded and 2.0 or 5.0)

  if expanded and has_children then
    if template_style then
      render_seq_pattern_nested_template_row(region, template_style, id_safe)
    end
    for _, child in ipairs(group.children or {}) do
      render_seq_gmd_pattern_row(region, child, id_safe)
    end
    r.ImGui_Dummy(ctx, 0, 4.0)
  end
end

-- Hard-coded preset nested as the first child under a same-named Groove MIDI parent.
function render_seq_pattern_nested_template_row(region, style_def, parent_id_safe)
  if type(style_def) ~= "table" or not style_def.key then return end
  local row_h = 30.0
  local gap = 2.0
  if not seq_pattern_list_item_visible(row_h + gap) then
    r.ImGui_Dummy(ctx, 0, row_h + gap)
    return
  end
  local style_key = style_def.key
  local id_safe = tostring(parent_id_safe or "gmd") .. "_tmpl_" .. tostring(style_key):gsub("[^%w]", "_")
  local selected = state.seq_pattern_source ~= "gmd" and state.seq_gen_style == style_key
  local can_generate = region and seq_preset_can_generate(style_key)
  local indent = 16.0
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local row_w = math.max(1.0, avail - indent)
  local left_pad = 8.0
  local right_pad = 6.0
  local btn_size = 18.0
  local btn_gap = 2.0

  local has_variations = seq_pattern_variation_count(style_key) > 0
  local list_w = has_variations and (btn_size + 4.0) or 0.0

  local x_base, y_base = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x_base + indent, y_base)

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hovered = mx >= x0 and mx <= x1 and my >= y0 and my <= y1

  local list_x = x0 + row_w - right_pad - btn_size
  local right_edge = x0 + row_w - right_pad - list_w
  local dice_size = btn_size
  local dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  if hovered and dice_total_w > (right_edge - x0 - 60.0) then
    dice_size = math.max(12.0, math.floor((right_edge - x0 - 60.0 - btn_gap * 5.0) / 6.0))
    dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  end
  local dice_x = right_edge - dice_total_w
  local interactive_left = hovered and dice_x or right_edge
  local row_button_w = math.max(40.0, interactive_left - x0 - 4.0)

  r.ImGui_InvisibleButton(ctx, "##seq_nested_tmpl_" .. id_safe, row_button_w, row_h)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local fill = selected and UI_THEME.accent_fill or UI_THEME.bg_panel
  local edge = selected and UI_THEME.accent or UI_THEME.border
  if hovered then
    fill = selected and UI_THEME.accent_fill_h or UI_THEME.surface_hvr
    edge = UI_THEME.accent_hvr
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, 4.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, edge, 4.0, 0, selected and 1.5 or 1.0)

  local label_right = hovered and dice_x or right_edge
  local label_max_w = math.max(20.0, label_right - x0 - left_pad - 6.0)
  local label_text = seq_truncate_text_to_width(style_def.label or style_key, label_max_w)
  r.ImGui_DrawList_AddText(dl, x0 + left_pad, y0 + 7.0, selected and 0xFFFFFFFF or UI_THEME.text, label_text)

  if not hovered then
    local pill_x = x0 + left_pad + select(1, r.ImGui_CalcTextSize(ctx, label_text)) + 8.0
    draw_ui_pill_label(dl, pill_x, (y0 + y1) * 0.5, "Built-in", {
      bg = UI_THEME.accent_fill,
      border = UI_THEME.accent,
      text_col = 0xF0F8FFFF,
      pad_x = 6.0,
      pad_y = 2.0,
      rounding = 5.0,
    })
  end

  if clicked and can_generate then
    run_seq_pattern_preset(region, style_key, nil)
  elseif clicked then
    state.seq_pattern_source = "template"
    state.seq_gen_style = normalize_seq_gen_style(style_key)
    save_config()
  end

  if hovered then
    seq_pattern_draw_hover_dice(
      region,
      "seq_nested_tmpl_dice_" .. id_safe,
      dice_x,
      y0 + (row_h - dice_size) * 0.5,
      dice_size,
      btn_gap,
      function(strength)
        if can_generate then
          run_seq_pattern_preset(region, style_key, strength)
        end
      end
    )
  end

  if has_variations then
    r.ImGui_SetCursorScreenPos(ctx, list_x, y0 + (row_h - btn_size) * 0.5)
    if draw_ui_button(
      "seq_nested_tmpl_varlist_" .. id_safe,
      nil,
      btn_size,
      btn_size,
      { icon = "list", compact = true, style = selected and "primary" or "default" }
    ) then
      state.seq_pattern_variations_open_key = style_key
      state.seq_pattern_variations_request_open = true
    end
  end

  r.ImGui_SetCursorScreenPos(ctx, x_base, y1)
  r.ImGui_Dummy(ctx, 0, 2.0)
end

function render_seq_pattern_preset_row(region, style_def)
  local style_key = style_def.key
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local row_w = math.max(1.0, avail_w)
  local row_h = 34.0
  local after_gap = 5.0
  if not seq_pattern_list_item_visible(row_h + after_gap) then
    r.ImGui_Dummy(ctx, 0, row_h + after_gap)
    return
  end
  local selected = state.seq_pattern_source ~= "gmd" and state.seq_gen_style == style_key
  local can_generate = region and seq_preset_can_generate(style_key)
  local left_pad = 10.0
  local right_pad = 8.0

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hovered = mx >= x0 and mx <= x1 and my >= y0 and my <= y1

  local has_variations = seq_pattern_variation_count(style_key) > 0
  local btn_size = 20.0
  local btn_gap = 3.0

  -- The list button sits at the far right whenever variations exist.
  local list_w = has_variations and (btn_size + 6.0) or 0.0
  local list_x = x0 + row_w - right_pad - btn_size

  -- Dice strip appears on hover, to the left of the list button.
  local dice_size = btn_size
  local dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  local right_edge = x0 + row_w - right_pad - list_w
  if hovered and dice_total_w > (right_edge - x0 - 70.0) then
    dice_size = math.max(13.0, math.floor((right_edge - x0 - 70.0 - btn_gap * 5.0) / 6.0))
    dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  end
  local dice_x = right_edge - dice_total_w

  -- Row click area excludes the dice strip (on hover) and the list button so
  -- those overlapping buttons receive their own clicks.
  local interactive_left = right_edge
  if hovered then
    interactive_left = dice_x
  end
  local row_button_w = math.max(40.0, interactive_left - x0 - 4.0)
  r.ImGui_InvisibleButton(ctx, "##seq_pattern_preset_row_" .. style_key, row_button_w, row_h)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local fill = selected and UI_THEME.accent_fill or UI_THEME.bg_panel
  local edge = selected and UI_THEME.accent or UI_THEME.border
  if hovered then
    fill = selected and UI_THEME.accent_fill_h or UI_THEME.surface_hvr
    edge = UI_THEME.accent_hvr
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, 5.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, edge, 5.0, 0, selected and 1.5 or 1.0)

  local label_color = selected and 0xFFFFFFFF or UI_THEME.text
  local label_right = hovered and dice_x or (x0 + row_w - right_pad - list_w)
  local label_max_w = math.max(20.0, label_right - x0 - left_pad - 6.0)
  if not hovered then
    label_max_w = math.min(label_max_w, row_w * 0.42)
  end
  local label_text = seq_truncate_text_to_width(style_def.label, label_max_w)
  r.ImGui_DrawList_AddText(dl, x0 + left_pad, y0 + 9.0, label_color, label_text)

  if not hovered then
    local palette = {}
    for _, role in ipairs(seq_template_roles(style_key)) do
      palette[#palette + 1] = SEQ_ROLE_LABELS[role] or role
    end
    if #palette > 0 then
      local palette_text = table.concat(palette, " \xC2\xB7 ")
      local label_w = select(1, r.ImGui_CalcTextSize(ctx, label_text))
      local palette_right = x0 + row_w - right_pad - list_w
      local palette_max_w = math.max(20.0, palette_right - (x0 + left_pad + label_w) - 12.0)
      palette_text = seq_truncate_text_to_width(palette_text, palette_max_w)
      local palette_w = select(1, r.ImGui_CalcTextSize(ctx, palette_text))
      r.ImGui_DrawList_AddText(
        dl,
        palette_right - palette_w,
        y0 + 9.0,
        can_generate and 0x8AA6C8FF or 0x6A748AFF,
        palette_text
      )
    end
  end

  if clicked and can_generate then
    run_seq_pattern_preset(region, style_key, nil)
  elseif clicked then
    state.seq_pattern_source = "template"
    state.seq_gen_style = normalize_seq_gen_style(style_key)
    save_config()
  end

  if hovered then
    local dice_y = y0 + (row_h - dice_size) * 0.5
    for strength = 1, 6 do
      r.ImGui_SetCursorScreenPos(ctx, dice_x + (strength - 1) * (dice_size + btn_gap), dice_y)
      local dice_clicked = draw_ui_button(
        "seq_pattern_dice_" .. style_key .. "_" .. tostring(strength),
        nil,
        dice_size,
        dice_size,
        { icon = "dice" .. tostring(strength), compact = true, style = "default" }
      )
      if dice_clicked and can_generate then
        run_seq_pattern_preset(region, style_key, strength)
      end
    end
  end

  if has_variations then
    r.ImGui_SetCursorScreenPos(ctx, list_x, y0 + (row_h - btn_size) * 0.5)
    local list_clicked = draw_ui_button(
      "seq_pattern_varlist_" .. style_key,
      nil,
      btn_size,
      btn_size,
      { icon = "list", compact = true, style = selected and "primary" or "default" }
    )
    if list_clicked then
      state.seq_pattern_variations_open_key = style_key
      state.seq_pattern_variations_request_open = true
    end
  end

  r.ImGui_SetCursorScreenPos(ctx, x0, y1)
  r.ImGui_Dummy(ctx, 0, 5.0)
end

function render_seq_pattern_popup(region)
  if not state.seq_pattern_window_open then
    return
  end
  seq_position_pattern_popup()

  local win_flags = 0
  local function add_flag(getter)
    if getter then win_flags = win_flags | getter() end
  end
  add_flag(r.ImGui_WindowFlags_NoTitleBar)
  add_flag(r.ImGui_WindowFlags_NoCollapse)
  add_flag(r.ImGui_WindowFlags_NoDocking)
  add_flag(r.ImGui_WindowFlags_NoScrollbar)
  add_flag(r.ImGui_WindowFlags_NoScrollWithMouse)

  local visible, keep_open = r.ImGui_Begin(ctx, "Pattern Presets##seq_pattern_window", true, win_flags)
  if keep_open == false then
    state.seq_pattern_window_open = false
  end
  if visible then
    state.seq_gen_style = normalize_seq_gen_style(state.seq_gen_style)
    local can_generate = region and seq_preset_can_generate(state.seq_gen_style)

    local region_name = get_seq_region_display_name(region)
    r.ImGui_TextColored(ctx, UI_THEME.text, "Pattern Presets")
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "· " .. region_name)
    r.ImGui_SameLine(ctx)
    local avail_close = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0.0, avail_close - 22.0))
    if draw_ui_button("seq_pattern_window_close", nil, 18.0, 18.0, { icon = "close", compact = true, style = "default" }) then
      state.seq_pattern_window_open = false
    end
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Applies to " .. region_name .. ". Click to generate. Hover for dice: 1 is subtle, 6 is unruly.")
    if not can_generate and state.seq_pattern_source ~= "gmd" then
      r.ImGui_TextColored(ctx, 0xFFB870FF, "No matching samples found for this preset's types.")
    end

    -- AI variation: a local model re-imagines the current pattern. The dice
    -- (1..6) set how far it strays from what's currently on the grid.
    r.ImGui_TextColored(ctx, 0x9FE3B5FF, "AI Variation")
    r.ImGui_SameLine(ctx)
    local ai_dice = 18.0
    local ai_gap = 3.0
    for strength = 1, 6 do
      if strength > 1 then r.ImGui_SameLine(ctx, 0, ai_gap) end
      local clicked_ai = draw_ui_button(
        "seq_ai_dice_" .. tostring(strength),
        nil, ai_dice, ai_dice,
        { icon = "dice" .. tostring(strength), compact = true, style = "success" }
      )
      if clicked_ai and can_generate then
        run_seq_ai_variation(region, state.seq_gen_style, strength / 6.0)
      end
    end
    if not seq_drum_ai_available() then
      r.ImGui_TextColored(ctx, 0xFFB870FF, "AI model script not found; dice will fall back to built-in randomizer.")
    end

    r.ImGui_Separator(ctx)

    -- Search + Groove MIDI filters share one toolbar above the unified list.
    r.ImGui_SetNextItemWidth(ctx, -1)
    local search_changed, search_val
    if r.ImGui_InputTextWithHint then
      search_changed, search_val = r.ImGui_InputTextWithHint(
        ctx, "##seq_pattern_search", "Search patterns...", state.seq_pattern_search or ""
      )
    else
      search_changed, search_val = r.ImGui_InputText(ctx, "##seq_pattern_search", state.seq_pattern_search or "", 256)
    end
    seq_mark_text_input_item()
    if search_changed then
      state.seq_pattern_search = search_val or ""
    end
    render_seq_gmd_toolbar()

    r.ImGui_Separator(ctx)

    local list_flags = 0
    if r.ImGui_WindowFlags_NoBackground then
      list_flags = r.ImGui_WindowFlags_NoBackground()
    end
    if r.ImGui_BeginChild(ctx, "seq_pattern_preset_list", 0, 0, 0, list_flags) then
      local entries = seq_pattern_browser_entries()
      if #entries == 0 then
        r.ImGui_TextColored(ctx, 0xFFB870FF, "No patterns match your search.")
      else
        for _, entry in ipairs(entries) do
          if entry.kind == "gmd" then
            render_seq_gmd_preset_row(region, entry.group, entry.template)
          elseif entry.style_def then
            render_seq_pattern_preset_row(region, entry.style_def)
          end
        end
      end
      r.ImGui_EndChild(ctx)
    end

    -- Generated-variation history popup only (Groove MIDI uses inline collapse).
    if state.seq_pattern_variations_request_open then
      state.seq_pattern_variations_request_open = false
      local open_key = state.seq_pattern_variations_open_key
      if not (type(open_key) == "string" and open_key:sub(1, 4) == "gmd:") then
        r.ImGui_OpenPopup(ctx, "seq_pattern_variations_popup")
      end
    end
    render_seq_pattern_variations_popup(region)
  end

  end_window(visible, true)
end

function render_seq_pattern_variation_row(region, style_key, entry)
  local row_w = math.max(1.0, r.ImGui_GetContentRegionAvail(ctx))
  local row_h = 30.0
  r.ImGui_InvisibleButton(ctx, "##seq_var_" .. tostring(entry.id), row_w, row_h)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  row_w = x1 - x0
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local cy = (y0 + y1) * 0.5

  if hovered then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, 0x174A24AA, 4.0)
    r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, UI_THEME.accent, 4.0, 0, 1.0)
  end

  local x = x0 + 6.0
  local base_name = get_seq_gen_style_label(style_key)
  local _, name_h = r.ImGui_CalcTextSize(ctx, base_name)
  r.ImGui_DrawList_AddText(dl, x, cy - name_h * 0.5, UI_THEME.text, base_name)
  x = x + select(1, r.ImGui_CalcTextSize(ctx, base_name)) + 8.0

  local num_text = "#" .. tostring(entry.id)
  local pill_w = draw_ui_pill_label(dl, x, cy, num_text, {
    bg = UI_THEME.accent_fill,
    border = UI_THEME.accent,
    text_col = 0xF0F8FFFF,
    pad_x = 7.0,
    pad_y = 2.0,
    rounding = 6.0,
  })
  x = x + pill_w + 6.0

  if entry.ai then
    draw_ui_pill_label(dl, x, cy, "AI", {
      bg = 0x243A2EFF,
      border = 0x66CC88FF,
      text_col = 0xCFF5DDFF,
      pad_x = 7.0,
      pad_y = 2.0,
      rounding = 5.0,
    })
    local pct = math.floor((entry.ai_variation or 0.5) * 100.0 + 0.5)
    x = x + select(1, r.ImGui_CalcTextSize(ctx, "AI")) + 14.0 + 6.0
    draw_ui_pill_label(dl, x, cy, pct .. "%", {
      bg = UI_THEME.surface,
      border = UI_THEME.border,
      text_col = UI_THEME.text_dim,
      pad_x = 6.0,
      pad_y = 2.0,
      rounding = 5.0,
    })
  else
    local dice_text = "dice " .. tostring(entry.strength or 1)
    draw_ui_pill_label(dl, x, cy, dice_text, {
      bg = UI_THEME.surface,
      border = UI_THEME.border,
      text_col = UI_THEME.text_dim,
      pad_x = 6.0,
      pad_y = 2.0,
      rounding = 5.0,
    })
  end

  if clicked then
    seq_apply_pattern_variation(region, style_key, entry)
    r.ImGui_CloseCurrentPopup(ctx)
  end
end

function render_seq_gmd_pattern_row(region, child, parent_id_safe)
  if type(child) ~= "table" or type(child.item) ~= "table" then return end
  local row_h = 30.0
  local gap = 2.0
  if not seq_pattern_list_item_visible(row_h + gap) then
    r.ImGui_Dummy(ctx, 0, row_h + gap)
    return
  end
  local item = child.item
  local indent = 16.0
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local row_w = math.max(1.0, avail - indent)
  local left_pad = 8.0
  local right_pad = 6.0
  local id = tostring(item.id or child.index or "")
  local id_safe = tostring(parent_id_safe or "gmd") .. "_pat_" .. id:gsub("[^%w]", "_")
  local btn_size = 18.0
  local btn_gap = 2.0
  local selected = tostring(state.seq_gmd_selected_id or "") == id

  local x_base, y_base = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x_base + indent, y_base)

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local mx, my = r.ImGui_GetMousePos(ctx)
  local hovered = mx >= x0 and mx <= x1 and my >= y0 and my <= y1

  local right_edge = x0 + row_w - right_pad
  local dice_size = btn_size
  local dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  if hovered and dice_total_w > (right_edge - x0 - 60.0) then
    dice_size = math.max(12.0, math.floor((right_edge - x0 - 60.0 - btn_gap * 5.0) / 6.0))
    dice_total_w = dice_size * 6.0 + btn_gap * 5.0
  end
  local dice_x = right_edge - dice_total_w
  local interactive_left = hovered and dice_x or right_edge
  local row_button_w = math.max(40.0, interactive_left - x0 - 4.0)

  r.ImGui_InvisibleButton(ctx, "##seq_gmd_pat_" .. id_safe, row_button_w, row_h)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local fill = selected and UI_THEME.accent_fill or UI_THEME.bg_panel
  local edge = selected and UI_THEME.accent or UI_THEME.border
  if hovered then
    fill = selected and UI_THEME.accent_fill_h or UI_THEME.surface_hvr
    edge = UI_THEME.accent_hvr
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, 4.0)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, edge, 4.0, 0, 1.0)

  local label_right = hovered and dice_x or right_edge
  local label_max_w = math.max(20.0, label_right - x0 - left_pad - 6.0)
  local label_text = seq_truncate_text_to_width(child.label or "Groove", label_max_w)
  r.ImGui_DrawList_AddText(dl, x0 + left_pad, y0 + 7.0, selected and 0xFFFFFFFF or UI_THEME.text, label_text)

  if not hovered then
    local bpm = tonumber(item.bpm)
    if bpm then
      local bpm_text = tostring(bpm) .. " BPM"
      local label_w = select(1, r.ImGui_CalcTextSize(ctx, label_text))
      local meta_right = label_right
      local meta_max_w = math.max(20.0, meta_right - (x0 + left_pad + label_w) - 10.0)
      bpm_text = seq_truncate_text_to_width(bpm_text, meta_max_w)
      local meta_w = select(1, r.ImGui_CalcTextSize(ctx, bpm_text))
      r.ImGui_DrawList_AddText(dl, meta_right - meta_w, y0 + 8.0, 0x8AA6C8FF, bpm_text)
    end
  end

  if clicked and region then
    run_seq_gmd_load_id(region, id)
  end

  if hovered then
    seq_pattern_draw_hover_dice(
      region,
      "seq_gmd_pat_dice_" .. id_safe,
      dice_x,
      y0 + (row_h - dice_size) * 0.5,
      dice_size,
      btn_gap,
      function(_strength)
        run_seq_gmd_load_id(region, id)
      end
    )
  end

  r.ImGui_SetCursorScreenPos(ctx, x_base, y1)
  r.ImGui_Dummy(ctx, 0, 2.0)
end

-- Popup for code-generated / AI variation history only (not Groove MIDI).
function render_seq_pattern_variations_popup(region)
  local style_key = state.seq_pattern_variations_open_key
  if type(style_key) == "string" and style_key:sub(1, 4) == "gmd:" then
    return
  end
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 280.0, 80.0, 280.0, 520.0)
  end
  if not r.ImGui_BeginPopup(ctx, "seq_pattern_variations_popup") then
    return
  end

  r.ImGui_TextColored(ctx, UI_THEME.text, "Generated Variations")
  local store = style_key and state.seq_pattern_variations and state.seq_pattern_variations[style_key]
  if style_key then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, get_seq_gen_style_label(style_key))
  end
  r.ImGui_Separator(ctx)

  if not store or #store.entries == 0 then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No variations yet. Roll a dice to add some.")
  else
    for i = #store.entries, 1, -1 do
      render_seq_pattern_variation_row(region, style_key, store.entries[i])
    end
    r.ImGui_Separator(ctx)
    if draw_ui_button("seq_var_clear", "Clear list", nil, nil, { compact = true, style = "danger" }) then
      store.entries = {}
      r.ImGui_CloseCurrentPopup(ctx)
    end
  end

  r.ImGui_EndPopup(ctx)
end

function render_seq_groove_popup()
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 280.0, 80.0, 340.0, 620.0)
  end
  if not r.ImGui_BeginPopup(ctx, "seq_groove_popup") then
    return
  end

  local region = get_selected_seq_region()
  local region_name = get_seq_region_display_name(region)
  r.ImGui_TextColored(ctx, UI_THEME.text, "Groove")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "· " .. region_name)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Timing feel for this region only.")
  r.ImGui_Separator(ctx)

  local current = get_seq_region_groove(region)
  for _, entry in ipairs(SEQ_GROOVE_ORDER) do
    if entry.header then
      r.ImGui_Dummy(ctx, 0, 2)
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, entry.header)
    elseif entry.key then
      local selected = (entry.key == current)
      if r.ImGui_Selectable(ctx, entry.label .. "##seq_groove_" .. entry.key, selected) then
        set_seq_region_groove(region, entry.key)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      if entry.desc and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, entry.desc)
      end
    end
  end

  r.ImGui_EndPopup(ctx)
end

function render_seq_kit_random_genre_chips(tags, id_prefix, priority_set)
  local wrap_w = r.ImGui_GetContentRegionAvail(ctx)
  local row_w = 0.0
  local gap = 6.0
  local first = true
  local shown = 0

  for idx, tag in ipairs(tags) do
    local tw = select(1, r.ImGui_CalcTextSize(ctx, tag)) + 16.0
    if not first then
      if row_w + gap + tw > wrap_w then
        row_w = 0.0
      else
        r.ImGui_SameLine(ctx, 0, gap)
        row_w = row_w + gap
      end
    end
    first = false
    shown = shown + 1
    local used_in_project = priority_set and priority_set[tag:lower()] == true
    if draw_tag_button(ctx, tag, false, tag, id_prefix .. tostring(idx) .. "_") then
      randomize_seq_kit({ tag }, { exact_tag = true })
    end
    if used_in_project then
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x0, y0 = r.ImGui_GetItemRectMin(ctx)
      local x1, y1 = r.ImGui_GetItemRectMax(ctx)
      local rounding = (y1 - y0) * 0.5
      r.ImGui_DrawList_AddRect(dl, x0 - 0.5, y0 - 0.5, x1 + 0.5, y1 + 0.5, 0xFFB870AA, rounding + 0.5, 0, 1.35)
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      local tip = "Randomize kit using \"" .. tag .. "\" samples (roles preserved)"
      if used_in_project then
        tip = "Used in this project\n" .. tip
      end
      r.ImGui_SetTooltip(ctx, tip)
    end
    row_w = row_w + tw
  end
  return shown
end

function render_seq_kit_history_element_chip(kit_id, elem_idx, element)
  local role_label = SEQ_ROLE_LABELS[element.role] or tostring(element.role or "?")
  local tag = element.sample_tag or element.role or role_label
  local text_w = select(1, r.ImGui_CalcTextSize(ctx, role_label))
  local pad_x, pad_y = 6.0, 2.0
  local button_w = text_w + pad_x * 2.0
  local button_h = select(2, r.ImGui_CalcTextSize(ctx, role_label)) + pad_y * 2.0

  local active = false
  local slot = find_seq_track_for_kit_element(element)
  if slot and slot.sample_path and element.sample_path and slot.sample_path == element.sample_path then
    active = true
  end

  local tag_color = state.tag_colors[tag] or state.tag_colors[element.role] or 0x336699
  local base_r, base_g, base_b = extract_rgb(tag_color)
  local factor = active and 0.75 or 0.45
  local bg = build_color_rrgbbaa(
    math.floor(base_r * factor),
    math.floor(base_g * factor),
    math.floor(base_b * factor),
    255
  )
  local border = build_color_rrgbbaa(
    math.floor(base_r * factor * (active and 0.7 or 1.2)),
    math.floor(base_g * factor * (active and 0.7 or 1.2)),
    math.floor(base_b * factor * (active and 0.7 or 1.2)),
    255
  )
  local text_col = active and 0xFFFFFFFF or 0xFFCCCCCC

  local id = string.format("##seq_kit_el_%s_%s", tostring(kit_id), tostring(elem_idx))
  r.ImGui_InvisibleButton(ctx, id, button_w, button_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dbl = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)

  local pressed = r.ImGui_IsItemActive(ctx)
  if hovered and not active then
    factor = 0.58
    text_col = 0xF4F4F4FF
  end
  bg = build_color_rrgbbaa(
    math.floor(base_r * factor),
    math.floor(base_g * factor),
    math.floor(base_b * factor),
    active and 255 or 200
  )
  border = build_color_rrgbbaa(
    math.min(255, math.floor(base_r * (active and 0.95 or 0.70))),
    math.min(255, math.floor(base_g * (active and 0.95 or 0.70))),
    math.min(255, math.floor(base_b * (active and 0.95 or 0.70))),
    hovered and 220 or 140
  )

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  ui_draw_panel(dl, x0, y0, x1, y1, button_h * 0.5, bg, border, hovered, pressed)
  local tw, th = r.ImGui_CalcTextSize(ctx, role_label)
  r.ImGui_DrawList_AddText(dl, x0 + (button_w - tw) * 0.5, y0 + (button_h - th) * 0.5 + (pressed and 1.0 or 0.0), text_col, role_label)

  if clicked then
    if dbl then
      apply_seq_kit_history_element(element)
    else
      preview_seq_kit_history_element(element)
    end
  end
  if hovered and r.ImGui_SetTooltip then
    local name = element.sample_name or basename(element.sample_path or "") or "sample"
    r.ImGui_SetTooltip(ctx, name .. "\nClick: preview  ·  Double-click: replace this drum")
  end

  return button_w
end

function render_seq_kit_history_entry(entry)
  if not entry or type(entry.elements) ~= "table" then
    return
  end
  local title = string.format("#%d  %s", entry.id or 0, entry.label or "Kit")
  if entry.is_original then
    title = title .. "  · original"
  end
  local count_label = string.format("(%d)", #entry.elements)
  local current_sig = seq_kit_signature(collect_seq_kit_elements())
  local is_active = current_sig ~= "" and current_sig == seq_kit_signature(entry.elements)
  local title_w = select(1, r.ImGui_CalcTextSize(ctx, title)) + 8.0
  local title_h = select(2, r.ImGui_CalcTextSize(ctx, title)) + 4.0
  r.ImGui_InvisibleButton(ctx, "##seq_kit_title_" .. tostring(entry.id or 0), title_w, title_h)
  local title_hovered = r.ImGui_IsItemHovered(ctx)
  local title_clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local tx0, ty0 = r.ImGui_GetItemRectMin(ctx)
  local title_col = is_active and 0xFFB870FF or (title_hovered and 0xFFFFFFFF or UI_THEME.text)
  r.ImGui_DrawList_AddText(dl, tx0 + 2.0, ty0 + 2.0, title_col, title)
  if title_clicked then
    apply_seq_kit_history_entry(entry)
  end
  if title_hovered and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Click to replace the whole kit with this one")
  end
  r.ImGui_SameLine(ctx, 0, 6.0)
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, count_label)

  local wrap_w = r.ImGui_GetContentRegionAvail(ctx)
  local row_w = 0.0
  local gap = 4.0
  local first = true
  for idx, element in ipairs(entry.elements) do
    local role_label = SEQ_ROLE_LABELS[element.role] or tostring(element.role or "?")
    local tw = select(1, r.ImGui_CalcTextSize(ctx, role_label)) + 12.0
    if not first then
      if row_w + gap + tw > wrap_w then
        row_w = 0.0
      else
        r.ImGui_SameLine(ctx, 0, gap)
        row_w = row_w + gap
      end
    end
    first = false
    local drawn_w = render_seq_kit_history_element_chip(entry.id or idx, idx, element)
    row_w = row_w + (drawn_w or tw)
  end
  r.ImGui_Dummy(ctx, 0, 4)
end

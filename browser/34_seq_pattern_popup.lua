-- Sample Map Browser module: seq_pattern_popup
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- True when a still-to-be-submitted list row intersects the current clip rect.
function seq_pattern_list_item_visible(row_h)
  local w = math.max(1.0, (r.ImGui_GetContentRegionAvail(ctx)))
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
  if state.seq_pattern_window_open and state.seq_fill then
    -- Both windows dock in the same spot beside the main window.
    state.seq_fill.open = false
    state.seq_fill_session = nil
  end
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

function seq_record_pattern_variation(style_key, strength, seed, preview)
  local store = seq_pattern_variation_store(style_key)
  store.counter = store.counter + 1
  local entry = {
    id = store.counter,
    name = get_seq_gen_style_label(style_key) .. " #" .. tostring(store.counter),
    seed = seed,
    strength = strength,
    preview = preview, -- role -> {16th positions} of the result, for the list
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
      local bars = seq_template_cycle_bars(SEQ_GEN_TEMPLATES[style])
      seq_record_pattern_variation(style, strength, seed, seq_collect_preview_positions(region, bars))
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

-- The first `bars` bars of the region as role -> {16th positions}, positions
-- running 0..16*bars-1 (for list previews of generated variations).
function seq_collect_preview_positions(region, bars)
  bars = math.max(1, bars or 1)
  local map = {}
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local notes_by_track = pattern and pattern.notes or nil
  if not notes_by_track then return map end
  local grid_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or 0.25
  local steps_per_bar = math.max(1, math.floor((4.0 / grid_qn) + 0.5))
  local sets = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    local notes = slot.sample_path and notes_by_track[tostring(slot.id)] or nil
    if notes then
      local role = infer_seq_track_role(slot)
      local set = sets[role] or {}
      sets[role] = set
      for step_key, note in pairs(notes) do
        if note and note.enabled ~= false then
          local step_idx = tonumber(note.step) or tonumber(step_key) or 0
          local bar = math.floor(step_idx / steps_per_bar)
          if bar >= 0 and bar < bars then
            local within = step_idx % steps_per_bar
            set[bar * 16 + math.floor((within * 16.0 / steps_per_bar) + 0.5)] = true
          end
        end
      end
    end
  end
  for role, set in pairs(sets) do
    local arr = {}
    for p in pairs(set) do arr[#arr + 1] = p end
    table.sort(arr)
    if #arr > 0 then map[role] = arr end
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
  local pipe = io.popen(sm_shell_cmd(cmd), "r")
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
  -- Skip the model when nothing could be generated; if tracks created below
  -- make it generatable after all, the built-in randomizer covers it.
  if region and seq_has_generatable_track(style) then
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
  local pipe = io.popen(sm_shell_cmd(cmd), "r")
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
    preview = true, -- one bar of hits per groove for the list's step preview
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

-- bar_offset picks the bar to load (the one shown in the list preview);
-- without it the sidecar picks a random bar.
function run_seq_gmd_load_id(region, entry_id, bar_offset)
  if not region or not entry_id then return false end
  if not seq_gmd_ensure(false) then return false end
  local result, err = seq_call_gmd({
    action = "get",
    id = entry_id,
    bars = 1,
    bar_offset = tonumber(bar_offset),
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

-- --- Pattern window: favorites, category filter --------------------------------
SEQ_PATTERN_EXT_SECTION = "SampleMapBrowser"
SEQ_PATTERN_ROW_H = 46.0
SEQ_PATTERN_FAV_COLOR = 0xFFC857FF

-- Lane colors for the step previews, one per drum role.
SEQ_PATTERN_ROLE_COLORS = {
  kick = 0xFF6B5AFF, ["808"] = 0xFF4F7AFF, bass = 0xE8A04AFF,
  snare = 0x5EC8FFFF, clap = 0x8FA8FFFF, rim = 0xB08CFFFF, tom = 0xD97BD0FF,
  hat = 0x6FE39AFF, ride = 0x4FD6C4FF, crash = 0xFFF2B0FF,
  perc = 0xE6E06AFF, fx = 0xA9B4ADFF, vocal = 0xFF8FC8FF,
}

function seq_pattern_favorites()
  if not state.seq_pattern_favs then
    local favs = {}
    local raw = r.GetExtState and r.GetExtState(SEQ_PATTERN_EXT_SECTION, "pattern_favorites") or ""
    for key in tostring(raw or ""):gmatch("[^,]+") do
      favs[key] = true
    end
    state.seq_pattern_favs = favs
    state.seq_pattern_favs_ver = 0
  end
  return state.seq_pattern_favs
end

function seq_pattern_is_favorite(style_key)
  return seq_pattern_favorites()[style_key] == true
end

function seq_pattern_toggle_favorite(style_key)
  local favs = seq_pattern_favorites()
  favs[style_key] = (not favs[style_key]) or nil
  local keys = {}
  for key in pairs(favs) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  if r.SetExtState then
    r.SetExtState(SEQ_PATTERN_EXT_SECTION, "pattern_favorites", table.concat(keys, ","), true)
  end
  state.seq_pattern_favs_ver = (state.seq_pattern_favs_ver or 0) + 1
end

function seq_pattern_current_category()
  if not state.seq_pattern_category then
    local saved = r.GetExtState and r.GetExtState(SEQ_PATTERN_EXT_SECTION, "pattern_category") or ""
    state.seq_pattern_category = (saved ~= nil and saved ~= "") and saved or "all"
  end
  return state.seq_pattern_category
end

function seq_pattern_set_category(key)
  state.seq_pattern_category = key
  if r.SetExtState then
    r.SetExtState(SEQ_PATTERN_EXT_SECTION, "pattern_category", key, true)
  end
end

function seq_pattern_template_hay(style)
  if not style._hay then
    local parts = { style.label or "", style.key or "", seq_pattern_category_label(style.cat), style.desc or "" }
    if style.bpm then
      parts[#parts + 1] = tostring(style.bpm) .. " bpm"
    end
    for _, role in ipairs(seq_template_roles(style.key)) do
      parts[#parts + 1] = SEQ_ROLE_LABELS[role] or role
    end
    style._hay = table.concat(parts, " "):lower()
  end
  return style._hay
end

-- Lanes for the mini step grid, cached per style.
function seq_pattern_preview_data(style_key)
  SEQ_PATTERN_PREVIEW_CACHE = SEQ_PATTERN_PREVIEW_CACHE or {}
  local data = SEQ_PATTERN_PREVIEW_CACHE[style_key]
  if data then
    return data
  end
  local template = SEQ_GEN_TEMPLATES[style_key] or {}
  data = { cols = 16 * seq_template_cycle_bars(template), lanes = {} }
  for _, role in ipairs(seq_template_roles(style_key)) do
    local on = {}
    for _, s in ipairs(template[role]) do
      on[#on + 1] = math.floor(tonumber(s) or 0)
    end
    data.lanes[#data.lanes + 1] = { role = role, steps = on, color = SEQ_PATTERN_ROLE_COLORS[role] or UI_THEME.text_dim }
  end
  SEQ_PATTERN_PREVIEW_CACHE[style_key] = data
  return data
end

-- Same lane data built from a role -> {16th positions} map (Groove MIDI grooves,
-- saved variations). Cached weakly per map table.
SEQ_PATTERN_MAP_PREVIEW = setmetatable({}, { __mode = "k" })
function seq_pattern_preview_from_map(map)
  if type(map) ~= "table" then return nil end
  local data = SEQ_PATTERN_MAP_PREVIEW[map]
  if data then return data end
  local max_step = 0
  data = { lanes = {} }
  for _, role in ipairs(SEQ_ROLE_ORDER) do
    local steps = map[role]
    if type(steps) == "table" and #steps > 0 then
      local on = {}
      for _, s in ipairs(steps) do
        local n = math.floor(tonumber(s) or 0)
        on[#on + 1] = n
        if n > max_step then max_step = n end
      end
      data.lanes[#data.lanes + 1] = { role = role, steps = on, color = SEQ_PATTERN_ROLE_COLORS[role] or UI_THEME.text_dim }
    end
  end
  data.cols = 16 * (math.floor(max_step / 16) + 1)
  SEQ_PATTERN_MAP_PREVIEW[map] = data
  return data
end

local function seq_pattern_scale_alpha(col, f)
  if f >= 1 then return col end
  return (col & 0xFFFFFF00) | math.floor((col & 0xFF) * f + 0.5)
end

-- Mini step grid: one thin lane per role, beats shaded in alternating bands.
-- src: a style key, or lane data from seq_pattern_preview_from_map.
function seq_pattern_draw_step_preview(dl, x0, y0, x1, y1, src, alpha)
  alpha = alpha or 1.0
  local data = type(src) == "table" and src or seq_pattern_preview_data(src)
  local n = data and #data.lanes or 0
  if n == 0 or x1 <= x0 then
    return
  end
  local cols = data.cols
  local cell_w = (x1 - x0) / cols
  local gap_y = 1.0
  local lane_h = math.max(2.0, math.min(6.0, ((y1 - y0) - gap_y * (n - 1)) / n))
  local total_h = lane_h * n + gap_y * (n - 1)
  local top = y0 + ((y1 - y0) - total_h) * 0.5

  r.ImGui_DrawList_AddRectFilled(dl, x0 - 4, top - 3, x1 + 4, top + total_h + 3, 0x0000003A, 4.0)
  for beat = 0, cols / 4 - 1 do
    if beat % 2 == 0 then
      local bx = x0 + beat * 4 * cell_w
      r.ImGui_DrawList_AddRectFilled(dl, bx, top - 1, bx + 4 * cell_w, top + total_h + 1, 0xFFFFFF08, 1.0)
    end
  end
  if cols > 16 then
    local mid = x0 + 16 * cell_w
    r.ImGui_DrawList_AddLine(dl, mid, top - 2, mid, top + total_h + 2, 0xFFFFFF30, 1.0)
  end
  local inset = cell_w > 4 and 0.75 or 0.35
  for i, lane in ipairs(data.lanes) do
    local ly = top + (i - 1) * (lane_h + gap_y)
    r.ImGui_DrawList_AddRectFilled(dl, x0, ly, x1, ly + lane_h, seq_pattern_scale_alpha(0xFFFFFF0C, alpha), 1.0)
    local col = seq_pattern_scale_alpha(lane.color, alpha)
    for _, s in ipairs(lane.steps) do
      if s >= 0 and s < cols then
        local cx = x0 + s * cell_w
        r.ImGui_DrawList_AddRectFilled(dl, cx + inset, ly, cx + cell_w - inset, ly + lane_h, col, 1.0)
      end
    end
  end
end

-- Dice 1..6 drawn into the draw list (no ImGui items, so they can sit on top of
-- a row's own button). Returns the strength under the mouse, if any.
function seq_pattern_draw_dice_strip(dl, x, y, size, gap, mx, my, style)
  local hit = nil
  local down = r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0)
  for s = 1, 6 do
    local bx = x + (s - 1) * (size + gap)
    local over = mx >= bx and mx <= bx + size and my >= y and my <= y + size
    local bg, _, text_col, border = ui_button_colors(style or "default", over, over and down, false)
    ui_draw_panel(dl, bx, y, bx + size, y + size, 4.0, bg, border, over, over and down)
    ui_button_draw_icon(dl, "dice" .. s, bx + size * 0.5, y + size * 0.5, size + 2, over and 0xFFFFFFFF or text_col)
    if over then hit = s end
  end
  return hit
end

local function seq_pattern_point_in(mx, my, x0, y0, x1, y1)
  return mx >= x0 and mx <= x1 and my >= y0 and my <= y1
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

function seq_gmd_group_has_children(group)
  local n = type(group) == "table" and type(group.children) == "table" and #group.children or 0
  return n > 1
end

-- Rows for the list: category captions, built-in presets (filtered by the
-- category chip, favorites and the search), then the Groove MIDI section.
function seq_pattern_browser_entries()
  local raw = tostring(state.seq_pattern_search or "")
  local q = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cat = seq_pattern_current_category()
  local gmd_on = seq_gmd_available()
  if state.seq_gmd_ready then
    seq_gmd_refresh_list(false)
  end
  local cache_key = table.concat({
    q, cat, tostring(state.seq_pattern_favs_ver or 0), tostring(state.seq_gmd_ready),
    tostring(state.seq_gmd_list_key or ""), tostring(gmd_on),
  }, "|")
  if state.seq_pattern_browser_cache_key == cache_key and type(state.seq_pattern_browser_cache) == "table" then
    return state.seq_pattern_browser_cache
  end

  local entries = {}
  if cat ~= "gmd" then
    local favs = seq_pattern_favorites()
    for _, c in ipairs(SEQ_PATTERN_CATEGORIES) do
      if cat == "all" or cat == "fav" or cat == c.key then
        local rows = {}
        for _, style in ipairs(SEQ_GEN_STYLE_ORDER) do
          if style.key and style.cat == c.key
              and (cat ~= "fav" or favs[style.key])
              and seq_pattern_query_matches(q, seq_pattern_template_hay(style)) then
            rows[#rows + 1] = style
          end
        end
        if #rows > 0 then
          entries[#entries + 1] = { kind = "caption", label = c.label, count = #rows }
          for _, style in ipairs(rows) do
            entries[#entries + 1] = { kind = "template", style_def = style }
            entries.first_template = entries.first_template or style
          end
        end
      end
    end
  end

  if gmd_on and (cat == "all" or cat == "gmd") then
    local groups = {}
    if state.seq_gmd_ready then
      for _, group in ipairs(state.seq_gmd_groups or {}) do
        local hay = group.search_hay
        if not hay then
          hay = seq_gmd_group_search_hay(group)
          group.search_hay = hay
        end
        if seq_pattern_query_matches(q, hay) then
          groups[#groups + 1] = group
        end
      end
    end
    if q == "" or #groups > 0 then
      entries[#entries + 1] = { kind = "caption", label = "Groove MIDI", count = state.seq_gmd_ready and #groups or nil }
      entries[#entries + 1] = { kind = "gmd_toolbar" }
      for _, group in ipairs(groups) do
        entries[#entries + 1] = { kind = "gmd", group = group }
      end
    end
  end

  state.seq_pattern_browser_cache_key = cache_key
  state.seq_pattern_browser_cache = entries
  return entries
end

-- Groove MIDI section controls: download button, or the beat / fill filter.
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
      r.ImGui_Dummy(ctx, 1, 4)
      return
    end
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Real drummers' grooves from Google Magenta (CC BY 4.0).")
    if draw_ui_button("seq_gmd_download", "Download Groove MIDI (~3 MB)", nil, 24, { style = "success", compact = true }) then
      seq_gmd_ensure(true)
    end
    if state.seq_gmd_status_msg then
      r.ImGui_TextColored(ctx, 0xFFB870FF, tostring(state.seq_gmd_status_msg))
    end
    r.ImGui_Dummy(ctx, 1, 4)
    return
  end

  local cur = state.seq_gmd_beat_type or "beat"
  local opts = { { "beat", "Beats" }, { "fill", "Fills" }, { "all", "Both" } }
  for i, opt in ipairs(opts) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 4) end
    local w = select(1, r.ImGui_CalcTextSize(ctx, opt[2])) + 18
    if draw_ui_button("seq_gmd_beat_" .. opt[1], opt[2], w, 22, { compact = true, pill = true, selected = cur == opt[1] }) then
      if cur ~= opt[1] then
        state.seq_gmd_beat_type = opt[1]
        state.seq_gmd_list_key = nil
      end
    end
  end
  if state.seq_gmd_status_msg then
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, tostring(state.seq_gmd_status_msg))
  end
  r.ImGui_Dummy(ctx, 1, 4)
end

-- Row panel shared by every list row; selected rows get an accent edge bar.
local function seq_pattern_row_panel(dl, x0, y0, x1, y1, selected, hovered, rounding)
  local fill = selected and UI_THEME.accent_fill or UI_THEME.bg_panel
  local edge = selected and 0x1EFF5E88 or UI_THEME.border_soft
  if hovered then
    fill = selected and UI_THEME.accent_fill_h or UI_THEME.surface_hvr
    edge = selected and UI_THEME.accent_hvr or UI_THEME.border_hvr
  end
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, rounding)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, edge, rounding, 0, 1.0)
  if selected then
    r.ImGui_DrawList_AddRectFilled(dl, x0 + 1, y0 + 7, x0 + 4, y1 - 7, UI_THEME.accent, 1.5)
  end
end

-- Built-in preset: star, name, BPM / bars, and a step preview on the right.
-- Hovering swaps the meta line for dice 1..6 (1 subtle, 6 unruly).
function render_seq_pattern_preset_row(region, style_def)
  local style_key = style_def.key
  local row_w = math.max(1.0, (r.ImGui_GetContentRegionAvail(ctx)))
  local row_h = SEQ_PATTERN_ROW_H
  local after_gap = 4.0
  if not seq_pattern_list_item_visible(row_h + after_gap) then
    r.ImGui_Dummy(ctx, 0, row_h + after_gap)
    return
  end
  local selected = state.seq_pattern_source ~= "gmd" and state.seq_gen_style == style_key
  local can_generate = region and seq_preset_can_generate(style_key)
  local fav = seq_pattern_is_favorite(style_key)
  local var_count = seq_pattern_variation_count(style_key)

  r.ImGui_InvisibleButton(ctx, "##seq_pattern_preset_row_" .. style_key, row_w, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local rclicked = r.ImGui_IsItemClicked(ctx, 1)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local mx, my = r.ImGui_GetMousePos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  seq_pattern_row_panel(dl, x0, y0, x1, y1, selected, hovered, 6.0)

  local pad = 8.0
  local star_s = 18.0
  local star_x, star_y = x0 + pad, y0 + 5.0
  local text_x = star_x + star_s + 6.0
  local grid_w = math.floor(math.min(150.0, row_w * 0.40))
  local grid_x1 = x1 - pad - 2.0
  local grid_x0 = grid_x1 - grid_w

  -- Star (favorite).
  local over_star = hovered and seq_pattern_point_in(mx, my, star_x - 2, star_y - 2, star_x + star_s + 2, star_y + star_s + 2)
  local star_col = fav and SEQ_PATTERN_FAV_COLOR or (over_star and UI_THEME.text or UI_THEME.text_mute)
  ui_button_draw_icon(dl, fav and "star_fill" or "star", star_x + star_s * 0.5, star_y + star_s * 0.5, star_s, star_col)

  -- Name.
  local label_col = selected and 0xFFFFFFFF or (can_generate and UI_THEME.text or UI_THEME.text_dim)
  local label = seq_truncate_text_to_width(style_def.label or style_key, grid_x0 - text_x - 10.0)
  r.ImGui_DrawList_AddText(dl, text_x, y0 + 6.0, label_col, label)

  -- Second line: dice on hover, otherwise BPM / bars / saved variations.
  local line_y = y0 + 25.0
  local dice_s, dice_gap = 15.0, 3.0
  local dice_hit, over_list = nil, false
  local list_x = text_x + 6 * (dice_s + dice_gap) + 4.0
  if hovered then
    dice_hit = seq_pattern_draw_dice_strip(dl, text_x, line_y, dice_s, dice_gap, mx, my, "default")
    if var_count > 0 then
      over_list = seq_pattern_point_in(mx, my, list_x, line_y, list_x + dice_s, line_y + dice_s)
      local bg, _, text_col, border = ui_button_colors(selected and "primary" or "default", over_list, false, false)
      ui_draw_panel(dl, list_x, line_y, list_x + dice_s, line_y + dice_s, 4.0, bg, border, over_list, false)
      ui_button_draw_icon(dl, "list", list_x + dice_s * 0.5, line_y + dice_s * 0.5, dice_s + 2, over_list and 0xFFFFFFFF or text_col)
    end
  else
    local meta = {}
    if style_def.bpm then meta[#meta + 1] = tostring(style_def.bpm) .. " BPM" end
    local bars = seq_template_cycle_bars(SEQ_GEN_TEMPLATES[style_key])
    if bars > 1 then meta[#meta + 1] = tostring(bars) .. " bars" end
    if var_count > 0 then meta[#meta + 1] = tostring(var_count) .. " saved" end
    if #meta > 0 then
      local meta_text = seq_truncate_text_to_width(table.concat(meta, "  \xC2\xB7  "), grid_x0 - text_x - 10.0)
      r.ImGui_DrawList_AddText(dl, text_x, line_y + 1.0, UI_THEME.text_mute, meta_text)
    end
  end

  seq_pattern_draw_step_preview(dl, grid_x0, y0 + 8.0, grid_x1, y1 - 8.0, style_key, can_generate and 1.0 or 0.45)

  if hovered and not dice_hit and not over_list then
    local tip = {}
    if style_def.desc then tip[#tip + 1] = style_def.desc end
    local roles = {}
    for _, role in ipairs(seq_template_roles(style_key)) do
      roles[#roles + 1] = SEQ_ROLE_LABELS[role] or role
    end
    tip[#tip + 1] = "Drums: " .. table.concat(roles, ", ")
    if over_star then
      tip = { fav and "Click to remove from favorites" or "Click to add to favorites" }
    elseif not can_generate then
      tip[#tip + 1] = "No matching samples in the library for these drums."
    else
      tip[#tip + 1] = "Click: apply to " .. get_seq_region_display_name(region) .. " · Right-click: favorite"
    end
    r.ImGui_SetTooltip(ctx, table.concat(tip, "\n"))
  end

  if rclicked or (clicked and over_star) then
    seq_pattern_toggle_favorite(style_key)
  elseif clicked and dice_hit then
    if can_generate then
      run_seq_pattern_preset(region, style_key, dice_hit)
    end
  elseif clicked and over_list then
    state.seq_pattern_variations_open_key = style_key
    state.seq_pattern_variations_request_open = true
  elseif clicked and can_generate then
    run_seq_pattern_preset(region, style_key, nil)
  elseif clicked then
    state.seq_pattern_source = "template"
    state.seq_gen_style = normalize_seq_gen_style(style_key)
    save_config()
  end
end

-- Groove MIDI genre: one row per genre, expanding to its performances.
function render_seq_gmd_preset_row(region, group)
  if type(group) ~= "table" then return end
  local id_safe = tostring(group.key or group.name or "gmd"):gsub("[^%w]", "_")
  local row_w = math.max(1.0, (r.ImGui_GetContentRegionAvail(ctx)))
  local row_h = 34.0
  local item_count = type(group.items) == "table" and #group.items or 0
  local has_children = seq_gmd_group_has_children(group)
  state.seq_gmd_expanded = state.seq_gmd_expanded or {}
  local expanded = state.seq_gmd_expanded[group.name] == true

  if not seq_pattern_list_item_visible(row_h + 4.0) then
    r.ImGui_Dummy(ctx, 0, row_h)
  else
    local selected = state.seq_pattern_source == "gmd" and state.seq_gmd_selected_style == group.name
    r.ImGui_InvisibleButton(ctx, "##seq_gmd_preset_row_" .. id_safe, row_w, row_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x0, y0 = r.ImGui_GetItemRectMin(ctx)
    local x1, y1 = x0 + row_w, y0 + row_h
    local mx, my = r.ImGui_GetMousePos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    seq_pattern_row_panel(dl, x0, y0, x1, y1, selected, hovered, 6.0)

    local cy = (y0 + y1) * 0.5
    ui_button_draw_icon(dl, "midi", x0 + 17.0, cy, 18.0, selected and UI_THEME.accent or UI_THEME.text_dim)
    local chev_x = x1 - 16.0
    if has_children then
      ui_button_draw_icon(dl, expanded and "chev_down" or "chev_right", chev_x, cy, 16.0, hovered and UI_THEME.text or UI_THEME.text_mute)
    end

    local dice_s, dice_gap = 15.0, 3.0
    local dice_w = 6 * dice_s + 5 * dice_gap
    local right = has_children and (chev_x - 14.0) or (x1 - 10.0)
    local dice_hit = nil
    if hovered then
      dice_hit = seq_pattern_draw_dice_strip(dl, right - dice_w, cy - dice_s * 0.5, dice_s, dice_gap, mx, my, "default")
    else
      local meta = item_count == 1 and "1 groove" or (tostring(item_count) .. " grooves")
      local mw, mh = r.ImGui_CalcTextSize(ctx, meta)
      r.ImGui_DrawList_AddText(dl, right - mw, cy - mh * 0.5, UI_THEME.text_mute, meta)
    end
    local label_right = hovered and (right - dice_w - 8.0) or (right - 70.0)
    local label = seq_truncate_text_to_width(group.label or group.name, label_right - (x0 + 32.0))
    local _, lh = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x0 + 32.0, cy - lh * 0.5, selected and 0xFFFFFFFF or UI_THEME.text, label)

    if hovered and not dice_hit then
      r.ImGui_SetTooltip(ctx, "Recorded performances from the Groove MIDI Dataset\n"
        .. (has_children and "Click: show grooves · Dice: random groove (higher = faster band)"
          or "Click: load · Dice: random groove (higher = faster band)"))
    end

    if clicked and dice_hit then
      run_seq_gmd_preset(region, group, dice_hit)
    elseif clicked then
      state.seq_gmd_selected_style = group.name
      if has_children then
        state.seq_gmd_expanded[group.name] = not expanded
        expanded = state.seq_gmd_expanded[group.name] == true
      elseif region and item_count > 0 then
        state.seq_pattern_source = "gmd"
        run_seq_gmd_load_id(region, group.items[1].id, group.items[1].preview_bar)
      end
    end
  end

  if expanded and has_children then
    for _, child in ipairs(group.children or {}) do
      render_seq_gmd_pattern_row(region, child, id_safe)
    end
    r.ImGui_Dummy(ctx, 0, 2.0)
  end
end

-- One recorded groove under an expanded Groove MIDI genre.
function render_seq_gmd_pattern_row(region, child, parent_id_safe)
  if type(child) ~= "table" or type(child.item) ~= "table" then return end
  local item = child.item
  local preview = seq_pattern_preview_from_map(item.preview)
  local row_h = preview and 36.0 or 26.0
  if not seq_pattern_list_item_visible(row_h + 2.0) then
    r.ImGui_Dummy(ctx, 0, row_h)
    return
  end
  local indent = 18.0
  local row_w = math.max(1.0, (r.ImGui_GetContentRegionAvail(ctx)) - indent)
  local id = tostring(item.id or child.index or "")
  local id_safe = tostring(parent_id_safe or "gmd") .. "_pat_" .. id:gsub("[^%w]", "_")
  local selected = tostring(state.seq_gmd_selected_id or "") == id

  local x_base, y_base = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x_base + indent, y_base)
  r.ImGui_InvisibleButton(ctx, "##seq_gmd_pat_" .. id_safe, row_w, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local x0, y0 = x_base + indent, y_base
  local x1, y1 = x0 + row_w, y0 + row_h
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddLine(dl, x_base + 9.0, y0, x_base + 9.0, y1, UI_THEME.border, 1.0)
  seq_pattern_row_panel(dl, x0, y0, x1, y1, selected, hovered, 5.0)

  local cy = (y0 + y1) * 0.5
  local bpm = tonumber(item.bpm)
  local bpm_text = bpm and (tostring(bpm) .. " BPM") or nil
  local label_col = selected and 0xFFFFFFFF or UI_THEME.text
  if preview then
    -- Name over BPM on the left, one bar of the groove on the right.
    local grid_w = math.floor(math.min(130.0, row_w * 0.42))
    local grid_x1 = x1 - 9.0
    local grid_x0 = grid_x1 - grid_w
    local text_w = grid_x0 - (x0 + 10.0) - 10.0
    r.ImGui_DrawList_AddText(dl, x0 + 10.0, y0 + 3.0, label_col, seq_truncate_text_to_width(child.label or "Groove", text_w))
    if bpm_text then
      r.ImGui_DrawList_AddText(dl, x0 + 10.0, y0 + 19.0, UI_THEME.text_mute, seq_truncate_text_to_width(bpm_text, text_w))
    end
    seq_pattern_draw_step_preview(dl, grid_x0, y0 + 6.0, grid_x1, y1 - 6.0, preview, 1.0)
  else
    local right = x1 - 10.0
    if bpm_text then
      local bw, bh = r.ImGui_CalcTextSize(ctx, bpm_text)
      r.ImGui_DrawList_AddText(dl, right - bw, cy - bh * 0.5, UI_THEME.text_mute, bpm_text)
      right = right - bw - 10.0
    end
    local label = seq_truncate_text_to_width(child.label or "Groove", right - (x0 + 10.0))
    local _, lh = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x0 + 10.0, cy - lh * 0.5, label_col, label)
  end

  if hovered and r.ImGui_SetTooltip then
    local tip = {}
    if item.drummer then tip[#tip + 1] = "Drummer " .. tostring(item.drummer) end
    if preview and item.preview_bar then tip[#tip + 1] = "Preview shows bar " .. tostring(math.floor(item.preview_bar) + 1) end
    tip[#tip + 1] = "Click: load " .. (preview and "this bar " or "") .. "into " .. get_seq_region_display_name(region)
    r.ImGui_SetTooltip(ctx, table.concat(tip, "\n"))
  end
  if clicked and region then
    run_seq_gmd_load_id(region, id, item.preview_bar)
  end
  r.ImGui_SetCursorScreenPos(ctx, x_base, y1 + 2.0)
  r.ImGui_Dummy(ctx, 0, 0)
end

-- Title row: icon tile, "Patterns", the target region as a chip, close button.
function seq_pattern_window_header(region_name)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 0
  local h = 26
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + h, y + h, UI_THEME.accent_fill, UI_METRICS.radius_ctrl)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + h - 0.5, y + h - 0.5, 0x1EFF5E44, UI_METRICS.radius_ctrl, 0, 1.0)
  ui_button_draw_icon(dl, "steps", x + h * 0.5, y + h * 0.5, h, UI_THEME.accent)
  local title = "Patterns"
  local tw, th = r.ImGui_CalcTextSize(ctx, title)
  local tx = x + h + 9
  r.ImGui_DrawList_AddText(dl, tx, y + (h - th) * 0.5, UI_THEME.text, title)
  r.ImGui_DrawList_AddText(dl, tx + 0.5, y + (h - th) * 0.5, UI_THEME.text, title)
  local close_s = 20
  local chip_x = tx + tw + 10
  local chip_max = (x + avail - close_s - 8) - chip_x - 14
  if chip_max > 30 then
    draw_ui_pill_label(dl, chip_x, y + h * 0.5, seq_truncate_text_to_width(region_name, chip_max), {
      bg = UI_THEME.surface, border = UI_THEME.border, text_col = UI_THEME.text_dim,
      pad_x = 7.0, pad_y = 2.0, rounding = 9.0,
    })
  end
  r.ImGui_SetCursorScreenPos(ctx, x + avail - close_s, y + (h - close_s) * 0.5)
  if draw_ui_button("seq_pattern_window_close", nil, close_s, close_s, { icon = "close", compact = true, style = "default" }) then
    state.seq_pattern_window_open = false
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Close (Esc)")
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + h)
  r.ImGui_Dummy(ctx, math.max(1, avail), 6)
end

-- Wrapping filter chips: All, Favorites, each category, Groove MIDI.
function seq_pattern_render_category_chips()
  local cur = seq_pattern_current_category()
  local items = {
    { key = "all", label = "All" },
    { key = "fav", label = "Favorites", icon = "star_fill" },
  }
  for _, c in ipairs(SEQ_PATTERN_CATEGORIES) do
    items[#items + 1] = { key = c.key, label = c.short, tip = c.label }
  end
  if seq_gmd_available() then
    items[#items + 1] = { key = "gmd", label = "Groove MIDI", tip = "Recorded performances (Groove MIDI Dataset)" }
  end
  local flow = ui_flow_begin(4.0)
  for _, item in ipairs(items) do
    local w = select(1, r.ImGui_CalcTextSize(ctx, item.label)) + 16 + (item.icon and 16 or 0)
    ui_flow_place(flow, w)
    local is_cur = cur == item.key
    if draw_ui_button("seq_pattern_cat_" .. item.key, item.label, w, 22, {
      compact = true, pill = true, selected = is_cur, lead_icon = item.icon,
      lead_color = item.icon and SEQ_PATTERN_FAV_COLOR or nil,
    }) and not is_cur then
      seq_pattern_set_category(item.key)
    end
    if item.tip and r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, item.tip)
    end
  end
  r.ImGui_Dummy(ctx, 1, 4)
end

-- AI variation card: a local model re-imagines what's on the grid now.
function seq_pattern_render_ai_strip(region, can_generate)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 0
  local h = 32
  ui_draw_panel(dl, x, y, x + avail, y + h, UI_METRICS.radius_ctrl, 0x13241AFF, 0x5EDC8A33, false, false)
  local dice_s, gap = 20, 3
  local dice_x = x + avail - 6 - (6 * dice_s + 5 * gap)

  r.ImGui_InvisibleButton(ctx, "##seq_ai_label", math.max(1, dice_x - x - 4), h)
  if r.ImGui_IsItemHovered(ctx) then
    local tip = "Re-imagines the current pattern with the local model.\nDice 1 stays close to what's on the grid, 6 strays far."
    if not seq_drum_ai_available() then
      tip = tip .. "\nModel script not found, so the dice use the built-in randomizer."
    end
    r.ImGui_SetTooltip(ctx, tip)
  end
  ui_button_draw_icon(dl, "vary", x + 16, y + h * 0.5, 20, UI_THEME.success)
  local label = "AI variation"
  local _, lh = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, x + 30, y + (h - lh) * 0.5, 0xCFF5DDFF, label)

  for s = 1, 6 do
    r.ImGui_SetCursorScreenPos(ctx, dice_x + (s - 1) * (dice_s + gap), y + (h - dice_s) * 0.5)
    if draw_ui_button("seq_ai_dice_" .. s, nil, dice_s, dice_s, { icon = "dice" .. s, compact = true, style = "success" })
        and can_generate then
      run_seq_ai_variation(region, state.seq_gen_style, s / 6.0)
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + h)
  r.ImGui_Dummy(ctx, math.max(1, avail), 6)
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

    seq_pattern_window_header(region_name)
    local submitted, query = ui_popup_search("seq_pattern_search", "Search genres, drums or BPM", state.seq_pattern_search)
    if query ~= state.seq_pattern_search then
      state.seq_pattern_search = query
    end
    r.ImGui_Dummy(ctx, 1, 2)
    seq_pattern_render_category_chips()
    seq_pattern_render_ai_strip(region, can_generate)
    if not region then
      r.ImGui_TextColored(ctx, 0xFFB870FF, "Select a region in the sequencer to apply patterns.")
    end

    local entries = seq_pattern_browser_entries()
    if submitted and region and entries.first_template and seq_preset_can_generate(entries.first_template.key) then
      run_seq_pattern_preset(region, entries.first_template.key, nil)
    end

    local footer_h = 22
    local list_flags = 0
    if r.ImGui_WindowFlags_NoBackground then
      list_flags = r.ImGui_WindowFlags_NoBackground()
    end
    if r.ImGui_BeginChild(ctx, "seq_pattern_preset_list", 0, -footer_h, 0, list_flags) then
      if #entries == 0 then
        r.ImGui_Dummy(ctx, 1, 8)
        local cat = seq_pattern_current_category()
        if cat == "fav" and (state.seq_pattern_search or "") == "" then
          r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No favorites yet.")
          r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Click the star on a pattern (or right-click it) to keep it here.")
        else
          r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No patterns match.")
          if cat ~= "all" and draw_ui_button("seq_pattern_search_all", "Search all categories", nil, 24, { compact = true }) then
            seq_pattern_set_category("all")
          end
        end
      else
        for _, entry in ipairs(entries) do
          if entry.kind == "caption" then
            ui_group_caption(entry.label .. (entry.count and ("  \xC2\xB7  " .. tostring(entry.count)) or ""))
          elseif entry.kind == "template" then
            render_seq_pattern_preset_row(region, entry.style_def)
          elseif entry.kind == "gmd_toolbar" then
            render_seq_gmd_toolbar()
          elseif entry.kind == "gmd" then
            render_seq_gmd_preset_row(region, entry.group)
          end
        end
      end
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Enter: apply top match  \xC2\xB7  Right-click: favorite  \xC2\xB7  Esc: close")

    -- Esc closes the window unless a text field or popup has the keyboard.
    if r.ImGui_IsWindowFocused and r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0)
        and not (r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx))
        and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      state.seq_pattern_window_open = false
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

-- One saved dice / AI roll: icon, number and strength on the left, the
-- resulting pattern as a step preview on the right.
function render_seq_pattern_variation_row(region, style_key, entry)
  local row_w = math.max(1.0, (r.ImGui_GetContentRegionAvail(ctx)))
  local preview = seq_pattern_preview_from_map(entry.ai_pattern or entry.preview)
  local row_h = 36.0
  r.ImGui_InvisibleButton(ctx, "##seq_var_" .. tostring(entry.id), row_w, row_h)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = x0 + row_w, y0 + row_h
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  seq_pattern_row_panel(dl, x0, y0, x1, y1, false, hovered, 5.0)

  local icon = entry.ai and "vary" or ("dice" .. tostring(math.max(1, math.min(6, entry.strength or 1))))
  ui_button_draw_icon(dl, icon, x0 + 16.0, (y0 + y1) * 0.5, 20.0, entry.ai and UI_THEME.success or UI_THEME.text_dim)

  local grid_w = preview and math.floor(math.min(140.0, row_w * 0.48)) or 0
  local grid_x1 = x1 - 9.0
  local grid_x0 = grid_x1 - grid_w
  local text_x = x0 + 32.0
  local text_w = (preview and grid_x0 or x1) - text_x - 10.0
  local title = "#" .. tostring(entry.id)
  r.ImGui_DrawList_AddText(dl, text_x, y0 + 3.0, UI_THEME.text, title)
  r.ImGui_DrawList_AddText(dl, text_x + 0.5, y0 + 3.0, UI_THEME.text, title)
  local meta
  if entry.ai then
    meta = string.format("AI \xC2\xB7 %d%%", math.floor((entry.ai_variation or 0.5) * 100.0 + 0.5))
  else
    meta = "Dice " .. tostring(entry.strength or 1)
  end
  r.ImGui_DrawList_AddText(dl, text_x, y0 + 19.0, UI_THEME.text_mute, seq_truncate_text_to_width(meta, text_w))
  if preview then
    seq_pattern_draw_step_preview(dl, grid_x0, y0 + 6.0, grid_x1, y1 - 6.0, preview, 1.0)
  end

  if hovered then
    r.ImGui_SetTooltip(ctx, "Click: apply this variation again")
  end
  if clicked then
    seq_apply_pattern_variation(region, style_key, entry)
    r.ImGui_CloseCurrentPopup(ctx)
  end
end

function render_seq_pattern_variations_popup(region)
  local style_key = state.seq_pattern_variations_open_key
  if type(style_key) == "string" and style_key:sub(1, 4) == "gmd:" then
    return
  end
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 340.0, 80.0, 340.0, 560.0)
  end
  if not r.ImGui_BeginPopup(ctx, "seq_pattern_variations_popup") then
    return
  end

  ui_popup_header("list", "Generated variations", style_key and get_seq_gen_style_label(style_key) or nil)
  local store = style_key and state.seq_pattern_variations and state.seq_pattern_variations[style_key]

  if not store or #store.entries == 0 then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No variations yet. Roll a dice to add some.")
  else
    for i = #store.entries, 1, -1 do
      render_seq_pattern_variation_row(region, style_key, store.entries[i])
    end
    r.ImGui_Dummy(ctx, 1, 4)
    if draw_ui_button("seq_var_clear", "Clear list", nil, nil, { compact = true, style = "danger" }) then
      store.entries = {}
      r.ImGui_CloseCurrentPopup(ctx)
    end
  end

  ui_popup_close_on_escape()
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

function render_seq_kit_random_genre_chips(tags, id_prefix, priority_set, counts, enabled)
  local flow = ui_flow_begin(6.0)
  local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
  local shown = 0
  for idx, tag in ipairs(tags) do
    ui_flow_place(flow, select(1, r.ImGui_CalcTextSize(ctx, tag)) + pad_x * 2)
    shown = shown + 1
    local used_in_project = priority_set and priority_set[tag:lower()] == true
    if draw_tag_button(ctx, tag, false, tag, id_prefix .. tostring(idx) .. "_") and enabled ~= false then
      randomize_seq_kit({ tag }, { exact_tag = true })
    end
    if used_in_project then
      ui_draw_chip_ring(SEQ_USED_CHIP_RING)
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      local count = counts and tonumber(counts[tag]) or nil
      local tip = "Roll a kit from \"" .. tag .. "\" samples (roles stay the same)"
      if count then
        tip = string.format("%d sample%s\n", count, count == 1 and "" or "s") .. tip
      end
      if used_in_project then
        tip = "Used in this project\n" .. tip
      end
      r.ImGui_SetTooltip(ctx, tip)
    end
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

-- One past kit as a card: title row with a Load button (or "current" when it
-- is the kit on the tracks now), then its drum chips.
function render_seq_kit_history_entry(entry, current_sig)
  if not entry or type(entry.elements) ~= "table" then
    return
  end
  local entry_id = tostring(entry.id or 0)
  if current_sig == nil then
    current_sig = seq_kit_signature(collect_seq_kit_elements())
  end
  local is_active = current_sig ~= "" and current_sig == seq_kit_signature(entry.elements)

  -- The card is painted from last frame's measured height so it sits behind
  -- the chips drawn below.
  state.seq_kit_card_h = state.seq_kit_card_h or {}
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local cx0, cy0 = r.ImGui_GetCursorScreenPos(ctx)
  local card_w = r.ImGui_GetContentRegionAvail(ctx) or 200
  local card_h = state.seq_kit_card_h[entry_id]
  if card_h then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local hovered = r.ImGui_IsWindowHovered(ctx) and mx and my
      and mx >= cx0 and mx <= cx0 + card_w and my >= cy0 and my <= cy0 + card_h
    local border = is_active and 0xFFB870CC or (hovered and UI_THEME.border_hvr or UI_THEME.border)
    ui_draw_panel(dl, cx0, cy0, cx0 + card_w, cy0 + card_h, UI_METRICS.radius_ctrl,
      hovered and UI_THEME.surface_hvr or UI_THEME.surface, border, false, false)
  end

  local inset = 8.0
  r.ImGui_Dummy(ctx, 1, 2)
  r.ImGui_Indent(ctx, inset)

  local title = string.format("#%d  %s", entry.id or 0, entry.label or "Kit")
  if entry.is_original then
    title = title .. "  · original"
  end
  local title_col = is_active and 0xFFB870FF or UI_THEME.text
  local btn_w = 46.0
  local row_x1 = cx0 + card_w - inset
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, title_col, seq_truncate_text_to_width(title, card_w - inset * 2 - btn_w - 8))
  local title_x1 = r.ImGui_GetItemRectMax(ctx)
  if is_active then
    local tag_w = r.ImGui_CalcTextSize(ctx, "current")
    r.ImGui_SameLine(ctx, 0, math.max(6.0, row_x1 - tag_w - title_x1))
    r.ImGui_TextColored(ctx, 0xFFB870FF, "current")
  else
    r.ImGui_SameLine(ctx, 0, math.max(6.0, row_x1 - btn_w - title_x1))
    if draw_ui_button("seq_kit_load_" .. entry_id, "Load", btn_w, nil, { compact = true }) then
      apply_seq_kit_history_entry(entry)
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "Put this whole kit back on the tracks")
    end
  end

  local flow = ui_flow_begin(4.0)
  flow.wrap = card_w - inset * 2
  for idx, element in ipairs(entry.elements) do
    local role_label = SEQ_ROLE_LABELS[element.role] or tostring(element.role or "?")
    ui_flow_place(flow, select(1, r.ImGui_CalcTextSize(ctx, role_label)) + 12.0)
    render_seq_kit_history_element_chip(entry.id or idx, idx, element)
  end

  r.ImGui_Unindent(ctx, inset)
  r.ImGui_Dummy(ctx, 1, 2)
  local _, cy1 = r.ImGui_GetCursorScreenPos(ctx)
  local spacing_y = select(2, r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())) or 0
  state.seq_kit_card_h[entry_id] = math.max(1, cy1 - cy0 - spacing_y)
end

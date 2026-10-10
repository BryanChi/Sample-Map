-- Sample Map Browser module: seq_kit_random
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

SEQ_KIT_POPUP_W = 640.0

function render_seq_kit_history_list()
  state.seq_kit_history = state.seq_kit_history or {}
  ui_group_caption("Recent kits")
  if #state.seq_kit_history == 0 then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Kits you roll show up here,")
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "so you can go back to one.")
    return
  end

  local current_sig = seq_kit_signature(collect_seq_kit_elements())
  for _, entry in ipairs(state.seq_kit_history) do
    render_seq_kit_history_entry(entry, current_sig)
    r.ImGui_Dummy(ctx, 1, 4)
  end
  if draw_ui_button("seq_kit_hist_clear", "Clear history", nil, nil, { compact = true, lead_icon = "close" }) then
    state.seq_kit_history = {}
    save_config()
  end
end

-- Genres to offer: ones already used by this project's regions first, then the
-- rest of the library, filtered by the query. Returns project, library, counts.
function seq_kit_popup_genres(query_lower)
  local library_genres = collect_library_genre_tags()
  local counts, library_set = {}, {}
  for _, entry in ipairs(library_genres) do
    library_set[entry.tag:lower()] = entry.tag
    counts[entry.tag] = entry.count or 0
  end
  local function matches(tag)
    return query_lower == "" or tag:lower():find(query_lower, 1, true) ~= nil
  end

  local project, library, shown = {}, {}, {}
  for _, tag in ipairs(collect_project_kit_genre_priority()) do
    local lib_tag = library_set[tag:lower()]
    if lib_tag and matches(lib_tag) and not shown[lib_tag:lower()] then
      project[#project + 1] = lib_tag
      shown[lib_tag:lower()] = true
    end
  end
  for _, entry in ipairs(library_genres) do
    local tag = entry.tag
    if matches(tag) and not shown[tag:lower()] then
      library[#library + 1] = tag
      shown[tag:lower()] = true
    end
  end
  return project, library, counts
end

function render_seq_kit_random_popup()
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, SEQ_KIT_POPUP_W, 0, SEQ_KIT_POPUP_W, 2000)
  end
  if not r.ImGui_BeginPopup(ctx, "seq_kit_random_popup") then
    return
  end

  sm_tag_index_rebuild_if_stale()

  local track_count = #(state.seq_tracks or {})
  local meta = (track_count > 0)
    and string.format("%d track%s  ·  roles stay the same", track_count, track_count == 1 and "" or "s")
    or "No tracks yet"
  ui_popup_header("dice5", "Randomize kit", meta)

  local submitted, query = ui_popup_search("seq_kit_random_query", "Filter genres or type any keyword", state.seq_kit_random_query)
  state.seq_kit_random_query = query
  local trimmed = seq_trim_text(query)

  if track_count > 0 then
    local randomize_label = (trimmed ~= "") and ('Randomize with "' .. trimmed .. '"') or "Randomize (any genre)"
    local run = draw_ui_button("seq_kit_random_run", randomize_label, nil, 28,
      { full_width = true, style = "primary", lead_icon = "dice5" })
    if run or submitted then
      randomize_seq_kit((trimmed ~= "") and { trimmed } or nil, { exact_tag = false })
    end
  else
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Add tracks to the sequencer first, then roll a kit for them.")
  end
  r.ImGui_Dummy(ctx, 1, 4)

  local project, library, counts = seq_kit_popup_genres(trimmed:lower())
  local project_set = {}
  for _, tag in ipairs(project) do
    project_set[tag:lower()] = true
  end

  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or SEQ_KIT_POPUP_W
  local gap = 14.0
  local right_w = 236.0
  local left_w = math.max(180.0, avail_w - right_w - gap)
  local keys = { "seq_kit_random_tags", "seq_kit_history_list" }
  local col_h = ui_fit_child_height(keys, 140, 360)

  local opened = ui_fit_child_begin(keys[1], left_w, col_h)
  if opened then
    if #project > 0 then
      ui_group_caption("In this project")
      render_seq_kit_random_genre_chips(project, "seq_kit_proj_", project_set, counts, track_count > 0)
      r.ImGui_Dummy(ctx, 1, 4)
    end
    ui_group_caption((#project > 0) and "Library" or "Genres")
    if #library > 0 then
      render_seq_kit_random_genre_chips(library, "seq_kit_lib_", project_set, counts, track_count > 0)
    elseif #project == 0 then
      local msg = (#collect_library_genre_tags() == 0) and "No genre tags in the library yet" or "No genres match"
      r.ImGui_TextColored(ctx, UI_THEME.text_mute, msg)
    end
  end
  ui_fit_child_end(keys[1], opened)

  r.ImGui_SameLine(ctx, 0, gap)
  local hist_opened = ui_fit_child_begin(keys[2], right_w, col_h)
  if hist_opened then
    render_seq_kit_history_list()
  end
  ui_fit_child_end(keys[2], hist_opened)

  ui_popup_footer("Click a genre to roll with it   ·   Enter: roll   ·   Esc: close")
  ui_popup_close_on_escape()
  r.ImGui_EndPopup(ctx)
end

function seq_anim_clamp01(v)
  if v <= 0.0 then return 0.0 end
  if v >= 1.0 then return 1.0 end
  return v
end

function seq_note_anim_cell_key(region_id, track_id, step_key)
  return tostring(region_id or 0) .. ":" .. tostring(track_id or 0) .. ":" .. tostring(step_key or 0)
end

function seq_snapshot_note_for_anim(note)
  if type(note) ~= "table" then
    return nil
  end
  return {
    enabled = note.enabled ~= false,
    step = note.step,
    qn_offset = note.qn_offset or 0.0,
    sample_path = note.sample_path,
    sample_name = note.sample_name,
    volume = note.volume,
    pan = note.pan,
    pitch = note.pitch,
    length_qn = note.length_qn,
    decay_qn = note.decay_qn,
    fade_in_qn = note.fade_in_qn,
    fade_out_qn = note.fade_out_qn,
    fade_in_shape = note.fade_in_shape,
    fade_out_shape = note.fade_out_shape,
    fade_in_curve = note.fade_in_curve,
    fade_out_curve = note.fade_out_curve,
    offset_qn = note.offset_qn,
    stretch = note.stretch,
    start = note.start,
    sample_vary = note.sample_vary,
    vary_filter = note.vary_filter,
    frozen_sample_path = note.frozen_sample_path,
    frozen_sample_name = note.frozen_sample_name,
    vary_origin_path = note.vary_origin_path,
    vary_rgb = note.vary_rgb,
    picked_sample = note.picked_sample,
    stutter = note.stutter,
    stutter_skew = note.stutter_skew,
    stutter_hits = clone_table_deep(note.stutter_hits),
    locked = note.locked,
    locked_skip = note.locked_skip,
    locked_vel = note.locked_vel,
    locked_humanize_sec = note.locked_humanize_sec,
    locked_humanize_pitch = note.locked_humanize_pitch,
    locked_humanize_stretch = note.locked_humanize_stretch,
    locked_humanize_len = note.locked_humanize_len,
    locked_humanize_fade = note.locked_humanize_fade,
    locked_ghosts = clone_table_deep(note.locked_ghosts),
  }
end

function register_seq_note_anim(region_id, track_id, step_key, note, kind)
  if not region_id or not track_id or step_key == nil
     or (kind ~= "add" and kind ~= "delete" and kind ~= "sync") then
    return
  end
  state.seq_note_anims = state.seq_note_anims or {}
  local duration = 0.20
  if kind == "sync" then
    duration = 0.45
  elseif kind == "delete" then
    duration = 0.18
  end
  state.seq_note_anims[seq_note_anim_cell_key(region_id, track_id, step_key)] = {
    kind = kind,
    region_id = region_id,
    track_id = track_id,
    step_key = tostring(step_key),
    note = seq_snapshot_note_for_anim(note),
    start_time = r.time_precise(),
    duration = duration,
  }
end

function prune_seq_note_anims(now)
  local anims = state.seq_note_anims
  if not anims then
    return
  end
  for key, anim in pairs(anims) do
    local start_t = anim.start_time or 0.0
    local dur = anim.duration or 0.2
    if (now - start_t) >= dur then
      anims[key] = nil
    end
  end
end

function seq_note_anim_progress(anim, now)
  if not anim then
    return 1.0
  end
  local dur = anim.duration or 0.2
  if dur <= 0 then
    return 1.0
  end
  return seq_anim_clamp01((now - (anim.start_time or now)) / dur)
end

function get_seq_note_anim(region_id, track_id, step_key, now)
  local anims = state.seq_note_anims
  if not anims then
    return nil
  end
  local key = seq_note_anim_cell_key(region_id, track_id, step_key)
  local anim = anims[key]
  if not anim then
    return nil
  end
  local t = seq_note_anim_progress(anim, now)
  if t >= 1.0 then
    anims[key] = nil
    return nil
  end
  anim.t = t
  return anim
end

function scale_rect_about_center(x0, y0, x1, y1, scale_x, scale_y, offset_y)
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5 + (offset_y or 0.0)
  local hw = math.max(0.25, (x1 - x0) * 0.5 * (scale_x or 1.0))
  local hh = math.max(0.25, (y1 - y0) * 0.5 * (scale_y or 1.0))
  return cx - hw, cy - hh, cx + hw, cy + hh
end

-- Insert grows in with a mid-pop.
function seq_note_anim_pop_scale(kind, t)
  t = seq_anim_clamp01(t or 0.0)
  local pulse = math.sin(t * math.pi)
  return 0.78 + t * 0.22 + pulse * 0.12, 0.66 + t * 0.34 + pulse * 0.18
end

function seq_note_anim_pop_alphas(kind, t, cell_selected)
  t = seq_anim_clamp01(t or 0.0)
  local note_alpha = math.floor((cell_selected and (120 + t * 115) or (34 + t * 36)))
  local border_alpha = math.floor((cell_selected and (90 + t * 150) or (24 + t * 28)))
  return note_alpha, border_alpha
end

function seq_ease_out_cubic(t)
  t = 1.0 - seq_anim_clamp01(t)
  return 1.0 - t * t * t
end

function seq_ease_in_cubic(t)
  t = seq_anim_clamp01(t)
  return t * t * t
end

function seq_ease_out_quart(t)
  t = 1.0 - seq_anim_clamp01(t)
  return 1.0 - t * t * t * t
end

function seq_anim_lerp(a, b, t)
  return a + (b - a) * t
end

function seq_anim_mix_rgb(r0, g0, b0, r1, g1, b1, t)
  return seq_anim_lerp(r0, r1, t), seq_anim_lerp(g0, g1, t), seq_anim_lerp(b0, b1, t)
end

-- Flash, crush into a streak, then a colored burst. Seeded so sparks stay stable.
function draw_seq_note_delete_fx(dl, x0, y0, x1, y1, t, br, bg, bb, seed)
  t = seq_anim_clamp01(t or 0.0)
  local w = math.max(4.0, x1 - x0)
  local h = math.max(4.0, y1 - y0)
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5
  seed = seed or 0

  local flash = 1.0 - seq_anim_clamp01(t / 0.20)
  local crush = seq_ease_in_cubic(seq_anim_clamp01((t - 0.05) / 0.58))
  local burst = seq_ease_out_cubic(seq_anim_clamp01((t - 0.08) / 0.92))
  local body_a = math.floor(235 * (1.0 - seq_ease_in_cubic(seq_anim_clamp01(t / 0.68))))

  local scale_x, scale_y
  if t < 0.14 then
    local punch = seq_ease_out_cubic(t / 0.14)
    scale_x = seq_anim_lerp(1.0, 1.08, punch)
    scale_y = seq_anim_lerp(1.0, 1.14, punch)
  else
    scale_x = seq_anim_lerp(1.08, 0.42, crush)
    scale_y = seq_anim_lerp(1.14, 0.06, crush)
  end
  local bx0, by0, bx1, by1 = scale_rect_about_center(x0, y0, x1, y1, scale_x, scale_y, 0.0)
  local fr, fg, fb = seq_anim_mix_rgb(br, bg, bb, 255, 255, 255, flash * 0.82)

  if body_a > 4 then
    r.ImGui_DrawList_AddRectFilled(dl, bx0, by0, bx1, by1, build_color_rrgbbaa(fr, fg, fb, body_a), 2.5)
    r.ImGui_DrawList_AddRect(dl, bx0, by0, bx1, by1, build_color_rrgbbaa(255, 255, 255, math.floor(body_a * 0.78)), 2.5, 0, 1.3)
  end

  local streak_in = seq_anim_clamp01(t / 0.08)
  local streak_out = 1.0 - seq_anim_clamp01((t - 0.10) / 0.52)
  local streak_a = math.floor(230 * streak_in * streak_out)
  if streak_a > 0 then
    local sw = w * seq_anim_lerp(0.42, 1.55, burst)
    local sh = seq_anim_lerp(2.6, 0.55, burst)
    r.ImGui_DrawList_AddRectFilled(
      dl, cx - sw * 0.5, cy - sh, cx + sw * 0.5, cy + sh,
      build_color_rrgbbaa(255, 255, 255, streak_a), 1.2
    )
    r.ImGui_DrawList_AddRectFilled(
      dl, cx - sw * 0.28, cy - sh * 0.45, cx + sw * 0.28, cy + sh * 0.45,
      build_color_rrgbbaa(br, bg, bb, math.floor(streak_a * 0.55)), 1.0
    )
  end

  local ring_t = seq_ease_out_cubic(seq_anim_clamp01((t - 0.03) / 0.80))
  local ring_a = math.floor(170 * ((1.0 - ring_t) ^ 0.65) * seq_anim_clamp01(t / 0.07))
  if ring_a > 0 then
    local pad = 1.5 + ring_t * math.max(7.0, math.min(14.0, w * 0.22))
    r.ImGui_DrawList_AddRect(
      dl, x0 - pad, y0 - pad * 0.65, x1 + pad, y1 + pad * 0.65,
      build_color_rrgbbaa(255, 255, 255, ring_a), 3.5, 0, 1.5
    )
    r.ImGui_DrawList_AddRect(
      dl, x0 - pad * 0.45, y0 - pad * 0.30, x1 + pad * 0.45, y1 + pad * 0.30,
      build_color_rrgbbaa(br, bg, bb, math.floor(ring_a * 0.6)), 3.0, 0, 1.1
    )
  end

  local spark_t = seq_ease_out_quart(seq_anim_clamp01((t - 0.07) / 0.93))
  local spark_a = math.floor(235 * (1.0 - seq_anim_clamp01((t - 0.18) / 0.72)))
  if spark_a > 8 and spark_t > 0 then
    local reach = 7.0 + h * 0.55 + w * 0.16
    for i = 1, 6 do
      local jitter = ((seed + i * 19) % 23) * 0.045
      local ang = (i - 1) * (math.pi * 2.0 / 6.0) + jitter
      local dist = reach * spark_t * (0.72 + ((seed + i * 7) % 10) * 0.03)
      local sx = cx + math.cos(ang) * dist
      local sy = cy + math.sin(ang) * dist * 0.70
      local rad = seq_anim_lerp(2.6, 0.35, spark_t)
      local hot = (i % 2 == 0) and 0.70 or 0.38
      local sr, sg, sb = seq_anim_mix_rgb(br, bg, bb, 255, 255, 255, hot)
      r.ImGui_DrawList_AddCircleFilled(dl, sx, sy, rad, build_color_rrgbbaa(sr, sg, sb, spark_a), 8)
    end
  end
end

-- Deleted notes leave active_cells immediately and use QN storage keys, so
-- ghosts are drawn from the anim snapshot rather than the live grid.
function seq_draw_lane_delete_anims(dl, slot, row_y0, row_y1, now_t, step_qn, qn_to_x, timeline_x0, timeline_x1, selected_region_id)
  local anims = state.seq_note_anims
  if not anims or not slot or not qn_to_x then
    return
  end
  local slot_key = tostring(slot.id)
  for _, anim in pairs(anims) do
    if anim.kind == "delete" and anim.note and tostring(anim.track_id) == slot_key then
      local t = seq_note_anim_progress(anim, now_t)
      if t < 1.0 then
        local region = get_seq_region_by_id(anim.region_id)
        if region then
          local note = anim.note
          local step_key = anim.step_key
          local resolved_path, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot.id, step_key)
          local origin_path = seq_note_vary_origin_path(note, slot, region)
          local origin_sample = find_sample_by_path(origin_path)
          local base = get_sample_dot_color(origin_sample or resolved_sample or find_sample_by_path(resolved_path or origin_path or note.sample_path or slot.sample_path))
          local pattern = get_seq_pattern(region.pattern_id, false)
          local note_qn = seq_note_abs_qn(region, note, step_key, step_qn)
          local note_len = seq_note_draw_length_qn(
            region, pattern, slot, slot.id, step_key, note, resolved_sample, step_qn
          )
          local note_off = note.offset_qn or 0.0
          local draw_x0 = qn_to_x(note_qn + note_off) + 2
          local draw_x1 = math.max(draw_x0 + 6.0, qn_to_x(note_qn + note_off + note_len) - 2)
          -- Size the FX to the solid head only, not the faint sustain tail.
          if not seq_note_has_stutter_span(note, step_qn) then
            local head_x1 = seq_note_head_end_x(qn_to_x, note_qn, note, step_qn)
            if head_x1 and draw_x1 > head_x1 + 1.0 then
              draw_x1 = math.max(draw_x0 + 6.0, head_x1)
            end
          end
          if draw_x1 >= (timeline_x0 or draw_x0) - 12.0 and draw_x0 <= (timeline_x1 or draw_x1) + 12.0 then
            local row_pad = 4.0
            local br, bg, bb = extract_rgb_rrgbbaa(base)
            if resolved_path and origin_path and resolved_path ~= origin_path then
              local vr, vg, vb = seq_note_vary_rgb(note, resolved_path)
              if vr then
                br, bg, bb = math.floor((br + vr) * 0.5), math.floor((bg + vg) * 0.5), math.floor((bb + vb) * 0.5)
              end
            end
            local seed = (tonumber(step_key) or 0) + (tonumber(anim.region_id) or 0) * 31 + (tonumber(anim.track_id) or 0) * 17
            draw_seq_note_delete_fx(dl, draw_x0, row_y0 + row_pad, draw_x1, row_y1 - row_pad, t, br, bg, bb, seed)
          end
        end
      end
    end
  end
end

function draw_seq_note_sync_flash(dl, x0, y0, x1, y1, t)
  t = seq_anim_clamp01(t or 0.0)
  local fade = 1.0 - t
  local fill_a = math.floor(150 * (fade ^ 1.25))
  local edge_a = math.floor(230 * (fade ^ 0.8))
  if fill_a > 0 then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, build_color_rrgbbaa(255, 255, 255, fill_a), 0)
  end
  if edge_a > 0 then
    r.ImGui_DrawList_AddRect(dl, x0 - 1.0, y0 - 1.0, x1 + 1.0, y1 + 1.0, build_color_rrgbbaa(255, 255, 255, edge_a), 0, 0, 1.8)
  end
end

function toggle_seq_note(region, slot, step_key, qn_offset, force_mode, opts)
  if not region or not slot then
    return false
  end
  opts = opts or {}
  local length = get_seq_region_length_qn(region)
  if type(qn_offset) == "number" then
    if qn_offset < -1e-9 or qn_offset >= length - 1e-9 then
      return false
    end
  elseif not seq_step_in_region(region, step_key) then
    return false
  end

  local existing_key = nil
  local existing = nil
  if type(qn_offset) == "number" then
    existing_key, existing = seq_find_note_key_at_qn(region, slot.id, qn_offset)
  end
  if not existing then
    existing = get_seq_note(region, slot.id, step_key)
    if existing and type(qn_offset) == "number"
       and math.abs(seq_note_qn_offset(existing, step_key) - qn_offset) > 1e-4 then
      existing = nil
    else
      existing_key = existing and tostring(step_key) or nil
    end
  end
  if not existing_key then
    existing_key = (type(qn_offset) == "number") and seq_alloc_note_key(region, slot.id, qn_offset) or tostring(step_key)
  end
  step_key = tostring(existing_key)

  if existing and force_mode ~= "paint" then
    local was_locked = seq_note_is_locked(existing)
    register_seq_note_anim(region.id, slot.id, step_key, existing, "delete")
    delete_seq_note(region, slot.id, step_key)
    if was_locked then
      local grid_qn = state.seq_grid_qn or 0.25
      local empty_key = seq_region_step_key(region, seq_note_abs_qn(region, existing, step_key, grid_qn), grid_qn)
      seq_set_cell_locked(get_seq_pattern(region.pattern_id, true), slot.id, empty_key, true)
    end
    if state.selected_seq_note and state.selected_seq_note.region_id == region.id and
       state.selected_seq_note.track_id == slot.id and tostring(state.selected_seq_note.step_key) == step_key then
      state.selected_seq_note = nil
    end
  elseif not existing and force_mode ~= "erase" then
    local note = make_default_seq_note(slot, step_key, qn_offset)
    if not note then
      log("Sequencer slot has no assigned sample")
      return false
    end
    local pattern = get_seq_pattern(region.pattern_id, true)
    seq_set_cell_locked(pattern, slot.id, step_key, false)
    if type(qn_offset) == "number" then
      seq_set_cell_locked(pattern, slot.id, seq_region_step_key(region, (region.start_qn or 0.0) + qn_offset, state.seq_grid_qn or 0.25), false)
    end
    set_seq_note(region, slot.id, step_key, note)
    register_seq_note_anim(region.id, slot.id, step_key, note, "add")
    state.selected_seq_note = { region_id = region.id, track_id = slot.id, step_key = step_key }
  else
    return false
  end

  if not opts.defer_sync then
    sync_seq_pattern_note(region.pattern_id, slot, step_key, { skip_neighbor = opts.skip_neighbor })
    if not opts.defer_arrange then
      r.UpdateArrange()
    end
  end
  if not opts.defer_save then
    save_config()
  end
  return true
end

function get_selected_seq_note()
  if not state.selected_seq_note then
    return nil, nil
  end
  local region = get_seq_region_by_id(state.selected_seq_note.region_id)
  if not region then
    return nil, nil
  end
  return get_seq_note(region, state.selected_seq_note.track_id, state.selected_seq_note.step_key), region
end

SEQ_PARAM_LANES = {
  { key = "volume", label = "Gain", mode_name = "Gain", hotkey = "G", shortcut_id = "edit_gain", min = 0.0, max = 2.0, default = 1.0, fmt = "%.2f" },
  { key = "sample_vary", label = "Vary", mode_name = "Variation", hotkey = "V", shortcut_id = "edit_vary", min = 0.0, max = 1.0, default = 0.0, fmt = "%.2f" },
  { key = "vary_filter", label = "Filter", mode_name = "Vary filter", hotkey = "F", shortcut_id = "edit_vary_filter", min = 0.0, max = 1.0, default = 0.0, fmt = "%.0f", boolean = true },
  { key = "stutter", label = "Stut", mode_name = "Stutter", hotkey = "S", shortcut_id = "edit_stutter", min = 1.0, max = SEQ_STUTTER_MAX, default = 1.0, fmt = "%.0f" },
  { key = "pan", label = "Pan", mode_name = "Pan", hotkey = "P", shortcut_id = "edit_pan", min = -1.0, max = 1.0, default = 0.0, fmt = "%.2f" },
  { key = "pitch", label = "Pitch", mode_name = "Pitch", hotkey = "T", shortcut_id = "edit_pitch", min = -24.0, max = 24.0, default = 0.0, fmt = "%.1f" },
  { key = "decay", label = "Dec", mode_name = "Decay", hotkey = "D", shortcut_id = "edit_decay", min = 0.0, max = 8.0, default = 0.0, fmt = "%.3f" },
  { key = "length_qn", label = "Len", min = 0.03125, max = 8.0, default = 0.25, fmt = "%.3f" },
  { key = "stretch", label = "Stretch", mode_name = "Stretch", hotkey = "R", shortcut_id = "edit_stretch", min = 0.25, max = 4.0, default = 1.0, fmt = "%.2fx" },
  { key = "start", label = "Start", mode_name = "Start", hotkey = "A", shortcut_id = "edit_start", min = 0.0, max = 0.99, default = 0.0, fmt = "%.0f%%" },
  { key = "locked", label = "Lock", mode_name = "Lock", hotkey = "L", shortcut_id = "edit_lock", min = 0.0, max = 1.0, default = 0.0, fmt = "%.0f", boolean = true },
}

function get_seq_row_lane_style(row)
  if row.type == "note" then
    return {
      bg = UI_THEME.bg_panel,
      label_bg = UI_THEME.bg,
      timeline_bg = UI_THEME.surface,
      edge = UI_THEME.border,
      accent = UI_THEME.accent,
    }
  end
  if row.type == "param" and row.param then
    local styles = {
      volume = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0xFFD166FF },
      sample_vary = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0x8FD98FFF },
      vary_filter = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0x7ECFA6FF },
      stutter = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0xC9A8FFFF },
      pan = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0x6EC8FFFF },
      pitch = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0xFFB84DFF },
      length_qn = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0x88DDAAFF },
      decay = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0xFFD166FF },
      stretch = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0x7ED0C8FF },
      start = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0xA8E0C0FF },
      locked = { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = 0xE8C070FF },
    }
    return styles[row.param.key] or { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = UI_THEME.text_dim }
  end
  return { bg = UI_THEME.bg_panel, label_bg = UI_THEME.bg, timeline_bg = UI_THEME.surface, edge = UI_THEME.border, accent = UI_THEME.text_mute }
end

function seq_lane_color_with_alpha(color, alpha)
  local cr, cg, cb = extract_rgb_rrgbbaa(color or 0xFFFFFFFF)
  return build_color_rrgbbaa(cr, cg, cb, alpha or 255)
end

function seq_lane_param_fill_colors(accent, bipolar, value)
  local ar, ag, ab = extract_rgb_rrgbbaa(accent or 0xFFD166FF)
  local fill = build_color_rrgbbaa(ar, ag, ab, 205)
  local cap = build_color_rrgbbaa(math.min(255, ar + 45), math.min(255, ag + 45), math.min(255, ab + 45), 255)
  local fill_neg = build_color_rrgbbaa(math.max(0, ar - 70), math.max(0, ag - 35), math.min(255, ab + 40), 205)
  if bipolar and value ~= nil and value < 0 then
    return fill_neg, cap
  end
  return fill, cap
end

function get_param_lane_def(param_key)
  for _, def in ipairs(SEQ_PARAM_LANES) do
    if def.key == param_key then
      return def
    end
  end
  return nil
end

function seq_note_edit_mode_defs()
  local defs = {}
  for _, def in ipairs(SEQ_PARAM_LANES) do
    if def.hotkey then
      defs[#defs + 1] = def
    end
  end
  return defs
end

function get_seq_note_edit_mode_def()
  return get_param_lane_def(state.seq_note_edit_mode)
end

function seq_set_note_edit_mode(param_key)
  if state.seq_note_edit_mode == "vary_filter" and param_key ~= "vary_filter" then
    if state.seq_vary_filter_edit and seq_trim_text(state.seq_vary_filter_edit.text) ~= "" then
      seq_commit_vary_filter_edit()
    else
      seq_cancel_vary_filter_edit()
    end
  end
  if param_key and get_param_lane_def(param_key) then
    state.seq_note_edit_mode = param_key
  else
    state.seq_note_edit_mode = nil
  end
end

function seq_toggle_note_edit_mode(param_key)
  if state.seq_note_edit_mode == param_key then
    seq_set_note_edit_mode(nil)
  else
    seq_set_note_edit_mode(param_key)
  end
end

function seq_plain_letter_pressed(letter)
  if not letter or not r.ImGui_IsKeyPressed then
    return false
  end
  if is_ctrl_down() or is_cmd_down() or is_alt_down() or is_shift_down() then
    return false
  end
  local fn = r["ImGui_Key_" .. string.upper(letter)]
  if not fn then
    return false
  end
  return r.ImGui_IsKeyPressed(ctx, fn(), false)
end

function seq_plain_digit_pressed(digit)
  if digit == nil or not r.ImGui_IsKeyPressed then
    return false
  end
  if is_ctrl_down() or is_cmd_down() or is_alt_down() or is_shift_down() then
    return false
  end
  local fn = r["ImGui_Key_" .. tostring(digit)]
  if not fn then
    return false
  end
  return r.ImGui_IsKeyPressed(ctx, fn(), false)
end

function seq_capture_shortcut_key()
  if r.ImGui_SetNextFrameWantCaptureKeyboard then
    r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
  end
end

function seq_start_transport_playback()
  local play_state = r.GetPlayState and r.GetPlayState() or 0
  if (play_state & 1) == 0 then
    r.Main_OnCommand(1007, 0)
  end
end

function seq_hover_play_qn()
  local hover = state.seq_grid_hover
  if not hover or type(hover.hovered_qn) ~= "number" then
    return nil
  end
  local step_qn = hover.step_qn or state.seq_grid_qn or 0.25
  if step_qn <= 0 then
    step_qn = 0.25
  end
  -- Start of the hovered grid cell (measure/beat on the current grid).
  return math.max(0.0, math.floor((hover.hovered_qn / step_qn) + 1e-9) * step_qn)
end

function seq_play_from_hover_grid()
  local qn = seq_hover_play_qn()
  if qn then
    seq_set_playhead_qn(qn)
  end
  seq_start_transport_playback()
  return qn ~= nil
end

function seq_set_exclusive_slot_solo(slot)
  local changed = false
  for _, s in ipairs(state.seq_tracks or {}) do
    local want = (slot ~= nil and s.id == slot.id)
    if s.solo ~= want then
      s.solo = want
      changed = true
    end
  end
  if changed then
    seq_apply_all_slot_mix_to_reaper()
    save_config()
  end
  return changed
end

function seq_clear_all_slot_solos()
  local changed = false
  for _, s in ipairs(state.seq_tracks or {}) do
    if s.solo then
      s.solo = false
      changed = true
    end
  end
  if changed then
    seq_apply_all_slot_mix_to_reaper()
    save_config()
  end
  return changed
end

function seq_hover_slot()
  local hover = state.seq_grid_hover
  if not hover or not hover.slot_id then
    return nil
  end
  return seq_find_slot_by_id(hover.slot_id)
end

function seq_set_note_body_length(note, length_qn, step_qn)
  if type(note) ~= "table" then
    return
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  length_qn = math.max(step_qn * 0.05, tonumber(length_qn) or step_qn)
  if seq_note_has_stutter_span(note, step_qn) or seq_stutter_count(note) > 1 then
    note.length_qn = length_qn
  else
    note.decay_qn = length_qn
  end
  seq_clamp_note_fades(note, length_qn)
end

function seq_find_note_covering_abs_qn(region, slot, abs_qn, step_qn)
  if not region or not slot or type(abs_qn) ~= "number" then
    return nil, nil
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local pattern = get_seq_pattern(region.pattern_id, false)
  local notes = get_track_note_table(pattern, slot.id, false)
  if not notes then
    return nil, nil
  end
  local best_key, best_note, best_start = nil, nil, -math.huge
  for key, note in pairs(notes) do
    if type(note) == "table" and note.enabled ~= false then
      local start_qn = seq_note_visual_abs_qn(region, note, key, step_qn)
      local length_qn = seq_note_current_decay_length_qn(region, slot, note, key, step_qn) or 0.0
      local end_qn = start_qn + math.max(0.0, length_qn)
      if abs_qn >= start_qn - 1e-9 and abs_qn < end_qn - 1e-9 and start_qn >= best_start then
        best_key, best_note, best_start = tostring(key), note, start_qn
      end
    end
  end
  return best_key, best_note
end

function seq_split_note_at_qn(region, slot, step_key, note, split_qn, step_qn, snap)
  if not region or not slot or not note or type(split_qn) ~= "number" then
    return false
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  if snap then
    split_qn = seq_snap_qn(split_qn, step_qn)
  else
    split_qn = seq_quantize_free_qn(split_qn)
  end
  local start_qn = seq_note_visual_abs_qn(region, note, step_key, step_qn)
  local length_qn = seq_note_current_decay_length_qn(region, slot, note, step_key, step_qn) or 0.0
  local end_qn = start_qn + math.max(0.0, length_qn)
  local min_qn = snap and 1e-4 or (1.0 / 192.0)
  if split_qn <= start_qn + min_qn or split_qn >= end_qn - min_qn then
    return false
  end
  local left_len = split_qn - start_qn
  local right_len = end_qn - split_qn
  if left_len < min_qn or right_len < min_qn then
    return false
  end

  local own = seq_undo_own_begin("Split sequencer note")
  local right = clone_table_deep(note)
  seq_set_note_body_length(note, left_len, step_qn)
  seq_note_clear_fade_side(note, "out")
  seq_clamp_note_fades(note, left_len)

  right.qn_offset = split_qn - (region.start_qn or 0.0)
  right.step = math.floor((right.qn_offset / step_qn) + 1e-9)
  right.offset_qn = 0.0
  seq_set_note_body_length(right, right_len, step_qn)
  seq_note_clear_fade_side(right, "in")
  seq_clamp_note_fades(right, right_len)

  local new_key = seq_alloc_note_key(region, slot.id, right.qn_offset)
  set_seq_note(region, slot.id, new_key, right)
  register_seq_note_anim(region.id, slot.id, new_key, right, "add")
  state.selected_seq_note = { region_id = region.id, track_id = slot.id, step_key = new_key }
  sync_seq_pattern_note(region.pattern_id, slot, step_key)
  sync_seq_pattern_note(region.pattern_id, slot, new_key, { skip_neighbor = true })
  r.UpdateArrange()
  save_config()
  if own then
    end_seq_undo("Split sequencer note")
  end
  return true
end

function handle_seq_playback_and_split_keys()
  if not sequencer_is_open() then
    return
  end
  if imgui_any_popup_open() or seq_ingest_busy() then
    return
  end
  if shortcut_pressed("solo_play") then
    local slot = seq_hover_slot()
    if slot then
      seq_capture_shortcut_key()
      seq_set_exclusive_slot_solo(slot)
      seq_play_from_hover_grid()
    end
    return
  end
  if shortcut_pressed("unsolo_play") then
    seq_capture_shortcut_key()
    seq_clear_all_slot_solos()
    seq_play_from_hover_grid()
    return
  end
  local snap_split = shortcut_pressed("split_snap")
  local free_split = shortcut_pressed("split_free")
  if snap_split or free_split then
    local hover = state.seq_grid_hover
    if not hover or not hover.slot_id or type(hover.hovered_qn) ~= "number" then
      return
    end
    local slot = seq_find_slot_by_id(hover.slot_id)
    local region = seq_region_at_qn(hover.hovered_qn)
      or (hover.region_id and get_seq_region_by_id(hover.region_id))
    if not slot or not region then
      return
    end
    local step_qn = hover.step_qn or state.seq_grid_qn or 0.25
    local step_key, note = seq_find_note_covering_abs_qn(region, slot, hover.hovered_qn, step_qn)
    if not step_key or not note then
      return
    end
    seq_capture_shortcut_key()
    seq_split_note_at_qn(region, slot, step_key, note, hover.hovered_qn, step_qn, snap_split)
  end
end

function handle_seq_note_edit_mode_keys()
  if not sequencer_is_open() then
    return
  end
  if shortcut_pressed("pick_note_sample") then
    seq_toggle_note_sample_pick()
    seq_capture_shortcut_key()
    return
  end
  if imgui_any_popup_open() then
    return
  end
  if shortcut_pressed("preview_hover") then
    local now = r.time_precise()
    local is_double = (now - (state.seq_z_preview_last_t or 0)) < 0.45
    state.seq_z_preview_last_t = now
    if is_double and preview_proc then
      stop_preview()
      state.preview_paused = false
      state.preview_position = 0.0
      return
    end
    preview_seq_hovered_grid()
    return
  end
  if handle_seq_razor_keys() then
    return
  end
  if seq_ingest_busy() then
    return
  end
  if shortcut_pressed("enlarge_track") then
    if seq_toggle_enlarge_hovered_track() then
      seq_capture_shortcut_key()
    end
    return
  end
  if shortcut_pressed("cancel") then
    if state.seq_vary_filter_edit then
      seq_cancel_vary_filter_edit()
      return
    end
    if state.seq_note_edit_mode then
      seq_set_note_edit_mode(nil)
      return
    end
  end
  for _, def in ipairs(seq_note_edit_mode_defs()) do
    if def.shortcut_id and shortcut_pressed(def.shortcut_id) then
      seq_toggle_note_edit_mode(def.key)
      return
    end
  end
end

SEQ_RAZOR_FILL = 0x3DCEFF55
SEQ_RAZOR_EDGE = 0x3DCEFFFF
SEQ_RAZOR_PREVIEW_FILL = 0x3DCEFF88
SEQ_RAZOR_PREVIEW_EDGE = 0x9AEEFFFF
SEQ_RAZOR_HOVER_FILL = 0x3DCEFF99
SEQ_RAZOR_HOVER_EDGE = 0xB8F0FFFF

function seq_razor_right_down()
  if not ctx or not r.ImGui_IsMouseDown then
    return false
  end
  return r.ImGui_IsMouseDown(ctx, 1)
end

function seq_razor_right_clicked()
  if not ctx or not r.ImGui_IsMouseClicked then
    return false
  end
  return r.ImGui_IsMouseClicked(ctx, 1)
end

-- Alt + right-drag draws a razor. Alt+Ctrl/Cmd + right-drag adds another.
function seq_razor_gesture_active()
  if state.seq_razor_drag then
    return state.seq_razor_drag.mode ~= "move"
  end
  if not is_alt_down() then
    return false
  end
  return seq_razor_right_down() or seq_razor_right_clicked()
end

function seq_razor_copy_modifier()
  return is_ctrl_down() or is_cmd_down()
end

function seq_note_copy_modifier()
  return is_ctrl_down() or is_cmd_down()
end

function seq_note_slip_modifier()
  return is_shift_down()
end

function seq_razor_additive_gesture()
  return is_alt_down() and (is_ctrl_down() or is_cmd_down())
end

function seq_has_razors()
  return state.seq_razors and #state.seq_razors > 0
end

function seq_razor_blocks_grid_edit()
  return state.seq_razor_drag ~= nil or seq_razor_gesture_active()
end

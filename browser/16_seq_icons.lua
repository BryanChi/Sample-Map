-- Sample Map Browser module: seq_icons
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_icon_role_from_tags(tags)
  if type(tags) ~= "table" then
    return nil
  end
  local best_tag = nil
  local best_weight = -1
  for _, tag_name in ipairs(tags) do
    local key = tostring(tag_name or ""):lower()
    if SEQ_ROLE_ICON_FILES[key] then
      local weight = TAG_KEYWORD_WEIGHT[key] or 1
      if weight > best_weight then
        best_weight = weight
        best_tag = key
      end
    end
  end
  return best_tag
end

-- Resolve icon role without using full file paths (parent folders like
-- "Snare Pack/Hats/..." falsely match "snare" before "hat").
function seq_icon_role_for_sample(sample)
  if not sample then
    return "default"
  end

  local role = seq_icon_role_from_tags(sample.tags)
  if role then
    return role
  end

  role = classify_seq_role_text(sample.name)
  if role and SEQ_ROLE_ICON_FILES[role] then
    return role
  end

  if sample.path then
    local base = sample.path:match("([^/\\]+)$") or sample.path
    role = classify_seq_role_text(base)
    if role and SEQ_ROLE_ICON_FILES[role] then
      return role
    end
  end

  return "default"
end

-- Sequencer lanes: prefer the track's role identity over sample-path heuristics.
function seq_icon_role_for_slot(slot, sample)
  if slot then
    local role = classify_seq_role_text(slot.name)
    if role and SEQ_ROLE_ICON_FILES[role] then
      return role
    end
    role = classify_seq_role_text(slot.sample_tag)
    if role and SEQ_ROLE_ICON_FILES[role] then
      return role
    end
  end
  return seq_icon_role_for_sample(sample or (slot and find_sample_by_path(slot.sample_path)) or nil)
end

function get_seq_role_icon(role)
  ensure_seq_role_icons()
  if role and seq_icon_images.by_role[role] then
    return seq_icon_images.by_role[role]
  end
  return seq_icon_images.by_role.default
end

function draw_seq_role_icon(dl, cx, cy, half, sample, tint, role)
  if not r.ImGui_DrawList_AddImage then
    return false
  end
  role = role or seq_icon_role_for_sample(sample)
  if not role or not SEQ_ROLE_ICON_FILES[role] then
    role = "default"
  end
  local img = get_seq_role_icon(role)
  if not img then
    return false
  end
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(img, "ImGui_Image*") then
    seq_icon_images.attached_ctx = nil
    img = get_seq_role_icon(role)
    if not img then
      return false
    end
  end
  r.ImGui_DrawList_AddImage(
    dl, img,
    cx - half, cy - half, cx + half, cy + half,
    0.0, 0.0, 1.0, 1.0,
    tint or 0xFFFFFFFF
  )
  return true
end

function prune_seq_track_play_anims(now)
  local anims = state.seq_track_play_anims
  if not anims then
    return
  end
  for key, anim in pairs(anims) do
    local start_t = anim.start_time or 0.0
    local dur = anim.duration or SEQ_TRACK_PLAY_ANIM_DURATION
    if (now - start_t) >= dur then
      anims[key] = nil
    end
  end
end

function get_seq_track_play_anim(track_id, now)
  local anims = state.seq_track_play_anims
  if not anims or track_id == nil then
    return nil
  end
  local anim = anims[tostring(track_id)]
  if not anim then
    return nil
  end
  local dur = anim.duration or SEQ_TRACK_PLAY_ANIM_DURATION
  local t = dur > 0 and ((now - (anim.start_time or now)) / dur) or 1.0
  if t <= 0.0 then
    t = 0.0
  elseif t >= 1.0 then
    anims[tostring(track_id)] = nil
    return nil
  end
  anim.t = t
  return anim
end

function draw_seq_track_play_row_fx(dl, x0, y0, x1, y1, play_t, sample)
  if not play_t then
    return
  end
  local pulse = math.sin(play_t * math.pi)
  local accent = sample and get_sample_dot_color(sample) or UI_THEME.accent
  local ar, ag, ab = extract_rgb_rrgbbaa(accent)
  local bg_alpha = math.floor(24 + pulse * 48 + (1.0 - play_t) * 36)
  local edge_alpha = math.floor(50 + pulse * 130)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, build_color_rrgbbaa(ar, ag, ab, bg_alpha), 4)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, build_color_rrgbbaa(255, 255, 255, edge_alpha), 4, 0, 1.0 + pulse * 1.5)
  local bar_w = 2.0 + pulse * 3.0
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + bar_w, y1, build_color_rrgbbaa(ar, ag, ab, math.floor(110 + pulse * 145)), 2)
end

function get_seq_track_sample_controls_width(ctrl_size, icon_size)
  ctrl_size = ctrl_size or 20.0
  icon_size = icon_size or SEQ_SAMPLE_DOT_SIZE
  local item_spacing = seq_sample_controls_item_spacing()
  return ctrl_size * 2 + icon_size + item_spacing * 2 + 2.0
end

function draw_sample_dot_control(sample, id_suffix, is_swap_active, play_t, role, icon_size, cue)
  local size = icon_size or SEQ_SAMPLE_DOT_SIZE
  r.ImGui_InvisibleButton(ctx, "seq_dot_" .. id_suffix, size, size)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local hover_flags = 0
  if sample_drag_active() and r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
    hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
  end
  local hovered = r.ImGui_IsItemHovered(ctx, hover_flags)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  if sample_drag_active() and not hovered then
    local mx, my = r.ImGui_GetMousePos(ctx)
    if mx and mx >= min_x and mx <= max_x and my >= min_y and my <= max_y then
      hovered = true
    end
  end
  local cx = (min_x + max_x) * 0.5
  local cy = (min_y + max_y) * 0.5
  local pulse = play_t and math.sin(play_t * math.pi) or 0.0
  local icon_half = (size * 0.46) + pulse * math.min(2.0, size * 0.06)
  local fill = get_sample_dot_color(sample)
  cue = cue or {}
  local region_color = cue.region_color
  local override_color = cue.override_color or region_color
  local has_override = cue.has_override
  local edit_mode = cue.edit_mode
  local ring_color = is_swap_active and 0xFFFFFFFF
    or (edit_mode and region_color)
    or (has_override and override_color)
    or 0x666666FF
  local ring_radius = icon_half + ((is_swap_active or edit_mode or has_override) and 2.0 or 1.0)
  local ring_thickness = is_swap_active and 2.0 or ((edit_mode or has_override) and 2.0 or 1.0)

  if (edit_mode or has_override) and (region_color or override_color) then
    local halo_col = (edit_mode and region_color) or override_color
    local halo_a = edit_mode and (has_override and 90 or 55) or 40
    local rr, rg, rb = extract_rgb_rrgbbaa(halo_col)
    r.ImGui_DrawList_AddCircleFilled(
      dl, cx, cy, icon_half + 3.5,
      build_color_rrgbbaa(rr, rg, rb, halo_a),
      24
    )
  end

  if play_t and sample then
    local ripple_r = ring_radius + 4.0 + play_t * 12.0
    local ripple_alpha = math.floor((1.0 - play_t) * 170 + pulse * 35)
    local sr, sg, sb = extract_rgb_rrgbbaa(fill)
    r.ImGui_DrawList_AddCircle(dl, cx, cy, ripple_r, build_color_rrgbbaa(sr, sg, sb, ripple_alpha), 24, 1.5)
    local outer_r = icon_half + 2.0 + pulse * 3.0
    r.ImGui_DrawList_AddCircle(dl, cx, cy, outer_r, build_color_rrgbbaa(255, 255, 255, math.floor(40 + pulse * 120)), 24, 1.0)
  end

  if sample then
    local icon_role = role or seq_icon_role_for_sample(sample)
    if not draw_seq_role_icon(dl, cx, cy, icon_half, sample, fill, icon_role) then
      r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, icon_half * 0.55, fill, 24)
    end
  end
  r.ImGui_DrawList_AddCircle(dl, cx, cy, ring_radius, ring_color or 0x666666FF, 24, ring_thickness)
  if cue.drop_armed and hovered then
    local dp = drag_pulse()
    local rr, rg, rb
    if region_color then
      rr, rg, rb = extract_rgb_rrgbbaa(region_color)
    else
      rr, rg, rb = 30, 255, 94
    end
    r.ImGui_DrawList_AddCircle(
      dl, cx, cy, ring_radius + 3.0 + dp * 2.0,
      build_color_rrgbbaa(rr, rg, rb, math.floor(160 + 80 * dp)),
      24, 2.2
    )
  end
  if has_override and override_color then
    local pip_r = math.max(2.2, size * 0.13)
    local pip_x = max_x - pip_r - 0.4
    local pip_y = max_y - pip_r - 0.4
    r.ImGui_DrawList_AddCircleFilled(dl, pip_x, pip_y, pip_r + 1.1, 0xFF111111, 12)
    r.ImGui_DrawList_AddCircleFilled(dl, pip_x, pip_y, pip_r, override_color, 12)
    r.ImGui_DrawList_AddCircle(dl, pip_x, pip_y, pip_r, 0xFFFFFFFF, 12, 1.0)
  end

  return clicked, hovered
end

function render_seq_track_sample_controls(slot, idx, opts)
  opts = opts or {}
  local id_suffix = opts.id_suffix or tostring(slot.id)
  local icon_size = opts.icon_size
  if not icon_size and opts.lane_h then
    icon_size = seq_icon_size_for_lane_h(opts.lane_h)
  end
  icon_size = icon_size or SEQ_SAMPLE_DOT_SIZE
  local ctrl_size = opts.ctrl_size or seq_ctrl_size_for_icon(icon_size)
  local show_sample_label = opts.show_sample_label == true
  local sample_label_max_len = opts.sample_label_max_len or 22
  local item_spacing = seq_sample_controls_item_spacing()
  local container_h = opts.container_h or opts.lane_h
  if not container_h then
    container_h = math.max(ctrl_size, icon_size)
  end

  local swap_active = state.seq_swap_track_id and state.seq_swap_track_id == slot.id
  local edit_region = seq_region_sample_edit_region and seq_region_sample_edit_region() or nil
  local cue_region, has_override = seq_slot_region_sample_cue(slot)
  local display_region = edit_region or get_seq_region_by_id(state.selected_seq_region_id)
  local assigned_sample = seq_effective_slot_sample(slot, display_region)
    or (slot.sample_path and find_sample_by_path(slot.sample_path)) or nil
  local play_anim = get_seq_track_play_anim(slot.id, r.time_precise())
  local play_t = play_anim and play_anim.t or nil
  local icon_role = seq_icon_role_for_slot(slot, assigned_sample)
  local sample_label = (assigned_sample and (assigned_sample.name or basename(assigned_sample.path)))
    or slot.sample_name or "(no sample)"
  if #sample_label > sample_label_max_len then
    sample_label = sample_label:sub(1, sample_label_max_len - 3) .. "..."
  end
  local cue_color = (edit_region or (has_override and cue_region))
    and seq_region_pool_color((edit_region or cue_region).pool_id, 230)
    or nil
  local dot_cue = {
    region_color = cue_color,
    override_color = has_override and cue_color or nil,
    has_override = has_override,
    edit_mode = edit_region ~= nil,
  }

  local row_drop_hovered = false
  local can_nav = assigned_sample ~= nil or (slot.sample_path and slot.sample_path ~= "")
  local start_x, start_y = r.ImGui_GetCursorScreenPos(ctx)
  local x = start_x
  -- Center in the track/row rect (opts.y0/y1), not relative to a pre-offset cursor.
  local area_y0 = opts.y0 or start_y
  local area_y1 = opts.y1 or (area_y0 + container_h)
  local mid_y = (area_y0 + area_y1) * 0.5

  -- Lay out chevrons + icon on a shared vertical center so lane zoom never skews them.
  if not can_nav then
    r.ImGui_BeginDisabled(ctx)
  end
  r.ImGui_SetCursorScreenPos(ctx, x, mid_y - ctrl_size * 0.5)
  if draw_ui_button("seq_left_" .. id_suffix, nil, ctrl_size, ctrl_size, { icon = "chev_left", compact = true, style = "ghost_arrow" }) then
    swap_seq_track_sample_neighbor(slot, -1)
    seq_open_minimap_popup(slot, true)
  end
  if sample_drag_active() and r.ImGui_IsItemHovered(ctx) and not seq_drag_is_from_candidate() then
    row_drop_hovered = true
  end
  if not can_nav then
    r.ImGui_EndDisabled(ctx)
  end
  x = x + ctrl_size + item_spacing

  r.ImGui_SetCursorScreenPos(ctx, x, mid_y - icon_size * 0.5)
  local region_mode = edit_region ~= nil
  dot_cue.drop_armed = sample_drag_active() and region_mode
  local dot_clicked, dot_hovered = draw_sample_dot_control(assigned_sample, id_suffix, swap_active, play_t, icon_role, icon_size, dot_cue)
  if r.ImGui_IsItemClicked(ctx, 1) then
    local region = seq_region_sample_edit_region and seq_region_sample_edit_region() or nil
    if region and seq_slot_has_region_sample(slot, region) then
      local own = seq_undo_own_begin("Clear region sample")
      seq_assign_region_track_sample(region, slot, nil, true)
      preview_seq_track_sample(slot)
      if own then
        end_seq_undo("Clear region sample")
      end
    end
  end
  if dot_hovered and r.ImGui_SetTooltip then
    if sample_drag_active() and edit_region then
      r.ImGui_SetTooltip(ctx, "Release to set this region's sample")
    elseif edit_region then
      if has_override then
        r.ImGui_SetTooltip(ctx, "Region sample — swap to change this region and linked copies\nRight-click to restore the track sample")
      else
        r.ImGui_SetTooltip(ctx, "Swap drums to change this region's sample (linked copies too)")
      end
    elseif has_override then
      r.ImGui_SetTooltip(ctx, "This track has a sample for the focused region")
    end
  end
  if dot_clicked and not sample_drag_active() then
    begin_seq_swap_mode(idx)
    if not sample_map_is_open() then
      state.active_view = "sample_map"
      save_config()
    end
  end
  if sample_drag_active() and dot_hovered and not seq_candidate_drag_from_slot(slot) then
    if region_mode then
      state.seq_drum_drop = { slot_id = slot.id, idx = idx }
      state.seq_candidate_drop = nil
      state.seq_drop_target_idx = nil
      state.seq_timeline_drop_time = nil
      state.seq_timeline_drop_track_idx = nil
    elseif not seq_drag_is_from_candidate() then
      row_drop_hovered = true
    end
  end
  x = x + icon_size + item_spacing

  if not can_nav then
    r.ImGui_BeginDisabled(ctx)
  end
  r.ImGui_SetCursorScreenPos(ctx, x, mid_y - ctrl_size * 0.5)
  if draw_ui_button("seq_right_" .. id_suffix, nil, ctrl_size, ctrl_size, { icon = "chev_right", compact = true, style = "ghost_arrow" }) then
    swap_seq_track_sample_neighbor(slot, 1)
    seq_open_minimap_popup(slot, true)
  end
  if sample_drag_active() and r.ImGui_IsItemHovered(ctx) and not seq_drag_is_from_candidate() then
    row_drop_hovered = true
  end
  if not can_nav then
    r.ImGui_EndDisabled(ctx)
  end
  x = x + ctrl_size

  if show_sample_label then
    local _, label_h = r.ImGui_CalcTextSize(ctx, sample_label)
    r.ImGui_SetCursorScreenPos(ctx, x + item_spacing, mid_y - (label_h or 0) * 0.5)
    r.ImGui_TextColored(ctx, assigned_sample and 0xFFCCCCCC or 0xFF666666, sample_label)
    if sample_drag_active() and r.ImGui_IsItemHovered(ctx) and not seq_drag_is_from_candidate() then
      row_drop_hovered = true
    end
    local label_max_x = select(1, r.ImGui_GetItemRectMax(ctx)) or (x + item_spacing)
    x = math.max(x, label_max_x)
  end

  -- Reserve the laid-out strip so following widgets don't overlap.
  r.ImGui_SetCursorScreenPos(ctx, start_x, start_y)
  r.ImGui_Dummy(ctx, math.max(1.0, x - start_x), container_h)

  state.seq_nav_anchors = state.seq_nav_anchors or {}
  state.seq_nav_anchors[slot.id] = {
    x = start_x,
    y = area_y0,
    w = math.max(1.0, x - start_x),
    h = math.max(1.0, area_y1 - area_y0),
  }

  return {
    row_drop_hovered = row_drop_hovered,
    swap_active = swap_active,
    row_h = container_h,
    icon_size = icon_size,
    ctrl_size = ctrl_size,
  }
end


function render_seq_tracks_panel()
  state.map_hover_track_id = nil
  seq_sync_track_order_from_arrange()

  if state.seq_random_edit_region_id then
    local random_edit_region = nil
    for _, reg in ipairs(state.seq_regions) do
      if reg.id == state.seq_random_edit_region_id then
        random_edit_region = reg
        break
      end
    end
    if random_edit_region then
      r.ImGui_TextColored(ctx, UI_THEME.text, "Region Random: " .. (random_edit_region.name or ("Region " .. tostring(random_edit_region.id))))
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Adjust knobs in sequencer lanes. Swap drums for this region only.")
      r.ImGui_Separator(ctx)
    else
      state.seq_random_edit_region_id = nil
    end
  end

  prune_seq_track_play_anims(r.time_precise())

  local add_row_h = 28.0
  local add_row_gap = 6.0
  local row_h = SEQ_PANEL_TRACK_ROW_H
  local icon_size = SEQ_PANEL_ICON_SIZE
  local ctrl_size = seq_ctrl_size_for_icon(icon_size)
  local nav_w = get_seq_track_sample_controls_width(ctrl_size, icon_size)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  if #state.seq_tracks == 0 then
    r.ImGui_TextColored(ctx, 0xFF888888, "No tracks")
  else
    for idx, slot in ipairs(state.seq_tracks) do
      local selected = state.selected_seq_track == idx
      local swap_active = state.seq_swap_track_id and state.seq_swap_track_id == slot.id
      local display_region = seq_region_sample_edit_region() or get_seq_region_by_id(state.selected_seq_region_id)
      local assigned_sample = seq_effective_slot_sample(slot, display_region)
        or (slot.sample_path and find_sample_by_path(slot.sample_path)) or nil
      local cue_region, has_override = seq_slot_region_sample_cue(slot)
      local stripe_region = has_override and (display_region or cue_region) or nil

      r.ImGui_PushID(ctx, slot.id)

      local row_x, row_y = r.ImGui_GetCursorScreenPos(ctx)
      local avail_w = r.ImGui_GetContentRegionAvail(ctx)
      local gap = 4.0
      local ctrl_x1 = row_x + math.max(90.0, avail_w - nav_w - gap)
      local row_drop_hovered = false
      local mx, my = r.ImGui_GetMousePos(ctx)
      local row_hovered = mx >= row_x and mx < row_x + avail_w and my >= row_y and my < row_y + row_h
        and r.ImGui_IsWindowHovered(ctx)
      if row_hovered then
        state.map_hover_track_id = slot.id
      end

      if selected or swap_active then
        r.ImGui_DrawList_AddRectFilled(dl, row_x, row_y, row_x + avail_w, row_y + row_h,
          swap_active and UI_THEME.accent_fill_h or UI_THEME.accent_fill, 4.0)
      elseif row_hovered and not seq_candidate_drag_from_slot(slot) then
        r.ImGui_DrawList_AddRectFilled(dl, row_x, row_y, row_x + avail_w, row_y + row_h, 0xFFFFFF12, 4.0)
      end
      if stripe_region then
        local stripe = seq_region_pool_color(stripe_region.pool_id, 220)
        r.ImGui_DrawList_AddRectFilled(dl, row_x, row_y, row_x + 3.5, row_y + row_h, stripe, 2.0)
        local sr, sg, sb = extract_rgb_rrgbbaa(stripe)
        r.ImGui_DrawList_AddRectFilled(
          dl, row_x, row_y, row_x + avail_w, row_y + row_h,
          build_color_rrgbbaa(sr, sg, sb, 22),
          4.0
        )
      end

      local layout = seq_get_track_control_layout(row_x, row_y, ctrl_x1, row_y + row_h, slot, { hide_expand = true })
      seq_draw_track_name_and_expand(dl, slot, layout, false, 255, nil, slot.name)

      local name_box = layout.name
      if name_box and name_box.w > 4 then
        r.ImGui_SetCursorScreenPos(ctx, name_box.x, name_box.y)
        r.ImGui_InvisibleButton(ctx, "##seq_panel_name_" .. slot.id, name_box.w, name_box.h)
        if r.ImGui_IsItemClicked(ctx, 0) and not sample_drag_active() then
          select_seq_track(idx)
        end
        if r.ImGui_IsItemClicked(ctx, 1) then
          seq_open_track_context_menu(slot.id)
        end
        if sample_drag_active() and r.ImGui_IsItemHovered(ctx)
            and not seq_candidate_drag_from_slot(slot) then
          row_drop_hovered = true
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          local linked_name = get_reaper_track_display_name(slot.reaper_track_guid)
          local tip = slot.name
          if linked_name and linked_name ~= "" and linked_name ~= slot.name then
            tip = tip .. "\n" .. linked_name
          end
          if assigned_sample and assigned_sample.name then
            tip = tip .. "\n" .. assigned_sample.name
          end
          if has_override then
            tip = tip .. "\nRegion sample"
          end
          r.ImGui_SetTooltip(ctx, tip)
        end
      end

      local mix_changed, overlap_changed, mix_hovered = render_seq_track_mix_controls(dl, slot, layout)
      if mix_hovered and not seq_candidate_drag_from_slot(slot) then
        row_drop_hovered = true
      end
      if row_hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 1)
          and not seq_layout_hit(layout.mix_hit, mx, my)
          and mx < ctrl_x1 then
        seq_open_track_context_menu(slot.id)
      end
      if mix_changed then
        begin_seq_undo("Adjust sequencer mix")
        seq_undo_commit_on_release = true
        seq_on_slot_mix_changed(slot, { resync = overlap_changed })
      end

      r.ImGui_SetCursorScreenPos(ctx, ctrl_x1 + gap, row_y)
      r.ImGui_PushID(ctx, "seq_panel_nav_" .. slot.id)
      local nav = render_seq_track_sample_controls(slot, idx, {
        id_suffix = "panel_" .. slot.id,
        ctrl_size = ctrl_size,
        icon_size = icon_size,
        container_h = row_h,
        y0 = row_y,
        y1 = row_y + row_h,
      })
      r.ImGui_PopID(ctx)
      if nav.row_drop_hovered then
        row_drop_hovered = true
      end

      r.ImGui_SetCursorScreenPos(ctx, row_x, row_y + row_h)

      if sample_drag_active() and row_hovered and not seq_drag_is_from_candidate() then
        row_drop_hovered = true
      end
      local play_anim = get_seq_track_play_anim(slot.id, r.time_precise())
      if play_anim then
        draw_seq_track_play_row_fx(dl, row_x, row_y, row_x + avail_w, row_y + row_h, play_anim.t, assigned_sample)
      end
      local cand_drop = state.seq_candidate_drop ~= nil
      local drum_drop = state.seq_drum_drop ~= nil
      if sample_drag_active() and row_drop_hovered and not cand_drop and not drum_drop
          and not seq_drag_is_from_candidate() then
        state.seq_drop_target_idx = idx
        state.seq_timeline_drop_time = nil
        state.seq_timeline_drop_track_idx = nil
        draw_drop_target_highlight(dl, row_x, row_y, row_x + avail_w, row_y + row_h, 4)
      end

      r.ImGui_Dummy(ctx, 0, 2)
      r.ImGui_PopID(ctx)
    end
  end

  r.ImGui_Dummy(ctx, 0, add_row_gap)
  render_seq_add_track_full_width_button("seq_add_track_popup_open", add_row_h)
  render_seq_add_track_popup()
  render_seq_track_context_menu()

  if render_seq_midi_assign_popup() then
    save_config()
    if save_seq_project_state then
      save_seq_project_state()
    end
  end

  if seq_undo_commit_on_release and r.ImGui_IsMouseReleased
      and (r.ImGui_IsMouseReleased(ctx, 0) or r.ImGui_IsMouseReleased(ctx, 1)) then
    if seq_undo_is_open() then
      end_seq_undo()
    end
    seq_undo_commit_on_release = false
  end

  if sample_drag_active() and (state.seq_drop_target_idx or state.seq_candidate_drop or state.seq_drum_drop) then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
  end
end

function get_arrange_view_range()
  if r.GetSet_ArrangeView2 then
    local a, b, c, d = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
    local start_time = nil
    local end_time = nil
    if type(a) == "number" and type(b) == "number" then
      start_time, end_time = a, b
    elseif type(c) == "number" and type(d) == "number" then
      start_time, end_time = c, d
    end
    if start_time and end_time and end_time > start_time then
      return start_time, end_time
    end
  end
  local cursor = r.GetCursorPosition()
  return math.max(0.0, cursor - 4.0), cursor + 12.0
end

function set_arrange_view_range(start_time, end_time)
  if not r.GetSet_ArrangeView2 or type(start_time) ~= "number" or type(end_time) ~= "number" then
    return false
  end
  if end_time <= start_time then
    return false
  end
  r.GetSet_ArrangeView2(0, true, 0, 0, start_time, end_time)
  return true
end

function seq_push_view_to_arrange()
  local start_qn = state.seq_view_start_qn
  local span_qn = state.seq_view_span_qn
  if type(start_qn) ~= "number" or type(span_qn) ~= "number" or span_qn <= 0 then
    return false
  end
  local t0 = qn_to_time(start_qn)
  local t1 = qn_to_time(start_qn + span_qn)
  if not t0 or not t1 or t1 <= t0 then
    return false
  end
  return set_arrange_view_range(t0, t1)
end

function get_project_grid_step_qn()
  local step_qn = 0.25
  if r.GetSetProjectGrid then
    local _, div = r.GetSetProjectGrid(0, false)
    if type(div) == "number" and div > 0.000001 then
      step_qn = math.abs(div)
    end
  end
  return step_qn
end

function time_to_qn(time_pos)
  if r.TimeMap2_timeToQN then
    return r.TimeMap2_timeToQN(0, time_pos)
  elseif r.TimeMap_timeToQN then
    return r.TimeMap_timeToQN(time_pos)
  end
  return nil
end

function qn_to_time(qn)
  if r.TimeMap2_QNToTime then
    return r.TimeMap2_QNToTime(0, qn)
  elseif r.TimeMap_QNToTime then
    return r.TimeMap_QNToTime(qn)
  end
  return nil
end

function get_visible_qn_grid_range(qn_start_raw, qn_end_raw)
  local step_qn = (type(state.seq_grid_qn) == "number" and state.seq_grid_qn > 0) and state.seq_grid_qn or get_project_grid_step_qn()
  qn_start_raw = qn_start_raw or 0.0
  qn_end_raw = qn_end_raw or (qn_start_raw + step_qn * 16.0)
  if qn_end_raw <= qn_start_raw then
    qn_end_raw = qn_start_raw + step_qn * 16.0
  end

  local start_qn = math.floor((qn_start_raw / step_qn) + 1e-9) * step_qn
  local end_qn = math.ceil((qn_end_raw / step_qn) - 1e-9) * step_qn
  if end_qn <= start_qn then
    end_qn = start_qn + step_qn
  end

  local step_count = math.max(1, math.floor(((end_qn - start_qn) / step_qn) + 0.5))
  local max_steps = 768
  if step_count > max_steps then
    local mult = math.ceil(step_count / max_steps)
    step_qn = step_qn * mult
    start_qn = math.floor((qn_start_raw / step_qn) + 1e-9) * step_qn
    end_qn = math.ceil((qn_end_raw / step_qn) - 1e-9) * step_qn
    if end_qn <= start_qn then
      end_qn = start_qn + step_qn
    end
    step_count = math.max(1, math.floor(((end_qn - start_qn) / step_qn) + 0.5))
  end

  return start_qn, end_qn, step_qn, step_count
end

function get_seq_slot_target_track(slot)
  if not slot then
    return nil
  end
  if slot.reaper_track_guid then
    local tr = get_track_by_guid(slot.reaper_track_guid)
    if tr then
      return tr
    end
  end
  local tr = r.GetSelectedTrack(0, 0)
  if tr then
    return tr
  end
  if r.CountTracks(0) > 0 then
    return r.GetTrack(0, 0)
  end
  return nil
end

function collect_seq_item_cells(start_qn, end_qn, step_qn, step_count)
  local occupied_any = {}
  local occupied_match = {}

  for idx, slot in ipairs(state.seq_tracks) do
    occupied_any[idx] = {}
    occupied_match[idx] = {}

    local tr = get_seq_slot_target_track(slot)
    if tr then
      local item_count = r.CountTrackMediaItems(tr)
      local expected_path = nil
      if slot.sample_path and slot.sample_path ~= "" then
        expected_path = normalize_path(slot.sample_path)
      end

      for item_idx = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(tr, item_idx)
        if item then
          local item_time = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local item_qn = time_to_qn(item_time)
          if item_qn then
            local col = math.floor(((item_qn - start_qn) / step_qn) + 0.5)
            if col >= 0 and col < step_count then
              occupied_any[idx][col] = true
              if not expected_path then
                occupied_match[idx][col] = true
              else
                local take = r.GetActiveTake(item)
                local src = take and r.GetMediaItemTake_Source(take) or nil
                if src and r.GetMediaSourceFileName then
                  local _, src_path = r.GetMediaSourceFileName(src, "")
                  if src_path and normalize_path(src_path) == expected_path then
                    occupied_match[idx][col] = true
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return occupied_any, occupied_match
end

function remove_seq_items_in_cell(slot, start_qn, step_qn, col)
  local tr = get_seq_slot_target_track(slot)
  if not tr then
    return 0
  end

  local removed = 0

  for item_idx = r.CountTrackMediaItems(tr) - 1, 0, -1 do
    local item = r.GetTrackMediaItem(tr, item_idx)
    if item then
      local item_time = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_qn = time_to_qn(item_time)
      if item_qn then
        local item_col = math.floor(((item_qn - start_qn) / step_qn) + 0.5)
        if item_col == col then
          if r.DeleteTrackMediaItem(tr, item) then
            removed = removed + 1
          end
        end
      end
    end
  end

  if removed > 0 then
    r.UpdateArrange()
  end
  return removed
end

SEQ_EXT_FLAG = "P_EXT:SampleMapSeq"
SEQ_EXT_REGION = "P_EXT:SampleMapSeqRegion"
SEQ_EXT_PATTERN = "P_EXT:SampleMapSeqPattern"
SEQ_EXT_TRACK = "P_EXT:SampleMapSeqTrack"
SEQ_EXT_STEP = "P_EXT:SampleMapSeqStep"
SEQ_EXT_LAYER = "P_EXT:SampleMapSeqLayer"
SEQ_EXT_GHOST = "P_EXT:SampleMapSeqGhost"
SEQ_EXT_PARENT = "P_EXT:SampleMapSeqParent"
SEQ_EXT_POOL = "P_EXT:SampleMapSeqPool"

function get_item_ext(item, key)
  if not item or not r.GetSetMediaItemInfo_String then
    return nil
  end
  local ok, value = r.GetSetMediaItemInfo_String(item, key, "", false)
  if ok then
    return value
  end
  return nil
end

function set_item_ext(item, key, value)
  if item and r.GetSetMediaItemInfo_String then
    r.GetSetMediaItemInfo_String(item, key, tostring(value or ""), true)
  end
end

seq_arrange_overlay_ctx = nil
seq_arrange_overlay_hwnd = nil
seq_arrange_hl_bm = nil
seq_arrange_hl_bm_w = 0
seq_arrange_hl_bm_h = 0
seq_arrange_hl_hwnd = nil
seq_arrange_hl_linked = false
seq_arrange_hl_pending = nil

function seq_get_arrange_hwnd()
  if not r.GetMainHwnd then
    return nil
  end
  local main = r.GetMainHwnd()
  if not main then
    return nil
  end
  if r.JS_Window_FindChildByID then
    local hwnd = r.JS_Window_FindChildByID(main, 1000)
    if hwnd then
      return hwnd
    end
  end
  if r.JS_Window_FindChild then
    return r.JS_Window_FindChild(main, "trackview", true)
  end
  return nil
end

function seq_js_unpack4(a, b, c, d, e)
  if type(a) == "boolean" or a == nil then
    return b, c, d, e
  end
  return a, b, c, d
end

function seq_get_arrange_geometry()
  local hwnd = seq_get_arrange_hwnd()
  if not hwnd then
    return nil
  end
  local geo = { hwnd = hwnd, view_w = nil, view_h = nil, scroll_pos = 0, l = nil, t = nil, r = nil, b = nil }

  if r.JS_Window_GetClientSize then
    local w, h = seq_js_unpack4(r.JS_Window_GetClientSize(hwnd))
    if type(w) == "number" and type(h) == "number" then
      geo.view_w = math.abs(w)
      geo.view_h = math.abs(h)
      geo.client_w = geo.view_w
      geo.client_h = geo.view_h
    end
  end

  if r.JS_Window_GetScrollInfo then
    local pos, page = seq_js_unpack4(r.JS_Window_GetScrollInfo(hwnd, "v"))
    if type(pos) == "number" then
      geo.scroll_pos = pos
    end
    -- pageSize is the visible arrange height in the same space as I_TCPY
    if type(page) == "number" and page > 8 then
      geo.view_h = page
      geo.v_page = page
    end
    local hpos, hpage = seq_js_unpack4(r.JS_Window_GetScrollInfo(hwnd, "h"))
    if type(hpage) == "number" then
      geo.h_page = hpage
    end
    if type(hpos) == "number" then
      geo.h_pos = hpos
    end
  end

  if r.JS_Window_GetClientRect then
    local l, t, rgt, btm = seq_js_unpack4(r.JS_Window_GetClientRect(hwnd))
    if type(l) == "number" and type(t) == "number" and type(rgt) == "number" and type(btm) == "number" then
      geo.l, geo.t, geo.r, geo.b = l, t, rgt, btm
      if not geo.view_w then
        geo.view_w = math.abs(rgt - l)
      end
      if not geo.view_h then
        geo.view_h = math.abs(btm - t)
      end
    end
  end

  if not geo.view_h or geo.view_h <= 8 then
    return geo
  end
  return geo
end

function seq_arrange_imgui_rect(octx, geo)
  if not geo or not geo.l then
    return nil
  end
  local x0, y0 = seq_native_to_imgui(octx, geo.l, geo.t)
  local x1, y1 = seq_native_to_imgui(octx, geo.r, geo.b)
  if x1 < x0 then x0, x1 = x1, x0 end
  if y1 < y0 then y0, y1 = y1, y0 end
  if x1 - x0 < 4 or y1 - y0 < 4 then
    return nil
  end
  return x0, y0, x1, y1
end

-- Follow and overlay both ask for the hovered items each frame; scan once.
function seq_find_hovered_arrange_items()
  local hover = state.seq_grid_hover
  local frame = nil
  if r.ImGui_GetFrameCount and ctx then
    local ok, fc = pcall(r.ImGui_GetFrameCount, ctx)
    if ok then frame = fc end
  end
  local c = state.seq_hover_items_frame_cache
  if frame and c and c.frame == frame and hover and c.hover == hover
      and c.slot_id == hover.slot_id and c.region_id == hover.region_id
      and c.step_key == hover.step_key and c.note == hover.note then
    return c.items, c.track
  end
  local items, track = seq_find_hovered_arrange_items_scan()
  if frame and hover then
    state.seq_hover_items_frame_cache = {
      frame = frame, hover = hover, slot_id = hover.slot_id, region_id = hover.region_id,
      step_key = hover.step_key, note = hover.note, items = items, track = track,
    }
  else
    state.seq_hover_items_frame_cache = nil
  end
  return items, track
end

function seq_find_hovered_arrange_items_scan()
  local hover = state.seq_grid_hover
  if not hover or not hover.slot_id or not hover.note then
    return nil, nil
  end
  local slot = nil
  for _, s in ipairs(state.seq_tracks) do
    if s.id == hover.slot_id then
      slot = s
      break
    end
  end
  if not slot then
    return nil, nil
  end
  local tr = get_seq_slot_target_track(slot)
  if not tr then
    return nil, nil
  end
  local region_id = hover.region_id
  local step = tostring(hover.step_key or "")
  local track_key = tostring(slot.id)
  local items = {}
  local aux = {}
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local item = r.GetTrackMediaItem(tr, i)
    if item and seq_item_is_owned(item, region_id)
        and tostring(get_item_ext(item, SEQ_EXT_TRACK) or "") == track_key
        and tostring(get_item_ext(item, SEQ_EXT_STEP) or "") == step then
      if seq_item_is_aux_piece(item) then
        aux[#aux + 1] = item
      else
        items[#items + 1] = item
      end
    end
  end
  if #items == 0 then
    items = aux
  end
  if #items == 0 then
    local t0, t1 = seq_hover_note_time_span()
    if t0 and t1 then
      for i = 0, r.CountTrackMediaItems(tr) - 1 do
        local item = r.GetTrackMediaItem(tr, i)
        if item and seq_item_is_owned(item, region_id) then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
          if pos < t1 and (pos + len) > t0 then
            items[#items + 1] = item
          end
        end
      end
    end
  end
  if #items == 0 then
    return nil, tr
  end
  return items, tr
end

function seq_hover_note_time_span()
  local hover = state.seq_grid_hover
  if not hover or not hover.note then
    return nil
  end
  local region = hover.region_id and get_seq_region_by_id(hover.region_id) or nil
  local abs_qn = seq_note_visual_abs_qn(region, hover.note, hover.step_key)
  local t0 = qn_to_time(abs_qn)
  if type(t0) ~= "number" then
    return nil
  end
  local t1 = nil
  local len_qn = tonumber(hover.note.length_qn)
  if len_qn and len_qn > 0 then
    t1 = qn_to_time(abs_qn + len_qn)
  end
  if type(t1) ~= "number" or t1 <= t0 then
    local sample = resolve_seq_hovered_grid_sample and resolve_seq_hovered_grid_sample() or nil
    local dur = sample and (tonumber(sample.effective_duration) or tonumber(sample.duration)) or 0.25
    t1 = t0 + math.max(0.05, dur)
  end
  return t0, t1
end

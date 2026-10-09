-- Sample Map Browser module: seq_random_ui
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_draw_random_caption(dl, x, y, w, text, color)
  if not text or text == "" then
    return
  end
  local tw = select(1, r.ImGui_CalcTextSize(ctx, text)) or 8.0
  r.ImGui_DrawList_AddText(dl, x + (w - tw) * 0.5, y, color or UI_THEME.text_dim, text)
end

function seq_get_lane_random_layout(row_pos, timeline_x0)
  local y0 = row_pos.y0
  local y1 = row_pos.y1
  local lane_h = y1 - y0
  local defs = {
    { id = "prob",  label = "Prob", short = "P", has_seed = true },
    { id = "human", label = "Hum",  short = "H", has_seed = true },
    { id = "vel",   label = "Vel",  short = "V", has_seed = true },
    { id = "vary",  label = "Vary", short = "Y", has_seed = true, has_refresh = true },
    { id = "stut",  label = "Stut", short = "S", has_seed = true },
    { id = "grace", label = "Grace", short = "G", has_seed = true },
    { id = "after", label = "After", short = "A", has_seed = true },
  }

  local mode, two_row, show_labels, show_seeds
  if lane_h >= 100 then
    mode, two_row = "xlarge", true
    show_labels, show_seeds = true, true
  elseif lane_h >= 72 then
    mode, two_row = "tall", false
    show_labels, show_seeds = true, true
  elseif lane_h >= 50 then
    mode, two_row = "medium", false
    show_labels, show_seeds = true, true
  else
    mode, two_row = "compact", false
    show_labels, show_seeds = lane_h >= 34, lane_h >= 42
  end

  local label_h, seed_h, seed_w, v_gap, gap_x, group_gap
  if mode == "xlarge" then
    label_h, seed_h, seed_w, v_gap, gap_x, group_gap = 13.0, 13.0, 15.0, 3.0, 6.0, 16.0
  elseif mode == "tall" then
    label_h, seed_h, seed_w, v_gap, gap_x, group_gap = 12.0, 12.0, 14.0, 2.0, 5.0, 12.0
  elseif mode == "medium" then
    label_h, seed_h, seed_w, v_gap, gap_x, group_gap = 11.0, 11.0, 13.0, 1.0, 4.0, 10.0
  else
    label_h, seed_h, seed_w, v_gap, gap_x, group_gap = 10.0, 10.0, 12.0, 1.0, 3.0, 8.0
  end

  local pad_x, pad_y = 8.0, 3.0
  local panel_x0 = timeline_x0 + 6.0
  local panel_y0 = y0 + 2.0
  local panel_y1 = y1 - 2.0
  local row_h = two_row and ((panel_y1 - panel_y0 - 4.0) * 0.5) or (panel_y1 - panel_y0 - pad_y * 2.0)

  local extra = 0.0
  if show_labels then extra = extra + label_h + v_gap end
  if show_seeds then extra = extra + seed_h + v_gap end
  local knob_size = math.max(14.0, math.min(mode == "xlarge" and 36.0 or (mode == "tall" and 30.0 or (mode == "medium" and 26.0 or 20.0)), row_h - extra))

  local use_short = (mode == "compact")
  local groups = {}

  local function group_width(def)
    local label = use_short and def.short or def.label
    local tw = select(1, r.ImGui_CalcTextSize(ctx, label)) or 16.0
    local seed_row = 0.0
    if show_seeds and def.has_seed then
      seed_row = seed_w
      if def.has_refresh then
        seed_row = seed_w * 2.0 + 2.0
      end
    end
    return math.max(knob_size, show_labels and (tw + 4.0) or 0.0, seed_row)
  end

  local function place_row(ids, row_y0, row_y1)
    local x = panel_x0 + pad_x
    local avail_h = row_y1 - row_y0
    for _, id in ipairs(ids) do
      local def
      for _, d in ipairs(defs) do
        if d.id == id then def = d break end
      end
      local col_w = group_width(def)
      local label_text = use_short and def.short or def.label
      local g = {
        id = def.id,
        label = label_text,
        has_seed = show_seeds and def.has_seed,
        has_refresh = show_seeds and def.has_refresh,
        col_x = x,
        col_w = col_w,
      }
      local stack = knob_size
      if show_labels then stack = stack + v_gap + label_h end
      if g.has_seed then stack = stack + v_gap + seed_h end
      local cursor = row_y0 + math.max(0.0, (avail_h - stack) * 0.5)
      local labels_on_top = (mode == "tall" or mode == "xlarge")

      if show_labels and labels_on_top then
        g.label_x, g.label_y, g.label_w = x, cursor, col_w
        cursor = cursor + label_h + v_gap
      end

      g.knob_x = x + (col_w - knob_size) * 0.5
      g.knob_y = cursor
      cursor = cursor + knob_size

      if show_labels and not labels_on_top then
        cursor = cursor + v_gap
        g.label_x, g.label_y, g.label_w = x, cursor, col_w
        cursor = cursor + label_h
      end

      if g.has_seed or g.has_refresh then
        cursor = cursor + v_gap
        local btn_n = (g.has_seed and 1 or 0) + (g.has_refresh and 1 or 0)
        local row_w = btn_n * seed_w + math.max(0, btn_n - 1) * 2.0
        local bx = x + (col_w - row_w) * 0.5
        if g.has_seed then
          g.seed_x = bx
          g.seed_y = cursor
          bx = bx + seed_w + 2.0
        end
        if g.has_refresh then
          g.refresh_x = bx
          g.refresh_y = cursor
        end
      end

      groups[def.id] = g
      x = x + col_w + group_gap
    end
    return x - group_gap
  end

  local row_right
  if two_row then
    local mid = panel_y0 + (panel_y1 - panel_y0) * 0.5
    local r1 = place_row({ "prob", "human", "vel", "vary" }, panel_y0 + pad_y, mid - 2.0)
    local r2 = place_row({ "stut", "grace", "after" }, mid + 2.0, panel_y1 - pad_y)
    row_right = math.max(r1, r2)
  else
    row_right = place_row({ "prob", "human", "vel", "vary", "stut", "grace", "after" }, panel_y0 + pad_y, panel_y1 - pad_y)
  end

  return {
    mode = mode,
    knob_size = knob_size,
    seed_w = seed_w,
    seed_h = seed_h,
    show_labels = show_labels,
    show_seeds = show_seeds,
    panel_x0 = panel_x0,
    panel_y0 = panel_y0,
    panel_x1 = row_right + pad_x,
    panel_y1 = panel_y1,
    groups = groups,
  }
end

function seq_lane_random_controls_hit(row_pos, mx, my, timeline_x0, clip_y0, clip_y1)
  if not row_pos or not row_pos.row or row_pos.row.type ~= "note" then
    return false
  end
  if seq_random_flyout_hit(mx, my) then
    return true
  end
  if clip_y0 and my < clip_y0 then
    return false
  end
  if clip_y1 and my > clip_y1 then
    return false
  end
  local ui = seq_get_lane_random_layout(row_pos, timeline_x0)
  return mx >= ui.panel_x0 and mx <= ui.panel_x1 and my >= ui.panel_y0 and my <= ui.panel_y1
end

function seq_render_lane_random_controls(dl, row_pos, slot_id, random_settings, focus_key, timeline_x0, clip_y0, clip_y1)
  if clip_y0 and clip_y1 and (row_pos.y1 <= clip_y0 or row_pos.y0 >= clip_y1) then
    return false, nil, nil, nil, false
  end
  local ui = seq_get_lane_random_layout(row_pos, timeline_x0)
  local bg = build_color_rrgbbaa(12, 16, 24, 236)
  local edge = build_color_rrgbbaa(72, 90, 114, 220)
  local clipped = false
  if clip_y0 and clip_y1 and r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(
      dl,
      ui.panel_x0,
      math.max(ui.panel_y0, clip_y0),
      ui.panel_x1,
      math.min(ui.panel_y1, clip_y1),
      true
    )
    clipped = true
  end
  ui_draw_panel(dl, ui.panel_x0, ui.panel_y0, ui.panel_x1, ui.panel_y1, 6.0, bg, edge, false, false)

  local changed = false
  local reseeded = false
  local active_key = nil
  local overlay_text = nil
  local caption_color = UI_THEME.text_dim
  local specs = {
    {
      id = "prob",
      key = "rand_prob_" .. slot_id,
      family = nil,
      value = random_settings.probability or 1.0,
      min_v = 0.0, max_v = 1.0,
      knob_id = "##seq_lane_prob_knob_" .. slot_id,
      seed_id = "##seq_lane_prob_seed_" .. slot_id,
      tooltip = "Chance this hit plays",
      overlay = function(v) return string.format("Prob %.2f", v) end,
      apply = function(v) random_settings.probability = v end,
      reseed = function() random_settings.probability_seed = seq_new_seed() end,
    },
    {
      id = "human",
      key = "rand_human_" .. slot_id,
      family = nil,
      value = random_settings.humanize_ms or 0.0,
      min_v = 0.0, max_v = 50.0,
      knob_id = "##seq_lane_human_knob_" .. slot_id,
      seed_id = "##seq_lane_human_seed_" .. slot_id,
      tooltip = "Timing humanize (ms). Hover for pitch, stretch, length, and early/late range.",
      overlay = function(v) return string.format("Human %.1f ms", v) end,
      apply = function(v) seq_humanize_sync_time_from_knob(random_settings, v) end,
      reseed = function() random_settings.humanize_seed = seq_new_seed() end,
      flyout = "human",
    },
    {
      id = "vel",
      key = "rand_vel_" .. slot_id,
      value = random_settings.humanize_vel or 0.0,
      min_v = 0.0, max_v = 1.0,
      knob_id = "##seq_lane_vel_knob_" .. slot_id,
      seed_id = "##seq_lane_vel_seed_" .. slot_id,
      tooltip = "Velocity humanize amount",
      overlay = function(v) return string.format("Vel %.2f", v) end,
      apply = function(v) random_settings.humanize_vel = v end,
      reseed = function() random_settings.humanize_vel_seed = seq_new_seed() end,
      flyout = "vel",
    },
    {
      id = "vary",
      key = "rand_vary_" .. slot_id,
      value = random_settings.vary_prob or 0.0,
      min_v = 0.0, max_v = 1.0,
      knob_id = "##seq_lane_vary_knob_" .. slot_id,
      seed_id = "##seq_lane_vary_seed_" .. slot_id,
      tooltip = "Chance this hit uses a varied sample",
      overlay = function(v) return string.format("Vary %.2f", v) end,
      apply = function(v) random_settings.vary_prob = v end,
      reseed = function() random_settings.vary_seed = seq_new_seed() end,
      refresh = function() random_settings.vary_swap_seed = seq_new_seed() end,
      flyout = "vary",
    },
    {
      id = "stut",
      key = "rand_stut_" .. slot_id,
      value = random_settings.stutter_prob or 0.0,
      min_v = 0.0, max_v = 1.0,
      knob_id = "##seq_lane_stut_knob_" .. slot_id,
      seed_id = "##seq_lane_stut_seed_" .. slot_id,
      tooltip = "Chance this hit stutters",
      overlay = function(v) return string.format("Stut %.2f", v) end,
      apply = function(v) random_settings.stutter_prob = v end,
      reseed = function() random_settings.stutter_seed = seq_new_seed() end,
      flyout = "stut",
    },
    {
      id = "grace",
      key = "rand_grace_" .. slot_id,
      value = random_settings.ghost_grace or 0.0,
      min_v = 0.0, max_v = 1.0,
      knob_id = "##seq_lane_grace_knob_" .. slot_id,
      seed_id = "##seq_lane_grace_seed_" .. slot_id,
      tooltip = "Chance of a quiet grace note before the hit",
      overlay = function(v) return string.format("Grace %.2f", v) end,
      apply = function(v) random_settings.ghost_grace = v end,
      reseed = function() random_settings.ghost_grace_seed = seq_new_seed() end,
      flyout = "grace",
    },
    {
      id = "after",
      key = "rand_after_" .. slot_id,
      value = random_settings.ghost_after or 0.0,
      min_v = 0.0, max_v = 1.0,
      knob_id = "##seq_lane_after_knob_" .. slot_id,
      seed_id = "##seq_lane_after_seed_" .. slot_id,
      tooltip = "Chance of a quiet note after the hit",
      overlay = function(v) return string.format("After %.2f", v) end,
      apply = function(v) random_settings.ghost_after = v end,
      reseed = function() random_settings.ghost_after_seed = seq_new_seed() end,
      flyout = "after",
    },
  }

  local function widget_in_clip(y, h)
    if not clip_y0 or not clip_y1 then
      return true
    end
    return (y + (h or 0)) > clip_y0 + 0.5 and y < clip_y1 - 0.5
  end

  for _, spec in ipairs(specs) do
    local g = ui.groups[spec.id]
    if g and widget_in_clip(g.knob_y, ui.knob_size) then
      local alpha = seq_random_control_alpha(focus_key, spec.key)
      if g.label_x then
        seq_draw_random_caption(dl, g.label_x, g.label_y, g.label_w, g.label, caption_color)
      end
      local knob_changed, knob_value, knob_active = seq_random_knob_control(
        spec.knob_id, dl, g.knob_x, g.knob_y, ui.knob_size,
        spec.value, spec.min_v, spec.max_v, alpha, spec.flyout and nil or spec.tooltip
      )
      local knob_hovered = r.ImGui_IsItemHovered(ctx)
      if knob_changed then
        spec.apply(knob_value)
        changed = true
      end
      if knob_active then
        active_key = spec.key
        overlay_text = spec.overlay(knob_value or spec.value)
      end
      if spec.flyout and (knob_hovered or knob_active) then
        seq_random_flyout_pin(spec.flyout, slot_id, {
          x = g.knob_x, y = g.knob_y, w = ui.knob_size, h = ui.knob_size,
          label_y = g.label_y,
        }, "lane")
      end
      if g.has_seed and g.seed_x then
        if seq_random_seed_button(spec.seed_id, dl, g.seed_x, g.seed_y, ui.seed_w, ui.seed_h, alpha) then
          if seq_apply_reseed_with_undo(spec.reseed) then
            reseeded = true
          else
            changed = true
          end
        end
      end
      if g.has_refresh and g.refresh_x and spec.refresh then
        if seq_random_refresh_button(spec.knob_id .. "_refresh", dl, g.refresh_x, g.refresh_y, ui.seed_w, ui.seed_h, alpha) then
          if seq_apply_reseed_with_undo(spec.refresh) then
            reseeded = true
          else
            changed = true
          end
        end
      end
    end
  end

  if clipped and r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
  return changed, active_key, overlay_text, ui.panel_x1, reseeded
end

SEQ_RANDOM_POPUP_DELAY = 0.34
SEQ_RANDOM_FLYOUT_HOLD = 0.12
SEQ_RANDOM_LABEL_H = 14.0
SEQ_RANDOM_CHIPS_MAX_FRAC = 0.40

function seq_region_random_chip_width(text, pad_x)
  local tw = select(1, r.ImGui_CalcTextSize(ctx, text)) or 8.0
  return math.max(12.0, tw + (pad_x or 4.0) * 2.0)
end

function seq_region_random_label_layout(rx0, rx1, y0, region_lane_h, has_prob, has_human, has_vel, has_vary, has_stut, has_ghost, has_grace, has_after)
  local labels = {}
  has_grace = has_grace or false
  has_after = has_after or false
  if has_ghost and not has_grace and not has_after then
    has_grace, has_after = true, true
  end
  if not has_prob and not has_human and not has_vel and not has_vary and not has_stut and not has_grace and not has_after then
    return labels
  end
  local vis_w = (rx1 or 0) - (rx0 or 0)
  if vis_w < 18.0 then
    return labels
  end
  local chip_h = math.min(SEQ_RANDOM_LABEL_H, math.max(11.0, (region_lane_h or 22.0) - 8.0))
  local chip_y = y0 + ((region_lane_h or 22.0) - chip_h) * 0.5
  local use_full = vis_w >= 200.0
  local pad_x = 4.0
  local gap = 3.0
  local x = rx1 - 7.0
  local min_x = (rx0 or 0) + 4.0

  local specs = {}
  if has_prob then specs[#specs + 1] = { kind = "prob", full = "Prob", short = "P" } end
  if has_human then specs[#specs + 1] = { kind = "human", full = "Hum", short = "H" } end
  if has_vel then specs[#specs + 1] = { kind = "vel", full = "Vel", short = "V" } end
  if has_vary then specs[#specs + 1] = { kind = "vary", full = "Vary", short = "Y" } end
  if has_stut then specs[#specs + 1] = { kind = "stut", full = "Stut", short = "S" } end
  if has_grace then specs[#specs + 1] = { kind = "grace", full = "Grace", short = "G" } end
  if has_after then specs[#specs + 1] = { kind = "after", full = "After", short = "A" } end

  local function chips_width(full)
    local w = 0.0
    for i, spec in ipairs(specs) do
      w = w + seq_region_random_chip_width(full and spec.full or spec.short, pad_x)
      if i < #specs then
        w = w + gap
      end
    end
    return w
  end

  -- Collapse to one control when even the compact chips eat too much of the region.
  local collapse = #specs > 1 and (chips_width(false) / vis_w) > SEQ_RANDOM_CHIPS_MAX_FRAC
  if collapse then
    use_full = vis_w >= 52.0
    specs = { { kind = "all", full = "Rand", short = "R" } }
  elseif use_full and (chips_width(true) / vis_w) > SEQ_RANDOM_CHIPS_MAX_FRAC then
    use_full = false
  end

  local function add_label(kind, text)
    local w = seq_region_random_chip_width(text, pad_x)
    if x - w < min_x then
      return false
    end
    x = x - w
    labels[#labels + 1] = {
      kind = kind,
      text = text,
      x0 = x,
      y0 = chip_y,
      x1 = x + w,
      y1 = chip_y + chip_h,
    }
    x = x - gap
    return true
  end

  -- Right-to-left so After sits on the far right. Stop when a chip would
  -- leave the visible region (e.g. after horizontal scroll clips the left).
  for i = #specs, 1, -1 do
    local spec = specs[i]
    if not add_label(spec.kind, use_full and spec.full or spec.short) then
      break
    end
  end
  local ordered = {}
  for i = #labels, 1, -1 do
    ordered[#ordered + 1] = labels[i]
  end
  return ordered
end

function seq_draw_region_random_labels(dl, labels, mx, my)
  if not labels or #labels == 0 then
    return
  end
  for _, lab in ipairs(labels) do
    local hovered = mx >= lab.x0 and mx <= lab.x1 and my >= lab.y0 and my <= lab.y1
    local fill, edge, text
    if lab.kind == "all" then
      fill = hovered and 0xF2C15AFF or 0xC8942EEE
      edge = hovered and 0xFFF4D0FF or 0xF0D090CC
      text = 0x1A1208FF
    elseif lab.kind == "prob" then
      fill = hovered and 0x4EC4D8FF or 0x2A8A9CEE
      edge = hovered and 0xD8F6FFFF or 0x8ED4E8CC
      text = 0xFFFFFFFF
    elseif lab.kind == "vel" then
      fill = hovered and 0x7EE0A8FF or 0x3CAA6EEE
      edge = hovered and 0xD8FFE8FF or 0x8ED4A8CC
      text = 0x0A180CFF
    elseif lab.kind == "vary" then
      fill = hovered and 0x9FE88FFF or 0x4CAA5EEE
      edge = hovered and 0xD8FFD0FF or 0x8ED48CCC
      text = 0x0A180CFF
    elseif lab.kind == "stut" then
      fill = hovered and 0xD0B8FFFF or 0x8A68C8EE
      edge = hovered and 0xF0E4FFFF or 0xC9A8FFCC
      text = 0x140C20FF
    elseif lab.kind == "grace" then
      fill = hovered and 0xD4DCE8FF or 0x8A96A8EE
      edge = hovered and 0xF0F4FAFF or 0xC4CCD8CC
      text = 0x10141CFF
    elseif lab.kind == "after" then
      fill = hovered and 0xC8D4E8FF or 0x6E7E96EE
      edge = hovered and 0xE8F0FAFF or 0xB0BCC8CC
      text = 0x10141CFF
    else
      fill = hovered and 0xF0C86AFF or 0xC4A04AEE
      edge = hovered and 0xFFF3C8FF or 0xE8D090CC
      text = 0x1A1208FF
    end
    r.ImGui_DrawList_AddRectFilled(dl, lab.x0, lab.y0, lab.x1, lab.y1, fill, 3.0)
    r.ImGui_DrawList_AddRect(dl, lab.x0, lab.y0, lab.x1, lab.y1, edge, 3.0, 0, 1.0)
    local tw, th = r.ImGui_CalcTextSize(ctx, lab.text)
    r.ImGui_DrawList_AddText(
      dl,
      lab.x0 + (lab.x1 - lab.x0 - (tw or 8)) * 0.5,
      lab.y0 + (lab.y1 - lab.y0 - (th or 12)) * 0.5,
      text,
      lab.text
    )
  end
end

function seq_find_track_slot_by_id(track_id)
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot.id == track_id then
      return slot
    end
  end
  return nil
end

function seq_open_region_random_popup(region, snapshot)
  if not region then
    return
  end
  state.seq_random_popup_region_id = region.id
  state.seq_random_popup_snapshot = snapshot or seq_snapshot_region_random_popup(region)
  state.seq_random_popup_pending = nil
  state.seq_random_popup_close = false
  if not state.seq_random_popup_snapshot or #state.seq_random_popup_snapshot == 0 then
    return
  end
  r.ImGui_OpenPopup(ctx, "seq_region_random_popup")
end

function seq_random_flyout_now()
  return (r.time_precise and r.time_precise()) or os.clock()
end

function seq_random_flyout_begin_frame(host)
  local f = state.seq_random_flyout
  if f and ((not host) or f.host == host) then
    f.pinned = false
  end
end

function seq_random_flyout_pin(kind, slot_id, anchor, host)
  if not kind or not slot_id then
    return
  end
  local f = state.seq_random_flyout
  if (not f) or f.kind ~= kind or f.slot_id ~= slot_id then
    f = { kind = kind, slot_id = slot_id }
    state.seq_random_flyout = f
  end
  f.kind = kind
  f.slot_id = slot_id
  f.anchor = anchor or f.anchor
  f.host = host or f.host or "lane"
  f.hold_until = nil
  f.pinned = true
  if not f.rect then
    local fw, fh = seq_random_flyout_size(kind)
    local rx0, ry0, rx1, ry1 = seq_random_flyout_place(anchor or f.anchor, fw, fh)
    f.rect = { x0 = rx0, y0 = ry0, x1 = rx1, y1 = ry1 }
  end
end

function seq_random_flyout_hit(mx, my)
  local f = state.seq_random_flyout
  local rect = f and f.rect
  if not rect or not mx or not my then
    return false
  end
  local pad = 2.0
  return mx >= rect.x0 - pad and mx <= rect.x1 + pad and my >= rect.y0 - pad and my <= rect.y1 + pad
end

function seq_random_flyout_size(kind, settings)
  if kind == "human" then
    local rows = 4
    if settings and seq_settings_humanize_len_active(settings) then
      rows = 5
    end
    return 196.0, rows * 20.0 + (rows - 1) * 1.0 + 2.0
  end
  if kind == "grace" or kind == "after" then
    return 176.0, 85.0
  end
  if kind == "stut" then
    return 176.0, 41.0
  end
  -- Keep this at ImGui's default min window height so a transparent overlay
  -- cannot be inflated downward over Vel/Vary when labels sit below the knobs.
  return 168.0, 32.0
end

function seq_random_flyout_place(anchor, w, h)
  local gap = 3.0
  local ax = (anchor and anchor.x) or 0.0
  local ay = (anchor and anchor.y) or 0.0
  local aw = (anchor and anchor.w) or 24.0
  local ah = (anchor and anchor.h) or aw
  local x0 = ax + aw * 0.5 - w * 0.5
  -- Sit on the label row when labels are above the knob; otherwise on the knob top.
  local label_y = anchor and anchor.label_y
  local above_bottom = ay
  if type(label_y) == "number" and label_y < ay then
    above_bottom = label_y
  end
  local y_above = above_bottom - gap - h
  local y_below = ay + ah + gap

  local win_x, win_y = r.ImGui_GetWindowPos(ctx)
  local win_w, win_h = r.ImGui_GetWindowSize(ctx)
  win_x, win_y = win_x or 0.0, win_y or 0.0
  win_w, win_h = win_w or 800.0, win_h or 600.0

  -- ImGui clamps top-level overlay windows to the host viewport. If we ask
  -- for a rect above the first-lane knobs at low zoom, that clamp slides the
  -- (transparent) window down over V/Y and eats their upper-half drags.
  local top_limit = win_y + 4.0
  local wr = state.main_window_rect
  if wr and wr.y then
    top_limit = math.max(top_limit, wr.y + 4.0)
  end
  local map = state.seq_map_rect
  if map and map.y then
    top_limit = math.max(top_limit, (map.y or 0) + 2.0)
  end

  local y0 = y_above
  local force_below = (anchor and anchor.force_below) or (state.seq_random_flyout and state.seq_random_flyout.force_below)
  if force_below then
    y0 = y_below
  elseif y_above < top_limit then
    y0 = y_below
  end

  if x0 < win_x + 6.0 then
    x0 = win_x + 6.0
  end
  if x0 + w > win_x + win_w - 6.0 then
    x0 = win_x + win_w - 6.0 - w
  end
  return x0, y0, x0 + w, y0 + h
end

function seq_render_random_flyout_body(dl, kind, settings, id_prefix, x, y, w)
  local gap = 1.0
  local row_h = 22.0
  local knob_sz = 20.0
  local cy = y
  local changed = false
  local active_any = false

  if kind == "human" then
    local p_lo, p_hi = seq_normalize_range(settings.humanize_pitch_min or 0.0, settings.humanize_pitch_max or 0.0, -SEQ_PITCH_HUMANIZE, SEQ_PITCH_HUMANIZE)
    local pch, nplo, nphi, pa = seq_random_range_control(
      id_prefix .. "_pitch", dl, x, cy, w, 20.0,
      p_lo, p_hi, -SEQ_PITCH_HUMANIZE, SEQ_PITCH_HUMANIZE, 210,
      {
        caption = "Pitch",
        step = 0.05,
        format = seq_format_pitch_range,
        to_norm = seq_pitch_range_to_norm,
        from_norm = seq_pitch_range_from_norm,
        reset_lo = 0.0,
        reset_hi = 0.0,
        tooltip = "Pitch randomization in semitones. Center is finer; larger shifts sit toward the edges. Right-click to reset.",
      }
    )
    if pch then settings.humanize_pitch_min, settings.humanize_pitch_max = nplo, nphi changed = true end
    if pa then active_any = true end
    cy = cy + 20.0 + gap

    local s_lo, s_hi = seq_normalize_range(settings.humanize_stretch_min or 1.0, settings.humanize_stretch_max or 1.0, 0.5, 2.0)
    local sch, nslo, nshi, sa = seq_random_range_control(
      id_prefix .. "_stretch", dl, x, cy, w, 20.0,
      s_lo, s_hi, 0.5, 2.0, 210,
      {
        caption = "Strch",
        format = seq_format_stretch_range,
        reset_lo = 1.0,
        reset_hi = 1.0,
        tooltip = "Stretch randomization. Drag an edge for a range. Right-click to reset.",
      }
    )
    if sch then settings.humanize_stretch_min, settings.humanize_stretch_max = nslo, nshi changed = true end
    if sa then active_any = true end
    cy = cy + 20.0 + gap

    local t_lo, t_hi = seq_humanize_time_ms_range(settings)
    local tch, ntlo, nthi, ta = seq_random_range_control(
      id_prefix .. "_time", dl, x, cy, w, 20.0,
      t_lo, t_hi, -SEQ_HUMANIZE_TIME_MS, SEQ_HUMANIZE_TIME_MS, 210,
      {
        caption = "Time",
        step = 1,
        format = seq_format_time_ms_range,
        reset_lo = 0.0,
        reset_hi = 0.0,
        tooltip = "Timing window in ms. Left is early, right is late (up to 500 ms). Right-click to reset.",
      }
    )
    if tch then
      settings.humanize_time_min, settings.humanize_time_max = ntlo, nthi
      settings.humanize_time_is_ms = true
      if math.abs(ntlo) < 0.05 and math.abs(nthi) < 0.05 then
        settings.humanize_ms = 0.0
      end
      changed = true
    end
    if ta then active_any = true end
    cy = cy + 20.0 + gap

    local l_lo, l_hi = seq_normalize_range(settings.humanize_len_min or 1.0, settings.humanize_len_max or 1.0, SEQ_HUMANIZE_LEN_MIN, 1.0)
    local lch, nllo, nlhi, la = seq_random_range_control(
      id_prefix .. "_len", dl, x, cy, w, 20.0,
      l_lo, l_hi, SEQ_HUMANIZE_LEN_MIN, 1.0, 210,
      {
        caption = "Len",
        format = seq_format_len_range,
        reset_lo = 1.0,
        reset_hi = 1.0,
        tooltip = "Length shortening. Items can only get shorter. Drag an edge for a range. Right-click to reset.",
      }
    )
    if lch then settings.humanize_len_min, settings.humanize_len_max = nllo, nlhi changed = true end
    if la then active_any = true end
    cy = cy + 20.0

    if seq_settings_humanize_len_active(settings) then
      cy = cy + gap
      local f_lo, f_hi = seq_normalize_range(settings.humanize_fade_min or 0.0, settings.humanize_fade_max or 0.0, 0.0, SEQ_HUMANIZE_FADE_MS)
      local fch, nflo, nfhi, fa = seq_random_range_control(
        id_prefix .. "_fade", dl, x, cy, w, 20.0,
        f_lo, f_hi, 0.0, SEQ_HUMANIZE_FADE_MS, 210,
        {
          caption = "Fade",
          step = 1,
          format = seq_format_fade_ms_range,
          reset_lo = 0.0,
          reset_hi = 0.0,
          tooltip = "Fade-out window in ms on shortened hits. Drag an edge for a range. Right-click to reset.",
        }
      )
      if fch then settings.humanize_fade_min, settings.humanize_fade_max = nflo, nfhi changed = true end
      if fa then active_any = true end
      cy = cy + 20.0
    end
  end

  if kind == "vel" or kind == "vary" or kind == "stut" or kind == "grace" or kind == "after" then
    local beat_key = (kind == "vel" and "humanize_vel_beat")
      or (kind == "vary" and "vary_beat")
      or (kind == "stut" and "stutter_beat")
      or (kind == "after" and "ghost_after_beat")
      or "ghost_grace_beat"
    local bc, bv, ba = seq_random_beat_drag(
      id_prefix .. "_beat", dl, x, cy, w, 20.0,
      settings[beat_key] or 0.0, 210,
      "Favor this on downbeats or upbeats"
    )
    if bc then settings[beat_key] = bv changed = true end
    if ba then active_any = true end
    cy = cy + 20.0 + gap
  end

  if kind == "stut" then
    local st_lo, st_hi = seq_normalize_range(settings.stutter_min or 2, settings.stutter_max or 4, 2, 16)
    local st_ch, nlo, nhi, st_a = seq_random_range_control(
      id_prefix .. "_hits", dl, x, cy, w, 20.0,
      st_lo, st_hi, 2, 16, 210,
      {
        caption = "Hits",
        step = 1,
        format = seq_format_stutter_range,
        reset_lo = 2,
        reset_hi = 4,
        tooltip = "Min and max stutter hits. Drag an edge for a range. Right-click to reset.",
      }
    )
    if st_ch then settings.stutter_min, settings.stutter_max = nlo, nhi changed = true end
    if st_a then active_any = true end
    cy = cy + 20.0
  elseif kind == "grace" or kind == "after" then
    local keys = seq_ghost_which_keys(kind)
    local clo, chi = seq_ghost_close_range(settings, kind)
    local cch, nclo, nchi, ca = seq_random_range_control(
      id_prefix .. "_close", dl, x, cy, w, 20.0,
      clo, chi, SEQ_GHOST_CLOSE_MIN, SEQ_GHOST_CLOSE_MAX, 210,
      {
        caption = "Close",
        reset_lo = 0.0625,
        reset_hi = 0.125,
        tooltip = "How close this note sits. Drag an edge for a range. Right-click to reset. Snap to musical values; hold Shift for free values.",
        format = seq_format_close_range,
        snap = seq_snap_close_qn,
        shift_free = true,
      }
    )
    if cch then settings[keys.close_min], settings[keys.close_max] = nclo, nchi changed = true end
    if ca then active_any = true end
    cy = cy + 20.0 + gap
    local vlo, vhi = seq_ghost_vol_range(settings, kind)
    local vch_r, nvlo, nvhi, vra = seq_random_range_control(
      id_prefix .. "_vol", dl, x, cy, w, 20.0,
      vlo, vhi, 0.0, 1.0, 210,
      {
        caption = "Vol",
        reset_lo = 0.20,
        reset_hi = 0.40,
        tooltip = "Ghost note volume as a range of the parent note. Drag an edge for a range. Right-click to reset.",
        format = seq_format_vol_range,
      }
    )
    if vch_r then settings[keys.vol_min], settings[keys.vol_max] = nvlo, nvhi changed = true end
    if vra then active_any = true end
    cy = cy + 20.0 + gap
    local vch, vv, va = seq_random_knob_control(
      id_prefix .. "_vary", dl, x, cy, knob_sz,
      settings[keys.vary] or 0.0, 0.0, 1.0, 210,
      "Chance this extra note uses a different sample",
      { caption = "Vary", w = w, h = row_h }
    )
    if vch then settings[keys.vary] = vv changed = true end
    if va then active_any = true end
    cy = cy + row_h
  end

  return changed, active_any, cy - y
end

function seq_render_random_flyout(dl, pattern, host)
  local f = state.seq_random_flyout
  if not f then
    return false
  end
  if host and f.host and f.host ~= host then
    return false
  end
  local now = seq_random_flyout_now()
  if (not f.pinned) and f.hold_until and now >= f.hold_until then
    state.seq_random_flyout = nil
    return false
  end
  local slot = seq_find_track_slot_by_id(f.slot_id)
  local settings = slot and get_seq_track_settings(pattern, slot.id, true)
  if not slot or not settings then
    state.seq_random_flyout = nil
    return false
  end

  local w, h = seq_random_flyout_size(f.kind, settings)
  local x0, y0, x1, y1 = seq_random_flyout_place(f.anchor, w, h)
  f.rect = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }

  local win_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    win_flags = win_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  if r.ImGui_WindowFlags_NoBackground then
    win_flags = win_flags | r.ImGui_WindowFlags_NoBackground()
  end
  if r.ImGui_WindowFlags_NoTitleBar then
    win_flags = win_flags | r.ImGui_WindowFlags_NoTitleBar()
  end
  if r.ImGui_WindowFlags_NoResize then
    win_flags = win_flags | r.ImGui_WindowFlags_NoResize()
  end
  if r.ImGui_WindowFlags_NoMove then
    win_flags = win_flags | r.ImGui_WindowFlags_NoMove()
  end
  if r.ImGui_WindowFlags_NoSavedSettings then
    win_flags = win_flags | r.ImGui_WindowFlags_NoSavedSettings()
  end
  if r.ImGui_WindowFlags_NoFocusOnAppearing then
    win_flags = win_flags | r.ImGui_WindowFlags_NoFocusOnAppearing()
  end
  if r.ImGui_WindowFlags_NoNav then
    win_flags = win_flags | r.ImGui_WindowFlags_NoNav()
  end

  local mx, my = r.ImGui_GetMousePos(ctx)
  local hover = mx and my and mx >= x0 and mx <= x1 and my >= y0 and my <= y1
  local changed, active = false, false
  local body_id = "##seq_rand_fly_" .. f.kind .. "_" .. tostring(f.slot_id) .. "_" .. (f.host or "lane")
  local use_overlay = (f.host or host) ~= "popup"
  local style_vars = 0

  local function push_flyout_window_style()
    if r.ImGui_StyleVar_WindowPadding then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
      style_vars = style_vars + 1
    end
    if r.ImGui_StyleVar_WindowBorderSize then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
      style_vars = style_vars + 1
    end
    -- Default min size is ~32px. Vel/Vary extras are 22px; the extra invisible
    -- strip was covering the upper half of those knobs at compact lane zoom.
    if r.ImGui_StyleVar_WindowMinSize then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowMinSize(), 1.0, 1.0)
      style_vars = style_vars + 1
    end
  end

  if use_overlay and r.ImGui_SetNextWindowPos and r.ImGui_Begin then
    -- Top-level overlay: the tracks child steals parent hits on every lane
    -- except the first (whose extras overlap the ruler).
    local cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
    r.ImGui_SetNextWindowPos(ctx, x0, y0, cond)
    if r.ImGui_SetNextWindowSize then
      r.ImGui_SetNextWindowSize(ctx, w, h, cond)
    end
    if r.ImGui_SetNextWindowBgAlpha then
      r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
    end
    push_flyout_window_style()
    local visible = r.ImGui_Begin(ctx, "##seq_rand_flyout_overlay", true, win_flags)
    local fdl = (r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx))
      or (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx))
      or dl
    if visible then
      local wx, wy = r.ImGui_GetWindowPos(ctx)
      local ww, wh = r.ImGui_GetWindowSize(ctx)
      if wx and wy then
        x0, y0 = wx, wy
        x1 = wx + (ww or w)
        y1 = wy + (wh or h)
        f.rect = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
      end
      local a = f.anchor
      if a and y1 > (a.y or y1) - 1.0 and y0 < (a.y or 0) + (a.h or 0) then
        f.force_below = true
      end
      changed, active = seq_render_random_flyout_body(fdl, f.kind, settings, body_id, x0, y0, w)
      r.ImGui_End(ctx)
    end
    if style_vars > 0 then
      r.ImGui_PopStyleVar(ctx, style_vars)
    end
  else
    push_flyout_window_style()
    r.ImGui_SetCursorScreenPos(ctx, x0, y0)
    local child_open = r.ImGui_BeginChild(ctx, "##seq_rand_flyout_hit", w, h, 0, win_flags)
    local fdl = (r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx))
      or (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx))
      or dl
    if child_open then
      changed, active = seq_render_random_flyout_body(fdl, f.kind, settings, body_id, x0, y0, w)
    end
    imgui_end_child(child_open)
    if style_vars > 0 then
      r.ImGui_PopStyleVar(ctx, style_vars)
    end
  end
  hover = mx and my and mx >= x0 and mx <= x1 and my >= y0 and my <= y1
  local over_knob = false
  local a = f.anchor
  if a and mx and my then
    local ax0, ay0 = a.x or 0.0, a.y or 0.0
    local ax1 = ax0 + (a.w or 0.0)
    local ay1 = ay0 + (a.h or 0.0)
    over_knob = mx >= ax0 and mx <= ax1 and my >= ay0 and my <= ay1
  end
  -- Only the extras panel and its own knob. A union bbox is as wide as Human
  -- extras and would keep that overlay parked over Vel/Vary.
  local near = hover or over_knob
  if (not near) and mx and my then
    local pad = 8.0
    near = (mx >= x0 - pad and mx <= x1 + pad and my >= y0 - pad and my <= y1 + pad)
      or over_knob
  end
  if hover or over_knob or active or f.pinned then
    f.hold_until = nil
    f.pinned = true
  elseif not near then
    state.seq_random_flyout = nil
  elseif not f.hold_until then
    f.hold_until = now + SEQ_RANDOM_FLYOUT_HOLD
  end
  return changed
end

function seq_handle_region_random_label_click(region, kind)
  if not region then
    return
  end
  seq_select_region(region)
  if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    state.seq_random_popup_pending = nil
    state.seq_random_popup_close = true
    local undo_label = "Reset sequencer humanize"
    if kind == "all" then
      undo_label = "Reset sequencer randomization"
    elseif kind == "prob" then
      undo_label = "Reset sequencer probability"
    elseif kind == "vel" then
      undo_label = "Reset sequencer velocity humanize"
    elseif kind == "vary" then
      undo_label = "Reset sequencer sample variation"
    elseif kind == "stut" then
      undo_label = "Reset sequencer stutter probability"
    elseif kind == "ghost" then
      undo_label = "Reset sequencer ghost notes"
    elseif kind == "grace" then
      undo_label = "Reset sequencer grace notes"
    elseif kind == "after" then
      undo_label = "Reset sequencer after notes"
    end
    local label = begin_seq_undo(undo_label)
    if seq_reset_region_random_settings(region, kind) then
      save_config()
      sync_seq_pattern_regions(region.pattern_id)
    end
    end_seq_undo(label)
  else
    local now = r.time_precise and r.time_precise() or os.clock()
    state.seq_random_popup_pending = {
      region_id = region.id,
      kind = kind,
      time = now,
      snapshot = seq_snapshot_region_random_popup(region),
    }
  end
end

function render_seq_region_random_popup()
  local pending = state.seq_random_popup_pending
  if pending then
    local now = r.time_precise and r.time_precise() or os.clock()
    if (now - (pending.time or now)) >= SEQ_RANDOM_POPUP_DELAY then
      local region = get_seq_region_by_id(pending.region_id)
      if region then
        seq_open_region_random_popup(region, pending.snapshot)
      else
        state.seq_random_popup_pending = nil
      end
    end
  end

  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  if r.ImGui_WindowFlags_AlwaysAutoResize then flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize() end

  local style_colors = 0
  local style_vars = 0
  if r.ImGui_Col_PopupBg then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), UI_THEME.popup_bg)
    style_colors = style_colors + 1
  end
  if r.ImGui_Col_Border then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), UI_THEME.border)
    style_colors = style_colors + 1
  end
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    style_vars = style_vars + 1
  end

  local function pop_random_popup_style()
    if style_vars > 0 then r.ImGui_PopStyleVar(ctx, style_vars) end
    if style_colors > 0 then r.ImGui_PopStyleColor(ctx, style_colors) end
  end

  local open = r.ImGui_BeginPopup(ctx, "seq_region_random_popup", flags)
  if not open then
    pop_random_popup_style()
    if not state.seq_random_popup_pending then
      if state.seq_random_popup_region_id then
        state.seq_random_knob_drag = nil
        seq_flush_pending_random_sync()
      end
      state.seq_random_popup_region_id = nil
      state.seq_random_popup_snapshot = nil
      state.seq_random_popup_close = false
      state.seq_random_popup_active_key = nil
    end
    if state.seq_random_flyout and state.seq_random_flyout.host == "popup" then
      state.seq_random_flyout = nil
    end
    return
  end

  if state.seq_random_popup_close then
    state.seq_random_popup_close = false
    r.ImGui_CloseCurrentPopup(ctx)
    r.ImGui_EndPopup(ctx)
    pop_random_popup_style()
    state.seq_random_popup_region_id = nil
    state.seq_random_popup_snapshot = nil
    state.seq_random_popup_active_key = nil
    return
  end

  local region = get_seq_region_by_id(state.seq_random_popup_region_id)
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  if not region or not pattern then
    r.ImGui_CloseCurrentPopup(ctx)
    r.ImGui_EndPopup(ctx)
    pop_random_popup_style()
    state.seq_random_popup_region_id = nil
    state.seq_random_popup_snapshot = nil
    state.seq_random_popup_active_key = nil
    return
  end

  local live_entries = seq_collect_region_random_entries(region)
  local snapshot = state.seq_random_popup_snapshot or {}
  local seen = {}
  local rows = {}
  for _, snap in ipairs(snapshot) do
    seen[snap.track_id] = true
    local slot = seq_find_track_slot_by_id(snap.track_id)
    local settings = slot and get_seq_track_settings(pattern, slot.id, true)
    if slot and settings then
      rows[#rows + 1] = {
        slot = slot,
        settings = settings,
        show_prob = snap.show_prob,
        show_human = snap.show_human,
        show_vel = snap.show_vel,
        show_vary = snap.show_vary,
        show_stut = snap.show_stut,
        show_grace = snap.show_grace or snap.show_ghost,
        show_after = snap.show_after or snap.show_ghost,
        show_ghost = snap.show_ghost,
      }
    end
  end
  for _, entry in ipairs(live_entries) do
    if not seen[entry.slot.id] then
      rows[#rows + 1] = entry
    else
      for _, row in ipairs(rows) do
        if row.slot.id == entry.slot.id then
          row.show_prob = row.show_prob or entry.show_prob
          row.show_human = row.show_human or entry.show_human
          row.show_vel = row.show_vel or entry.show_vel
          row.show_vary = row.show_vary or entry.show_vary
          row.show_stut = row.show_stut or entry.show_stut
          row.show_grace = row.show_grace or entry.show_grace
          row.show_after = row.show_after or entry.show_after
          row.show_ghost = row.show_ghost or entry.show_ghost
          break
        end
      end
    end
  end

  if #rows == 0 then
    r.ImGui_CloseCurrentPopup(ctx)
    r.ImGui_EndPopup(ctx)
    pop_random_popup_style()
    state.seq_random_popup_region_id = nil
    state.seq_random_popup_snapshot = nil
    state.seq_random_popup_active_key = nil
    return
  end

  local pad = 10.0
  local name_h = 16.0
  local caption_h = 13.0
  local knob_size = 28.0
  local seed_h = 13.0
  local seed_w = 15.0
  local value_h = 13.0
  local stack_h = caption_h + 2.0 + knob_size + 2.0 + seed_h + 2.0 + value_h
  local col_w = 54.0
  local col_gap = 10.0
  local track_gap = 10.0
  local popup_dl = r.ImGui_GetWindowDrawList(ctx)
  local origin_x, origin_y = r.ImGui_GetCursorScreenPos(ctx)
  local focus_key = state.seq_random_popup_active_key
  local next_focus = nil
  local content_w = 80.0
  local content_h = pad
  local changed_any = false
  seq_random_flyout_begin_frame("popup")

  for _, row in ipairs(rows) do
    local cols = (row.show_prob and 1 or 0) + (row.show_human and 1 or 0)
      + (row.show_vel and 1 or 0) + (row.show_vary and 1 or 0)       + (row.show_stut and 1 or 0)
      + (row.show_grace and 1 or 0)
      + (row.show_after and 1 or 0)
    if cols < 1 then cols = 1 end
    local name = row.slot.name or ("Track " .. tostring(row.slot.id))
    local name_w = select(1, r.ImGui_CalcTextSize(ctx, name)) or 40.0
    local row_w = math.max(name_w, cols * col_w + math.max(0, cols - 1) * col_gap)
    content_w = math.max(content_w, row_w)
    content_h = content_h + name_h + stack_h + track_gap
  end
  content_h = content_h - track_gap + pad
  content_w = content_w + pad * 2.0

  local y = origin_y + pad
  for row_idx, row in ipairs(rows) do
    local name = row.slot.name or ("Track " .. tostring(row.slot.id))
    r.ImGui_DrawList_AddText(popup_dl, origin_x + pad, y, UI_THEME.text, name)
    y = y + name_h
    local x = origin_x + pad
    local row_changed = false
    local function apply_seed(reseed_fn)
      if seq_apply_reseed_with_undo(reseed_fn) then
        seq_queue_random_sync(region.pattern_id, row.slot.id)
      else
        row_changed = true
      end
    end
    local function render_column(control_key, caption, value_fmt, value, min_v, max_v, knob_id, seed_id, related, flyout_kind, refresh_id)
      local alpha = seq_random_control_alpha(focus_key, control_key, related)
      r.ImGui_DrawList_AddText(popup_dl, x + (col_w - (select(1, r.ImGui_CalcTextSize(ctx, caption)) or 20)) * 0.5, y, UI_THEME.text_dim, caption)
      local knob_x = x + (col_w - knob_size) * 0.5
      local knob_y = y + caption_h + 2.0
      local changed, new_value, active = seq_random_knob_control(
        knob_id, popup_dl, knob_x, knob_y, knob_size, value, min_v, max_v, alpha
      )
      local hovered = r.ImGui_IsItemHovered(ctx)
      if flyout_kind and (hovered or active) then
        seq_random_flyout_pin(flyout_kind, row.slot.id, {
          x = knob_x, y = knob_y, w = knob_size, h = knob_size,
          label_y = y,
        }, "popup")
      end
      local seed_y = knob_y + knob_size + 2.0
      local seed_clicked = false
      local refresh_clicked = false
      local btn_n = (seed_id and 1 or 0) + (refresh_id and 1 or 0)
      local row_w = btn_n * seed_w + math.max(0, btn_n - 1) * 2.0
      local bx = x + (col_w - row_w) * 0.5
      if seed_id then
        seed_clicked = seq_random_seed_button(seed_id, popup_dl, bx, seed_y, seed_w, seed_h, alpha)
        bx = bx + seed_w + 2.0
      end
      if refresh_id then
        refresh_clicked = seq_random_refresh_button(refresh_id, popup_dl, bx, seed_y, seed_w, seed_h, alpha)
      end
      local value_text
      if type(value_fmt) == "function" then
        value_text = value_fmt(new_value or value)
      else
        value_text = string.format(value_fmt, new_value or value)
      end
      r.ImGui_DrawList_AddText(
        popup_dl,
        x + (col_w - (select(1, r.ImGui_CalcTextSize(ctx, value_text)) or 20)) * 0.5,
        seed_y + seed_h + 2.0,
        0xFFE7A6DD,
        value_text
      )
      if active then
        next_focus = control_key
      end
      return changed, new_value, seed_clicked, refresh_clicked
    end

    if row.show_prob then
      local prob_changed, prob_value, prob_seed = render_column(
        "popup_prob_" .. row.slot.id,
        "Prob",
        "%.2f",
        row.settings.probability or 1.0,
        0.0,
        1.0,
        "##seq_popup_prob_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_prob_seed_" .. region.id .. "_" .. row.slot.id
      )
      if prob_changed then
        row.settings.probability = prob_value
        row_changed = true
      end
      if prob_seed then
        apply_seed(function() row.settings.probability_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end
    if row.show_human then
      local human_changed, human_value, human_seed = render_column(
        "popup_human_" .. row.slot.id,
        "Hum",
        "%.1f ms",
        row.settings.humanize_ms or 0.0,
        0.0,
        50.0,
        "##seq_popup_human_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_human_seed_" .. region.id .. "_" .. row.slot.id,
        nil,
        "human"
      )
      if human_changed then
        seq_humanize_sync_time_from_knob(row.settings, human_value)
        row_changed = true
      end
      if human_seed then
        apply_seed(function() row.settings.humanize_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end
    if row.show_vel then
      local vel_changed, vel_value, vel_seed = render_column(
        "popup_vel_" .. row.slot.id,
        "Vel",
        "%.2f",
        row.settings.humanize_vel or 0.0,
        0.0,
        1.0,
        "##seq_popup_vel_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_vel_seed_" .. region.id .. "_" .. row.slot.id,
        nil,
        "vel"
      )
      if vel_changed then
        row.settings.humanize_vel = vel_value
        row_changed = true
      end
      if vel_seed then
        apply_seed(function() row.settings.humanize_vel_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end
    if row.show_vary then
      local vary_changed, vary_value, vary_seed, vary_refresh = render_column(
        "popup_vary_" .. row.slot.id,
        "Vary",
        "%.2f",
        row.settings.vary_prob or 0.0,
        0.0,
        1.0,
        "##seq_popup_vary_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_vary_seed_" .. region.id .. "_" .. row.slot.id,
        nil,
        "vary",
        "##seq_popup_vary_refresh_" .. region.id .. "_" .. row.slot.id
      )
      if vary_changed then
        row.settings.vary_prob = vary_value
        row_changed = true
      end
      if vary_seed then
        apply_seed(function() row.settings.vary_seed = seq_new_seed() end)
      end
      if vary_refresh then
        apply_seed(function() row.settings.vary_swap_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end
    if row.show_stut then
      local stut_changed, stut_value, stut_seed = render_column(
        "popup_stut_" .. row.slot.id,
        "Stut",
        "%.2f",
        row.settings.stutter_prob or 0.0,
        0.0,
        1.0,
        "##seq_popup_stut_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_stut_seed_" .. region.id .. "_" .. row.slot.id,
        nil,
        "stut"
      )
      if stut_changed then
        row.settings.stutter_prob = stut_value
        row_changed = true
      end
      if stut_seed then
        apply_seed(function() row.settings.stutter_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end
    if row.show_grace then
      local grace_changed, grace_value, grace_seed = render_column(
        "popup_grace_" .. row.slot.id,
        "Grace",
        "%.2f",
        row.settings.ghost_grace or 0.0,
        0.0,
        1.0,
        "##seq_popup_grace_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_grace_seed_" .. region.id .. "_" .. row.slot.id,
        nil,
        "grace"
      )
      if grace_changed then
        row.settings.ghost_grace = grace_value
        row_changed = true
      end
      if grace_seed then
        apply_seed(function() row.settings.ghost_grace_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end
    if row.show_after then
      local after_changed, after_value, after_seed = render_column(
        "popup_after_" .. row.slot.id,
        "After",
        "%.2f",
        row.settings.ghost_after or 0.0,
        0.0,
        1.0,
        "##seq_popup_after_knob_" .. region.id .. "_" .. row.slot.id,
        "##seq_popup_after_seed_" .. region.id .. "_" .. row.slot.id,
        nil,
        "after"
      )
      if after_changed then
        row.settings.ghost_after = after_value
        row_changed = true
      end
      if after_seed then
        apply_seed(function() row.settings.ghost_after_seed = seq_new_seed() end)
      end
      x = x + col_w + col_gap
    end

    if row_changed then
      changed_any = true
      seq_queue_random_sync(region.pattern_id, row.slot.id)
    end
    y = y + stack_h
    if row_idx < #rows then
      y = y + track_gap
    end
  end

  state.seq_random_popup_active_key = next_focus
  r.ImGui_SetCursorScreenPos(ctx, origin_x, origin_y)
  r.ImGui_Dummy(ctx, content_w, content_h)
  local fly_slot = state.seq_random_flyout and state.seq_random_flyout.slot_id
  if seq_render_random_flyout(popup_dl, pattern, "popup") then
    changed_any = true
    seq_queue_random_sync(region.pattern_id, fly_slot)
  end

  if changed_any then
    begin_seq_undo("Edit sequencer random")
    seq_undo_commit_on_release = true
  end

  r.ImGui_EndPopup(ctx)
  pop_random_popup_style()
end

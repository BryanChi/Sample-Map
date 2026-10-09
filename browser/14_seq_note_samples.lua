-- Sample Map Browser module: seq_note_samples
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_resolve_note_sample(note, slot, vary_override, region, track_id, step_key)
  local filter = seq_cell_vary_filter(region, track_id or (slot and slot.id), step_key, note)
  local origin_path = seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, region)) or nil
  return resolve_seq_note_sample(note, slot, vary_override, filter, origin_path)
end

function resolve_seq_hovered_grid_sample()
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
  local region = hover.region_id and get_seq_region_by_id(hover.region_id) or nil
  local vary = seq_random_vary_amount(hover.note, region, slot.id, hover.step_key, 1)
  local _, sample = seq_resolve_note_sample(hover.note, slot, vary, region, slot.id, hover.step_key)
  return sample, slot
end

function preview_seq_hovered_grid()
  local hover = state.seq_grid_hover
  if not hover or not hover.slot_id then
    return false
  end
  local slot = nil
  for _, s in ipairs(state.seq_tracks) do
    if s.id == hover.slot_id then
      slot = s
      break
    end
  end
  if not slot then
    return false
  end
  local region = hover.region_id and get_seq_region_by_id(hover.region_id) or nil
  local vary = seq_random_vary_amount(hover.note, region, slot.id, hover.step_key, 1)
  local _, sample = seq_resolve_note_sample(hover.note, slot, vary, region, slot.id, hover.step_key)
  if sample then
    preview_sample(sample)
    state.seq_track_play_anims = state.seq_track_play_anims or {}
    state.seq_track_play_anims[tostring(slot.id)] = {
      start_time = r.time_precise(),
      duration = 0.35,
    }
    return true
  end
  return preview_seq_track_sample(slot)
end

function swap_seq_track_sample_neighbor(slot, direction)
  if not slot then
    return false
  end
  local region = seq_sample_assign_region and seq_sample_assign_region() or nil
  local current_path = seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, region))
    or slot.sample_path
  if not current_path then
    return false
  end

  local current = find_sample_by_path(current_path)
  if not current then
    return false
  end

  local neighbor = find_map_neighbor_sample(current, direction, slot.sample_tag)
  if not neighbor then
    if slot.sample_tag and seq_trim_text(slot.sample_tag) ~= "" then
      log("No more samples with tag '" .. slot.sample_tag .. "' " .. (direction < 0 and "to the left" or "to the right") .. " on the map")
    else
      log("No similar sample " .. (direction < 0 and "to the left" or "to the right") .. " on the map")
    end
    return false
  end

  local persist = not seq_slot_in_swap_mode(slot)
  local own = persist and seq_undo_own_begin("Swap sequencer sample")
  seq_assign_sample_for_context(slot, neighbor, persist)
  preview_seq_track_sample(slot)
  if own then
    end_seq_undo("Swap sequencer sample")
  end
  return true
end

function handle_map_arrow_keys()
  if not sample_map_is_open() then
    return
  end
  if imgui_any_popup_open and imgui_any_popup_open() then
    return
  end
  local left = shortcut_pressed("map_prev_sample")
  local right = shortcut_pressed("map_next_sample")
  if not left and not right then
    return
  end
  local direction = left and -1 or 1
  local slot = get_active_swap_slot()
  if not slot and state.selected_seq_track then
    slot = state.seq_tracks[state.selected_seq_track]
  end
  if slot then
    swap_seq_track_sample_neighbor(slot, direction)
    seq_open_minimap_popup(slot, true)
    return
  end
  local current = preview_sample_obj
  if current and current.path then
    local neighbor = find_map_neighbor_sample(current, direction)
    if neighbor then
      preview_sample(neighbor)
    end
  end
end

SEQ_NEIGHBOR_POPUP_COUNT = 10
SEQ_NEIGHBOR_POPUP_CENTER = 5
SEQ_NEIGHBOR_POPUP_PAD = 8

function seq_neighbor_popup_push_closest(arr, limit, sample, dist)
  local count = arr.n or 0
  if count < limit then
    count = count + 1
    arr.n = count
    arr[count] = { sample, dist }
    return
  end
  local worst_i, worst_d = 1, arr[1][2]
  for i = 2, count do
    local d = arr[i][2]
    if d > worst_d then
      worst_i, worst_d = i, d
    end
  end
  if dist < worst_d then
    arr[worst_i] = { sample, dist }
  end
end

function seq_neighbor_popup_take_sorted(arr)
  local count = arr.n or 0
  if count > 1 then
    table.sort(arr, function(a, b)
      return a[2] < b[2]
    end)
  end
  local out = {}
  for i = 1, count do
    out[i] = arr[i][1]
  end
  return out
end

function seq_neighbor_popup_build_items(origin, required_tag)
  local left_n = (SEQ_NEIGHBOR_POPUP_CENTER - 1) + SEQ_NEIGHBOR_POPUP_PAD
  local right_n = (SEQ_NEIGHBOR_POPUP_COUNT - SEQ_NEIGHBOR_POPUP_CENTER) + SEQ_NEIGHBOR_POPUP_PAD
  local items = {}
  local n = 0
  for _ = 1, left_n do
    n = n + 1
    items[n] = nil
  end
  n = n + 1
  items[n] = origin
  local center_idx = n
  for _ = 1, right_n do
    n = n + 1
    items[n] = nil
  end
  if not origin or not origin.path then
    return items, center_idx, n
  end

  local cx = origin.x or 0.5
  local cy = origin.y or 0.5
  local origin_path = origin.path
  local tag_filter = required_tag and seq_trim_text(required_tag) or ""
  local lefts, rights = { n = 0 }, { n = 0 }

  for _, s in ipairs(state.samples) do
    if s.path and s.path ~= origin_path and s.x and s.y
      and not sample_scan_folder_unavailable(s)
      and (tag_filter == "" or sample_has_tag(s, tag_filter)) then
      local dx = s.x - cx
      if dx < -1e-5 then
        local dy = s.y - cy
        seq_neighbor_popup_push_closest(lefts, left_n, s, dx * dx + dy * dy)
      elseif dx > 1e-5 then
        local dy = s.y - cy
        seq_neighbor_popup_push_closest(rights, right_n, s, dx * dx + dy * dy)
      end
    end
  end

  lefts = seq_neighbor_popup_take_sorted(lefts)
  rights = seq_neighbor_popup_take_sorted(rights)
  for i = 1, left_n do
    items[center_idx - i] = lefts[i]
  end
  for i = 1, right_n do
    items[center_idx + i] = rights[i]
  end
  return items, center_idx, n
end

function seq_neighbor_popup_prepare(items, count)
  local entries = {}
  local taken = 0
  local b_lo, b_hi = 1e9, -1e9
  local w_lo, w_hi = 1e9, -1e9
  local d_lo, d_hi = 1e9, -1e9
  for i = 1, count do
    local sample = items[i]
    local entry = sample and seq_candidate_entry_from_sample(sample) or nil
    entries[i] = entry
    if entry then
      local p = seq_candidate_chip_props(entry)
      local bright = p.brightness or p.freq
      taken = taken + 1
      if type(bright) == "number" then
        b_lo = math.min(b_lo, bright)
        b_hi = math.max(b_hi, bright)
      end
      w_lo = math.min(w_lo, p.weight)
      w_hi = math.max(w_hi, p.weight)
      if type(p.duration) == "number" and p.duration > 0 then
        d_lo = math.min(d_lo, p.duration)
        d_hi = math.max(d_hi, p.duration)
      end
    end
  end
  local scale = nil
  if taken >= 2 then
    scale = {
      bright_lo = b_lo, bright_hi = b_hi,
      weight_lo = w_lo, weight_hi = w_hi,
      dur_lo = d_lo, dur_hi = d_hi,
    }
  end
  return entries, scale
end

function seq_open_neighbor_popup(slot, rel)
  if not slot then
    return
  end
  local region = seq_sample_assign_region and seq_sample_assign_region() or nil
  local origin = seq_effective_slot_sample and seq_effective_slot_sample(slot, region)
    or (slot.sample_path and find_sample_by_path(slot.sample_path))
  if not origin then
    return
  end
  rel = tonumber(rel) or 0
  local items, center_idx, item_count = seq_neighbor_popup_build_items(origin, slot.sample_tag)
  local entries, scale = seq_neighbor_popup_prepare(items, item_count)
  local now = r.time_precise()
  local prev = state.seq_neighbor_popup
  local same_slot = prev and prev.slot_id == slot.id
  local anchors = state.seq_nav_anchors
  local anchor = (anchors and anchors[slot.id]) or (same_slot and prev.anchor) or nil
  state.seq_neighbor_popup = {
    slot_id = slot.id,
    items = items,
    entries = entries,
    scale = scale,
    center_idx = center_idx,
    item_count = item_count,
    anchor = anchor,
    idle_since = now,
    hovered = same_slot and prev.hovered or false,
    scroll_from = (rel ~= 0) and -rel or 0,
    scroll_t0 = now,
    scroll_dur = 0.22,
  }
end

function seq_neighbor_popup_choose(slot, sample, rel)
  if not slot or not sample then
    return
  end
  local persist = not seq_slot_in_swap_mode(slot)
  local own = persist and seq_undo_own_begin("Swap sequencer sample")
  seq_assign_sample_for_context(slot, sample, persist)
  preview_seq_track_sample(slot)
  if own then
    end_seq_undo("Swap sequencer sample")
  end
  seq_open_neighbor_popup(slot, rel)
end

function render_seq_neighbor_popup()
  local pop = state.seq_neighbor_popup
  if not pop then
    return
  end
  local slot = find_seq_track_by_id(pop.slot_id)
  if not slot then
    state.seq_neighbor_popup = nil
    return
  end

  local now = r.time_precise()
  if pop.hovered then
    pop.idle_since = now
  end
  local age = now - (pop.idle_since or now)
  if (not pop.hovered) and age >= 1.0 then
    state.seq_neighbor_popup = nil
    return
  end
  local alpha = pop.hovered and 1.0 or math.max(0.0, 1.0 - age)

  local scroll = 0.0
  if pop.scroll_from and pop.scroll_from ~= 0 and pop.scroll_t0 then
    local t = (now - pop.scroll_t0) / (pop.scroll_dur or 0.22)
    if t >= 1.0 then
      pop.scroll_from = 0
      scroll = 0.0
    else
      t = math.max(0.0, t)
      local ease = 1.0 - (1.0 - t) * (1.0 - t)
      scroll = pop.scroll_from * (1.0 - ease)
    end
  end

  local anchors = state.seq_nav_anchors
  if anchors and anchors[pop.slot_id] then
    pop.anchor = anchors[pop.slot_id]
  end
  local anchor = pop.anchor
  if not anchor then
    return
  end

  local sq, gap, pad = 28.0, 4.0, 8.0
  local count = SEQ_NEIGHBOR_POPUP_COUNT
  local view_w = count * sq + (count - 1) * gap
  local win_w = view_w + pad * 2
  local win_h = sq + pad * 2
  local wx = (anchor.x or 0) + (anchor.w or 0) * 0.5 - win_w * 0.5
  local wy = (anchor.y or 0) + (anchor.h or 0) + 8.0
  local wr = state.main_window_rect
  if wr then
    wx = math.max(wr.x + 8, math.min(wx, wr.x + wr.w - win_w - 8))
    if wy + win_h > wr.y + wr.h - 8 then
      wy = (anchor.y or wy) - win_h - 8
    end
    wy = math.max(wr.y + 8, math.min(wy, wr.y + wr.h - win_h - 8))
  end

  if r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(ctx, wx, wy, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end
  if r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, win_w, win_h, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  end

  local flags = 0
  if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
  if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoCollapse then flags = flags | r.ImGui_WindowFlags_NoCollapse() end
  if r.ImGui_WindowFlags_NoSavedSettings then flags = flags | r.ImGui_WindowFlags_NoSavedSettings() end
  if r.ImGui_WindowFlags_NoDocking then flags = flags | r.ImGui_WindowFlags_NoDocking() end
  if r.ImGui_WindowFlags_NoNav then flags = flags | r.ImGui_WindowFlags_NoNav() end
  if r.ImGui_WindowFlags_NoFocusOnAppearing then flags = flags | r.ImGui_WindowFlags_NoFocusOnAppearing() end
  if r.ImGui_WindowFlags_NoBackground then flags = flags | r.ImGui_WindowFlags_NoBackground() end
  if r.ImGui_WindowFlags_NoMove then flags = flags | r.ImGui_WindowFlags_NoMove() end

  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  end
  local began_ok, visible = pcall(r.ImGui_Begin, ctx, "##seq_neighbor_popup", nil, flags)
  if not began_ok or not visible then
    if r.ImGui_PopStyleVar then
      pcall(r.ImGui_PopStyleVar, ctx, 1)
    end
    return
  end

  local hover_flags = 0
  if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then
    hover_flags = r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
  end
  pop.hovered = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx, hover_flags) or false

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local px, py = r.ImGui_GetWindowPos(ctx)
  local bg = UI_THEME.surface or 0x121816FF
  local border = UI_THEME.border or 0x2A3830FF
  local function fade_col(col)
    local orig_a = (col % 256) / 255.0
    return change_color_alpha(col, orig_a * alpha)
  end
  r.ImGui_DrawList_AddRectFilled(dl, px, py, px + win_w, py + win_h, fade_col(bg), 8.0)
  r.ImGui_DrawList_AddRect(dl, px + 0.5, py + 0.5, px + win_w - 0.5, py + win_h - 0.5, fade_col(border), 8.0, 0, 1.0)

  local items = pop.items or {}
  local entries = pop.entries or {}
  local center_idx = pop.center_idx or SEQ_NEIGHBOR_POPUP_CENTER
  local item_count = pop.item_count or 0
  local view_left_idx = center_idx - (SEQ_NEIGHBOR_POPUP_CENTER - 1)
  local scale = pop.scale
  local pitch = sq + gap
  local clip_x0 = px + pad
  local clip_y0 = py + pad
  local clip_x1 = clip_x0 + view_w
  local clip_y1 = clip_y0 + sq
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, clip_x0, clip_y0, clip_x1, clip_y1, true)
  end

  local mx, my = r.ImGui_GetMousePos(ctx)
  local clicked_sample, clicked_rel = nil, 0
  local tip_name = nil
  for i = 1, item_count do
    local x = clip_x0 + (i - view_left_idx - scroll) * pitch
    if x + sq > clip_x0 - 1 and x < clip_x1 + 1 then
      local sample = items[i]
      local entry = entries[i]
      local is_center = (i == center_idx)
      local hovered_sq = mx >= x and my >= clip_y0 and mx <= x + sq and my <= clip_y1
      seq_draw_sample_candidate_square(
        dl, seq_box(x, clip_y0, sq, sq), entry, is_center, hovered_sq, scale, nil, alpha
      )
      if sample and hovered_sq then
        tip_name = sample.name or sample.path
        if r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) and not is_center then
          clicked_sample = sample
          clicked_rel = i - center_idx
        end
      end
    end
  end

  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end

  r.ImGui_InvisibleButton(ctx, "##seq_neighbor_hit", win_w, win_h)
  if tip_name and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, tip_name)
  end

  if r.ImGui_PopStyleVar then
    r.ImGui_PopStyleVar(ctx, 1)
  end
  r.ImGui_End(ctx)

  if clicked_sample then
    seq_neighbor_popup_choose(slot, clicked_sample, clicked_rel)
  end
end

SEQ_MINIMAP_SIZE = 200
SEQ_MINIMAP_ZOOM = 8.0
SEQ_MINIMAP_ZOOM_MIN = 2.0
SEQ_MINIMAP_ZOOM_MAX = 16.0
SEQ_MINIMAP_FADE_HOLD = 0.65
SEQ_MINIMAP_FADE_DUR = 0.8
SEQ_MINIMAP_LABEL_SCALE = 0.7

function seq_minimap_fade_col(col, alpha)
  if not col then
    return col
  end
  if (alpha or 1.0) >= 0.999 then
    return col
  end
  local orig_a = (col % 256) / 255.0
  return change_color_alpha(col, orig_a * (alpha or 1.0))
end

function seq_minimap_format_duration(nx)
  local log10 = math.log(10)
  local dmin = map_cache and map_cache.duration_min
  local dmax = map_cache and map_cache.duration_max
  if not dmin or not dmax then
    dmin, dmax = 0.01, 60.0
  end
  local len_min_log = math.log(math.max(dmin, 0.01)) / log10
  local len_max_log = math.log(math.max(dmax, 0.01)) / log10
  local padding = 0.05
  local t = (nx - padding) / (1.0 - 2.0 * padding)
  t = math.max(0.0, math.min(1.0, t))
  local time_val = 10 ^ (len_min_log + t * (len_max_log - len_min_log))
  if time_val < 1.0 then
    return string.format("%.2fs", time_val)
  elseif time_val < 10.0 then
    return string.format("%.1fs", time_val)
  end
  return string.format("%.0fs", time_val)
end

function seq_minimap_format_y(ny)
  local y_axis = map_y_axis_id()
  local y_normalized = 1.0 - ny
  if y_axis == "weight" then
    if y_normalized >= 0.92 then
      return "Heavy"
    elseif y_normalized <= 0.08 then
      return "Light"
    end
    return string.format("%.0f%%", y_normalized * 100.0)
  end
  local log10 = math.log(10)
  local freq_val = 10 ^ (math.log(40.0) / log10 + y_normalized * (math.log(20000.0) / log10 - math.log(40.0) / log10))
  local rounded_freq = round_to_nice_map_freq(freq_val)
  if rounded_freq >= 1000.0 then
    return string.format("%.1fkHz", rounded_freq / 1000.0)
  end
  return string.format("%.0fHz", rounded_freq)
end

function seq_minimap_label_size(text)
  local tw, th = 0, 10
  if r.ImGui_CalcTextSize then
    tw, th = r.ImGui_CalcTextSize(ctx, text)
  end
  local base_sz = (r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx)) or 13.0
  local sz = base_sz * SEQ_MINIMAP_LABEL_SCALE
  return (tw or 24) * SEQ_MINIMAP_LABEL_SCALE, (th or 10) * SEQ_MINIMAP_LABEL_SCALE, sz
end

function seq_minimap_draw_label(dl, x, y, color, text, alpha)
  local font = r.ImGui_GetFont and r.ImGui_GetFont(ctx) or nil
  local _, _, sz = seq_minimap_label_size(text)
  local shadow = seq_minimap_fade_col(0x000000AA, alpha)
  if r.ImGui_DrawList_AddTextEx then
    r.ImGui_DrawList_AddTextEx(dl, font, sz, x + 0.7, y + 0.7, shadow, text)
    r.ImGui_DrawList_AddTextEx(dl, font, sz, x, y, color, text)
  else
    r.ImGui_DrawList_AddText(dl, x + 0.7, y + 0.7, shadow, text)
    r.ImGui_DrawList_AddText(dl, x, y, color, text)
  end
end

function draw_seq_minimap_rulers(dl, pop, x0, y0, w, h, alpha, draw_labels)
  local zoom = pop.zoom or SEQ_MINIMAP_ZOOM
  if zoom < 0.001 then
    zoom = 0.001
  end
  local center_x = x0 + w * 0.5 + (pop.pan_x or 0)
  local center_y = y0 + h * 0.5 + (pop.pan_y or 0)
  local grid_color = seq_minimap_fade_col(0x4A5850AA, alpha)
  local text_color = seq_minimap_fade_col(0xC8D4CCDD, alpha)
  local n = 3
  local nx0 = ((x0 - center_x) / (w * zoom)) + 0.5
  local nx1 = ((x0 + w - center_x) / (w * zoom)) + 0.5
  local ny0 = ((y0 - center_y) / (h * zoom)) + 0.5
  local ny1 = ((y0 + h - center_y) / (h * zoom)) + 0.5
  local inset = 3.0

  for i = 0, n do
    local nx = nx0 + (i / n) * (nx1 - nx0)
    local px = center_x + w * (nx - 0.5) * zoom
    if not draw_labels then
      r.ImGui_DrawList_AddLine(dl, px, y0, px, y0 + h, grid_color, 1.0)
    else
      local label = seq_minimap_format_duration(nx)
      local tw = seq_minimap_label_size(label)
      local tx = px + 3
      if i == 0 then
        tx = x0 + 28
      elseif i == n or tx + tw > x0 + w - inset then
        tx = math.max(x0 + inset, px - tw - 2)
      end
      seq_minimap_draw_label(dl, tx, y0 + inset, text_color, label, alpha)
    end
  end

  for i = 0, n do
    local ny = ny0 + (i / n) * (ny1 - ny0)
    local py = center_y + h * (ny - 0.5) * zoom
    if not draw_labels then
      r.ImGui_DrawList_AddLine(dl, x0, py, x0 + w, py, grid_color, 1.0)
    elseif i > 0 then
      local label = seq_minimap_format_y(ny)
      local tw, th = seq_minimap_label_size(label)
      local ty = py - (th or 8) * 0.5
      if ty < y0 + 12 then
        ty = y0 + 12
      elseif ty > y0 + h - (th or 8) - inset then
        ty = y0 + h - (th or 8) - inset
      end
      seq_minimap_draw_label(dl, x0 + inset, ty, text_color, label, alpha)
    end
  end
end

function seq_minimap_filter_tag(slot)
  local tag = resolve_seq_swap_filter_tag(slot)
  if not tag or tag == "" then
    return ""
  end
  return find_library_tag(tag) or tag
end

function seq_minimap_ensure_samples(pop, slot)
  local tag = seq_minimap_filter_tag(slot)
  local lib_n = #(state.samples or {})
  local epoch = state.tag_index_epoch or 0
  if pop.samples and pop.tag == tag and pop.lib_n == lib_n and pop.tag_epoch == epoch then
    return
  end

  -- Reuse a process-wide list for the same tag so Shift+V reopen is instant.
  local cache = state._seq_minimap_sample_cache
  if cache and cache.tag == tag and cache.lib_n == lib_n and cache.epoch == epoch and cache.list then
    pop.tag = tag
    pop.lib_n = lib_n
    pop.tag_epoch = epoch
    pop.samples = cache.list
    return
  end

  local list = {}
  local by_tag = (tag ~= "" and state.samples_by_tag) and state.samples_by_tag[tag] or nil
  if by_tag then
    for i = 1, #by_tag do
      local s = by_tag[i]
      if s and s.path and s.x and s.y and not sample_scan_folder_unavailable(s) then
        if not s._render_color then
          s._render_color = get_sample_dot_color(s)
        end
        list[#list + 1] = s
      end
    end
  else
    local samples = state.samples or {}
    for i = 1, #samples do
      local s = samples[i]
      if s and s.path and s.x and s.y and not sample_scan_folder_unavailable(s) then
        local ok = (tag == "")
        if not ok then
          ok = (s._tag_set and s._tag_set[tag]) or sample_has_tag(s, tag)
        end
        if ok then
          if not s._render_color then
            s._render_color = get_sample_dot_color(s)
          end
          list[#list + 1] = s
        end
      end
    end
  end

  pop.tag = tag
  pop.lib_n = lib_n
  pop.tag_epoch = epoch
  pop.samples = list
  state._seq_minimap_sample_cache = {
    tag = tag,
    lib_n = lib_n,
    epoch = epoch,
    list = list,
  }
end

function seq_minimap_center_on(pop, sample, w, h)
  local sx = (sample and sample.x) or 0.5
  local sy = (sample and sample.y) or 0.5
  local z = pop.zoom or SEQ_MINIMAP_ZOOM
  pop.pan_x = -w * (sx - 0.5) * z
  pop.pan_y = -h * (sy - 0.5) * z
end

function seq_minimap_clamp_pan(pop, w, h)
  local z = pop.zoom or SEQ_MINIMAP_ZOOM
  local max_pan = w * 0.5 * z
  pop.pan_x = math.max(-max_pan, math.min(max_pan, pop.pan_x or 0))
  local min_pan_y = h * 0.5 * (1.0 - z)
  local max_pan_y = h * 0.5 * (z - 1.0)
  pop.pan_y = math.max(min_pan_y, math.min(max_pan_y, pop.pan_y or 0))
end

function seq_pin_note_sample(note, sample, slot, region)
  if type(note) ~= "table" or not sample or not sample.path then
    return false
  end
  local path = sample.path
  local origin_path = seq_note_vary_origin_path(note, slot, region)
  local track_path, track_name = seq_effective_slot_sample_path(slot, region)
  if not track_path then
    track_path, track_name = slot and slot.sample_path, slot and slot.sample_name
  end
  local same_as_track = track_path and seq_paths_same(path, track_path)
  local already = seq_paths_same(note.frozen_sample_path, path)
    or ((not seq_note_has_frozen_sample(note)) and same_as_track)
  if already and (tonumber(note.sample_vary) or 0) <= 0.000001 then
    return false
  end

  local function zero_hit_vary(hit)
    if type(hit) == "table" then
      hit.sample_vary = 0.0
    end
  end

  if same_as_track then
    seq_clear_frozen_sample(note)
    note.sample_path = track_path
    note.sample_name = track_name or basename(track_path)
    note.sample_vary = 0.0
    if type(note.stutter_hits) == "table" then
      for _, hit in pairs(note.stutter_hits) do
        zero_hit_vary(hit)
      end
    end
    return true
  end

  seq_apply_frozen_sample(note, path, sample, origin_path)
  note.sample_path = path
  note.sample_name = sample.name or basename(path)
  note.sample_vary = 0.0
  note.picked_sample = true
  if type(note.stutter_hits) == "table" then
    for _, hit in pairs(note.stutter_hits) do
      if type(hit) == "table" then
        seq_apply_frozen_sample(hit, path, sample, origin_path)
        hit.sample_vary = 0.0
        hit.picked_sample = true
      end
    end
  end
  return true
end

function seq_collect_note_sample_pick_targets()
  local targets = {}
  local seen = {}
  local function add(region_id, track_id, step_key)
    if not region_id or track_id == nil or step_key == nil then
      return
    end
    local key = tostring(region_id) .. ":" .. tostring(track_id) .. ":" .. tostring(step_key)
    if seen[key] then
      return
    end
    if not get_seq_note(get_seq_region_by_id(region_id), track_id, step_key) then
      return
    end
    seen[key] = true
    targets[#targets + 1] = {
      region_id = region_id,
      track_id = track_id,
      step_key = tostring(step_key),
    }
  end

  if seq_has_razors() then
    local items = seq_razor_collect_notes()
    for i = 1, #items do
      local rec = items[i]
      add(rec.region_id, rec.track_id, rec.step_key)
    end
    return targets
  end

  local hover = state.seq_grid_hover
  if hover and hover.note and hover.region_id and hover.step_key then
    add(hover.region_id, hover.slot_id, hover.step_key)
    return targets
  end

  local sel = state.selected_seq_note
  if sel then
    add(sel.region_id, sel.track_id, sel.step_key)
  end
  return targets
end

function seq_assign_sample_to_note_targets(targets, sample)
  if not sample or not sample.path or not targets or #targets == 0 then
    return false
  end
  local own = seq_undo_own_begin("Swap note sample")
  local changed = false
  local synced = {}
  for i = 1, #targets do
    local t = targets[i]
    local region = get_seq_region_by_id(t.region_id)
    local slot = seq_find_slot_by_id(t.track_id)
    local note = get_seq_note(region, t.track_id, t.step_key)
    if note and slot and seq_pin_note_sample(note, sample, slot, region) then
      changed = true
      if region and region.pattern_id then
        local by_track = synced[region.pattern_id]
        if not by_track then
          by_track = {}
          synced[region.pattern_id] = by_track
        end
        by_track[slot.id] = slot
      end
    end
  end
  if changed then
    if r.PreventUIRefresh then
      r.PreventUIRefresh(1)
    end
    for pattern_id, slots in pairs(synced) do
      for _, slot in pairs(slots) do
        sync_seq_pattern_track(pattern_id, slot, { skip_arrange = true, force_rebuild = true })
      end
    end
    if r.PreventUIRefresh then
      r.PreventUIRefresh(-1)
    end
    r.UpdateArrange()
    save_config()
  end
  preview_sample(sample)
  if own then
    end_seq_undo("Swap note sample")
  end
  return true
end

function seq_begin_note_sample_pick()
  if seq_ingest_busy and seq_ingest_busy() then
    return false
  end
  local targets = seq_collect_note_sample_pick_targets()
  if #targets == 0 then
    if seq_has_razors() then
      log("No notes in the razor to swap")
    else
      log("Hover a sequencer note or draw a razor, then Shift+V to pick a sample")
    end
    return false
  end
  local origin = targets[1]
  local hover = state.seq_grid_hover
  if hover and hover.slot_id then
    for i = 1, #targets do
      if targets[i].track_id == hover.slot_id then
        origin = targets[i]
        break
      end
    end
  end
  local region = get_seq_region_by_id(origin.region_id)
  local slot = seq_find_slot_by_id(origin.track_id)
  if not slot then
    return false
  end
  local note = get_seq_note(region, origin.track_id, origin.step_key)
  local origin_sample = nil
  if note then
    local vary = seq_random_vary_amount(note, region, slot.id, origin.step_key, 1)
    local _, resolved = seq_resolve_note_sample(note, slot, vary, region, slot.id, origin.step_key)
    origin_sample = resolved
  end
  origin_sample = origin_sample or find_sample_by_path(slot.sample_path)
  seq_open_minimap_popup(slot, true, {
    mode = "notes",
    targets = targets,
    origin_path = (origin_sample and origin_sample.path) or slot.sample_path,
    place_at_mouse = true,
    pin_anchor = true,
  })
  return true
end

function seq_toggle_note_sample_pick()
  local pop = state.seq_minimap_popup
  if pop and pop.mode == "notes" then
    state.seq_minimap_popup = nil
    return true
  end
  return seq_begin_note_sample_pick()
end

function seq_minimap_assign(slot, sample)
  if not sample or not sample.path then
    return
  end
  local pop = state.seq_minimap_popup
  if pop and pop.mode == "notes" then
    seq_assign_sample_to_note_targets(pop.targets, sample)
    pop.origin_path = sample.path
    return
  end
  if not slot then
    return
  end
  local region = seq_sample_assign_region and seq_sample_assign_region() or nil
  local current_path = seq_effective_slot_sample_path and select(1, seq_effective_slot_sample_path(slot, region))
    or slot.sample_path
  if current_path and seq_paths_same and seq_paths_same(current_path, sample.path) then
    preview_seq_track_sample(slot)
    return
  end
  local persist = not seq_slot_in_swap_mode(slot)
  local own = persist and seq_undo_own_begin("Swap sequencer sample")
  seq_assign_sample_for_context(slot, sample, persist)
  preview_seq_track_sample(slot)
  if own then
    end_seq_undo("Swap sequencer sample")
  end
end

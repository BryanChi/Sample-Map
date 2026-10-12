-- Sample Map Browser module: seq_track_order
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_capture_selected_track_guids()
  local guids = {}
  local n = r.CountSelectedTracks(0)
  for i = 0, n - 1 do
    local tr = r.GetSelectedTrack(0, i)
    if tr then
      guids[#guids + 1] = r.GetTrackGUID(tr)
    end
  end
  return guids
end

function seq_restore_selected_track_guids(guids)
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    r.SetTrackSelected(r.GetTrack(0, i), false)
  end
  for i = 1, #(guids or {}) do
    local tr = get_track_by_guid(guids[i])
    if tr then
      r.SetTrackSelected(tr, true)
    end
  end
end

function seq_select_reaper_track_block(tr)
  if not tr then
    return nil, 0
  end
  r.SetOnlyTrackSelected(tr)
  local idx = seq_get_media_track_index(tr)
  if not idx then
    return nil, 0
  end
  local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
  local count = 1
  if depth >= 1 then
    local d = 1
    local n = r.CountTracks(0)
    for i = idx + 1, n - 1 do
      local child = r.GetTrack(0, i)
      r.SetTrackSelected(child, true)
      count = count + 1
      d = d + (r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") or 0)
      if d <= 0 then
        break
      end
    end
  end
  return idx, count
end

function seq_reaper_track_span_end(tr)
  local idx = seq_get_media_track_index(tr)
  if not idx then
    return nil
  end
  local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
  if depth < 1 then
    return idx
  end
  return seq_folder_last_child_index(tr) or idx
end

function seq_move_reaper_track_block_to(tr, dest_idx)
  if not tr or not dest_idx or not r.ReorderSelectedTracks then
    return false
  end
  local src, count = seq_select_reaper_track_block(tr)
  if not src or count < 1 or src == dest_idx then
    return false
  end
  if src < dest_idx then
    r.ReorderSelectedTracks(dest_idx + count, 0)
  else
    r.ReorderSelectedTracks(dest_idx, 0)
  end
  return true
end

function seq_apply_seq_order_to_arrange()
  if not r.ReorderSelectedTracks then
    return false
  end
  local ordered = {}
  for i = 1, #(state.seq_tracks or {}) do
    local slot = state.seq_tracks[i]
    local tr = slot and slot.reaper_track_guid and get_track_by_guid(slot.reaper_track_guid)
    if tr then
      ordered[#ordered + 1] = tr
    end
  end
  if #ordered < 2 then
    return false
  end
  local saved = seq_capture_selected_track_guids()
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  local moved = false
  local guard = 0
  local limit = #ordered * #ordered + 4
  while guard < limit do
    guard = guard + 1
    local prev_tr = nil
    local inversion = nil
    for i = 1, #ordered do
      local tr = ordered[i]
      local idx = seq_get_media_track_index(tr)
      if idx then
        if prev_tr then
          local prev_idx = seq_get_media_track_index(prev_tr)
          if prev_idx and idx < prev_idx then
            inversion = tr
            break
          end
        end
        prev_tr = tr
      end
    end
    if not inversion or not prev_tr then
      break
    end
    local want = (seq_reaper_track_span_end(prev_tr) or seq_get_media_track_index(prev_tr) or 0) + 1
    local have = seq_get_media_track_index(inversion)
    if have and have ~= want then
      if seq_move_reaper_track_block_to(inversion, want) then
        moved = true
      else
        break
      end
    else
      break
    end
  end
  seq_restore_selected_track_guids(saved)
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if moved then
    r.UpdateArrange()
    state.seq_skip_order_sync = true
    seq_mark_self_arrange_write()
  end
  return moved
end

function find_seq_parent_folder_track()
  if state.seq_folder_guid and state.seq_folder_guid ~= "" then
    local tr = get_track_by_guid(state.seq_folder_guid)
    if tr then
      return tr
    end
    state.seq_folder_guid = nil
  end
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    local tr = r.GetTrack(0, i)
    local _, name = r.GetTrackName(tr)
    if name == SEQ_TRACK_FOLDER_NAME then
      local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
      if depth >= 1 then
        state.seq_folder_guid = r.GetTrackGUID(tr)
        return tr
      end
    end
  end
  return nil
end

function create_seq_parent_folder_track()
  local insert_idx = r.CountTracks(0)
  r.InsertTrackAtIndex(insert_idx, true)
  local tr = r.GetTrack(0, insert_idx)
  if not tr then
    return nil
  end
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", SEQ_TRACK_FOLDER_NAME, true)
  r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
  state.seq_folder_guid = r.GetTrackGUID(tr)
  return tr
end

function seq_folder_last_child_index(folder_tr)
  local folder_idx = seq_get_media_track_index(folder_tr)
  if not folder_idx then
    return nil, false
  end
  local folder_depth = r.GetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH") or 0
  if folder_depth < 1 then
    return folder_idx, false
  end
  local depth = 1
  local last_idx = folder_idx
  local n = r.CountTracks(0)
  for i = folder_idx + 1, n - 1 do
    last_idx = i
    depth = depth + (r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH") or 0)
    if depth <= 0 then
      return last_idx, true
    end
  end
  return last_idx, last_idx > folder_idx
end

function insert_reaper_track_in_seq_folder()
  local folder = find_seq_parent_folder_track() or create_seq_parent_folder_track()
  if not folder then
    local idx = r.CountTracks(0)
    r.InsertTrackAtIndex(idx, true)
    return r.GetTrack(0, idx)
  end

  local last_idx, has_children = seq_folder_last_child_index(folder)
  if not last_idx then
    local idx = r.CountTracks(0)
    r.InsertTrackAtIndex(idx, true)
    return r.GetTrack(0, idx)
  end

  local insert_idx = last_idx + 1
  r.InsertTrackAtIndex(insert_idx, true)
  local new_tr = r.GetTrack(0, insert_idx)
  if not new_tr then
    return nil
  end

  if not has_children then
    r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
    r.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", -1)
  else
    local prev = r.GetTrack(0, last_idx)
    local prev_d = r.GetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH") or 0
    if prev_d < 0 then
      r.SetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH", prev_d + 1)
    else
      r.SetMediaTrackInfo_Value(prev, "I_FOLDERDEPTH", 0)
    end
    r.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", -1)
  end
  return new_tr
end

function create_seq_track_with_name(track_name)
  local final_name = seq_trim_text(track_name)
  if final_name == "" then
    final_name = "Track " .. tostring(#state.seq_tracks + 1)
  end

  local tr
  if state.group_seq_tracks_in_folder ~= false then
    tr = insert_reaper_track_in_seq_folder()
  else
    local insert_idx = r.CountTracks(0)
    r.InsertTrackAtIndex(insert_idx, true)
    tr = r.GetTrack(0, insert_idx)
  end
  if not tr then
    return nil
  end

  r.GetSetMediaTrackInfo_String(tr, "P_NAME", final_name, true)
  local slot = add_seq_track_from_reaper_track(tr)
  if not slot then
    return nil
  end

  slot.name = final_name
  return slot
end

-- Recreate arrange tracks for sequencer slots whose GUIDs no longer resolve
-- (sequencer undo after a track delete).
function seq_ensure_slot_reaper_tracks()
  local changed = false
  for _, slot in ipairs(state.seq_tracks or {}) do
    local guid = slot.reaper_track_guid
    local tr = (guid and guid ~= "") and get_track_by_guid(guid) or nil
    if not tr then
      if state.group_seq_tracks_in_folder ~= false and insert_reaper_track_in_seq_folder then
        tr = insert_reaper_track_in_seq_folder()
      else
        local insert_idx = r.CountTracks(0)
        r.InsertTrackAtIndex(insert_idx, true)
        tr = r.GetTrack(0, insert_idx)
      end
      if tr then
        r.GetSetMediaTrackInfo_String(tr, "P_NAME", slot.name or "Track", true)
        slot.reaper_track_guid = r.GetTrackGUID(tr)
        changed = true
      end
    end
  end
  if changed then
    if seq_apply_seq_order_to_arrange then
      seq_apply_seq_order_to_arrange()
    end
    if seq_mark_self_arrange_write then
      seq_mark_self_arrange_write()
    end
  end
  return changed
end

function create_seq_track_from_popup(track_name, tag_name)
  local own = seq_undo_own_begin("Add sequencer track")
  local slot = create_seq_track_with_name(track_name)
  if not slot then
    if own then
      end_seq_undo("Add sequencer track")
    end
    return false
  end

  local chosen_tag = seq_trim_text(tag_name)
  if chosen_tag ~= "" then
    slot.sample_tag = chosen_tag
    local sample = find_sample_for_tag(chosen_tag)
    if sample then
      assign_sample_to_seq_track(slot, sample, false)
    else
      log("No sample found for tag '" .. chosen_tag .. "'")
    end
  end

  save_config()
  if r.TrackList_AdjustWindows then
    r.TrackList_AdjustWindows(false)
  end
  r.UpdateArrange()
  if own then
    end_seq_undo("Add sequencer track")
  end
  return true
end

SEQ_ADD_TRACK_POPUP_W = 460.0
-- Outline for chips that are already in use (tracks here, project genres in
-- the kit popup).
SEQ_USED_CHIP_RING = 0xFFB870AA

-- Tag groups shown in the add-track popup, in display order.
SEQ_ADD_TRACK_GROUPS = {
  { key = "drum", label = "Drums" },
  { key = "melodic", label = "Melodic" },
  { key = "loop", label = "Loops" },
  { key = "other", label = "Other" },
  { key = "genre", label = "Genres" },
}

function seq_add_popup_tag_width(tag_label)
  local text_w = r.ImGui_CalcTextSize(ctx, tag_label)
  local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
  return text_w + pad_x * 2
end

function seq_add_popup_group_key(tag)
  local cat = categorize_tags(tag)
  if cat == "drum" or cat == "melodic" or cat == "loop" or cat == "genre" then
    return cat
  end
  return "other"
end

-- Lowercased tags and names already used by sequencer tracks.
function seq_add_popup_used_set()
  local used = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    local tag = seq_trim_text(slot.sample_tag):lower()
    if tag ~= "" then
      used[tag] = true
    end
    local name = seq_trim_text(slot.name):lower()
    if name ~= "" then
      used[name] = true
    end
  end
  return used
end

-- Library tags matching the query, grouped for display, plus the tag that
-- matches the query exactly (if any).
function seq_add_popup_matches(query_lower)
  local groups, exact = {}, nil
  for _, entry in ipairs(state.tag_list or {}) do
    local tag = tostring(entry.tag or "")
    if tag ~= "" and (query_lower == "" or tag:lower():find(query_lower, 1, true)) then
      local key = seq_add_popup_group_key(tag)
      groups[key] = groups[key] or {}
      groups[key][#groups[key] + 1] = entry
      if query_lower ~= "" and tag:lower() == query_lower then
        exact = tag
      end
    end
  end
  return groups, exact
end

function open_seq_add_track_popup()
  state.seq_new_track_query = ""
  if (not state.tag_list or #state.tag_list == 0) and #state.samples > 0 then
    rebuild_tag_index()
  end
  r.ImGui_OpenPopup(ctx, "seq_add_track_popup")
end

function render_seq_add_track_full_width_button(button_id, button_h)
  if draw_ui_button(tostring(button_id or "seq_add_track_popup_open"), nil, nil, button_h or 28, { icon = "plus", full_width = true, style = "primary" }) then
    open_seq_add_track_popup()
  end
end

function seq_add_track_and_close(name, tag)
  if create_seq_track_from_popup(name, tag) then
    state.seq_new_track_query = ""
    r.ImGui_CloseCurrentPopup(ctx)
    return true
  end
  return false
end

function render_seq_add_popup_tag_chip(entry, idx, used)
  local tag = tostring(entry.tag or "")
  local is_used = used[tag:lower()] == true
  if draw_tag_button(ctx, tag, false, tag, "seq_add_popup_" .. tostring(idx) .. "_") then
    seq_add_track_and_close(tag, tag)
  end
  if is_used then
    ui_draw_chip_ring(SEQ_USED_CHIP_RING)
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    local count = tonumber(entry.count) or 0
    local tip = string.format("%d sample%s\nAdd a \"%s\" track with one of them", count, count == 1 and "" or "s", tag)
    if is_used then
      tip = tip .. "\nAlready in the sequencer"
    end
    r.ImGui_SetTooltip(ctx, tip)
  end
end

function render_seq_add_popup_tag_list(groups)
  local used = seq_add_popup_used_set()
  local shown = 0
  local idx = 0
  for _, group in ipairs(SEQ_ADD_TRACK_GROUPS) do
    local entries = groups[group.key]
    if entries and #entries > 0 then
      ui_group_caption(group.label)
      local flow = ui_flow_begin(6.0)
      for _, entry in ipairs(entries) do
        idx = idx + 1
        ui_flow_place(flow, seq_add_popup_tag_width(tostring(entry.tag or "")))
        render_seq_add_popup_tag_chip(entry, idx, used)
        shown = shown + 1
      end
      r.ImGui_Dummy(ctx, 1, 4)
    end
  end
  return shown
end

function render_seq_add_track_popup()
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, SEQ_ADD_TRACK_POPUP_W, 0, SEQ_ADD_TRACK_POPUP_W, 2000)
  end
  if not r.ImGui_BeginPopup(ctx, "seq_add_track_popup") then
    return
  end

  if (not state.tag_list or #state.tag_list == 0) and #state.samples > 0 then
    rebuild_tag_index()
  end

  local track_count = #(state.seq_tracks or {})
  ui_popup_header("plus", "Add track",
    string.format("%d track%s", track_count, track_count == 1 and "" or "s"))

  local submitted, query = ui_popup_search("seq_new_track_query", "Name the track or search tags", state.seq_new_track_query)
  state.seq_new_track_query = query
  local trimmed_query = seq_trim_text(query)
  local groups, exact_tag = seq_add_popup_matches(trimmed_query:lower())

  local create_label = (trimmed_query ~= "") and ('Create "' .. trimmed_query .. '"') or "Create empty track"
  local create_clicked = draw_ui_button("seq_create_custom", create_label, nil, 28,
    { full_width = true, style = "primary", lead_icon = "plus" })
  local hint
  if exact_tag then
    hint = "Loads a sample tagged \"" .. exact_tag .. "\""
  elseif trimmed_query ~= "" then
    hint = "No tag matches this name, so the track starts empty"
  else
    hint = "Or pick a tag below to get a track with a matching sample"
  end
  r.ImGui_TextColored(ctx, UI_THEME.text_dim, hint)
  if create_clicked or (submitted and trimmed_query ~= "") then
    seq_add_track_and_close(trimmed_query, exact_tag)
  end

  r.ImGui_Dummy(ctx, 1, 2)
  local list_h = ui_fit_child_height("seq_add_track_tags", 48, 300)
  local opened = ui_fit_child_begin("seq_add_track_tags", 0, list_h)
  if opened then
    local shown = render_seq_add_popup_tag_list(groups)
    if shown == 0 then
      local msg = (#(state.tag_list or {}) == 0) and "No tags in the library yet" or "No tags match"
      r.ImGui_TextColored(ctx, UI_THEME.text_mute, msg)
    end
  end
  ui_fit_child_end("seq_add_track_tags", opened)

  ui_popup_footer("Enter: create   ·   Esc: close   ·   Outlined: already a track")
  ui_popup_close_on_escape()
  r.ImGui_EndPopup(ctx)
end

function get_selected_seq_track()
  clamp_selected_seq_track()
  if not state.selected_seq_track then
    return nil
  end
  return state.seq_tracks[state.selected_seq_track]
end

function preview_seq_track_sample(slot)
  if not slot then
    return false
  end
  local region = seq_sample_assign_region and seq_sample_assign_region() or nil
  local sample = seq_effective_slot_sample and seq_effective_slot_sample(slot, region)
    or (slot.sample_path and find_sample_by_path(slot.sample_path))
  if not sample then
    return false
  end
  preview_sample(sample)
  state.seq_track_play_anims = state.seq_track_play_anims or {}
  state.seq_track_play_anims[tostring(slot.id)] = {
    start_time = r.time_precise(),
    duration = 0.35,
  }
  return true
end

function seq_resolve_hover_note(active, hovered_qn, start_qn, col, step_qn)
  if not active then
    return nil
  end
  if seq_active_cell_is_playable
      and not seq_active_cell_is_playable(active, start_qn, col, step_qn) then
    return nil
  end
  if seq_pick_packed_note then
    return seq_pick_packed_note(active, hovered_qn, start_qn, col, step_qn)
  end
  return active
end

function seq_set_grid_hover(slot, col, active_cells, start_qn, step_qn, hovered_qn)
  if not slot then
    state.seq_grid_hover = nil
    return
  end
  local active = active_cells and col and active_cells[slot.id] and active_cells[slot.id][col]
  local picked = hovered_qn and seq_resolve_hover_note(active, hovered_qn, start_qn, col, step_qn) or nil
  state.seq_grid_hover = {
    slot_id = slot.id,
    step_key = picked and picked.key or nil,
    region_id = picked and picked.region_id or nil,
    note = picked and picked.note or nil,
    hovered_qn = hovered_qn,
    step_qn = step_qn,
  }
end

function select_seq_track(idx, opts)
  opts = opts or {}
  if not idx or idx < 1 or idx > #state.seq_tracks then
    return false
  end
  state.selected_seq_track = idx
  save_config()
  if opts.preview ~= false then
    preview_seq_track_sample(state.seq_tracks[idx])
  end
  return true
end

-- Exposed for the upcoming sequencer UI
function SampleMapBrowser_GetSeqTracks()
  return state.seq_tracks
end

function SampleMapBrowser_GetSelectedSeqTrack()
  return get_selected_seq_track()
end

function SampleMapBrowser_GetSeqTrackSample(slot)
  if not slot or not slot.sample_path then
    return nil
  end
  return find_sample_by_path(slot.sample_path)
end

-- Eased 0..1 pulse used for animated drag/drop feedback.
function drag_pulse()
  return 0.5 + 0.5 * math.sin(r.time_precise() * 6.0)
end

-- Highlight a rectangular drop target while a sample is being dragged onto it.
function draw_drop_target_highlight(dl, x0, y0, x1, y1, radius)
  radius = radius or 4.0
  local pulse = drag_pulse()
  local fill = build_color_rrgbbaa(30, 255, 94, math.floor(28 + 40 * pulse))
  local border = build_color_rrgbbaa(30, 255, 94, math.floor(160 + 80 * pulse))
  local accent = build_color_rrgbbaa(30, 255, 94, 255)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, fill, radius)
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, border, radius, 0, 2.0)
  -- Bright accent bar on the left edge so the active target reads at a glance.
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + 3.0, y1, accent, radius)
end

function cursor_over_script_ui()
  local mx, my = r.ImGui_GetMousePos and r.ImGui_GetMousePos(ctx)
  mx, my = tonumber(mx), tonumber(my)
  if not mx or not my then
    return false
  end
  local function in_rect(rect)
    return rect
      and mx >= (rect.x or 0) and my >= (rect.y or 0)
      and mx <= (rect.x or 0) + (rect.w or 0)
      and my <= (rect.y or 0) + (rect.h or 0)
  end
  return in_rect(state.main_window_rect)
    or in_rect(state.sample_map_window_rect)
    or in_rect(state.sequencer_window_rect)
    or in_rect(state.seq_layering_rect)
end

function sample_is_waveform_drag_source(sample)
  local drag = state.pending_waveform_drop
  if not drag or not sample then
    return false
  end
  if drag.is_layering_mix or sample.is_layering_mix then
    return drag.is_layering_mix == true
      and sample.is_layering_mix == true
      and drag.layering_slot_id == sample.layering_slot_id
  end
  local a = drag.path and normalize_path(drag.path)
  local b = sample.path and normalize_path(sample.path)
  return a ~= nil and a == b
end

function draw_waveform_drag_source_cue(dl, x, y, w, h)
  if not dl or not state.pending_waveform_drop then
    return
  end
  local pulse = drag_pulse()
  local fill = build_color_rrgbbaa(30, 255, 94, math.floor(20 + 32 * pulse))
  local border = build_color_rrgbbaa(30, 255, 94, math.floor(170 + 70 * pulse))
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, fill, 4.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, border, 4.0, 0, 2.0)
end

-- Floating feedback that follows the cursor while a sample is being dragged.
function draw_sample_drag_ghost()
  local sample = get_active_dragged_sample()
  if not sample then
    clear_drag_tooltip()
    return
  end

  -- Normal map-dot audition drag: no tooltip unless the cursor is over a
  -- layering corner. Alt+drag and waveform drags keep the sequencer/arrange hints.
  if not state.pending_waveform_drop and not state.seq_layering_drop_vert then
    clear_drag_tooltip()
    return
  end

  local name = sample.name or basename(sample.path or "") or "sample"
  if #name > 40 then
    name = name:sub(1, 39) .. "..."
  end

  local over_seq = state.seq_drop_target_idx ~= nil or state.seq_candidate_drop ~= nil
    or state.seq_drum_drop ~= nil
  local over_timeline = state.seq_timeline_drop_time ~= nil
  local over_layer = state.seq_layering_drop_vert ~= nil
  local over_arrange = state.provisional_drop ~= nil
  local outside = not cursor_over_script_ui()

  -- Native tooltip when the cursor leaves the script (arrange drop).
  if over_arrange or (outside and not over_seq and not over_timeline and not over_layer) then
    local hint
    if state.seq_drum_drop then
      hint = "Release to set this region's sample"
    elseif state.seq_candidate_drop then
      hint = "Release to save in this slot"
    elseif over_seq then
      hint = sample.is_layering_mix
        and "Release to apply layered mix"
        or "Release to swap track sample"
    elseif over_timeline then
      hint = "Release to insert on this track"
    elseif over_arrange then
      hint = "Drop to insert on the arrange"
    else
      hint = "Drag over the arrange to insert  (Esc to cancel)"
    end
    if r.TrackCtl_SetToolTip and r.GetMousePosition then
      local sx, sy = r.GetMousePosition()
      r.TrackCtl_SetToolTip(name .. "\n" .. hint, math.floor((sx or 0) + 22), math.floor((sy or 0) + 22), true)
      state.drag_tooltip_active = true
    end
    return
  end

  clear_drag_tooltip()

  local mx, my = r.ImGui_GetMousePos(ctx)
  if not mx or mx ~= mx then
    return
  end

  local dl = (r.APIExists and r.APIExists("ImGui_GetForegroundDrawList"))
    and r.ImGui_GetForegroundDrawList(ctx)
    or r.ImGui_GetWindowDrawList(ctx)

  if #name > 30 then
    name = name:sub(1, 29) .. "..."
  end

  local over_target = state.seq_drop_target_idx ~= nil
  local hint
  if state.seq_drum_drop then
    hint = "Release to set this region's sample"
  elseif state.seq_candidate_drop then
    hint = "Release to save in this slot"
  elseif over_layer then
    local idx = state.seq_layering_drop_vert and state.seq_layering_drop_vert.idx
    hint = (idx == 1) and "Release to set the original sample" or "Release to set this layer"
  elseif over_target then
    hint = sample.is_layering_mix
      and "Release to apply layered mix"
      or "Release to swap track sample"
  elseif seq_drag_is_from_candidate() then
    hint = seq_region_sample_edit_region()
      and "Drop on the drum icon to set this region's sample"
      or "Drop on a candidate slot or the arrange"
  elseif state.seq_timeline_drop_time then
    hint = "Release to insert on this track"
  else
    hint = "Drag onto a sequencer track"
  end

  local dot_color = get_sample_dot_color(sample)
  local pulse = drag_pulse()

  local name_w, name_h = r.ImGui_CalcTextSize(ctx, name)
  local hint_w, hint_h = r.ImGui_CalcTextSize(ctx, hint)
  local dot_r = 5.0
  local pad = 8.0
  local gap = 7.0
  local line_gap = 3.0
  local text_block_w = math.max(name_w, hint_w)
  local chip_w = pad + dot_r * 2 + gap + text_block_w + pad
  local chip_h = pad + name_h + line_gap + hint_h + pad

  local x0 = mx + 18.0
  local y0 = my + 12.0
  local x1 = x0 + chip_w
  local y1 = y0 + chip_h

  r.ImGui_DrawList_AddRectFilled(dl, x0 + 2, y0 + 3, x1 + 2, y1 + 3, 0x00000070, 7.0)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, 0x1E2620F5, 7.0)

  local cr, cg, cb = extract_rgb_rrgbbaa(dot_color)
  local border = build_color_rrgbbaa(cr, cg, cb, math.floor(140 + 115 * pulse))
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, border, 7.0, 0, 1.5)

  local cx = x0 + pad + dot_r
  local cy = y0 + pad + name_h * 0.5
  local ghost_role = seq_icon_role_for_sample(sample)
  if not draw_seq_role_icon(dl, cx, cy, dot_r + 2.0, sample, dot_color, ghost_role) then
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, dot_r, dot_color, 16)
  end
  r.ImGui_DrawList_AddCircle(dl, cx, cy, dot_r + 1.5, border, 16, 1.0)

  local tx = x0 + pad + dot_r * 2 + gap
  r.ImGui_DrawList_AddText(dl, tx, y0 + pad, 0xFFFFFFFF, name)
  local hint_color = (over_target or over_layer) and 0x8FE0A6FF or 0x9FB2CCFF
  r.ImGui_DrawList_AddText(dl, tx, y0 + pad + name_h + line_gap, hint_color, hint)
end

function find_map_neighbor_sample(current, direction, required_tag)
  if not current or not current.path then
    return nil
  end

  local cx = current.x or 0.5
  local cy = current.y or 0.5
  local best = nil
  local best_dist = math.huge
  local tag_filter = required_tag and seq_trim_text(required_tag) or ""

  for _, s in ipairs(state.samples) do
    if s.path and s.path ~= current.path and s.x and s.y
      and not sample_scan_folder_unavailable(s)
      and (tag_filter == "" or sample_has_tag(s, tag_filter)) then
      if direction < 0 then
        local dx = cx - s.x
        if dx > 1e-5 then
          local dist = dx * dx + (cy - s.y) * (cy - s.y)
          if dist < best_dist then
            best_dist = dist
            best = s
          end
        end
      else
        local dx = s.x - cx
        if dx > 1e-5 then
          local dist = dx * dx + (cy - s.y) * (cy - s.y)
          if dist < best_dist then
            best_dist = dist
            best = s
          end
        end
      end
    end
  end

  return best
end

function seq_vary_role_is_specific(role)
  return role and role ~= "" and role ~= "default" and role ~= "other"
end

function seq_sample_matches_vary_role(sample, required_role)
  if not seq_vary_role_is_specific(required_role) then
    return true
  end
  if seq_icon_role_for_sample(sample) == required_role then
    return true
  end
  return sample_has_tag(sample, required_role)
end

function seq_normalize_vary_filter(text)
  return seq_trim_text(text):lower()
end

function seq_sample_matches_vary_filter_token(sample, needle)
  if not sample or not needle or needle == "" then
    return true
  end
  local name = string.lower(sample.name or "")
  if name ~= "" and string.find(name, needle, 1, true) then
    return true
  end
  if type(sample.tags) == "table" then
    for _, tag in ipairs(sample.tags) do
      if string.find(string.lower(tostring(tag or "")), needle, 1, true) then
        return true
      end
    end
  end
  local path = sample.path or ""
  local base = path:match("([^/\\]+)$") or path
  if base ~= "" and string.find(string.lower(base), needle, 1, true) then
    return true
  end
  local parent = path:match("([^/\\]+)[/\\][^/\\]+$")
  if parent and string.find(string.lower(parent), needle, 1, true) then
    return true
  end
  return false
end

function seq_sample_matches_vary_filter(sample, filter_text)
  local needle = seq_normalize_vary_filter(filter_text)
  if needle == "" then
    return true
  end
  for token in needle:gmatch("%S+") do
    if not seq_sample_matches_vary_filter_token(sample, token) then
      return false
    end
  end
  return true
end

function collect_map_samples_by_distance(origin, required_role, filter_text)
  local ranked = {}
  if not origin or not origin.path then
    return ranked
  end

  local cx = origin.x or 0.5
  local cy = origin.y or 0.5
  for _, s in ipairs(state.samples) do
    if s.path and s.path ~= origin.path and s.x and s.y
      and not sample_scan_folder_unavailable(s)
      and seq_sample_matches_vary_role(s, required_role)
      and seq_sample_matches_vary_filter(s, filter_text) then
      local dx = s.x - cx
      local dy = s.y - cy
      ranked[#ranked + 1] = { sample = s, dist = math.sqrt(dx * dx + dy * dy) }
    end
  end

  table.sort(ranked, function(a, b)
    if math.abs(a.dist - b.dist) < 1e-9 then
      return (a.sample.path or "") < (b.sample.path or "")
    end
    return a.dist < b.dist
  end)
  return ranked
end

seq_vary_rank_cache = {}
seq_vary_filter_hit_cache = {}

function clear_seq_vary_rank_cache()
  seq_vary_rank_cache = {}
  seq_vary_filter_hit_cache = {}
end

function seq_vary_filter_library_hits(filter_text)
  local needle = seq_normalize_vary_filter(filter_text)
  if needle == "" then
    return nil
  end
  seq_vary_filter_hit_cache = seq_vary_filter_hit_cache or {}
  local cached = seq_vary_filter_hit_cache[needle]
  if cached ~= nil then
    return cached
  end
  local n = 0
  for _, s in ipairs(state.samples or {}) do
    if s and s.path and not sample_scan_folder_unavailable(s)
        and seq_sample_matches_vary_filter(s, needle) then
      n = n + 1
    end
  end
  seq_vary_filter_hit_cache[needle] = n
  return n
end

function seq_vary_filter_has_no_hits(filter_text)
  return seq_vary_filter_library_hits(filter_text) == 0
end

function get_map_samples_ranked_from_path(base_path, required_role, filter_text)
  if state._clear_vary_rank_cache then
    clear_seq_vary_rank_cache()
    state._clear_vary_rank_cache = false
  end
  if not base_path then
    return {}
  end
  if not seq_vary_role_is_specific(required_role) then
    required_role = nil
  end
  filter_text = seq_normalize_vary_filter(filter_text)
  if filter_text == "" then
    filter_text = nil
  end
  local cache_key = base_path
  if required_role then
    cache_key = cache_key .. "\0" .. required_role
  end
  if filter_text then
    cache_key = cache_key .. "\0f:" .. filter_text
  end
  if seq_vary_rank_cache[cache_key] then
    return seq_vary_rank_cache[cache_key]
  end
  local origin = find_sample_by_path(base_path)
  local ranked = origin and collect_map_samples_by_distance(origin, required_role, filter_text) or {}
  seq_vary_rank_cache[cache_key] = ranked
  return ranked
end

function seq_vary_role_for_origin(slot, origin)
  local role = infer_seq_track_role(slot)
  if seq_vary_role_is_specific(role) then
    return role
  end
  role = seq_icon_role_for_sample(origin)
  if seq_vary_role_is_specific(role) then
    return role
  end
  return nil
end

function resolve_seq_note_sample(note, slot, vary_override, filter_text, origin_path)
  -- Locked, copied, or Shift+V-picked notes keep a pinned file. A live vary
  -- filter is a new constraint, so drop an unlocked auto-pin and re-pick.
  if note and type(note.frozen_sample_path) == "string" and note.frozen_sample_path ~= "" then
    if seq_path_exists(note.frozen_sample_path) then
      if seq_note_is_locked(note) or note.picked_sample
          or seq_normalize_vary_filter(filter_text) == "" then
        return note.frozen_sample_path, find_sample_by_path(note.frozen_sample_path)
      end
      seq_clear_frozen_sample(note)
    end
  end
  -- Track slot sample (or region override) is the vary origin.
  local base_path = origin_path or (slot and slot.sample_path) or (note and note.sample_path)
  if not base_path then
    return nil, nil
  end

  local vary = (type(vary_override) == "number") and vary_override or (note and note.sample_vary or 0.0)
  if vary <= 0.000001 then
    return base_path, find_sample_by_path(base_path)
  end

  local origin = find_sample_by_path(base_path)
  if not origin or origin.x == nil or origin.y == nil then
    return base_path, origin
  end

  -- Stay in the same drum/instrument category when possible, but a typed
  -- filter is the real constraint (perc + "bell" should still find bells).
  local role = seq_vary_role_for_origin(slot, origin)
  local ranked = get_map_samples_ranked_from_path(base_path, role, filter_text)
  if #ranked == 0 and seq_normalize_vary_filter(filter_text) ~= "" then
    ranked = get_map_samples_ranked_from_path(base_path, nil, filter_text)
  end
  if #ranked == 0 then
    return base_path, origin
  end

  local t = math.max(0.0, math.min(1.0, vary))
  local idx = math.max(1, math.min(#ranked, math.ceil(t * #ranked)))
  local picked = ranked[idx].sample
  return picked.path, picked
end

-- Sample Map Browser module: settings
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function settings_section_should_show(label)
  if not settings_search_active() then
    return true
  end
  if settings_matches(label) then
    return true
  end
  if label == "Scan Folders" then
    if settings_matches("Add Folder", "Rescan", "Browse", "Remove", "scan", "offline") then
      return true
    end
    local i
    for i = 1, #(state.folders or {}) do
      if settings_matches(state.folders[i]) then
        return true
      end
    end
    return false
  end
  if label == "Map" then
    return settings_matches(
      "Y axis", "Brightness", "Dominant frequency", "Weight",
      "Spectral centroid", "audible length", "pitch", "subby", "heavy"
    )
  end
  if label == "Dot Appearance" then
    return settings_matches(
      "Dot Radius", "Outline Size", "Outline Thickness",
      "Detection Size Multiplier", "Dot Color", "Outline Color", "Hover Color"
    )
  end
  if label == "Tag Layout" then
    return settings_matches(
      "Collapse children tags", "Drum", "Melodic", "Genre", "Library",
      "Off", "On", "Dynamic", "Window width", "threshold"
    )
  end
  if label == "Tag Colors" then
    if settings_matches("Presets", "Load Preset", "Save as Preset", "preset") then
      return true
    end
    local tag
    for tag in pairs(state.tag_colors or {}) do
      if settings_matches(tag) then
        return true
      end
    end
    return false
  end
  if label == "Sequencer Controls" then
    if settings_matches(
      "Track folder", "Group sequencer tracks in a folder",
      "Follow hovered notes in the arrange",
      "Show numbers on sample candidate slots",
      "Region item image", "Mouse wheel scrolling",
      "Mouse modifiers", "Reset to defaults", "TCP"
    ) then
      return true
    end
    local i
    for i = 1, #(SEQ_PARENT_IMAGE_STYLES or {}) do
      local style = SEQ_PARENT_IMAGE_STYLES[i]
      if style and settings_matches(style.label, style.id) then
        return true
      end
    end
    if settings_matches(
      "Vertical wheel scrolls the timeline",
      "Vertical wheel scrolls tracks", "classic", "natural", "trackpad"
    ) then
      return true
    end
    for i = 1, #(MOUSE_MOD_ACTIONS or {}) do
      local action = MOUSE_MOD_ACTIONS[i]
      if action and settings_matches(action.label, action.hint, action.id) then
        return true
      end
    end
    return settings_matches("Shift", "Alt", "Ctrl", "Cmd", "None")
  end
  if label == "Keyboard Shortcuts" then
    if settings_matches("Reset to defaults", "shortcut", "hotkey") then
      return true
    end
    local i
    for i = 1, #(KEYBOARD_SHORTCUT_ACTIONS or {}) do
      local action = KEYBOARD_SHORTCUT_ACTIONS[i]
      if action and settings_matches(
        action.label, action.hint, action.group, action.id,
        shortcut_display(action.id)
      ) then
        return true
      end
    end
    return false
  end
  if label == "Updates" then
    return settings_matches(
      "Update", "GitHub", "Download", "version", "Check for updates", "install"
    )
  end
  return false
end

function settings_render_search()
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local query = state.settings_search or ""
  local show_clear = query ~= ""
  local clear_w = 24
  local input_w = avail
  if show_clear then
    input_w = math.max(80, avail - clear_w - 8)
  end
  if r.ImGui_IsWindowAppearing and r.ImGui_IsWindowAppearing(ctx) and r.ImGui_SetKeyboardFocusHere then
    r.ImGui_SetKeyboardFocusHere(ctx)
  end
  r.ImGui_SetNextItemWidth(ctx, input_w)
  local changed, text
  if r.ImGui_InputTextWithHint then
    changed, text = r.ImGui_InputTextWithHint(ctx, "##settings_search", "Search settings…", query)
  else
    changed, text = r.ImGui_InputText(ctx, "##settings_search", query, 256)
  end
  seq_mark_text_input_item()
  if changed then
    state.settings_search = text or ""
  end
  local active = r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx)
  if active and query ~= "" and r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
      and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
    state.settings_search = ""
  end
  if show_clear then
    r.ImGui_SameLine(ctx, 0, 6)
    if draw_ui_button("settings_search_clear", nil, clear_w, 24, { icon = "close", compact = true }) then
      state.settings_search = ""
    end
  end
end

function settings_section(label, default_open)
  state.settings_section_open = state.settings_section_open or {}
  if state.settings_section_open[label] == nil then
    state.settings_section_open[label] = default_open and true or false
  end
  local searching = settings_search_active()
  local open = searching or (state.settings_section_open[label] and true or false)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local h = UI_METRICS.section_h
  r.ImGui_InvisibleButton(ctx, "##sec_" .. label, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  if (not searching) and r.ImGui_IsItemClicked(ctx, 0) then
    open = not open
    state.settings_section_open[label] = open
  end
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local bg = hovered and UI_THEME.surface_hvr or (open and UI_THEME.elevated or UI_THEME.surface)
  local border = hovered and UI_THEME.border_hvr or UI_THEME.border
  ui_draw_panel(dl, x0, y0, x1, y1, UI_METRICS.radius_ctrl, bg, border, hovered, active)
  if open then
    r.ImGui_DrawList_AddRectFilled(dl, x0 + 1, y0 + 6, x0 + 4, y1 - 6, UI_THEME.accent, 1.5)
  end
  local cy = (y0 + y1) * 0.5 + (active and 1.0 or 0.0)
  ui_button_draw_icon(dl, open and "chev_down" or "chev_right", x0 + 16, cy, 14, open and UI_THEME.accent_hvr or UI_THEME.text_dim)
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, x0 + 30, cy - th * 0.5, open and UI_THEME.text or UI_THEME.text_dim, label)
  state.settings_filter_section_title_hit = searching and settings_matches(label)
  return open
end

function settings_render_scan_folders()
  if settings_show("Add Folder", "scan", "folder") then
    if draw_ui_button("settings_add_folder", "Add Folder", nil, nil, { style = "primary" }) then
    local new_folder = ""

    -- Try JS_Dialog_BrowseForFolder first (from JS_ReaScriptAPI extension)
    if r.APIExists("JS_Dialog_BrowseForFolder") then
      local retval, selectedFolder = r.JS_Dialog_BrowseForFolder("Choose folder to scan", "")
      if retval == 1 and selectedFolder and selectedFolder ~= "" then
        new_folder = selectedFolder
        log("JS_Dialog_BrowseForFolder returned: " .. tostring(selectedFolder))
      else
        log("JS_Dialog_BrowseForFolder cancelled or failed. retval=" .. tostring(retval))
      end
    else
      log("JS_Dialog_BrowseForFolder not available - JS_ReaScriptAPI extension may not be installed")
    end

    -- Only show fallback dialog if JS dialog didn't work
    if new_folder == "" and not r.APIExists("JS_Dialog_BrowseForFolder") then
      r.ShowMessageBox("JS_ReaScriptAPI extension is required for folder browsing.\n\nPlease install it via ReaPack:\nExtensions > ReaPack > Browse Packages > Search for 'js_ReaScriptAPI'", "Extension Required", 0)
    end

    -- Normalize and validate folder path before adding
    if new_folder and new_folder ~= "" then
      new_folder = normalize_path(new_folder)
      if string.len(new_folder) < 2 or new_folder:match("^%d+$") then
        r.ShowMessageBox("Invalid folder path: " .. new_folder .. "\n\nPlease select a valid folder.", "Error", 0)
        log("Rejected invalid folder path: " .. new_folder)
      else
        local exists = false
        for _, f in ipairs(state.folders) do
          if f == new_folder then exists = true break end
        end
        if not exists then
          table.insert(state.folders, new_folder)
          refresh_scan_folder_availability()
          explorer_invalidate_cache(new_folder)
          save_config()
          log("Added folder: " .. new_folder)
          enqueue_scan(new_folder)
          sm_notify("Added folder; scanning " .. (new_folder:match("([^/]+)$") or new_folder) .. "…")
        else
          sm_notify("Folder is already in the list", "warn")
        end
      end
    end
  end
  end

  if #state.folders > 0 then
    if settings_show("Add Folder", "scan", "folder") then
      r.ImGui_SameLine(ctx)
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, string.format("%d folder%s", #state.folders, #state.folders == 1 and "" or "s"))
    end

    local child_flags = 0
    child_flags = sm_child_border_flag()

    -- Size the list to its contents (capped) so there is no large empty area.
    local row_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
    local visible_rows = math.min(#state.folders, 8)
    local list_h = visible_rows * row_h + 10
    if r.ImGui_BeginChild(ctx, "folder_list", 0, list_h, child_flags) then
      for idx, folder in ipairs(state.folders) do
        local norm_folder = normalize_path(folder)
        local offline = false
        local vol = volume_root_from_path(norm_folder)
        if (vol and state.missing_volumes[vol]) or state.missing_scan_folders[norm_folder] then
          offline = true
        end
        if settings_show(folder, offline and "offline" or nil, "Remove", "Rescan", "Browse") then
          if draw_ui_button("settings_remove_folder_" .. idx, "Remove", nil, nil, { style = "danger", compact = true }) then
            local in_folder = 0
            for _, s in ipairs(state.samples) do
              if s.path and sample_under_scan_folder(s.path, norm_folder) then
                in_folder = in_folder + 1
              end
            end
            local msg = string.format(
              "Remove this scan folder?\n\n%s\n\n%d analyzed sample%s from it will be removed from the library (files on disk are not touched).",
              folder, in_folder, in_folder == 1 and "" or "s"
            )
            if r.ShowMessageBox(msg, "Remove folder", 4) == 6 then
              table.remove(state.folders, idx)
              local removed = filter_samples_by_folders()
              refresh_scan_folder_availability()
              explorer_invalidate_cache()
              if #state.samples > 0 then
                layout_samples()
              end
              save_config()
              save_samples()
              sm_notify(string.format("Removed folder (%d sample%s)", removed or 0, removed == 1 and "" or "s"))
            end
            break
          end
          r.ImGui_SameLine(ctx)
          if draw_ui_button("settings_rescan_folder_" .. idx, "Rescan", nil, nil, { style = "primary", compact = true }) then
            enqueue_scan(folder)
          end
          r.ImGui_SameLine(ctx)
          if draw_ui_button("settings_browse_folder_" .. idx, "Browse", nil, nil, { compact = true }) then
            state.explorer_open = true
            state.explorer_open_dirs[norm_folder] = true
            explorer_invalidate_cache(norm_folder)
            save_config()
          end
          r.ImGui_SameLine(ctx)
          r.ImGui_AlignTextToFramePadding(ctx)
          if offline then
            r.ImGui_TextColored(ctx, UI_THEME.text_dim, folder .. "  (offline)")
          else
            r.ImGui_Text(ctx, folder)
          end
        end
      end
      r.ImGui_EndChild(ctx)
    end
  elseif settings_show("Add Folder", "scan", "folder") then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No folders yet. Click Add Folder to add scan folders.")
  end
end

function settings_render_map()
  if settings_show("Y axis", "Brightness", "Dominant frequency", "Weight", "audible length") then
    r.ImGui_Text(ctx, "Y axis")
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "How samples are spread vertically. X stays audible length.")
    r.ImGui_Spacing(ctx)
  end

  local axis = map_y_axis_id()
  if settings_show("Brightness", "Spectral centroid") then
    if draw_ui_radio("map_y_brightness", "Brightness", axis == "brightness") then
      apply_map_y_axis("brightness")
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Spectral centroid. Dark / thud at the bottom, clicky / bright at the top.")
    end
  end
  if settings_show("Dominant frequency", "pitch") then
    if draw_ui_radio("map_y_freq", "Dominant frequency", axis == "dominant_freq") then
      apply_map_y_axis("dominant_freq")
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Strongest pitch. Better for 808s, bass, and tonal samples.")
    end
  end
  if settings_show("Weight", "subby", "heavy") then
    if draw_ui_radio("map_y_weight", "Weight", axis == "weight") then
      apply_map_y_axis("weight")
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "How subby / heavy the sample is. Heavy at the top, light at the bottom.")
    end
  end
end

function settings_render_dot_appearance()
  if settings_show("Dot Radius") then
    local ret, dot_radius = draw_ui_number("dot_radius", "Dot Radius", state.dot_radius, 0.1, 1.0, "%.1f", 0.5, 10.0)
    if ret then
      state.dot_radius = dot_radius
      save_config()
    end
  end

  if settings_show("Outline Size") then
    local ret2, outline_size = draw_ui_number("outline_size", "Outline Size", state.dot_outline_size, 0.1, 1.0, "%.1f", 0.0, 20.0)
    if ret2 then
      state.dot_outline_size = outline_size
      save_config()
    end
  end

  if settings_show("Outline Thickness") then
    local ret3, outline_thickness = draw_ui_number("outline_thickness", "Outline Thickness", state.dot_outline_thickness, 0.1, 1.0, "%.1f", 0.5, 10.0)
    if ret3 then
      state.dot_outline_thickness = outline_thickness
      save_config()
    end
  end

  if settings_show("Detection Size Multiplier") then
    local ret4, detection_mult = draw_ui_number("detection_mult", "Detection Size Multiplier", state.dot_detection_multiplier, 0.5, 2.0, "%.1f", 1.0, 50.0)
    if ret4 then
      state.dot_detection_multiplier = detection_mult
      save_config()
    end
  end

  if settings_show("Dot Color", "Outline Color", "Hover Color") then
    r.ImGui_Spacing(ctx)
  end
  if settings_show("Dot Color") then
    local dot_changed, dot_color_result = draw_ui_color("dot_color", "Dot Color", state.dot_color or 0x44AA55)
    if dot_changed then
      state.dot_color = dot_color_result
      save_config()
      invalidate_sample_render_colors()
    end
  end

  if settings_show("Outline Color") then
    local outline_changed, outline_color_result = draw_ui_color("outline_color", "Outline Color", state.dot_outline_color or 0xFF00FF)
    if outline_changed then
      state.dot_outline_color = outline_color_result
      save_config()
    end
  end

  if settings_show("Hover Color") then
    local hover_changed, hover_color_result = draw_ui_color("hover_color", "Hover Color", state.dot_hover_color or 0xC84D)
    if hover_changed then
      state.dot_hover_color = hover_color_result
      save_config()
    end
  end
end

function settings_render_tag_layout()
  if settings_show("Collapse children tags", "Drum", "Melodic", "Genre", "Library", "Off", "On", "Dynamic") then
    r.ImGui_Text(ctx, "Collapse children tags")
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "When on, Drum / Melodic / Library sit on the search row. Select a parent to reveal its child tags on the right; they wrap to the next line if needed.")
    r.ImGui_Spacing(ctx)

    local mode = state.collapse_children_tags or "off"
    if settings_show("Off", "Collapse children tags") then
      if draw_ui_radio("collapse_off", "Off", mode == "off") then
        set_collapse_children_tags_mode("off")
      end
    end
    if settings_show("On", "Collapse children tags") then
      if draw_ui_radio("collapse_on", "On", mode == "on") then
        set_collapse_children_tags_mode("on")
      end
    end
    if settings_show("Dynamic", "window width", "Collapse children tags") then
      if draw_ui_radio("collapse_dyn", "Dynamic (by window width)", mode == "dynamic") then
        set_collapse_children_tags_mode("dynamic")
      end
    end
  end

  if settings_show("Dynamic width threshold", "Window width") then
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Dynamic width threshold")
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "In Dynamic mode, children tags collapse when the window is this wide or narrower.")
    local changed, width = draw_ui_number("collapse_width", "Window width (px)", state.collapse_children_tags_width or 1100, 10.0, 50.0, "%.0f", 400, 4000)
    if changed then
      state.collapse_children_tags_width = math.max(400, math.min(4000, width))
      save_config()
    end

    local current_w = state.main_window_rect and state.main_window_rect.w
    if current_w then
      local collapsed_now = collapse_children_tags_active()
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, string.format(
        "Current window width: %.0f px (%s)",
        current_w,
        collapsed_now and "collapsed" or "expanded"
      ))
    end
  end
end

function settings_render_tag_colors()
  -- Load tag presets (cached; re-read at most every 2 s)
  local tag_presets = sm_get_tag_presets()

  local preset_names = {}
  for name, _ in pairs(tag_presets) do
    table.insert(preset_names, name)
  end
  table.sort(preset_names)

  if #preset_names > 0 and settings_show("Presets", "Load Preset", "preset") then
    r.ImGui_Text(ctx, "Presets:")
    r.ImGui_SameLine(ctx)
    if draw_ui_button("settings_load_preset", "Load Preset") then
      r.ImGui_OpenPopup(ctx, "select_tag_preset")
    end

    if r.ImGui_BeginPopup(ctx, "select_tag_preset") then
      for _, preset_name in ipairs(preset_names) do
        if r.ImGui_Selectable(ctx, preset_name) then
          local preset = tag_presets[preset_name]
          if preset then
            for tag, color in pairs(preset) do
              state.tag_colors[tag] = color
            end
            state.current_preset_name = preset_name
            save_config()
          end
        end
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "|")
    r.ImGui_SameLine(ctx)
  end

  if settings_show("Save as Preset", "preset") then
    if draw_ui_button("settings_save_preset", "Save as Preset") then
      r.ImGui_OpenPopup(ctx, "save_tag_preset")
    end

    if r.ImGui_BeginPopup(ctx, "save_tag_preset") then
      r.ImGui_Text(ctx, "Preset Name:")
      local preset_name = state.settings_preset_name_buf or ""
      local changed, new_name = r.ImGui_InputText(ctx, "##preset_name", preset_name, 0)
      if changed then
        preset_name = new_name
        state.settings_preset_name_buf = new_name
      end

      if draw_ui_button("settings_save_preset_confirm", "Save") and preset_name ~= "" then
        tag_presets[preset_name] = {}
        for tag, color in pairs(state.tag_colors) do
          tag_presets[preset_name][tag] = color
        end
        state.current_preset_name = preset_name
        state.settings_preset_name_buf = nil

        sm_save_tag_presets(tag_presets)

        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
  end

  r.ImGui_Spacing(ctx)

  local sorted_tags = {}
  for tag, _ in pairs(state.tag_colors) do
    table.insert(sorted_tags, tag)
  end
  table.sort(sorted_tags)

  for _, tag in ipairs(sorted_tags) do
    if settings_show(tag) then
      local tag_color = state.tag_colors[tag]
      local color_changed, new_color = draw_ui_color("tag_color_" .. tag, tag, tag_color)
      if color_changed then
        state.tag_colors[tag] = new_color & 0xFFFFFF
        save_config()
      end
    end
  end
end

function settings_render_sequencer_controls()
  local drawn = false
  if settings_show("Track folder", "Group sequencer tracks in a folder", "TCP") then
    r.ImGui_Text(ctx, "Track folder")
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "New tracks created by this script go in a '" .. SEQ_TRACK_FOLDER_NAME .. "' folder in the TCP.")
    r.ImGui_Spacing(ctx)
    local group_on = state.group_seq_tracks_in_folder ~= false
    local group_changed, group_v = draw_ui_checkbox("settings_group_seq_folder", "Group sequencer tracks in a folder", group_on)
    if group_changed then
      state.group_seq_tracks_in_folder = group_v and true or false
      save_config()
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Turn off to create tracks at the end of the project instead.")
    end
    drawn = true
  end

  if settings_show("Follow hovered notes in the arrange") then
    if drawn then r.ImGui_Spacing(ctx) end
    local peek_on = state.seq_follow_hovered_item == true
    local peek_changed, peek_v = draw_ui_checkbox(
      "settings_follow_hovered_item",
      "Follow hovered notes in the arrange",
      peek_on
    )
    if peek_changed then
      state.seq_follow_hovered_item = peek_v and true or false
      save_config()
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "When a sequencer note is hovered, scroll its track into view and highlight the audio item.")
    end
    drawn = true
  end

  if settings_show("Show numbers on sample candidate slots") then
    if drawn then r.ImGui_Spacing(ctx) end
    local nums_on = state.seq_candidate_show_numbers ~= false
    local nums_changed, nums_v = draw_ui_checkbox(
      "settings_candidate_numbers",
      "Show numbers on sample candidate slots",
      nums_on
    )
    if nums_changed then
      state.seq_candidate_show_numbers = nums_v and true or false
      save_config()
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "1, 2, 3… inside each candidate square on sequencer tracks.")
    end
    drawn = true
  end

  local show_images = settings_show("Region item image")
  local i
  if not show_images then
    for i = 1, #(SEQ_PARENT_IMAGE_STYLES or {}) do
      local style = SEQ_PARENT_IMAGE_STYLES[i]
      if style and settings_show(style.label, style.id) then
        show_images = true
        break
      end
    end
  end
  if show_images then
    if drawn then
      r.ImGui_Spacing(ctx)
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
    end
    r.ImGui_Text(ctx, "Region item image")
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Tiled graphic on the Sample Map parent-track items. Transparent so the item color stays continuous.")
    r.ImGui_Spacing(ctx)
    local current_style = (state.seq_parent_item_image or "drum")
    for i = 1, #SEQ_PARENT_IMAGE_STYLES do
      local style = SEQ_PARENT_IMAGE_STYLES[i]
      if settings_show("Region item image", style.label, style.id) then
        if draw_ui_radio("seq_parent_img_" .. style.id, style.label, current_style == style.id) then
          if current_style ~= style.id then
            seq_set_parent_image_style(style.id)
          end
        end
      end
    end
    drawn = true
  end

  if settings_show(
    "Mouse wheel scrolling",
    "Vertical wheel scrolls the timeline",
    "Vertical wheel scrolls tracks",
    "classic", "natural", "trackpad"
  ) then
    if drawn then
      r.ImGui_Spacing(ctx)
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
    end
    r.ImGui_Text(ctx, "Mouse wheel scrolling")
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "How the wheel behaves over the sequencer timeline. Shift+horizontal scroll zooms the timeline.")
    r.ImGui_Spacing(ctx)

    if settings_show("Mouse wheel scrolling", "Vertical wheel scrolls the timeline", "classic") then
      if draw_ui_radio("seq_scroll_classic", "Vertical wheel scrolls the timeline (classic)", state.seq_scroll_mode ~= "natural") then
        if state.seq_scroll_mode ~= "v_as_h" then
          state.seq_scroll_mode = "v_as_h"
          save_config()
        end
      end
    end
    if settings_show("Mouse wheel scrolling", "Vertical wheel scrolls tracks", "natural", "trackpad") then
      if draw_ui_radio("seq_scroll_natural", "Vertical wheel scrolls tracks, horizontal wheel scrolls timeline", state.seq_scroll_mode == "natural") then
        if state.seq_scroll_mode ~= "natural" then
          state.seq_scroll_mode = "natural"
          save_config()
        end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Best for trackpads and the Magic Mouse, which can send a horizontal wheel.")
      end
    end
    drawn = true
  end

  local show_mods = settings_show("Mouse modifiers", "Reset to defaults")
  if not show_mods then
    for i = 1, #(MOUSE_MOD_ACTIONS or {}) do
      local action = MOUSE_MOD_ACTIONS[i]
      if action and settings_show(action.label, action.hint, action.id) then
        show_mods = true
        break
      end
    end
  end
  if show_mods then
    if drawn then
      r.ImGui_Spacing(ctx)
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
    end
    if settings_show("Mouse modifiers") then
      r.ImGui_Text(ctx, "Mouse modifiers")
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Assign which key activates each sequencer gesture.")
      r.ImGui_Spacing(ctx)
    end

    state.mouse_mods = state.mouse_mods or {}
    for i = 1, #MOUSE_MOD_ACTIONS do
      local action = MOUSE_MOD_ACTIONS[i]
      if settings_show("Mouse modifiers", action.label, action.hint, action.id) then
        local current = state.mouse_mods[action.id] or MOUSE_MOD_DEFAULTS[action.id] or "none"
        local combo_changed, choice = draw_ui_combo(
          "mmod_" .. action.id,
          action.label,
          mouse_mod_label(current),
          MOUSE_MOD_CHOICES,
          current,
          mouse_mod_label
        )
        if combo_changed then
          state.mouse_mods[action.id] = choice
          save_config()
        end
        if r.ImGui_IsItemHovered(ctx) and action.hint then
          r.ImGui_SetTooltip(ctx, action.hint)
        end
      end
    end

    if settings_show("Reset to defaults", "Mouse modifiers") then
      r.ImGui_Spacing(ctx)
      if draw_ui_button("settings_reset_mouse_mods", "Reset to defaults", nil, nil, { compact = true }) then
        state.seq_scroll_mode = "v_as_h"
        state.mouse_mods = {}
        for k, v in pairs(MOUSE_MOD_DEFAULTS) do
          state.mouse_mods[k] = v
        end
        save_config()
      end
    end
  end
end

function settings_render_keyboard_shortcuts()
  if settings_show("shortcut", "hotkey", "Click a shortcut") then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Click a shortcut, then press the new key. Right-click to restore the default. Click again or click elsewhere to cancel.")
    r.ImGui_Spacing(ctx)
  end

  if state.shortcut_capture_id then
    seq_capture_shortcut_key()
    if r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then
      state.shortcut_capture_click_cancel = true
    end
  end

  local last_group = nil
  for i = 1, #KEYBOARD_SHORTCUT_ACTIONS do
    local action = KEYBOARD_SHORTCUT_ACTIONS[i]
    local capturing = state.shortcut_capture_id == action.id
    local preview = capturing and "Press a key..." or shortcut_display(action.id)
    if capturing or settings_show(action.label, action.hint, action.group, action.id, preview) then
      if action.group ~= last_group then
        if last_group then
          r.ImGui_Spacing(ctx)
        end
        r.ImGui_Text(ctx, action.group)
        last_group = action.group
      end

      local conflict = (not capturing) and shortcut_conflict_label(action.id)
      local style = "default"
      if capturing then
        style = "primary"
      elseif conflict then
        style = "danger"
      end
      if draw_ui_button("kbd_" .. action.id, preview, 168, 24, { compact = true, style = style, selected = capturing }) then
        state.shortcut_capture_click_cancel = false
        if capturing then
          state.shortcut_capture_id = nil
        else
          state.shortcut_capture_id = action.id
        end
      end
      local btn_hovered = r.ImGui_IsItemHovered(ctx)
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then
        state.shortcut_capture_click_cancel = false
        state.shortcut_capture_id = nil
        shortcut_reset_one(action.id)
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, action.label)
      if btn_hovered or r.ImGui_IsItemHovered(ctx) then
        local hint = action.hint or ""
        if conflict then
          hint = (hint ~= "" and (hint .. "\n") or "") .. "Conflicts with: " .. conflict
        end
        hint = (hint ~= "" and (hint .. "\n") or "") .. "Right-click the key to restore the default."
        r.ImGui_SetTooltip(ctx, hint)
      end
    end
  end

  if state.shortcut_capture_click_cancel then
    state.shortcut_capture_id = nil
    state.shortcut_capture_click_cancel = false
  end

  if settings_show("Reset to defaults", "shortcut") then
    r.ImGui_Spacing(ctx)
    if draw_ui_button("settings_reset_keyboard_shortcuts", "Reset to defaults", nil, nil, { compact = true }) then
      shortcut_reset_all()
    end
  end
end

-- Settings are grouped by what they affect; each group gets a caption and
-- its sections stay individually collapsible (search expands everything).
function settings_groups()
  local groups = {
    { caption = "Library", sections = {
      { label = "Scan Folders", open = true, draw = settings_render_scan_folders },
    } },
    { caption = "Sample Map", sections = {
      { label = "Map", open = true, draw = settings_render_map },
      { label = "Dot Appearance", open = false, draw = settings_render_dot_appearance },
    } },
    { caption = "Tags", sections = {
      { label = "Tag Layout", open = false, draw = settings_render_tag_layout },
      { label = "Tag Colors", open = false, draw = settings_render_tag_colors },
    } },
    { caption = "Sequencer", sections = {
      { label = "Sequencer Controls", open = true, draw = settings_render_sequencer_controls },
    } },
    { caption = "General", sections = {
      { label = "Keyboard Shortcuts", open = false, draw = settings_render_keyboard_shortcuts },
    } },
  }
  if DrawSampleMapUpdateSettings then
    local general = groups[#groups].sections
    general[#general + 1] = {
      label = "Updates",
      open = SampleMapUpdateState and SampleMapUpdateState.show_update_icon,
      draw = function() DrawSampleMapUpdateSettings(ctx) end,
    }
  end
  return groups
end

function render_settings()
  if not state.settings_open then
    return
  end

  r.ImGui_SetNextWindowSize(ctx, 580, 680, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, "Settings", true, r.ImGui_WindowFlags_None())

  if visible then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)

    settings_render_search()
    r.ImGui_Spacing(ctx)

    -- Scrollable body; search stays pinned above and the footer below.
    local _, avail_y = r.ImGui_GetContentRegionAvail(ctx)
    local footer_h = 30
    local body_open = r.ImGui_BeginChild(ctx, "settings_body", 0, math.max(80, avail_y - footer_h))
    if body_open then
      local any_section = false
      for _, group in ipairs(settings_groups()) do
        local shown = {}
        for _, sec in ipairs(group.sections) do
          if settings_section_should_show(sec.label) then
            shown[#shown + 1] = sec
          end
        end
        if #shown > 0 then
          any_section = true
          ui_group_caption(group.caption)
          for _, sec in ipairs(shown) do
            if settings_section(sec.label, sec.open) then
              r.ImGui_Spacing(ctx)
              r.ImGui_Indent(ctx, 6)
              sec.draw()
              r.ImGui_Unindent(ctx, 6)
              r.ImGui_Spacing(ctx)
            end
          end
          r.ImGui_Spacing(ctx)
        end
      end

      if settings_search_active() and not any_section then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No settings match your search.")
      end
    end
    imgui_end_child(body_open)

    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Settings are saved globally and persist across projects.")

    r.ImGui_PopStyleVar(ctx, 2)
  end

  end_window(visible, true)

  -- Update settings_open state based on window open state
  if not open then
    state.settings_open = false
    state.shortcut_capture_id = nil
    state.shortcut_capture_click_cancel = false
  end
end


function draw_map_status_overlay(dl, x0, y0, width, height)
  if state.scan_running and #state.scan_queue > 0 then
    return
  end
  if state.scan_running and (state.incomplete_analysis_total or 0) > 0
      and (#state.analyzer_queue > 0 or #state.active_processes > 0) then
    return
  end

  local lines = {}
  if #state.scan_queue > 0 and not state.scan_running then
    lines[#lines + 1] = string.format(
      "Scan paused — %d file(s) left. Library → Resume Scan continues where it left off.",
      #state.scan_queue
    )
  elseif #state.samples == 0 then
    lines[#lines + 1] = "Use Library → Rescan to populate the map."
    if #state.folders > 0 then
      lines[#lines + 1] = "Folders configured: " .. #state.folders
    end
  else
    local filtered_count = map_cache.filtered_count or #state.samples
    if map_cache.dots_capped then
      lines[#lines + 1] = string.format(
        "Showing %d of %d in view (Zoom: %.1fx)",
        map_cache.draw_count or 0,
        map_cache.visible_total or 0,
        state.zoom
      )
    elseif filtered_count < #state.samples then
      lines[#lines + 1] = string.format(
        "Showing %d of %d samples (Zoom: %.1fx)",
        filtered_count,
        #state.samples,
        state.zoom
      )
    else
      lines[#lines + 1] = string.format("Showing %d samples on map (Zoom: %.1fx)", #state.samples, state.zoom)
    end
    local missing_volume_count = 0
    for _ in pairs(state.missing_volumes or {}) do
      missing_volume_count = missing_volume_count + 1
    end
    local missing_folder_count = 0
    for _ in pairs(state.missing_scan_folders) do
      missing_folder_count = missing_folder_count + 1
    end
    if missing_volume_count > 0 then
      lines[#lines + 1] = string.format(
        "%d removable drive(s) offline — gray dots unavailable",
        missing_volume_count
      )
    elseif missing_folder_count > 0 then
      lines[#lines + 1] = string.format(
        "%d scan folder(s) offline — gray dots unavailable",
        missing_folder_count
      )
    end
    if state.selected then
      lines[#lines + 1] = "Selected: " .. state.selected.name
    end
  end

  if #lines == 0 then
    return
  end

  -- Compact translucent card in the bottom-left corner: first line is the
  -- primary status, the rest are secondary notes.
  local line_h = 16.0
  local margin = 10.0
  local pad_x, pad_y = 10.0, 6.0
  local max_w = 0
  for _, line in ipairs(lines) do
    max_w = math.max(max_w, (r.ImGui_CalcTextSize(ctx, line)))
  end
  local card_w = math.min(max_w + pad_x * 2, math.max(40, width - margin * 2))
  local card_h = #lines * line_h + pad_y * 2 - 2
  local cx0 = x0 + margin
  local cy1 = y0 + height - margin
  local cy0 = cy1 - card_h
  if r.ImGui_DrawList_PushClipRect then
    r.ImGui_DrawList_PushClipRect(dl, x0, y0, x0 + width, y0 + height, true)
  end
  r.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx0 + card_w, cy1, 0x0B0E0CD0, UI_METRICS.radius_ctrl)
  r.ImGui_DrawList_AddRect(dl, cx0 + 0.5, cy0 + 0.5, cx0 + card_w - 0.5, cy1 - 0.5, UI_THEME.border, UI_METRICS.radius_ctrl, 0, 1.0)
  for i, line in ipairs(lines) do
    local ty = cy0 + pad_y + (i - 1) * line_h
    r.ImGui_DrawList_AddText(dl, cx0 + pad_x, ty, i == 1 and UI_THEME.text or UI_THEME.text_dim, line)
  end
  if r.ImGui_DrawList_PopClipRect then
    r.ImGui_DrawList_PopClipRect(dl)
  end
end

function clamp_map_pan(width, height)
  local max_pan = width * 0.5 * state.zoom
  state.pan_x = math.max(-max_pan, math.min(max_pan, state.pan_x))
  local min_pan_y = height * 0.5 * (1 - state.zoom)
  local max_pan_y = height * 0.5 * (state.zoom - 1)
  state.pan_y = math.max(min_pan_y, math.min(max_pan_y, state.pan_y))
end

function map_zoom_snap_target()
  state.zoom_log_vel = 0.0
  state.zoom_smooth_last_t = nil
  state.zoom_anchor_nx = nil
  state.zoom_anchor_ny = nil
  state.zoom_anchor_mx = nil
  state.zoom_anchor_my = nil
end

function map_zoom_is_active()
  return math.abs(state.zoom_log_vel or 0.0) > MAP_ZOOM_VEL_EPS
end

-- Keep a map-normalized point under the cursor while zoom changes.
function map_zoom_apply_anchored(old_zoom, new_zoom, mx, my, width, height, x0, y0, map_norm_x, map_norm_y)
  if not old_zoom or old_zoom <= 0 or not new_zoom then
    return
  end
  if map_norm_x == nil or map_norm_y == nil then
    local center_x = x0 + width * 0.5 + state.pan_x
    local center_y = y0 + height * 0.5 + state.pan_y
    map_norm_x = ((mx - center_x) / (width * old_zoom)) + 0.5
    map_norm_y = ((my - center_y) / (height * old_zoom)) + 0.5
  end
  state.zoom = new_zoom
  local new_center_x = mx - width * (map_norm_x - 0.5) * new_zoom
  local new_center_y = my - height * (map_norm_y - 0.5) * new_zoom
  state.pan_x = new_center_x - (x0 + width * 0.5)
  state.pan_y = new_center_y - (y0 + height * 0.5)
  clamp_map_pan(width, height)
end

function map_zoom_add_wheel(wheel, mx, my, width, height, x0, y0)
  if not wheel or wheel == 0 then
    return
  end
  local old_zoom = state.zoom or 1.0
  -- Apply the full wheel delta immediately (trackpad already sends smooth increments)
  local new_zoom = math.max(MAP_ZOOM_MIN, math.min(MAP_ZOOM_MAX, old_zoom * math.exp(wheel * MAP_ZOOM_WHEEL_GAIN)))
  map_zoom_apply_anchored(old_zoom, new_zoom, mx, my, width, height, x0, y0)

  -- Mouse notches are large discrete steps — add a short coast. Trackpad ticks stay 1:1.
  if math.abs(wheel) >= MAP_ZOOM_MOUSE_NOTCH then
    local kick = (wheel > 0 and 1 or -1) * MAP_ZOOM_COAST_VEL
    local vel = (state.zoom_log_vel or 0.0) + kick
    state.zoom_log_vel = math.max(-MAP_ZOOM_VEL_MAX, math.min(MAP_ZOOM_VEL_MAX, vel))
    state.zoom_smooth_last_t = r.time_precise()
  else
    -- Continuous trackpad input cancels any leftover mouse coast
    state.zoom_log_vel = 0.0
  end
end

function map_zoom_update_smooth(mx, my, width, height, x0, y0)
  local vel = state.zoom_log_vel or 0.0
  if math.abs(vel) < MAP_ZOOM_VEL_EPS then
    if vel ~= 0.0 then
      state.zoom_log_vel = 0.0
    end
    return false
  end

  local now = r.time_precise()
  local last = state.zoom_smooth_last_t or now
  local dt = math.max(0.0, math.min(0.05, now - last))
  state.zoom_smooth_last_t = now
  if dt <= 0 then
    return true
  end

  local old_zoom = state.zoom or 1.0
  local new_zoom = math.max(MAP_ZOOM_MIN, math.min(MAP_ZOOM_MAX, old_zoom * math.exp(vel * dt)))
  if (vel < 0 and new_zoom <= MAP_ZOOM_MIN) or (vel > 0 and new_zoom >= MAP_ZOOM_MAX) then
    state.zoom_log_vel = 0.0
  end
  map_zoom_apply_anchored(old_zoom, new_zoom, mx, my, width, height, x0, y0)
  state.zoom_log_vel = vel * (MAP_ZOOM_VEL_FRICTION ^ (dt * 60.0))
  if math.abs(state.zoom_log_vel) < MAP_ZOOM_VEL_EPS then
    state.zoom_log_vel = 0.0
  end
  return true
end

-- Don't treat a click as drag-audition until the mouse has moved this far.
-- Also ignores motion that happened while a slow preview was blocking.
MAP_AUDITION_DRAG_THRESHOLD_SQ = 8 * 8

-- Sample Map Browser module: persistence
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Persistence -------------------------------------------------------------
function is_valid_project(proj)
  if proj == nil or proj == false then
    return false
  end
  if r.ValidatePtr2 then
    local ok, valid = pcall(r.ValidatePtr2, 0, proj, "ReaProject*")
    if ok then
      return valid and true or false
    end
  end
  if r.ValidatePtr then
    local ok, valid = pcall(r.ValidatePtr, proj, "ReaProject*")
    if ok then
      return valid and true or false
    end
  end
  return type(proj) == "userdata"
end

function get_current_project()
  if r.EnumProjects then
    local proj = r.EnumProjects(-1, "")
    if is_valid_project(proj) then
      return proj
    end
  end
  return nil
end

function reset_seq_project_state()
  if state.seq_swap_saved_active_tags ~= nil then
    state.active_tags = {}
    for tag, active in pairs(state.seq_swap_saved_active_tags) do
      if active then
        state.active_tags[tag] = true
      end
    end
  end
  state.seq_tracks = {}
  state.selected_seq_track = nil
  state.seq_folder_guid = nil
  state.seq_swap_track_idx = nil
  state.seq_swap_track_id = nil
  state.seq_swap_backup_path = nil
  state.seq_swap_backup_name = nil
  state.seq_swap_region_id = nil
  state.seq_swap_backup_was_override = false
  state.seq_swap_saved_active_tags = nil
  state.seq_swap_return_view = nil
  state.seq_track_next_id = 1
  state.seq_panel_width = 240
  state.seq_timeline_drop_track_idx = nil
  state.seq_timeline_drop_time = nil
  state.seq_follow_arrange = true
  state.seq_view_start_qn = nil
  state.seq_view_span_qn = nil
  state.seq_grid_qn = 0.25
  state.seq_gen_style = "basic"
  state.seq_groove = "off"
  state.seq_regions = {}
  state.seq_patterns = {}
  state.seq_region_next_id = 1
  state.seq_pattern_next_id = 1
  state.seq_pool_next_id = 1
  state.selected_seq_region_id = nil
  state.seq_pattern_popup_last_style = nil
  state.seq_pattern_popup_last_strength = nil
  state.seq_kit_random_query = ""
  state.seq_kit_history = {}
  state.seq_kit_history_next_id = 1
  state.selected_seq_note = nil
  state.seq_note_drag = nil
  state.seq_expanded_tracks = {}
  state.seq_new_track_query = ""
  state.seq_param_drag = nil
  state.seq_note_edit_mode = nil
  state.seq_vary_filter_edit = nil
  state.seq_razors = {}
  state.seq_razor_drag = nil
  state.seq_region_drag = nil
  state.seq_region_rename = nil
  state.seq_random_popup_region_id = nil
  state.seq_random_popup_pending = nil
  state.seq_random_popup_snapshot = nil
  state.seq_random_popup_close = false
  state.seq_random_knob_drag = nil
  state.seq_random_sync_pending = nil
  state.seq_lane_zoom = 1.0
  state.seq_lane_h_drag = nil
  state.seq_track_reorder_drag = nil
  state.seq_track_menu_id = nil
  state.seq_track_menu_want_open = nil
  state.seq_skip_order_sync = nil
  state.seq_over_lane_resize = false
  state.seq_note_anims = {}
  state.seq_track_play_anims = {}
  state.seq_candidate_slide = {}
  state.seq_neighbor_popup = nil
  state.seq_minimap_popup = nil
  state.preview_history_popup = nil
  state.seq_nav_anchors = {}
  state.seq_layering_slot_id = nil
  state.seq_layering_drag = nil
  state.seq_layering_drop_vert = nil
  state.seq_layering_vert_hits = nil
  state.seq_layering_hover_side = nil
  state.seq_layering_ab = nil
  state.seq_grid_hover = nil
  state.seq_sample_start_session = {}
  state.seq_sample_vol_session = {}
  state.seq_header_start_drag = nil
  state.seq_header_vol_drag = nil
  state.seq_header_menu_sample = nil
  state.seq_last_proj_change = nil
  state.seq_skip_ingest = false
  state.seq_self_write_count = nil
  state.seq_arrange_fp = nil
  state.seq_arrange_fp_meta = nil
  state.seq_fp_touched = nil
  state.seq_fp_refresh_at = nil
  state.seq_self_write_at = nil
  state.seq_ingest_rescan = nil
  state.seq_ingest_stale_since = nil
  state.seq_ingest_pending_count = nil
  state.seq_ingest_pending_at = nil
  state.seq_ingest_hold_parent = false
  state.seq_ingest_save_due = nil
  state.seq_parent_items_ensured = false
  state.seq_stem_import = nil
  state.seq_stem_import_hover = false
  if seq_undo_clear_history then
    seq_undo_clear_history()
  end
end

function apply_seq_project_state(cfg)
  if type(cfg) ~= "table" then
    return
  end
  if cfg.seq_tracks and type(cfg.seq_tracks) == "table" then
    state.seq_tracks = {}
    for _, entry in ipairs(cfg.seq_tracks) do
      if type(entry) == "table" and entry.id then
        local slot = {
          id = entry.id,
          name = entry.name or "Track",
          reaper_track_guid = entry.reaper_track_guid,
          sample_path = entry.sample_path,
          sample_name = entry.sample_name,
          sample_tag = entry.sample_tag,
          volume = entry.volume,
          pan = entry.pan,
          mute = entry.mute,
          solo = entry.solo,
          overlap = entry.overlap,
          env = entry.env,
          layers = entry.layers,
          midi_lo = entry.midi_lo,
          midi_hi = entry.midi_hi,
          sample_candidates = entry.sample_candidates,
          sample_candidate_idx = entry.sample_candidate_idx,
          lane_h = (type(entry.lane_h) == "number" and entry.lane_h > 0) and entry.lane_h or nil,
          lane_h_enlarged = entry.lane_h_enlarged and true or nil,
        }
        seq_normalize_slot_mix(slot)
        table.insert(state.seq_tracks, slot)
        if type(entry.id) == "number" and entry.id >= state.seq_track_next_id then
          state.seq_track_next_id = entry.id + 1
        end
      end
    end
  end
  if cfg.selected_seq_track and type(cfg.selected_seq_track) == "number" then
    state.selected_seq_track = cfg.selected_seq_track
  end
  if type(cfg.seq_folder_guid) == "string" and cfg.seq_folder_guid ~= "" then
    state.seq_folder_guid = cfg.seq_folder_guid
  end
  if cfg.seq_panel_width and type(cfg.seq_panel_width) == "number" then
    state.seq_panel_width = math.max(140, math.min(cfg.seq_panel_width, 1600))
  end
  if type(cfg.seq_follow_arrange) == "boolean" then
    state.seq_follow_arrange = cfg.seq_follow_arrange
  end
  if type(cfg.seq_view_start_qn) == "number" then
    state.seq_view_start_qn = cfg.seq_view_start_qn
  end
  if type(cfg.seq_view_span_qn) == "number" and cfg.seq_view_span_qn > 0 then
    state.seq_view_span_qn = cfg.seq_view_span_qn
  end
  if type(cfg.seq_grid_qn) == "number" and cfg.seq_grid_qn > 0 then
    state.seq_grid_qn = cfg.seq_grid_qn
  end
  if type(cfg.seq_gen_style) == "string" and cfg.seq_gen_style ~= "" then
    state.seq_gen_style = cfg.seq_gen_style
  end
  if type(cfg.seq_groove) == "string" and cfg.seq_groove ~= "" then
    state.seq_groove = cfg.seq_groove
  end
  if type(cfg.seq_lane_zoom) == "number" and cfg.seq_lane_zoom > 0 then
    state.seq_lane_zoom = cfg.seq_lane_zoom
  end
  if cfg.seq_regions and type(cfg.seq_regions) == "table" then
    state.seq_regions = cfg.seq_regions
    for _, region in ipairs(state.seq_regions) do
      if type(region) == "table" and type(region.id) == "number" and region.id >= state.seq_region_next_id then
        state.seq_region_next_id = region.id + 1
      end
    end
  end
  if cfg.seq_patterns and type(cfg.seq_patterns) == "table" then
    state.seq_patterns = cfg.seq_patterns
  end
  if type(cfg.seq_region_next_id) == "number" then
    state.seq_region_next_id = math.max(state.seq_region_next_id, cfg.seq_region_next_id)
  end
  if type(cfg.seq_pattern_next_id) == "number" then
    state.seq_pattern_next_id = cfg.seq_pattern_next_id
  end
  if type(cfg.seq_pool_next_id) == "number" then
    state.seq_pool_next_id = cfg.seq_pool_next_id
  end
  if type(cfg.selected_seq_region_id) == "number" then
    state.selected_seq_region_id = cfg.selected_seq_region_id
  end
  if cfg.seq_expanded_tracks and type(cfg.seq_expanded_tracks) == "table" then
    state.seq_expanded_tracks = cfg.seq_expanded_tracks
  end
  if cfg.seq_kit_history and type(cfg.seq_kit_history) == "table" then
    state.seq_kit_history = cfg.seq_kit_history
    for _, entry in ipairs(state.seq_kit_history) do
      if type(entry) == "table" and type(entry.id) == "number" and entry.id >= state.seq_kit_history_next_id then
        state.seq_kit_history_next_id = entry.id + 1
      end
    end
  end
  if type(cfg.seq_kit_history_next_id) == "number" then
    state.seq_kit_history_next_id = math.max(state.seq_kit_history_next_id, cfg.seq_kit_history_next_id)
  end
  migrate_seq_region_grooves()
end

function build_seq_project_state_payload()
  return {
    version = 1,
    seq_tracks = state.seq_tracks,
    selected_seq_track = state.selected_seq_track,
    seq_folder_guid = state.seq_folder_guid,
    seq_panel_width = state.seq_panel_width,
    seq_follow_arrange = state.seq_follow_arrange,
    seq_view_start_qn = state.seq_view_start_qn,
    seq_view_span_qn = state.seq_view_span_qn,
    seq_grid_qn = state.seq_grid_qn,
    seq_gen_style = state.seq_gen_style,
    seq_groove = state.seq_groove,
    seq_lane_zoom = state.seq_lane_zoom,
    seq_regions = state.seq_regions,
    seq_patterns = state.seq_patterns,
    seq_region_next_id = state.seq_region_next_id,
    seq_pattern_next_id = state.seq_pattern_next_id,
    seq_pool_next_id = state.seq_pool_next_id,
    selected_seq_region_id = state.selected_seq_region_id,
    seq_expanded_tracks = state.seq_expanded_tracks,
    seq_kit_history = state.seq_kit_history,
    seq_kit_history_next_id = state.seq_kit_history_next_id,
  }
end

function save_seq_project_state(proj)
  if not r.SetProjExtState then
    return
  end
  proj = proj or get_current_project()
  if not is_valid_project(proj) then
    return
  end
  local ok, serialized = pcall(json_encode, build_seq_project_state_payload())
  if ok and type(serialized) == "string" then
    -- If the change count is where ingest last left it, whatever this write
    -- moves it by is ours, not an arrange edit to scan for.
    local count_before = r.GetProjectStateChangeCount and proj == get_current_project()
      and r.GetProjectStateChangeCount(0)
    local set_ok = pcall(r.SetProjExtState, proj, PROJ_EXT_SECTION, PROJ_EXT_KEY_SEQUENCER, serialized)
    if set_ok then
      state.seq_last_ext_state = serialized
      if count_before and state.seq_last_proj_change == count_before then
        state.seq_last_proj_change = r.GetProjectStateChangeCount(0)
      end
    end
  end
end

function load_seq_project_state(proj)
  proj = proj or get_current_project()
  reset_seq_project_state()
  state.seq_last_ext_state = nil
  if not is_valid_project(proj) then
    return
  end
  local loaded = false
  if r.GetProjExtState then
    local ok, serialized = r.GetProjExtState(proj, PROJ_EXT_SECTION, PROJ_EXT_KEY_SEQUENCER)
    if ok and ok ~= 0 and serialized and serialized ~= "" then
      local parse_ok, cfg = pcall(json_decode, serialized)
      if parse_ok and type(cfg) == "table" then
        apply_seq_project_state(cfg)
        loaded = true
        state.seq_last_ext_state = serialized
      end
    end
  end
  if loaded then
    legacy_seq_project_state = nil
  elseif legacy_seq_project_state and type(legacy_seq_project_state) == "table" then
    apply_seq_project_state(legacy_seq_project_state)
    legacy_seq_project_state = nil
    save_seq_project_state(proj)
  end
  -- The project's track faders were saved with it and may be newer than the
  -- stored slot mix (moved while the script was closed): read them, don't
  -- overwrite them.
  if seq_ingest_slot_mix_from_arrange then
    seq_ingest_slot_mix_from_arrange()
  end
end

function sync_project_state_if_needed()
  local proj = get_current_project()
  if not proj then
    -- Project is closing or none is active; keep in-memory state.
    return
  end
  -- REAPER can reuse a ReaProject pointer when another project is opened in the
  -- same tab, so the project file path is part of the identity.
  local proj_fn = ""
  if r.EnumProjects then
    local cur, fn = r.EnumProjects(-1, "")
    if cur == proj and type(fn) == "string" then
      proj_fn = fn
    end
  end
  local token = tostring(proj) .. "|" .. proj_fn
  if loaded_project_token ~= token then
    -- A pending save belongs to the old project; the code below decides
    -- whether that project may still be written. Keep only the config file.
    if state._config_save_due then
      state._config_save_due = nil
      save_config_file()
    end
    local same_pointer = loaded_project ~= nil and tostring(loaded_project) == tostring(proj)
    if same_pointer and r.GetProjExtState then
      -- Same pointer, new path: either "Save As" of this project, or another
      -- project opened into this tab. If the project still holds exactly what we
      -- last wrote/read, it is the same project: keep the in-memory state.
      local _, ext = r.GetProjExtState(proj, PROJ_EXT_SECTION, PROJ_EXT_KEY_SEQUENCER)
      -- An untitled project saved for the first time may not hold any state yet.
      local was_untitled = type(loaded_project_token) == "string" and loaded_project_token:match("|$") ~= nil
      if type(ext) == "string" and ((ext ~= "" and ext == state.seq_last_ext_state)
          or (ext == "" and was_untitled)) then
        save_seq_project_state(proj)
        loaded_project = proj
        loaded_project_token = token
        return
      end
    end
    -- Never write the old state into a pointer that may now be another project.
    if is_valid_project(loaded_project) and not same_pointer then
      save_seq_project_state(loaded_project)
    end
    load_seq_project_state(proj)
    loaded_project = proj
    loaded_project_token = token
  end
end

function load_config()
  local content = sm_read_nonempty_file(CONFIG_PATH)
  local success, cfg = false, nil
  if content then
    success, cfg = pcall(json_decode, content)
  end
  if not (success and type(cfg) == "table") then
    -- Missing, empty or corrupt config: fall back to the previous good copy.
    local bak_content = sm_read_nonempty_file(CONFIG_PATH .. ".bak")
    if bak_content then
      local ok_bak, cfg_bak = pcall(json_decode, bak_content)
      if ok_bak and type(cfg_bak) == "table" then
        log("Config file unreadable; using SampleMapBrowser.json.bak")
        content, success, cfg = bak_content, ok_bak, cfg_bak
      end
    end
  end
  if content then
    do
      if success and cfg and type(cfg) == "table" then
        -- Ensure folders is an array of strings (normalized)
        if cfg.folders and type(cfg.folders) == "table" then
          state.folders = {}
          for i, folder in ipairs(cfg.folders) do
            if type(folder) == "string" then
              table.insert(state.folders, normalize_path(folder))
            end
          end
        else
          state.folders = {}
        end
        state.map_seed = cfg.map_seed or 1337
        if cfg.map_y_axis == "brightness" or cfg.map_y_axis == "dominant_freq" or cfg.map_y_axis == "weight" then
          state.map_y_axis = cfg.map_y_axis
        else
          state.map_y_axis = "brightness"
        end
        -- Zoom and pan are not saved - always start at defaults
        -- Load dot customization settings
        state.dot_radius = cfg.dot_radius or 2.0
        state.dot_outline_size = cfg.dot_outline_size or 4.0
        state.dot_outline_thickness = cfg.dot_outline_thickness or 3.0
        -- Load colors (RGB format)
        if cfg.dot_color then
          state.dot_color = cfg.dot_color
        elseif cfg.dot_color_r then
          -- Convert old RGB component format to RGB color value
          state.dot_color = build_rgb(cfg.dot_color_r or 68, cfg.dot_color_g or 170, cfg.dot_color_b or 85)
        else
          state.dot_color = 0x44AA55
        end
        if cfg.dot_outline_color then
          state.dot_outline_color = cfg.dot_outline_color
        elseif cfg.dot_outline_color_r then
          state.dot_outline_color = build_rgb(cfg.dot_outline_color_r or 255, cfg.dot_outline_color_g or 0, cfg.dot_outline_color_b or 255)
        else
          state.dot_outline_color = 0xFF00FF
        end
        if cfg.dot_hover_color then
          state.dot_hover_color = cfg.dot_hover_color
        elseif cfg.dot_hover_color_r then
          state.dot_hover_color = build_rgb(cfg.dot_hover_color_r or 200, cfg.dot_hover_color_g or 76, cfg.dot_hover_color_b or 77)
        else
          state.dot_hover_color = 0xC84D
        end
        state.dot_detection_multiplier = cfg.dot_detection_multiplier or 16.0
        -- Load preview volume
        state.preview_volume = cfg.preview_volume or 1.0
        -- Load tag colors
        if cfg.tag_colors and type(cfg.tag_colors) == "table" then
          for tag, color in pairs(cfg.tag_colors) do
            if type(color) == "number" then
              state.tag_colors[tag] = color
            end
          end
        end
        if cfg.active_view == "explorer" then
          state.active_view = "sample_map"
          state.explorer_open = true
        elseif cfg.active_view == "sample_map" or cfg.active_view == "sequencer" then
          state.active_view = cfg.active_view
        end
        if type(cfg.explorer_open) == "boolean" then
          state.explorer_open = cfg.explorer_open
        end
        if cfg.explorer_docked == true or cfg.explorer_docked == "sample_map" then
          state.explorer_docked = "sample_map"
        elseif cfg.explorer_docked == "sequencer" then
          state.explorer_docked = "sequencer"
        else
          state.explorer_docked = false
        end
        if type(cfg.explorer_width) == "number" then
          state.explorer_width = math.max(220, math.min(900, cfg.explorer_width))
        end
        if type(cfg.explorer_hide_empty) == "boolean" then
          state.explorer_hide_empty = cfg.explorer_hide_empty
        end
        if cfg.custom_tags and type(cfg.custom_tags) == "table" then
          state.custom_tags = {}
          for path, tags in pairs(cfg.custom_tags) do
            if type(path) == "string" and type(tags) == "table" then
              local cleaned = {}
              for _, tag in ipairs(tags) do
                if type(tag) == "string" and tag ~= "" then
                  cleaned[#cleaned + 1] = tag
                end
              end
              if #cleaned > 0 then
                state.custom_tags[normalize_path(path)] = cleaned
              end
            end
          end
        end
        if cfg.deleted_tags and type(cfg.deleted_tags) == "table" then
          state.deleted_tags = {}
          for key, on in pairs(cfg.deleted_tags) do
            if type(key) == "string" and key ~= "" and on then
              state.deleted_tags[string.lower(key)] = true
            elseif type(on) == "string" and on ~= "" then
              state.deleted_tags[string.lower(on)] = true
            end
          end
        end
        if cfg.explorer_open_dirs and type(cfg.explorer_open_dirs) == "table" then
          state.explorer_open_dirs = {}
          for path, open in pairs(cfg.explorer_open_dirs) do
            if type(path) == "string" and open then
              state.explorer_open_dirs[normalize_path(path)] = true
            end
          end
        end
        -- Sequencer scroll behavior
        if cfg.seq_scroll_mode == "v_as_h" or cfg.seq_scroll_mode == "natural" then
          state.seq_scroll_mode = cfg.seq_scroll_mode
        end
        if type(cfg.seq_parent_item_image) == "string" and cfg.seq_parent_item_image ~= "" then
          state.seq_parent_item_image = cfg.seq_parent_item_image
        end
        if type(cfg.seq_follow_hovered_item) == "boolean" then
          state.seq_follow_hovered_item = cfg.seq_follow_hovered_item
        end
        if type(cfg.group_seq_tracks_in_folder) == "boolean" then
          state.group_seq_tracks_in_folder = cfg.group_seq_tracks_in_folder
        end
        if type(cfg.seq_candidate_show_numbers) == "boolean" then
          state.seq_candidate_show_numbers = cfg.seq_candidate_show_numbers
        end
        -- Customizable mouse modifiers (validate each value)
        if cfg.mouse_mods and type(cfg.mouse_mods) == "table" then
          local valid = { none = true, shift = true, alt = true, ctrl = true, cmd = true }
          state.mouse_mods = state.mouse_mods or {}
          for action, default in pairs(MOUSE_MOD_DEFAULTS) do
            local v = cfg.mouse_mods[action]
            state.mouse_mods[action] = (type(v) == "string" and valid[v]) and v or default
          end
        end
        if cfg.keyboard_shortcuts and type(cfg.keyboard_shortcuts) == "table" then
          state.keyboard_shortcuts = {}
          for id, spec in pairs(cfg.keyboard_shortcuts) do
            if type(id) == "string" and type(spec) == "table" and type(spec.key) == "string" then
              state.keyboard_shortcuts[id] = {
                key = spec.key,
                shift = spec.shift and true or nil,
                alt = spec.alt and true or nil,
                ctrl = spec.ctrl and true or nil,
                cmd = spec.cmd and true or nil,
                cmdctrl = spec.cmdctrl and true or nil,
              }
            end
          end
        end
        if cfg.collapse_children_tags == "on"
            or cfg.collapse_children_tags == "off"
            or cfg.collapse_children_tags == "dynamic" then
          state.collapse_children_tags = cfg.collapse_children_tags
        end
        if type(cfg.collapse_children_tags_width) == "number" then
          state.collapse_children_tags_width = math.max(400, math.min(4000, cfg.collapse_children_tags_width))
        end
        if type(cfg.tag_parent_map) == "table" then
          state.tag_parent_map = {}
          for child, parent in pairs(cfg.tag_parent_map) do
            if type(child) == "string" and type(parent) == "string" and child ~= "" and parent ~= "" then
              state.tag_parent_map[string.lower(child)] = parent
            end
          end
        end
        if type(cfg.custom_tag_parents) == "table" then
          state.custom_tag_parents = {}
          for _, parent in ipairs(cfg.custom_tag_parents) do
            if type(parent) == "table" and type(parent.id) == "string" and type(parent.label) == "string" then
              state.custom_tag_parents[#state.custom_tag_parents + 1] = {
                id = parent.id,
                label = parent.label,
              }
            end
          end
        end
        if type(cfg.seq_tracks) == "table"
            or type(cfg.seq_regions) == "table"
            or type(cfg.seq_patterns) == "table" then
          legacy_seq_project_state = {
            seq_tracks = cfg.seq_tracks,
            selected_seq_track = cfg.selected_seq_track,
            seq_panel_width = cfg.seq_panel_width,
            seq_follow_arrange = cfg.seq_follow_arrange,
            seq_view_start_qn = cfg.seq_view_start_qn,
            seq_view_span_qn = cfg.seq_view_span_qn,
            seq_grid_qn = cfg.seq_grid_qn,
            seq_gen_style = cfg.seq_gen_style,
            seq_groove = cfg.seq_groove,
            seq_lane_zoom = cfg.seq_lane_zoom,
            seq_regions = cfg.seq_regions,
            seq_patterns = cfg.seq_patterns,
            seq_region_next_id = cfg.seq_region_next_id,
            seq_pattern_next_id = cfg.seq_pattern_next_id,
            seq_pool_next_id = cfg.seq_pool_next_id,
            selected_seq_region_id = cfg.selected_seq_region_id,
            seq_expanded_tracks = cfg.seq_expanded_tracks,
            seq_kit_history = cfg.seq_kit_history,
            seq_kit_history_next_id = cfg.seq_kit_history_next_id,
          }
        end
        state.sample_map_floating = cfg.sample_map_floating and true or false
        state.sequencer_floating = cfg.sequencer_floating and true or false
        local function copy_flag_map(src)
          local copy = {}
          if type(src) ~= "table" then
            return copy
          end
          for key, on in pairs(src) do
            if on then
              copy[key] = true
            end
          end
          return copy
        end
        local function copy_path_list(src)
          local copy = {}
          if type(src) ~= "table" then
            return copy
          end
          for _, path in ipairs(src) do
            if type(path) == "string" and path ~= "" then
              copy[#copy + 1] = path
            end
          end
          return copy
        end
        state.map_tabs = {}
        if type(cfg.map_tabs) == "table" then
          for _, raw in ipairs(cfg.map_tabs) do
            if type(raw) == "table" then
              local axis = raw.map_y_axis
              if axis ~= "brightness" and axis ~= "dominant_freq" and axis ~= "weight" then
                axis = state.map_y_axis
              end
              local tab_id = tonumber(raw.id)
              if not tab_id then
                tab_id = #(state.map_tabs) + 1
              end
              state.map_tabs[#state.map_tabs + 1] = {
                id = tab_id,
                title = (type(raw.title) == "string" and raw.title ~= "") and raw.title or nil,
                filter = type(raw.filter) == "string" and raw.filter or "",
                active_tags = copy_flag_map(raw.active_tags),
                folder_filter_paths = copy_path_list(raw.folder_filter_paths),
                zoom = math.max(MAP_ZOOM_MIN, math.min(MAP_ZOOM_MAX, tonumber(raw.zoom) or 1.0)),
                pan_x = tonumber(raw.pan_x) or 0.0,
                pan_y = tonumber(raw.pan_y) or 0.0,
                view_cx = tonumber(raw.view_cx),
                view_cy = tonumber(raw.view_cy),
                map_y_axis = axis,
                selected_tag_parents = copy_flag_map(raw.selected_tag_parents),
              }
            end
          end
        end
        state.map_tab_active_id = tonumber(cfg.map_tab_active_id) or 1
        state.map_tab_next_id = tonumber(cfg.map_tab_next_id) or 1
        if type(cfg.map_ui_layout) == "table" then
          state.map_ui_layout = cfg.map_ui_layout
        end
        log("Loaded config: " .. #state.folders .. " folder(s)")
        if #state.folders > 0 then
          for i, folder in ipairs(state.folders) do
            log("  Folder " .. i .. ": " .. folder)
          end
        end
      else
        log("Config file exists but couldn't parse it: " .. tostring(cfg))
      end
    end
  else
    log("No config file found, starting fresh")
  end
  if ensure_map_tabs then
    ensure_map_tabs()
  end
  if apply_map_tab_view and find_map_tab then
    local tab = find_map_tab(state.map_tab_active_id)
    if tab then
      apply_map_tab_view(tab)
    end
  end
end


function serialize_table(t, indent)
  indent = indent or ""
  local result = "{\n"
  for k, v in pairs(t) do
    result = result .. indent .. "  "
    if type(k) == "string" then
      result = result .. "[" .. string.format("%q", k) .. "]"
    else
      result = result .. '[' .. tostring(k) .. ']'
    end
    result = result .. " = "
    if type(v) == "table" then
      result = result .. serialize_table(v, indent .. "  ")
    elseif type(v) == "string" then
      result = result .. string.format("%q", v)
    else
      result = result .. tostring(v)
    end
    result = result .. ",\n"
  end
  result = result .. indent .. "}"
  return result
end

-- Tag colour presets: the user's copy (tag_presets.lua, gitignored) wins over the
-- shipped defaults (tag_presets.default.lua). Kept in memory; re-read at most every 2 s.
SM_TAG_PRESETS_PATH = CONFIG_DIR .. "/tag_presets.lua"
SM_TAG_PRESETS_DEFAULT_PATH = CONFIG_DIR .. "/tag_presets.default.lua"

function sm_read_tag_presets_file()
  local sources = { SM_TAG_PRESETS_PATH, SM_TAG_PRESETS_PATH .. ".bak", SM_TAG_PRESETS_DEFAULT_PATH }
  for i = 1, #sources do
    local content = sm_read_nonempty_file(sources[i])
    if content then
      local chunk = load(content, "@tag_presets.lua", "t", {})
      if chunk then
        local ok, presets = pcall(chunk)
        if ok and type(presets) == "table" then
          return presets
        end
      end
    end
  end
  return {}
end

function sm_get_tag_presets(force)
  local now = r.time_precise()
  if force or type(state.tag_presets_cache) ~= "table"
      or (now - (state.tag_presets_cache_time or 0)) > 2.0 then
    state.tag_presets_cache = sm_read_tag_presets_file()
    state.tag_presets_cache_time = now
  end
  return state.tag_presets_cache
end

function sm_save_tag_presets(presets)
  state.tag_presets_cache = presets
  state.tag_presets_cache_time = r.time_precise()
  local ok_ser, content = pcall(serialize_table, presets)
  if not ok_ser then
    log("Failed to serialize tag presets: " .. tostring(content))
    return false
  end
  local ok, err = sm_atomic_write(SM_TAG_PRESETS_PATH, "return " .. content)
  if not ok then
    sm_notify("Could not save tag presets: " .. tostring(err), "error")
  end
  return ok
end

-- Edits call save_config() often, several times per click, and each call
-- wrote the config file and re-encoded the whole sequencer state. Requests
-- are now coalesced and written once, shortly after the last one
-- (sm_flush_config_save runs every frame). Shutdown writes immediately.
SM_CONFIG_SAVE_DELAY = 0.35

function save_config()
  state._config_save_due = (r.time_precise and r.time_precise() or os.clock()) + SM_CONFIG_SAVE_DELAY
end

function sm_flush_config_save(force)
  local due = state._config_save_due
  if not due then
    return false
  end
  if not force and (r.time_precise and r.time_precise() or os.clock()) < due then
    return false
  end
  save_config_now()
  return true
end

function save_config_now()
  state._config_save_due = nil
  save_config_file()
  save_seq_project_state(loaded_project or get_current_project())
end

function save_config_file()
  if snapshot_active_map_tab then
    snapshot_active_map_tab()
  end
  local cfg = {
    folders = state.folders,
    map_seed = state.map_seed,
    map_y_axis = state.map_y_axis,
    -- Save dot customization settings
    dot_radius = state.dot_radius,
    dot_outline_size = state.dot_outline_size,
    dot_outline_thickness = state.dot_outline_thickness,
    dot_color = state.dot_color,
    dot_outline_color = state.dot_outline_color,
    dot_hover_color = state.dot_hover_color,
    dot_detection_multiplier = state.dot_detection_multiplier,
    preview_volume = state.preview_volume,
    tag_colors = state.tag_colors,
    active_view = state.active_view,
    seq_scroll_mode = state.seq_scroll_mode,
    seq_parent_item_image = state.seq_parent_item_image or "drum",
    seq_follow_hovered_item = state.seq_follow_hovered_item == true,
    group_seq_tracks_in_folder = state.group_seq_tracks_in_folder ~= false,
    seq_candidate_show_numbers = state.seq_candidate_show_numbers ~= false,
    mouse_mods = state.mouse_mods,
    keyboard_shortcuts = state.keyboard_shortcuts,
    collapse_children_tags = state.collapse_children_tags,
    collapse_children_tags_width = state.collapse_children_tags_width,
    custom_tags = state.custom_tags,
    deleted_tags = state.deleted_tags,
    explorer_open = state.explorer_open and true or false,
    explorer_docked = state.explorer_docked or false,
    explorer_width = state.explorer_width,
    explorer_open_dirs = state.explorer_open_dirs,
    explorer_hide_empty = state.explorer_hide_empty and true or false,
    tag_parent_map = state.tag_parent_map,
    custom_tag_parents = state.custom_tag_parents,
    sample_map_floating = state.sample_map_floating and true or false,
    sequencer_floating = state.sequencer_floating and true or false,
    map_tabs = state.map_tabs,
    map_tab_active_id = state.map_tab_active_id,
    map_tab_next_id = state.map_tab_next_id,
    map_ui_layout = map_ui_clone(state.map_ui_layout) or state.map_ui_layout,
  }
  local ok_enc, json_str = pcall(json_encode, cfg)
  local saved, save_err = false, nil
  if ok_enc and type(json_str) == "string" then
    saved, save_err = sm_atomic_write(CONFIG_PATH, json_str)
  else
    save_err = "encode failed: " .. tostring(json_str)
  end
  if saved then
    log("Saved config with " .. #state.folders .. " folder(s)")
  else
    sm_notify("Could not save settings: " .. tostring(save_err), "error")
  end
end


-- Run external Python analyzer to compute metadata (e.g., frequency/RMS)
-- Expected JSON output: { dominant_freq, brightness, sub_weight, rms_energy, ... }
function run_external_analyzer(path)
  local analyzer_start = r.time_precise()
  
  if not analyzer_script_exists() then
    return nil, "analyzer script missing"
  end

  local t1 = r.time_precise()
  local cmd = table.concat({
    shell_escape(PYTHON_BIN),
    shell_escape(EXTERNAL_ANALYZER),
    shell_escape(path)
  }, " ")

  -- Try to capture both stdout and stderr
  -- On macOS, we can redirect stderr to stdout with 2>&1
  local cmd_with_stderr = cmd .. " 2>&1"
  local pipe = io.popen(cmd_with_stderr, "r")
  if not pipe then
    return nil, "failed to start analyzer"
  end
  local spawn_time = (r.time_precise() - t1) * 1000

  local t2 = r.time_precise()
  local output = pipe:read("*all")
  local ok, why, code = pipe:close()
  local exec_time = (r.time_precise() - t2) * 1000
  
  if not ok then
    return nil, "analyzer process failed"
  end

  if not output or output == "" then
    return nil, "empty analyzer output"
  end

  local t3 = r.time_precise()
  -- stderr is merged in; decode only the JSON object so warnings don't spoil it.
  local json_s, json_e = output:find("{", 1, true), output:match(".*()}")
  local json_text = (json_s and json_e and json_e > json_s) and output:sub(json_s, json_e) or output
  local success, data = pcall(json_decode, json_text)
  local parse_time = (r.time_precise() - t3) * 1000
  
  local total_analyzer_time = (r.time_precise() - analyzer_start) * 1000
  
  if success and type(data) == "table" then
    -- Remove debug key before returning (don't store it in sample data)
    data._debug = nil
    
    -- Analyzer timing removed - use scan logs instead
    
    return data, nil
  end

  return nil, "invalid analyzer JSON"
end


ANALYZER_SCRIPT_OK = nil

function analyzer_script_exists()
  if ANALYZER_SCRIPT_OK == true then
    return true
  end
  if ANALYZER_SCRIPT_OK == false then
    return false
  end
  local fh = io.open(EXTERNAL_ANALYZER, "r")
  if fh then
    fh:close()
    ANALYZER_SCRIPT_OK = true
    return true
  end
  ANALYZER_SCRIPT_OK = false
  return false
end

function analyzer_work_dir()
  if state.analyzer_work_dir and state.analyzer_work_dir ~= "" then
    return state.analyzer_work_dir
  end
  local tmp
  if SM_IS_WINDOWS then
    tmp = os.getenv("TEMP") or os.getenv("TMP") or "C:/Windows/Temp"
  else
    tmp = os.getenv("TMPDIR") or "/tmp"
  end
  tmp = tmp:gsub("\\", "/")
  if tmp:sub(-1) == "/" then
    tmp = tmp:sub(1, -2)
  end
  state.analyzer_work_dir = tmp .. "/sma_workers_" .. tostring(os.time())
  if r.RecursiveCreateDirectory then
    r.RecursiveCreateDirectory(state.analyzer_work_dir, 0)
  else
    os.execute("mkdir -p " .. shell_escape(state.analyzer_work_dir))
  end
  return state.analyzer_work_dir
end

-- Pid written by the worker (SampleMapAnalyzer.py --worker) into pid_<slot>.
function sm_analyzer_worker_pid(w)
  if not w or not w.pid_path then
    return nil
  end
  local f = io.open(w.pid_path, "r")
  if not f then
    return nil
  end
  local pid = tonumber((f:read("*l") or ""):match("%d+"))
  f:close()
  if pid and pid > 1 then
    w.pid_seen = true
    return pid
  end
  return nil
end

function sm_kill_pid(pid)
  pid = tonumber(pid)
  if not pid or pid <= 1 then
    return
  end
  if SM_IS_WINDOWS then
    os.execute(string.format("taskkill /F /PID %d >NUL 2>&1", pid))
  else
    os.execute(string.format("kill %d >/dev/null 2>&1", pid))
  end
end

-- Stop one worker without blocking: ask it to quit, kill it if it is busy
-- (or force is set) and its pid is known, then close the pipe.
-- Returns false when the pipe was left open because closing could block.
function sm_stop_analyzer_worker(w, force)
  if not w then
    return true
  end
  if w.quit_path then
    pcall(function()
      local qf = io.open(w.quit_path, "w")
      if qf then
        qf:write("1")
        qf:close()
      end
    end)
  end
  local pid = sm_analyzer_worker_pid(w)
  if pid and (force or w.path) then
    sm_kill_pid(pid)
  elseif w.path then
    -- Busy and no pid: pclose would wait for the job to finish; leave it.
    return false
  end
  if w.pipe then
    pcall(function()
      w.pipe:close()
    end)
    w.pipe = nil
  end
  return true
end

-- Replace a dead or hung worker with a fresh process in the same slot (in place).
function sm_restart_analyzer_worker(w)
  if not w then
    return false
  end
  if not sm_stop_analyzer_worker(w, true) then
    return false
  end
  if w.pid_path then
    os.remove(w.pid_path)
  end
  local nw = start_analyzer_worker(w.slot)
  if not nw then
    return false
  end
  for k in pairs(w) do
    w[k] = nil
  end
  for k, v in pairs(nw) do
    w[k] = v
  end
  return true
end

-- False once a worker that has written its pid file removed it again (idle exit / crash).
function sm_analyzer_worker_alive(w)
  if not w then
    return false
  end
  if sm_analyzer_worker_pid(w) then
    return true
  end
  if not w.pid_seen then
    -- Still starting up (or an older analyzer script without pid files).
    return true
  end
  return false
end

function sm_analyzer_paths_equal(a, b)
  local function norm(p)
    p = tostring(p or ""):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    return p
  end
  return norm(a) == norm(b)
end

function write_worker_file(path, contents)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return false
  end
  f:write(contents or "")
  f:close()
  os.remove(path)
  local ok, err = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return false, err
  end
  return true
end

function stop_analyzer_workers(requeue)
  local workers = state.analyzer_workers or {}
  -- Signal every worker first so idle ones exit in parallel.
  for _, w in ipairs(workers) do
    if w.quit_path then
      pcall(function()
        local qf = io.open(w.quit_path, "w")
        if qf then
          qf:write("1")
          qf:close()
        end
      end)
    end
  end
  for _, w in ipairs(workers) do
    if requeue and w.path and w.path ~= "" then
      table.insert(state.analyzer_queue, 1, w.path)
      if w.mode then
        state.analyzer_path_mode = state.analyzer_path_mode or {}
        state.analyzer_path_mode[w.path] = w.mode
      end
    end
    -- Quit file for idle workers; busy ones are killed by pid so closing
    -- the pipe does not wait for their current job.
    sm_stop_analyzer_worker(w, false)
  end
  state.analyzer_workers = {}
  state.active_processes = {}
  if state.analyzer_work_dir and state.analyzer_work_dir ~= "" then
    os.execute("rm -rf " .. shell_escape(state.analyzer_work_dir))
    state.analyzer_work_dir = nil
  end
end

function start_analyzer_worker(slot)
  if not analyzer_script_exists() then
    return nil
  end
  local dir = analyzer_work_dir()
  local cmd = table.concat({
    shell_escape(PYTHON_BIN),
    "-u",
    shell_escape(EXTERNAL_ANALYZER),
    "--worker",
    "--slot",
    tostring(slot),
    "--dir",
    shell_escape(dir),
  }, " ")
  local log_path = dir .. "/worker_" .. tostring(slot) .. ".log"
  os.remove(dir .. "/quit_" .. tostring(slot))
  -- A killed worker never removes its pid file; a stale one would read as alive.
  os.remove(dir .. "/pid_" .. tostring(slot))
  local pipe = io.popen(sm_shell_cmd(cmd .. " 2>> " .. shell_escape(log_path)), "r")
  if not pipe then
    return nil
  end
  -- Don't wait for the worker's "ready" line: a job written to req_<slot>
  -- before the worker is up is picked up as soon as it starts polling.
  return {
    slot = slot,
    pipe = pipe,
    req_path = dir .. "/req_" .. tostring(slot),
    res_path = dir .. "/res_" .. tostring(slot),
    quit_path = dir .. "/quit_" .. tostring(slot),
    pid_path = dir .. "/pid_" .. tostring(slot),
    path = nil,
    mode = nil,
    start_time = 0,
  }
end

function detect_cpu_count()
  local n = 0
  local pipe = io.popen("sysctl -n hw.logicalcpu 2>/dev/null")
  if pipe then
    n = tonumber((pipe:read("*l") or ""):match("%d+")) or 0
    pipe:close()
  end
  if n < 1 then
    pipe = io.popen("getconf _NPROCESSORS_ONLN 2>/dev/null")
    if pipe then
      n = tonumber((pipe:read("*l") or ""):match("%d+")) or 0
      pipe:close()
    end
  end
  if n < 1 then
    n = 4
  end
  return n
end

function recommended_analyzer_workers(cores)
  cores = tonumber(cores) or 4
  local n
  if cores <= 4 then
    n = math.max(2, cores - 1)
  elseif cores <= 8 then
    n = math.min(6, cores - 1)
  else
    n = math.min(8, cores - 1)
  end
  if n < 2 then n = 2 end
  if n > 8 then n = 8 end
  return n
end

function apply_cpu_analyzer_workers()
  local cores = detect_cpu_count()
  state.cpu_core_count = cores
  state.max_concurrent_analyzers = recommended_analyzer_workers(cores)
end

-- cmd.exe strips the first and last quote of a command that starts with a
-- quote; wrapping the whole command in one more pair keeps it intact.
function sm_shell_cmd(cmd)
  if SM_IS_WINDOWS then
    return '"' .. cmd .. '"'
  end
  return cmd
end

-- Run `<python> -c <code>` quietly; true when it exits with status 0.
function sm_python_check(bin, code)
  if not bin or bin == "" then
    return false
  end
  local null_dev = SM_IS_WINDOWS and "NUL" or "/dev/null"
  local pipe = io.popen(sm_shell_cmd(shell_escape(bin) .. ' -c "' .. code .. '" 2>' .. null_dev))
  if not pipe then
    return false
  end
  pipe:read("*a")
  local ok = pipe:close()
  return ok == true
end

function python_has_numpy(bin)
  return sm_python_check(bin, "import numpy")
end

-- On macOS /usr/bin/python3 is a stub that pops up the "install command line
-- developer tools" dialog when the tools are missing; don't probe it then.
function sm_macos_clt_missing()
  if state.macos_clt_missing ~= nil then
    return state.macos_clt_missing
  end
  local os_name = (r.GetOS and r.GetOS()) or ""
  if SM_IS_WINDOWS or not (os_name:match("^OSX") or os_name:match("^macOS")) then
    state.macos_clt_missing = false
    return false
  end
  local ok = os.execute("/usr/bin/xcode-select -p >/dev/null 2>&1")
  state.macos_clt_missing = not ok
  return state.macos_clt_missing
end

function resolve_analyzer_python()
  if state.python_resolved then
    return PYTHON_BIN
  end
  state.python_resolved = true
  local candidates
  if SM_IS_WINDOWS then
    candidates = { "py", "python", "python3" }
    if PYTHON_BIN ~= "/usr/bin/python3" then
      table.insert(candidates, 1, PYTHON_BIN)
    end
  else
    candidates = {
      PYTHON_BIN,
      "/opt/homebrew/bin/python3",
      "/usr/local/bin/python3",
      "/usr/bin/python3",
      "python3",
    }
  end
  local skip_system = sm_macos_clt_missing()
  local seen = {}
  local fallback = nil
  for i = 1, #candidates do
    local bin = candidates[i]
    local is_bare = bin and not bin:find("[/\\]")
    local stub = skip_system and (bin == "/usr/bin/python3" or bin == "python3")
    if bin and bin ~= "" and not seen[bin] and not stub then
      seen[bin] = true
      if is_bare or r.file_exists(bin) then
        if python_has_numpy(bin) then
          PYTHON_BIN = bin
          state.analyzer_numpy_missing = false
          add_scan_log("Analyzer Python: " .. bin .. " (numpy)")
          return PYTHON_BIN
        end
        if not fallback and (not is_bare or sm_python_check(bin, "import sys")) then
          fallback = bin
        end
      end
    end
  end
  if not fallback then
    state.analyzer_no_python = true
    add_scan_log("Analyzer: no working Python 3 found — install Python 3 to enable audio analysis")
    return PYTHON_BIN
  end
  PYTHON_BIN = fallback
  state.analyzer_numpy_missing = true
  add_scan_log("Analyzer Python: " .. fallback .. " (numpy not installed — using the slower built-in FFT)")
  add_scan_log("To speed up analysis, use Library > Re-analyze > Install numpy…, or run: "
    .. sm_numpy_install_command())
  return PYTHON_BIN
end

function sm_numpy_install_command()
  return shell_escape(PYTHON_BIN) .. " -m pip install --user numpy"
end

-- Only runs when the user picks the menu item (never automatically).
function sm_install_numpy()
  local cmd = sm_numpy_install_command()
  local answer = r.ShowMessageBox(
    "Install numpy for the analyzer's Python?\n\nThis runs:\n" .. cmd
      .. "\n\nAnalysis keeps working without it, just slower. New analyzer workers use numpy once the install finishes.",
    "Install numpy", 4)
  if answer ~= 6 then
    return
  end
  state.analyzer_numpy_install_started = true
  if SM_IS_WINDOWS then
    os.execute(sm_shell_cmd('start "" /B ' .. cmd .. " >NUL 2>&1"))
  else
    os.execute(cmd .. " >/dev/null 2>&1 &")
  end
  add_scan_log("Installing numpy in the background: " .. cmd)
end

function ensure_analyzer_workers()
  resolve_analyzer_python()
  if state.analyzer_no_python then
    -- Fail queued jobs instead of starting workers that cannot run.
    for _, path in ipairs(state.analyzer_queue) do
      state.analyzer_results[path] = {data = nil, err = "no Python 3 found"}
    end
    state.analyzer_queue = {}
    return false
  end
  if not state.cpu_core_count or state.cpu_core_count < 1 then
    apply_cpu_analyzer_workers()
  end
  state.analyzer_workers = state.analyzer_workers or {}
  local want = state.max_concurrent_analyzers or 3
  if want < 1 then want = 1 end
  if want > 8 then want = 8 end
  local started = #state.analyzer_workers
  while #state.analyzer_workers < want do
    local worker = start_analyzer_worker(#state.analyzer_workers + 1)
    if not worker then
      if #state.analyzer_workers == 0 then
        state.external_disabled = true
        state.analyzer_warned = true
      end
      break
    end
    table.insert(state.analyzer_workers, worker)
  end
  if started == 0 and #state.analyzer_workers > 0 then
    add_scan_log(string.format(
      "Analyzer workers: %d (detected %d CPU cores, leaving 1 free)",
      #state.analyzer_workers,
      state.cpu_core_count or 0
    ))
  end
  return #state.analyzer_workers > 0
end

apply_cpu_analyzer_workers()

function refresh_active_processes()
  local busy = {}
  for _, w in ipairs(state.analyzer_workers or {}) do
    if w.path then
      busy[#busy + 1] = w
    end
  end
  state.active_processes = busy
end

function collect_worker_result(w)
  if not w or not w.path then
    return false
  end
  local f = io.open(w.res_path, "r")
  if not f then
    if w.start_time and (r.time_precise() - w.start_time) > 30.0 then
      state.analyzer_results[w.path] = {data = nil, err = "analyzer timeout"}
      add_scan_log(string.format("Analyzer timeout on %s (continuing)", w.path:match("([^/]+)$") or w.path))
      note_scan_session_analyzer(false)
      w.path = nil
      w.mode = nil
      -- Restart the hung worker so its late result can't land on the next job;
      -- also restart one that exited (pid file gone) right as the job was sent.
      if sm_analyzer_worker_pid(w) or w.pid_seen then
        sm_restart_analyzer_worker(w)
      end
      return true
    end
    return false
  end
  local output = f:read("*a")
  f:close()
  os.remove(w.res_path)
  local path = w.path
  local mode = w.mode
  local ok_peek, peek = false, nil
  if output and output ~= "" then
    ok_peek, peek = pcall(json_decode, output)
    local result_path = ok_peek and type(peek) == "table" and peek._path or nil
    if type(result_path) == "string" and result_path ~= ""
        and not sm_analyzer_paths_equal(result_path, path) then
      -- Late result for an earlier job (e.g. after a timeout): drop it, keep waiting.
      add_scan_log(string.format("Dropped stale analyzer result for %s", result_path:match("([^/]+)$") or result_path))
      return false
    end
  end
  w.path = nil
  w.mode = nil
  if output and output ~= "" then
    local success, data = ok_peek, peek
    if success and type(data) == "table" then
      data._debug = nil
      local err = data._error
      data._path = nil
      data._error = nil
      if err then
        state.analyzer_results[path] = {data = nil, err = tostring(err)}
        add_scan_log(string.format("Analyzer error on %s: %s", path:match("([^/]+)$") or path, tostring(err)))
        note_scan_session_analyzer(false)
      elseif not analyzer_data_has_fields(data) then
        state.analyzer_results[path] = {data = nil, err = "could not decode audio"}
        add_scan_log(string.format("Analyzer error on %s: could not decode audio", path:match("([^/]+)$") or path))
        note_scan_session_analyzer(false)
      else
        state.analyzer_results[path] = {data = data, err = nil}
        note_scan_session_analyzer(true)
        if mode == "transient" then
          add_scan_log(string.format("Transient scan: %s (onset=%.4f, transient_end=%.4f)", path:match("([^/]+)$") or path, data.onset or 0, data.transient_end or 0))
        elseif mode == "weight" then
          add_scan_log(string.format("Weight scan: %s (weight=%.3f)", path:match("([^/]+)$") or path, data.sub_weight or 0))
        else
          add_scan_log(string.format("Analyzer completed: %s (freq=%.1f, bright=%.1f, weight=%.2f, rms=%.3f, playback=%s)", path:match("([^/]+)$") or path, data.dominant_freq or 0, data.brightness or 0, data.sub_weight or 0, data.rms_energy or 0, tostring(data.playback_type or "?")))
        end
      end
    else
      state.analyzer_results[path] = {data = nil, err = "invalid analyzer JSON"}
      add_scan_log(string.format("Analyzer error on %s: invalid JSON: %s", path:match("([^/]+)$") or path, tostring(data)))
      note_scan_session_analyzer(false)
    end
  else
    state.analyzer_results[path] = {data = nil, err = "empty analyzer output"}
    add_scan_log(string.format("Analyzer error on %s: empty output", path:match("([^/]+)$") or path))
    note_scan_session_analyzer(false)
  end
  return true
end

function assign_worker_job(w, path, mode)
  if not w or not path or path == "" then
    return false
  end
  if mode ~= "transient" and mode ~= "weight" then
    mode = "full"
  end
  if not sm_analyzer_worker_alive(w) then
    -- Worker exited (idle timeout or crash): start a fresh one in this slot.
    if not sm_restart_analyzer_worker(w) then
      return false
    end
  end
  os.remove(w.res_path)
  if not write_worker_file(w.req_path, mode .. "\t" .. path .. "\n") then
    return false
  end
  w.path = path
  w.mode = mode
  w.start_time = r.time_precise()
  return true
end

function process_analyzer_queue()
  if state.external_disabled then
    return
  end
  local workers = state.analyzer_workers or {}
  if #workers == 0 and #state.analyzer_queue == 0 then
    state.active_processes = {}
    return
  end
  if #state.analyzer_queue > 0 then
    if not ensure_analyzer_workers() then
      return
    end
    workers = state.analyzer_workers or {}
  end

  for _, w in ipairs(workers) do
    if w.path then
      collect_worker_result(w)
    end
  end

  if state.scan_running then
    for _, w in ipairs(workers) do
      if not w.path and #state.analyzer_queue > 0 then
        local path = table.remove(state.analyzer_queue, 1)
        local mode = nil
        if state.analyzer_path_mode and path then
          mode = state.analyzer_path_mode[path]
          state.analyzer_path_mode[path] = nil
        end
        if not mode then
          mode = state.analyzer_mode
        end
        if not assign_worker_job(w, path, mode) then
          table.insert(state.analyzer_queue, 1, path)
          if mode then
            state.analyzer_path_mode = state.analyzer_path_mode or {}
            state.analyzer_path_mode[path] = mode
          end
          break
        end
      end
    end
  end
  refresh_active_processes()
end


function folders_match(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if #a ~= #b then return false end
  for i = 1, #a do
    -- Normalize paths before comparison
    local norm_a = normalize_path(a[i] or "")
    local norm_b = normalize_path(b[i] or "")
    if norm_a ~= norm_b then return false end
  end
  return true
end


-- Layout samples on the 2D map based on their audio characteristics
function layout_samples()
  if #state.samples == 0 then return end

  -- Use Lua calculation (Python analyzer doesn't support layout calculations)
  -- Coordinates are cached after calculation, so this only runs when needed

  -- Calculate positioning scores for all samples
  local len_scores = {}
  local freq_scores = {}
  local rms_scores = {}
  local size_scores = {}

  -- Lua doesn't have log10, so use log(x) / log(10)
  local log10 = math.log(10)
  for _, s in ipairs(state.samples) do
    table.insert(len_scores, math.log(math.max(sample_map_duration(s), 0.01)) / log10)
    -- Y: user-selected axis (brightness, dominant freq, or sub weight)
    local axis = state.map_y_axis
    if axis == "weight" then
      local w = s.sub_weight
      if type(w) ~= "number" then w = 0.0 end
      table.insert(freq_scores, math.max(0.0, math.min(1.0, w)))
    else
      local y_hz
      if axis == "dominant_freq" then
        y_hz = s.dominant_freq or 440.0
      else
        y_hz = s.brightness or s.dominant_freq or 440.0
      end
      local freq = math.max(40.0, math.min(20000.0, y_hz))
      table.insert(freq_scores, math.log(freq) / log10)
    end
    -- Store RMS energy (use log scale for better distribution)
    local rms = math.max(1e-6, s.rms_energy or 0.0)
    table.insert(rms_scores, math.log(rms) / log10)
    -- Store file size (use log scale for better distribution)
    local size = math.max(1, s.file_size or 1)
    table.insert(size_scores, math.log(size) / log10)
  end

  -- Check if frequencies are too similar (all defaulting to 440Hz)
  local freq_min = freq_scores[1]
  local freq_max = freq_scores[1]
  for _, v in ipairs(freq_scores) do
    freq_min = math.min(freq_min, v)
    freq_max = math.max(freq_max, v)
  end
  local freq_range = freq_max - freq_min

  -- Check if RMS is all zeros
  local rms_min = rms_scores[1]
  local rms_max = rms_scores[1]
  for _, v in ipairs(rms_scores) do
    rms_min = math.min(rms_min, v)
    rms_max = math.max(rms_max, v)
  end
  local rms_range = rms_max - rms_min
  local rms_all_zero = rms_range < 1e-6  -- RMS is essentially zero

  -- Decide what to use for Y axis
  local use_rms_for_y = false
  local use_size_for_y = false

  if freq_range < 0.01 then
    -- Frequency range too small
    if rms_all_zero then
      -- RMS is also zero, use file size
      use_size_for_y = true
    else
      use_rms_for_y = true
    end
  end

  math.randomseed(state.map_seed)

  -- Ensure we use the full range: find min/max for both axes
  local len_min, len_max = len_scores[1], len_scores[1]
  local y_min, y_max

  for _, v in ipairs(len_scores) do
    len_min = math.min(len_min, v)
    len_max = math.max(len_max, v)
  end

  -- Use RMS, file size, or frequency for Y axis
  if use_size_for_y then
    y_min, y_max = size_scores[1], size_scores[1]
    for _, v in ipairs(size_scores) do
      y_min = math.min(y_min, v)
      y_max = math.max(y_max, v)
    end
  elseif use_rms_for_y then
    y_min, y_max = rms_scores[1], rms_scores[1]
    for _, v in ipairs(rms_scores) do
      y_min = math.min(y_min, v)
      y_max = math.max(y_max, v)
    end
  else
    y_min, y_max = freq_scores[1], freq_scores[1]
    for _, v in ipairs(freq_scores) do
      y_min = math.min(y_min, v)
      y_max = math.max(y_max, v)
    end
  end

  -- Normalize function that ensures full range usage with padding for better spread
  local function normalize(value, min_val, max_val, padding)
    padding = padding or 0.1  -- 10% padding on each side
    if max_val - min_val < 1e-9 then
      return 0.5  -- All same value, center it
    end
    -- Normalize to 0-1 range
    local normalized = (value - min_val) / (max_val - min_val)
    -- Scale to use more of the available space (with padding)
    -- Maps 0-1 to padding to (1-padding)
    return padding + normalized * (1.0 - 2.0 * padding)
  end

  -- Position each sample
  for i, s in ipairs(state.samples) do
    -- Preserve existing tags before modifying sample (make a copy, not a reference)
    local preserved_tags = nil
    if s.tags and type(s.tags) == "table" then
      preserved_tags = {}
      for _, tag in ipairs(s.tags) do
        table.insert(preserved_tags, tag)
      end
    end

    -- X-axis: duration (left = short, right = long)
    local x = normalize(len_scores[i], len_min, len_max, 0.05)  -- 5% padding
    -- Y-axis: brightness (or pitch fallback), RMS energy, or file size (top = high, bottom = low)
    -- Use full range (0.0 padding) to spread from top to bottom
    local y_value
    if use_size_for_y then
      y_value = size_scores[i]
    elseif use_rms_for_y then
      y_value = rms_scores[i]
    else
      y_value = freq_scores[i]
    end
    local y_normalized = normalize(y_value, y_min, y_max, 0.0)  -- No padding - use full range
    local y = 1.0 - y_normalized  -- Invert so highest value is at top
    -- Add jitter to avoid clustering
    local jx = (math.random() - 0.5) * 0.04
    local jy = (math.random() - 0.5) * 0.04
    s.x = math.max(0.0, math.min(1.0, x + jx))
    s.y = math.max(0.0, math.min(1.0, y + jy))
    -- Use customizable dot color, with slight variation for mono samples
    local base_color = state.dot_color or 0x44AA55FF  -- RRGGBBAA format
    local base_r, base_g, base_b = extract_rgb_rrgbbaa(base_color)
    local base_alpha = math.floor(base_color % 256)
    if s.channels == 1 then
      -- Mono: use lighter version (add 50% to each component, clamped to 255)
      local mono_r = math.min(255, math.floor(base_r * 1.5))
      local mono_g = math.min(255, math.floor(base_g * 1.5))
      local mono_b = math.min(255, math.floor(base_b * 1.5))
      s.color = build_color_rrgbbaa(mono_r, mono_g, mono_b, base_alpha)
    else
      -- Stereo: use base customizable color directly
      s.color = base_color
    end
    -- Use customizable hover color directly (RRGGBBAA format)
    s.hot_color = state.dot_hover_color or 0xFFC84DFF

    -- Restore preserved tags
    if preserved_tags then
      s.tags = preserved_tags
    end
  end

  state.map_layout_version = (state.map_layout_version or 0) + 1

  -- Layout debug logs removed - happens during scanning
end

MAP_Y_AXIS_OPTIONS = { "brightness", "dominant_freq", "weight" }
MAP_Y_AXIS_LABELS = {
  brightness = "Brightness",
  dominant_freq = "Dominant frequency",
  weight = "Weight",
}

function map_y_axis_id()
  local id = state.map_y_axis
  if id == "brightness" or id == "dominant_freq" or id == "weight" then
    return id
  end
  return "brightness"
end

function map_y_axis_label(id)
  return MAP_Y_AXIS_LABELS[id] or MAP_Y_AXIS_LABELS.brightness
end

function apply_map_y_axis(id)
  if id ~= "brightness" and id ~= "dominant_freq" and id ~= "weight" then
    return
  end
  if state.map_y_axis == id then
    return
  end
  state.map_y_axis = id
  if #state.samples > 0 then
    layout_samples()
  end
  save_config()
end


function hydrate_sample_runtime(sample)
  if not sample then return end
  if sample.hot_color == nil then
    sample.hot_color = state.dot_hover_color or 0xFFC84DFF
  end
  if sample.samplerate == nil and sample.sample_rate ~= nil then
    sample.samplerate = sample.sample_rate
  end
  if sample.samplerate == nil then
    sample.samplerate = 44100
  end
  if sample.file_size == nil then
    local dur = sample.duration or 0
    local bps = sample.bps or 0
    sample.file_size = math.max(0, math.floor(bps * dur + 0.5))
  end
end

-- Prepare one cached sample. full_tag_backfill runs expensive genre/loop inference.
function prepare_cached_sample(s, full_tag_backfill, dirs, tag_dict)
  if type(s) == "table" and SampleCacheCodec then
    s = SampleCacheCodec.expand_sample(s, dirs, tag_dict)
  end
  if type(s) ~= "table" or not s.path or not s.name then
    return nil
  end
  s.path = normalize_path(s.path)
  if not s.x then s.x = 0.5 end
  if not s.y then s.y = 0.5 end

  if not s.tags or type(s.tags) ~= "table" then
    s.tags = infer_tags_from_path(s.path, s.folder or "")
  end

  if s.sample_type and (s.sample_type == "Drum" or s.sample_type == "Swell") then
    local has_tag = false
    for _, tag in ipairs(s.tags) do
      if tag == s.sample_type then
        has_tag = true
        break
      end
    end
    if not has_tag and not (tag_is_suppressed and tag_is_suppressed(s.sample_type)) then
      table.insert(s.tags, s.sample_type)
    end
  end

  if full_tag_backfill then
    apply_loop_oneshot_tag(s, detect_loop_or_oneshot(s.path, s.folder or "", s.playback_type))
    s.tags = append_unique_tags(s.tags, infer_genre_tags_from_path(s.path, s.folder or ""))
  end

  hydrate_sample_runtime(s)
  return s
end

function tag_schema_needs_backfill(data)
  local ver = tonumber(data and data.tag_schema_version) or 0
  if ver < TAG_SCHEMA_VERSION then
    return true, true
  end
  return false, false
end

function is_library_loading()
  local job = state.library_load
  return job ~= nil and job.phase ~= "done" and job.phase ~= "miss"
end

function begin_library_load()
  state.library_ready = false
  clear_genre_tag_dir_cache()
  state.library_load = {
    phase = "init",
    format = nil,
    path = nil,
    content = nil,
    data = nil,
    raw_samples = nil,
    cleaned = {},
    index = 1,
    needs_tag_backfill = false,
    stamp_schema = false,
    needs_layout = false,
    total = 0,
    started = r.time_precise(),
    message = "Loading sample library…",
    progress = 0,
  }
  log("Starting deferred library load")
end

function finish_library_miss(reason)
  local job = state.library_load
  if job then
    job.phase = "miss"
    job.message = reason or "No sample cache"
    job.progress = 1
  end
  state.library_ready = true
  state.library_load = nil
  log(reason or "Library cache miss")
  refresh_scan_folder_availability()
  if #state.folders > 0 then
    state._enqueue_scan_after_load = true
  end
end

-- `folders` must already be normalized (see normalize_path).
function sm_path_in_folders(path, folders)
  local p = normalize_path(path or "")
  for _, f in ipairs(folders or {}) do
    if f ~= "" and (p == f or (p:sub(1, #f) == f and p:sub(#f + 1, #f + 1) == "/")) then
      return true
    end
  end
  return false
end

-- The configured folder list differs from the cached one: keep the cache, drop
-- entries outside the current folders, and scan only folders the cache lacks.
function sm_library_note_folder_change(job, cached_folders)
  local cached = {}
  for _, f in ipairs(cached_folders or {}) do
    if type(f) == "string" then
      cached[normalize_path(f)] = true
    end
  end
  job.folder_filter = true
  job.new_folders = {}
  for _, f in ipairs(state.folders) do
    local nf = normalize_path(f)
    if nf ~= "" and not cached[nf] then
      job.new_folders[#job.new_folders + 1] = nf
    end
  end
  log(string.format("Folder list changed: keeping cache for current folders, %d new folder(s) to scan", #job.new_folders))
end

function sm_library_apply_folder_filter(job)
  local folders = {}
  for _, f in ipairs(state.folders) do
    folders[#folders + 1] = normalize_path(f)
  end
  local kept = {}
  local removed = 0
  for _, sample in ipairs(state.samples) do
    if not sample.path or sm_path_in_folders(sample.path, folders) then
      kept[#kept + 1] = sample
    else
      removed = removed + 1
    end
  end
  state.samples = kept
  local function filter_list(list)
    local out = {}
    for _, p in ipairs(list or {}) do
      if sm_path_in_folders(p, folders) then
        out[#out + 1] = p
      end
    end
    return out
  end
  state.scan_queue = filter_list(state.scan_queue)
  state.analyzer_queue = filter_list(state.analyzer_queue)
  for path in pairs(state.analyzer_results or {}) do
    if not sm_path_in_folders(path, folders) then
      state.analyzer_results[path] = nil
    end
  end
  if #state.scan_queue == 0 then
    state.scan_total = 0
  end
  if removed > 0 then
    log("Removed " .. removed .. " cached sample(s) outside the current folders")
  end
  state._save_library_after_load = true
  if job.new_folders and #job.new_folders > 0 then
    state._enqueue_scan_after_load = job.new_folders
  end
end

function finish_library_hit(job)
  state.samples = job.cleaned

  local data = job.data or {}
  local dirs = data.dirs
  if data.scan_queue and type(data.scan_queue) == "table" and #data.scan_queue > 0 then
    state.scan_queue = SampleCacheCodec.expand_path_list(data.scan_queue, dirs)
    state.scan_total = data.scan_total or (#state.samples + #state.scan_queue)
    state.scan_started = 0
    state.scan_running = false
    log(string.format("Loaded unfinished scan: %d file(s) remaining — press Rescan to continue", #state.scan_queue))
  else
    state.scan_queue = {}
    state.scan_total = 0
    state.scan_running = false
  end

  if data.analyzer_queue and type(data.analyzer_queue) == "table" and #data.analyzer_queue > 0 then
    state.analyzer_queue = SampleCacheCodec.expand_path_list(data.analyzer_queue, dirs)
  else
    state.analyzer_queue = {}
  end
  if data.analyzer_results and type(data.analyzer_results) == "table" then
    state.analyzer_results = data.analyzer_results
  else
    state.analyzer_results = {}
  end
  state.analyzer_mode = data.analyzer_mode
  state.analyzer_path_mode = {}
  if state.analyzer_mode == "transient" then
    state.analyzer_job_label = "Scanning transient/sustain"
    for _, path in ipairs(state.analyzer_queue) do
      state.analyzer_path_mode[path] = "transient"
    end
  elseif state.analyzer_mode == "weight" then
    state.analyzer_job_label = "Scanning weight"
    for _, path in ipairs(state.analyzer_queue) do
      state.analyzer_path_mode[path] = "weight"
    end
  end
  if data.analyzer_pending and state.analyzer_mode ~= "transient" and state.analyzer_mode ~= "weight" then
    for _, sample in ipairs(state.samples) do
      if not sample.dominant_freq then
        table.insert(state.analyzer_queue, sample.path)
      end
    end
  end

  if job.folder_filter then
    sm_library_apply_folder_filter(job)
  end

  if job.needs_layout then
    layout_samples()
    log("Re-layouting samples (missing/invalid coordinates)")
  else
    log("Using cached coordinates (no layout needed)")
  end

  apply_discovered_library_tags()
  rebuild_samples_path_index()
  apply_custom_tags_to_samples()
  rebuild_tag_index()
  refresh_scan_folder_availability()
  explorer_invalidate_cache()

  if job.stamp_schema or job.needs_tag_backfill then
    state.tag_schema_dirty = true
  end

  -- Rewrite cache after JSON migration, schema stamp, or compact-format upgrade.
  if job.format == "json" or state.tag_schema_dirty or job.rewrite_compact then
    state._save_library_after_load = true
  end

  job.phase = "done"
  job.progress = 1
  job.message = string.format("Loaded %d samples", #state.samples)
  state.library_ready = true
  state.library_load = nil
  log(string.format(
    "Library loaded (%s): %d samples in %.0fms",
    job.format or "?",
    #state.samples,
    (r.time_precise() - job.started) * 1000
  ))
end

-- Pick the next readable cache file: main Lua, main JSON, then their .bak copies.
function sm_library_load_next_source(job)
  local candidates = {
    { "lua", DATA_LUA_PATH },
    { "json", DATA_PATH },
    { "lua", DATA_LUA_PATH .. ".bak" },
    { "json", DATA_PATH .. ".bak" },
  }
  local i = (job.source_index or 0) + 1
  while i <= #candidates do
    local c = candidates[i]
    local f = io.open(c[2], "rb")
    if f then
      local size = f:seek("end") or 0
      f:close()
      if size > 0 then
        job.source_index = i
        job.format = c[1]
        job.path = c[2]
        job.content = nil
        job.phase = "read"
        job.message = (c[1] == "lua") and "Reading Lua cache…" or "Reading JSON cache…"
        if i > 2 then
          log("Using backup sample cache: " .. c[2])
        end
        return true
      end
    end
    i = i + 1
  end
  job.source_index = i
  return false
end

function process_library_load_slice(max_ms)
  local job = state.library_load
  if not job or job.phase == "done" or job.phase == "miss" then
    return false
  end
  max_ms = max_ms or LIBRARY_LOAD_SLICE_MS
  local deadline = r.time_precise() + (max_ms / 1000.0)

  while r.time_precise() < deadline do
    if job.phase == "init" then
      if not sm_library_load_next_source(job) then
        finish_library_miss("Cache file not found")
        return false
      end

    elseif job.phase == "read" then
      if job.format == "lua" then
        -- loadfile avoids holding a second giant string copy in Lua
        job.message = "Decoding Lua cache…"
        job.phase = "decode"
        job.progress = 0.05
      else
        local file = io.open(job.path, "r")
        if not file then
          if not sm_library_load_next_source(job) then
            finish_library_miss("Cache file cannot be opened")
            return false
          end
        else
          job.content = file:read("*all")
          file:close()
          if not job.content or job.content == "" or not job.content:sub(-64):find("}%s*$") then
            -- Empty or truncated (a complete cache ends with '}').
            log("JSON cache empty or truncated: " .. tostring(job.path))
            job.content = nil
            if not sm_library_load_next_source(job) then
              finish_library_miss("Cache file is empty")
              return false
            end
          else
            log(string.format("Cache file size: %d bytes (json)", #job.content))
            job.message = "Decoding JSON cache…"
            job.phase = "decode"
            job.progress = 0.05
          end
        end
      end

    elseif job.phase == "decode" then
      local data
      if job.format == "lua" then
        local loader, err
        if loadfile then
          local ok_lf, a, b = pcall(loadfile, job.path)
          if ok_lf then
            loader, err = a, b
          end
        end
        if not loader then
          local file = io.open(job.path, "r")
          if file then
            local content = file:read("*all")
            file:close()
            if load then
              local ok_l, a, b = pcall(load, content, "@SampleMapData.cache.lua")
              if ok_l then
                loader, err = a, b
              else
                err = a
              end
            end
          end
        end
        if not loader then
          log("Failed to load Lua cache: " .. tostring(err))
          if job.path == DATA_LUA_PATH then
            pcall(os.remove, DATA_LUA_PATH)
          end
          if not sm_library_load_next_source(job) then
            finish_library_miss("Failed to load Lua cache")
            return false
          end
        else
          local ok, result = pcall(loader)
          if not ok or type(result) ~= "table" then
            log("Failed to execute Lua cache: " .. tostring(result))
            if job.path == DATA_LUA_PATH then
              pcall(os.remove, DATA_LUA_PATH)
            end
            if not sm_library_load_next_source(job) then
              finish_library_miss("Failed to execute Lua cache")
              return false
            end
          else
            data = result
          end
        end
      else
        local ok, result = pcall(json_decode_sample_cache, job.content)
        job.content = nil
        if not ok or type(result) ~= "table" then
          log("Fast JSON decode failed (" .. tostring(result) .. "); trying full decoder")
          local content = sm_read_nonempty_file(job.path)
          if content then
            ok, result = pcall(json_decode, content)
          else
            ok, result = false, "cannot read " .. tostring(job.path)
          end
          content = nil
          if not ok or type(result) ~= "table" then
            log("Failed to decode JSON cache " .. tostring(job.path) .. ": " .. tostring(result))
            result = nil
            if not sm_library_load_next_source(job) then
              finish_library_miss("Failed to decode JSON cache")
              return false
            end
          end
        end
        data = result
      end

      if not data then
        -- Waiting for fallback read path
      else
        if data.folders and not folders_match(state.folders, data.folders) then
          sm_library_note_folder_change(job, data.folders)
        end
        local streaming = data._samples_content ~= nil and data._samples_pos ~= nil
        local count = 0
        if streaming then
          -- Estimate from newlines (one sample per line in our writer).
          count = select(2, data._samples_content:gsub("\n", "\n"))
          if count < 1 then count = 0 end
        elseif data.samples and type(data.samples) == "table" then
          count = #data.samples
        end
        if not streaming and count == 0 then
          finish_library_miss("Cache has no samples")
          return false
        end
        job.data = data
        job.dirs = data.dirs
        job.tag_dict = data.tag_dict
        job.rewrite_compact = (tonumber(data.v) or 1) < SampleCacheCodec.VERSION
        job.raw_samples = (not streaming) and data.samples or nil
        job.json_content = data._samples_content
        job.json_pos = data._samples_pos
        data._samples_content = nil
        data._samples_pos = nil
        job.total = count
        job.index = 1
        job.cleaned = {}
        job.needs_tag_backfill, job.stamp_schema = tag_schema_needs_backfill(data)
        job.needs_layout = false
        job.stream_json = streaming
        job.phase = "process"
        if job.needs_tag_backfill then
          job.message = streaming and "Refreshing library tags…" or string.format("Refreshing library tags (0/%d)…", job.total)
        else
          job.message = streaming and "Preparing samples…" or string.format("Preparing samples (0/%d)…", job.total)
        end
        job.progress = 0.1
        log(string.format(
          "Decoded cache meta (stream=%s, estimate=%d, tag_backfill=%s)",
          tostring(streaming),
          job.total,
          tostring(job.needs_tag_backfill)
        ))
      end

    elseif job.phase == "process" then
      if job.stream_json then
        while r.time_precise() < deadline do
          local obj
          obj, job.json_pos = next_json_sample(job.json_content, job.json_pos)
          if not obj then
            job.json_content = nil
            job.stream_json = false
            job.total = #job.cleaned
            job.phase = "finalize"
            job.message = "Finalizing library…"
            job.progress = 0.96
            break
          end
          local s = prepare_cached_sample(obj, job.needs_tag_backfill, job.dirs, job.tag_dict)
          if s then
            job.cleaned[#job.cleaned + 1] = s
            if not job.needs_layout then
              if not s.x or not s.y or s.x < 0 or s.x > 1 or s.y < 0 or s.y > 1 then
                job.needs_layout = true
              end
            end
          end
          local done = #job.cleaned
          if done % 256 == 0 then
            local total = math.max(job.total, done)
            job.progress = 0.1 + 0.85 * (done / total)
            local label = job.needs_tag_backfill and "Refreshing library tags" or "Preparing samples"
            job.message = string.format("%s (%d/%d)…", label, done, total)
          end
        end
      else
        local raw = job.raw_samples
        local total = job.total
        while job.index <= total and r.time_precise() < deadline do
          local s = prepare_cached_sample(raw[job.index], job.needs_tag_backfill, job.dirs, job.tag_dict)
          if s then
            job.cleaned[#job.cleaned + 1] = s
            if not job.needs_layout then
              if not s.x or not s.y or s.x < 0 or s.x > 1 or s.y < 0 or s.y > 1 then
                job.needs_layout = true
              end
            end
          end
          job.index = job.index + 1
          if job.index % 256 == 0 then
            job.progress = 0.1 + 0.85 * ((job.index - 1) / math.max(total, 1))
            local label = job.needs_tag_backfill and "Refreshing library tags" or "Preparing samples"
            job.message = string.format("%s (%d/%d)…", label, job.index - 1, total)
          end
        end
        if job.index > total then
          job.raw_samples = nil
          job.phase = "finalize"
          job.message = "Finalizing library…"
          job.progress = 0.96
        end
      end

    elseif job.phase == "finalize" then
      if #job.cleaned == 0 then
        finish_library_miss("No valid samples in cache")
        return false
      end
      finish_library_hit(job)
      return false
    else
      break
    end
  end

  return is_library_loading()
end


function save_samples()
  local save_start = r.time_precise()

  local normalized_folders = {}
  for _, folder in ipairs(state.folders) do
    table.insert(normalized_folders, normalize_path(folder))
  end

  local payload = SampleCacheCodec.build_payload(state, normalized_folders, state.samples)
  local sample_count = #payload.samples

  -- Fast Lua cache (primary load path)
  local ok_lua_enc, lua_str = pcall(encode_lua_cache, payload)
  local lua_saved, lua_err = false, nil
  if ok_lua_enc and type(lua_str) == "string" then
    lua_saved, lua_err = sm_atomic_write(DATA_LUA_PATH, lua_str)
  else
    lua_err = "encode failed: " .. tostring(lua_str)
  end
  lua_str = nil
  if not lua_saved then
    log("Failed to write Lua cache: " .. DATA_LUA_PATH .. " (" .. tostring(lua_err) .. ")")
  end

  -- Compact JSON for companion scripts (Quick Swap, etc.)
  local function encode_samples_lines(list)
    local out = {"["}
    for i, row in ipairs(list) do
      out[#out + 1] = SampleCacheCodec.encode_row_json(row)
      if i < #list then
        out[#out + 1] = ",\n"
      end
    end
    out[#out + 1] = "]"
    return table.concat(out)
  end

  local ok_json_enc, json_str = pcall(function() return table.concat({
    "{",
    "\"v\":", json_encode(payload.v), ",",
    "\"tag_schema_version\":", json_encode(payload.tag_schema_version), ",",
    "\"folders\":", json_encode(payload.folders), ",",
    "\"dirs\":", json_encode(payload.dirs), ",",
    "\"tag_dict\":", json_encode(payload.tag_dict), ",",
    "\"map_seed\":", json_encode(payload.map_seed), ",",
    "\"samples\":", encode_samples_lines(payload.samples), ",",
    "\"scan_queue\":", json_encode(payload.scan_queue), ",",
    "\"scan_total\":", json_encode(payload.scan_total), ",",
    "\"scan_started\":", json_encode(payload.scan_started), ",",
    "\"analyzer_queue\":", json_encode(payload.analyzer_queue), ",",
    "\"analyzer_pending\":", json_encode(payload.analyzer_pending), ",",
    "\"analyzer_results\":", json_encode(payload.analyzer_results), ",",
    "\"analyzer_mode\":", json_encode(payload.analyzer_mode),
    "}"
  }) end)

  if ok_json_enc and type(json_str) == "string" then
    local json_saved, json_err = sm_atomic_write(DATA_PATH, json_str)
    if not json_saved then
      sm_notify("Could not save the sample library: " .. tostring(json_err), "error")
    end
  else
    sm_notify("Could not save the sample library: " .. tostring(json_str), "error")
  end

  state.last_save_time = r.time_precise()
  state.scan_unsaved_results = false
  log(string.format("Saved sample cache in %.0fms (%d samples, compact v%d)", (state.last_save_time - save_start) * 1000, sample_count, payload.v or 2))
end


function clear_sample_cache()
  for _, p in ipairs({ DATA_PATH, DATA_LUA_PATH }) do
    os.remove(p)
    os.remove(p .. ".bak")
    os.remove(p .. ".tmp")
  end
end

function filter_samples_by_folders()
  if #state.folders == 0 then
    -- If no folders, clear all samples
    state.samples = {}
    state.active_tags = {}
    state.tag_list = {}
    state.tag_counts = {}
    rebuild_samples_path_index()
    return 0
  end

  local filtered_samples = {}
  local removed_count = 0

  for _, sample in ipairs(state.samples) do
    if sample.path then
      local keep_sample = false

      -- Check if sample belongs to any of the current folders (whole path
      -- components, so ".../Drums" does not also keep ".../Drums2").
      for _, folder in ipairs(state.folders) do
        if sample_under_scan_folder(sample.path, folder) then
          keep_sample = true
          break
        end
      end

      if keep_sample then
        table.insert(filtered_samples, sample)
      else
        removed_count = removed_count + 1
      end
    else
      -- Keep samples without path (shouldn't happen but safety check)
      table.insert(filtered_samples, sample)
    end
  end

  state.samples = filtered_samples
  rebuild_samples_path_index()

  -- Rebuild tag data since samples changed; the user's tag filters stay.
  rebuild_tag_index()

  if removed_count > 0 then
    log("Removed " .. removed_count .. " samples from removed folder(s)")
  end
  return removed_count
end

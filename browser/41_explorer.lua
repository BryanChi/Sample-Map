-- Sample Map Browser module: explorer
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function apply_custom_tags_to_samples()
  if not state.custom_tags then
    return
  end
  local changed = false
  for path, tags in pairs(state.custom_tags) do
    if type(tags) == "table" and #tags > 0 then
      local sample = find_sample_by_path(path)
      if not sample then
        sample = find_sample_by_path(normalize_path(path))
      end
      if sample then
        local before = #(sample.tags or {})
        sample.tags = append_unique_tags(sample.tags or {}, tags)
        if #(sample.tags) > before then
          changed = true
        end
      end
    end
  end
  if changed then
    rebuild_tag_index()
  end
end

function explorer_normalize_tag(tag)
  tag = tostring(tag or ""):gsub("^%s+", ""):gsub("%s+$", "")
  tag = tag:gsub("%s+", " ")
  return tag
end

function explorer_is_audio_name(name)
  local ext = tostring(name or ""):match("%.([^%.]+)$")
  if not ext then
    return false
  end
  return AUDIO_EXTS["." .. ext:lower()] == true
end

EXPLORER_ROW_H = 22
EXPLORER_MAX_DEPTH = 20
EXPLORER_MAX_LIST = 4000
EXPLORER_MAX_ROWS = 12000
EXPLORER_SEED_SLICE_MS = 0.006
EXPLORER_MAX_ENUM = 400

function explorer_invalidate_rows()
  state.explorer_row_list = nil
end

function explorer_is_safe_child(parent, child)
  parent = normalize_path(parent or "")
  child = normalize_path(child or "")
  if parent == "" or child == "" or child == parent then
    return false
  end
  return child:sub(1, #parent + 1) == (parent .. "/")
end

function explorer_collect_scan_roots()
  local roots = {}
  for _, folder in ipairs(state.folders or {}) do
    local path = normalize_path(folder)
    if path ~= "" then
      roots[#roots + 1] = path
    end
  end
  return roots
end

function explorer_path_in_library(path, roots)
  roots = roots or state.explorer_seed_roots
  if not path or path == "" or not roots then
    return false
  end
  for i = 1, #roots do
    local root = roots[i]
    if path == root then
      return true
    end
    local n = #root
    if #path > n and path:sub(1, n) == root and path:sub(n + 1, n + 1) == "/" then
      return true
    end
  end
  return false
end

function explorer_ensure_sorted(entry)
  if not entry or entry.sorted then
    return
  end
  sm_sort_ci(entry.dirs)
  sm_sort_ci(entry.files)
  entry.sorted = true
end

function explorer_ensure_cache_entry(path)
  path = normalize_path(path or "")
  local entry = state.explorer_dir_cache[path]
  if not entry then
    entry = {
      dirs = {},
      files = {},
      dir_set = {},
      file_set = {},
      sorted = true,
      source = "index",
    }
    state.explorer_dir_cache[path] = entry
    return entry
  end
  if not entry.dir_set then
    entry.dir_set = {}
    for _, name in ipairs(entry.dirs) do
      entry.dir_set[name] = true
    end
  end
  if not entry.file_set then
    entry.file_set = {}
    for _, name in ipairs(entry.files) do
      entry.file_set[name] = true
    end
  end
  return entry
end

function explorer_cache_add_dir(parent, name)
  if not name or name == "" then
    return
  end
  local entry = explorer_ensure_cache_entry(parent)
  if entry.dir_set[name] then
    return
  end
  if #entry.dirs >= EXPLORER_MAX_LIST then
    return
  end
  entry.dir_set[name] = true
  entry.dirs[#entry.dirs + 1] = name
  entry.sorted = false
end

function explorer_cache_add_file(parent, name)
  if not name or name == "" then
    return
  end
  local entry = explorer_ensure_cache_entry(parent)
  if entry.file_set[name] then
    return
  end
  if #entry.files >= EXPLORER_MAX_LIST then
    return
  end
  entry.file_set[name] = true
  entry.files[#entry.files + 1] = name
  entry.sorted = false
end

function explorer_index_sample(sample)
  if not state.explorer_cache_seeded and not state.explorer_seed_index then
    return
  end
  local path = normalize_path((sample and sample.path) or "")
  local name = path:match("([^/]+)$")
  local dir = path:match("(.+)/[^/]+$")
  if not dir or not name or not explorer_is_audio_name(name) then
    return
  end
  local roots = state.explorer_seed_roots
  if not roots then
    roots = explorer_collect_scan_roots()
    state.explorer_seed_roots = roots
  end
  if not explorer_path_in_library(dir, roots) then
    return
  end
  explorer_cache_add_file(dir, name)
  local child = dir
  local guard = 0
  while child and guard < EXPLORER_MAX_DEPTH do
    guard = guard + 1
    local parent = child:match("(.+)/[^/]+$")
    local child_name = child:match("([^/]+)$")
    if not parent or not child_name then
      break
    end
    if not explorer_path_in_library(parent, roots) then
      explorer_ensure_cache_entry(child)
      break
    end
    explorer_cache_add_dir(parent, child_name)
    child = parent
  end
  if state.explorer_cache_seeded then
    state.explorer_index_dirty = true
  end
end

function explorer_reset_seed_state()
  state.explorer_cache_seeded = false
  state.explorer_seed_index = nil
  state.explorer_seed_roots = nil
  state.explorer_disk_queue = {}
  state.explorer_disk_queued = {}
end

function explorer_invalidate_cache(path)
  state.explorer_has_audio = {}
  state.explorer_has_audio_queue = {}
  state.explorer_has_audio_queued = {}
  state.explorer_has_audio_seeded = false
  explorer_reset_seed_state()
  explorer_invalidate_rows()
  if path and path ~= "" then
    state.explorer_dir_cache[normalize_path(path)] = nil
    return
  end
  state.explorer_dir_cache = {}
end

function explorer_pump_seed_from_samples()
  if state.explorer_cache_seeded then
    return
  end
  local samples = state.samples or {}
  if not state.explorer_seed_index then
    state.explorer_seed_index = 1
    state.explorer_seed_roots = explorer_collect_scan_roots()
    for i = 1, #state.explorer_seed_roots do
      explorer_ensure_cache_entry(state.explorer_seed_roots[i])
    end
  end
  local idx = state.explorer_seed_index
  local started = r.time_precise and r.time_precise() or 0
  while idx <= #samples do
    explorer_index_sample(samples[idx])
    idx = idx + 1
    if r.time_precise and (r.time_precise() - started) > EXPLORER_SEED_SLICE_MS then
      break
    end
  end
  if idx ~= state.explorer_seed_index then
    state.explorer_seed_index = idx
    explorer_invalidate_rows()
  else
    state.explorer_seed_index = idx
  end
  if idx > #samples then
    state.explorer_cache_seeded = true
    if state.explorer_want_disk_refresh then
      state.explorer_want_disk_refresh = false
      explorer_queue_expanded_disk_refresh()
    end
  end
end

function explorer_queue_disk_refresh(path)
  path = normalize_path(path or "")
  if path == "" then
    return
  end
  state.explorer_disk_queue = state.explorer_disk_queue or {}
  state.explorer_disk_queued = state.explorer_disk_queued or {}
  if state.explorer_disk_queued[path] then
    return
  end
  state.explorer_disk_queued[path] = true
  state.explorer_disk_queue[#state.explorer_disk_queue + 1] = path
end

function explorer_queue_expanded_disk_refresh()
  for path, open in pairs(state.explorer_open_dirs or {}) do
    if open then
      explorer_queue_disk_refresh(path)
    end
  end
end

function explorer_pump_disk_refresh()
  local queue = state.explorer_disk_queue
  if not queue or #queue == 0 then
    return
  end
  -- List directories until the per-frame budget (checked before each one) runs out.
  local started = r.time_precise()
  local listed = 0
  while #queue > 0 and (listed == 0 or (r.time_precise() - started) < 0.004) do
    local path = table.remove(queue, 1)
    state.explorer_disk_queued[path] = nil
    explorer_list_dir_from_disk(path)
    listed = listed + 1
  end
  explorer_invalidate_rows()
end

function explorer_shell_quote(path)
  return "'" .. tostring(path or ""):gsub("'", "'\\''") .. "'"
end

-- REAPER's directory enumeration (no shell process per directory).
function explorer_list_dir_via_enumerate(path, dirs, files)
  -- Index -1 clears REAPER's cached listing so a refresh sees disk changes.
  pcall(r.EnumerateSubdirectories, path, -1)
  pcall(r.EnumerateFiles, path, -1)
  local i = 0
  local subdir = r.EnumerateSubdirectories(path, i)
  while subdir do
    if subdir ~= "." and subdir ~= ".." and not subdir:match("^%.") then
      local child = explorer_join_path(path, subdir)
      if explorer_is_safe_child(path, child) then
        dirs[#dirs + 1] = subdir
      end
    end
    i = i + 1
    if i >= EXPLORER_MAX_ENUM or #dirs >= EXPLORER_MAX_LIST then
      break
    end
    subdir = r.EnumerateSubdirectories(path, i)
  end

  i = 0
  local file = r.EnumerateFiles(path, i)
  local seen = 0
  while file do
    seen = seen + 1
    if explorer_is_audio_name(file) then
      files[#files + 1] = file
    end
    i = i + 1
    if seen >= EXPLORER_MAX_ENUM or #files >= EXPLORER_MAX_LIST then
      break
    end
    file = r.EnumerateFiles(path, i)
  end
  return true
end

function explorer_list_dir_from_disk(path)
  path = normalize_path(path or "")
  if path == "" then
    return nil, nil
  end
  local vol = volume_root_from_path(path)
  if vol and state.missing_volumes[vol] then
    return nil, nil
  end

  local dirs, files = {}, {}
  local ok = explorer_list_dir_via_enumerate(path, dirs, files)
  if not ok then
    return nil, nil
  end

  sm_sort_ci(dirs)
  sm_sort_ci(files)
  local dir_set, file_set = {}, {}
  for _, name in ipairs(dirs) do
    dir_set[name] = true
  end
  for _, name in ipairs(files) do
    file_set[name] = true
  end
  state.explorer_dir_cache[path] = {
    dirs = dirs,
    files = files,
    dir_set = dir_set,
    file_set = file_set,
    sorted = true,
    source = "disk",
  }
  return dirs, files
end

function explorer_seed_has_audio_from_samples()
  if state.explorer_has_audio_seeded then
    return
  end
  state.explorer_has_audio_seeded = true
  state.explorer_has_audio = state.explorer_has_audio or {}
  for _, sample in ipairs(state.samples or {}) do
    local dir = normalize_path(sample.path or ""):match("(.+)/[^/]+$")
    local guard = 0
    while dir and dir ~= "" and guard < EXPLORER_MAX_DEPTH do
      guard = guard + 1
      if state.explorer_has_audio[dir] == true then
        break
      end
      state.explorer_has_audio[dir] = true
      local parent = dir:match("(.+)/[^/]+$")
      if not parent or parent == dir then
        break
      end
      dir = parent
    end
  end
end

function explorer_mark_has_audio(path)
  local dir = normalize_path(path or "")
  local guard = 0
  local changed = false
  while dir and dir ~= "" and guard < EXPLORER_MAX_DEPTH do
    guard = guard + 1
    if state.explorer_has_audio[dir] ~= true then
      state.explorer_has_audio[dir] = true
      changed = true
    end
    local parent = dir:match("(.+)/[^/]+$")
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  if changed then
    explorer_invalidate_rows()
  end
end

function explorer_queue_has_audio(path)
  path = normalize_path(path or "")
  if path == "" then
    return
  end
  local slashes = 0
  path:gsub("/", function()
    slashes = slashes + 1
  end)
  if slashes > 40 then
    state.explorer_has_audio = state.explorer_has_audio or {}
    state.explorer_has_audio[path] = false
    return
  end
  state.explorer_has_audio = state.explorer_has_audio or {}
  state.explorer_has_audio_queue = state.explorer_has_audio_queue or {}
  state.explorer_has_audio_queued = state.explorer_has_audio_queued or {}
  if state.explorer_has_audio[path] ~= nil or state.explorer_has_audio_queued[path] then
    return
  end
  state.explorer_has_audio_queued[path] = true
  state.explorer_has_audio_queue[#state.explorer_has_audio_queue + 1] = path
end

function explorer_pump_has_audio()
  if not state.explorer_hide_empty then
    return
  end
  explorer_seed_has_audio_from_samples()
  local queue = state.explorer_has_audio_queue or {}
  if #queue == 0 then
    return
  end
  local budget = 10
  local started = r.time_precise and r.time_precise() or 0
  while budget > 0 and #queue > 0 do
    local path = table.remove(queue, 1)
    state.explorer_has_audio_queued[path] = nil
    if state.explorer_has_audio[path] == nil then
      local dirs, files = explorer_list_dir(path)
      budget = budget - 1
      if files and #files > 0 then
        explorer_mark_has_audio(path)
      elseif not dirs then
        state.explorer_has_audio[path] = false
        explorer_invalidate_rows()
      else
        local unknown, any_true = 0, false
        for _, name in ipairs(dirs) do
          local child = explorer_join_path(path, name)
          if explorer_is_safe_child(path, child) then
            local cached = state.explorer_has_audio[child]
            if cached == true then
              any_true = true
              break
            elseif cached == nil then
              unknown = unknown + 1
              explorer_queue_has_audio(child)
            end
          end
        end
        if any_true then
          explorer_mark_has_audio(path)
        elseif unknown == 0 then
          state.explorer_has_audio[path] = false
          explorer_invalidate_rows()
        else
          explorer_queue_has_audio(path)
        end
      end
    end
    if r.time_precise and (r.time_precise() - started) > 0.006 then
      break
    end
  end
end

function explorer_dir_has_audio(path)
  path = normalize_path(path or "")
  if path == "" then
    return false
  end
  explorer_seed_has_audio_from_samples()
  local cached = state.explorer_has_audio[path]
  if cached ~= nil then
    return cached
  end
  explorer_queue_has_audio(path)
  return true
end

function explorer_dir_should_show(path)
  if not state.explorer_hide_empty then
    return true
  end
  return explorer_dir_has_audio(path)
end

function folder_filter_list()
  return state.folder_filter_paths or {}
end

function folder_filter_key()
  local paths = {}
  for _, path in ipairs(folder_filter_list()) do
    paths[#paths + 1] = path
  end
  table.sort(paths)
  return table.concat(paths, "\n")
end

function folder_filter_has(path)
  path = normalize_path(path or "")
  if path == "" then
    return false
  end
  for _, existing in ipairs(folder_filter_list()) do
    if existing == path then
      return true
    end
  end
  return false
end

function folder_filter_add(path)
  path = normalize_path(path or "")
  if path == "" or folder_filter_has(path) then
    return
  end
  state.folder_filter_paths = state.folder_filter_paths or {}
  state.folder_filter_paths[#state.folder_filter_paths + 1] = path
end

function folder_filter_remove(path)
  path = normalize_path(path or "")
  local kept = {}
  for _, existing in ipairs(folder_filter_list()) do
    if existing ~= path then
      kept[#kept + 1] = existing
    end
  end
  state.folder_filter_paths = kept
end

function folder_filter_toggle(path)
  if folder_filter_has(path) then
    folder_filter_remove(path)
  else
    folder_filter_add(path)
  end
end

function folder_filter_matches_sample(sample_path)
  local filters = folder_filter_list()
  if #filters == 0 then
    return true
  end
  sample_path = normalize_path(sample_path or "")
  if sample_path == "" then
    return false
  end
  for _, filter_path in ipairs(filters) do
    if sample_path == filter_path then
      return true
    end
    if #sample_path > #filter_path and sample_path:sub(1, #filter_path) == filter_path then
      if sample_path:sub(#filter_path + 1, #filter_path + 1) == "/" then
        return true
      end
    end
  end
  return false
end

function folder_filter_chip_label(path)
  path = normalize_path(path or "")
  local name = path:match("([^/]+)$") or path
  local dup = 0
  for _, existing in ipairs(folder_filter_list()) do
    local other = existing:match("([^/]+)$") or existing
    if string.lower(other) == string.lower(name) then
      dup = dup + 1
    end
  end
  if dup > 1 then
    local parent = path:match("([^/]+)/[^/]+$")
    if parent then
      return parent .. " / " .. name
    end
  end
  return name
end

function render_folder_filter_chips(opts)
  opts = opts or {}
  local filters = folder_filter_list()
  if #filters == 0 then
    return false
  end
  for i, path in ipairs(filters) do
    local label = folder_filter_chip_label(path)
    local chip_w = calc_tag_chip_width(label)
    if i > 1 or not opts.new_line then
      imgui_same_line_if_fits(chip_w, i == 1 and 8 or 4)
    end
    if draw_ui_button("folder_filter_chip_" .. path, label, nil, 22, {
      compact = true,
      selected = true,
    }) then
      folder_filter_remove(path)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, path .. "\nClick to remove this folder filter")
    end
  end
  return true
end

function explorer_folder_filter_active(path)
  return folder_filter_has(path)
end

function explorer_toggle_folder_filter(path)
  folder_filter_toggle(path)
end

function explorer_list_dir(path)
  path = normalize_path(path or "")
  if path == "" then
    return nil, nil
  end
  explorer_pump_seed_from_samples()
  local cache = state.explorer_dir_cache[path]
  if cache then
    explorer_ensure_sorted(cache)
    return cache.dirs, cache.files
  end
  if not state.explorer_cache_seeded then
    return {}, {}
  end
  -- Stay off the disk while browsing. Missing folders show empty until Refresh.
  cache = explorer_ensure_cache_entry(path)
  return cache.dirs, cache.files
end

function explorer_name_matches(name, filter)
  if not filter or filter == "" then
    return true
  end
  return string.find(string.lower(tostring(name or "")), filter, 1, true) ~= nil
end

function explorer_dir_has_visible_match(path, filter, depth, seen)
  if not filter or filter == "" then
    return true
  end
  depth = depth or 0
  if depth > EXPLORER_MAX_DEPTH then
    return false
  end
  path = normalize_path(path or "")
  seen = seen or {}
  if path == "" or seen[path] then
    return false
  end
  seen[path] = true
  local cache = state.explorer_dir_cache[path]
  if not cache then
    return false
  end
  for _, name in ipairs(cache.dirs) do
    if explorer_name_matches(name, filter) then
      return true
    end
    local child = explorer_join_path(path, name)
    if explorer_is_safe_child(path, child) and explorer_dir_has_visible_match(child, filter, depth + 1, seen) then
      return true
    end
  end
  for _, name in ipairs(cache.files) do
    if explorer_name_matches(name, filter) then
      return true
    end
  end
  return false
end

function explorer_join_path(dir, name)
  return normalize_path((dir or "") .. "/" .. (name or ""))
end

function explorer_custom_tags_for(path)
  path = normalize_path(path or "")
  if path == "" or not state.custom_tags then
    return nil, path
  end
  local tags = state.custom_tags[path]
  if tags then
    return tags, path
  end
  local key = path_index_key(path)
  for stored, stored_tags in pairs(state.custom_tags) do
    if path_index_key(stored) == key then
      return stored_tags, stored
    end
  end
  return nil, path
end

function explorer_get_tags(path)
  path = normalize_path(path or "")
  local sample = find_sample_by_path(path)
  if sample and type(sample.tags) == "table" then
    return sample.tags
  end
  local custom = explorer_custom_tags_for(path)
  return custom or {}
end

function explorer_known_tags()
  local seen, out = {}, {}
  for _, entry in ipairs(TAG_KEYWORDS) do
    if entry.tag and not seen[entry.tag] then
      seen[entry.tag] = true
      out[#out + 1] = entry.tag
    end
  end
  for _, item in ipairs(state.tag_list or {}) do
    if item.tag and not seen[item.tag] then
      seen[item.tag] = true
      out[#out + 1] = item.tag
    end
  end
  for child, _ in pairs(state.tag_parent_map or {}) do
    if child and child ~= "" and not seen[child] then
      seen[child] = true
      out[#out + 1] = child
    end
  end
  sm_sort_ci(out)
  return out
end

function explorer_add_tag(path, tag)
  path = normalize_path(path or "")
  tag = explorer_normalize_tag(tag)
  if path == "" or tag == "" then
    return false
  end
  if state.deleted_tags then
    state.deleted_tags[string.lower(tag)] = nil
  end

  local sample = find_sample_by_path(path)
  local store_path = (sample and sample.path) or path
  state.custom_tags = state.custom_tags or {}
  local custom = select(1, explorer_custom_tags_for(store_path)) or state.custom_tags[store_path] or {}
  local already = false
  for _, existing in ipairs(custom) do
    if existing == tag then
      already = true
      break
    end
  end
  if not already then
    custom[#custom + 1] = tag
    state.custom_tags[store_path] = custom
  end

  if sample then
    sample.tags = append_unique_tags(sample.tags or {}, { tag })
    if preview_sample_obj and preview_sample_obj.path and path_index_key(preview_sample_obj.path) == path_index_key(store_path) then
      preview_sample_obj.tags = sample.tags
    end
    rebuild_tag_index()
    save_samples()
  end
  save_config()
  return true
end

function explorer_remove_tag(path, tag)
  path = normalize_path(path or "")
  if path == "" or not tag then
    return false
  end

  local custom, store_path = explorer_custom_tags_for(path)
  if custom and store_path then
    local kept = {}
    for _, existing in ipairs(custom) do
      if existing ~= tag then
        kept[#kept + 1] = existing
      end
    end
    if #kept > 0 then
      state.custom_tags[store_path] = kept
    else
      state.custom_tags[store_path] = nil
    end
  end

  local sample = find_sample_by_path(path)
  if sample and type(sample.tags) == "table" then
    local kept = {}
    for _, existing in ipairs(sample.tags) do
      if existing ~= tag then
        kept[#kept + 1] = existing
      end
    end
    sample.tags = kept
    if preview_sample_obj and preview_sample_obj.path and path_index_key(preview_sample_obj.path) == path_index_key(sample.path or path) then
      preview_sample_obj.tags = kept
    end
    rebuild_tag_index()
    save_samples()
  end
  save_config()
  return true
end

function explorer_sample_for_path(path)
  path = normalize_path(path or "")
  local sample = find_sample_by_path(path)
  if sample then
    return sample
  end
  return {
    path = path,
    name = path:match("([^/]+)$") or path,
    folder = path:match("(.+)/[^/]+$") or "",
    tags = explorer_get_tags(path),
    duration = 0,
  }
end

function explorer_select_file(path, play)
  path = normalize_path(path or "")
  if path == "" then
    return
  end
  state.explorer_selected_path = path
  local sample = explorer_sample_for_path(path)
  if play then
    preview_sample(sample)
  end
  if not preview_sample_obj or preview_sample_obj.path ~= path then
    preview_sample_obj = sample
  end
end

function explorer_match_tags(query, exclude_set)
  query = string.lower(explorer_normalize_tag(query))
  if query == "" then
    return {}
  end
  local out = {}
  for _, tag in ipairs(explorer_known_tags()) do
    if not (exclude_set and exclude_set[tag]) then
      if string.find(string.lower(tag), query, 1, true) then
        out[#out + 1] = tag
        if #out >= 8 then
          break
        end
      end
    end
  end
  return out
end

function explorer_open_tag_popup(path)
  path = normalize_path(path or "")
  if path == "" then
    return
  end
  state.explorer_tag_target = path
  state.explorer_tag_input = ""
  state.explorer_selected_path = path
  local mx, my = r.ImGui_GetMousePos(ctx)
  state.explorer_tag_popup_pos = { x = mx, y = my }
  state.explorer_tag_popup_open = true
end

function explorer_draw_wrapped_tags(tags, id_prefix, active_lookup, on_click, after_item)
  if not tags or #tags == 0 then
    return
  end
  for i, tag in ipairs(tags) do
    local chip_w = calc_tag_chip_width(tag)
    if i > 1 or after_item then
      imgui_same_line_if_fits(chip_w, 4)
    end
    local active = active_lookup and active_lookup[tag] or false
    if draw_tag_button(ctx, tag, active, tag, id_prefix) then
      on_click(tag)
    end
  end
end

function explorer_render_tag_editor(path, id_prefix)
  path = normalize_path(path or "")
  if path == "" then
    return
  end
  local current = explorer_get_tags(path)
  local current_set = {}
  for _, tag in ipairs(current) do
    current_set[tag] = true
  end

  if draw_ui_button(id_prefix .. "add_tag", "+", 22, 22, { compact = true, pill = true }) then
    tag_add_open_for(path)
    r.ImGui_OpenPopup(ctx, "##tag_add_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Add a tag")
  end
  explorer_draw_wrapped_tags(current, id_prefix .. "cur_", current_set, function(tag)
    explorer_remove_tag(path, tag)
  end, true)
  render_tag_add_popup()
end

function explorer_render_row(kind, path, name, depth, offline)
  local row_h = 22
  local indent = depth * 16
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local selected = state.explorer_selected_path == path
  local open = kind == "dir" and state.explorer_open_dirs[path] == true
  local filtering = kind == "dir" and explorer_folder_filter_active(path)

  r.ImGui_InvisibleButton(ctx, "##exp_" .. kind .. "_" .. path, math.max(40, avail_w), row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local right_clicked = r.ImGui_IsItemClicked(ctx, 1)
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)

  if selected or filtering then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, UI_THEME.accent_fill, 4.0)
  elseif hovered then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, UI_THEME.surface_hvr, 4.0)
  end

  local cx = x0 + indent + 10
  local cy = (y0 + y1) * 0.5
  local icon_hovered = false
  if kind == "dir" then
    ui_button_draw_icon(dl, open and "chev_down" or "chev_right", cx, cy, 12, hovered and UI_THEME.text or UI_THEME.text_mute)
    cx = cx + 14
    icon_hovered = hovered and mx >= (cx - 9) and mx <= (cx + 9) and my >= y0 and my <= y1
    local show_filter = filtering or icon_hovered
    local icon_col
    if offline then
      icon_col = UI_THEME.text_mute
    elseif show_filter then
      icon_col = UI_THEME.accent_hvr
    elseif hovered then
      icon_col = UI_THEME.folder_hvr
    else
      icon_col = UI_THEME.folder
    end
    ui_button_draw_icon(dl, show_filter and "filter" or "folder", cx, cy, 14, icon_col)
    cx = cx + 14
    if icon_hovered then
      r.ImGui_SetTooltip(ctx, filtering and "Remove this folder from the filter" or "Add this folder to the sample map filter")
    end
  else
    cx = cx + 14
    ui_button_draw_icon(dl, "audio", cx, cy, 14, selected and UI_THEME.accent_hvr or UI_THEME.text_dim)
    cx = cx + 14
  end

  local label = name
  if offline then
    label = name .. "  (offline)"
  end
  local _, th = r.ImGui_CalcTextSize(ctx, label)
  local text_col = offline and UI_THEME.text_mute or ((selected or hovered) and UI_THEME.text or UI_THEME.text_dim)
  r.ImGui_DrawList_AddText(dl, cx + 4, cy - th * 0.5, text_col, label)

  if kind == "file" then
    local tags = explorer_get_tags(path)
    if #tags > 0 then
      local chip_x = cx + 8 + r.ImGui_CalcTextSize(ctx, label)
      local shown = 0
      for _, tag in ipairs(tags) do
        if shown >= 3 then
          local extra = string.format("+%d", #tags - shown)
          r.ImGui_DrawList_AddText(dl, chip_x + 4, cy - th * 0.5, UI_THEME.text_mute, extra)
          break
        end
        local tw = r.ImGui_CalcTextSize(ctx, tag)
        local chip_w = tw + 10
        if chip_x + chip_w > x1 - 8 then
          break
        end
        local tag_color = state.tag_colors[tag] or 0x336699
        local cr, cg, cb = extract_rgb(tag_color)
        local fill = build_color_rrgbbaa(cr, cg, cb, 90)
        r.ImGui_DrawList_AddRectFilled(dl, chip_x, y0 + 4, chip_x + chip_w, y1 - 4, fill, 6.0)
        r.ImGui_DrawList_AddText(dl, chip_x + 5, cy - th * 0.5, 0xF0F0F0FF, tag)
        chip_x = chip_x + chip_w + 4
        shown = shown + 1
      end
    end
  end

  if kind == "dir" and clicked then
    if icon_hovered then
      explorer_toggle_folder_filter(path)
    else
      state.explorer_open_dirs[path] = not open
      explorer_invalidate_rows()
      save_config()
    end
  elseif kind == "file" and clicked then
    explorer_select_file(path, true)
  end
  if kind == "file" and right_clicked then
    explorer_open_tag_popup(path)
  end
end

function explorer_collect_rows()
  local rows = {}
  local filter = string.lower(state.explorer_filter or "")
  local seen = {}

  local function consider_dir(path, name, depth, offline)
    if #rows >= EXPLORER_MAX_ROWS or depth > EXPLORER_MAX_DEPTH then
      return
    end
    path = normalize_path(path or "")
    if path == "" or seen[path] then
      return
    end
    seen[path] = true
    if not offline and not explorer_dir_should_show(path) then
      return
    end
    if filter ~= ""
        and not explorer_name_matches(name, filter)
        and not state.explorer_open_dirs[path]
        and not explorer_dir_has_visible_match(path, filter) then
      return
    end
    rows[#rows + 1] = {
      kind = "dir",
      path = path,
      name = name,
      depth = depth,
      offline = offline and true or false,
    }
    if not state.explorer_open_dirs[path] then
      return
    end
    if offline then
      rows[#rows + 1] = { kind = "msg", text = "Folder is offline", depth = depth + 1 }
      return
    end
    local dirs, files = explorer_list_dir(path)
    if not dirs then
      rows[#rows + 1] = { kind = "msg", text = "Folder unavailable", depth = depth + 1 }
      return
    end
    for _, child_name in ipairs(dirs) do
      local child = explorer_join_path(path, child_name)
      if explorer_is_safe_child(path, child) then
        consider_dir(child, child_name, depth + 1, false)
      end
    end
    for _, file_name in ipairs(files) do
      if #rows >= EXPLORER_MAX_ROWS then
        break
      end
      if explorer_name_matches(file_name, filter) then
        rows[#rows + 1] = {
          kind = "file",
          path = explorer_join_path(path, file_name),
          name = file_name,
          depth = depth + 1,
          offline = false,
        }
      end
    end
  end

  for _, folder in ipairs(state.folders) do
    local root = normalize_path(folder)
    local root_name = root:match("([^/]+)$") or root
    local vol = volume_root_from_path(root)
    local offline = (vol and state.missing_volumes[vol]) or state.missing_scan_folders[root]
    consider_dir(root, root_name, 0, offline)
  end
  return rows
end

function explorer_get_rows()
  if not state.explorer_row_list then
    state.explorer_row_list = explorer_collect_rows()
  end
  return state.explorer_row_list
end

function explorer_render_clipped_rows(rows)
  local row_h = EXPLORER_ROW_H
  local scroll_y = 0
  if r.ImGui_GetScrollY then
    scroll_y = r.ImGui_GetScrollY(ctx) or 0
  end
  local avail_h = select(2, r.ImGui_GetContentRegionAvail(ctx)) or 400
  local pad = 6
  local first = math.max(1, math.floor(scroll_y / row_h) - pad + 1)
  local last = math.min(#rows, math.ceil((scroll_y + avail_h) / row_h) + pad)
  if first > 1 then
    r.ImGui_Dummy(ctx, 1, (first - 1) * row_h)
  end
  for i = first, last do
    local row = rows[i]
    if row.kind == "msg" then
      r.ImGui_Dummy(ctx, 1, row_h)
      local x0, y0 = r.ImGui_GetItemRectMin(ctx)
      r.ImGui_DrawList_AddText(
        r.ImGui_GetWindowDrawList(ctx),
        x0 + (row.depth or 0) * 16 + 24,
        y0 + 4,
        UI_THEME.text_mute,
        row.text or ""
      )
    else
      explorer_render_row(row.kind, row.path, row.name, row.depth, row.offline)
    end
  end
  if last < #rows then
    r.ImGui_Dummy(ctx, 1, (#rows - last) * row_h)
  end
end

function explorer_render_tag_popup()
  local pos = state.explorer_tag_popup_pos
  if state.explorer_tag_popup_open then
    state.explorer_tag_popup_open = false
    if pos and r.ImGui_SetNextWindowPos then
      r.ImGui_SetNextWindowPos(ctx, pos.x, pos.y, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
    end
    r.ImGui_OpenPopup(ctx, "##explorer_tag_popup")
  elseif pos and r.ImGui_SetNextWindowPos then
    r.ImGui_SetNextWindowPos(
      ctx,
      pos.x,
      pos.y,
      r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
    )
  end
  if not r.ImGui_BeginPopup(ctx, "##explorer_tag_popup") then
    if not state.explorer_tag_popup_open then
      state.explorer_tag_popup_pos = nil
    end
    return
  end
  local path = state.explorer_tag_target
  if not path or path == "" then
    r.ImGui_EndPopup(ctx)
    return
  end

  r.ImGui_Text(ctx, path:match("([^/]+)$") or path)
  r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Assigned tags")
  r.ImGui_Separator(ctx)
  r.ImGui_PushItemWidth(ctx, 260)
  explorer_render_tag_editor(path, "popup_")
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_Separator(ctx)
  if r.ImGui_Selectable(ctx, "Reveal in Finder / Explorer") then
    seq_reveal_sample_in_explorer(explorer_sample_for_path(path))
  end
  r.ImGui_EndPopup(ctx)
end

EXPLORER_SPLIT_W = 6
EXPLORER_DOCK_MIN_W = 220
EXPLORER_DOCK_MAX_W = 900

function explorer_dock_host()
  local d = state.explorer_docked
  if d == true then
    return "sample_map"
  end
  if d == "sample_map" or d == "sequencer" then
    return d
  end
  return nil
end

function explorer_is_docked_in(host)
  return state.explorer_open and explorer_dock_host() == host
end

function explorer_host_is_open(host)
  if host == "sample_map" then
    return sample_map_is_open()
  end
  if host == "sequencer" then
    return sequencer_is_open()
  end
  return false
end

function explorer_dock_width()
  return math.max(EXPLORER_DOCK_MIN_W, math.min(EXPLORER_DOCK_MAX_W, state.explorer_width or 320))
end

function explorer_draw_dock_splitter(host, height, avail_x)
  local split_w = EXPLORER_SPLIT_W
  r.ImGui_InvisibleButton(ctx, "##explorer_split_" .. tostring(host), split_w, math.max(1, height or 0))
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local dragging = state.explorer_split_drag and state.explorer_split_drag.host == host
  if hovered or active or dragging then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    end
  end
  local x0, y0 = r.ImGui_GetItemRectMin(ctx)
  local x1, y1 = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local col = (active or dragging) and UI_THEME.accent or (hovered and UI_THEME.border_hvr or UI_THEME.border)
  local mid = (x0 + x1) * 0.5
  r.ImGui_DrawList_AddRectFilled(dl, mid - 1.0, y0 + 10, mid + 1.0, y1 - 10, col, 1.0)

  local mx = r.ImGui_GetMousePos(ctx)
  if active then
    if not dragging then
      state.explorer_split_drag = {
        host = host,
        start_x = mx,
        width0 = explorer_dock_width(),
        avail_x = avail_x or 0,
      }
    else
      local drag = state.explorer_split_drag
      local max_w = math.max(EXPLORER_DOCK_MIN_W, (drag.avail_x or 0) - 180 - split_w)
      max_w = math.min(EXPLORER_DOCK_MAX_W, max_w)
      local new_w = drag.width0 + (drag.start_x - mx)
      state.explorer_width = math.max(EXPLORER_DOCK_MIN_W, math.min(max_w, new_w))
    end
  elseif dragging then
    state.explorer_split_drag = nil
    save_config()
  end
end

function explorer_render_toolbar()
  if render_folder_filter_chips({ new_line = true }) then
    r.ImGui_Spacing(ctx)
  end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 4)
  if r.ImGui_InputTextWithHint then
    local changed, text = r.ImGui_InputTextWithHint(ctx, "##explorer_filter", "Filter folders and files…", state.explorer_filter or "")
    seq_mark_text_input_item()
    if changed then
      state.explorer_filter = text
      explorer_invalidate_rows()
    end
  else
    local changed, text = r.ImGui_InputText(ctx, "##explorer_filter", state.explorer_filter or "", 256)
    seq_mark_text_input_item()
    if changed then
      state.explorer_filter = text
      explorer_invalidate_rows()
    end
  end
  r.ImGui_SameLine(ctx)
  if draw_ui_button("explorer_hide_empty", "", 22, 22, {
    icon = "hide",
    compact = true,
    selected = state.explorer_hide_empty,
  }) then
    state.explorer_hide_empty = not state.explorer_hide_empty
    explorer_invalidate_rows()
    save_config()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, state.explorer_hide_empty
      and "Showing only folders that contain audio"
      or "Hide folders that contain no audio files")
  end
  r.ImGui_SameLine(ctx)
  if draw_ui_button("explorer_refresh", "Refresh", nil, nil, { compact = true }) then
    state.explorer_want_disk_refresh = true
    explorer_invalidate_cache()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Reload folder contents from disk")
  end
  r.ImGui_SameLine(ctx)
  if explorer_dock_host() then
    if draw_ui_button("explorer_undock", "Undock", nil, nil, { compact = true }) then
      state.explorer_docked = false
      save_config()
    end
  else
    if sample_map_is_open() then
      if draw_ui_button("explorer_dock_map", "Dock to Map", nil, nil, { compact = true }) then
        state.explorer_docked = "sample_map"
        save_config()
      end
    end
    if sequencer_is_open() then
      if sample_map_is_open() then
        r.ImGui_SameLine(ctx)
      end
      if draw_ui_button("explorer_dock_seq", "Dock to Sequencer", nil, nil, { compact = true }) then
        state.explorer_docked = "sequencer"
        save_config()
      end
    end
  end
  r.ImGui_PopStyleVar(ctx)
end

function explorer_render_tree()
  local child_flags = 0
  child_flags = sm_child_border_flag()
  local _, after_toolbar = r.ImGui_GetContentRegionAvail(ctx)
  local tree_h = math.max(80, after_toolbar - 6)

  if r.ImGui_BeginChild(ctx, "explorer_tree", 0, tree_h, child_flags) then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
    local rows = explorer_get_rows()
    if #rows == 0 then
      r.ImGui_TextColored(ctx, UI_THEME.text_mute, "No folders to show")
    else
      explorer_render_clipped_rows(rows)
    end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_EndChild(ctx)
  end
end

function render_explorer_content()
  if #state.folders == 0 then
    r.ImGui_TextColored(ctx, UI_THEME.text_dim, "No scan folders yet.")
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Add a folder in Settings, then browse it here and right-click files to tag them.")
    if draw_ui_button("explorer_open_settings", "Open Settings", nil, nil, { style = "primary" }) then
      state.settings_open = true
    end
    return
  end

  if not next(state.explorer_open_dirs) then
    for _, folder in ipairs(state.folders) do
      state.explorer_open_dirs[normalize_path(folder)] = true
    end
  end

  explorer_pump_seed_from_samples()
  if state.explorer_index_dirty then
    state.explorer_index_dirty = false
    explorer_invalidate_rows()
  end
  explorer_pump_disk_refresh()
  explorer_pump_has_audio()
  explorer_render_toolbar()
  if not state.explorer_cache_seeded then
    local n = #(state.samples or {})
    local i = math.max(0, (state.explorer_seed_index or 1) - 1)
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, string.format("Indexing folders… %d / %d", i, n))
  elseif (state.explorer_disk_queue and #state.explorer_disk_queue > 0) then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Refreshing folders from disk…")
  else
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Right-click a file to set custom tags")
  end
  explorer_render_tree()
  explorer_render_tag_popup()
end

function render_explorer_window()
  if not state.explorer_open then
    return
  end
  local host = explorer_dock_host()
  if host and explorer_host_is_open(host) then
    return
  end

  -- Recover from a leftover 0-width native dock node, then keep this window floating.
  if not state.explorer_window_recovered then
    state.explorer_window_recovered = true
    if r.ImGui_SetNextWindowDockID then
      r.ImGui_SetNextWindowDockID(ctx, 0, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
    end
    r.ImGui_SetNextWindowSize(ctx, 380, 640, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
    if r.ImGui_SetNextWindowCollapsed then
      r.ImGui_SetNextWindowCollapsed(ctx, false, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
    end
  elseif r.ImGui_SetNextWindowDockID then
    r.ImGui_SetNextWindowDockID(ctx, 0, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0)
  else
    r.ImGui_SetNextWindowSize(ctx, 380, 640, r.ImGui_Cond_FirstUseEver())
  end
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 260, 220, 1600, 1600)
  end

  local flags = r.ImGui_WindowFlags_None and r.ImGui_WindowFlags_None() or 0
  if r.ImGui_WindowFlags_NoDocking then
    flags = flags | r.ImGui_WindowFlags_NoDocking()
  end
  if r.ImGui_WindowFlags_NoCollapse then
    flags = flags | r.ImGui_WindowFlags_NoCollapse()
  end

  -- ReaImGui can fail Begin during docker attach/detach without pushing a window.
  -- Calling End() in that state poisons the context and prevents the script from restarting.
  local began_ok, visible, open = pcall(r.ImGui_Begin, ctx, "Library Explorer", true, flags)
  if not began_ok then
    return
  end
  if visible then
    render_explorer_content()
    pcall(r.ImGui_End, ctx)
  end
  if open == false then
    state.explorer_open = false
    save_config()
  end
end

function render_explorer_docked_panel(height)
  if not (state.explorer_open and explorer_dock_host()) then
    return
  end
  local child_flags = 0
  child_flags = sm_child_border_flag()
  local w = explorer_dock_width()
  if r.ImGui_BeginChild(ctx, "explorer_dock", w, math.max(0, height or 0), child_flags) then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 4)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, "Library Explorer")
    r.ImGui_SameLine(ctx)
    local remain = r.ImGui_GetContentRegionAvail(ctx)
    if remain > 86 then
      r.ImGui_Dummy(ctx, remain - 86, 1)
      r.ImGui_SameLine(ctx, 0, 0)
    end
    if draw_ui_button("explorer_dock_close", "Close", nil, nil, { compact = true, style = "danger" }) then
      state.explorer_open = false
      save_config()
    end
    r.ImGui_PopStyleVar(ctx)
    render_explorer_content()
    r.ImGui_EndChild(ctx)
  end
end

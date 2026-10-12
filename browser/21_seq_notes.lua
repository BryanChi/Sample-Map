-- Sample Map Browser module: seq_notes
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function get_seq_note(region, track_id, step_key)
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local notes = get_track_note_table(pattern, track_id, false)
  return notes and notes[tostring(step_key)] or nil
end

function set_seq_note(region, track_id, step_key, note)
  local pattern = region and get_seq_pattern(region.pattern_id, true)
  local notes = get_track_note_table(pattern, track_id, true)
  if type(note) == "table" and (type(note.vary_filter) ~= "string" or seq_trim_text(note.vary_filter) == "") then
    local text = seq_cell_vary_filter(region, track_id, step_key, note)
    if text then
      note.vary_filter = text
    end
  end
  notes[tostring(step_key)] = note
end

function delete_seq_note(region, track_id, step_key)
  local pattern = region and get_seq_pattern(region.pattern_id, false)
  local notes = get_track_note_table(pattern, track_id, false)
  if notes then
    notes[tostring(step_key)] = nil
  end
end

function clone_table_deep(src)
  if type(src) ~= "table" then
    return src
  end
  local out = {}
  for k, v in pairs(src) do
    out[k] = clone_table_deep(v)
  end
  return out
end

function seq_item_is_aux_piece(item)
  if not item then
    return false
  end
  if get_item_ext(item, SEQ_EXT_LAYER) == "1" then
    return true
  end
  local ghost = get_item_ext(item, SEQ_EXT_GHOST)
  return ghost ~= nil and ghost ~= ""
end

function seq_item_is_parent_marker(item)
  return item and get_item_ext(item, SEQ_EXT_PARENT) == "1"
end

function seq_item_is_owned(item, region_id)
  if seq_item_is_parent_marker(item) then
    return false
  end
  if get_item_ext(item, SEQ_EXT_FLAG) ~= "1" then
    return false
  end
  if region_id and tonumber(get_item_ext(item, SEQ_EXT_REGION) or "") ~= region_id then
    return false
  end
  return true
end

function seq_item_guid(item)
  if not item then
    return nil
  end
  if r.GetSetMediaItemInfo_String then
    local ok, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
    if type(guid) == "string" and guid ~= "" then
      return guid
    end
    if type(ok) == "string" and ok ~= "" then
      return ok
    end
  end
  if r.BR_GetMediaItemGUID then
    local guid = r.BR_GetMediaItemGUID(item)
    if type(guid) == "string" and guid ~= "" then
      return guid
    end
  end
  return nil
end

function seq_item_name(item)
  if not item then
    return ""
  end
  local take = r.GetActiveTake and r.GetActiveTake(item)
  if take and r.GetSetMediaItemTakeInfo_String then
    local ok, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if type(name) == "string" and name ~= "" then
      return name
    end
    if type(ok) == "string" and ok ~= "" then
      return ok
    end
  end
  if r.GetSetMediaItemInfo_String then
    local ok, name = r.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
    if type(name) == "string" then
      return name
    end
    if type(ok) == "string" then
      return ok
    end
  end
  return ""
end

function seq_region_parent_label(region)
  if not region then
    return "Region"
  end
  local name = region.name
  if type(name) == "string" and name ~= "" then
    return name
  end
  return "Region " .. tostring(region.id)
end

function seq_refresh_arrange()
  if r.UpdateTimeline then
    r.UpdateTimeline()
  end
  if r.UpdateArrange then
    r.UpdateArrange()
  end
  if r.TrackList_AdjustWindows then
    r.TrackList_AdjustWindows(false)
  end
end

-- Transparent tiles so item color shows through (incl. the small REAPER tile gap).
SEQ_PARENT_IMAGE_FLAGS = 1 -- center/tile
SEQ_PARENT_IMAGE_STYLES = {
  { id = "drum", file = "seq-region-parent-drum.png", label = "Drum sequencer" },
  { id = "led", file = "seq-region-parent-led.png", label = "LED step row" },
  { id = "tape", file = "seq-region-parent-tape.png", label = "Measure tape" },
  { id = "wave", file = "seq-region-parent-wave.png", label = "Waveform" },
  { id = "notes", file = "seq-region-parent-notes.png", label = "Piano-roll notes" },
  { id = "dots", file = "seq-region-parent-dots.png", label = "Pulse dots" },
}

function seq_parent_image_style(id)
  id = id or (state and state.seq_parent_item_image) or "drum"
  for i = 1, #SEQ_PARENT_IMAGE_STYLES do
    if SEQ_PARENT_IMAGE_STYLES[i].id == id then
      return SEQ_PARENT_IMAGE_STYLES[i]
    end
  end
  return SEQ_PARENT_IMAGE_STYLES[1]
end

function seq_parent_image_file()
  return seq_parent_image_style().file
end

function seq_file_exists(path)
  if not path or path == "" then
    return false
  end
  if r.file_exists and r.file_exists(path) then
    return true
  end
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

function seq_parent_item_image_candidates()
  local dirs = {}
  local data_dir = r.GetResourcePath() .. "/Data/track_icons"
  dirs[#dirs + 1] = data_dir
  dirs[#dirs + 1] = SCRIPT_DIR .. "/assets"
  local info = debug.getinfo and debug.getinfo(1, "S")
  local src = info and info.source
  if type(src) == "string" then
    local path = src:match("^@(.+)$")
    local dir = path and path:match("^(.*)[/\\]")
    if dir then
      dirs[#dirs + 1] = dir .. "/assets"
    end
  end
  return dirs, data_dir
end

function seq_parent_item_image_path()
  if seq_parent_image_ready_path and seq_file_exists(seq_parent_image_ready_path)
      and seq_parent_item_image_matches(seq_parent_image_ready_path) then
    return seq_parent_image_ready_path
  end
  local dirs, data_dir = seq_parent_item_image_candidates()
  local found = nil
  for i = 1, #dirs do
    local p = dirs[i] .. "/" .. seq_parent_image_file()
    if seq_file_exists(p) then
      found = p
      break
    end
  end
  local dest = data_dir .. "/" .. seq_parent_image_file()
  if found and found ~= dest then
    if r.RecursiveCreateDirectory then
      r.RecursiveCreateDirectory(data_dir, 0)
    end
    local sf = io.open(found, "rb")
    if sf then
      local data = sf:read("*a")
      sf:close()
      local df = io.open(dest, "wb")
      if df then
        df:write(data)
        df:close()
        found = dest
      end
    end
  end
  seq_parent_image_ready_path = found or dest
  return seq_parent_image_ready_path
end

function seq_item_state_chunk(item)
  if not item or not r.GetItemStateChunk then
    return nil
  end
  local retval, chunk = r.GetItemStateChunk(item, "", false)
  if type(retval) == "string" then
    chunk = retval
  end
  if type(chunk) == "string" and chunk ~= "" then
    return chunk
  end
  return nil
end

function seq_parent_item_image_matches(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local name = seq_parent_image_file()
  if path == name then
    return true
  end
  if path:sub(-#name) == name then
    return true
  end
  return path:find(name, 1, true) ~= nil
end

function seq_parent_item_has_image(item)
  if not item then
    return false
  end
  if r.BR_GetMediaItemImageResource then
    local a, b, c = r.BR_GetMediaItemImageResource(item)
    local image, flags
    if type(a) == "string" then
      image, flags = a, b
    elseif a then
      image, flags = b, c
    end
    if seq_parent_item_image_matches(image)
        and (tonumber(flags) or 0) == SEQ_PARENT_IMAGE_FLAGS then
      return true
    end
  end
  local chunk = seq_item_state_chunk(item)
  if chunk then
    local fn = chunk:match('RESOURCEFN%s+"([^"]+)"') or chunk:match("RESOURCEFN%s+(%S+)")
    local flags = tonumber(chunk:match("IMGRESOURCEFLAGS%s+(%-?%d+)"))
    if seq_parent_item_image_matches(fn) and flags == SEQ_PARENT_IMAGE_FLAGS then
      return true
    end
  end
  return false
end

function seq_set_parent_item_image_chunk(item, path, flags)
  local chunk = seq_item_state_chunk(item)
  if not chunk or not path or path == "" then
    return false
  end
  flags = flags or SEQ_PARENT_IMAGE_FLAGS
  local line = string.format('RESOURCEFN "%s"', path)
  local flag_line = string.format("IMGRESOURCEFLAGS %d", flags)
  -- gsub replacement strings treat % specially; escape it for paths like "100%".
  local line_repl = line:gsub("%%", "%%%%")
  if chunk:find("RESOURCEFN%s+", 1) then
    chunk = chunk:gsub('RESOURCEFN%s+"[^"]*"', line_repl, 1)
    if chunk:find("RESOURCEFN%s+[^\"\r\n]+", 1) and not chunk:find(line, 1, true) then
      chunk = chunk:gsub("RESOURCEFN%s+[^\r\n]+", line_repl, 1)
    end
  elseif chunk:find("\n>%s*$") then
    chunk = chunk:gsub("\n>%s*$", "\n" .. line_repl .. "\n" .. flag_line .. "\n>\n")
  else
    chunk = chunk .. line .. "\n" .. flag_line .. "\n"
  end
  if chunk:find("IMGRESOURCEFLAGS%s+", 1) then
    chunk = chunk:gsub("IMGRESOURCEFLAGS%s+%-?%d+", flag_line, 1)
  else
    chunk = chunk:gsub("(RESOURCEFN[^\r\n]+\r?\n)", "%1" .. flag_line .. "\n", 1)
  end
  return r.SetItemStateChunk(item, chunk, false) and true or false
end

function seq_set_parent_image_style(id)
  local style = seq_parent_image_style(id)
  if not style then
    return false
  end
  if state.seq_parent_item_image == style.id and seq_parent_image_ready_path then
    return false
  end
  state.seq_parent_item_image = style.id
  seq_parent_image_ready_path = nil
  if save_config then
    save_config()
  end
  seq_ensure_all_region_parent_items()
  return true
end

function seq_attach_parent_item_image(item)
  item = seq_media_item_ptr(item)
  if not item then
    return false
  end
  local path = seq_parent_item_image_path()
  if not path or not seq_file_exists(path) then
    return false
  end
  if r.BR_SetMediaItemImageResource then
    r.BR_SetMediaItemImageResource(item, path, SEQ_PARENT_IMAGE_FLAGS)
    if seq_parent_item_has_image(item) then
      return true
    end
  end
  return seq_set_parent_item_image_chunk(item, path, SEQ_PARENT_IMAGE_FLAGS)
end

seq_parent_pcm_by_pool = seq_parent_pcm_by_pool or {}
seq_parent_image_ready_path = seq_parent_image_ready_path or nil

function seq_parent_source_valid(src)
  if not src then
    return false
  end
  if r.ValidatePtr2 and r.ValidatePtr2(0, src, "PCM_source*") then
    return true
  end
  if r.ValidatePtr and r.ValidatePtr(src, "PCM_source*") then
    return true
  end
  if r.GetMediaSourceType then
    local ok, typ = pcall(r.GetMediaSourceType, src, "")
    if ok and type(typ) == "string" and typ ~= "" then
      return true
    end
    if type(ok) == "string" and ok ~= "" then
      return true
    end
  end
  return false
end

function seq_source_type(src)
  if not src or not r.GetMediaSourceType then
    return ""
  end
  local a, b = r.GetMediaSourceType(src, "")
  if type(b) == "string" and b ~= "" then
    return b
  end
  if type(a) == "string" then
    return a
  end
  return ""
end

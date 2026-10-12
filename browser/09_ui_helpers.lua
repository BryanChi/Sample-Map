-- Sample Map Browser module: ui_helpers
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- UI helpers --------------------------------------------------------------
-- Text half of sample_passes_filters: does the (lowercased, non-empty) needle
-- occur in the sample's name or path?
function sample_matches_filter_text(sample, needle)
  -- Lowercased name/path are memoized on the sample (underscore fields are
  -- never written to the library cache) and refreshed if either changes.
  local src_name, src_path = sample.name or "", sample.path or ""
  if sample._lc_src_name ~= src_name or sample._lc_src_path ~= src_path then
    sample._lc_src_name = src_name
    sample._lc_src_path = src_path
    sample._lc_name = string.lower(src_name)
    sample._lc_path = string.lower(src_path)
  end
  return string.find(sample._lc_name, needle, 1, true) ~= nil or string.find(sample._lc_path, needle, 1, true) ~= nil
end

-- skip_tags: caller already restricted the candidate set via samples_by_tag
function sample_passes_filters(sample, needle, skip_tags)
  if not sample then return false end

  if needle == nil then
    needle = (state.filter ~= "" and string.lower(state.filter)) or ""
  end
  if needle ~= "" then
    if not sample_matches_filter_text(sample, needle) then
      return false
    end
  end

  if not skip_tags and state.active_tags and next(state.active_tags) ~= nil then
    local matched = false
    local set = sample._tag_set
    if set then
      for tag, on in pairs(state.active_tags) do
        if on and set[tag] then
          matched = true
          break
        end
      end
    elseif sample.tags then
      for _, tag in ipairs(sample.tags) do
        if state.active_tags[tag] then
          matched = true
          break
        end
      end
    end
    if not matched then
      return false
    end
  end

  -- Check folder path filter (sample matches if it is under any selected folder)
  if not folder_filter_matches_sample(sample.path) then
    return false
  end

  return true
end

-- Samples currently assigned to sequencer tracks (and layering verts).
-- Optional slot_id limits the result to one track (used for map hover highlight).
function seq_assigned_sample_info(slot_id)
  local info = {}
  local selected_slot = nil
  if state.selected_seq_track then
    selected_slot = state.seq_tracks[state.selected_seq_track]
  end
  local function mark(path, name, is_selected)
    if not path or path == "" then
      return
    end
    local entry = info[path]
    if not entry then
      entry = { names = {}, selected = false }
      info[path] = entry
    end
    entry.names[#entry.names + 1] = name or "Track"
    if is_selected then
      entry.selected = true
    end
  end
  for _, slot in ipairs(state.seq_tracks or {}) do
    if slot_id == nil or slot.id == slot_id then
      local is_selected = selected_slot ~= nil and slot.id == selected_slot.id
      mark(slot.sample_path, slot.name, is_selected)
      local layers = slot.layers
      if type(layers) == "table" then
        for _, side_key in ipairs({ "transient", "sustain" }) do
          local verts = layers[side_key] and layers[side_key].verts
          if type(verts) == "table" then
            for i = 1, #verts do
              local vert = verts[i]
              if vert and vert.path then
                mark(vert.path, (slot.name or "Track") .. " (" .. side_key .. ")", is_selected)
              end
            end
          end
        end
      end
    end
  end
  return info
end

function seq_map_highlight_sample_info()
  if state.map_ui_drag then
    return {}
  end
  local hover_id = state.map_hover_track_id
  if not hover_id then
    return {}
  end
  return seq_assigned_sample_info(hover_id)
end

function seq_assigned_view_fingerprint()
  local bits = {}
  for _, slot in ipairs(state.seq_tracks or {}) do
    bits[#bits + 1] = tostring(slot.sample_path or "")
    local layers = slot.layers
    if type(layers) == "table" then
      for _, side_key in ipairs({ "transient", "sustain" }) do
        local verts = layers[side_key] and layers[side_key].verts
        if type(verts) == "table" then
          for i = 1, #verts do
            local vert = verts[i]
            if vert and vert.path then
              bits[#bits + 1] = vert.path
            end
          end
        end
      end
    end
  end
  bits[#bits + 1] = tostring(state.selected_seq_track or 0)
  return table.concat(bits, "\n")
end

-- Dot colour for a base colour value (state.dot_color or a tag colour) and its
-- brightened mono variant. Both are pure functions of the value; the map
-- recolours every sample after each tag change, so they're memoized.
local dot_color_memo, dot_color_mono_memo, dot_color_memo_n = {}, {}, 0

local function dot_color_for(base, mono)
  local memo = mono and dot_color_mono_memo or dot_color_memo
  local color = memo[base]
  if color then
    return color
  end
  local tr, tg, tb = extract_rgb(base)
  color = build_color_rrgbbaa(tr, tg, tb, 255)
  if mono then
    local base_r, base_g, base_b = extract_rgb_rrgbbaa(color)
    color = build_color_rrgbbaa(
      math.min(255, math.floor(base_r * 1.5)),
      math.min(255, math.floor(base_g * 1.5)),
      math.min(255, math.floor(base_b * 1.5)),
      255
    )
  end
  if base == base then
    if dot_color_memo_n >= 1024 then
      dot_color_memo, dot_color_mono_memo, dot_color_memo_n = {}, {}, 0
      memo = mono and dot_color_mono_memo or dot_color_memo
    end
    memo[base] = color
    dot_color_memo_n = dot_color_memo_n + 1
  end
  return color
end

function get_sample_dot_color(sample)
  if not sample then
    return build_color_rrgbbaa(96, 96, 96, 255)
  end
  if sample._render_color then
    return sample._render_color
  end

  local base = state.dot_color or 0x44AA55
  if sample.tags and type(sample.tags) == "table" and #sample.tags > 0 then
    local best_tag = nil
    local best_weight = 0
    for _, tag_name in ipairs(sample.tags) do
      local weight = TAG_KEYWORD_WEIGHT[tag_name]
      if weight and weight > best_weight then
        best_weight = weight
        best_tag = tag_name
      end
    end
    if best_tag and state.tag_colors[best_tag] then
      base = state.tag_colors[best_tag]
    end
  end

  local color = dot_color_for(base, sample.channels == 1)
  sample._render_color = color
  return color
end

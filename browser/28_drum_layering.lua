-- Sample Map Browser module: drum_layering
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- ===== Drum layering ====================================================
-- Each sequencer track can blend three samples for the transient and three
-- for the sustain. Blend weights are barycentric coordinates in a triangle.

function seq_layering_button(id, dl, x, y, size, active)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local bg = active and UI_THEME.accent_fill or UI_THEME.surface
  local edge = hovered and 0xFFFFFFFF or (active and UI_THEME.accent or UI_THEME.border)
  local col = active and 0xC8FF9AFF or 0xD0D8E8FF
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + size, y + size, bg, 3.0)
  r.ImGui_DrawList_AddRect(dl, x, y, x + size, y + size, edge, 3.0, 0, 1.0)
  local pad = size * 0.22
  local ax = x + size * 0.5
  local ay = y + pad
  local bx = x + pad
  local by = y + size - pad
  local cx_pt = x + size - pad
  local cy_pt = by
  r.ImGui_DrawList_AddTriangleFilled(dl, ax, ay, bx, by, cx_pt, cy_pt, col)
  r.ImGui_DrawList_AddLine(dl, ax, ay, bx, by, edge, 1.0)
  r.ImGui_DrawList_AddLine(dl, bx, by, cx_pt, cy_pt, edge, 1.0)
  r.ImGui_DrawList_AddLine(dl, cx_pt, cy_pt, ax, ay, edge, 1.0)
  return clicked
end

function seq_layer_vert_vol(vert)
  local v = tonumber(vert and vert.vol)
  if v == nil then return 1.0 end
  if v < 0.0 then return 0.0 end
  local max_v = SEQ_LAYER_VOL_MAX or 4.0
  if v > max_v then return max_v end
  return v
end

function seq_layer_default_side()
  return {
    verts = {
      { path = nil, name = nil, locked = true, vol = 1.0 },
      { path = nil, name = nil, locked = false, vol = 1.0 },
      { path = nil, name = nil, locked = false, vol = 1.0 },
    },
    blend = { 1.0, 0.0, 0.0 },
  }
end

SEQ_LAYER_GAIN_MIN_DB = -24.0
SEQ_LAYER_GAIN_MAX_DB = 12.0

-- Side gain (linear) over everything in the transient or sustain.
function seq_layer_clamp_gain(g)
  g = tonumber(g)
  if g == nil or g ~= g then return 1.0 end
  local lo = 10 ^ (SEQ_LAYER_GAIN_MIN_DB / 20.0)
  local hi = 10 ^ (SEQ_LAYER_GAIN_MAX_DB / 20.0)
  if g < lo then return lo end
  if g > hi then return hi end
  return g
end

-- Corner play length (seconds from the hit, nil = to its natural end) and
-- fade-out length (nil = none).
function seq_layer_clamp_len(len)
  len = tonumber(len)
  if len == nil or len ~= len or len <= 0 then return nil end
  return math.max(0.005, math.min(30.0, len))
end

function seq_layer_clamp_fade(f)
  f = tonumber(f)
  if f == nil or f ~= f or f <= 0.0005 then return nil end
  return math.min(30.0, f)
end

-- Normalizes in place (no new tables once a side is well formed): this runs
-- many times per frame while the layering window is open.
function seq_layer_normalize_side(side)
  if type(side) ~= "table" then
    return seq_layer_default_side()
  end
  if type(side.verts) ~= "table" then
    side.verts = seq_layer_default_side().verts
  end
  for i = 1, 3 do
    local v = side.verts[i]
    if type(v) ~= "table" then
      side.verts[i] = { path = nil, name = nil, locked = (i == 1), vol = 1.0 }
    else
      v.locked = v.locked == true
      v.vol = seq_layer_vert_vol(v)
      if v.path == "" then v.path = nil end
      v.len = seq_layer_clamp_len(v.len)
      v.fade = seq_layer_clamp_fade(v.fade)
    end
  end
  side.gain = seq_layer_clamp_gain(side.gain)
  local b = side.blend
  if type(b) ~= "table" then
    side.blend = { 1.0, 0.0, 0.0 }
  else
    b[1], b[2], b[3] = seq_layer_clamp_bary(tonumber(b[1]) or 0, tonumber(b[2]) or 0, tonumber(b[3]) or 0)
  end
  -- A side-wide source (older layouts) moves onto corners that have none.
  if type(side.rand) == "table" then
    for i = 2, 3 do
      local v = side.verts[i]
      if v.rand == nil then
        local tags = {}
        for k, t in ipairs(side.rand.tags or {}) do tags[k] = t end
        v.rand = { role = side.rand.role, tags = tags }
      end
    end
  end
  side.rand = nil
  for i = 1, 3 do
    seq_layer_normalize_rand(side.verts[i])
  end
  return side
end

-- Where a corner looks for samples: vert.rand = { role = drum type or nil
-- (the track's own), tags = { tag, ... } (a sample must carry all of them) }.
-- The dice, the map picker and its tag chips all read and write this.
function seq_layer_normalize_rand(vert)
  local rd = vert.rand
  if type(rd) ~= "table" then
    vert.rand = nil
    return
  end
  if type(rd.role) ~= "string" or rd.role == "" then
    rd.role = nil
  end
  if type(rd.tags) ~= "table" then
    rd.tags = {}
  end
  if not rd.role and #rd.tags == 0 then
    vert.rand = nil
  end
end

function seq_normalize_slot_layers(slot)
  if not slot then return end
  if type(slot.layers) ~= "table" then
    slot.layers = {}
  end
  slot.layers.transient = seq_layer_normalize_side(slot.layers.transient)
  slot.layers.sustain = seq_layer_normalize_side(slot.layers.sustain)
  slot.layers.linked = slot.layers.linked == true
  if slot.layers.output ~= "original" and slot.layers.output ~= "layered" then
    slot.layers.output = nil
  end
  local bias = tonumber(slot.layers.bias)
  if bias == nil then
    slot.layers.bias = 0.0
  else
    if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
    slot.layers.bias = bias
  end
  slot.layers.xfade = seq_layering_clamp_xfade(slot.layers.xfade)
  -- Whole-hit tail: end point and fade-out (seconds from the hit).
  slot.layers.tail_end = seq_layer_clamp_len(slot.layers.tail_end)
  slot.layers.tail_fade = seq_layer_clamp_fade(slot.layers.tail_fade)
  if not slot.layers.tail_end and not slot.layers.tail_fade then
    slot.layers.tail_fade = nil
  end
  -- The sustain as it was when the sides were linked, restored on unlink.
  if type(slot.layers.unlinked_sustain) == "table" then
    slot.layers.unlinked_sustain = seq_layer_normalize_side(slot.layers.unlinked_sustain)
  else
    slot.layers.unlinked_sustain = nil
  end
  if slot.layers.top_locked_inited ~= true then
    slot.layers.transient.verts[1].locked = true
    slot.layers.sustain.verts[1].locked = true
    slot.layers.top_locked_inited = true
  end
end

function seq_layering_copy_side(dst, src)
  if not dst or not src then return end
  if type(dst.verts) ~= "table" then
    dst.verts = seq_layer_default_side().verts
  end
  local sb = src.blend or { 1.0, 0.0, 0.0 }
  dst.blend = { sb[1] or 1.0, sb[2] or 0.0, sb[3] or 0.0 }
  dst.rand = nil
  dst.gain = seq_layer_clamp_gain(src.gain)
  for i = 1, 3 do
    local sv = src.verts and src.verts[i]
    if type(dst.verts[i]) ~= "table" then
      dst.verts[i] = { path = nil, name = nil, locked = (i == 1), vol = 1.0 }
    end
    if sv then
      dst.verts[i].path = sv.path
      dst.verts[i].name = sv.name
      dst.verts[i].locked = sv.locked == true
      dst.verts[i].vol = seq_layer_vert_vol(sv)
      dst.verts[i].len = seq_layer_clamp_len(sv.len)
      dst.verts[i].fade = seq_layer_clamp_fade(sv.fade)
      if type(sv.rand) == "table" then
        local tags = {}
        for k, t in ipairs(sv.rand.tags or {}) do tags[k] = t end
        dst.verts[i].rand = { role = sv.rand.role, tags = tags }
      else
        dst.verts[i].rand = nil
      end
    end
  end
end

function seq_layering_copy_to_slot(dst, src)
  if not dst or not src then return end
  seq_normalize_slot_layers(src)
  seq_normalize_slot_layers(dst)
  dst.layers.linked = src.layers.linked == true
  dst.layers.output = src.layers.output
  dst.layers.bias = src.layers.bias or 0.0
  dst.layers.xfade = src.layers.xfade
  dst.layers.tail_end = src.layers.tail_end
  dst.layers.tail_fade = src.layers.tail_fade
  dst.layers.unlinked_sustain = nil
  dst.layers.top_locked_inited = true
  seq_layering_copy_side(dst.layers.transient, src.layers.transient)
  seq_layering_copy_side(dst.layers.sustain, src.layers.sustain)
end

function seq_layering_sync_linked(slot, from_key)
  if not slot then return end
  seq_normalize_slot_layers(slot)
  if not slot.layers.linked then return end
  from_key = from_key or "transient"
  local src = slot.layers[from_key]
  local dst = slot.layers[from_key == "transient" and "sustain" or "transient"]
  seq_layering_copy_side(dst, src)
end

function seq_layering_set_linked(slot, linked)
  if not slot then return end
  seq_normalize_slot_layers(slot)
  linked = linked == true
  if slot.layers.linked == linked then return end
  slot.layers.linked = linked
  if linked then
    -- Keep the sustain's own samples, blend and volumes for when it unlinks.
    local keep = seq_layer_default_side()
    seq_layering_copy_side(keep, slot.layers.sustain)
    slot.layers.unlinked_sustain = keep
    seq_layering_sync_linked(slot, "transient")
  elseif slot.layers.unlinked_sustain then
    seq_layering_copy_side(slot.layers.sustain, slot.layers.unlinked_sustain)
    slot.layers.unlinked_sustain = nil
  end
end

function seq_layering_follow_track_sample(slot, old_path, sample)
  if not slot or not sample or not sample.path then
    return
  end
  seq_normalize_slot_layers(slot)
  local old_norm = old_path and normalize_path(old_path) or nil
  local new_path = sample.path
  local new_name = sample.name or basename(new_path)
  for _, side_key in ipairs({ "transient", "sustain" }) do
    local side = slot.layers[side_key]
    local v = side and side.verts and side.verts[1]
    if type(v) == "table" then
      local vp = v.path and normalize_path(v.path) or nil
      -- Locked top is the track original and must follow a swap.
      -- Also replace empty verts or verts that still point at the old sample.
      if v.locked or not vp or (old_norm and vp == old_norm) then
        v.path = new_path
        v.name = new_name
        v.vol = 1.0
        if v.locked or not vp then
          v.locked = true
        end
      end
    end
  end
  if slot.layers.linked then
    seq_layering_sync_linked(slot, "transient")
  end
end

function seq_layering_seed_from_track(slot)
  if not slot then return end
  seq_normalize_slot_layers(slot)
  if not slot.sample_path then return end
  local sides = { slot.layers.transient, slot.layers.sustain }
  for i = 1, 2 do
    local v = sides[i] and sides[i].verts and sides[i].verts[1]
    if type(v) == "table" and not v.path then
      v.path = slot.sample_path
      v.name = slot.sample_name or basename(slot.sample_path)
      v.locked = true
    end
  end
  if slot.layers.linked then
    seq_layering_sync_linked(slot, "transient")
  end
end

function seq_layering_set_vert(slot, side_key, idx, sample)
  if not slot or not sample or not sample.path then return end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  if not side or idx < 1 or idx > 3 then return end
  local v = side.verts[idx]
  if v.locked then
    if idx == 1 then
      assign_sample_to_seq_track(slot, sample, true)
    end
    return
  end
  v.path = sample.path
  v.name = sample.name or basename(sample.path)
  v.vol = 1.0
  seq_layering_ensure_audible(side, idx)
  seq_layering_sync_linked(slot, side_key)
end

function seq_layer_clamp_bary(a, b, c)
  a = math.max(0.0, a or 0.0)
  b = math.max(0.0, b or 0.0)
  c = math.max(0.0, c or 0.0)
  local s = a + b + c
  if s < 1e-9 then
    return 1.0, 0.0, 0.0
  end
  return a / s, b / s, c / s
end

function seq_layer_barycentric_raw(px, py, ax, ay, bx, by, cx, cy)
  local v0x, v0y = cx - ax, cy - ay
  local v1x, v1y = bx - ax, by - ay
  local v2x, v2y = px - ax, py - ay
  local dot00 = v0x * v0x + v0y * v0y
  local dot01 = v0x * v1x + v0y * v1y
  local dot02 = v0x * v2x + v0y * v2y
  local dot11 = v1x * v1x + v1y * v1y
  local dot12 = v1x * v2x + v1y * v2y
  local denom = dot00 * dot11 - dot01 * dot01
  if math.abs(denom) < 1e-12 then
    return 1.0, 0.0, 0.0
  end
  local u = (dot11 * dot02 - dot01 * dot12) / denom
  local v = (dot00 * dot12 - dot01 * dot02) / denom
  local w = 1.0 - u - v
  return w, v, u
end

function seq_layer_barycentric(px, py, ax, ay, bx, by, cx, cy)
  local w, v, u = seq_layer_barycentric_raw(px, py, ax, ay, bx, by, cx, cy)
  return seq_layer_clamp_bary(w, v, u)
end

function seq_layer_point_from_bary(blend, ax, ay, bx, by, cx, cy)
  local a = blend[1] or 1.0
  local b = blend[2] or 0.0
  local c = blend[3] or 0.0
  return ax * a + bx * b + cx * c, ay * a + by * b + cy * c
end

function seq_layering_collect_pool(slot, side, vert_idx)
  local pool = {}
  local used = {}
  seq_normalize_slot_layers(slot)
  local verts = slot.layers[side].verts
  for i = 1, 3 do
    if verts[i] and verts[i].path then
      used[verts[i].path] = true
    end
  end
  if slot.sample_path then
    used[slot.sample_path] = true
  end
  local origin = (verts[vert_idx] and verts[vert_idx].path and find_sample_by_path(verts[vert_idx].path))
      or find_sample_by_path(slot.sample_path)
  local rand = verts[vert_idx] and verts[vert_idx].rand
  local role = (rand and rand.role) or seq_vary_role_for_origin(slot, origin)
  local tags = rand and rand.tags or nil
  if tags and #tags == 0 then tags = nil end

  local function consider(s, drums_only)
    if not s or not s.path or used[s.path] then
      return
    end
    if sample_scan_folder_unavailable(s) then
      return
    end
    if drums_only and not sample_is_drum_oneshot(s) then
      return
    end
    if role and not seq_sample_matches_vary_role(s, role) then
      return
    end
    if tags then
      for t = 1, #tags do
        if not sample_has_tag(s, tags[t]) then
          return
        end
      end
    end
    pool[#pool + 1] = s
    used[s.path] = true
  end

  local ranked = {}
  if origin and collect_map_samples_by_distance then
    ranked = collect_map_samples_by_distance(origin, role)
  end
  for i = 1, #ranked do
    consider(ranked[i].sample, true)
    if #pool >= 48 then return pool end
  end
  if #pool < 8 then
    for i = 1, #ranked do
      consider(ranked[i].sample, false)
      if #pool >= 48 then return pool end
    end
  end
  if #pool < 4 then
    for _, s in ipairs(state.samples) do
      consider(s, true)
      if #pool >= 48 then return pool end
    end
  end
  if #pool < 2 then
    for _, s in ipairs(state.samples) do
      consider(s, false)
      if #pool >= 48 then return pool end
    end
  end
  return pool
end

-- Drum types that have samples in the library, and the tags found on each
-- type's samples: { roles = { role = n }, tags = { role = { { tag, count } } } }.
-- One pass over the library, cached until the tag index changes.
function seq_layering_role_index()
  local samples = state.samples or {}
  local key = tostring(state.tag_index_epoch or 0) .. ":" .. tostring(#samples)
  local c = seq_layer_role_index_cache
  if c and c.key == key then
    return c
  end
  local is_role = {}
  for _, role in ipairs(SEQ_ROLE_ORDER or {}) do is_role[role] = true end
  local roles, tag_counts = {}, {}
  local hit = {}
  for i = 1, #samples do
    local s = samples[i]
    if s and s.path and not sample_scan_folder_unavailable(s) then
      for k in pairs(hit) do hit[k] = nil end
      local icon_role = seq_icon_role_for_sample(s)
      if is_role[icon_role] then hit[icon_role] = true end
      local stags = type(s.tags) == "table" and s.tags or {}
      for t = 1, #stags do
        local low = tostring(stags[t]):lower()
        if is_role[low] then hit[low] = true end
      end
      for role in pairs(hit) do
        roles[role] = (roles[role] or 0) + 1
        local tc = tag_counts[role]
        if not tc then
          tc = {}
          tag_counts[role] = tc
        end
        for t = 1, #stags do
          local tag = tostring(stags[t])
          tc[tag] = (tc[tag] or 0) + 1
        end
      end
    end
  end
  local tags = {}
  for role, tc in pairs(tag_counts) do
    local skip = { [role] = true }
    for _, alias in ipairs((SEQ_ROLE_TAG_CANDIDATES or {})[role] or {}) do
      skip[alias] = true
    end
    local list = {}
    for tag, n in pairs(tc) do
      -- A tag every sample of the type has doesn't narrow anything.
      if not skip[tag:lower()] and n < (roles[role] or 0) then
        list[#list + 1] = { tag = tag, count = n }
      end
    end
    table.sort(list, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.tag:lower() < b.tag:lower()
    end)
    tags[role] = list
  end
  c = { key = key, roles = roles, tags = tags }
  seq_layer_role_index_cache = c
  return c
end

-- The track's own drum type (what a corner draws from by default).
function seq_layering_track_role(slot)
  return seq_vary_role_for_origin(slot, find_sample_by_path(slot.sample_path))
end

local function corner(slot, side_key, idx)
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  return side and side.verts[idx], side
end

-- Drum type a corner draws from: its own choice, else the track's. The
-- second value is true when the corner chose it.
function seq_layering_rand_role(slot, side_key, idx)
  local v = corner(slot, side_key, idx)
  if v and v.rand and v.rand.role then
    return v.rand.role, true
  end
  return seq_layering_track_role(slot), false
end

-- role: a drum type, or nil for the track's own. Changing the type drops tags
-- that belonged to the old one.
function seq_layering_set_rand_role(slot, side_key, idx, role)
  local v = corner(slot, side_key, idx)
  if not v then return false end
  if role == "" or role == seq_layering_track_role(slot) then role = nil end
  local cur = v.rand and v.rand.role or nil
  if cur == role then return false end
  v.rand = { role = role, tags = {} }
  seq_layer_normalize_rand(v)
  seq_layering_sync_linked(slot, side_key)
  return true
end

function seq_layering_rand_has_tag(slot, side_key, idx, tag)
  local v = corner(slot, side_key, idx)
  if not v or not v.rand then return false end
  for _, t in ipairs(v.rand.tags or {}) do
    if t == tag then return true end
  end
  return false
end

function seq_layering_toggle_rand_tag(slot, side_key, idx, tag)
  local v = corner(slot, side_key, idx)
  if not v then return false end
  v.rand = v.rand or { tags = {} }
  local tags = v.rand.tags
  local found = false
  for i = #tags, 1, -1 do
    if tags[i] == tag then
      table.remove(tags, i)
      found = true
    end
  end
  if not found then
    tags[#tags + 1] = tag
  end
  seq_layer_normalize_rand(v)
  seq_layering_sync_linked(slot, side_key)
  return true
end

function seq_layering_clear_rand(slot, side_key, idx)
  local v = corner(slot, side_key, idx)
  if not v or not v.rand then return false end
  v.rand = nil
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Label of a corner's source: "Clap · punchy, dry", or the track's type.
-- The second value is true when the corner has its own source.
function seq_layering_rand_label(slot, side_key, idx)
  local v = corner(slot, side_key, idx)
  local labels = SEQ_ROLE_LABELS or {}
  local role, own = seq_layering_rand_role(slot, side_key, idx)
  local bits = { role and (labels[role] or role) or "Any" }
  local tags = v and v.rand and v.rand.tags or {}
  if #tags > 0 then
    bits[#bits + 1] = table.concat(tags, ", ")
  end
  return table.concat(bits, " · "), own or #tags > 0
end

-- Samples a corner can draw from (drum type and tags), placed on the map.
-- Cached per filter until the library or its tags change.
function seq_layering_corner_samples(slot, side_key, idx)
  local role = seq_layering_rand_role(slot, side_key, idx)
  local v = corner(slot, side_key, idx)
  local tags = v and v.rand and v.rand.tags or {}
  local samples = state.samples or {}
  local key = tostring(role) .. "|" .. table.concat(tags, "\0") .. "|"
      .. tostring(state.tag_index_epoch or 0) .. ":" .. tostring(#samples)
  local cache = seq_layer_corner_pool_cache
  if cache and cache.key == key then
    return cache.list
  end
  local list = {}
  for i = 1, #samples do
    local s = samples[i]
    if s and s.path and s.x and s.y and not sample_scan_folder_unavailable(s)
        and (not role or seq_sample_matches_vary_role(s, role)) then
      local ok = true
      for t = 1, #tags do
        if not sample_has_tag(s, tags[t]) then
          ok = false
          break
        end
      end
      if ok then
        if not s._render_color then
          s._render_color = get_sample_dot_color(s)
        end
        list[#list + 1] = s
      end
    end
  end
  seq_layer_corner_pool_cache = { key = key, list = list }
  return list
end

function seq_layering_ensure_audible(side, idx)
  if not side or not side.blend then return end
  local b = side.blend
  if (b[idx] or 0) >= 0.08 then
    return
  end
  local pull = 0.34
  b[1] = (b[1] or 0) * (1.0 - pull)
  b[2] = (b[2] or 0) * (1.0 - pull)
  b[3] = (b[3] or 0) * (1.0 - pull)
  b[idx] = (b[idx] or 0) + pull
  local a, bb, c = seq_layer_clamp_bary(b[1], b[2], b[3])
  side.blend = { a, bb, c }
end

function seq_layering_repair_note_volumes(slot)
  if not slot or not slot.id then
    return
  end
  for _, pattern in pairs(state.seq_patterns or {}) do
    if type(pattern) == "table" then
      local notes = get_track_note_table(pattern, slot.id, false)
      if notes then
        for _, note in pairs(notes) do
          -- Older layering wrote item*take*blend into note.volume (~0.08 and down).
          if type(note) == "table" and type(note.volume) == "number"
             and note.volume > 0.0 and note.volume < 0.1 then
            note.volume = 1.0
          end
        end
      end
    end
  end
end

function seq_layering_sync_arrange(slot, opts)
  if not slot or not slot.id then
    return
  end
  opts = opts or {}
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  for _, region in ipairs(state.seq_regions or {}) do
    sync_seq_region_track(region, slot, {
      skip_arrange = true,
      force_rebuild = opts.force_rebuild,
    })
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if r.UpdateArrange then
    r.UpdateArrange()
  end
end

function seq_layering_get_bias(slot)
  if not slot then return 0.0 end
  seq_normalize_slot_layers(slot)
  return slot.layers.bias or 0.0
end

function seq_layering_apply_bias(base_trans, onset, dur, bias)
  onset = math.max(0.0, onset or 0.0)
  dur = math.max(onset + 0.02, dur or 0.2)
  local base_len = math.max(0.004, (base_trans or (onset + 0.02)) - onset)
  local min_len = 0.004
  local max_len = math.min(math.max(0.02, dur - onset - 0.012), math.max(base_len * 4.0, 0.12))
  if max_len < base_len then
    max_len = math.min(math.max(0.02, dur - onset - 0.012), base_len * 2.0)
  end
  bias = tonumber(bias) or 0.0
  if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
  local len
  if bias <= 0.0 then
    len = min_len + (base_len - min_len) * (bias + 1.0)
  else
    len = base_len + (max_len - base_len) * bias
  end
  return onset + math.max(min_len, len)
end

-- Onset, unbiased transient end and length (seconds) of a sample, as the
-- transient / sustain split uses them.
function seq_layering_trans_base(sample)
  local dur = seq_sample_source_length_sec(sample and sample.path, sample)
      or (sample and tonumber(sample.duration)) or 0.2
  if dur <= 0.001 then dur = 0.2 end
  local onset = (sample and type(sample.onset) == "number" and sample.onset > 0) and sample.onset or 0.0
  local trans = (sample and type(sample.transient_end) == "number" and sample.transient_end > 0)
      and sample.transient_end or math.min(0.024, dur * 0.18)
  trans = math.max(onset + 0.003, math.min(trans, dur * 0.9))
  return onset, trans, dur
end

-- Inverse of seq_layering_apply_bias: the bias that puts the split at t.
function seq_layering_bias_for_trans(base_trans, onset, dur, t)
  onset = math.max(0.0, onset or 0.0)
  dur = math.max(onset + 0.02, dur or 0.2)
  local base_len = math.max(0.004, (base_trans or (onset + 0.02)) - onset)
  local min_len = 0.004
  local max_len = math.min(math.max(0.02, dur - onset - 0.012), math.max(base_len * 4.0, 0.12))
  if max_len < base_len then
    max_len = math.min(math.max(0.02, dur - onset - 0.012), base_len * 2.0)
  end
  local len = (tonumber(t) or (onset + base_len)) - onset
  local bias
  if len <= base_len then
    bias = (base_len > min_len) and ((len - min_len) / (base_len - min_len) - 1.0) or 0.0
  else
    bias = (max_len > base_len) and ((len - base_len) / (max_len - base_len)) or 0.0
  end
  if bias < -1.0 then bias = -1.0 elseif bias > 1.0 then bias = 1.0 end
  return bias
end

function seq_layering_piece_times(sample, side_key, slot)
  local onset, trans, dur = seq_layering_trans_base(sample)
  if slot then
    trans = seq_layering_apply_bias(trans, onset, dur, seq_layering_get_bias(slot))
    trans = math.max(onset + 0.003, math.min(trans, dur * 0.9))
  end
  if side_key == "transient" then
    return onset, math.max(0.004, trans - onset)
  end
  return trans, math.max(0.012, dur - trans)
end

SEQ_LAYER_XFADE_SEC = 0.008
SEQ_LAYER_XFADE_MIN = 0.001
SEQ_LAYER_XFADE_MAX = 0.25
SEQ_LAYER_VOL_MAX = 4.0

function seq_layering_clamp_xfade(sec)
  sec = tonumber(sec)
  if sec == nil or sec ~= sec then
    return SEQ_LAYER_XFADE_SEC
  end
  if sec < SEQ_LAYER_XFADE_MIN then return SEQ_LAYER_XFADE_MIN end
  if sec > SEQ_LAYER_XFADE_MAX then return SEQ_LAYER_XFADE_MAX end
  return sec
end

-- Crossfade length (seconds) between the transient and the sustain.
function seq_layering_get_xfade(slot)
  if not slot then return SEQ_LAYER_XFADE_SEC end
  seq_normalize_slot_layers(slot)
  return slot.layers.xfade
end

function seq_layering_set_xfade(slot, sec)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  sec = seq_layering_clamp_xfade(sec)
  if math.abs((slot.layers.xfade or 0) - sec) < 1e-7 then
    return false
  end
  slot.layers.xfade = sec
  return true
end

-- The crossfade window around the split, in mix time: it opens `pre` before
-- the split and closes `post` after it. `pre` never eats more than half the
-- transient, so a long fade still keeps the attack whole.
function seq_layering_xfade_window(slot, split)
  local xf = seq_layering_get_xfade(slot)
  split = split or seq_layering_split_sec(slot)
  local post = xf * 0.5
  local pre = math.min(xf * 0.5, split * 0.5)
  return pre, post
end

function seq_layering_geometry_active(slot)
  if not slot then
    return false
  end
  seq_normalize_slot_layers(slot)
  if slot.layers.tail_end or slot.layers.tail_fade then
    return true
  end
  local sides = { slot.layers.transient, slot.layers.sustain }
  for s = 1, 2 do
    local side = sides[s]
    if math.abs((side.blend[1] or 1.0) - 1.0) > 0.02 then
      return true
    end
    if math.abs((side.gain or 1.0) - 1.0) > 0.001 then
      return true
    end
    for i = 1, 3 do
      local v = side.verts[i]
      if v.path and (v.len or v.fade) and (side.blend[i] or 0) >= 0.02 then
        return true
      end
    end
    for i = 2, 3 do
      if (side.blend[i] or 0.0) >= 0.02 and side.verts[i] and side.verts[i].path then
        return true
      end
    end
    local v1 = side.verts[1]
    if v1 and v1.path and slot.sample_path and v1.path ~= slot.sample_path then
      return true
    end
  end
  return false
end

function seq_layering_output(slot)
  if not slot then
    return "original"
  end
  seq_normalize_slot_layers(slot)
  local out = slot.layers.output
  if out == "original" or out == "layered" then
    return out
  end
  return seq_layering_geometry_active(slot) and "layered" or "original"
end

function seq_layering_set_output(slot, kind)
  if not slot or (kind ~= "original" and kind ~= "layered") then
    return false
  end
  seq_normalize_slot_layers(slot)
  if slot.layers.output == kind then
    return false
  end
  slot.layers.output = kind
  state.seq_layering_ab = kind
  seq_layering_sync_arrange(slot, { force_rebuild = true })
  save_config()
  return true
end

function seq_layering_is_active(slot)
  return seq_layering_output(slot) == "layered" and seq_layering_geometry_active(slot)
end

function seq_layering_drag_sample(slot)
  if not slot or not slot.sample_path then
    return nil
  end
  local src = find_sample_by_path(slot.sample_path)
  local name = slot.sample_name or (src and src.name) or basename(slot.sample_path)
  return {
    path = slot.sample_path,
    name = name .. " (layered)",
    duration = src and src.duration,
    is_layering_mix = true,
    layering_slot_id = slot.id,
  }
end

function apply_dragged_sample_to_seq_track(slot, sample, persist)
  if not slot or not sample then
    return false
  end
  if sample.is_layering_mix then
    local src = find_seq_track_by_id(sample.layering_slot_id)
    if src and src.id ~= slot.id then
      local base = find_sample_by_path(src.sample_path)
        or { path = src.sample_path, name = src.sample_name }
      assign_sample_to_seq_track(slot, base, persist)
      seq_layering_copy_to_slot(slot, src)
    elseif (not src) and sample.path then
      assign_sample_to_seq_track(slot, find_sample_by_path(sample.path) or sample, persist)
    end
    seq_normalize_slot_layers(slot)
    slot.layers.output = "layered"
    seq_layering_sync_arrange(slot)
    if persist ~= false then
      save_config()
    end
    return true
  end
  return seq_assign_sample_for_context(slot, sample, persist)
end

function seq_layering_insert_mix_at_position(sample, time_pos, target_track)
  if not sample or not time_pos then
    return false
  end
  local slot = sample.layering_slot_id and find_seq_track_by_id(sample.layering_slot_id)
  local pieces = slot and seq_layering_build_pieces(slot) or {}
  if #pieces == 0 then
    local fallback = (slot and slot.sample_path and find_sample_by_path(slot.sample_path))
      or find_sample_by_path(sample.path)
      or sample
    local clean = {
      path = fallback.path,
      name = fallback.name,
      duration = fallback.duration,
    }
    return insert_sample_at_position(clean, time_pos, target_track)
  end

  local track = target_track
  if not track then
    track = r.GetSelectedTrack(0, 0)
    if not track then
      local num_tracks = r.CountTracks(0)
      if num_tracks > 0 then
        track = r.GetTrack(0, 0)
      end
    end
  end
  if not track then
    return false
  end

  r.PreventUIRefresh(1)
  local any = false
  for i = 1, #pieces do
    local piece = pieces[i]
    if piece.path and r.file_exists(piece.path) then
      local item = r.AddMediaItemToTrack(track)
      local item_ok = false
      if item then
        local src_sample = piece.sample or find_sample_by_path(piece.path)
        local pdur = (seq_sample_source_length_sec and seq_sample_source_length_sec(piece.path, src_sample))
          or (src_sample and tonumber(src_sample.duration))
          or (sample.duration or 1.0)
        local startoffs = piece.startoffs or 0.0
        local len = piece.length_sec
        if not len or len <= 0 then
          len = math.max(0.001, pdur - startoffs)
        end
        r.SetMediaItemPosition(item, time_pos + (piece.time_offset_sec or 0.0), false)
        r.SetMediaItemLength(item, len, false)
        local take = r.AddTakeToMediaItem(item)
        if take then
          local src = r.PCM_Source_CreateFromFile(piece.path)
          if src then
            r.SetMediaItemTake_Source(take, src)
            set_item_name(item, take, piece.path)
            if startoffs > 0 then
              r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startoffs)
            end
            local gain = (piece.weight or 1.0) * get_sample_gain(src_sample)
            if gain ~= 1.0 then
              r.SetMediaItemTakeInfo_Value(take, "D_VOL", gain)
            end
            seq_item_apply_layer_fades(item, piece.fade_in, piece.fade_out)
            rebuild_peaks_for_item(item)
            any = true
            item_ok = true
          end
        end
        if not item_ok and r.DeleteTrackMediaItem then
          -- Source failed to load: don't leave an empty item behind.
          r.DeleteTrackMediaItem(track, item)
        end
      end
    end
  end
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  return any
end

-- The sample whose transient sets the split: the track sample, else the first
-- transient corner that resolves.
function seq_layering_split_sample(slot)
  -- A just-rendered glue isn't indexed yet: use its file as is.
  local sample = slot and (find_sample_by_path(slot.sample_path)
    or (slot.sample_path and { path = slot.sample_path, name = slot.sample_name }))
  if not sample and slot then
    seq_normalize_slot_layers(slot)
    for i = 1, 3 do
      local v = slot.layers.transient.verts[i]
      if v and v.path then
        sample = find_sample_by_path(v.path)
        if sample then
          break
        end
      end
    end
  end
  return sample
end

function seq_layering_split_sec(slot)
  local _, tlen = seq_layering_piece_times(seq_layering_split_sample(slot), "transient", slot)
  return math.max(0.004, tlen or 0.02)
end

-- Split position in the split sample's own time (seconds from its start).
function seq_layering_split_time(slot)
  local sample = seq_layering_split_sample(slot)
  local onset, tlen = seq_layering_piece_times(sample, "transient", slot)
  return onset + tlen, sample
end

-- Moves the split to time t (seconds into the split sample) by setting the bias.
function seq_layering_set_split_time(slot, t)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local onset, trans, dur = seq_layering_trans_base(seq_layering_split_sample(slot))
  local bias = seq_layering_bias_for_trans(trans, onset, dur, t)
  if math.abs((slot.layers.bias or 0.0) - bias) < 1e-6 then
    return false
  end
  slot.layers.bias = bias
  return true
end

function seq_layering_remap_piece_lanes(pieces)
  local used = {}
  for p = 1, #pieces do
    used[pieces[p].lane] = true
  end
  local map = {}
  local n = 0
  for i = 0, 2 do
    if used[i] then
      map[i] = n
      n = n + 1
    end
  end
  for p = 1, #pieces do
    pieces[p].lane = map[pieces[p].lane] or 0
  end
  return pieces
end

-- Cuts piece p at end_t (seconds from the hit) and fades it out so it reaches
-- silence there, the fade starting at fade_from. A piece that ends earlier
-- on its own still follows the fade.
local function piece_end_at(p, end_t, fade_from)
  local _, _, _, t_off, len = seq_layering_piece_span(p)
  local p_end = t_off + len
  if end_t and end_t < p_end then
    p_end = math.max(t_off + 0.001, end_t)
    p.length_sec = p_end - t_off
  end
  if fade_from and fade_from < p_end then
    p.fade_out = math.max(p.fade_out or 0.0, p_end - math.max(t_off, fade_from))
  end
  local plen = p.length_sec or len
  if (p.fade_out or 0) > plen then p.fade_out = plen end
  if (p.fade_in or 0) > plen then p.fade_in = plen end
end

-- opts.no_tail: ignore the whole-hit tail; opts.no_corner_cut: ignore corner
-- lengths and fades (both for drawing what a cut takes away); opts.all: build
-- them even when the stack only plays the original sample.
function seq_layering_build_pieces(slot, opts)
  seq_normalize_slot_layers(slot)
  opts = opts or {}
  if not opts.all and not seq_layering_geometry_active(slot) then
    return {}
  end
  local pieces = {}
  local function add(path, v, weight, fields, owners)
    local p = {
      path = path,
      sample = find_sample_by_path(path) or { path = path, name = v and v.name },
      weight = weight,
      startoffs = 0.0,
      time_offset_sec = 0.0,
      length_sec = nil,
      fade_in = 0.0,
      fade_out = 0.0,
      owners = owners,
    }
    for k, val in pairs(fields or {}) do p[k] = val end
    pieces[#pieces + 1] = p
    return p
  end

  if slot.layers.linked then
    local side = slot.layers.transient
    for i = 1, 3 do
      local v, w = side.verts[i], side.blend[i] or 0.0
      local path = (w >= 0.02 and v and v.path) and normalize_path(v.path) or nil
      if path then
        add(path, v, w * seq_layer_vert_vol(v) * side.gain, { lane = i - 1 },
          { { side = "transient", idx = i }, { side = "sustain", idx = i } })
      end
    end
  else
    local tside = slot.layers.transient
    local sside = slot.layers.sustain
    local split = seq_layering_split_sec(slot)
    local pre, post = seq_layering_xfade_window(slot, split)
    for i = 1, 3 do
      local tv, tw = tside.verts[i], tside.blend[i] or 0.0
      local sv, sw = sside.verts[i], sside.blend[i] or 0.0
      local tpath = (tw >= 0.02 and tv and tv.path) and normalize_path(tv.path) or nil
      local spath = (sw >= 0.02 and sv and sv.path) and normalize_path(sv.path) or nil
      local tgain = tw * seq_layer_vert_vol(tv) * tside.gain
      local sgain = sw * seq_layer_vert_vol(sv) * sside.gain
      if tpath and spath and tpath == spath and math.abs(tgain - sgain) < 0.05
          and tv.len == sv.len and tv.fade == sv.fade then
        -- Same sample at the same level on both sides: play it whole.
        add(tpath, tv, (tgain + sgain) * 0.5, { lane = i - 1 },
          { { side = "transient", idx = i }, { side = "sustain", idx = i } })
      else
        if tpath then
          local sample = find_sample_by_path(tpath) or { path = tpath, name = tv and tv.name }
          local offs = seq_layering_piece_times(sample, "transient", slot)
          add(tpath, tv, tgain, {
            sample = sample,
            lane = i - 1,
            startoffs = offs or 0.0,
            length_sec = split + post,
            fade_out = pre + post,
          }, { { side = "transient", idx = i } })
        end
        if spath then
          local sample = find_sample_by_path(spath) or { path = spath, name = sv and sv.name }
          local offs, slen = seq_layering_piece_times(sample, "sustain", slot)
          offs = offs or 0.0
          -- Start early by the fade's lead-in (as far as the sample allows).
          local lead = math.min(pre, offs)
          add(spath, sv, sgain, {
            sample = sample,
            lane = i - 1,
            startoffs = offs - lead,
            time_offset_sec = split - lead,
            length_sec = slen + lead,
            fade_in = lead + post,
          }, { { side = "sustain", idx = i } })
        end
      end
    end
  end

  -- Corner lengths / fades, then the whole-hit tail.
  local layers = slot.layers
  local tail_on = not opts.no_tail and (layers.tail_end or layers.tail_fade)
  local natural_end = nil
  if tail_on and not layers.tail_end then
    natural_end = seq_layering_natural_end(slot)
  end
  local kept = {}
  for _, p in ipairs(pieces) do
    if not opts.no_corner_cut then
      local o = p.owners[#p.owners]
      local v = layers[o.side].verts[o.idx]
      if v.len or v.fade then
        local _, _, _, t_off, len = seq_layering_piece_span(p)
        local end_t = v.len or (t_off + len)
        piece_end_at(p, v.len, v.fade and (math.min(end_t, t_off + len) - v.fade) or nil)
      end
    end
    local keep = true
    if tail_on then
      local _, _, _, t_off, len = seq_layering_piece_span(p)
      local end_t = layers.tail_end or natural_end or (t_off + len)
      if t_off >= end_t - 0.0005 then
        keep = false
      else
        piece_end_at(p, layers.tail_end, layers.tail_fade and (end_t - layers.tail_fade) or nil)
      end
    end
    if keep then kept[#kept + 1] = p end
  end
  return seq_layering_remap_piece_lanes(kept)
end

function seq_layering_set_side_gain(slot, side_key, g)
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  g = seq_layer_clamp_gain(g)
  if math.abs((side.gain or 1.0) - g) < 1e-7 then return false end
  side.gain = g
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Tail end (seconds from the hit; nil or past the natural end = none) and
-- fade (seconds before the end). The fade never outlasts the end.
function seq_layering_set_tail(slot, end_t, fade)
  seq_normalize_slot_layers(slot)
  local L = slot.layers
  local natural = seq_layering_natural_end(slot)
  end_t = seq_layer_clamp_len(end_t)
  if end_t and natural and end_t >= natural - 0.001 then end_t = nil end
  local stop = end_t or natural
  fade = seq_layer_clamp_fade(fade)
  if fade and stop then fade = math.min(fade, stop) end
  if L.tail_end == end_t and L.tail_fade == fade then return false end
  L.tail_end, L.tail_fade = end_t, fade
  return true
end

-- Corner length and fade (seconds; nil = natural end / no fade).
function seq_layering_set_corner_cut(slot, side_key, idx, len, fade)
  seq_normalize_slot_layers(slot)
  local v = slot.layers[side_key].verts[idx]
  len, fade = seq_layer_clamp_len(len), seq_layer_clamp_fade(fade)
  if v.len == len and v.fade == fade then return false end
  v.len, v.fade = len, fade
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Where a corner's sound starts and ends in the hit (seconds), before its
-- own length / fade, or nil when it isn't heard.
function seq_layering_corner_span(slot, side_key, idx)
  local t0, t1 = nil, nil
  for _, p in ipairs(seq_layering_build_pieces(slot, { no_tail = true, no_corner_cut = true })) do
    for _, o in ipairs(p.owners or {}) do
      if o.side == side_key and o.idx == idx then
        local _, _, _, t_off, len = seq_layering_piece_span(p)
        t0 = math.min(t0 or t_off, t_off)
        t1 = math.max(t1 or 0, t_off + len)
      end
    end
  end
  return t0, t1
end

-- One lane per sound in the hit, for its length / fade handles: the corner(s)
-- it belongs to, its sample and where it sits (seconds, uncut).
function seq_layering_lanes(slot)
  seq_normalize_slot_layers(slot)
  local lanes = {}
  for _, p in ipairs(seq_layering_build_pieces(slot, { no_tail = true, no_corner_cut = true, all = true })) do
    local owners = p.owners or {}
    if slot.layers.linked then
      owners = { owners[1] }  -- the sustain mirrors the transient
    end
    local o = owners[1]
    if o then
      local keys = {}
      for _, ow in ipairs(owners) do keys[#keys + 1] = ow.side:sub(1, 1) .. ow.idx end
      local sample, pd, startoffs, t_off, len = seq_layering_piece_span(p)
      lanes[#lanes + 1] = {
        key = table.concat(keys, "+"),
        owners = owners,
        path = p.path,
        sample = sample,
        pdur = pd,
        startoffs = startoffs,
        t_off = t_off,
        len = len,
        vert = slot.layers[o.side].verts[o.idx],
      }
    end
  end
  return lanes
end

-- Peaks of a lane on the hit's time line [0, dur] (normalized to the lane),
-- cached per lane, width and time line.
seq_layer_lane_peak_cache = {}
function seq_layering_lane_peaks(lane, bins, dur)
  local key = string.format("%s|%s|%.5f|%.5f|%.5f|%d|%.5f", lane.key, lane.path, lane.startoffs, lane.t_off, lane.len, bins, dur)
  local hit = seq_layer_lane_peak_cache[key]
  if hit then return hit end
  if seq_layer_lane_peak_cache_n and seq_layer_lane_peak_cache_n > 64 then
    seq_layer_lane_peak_cache = {}
    seq_layer_lane_peak_cache_n = 0
  end
  local out = {}
  local src = lane.sample and seq_env_get_wave_peaks(lane.sample, math.max(64, bins))
  local n = src and #src or 0
  local max_v = 0.0
  for b = 1, bins do
    local t = (b - 0.5) / bins * dur
    local v = 0.0
    if n > 0 and lane.pdur > 0 and t >= lane.t_off and t <= lane.t_off + lane.len then
      local si = math.floor(((lane.startoffs + t - lane.t_off) / lane.pdur) * n) + 1
      if si >= 1 and si <= n then v = src[si] or 0 end
    end
    out[b] = v
    if v > max_v then max_v = v end
  end
  if max_v > 0.0001 then
    for b = 1, bins do out[b] = out[b] / max_v end
  end
  seq_layer_lane_peak_cache[key] = out
  seq_layer_lane_peak_cache_n = (seq_layer_lane_peak_cache_n or 0) + 1
  return out
end

-- Sets length / fade on every corner a lane belongs to.
function seq_layering_set_lane_cut(slot, lane, len, fade)
  local changed = false
  for _, o in ipairs(lane.owners) do
    if seq_layering_set_corner_cut(slot, o.side, o.idx, len, fade) then changed = true end
  end
  return changed
end

-- End of the hit before the tail cuts it (seconds).
function seq_layering_natural_end(slot)
  local pieces = seq_layering_build_pieces(slot, { no_tail = true })
  local dur = nil
  for i = 1, #pieces do
    local _, _, _, t_off, len = seq_layering_piece_span(pieces[i])
    if not dur or t_off + len > dur then dur = t_off + len end
  end
  return dur
end

function seq_item_apply_layer_fades(item, fade_in, fade_out)
  if not item then
    return
  end
  fade_in = math.max(0.0, fade_in or 0.0)
  fade_out = math.max(0.0, fade_out or 0.0)
  r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out)
  if fade_in > 0.0 then
    pcall(function()
      r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 1)
    end)
  end
  if fade_out > 0.0 then
    pcall(function()
      r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 1)
    end)
  end
  pcall(function()
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", 0)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", 0)
  end)
end

function seq_layering_randomize_vert(slot, side, vert_idx)
  seq_normalize_slot_layers(slot)
  local v = slot.layers[side].verts[vert_idx]
  if not v or v.locked then
    return false
  end
  local pool = seq_layering_collect_pool(slot, side, vert_idx)
  if #pool == 0 then
    local filter, own = seq_layering_rand_label(slot, side, vert_idx)
    log(own and ("No samples match " .. filter) or "No other samples available to layer")
    return false
  end
  local pick = pool[math.random(1, #pool)]
  if not pick then
    return false
  end
  v.path = pick.path
  v.name = pick.name or basename(pick.path)
  v.vol = 1.0
  seq_layering_ensure_audible(slot.layers[side], vert_idx)
  seq_layering_sync_linked(slot, side)
  state.seq_layering_ab = nil
  preview_sample(pick)
  return true
end

function seq_layering_randomize_side(slot, side)
  seq_normalize_slot_layers(slot)
  local changed = false
  for i = 1, 3 do
    if seq_layering_randomize_vert(slot, side, i) then
      changed = true
    end
  end
  return changed
end

-- Puts the whole blend on one corner.
function seq_layering_solo_vert(slot, side_key, idx)
  if not slot or idx < 1 or idx > 3 then return false end
  seq_normalize_slot_layers(slot)
  local b = slot.layers[side_key].blend
  b[1], b[2], b[3] = 0.0, 0.0, 0.0
  b[idx] = 1.0
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Equal weights across the corners that hold a sample.
function seq_layering_even_mix(slot, side_key)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  local w = { 0.0, 0.0, 0.0 }
  local n = 0
  for i = 1, 3 do
    if side.verts[i].path then
      w[i] = 1.0
      n = n + 1
    end
  end
  if n == 0 then
    w = { 1.0, 1.0, 1.0 }
  end
  side.blend[1], side.blend[2], side.blend[3] = seq_layer_clamp_bary(w[1], w[2], w[3])
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Back to the track sample alone: blend on the top corner, volumes at 100%.
function seq_layering_reset_side(slot, side_key)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  side.blend[1], side.blend[2], side.blend[3] = 1.0, 0.0, 0.0
  for i = 1, 3 do
    side.verts[i].vol = 1.0
  end
  seq_layering_sync_linked(slot, side_key)
  return true
end

-- Empties an unlocked side corner (the top corner is the track sample).
function seq_layering_clear_vert(slot, side_key, idx)
  if not slot or idx < 2 or idx > 3 then return false end
  seq_normalize_slot_layers(slot)
  local side = slot.layers[side_key]
  local v = side.verts[idx]
  if v.locked or not v.path then return false end
  v.path = nil
  v.name = nil
  v.vol = 1.0
  local b = side.blend
  b[idx] = 0.0
  b[1], b[2], b[3] = seq_layer_clamp_bary(b[1], b[2], b[3])
  seq_layering_sync_linked(slot, side_key)
  return true
end

function seq_layering_copy_side_to_other(slot, from_key)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  local to_key = (from_key == "transient") and "sustain" or "transient"
  seq_layering_copy_side(slot.layers[to_key], slot.layers[from_key])
  return true
end

function seq_layering_swap_sides(slot)
  if not slot then return false end
  seq_normalize_slot_layers(slot)
  slot.layers.transient, slot.layers.sustain = slot.layers.sustain, slot.layers.transient
  return true
end

function seq_layering_mix_fingerprint(slot)
  seq_normalize_slot_layers(slot)
  local bits = { tostring(slot.id or 0), slot.layers.linked and "1" or "0" }
  for _, side_key in ipairs({ "transient", "sustain" }) do
    local side = slot.layers[side_key]
    bits[#bits + 1] = string.format("%.3f,%.3f,%.3f,%.4f", side.blend[1] or 0, side.blend[2] or 0, side.blend[3] or 0, side.gain or 1)
    for i = 1, 3 do
      local v = side.verts[i]
      bits[#bits + 1] = (v and v.path) or ""
      bits[#bits + 1] = string.format("%.3f,%.4f,%.4f", seq_layer_vert_vol(v), v.len or -1, v.fade or -1)
    end
  end
  bits[#bits + 1] = string.format("%.4f,%.4f", slot.layers.tail_end or -1, slot.layers.tail_fade or -1)
  bits[#bits + 1] = slot.sample_path or ""
  bits[#bits + 1] = string.format("%.3f", slot.layers.bias or 0.0)
  bits[#bits + 1] = string.format("%.4f", slot.layers.xfade or 0.0)
  return table.concat(bits, "|")
end

-- Where a piece sits: its sample, source length, source offset, start in
-- the mix and length (seconds). A piece without a length plays to its end.
function seq_layering_piece_span(p)
  local sample = p.sample or find_sample_by_path(p.path)
  local pdur = seq_sample_source_length_sec(p.path, sample)
      or (sample and tonumber(sample.duration)) or 0.2
  local startoffs = p.startoffs or 0.0
  local t_off = p.time_offset_sec or 0.0
  local len = p.length_sec
  if not len or len <= 0 then
    len = math.max(0.01, pdur - startoffs)
  end
  -- A piece never outlasts its source.
  len = math.max(0.001, math.min(len, pdur - startoffs))
  return sample, pdur, startoffs, t_off, len
end

-- Length of the layered hit (seconds): until its last piece ends, or nil when
-- the track isn't layered.
function seq_layering_mix_duration(slot)
  if not slot then return nil end
  local pieces = seq_layering_build_pieces(slot)
  if #pieces == 0 then return nil end
  local dur = 0.0
  for i = 1, #pieces do
    local _, _, _, t_off, len = seq_layering_piece_span(pieces[i])
    if t_off + len > dur then dur = t_off + len end
  end
  return dur > 0.001 and dur or nil
end

-- Fade gain of a piece at t seconds into it (linear, as the preview draws it).
function seq_layering_piece_gain(t, len, fade_in, fade_out)
  local g = 1.0
  if fade_in and fade_in > 0 and t < fade_in then
    g = g * math.max(0.0, t / fade_in)
  end
  if fade_out and fade_out > 0 and t > len - fade_out then
    g = g * math.max(0.0, (len - t) / fade_out)
  end
  return g
end

-- Peaks of the layered mix (normalized to 1), its duration, and "ribbon"
-- segments { u0, u1, color } (fractions of the width) naming the corner sample
-- that dominates each stretch. Cached until the layering changes.
function seq_layering_mix_peaks(slot, width)
  width = math.max(48, math.min(320, math.floor(width or 200)))
  local fp = seq_layering_mix_fingerprint(slot) .. "#" .. tostring(width)
  local cache = seq_layer_mix_wave_cache
  if cache and cache.fp == fp and cache.peaks then
    return cache.peaks, cache.dur, cache.ribbon
  end
  local pieces = seq_layering_build_pieces(slot)
  local orig = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if #pieces == 0 then
    if not orig then
      return nil, nil, nil
    end
    local peaks, dur = seq_env_get_wave_peaks(orig, width)
    seq_layer_mix_wave_cache = { fp = fp, peaks = peaks, dur = dur }
    return peaks, dur, nil
  end
  local dur = 0.0
  local resolved = {}
  for i = 1, #pieces do
    local p = pieces[i]
    local sample, pdur, startoffs, t_off, len = seq_layering_piece_span(p)
    local end_t = t_off + len
    if end_t > dur then dur = end_t end
    resolved[#resolved + 1] = {
      sample = sample,
      startoffs = startoffs,
      t_off = t_off,
      len = len,
      weight = p.weight or 1.0,
      fade_in = p.fade_in or 0.0,
      fade_out = p.fade_out or 0.0,
      pdur = pdur,
    }
  end
  -- The axis runs to where the hit would end without the tail or corner
  -- cuts, so the cut part stays in view (and its handle can be dragged back).
  -- Corner cuts too: the axis is the hit with nothing cut.
  for _, p in ipairs(seq_layering_build_pieces(slot, { no_tail = true, no_corner_cut = true })) do
    local _, _, _, t_off, len = seq_layering_piece_span(p)
    if t_off + len > dur then dur = t_off + len end
  end
  if dur <= 0.001 then dur = 0.2 end
  local out, best, best_v = {}, {}, {}
  for i = 1, width do
    out[i] = 0.0
    best_v[i] = 0.0
  end
  for i = 1, #resolved do
    local rp = resolved[i]
    if rp.sample then
      local peaks, pd = seq_env_get_wave_peaks(rp.sample, width)
      pd = pd or rp.pdur
      if peaks and pd and pd > 0 then
        local n = #peaks
        -- Only the bins this piece covers.
        local b0 = math.max(1, math.floor(rp.t_off / dur * width + 0.5))
        local b1 = math.min(width, math.ceil((rp.t_off + rp.len) / dur * width + 0.5))
        for b = b0, b1 do
          local t = ((b - 0.5) / width) * dur
          if t >= rp.t_off and t <= rp.t_off + rp.len then
            local src_t = rp.startoffs + (t - rp.t_off)
            local si = math.floor((src_t / pd) * n) + 1
            if si >= 1 and si <= n then
              local v = (peaks[si] or 0) * rp.weight
                  * seq_layering_piece_gain(t - rp.t_off, rp.len, rp.fade_in, rp.fade_out)
              out[b] = out[b] + v
              if v > best_v[b] then
                best_v[b] = v
                best[b] = i
              end
            end
          end
        end
      end
    end
  end
  local max_v = 0.0
  for i = 1, width do
    if out[i] > max_v then max_v = out[i] end
  end
  if max_v > 0.0001 then
    for i = 1, width do out[i] = out[i] / max_v end
  end
  -- Merge runs of the same dominant piece; quiet bins extend the current run.
  local ribbon = {}
  local cur, run0 = nil, 1
  for b = 1, width + 1 do
    local who = best[b]
    if b <= width and (not who or best_v[b] < 0.02 * max_v) then
      who = cur
    end
    if who ~= cur or b > width then
      if cur then
        local rs = resolved[cur].sample
        ribbon[#ribbon + 1] = {
          u0 = (run0 - 1) / width,
          u1 = (b - 1) / width,
          color = get_sample_dot_color(rs),
        }
      end
      cur, run0 = who, b
    end
  end
  seq_layer_mix_wave_cache = { fp = fp, peaks = out, dur = dur, ribbon = ribbon }
  return out, dur, ribbon
end

function seq_layering_start_mix_voice(v, into)
  if not v or not v.path or v.started then
    return
  end
  local src = r.PCM_Source_CreateFromFile(v.path)
  if not src then
    return
  end
  local vol = seq_layering_voice_vol(v, into or 0.0)
  local pos = (v.startoffs or 0.0) + (into or 0.0)
  if r.CF_CreatePreview and r.CF_Preview_SetValue and r.CF_Preview_Play then
    local obj = r.CF_CreatePreview(src)
    if obj then
      r.CF_Preview_SetValue(obj, "D_VOLUME", vol)
      if pos > 0 then
        r.CF_Preview_SetValue(obj, "D_POSITION", pos)
      end
      if r.CF_Preview_Play(obj) then
        v.started = true
        v.obj = obj
        v.src = src
        return
      end
    end
  elseif r.Xen_StartSourcePreview then
    local preview_id = r.Xen_StartSourcePreview(src, vol, false)
    if preview_id and preview_id ~= 0 then
      v.started = true
      v.xen_id = preview_id
      v.src = src
      v.engine_owned = true
      return
    end
  end
  if r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, src)
  end
end

-- Preview volume of a voice t seconds after it starts, with its fades.
function seq_layering_voice_vol(v, t)
  local g = 1.0
  if v.len and v.len > 0 then
    g = seq_layering_piece_gain(t, v.len, v.fade_in, v.fade_out)
  elseif v.fade_in and v.fade_in > 0 and t < v.fade_in then
    g = math.max(0.0, t / v.fade_in)
  end
  return (state.preview_volume or 1.0) * (v.volume or 1.0) * g
end

function seq_layering_stop_mix_voice(v)
  if not v or not v.started then
    return
  end
  if v.obj and r.CF_Preview_Stop then
    pcall(r.CF_Preview_Stop, v.obj)
  elseif v.xen_id and r.Xen_StopSourcePreview then
    pcall(r.Xen_StopSourcePreview, v.xen_id)
  end
  if v.src and not v.engine_owned and r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, v.src)
  end
  v.obj = nil
  v.xen_id = nil
  v.src = nil
  v.started = false
end

function seq_layering_update_mix_preview()
  local mix = seq_layer_mix_preview
  if not mix then
    return
  end
  local now = r.time_precise()
  local elapsed = now - (mix.t0 or now)
  if elapsed >= (mix.duration or 0) + 0.04 then
    stop_preview()
    return
  end
  for i = 1, #(mix.voices or {}) do
    local v = mix.voices[i]
    if v and not v.started and elapsed >= (v.start_at or 0) - 0.001 then
      seq_layering_start_mix_voice(v, math.max(0.0, elapsed - (v.start_at or 0)))
    end
    if v and v.started and v.stop_at and elapsed >= v.stop_at then
      seq_layering_stop_mix_voice(v)
    elseif v and v.started and v.obj and ((v.fade_in or 0) > 0 or (v.fade_out or 0) > 0)
        and r.CF_Preview_SetValue then
      -- Fades ride the preview volume, one step per frame.
      pcall(r.CF_Preview_SetValue, v.obj, "D_VOLUME",
        seq_layering_voice_vol(v, elapsed - (v.start_at or 0)))
    end
  end
end

function seq_layering_preview_original(slot, start_time)
  if not slot then return end
  local sample = slot.sample_path and find_sample_by_path(slot.sample_path) or nil
  if not sample then return end
  state.seq_layering_ab = "original"
  preview_sample(sample, start_time)
end

function seq_layering_preview_layered(slot, start_time)
  if not slot then return end
  start_time = math.max(0.0, start_time or 0.0)
  state.seq_layering_ab = "layered"
  local pieces = seq_layering_build_pieces(slot)
  local _, dur = seq_layering_mix_peaks(slot, 200)
  dur = dur or 0.2
  if #pieces == 0 then
    seq_layering_preview_original(slot, start_time)
    state.seq_layering_ab = "layered"
    return
  end
  stop_preview()
  local voices = {}
  for i = 1, #pieces do
    local piece = pieces[i]
    local _, _, startoffs, t_off, len = seq_layering_piece_span(piece)
    voices[#voices + 1] = {
      path = piece.path,
      startoffs = startoffs,
      volume = piece.weight or 1.0,
      start_at = t_off,
      stop_at = t_off + len,
      len = len,
      fade_in = piece.fade_in or 0.0,
      fade_out = piece.fade_out or 0.0,
      started = false,
    }
  end
  seq_layer_mix_preview = {
    slot_id = slot.id,
    t0 = r.time_precise() - start_time,
    duration = dur,
    voices = voices,
  }
  preview_sample_obj = {
    path = "layering-mix:" .. tostring(slot.id),
    name = (slot.name or "Track") .. " (layered)",
    duration = dur,
  }
  preview_proc = true
  preview_start_time = seq_layer_mix_preview.t0
  state.preview_position = start_time
  state.preview_paused = false
  seq_layering_update_mix_preview()
end

function seq_layering_ab_playing(slot, kind)
  if not slot then return false end
  if kind == "layered" then
    return seq_layer_mix_preview ~= nil and seq_layer_mix_preview.slot_id == slot.id
  end
  return seq_layer_mix_preview == nil
      and preview_sample_obj
      and slot.sample_path
      and preview_sample_obj.path == slot.sample_path
end

-- ===== Commit (glue) =======================================================
-- Commit renders the layered hit to a WAV in the render folder, adds it to
-- the library and makes it the track's sample with a fresh stack on top.
-- slot.layer_versions keeps every glue and the stack it was glued from:
--   { current = n (a glue) or "stack:n" (glue n's source stack) or nil,
--     glues = { { path, name, at, stack = { sample_path, sample_name, layers } } } }

SEQ_LAYER_RENDER_DIRNAME = "Layered Renders"
SEQ_LAYER_RENDER_KEY = "layering_render_folder"

function seq_layering_default_render_folder()
  local lib = state.folders and state.folders[1]
  if type(lib) == "string" and lib ~= "" then
    return normalize_path(lib):gsub("/+$", "") .. "/" .. SEQ_LAYER_RENDER_DIRNAME
  end
  local res = (r.GetResourcePath and r.GetResourcePath()) or "."
  return normalize_path(res) .. "/Data/Sample Map/" .. SEQ_LAYER_RENDER_DIRNAME
end

-- The configured render folder (Settings > Sequencer), else the default.
function seq_layering_render_folder()
  local v = r.GetExtState and r.GetExtState(SEQ_LAYER_EXT_SECTION or "SampleMapBrowser", SEQ_LAYER_RENDER_KEY) or ""
  if v ~= "" then return v end
  return seq_layering_default_render_folder()
end

function seq_layering_set_render_folder(path)
  if not r.SetExtState then return end
  if not path or path == "" then
    if r.DeleteExtState then
      r.DeleteExtState(SEQ_LAYER_EXT_SECTION or "SampleMapBrowser", SEQ_LAYER_RENDER_KEY, true)
    else
      r.SetExtState(SEQ_LAYER_EXT_SECTION or "SampleMapBrowser", SEQ_LAYER_RENDER_KEY, "", true)
    end
    return
  end
  r.SetExtState(SEQ_LAYER_EXT_SECTION or "SampleMapBrowser", SEQ_LAYER_RENDER_KEY, normalize_path(path), true)
end

-- Writes interleaved float samples (frames x channels) as a 32-bit float WAV.
-- chunks: list of tables of interleaved samples. Returns true on success.
function seq_layering_write_wav(path, srate, channels, chunks)
  local f = io.open(path, "wb")
  if not f then return false end
  local frames_total = 0
  for _, c in ipairs(chunks) do frames_total = frames_total + #c end
  local data_bytes = frames_total * 4
  local block_align = channels * 4
  f:write("RIFF", string.pack("<I4", 4 + 26 + 12 + 8 + data_bytes), "WAVE")
  f:write("fmt ", string.pack("<I4I2I2I4I4I2I2", 18, 3, channels, srate, srate * block_align, block_align, 32),
    string.pack("<I2", 0))
  f:write("fact", string.pack("<I4I4", 4, frames_total // channels))
  f:write("data", string.pack("<I4", data_bytes))
  for _, c in ipairs(chunks) do
    local parts, n = {}, 0
    for i = 1, #c do
      n = n + 1
      parts[n] = string.pack("<f", c[i])
      if n >= 4096 then
        f:write(table.concat(parts, "", 1, n))
        n = 0
      end
    end
    if n > 0 then f:write(table.concat(parts, "", 1, n)) end
  end
  f:close()
  return true
end

-- Renders the layered hit of slot to path (a WAV). The pieces go on a
-- temporary track as items, a track audio accessor reads them back mixed
-- (with their volumes and fades), and the track is removed again.
function seq_layering_render_mix(slot, path)
  local pieces = seq_layering_build_pieces(slot)
  local dur = seq_layering_mix_duration(slot)
  if #pieces == 0 or not dur then return false, "Nothing to glue" end
  if not (r.CreateTrackAudioAccessor and r.GetAudioAccessorSamples and r.new_array) then
    return false, "This REAPER can't render audio from a script"
  end
  local srate = 48000
  if r.GetSetProjectInfo then
    local sr = tonumber(r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)) or 0
    if sr >= 8000 then srate = math.floor(sr + 0.5) end
  end
  dur = dur + 0.005
  local chunks = {}
  local ok_items, err = false, nil
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, false)
  local tr = r.GetTrack(0, idx)
  if tr then
    ok_items = seq_layering_insert_mix_at_position(
      { path = slot.sample_path, name = slot.sample_name, is_layering_mix = true, layering_slot_id = slot.id },
      0.0, tr)
    if ok_items then
      local acc = r.CreateTrackAudioAccessor(tr)
      if acc then
        local block = 4096
        local total = math.floor(dur * srate + 0.5)
        local buf = r.new_array(block * 2)
        local pos = 0
        while pos < total do
          local n = math.min(block, total - pos)
          buf.clear()
          r.GetAudioAccessorSamples(acc, srate, 2, pos / srate, n, buf)
          local t = buf.table(1, n * 2)
          chunks[#chunks + 1] = t
          pos = pos + n
        end
        r.DestroyAudioAccessor(acc)
      else
        err = "Couldn't read the layered audio"
      end
    else
      err = "The layer samples are offline"
    end
    r.DeleteTrack(tr)
  else
    err = "Couldn't create a render track"
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  if err then return false, err end
  if not seq_layering_write_wav(path, srate, 2, chunks) then
    return false, "Couldn't write " .. path
  end
  return true
end

local function render_file_name(slot)
  local base = tostring(slot.name or slot.sample_name or "Drum"):gsub("%.%w+$", "")
  base = base:gsub("[^%w%-_ ]", ""):gsub("%s+", " ")
  if base == "" then base = "Drum" end
  return string.format("%s layered %s.wav", base, os.date("%Y%m%d-%H%M%S"))
end

-- Adds one rendered file to the library without a scan: indexed now, placed
-- next to the sample it was layered from (tags included), and analyzed
-- quietly in the background (no scan window); the map lays it out when the
-- analysis lands. Returns the sample.
function seq_layering_add_to_library(path, source)
  local hit = find_sample_by_path(path)
  if hit then return hit end
  local ok, sample = pcall(analyze_file, path)  -- also queues the analyzer
  if not ok or type(sample) ~= "table" then return nil end
  if source then
    sample.tags = sample.tags or {}
    local have = {}
    for _, t in ipairs(sample.tags) do have[tostring(t):lower()] = true end
    for _, t in ipairs(source.tags or {}) do
      if not have[tostring(t):lower()] then
        sample.tags[#sample.tags + 1] = t
        have[tostring(t):lower()] = true
      end
    end
    if type(source.x) == "number" and type(source.y) == "number" then
      sample.x = math.max(0.0, math.min(1.0, source.x + (math.random() - 0.5) * 0.01))
      sample.y = math.max(0.0, math.min(1.0, source.y + (math.random() - 0.5) * 0.01))
    end
  end
  state.samples[#state.samples + 1] = sample
  samples_by_path[sample.path] = sample
  if explorer_index_sample then pcall(explorer_index_sample, sample) end
  if sm_quiet_analysis_add then sm_quiet_analysis_add(sample.path) end
  state.scan_unsaved_results = true
  if rebuild_tag_index then pcall(rebuild_tag_index) end
  return sample
end

-- A sample record for a file the library may not have indexed yet.
function seq_layering_sample_for_path(path, name)
  if not path then return nil end
  return find_sample_by_path(path) or { path = path, name = name or basename(path) }
end

function seq_layering_versions(slot)
  if type(slot.layer_versions) ~= "table" then
    slot.layer_versions = { glues = {} }
  end
  local v = slot.layer_versions
  if type(v.glues) ~= "table" then v.glues = {} end
  return v
end

function seq_layering_can_commit(slot)
  return slot ~= nil and slot.sample_path ~= nil and seq_layering_geometry_active(slot)
end

-- Puts sample on the track with a fresh stack (the sample alone on top).
local function start_fresh_stack(slot, sample)
  assign_sample_to_seq_track(slot, sample, false)
  slot.layers = nil
  seq_normalize_slot_layers(slot)
  seq_layering_seed_from_track(slot)
end

-- Glues the current stack. Returns the new glue entry, or nil and a reason.
-- Callers wrap it in an undo step.
function seq_layering_commit_glue(slot)
  if not seq_layering_can_commit(slot) then
    return nil, "Nothing to glue: the stack plays the original sample"
  end
  local folder = seq_layering_render_folder()
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(folder, 0) end
  local path = folder .. "/" .. render_file_name(slot)
  local ok, err = seq_layering_render_mix(slot, path)
  if not ok then
    return nil, err or ("Couldn't render to " .. folder)
  end
  local versions = seq_layering_versions(slot)
  local entry = {
    path = normalize_path(path),
    name = basename(path),
    at = os.time(),
    stack = {
      sample_path = slot.sample_path,
      sample_name = slot.sample_name,
      layers = clone_table_deep(slot.layers),
    },
  }
  versions.glues[#versions.glues + 1] = entry
  versions.current = #versions.glues
  -- Into the library (just this file), then onto the track as the new
  -- stack's sample A.
  local added = seq_layering_add_to_library(entry.path, find_sample_by_path(entry.stack.sample_path))
  start_fresh_stack(slot, added or seq_layering_sample_for_path(entry.path, entry.name))
  seq_layering_sync_arrange(slot, { force_rebuild = true })
  save_config()
  return entry
end

-- Switches the track to glue n, or (unglued = true) back to the stack glue n
-- was made from.
function seq_layering_use_version(slot, n, unglued)
  local versions = seq_layering_versions(slot)
  local g = versions.glues[n]
  if not g then return false end
  if unglued then
    local st = g.stack or {}
    assign_sample_to_seq_track(slot, seq_layering_sample_for_path(st.sample_path, st.sample_name), false)
    slot.layers = clone_table_deep(st.layers)
    seq_normalize_slot_layers(slot)
    versions.current = "stack:" .. n
  else
    start_fresh_stack(slot, seq_layering_sample_for_path(g.path, g.name))
    versions.current = n
  end
  seq_layering_sync_arrange(slot, { force_rebuild = true })
  save_config()
  return true
end

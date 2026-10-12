-- Sample Map Browser module: map_modules
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
-- The Tabs and Path modules of the Sample Map layout. Both lay themselves out
-- for whatever rect the layout gives them: one line, several lines, or a
-- narrow column (one item per line), and fold what does not fit into a
-- "+N" / "..." button instead of clipping it.
local r = reaper

MAP_MOD_ROW_H = 22
MAP_MOD_LINE_GAP = 3

-- Content rect of the current module child, in screen coordinates.
function map_module_rect(pad)
  pad = pad or 2
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww, wh = r.ImGui_GetWindowSize(ctx)
  return wx + pad, wy + pad, math.max(1, (ww or 1) - pad * 2), math.max(1, (wh or 1) - pad * 2)
end

-- How many rows of height row_h (with gap between rows) fit in h.
function map_module_lines(h, row_h, gap)
  row_h = row_h or MAP_MOD_ROW_H
  gap = gap or MAP_MOD_LINE_GAP
  return math.max(1, math.floor((h + gap) / (row_h + gap)))
end

function map_module_text_fit(text, max_w)
  text = tostring(text or "")
  if max_w <= 4 then
    return ""
  end
  local tw = select(1, r.ImGui_CalcTextSize(ctx, text)) or 0
  if tw <= max_w + 0.5 then
    return text
  end
  local ell = "..."
  local lo, hi, best = 0, #text, ""
  while lo <= hi do
    local mid = math.floor((lo + hi) * 0.5)
    local cand = text:sub(1, mid)
    -- never cut inside a UTF-8 sequence
    while #cand > 0 and (cand:byte(#cand) or 0) >= 0x80 and (cand:byte(#cand) or 0) < 0xC0 do
      cand = cand:sub(1, #cand - 1)
    end
    if #cand > 0 and (cand:byte(#cand) or 0) >= 0xC0 then
      cand = cand:sub(1, #cand - 1)
    end
    cand = cand .. ell
    if (select(1, r.ImGui_CalcTextSize(ctx, cand)) or 0) <= max_w then
      best = cand
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return best
end

-- Greedy line packing. widths[i] are item widths; line_w(n) is the room on
-- line n. Returns { {i, ...}, ... }. An item wider than a line gets a line
-- of its own (it is drawn clipped / shortened).
function map_module_pack(widths, line_w, gap, one_per_line)
  local lines, cur, cur_w = {}, {}, 0
  for i, w in ipairs(widths) do
    local need = (#cur > 0) and (gap + w) or w
    if #cur > 0 and (one_per_line or cur_w + need > line_w(#lines + 1)) then
      lines[#lines + 1] = cur
      cur, cur_w, need = {}, 0, w
    end
    cur[#cur + 1] = i
    cur_w = cur_w + need
  end
  if #cur > 0 then
    lines[#lines + 1] = cur
  end
  return lines
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

MAP_TAB_MAX_W = 220
MAP_TAB_MIN_W = 52

-- Plan the tab strip. nat[i] are the tabs' natural widths. Returns
--   { lines = { { 1, 2, "add" }, { 3, "more" } }, widths = { [i] = w }, hidden = { i, ... } }
-- Tabs first shrink (labels shorten) before anything is hidden; hidden tabs
-- are listed under a "+N" button, and the active tab is never hidden.
function map_tabs_plan(nat, avail_w, max_lines, opts)
  opts = opts or {}
  local gap = opts.gap or 3
  local add_w = opts.add_w or 0
  local more_w = opts.more_w or 34
  local min_w = math.min(opts.min_w or MAP_TAB_MIN_W, avail_w)
  local active = opts.active
  local n = #nat
  local function line_w()
    return avail_w
  end

  if opts.vertical then
    local widths, lines, hidden = {}, {}, {}
    for i = 1, n do
      widths[i] = avail_w
    end
    local slots = n + (add_w > 0 and 1 or 0)
    if slots <= max_lines then
      for i = 1, n do
        lines[#lines + 1] = { i }
      end
      if add_w > 0 then
        lines[#lines + 1] = { "add" }
      end
      return { lines = lines, widths = widths, hidden = hidden }
    end
    local show = math.max(0, max_lines - 1)
    local shown = {}
    for i = 1, math.min(show, n) do
      shown[#shown + 1] = i
    end
    if active and active > show and show > 0 then
      shown[#shown] = active
    end
    local is_shown = {}
    for _, i in ipairs(shown) do
      is_shown[i] = true
      lines[#lines + 1] = { i }
    end
    for i = 1, n do
      if not is_shown[i] then
        hidden[#hidden + 1] = i
      end
    end
    local last = { "more" }
    if add_w > 0 then
      last[#last + 1] = "add"
    end
    lines[#lines + 1] = last
    return { lines = lines, widths = widths, hidden = hidden }
  end

  local function try(cap)
    local ws, all = {}, {}
    for i = 1, n do
      ws[i] = math.max(math.min(nat[i], cap), math.min(nat[i], min_w))
      all[i] = math.min(ws[i], avail_w)
    end
    if add_w > 0 then
      all[n + 1] = add_w
    end
    return ws, map_module_pack(all, line_w, gap)
  end
  local function as_plan(ws, packed)
    for _, line in ipairs(packed) do
      for k, i in ipairs(line) do
        if i == n + 1 then
          line[k] = "add"
        end
      end
    end
    return { lines = packed, widths = ws, hidden = {} }
  end

  local maxcap = min_w
  for i = 1, n do
    maxcap = math.max(maxcap, nat[i])
  end
  local ws, packed = try(maxcap)
  if #packed <= max_lines then
    return as_plan(ws, packed)
  end
  -- Shrink every tab to a common cap, as wide as still fits.
  local lo, hi, best = min_w, maxcap, nil
  for _ = 1, 14 do
    local mid = (lo + hi) * 0.5
    local _, p = try(mid)
    if #p <= max_lines then
      best, lo = mid, mid
    else
      hi = mid
    end
  end
  if best then
    ws, packed = try(math.floor(best))
    if #packed <= max_lines then
      return as_plan(ws, packed)
    end
  end
  -- Still too many: show what fits at the smallest width, "+N" for the rest.
  ws = try(min_w)
  local lines, cur, cur_w = {}, {}, 0
  local i = 1
  local tail_w = more_w + (add_w > 0 and (gap + add_w) or 0)
  while i <= n do
    local w = math.min(ws[i], avail_w)
    local need = (#cur > 0) and (gap + w) or w
    local last_line = #lines >= max_lines - 1
    local reserve = last_line and (gap + tail_w) or 0
    if cur_w + need + reserve <= avail_w then
      cur[#cur + 1] = i
      cur_w = cur_w + need
      i = i + 1
    elseif last_line then
      break
    elseif #cur == 0 then
      cur[1] = i
      lines[#lines + 1] = cur
      cur, cur_w = {}, 0
      i = i + 1
    else
      lines[#lines + 1] = cur
      cur, cur_w = {}, 0
    end
  end
  local hidden = {}
  for j = i, n do
    hidden[#hidden + 1] = j
  end
  -- Keep the active tab on screen: it takes the last visible slot.
  if active and active >= i then
    local holder = #cur > 0 and cur or lines[#lines]
    if holder and #holder > 0 then
      local out = holder[#holder]
      holder[#holder] = active
      for k, j in ipairs(hidden) do
        if j == active then
          hidden[k] = out
        end
      end
      table.sort(hidden)
    end
  end
  cur[#cur + 1] = "more"
  if add_w > 0 then
    cur[#cur + 1] = "add"
  end
  lines[#lines + 1] = cur
  return { lines = lines, widths = ws, hidden = hidden }
end

local function map_tab_glyph(tab)
  local tags = {}
  for tag, on in pairs(tab and tab.active_tags or {}) do
    if on and type(tag) == "string" then
      tags[#tags + 1] = tag
    end
  end
  if #tags > 0 then
    table.sort(tags, function(a, b) return a:lower() < b:lower() end)
    local cr, cg, cb = extract_rgb(state.tag_colors and state.tag_colors[tags[1]] or 0x336699)
    return "dot", build_color_rrgbbaa(cr, cg, cb, 255)
  end
  if type(tab.folder_filter_paths) == "table" and #tab.folder_filter_paths > 0 then
    return "folder"
  end
  if type(tab.filter) == "string" and tab.filter ~= "" then
    return "search"
  end
  return nil
end

local MAP_TAB_PAD_X = 9
local MAP_TAB_GLYPH_W = 13
local MAP_TAB_CLOSE_W = 16

local function map_tab_label_and_width(tab)
  local label = map_tab_display_label(tab)
  local tw = select(1, r.ImGui_CalcTextSize(ctx, label)) or 0
  local glyph = map_tab_glyph(tab)
  local w = MAP_TAB_PAD_X * 2 + tw + (glyph and MAP_TAB_GLYPH_W or 0)
  if #(state.map_tabs or {}) > 1 then
    w = w + MAP_TAB_CLOSE_W
  end
  return label, math.min(MAP_TAB_MAX_W, math.ceil(w))
end

function duplicate_map_tab(id)
  ensure_map_tabs()
  if #(state.map_tabs or {}) >= MAP_TAB_MAX then
    return
  end
  local src, idx = find_map_tab(id)
  if not src then
    return
  end
  if id == state.map_tab_active_id then
    snapshot_active_map_tab()
  end
  local parents = {}
  for k, v in pairs(src.selected_tag_parents or {}) do
    parents[k] = v
  end
  local copy = {
    id = state.map_tab_next_id or 1,
    title = src.title and (src.title .. " copy") or nil,
    filter = src.filter or "",
    active_tags = clone_active_tags(src.active_tags),
    folder_filter_paths = clone_string_list(src.folder_filter_paths),
    zoom = src.zoom,
    pan_x = src.pan_x,
    pan_y = src.pan_y,
    view_cx = src.view_cx,
    view_cy = src.view_cy,
    map_y_axis = src.map_y_axis,
    selected_tag_parents = parents,
  }
  state.map_tab_next_id = copy.id + 1
  table.insert(state.map_tabs, idx + 1, copy)
  state.map_tab_active_id = copy.id
  apply_map_tab_view(copy)
  save_config()
end

function close_other_map_tabs(id)
  ensure_map_tabs()
  local keep = find_map_tab(id)
  if not keep then
    return
  end
  if id ~= state.map_tab_active_id then
    switch_map_tab(id)
  end
  state.map_tabs = { keep }
  save_config()
end

function rename_map_tab(id, title)
  local tab = find_map_tab(id)
  if not tab then
    return
  end
  title = tostring(title or ""):gsub("^%s+", ""):gsub("%s+$", "")
  tab.title = title ~= "" and title or nil
  save_config()
end

-- Moves tab `id` to position `to` (1-based) in state.map_tabs.
function move_map_tab(id, to)
  local _, from = find_map_tab(id)
  local n = #(state.map_tabs or {})
  if not from or n < 2 then
    return false
  end
  to = math.max(1, math.min(n, to))
  if to == from then
    return false
  end
  local tab = table.remove(state.map_tabs, from)
  table.insert(state.map_tabs, to, tab)
  return true
end

local function draw_map_tab_glyph(dl, kind, color, cx, cy, text_col)
  if kind == "dot" then
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 3.4, color, 12)
  elseif kind == "folder" then
    ui_button_draw_icon(dl, "folder", cx, cy, 11, text_col)
  elseif kind == "search" then
    r.ImGui_DrawList_AddCircle(dl, cx - 1, cy - 1, 3.2, text_col, 12, 1.2)
    r.ImGui_DrawList_AddLine(dl, cx + 1.4, cy + 1.4, cx + 3.6, cy + 3.6, text_col, 1.3)
  end
end

local function render_map_tab_item(tab, idx, x, y, w, h, vertical, can_close)
  local active = tab.id == state.map_tab_active_id
  local dragging = state.map_tab_drag == tab.id
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = r.ImGui_InvisibleButton(ctx, "##map_tab_" .. tostring(tab.id), w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local pressed = r.ImGui_IsItemActive(ctx)
  local x1, y1 = x + w, y + h
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local rad = UI_METRICS.radius_ctrl
  local text_col
  if active then
    text_col = UI_THEME.text
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x1, y1, hovered and UI_THEME.accent_fill_h or UI_THEME.accent_fill, rad)
    r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x1 - 0.5, y1 - 0.5, 0x1EFF5E50, rad, 0, 1.0)
    if vertical then
      r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 4, x + 4.5, y1 - 4, UI_THEME.accent, 2)
    else
      r.ImGui_DrawList_AddLine(dl, x + 7, y1 - 1.0, x1 - 7, y1 - 1.0, UI_THEME.accent, 2.0)
    end
  elseif hovered or dragging then
    text_col = UI_THEME.text
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x1, y1, UI_THEME.surface_hvr, rad)
  else
    text_col = UI_THEME.text_dim
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x1, y1, UI_THEME.surface, rad)
  end
  if dragging then
    r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x1 - 0.5, y1 - 0.5, UI_THEME.accent, rad, 0, 1.5)
  end

  local show_close = can_close and (hovered or active) and w >= 56
  local tx = x + (vertical and 10 or MAP_TAB_PAD_X)
  local glyph, glyph_col = map_tab_glyph(tab)
  local dy = pressed and 1 or 0
  if glyph and w >= 64 then
    draw_map_tab_glyph(dl, glyph, glyph_col, tx + 4, y + h * 0.5 + dy, text_col)
    tx = tx + MAP_TAB_GLYPH_W
  end
  local right = x1 - MAP_TAB_PAD_X + 2 - (show_close and MAP_TAB_CLOSE_W or 0)
  local full = map_tab_display_label(tab)
  local label = map_module_text_fit(full, right - tx)
  local th = select(2, r.ImGui_CalcTextSize(ctx, "Ay")) or 13
  r.ImGui_DrawList_AddText(dl, tx, y + (h - th) * 0.5 + dy, text_col, label)
  local close_x0 = x1 - MAP_TAB_PAD_X - MAP_TAB_CLOSE_W + 6
  if show_close then
    local mx = select(1, r.ImGui_GetMousePos(ctx))
    local over = hovered and mx and mx >= close_x0 - 2
    local cx, cy = x1 - MAP_TAB_PAD_X - 3, y + h * 0.5 + dy
    if over then
      r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 7, UI_THEME.border_hvr, 12)
    end
    ui_button_draw_icon(dl, "close", cx, cy, 10, over and UI_THEME.text or text_col)
  end

  -- Drag to reorder.
  if pressed and not state.map_ui_edit and r.ImGui_IsMouseDragging and r.ImGui_IsMouseDragging(ctx, 0, 5) then
    state.map_tab_drag = tab.id
  end
  if clicked and not state.map_tab_drag_moved then
    local mx = select(1, r.ImGui_GetMousePos(ctx))
    if show_close and mx and mx >= close_x0 - 2 then
      close_map_tab(tab.id)
      return
    end
    switch_map_tab(tab.id)
  end
  if hovered and r.ImGui_IsItemClicked(ctx, 2) and can_close then
    close_map_tab(tab.id)
    return
  end
  if hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    state.map_tab_rename = { id = tab.id, buf = tab.title or full, focus = true }
    r.ImGui_OpenPopup(ctx, "##map_tab_rename")
  end
  if hovered and r.ImGui_IsItemClicked(ctx, 1) then
    state.map_tab_ctx_id = tab.id
    r.ImGui_OpenPopup(ctx, "##map_tab_ctx")
  end
  if hovered and not state.map_tab_drag then
    r.ImGui_SetTooltip(ctx, full .. "\nEach tab keeps its own search, tags, folders, zoom and pan.\nDouble-click to rename, right-click for more, drag to reorder.")
  end
  state.map_tab_rects[#state.map_tab_rects + 1] = { id = tab.id, index = idx, x0 = x, y0 = y, x1 = x1, y1 = y1 }
end

local function render_map_tab_popups()
  if r.ImGui_BeginPopup(ctx, "##map_tab_ctx") then
    local id = state.map_tab_ctx_id
    local tab = find_map_tab(id)
    if not tab then
      r.ImGui_CloseCurrentPopup(ctx)
    else
      local n = #(state.map_tabs or {})
      if r.ImGui_MenuItem(ctx, "Rename...") then
        state.map_tab_rename = { id = id, buf = tab.title or map_tab_display_label(tab), focus = true }
        state.map_tab_rename_open = true
      end
      if r.ImGui_MenuItem(ctx, "Duplicate", nil, false, n < MAP_TAB_MAX) then
        duplicate_map_tab(id)
      end
      if tab.title and r.ImGui_MenuItem(ctx, "Use automatic name") then
        rename_map_tab(id, "")
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "New tab", nil, false, n < MAP_TAB_MAX) then
        add_map_tab()
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Close", nil, false, n > 1) then
        close_map_tab(id)
      end
      if r.ImGui_MenuItem(ctx, "Close other tabs", nil, false, n > 1) then
        close_other_map_tabs(id)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  if state.map_tab_rename_open then
    state.map_tab_rename_open = nil
    r.ImGui_OpenPopup(ctx, "##map_tab_rename")
  end
  if r.ImGui_BeginPopup(ctx, "##map_tab_rename") then
    local ren = state.map_tab_rename
    if not ren or not find_map_tab(ren.id) then
      r.ImGui_CloseCurrentPopup(ctx)
    else
      r.ImGui_TextColored(ctx, UI_THEME.text_dim, "Tab name")
      if ren.focus and r.ImGui_SetKeyboardFocusHere then
        r.ImGui_SetKeyboardFocusHere(ctx)
        ren.focus = nil
      end
      local flags = 0
      if r.ImGui_InputTextFlags_EnterReturnsTrue then
        flags = r.ImGui_InputTextFlags_EnterReturnsTrue()
      end
      if r.ImGui_InputTextFlags_AutoSelectAll then
        flags = flags | r.ImGui_InputTextFlags_AutoSelectAll()
      end
      r.ImGui_SetNextItemWidth(ctx, 200)
      local enter, buf = r.ImGui_InputText(ctx, "##map_tab_rename_input", ren.buf or "", flags)
      if type(buf) == "string" then
        ren.buf = buf
      end
      if enter or (draw_ui_button("map_tab_rename_ok", "Rename", 0, 0, { compact = true, style = "primary" })) then
        rename_map_tab(ren.id, ren.buf)
        state.map_tab_rename = nil
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx, 0, 6)
      r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Empty = automatic name")
    end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "##map_tab_more") then
    for _, i in ipairs(state.map_tab_hidden or {}) do
      local tab = state.map_tabs[i]
      if tab then
        local active = tab.id == state.map_tab_active_id
        if r.ImGui_Selectable(ctx, map_tab_display_label(tab) .. "##more_" .. tostring(tab.id), active) then
          switch_map_tab(tab.id)
        end
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

function render_sample_map_tab_bar()
  ensure_map_tabs()
  local x0, y0, W, H = map_module_rect(3)
  local row_h, gap = MAP_MOD_ROW_H, MAP_MOD_LINE_GAP
  local tabs = state.map_tabs or {}
  local n = #tabs
  local can_add = n < MAP_TAB_MAX
  local can_close = n > 1
  local max_lines = map_module_lines(H, row_h, gap)
  -- A narrow, tall module lists the tabs one per line.
  local vertical = max_lines >= 2 and (W < 150 or (H > W * 1.2 and max_lines >= 3))

  local labels, nat, active_idx = {}, {}, nil
  for i, tab in ipairs(tabs) do
    labels[i], nat[i] = map_tab_label_and_width(tab)
    if tab.id == state.map_tab_active_id then
      active_idx = i
    end
  end
  local add_w = can_add and row_h or 0
  local plan = map_tabs_plan(nat, W, max_lines, {
    gap = gap, add_w = add_w, more_w = 38, min_w = MAP_TAB_MIN_W, active = active_idx, vertical = vertical,
  })
  state.map_tab_hidden = plan.hidden

  -- Height that shows every tab at full width; the layout uses it when the
  -- module has no fixed height, so new tabs wrap onto a new line.
  local fit_lines
  if vertical then
    fit_lines = n + (can_add and 1 or 0)
  else
    local all = {}
    for i = 1, n do
      all[i] = math.min(nat[i], W)
    end
    if can_add then
      all[#all + 1] = add_w
    end
    fit_lines = #map_module_pack(all, function() return W end, gap)
  end
  state.map_ui_fit_h = state.map_ui_fit_h or {}
  state.map_ui_fit_h.tabs = math.max(1, fit_lines) * (row_h + gap) - gap + 6

  state.map_tab_rects = {}
  local y = y0
  for li, line in ipairs(plan.lines) do
    if li > max_lines then
      break
    end
    local x = x0
    for k, item in ipairs(line) do
      local w
      if item == "add" or item == "more" then
        -- In the one-per-line list the last line is "N more" + a "+" button,
        -- or a full-width "New tab" button.
        if vertical then
          if #line == 1 then
            w = W
          elseif item == "add" then
            w = row_h
          else
            w = math.max(row_h, W - gap - row_h)
          end
        else
          w = item == "add" and add_w or 38
        end
        r.ImGui_SetCursorScreenPos(ctx, x, y)
        if item == "add" then
          local wide = w >= 80
          if draw_ui_button("map_tab_add", wide and "New tab" or nil, w, row_h, {
            icon = (not wide) and "plus" or nil, lead_icon = wide and "plus" or nil, compact = true,
          }) then
            add_map_tab()
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "New Sample Map tab")
          end
        else
          local label = "+" .. tostring(#plan.hidden)
          if w >= 80 then
            label = tostring(#plan.hidden) .. " more"
          end
          if draw_ui_button("map_tab_more", label, w, row_h, { compact = true, trailing_icon = "chev_down" }) then
            r.ImGui_OpenPopup(ctx, "##map_tab_more")
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, #plan.hidden .. " more tab(s): the module is too small to show them all")
          end
        end
      else
        w = math.min(plan.widths[item] or MAP_TAB_MIN_W, W)
        render_map_tab_item(tabs[item], item, x, y, w, row_h, vertical, can_close)
        if tabs ~= state.map_tabs or #state.map_tabs ~= n then
          -- a tab was closed or added this frame; the rest draws next frame
          r.ImGui_SetCursorScreenPos(ctx, x0, y0)
          r.ImGui_Dummy(ctx, 0, 0)
          render_map_tab_popups()
          return
        end
      end
      x = x + w + gap
    end
    y = y + row_h + gap
  end

  -- Reorder while dragging: the dragged tab takes the slot under the mouse.
  if state.map_tab_drag then
    if not r.ImGui_IsMouseDown(ctx, 0) then
      if state.map_tab_drag_moved then
        save_config()
      end
      state.map_tab_drag = nil
      state.map_tab_drag_moved = nil
    else
      local mx, my = r.ImGui_GetMousePos(ctx)
      for _, rect in ipairs(state.map_tab_rects) do
        if rect.id ~= state.map_tab_drag and mx >= rect.x0 and mx <= rect.x1 and my >= rect.y0 and my <= rect.y1 then
          if move_map_tab(state.map_tab_drag, rect.index) then
            state.map_tab_drag_moved = true
          end
          break
        end
      end
      if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
      end
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0)
  r.ImGui_Dummy(ctx, 0, 0)
  render_map_tab_popups()
end

---------------------------------------------------------------------------
-- Path
---------------------------------------------------------------------------

-- Folders from the scan root (or the filesystem root) down to the sample's
-- folder: { { name = "Samples", path = "/Users/b/Samples" }, ... }.
function sample_path_segments(sample)
  local segs = {}
  local full_path = sample and sample.path or ""
  if full_path == "" then
    return segs
  end
  local normalized_path = normalize_path(full_path)
  local scanned_root = nil
  for _, scanned_folder in ipairs(state.folders or {}) do
    local norm_scanned = normalize_path(scanned_folder)
    if normalized_path:sub(1, #norm_scanned) == norm_scanned then
      if not scanned_root or #norm_scanned > #scanned_root then
        scanned_root = norm_scanned
      end
    end
  end
  local dir_path = normalized_path:match("(.+)/[^/]+$") or ""
  if scanned_root and dir_path ~= "" then
    local root_name = scanned_root:match("([^/]+)/?$") or scanned_root
    segs[#segs + 1] = { name = root_name, path = scanned_root, root = true }
    local relative_path = dir_path
    if dir_path:sub(1, #scanned_root) == scanned_root then
      relative_path = dir_path:sub(#scanned_root + 1)
      if relative_path:sub(1, 1) == "/" then
        relative_path = relative_path:sub(2)
      end
    end
    local current_path = scanned_root
    for segment in relative_path:gmatch("([^/]+)") do
      current_path = current_path .. "/" .. segment
      segs[#segs + 1] = { name = segment, path = current_path }
    end
  elseif dir_path ~= "" then
    local is_absolute = dir_path:sub(1, 1) == "/"
    local current_path = is_absolute and "/" or ""
    for segment in dir_path:gmatch("([^/]+)") do
      if is_absolute then
        current_path = current_path .. segment
      else
        current_path = current_path .. (current_path == "" and "" or "/") .. segment
      end
      segs[#segs + 1] = { name = segment, path = current_path }
      if is_absolute then
        current_path = current_path .. "/"
      end
    end
  end
  return segs
end

local PATH_CHEV_W = 13

-- Plan the breadcrumb. seg_w[i] are folder pill widths, file_w the file
-- pill. line_w(n) is the room on line n. Folders from the second one on are
-- folded into a "..." pill (more_w) until the trail fits in max_lines.
-- Returns { items = { {kind="seg", i=}, {kind="more"}, {kind="file"} }, lines = {{item idx...}}, hidden = {seg idx...} }
function map_path_plan(seg_w, file_w, line_w, max_lines, opts)
  opts = opts or {}
  local gap = opts.gap or 2
  local more_w = opts.more_w or 26
  local one = opts.one_per_line
  local n = #seg_w
  local function build(k)
    -- k folders hidden: 2..k+1 while the root stays; k == n hides the root too
    local items, widths, hidden = {}, {}, {}
    local first_hidden, last_hidden = 2, k + 1
    if k >= n then
      first_hidden, last_hidden = 1, n
    end
    local more_added = false
    for i = 1, n do
      if k > 0 and i >= first_hidden and i <= last_hidden then
        hidden[#hidden + 1] = i
        if not more_added then
          items[#items + 1] = { kind = "more" }
          more_added = true
        end
      else
        items[#items + 1] = { kind = "seg", i = i }
      end
    end
    items[#items + 1] = { kind = "file" }
    for idx, it in ipairs(items) do
      local w = it.kind == "seg" and seg_w[it.i] or (it.kind == "more" and more_w or file_w)
      if idx > 1 then
        w = w + PATH_CHEV_W
      end
      widths[idx] = w
    end
    return items, widths, hidden
  end
  for k = 0, n do
    local items, widths, hidden = build(k)
    local lines = map_module_pack(widths, line_w, gap, one)
    if #lines <= max_lines then
      return { items = items, lines = lines, hidden = hidden, widths = widths }
    end
  end
  -- Even "..." + file is too long: one line, the file name shortened.
  local items, widths, hidden = build(n)
  local room = line_w(1)
  local lines = { {} }
  for idx = 1, #items - 1 do
    room = room - widths[idx] - gap
    lines[1][#lines[1] + 1] = idx
  end
  widths[#items] = math.max(PATH_CHEV_W + 30, room)
  lines[1][#lines[1] + 1] = #items
  return { items = items, lines = lines, hidden = hidden, widths = widths }
end

local function path_pill(dl, x0, y0, x1, y1, style, hovered, pressed)
  local bg, border
  if style == "filtered" then
    bg = hovered and UI_THEME.accent_fill_h or UI_THEME.accent_fill
    border = UI_THEME.accent
  elseif style == "file" then
    bg = UI_THEME.elevated
    border = UI_THEME.border_hvr
  elseif hovered then
    bg = UI_THEME.surface_hvr
    border = UI_THEME.border_hvr
  else
    bg = UI_THEME.surface
    border = UI_THEME.border
  end
  ui_draw_panel(dl, x0, y0, x1, y1, (y1 - y0) * 0.5, bg, border, hovered, pressed)
end

function render_path_explorer_button(x, y, w, h, icon_only)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  if draw_ui_button("path_open_explorer", (not icon_only) and "Explorer" or nil, w, h, {
    style = state.explorer_open and "primary" or "default",
    icon = icon_only and "folder" or nil,
    compact = true,
    selected = state.explorer_open,
  }) then
    state.explorer_open = not state.explorer_open
    save_config()
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Browse scan folders and set custom tags.\nDock the window on the right of the sample map, or leave it floating.")
  end
end

local function path_copy(text)
  if r.ImGui_SetClipboardText then
    r.ImGui_SetClipboardText(ctx, text or "")
    if sm_notify then
      sm_notify("Copied to the clipboard")
    end
  end
end

local function render_path_popups()
  if r.ImGui_BeginPopup(ctx, "##path_ctx") then
    local it = state.path_ctx or {}
    if it.kind == "seg" then
      local filtered = folder_filter_has(it.path)
      if r.ImGui_MenuItem(ctx, filtered and "Remove from folder filter" or "Add to folder filter") then
        folder_filter_toggle(it.path)
      end
      if r.ImGui_MenuItem(ctx, "Show only this folder") then
        state.folder_filter_paths = { normalize_path(it.path) }
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, SM_IS_WINDOWS and "Show in Explorer" or "Show in Finder") then
        sm_reveal_path(it.path)
      end
      if r.ImGui_MenuItem(ctx, "Copy folder path") then
        path_copy(it.path)
      end
    elseif it.kind == "file" then
      if r.ImGui_MenuItem(ctx, SM_IS_WINDOWS and "Show in Explorer" or "Show in Finder") then
        sm_reveal_path(it.path)
      end
      if r.ImGui_MenuItem(ctx, "Copy file path") then
        path_copy(it.path)
      end
      if r.ImGui_MenuItem(ctx, "Copy file name") then
        path_copy(it.name)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "##path_more") then
    r.ImGui_TextColored(ctx, UI_THEME.text_mute, "Folders")
    for depth, seg in ipairs(state.path_hidden or {}) do
      local filtered = folder_filter_has(seg.path)
      if r.ImGui_Selectable(ctx, string.rep("  ", depth - 1) .. seg.name .. "##path_more_" .. depth, filtered) then
        folder_filter_toggle(seg.path)
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, seg.path .. "\nClick to add or remove it from the folder filter")
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

function render_sample_path_line()
  local x0, y0, W, H = map_module_rect(3)
  local row_h, line_gap = MAP_MOD_ROW_H, MAP_MOD_LINE_GAP
  local max_lines = map_module_lines(H, row_h, line_gap)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local text_h = select(2, r.ImGui_CalcTextSize(ctx, "Ay")) or 13
  local pill_h = math.min(row_h, text_h + 7)

  -- Explorer button: top right; just a folder icon when space is short.
  local explorer_label_w = (select(1, r.ImGui_CalcTextSize(ctx, "Explorer")) or 50) + 18
  local icon_only = W < 300
  local explorer_w = icon_only and row_h + 2 or explorer_label_w
  if W < explorer_w + 30 then
    explorer_w = 0
  end
  local first_w = math.max(20, W - (explorer_w > 0 and (explorer_w + 6) or 0))
  local function line_w(n)
    return n == 1 and first_w or W
  end

  local function explorer_at(y)
    if explorer_w > 0 then
      render_path_explorer_button(x0 + W - explorer_w, y, explorer_w, row_h, icon_only)
    end
  end

  if not preview_sample_obj then
    local ey = y0 + math.max(0, math.floor((H - row_h) * 0.5))
    explorer_at(ey)
    local msg = W >= 300 and "No sample selected. Click a dot on the map to audition it." or "No sample selected"
    msg = map_module_text_fit(msg, first_w - 4)
    r.ImGui_DrawList_AddText(dl, x0 + 4, ey + (row_h - text_h) * 0.5, UI_THEME.text_mute, msg)
    state.path_hidden = nil
    r.ImGui_SetCursorScreenPos(ctx, x0, y0)
    r.ImGui_Dummy(ctx, 0, 0)
    render_path_popups()
    return
  end

  local sample = preview_sample_obj
  local segs = sample_path_segments(sample)
  local filename = sample.name or (sample.path or ""):match("([^/\\]+)$") or "Unknown"
  local vertical = max_lines >= 3 and W < 220
  local indent_step = vertical and math.min(9, math.max(4, (W - 80) / math.max(1, #segs + 1))) or 0
  -- Folder pills never take more than about half a line.
  local seg_cap = vertical and W or math.max(56, W * 0.5)
  local seg_w = {}
  for i, seg in ipairs(segs) do
    local tw = select(1, r.ImGui_CalcTextSize(ctx, seg.name)) or 0
    seg_w[i] = math.min(seg_cap, tw + 14 + (seg.root and 14 or 0))
  end
  local dur = tonumber(sample.duration)
  local meta = (dur and dur > 0) and string.format("%.2fs", dur) or nil
  local meta_w = meta and ((select(1, r.ImGui_CalcTextSize(ctx, meta)) or 0) + 8) or 0
  local file_text_w = select(1, r.ImGui_CalcTextSize(ctx, filename)) or 0
  local file_w = math.min(W, file_text_w + 28 + meta_w)
  local plan = map_path_plan(seg_w, file_w, line_w, max_lines, {
    gap = 2, more_w = 26, one_per_line = vertical,
  })
  state.path_hidden = {}
  for _, i in ipairs(plan.hidden) do
    state.path_hidden[#state.path_hidden + 1] = segs[i]
  end

  local y = y0
  if #plan.lines == 1 and max_lines > 1 then
    y = y0 + math.floor((H - row_h) * 0.5)
  end
  explorer_at(y)
  local item_n = 0
  for li, line in ipairs(plan.lines) do
    if li > max_lines then
      break
    end
    local lw = line_w(li)
    local x = x0
    if vertical then
      x = x0 + math.min(W * 0.35, (li - 1) * indent_step)
    end
    for k, idx in ipairs(line) do
      local it = plan.items[idx]
      item_n = item_n + 1
      local room = (x0 + lw) - x
      if idx > 1 then
        -- chevron (an elbow in the one-per-line tree)
        local cy = y + row_h * 0.5
        if vertical then
          local ex = x + 3
          r.ImGui_DrawList_AddLine(dl, ex, y - line_gap - 2, ex, cy, UI_THEME.border_hvr, 1.0)
          r.ImGui_DrawList_AddLine(dl, ex, cy, ex + 7, cy, UI_THEME.border_hvr, 1.0)
        else
          ui_button_draw_icon(dl, "chev_right", x + 5, cy, 11, UI_THEME.text_mute)
        end
        x = x + PATH_CHEV_W
        room = room - PATH_CHEV_W
      end
      local w = math.min(plan.widths[idx] - (idx > 1 and PATH_CHEV_W or 0), math.max(18, room))
      local py = y + (row_h - pill_h) * 0.5
      r.ImGui_SetCursorScreenPos(ctx, x, py)
      if it.kind == "more" then
        local clicked = r.ImGui_InvisibleButton(ctx, "##path_more_btn", w, pill_h)
        local hovered = r.ImGui_IsItemHovered(ctx)
        path_pill(dl, x, py, x + w, py + pill_h, nil, hovered, r.ImGui_IsItemActive(ctx))
        local cx, cy = x + w * 0.5, py + pill_h * 0.5
        for d = -1, 1 do
          r.ImGui_DrawList_AddCircleFilled(dl, cx + d * 4.5, cy, 1.4, hovered and UI_THEME.text or UI_THEME.text_dim, 6)
        end
        if clicked then
          r.ImGui_OpenPopup(ctx, "##path_more")
        end
        if hovered then
          r.ImGui_SetTooltip(ctx, #plan.hidden .. " folder(s) hidden to fit; click to see them")
        end
      elseif it.kind == "seg" then
        local seg = segs[it.i]
        local filtered = folder_filter_has(seg.path)
        local clicked = r.ImGui_InvisibleButton(ctx, "##path_seg_" .. it.i, w, pill_h)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local pressed = r.ImGui_IsItemActive(ctx)
        path_pill(dl, x, py, x + w, py + pill_h, filtered and "filtered" or nil, hovered, pressed)
        local tx = x + 7
        local col = filtered and 0xFFFFFFFF or (hovered and UI_THEME.text or UI_THEME.text_dim)
        if seg.root then
          ui_button_draw_icon(dl, "folder", tx + 5, py + pill_h * 0.5, 11, filtered and UI_THEME.accent or UI_THEME.text_mute)
          tx = tx + 14
        end
        local label = map_module_text_fit(seg.name, x + w - 7 - tx)
        r.ImGui_DrawList_AddText(dl, tx, py + (pill_h - text_h) * 0.5 + (pressed and 1 or 0), col, label)
        if clicked then
          folder_filter_toggle(seg.path)
        end
        if hovered and r.ImGui_IsItemClicked(ctx, 1) then
          state.path_ctx = { kind = "seg", path = seg.path }
          r.ImGui_OpenPopup(ctx, "##path_ctx")
        end
        if hovered then
          r.ImGui_SetTooltip(ctx, seg.path .. "\nClick: " .. (filtered and "remove from" or "add to")
            .. " the folder filter.  Right-click: more")
        end
      else
        local clicked = r.ImGui_InvisibleButton(ctx, "##path_file", w, pill_h)
        local hovered = r.ImGui_IsItemHovered(ctx)
        path_pill(dl, x, py, x + w, py + pill_h, "file", hovered, r.ImGui_IsItemActive(ctx))
        local gx, gy = x + 10, py + pill_h * 0.5
        local bars = { 0.35, 0.8, 0.55, 1.0, 0.45 }
        for bi = 1, #bars do
          local bh = bars[bi] * (pill_h * 0.28)
          local bx = gx - 4 + (bi - 1) * 2
          r.ImGui_DrawList_AddLine(dl, bx, gy - bh, bx, gy + bh, UI_THEME.accent, 1.0)
        end
        local tx = x + 18
        local right = x + w - 8
        local show_meta = meta and (right - tx) >= file_text_w + meta_w
        if show_meta then
          local mw = meta_w - 8
          r.ImGui_DrawList_AddText(dl, right - mw, py + (pill_h - text_h) * 0.5, UI_THEME.text_mute, meta)
          right = right - meta_w
        end
        r.ImGui_DrawList_AddText(dl, tx, py + (pill_h - text_h) * 0.5, UI_THEME.text, map_module_text_fit(filename, right - tx))
        if clicked or (hovered and r.ImGui_IsItemClicked(ctx, 1)) then
          state.path_ctx = { kind = "file", path = sample.path, name = filename }
          r.ImGui_OpenPopup(ctx, "##path_ctx")
        end
        if hovered then
          r.ImGui_SetTooltip(ctx, (sample.path or filename) .. "\nClick for Show in Finder / Copy path")
        end
      end
      x = x + w + 2
    end
    y = y + row_h + line_gap
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0)
  r.ImGui_Dummy(ctx, 0, 0)
  render_path_popups()
end

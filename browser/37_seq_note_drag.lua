-- Sample Map Browser module: seq_note_drag
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

function seq_vary_filter_span_cols(slot, col, start_qn, step_qn, step_count)
  col = math.max(0, math.min((step_count or 1) - 1, col or 0))
  local key = seq_vary_filter_cell_key(slot, col, start_qn, step_qn)
  if not key then
    return col, col
  end
  local lo, hi = col, col
  while lo > 0 and seq_vary_filter_cell_key(slot, lo - 1, start_qn, step_qn) == key do
    lo = lo - 1
  end
  while hi < step_count - 1 and seq_vary_filter_cell_key(slot, hi + 1, start_qn, step_qn) == key do
    hi = hi + 1
  end
  return lo, hi
end

function draw_seq_vary_filter_span(dl, ctx, x0, y0, x1, y1, text, edit_mode, hovered, editing)
  local pad = 3.0
  local sx0 = x0 + 1.0
  local sx1 = x1 - 1.0
  local sy0 = y0 + pad
  local sy1 = y1 - pad
  if sx1 <= sx0 + 2.0 then
    return sx0, sy0, sx1, sy1
  end
  local no_hits = seq_vary_filter_has_no_hits(text)
  local fill = editing and 0x10261CB8 or (edit_mode and 0x0E1C16A8 or 0x0C181496)
  local wash = editing and 0x8FD98F55 or 0x8FD98F2A
  local outline = editing and 0xB6F0C8FF or 0x8FD98F99
  local outline_w = editing and 1.9 or 1.4
  if hovered and not editing then
    fill = 0x163024D0
    wash = 0x8FD98F48
    outline = 0xC8F8D8FF
    outline_w = 2.0
  end
  if no_hits then
    fill = editing and 0x2A1810C8 or (hovered and 0x241610D0 or 0x1C141096)
    wash = editing and 0xE8A02055 or 0xE8A02030
    outline = editing and 0xF0B848FF or (hovered and 0xF0C060FF or 0xE8A020CC)
    outline_w = editing and 2.0 or 1.6
  end
  r.ImGui_DrawList_AddRectFilled(dl, sx0, sy0, sx1, sy1, fill, 5.0)
  r.ImGui_DrawList_AddRectFilled(dl, sx0, sy0, sx1, sy1, wash, 5.0)
  r.ImGui_DrawList_AddRect(dl, sx0, sy0, sx1, sy1, outline, 5.0, 0, outline_w)
  local warn_w = 0.0
  if no_hits then
    local mark = "!"
    local mw = select(1, r.ImGui_CalcTextSize(ctx, mark)) or 6.0
    warn_w = mw + 5.0
    local mx = sx1 - mw - 3.0
    local my = sy0 + 1.0
    r.ImGui_DrawList_AddText(dl, mx + 1, my + 1, 0x00000099, mark)
    r.ImGui_DrawList_AddText(dl, mx, my, 0xFFD080FF, mark)
  end
  if text and text ~= "" and not editing then
    local label = text
    local tw, th = r.ImGui_CalcTextSize(ctx, label)
    local max_w = (sx1 - sx0) - 8.0 - warn_w
    if tw > max_w and max_w > 12.0 then
      while #label > 1 and tw > max_w do
        label = label:sub(1, #label - 1)
        tw = select(1, r.ImGui_CalcTextSize(ctx, label .. "…")) or tw
      end
      label = label .. "…"
      tw = select(1, r.ImGui_CalcTextSize(ctx, label)) or tw
    end
    if tw <= (sx1 - sx0) - 4.0 - warn_w then
      local tx = sx0 + 4.0
      local ty = sy0 + 2.0
      r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x00000099, label)
      r.ImGui_DrawList_AddText(dl, tx, ty, no_hits and 0xFFE8C0FF or 0xE8FFEEFF, label)
    end
  end
  return sx0, sy0, sx1, sy1
end

function draw_seq_vary_filter_spans(dl, ctx, slot, row_y0, row_y1, start_qn, step_qn, step_count, col_x0, col_x1, timeline_x0, timeline_x1, edit_mode, hover_col)
  local edit = state.seq_vary_filter_edit
  if edit and slot and tostring(edit.track_id) == tostring(slot.id) then
    edit.x0, edit.y0, edit.x1, edit.y1 = nil, nil, nil, nil
  end
  local run_start, run_key, run_text, run_editing = nil, nil, nil, false
  local function flush(run_end)
    if not run_start then
      return
    end
    local x0 = math.max(timeline_x0, col_x0(run_start))
    local x1 = math.min(timeline_x1, col_x1(run_end))
    if x1 > x0 + 1.0 then
      local hovered = hover_col ~= nil and hover_col >= run_start and hover_col <= run_end
      local sx0, sy0, sx1, sy1 = draw_seq_vary_filter_span(
        dl, ctx, x0, row_y0, x1, row_y1, run_text, edit_mode, hovered, run_editing
      )
      if hovered and not run_editing and seq_vary_filter_has_no_hits(run_text)
          and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "No samples match this filter")
      end
      local edit = state.seq_vary_filter_edit
      if run_editing and edit and tostring(edit.track_id) == tostring(slot.id) then
        edit.x0, edit.y0, edit.x1, edit.y1 = sx0, sy0, sx1, sy1
      end
    end
    run_start, run_key, run_text, run_editing = nil, nil, nil, false
  end
  for col = 0, step_count - 1 do
    local key, editing, text = seq_vary_filter_cell_key(slot, col, start_qn, step_qn)
    if key then
      if run_start and key ~= run_key then
        flush(col - 1)
      end
      if not run_start then
        run_start = col
        run_key = key
        run_text = text
        run_editing = editing
      end
    else
      flush(col - 1)
    end
  end
  flush(step_count - 1)
end

function render_seq_vary_filter_input()
  local edit = state.seq_vary_filter_edit
  if not edit or not ctx then
    return
  end
  if state.seq_param_drag and state.seq_param_drag.param == "vary_filter" then
    return
  end
  if type(edit.x0) ~= "number" or type(edit.x1) ~= "number" then
    return
  end
  local x0, y0 = edit.x0, edit.y0 or 0
  local min_w = 108.0
  local w = math.max(min_w, math.min(220.0, (edit.x1 - x0)))
  if r.ImGui_SetNextFrameWantCaptureKeyboard then
    r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
  end
  local restore_x, restore_y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x0, y0 - 1.0)
  r.ImGui_SetNextItemWidth(ctx, w)
  local first_focus = edit.focus
  if first_focus and r.ImGui_SetKeyboardFocusHere then
    r.ImGui_SetKeyboardFocusHere(ctx)
    edit.focus = false
  end
  local flags = 0
  if r.ImGui_InputTextFlags_EnterReturnsTrue then
    flags = flags | r.ImGui_InputTextFlags_EnterReturnsTrue()
  end
  if first_focus and r.ImGui_InputTextFlags_AutoSelectAll and edit.orig and edit.orig ~= "" then
    flags = flags | r.ImGui_InputTextFlags_AutoSelectAll()
  end
  local no_hits = seq_vary_filter_has_no_hits(edit.text)
  local style_cols, style_vars = 0, 0
  if r.ImGui_Col_FrameBg then
    if no_hits then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x2A1810EE)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x321C12EE)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x3A2216EE)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFE8C0FF)
    else
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x10261CEE)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x163024EE)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x1C3A2CEE)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE8FFEEFF)
    end
    style_cols = 4
    if r.ImGui_Col_Border then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), no_hits and 0xE8A020FF or 0x8FD98F99)
      style_cols = style_cols + 1
    end
  end
  if r.ImGui_StyleVar_FramePadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 1)
    style_vars = style_vars + 1
  end
  if no_hits and r.ImGui_StyleVar_FrameBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 1.0)
    style_vars = style_vars + 1
  end
  local submitted, txt
  if r.ImGui_InputTextWithHint then
    submitted, txt = r.ImGui_InputTextWithHint(ctx, "##seq_vary_filter", "type to filter", edit.text or "", flags)
  else
    submitted, txt = r.ImGui_InputText(ctx, "##seq_vary_filter", edit.text or "", flags)
  end
  seq_mark_text_input_item()
  edit.hovered = r.ImGui_IsItemHovered(ctx) and true or false
  if type(txt) == "string" then
    edit.text = txt
    no_hits = seq_vary_filter_has_no_hits(edit.text)
  end
  if no_hits then
    local ix0, iy0 = r.ImGui_GetItemRectMin(ctx)
    local ix1, iy1 = r.ImGui_GetItemRectMax(ctx)
    local idl = r.ImGui_GetWindowDrawList(ctx)
    if idl then
      r.ImGui_DrawList_AddText(idl, ix1 - 11, iy0 + 1, 0xFFD080FF, "!")
    end
    if edit.hovered and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "No samples match this filter")
    end
  end
  if style_vars > 0 then
    r.ImGui_PopStyleVar(ctx, style_vars)
  end
  if style_cols > 0 then
    r.ImGui_PopStyleColor(ctx, style_cols)
  end
  local escape = r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
    and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
  local enter = submitted or (r.ImGui_IsKeyPressed and r.ImGui_Key_Enter
    and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false))
  if escape then
    seq_cancel_vary_filter_edit()
  elseif enter then
    seq_commit_vary_filter_edit()
  end
  r.ImGui_SetCursorScreenPos(ctx, restore_x, restore_y)
  r.ImGui_Dummy(ctx, 0, 0)
end

function draw_seq_note_param_mode_overlay(dl, ctx, def, value, cx0, cx1, y0, y1, step_qn, accent, selected)
  if not def then
    return
  end
  local lane_top = y0 + 2
  local lane_bot = y1 - 2
  if seq_is_span_overlay_def(def) then
    return
  end
  if def.key == "stutter" then
    if value == nil then
      value = def.default
    end
    draw_seq_stutter_lane_cell(dl, ctx, cx0, cx1, lane_top, lane_bot, value, accent)
    return
  end
  draw_seq_param_value_bar(dl, cx0, cx1, lane_top, lane_bot, def, value, step_qn, accent, selected)
end

function seq_edit_mode_accent(param_key)
  if not param_key then
    return UI_THEME.accent
  end
  local style = get_seq_row_lane_style({ type = "param", param = { key = param_key } })
  return (style and style.accent) or UI_THEME.accent
end

function seq_note_edit_mode_tooltip(def)
  if not def then
    return string.format(
      "Paint and erase notes (%s)\nAlt+LMB drag = stutter (horizontal = length, vertical = count)\nDrag the stutter number = hits (vertical) or skew (horizontal)\nCtrl/Cmd+LMB drag on a note = copy (keeps sample, including region variation)\nShift+empty grid = place off-grid (click inserts at the pointer)\nShift+LMB drag on a note = move off-grid\nDrag the border between tracks to set individual heights\n%s = enlarge hovered track (again to restore)\nAlt+RMB drag = razor edit\nAlt+Ctrl+RMB drag = add razor area\nLMB drag on razor = move notes\nCtrl/Cmd+LMB drag on razor = copy notes",
      shortcut_display("cancel"),
      shortcut_display("enlarge_track")
    )
  end
  local hotkey = (def.shortcut_id and shortcut_display(def.shortcut_id)) or def.hotkey or ""
  if seq_is_decay_def(def) then
    return "Decay mode (" .. hotkey .. ")\nDrag the last grid / end line to set note length (Shift = unsnap)\nDrag start/end circles for fade length (vertical = fade type)\nDrag the fade curve to change native curvature\nDragging a fade past the other fade pushes it out of the way\nRMB on a handle = reset"
  end
  if seq_is_stutter_def(def) then
    return "Stutter mode (" .. hotkey .. ")\nDrag vertically to change hit count (no click-to-jump)\nDrag horizontally to skew timing\nThe first move locks the axis\nRMB = reset count and skew"
  end
  if seq_is_lock_def(def) then
    return "Lock mode (" .. hotkey .. ")\nClick a note or empty cell to lock it\nDrag to lock a range of notes and empty grids\nRMB click a lock = unlock the whole area\nRMB drag = unlock only the cells you sweep"
  end
  if seq_is_vary_def(def) then
    return "Variation mode (" .. hotkey .. ")\nLMB drag on notes = set how far the sample can wander on the map\nOn stutter notes, each slice can be edited separately\nRMB drag on notes = reset to the track sample\n" .. shortcut_display("pick_note_sample") .. " = open the mini map and click a sample to swap the hovered note\nWith a razor, that swap applies to every note inside it"
  end
  if seq_is_vary_filter_def(def) then
    return "Vary filter mode (" .. hotkey .. ")\nClick or drag a grid area, type a word (lofi, robot…), then Enter\nVariation on those grids prefers matching filenames and tags\nRMB click a filter = clear the whole area\nRMB drag = clear only the cells you sweep"
  end
  return string.format(
    "%s mode (%s)\nLMB drag on notes = set value\nRMB drag on notes = reset to default\nOn stutter notes, each slice can be edited separately",
    def.mode_name or def.label, hotkey
  )
end

SEQ_SEG_ICON_W = 16
SEQ_SEG_SEP_W = 9
SEQ_SEG_LEAD_W = 22

-- Per-cell widths. Cells size to their own content (icon + label) unless
-- opts.uniform is set, so long labels don't inflate every cell in the bar.
-- An item with sep_before starts a sub-group: a wider gap with a rule in it.
function seq_segmented_bar_metrics(items, h, opts)
  h = h or 26
  opts = opts or {}
  local rounding = 7.0
  local widths = {}
  local max_w = 0
  for i, it in ipairs(items or {}) do
    local w
    if it.icon_only then
      w = math.max(24, h - 2)
    else
      local tw = select(1, r.ImGui_CalcTextSize(ctx, it.label or "")) or 0
      w = tw + 14 + (it.icon and SEQ_SEG_ICON_W or 0)
      w = math.max(30, math.floor(w + 0.5))
    end
    widths[i] = w
    if w > max_w then max_w = w end
  end
  if opts.uniform then
    for i = 1, #widths do widths[i] = max_w end
  end
  local side = 3
  local total = side * 2 + (opts.lead_icon and SEQ_SEG_LEAD_W or 0)
  for i, it in ipairs(items or {}) do
    total = total + widths[i]
    if it.sep_before and i > 1 then
      total = total + SEQ_SEG_SEP_W
    end
  end
  return total, widths, side, h, rounding
end

function seq_draw_segmented_bar(bar_id, items, h, opts)
  opts = opts or {}
  items = items or {}
  h = h or 26
  local n = #items
  if n == 0 then
    return nil
  end
  local group_w, widths, side, _, rounding = seq_segmented_bar_metrics(items, h, opts)
  if not opts.first then
    imgui_same_line_if_fits(group_w, opts.gap or 8)
  end

  local gx, gy = r.ImGui_GetCursorScreenPos(ctx)
  gx, gy = math.floor(gx + 0.5), math.floor(gy + 0.5)
  local x1, y1 = gx + group_w, gy + h
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local inner_y0 = gy + 2
  local inner_y1 = y1 - 2

  r.ImGui_DrawList_AddRectFilled(dl, gx, gy, x1, y1, 0x0B0F0CFF, rounding)
  r.ImGui_DrawList_AddRectFilled(dl, gx + 1, gy + 1, x1 - 1, y1 - 1, 0x141A16FF, rounding - 1)
  r.ImGui_DrawList_AddLine(dl, gx + rounding, gy + 1.2, x1 - rounding, gy + 1.2, 0x00000077, 1.0)
  r.ImGui_DrawList_AddLine(dl, gx + rounding, y1 - 1.6, x1 - rounding, y1 - 1.6, 0xFFFFFF0C, 1.0)
  r.ImGui_DrawList_AddRect(dl, gx + 0.5, gy + 0.5, x1 - 0.5, y1 - 0.5, UI_THEME.border, rounding, 0, 1.0)

  local clicked_item = nil
  local sx0 = gx + side
  if opts.lead_icon then
    -- Non-interactive caption glyph naming what the bar controls.
    ui_button_draw_icon(dl, opts.lead_icon, sx0 + SEQ_SEG_LEAD_W * 0.5, gy + h * 0.5, math.min(h, 24), UI_THEME.text_mute)
    sx0 = sx0 + SEQ_SEG_LEAD_W
  end
  for i, it in ipairs(items) do
    if it.sep_before and i > 1 then
      local lx = sx0 + SEQ_SEG_SEP_W * 0.5
      r.ImGui_DrawList_AddLine(dl, lx, inner_y0 + 4, lx, inner_y1 - 4, UI_THEME.border_hvr, 1.0)
      sx0 = sx0 + SEQ_SEG_SEP_W
    end
    local cell_w = widths[i]
    local sx1 = sx0 + cell_w
    r.ImGui_SetCursorScreenPos(ctx, sx0, inner_y0)
    r.ImGui_InvisibleButton(ctx, "##" .. tostring(bar_id) .. "_" .. tostring(it.id), cell_w, inner_y1 - inner_y0)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local pressed = r.ImGui_IsItemActive(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local pill_round = 5.0
    local accent = it.accent or UI_THEME.accent
    local cr, cg, cb = extract_rgb_rrgbbaa(accent)
    local function tone(t, a)
      return build_color_rrgbbaa(
        math.max(0, math.min(255, math.floor(cr * t))),
        math.max(0, math.min(255, math.floor(cg * t))),
        math.max(0, math.min(255, math.floor(cb * t))),
        a or 255
      )
    end

    if it.selected then
      local fill = build_color_rrgbbaa(
        math.max(0, math.min(255, math.floor(18 + cr * 0.16))),
        math.max(0, math.min(255, math.floor(22 + cg * 0.20))),
        math.max(0, math.min(255, math.floor(18 + cb * 0.16))),
        255
      )
      r.ImGui_DrawList_AddRectFilled(dl, sx0 + 2, inner_y0 + 1, sx1 - 2, inner_y1 - 1, fill, pill_round)
      r.ImGui_DrawList_AddLine(dl, sx0 + 6, inner_y0 + 2.2, sx1 - 6, inner_y0 + 2.2, 0xFFFFFF2A, 1.0)
      r.ImGui_DrawList_AddRect(dl, sx0 + 2.5, inner_y0 + 1.5, sx1 - 2.5, inner_y1 - 1.5, tone(0.85, 150), pill_round, 0, 1.0)
      local dash_w = math.min(12.0, cell_w * 0.34)
      local dash_x = sx0 + (cell_w - dash_w) * 0.5
      r.ImGui_DrawList_AddRectFilled(dl, dash_x, inner_y1 - 3.4, dash_x + dash_w, inner_y1 - 2.0, accent, 1.2)
    elseif pressed then
      r.ImGui_DrawList_AddRectFilled(dl, sx0 + 2, inner_y0 + 1, sx1 - 2, inner_y1 - 1, 0xFFFFFF12, pill_round)
    elseif hovered then
      r.ImGui_DrawList_AddRectFilled(dl, sx0 + 2, inner_y0 + 1, sx1 - 2, inner_y1 - 1, 0xFFFFFF16, pill_round)
    end

    if i < n then
      local nxt = items[i + 1]
      if not it.selected and not (nxt and (nxt.selected or nxt.sep_before)) then
        r.ImGui_DrawList_AddLine(dl, sx1, inner_y0 + 5, sx1, inner_y1 - 5, 0xFFFFFF14, 1.0)
      end
    end

    local press = (pressed and not it.selected) and 1.0 or 0.0
    local text_col = it.selected and 0xF7FFF9FF or (hovered and UI_THEME.text or UI_THEME.text_dim)
    local mid_y = inner_y0 + (inner_y1 - inner_y0) * 0.5 + press
    -- Selected icons take the cell's accent so the active mode reads at a glance.
    local icon_col = it.selected and accent or text_col
    if it.icon_only then
      ui_button_draw_icon(dl, it.icon, sx0 + cell_w * 0.5, mid_y, h, icon_col)
    else
      local label = it.label or ""
      local tw, th = r.ImGui_CalcTextSize(ctx, label)
      local icon_w = it.icon and SEQ_SEG_ICON_W or 0
      local content_x = sx0 + (cell_w - tw - icon_w) * 0.5
      if it.icon then
        ui_button_draw_icon(dl, it.icon, content_x + icon_w * 0.5 - 1, mid_y, math.min(h, 24), icon_col)
      end
      r.ImGui_DrawList_AddText(dl, content_x + icon_w, mid_y - th * 0.5, text_col, label)
    end

    if hovered and it.tooltip then
      r.ImGui_SetTooltip(ctx, it.tooltip)
    end
    if clicked then
      clicked_item = it
    end
    sx0 = sx1
  end

  r.ImGui_SetCursorScreenPos(ctx, gx + group_w, gy)
  r.ImGui_Dummy(ctx, 1, h)
  return clicked_item
end

function seq_draw_razor_badge(btn_h)
  local count = state.seq_razors and #state.seq_razors or 0
  if state.seq_razor_drag and state.seq_razor_drag.mode ~= "move" then
    count = count + 1
  end
  local label = string.format("Razor ×%d", count)
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  local pad_x, pad_y = 8.0, 3.0
  local w = tw + pad_x * 2
  local h = math.min(btn_h or 26, th + pad_y * 2)
  if not imgui_same_line_if_fits(w, 8) then
    return
  end
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, cx, cy + ((btn_h or 26) - h) * 0.5)
  r.ImGui_InvisibleButton(ctx, "##seq_razor_badge", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x0, iy0 = r.ImGui_GetItemRectMin(ctx)
  local x1, iy1 = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local fill = hovered and 0x1A3A44FF or 0x122830FF
  r.ImGui_DrawList_AddRectFilled(dl, x0, iy0, x1, iy1, fill, 6.0)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, iy0 + 0.5, x1 - 0.5, iy1 - 0.5, SEQ_RAZOR_EDGE, 6.0, 0, 1.2)
  r.ImGui_DrawList_AddText(dl, x0 + pad_x, iy0 + (h - th) * 0.5, SEQ_RAZOR_EDGE, label)
  if hovered then
    r.ImGui_SetTooltip(ctx, string.format(
      "LMB move  ·  Ctrl/Cmd+LMB copy  ·  %s erase  ·  %s clear  ·  %s pick sample",
      shortcut_display("delete_razor"),
      shortcut_display("cancel"),
      shortcut_display("pick_note_sample")
    ))
  end
end

-- Toolbar order for the note edit modes, in sub-groups: level/placement,
-- sample playback, rhythm, sample choice, protection. Modes missing here are
-- appended at the end so new lanes still show up.
SEQ_EDIT_MODE_GROUPS = {
  { "volume", "pan", "pitch" },
  { "start", "stretch", "decay" },
  { "stutter" },
  { "sample_vary", "vary_filter" },
  { "locked" },
}
SEQ_EDIT_MODE_ICONS = {
  volume = "gain",
  pan = "pan",
  pitch = "pitch",
  start = "start",
  stretch = "stretch",
  decay = "decay",
  stutter = "stutter",
  sample_vary = "vary",
  vary_filter = "filter",
  locked = "lock",
}

function render_seq_note_edit_mode_bar(btn_h)
  btn_h = btn_h or 26
  local active_def = get_seq_note_edit_mode_def()
  local items = {
    {
      id = "notes",
      label = "Notes",
      icon = "note",
      icon_only = active_def ~= nil,
      selected = not active_def,
      accent = seq_edit_mode_accent(nil),
      tooltip = seq_note_edit_mode_tooltip(nil),
    },
  }
  local by_key, placed = {}, {}
  for _, def in ipairs(seq_note_edit_mode_defs()) do
    by_key[def.key] = def
  end
  local function add(def, sep_before)
    placed[def.key] = true
    local selected = active_def and active_def.key == def.key
    local icon = SEQ_EDIT_MODE_ICONS[def.key]
    items[#items + 1] = {
      id = def.key,
      key = def.key,
      label = def.label,
      icon = icon,
      -- Only the active mode spells out its name; the rest stay icon-only
      -- (name + hotkey in the tooltip) so the bar stays compact.
      icon_only = icon ~= nil and not selected,
      sep_before = sep_before,
      selected = selected,
      accent = seq_edit_mode_accent(def.key),
      tooltip = seq_note_edit_mode_tooltip(def),
    }
  end
  for _, group in ipairs(SEQ_EDIT_MODE_GROUPS) do
    local first = true
    for _, key in ipairs(group) do
      if by_key[key] then
        add(by_key[key], first)
        first = false
      end
    end
  end
  local first_extra = true
  for _, def in ipairs(seq_note_edit_mode_defs()) do
    if not placed[def.key] then
      add(def, first_extra)
      first_extra = false
    end
  end
  local clicked = seq_draw_segmented_bar("seq_edit_mode", items, btn_h, { gap = 6 })
  if clicked then
    if clicked.key then
      seq_toggle_note_edit_mode(clicked.key)
    else
      seq_set_note_edit_mode(nil)
    end
  end
  if seq_has_razors() or state.seq_razor_drag then
    seq_draw_razor_badge(btn_h)
  end
end

function render_seq_top_toolbar()
  local btn_h = UI_METRICS.toolbar_h
  local inner_h = btn_h - 6
  local pocket_pad = 4
  local inner_gap = 3

  local function toolbar_button(id, label, opts, tooltip)
    opts = opts or {}
    opts.compact = true
    local clicked = draw_ui_button(id, label, nil, btn_h, opts)
    if tooltip and r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, tooltip)
    end
    return clicked
  end

  local function toolbar_divider()
    if not imgui_same_line_if_fits(7, 8) then
      return
    end
    local x, y0 = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_Dummy(ctx, 1, btn_h)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddLine(dl, x, y0 + 5, x, y0 + btn_h - 5, UI_THEME.border, 1.0)
  end

  -- Layout, left to right:
  --   [region | pattern | groove] [kit]  |  [grid | T]  |  [edit modes] [razor]  ...  [sync peek]
  -- Content (what plays) first, then editing, with view toggles pinned right.
  local focus_region = get_selected_seq_region()
  if state.seq_region_rename and focus_region and state.seq_region_rename.region_id ~= focus_region.id then
    seq_commit_region_rename()
  end
  local renaming = state.seq_region_rename
    and focus_region
    and state.seq_region_rename.region_id == focus_region.id
  local region_name = get_seq_region_display_name(focus_region)
  local region_chip = seq_truncate_text_to_width(region_name, 96)
  state.seq_gen_style = normalize_seq_gen_style(state.seq_gen_style)
  local pattern_label = get_seq_region_pattern_label(focus_region)
  local groove_key = get_seq_region_groove(focus_region)
  local groove_active = groove_key ~= "off"
  local groove_label = get_seq_groove_chip_label(groove_key)
  local drop_beacon = seq_stem_import_file_drag_active()
  state.seq_stem_import_hover = false
  local pat_btn_label = drop_beacon and (SEQ_STEM_IMPORT_DROP_LABEL or "Drop here to dissect drum pattern") or pattern_label
  local name_w = calc_compact_chip_width(region_chip) + 6
  if renaming then
    local typed = state.seq_region_rename.text or ""
    local measure = typed ~= "" and typed or "Intro 1"
    local tw = select(1, r.ImGui_CalcTextSize(ctx, measure)) or 0
    name_w = math.max(150, tw + 28)
  end
  local pat_w = calc_compact_chip_width(pat_btn_label) + 16
  local grv_w = calc_compact_chip_width(groove_label) + 16
  local pocket_w = pocket_pad + pat_w + inner_gap + grv_w + pocket_pad
  local group_w = name_w + pocket_w
  do
    local gx, gy = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local pool = seq_region_pool_color(focus_region and focus_region.pool_id, 255)
    local cr, cg, cb = extract_rgb_rrgbbaa(pool)
    local function tone(t, a)
      return build_color_rrgbbaa(
        math.max(0, math.min(255, math.floor(cr * t))),
        math.max(0, math.min(255, math.floor(cg * t))),
        math.max(0, math.min(255, math.floor(cb * t))),
        a or 255
      )
    end
    local rounding = 8.0
    r.ImGui_DrawList_AddRectFilled(dl, gx, gy, gx + group_w, gy + btn_h, tone(0.16), rounding)
    r.ImGui_DrawList_AddRectFilled(dl, gx, gy, gx + name_w + rounding, gy + btn_h, tone(0.38), rounding)
    r.ImGui_DrawList_AddRectFilled(dl, gx + name_w, gy, gx + name_w + rounding, gy + btn_h, tone(0.16), 0)
    r.ImGui_DrawList_AddRect(dl, gx + 0.5, gy + 0.5, gx + group_w - 0.5, gy + btn_h - 0.5, tone(0.95), rounding, 0, 1.6)
    r.ImGui_DrawList_AddLine(dl, gx + name_w, gy + 4, gx + name_w, gy + btn_h - 4, tone(0.75, 180), 1.0)

    if renaming then
      if r.ImGui_SetNextFrameWantCaptureKeyboard then
        r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
      end
      r.ImGui_SetCursorScreenPos(ctx, gx + 4, gy + 2)
      r.ImGui_SetNextItemWidth(ctx, name_w - 8)
      local first_focus = state.seq_region_rename.focus
      if first_focus then
        if r.ImGui_SetKeyboardFocusHere then
          r.ImGui_SetKeyboardFocusHere(ctx)
        end
        state.seq_region_rename.focus = false
      end
      local input_flags = 0
      if first_focus and r.ImGui_InputTextFlags_AutoSelectAll then
        input_flags = input_flags | r.ImGui_InputTextFlags_AutoSelectAll()
      end
      local input_value = state.seq_region_rename.typed_prefix
      if input_value == nil then
        input_value = state.seq_region_rename.text or ""
      end
      local completing = state.seq_region_rename.completed == true
      local style_cols, style_vars = 0, 0
      if r.ImGui_Col_FrameBg then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000066)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x00000088)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x00000099)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), completing and 0xFFFFFF00 or 0xFFFFFFFF)
        style_cols = 4
      end
      if r.ImGui_StyleVar_FramePadding then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
        style_vars = style_vars + 1
      end
      local _, txt = r.ImGui_InputText(ctx, "##seq_region_rename", input_value, input_flags)
      seq_mark_text_input_item()
      local edit_x, edit_y = r.ImGui_GetItemRectMin(ctx)
      local edit_x1, edit_y1 = r.ImGui_GetItemRectMax(ctx)
      local edit_hovered = r.ImGui_IsItemHovered(ctx)
      if style_vars > 0 then
        r.ImGui_PopStyleVar(ctx, style_vars)
      end
      if style_cols > 0 then
        r.ImGui_PopStyleColor(ctx, style_cols)
      end
      local arrow_down = r.ImGui_IsKeyPressed and r.ImGui_Key_DownArrow
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow(), false)
      local arrow_up = r.ImGui_IsKeyPressed and r.ImGui_Key_UpArrow
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow(), false)
      if arrow_down or arrow_up then
        seq_region_rename_move_candidate(state.seq_region_rename, focus_region, arrow_down and 1 or -1)
      elseif type(txt) == "string" then
        if first_focus and txt == (state.seq_region_rename.orig or "") then
          state.seq_region_rename.text = txt
        else
          seq_apply_region_rename_autocomplete(state.seq_region_rename, txt, focus_region)
        end
      end
      if state.seq_region_rename and state.seq_region_rename.completed then
        seq_draw_region_rename_completion(state.seq_region_rename, edit_x, edit_y, edit_x1, edit_y1)
        if r.ImGui_IsKeyPressed and r.ImGui_Key_Tab
            and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Tab(), false) then
          state.seq_region_rename.typed_prefix = state.seq_region_rename.text
          state.seq_region_rename.completed = false
          state.seq_region_rename.select_from = 0
        end
      end
      local edit_w = (edit_x1 or (gx + name_w)) - (edit_x or gx)
      local enter = r.ImGui_IsKeyPressed and r.ImGui_Key_Enter
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false)
      local escape = r.ImGui_IsKeyPressed and r.ImGui_Key_Escape
        and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false)
      local click_outside = r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
        and not edit_hovered
        and not (state.seq_region_rename and state.seq_region_rename.over_suggest)
      if escape then
        seq_cancel_region_rename()
      elseif enter then
        seq_commit_region_rename()
      elseif click_outside then
        seq_commit_region_rename()
      end
      if state.seq_region_rename then
        render_seq_region_name_suggest_popup(edit_x or gx, edit_y or gy, edit_w)
      end
    else
      r.ImGui_InvisibleButton(ctx, "##ui_seq_focus_region_chip", name_w, btn_h)
      local cap_hovered = r.ImGui_IsItemHovered(ctx)
      local cap_clicked = r.ImGui_IsItemClicked(ctx, 0)
      local cap_dbl = cap_hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
      if cap_hovered then
        r.ImGui_DrawList_AddRectFilled(dl, gx, gy, gx + name_w + rounding, gy + btn_h, tone(0.50, 70), rounding)
        r.ImGui_SetTooltip(ctx, "Focused region — pattern and groove apply here only.\nClick to zoom. Double-click to rename.")
      end
      local tw, th = r.ImGui_CalcTextSize(ctx, region_chip)
      r.ImGui_DrawList_AddText(dl, gx + (name_w - tw) * 0.5, gy + (btn_h - th) * 0.5, 0xFFFFFFFF, region_chip)
      if cap_dbl then
        seq_begin_region_rename(focus_region)
      elseif cap_clicked then
        seq_zoom_to_region(focus_region)
      end
    end

    local inner_y = gy + (btn_h - inner_h) * 0.5
    r.ImGui_SetCursorScreenPos(ctx, gx + name_w + pocket_pad, inner_y)
    if draw_ui_button("seq_pattern_popup_open", pat_btn_label, nil, inner_h, {
      compact = true,
      lead_icon = "steps",
      style = drop_beacon and "accent" or "primary",
      selected = drop_beacon or state.seq_pattern_window_open,
    }) then
      if not drop_beacon then
        open_seq_pattern_popup()
      end
    end
    seq_stem_import_accept_file_drop()
    if r.ImGui_IsItemHovered(ctx) then
      if drop_beacon then
        r.ImGui_SetTooltip(ctx, "Drop an audio file to dissect its drum pattern")
      else
        r.ImGui_SetTooltip(ctx, "Pattern for " .. region_name)
      end
    end
    r.ImGui_SameLine(ctx, 0, inner_gap)
    if draw_ui_button("seq_groove_popup_open", groove_label, nil, inner_h, {
      compact = true,
      lead_icon = "groove",
      style = "primary",
      selected = groove_active,
    }) then
      r.ImGui_OpenPopup(ctx, "seq_groove_popup")
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Groove for " .. region_name .. " — this region only")
    end

    r.ImGui_SetCursorScreenPos(ctx, gx + group_w, gy)
    r.ImGui_Dummy(ctx, 1, btn_h)
  end
  render_seq_groove_popup()

  imgui_same_line_if_fits(calc_compact_chip_width("Kit") + 16, 6)
  if toolbar_button("seq_kit_random_popup_open", "Kit", { style = "primary", lead_icon = "dice5" }, "Randomize Kit") then
    open_seq_kit_random_popup()
  end
  render_seq_kit_random_popup()

  toolbar_divider()
  render_seq_grid_bar(btn_h)

  toolbar_divider()
  render_seq_note_edit_mode_bar(btn_h)

  render_seq_view_toggles(btn_h)
end

-- Grid: straight values plus a triplet toggle, so 1/4T and 1/32T are reachable
-- without doubling the number of cells.
SEQ_GRID_STRAIGHT = {
  { "1/4", 1.0 },
  { "1/8", 0.5 },
  { "1/16", 0.25 },
  { "1/32", 0.125 },
}

function seq_grid_split(qn)
  qn = qn or 0.25
  for _, g in ipairs(SEQ_GRID_STRAIGHT) do
    if math.abs(qn - g[2]) < 0.0001 then
      return g[2], false
    end
    if math.abs(qn - g[2] * 2.0 / 3.0) < 0.0001 then
      return g[2], true
    end
  end
  return nil, false
end

function render_seq_grid_bar(btn_h)
  local base, triplet = seq_grid_split(state.seq_grid_qn)
  local items = {}
  for _, g in ipairs(SEQ_GRID_STRAIGHT) do
    items[#items + 1] = {
      id = "seq_grid_" .. g[1],
      label = g[1],
      qn = g[2],
      selected = base ~= nil and math.abs(base - g[2]) < 0.0001,
      accent = UI_THEME.accent,
      tooltip = "Grid " .. g[1] .. (triplet and " triplet" or ""),
    }
  end
  items[#items + 1] = {
    id = "seq_grid_triplet",
    label = "T",
    triplet_toggle = true,
    sep_before = true,
    selected = triplet,
    accent = 0xFFC861FF,
    tooltip = triplet and "Triplet grid on (click for straight)" or "Triplet grid",
  }
  local clicked = seq_draw_segmented_bar("seq_grid", items, btn_h, { gap = 6, lead_icon = "grid" })
  if clicked then
    local cur_base = base or 0.25
    if clicked.triplet_toggle then
      state.seq_grid_qn = triplet and cur_base or (cur_base * 2.0 / 3.0)
    else
      state.seq_grid_qn = triplet and (clicked.qn * 2.0 / 3.0) or clicked.qn
    end
    save_config()
  end
end

-- View toggles sit at the right edge when the row has room for them.
function render_seq_view_toggles(btn_h)
  local sync_on = state.seq_follow_arrange == true
  local peek_on = state.seq_follow_hovered_item == true
  local items = {
    {
      id = "sync",
      label = "Sync",
      icon = "link",
      icon_only = true,
      selected = sync_on,
      accent = UI_THEME.accent,
      tooltip = sync_on and "Sync to Arrange: on\nThe sequencer view follows the arrange view." or "Sync to Arrange: off\nClick to make the sequencer view follow the arrange view.",
    },
    {
      id = "peek",
      label = "Peek",
      icon = "eye",
      icon_only = true,
      selected = peek_on,
      accent = UI_THEME.accent,
      tooltip = peek_on and "Peek: on\nFollows the notes you hover in the arrange." or "Peek: off\nClick to follow the notes you hover in the arrange.",
    },
  }
  local w = seq_segmented_bar_metrics(items, btn_h)
  local right = imgui_window_right_x()
  local last_x2 = r.ImGui_GetItemRectMax(ctx)
  if last_x2 + 16 + w <= right then
    r.ImGui_SameLine(ctx, 0, 0)
    local _, cy = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_SetCursorScreenPos(ctx, right - w, cy)
  end
  local clicked = seq_draw_segmented_bar("seq_view", items, btn_h, { first = true })
  if not clicked then
    return
  end
  if clicked.id == "sync" then
    state.seq_follow_arrange = not sync_on
    seq_timeline_scroll_stop()
    if state.seq_follow_arrange then
      local arrange_start, arrange_end = get_arrange_view_range()
      local arrange_start_qn = time_to_qn(arrange_start) or 0.0
      local arrange_end_qn = time_to_qn(arrange_end) or (arrange_start_qn + (state.seq_grid_qn or 0.25) * 16.0)
      state.seq_view_start_qn = arrange_start_qn
      state.seq_view_span_qn = math.max(state.seq_grid_qn or 0.25, arrange_end_qn - arrange_start_qn)
    end
  else
    state.seq_follow_hovered_item = not peek_on
  end
  save_config()
end

function seq_param_value_from_y(def, y, y0, y1, step_qn)
  if def.boolean or seq_is_lock_def(def) then
    return def.max or 1.0
  end
  local t = 1.0 - ((y - y0) / math.max(1.0, y1 - y0))
  t = math.max(0.0, math.min(1.0, t))
  local min_v = def.min
  local max_v = def.max
  if def.key == "length_qn" then
    min_v = math.min(step_qn or state.seq_grid_qn or 0.25, def.min)
    max_v = math.max(step_qn or state.seq_grid_qn or 0.25, def.max)
  elseif def.key == "stretch" then
    -- Log scale so 1.0x sits in the middle (0.25x .. 4.0x).
    return SEQ_STRETCH_MIN * ((SEQ_STRETCH_MAX / SEQ_STRETCH_MIN) ^ t)
  end
  return min_v + (max_v - min_v) * t
end

function seq_param_y_from_value(def, value, y0, y1, step_qn)
  local min_v = def.min
  local max_v = def.max
  if def.key == "length_qn" then
    min_v = math.min(step_qn or state.seq_grid_qn or 0.25, def.min)
    max_v = math.max(step_qn or state.seq_grid_qn or 0.25, def.max)
  elseif def.key == "stretch" then
    local v = tonumber(value) or 1.0
    if v < SEQ_STRETCH_MIN then v = SEQ_STRETCH_MIN end
    if v > SEQ_STRETCH_MAX then v = SEQ_STRETCH_MAX end
    local t = math.log(v / SEQ_STRETCH_MIN) / math.log(SEQ_STRETCH_MAX / SEQ_STRETCH_MIN)
    t = math.max(0.0, math.min(1.0, t))
    return y1 - t * (y1 - y0)
  end
  local t = ((value or def.default) - min_v) / math.max(0.000001, max_v - min_v)
  t = math.max(0.0, math.min(1.0, t))
  return y1 - t * (y1 - y0)
end

function seq_get_project_first_measure()
  -- Project Settings → "Project start measure". TimeMap measure 0 is always
  -- the first bar; the displayed number can be 1 (default), 0, -1, etc.
  if r.format_timestr_pos and r.TimeMap_GetMeasureInfo then
    local meas_time, qn_start = r.TimeMap_GetMeasureInfo(0, 0)
    if type(qn_start) == "number" then
      local nudged = qn_to_time(qn_start + 0.0001)
      if type(nudged) == "number" then
        meas_time = nudged
      end
    end
    if type(meas_time) == "number" then
      local formatted = r.format_timestr_pos(meas_time, "", 2)
      local n = tonumber((formatted or ""):match("^%s*(-?%d+)"))
      if n then
        return n
      end
    end
  end
  -- SWS: projmeasoffs is 0 when the first displayed measure is 1.
  if r.SNM_GetIntConfigVarEx then
    return (r.SNM_GetIntConfigVarEx(0, "projmeasoffs", 0) or 0) + 1
  end
  if r.SNM_GetIntConfigVar then
    return (r.SNM_GetIntConfigVar("projmeasoffs", 0) or 0) + 1
  end
  return 1
end

function seq_measure_guide_step(measure_px)
  if not measure_px or measure_px >= 95 then
    return 1
  end
  if measure_px < 12 then
    return 32
  elseif measure_px < 20 then
    return 16
  elseif measure_px < 35 then
    return 8
  elseif measure_px < 60 then
    return 4
  end
  return 2
end

function collect_measure_guides_qn(start_qn, end_qn, max_guides, measure_step)
  local guides = {}
  if not r.TimeMap_GetMeasureInfo or not r.TimeMap2_timeToBeats then
    return guides
  end

  local start_time = qn_to_time(start_qn)
  if not start_time then
    return guides
  end

  max_guides = max_guides or 1024
  measure_step = math.max(1, math.floor(measure_step or 1))
  local _, start_measure = r.TimeMap2_timeToBeats(0, start_time)
  if start_measure == nil then
    return guides
  end

  local first_measure = seq_get_project_first_measure()
  local measure = math.max(0, start_measure)
  if measure_step > 1 then
    measure = math.floor(measure / measure_step) * measure_step
  end
  local guard = 0
  while guard < max_guides do
    local meas_time, qn_start, qn_end, ts_num, ts_den = r.TimeMap_GetMeasureInfo(0, measure)
    if not meas_time or not qn_start then
      break
    end
    if qn_start > end_qn + 0.000001 then
      break
    end

    local out_num = (type(ts_num) == "number" and ts_num > 0) and ts_num or 4
    local out_den = (type(ts_den) == "number" and ts_den > 0) and ts_den or 4
    local out_qn_end = qn_end
    if type(out_qn_end) ~= "number" or out_qn_end <= qn_start then
      out_qn_end = qn_start + out_num * (4.0 / out_den)
    end

    if out_qn_end >= start_qn - 0.000001 then
      guides[#guides + 1] = {
        measure = measure,
        display_measure = measure + first_measure,
        qn_start = qn_start,
        qn_end = out_qn_end,
        time = meas_time,
        ts_num = out_num,
        ts_den = out_den,
      }
    end

    measure = measure + measure_step
    guard = guard + 1
  end

  return guides
end

function find_seq_param_lane_bounds(row_positions, track_id, param_key)
  for _, row_pos in ipairs(row_positions) do
    local row = row_pos.row
    if row.type == "param" and row.slot and row.slot.id == track_id and row.param and row.param.key == param_key then
      return row_pos.y0 + 2, row_pos.y1 - 2, row_pos
    end
  end
  return nil, nil, nil
end

function format_seq_param_value(def, value)
  if value == nil then
    value = def.default
  end
  if def.boolean or seq_is_lock_def(def) then
    local on = value == true or (tonumber(value) or 0) >= 0.5
    return string.format("%s %s", def.label, on and "On" or "Off")
  end
  if def.key == "start" then
    return string.format("%s %.0f%%", def.label, (tonumber(value) or 0.0) * 100.0)
  end
  if def.key == "stretch" then
    return string.format("%s %.2fx", def.label, tonumber(value) or 1.0)
  end
  return string.format("%s %s", def.label, string.format(def.fmt, value))
end

function draw_seq_stutter_count_badge(dl, ctx, x0, y0, x1, y1, count, accent, hover)
  count = seq_clamp_stutter_count(count)
  local text = tostring(count)
  local text_size = { r.ImGui_CalcTextSize(ctx, text) }
  local text_w = text_size[1] or 0
  local text_h = text_size[2] or 0
  local tx = (x0 + x1) * 0.5 - text_w * 0.5
  local ty = (y0 + y1) * 0.5 - text_h * 0.5
  local bx0, by0, bx1, by1 = tx - 3, ty - 1, tx + text_w + 3, ty + text_h + 1
  r.ImGui_DrawList_AddRectFilled(dl, bx0, by0, bx1, by1, hover and 0x000000EE or 0x000000BB, 2.0)
  if hover then
    r.ImGui_DrawList_AddRect(dl, bx0, by0, bx1, by1, seq_lane_color_with_alpha(accent or 0xC9A8FFFF, 255), 2.0, 0, 1.2)
  end
  r.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, 0x000000AA, text)
  r.ImGui_DrawList_AddText(dl, tx, ty, seq_lane_color_with_alpha(accent or 0xC9A8FFFF, 255), text)
  return bx0, by0, bx1, by1
end

function draw_seq_stutter_lane_cell(dl, ctx, cx0, cx1, lane_top, lane_bot, count, accent)
  count = seq_clamp_stutter_count(count)
  local ar, ag, ab = extract_rgb_rrgbbaa(accent or 0xC9A8FFFF)
  local pad_x = 2.0
  local fill_x0 = cx0 + pad_x
  local fill_x1 = cx1 - pad_x
  if fill_x1 <= fill_x0 then
    fill_x1 = fill_x0 + 1.0
  end

  local lane_h = math.max(4.0, lane_bot - lane_top)
  local gap = 1.0
  local draw_n = math.max(1, math.min(count, SEQ_STUTTER_LANE_STACK_MAX))
  local box_h = math.max(2.0, (lane_h - gap * (draw_n - 1)) / draw_n)
  local stack_h = draw_n * box_h + math.max(0, draw_n - 1) * gap
  local stack_y0 = lane_bot - stack_h

  for i = 1, draw_n do
    local by1 = lane_bot - (i - 1) * (box_h + gap)
    local by0 = by1 - box_h
    if by0 < stack_y0 then
      by0 = stack_y0
    end
    local fade = 50 + math.floor((i / draw_n) * 120)
    local edge_fade = math.min(255, fade + 40)
    local fill_col = build_color_rrgbbaa(ar, ag, ab, fade)
    local edge_col = build_color_rrgbbaa(ar, ag, ab, edge_fade)
    r.ImGui_DrawList_AddRectFilled(dl, fill_x0, by0, fill_x1, by1, fill_col, 1.0)
    r.ImGui_DrawList_AddRect(dl, fill_x0, by0, fill_x1, by1, edge_col, 1.0, 0, 1.0)
  end

  draw_seq_stutter_count_badge(dl, ctx, fill_x0, lane_top, fill_x1, lane_bot, count, accent)
end

function seq_param_mouse_col(mx, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, step_qn, step_count)
  local qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  return math.max(0, math.min(step_count - 1, math.floor((qn - start_qn) / step_qn + 1e-9)))
end

function seq_param_value_for_drag(def, value, step_qn)
  if def.key == "length_qn" then
    return snap_seq_length_qn(value, step_qn)
  end
  if def.key == "stutter" then
    return seq_clamp_stutter_count(value)
  end
  if def.key == "stretch" then
    value = tonumber(value) or 1.0
    if value < SEQ_STRETCH_MIN then return SEQ_STRETCH_MIN end
    if value > SEQ_STRETCH_MAX then return SEQ_STRETCH_MAX end
    return value
  end
  if def.key == "start" then
    value = tonumber(value) or 0.0
    if value < 0.0 then return 0.0 end
    if value > SEQ_START_MAX then return SEQ_START_MAX end
    return value
  end
  return value
end

function apply_seq_note_lane_drag(drag, region, step_qn, start_qn, step_count, mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  if not drag or not region then
    return false
  end

  local slot = nil
  for _, track_slot in ipairs(state.seq_tracks) do
    if track_slot.id == drag.track_id then
      slot = track_slot
      break
    end
  end
  if not slot then
    return false
  end

  drag.end_col = seq_param_mouse_col(mx, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, step_qn, step_count)
  local col_min = math.min(drag.start_col, drag.end_col)
  local col_max = math.max(drag.start_col, drag.end_col)
  local prev_min = drag.applied_min or drag.start_col
  local prev_max = drag.applied_max or drag.start_col
  if col_min >= prev_min and col_max <= prev_max then
    return false
  end

  local region_start = region.start_qn or 0.0
  local region_end = region_start + get_seq_region_length_qn(region)
  local changed = false

  local function apply_col(col)
    local qn = start_qn + col * step_qn
    if qn < region_start or qn >= region_end then
      return
    end
    if drag.mode == "erase" then
      if seq_erase_notes_starting_in_span(region, slot, qn, qn + step_qn, {
        defer_save = true,
        defer_arrange = true,
      }) then
        changed = true
      end
      return
    end
    local step_idx = math.floor(((qn - region_start) / step_qn) + 1e-9)
    local step_key = tostring(step_idx)
    if toggle_seq_note(region, slot, step_key, step_idx * step_qn, drag.mode, {
      defer_save = true,
      defer_arrange = true,
    }) then
      changed = true
    end
  end

  -- Highest step first so gap-to-next-hit lengths are correct on first insert.
  if r.PreventUIRefresh then r.PreventUIRefresh(1) end
  if col_min < prev_min then
    for col = prev_min - 1, col_min, -1 do
      apply_col(col)
    end
  end
  if col_max > prev_max then
    for col = col_max, prev_max + 1, -1 do
      apply_col(col)
    end
  end
  if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
  if changed then
    r.UpdateArrange()
  end

  drag.applied_min = col_min
  drag.applied_max = col_max
  return changed
end

function apply_seq_note_copy_drag(drag, step_qn, start_qn, step_count, mx, my, timeline_x0, timeline_w, view_start_qn, qn_span, row_positions)
  if not drag or not drag.src_note then
    return false
  end
  if drag.mode ~= "copy" and drag.mode ~= "move" then
    return false
  end
  step_qn = step_qn or state.seq_grid_qn or 0.25
  local mouse_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  local dest_abs
  if drag.mode == "copy" and drag.snap ~= false then
    dest_abs = math.floor((mouse_qn / step_qn) + 1e-9) * step_qn
  else
    dest_abs = (drag.src_abs_qn or 0.0) + (mouse_qn - (drag.grab_qn or mouse_qn))
    dest_abs = seq_quantize_free_qn(dest_abs)
  end
  if dest_abs < 0 then
    dest_abs = 0
  end
  local dest_track_id = seq_track_id_at_y(row_positions, my) or drag.track_id
  local dest_region = seq_region_at_qn(dest_abs)
  local dest_slot = seq_find_slot_by_id(dest_track_id)

  local function restore()
    if drag.patterns_backup then
      state.seq_patterns = clone_table_deep(drag.patterns_backup)
    end
  end

  local origin_qn = (drag.mode == "copy") and (drag.src_snap_qn or drag.src_abs_qn or 0) or (drag.src_abs_qn or 0)
  local same = dest_region and dest_region.id == drag.region_id
    and dest_track_id == drag.track_id
    and math.abs(dest_abs - origin_qn) < 1e-6

  if not dest_region or not dest_slot or (same and not drag.place_new) then
    if drag.dirty then
      restore()
      drag.dirty = false
      drag.dest_track_id = nil
      drag.dest_region_id = nil
      drag.dest_step_key = nil
    end
    drag.last_dest_qn = dest_abs
    drag.last_dest_track = dest_track_id
    drag.last_dest_region = dest_region and dest_region.id or nil
    return false
  end

  if drag.last_dest_qn == dest_abs and drag.last_dest_track == dest_track_id
     and drag.last_dest_region == dest_region.id then
    return drag.dirty and true or false
  end

  restore()
  local rel = dest_abs - (dest_region.start_qn or 0.0)
  local region_len = get_seq_region_length_qn(dest_region)
  if rel < -1e-9 then
    rel = 0.0
    dest_abs = dest_region.start_qn or 0.0
  elseif rel >= region_len - 1e-9 then
    rel = math.max(0.0, seq_quantize_free_qn(region_len - (1.0 / 192.0)))
    dest_abs = (dest_region.start_qn or 0.0) + rel
  end

  if drag.mode == "move" and not drag.place_new then
    local src_region = get_seq_region_by_id(drag.region_id)
    delete_seq_note(src_region, drag.track_id, drag.src_step_key)
  end

  local note = clone_table_deep(drag.src_note)
  note.qn_offset = rel
  note.step = math.floor((rel / step_qn) + 1e-9)
  seq_keep_copied_note_over_region(note, drag.src_length_qn, dest_region, rel)
  local n_start, n_end = seq_note_qn_range(note, "0", step_qn)
  local span_end = (n_end and n_end > n_start + 1e-9) and n_end or (rel + step_qn)
  local keep_key = nil
  if drag.mode == "copy" and dest_region.id == drag.region_id and dest_track_id == drag.track_id then
    keep_key = drag.src_step_key
  end
  seq_delete_notes_overlapping_span(
    dest_region, dest_slot, rel, span_end, keep_key, step_qn, {
      defer_arrange = true,
      -- Keep later hits; item lengths crop to the next start instead of deleting.
      same_start = true,
    }
  )
  local key = seq_alloc_note_key(dest_region, dest_slot.id, rel)
  set_seq_note(dest_region, dest_slot.id, key, note)
  state.selected_seq_note = { region_id = dest_region.id, track_id = dest_slot.id, step_key = key }
  drag.dest_region_id = dest_region.id
  drag.dest_track_id = dest_slot.id
  drag.dest_step_key = key
  drag.last_dest_qn = dest_abs
  drag.last_dest_track = dest_track_id
  drag.last_dest_region = dest_region.id
  drag.dirty = true
  return true
end

function apply_seq_stutter_lane_drag(drag, region, step_qn, start_qn, step_count, mx, my, timeline_x0, timeline_w, view_start_qn, qn_span)
  if not drag or not region then
    return false
  end
  local slot = seq_find_slot_by_id(drag.track_id)
  if not slot then
    return false
  end

  drag.end_col = seq_param_mouse_col(mx, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, step_qn, step_count)
  local col_min = math.min(drag.start_col, drag.end_col)
  local col_max = math.max(drag.start_col, drag.end_col)
  local region_start = region.start_qn or 0.0
  local region_end = region_start + get_seq_region_length_qn(region)
  local abs_start = start_qn + col_min * step_qn
  local abs_end = start_qn + (col_max + 1) * step_qn
  if abs_start < region_start then abs_start = region_start end
  if abs_end > region_end then abs_end = region_end end
  if abs_end - abs_start < step_qn * 0.5 then
    abs_end = math.min(region_end, abs_start + step_qn)
    if abs_end - abs_start < step_qn * 0.5 then
      abs_start = math.max(region_start, abs_end - step_qn)
    end
  end
  local length_qn = snap_seq_length_qn(abs_end - abs_start, step_qn)
  if length_qn <= 0 then
    return false
  end
  local qn_offset = abs_start - region_start
  if qn_offset < -1e-9 or qn_offset >= (region_end - region_start) - 1e-9 then
    return false
  end
  local count = seq_stutter_count_from_drag_dy(drag.origin_y, my)

  if not drag.step_key then
    local existing_key, existing = seq_find_note_key_at_qn(region, slot.id, qn_offset)
    if existing then
      drag.step_key = existing_key
    else
      local key = seq_alloc_note_key(region, slot.id, qn_offset)
      local note = make_default_seq_note(slot, key, qn_offset)
      if not note then
        log("Sequencer slot has no assigned sample")
        return false
      end
      set_seq_note(region, slot.id, key, note)
      register_seq_note_anim(region.id, slot.id, key, note, "add")
      drag.step_key = key
    end
  end

  local note = get_seq_note(region, slot.id, drag.step_key)
  if not note then
    return false
  end

  local changed = not drag.initialized
  if math.abs((note.qn_offset or 0.0) - qn_offset) > 1e-9 then
    note.qn_offset = qn_offset
    note.step = math.floor((qn_offset / step_qn) + 1e-9)
    changed = true
  end
  if math.abs((note.length_qn or 0.0) - length_qn) > 1e-9 then
    note.length_qn = length_qn
    changed = true
  end
  if note.stutter ~= count then
    note.stutter = count
    seq_prune_stutter_hits(note)
    changed = true
  end

  drag.length_qn = length_qn
  drag.stutter = count
  drag.qn_offset = qn_offset

  if changed then
    seq_delete_notes_overlapping_span(
      region, slot, qn_offset, qn_offset + length_qn, drag.step_key, step_qn, { defer_arrange = true }
    )
    state.selected_seq_note = { region_id = region.id, track_id = slot.id, step_key = drag.step_key }
    drag.initialized = true
    drag.dirty = true
    return true
  end
  return false
end

function seq_begin_stutter_edit_drag(region, slot, step_key, note, mx, my, undo_label)
  if not region or not slot or not note then
    return false
  end
  local label = begin_seq_undo(undo_label or "Edit sequencer stutter")
  state.selected_seq_note = { region_id = region.id, track_id = slot.id, step_key = step_key }
  state.seq_note_drag = {
    mode = "stutter_edit",
    track_id = slot.id,
    region_id = region.id,
    step_key = tostring(step_key),
    origin_x = mx,
    origin_y = my,
    origin_count = seq_stutter_count(note),
    origin_skew = seq_stutter_skew(note),
    stutter = seq_stutter_count(note),
    skew = seq_stutter_skew(note),
    axis = nil,
    undo_label = label,
    undo_open = true,
    dirty = false,
  }
  return true
end

function apply_seq_stutter_edit_drag(drag, region, mx, my)
  if not drag or not region then
    return false
  end
  local note = get_seq_note(region, drag.track_id, drag.step_key)
  if not note then
    return false
  end
  if not drag.axis then
    local dx = (mx or drag.origin_x or 0) - (drag.origin_x or 0)
    local dy = (drag.origin_y or 0) - (my or drag.origin_y or 0)
    if math.abs(dx) < SEQ_STUTTER_AXIS_PX and math.abs(dy) < SEQ_STUTTER_AXIS_PX then
      return false
    end
    drag.axis = (math.abs(dx) > math.abs(dy)) and "skew" or "count"
  end
  local changed = false
  if drag.axis == "count" then
    local count = seq_stutter_count_from_relative_dy(drag.origin_count, drag.origin_y, my)
    if note.stutter ~= count then
      note.stutter = count
      seq_prune_stutter_hits(note)
      changed = true
    end
    drag.stutter = count
  else
    local skew = seq_stutter_skew_from_dx(drag.origin_skew, drag.origin_x, mx)
    if seq_set_stutter_skew(note, skew) then
      changed = true
    end
    drag.skew = seq_stutter_skew(note)
  end
  if changed then
    state.selected_seq_note = { region_id = region.id, track_id = drag.track_id, step_key = drag.step_key }
    drag.dirty = true
    local slot = seq_find_slot_by_id(drag.track_id)
    if slot then
      if r.PreventUIRefresh then r.PreventUIRefresh(1) end
      sync_seq_pattern_note(region.pattern_id, slot, drag.step_key, { skip_neighbor = true })
      if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
      r.UpdateArrange()
    end
  end
  return changed
end

function seq_note_decay_max_qn(region, slot, note, step_key, step_qn)
  local resolved_path, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot and slot.id, step_key)
  local cap = seq_sample_length_qn(resolved_path, resolved_sample)
  if cap and cap > 0 then
    return cap
  end
  local region_len = region and get_seq_region_length_qn(region) or 8.0
  return math.max(step_qn or 0.25, region_len)
end

function seq_note_current_decay_length_qn(region, slot, note, step_key, step_qn)
  if seq_note_has_stutter_span(note, step_qn) then
    return seq_stutter_span_qn(note, step_qn) or step_qn
  end
  local _, resolved_sample = seq_resolve_note_sample(note, slot, nil, region, slot and slot.id, step_key)
  local pattern = region and get_seq_pattern(region.pattern_id, false) or nil
  return seq_note_draw_length_qn(region, pattern, slot, slot and slot.id, step_key, note, resolved_sample, step_qn)
end

function apply_seq_decay_drag(drag, region, step_qn, mx, my, timeline_x0, timeline_w, view_start_qn, qn_span)
  if not drag or not region then
    return false
  end
  local slot = seq_find_slot_by_id(drag.track_id)
  local note = get_seq_note(region, drag.track_id, drag.step_key)
  if not slot or not note then
    return false
  end
  local note_start_qn = drag.note_start_qn
  if not note_start_qn then
    note_start_qn = seq_note_abs_qn(region, note, drag.step_key, step_qn) + (note.offset_qn or 0.0)
    drag.note_start_qn = note_start_qn
  end
  local min_qn = (step_qn or 0.25) * 0.25
  local max_qn = drag.max_length_qn or seq_note_decay_max_qn(region, slot, note, drag.step_key, step_qn)
  drag.max_length_qn = max_qn
  local mouse_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  local changed = false
  local dx = mx - (drag.origin_x or mx)
  local dy = (drag.origin_y or my) - my

  if drag.handle == "end" then
    local length_qn = mouse_qn - note_start_qn
    if not is_shift_down() then
      length_qn = snap_seq_length_qn(length_qn, step_qn)
    else
      length_qn = math.max(min_qn, length_qn)
    end
    if length_qn < min_qn then length_qn = min_qn end
    if length_qn > max_qn then length_qn = max_qn end
    if seq_note_has_stutter_span(note, step_qn) or seq_stutter_count(note) > 1 then
      if math.abs((note.length_qn or 0.0) - length_qn) > 1e-9 then
        note.length_qn = length_qn
        changed = true
        local qn_offset = seq_note_qn_offset(note, drag.step_key, step_qn)
        seq_delete_notes_overlapping_span(
          region, slot, qn_offset, qn_offset + length_qn, drag.step_key, step_qn, { defer_arrange = true }
        )
      end
    else
      if math.abs((tonumber(note.decay_qn) or 0.0) - length_qn) > 1e-9 then
        note.decay_qn = length_qn
        changed = true
      end
    end
    seq_clamp_note_fades(note, length_qn)
    drag.length_qn = length_qn
  elseif drag.handle == "curve_in" or drag.handle == "curve_out" then
    local which = (drag.handle == "curve_in") and "in" or "out"
    local base_curve = drag.origin_curve or 0.0
    local curve = seq_fade_curve_clamp(base_curve + dy / SEQ_FADE_CURVE_PX)
    if seq_note_set_fade_curve(note, which, curve) then
      changed = true
    end
    drag.fade_curve = seq_note_fade_curve(note, which)
    drag.fade_qn = seq_note_fade_qn(note, which)
    drag.fade_shape = seq_note_fade_shape(note, which)
  elseif drag.handle == "fade_out" or drag.handle == "fade_in" then
    local length_qn = seq_note_current_decay_length_qn(region, slot, note, drag.step_key, step_qn)
    local which = (drag.handle == "fade_in") and "in" or "out"
    if not drag.axis then
      if math.abs(dx) >= SEQ_FADE_AXIS_PX or math.abs(dy) >= SEQ_FADE_AXIS_PX then
        drag.axis = (math.abs(dy) > math.abs(dx)) and "type" or "length"
      end
    end
    if drag.axis == "type" and (drag.origin_fade_qn or 0) < 1e-6 then
      drag.axis = "length"
    end
    if drag.axis ~= "type" then
      local fade_qn
      if which == "in" then
        fade_qn = mouse_qn - note_start_qn
      else
        fade_qn = (note_start_qn + length_qn) - mouse_qn
      end
      if fade_qn < 0 then fade_qn = 0 end
      fade_qn = math.min(fade_qn, math.max(0.0, length_qn - min_qn * 0.1))
      if seq_note_set_fade(note, which, fade_qn, drag.origin_shape) then
        changed = true
      end
      seq_push_note_fades(note, length_qn, which)
    end
    if drag.axis == "type" then
      local base_shape = drag.origin_shape
      if base_shape == nil then
        base_shape = 1
      end
      local shape = seq_fade_shape_clamp(base_shape + math.floor(dy / SEQ_FADE_SHAPE_PX + 0.5))
      local fade_qn = seq_note_fade_qn(note, which)
      if fade_qn < 1e-6 then
        fade_qn = drag.origin_fade_qn or 0.0
      end
      if fade_qn > 1e-6 and seq_note_set_fade(note, which, fade_qn, shape) then
        changed = true
      end
    end
    drag.fade_qn = seq_note_fade_qn(note, which)
    drag.fade_shape = seq_note_fade_shape(note, which)
    drag.fade_curve = seq_note_fade_curve(note, which)
    drag.length_qn = length_qn
  end

  if changed then
    state.selected_seq_note = { region_id = region.id, track_id = slot.id, step_key = drag.step_key }
    drag.dirty = true
  end
  return changed
end

function apply_seq_param_lane_drag(drag, def, lane_y0, lane_y1, mx, my, step_qn, step_count, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, active_cells)
  drag.end_col = seq_param_mouse_col(mx, timeline_x0, timeline_w, view_start_qn, qn_span, start_qn, step_qn, step_count)
  local mouse_col = drag.end_col
  local current_value
  if def.key == "stutter" then
    if drag.origin_count == nil then
      drag.origin_count = seq_clamp_stutter_count(drag.start_value or 1)
      drag.origin_y = drag.origin_y or my
    end
    current_value = seq_stutter_count_from_relative_dy(drag.origin_count, drag.origin_y, my)
  else
    current_value = seq_param_value_for_drag(def, seq_param_value_from_y(def, my, lane_y0, lane_y1, step_qn), step_qn)
  end
  local col_min = math.min(drag.col, drag.end_col)
  local col_max = math.max(drag.col, drag.end_col)
  local mouse_qn = seq_x_to_qn(mx, timeline_x0, timeline_w, view_start_qn, qn_span)
  if seq_is_lock_def(def) then
    local region = get_seq_region_by_id(drag.region_id)
    local changed = seq_apply_lock_range(region, drag.track_id, col_min, col_max, start_qn, step_qn, true, active_cells)
    return changed, 1.0, col_min, col_max, mouse_col
  end
  if seq_is_vary_filter_def(def) then
    if drag.filter_click_span then
      if drag.end_col == drag.col then
        return false, 1.0, col_min, col_max, mouse_col
      end
      drag.filter_click_span = false
    end
    local region = get_seq_region_by_id(drag.region_id)
    local edit = state.seq_vary_filter_edit
    if not edit or edit.region_id ~= drag.region_id or tostring(edit.track_id) ~= tostring(drag.track_id) then
      seq_begin_vary_filter_edit(region, drag.track_id, col_min, col_max, start_qn, step_qn, "", nil)
    else
      edit.col_min = col_min
      edit.col_max = col_max
      edit.start_qn = start_qn
      edit.step_qn = step_qn
    end
    if state.seq_vary_filter_edit then
      state.seq_vary_filter_edit.focus = false
    end
    return false, 1.0, col_min, col_max, mouse_col
  end
  local changed = false

  local function apply_entry(entry, value, qn, all_hits, qn0, qn1)
    if seq_apply_param_to_note(entry.note, entry.abs_qn, def, value, qn, step_qn, false, all_hits, qn0, qn1) then
      changed = true
    end
  end

  if drag.ramp and drag.end_col ~= drag.col then
    local start_val = drag.start_value
    if start_val == nil then
      start_val = def.default
    end
    for col = col_min, col_max do
      local active = active_cells[drag.track_id] and active_cells[drag.track_id][col]
      if active then
        local t = (col - drag.col) / (drag.end_col - drag.col)
        local value = seq_param_value_for_drag(def, start_val + (current_value - start_val) * t, step_qn)
        local qn0 = start_qn + col * step_qn
        local qn1 = qn0 + step_qn
        seq_for_each_active_note(active, function(entry)
          apply_entry(entry, value, qn0 + step_qn * 0.5, true, qn0, qn1)
        end)
      end
    end
  elseif drag.unify then
    for col = col_min, col_max do
      local active = active_cells[drag.track_id] and active_cells[drag.track_id][col]
      if active then
        local qn0 = start_qn + col * step_qn
        local qn1 = qn0 + step_qn
        seq_for_each_active_note(active, function(entry)
          apply_entry(entry, current_value, qn0 + step_qn * 0.5, true, qn0, qn1)
        end)
      end
    end
  else
    local active = active_cells[drag.track_id] and active_cells[drag.track_id][mouse_col]
    if active then
      seq_for_each_active_note(active, function(entry)
        apply_entry(entry, current_value, mouse_qn, false)
      end)
      changed = true
      state.selected_seq_note = {
        region_id = drag.region_id,
        track_id = drag.track_id,
        step_key = active.key,
      }
      drag.hit_idx = seq_stutter_hit_index_at_qn(active.note, active.abs_qn, mouse_qn, step_qn)
    elseif def.key == "stutter" and drag.step_key then
      local region = get_seq_region_by_id(drag.region_id)
      local note = region and get_seq_note(region, drag.track_id, drag.step_key)
      if note then
        if seq_set_note_param_value(note, "stutter", current_value) then
          changed = true
        end
        state.selected_seq_note = {
          region_id = drag.region_id,
          track_id = drag.track_id,
          step_key = drag.step_key,
        }
      end
    end
  end

  local highlight_col_min = mouse_col
  local highlight_col_max = mouse_col
  if drag.ramp or drag.unify then
    highlight_col_min = col_min
    highlight_col_max = col_max
  end

  return changed, current_value, highlight_col_min, highlight_col_max, mouse_col
end

function sample_start_path_key(sample)
  if not sample or not sample.path or sample.path == "" then
    return nil
  end
  return normalize_path(sample.path)
end

function get_sample_start_offset(sample)
  if not sample then
    return 0.0
  end
  local path = sample_start_path_key(sample)
  local session = path and state.seq_sample_start_session and state.seq_sample_start_session[path]
  local t = nil
  if type(session) == "number" then
    t = session
  else
    t = tonumber(sample.start_pos)
  end
  t = tonumber(t) or 0.0
  if t < 0 then
    t = 0
  end
  local dur = tonumber(sample.duration) or 0.0
  if dur > 0.002 and t > dur - 0.001 then
    t = dur - 0.001
  end
  return t
end

function sample_start_has_session(sample)
  local path = sample_start_path_key(sample)
  return path and state.seq_sample_start_session and type(state.seq_sample_start_session[path]) == "number"
end

function sample_start_is_saved(sample)
  return sample ~= nil and sample.start_pos ~= nil
end

function set_sample_start_offset_session(sample, t)
  local path = sample_start_path_key(sample)
  if not path then
    return 0.0
  end
  state.seq_sample_start_session = state.seq_sample_start_session or {}
  t = tonumber(t) or 0.0
  if t < 0 then
    t = 0
  end
  local dur = tonumber(sample.duration) or 0.0
  if dur > 0.002 and t > dur - 0.001 then
    t = dur - 0.001
  end
  state.seq_sample_start_session[path] = t
  return t
end

function seq_rebuild_after_sample_start_change(sample)
  if not sample then
    return
  end
  local path = sample_start_path_key(sample)
  if not path then
    return
  end
  if seq_mark_self_arrange_write then
    seq_mark_self_arrange_write()
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(1)
  end
  for _, slot in ipairs(state.seq_tracks or {}) do
    local match = slot.sample_path and normalize_path(slot.sample_path) == path
    if not match and slot.layers then
      local sides = { slot.layers.transient, slot.layers.sustain }
      for s = 1, #sides do
        local side = sides[s]
        local verts = side and side.verts
        if verts then
          for i = 1, #verts do
            local v = verts[i]
            if v and v.path and normalize_path(v.path) == path then
              match = true
              break
            end
          end
        end
        if match then
          break
        end
      end
    end
    if match then
      sync_seq_slot_all_regions(slot, { skip_arrange = true, force_rebuild = true })
    end
  end
  if r.PreventUIRefresh then
    r.PreventUIRefresh(-1)
  end
  if r.UpdateArrange then
    r.UpdateArrange()
  end
end

function save_sample_start_offset(sample)
  if not sample then
    return
  end
  sample.start_pos = get_sample_start_offset(sample)
  save_samples()
  seq_rebuild_after_sample_start_change(sample)
end

function clear_sample_start_offset_session(sample)
  local path = sample_start_path_key(sample)
  if path and state.seq_sample_start_session then
    state.seq_sample_start_session[path] = nil
  end
  seq_rebuild_after_sample_start_change(sample)
end

function clear_sample_start_offset_saved(sample)
  if not sample then
    return
  end
  sample.start_pos = nil
  save_samples()
  seq_rebuild_after_sample_start_change(sample)
end

function sample_gain_has_session(sample)
  local path = sample_start_path_key(sample)
  return path and state.seq_sample_vol_session and type(state.seq_sample_vol_session[path]) == "number"
end

function sample_gain_is_saved(sample)
  return sample ~= nil and sample.gain ~= nil
end

function apply_sample_gain_to_preview(sample)
  if not cf_preview_obj or not r.CF_Preview_SetValue then
    return
  end
  if preview_sample_obj and sample and preview_sample_obj.path == sample.path then
    r.CF_Preview_SetValue(cf_preview_obj, "D_VOLUME", preview_output_volume(sample))
  end
end

function seq_apply_sample_gain_to_project_items(sample, old_gain, new_gain)
  local path = sample_start_path_key(sample)
  if not path then
    return
  end
  old_gain = tonumber(old_gain) or 1.0
  new_gain = tonumber(new_gain) or 1.0
  if math.abs(new_gain - old_gain) < 1e-6 then
    return
  end
  if old_gain < 1e-4 then
    old_gain = 1e-4
  end
  local mul = new_gain / old_gain
  if seq_mark_self_arrange_write then
    seq_mark_self_arrange_write()
  end
  local n = r.CountMediaItems(0)
  for i = 0, n - 1 do
    local item = r.GetMediaItem(0, i)
    if item and seq_item_source_path(item) == path then
      local take = r.GetActiveTake(item)
      if take then
        local vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1.0
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", vol * mul)
        if r.UpdateItemInProject then
          r.UpdateItemInProject(item)
        end
      end
    end
  end
  if r.UpdateArrange then
    r.UpdateArrange()
  end
end

function set_sample_gain_session(sample, gain)
  local path = sample_start_path_key(sample)
  if not path then
    return 1.0
  end
  local old = get_sample_gain(sample)
  gain = tonumber(gain) or 1.0
  if gain < 0.05 then
    gain = 0.05
  elseif gain > 4 then
    gain = 4
  end
  state.seq_sample_vol_session = state.seq_sample_vol_session or {}
  state.seq_sample_vol_session[path] = gain
  seq_apply_sample_gain_to_project_items(sample, old, gain)
  apply_sample_gain_to_preview(sample)
  return gain
end

function save_sample_gain(sample)
  if not sample then
    return
  end
  sample.gain = get_sample_gain(sample)
  local path = sample_start_path_key(sample)
  if path and state.seq_sample_vol_session then
    state.seq_sample_vol_session[path] = nil
  end
  save_samples()
end

function clear_sample_gain_session(sample)
  local old = get_sample_gain(sample)
  local path = sample_start_path_key(sample)
  if path and state.seq_sample_vol_session then
    state.seq_sample_vol_session[path] = nil
  end
  seq_apply_sample_gain_to_project_items(sample, old, get_sample_gain(sample))
  apply_sample_gain_to_preview(sample)
end

function clear_sample_gain_saved(sample)
  if not sample then
    return
  end
  local old = get_sample_gain(sample)
  sample.gain = nil
  save_samples()
  seq_apply_sample_gain_to_project_items(sample, old, get_sample_gain(sample))
  apply_sample_gain_to_preview(sample)
end

function save_sample_header_settings(sample)
  if not sample then
    return
  end
  sample.start_pos = get_sample_start_offset(sample)
  sample.gain = get_sample_gain(sample)
  local path = sample_start_path_key(sample)
  if path then
    if state.seq_sample_start_session then
      state.seq_sample_start_session[path] = nil
    end
    if state.seq_sample_vol_session then
      state.seq_sample_vol_session[path] = nil
    end
  end
  save_samples()
end

function wave_view_ensure(sample, duration)
  duration = tonumber(duration) or 0.0
  if duration <= 0.0001 then
    duration = 0.0001
  end
  local path = sample and sample.path
  if path and state.wave_view_path ~= path then
    state.wave_view_path = path
    state.wave_view_t0 = 0.0
    state.wave_view_t1 = duration
    state.wave_view_pan = nil
  end
  local t0 = tonumber(state.wave_view_t0) or 0.0
  local t1 = tonumber(state.wave_view_t1) or duration
  if t0 < 0 then t0 = 0 end
  if t1 > duration then t1 = duration end
  if t1 <= t0 then
    t1 = math.min(duration, t0 + math.max(0.04, duration * 0.02))
  end
  if t1 > duration then
    local span = t1 - t0
    t1 = duration
    t0 = math.max(0.0, t1 - span)
  end
  state.wave_view_t0 = t0
  state.wave_view_t1 = t1
  return t0, t1
end

function wave_time_to_x(t, x, w, t0, t1)
  local span = (t1 or 0) - (t0 or 0)
  if span <= 0 or w <= 0 then
    return x
  end
  return x + (((t or 0) - t0) / span) * w
end

function wave_x_to_time(px, x, w, t0, t1)
  if not w or w <= 0 then
    return t0 or 0
  end
  local u = (px - x) / w
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  return (t0 or 0) + u * ((t1 or 0) - (t0 or 0))
end

function wave_view_reset(sample, duration)
  duration = tonumber(duration) or 0.0
  state.wave_view_path = sample and sample.path
  state.wave_view_t0 = 0.0
  state.wave_view_t1 = duration
  state.wave_view_pan = nil
end

function wave_view_zoom(sample, duration, mx, x, w, wheel)
  duration = tonumber(duration) or 0.0
  if not wheel or wheel == 0 or duration <= 0.0001 or w <= 0 then
    return
  end
  local t0, t1 = wave_view_ensure(sample, duration)
  local focus = wave_x_to_time(mx, x, w, t0, t1)
  local span = t1 - t0
  local new_span = span * math.exp(-wheel * 0.18)
  local min_span = math.max(0.04, duration * 0.02)
  if new_span < min_span then new_span = min_span end
  if new_span > duration then new_span = duration end
  local u = (span > 0) and ((focus - t0) / span) or 0.5
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local nt0 = focus - u * new_span
  local nt1 = nt0 + new_span
  if nt0 < 0 then
    nt1 = nt1 - nt0
    nt0 = 0
  end
  if nt1 > duration then
    nt0 = math.max(0.0, nt0 - (nt1 - duration))
    nt1 = duration
  end
  state.wave_view_t0 = nt0
  state.wave_view_t1 = nt1
end

function wave_view_pan(sample, duration, dx, w)
  duration = tonumber(duration) or 0.0
  if duration <= 0.0001 or not w or w <= 0 or not dx or dx == 0 then
    return
  end
  local t0, t1 = wave_view_ensure(sample, duration)
  local span = t1 - t0
  t0 = t0 - (dx / w) * span
  t1 = t0 + span
  if t0 < 0 then
    t1 = t1 - t0
    t0 = 0
  end
  if t1 > duration then
    t0 = math.max(0.0, t0 - (t1 - duration))
    t1 = duration
  end
  state.wave_view_t0 = t0
  state.wave_view_t1 = t1
end

function wave_view_is_zoomed(duration)
  duration = tonumber(duration) or 0.0
  local t0 = tonumber(state.wave_view_t0) or 0.0
  local t1 = tonumber(state.wave_view_t1) or duration
  return duration > 0 and (t1 - t0) < (duration - 0.0005)
end

-- Shared start-marker + volume knob + "..." menu for map and sequencer waveforms.
-- Returns { consumed, over_start, over_vol, over_menu }.
function draw_sample_wave_controls(dl, sample, x, y, w, h, duration, t0, t1, mx, my, left_down, left_clicked, id_suffix, opts)
  opts = opts or {}
  if not sample or w < 16 or h < 10 then
    return { consumed = false }
  end
  duration = tonumber(duration) or 0.0
  t0 = tonumber(t0) or 0.0
  t1 = tonumber(t1) or duration
  if t1 <= t0 then
    t1 = t0 + 0.001
  end
  id_suffix = id_suffix or "wave"

  local start_t = get_sample_start_offset(sample)
  local start_x = wave_time_to_x(start_t, x, w, t0, t1)
  if start_t > t0 then
    local dim_x1 = math.min(x + w, math.max(x, start_x))
    if dim_x1 > x then
      r.ImGui_DrawList_AddRectFilled(dl, x, y, dim_x1, y + h, 0x00000099)
    end
  end
  local start_visible = start_x >= x - 2 and start_x <= x + w + 2
  local start_col = sample_start_has_session(sample) and 0x5CE1FFFF
      or (sample_start_is_saved(sample) and 0x7CFFB0FF or 0x8EC8E8CC)
  local start_tri_half = 6.0
  local start_tri_h = 8.0
  if start_visible then
    r.ImGui_DrawList_AddLine(dl, start_x, y + 1, start_x, y + h - 1, start_col, 1.6)
    r.ImGui_DrawList_AddTriangleFilled(dl,
      start_x - start_tri_half, y + 1,
      start_x + start_tri_half, y + 1,
      start_x, y + 1 + start_tri_h,
      start_col)
    if start_t > 0.0005 then
      r.ImGui_DrawList_AddText(dl, math.min(start_x + 8, x + w - 48), y + 2, start_col,
        string.format("%.2fs", start_t))
    end
  end

  local btn_r = 7.5
  local btn_cx = x + w - 11
  local btn_cy = y + 11
  local vol_r = 8.0
  local vol_cx = btn_cx - 20
  local vol_cy = btn_cy
  local gain = get_sample_gain(sample)
  local over_vol = (mx - vol_cx) * (mx - vol_cx) + (my - vol_cy) * (my - vol_cy) <= (vol_r + 3) * (vol_r + 3)
  local vol_col = sample_gain_has_session(sample) and 0x5CE1FFFF
      or (sample_gain_is_saved(sample) and 0x7CFFB0FF or 0x8EC8E8CC)
  local vol_fill = (over_vol or state.seq_header_vol_drag) and 0x4A5A74FF or 0x2C384CFF
  r.ImGui_DrawList_AddCircleFilled(dl, vol_cx, vol_cy, vol_r, vol_fill, 18)
  r.ImGui_DrawList_AddCircle(dl, vol_cx, vol_cy, vol_r, vol_col, 18, 1.3)
  local ANGLE_MIN = math.pi * 0.75
  local ANGLE_MAX = math.pi * 2.25
  local vol_u = gain / 4.0
  if vol_u < 0 then vol_u = 0 elseif vol_u > 1 then vol_u = 1 end
  local angle = ANGLE_MIN + (ANGLE_MAX - ANGLE_MIN) * vol_u
  local arc_r = vol_r - 2.5
  local prev_ax, prev_ay
  for i = 0, 12 do
    local a = ANGLE_MIN + (angle - ANGLE_MIN) * (i / 12)
    local ax = vol_cx + math.cos(a) * arc_r
    local ay = vol_cy + math.sin(a) * arc_r
    if prev_ax then
      r.ImGui_DrawList_AddLine(dl, prev_ax, prev_ay, ax, ay, vol_col, 1.8)
    end
    prev_ax, prev_ay = ax, ay
  end
  r.ImGui_DrawList_AddLine(dl, vol_cx, vol_cy,
    vol_cx + math.cos(angle) * (vol_r - 3.5),
    vol_cy + math.sin(angle) * (vol_r - 3.5),
    0xFFFFFFFF, 1.4)
  r.ImGui_DrawList_AddCircleFilled(dl, vol_cx, vol_cy, 1.6, 0xFFFFFFFF, 8)

  local over_btn = (mx - btn_cx) * (mx - btn_cx) + (my - btn_cy) * (my - btn_cy) <= (btn_r + 2) * (btn_r + 2)
  r.ImGui_DrawList_AddCircleFilled(dl, btn_cx, btn_cy, btn_r, over_btn and 0x4A5A74FF or 0x2C384CFF, 16)
  r.ImGui_DrawList_AddCircle(dl, btn_cx, btn_cy, btn_r, over_btn and 0xC8D4E8FF or 0x8090A8FF, 16, 1.2)
  local dots = "..."
  local dots_w, dots_h = 10, 12
  if r.ImGui_CalcTextSize then
    dots_w, dots_h = r.ImGui_CalcTextSize(ctx, dots)
  end
  r.ImGui_DrawList_AddText(dl, btn_cx - dots_w * 0.5, btn_cy - dots_h * 0.5 - 1, 0xF4F7FCFF, dots)

  local restore_x, restore_y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, vol_cx - vol_r, vol_cy - vol_r)
  r.ImGui_InvisibleButton(ctx, "##sample_wave_vol_" .. id_suffix, vol_r * 2 + 2, vol_r * 2 + 2)
  if r.ImGui_IsItemHovered(ctx) then
    over_vol = true
  end
  local vol_active = r.ImGui_IsItemActive(ctx)
  local vol_double = r.ImGui_IsItemClicked(ctx, 0) and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  r.ImGui_SetCursorScreenPos(ctx, btn_cx - btn_r, btn_cy - btn_r)
  r.ImGui_InvisibleButton(ctx, "##sample_wave_dots_" .. id_suffix, btn_r * 2 + 2, btn_r * 2 + 2)
  if r.ImGui_IsItemHovered(ctx) then
    over_btn = true
  end
  local dots_clicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 0)
  r.ImGui_SetCursorScreenPos(ctx, restore_x, restore_y)

  if vol_double or (over_vol and left_clicked and r.ImGui_IsMouseDoubleClicked
      and r.ImGui_IsMouseDoubleClicked(ctx, 0)) then
    set_sample_gain_session(sample, 1.0)
    gain = 1.0
    state.seq_header_vol_drag = nil
  elseif over_vol and left_clicked then
    state.seq_header_vol_drag = true
    state.waveform_drag_armed = nil
  end
  local vol_fine = seq_fine_drag_down()
  if (vol_active or state.seq_header_vol_drag) and left_down then
    local _, dy = r.ImGui_GetMouseDelta(ctx)
    if dy and dy ~= 0.0 then
      state.seq_header_vol_drag = true
      state.waveform_drag_armed = nil
      set_sample_gain_session(sample, gain + (-dy) * 0.02 * (vol_fine and SEQ_FINE_DRAG_SCALE or 1.0))
      gain = get_sample_gain(sample)
    end
  elseif state.seq_header_vol_drag and not left_down then
    state.seq_header_vol_drag = nil
  end
  if over_vol and not vol_active then
    local wheel = r.ImGui_GetMouseWheel and select(1, r.ImGui_GetMouseWheel(ctx)) or 0
    if wheel and wheel ~= 0 then
      set_sample_gain_session(sample, gain + wheel * 0.08)
      gain = get_sample_gain(sample)
    end
  end

  if opts.show_name then
    local name = sample.name or ""
    if name ~= "" then
      if r.ImGui_DrawList_PushClipRect then
        r.ImGui_DrawList_PushClipRect(dl, x + 4, y + 1, vol_cx - vol_r - 3, y + h - 1, true)
      end
      r.ImGui_DrawList_AddText(dl, x + 7, y + 4, 0x000000CC, name)
      r.ImGui_DrawList_AddText(dl, x + 6, y + 3, 0xF4F7FCFF, name)
      if r.ImGui_DrawList_PopClipRect then
        r.ImGui_DrawList_PopClipRect(dl)
      end
    end
  end

  local over_start = start_visible
      and mx >= start_x - (start_tri_half + 2)
      and mx <= start_x + (start_tri_half + 2)
      and my >= y
      and my <= y + start_tri_h + 3

  if (over_btn and left_clicked) or dots_clicked then
    state.seq_header_menu_sample = sample
    if r.ImGui_OpenPopup then
      r.ImGui_OpenPopup(ctx, "##seq_header_sample_menu")
    end
  end
  draw_seq_header_sample_menu(sample)

  if state.seq_header_start_drag and not left_down then
    state.seq_header_start_drag = nil
    seq_rebuild_after_sample_start_change(sample)
  end

  if over_btn then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
  elseif over_vol or state.seq_header_vol_drag then
    if r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, string.format("Volume  %.0f%% (double-click reset)", gain * 100.0))
    end
  elseif over_start or state.seq_header_start_drag then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    end
    if r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, string.format("Start  %.3fs", start_t))
    end
  end

  if duration > 0 and not over_btn and not over_vol and not state.seq_header_vol_drag
      and ((left_clicked and over_start) or (state.seq_header_start_drag and left_down)) then
    state.seq_header_start_drag = true
    state.seq_header_wave_press = nil
    state.seq_header_wave_press_t = nil
    local new_t = wave_x_to_time(mx, x, w, t0, t1)
    start_t = set_sample_start_offset_session(sample, new_t)
    if preview_proc and preview_sample_obj and preview_sample_obj.path == sample.path then
      seek_preview(start_t)
    end
  end

  local consumed = over_btn or over_vol or over_start
      or state.seq_header_start_drag or state.seq_header_vol_drag
  return {
    consumed = consumed,
    over_start = over_start,
    over_vol = over_vol,
    over_menu = over_btn,
    start_t = start_t,
  }
end

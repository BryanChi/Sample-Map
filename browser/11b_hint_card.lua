-- Sample Map Browser module: hint_card
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Hint card -----------------------------------------------------------------
-- Hover hints show as a card just above the hovered control (below it when
-- there's no room), instead of a tooltip that follows the mouse. Mouse buttons
-- and modifier keys in the hint text become icons and key chips, and a caret
-- plus an outline tie the card to the control. Every ImGui_SetTooltip call in the browser comes
-- through here (see the override at the end of this file), so hint text keeps
-- its plain-string form: "Alt+LMB drag = stutter", "Click: preview · …".

HINT_CARD = {
  max_w = 400,         -- card width cap; text wraps inside it
  pad_x = 12,
  pad_y = 9,
  row_gap = 5,
  key_gap = 10,        -- between the key column and the description
  rounding = 8,
  margin = 6,          -- distance from the window edge
  gap = 8,             -- between the card and the hovered control
  caret = 6,           -- size of the pointer under the card
  shadow = 6,
  show_delay = 0.16,   -- seconds of hover before a cold card appears
  warm_time = 0.5,     -- moving to another control within this keeps it up
  fade_time = 0.12,
}

HINT_COLORS = {
  bg          = 0x101612F4,
  border      = 0x2E3C33FF,
  shadow      = 0x00000050,
  title       = 0xF1F6F2FF,
  text        = 0xC9D3CCFF,
  qual        = 0x8E9A92FF,
  plus        = 0x5F6962FF,
  rule        = 0xFFFFFF14,
  key_fill    = 0x27302AFF,
  key_edge    = 0x3C4A42FF,
  key_base    = 0x0A0D0BFF,
  key_text    = 0xE8EEEAFF,
  mouse_line  = 0xB4C0B8FF,
}

hint_state = hint_state or {
  req = nil,
  pending_text = nil,
  pending_since = 0,
  visible_since = 0,
  last_shown = -100,
  layouts = {},
  layout_count = 0,
}

-- Context the card is being laid out / drawn for (set by hint_card_flush).
hint_ctx = nil

local function hint_accent()
  return (UI_THEME and UI_THEME.accent) or 0x1EFF5EFF
end

-- Scale a 0xRRGGBBAA color's alpha by f (0..1).
local function hint_fade(col, f)
  if f >= 1 then
    return col
  end
  local a = col & 0xFF
  return (col & 0xFFFFFF00) | math.floor(a * math.max(0, f) + 0.5)
end

local function hint_with_alpha(col, a)
  return (col & 0xFFFFFF00) | (a & 0xFF)
end

-- --- Parsing ---------------------------------------------------------------------

local HINT_IS_MAC = nil
local function hint_is_mac()
  if HINT_IS_MAC == nil then
    local os_name = (r.GetOS and r.GetOS()) or ""
    HINT_IS_MAC = (os_name:find("OSX") or os_name:find("mac")) and true or false
  end
  return HINT_IS_MAC
end

local function hint_mod_label(word)
  if word == "Ctrl/Cmd" or word == "Cmd/Ctrl" then
    return hint_is_mac() and "Cmd" or "Ctrl"
  end
  if word == "Alt" or word == "Opt" or word == "Option" then
    return hint_is_mac() and "Opt" or "Alt"
  end
  if word == "Shift" or word == "Ctrl" or word == "Cmd" then
    return word
  end
  return nil
end

local HINT_MOUSE_ABBR = {
  LMB = { btn = "L" },
  RMB = { btn = "R" },
  MMB = { btn = "M" },
}

-- Mouse verbs get an icon too, but the word itself stays in the sentence.
local HINT_MOUSE_WORDS = {
  ["click"] = { btn = "L" },
  ["double-click"] = { btn = "L", dbl = true },
  ["right-click"] = { btn = "R" },
  ["drag"] = { btn = "L" },
  ["wheel"] = { btn = "W" },
  ["scroll"] = { btn = "W" },
}

local HINT_NAMED_KEYS = {
  Esc = true, Escape = true, Enter = true, Return = true, Tab = true, Space = true,
  Backspace = true, Delete = true, Del = true, Insert = true, Home = true, End = true,
  Left = true, Right = true, Up = true, Down = true,
}

-- Plain keys (letters, named keys, F-keys) only count in a combo with a
-- modifier, or when they stand alone as the subject of "X = …" / "(X)", so
-- prose like "A sample…" or "Enter a word" stays prose.
local function hint_plain_key(part)
  if HINT_NAMED_KEYS[part] then
    return part
  end
  if part:match("^F%d%d?$") then
    return part
  end
  if #part == 1 and not part:match("[%s%l]") then
    return part
  end
  if SHORTCUT_KEY_LABELS then
    for _, label in pairs(SHORTCUT_KEY_LABELS) do
      if label == part then
        return part
      end
    end
  end
  return nil
end

-- One "+"-joined word -> list of atoms, or nil when it isn't a key combo.
-- strict: plain keys need a modifier alongside (or loose=true to allow alone).
local function hint_parse_combo(word, loose)
  if word == "" then
    return nil
  end
  local parts = {}
  -- "Ctrl/Cmd" contains no "+", so splitting on "+" is safe; a trailing "+" key
  -- ("Ctrl++") is not used by any hint.
  for part in (word .. "+"):gmatch("(.-)%+") do
    parts[#parts + 1] = part
  end
  local atoms, has_mod = {}, false
  local mouse_word = nil
  for i, part in ipairs(parts) do
    if i > 1 then
      atoms[#atoms + 1] = { t = "plus" }
    end
    local mod = hint_mod_label(part)
    local abbr = HINT_MOUSE_ABBR[part]
    local mw = HINT_MOUSE_WORDS[part:lower()]
    if mod then
      atoms[#atoms + 1] = { t = "key", s = mod }
      has_mod = true
    elseif abbr then
      atoms[#atoms + 1] = { t = "mouse", btn = abbr.btn }
      has_mod = true
    elseif mw and i == #parts then
      atoms[#atoms + 1] = { t = "mouse", btn = mw.btn, dbl = mw.dbl }
      mouse_word = part
      has_mod = true
    else
      local plain = hint_plain_key(part)
      if not plain then
        return nil
      end
      atoms[#atoms + 1] = { t = "key", s = plain }
    end
  end
  if not has_mod and not loose then
    return nil
  end
  return atoms, mouse_word
end

-- Body text -> atoms: words, with inline chips for key combos and "(X)" keys.
local function hint_body_atoms(text, col)
  local atoms = {}
  for word in text:gmatch("%S+") do
    local lead, core, trail = word:match("^([%(%[\"']*)(.-)([%)%]%.,;:!?\"']*)$")
    lead, core, trail = lead or "", core or word, trail or ""
    local chips = nil
    if core ~= "" and core:find("[%+]") or hint_mod_label(core) or HINT_MOUSE_ABBR[core] then
      chips = hint_parse_combo(core, false)
      if chips and #chips == 1 and chips[1].t == "mouse" and not HINT_MOUSE_ABBR[core] then
        chips = nil -- a lone mouse verb mid-sentence stays a word
      end
    end
    if not chips and lead == "(" and trail:sub(1, 1) == ")" then
      chips = hint_parse_combo(core, true)
      if chips then
        lead, trail = "", trail:sub(2)
      end
    end
    if chips then
      if lead ~= "" then
        atoms[#atoms + 1] = { t = "text", s = lead, col = col }
      end
      for i, a in ipairs(chips) do
        a.glue = (i > 1) or (lead ~= "")
        atoms[#atoms + 1] = a
      end
      if trail ~= "" then
        atoms[#atoms + 1] = { t = "text", s = trail, col = col, glue = true }
      end
    else
      atoms[#atoms + 1] = { t = "text", s = word, col = col }
    end
  end
  return atoms
end

local function hint_trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One segment ("Alt+LMB drag = stutter") -> row { keys, body }.
local function hint_parse_segment(seg)
  seg = hint_trim(seg)
  if seg == "" then
    return nil
  end
  local left, right = seg:match("^(.-)%s+=%s+(.+)$")
  if not left then
    left, right = seg:match("^([^:]-):%s+(.+)$")
  end
  -- "X = Y" / "X: Y" only splits when X is a short key phrase, so "(Shift =
  -- unsnap)" inside a sentence stays part of the sentence.
  if left and (#left > 40 or left:find("[%(%)]") or select(2, left:gsub("%S+", "")) > 6) then
    left, right = nil, nil
  end
  local head = left or seg
  local first, rest = head:match("^(%S+)%s*(.-)$")
  local keys, mouse_word = nil, nil
  if first then
    -- Plain keys may lead only when they are the whole left side: "Q = enlarge".
    keys, mouse_word = hint_parse_combo(first, (left and rest == "") and true or false)
    if not keys and first:find("+", 1, true) then
      -- "Shift+empty grid": chips for the leading keys, the rest stays words.
      local key_part, word_part = first:match("^(.-)%+([^%+]+)$")
      keys = key_part and hint_parse_combo(key_part, false)
      if keys then
        rest = word_part .. (rest ~= "" and (" " .. rest) or "")
      end
    end
    local loose_word = keys and #keys == 1 and keys[1].t == "mouse" and mouse_word
    if loose_word and not left and rest == "" then
      keys = nil -- a lone "Drag" with nothing after it is just a word
    end
  end
  if not keys then
    return { body = hint_body_atoms(seg, "text") }
  end
  local qual = rest or ""
  if mouse_word then
    qual = mouse_word .. (qual ~= "" and (" " .. qual) or "")
  end
  local body = {}
  if left then
    if qual ~= "" then
      for _, a in ipairs(hint_body_atoms(qual, "qual")) do
        body[#body + 1] = a
      end
      body[#body + 1] = { t = "arrow" }
    end
    for _, a in ipairs(hint_body_atoms(right, "text")) do
      body[#body + 1] = a
    end
  else
    body = hint_body_atoms(qual, "text")
  end
  return { keys = keys, body = body }
end

function hint_parse(text)
  local rows = {}
  text = tostring(text or ""):gsub("\r", "")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    -- "A · B · C" lists become one row per item.
    local segs = {}
    for seg in (line .. "\194\183"):gmatch("(.-)\194\183") do
      segs[#segs + 1] = seg
    end
    for _, seg in ipairs(segs) do
      local row = hint_parse_segment(seg)
      if row then
        rows[#rows + 1] = row
      end
    end
  end
  -- A leading prose line over more rows reads as the card's title.
  if #rows > 1 and not rows[1].keys then
    rows[1].title = true
  end
  return rows
end

-- --- Layout ----------------------------------------------------------------------
-- Produces draw ops relative to the card's top-left, so drawing is a translate.

local function hint_text_w(c, s)
  local w = r.ImGui_CalcTextSize(c, s)
  return tonumber(w) or 0
end

local function hint_atom_w(c, a, m)
  if a.t == "text" then
    return hint_text_w(c, a.s)
  elseif a.t == "plus" then
    return m.plus_w
  elseif a.t == "arrow" then
    return 14
  elseif a.t == "mouse" then
    return m.chip_h * 0.86 + (a.dbl and (m.x2_w + 2) or 0)
  end
  return math.max(m.chip_h, hint_text_w(c, a.s) + 10)
end

local function hint_keys_w(c, keys, m)
  local w = 0
  for i, a in ipairs(keys) do
    w = w + hint_atom_w(c, a, m) + (i > 1 and 2 or 0)
  end
  return w
end

-- Flow atoms into lines of at most max_w; returns ops (y relative to row top),
-- used width and line count.
local function hint_flow(c, atoms, x0, max_w, m, ops, y0, row_col)
  local x, y = x0, y0
  local used, lines = 0, 1
  for i, a in ipairs(atoms) do
    local w = hint_atom_w(c, a, m)
    local gap = (i == 1 or a.glue) and 0 or ((a.t == "plus" or atoms[i - 1].t == "plus") and 0 or m.space_w)
    if i > 1 and not a.glue and x + gap + w > x0 + max_w then
      x = x0
      y = y + m.line_h + 1
      lines = lines + 1
      gap = 0
    end
    x = x + gap
    local col = (a.col == "qual") and "qual" or row_col
    if a.t == "text" then
      ops[#ops + 1] = { k = "text", x = x, y = y, s = a.s, col = col }
    elseif a.t == "plus" then
      ops[#ops + 1] = { k = "text", x = x + 1, y = y, s = "+", col = "plus" }
    elseif a.t == "arrow" then
      ops[#ops + 1] = { k = "arrow", x = x, y = y + m.line_h * 0.5 + 0.5, w = w }
    elseif a.t == "mouse" then
      ops[#ops + 1] = { k = "mouse", x = x, y = y + (m.line_h - m.chip_h) * 0.5, w = w, h = m.chip_h, btn = a.btn, dbl = a.dbl }
    else
      ops[#ops + 1] = { k = "key", x = x, y = y + (m.line_h - m.chip_h) * 0.5, w = w, h = m.chip_h, s = a.s }
    end
    x = x + w
    if x - x0 > used then
      used = x - x0
    end
  end
  return used, lines
end

function hint_layout(c, text)
  local cached = hint_state.layouts[text]
  if cached then
    return cached
  end
  local cfg = HINT_CARD
  local _, line_h = r.ImGui_CalcTextSize(c, "Ag")
  line_h = tonumber(line_h) or 14
  local m = {
    line_h = line_h,
    chip_h = math.floor(line_h + 4),
    space_w = hint_text_w(c, " "),
    plus_w = hint_text_w(c, "+") + 2,
    x2_w = hint_text_w(c, "×2"),
  }
  local rows = hint_parse(text)
  local key_col = 0
  for _, row in ipairs(rows) do
    if row.keys then
      key_col = math.max(key_col, hint_keys_w(c, row.keys, m))
    end
  end
  local inner_max = cfg.max_w - cfg.pad_x * 2
  -- A very wide key cluster shouldn't squeeze every description.
  key_col = math.min(key_col, inner_max * 0.45)

  local ops = {}
  local y = cfg.pad_y
  local content_w = 0
  local x_left = cfg.pad_x
  for i, row in ipairs(rows) do
    local row_top = y
    local row_h = line_h
    if row.keys then
      local kx = x_left
      for j, a in ipairs(row.keys) do
        local w = hint_atom_w(c, a, m)
        if j > 1 then
          kx = kx + 2
        end
        if a.t == "plus" then
          ops[#ops + 1] = { k = "text", x = kx + 1, y = row_top, s = "+", col = "plus" }
        elseif a.t == "mouse" then
          ops[#ops + 1] = { k = "mouse", x = kx, y = row_top + (line_h - m.chip_h) * 0.5, w = w, h = m.chip_h, btn = a.btn, dbl = a.dbl }
        else
          ops[#ops + 1] = { k = "key", x = kx, y = row_top + (line_h - m.chip_h) * 0.5, w = w, h = m.chip_h, s = a.s }
        end
        kx = kx + w
      end
      local body_x = x_left + math.max(key_col, kx - x_left) + cfg.key_gap
      local avail = inner_max - (body_x - x_left)
      local used, lines = hint_flow(c, row.body, body_x, math.max(80, avail), m, ops, row_top, "text")
      content_w = math.max(content_w, (body_x - x_left) + used)
      row_h = math.max(m.chip_h - 2, lines * (line_h + 1) - 1)
    else
      local used, lines = hint_flow(c, row.body, x_left, inner_max, m, ops, row_top, row.title and "title" or (#rows == 1 and "title" or "text"))
      content_w = math.max(content_w, used)
      row_h = lines * (line_h + 1) - 1
    end
    y = row_top + row_h
    if i < #rows then
      if row.title then
        y = y + cfg.row_gap + 1
        ops[#ops + 1] = { k = "rule", y = y }
        y = y + cfg.row_gap + 2
      else
        y = y + cfg.row_gap
      end
    end
  end
  local layout = {
    w = math.floor(content_w + cfg.pad_x * 2 + 0.5),
    h = math.floor(y + cfg.pad_y + 0.5),
    ops = ops,
    rows = rows,
  }
  if hint_state.layout_count > 96 then
    hint_state.layouts = {}
    hint_state.layout_count = 0
  end
  hint_state.layouts[text] = layout
  hint_state.layout_count = hint_state.layout_count + 1
  return layout
end

-- --- Drawing ---------------------------------------------------------------------

local function hint_round_flag(name)
  local fn = r["ImGui_DrawFlags_" .. name]
  return fn and fn() or 0
end

local function hint_draw_mouse(dl, op, ox, oy, f)
  local accent = hint_fade(hint_accent(), f)
  local line = hint_fade(HINT_COLORS.mouse_line, f)
  local icon_w = op.h * 0.86
  local cx = ox + op.x + icon_w * 0.5
  local cy = oy + op.y + op.h * 0.5
  local bw = math.floor(op.h * 0.56 + 0.5)
  local bh = math.floor(op.h * 0.82 + 0.5)
  local x0, y0 = cx - bw * 0.5, cy - bh * 0.5
  local x1, y1 = x0 + bw, y0 + bh
  local rr = bw * 0.5
  local split = y0 + bh * 0.44
  if op.btn == "L" then
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, cx, split, accent, rr, hint_round_flag("RoundCornersTopLeft"))
  elseif op.btn == "R" then
    r.ImGui_DrawList_AddRectFilled(dl, cx, y0, x1, split, accent, rr, hint_round_flag("RoundCornersTopRight"))
  end
  r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, line, rr, 0, 1.2)
  r.ImGui_DrawList_AddLine(dl, x0 + 0.5, split, x1 - 0.5, split, line, 1.0)
  if op.btn == "M" or op.btn == "W" then
    r.ImGui_DrawList_AddRectFilled(dl, cx - 1.5, y0 + 2, cx + 1.5, split + 2, accent, 1.5)
  else
    r.ImGui_DrawList_AddLine(dl, cx, y0 + 0.5, cx, split, line, 1.0)
  end
  if op.dbl then
    local tx = ox + op.x + icon_w + 1
    local _, th = r.ImGui_CalcTextSize(hint_ctx, "2")
    r.ImGui_DrawList_AddText(dl, tx, cy - (tonumber(th) or 12) * 0.5, accent, "×2")
  end
end

local function hint_draw_key(dl, op, ox, oy, f)
  local x0, y0 = ox + op.x, oy + op.y
  local x1, y1 = x0 + op.w, y0 + op.h
  -- Keycap: a darker base peeking out below gives it some depth.
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0 + 1.5, x1, y1 + 1.5, hint_fade(HINT_COLORS.key_base, f), 4.0)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, hint_fade(HINT_COLORS.key_fill, f), 4.0)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, hint_fade(HINT_COLORS.key_edge, f), 4.0, 0, 1.0)
  local tw, th = r.ImGui_CalcTextSize(hint_ctx, op.s)
  r.ImGui_DrawList_AddText(dl, x0 + (op.w - (tonumber(tw) or 0)) * 0.5, y0 + (op.h - (tonumber(th) or 0)) * 0.5 - 0.5,
    hint_fade(HINT_COLORS.key_text, f), op.s)
end

local function hint_draw_mouse_chip(dl, op, ox, oy, f)
  local x0, y0 = ox + op.x, oy + op.y
  local x1, y1 = x0 + op.w, y0 + op.h
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0 + 1.5, x1, y1 + 1.5, hint_fade(HINT_COLORS.key_base, f), 4.0)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, hint_fade(HINT_COLORS.key_fill, f), 4.0)
  r.ImGui_DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, hint_fade(HINT_COLORS.key_edge, f), 4.0, 0, 1.0)
  hint_draw_mouse(dl, op, ox, oy, f)
end

-- Card body at (x, y) with fade f.
function hint_draw_card(dl, layout, x, y, f)
  local cfg = HINT_CARD
  local w, h = layout.w, layout.h
  local sh = cfg.shadow
  r.ImGui_DrawList_AddRectFilled(dl, x - 1, y + 2, x + w + 1, y + h + sh * 0.6, hint_fade(HINT_COLORS.shadow, f), cfg.rounding + 2)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, hint_fade(HINT_COLORS.bg, f), cfg.rounding)
  r.ImGui_DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, hint_fade(HINT_COLORS.border, f), cfg.rounding, 0, 1.0)
  -- Accent tab on the left edge, matching the leader line.
  r.ImGui_DrawList_AddRectFilled(dl, x + 1, y + cfg.rounding, x + 3, y + h - cfg.rounding,
    hint_fade(hint_with_alpha(hint_accent(), 0xC8), f), 1.0)
  for _, op in ipairs(layout.ops) do
    if op.k == "text" then
      r.ImGui_DrawList_AddText(dl, x + op.x, y + op.y, hint_fade(HINT_COLORS[op.col] or HINT_COLORS.text, f), op.s)
    elseif op.k == "key" then
      hint_draw_key(dl, op, x, y, f)
    elseif op.k == "mouse" then
      hint_draw_mouse_chip(dl, op, x, y, f)
    elseif op.k == "arrow" then
      local ac = hint_fade(HINT_COLORS.plus, f)
      local ax0, ax1, ay = x + op.x + 2, x + op.x + op.w - 3, y + op.y
      r.ImGui_DrawList_AddLine(dl, ax0, ay, ax1, ay, ac, 1.2)
      r.ImGui_DrawList_AddLine(dl, ax1 - 3.5, ay - 3, ax1, ay, ac, 1.2)
      r.ImGui_DrawList_AddLine(dl, ax1 - 3.5, ay + 3, ax1, ay, ac, 1.2)
    elseif op.k == "rule" then
      r.ImGui_DrawList_AddLine(dl, x + cfg.pad_x, y + op.y, x + w - cfg.pad_x, y + op.y, hint_fade(HINT_COLORS.rule, f), 1.0)
    end
  end
end

local function hint_rects_overlap(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1)
  return ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1
end

-- Place the card just above the hovered control, centred on it and kept inside
-- the window; below it when there's no room above. Returns x, y and which side.
function hint_place(req, w, h)
  local cfg = HINT_CARD
  local vp = req.vp
  local m = cfg.margin
  if not vp or vp.w < w + m * 2 then
    return nil
  end
  local a = req.anchor
  local gap = cfg.gap
  local x = (a.x0 + a.x1) * 0.5 - w * 0.5
  x = math.max(vp.x + m, math.min(vp.x + vp.w - m - w, x))
  local above_y = a.y0 - gap - h
  if above_y >= vp.y + m then
    return x, above_y, "above"
  end
  local below_y = a.y1 + gap
  if below_y + h <= vp.y + vp.h - m then
    return x, below_y, "below"
  end
  return x, math.max(vp.y + m, above_y), "above"
end

-- Guidance: outline the hovered control and point a small caret at it.
local function hint_draw_pointer(dl, fg, req, cx, cy, w, h, side, f)
  local a = req.anchor
  local accent = hint_accent()
  if req.item and fg then
    r.ImGui_DrawList_AddRect(fg, a.x0 - 2, a.y0 - 2, a.x1 + 2, a.y1 + 2, hint_fade(hint_with_alpha(accent, 0xB0), f), 5.0, 0, 1.5)
  end
  local r0 = HINT_CARD.rounding + 6
  local px = math.max(cx + r0, math.min(cx + w - r0, (a.x0 + a.x1) * 0.5))
  local cs = HINT_CARD.caret
  local bg = hint_fade(HINT_COLORS.bg, f)
  local edge = hint_fade(HINT_COLORS.border, f)
  if r.ImGui_DrawList_AddTriangleFilled then
    if side == "above" then
      local by = cy + h - 1
      r.ImGui_DrawList_AddTriangleFilled(dl, px - cs, by, px + cs, by, px, by + cs, bg)
      r.ImGui_DrawList_AddLine(dl, px - cs, by + 0.5, px, by + cs + 0.5, edge, 1.0)
      r.ImGui_DrawList_AddLine(dl, px, by + cs + 0.5, px + cs, by + 0.5, edge, 1.0)
    else
      local ty = cy + 1
      r.ImGui_DrawList_AddTriangleFilled(dl, px - cs, ty, px, ty - cs, px + cs, ty, bg)
      r.ImGui_DrawList_AddLine(dl, px - cs, ty - 0.5, px, ty - cs - 0.5, edge, 1.0)
      r.ImGui_DrawList_AddLine(dl, px, ty - cs - 0.5, px + cs, ty - 0.5, edge, 1.0)
    end
  end
end

-- --- Request / flush ---------------------------------------------------------------

local function hint_capture(c, text, opts)
  local mx, my = r.ImGui_GetMousePos(c)
  mx, my = tonumber(mx) or 0, tonumber(my) or 0
  local anchor = { x0 = mx - 1, y0 = my - 1, x1 = mx + 1, y1 = my + 1 }
  local item = false
  if not (opts and opts.at_mouse) and r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
    local x0, y0 = r.ImGui_GetItemRectMin(c)
    local x1, y1 = r.ImGui_GetItemRectMax(c)
    x0, y0, x1, y1 = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)
    -- Only trust the last item when the mouse is on it and it's control-sized;
    -- hints for things drawn inside a big canvas point at the mouse instead.
    if x0 and y0 and x1 and y1
        and mx >= x0 - 2 and mx <= x1 + 2 and my >= y0 - 2 and my <= y1 + 2
        and (x1 - x0) <= 320 and (y1 - y0) <= 120 then
      anchor = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
      item = true
    end
  end
  local vp = nil
  if r.ImGui_GetWindowViewport and r.ImGui_Viewport_GetWorkPos and r.ImGui_Viewport_GetWorkSize then
    local v = r.ImGui_GetWindowViewport(c)
    if v then
      local vx, vy = r.ImGui_Viewport_GetWorkPos(v)
      local vw, vh = r.ImGui_Viewport_GetWorkSize(v)
      if tonumber(vw) and tonumber(vw) > 0 and tonumber(vh) and tonumber(vh) > 0 then
        vp = { x = tonumber(vx) or 0, y = tonumber(vy) or 0, w = tonumber(vw), h = tonumber(vh) }
      end
    end
  end
  if not vp and state and state.main_window_rect then
    local mw = state.main_window_rect
    vp = { x = mw.x, y = mw.y, w = mw.w, h = mw.h }
  end
  hint_state.req = {
    ctx = c,
    text = text,
    anchor = anchor,
    item = item,
    vp = vp,
  }
end

-- Queue a hint for this frame; the last one requested wins, like SetTooltip.
function hint_request(c, text, opts)
  if text == nil then
    return
  end
  text = tostring(text)
  if text == "" then
    return
  end
  local ok = pcall(hint_capture, c or ctx, text, opts)
  if not ok and HINT_RAW_SET_TOOLTIP then
    HINT_RAW_SET_TOOLTIP(c or ctx, text)
  end
end

function hint_tooltip(text, opts)
  hint_request(ctx, text, opts)
end

local function hint_begin_card_window(c, x, y)
  local cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
  r.ImGui_SetNextWindowPos(c, x, y, cond)
  local pushed_vars, pushed_cols = 0, 0
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_StyleVar_PopupBorderSize then
    r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_PopupBorderSize(), 0)
    pushed_vars = pushed_vars + 1
  end
  if r.ImGui_Col_PopupBg then
    r.ImGui_PushStyleColor(c, r.ImGui_Col_PopupBg(), 0x00000000)
    pushed_cols = pushed_cols + 1
  end
  local open = r.ImGui_BeginTooltip(c)
  return open ~= false, pushed_vars, pushed_cols
end

-- Draw the hint requested this frame. Called once per frame from the main loop,
-- after every window, so the card sits on top of everything.
function hint_card_flush()
  local req = hint_state.req
  hint_state.req = nil
  local now = r.time_precise()
  if not req then
    hint_state.pending_text = nil
    return
  end
  local c = req.ctx or ctx
  hint_ctx = c
  if req.text ~= hint_state.pending_text then
    hint_state.pending_text = req.text
    hint_state.pending_since = now
  end
  local cold = (now - (hint_state.last_shown or -100)) > HINT_CARD.warm_time
  if cold then
    if now - hint_state.pending_since < HINT_CARD.show_delay then
      return
    end
    hint_state.visible_since = now
  end
  hint_state.last_shown = now
  local f = 1.0
  if HINT_CARD.fade_time > 0 then
    f = math.min(1.0, (now - (hint_state.visible_since or now)) / HINT_CARD.fade_time)
    f = 0.25 + 0.75 * f
  end

  local layout = hint_layout(c, req.text)
  local cs = HINT_CARD.caret
  local x, y, side = hint_place(req, layout.w + 2, layout.h)
  if not x then
    x, y, side = req.anchor.x0, req.anchor.y1 + HINT_CARD.gap, "below"
  end
  -- The window also holds the caret: below the card when it sits above the
  -- control, above it when below.
  local top_pad = (side == "below") and cs or 0
  local bot_pad = (side == "above") and cs or HINT_CARD.shadow

  local open, pushed_vars, pushed_cols = hint_begin_card_window(c, x, y - top_pad)
  if open then
    local dl = r.ImGui_GetWindowDrawList(c)
    local wx, wy = r.ImGui_GetCursorScreenPos(c)
    wx, wy = tonumber(wx) or x, (tonumber(wy) or (y - top_pad)) + top_pad
    hint_draw_card(dl, layout, wx + 1, wy, f)
    local fg = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(c) or nil
    hint_draw_pointer(dl, fg, req, wx + 1, wy, layout.w, layout.h, side, f)
    r.ImGui_Dummy(c, layout.w + 2, layout.h + top_pad + bot_pad)
    r.ImGui_EndTooltip(c)
  end
  if pushed_cols > 0 then
    r.ImGui_PopStyleColor(c, pushed_cols)
  end
  if pushed_vars > 0 then
    r.ImGui_PopStyleVar(c, pushed_vars)
  end
end

-- Route every SetTooltip in the browser through the hint card. The original is
-- kept as a fallback for when capturing the hint fails.
if r.ImGui_SetTooltip and not HINT_RAW_SET_TOOLTIP then
  HINT_RAW_SET_TOOLTIP = r.ImGui_SetTooltip
  r.ImGui_SetTooltip = function(c, text)
    hint_request(c, text)
  end
end

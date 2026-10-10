"""Tests for the hover hint card (browser/11b_hint_card.lua): parsing hint text
into key chips / mouse icons, and drawing the card pinned clear of the control."""
import os

from lupa import lua54

ROOT = os.path.join(os.path.dirname(__file__), "..")

STUB = r'''
CALLS = {}
OS_NAME = OS_NAME or "Win64"
MOUSE = MOUSE or {100, 100}
ITEM = ITEM or {90, 90, 130, 112}
local special = {
  GetOS = function() return OS_NAME end,
  time_precise = function() return NOW end,
  ImGui_CalcTextSize = function(_, s) return #tostring(s) * 7, 14 end,
  ImGui_GetMousePos = function() return MOUSE[1], MOUSE[2] end,
  ImGui_GetItemRectMin = function() return ITEM[1], ITEM[2] end,
  ImGui_GetItemRectMax = function() return ITEM[3], ITEM[4] end,
  ImGui_GetWindowViewport = function() return {} end,
  ImGui_Viewport_GetWorkPos = function() return 0, 0 end,
  ImGui_Viewport_GetWorkSize = function() return 1200, 800 end,
  ImGui_BeginTooltip = function() return true end,
  ImGui_GetForegroundDrawList = function() return {} end,
}
reaper = setmetatable({}, { __index = function(t, k)
  local f = special[k] or function(...)
    CALLS[#CALLS + 1] = { k, ... }
    if k:match("^ImGui_GetCursorScreenPos") then return LAST_POS[1], LAST_POS[2] end
    if k:match("^ImGui_[A-Z]%w*_") and not k:match("^ImGui_DrawList_") then return 0 end
    if k == "ImGui_SetNextWindowPos" then LAST_POS = { select(2, ...) } end
    return nil
  end
  rawset(t, k, f)
  return f
end })
LAST_POS = { 0, 0 }
NOW = 0
UI_THEME = { accent = 0x1EFF5EFF }
ctx = {}
'''


def _runtime(os_name="Win64"):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.globals().OS_NAME = os_name
    L.execute(STUB)
    with open(os.path.join(ROOT, "browser", "11b_hint_card.lua"), "rb") as fh:
        L.execute(fh.read())
    return L


def _rows(L, text):
    """Rows as python lists: (title?, [key atoms], [body words])."""
    rows = L.globals().hint_parse(text)
    out = []
    for i in range(1, len(rows) + 1):
        row = rows[i]
        keys = []
        if row["keys"]:
            for j in range(1, len(row["keys"]) + 1):
                a = row["keys"][j]
                if a.t == "key":
                    keys.append(a.s)
                elif a.t == "plus":
                    keys.append("+")
                else:
                    keys.append("mouse:" + a.btn + ("x2" if a.dbl else ""))
        body = []
        for j in range(1, len(row["body"]) + 1):
            a = row["body"][j]
            if a.t == "arrow":
                body.append("->")
            else:
                body.append(a.s if a.t == "text" else "[" + (a.s or ("mouse:" + a.btn)) + "]")
        out.append((bool(row.title), keys, " ".join(body)))
    return out


def test_modifier_and_mouse_combo_rows():
    L = _runtime()
    rows = _rows(L, "Paint and erase notes (Esc)\nAlt+LMB drag = stutter\nCtrl/Cmd+LMB drag on a note = copy")
    assert rows[0] == (True, [], "Paint and erase notes [Esc]")
    assert rows[1] == (False, ["Alt", "+", "mouse:L"], "drag -> stutter")
    assert rows[2] == (False, ["Ctrl", "+", "mouse:L"], "drag on a note -> copy")


def test_mac_labels():
    L = _runtime("macOS-arm64")
    rows = _rows(L, "Ctrl/Cmd+LMB drag on razor = copy notes\nAlt+RMB drag = razor edit")
    assert rows[0][1] == ["Cmd", "+", "mouse:L"]
    assert rows[1][1] == ["Opt", "+", "mouse:R"]


def test_dot_separated_items_and_mouse_words():
    L = _runtime()
    rows = _rows(L, "Kick 01\nClick: preview  ·  Double-click: replace this drum")
    assert rows[0] == (True, [], "Kick 01")
    assert rows[1] == (False, ["mouse:L"], "Click -> preview")
    assert rows[2] == (False, ["mouse:Lx2"], "Double-click -> replace this drum")


def test_prose_stays_prose():
    L = _runtime()
    rows = _rows(L, "A sample is here\nEnter a word to filter\nDrag")
    assert rows == [(True, [], "A sample is here"), (False, [], "Enter a word to filter"), (False, [], "Drag")]


def test_partial_combo_and_single_key_subject():
    L = _runtime()
    rows = _rows(L, "Tips\nShift+empty grid = place off-grid\nQ = enlarge hovered track")
    assert rows[1] == (False, ["Shift"], "empty grid -> place off-grid")
    assert rows[2] == (False, ["Q"], "enlarge hovered track")


def test_equals_inside_a_sentence_does_not_split_it():
    L = _runtime()
    rows = _rows(L, "Decay mode (D)\nDrag the last grid to set note length (Shift = unsnap)")
    assert rows[0] == (True, [], "Decay mode [D]")
    assert rows[1] == (False, ["mouse:L"], "Drag the last grid to set note length ( [Shift] = unsnap)")


def test_set_tooltip_draws_pinned_card_clear_of_the_control():
    L = _runtime()
    L.execute('''
      MOUSE = {40, 760}; ITEM = {20, 750, 80, 772}
      reaper.ImGui_SetTooltip(ctx, "Grid 1/16\\nAlt+LMB drag = stutter")
      NOW = 0.05; hint_card_flush()          -- still in the show delay
      reaper.ImGui_SetTooltip(ctx, "Grid 1/16\\nAlt+LMB drag = stutter")
      NOW = 0.3; hint_card_flush()
    ''')
    calls = [list(c.values()) for c in L.globals().CALLS.values()]
    names = [c[0] for c in calls]
    assert "ImGui_SetTooltip" not in names
    pos = [c for c in calls if c[0] == "ImGui_SetNextWindowPos"]
    assert len(pos) == 1
    x, y = pos[0][2], pos[0][3]
    # The control sits in the bottom-left corner, so the card moves elsewhere.
    assert not (x < 80 and y + 20 > 750)
    assert "ImGui_EndTooltip" in names
    assert any(n == "ImGui_DrawList_AddBezierCubic" for n in names)
    texts = [c[-1] for c in calls if c[0] == "ImGui_DrawList_AddText"]
    assert "Grid" in texts and "Alt" in texts and "stutter" in texts


def test_flush_without_request_draws_nothing():
    L = _runtime()
    L.execute("NOW = 1; hint_card_flush()")
    assert len(L.globals().CALLS) == 0

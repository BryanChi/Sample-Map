"""Tests for the fill designer (browser/34b_seq_fill_designer.lua): the fill
library, where fills land, inserting / re-auditioning / reverting fills, razor
areas, and a smoke render of the window. Requires `pip install lupa`."""
import os
import tempfile

from lupa import lua54

from test_pattern_library import STUB

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

MODULES = [
    "01_state.lua", "02_helpers.lua", "03_json.lua", "09_ui_helpers.lua", "11_ui_kit.lua",
    "11b_hint_card.lua", "18_seq_regions.lua", "19_seq_random.lua", "19b_seq_pattern_library.lua",
    "21_seq_notes.lua", "33_seq_generate.lua", "34_seq_pattern_popup.lua", "34b_seq_fill_designer.lua",
]

# A tiny sequencer: kick / snare / hat / crash tracks (no toms) and one
# 8-bar region with a plain backbeat groove.
WORLD = r'''
ctx = {}; log = function() end; save_config = function() end
SYNCED = {}
sync_seq_pattern_regions = function(pid) SYNCED[#SYNCED + 1] = pid end
seq_undo_stack = {}
local open_label = nil
begin_seq_undo = function(label) open_label = label; return label end
end_seq_undo = function(label) seq_undo_stack[#seq_undo_stack + 1] = { label = label }; open_label = nil end
seq_has_razors = function() return state.seq_razors and #state.seq_razors > 0 end
seq_note_is_locked = function(n) return type(n) == "table" and n.locked == true end
seq_cell_is_locked = function() return false end
seq_region_step_key = function() return "0" end
seq_select_region = function(reg) state.selected_seq_region_id = reg.id end
seq_region_is_linked = function() return false end
seq_unpool_region = function() end
get_seq_region_length_qn = function(region) return (region and region.length_bars or 4) * 4.0 end
find_sample_by_path = function(path) return { path = path, name = path } end
set_seq_note = function(region, track_id, key, note)
  get_track_note_table(get_seq_pattern(region.pattern_id, true), track_id, true)[tostring(key)] = note
end
local roles = { [1] = "kick", [2] = "snare", [3] = "hat", [4] = "crash" }
infer_seq_track_role = function(slot) return roles[slot.id] or "perc" end
state.seq_grid_qn = 0.25
state.seq_tracks = {
  { id = 1, sample_path = "/k.wav" }, { id = 2, sample_path = "/s.wav" },
  { id = 3, sample_path = "/h.wav" }, { id = 4, sample_path = "/c.wav" },
}
state.seq_patterns = {}
state.seq_regions = { { id = 1, pattern_id = 1, pool_id = 1, start_qn = 0.0, length_bars = 8, name = "Verse 1" } }
state.selected_seq_region_id = 1
state.seq_razors = {}
local function put(track, qn)
  local key = seq_alloc_note_key(state.seq_regions[1], track, qn)
  set_seq_note(state.seq_regions[1], track, key, { enabled = true, qn_offset = qn, sample_path = "x", groove = true })
end
for bar = 0, 7 do
  local b = bar * 4
  for beat = 0, 3 do put(1, b + beat) end         -- kick on every beat
  put(2, b + 1); put(2, b + 3)                     -- snare on 2 and 4
  for e = 0, 7 do put(3, b + e * 0.5) end          -- eighth hats
end

-- Notes on a track in [q0, q1): count, and whether any came from a fill.
function span(track, q0, q1)
  local n, fills, pitched = 0, 0, 0
  for _, note in pairs(state.seq_patterns["1"].notes[tostring(track)] or {}) do
    if note.qn_offset >= q0 - 1e-6 and note.qn_offset < q1 - 1e-6 then
      n = n + 1
      if note.fill then fills = fills + 1 end
      if (note.pitch or 0) ~= 0 then pitched = pitched + 1 end
    end
  end
  return n, fills, pitched
end
'''


def _runtime():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    tmp = tempfile.mkdtemp()
    L.globals().RES = tmp
    L.globals().SCRIPT_PATH = os.path.join(tmp, "Sample Map Browser.lua")
    L.globals().HOVER = False
    L.execute(STUB)
    for name in MODULES:
        with open(os.path.join(ROOT, "browser", name), "rb") as fh:
            L.execute(fh.read())
    L.execute(WORLD)
    return L


def test_fill_library_is_consistent():
    L = _runtime()
    problems = L.execute(r'''
      local out, seen, cats = {}, {}, {}
      for _, c in ipairs(SEQ_FILL_CATEGORIES) do cats[c.key] = 0 end
      for _, def in ipairs(SEQ_FILL_LIBRARY) do
        if seen[def.key] then out[#out + 1] = "duplicate " .. def.key end
        seen[def.key] = true
        if not cats[def.cat or ""] then out[#out + 1] = "no category " .. def.key
        else cats[def.cat] = cats[def.cat] + 1 end
        if not (def.len == 4 or def.len == 8 or def.len == 16 or def.len == 32) then
          out[#out + 1] = def.key .. " odd length " .. tostring(def.len)
        end
        for lane, s in pairs(def.lanes) do
          if not SEQ_FILL_LANE_DEFS[lane] then out[#out + 1] = def.key .. " unknown lane " .. lane end
          if #s ~= def.len then out[#out + 1] = def.key .. "." .. lane .. " is " .. #s .. " long" end
          if s:find("[^%.xXgrtR]") then out[#out + 1] = def.key .. "." .. lane .. " bad char" end
        end
        for _, lane in ipairs(SEQ_FILL_LANE_ORDER) do end
      end
      for key, n in pairs(cats) do if n == 0 then out[#out + 1] = "empty category " .. key end end
      for lane, ld in pairs(SEQ_FILL_LANE_DEFS) do
        if not SEQ_ROLE_LABELS[ld.role] then out[#out + 1] = "lane " .. lane .. " unknown role" end
        local listed = false
        for _, l in ipairs(SEQ_FILL_LANE_ORDER) do if l == lane then listed = true end end
        if not listed then out[#out + 1] = "lane " .. lane .. " missing from order" end
      end
      return table.concat(out, "\n")
    ''')
    assert problems == ""
    assert L.execute("return #SEQ_FILL_LIBRARY") >= 25


def test_spots_at_phrase_ends_and_region_end():
    L = _runtime()
    out = L.execute(r'''
      local reg = state.seq_regions[1]
      local function ends(o) return table.concat(seq_fill_region_spot_ends(reg, o), ",") end
      local six = { length_bars = 6 }
      return table.concat({
        ends({ phrase_on = true, phrase_bars = 4, end_on = true }),
        ends({ phrase_on = true, phrase_bars = 2, end_on = false }),
        ends({ phrase_on = false, phrase_bars = 4, end_on = true }),
        ends({ phrase_on = false, end_on = false }),
        table.concat(seq_fill_region_spot_ends(six, { phrase_on = true, phrase_bars = 4, end_on = false }), ","),
        table.concat(seq_fill_region_spot_ends(six, { phrase_on = true, phrase_bars = 4, end_on = true }), ","),
      }, "|")
    ''')
    assert out == "16.0,32.0|8.0,16.0,24.0,32.0|32.0||16.0|16.0,24.0"


def test_random_fills_are_reproducible_and_in_range():
    L = _runtime()
    bad = L.execute(r'''
      local out = {}
      for len = 1, 32 do
        for energy = 1, 6 do
          for seed = 1, 12 do
            local a = seq_fill_random_hits(len, seed * 101, energy)
            local b = seq_fill_random_hits(len, seed * 101, energy)
            if #a == 0 then out[#out + 1] = ("empty %d/%d/%d"):format(len, energy, seed) end
            if #a ~= #b then out[#out + 1] = "not reproducible" end
            for i, h in ipairs(a) do
              if h.pos < 0 or h.pos >= len then out[#out + 1] = "pos out of range" end
              if h.vol <= 0 or h.vol > 1.0 then out[#out + 1] = "vol " .. h.vol end
              if not SEQ_ROLE_LABELS[h.role] then out[#out + 1] = "role " .. tostring(h.role) end
              if b[i].pos ~= h.pos or b[i].role ~= h.role then out[#out + 1] = "differs" end
            end
          end
        end
      end
      return table.concat(out, "\n", 1, math.min(#out, 5))
    ''')
    assert bad == ""


def test_fit_keeps_the_ending():
    L = _runtime()
    out = L.execute(r'''
      local hits = seq_fill_library_hits(seq_fill_def("tom_bar"))  -- 16 long
      local short = seq_fill_fit_hits(hits, 16, 4)
      local long = seq_fill_fit_hits(seq_fill_library_hits(seq_fill_def("snare_beat")), 4, 16)
      local sp, lp = {}, {}
      for _, h in ipairs(short) do sp[#sp + 1] = h.pos .. h.lane end
      for _, h in ipairs(long) do lp[#lp + 1] = h.pos end
      return table.concat(sp, ",") .. "|" .. table.concat(lp, ",")
    ''')
    assert out == "0tom_floor,1tom_floor,2tom_floor,3tom_floor|12,13,14,15"


def test_insert_audition_and_revert():
    L = _runtime()
    out = L.execute(r'''
      local res = {}
      local before = clone_table_deep(state.seq_patterns)
      local f = seq_fill_state()
      f.open = true; f.mode = "region"; f.scope = "region"; f.region_id = 1
      f.phrase_on = true; f.phrase_bars = 4; f.end_on = true; f.len = "auto"; f.crash = true
      f.clear_others = false

      -- Tom fill with no tom track: toms fall back to snare, pitched.
      seq_fill_insert({ { kind = "fill", key = "tom_bar" } })
      local n, fills, pitched = span(2, 12, 16)
      res[#res + 1] = ("snare %d %d %d"):format(n, fills, pitched)
      res[#res + 1] = ("hat %d"):format((span(3, 12, 16)))       -- untouched
      res[#res + 1] = ("kick %d"):format((span(1, 12, 16)))      -- untouched
      res[#res + 1] = ("crash %d"):format((span(4, 16, 16.01)))  -- downbeat after bar 4
      res[#res + 1] = ("end %d"):format(select(2, span(2, 28, 32)))
      res[#res + 1] = tostring(seq_fill_session_active())

      -- Auditioning another fill first puts the groove back.
      seq_fill_insert({ { kind = "fill", key = "kick_run" } })
      res[#res + 1] = ("snare %d %d"):format(span(2, 12, 16))
      res[#res + 1] = ("kick %d %d"):format(span(1, 15, 16))
      res[#res + 1] = ("crash %d"):format((span(4, 0, 32)))

      seq_fill_revert()
      local same = true
      for k, v in pairs(before["1"].notes) do
        local a, b = 0, 0
        for _ in pairs(v) do a = a + 1 end
        for _ in pairs(state.seq_patterns["1"].notes[k] or {}) do b = b + 1 end
        if a ~= b then same = false end
      end
      for _, note in pairs(state.seq_patterns["1"].notes["2"]) do if note.fill then same = false end end
      res[#res + 1] = tostring(same) .. " " .. tostring(seq_fill_session_active())
      return table.concat(res, "|")
    ''')
    assert out == ("snare 16 16 12|hat 8|kick 4|crash 1|end 16|true"
                   "|snare 2 0|kick 4 4|crash 1|true false")


def test_another_edit_starts_a_new_session():
    L = _runtime()
    out = L.execute(r'''
      local f = seq_fill_state()
      f.open = true; f.mode = "region"; f.region_id = 1; f.phrase_on = false; f.end_on = true
      f.len = "auto"; f.crash = false
      seq_fill_insert({ { kind = "fill", key = "snare_beat" } })
      seq_undo_stack[#seq_undo_stack + 1] = { label = "Paint note" }  -- user edit
      local a = tostring(seq_fill_session_active())
      seq_fill_insert({ { kind = "fill", key = "kick_run" } })
      -- The snare fill stays, since the session restarted after the user's edit.
      return a .. " " .. select(2, span(2, 31, 32)) .. " " .. select(2, span(1, 31, 32))
    ''')
    assert out == "false 4 4"


def test_mix_cycles_over_spots_and_patterns_switch_groove():
    L = _runtime()
    out = L.execute(r'''
      local f = seq_fill_state()
      f.open = true; f.mode = "region"; f.region_id = 1
      f.phrase_on = true; f.phrase_bars = 2; f.end_on = true; f.len = "beat"; f.crash = false
      f.pick = "cycle"
      seq_fill_insert({ { kind = "fill", key = "kick_run" }, { kind = "fill", key = "hat_roll" } })
      local res = {}
      for _, e in ipairs({ 8, 16, 24, 32 }) do
        local _, kf = span(1, e - 1, e)
        local _, hf = span(3, e - 1, e)
        res[#res + 1] = kf .. "/" .. hf
      end
      seq_fill_keep()
      -- A pattern pick replaces every drum in the span with that groove
      -- (House has no snare; its clap lands on the snare track).
      f.phrase_on = false; f.len = "bar"
      seq_fill_insert({ { kind = "pattern", key = "house" } })
      local _, kick_fill = span(1, 28, 32)
      local _, snare_fill = span(2, 28, 32)
      res[#res + 1] = kick_fill .. "/" .. snare_fill
      return table.concat(res, " ")
    ''')
    assert out == "4/0 0/4 4/0 0/4 4/2"


def test_razor_area_only_touches_its_tracks():
    L = _runtime()
    out = L.execute(r'''
      local f = seq_fill_state()
      state.seq_razors = { { start_qn = 4, end_qn = 6, track_ids = { 3 } } }
      seq_fill_open_for_razor()
      f.len = "auto"; f.crash = true
      local spots = seq_fill_compute_spots()
      seq_fill_insert({}, { seed = 7, energy = 6 })
      local _, hat_fill = span(3, 4, 6)
      local hat_old = 0
      for _, n in pairs(state.seq_patterns["1"].notes["3"]) do
        if n.qn_offset >= 4 and n.qn_offset < 6 and n.groove then hat_old = hat_old + 1 end
      end
      local others = 0
      for _, t in ipairs({ 1, 2, 4 }) do others = others + select(2, span(t, 0, 32)) end
      return #spots .. " " .. spots[1].span_qn .. " " .. hat_old .. " " .. tostring(hat_fill > 0) .. " " .. others
    ''')
    assert out == "1 2.0 0 true 0"


def test_fill_window_renders_every_view():
    L = _runtime()
    err = L.execute(r'''
      seq_mark_text_input_item = function() end
      state.main_window_rect = { x = 0, y = 0, w = 800, h = 600 }
      local f = seq_fill_state()
      f.open = true; f.region_id = 1
      local views = {
        function() f.mode = "region"; f.scope = "region"; f.source = "fills" end,
        function() f.source = "patterns" end,
        function() f.scope = "all"; f.mix = { { kind = "fill", key = "tom_bar" }, { kind = "pattern", key = "trap" } } end,
        function() f.mode = "razor"; state.seq_razors = { { start_qn = 0, end_qn = 4, track_ids = { 1, 2 } } } end,
        function() f.mode = "razor"; state.seq_razors = {} end,
      }
      for pass = 1, 2 do
        HOVER = pass == 2
        for i, set in ipairs(views) do
          set()
          f.open = true
          local ok, e = xpcall(render_seq_fill_window, debug.traceback)
          if not ok then return "view " .. i .. ": " .. tostring(e) end
        end
      end
      seq_fill_insert({ { kind = "fill", key = "snare_two" } })
      f.mode = "region"; f.open = true
      local ok, e = xpcall(render_seq_fill_window, debug.traceback)
      if not ok then return "session: " .. tostring(e) end
      return ""
    ''')
    assert err == ""
    assert L.execute("return #DRAWN") > 100

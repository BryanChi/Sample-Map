"""Patterns window: apply with genre samples, and the Keep pattern samples
toggle (original <-> genre). Requires lupa."""
from test_kit_and_stem_fixes import _runtime, ROOT
import os


def _with_popup():
    L = _runtime()
    for name in ("21_seq_notes.lua", "34_seq_pattern_popup.lua"):
        with open(os.path.join(ROOT, "browser", name), "rb") as fh:
            L.execute(fh.read())
    # A fake kit: role -> sample path, applied through the real helpers' seams.
    L.execute(r'''
      KIT = { kick = "/orig_kick.wav", snare = "/orig_snare.wav" }
      ROLLS = 0
      collect_seq_kit_elements = function()
        local out = {}
        for _, role in ipairs({ "kick", "snare", "hat" }) do
          if KIT[role] then out[#out + 1] = { role = role, sample_path = KIT[role] } end
        end
        return out
      end
      randomize_seq_kit = function(genres)
        ROLLS = ROLLS + 1
        for role in pairs(KIT) do KIT[role] = "/" .. genres[1] .. "_" .. role .. ".wav" end
        return 2
      end
      apply_seq_kit_history_element = function(el)
        if KIT[el.role] == el.sample_path then return false end
        KIT[el.role] = el.sample_path
        return true
      end
      begin_seq_undo = function(l) return l end
      end_seq_undo = function() end
      sync_seq_pattern_regions = function() end
      sm_notify = function(msg) LAST_NOTIFY = msg end
      REGION = { id = 7, pattern_id = 3, kit_genres = { "hiphop" } }
      get_seq_region_by_id = function(id) if id == 7 then return REGION end end
      state.seq_patterns = { ["3"] = { notes = {} } }
    ''')
    return L


def test_pattern_only_keeps_samples():
    L = _with_popup()
    kick, rolls, swapped = L.execute(r'''
      seq_pattern_confirm_capture(REGION)
      seq_pattern_request_swap(false)
      seq_pattern_finish_apply(REGION)
      return KIT.kick, ROLLS, state.seq_pattern_confirm.swapped
    ''')
    assert kick == "/orig_kick.wav" and rolls == 0 and swapped is False


def test_swap_then_toggle_between_original_and_genre():
    L = _with_popup()
    out = L.execute(r'''
      seq_pattern_confirm_capture(REGION)
      seq_pattern_request_swap(true)
      KIT.hat = "/new_track_hat.wav"   -- track the pattern just added
      seq_pattern_finish_apply(REGION)
      local a = KIT.kick
      seq_pattern_confirm_toggle_samples()
      local b, hat = KIT.kick, KIT.hat
      seq_pattern_confirm_toggle_samples()
      local c = KIT.kick
      return a, b, hat, c, ROLLS, state.seq_pattern_swap_next
    ''')
    assert out[0] == "/hiphop_kick.wav"
    assert out[1] == "/orig_kick.wav" and out[2] == "/new_track_hat.wav"
    # Toggling back reuses the same genre kit instead of rolling a new one.
    assert out[3] == "/hiphop_kick.wav" and out[4] == 1
    assert out[5] is None


def test_toggle_swaps_after_pattern_only_and_x_restores():
    L = _with_popup()
    out = L.execute(r'''
      seq_pattern_confirm_capture(REGION)
      seq_pattern_request_swap(false)
      seq_pattern_finish_apply(REGION)
      seq_pattern_confirm_toggle_samples()
      local a = KIT.snare
      seq_pattern_confirm_restore()
      return a, KIT.snare, state.seq_pattern_confirm == nil
    ''')
    assert out == ("/hiphop_snare.wav", "/orig_snare.wav", True)


def test_no_genre_keeps_samples_and_warns():
    L = _with_popup()
    kick, note = L.execute(r'''
      REGION.kit_genres = nil
      REGION.style_key = nil
      seq_pattern_confirm_capture(REGION)
      seq_pattern_request_swap(true)
      seq_pattern_finish_apply(REGION)
      return KIT.kick, LAST_NOTIFY
    ''')
    assert kick == "/orig_kick.wav" and "No genre" in note


def test_click_default_setting_persists():
    L = _with_popup()
    out = L.execute(r'''
      local store = {}
      reaper.GetExtState = function(s, k) return store[k] or "" end
      reaper.SetExtState = function(s, k, v) store[k] = v end
      state.seq_pattern_swap_samples = nil
      local before = seq_pattern_swap_default()
      seq_pattern_set_swap_default(true)
      state.seq_pattern_swap_samples = nil
      seq_pattern_request_swap(nil)
      return before, seq_pattern_swap_default(), state.seq_pattern_swap_next
    ''')
    assert out == (False, True, True)


def test_keep_pattern_bar_renders_both_states():
    from test_pattern_library import _runtime as full_runtime
    L = full_runtime()
    err = L.execute(r'''
      get_seq_region_by_id = function() return { id = 1, pattern_id = 1, kit_genres = { "house" } } end
      for pass = 1, 4 do
        HOVER = pass % 2 == 0
        state.seq_pattern_confirm = { active = true, region_id = 1, pattern_id = 1, swapped = pass > 2,
          swapped_genres = "house" }
        for _, w in ipairs({ 330, 160 }) do
          local ok, e = xpcall(render_seq_pattern_confirm_bar, debug.traceback, {}, 0, 0, w, 34)
          if not ok then return tostring(e) end
        end
      end
      return ""
    ''')
    assert err == ""

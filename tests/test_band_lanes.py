"""Band lanes (browser/42d_band_lanes.lua): Song Starter roles as lanes under the
sequencer's drum tracks. Section rules, picking (key, tempo, kit genre bias),
repeat linking and unlinking, locks, item placement maths, items following
region edits, persistence, sequencer undo and Song Starter's OPEN IN
SEQUENCER. Runs the browser with a stub REAPER. Requires `pip install lupa`."""
from test_song_starter import _runtime, FAKE_PROJECT

BAND_PROJECT = FAKE_PROJECT + r'''
  PEXT = {}
  reaper.SetProjExtState = function(_, s, k, v) PEXT[s .. "/" .. k] = v; return 1 end
  reaper.GetProjExtState = function(_, s, k) local v = PEXT[s .. "/" .. k]; return v and 1 or 0, v or "" end
  get_current_project = function() return "PROJ" end
  reaper.TimeMap2_QNToTime = function(_, qn) return qn * 0.5 end   -- 120 bpm
  reaper.TimeMap2_timeToQN = function(_, t) return t * 2.0 end
  local guid_n = 0
  reaper.GetTrackGUID = function(tr)
    if not tr.guid then guid_n = guid_n + 1; tr.guid = "{T" .. guid_n .. "}" end
    return tr.guid
  end
  reaper.SetMediaTrackInfo_Value = function(tr, k, v) tr[k] = v; if k == "I_FOLDERDEPTH" then tr.depth = v end end
  reaper.GetMediaTrackInfo_Value = function(tr, k)
    if k == "I_FOLDERDEPTH" then return tr.depth or 0 end
    if k == "IP_TRACKNUMBER" then
      for i, t in ipairs(TRACKS) do if t == tr then return i end end
      return 0
    end
    return tr[k] or 0
  end
  reaper.DeleteTrack = function(tr)
    for i, t in ipairs(TRACKS) do if t == tr then table.remove(TRACKS, i) break end end
  end
  reaper.CountTrackMediaItems = function(tr) return #tr.items end
  reaper.GetTrackMediaItem = function(tr, i) return tr.items[i + 1] end
  reaper.DeleteTrackMediaItem = function(tr, it)
    for i, x in ipairs(tr.items) do if x == it then table.remove(tr.items, i) break end end
    it.deleted = true
  end
  reaper.GetSetMediaItemInfo_String = function(it, k, v, set) if set then it[k] = v end return true, it[k] or "" end
  reaper.AddMediaItemToTrack = function(tr)
    local it = { tr = tr }; tr.items[#tr.items + 1] = it; ITEMS[#ITEMS + 1] = it; return it
  end
  -- Melodic loops at 120 bpm in A minor / C major, a hip-hop set and others.
  mk("/lib/Bass/Bass Groove 120bpm Am.wav", 8.0, { "bass", "loop" })
  mk("/lib/Bass/Deep Bass 120bpm Em.wav", 8.0, { "bass", "loop" })
  mk("/lib/Bass/Boom Bass 120bpm Am.wav", 8.0, { "bass", "loop", "hiphop" })
  mk("/lib/Keys/Organ Chords 120bpm Am.wav", 8.0, { "keys", "loop" })
  mk("/lib/Keys/Dusty Keys 120bpm Am.wav", 8.0, { "keys", "loop", "hiphop" })
  mk("/lib/Keys/Soul Chords 120bpm Gm.wav", 8.0, { "keys", "loop" })
  mk("/lib/Lead/Pluck Melody 120bpm Am.wav", 8.0, { "lead", "loop" })
  mk("/lib/Lead/Flute Lead 120bpm Em.wav", 8.0, { "lead", "loop", "hiphop" })
  mk("/lib/Lead/Bell Hook 120bpm C.wav", 8.0, { "lead", "loop" })
  rebuild_samples_path_index()
  state.seq_regions = {
    { id = 1, name = "Intro", start_qn = 0, length_bars = 4 },
    { id = 2, name = "Verse 1", start_qn = 16, length_bars = 8 },
    { id = 3, name = "Chorus 1", start_qn = 48, length_bars = 8 },
    { id = 4, name = "Verse 2", start_qn = 80, length_bars = 8 },
    { id = 5, name = "Chorus 2", start_qn = 112, length_bars = 8 },
  }
  state.selected_seq_region_id = 1
  state.seq_band = band_new_state()
  ss_state().chaos = 0.0
  function lane_of(role)
    for _, l in ipairs(state.seq_band.lanes) do if l.role == role then return l end end
  end
  function cell_of(role, region_id)
    local b = state.seq_band
    local _, _, c = band_cell_info(b, lane_of(role), get_seq_region_by_id(region_id))
    return c
  end
  function track_items(role)
    local tr = band_lane_track(lane_of(role))
    local out = {}
    for _, it in ipairs(tr and tr.items or {}) do out[#out + 1] = it end
    table.sort(out, function(a, b) return a.D_POSITION < b.D_POSITION end)
    return out
  end
'''


def _band():
    L = _runtime()
    L.execute(BAND_PROJECT)
    return L


def test_section_rules_follow_song_starter_presence():
    L = _band()
    got = L.execute(r'''
      local function plays(role, name) return band_default_part(role, name, 8) ~= nil end
      local build_lead = band_default_part("lead", "Build", 8)
      return plays("chords", "Intro"), plays("bass", "Intro"), plays("lead", "Intro"),
             plays("bass", "Verse 2"), plays("chords", "Verse 2"), plays("lead", "Verse 2"),
             plays("lead", "Chorus 1"), plays("bass", "Drop"),
             plays("bass", "Breakdown"), plays("lead", "Bridge"),
             plays("lead", "Region 4"), build_lead.from, build_lead.vol,
             band_group_key(state.seq_band, get_seq_region_by_id(3)),
             band_group_key(state.seq_band, get_seq_region_by_id(5)),
             band_group_key(state.seq_band, { id = 9, name = "Region 9" })
    ''')
    (ch_intro, bass_intro, lead_intro, bass_verse, ch_verse, lead_verse, lead_chorus, bass_drop,
     bass_break, lead_bridge, lead_unnamed, build_from, build_vol, g3, g5, g9) = got
    assert ch_intro and not bass_intro and not lead_intro          # intro = chords only
    assert bass_verse and ch_verse and not lead_verse              # verse adds bass
    assert lead_chorus and bass_drop                               # chorus / drop: everyone
    assert not bass_break and lead_bridge                          # breakdown thins out
    assert lead_unnamed                                            # no section name: all play
    assert build_from == 4 and abs(build_vol - 0.6) < 1e-9         # lead enters halfway
    assert g3 == "chorus" and g5 == "chorus" and g9 == "r9"


def test_band_on_builds_folder_lanes_and_placed_items():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local b = state.seq_band
      local folder = band_folder_track(b, false)
      local names = {}
      for i, t in ipairs(TRACKS) do names[i] = (t.P_NAME or "?") .. ":" .. tostring(t.depth) end
      local chords, bass, lead = track_items("chords"), track_items("bass"), track_items("lead")
      local c1 = chords[1]
      local ok_items = true
      for _, it in ipairs(chords) do
        if it.B_LOOPSRC ~= 1 or it.take.B_PPITCH ~= 1 or not it[BAND_EXT_ITEM]:match("^%d+|%d+$") then ok_items = false end
      end
      return #b.lanes, folder.P_NAME, table.concat(names, ","), #chords, #bass, #lead,
             c1.D_POSITION, c1.D_LENGTH, bass[1].D_POSITION, lead[1].D_POSITION, lead[1].D_LENGTH,
             ok_items, b.key, b.on, UNDO[#UNDO], #seq_undo_stack
    ''')
    (n_lanes, folder, names, n_ch, n_bass, n_lead, c_pos, c_len, b_pos, l_pos, l_len, ok_items, key, on, undo,
     stack) = got
    assert n_lanes == 3 and folder == "Band"
    assert names == "Band:1,Bass:0,Chords:0,Lead:-1"
    assert n_ch == 5 and n_bass == 4 and n_lead == 2     # chords everywhere, bass not in the intro, lead only in choruses
    assert c_pos == 0 and c_len == 8.0                   # 4 bars at 120 bpm
    assert b_pos == 8.0                                  # Verse 1 starts at qn 16
    assert l_pos == 24.0 and l_len == 16.0               # Chorus 1, 8 bars
    assert ok_items and on is True and key is not None
    assert undo == "Sample Map: band on" and stack == 1


def test_repeats_share_a_loop_until_unlinked():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local lead = lane_of("lead")
      local same0 = cell_of("lead", 3) == cell_of("lead", 5)
      local before = cell_of("lead", 3).path
      band_ui_roll_cell(lead.id, 3)
      local after = cell_of("lead", 3).path
      local items = track_items("lead")
      local items_same = items[1].take.src.path == after and items[2].take.src.path == after
      band_ui_toggle_link(5)
      local unlinked = state.seq_band.unlinked["5"] == true
      local copy_same = cell_of("lead", 5).path == after and cell_of("lead", 5) ~= cell_of("lead", 3)
      band_ui_roll_cell(lead.id, 3)
      local c3, c5 = cell_of("lead", 3).path, cell_of("lead", 5).path
      band_ui_toggle_link(5)
      local relinked = cell_of("lead", 5) == cell_of("lead", 3)
      return same0, before ~= after, items_same, unlinked, copy_same, c3 ~= c5, c5 == after, relinked
    ''')
    assert list(got) == [True] * 8


def test_locks_keep_loops_through_rolls():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local bass, chords = lane_of("bass"), lane_of("chords")
      band_ui_lock_cell(chords.id, 2)          -- Verse 1 (and Verse 2) chords
      band_ui_lock_lane(bass.id)
      local ch_verse, ch_chorus = cell_of("chords", 2).path, cell_of("chords", 3).path
      local bass_paths = {}
      for k, c in pairs(state.seq_band.cells) do if k:match("^" .. bass.id .. ":") then bass_paths[k] = c.path end end
      for i = 1, 3 do band_ui_roll_all() end
      local bass_same = true
      for k, p in pairs(bass_paths) do if state.seq_band.cells[k].path ~= p then bass_same = false end end
      local before_lane_roll = cell_of("bass", 2).path
      band_ui_roll_lane(bass.id)                -- explicit lane roll still works on a locked lane
      return cell_of("chords", 2).path == ch_verse, cell_of("chords", 4).path == ch_verse,
             cell_of("chords", 3).path ~= ch_chorus, bass_same, cell_of("chords", 2).locked
    ''')
    keep_verse, keep_repeat, chorus_rolled, bass_same, locked = got
    assert keep_verse and keep_repeat and bass_same and locked
    assert chorus_rolled


def test_clear_and_add_cells():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local lead, bass = lane_of("lead"), lane_of("bass")
      local n0 = #track_items("lead")
      band_ui_clear_cell(lead.id, 3)                       -- lead sits out both choruses
      local n1 = #track_items("lead")
      band_ui_roll_cell(bass.id, 1)                        -- bass joins the intro (empty cell click)
      local intro_bass = track_items("bass")[1]
      return n0, n1, cell_of("lead", 3).off, intro_bass.D_POSITION, cell_of("bass", 1).on
    ''')
    assert list(got) == [2, 0, True, 0.0, True]


def test_item_spec_stretches_and_pitches_to_the_band():
    L = _band()
    got = L.execute(r'''
      local b = state.seq_band
      b.key = "Am"
      local lane = { id = 1, role = "bass", vol = 0.5 }
      local cell = { path = "/x.wav", name = "x", src_bpm = 90, src_key = "Cm", dur = 10.667 }
      local reg = get_seq_region_by_id(2)
      local w = band_item_spec(b, lane, cell, reg, { from = 2, to = 6, vol = 0.8, rise = true })
      local cell2 = { path = "/y.wav", src_bpm = 240, src_key = "Am" }
      local w2 = band_item_spec(b, lane, cell2, reg, { from = 0, to = 8, vol = 1 })
      local cell3 = { path = "/z.wav", src_bpm = 120, src_key = "Cm", from_role = "drums" }
      local w3 = band_item_spec(b, lane, cell3, reg, { from = 0, to = 8, vol = 1 })
      return w.pos, w.len, w.rate, w.shift, w.vol, w.rise, w.tag, w2.rate, w2.shift, w3.shift
    ''')
    pos, length, rate, shift, vol, rise, tag, rate2, shift2, shift3 = got
    assert pos == 8.0 + 2 * 2.0 and length == 4 * 2.0      # bars 2..6 of Verse 1 at 120 bpm
    assert abs(rate - 120 / 90) < 1e-9                      # straight stretch beats half time here
    assert shift == -3                                      # C minor -> A minor
    assert abs(vol - 0.4) < 1e-9 and rise is True and tag == "1|2"
    assert abs(rate2 - 1.0) < 1e-9 and shift2 == 0          # 240 bpm counts as double time
    assert shift3 == 0                                      # a drum loop in the lane is not pitched


def test_picks_lean_to_the_region_kit_genre():
    L = _band()
    got = L.execute(r'''
      local pool = ss_loop_pool(ss_state())
      local hits, n = 0, 60
      local genres = band_genre_set({ kit_genres = { "HipHop" } })
      for i = 1, n do
        local c = band_pick("chords", { pool = pool, bpm = 120, key = "Am", chaos = 0, genres = genres })
        if c and c.path:find("Dusty", 1, true) then hits = hits + 1 end
      end
      local plain = 0
      for i = 1, n do
        local c = band_pick("chords", { pool = pool, bpm = 120, key = "Am", chaos = 0 })
        if c and c.path:find("Dusty", 1, true) then plain = plain + 1 end
      end
      return hits, plain, n
    ''')
    hits, plain, n = got
    assert hits > n * 0.6 and hits > plain


def test_items_follow_region_moves_resizes_and_deletes():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local tr = band_lane_track(lane_of("chords"))
      local user = { tr = tr, D_POSITION = 99 }
      tr.items[#tr.items + 1] = user                    -- the user's own item stays
      local reg = get_seq_region_by_id(2)
      reg.start_qn, reg.length_bars = 20, 4
      seq_band_tick()
      local verse = nil
      for _, it in ipairs(track_items("chords")) do
        if it[BAND_EXT_ITEM] and it[BAND_EXT_ITEM]:match("|2$") then verse = it end
      end
      local n_before = #track_items("chords")
      table.remove(state.seq_regions, 1)                -- delete the intro
      seq_band_tick()
      local n_after = #track_items("chords")
      local writes = band_sync_items(state.seq_band)    -- nothing changed: nothing written
      state.seq_regions[#state.seq_regions + 1] = { id = 6, name = "Outro", start_qn = 144, length_bars = 4 }
      seq_band_tick()
      local outro = false
      for _, it in ipairs(track_items("chords")) do
        if it[BAND_EXT_ITEM] and it[BAND_EXT_ITEM]:match("|6$") then outro = it.D_POSITION end
      end
      local still_user = false
      for _, it in ipairs(tr.items) do if it == user then still_user = true end end
      return verse.D_POSITION, verse.D_LENGTH, n_before, n_after, writes, outro, still_user
    ''')
    pos, length, n_before, n_after, writes, outro, still_user = got
    assert pos == 10.0 and length == 8.0
    assert n_before == 6 and n_after == 5          # 5 regions + the user's item, then the intro goes
    assert writes == 0
    assert outro == 72.0                            # the new outro got its own pick
    assert still_user


def test_state_persists_in_the_project_and_reloads():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      band_ui_set_key("Dm")
      local text = PEXT[PROJ_EXT_SECTION .. "/" .. BAND_EXT_KEY]
      local paths = cell_of("chords", 3).path
      state.seq_band = band_new_state()
      band_load("PROJ")
      local b = state.seq_band
      return text ~= nil, #b.lanes, b.key, b.key_auto, b.on, cell_of("chords", 3).path == paths,
             lane_of("bass").guid ~= nil
    ''')
    assert list(got) == [True, 3, "Dm", False, True, True, True]


def test_reaper_undo_of_the_ext_state_reloads_the_band():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local saved = PEXT[PROJ_EXT_SECTION .. "/" .. BAND_EXT_KEY]
      band_ui_set_key("Em")
      -- REAPER's own undo puts the older text back and bumps the change count.
      PEXT[PROJ_EXT_SECTION .. "/" .. BAND_EXT_KEY] = saved
      reaper.GetProjectStateChangeCount = function() return 77 end
      seq_band_tick()
      return state.seq_band.key ~= "Em"
    ''')
    assert got is True


def test_sequencer_undo_takes_back_a_lane_and_its_track():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      band_ui_add_lane("texture")
      local n_tracks = #TRACKS
      local has = lane_of("texture") ~= nil
      seq_undo()
      local gone = lane_of("texture") == nil
      local tracks_after = #TRACKS
      local bass_track = band_lane_track(lane_of("bass")) ~= nil
      return has, n_tracks, gone, tracks_after, bass_track, UNDO[#UNDO - 2]
    ''')
    has, n_tracks, gone, tracks_after, bass_track, label = got
    assert has and gone and bass_track
    assert tracks_after == n_tracks - 1
    assert label == "Sample Map: band add Texture"


def test_open_in_sequencer_turns_the_starter_into_lanes():
    L = _band()
    got = L.execute(r'''
      local st = ss_state()
      st.target_bpm, st.key_auto, st.target_key = 120, false, "Am"
      ss_do_reroll("batch")
      local bass_slot, lead_slot
      for _, s in ipairs(st.slots) do
        if s.role == "bass" then bass_slot = s end
        if s.role == "lead" then lead_slot = s end
      end
      bass_slot.locked = true
      state.active_view = "sample_map"
      band_from_song_starter()
      local roles = {}
      for _, l in ipairs(state.seq_band.lanes) do roles[#roles + 1] = l.role end
      return table.concat(roles, ","), cell_of("bass", 2).path == bass_slot.path, cell_of("bass", 2).locked,
             lead_slot.path == nil or cell_of("lead", 3).path == lead_slot.path, state.seq_band.key,
             state.active_view, state.seq_band.on, UNDO[#UNDO]
    ''')
    roles, bass_ok, locked, lead_ok, key, view, on, undo = got
    assert "drums" not in roles.split(",") and "bass" in roles.split(",")
    assert bass_ok and locked is True and lead_ok
    assert key == "Am" and view == "sequencer" and on is True
    assert undo == "Sample Map: band from Song Starter"


def test_band_draws_without_errors_and_reserves_height():
    L = _band()
    got = L.execute(r'''
      band_set_on(true)
      local h = seq_band_height()
      local ok, err = pcall(seq_band_draw, {
        x0 = 0, w = 1000, tx0 = 300, tx1 = 1000, y0 = 100, view_qn0 = 0, qn_span = 160,
        qn_to_x = function(q) return 300 + q / 160 * 700 end, region = get_seq_region_by_id(1), playhead_qn = 10,
      })
      local cap = band_caption(state.seq_band, { kit_genres = { "HipHop" } })
      state.seq_band.on = false
      return h, ok, tostring(err), seq_band_height(), cap
    ''')
    h, ok, err, h_off, cap = got
    assert h == 22 + 3 * 44 + 22
    assert ok, err
    assert h_off == 0
    assert cap.startswith("Band fits: 120 BPM · ") and cap.endswith("hiphop kit")

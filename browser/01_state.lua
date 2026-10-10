-- Sample Map Browser module: state
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Script state ------------------------------------------------------------
SCRIPT_NAME = "Sample Map Browser"
-- Resolve from the main script's path (modules run with the main script's action context).
SCRIPT_DIR = (select(2, r.get_action_context()) or ""):match("^(.+)[/\\][^/\\]+$")
  or (r.GetResourcePath() .. "/Scripts/Sample Map")
SAMPLE_MAP_SCRIPT_DIR = SCRIPT_DIR
do
  local ok_update = pcall(dofile, SCRIPT_DIR .. "/SampleMapUpdate.lua")
  if not ok_update then
    -- Updater is optional; the rest of the script still runs.
  end
end
do
  local ok_stem = pcall(dofile, SCRIPT_DIR .. "/SampleMapStemImport.lua")
  if not ok_stem then
    -- Stem-split import is optional until Stem Split is installed.
  end
end
CONFIG_DIR = SCRIPT_DIR
CONFIG_PATH = CONFIG_DIR .. "/SampleMapBrowser.json"
DATA_PATH = SCRIPT_DIR .. "/SampleMapData.json"  -- Cached sample index (JSON, compatibility)
DATA_LUA_PATH = SCRIPT_DIR .. "/SampleMapData.cache.lua"  -- Fast Lua table cache
-- Behringer mixer instrument icons (see assets/behringer-icons/ATTRIBUTION.md)
-- Kept global to avoid Lua's 200-local main-chunk limit.
-- New module-level helpers/constants should be globals or live on `state`, not `local`.
SEQ_ICON_DIR = SCRIPT_DIR .. "/assets/behringer-icons/png"
VFX_ICON_DIR = SCRIPT_DIR .. "/assets/vertical-fx-icons"
FXD_ICON_DIR = SCRIPT_DIR .. "/assets/fx-device-icons"
-- Bump when genre/loop/library-folder inference rules change and caches must be re-tagged.
TAG_SCHEMA_VERSION = 4
LIBRARY_LOAD_SLICE_MS = 10.0
PROJ_EXT_SECTION = "SampleMapBrowser"
PROJ_EXT_KEY_SEQUENCER = "SequencerStateV1"

AUDIO_EXTS = {
  [".wav"] = true, [".wave"] = true, [".aif"] = true, [".aiff"] = true,
  [".flac"] = true, [".mp3"] = true, [".ogg"] = true, [".m4a"] = true, [".wv"] = true
}

-- Common tag keywords (ordered by priority for tagging)
TAG_KEYWORDS = {
  {tag = "kick",   keys = {"kick", "kck"}, weight = 100},
  {tag = "snare",  keys = {"snare", "snr"}, weight = 95},
  {tag = "clap",   keys = {"clap"}, weight = 92},
  {tag = "snap",   keys = {"snap", "finger", "finger snap", "finger snaps", "fingersnap", "fingersnaps"}, weight = 91},
  {tag = "rim",    keys = {"rim", "rimshot"}, weight = 90},
  {tag = "hat",    keys = {"hat", "hihat", "oh", "ch", "hh"}, weight = 88},
  {tag = "tom",    keys = {"tom"}, weight = 82},
  {tag = "ride",   keys = {"ride"}, weight = 80},
  {tag = "crash",  keys = {"crash", "cymbal"}, weight = 79},
  {tag = "perc",   keys = {"perc", "percussion", "shaker", "tamb", "cowbell"}, weight = 76},
  {tag = "fx",     keys = {"fx", "sfx", "impact", "whoosh", "sweep", "riser", "uplift", "downlift"}, weight = 74},
  {tag = "bass",   keys = {"bass", "sub"}, weight = 70},
  {tag = "808s",   keys = {"808s", "808"}, weight = 69},
  {tag = "vocal",  keys = {"vocal", "vox", "voice"}, weight = 65},
  {tag = "drum",   keys = {"drum", "beat", "break"}, weight = 58},
  {tag = "pad",    keys = {"pad"}, weight = 55},
  {tag = "lead",   keys = {"lead"}, weight = 54},
  {tag = "pluck",  keys = {"pluck"}, weight = 53},
  {tag = "keys",   keys = {"keys", "piano"}, weight = 52},
  {tag = "guitar", keys = {"guitar"}, weight = 50},
}

-- O(1) tag → weight for map colors (avoids nested TAG_KEYWORDS scans per sample)
TAG_KEYWORD_WEIGHT = {}
do
  for _, entry in ipairs(TAG_KEYWORDS) do
    TAG_KEYWORD_WEIGHT[entry.tag] = entry.weight or 0
  end
  TAG_KEYWORD_WEIGHT["808"] = TAG_KEYWORD_WEIGHT["808s"] or 69
end

-- Genre words detected from pack/folder names in the user's library.
-- More specific keys first within each entry; kept separate from TAG_KEYWORDS
-- so genres don't compete for instrument tags or map dot colors.
GENRE_KEYWORDS = {
  -- Multi-word / compound (check before shorter overlaps)
  {tag = "drum and bass",   keys = {"drum and bass", "drumandbass", "dnb", "d&b"}},
  {tag = "future bass",     keys = {"future bass", "futurebass"}},
  {tag = "future soul",     keys = {"future soul", "futuresoul"}},
  {tag = "future garage",   keys = {"future garage", "futuregarage", "2step", "two step"}},
  {tag = "deep house",      keys = {"deep house", "deephouse"}},
  {tag = "tech house",      keys = {"tech house", "techhouse"}},
  {tag = "progressive house", keys = {"progressive house", "progressivehouse", "prog house"}},
  {tag = "acid house",      keys = {"acid house", "acidhouse"}},
  {tag = "tropical house",  keys = {"tropical house", "tropicalhouse"}},
  {tag = "electro house",   keys = {"electro house", "electrohouse"}},
  {tag = "bass house",      keys = {"bass house", "basshouse"}},
  {tag = "slap house",      keys = {"slap house", "slaphouse"}},
  {tag = "afro house",      keys = {"afro house", "afrohouse"}},
  {tag = "melodic house",   keys = {"melodic house", "melodichouse"}},
  {tag = "organic house",   keys = {"organic house", "organichouse"}},
  {tag = "speed garage",    keys = {"speed garage", "speedgarage"}},
  {tag = "jersey club",     keys = {"jersey club", "jerseyclub", "jersey"}},
  {tag = "baltimore club",  keys = {"baltimore club", "baltimoreclub", "bmore"}},
  {tag = "hip hop",         keys = {"hip hop", "hiphop", "hip-hop"}},
  {tag = "boom bap",        keys = {"boom bap", "boombap"}},
  {tag = "cloud rap",       keys = {"cloud rap", "cloudrap"}},
  {tag = "emo rap",         keys = {"emo rap", "emorap"}},
  {tag = "trap soul",       keys = {"trap soul", "trapsoul"}},
  {tag = "uk drill",        keys = {"uk drill", "ukdrill"}},
  {tag = "ny drill",        keys = {"ny drill", "nydrill", "new york drill"}},
  {tag = "liquid dnb",      keys = {"liquid dnb", "liquiddnb", "liquid drum and bass"}},
  {tag = "jump up",         keys = {"jump up", "jumpup"}},
  {tag = "goa trance",      keys = {"goa trance", "goatrance", "goa"}},
  {tag = "psytrance",       keys = {"psytrance", "psy trance", "psy-trance"}},
  {tag = "hardstyle",       keys = {"hardstyle", "hard style"}},
  {tag = "happy hardcore",  keys = {"happy hardcore", "happyhardcore"}},
  {tag = "nu disco",        keys = {"nu disco", "nudisco", "nu-disco"}},
  {tag = "synthwave",       keys = {"synthwave", "synth wave", "retrowave", "outrun"}},
  {tag = "chillwave",       keys = {"chillwave", "chill wave"}},
  {tag = "vaporwave",       keys = {"vaporwave", "vapor wave"}},
  {tag = "witch house",     keys = {"witch house", "witchhouse"}},
  {tag = "dark wave",       keys = {"dark wave", "darkwave"}},
  {tag = "new wave",        keys = {"new wave", "newwave"}},
  {tag = "dream pop",       keys = {"dream pop", "dreampop"}},
  {tag = "post punk",       keys = {"post punk", "postpunk", "post-punk"}},
  {tag = "trap metal",      keys = {"trap metal", "trapmetal"}},
  {tag = "baile funk",      keys = {"baile funk", "bailefunk"}},
  {tag = "zouk bass",       keys = {"zouk bass", "zoukbass"}},
  {tag = "bossa nova",      keys = {"bossa nova", "bossanova"}},
  {tag = "big room",        keys = {"big room", "bigroom"}},
  {tag = "color bass",      keys = {"color bass", "colorbass"}},
  {tag = "ghetto tech",     keys = {"ghetto tech", "ghettotech"}},
  {tag = "afrobeat",        keys = {"afrobeat", "afrobeats", "afro beat"}},
  {tag = "downtempo",       keys = {"downtempo", "down tempo"}},
  {tag = "lofi",            keys = {"lofi", "lo-fi", "lo fi"}},

  -- Electronic / dance (single-word and short)
  {tag = "house",           keys = {"house"}},
  {tag = "techno",          keys = {"techno"}},
  {tag = "trance",          keys = {"trance"}},
  {tag = "disco",           keys = {"disco"}},
  {tag = "garage",          keys = {"garage", "ukg"}},
  {tag = "grime",           keys = {"grime"}},
  {tag = "dubstep",         keys = {"dubstep"}},
  {tag = "riddim",          keys = {"riddim"}},
  {tag = "brostep",         keys = {"brostep"}},
  {tag = "neurofunk",       keys = {"neurofunk", "neuro funk"}},
  {tag = "jungle",          keys = {"jungle"}},
  {tag = "breakbeat",       keys = {"breakbeat", "break beat", "breaks"}},
  {tag = "breakcore",       keys = {"breakcore"}},
  {tag = "hardcore",        keys = {"hardcore"}},
  {tag = "gabber",          keys = {"gabber"}},
  {tag = "midtempo",        keys = {"midtempo", "mid tempo"}},
  {tag = "halftime",        keys = {"halftime", "half time"}},
  {tag = "moombahton",      keys = {"moombahton"}},
  {tag = "footwork",        keys = {"footwork"}},
  {tag = "juke",            keys = {"juke"}},
  {tag = "phonk",           keys = {"phonk"}},
  {tag = "trap",            keys = {"trap"}},
  {tag = "drill",           keys = {"drill"}},
  {tag = "hyperpop",        keys = {"hyperpop", "hyper pop"}},
  {tag = "ambient",         keys = {"ambient"}},
  {tag = "chillout",        keys = {"chillout", "chill out"}},
  {tag = "chill",           keys = {"chill"}},
  {tag = "electro",         keys = {"electro"}},
  {tag = "edm",             keys = {"edm"}},
  {tag = "minimal",         keys = {"minimal"}},
  {tag = "glitch",          keys = {"glitch"}},
  {tag = "idm",             keys = {"idm"}},
  {tag = "industrial",      keys = {"industrial"}},
  {tag = "ebm",             keys = {"ebm"}},
  {tag = "synthpop",        keys = {"synthpop", "synth pop"}},
  {tag = "hardwave",        keys = {"hardwave", "hard wave"}},

  -- Hip-hop / R&B / soul / funk
  {tag = "rnb",             keys = {"rnb", "r&b", "r and b"}},
  {tag = "soul",            keys = {"soul"}},
  {tag = "funk",            keys = {"funk"}},
  {tag = "neo soul",        keys = {"neo soul", "neosoul"}},
  {tag = "gospel",          keys = {"gospel"}},

  -- Global / regional
  {tag = "reggaeton",       keys = {"reggaeton"}},
  {tag = "dembow",          keys = {"dembow"}},
  {tag = "dancehall",       keys = {"dancehall"}},
  {tag = "reggae",          keys = {"reggae"}},
  {tag = "dub",             keys = {"dub"}},
  {tag = "amapiano",        keys = {"amapiano"}},
  {tag = "gqom",            keys = {"gqom"}},
  {tag = "kuduro",          keys = {"kuduro"}},
  {tag = "soca",            keys = {"soca"}},
  {tag = "cumbia",          keys = {"cumbia"}},
  {tag = "samba",           keys = {"samba"}},
  {tag = "latin",           keys = {"latin"}},
  {tag = "zouk",            keys = {"zouk"}},

  -- Rock / pop / alternative
  {tag = "pop",             keys = {"pop"}},
  {tag = "rock",            keys = {"rock"}},
  {tag = "metal",           keys = {"metal"}},
  {tag = "punk",            keys = {"punk"}},
  {tag = "emo",             keys = {"emo"}},
  {tag = "indie",           keys = {"indie"}},
  {tag = "shoegaze",        keys = {"shoegaze", "shoe gaze"}},
  {tag = "grunge",          keys = {"grunge"}},
  {tag = "alternative",     keys = {"alternative", "alt rock"}},

  -- Jazz / blues / acoustic
  {tag = "jazz",            keys = {"jazz"}},
  {tag = "blues",           keys = {"blues"}},
  {tag = "country",         keys = {"country"}},
  {tag = "folk",            keys = {"folk"}},
  {tag = "bluegrass",       keys = {"bluegrass"}},

  -- Cinematic / orchestral / experimental
  {tag = "cinematic",       keys = {"cinematic"}},
  {tag = "orchestral",      keys = {"orchestral"}},
  {tag = "trailer",         keys = {"trailer"}},
  {tag = "epic",            keys = {"epic"}},
  {tag = "experimental",    keys = {"experimental"}},
  {tag = "world",           keys = {"world"}},
}

-- Fast lookup of canonical genre tags for UI categorization
GENRE_TAG_SET = {}
do
  for _, entry in ipairs(GENRE_KEYWORDS) do
    GENRE_TAG_SET[string.lower(entry.tag)] = true
  end
end

-- Map render performance: spatial grid + on-screen dot budget
MAP_GRID_RES = 32
-- Hard cap for AddCircleFilled at every zoom. Over budget, a viewport-relative
-- pick grid keeps on-screen density even instead of packing more when zoomed in.
MAP_DOT_BUDGET = 30000
MAP_ZOOM_MIN = 1.0
MAP_ZOOM_MAX = 16.0
MAP_PLAY_TRACE_COUNT = 10
-- Click/hover snaps to the nearest visible dot within this radius (px).
MAP_CLICK_SNAP_MIN = 96.0
-- Trackpad sends many tiny wheel deltas — apply them 1:1. Mouse notches
-- (|wheel| >= threshold) also get a short coast so they don't feel abrupt.
MAP_ZOOM_WHEEL_GAIN = 0.15
MAP_ZOOM_MOUSE_NOTCH = 0.85
MAP_ZOOM_COAST_VEL = 1.35
MAP_ZOOM_VEL_FRICTION = 0.82
MAP_ZOOM_VEL_MAX = 4.0
MAP_ZOOM_VEL_EPS = 0.025

state = {
  folders = {},
  samples = {},
  scan_queue = {},
  scan_started = 0.0,
  scan_total = 0,
  scan_running = false,  -- false = paused/stopped; remaining queue is kept for resume
  scanned_paths = {},  -- Set of already-scanned file paths (for resuming)
  selected = nil,
  filter = "",
  active_tags = {},      -- Tag filters toggled by the user
  tag_list = {},         -- Cached sorted list of tags with counts
  tag_counts = {},       -- Map<tag,count>
  scan_logs = {},        -- Rolling buffer of scan/analyzer logs
  map_seed = 1337,
  map_layout_version = 0,  -- Bumped when sample coordinates are recalculated
  map_y_axis = "brightness", -- "brightness" | "dominant_freq" | "weight"
  zoom = 1.0,  -- Zoom level (1.0 = normal)
  pan_x = 0.0,  -- Pan offset X
  pan_y = 0.0,  -- Pan offset Y
  map_view_w = nil,  -- Last sample-map widget width (for tab camera restore)
  map_view_h = nil,
  drag_start_x = nil,  -- Drag start position
  drag_start_y = nil,
  drag_start_pan_x = 0.0,
  drag_start_pan_y = 0.0,
  is_dragging = false,  -- Right mouse drag for panning
  is_left_dragging = false,  -- Left mouse drag for selecting samples
  map_press_x = nil,  -- Left-press origin for click-vs-drag audition
  map_press_y = nil,
  map_press_pending = false,  -- Mouse is down on the map, not yet a drag
  map_audition_rearm = false,  -- Recapture origin next frame after a blocking preview
  last_dragged_sample_path = nil,  -- Track last sample previewed during drag
  pending_waveform_drop = nil,  -- Sample waiting to be dropped (global drag operation)
  last_mouse_time_pos = nil,  -- Last known mouse time position during drag
  last_mouse_track = nil,     -- Last known mouse track during drag
  seq_drop_target_idx = nil,  -- Sequencer track row hovered during sample drag
  seq_candidate_drop = nil,   -- { slot_id, idx } candidate square hovered during sample drag
  seq_drum_drop = nil,        -- { slot_id, idx } drum icon hovered during sample drag (region sample)
  seq_candidate_press = nil,  -- { slot_id, idx } mouse-down on a filled candidate (click vs drag)
  seq_candidate_drag_source = nil, -- { slot_id, idx } candidate that started the current sample drag
  provisional_drop = nil,     -- { item, track, time, sample_path } live arrange preview item during drag
  drag_tooltip_active = false,-- Whether the native floating drag tooltip is showing
  external_disabled = false,  -- Stop trying analyzer after first hard failure
  analyzer_warned = false,
  folder_filter_paths = {},  -- folder paths included in the sample-map filter
  missing_scan_folders = {},  -- Set of normalized scan roots currently unavailable
  missing_volumes = {},       -- Set of removable volume roots currently unmounted (e.g. /Volumes/Name)
  map_availability_epoch = 0, -- Bumped when mount/folder availability changes (invalidates map cache)
  last_volume_check_time = 0, -- Throttle for periodic removable-drive polling
  waveform_eff_drag = false,  -- Dragging the waveform effective-length marker
  waveform_eff_drag_path = nil,
  map_wave_press = nil,       -- Sample Map waveform click-to-preview press
  map_wave_press_t = nil,
  settings_open = false,  -- Settings window open/closed state
  settings_search = "",  -- Filter text for the settings window search bar
  -- Sample map tag row: collapse Drum/Melodic/Library children under parent chips.
  discovered_library_tag_set = {}, -- lowercased folder/pack tokens discovered from the library
  -- "on" | "off" | "dynamic" (dynamic uses collapse_children_tags_width).
  collapse_children_tags = "off",
  collapse_children_tags_width = 1100,
  selected_tag_parents = {}, -- Collapsed mode: which parent chips are expanded (drum/melodic/genre)
  played_history = {},  -- Array of played samples (history)
  history_index = 0,  -- Current position in history (0 = most recent, higher = older)
  history_head = nil,  -- Sample that was current when up/down history browsing started
  map_play_trace = {}, -- Last N unique map plays (oldest → newest); history nav does not mutate this
  hovered_tag = nil,  -- Currently hovered tag name
  tag_color_picker_open = false,  -- Whether color picker popup is open
  tag_color_picker_tag = nil,  -- Tag being edited in color picker
  current_preset_name = "Default",  -- Currently active preset name
  -- Dot customization settings
  dot_radius = 2.0,  -- Base dot radius
  dot_outline_size = 4.0,  -- Outline size for selected/playing sample
  dot_outline_thickness = 3.0,  -- Outline thickness
  dot_color = 0x44AA55,     -- Dot color (RRGGBB format, default: green)
  dot_outline_color = 0xFF00FF,   -- Outline color (RRGGBB format, default: magenta)
  dot_hover_color = 0xC84D,       -- Hover highlight color (RRGGBB format, default: yellow)
  dot_detection_multiplier = 16.0,  -- Detection radius multiplier (multiplies dot_radius)
  -- Tag colors (RRGGBB format - full opacity)
  tag_colors = {
    kick = 0x6B46C1,      -- Purple
    snare = 0xFF6B6B,     -- Red
    clap = 0x4ECDC4,      -- Teal
    rim = 0xFFBE0B,       -- Yellow
    hat = 0x8338EC,       -- Purple-blue
    tom = 0x3A86FF,       -- Blue
    ride = 0x06FFA5,      -- Green
    crash = 0xFF006E,     -- Pink
    perc = 0xFFB703,      -- Orange
    fx = 0x9B5DE5,        -- Light purple
    bass = 0x00F5FF,      -- Cyan
    ["808"] = 0xFFD60A,   -- Gold (legacy tag)
    ["808s"] = 0xFFD60A,  -- Gold
    vocal = 0xFF9F43,     -- Orange
    loop = 0x0ABDE3,      -- Light blue
    drum = 0xFF3838,      -- Red
    pad = 0xA29BFE,       -- Light purple
    lead = 0xFD79A8,      -- Pink
    pluck = 0x00B894,     -- Green
    keys = 0xE17055,      -- Coral
    guitar = 0x6C5CE7,    -- Purple
  },
  -- Sequencer scroll behavior:
  --   "v_as_h"  = vertical wheel scrolls the timeline horizontally (default/legacy)
  --   "natural" = vertical wheel scrolls tracks vertically, horizontal wheel scrolls the timeline
  seq_scroll_mode = "v_as_h",
  seq_parent_item_image = "drum", -- parent-track region item tile style id
  -- User-customizable mouse modifiers for sequencer gestures.
  -- Allowed values: "none", "shift", "alt", "ctrl", "cmd".
  mouse_mods = {
    lane_zoom = "shift",      -- wheel: zoom note/param lane height
    time_zoom = "cmd",        -- wheel: zoom the timeline (horizontal)
    velocity_ramp = "shift",  -- param drag: ramp values across cells
    unify = "alt",            -- param drag: set all cells to the same value
  },
  -- User-customizable keyboard shortcuts. Missing ids fall back to KEYBOARD_SHORTCUT_DEFAULTS.
  -- Each value is { key = "G", shift = true, alt = true, ctrl = true, cmd = true, cmdctrl = true }.
  -- key = "" means explicitly unbound. cmdctrl means Ctrl or Cmd.
  keyboard_shortcuts = {},
  shortcut_capture_id = nil,  -- Action id currently waiting for a key press in Settings
  shortcut_capture_click_cancel = false,
  -- Pop effect animation
  pop_start_time = nil,  -- When pop animation started (nil = no pop)
  pop_duration = 0.3,  -- Pop animation duration in seconds
  breathing_start_time = nil,  -- When breathing cycle started (resets on dot click)
  -- Parallel analyzer processing
  analyzer_queue = {},              -- Files waiting for analyzer processing
  analyzer_results = {},            -- Map: path -> analyzer_data (completed results)
  active_processes = {},            -- Busy analyzer jobs (derived from analyzer_workers)
  analyzer_workers = {},            -- Persistent Python workers
  analyzer_work_dir = nil,          -- Temp dir for worker job files
  max_concurrent_analyzers = 3,     -- Set from CPU count at startup (2-8)
  cpu_core_count = 0,               -- Logical cores detected for worker sizing
  incomplete_analysis_total = 0,    -- Progress denominator for incomplete-only analyzer runs
  analyzer_job_label = nil,         -- Overlay label while analyzer-only jobs run
  analyzer_mode = nil,              -- "transient" | "weight" | nil (full analysis)
  analyzer_path_mode = {},          -- path -> mode for queued analyzer jobs
  last_save_time = 0.0,             -- Timestamp of last cache save
  preview_volume = 1.0,             -- Preview volume (0.0 to 1.0)
  preview_paused = false,           -- Whether preview is paused
  preview_position = 0.0,           -- Playhead position when paused/stopped
  -- Sequencer track slots (linked to project tracks + assigned samples)
  seq_tracks = {},                  -- { id, name, reaper_track_guid, sample_path, sample_name, sample_tag, sample_candidates, lane_h }
  selected_seq_track = nil,         -- 1-based index into seq_tracks
  group_seq_tracks_in_folder = true, -- Put script-created tracks in a TCP folder
  seq_folder_guid = nil,            -- GUID of the Sample Map parent folder track
  seq_swap_track_idx = nil,         -- Track slot in sample swap mode (1-based)
  seq_swap_track_id = nil,          -- Stable track slot id in sample swap mode
  seq_swap_backup_path = nil,       -- Original sample path when swap mode started
  seq_swap_backup_name = nil,       -- Original sample name when swap mode started
  seq_swap_region_id = nil,         -- Region id targeted by a region-only sample swap
  seq_swap_backup_was_override = false, -- Backup was a region sample, not the track default
  seq_swap_saved_active_tags = nil, -- active_tags snapshot before swap-mode map filter
  seq_swap_return_view = nil,       -- view to restore after swap confirm/cancel
  block_swap_bar_input = false,     -- Prevent same-frame click bleed from map to bar
  seq_track_next_id = 1,
  seq_panel_width = 240,
  map_ui_layout = nil,              -- Nested row/col tree for Sample Map modules
  map_ui_drag = nil,                -- { id } while dragging a Sample Map module
  map_ui_drop = nil,                -- { id, edge } live dock target while dragging
  map_ui_rects = {},                -- module id -> { x0, y0, x1, y1 }
  map_ui_split_drag = nil,          -- { node, index, axis, start, size0 }
  map_ui_edit = false,              -- Sample Map layout edit mode
  map_ui_leaf_info = {},            -- leaf id -> { row, col, w, h }
  map_hover_track_id = nil,         -- Sequencer track hovered in the Sample Map tracks module
  active_view = "sample_map",       -- "sample_map" | "sequencer"
  sample_map_floating = false,      -- Sample Map content in a separate window
  sequencer_floating = false,       -- Sequencer content in a separate window
  sample_map_window_rect = nil,     -- { x, y, w, h } of the Sample Map float
  sequencer_window_rect = nil,      -- { x, y, w, h } of the Sequencer float
  map_tabs = {},                    -- Saved Sample Map view snapshots
  map_tab_active_id = 1,
  map_tab_next_id = 1,
  custom_tags = {},                 -- path -> { tag, ... } user-assigned tags
  deleted_tags = {},                -- lowercase tag -> true, hidden from inference and the tag row
  tag_delete_pending = nil,         -- tag waiting for delete confirmation
  tag_delete_open_popup = false,
  explorer_open = false,            -- Library explorer window/panel visible
  explorer_docked = false,          -- false | "sample_map" | "sequencer"
  explorer_width = 320,             -- Docked panel width
  explorer_split_drag = nil,        -- { host, start_x, width0, avail_x } while resizing
  explorer_open_dirs = {},          -- path -> true when a folder is expanded
  explorer_selected_path = nil,     -- currently selected file in the explorer
  explorer_filter = "",
  explorer_dir_cache = {},          -- path -> { dirs = {}, files = {} }
  explorer_has_audio = {},          -- path -> true/false, cached audio-in-tree
  explorer_has_audio_queue = {},    -- pending hide-empty folder checks
  explorer_has_audio_queued = {},   -- path -> true while queued
  explorer_has_audio_seeded = false,
  explorer_cache_seeded = false,    -- true after sample-index tree is built
  explorer_seed_index = nil,        -- next sample index while building the tree
  explorer_seed_roots = nil,        -- scan-folder roots used for the current seed
  explorer_disk_queue = {},         -- paths waiting for a background disk refresh
  explorer_disk_queued = {},        -- path -> true while queued for disk refresh
  explorer_want_disk_refresh = false,
  explorer_row_list = nil,          -- flattened visible explorer rows
  explorer_hide_empty = false,      -- hide folders that contain no audio files
  explorer_tag_target = nil,        -- file path the tag popup is editing
  explorer_tag_input = "",
  explorer_tag_popup_pos = nil,     -- screen pos for the file context menu
  explorer_tag_popup_open = false,
  explorer_window_recovered = false, -- one-shot undock/size reset after a native-dock crash
  tag_parent_map = {},              -- child tag (lower) -> parent id
  custom_tag_parents = {},          -- { { id, label }, ... } user-created parents
  tag_add_query = "",
  tag_add_new_name = "",
  tag_add_parent_name = "",
  tag_add_target_path = nil,
  tag_add_create_open = false,
  tag_add_parent_prompt = false,
  tag_add_should_close = false,
  seq_timeline_drop_track_idx = nil,-- Sequencer timeline row hovered during sample drag
  seq_timeline_drop_time = nil,     -- Sequencer timeline time hovered during sample drag
  seq_follow_arrange = true,        -- Sequencer view follows arrange view when true
  seq_follow_hovered_item = false,  -- Scroll/highlight the hovered note's arrange item
  seq_candidate_show_numbers = true, -- Number sample-candidate slots 1, 2, 3…
  seq_view_start_qn = nil,          -- Manual sequencer view start (QN)
  seq_view_span_qn = nil,           -- Sequencer view span in QN
  seq_grid_qn = 0.25,               -- Musical sequencer cell size in quarter notes
  seq_gen_style = "basic",          -- Template style used by sequencer pattern generation
  seq_groove = "off",               -- Last-used groove; actual feel lives on each region.groove
  seq_regions = {},                 -- { id, name, start_qn, length_bars, pool_id, pattern_id, groove?, style_key?, style_source?, kit_genres?, parent_item_guid?, track_samples? }
  seq_patterns = {},                -- pattern_id -> { notes = { track_slot_id -> step_key -> note } }
  seq_region_next_id = 1,
  seq_pattern_next_id = 1,
  seq_pool_next_id = 1,
  selected_seq_region_id = nil,
  seq_random_edit_region_id = nil, -- Region id for per-track random knobs and region-only drum swaps
  seq_random_active_key = nil,     -- Active random knob key while dragging in sequencer overlay
  seq_random_knob_drag = nil,      -- { id, start_value } for custom knob drag math
  seq_random_popup_region_id = nil, -- Region whose non-default random settings popup is open
  seq_random_popup_pending = nil,  -- Delayed popup open so double-click can reset instead
  seq_random_popup_snapshot = nil, -- Track/control visibility captured when the popup opens
  seq_random_popup_close = false,  -- Close the random settings popup after a reset
  seq_random_popup_active_key = nil, -- Active knob key while dragging in the region random popup
  seq_random_flyout = nil,         -- Momentary extras panel: { kind, slot_id, anchor, rect, hold_until, pinned }
  seq_random_sync_pending = nil,   -- { by_pattern = { [pid] = { track_ids, all_tracks } } } flushed on mouse release
  seq_random_sync_run = false,     -- flush pending random rebuild on the next frame
  seq_pattern_popup_last_style = nil, -- Last popup preset targeted by a dice strength button
  seq_pattern_popup_last_strength = nil,
  seq_kit_random_query = "",        -- Custom keyword / genre filter text for Randomize Kit popup
  seq_kit_history = {},             -- Past randomized kits: { id, label, keywords, elements[] }
  seq_kit_history_next_id = 1,
  seq_gmd_ready = nil,              -- nil unknown, true/false after status/ensure
  seq_gmd_items = {},               -- Cached Groove MIDI list rows
  seq_gmd_groups = {},              -- Same-name Groove MIDI rows merged into presets
  seq_gmd_group_by_name = {},       -- style name -> group
  seq_gmd_total = 0,
  seq_gmd_beat_type = "beat",       -- "beat" | "fill" | "all"
  seq_gmd_status_msg = nil,
  seq_gmd_list_key = nil,           -- Cache key for last list query
  seq_gmd_selected_id = nil,
  seq_gmd_selected_style = nil,     -- Merged Groove MIDI preset name currently selected
  seq_gmd_expanded = {},            -- style name -> true when MIDI variations are expanded inline
  seq_pattern_source = "template",  -- "template" | "gmd"
  seq_pattern_search = "",          -- Pattern browser search query
  selected_seq_note = nil,          -- { region_id, track_id, step_key }
  seq_note_drag = nil,              -- { track_id, region_id, start_col, end_col, applied_min, applied_max, mode } mode: paint|erase|stutter|stutter_edit|decay|copy|move
  seq_expanded_tracks = {},         -- track slot id -> true when parameter lanes are visible
  seq_new_track_query = "",         -- Text input for sequencer add-track popup
  seq_param_drag = nil,             -- { track_id, param, region_id, step_key, col, end_col, ramp, unify, start_value }
  seq_note_edit_mode = nil,         -- Param key for note-lane edit mode (volume, sample_vary, ...); nil = paint notes
  seq_vary_filter_edit = nil,       -- { region_id, track_id, col_min, col_max, text, orig, focus, hovered } while typing a vary filter
  seq_razors = {},                  -- Razor areas: { start_qn, end_qn, track_ids = {id, ...} }
  seq_razor_drag = nil,             -- Live razor draw: { additive, start_qn, start_track_id, current_qn, current_track_id }
  seq_region_drag = nil,            -- Region lane mouse interaction state
  seq_link_hover_region_id = nil,   -- Region whose linked pool is highlighted on hover
  seq_region_rename = nil,          -- { region_id, text, orig, focus, over_suggest } while renaming the top-bar chip
  seq_lane_zoom = 1.0,              -- Vertical zoom for sequencer track/param lanes
  seq_lane_h_drag = nil,            -- { slot_id, start_my, start_h } while dragging a track-height divider
  seq_track_reorder_drag = nil,     -- { slot_id, start_idx, start_my, moved, undo_open } while dragging a track to reorder
  seq_track_menu_id = nil,          -- Sequencer track id whose TCP context menu is open
  seq_track_menu_want_open = nil,   -- Open the TCP context menu on the next popup render
  seq_skip_order_sync = nil,        -- Skip one arrange→sequencer order sync after we write TCP order
  seq_over_lane_resize = false,     -- True while hovering/dragging a track-height divider
  seq_note_anims = {},              -- region:track:step -> { kind, start_time, duration, note }
  seq_track_play_anims = {},        -- track slot id -> { start_time, duration }
  seq_candidate_slide = {},         -- track slot id -> { start, duration, moves, fade }
  seq_neighbor_popup = nil,         -- Horizontal neighbor-sample picker after < > swap
  seq_minimap_popup = nil,          -- Mini sample-map picker after < > swap or Shift+V note pick
  preview_history_popup = nil,      -- Up/down preview-history list
  seq_nav_anchors = {},             -- track slot id -> { x, y, w, h } chevron/dot strip
  seq_layering_slot_id = nil,       -- Sequencer track whose drum-layering window is open
  seq_layering_drag = nil,          -- { side = "transient"|"sustain" } while dragging blend point
  seq_layering_drop_vert = nil,     -- { side, idx } vertex hovered during sample drag
  seq_layering_hover_side = nil,    -- "transient"|"sustain" for waveform highlight
  seq_layering_ab = nil,            -- "original"|"layered" last A/B preview source
  seq_layering_hovered = false,     -- Layering window hovered last frame (blocks sequencer clicks)
  seq_layering_rect = nil,          -- { x, y, w, h } screen rect of the layering window
  seq_layering_bias_drag = nil,     -- true while dragging the layering transient-bias fader
  seq_env_view = nil,               -- { slot_id, t0, t1 } envelope editor time zoom
  seq_env_view_pan = nil,           -- middle-drag pan for envelope editor
  seq_grid_hover = nil,             -- { slot_id, step_key, region_id, note, hovered_qn, step_qn }
  seq_z_preview_last_t = 0,         -- last plain-Z press time (double-tap stops preview)
  seq_last_reaper_playing = false,  -- previous GetPlayState playing bit
  seq_preview_wave_scrub = nil,     -- true while dragging the sequencer header preview waveform
  seq_header_start_drag = nil,      -- true while dragging the header waveform start marker
  seq_header_vol_drag = nil,        -- true while dragging the header sample-volume knob
  seq_header_wave_sample = nil,     -- last hovered/previewed sample shown in the header waveform
  seq_header_menu_sample = nil,     -- sample the header "..." menu was opened for
  seq_sample_start_session = {},    -- path -> start seconds for this project session (not saved)
  seq_sample_vol_session = {},      -- path -> gain for this project session (not saved)
  wave_view_path = nil,             -- sample path the waveform zoom window belongs to
  wave_view_t0 = 0.0,               -- visible waveform start (seconds)
  wave_view_t1 = nil,               -- visible waveform end (seconds); nil = full file
  wave_view_pan = nil,              -- true while middle/alt-panning the waveform
  seq_midi_popup_slot_id = nil,     -- Sequencer track whose MIDI-note assign popup is open
  seq_midi_learn_slot_id = nil,     -- Sequencer track waiting for a MIDI note to assign
  seq_midi_learn_range = false,     -- True when learn should expand lo/hi instead of replacing
  seq_midi_gmem_serial = nil,       -- Last SampleMapMIDI.jsfx gmem serial processed
  seq_midi_jsfx_ready = false,      -- Preview-track JSFX inserted this session
  -- Deferred library load (SampleMapData.*) so the UI can paint before decode/process
  library_load = nil,               -- job table while loading; nil when idle
  library_ready = false,            -- true after first load attempt finishes (hit or miss)
  tag_schema_dirty = false,         -- stamp/save tag_schema_version after load
  _save_library_after_load = false, -- write cache after deferred load completes
  _enqueue_scan_after_load = false, -- start folder scan after cache miss
  seq_last_proj_change = nil,       -- GetProjectStateChangeCount snapshot
  seq_skip_ingest = false,          -- true after script writes arrange items
  seq_self_write_count = nil,       -- change-count at the end of the last frame that wrote arrange
  seq_arrange_fp = nil,             -- region_id -> arrange item fingerprint after the last sync
  seq_ingest_rescan = nil,          -- true: run a full ingest pass next frame
  seq_fp_refresh_at = nil,          -- time to refresh seq_arrange_fp after a streak of script writes
  seq_self_write_at = nil,          -- time the last script-only change was consumed
  seq_ingest_stale_since = nil,     -- time a release-commit hold was first seen with the mouse up
  seq_ingest_pending_count = nil,   -- wait until arrange change count is stable
  seq_ingest_pending_at = nil,      -- time_precise when pending count last changed
  seq_ingest_hold_parent = false,   -- true while arrange selection defers parent geometry
  seq_ingest_save_due = nil,        -- debounce timer for ingest → config save
  seq_parent_items_ensured = false, -- created MIDI parent-track region items
  seq_stem_import = nil,            -- Live OS-drop stem→drum→sequencer job
  seq_stem_import_hover = false,    -- OS audio file is hovered over the sequencer
}

ctx = nil
font = nil
running = true
SampleMapInstance = {
  section = "SampleMapBrowser",
  key = "alive",
  shutdown_done = false,
}
legacy_seq_project_state = nil
loaded_project = nil
loaded_project_token = nil
preview_proc = nil  -- preview handle/ID (integer ID for Xen_StartSourcePreview, or boolean for other APIs)
preview_track = nil  -- dedicated preview track (for PlayTrackPreview2)
PYTHON_BIN = "/usr/bin/python3"
EXTERNAL_ANALYZER = SCRIPT_DIR .. "/SampleMapAnalyzer.py"  -- External analysis script path
preview_source = nil  -- PCM_Source for preview
preview_source_engine_owned = false  -- True when preview API owns source lifetime
preview_start_time = 0.0  -- When preview started
preview_sample_obj = nil  -- Currently previewing sample object
waveform_data = nil  -- Cached waveform data for current preview
waveform_width = 400  -- Width of waveform display (lower = faster generation)
PREVIEW_TRACK_NAME = "__SampleMapPreview"
SEQ_TRACK_FOLDER_NAME = "Sample Map"
cf_preview_obj = nil  -- CF_Preview object (light userdata) for seeking support
samples_by_path = {}  -- O(1) path -> sample lookup

function path_index_key(path)
  if not path or path == "" then
    return ""
  end
  path = tostring(path):gsub("\\", "/"):gsub("/+$", "")
  return string.lower(path)
end

sample_path_miss = {}       -- path -> #state.samples when find_sample_by_path last missed
sample_path_miss_list = nil -- state.samples table the miss cache belongs to

function rebuild_samples_path_index()
  samples_by_path = {}
  sample_path_miss = {}
  for _, s in ipairs(state.samples) do
    if s.path then
      samples_by_path[s.path] = s
      -- Also index forward-slash normalized form for analyzer path lookups
      local norm = tostring(s.path):gsub("\\", "/"):gsub("/+$", "")
      if norm ~= s.path then
        samples_by_path[norm] = s
      end
      -- External volumes (ExFAT/HFS) often change spelling/case on remount.
      local key = path_index_key(s.path)
      if key ~= "" and key ~= s.path and key ~= norm then
        samples_by_path[key] = s
      end
    end
  end
end

function lookup_sample_by_path(path)
  if not path or path == "" then
    return nil
  end
  local sample = samples_by_path[path]
  if sample then
    return sample
  end
  local norm = tostring(path):gsub("\\", "/"):gsub("/+$", "")
  sample = samples_by_path[norm]
  if sample then
    return sample
  end
  return samples_by_path[path_index_key(path)]
end

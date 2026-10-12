-- Sample Map Browser module: seq_pattern_library
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.

-- --- Pattern presets ------------------------------------------------------------
-- Every preset is a role -> {16th positions} map. Positions 0..15 are one bar
-- and repeat every bar; a preset that uses 16..31 is a two-bar phrase (bar two
-- starts at 16) and alternates. Genre presets are written from the common
-- textbook form of each style (kick/backbeat placement, clave, dembow, etc.),
-- not copied from any sample pack or pattern collection. The "Abstract" ones
-- are originals made for Sample Map.

-- Categories in display order. `key` is stored on each style as `cat`.
SEQ_PATTERN_CATEGORIES = {
  { key = "house",    label = "House & Disco",     short = "House" },
  { key = "techno",   label = "Techno & Electro",  short = "Techno" },
  { key = "hiphop",   label = "Hip-Hop & Trap",    short = "Hip-Hop" },
  { key = "breaks",   label = "Breaks & Bass",     short = "Breaks" },
  { key = "rockpop",  label = "Rock, Pop & Funk",  short = "Rock/Pop" },
  { key = "world",    label = "Latin & World",     short = "World" },
  { key = "abstract", label = "Abstract",          short = "Abstract" },
}

-- `header` rows are kept for older callers that list styles in order; the
-- pattern window groups by `cat` instead. `bpm` is the tempo the pattern is
-- usually played at (shown as a hint only, nothing is changed in the project).
SEQ_GEN_STYLE_ORDER = {
  { header = "House & Disco" },
  { key = "house", label = "House", cat = "house", bpm = 124, desc = "Four-on-the-floor kick, clap on 2 and 4, offbeat hats and bass." },
  { key = "deep_house", label = "Deep House", cat = "house", bpm = 122, desc = "Laid-back four-on-the-floor with a shaker line and a syncopated bass." },
  { key = "tech_house", label = "Tech House", cat = "house", bpm = 126, desc = "Rolling bass under a straight kick, with clipped percussion stabs." },
  { key = "disco", label = "Disco", cat = "house", bpm = 118, desc = "Four-on-the-floor with steady eighth hats and an offbeat ride." },
  { key = "nu_disco", label = "Nu Disco", cat = "house", bpm = 120, desc = "Disco kick and clap with a tambourine offbeat and octave-style bass." },
  { key = "garage", label = "UK Garage (2-Step)", cat = "house", bpm = 132, desc = "Skippy two-step kick, shuffled hats and rim ghosts." },
  { key = "afro_house", label = "Afro House", cat = "house", bpm = 122, desc = "Straight kick under interlocking rim, conga and tom figures." },

  { header = "Techno & Electro" },
  { key = "techno", label = "Techno", cat = "techno", bpm = 130, desc = "Driving 4/4 with offbeat open hats and syncopated perc stabs." },
  { key = "minimal", label = "Minimal Techno", cat = "techno", bpm = 128, desc = "Sparse clicks and rims around a dry kick." },
  { key = "hard_techno", label = "Hard Techno", cat = "techno", bpm = 145, desc = "Pounding kick, clap backbeat and a full ride line." },
  { key = "dub_techno", label = "Dub Techno", cat = "techno", bpm = 120, desc = "Soft kick with a delayed chord-stab FX and quiet percussion." },
  { key = "trance", label = "Trance", cat = "techno", bpm = 138, desc = "Rolling offbeat bass between kicks, clap on 2 and 4." },
  { key = "electro", label = "Electro", cat = "techno", bpm = 125, desc = "Syncopated drum-machine kick, snare and cowbell." },
  { key = "ebm", label = "EBM", cat = "techno", bpm = 120, desc = "Straight kick and snare with a sequenced sixteenth bass." },

  { header = "Hip-Hop & Trap" },
  { key = "hiphop", label = "Boom Bap", cat = "hiphop", bpm = 90, desc = "Kick on 1 and the & of 2, classic backbeat, swung eighth hats." },
  { key = "lofi", label = "Lo-Fi Hip-Hop", cat = "hiphop", bpm = 80, desc = "Lazy, heavily swung kit with a late rim ghost." },
  { key = "gfunk", label = "West Coast", cat = "hiphop", bpm = 92, desc = "Bouncy kick and bass with a clap backbeat." },
  { key = "trap", label = "Trap", cat = "hiphop", bpm = 140, desc = "Half-time snare on 3, syncopated 808 and kick, rapid hats." },
  { key = "drill", label = "Drill", cat = "hiphop", bpm = 142, desc = "Half-time snare with a late second hit, triplet-feel hats and sliding 808." },
  { key = "phonk", label = "Phonk", cat = "hiphop", bpm = 135, desc = "808 and kick with a cowbell riff on top." },
  { key = "jersey_club", label = "Jersey Club", cat = "hiphop", bpm = 140, desc = "Bouncing kick run into beat 4 with vocal chops." },

  { header = "Breaks & Bass" },
  { key = "breakbeat", label = "Breakbeat", cat = "breaks", bpm = 130, desc = "Break-style kick and snare interplay with a perc tail." },
  { key = "amen", label = "Amen-Style Break", cat = "breaks", bpm = 170, desc = "Two-bar break in the style of the classic Amen: ghosted snares, double kicks." },
  { key = "dnb", label = "Drum & Bass", cat = "breaks", bpm = 174, desc = "Two-step kick on 1 and the & of 3, snare backbeat, sub on kicks." },
  { key = "liquid", label = "Liquid DnB", cat = "breaks", bpm = 174, desc = "Smooth two-step with ride and shaker ghosts." },
  { key = "jungle", label = "Jungle", cat = "breaks", bpm = 165, desc = "Choppy snares and a rolling bass under break hats." },
  { key = "dubstep", label = "Dubstep", cat = "breaks", bpm = 140, desc = "Half-time: kick on 1, snare on 3, wobble bass." },
  { key = "footwork", label = "Footwork", cat = "breaks", bpm = 160, desc = "Stuttering kicks, chopped vocal hits and tom fills." },
  { key = "big_beat", label = "Big Beat", cat = "breaks", bpm = 130, desc = "Heavy break kick with a snare push and crash." },

  { header = "Rock, Pop & Funk" },
  { key = "basic", label = "Pop Backbeat", cat = "rockpop", bpm = 100, desc = "Straight pop backbeat; clap layered on the snare." },
  { key = "rock", label = "Rock", cat = "rockpop", bpm = 120, desc = "Kick on 1 and the & of 3, backbeat snare, crash on the downbeat." },
  { key = "punk", label = "Punk", cat = "rockpop", bpm = 180, desc = "Fast kick-snare alternation on eighths." },
  { key = "ballad", label = "Ballad", cat = "rockpop", bpm = 70, desc = "Slow half-feel with a cross-stick backbeat." },
  { key = "motown", label = "Motown", cat = "rockpop", bpm = 120, desc = "Snare on every beat with tambourine on 2 and 4." },
  { key = "synthpop", label = "Synth Pop", cat = "rockpop", bpm = 118, desc = "Drum-machine pop with offbeat hats and a tom pickup." },
  { key = "funk", label = "Funk", cat = "rockpop", bpm = 105, desc = "Syncopated kick, backbeat snare, sixteenth hats." },
  { key = "new_jack", label = "New Jack Swing", cat = "rockpop", bpm = 105, desc = "Swung sixteenths, syncopated kick, snare and clap together." },

  { header = "Latin & World" },
  { key = "reggaeton", label = "Reggaeton", cat = "world", bpm = 95, desc = "Dembow: kick on every beat, rim on the boom-ch-boom-chick." },
  { key = "dancehall", label = "Dancehall", cat = "world", bpm = 100, desc = "Syncopated kick with rim backbeat and perc offbeats." },
  { key = "reggae", label = "Reggae One Drop", cat = "world", bpm = 75, desc = "Kick and cross-stick together on 3, swung hats." },
  { key = "afrobeat", label = "Afrobeat", cat = "world", bpm = 110, desc = "Clave-like rim, rolling perc, lilting kick." },
  { key = "afrobeats", label = "Afrobeats", cat = "world", bpm = 104, desc = "Modern afrobeats: 3-3-2 rim, clap backbeat, shaker." },
  { key = "amapiano", label = "Amapiano", cat = "world", bpm = 112, desc = "Kick on the beat, shaker offbeats and a syncopated log-drum bass." },
  { key = "bossa", label = "Bossa Nova", cat = "world", bpm = 130, desc = "Two-bar bossa clave on the rim, soft kick ostinato." },
  { key = "samba", label = "Samba", cat = "world", bpm = 100, desc = "Surdo-style kick, partido-alto rim and busy tamborim." },
  { key = "son", label = "Son / Salsa", cat = "world", bpm = 180, desc = "Two-bar 3-2 son clave, conga tumbao and bass anticipation." },
  { key = "cumbia", label = "Cumbia", cat = "world", bpm = 95, desc = "Kick on 1 and 3, guacharaca scrape and offbeat hats." },
  { key = "baile_funk", label = "Baile Funk", cat = "world", bpm = 130, desc = "Tamborzao-style kick and tom groove with a clap backbeat." },

  { header = "Abstract" },
  { key = "dust_motes", label = "Dust Motes", cat = "abstract" },
  { key = "glass_steps", label = "Glass Steps", cat = "abstract" },
  { key = "crooked_neon", label = "Crooked Neon", cat = "abstract" },
  { key = "soft_alarm", label = "Soft Alarm", cat = "abstract" },
  { key = "tiny_machines", label = "Tiny Machines", cat = "abstract" },
  { key = "low_gravity", label = "Low Gravity", cat = "abstract" },
  { key = "ritual_drift", label = "Ritual Drift", cat = "abstract" },
  { key = "broken_lantern", label = "Broken Lantern", cat = "abstract" },
  { key = "afterimage", label = "Afterimage", cat = "abstract" },
  { key = "rain_on_plastic", label = "Rain On Plastic", cat = "abstract" },
  { key = "velvet_push", label = "Velvet Push", cat = "abstract" },
  { key = "static_bloom", label = "Static Bloom", cat = "abstract" },
  { key = "paper_lanterns", label = "Paper Lanterns", cat = "abstract" },
  { key = "clockwork_moth", label = "Clockwork Moth", cat = "abstract" },
  { key = "tilted_orbit", label = "Tilted Orbit", cat = "abstract" },
  { key = "copper_rain", label = "Copper Rain", cat = "abstract" },
  { key = "slow_comet", label = "Slow Comet", cat = "abstract", desc = "Two-bar phrase." },
  { key = "folded_map", label = "Folded Map", cat = "abstract" },
  { key = "night_bus", label = "Night Bus", cat = "abstract" },
  { key = "hollow_bell", label = "Hollow Bell", cat = "abstract" },
}

-- Map sequencer pattern style keys to library genre tags used for kit randomization.
SEQ_STYLE_LIBRARY_GENRES = {
  house = { "house" },
  deep_house = { "deep house", "house" },
  tech_house = { "tech house", "house" },
  disco = { "disco", "nu disco" },
  nu_disco = { "nu disco", "disco" },
  garage = { "garage", "uk garage" },
  afro_house = { "afro house", "house" },
  techno = { "techno" },
  minimal = { "minimal", "techno" },
  hard_techno = { "hard techno", "techno" },
  dub_techno = { "dub techno", "techno" },
  trance = { "trance" },
  electro = { "electro" },
  ebm = { "ebm", "industrial" },
  basic = { "pop" },
  rock = { "rock" },
  punk = { "punk", "rock" },
  ballad = { "pop", "rock" },
  motown = { "soul", "motown" },
  synthpop = { "synthpop", "pop" },
  hiphop = { "boom bap", "hip hop" },
  lofi = { "lofi", "hip hop" },
  gfunk = { "g-funk", "hip hop" },
  trap = { "trap" },
  drill = { "drill", "trap" },
  phonk = { "phonk" },
  jersey_club = { "jersey club", "club" },
  funk = { "funk" },
  new_jack = { "new jack swing", "r&b" },
  dnb = { "drum and bass" },
  liquid = { "liquid", "drum and bass" },
  jungle = { "jungle", "drum and bass" },
  amen = { "breakbeat", "jungle" },
  breakbeat = { "breakbeat" },
  big_beat = { "big beat", "breakbeat" },
  dubstep = { "dubstep" },
  footwork = { "footwork", "juke" },
  reggaeton = { "reggaeton" },
  dancehall = { "dancehall" },
  reggae = { "reggae" },
  afrobeat = { "afrobeat" },
  afrobeats = { "afrobeats", "afrobeat" },
  amapiano = { "amapiano" },
  bossa = { "bossa nova", "latin" },
  samba = { "samba", "latin" },
  son = { "salsa", "latin" },
  cumbia = { "cumbia", "latin" },
  baile_funk = { "baile funk", "funk carioca" },
}

-- Each preset declares its own palette of sample-type roles. Picking a preset
-- auto-adds any missing track types it needs (see ensure_seq_tracks_for_roles).
SEQ_GEN_TEMPLATES = {
  -- ---- House & Disco ----------------------------------------------------------
  -- Four-on-the-floor; clap doubles beats 2 & 4; open hats on the offbeats.
  house = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    bass = {2, 6, 10, 14},
  },
  deep_house = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    perc = {1, 3, 5, 7, 9, 11, 13, 15},
    bass = {3, 6, 11, 14},
  },
  tech_house = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    perc = {3, 7, 10, 15},
    bass = {2, 5, 10, 13},
  },
  -- Disco: four-on-the-floor with steady 8th hats and offbeat open ride.
  disco = {
    kick = {0, 4, 8, 12},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    ride = {2, 6, 10, 14},
  },
  nu_disco = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    perc = {2, 6, 10, 14},
    bass = {0, 3, 6, 8, 11, 14},
  },
  -- Two-step: no kick on 2 and 4, the second kick skips to the & of 3.
  garage = {
    kick = {0, 10},
    snare = {4, 12},
    hat = {2, 3, 6, 10, 11, 14},
    rim = {7, 15},
    bass = {0, 7, 10},
  },
  afro_house = {
    kick = {0, 4, 8, 12},
    rim = {3, 6, 10, 13},
    perc = {2, 5, 7, 11, 14},
    hat = {2, 6, 10, 14},
    tom = {14},
  },

  -- ---- Techno & Electro -------------------------------------------------------
  -- Driving 4/4; offbeat open hats; syncopated perc stabs.
  techno = {
    kick = {0, 4, 8, 12},
    hat = {2, 6, 10, 14},
    clap = {12},
    perc = {3, 11},
  },
  minimal = {
    kick = {0, 4, 8, 12},
    rim = {3, 11, 14},
    hat = {2, 6, 10, 14},
    perc = {7, 13},
  },
  hard_techno = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    ride = {0, 2, 4, 6, 8, 10, 12, 14},
    perc = {3, 7, 11, 15},
  },
  dub_techno = {
    kick = {0, 4, 8, 12},
    hat = {2, 6, 10, 14},
    perc = {3, 11},
    fx = {6},
  },
  -- Rolling offbeat bass fills every 16th the kick doesn't take.
  trance = {
    kick = {0, 4, 8, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    bass = {1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15},
    crash = {0},
  },
  electro = {
    kick = {0, 7, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14, 15},
    perc = {3, 6, 11},
  },
  ebm = {
    kick = {0, 4, 8, 12},
    snare = {4, 12},
    bass = {2, 3, 6, 7, 10, 11, 14, 15},
    hat = {2, 6, 10, 14},
  },

  -- ---- Hip-Hop & Trap ---------------------------------------------------------
  -- Boom bap: kick on 1 and the & of 2, classic backbeat, swung 8th hats.
  hiphop = {
    kick = {0, 6, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  lofi = {
    kick = {0, 7, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    rim = {15},
  },
  gfunk = {
    kick = {0, 3, 8, 10},
    clap = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    bass = {0, 3, 8, 11},
  },
  -- Trap: half-time snare on beat 3, syncopated 808/kick, rapid 16th hats.
  trap = {
    kick = {0, 7, 10},
    snare = {8},
    hat = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    ["808"] = {0, 7, 10},
  },
  drill = {
    kick = {0, 6, 11},
    snare = {8, 15},
    hat = {0, 3, 6, 8, 10, 13},
    ["808"] = {0, 6, 11},
    perc = {13},
  },
  phonk = {
    kick = {0, 6, 10},
    clap = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    ["808"] = {0, 6, 10},
    perc = {0, 3, 6, 10, 12},
  },
  jersey_club = {
    kick = {0, 4, 8, 10, 12, 14},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    vocal = {2, 6},
  },

  -- ---- Breaks & Bass ----------------------------------------------------------
  -- Breakbeat: amen-style kick/snare interplay with a perc tail.
  breakbeat = {
    kick = {0, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    perc = {7, 15},
  },
  -- Two bars: double kick on 1, ghosted snares around the backbeat; bar two
  -- answers with the kick pair moved later.
  amen = {
    kick = {0, 2, 10, 11, 16, 18, 26},
    snare = {4, 7, 9, 12, 15, 20, 23, 25, 30},
    ride = {0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30},
    crash = {26},
  },
  -- Drum & bass two-step: kick on 1 and the & of 3, snare backbeat, sub on kicks.
  dnb = {
    kick = {0, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    bass = {0, 10},
  },
  liquid = {
    kick = {0, 10},
    snare = {4, 12},
    ride = {2, 6, 10, 14},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    perc = {7, 15},
  },
  jungle = {
    kick = {0, 10},
    snare = {4, 7, 12, 15},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    bass = {0, 6, 10},
    perc = {13},
  },
  dubstep = {
    kick = {0},
    snare = {8},
    hat = {2, 3, 6, 10, 11, 14},
    bass = {0, 3, 6},
    fx = {14},
  },
  footwork = {
    kick = {0, 3, 6, 10, 13},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    tom = {11, 15},
    vocal = {2, 8, 14},
  },
  big_beat = {
    kick = {0, 3, 8, 10},
    snare = {4, 12, 15},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    crash = {0},
  },

  -- ---- Rock, Pop & Funk -------------------------------------------------------
  -- Straight pop backbeat; clap layered on the snare.
  basic = {
    kick = {0, 8},
    snare = {4, 12},
    clap = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  -- Rock: kick on 1 and the & of 3, backbeat snare, crash on the downbeat.
  rock = {
    kick = {0, 8, 10},
    snare = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
    crash = {0},
  },
  -- Kick on every beat, snare on every &.
  punk = {
    kick = {0, 4, 8, 12},
    snare = {2, 6, 10, 14},
    ride = {0, 2, 4, 6, 8, 10, 12, 14},
    crash = {0},
  },
  ballad = {
    kick = {0, 7, 8},
    rim = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  motown = {
    kick = {0, 8, 10},
    snare = {0, 4, 8, 12},
    perc = {4, 12},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  synthpop = {
    kick = {0, 8, 10},
    snare = {4, 12},
    clap = {4, 12},
    hat = {2, 6, 10, 14},
    tom = {14, 15},
  },
  -- Funk: syncopated kick, backbeat snare, 16th hats, perc ghost on the &-a.
  funk = {
    kick = {0, 3, 10},
    snare = {4, 12},
    hat = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    perc = {7, 14},
  },
  new_jack = {
    kick = {0, 3, 7, 10},
    snare = {4, 12},
    clap = {4, 12},
    hat = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
  },

  -- ---- Latin & World ----------------------------------------------------------
  -- Reggaeton dembow: kick on every beat, rimshot on the boom-ch-boom-chick.
  reggaeton = {
    kick = {0, 8},
    rim = {3, 6, 11, 14},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  dancehall = {
    kick = {0, 6, 10},
    rim = {4, 12},
    clap = {12},
    perc = {3, 11},
    hat = {2, 6, 10, 14},
  },
  -- One drop: nothing on 1; kick and cross-stick land together on 3.
  reggae = {
    kick = {8},
    rim = {8},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  -- Afrobeat: son-clave (3-2) rimshot, rolling perc, lilting kick.
  afrobeat = {
    kick = {0, 6, 10},
    rim = {0, 3, 6, 10, 12},
    perc = {2, 5, 8, 11, 14},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  afrobeats = {
    kick = {0, 7, 8},
    rim = {0, 3, 6},
    clap = {4, 12},
    perc = {2, 6, 10, 14},
    hat = {0, 2, 4, 6, 8, 10, 12, 14},
  },
  amapiano = {
    kick = {0, 4, 8, 12},
    clap = {12},
    perc = {1, 3, 5, 7, 9, 11, 13, 15},
    bass = {3, 6, 10, 13},
  },
  -- Two bars: bossa clave (3 + 2 with the last note pushed late).
  bossa = {
    kick = {0, 6, 8, 14, 16, 22, 24, 30},
    rim = {0, 6, 12, 20, 26},
    hat = {0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30},
  },
  samba = {
    kick = {0, 3, 4, 8, 11, 12},
    rim = {0, 3, 6, 10, 12},
    hat = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    perc = {2, 5, 7, 10, 13, 15},
  },
  -- Two bars: 3-2 son clave on the rim, conga tumbao on the &-of-2/4 pairs.
  son = {
    rim = {0, 6, 12, 20, 24},
    tom = {6, 7, 14, 15, 22, 23, 30, 31},
    bass = {6, 12, 22, 28},
    perc = {0, 4, 8, 12, 16, 20, 24, 28},
  },
  cumbia = {
    kick = {0, 8},
    rim = {4, 12},
    perc = {0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15},
    hat = {2, 6, 10, 14},
  },
  baile_funk = {
    kick = {0, 3, 7, 10},
    clap = {4, 12},
    tom = {6, 13},
    perc = {2, 5, 8, 11, 14},
  },

  -- ---- Abstract (originals) ---------------------------------------------------
  dust_motes = {
    kick = {0, 10},
    rim = {4, 12},
    perc = {3, 7, 11, 13},
    vocal = {2, 10},
  },
  glass_steps = {
    kick = {0, 6, 11},
    snare = {4, 12},
    hat = {1, 3, 5, 7, 9, 11, 13, 15},
    perc = {6, 10, 14},
    fx = {0},
  },
  crooked_neon = {
    ["808"] = {0, 5, 10, 14},
    clap = {4, 11},
    hat = {0, 2, 5, 7, 8, 10, 13, 15},
    perc = {3, 9, 12},
  },
  soft_alarm = {
    kick = {0, 9},
    snare = {4, 12},
    hat = {2, 6, 10, 14},
    fx = {8, 15},
  },
  tiny_machines = {
    kick = {0, 4, 9, 12},
    rim = {6, 14},
    perc = {2, 5, 10, 13},
    hat = {0, 1, 3, 4, 6, 8, 9, 11, 12, 14},
  },
  low_gravity = {
    kick = {0, 11},
    snare = {6, 13},
    bass = {0, 8},
    ride = {0, 4, 8, 12},
  },
  ritual_drift = {
    kick = {0, 7, 12},
    tom = {5, 13},
    perc = {2, 4, 6, 10, 12, 14},
    vocal = {1, 8, 15},
  },
  broken_lantern = {
    kick = {0, 3, 10},
    snare = {4, 12, 15},
    hat = {1, 4, 6, 9, 11, 14},
    fx = {0},
    perc = {2, 7, 13},
  },
  afterimage = {
    kick = {0, 8, 15},
    clap = {4, 12},
    hat = {2, 3, 6, 7, 10, 11, 14, 15},
    ride = {0, 4, 8, 12},
    fx = {15},
  },
  rain_on_plastic = {
    kick = {0, 6, 12},
    rim = {4, 10},
    hat = {0, 2, 3, 5, 7, 8, 10, 12, 13, 15},
    perc = {1, 6, 11, 14},
    vocal = {3, 11},
  },
  velvet_push = {
    kick = {0, 8, 10},
    snare = {4, 12},
    hat = {2, 6, 9, 10, 14},
    bass = {0, 8},
    clap = {12},
  },
  static_bloom = {
    ["808"] = {0, 4, 10},
    snare = {7, 12},
    hat = {1, 2, 4, 5, 7, 8, 10, 11, 13, 14},
    perc = {3, 6, 9, 15},
    fx = {0, 8},
  },
  paper_lanterns = {
    kick = {0, 9},
    rim = {5, 13},
    perc = {2, 7, 11, 14},
    ride = {0, 4, 8, 12},
    vocal = {6},
  },
  clockwork_moth = {
    kick = {0, 3, 6, 9, 12},
    snare = {4, 13},
    hat = {1, 2, 5, 6, 9, 10, 13, 14},
    perc = {15},
  },
  tilted_orbit = {
    kick = {0, 5, 10},
    snare = {7, 15},
    hat = {0, 3, 6, 9, 12, 15},
    bass = {0, 5, 10},
  },
  copper_rain = {
    kick = {0, 8, 11},
    snare = {4, 12},
    rim = {3, 6, 14},
    hat = {0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15},
    perc = {7, 15},
  },
  slow_comet = {
    kick = {0, 22},
    snare = {12, 28},
    ride = {0, 4, 8, 12, 16, 20, 24, 28},
    bass = {0, 14, 22},
    fx = {0},
  },
  folded_map = {
    kick = {0, 7, 10, 13},
    clap = {4, 12},
    hat = {2, 6, 9, 10},
    tom = {14, 15},
    perc = {1, 5},
  },
  night_bus = {
    kick = {0, 6, 10},
    snare = {4, 12},
    hat = {0, 3, 6, 8, 11, 14},
    rim = {15},
    bass = {0, 10, 14},
    fx = {8},
  },
  hollow_bell = {
    kick = {0, 12},
    rim = {8},
    ride = {2, 6, 10, 14},
    perc = {0, 3, 6, 9, 12},
    vocal = {4},
  },
}

-- Per-preset groove. swing delays odd 16th positions (fraction of a 16th note)
-- to push the pattern off the grid and into a more human pocket.
SEQ_GEN_GROOVE = {
  house       = { swing = 0.0 },
  deep_house  = { swing = 0.06 },
  tech_house  = { swing = 0.03 },
  nu_disco    = { swing = 0.04 },
  garage      = { swing = 0.18 },
  afro_house  = { swing = 0.08 },
  techno      = { swing = 0.0 },
  disco       = { swing = 0.04 },
  basic       = { swing = 0.04 },
  rock        = { swing = 0.0 },
  ballad      = { swing = 0.04 },
  motown      = { swing = 0.04 },
  hiphop      = { swing = 0.16 },
  lofi        = { swing = 0.22 },
  gfunk       = { swing = 0.10 },
  trap        = { swing = 0.0 },
  drill       = { swing = 0.0 },
  phonk       = { swing = 0.0 },
  funk        = { swing = 0.10 },
  new_jack    = { swing = 0.22 },
  dnb         = { swing = 0.0 },
  liquid      = { swing = 0.04 },
  jungle      = { swing = 0.06 },
  amen        = { swing = 0.04 },
  breakbeat   = { swing = 0.08 },
  big_beat    = { swing = 0.06 },
  reggaeton   = { swing = 0.0 },
  dancehall   = { swing = 0.04 },
  reggae      = { swing = 0.18 },
  afrobeat    = { swing = 0.06 },
  afrobeats   = { swing = 0.10 },
  amapiano    = { swing = 0.08 },
  bossa       = { swing = 0.0 },
  samba       = { swing = 0.06 },
  son         = { swing = 0.0 },
  cumbia      = { swing = 0.04 },
  baile_funk  = { swing = 0.0 },
}

-- Bars in one cycle of the template: 1 for ordinary presets, 2 when any role
-- has a step in 16..31.
function seq_template_cycle_bars(template)
  local bars = 1
  if type(template) ~= "table" then
    return bars
  end
  for _, steps in pairs(template) do
    if type(steps) == "table" then
      for _, s in ipairs(steps) do
        local b = math.floor((tonumber(s) or 0) / 16) + 1
        if b > bars then bars = b end
      end
    end
  end
  return bars
end

function seq_gen_style_def(style_key)
  if not SEQ_GEN_STYLE_DEFS then
    SEQ_GEN_STYLE_DEFS = {}
    for _, style in ipairs(SEQ_GEN_STYLE_ORDER) do
      if style.key then
        SEQ_GEN_STYLE_DEFS[style.key] = style
      end
    end
  end
  return SEQ_GEN_STYLE_DEFS[style_key]
end

function seq_pattern_category_label(cat_key)
  for _, cat in ipairs(SEQ_PATTERN_CATEGORIES) do
    if cat.key == cat_key then
      return cat.label
    end
  end
  return "Other"
end

# Chord Detector

Detects the key and the chords of an audio take and writes a take marker at
every chord change, spelled with the key's sharps or flats (Bb7 in Eb major,
D#m in F# major, E7 in A minor).

## Actions

- **CRS_Chord Detector - Insert chord take markers.lua**: runs on the active
  take of every selected audio item. A small window shows progress (Esc
  cancels, nothing is written). Re-running replaces the markers it wrote
  before and leaves your own markers alone. One undo step.
- **CRS_Chord Detector - Settings.lua**: chord types (triads / standard / full),
  shortest chord in beats, change resistance, key changes, slash chords,
  key name in the marker, N.C. markers.

The first chord of each key area carries the key, e.g. `Cm  (key Eb major)`.
The full result is also stored in the take's `P_EXT:CRS_ChordDetector`
(tab-separated lines `key`, `area`, `chord`, `tempo`) for other scripts.

## High accuracy mode (neural)

On by default (Settings: "High accuracy, slower"). The chord evidence then
comes from BTC, a small transformer network trained on real songs
(Park et al., ISMIR 2019, MIT License, see LICENSE-BTC.txt), ported to pure
Lua in `ChordDetector_BTC.lua` with its original weights in
`ChordDetector_BTC.bin` (12 MB, 170 chord classes). Nothing to install.
The key, beats, minimum chord length and spelling still come from the
decoder below. It takes roughly 1-2 s of computing per second of audio, in
the background with a progress bar. Without the two BTC files the script
falls back to the fast chroma detector.

Other scripts: `opts.btc = { lib = BTC, weights = BTC.load(path) }` with
`local BTC = dofile(dir .. "ChordDetector_BTC.lua")`.

## How it decides

The detector does not label each moment on its own. It

1. reads the spectrum, estimates the tuning (works on detuned recordings),
   and builds treble and bass chroma,
2. tracks the beat and averages the chroma per beat,
3. finds the key, and key changes, from key profiles and later from the
   chords' harmonic functions,
4. decodes the whole chord sequence at once (minimum-duration Viterbi): each
   chord must last at least the shortest-chord length, every change costs,
   chords that belong to the key are preferred (secondary dominants and
   borrowed chords are cheaper than random ones), and strong root motion such
   as V7 to I is preferred,
5. lets a change land half a beat early or late when the audio says so
   (anticipated chords),
6. names each chord in its local key.

Vocabulary: by default major, minor, 7, dim and sus4 ("standard"), plus N.C.
Settings can switch to "full" (adds maj7, m7, aug, sus2, m7b5) or "triads".
On real recordings "full" tends to label melody notes as maj7/sus2, so it is opt-in.

## Using the engine in other scripts

```lua
local CD = dofile(path .. "ChordDetector_Engine.lua")

-- from a take (times are item time, 0 = item start)
local res = CD.analyze_take(take, { min_beats = 2, vocabulary = "full" })

-- or from your own mono samples (1-based table, any sample rate)
local res = CD.analyze(samples, samplerate, opts)

res.key      -- { tonic = 3, mode = "major", name = "Eb major", short = "Eb", confidence = 0.9 }
res.keys     -- key areas: { start, stop, tonic, mode, name, short }
res.chords   -- { start, stop, root, quality, bass, name, confidence, key }
res.tempo, res.beats, res.tuning_cents, res.duration

CD.chord_name(10, "7", { tonic = 3, mode = "major" })  --> "Bb7"
CD.spell_note(6, { tonic = 9, mode = "minor" })        --> "F#"
CD.key_name({ tonic = 8, mode = "minor" })             --> "G# minor", "G#m"
CD.item_to_source_time(take, t)                        -- for take markers
```

Options (all optional, see `M.DEFAULTS`): `vocabulary`, `min_beats`,
`beat_sync`, `min_seconds`, `change_penalty`, `key_weight`, `key_changes`,
`min_key_beats`, `slash_chords`, `refine`, `no_chord`, `tuning`, `progress`.
`progress(fraction, label)` is called during analysis; calling
`coroutine.yield()` from it lets a script run the analysis in the background
with `reaper.defer`, as the action does.

Important: REAPER returns silence from `GetAudioAccessorSamples` when it is
called inside a Lua coroutine. So read the audio outside the coroutine:
`CD.analyze_take` / `CD.read_take` from the main script body (blocking), or
`CD.take_reader(take)` with `rd:step(0.03)` once per defer cycle, then run
`CD.analyze(rd.samples, rd.sr, opts)` in a coroutine and
`CD.shift_result(res, rd.t_start)`.

Pure Lua 5.4; it avoids math.pow / sinh / cosh / tanh, which REAPER lacks.
Speed: about 12 s for a 4 minute song.

## Tests

```
python3 tests/synth_songs.py /tmp/cdtest       # 15 synthesised songs with known chords
lua tests/run_tests.lua /tmp/cdtest            # FFT, spelling, decoder, accuracy per song
lua tests/mock_reaper_test.lua /tmp/cdtest     # the action against a mocked REAPER API
```

Known limits: stretch markers on the take are ignored when placing markers;
the songs in the tests are synthesised, so real mixes (vocals, distortion)
will score lower than the test numbers.

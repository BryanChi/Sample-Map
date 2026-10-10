# Sample Map

REAPER script that scans audio folders into an interactive 2D sample map, with a drum sequencer, preview, and companion JSFX player.

## Requirements

- [REAPER](https://www.reaper.fm/)
- [ReaImGui](https://forum.cockos.com/showthread.php?t=250419) (ReaPack)
- [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174) (ReaPack; recommended for folder browsing)
- Python 3 (optional; used for sample analysis, groove MIDI, and AI pattern variation)
- ffmpeg or sox (optional; analysis of non-WAV formats)

## Install

1. Clone this repo into REAPER's Scripts folder, for example:

   `~/Library/Application Support/REAPER/Scripts/Sample Map`

2. Copy the JSFX files from `Effects/` into REAPER's Effects folder:

   `~/Library/Application Support/REAPER/Effects/`

3. In REAPER: **Actions → Show action list → Load ReaScript…** and load:

   - `Sample Map Browser.lua`
   - `Sample Map - Quick swap for selected item.lua` (optional companion)

   Keep the `browser/` folder next to `Sample Map Browser.lua`; the script loads its modules from there.

## Using the UI

- **Library** menu: rescan / resume, manage scan folders, and *Re-analyze* passes (effective range, transients, loop / one-shot, weight).
- **View** menu: switch between Sample Map and Sequencer, toggle the File Explorer, or pop either view into its own window.
- **Tools** menu: copy scan logs and debug helpers.
- **Settings** are grouped by area (Library, Sample Map, Tags, Sequencer, General) and searchable.
- **Fills** (sequencer): open the fill designer from the fill icon on a region, the *Fill* button in the toolbar, or the *Fill* chip on a razor area (Alt + right-drag; REAPER's own razor edits work too). Fills land at phrase ends (every 2/4/8/16 bars) and right before the region ends, or exactly in the razor areas. Pick a fill from the library, switch the span to a pattern preset, roll random fills with the dice, or Ctrl+click several to mix them across the spots.

## Layout

| Path | Role |
| --- | --- |
| `Sample Map Browser.lua` | Entry point: checks dependencies and loads `browser/` |
| `browser/NN_*.lua` | The browser itself (map, sequencer, explorer, settings), loaded in numeric order |
| `Sample Map - Quick swap for selected item.lua` | Replace the selected item's sample from the map |
| `SampleMapAnalyzer.py` | External audio analysis sidecar |
| `SampleMapDrumAI.py` | Local drum-pattern variation |
| `SampleMapGrooveMIDI.py` | Magenta Groove MIDI Dataset sidecar |
| `Effects/SampleMapMIDI.jsfx` | MIDI → gmem bridge |
| `Effects/SampleMapPlayer.jsfx` | Per-track layered sampler |
| `Effects/SampleMapPreview.jsfx` | Preview bus passthrough |
| `assets/` | Sequencer / map icons |
| `tag_presets.default.lua` | Default tag color palettes (your edits are saved to `tag_presets.lua`) |
| `tests/` | Syntax checks, a stub-REAPER load test and unit tests (run by CI) |

## Development

The browser is split into modules under `browser/`. They run in order and share globals,
so a helper defined in an earlier module is visible to later ones. To check changes locally:

```sh
pip install lupa pytest numpy
python3 tests/lua_syntax.py *.lua browser/*.lua
python3 tests/load_browser.py . 30   # runs the script for 30 frames against a stub REAPER API
pytest -q tests
```

Local files such as `SampleMapData.json` and `SampleMapBrowser.json` are generated at runtime and are not committed.

Behringer mixer icons in `assets/behringer-icons/` are GPL-3.0; see `assets/behringer-icons/ATTRIBUTION.md`.

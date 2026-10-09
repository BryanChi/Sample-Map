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

## Using the UI

- **Library** menu: rescan / resume, manage scan folders, and *Re-analyze* passes (effective range, transients, loop / one-shot, weight).
- **View** menu: switch between Sample Map and Sequencer, toggle the File Explorer, or pop either view into its own window.
- **Tools** menu: copy scan logs and debug helpers.
- **Settings** are grouped by area (Library, Sample Map, Tags, Sequencer, General) and searchable.

## Layout

| Path | Role |
| --- | --- |
| `Sample Map Browser.lua` | Main UI (map + sequencer) |
| `Sample Map - Quick swap for selected item.lua` | Replace the selected item's sample from the map |
| `SampleMapAnalyzer.py` | External audio analysis sidecar |
| `SampleMapDrumAI.py` | Local drum-pattern variation |
| `SampleMapGrooveMIDI.py` | Magenta Groove MIDI Dataset sidecar |
| `Effects/SampleMapMIDI.jsfx` | MIDI → gmem bridge |
| `Effects/SampleMapPlayer.jsfx` | Per-track layered sampler |
| `Effects/SampleMapPreview.jsfx` | Preview bus passthrough |
| `assets/` | Sequencer / map icons |
| `tag_presets.default.lua` | Default tag color palettes (your edits are saved to `tag_presets.lua`) |

Local files such as `SampleMapData.json` and `SampleMapBrowser.json` are generated at runtime and are not committed.

Behringer mixer icons in `assets/behringer-icons/` are GPL-3.0; see `assets/behringer-icons/ATTRIBUTION.md`.

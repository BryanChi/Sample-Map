# In-script feedback → GitHub issues

Users of Sample Map, FX Devices and Vertical FX List can send a report from inside the script: a bug, an idea or a question, a note, up to 5 pictures (files, drag-and-drop, or a screenshot) and, if they tick the box, a usage log. Each report becomes a GitHub issue on that script's repository, labelled `user-report` plus `bug` / `enhancement` / `question` / `feedback` and `os:mac` / `os:windows` / `os:linux`.

```
script (CRS_Feedback.lua) --curl--> relay (Cloudflare Worker, holds the token) --> GitHub issue
                                           \--> pictures and long logs (Cloudflare KV, linked from the issue)
```

No GitHub token ships inside the scripts. The relay is the only thing that holds one.

## Files

| Path | What |
|---|---|
| `CRS_Feedback.lua` | The window. One file, copied unchanged into each script. |
| `CRS_Feedback_Recorder.lua` | The recording badge and send window as their own script, so they survive a crash of the script being recorded. Copied next to `CRS_Feedback.lua`. |
| `relay/src/index.js` | The Cloudflare Worker. |
| `relay/wrangler.toml` | Worker config (name, KV storage, rate limit). |
| `relay/test/` | Worker tests (`npm test`). |

## One-time setup (bryan)

You need a free Cloudflare account and Node.js (`node -v` in Terminal; install from nodejs.org if missing).

1. **GitHub token.** Open <https://github.com/settings/personal-access-tokens/new>.
   - Name: `CRS feedback relay`. Expiration: the longest offered (put a reminder in your calendar).
   - Repository access: *Only select repositories* → `Sample-Map`, `BryanChi-FX-Devices`, `Vertical-FX-List`.
   - Permissions → Repository permissions → **Issues: Read and write**. Nothing else.
   - Generate, and copy the token (starts with `github_pat_`).
2. **Deploy the relay.** In Terminal, from this folder:
   ```sh
   cd relay
   npm install
   npx wrangler login                        # opens the browser; click Allow
   npx wrangler kv namespace create FEEDBACK # prints an id
   ```
   Paste the printed `id` into `wrangler.toml` in place of `PASTE-KV-ID-HERE`, then:
   ```sh
   npx wrangler secret put GITHUB_TOKEN      # paste the token from step 1
   npx wrangler deploy                       # prints https://crs-feedback.<you>.workers.dev
   ```
3. **Check it.** Open the printed URL in a browser; it should show `{"ok":true,"service":"crs-feedback"}`.
4. **Point the scripts at it.** Set `F.ENDPOINT` near the top of `CRS_Feedback.lua` to `https://crs-feedback.<you>.workers.dev/report` in each script's copy (or ask Claude to). Until then the window opens but tells users reporting isn't set up, and offers "Copy report" instead.

To test against a different relay without editing files, run this once in REAPER's ReaScript console:
`reaper.SetExtState("CRS_Feedback", "endpoint", "https://.../report", true)` (an empty string clears it).

## Adding the window to a script

```lua
local ok, Feedback = pcall(dofile, script_dir .. "/CRS_Feedback.lua")
if ok then
  Feedback.Setup({
    script_id = "sample-map",        -- must be listed in DEFAULT_SCRIPTS in relay/src/index.js
    script_name = "Sample Map",
    version = "0.1.0",
    repo = "BryanChi/Sample-Map",    -- shown in the "posted publicly on ..." notice
    get_log = function() return my_recent_log_lines end, -- optional
  })
end
-- in a menu:
if ImGui.MenuItem(ctx, "Send feedback...") then CRSFeedback.Open() end
-- anywhere:
CRSFeedback.Log("Loaded preset 'Warm'")
-- optional, instead of reaper.defer(loop): a crash opens the window with the error filled in
CRSFeedback.Defer(loop)
```

The window has its own ImGui context and defer loop, so it looks the same in every script and the host only calls `Open()`. It needs curl (built into macOS and Windows 10+).

A new script needs a line in `DEFAULT_SCRIPTS` in `relay/src/index.js` (id → repo) and a redeploy (`npx wrangler deploy`). The relay refuses any other script id, so nobody can use it to post to other repositories.

## What gets sent

- Title, note, kind, optional contact. The window says the issue is public.
- Environment: script version, REAPER version, OS, ReaImGui version, whether JS_ReaScriptAPI / SWS are installed, and a random per-install id (to tell whether several reports come from the same person).
- Usage log, only when the box is ticked: lines from `CRSFeedback.Log` (kept in `<REAPER>/Data/CRS_Feedback/<script>.log`, so the last session's lines survive a crash) and the script's own `get_log` lines. "Show what's sent" displays exactly this text. The REAPER folder becomes `<REAPER>`, the home folder `~`, and user names in `/Users/…`, `/home/…` and `C:\Users\…` become `<user>`.
- Pictures are copied to a temp name before upload, so original file names don't leak.

## Bug recording

For bugs that are hard to pin down. On the window's **Bug** tab, users press **Start bug recording**; the window closes and a small red "Recording bug details" badge stays on top. They repeat the problem, then press **Stop and send** on the badge: the window opens again with the recording attached (a checkbox, plus "Show what's sent" to read it). **Stop** keeps the recording for later; **Discard recording** in the window throws it away.

While it's on, the script runs a little slower and the module writes down:

- every REAPER call the script makes that changes something (`Set…`, `Add…`, `Delete…`, `Insert…`, `Main_OnCommand`, `Undo_…`, `GetSet…` when setting, and so on), with its arguments and result; tracks are shown as `<track 3 "Bass">`;
- every button, menu item, checkbox, slider, drag, combo and text field the user changes, plus shortcut keys and mouse clicks the script reacts to (through the host's ImGui table and `reaper.ImGui_*`);
- errors with a traceback (from `reaper.defer` callbacks), frames slower than 50 ms, and every 10 s the frame count, slowest frame and Lua memory;
- REAPER undo points and transport changes;
- the host's own lines: `CRSFeedback.Trace("...")`, and `get_state()` at start and stop if the host gives one.

Repeats in a row collapse into one line with a count (a slider dragged, a parameter set every frame). It's kept in memory (last 6,000 lines) and in `<REAPER>/Data/CRS_Feedback/<script>.recording.log`. Recording stays on across a restart, so startup bugs are caught; if the host's window closes, the badge closes with it. A report includes at most the last 420 KB of it, which fits the relay's 512 KB log limit (the issue shows the last 30,000 characters and links the rest).

Privacy: typed text is never recorded, only its length. ExtState values and shell commands are hidden, e-mail addresses and long tokens (license keys, hashes) are masked, and personal folder names are scrubbed as in the usage log.

Optional `Setup` fields: `imgui` (the script's ImGui API table; globals `ImGui` and `im` are found on their own), `get_state` (returns lines describing the script's state), `on_recording(on)` (switch the script's own debug output). Call `Setup` at startup so a recording left on resumes.

## Spam and limits

- Per IP: 5 reports per 10 minutes, 20 per day (plus a 5-per-minute burst limit). All users together: 300 per day. IPs are only stored as salted hashes.
- Pictures: PNG / JPG / GIF / WebP only (checked by content), 5 MB each, 5 per report. Note: 8,000 characters. Logs over 30,000 characters are trimmed in the issue with a link to the full log.
- The same report sent twice within 15 minutes returns the first issue.
- Reporter text can't @-mention people or auto-close issues (`fixes #3`).

## Working on reports with Claude

Every report carries the `user-report` label, so in the project you can ask "check new user reports on Sample Map" and Claude can read the issue, its pictures and log, fix it, and open a PR that closes it.

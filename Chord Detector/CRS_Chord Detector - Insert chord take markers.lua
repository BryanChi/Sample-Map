-- @description Chord Detector: detect chords and key, insert take markers at chord changes
-- @author Bryan Chi
-- @version 1.0
-- @about
--   Analyses the active take of every selected audio item, finds the key and
--   the chords (with musical context: beats, key, chord functions, minimum
--   chord length) and writes a take marker at each chord change, spelled with
--   the key's sharps or flats. Re-running replaces the markers it wrote before.
--   Settings: "CRS_Chord Detector - Settings.lua".

local r = reaper
local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or ""
local CD = dofile(script_dir .. "ChordDetector_Engine.lua")

local EXT = "CRS_ChordDetector"
local CHORD_COLOR = r.ColorToNative(90, 200, 150) | 0x1000000
local NC_COLOR = r.ColorToNative(110, 110, 110) | 0x1000000
local KEY_COLOR = r.ColorToNative(230, 170, 60) | 0x1000000
local OUR_COLORS = { [CHORD_COLOR] = true, [NC_COLOR] = true, [KEY_COLOR] = true }

local function get_setting(key, default)
  local v = r.GetExtState(EXT, key)
  if v == "" then return default end
  if type(default) == "number" then return tonumber(v) or default end
  if type(default) == "boolean" then return v == "1" or v == "true" end
  return v
end

local settings = {
  vocabulary     = get_setting("vocabulary", "standard"),
  min_beats      = get_setting("min_beats", 2),
  change_penalty = get_setting("change_penalty", 2.0),
  key_changes    = get_setting("key_changes", true),
  slash_chords   = get_setting("slash_chords", false),
  key_in_marker  = get_setting("key_in_marker", true),
  mark_no_chord  = get_setting("mark_no_chord", true),
  neural         = get_setting("neural", true),
}

-- collect takes
local jobs = {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local take = r.GetActiveTake(item)
  if take and not r.TakeIsMIDI(take) then
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    jobs[#jobs + 1] = { item = item, take = take, name = name }
  end
end
if #jobs == 0 then
  r.MB("Select one or more audio items first.", "Chord Detector", 0)
  return
end

-- high-accuracy mode: the BTC neural chord model (pure Lua, slower)
local BTC_OPT
if settings.neural then
  local ok, lib = pcall(dofile, script_dir .. "ChordDetector_BTC.lua")
  local okw, weights = false, nil
  if ok then okw, weights = pcall(lib.load, script_dir .. "ChordDetector_BTC.bin") end
  if ok and okw then BTC_OPT = { lib = lib, weights = weights }
  else r.ShowConsoleMsg("Chord Detector: neural model not found, using the fast detector\n") end
end

---------------------------------------------------------------------------
-- writing markers
---------------------------------------------------------------------------

local function remove_old_markers(take)
  for i = r.GetNumTakeMarkers(take) - 1, 0, -1 do
    local _, _, color = r.GetTakeMarker(take, i)
    if OUR_COLORS[color] then r.DeleteTakeMarker(take, i) end
  end
end

local function serialize(res)
  local lines = { "key\t" .. res.key.name }
  for _, k in ipairs(res.keys) do lines[#lines + 1] = ("area\t%.4f\t%.4f\t%s"):format(k.start, k.stop, k.name) end
  for _, c in ipairs(res.chords) do
    lines[#lines + 1] = ("chord\t%.4f\t%.4f\t%s\t%s\t%s\t%.2f"):format(c.start, c.stop, c.name,
      c.root or "", c.quality or "", c.confidence or 0)
  end
  if res.tempo then lines[#lines + 1] = ("tempo\t%.2f"):format(res.tempo) end
  return table.concat(lines, "\n")
end

local function write_markers(job, res)
  local take = job.take
  remove_old_markers(take)
  -- the chord that announces each key area: first real chord of the area
  local key_label = {}
  if settings.key_in_marker then
    for _, k in ipairs(res.keys) do
      for ci, c in ipairs(res.chords) do
        if c.root and c.stop > k.start + 0.05 and not key_label[ci] then
          key_label[ci] = k.name
          break
        end
      end
    end
  end
  local count = 0
  for ci, c in ipairs(res.chords) do
    local label, color = c.name, c.root and CHORD_COLOR or NC_COLOR
    if key_label[ci] then label = label .. "  (key " .. key_label[ci] .. ")"; color = KEY_COLOR end
    if c.root or settings.mark_no_chord then
      r.SetTakeMarker(take, -1, label, CD.item_to_source_time(take, math.max(0, c.start)), color)
      count = count + 1
    end
  end
  r.GetSetMediaItemTakeInfo_String(take, "P_EXT:" .. EXT, serialize(res), true)
  return count
end

---------------------------------------------------------------------------
-- background analysis with a small progress window
---------------------------------------------------------------------------

-- REAPER returns silence from GetAudioAccessorSamples inside a coroutine, so
-- audio is read in the defer loop itself; only the analysis runs in a coroutine.
local status = { job = 1, frac = 0, label = "Reading audio" }
local results = {}
local last_yield = r.time_precise()
local reader, worker

local function maybe_yield()
  local now = r.time_precise()
  if now - last_yield > 0.04 then
    last_yield = now
    coroutine.yield()
  end
end

local function analysis_opts()
  return {
    vocabulary = settings.vocabulary,
    min_beats = settings.min_beats,
    change_penalty = settings.change_penalty,
    key_changes = settings.key_changes,
    slash_chords = settings.slash_chords,
    no_chord = settings.mark_no_chord and "N.C." or false,
    btc = BTC_OPT,
    progress = function(p, label) status.frac = 0.15 + 0.85 * p; status.label = label; maybe_yield() end,
  }
end

-- one slice of work per defer cycle; returns true when every job is done
local function work()
  local job = jobs[status.job]
  if not job then return true end
  if not worker then
    if not reader then reader = CD.take_reader(job.take) end
    local done, frac = reader:step(0.03)
    status.frac, status.label = 0.15 * frac, "Reading audio"
    if done then
      local rd = reader
      worker = coroutine.create(function()
        return CD.shift_result(CD.analyze(rd.samples, rd.sr, analysis_opts()), rd.t_start)
      end)
    end
    return false
  end
  last_yield = r.time_precise()
  local ok, res = coroutine.resume(worker)
  if not ok then error(res, 0) end
  if coroutine.status(worker) == "dead" then
    results[status.job] = res
    reader, worker = nil, nil
    status.job, status.frac = status.job + 1, 0
  end
  return status.job > #jobs
end

local W, H = 380, 74
gfx.init("Chord Detector", W, H)
gfx.setfont(1, "Arial", 15)

local function draw()
  gfx.set(0.11, 0.11, 0.12, 1); gfx.rect(0, 0, W, H, 1)
  gfx.set(0.9, 0.9, 0.9, 1)
  gfx.x, gfx.y = 12, 10
  local nm = jobs[status.job] and jobs[status.job].name or ""
  if #nm > 34 then nm = nm:sub(1, 33) .. "…" end
  gfx.drawstr(("%s  (%d/%d)"):format(nm, status.job, #jobs))
  gfx.set(0.6, 0.6, 0.62, 1)
  gfx.x, gfx.y = 12, 30
  gfx.drawstr(status.label .. "…   Esc to cancel")
  gfx.set(0.25, 0.25, 0.27, 1); gfx.rect(12, 52, W - 24, 8, 1)
  local total = ((status.job - 1) + status.frac) / #jobs
  gfx.set(0.35, 0.78, 0.59, 1); gfx.rect(12, 52, math.floor((W - 24) * total), 8, 1)
  gfx.update()
end

local function finish()
  gfx.quit()
  r.Undo_BeginBlock()
  local summary = {}
  for i, job in ipairs(jobs) do
    local res = results[i]
    if res and res.key then
      local n = write_markers(job, res)
      local keys = {}
      for _, k in ipairs(res.keys) do keys[#keys + 1] = k.name end
      summary[#summary + 1] = ("%s: %s, %d markers%s"):format(job.name, table.concat(keys, " -> "), n,
        res.tempo and (", %.0f BPM"):format(res.tempo) or "")
      local any = false
      for _, c in ipairs(res.chords) do if c.root then any = true end end
      local st = res.stats
      if not any and st then
        r.ShowConsoleMsg(("Chord Detector: no chords found in %s. Audio peak %.4f, beats %d, silent %.0f%%, "
          .. "best chord %.2f vs no-chord %.2f, flatness %.2f\n"):format(job.name, st.input_peak, st.beats,
          100 * st.silent, st.best_chord, st.no_chord, st.flatness))
      end
    elseif res then
      summary[#summary + 1] = ("%s: skipped (%s)"):format(job.name, res.error or "no audio")
    end
  end
  r.UpdateArrange()
  r.Undo_EndBlock("Chord Detector: insert chord take markers", -1)
  if #summary > 0 then r.Help_Set("Chord Detector: " .. table.concat(summary, " | "), false) end
end

local function loop()
  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then                           -- cancelled, nothing written
    if reader then reader:cancel() end
    gfx.quit(); return
  end
  local ok, finished = pcall(work)
  if not ok then
    if reader then reader:cancel() end
    gfx.quit()
    r.ShowConsoleMsg("Chord Detector error: " .. tostring(finished) .. "\n")
    return
  end
  if finished then finish(); return end
  draw()
  r.defer(loop)
end

draw()
r.defer(loop)

-- @description Bloom Study Kit: black-box measurement of an adaptive tone shaper
-- @author Bryan Chi
-- @about
--   Renders a fixed set of test signals through the first FX on a track whose name matches
--   TARGET_FX (default "bloom"), for a list of parameter cases, and writes the dry signals,
--   the rendered outputs, a parameter dump and manifest.json into <project folder>/Bloom Study/.
--   Only the plug-in's audio output and its public parameter list are used: nothing inspects
--   the plug-in binary. Analyse the results with analyze_bloom.py (numpy only).
--
--   Use: save an EMPTY project somewhere first (outputs go next to it), then run this script.

local TARGET_FX   = 'bloom'          -- matched case-insensitively against the FX name
local ADD_NAMES   = { 'VST3: bloom (oeksound)', 'VST3: bloom', 'AU: bloom (oeksound)', 'VST: bloom (oeksound)', 'bloom' }
local TRY_PRESET  = 'Factory default'

-- Role -> Lua patterns matched against lower-cased parameter names. First match wins.
-- If the dump shows other names, edit these and run again (signals are reused).
local ROLES = {
  amount     = { '^amount' },
  attack     = { '^attack' },
  release    = { '^release' },
  mix        = { '^mix', 'dry/wet', 'wet/dry' },
  wet_trim   = { 'wet trim' },
  squash_cal = { 'squash cal', 'squash' },
  output     = { '^output', 'out gain' },
  quality    = { 'quality' },
  stereo     = { 'stereo mode', '^stereo' },
  link       = { 'channel link', '^link', 'stereo link' },
  tone1      = { '^level 1 %(main', 'tone 1 level', 'lows? level', 'tone ?1$', 'band 1 gain', 'low level' },
  tone2      = { '^level 2 %(main', 'tone 2 level', 'lo%-?mids? level', 'tone ?2$', 'band 2 gain' },
  tone3      = { '^level 3 %(main', 'tone 3 level', 'hi%-?mids? level', 'tone ?3$', 'band 3 gain' },
  tone4      = { '^level 4 %(main', 'tone 4 level', 'highs? level', 'tone ?4$', 'band 4 gain' },
  tone2_freq = { '^freq 2 %(main', 'tone 2 freq', 'lo%-?mids? freq', 'band 2 freq' },
}

-- A setting is: number = displayed value to reach (bisection on the formatted text),
-- {n = x} = normalized value, {text = 'High'} = first normalized step whose text contains it.
local ST = { 'S01_pink', 'S02_white', 'S03_brown', 'S04_bright', 'S05_dark', 'S06_bumps', 'S07_hole' }
local function plus(a, b) local t = {} for _, v in ipairs(a) do t[#t + 1] = v end for _, v in ipairs(b) do t[#t + 1] = v end return t end
local DYN = { 'S08_ladder', 'S09_switch', 'S10_burst', 'S11_clicks' }

local CASES = {
  { id = 'C01_amount0',   set = { amount = 0 },   sig = { 'S01_pink', 'S06_bumps', 'S11_clicks' } },
  { id = 'C02_amount1',   set = { amount = 1 },   sig = ST },
  { id = 'C03_amount3',   set = { amount = 3 },   sig = ST },
  { id = 'C04_amount5',   set = { amount = 5 },   sig = plus(ST, DYN) },
  { id = 'C05_amount7',   set = { amount = 7 },   sig = plus(ST, DYN) },
  { id = 'C06_amount8_5', set = { amount = 8.5 }, sig = { 'S01_pink', 'S06_bumps', 'S08_ladder', 'S10_burst', 'S11_clicks' } },
  { id = 'C07_amount10',  set = { amount = 10 },  sig = { 'S01_pink', 'S06_bumps', 'S08_ladder', 'S10_burst', 'S11_clicks' } },
  { id = 'C08_sqcal_hi',  set = { amount = 10, squash_cal = { n = 1 } }, sig = { 'S08_ladder' } },
  { id = 'C09_sqcal_lo',  set = { amount = 10, squash_cal = { n = 0 } }, sig = { 'S08_ladder' } },
  { id = 'C10_att_min',   set = { amount = 7, attack = { n = 0 } },  sig = { 'S09_switch', 'S10_burst', 'S11_clicks' } },
  { id = 'C11_att_max',   set = { amount = 7, attack = { n = 1 } },  sig = { 'S09_switch', 'S10_burst', 'S11_clicks' } },
  { id = 'C12_rel_min',   set = { amount = 7, release = { n = 0 } }, sig = { 'S09_switch', 'S10_burst', 'S11_clicks' } },
  { id = 'C13_rel_max',   set = { amount = 7, release = { n = 1 } }, sig = { 'S09_switch', 'S10_burst', 'S11_clicks' } },
  { id = 'C14_tone1_up',  set = { amount = 7, tone1 = { n = 1 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C15_tone1_dn',  set = { amount = 7, tone1 = { n = 0 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C16_tone2_up',  set = { amount = 7, tone2 = { n = 1 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C17_tone2_dn',  set = { amount = 7, tone2 = { n = 0 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C18_tone3_up',  set = { amount = 7, tone3 = { n = 1 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C19_tone3_dn',  set = { amount = 7, tone3 = { n = 0 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C20_tone4_up',  set = { amount = 7, tone4 = { n = 1 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C21_tone4_dn',  set = { amount = 7, tone4 = { n = 0 } }, sig = { 'S01_pink', 'S05_dark' } },
  { id = 'C22_t2f_low',   set = { amount = 7, tone2 = { n = 1 }, tone2_freq = { n = 0.25 } }, sig = { 'S01_pink' } },
  { id = 'C23_t2f_high',  set = { amount = 7, tone2 = { n = 1 }, tone2_freq = { n = 0.75 } }, sig = { 'S01_pink' } },
  { id = 'C24_q_high',    set = { amount = 7, quality = { text = 'high' } },  sig = { 'S01_pink', 'S06_bumps', 'S09_switch', 'S11_clicks' } },
  { id = 'C25_q_lowlat',  set = { amount = 7, quality = { text = 'low' } },   sig = { 'S01_pink', 'S06_bumps', 'S09_switch', 'S11_clicks' } },
  { id = 'C26_st_linked', set = { amount = 7, stereo = { text = 'link' } },   sig = { 'S12_stereo' } },
  { id = 'C27_st_lr',     set = { amount = 7, stereo = { text = 'l/r' }, link = { n = 0 } }, sig = { 'S12_stereo' } },
  { id = 'C28_st_ms',     set = { amount = 7, stereo = { text = 'm/s' }, link = { n = 0 } }, sig = { 'S12_stereo' } },
  { id = 'C29_mix50',     set = { amount = 7, mix = { n = 0.5 } }, sig = { 'S06_bumps', 'S11_clicks' } },
}

---------------------------------------------------------------- utils
local r = reaper
local function msg(s) r.ShowConsoleMsg(tostring(s) .. '\n') end
local SEP = package.config:sub(1, 1)
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or ''

local function copy_file(src, dst)
  local a = io.open(src, 'rb'); if not a then return false end
  local b = io.open(dst, 'wb'); if not b then a:close() return false end
  while true do local d = a:read(1 << 20); if not d then break end b:write(d) end
  a:close(); b:close(); return true
end
local function exists(p) local f = io.open(p, 'rb') if f then f:close() return true end return false end

local function json(v, ind)
  ind = ind or ''
  local t = type(v)
  if t == 'nil' then return 'null' end
  if t == 'boolean' or t == 'number' then return tostring(v) end
  if t == 'string' then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"' end
  local ni = ind .. '  '
  if #v > 0 or next(v) == nil then
    local p = {} for _, x in ipairs(v) do p[#p + 1] = ni .. json(x, ni) end
    return '[\n' .. table.concat(p, ',\n') .. '\n' .. ind .. ']'
  end
  local keys = {} for k in pairs(v) do keys[#keys + 1] = k end table.sort(keys)
  local p = {} for _, k in ipairs(keys) do p[#p + 1] = ni .. json(tostring(k)) .. ': ' .. json(v[k], ni) end
  return '{\n' .. table.concat(p, ',\n') .. '\n' .. ind .. '}'
end

---------------------------------------------------------------- plug-in parameters
local tr, fx
local function pname(p) local _, n = r.TrackFX_GetParamName(tr, fx, p, '') return n end
local function fmt_norm(p, v)
  local ok, s = r.TrackFX_FormatParamValueNormalized(tr, fx, p, v, '')
  if ok and s ~= '' then return s end
  local old = r.TrackFX_GetParamNormalized(tr, fx, p)
  r.TrackFX_SetParamNormalized(tr, fx, p, v)
  local _, s2 = r.TrackFX_GetFormattedParamValue(tr, fx, p, '')
  r.TrackFX_SetParamNormalized(tr, fx, p, old)
  return s2
end
local function num(s) return tonumber((s or ''):match('[-+]?%d*%.?%d+')) end

local function find_role(role)
  local pats = ROLES[role]; if not pats then return nil end
  for _, pat in ipairs(pats) do
    for p = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
      if pname(p):lower():find(pat) then return p end
    end
  end
end

local function set_param(p, want)
  if type(want) == 'number' then             -- bisection on the displayed number (assumes monotonic)
    local lo, hi = 0, 1
    local vlo, vhi = num(fmt_norm(p, 0)), num(fmt_norm(p, 1))
    if not vlo or not vhi then return false, 'no numeric display' end
    local up = vhi >= vlo
    for _ = 1, 40 do
      local mid = (lo + hi) / 2
      local v = num(fmt_norm(p, mid)) or 0
      if (v < want) == up then lo = mid else hi = mid end
    end
    r.TrackFX_SetParamNormalized(tr, fx, p, (lo + hi) / 2)
  elseif want.n then
    r.TrackFX_SetParamNormalized(tr, fx, p, want.n)
  elseif want.text then
    local found
    for i = 0, 200 do
      local v = i / 200
      if fmt_norm(p, v):lower():find(want.text, 1, true) then found = v break end
    end
    if not found then return false, 'no step shows "' .. want.text .. '"' end
    r.TrackFX_SetParamNormalized(tr, fx, p, found)
  end
  local _, s = r.TrackFX_GetFormattedParamValue(tr, fx, p, '')
  return true, s
end

local function dump_params(path)
  local f = io.open(path, 'w')
  local out = {}
  for p = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
    local row = { index = p, name = pname(p), default_norm = r.TrackFX_GetParamNormalized(tr, fx, p), steps = {} }
    local _, cur = r.TrackFX_GetFormattedParamValue(tr, fx, p, '')
    row.default_text = cur
    for i = 0, 20 do row.steps[#row.steps + 1] = { n = i / 20, text = fmt_norm(p, i / 20) } end
    out[#out + 1] = row
    f:write(('%3d  %-32s default %-12s  0:%s  0.25:%s  0.5:%s  0.75:%s  1:%s\n'):format(p, row.name, cur,
      row.steps[1].text, row.steps[6].text, row.steps[11].text, row.steps[16].text, row.steps[21].text))
  end
  f:close()
  return out
end

---------------------------------------------------------------- main
local function main()
  local proj_path = r.GetProjectPath('')
  local _, proj_file = r.EnumProjects(-1, '')
  if proj_file == '' then
    r.MB('Save an empty project first. The study folder is created next to it.', 'Bloom Study Kit', 0) return
  end
  local root = proj_path .. SEP .. 'Bloom Study'
  local sig_dir, out_dir = root .. SEP .. 'signals', root .. SEP .. 'renders'
  r.RecursiveCreateDirectory(sig_dir, 0); r.RecursiveCreateDirectory(out_dir, 0)
  r.ClearConsole()
  msg('Bloom Study Kit -> ' .. root)

  r.GetSetProjectInfo(0, 'PROJECT_SRATE', 48000, true)
  r.GetSetProjectInfo(0, 'PROJECT_SRATE_USE', 1, true)

  -- 1. signals (reused when already there)
  local S = dofile(here .. 'Bloom Study Signals.lua')
  local signals
  if exists(sig_dir .. SEP .. 'S12_stereo.wav') then
    signals = {}
    for _, s in ipairs({ 'S01_pink','S02_white','S03_brown','S04_bright','S05_dark','S06_bumps','S07_hole','S08_ladder','S09_switch','S10_burst','S11_clicks','S12_stereo' }) do
      signals[#signals + 1] = { id = s, file = sig_dir .. SEP .. s .. '.wav', channels = (s == 'S12_stereo') and 2 or 1 }
    end
    msg('Reusing signals in ' .. sig_dir)
  else
    msg('Generating signals (about 20 s)...')
    signals = S.WriteAll(sig_dir)
  end
  local sig_by_id = {} for _, s in ipairs(signals) do sig_by_id[s.id] = s end

  -- 2. track + plug-in
  r.Undo_BeginBlock()
  r.InsertTrackAtIndex(r.CountTracks(0), true)
  tr = r.GetTrack(0, r.CountTracks(0) - 1)
  r.GetSetMediaTrackInfo_String(tr, 'P_NAME', 'Bloom study', true)
  r.SetMediaTrackInfo_Value(tr, 'I_NCHAN', 2)
  fx = -1
  for _, n in ipairs(ADD_NAMES) do
    fx = r.TrackFX_AddByName(tr, n, false, 1)
    if fx >= 0 then
      local _, nm = r.TrackFX_GetFXName(tr, fx, '')
      if nm:lower():find(TARGET_FX, 1, true) then break end
      r.TrackFX_Delete(tr, fx); fx = -1
    end
  end
  if fx < 0 then r.MB('Could not add "' .. TARGET_FX .. '". Is it installed and scanned?', 'Bloom Study Kit', 0) return end
  local _, fxname = r.TrackFX_GetFXName(tr, fx, '')
  msg('Plug-in: ' .. fxname)
  if TRY_PRESET then r.TrackFX_SetPreset(tr, fx, TRY_PRESET) end
  r.TrackFX_Show(tr, fx, 2)    -- keep the floating window closed

  local params = dump_params(root .. SEP .. 'params.txt')
  local roles = {}
  for role in pairs(ROLES) do roles[role] = find_role(role) end
  msg('Parameter roles:')
  for role, p in pairs(roles) do msg(('  %-10s -> %s'):format(role, p and (p .. ' ' .. pname(p)) or 'NOT FOUND')) end
  local baseline = {}
  for p = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do baseline[p] = r.TrackFX_GetParamNormalized(tr, fx, p) end
  local _, lat = r.TrackFX_GetNamedConfigParm(tr, fx, 'pdc')

  -- 3. one item per signal, laid out on the track
  local items, pos = {}, 0
  for _, s in ipairs(signals) do
    local it = r.AddMediaItemToTrack(tr)
    local tk = r.AddTakeToMediaItem(it)
    local src = r.PCM_Source_CreateFromFile(s.file)
    r.SetMediaItemTake_Source(tk, src)
    local len = r.GetMediaSourceLength(src)
    r.SetMediaItemInfo_Value(it, 'D_POSITION', pos)
    r.SetMediaItemInfo_Value(it, 'D_LENGTH', len)
    r.GetSetMediaItemTakeInfo_String(tk, 'P_NAME', s.id, true)
    items[s.id] = it
    pos = pos + len + 2
  end
  r.UpdateArrange()

  -- 4. render every case
  local outputs, case_log = {}, {}
  for ci, c in ipairs(CASES) do
    for p, v in pairs(baseline) do r.TrackFX_SetParamNormalized(tr, fx, p, v) end
    local got, missing = {}, {}
    for role, want in pairs(c.set) do
      local p = roles[role]
      if not p then missing[#missing + 1] = role
      else
        local ok, s = set_param(p, want)
        got[role] = ok and s or ('FAILED: ' .. s)
      end
    end
    local _, pdc = r.TrackFX_GetNamedConfigParm(tr, fx, 'pdc')
    case_log[#case_log + 1] = { id = c.id, requested = c.set, achieved = got, missing = missing, pdc = tonumber(pdc) }
    if #missing > 0 then msg(('%s: missing roles %s'):format(c.id, table.concat(missing, ', '))) end
    if #missing == 0 then
      for _, sid in ipairs(c.sig) do
        local it, s = items[sid], sig_by_id[sid]
        local done_file = out_dir .. SEP .. c.id .. '__' .. sid .. '.wav'
        local fh = io.open(done_file, 'rb')
        local done = fh and fh:seek('end') > 1000
        if fh then fh:close() end
        if done then                                     -- rendered by an earlier run: keep it
          outputs[#outputs + 1] = { case = c.id, signal = sid, file = 'renders/' .. c.id .. '__' .. sid .. '.wav' }
          goto next_signal
        end
        r.Main_OnCommand(40289, 0)                       -- unselect all items
        r.SetMediaItemSelected(it, true)
        r.Main_OnCommand(s.channels == 2 and 40209 or 40361, 0)   -- apply track FX (stereo / mono output)
        local tk = r.GetActiveTake(it)
        local fn = r.GetMediaSourceFileName(r.GetMediaItemTake_Source(tk), '')
        local dst = out_dir .. SEP .. c.id .. '__' .. sid .. '.' .. (fn:match('%.(%w+)$') or 'wav')
        if fn ~= s.file and copy_file(fn, dst) then
          outputs[#outputs + 1] = { case = c.id, signal = sid, file = 'renders/' .. dst:match('[^/\\]+$') }
        else
          msg('  render failed for ' .. c.id .. ' / ' .. sid)
        end
        if fn ~= s.file then r.Main_OnCommand(40129, 0) end   -- delete the rendered take, keep the dry one
        ::next_signal::
      end
      msg(('[%d/%d] %s done'):format(ci, #CASES, c.id))
    end
  end
  for p, v in pairs(baseline) do r.TrackFX_SetParamNormalized(tr, fx, p, v) end
  r.Undo_EndBlock('Bloom study renders', -1)

  local sigs = {}
  for _, s in ipairs(signals) do sigs[#sigs + 1] = { id = s.id, file = 'signals/' .. s.id .. '.wav', channels = s.channels, desc = s.desc } end
  local f = io.open(root .. SEP .. 'manifest.json', 'w')
  f:write(json({ plugin = fxname, sample_rate = 48000, reaper = r.GetAppVersion(), pdc_default = tonumber(lat),
    created = os.date('!%Y-%m-%dT%H:%M:%SZ'), roles = roles, signals = sigs, cases = case_log, outputs = outputs, params = params }))
  f:close()
  msg(('\nDone: %d renders. Next: python3 analyze_bloom.py "%s"'):format(#outputs, root))
end

main()

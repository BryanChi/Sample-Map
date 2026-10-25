-- @description Chord Detector: settings
-- @author Bryan Chi
-- @version 1.0

local r = reaper
local EXT = "CRS_ChordDetector"

local fields = {
  { key = "vocabulary",     label = "Chord types (triads/standard/full)", default = "standard" },
  { key = "min_beats",      label = "Shortest chord (beats)",          default = "2" },
  { key = "change_penalty", label = "Change resistance (0.5-6)",       default = "2" },
  { key = "key_changes",    label = "Detect key changes (y/n)",        default = "y" },
  { key = "slash_chords",   label = "Slash chords, e.g. C/E (y/n)",    default = "n" },
  { key = "key_in_marker",  label = "Write key in marker (y/n)",       default = "y" },
  { key = "mark_no_chord",  label = "Mark no-chord parts N.C. (y/n)",  default = "y" },
  { key = "neural",         label = "High accuracy, slower (y/n)",     default = "y" },
}
local BOOL = { key_changes = true, slash_chords = true, key_in_marker = true, mark_no_chord = true, neural = true }

local cur, labels = {}, {}
for i, f in ipairs(fields) do
  local v = r.GetExtState(EXT, f.key)
  if v == "" then v = f.default
  elseif BOOL[f.key] then v = (v == "1") and "y" or "n" end
  cur[i] = v
  labels[i] = f.label
end

local ok, csv = r.GetUserInputs("Chord Detector settings", #fields,
  table.concat(labels, ",") .. ",extrawidth=60", table.concat(cur, ","))
if not ok then return end

local vals = {}
for v in (csv .. ","):gmatch("([^,]*),") do vals[#vals + 1] = v:match("^%s*(.-)%s*$") end

for i, f in ipairs(fields) do
  local v = vals[i] or f.default
  if BOOL[f.key] then
    v = (v:lower():sub(1, 1) == "y") and "1" or "0"
  elseif f.key == "vocabulary" then
    v = v:lower()
    if v ~= "triads" and v ~= "standard" and v ~= "basic" and v ~= "full" then v = "standard" end
  else
    local n = tonumber(v) or tonumber(f.default)
    if f.key == "min_beats" then n = math.max(1, math.min(16, math.floor(n + 0.5))) end
    if f.key == "change_penalty" then n = math.max(0, math.min(20, n)) end
    v = tostring(n)
  end
  r.SetExtState(EXT, f.key, v, true)
end

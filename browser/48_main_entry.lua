-- Sample Map Browser module: main_entry
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Main entry point --------------------------------------------------------
-- Per-instance token stored in the "alive" ExtState. A running instance stops
-- as soon as the stored value is no longer its own token.
function SampleMap_NewInstanceToken()
  local t = (r.time_precise and r.time_precise()) or os.clock()
  return string.format("%d-%d-%06d", os.time(), math.floor((t % 1000) * 1000), math.random(0, 999999))
end

function SampleMap_BeginInstance()
  SampleMapInstance.shutdown_done = false
  running = true
  SampleMapInstance.token = SampleMapInstance.token or SampleMap_NewInstanceToken()
  r.SetExtState(SampleMapInstance.section, SampleMapInstance.key, SampleMapInstance.token, false)
  if r.atexit then
    r.atexit(function()
      shutdown_script("atexit")
    end)
  end

  log("Starting Sample Map Browser...")

  load_config()
  sync_project_state_if_needed()

  ctx = r.ImGui_CreateContext(SCRIPT_NAME, r.ImGui_ConfigFlags_DockingEnable())
  font = r.ImGui_CreateFont("sans-serif", 16)
  if font then
    r.ImGui_Attach(ctx, font)
  end
  ensure_seq_role_icons()
  ensure_vfx_icons()

  begin_library_load()
  log("ImGui context created; loading library asynchronously")
  loop()
end

function SampleMap_WaitThenBegin(n)
  n = (tonumber(n) or 0) + 1
  local win = nil
  if r.JS_Window_Find then
    win = r.JS_Window_Find(SCRIPT_NAME, true)
  end
  local flag = r.GetExtState(SampleMapInstance.section, SampleMapInstance.key)
  if flag ~= "" and flag ~= SampleMapInstance.token then
    -- An even newer launch claimed the key while we waited: let it win.
    return
  end
  if n < 90 and win then
    r.defer(function()
      SampleMap_WaitThenBegin(n)
    end)
    return
  end
  SampleMap_BeginInstance()
end

function main()
  SampleMapInstance.token = SampleMap_NewInstanceToken()
  if r.GetExtState(SampleMapInstance.section, SampleMapInstance.key) ~= "" then
    local existing = true
    if r.JS_Window_Find then
      existing = r.JS_Window_Find(SCRIPT_NAME, true) ~= nil
    end
    if existing then
      -- Already running: claim the key with this instance's token (the live
      -- instance sees a foreign token and quits), then start THIS (new) copy.
      r.SetExtState(SampleMapInstance.section, SampleMapInstance.key, SampleMapInstance.token, false)
      if r.ShowConsoleMsg then
        r.ShowConsoleMsg("[Sample Map] Reloading from disk…\n")
      end
      r.defer(function()
        SampleMap_WaitThenBegin(0)
      end)
      return
    end
    -- Stale flag from a previous crash; start a new instance.
  end
  SampleMap_BeginInstance()
end

main()

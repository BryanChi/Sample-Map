-- Sample Map Browser module: preview_track
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Preview helpers (track only) ----------------------------------------------
function ensure_preview_track()
  if preview_track then
    local valid = false
    if r.ValidatePtr2 then
      valid = r.ValidatePtr2(0, preview_track, "MediaTrack*") and true or false
    elseif r.ValidatePtr then
      valid = r.ValidatePtr(preview_track, "MediaTrack*") and true or false
    end
    if valid then
      return preview_track
    end
    preview_track = nil
  end

  -- Try to find existing preview track
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, name = r.GetTrackName(tr, "")
    if name == PREVIEW_TRACK_NAME then
      preview_track = tr
      break
    end
  end

  -- Create if missing
  if not preview_track then
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    preview_track = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(preview_track, "P_NAME", PREVIEW_TRACK_NAME, true)
    -- Hide from TCP/mixer to avoid clutter
    r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINTCP", 0)
    r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINMIXER", 0)
    -- Keep normal routing (main send on)
    r.SetMediaTrackInfo_Value(preview_track, "B_MAINSEND", 1)
  end

  return preview_track
end

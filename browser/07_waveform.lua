-- Sample Map Browser module: waveform
-- Loaded in order by "Sample Map Browser.lua"; shares globals with the other modules.
local r = reaper

-- --- Frequency analysis for spectral waveform ----------------------------------
-- Estimate dominant frequency using autocorrelation with zero-crossing fallback
function estimate_dominant_frequency(samples, sample_rate)
  if not samples or #samples < 16 then
    return nil  -- Need at least 16 samples for meaningful analysis
  end

  local n = #samples

  -- For large sample sets, downsample to improve performance while maintaining frequency resolution
  local analysis_samples = samples
  local analysis_sr = sample_rate
  if n > 512 then
    -- Downsample to ~512 samples to balance performance and accuracy
    local downsample_factor = math.floor(n / 512)
    analysis_samples = {}
    analysis_sr = sample_rate / downsample_factor

    for i = 1, n, downsample_factor do
      table.insert(analysis_samples, samples[i])
    end
    n = #analysis_samples
  end

  -- Normalize samples (center around zero and normalize amplitude)
  local sum = 0.0
  local max_amp = 0.0
  for i = 1, n do
    sum = sum + analysis_samples[i]
    max_amp = math.max(max_amp, math.abs(analysis_samples[i]))
  end

  if max_amp < 1e-6 then
    return nil  -- Silence
  end

  -- Remove DC offset and normalize
  local mean = sum / n
  local normalized = {}
  for i = 1, n do
    normalized[i] = (analysis_samples[i] - mean) / max_amp
  end

  -- Try autocorrelation first (more accurate for periodic signals)
  -- Focus on musical frequency range: 80Hz to 8000Hz (covers most instruments)
  local max_freq = 8000  -- Look for frequencies up to 8kHz
  local min_freq = 80    -- Minimum frequency to detect (below this, likely noise or rumble)
  local min_lag = math.floor(analysis_sr / max_freq)
  local max_lag = math.floor(analysis_sr / min_freq)

  min_lag = math.max(2, min_lag)
  max_lag = math.min(max_lag, math.floor(n / 2))

  if max_lag >= min_lag then
    -- Calculate autocorrelation at lag 0 for normalization
    local autocorr_0 = 0.0
    for i = 1, n do
      autocorr_0 = autocorr_0 + normalized[i] * normalized[i]
    end
    autocorr_0 = autocorr_0 / n

    if autocorr_0 > 1e-10 then
      -- Autocorrelation - look for the strongest peak in the musical range
      local max_corr = -math.huge
      local best_lag = nil

      for lag = min_lag, max_lag do
        local corr = 0.0
        local count = 0

        for i = 1, n - lag do
          corr = corr + normalized[i] * normalized[i + lag]
          count = count + 1
        end

        if count > 0 then
          -- Normalize autocorrelation
          corr = corr / count
          corr = corr / autocorr_0  -- Normalize by autocorrelation at lag 0

          if corr > max_corr then
            max_corr = corr
            best_lag = lag
          end
        end
      end

      -- Require a minimum correlation threshold to avoid noise
      if best_lag and best_lag > 0 and max_corr > 0.3 then  -- Higher threshold for better accuracy
        local freq = analysis_sr / best_lag
        -- Clamp to audible range (20Hz to 20kHz)
        freq = math.max(20, math.min(20000, freq))
        return freq
      end
    end
  end

  -- Fallback: Zero-crossing rate estimation (simpler but less accurate)
  -- Count zero crossings to estimate frequency
  local zero_crossings = 0
  for i = 2, n do
    if (normalized[i-1] >= 0 and normalized[i] < 0) or (normalized[i-1] < 0 and normalized[i] >= 0) then
      zero_crossings = zero_crossings + 1
    end
  end

  if zero_crossings > 2 then
    -- Each zero crossing represents half a cycle
    local cycles = zero_crossings / 2
    local duration = n / analysis_sr
    local freq = cycles / duration
    -- Clamp to audible range
    freq = math.max(20, math.min(20000, freq))
    return freq
  end

  return nil
end

-- Convert frequency to color (spectral mapping: low=red, mid=yellow/green, high=blue)
function frequency_to_color(freq)
  if not freq then
    return UI_THEME.text_dim  -- Gray for no frequency data
  end
  
  -- Map frequency to hue (0-360 degrees)
  -- 20Hz = red (0°), 2000Hz = yellow (60°), 20000Hz = blue (240°)
  local hue
  if freq < 2000 then
    -- Low to mid: red to yellow (0° to 60°)
    local t = (freq - 20) / (2000 - 20)
    hue = t * 60
  elseif freq < 8000 then
    -- Mid to high-mid: yellow to cyan (60° to 180°)
    local t = (freq - 2000) / (8000 - 2000)
    hue = 60 + t * 120
  else
    -- High: cyan to blue (180° to 240°)
    local t = (freq - 8000) / (20000 - 8000)
    hue = 180 + t * 60
  end
  
  -- Convert HSV to RGB
  local c = 1.0  -- Chroma
  local x = c * (1 - math.abs((hue / 60) % 2 - 1))
  local m = 0.3  -- Lightness adjustment (make it darker for visibility)
  
  local r, g, b = 0, 0, 0
  if hue < 60 then
    r, g, b = c, x, 0
  elseif hue < 120 then
    r, g, b = x, c, 0
  elseif hue < 180 then
    r, g, b = 0, c, x
  elseif hue < 240 then
    r, g, b = 0, x, c
  else
    r, g, b = x, 0, c
  end
  
  -- Convert to 0-255 and apply lightness
  r = math.floor((r + m) * 255)
  g = math.floor((g + m) * 255)
  b = math.floor((b + m) * 255)
  
  -- Clamp values
  r = math.max(0, math.min(255, r))
  g = math.max(0, math.min(255, g))
  b = math.max(0, math.min(255, b))
  
  -- Return as ARGB (0xAARRGGBB format)
  return (0xFF << 24) | (r << 16) | (g << 8) | b
end

-- --- Waveform generation -----------------------------------------------------
function generate_waveform(sample, width)
  width = width or waveform_width
  if not sample or not sample.path then
    return nil
  end
  
  -- Create a temporary track and item to access audio samples via AudioAccessor
  local temp_track = r.GetTrack(0, 0)  -- Try to use first track
  if not temp_track then
    temp_track = r.InsertTrackAtIndex(0, true)
  end
  
  if not temp_track then
    log("Failed to create/get track for waveform generation")
    return nil
  end
  
  -- Insert media item
  local item = r.AddMediaItemToTrack(temp_track)
  if not item then
    log("Failed to create media item for waveform")
    return nil
  end
  
  -- Set item position
  r.SetMediaItemPosition(item, 0, false)
  local src = r.PCM_Source_CreateFromFile(sample.path)
  if not src then
    r.DeleteTrackMediaItem(temp_track, item)
    log("Failed to create PCM source for waveform")
    return nil
  end
  
  local length_ret = {r.GetMediaSourceLength(src)}
  local duration = pick_number(length_ret, 0.0)
  if duration <= 0 then
    r.PCM_Source_Destroy(src)
    r.DeleteTrackMediaItem(temp_track, item)
    return nil
  end
  
  r.SetMediaItemLength(item, duration, false)
  
  -- Add take
  local take = r.AddTakeToMediaItem(item)
  if not take then
    r.PCM_Source_Destroy(src)
    r.DeleteTrackMediaItem(temp_track, item)
    log("Failed to create take for waveform")
    return nil
  end
  
  r.SetMediaItemTake_Source(take, src)
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.0)
  
  -- Note: After SetMediaItemTake_Source, REAPER owns the src, so don't destroy it manually
  
  -- We create/destroy a fresh accessor per pixel below.
  -- Only check API availability here.
  if not r.APIExists("GetAudioAccessorSamples") then
    log("GetAudioAccessorSamples API not available in this REAPER version")
    -- Note: Don't destroy src here - it's owned by the take/item
    r.DeleteTrackMediaItem(temp_track, item)
    return nil
  end
  
  local sr_ret = {r.GetMediaSourceSampleRate(src)}
  local sr = pick_number(sr_ret, 44100.0)
  
  local ch_ret = {r.GetMediaSourceNumChannels(src)}
  local channels = math.max(1, math.floor(pick_number(ch_ret, 2)))  -- Ensure at least 1 channel
  
  -- Calculate samples to read per pixel
  -- Ensure we read at least 128 samples per pixel for better frequency analysis
  local samples_per_pixel = math.max(128, math.floor((duration * sr) / width))
  
  -- Store waveform data per channel (for stereo: separate left/right)
  local waveform_channels = {}
  local frequency_channels = {}  -- Store frequency data per channel per pixel
  for c = 0, channels - 1 do
    waveform_channels[c] = {}
    frequency_channels[c] = {}
  end
  local max_val_per_channel = {}
  for c = 0, channels - 1 do
    max_val_per_channel[c] = 0.0
  end
  
  -- Read samples for each pixel
  local pixel_idx = 0
  
  while pixel_idx < width do
    
    -- Read samples (REAPER's PCM_Source API)
    -- Note: REAPER doesn't have a direct ReadSamples API in Lua
    -- We'll use a workaround: create a temporary take and read from it
    -- For now, let's use a simpler approach: sample at regular intervals
    
    -- Calculate RMS for this pixel's worth of samples
    -- Since we can't easily read raw samples, we'll use a simplified approach
    -- by sampling at regular time intervals
    local time_per_pixel = duration / width
    local time_at_pixel = pixel_idx * time_per_pixel
    
    -- Use REAPER's ability to get peak info at a specific time
    -- This is a simplified waveform - we'll use duration-based estimation
    -- For a more accurate waveform, we'd need to read actual samples
    
    -- For now, create a placeholder waveform based on file properties
    -- In a full implementation, you'd read actual sample data
    -- Calculate RMS for this pixel using AudioAccessor
    local time_start = (pixel_idx) * (duration / width)
    local time_end = (pixel_idx + 1) * (duration / width)
    local time_center = (time_start + time_end) * 0.5
    
    -- For frequency analysis, we need a longer time window to capture low frequencies
    -- Use a wider window: current pixel plus some surrounding context
    local analysis_window_start = math.max(0, time_start - 0.01)  -- 10ms before
    local analysis_window_end = math.min(duration, time_end + 0.01)  -- 10ms after
    local analysis_window_duration = analysis_window_end - analysis_window_start

    -- Read enough samples for frequency analysis (aim for 256-1024 samples for good analysis)
    local target_samples = math.max(256, math.floor(analysis_window_duration * sr))
    target_samples = math.min(target_samples, 1024)  -- Cap at 1024 to avoid excessive processing
    local max_samples_for_window = math.floor(analysis_window_duration * sr)
    local read_samples = math.min(target_samples, max_samples_for_window)
    read_samples = math.max(64, read_samples)  -- Minimum 64 samples for frequency analysis

    -- For very short windows, try to read more samples by extending the window
    if read_samples < 256 and analysis_window_start > 0.02 then
      -- Extend backward if possible
      analysis_window_start = math.max(0, analysis_window_start - 0.02)
      analysis_window_duration = analysis_window_end - analysis_window_start
      read_samples = math.min(1024, math.floor(analysis_window_duration * sr))
      read_samples = math.max(64, read_samples)
    elseif read_samples < 256 and analysis_window_end < duration - 0.02 then
      -- Extend forward if possible
      analysis_window_end = math.min(duration, analysis_window_end + 0.02)
      analysis_window_duration = analysis_window_end - analysis_window_start
      read_samples = math.min(1024, math.floor(analysis_window_duration * sr))
      read_samples = math.max(64, read_samples)
    end

    local buf_size = read_samples * channels
    local buf = r.new_array(buf_size)

    -- Debug logging for analysis window setup
    if pixel_idx < 3 then
      log(string.format("Pixel %d: analysis_window=%.3fs-%.3fs (%.1fms), target_samples=%d, read_samples=%d",
          pixel_idx + 1, analysis_window_start, analysis_window_end, analysis_window_duration * 1000, target_samples, read_samples))
    end
    
    -- Create a fresh accessor for each pixel to avoid positioning issues
    local pixel_accessor = r.CreateTakeAudioAccessor(take)
    if not pixel_accessor then
      log("Failed to create accessor for pixel " .. (pixel_idx + 1))
      if buf and buf.clear then
        buf.clear(buf)
      end
      for c = 0, channels - 1 do
        waveform_channels[c][pixel_idx + 1] = 0.1
        frequency_channels[c][pixel_idx + 1] = nil
      end
      pixel_idx = pixel_idx + 1
    elseif not r.GetAudioAccessorSamples then
      log("ERROR: GetAudioAccessorSamples not available - waveform generation will fail")
      r.DestroyAudioAccessor(pixel_accessor)
      if buf and buf.clear then
        buf.clear(buf)
      end
      for c = 0, channels - 1 do
        waveform_channels[c][pixel_idx + 1] = 0.1
        frequency_channels[c][pixel_idx + 1] = nil
      end
      pixel_idx = pixel_idx + 1
    else
      -- Read from analysis window to get samples for frequency analysis
      local samples_read = r.GetAudioAccessorSamples(pixel_accessor, sr, channels, analysis_window_start, read_samples, buf)

      -- Clean up the pixel accessor
      r.DestroyAudioAccessor(pixel_accessor)

      -- Debug logging for first few pixels
      if pixel_idx < 3 then
        log(string.format("Pixel %d: samples_read=%s, read_samples=%d, buf_size=%d, channels=%d, sr=%.0f, analysis_start=%.3f, analysis_end=%.3f", 
            pixel_idx + 1, tostring(samples_read), read_samples, buf_size, channels, sr, analysis_window_start, analysis_window_end))
      end
      
      if samples_read and samples_read > 0 and buf then
        -- GetAudioAccessorSamples returns the number of sample frames read (not total samples)
        -- Each frame contains one sample per channel
        local actual_frames = samples_read

        if pixel_idx < 3 then
          log(string.format("Pixel %d: Got %d sample frames (%d total samples across %d channels)",
              pixel_idx + 1, actual_frames, actual_frames * channels, channels))
        end
        
        -- Calculate RMS per channel for this pixel
        local sum_sq_per_channel = {}
        local count_per_channel = {}
        for c = 0, channels - 1 do
          sum_sq_per_channel[c] = 0.0
          count_per_channel[c] = 0
        end
        
        -- Debug: check first few buffer values for first pixel
        if pixel_idx < 1 and channels >= 2 then
          local debug_vals = {}
          -- REAPER arrays are 1-indexed, so we need to add 1 to the index
          for i = 0, math.min(5, buf_size - 1) do
            local buf_idx = i + 1  -- Convert to 1-based index
            local ok, val = pcall(function() return buf[buf_idx] end)
            if ok then
              debug_vals[i] = val
            else
              debug_vals[i] = "ERROR"
            end
          end
          -- Use %s to avoid errors if values are non-numeric
          log(string.format("Pixel %d buffer first 6 values: [0]=%s [1]=%s [2]=%s [3]=%s [4]=%s [5]=%s", 
              pixel_idx + 1, tostring(debug_vals[0] or 0), tostring(debug_vals[1] or 0), tostring(debug_vals[2] or 0), 
              tostring(debug_vals[3] or 0), tostring(debug_vals[4] or 0), tostring(debug_vals[5] or 0)))
        end
        
        -- Extract samples per channel for frequency analysis
        local channel_samples = {}
        for c = 0, channels - 1 do
          channel_samples[c] = {}
        end
        
        for j = 0, actual_frames - 1 do
          for c = 0, channels - 1 do
            -- REAPER arrays are 1-indexed, interleaved: [sample0_ch0, sample0_ch1, sample1_ch0, sample1_ch1, ...]
            -- Calculate 0-based index, then add 1 for 1-based array access
            local idx_0based = j * channels + c
            local buf_idx = idx_0based + 1  -- Convert to 1-based index for REAPER arrays
            if idx_0based >= 0 and idx_0based < buf_size then
              local ok, sample_val = pcall(function() return buf[buf_idx] end)
              if ok and sample_val ~= nil then
                sum_sq_per_channel[c] = sum_sq_per_channel[c] + (sample_val * sample_val)
                count_per_channel[c] = count_per_channel[c] + 1
                table.insert(channel_samples[c], sample_val)
              else
                if pixel_idx < 3 then
                  log(string.format("WARNING: Pixel %d, frame %d, ch %d: failed to read buf[%d] (1-based)", pixel_idx + 1, j, c, buf_idx))
                end
              end
            else
              if pixel_idx < 3 and c == 0 then
                log(string.format("WARNING: Pixel %d, frame %d, ch %d: idx %d out of bounds (buf_size=%d)", 
                    pixel_idx + 1, j, c, idx_0based, buf_size))
              end
            end
          end
        end
        
        -- Calculate RMS and frequency for each channel
        for c = 0, channels - 1 do
          if count_per_channel[c] > 0 then
            local rms = math.sqrt(sum_sq_per_channel[c] / count_per_channel[c])
            waveform_channels[c][pixel_idx + 1] = rms
            max_val_per_channel[c] = math.max(max_val_per_channel[c], rms)
            
            -- Estimate dominant frequency for this pixel/channel
            local freq = estimate_dominant_frequency(channel_samples[c], sr)
            frequency_channels[c][pixel_idx + 1] = freq
            
            -- Debug first few pixels for all channels
            if pixel_idx < 3 then
              local sample_count = channel_samples[c] and #channel_samples[c] or 0
              local first_sample = (channel_samples[c] and channel_samples[c][1]) or 0
              log(string.format("Pixel %d: time=%.3f, ch%d_rms=%.6f, ch%d_freq=%sHz, sample_count=%d, first_sample=%.6f", 
                  pixel_idx + 1, time_center, c, rms, c, freq and string.format("%.1f", freq) or "nil", sample_count, first_sample))
            end
          else
            waveform_channels[c][pixel_idx + 1] = 0.0
            frequency_channels[c][pixel_idx + 1] = nil
            if pixel_idx < 3 then
              log(string.format("WARNING: Pixel %d ch%d got 0 samples (buf_size=%d, read_samples=%d, actual_frames=%d, channels=%d)", 
                  pixel_idx + 1, c, buf_size, read_samples, actual_frames, channels))
            end
          end
        end
      else
        for c = 0, channels - 1 do
          waveform_channels[c][pixel_idx + 1] = 0.0
        end
        if pixel_idx < 3 then
          log(string.format("WARNING: GetAudioAccessorSamples failed for pixel %d: samples_read=%s, buf=%s", 
              pixel_idx + 1, tostring(samples_read), tostring(buf ~= nil)))
        end
      end
      
      if buf and buf.clear then
        buf.clear(buf)
      end
    end
    
    pixel_idx = pixel_idx + 1
  end
  
  -- Cleanup (accessors are destroyed per pixel now)
  -- Note: Don't destroy src - it's owned by the take/item, will be cleaned up when item is deleted
  r.DeleteTrackMediaItem(temp_track, item)
  
  -- Normalize waveforms per channel
  for c = 0, channels - 1 do
    local max_val = max_val_per_channel[c]
    log(string.format("Channel %d max_val before normalization: %.6f", c, max_val))
    if max_val > 0.001 then
      for i = 1, #waveform_channels[c] do
        waveform_channels[c][i] = waveform_channels[c][i] / max_val
      end
      log(string.format("Channel %d waveform normalized successfully", c))
    else
      -- If all values are very small, log warning and use a small value
      log("WARNING: Channel " .. c .. " max_val is very small (" .. string.format("%.6f", max_val) .. "), using placeholder")
      for i = 1, #waveform_channels[c] do
        waveform_channels[c][i] = 0.1
      end
    end
  end
  
  -- Log first few values for debugging (all channels)
  for c = 0, channels - 1 do
    if #waveform_channels[c] > 0 then
      local debug_str = string.format("First 5 waveform values (ch%d): ", c)
      for i = 1, math.min(5, #waveform_channels[c]) do
        debug_str = debug_str .. string.format("%.6f ", waveform_channels[c][i])
      end
      log(debug_str)
      
      -- Count non-zero values
      local non_zero_count = 0
      for i = 1, #waveform_channels[c] do
        if waveform_channels[c][i] and waveform_channels[c][i] > 0.0001 then
          non_zero_count = non_zero_count + 1
        end
      end
      log(string.format("Channel %d: %d total pixels, %d non-zero values", c, #waveform_channels[c], non_zero_count))
    else
      log(string.format("WARNING: Channel %d has no waveform data!", c))
    end
  end
  
  -- Return channel data: for mono, return single array; for stereo+, return table with channel arrays
  local waveform_data = {}
  local frequency_data = {}
  if channels == 1 then
    -- Mono: return single array for backward compatibility
    waveform_data.data = waveform_channels[0]
    frequency_data.data = frequency_channels[0]
    log("Returning mono waveform data")
  else
    -- Multi-channel: return table with channel arrays
    waveform_data.channel_data = {}
    frequency_data.channel_data = {}
    for c = 0, channels - 1 do
      waveform_data.channel_data[c] = waveform_channels[c]
      frequency_data.channel_data[c] = frequency_channels[c]
      log(string.format("Channel %d: %d pixels in channel_data", c, #waveform_channels[c]))
    end
    -- Also provide 'data' for backward compatibility (use first channel)
    waveform_data.data = waveform_channels[0]
    frequency_data.data = frequency_channels[0]
    local ch_data_count = 0
    if waveform_data.channel_data then
      for k, v in pairs(waveform_data.channel_data) do
        ch_data_count = ch_data_count + 1
      end
    end
    log(string.format("Multi-channel waveform: %d channels, channel_data has %d entries", 
        channels, ch_data_count))
  end
  
  local result = {
    data = waveform_data.data,  -- For backward compatibility
    channel_data = waveform_data.channel_data,  -- Per-channel data (nil for mono)
    frequency_data = frequency_data.data,  -- Frequency data for mono (backward compatibility)
    frequency_channel_data = frequency_data.channel_data,  -- Per-channel frequency data (nil for mono)
    duration = duration,
    sample_rate = sr,
    channels = channels
  }
  
  log(string.format("Waveform generation complete: channels=%d, data points=%d, channel_data=%s", 
      channels, result.data and #result.data or 0, result.channel_data and "present" or "nil"))
  
  return result
end


waveform_gen_job = nil

function make_placeholder_waveform(sample)
  local channels = sample.channels or 2
  local data = {
    data = {},
    duration = sample.duration or 1.0,
    sample_rate = sample.samplerate or 44100,
    channels = channels,
    sample_path = sample.path,
    frequency_data = {},
    frequency_channel_data = nil,
    _placeholder = true,
  }
  if channels > 1 then
    data.channel_data = {}
    data.frequency_channel_data = {}
    for c = 0, channels - 1 do
      data.channel_data[c] = {}
      data.frequency_channel_data[c] = {}
      for i = 1, waveform_width do
        data.channel_data[c][i] = 0.1
        data.frequency_channel_data[c][i] = nil
      end
    end
    data.data = data.channel_data[0]
    data.frequency_data = data.frequency_channel_data[0]
  else
    for i = 1, waveform_width do
      data.data[i] = 0.1
      data.frequency_data[i] = nil
    end
  end
  return data
end

function cancel_waveform_generation()
  local job = waveform_gen_job
  if not job then
    return
  end
  if job.accessor then
    pcall(function() r.DestroyAudioAccessor(job.accessor) end)
  end
  if job.item and job.track then
    r.PreventUIRefresh(1)
    pcall(function() r.DeleteTrackMediaItem(job.track, job.item) end)
    if job.inserted_track then
      pcall(function() r.DeleteTrack(job.track) end)
    end
    r.PreventUIRefresh(-1)
  end
  if job.peak_src then
    -- Peak mode owns its source; in item mode the take owns it.
    pcall(function() r.PCM_Source_Destroy(job.peak_src) end)
  end
  waveform_gen_job = nil
end

function finalize_waveform_job(job)
  local channels = job.channels
  for c = 0, channels - 1 do
    local max_val = job.max_val_per_channel[c] or 0.0
    if max_val > 0.001 then
      for i = 1, #job.waveform_channels[c] do
        job.waveform_channels[c][i] = job.waveform_channels[c][i] / max_val
      end
    else
      for i = 1, #job.waveform_channels[c] do
        job.waveform_channels[c][i] = 0.1
      end
    end
  end

  local result
  if channels == 1 then
    result = {
      data = job.waveform_channels[0],
      channel_data = nil,
      frequency_data = job.frequency_channels[0],
      frequency_channel_data = nil,
      duration = job.duration,
      sample_rate = job.sr,
      channels = channels,
      sample_path = job.path,
    }
  else
    result = {
      data = job.waveform_channels[0],
      channel_data = {},
      frequency_data = job.frequency_channels[0],
      frequency_channel_data = {},
      duration = job.duration,
      sample_rate = job.sr,
      channels = channels,
      sample_path = job.path,
    }
    for c = 0, channels - 1 do
      result.channel_data[c] = job.waveform_channels[c]
      result.frequency_channel_data[c] = job.frequency_channels[c]
    end
  end
  return result
end

function init_waveform_job_buffers(job, sr, channels, duration)
  job.sr = sr
  job.channels = channels
  job.duration = duration
  job.width = waveform_width
  job.waveform_channels = {}
  job.frequency_channels = {}
  job.max_val_per_channel = {}
  for c = 0, channels - 1 do
    job.waveform_channels[c] = {}
    job.frequency_channels[c] = {}
    job.max_val_per_channel[c] = 0.0
  end
  job.pixel_idx = 0
  job.setup_done = true
end

-- Preferred path: read peaks straight from a PCM source, so browsing never
-- adds an item or track to the project (and never marks it modified).
function setup_waveform_job_peaks(job)
  if not (r.PCM_Source_CreateFromFile and r.PCM_Source_GetPeaks and r.new_array) then
    return false
  end
  local src = r.PCM_Source_CreateFromFile(job.sample.path)
  if not src then
    return false
  end
  local duration = pick_number({ r.GetMediaSourceLength(src) }, 0.0)
  if duration <= 0 then
    r.PCM_Source_Destroy(src)
    return false
  end
  local sr = pick_number({ r.GetMediaSourceSampleRate(src) }, 44100.0)
  local channels = math.max(1, math.floor(pick_number({ r.GetMediaSourceNumChannels(src) }, 2)))
  job.peak_src = src
  job.peaks_building = r.PCM_Source_BuildPeaks and r.PCM_Source_BuildPeaks(src, 0) ~= 0 or false
  init_waveform_job_buffers(job, sr, math.min(channels, 8), duration)
  return true
end

-- Builds peak files a slice at a time, then reads every pixel in one call.
-- Returns false when the source gave no peaks (caller falls back to items).
function process_waveform_peaks(job, deadline)
  local src = job.peak_src
  if job.peaks_building then
    while r.PCM_Source_BuildPeaks(src, 1) ~= 0 do
      if r.time_precise() >= deadline then
        return true
      end
    end
    r.PCM_Source_BuildPeaks(src, 2)
    job.peaks_building = false
  end
  local width, channels = job.width, job.channels
  local buf = r.new_array(channels * width * 2)
  buf.clear()
  local ret = r.PCM_Source_GetPeaks(src, width / job.duration, 0.0, channels, width, 0, buf)
  local got = math.floor(tonumber(ret) or 0) % 1048576
  if got <= 0 then
    return false
  end
  local vals = buf.table and buf.table() or buf
  -- Block of maxima (frame-major, channel-interleaved), then a block of minima.
  local min_off = channels * width
  for i = 0, width - 1 do
    for c = 0, channels - 1 do
      local v = 0.0
      if i < got then
        local hi = math.abs(vals[i * channels + c + 1] or 0.0)
        local lo = math.abs(vals[min_off + i * channels + c + 1] or 0.0)
        v = hi > lo and hi or lo
      end
      job.waveform_channels[c][i + 1] = v
      job.frequency_channels[c][i + 1] = nil
      if v > job.max_val_per_channel[c] then
        job.max_val_per_channel[c] = v
      end
    end
  end
  job.pixel_idx = width
  return true
end

-- Fallback (no peak API, or the source returned no peaks): a temporary item
-- read through a take audio accessor. Prefers the script's own hidden
-- preview track; a track inserted here is deleted again on cleanup.
function setup_waveform_job(job)
  local sample = job.sample
  local temp_track = nil
  if preview_track and r.ValidatePtr2 and r.ValidatePtr2(0, preview_track, "MediaTrack*") then
    temp_track = preview_track
  end
  temp_track = temp_track or r.GetTrack(0, 0)
  local inserted_track = false
  if not temp_track then
    r.InsertTrackAtIndex(0, false)
    temp_track = r.GetTrack(0, 0)
    inserted_track = temp_track ~= nil
  end
  if not temp_track then
    return false
  end
  local function drop_track()
    if inserted_track then
      r.DeleteTrack(temp_track)
    end
  end

  r.PreventUIRefresh(1)
  local item = r.AddMediaItemToTrack(temp_track)
  if not item then
    drop_track()
    r.PreventUIRefresh(-1)
    return false
  end

  r.SetMediaItemPosition(item, 0, false)
  local src = r.PCM_Source_CreateFromFile(sample.path)
  if not src then
    r.DeleteTrackMediaItem(temp_track, item)
    drop_track()
    r.PreventUIRefresh(-1)
    return false
  end

  local duration = pick_number({ r.GetMediaSourceLength(src) }, 0.0)
  if duration <= 0 then
    r.DeleteTrackMediaItem(temp_track, item)
    drop_track()
    r.PreventUIRefresh(-1)
    return false
  end

  r.SetMediaItemLength(item, duration, false)
  local take = r.AddTakeToMediaItem(item)
  if not take then
    r.DeleteTrackMediaItem(temp_track, item)
    drop_track()
    r.PreventUIRefresh(-1)
    return false
  end

  r.SetMediaItemTake_Source(take, src)
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.0)

  if not r.APIExists("GetAudioAccessorSamples") then
    r.DeleteTrackMediaItem(temp_track, item)
    drop_track()
    r.PreventUIRefresh(-1)
    return false
  end

  local accessor = r.CreateTakeAudioAccessor(take)
  if not accessor then
    r.DeleteTrackMediaItem(temp_track, item)
    drop_track()
    r.PreventUIRefresh(-1)
    return false
  end
  r.PreventUIRefresh(-1)

  local sr = pick_number({ r.GetMediaSourceSampleRate(src) }, 44100.0)
  local channels = math.max(1, math.floor(pick_number({ r.GetMediaSourceNumChannels(src) }, 2)))

  job.track = temp_track
  job.inserted_track = inserted_track
  job.item = item
  job.accessor = accessor
  init_waveform_job_buffers(job, sr, channels, duration)
  return true
end

function begin_waveform_generation(sample)
  if not sample or not sample.path then
    return
  end
  cancel_waveform_generation()
  waveform_gen_job = {
    sample = sample,
    path = sample.path,
    setup_done = false,
  }
end

function waveform_is_ready(sample)
  return waveform_data
    and sample
    and waveform_data.sample_path == sample.path
    and not waveform_data._placeholder
end

function ensure_waveform_for_sample(sample)
  if not sample or not sample.path then
    return
  end
  if tostring(sample.path):find("^layering%-mix:", 1, false) then
    return
  end
  if waveform_is_ready(sample) then
    return
  end
  if waveform_gen_job and waveform_gen_job.path == sample.path then
    return
  end
  waveform_data = make_placeholder_waveform(sample)
  begin_waveform_generation(sample)
end

function process_waveform_pixel(job)
  local pixel_idx = job.pixel_idx
  local width = job.width
  local duration = job.duration
  local sr = job.sr
  local channels = job.channels
  local accessor = job.accessor

  local time_start = pixel_idx * (duration / width)
  -- Cap read size for speed — RMS only needs a short window, not full pixel duration
  local read_samples = math.min(256, math.max(64, math.floor((duration / width) * sr)))
  local buf_size = read_samples * channels
  -- One buffer per job (it is cleared after every pixel below) instead of a
  -- new reaper.array per pixel.
  local buf = job.pixel_buf
  if not buf or job.pixel_buf_size ~= buf_size then
    buf = r.new_array(buf_size)
    job.pixel_buf = buf
    job.pixel_buf_size = buf_size
  end

  local samples_read = r.GetAudioAccessorSamples(accessor, sr, channels, time_start, read_samples, buf)
  if samples_read and samples_read > 0 and buf then
    local actual_frames = samples_read
    -- Read the samples into a Lua table with one call; indexing the
    -- reaper.array directly costs a C call per sample.
    local vals = buf.table and buf.table() or buf
    for c = 0, channels - 1 do
      local sum_sq = 0.0
      local count = 0
      for j = 0, actual_frames - 1 do
        local buf_idx = j * channels + c + 1
        local sample_val = vals[buf_idx]
        if sample_val then
          sum_sq = sum_sq + (sample_val * sample_val)
          count = count + 1
        end
      end
      if count > 0 then
        local rms = math.sqrt(sum_sq / count)
        job.waveform_channels[c][pixel_idx + 1] = rms
        job.max_val_per_channel[c] = math.max(job.max_val_per_channel[c], rms)
      else
        job.waveform_channels[c][pixel_idx + 1] = 0.0
      end
      job.frequency_channels[c][pixel_idx + 1] = nil
    end
  else
    for c = 0, channels - 1 do
      job.waveform_channels[c][pixel_idx + 1] = 0.0
      job.frequency_channels[c][pixel_idx + 1] = nil
    end
  end

  if buf and buf.clear then
    buf.clear(buf)
  end
  job.pixel_idx = pixel_idx + 1
end

function process_waveform_slice(max_ms)
  local job = waveform_gen_job
  if not job then
    return
  end
  max_ms = max_ms or 6.0

  if not job.setup_done then
    if not job.peaks_failed and setup_waveform_job_peaks(job) then
      job.peaks_mode = true
    elseif not setup_waveform_job(job) then
      cancel_waveform_generation()
      return
    end
    if waveform_data and waveform_data.sample_path == job.path then
      waveform_data.duration = job.duration
      waveform_data.sample_rate = job.sr
      waveform_data.channels = job.channels
    end
  end

  local deadline = r.time_precise() + (max_ms / 1000.0)
  if job.peaks_mode then
    if not process_waveform_peaks(job, deadline) then
      -- No peaks from this source: retry next frame through a temp item.
      pcall(function() r.PCM_Source_Destroy(job.peak_src) end)
      job.peak_src = nil
      job.peaks_mode = false
      job.peaks_failed = true
      job.setup_done = false
      return
    end
  else
    while job.pixel_idx < job.width and r.time_precise() < deadline do
      process_waveform_pixel(job)
    end
  end

  if job.pixel_idx >= job.width then
    waveform_data = finalize_waveform_job(job)
    cancel_waveform_generation()
  end
end

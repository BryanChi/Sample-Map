-- @description Chord Detector: BTC neural chord model in pure Lua
-- @author Bryan Chi
-- @version 1.0
--
-- Lua port of BTC, the Bi-directional Transformer for Chord recognition
-- (Park et al., ISMIR 2019, github.com/jayg996/BTC-ISMIR19, MIT License,
-- Copyright (c) 2019 Jonggwon Park). Trained weights: ChordDetector_BTC.bin
-- (the "large vocabulary" model, 170 classes), exported from the original
-- checkpoint without changes.
--
--   local BTC = dofile(dir .. "ChordDetector_BTC.lua")
--   local model = BTC.load(dir .. "ChordDetector_BTC.bin")
--   local feats = BTC.features(model, samples_11025)   -- {frames}{144}
--   local probs = BTC.run(model, feats, progress)      -- {frames}{170}, softmax
--   BTC.FRAME_DT                                        -- seconds per frame
--   BTC.class(i) -> root (0-11) or nil, quality ("maj", "min", "7", ...) or "N"/"X"
--
-- Input audio is mono at 11025 Hz (BTC itself reads 22050 Hz, but its CQT
-- starts by halving the rate, so 11025 Hz gives the same features).
-- Pure Lua 5.4: no math.pow / sinh / cosh / tanh.

local M = {}

local floor, ceil, sqrt, log, exp, cos, sin, pi, abs = math.floor, math.ceil, math.sqrt, math.log, math.exp,
  math.cos, math.sin, math.pi, math.abs

local SR = 11025
local BPO, NBINS = 24, 144
local FMIN = 32.70319566257483            -- C1
local CHUNK = 110250                      -- 10 s, BTC computes features per 10 s chunk
local HOP = 1024
local T = 108                             -- frames per model window (= one chunk)
local HIDDEN, HEADS, LAYERS, NCLASS = 128, 4, 8, 170
M.FRAME_DT = 10 / 108

-- class index (1-based) -> root, quality
local BTC_QUAL = { "min", "maj", "dim", "aug", "min6", "maj6", "min7", "minmaj7", "maj7", "7", "dim7", "hdim7", "sus2", "sus4" }
function M.class(i)
  local z = i - 1
  if z == 169 then return nil, "N" end
  if z == 168 then return nil, "X" end
  return z // 14, BTC_QUAL[z % 14 + 1]
end

---------------------------------------------------------------------------
-- weights
---------------------------------------------------------------------------

--- Load the weight file. Returns a table name -> flat float array (row-major).
function M.load(path)
  local f = assert(io.open(path, "rb"), "Chord Detector: missing " .. path)
  local d = f:read("a")
  f:close()
  assert(d:sub(1, 4) == "BTCW", "Chord Detector: bad weight file")
  local count, pos = string.unpack("<I4", d, 5)
  local W = {}
  local fmt64 = "<" .. string.rep("f", 64)
  for _ = 1, count do
    local nl
    nl, pos = string.unpack("<I2", d, pos)
    local name = d:sub(pos, pos + nl - 1); pos = pos + nl
    local nd
    nd, pos = string.unpack("<B", d, pos)
    local n = 1
    for _ = 1, nd do
      local dim
      dim, pos = string.unpack("<I4", d, pos)
      n = n * dim
    end
    local a, k = {}, 0
    while k + 64 <= n do
      local v = table.pack(string.unpack(fmt64, d, pos))
      for i = 1, 64 do a[k + i] = v[i] end
      k = k + 64; pos = pos + 256
    end
    while k < n do
      k = k + 1
      a[k], pos = string.unpack("<f", d, pos)
    end
    W[name] = a
  end
  return W
end

---------------------------------------------------------------------------
-- CQT front end (matches librosa.cqt as BTC uses it)
---------------------------------------------------------------------------

local function make_fft(n)
  local bits = 0
  while (1 << bits) < n do bits = bits + 1 end
  local rev = {}
  for i = 0, n - 1 do
    local r, x = 0, i
    for _ = 1, bits do r = (r << 1) | (x & 1); x = x >> 1 end
    rev[i + 1] = r + 1
  end
  local cr, ci = {}, {}
  for i = 0, n // 2 - 1 do cr[i + 1] = cos(2 * pi * i / n); ci[i + 1] = -sin(2 * pi * i / n) end
  return function(re, im)
    for i = 1, n do
      local j = rev[i]
      if j > i then re[i], re[j] = re[j], re[i]; im[i], im[j] = im[j], im[i] end
    end
    local size = 2
    while size <= n do
      local half, step = size // 2, n // size
      for start = 1, n, size do
        local k = 1
        for j = start, start + half - 1 do
          local wr, wi = cr[k], ci[k]
          local l = j + half
          local xr, xi = re[l], im[l]
          local tr = wr * xr - wi * xi
          local ti = wr * xi + wi * xr
          local ar, ai = re[j], im[j]
          re[l] = ar - tr; im[l] = ai - ti
          re[j] = ar + tr; im[j] = ai + ti
          k = k + step
        end
      end
      size = size * 2
    end
  end
end

local NFFT = 512
local fft512 = make_fft(NFFT)
local ALPHA = (2 ^ (2 / BPO) - 1) / (2 ^ (2 / BPO) + 1)
local Q = 1 / ALPHA
local FREQS = {}
for k = 1, NBINS do FREQS[k] = FMIN * 2 ^ ((k - 1) / BPO) end

-- one octave of filters in the frequency domain; every octave reuses it on
-- audio decimated by 2 (same filters relative to the sample rate)
local BASIS                                -- [24] = { bins = {}, re = {}, im = {} }
local function build_basis()
  BASIS = {}
  local re, im = {}, {}
  for b = 1, BPO do
    local f = FREQS[NBINS - BPO + b]
    local l = Q * SR / f
    local i0, i1 = floor(-l / 2), floor(l / 2)
    local n = i1 - i0
    for i = 1, NFFT do re[i] = 0; im[i] = 0 end
    local sr_, si_ = {}, {}
    local norm = 0
    for j = 0, n - 1 do
      local t = (i0 + j) / SR
      local w = 0.5 - 0.5 * cos(2 * pi * j / n)
      sr_[j + 1] = cos(2 * pi * f * t) * w
      si_[j + 1] = sin(2 * pi * f * t) * w
      norm = norm + sqrt(sr_[j + 1] ^ 2 + si_[j + 1] ^ 2)
    end
    local lpad = (NFFT - n) // 2
    local sc = (l / NFFT) / norm
    for j = 1, n do re[lpad + j] = sr_[j] * sc; im[lpad + j] = si_[j] * sc end
    fft512(re, im)
    -- keep the largest entries holding 99% of the magnitude (librosa sparsity 0.01)
    local mags, order, total = {}, {}, 0
    for i = 1, NFFT // 2 + 1 do
      mags[i] = sqrt(re[i] ^ 2 + im[i] ^ 2); order[i] = i; total = total + mags[i]
    end
    table.sort(order, function(a, c) return mags[a] < mags[c] end)
    local drop, acc = {}, 0
    for _, i in ipairs(order) do
      acc = acc + mags[i]
      if acc >= 0.01 * total then break end
      drop[i] = true
    end
    local e = { bins = {}, re = {}, im = {} }
    for i = 1, NFFT // 2 + 1 do
      if not drop[i] then
        e.bins[#e.bins + 1] = i; e.re[#e.re + 1] = re[i]; e.im[#e.im + 1] = im[i]
      end
    end
    BASIS[b] = e
  end
end

-- 65-tap half-band low-pass, then keep every 2nd sample (x sqrt 2 keeps energy)
local HB = {}
do
  local s = 0
  for i = 0, 64 do
    local n = i - 32
    local x = 0.5 * n
    local sinc = (n == 0) and 1 or sin(pi * x) / (pi * x)
    local bw = 0.42 - 0.5 * cos(2 * pi * i / 64) + 0.08 * cos(4 * pi * i / 64)
    HB[i + 1] = sinc * 0.5 * bw
    s = s + HB[i + 1]
  end
  for i = 1, 65 do HB[i] = HB[i] / s end
end

local SQRT2 = sqrt(2)
local function decimate2(y)
  local n, out = #y, {}
  local j = 0
  for c = 1, n, 2 do
    local acc = 0
    local lo = c - 32
    local m0 = lo < 1 and (2 - lo) or 1
    local m1 = (lo + 64 > n) and (n - lo + 1) or 65
    for m = m0, m1 do acc = acc + HB[m] * y[lo + m - 1] end
    j = j + 1; out[j] = acc * SQRT2
  end
  return out
end

local INV_SQRT_L = {}
for k = 1, NBINS do INV_SQRT_L[k] = 1 / sqrt(Q * SR / FREQS[k]) end

-- log-magnitude CQT frames of one chunk; appends to `out`
local function chunk_cqt(y, out, mean, std)
  local re, im = {}, {}
  local cur = {}
  for i = 1, #y do cur[i] = y[i] * SQRT2 end
  local hop = HOP
  local nframes = 1 + floor(#cur / hop)
  local mags = {}                          -- [frame][bin]
  for f = 1, nframes do mags[f] = {} end
  local nmin = nframes
  for oct = 0, 5 do
    local n = #cur
    local nfr = 1 + floor(n / hop)
    if nfr < nmin then nmin = nfr end
    local gain = sqrt(2 ^ oct)
    local base = NBINS - BPO * (oct + 1)
    for f = 1, math.min(nfr, nframes) do
      local s0 = (f - 1) * hop - NFFT // 2
      for i = 1, NFFT do
        local idx = s0 + i
        re[i] = (idx >= 1 and idx <= n) and cur[idx] or 0
        im[i] = 0
      end
      fft512(re, im)
      local row = mags[f]
      for b = 1, BPO do
        local e = BASIS[b]
        local bins, br, bi = e.bins, e.re, e.im
        local sr_, si_ = 0, 0
        for q = 1, #bins do
          local i = bins[q]
          local xr, xi = re[i], im[i]
          local cr_, ci_ = br[q], bi[q]
          sr_ = sr_ + cr_ * xr - ci_ * xi
          si_ = si_ + cr_ * xi + ci_ * xr
        end
        local k = base + b
        row[k] = sqrt(sr_ * sr_ + si_ * si_) * gain * INV_SQRT_L[k]
      end
    end
    if oct < 5 then cur = decimate2(cur); hop = hop // 2 end
  end
  local inv = 1 / std
  for f = 1, math.min(nmin, nframes) do
    local row = mags[f]
    local v = {}
    for k = 1, NBINS do v[k] = (log(row[k] + 1e-6) - mean) * inv end
    out[#out + 1] = v
  end
end

--- Normalised BTC features for mono 11025 Hz samples: {frames}{144}.
function M.features(model, samples, progress)
  if not BASIS then build_basis() end
  local mean, std = model.mean[1], model.std[1]
  local out = {}
  local n = #samples
  local pos = 0
  repeat
    local len = math.min(CHUNK, n - pos)
    local y = table.move(samples, pos + 1, pos + len, 1, {})
    chunk_cqt(y, out, mean, std)
    pos = pos + len
    if progress then progress(pos / math.max(1, n)) end
  until pos >= n
  return out
end

---------------------------------------------------------------------------
-- transformer
---------------------------------------------------------------------------

-- y[t] = W x[t] (+ b); W is a list of rows (W[o][i])
local function linear(x, W, b, nin, nout)
  local y = {}
  for t = 1, #x do
    local xt = x[t]
    local yt = {}
    for o = 1, nout do
      local s = b and b[o] or 0
      local wr = W[o]
      for i = 1, nin do s = s + wr[i] * xt[i] end
      yt[o] = s
    end
    y[t] = yt
  end
  return y
end

local function to_rows(flat, nout, nin)
  local rows = {}
  for o = 1, nout do
    local r = {}
    local base = (o - 1) * nin
    for i = 1, nin do r[i] = flat[base + i] end
    rows[o] = r
  end
  return rows
end

local function layernorm(x, g, b, n)
  local y = {}
  for t = 1, #x do
    local xt = x[t]
    local m = 0
    for i = 1, n do m = m + xt[i] end
    m = m / n
    local v = 0
    for i = 1, n do local d = xt[i] - m; v = v + d * d end
    local inv = 1 / (sqrt(v / (n - 1)) + 1e-6)
    local yt = {}
    for i = 1, n do yt[i] = g[i] * (xt[i] - m) * inv + b[i] end
    y[t] = yt
  end
  return y
end

-- 1-D convolution, kernel 3, padding 1 both sides, then ReLU.
-- Wk[k][o] is the row of input weights for tap k and output o.
local function conv3_relu(x, Wk, b, n)
  local Tn = #x
  local zero = {}
  for i = 1, n do zero[i] = 0 end
  local w0, w1, w2 = Wk[1], Wk[2], Wk[3]
  local y = {}
  for t = 1, Tn do
    local x0, x1, x2 = x[t - 1] or zero, x[t], x[t + 1] or zero
    local yt = {}
    for o = 1, n do
      local s = b[o]
      local r0, r1, r2 = w0[o], w1[o], w2[o]
      for i = 1, n do
        s = s + r0[i] * x0[i] + r1[i] * x1[i] + r2[i] * x2[i]
      end
      yt[o] = s > 0 and s or 0
    end
    y[t] = yt
  end
  return y
end

local DK = HIDDEN // HEADS
local QSCALE = 1 / sqrt(DK)

local function attention(xn, P, forward)
  local Tn = #xn
  local q = linear(xn, P.q, nil, HIDDEN, HIDDEN)
  local k = linear(xn, P.k, nil, HIDDEN, HIDDEN)
  local v = linear(xn, P.v, nil, HIDDEN, HIDDEN)
  local ctx = {}
  for t = 1, Tn do ctx[t] = {} end
  local w = {}
  for h = 0, HEADS - 1 do
    local off = h * DK
    for t = 1, Tn do
      local qt = q[t]
      local j0, j1 = 1, Tn
      if forward then j1 = t else j0 = t end   -- forward: past + self, backward: self + future
      local mx = -1e30
      for j = j0, j1 do
        local kj = k[j]
        local s = 0
        for d = off + 1, off + DK do s = s + qt[d] * kj[d] end
        s = s * QSCALE
        w[j] = s
        if s > mx then mx = s end
      end
      local sum = 0
      for j = j0, j1 do local e = exp(w[j] - mx); w[j] = e; sum = sum + e end
      local ct = ctx[t]
      for d = off + 1, off + DK do ct[d] = 0 end
      for j = j0, j1 do
        local a = w[j] / sum
        local vj = v[j]
        for d = off + 1, off + DK do ct[d] = ct[d] + a * vj[d] end
      end
    end
  end
  return linear(ctx, P.o, nil, HIDDEN, HIDDEN)
end

local function block(x, P, forward)
  local xn = layernorm(x, P.ln1g, P.ln1b, HIDDEN)
  local y = attention(xn, P, forward)
  local Tn = #x
  local r = {}
  for t = 1, Tn do
    local xt, yt, rt = x[t], y[t], {}
    for i = 1, HIDDEN do rt[i] = xt[i] + yt[i] end
    r[t] = rt
  end
  xn = layernorm(r, P.ln2g, P.ln2b, HIDDEN)
  local h = conv3_relu(xn, P.c1, P.c1b, HIDDEN)
  h = conv3_relu(h, P.c2, P.c2b, HIDDEN)
  for t = 1, Tn do
    local rt, ht = r[t], h[t]
    for i = 1, HIDDEN do rt[i] = rt[i] + ht[i] end
  end
  return r
end

local function split_taps(Wc, n)
  local taps = { {}, {}, {} }
  for o = 0, n - 1 do
    local r1, r2, r3 = {}, {}, {}
    for i = 0, n - 1 do
      local src = (o * n + i) * 3
      r1[i + 1] = Wc[src + 1]; r2[i + 1] = Wc[src + 2]; r3[i + 1] = Wc[src + 3]
    end
    taps[1][o + 1] = r1; taps[2][o + 1] = r2; taps[3][o + 1] = r3
  end
  return taps
end

local function prepare(W)
  if W._layers then return W._layers end
  local layers = {}
  for l = 0, LAYERS - 1 do
    local function blk(name)
      local p = "L" .. l .. "." .. name .. "."
      local a = p .. "multi_head_attention."
      local c = p .. "positionwise_convolution.layers."
      return {
        q = to_rows(W[a .. "query_linear.weight"], HIDDEN, HIDDEN),
        k = to_rows(W[a .. "key_linear.weight"], HIDDEN, HIDDEN),
        v = to_rows(W[a .. "value_linear.weight"], HIDDEN, HIDDEN),
        o = to_rows(W[a .. "output_linear.weight"], HIDDEN, HIDDEN),
        ln1g = W[p .. "layer_norm_mha.gamma"], ln1b = W[p .. "layer_norm_mha.beta"],
        ln2g = W[p .. "layer_norm_ffn.gamma"], ln2b = W[p .. "layer_norm_ffn.beta"],
        c1 = split_taps(W[c .. "0.conv.weight"], HIDDEN), c1b = W[c .. "0.conv.bias"],
        c2 = split_taps(W[c .. "1.conv.weight"], HIDDEN), c2b = W[c .. "1.conv.bias"],
      }
    end
    layers[l + 1] = {
      fwd = blk("attn_block"), bwd = blk("backward_attn_block"),
      lin = to_rows(W["L" .. l .. ".linear.weight"], HIDDEN, 2 * HIDDEN), linb = W["L" .. l .. ".linear.bias"],
    }
  end
  W._layers = layers
  W._emb = to_rows(W["embedding_proj.weight"], HIDDEN, NBINS)
  W._out = to_rows(W["output_layer.output_projection.weight"], NCLASS, HIDDEN)
  -- timing signal
  local ts = {}
  local nt = HIDDEN // 2
  local inc = log(1e4) / (nt - 1)
  for t = 0, T - 1 do
    local row = {}
    for i = 0, nt - 1 do
      local s = t * exp(-i * inc)
      row[i + 1] = sin(s); row[nt + i + 1] = cos(s)
    end
    ts[t + 1] = row
  end
  W._timing = ts
  return layers
end

--- Run the model on normalised features. Returns per-frame class
-- probabilities {frames}{170}. progress(fraction) is called per window.
function M.run(W, feats, progress)
  local layers = prepare(W)
  local ts = W._timing
  local n = #feats
  local probs = {}
  local zero = {}
  for i = 1, NBINS do zero[i] = 0 end
  local nwin = ceil(n / T)
  for w = 0, nwin - 1 do
    local x = {}
    for t = 1, T do x[t] = feats[w * T + t] or zero end
    x = linear(x, W._emb, nil, NBINS, HIDDEN)
    for t = 1, T do
      local xt, st = x[t], ts[t]
      for i = 1, HIDDEN do xt[i] = xt[i] + st[i] end
    end
    for l = 1, LAYERS do
      local L = layers[l]
      local f = block(x, L.fwd, true)
      if progress then progress((w + (l - 0.5) / LAYERS) / nwin) end
      local b = block(x, L.bwd, false)
      local cat = {}
      for t = 1, T do
        local c, ft, bt = {}, f[t], b[t]
        for i = 1, HIDDEN do c[i] = ft[i]; c[HIDDEN + i] = bt[i] end
        cat[t] = c
      end
      x = linear(cat, L.lin, L.linb, 2 * HIDDEN, HIDDEN)
      if progress then progress((w + l / LAYERS) / nwin) end
    end
    x = layernorm(x, W["layer_norm.gamma"], W["layer_norm.beta"], HIDDEN)
    local lg = linear(x, W._out, W["output_layer.output_projection.bias"], HIDDEN, NCLASS)
    for t = 1, T do
      local idx = w * T + t
      if idx > n then break end
      local row = lg[t]
      local mx = -1e30
      for c = 1, NCLASS do if row[c] > mx then mx = row[c] end end
      local s = 0
      for c = 1, NCLASS do local e = exp(row[c] - mx); row[c] = e; s = s + e end
      for c = 1, NCLASS do row[c] = row[c] / s end
      probs[idx] = row
    end
  end
  return probs
end

return M

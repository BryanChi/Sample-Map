#!/usr/bin/env python3
"""Reference prototype of OUR adaptive tonal balancer (working name "FXD Poise").

Written from first principles and public descriptions only. It is the floating-point
model a JSFX port will be checked against, and it doubles as a stand-in plug-in so the
measurement kit can be tested end to end:

    python3 proto_balancer.py fake "<dir>"      # renders the kit's cases into <dir> like REAPER would

Signal flow per STFT frame (N = 2048, hop 512, sqrt-Hann in and out, 75 % overlap):
  1. power per bin -> 40 constant-Q analysis bands (pink noise reads flat)
  2. per-band level in dB, smoothed in time with separate attack (level rising) and release
  3. spectral TREND: the band levels smoothed across frequency (Gaussian, ~2/3 octave)
  4. deviation = target - trend, with the loudness-weighted mean removed (level neutral)
  5. gain = alpha(Amount) * deviation, clamped; squash (Amount > 7) adds a per-band
     up/down compressor whose threshold follows an equal-loudness-shaped curve
  6. band gains -> smooth per-bin real (zero-phase) gain, multiplied into the frame
"""
import json, math, os, sys
import numpy as np

SR = 48000
N, HOP = 2048, 512
NB = 40
FB = np.geomspace(30, 18000, NB)                      # band centres


def band_weights(n=N, sr=SR):
    f = np.fft.rfftfreq(n, 1 / sr)
    lf = np.log2(np.maximum(f, 1.0))
    W = np.zeros((NB, len(f)))
    step = math.log2(FB[1] / FB[0])
    for i, c in enumerate(np.log2(FB)):
        W[i] = np.maximum(0, 1 - np.abs(lf - c) / step)          # triangular in log-frequency
        lo, hi = 2 ** (c - step), 2 ** (c + step)                  # low bands narrower than a bin: take the bins around them
        if W[i].sum() < 1: W[i] = np.maximum(W[i], (f >= lo - sr / n) & (f <= hi + sr / n))
    # normalise by bandwidth in octaves so pink noise is flat across bands
    return W, f


def gauss_oct(fc, sigma):
    return np.exp(-0.5 * (np.log2(FB / fc) / sigma) ** 2)


# equal-loudness-ish sensitivity (dB, 0 at 1-4 kHz, lower at the extremes), loosely after ISO 226 at 60 phon
def sensitivity_db(f):
    f = np.asarray(f, float)
    return -(10 * np.log10(1 + (120 / f) ** 2.2) + 6 * np.log10(1 + (f / 9000) ** 3)) + 3 * np.exp(-0.5 * (np.log2(f / 3200) / 0.8) ** 2)


DEFAULT_TONES = [(100, 0.0), (500, 0.0), (2500, 0.0), (10000, 0.0)]


class Poise:
    def __init__(self, amount=5.0, attack=0.5, release=0.5, tones=None, mix=1.0, squash_cal=0.0, sr=SR):
        self.sr = sr
        self.W, self.f = band_weights(N, sr)
        self.Wn = self.W / self.W.sum(axis=1, keepdims=True)
        self.amount, self.mix, self.squash_cal = amount, mix, squash_cal
        # attack 0..1 -> 30..600 ms, release 0..1 -> 80..2000 ms (per-frame one-pole)
        fr = sr / HOP
        ta = 0.03 * 20 ** attack; trl = 0.08 * 25 ** release
        self.ca, self.cr = math.exp(-1 / (ta * fr)), math.exp(-1 / (trl * fr))
        tones = tones or DEFAULT_TONES
        # target: pink with a gentle presence scoop, plus tone offsets (broad, ~1 oct sigma)
        self.target = -1.0 * gauss_oct(1800, 1.0) + sum(g * gauss_oct(fc, 0.9) for fc, g in tones)
        self.sens = sensitivity_db(FB)
        self.level = None
        self.win = np.sqrt(np.hanning(N + 1)[:N])
        # dB offset from 'trend' (mean bin power + 10log10 f) to band RMS in dBFS
        step = math.log2(FB[1] / FB[0])
        self.cal = 10 * math.log10(math.log(2) * step * N / sr) + 10 * math.log10(2 / (N * np.sum(self.win ** 2)))
        self.gain_hist = []

    def alpha(self):
        a = min(self.amount, 7.0) / 7.0
        return 0.85 * a ** 1.3                                  # fraction of the deviation corrected

    def band_gains(self, P):
        bl = 10 * np.log10(self.Wn @ P + 1e-20) + 10 * np.log10(FB)   # power per octave: pink reads flat
        if self.level is None: self.level = bl.copy()
        rise = bl > self.level
        c = np.where(rise, self.ca, self.cr)
        self.level = c * self.level + (1 - c) * bl
        # trend across frequency: Gaussian smoothing over ~0.67 oct in band index space
        oct_per_band = math.log2(FB[1] / FB[0])
        k = np.arange(-8, 9); g = np.exp(-0.5 * (k * oct_per_band / 0.67) ** 2); g /= g.sum()
        pad = np.pad(self.level, 8, mode='edge')
        trend = np.convolve(pad, g, mode='same')[8:-8]
        # loudness weights: input energy share times hearing sensitivity
        w = 10 ** ((trend + self.sens) / 10); w /= w.sum()
        dev = self.target - trend
        dev -= np.sum(w * dev)
        G = np.clip(self.alpha() * dev, -12, 12)
        if self.amount > 7:                                     # squash: up/down compression per band
            s = (self.amount - 7) / 3
            ratio = 1 + 3 * s
            thr = -36 + self.squash_cal - 0.5 * self.sens       # lower threshold where the ear is sensitive
            lvl = trend + self.cal                              # band RMS in dBFS
            over = lvl - thr
            knee = 6 + 0.6 * (-self.sens)                       # harder knee where the ear is less sensitive
            soft = over * np.abs(over) / (np.abs(over) + knee)  # smooth knee around the threshold
            G = G - soft * (1 - 1 / ratio)
            G = np.clip(G, -18, 12)
        self.gain_hist.append(G)
        return G

    def bins_from_bands(self, G):
        lf = np.log2(np.maximum(self.f, 1.0))
        return 10 ** (np.interp(lf, np.log2(FB), G) / 20)

    def process(self, x):
        """x: (n,) or (n, ch). Linked stereo: analysis on the channel sum. Returns latency-compensated output."""
        mono = x.ndim == 1
        X = x[:, None] if mono else x
        n, ch = X.shape
        pad = np.vstack([np.zeros((N, ch)), X, np.zeros((N, ch))])
        out = np.zeros_like(pad)
        for s in range(0, len(pad) - N, HOP):
            fr = pad[s:s + N] * self.win[:, None]
            F = np.fft.rfft(fr, axis=0)
            P = np.sum(np.abs(F) ** 2, axis=1) / ch
            g = self.bins_from_bands(self.band_gains(P))
            out[s:s + N] += np.fft.irfft(F * g[:, None], N, axis=0) * self.win[:, None]
        out *= HOP / (N * 0.5)                                  # sqrt-Hann^2 OLA gain at 75 % overlap
        y = out[N:N + n]
        y = self.mix * y + (1 - self.mix) * X
        return y[:, 0] if mono else y


# ------------------------------------------------------------------ fake study folder
CASE_MAP = {           # case id -> prototype settings (mirrors the Lua kit's case list)
    'C01_amount0': dict(amount=0), 'C02_amount1': dict(amount=1), 'C03_amount3': dict(amount=3),
    'C04_amount5': dict(amount=5), 'C05_amount7': dict(amount=7), 'C06_amount8_5': dict(amount=8.5),
    'C07_amount10': dict(amount=10),
    'C10_att_min': dict(amount=7, attack=0), 'C11_att_max': dict(amount=7, attack=1),
    'C12_rel_min': dict(amount=7, release=0), 'C13_rel_max': dict(amount=7, release=1),
    'C14_tone1_up': dict(amount=7, tones=[(100, 6), (500, 0), (2500, 0), (10000, 0)]),
    'C16_tone2_up': dict(amount=7, tones=[(100, 0), (500, 6), (2500, 0), (10000, 0)]),
    'C18_tone3_up': dict(amount=7, tones=[(100, 0), (500, 0), (2500, 6), (10000, 0)]),
    'C20_tone4_up': dict(amount=7, tones=[(100, 0), (500, 0), (2500, 0), (10000, 6)]),
    'C29_mix50': dict(amount=7, mix=0.5),
}
CASE_SIGS = {
    'C01_amount0': ['S01_pink', 'S06_bumps', 'S11_clicks'],
    'C06_amount8_5': ['S01_pink', 'S06_bumps', 'S08_ladder', 'S10_burst', 'S11_clicks'],
    'C07_amount10': ['S01_pink', 'S06_bumps', 'S08_ladder', 'S10_burst', 'S11_clicks'],
    'C29_mix50': ['S06_bumps', 'S11_clicks'],
}
ST = ['S01_pink', 'S02_white', 'S03_brown', 'S04_bright', 'S05_dark', 'S06_bumps', 'S07_hole']
DYN = ['S08_ladder', 'S09_switch', 'S10_burst', 'S11_clicks']


def fake(root):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from analyze_bloom import read_wav
    import struct
    sig_dir = os.path.join(root, 'signals'); os.makedirs(os.path.join(root, 'renders'), exist_ok=True)
    ids = sorted(f[:-4] for f in os.listdir(sig_dir) if f.endswith('.wav'))
    signals = [{'id': i, 'file': 'signals/%s.wav' % i, 'channels': 2 if i == 'S12_stereo' else 1} for i in ids]
    outputs = []
    for cid, kw in CASE_MAP.items():
        sigs = CASE_SIGS.get(cid) or (ST + DYN if cid in ('C04_amount5', 'C05_amount7') else
                                      ['S09_switch', 'S10_burst', 'S11_clicks'] if 'att' in cid or 'rel' in cid else
                                      ['S01_pink', 'S05_dark'] if 'tone' in cid else ST)
        for sid in sigs:
            x, _ = read_wav(os.path.join(sig_dir, sid + '.wav'))
            y = Poise(**kw).process(x[:, 0] if x.shape[1] == 1 else x)
            y = y[:, None] if y.ndim == 1 else y
            path = os.path.join(root, 'renders', '%s__%s.wav' % (cid, sid))
            with open(path, 'wb') as f:
                d = y.astype('<f4').tobytes()
                f.write(b'RIFF' + struct.pack('<I', 36 + len(d)) + b'WAVE')
                f.write(b'fmt ' + struct.pack('<IHHIIHH', 16, 3, y.shape[1], SR, SR * 4 * y.shape[1], 4 * y.shape[1], 32))
                f.write(b'data' + struct.pack('<I', len(d)) + d)
            outputs.append({'case': cid, 'signal': sid, 'file': 'renders/%s__%s.wav' % (cid, sid)})
            print('rendered', cid, sid)
    json.dump({'plugin': 'prototype (FXD Poise model)', 'sample_rate': SR, 'signals': signals, 'outputs': outputs,
               'cases': [{'id': c, 'requested': k} for c, k in CASE_MAP.items()]}, open(os.path.join(root, 'manifest.json'), 'w'), indent=1)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'fake':
        fake(sys.argv[2])

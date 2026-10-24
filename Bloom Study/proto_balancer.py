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


DEFAULT_TONES = [(100, 0.0), (350, 0.0), (3500, 0.0), (6300, 0.0)]


class Poise:
    def __init__(self, amount=5.0, attack=0.5, release=0.3, tones=None, mix=1.0, squash_cal=0.0, sr=SR):
        self.sr = sr
        self.W, self.f = band_weights(N, sr)
        self.Wn = self.W / self.W.sum(axis=1, keepdims=True)
        self.amount, self.mix, self.squash_cal = amount, mix, squash_cal
        # attack 0..1 -> 40..480 ms, release 0..1 -> 20..280 ms one-pole (plus frame lag: lands near the bloom study's 63 % times)
        fr = sr / HOP
        ta = 0.04 * 12 ** attack; trl = 0.02 * 14 ** release
        self.ca, self.cr = math.exp(-1 / (ta * fr)), math.exp(-1 / (trl * fr))
        self.tones = tones or DEFAULT_TONES
        # house curve: a gentle loudness "smile" the correction leans toward (a user-selectable Voice later)
        self.house = 1.2 * gauss_oct(70, 1.2) - 1.0 * gauss_oct(2500, 0.9)
        self.sens = sensitivity_db(FB)
        sw = np.exp(-0.5 * (np.log2(FB / 3000) / 1.5) ** 2)
        self.mid_w = 0.6 + 0.4 * sw                              # correct mid-scale lumps more where the ear is sensitive
        self.tone_curve = self.tone_eq(self.tones)
        self.level = None
        self.win = np.sqrt(np.hanning(N + 1)[:N])
        # dB offset from 'trend' (mean bin power + 10log10 f) to band RMS in dBFS
        step = math.log2(FB[1] / FB[0])
        self.cal = 10 * math.log10(math.log(2) * step * N / sr) + 10 * math.log10(2 / (N * np.sum(self.win ** 2)))
        self.gain_hist = []

    @staticmethod
    def tone_eq(tones):
        """Static broad EQ from the four tone controls (level -10..10 ~ dB at the centre), slightly level-compensated."""
        lf = np.log2(FB)
        G = np.zeros(NB)
        for i, (fc, lv) in enumerate(tones):
            d = lf - math.log2(fc)
            if i == 0:   shape = 0.75 / (1 + np.exp((d - 0.4) / 0.45))     # low shelf
            elif i == 3: shape = 1.3 / (1 + np.exp(-(d + 0.3) / 0.6))      # high shelf, keeps rising
            else:        shape = np.exp(-0.5 * (d / 0.85) ** 2)             # bell
            G += lv * (shape - 0.06)
        return G

    @staticmethod
    def smooth(v, sigma_oct):
        ob = math.log2(FB[1] / FB[0])
        h = int(math.ceil(3 * sigma_oct / ob))
        k = np.arange(-h, h + 1); g = np.exp(-0.5 * (k * ob / sigma_oct) ** 2); g /= g.sum()
        return np.convolve(np.pad(v, h, mode='edge'), g, mode='same')[h:-h]

    def band_gains(self, P):
        bl = 10 * np.log10(self.Wn @ P + 1e-20) + 10 * np.log10(FB)   # power per octave: pink reads flat
        if self.level is None: self.level = bl.copy()
        rise = bl > self.level
        c = np.where(rise, self.ca, self.cr)
        self.level = c * self.level + (1 - c) * bl
        # two scales: broad tilt (2 oct) and mid-scale lumps (0.5 oct minus 2 oct)
        fine, broad = self.smooth(self.level, 0.5), self.smooth(self.level, 2.0)
        w = 10 ** ((broad + self.sens) / 10); w /= w.sum()          # loudness weights
        tilt = broad - np.sum(w * broad)
        lump = fine - broad
        a = min(self.amount, 7.0) / 7.0
        G = a * (self.house - 0.12 * tilt - 0.65 * self.mid_w * lump)
        G = G - np.sum(w * G)                                          # level neutral
        G = np.clip(G, -12, 12) + self.tone_curve
        if self.amount > 7:                                     # squash: up/down compression per band
            inv_r = max(0.1, 1 - 0.4 * (self.amount - 7))     # 1/ratio: 1 at 7, 0.4 at 8.5, 0.1 at 10
            thr = -33 - 10 * math.log10(NB) - self.squash_cal + 10 * np.log10(1 + (120 / FB) ** 2.2)  # higher at the low end
            over = (fine + self.cal) - thr                      # band RMS in dBFS above the threshold
            knee = 6 + 0.3 * (-self.sens)                       # harder knee where the ear is less sensitive
            soft = over * np.abs(over) / (np.abs(over) + knee)
            G = np.clip(G - soft * (1 - inv_r), -30, 24)
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
    **{'C%02d_tone%d_%s' % (12 + 2 * k + (d < 0), k, 'up' if d > 0 else 'dn'):
       dict(amount=7, tones=[(fc, d if j == k - 1 else 0) for j, fc in enumerate((100, 350, 3500, 6300))])
       for k in range(1, 5) for d in (10, -10)},
    'C29_mix50': dict(amount=7, mix=0.5),
    'C08_sqcal_hi': dict(amount=10, squash_cal=24), 'C09_sqcal_lo': dict(amount=10, squash_cal=-24),
}
CASE_SIGS = {
    'C01_amount0': ['S01_pink', 'S06_bumps', 'S11_clicks'],
    'C06_amount8_5': ['S01_pink', 'S06_bumps', 'S08_ladder', 'S10_burst', 'S11_clicks'],
    'C07_amount10': ['S01_pink', 'S06_bumps', 'S08_ladder', 'S10_burst', 'S11_clicks'],
    'C29_mix50': ['S06_bumps', 'S11_clicks'],
    'C08_sqcal_hi': ['S08_ladder'], 'C09_sqcal_lo': ['S08_ladder'],
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

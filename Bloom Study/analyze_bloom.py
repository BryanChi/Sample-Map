#!/usr/bin/env python3
"""Analyse a Bloom Study folder (made by 'Bloom Study Kit.lua').

    python3 analyze_bloom.py "<project>/Bloom Study"

Needs only numpy. Writes results.json and report.html (inline SVG charts) into the folder.
Everything is measured from audio in and audio out; nothing looks inside the plug-in.
"""
import json, math, os, struct, sys
import numpy as np

SR = 48000
SETTLE = 3.0                     # seconds skipped before steady-state measurements
NFFT = 8192
F_LO, F_HI = 25.0, 20000.0

# ------------------------------------------------------------------ io
def read_wav(path):
    with open(path, 'rb') as f:
        d = f.read()
    if d[:4] != b'RIFF' or d[8:12] != b'WAVE':
        raise ValueError(path + ' is not a WAV file')
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(d):
        cid, size = d[pos:pos + 4], struct.unpack('<I', d[pos + 4:pos + 8])[0]
        body = d[pos + 8:pos + 8 + size]
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', body[:16])
            if fmt[0] == 0xFFFE and len(body) >= 26:
                fmt = (struct.unpack('<H', body[24:26])[0],) + fmt[1:]
        elif cid == b'data':
            data = body
        pos += 8 + size + (size & 1)
    tag, ch, sr, _, _, bits = fmt
    if tag == 3:
        x = np.frombuffer(data, dtype='<f4' if bits == 32 else '<f8').astype(np.float64)
    elif bits == 16:
        x = np.frombuffer(data, dtype='<i2') / 32768.0
    elif bits == 24:
        b = np.frombuffer(data[:len(data) // 3 * 3], dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        x = np.where(v >= 1 << 23, v - (1 << 24), v) / float(1 << 23)
    elif bits == 32:
        x = np.frombuffer(data, dtype='<i4') / 2147483648.0
    else:
        raise ValueError('unsupported WAV format %d/%d' % (tag, bits))
    x = x[:len(x) // ch * ch].reshape(-1, ch)
    return x, sr

# ------------------------------------------------------------------ dsp helpers
def bands_third_oct():
    centres = 1000.0 * 2.0 ** (np.arange(-16, 14) / 3.0)          # 25 Hz .. 20 kHz
    return centres[(centres >= F_LO) & (centres <= F_HI)]

BANDS = bands_third_oct()

def band_matrix(nfft, sr, centres=BANDS, width=1 / 3):
    f = np.fft.rfftfreq(nfft, 1 / sr)
    M = np.zeros((len(centres), len(f)))
    for i, c in enumerate(centres):
        lo, hi = c * 2 ** (-width / 2), c * 2 ** (width / 2)
        M[i] = (f >= lo) & (f < hi)
    return M

def welch(x, y=None, nfft=NFFT):
    w = np.hanning(nfft)
    hop = nfft // 2
    n = (len(x) - nfft) // hop + 1
    Sxx = np.zeros(nfft // 2 + 1); Sxy = np.zeros(nfft // 2 + 1, complex); Syy = np.zeros(nfft // 2 + 1)
    for i in range(n):
        X = np.fft.rfft(x[i * hop:i * hop + nfft] * w)
        Sxx += np.abs(X) ** 2
        if y is not None:
            Y = np.fft.rfft(y[i * hop:i * hop + nfft] * w)
            Sxy += np.conj(X) * Y; Syy += np.abs(Y) ** 2
    return Sxx / n, Sxy / n, Syy / n

def lag_of(x, y, maxlag=16384):
    n = 1 << int(math.ceil(math.log2(len(x) + len(y))))
    c = np.fft.irfft(np.fft.rfft(y, n) * np.conj(np.fft.rfft(x, n)), n)
    c = np.concatenate([c[-maxlag:], c[:maxlag + 1]])
    return int(np.argmax(np.abs(c))) - maxlag

def shift(y, lag):
    if lag > 0:  return np.concatenate([y[lag:], np.zeros(lag)])
    if lag < 0:  return np.concatenate([np.zeros(-lag), y[:lag]])
    return y

def k_weight_power(nfft, sr):
    """|K(f)|^2 of the BS.1770 pre-filter (48 kHz coefficients)."""
    f = np.fft.rfftfreq(nfft, 1 / sr)
    z = np.exp(-2j * np.pi * f / sr)
    def biq(b, a):
        return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    h = biq([1.53512485958697, -2.69169618940638, 1.19839281085285], [1, -1.69065929318241, 0.73248077421585]) * \
        biq([1, -2, 1], [1, -1.99004745483398, 0.99007225036621])
    return np.abs(h) ** 2

KW = k_weight_power(NFFT, SR)
BM = band_matrix(NFFT, SR)

def db(x):
    return 10 * np.log10(np.maximum(x, 1e-20))

def lufs_like(Sxx):
    return float(db(np.sum(Sxx * KW)) - 0.691)

# ------------------------------------------------------------------ measurements
def steady(x, y):
    """Transfer curve (third-octave dB), output band spectrum, loudness change, IR facts."""
    a = int(SETTLE * SR)
    Sxx, Sxy, Syy = welch(x[a:], y[a:])
    bx, by = BM @ Sxx, BM @ Syy
    gain = db(by) - db(bx)
    H = Sxy / np.maximum(Sxx, 1e-20)
    f = np.fft.rfftfreq(NFFT, 1 / SR)
    H[(f < 30) | (f > 19000)] = 0               # the test noise has no energy there: H would be noise
    ir = np.fft.irfft(H)
    ir = np.roll(ir, NFFT // 2)                  # centre so pre-ringing is visible
    pk = int(np.argmax(np.abs(ir)))
    e = ir ** 2
    pre = float(db(np.sum(e[:max(pk - 48, 0)]) / np.sum(e)))     # energy > 1 ms before the peak
    coh = np.abs(Sxy) ** 2 / np.maximum(Sxx * Syy, 1e-30)
    return {
        'gain_db': gain.round(2).tolist(),
        'out_band_db': (db(by) - np.mean(db(by))).round(2).tolist(),
        'in_band_db': (db(bx) - np.mean(db(bx))).round(2).tolist(),
        'loudness_change_db': round(lufs_like(Syy) - lufs_like(Sxx), 2),
        'ir_peak_offset': pk - NFFT // 2,
        'pre_ring_db': round(pre, 1),
        'coherence_mean': round(float(np.mean(coh[(np.fft.rfftfreq(NFFT, 1 / SR) > 40) & (np.fft.rfftfreq(NFFT, 1 / SR) < 16000)])), 3),
    }

def band_tracks(x, y, nfft=2048, hop=240):
    """Per-frame third-octave gain (dB) and input level, 5 ms resolution."""
    w = np.hanning(nfft)
    M = band_matrix(nfft, SR)
    n = (len(x) - nfft) // hop + 1
    G = np.zeros((n, len(BANDS))); L = np.zeros((n, len(BANDS)))
    for i in range(n):
        X = np.abs(np.fft.rfft(x[i * hop:i * hop + nfft] * w)) ** 2
        Y = np.abs(np.fft.rfft(y[i * hop:i * hop + nfft] * w)) ** 2
        bx, byy = M @ X, M @ Y
        G[i] = db(byy) - db(bx); L[i] = db(bx)
    t = (np.arange(n) * hop + nfft / 2) / SR
    return t, G, L

def smooth_t(v, k=9):
    return np.convolve(v, np.ones(k) / k, mode='same')

def tau63(t, g, t0, t1):
    """Time from t0 until g has moved 63 % of the way to its value in the last 0.5 s before t1."""
    s = (t >= t0) & (t < t1)
    tt, gg = t[s], smooth_t(g[s])
    if len(gg) < 20: return None
    start, end = gg[2], np.mean(gg[tt > t1 - 0.5])
    if abs(end - start) < 0.5: return None
    target = start + 0.63 * (end - start)
    hit = np.where((gg - target) * np.sign(end - start) >= 0)[0]
    return round(float(tt[hit[0]] - t0) * 1000, 1) if len(hit) else None

def switch_times(t, G, L, seg=3.0, nseg=8):
    out = {'attack_ms': {}, 'release_ms': {}}
    for fc in (125, 1000, 8000):
        bi = int(np.argmin(np.abs(BANDS - fc)))
        att, rel = [], []
        for k in range(1, nseg):
            t0 = k * seg
            v = tau63(t, G[:, bi], t0, t0 + seg)
            if v is None: continue
            pre = np.mean(L[(t > t0 - 1) & (t < t0), bi]); post = np.mean(L[(t > t0 + 0.2) & (t < t0 + 1), bi])
            (att if post > pre else rel).append(v)
        out['attack_ms'][str(fc)] = float(np.median(att)) if att else None
        out['release_ms'][str(fc)] = float(np.median(rel)) if rel else None
    return out

def ladder(x, y):
    t, G, L = band_tracks(x, y)
    levels = [-42, -30, -18, -12, -6]
    curves = []
    for i, lv in enumerate(levels):
        s = (t > i * 5 + 2) & (t < i * 5 + 4.8)
        curves.append(np.mean(G[s], axis=0))
    C = np.array(curves)
    shape = C - C.mean(axis=1, keepdims=True)
    return {
        'levels_dbfs': levels,
        'curves_db': C.round(2).tolist(),
        'mean_gain_db': C.mean(axis=1).round(2).tolist(),
        'shape_spread_db': round(float(np.max(np.std(shape, axis=0))), 2),
    }

def burst(x, y):
    t, G, L = band_tracks(x, y)
    bi = int(np.argmin(np.abs(BANDS - 1000)))
    on, off = [], []
    for k in range(1, 7):
        t0 = k * 3.0
        a = tau63(t, G[:, bi], t0, t0 + 1.0); r = tau63(t, G[:, bi], t0 + 1.0, t0 + 3.0)
        if a: on.append(a)
        if r: off.append(r)
    g = G[:, bi]
    in_burst = np.mean([np.mean(g[(t > k * 3 + 0.6) & (t < k * 3 + 0.95)]) for k in range(1, 7)])
    between = np.mean([np.mean(g[(t > k * 3 + 2.4) & (t < k * 3 + 2.95)]) for k in range(1, 7)])
    return {'attack_ms_1k': float(np.median(on)) if on else None, 'release_ms_1k': float(np.median(off)) if off else None,
            'gain_1k_during_burst_db': round(float(in_burst), 2), 'gain_1k_between_db': round(float(between), 2),
            'track_t': t[::4].round(3).tolist(), 'track_1k_db': g[::4].round(2).tolist()}

def clicks(x, y):
    res = []
    for k in range(3, 16):
        c = int((k + 0.5) * SR)
        wi, wo = x[c - 960:c + 960], y[c - 960:c + 960]
        pre_in = np.sum(x[c - 480:c - 24] ** 2); pre_out = np.sum(y[c - 480:c - 24] ** 2)
        res.append((db(np.max(np.abs(wo)) ** 2) - db(np.max(np.abs(wi)) ** 2), db(pre_out) - db(pre_in)))
    r = np.array(res)
    return {'peak_change_db': round(float(np.median(r[:, 0])), 2), 'pre_click_energy_change_db': round(float(np.median(r[:, 1])), 2)}

# ------------------------------------------------------------------ svg charts
PALETTE = ['#2a78d6', '#e0612a', '#2e9e6a', '#b0418f', '#c9a227', '#6a5acd', '#1aa5b8', '#d0453f', '#7a7a7a', '#8b5a2b']

def svg_chart(series, title, ylabel, xlog=True, x=None, ymin=None, ymax=None, w=640, h=260):
    x = np.asarray(BANDS if x is None else x, float)
    ys = [np.asarray(s[1], float) for s in series]
    lo = min(np.nanmin(v) for v in ys) if ymin is None else ymin
    hi = max(np.nanmax(v) for v in ys) if ymax is None else ymax
    if hi - lo < 2: lo, hi = lo - 1, hi + 1
    pad = 0.08 * (hi - lo); lo -= pad; hi += pad
    L, R, T, B = 48, 12, 28, 34
    fx = (lambda v: L + (math.log10(v) - math.log10(x[0])) / (math.log10(x[-1]) - math.log10(x[0])) * (w - L - R)) if xlog \
        else (lambda v: L + (v - x[0]) / (x[-1] - x[0]) * (w - L - R))
    fy = lambda v: T + (hi - v) / (hi - lo) * (h - T - B)
    o = ['<svg viewBox="0 0 %d %d" class="chart" role="img" aria-label="%s">' % (w, h, title),
         '<text x="%d" y="18" class="ct">%s</text>' % (L, title)]
    step = 10 ** math.floor(math.log10((hi - lo) / 2)); step *= 2 if (hi - lo) / step > 8 else 1
    v = math.ceil(lo / step) * step
    while v <= hi:
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" class="grid"/><text x="%d" y="%.1f" class="ax" text-anchor="end">%g</text>'
                 % (L, w - R, fy(v), fy(v), L - 6, fy(v) + 4, round(v, 3)))
        v += step
    ticks = [31.5, 100, 315, 1000, 3150, 10000] if xlog else np.linspace(x[0], x[-1], 6)
    for tv in ticks:
        lab = ('%gk' % (tv / 1000) if tv >= 1000 else '%g' % tv) if xlog else '%.3g' % tv
        o.append('<text x="%.1f" y="%d" class="ax" text-anchor="middle">%s</text>' % (fx(tv), h - B + 16, lab))
    o.append('<text x="%d" y="%d" class="ax">%s</text>' % (w - R - 90, h - 4, 'Hz' if xlog else 's'))
    o.append('<text x="10" y="%d" class="ax" transform="rotate(-90 10 %d)">%s</text>' % (h // 2 + 20, h // 2 + 20, ylabel))
    for i, (name, yv) in enumerate(series):
        yv = np.asarray(yv, float)
        pts = ' '.join('%.1f,%.1f' % (fx(a), fy(b)) for a, b in zip(x, yv) if np.isfinite(b))
        o.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.8"/>' % (pts, PALETTE[i % len(PALETTE)]))
    o.append('</svg>')
    leg = ''.join('<span><i style="background:%s"></i>%s</span>' % (PALETTE[i % len(PALETTE)], n) for i, (n, _) in enumerate(series))
    return '<figure>' + ''.join(o) + '<figcaption class="legend">' + leg + '</figcaption></figure>'

# ------------------------------------------------------------------ main
def main(root):
    man = json.load(open(os.path.join(root, 'manifest.json')))
    sig = {s['id']: read_wav(os.path.join(root, s['file']))[0] for s in man['signals']}
    res = {'plugin': man.get('plugin'), 'bands_hz': BANDS.round(1).tolist(), 'cases': {}}
    for o in man['outputs']:
        y, sr = read_wav(os.path.join(root, o['file']))
        x = sig[o['signal']]
        n = min(len(x), len(y))
        x, y = x[:n], y[:n]
        r = {}
        chans = range(x.shape[1]) if o['signal'] == 'S12_stereo' else [0]
        for ch in chans:
            xc, yc = x[:, ch], y[:, min(ch, y.shape[1] - 1)]
            lag = lag_of(xc[int(SETTLE * SR):], yc[int(SETTLE * SR):])
            yc = shift(yc, lag)
            key = '' if len(chans) == 1 else ('_L', '_R')[ch]
            r['lag_samples' + key] = lag
            r['steady' + key] = steady(xc, yc)
            if o['signal'] == 'S08_ladder': r['ladder'] = ladder(xc, yc)
            if o['signal'] == 'S09_switch': r['switch'] = switch_times(*band_tracks(xc, yc))
            if o['signal'] == 'S10_burst':  r['burst'] = burst(xc, yc)
            if o['signal'] == 'S11_clicks': r['clicks'] = clicks(xc, yc)
        res['cases'].setdefault(o['case'], {})[o['signal']] = r
        print('%-16s %-12s lag %5d  loudness %+5.2f dB  pre-ring %6.1f dB' % (
            o['case'], o['signal'], r.get('lag_samples', r.get('lag_samples_L', 0)),
            r.get('steady', r.get('steady_L'))['loudness_change_db'], r.get('steady', r.get('steady_L'))['pre_ring_db']))

    # convergence: how much of the spread between differently tilted inputs is removed per case
    stat = ['S01_pink', 'S02_white', 'S03_brown', 'S04_bright', 'S05_dark', 'S06_bumps', 'S07_hole']
    conv = {}
    for cid, c in res['cases'].items():
        have = [s for s in stat if s in c]
        if len(have) < 5: continue
        In = np.array([c[s]['steady']['in_band_db'] for s in have]); Out = np.array([c[s]['steady']['out_band_db'] for s in have])
        m = (BANDS > 40) & (BANDS < 16000)
        conv[cid] = {'correction_fraction': round(float(1 - np.mean(np.std(Out[:, m], 0)) / np.mean(np.std(In[:, m], 0))), 3),
                     'implied_target_db': np.mean(Out, 0).round(2).tolist()}
    res['convergence'] = conv
    json.dump(res, open(os.path.join(root, 'results.json'), 'w'), indent=1)
    write_report(root, res)
    print('\nwrote results.json and report.html in', root)

def write_report(root, res):
    C = res['cases']
    parts = ['<h1>Bloom study: measured behaviour</h1><p>Plug-in: %s. Third-octave transfer curves in dB after %g s settle.</p>' % (res.get('plugin'), SETTLE)]
    def g(cid, sid, key='gain_db'):
        try: return C[cid][sid]['steady'][key]
        except KeyError: return None
    for sid in ('S01_pink', 'S06_bumps', 'S03_brown', 'S02_white'):
        ser = [(cid, g(cid, sid)) for cid in sorted(C) if 'amount' in cid and g(cid, sid)]
        if ser: parts.append(svg_chart(ser, 'Gain vs Amount on ' + sid, 'dB'))
    for cid in sorted(res['convergence']):
        cv = res['convergence'][cid]
        ser = [(s, C[cid][s]['steady']['out_band_db']) for s in sorted(C[cid]) if s < 'S08']
        ser.append(('mean (implied target)', cv['implied_target_db']))
        parts.append(svg_chart(ser, '%s: output band spectra (pink = flat), correction %.0f%%' % (cid, 100 * cv['correction_fraction']), 'dB'))
    base = g('C05_amount7', 'S01_pink')
    if base:
        ser = []
        for k in range(1, 5):
            for d in ('up', 'dn'):
                v = g('C%02d_tone%d_%s' % (12 + 2 * k + (d == 'dn'), k, d), 'S01_pink')
                if v: ser.append(('tone%d %s' % (k, d), (np.array(v) - np.array(base)).tolist()))
        if ser: parts.append(svg_chart(ser, 'Tone controls: change vs Amount 7 on pink', 'dB'))
    for cid in sorted(C):
        if 'S08_ladder' in C[cid]:
            L = C[cid]['S08_ladder']['ladder']
            parts.append(svg_chart([('%d dBFS' % lv, cv) for lv, cv in zip(L['levels_dbfs'], L['curves_db'])],
                                   '%s: curve per input level (shape spread %.1f dB)' % (cid, L['shape_spread_db']), 'dB'))
    ser = [(cid, C[cid]['S10_burst']['burst']['track_1k_db']) for cid in sorted(C) if 'S10_burst' in C[cid]]
    if ser:
        t = C[sorted(c for c in C if 'S10_burst' in C[c])[0]]['S10_burst']['burst']['track_t']
        ser = [(n, v[:len(t)]) for n, v in ser]
        parts.append(svg_chart(ser, '1 kHz band gain over time, burst signal', 'dB', xlog=False, x=t))
    rows = []
    for cid in sorted(C):
        for sid in sorted(C[cid]):
            r = C[cid][sid]; st = r.get('steady') or r.get('steady_L')
            extra = []
            if 'switch' in r: extra.append('attack %s / release %s ms' % (r['switch']['attack_ms'], r['switch']['release_ms']))
            if 'burst' in r: b = r['burst']; extra.append('1k: %s dB in burst, %s dB between, on %s ms, off %s ms' % (b['gain_1k_during_burst_db'], b['gain_1k_between_db'], b['attack_ms_1k'], b['release_ms_1k']))
            if 'clicks' in r: extra.append('click peak %+.1f dB, pre-click %+.1f dB' % (r['clicks']['peak_change_db'], r['clicks']['pre_click_energy_change_db']))
            if 'ladder' in r: extra.append('mean gain per level %s' % r['ladder']['mean_gain_db'])
            rows.append('<tr><td>%s</td><td>%s</td><td>%s</td><td>%+.2f</td><td>%s</td><td>%.2f</td><td>%s</td></tr>' % (
                cid, sid, r.get('lag_samples', r.get('lag_samples_L')), st['loudness_change_db'], st['pre_ring_db'], st['coherence_mean'], '; '.join(extra)))
    parts.append('<h2>All renders</h2><table><tr><th>case</th><th>signal</th><th>lag</th><th>loudness</th><th>pre-ring dB</th><th>coherence</th><th>dynamics</th></tr>%s</table>' % ''.join(rows))
    css = (':root{--bg:#fff;--fg:#1d1d1f;--mut:#666;--grid:#e3e3e3}@media (prefers-color-scheme:dark){:root{--bg:#161617;--fg:#eee;--mut:#999;--grid:#333}}'
           'body{background:var(--bg);color:var(--fg);font:14px system-ui;margin:24px auto;max-width:900px;padding:0 16px}'
           '.chart{width:100%;height:auto}.ct{font-size:13px;font-weight:600;fill:var(--fg)}.ax{font-size:10px;fill:var(--mut)}.grid{stroke:var(--grid)}'
           '.legend span{margin-right:12px;font-size:12px;white-space:nowrap}.legend i{display:inline-block;width:10px;height:10px;margin-right:4px;border-radius:2px}'
           'table{border-collapse:collapse;font-size:12px}td,th{border-bottom:1px solid var(--grid);padding:3px 6px;text-align:left;vertical-align:top}figure{margin:18px 0}')
    open(os.path.join(root, 'report.html'), 'w').write('<!doctype html><meta charset="utf-8"><title>Bloom study report</title><style>%s</style>%s' % (css, ''.join(parts)))

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')

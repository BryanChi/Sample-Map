#!/usr/bin/env python3
"""Side-by-side summary of two results.json files (e.g. bloom vs the Poise prototype).

    python3 compare_results.py <bloom results.json> <prototype results.json>
"""
import json, sys
import numpy as np

def summary(path):
    r = json.load(open(path)); c = r['cases']; B = np.array(r['bands_hz'])
    g = lambda cid, s: np.array(c[cid][s]['steady']['gain_db'])
    out = {'correction': {k: v['correction_fraction'] for k, v in r['convergence'].items()}}
    S = ['S01_pink', 'S02_white', 'S03_brown', 'S04_bright', 'S05_dark']
    if all(s in c.get('C05_amount7', {}) for s in S):
        X = np.array([c['C05_amount7'][s]['steady']['in_band_db'] for s in S]); G = np.array([g('C05_amount7', s) for s in S])
        out['tilt_slope_A7'] = float(np.median([np.polyfit(X[:, b], G[:, b], 1)[0] for b in range(len(B)) if 40 < B[b] < 16000]))
    def lump(sig, fc):
        b = int(np.argmin(abs(B - fc)))
        dx = c['C05_amount7'][sig]['steady']['in_band_db'][b] - c['C05_amount7']['S01_pink']['steady']['in_band_db'][b]
        return (g('C05_amount7', sig)[b] - g('C05_amount7', 'S01_pink')[b]) / dx
    out['lump_ratio_250'] = lump('S06_bumps', 250); out['lump_ratio_4k'] = lump('S06_bumps', 4000); out['hole_ratio_1k'] = lump('S07_hole', 1000)
    out['pink_A7_curve'] = g('C05_amount7', 'S01_pink')[::3].round(1).tolist()
    out['pink_A10_curve'] = g('C07_amount10', 'S01_pink')[::3].round(1).tolist()
    for k in ('C06_amount8_5', 'C07_amount10', 'C08_sqcal_hi', 'C09_sqcal_lo'):
        if 'S08_ladder' in c.get(k, {}): out['ladder_' + k] = c[k]['S08_ladder']['ladder']['mean_gain_db']
    for k in ('C10_att_min', 'C05_amount7', 'C11_att_max', 'C12_rel_min', 'C13_rel_max'):
        if 'S09_switch' in c.get(k, {}):
            sw = c[k]['S09_switch']['switch']; out['times_' + k] = (sw['attack_ms']['125'], sw['release_ms']['125'], sw['attack_ms']['8000'], sw['release_ms']['8000'])
    for k in ('C14_tone1_up', 'C16_tone2_up', 'C19_tone3_dn', 'C21_tone4_dn'):
        if k in c: out['tone_' + k] = (g(k, 'S01_pink') - g('C05_amount7', 'S01_pink'))[::3].round(1).tolist()
    out['pre_ring_pink_A7'] = c['C05_amount7']['S01_pink']['steady']['pre_ring_db']
    out['bands'] = B[::3].round(0).tolist()
    return out

a, b = summary(sys.argv[1]), summary(sys.argv[2])
for k in a:
    print('%-22s %s\n%-22s %s' % (k, a[k], '', b.get(k)))

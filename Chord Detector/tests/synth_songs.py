"""Synthesise test songs with known chords and keys for the Chord Detector.

python3 synth_songs.py OUTDIR  -> OUTDIR/<song>.wav + OUTDIR/<song>.truth.lua
"""
import sys, os, wave
import numpy as np

SR = 44100
rng = np.random.default_rng(7)
PC = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11}
QUAL = {'':('maj',[0,4,7]),'m':('min',[0,3,7]),'7':('7',[0,4,7,10]),'maj7':('maj7',[0,4,7,11]),
        'm7':('m7',[0,3,7,10]),'dim':('dim',[0,3,6]),'sus4':('sus4',[0,5,7]),'m7b5':('m7b5',[0,3,6,10])}

def parse(name):
    bass = None
    if '/' in name:
        name, b = name.split('/'); bass = PC[b]
    r = name[:2] if len(name) > 1 and name[1] in '#b' else name[:1]
    q = name[len(r):]
    qid, iv = QUAL[q]
    return PC[r], qid, iv, bass

def note(midi, dur, tune_cents=0.0, kind='piano', amp=1.0):
    f = 440.0 * 2 ** ((midi - 69 + tune_cents / 100) / 12)
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    if kind == 'piano':
        for h in range(1, 11):
            fh = f * h * np.sqrt(1 + 0.0004 * h * h)
            if fh > SR / 2.2: break
            a = (1 / h ** 1.1) * (0.7 + 0.6 * rng.random())
            out += a * np.sin(2 * np.pi * fh * t + rng.random() * 6.28) * np.exp(-t * (1.2 + 0.5 * h))
    elif kind == 'pad':
        for h in range(1, 8):
            fh = f * h
            if fh > SR / 2.2: break
            a = 1 / h ** 1.5
            for det in (-0.003, 0.003):
                out += 0.5 * a * np.sin(2 * np.pi * fh * (1 + det) * t + rng.random() * 6.28)
        env = np.minimum(1, t / 0.08) * np.minimum(1, (dur - t) / 0.1).clip(0)
        out *= env
    elif kind == 'bass':
        for h in range(1, 6):
            out += (1 / h ** 1.6) * np.sin(2 * np.pi * f * h * t)
        out *= np.exp(-t * 2.0)
    elif kind == 'lead':
        for h in range(1, 7):
            out += (1 / h) * np.sin(2 * np.pi * f * h * t)
        out *= np.minimum(1, t / 0.02) * np.exp(-t * 3)
    atk = np.minimum(1, t / 0.004)
    rel = np.clip((dur - t) / 0.03, 0, 1)
    return amp * out * atk * rel

def add(buf, start, sig):
    i = int(start * SR)
    j = min(len(buf), i + len(sig))
    if j > i: buf[i:j] += sig[:j - i]

def kick(): t = np.arange(int(0.25 * SR)) / SR; return np.sin(2 * np.pi * (50 + 80 * np.exp(-t * 30)) * t) * np.exp(-t * 14)
def snare(): n = int(0.18 * SR); t = np.arange(n) / SR; return (rng.standard_normal(n) * 0.6 + 0.4 * np.sin(2*np.pi*190*t)) * np.exp(-t * 22)
def hat(): n = int(0.05 * SR); t = np.arange(n) / SR; x = rng.standard_normal(n); x = np.diff(np.concatenate([[0], x])); return x * np.exp(-t * 80) * 0.5

def voicing(root, iv, low=55):
    pcs = [(root + i) % 12 for i in iv]
    out = []
    for pc in pcs:
        m = low + ((pc - low) % 12)
        out.append(m)
    return sorted(out)

def render(song):
    bpm = song['bpm']
    tune = song.get('tune', 0)
    prog = song['prog']
    lead_in = song.get('lead_in', 0.0)
    total_beats = sum(b for _, b in prog)
    drift = song.get('drift', 0.0)
    bt = [lead_in]
    for k in range(total_beats + 8):
        tempo = bpm * (1 + drift * np.sin(k / 5.0))
        bt.append(bt[-1] + 60 / tempo)
    def T(beat):  # fractional beat -> seconds
        k = int(np.floor(beat)); f = beat - k
        return bt[k] + f * (bt[k + 1] - bt[k])
    dur = T(total_beats) + song.get('tail', 1.5)
    buf = np.zeros(int(dur * SR) + SR)
    truth = []
    kind = song.get('kind', 'piano')
    push = song.get('push', 0.0)
    b0 = 0
    for ci, (name, nb) in enumerate(prog):
        root, qid, iv, bass = parse(name)
        sb = b0 - (push if ci > 0 else 0)
        eb = b0 + nb - (push if ci + 1 < len(prog) else 0)
        seg_start, seg_end = T(sb), T(eb)
        if kind == 'pad':
            for m in voicing(root, iv):
                add(buf, seg_start, note(m, seg_end - seg_start, tune, 'pad', 0.35))
        elif kind == 'arp':
            vs = voicing(root, iv, 52) + [voicing(root, iv, 52)[0] + 12]
            k = 0; b = sb
            while b < eb - 1e-6:
                m = vs[[0, 1, 2, 3, 2, 1][k % 6]]
                add(buf, T(b), note(m, 0.6, tune, 'piano', 0.45))
                b += 0.5; k += 1
        else:
            hits = [sb] + [float(x) for x in range(int(np.ceil(sb + 1e-6)), int(np.ceil(eb - 1e-6)))]
            for h in hits:
                for m in voicing(root, iv):
                    add(buf, T(h) + rng.random() * 0.01, note(m, 0.6, tune, 'piano', 0.33))
        bnote = (bass if bass is not None else root)
        bm = 36 + ((bnote - 36) % 12)
        b = sb
        while b < eb - 1e-6:
            ln = min(2, eb - b)
            add(buf, T(b), note(bm, (T(b + ln) - T(b)) * 0.95, tune, 'bass', 0.7))
            b += 2 if b == np.floor(b) else (np.ceil(b) - b)
        if song.get('melody', 0):
            scale = song['scale']
            for bb in range(b0, b0 + nb):
                ct = (root + iv[rng.integers(len(iv))]) % 12
                m = 72 + ((ct - 72) % 12)
                add(buf, T(bb), note(m, 0.3, tune, 'lead', 0.25 * song['melody']))
                pt = min(scale, key=lambda s: ((s - ct) % 12) if (s - ct) % 12 else 99)
                m2 = 72 + ((pt - 72) % 12)
                add(buf, T(bb + 0.5), note(m2, 0.3, tune, 'lead', 0.25 * song['melody']))
        truth.append((seg_start, seg_end, root, qid, bass, name))
        b0 += nb
    if song.get('drums', True):
        meter = song.get('meter', 4)
        g = song.get('drum_gain', 1.0)
        for i in range(total_beats):
            tb = T(i)
            if i % meter == 0 or (meter == 4 and i % 4 == 2): add(buf, tb, 0.8 * g * kick())
            elif meter == 4 or i % meter == 1: add(buf, tb, 0.35 * g * snare())
            add(buf, tb, g * hat()); add(buf, T(i + 0.5), g * hat())
    if song.get('noise_tail'):
        add(buf, T(total_beats) + 0.2, 0.05 * rng.standard_normal(int(song['noise_tail'] * SR)))
    if song.get('noise'):
        buf += song['noise'] * rng.standard_normal(len(buf)) * np.max(np.abs(buf)) * 0.1
    if song.get('reverb'):
        n = int(2.0 * SR); t = np.arange(n) / SR
        ir = rng.standard_normal(n) * np.exp(-t * 3.0); ir[0] = 1.0
        wet = np.fft.irfft(np.fft.rfft(buf, len(buf) + n) * np.fft.rfft(ir, len(buf) + n))[:len(buf)]
        wet *= np.max(np.abs(buf)) / (np.max(np.abs(wet)) + 1e-9)
        buf = buf + song['reverb'] * wet
    buf /= np.max(np.abs(buf)) * 1.1
    return buf, truth

MAJ = [0,2,4,5,7,9,11]
def sc(tonic, minor=False):
    s = [0,2,3,5,7,8,11] if minor else MAJ
    return [(tonic + i) % 12 for i in s]

SONGS = {
 'pop_C': dict(bpm=120, key='C major', prog=[(c, 4) for c in ['C','G','Am','F'] * 4], melody=1, scale=sc(0)),
 'eb_ballad': dict(bpm=80, key='Eb major', kind='pad', prog=[(c, 4) for c in ['Eb','Cm','Ab','Bb7'] * 3 + ['Eb']], melody=0.8, scale=sc(3)),
 'a_minor': dict(bpm=100, key='A minor', prog=[(c, 4) for c in ['Am','Dm','E7','Am','F','Dm','E7','Am'] * 2], melody=1, scale=sc(9, True)),
 'fsharp': dict(bpm=130, key='F# major', prog=[(c, 4) for c in ['F#','D#m','B','C#7'] * 4], melody=0.8, scale=sc(6)),
 'jazz_C': dict(bpm=110, key='C major', prog=[(c, 4) for c in ['Dm7','G7','Cmaj7','Cmaj7','Em7','A7','Dm7','G7'] * 2 + ['Cmaj7']], melody=0.6, scale=sc(0)),
 'modulate': dict(bpm=120, key='C major', keys=['C major','D major'], prog=[(c, 4) for c in ['C','F','G','C'] * 3 + ['D','G','A','D'] * 3], melody=0.8, scale=sc(0)),
 'bb_minor': dict(bpm=90, key='Bb minor', prog=[(c, 4) for c in ['Bbm','Gb','Db','Ab','Bbm','Ebm','F7','Bbm'] * 2], melody=0.8, scale=sc(10, True)),
 'detuned_fast': dict(bpm=96, key='G major', tune=40, prog=[(c, 2) for c in ['G','D','Em','C'] * 6], melody=1, scale=sc(7)),
 'silence_noise': dict(bpm=110, key='D major', lead_in=2.5, noise_tail=3, prog=[(c, 4) for c in ['D','Bm','G','A'] * 3], melody=0.6, scale=sc(2)),
 'hard_pop': dict(bpm=124, key='E major', prog=[(c, 4) for c in ['E','B/D#','C#m','A','E/G#','A','B','B7'] * 2 + ['E']], melody=2.2, drum_gain=1.8, noise=0.3, scale=sc(4)),
 'arpeggio': dict(bpm=92, key='Ab major', kind='arp', drums=False, prog=[(c, 4) for c in ['Ab','Fm','Db','Eb7','Cm','Fm','Bbm7','Eb7'] * 2 + ['Ab']], melody=0.5, scale=sc(8)),
 'rubato': dict(bpm=72, drift=0.12, key='G minor', kind='piano', drums=False, prog=[(c, n) for c, n in [('Gm',4),('Cm',4),('D7',4),('Gm',4),('Eb',4),('Cm',2),('D7',2),('Gm',8)] * 2], melody=0.7, scale=sc(7, True)),
 'push': dict(bpm=118, push=0.5, key='A major', prog=[(c, 4) for c in ['A','F#m','D','E'] * 4], melody=0.8, scale=sc(9)),
 'waltz': dict(bpm=150, meter=3, key='F major', prog=[(c, 3) for c in ['F','F','Dm','Dm','Gm','C7','F','F','Bb','C','Am','Dm','Gm','C7','F','F']], melody=0.7, scale=sc(5)),
 'wet_mix': dict(bpm=100, key='Bb major', reverb=1.2, noise=0.6, drum_gain=1.5, prog=[(c, 4) for c in ['Bb','Gm','Eb','F7'] * 4], melody=1.5, scale=sc(10)),
 'wet_pad': dict(bpm=76, key='E minor', kind='pad', reverb=1.5, noise=0.4, drums=False, prog=[(c, 4) for c in ['Em','C','G','D','Em','Am','B7','Em'] * 2], melody=1.0, scale=sc(4, True)),
 'db_mixed': dict(bpm=104, key='Db major', prog=[(c, n) for c, n in [('Db',4),('Bbm',4),('Gbmaj7',4),('Ab7',4),('Fm',2),('Bbm',2),('Ebm7',2),('Ab7',2),('Db',8)] * 2], melody=0.8, scale=sc(1)),
}

def write(path, x, sr=SR):
    y = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(y.tobytes())

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    for name, song in SONGS.items():
        x, truth = render(song)
        write(os.path.join(out, name + '.wav'), x)
        with open(os.path.join(out, name + '.truth.lua'), 'w') as f:
            f.write(('return { key = %r, keys = {%s}, chords = {\n' % (song['key'], ','.join(repr(k) for k in song.get('keys', [song['key']])))).replace("'", '"'))
            for s, e, r, q, b, nm in truth:
                f.write('  { %.4f, %.4f, %d, "%s", "%s" },\n' % (s, e, r, q, nm))
            f.write('} }\n')
        print(name, len(x) / SR)

"""Default Playscribe header art for games with no backdrop art (wide 16:9, tall 9:16).
A world being written: mountain ridges drawn from patch-note lines, the spark rising behind
them like a dawn sun, pages drifting like birds, and an update bar winding up the slope as the path.
Run from the repo root: python3 brand/tools/header.py, then node brand/tools/render.mjs."""
import json, math, random, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from gen import SPARK
B = pathlib.Path(__file__).resolve().parent.parent
C = json.loads((B / 'tokens.json').read_text())['color']
INK, PLUM, VEL, EMB = C['ink']['900'], C['icon']['bgTop'], C['vellum']['100'], C['accent']['base']

def ridge(rnd, w, base, amp, rough, peaks):
    """Height profile: a few broad peaks plus jagged noise, sampled every 8 px."""
    xs = list(range(-20, w + 28, 8))
    ph = [(rnd.uniform(0, w), rnd.uniform(.5, 1) * amp, rnd.uniform(w * .08, w * .22)) for _ in range(peaks)]
    ys, n = [], 0
    for x in xs:
        n = n * .9 + rnd.uniform(-1, 1) * rough * .5
        h = sum(a * math.exp(-((x - c) / s) ** 2) for c, a, s in ph)
        ys.append(base - h + n)
    return xs, ys

def header(w, h, seed, sun):
    rnd = random.Random(seed)
    sx, sy = sun
    out = []
    # Sky: plum to a warm horizon, the spark rising as a sun with a halo.
    out.append(f'<rect width="{w}" height="{h}" fill="url(#sky)"/>')
    out.append(f'<circle cx="{sx}" cy="{sy}" r="{h*.42:.0f}" fill="url(#halo)"/>')
    for i in range(70):  # stars
        x, y = rnd.uniform(0, w), rnd.uniform(0, h * .5)
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{rnd.choice([.8,1.1,1.5])}" fill="{VEL}" opacity="{rnd.uniform(.15,.55):.2f}"/>')
    k = h / 900 * 3.2
    out.append(f'<g transform="translate({sx} {sy}) scale({k:.2f}) translate(-32 -14.5)"><path d="{SPARK}" fill="{EMB}" filter="url(#bloom)" opacity=".9"/><path d="{SPARK}" fill="url(#spk)"/></g>')
    # Ridges, far to near. Each is a silhouette with patch-note dashes written along its contour.
    layers = 6
    for L in range(layers):
        t = L / (layers - 1)
        base = h * (.52 + .09 * L) if w > h else h * (.5 + .075 * L)
        xs, ys = ridge(rnd, w, base, h * (.22 - .025 * L), 4 + 2 * L, 3)
        # Keep a notch so the sun always shows above the ridges.
        tgt = sy + h * (.08 + .05 * L); sw = w * (.10 + .02 * L)
        ys = [y + max(0, tgt - y) * math.exp(-((x - sx) / sw) ** 2) for x, y in zip(xs, ys)]
        pts = ' '.join(f'{x},{y:.1f}' for x, y in zip(xs, ys))
        out.append(f'<polygon points="-20,{h} {pts} {w+28},{h}" fill="url(#r{L})"/>')
        # Dashes: rows of note lines following the ridge, fading as they go down the slope.
        rows = 9 - L // 2
        for r in range(1, rows):
            dy = r * (10 + 3 * L)
            x = rnd.uniform(-30, 10)
            while x < w:
                ln = rnd.choice([24, 36, 52, 70, 90]) * (1 + .4 * t)
                i0 = max(0, min(len(xs) - 1, int((x + 20) / 8)))
                i1 = max(0, min(len(xs) - 1, int((x + ln + 20) / 8)))
                y0, y1 = ys[i0] + dy, ys[i1] + dy
                op = (.16 - .012 * r) * (1 - .45 * t)
                if abs(y1 - y0) > ln * .45: op = 0
                if op > .02:
                    col = EMB if (L == 3 and rnd.random() < .06) else VEL
                    out.append(f'<line x1="{x:.0f}" y1="{y0:.1f}" x2="{x+ln:.0f}" y2="{y1:.1f}" stroke="{col}" stroke-width="{2.2 + 1.2*t:.1f}" stroke-linecap="round" opacity="{op*(3 if col==EMB else 1):.3f}"/>')
                x += ln + rnd.uniform(10, 34)
        # Rim light on the ridge line, warm where it faces the sun.
        out.append(f'<polyline points="{pts}" fill="none" stroke="url(#rim{L})" stroke-width="{1.4 + t:.1f}" opacity="{.7 - .5*t:.2f}"/>')
        if L == 4:
            # The path: an update bar winding through the foothills toward the sun, part way installed.
            x0, y0 = w * .06, h * .97
            x3, y3 = sx, ys[max(0, min(len(xs) - 1, int((sx + 20) / 8)))] + h * .05
            d = (f'M{x0:.0f} {y0:.0f} C{w*.42:.0f} {h*.98:.0f} {w*.18:.0f} {h*.80:.0f} {(x0+x3)/2:.0f} {(y0+y3)/2 + h*.04:.0f} '
                 f'S{x3 - w*.05:.0f} {y3 + h*.06:.0f} {x3:.0f} {y3:.0f}')
            out.append(f'<path d="{d}" fill="none" stroke="{VEL}" stroke-opacity=".18" stroke-width="5" stroke-linecap="round"/>')
            out.append(f'<path d="{d}" fill="none" stroke="{EMB}" stroke-width="5" stroke-linecap="round" pathLength="100" stroke-dasharray="62 100" filter="url(#glowline)"/>')
    # Pages drifting like birds toward the sun.
    for i in range(9):
        bx = sx + rnd.uniform(-w * .32, w * .22); by = sy + rnd.uniform(-h * .22, h * .12)
        s = rnd.uniform(5, 11)
        out.append(f'<path d="M{bx-s:.0f} {by:.0f} Q{bx-s/2:.0f} {by-s*.55:.0f} {bx:.0f} {by:.0f} Q{bx+s/2:.0f} {by-s*.55:.0f} {bx+s:.0f} {by:.0f}" fill="none" stroke="{VEL}" stroke-width="1.6" stroke-linecap="round" opacity="{rnd.uniform(.35,.7):.2f}"/>')
    out.append(f'<rect width="{w}" height="{h}" fill="url(#fade)"/>')
    ridges = ''.join(
        f'<linearGradient id="r{L}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{mix(PLUM, INK, .25 + .15*L)}"/><stop offset="1" stop-color="{mix(PLUM, INK, .55 + .09*L)}"/></linearGradient>'
        f'<linearGradient id="rim{L}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{VEL}" stop-opacity=".15"/><stop offset="{sx/w:.2f}" stop-color="{EMB}" stop-opacity=".9"/><stop offset="1" stop-color="{VEL}" stop-opacity=".15"/></linearGradient>'
        for L in range(layers))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<defs>
 <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1B1428"/><stop offset=".45" stop-color="{PLUM}"/><stop offset=".62" stop-color="#7A4A4E"/><stop offset=".72" stop-color="#3A2A45"/></linearGradient>
 <radialGradient id="halo"><stop offset="0" stop-color="#FFD9A0" stop-opacity=".55"/><stop offset=".25" stop-color="{EMB}" stop-opacity=".22"/><stop offset="1" stop-color="{EMB}" stop-opacity="0"/></radialGradient>
 <radialGradient id="spk" cx=".5" cy=".45" r=".6"><stop offset="0" stop-color="#FFF4E2"/><stop offset="1" stop-color="{EMB}"/></radialGradient>
 <filter id="bloom" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="3"/></filter>
 <filter id="glowline" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="1.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
 <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset=".7" stop-color="{INK}" stop-opacity="0"/><stop offset="1" stop-color="{INK}" stop-opacity=".85"/></linearGradient>
 {ridges}
</defs>
{''.join(out)}
</svg>'''

def mix(a, b, t):
    a = [int(a[i:i+2], 16) for i in (1, 3, 5)]; b = [int(b[i:i+2], 16) for i in (1, 3, 5)]
    return '#' + ''.join(f'{round(x + (y - x) * t):02x}' for x, y in zip(a, b))

out = B / 'hero'; out.mkdir(exist_ok=True)
(out / 'default-header-wide.svg').write_text(header(1600, 900, 3, (1060, 250)))
(out / 'default-header-tall.svg').write_text(header(900, 1600, 5, (520, 520)))
print('ok')

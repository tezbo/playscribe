"""Default Playscribe header art, used when a game has no art (wide 16:9 and tall 9:16).
Run from the repo root: python3 brand/tools/header.py, then render.mjs rasterises it."""
import json, random, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from gen import LEFT_PAGE, RIGHT_PAGE, SPARK, NOTE_LINES, NOTE_H, BAR, BAR_FILL
B = pathlib.Path(__file__).resolve().parent.parent
C = json.loads((B / 'tokens.json').read_text())['color']
INK, PLUM, VEL, EMB = C['ink']['900'], C['icon']['bgTop'], C['vellum']['100'], C['accent']['base']

def header(w, h, mark_scale, mark_xy, seed):
    rnd = random.Random(seed)
    # A field of faint patch-note lines, like the pages of a journal, drifting behind the mark.
    lines = []
    for row in range(0, h, 34):
        x = rnd.randint(-60, 40)
        while x < w:
            ln = rnd.choice([60, 90, 120, 160, 210])
            op = rnd.choice([.035, .05, .07])
            lines.append(f'<rect x="{x}" y="{row + 14}" width="{ln}" height="7" rx="3.5" fill="{VEL}" opacity="{op}"/>')
            x += ln + rnd.randint(18, 60)
    # Embers rising from the open book, and a few distant sparks.
    mx, my = mark_xy; k = mark_scale
    sparks = []
    for _ in range(46):
        x = rnd.gauss(mx, w * .16); y = rnd.uniform(0, my - 4 * k)
        r = rnd.choice([1.5, 2, 2.5, 3.5])
        sparks.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{EMB}" opacity="{rnd.uniform(.25,.8):.2f}"/>')
    for _ in range(9):
        sc = rnd.uniform(.22, .5); x = rnd.uniform(0, w); y = rnd.uniform(0, h * .55)
        sparks.append(f'<path d="{SPARK}" transform="translate({x:.0f} {y:.0f}) scale({sc:.2f}) translate(-32 -14)" fill="{EMB}" opacity="{rnd.uniform(.35,.7):.2f}"/>')
    # Light fanning up out of the spine.
    rays = []
    for ang in range(-58, 59, 9):
        rays.append(f'<path d="M0 0 L{-26} {-1600} L{26} {-1600} Z" transform="rotate({ang})" fill="url(#ray)" opacity="{.55 - abs(ang)/160:.2f}"/>')
    notes = ''.join(f'<rect x="{x}" y="{y}" width="{ww}" height="{NOTE_H}" rx="{NOTE_H/2}" fill="#5a4a3a" opacity=".28"/>' for x, y, ww in NOTE_LINES)
    bx, by, bw, bh = BAR
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="{PLUM}"/><stop offset="1" stop-color="#141019"/></linearGradient>
 <radialGradient id="glow" cx="{mx/w:.3f}" cy="{(my - 18*k)/h:.3f}" r="{.6 if w > h else .8}"><stop offset="0" stop-color="{EMB}" stop-opacity=".42"/><stop offset=".4" stop-color="{EMB}" stop-opacity=".1"/><stop offset="1" stop-color="{EMB}" stop-opacity="0"/></radialGradient>
 <linearGradient id="ray" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#FFE2B8" stop-opacity=".5"/><stop offset=".6" stop-color="{EMB}" stop-opacity="0"/></linearGradient>
 <radialGradient id="page" cx="32" cy="26" r="34" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFF8EA"/><stop offset=".55" stop-color="{VEL}" stop-opacity=".9"/><stop offset="1" stop-color="{C['vellum']['500']}" stop-opacity=".55"/></radialGradient>
 <radialGradient id="spk" cx=".5" cy=".45" r=".6"><stop offset="0" stop-color="#FFF1DC"/><stop offset="1" stop-color="{EMB}"/></radialGradient>
 <filter id="bloom" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="2.4"/></filter>
 <filter id="soft"><feGaussianBlur stdDeviation="{k*1.1:.0f}"/></filter>
 <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset=".62" stop-color="{INK}" stop-opacity="0"/><stop offset="1" stop-color="{INK}" stop-opacity=".9"/></linearGradient>
 <filter id="ember"><feGaussianBlur stdDeviation="1.2"/></filter>
</defs>
<rect width="{w}" height="{h}" fill="url(#bg)"/>
{''.join(lines)}
<rect width="{w}" height="{h}" fill="url(#glow)"/>
<g transform="translate({mx} {my - 26*k})" filter="url(#soft)">{''.join(rays)}</g>
<g filter="url(#ember)">{''.join(sparks)}</g>
<g transform="translate({mx} {my}) scale({k}) translate(-32 -32)">
 <path d="{LEFT_PAGE}" fill="#000" opacity=".35" transform="translate(0 2.5)" filter="url(#bloom)"/><path d="{RIGHT_PAGE}" fill="#000" opacity=".35" transform="translate(0 2.5)" filter="url(#bloom)"/>
 <path d="{LEFT_PAGE}" fill="url(#page)"/><path d="{RIGHT_PAGE}" fill="url(#page)"/>
 {notes}
 <rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="{bh/2}" fill="#5a4a3a" opacity=".22"/>
 <rect x="{bx}" y="{by}" width="{bw*BAR_FILL:.2f}" height="{bh}" rx="{bh/2}" fill="{EMB}"/>
 <path d="{SPARK}" fill="{EMB}" filter="url(#bloom)" transform="translate(32 14) scale(1.5) translate(-32 -14)" opacity=".75"/>
 <path d="{SPARK}" fill="url(#spk)"/>
</g>
<rect width="{w}" height="{h}" fill="url(#fade)"/>
</svg>'''

out = B / 'hero'; out.mkdir(exist_ok=True)
(out / 'default-header-wide.svg').write_text(header(1600, 900, 17, (1080, 610), 7))
(out / 'default-header-tall.svg').write_text(header(900, 1600, 15, (450, 900), 11))
print('ok')

"""Generates every Playscribe brand asset from one set of shapes and tokens.

Run from the repo root:  python3 brand/tools/gen.py && node brand/tools/render.mjs
Needs fonttools and uharfbuzz (pip install fonttools uharfbuzz). Text is outlined, so the SVGs
carry no font dependency.
"""
import json
import pathlib

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

BRAND = pathlib.Path(__file__).resolve().parent.parent
T = json.loads((BRAND / 'tokens.json').read_text())
C = T['color']

# ---------------------------------------------------------------------------------------------
# The mark, drawn on a 64-unit square. Two pages meet at the spine with a small gap (the hinge).
# A spark rises from the spine; its long lower point, slit and breather hole make it a pen nib.

LEFT_PAGE = ('M31.2 24C25.2 19.6 16.8 18.4 9.4 20.3Q7.6 20.8 7.6 22.7V49.9'
             'Q7.6 52.4 10 51.9C17.2 50.3 25 51.3 31.2 55.8Z')
RIGHT_PAGE = ('M32.8 24C38.8 19.6 47.2 18.4 54.6 20.3Q56.4 20.8 56.4 22.7V49.9'
              'Q56.4 52.4 54 51.9C46.8 50.3 39 51.3 32.8 55.8Z')
SPARK = ('M32 2.5C32.7 9.4 34.6 12 41 13.2C35 14.4 33.1 16.8 32 26.5'
         'C30.9 16.8 29 14.4 23 13.2C29.4 12 31.3 9.4 32 2.5Z')
# Cut into the spark: a breather hole and a slit running to the tip.
NIB_CUT = 'M32 14.6a1.25 1.25 0 1 1 0 2.5a1.25 1.25 0 1 1 0-2.5ZM31.55 17.6H32.45L32.12 23.4H31.88Z'


def gradient(id_, stops, x1=0, y1=0, x2=0, y2=1, units=None):
    u = f' gradientUnits="userSpaceOnUse"' if units else ''
    s = ''.join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"{u}>{s}</linearGradient>'


def mark_defs(p, tone='default'):
    """Gradients for the pages and spark. `p` prefixes ids so several marks can share a page."""
    if tone == 'mono':
        return ''
    pages = C['vellum']
    if tone == 'dark':
        pages = {k: v for k, v in C['vellumDim'].items()}
    return (gradient(f'{p}l', [(0, pages['300']), (1, pages['500'])], 0, 0, 1, 1)
            + gradient(f'{p}r', [(0, pages['100']), (1, pages['300'])], 1, 0, 0, 1)
            + gradient(f'{p}s', [(0, C['ember']['300']), (1, C['ember']['600'])], 0, 0, 0, 1))


def mark_body(p, tone='default', nib=True, parts=('left', 'right', 'spark'), mono_fill=None):
    fills = {
        'left': f'url(#{p}l)', 'right': f'url(#{p}r)', 'spark': f'url(#{p}s)',
    } if tone != 'mono' else {k: mono_fill or 'currentColor' for k in ('left', 'right', 'spark')}
    out = []
    if 'left' in parts:
        out.append(f'<path d="{LEFT_PAGE}" fill="{fills["left"]}"/>')
    if 'right' in parts:
        out.append(f'<path d="{RIGHT_PAGE}" fill="{fills["right"]}"/>')
    if 'spark' in parts:
        d = SPARK + (NIB_CUT if nib else '')
        out.append(f'<path d="{d}" fill="{fills["spark"]}" fill-rule="evenodd"/>')
    return ''.join(out)


def svg(w, h, body, defs='', view=None, extra=''):
    vb = view or f'0 0 {w} {h}'
    d = f'<defs>{defs}</defs>' if defs else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{vb}"{extra}>'
            f'{d}{body}</svg>\n')


# ---------------------------------------------------------------------------------------------
# Outlined text, shaped with HarfBuzz so kerning matches the font.

FONTS = BRAND / 'fonts'


class Face:
    def __init__(self, file):
        self.path = FONTS / file
        self.tt = TTFont(self.path)
        self.gs = self.tt.getGlyphSet()
        self.order = self.tt.getGlyphOrder()
        self.upem = self.tt['head'].unitsPerEm
        blob = hb.Blob.from_file_path(str(self.path))
        self.hb = hb.Font(hb.Face(blob))

    def shape(self, text):
        buf = hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        hb.shape(self.hb, buf, {'kern': True, 'liga': True})
        return [(self.order[i.codepoint], p.x_advance, p.x_offset, p.y_offset)
                for i, p in zip(buf.glyph_infos, buf.glyph_positions)]

    def bounds(self, glyph):
        bp = BoundsPen(self.gs)
        self.gs[glyph].draw(bp)
        return bp.bounds

    def run(self, text, size, x=0, y=0, tracking=0):
        """Returns (path data, advance width, [(glyph, x_left, advance)]) with baseline at y."""
        s = size / self.upem
        pen = SVGPathPen(self.gs, ntos=lambda v: f'{v:.2f}'.rstrip('0').rstrip('.'))
        cx, placed = 0, []
        for name, adv, xo, yo in self.shape(text):
            tp = TransformPen(pen, (s, 0, 0, -s, x + (cx + xo) * s, y - yo * s))
            self.gs[name].draw(tp)
            placed.append((name, x + cx * s, adv * s))
            cx += adv + tracking * self.upem
        return pen.getCommands(), cx * s - tracking * size, placed


DISPLAY = Face('Literata72pt-SemiBold.ttf')
SANS = Face('InstrumentSans-Medium.ttf')

WORD = 'Playscrıbe'  # dotless i: the spark is the tittle


def wordmark(size, x, y, ink, p, tone='default', tracking=-0.012):
    """'Playscribe' with a spark for the dot of the i. Returns (svg body, width, i-centre)."""
    d, w, placed = DISPLAY.run(WORD, size, x, y, tracking)
    name, ix, iadv = next(g for g in placed if g[0] in ('dotlessi', 'uni0131', 'idotless'))
    b = DISPLAY.bounds(name)
    s = size / DISPLAY.upem
    icx = ix + (b[0] + b[2]) / 2 * s
    # Sit the spark where the tittle would be, a touch larger so it reads as the spark.
    ib = DISPLAY.bounds('i')
    dot_cy = y - ((b[3] + ib[3]) / 2 + 12) * s
    k = size * 0.27 / 24  # spark units → px; the spark is ~24 units tall
    sx, sy = icx - 32 * k, dot_cy - 14.5 * k
    fill = f'url(#{p}s)' if tone != 'mono' else ink
    spark = (f'<path transform="translate({sx:.2f} {sy:.2f}) scale({k:.4f})" d="{SPARK}" '
             f'fill="{fill}"/>')
    return f'<path d="{d}" fill="{ink}"/>' + spark, w, (icx, dot_cy)


def word_defs(p, tone='default'):
    return '' if tone == 'mono' else gradient(f'{p}s', [(0, C['ember']['300']), (1, C['ember']['600'])], 0, 0, 0, 1)


def text(face, s, size, x, y, fill, anchor='start', tracking=0):
    d, w, _ = face.run(s, size, 0, 0, tracking)
    dx = {'start': 0, 'middle': -w / 2, 'end': -w}[anchor]
    return f'<path transform="translate({x + dx:.2f} {y:.2f})" d="{d}" fill="{fill}"/>', w


# ---------------------------------------------------------------------------------------------

def write(rel, content):
    f = BRAND / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(content)


def logos():
    for tone, name in (('default', 'mark'), ('dark', 'mark-dim')):
        write(f'logo/{name}.svg', svg(64, 64, mark_body('m', tone), mark_defs('m', tone)))
    write('logo/mark-small.svg', svg(64, 64, mark_body('m', nib=False), mark_defs('m')))
    write('logo/mark-mono.svg', svg(64, 64, mark_body('m', 'mono', mono_fill='#000')))

    for tone, ink, name in (('default', C['vellum']['100'], 'wordmark-on-dark'),
                            ('default', C['ink']['900'], 'wordmark-on-light'),
                            ('mono', '#000', 'wordmark-mono')):
        body, w, _ = wordmark(96, 0, 96, ink, 'w', tone)
        W = round(w + 4)
        write(f'logo/{name}.svg', svg(W, 124, body, word_defs('w', tone)))

    # Horizontal lockup: mark, then the wordmark, sharing a baseline-ish centre.
    for tone, ink, name in (('default', C['vellum']['100'], 'lockup-on-dark'),
                            ('default', C['ink']['900'], 'lockup-on-light')):
        m = f'<g transform="translate(0 10) scale(1.6)">{mark_body("l", tone)}</g>'
        body, w, _ = wordmark(84, 128, 96, ink, 'l', tone)
        write(f'logo/{name}.svg', svg(round(128 + w + 4), 124, m + body, mark_defs('l', tone)))


ICON = 1024
ICON_SCALE = 12.6
ICON_OFFSET = (ICON / 2 - 32 * ICON_SCALE, ICON / 2 - 29.6 * ICON_SCALE)


def icon_group(inner):
    ox, oy = ICON_OFFSET
    return f'<g transform="translate({ox:.1f} {oy:.1f}) scale({ICON_SCALE})">{inner}</g>'


def icon_bg(id_, tone):
    stops = {'default': [(0, C['icon']['bgTop']), (1, C['icon']['bgBottom'])],
             'dark': [(0, C['icon']['darkTop']), (1, C['icon']['darkBottom'])]}[tone]
    return gradient(id_, stops), f'<rect width="{ICON}" height="{ICON}" fill="url(#{id_})"/>'


def app_icon():
    # Icon Composer layers: full-canvas, unmasked, no background (set the gradient in Icon Composer).
    # Folders become groups: back to front.
    write('app-icon/layers/1-pages/1-left-page.svg',
          svg(ICON, ICON, icon_group(mark_body('i', parts=('left',))), mark_defs('i')))
    write('app-icon/layers/1-pages/2-right-page.svg',
          svg(ICON, ICON, icon_group(mark_body('i', parts=('right',))), mark_defs('i')))
    write('app-icon/layers/2-spark/1-spark.svg',
          svg(ICON, ICON, icon_group(mark_body('i', parts=('spark',))), mark_defs('i')))

    # Flattened sources for the asset catalog fallback and for previews (render.mjs makes PNGs).
    gd, bg = icon_bg('bg', 'default')
    write('app-icon/flat/AppIcon-default.svg', svg(ICON, ICON, bg + icon_group(mark_body('i')), gd + mark_defs('i')))
    # Dark: transparent background, as Apple asks for asset catalogs; pages dimmed.
    write('app-icon/flat/AppIcon-dark.svg', svg(ICON, ICON, icon_group(mark_body('i', 'dark')), mark_defs('i', 'dark')))
    # Dark preview on its own background, for the board only.
    gd2, bg2 = icon_bg('bg', 'dark')
    write('app-icon/flat/preview-dark.svg', svg(ICON, ICON, bg2 + icon_group(mark_body('i', 'dark')), gd2 + mark_defs('i', 'dark')))
    # Tinted: grayscale on black. Pages light grey, spark white so it stays the brightest point.
    tinted = (f'<rect width="{ICON}" height="{ICON}" fill="#000"/>'
              + icon_group(f'<path d="{LEFT_PAGE}" fill="#9a9a9a"/><path d="{RIGHT_PAGE}" fill="#c4c4c4"/>'
                           f'<path d="{SPARK + NIB_CUT}" fill="#fff" fill-rule="evenodd"/>'))
    write('app-icon/flat/AppIcon-tinted.svg', svg(ICON, ICON, tinted))


def splash_and_cover():
    """Reference compositions for each posture, in points (iPhone Duo sizes from the prototype)."""
    ink, paper, tag = C['ink']['900'], C['vellum']['100'], C['text']['secondary']
    tagline = T['voice']['tagline']

    def stacked(w, h, msize, wsize, cy, p):
        m = (f'<g transform="translate({w / 2 - 32 * msize / 64:.1f} {cy - msize * 0.75:.1f}) '
             f'scale({msize / 64:.4f})">{mark_body(p)}</g>')
        body, ww, _ = wordmark(wsize, 0, 0, paper, p)
        wm = f'<g transform="translate({w / 2 - ww / 2:.1f} {cy + msize * 0.25 + wsize * 0.9:.1f})">{body}</g>'
        t, _ = text(SANS, tagline, wsize * 0.32, w / 2, cy + msize * 0.25 + wsize * 1.55, tag, 'middle')
        return m + wm + t

    bg = f'<rect width="100%" height="100%" fill="{ink}"/>'

    # Closed (outer display, portrait).
    W, H = 393, 852
    write('splash/closed.svg', svg(W, H, bg + stacked(W, H, 120, 46, H * 0.44, 'c'), mark_defs('c')))

    # Book: inner display held like a book, fold vertical. "Play" | "scribe" across the hinge.
    W, H = 1024, 820
    hx = W / 2
    ms = 210
    left = (f'<g transform="translate({hx - ms / 2 - 16:.1f} {H * 0.27:.1f}) scale({ms / 64:.4f})">'
            f'{mark_body("b", parts=("left",))}</g>')
    right = (f'<g transform="translate({hx - ms / 2 + 16:.1f} {H * 0.27:.1f}) scale({ms / 64:.4f})">'
             f'{mark_body("b", parts=("right",))}</g>')
    # Nothing crosses the hinge: the spark moves to the i of "scribe" on the right page.
    size = 92
    dP, wP, _ = DISPLAY.run('Play', size, 0, 0, -0.012)
    body_s, wS, _ = wordmark(size, 0, 0, paper, 'b')
    # Drop "Play" from the wordmark body: draw "scribe" with the spark i on the right page.
    d_s, w_s, placed = DISPLAY.run('scrıbe', size, 0, 0, -0.012)
    name, ix, _ = next(g for g in placed if g[0] in ('dotlessi', 'uni0131', 'idotless'))
    b = DISPLAY.bounds(name); ib = DISPLAY.bounds('i'); s = size / DISPLAY.upem
    icx = ix + (b[0] + b[2]) / 2 * s
    dot_cy = -((b[3] + ib[3]) / 2 + 12) * s
    k = size * 0.27 / 24
    gap = 30
    by = H * 0.27 + ms * 0.95 + size
    words = (f'<path transform="translate({hx - gap - wP:.1f} {by:.1f})" d="{dP}" fill="{paper}"/>'
             f'<g transform="translate({hx + gap:.1f} {by:.1f})"><path d="{d_s}" fill="{paper}"/>'
             f'<path transform="translate({icx - 32 * k:.2f} {dot_cy - 14.5 * k:.2f}) scale({k:.4f})" d="{SPARK}" fill="url(#bs)"/></g>')
    # The tagline sits under "Play" on the left page, which balances the wider "scribe".
    t, _ = text(SANS, tagline, 22, hx - gap, by + 46, tag, 'end')
    write('splash/book.svg', svg(W, H, bg + left + right + words + t, mark_defs('b')))

    # Tabletop: fold horizontal; mark in the upper half, name and tagline in the lower half.
    W, H = 820, 1024
    fy = H / 2
    ms = 200
    m = (f'<g transform="translate({W / 2 - ms / 2:.1f} {fy - ms * 0.98:.1f}) scale({ms / 64:.4f})">'
         f'{mark_body("t")}</g>')
    body, ww, _ = wordmark(88, 0, 0, paper, 't')
    wm = f'<g transform="translate({W / 2 - ww / 2:.1f} {fy + 150:.1f})">{body}</g>'
    t, _ = text(SANS, tagline, 26, W / 2, fy + 204, tag, 'middle')
    write('splash/tabletop.svg', svg(W, H, bg + m + wm + t, mark_defs('t')))

    # Flat open.
    W, H = 1024, 820
    write('splash/flat.svg', svg(W, H, bg + stacked(W, H, 190, 84, H * 0.42, 'f'), mark_defs('f')))

    # Outer-cover brand bug: a glass capsule at the bottom-leading corner (camera is top-right).
    # Rest state = mark only. On wake it opens to show the wordmark for 2 s, then closes.
    for state in ('rest', 'open'):
        h = 40
        m = f'<g transform="translate(8 6) scale({28 / 64:.4f})">{mark_body("g", nib=False)}</g>'
        if state == 'open':
            body, ww, _ = wordmark(20, 0, 0, paper, 'g')
            w = 8 + 28 + 8 + ww + 14
            inner = m + f'<g transform="translate(44 27)">{body}</g>'
        else:
            w, inner = 44, m
        cap = (f'<rect x=".5" y=".5" width="{w - 1:.1f}" height="{h - 1}" rx="{(h - 1) / 2}" '
               f'fill="{C["glass"]["fill"]}" stroke="{C["glass"]["stroke"]}"/>')
        write(f'cover/bug-{state}.svg', svg(round(w), h, cap + inner, mark_defs('g')))


def css():
    lines = [':root {']
    def emit(prefix, obj):
        for k, v in obj.items():
            if isinstance(v, dict):
                emit(f'{prefix}-{k}', v)
            else:
                lines.append(f'  --ps{prefix}-{k}: {v};')
    emit('', {k: v for k, v in C.items()})
    lines.append(f"  --ps-font-display: 'Literata', 'Iowan Old Style', Georgia, serif;")
    lines.append(f"  --ps-font-text: 'Instrument Sans', ui-sans-serif, system-ui, -apple-system, sans-serif;")
    lines.append('}')
    write('web/brand.css', '\n'.join(lines) + '\n')


def swift():
    def rgb(hexv):
        h = hexv.lstrip('#')
        r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
        return f'Color(red: {r:.3f}, green: {g:.3f}, blue: {b:.3f})'
    cols = []
    for group in ('ink', 'vellum', 'ember'):
        for k, v in C[group].items():
            cols.append(f'    static let {group}{k} = {rgb(v)}')
    for k, v in C['text'].items():
        cols.append(f'    static let text{k[0].upper() + k[1:]} = {rgb(v)}')
    cols.append(f'    /// Interactive elements and unread state only.')
    cols.append(f'    static let accent = {rgb(C["accent"]["base"])}')
    cols.append(f'    static let accentPressed = {rgb(C["accent"]["pressed"])}')
    cols.append(f'    /// Text and glyphs on any `accent` fill. Never white on accent (1.8:1); this is 9.5:1.')
    cols.append(f'    static let onAccent = {rgb(C["accent"]["on"])}')
    styles = []
    for name, spec in T['type']['ios'].items():
        styles.append(f'    static let {name} = Font.custom("{spec["font"]}", size: {spec["size"]}, relativeTo: .{spec["relativeTo"]})')
    src = (BRAND / 'tools' / 'PlayscribeBrand.swift.tmpl').read_text()
    src = src.replace('{{COLORS}}', '\n'.join(cols)).replace('{{FONTS}}', '\n'.join(styles))
    write('ios/PlayscribeBrand.swift', src)


if __name__ == '__main__':
    logos()
    app_icon()
    splash_and_cover()
    css()
    swift()
    print('ok')

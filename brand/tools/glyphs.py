"""Playscribe UI glyphs on a 24 pt grid, weight-matched to SF Symbols Regular (1.6 pt strokes).

swap-sides: two facing pages from the Playscribe mark, with an arc above that trades them across
the spine. Used for "Swap sides" on iPhone Duo (moves the reading page to the other half).
Run: python3 brand/tools/glyphs.py
"""
import json
import math
import pathlib

BRAND = pathlib.Path(__file__).resolve().parent.parent
C = json.loads((BRAND / 'tokens.json').read_text())['color']
OUT = BRAND / 'ios' / 'symbols'
SW = 1.6  # stroke width at 24 pt, close to SF Symbols Regular

LEFT = 'M11 11.2C9 9.9 6.3 9.6 3.6 10.1V20.2C6.3 19.7 9 20 11 21.3Z'
RIGHT = 'M13 11.2C15 9.9 17.7 9.6 20.4 10.1V20.2C17.7 19.7 15 20 13 21.3Z'
ARC_A, ARC_C, ARC_B = (6.4, 7.6), (12, 1.4), (17.6, 7.6)


def head(tip, ctrl, size=2.6, spread=math.radians(38)):
    """Open arrowhead at `tip`, pointing along the curve's end tangent (from `ctrl`)."""
    ang = math.atan2(tip[1] - ctrl[1], tip[0] - ctrl[0])
    pts = [(tip[0] - size * math.cos(ang + s), tip[1] - size * math.sin(ang + s)) for s in (spread, -spread)]
    return f'M{pts[0][0]:.2f} {pts[0][1]:.2f}L{tip[0]} {tip[1]}L{pts[1][0]:.2f} {pts[1][1]:.2f}'


ARC = f'M{ARC_A[0]} {ARC_A[1]}Q{ARC_C[0]} {ARC_C[1]} {ARC_B[0]} {ARC_B[1]}'
HEADS = head(ARC_B, ARC_C) + head(ARC_A, ARC_C)
STROKE = f'fill="none" stroke="currentColor" stroke-width="{SW}" stroke-linecap="round" stroke-linejoin="round"'


def glyph(fill_pages=False, color='currentColor'):
    pages = (f'<path d="{LEFT} {RIGHT}" fill="{color}" stroke="{color}" stroke-width="{SW}" stroke-linejoin="round"/>'
             if fill_pages else f'<path d="{LEFT} {RIGHT}" {STROKE.replace("currentColor", color)}/>')
    return pages + f'<path d="{ARC}{HEADS}" {STROKE.replace("currentColor", color)}/>'


def svg(body, size=24, view='0 0 24 24'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{view}">{body}</svg>\n'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'swap-sides.svg').write_text(svg(glyph()))
    (OUT / 'swap-sides.fill.svg').write_text(svg(glyph(fill_pages=True)))
    # Ember button: 30 pt circle in accent, glyph at 17 pt in accent.on (never white on ember).
    k = 17 / 24
    off = (30 - 17) / 2
    body = (f'<circle cx="15" cy="15" r="15" fill="{C["accent"]["base"]}"/>'
            f'<g transform="translate({off} {off}) scale({k:.4f})">{glyph(color=C["accent"]["on"])}</g>')
    (OUT / 'swap-sides-button-ember.svg').write_text(svg(body, 30, '0 0 30 30'))
    body = (f'<circle cx="15" cy="15" r="15" fill="{C["ink"]["700"]}"/>'
            f'<g transform="translate({off} {off}) scale({k:.4f})">{glyph(color=C["text"]["primary"])}</g>')
    (OUT / 'swap-sides-button.svg').write_text(svg(body, 30, '0 0 30 30'))
    print('ok')


if __name__ == '__main__':
    main()

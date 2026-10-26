"""Playscribe UI glyphs on a 24 pt grid, weight-matched to SF Symbols Regular (1.6 pt strokes).

swap-sides: two facing pages from the Playscribe mark with the reading page filled. Used for "Swap sides"
on iPhone Duo (moves the reading page to the other half); the fill follows the reading side.
Run: python3 brand/tools/glyphs.py
"""
import json
import pathlib

BRAND = pathlib.Path(__file__).resolve().parent.parent
C = json.loads((BRAND / 'tokens.json').read_text())['color']
OUT = BRAND / 'ios' / 'symbols'
SW = 1.6  # stroke width at 24 pt, close to SF Symbols Regular
STROKE = f'fill="none" stroke="currentColor" stroke-width="{SW}" stroke-linecap="round" stroke-linejoin="round"'


def svg(body, size=24, view='0 0 24 24'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{view}">{body}</svg>\n'


# Chosen by Terry (2026-10-26): the book with the reading page filled, no arrows. The filled page
# shows which half you read on, and it moves to the other page when tapped.
BIG_L = 'M11 6.4C8.8 4.9 5.6 4.5 2.6 5.1V18.6C5.6 18 8.8 18.4 11 19.9Z'
BIG_R = 'M13 6.4C15.2 4.9 18.4 4.5 21.4 5.1V18.6C18.4 18 15.2 18.4 13 19.9Z'


def swap(side='left', color='currentColor'):
    filled, empty = (BIG_L, BIG_R) if side == 'left' else (BIG_R, BIG_L)
    return (f'<path d="{filled}" fill="{color}" stroke="{color}" stroke-width="{SW}" stroke-linejoin="round"/>'
            f'<path d="{empty}" {STROKE.replace("currentColor", color)}/>')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    k, off = 17 / 24, (30 - 17) / 2
    for side in ('left', 'right'):
        (OUT / f'swap-sides.{side}.svg').write_text(svg(swap(side)))
        # 30 pt buttons with the glyph at 17 pt: ink with vellum, or ember with accent.on (never white).
        for tone, bg, fg in (('', C['ink']['700'], C['text']['primary']), ('-ember', C['accent']['base'], C['accent']['on'])):
            body = (f'<circle cx="15" cy="15" r="15" fill="{bg}"/>'
                    f'<g transform="translate({off} {off}) scale({k:.4f})">{swap(side, fg)}</g>')
            (OUT / f'swap-sides-button{tone}.{side}.svg').write_text(svg(body, 30, '0 0 30 30'))
    print('ok')


if __name__ == '__main__':
    main()

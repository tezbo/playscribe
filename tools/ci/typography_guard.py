#!/usr/bin/env python3
"""Typography guard (Terry, 13 Nov 2026): the middle dot "·" is never a separator, and user-facing text uses curly apostrophes.

Fails (exit 1) when:
  1. a Swift file under ios/ or docs/ux-acceptance.md has the middle dot (literal or \\u{00B7} / \\u{B7}); or
  2. app Swift (ios/Playscribe, ios/PlayscribeWidget, ios/Shared) has a straight apostrophe between letters inside a string literal
     ("We'll", "What's", "players' notes"), or around an interpolation ('\\(query)').
  3. app Swift shows a game title straight from `<x>.name` in `Text(...)` / `WholeWordText(text: ...)` without `.gluingTrailingNumeral`
     (a title ending in a numeral such as "Deliverance II" must not wrap the numeral onto its own line).
A line carrying `dot-ok` (rule 1) or `apos-ok` (rule 2) is skipped: use it only where the character is not shown to a person
(for example stripping a pasted bullet from imported text).
`dot-ok` is only for code that strips a dot or asserts that a dot is absent (a test `#expect(!s.contains("·"))`); never for shown text.
`title-ok` skips rule 3 where a name is not a game title (a person, a brand, a platform). Comments are skipped for rule 2. Run from the repo root.
"""
import pathlib, re, sys

DOT = re.compile(r"·|\\u\{0*b7\}", re.I)
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
APOS = re.compile(r"(?<=[A-Za-z0-9\)])'(?=[a-z])|(?<=s)'(?=[ \".,:;!?]|$)|'\\\([A-Za-z.]+\)'")
TITLE = re.compile(r'(?:Text|WholeWordText)\((?:text: )?(?!Brand\.)[A-Za-z0-9_.?$]*\.name(?:\)|,)')
problems = []

for p in sorted(pathlib.Path('ios').rglob('*.swift')) + [pathlib.Path('docs/ux-acceptance.md')]:
    if not p.exists():
        continue
    for i, line in enumerate(p.read_text(encoding='utf8').split('\n'), 1):
        if DOT.search(line) and 'dot-ok' not in line:
            problems.append(f'{p}:{i}: middle dot separator: {line.strip()[:110]}')

for root in ('ios/Playscribe', 'ios/PlayscribeWidget', 'ios/Shared'):
    for p in sorted(pathlib.Path(root).rglob('*.swift')):
        for i, line in enumerate(p.read_text(encoding='utf8').split('\n'), 1):
            if line.lstrip().startswith('//') or 'apos-ok' in line or 'player.' in line:
                continue
            if TITLE.search(line) and 'title-ok' not in line:
                problems.append(f"{p}:{i}: game title without .gluingTrailingNumeral (or add // title-ok): {line.strip()[:90]}")
            for m in LIT.finditer(line):
                if APOS.search(m.group(1)):
                    problems.append(f"{p}:{i}: straight apostrophe in text, use ’: {m.group(1)[:90]}")

for q in problems:
    print(f'::error::{q}' if len(sys.argv) > 1 and sys.argv[1] == '--gha' else q)
print(f'typography guard: {len(problems)} problems')
sys.exit(1 if problems else 0)

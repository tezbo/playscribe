#!/usr/bin/env python3
"""Compare two folders of harness stills (main's and a PR's) and list the screens that changed.

Usage: screen_diff.py <before-dir> <after-dir> <out-dir> [--base-sha SHA] [--head-sha SHA] [--image-url PREFIX] [--run-url URL]

Both folders come from HarnessStillsTests with HARNESS_STABLE=1: <screen>-<pose>-<size>.png plus <file>-frames.txt.
Pass bar (Quinn and Iris, 12 Nov 2026, card qa-screen-diffs-on-prs):
  - a pixel differs when any channel differs by more than 2 of 255 (antialias noise stays below that);
  - a screen changed when any 48 x 48 px tile has more than 30 differing pixels, or more than 0.02% of all pixels differ;
  - a screen also changed when its tappable-frames text differs (a clipped word or a lost chip moves a frame);
  - a screen only on one side is listed as new or gone.
Unchanged does not mean signed: release gates stay Mac stills of the exact SHA (Quinn).
Writes to <out-dir>: comment.md (the PR comment), summary.json, and for each changed screen <name>.png (before | after | diff).
Needs Pillow.
"""
import argparse
import difflib
import json
import os
import sys

from PIL import Image, ImageChops, ImageDraw

CHANNEL_TOLERANCE = 2      # out of 255
TILE = 48                  # px (the stills are 1 px per pt)
TILE_PIXELS = 30           # differing pixels in one tile that make it a change
OVERALL_FRACTION = 0.0002  # 0.02% of the image
MARKER = "<!-- screen-diffs -->"
MAC_STILL_LIST = ("real hinge position, Tabletop system rail and toolbar, sheets and sheet bottoms, navigation bar collapse, "
                  "status bar, video, scroll-edge fades, Reduce Motion states, light and dark switching, any frame claim about "
                  "the hinge band (455-495) or the Tabletop fold (374-414), a game page's unread state (Mark N read, unread dot), anything "
                  "that depends on remote art or the live feed, and every release gate")


def stills(folder):
    return {f[:-4] for f in os.listdir(folder) if f.endswith(".png")} if os.path.isdir(folder) else set()


def read_text(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().splitlines()
    except OSError:
        return None


def compare_pixels(a, b):
    """Returns (changed, fraction, hot_tiles, mask) for two RGBA images. Different sizes always count as changed."""
    if a.size != b.size:
        return True, 1.0, [], None
    diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    # A pixel differs when its largest channel difference is over the tolerance.
    r, g, bl = diff.split()
    biggest = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    mask = biggest.point(lambda v: 255 if v > CHANNEL_TOLERANCE else 0)
    w, h = mask.size
    total = mask.histogram()[255]
    fraction = total / float(w * h)
    hot = []
    if total:
        for ty in range(0, h, TILE):
            for tx in range(0, w, TILE):
                box = (tx, ty, min(tx + TILE, w), min(ty + TILE, h))
                n = mask.crop(box).histogram()[255]
                if n > TILE_PIXELS:
                    hot.append(box)
    changed = bool(hot) or fraction > OVERALL_FRACTION
    return changed, fraction, hot, mask


def panel(before, after, mask, hot, out_path):
    """before | after | diff side by side (stacked for landscape stills), at full size so AX5 text stays readable."""
    diff = after.convert("L").convert("RGB").point(lambda v: v // 3)
    if mask is not None:
        magenta = Image.new("RGB", after.size, (255, 0, 200))
        diff.paste(magenta, (0, 0), mask)
    draw = ImageDraw.Draw(diff)
    for box in hot:
        draw.rectangle((box[0], box[1], box[2] - 1, box[3] - 1), outline=(255, 60, 60), width=2)
    images = [before.convert("RGB"), after.convert("RGB"), diff]
    gap, label_h = 12, 22
    landscape = after.width > after.height
    w = max(i.width for i in images)
    h = max(i.height for i in images)
    size = (w, (h + label_h) * 3 + gap * 2) if landscape else (w * 3 + gap * 2, h + label_h)
    sheet = Image.new("RGB", size, (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    for i, (img, name) in enumerate(zip(images, ["before (main)", "after (this PR)", "diff (magenta = changed)"])):
        x, y = (0, i * (h + label_h + gap)) if landscape else (i * (w + gap), 0)
        d.text((x + 4, y + 4), name, fill=(230, 230, 230))
        sheet.paste(img, (x, y + label_h))
    sheet.save(out_path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("out")
    ap.add_argument("--base-sha", default="?")
    ap.add_argument("--head-sha", default="?")
    ap.add_argument("--image-url", default="", help="URL prefix the comment uses for <out>/<name>.png")
    ap.add_argument("--run-url", default="")
    ap.add_argument("--note", action="append", default=[], help="extra line for the comment (repeatable)")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    before, after = stills(args.before), stills(args.after)
    # One side with no stills means that side failed to build or render (Quinn, #485): say so instead of listing every screen
    # as new or gone.
    empty = [side for side, s in (("before", before), ("after", after)) if not s]
    if empty and (before or after):
        side = empty[0]
        lines = [MARKER, f"### Screen diffs: the {side} render produced no stills", "",
                 f"Main `{args.base_sha}` (before) against this PR `{args.head_sha}` (after). The {side} side wrote no stills, usually "
                 "because it did not build, so nothing was compared. Check the iOS and Precheck results and the run log."]
        lines += [f"_{n}_" for n in args.note]
        if args.run_url:
            lines.append(f"Run log: [screen diffs run]({args.run_url}).")
        lines += ["", "---", "_Generated by the Screen diffs workflow (.github/workflows/screen-diffs.yml)_"]
        with open(os.path.join(args.out, "comment.md"), "w") as fh:
            fh.write("\n".join(lines) + "\n")
        with open(os.path.join(args.out, "summary.json"), "w") as fh:
            json.dump({"base": args.base_sha, "head": args.head_sha, "empty": side}, fh, indent=1)
        print(f"SCREENS {side} render produced no stills")
        return 0
    rows, changed = [], []
    for name in sorted(before | after):
        if name not in after:
            rows.append({"name": name, "status": "gone"}); changed.append(name); continue
        if name not in before:
            rows.append({"name": name, "status": "new"}); changed.append(name)
            Image.open(os.path.join(args.after, name + ".png")).convert("RGB").save(os.path.join(args.out, name + ".png"))
            continue
        a = Image.open(os.path.join(args.before, name + ".png"))
        b = Image.open(os.path.join(args.after, name + ".png"))
        px_changed, fraction, hot, mask = compare_pixels(a, b)
        fa = read_text(os.path.join(args.before, name + "-frames.txt")) or []
        fb = read_text(os.path.join(args.after, name + "-frames.txt")) or []
        frame_lines = [l for l in difflib.unified_diff(fa, fb, lineterm="", n=0) if l[:1] in "+-" and l[:3] not in ("+++", "---")]
        row = {"name": name, "status": "changed" if (px_changed or frame_lines) else "same", "fraction": round(fraction, 6),
               "tiles": len(hot), "size": f"{a.width}x{a.height}" if a.size == b.size else f"{a.width}x{a.height} -> {b.width}x{b.height}",
               "frames": frame_lines}
        rows.append(row)
        if row["status"] == "changed":
            changed.append(name)
            panel(a, b, mask, hot, os.path.join(args.out, name + ".png"))

    with open(os.path.join(args.out, "summary.json"), "w") as fh:
        json.dump({"base": args.base_sha, "head": args.head_sha, "total": len(rows), "changed": changed, "rows": rows}, fh, indent=1)

    lines = [MARKER, f"### Screen diffs: {len(changed)} of {len(rows)} screens changed", ""]
    lines.append(f"Main `{args.base_sha}` (before) against this PR `{args.head_sha}` (after), both rendered by the fold harness in this run "
                 "with no network and motion off. Advisory: unchanged does not mean signed.")
    lines += [f"_{n}_" for n in args.note]
    if not rows:
        lines += ["", "No stills were written on either side. See the run log."]
    elif not changed:
        lines += ["", "Nothing changed on any screen in the matrix."]
    else:
        lines += ["", "| Screen | Change | Pixels | Tiles | Frames |", "|---|---|---|---|---|"]
        for r in rows:
            if r["status"] == "same":
                continue
            if r["status"] in ("new", "gone"):
                lines.append(f"| `{r['name']}` | {r['status']} | | | |")
            else:
                lines.append(f"| `{r['name']}` | changed | {r['fraction'] * 100:.3f}% | {r['tiles']} | {len(r['frames'])} lines |")
        for r in rows:
            if r["status"] in ("same", "gone"):
                continue
            lines += ["", f"#### `{r['name']}`" + (" (new screen)" if r["status"] == "new" else "")]
            if args.image_url:
                lines.append(f"[![{r['name']}]({args.image_url}/{r['name']}.png)]({args.image_url}/{r['name']}.png)")
            if r.get("frames"):
                shown = r["frames"][:40]
                lines += ["<details><summary>Tappable frames that moved</summary>", "", "```diff", *shown]
                if len(r["frames"]) > 40:
                    lines.append(f"... {len(r['frames']) - 40} more lines in the artifact")
                lines += ["```", "</details>"]
    lines += ["", f"Still needs a Mac still: {MAC_STILL_LIST}."]
    if args.run_url:
        lines.append(f"Full stills and frame dumps: [run artifacts]({args.run_url}).")
    lines += ["", "---", "_Generated by the Screen diffs workflow (.github/workflows/screen-diffs.yml)_"]
    with open(os.path.join(args.out, "comment.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"SCREENS {len(changed)} of {len(rows)} changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

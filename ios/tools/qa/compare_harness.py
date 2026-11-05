#!/usr/bin/env python3
"""Calibration: diff the fold harness against the simulator, pose by pose.

    # 1. harness (any Mac or CI runner):  TEST_RUNNER_HARNESS_DUMP_DIR=/tmp/h xcodebuild test -scheme Playscribe … -only-testing:PlayscribeTests
    # 2. simulator, per pose (gate.sh already runs UI tests in each pose):  run PoseProbeTests, keep the log
    # 3. compare_harness.py /tmp/h <pose>=<ui-test-log> …     e.g.  book=/tmp/gate/book.log tabletop=/tmp/gate/tabletop.log

A pose is CALIBRATED when the container, safe area, fold and occlusions are equal and every tappable frame matches
within 1 pt. Anything else prints the differences, which are the numbers to put into PoseCatalog.swift."""
import json, re, sys, pathlib

TOL = 1.0
ALIASES = {"closed": "closed", "closedLandscape": "closedLandscape", "open": "open", "openPortrait": "openPortrait", "book": "book", "tabletop": "tabletop"}

def load_probe(log):
    last = None
    for line in pathlib.Path(log).read_text(errors="replace").splitlines():
        m = re.search(r"POSEPROBE (\{.*\})", line)
        if m: last = json.loads(m.group(1))
    if last is None: sys.exit(f"{log}: no POSEPROBE line")
    return last

def close(a, b): return len(a) == len(b) and all(abs(x - y) <= TOL for x, y in zip(a, b))

def diff(h, s):
    out = []
    for k in ("size", "safeArea"):
        if not close(h[k], s[k]): out.append(f"{k}: harness {h[k]} sim {s[k]}")
    if (h.get("division") is None) != (s.get("division") is None) or (h.get("division") and not close(h["division"], s["division"])):
        out.append(f"division: harness {h.get('division')} sim {s.get('division')}")
    if len(h["occlusions"]) != len(s["occlusions"]) or any(not close(a, b) for a, b in zip(h["occlusions"], s["occlusions"])):
        out.append(f"occlusions: harness {h['occlusions']} sim {s['occlusions']}")
    # The harness reports frames relative to the safe-area origin (rules are written against it); the simulator probe reports
    # them in the container's own coordinates. Add the origin back so both sides are in the same space.
    top, lead = h["safeArea"][0], h["safeArea"][1]
    def shift(f): return [f[0] + lead, f[1] + top, f[2], f[3]]
    hf, sf = [shift(f) for f in h["frames"]], list(s["frames"])
    for f in sf:
        m = next((g for g in hf if close(f, g)), None)
        if m: hf.remove(m)
        else: out.append(f"sim-only tappable frame {f}")
    out += [f"harness-only tappable frame {g}" for g in hf]
    for name in sorted(set(h["named"]) | set(s["named"])):
        a, b = h["named"].get(name), s["named"].get(name)
        if a is not None: a = shift(a)
        if a is None or b is None or not close(a, b): out.append(f"named {name}: harness {a} sim {b}")
    return out

harness_dir = pathlib.Path(sys.argv[1]); bad = 0
for arg in sys.argv[2:]:
    pose, log = arg.split("=", 1)
    h = json.loads((harness_dir / f"{pose}.json").read_text()); s = load_probe(log)
    d = diff(h, s)
    print(f"{pose}: {'CALIBRATED' if not d else 'DIFFERS'}")
    for line in d[:20]: print("   ", line)
    bad += bool(d)
sys.exit(1 if bad else 0)

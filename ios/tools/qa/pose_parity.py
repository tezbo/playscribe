#!/usr/bin/env python3
"""PP-1 pose parity: compare PoseParityTests dumps of one game across poses.

Usage: pose_parity.py DUMP [DUMP ...]   (each file: ITEM lines from one pose; the pose= field names it)
Fails (exit 1) when a pose lacks an item another pose has: absent, or not reachable (Tabletop: not in the lower half).
Same-game dumps only: run it once per game (A tracked with notes, B tracked with no notes, C untracked).
"""
import re, sys
from collections import defaultdict

STATE = re.compile(r"STATE tracked=(true|false) pose=(\S+)")
LINE = re.compile(r"ITEM (\S+) present=(true|false) reachable=(true|false) half=(\S+) pose=(\S+)")

def main(paths):
    poses = defaultdict(dict)  # pose -> item -> reachable
    states = {}  # pose -> tracked
    for p in paths:
        for line in open(p, encoding="utf-8"):
            st = STATE.search(line)
            if st: states[st.group(2)] = st.group(1)
            m = LINE.search(line)
            if m:
                item, present, reachable, half, pose = m.groups()
                poses[pose][item] = (reachable == "true", half)
    if len(poses) < 2:
        print("need dumps from at least two poses"); return 2
    if len(set(states.values())) > 1:
        print(f"FAIL state: the game is tracked in some poses and not others: {states}"); return 1
    items = sorted({i for d in poses.values() for i in d})
    bad = 0
    for item in items:
        have = [p for p, d in poses.items() if d.get(item, (False, ""))[0]]
        if have and len(have) != len(poses):
            lacking = [f"{p}{' (upper half only)' if poses[p].get(item, (0, ''))[1] == 'upper' else ''}" for p in poses if p not in have]
            print(f"FAIL {item}: reachable in {', '.join(sorted(have))}; not in {', '.join(sorted(lacking))}")
            bad += 1
    if not bad:
        print(f"OK: {len(items)} items, {len(poses)} poses ({', '.join(sorted(poses))})")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

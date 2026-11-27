#!/bin/bash
# bug-r12-close-38pt (G-7): every "Close" button in the given sim-use trees is at least 44 x 44 pt.
# Usage: check-close-target.sh TREE.txt ...   Exit 1 on any smaller Close or a tree with none.
bad=0
for f in "$@"; do
  sizes=$(grep -E 'Button +"Close"' "$f" | grep -oE '[0-9]+x[0-9]+\)' | tr -d ')')
  if [ -z "$sizes" ]; then echo "FAIL $(basename "$f"): no Close button"; bad=1; continue; fi
  for s in $sizes; do
    w=${s%x*}; h=${s#*x}
    if [ "$w" -lt 44 ] || [ "$h" -lt 44 ]; then echo "FAIL $(basename "$f"): Close is ${w}x${h}"; bad=1
    else echo "ok $(basename "$f"): Close ${w}x${h}"; fi
  done
done
exit $bad

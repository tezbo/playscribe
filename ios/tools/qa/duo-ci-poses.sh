#!/usr/bin/env bash
# Real-hinge pose shoot on a booted iPhone Duo simulator (hosted runner or any Mac). Needs sim-use
# (brew install lycorp-jp/tap/sim-use). No Device Hub, no Mac GUI.
#   ios/tools/qa/duo-ci-poses.sh UDID OUTDIR ROUTE RUNS "STEPS" [extra launch args...]
#   STEPS: "angle:orientation ..." e.g. "0 180 90:landscape-left". orientation = portrait|landscape-left|landscape-right|pud
# Files: <sha>-<run>-<NN>-a<angle>-<orientation>-<display>-{shot.png,ui.txt,displays.txt}; manifest.tsv records
# requested vs observed (active display, image pixel size) so label/size mismatches are visible.
set -uo pipefail
UDID=$1; OUT=$2; ROUTE=$3; RUNS=$4; STEPS=$5; shift 5
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nosha); B=co.codeconnectors.playscribe
mkdir -p "$OUT"; printf 'file\trequested_angle\trequested_orientation\tactive_display\thinge_read\tpx_w\tpx_h\n' > "$OUT/manifest.tsv"
for r in $(seq 1 "$RUNS"); do
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; sim-use ios fold closed --device "$UDID" >/dev/null 2>&1; sleep 3
  xcrun simctl launch "$UDID" $B -qaRoute "$ROUTE" -qaOverlay YES "$@" >/dev/null; sleep 8; n=0
  for s in $STEPS; do
    n=$((n+1)); ang=${s%%:*}; ori=${s#*:}; [ "$ori" = "$s" ] && ori=portrait
    sim-use ios fold "$ang" --device "$UDID" >/dev/null 2>&1; sim-use ios rotate "$ori" --device "$UDID" >/dev/null 2>&1; sleep 5
    j=$(sim-use ios fold --json --device "$UDID" 2>/dev/null)
    disp=$(echo "$j" | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];print(d["posture"]["activeDisplay"]["id"],d.get("hingeAngle",""))' 2>/dev/null || echo "? ?")
    did=${disp% *}; hing=${disp#* }; [ "$did" = 3 ] && dn=inner || dn=outer
    f="$OUT/$SHA-r$r-$(printf %02d $n)-a$ang-$ori-$dn"
    xcrun simctl io "$UDID" screenshot --display=$did "$f-shot.png" >/dev/null 2>&1
    sim-use ui --device "$UDID" > "$f-ui.txt" 2>&1
    xcrun devicectl device info displays --device "$UDID" 2>&1 | grep -E 'LCD|active|currentOrientation|bounds' > "$f-displays.txt"
    wh=$(python3 -c 'import struct,sys;b=open(sys.argv[1],"rb").read(24);print(*struct.unpack(">II",b[16:24]))' "$f-shot.png" 2>/dev/null || echo "0 0")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(basename "$f")" "$ang" "$ori" "$dn" "$hing" "${wh// /\t}" >> "$OUT/manifest.tsv"
  done
done

#!/usr/bin/env bash
# Quinn's five cloud runs on a booted, app-installed iPhone Duo (hosted runner or Mac). Needs sim-use.
#   ios/tools/qa/duo-ci-scenarios.sh UDID OUTDIR [scenario ...]    (default: all)   scenarios: listplace noart headerart continuity trailer closedax5 schemes video axchips deckwide plusend switchax switchtt rails heroswipe herolong removemenu lane fullscreen blocked fsxctest
# Every step saves <sha>-<scenario>-<step>-<display>-shot.png and -ui.txt (outline with frames, ids and the pose line).
set -uo pipefail
UDID=$1; OUT=$2; shift 2; FAILED=""; SCEN=${*:-continuity trailer closedax5 schemes video}
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nosha); B=co.codeconnectors.playscribe; mkdir -p "$OUT"
AX5=UICTContentSizeCategoryAccessibilityXXXL
# Rotate first, fold second, then check the active display matches the angle (inner for any open angle, outer for 0); redo once if not.
fold() {
  for try in 1 2 3; do
    sim-use ios rotate "${2:-portrait}" --device "$UDID" >/dev/null 2>&1; sim-use ios fold "$1" --device "$UDID" >/dev/null 2>&1; sleep 5
    local d o; read -r d o <<<"$(sim-use ios fold --json --device "$UDID" 2>/dev/null | python3 -c 'import json,sys;a=json.load(sys.stdin)["data"]["posture"]["activeDisplay"];print(a["id"],a["orientation"])' 2>/dev/null || echo "1 ?")"
    # inner display must also report the requested orientation (portrait above 0 deg is Tabletop below 140, landscape is Book)
    { [ "$1" = 0 ] && [ "$d" = 1 ]; } || { [ "$1" != 0 ] && [ "$d" = 3 ] && [ "$o" = "${2:-portrait}" ]; } && return 0
    echo "fold $1 ${2:-portrait}: display $d orientation $o is wrong, retry $try"
  done; }
did() { sim-use ios fold --json --device "$UDID" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["posture"]["activeDisplay"]["id"])' 2>/dev/null || echo 1; }
# Swipe until two consecutive outlines are identical (page cannot scroll further), up to 20 swipes; logs the final qa offset.
scroll_end() { # fromX,fromY toX,toY label
  local prev="" cur i
  for i in $(seq 1 20); do
    sim-use swipe --from "$1" --to "$2" --duration 0.5 --device "$UDID" >/dev/null 2>&1; sleep 1
    cur=$(sim-use ui --device "$UDID" 2>&1 | grep -v 'poseProbe' | md5sum)
    [ "$cur" = "$prev" ] && break; prev=$cur
  done
  echo "scroll end ($3): $i swipes; $(sim-use ui --device "$UDID" 2>&1 | grep -o 'qa-page[^"]*' | head -1)"; }
# qa-page offset and the first three visible rows (id and label) after each step, for position-loss checks (row 8).
state() { echo "state $1: $(sim-use ui --device "$UDID" 2>/dev/null | grep -o 'qa-page: [^"]*' | head -1) | first rows: $(sim-use ui --device "$UDID" 2>/dev/null | grep -E '^ +@[0-9]+ +(Button|Cell|StaticText|Heading) ' | grep -vE 'qa-|poseProbe|foldAudit|libraryDuo' | head -3 | cut -c1-90 | tr '\n' ';')"; }
snap() { # scenario step
  local d; d=$(did); local n; [ "$d" = 3 ] && n=inner || n=outer
  local f="$OUT/$SHA-$1-$2-$n"
  xcrun simctl io "$UDID" screenshot --display=$d "$f-shot.png" >/dev/null 2>&1
  sim-use ui --device "$UDID" > "$f-ui.txt" 2>&1; echo "$f: $(head -1 "$f-ui.txt" | cut -c1-80) | $(grep -o 'pose: [a-z]*[^"]*' "$f-ui.txt" | head -1)"; }
launch() { xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 0 portrait; xcrun simctl launch "$UDID" $B "$@" >/dev/null; sleep 8; }
# R-7 rails (Terry 26 Nov): shoot a sideways rail at rest, then swiped sideways. $1 = step name, $2 = egrep on the outline line that names the rail's first
# element (its #id or label); the rail's frame comes from that line, "(x,y WxH)". Left-swipe starts near the right edge of the element's row.
rail() {
  local f; f=$(sim-use ui --device "$UDID" 2>/dev/null | grep -E "$2" | head -1)
  local box; box=$(echo "$f" | grep -o '([0-9.]*,[0-9.]* [0-9.]*x[0-9.]*)' | tail -1 | tr -d '()x,' )
  echo "rail $1: element line: $f"
  snap rails "$1-rest"
  local x y w h; read -r x y w h <<<"$(echo "$f" | grep -o '([0-9.]*,[0-9.]* [0-9.]*x[0-9.]*)' | tail -1 | tr -d '()' | tr ',x' '  ')"
  [ -n "${x:-}" ] || { echo "rail $1: element not found"; return; }
  local cy; cy=$(python3 -c "print(int($y+$h/2))")
  sim-use swipe --from 330,$cy --to 40,$cy --duration 0.5 --device "$UDID" >/dev/null 2>&1; sleep 2
  snap rails "$1-scrolled"
}
for s in $SCEN; do echo "##### $s"; case $s in
continuity) # row 8: open game scrolled mid-update, fold 0, 90, 180, 120, 0
  launch -qaRoute gamepage/dawnwalker -qaOverlay YES
  sim-use swipe --from 233,520 --to 233,220 --duration 0.6 --device "$UDID" >/dev/null 2>&1; sleep 2
  echo "scroll check: $(sim-use ui --device "$UDID" 2>/dev/null | grep -o "qa-page: [^\"]*" | head -1)"; snap continuity 1-closed-scrolled
  fold 90 landscape-left; snap continuity 2-a90-landscape; fold 180 landscape-left; snap continuity 3-a180
  fold 120 portrait; snap continuity 4-a120-portrait; fold 0 portrait; snap continuity 5-closed-again ;;
trailer) # row 3: reflection element + 3 taps in the upper half, portrait Tabletop
  launch -qaRoute trailer/dQw4w9WgXcQ/dawnwalker -qaOverlay YES
  fold 90 portrait; snap trailer 1-tabletop-before
  for y in 60 200 330; do sim-use tap -x 335 -y $y --device "$UDID" >/dev/null 2>&1; sleep 1; done
  snap trailer 2-tabletop-after-3-upper-taps ;;
closedax5) # row 1: Closed outer landscape at AX5
  launch -qaRoute library/playing -qaOrientation landscape -qaOverlay YES -UIPreferredContentSizeCategoryName $AX5
  snap closedax5 1-closed-landscape-ax5
  scroll_end 339,380 339,60 landscape; snap closedax5 1b-closed-landscape-ax5-scrolled-end
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; snap closedax5 2-closed-portrait-ax5
  scroll_end 233,560 233,120 portrait; snap closedax5 2b-closed-portrait-ax5-scrolled-end ;;
continuity3) # row 8 repeat x3: scrolled Closed, fold flat, fold closed; position logged each step
  for run in 1 2 3; do
    launch -qaRoute gamepage/dawnwalker -qaOverlay YES
    sim-use swipe --from 233,520 --to 233,220 --duration 0.6 --device "$UDID" >/dev/null 2>&1; sleep 2; state "run$run closed-scrolled"
    fold 180 portrait; state "run$run flat"; snap continuity3 run$run-flat
    fold 0 portrait; state "run$run closed-again"; snap continuity3 run$run-closed-again
  done ;;
portraitfold) # row 8 variant: Closed portrait scrolled, open 180 portrait, close 0 portrait; no Tabletop step, no landscape
  launch -qaRoute gamepage/dawnwalker -qaOverlay YES
  sim-use swipe --from 233,520 --to 233,220 --duration 0.6 --device "$UDID" >/dev/null 2>&1; sleep 2; state closed-scrolled; snap portraitfold 1-closed-scrolled
  fold 180 portrait; state open-180-portrait; snap portraitfold 2-open-180-portrait
  fold 0 portrait; state closed-again; snap portraitfold 3-closed-again ;;
ax5landscape) # row 1 repeat: alternate swipe origin, then try to reach "Turn on alerts" by label; trees before and after
  launch -qaRoute library/playing -qaOrientation landscape -qaOverlay YES -UIPreferredContentSizeCategoryName $AX5
  snap ax5landscape 1-before
  for i in 1 2 3 4 5 6; do sim-use swipe --from 300,380 --to 300,100 --duration 0.5 --device "$UDID" >/dev/null 2>&1; done; sleep 2
  snap ax5landscape 2-after-6-swipes
  echo "tap by label: $(sim-use tap --label "Turn on alerts" --device "$UDID" 2>&1 | head -3)"; sleep 2
  snap ax5landscape 3-after-label-tap
  for i in 1 2 3 4 5 6; do sim-use swipe --from 300,100 --to 300,380 --duration 0.5 --device "$UDID" >/dev/null 2>&1; done; sleep 2
  snap ax5landscape 4-scrolled-back-up-to-alerts-card ;;
alertscard) # row 1: Closed landscape AX5, scroll by element until "Turn on alerts" and "Not now" are whole on screen, then shoot
  launch -qaRoute library/playing -qaOrientation landscape -qaOverlay YES -UIPreferredContentSizeCategoryName $AX5
  snap alertscard 1-before
  H=$(sim-use ui --device "$UDID" 2>/dev/null | head -1 | sed -E 's/.* ([0-9]+)x([0-9]+) .*/\2/')
  for i in $(seq 1 25); do
    ui=$(sim-use ui --device "$UDID" 2>/dev/null)
    verdict=$(echo "$ui" | python3 -c '
import re,sys
H=int(sys.argv[1]); t=sys.stdin.read(); r={}
for n in ("Turn on alerts","Not now"):
    m=re.search(r"Button  \""+n+r"\".*?\((-?\d+),(-?\d+) (\d+)x(\d+)\)",t)
    r[n]=(int(m.group(2)),int(m.group(2))+int(m.group(4))) if m else None
if all(r.values()) and all(a>=0 and b<=H for a,b in r.values()): print("whole")
elif any(v and v[0]<0 for v in r.values()): print("up")
else: print("down")' "${H:-466}")
    echo "alertscard step $i: $verdict (window ${H:-466})"
    [ "$verdict" = whole ] && break
    if [ "$verdict" = up ]; then sim-use swipe --from 300,100 --to 300,300 --duration 0.5 --device "$UDID" >/dev/null 2>&1
    else sim-use swipe --from 300,300 --to 300,150 --duration 0.5 --device "$UDID" >/dev/null 2>&1; fi; sleep 1
  done
  snap alertscard 2-alerts-card; echo "$ui" | grep -E "Turn on alerts|Not now" ;;
tt) # Tabletop/Open shots with an assertion: TT_ROUTE, TT_STEPS ("angle:orientation ..."), TT_AX5 (yes|no); pose line and tree per step
  extra=(); [ "${TT_AX5:-no}" = yes ] && extra=(-UIPreferredContentSizeCategoryName $AX5)
  launch -qaRoute "${TT_ROUTE:-library/playing}" -qaOverlay YES "${extra[@]}"
  for st in ${TT_STEPS:-90:portrait}; do
    a=${st%%:*}; o=${st#*:}; fold "$a" "$o"
    snap tt "a$a-$o-$([ "${TT_AX5:-no}" = yes ] && echo ax5 || echo std)-first"
    if [ "$o" = portrait ]; then scroll_end 300,900 300,520 "a$a-$o"; else scroll_end 300,560 300,200 "a$a-$o"; fi; snap tt "a$a-$o-$([ "${TT_AX5:-no}" = yes ] && echo ax5 || echo std)-end"
  done ;;
removemenu) # s-06-remove-row-ax5-wrap + r060-version-chip-spoken: the game's status menu open (Remove row) at AX5 in Closed portrait, Closed landscape and Tabletop; the deck outline carries the spoken chip label
  tapRail() { local f x y w h; f=$(sim-use ui --device "$UDID" 2>/dev/null | grep "#rail.$1" | head -1 | grep -o '([0-9.,]* [0-9.x]*)' | tr -d '()'); [ -z "$f" ] && { echo "no #rail.$1"; return 1; }
    x=${f%%,*}; y=${f#*,}; y=${y%% *}; w=${f#* }; w=${w%x*}; h=${f##*x}
    sim-use tap -x $((${x%.*} + ${w%.*} / 2)) -y $((${y%.*} + ${h%.*} / 2)) --device "$UDID" >/dev/null 2>&1; sleep 2; }
  launch -qaRoute two-update -UIPreferredContentSizeCategoryName $AX5; snap removemenu 0-deck-chips-closed-portrait-AX5
  launch -qaRoute gamepage/dawnwalker -qaOrientation portrait -UIPreferredContentSizeCategoryName $AX5; tapRail status; snap removemenu 1-closed-portrait-AX5
  sim-use swipe --from 200,500 --to 200,200 --device "$UDID" >/dev/null 2>&1; sleep 2; snap removemenu 1b-closed-portrait-AX5-scrolled-to-remove
  launch -qaRoute gamepage/dawnwalker -qaOrientation landscape -UIPreferredContentSizeCategoryName $AX5; tapRail status; snap removemenu 2-closed-landscape-AX5
  launch -qaRoute gamepage/dawnwalker -qaOrientation portrait -UIPreferredContentSizeCategoryName $AX5; fold 90 portrait; tapRail status; snap removemenu 3-tabletop-AX5 ;;
lane) # AX/VoiceOver lane (0.6.0): LANE_ROUTES (space list of -qaRoute values), each at AX5 in Closed portrait, Closed landscape and Tabletop;
  # first screen then scrolled to the end, so a baseline on main and the PR share one matrix. LANE_AX (AX5|std) picks the text size.
  size=$AX5; [ "${LANE_AX:-AX5}" = std ] && size=UICTContentSizeCategoryL
  for r in ${LANE_ROUTES:-library/playing}; do n=$(echo "$r" | tr '/' '_')
    launch -qaRoute "$r" -qaOrientation portrait -UIPreferredContentSizeCategoryName $size; snap lane "$n-1-closed-portrait"
    [ "${LANE_SCROLL:-no}" = yes ] && { scroll_end 233,560 233,120 portrait; snap lane "$n-1b-closed-portrait-end"; }
    launch -qaRoute "$r" -qaOrientation landscape -UIPreferredContentSizeCategoryName $size; snap lane "$n-2-closed-landscape"
    [ "${LANE_SCROLL:-no}" = yes ] && { scroll_end 339,380 339,60 landscape; snap lane "$n-2b-closed-landscape-end"; }
    launch -qaRoute "$r" -qaOrientation portrait -UIPreferredContentSizeCategoryName $size; fold 90 portrait; snap lane "$n-3-tabletop"
    [ "${LANE_SCROLL:-no}" = yes ] && { scroll_end 300,900 300,520 tabletop; snap lane "$n-3b-tabletop-end"; }
  done ;;
axchips) # bug-closed-landscape-ax5-no-games + r060-filter-pills-grid-ax5: overlay off, first screen then scrolled (chips in view)
  for ax in AX3:UICTContentSizeCategoryAccessibilityL AX5:$AX5; do n=${ax%%:*}; c=${ax#*:}
    launch -qaRoute library/playing -qaOrientation landscape -UIPreferredContentSizeCategoryName $c
    snap axchips 1-closed-landscape-$n
    sim-use swipe --from 233,450 --to 233,150 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 2-closed-landscape-$n-scrolled
    sim-use swipe --from 233,450 --to 233,150 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 2b-closed-landscape-$n-scrolled-more
    for k in $(seq 1 16); do sim-use swipe --from 233,450 --to 233,100 --device "$UDID" >/dev/null 2>&1; sleep 1
      [ $((k % 3)) = 0 ] && snap axchips 2c-closed-landscape-$n-swipe$k; done
    sleep 1; snap axchips 2c-closed-landscape-$n-end
  done
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; snap axchips 3-closed-portrait-AX5
  sim-use swipe --from 233,560 --to 233,160 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 4-closed-portrait-AX5-scrolled
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; fold 90 portrait; snap axchips 5-tabletop-AX5
  sim-use swipe --from 335,880 --to 335,560 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 6-tabletop-AX5-scrolled ;;
deckwide) # bug-deck-card-closed-landscape-ax5-dots-order: the deck card in Closed landscape std/AX3/AX5 and Closed portrait AX5
  for ax in std:UICTContentSizeCategoryL AX3:UICTContentSizeCategoryAccessibilityL AX5:$AX5; do n=${ax%%:*}; c=${ax#*:}
    launch -qaRoute library/playing -qaOrientation landscape -UIPreferredContentSizeCategoryName $c
    snap deckwide 1-closed-landscape-$n
    for k in 1 2 3 4 5 6 7 8; do sim-use swipe --from 233,300 --to 233,100 --device "$UDID" >/dev/null 2>&1; sleep 1
      [ $((k % 2)) = 0 ] && snap deckwide 2-closed-landscape-$n-swipe$k; done
  done
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; snap deckwide 3-closed-portrait-AX5 ;;
herolong) # r054-closed-ax5-hero-headline-4-lines: the longest Dawnwalker headline leads the deck, at rest, in Closed portrait, Closed landscape and Tabletop at AX5 (then Closed portrait std)
  for ax in AX5:$AX5 std:UICTContentSizeCategoryL; do n=${ax%%:*}; c=${ax#*:}
    launch -qaRoute long-hero/dawnwalker -qaOrientation portrait -UIPreferredContentSizeCategoryName $c; snap herolong 1-closed-portrait-$n
    [ "$n" = AX5 ] || continue
    launch -qaRoute long-hero/dawnwalker -qaOrientation landscape -UIPreferredContentSizeCategoryName $c; snap herolong 2-closed-landscape-$n
    for k in 1 2 3 4; do sim-use swipe --from 339,380 --to 339,150 --duration 0.5 --device "$UDID" >/dev/null 2>&1; sleep 2; snap herolong 2$k-closed-landscape-$n-scrolled$k; done
    launch -qaRoute long-hero/dawnwalker -qaOrientation portrait -UIPreferredContentSizeCategoryName $c; fold 90 portrait; snap herolong 3-tabletop-$n
  done ;;
heroswipe) # r054-closed-ax5-hero-headline-4-lines: every hero card in Closed portrait, AX5 then std (J-5d); horizontal swipes on the deck
  for ax in AX5:$AX5 std:UICTContentSizeCategoryL; do n=${ax%%:*}; c=${ax#*:}
    launch -qaRoute ${HERO_ROUTE:-many-updates} -qaOrientation portrait -UIPreferredContentSizeCategoryName $c
    snap heroswipe 0-closed-portrait-$n
    for k in 1 2 3 4 5; do sim-use swipe --from 340,280 --to 40,280 --duration 0.5 --device "$UDID" >/dev/null 2>&1; sleep 2; snap heroswipe $k-closed-portrait-$n; done
  done ;;
switchax) # bug-playing-upcoming-switch-ax5-small: switch + filter chips, each state, light and dark; Closed landscape AX5; Tabletop AX5
  for ap in light dark; do for t in playing upcoming; do
    launch -qaRoute library/$t -qaAppearance $ap -UIPreferredContentSizeCategoryName UICTContentSizeCategoryL; snap switchax 1-closed-portrait-std-$ap-$t
    launch -qaRoute library/$t -qaAppearance $ap -UIPreferredContentSizeCategoryName $AX5; snap switchax 2-closed-portrait-AX5-$ap-$t
    if [ $t = playing ]; then for k in 1 2 3; do sim-use swipe --from 233,560 --to 233,160 --device "$UDID" >/dev/null 2>&1; sleep 1; done
      sleep 1; snap switchax 2b-closed-portrait-AX5-$ap-chips; fi
  done; done
  for t in playing upcoming; do
    launch -qaRoute library/$t -qaOrientation landscape -UIPreferredContentSizeCategoryName $AX5; snap switchax 3-closed-landscape-AX5-$t
    launch -qaRoute library/$t -UIPreferredContentSizeCategoryName $AX5; fold 90 portrait; snap switchax 4-tabletop-AX5-$t
    sim-use swipe --from 335,880 --to 335,620 --device "$UDID" >/dev/null 2>&1; sleep 2; snap switchax 4b-tabletop-AX5-$t-scrolled
  done
  # A real tap on the chip (Closed portrait AX5): Playing, then Upcoming by label.
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5
  echo "tap Upcoming: $(sim-use tap --label "Upcoming" --device "$UDID" 2>&1 | head -2)"; sleep 2; snap switchax 5-closed-portrait-AX5-tapped-upcoming ;;
unfoldupdate) # bug-075: an update open in Closed stays the update through Open portrait, Book, Tabletop and back (J-1, pose parity)
  launch -qaRoute release/dawnwalker/dawnwalker@1.1; snap unfoldupdate 1-closed
  fold 180 portrait; sleep 3; snap unfoldupdate 2-open-portrait
  fold 90 landscape-left; sleep 3; snap unfoldupdate 3-book
  fold 120 portrait; sleep 3; snap unfoldupdate 4-tabletop
  fold 0 portrait; sleep 3; snap unfoldupdate 5-closed-again ;;
unfoldupdate2) # bug-075 other doors: scrolled mid-update, and an update opened from the Updates tab
  launch -qaRoute release/dawnwalker/dawnwalker@1.1; sim-use swipe --from 233,560 --to 233,160 --duration 0.6 --device "$UDID" >/dev/null 2>&1; sleep 2; snap unfoldupdate2 1a-closed-scrolled
  fold 180 portrait; sleep 3; snap unfoldupdate2 1b-open-portrait
  fold 90 landscape-left; sleep 3; snap unfoldupdate2 1c-book
  launch -qaRoute two-update/updates; sleep 2; snap unfoldupdate2 2a-updates-tab
  row=$(sim-use ui --device "$UDID" 2>/dev/null | grep -E "Button .*(Out on PS5|New)" | head -1 | python3 -c 'import re,sys;m=re.search(r"\(([0-9.]+),([0-9.]+) ([0-9.]+)x([0-9.]+)\)",sys.stdin.read());print("%d,%d"%(float(m[1])+float(m[3])/2,float(m[2])+float(m[4])/2)) if m else None' 2>/dev/null); echo "row tap: $row"
  [ -n "$row" ] && [ "$row" != None ] && sim-use tap -x ${row%,*} -y ${row#*,} --device "$UDID" >/dev/null 2>&1; sleep 3; snap unfoldupdate2 2b-updates-opened
  fold 180 portrait; sleep 3; snap unfoldupdate2 2c-open-portrait
  fold 90 landscape-left; sleep 3; snap unfoldupdate2 2d-book
  fold 180 portrait; sleep 3; snap unfoldupdate2 2e-open-portrait-again
  fold 0 portrait; sleep 3; snap unfoldupdate2 2f-closed-again ;;
rails) # R-7: the four sideways rails, at rest (trailing fade only) and scrolled (leading fade too)
  launch -qaRoute gamepage/dawnwalker; scroll_end 233,560 233,160 similar; rail 1-youmightalsolike '#similarGame'
  launch -qaRoute fill-library/12 -UIPreferredContentSizeCategoryName UICTContentSizeCategoryL; rail 2-library-chips 'Button +"All '
  launch -qaRoute first-run; sim-use tap --label "Skip for now" --device "$UDID" >/dev/null 2>&1; sleep 3; rail 3-firstrun-popular '#popularAdd'   # the empty Library's Popular on PS5 row (sized to the tiles that fit, so it should fade nowhere)
  launch -qaRoute fill-library/12; fold 120 portrait; sleep 3; rail 4-tabletop-chips 'Button +"All '
  sim-use tap --label "Search" --device "$UDID" >/dev/null 2>&1; sleep 3; rail 5-tabletop-letters '#letter-A' ;;
switchtt) # bug-playing-upcoming-switch-ax5-small: real Tabletop at AX5. Tries portrait-first then fold, and fold-then-portrait, at hinge angles 90 120 60 130 until the app reports "pose: tabletop"
  for t in playing upcoming; do
    launch -qaRoute library/$t -UIPreferredContentSizeCategoryName $AX5; got=no
    for ord in rotate-first fold-first; do for ang in 90 120 60 130; do
      if [ $ord = rotate-first ]; then sim-use ios rotate portrait --device "$UDID" >/dev/null 2>&1; sleep 3; sim-use ios fold $ang --device "$UDID" >/dev/null 2>&1; sleep 5
      else sim-use ios fold $ang --device "$UDID" >/dev/null 2>&1; sleep 4; sim-use ios rotate portrait --device "$UDID" >/dev/null 2>&1; sleep 4; fi
      pl=$(sim-use ui --device "$UDID" 2>/dev/null | grep -o "pose: [a-z]*" | head -1); echo "switchtt $t $ord $ang: $pl"
      [ "$pl" = "pose: tabletop" ] && { got=yes; break 2; }
    done; done
    echo "switchtt $t: tabletop reached: $got"
    snap switchtt 4-tabletop-AX5-$t
    sim-use swipe --from 335,880 --to 335,620 --device "$UDID" >/dev/null 2>&1; sleep 2; snap switchtt 4b-tabletop-AX5-$t-scrolled
  done ;;
plusend) # bug-psplus-card-missing-cover-empty-grid + r060-psplus-compact-ax3: the end of the Library (PS Plus card) in every pose, std and AX5.
  # Each step logs the element type of every PS Plus title in the outline: each must be a Button (never a bare text element).
  # Rotation is set again after each fold (a fold can reset it), and the page is swiped until the last PS Plus title is in the
  # outline, then twice more to the end (an unchanged outline after one swipe is not the end: run 45541589244 stopped early).
  # Swipes start clear of the tiles, rail and the bottom edge (run 45546236061: Tabletop from y 900 and Open landscape AX5 from
  # the middle of the page never scrolled).
  pose() { sim-use ios fold "$1" --device "$UDID" >/dev/null 2>&1; sleep 4; sim-use ios rotate "$2" --device "$UDID" >/dev/null 2>&1; sleep 4; }
  to_plus() { # fromX,fromY toX,toY label
    local i k
    for i in $(seq 1 25); do
      sim-use ui --device "$UDID" 2>/dev/null | grep -q 'Monster Train 2' && { for k in 1 2; do sim-use swipe --from "$1" --to "$2" --duration 0.3 --device "$UDID" >/dev/null 2>&1; sleep 1; done; break; }
      sim-use swipe --from "$1" --to "$2" --duration 0.3 --device "$UDID" >/dev/null 2>&1; sleep 1
    done; echo "to plus ($3): $i swipes; $(sim-use ui --device "$UDID" 2>/dev/null | head -1)"; }
  plus() { snap plusend "$1"; echo "plus titles $1: $(grep -E 'Tomb Raider|Dead Island|Monster Train' "$OUT/$SHA-plusend-$1-$( [ "$(did)" = 3 ] && echo inner || echo outer)-ui.txt" | sed -E 's/^ *@[0-9]+ +//' | cut -c1-70 | tr '\n' ';')"; }
  for ax in std:UICTContentSizeCategoryL AX5:$AX5; do n=${ax%%:*}; c=${ax#*:}
    launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $c; pose 0 portrait
    to_plus 300,600 300,150 closed-portrait; plus $n-1-closed-portrait
    launch -qaRoute library/playing -qaOrientation landscape -UIPreferredContentSizeCategoryName $c
    to_plus 400,400 400,80 closed-landscape; plus $n-2-closed-landscape
    launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $c
    pose 180 landscape-left; to_plus 200,560 200,140 open-landscape; plus $n-3-open-landscape
    pose 90 landscape-left; to_plus 700,600 700,120 book; plus $n-4-book
    pose 90 portrait; to_plus 450,800 450,520 tabletop; plus $n-5-tabletop
    pose 180 portrait; to_plus 500,850 500,150 open-portrait; plus $n-6-open-portrait
  done ;;
schemes) # dark and light for the pose set
  for ap in dark light; do
    launch -qaRoute library/playing -qaAppearance $ap -qaOverlay YES
    snap schemes $ap-1-closed; fold 180 landscape-left; snap schemes $ap-2-flat-landscape
    fold 90 landscape-left; snap schemes $ap-3-book; fold 90 portrait; snap schemes $ap-4-tabletop; fold 180 portrait; snap schemes $ap-5-flat-portrait
  done ;;
fullscreen) # bug-071: full-screen video Fit with our controls in the bands; the WebView frame in each -ui.txt is the picture.
  # Our controls hide 3 s after the last touch while playing, so each pose is shot within 1 s of entering, then hidden.
  frames() { echo "frames $1: $(sim-use ui --device "$UDID" 2>/dev/null | grep -E 'qaFullScreen|qaBands|qaVideoTime|qaVideoState|WebView|Show player controls|mirrorAudit|videoExitFullScreen|videoPlayPause|videoScrubber|videoBack10|videoForward10' | cut -c1-140 | tr '\n' ';')"; }
  tapl() { echo "tap $1: $(sim-use tap --label "$1" --device "$UDID" 2>&1 | head -1)"; sleep "${2:-4}"; }
  enter() { tapl "Full screen" 1; snap fullscreen "$1-entered"; frames "$1"; }
  # -qaHideAfter 20: the controls still auto-hide, but after 20 s, as sim-use took up to 12.5 s between two taps (run 46096007450).
  launch -qaRoute trailer/dQw4w9WgXcQ/dawnwalker -qaOverlay YES -qaVideoTime YES -qaHideAfter 20
  tapl Play 8; snap fullscreen 1-closed-portrait-inline; frames 1
  enter 2-closed-portrait
  sleep 3; frames 2b-still-playing
  sleep 20; snap fullscreen 3-controls-hidden; frames 3
  # bug-073 (Terry, beta 6: in Closed a band tap never brought the controls back; in Open it did): a picture tap after the turn,
  # in the middle of the screen, which is on the picture in either coordinate reading. wakes counts it.
  echo "picture tap: $(sim-use tap -x 339 -y 233 --device "$UDID" 2>&1 | head -1)"; t4=$(sim-use ui --device "$UDID" 2>/dev/null); snap fullscreen 4p-picture-tap
  # bug-073: the picture tap brought the controls back with Exit, in Closed after the turn (read at once: they hide in 3 s); fails the job.
  echo "frames 4p: $(echo "$t4" | grep -E 'qaBands|videoExitFullScreen' | cut -c1-140 | tr '\n' ';')"
  if echo "$t4" | grep -q 'shown=1' && echo "$t4" | grep -q '#videoExitFullScreen'; then echo "ok picture tap shows Exit"
  else echo "FAIL picture tap"; FAILED="$FAILED fullscreen-picture-tap"; fi
  sleep 22
  # Which coordinate space sim-use taps in after the turn is not known, so the band is tapped in both readings.
  echo "band tap: $(sim-use tap -x 339 -y 12 --device "$UDID" 2>&1 | head -1)"; sleep 0.5; frames 4a
  echo "band tap (portrait reading): $(sim-use tap -x 12 -y 339 --device "$UDID" 2>&1 | head -1)"; sleep 0.5; frames 4b
  snap fullscreen 4-band-tap-shows
  # The device stays portrait while the app has turned its scene (as on a phone with rotation lock), and sim-use taps in the
  # device's portrait space. Which way the scene is turned there is not settled (the band tap at 12,339 in run 46050038868 fits
  # both), so Exit is tried at each reading: a landscape point (x, y) is (466 - y, x) or (y, 678 - x). Each try starts hidden:
  # a picture tap, then Exit at once, before the 3 s auto-hide. Exit's centre comes from the measured geometry, as in the UI test.
  g=$(echo "$t4" | grep -o 'pic=[0-9,x]* safe=[0-9,]* full=[0-9x]*' | head -1); pic=${g#pic=}; pic=${pic%% *}; sf=${g#*safe=}; sf=${sf%% *}
  [ -n "$g" ] || { echo "FAIL no geometry in qaFullScreen"; FAILED="$FAILED fullscreen-geometry"; g="pic=0,0,0x0 safe=0,0,0,0 full=0x0"; pic=0,0,0x0; sf=0,0,0,0; }
  fh=${g##*x}; pmax=$(( $(echo "$pic" | cut -d, -f2) + ${pic##*x} )); band=$(( fh - pmax ))
  lx=$(( $(echo "$sf" | cut -d, -f2) + 12 + 22 ))
  if [ "$band" -gt 104 ]; then ly=$(( pmax + 8 + 22 )); else ly=$(( pmax + (band - 44) / 2 + 22 )); fi
  # Also (y, x): every result so far fits it (6cba5b0 missed with both rotations; 12,339 woke the top band, 339,12 hit the picture).
  # bug-073 measurement (runs 46083290466, 46086481097): after the turn sim-use taps land at the same point in window space,
  # but nothing in the top ~70 pt arrives (118,60 lost, 118,80 landed), so Exit now leads the bottom row.
  for xy in "$lx $ly" "$ly $lx" "$((466 - ly)) $lx" "$ly $((678 - lx))"; do
    sleep 22; echo "picture tap: $(sim-use tap -x 233 -y 339 --device "$UDID" 2>&1 | head -1)"
    echo "exit tap at ($xy) from $g: $(sim-use tap -x ${xy% *} -y ${xy#* } --device "$UDID" 2>&1 | head -1)"; sleep 4
    sim-use ui --device "$UDID" 2>/dev/null | grep -q qaFullScreen || { echo "exit reading: $xy"; break; }
  done
  snap fullscreen 5-exited
  # bug-073: hidden, then a picture tap, then Exit leaves full screen and turns back to portrait; fails the job.
  t5=$(ls "$OUT/$SHA"-fullscreen-5-exited-*-ui.txt | head -1)
  if ! grep -q qaFullScreen "$t5" && ! head -1 "$t5" | grep -q landscape; then echo "ok exit returns to portrait"
  else echo "FAIL exit: $(head -1 "$t5"); $(grep -c qaFullScreen "$t5") qaFullScreen"; FAILED="$FAILED fullscreen-exit"; fi
  # The same poses again with the controls held up (-qaBandsStay, internal), so the stills show them (Iris).
  launch -qaRoute trailer/dQw4w9WgXcQ/dawnwalker -qaOverlay YES -qaVideoTime YES -qaBandsStay YES
  tapl Play 8; enter 5b-closed-portrait-turned-shown; tapl "Exit full screen" 3
  fold 0 landscape-left; enter 6-closed-landscape-shown; tapl "Exit full screen" 3
  fold 180 landscape-left; enter 7-flat-landscape-shown
  fold 90 landscape-left; sleep 2; snap fullscreen 8-book-shown; frames 8
  fold 90 portrait; sleep 2; snap fullscreen 9-tabletop-ends-it
  # bug-073: the same at AX5 (Iris); the band glyphs cap at xxxLarge, so the row must look the same.
  fold 0 portrait; sleep 2
  launch -qaRoute trailer/dQw4w9WgXcQ/dawnwalker -qaOverlay YES -qaVideoTime YES -qaBandsStay YES -UIPreferredContentSizeCategoryName $AX5
  tapl Play 8; enter 10-closed-portrait-turned-shown-ax5; tapl "Exit full screen" 3
  fold 0 landscape-left; enter 11-closed-landscape-shown-ax5; tapl "Exit full screen" 3
  fold 180 landscape-left; enter 12-flat-landscape-shown-ax5
  fold 90 landscape-left; sleep 2; snap fullscreen 13-book-shown-ax5; frames 13
  fold 0 portrait; sleep 2
  # Every full-screen tree (those with our qaFullScreen probe) must keep YouTube's buttons from VoiceOver; fails the job.
  "$(dirname "$0")/check-no-youtube-buttons.sh" $(grep -l qaFullScreen "$OUT/$SHA"-fullscreen-*-ui.txt) || FAILED="$FAILED fullscreen-youtube-buttons" ;;
blocked) # R-12: a video YouTube refuses (IFrame error 150) shows Open in YouTube in every pose, never a full-screen button
  # A turn left over from an earlier scenario can keep the Closed scene in landscape (c46af75): rotate away and back first.
  fold 0 landscape-left; sleep 2; fold 0 portrait; sleep 2
  launch -qaRoute video-blocked/dawnwalker/dawnwalker@1.1 -qaOverlay YES; sleep 6; snap blocked 1-closed-portrait
  fold 0 landscape-left; sleep 3; snap blocked 2-closed-landscape
  fold 180 landscape-left; sleep 3; snap blocked 3-flat-landscape
  fold 90 landscape-left; sleep 3; snap blocked 4-book
  fold 90 portrait; sleep 3; snap blocked 5-tabletop ;;
fsxctest) # bug-071: XCUITest taps (sim-use taps did not reach the bands after the turn): enter, band tap, Exit, in Closed
  # The landscape case runs on its own after a landscape fold: XCUIDevice's orientation alone left the Duo's cover display
  # portrait (run 46107453270).
  fsx() { local name=$1; shift; xcodebuild test -project ios/Playscribe.xcodeproj -scheme PlayscribeUI -destination "id=$UDID" -derivedDataPath build/dd-ui \
    "$@" -resultBundlePath "$OUT/fsxctest-$name.xcresult" CODE_SIGNING_ALLOWED=NO > "$OUT/fsxctest-$name.log" 2>&1; local rc=$?
    echo "fsxctest $name exit $rc"; grep -E 'qaFullScreen|qaBands|videoExitFullScreen frame|window after|error:|Test Case|\*\* TEST' "$OUT/fsxctest-$name.log" | cut -c1-400
    [ $rc -eq 0 ] || FAILED="$FAILED fsxctest-$name"; }
  fold 0 portrait
  fsx portrait -only-testing:PlayscribeUITests/FullScreenVideoTests -skip-testing:PlayscribeUITests/FullScreenVideoTests/testExitStaysAfterAutoHideFromLandscape
  fold 0 landscape-left; sleep 3
  fsx landscape -only-testing:PlayscribeUITests/FullScreenVideoTests/testExitStaysAfterAutoHideFromLandscape
  fold 0 portrait ;;
newest) # bug-072: Dawnwalker left on Gallery, relaunch, open it from its Library tile: What's new, Closed portrait and Open portrait
  tapTile() { local f; f=$(sim-use ui --device "$UDID" 2>/dev/null | grep 'The Blood of Dawnwalker, last' | head -1 | grep -o '([0-9.,]* [0-9.x]*)' | tr -d '()'); local x y w h; x=${f%%,*}; y=${f#*,}; y=${y%% *}; w=${f#* }; w=${w%x*}; h=${f##*x}
    sim-use tap -x $((${x%.*} + ${w%.*} / 2)) -y $((${y%.*} + ${h%.*} / 2)) --device "$UDID" >/dev/null 2>&1; sleep 3; }
  launch -qaRoute gamepage/dawnwalker/gallery; snap newest 1-closed-left-on-gallery
  sleep 2; xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; xcrun simctl launch "$UDID" $B >/dev/null; sleep 14
  snap newest 2-closed-relaunched-library; tapTile; snap newest 3-closed-game-opened
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; xcrun simctl launch "$UDID" $B >/dev/null; sleep 8
  fold 180 portrait; sleep 3; snap newest 4-open-portrait-library; tapTile; snap newest 5-open-portrait-game-opened ;;
noart) # bug-076: no-hero-art game (Tomb Raider: Catalyst, 381234): the thumbnail stays left of the rail strip in Closed
  launch -qaRoute index-game/381234; sleep 6; snap noart 1-portrait
  launch -qaRoute index-game/381234 -qaOrientation landscape; sleep 6; snap noart 2-landscape
  launch -qaRoute index-game/381234 -UIPreferredContentSizeCategoryName $AX5; sleep 6; snap noart 3-portrait-ax5
  launch -qaRoute index-game/381234 -qaAppearance dark; sleep 6; snap noart 4-portrait-dark
  launch -qaRoute index-game/381234 -qaAppearance dark -qaOrientation landscape; sleep 6; snap noart 5-landscape-dark
  launch -qaRoute index-game/381234 -qaOrientation landscape -UIPreferredContentSizeCategoryName $AX5; sleep 6; snap noart 6-landscape-ax5
  launch -qaRoute index-game/381248; sleep 6; snap noart 7-other-portrait
  launch -qaRoute index-game/381248 -qaOrientation landscape; sleep 6; snap noart 8-other-landscape ;;
headerart) # bug-076: Closed header art edge to edge, title 20 pt under it; game page and update page, portrait and landscape, std and AX5
  for g in dawnwalker minecraft; do
    launch -qaRoute gamepage/$g; sleep 6; snap headerart $g-page-portrait
    launch -qaRoute gamepage/$g -qaOrientation landscape; snap headerart $g-page-landscape
    launch -qaRoute gamepage/$g -UIPreferredContentSizeCategoryName $AX5; snap headerart $g-page-portrait-ax5
  done
  launch -qaRoute release/dawnwalker/dawnwalker@1.1; snap headerart update-portrait
  launch -qaRoute release/dawnwalker/dawnwalker@1.1 -qaOrientation landscape; snap headerart update-landscape
  launch -qaRoute release/dawnwalker/dawnwalker@1.1 -UIPreferredContentSizeCategoryName $AX5; snap headerart update-portrait-ax5
  launch -qaRoute release/dawnwalker/dawnwalker@1.1 -qaAppearance dark; snap headerart update-portrait-dark
  launch -qaRoute gamepage/dawnwalker -qaAppearance dark; snap headerart dawnwalker-page-portrait-dark
  launch -qaRoute gamepage/dawnwalker -qaAppearance dark -qaOrientation landscape; snap headerart dawnwalker-page-landscape-dark
  launch -qaRoute index-game/381234; sleep 6; snap headerart noart-portrait
  launch -qaRoute index-game/381234 -qaOrientation landscape; sleep 6; snap headerart noart-landscape
  launch -qaRoute gamepage/dawnwalker; fold 120 portrait; snap headerart tabletop-unchanged ;;
listplace) # polish-pose-change-scroll-anchor: the topmost update row survives Closed, Book, Open landscape, Tabletop, Closed (state line names the first rows)
  launch -qaRoute gamepage/dawnwalker
  sim-use swipe --from 233,560 --to 233,160 --duration 0.6 --device "$UDID" >/dev/null 2>&1; sleep 2
  state closed; snap listplace 1-closed
  fold 90 landscape-left; sleep 3; state book; snap listplace 2-book
  fold 180 landscape-left; sleep 3; state open-landscape; snap listplace 3-open-landscape
  fold 120 portrait; sleep 3; state tabletop; snap listplace 4-tabletop
  fold 0 portrait; sleep 3; state closed-again; snap listplace 5-closed-again ;;
video) # row 9: hinge sweep recording with frame timing
  launch -qaRoute library/playing; fold 180 landscape-left
  sim-use record-video --device "$UDID" --fps 60 --output "$OUT/$SHA-video-sweep.mp4" >/dev/null 2>&1 & rp=$!
  sleep 3; for a in 180 170 160 150 140 130 120 110 100 90 80 70 60 70 80 90 100 110 120 130 140 150 160 170 180; do sim-use ios fold $a --device "$UDID" >/dev/null 2>&1; sleep 1.5; done
  sleep 2; kill -INT $rp 2>/dev/null; wait $rp 2>/dev/null
  if command -v ffprobe >/dev/null; then ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$OUT/$SHA-video-sweep.mp4" \
    | python3 -c 'import sys;t=[float(x) for x in sys.stdin if x.strip()];g=[(b-a)*1000 for a,b in zip(t,t[1:])];print("frames",len(t),"(frames are emitted only when the screen changes: gaps are NOT hitches; row 9 needs the app frame log) max gap ms",round(max(g),1) if g else 0,"gaps>100ms",sum(x>100 for x in g))' | tee "$OUT/$SHA-video-frame-gaps.txt"; fi ;;
esac; done
[ -z "${FAILED:-}" ] || { echo "FAILED:$FAILED"; exit 1; }

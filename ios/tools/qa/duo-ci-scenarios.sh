#!/usr/bin/env bash
# Quinn's five cloud runs on a booted, app-installed iPhone Duo (hosted runner or Mac). Needs sim-use.
#   ios/tools/qa/duo-ci-scenarios.sh UDID OUTDIR [scenario ...]    (default: all)   scenarios: continuity trailer closedax5 schemes video axchips deckwide plusend switchax switchtt heroswipe herolong removemenu brand brandbook edgefade lane
# Every step saves <sha>-<scenario>-<step>-<display>-shot.png and -ui.txt (outline with frames, ids and the pose line).
set -uo pipefail
UDID=$1; OUT=$2; shift 2; SCEN=${*:-continuity trailer closedax5 schemes video}
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nosha); B=co.codeconnectors.playscribe; mkdir -p "$OUT"
AX5=UICTContentSizeCategoryAccessibilityXXXL
# Rotate first, fold second, then check the active display matches the angle (inner for any open angle, outer for 0); redo once if not.
fold() {
  for try in 1 2 3 4 5; do
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
  launch -qaRoute "${TT_ROUTE:-library/playing}" -qaOverlay YES ${extra[@]+"${extra[@]}"}
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
brand) # s-06-brand-swap (#614): Home Screen icon light and dark (tinted cannot be set here), Settings footer, caught-up and new-update marks, splash in Closed, Book and Tabletop
  quick() { local d; d=$(did); local n; [ "$d" = 3 ] && n=inner || n=outer; for i in 1 2 3 4; do xcrun simctl io "$UDID" screenshot --display=$d "$OUT/$SHA-brand-$1-$i-$n-shot.png" >/dev/null 2>&1; done; }
  for ap in light dark; do xcrun simctl ui "$UDID" appearance $ap >/dev/null 2>&1; xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 0 portrait; sleep 3; snap brand 1-home-icon-$ap; done
  xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1
  launch -qaRoute settings; snap brand 2-settings-top
  scroll_end 233,520 233,160 settings-footer; snap brand 3-settings-footer
  launch -qaRoute caught-up; snap brand 4-library-caught-up
  launch -qaRoute two-update; snap brand 5-library-new-update
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 0 portrait; xcrun simctl launch "$UDID" $B -qaRoute library/playing -qaSplashHold 12 >/dev/null; sleep 3; quick 6-splash-closed
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 90 landscape-left; xcrun simctl launch "$UDID" $B -qaRoute library/playing -qaSplashHold 12 >/dev/null; sleep 3; quick 7-splash-book
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 90 portrait; xcrun simctl launch "$UDID" $B -qaRoute library/playing -qaSplashHold 12 >/dev/null; sleep 3; quick 8-splash-tabletop
  xcrun simctl ui "$UDID" appearance dark >/dev/null 2>&1; xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 0 portrait; xcrun simctl launch "$UDID" $B -qaRoute library/playing -qaSplashHold 12 >/dev/null; sleep 3; quick 9-splash-closed-dark; xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 ;;
brandbook) # #614: the splash in Book only (light), four frames; a lighter run than brand
  quick() { local d; d=$(did); local n; [ "$d" = 3 ] && n=inner || n=outer; for i in 1 2 3 4; do xcrun simctl io "$UDID" screenshot --display=$d "$OUT/$SHA-brandbook-$1-$i-$n-shot.png" >/dev/null 2>&1; done; }
  xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 90 landscape-left; T0=$(date +%s); xcrun simctl launch "$UDID" $B -qaRoute library/playing -qaSplashHold 40 >/dev/null; sleep 3
  for i in 1 2 3 4; do xcrun simctl io "$UDID" screenshot --display=$(did) "$OUT/$SHA-brandbook-splash-book-$i-inner-shot.png" >/dev/null 2>&1; echo "brandbook frame $i at +$(( $(date +%s) - T0 )) s after launch (hold 40 s)"; done ;;
edgefade) # #613 (bug-063, bug-library-tabbar-edge-fade): game page and Library mid-scroll and at the end, std and AX5, Closed portrait and Open portrait (fold 180; swipes start above the bottom tab bar, y 780); ui.txt carries qaBarPinned
  for sz in std AX5; do size=UICTContentSizeCategoryL; [ $sz = AX5 ] && size=$AX5
    for pose in closed open; do
      if [ $pose = closed ]; then F=0; X=233; Y1=560; Y2=200; else F=180; X=300; Y1=780; Y2=300; fi
      for r in gamepage/dawnwalker library/playing; do n=$(echo "$r" | tr '/' '_')
        xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold $F portrait; xcrun simctl launch "$UDID" $B -qaRoute "$r" -qaOrientation portrait -UIPreferredContentSizeCategoryName $size >/dev/null; sleep 8
        sim-use swipe --from $X,$Y1 --to $X,$Y2 --duration 0.5 --device "$UDID" >/dev/null 2>&1; sleep 2; snap edgefade "$sz-$pose-$n-1-mid"
        scroll_end $X,$Y1 $X,$Y2 $pose; snap edgefade "$sz-$pose-$n-2-end"
      done
    done
  done ;;
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
newest) # bug-072: Dawnwalker left on Gallery, relaunch, open it from its Library tile: What's new, Closed portrait and Open portrait
  tapTile() { local f; f=$(sim-use ui --device "$UDID" 2>/dev/null | grep 'The Blood of Dawnwalker, last' | head -1 | grep -o '([0-9.,]* [0-9.x]*)' | tr -d '()'); local x y w h; x=${f%%,*}; y=${f#*,}; y=${y%% *}; w=${f#* }; w=${w%x*}; h=${f##*x}
    sim-use tap -x $((${x%.*} + ${w%.*} / 2)) -y $((${y%.*} + ${h%.*} / 2)) --device "$UDID" >/dev/null 2>&1; sleep 3; }
  launch -qaRoute gamepage/dawnwalker/gallery; snap newest 1-closed-left-on-gallery
  sleep 2; xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; xcrun simctl launch "$UDID" $B >/dev/null; sleep 14
  snap newest 2-closed-relaunched-library; tapTile; snap newest 3-closed-game-opened
  xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; xcrun simctl launch "$UDID" $B >/dev/null; sleep 8
  fold 180 portrait; sleep 3; snap newest 4-open-portrait-library; tapTile; snap newest 5-open-portrait-game-opened ;;
video) # row 9: hinge sweep recording with frame timing
  launch -qaRoute library/playing; fold 180 landscape-left
  sim-use record-video --device "$UDID" --fps 60 --output "$OUT/$SHA-video-sweep.mp4" >/dev/null 2>&1 & rp=$!
  sleep 3; for a in 180 170 160 150 140 130 120 110 100 90 80 70 60 70 80 90 100 110 120 130 140 150 160 170 180; do sim-use ios fold $a --device "$UDID" >/dev/null 2>&1; sleep 1.5; done
  sleep 2; kill -INT $rp 2>/dev/null; wait $rp 2>/dev/null
  if command -v ffprobe >/dev/null; then ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$OUT/$SHA-video-sweep.mp4" \
    | python3 -c 'import sys;t=[float(x) for x in sys.stdin if x.strip()];g=[(b-a)*1000 for a,b in zip(t,t[1:])];print("frames",len(t),"(frames are emitted only when the screen changes: gaps are NOT hitches; row 9 needs the app frame log) max gap ms",round(max(g),1) if g else 0,"gaps>100ms",sum(x>100 for x in g))' | tee "$OUT/$SHA-video-frame-gaps.txt"; fi ;;
esac; done

---
name: five-pose-stills
description: Use when a Playscribe PR changes any UI and needs stills or a pose gate, when asked for a shoot list, or when signing off layout. Plans which of the five iPhone Duo poses to shoot (Closed portrait, Closed landscape, Book, Open, Tabletop plus Open portrait), at standard and AX3 text, and what to check in each. Cites docs/ux-acceptance.md IDs.
---

# Five-pose stills plan

Poses: `closed`, `book`, `open`, `open-portrait`, `tabletop` (+ `closed-landscape` where the view has a landscape layout). Pose comes from the container and reserved regions, never device checks (CLAUDE.md).

1. **Scope from the diff.** Name each changed view and the acceptance IDs it touches (G-5 reserved regions, P-1..P-3, TT-0, B-/R- rules in `docs/ux-acceptance.md`). Shoot only poses the view appears in; say which are skipped and why.
2. **Order: AX3 first**, in Book, Closed portrait, Open portrait and Closed landscape (button gaps and rail overlap failed in all four, not only Book and Closed portrait; #292). Then Open, Tabletop, Closed.
3. **Per pose, check:** nothing tappable crosses an active `.division` (G-5); Tabletop has nothing tappable above the fold; no text clipped or ellipsised that should wrap; no module over 25% of a page (Book); fonts match other poses; hero headline cap 3 lines in Book and Closed, 4 in Closed portrait, cut only on word boundaries, chips never dropped (#292); Book tile widths match within 1 pt across both pages (#287); the no-cover placeholder is checked in the smallest tile (#308).
   A still must show the whole card top. A cropped still counts as **unshot** for the top.
4. **Capture** with `ios/tools/qa/gate.sh <out> [poses]` or `ios/tools/qa/shots.sh <pose> <dir>`; routes via `-qaRoute` (see CLAUDE.md). One gate or simctl run at a time on the Mac.
4a. **Rotating to Closed landscape (or any rotation):** use the simulator control tool's `rotate` action, direction right. The AppleScript click on Device Hub's "Rotate Right" (as `poselib.sh` `press` does) hangs. Source: Mac tester, 2026-11-07. Exact invocation not yet recorded here: the Mac tester adds the command when next confirmed.
5. **Name files** `<sha>-<pose>-<what>[-ax3].png` at the shared folder root. Sign-offs name the exact SHA.
6. **Say "unshot"** for any pose you did not shoot and infer from the diff.
7. End with a one-line `Next:`.

# Decision note: real ArrangementView split in the harness

Date 2026-11-07 / owner: QA-poses thread (Theo builds) / card: harness Book split (new)

1. **Why.** Quinn's KCD II Book AX5 calibration (#354): harness stills are good for wraps, cuts, ticks, chips and overlap, but the Book page split is ~41% against 48% on the Mac, so row and line counts can't be trusted. Goal: Book counts without a Mac run (Terry, 7 Nov: keep the Mac unloaded).
2. **Still needed?** Yes, but only for Book (and Tabletop's page split). Closed, Open and Open portrait have no system split.
3. **Value vs cost.** Worth = fewer Mac Book shoots with Quinn's sign-off intact. ArrangementView is system-owned and lays out against the window's real reserved region; the phone-sim harness window is 155 pt wide, so it cannot be fed a synthetic region (docs/fold-harness.md). Size of gain is a guess; Book is one of five poses but the one that differs most.
4. **Alternatives.**
   - A. Do nothing: Mac stays the sign-off for Book. Costs Mac time, zero risk.
   - B. Calibrate in the harness only: a test-only stand-in that splits at the Mac-measured ratio (48%) and is checked against one Mac still per release. Small, no production change; proves app content, not the system split.
   - C. App-owned split view used in production: exact in the harness, but replaces the system's arrangement behaviour. Large, risks the Duo-native feel.
5. **Decision.** B, as a 1 h spike with a kill rule: if the harness Book still doesn't match the Mac within ~2 points on row/line counts for KCD II AX5, stop and keep A. Do not do C.
6. **Learning.** A headless stand-in is only trustworthy for what it was calibrated against; record the Mac pair that justifies it.

Weighed by Nadia, 7 Nov: B approved with conditions: the Mac still signs off Book (the stand-in is triage only), record the Mac and harness pair that justifies it, and C stays rejected. Board card: r052-harness-book-split.

**Spike result, 7 Nov (e6fd747, 487b926):** the stand-in puts the left pane at ~48% and Quinn's KCD II Book AX5 left page matches 6 of 6. The right page matched 3 of 4: "Patch 1.5.6" wraps to 2 lines on the harness (one line on the Mac). A 9 pt rail-reserve trim widened the art but the title still wraps, so one iteration was spent and the kill rule applies: the Book split is **left page advisory only**; the right page and the Mac's side-rail reserve stay Mac-only. Stand-in kept (test-only, off unless `SPLIT=1`).


Weighed by Iris, 7 Nov: B signed. Her conditions: calibrate at AX3 and AX5 on two unlike games before the left page counts; name harness Book stills "calibrated, not signed"; record the Mac pair that justifies it.
**Mac pair on record:** Mac `893a329-book-ax5.png` vs harness `harness-4beebaf-kcd2-book-ax5-calibrated-not-signed.png` (KCD II, AX5). Still to do: AX3, and a second unlike game (not KCD II).

**Calibration result, 7 Nov (Iris's condition, Mac pairs on 4bb2740, harness on main + #360):** three pairs compared by eye on two unlike games.
- Dawnwalker Book AX5: `mac-4bb2740-dawnwalker-book-ax5` vs `harness-e4daf3a-dawnwalker-book-ax5-calibrated-not-signed`. Left pane 47.9% vs 47.8%; title 2 lines, links 1+2, chips 2+2+2, "Update 1.1" on one line, "Read full notes on Steam" 3 lines, "Story" below: all equal.
- Dawnwalker Book AX3: `mac-4bb2740-dawnwalker-book-ax3` vs `harness-e4daf3a-dawnwalker-book-ax3-calibrated-not-signed`. Chips 2+2+2, links 1+2, "Read full notes / on Steam" 2 lines, "Story spoilers hidden / Show" 3 lines, "Respec with" cut at the same line: all equal.
- KCD II Book AX3: `mac-4bb2740-kcd2-book-ax3` vs `harness-f9d11a8-kcd2-book-ax3-calibrated-not-signed`. "Patch 1.5.6" on one line (was 2 before #360), chips 2+2, links 1+2, notes link 2 lines, headline 3 lines: all equal.
Verdict: on these three the harness Book still agrees with the Mac on line counts, wraps and the split, so it is good for triage on both pages. The Mac still signs off Book. Not covered by the harness: the system side rail, the status area, the hinge, and anything on KCD II at AX5 (only the pre-#360 pair exists). Re-calibrate if #360's width rule or the Book layout changes.


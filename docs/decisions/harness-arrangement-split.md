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

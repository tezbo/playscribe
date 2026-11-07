---
name: ax3-layout-check
description: Use when adding or changing any SwiftUI view that shows text or chips, before pushing, to prevent Dynamic Type AX3 (accessibility3) clipping, missing chips or overlapping art. Also use when an AX3 still fails the gate. Cloud engineers have no Xcode, so this is a written checklist plus a headless layout check.
---

# AX3 layout check

Past failures: #292 (hero headline clipped at top, "v1.1 / New update" chips missing, art overlapping headline in Book and Closed portrait) and the #308 plate (11 pt floor).

For every text-bearing view you touch, answer in the commit message, one line each:
1. **Fixed heights?** Replace with `minHeight` or let content size it; no `.frame(height:)` around text.
2. **Line limits?** `lineLimit(nil)` or a stated cap with `minimumScaleFactor` (floor documented, 0.85 on plates, never below 11 pt).
3. **Chips and badges:** do they wrap (`ViewThatFits`, flow layout) or are they dropped? A hidden chip is a bug.
4. **Overlap:** art, plates and text in a `ZStack` need the text to push the art, not the other way round. Check Book (narrow page) first.
5. **Hit targets** stay 44 pt and clear of the `.division` reserved region (G-5).
6. **Headless check:** add or extend a case in `ios/PlayscribeTests/Harness/FoldHarnessTests.swift` or the layout suites that renders the view at `.accessibility3` in a Book-width and Closed-width container and asserts no clipping or overlap.
7. Run Precheck (see `precheck-loop`), then ask for AX3 stills in Book and Closed portrait (`five-pose-stills`).
7a. The gate size is AX5, not only AX3: check the same items at AX5 and name the size in any still (`-ax5`; `docs/learnings.md` entry 9). Before "fixing" something that looks missing at an AX size, confirm it is present in a clean standard-size still (entries 13 and 14).
8. **Headlines:** wrap in full. If a cap is unavoidable (hero deck: 3 lines in Book and Closed, 4 in Closed portrait), cut only on a word boundary, never mid-word, and keep the full text in the VoiceOver label and on the release page. Chips and badges are never dropped: they wrap to a second line before the headline loses its last line (#292).
9. **Stacking at AX:** buttons stack full width with at least a 12 pt gap, labels wrap whole in a rounded rectangle (capsule only for one line), and nothing truncates (#278). Rows stack: title, tags, then trailing controls on their own row, 24 pt clear of the trailing rail and never behind it. Metadata rows ("Released / size / chevron") stay one block (#288).
10. **State copy:** the undecided state never shows the denied wording, and a body line dropped at AX stays in the VoiceOver label (#278).
11. **Plates:** wrap on whole words, 11 pt absolute floor (0.85 of 13 pt), never below, same size at AX (#308).
12. **Book geometry:** content, sheets and containers keep 24 pt from the hinge or division. In Open, a sheet's leading edge sits 24 pt past the hinge band. No single module over 25 percent of a page height. One tile size per pose. Both pages of a spread must end at about the same height (#304, #306, #287).

(Items 8 to 12 are Iris's rulings, final; she records them as design tokens via design-system.)

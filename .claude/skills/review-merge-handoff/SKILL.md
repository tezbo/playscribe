---
name: review-merge-handoff
description: Use when a Playscribe PR is ready for sign-off, when asked to review or sign a PR, or before merging. Covers who signs (Quinn front/back end, Iris design), what a sign-off must contain, and merge conditions. Never merge red; irreversible steps need Terry's explicit yes.
---

# Review and merge handoff

**Requesting a sign-off** (author): PR number, head SHA, Precheck PASS, **the CI verdict for that SHA (green or red, with the run link)**, acceptance IDs touched, stills filenames (`five-pose-stills`), and what is "unshot". One message, batched.

The author posts the CI verdict every time they ask for a review, because reviewers often cannot read CI. Re-post it for that exact SHA if the head moves.

**Signing** (Quinn, Iris, Jun): name the exact SHA; list what you opened (files, poses); give conditions as numbered items, blocking vs not; say "unshot" for anything inferred; state CI status or that you could not read it. Batch all feedback into one pass. Use `code-review` for diffs (see `playscribe-code-review`).

**Merging** (Theo or the owner): needs Quinn and, for UI, Iris signs on the current head SHA, and CI green. Re-sign if the head moves beyond the geometry already signed. Never merge red. Squash per repo habit; delete only branches Terry has agreed to delete.

**Needs Terry's plain yes**: key copies to Cloudflare or any deploy, leftover branch deletion, TestFlight publishing, domain or money, any message sent outside the project.

Then move the board card (`qa` -> `done`) and end with `Next:`.

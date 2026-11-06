# Team learnings

Append-only. Newest cycle at the bottom. One entry per lesson: what happened, the lesson, the rule it became, and where the evidence is (PR, commit or skill). Owner: Gabrielle (Agent Resources). Added each 3-hourly cycle via a small PR (Terry, 2026-11-07 09:57 AEDT). Times AEDT.

Do not edit past entries. If a lesson turns out wrong, add a new entry that corrects it.

## Cycle 2026-11-07 (to 09:00)

1. **Branch from a fresh main.** Cloud sessions can hold a stale or shallow `origin/main`; Gabrielle's #314 branch was cut from one and had unrelated history, caught before merge. Rule: `git fetch origin main` before branching. Evidence: #314 (merged a46cafa). Follow-up: add the line to the `precheck-loop` skill (risk 7).
2. **Report the route, not the blocker.** Naming a limit ("can't", "only", "needs Terry") without a workaround stalled work. Rule: check repo, other thread or tool, then build, before any limit goes in a reply. Evidence: `.claude/skills/workaround-first`.
3. **Reviewers cannot read CI, so the author posts the verdict.** Quinn and Jun signed with "confirm green". Rule: the PR author posts the CI verdict for the exact SHA with each review request. Evidence: `.claude/skills/review-merge-handoff` (#319).
4. **Shared curl needs `|| true`.** Quinn's catch in a status curl was copied into two workflows. Rule: status curls end `|| true` so no failure email reaches Terry. Evidence: `precheck.yml`, `relay-check.yml` on main.
5. **AX3 fit is checked before the Mac shot.** #292 failed the AX3 gate (clipped headline, missing chips, overlap). Rule: run `ax3-layout-check` first and shoot AX3 in Book, Closed portrait, Open portrait and Closed landscape. Evidence: `.claude/skills/ax3-layout-check`, `.claude/skills/five-pose-stills` (#314).
6. **Rotate the simulator with the simulator tool.** The Mac tester found `rotate right` works and the AppleScript click hangs. Rule: use the rotate action, not a click. Evidence: `five-pose-stills` step 4a (#326).
7. **Estimates carry a basis.** Estimates were guesses. Rule: cards carry est_work, est_wait and basis from the agent-estimate CLI (manual PERT if it is unavailable); "n/e" when there is no basis. Evidence: `.claude/skills/playscribe-estimate`, AGENTS.md "Estimates".
8. **Check the original goal and weigh the options before removing something.** From the "Also new" card work: the fix was to remove the card, when the original goal should have been checked and the options weighed first. Proposed rule (Gabrielle, to confirm with Nadia): before removing a feature or card, state its original goal and compare the options. Source: coordinator's account (2026-11-07 09:57 AEDT); thread/PR link to be added by the card owner.
9. **Shoot the size that was asked for.** AX5 stills were shot where AX3 was required. Proposed rule (Gabrielle, to confirm with Quinn): take the Dynamic Type size from the PR's checklist and name it in the still's filename. Source: coordinator's account (2026-11-07 09:57 AEDT); the Mac tester or Quinn should add the PR link.

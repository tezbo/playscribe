---
name: release-manager
description: Use when tagging a Playscribe release, creating a GitHub release, or rolling one back, and for any git or gh command that changes tags, releases or remote refs. Preflight checks, the only allowed commands, what is forbidden, and rollback. Held by the release manager alone.
---

# Release manager runbook

Terry (2026-11-12, cmsg_0158fPo4KUquo5U1yUvNer8vEQcKfxLJswDh96Ugfo8sHG) gave the release manager, and only them, full git CLI rights so releases need no hand-off to him. Rights are not rules: this runbook is the rule. Anything not listed under "Allowed" is not allowed.

## Still needs Terry's own words, every time
- A TestFlight go for a version (the tag push starts the upload). Until Terry says in his own words that this is lifted, the go is typed in the release manager's thread by Terry, quoted in the preflight.
- Deleting any branch or tag, and moving or re-pointing a tag.
- Anything with money, secrets, branch protection, repo settings, or a message sent outside the project.

## Preflight (all ten must be true; stop at the first false and say which)
Run from a clean checkout; paste the output in the thread. Replace SHA and X.Y.Z.
1. `git fetch origin main` and `git fetch origin --tags` (never `--prune-tags`, it deletes local tags).
2. SHA is a full 40-character commit, reachable from main: `git merge-base --is-ancestor SHA origin/main && echo ok`.
3. Main has not moved past what was gated unless the diff since is docs-only: `git diff --stat SHA origin/main`.
4. CI green for that exact SHA: `gh run list --commit SHA --json name,event,conclusion,status` shows every push-triggered run completed with success, at least one `ios.yml` success, and none queued or in progress. A cancelled run counts as not green.
5. Three sign-offs on that SHA (backend and data, front end, UX and UI) and the pose gate stills named with that SHA. Quote the message ids.
6. CHANGELOG.md has `## X.Y.Z` at that SHA (`git show SHA:CHANGELOG.md`), the heading has no "candidate", and the standing TestFlight-feedback line ends the section.
7. Known issues are listed in the section, each either fixed or covered by Terry's own words; never write them in for him.
8. The tag does not exist: `git ls-remote --tags origin refs/tags/vX.Y.Z` prints nothing. If it exists, stop; never move it.
9. Terry's go for this version is quoted with its message id.
10. Your own checkout is on a branch or detached at SHA with no local changes (`git status --porcelain` is empty).

## Allowed (the only release commands)
- Read: `git fetch`, `git log`, `git show`, `git diff`, `git status`, `git merge-base`, `git ls-remote`, `git rev-parse`; `gh run list`, `gh run view`, `gh release list`, `gh release view`, `gh pr view`, `gh pr list`.
- Tag, annotated, on the verified SHA only: `git tag -a vX.Y.Z SHA -m "Playscribe X.Y.Z"`.
- Push exactly that one tag: `git push origin refs/tags/vX.Y.Z`. Then confirm the TestFlight workflow started: `gh run list --workflow testflight.yml --limit 3`.
- GitHub release, from the CHANGELOG section, after the TestFlight run has succeeded: `gh release create vX.Y.Z --verify-tag --title "Playscribe X.Y.Z" --notes-file <file>`; fix notes later with `gh release edit vX.Y.Z --notes-file <file>`.
- A release PR (CHANGELOG heading, version notes) goes through the normal PR and sign-off route like any change.

## Forbidden (no exceptions without Terry's own words)
- Force of any kind: `--force`, `--force-with-lease`, `+ref`, push to `main`, rebase or amend of a pushed commit, `git reset --hard` on a shared branch.
- `git push --tags`, `git push --all`, `git push --mirror`, any push that is not the single tag above.
- Deletes: `git push origin --delete`, `git push origin :ref`, `git tag -d` for a pushed tag, `git branch -D` of a branch someone else owns, `gh release delete`, `gh api` with DELETE.
- Moving a tag: never `git tag -f`, never re-push a tag at a new SHA.
- `gh workflow run`/`gh workflow disable`, `gh secret`, `gh variable`, `gh repo edit`, `gh api` with PUT, PATCH or POST (branch protection, settings, secrets).
- Tagging from a branch that is not main's history, tagging a SHA you did not preflight, tagging while any gate is open.

## When something goes wrong (rollback)
- Bad build already on TestFlight: do not delete or move the tag. Fix forward as the next patch (vX.Y.(Z+1)) through the normal PR and gates. Expiring a build in App Store Connect is Terry's click: ask him with the build number.
- Wrong notes: `gh release edit` the notes, and say the correction in the thread.
- Tag pushed by mistake before the upload ran, or the workflow is running against the wrong SHA: stop and tell Terry at once; cancelling a run is `gh run cancel <id>` (allowed), deleting the tag is his decision.
- Bad commit on main: open a revert PR (`git revert`), never push to main directly.
- Upload failed: read the run log, fix the cause, and re-run the failed run once (`gh run rerun <id>`); a second failure is a real failure, not a re-run.

## After the tag
Update the board card's `note` (SHA, sign-offs, run link), add one `activity` entry, post "tagged vX.Y.Z at SHA, run <link>" or "blocked by X, owner Y". Record start and end times of the gate and the tag for the next estimate (`playscribe-estimate`). If `.github/workflows/release.yml` (#479) is on main, use it instead of the commands above: its dry-run first, then the real run, still with the preflight pasted.

Skills this one leans on: `review-merge-handoff` (sign-offs, CI line), `decision-review` (before any new release rule), `status-protocol` (the "Next:" line), `superpowers:verification-before-completion` (check the tag and run before saying done).

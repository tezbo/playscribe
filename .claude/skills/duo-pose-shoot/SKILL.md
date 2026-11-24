---
name: duo-pose-shoot
description: Use when you need real iPhone Duo stills from a hinge fold without the Mac, to look at the app in Closed, Book, Tabletop or Open, check a pose, or prove you can run native simulator QA. For Quinn, Iris, Jun, Nadia and engineers; no Xcode needed.
---

# Duo pose shoot (cloud, real hinge)

Source of the procedure: the engineering thread's coverage map (`/mnt/project-files/qa/cloud-duo-qa/coverage-map-and-procedure.md`, 24 Nov 2026, SHA 5da5b37, 3 runs). It uses `sim-use` on the free `xcode-27` runner, folds the simulated Duo through hinge angles without Device Hub, and keeps native stills, an accessibility outline and the app's own pose line per step. Costs nothing and needs no secret.

A shoot is **evidence of what rendered**. It is not a sign-off. A matrix row is PASS only after Quinn's functional sign and Iris's visual sign, and a pose the shoot cannot reach is NOT TESTED, never "looks fine".

## Before you start

1. The workflow is `.github/workflows/duo-poses.yml` ("Duo poses (real hinge)") with `ios/tools/qa/duo-ci-poses.sh`. At 24 Nov it lives on engineering's branch `claude/project-thread-2cqf9d`, not main. If `git ls-tree origin/main .github/workflows/duo-poses.yml` shows nothing, say so and ask engineering to merge it. Do not fake a shoot.
2. Pick the route. Default `library/playing`. Others: `gamepage/dawnwalker`, `two-update`, `many-updates`, `release/<game>/<release>`; any `-qaRoute` in `CLAUDE.md` except one that opens Settings.

## Shoot

1. Run the workflow on your branch: GitHub, Actions, "Duo poses (real hinge)", Run workflow, fill `route`. Agents without the web UI can dispatch it with the GitHub Actions tool; a push to a `claude/**` branch that edits the workflow file also runs it.
2. Wait about 20 minutes. Download the `duo-poses` artifact.
3. Read `manifest.tsv` first. Per file it gives the angle and orientation requested, the display that became active, and the image size. Wide image = landscape, tall = portrait. If the request and the image disagree, trust the image.
4. Files are `<sha>-r<run>-<step>-a<angle>-<orientation>-<display>-shot.png` (full resolution), `-ui.txt` (accessibility outline with frames, ids and the pose line: closed, flat, book or tabletop) and `-displays.txt`.
5. To change poses, edit the steps string in `duo-poses.yml` as `angle:orientation` (portrait, landscape-left, landscape-right). Hinge 180 is flat, 130 to 60 partly open. Landscape plus partly open is Book. Portrait plus partly open is Tabletop.

## Read it honestly

- Report: commit SHA, route, angles reached, the pose line from `-ui.txt`, and one concrete observation per still (or "none found", with the filename).
- Compare against the acceptance IDs in `docs/ux-acceptance.md`; cite them.
- Tabletop: check nothing tappable sits above the fold using the frames in `-ui.txt`, not by eye.
- Known gaps (24 Nov): no video, no reflection pixels, only two layouts between 60 and 130 degrees, 30 and 150 degrees untested, system Table Mode is device only, AX5, dark and Reduce Transparency are not yet workflow inputs (use the app's launch args, for example `-qaAppearance dark`, passed to the script). Limrun cannot take launch args, so routes do not work there. Update this list when engineering lands the AX5, appearance and recording inputs.
- Never put a key in a file or chat.

## Competency check (run it, do not read it)

Pass means a posted shoot, in your own thread, that names the SHA and route, links the run or artifact, and gives one observation per pose from the images. A manifest quoted without opening a still does not pass. Record the result in `docs/capability-register.md`.

# Screen diffs on PRs

Every pull request gets one comment, kept up to date, that lists only the screens that look different from main, with
before, after and diff images. People review those few screens instead of reshooting and rereading the whole set.
Workflow: `.github/workflows/screen-diffs.yml`. Compare step: `ios/tools/qa/screen_diff.py`. Card: qa-screen-diffs-on-prs.

## How it works

1. `scope` checks whether the PR touches anything that can change a still: `ios/Playscribe`, `ios/Shared`,
   `ios/PlayscribeWidget`, `ios/project.yml` or `ios/PlayscribeTests/Harness`. If not, the comment says nothing changed and
   no macOS runner is used.
2. Two `render` jobs run side by side on the free `xcode-27` runner. **Before** is main's latest commit (the merge ref's
   first parent) and **after** is the PR merged into main. Both use the PR's fold harness, so only the app code differs. If
   the PR's tests don't build against main, main falls back to its own tests, and the comment says so.
3. Both render the matrix with `HARNESS_STABLE=1`. That means no network (remote art falls back to bundled art or the title
   plate), animations off (drifting key art and fades jump to their end state), and a 0.6 s pause after layout settles.
   - Matrix: library, game, updates, settings and upcoming screens.
   - Poses and sizes: every pose at std and AX5, plus AX3 in Closed and Tabletop only. That is 70 stills a side.
4. `compare` diffs the two sets. It pushes the changed images to the `screen-diffs` branch, then writes the PR comment.
   - The branch holds one orphan commit and is written only by this workflow.
   - The comment names the main SHA it compared against.

Main is rendered fresh in every run rather than kept as stored reference images. The app shows dates relative to today, so
stored images go stale and would raise false alarms. Rendering both sides on the same runner image minutes apart avoids
that. The references still change only one way: by merging to main.

## Pass bar (Quinn and Iris, 12 Nov 2026)

- A pixel differs when any channel differs by more than 2 of 255.
- A screen has changed when any 48 x 48 px tile has more than 30 differing pixels, or when more than 0.02% of all pixels
  differ. Stills are 1 px per pt.
- A screen has also changed when its tappable-frames text differs, for example after a clipped word or a lost chip.
- When a screen shows as changed, Iris signs the UI and Quinn signs the behaviour, both from the comment's images.
- An unchanged screen needs no look, but unchanged does not mean signed. Release gates stay Mac stills of the exact SHA,
  plus one whole-page still per pose.
- These still need a Mac still, because the harness can't see them:
  - the real hinge position, and any frame claim about the hinge band (455-495) or the Tabletop fold (374-414)
  - the Tabletop system rail and toolbar
  - sheets and sheet bottoms, and navigation bar collapse
  - the status bar and video
  - scroll-edge fades, Reduce Motion states, and switching between light and dark
- Harness images are only ever compared with harness images. Open portrait and Book have a known 44 pt leading shift
  against the Mac.

## Trial (next 3 UI PRs)

Run it side by side with the Mac reshoot. It passes when all three of these hold:

- every change the Mac finds is in the list
- there are no more than 2 false alarms per PR
- the run takes under 10 minutes

If it passes, pick 2 follows: simulator stills per pose on CI with `-qaPose`
(`/mnt/project-files/qa/faster-screen-testing-research.md`).

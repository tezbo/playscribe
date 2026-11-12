# Releasing to TestFlight

Nothing ships to TestFlight by itself. Merging to main never uploads a build; only a release tag does.

1. **Scope.** The release manager lists what is in `## x.y.z` of CHANGELOG.md, adds connected feature
   recommendations, and asks Terry whether anything else should go in. Every `## x.y.z` section ends with this
   standing line (Terry, 2026-11-06, while TestFlight feedback becomes public issues): "Feedback you send through
   TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details."
2. **Three sign-offs** on that exact commit, each naming its SHA:
   - **Backend and data** (QA thread): the feed, alerts and links for the release's games are right.
   - **Front end** (QA thread): docs/ux-acceptance.md passes in every pose, driven by taps, not stills alone: every
     row, card and control on a screen the release touches is tapped and lands where a player expects (a patch row
     opens that patch). Captures or a recording show each journey.
   - **UX and UI** (designer thread): the release keeps the core purpose, PS5 game update journals, clear and
     first, and new features fit without crowding it.
3. **On device.** Leo installs the signed-off commit on Terry's own iPhone Duo over USB from Xcode (Debug, the same
   SHA), so Terry can try it on real hardware before the review. Since 0.2.0 (Terry, 2026-11-02).
4. **Sprint review.** Terry gets a complete, working demo of every new feature in the release, built from the
   signed-off commit: simulator captures in each pose and a clickable walkthrough. The designer helps put it
   together. Go is asked for only at this review.
5. **Go.** Only after Terry says go: make sure the heading no longer says "(candidate, not released)" (it is dropped when the notes are final), then tag that commit
   `vX.Y.Z` and push the tag. `.github/workflows/testflight.yml` builds it, sets the version from the tag and
   the next build number, and uses the section as "What to Test".

**Checking a TestFlight build.** A TestFlight or App Store build carries a receipt, so the `playscribe://` QA routes
(including `playscribe://first-run`) do nothing there by design (#231). To see first run on such a build, delete the
app and install it again; use Settings, Reset to first run only on a developer build.

Versions: patch (0.2.1) for fixes only, minor (0.3.0) for features, 1.0.0 for the App Store launch.

## Bundle IDs and the Home Screen widget

`ios/project.yml` has one setting, `PLAYSCRIBE_BUNDLE_ID` (default `co.codeconnectors.playscribe`). The app uses it,
the widget is `<id>.widget` and the App Group is `group.<id>` (read at runtime from Info.plist `PlayscribeAppGroup`).
The release lane overrides it with the App Store Connect app's id (`tezbo.Playscribe`), so TestFlight builds use
`tezbo.Playscribe`, `tezbo.Playscribe.widget` and `group.tezbo.Playscribe`.

Registration. Automatic signing is the first plan: the first 0.5.0 release lane run (with `-allowProvisioningUpdates`
and the Admin API key) is expected to create the widget App ID `tezbo.Playscribe.widget` and the App Group
`group.tezbo.Playscribe` itself, and to add App Groups to `tezbo.Playscribe`. This is unverified until the lane runs.
The existing app record and identifier `tezbo.Playscribe` need no re-registration.

Fallback, only if the lane fails with "doesn't include the App Groups capability" or similar: Terry registers by hand.
1. developer.apple.com, Certificates, Identifiers & Profiles, Identifiers, App Groups, add `group.tezbo.Playscribe`.
2. Identifiers, `tezbo.Playscribe`, enable App Groups, select that group, Save.
3. Identifiers, add an App ID `tezbo.Playscribe.widget` (Explicit, no capabilities but App Groups with the same group).
4. Re-run the release lane. If it still fails with the same message, step 2 or 3 is missing.
No App Store Connect app record is needed for the widget.

## Deleting leftover branches

Agents' git pushes cannot delete remote branches (the proxy returns 403), so any agent runs **Delete leftover
branches** (`branch-delete.yml`, workflow_dispatch on `main`) with `branches` (space-separated `name@sha` pairs, up to
50), `approval` (the id or a quote of Terry's yes) and `dry_run` (run `true` first). It refuses kept branches (main,
`feed`, `ps5-index-update`, `backup/*`, `release/*`, `rc/*`), a moved tip, an open PR, and an unmerged branch unless
`allow_unmerged` is true, re-checks just before deleting, and prints a restore command per branch. `approval` quotes
Terry's yes or the coordinator's, under Terry's cloud admin grant (12 Nov 2026).

## Roadmap

The version plan and backlog live in docs/roadmap.md, owned by the product owner.

## Keeping the board current

The release manager keeps the release's card on the sprint board (https://claude.ai/artifact/T5NNq75hBh7Yu9SGt28BEU)
current at each gate. Update the card's `note` (the current SHA, which sign-offs are in, and what blocks), and add
one `activity` entry for each build, QA result and blocker, including Leo's steps since he cannot write to the board.
Use small writes and don't re-read the whole board.

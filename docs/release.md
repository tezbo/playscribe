# Releasing to TestFlight

Nothing ships to TestFlight by itself. Merging to main never uploads a build; only a release tag does.

1. **Scope.** The release manager lists what is in `## x.y.z` of CHANGELOG.md, adds connected feature
   recommendations, and asks Terry whether anything else should go in.
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
5. **Go.** Only after Terry says go: drop "(candidate, not released)" from the heading, then tag that commit
   `vX.Y.Z` and push the tag. `.github/workflows/testflight.yml` builds it, sets the version from the tag and
   the next build number, and uses the section as "What to Test".

Versions: patch (0.2.1) for fixes only, minor (0.3.0) for features, 1.0.0 for the App Store launch.

## Roadmap

The version plan and backlog live in docs/roadmap.md, owned by the product owner.

## Keeping the board current

The release manager keeps the release's card on the sprint board (https://claude.ai/artifact/T5NNq75hBh7Yu9SGt28BEU)
current at each gate. Update the card's `note` (the current SHA, which sign-offs are in, and what blocks), and add
one `activity` entry for each build, QA result and blocker, including Leo's steps since he cannot write to the board.
Use small writes and don't re-read the whole board.

# Releasing to TestFlight

Nothing ships to TestFlight by itself. Merging to main never uploads a build; only a release tag does.

1. **Scope.** The release manager lists what is in `## x.y.z` of CHANGELOG.md, adds connected feature
   recommendations, and asks Terry whether anything else should go in.
2. **Three sign-offs** on that exact commit, each naming its SHA:
   - **Backend and data** (QA thread): the feed, alerts and links for the release's games are right.
   - **Front end** (QA thread): docs/ux-acceptance.md passes in every pose.
   - **UX and UI** (designer thread): the release keeps the core purpose, PS5 game update journals, clear and
     first, and new features fit without crowding it.
3. **Go.** Only after Terry says go: drop "(candidate, not released)" from the heading, then tag that commit
   `vX.Y.Z` and push the tag. `.github/workflows/testflight.yml` builds it, sets the version from the tag and
   the next build number, and uses the section as "What to Test".

Versions: patch (0.2.1) for fixes only, minor (0.3.0) for features, 1.0.0 for the App Store launch.

## Roadmap

The version plan and backlog live in docs/roadmap.md, owned by the product owner.

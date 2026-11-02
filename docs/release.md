# Releasing to TestFlight

Nothing ships to TestFlight by itself. Merging to main never uploads a build; only a release tag does.

1. **Scope.** The release manager lists what is in `## x.y.z` of CHANGELOG.md, adds connected feature
   recommendations, and asks Terry whether anything else should go in.
2. **QA.** The QA thread tests that exact commit against docs/ux-acceptance.md and signs it off.
3. **Go.** Only after Terry says go: drop "(candidate, not released)" from the heading, then tag that commit
   `vX.Y.Z` and push the tag. `.github/workflows/testflight.yml` builds it, sets the version from the tag and
   the next build number, and uses the section as "What to Test".

Versions: patch (0.2.1) for fixes only, minor (0.3.0) for features, 1.0.0 for the App Store launch.

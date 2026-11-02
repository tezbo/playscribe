# Skills by role

What each agent must know and use. Roles and reporting lines are in `AGENTS.md`.

**Nadia, product owner**
- Product discovery for PS5 players: what changed, did it fix my thing, is it on my console, what's coming.
- Roadmapping and backlog grooming against the north star. Writing scopes as user outcomes, not features.
- Knowing what iPhone Duo makes possible (poses, Tabletop, side by side, reserved regions) from Apple's docs.

**Sam, delivery lead and scrum master**
- Turning a release theme into a sprint: tasks, owners and acceptance IDs.
- Running ideation, reviews and retros. Unblocking the team. Keeping the project dashboard and memory current.

**Theo, senior iOS engineer and release manager**
- Swift and SwiftUI architecture, the iOS 27 SDK and Duo APIs (`ArrangementView`, `ReservedRegion`), checked
  against the installed swiftinterface.
- GitHub Actions, TestFlight signing, semantic versioning, and the tag release in `docs/release.md`.
- Code review and merging. Running free-tier budgets.

**Priya, backend iOS and integration engineer**
- Steam store and news APIs, IGDB (Twitch auth), studio PS5 sources, and the rules in `docs/ps5-patch-data.md`.
- `npm test` and `typecheck` in `backend/`. The feed.yml actions: poll, backfill, confirm, dismiss, info.
- JSON feed design, APNs alerts, and fixture tooling (`ios/tools/build_fixtures.py`).
- Legal and ToS screening of sources: official only.

**Leo, full-stack iOS and web engineer**
- SwiftUI views and tests, xcodegen, the `xcodebuild … test` command in CLAUDE.md, the simulator and Duo poses,
  and captures with `tools/qa/shots.sh`.
- Accessibility (Dynamic Type, VoiceOver, Reduce Motion). Static web on GitHub Pages.

**Iris, senior iOS design manager**
- The HIG and Designing for iPhone Duo (baseline copies in project files, `qa/apple-baseline/`).
- Layout across poses, typography, motion, and brand tokens (`brand/`). UX acceptance criteria.

**Ezra, app artist, lore and documentation lead**
- Vector art and the brand toolchain (`brand/tools/`), App Store screenshots and the icon.
- Voice and copy: "update" for patches, "chapter" only for book sections. Tester-facing changelogs.

**Jun, playtester**
- Playing PS5 games and knowing how players follow updates (Reddit, Steam, PS App). Honest, ranked feedback.

**Quinn, QA lead**
- `docs/ux-acceptance.md` in every pose, feed and alert checks, and screenshot evidence saved per build.
- Writing reproducible bugs with acceptance IDs and the SHA.

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

**Mara, marketing and App Store lead**
- App Store Connect marketing surface: name, subtitle, keywords, promotional text, screenshots, app preview, In-App Events, Product Page Optimization, custom product pages. Checks limits against current Apple docs, never memory.
- Keyword research and competitor positioning (Patchbook.gg, Patch Pulse), web SEO basics, static sites on GitHub Pages.

# Repo skills (`.claude/skills/`)

Claude Code loads these on its own in any session that checks out the repo, and they are versioned with the code. Each `SKILL.md` description says when it triggers. Edit them by PR.

| Skill | Use it when |
|---|---|
| `five-pose-stills` | A UI change needs stills, a shoot list or a layout sign-off across the Duo poses. |
| `ax3-layout-check` | Adding or changing text-bearing SwiftUI, to avoid AX3 clipping, missing chips, overlap. |
| `precheck-loop` | About to push or open a PR without Xcode: push, read PRECHECK PASS/FAIL, fix, then PR. |
| `status-protocol` | A message is just "s", or a step is finished (`Next:` line). |
| `review-merge-handoff` | Requesting or giving a sign-off, or merging. |
| `playscribe-estimate` | Picking up, sizing or closing a card: `est_work`, `est_wait`, `basis`, then actuals (PERT, never invented). |
| `workaround-first` | About to say "can't", "only", "missing" or "needs Terry": check repo, other thread, build it, then report the route. |
| `playscribe-code-review` | Reviewing a diff with the repo rules first. |

**General skills.** Teammates also see the shared design, engineering, marketing and product-management skills (for example `engineering:code-review`, `design:accessibility-review`, `marketing:brand-review`, `product-management:write-spec`). Say "Skill: <name>" in the reply when you use one.

**Outside sources.** Candidates come from Anthropic's skills and agent docs and from the VoltAgent awesome-agent-skills list. That list only links to other repos, each with its own licence. Nothing is copied in until its licence is checked; a copied skill keeps its licence file and credit in its folder. Propose a new skill when the same gap shows up twice, to Gabrielle (the "Assess agents and plan skill growth" thread). Per-agent plans: `/mnt/project-files/team/improvement-plans.md`.

**Estimating.** Every card gets `est_work`, `est_wait` and `basis` at pick-up, and `actual_work` and `actual_wait` at Done (AGENTS.md, "Estimates"). No basis means `n/e` in both, never a guessed number. The method is the `playscribe-estimate` skill, built on `agent-estimate` (PERT three-point, from the Anthropic Directory; upstream vendored in `.claude/skills/agent-estimate/`, Apache-2.0, credit in `SOURCE.md`). The CLI install is approved (Terry, 2026-11-07: `pip install agent-estimate`); manual PERT is the fallback.

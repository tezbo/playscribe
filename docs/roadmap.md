# Product roadmap

Owner: the product owner thread. Terry sets direction; the release manager ships (docs/release.md).
Last updated 2 Nov 2026.

**Core purpose:** a PS5 player opens Playscribe and, in seconds, knows what an update changed, whether it
fixed their thing, and whether it's on their console. Everything else must make that faster or bring people
back to it. Steam is the source of truth, no game opens to a blank page, and we spend nothing.

## Version plan

### 0.2.0 "Complete journals" (in progress)
- Full update history for every game (Blue Prince fix).
- Cold launch opens on the home screen.
- Links open in the default browser; each game links its official site and patch notes.
- Recent chapters hero moved to 0.3.0 as the Latest updates hero (0.2.0 UX signed off at cca2c99 without it).

### 0.3.0 "Trust the notes"
Answers the questions a PS5 player actually has (from the gamer review, 25 Oct), plus the designer's 0.2.0 sign-off notes.
1. Latest updates hero on home (formerly Recent chapters; mock-up v3).
2. Tabletop links: one "Links" rail button opens a lower-half sheet (Official website, Patch notes, Steam notes);
   upper-half labels become secondary text so nothing above the fold looks tappable. **Required.**
3. Wording: an update is always "update"; "chapter" only means a book section. "What's new" for this patch,
   "All updates" for the history (replacing Changes and Changelog).
4. Reader leads with what changed; links and details sit below.
5. PS5 version number when the studio publishes one (never a PC number).
6. PC-only items (Steam Deck, mouse, PC graphics settings) folded under "PC only", not mixed into PS5 notes.
7. Search inside a game's notes ("did they fix the save bug?").
8. Catch-up: "Since you last opened" groups every patch you missed into one summary.
9. Games without backdrop art fill the band above the title with a cover crop or the ink plate.
10. "Checked" date refreshes when the history is fetched, or goes.
11. Tabletop eyebrow shows the game name or date, not the patch title twice.
12. Updates older than a game's PS5 launch (Blue Prince "Patch 1", Jun 2024) don't count as released on PS5.
13. Backend (Theo): 72-hour guard on reported alerts; alert when a "consoles later" update goes live.

### 0.4.0 "Stay in the loop"
- Watchlist for upcoming games: release dates, announcements and release-day alerts (Terry).
- Faster alerts: tighter feed schedule for followed games, within the free GitHub Actions budget.
- Home Screen widget: latest update across your library.
- Add several games at once, including from a screenshot of your PS App library.
- Follow a known issue and get an alert when a patch mentions it.

### 0.5.0 "Your gaming world"
- News for your games and series from official studio and PlayStation Blog posts (Terry).
- Similar games to your library (IGDB).
- Share an update as a card.

### 1.0.0 App Store launch
- Works well on every iPhone, best on iPhone Duo. Accessibility pass (Dynamic Type, VoiceOver, Reduce Motion).
- Light (vellum) and dark (ink) appearance (Terry).
- Siri and Shortcuts: "What's new in Wukong?"
- In-app feature suggestions from users, feeding this backlog (Terry).
- App Store listing, screenshots, privacy labels, support page on GitHub Pages; empty, offline and error states.

### Later: Sidekick / Field Guide (parked as a release, hidden trial planned)
A made-for-Duo strategy guide behind a Playscribe+ members-only gateway (Terry). Parked as a public release. A hidden,
internal-only trial for one game is planned after 0.2.0 ships. Brief: docs/game-guide.md.

## Backlog (not scheduled)

- Parked: patch size hint (only 3% of PS5 updates list a size).
- Parked until Sony opens an official route: trophy data (Terry), PlayStation sign-in, price watch.
- Other consoles once PS5 is excellent.

## Suggestions and agent ideas

Every agent is empowered to pitch its own ideas at any time, not only in ideation (Terry, 2 Nov). Pitches and Terry's
suggestions go on the live sprint board (https://claude.ai/artifact/T5NNq75hBh7Yu9SGt28BEU) and in the suggestion box on the visual roadmap
(https://claude.ai/artifact/2uRr1xdcv4xLRvwvMao6k4). Nadia decides each one:

- **Approve:** place it in the release whose theme it strengthens, with the reasoning.
- **Park:** keep it in the backlog with the reason (no official source, costs money, wrong time).
- **Escalate to Terry:** when it's unclear the idea fits the vision, or it changes cost, monetisation, data sources
  or the core purpose.

Releases are packaged by theme, never by cramming in the newest ideas. Other agents are encouraged to challenge a
pitch on the board before Nadia decides.

## Release cycle

Owners and roles are in AGENTS.md. Each minor release runs once through this cycle.

1. **Ideation.** Every agent pitches one to three ideas to Nadia. Nadia and Sam groom them into one release theme.
2. **Plan.** Theo and Nadia pick the version's scope from this file, and Terry agrees it.
3. **Build.** Sam runs it as a sprint. Priya and Leo build it, Iris and Ezra design ahead of the build, and work
   merges to main. Merging never uploads anything. Every PR cites acceptance IDs.
4. **Freeze.** Theo names one RC SHA.
5. **Test that SHA.** Quinn signs off backend/data and front end, Iris signs off UX/UI, and Jun playtests. Fixes
   make a new RC, and only the diff is re-checked.
6. **Sprint review.** Leo captures, Iris builds the walkthrough, and Theo presents it to Terry with the CHANGELOG section.
7. **Ship.** Terry says go, then Theo tags `vX.Y.Z` and TestFlight ships it (docs/release.md).
8. **Retro.** Each agent sends Sam one keep and one change. Leftovers and new ideas go back to the backlog.

Patch releases (0.x.1) skip ideation and the sprint review, and still need steps 4, 5 and Terry's go.

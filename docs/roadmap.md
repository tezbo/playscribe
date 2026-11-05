# Product roadmap

Owner: the product owner thread. Terry sets direction; the release manager ships (docs/release.md).
Last updated 3 Nov 2026.

**Core purpose:** a PS5 player opens Playscribe and, in seconds, knows what an update changed, whether it
fixed their thing, and whether it's on their console. Everything else must make that faster or bring people
back to it. Steam is the source of truth, no game opens to a blank page, and we spend nothing.

## Version plan

### 0.2.0 "Complete journals" (in progress)
- Full update history for every game (Blue Prince fix).
- Cold launch opens on the home screen.
- Links open in the default browser; each game links its official site and "All patch notes", and each update
  has "Open in Steam" (Terry).
- Recent chapters hero moved to 0.5.0 as the Latest updates hero (0.2.0 UX signed off at cca2c99 without it).

### 0.5.0 "Know your games" (0.3.0, 0.4.0 and 0.5.0 merged into one release, Terry 3 Nov)
One release, ordered by value. The core purpose comes first, then staying in the loop, then the wider gaming world.
Engineering = Theo (lead), Priya. Design = Iris (lead), Ezra. Leo builds the app work in both columns.
The Field Guide trial (docs/game-guide.md) stays hidden and is not part of this release's sign-off.

**A. Trust the notes (core purpose, ship first)**
| # | Item | Eng | Design |
|---|---|---|---|
| 1 | Latest updates hero on home (mock-up v3) | Leo | Iris |
| 2 | Tabletop Links rail button and lower-half sheet (**required**); upper-half labels read as secondary text | Leo | Iris |
| 3 | Reader leads with what changed; wording "What's new" and "All updates"; an update is always "update" | Leo | Iris, Ezra (copy) |
| 4 | PS5 version number when published, never a PC number; PC-only items folded under "PC only" | Priya | Iris |
| 5 | Search inside a game's notes | Leo | Iris |
| 6 | Catch-up: "Since you last opened" | Leo | Iris |
| 7 | Game page status glyph: the inline owned glyph shipped in 0.2.0. Remaining: wishlist and watching glyphs, and website and All patch notes on one row | Leo | Iris (VoiceOver text) |
| 8 | Faded key-art header as default, generic landscape last resort (spec: header-fade handoff). No game opens to a blank page. | Leo | Iris, Ezra (landscape art) |
| 9 | "Checked" date refreshes with the history; Tabletop eyebrow shows game name or date; pre-launch patches not counted on PS5 | Priya, Leo | Iris |
| 10 | Settings notifications redesign: built in 0.2.0, nothing left here | | |

**B. Stay in the loop**
| # | Item | Eng | Design |
|---|---|---|---|
| 11 | Backend: 72-hour guard on reported alerts; alert when a "consoles later" update goes live; faster alerts: a hot set (games with a patch in the last 14 days plus a pinned list of up to 12) polled about every 30 minutes, everything else hourly; follows live on devices, so this is not per-user; the repo is public, so the Actions minutes are free | Theo, Priya | |
| 12 | Add flow: + menu with Scan with camera, From a photo, Say it, Type it; decline-camera fallback; first-run welcome and guided add. API check first (Vision, DataScanner, Foundation Models against the SDK). | Leo, Priya | Iris, Ezra |
| 13 | Add games multi-select: shipped in 0.2.0 as the pinned "Add N games" bar with tap-to-select (Terry agreed), instead of a Select multiple toggle. Nothing left here | | |
| 14 | Watchlist for upcoming games: release dates, announcements, release-day alerts | Priya, Leo | Iris |
| 15 | Home Screen widget: latest update across your library | Leo | Iris |
| 16 | Follow a known issue and get an alert when a patch mentions it | Priya, Leo | Iris |

**C. Your gaming world**
| # | Item | Eng | Design |
|---|---|---|---|
| 17 | Official studio news for your games and series (Steam news only; no PlayStation Blog until we have written permission, its terms bar automated access) | Priya | Iris |
| 18 | Similar games to your library (IGDB) | Priya | Iris |
| 19 | Share an update as a card | Leo | Iris, Ezra |

Cut line: if time runs short, items 16 to 19 move to 0.6.0 first. A and B11 to B13 ship together or not at all. Item 12 needs an SDK feasibility check first, as step one of block B. Engineer order: A1, A2, A3, A8, A5, A6, A9, A7 remainder, then B.

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

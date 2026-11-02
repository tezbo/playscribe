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
- Faster alerts: tighter feed schedule for followed games, within the free GitHub Actions budget.
- Home Screen widget: latest update across your library.
- Add several games at once, plus suggested popular PS5 games on first run.
- Upcoming release dates and new game announcements for games and series you follow (first of Terry's ideas).

### 1.0.0 App Store launch
- Works well on every iPhone, best on iPhone Duo.
- Accessibility pass (Dynamic Type, VoiceOver, Reduce Motion) and the HIG baseline in qa/.
- App Store listing, screenshots, privacy labels, support page on GitHub Pages.
- Empty, offline and error states for every screen; crash-free TestFlight run with outside testers.

## Backlog (not scheduled, roughly ranked)

1. Similar games to your library (needs a free data source; IGDB is the candidate).
2. Share an update as a card (image + one-line summary).
3. Siri and Shortcuts: "What's new in Wukong?"
4. Patch size and "download now" hint before you play.
5. Follow a known issue and get told when a patch mentions it.
6. Price watch for DLC and games with deal alerts. Parked: no official, free PS Store price source.
7. PlayStation sign-in to import your library. Parked: official auth only.
8. Other consoles (Xbox, Switch 2) once PS5 is solid.

## Release cycle

Owners and roles are in AGENTS.md. Each minor release runs once through this cycle.

1. **Ideation.** Every agent pitches one to three ideas to Nadia. Nadia and Sam groom them into one release theme
   with a short scope in this file.
2. **Scope.** Nadia sends Terry the theme and scope. Terry approves or changes it.
3. **Build.** Sam turns the scope into a sprint. Theo, Priya and Leo build it, with Iris and Ezra designing ahead
   of the build. Every PR cites acceptance IDs.
4. **Test.** On one candidate SHA: Quinn signs off backend/data and front end, Iris signs off UX/UI, and Jun
   playtests. Fixes loop back to step 3.
5. **Review.** Sam shows Terry a short demo: screenshots for each pose plus the CHANGELOG section.
6. **Ship.** Terry says go, and Theo tags the release, which goes to TestFlight (docs/release.md).
7. **Retro.** Each agent sends Sam one keep and one change. Leftovers and new ideas go back to the backlog.

Patch releases (0.x.1) skip steps 1, 2 and 5 and still need step 4 and Terry's go.

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
- Recent chapters hero carousel: **ship only if signed off with the rest; otherwise first item of 0.3.0.**

### 0.3.0 "Trust the notes"
Answers the questions a PS5 player actually has (from the gamer review, 25 Oct).
- Reader leads with what changed; links and details sit below.
- PS5 version number when the studio publishes one (never a PC number).
- PC-only items (Steam Deck, mouse, PC graphics settings) folded under "PC only", not mixed into PS5 notes.
- Search inside a game's notes ("did they fix the save bug?").
- Catch-up: "Since you last opened" groups every patch you missed into one summary.
- Recent chapters hero, if it slipped from 0.2.0.

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

## How the product owner works

- Keeps this file current and proposes each version's scope to the release manager.
- Brings Terry only real product calls (scope changes, anything that costs money, anything touching the core).
- Ideas from any thread land in the backlog here, ranked against the core purpose.

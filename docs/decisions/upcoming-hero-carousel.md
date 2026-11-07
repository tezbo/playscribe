# Decision note: Upcoming hero becomes a carousel

Date 2026-11-07 / owner: this thread / card: Terry's Upcoming screenshot (short form). Acceptance: J-11, G-4, G-9. Builds on #348.

1. **Why:** Terry's Tabletop Upcoming screen fronted one game ("Ova Magica"); the half of the screen with the most art should show what is coming, not one game. He asked for auto-scroll that can also be swiped.
3. **Worth:** north-star fit (in the know about upcoming games) for one small view plus one control; no new data. Guess: 5 slides at 8 s is about right; Iris may tune it.
4. **Alternatives:** (a) leave one game, zero cost, but wastes the stage; (b) swipe the stage itself, breaks G-4 (nothing tappable above the fold), so rejected; (c) dots only, no auto-advance, simpler but Terry asked for auto.
5. **Decision:** the stage cycles up to 5 games (watched first, then the catalogue's next) every 8 s with a cross-fade. A control strip in the lower half holds the dots, a pause/play button and the swipe (the stage stays view-only). Auto-advance stops on pause, any touch of the strip, VoiceOver, Switch Control, Reduce Motion (G-9) and accessibility sizes; the dots still work. Caption block is fixed height; VoiceOver hears \"Game n of N\" on manual changes only (Iris). Only Tabletop has a stage, so other poses are unchanged. Nadia and Iris input requested via coordinator.
6. **Learning:** a swipeable hero in Tabletop must put its gesture in the lower half; the stage only mirrors the selection.

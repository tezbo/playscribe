# Decision note: one News tab, not two (short form)

Date 2026-11-12 / owner: News thread / cards: #232 (N-9 → J-13), #443.

1. **Why:** #232 (global News tab, 5 Nov) and #443 (News as its own tab, J-13, 9 Nov) were built in parallel. Merging main into #232 left two News tabs, two stores of the same headlines and a `news.json` export nothing on main reads.
2. **Goal still needed:** yes. Terry's ask was a global feed across games that works on device; #443 delivers it, and Iris's #232 review found three Tabletop and Book defects that are on main too.
3. **Value/cost:** keeping both costs a second code path forever; dropping #232's view costs nothing players see.
4. **Alternatives:** (a) keep #232's view and drop #443's: throws away the signed v0.5.3 work and the per-game cap. (b) Keep `news.json` for a later "all games, not only the library" widening: unused bytes on the feed every hour; it can come back with that card.
5. **Decision:** main's `NewsView` is the News tab. #232 keeps only what main lacks: the Tabletop stage (newest story, hero art and scrim, headline below the title), the rail with three tabs and News as the last control at 8 pt gaps, Book cards 24 pt from the hinge, the per-game News chapter in Tabletop's lower half with its art on the stage, and `-qaNews` seeding for stills. The Library strip, `GlobalNewsView`, `news.json` and `library/news` are gone.
6. **Learning:** when a card sits in review for days, check main for a sibling before each merge of main; the second one to merge pays.

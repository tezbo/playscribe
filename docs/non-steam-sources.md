# Non-Steam games: source options (Priya, 3 Nov 2026)

Question: which official studio pages could cover games with no Steam feed (Rocket League, Valorant, Minecraft, Fortnite, Genshin Impact and the Sony first-party games)? Probed each page's robots.txt and fetchability on 3 Nov 2026 with the Playscribe user agent, and read the terms where they were reachable.

| Game | Page | Result |
|---|---|---|
| Rocket League | rocketleague.com/en/news | 403 to automated fetches. Rule: mark manual, do not work around. |
| Minecraft | feedback.minecraft.net changelogs | 403. Same. minecraft.net timed out. |
| Fortnite | fortnite.com/news | 403, robots.txt also 403. Same. |
| Valorant | playvalorant.com/en-us/news/game-updates/ | Fetchable, robots.txt allows it, patch links in the listing (`valorant-patch-notes-13-09`). Riot's Terms of Service bar anything that would "mine, scrape or expropriate any system, data" without saying whether public pages count. Unclear, so not added. |
| Genshin Impact | genshin.hoyoverse.com/en/news | Fetchable but the page is a client-side app; no links to read without running scripts. Not added. |
| Gran Turismo 7 | gran-turismo.com/us/gt7/news/ | Fetchable, robots.txt allows it, but the listing has no patch links to read and the terms page was not found (404). Not added. |
| Ghost of Yōtei, Astro Bot, Wolverine, Alan Wake 2 | studio sites | Sucker Punch and Remedy sites fetch fine and have no patch-note listings; Insomniac's certificate is invalid for its host; Team Asobi was unreachable. Sony-owned sites sit under SIE terms, the same family as the PlayStation Blog problem (docs/ps5-patch-data.md, open check). |

## What I did not do

I did not add a scraper for any of these. The existing `html` source kind only turns patch-looking links into review items for a person; it never makes a release by itself, so adding Valorant would add review work without adding history. Making an article scraper means reading terms that are unclear or silent for every candidate, and we are going to the App Store, so I would rather ask than guess.

## Options for Theo and Terry

1. **Keep as is.** Press-only reports are not shown, so these games show only what a person adds. Cheapest and safest.
2. **Hand-entered releases** for the biggest ones through the existing confirm flow plus `links` added by hand. A person pastes a patch note summary or just the link. No terms issue; costs a person's time.
3. **Ask for permission.** Riot, Mojang, Epic and Psyonix each have developer or partner contact routes; a written yes would unlock their pages (the 403s are the sites saying no to bots, so a key or allowlisting would have to come from them).
4. **wiki.gg** is only for non-Steam games, per Terry. Of the games here, none has a wiki.gg patch-notes page I could confirm today, so there is nothing to wire up yet. Blue Prince is on Steam, so it stays on Steam.

Recommendation: option 2 for Valorant and Rocket League only if their users ask for it, and option 3 as the path to real coverage.

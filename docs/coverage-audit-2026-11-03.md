# Feed coverage audit, 3 Nov 2026 (Priya)

Run with `npm run coverage-audit` in `backend/` against the live feed (68 games, 1,298 releases at the time).

## Findings

| Finding | Count | Action |
|---|---|---|
| Steam-assumed PS5 rows dated before the game's PS5 launch (bg3 16, enshrouded 1, hades-2 1, indiana-jones 1, mh-wilds 1) | 20 | Fixed: `dropPreLaunchPs5` runs every ingest and removes them. These rows were made before IGDB gave the PS5 date. Official and press-sourced rows are never touched. |
| PS5 version equal to the PC version | 0 | None. |
| Games with 0 releases | 5: cod-mw4, gta5, minecraft, rocket-league, valorant | gta5 and warframe/destiny-2 are live-service: Steam carries events, not patch notes, so the news shard (headlines) is their coverage. cod-mw4's Steam news returned nothing. minecraft, rocket-league and valorant have no Steam source (Epic, Riot, Mojang): Q2, non-Steam sources. |
| Games whose releases all lack links (no Steam or studio source): alan-wake-2, astro-bot, gt7, wolverine, yotei, fortnite, genshin-impact | 7 | Q2. Press-only reports are not shown (no Unconfirmed state), so these games show little until a studio source exists. |
| Games with PC rows only, no PS5 row at all: ff16, ghost-of-tsushima, poe2 | 3 | Expected: Sony and Square Enix ports (`steamIsPcPort`) and a game whose PS5 build has not launched. |
| Releases with no PS5 row (PC-only patches, port patches, pre-launch) | 284 of 1,298 | Expected. |

## 30 popular PS5 titles outside the catalog

Checked each against Steam's news API: 16 have healthy patch-note history and a PS5 build, so they are added to the registry (Steam source only, IGDB id resolved from the Steam app id at seed): Dragon's Dogma 2, Mortal Kombat 1, Persona 3 Reload, Resident Evil 4, Resident Evil Village, Star Wars Outlaws, Metaphor: ReFantazio, Cult of the Lamb, Stardew Valley, Monster Hunter: World, It Takes Two, Ready or Not, PAYDAY 3, Remnant II, Star Wars Jedi: Survivor, Hunt: Showdown 1896.

Not added: God of War Ragnarök, Horizon Forbidden West, The Last of Us Part II (Sony PC ports, so Steam says nothing about PS5; they need a studio source, Q2); Red Dead Redemption 2, Terraria and Like a Dragon: Infinite Wealth (no patch-style posts in recent Steam news); Sons of the Forest (no PS5 build); Black Ops 6 (Call of Duty patch notes are not on Steam); Fallout 4 and Skyrim (PS5 builds are the PS4 version; Steam notes are PC-specific); Dead Space (last post 2024).

## Not verified

The IGDB-side checks (cover, art and PS5 dates for the 16 new games) only run in the Actions feed job, which has the Twitch keys. Check the next feed run.

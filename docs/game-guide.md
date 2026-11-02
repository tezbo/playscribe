# Field Guide (hidden members-only trial)

Owner: Nadia. Status: brief, build held until 0.2.0 ships (Terry, 2 Nov 2026). Sidekick as a public release is parked.

**Goal.** Bring the classic strategy guide back to life, made for iPhone Duo: the excitement of a printed guide,
with a live map and walkthrough that every pose presents differently. It sits behind a members-only gateway that
replaces the "My book" badge. For now it's a hidden trial: internal builds only, one game.

## Name

Recommended: **Field Guide** (badge "Field Guide" with a lock glyph until unlocked). Alternatives: "Full game guide",
"Strategy Guide", "Atlas". The membership is **Playscribe+**.

## Poses (Iris owns the layouts; nothing tappable above the fold in Tabletop)

| Pose | What it shows |
|---|---|
| Closed | "Where am I": your current chapter, next objective, and a checklist of collectibles nearby. |
| Tabletop | Upper half: the map, a view-only stage that pans, zooms and lights up pins as the walkthrough moves. Lower half: swipeable walkthrough steps, plus rail toggles for map layers (collectibles, bosses, merchants, secrets) and "show on map". The map is interactive *through* the lower half, which keeps the Tabletop rule. |
| Open, book | A guide spread: walkthrough on the left page, map plate or boss card on the right, turning like pages. |
| Open, flat | The full atlas with every layer, and the codex (characters, lore, series history). |

## Guide devices to carry over (from docs/guide-references.md)

Terry's reference is a classic official strategy guide. We keep its devices and draw them in Playscribe's own art:
- **Chapter thumb tabs** on the outer page edge in book pose, so the guide has a geography you can find by feel.
- **Numbered walkthrough steps** under place-named section banners, with **Tip** callouts for optional depth.
- **Numbered collectible cards** (bestiary, items) with element chips and a completion count, so it reads as a checklist you want to finish.
- **Full-page location plates** in our ink style, and an **Extras** chapter for lore and art.
- Closed pose shows the current boss's weaknesses as element chips next to the next step.

## The gateway

- A "Field Guide" badge where "My book" is today. Locked, it opens a preview spread and the Playscribe+ offer.
- StoreKit 2 subscription, tested with the sandbox and StoreKit configuration only. Sandbox and TestFlight purchases
  are free, so the trial costs nothing.
- Hidden behind a feature flag and a `-qaRoute guide/<game>` route. It never appears in a TestFlight build for
  outside testers until Terry says so.

## Content (the hard part)

IGN wikis and GameFAQs guides are the right *feel* but we can't use their content: it's copyrighted by IGN or by
each guide's author, and both sites' terms forbid reuse. Allowed sources, best first (Terry chose 1 and 2 for the trial):

1. **Our own content.** Ezra writes the walkthrough and draws a stylised map for the trial game.
2. **CC BY-SA wikis** (Fandom, wiki.gg): reusable with attribution and share-alike, so credit them as we already do
   for wiki.gg.
3. **Licensed guides** later: partner with guide writers or studios (a revenue share fits Playscribe+).

Trial game: **The Blood of Dawnwalker** (our demo game). Scope: one region, with a walkthrough, map layers, two boss
cards and a short codex.

## Decisions

- Content (Terry, 2 Nov): our own content plus CC BY-SA wiki text, credited in the guide. No IGN or GameFAQs content.
- Name: "Field Guide" is the working name until Terry says otherwise.

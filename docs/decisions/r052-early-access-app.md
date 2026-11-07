# r052-early-access-app

Short form. Goal: show an early-access game's two dates (Priya's `ea`/`fr`/`frq` in the bundled index, Quinn's rule) without ever saying "TBA".

- Chosen: `CatalogGame` carries `earlyAccessSince`, `fullRelease`, `fullReleasePrecision`. `ps5DateLine` reads "Early access since <day>" and a new `fullReleaseLine` reads "Full release <day>", or the month, quarter or year when `frq` says so. Both only while `fr` is after today (UTC day); after that the game reads as an ordinary release. Add-game rows show the two lines.
- Alternative: infer "year" from a 31 Dec date (rejected: Priya added `frq`). Doing nothing leaves PoE2 and Starseeker reading as plain releases.
- Not in this PR: the feed-side `eaSince`/`fullRelease` on the game page (the feed run is still finishing); a follow-up once it is live.

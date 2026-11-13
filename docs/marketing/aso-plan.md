# ASO and launch plan (draft v0.1)

Owner: Mara. Reviewers: Nadia (positioning), Iris and Ezra (screenshots). Public-safe: no personal names, no source names,
no QA routes. Publisher is CodeConnectors.

## Verified Apple limits (checked 5 Nov 2026)

| Field | Limit | Source |
|---|---|---|
| App name | 30 characters | [Product page](https://developer.apple.com/app-store/product-page/) |
| Subtitle | 30 characters | same |
| Keywords | 100 (page says characters, the Connect reference says bytes; we plan to 100 bytes, which is the safe reading), comma separated, no spaces | [Product page](https://developer.apple.com/app-store/product-page/), [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
| Promotional text | 170 characters, editable without a new build | both |
| Description | 4000 characters, plain text | Platform version information |
| What's New | 4000 characters, required after v1 | same |
| Screenshots | up to 10 per localization | Product page |
| App previews | up to 3, up to 30 seconds each | Product page |
| Support URL | required, must lead to real contact information | Platform version information |

**Still to verify before submission:** exact screenshot sizes and whether iPhone Duo has its own slot (screenshot
specifications page), privacy policy URL rules, In-App Events and Product Page Optimization limits, and the review
guidelines on names and keywords.

## Positioning

For PS5 players who want to know, fast, what an update changed and whether it is on their console. Competitor: Patchbook.gg
is Steam-only and web-only. Our edge: PS5-first ("on PS5" means a PS5 row, live and official),
a game-book reading experience, and a Duo layout in every pose. Never claim more than the app does.

## URLs (live 6 Nov 2026)

- Marketing: https://playscribe.codeconnectors.co/
- Privacy: https://playscribe.codeconnectors.co/privacy.html
- Support: https://playscribe.codeconnectors.co/support.html

Support shows an email only for now; confirm Apple's support URL requirement before submission.

## Metadata draft (for Nadia's sign-off)

- Name: `Playscribe: PS5 Patch Notes` (27)
- Subtitle: TBD (the old tagline was dropped 9 Nov; needs a new line, max 30)
- Keywords (no repeats of name/subtitle words, no competitor names, no other brands):
  `changelog,hotfix,gaming,tracker,game news,wishlist,library,release dates,foldable,duo,alerts,widget`
- Promotional text (170 max, 152 used): `Every update for the games you play, told in plain words. Built for the fold: two pages in Book, a reader in Tabletop, and quiet alerts when it matters.`

Keyword volume and difficulty need a paid tool or live Search Ads data; we spend nothing, so we start from this reasoned
set and tune from App Store Connect analytics after launch.

## Screenshot story (up to 10 frames, one claim each; refreshed for 0.5.5, 13 Nov 2026)

1. Closed: front cover, the deck behind it. "Your games, closed like a book." (Closed pose only; Open, Book and Tabletop go straight to the Library.)
2. Latest updates hero: "What changed, at a glance."
3. Reader leading with what changed, with the unread mark: "Read it like a book." Opening an update marks it read; use a Library with a mix of read and unread (R-6a).
4. PS5 tag and verification: "Know if it's on your PS5."
5. Alerts and widget: "Told when it lands."
6. Follow list (N-9): "Tell it which games to keep up to date." Frame must show the opt-in wording as shipped, including what leaves the phone and the Settings toggle. Terry approved the wording on 12 Nov 2026 (#455); use it as shipped.
7. Duo Tabletop: "Made for the fold." Stage above shows the trailer poster, controls below (R-11).
8. Duo Open/Book: "Two pages, one story." Video reflections show in the mirror in all three poses (R-11, G-9); pick the pose where the reflection reads best.
9. Library and add flow: "Your games, in seconds."

Order is a hypothesis, not a result: the first three frames carry the install decision, so Product Page Optimization tests
at 1.0 reorder them. Frame 6 ships only if the follow list is in the release build the store set is shot from.
Rules: real app captures, no source names, no fabricated data (use sample games the app ships).

## Launch plan

- 0.5.2: this plan, placeholder site (privacy and support URLs), metadata locked.
- 1.0.0: screenshots, preview video, In-App Event for launch, Product Page Optimization tests (name-free variants of
  screenshot order and first frame), custom product pages per audience (Duo owners vs general PS5).
- Measure: impressions to page views to downloads in App Store Connect analytics.

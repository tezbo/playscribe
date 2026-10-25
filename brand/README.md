# Playscribe brand

Live board: https://claude.ai/artifact/8mRkcMcHMa3jox19BszVpb

**Mark.** An open book whose spine is the hinge, with a spark rising from it. The spark's long lower point, slit and breather hole make it a pen nib (the scribe). The left page holds patch-note lines. The right page holds a line and a console-style update bar, part filled in ember. In the wordmark the spark dots the i. Below 24 pt use `logo/mark-small.svg`, which drops the nib cut and the page details.

**Voice.** The tagline is "Every update, a new chapter". Copy always invites the player back: what changed, then "Catch up, then jump back in". Write like a fellow player, not a changelog.

**Console cues.** These come from shared console vernacular, never from PlayStation's own marks:
- the update bar: in the mark, and filling on the splash
- the lit inner edge on the selected game tile
- the ember version chip ("v1.1")

**Colour.** `tokens.json` is the source of truth. Ink is the ground, vellum is pages and text, ember is the accent and is reserved for interactive elements and unread state. Every text colour passes WCAG AA on Ink 900 down to Ink 600. Text and glyphs on an ember fill always use `accent.on` (#2A1600), never white. Dark is the default.

**Type.** Literata (titles) and Instrument Sans (everything else), both SIL OFL, in `fonts/`. Each style maps to an iOS text style with `Font.custom(_:size:relativeTo:)`, so it scales with Dynamic Type up to AX5. List all eight files under `UIAppFonts`.

## App icon

Checked against Apple's HIG, App icons (updated 8 June 2026) and "Creating your app icon using Icon Composer":
iOS icons are one 1024x1024 layered design. Appearances are default, dark, clear light, clear dark, tinted light and tinted dark, and the system generates any you don't provide.

- **Icon Composer (preferred).** Drag the `app-icon/layers/` folders into Icon Composer. Folders become groups, back to front: `1-pages`, `2-notes` (lines and update bar), `3-spark`. The layers have no background, as Apple asks. Set the background in Icon Composer to a linear gradient from `#3B2D57` (top) to `#141019` (bottom). For dark, use `#1C1824` to `#08070B`. Keep the default Liquid Glass settings. Save it as `AppIcon.icon` in the Xcode project.
- **Asset catalog fallback.** `ios/AppIcon.appiconset` has the single-size light, dark (transparent background) and tinted (grayscale) PNGs, as Apple's "Configuring your app icon" asks.

## Splash and closed Library hero

- The native launch screen is plain Ink 900, with no logo (HIG, Launching).
- The branded splash plays on the first launch after install only: 0.8 s hold while the ember update bar fills from 0 to 100%, like a console update installing, then a 0.3 s fade. Under Reduce Motion it is a plain fade with the bar shown full, and never when the app opens from a notification. `splash/*.svg` shows each posture. In Book posture "Play" and the tagline sit on the left page, and "scribe" and the bar sit on the right. Nothing crosses the hinge.
- **No open-device outer cover.** iPhone Duo gives apps no way to draw on or take touches from the outer display while the device is open. The only outer-display content while open is the rear-camera capture preview for registered camera accessories ("Preparing your app for iPhone Duo"), and the simulator reports the outer panel as inactive.
- **Closed Library hero: framed, not badged.** The closed Library leads with the Continue game's key art. Playscribe's own frame around the art is what says "this is the app, not the game". There is no logo or badge on the art, because HIG Branding advises against repeating your logo or app name in the UI.
  - The art sits in a card inset 14 pt from both edges, below the large title, with 14 pt continuous corners at the top.
  - The card's bottom edge follows the open book's lower silhouette: straight at both sides, dipping 16 pt to the centre like the pages meeting at the spine. Draw it as two quad curves (see `library/closed-hero.svg`).
  - The selected game gets a lit inner edge: 1.5 pt vellum 100 at 60% opacity, inset inside the frame and following its corners. It is decoration with no accessibility trait. It must never look like a focus ring, because Full Keyboard Access draws its own.
  - Below the art, on ink: "NEW CHAPTER" in Instrument Sans caption with ember and 0.08 em tracking, followed by the version chip (an ember outline at 70% opacity, 19 pt tall, pill-shaped). Then the game title in Literata title2, then the invite line in subheadline secondary, for example "Update 1.1 is here. Catch up, then jump back in." The game's own logo stays inside its art and is never redrawn by us.
  - The whole card, frame plus text, is one button, at least 44 pt, with a VoiceOver label like "New chapter, Update 1.1, The Blood of Dawnwalker". The inner edge and the dip are decoration only.
  - In tabletop the framed art moves to the upper half and is display-only. The NEW CHAPTER label, chip, title, update line and tap target stay in the lower half.
  - The large title "Library" in Literata and the ink and vellum chrome carry the brand everywhere else.

## Glyphs

`ios/symbols/swap-sides*.svg` is Swap sides: two facing pages from the mark, traded across the spine by a flat left/right arrow pair. It uses a 24 pt grid and 1.6 pt strokes, close to SF Symbols Regular. It comes as an outline and a fill. The buttons are a 30 pt circle with the glyph at 17 pt, in ink 700 with vellum, or ember with `accent.on` (never white). To make a true SF Symbol, open the SF Symbols app on the Mac, export the template for `book` (Regular-S), paste `swap-sides.svg` into the Regular-S group, then validate and import the template into the asset catalog as a Symbol Image. That can't be done off a Mac. Until then, use the SVG as a template image with Preserve Vector Data turned on.

## PlayStation

Don't use the PlayStation or PS5 logos, the four button shapes, or PlayStation blue. Use "PS5" only as plain descriptive text, and show the notice in `tokens.json` (`voice.trademarkNotice`) in About.

## Rebuild

    pip install fonttools uharfbuzz
    python3 brand/tools/gen.py
    NODE_PATH=$(npm root -g) node brand/tools/render.mjs

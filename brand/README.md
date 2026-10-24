# Playscribe brand

Live board: https://claude.ai/artifact/8mRkcMcHMa3jox19BszVpb

**Mark.** An open book whose spine is the hinge, with a spark rising from it. The spark's long lower point, slit and breather hole make it a pen nib (the scribe). In the wordmark the spark dots the i. Below 24 pt use `logo/mark-small.svg`, which drops the nib cut.

**Colour.** `tokens.json` is the source of truth. Ink is the ground, vellum is pages and text, ember is the accent and is reserved for interactive elements and unread state. Every text colour passes WCAG AA on Ink 900 down to Ink 600. Text and glyphs on an ember fill always use `accent.on` (#2A1600), never white. Dark is the default.

**Type.** Literata (titles) and Instrument Sans (everything else), both SIL OFL, in `fonts/`. Each style maps to an iOS text style with `Font.custom(_:size:relativeTo:)`, so it scales with Dynamic Type up to AX5. List all eight files under `UIAppFonts`.

## App icon

Checked against Apple's HIG, App icons (updated 8 June 2026) and "Creating your app icon using Icon Composer":
iOS icons are one 1024x1024 layered design. Appearances are default, dark, clear light, clear dark, tinted light and tinted dark, and the system generates any you don't provide.

- **Icon Composer (preferred).** Drag the `app-icon/layers/` folders into Icon Composer. Folders become groups, back to front: `1-pages`, `2-spark`. The layers have no background, as Apple asks. Set the background in Icon Composer to a linear gradient from `#3B2D57` (top) to `#141019` (bottom). For dark, use `#1C1824` to `#08070B`. Keep the default Liquid Glass settings. Save it as `AppIcon.icon` in the Xcode project.
- **Asset catalog fallback.** `ios/AppIcon.appiconset` has the single-size light, dark (transparent background) and tinted (grayscale) PNGs, as Apple's "Configuring your app icon" asks.

## Splash and closed Library hero

- The native launch screen is plain Ink 900, with no logo (HIG, Launching).
- The branded splash plays on the first launch after install only: 0.8 s hold, 0.3 s fade, plain fade under Reduce Motion, and never when the app opens from a notification. `splash/*.svg` shows each posture. In Book posture "Play" and the tagline sit on the left page, "scribe" on the right, and nothing crosses the hinge.
- **No open-device outer cover.** iPhone Duo gives apps no way to draw on or take touches from the outer display while the device is open. The only outer-display content while open is the rear-camera capture preview for registered camera accessories ("Preparing your app for iPhone Duo"), and the simulator reports the outer panel as inactive.
- **Closed Library hero: framed, not badged.** The closed Library leads with the Continue game's key art. Playscribe's own frame around the art is what says "this is the app, not the game". There is no logo or badge on the art, because HIG Branding advises against repeating your logo or app name in the UI.
  - The art sits in a card inset 14 pt from both edges, below the large title, with 14 pt continuous corners at the top.
  - The card's bottom edge follows the open book's lower silhouette: straight at both sides, dipping 16 pt to the centre like the pages meeting at the spine. Draw it as two quad curves (see `library/closed-hero.svg`).
  - A 1 pt vellum 300 hairline at 35% opacity outlines the card.
  - Below the art, on ink: "CONTINUE" in Instrument Sans caption with ember and tracking, then the game title in Literata title2, then the update line in the body style. The game's own logo stays inside its art and is never redrawn by us.
  - The whole card, frame plus text, is one button, at least 44 pt, with a VoiceOver label like "Continue, Update 1.1, The Blood of Dawnwalker". The hairline and the dip are decoration only.
  - In tabletop the framed art moves to the upper half and is display-only. The CONTINUE label, title, update line and tap target stay in the lower half.
  - The large title "Library" in Literata and the ink and vellum chrome carry the brand everywhere else.

## PlayStation

Don't use the PlayStation or PS5 logos, the four button shapes, or PlayStation blue. Use "PS5" only as plain descriptive text, and show the notice in `tokens.json` (`voice.trademarkNotice`) in About.

## Rebuild

    pip install fonttools uharfbuzz
    python3 brand/tools/gen.py
    NODE_PATH=$(npm root -g) node brand/tools/render.mjs

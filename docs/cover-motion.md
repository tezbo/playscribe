# Cover motion (Closed-pose front cover with three motion modes)

Terry's go, 12 Nov 2026 07:27 UTC ("I love all of them. Make the three of them user-selectable options in settings."), from the mock-up
https://claude.ai/artifact/E3BFLUojqyY5dzJEcoMve2 (copy: `/mnt/project-files/cover/duo-front-cover.html`). Decision note: `docs/decisions/duo-cover-screen.md`.
Board card `duo-closed-cover`. IDs below are proposed for `docs/ux-acceptance.md` (UX QA thread folds them in).

## What it is
When the Duo is closed, the outer display is the app's whole canvas. The Library's Continue hero grows to a full-bleed **cover** of the
game you were in: key art, eyebrow ("New update" when unread, else "Continue"), game name, chips (`v1.1 · On PS5` in accent, date,
change count), the page-edge leaves, and the Playscribe lockup (brand/logo/lockup-on-dark.svg) bottom-left. No invite line (Terry, 12 Nov 07:29 UTC). The rail keeps every control (G-4 spirit; the art is
never tappable except as the Continue target). The cover is the same view in Closed portrait and Closed landscape (compact width).

## The three motion modes (Settings > Appearance > "Cover motion")
| Mode | What moves | Source | Fallback |
|---|---|---|---|
| **Trailer loop** (default) | A silent 10 s clip of the game's official trailer, looping without a seam | Backend-cut loop served in the feed (`coverLoop` URL, H.264, 480×700, ≈0.5 MB) | Key-art motion when the game has no loop |
| **Key-art motion** | 18 s slow push on the art (1.04 → 1.18), drifting accent-coloured embers, a 9 s light sweep, and depth | Key art already in the feed | Still |
| **Still** | Nothing | Key art | n/a |

Rules that apply to every mode:
- **CM-1** Only Reduce Motion forces Still, whatever the setting says (G-9). Autoplay videos off stops only the Trailer loop, which falls back to Key-art motion. The Settings row footnote says so. Built in #467.
- **CM-2** First frame is the cover. The key art shows at once; the loop fades in over 1.2 s once it can play, so a slow load or a screenshot still looks like the cover (Apple Music Album Motion rule).
- **CM-3** Motion pauses when the app leaves the foreground, when the cover scrolls off screen, and after 90 s with no touch; it resumes on touch. Loops never play on cellular unless "Autoplay videos" is on.
- **CM-4** Depth (key-art mode): the art, the plate and the leaves move at different rates. Closed: CoreMotion tilt, capped at 10 pt for the art and 6 pt for the plate. Book and Tabletop: the hinge angle (`onHingeChange`) drives the same offsets, which only the Duo can do. Never used for layout (DuoReader does that).
- **CM-5** The caption keeps the AX rules (headline max 4 lines, chips wrap before dropping, capped at AX3 in Tabletop). Contrast over the darkest frame of the loop meets AA; the shade gradient is part of the cover, not the art.
- **CM-6** No source names or credits on the cover (CLAUDE.md). The loop is the game's own trailer, treated like its art.
- **CM-7** VoiceOver: the cover is one element, "<Game> cover, update 1.1 on PS5, 22 October"; motion mode is not announced.

## Per-game crop focus
Optional feed field `coverFocusX`, 0 to 1, default 0.5 (centre): the horizontal point of the art that stays in view when the art is cropped to the cover's portrait shape. Applies to the key art in every mode and to the first frame of the loop.

## Loop cut rule (backend)
Source: the game's Steam store trailer (`appdetails.movies[0]`, HLS 720p; Steam is the source of truth and already feeds the catalogue).
Cut: skip the first 10 s (rating cards), take 11 s, crossfade the last second into the first so the loop starts and ends on the same frame,
crop to 466:678, scale to 480×700, 30 fps, no audio, H.264 main, CRF 27, faststart. The first run produced 467 KB for Dawnwalker
(`/mnt/project-files/cover/dawnwalker-cover-loop.mp4`). Re-cut when the trailer changes; serve as `coverLoop` next to the key art.
Open check (Nadia): re-hosting a cut of a publisher's trailer is a step beyond embedding it; confirm it sits inside how we already use
publisher art, or restrict loops to games whose press kits allow it.

## Scene 2 (outer display while open) is NOT in this card
It waits for the Mac probe (`ExternalNonInteractiveAccessory`). If it passes, the same cover is reused there, view-only.

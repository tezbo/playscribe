# Server push readiness (Priya, 2026-11-05)

The 0.5.0 backend is on main (#234), so the staged cutover plan is obsolete. What is still open is whether **server pushes** can be switched on. They cannot yet, and `PUSH_ENABLED` alone will not change that.

## Findings

- The app's `PlayscribeAPIBaseURL` (Info.plist) is `https://raw.githubusercontent.com/tezbo/playscribe/feed/v1/`, a static file host. `PushRegistrar` posts to `v1/devices` and `v1/devices/me` there, which cannot accept a POST. There is **no hosted relay**: the Hono server in `backend/src/server.ts` only runs locally. So no device token, follow or quiet-hours window is stored anywhere, and the hourly feed job sends to nobody.
- The workflow already reads `PUSH_ENABLED` (a repository variable) and `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8` (secrets); its comment says push is parked until the Apple Developer Program is paid.
- Code that waits on a relay and is ready: quiet-hours window on the relay (#198, on main), digest counts and Iris's alert copy (#162, open). The app's own local alerts (including Leaving soon) honour quiet hours today.

## What switching pushes on needs

1. A free host for `server.ts` that persists SQLite, or a different place for the device table that the Actions job can read.
2. An app change to give the relay its own base URL, separate from the feed URL (so it ships in a TestFlight build after 0.5.1).
3. The APNs secrets and `PUSH_ENABLED=1`, which only Terry can add.
4. Then a staged check: one TestFlight device registers, one release pushes, quiet hours silences it, and the 72-hour guard still holds.

Steps 1 and 2 are design decisions for Theo and Terry.

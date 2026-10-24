# Releasing to TestFlight

Parked: TestFlight needs the paid Apple Developer Program. Until then the workflow finds no secrets and skips. To run the app on your own iPhone for free, open the project in Xcode and sign with your personal team (a free Apple ID). The build lasts 7 days before you need to re-run it.

`git tag v0.1.0 && git push origin v0.1.0` builds that version and uploads it to TestFlight (`.github/workflows/testflight.yml`). Running the workflow by hand uploads main with the project's own version. Build numbers are always one past TestFlight's latest.

Signing is cloud-managed by Xcode through an App Store Connect API key, so nothing else is needed: no certificates, no profiles, no match repo.

Repository secrets (Settings → Secrets and variables → Actions):

| Secret | Where it comes from |
|---|---|
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → Team key (Admin role, needed for cloud signing) |
| `ASC_ISSUER_ID` | Same page, above the key list |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `APPLE_TEAM_ID` | developer.apple.com → Membership |

Optional repository variables: `IOS_SCHEME` (default `Playscribe`), `IOS_BUNDLE_ID` (default `co.codeconnectors.playscribe`).

Local run: `cd ios && bundle install && bundle exec fastlane beta` with the same variables exported.

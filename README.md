# Bright Lights

A private app for Jon and Wendy's monthly stays at their NYC apartment. It answers one question: what's on at the
places we care about while we're in town, and what needs booking before the next stay?

The app is a multiplatform SwiftUI shell with its SQLiteData schema and the seeded source registry in
`BrightLightsLibrary`.

## Development

- Run `scripts/check-drift.sh` for registry parity, SwiftLint, package tests, and iOS/macOS builds.
- Enable the tracked pre-commit hook with `git config core.hooksPath .githooks`.
- To opt into the real model check, set `BRIGHT_LIGHTS_LIVE_MODEL_TEST=1` when running `swift test --package-path BrightLightsLibrary`.
- To exercise CloudKit Development sync, add `-BrightLightsCloudKitSyncEnabled` to the app's launch arguments. The opt-in is saved locally for later launches.

Product and settled decisions are in [`docs/PRODUCT.md`](docs/PRODUCT.md); the current dispatch is in [`docs/NEXT_UP.md`](docs/NEXT_UP.md).

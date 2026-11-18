# Bright Lights

A private app for Jon and Wendy's monthly stays at their NYC apartment. It answers one question: what's on at the
places we care about while we're in town, and what needs booking before the next stay?

The extraction package is built first, before the app scaffold. Its tests use copied source samples from
[`docs/sources/fixtures/`](docs/sources/fixtures/).

## Development

- Run `scripts/check-drift.sh` for SwiftLint and package tests.
- Enable the tracked pre-commit hook with `git config core.hooksPath .githooks`.
- To opt into the real model check, set `BRIGHT_LIGHTS_LIVE_MODEL_TEST=1` when running `swift test --package-path BrightLightsLibrary`.

The app remains pre-build. Product and settled decisions are in [`docs/PRODUCT.md`](docs/PRODUCT.md); the current dispatch is in [`docs/NEXT_UP.md`](docs/NEXT_UP.md).

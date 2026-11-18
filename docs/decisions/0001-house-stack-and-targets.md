# ADR-0001: The house stack, with iPad, iPhone and Mac targets from one XcodeGen project

*Status: proposed — 2026-11-18. Summary: Bright Lights uses jon-platform's stack unchanged. One multiplatform app
target covers iPad, iPhone and Mac, and reusable logic lives in a local SPM package.*

## Context

jon-platform's `AGENTS.md` sets the house stack: SwiftUI, SQLiteData + CloudKit, Point-Free libraries without TCA,
`@Dependency` instead of singletons, and AI only through `LLMClientKit`. Galavant applies it to the same kind of
two-person app. Bright Lights has one unusual need: the Mac build is a working part of the system (ADR-0003), not just
a convenience.

## Decision

1. **The house stack, unchanged.** Read jon-platform `docs/ios/` before writing code, and follow its `swift-style.md`
   and `persistence-and-sync.md`.
2. **One XcodeGen project, `BrightLights`,** with a multiplatform app target (iPadOS, iOS, macOS). The project isn't
   committed, only its package pins (jon-platform `templates/app.gitignore`, already adopted).
3. **A local package, `BrightLightsLibrary`,** holds everything testable without the app: the extraction engine
   (ADR-0004), schema, and pure read models. It has package tests, as Galavant's `GalavantLibrary` does.
4. **Deployment target: the latest OS (27)**, the house default.
5. **Shared packages:** `WebExtractorKit` (in-app browser and headless rendering) and `LLMClientKit` (model access
   with Jon's key, structured output). `CloudSyncKit` arrives with sharing in M2, and `MCPServerKit` with chat access.
   Each gets a SEAM-LEDGER or EXTRACTION-NOTES row as it's adopted.
6. **The house scaffolding comes with the first app slice:** `check-drift.sh`, `.githooks`, SwiftLint, and builds
   through `quiet-run`.
7. **No version suffixes** in names (house rule).

## Consequences

- The Mac target ships from day one, so every screen has to compile for macOS, even ones built for the iPad.
- The first slice (M1 S1) is package-only, so the hardest part, extraction, can be proven before any app exists.

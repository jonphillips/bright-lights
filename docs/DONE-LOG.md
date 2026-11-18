# Done Log — completed dispatches

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-18 — Event source survey (`codex/source-survey`)

- **Result:** Surveyed all 47 registry sources, documented core source methods and limits, and added bounded fixtures for all 15 automated core routes, including UCB’s rendered-page sample. Recorded the registry count mismatch and the access/permission limits.
- **Verification:** JSON parses; registry/source counts are 24 core plus 23 other; all 15 automated core routes have fixtures under 100 KB, including UCB’s rendered-page sample. No build or tests run (research-only dispatch).

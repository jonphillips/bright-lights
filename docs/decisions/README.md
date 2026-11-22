# Decisions

Settled architecture. Check here before proposing a change, and don't re-litigate. General house decisions live in
jon-platform `docs/adr/`.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-house-stack-and-targets.md) | The house stack; iPad, iPhone and Mac targets from one XcodeGen project | accepted |
| [0002](0002-shared-data-model.md) | One shared household; listings are synced rows, upserted only when they change; what's deleted, and when (Amendment 1) | accepted |
| [0003](0003-the-mac-checks-the-sources.md) | The app's Mac build on the always-on mini checks automated sources | accepted |
| [0004](0004-one-extraction-engine.md) | One extraction engine, deterministic first, with a model as the last resort | accepted |
| [0005](0005-rounds-and-browser-capture.md) | Rounds: a due-list of sources, captured in the in-app browser while Jon reads; the Capture tab (Amendment 2); fixing a source from the app (Amendment 3) | accepted |
| [0006](0006-screening-and-the-taste-record.md) | Screening: new listings are kept or cleared, and a taste record outlives them | accepted |
| [0007](0007-places-and-the-check-sheet.md) | Places: a map and an ideas list, with one shared standing per place (the check sheet) and an optional season | accepted |
| [0008](0008-the-stay-plan.md) | The stay plan: a list and the days, with errands from a shared Reminders list | accepted |
| [0009](0009-production-and-wendy.md) | Production starts empty; registry writes gated by version; a shared household survives; Wendy joins through a share; one store per environment (Amendment 1) | accepted |

Status changes to **accepted** when Jon merges the plan PR that proposes it.

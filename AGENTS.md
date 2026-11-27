# Bright Lights

Private app for Jon and Wendy (two users, never on the App Store). They stay at an NYC apartment (probably
Williamsburg) for about a week a month, and stays have soft edges. Bright Lights follows the venues they care about
and shows what's on during a stay, plus what needs booking before the next one.

**Status: building.** M1 through M3 are done; the current slice is in `docs/NEXT_UP.md`, and its milestone is in
`docs/milestones/`.

## Working mode — architect / executor

The same as Galavant: Claude is the architect (docs, decision records, briefs, reviews) and writes **no feature
code**. Codex is the executor (builds `docs/NEXT_UP.md`, one branch and PR per dispatch). Jon approves plans by
merging plan PRs. The full loop is in jon-platform `docs/agent-collaboration.md` and jon-platform ADR-0005.

## Read first

- `~/code/jon-platform`: Jon's house knowledge base, with general style, architecture, persistence and sync rules,
  toolchain and agent workflow. Read its `AGENTS.md` before proposing architecture or style.
- `docs/PRODUCT.md`: what we're building, and what's out of scope.
- `docs/decisions/`: settled architecture. Check these before proposing a change, and don't re-litigate them.
- `docs/NEXT_UP.md`: the single dispatch. If you're the executor, it's your only planning input; if it's empty,
  stop and ask.
- `docs/open-questions.md`: for the architect only; the executor never reads it.
- `~/code/galavant`: the sibling app. Bright Lights reuses its patterns and the jon-platform packages it
  uses. Mine it, never import it wholesale.

History, read only when a doc cites it: `docs/BRAINSTORM.md` (how the ideas formed; `PRODUCT.md` and the decisions
supersede it), `docs/DONE-LOG.md`, and the `archive/` folders.

## Stack

The house stack from jon-platform: SwiftUI multiplatform (iPad first for planning, iPhone for use on the go),
SQLiteData + CloudKit, Point-Free libraries without TCA, and AI through `LLMClientKit`, bound by ADR-0001. Checking
venues happens on Jon's always-on Mac mini (ADR-0003).

## Conventions

- 2-space indentation.
- Keep dependencies minimal; each new package needs a reason.
- Fetching from sources is personal-use and polite: honor robots.txt, no logins, no paywall circumvention, and
  low request rates.

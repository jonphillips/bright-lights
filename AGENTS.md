# Bright Lights

Private app for Jon and Wendy (two users, never on the App Store). They stay at an NYC apartment (probably
Williamsburg) for about a week a month, and stays have soft edges. Bright Lights follows the venues they care about
and shows what's on during a stay, plus what needs booking before the next one. [`docs/PRODUCT.md`](docs/PRODUCT.md)
has the scope and what's out of it.

## Working mode

Architect / executor, per jon-platform `AGENTS.md`.

## Read first

1. `~/code/jon-platform/AGENTS.md`: the house stack and rules. Bright Lights' docs hold only the venue domain.
2. [`docs/README.md`](docs/README.md): the map of this repo's docs.
3. `~/code/galavant`, the sibling app, when you need a pattern. Bright Lights reuses its patterns and the
   jon-platform packages it uses. Mine it, never import it wholesale.

`docs/BRAINSTORM.md` is history: `PRODUCT.md` and the decisions supersede it.

## What's Bright Lights' own

- **iPad first for planning, iPhone on the go** (ADR-0001).
- **Venue checks run on Jon's always-on Mac mini** (ADR-0003), not on the devices.
- **Fetching from sources is personal-use and polite:** honor robots.txt, no logins, no paywall circumvention,
  and low request rates.

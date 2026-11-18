# ADR-0002: One shared household; listings are synced rows, upserted only when they change

*Status: accepted — 2026-11-18 (PR #3). Summary: Everything descends from a single shared `Household` root, so inviting
Wendy is a share, not a migration. Listings sync like any other row. Writers change a row only when its content
changes, so nightly checks don't churn CloudKit.*

## Context

Jon curates now, and Wendy joins later as a full peer with no ceremony (BRAINSTORM, settled). jon-platform's
multi-user pattern requires one shared root record, no privacy flags, and attribution rather than ownership. Listings
are observations of public pages, written mostly by the Mac (ADR-0003) and sometimes by the browser (ADR-0005), and
they change constantly. The survey found about 1,500 future listings across the core sources.

## Decision

1. **`Household` is the shared root.** Every synced table descends from it.
2. **Tables (M1):**
   - **`Source`:** a followed venue, presenter or feed. Holds its method (`automated` or `manual`, with the adapter
     name), canonical URL, registered hosts for browser capture, cadence, and the outcome of its last check (when,
     success or failure, listing count). Seeded from `docs/sources/registry.json`.
   - **`Listing`:** something on at a source. Identity is a **stable key**: the source's canonical event URL or ID
     where the survey found one, otherwise a hash of source, normalized title, room and local start. Its time is an
     enum, never a pair of optional dates: `.performance(start)` or `.run(opens, closes)`. It also holds title,
     performers (names), room, ticket URL, on-sale date, a status enum (`listed`, `soldOut`, `cancelled`, `missing`),
     and provenance (which rung of ADR-0004 extracted it, and whether the Mac or the browser captured it).
   - **`Stay`:** an arrival date and a departure that's an enum: `.booked(date)`, `.tentative(date)` or `.open`.
   - **`Reaction`:** one per listing: `interested`, `booked`, `pass` or `went`, with an optional note and an
     attribution-only author.
3. **Upsert by stable key, and only on change.** A writer compares extracted content with the stored row and writes
   only if something differs. The time of each check lives on `Source`, never on every listing. A listing that
   disappears from its source becomes `missing` rather than being deleted. Past listings without a reaction are pruned
   30 days after they end. Listings with reactions are kept, because they're the history the taste work reads.
4. **Times are NYC wall-clock time.** Extracted local times are interpreted in `America/New_York`.
5. **Performers are names on the listing for now.** A `Performer` entity waits until the M2 taste work needs it.

## Considered and rejected

- **Listings as a snapshot file per source** (a CKAsset row), materialized into a local table on each device. That
  avoids row churn, but it adds a second persistence path and a merge policy for partial browser captures. The
  only-on-change upsert keeps churn low with plain observed rows.
- **Listings in iCloud Drive files**, as Vinyl Fever's listening log does. Wendy's devices can't read Jon's iCloud
  Drive, so this would break sharing.

## Consequences

- The CloudKit Development schema follows M1. Deploying to Production is permanent and additive, so it waits for
  TestFlight in M2, and every synced column added in M1 is named carefully (house schema hygiene).
- Inviting Wendy needs no data work: it's `share(record:)` on the household (jon-platform persistence-and-sync,
  "Creating and accepting the share").

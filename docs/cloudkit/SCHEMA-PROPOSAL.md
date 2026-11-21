# CloudKit Development schema proposal

The full proposal starts from a fresh Development export captured on 2026-11-20 and adds `tasteRecords`. `development-schema-proposal.diff` shows only that addition; `development-schema-proposed.ckdb` is the complete schema file to import after approval.

The proposal adds the checker lease fields to `households`; missing S2 and S3 `sources` fields, including `feedURL`; the v3 `startPageURL`, `flaggedAt`, and `flagNote` fields on `sources`; and the `listings`, `stays`, and `reactions` record types with their SQLiteData modification-time fields.

The proposal passed `cktool validate-schema` against Development on 2026-11-20 and was imported into Development the same day, on Jon's approval. A fresh export afterwards matched it apart from CloudKit's field order. No Production schema operation was run.

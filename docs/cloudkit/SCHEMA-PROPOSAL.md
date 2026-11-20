# CloudKit Development schema proposal

The full proposal starts from a fresh Development export captured on 2026-11-19 and adds the fields used by the current synced model. `development-schema-proposal.diff` shows only the additions; `development-schema-proposed.ckdb` is the complete schema file to import after approval.

The proposal adds the checker lease fields to `households`; missing S2 and S3 `sources` fields, including `feedURL`; the v3 `startPageURL`, `flaggedAt`, and `flagNote` fields on `sources`; and the `listings`, `stays`, and `reactions` record types with their SQLiteData modification-time fields.

CloudKit Development accepted the proposal, including the v3 source-fix fields, with `cktool validate-schema`. Jon approved it, and it was imported on 2026-11-20 from a fresh export plus the six new `sources` fields. Development matched this proposal afterwards, and Production was unchanged.

# CloudKit Development schema proposal

The full proposal starts from a fresh Development export captured on 2026-11-19 and adds the fields used by the current synced model. `development-schema-proposal.diff` shows only the additions; `development-schema-proposed.ckdb` is the complete schema file to import after approval.

The proposal adds the checker lease fields to `households`; missing S2 and S3 `sources` fields, including `feedURL`; and the `listings`, `stays`, and `reactions` record types with their SQLiteData modification-time fields.

CloudKit Development accepted the proposal with `cktool validate-schema`. It has not been imported. Import waits for Jon's approval of this diff.

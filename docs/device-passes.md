# Device passes

Real-device checks still owed, and held setup steps. A completing PR adds its own line here (jon-platform ADR-0005
D15).

## Gates
- **check-report:** Install on the checking Mac, let one night of checks run, then use scripts/check-report --days 1 on the laptop and ask the architect how the checks are doing. ([brief](efforts/archive/check-report.md))
- **M2 S1:** Run the S1 cutover after merge, verifying Production seeding, matching source and household identity across Mac and TestFlight devices, and recording whether pushes arrive within a minute. ([M2](milestones/archive/M2-wendy-joins.md))
- **M2 S2:** Jon and Wendy complete § S2 device pass after the M2 S1 Production cutover. ([M2](milestones/archive/M2-wendy-joins.md))
- **M3 S1:** After a week or so of Production screening, open New on the iPad and check evidence lines and likely-first order for a screened source; switch to By date and back; then review a capture and check the same sort and evidence. ([M3](milestones/archive/M3-taste.md))
- **M3 S2:** Jon deploys tasteNotes to Production, runs TestFlight, and installs on the iPad and iPhone; he opens a listing on iPad, adds a note with its performer prefilled as Subject, and confirms it appears on his iPhone and Wendy’s phone under his name; Wendy adds a note from Settings → Taste, and Jon confirms it appears on iPad under her name and cannot be edited there. ([M3](milestones/archive/M3-taste.md))
- **M3 S3:** Jon deploys tasteRecords.suggestion to Production, runs testflight, and installs. On iPad, with a frontier key, open a source in New. Rows show Suggesting…, then verdicts with reasons that cite a note or past show; likely keeps come first. Press Done. Settings → Taste shows the provider and counts. Remove the key: the screen asks for one, while S1’s sort still works. After two weeks of screening, read Settings → Taste and tell the architect how often suggestions agreed. ([M3](milestones/archive/M3-taste.md))


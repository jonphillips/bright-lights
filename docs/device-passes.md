# Device passes

Real-device checks still owed, and held setup steps. A completing PR adds its own line here (jon-platform ADR-0005
D15).

## Gates
- **check-report:** Install on the checking Mac, let one night of checks run, then use scripts/check-report --days 1 on the laptop and ask the architect how the checks are doing. ([brief](efforts/archive/check-report.md))
- **M2 S1:** Run the S1 cutover after merge, verifying Production seeding, matching source and household identity across Mac and TestFlight devices, and recording whether pushes arrive within a minute. ([M2](milestones/archive/M2-wendy-joins.md))
- **M2 S2:** Jon and Wendy complete § S2 device pass after the M2 S1 Production cutover. ([M2](milestones/archive/M2-wendy-joins.md))
- **M3 S1:** After a week or so of Production screening, open New on the iPad and check evidence lines and likely-first order for a screened source; switch to By date and back; then review a capture and check the same sort and evidence. ([M3](milestones/M3-taste.md))
- **M3 S2:** Jon deploys tasteNotes to Production, runs TestFlight, and installs on the iPad and iPhone; he opens a listing on iPad, adds a note with its performer prefilled as Subject, and confirms it appears on his iPhone and Wendy’s phone under his name; Wendy adds a note from Settings → Taste, and Jon confirms it appears on iPad under her name and cannot be edited there. ([M3](milestones/M3-taste.md))


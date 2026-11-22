# Device passes

Real-device checks still owed, and held setup steps. A completing PR adds its own line here (jon-platform ADR-0005
D15).

## Gates
- **check-report:** Install on the checking Mac, let one night of checks run, then use scripts/check-report --days 1 on the laptop and ask the architect how the checks are doing. ([brief](efforts/archive/check-report.md))
- **M2 S1:** Run the S1 cutover after merge, verifying Production seeding, matching source and household identity across Mac and TestFlight devices, and recording whether pushes arrive within a minute. ([M2](milestones/archive/M2-wendy-joins.md))
- **M2 S2:** Jon and Wendy complete § S2 device pass after the M2 S1 Production cutover. ([M2](milestones/archive/M2-wendy-joins.md))


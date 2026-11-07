**What a player sees:** <!-- one or two plain lines; optional -->

**Should do:** <!-- the change, as a player or a check would notice it -->
**Must not break:** <!-- what nearby still has to work -->
**Measured:** <!-- tests, doctor steps, numbers: things that ran -->
**Not measured:** <!-- say it plainly; "how it feels" counts -->
**Evidence:** <!-- what Luke looks at instead of the diff: screenshot, clip, doctor report path. Needed when src/ changed -->
**Review:** <!-- fresh-context review before this PR: rounds (max 2), findings, how many fixed, the rest answered here -->
**Risk:** <!-- paste the verdict from `lune run tools/bas risk`: "needs Luke (gameplay, save)" or "routine" -->
**Undo:** <!-- a flag (docs/ROLLBACK.md step 1), "revert this PR", or the place version to restore -->

<!-- `lune run tools/bas intent --body-file <this file>` checks the card before you open the PR; CI runs the same check (intent.yml). -->

# LEARNINGS — repo-optimizer

| # | Learning | Source |
|---|---|---|
| L1 | repo-optimizer was a script directory with 0 self-authored commits, dormant spec-kit, and no self-management infrastructure. Every repo-agent needs a build spec — the spec IS the repo-agent's DNA. | spec 054 RCA, L272 |
| L2 | Agent must call repo-optimizer.sh directly as a single command, not dispatch discovery subagents individually. The bash orchestrator manages directory layout and phase sequencing that downstream tools depend on. | spec 054, L274/L6 |
| L3 | First self-managed work contract (M5.5 validation) confirmed the full work-init -> edit -> work-close -> SCORECARD cycle works end-to-end. Session grader produces valid OPERATING_MODEL_SCORECARD.json. Domain tests are unaffected by self-management infrastructure. | spec 054 M5.5 validation, v94 |
| L4 | Line-continuation backslashes in multi-line find commands are invisible failure points: the minimal budget tier find on line 116 of repo-optimizer.sh was missing a trailing backslash after the opening parenthesis grouping operator, causing "find: (): empty inner expression" on any repo with >1000 files. The focused tier (line 95) had the correct syntax. Fix was 1 character. Regression test with synthetic repos at all 3 tier boundaries (50, 500, 1100 files) now prevents recurrence. | L270 (BMA), v96 work contract |

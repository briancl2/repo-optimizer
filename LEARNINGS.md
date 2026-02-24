# LEARNINGS — repo-optimizer

| # | Learning | Source |
|---|---|---|
| L1 | repo-optimizer was a script directory with 0 self-authored commits, dormant spec-kit, and no self-management infrastructure. Every repo-agent needs a build spec — the spec IS the repo-agent's DNA. | spec 054 RCA, L272 |
| L2 | Agent must call repo-optimizer.sh directly as a single command, not dispatch discovery subagents individually. The bash orchestrator manages directory layout and phase sequencing that downstream tools depend on. | spec 054, L274/L6 |

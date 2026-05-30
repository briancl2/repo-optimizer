---
name: repo-optimizer-inbound
description: >
  Inbound invocation: optimize the current repository. Reads context from pwd,
  resolves skills and scripts from this agent repo.
model: claude-opus-4.7
tools: [read, search, execute]
stop_rules:
  max_files: 200
  timeout_seconds: 900
---

# Repo Optimizer — Inbound Mode

Optimize the repository at the current working directory.

## Prerequisites

- SCORECARD.json must exist (from repo-auditor)
- AUDIT_REPORT.md must exist (from repo-auditor)

## Steps

1. Read SCORECARD.json and AUDIT_REPORT.md
2. Run 4-phase optimization pipeline
3. Write OPTIMIZATION_PLAN.md to `./optimizer_output/`
4. If --patch flag present, write PATCH_PACK/ directory

Inbound reciprocal proving-ground checks remain read-only. If the current repo
is acting as a live proving ground for owner-repo guidance, compare and verify
read-only targets without mutating downstream targets. Keep optimizer output
limited to plan artifacts and patch files unless a named owner issue or PR
explicitly authorizes owner-repo mutation.

## Invocation

This agent is invoked from within a target repo that references it:

```markdown
## External Agents
- Optimize: @repo-optimizer at briancl2/repo-optimizer, optimize this repo
```

`PATCH_PACK/` is a review artifact, not auto-apply permission. Do not create
owner branches, commits, pull requests, background sync, or any other mutation
path from inbound mode unless the invoking prompt cites a named owner issue/PR
that authorizes the write.

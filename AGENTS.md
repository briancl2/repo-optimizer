# AGENTS.md — repo-optimizer

> Standalone repo optimizer — produces concrete patches that improve audit scores for any AI-native repository.
> Read this file FIRST.

## Purpose

`repo-optimizer` reads SCORECARD.json and OPPORTUNITIES.md, then produces concrete unified-diff patches that improve the target repo's health metrics. It includes an adversarial critic that must reject at least 1 finding per run.

## Architecture

**Orchestrator → 4 domain subagents → adversarial critic → patch generation**

| Subagent | Domain | Output |
|---|---|---|
| decomposition-optimizer | Break files >200 lines | decompose_findings.json |
| consolidation-optimizer | Merge duplicates, reduce drift | consolidate_findings.json |
| extraction-optimizer | Promote scripts → skills | extract_findings.json |
| standardization-optimizer | Normalize naming, frontmatter, structure | standardize_findings.json |

**Adversarial critic:** Reviews all findings before patch generation. Must reject ≥1 finding or explain why all pass. Rejects "delta-hack" patterns (stub docs, renames without function change).

## Invocation

**Mode A — Outbound (from this repo):**
```bash
make optimize TARGET=~/repos/some-target-repo AUDIT=path/to/SCORECARD.json
```

**Mode B — Inbound (from a target repo):**
```
@repo-optimizer at briancl2/repo-optimizer, optimize this repo
```

## Key Conventions

- Every change goes through `make review` before committing
- `--no-verify` is NEVER permitted (L102)
- Pre-commit hook blocks by default (L105)
- Patches: ≤6 files per patch, ≤160 net lines
- Adversarial critic is non-negotiable (L18, L29)

## Skills

| # | Skill | Purpose |
|---|---|---|
| 1 | reviewing-code-locally | Pre-commit code review via Copilot CLI |

## Token Budget

~45K tokens per optimization run (4 subagents + critic).

## Patch Constraints

- Maximum 5 patches per run
- Each patch: ≤6 files, ≤160 net lines
- Unified diff format validated with `git apply --check`
- Post-processed hunk headers (L36)
- Explicit rollback commands included (L32)

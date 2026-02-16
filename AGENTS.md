# AGENTS.md — repo-optimizer

> Produce concrete optimization patches that improve audit scores for any repository.
> Report-only by default; `--patch` flag enables patch generation.
> Adversarial critic is non-negotiable. `--no-verify` NEVER permitted.

## Purpose

`repo-optimizer` reads SCORECARD.json + AUDIT_REPORT.md (from repo-auditor) and
produces an OPTIMIZATION_PLAN.md with prioritized findings. With `--patch` flag,
generates unified diff patches validated with `git apply --check`.

## Key Conventions

- **Report-only by default** — `--patch` flag required for modifications
- Adversarial critic is mandatory (L29) — must reject ≥1 finding per run
- Pre-commit hook blocks by default (SKIP_REVIEW=1 for emergency only)
- `--no-verify` is NEVER permitted (L102)
- AGENTS.md is the canonical instruction surface (L104)
- Target repos are NEVER modified directly — only patches produced

## Agents (8)

| # | Agent | Model | Purpose |
|---|---|---|---|
| 1 | repo-optimizer | claude-opus-4.6 | Orchestrator — 4-phase pipeline |
| 2 | repo-optimizer-inbound | claude-opus-4.6 | Inbound invocation (Mode B) |
| 3 | decomposition-optimizer | claude-sonnet-4.5 | Break >200L files into focused components |
| 4 | consolidation-optimizer | claude-sonnet-4.5 | Merge near-duplicates, eliminate dead code |
| 5 | extraction-optimizer | claude-sonnet-4.5 | Promote scripts → skills |
| 6 | standardization-optimizer | claude-sonnet-4.5 | Normalize naming, frontmatter, patterns |
| 7 | repo-optimizer-critic | claude-opus-4.6 | Adversarial critic (MANDATORY) |
| 8 | repo-optimizer-synthesis | claude-opus-4.6 | Findings + patch summary synthesis |

## Skills (2)

| # | Skill | Purpose |
|---|---|---|
| 1 | reviewing-code-locally | Pre-commit code review via Copilot CLI |
| 2 | bundle-integrity | Validate optimization output bundle completeness |

## Scripts (7)

| Script | Purpose |
|---|---|
| `scripts/repo-optimizer.sh` | 4-phase pipeline orchestrator |
| `scripts/pre-flight.sh` | Read SCORECARD + identify bottom-2 dimensions |
| `scripts/generate-patches.sh` | Unified diff generation from findings |
| `scripts/fix-diff-headers.sh` | Hunk header recomputation (L36) |
| `scripts/validate-patches.sh` | `git apply --check` wrapper |
| `scripts/compare-scorecards.sh` | Pre/post delta computation |

## How to Use

```bash
# Mode A — Outbound (from this repo)
make optimize TARGET=~/repos/some-repo AUDIT=path/to/audit_output

# Report-only (default)
make optimize TARGET=~/repos/some-repo AUDIT=path/to/audit_output

# With patch generation
make optimize TARGET=~/repos/some-repo AUDIT=path/to/audit_output PATCH=true

# Run tests
make test
```

## Pipeline

| Phase | Description | Tokens |
|---|---|---|
| 1. Pre-flight | Read SCORECARD, identify bottom-2 dims | 0 (deterministic) |
| 2. Discovery | 4 domain subagents find optimization opportunities | ~20K |
| 3. Critic | Adversarial review — reject ≥1 finding | ~10K |
| 4. Synthesis | Assemble plan + optional patches | ~15K |

## Patch Constraints

- Maximum 5 patches per run
- Each patch: ≤6 files, ≤160 net lines
- No dependency changes
- Validated with `git apply --check`
- Post-processed hunk headers (L36)

## Stop Rules

- Max 200 files scanned per target
- Max 30 findings per domain subagent
- Max 900 seconds per run
- Halt if SCORECARD.json missing

# Repo-Optimizer Agent Operations

This document keeps detailed operational inventory out of the startup
bootloader. `AGENTS.md` is the concise live surface.

## Agents

| Agent | Model | Purpose |
|---|---|---|
| repo-optimizer | claude-opus-4.7 | Four-phase optimization orchestrator |
| repo-optimizer-inbound | claude-opus-4.7 | Inbound invocation |
| decomposition-optimizer | claude-sonnet-4.6 | Break oversized files into focused components |
| consolidation-optimizer | claude-sonnet-4.6 | Merge near-duplicates and remove dead code |
| extraction-optimizer | claude-sonnet-4.6 | Promote scripts into skills |
| standardization-optimizer | claude-sonnet-4.6 | Normalize names, frontmatter, and patterns |
| repo-optimizer-critic | claude-opus-4.7 | Mandatory adversarial critique |
| repo-optimizer-synthesis | claude-opus-4.7 | Findings and patch summary synthesis |

## Spec-Kit Agents

The spec-kit pipeline includes `speckit.specify`, `speckit.plan`,
`speckit.tasks`, `speckit.analyze`, `speckit.implement`,
`speckit.checklist`, `speckit.clarify`, `speckit.constitution`, and
`speckit.taskstoissues`. Dispatch may be interactive or batch through the
spec orchestrator scripts.

Spec-kit helper scripts retained in this repo include
`.specify/scripts/bash/check-prerequisites.sh`,
`.specify/scripts/bash/common.sh`, `.specify/scripts/bash/create-new-feature.sh`,
`.specify/scripts/bash/setup-plan.sh`, and `.specify/scripts/bash/update-agent-context.sh`.

## Skills

| Skill | Purpose |
|---|---|
| reviewing-code-locally | Pre-commit code review through Copilot CLI |
| bundle-integrity | Validate optimization output bundle completeness |

## Domain Scripts

| Script | Purpose |
|---|---|
| `scripts/repo-optimizer.sh` | Four-phase pipeline orchestrator |
| `scripts/pre-flight.sh` | Read scorecard and identify bottom dimensions |
| `scripts/generate-patches.sh` | Unified diff generation |
| `scripts/fix-diff-headers.sh` | Hunk-header recomputation |
| `scripts/validate-patches.sh` | `git apply --check` wrapper |
| `scripts/compare-scorecards.sh` | Pre/post scorecard deltas |

## Benchmark And Receipt Scripts

| Script | Purpose |
|---|---|
| `scripts/evaluate-advisory-transfer.py` | Bounded advisory decision transfer oracle |
| `scripts/benchmark-optimization-workloads.py` | Prompt/context benchmark harness |
| `scripts/normalize-agent-run-receipts.py` | Normalize Codex/Copilot/VS Code/generic receipts |
| `scripts/build-live-paired-corpus.py` | Provider-neutral live-paired corpus builder |
| `scripts/run-live-agent-benchmark.py` | Live receipt collector |

## Self-Management Scripts

| Script | Purpose |
|---|---|
| `scripts/check.sh` | Gate 2 pre-commit check |
| `scripts/work-init.sh` | Work contract initializer |
| `scripts/work-close.sh` | Work contract finalizer; runs the session grader by default and writes `score-session-bypass.json` for explicit GitHub-native issue/PR closeout |
| `scripts/score-session.sh` | Operating-model scorecard for ordinary session-local work |
| `scripts/pre-commit-hook.sh` | Runs `make check` |
| `scripts/pre-push-hook.sh` | Pre-push guard |

## Pipeline Token Posture

| Phase | Description | Token posture |
|---|---|---|
| Pre-flight | Read scorecard and bottom dimensions | deterministic |
| Discovery | Domain subagents find opportunities | about 20K |
| Critic | Adversarial review | about 10K |
| Synthesis | Plan and optional patches | about 15K |

## Operator Notes

- Patch packs are artifacts, not direct target mutations.
- `PATCH_PACK/` contents must remain apply-checkable.
- Benchmark evidence is not production proof or billing proof.
- Spec-kit infrastructure is retained but does not override the repo-native
  report-only default.

# Live Capability Inventory

> Owner: repo-optimizer
> Scope: human-readable live capability tracking surface for calibrated capability-drift checks

This document tracks the repo-optimizer live capability surfaces that are intentionally present on disk. It closes the tracking-surface gap raised by Issue #78 without adding a schema, generated registry, runtime API, scheduler, controller, queue, watcher, daemon, retry loop, or background sync.

The calibrated detector separates live surfaces from retained, archive, test-fixture, and generated paths. This inventory records owner intent for the live paths; it does not authorize deleting, archiving, enabling, or mutating target repositories.

## Triage Summary

| Field | Value |
|---|---|
| Calibrated detector live paths | 54 |
| Calibrated tracking-surface gaps closed by this PR | 33 |
| Additional `.agents/skills` reference prompts tracked by owner review | 1 |
| Delete/archive candidates selected here | 0 |
| Generated registry or runtime dependency added | no |
| Target-repo mutation authorized | no |

## Live Paths

| Path | Classification | Tracking status | Owner decision |
|---|---|---|---|
| `.agents/consolidation-optimizer.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/decomposition-optimizer.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/extraction-optimizer.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/repo-optimizer-critic.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/repo-optimizer-inbound.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/repo-optimizer-synthesis.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/repo-optimizer.agent.md` | owner-owned agent surface | already tracked before Issue #164 replay | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/skills/bundle-integrity/SKILL.md` | owner-owned agent surface | already tracked before Issue #164 replay | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/skills/bundle-integrity/scripts/validate-bundle.sh` | owner-owned agent surface | already tracked before Issue #164 replay | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/skills/reviewing-code-locally/SKILL.md` | owner-owned agent surface | already tracked before Issue #164 replay | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/skills/reviewing-code-locally/references/review-prompt.md` | owner-owned skill reference prompt | owner review addition | Keep tracked as an active reviewing-code-locally prompt surface. |
| `.agents/skills/reviewing-code-locally/scripts/local_review.sh` | owner-owned agent surface | already tracked before Issue #164 replay | Keep tracked as an owner-owned agent or skill surface. |
| `.agents/speckit.analyze.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.checklist.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.clarify.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.constitution.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.implement.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.plan.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.specify.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.tasks.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/speckit.taskstoissues.agent.md` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.agents/standardization-optimizer.agent.md` | owner-owned agent surface | tracking-surface gap closed by this PR | Keep tracked as an owner-owned agent or skill surface. |
| `.specify/scripts/bash/check-prerequisites.sh` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.specify/scripts/bash/common.sh` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.specify/scripts/bash/create-new-feature.sh` | dormant Speckit helper | already tracked before Issue #164 replay | Keep tracked pending a later Speckit owner decision. |
| `.specify/scripts/bash/setup-plan.sh` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `.specify/scripts/bash/update-agent-context.sh` | dormant Speckit helper | tracking-surface gap closed by this PR | Keep tracked pending a later Speckit owner decision. |
| `scripts/audit-admission.py` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/benchmark-optimization-workloads.py` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/build-live-paired-corpus.py` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/check.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/classify-phase-output.py` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/cleanup-contract.py` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/closure-run-identity.py` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/compare-scorecards.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/coverage-verdict.py` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/evaluate-advisory-transfer.py` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/fix-diff-headers.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/generate-patches.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/normalize-agent-run-receipts.py` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/operation-guard.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/pre-commit-hook.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/pre-flight.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/pre-push-hook.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/proof-seam-closure.py` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/replay-cr01-patch-pack.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/replay-recovery-runtime-patch-pack.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/repo-optimizer.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/run-live-agent-benchmark.py` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/score-operation.sh` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/score-session.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/target-policy-context.py` | runtime-loaded script | tracking-surface gap closed by this PR | Keep tracked as an owner-owned script surface. |
| `scripts/validate-patches.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/work-close.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |
| `scripts/work-init.sh` | runtime-loaded script | already tracked before Issue #164 replay | Keep tracked as an owner-owned script surface. |

## Non-Claims

- This inventory is documentation for existing calibrated repo-auditor drift semantics, not a separate inventory registry.
- This inventory does not add a schema, runtime API, generated catalog, scheduler, controller, queue, watcher, daemon, retry loop, or background sync.
- This inventory does not authorize target repo mutation, component upgrades, deletion, archive moves, or default enablement of dormant helpers.

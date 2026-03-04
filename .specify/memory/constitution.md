# repo-optimizer Constitution

## Purpose

repo-optimizer is a **4-phase optimization pipeline** that takes auditor output
(SCORECARD.json + AUDIT_REPORT.md), discovers improvement opportunities,
critically reviews them, and generates concrete unified-diff patches. It bridges
the gap between "what's wrong" (auditor) and "here's the fix" (patches).

## Non-Goals

- No audit scoring (that's the auditor's job — never re-score).
- No advisory recommendations (that's the advisor's job).
- No auto-apply of patches (generate drafts only, operator decides).

## Core Principles

### 1. Auditor-First — Never Optimize Without SCORECARD
The optimizer MUST receive SCORECARD.json as input. Without auditor data,
it cannot identify bottom-2 dimensions or verify that patches address real
weaknesses. Running optimizer without audit is a hard error, not a warning.

### 2. Critic-Mandatory
Every discovery finding passes through an adversarial critic phase before
patch generation. The critic must find at least 1 issue or explain why none
exist (L29). Confirmatory critics are a known failure mode. **Mandatory critique
triggers (P11v3):** (1) new spec, (2) principle revision, (3) >200 new lines
across ALL modified repos, (4) handoff with >3 deliverables, (5) stage gate.
Critique-Status header required on triggered commits.

### 3. Patch Validation Required
Generated patches must pass `git apply --check` before being reported as valid.
LLM-generated diffs have ~55% clean-apply rate (L114) — always run
fix-patch-headers.sh post-generation (L122). **Grader accuracy is a first-class
metric (P3v2):** patch success rates are calibrated against ground truth. Scorer
stalls require measurement investigation before product investigation.

### 4. Bottom-2 Focus
Optimization effort concentrates on the 2 lowest-scoring SCORECARD dimensions.
Patches addressing already-strong dimensions are deprioritized. This prevents
scope creep and maximizes delta per token spent.

### 5. Bounded Scope
Max 10 findings per run. Max 5 patches per run. Pre-flight completes in <60s.
Budget tiering (full/focused/minimal) controls discovery scope based on
target repo file count.

### 6. Budget Tiering
- <200 files: full tier (all files eligible for discovery)
- 200-1000 files: focused tier (AI surfaces + governance only)
- >1000 files: minimal tier (scored-dimension files only)
pre-flight.json records the tier and discovery scope for transparency.

## Spec-Kit Operating Rules

### Required Workflow (features >160 lines)
1. /speckit.specify → /speckit.plan → /speckit.tasks → implement
2. Every spec includes acceptance scenarios
3. Patch format changes require downstream coordination

### Definition of Done
- All existing tests pass (`make test`)
- pre-flight.json has required schema fields
- Patches pass `git apply --check` (or documented why not)
- OPTIMIZATION_PLAN.md format unchanged (or migration applied)

## Self-Management (added spec 054)

### 7. Work Contracts Required
All changes must be tracked via `make work` / `make work-close` contracts.
No file edits without an open work contract. Hypothesis stated before work begins.
Learnings extracted before work contract closes (or explicit `--no-novel-findings`).

### 8. Spec-Kit for Significant Changes
Features >160 lines require full spec-kit pipeline: specify -> plan -> tasks -> implement.
Spec-Exempt trailer for in-pipeline commits only.

### 9. Measurement via Session Grader
Every work-close invokes `scripts/score-session.sh` producing OPERATING_MODEL_SCORECARD.json.
PASS threshold: >= 80% (12/15). Measurement is verification (P2).

### 10. Pre-Commit Hook Mandatory
`make install-hooks` installs `scripts/pre-commit-hook.sh` to `.git/hooks/pre-commit`.
Hook runs `make check`. No `--no-verify` permitted (constitution principle, L102).

### 11. LEARNINGS.md is Append-Only
New findings are appended as `| L<N> | description | source |` rows.
Every work contract must produce >= 1 learning or document why not.

## Governance

This constitution supersedes informal practices. Amendments require
documented rationale and review.

### Universal Principle Amendments (Stage 11.6)

The following amendments from the 12 Universal Principles are binding:

- **P3v2 (Fix Measurement First):** Grader accuracy is a first-class metric.
  Ground-truth test on >=3 targets, golden fixture baseline, recalibrate at
  stage boundaries. Reflected in §3 above.
- **P6v5 (Enforced Over Advisory):** T1.5 tier recognized: mechanical triggers
  that invoke behavioral checks (e.g., auto-SER at work-close). score-operation.sh
  and operation-guard.sh are T1.5 mechanisms.
- **P7v3 (Feed Forward Automatically):** work-close REFUSES without learning
  extraction or explicit `--no-novel-findings <rationale>`. Learning-to-DS
  propagation rate tracked (target >=30%). Reflected in self-management §7+§11.
- **P11v3 (Seek Adversarial Counsel):** Mandatory critique triggers with 5
  material events. Critique-Status header on triggered commits. Skip-with-
  rationale allowed. Reflected in §2 above.

**Version**: 3.0 | **Ratified**: 2026-03-04 | **Amendment**: §2 P11v3 critique triggers + §3 P3v2 calibration + UA Stage 11.6 (P6v5, P7v3)

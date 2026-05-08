# Implementation Plan: Coverage-Aware Optimizer Verdicts

**Branch**: `bma-phase2-coverage-verdicts` | **Date**: 2026-05-08 | **Spec**: `specs/004-coverage-aware-optimizer-verdicts/spec.md`

## Summary

Add coverage verdict metadata to optimizer output artifacts so a run with missing
discovery domains cannot look like an unconditional pass. The change is additive:
existing finding counts, ROI scoring, receipt status fields, and trend metadata
remain intact.

## Technical Context

**Language/Version**: Bash + Python 3
**Primary Dependencies**: Standard library only
**Storage**: Filesystem artifacts in optimizer output directories
**Testing**: Shell tests under `tests/` with deterministic pre-flight-only where applicable
**Target Platform**: Local CLI invocation
**Constraints**: P3 only; no target-policy/P4, P5 cleanup, P7 denominator implementation, repo-agent-core schema work, or BMA shared-surface edits

## Constitution Check

- Report-only optimizer behavior remains unchanged.
- Target repositories are not modified.
- Coverage verdicts are bounded non-claims and must not strengthen recommendations
  when discovery domains are missing.
- Review/verification remains repo-local.

## Project Structure

```text
scripts/
├── repo-optimizer.sh
└── score-operation.sh

schemas/
└── OPTIMIZATION_SCORECARD.schema.json

tests/
└── test-coverage-verdicts.sh

docs/
└── invocation-contract.md
```

## Out Of Scope

- Phase 3 target-policy/P4 behavior.
- P5 cleanup.
- P7 denominator implementation.
- repo-agent-core shared schemas.
- BMA handoffs, roadmap, ledgers, or shared surfaces.

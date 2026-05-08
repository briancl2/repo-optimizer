# Tasks: Coverage-Aware Optimizer Verdicts

**Input**: `specs/004-coverage-aware-optimizer-verdicts/spec.md` and `plan.md`

## Phase 1: Contract

- [x] T001 Create repo-local spec scoped to Phase 2 P3.
- [x] T002 Open and fill repo-local work contract.

## Phase 2: Implementation

- [x] T003 Compute additive discovery coverage metadata from the four domain
  payloads and runtime status.
- [x] T004 Emit `coverage_verdict` and bounded non-claims in
  `OPTIMIZATION_SCORECARD.json` and runtime receipts.
- [x] T005 Add deterministic plan coverage notes without replacing synthesis
  content.
- [x] T006 Preserve existing ROI, receipt scoring, finding counts, and trend fields.

## Phase 3: Tests And Documentation

- [x] T007 Add deterministic tests for 2/4 discovery domains, count agreement, and
  missing-domain recommendation constraints.
- [x] T008 Update scorecard schema and invocation contract.
- [ ] T009 Run focused tests, `make test`, `make check`, repo-local review, work-close,
  commit, and PR creation if possible.

## Explicitly Out Of Scope

- [ ] Phase 3 target-policy/P4.
- [ ] P5 cleanup.
- [ ] P7 denominator implementation.
- [ ] repo-agent-core shared schema changes.
- [ ] BMA shared-surface edits.

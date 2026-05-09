# Tasks: Partial Audit Admission

**Input**: `specs/003-partial-audit-admission/spec.md` and `plan.md`

## Phase 1: Admission Gate

- [x] T001 Add optimizer-local audit admission helper in `scripts/audit-admission.py`.
- [x] T002 Wire admission evaluation into `scripts/repo-optimizer.sh` before pre-flight.
- [x] T003 Emit blocked pre-flight, runtime, scorecard, plan, and operation-eval artifacts when admission fails.

## Phase 2: Research Calibration Path

- [x] T004 Support only `REPO_OPTIMIZER_RESEARCH_MODE=partial-audit-calibration`.
- [x] T005 Require research-mode output paths to include `research-mode/partial-audit-calibration/`.
- [x] T006 Record research mode in `pre-flight.json`, `OPTIMIZATION_SCORECARD.json`, and `OPERATION_EVAL.json`.

## Phase 3: Tests And Documentation

- [x] T007 Add focused tests for completed, partial, failed, missing receipt, missing report, valid research mode, and invalid research path.
- [x] T008 Update existing optimizer-run tests to use completed audit fixtures.
- [x] T009 Document admission contract and research mode in `docs/invocation-contract.md`.
- [x] T010 Block and explicitly classify scan-limited and snapshot-limited completed audit evidence.

## Explicitly Out Of Scope

- [ ] P3 coverage verdicts.
- [ ] repo-auditor receipt emission.
- [ ] target policy context adapters.
- [ ] BMA shared-surface edits.

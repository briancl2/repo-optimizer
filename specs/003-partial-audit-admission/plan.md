# Implementation Plan: Partial Audit Admission

**Branch**: `bma-phase1-partial-audit-admission` | **Date**: 2026-05-07 | **Spec**: `specs/003-partial-audit-admission/spec.md`

## Summary

Add a small optimizer-local audit admission gate before pre-flight discovery.
Normal runs proceed only for completed audit receipts with both scorecard and
report artifacts. Partial/failed/missing receipt shapes write blocked receipts.
The single research bypass is `REPO_OPTIMIZER_RESEARCH_MODE=partial-audit-calibration`
and it is valid only under `research-mode/partial-audit-calibration/` output
paths.

## Technical Context

**Language/Version**: Bash + Python 3
**Primary Dependencies**: Standard library only
**Storage**: Filesystem artifacts in optimizer output directories
**Testing**: Existing shell tests under `tests/` plus focused admission tests
**Target Platform**: Local CLI invocation
**Project Type**: Single repository CLI scripts
**Constraints**: No repo-auditor changes, no P3 coverage verdicts, no target policy adapters, no BMA shared-surface edits

## Constitution Check

- Report-only optimizer behavior remains unchanged after admission.
- Target repositories are not modified.
- Blocked and research-admitted paths explicitly avoid normal readiness claims.
- Review/verification remains bounded to repo-local tests and `make check`.

## Project Structure

```text
scripts/
├── repo-optimizer.sh
├── audit-admission.py
└── score-operation.sh

tests/
├── test-audit-admission.sh
├── test-preflight-tiers.sh
└── test-discovery-payload-capture.sh

docs/
└── invocation-contract.md
```

## Merge-Order Dependency

This branch implements strict default admission in repo-optimizer. It must not
merge to `main` before repo-auditor emits the completed/partial/failed receipt
shape unless both PRs are approved for a same-window merge.

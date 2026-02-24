# Work Contract

## Description

M5.5 validation: prove self-management works end-to-end

## Hypothesis

**Prediction:** repo-optimizer can independently open a work contract, make a documented change, extract a learning, and close the contract with OPERATING_MODEL_SCORECARD >= 12/15 (80%) AND no dimension scoring 0.

**PASS:** `make work-close` produces OPERATING_MODEL_SCORECARD.json with composite >= 12/15, all 4 dimensions > 0, and domain tests pass identically to baseline.

**FAIL:** work-close rejects (missing learnings, placeholder hypothesis), OR composite < 12/15, OR any dimension = 0, OR domain tests regress.

## Work Type

code-change

## Status

- [x] Hypothesis stated
- [ ] Work completed
- [ ] Learnings extracted (or --no-novel-findings)
- [ ] work-close run


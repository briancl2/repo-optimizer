# Work Contract

## Description

Fix find empty-expression bug in pre-flight minimal tier (L270)

## Hypothesis

> **Gate 1 Required.** State a testable prediction with PASS/FAIL criteria.

**Prediction:** The `find: (): empty inner expression` error in `scripts/repo-optimizer.sh` line 116 is caused by a missing line-continuation backslash after `\(` in the minimal budget tier's find command. Fixing this 1-character omission will allow pre-flight to complete on large repos (>1000 files) without error. A regression test will confirm the fix.
**PASS:** `bash scripts/repo-optimizer.sh` completes pre-flight Phase 1 on a repo with >1000 files (minimal tier) without error. Regression test added and passing. `make check` PASS. `make test` PASS (31/31 + new test).
**FAIL:** Pre-flight still errors on minimal tier, or fix introduces regressions in other tiers.

## Work Type

bug-fix

## Status

- [x] Hypothesis stated
- [x] Work completed
- [x] Learnings extracted (or --no-novel-findings)
- [x] work-close run


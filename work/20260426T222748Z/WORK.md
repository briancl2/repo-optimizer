# Work Contract

## Description

First ordinary repo-star run with command-output ROI guard

## Hypothesis

> **Gate 1 Required.** State a testable prediction with PASS/FAIL criteria.

**Prediction:** An ordinary report-only `repo-optimizer` run against a
read-only/copy target fixture will emit governed optimizer artifacts that pass
the fleet `command_output_roi` receipt contract, while an injected copied raw
transcript dump in a governed artifact will fail the same scorer.
**PASS:** Positive production output has a passing
`command_output_roi_receipt`, the negative-control copy fails, repo-native gates
pass, and the real target repo remains clean before/after.
**FAIL:** The positive production output is `not_measured`/failed, the injected
negative control is accepted, repo-native gates fail without a bounded fix, or
the real target repo is mutated.

## Work Type

fleet-run

## Status

- [x] Hypothesis stated
- [x] Work completed
- [x] Learnings extracted (or --no-novel-findings)
- [x] work-close run

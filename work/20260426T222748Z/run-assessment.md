# First Ordinary Command-Output ROI Guarded Run Assessment

## Result

The ordinary report-only optimizer run against a disposable
`briancl2-customer-newsletter` copy completed all production phases:
4/4 discovery payloads, critic, synthesis, `OPTIMIZATION_PLAN.md`,
`OPTIMIZATION_SCORECARD.json`, runtime receipts, and operation scoring.

The retained clean output is `newsletter-optimizer-output-clean/`.

## Command-Output ROI Evidence

- Positive scorer output: `positive-score-operation-clean.json`
- Positive operation verdict: `PASS` (`25/26`)
- Positive `COMMAND_OUTPUT_ROI_RECEIPT`: `pass`
- Positive raw transcript detection: `false`
- Negative-control scorer output: `negative-score-operation-clean.json`
- Negative-control operation verdict: `FAIL`
- Negative-control `COMMAND_OUTPUT_ROI_RECEIPT`: `fail`
- Negative-control violation: raw-looking command transcript injected into copied
  `OPTIMIZATION_PLAN.md`

## Target Safety

The production newsletter repo remained clean before and after the run. The
disposable local copy also remained clean after audit and optimizer execution.

## Owner Fixes Made

The ordinary run exposed scorer-noise bugs outside the command-output ROI
policy itself. `scripts/score-operation.sh` now handles zero-match grep counts
without integer-expression stderr, counts numbered approved-heading styles, and
does not treat domain text such as `timeout/retry` as runtime timeout failure.
Targeted tests were added in `tests/test-score-operation.sh`.

## Non-Claims

This run does not claim cache savings, direct token savings, provider-cache
behavior, target-repo improvement, publication readiness, Gate 4 readiness, or
promotion of `context_pruning`, `prompt_bundle_shape`, or
`transfer_token_efficiency`.

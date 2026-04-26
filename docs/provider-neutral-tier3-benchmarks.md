# Provider-Neutral Tier 3 Benchmarks

Repo-optimizer treats Codex, Copilot CLI, VS Code chat, and future agent
harnesses as adapters. The benchmark evaluator consumes only normalized
`AGENT_RUN_RECEIPTS` and generated `OPTIMIZATION_BENCHMARK_CORPUS` rows.

## Contract

Each normalized run receipt records the harness, provider, model, optional model
version, fixture id, variant, run index, prompt/fixture hashes, raw receipt path,
wall time, exit status, mutation status, correctness status, and optional metric
fields. Metrics must declare their source as `direct` or `proxy`.

Proxy metrics are diagnostic only. They cannot satisfy direct-token,
direct-cost, or cache claims. Cache promotion is excluded from the current Tier
3 package even when receipts contain cached-token fields.

## Flow

1. `make normalize-agent-run-receipts RECEIPTS=<raw> OUTPUT_DIR=<dir>`
   normalizes historical Codex, Copilot, VS Code, or generic receipts.
2. `make collect-live-agent-receipts FIXTURES=<path> ADAPTER=<codex|copilot|generic> OUTPUT_DIR=<dir>`
   collects new provider-neutral receipts.
3. `make build-live-paired-corpus FIXTURES=<path> RECEIPTS=<AGENT_RUN_RECEIPTS.json> OUTPUT_DIR=<dir>`
   builds a live-paired corpus.
4. `make benchmark-optimization-workloads CORPUS=<corpus> OUTPUT_DIR=<dir> MODE=live-paired`
   evaluates dispositions.

## Promotion

Live-paired evidence is stratified by `provider + harness + model +
model_version`.

- One passing stratum can become `provider-scoped`.
- Fleet-portable promotion requires at least two independent passing
  provider/harness strata and no failed or noisy contradictory stratum.
- Cross-provider averages are not used to hide a failed provider or harness.

Target repositories remain read-only. Any target mutation, missing provider or
model metadata, missing paired deltas, failed correctness scorer, or live
repetition count below the threshold fails closed.

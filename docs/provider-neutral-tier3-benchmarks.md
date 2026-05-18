# Provider-Neutral Tier 3 Benchmarks

Repo-optimizer treats Codex, Copilot CLI, VS Code chat, and future agent
harnesses as adapters. The benchmark evaluator consumes only normalized
`AGENT_RUN_RECEIPTS` and generated `OPTIMIZATION_BENCHMARK_CORPUS` rows.

## Contract

Each normalized run receipt records the harness, provider, model, optional model
version, fixture id, variant, run index, prompt/fixture hashes, raw receipt path,
wall time, exit status, mutation status, correctness status, and optional metric
fields. Metrics must declare their source as `direct` or `proxy`.

Burst 126A telemetry adds optional route and fixed-input fields to the same
receipt object: `route_command_argv`, `original_prompt_sha256`,
`rendered_prompt_sha256`, `frozen_pre_render_input_manifest_sha256`,
`quality_gate_state`, `direct_fields_complete`, and
`missing_direct_provider_token_fields`. Direct metric keys may include
`input_tokens`, `output_tokens`, `reasoning_tokens`, `cache_read_tokens`,
`cache_write_tokens`, `request_count`, and `tool_calls`.

Proxy metrics are diagnostic only. They cannot satisfy direct-token,
direct-cost, or cache claims. Cache promotion is excluded from the current Tier
3 package even when receipts contain cached-token fields.

## Flow

1. `make normalize-agent-run-receipts RECEIPTS=<raw> OUTPUT_DIR=<dir>`
   normalizes historical Codex, Copilot, VS Code, or generic receipts.
2. `make collect-live-agent-receipts FIXTURES=<path> ADAPTER=<codex|copilot|generic> OUTPUT_DIR=<dir>`
   collects new provider-neutral receipts. Use `VARIANTS=baseline` or
   `VARIANTS=candidate` to run only one side of a fixed-input route; the default
   `VARIANTS=both` preserves paired collection.
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

# Invocation Contract -- repo-optimizer

> Version: 1.4 | Spec: 054 | Date: 2026-04-20

## Purpose

This contract defines the interface for invoking repo-optimizer, whether
called by an outer-loop orchestrator (run-continuous-loop.sh) or by an
agent (copilot CLI). All consumers must follow this contract.

## Required Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `repo_path` | filesystem path | YES | Absolute path to target repository |
| `audit_dir` | filesystem path | YES | Directory containing SCORECARD.json + AUDIT_REPORT.md from repo-auditor |
| `output_dir` | filesystem path | NO | Where to write optimization artifacts (default: `optimizer_output`) |
| `--patch` | flag | NO | Enable patch generation (default: report-only) |

## Expected Outputs

| Output | Always | Description |
|---|---|---|
| `OPTIMIZATION_PLAN.md` | YES | Human-readable optimization plan |
| `OPTIMIZATION_SCORECARD.json` | YES | Machine-readable scoring of optimization |
| `pre-flight.json` | YES | Pre-flight analysis (budget tier, bottom-2 dimensions) |
| `runtime-safe-target-context.md` | YES | Deterministic inventory for safe LLM discovery |
| `critic-phase-receipt.json` | YES | Critic phase artifact-contract receipt |
| `synthesis-phase-receipt.json` | YES | Synthesis phase artifact-contract receipt |
| `RUNTIME_RECEIPTS.json` | YES | Phase-by-phase runtime status and fail-closed receipts |
| `PATCH_PACK/*.patch` | Only with --patch | Unified diff patches |

## Additive Bounded Consumer

`repo-optimizer` also supports a bounded advisory-consumer path for retained
`ADVISORY_DECISIONS.json` artifacts:

```bash
make transfer-oracle DECISIONS=<path> [OUTPUT_DIR=<dir>] [CAPABILITY_FAMILY=<family>] [HOTSPOT_ID=<hotspot>]
```

This emits `TRANSFER_ORACLE_RECEIPT.json`, a shared-core receipt that says
whether the selected advisory decisions are `ready`, `partial`, or `blocked`
for a repo-optimizer follow-on. It is an optimizer-readiness surface only; it
does not claim that an optimizer patch or plan has already been generated.

The receipt also carries normalized calibration metadata:
`capability_state`, `provider_scope`, `calibration_basis`,
`evidence_provenance`, and `downstream_admission`. These fields keep the
mixed external-critique gate explicit without upgrading partial or blocked
states into remediation claims.
When a selected batch spans multiple calibration families, the top-level
`calibration_basis` field preserves that mix as a sorted, comma-separated
summary instead of collapsing it into one stronger basis claim.

## Error Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | SCORECARD.json not found in audit_dir |
| 1 | AUDIT_REPORT.md not found in audit_dir |
| 1 | Target repo path does not exist |
| 1 | Pre-flight failed |

## Invocation Patterns

### Pattern A: Bash (from orchestrator)

```bash
bash scripts/repo-optimizer.sh "$REPO" "$AUDIT_DIR" "$OUTPUT_DIR"
# With patches:
bash scripts/repo-optimizer.sh "$REPO" "$AUDIT_DIR" "$OUTPUT_DIR" --patch
```

### Pattern B: Agent (from copilot CLI)

```bash
cd ~/repos/repo-optimizer && timeout 600 copilot --model claude-opus-4.7 \
  -p "Read .agents/repo-optimizer.agent.md. Optimize $REPO. \
      AUDIT_DIR: $AUDIT_DIR. OUTPUT: $OUTPUT_DIR." \
  --allow-all --no-ask-user
```

**CRITICAL (L274/L6):** The agent MUST call `repo-optimizer.sh` as a single
command via `run_in_terminal`. Do NOT dispatch discovery subagents individually.
The bash orchestrator manages directory layout and phase sequencing.

Long-running Copilot-backed phases in `repo-optimizer.sh` must emit bounded
stdout progress while raw JSONL artifacts are being captured, so outer agent
shell supervision can keep the public Pattern B run alive until terminal
artifacts materialize.

Governed optimizer artifacts summarize command evidence instead of copying raw
stdout/stderr transcripts. `OPTIMIZATION_PLAN.md`,
`OPTIMIZATION_SCORECARD.json`, and critic/synthesis human outputs should cite
the relevant command, outcome, and artifact path; raw logs remain in `.jsonl`,
`optimizer-stdout.txt`, phase receipts, or `RUNTIME_RECEIPTS.json`.

## Artifact Path Conventions

All outputs go to `$output_dir/`:
- `$output_dir/pre-flight.json`
- `$output_dir/OPTIMIZATION_PLAN.md`
- `$output_dir/OPTIMIZATION_SCORECARD.json`
- `$output_dir/critic-phase-receipt.json`
- `$output_dir/synthesis-phase-receipt.json`
- `$output_dir/RUNTIME_RECEIPTS.json`
- `$output_dir/PATCH_PACK/*.patch` (if --patch)

## Terminal Artifact Contract

Copilot-backed critic and synthesis phases are fail-closed on one authoritative
artifact contract:

- critic producer: final non-tool `assistant.message` content materialized to
  `critic-verdicts.md`
- synthesis producer: final non-tool `assistant.message` content materialized to
  `OPTIMIZATION_PLAN.md`
- diagnostic fallback: retained `*.jsonl` transcript plus explicit
  `critic-phase-receipt.json` / `synthesis-phase-receipt.json`
- downstream rule: synthesis consumes `critic-verdicts.md` only when the critic
  receipt status is `completed`; otherwise the runtime skips synthesis with an
  explicit upstream failure receipt instead of attempting a missing-path read
- receipt metadata: phase and runtime receipts include proof-boundary fields
  that keep artifact existence, acceptance/startability, and phase completion
  separate via `proof_boundary.authority_fingerprint`,
  `proof_boundary.heartbeat_status`, `proof_boundary.artifact_depth`,
  `proof_boundary.receipt_depth`, and
  `proof_boundary.phase_classification_evidence`

## Version History

| Version | Date | Change |
|---|---|---|
| 1.4 | 2026-04-20 | Added calibration metadata for transfer-oracle receipts and documented mixed-family calibration-basis summarization |
| 1.3 | 2026-04-19 | Added proof-boundary metadata to phase and runtime receipts so artifact existence, startability, and phase completion remain distinct |
| 1.2 | 2026-04-13 | Pattern B contract now requires bounded stdout progress during long Copilot-backed phases so public agent invocations retain terminal artifacts instead of dying in a silent shell wait |
| 1.1 | 2026-03-30 | Added per-phase artifact-contract receipts and explicit fail-closed terminal artifact rules |
| 1.0 | 2026-02-24 | Initial contract (spec 054) |

# Invocation Contract -- repo-optimizer

> Version: 1.8 | Spec: 054 + 003 + 004 + 005 + 006 | Date: 2026-05-08

## Purpose

This contract defines the interface for invoking repo-optimizer, whether
called by an outer-loop orchestrator (run-continuous-loop.sh) or by an
agent (copilot CLI). All consumers must follow this contract.

## Required Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `repo_path` | filesystem path | YES | Absolute path to target repository |
| `audit_dir` | filesystem path | YES | Directory containing a completed audit receipt, SCORECARD.json, and AUDIT_REPORT.md from repo-auditor |
| `output_dir` | filesystem path | NO | Where to write optimization artifacts (default: `optimizer_output`) |
| `--patch` | flag | NO | Enable patch generation (default: report-only) |

## Expected Outputs

| Output | Always | Description |
|---|---|---|
| `OPTIMIZATION_PLAN.md` | YES | Human-readable optimization plan |
| `OPTIMIZATION_SCORECARD.json` | YES | Machine-readable scoring of optimization |
| `pre-flight.json` | YES | Pre-flight analysis (budget tier, bottom-2 dimensions, pointer-only target policy context) |
| `runtime-safe-target-context.md` | YES | Deterministic inventory for safe LLM discovery |
| `target-policy-context.json` | YES | Pointer-only target policy context metadata mirrored in `pre-flight.json.target_policy_context` |
| `critic-phase-receipt.json` | YES | Critic phase artifact-contract receipt |
| `synthesis-phase-receipt.json` | YES | Synthesis phase artifact-contract receipt |
| `RUNTIME_RECEIPTS.json` | YES | Phase-by-phase runtime status and fail-closed receipts |
| `audit-admission-receipt.json` | YES | Audit receipt admission verdict before optimizer discovery |
| `PATCH_PACK/*.patch` | Only with --patch | Unified diff patches |

`OPTIMIZATION_SCORECARD.json`, `RUNTIME_RECEIPTS.json`, `OPERATION_EVAL.json`,
and the deterministic coverage section in `OPTIMIZATION_PLAN.md` carry additive
coverage verdict metadata. These fields do not replace ROI scoring, receipt
status, score trends, or existing finding counts.

`pre-flight.json.discovery_scope` also carries additive denominator metadata for
optimizer budgeting:

- `denominator_semantics.name=optimizer_budgeting_denominator`
- `denominator_semantics.description` explains that the denominator is regular
  files under the target repository after excluded path classes are removed
- `denominator_semantics.total_files_field` points to `file_count` and
  `discovery_scope.total_files`
- `denominator_semantics.eligible_files_field` points to
  `discovery_scope.eligible_files`
- `denominator_semantics.coverage_pct_field` points to
  `discovery_scope.coverage_pct`
- `excluded_path_classes` lists `.git` and `node_modules`

These fields are metadata only. They do not change `file_count`,
`discovery_scope.total_files`, `discovery_scope.eligible_files`,
`discovery_scope.coverage_pct`, budget tier selection, coverage verdicts, or
SCORECARD consumers.

`pre-flight.json.target_policy_context` carries additive pointer-only metadata
for obvious target-local policy files. The same object is written to
`target-policy-context.json`, and `runtime-safe-target-context.md` renders a
compact `## Target Policy Pointers` table. Matching is intentionally bounded to
clear policy paths such as `system/policy/**`, `.github/**policy**`,
`docs/**policy**`, and root `*policy*.{json,yaml,yml,md}` files.

This context is not a policy engine. Its `policy_context_non_claim` says listed
files are for optimizer context and not fully interpreted. Consumers may use the
pointers to explain, downgrade, or require stronger authority for potentially
policy-conflicting findings, but must not claim complete target policy
interpretation from this artifact alone.

## Audit Receipt Admission

Normal optimizer runs are strict consumers of repo-auditor completion receipts.
The optimizer only makes a normal readiness claim when all of these inputs are
present:

1. `SCORECARD.json`
2. `AUDIT_REPORT.md`
3. a completed audit receipt (`AUDIT_RUN_RECEIPT.json`, `AUDIT_RECEIPT.json`, or
   `SCORECARD_RECEIPTS.json`) whose audit status normalizes to `completed`

Admission outcomes:

| Audit input shape | Normal admission | Receipt behavior |
|---|---|---|
| Completed receipt + scorecard + audit report | admitted | `audit-admission-receipt.json` records `admission_status=admitted` and `normal_readiness_claim=true` |
| Partial receipt | blocked | blocked receipts are written; no normal readiness claim is emitted |
| Failed receipt | blocked | blocked receipts are written; no normal readiness claim is emitted |
| Missing receipt | blocked | blocked receipts are written even when legacy `SCORECARD.json` and `AUDIT_REPORT.md` exist |
| Completed receipt missing `AUDIT_REPORT.md` | blocked | blocked receipts are written because required report materialization is incomplete |

The only non-normal bypass is the explicit calibration mode:

```bash
REPO_OPTIMIZER_RESEARCH_MODE=partial-audit-calibration \
  bash scripts/repo-optimizer.sh "$REPO" "$AUDIT_DIR" \
  "research-mode/partial-audit-calibration/<run-id>"
```

Research mode must write under an output path containing
`research-mode/partial-audit-calibration/` and must still carry an audit receipt
or scorecard audit status that proves an incomplete audit shape. The run records
`research_mode=partial-audit-calibration` in `pre-flight.json`,
`OPTIMIZATION_SCORECARD.json`, and `OPERATION_EVAL.json`. Research mode preserves
partial-audit calibration evidence only; it does not create a normal readiness
claim.

## Coverage-Aware Optimizer Verdicts

Optimizer outputs include an additive discovery-coverage verdict:

| Verdict | Meaning | Recommendation strength |
|---|---|---|
| `complete` | All four discovery domains produced payloads and downstream critic/synthesis completed | `strong` |
| `pass_with_coverage_gap` | A plan materialized but at least one discovery domain is missing | `limited` |
| `partial` | Discovery was intentionally skipped or downstream phases did not fully complete | `diagnostic` |
| `blocked` | No discovery domain completed, or audit admission blocked before discovery | `none` |

The expected discovery domains are `decomposition`, `consolidation`,
`extraction`, and `standardization`. Missing domains are listed in
`discovery_coverage.missing_domains`; any missing domain constrains
`recommendation_strength` below `strong` and emits bounded non-claims that the
run did not observe complete discovery coverage and may have missed
higher-priority opportunities. Coverage verdicts are P3 discovery-coverage
metadata only: they do not implement P4 target-policy interpretation, P5
cleanup, or repo-agent-core shared schema changes. P4 pointer-only context is
carried separately in `pre-flight.json.target_policy_context`; P7 (BMA Phase 3A
denominator lane) semantics are carried separately in
`pre-flight.json.discovery_scope` metadata.

The optimizer also writes a deterministic `## Coverage Verdict` section in
`OPTIMIZATION_PLAN.md` with machine finding counts. The
`finding_count_agreement` object in `OPTIMIZATION_SCORECARD.json` records whether
those plan-declared counts match the JSON scorecard counts.

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
| 1 | Audit admission blocked; inspect `audit-admission-receipt.json.blocker.code` |

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
- `$output_dir/target-policy-context.json`
- `$output_dir/audit-admission-receipt.json`
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
| 1.8 | 2026-05-08 | Added pointer-only target policy context metadata in `pre-flight.json`, `target-policy-context.json`, and runtime-safe context |
| 1.7 | 2026-05-08 | Added additive pre-flight discovery-scope denominator semantics and excluded path-class metadata |
| 1.6 | 2026-05-08 | Added additive coverage verdict metadata, missing-domain recommendation constraints, and plan/scorecard finding-count agreement |
| 1.5 | 2026-05-07 | Added completed/partial/failed audit receipt admission and the explicit partial-audit calibration research mode |
| 1.4 | 2026-04-20 | Added calibration metadata for transfer-oracle receipts and documented mixed-family calibration-basis summarization |
| 1.3 | 2026-04-19 | Added proof-boundary metadata to phase and runtime receipts so artifact existence, startability, and phase completion remain distinct |
| 1.2 | 2026-04-13 | Pattern B contract now requires bounded stdout progress during long Copilot-backed phases so public agent invocations retain terminal artifacts instead of dying in a silent shell wait |
| 1.1 | 2026-03-30 | Added per-phase artifact-contract receipts and explicit fail-closed terminal artifact rules |
| 1.0 | 2026-02-24 | Initial contract (spec 054) |

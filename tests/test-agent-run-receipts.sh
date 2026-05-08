#!/usr/bin/env bash
# test-agent-run-receipts.sh — Verify provider-neutral live-paired receipt contracts.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0
FAIL=0

check_cmd() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Agent Run Receipt Contract Test ==="

python3 - "$TEST_TMPDIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])

(root / "fake-codex.jsonl").write_text(
    "\n".join(
        [
            json.dumps({"type": "session_meta", "payload": {"model": "gpt-5.5"}, "timestamp": "2026-04-26T00:00:00Z"}),
            json.dumps({"type": "response_item", "item": {"usage": {"inputTokens": 1000, "outputTokens": 100, "reasoningTokens": 25}}, "timestamp": "2026-04-26T00:00:05Z"}),
        ]
    )
    + "\n",
    encoding="utf-8",
)
(root / "fake-copilot-events.jsonl").write_text(
    "\n".join(
        [
            json.dumps({"type": "session", "data": {"selectedModel": "claude-opus-4.6"}, "timestamp": "2026-04-26T00:01:00Z"}),
            json.dumps({"type": "assistant", "data": {"inputTokens": 900, "outputTokens": 90, "cacheReadTokens": 12}, "timestamp": "2026-04-26T00:01:04Z"}),
        ]
    )
    + "\n",
    encoding="utf-8",
)
(root / "fake-vscode.jsonl").write_text(
    json.dumps({"kind": 2, "v": {"modelId": "gpt-5.4", "provider": "github-copilot", "usage": {"inputTokens": 800, "outputTokens": 80}}, "timestamp": "2026-04-26T00:02:00Z"})
    + "\n",
    encoding="utf-8",
)
(root / "fake-generic.json").write_text(
    json.dumps({"model": "future-model-v1", "inputTokens": 700, "outputTokens": 70, "prompt": "generic provider prompt"}),
    encoding="utf-8",
)

fixtures = {
    "schema_version": "1.0.0",
    "artifact": "LIVE_PAIRED_FIXTURES",
    "corpus_id": "provider-neutral-tier3-fixture",
    "target_label": "provider-neutral Tier 3 fixture",
    "thresholds": {
        "paired_fixture_count_minimum": 3,
        "token_or_input_size_delta": {"min_pct": 15, "min_absolute_tokens": 500},
        "output_noise_delta": {"min_pct": 20},
        "wall_time_delta": {"max_regression_pct": 10, "speed_claim_min_improvement_pct": 10},
        "llm_backed_run_count": 5,
        "variance_multiplier": 2,
    },
    "fixtures": [
        {
            "fixture_id": f"context-{idx}",
            "source_repo": "build-meta-analysis",
            "bucket": "bma",
            "tactic_id": "context_pruning",
            "claim_types": ["token"],
            "baseline_prompt": f"baseline context fixture {idx}",
            "candidate_prompt": f"candidate context fixture {idx}",
        }
        for idx in range(1, 4)
    ]
    + [
        {
            "fixture_id": f"transfer-{idx}",
            "source_repo": "repo-star",
            "bucket": "repo_star_transfer",
            "tactic_id": "transfer_token_efficiency",
            "claim_types": ["token"],
            "baseline_prompt": f"baseline transfer fixture {idx}",
            "candidate_prompt": f"candidate transfer fixture {idx}",
        }
        for idx in range(1, 4)
    ]
    + [
        {
            "fixture_id": "missing-metadata",
            "source_repo": "repo-star",
            "bucket": "repo_star_transfer",
            "tactic_id": "command_output_roi",
            "claim_types": ["output_noise"],
            "baseline_prompt": "baseline missing metadata",
            "candidate_prompt": "candidate missing metadata",
        }
    ],
}
(root / "fixtures.json").write_text(json.dumps(fixtures, indent=2, sort_keys=True) + "\n", encoding="utf-8")

receipts = []

def add_pair(fixture_id: str, provider: str, harness: str, model: str, run_index: int, base: int | None, cand: int | None, proxy: bool = False, baseline_noise: int | None = None, candidate_noise: int | None = None) -> None:
    for variant, value in (("baseline", base), ("candidate", cand)):
        metrics = {}
        if value is not None:
            metrics["input_tokens"] = {"value": value, "source": "proxy" if proxy else "direct"}
        if baseline_noise is not None and candidate_noise is not None:
            metrics["irrelevant_output_bytes"] = {
                "value": baseline_noise if variant == "baseline" else candidate_noise,
                "source": "direct",
            }
        receipts.append(
            {
                "schema_version": "1.0.0",
                "harness": harness,
                "provider": provider,
                "model": model,
                "model_version": "2026-04",
                "model_family": provider,
                "invocation_surface": harness,
                "fixture_id": fixture_id,
                "variant": variant,
                "run_index": run_index,
                "started_at": "2026-04-26T00:00:00Z",
                "completed_at": "2026-04-26T00:00:01Z",
                "wall_time_ms": 1000,
                "prompt_hash": f"{fixture_id}-{variant}-{run_index}",
                "fixture_hash": fixture_id,
                "raw_receipt_path": f"fixture://{fixture_id}/{provider}/{variant}/{run_index}",
                "exit_status": "success",
                "target_repo_mutated": False,
                "correctness_pass": True,
                "closeout_truth_pass": True,
                "metrics": metrics,
            }
        )

for fixture_id in ["context-1", "context-2", "context-3"]:
    for run_index in range(1, 6):
        # Codex stratum clears the direct token threshold.
        add_pair(fixture_id, "openai", "codex-cli", "gpt-5.5", run_index, 4000, 3000 + run_index)
        # Copilot stratum stays measured but below threshold.
        add_pair(fixture_id, "github-copilot", "copilot-cli", "claude-opus-4.6", run_index, 4000, 3950)

for fixture_id in ["transfer-1", "transfer-2", "transfer-3"]:
    for run_index in range(1, 6):
        # Proxy token metrics are retained but must not satisfy direct-token claims.
        add_pair(fixture_id, "future-provider", "future-harness", "future-model", run_index, 4000, 2500, proxy=True)

for run_index in range(1, 6):
    add_pair("missing-metadata", "", "generic-command", "", run_index, None, None, baseline_noise=5000, candidate_noise=3000)

(root / "receipts.json").write_text(
    json.dumps(
        {
            "schema_version": "1.0.0",
            "artifact": "AGENT_RUN_RECEIPTS",
            "generated_at": "2026-04-26T00:00:00Z",
            "receipts": receipts,
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY

for source in codex copilot vscode generic; do
    case "$source" in
        codex)
            input="$TEST_TMPDIR/fake-codex.jsonl"
            ;;
        copilot)
            input="$TEST_TMPDIR/fake-copilot-events.jsonl"
            ;;
        vscode)
            input="$TEST_TMPDIR/fake-vscode.jsonl"
            ;;
        generic)
            input="$TEST_TMPDIR/fake-generic.json"
            ;;
    esac
    python3 "$OPT_DIR/scripts/normalize-agent-run-receipts.py" \
        --source-format "$source" \
        --input "$input" \
        --output "$TEST_TMPDIR/normalized-$source.json" \
        --fixture-id "normalize-$source" \
        --variant baseline \
        --run-index 1 >/dev/null
done

check_cmd "Codex normalizer emits shared receipt artifact" python3 - "$TEST_TMPDIR/normalized-codex.json" <<'PY'
from __future__ import annotations
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
receipt = payload["receipts"][0]
assert payload["artifact"] == "AGENT_RUN_RECEIPTS", payload
assert receipt["harness"] == "codex-cli", receipt
assert receipt["provider"] == "openai", receipt
assert receipt["metrics"]["input_tokens"]["source"] == "direct", receipt
PY

check_cmd "Copilot normalizer emits shared receipt artifact" python3 - "$TEST_TMPDIR/normalized-copilot.json" <<'PY'
from __future__ import annotations
import json, sys
receipt = json.load(open(sys.argv[1], encoding="utf-8"))["receipts"][0]
assert receipt["harness"] == "copilot-cli", receipt
assert receipt["provider"] == "github-copilot", receipt
assert receipt["metrics"]["cached_tokens"]["source"] == "direct", receipt
PY

check_cmd "VS Code and generic normalizers preserve provider-neutral fields" python3 - "$TEST_TMPDIR/normalized-vscode.json" "$TEST_TMPDIR/normalized-generic.json" <<'PY'
from __future__ import annotations
import json, sys
vscode = json.load(open(sys.argv[1], encoding="utf-8"))["receipts"][0]
generic = json.load(open(sys.argv[2], encoding="utf-8"))["receipts"][0]
assert vscode["harness"] == "vscode-chat", vscode
assert generic["harness"] == "generic-command", generic
assert "metrics" in vscode and "metrics" in generic
PY

python3 "$OPT_DIR/scripts/build-live-paired-corpus.py" \
    --fixtures "$TEST_TMPDIR/fixtures.json" \
    --receipts "$TEST_TMPDIR/receipts.json" \
    --output "$TEST_TMPDIR/live-corpus.json" \
    --minimum-total 7 >/dev/null

OUTPUT="$TEST_TMPDIR/benchmark-output"
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$TEST_TMPDIR/live-corpus.json" \
    --output-dir "$OUTPUT" \
    --mode live-paired >/dev/null

RESULTS="$OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json"

check_cmd "builder emits live-paired corpus rows from normalized receipts" python3 - "$TEST_TMPDIR/live-corpus.json" <<'PY'
from __future__ import annotations
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["artifact"] == "OPTIMIZATION_BENCHMARK_CORPUS", payload
assert len(payload["workloads"]) == 10, len(payload["workloads"])
assert all(row["allowed_modes"] == ["live-paired"] for row in payload["workloads"])
PY

check_cmd "proxy token rows cannot satisfy direct-token claims" python3 - "$RESULTS" <<'PY'
from __future__ import annotations
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
rollups = {row["tactic_id"]: row for row in payload["tactic_rollups"]}
transfer = rollups["transfer_token_efficiency"]
assert transfer["disposition"] == "not-measured", transfer
assert transfer["eligible_workload_count"] == 0, transfer
PY

check_cmd "passing Codex plus failing Copilot is provider-scoped, not fleet-portable" python3 - "$RESULTS" <<'PY'
from __future__ import annotations
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
context = {row["tactic_id"]: row for row in payload["tactic_rollups"]}["context_pruning"]
assert context["disposition"] == "promoted", context
assert context["promotion_scope"] == "provider-scoped", context
assert context["fleet_portable"] is False, context
strata = {(row["provider"], row["harness"]): row["disposition"] for row in context["provider_strata"]}
assert strata[("openai", "codex-cli")] == "promoted", strata
assert strata[("github-copilot", "copilot-cli")] == "rejected", strata
PY

check_cmd "live-paired missing provider/model metadata fails closed" python3 - "$RESULTS" <<'PY'
from __future__ import annotations
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
rows = {row["workload_id"]: row for row in payload["workload_results"]}
missing = [row for row in rows.values() if row["tactic_id"] == "command_output_roi"][0]
assert missing["disposition"] == "not-measured", missing
assert "lacks provider metadata" in missing["reason"], missing
PY

PAIR_FIXTURES="$TEST_TMPDIR/artifact-reuse-fixtures.json"
PAIR_RECEIPT="$TEST_TMPDIR/artifact-reuse-pair.json"
PAIR_NORMALIZED="$TEST_TMPDIR/artifact-reuse-normalized.json"
PAIR_CORPUS="$TEST_TMPDIR/artifact-reuse-corpus.json"
PAIR_OUTPUT="$TEST_TMPDIR/artifact-reuse-output"

write_pair_receipt() {
    local output="$1"
    local scenario="$2"
    python3 - "$output" "$scenario" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

output = Path(sys.argv[1])
scenario = sys.argv[2]

def row(name: str, input_tokens: int, output_tokens: int, requests: int, tools: int) -> dict:
    return {
        "row_name": name,
        "summary": {
            "run_id": f"20260508T15000{name[0]}Z",
            "date_range": "2025-12-05 to 2026-02-13",
            "mode": "benchmark",
            "model": "gpt-5.5",
            "final_status": "pass",
            "overall_return_code": 0,
            "phase_return_code": 0,
            "validation_return_code": 0,
            "curated_receipt_return_code": 0,
        },
        "metrics": {
            "loaded": True,
            "phase_id": "phase3_stdout_no_tools_artifact_reuse" if name == "candidate" else "phase3_curation",
            "model": "gpt-5.5",
            "exit_code": 0,
            "prompt_sha256": f"{name}-prompt",
            "session_detection_status": "bound_candidate",
            "bound_candidate_count": 1,
            "candidate_count": 1,
            "direct_fields_complete": True,
            "missing_direct_provider_token_fields": [],
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "reasoning_tokens": 100,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
            "request_count": requests,
            "tool_calls": tools,
        },
        "passes": True,
        "errors": [],
    }

sidecar = {"exists": True, "sha256": "abc", "size_bytes": 1}
payload = {
    "schema_version": 1,
    "receipt_type": "artifact_reuse_stdout_no_tools_phase3_pair",
    "generated_at_utc": "2026-05-08T15:41:53Z",
    "slice": {"start": "2025-12-05", "end": "2026-02-13", "mode": "benchmark", "model": "gpt-5.5", "candidate_run_id": "20260508T150000Z"},
    "fixture": {
        "manifest_id": "benchmark-anchor-2025-12-05_2026-02-13",
        "manifest_sha256": "manifest-sha",
        "source_pack_sha256": "source-pack-sha",
    },
    "selected_source_no_refetch": {
        "exists": True,
        "sha256": "no-refetch-sha",
        "admission_verdict": "admit_no_refetch",
        "source_pack_sha256": "source-pack-sha",
        "sidecars": {
            "phase2_selected_source_ids": dict(sidecar),
            "phase2_fetch_attempt_ledger": dict(sidecar),
            "phase2_no_refetch_compliance": dict(sidecar),
        },
    },
    "candidate": row("candidate", 30000, 5000, 1, 0),
    "control": row("control", 300000, 15000, 8, 17),
    "admission": {
        "admitted_for_single_live_benchmark_pair": True,
        "verdict": "admit_single_pair_stdout_no_tools_evidence",
        "blockers": [],
    },
    "non_claims": [
        "This receipt admits at most one bounded Phase 3 benchmark pair.",
        "It is not production behavior, not a durable savings proof, not a billing claim, and not a cache-savings claim.",
    ],
}

if scenario == "missing_direct_fields":
    payload["candidate"]["metrics"]["direct_fields_complete"] = False
    payload["candidate"]["metrics"]["missing_direct_provider_token_fields"] = ["inputTokens"]
    del payload["candidate"]["metrics"]["input_tokens"]
elif scenario == "request_tool_amplification":
    payload["candidate"]["metrics"]["request_count"] = 9
    payload["candidate"]["metrics"]["tool_calls"] = 18
elif scenario == "candidate_nonzero_tools_below_control":
    payload["candidate"]["metrics"]["tool_calls"] = 1
elif scenario == "missing_no_refetch":
    payload["selected_source_no_refetch"]["sidecars"]["phase2_no_refetch_compliance"]["exists"] = False
elif scenario == "stale_dollar_claim":
    payload["receipt_stale"] = True
    payload["dollar_savings_claimed"] = True

output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

write_pair_fixtures() {
    python3 - "$PAIR_FIXTURES" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": "1.0.0",
    "artifact": "LIVE_PAIRED_FIXTURES",
    "corpus_id": "artifact-reuse-stdout-no-tools-fixture",
    "target_label": "artifact reuse stdout/no-tools fixture",
    "thresholds": {
        "paired_fixture_count_minimum": 1,
        "token_or_input_size_delta": {"min_pct": 15, "min_absolute_tokens": 500},
        "llm_backed_run_count": 1,
        "variance_multiplier": 2,
    },
    "fixtures": [{
        "fixture_id": "benchmark-anchor-2025-12-05_2026-02-13",
        "source_repo": "briancl2-customer-newsletter",
        "bucket": "private_newsletter",
        "tactic_id": "artifact_reuse_stdout_no_tools_phase3",
        "claim_types": ["token"],
        "counts_toward_promotion": True,
    }],
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

run_pair_scenario() {
    local scenario="$1"
    rm -rf "$PAIR_OUTPUT"
    write_pair_fixtures
    write_pair_receipt "$PAIR_RECEIPT" "$scenario"
    python3 "$OPT_DIR/scripts/normalize-agent-run-receipts.py" \
        --input "$PAIR_RECEIPT" \
        --output "$PAIR_NORMALIZED" >/dev/null
    python3 "$OPT_DIR/scripts/build-live-paired-corpus.py" \
        --fixtures "$PAIR_FIXTURES" \
        --receipts "$PAIR_NORMALIZED" \
        --output "$PAIR_CORPUS" \
        --minimum-total 1 >/dev/null
    python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
        --corpus "$PAIR_CORPUS" \
        --output-dir "$PAIR_OUTPUT" \
        --mode live-paired >/dev/null
}

run_pair_scenario positive
check_cmd "artifact reuse pair receipt normalizes and promotes positive direct-token row" python3 - "$PAIR_NORMALIZED" "$PAIR_CORPUS" "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
normalized = json.load(open(sys.argv[1], encoding="utf-8"))
corpus = json.load(open(sys.argv[2], encoding="utf-8"))
results = json.load(open(sys.argv[3], encoding="utf-8"))
assert len(normalized["receipts"]) == 2, normalized
workload = corpus["workloads"][0]
assert workload["candidate"]["request_count"] == 1, workload
assert workload["baseline"]["tool_calls"] == 17, workload
row = results["workload_results"][0]
assert row["disposition"] == "promoted", row
assert row["artifact_reuse_gate"]["passed"] is True, row
assert row["artifact_reuse_gate"]["request_count_delta"] == -7, row
assert row["artifact_reuse_gate"]["tool_calls_delta"] == -17, row
PY

run_pair_scenario missing_direct_fields
check_cmd "artifact reuse pair fails closed when direct token fields are missing" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
assert row["disposition"] == "not-measured", row
assert row["artifact_reuse_gate"]["direct_fields_complete"] is False, row
assert "direct provider token fields are incomplete" in row["reason"], row
PY

run_pair_scenario request_tool_amplification
check_cmd "artifact reuse pair evaluates request/tool amplification separately" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
gate = row["artifact_reuse_gate"]
assert row["disposition"] == "not-measured", row
assert gate["request_count_delta"] == 1, gate
assert gate["tool_calls_delta"] == 1, gate
assert "candidate request count is higher than control" in row["reason"], row
PY

run_pair_scenario candidate_nonzero_tools_below_control
check_cmd "artifact reuse pair rejects any candidate tool calls" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
gate = row["artifact_reuse_gate"]
assert row["disposition"] == "not-measured", row
assert gate["candidate_tool_calls"] == 1, gate
assert gate["tool_calls_delta"] == -16, gate
assert "candidate tool calls are nonzero for stdout/no-tools receipt" in row["reason"], row
PY

run_pair_scenario missing_no_refetch
check_cmd "artifact reuse pair fails closed when no-refetch binding is missing" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
assert row["disposition"] == "not-measured", row
assert row["artifact_reuse_gate"]["no_refetch_bound"] is False, row
assert "selected-source/no-refetch binding is incomplete" in row["reason"], row
PY

run_pair_scenario positive
python3 - "$PAIR_NORMALIZED" <<'PY'
from __future__ import annotations
import json, sys
path = sys.argv[1]
payload = json.load(open(path, encoding="utf-8"))
for receipt in payload["receipts"]:
    if receipt.get("variant") == "candidate":
        receipt.pop("artifact_reuse_stdout_no_tools_boundary", None)
json.dump(payload, open(path, "w", encoding="utf-8"), indent=2, sort_keys=True)
PY
python3 "$OPT_DIR/scripts/build-live-paired-corpus.py" \
    --fixtures "$PAIR_FIXTURES" \
    --receipts "$PAIR_NORMALIZED" \
    --output "$PAIR_CORPUS" \
    --minimum-total 1 >/dev/null
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$PAIR_CORPUS" \
    --output-dir "$PAIR_OUTPUT" \
    --mode live-paired >/dev/null
check_cmd "artifact reuse pair fails closed when candidate boundary is missing" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
gate = row["artifact_reuse_gate"]
assert row["disposition"] == "not-measured", row
assert gate["row_boundaries_present"] == {"candidate": False, "control": True}, gate
assert "artifact reuse control and candidate boundaries are both required" in row["reason"], row
PY

run_pair_scenario positive
python3 - "$PAIR_NORMALIZED" <<'PY'
from __future__ import annotations
import json, sys
path = sys.argv[1]
payload = json.load(open(path, encoding="utf-8"))
for receipt in payload["receipts"]:
    boundary = receipt.get("artifact_reuse_stdout_no_tools_boundary", {})
    if receipt.get("variant") == "baseline":
        boundary.setdefault("boundary_claims", {})["dollar_savings_claimed"] = True
    if receipt.get("variant") == "candidate":
        boundary.setdefault("boundary_claims", {})["dollar_savings_claimed"] = False
json.dump(payload, open(path, "w", encoding="utf-8"), indent=2, sort_keys=True)
PY
python3 "$OPT_DIR/scripts/build-live-paired-corpus.py" \
    --fixtures "$PAIR_FIXTURES" \
    --receipts "$PAIR_NORMALIZED" \
    --output "$PAIR_CORPUS" \
    --minimum-total 1 >/dev/null
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$PAIR_CORPUS" \
    --output-dir "$PAIR_OUTPUT" \
    --mode live-paired >/dev/null
check_cmd "artifact reuse pair preserves forbidden claim flags across rows" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
gate = row["artifact_reuse_gate"]
assert row["disposition"] == "not-measured", row
assert gate["invalid_claim_boundaries"] == ["dollar_savings_claimed"], gate
assert "forbidden claim boundary fields" in row["reason"], row
PY

run_pair_scenario stale_dollar_claim
check_cmd "artifact reuse pair rejects stale or dollar-claim boundaries" python3 - "$PAIR_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["workload_results"][0]
gate = row["artifact_reuse_gate"]
assert row["disposition"] == "not-measured", row
assert gate["invalid_claim_boundaries"] == ["dollar_savings_claimed", "receipt_stale"], gate
assert "forbidden claim boundary fields" in row["reason"], row
PY

if python3 -c "import jsonschema" 2>/dev/null; then
    check_cmd "agent run receipt schema validates generated receipts" python3 - "$TEST_TMPDIR/receipts.json" "$OPT_DIR/schemas/AGENT_RUN_RECEIPTS.schema.json" <<'PY'
from __future__ import annotations
import json, sys, jsonschema
jsonschema.validate(json.load(open(sys.argv[1], encoding="utf-8")), json.load(open(sys.argv[2], encoding="utf-8")))
PY
    check_cmd "live paired fixture schema validates generated fixtures" python3 - "$TEST_TMPDIR/fixtures.json" "$OPT_DIR/schemas/LIVE_PAIRED_FIXTURES.schema.json" <<'PY'
from __future__ import annotations
import json, sys, jsonschema
jsonschema.validate(json.load(open(sys.argv[1], encoding="utf-8")), json.load(open(sys.argv[2], encoding="utf-8")))
PY
else
    echo "  SKIP: jsonschema module not installed"
fi

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

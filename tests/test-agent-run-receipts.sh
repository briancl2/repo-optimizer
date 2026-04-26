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

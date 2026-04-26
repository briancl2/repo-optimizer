#!/usr/bin/env bash
# test-optimization-benchmark-harness.sh — Verify prompt/context benchmark classification.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$OPT_DIR/tests/fixtures/optimization-benchmarks/corpus.json"
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

json_field() {
    python3 - "$1" "$2" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

value = payload
for part in sys.argv[2].split("."):
    if isinstance(value, dict):
        value = value.get(part)
    elif isinstance(value, list):
        value = value[int(part)]
    else:
        value = None
        break

if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

echo "=== Optimization Benchmark Harness Test ==="

OUTPUT="$TEST_TMPDIR/output"
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$FIXTURE" \
    --output-dir "$OUTPUT" \
    --mode retained-replay

RESULTS="$OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json"

check_cmd "benchmark result artifact exists" test -s "$RESULTS"
check_cmd "benchmark readout artifact exists" test -s "$OUTPUT/OPTIMIZATION_BENCHMARK_READOUT.md"
check_cmd "optimizer-compatible plan artifact exists" test -s "$OUTPUT/OPTIMIZATION_PLAN.md"
check_cmd "optimizer-compatible scorecard artifact exists" test -s "$OUTPUT/OPTIMIZATION_SCORECARD.json"
check_cmd "corpus readiness is true for fixture buckets" test "$(json_field "$RESULTS" "corpus_readiness.ready")" = "true"
check_cmd "context pruning promotes on two of three paired fixtures" python3 - "$RESULTS" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
rollups = {row["tactic_id"]: row for row in payload["tactic_rollups"]}
assert rollups["context_pruning"]["disposition"] == "promoted", rollups["context_pruning"]
PY
check_cmd "cache proxy stays sandbox-only" python3 - "$RESULTS" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
rollups = {row["tactic_id"]: row for row in payload["tactic_rollups"]}
assert rollups["prompt_cache_stability"]["disposition"] == "not-measured", rollups["prompt_cache_stability"]
workloads = {row["workload_id"]: row for row in payload["workload_results"]}
assert workloads["fixture-cache-proxy-only"]["disposition"] == "sandbox-only", workloads["fixture-cache-proxy-only"]
PY
check_cmd "existing bundle validator accepts benchmark output" \
    bash "$OPT_DIR/.agents/skills/bundle-integrity/scripts/validate-bundle.sh" "$OUTPUT"

LIVE_FIXTURE="$TEST_TMPDIR/live-missing-variance-corpus.json"
python3 - "$FIXTURE" "$LIVE_FIXTURE" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    corpus = json.load(handle)
corpus["corpus_id"] = "repo-optimizer-live-missing-variance-fixture"
corpus["minimum_corpus"] = {
    "total_admitted": 1,
    "buckets": {
        "portfolio_advisor": 1
    },
}
corpus["workloads"] = [
    {
        "workload_id": "fixture-live-paired-missing-variance",
        "source_repo": "portfolio-advisor",
        "bucket": "portfolio_advisor",
        "tactic_id": "context_pruning",
        "workload_role": "roi_candidate",
        "live_tier": "tier3",
        "allowed_modes": ["live-paired"],
        "claim_types": ["token"],
        "target_repo_mutated": False,
        "baseline": {
            "input_tokens": 4000,
            "correctness_pass": True,
            "closeout_truth_pass": True,
        },
        "candidate": {
            "input_tokens": 3000,
            "run_count": 5,
            "correctness_pass": True,
            "closeout_truth_pass": True,
        },
        "evidence_refs": ["fixture://live/missing-variance"],
    }
]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(corpus, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
LIVE_OUTPUT="$TEST_TMPDIR/live-output"
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$LIVE_FIXTURE" \
    --output-dir "$LIVE_OUTPUT" \
    --mode live-paired
check_cmd "live-paired promotion requires variance telemetry" python3 - "$LIVE_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
workload = payload["workload_results"][0]
assert workload["disposition"] == "not-measured", workload
assert workload["variance_gate"] == {"evaluated": False, "passed": None}, workload
assert "lacks paired delta samples" in workload["reason"], workload
PY

NOT_READY_FIXTURE="$TEST_TMPDIR/not-ready-corpus.json"
python3 - "$FIXTURE" "$NOT_READY_FIXTURE" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    corpus = json.load(handle)
corpus["corpus_id"] = "repo-optimizer-not-ready-fixture"
corpus["minimum_corpus"] = {
    "total_admitted": 99,
    "buckets": {
        "bma": 99
    },
}
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(corpus, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
NOT_READY_OUTPUT="$TEST_TMPDIR/not-ready-output"
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$NOT_READY_FIXTURE" \
    --output-dir "$NOT_READY_OUTPUT" \
    --mode retained-replay
check_cmd "corpus readiness gates approved findings" python3 - "$NOT_READY_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" "$NOT_READY_OUTPUT/OPTIMIZATION_PLAN.md" "$NOT_READY_OUTPUT/OPTIMIZATION_SCORECARD.json" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    results = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    plan = handle.read()
with open(sys.argv[3], encoding="utf-8") as handle:
    scorecard = json.load(handle)
assert results["promotion_claims_allowed"] is False, results
assert "(APPROVED)" not in plan, plan
assert scorecard["findings_approved"] == 0, scorecard
assert scorecard["meta"]["blocked_promoted_count"] >= 1, scorecard
PY

MODE_FILTER_FIXTURE="$TEST_TMPDIR/mode-filter-corpus.json"
python3 - "$FIXTURE" "$MODE_FILTER_FIXTURE" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    corpus = json.load(handle)
corpus["corpus_id"] = "repo-optimizer-mode-filter-fixture"
for workload in corpus["workloads"]:
    if workload["workload_id"] == "fixture-git-history-context-pruning-fail":
        workload["allowed_modes"] = ["live-paired"]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(corpus, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
MODE_FILTER_OUTPUT="$TEST_TMPDIR/mode-filter-output"
python3 "$OPT_DIR/scripts/benchmark-optimization-workloads.py" \
    --corpus "$MODE_FILTER_FIXTURE" \
    --output-dir "$MODE_FILTER_OUTPUT" \
    --mode retained-replay
check_cmd "not-measured rows do not satisfy paired fixture minimum" python3 - "$MODE_FILTER_OUTPUT/OPTIMIZATION_BENCHMARK_RESULTS.json" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
rollups = {row["tactic_id"]: row for row in payload["tactic_rollups"]}
assert rollups["context_pruning"]["eligible_workload_count"] == 2, rollups["context_pruning"]
assert rollups["context_pruning"]["disposition"] == "not-measured", rollups["context_pruning"]
PY

if python3 -c "import jsonschema" 2>/dev/null; then
    check_cmd "corpus schema validates fixture" python3 - "$FIXTURE" "$OPT_DIR/schemas/OPTIMIZATION_BENCHMARK_CORPUS.schema.json" <<'PY'
from __future__ import annotations

import json
import sys

import jsonschema

with open(sys.argv[1], encoding="utf-8") as handle:
    artifact = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    schema = json.load(handle)
jsonschema.validate(artifact, schema)
PY
    check_cmd "results schema validates output" python3 - "$RESULTS" "$OPT_DIR/schemas/OPTIMIZATION_BENCHMARK_RESULTS.schema.json" <<'PY'
from __future__ import annotations

import json
import sys

import jsonschema

with open(sys.argv[1], encoding="utf-8") as handle:
    artifact = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    schema = json.load(handle)
jsonschema.validate(artifact, schema)
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

#!/usr/bin/env bash
# test-discovery-payload-capture.sh — Verify discovery payload handoff keeps
# the authoritative findings table when a later assistant summary follows it.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$OPT_DIR/tests/fixtures/discovery-payload-capture"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

echo "=== Discovery Payload Capture Test ==="

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

TARGET_REPO="$TEST_DIR/target-repo"
mkdir -p "$TARGET_REPO"
printf '# Target Repo\n' > "$TARGET_REPO/AGENTS.md"

AUDIT_DIR="$TEST_DIR/audit"
mkdir -p "$AUDIT_DIR"
python3 - "$AUDIT_DIR/SCORECARD.json" <<'PY'
from __future__ import annotations

import json
import sys

payload = {
    "composite": 50,
    "dimensions": {
        "D1_governance": {"score": 10, "max": 20},
        "D2_surface_health": {"score": 10, "max": 20},
        "D3_skill_maturity": {"score": 10, "max": 20},
        "D4_measurement": {"score": 10, "max": 20},
        "D5_self_improvement": {"score": 10, "max": 20},
    },
    "tier2_warnings": {"warnings": []},
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
PY

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/copilot" <<EOF
#!/usr/bin/env bash
set -euo pipefail

prompt=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -p)
            prompt="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

case "\$prompt" in
    *".agents/repo-optimizer-critic.agent.md"*)
        # Sleep 3s with PROGRESS_INTERVAL=1 so the orchestrator has room to emit a heartbeat.
        sleep 3
        cat "$FIXTURE_DIR/critic-success.jsonl"
        ;;
    *".agents/repo-optimizer-synthesis.agent.md"*)
        # Sleep 3s with PROGRESS_INTERVAL=1 so the orchestrator has room to emit a heartbeat.
        sleep 3
        cat "$FIXTURE_DIR/synthesis-success.jsonl"
        ;;
    *"-optimizer.agent.md"*)
        # Sleep 3s with PROGRESS_INTERVAL=1 so the orchestrator has room to emit a heartbeat.
        sleep 3
        cat "$FIXTURE_DIR/discovery-summary-after-tool.jsonl"
        ;;
    *)
        echo "unexpected prompt: \$prompt" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$FAKE_BIN/copilot"

OUTPUT_DIR="$TEST_DIR/output"
if PATH="$FAKE_BIN:$PATH" OPTIMIZER_TIMEOUT=5 OPTIMIZER_PROGRESS_INTERVAL=1 bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$AUDIT_DIR" "$OUTPUT_DIR" > "$TEST_DIR/run.log" 2>&1; then
    echo "  ✓ repo-optimizer.sh completed with fake copilot"
    PASS=$((PASS + 1))
else
    echo "  ✗ repo-optimizer.sh failed with fake copilot"
    cat "$TEST_DIR/run.log"
    FAIL=$((FAIL + 1))
fi

PAYLOAD_FILE="$OUTPUT_DIR/payloads/decomposition.md"
if [ -s "$PAYLOAD_FILE" ] \
    && grep -Fq '| Rank | Severity | Finding | File | Token Impact | Evidence Quote | Verification |' "$PAYLOAD_FILE" \
    && grep -Fq '| 1 | HIGH | Discovery payloads must preserve the findings table. |' "$PAYLOAD_FILE" \
    && ! grep -Fq 'Analysis complete.' "$PAYLOAD_FILE"; then
    echo "  ✓ discovery payload preserved the findings table instead of the summary"
    PASS=$((PASS + 1))
else
    echo "  ✗ discovery payload did not preserve the authoritative findings table"
    [ -f "$PAYLOAD_FILE" ] && cat "$PAYLOAD_FILE"
    FAIL=$((FAIL + 1))
fi

if [ -s "$PAYLOAD_FILE" ] && ! grep -Fq '<exited with exit code 0>' "$PAYLOAD_FILE"; then
    echo "  ✓ discovery payload trimmed terminal exit marker"
    PASS=$((PASS + 1))
else
    echo "  ✗ discovery payload kept terminal exit marker"
    FAIL=$((FAIL + 1))
fi

if grep -Fq '[decomposition] progress:' "$TEST_DIR/run.log" && grep -Fq '[critic] progress:' "$TEST_DIR/run.log"; then
    echo "  ✓ slow Copilot-backed phases emitted bounded progress output"
    PASS=$((PASS + 1))
else
    echo "  ✗ slow Copilot-backed phases did not emit expected progress output"
    cat "$TEST_DIR/run.log"
    FAIL=$((FAIL + 1))
fi

if [ -s "$OUTPUT_DIR/critic-verdicts.md" ] && grep -Fq '[VERDICT: APPROVED]' "$OUTPUT_DIR/critic-verdicts.md"; then
    echo "  ✓ downstream critic phase still materialized verdict markdown"
    PASS=$((PASS + 1))
else
    echo "  ✗ downstream critic phase did not materialize verdict markdown"
    FAIL=$((FAIL + 1))
fi

if [ -s "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" ] && grep -Fq '# Optimization Plan' "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"; then
    echo "  ✓ synthesis phase still materialized its plan artifact"
    PASS=$((PASS + 1))
else
    echo "  ✗ synthesis phase did not materialize its plan artifact"
    FAIL=$((FAIL + 1))
fi

CRITIC_RECEIPT="$OUTPUT_DIR/critic-phase-receipt.json"
SYNTH_RECEIPT="$OUTPUT_DIR/synthesis-phase-receipt.json"
RUNTIME_RECEIPT="$OUTPUT_DIR/RUNTIME_RECEIPTS.json"

if [ -s "$CRITIC_RECEIPT" ] \
    && [ "$(json_field "$CRITIC_RECEIPT" "proof_boundary.artifact_depth")" = "completed" ] \
    && [ "$(json_field "$CRITIC_RECEIPT" "proof_boundary.heartbeat_status")" = "observed" ] \
    && [ "$(json_field "$CRITIC_RECEIPT" "proof_boundary.phase_classification_evidence.phase_completed")" = "true" ] \
    && [ "$(json_field "$CRITIC_RECEIPT" "proof_boundary.phase_classification_evidence.artifact_exists")" = "true" ] \
    && [ -n "$(json_field "$CRITIC_RECEIPT" "proof_boundary.authority_fingerprint")" ]; then
    echo "  ✓ critic receipt carries proof-boundary metadata"
    PASS=$((PASS + 1))
else
    echo "  ✗ critic receipt missing proof-boundary metadata"
    [ -f "$CRITIC_RECEIPT" ] && cat "$CRITIC_RECEIPT"
    FAIL=$((FAIL + 1))
fi

if [ -s "$SYNTH_RECEIPT" ] \
    && [ "$(json_field "$SYNTH_RECEIPT" "proof_boundary.artifact_depth")" = "completed" ] \
    && [ "$(json_field "$SYNTH_RECEIPT" "proof_boundary.phase_classification_evidence.phase_completed")" = "true" ] \
    && [ "$(json_field "$SYNTH_RECEIPT" "proof_boundary.phase_classification_evidence.artifact_startable")" = "true" ]; then
    echo "  ✓ synthesis receipt preserves completion vs startability boundary"
    PASS=$((PASS + 1))
else
    echo "  ✗ synthesis receipt did not preserve completion vs startability boundary"
    [ -f "$SYNTH_RECEIPT" ] && cat "$SYNTH_RECEIPT"
    FAIL=$((FAIL + 1))
fi

# phases.critic and phases.synthesis each embed the full child phase receipt,
# so the proof_boundary path intentionally resolves through
# phases.*.proof_boundary rather than only the runtime summary.
if [ -s "$RUNTIME_RECEIPT" ] \
    && [ "$(json_field "$RUNTIME_RECEIPT" "proof_boundary.receipt_depth")" = "runtime" ] \
    && [ "$(json_field "$RUNTIME_RECEIPT" "proof_boundary.heartbeat_status")" = "observed" ] \
    && [ "$(json_field "$RUNTIME_RECEIPT" "phases.critic.proof_boundary.phase_classification_evidence.phase_completed")" = "true" ] \
    && [ "$(json_field "$RUNTIME_RECEIPT" "phases.synthesis.proof_boundary.phase_classification_evidence.phase_completed")" = "true" ]; then
    echo "  ✓ runtime receipt aggregates proof boundaries from both phases"
    PASS=$((PASS + 1))
else
    echo "  ✗ runtime receipt did not aggregate proof boundaries"
    [ -f "$RUNTIME_RECEIPT" ] && cat "$RUNTIME_RECEIPT"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

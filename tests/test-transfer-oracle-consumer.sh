#!/usr/bin/env bash
# test-transfer-oracle-consumer.sh — verify bounded advisory transfer evaluation.
# Requires a sibling repo-agent-core checkout for shared schema validation.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR_DEFAULT="$(cd "$OPT_DIR/.." && pwd)/repo-agent-core"
CORE_DIR="${REPO_AGENT_CORE:-$CORE_DIR_DEFAULT}"
if [ ! -d "$CORE_DIR" ]; then
    echo "ERROR: repo-agent-core not found. Set REPO_AGENT_CORE to the repo-agent-core checkout."
    exit 1
fi
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

write_decisions() {
    local path="$1"
    local decisions_json="$2"
    python3 - "$path" "$decisions_json" <<'PY'
from __future__ import annotations

import json
import sys

path = sys.argv[1]
decisions = json.loads(sys.argv[2])
payload = {
    "schema_version": "1.0.0",
    "generated_at": "2026-04-19T16:00:00Z",
    "producer": "repo-upgrade-advisor",
    "decision_contract": "bounded_advisory_decision_v1",
    "source_briefs": "fixture-briefs.json",
    "source_inputs": ["fixture-briefs.json", "fixture-responses.json"],
    "decisions": decisions,
    "non_claims": [
        "Fixture artifact for repo-optimizer transfer evaluation tests."
    ],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
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

echo "=== advisory transfer oracle consumer ==="

TOKEN_DECISIONS="$TEST_TMPDIR/token-decisions.json"
write_decisions "$TOKEN_DECISIONS" '[
  {
    "hotspot_id": "prompt_family:native_code_review",
    "verdict": "protect",
    "rationale": "Protect the measured spend until a cleaner owner-side split is proved.",
    "confidence": "medium",
    "brief_type": "root_cause_hypothesis_check",
    "user_facing_outcome": "agentic_root_cause_analysis_required",
    "decision_basis": "brief_constrained",
    "capability_family": "token_efficiency",
    "oracle_ref": "TE-03",
    "evidence_class": "oracle_backed",
    "transfer_status": "preserved",
    "bounded_non_claim": "Protect means preserve the bucket only; no optimizer mutation is admitted."
  },
  {
    "hotspot_id": "prompt_family:other",
    "verdict": "re-bucket",
    "rationale": "This looks like measurement cleanup rather than a downstream patch target.",
    "confidence": "low",
    "brief_type": "root_cause_hypothesis_check",
    "user_facing_outcome": "agentic_root_cause_analysis_required",
    "decision_basis": "brief_constrained",
    "capability_family": "token_efficiency",
    "oracle_ref": "TE-03",
    "evidence_class": "bounded_measurement",
    "transfer_status": "partial",
    "bounded_non_claim": "Re-bucket means attribution cleanup only; no optimizer-ready remediation is claimed."
  }
]'

TOKEN_OUTPUT="$TEST_TMPDIR/token-transfer-receipt.json"
python3 "$OPT_DIR/scripts/evaluate-advisory-transfer.py" \
    --decisions "$TOKEN_DECISIONS" \
    --capability-family token_efficiency \
    --output "$TOKEN_OUTPUT"

check_cmd "token-efficiency receipt validates against shared schema" \
    bash "$CORE_DIR/scripts/validate-artifacts.sh" "$TOKEN_OUTPUT" TRANSFER_ORACLE_RECEIPT
check_cmd "token-efficiency receipt stays partial" test "$(json_field "$TOKEN_OUTPUT" "transfer_state")" = "partial"
check_cmd "token-efficiency receipt stays fail-closed" test "$(json_field "$TOKEN_OUTPUT" "verdict")" = "fail"

CRITIQUE_DECISIONS="$TEST_TMPDIR/critique-decisions.json"
write_decisions "$CRITIQUE_DECISIONS" '[
  {
    "hotspot_id": "prompt_family:external_critique",
    "verdict": "insufficient_evidence",
    "rationale": "Helper-only critique evidence should not be upgraded into direct optimizer action.",
    "confidence": "low",
    "brief_type": "root_cause_hypothesis_check",
    "user_facing_outcome": "agentic_root_cause_analysis_required",
    "decision_basis": "brief_constrained",
    "capability_family": "external_critique",
    "oracle_ref": "EC-02",
    "evidence_class": "helper_only",
    "transfer_status": "helper_only",
    "bounded_non_claim": "Helper-only critique transfer stays bounded and cannot authorize optimizer mutation."
  }
]'

CRITIQUE_OUTPUT="$TEST_TMPDIR/critique-transfer-receipt.json"
python3 "$OPT_DIR/scripts/evaluate-advisory-transfer.py" \
    --decisions "$CRITIQUE_DECISIONS" \
    --capability-family external_critique \
    --output "$CRITIQUE_OUTPUT"

check_cmd "external-critique receipt validates against shared schema" \
    bash "$CORE_DIR/scripts/validate-artifacts.sh" "$CRITIQUE_OUTPUT" TRANSFER_ORACLE_RECEIPT
check_cmd "external-critique receipt stays blocked" test "$(json_field "$CRITIQUE_OUTPUT" "transfer_state")" = "blocked"
check_cmd "external-critique receipt notes helper-only boundary" grep -q "helper-only transfer" "$CRITIQUE_OUTPUT"

READY_DECISIONS="$TEST_TMPDIR/ready-decisions.json"
write_decisions "$READY_DECISIONS" '[
  {
    "hotspot_id": "prompt_family:optimizer_extraction",
    "verdict": "candidate_remediation",
    "rationale": "A bounded modernization candidate is ready for an optimizer-scoped follow-on.",
    "confidence": "medium",
    "brief_type": "root_cause_hypothesis_check",
    "user_facing_outcome": "agentic_root_cause_analysis_required",
    "decision_basis": "brief_constrained",
    "capability_family": "modernization",
    "oracle_ref": "AD-01",
    "evidence_class": "oracle_backed",
    "transfer_status": "preserved",
    "bounded_non_claim": "Ready means ready for an optimizer follow-on only; it is not a patch receipt."
  }
]'

READY_OUTPUT="$TEST_TMPDIR/ready-transfer-receipt.json"
python3 "$OPT_DIR/scripts/evaluate-advisory-transfer.py" \
    --decisions "$READY_DECISIONS" \
    --hotspot-id prompt_family:optimizer_extraction \
    --output "$READY_OUTPUT"

check_cmd "ready receipt validates against shared schema" \
    bash "$CORE_DIR/scripts/validate-artifacts.sh" "$READY_OUTPUT" TRANSFER_ORACLE_RECEIPT
check_cmd "candidate remediation receipt reaches ready state" test "$(json_field "$READY_OUTPUT" "transfer_state")" = "ready"
check_cmd "candidate remediation receipt passes" test "$(json_field "$READY_OUTPUT" "verdict")" = "pass"

echo ""
echo "=== test-transfer-oracle-consumer.sh: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] || exit 1

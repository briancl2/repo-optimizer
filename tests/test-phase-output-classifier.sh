#!/usr/bin/env bash
# test-phase-output-classifier.sh — Verify explicit artifact-contract receipt
# classes for Copilot JSONL phase output.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$OPT_DIR/tests/fixtures/phase-output-contract"
TMP_DIR="$OPT_DIR/tests/tmp-phase-output-classifier"
PASS=0
FAIL=0

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "=== Phase Output Classifier Test ==="

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

run_case() {
    local fixture_name="$1"
    local expected_status="$2"
    local expected_class="$3"
    local expect_artifact="$4"
    local case_name="$5"
    local phase="${6:-critic}"
    local heartbeat_count="${7:-0}"

    local raw_file="$FIXTURE_DIR/$fixture_name"
    local artifact_file="$TMP_DIR/$case_name.md"
    local receipt_file="$TMP_DIR/$case_name.json"

    python3 "$OPT_DIR/scripts/classify-phase-output.py" \
        --phase "$phase" \
        --raw "$raw_file" \
        --artifact "$artifact_file" \
        --copilot-exit-code 0 \
        --heartbeat-count "$heartbeat_count" > "$receipt_file"

    local actual_status
    actual_status=$(json_field "$receipt_file" "status")
    local actual_class
    actual_class=$(json_field "$receipt_file" "receipt_class")

    if [ "$actual_status" = "$expected_status" ]; then
        echo "  ✓ $case_name status = $expected_status"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $case_name status expected=$expected_status got=$actual_status"
        FAIL=$((FAIL + 1))
    fi

    if [ "$actual_class" = "$expected_class" ]; then
        echo "  ✓ $case_name receipt_class = $expected_class"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $case_name receipt_class expected=$expected_class got=$actual_class"
        FAIL=$((FAIL + 1))
    fi

    if [ "$expect_artifact" = "yes" ] && [ -s "$artifact_file" ]; then
        echo "  ✓ $case_name materialized markdown artifact"
        PASS=$((PASS + 1))
    elif [ "$expect_artifact" = "no" ] && [ ! -e "$artifact_file" ]; then
        echo "  ✓ $case_name left markdown artifact absent"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $case_name artifact expectation failed"
        FAIL=$((FAIL + 1))
    fi

    if [ "$case_name" = "success" ]; then
        local artifact_depth
        artifact_depth=$(json_field "$receipt_file" "proof_boundary.artifact_depth")
        local heartbeat_status
        heartbeat_status=$(json_field "$receipt_file" "proof_boundary.heartbeat_status")
        local receipt_depth
        receipt_depth=$(json_field "$receipt_file" "proof_boundary.receipt_depth")
        if [ "$artifact_depth" = "completed" ] && [ "$heartbeat_status" = "observed" ] && [ "$receipt_depth" = "phase" ]; then
            echo "  ✓ success proof boundary captures completed artifact with observed heartbeat"
            PASS=$((PASS + 1))
        else
            echo "  ✗ success proof boundary mismatch: depth=$artifact_depth heartbeat=$heartbeat_status receipt_depth=$receipt_depth"
            FAIL=$((FAIL + 1))
        fi
    fi

    if [ "$case_name" = "critic_tool_result_only" ]; then
        local artifact_exists
        artifact_exists=$(json_field "$receipt_file" "proof_boundary.phase_classification_evidence.artifact_exists")
        local artifact_startable
        artifact_startable=$(json_field "$receipt_file" "proof_boundary.phase_classification_evidence.artifact_startable")
        local phase_completed
        phase_completed=$(json_field "$receipt_file" "proof_boundary.phase_classification_evidence.phase_completed")
        if [ "$artifact_exists" = "false" ] && [ "$artifact_startable" = "false" ] && [ "$phase_completed" = "false" ]; then
            echo "  ✓ critic_tool_result_only keeps artifact existence separate from completion"
            PASS=$((PASS + 1))
        else
            echo "  ✗ critic_tool_result_only proof boundary leaked completion truth"
            FAIL=$((FAIL + 1))
        fi
    fi
}

run_case "success-terminal-message.jsonl" "completed" "terminal_markdown_captured" "yes" "success" "critic" "2"
run_case "v308-tool-result-empty-final.jsonl" "failed_artifact_contract" "missing_terminal_non_tool_message" "no" "critic_tool_result_only"
run_case "critic-tool-result-verdict-instructions.jsonl" "failed_artifact_contract" "missing_terminal_non_tool_message" "no" "critic_tool_result_verdict_text"
run_case "v308-tool-result-empty-final.jsonl" "completed" "terminal_tool_result_content_captured" "yes" "noncritic_tool_result" "discovery"
run_case "critic-delta-with-tool-dump.jsonl" "completed" "critic_delta_markdown_captured" "yes" "critic_delta" "critic" "1"
run_case "tool-only-nonterminal.jsonl" "failed_artifact_contract" "missing_terminal_non_tool_message" "no" "tool_only"
run_case "tool-result-nonterminal.jsonl" "failed_artifact_contract" "missing_terminal_non_tool_message" "no" "tool_result_nonterminal"
run_case "empty-terminal-message.jsonl" "failed_artifact_contract" "empty_terminal_non_tool_message" "no" "empty_terminal"

if [ -s "$TMP_DIR/success.md" ] && grep -q '\[VERDICT: APPROVED\]' "$TMP_DIR/success.md"; then
    echo "  ✓ success artifact preserved final markdown content"
    PASS=$((PASS + 1))
else
    echo "  ✗ success artifact missing expected verdict content"
    FAIL=$((FAIL + 1))
fi

if [ -s "$TMP_DIR/noncritic_tool_result.md" ] && grep -q '| Rank | Severity | Finding | File | Token Impact | Evidence Quote | Verification |' "$TMP_DIR/noncritic_tool_result.md"; then
    echo "  ✓ noncritic_tool_result preserved terminal tool-result markdown"
    PASS=$((PASS + 1))
else
    echo "  ✗ noncritic_tool_result artifact missing expected findings table"
    FAIL=$((FAIL + 1))
fi

if [ -s "$TMP_DIR/critic_delta.md" ] \
    && grep -Fq '# Adversarial Critic — Verdict Report' "$TMP_DIR/critic_delta.md" \
    && grep -Fq '[VERDICT: APPROVED]' "$TMP_DIR/critic_delta.md" \
    && ! grep -Fq 'payloads/standardization.md.jsonl' "$TMP_DIR/critic_delta.md"; then
    echo "  ✓ critic_delta artifact preferred reconstructed verdict markdown"
    PASS=$((PASS + 1))
else
    echo "  ✗ critic_delta artifact did not preserve authoritative verdict markdown"
    FAIL=$((FAIL + 1))
fi

rm -rf "$TMP_DIR"

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

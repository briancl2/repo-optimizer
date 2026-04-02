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

run_case() {
    local fixture_name="$1"
    local expected_status="$2"
    local expected_class="$3"
    local expect_artifact="$4"
    local case_name="$5"

    local raw_file="$FIXTURE_DIR/$fixture_name"
    local artifact_file="$TMP_DIR/$case_name.md"
    local receipt_file="$TMP_DIR/$case_name.json"

    python3 "$OPT_DIR/scripts/classify-phase-output.py" \
        --phase critic \
        --raw "$raw_file" \
        --artifact "$artifact_file" \
        --copilot-exit-code 0 > "$receipt_file"

    local actual_status
    actual_status=$(python3 -c "import json; print(json.load(open('$receipt_file'))['status'])")
    local actual_class
    actual_class=$(python3 -c "import json; print(json.load(open('$receipt_file'))['receipt_class'])")

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
}

run_case "success-terminal-message.jsonl" "completed" "terminal_markdown_captured" "yes" "success"
run_case "v308-tool-result-empty-final.jsonl" "completed" "terminal_tool_result_content_captured" "yes" "v308_tool_result"
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

if [ -s "$TMP_DIR/v308_tool_result.md" ] && grep -q '| Rank | Severity | Finding | File | Token Impact | Evidence Quote | Verification |' "$TMP_DIR/v308_tool_result.md"; then
    echo "  ✓ v308_tool_result artifact preserved terminal tool-result markdown"
    PASS=$((PASS + 1))
else
    echo "  ✗ v308_tool_result artifact missing expected findings table"
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

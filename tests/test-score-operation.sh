#!/usr/bin/env bash
# tests/test-score-operation.sh — Validate score-operation.sh content quality gates
#
# Tests that:
#   1. Stub OPTIMIZATION_PLAN (<50 lines, 0 approved, 0 file refs) scores WARN or FAIL
#   2. Good OPTIMIZATION_PLAN (>=50 lines, approved findings, file refs) scores PASS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCORER="$SCRIPT_DIR/scripts/score-operation.sh"

PASS=0
FAIL=0

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $label (expected=$expected, got=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Test: score-operation.sh content quality gates ==="

# Test 1: Stub fixture should NOT score PASS
echo ""
echo "--- Test 1: Stub OPTIMIZATION_PLAN ---"
STUB_OUT=$(bash "$SCORER" "$SCRIPT_DIR/tests/fixtures/stub-operation" --json 2>/dev/null)
STUB_VERDICT=$(echo "$STUB_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
STUB_SCORE=$(echo "$STUB_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['score'])")
check "Stub verdict != PASS" "true" "$([ "$STUB_VERDICT" != "PASS" ] && echo true || echo false)"
echo "  (stub scored $STUB_SCORE, verdict=$STUB_VERDICT)"
STUB_ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/repo-optimizer-scoreop-stderr.XXXXXX")"
bash "$SCORER" "$SCRIPT_DIR/tests/fixtures/stub-operation" --json >/dev/null 2>"$STUB_ERR_FILE"
check "Stub scoring has no integer-expression stderr" "false" "$(grep -qi 'integer expression expected' "$STUB_ERR_FILE" && echo true || echo false)"
rm -f "$STUB_ERR_FILE"

# Test 2: Good fixture should score PASS
echo ""
echo "--- Test 2: Good OPTIMIZATION_PLAN ---"
GOOD_OUT=$(bash "$SCORER" "$SCRIPT_DIR/tests/fixtures/good-operation" --json 2>/dev/null)
GOOD_VERDICT=$(echo "$GOOD_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
GOOD_SCORE=$(echo "$GOOD_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['score'])")
GOOD_CRITIC_SCANNED=$(echo "$GOOD_OUT" | python3 -c "import json,sys; rows=json.load(sys.stdin)['command_output_roi_receipt']['governed_artifacts']; print(next(row['scanned'] for row in rows if row['path'] == 'critic-verdicts.md'))")
check "Good verdict = PASS" "PASS" "$GOOD_VERDICT"
check "Good fixture reports missing critic output as not scanned" "False" "$GOOD_CRITIC_SCANNED"
echo "  (good scored $GOOD_SCORE, verdict=$GOOD_VERDICT)"

EMPTY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/repo-optimizer-empty.XXXXXX")"
EMPTY_OUT=$(bash "$SCORER" "$EMPTY_DIR" --json 2>/dev/null)
EMPTY_RECEIPT_VERDICT=$(echo "$EMPTY_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['command_output_roi_receipt']['verdict'])")
rm -rf "$EMPTY_DIR"
check "Empty fixture command-output ROI receipt is not measured" "not-measured" "$EMPTY_RECEIPT_VERDICT"

# Test 3: Stub should have issues about approved findings and file refs
echo ""
echo "--- Test 3: Stub issues contain expected signals ---"
STUB_ISSUES=$(echo "$STUB_OUT" | python3 -c "import json,sys; issues=json.load(sys.stdin)['issues']; print(' '.join(issues))")
check "Stub flags approved findings" "true" "$(echo "$STUB_ISSUES" | grep -qi 'approved' && echo true || echo false)"
check "Stub flags target files or sparse" "true" "$(echo "$STUB_ISSUES" | grep -qiE '(target file|sparse|trivial)' && echo true || echo false)"

echo ""
echo "--- Test 4: Raw command transcript in plan fails ---"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/repo-optimizer-scoreop.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
PLAN_DUMP="$TMP_ROOT/plan-dump"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$PLAN_DUMP"
{
    cat "$SCRIPT_DIR/tests/fixtures/good-operation/OPTIMIZATION_PLAN.md"
    printf '%s\n' '' '```text'
    for i in $(seq 1 40); do
        printf 'PASS: make check raw optimizer transcript line %s\n' "$i"
    done
    printf '%s\n' '```'
} > "$PLAN_DUMP/OPTIMIZATION_PLAN.md"
PLAN_DUMP_OUT=$(bash "$SCORER" "$PLAN_DUMP" --json 2>/dev/null)
PLAN_DUMP_VERDICT=$(echo "$PLAN_DUMP_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
check "Plan dump verdict = FAIL" "FAIL" "$PLAN_DUMP_VERDICT"
check "Plan dump flags command-output ROI" "true" "$(echo "$PLAN_DUMP_OUT" | grep -qi 'Command-output ROI violation' && echo true || echo false)"

echo ""
echo "--- Test 5: Plaintext raw command transcript fails ---"
PLAINTEXT_DUMP="$TMP_ROOT/plaintext-dump"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$PLAINTEXT_DUMP"
{
    cat "$SCRIPT_DIR/tests/fixtures/good-operation/OPTIMIZATION_PLAN.md"
    printf '%s\n' ''
    for i in $(seq 1 30); do
        printf 'FAIL: optimizer raw transcript line %s\n' "$i"
    done
} > "$PLAINTEXT_DUMP/OPTIMIZATION_PLAN.md"
PLAINTEXT_OUT=$(bash "$SCORER" "$PLAINTEXT_DUMP" --json 2>/dev/null)
PLAINTEXT_VERDICT=$(echo "$PLAINTEXT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
check "Plaintext dump verdict = FAIL" "FAIL" "$PLAINTEXT_VERDICT"

echo ""
echo "--- Test 6: Critic raw command transcript fails ---"
CRITIC_DUMP="$TMP_ROOT/critic-dump"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$CRITIC_DUMP"
{
    printf '%s\n' '# Critic Verdicts' ''
    for i in $(seq 1 30); do
        printf 'PASS: critic raw transcript line %s\n' "$i"
    done
} > "$CRITIC_DUMP/critic-verdicts.md"
CRITIC_DUMP_OUT=$(bash "$SCORER" "$CRITIC_DUMP" --json 2>/dev/null)
CRITIC_DUMP_VERDICT=$(echo "$CRITIC_DUMP_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
check "Critic dump verdict = FAIL" "FAIL" "$CRITIC_DUMP_VERDICT"

echo ""
echo "--- Test 7: JSON raw command transcript fails ---"
JSON_DUMP="$TMP_ROOT/json-dump"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$JSON_DUMP"
JSON_DUMP="$JSON_DUMP" python3 - <<'PY'
import json
import os
import pathlib

path = pathlib.Path(os.environ["JSON_DUMP"]) / "OPTIMIZATION_SCORECARD.json"
payload = json.loads(path.read_text(encoding="utf-8"))
payload["raw_notes"] = "\n".join(f"PASS: optimizer raw JSON transcript {idx}" for idx in range(30))
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
JSON_DUMP_OUT=$(bash "$SCORER" "$JSON_DUMP" --json 2>/dev/null)
JSON_DUMP_VERDICT=$(echo "$JSON_DUMP_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
check "JSON dump verdict = FAIL" "FAIL" "$JSON_DUMP_VERDICT"

echo ""
echo "--- Test 8: Separate JSON command summaries do not combine into false run ---"
JSON_SEPARATE="$TMP_ROOT/json-separate"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$JSON_SEPARATE"
JSON_SEPARATE="$JSON_SEPARATE" python3 - <<'PY'
import json
import os
import pathlib

path = pathlib.Path(os.environ["JSON_SEPARATE"]) / "OPTIMIZATION_SCORECARD.json"
payload = json.loads(path.read_text(encoding="utf-8"))
payload["summary_a"] = "\n".join(f"PASS: separate optimizer summary A {idx}" for idx in range(6))
payload["summary_b"] = "\n".join(f"PASS: separate optimizer summary B {idx}" for idx in range(6))
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
JSON_SEPARATE_OUT=$(bash "$SCORER" "$JSON_SEPARATE" --json 2>/dev/null)
JSON_SEPARATE_VERDICT=$(echo "$JSON_SEPARATE_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
check "Separate JSON summaries verdict = PASS" "PASS" "$JSON_SEPARATE_VERDICT"

echo ""
echo "--- Test 9: Raw receipt/log artifacts allowed ---"
RECEIPT_LOG="$TMP_ROOT/receipt-log"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$RECEIPT_LOG"
{
    printf '%s\n' '# Raw Optimizer Receipt' '```text'
    for i in $(seq 1 70); do
        printf 'PASS: retained optimizer raw receipt line %s\n' "$i"
    done
    printf '%s\n' '```'
} > "$RECEIPT_LOG/optimizer-stdout.txt"
RECEIPT_LOG_OUT=$(bash "$SCORER" "$RECEIPT_LOG" --json 2>/dev/null)
RECEIPT_LOG_VERDICT=$(echo "$RECEIPT_LOG_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
RECEIPT_LOG_RECEIPT=$(echo "$RECEIPT_LOG_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['command_output_roi_receipt']['verdict'])")
check "Raw receipt/log fixture verdict = PASS" "PASS" "$RECEIPT_LOG_VERDICT"
check "Raw receipt/log fixture emits passing ROI receipt" "pass" "$RECEIPT_LOG_RECEIPT"

echo ""
echo "--- Test 10: Numbered approved headings and domain timeout text stay valid ---"
NUMBERED_APPROVED="$TMP_ROOT/numbered-approved"
cp -R "$SCRIPT_DIR/tests/fixtures/good-operation" "$NUMBERED_APPROVED"
python3 - "$NUMBERED_APPROVED/OPTIMIZATION_PLAN.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("## Approved Findings", "## 2. Approved Findings")
text = text.replace(" (APPROVED)", "")
text += "\n\nThis target contains timeout/retry orchestration and error handling recommendations as domain content, not runtime failure evidence.\n"
path.write_text(text, encoding="utf-8")
PY
NUMBERED_APPROVED_OUT=$(bash "$SCORER" "$NUMBERED_APPROVED" --json 2>/dev/null)
NUMBERED_APPROVED_VERDICT=$(echo "$NUMBERED_APPROVED_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
NUMBERED_APPROVED_ISSUES=$(echo "$NUMBERED_APPROVED_OUT" | python3 -c "import json,sys; print('\\n'.join(json.load(sys.stdin)['issues']))")
check "Numbered approved heading verdict = PASS" "PASS" "$NUMBERED_APPROVED_VERDICT"
check "Domain timeout text is not runtime timeout" "false" "$(echo "$NUMBERED_APPROVED_ISSUES" | grep -qi 'Timeout or error detected' && echo true || echo false)"
check "Numbered approved heading counts approved findings" "false" "$(echo "$NUMBERED_APPROVED_ISSUES" | grep -qi '0 approved findings' && echo true || echo false)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

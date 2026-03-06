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

# Test 2: Good fixture should score PASS
echo ""
echo "--- Test 2: Good OPTIMIZATION_PLAN ---"
GOOD_OUT=$(bash "$SCORER" "$SCRIPT_DIR/tests/fixtures/good-operation" --json 2>/dev/null)
GOOD_VERDICT=$(echo "$GOOD_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['verdict'])")
GOOD_SCORE=$(echo "$GOOD_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['score'])")
check "Good verdict = PASS" "PASS" "$GOOD_VERDICT"
echo "  (good scored $GOOD_SCORE, verdict=$GOOD_VERDICT)"

# Test 3: Stub should have issues about approved findings and file refs
echo ""
echo "--- Test 3: Stub issues contain expected signals ---"
STUB_ISSUES=$(echo "$STUB_OUT" | python3 -c "import json,sys; issues=json.load(sys.stdin)['issues']; print(' '.join(issues))")
check "Stub flags approved findings" "true" "$(echo "$STUB_ISSUES" | grep -qi 'approved' && echo true || echo false)"
check "Stub flags target files or sparse" "true" "$(echo "$STUB_ISSUES" | grep -qiE '(target file|sparse|trivial)' && echo true || echo false)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

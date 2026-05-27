#!/usr/bin/env bash
# tests/test-work-close-github-native.sh — GitHub-native work-close bypass tests
#
# Verifies that issue/PR-backed work can bypass session-local score authority
# only when explicitly requested, while ordinary work still runs score-session.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

make_fixture() {
    local work_dir="$1"
    mkdir -p "$work_dir/pre-audit"
    echo "PASS" > "$work_dir/pre-audit/test-result.txt"
    grep -cE '^\| L[0-9]+' LEARNINGS.md > "$work_dir/.learnings_baseline_count" 2>/dev/null || echo "0" > "$work_dir/.learnings_baseline_count"
    cat > "$work_dir/WORK.md" <<'EOF'
# Work Contract

## Description

GitHub-native closeout fixture

## Hypothesis

**Prediction:** This fixture can close through the selected work-close mode.
**PASS:** The expected closeout artifact is written.
**FAIL:** The wrong closeout artifact is written.

## Work Type

code-change

## Status

- [x] Hypothesis stated
- [x] Work completed
- [x] Learnings extracted (or --no-novel-findings)
- [ ] work-close run
EOF
}

FAKEBIN="$TMPDIR/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/make" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "test" ]; then
    echo "fake make test PASS"
    exit 0
fi
exec /usr/bin/make "$@"
EOF
chmod +x "$FAKEBIN/make"

echo "=== GitHub-native work-close tests ==="

echo ""
echo "=== Fixture 1: explicit GitHub-native bypass ==="
WORK1="$TMPDIR/work-github-native"
make_fixture "$WORK1"
PATH="$FAKEBIN:$PATH" WORK_CLOSE_OPS_LEDGER="$TMPDIR/ops.jsonl" \
    bash scripts/work-close.sh "$WORK1" \
    --no-novel-findings "No reusable repo-optimizer learning beyond the closure-authority change under test." \
    --github-native-closeout "GitHub issue and PR state are closure authority for this Issue 164 campaign slice."

check "bypass receipt exists" "true" "$([ -f "$WORK1/score-session-bypass.json" ] && echo true || echo false)"
check "scorecard omitted in bypass mode" "false" "$([ -f "$WORK1/OPERATING_MODEL_SCORECARD.json" ] && echo true || echo false)"
mode=$(python3 -c "import json; print(json.load(open('$WORK1/score-session-bypass.json'))['mode'])")
status=$(python3 -c "import json; print(json.load(open('$WORK1/score-session-bypass.json'))['status'])")
ops_mode=$(python3 -c "import json; print(json.load(open('$TMPDIR/ops.jsonl'))['data']['score_session_mode'])")
check "receipt mode" "github_native_issue_pr" "$mode"
check "receipt status" "score_session_not_authoritative" "$status"
check "ops ledger records bypass" "github_native_bypass" "$ops_mode"

echo ""
echo "=== Fixture 2: too-short bypass rationale fails closed ==="
WORK2="$TMPDIR/work-short-rationale"
make_fixture "$WORK2"
set +e
PATH="$FAKEBIN:$PATH" WORK_CLOSE_OPS_LEDGER="$TMPDIR/ops-short.jsonl" \
    bash scripts/work-close.sh "$WORK2" --github-native-closeout "short" > "$TMPDIR/short.out" 2>&1
short_status=$?
set -e
check "short rationale rejected" "true" "$([ "$short_status" -ne 0 ] && echo true || echo false)"
check "short rationale writes no bypass receipt" "false" "$([ -f "$WORK2/score-session-bypass.json" ] && echo true || echo false)"

echo ""
echo "=== Fixture 3: default closeout still runs score-session ==="
WORK3="$TMPDIR/work-default"
make_fixture "$WORK3"
PATH="$FAKEBIN:$PATH" WORK_CLOSE_OPS_LEDGER="$TMPDIR/ops-default.jsonl" \
    bash scripts/work-close.sh "$WORK3" \
    --no-novel-findings "No reusable repo-optimizer learning beyond proving the default score-session path stays active."

check "default scorecard exists" "true" "$([ -f "$WORK3/OPERATING_MODEL_SCORECARD.json" ] && echo true || echo false)"
check "default bypass receipt omitted" "false" "$([ -f "$WORK3/score-session-bypass.json" ] && echo true || echo false)"
default_mode=$(python3 -c "import json; print(json.load(open('$TMPDIR/ops-default.jsonl'))['data']['score_session_mode'])")
check "ops ledger records default scorer" "session_grader" "$default_mode"

echo ""
echo "=== GitHub-native Work-Close Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "  VERDICT: PASS"
    exit 0
else
    echo "  VERDICT: FAIL"
    exit 1
fi

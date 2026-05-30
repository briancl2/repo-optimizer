#!/usr/bin/env bash
# tests/test-validate-target-ux.sh - Validate make validate guidance.

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

run_expect_status() {
    local desc="$1"
    local expected_status="$2"
    local output_file="$3"
    shift 3
    set +e
    "$@" > "$output_file" 2>&1
    local actual_status=$?
    set -e
    check "$desc status" "$expected_status" "$actual_status"
}

echo "=== Validate target UX tests ==="

missing_output="$TMPDIR/missing-output.log"
run_expect_status "missing bundle dir" "2" "$missing_output" \
    make validate OUTPUT_DIR="$TMPDIR/no-such-bundle"
check "missing dir explains bundle contract" "true" \
    "$(grep -Fq 'validates a generated optimizer output bundle' "$missing_output" && echo true || echo false)"
check "missing dir names source-only gate" "true" \
    "$(grep -Fq 'For source-only or workflow-only repo changes, run: make check && make test' "$missing_output" && echo true || echo false)"

incomplete_dir="$TMPDIR/incomplete-bundle"
mkdir -p "$incomplete_dir"
printf '# Plan\n' > "$incomplete_dir/OPTIMIZATION_PLAN.md"
incomplete_output="$TMPDIR/incomplete-output.log"
run_expect_status "incomplete bundle dir" "2" "$incomplete_output" \
    make validate OUTPUT_DIR="$incomplete_dir"
check "incomplete dir names missing scorecard" "true" \
    "$(grep -Fq 'OPTIMIZATION_SCORECARD.json' "$incomplete_output" && echo true || echo false)"
check "incomplete dir names bundle generation path" "true" \
    "$(grep -Fq 'For bundle validation, first run make optimize or pass OUTPUT_DIR=<existing-bundle-dir>.' "$incomplete_output" && echo true || echo false)"

valid_output="$TMPDIR/valid-output.log"
run_expect_status "complete bundle fixture" "0" "$valid_output" \
    make validate OUTPUT_DIR="$REPO_ROOT/tests/fixtures/good-operation"
check "complete bundle still reaches bundle validator" "true" \
    "$(grep -Fq 'VERDICT: PASS' "$valid_output" && echo true || echo false)"

help_output="$TMPDIR/help-output.log"
make help > "$help_output"
check "Makefile help clarifies validate target" "true" \
    "$(grep -Fq 'make validate OUTPUT_DIR=<dir>' "$help_output" && echo true || echo false)"
check "AGENTS command list clarifies validate target" "true" \
    "$(grep -Fq 'make validate OUTPUT_DIR=<dir>' AGENTS.md && echo true || echo false)"
check "AGENTS names source-only gate" "true" \
    "$(grep -Fq 'source-only or workflow-only repo changes' AGENTS.md && echo true || echo false)"

echo ""
echo "=== Validate target UX Test Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "  VERDICT: PASS"
    exit 0
else
    echo "  VERDICT: FAIL"
    exit 1
fi

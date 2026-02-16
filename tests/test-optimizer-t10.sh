#!/usr/bin/env bash
# test-optimizer-t10.sh — Functional test: run optimizer pre-flight on T10.
#
# Usage: bash tests/test-optimizer-t10.sh [audit_dir]
#   audit_dir: Directory containing SCORECARD.json (from repo-auditor run on T10)

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$HOME/repos/build-meta-analysis/targets/T10-transcript-processor"
AUDIT_DIR="${1:-}"
OUTPUT_DIR="$OPT_DIR/tests/test-output-t10"

echo "=== Optimizer Functional Test: T10 ==="

# If no audit dir provided, try to run auditor first
if [ -z "$AUDIT_DIR" ]; then
    # Check if repo-auditor is available
    if [ -x "$HOME/repos/repo-auditor/scripts/repo-auditor.sh" ]; then
        AUDIT_DIR="$OPT_DIR/tests/test-audit-t10"
        echo "  Running repo-auditor on T10 first..."
        mkdir -p "$AUDIT_DIR"
        bash "$HOME/repos/repo-auditor/scripts/repo-auditor.sh" "$TARGET" "$AUDIT_DIR" 2>/dev/null || true
    else
        echo "SKIP: No audit_dir provided and repo-auditor not available"
        echo "  Run: bash tests/test-optimizer-t10.sh <path-to-audit-output>"
        exit 0
    fi
fi

if [ ! -f "$AUDIT_DIR/SCORECARD.json" ]; then
    echo "SKIP: SCORECARD.json not found in $AUDIT_DIR"
    exit 0
fi

# Clean previous test output
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "  Target: $TARGET"
echo "  Audit:  $AUDIT_DIR"
echo "  Output: $OUTPUT_DIR"

# Run optimizer pre-flight
echo ""
echo "--- Running optimizer pre-flight ---"
bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET" "$AUDIT_DIR" "$OUTPUT_DIR" 2>&1

# Verify outputs
echo ""
echo "--- Verifying outputs ---"
PASS=0
FAIL=0

# Check OPTIMIZATION_PLAN.md
if [ -s "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" ]; then
    echo "  ✓ OPTIMIZATION_PLAN.md ($(wc -l < "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" | tr -d ' ')L)"
    PASS=$((PASS + 1))
else
    echo "  ✗ OPTIMIZATION_PLAN.md — missing or empty"
    FAIL=$((FAIL + 1))
fi

# Check OPTIMIZATION_SCORECARD.json
if [ -s "$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json" ]; then
    if python3 -c "import json; json.load(open('$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json'))" 2>/dev/null; then
        echo "  ✓ OPTIMIZATION_SCORECARD.json — valid JSON"
        PASS=$((PASS + 1))
    else
        echo "  ✗ OPTIMIZATION_SCORECARD.json — invalid JSON"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ✗ OPTIMIZATION_SCORECARD.json — missing or empty"
    FAIL=$((FAIL + 1))
fi

# Check pre-flight.json
if [ -s "$OUTPUT_DIR/pre-flight.json" ]; then
    echo "  ✓ pre-flight.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ pre-flight.json — missing"
    FAIL=$((FAIL + 1))
fi

# Clean up
rm -rf "$OUTPUT_DIR"
rm -rf "$OPT_DIR/tests/test-audit-t10" 2>/dev/null || true

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

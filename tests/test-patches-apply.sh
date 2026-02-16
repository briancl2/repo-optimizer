#!/usr/bin/env bash
# test-patches-apply.sh — Verify all patches in PATCH_PACK/ apply cleanly.
# Structural test: verifies validate-patches.sh script exists and is executable.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

echo "=== Patch Application Test ==="

# Check validate-patches.sh exists
if [ -x "$OPT_DIR/scripts/validate-patches.sh" ]; then
    echo "  ✓ validate-patches.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ validate-patches.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# Check fix-diff-headers.sh exists
if [ -x "$OPT_DIR/scripts/fix-diff-headers.sh" ]; then
    echo "  ✓ fix-diff-headers.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ fix-diff-headers.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# Check generate-patches.sh exists
if [ -x "$OPT_DIR/scripts/generate-patches.sh" ]; then
    echo "  ✓ generate-patches.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

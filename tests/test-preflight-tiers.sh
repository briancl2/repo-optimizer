#!/usr/bin/env bash
# test-preflight-tiers.sh — Regression test for pre-flight budget tier find commands.
#
# Validates that all 3 budget tiers (full, focused, minimal) complete without
# errors. Regression for L270: "find: (): empty inner expression" bug in
# minimal tier caused by missing line-continuation backslash.
#
# Creates a synthetic repo structure to test each tier boundary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0
TOTAL=0

check() {
    TOTAL=$((TOTAL + 1))
    if "$@" >"$TEST_DIR/check.out" 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS ($TOTAL): $1 ${2:-}"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL ($TOTAL): $1 ${2:-}"
        echo "  --- stderr ---"
        cat "$TEST_DIR/check.out"
        echo "  --- end ---"
    fi
}

echo "=== Pre-flight Budget Tier Tests ==="

# Create synthetic SCORECARD.json
AUDIT_DIR="$TEST_DIR/audit"
mkdir -p "$AUDIT_DIR"
python3 -c "
import json
data = {
    'composite': 50,
    'dimensions': {
        'D1_governance': {'score': 10, 'max': 20},
        'D2_surface_health': {'score': 5, 'max': 20},
        'D3_velocity': {'score': 10, 'max': 20},
        'D4_organicity': {'score': 15, 'max': 20},
        'D5_trajectory': {'score': 10, 'max': 20}
    },
    'tier2_warnings': {'warnings': []}
}
with open('$AUDIT_DIR/SCORECARD.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# --- Test 1: Full tier (<200 files) ---
echo ""
echo "--- Tier: full (<200 files) ---"
REPO_FULL="$TEST_DIR/repo-full"
mkdir -p "$REPO_FULL"
# Create 50 files (well under 200)
for i in $(seq 1 50); do
    echo "content $i" > "$REPO_FULL/file-$i.txt"
done
mkdir -p "$REPO_FULL/.agents"
echo "agent" > "$REPO_FULL/AGENTS.md"
echo "readme" > "$REPO_FULL/README.md"

OUTPUT_FULL="$TEST_DIR/out-full"
check bash "$OPT_DIR/scripts/repo-optimizer.sh" "$REPO_FULL" "$AUDIT_DIR" "$OUTPUT_FULL"
TOTAL=$((TOTAL + 1))
if [ -f "$OUTPUT_FULL/pre-flight.json" ]; then
    TIER=$(python3 -c "import json; print(json.load(open('$OUTPUT_FULL/pre-flight.json'))['budget_tier'])")
    if [ "$TIER" = "full" ]; then
        PASS=$((PASS + 1))
        echo "  PASS ($TOTAL): budget_tier = full"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL ($TOTAL): expected full, got $TIER"
    fi
else
    FAIL=$((FAIL + 1))
    echo "  FAIL ($TOTAL): pre-flight.json not created"
fi

# --- Test 2: Focused tier (200-1000 files) ---
echo ""
echo "--- Tier: focused (200-1000 files) ---"
REPO_FOCUSED="$TEST_DIR/repo-focused"
mkdir -p "$REPO_FOCUSED"
# Create 500 files
for i in $(seq 1 500); do
    echo "content $i" > "$REPO_FOCUSED/file-$i.txt"
done
echo "agent" > "$REPO_FOCUSED/AGENTS.md"

OUTPUT_FOCUSED="$TEST_DIR/out-focused"
check bash "$OPT_DIR/scripts/repo-optimizer.sh" "$REPO_FOCUSED" "$AUDIT_DIR" "$OUTPUT_FOCUSED"
TOTAL=$((TOTAL + 1))
if [ -f "$OUTPUT_FOCUSED/pre-flight.json" ]; then
    TIER=$(python3 -c "import json; print(json.load(open('$OUTPUT_FOCUSED/pre-flight.json'))['budget_tier'])")
    if [ "$TIER" = "focused" ]; then
        PASS=$((PASS + 1))
        echo "  PASS ($TOTAL): budget_tier = focused"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL ($TOTAL): expected focused, got $TIER"
    fi
else
    FAIL=$((FAIL + 1))
    echo "  FAIL ($TOTAL): pre-flight.json not created"
fi

# --- Test 3: Minimal tier (>1000 files) — L270 regression ---
echo ""
echo "--- Tier: minimal (>1000 files) — L270 regression ---"
REPO_MINIMAL="$TEST_DIR/repo-minimal"
mkdir -p "$REPO_MINIMAL"
# Create 1100 files (just over 1000 threshold)
for i in $(seq 1 1100); do
    echo "content $i" > "$REPO_MINIMAL/file-$i.txt"
done
echo "agent" > "$REPO_MINIMAL/AGENTS.md"
echo "makefile" > "$REPO_MINIMAL/Makefile"

OUTPUT_MINIMAL="$TEST_DIR/out-minimal"
check bash "$OPT_DIR/scripts/repo-optimizer.sh" "$REPO_MINIMAL" "$AUDIT_DIR" "$OUTPUT_MINIMAL"
TOTAL=$((TOTAL + 1))
if [ -f "$OUTPUT_MINIMAL/pre-flight.json" ]; then
    TIER=$(python3 -c "import json; print(json.load(open('$OUTPUT_MINIMAL/pre-flight.json'))['budget_tier'])")
    if [ "$TIER" = "minimal" ]; then
        PASS=$((PASS + 1))
        echo "  PASS ($TOTAL): budget_tier = minimal"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL ($TOTAL): expected minimal, got $TIER"
    fi
else
    FAIL=$((FAIL + 1))
    echo "  FAIL ($TOTAL): pre-flight.json not created"
fi

# --- Test 4: Minimal tier produces non-zero eligible files ---
echo ""
echo "--- Minimal tier: eligible files > 0 ---"
TOTAL=$((TOTAL + 1))
if [ -f "$OUTPUT_MINIMAL/pre-flight.json" ]; then
    ELIGIBLE=$(python3 -c "import json; print(json.load(open('$OUTPUT_MINIMAL/pre-flight.json'))['discovery_scope']['eligible_files'])")
    if [ "$ELIGIBLE" -gt 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS ($TOTAL): minimal tier eligible_files = $ELIGIBLE (>0)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL ($TOTAL): minimal tier eligible_files = 0"
    fi
else
    FAIL=$((FAIL + 1))
    echo "  FAIL ($TOTAL): pre-flight.json not created"
fi

# Summary
echo ""
echo "=== Pre-flight Tier Tests: $PASS/$TOTAL passed ==="
if [ "$FAIL" -gt 0 ]; then
    echo "  FAILED: $FAIL tests"
    exit 1
fi

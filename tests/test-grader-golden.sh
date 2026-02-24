#!/usr/bin/env bash
# tests/test-grader-golden.sh — Golden fixture test for score-session.sh
#
# Tests the session grader against known inputs to verify scoring correctness.
# Includes positive fixture (well-formed work dir) and 2 negative fixtures
# (per spec 054 SC6 / critique C1 finding).
#
# Usage: bash tests/test-grader-golden.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Helper ────────────────────────────────────────────────────────────
check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc (expected=$expected, got=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ==============================
# FIXTURE 1: Well-formed work dir (positive)
# Expected: hypothesis 3/3, gate 2/4 (no trailers, no post-audit), learning 4/4, self_correction 0/4
# ==============================
echo "=== Fixture 1: Well-formed (positive) ==="
WORK1="$TMPDIR/fixture1"
mkdir -p "$WORK1/pre-audit"
echo "PASS" > "$WORK1/pre-audit/test-result.txt"
echo "2" > "$WORK1/.learnings_baseline_count"
cat > "$WORK1/WORK.md" << 'EOF'
# Work Contract

## Description
Test fixture

## Hypothesis

**Prediction:** The grader will score this well-formed fixture correctly.
**PASS:** Score matches expected values.
**FAIL:** Score does not match.

## Status
- [x] Hypothesis stated
- [x] Work completed
- [ ] Learnings extracted
- [ ] work-close run
EOF

bash scripts/score-session.sh "$WORK1" "fixture-1" > /dev/null 2>&1 || true

if [ -f "$WORK1/OPERATING_MODEL_SCORECARD.json" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: SCORECARD.json produced"
    
    # Check hypothesis score (should be 3/3)
    hd=$(python3 -c "import json; print(json.load(open('$WORK1/OPERATING_MODEL_SCORECARD.json'))['dimensions']['hypothesis_discipline']['score'])")
    check "hypothesis_discipline" "3" "$hd"
    
    # Check gate_integrity (should be 2/4: Gate1 present + no --no-verify, but no trailers and no post-audit)
    gi=$(python3 -c "import json; print(json.load(open('$WORK1/OPERATING_MODEL_SCORECARD.json'))['dimensions']['gate_integrity']['score'])")
    # Gate 1 (1pt) + no-verify (1pt) = 2. No trailers check (0) + no post-audit (0) = 2
    check "gate_integrity >= 2" "true" "$([ "$gi" -ge 2 ] && echo true || echo false)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: SCORECARD.json not produced"
fi

# ==============================
# FIXTURE 2: Missing pre-audit (negative — gate_integrity reduced)
# ==============================
echo ""
echo "=== Fixture 2: Missing pre-audit (negative) ==="
WORK2="$TMPDIR/fixture2"
mkdir -p "$WORK2"
echo "0" > "$WORK2/.learnings_baseline_count"
cat > "$WORK2/WORK.md" << 'EOF'
# Work Contract

## Description
Negative fixture: no pre-audit

## Hypothesis

**Prediction:** Missing pre-audit reduces gate score.
**PASS:** gate < 4.
**FAIL:** gate = 4.

## Status
- [x] Hypothesis stated
EOF

bash scripts/score-session.sh "$WORK2" "fixture-2" > /dev/null 2>&1 || true

if [ -f "$WORK2/OPERATING_MODEL_SCORECARD.json" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: SCORECARD.json produced"
    gi2=$(python3 -c "import json; print(json.load(open('$WORK2/OPERATING_MODEL_SCORECARD.json'))['dimensions']['gate_integrity']['score'])")
    # No pre-audit: Gate1 check should fail (0pt for that check)
    check "gate_integrity missing pre-audit" "true" "$([ "$gi2" -lt 4 ] && echo true || echo false)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: SCORECARD.json not produced"
fi

# ==============================
# FIXTURE 3: Fabricated learnings (negative — empty source column)
# ==============================
echo ""
echo "=== Fixture 3: Fabricated learnings (negative) ==="
WORK3="$TMPDIR/fixture3"
mkdir -p "$WORK3/pre-audit"
echo "PASS" > "$WORK3/pre-audit/test-result.txt"
echo "0" > "$WORK3/.learnings_baseline_count"
cat > "$WORK3/WORK.md" << 'EOF'
# Work Contract

## Description
Negative fixture: fabricated learnings

## Hypothesis

**Prediction:** Fabricated empty-source learnings score lower.
**PASS:** learning_extraction < 4.
**FAIL:** learning_extraction = 4.

## Status
- [x] Hypothesis stated
EOF

# Create a fake LEARNINGS.md with empty source column
REAL_LEARNINGS="$REPO_ROOT/LEARNINGS.md"
BACKUP_LEARNINGS="$TMPDIR/LEARNINGS.md.bak"
cp "$REAL_LEARNINGS" "$BACKUP_LEARNINGS"

# Add a fabricated entry with empty source
cat >> "$REPO_ROOT/LEARNINGS.md" << 'EOF'
| L999 | Fabricated test entry |  |
EOF

bash scripts/score-session.sh "$WORK3" "fixture-3" > /dev/null 2>&1 || true

# Restore LEARNINGS.md
cp "$BACKUP_LEARNINGS" "$REAL_LEARNINGS"

if [ -f "$WORK3/OPERATING_MODEL_SCORECARD.json" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: SCORECARD.json produced"
    le3=$(python3 -c "import json; print(json.load(open('$WORK3/OPERATING_MODEL_SCORECARD.json'))['dimensions']['learning_extraction']['score'])")
    # Empty source column: Check 3 should fail -> le < 4
    check "learning_extraction with empty source" "true" "$([ "$le3" -lt 4 ] && echo true || echo false)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: SCORECARD.json not produced"
fi

# ==============================
# SUMMARY
# ==============================
echo ""
echo "=== Golden Fixture Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "  VERDICT: PASS"
    exit 0
else
    echo "  VERDICT: FAIL"
    exit 1
fi

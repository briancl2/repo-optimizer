#!/usr/bin/env bash
# compare-scorecards.sh — Compare two audit scorecards and report delta
#
# Usage: bash scripts/compare-scorecards.sh <before_scorecard> <after_scorecard>
#
# Reads two SCORECARD.json files and reports:
#   - Per-dimension score changes
#   - Composite delta
#   - New T1 failures or T2 warnings
#   - PASS/FAIL verdict (delta ≥ +2 = PASS, delta < 0 = REGRESSION)
#
# Exit codes:
#   0 — delta ≥ 0 (improvement or stable)
#   1 — delta < 0 (regression)

set -euo pipefail

BEFORE="${1:?Usage: compare-scorecards.sh <before_scorecard.json> <after_scorecard.json>}"
AFTER="${2:?Usage: compare-scorecards.sh <before_scorecard.json> <after_scorecard.json>}"

if [ ! -f "$BEFORE" ]; then echo "ERROR: $BEFORE not found" >&2; exit 1; fi
if [ ! -f "$AFTER" ]; then echo "ERROR: $AFTER not found" >&2; exit 1; fi

# Extract values using python (reliable JSON parsing)
# B7 fix: pass paths as sys.argv, not interpolated into source code
extract() {
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
path = sys.argv[2].split('.')
v = d
for p in path:
    v = v[p]
print(v)
" "$1" "$2" 2>/dev/null || echo "?"
}

extract_int() {
    local val
    val=$(extract "$1" "$2")
    echo "$val" | grep -oE '^-?[0-9]+' || echo "0"
}

# Extract composites
B_COMP=$(extract_int "$BEFORE" "composite")
A_COMP=$(extract_int "$AFTER" "composite")
DELTA=$((A_COMP - B_COMP))

# Extract per-dimension
B_D1=$(extract_int "$BEFORE" "dimensions.D1_governance.score")
A_D1=$(extract_int "$AFTER" "dimensions.D1_governance.score")
B_D2=$(extract_int "$BEFORE" "dimensions.D2_surface_health.score")
A_D2=$(extract_int "$AFTER" "dimensions.D2_surface_health.score")
B_D3=$(extract_int "$BEFORE" "dimensions.D3_skill_maturity.score")
A_D3=$(extract_int "$AFTER" "dimensions.D3_skill_maturity.score")
B_D4=$(extract_int "$BEFORE" "dimensions.D4_measurement.score")
A_D4=$(extract_int "$AFTER" "dimensions.D4_measurement.score")
B_D5=$(extract_int "$BEFORE" "dimensions.D5_self_improvement.score")
A_D5=$(extract_int "$AFTER" "dimensions.D5_self_improvement.score")

# T1 checks
B_T1_PASS=$(extract_int "$BEFORE" "tier1_checks.passed")
A_T1_PASS=$(extract_int "$AFTER" "tier1_checks.passed")
B_T1_FAIL=$(extract_int "$BEFORE" "tier1_checks.failed")
A_T1_FAIL=$(extract_int "$AFTER" "tier1_checks.failed")

# Phase
B_PHASE=$(extract "$BEFORE" "meta.phase")
A_PHASE=$(extract "$AFTER" "meta.phase")

# Verdict
if [ "$DELTA" -ge 2 ]; then
    VERDICT="PASS (delta ≥ +2)"
elif [ "$DELTA" -ge 0 ]; then
    VERDICT="STABLE (delta 0 to +1)"
else
    VERDICT="REGRESSION (delta < 0)"
fi

# Format delta with sign
fmt_delta() {
    local d=$1
    if [ "$d" -gt 0 ]; then echo "+$d"
    elif [ "$d" -eq 0 ]; then echo "="
    else echo "$d"
    fi
}

echo "================================================================"
echo "Scorecard Comparison"
echo "================================================================"
echo ""
echo "  Before: $BEFORE"
echo "  After:  $AFTER"
echo ""
echo "  Phase:  $B_PHASE → $A_PHASE"
echo ""
echo "  Dimension        Before  After   Delta"
echo "  ─────────────────────────────────────────"
printf "  D1 Governance:    %4d    %4d    %s\n" "$B_D1" "$A_D1" "$(fmt_delta $((A_D1 - B_D1)))"
printf "  D2 Surface:       %4d    %4d    %s\n" "$B_D2" "$A_D2" "$(fmt_delta $((A_D2 - B_D2)))"
printf "  D3 Skill:         %4d    %4d    %s\n" "$B_D3" "$A_D3" "$(fmt_delta $((A_D3 - B_D3)))"
printf "  D4 Measurement:   %4d    %4d    %s\n" "$B_D4" "$A_D4" "$(fmt_delta $((A_D4 - B_D4)))"
printf "  D5 Self-Improve:  %4d    %4d    %s\n" "$B_D5" "$A_D5" "$(fmt_delta $((A_D5 - B_D5)))"
echo "  ─────────────────────────────────────────"
printf "  COMPOSITE:        %4d    %4d    %s\n" "$B_COMP" "$A_COMP" "$(fmt_delta $DELTA)"
echo ""
echo "  T1 checks: $B_T1_PASS/$((B_T1_PASS+B_T1_FAIL)) → $A_T1_PASS/$((A_T1_PASS+A_T1_FAIL))"
echo ""
echo "  VERDICT: $VERDICT"
echo "================================================================"

# Exit non-zero on regression
if [ "$DELTA" -lt 0 ]; then
    exit 1
fi

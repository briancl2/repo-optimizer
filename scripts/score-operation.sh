#!/usr/bin/env bash
# scripts/score-operation.sh — Runtime evaluation of optimization quality (C1: Runtime Eval)
#
# Evaluates the QUALITY of a completed optimization operation — not whether it ran,
# but whether the output was complete, correct, and useful.
#
# Complements score-session.sh (session PROCESS) by measuring operational OUTPUT QUALITY:
# pre-flight completeness, patch validity, plan quality, SCORECARD generation.
#
# Usage: bash scripts/score-operation.sh <optimizer_output_dir> [--json]
#
# Checks (8 total, 20 points max):
#   1. pre-flight.json exists and valid (3pt)
#   2. Bottom-2 dimensions identified (2pt)
#   3. OPTIMIZATION_PLAN.md exists and non-trivial (3pt)
#   4. OPTIMIZATION_SCORECARD.json exists and valid (2pt)
#   5. Patch generation attempted (if --patch mode) (2pt)
#   6. No timeout/error indicators (2pt)
#   7. Budget tier assigned (2pt)
#   8. Input SCORECARD referenced (4pt)
#
# Exit codes:
#   0 — evaluation complete (score in stdout)
#   1 — missing inputs
#
# Source: Stage 11.2 (C1 runtime eval). Adapted from repo-auditor pattern.

set -euo pipefail

OPT_DIR="${1:?Usage: score-operation.sh <optimizer_output_dir> [--json]}"
JSON_MODE="false"

for arg in "$@"; do
    if [ "$arg" = "--json" ]; then JSON_MODE="true"; fi
done

if [ ! -d "$OPT_DIR" ]; then
    echo "ERROR: Optimizer output directory not found: $OPT_DIR" >&2
    exit 1
fi

SCORE=0
MAX=20
ISSUES=""
EVIDENCE=""

add_score() {
    local pts="$1"
    local label="$2"
    SCORE=$((SCORE + pts))
    EVIDENCE="${EVIDENCE}  +${pts}pt: $label\n"
}

add_issue() {
    local label="$1"
    ISSUES="${ISSUES}  - $label\n"
}

# ── Check 1: pre-flight.json exists and valid (3pt) ──────────────────
PREFLIGHT="$OPT_DIR/pre-flight.json"
if [ -f "$PREFLIGHT" ]; then
    if python3 -c "import json; json.load(open('$PREFLIGHT'))" 2>/dev/null; then
        add_score 3 "pre-flight.json exists and valid JSON"
    else
        add_score 1 "pre-flight.json exists but invalid JSON"
        add_issue "pre-flight.json is not valid JSON"
    fi
else
    add_issue "pre-flight.json missing"
fi

# ── Check 2: Bottom-2 dimensions identified (2pt) ────────────────────
if [ -f "$PREFLIGHT" ]; then
    BOTTOM_DIMS=$(python3 -c "
import json
try:
    pf = json.load(open('$PREFLIGHT'))
    dims = pf.get('bottom_dimensions', pf.get('target_dimensions', []))
    print(len(dims))
except:
    print(0)
" 2>/dev/null || echo "0")
    if [ "$BOTTOM_DIMS" -ge 2 ]; then
        add_score 2 "Bottom dimensions identified ($BOTTOM_DIMS)"
    elif [ "$BOTTOM_DIMS" -ge 1 ]; then
        add_score 1 "Partial bottom dimensions ($BOTTOM_DIMS)"
        add_issue "Only $BOTTOM_DIMS bottom dimensions identified (expected 2)"
    else
        add_issue "No bottom dimensions identified in pre-flight"
    fi
fi

# ── Check 3: OPTIMIZATION_PLAN.md exists and non-trivial (3pt) ───────
PLAN="$OPT_DIR/OPTIMIZATION_PLAN.md"
if [ -f "$PLAN" ]; then
    PLAN_LINES=$(wc -l < "$PLAN" | tr -d ' ')
    if [ "$PLAN_LINES" -ge 20 ]; then
        add_score 3 "OPTIMIZATION_PLAN.md exists ($PLAN_LINES lines)"
    elif [ "$PLAN_LINES" -ge 5 ]; then
        add_score 1 "OPTIMIZATION_PLAN.md exists but sparse ($PLAN_LINES lines)"
        add_issue "OPTIMIZATION_PLAN.md is sparse ($PLAN_LINES lines)"
    else
        add_issue "OPTIMIZATION_PLAN.md is trivial ($PLAN_LINES lines)"
    fi
else
    add_issue "OPTIMIZATION_PLAN.md missing"
fi

# ── Check 4: OPTIMIZATION_SCORECARD.json exists and valid (2pt) ──────
OPT_SC="$OPT_DIR/OPTIMIZATION_SCORECARD.json"
if [ -f "$OPT_SC" ]; then
    if python3 -c "import json; json.load(open('$OPT_SC'))" 2>/dev/null; then
        add_score 2 "OPTIMIZATION_SCORECARD.json exists and valid"
    else
        add_score 1 "OPTIMIZATION_SCORECARD.json exists but invalid JSON"
        add_issue "OPTIMIZATION_SCORECARD.json is not valid JSON"
    fi
else
    add_issue "OPTIMIZATION_SCORECARD.json missing"
fi

# ── Check 5: Patch generation (2pt — if PATCH_PACK dir exists) ───────
PATCH_DIR="$OPT_DIR/PATCH_PACK"
if [ -d "$PATCH_DIR" ]; then
    PATCH_COUNT=$(find "$PATCH_DIR" -name '*.patch' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PATCH_COUNT" -gt 0 ]; then
        add_score 2 "PATCH_PACK contains $PATCH_COUNT patches"
    else
        add_score 1 "PATCH_PACK dir exists but no patches"
        add_issue "PATCH_PACK directory exists but contains 0 patches"
    fi
else
    # Patch generation may not have been requested — partial credit
    add_score 1 "No PATCH_PACK (report-only mode)"
fi

# ── Check 6: Runtime receipts / timeout indicators (2pt) ─────────────
RUNTIME_RECEIPTS="$OPT_DIR/RUNTIME_RECEIPTS.json"
RUNTIME_PHASE_FAILURES=""
if [ -f "$RUNTIME_RECEIPTS" ]; then
    RUNTIME_PHASE_FAILURES=$(python3 - "$RUNTIME_RECEIPTS" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

issues = []
for phase_name in ("critic", "synthesis"):
    phase = payload.get("phases", {}).get(phase_name, {})
    status = phase.get("status", "")
    receipt_class = phase.get("receipt_class", "")
    if status.startswith("failed_") or status in {"skipped_missing_agent", "skipped_upstream_critic_failure"}:
        issues.append(f"{phase_name}:{status}/{receipt_class}")

print("; ".join(issues))
PY
)
fi

FALLBACK_SIGNALS=0
for f in "$OPT_DIR"/*.md "$OPT_DIR"/*.txt "$OPT_DIR"/*.json; do
    if [ -f "$f" ] && grep -qi 'timeout\|timed out\|TIMEOUT\|error.*fatal' "$f" 2>/dev/null; then
        FALLBACK_SIGNALS=$((FALLBACK_SIGNALS + 1))
    fi
done

if [ -n "$RUNTIME_PHASE_FAILURES" ]; then
    add_score 1 "Runtime receipts classify fail-closed phase issues ($RUNTIME_PHASE_FAILURES)"
    add_issue "Runtime receipts classify fail-closed phase issues: $RUNTIME_PHASE_FAILURES"
elif [ "$FALLBACK_SIGNALS" -eq 0 ]; then
    add_score 2 "No timeout or error indicators"
else
    add_score 1 "Timeout/error indicators detected ($FALLBACK_SIGNALS files)"
    add_issue "Timeout or error detected in optimizer artifacts"
fi

# ── Check 7: Budget tier assigned (2pt) ──────────────────────────────
if [ -f "$PREFLIGHT" ]; then
    BUDGET_TIER=$(python3 -c "
import json
try:
    pf = json.load(open('$PREFLIGHT'))
    tier = pf.get('budget_tier', pf.get('tier', ''))
    print(tier)
except:
    print('')
" 2>/dev/null || echo "")
    if [ -n "$BUDGET_TIER" ]; then
        add_score 2 "Budget tier assigned ($BUDGET_TIER)"
    else
        add_issue "No budget tier in pre-flight"
    fi
fi

# ── Check 8: Input SCORECARD referenced (4pt) ────────────────────────
if [ -f "$PREFLIGHT" ]; then
    SC_REF=$(python3 -c "
import json
try:
    pf = json.load(open('$PREFLIGHT'))
    composite = pf.get('input_composite', pf.get('scorecard_composite', pf.get('composite', 0)))
    print(composite)
except:
    print(0)
" 2>/dev/null || echo "0")
    if [ "$SC_REF" -gt 0 ] 2>/dev/null; then
        add_score 4 "Input SCORECARD composite referenced ($SC_REF)"
    else
        add_issue "No input SCORECARD composite in pre-flight"
    fi
fi

# ── Output ────────────────────────────────────────────────────────────
if [ "$JSON_MODE" = "true" ]; then
    ISSUES_JSON=$(printf '%b' "$ISSUES" | sed 's/^  - //' | python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
" 2>/dev/null || echo '[]')
    VERDICT="PASS"
    if [ "$SCORE" -lt 14 ]; then VERDICT="FAIL"; fi
    if [ "$SCORE" -ge 14 ] && [ "$SCORE" -lt 18 ]; then VERDICT="WARN"; fi

    python3 -c "
import json, sys
result = {
    'score': $SCORE,
    'max': $MAX,
    'verdict': '$VERDICT',
    'output_dir': '$OPT_DIR',
    'issues': $ISSUES_JSON,
    'timestamp': __import__('datetime').datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
}
json.dump(result, sys.stdout, indent=2)
print()
"
else
    echo "OPERATION EVAL: Optimization Quality Assessment"
    echo "  Output dir: $OPT_DIR"
    echo ""
    printf "%b" "$EVIDENCE"
    if [ -n "$ISSUES" ]; then
        echo ""
        echo "Issues detected (session grader would miss these):"
        printf "%b" "$ISSUES"
    fi
    echo ""
    VERDICT="PASS"
    if [ "$SCORE" -lt 14 ]; then VERDICT="FAIL"; fi
    if [ "$SCORE" -ge 14 ] && [ "$SCORE" -lt 18 ]; then VERDICT="WARN"; fi
    echo "OPERATION EVAL: $SCORE/$MAX ($VERDICT)"
fi

exit 0

#!/usr/bin/env bash
# scripts/work-close.sh — Work contract finalizer for repo-optimizer
#
# Runs post-audit (make test), computes delta vs baseline, writes DELTA.md.
# REFUSES (exit 1) without learnings extraction.
# Adapted from repo-auditor work-close.sh (spec 052), per spec 054.
# Deterministic. macOS bash 3.2 compatible.
#
# Usage:
#   work-close.sh <work-dir>
#   work-close.sh <work-dir> --no-novel-findings "rationale"
#
# Requires: pre-audit baseline from work-init.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

WORK_DIR="${1:?Usage: work-close.sh <work-dir> [--no-novel-findings \"rationale\"]}"
shift

# ── Parse flags ──────────────────────────────────────────────────────
NO_NOVEL_FINDINGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-novel-findings) NO_NOVEL_FINDINGS="${2:?--no-novel-findings requires a rationale}"; shift 2 ;;
        *) shift ;;
    esac
done

# ── Resolve work dir ─────────────────────────────────────────────────
if [[ ! "$WORK_DIR" = /* ]]; then
    WORK_DIR="$REPO_ROOT/$WORK_DIR"
fi

# ── Validate work directory ──────────────────────────────────────────
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found: $WORK_DIR" >&2
    exit 1
fi

if [ ! -f "$WORK_DIR/WORK.md" ]; then
    echo "ERROR: No WORK.md found in $WORK_DIR" >&2
    echo "  Run 'make work DESC=\"...\"' to initialize a work contract first." >&2
    exit 1
fi

# ── Validate hypothesis is not a placeholder ─────────────────────────
if grep -qF '{what you expect' "$WORK_DIR/WORK.md"; then
    echo "ERROR: Gate 3 -- WORK.md still contains hypothesis placeholder text." >&2
    echo "  Fill in the Hypothesis section before closing the work contract." >&2
    exit 1
fi

echo "=== Work Close: $WORK_DIR ==="

# ── Gate 3a: Pre-audit must exist ────────────────────────────────────
if [ ! -d "$WORK_DIR/pre-audit" ]; then
    echo "ERROR: No pre-audit baseline found at $WORK_DIR/pre-audit/" >&2
    echo "  The work contract was not properly initialized." >&2
    exit 1
fi

# ── Gate 3b: Learning extraction required ────────────────────────────
LEARNINGS_ADDED=0
if [ -f LEARNINGS.md ] && [ -f "$WORK_DIR/.learnings_baseline_count" ]; then
    BASELINE_COUNT=$(cat "$WORK_DIR/.learnings_baseline_count")
    CURRENT_COUNT=$(grep -cE '^\| L[0-9]+' LEARNINGS.md 2>/dev/null || echo "0")
    LEARNINGS_ADDED=$((CURRENT_COUNT - BASELINE_COUNT))
fi

if [ "$LEARNINGS_ADDED" -le 0 ] && [ -z "$NO_NOVEL_FINDINGS" ]; then
    echo "" >&2
    echo "ERROR: Gate 3 -- Learning extraction required before closing work contract." >&2
    echo "  LEARNINGS.md has $LEARNINGS_ADDED new L-number entries (need >=1)." >&2
    echo "  Either:" >&2
    echo "    (a) Append at least one L-number to LEARNINGS.md, or" >&2
    echo "    (b) Re-run with: bash scripts/work-close.sh \"$WORK_DIR\" --no-novel-findings \"rationale\"" >&2
    echo "" >&2
    exit 1
fi

# ── Gate 3c: Assessment artifact check ───────────────────────────────
ASSESSMENT_FOUND=0
for f in "$WORK_DIR"/*review* "$WORK_DIR"/*critique* "$WORK_DIR"/*assessment*; do
    if [ -f "$f" ]; then
        # Check content validity (not empty/template)
        LINES=$(wc -l < "$f" | tr -d ' ')
        if [ "$LINES" -ge 3 ]; then
            ASSESSMENT_FOUND=1
            break
        fi
    fi
done

if [ "$ASSESSMENT_FOUND" -eq 0 ]; then
    echo "  WARNING: No assessment artifact found in work dir (review, critique, or assessment file)."
fi

# ── Post-audit: run make test ─────────────────────────────────────────
echo "  Running post-audit..."
mkdir -p "$WORK_DIR/post-audit"
if make test > "$WORK_DIR/post-audit/test-output.txt" 2>&1; then
    echo "  Post-audit: make test PASS"
    echo "PASS" > "$WORK_DIR/post-audit/test-result.txt"
else
    echo "  Post-audit: make test FAIL"
    echo "FAIL" > "$WORK_DIR/post-audit/test-result.txt"
fi

# ── Compute delta ────────────────────────────────────────────────────
PRE_RESULT="?"
POST_RESULT="?"
if [ -f "$WORK_DIR/pre-audit/test-result.txt" ]; then
    PRE_RESULT=$(cat "$WORK_DIR/pre-audit/test-result.txt")
fi
if [ -f "$WORK_DIR/post-audit/test-result.txt" ]; then
    POST_RESULT=$(cat "$WORK_DIR/post-audit/test-result.txt")
fi

# ── Write DELTA.md ───────────────────────────────────────────────────
cat > "$WORK_DIR/DELTA.md" <<EOF
# Delta Report

| Metric | Pre | Post | Delta |
|--------|-----|------|-------|
| Tests | $PRE_RESULT | $POST_RESULT | $([ "$PRE_RESULT" = "$POST_RESULT" ] && echo "STABLE" || echo "CHANGED") |

## Learnings Added: $LEARNINGS_ADDED

$(if [ -n "$NO_NOVEL_FINDINGS" ]; then echo "**No-novel-findings:** $NO_NOVEL_FINDINGS"; fi)

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "  DELTA.md written."

# ── Session grader (soft dependency) ─────────────────────────────────
SESSION_ID=$(basename "$WORK_DIR")
if [ -f scripts/score-session.sh ]; then
    echo "  Running session grader..."
    if bash scripts/score-session.sh "$WORK_DIR" "$SESSION_ID" 2>&1; then
        echo "  Session grader complete."
    else
        echo "  WARNING: Session grader failed (non-blocking)."
    fi
else
    echo "  WARNING: scripts/score-session.sh not found (skipping session grader)."
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Work Close Summary ==="
echo "  Work Dir:    $WORK_DIR"
echo "  Pre-Tests:   $PRE_RESULT"
echo "  Post-Tests:  $POST_RESULT"
echo "  Learnings:   $LEARNINGS_ADDED new"
if [ -n "$NO_NOVEL_FINDINGS" ]; then
    echo "  NNF:         $NO_NOVEL_FINDINGS"
fi
echo "  Artifacts:   DELTA.md$([ -f "$WORK_DIR/OPERATING_MODEL_SCORECARD.json" ] && echo ', OPERATING_MODEL_SCORECARD.json')"
echo "=== Done ==="

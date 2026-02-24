#!/usr/bin/env bash
# scripts/work-init.sh — Work contract initializer for repo-optimizer
#
# Creates a work directory with WORK.md template and baseline test results.
# Adapted from repo-auditor work-init.sh (spec 052), per spec 054.
# Deterministic. macOS bash 3.2 compatible.
#
# Usage: work-init.sh "description"
# Creates: work/YYYYMMDDTHHMMSSZ/WORK.md + work/YYYYMMDDTHHMMSSZ/pre-audit/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DESC="${1:?Usage: work-init.sh \"description\"}"

# ── Create work directory ─────────────────────────────────────────────
TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
WORK_DIR="work/${TIMESTAMP}"
mkdir -p "$WORK_DIR"

# ── Write WORK.md template ───────────────────────────────────────────
cat > "$WORK_DIR/WORK.md" <<'TEMPLATE'
# Work Contract

## Description

DESC_PLACEHOLDER

## Hypothesis

> **Gate 1 Required.** State a testable prediction with PASS/FAIL criteria.

**Prediction:** {what you expect to happen}
**PASS:** {measurable success condition}
**FAIL:** {measurable failure condition}

## Work Type

{code-change | fleet-run | research | bug-fix}

## Status

- [ ] Hypothesis stated
- [ ] Work completed
- [ ] Learnings extracted (or --no-novel-findings)
- [ ] work-close run

TEMPLATE

# Replace placeholder with actual description
sed -i '' "s|DESC_PLACEHOLDER|${DESC}|" "$WORK_DIR/WORK.md"

# ── Snapshot LEARNINGS.md baseline ────────────────────────────────────
if [ -f LEARNINGS.md ]; then
    grep -cE '^\| L[0-9]+' LEARNINGS.md > "$WORK_DIR/.learnings_baseline_count" 2>/dev/null || echo "0" > "$WORK_DIR/.learnings_baseline_count"
else
    echo "0" > "$WORK_DIR/.learnings_baseline_count"
fi

# ── Baseline: run make test as pre-audit ──────────────────────────────
echo "=== Work Init: $WORK_DIR ==="
echo "  Description: $DESC"
mkdir -p "$WORK_DIR/pre-audit"

if make test > "$WORK_DIR/pre-audit/test-output.txt" 2>&1; then
    echo "  Baseline: make test PASS"
    echo "PASS" > "$WORK_DIR/pre-audit/test-result.txt"
else
    echo "  WARNING: make test failed at baseline"
    echo "FAIL" > "$WORK_DIR/pre-audit/test-result.txt"
fi

echo "  WORK.md: $WORK_DIR/WORK.md"
echo ""
echo "Next steps:"
echo "  1. Fill in Hypothesis in $WORK_DIR/WORK.md"
echo "  2. Do the work"
echo "  3. make work-close WORK=$WORK_DIR"

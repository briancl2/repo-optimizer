#!/bin/bash
# pre-commit hook — Run `make review` before allowing commits
#
# Install: ln -sf ../../scripts/pre-commit-hook.sh .git/hooks/pre-commit
#
# This hook runs `make review` on staged changes before every commit.
# If review fails or copilot CLI is unavailable, the commit is BLOCKED
# (unless SKIP_REVIEW=1).
# Works identically in Copilot CLI and VS Code.
#
# IMPORTANT: --no-verify is NEVER permitted (L102, Principle 12).
# Review applies to ALL changes — code, docs, specs, artifacts. No exceptions.
#
# Escape hatch: SKIP_REVIEW=1 git commit -m "message"
#   Use ONLY when copilot CLI is genuinely unavailable (not for speed).
#   The skip is logged in the commit hook output for audit trail.
#
# Why: AI agents generate and commit code that needs review before merging.
# Without a pre-commit gate, defects propagate silently (L75, L102).

set -euo pipefail

# Check if there are staged changes
if git diff --staged --quiet 2>/dev/null; then
  exit 0  # Nothing staged, skip review
fi

# Explicit skip (escape hatch — logged for audit trail)
if [ "${SKIP_REVIEW:-0}" = "1" ]; then
  echo "=== Pre-commit: SKIP_REVIEW=1 — review skipped ==="
  echo "WARNING: This commit was NOT reviewed. Run 'make review' before pushing."
  exit 0
fi

# Check if Makefile has a review target
if [ -f "Makefile" ] && grep -q "^review:" Makefile 2>/dev/null; then
  echo "=== Pre-commit: Running make review ==="
  if make review; then
    echo "=== Review passed ==="
    exit 0
  else
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  COMMIT BLOCKED — review failed or unavailable          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Review could not complete (copilot CLI unavailable or error)."
    echo ""
    echo "  Options:"
    echo "    1. Fix copilot CLI and retry: git commit"
    echo "    2. Skip review (emergency only): SKIP_REVIEW=1 git commit -m '...'"
    echo ""
    exit 1
  fi
else
  echo "=== Pre-commit: No 'make review' target found — skipping review ==="
  echo "Tip: Add a 'review' target to your Makefile for automatic code review."
  exit 0
fi

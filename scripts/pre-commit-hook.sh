#!/bin/bash
# pre-commit hook -- Run make check before allowing commits
#
# Install: make install-hooks
# Versioned in repo. Must re-run make install-hooks after edits (L4).
#
# Runs the deterministic Gate 2 check (shellcheck, inventory, trailers).
# --no-verify requires No-Verify-Reason: trailer (L102).
#
# Spec 054: updated from make review (LLM, slow) to make check (deterministic).

set -euo pipefail

# Nothing staged? Skip.
if git diff --staged --quiet 2>/dev/null; then
  exit 0
fi

echo "=== pre-commit: running make check ==="

if [ -f "Makefile" ] && grep -q "^check:" Makefile 2>/dev/null; then
  if make check; then
    echo "=== pre-commit: PASS ==="
    exit 0
  else
    echo ""
    echo "BLOCKED: make check failed. Fix issues before committing."
    echo "Use git commit --no-verify only with No-Verify-Reason: in message."
    exit 1
  fi
else
  echo "=== pre-commit: No make check target found -- skipping ==="
  exit 0
fi

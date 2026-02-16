#!/bin/bash
# pre-push hook — Catch unreviewed commits before pushing
#
# Install: cp scripts/pre-push-hook.sh .git/hooks/pre-push && chmod +x .git/hooks/pre-push
# Or:      ln -sf ../../scripts/pre-push-hook.sh .git/hooks/pre-push
#
# This hook fires on every push that contains commits. Review applies to ALL
# changes — code, docs, specs, artifacts — because defects live everywhere.
# `--no-verify` is NEVER acceptable. (L102)
#
# Behavior:
#   Default: warn + allow (BLOCK_UNREVIEWED=0)
#   Strict:  warn + block (BLOCK_UNREVIEWED=1)

set -uo pipefail

# Count commits being pushed
REMOTE="$1"
URL="$2"

# Read stdin for commit range
while read -r LOCAL_REF LOCAL_SHA REMOTE_REF REMOTE_SHA; do
    if [ "$LOCAL_SHA" = "0000000000000000000000000000000000000000" ]; then
        continue  # Deleting branch
    fi
    
    if [ "$REMOTE_SHA" = "0000000000000000000000000000000000000000" ]; then
        # New branch — check all commits
        RANGE="$LOCAL_SHA"
    else
        RANGE="$REMOTE_SHA..$LOCAL_SHA"
    fi
    
    # Count commits in range
    COMMIT_COUNT=$(git rev-list --count "$RANGE" 2>/dev/null || echo "0")
    
    if [ "$COMMIT_COUNT" -eq 0 ]; then
        continue
    fi
    
    # Check for ANY changes (review applies to all changes, not just code)
    FILE_COUNT=$(git diff --name-only "$REMOTE_SHA".."$LOCAL_SHA" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$FILE_COUNT" -gt 0 ]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  PRE-PUSH REVIEW CHECK                                  ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Pushing $COMMIT_COUNT commit(s) with $FILE_COUNT file(s) changed."
        echo ""
        echo "  ⚠️  Have these changes been reviewed?"
        echo "     Run: make review"
        echo "     Or:  git diff $REMOTE_SHA..$LOCAL_SHA | head -200"
        echo ""
        
        if [ "${BLOCK_UNREVIEWED:-0}" = "1" ]; then
            echo "  BLOCK_UNREVIEWED=1 — blocking push."
            echo "  Run 'make review' first, then push again."
            echo ""
            exit 1
        else
            echo "  Allowing push (set BLOCK_UNREVIEWED=1 to enforce)."
            echo ""
        fi
    fi
done

exit 0

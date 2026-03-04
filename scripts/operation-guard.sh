#!/usr/bin/env bash
# scripts/operation-guard.sh — Pre-operation safety checks (C4: Guard Rails)
#
# Deterministic checks that run BEFORE each fleet operation to prevent
# contaminated runs. Catches: missing target, dirty git state, concurrent
# operations (lockfile), missing required tools, missing prerequisites.
#
# Usage: bash scripts/operation-guard.sh <target_repo> [--lockdir <dir>]
#
# Exit codes:
#   0 — all checks passed, safe to proceed
#   1 — one or more checks failed, operation should abort
#
# Source: Stage 11.2 (C4 guard rails). Adapted from repo-auditor pattern.

set -euo pipefail

TARGET="${1:?Usage: operation-guard.sh <target_repo> [--lockdir <dir>]}"
LOCKDIR=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse --lockdir flag
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lockdir) LOCKDIR="$2"; shift 2 ;;
        *) shift ;;
    esac
done

LOCKDIR="${LOCKDIR:-/tmp/repo-optimizer-locks}"
LOCKFILE="$LOCKDIR/$(echo "$TARGET" | tr '/' '_').lock"

PASS=0
FAIL=0
RESULTS=""

check() {
    local name="$1"
    local result="$2"
    local detail="${3:-}"
    if [ "$result" = "PASS" ]; then
        PASS=$((PASS + 1))
        RESULTS="${RESULTS}  [PASS] $name"
        if [ -n "$detail" ]; then RESULTS="${RESULTS} -- $detail"; fi
        RESULTS="${RESULTS}\n"
    else
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}  [FAIL] $name"
        if [ -n "$detail" ]; then RESULTS="${RESULTS} -- $detail"; fi
        RESULTS="${RESULTS}\n"
    fi
}

# ── Check 1: Target directory exists ──────────────────────────────────
if [ -d "$TARGET" ]; then
    check "Target directory" "PASS" "$TARGET"
else
    check "Target directory" "FAIL" "not found: $TARGET"
fi

# ── Check 2: Target git state clean ──────────────────────────────────
if [ -d "$TARGET/.git" ] || git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    DIRTY_COUNT=$(git -C "$TARGET" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIRTY_COUNT" -eq 0 ]; then
        check "Target git state" "PASS" "clean"
    else
        check "Target git state" "FAIL" "$DIRTY_COUNT uncommitted files"
    fi
else
    check "Target git state" "PASS" "not a git repo (skip)"
fi

# ── Check 3: No concurrent lockfile ──────────────────────────────────
if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "unknown")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        check "Concurrent lock" "FAIL" "active lock (PID $LOCK_PID)"
    else
        rm -f "$LOCKFILE"
        check "Concurrent lock" "PASS" "stale lock removed"
    fi
else
    check "Concurrent lock" "PASS" "no lock"
fi

# ── Check 4: Required tools available ─────────────────────────────────
MISSING_TOOLS=""
for tool in git find grep wc python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done
if [ -z "$MISSING_TOOLS" ]; then
    check "Required tools" "PASS"
else
    check "Required tools" "FAIL" "missing:$MISSING_TOOLS"
fi

# ── Result ────────────────────────────────────────────────────────────
echo "GUARD: Pre-operation checks"
printf "%b" "$RESULTS"

if [ "$FAIL" -gt 0 ]; then
    echo "GUARD: FAIL ($FAIL check(s) failed, $PASS passed)"
    exit 1
fi

echo "GUARD: PASS ($PASS checks passed)"

# NOTE: Lock acquisition moved to the calling script (repo-optimizer.sh)
# so the lock PID matches the actual long-running operation process.
# Guard only CHECKS, does not acquire. (v150 critique CRITICAL-1 fix)

exit 0

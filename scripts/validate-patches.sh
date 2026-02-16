#!/usr/bin/env bash
# validate-patches.sh — Validate all patches in PATCH_PACK/ with git apply --check.
#
# Usage: bash scripts/validate-patches.sh <repo_path> <patch_dir>

set -euo pipefail

REPO="${1:?Usage: validate-patches.sh <repo_path> <patch_dir>}"
PATCH_DIR="${2:?Usage: validate-patches.sh <repo_path> <patch_dir>}"

if [ ! -d "$REPO" ]; then
    echo "ERROR: Repository not found: $REPO" >&2
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "ERROR: Patch directory not found: $PATCH_DIR" >&2
    exit 1
fi

PASS=0
FAIL=0
TOTAL=0

echo "=== Patch Validation ==="
echo "  Repo: $REPO"
echo "  Patches: $PATCH_DIR"
echo ""

for patch in "$PATCH_DIR"/*.patch; do
    [ -f "$patch" ] || continue
    TOTAL=$((TOTAL + 1))
    NAME="$(basename "$patch")"

    # Check file count
    FILES=$(grep -c "^diff --git" "$patch" || true)
    if [ "$FILES" -gt 6 ]; then
        echo "  ✗ $NAME — exceeds 6-file limit ($FILES files)"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Check with git apply
    if (cd "$REPO" && git apply --check "$patch" 2>/dev/null); then
        echo "  ✓ $NAME ($FILES files)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $NAME — FAILS git apply --check"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "  Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [ "$TOTAL" -eq 0 ]; then
    echo "  No patches found."
    exit 0
fi

if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

#!/usr/bin/env bash
# generate-patches.sh — Generate unified diff patches from approved findings.
#
# Usage: bash scripts/generate-patches.sh <repo_path> <findings_file> <output_dir>
#
# Reads approved findings and generates patch files in PATCH_PACK/ directory.
# Each patch is validated with git apply --check.

set -euo pipefail

REPO="${1:?Usage: generate-patches.sh <repo_path> <findings_file> <output_dir>}"
FINDINGS="${2:?Usage: generate-patches.sh <repo_path> <findings_file> <output_dir>}"
OUTPUT_DIR="${3:?Usage: generate-patches.sh <repo_path> <findings_file> <output_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$OUTPUT_DIR/PATCH_PACK"
mkdir -p "$PATCH_DIR"

echo "=== Patch Generation ==="
echo "  Repo: $REPO"
echo "  Findings: $FINDINGS"
echo "  Output: $PATCH_DIR"
echo ""

# Validate patches exist
if [ ! -f "$FINDINGS" ]; then
    echo "ERROR: Findings file not found: $FINDINGS"
    exit 1
fi

echo "Patch generation requires LLM agent to create diffs from findings."
echo "Run the repo-optimizer agent (phases 2-4) to generate patches."
echo ""
echo "After patches are generated, validate with:"
echo "  for p in $PATCH_DIR/*.patch; do"
echo "    cd $REPO && git apply --check \"\$p\" && echo \"✓ \$(basename \$p)\""
echo "  done"

# Post-process any existing patches
PATCH_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    [ -f "$patch" ] || continue
    PATCH_COUNT=$((PATCH_COUNT + 1))

    # Fix diff headers if needed
    if [ -x "$SCRIPT_DIR/fix-diff-headers.sh" ]; then
        bash "$SCRIPT_DIR/fix-diff-headers.sh" "$patch" 2>/dev/null || true
    fi

    # Validate
    BASENAME="$(basename "$patch")"
    if cd "$REPO" && git apply --check "$patch" 2>/dev/null; then
        echo "  ✓ $BASENAME — applies cleanly"
    else
        echo "  ✗ $BASENAME — FAILS git apply --check"
    fi
done

if [ "$PATCH_COUNT" -eq 0 ]; then
    echo "  No patches found in $PATCH_DIR/"
fi

echo ""
echo "=== Done. $PATCH_COUNT patches processed ==="

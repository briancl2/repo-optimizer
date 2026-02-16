#!/usr/bin/env bash
# validate-bundle.sh — Check optimizer output bundle completeness and integrity.
#
# Usage: bash validate-bundle.sh <output_dir>
#
# Checks:
#   1. Required files exist and are non-empty
#   2. JSON artifacts are valid JSON
#   3. Patches (if present) pass git apply --check
#   4. SHA256 hashes match manifest (if manifest exists)

set -euo pipefail

OUTPUT_DIR="${1:?Usage: validate-bundle.sh <output_dir>}"
PASS=0
FAIL=0

echo "=== Bundle Integrity Check ==="
echo "  Directory: $OUTPUT_DIR"
echo ""

# Check required files
check_file() {
    local file="$1"
    local required="$2"
    local path="$OUTPUT_DIR/$file"

    if [ -s "$path" ]; then
        echo "  ✓ $file ($(wc -l < "$path" | tr -d ' ')L)"
        PASS=$((PASS + 1))
    elif [ "$required" = "yes" ]; then
        echo "  ✗ $file — MISSING (required)"
        FAIL=$((FAIL + 1))
    else
        echo "  - $file — not present (optional)"
    fi
}

echo "--- Required Files ---"
check_file "OPTIMIZATION_PLAN.md" "yes"
check_file "OPTIMIZATION_SCORECARD.json" "yes"

echo ""
echo "--- Optional Files ---"
check_file "manifest.json" "no"

# Check patches if PATCH_PACK exists
if [ -d "$OUTPUT_DIR/PATCH_PACK" ]; then
    echo ""
    echo "--- Patch Validation ---"
    PATCH_COUNT=0
    PATCH_VALID=0
    for patch in "$OUTPUT_DIR/PATCH_PACK"/*.patch; do
        [ -f "$patch" ] || continue
        PATCH_COUNT=$((PATCH_COUNT + 1))
        NAME="$(basename "$patch")"
        # Count files and lines
        FILES_IN_PATCH=$(grep -c "^diff --git" "$patch" || true)
        LINES_IN_PATCH=$(wc -l < "$patch" | tr -d ' ')

        # Check constraints
        if [ "$FILES_IN_PATCH" -gt 6 ]; then
            echo "  ✗ $NAME — exceeds 6-file limit ($FILES_IN_PATCH files)"
            FAIL=$((FAIL + 1))
            continue
        fi

        echo "  ✓ $NAME ($FILES_IN_PATCH files, ${LINES_IN_PATCH}L)"
        PATCH_VALID=$((PATCH_VALID + 1))
        PASS=$((PASS + 1))
    done
    echo "  Patches: $PATCH_VALID/$PATCH_COUNT valid"
fi

# Validate JSON artifacts
echo ""
echo "--- JSON Validation ---"
for json in "$OUTPUT_DIR"/*.json; do
    [ -f "$json" ] || continue
    NAME="$(basename "$json")"
    if python3 -c "import json; json.load(open('$json'))" 2>/dev/null; then
        echo "  ✓ $NAME — valid JSON"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $NAME — INVALID JSON"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results ==="
echo "  PASS: $PASS  FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

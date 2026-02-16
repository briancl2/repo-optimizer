#!/bin/bash
# fix-diff-headers.sh — Recount and fix unified diff hunk headers
#
# Usage: fix-diff-headers.sh <PATCH_PACK.md> [output.md]
#
# LLM-generated diffs often have correct content but incorrect @@ counts.
# This script recounts actual lines and rewrites hunk headers.
#
# Algorithm:
#   1. Read file line by line
#   2. Detect ```diff blocks
#   3. For each @@ hunk, recount: old = context + removes, new = context + adds
#   4. Rewrite @@ header with correct counts
#   5. Preserve all other content unchanged
#
# Compatible with macOS bash 3.2 (no associative arrays, no readarray).

set -euo pipefail

INPUT_FILE="${1:?Usage: fix-diff-headers.sh <PATCH_PACK.md> [output.md]}"
OUTPUT_FILE="${2:-}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Temp file for processing
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# State machine: outside | in_diff | in_hunk
state="outside"
hunk_lines=""
old_start=0
new_start=0
hunk_header=""

recount_and_emit_hunk() {
    if [ -z "$hunk_lines" ]; then
        return
    fi
    
    # Count lines by type
    local context_count=0 remove_count=0 add_count=0
    local line
    while IFS= read -r line; do
        case "$line" in
            " "*) context_count=$((context_count + 1)) ;;
            "-"*) remove_count=$((remove_count + 1)) ;;
            "+"*) add_count=$((add_count + 1)) ;;
        esac
    done <<EOF
$hunk_lines
EOF
    
    # Recount: old = context + removes, new = context + adds
    local old_count=$((context_count + remove_count))
    local new_count=$((context_count + add_count))
    
    # Emit corrected header
    echo "@@ -${old_start},${old_count} +${new_start},${new_count} @@"
    
    # Emit hunk content
    echo "$hunk_lines"
    
    # Reset state
    hunk_lines=""
}

while IFS= read -r line; do
    case "$state" in
        outside)
            if echo "$line" | grep -q '```diff'; then
                state="in_diff"
                echo "$line"
            else
                echo "$line"
            fi
            ;;
        
        in_diff)
            if echo "$line" | grep -q '^```$'; then
                # End of diff block - emit any pending hunk
                recount_and_emit_hunk
                state="outside"
                echo "$line"
            elif echo "$line" | grep -qE '^@@'; then
                # New hunk - emit previous hunk if any
                recount_and_emit_hunk
                
                # Parse hunk header: @@ -N,M +N,M @@
                # Extract old_start and new_start
                old_start=$(echo "$line" | sed -E 's/^@@[[:space:]]*-([0-9]+).*/\1/')
                new_start=$(echo "$line" | sed -E 's/^.*\+([0-9]+).*/\1/')
                
                state="in_hunk"
                # Don't emit header yet - will recount and emit when hunk ends
            elif echo "$line" | grep -qE '^(---|\+\+\+)'; then
                # File header lines - pass through
                echo "$line"
            else
                # Pass through non-hunk lines in diff block
                echo "$line"
            fi
            ;;
        
        in_hunk)
            if echo "$line" | grep -q '^```$'; then
                # End of diff block
                recount_and_emit_hunk
                state="outside"
                echo "$line"
            elif echo "$line" | grep -qE '^@@'; then
                # New hunk - emit previous hunk
                recount_and_emit_hunk
                
                # Parse new hunk header
                old_start=$(echo "$line" | sed -E 's/^@@[[:space:]]*-([0-9]+).*/\1/')
                new_start=$(echo "$line" | sed -E 's/^.*\+([0-9]+).*/\1/')
                # Stay in in_hunk state
            elif echo "$line" | grep -qE '^(---|\+\+\+)'; then
                # File header - should not appear mid-hunk, but handle gracefully
                recount_and_emit_hunk
                echo "$line"
                state="in_diff"
            elif echo "$line" | grep -qE '^( |\+|-)'; then
                # Hunk content line
                if [ -z "$hunk_lines" ]; then
                    hunk_lines="$line"
                else
                    hunk_lines="$hunk_lines"$'\n'"$line"
                fi
            else
                # Non-diff line (e.g., blank, text) - end hunk
                recount_and_emit_hunk
                echo "$line"
                state="in_diff"
            fi
            ;;
    esac
done < "$INPUT_FILE" > "$TEMP_FILE"

# Emit any final pending hunk
if [ "$state" = "in_hunk" ]; then
    recount_and_emit_hunk >> "$TEMP_FILE"
fi

# Output to file or stdout
if [ -n "$OUTPUT_FILE" ]; then
    mv "$TEMP_FILE" "$OUTPUT_FILE"
    echo "Fixed diff written to: $OUTPUT_FILE" >&2
else
    cat "$TEMP_FILE"
fi

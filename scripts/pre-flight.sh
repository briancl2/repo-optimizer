#!/usr/bin/env bash
# pre-flight.sh — Read SCORECARD + AUDIT + OPPORTUNITIES, identify optimization targets.
#
# Usage: bash scripts/pre-flight.sh <audit_dir> [output_file]
#
# Reads audit artifacts and outputs a pre-flight summary identifying
# bottom-2 dimensions, T2 warnings, and optimization priorities.

set -euo pipefail

AUDIT_DIR="${1:?Usage: pre-flight.sh <audit_dir> [output_file]}"
OUTPUT_FILE="${2:-/dev/stdout}"

if [ ! -f "$AUDIT_DIR/SCORECARD.json" ]; then
    echo "ERROR: SCORECARD.json not found in $AUDIT_DIR" >&2
    exit 1
fi

python3 -c "
import json, sys

with open('$AUDIT_DIR/SCORECARD.json') as f:
    data = json.load(f)

composite = data.get('composite', 0)
dims = data.get('dimensions', {})

# Sort by score ascending
scores = sorted(
    [(k, v.get('score', 0), v.get('max', 20)) for k, v in dims.items()],
    key=lambda x: x[1]
)

# T2 warnings
warnings = data.get('tier2_warnings', {}).get('warnings', [])

# Build pre-flight summary
result = {
    'composite': composite,
    'bottom_2': [s[0] for s in scores[:2]],
    'dimensions': {s[0]: {'score': s[1], 'max': s[2]} for s in scores},
    'tier2_warnings': warnings,
    'optimization_targets': [
        {'dimension': s[0], 'gap': s[2] - s[1], 'score': s[1], 'max': s[2]}
        for s in scores[:2]
    ]
}

print(json.dumps(result, indent=2))
" > "$OUTPUT_FILE"

echo "Pre-flight complete. Output: $OUTPUT_FILE" >&2

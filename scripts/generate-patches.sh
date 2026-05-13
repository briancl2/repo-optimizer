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

python3 - "$REPO" "$FINDINGS" "$PATCH_DIR/P4-shell-hardening.patch" <<'PY'
from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
findings = Path(sys.argv[2])
patch_path = Path(sys.argv[3])

plan = findings.read_text(encoding="utf-8", errors="replace")

# First deterministic materializer: the retained P4/S-05/S-06/S-07 shell
# hardening patch. Other patch families remain recommendation-only until they
# get their own bounded materializer.
if not (
    re.search(r"\bS-05\b", plan)
    and re.search(r"\bS-06\b", plan)
    and re.search(r"\bS-07\b", plan)
):
    sys.exit(0)

targets = [
    "scripts/pre-commit-hook.sh",
    ".agents/skills/reviewing-code-locally/scripts/local_review.sh",
]


def harden_shell(lines: list[str]) -> list[str]:
    if not lines:
        return lines

    updated = list(lines)
    if updated[0] == "#!/bin/bash":
        updated[0] = "#!/usr/bin/env bash"

    if updated[0].startswith("#!") and "set -euo pipefail" not in updated[:5]:
        updated.insert(1, "set -euo pipefail")

    return updated


patch_parts: list[str] = []
changed_files = 0

for rel in targets:
    path = repo / rel
    if not path.exists():
        continue

    old = path.read_text(encoding="utf-8", errors="replace").splitlines()
    new = harden_shell(old)
    if old == new:
        continue

    diff = list(
        difflib.unified_diff(
            old,
            new,
            fromfile=f"a/{rel}",
            tofile=f"b/{rel}",
            lineterm="",
        )
    )
    if not diff:
        continue

    patch_parts.append(f"diff --git a/{rel} b/{rel}")
    patch_parts.extend(diff)
    changed_files += 1

if changed_files:
    patch_path.write_text("\n".join(patch_parts) + "\n", encoding="utf-8")
PY

# Post-process any existing patches
PATCH_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    [ -f "$patch" ] || continue
    PATCH_COUNT=$((PATCH_COUNT + 1))

    # Fix diff headers if needed
    if [ -x "$SCRIPT_DIR/fix-diff-headers.sh" ]; then
        TMP_PATCH="$(mktemp)"
        if bash "$SCRIPT_DIR/fix-diff-headers.sh" "$patch" "$TMP_PATCH" >/dev/null 2>&1; then
            mv "$TMP_PATCH" "$patch"
        else
            rm -f "$TMP_PATCH"
        fi
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

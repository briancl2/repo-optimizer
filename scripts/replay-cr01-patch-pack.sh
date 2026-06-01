#!/usr/bin/env bash
# replay-cr01-patch-pack.sh — Bounded read-only CR-01 patch-pack replay.
#
# Usage: bash scripts/replay-cr01-patch-pack.sh <repo_path> <output_dir> <target_file> <capability>
#
# Builds a one-row CR-01 optimization manifest, generates a patch pack,
# validates it with git apply --check, and records target git state before/after.
# It never applies patches or mutates the target repository.

set -euo pipefail

REPO="${1:?Usage: replay-cr01-patch-pack.sh <repo_path> <output_dir> <target_file> <capability>}"
OUTPUT_DIR="${2:?Usage: replay-cr01-patch-pack.sh <repo_path> <output_dir> <target_file> <capability>}"
TARGET_FILE="${3:?Usage: replay-cr01-patch-pack.sh <repo_path> <output_dir> <target_file> <capability>}"
CAPABILITY="${4:?Usage: replay-cr01-patch-pack.sh <repo_path> <output_dir> <target_file> <capability>}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: target path must be inside a git checkout: $REPO" >&2
    exit 1
fi

REPO_TOP="$(git -C "$REPO" rev-parse --show-toplevel)"
REPO_ABS="$(python3 - "$REPO_TOP" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=True))
PY
)"
REPO="$REPO_ABS"
OUTPUT_ABS="$(python3 - "$OUTPUT_DIR" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"

case "$OUTPUT_ABS" in
    "$REPO_ABS"|"$REPO_ABS"/*)
        echo "ERROR: output_dir must be outside the target repository: $OUTPUT_DIR" >&2
        exit 1
        ;;
esac

case "$TARGET_FILE" in
    /*|../*|*/../*)
        echo "ERROR: target_file must be a safe repository-relative path: $TARGET_FILE" >&2
        exit 1
        ;;
esac

if [ ! -f "$REPO/$TARGET_FILE" ]; then
    echo "ERROR: target_file does not exist in target repo: $TARGET_FILE" >&2
    exit 1
fi

python3 - "$TARGET_FILE" "$CAPABILITY" <<'PY'
from __future__ import annotations

import re
import sys

target_file, capability = sys.argv[1:3]
if not re.fullmatch(r"[A-Za-z0-9_./-]+", target_file):
    raise SystemExit("ERROR: target_file contains unsupported manifest characters")
if not capability.strip():
    raise SystemExit("ERROR: capability must not be empty")
if any(ch in capability for ch in "\r\n`|"):
    raise SystemExit("ERROR: capability contains unsupported manifest table characters")
PY

BEFORE_HEAD="$(git -C "$REPO" rev-parse HEAD)"
BEFORE_STATUS="$(git -C "$REPO" status --short)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$OUTPUT_ABS/OPTIMIZATION_PLAN.md"
PATCH_DIR="$OUTPUT_ABS/PATCH_PACK"
RECEIPT="$OUTPUT_ABS/CR01_REPLAY_RECEIPT.json"
GENERATE_LOG="$OUTPUT_ABS/cr01-generate-patches.log"
VALIDATE_LOG="$OUTPUT_ABS/cr01-validate-patches.log"

mkdir -p "$OUTPUT_ABS"

cat > "$MANIFEST" <<EOF
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| CR-01 | capability reconciliation for capability \`$CAPABILITY\` in \`$TARGET_FILE\` | 1 |
EOF

GENERATE_STATUS=0
if bash "$SCRIPT_DIR/generate-patches.sh" "$REPO" "$MANIFEST" "$OUTPUT_ABS" > "$GENERATE_LOG" 2>&1; then
    GENERATE_STATUS=0
else
    GENERATE_STATUS=$?
fi

VALIDATE_STATUS=0
if bash "$SCRIPT_DIR/validate-patches.sh" "$REPO" "$PATCH_DIR" > "$VALIDATE_LOG" 2>&1; then
    VALIDATE_STATUS=0
else
    VALIDATE_STATUS=$?
fi

AFTER_HEAD="$(git -C "$REPO" rev-parse HEAD)"
AFTER_STATUS="$(git -C "$REPO" status --short)"

PATCH_COUNT=0
if [ -d "$PATCH_DIR" ]; then
    PATCH_COUNT="$(find "$PATCH_DIR" -maxdepth 1 -name '*.patch' -type f | wc -l | tr -d ' ')"
fi

EXPECTED_PATCH="$PATCH_DIR/CR-01-default-capability-reconciliation.patch"
PATCHES_VALID=0
if [ "$PATCH_COUNT" -gt 0 ]; then
    for patch in "$PATCH_DIR"/*.patch; do
        [ -f "$patch" ] || continue
        if git -C "$REPO" apply --check "$patch" 2>/dev/null; then
            PATCHES_VALID=$((PATCHES_VALID + 1))
        fi
    done
fi

UNCHANGED=false
if [ "$BEFORE_HEAD" = "$AFTER_HEAD" ] && [ "$BEFORE_STATUS" = "$AFTER_STATUS" ]; then
    UNCHANGED=true
fi

STATUS="failed"
if [ "$GENERATE_STATUS" -eq 0 ] && [ "$VALIDATE_STATUS" -eq 0 ] && [ "$PATCH_COUNT" -eq 1 ] && [ -s "$EXPECTED_PATCH" ] && [ "$PATCHES_VALID" -eq 1 ] && [ "$UNCHANGED" = "true" ]; then
    STATUS="completed"
fi

python3 - "$RECEIPT" "$STATUS" "$REPO" "$MANIFEST" "$PATCH_DIR" "$GENERATE_LOG" "$VALIDATE_LOG" "$GENERATE_STATUS" "$VALIDATE_STATUS" "$PATCH_COUNT" "$PATCHES_VALID" "$BEFORE_HEAD" "$AFTER_HEAD" "$BEFORE_STATUS" "$AFTER_STATUS" "$UNCHANGED" "$SCRIPT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    receipt,
    status,
    repo,
    manifest,
    patch_dir,
    generate_log,
    validate_log,
    generate_status,
    validate_status,
    patch_count,
    patches_valid,
    before_head,
    after_head,
    before_status,
    after_status,
    unchanged,
    script_dir,
) = sys.argv[1:18]

script_dir_path = Path(script_dir)
payload = {
    "schema_version": "1.0.0",
    "artifact": "CR01_REPLAY_RECEIPT",
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": status,
    "target_repo": str(Path(repo).resolve()),
    "target_read_only": True,
    "manifest_path": str(Path(manifest).resolve()),
    "patch_dir": str(Path(patch_dir).resolve()),
    "receipt_path": str(Path(receipt).resolve()),
    "patches_generated": int(patch_count),
    "patches_valid": int(patches_valid),
    "target_git_state_unchanged": unchanged == "true",
    "before_git_head": before_head,
    "after_git_head": after_head,
    "before_git_status": before_status,
    "after_git_status": after_status,
    "commands": [
        {
            "command": f"bash {script_dir_path / 'generate-patches.sh'} {repo} {manifest} {Path(patch_dir).parent}",
            "exit_code": int(generate_status),
            "log_path": str(Path(generate_log).resolve()),
        },
        {
            "command": f"bash {script_dir_path / 'validate-patches.sh'} {repo} {patch_dir}",
            "exit_code": int(validate_status),
            "log_path": str(Path(validate_log).resolve()),
        },
    ],
    "bounded_non_claims": [
        "Replay validates patch generation and git apply --check only.",
        "Replay does not apply patches or mutate the target repository.",
    ],
}
Path(receipt).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [ "$STATUS" != "completed" ]; then
    echo "ERROR: CR-01 replay failed; receipt: $RECEIPT" >&2
    exit 1
fi

echo "CR-01 replay completed"
echo "  manifest: $MANIFEST"
echo "  patch_dir: $PATCH_DIR"
echo "  receipt: $RECEIPT"

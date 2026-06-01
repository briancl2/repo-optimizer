#!/usr/bin/env bash
# test-cr01-replay.sh — Verify bounded CR-01 replay is read-only and receipts-backed.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="$(mktemp -d)"
OUTPUT_DIR="$(mktemp -d)"
LINK_PARENT="$(mktemp -d)"
WORKTREE_REPO="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$OUTPUT_DIR" "$LINK_PARENT" "$WORKTREE_REPO"' EXIT

mkdir -p "$TARGET_REPO/docs"
cat > "$TARGET_REPO/docs/capability-guidance.md" <<'EOF'
# Capability Guidance

Existing guidance before replay.
EOF
(
    cd "$TARGET_REPO"
    git init -q
    git config user.email test@example.invalid
    git config user.name "Test User"
    git add docs/capability-guidance.md
    git commit -q -m initial
)

if bash "$OPT_DIR/scripts/replay-cr01-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR" \
    docs/capability-guidance.md \
    "Hermes -z" >/dev/null; then
    echo "  ✓ CR-01 replay completed"
else
    echo "  ✗ CR-01 replay failed"
    exit 1
fi

RECEIPT="$OUTPUT_DIR/CR01_REPLAY_RECEIPT.json"
PATCH="$OUTPUT_DIR/PATCH_PACK/CR-01-default-capability-reconciliation.patch"
MANIFEST="$OUTPUT_DIR/OPTIMIZATION_PLAN.md"

if [ -s "$MANIFEST" ] \
    && grep -Fq '| CR-01 | capability reconciliation for capability `Hermes -z` in `docs/capability-guidance.md` | 1 |' "$MANIFEST"; then
    echo "  ✓ CR-01 replay wrote one-row optimization manifest"
else
    echo "  ✗ CR-01 replay manifest missing expected one-row CR-01 entry"
    [ -f "$MANIFEST" ] && cat "$MANIFEST"
    exit 1
fi

if [ -s "$PATCH" ] && bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$OUTPUT_DIR/PATCH_PACK" >/dev/null; then
    echo "  ✓ CR-01 replay patch pack validates with git apply --check"
else
    echo "  ✗ CR-01 replay patch pack did not validate"
    [ -f "$PATCH" ] && cat "$PATCH"
    exit 1
fi

if [ -s "$RECEIPT" ] \
    && python3 - "$RECEIPT" "$TARGET_REPO" "$MANIFEST" "$PATCH" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2]).resolve()
manifest = Path(sys.argv[3]).resolve()
patch = Path(sys.argv[4]).resolve()
assert receipt["artifact"] == "CR01_REPLAY_RECEIPT"
assert receipt["status"] == "completed"
assert receipt["target_read_only"] is True
assert receipt["patches_generated"] == 1
assert receipt["patches_valid"] == 1
assert receipt["target_git_state_unchanged"] is True
assert receipt["before_git_head"] == receipt["after_git_head"]
assert receipt["before_git_status"] == receipt["after_git_status"] == ""
assert Path(receipt["manifest_path"]).resolve() == manifest
assert Path(receipt["patch_dir"]).resolve() == patch.parent
assert Path(receipt["receipt_path"]).resolve() == Path(sys.argv[1]).resolve()
assert receipt["commands"][0]["command"].startswith("bash ")
assert "generate-patches.sh" in receipt["commands"][0]["command"]
assert "validate-patches.sh" in receipt["commands"][1]["command"]
status = subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True)
assert status == ""
PY
then
    echo "  ✓ CR-01 replay receipt records read-only unchanged git proof"
else
    echo "  ✗ CR-01 replay receipt missing expected proof"
    [ -f "$RECEIPT" ] && cat "$RECEIPT"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-cr01-patch-pack.sh" \
    "$TARGET_REPO" \
    "$TARGET_REPO/.cr01-replay-output" \
    docs/capability-guidance.md \
    "Hermes -z" >/dev/null 2>&1; then
    echo "  ✗ CR-01 replay allowed output inside target repo"
    exit 1
else
    echo "  ✓ CR-01 replay rejects output inside target repo"
fi

ln -s "$TARGET_REPO" "$LINK_PARENT/target-link"
if bash "$OPT_DIR/scripts/replay-cr01-patch-pack.sh" \
    "$LINK_PARENT/target-link" \
    "$TARGET_REPO/.cr01-replay-symlink-output" \
    docs/capability-guidance.md \
    "Hermes -z" >/dev/null 2>&1; then
    echo "  ✗ CR-01 replay allowed output inside symlinked target repo"
    exit 1
else
    echo "  ✓ CR-01 replay canonicalizes symlinked target repo guard"
fi

if bash "$OPT_DIR/scripts/replay-cr01-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR/unsafe-capability" \
    docs/capability-guidance.md \
    "Hermes|z" >/dev/null 2>&1; then
    echo "  ✗ CR-01 replay allowed manifest-breaking capability text"
    exit 1
else
    echo "  ✓ CR-01 replay rejects manifest-breaking capability text"
fi

git -C "$TARGET_REPO" worktree add --detach -q "$WORKTREE_REPO" HEAD
if bash "$OPT_DIR/scripts/replay-cr01-patch-pack.sh" \
    "$WORKTREE_REPO" \
    "$OUTPUT_DIR/worktree-replay" \
    docs/capability-guidance.md \
    "Hermes -z" >/dev/null; then
    echo "  ✓ CR-01 replay accepts git worktree targets"
else
    echo "  ✗ CR-01 replay rejected a valid git worktree target"
    exit 1
fi

echo ""
echo "=== CR-01 replay test passed ==="

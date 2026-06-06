#!/usr/bin/env bash
# test-native-pruning-replay.sh - Verify bounded NR-01 replay is read-only and receipts-backed.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="$(mktemp -d)"
OUTPUT_DIR="$(mktemp -d)"
LINK_PARENT="$(mktemp -d)"
WORKTREE_REPO="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$OUTPUT_DIR" "$LINK_PARENT" "$WORKTREE_REPO"' EXIT

mkdir -p "$TARGET_REPO/docs"
cat > "$TARGET_REPO/docs/pruning-continuity.md" <<'EOF'
# Pruning Continuity

Existing owner-review notes before replay.
EOF
(
    cd "$TARGET_REPO"
    git init -q
    git config user.email test@example.invalid
    git config user.name "Test User"
    git add docs/pruning-continuity.md
    git commit -q -m initial
)

if bash "$OPT_DIR/scripts/replay-native-pruning-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR" \
    docs/pruning-continuity.md \
    "repo-agent-core upstream capability intake contract" >/dev/null; then
    echo "  ✓ NR-01 replay completed"
else
    echo "  ✗ NR-01 replay failed"
    exit 1
fi

RECEIPT="$OUTPUT_DIR/NR01_REPLAY_RECEIPT.json"
PATCH="$OUTPUT_DIR/PATCH_PACK/NR-01-native-replacement-pruning-candidate.patch"
MANIFEST="$OUTPUT_DIR/OPTIMIZATION_PLAN.md"

if [ -s "$MANIFEST" ] \
    && grep -Fq '| NR-01 | native replacement pruning candidate for native capability `repo-agent-core upstream capability intake contract` in `docs/pruning-continuity.md` affected_surface: docs/pruning-continuity.md' "$MANIFEST"; then
    echo "  ✓ NR-01 replay wrote one-row optimization manifest"
else
    echo "  ✗ NR-01 replay manifest missing expected one-row NR-01 entry"
    [ -f "$MANIFEST" ] && cat "$MANIFEST"
    exit 1
fi

if [ -s "$PATCH" ] && bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$OUTPUT_DIR/PATCH_PACK" >/dev/null; then
    echo "  ✓ NR-01 replay patch pack validates with git apply --check"
else
    echo "  ✗ NR-01 replay patch pack did not validate"
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
assert receipt["artifact"] == "NR01_REPLAY_RECEIPT"
assert receipt["status"] == "completed"
assert receipt["target_read_only"] is True
assert receipt["target_file"] == "docs/pruning-continuity.md"
assert receipt["native_capability"] == "repo-agent-core upstream capability intake contract"
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
    echo "  ✓ NR-01 replay receipt records read-only unchanged git proof"
else
    echo "  ✗ NR-01 replay receipt missing expected proof"
    [ -f "$RECEIPT" ] && cat "$RECEIPT"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-native-pruning-patch-pack.sh" \
    "$TARGET_REPO" \
    "$TARGET_REPO/.nr01-replay-output" \
    docs/pruning-continuity.md \
    "repo-agent-core upstream capability intake contract" >/dev/null 2>&1; then
    echo "  ✗ NR-01 replay allowed output inside target repo"
    exit 1
else
    echo "  ✓ NR-01 replay rejects output inside target repo"
fi

ln -s "$TARGET_REPO" "$LINK_PARENT/target-link"
if bash "$OPT_DIR/scripts/replay-native-pruning-patch-pack.sh" \
    "$LINK_PARENT/target-link" \
    "$TARGET_REPO/.nr01-replay-symlink-output" \
    docs/pruning-continuity.md \
    "repo-agent-core upstream capability intake contract" >/dev/null 2>&1; then
    echo "  ✗ NR-01 replay allowed output inside symlinked target repo"
    exit 1
else
    echo "  ✓ NR-01 replay canonicalizes symlinked target repo guard"
fi

if bash "$OPT_DIR/scripts/replay-native-pruning-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR/unsafe-capability" \
    docs/pruning-continuity.md \
    "repo-agent-core|upstream" >/dev/null 2>&1; then
    echo "  ✗ NR-01 replay allowed manifest-breaking native capability text"
    exit 1
else
    echo "  ✓ NR-01 replay rejects manifest-breaking native capability text"
fi

git -C "$TARGET_REPO" worktree add --detach -q "$WORKTREE_REPO" HEAD
if bash "$OPT_DIR/scripts/replay-native-pruning-patch-pack.sh" \
    "$WORKTREE_REPO" \
    "$OUTPUT_DIR/worktree-replay" \
    docs/pruning-continuity.md \
    "repo-agent-core upstream capability intake contract" >/dev/null; then
    echo "  ✓ NR-01 replay accepts git worktree targets"
else
    echo "  ✗ NR-01 replay rejected a valid git worktree target"
    exit 1
fi

echo ""
echo "=== NR-01 replay test passed ==="

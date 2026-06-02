#!/usr/bin/env bash
# test-recovery-runtime-replay.sh — Verify bounded recovery-runtime replay patch packs.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="$(mktemp -d)"
OUTPUT_DIR="$(mktemp -d)"
BLOCKED_OUTPUT="$(mktemp -d)"
LINK_PARENT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$OUTPUT_DIR" "$BLOCKED_OUTPUT" "$LINK_PARENT"' EXIT

mkdir -p "$TARGET_REPO/docs"
cat > "$TARGET_REPO/docs/foreground-guide.md" <<'EOF'
# Foreground Guide

Existing foreground command guidance.
EOF
cat > "$TARGET_REPO/docs/learning-recovery.md" <<'EOF'
# Learning Recovery

Existing learning capture guidance.
EOF
cat > "$TARGET_REPO/docs/already-grounded.md" <<'EOF'
# Already Grounded

## Foreground Failure Guidance / Recovery

- Failure signal: already present.
- Recovery owner: already present.
- Recovery action: already present.
- Evidence receipt: already present.
- Bounded non-claims: already present.
EOF
(
    cd "$TARGET_REPO"
    git init -q
    git config user.email test@example.invalid
    git config user.name "Test User"
    git add docs
    git commit -q -m initial
)

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR" \
    --fgr-target docs/foreground-guide.md \
    --lr-target docs/learning-recovery.md >/dev/null; then
    echo "  ✓ recovery-runtime replay completed for FGR-01 and LR-01 safe rows"
else
    echo "  ✗ recovery-runtime replay failed for safe rows"
    exit 1
fi

MANIFEST="$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
RECEIPT="$OUTPUT_DIR/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
SCORECARD="$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json"
FGR_PATCH="$OUTPUT_DIR/PATCH_PACK/FGR-01-foreground-failure-guidance-recovery.patch"
LR_PATCH="$OUTPUT_DIR/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch"

if [ -s "$MANIFEST" ] \
    && grep -Fq '| FGR-01 | foreground failure guidance recovery for `docs/foreground-guide.md`' "$MANIFEST" \
    && grep -Fq '| LR-01 | Learning Recovery guidance for `docs/learning-recovery.md`' "$MANIFEST"; then
    echo "  ✓ replay wrote explicit recovery-runtime optimization manifest"
else
    echo "  ✗ replay manifest missing expected FGR-01/LR-01 rows"
    [ -f "$MANIFEST" ] && cat "$MANIFEST"
    exit 1
fi

if [ -s "$FGR_PATCH" ] \
    && [ -s "$LR_PATCH" ] \
    && grep -Fq '## Foreground Failure Guidance / Recovery' "$FGR_PATCH" \
    && grep -Fq '## Learning / Recovery' "$LR_PATCH" \
    && bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$OUTPUT_DIR/PATCH_PACK" >/dev/null; then
    echo "  ✓ recovery-runtime replay patch pack validates with git apply --check"
else
    echo "  ✗ recovery-runtime replay patch pack did not validate"
    find "$OUTPUT_DIR" -maxdepth 3 -type f -print
    [ -f "$FGR_PATCH" ] && cat "$FGR_PATCH"
    [ -f "$LR_PATCH" ] && cat "$LR_PATCH"
    exit 1
fi

if [ -s "$RECEIPT" ] \
    && [ -s "$SCORECARD" ] \
    && python3 - "$RECEIPT" "$SCORECARD" "$TARGET_REPO" "$MANIFEST" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
scorecard = json.loads(Path(sys.argv[2]).read_text())
target = Path(sys.argv[3]).resolve()
manifest = Path(sys.argv[4]).resolve()
assert receipt["artifact"] == "RECOVERY_RUNTIME_REPLAY_RECEIPT"
assert receipt["status"] == "completed"
assert receipt["target_read_only"] is True
assert receipt["materializers"] == ["FGR-01", "LR-01"]
assert receipt["expected_patches"] == 2
assert receipt["patches_generated"] == 2
assert receipt["patches_valid"] == 2
assert receipt["expected_blockers"] == 0
assert receipt["blocker_count"] == 0
assert receipt["target_git_state_unchanged"] is True
assert receipt["before_git_head"] == receipt["after_git_head"]
assert receipt["before_git_status"] == receipt["after_git_status"] == ""
assert Path(receipt["manifest_path"]).resolve() == manifest
assert Path(receipt["optimization_scorecard_path"]).resolve() == Path(sys.argv[2]).resolve()
assert scorecard["patches_generated"] == 2
assert scorecard["patches_valid"] == 2
assert scorecard["recommendation_strength"] == "limited"
assert scorecard["meta"]["status"] == "completed"
assert any("generate-patches.sh" in command["command"] for command in receipt["commands"])
assert any("validate-patches.sh" in command["command"] for command in receipt["commands"])
status = subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True)
assert status == ""
PY
then
    echo "  ✓ replay receipt records expected patch/blocker counts and unchanged target git proof"
else
    echo "  ✗ replay receipt missing expected proof"
    [ -f "$RECEIPT" ] && cat "$RECEIPT"
    exit 1
fi

if make -C "$OPT_DIR" validate OUTPUT_DIR="$OUTPUT_DIR" >/dev/null; then
    echo "  ✓ recovery-runtime replay output passes make validate"
else
    echo "  ✗ recovery-runtime replay output failed make validate"
    find "$OUTPUT_DIR" -maxdepth 3 -type f -print
    [ -f "$SCORECARD" ] && cat "$SCORECARD"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$BLOCKED_OUTPUT" \
    --fgr-target docs/foreground-guide.md \
    --fgr-target docs/already-grounded.md \
    --expect-patches 1 \
    --expect-blockers 1 >/dev/null; then
    echo "  ✓ recovery-runtime replay preserves expected PATCHABILITY_BLOCKERS.json for unsafe row"
else
    echo "  ✗ recovery-runtime replay failed expected blocker preservation case"
    find "$BLOCKED_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" "$BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" <<'PY'
import json
import sys
from pathlib import Path

blockers = json.loads(Path(sys.argv[1]).read_text())
receipt = json.loads(Path(sys.argv[2]).read_text())
assert blockers["patches_generated"] == 1
assert blockers["blocker_count"] == 1
row = blockers["blockers"][0]
assert row["row_id"] == "FGR-01"
assert row["blocker_code"] == "fgr01_already_grounded"
assert "already-grounded.md" in row["reason"]
assert receipt["patches_generated"] == 1
assert receipt["blocker_count"] == 1
assert receipt["status"] == "completed"
PY
then
    echo "  ✓ blocker artifact remains intact and receipt reflects expected unsafe row"
else
    echo "  ✗ blocker artifact or receipt lost unsafe-row evidence"
    [ -f "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$TARGET_REPO/.recovery-runtime-output" \
    --fgr-target docs/foreground-guide.md >/dev/null 2>&1; then
    echo "  ✗ replay allowed output inside target repo"
    exit 1
else
    echo "  ✓ replay rejects output inside target repo"
fi

ln -s "$TARGET_REPO" "$LINK_PARENT/target-link"
if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$LINK_PARENT/target-link" \
    "$TARGET_REPO/.recovery-runtime-symlink-output" \
    --lr-target docs/learning-recovery.md >/dev/null 2>&1; then
    echo "  ✗ replay allowed output inside symlinked target repo"
    exit 1
else
    echo "  ✓ replay canonicalizes symlinked target repo guard"
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR/bad-target" \
    --fgr-target ../escape.md >/dev/null 2>&1; then
    echo "  ✗ replay allowed unsafe target file"
    exit 1
else
    echo "  ✓ replay rejects unsafe target files before manifest generation"
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$OUTPUT_DIR/mismatch" \
    --fgr-target docs/foreground-guide.md \
    --expect-patches 2 >/dev/null 2>&1; then
    echo "  ✗ replay ignored explicit expectation mismatch"
    exit 1
else
    echo "  ✓ replay fails closed on patch-count expectation mismatch"
fi

echo ""
echo "=== Recovery-runtime replay test passed ==="

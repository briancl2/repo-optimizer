#!/usr/bin/env bash
# replay-recovery-runtime-patch-pack.sh — Bounded read-only recovery-runtime patch-pack replay.
#
# Usage:
#   bash scripts/replay-recovery-runtime-patch-pack.sh <repo_path> <output_dir> \
#     [--fgr-target <repo-relative-file>]... [--lr-target <repo-relative-file>]... \
#     [--expect-patches <count>] [--expect-blockers <count>]
#
# Builds an explicit FGR-01/LR-01 optimization manifest, generates a patch pack,
# validates it with git apply --check, and records target git state before/after.
# It never applies patches or mutates the target repository.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: replay-recovery-runtime-patch-pack.sh <repo_path> <output_dir> [options]

Options:
  --fgr-target <path>      Add one FGR-01 foreground failure guidance target file.
  --lr-target <path>       Add one LR-01 Learning Recovery target file.
  --expect-patches <n>     Required generated patch count. Defaults to one per materializer family present.
  --expect-blockers <n>    Required PATCHABILITY_BLOCKERS blocker_count. Defaults to 0.
  -h, --help               Show this help.

All target files must be explicit repository-relative files. The output directory
must be outside the target repository. This replay writes only output artifacts;
it does not apply patches or mutate the target repository.
EOF
}

if [ $# -lt 2 ]; then
    usage
    exit 2
fi

REPO="${1:?repo path required}"
OUTPUT_DIR="${2:?output dir required}"
shift 2

FGR_TARGETS=()
LR_TARGETS=()
EXPECT_PATCHES=""
EXPECT_BLOCKERS="0"

while [ $# -gt 0 ]; do
    case "$1" in
        --fgr-target)
            FGR_TARGETS+=("${2:?--fgr-target requires a repository-relative file}")
            shift 2
            ;;
        --lr-target)
            LR_TARGETS+=("${2:?--lr-target requires a repository-relative file}")
            shift 2
            ;;
        --expect-patches)
            EXPECT_PATCHES="${2:?--expect-patches requires a count}"
            shift 2
            ;;
        --expect-blockers)
            EXPECT_BLOCKERS="${2:?--expect-blockers requires a count}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [ "${#FGR_TARGETS[@]}" -eq 0 ] && [ "${#LR_TARGETS[@]}" -eq 0 ]; then
    echo "ERROR: at least one --fgr-target or --lr-target is required" >&2
    exit 2
fi

python3 - "$EXPECT_BLOCKERS" "$EXPECT_PATCHES" <<'PY'
import re
import sys
for label, value, allow_empty in (
    ("--expect-blockers", sys.argv[1], False),
    ("--expect-patches", sys.argv[2], True),
):
    if allow_empty and value == "":
        continue
    if not re.fullmatch(r"[0-9]+", value):
        raise SystemExit(f"ERROR: {label} must be a non-negative integer")
PY

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

validate_target_file() {
    local rel="$1"
    case "$rel" in
        /*|../*|*/../*|.git|.git/*|*/.git|*/.git/*)
            echo "ERROR: target file must be a safe repository-relative path: $rel" >&2
            exit 1
            ;;
    esac
    python3 - "$rel" <<'PY'
from pathlib import PurePosixPath
import re
import sys
rel = sys.argv[1]
if not re.fullmatch(r"[A-Za-z0-9_./-]+", rel):
    raise SystemExit("ERROR: target file contains unsupported manifest characters")
if PurePosixPath(rel).suffix not in {".md", ".txt"} and not rel.endswith("/SKILL.md"):
    raise SystemExit("ERROR: target file must be a .md, .txt, or */SKILL.md path supported by FGR-01/LR-01 materializers")
PY
    if [ ! -f "$REPO/$rel" ]; then
        echo "ERROR: target file does not exist in target repo: $rel" >&2
        exit 1
    fi
}

if [ "${#FGR_TARGETS[@]}" -gt 0 ]; then
    for rel in "${FGR_TARGETS[@]}"; do
        validate_target_file "$rel"
    done
fi
if [ "${#LR_TARGETS[@]}" -gt 0 ]; then
    for rel in "${LR_TARGETS[@]}"; do
        validate_target_file "$rel"
    done
fi

if [ -z "$EXPECT_PATCHES" ]; then
    EXPECT_PATCHES=0
    if [ "${#FGR_TARGETS[@]}" -gt 0 ]; then
        EXPECT_PATCHES=$((EXPECT_PATCHES + 1))
    fi
    if [ "${#LR_TARGETS[@]}" -gt 0 ]; then
        EXPECT_PATCHES=$((EXPECT_PATCHES + 1))
    fi
fi

BEFORE_HEAD="$(git -C "$REPO" rev-parse HEAD)"
BEFORE_STATUS="$(git -C "$REPO" status --short)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$OUTPUT_ABS/OPTIMIZATION_PLAN.md"
PATCH_DIR="$OUTPUT_ABS/PATCH_PACK"
BLOCKERS="$OUTPUT_ABS/PATCHABILITY_BLOCKERS.json"
RECEIPT="$OUTPUT_ABS/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
SCORECARD="$OUTPUT_ABS/OPTIMIZATION_SCORECARD.json"
GENERATE_LOG="$OUTPUT_ABS/recovery-runtime-generate-patches.log"
VALIDATE_LOG="$OUTPUT_ABS/recovery-runtime-validate-patches.log"

mkdir -p "$OUTPUT_ABS"

MANIFEST_ARGS=("$MANIFEST" "${#FGR_TARGETS[@]}" "${#LR_TARGETS[@]}")
if [ "${#FGR_TARGETS[@]}" -gt 0 ]; then
    MANIFEST_ARGS+=("${FGR_TARGETS[@]}")
fi
if [ "${#LR_TARGETS[@]}" -gt 0 ]; then
    MANIFEST_ARGS+=("${LR_TARGETS[@]}")
fi
python3 - "${MANIFEST_ARGS[@]}" <<'PY'
from pathlib import Path
import sys
manifest = Path(sys.argv[1])
fgr_count = int(sys.argv[2])
lr_count = int(sys.argv[3])
values = sys.argv[4:]
fgr_targets = values[:fgr_count]
lr_targets = values[fgr_count:fgr_count + lr_count]
lines = [
    "# Optimization Plan",
    "",
    "## Patch Manifest",
    "",
    "| Patch # | Findings | Files touched |",
    "|---|---|---:|",
]
for target in fgr_targets:
    lines.append(f"| FGR-01 | foreground failure guidance recovery for `{target}` scan_context={{\"scanner\":\"recovery-runtime-replay\",\"scan_limited\":true,\"sample\":\"explicit-fgr-target\"}} | 1 |")
for target in lr_targets:
    lines.append(f"| LR-01 | Learning Recovery guidance for `{target}` scan_context={{\"scanner\":\"recovery-runtime-replay\",\"scan_limited\":true,\"sample\":\"explicit-lr-target\"}} | 1 |")
manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

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

PATCHES_VALID=0
if [ "$PATCH_COUNT" -gt 0 ]; then
    for patch in "$PATCH_DIR"/*.patch; do
        [ -f "$patch" ] || continue
        if git -C "$REPO" apply --check "$patch" 2>/dev/null; then
            PATCHES_VALID=$((PATCHES_VALID + 1))
        fi
    done
fi

BLOCKER_COUNT=0
if [ -s "$BLOCKERS" ]; then
    BLOCKER_COUNT="$(python3 - "$BLOCKERS" <<'PY'
import json
import sys
print(int(json.load(open(sys.argv[1])).get("blocker_count", 0)))
PY
)"
fi

UNCHANGED=false
if [ "$BEFORE_HEAD" = "$AFTER_HEAD" ] && [ "$BEFORE_STATUS" = "$AFTER_STATUS" ]; then
    UNCHANGED=true
fi

MATERIALIZERS=""
if [ "${#FGR_TARGETS[@]}" -gt 0 ]; then
    MATERIALIZERS="FGR-01"
fi
if [ "${#LR_TARGETS[@]}" -gt 0 ]; then
    if [ -n "$MATERIALIZERS" ]; then
        MATERIALIZERS="$MATERIALIZERS,LR-01"
    else
        MATERIALIZERS="LR-01"
    fi
fi

STATUS="failed"
if [ "$GENERATE_STATUS" -eq 0 ] \
    && [ "$VALIDATE_STATUS" -eq 0 ] \
    && [ "$PATCH_COUNT" -eq "$EXPECT_PATCHES" ] \
    && [ "$PATCHES_VALID" -eq "$PATCH_COUNT" ] \
    && [ "$BLOCKER_COUNT" -eq "$EXPECT_BLOCKERS" ] \
    && [ "$UNCHANGED" = "true" ]; then
    STATUS="completed"
fi

python3 - "$RECEIPT" "$SCORECARD" "$STATUS" "$REPO" "$MANIFEST" "$PATCH_DIR" "$BLOCKERS" "$GENERATE_LOG" "$VALIDATE_LOG" "$GENERATE_STATUS" "$VALIDATE_STATUS" "$PATCH_COUNT" "$PATCHES_VALID" "$EXPECT_PATCHES" "$BLOCKER_COUNT" "$EXPECT_BLOCKERS" "$BEFORE_HEAD" "$AFTER_HEAD" "$BEFORE_STATUS" "$AFTER_STATUS" "$UNCHANGED" "$SCRIPT_DIR" "$MATERIALIZERS" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    receipt,
    scorecard,
    status,
    repo,
    manifest,
    patch_dir,
    blockers,
    generate_log,
    validate_log,
    generate_status,
    validate_status,
    patch_count,
    patches_valid,
    expected_patches,
    blocker_count,
    expected_blockers,
    before_head,
    after_head,
    before_status,
    after_status,
    unchanged,
    script_dir,
    materializers,
) = sys.argv[1:24]

script_dir_path = Path(script_dir)
materializer_list = [item for item in materializers.split(",") if item]
bounded_non_claims = [
    "Replay consumes explicit FGR-01/LR-01 target rows and validates generated patch packs only.",
    "Replay does not run a controller, scheduler, queue, daemon, retry loop, retained report, downstream mutation, or direct target mutation.",
    "Replay does not apply generated patches to the target repository.",
]
payload = {
    "schema_version": "1.0.0",
    "artifact": "RECOVERY_RUNTIME_REPLAY_RECEIPT",
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": status,
    "target_repo": str(Path(repo).resolve()),
    "target_read_only": True,
    "materializers": materializer_list,
    "manifest_path": str(Path(manifest).resolve()),
    "patch_dir": str(Path(patch_dir).resolve()),
    "patchability_blockers_path": str(Path(blockers).resolve()) if Path(blockers).exists() else None,
    "receipt_path": str(Path(receipt).resolve()),
    "optimization_scorecard_path": str(Path(scorecard).resolve()),
    "expected_patches": int(expected_patches),
    "patches_generated": int(patch_count),
    "patches_valid": int(patches_valid),
    "expected_blockers": int(expected_blockers),
    "blocker_count": int(blocker_count),
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
    "bounded_non_claims": bounded_non_claims,
}
scorecard_payload = {
    "findings_total": len(materializer_list),
    "findings_approved": len(materializer_list),
    "findings_rejected": 0,
    "patches_generated": int(patch_count),
    "patches_valid": int(patches_valid),
    "expected_delta": 0,
    "coverage_verdict": "partial",
    "recommendation_strength": "limited",
    "bounded_non_claims": bounded_non_claims,
    "meta": {
        "status": status,
        "patch_status": "patches_generated" if int(patch_count) else "patchability_blocked",
        "target": str(Path(repo).resolve()),
        "optimizer_version": "recovery-runtime-replay-v1",
    },
}
Path(receipt).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
Path(scorecard).write_text(json.dumps(scorecard_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [ "$STATUS" != "completed" ]; then
    echo "ERROR: recovery-runtime replay failed closed; receipt: $RECEIPT" >&2
    echo "  expected patches: $EXPECT_PATCHES; actual patches: $PATCH_COUNT; valid patches: $PATCHES_VALID" >&2
    echo "  expected blockers: $EXPECT_BLOCKERS; actual blockers: $BLOCKER_COUNT" >&2
    echo "  target unchanged: $UNCHANGED" >&2
    echo "  generate log: $GENERATE_LOG" >&2
    echo "  validate log: $VALIDATE_LOG" >&2
    exit 1
fi

echo "Recovery-runtime replay completed"
echo "  manifest: $MANIFEST"
echo "  patch_dir: $PATCH_DIR"
echo "  blockers: $BLOCKERS"
echo "  receipt: $RECEIPT"

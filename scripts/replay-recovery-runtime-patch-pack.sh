#!/usr/bin/env bash
# replay-recovery-runtime-patch-pack.sh — Bounded read-only recovery-runtime patch-pack replay.
#
# Usage:
#   bash scripts/replay-recovery-runtime-patch-pack.sh <repo_path> <output_dir> \
#     [--fgr-target <repo-relative-file>]... [--lr-target <repo-relative-file>]... \
#     [--from-advisor <OPPORTUNITIES.json>] [--expect-patches <count>] [--expect-blockers <count>]
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
  --from-advisor <json>    Read repo-upgrade-advisor OPPORTUNITIES.json bridge rows.
  --expect-patches <n>     Required generated patch count. Defaults to one per materializer family present.
  --expect-blockers <n>    Required PATCHABILITY_BLOCKERS blocker_count. Defaults to 0,
                           or to the actual blocker count for advisor-derived
                           mixed replay rows when omitted.
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
FROM_ADVISOR=""
EXPECT_PATCHES=""
EXPECT_BLOCKERS=""

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
        --from-advisor)
            FROM_ADVISOR="${2:?--from-advisor requires OPPORTUNITIES.json}"
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

if [ "${#FGR_TARGETS[@]}" -eq 0 ] && [ "${#LR_TARGETS[@]}" -eq 0 ] && [ -z "$FROM_ADVISOR" ]; then
    echo "ERROR: at least one --fgr-target, --lr-target, or --from-advisor is required" >&2
    exit 2
fi

python3 - "$EXPECT_BLOCKERS" "$EXPECT_PATCHES" <<'PY'
import re
import sys
for label, value, allow_empty in (
    ("--expect-blockers", sys.argv[1], True),
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

if [ -n "$FROM_ADVISOR" ] && [ ! -f "$FROM_ADVISOR" ]; then
    echo "ERROR: --from-advisor file does not exist: $FROM_ADVISOR" >&2
    exit 1
fi
ADVISOR_ABS=""
if [ -n "$FROM_ADVISOR" ]; then
    ADVISOR_ABS="$(python3 - "$FROM_ADVISOR" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=True))
PY
)"
fi

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
    if [ "${#FGR_TARGETS[@]}" -gt 0 ] || { [ -n "$ADVISOR_ABS" ] && grep -Fq '"patch_materializer": "FGR-01"' "$ADVISOR_ABS"; }; then
        EXPECT_PATCHES=$((EXPECT_PATCHES + 1))
    fi
    if [ "${#LR_TARGETS[@]}" -gt 0 ] || { [ -n "$ADVISOR_ABS" ] && grep -Fq '"patch_materializer": "LR-01"' "$ADVISOR_ABS"; }; then
        EXPECT_PATCHES=$((EXPECT_PATCHES + 1))
    fi
fi

BEFORE_HEAD="$(git -C "$REPO" rev-parse HEAD)"
BEFORE_STATUS="$(git -C "$REPO" status --short)"
BEFORE_DIRTY_COUNT="$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"
TARGET_REMOTE_URL="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
TARGET_REPO_IDENTITY="$(python3 - "$REPO" "$TARGET_REMOTE_URL" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

repo_name = Path(sys.argv[1]).name
remote = sys.argv[2].strip()
if not remote:
    print(repo_name)
    raise SystemExit(0)

if "://" in remote:
    parsed = urlsplit(remote)
    netloc = parsed.hostname or ""
    if parsed.port:
        netloc = f"{netloc}:{parsed.port}"
    sanitized = urlunsplit((parsed.scheme, netloc, parsed.path, "", ""))
elif "@" in remote and ":" in remote.split("@", 1)[1]:
    sanitized = remote.split("@", 1)[1]
else:
    sanitized = remote

print(f"{repo_name} <{sanitized}>")
PY
)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$OUTPUT_ABS/OPTIMIZATION_PLAN.md"
PATCH_DIR="$OUTPUT_ABS/PATCH_PACK"
PATCH_METADATA="$OUTPUT_ABS/PATCH_PACK_METADATA.json"
BLOCKERS="$OUTPUT_ABS/PATCHABILITY_BLOCKERS.json"
RECEIPT="$OUTPUT_ABS/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
SCORECARD="$OUTPUT_ABS/OPTIMIZATION_SCORECARD.json"
GENERATE_LOG="$OUTPUT_ABS/recovery-runtime-generate-patches.log"
VALIDATE_LOG="$OUTPUT_ABS/recovery-runtime-validate-patches.log"

mkdir -p "$OUTPUT_ABS"

MANIFEST_ARGS=("$MANIFEST" "$REPO" "$ADVISOR_ABS" "${#FGR_TARGETS[@]}" "${#LR_TARGETS[@]}")
if [ "${#FGR_TARGETS[@]}" -gt 0 ]; then
    MANIFEST_ARGS+=("${FGR_TARGETS[@]}")
fi
if [ "${#LR_TARGETS[@]}" -gt 0 ]; then
    MANIFEST_ARGS+=("${LR_TARGETS[@]}")
fi
python3 - "${MANIFEST_ARGS[@]}" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any

manifest = Path(sys.argv[1])
repo = Path(sys.argv[2])
advisor_arg = sys.argv[3]
fgr_count = int(sys.argv[4])
lr_count = int(sys.argv[5])
values = sys.argv[6:]
fgr_targets = values[:fgr_count]
lr_targets = values[fgr_count:fgr_count + lr_count]

SAFE_TARGET_RE = re.compile(r"[A-Za-z0-9_./-]+")
SUPPORTED_SUFFIXES = {".md", ".txt"}
PRESERVE_KEYS = [
    "anti_pattern_family",
    "evidence_refs",
    "owner_surface",
    "first_deliverable",
    "downstream_pilot_receipt",
    "downstream_pilot_context",
]


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def is_safe_target(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    rel = value.strip()
    if not rel or rel.startswith("/") or rel.startswith("../") or "/../" in rel:
        return False
    if any(part == ".git" for part in PurePosixPath(rel).parts):
        return False
    if not SAFE_TARGET_RE.fullmatch(rel):
        return False
    if PurePosixPath(rel).suffix not in SUPPORTED_SUFFIXES and not rel.endswith("/SKILL.md"):
        return False
    return (repo / rel).is_file()


def advisor_metadata(row: dict[str, Any], *, blocker_code: str | None = None, blocker_reason: str | None = None) -> dict[str, Any]:
    metadata: dict[str, Any] = {"advisor_row": row}
    for key in PRESERVE_KEYS:
        if key in row:
            metadata[key] = row[key]
    if blocker_code:
        metadata["blocker_code"] = blocker_code
    if blocker_reason:
        metadata["blocker_reason"] = blocker_reason
    return metadata


def blocker_row(row: dict[str, Any], code: str, reason: str) -> tuple[str, str, str]:
    rec_id = str(row.get("id") or "advisor-row")
    findings = f"Advisor bridge blocker for {rec_id}: {reason} advisor_metadata={compact_json(advisor_metadata(row, blocker_code=code, blocker_reason=reason))}"
    safe_rec_id = re.sub(r"[^A-Za-z0-9_.-]+", "-", rec_id).strip("-") or "advisor-row"
    return f"ADVISOR-BLOCKER-{safe_rec_id}", findings, "0"


def advisor_manifest_rows(path: Path) -> list[tuple[str, str, str]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"ERROR: invalid --from-advisor JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit("ERROR: --from-advisor JSON must be an object")
    recommendations = payload.get("recommendations")
    if not isinstance(recommendations, list):
        return [
            blocker_row(
                {"id": "recommendations", "value": recommendations},
                "advisor_missing_recommendation_object",
                "OPPORTUNITIES.json must contain a recommendations array.",
            )
        ]

    rows: list[tuple[str, str, str]] = []
    for idx, rec in enumerate(recommendations, start=1):
        if not isinstance(rec, dict):
            rows.append(
                blocker_row(
                    {"id": f"REC-{idx:02d}", "value": rec},
                    "advisor_missing_recommendation_object",
                    "Advisor recommendation entry must be an object.",
                )
            )
            continue
        materializer = rec.get("patch_materializer")
        target = rec.get("patch_target_file")
        if materializer not in {"FGR-01", "LR-01"}:
            rows.append(
                blocker_row(
                    rec,
                    "advisor_unsupported_patch_materializer",
                    "Advisor bridge rows must declare patch_materializer FGR-01 or LR-01.",
                )
            )
            continue
        if isinstance(target, list) or isinstance(target, dict):
            rows.append(
                blocker_row(
                    rec,
                    "advisor_ambiguous_broad_row",
                    "Advisor bridge rows must name exactly one patch_target_file.",
                )
            )
            continue
        if not is_safe_target(target):
            rows.append(
                blocker_row(
                    rec,
                    "advisor_unsafe_patch_target_file",
                    "Advisor bridge row patch_target_file is missing, unsafe, unsupported, or absent from the target repo.",
                )
            )
            continue
        scan_context = rec.get("scan_context") if isinstance(rec.get("scan_context"), dict) else {
            "scanner": "repo-upgrade-advisor",
            "scan_limited": True,
            "source": "--from-advisor",
        }
        evidence_context = rec.get("evidence_context") if isinstance(rec.get("evidence_context"), dict) else None
        finding_prefix = (
            "foreground failure guidance recovery"
            if materializer == "FGR-01"
            else "Learning Recovery guidance"
        )
        metadata = advisor_metadata(rec)
        findings = f"{finding_prefix} for `{target}` scan_context={compact_json(scan_context)}"
        if evidence_context:
            findings += f" evidence_context={compact_json(evidence_context)}"
        findings += f" advisor_metadata={compact_json(metadata)}"
        rows.append((materializer, findings, "1"))
    return rows

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
if advisor_arg:
    for row_id, findings, files_touched in advisor_manifest_rows(Path(advisor_arg)):
        lines.append(f"| {row_id} | {findings} | {files_touched} |")
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
AFTER_DIRTY_COUNT="$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"

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
ADVISOR_BLOCKER_COUNT=0
ADVISOR_PATCHABLE_COUNT=0
if [ -s "$BLOCKERS" ]; then
    BLOCKER_COUNT="$(python3 - "$BLOCKERS" <<'PY'
import json
import sys
print(int(json.load(open(sys.argv[1])).get("blocker_count", 0)))
PY
)"
    ADVISOR_BLOCKER_COUNT="$(python3 - "$BLOCKERS" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
count = 0
for row in payload.get("blockers", []):
    if isinstance(row, dict) and str(row.get("blocker_code", "")).startswith("advisor_"):
        count += 1
print(count)
PY
)"
fi
if [ -n "$ADVISOR_ABS" ]; then
    ADVISOR_PATCHABLE_COUNT="$(python3 - "$ADVISOR_ABS" "$REPO" <<'PY'
import json
import re
import sys
from pathlib import Path, PurePosixPath

payload = json.load(open(sys.argv[1]))
repo = Path(sys.argv[2])
safe_re = re.compile(r"[A-Za-z0-9_./-]+")
supported_suffixes = {".md", ".txt"}
count = 0
for rec in payload.get("recommendations", []):
    if not isinstance(rec, dict):
        continue
    materializer = rec.get("patch_materializer")
    target = rec.get("patch_target_file")
    if materializer not in {"FGR-01", "LR-01"}:
        continue
    if not isinstance(target, str):
        continue
    rel = target.strip()
    if not rel or rel.startswith("/") or rel.startswith("../") or "/../" in rel:
        continue
    if any(part == ".git" for part in PurePosixPath(rel).parts):
        continue
    if not safe_re.fullmatch(rel):
        continue
    if PurePosixPath(rel).suffix not in supported_suffixes and not rel.endswith("/SKILL.md"):
        continue
    if (repo / rel).is_file():
        count += 1
print(count)
PY
)"
fi

if [ -z "$EXPECT_BLOCKERS" ]; then
    if [ -n "$ADVISOR_ABS" ] && [ "$ADVISOR_PATCHABLE_COUNT" -gt 0 ] && [ "$PATCH_COUNT" -gt 0 ] && [ "$ADVISOR_BLOCKER_COUNT" -eq "$BLOCKER_COUNT" ]; then
        EXPECT_BLOCKERS="$ADVISOR_BLOCKER_COUNT"
    else
        EXPECT_BLOCKERS=0
    fi
fi

python3 - "$PATCH_METADATA" "$BLOCKERS" "$RECEIPT" "$PATCH_DIR" "$VALIDATE_LOG" "$MANIFEST" "$REPO" "$TARGET_REPO_IDENTITY" "$BEFORE_HEAD" "$AFTER_HEAD" "$BEFORE_DIRTY_COUNT" "$AFTER_DIRTY_COUNT" "$ADVISOR_ABS" <<'PY'
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

(
    patch_metadata,
    blockers,
    receipt,
    patch_dir,
    validate_log,
    manifest,
    repo,
    target_repo_identity,
    before_head,
    after_head,
    before_dirty_count,
    after_dirty_count,
    source_advisor_artifact,
) = sys.argv[1:14]

bounded_non_claims = [
    "This receipt does not apply patches.",
    "This receipt does not open downstream PRs or issues.",
    "This receipt does not mutate the target repo.",
    "This receipt does not install hooks or change target repo configuration.",
    "This receipt does not start a daemon, scheduler, queue, controller, retry loop, hidden registry, background sync, MCP server, watcher, cron job, service, or autopilot.",
    "This receipt does not perform automatic GitHub issue creation.",
    "This receipt does not claim the generated patch pack is safe to apply without explicit operator review and an explicit downstream write step outside this pilot.",
]
context: dict[str, Any] = {
    "artifact": "DOWNSTREAM_READ_ONLY_RECOVERY_RUNTIME_PILOT_RECEIPT_CONTEXT",
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "contract_reference": "https://github.com/briancl2/repo-agent-core/blob/main/docs/downstream-read-only-recovery-runtime-pilot-contract.md",
    "target_repo_identity": target_repo_identity,
    "target_path_or_name": str(Path(repo).resolve()),
    "target_git_head_before": before_head,
    "target_git_head_after": after_head,
    "target_dirty_count_before": int(before_dirty_count),
    "target_dirty_count_after": int(after_dirty_count),
    "auditor_as_replay_artifact_path": None,
    "advisor_artifact_path": str(Path(manifest).resolve()),
    "source_advisor_artifact_path": str(Path(source_advisor_artifact).resolve()) if source_advisor_artifact else None,
    "optimizer_replay_receipt_path": str(Path(receipt).resolve()),
    "generated_patch_pack_path": str(Path(patch_dir).resolve()),
    "patch_metadata_path": str(Path(patch_metadata).resolve()) if Path(patch_metadata).exists() else None,
    "blocker_path": str(Path(blockers).resolve()) if Path(blockers).exists() else None,
    "apply_check_result_path": str(Path(validate_log).resolve()),
    "bounded_non_claims": bounded_non_claims,
}


def safe_target_from_text(text: str) -> str | None:
    values = []
    for match in re.finditer(r"`([^`]+)`", text):
        value = match.group(1).strip()
        if (
            value
            and not value.startswith("/")
            and not value.startswith("../")
            and "/../" not in value
            and ".git" not in value.split("/")
            and re.fullmatch(r"[A-Za-z0-9_./-]+(?:\.md|\.txt|/SKILL\.md)", value)
        ):
            values.append(value)
    if len(set(values)) == 1:
        return values[0]
    return None


def row_context(row: dict[str, Any]) -> dict[str, Any]:
    value = dict(context)
    target = row.get("target_file")
    if not isinstance(target, str) or not target:
        target = safe_target_from_text(
            " ".join(str(row.get(key, "")) for key in ("findings", "reason", "raw_row"))
        )
    if target:
        value["target_file"] = target
    return value


def enrich(path: Path, rows_key: str) -> None:
    if not path.exists():
        return
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"ERROR: cannot enrich invalid JSON artifact {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"ERROR: cannot enrich non-object JSON artifact {path}")
    payload["downstream_contract_reference"] = context["contract_reference"]
    payload["downstream_pilot_context"] = context
    rows = payload.get(rows_key)
    if isinstance(rows, list):
        for row in rows:
            if isinstance(row, dict):
                row["downstream_pilot_context"] = row_context(row)
    claims = payload.setdefault("bounded_non_claims", [])
    if isinstance(claims, list):
        for claim in bounded_non_claims:
            if claim not in claims:
                claims.append(claim)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


enrich(Path(patch_metadata), "patches")
enrich(Path(blockers), "blockers")
PY

UNCHANGED=false
if [ "$BEFORE_HEAD" = "$AFTER_HEAD" ] && [ "$BEFORE_STATUS" = "$AFTER_STATUS" ]; then
    UNCHANGED=true
fi

MATERIALIZERS=""
if grep -Eq '^\| FGR-01 \|' "$MANIFEST"; then
    MATERIALIZERS="FGR-01"
fi
if grep -Eq '^\| LR-01 \|' "$MANIFEST"; then
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

python3 - "$RECEIPT" "$SCORECARD" "$STATUS" "$REPO" "$MANIFEST" "$PATCH_DIR" "$BLOCKERS" "$GENERATE_LOG" "$VALIDATE_LOG" "$GENERATE_STATUS" "$VALIDATE_STATUS" "$PATCH_COUNT" "$PATCHES_VALID" "$EXPECT_PATCHES" "$BLOCKER_COUNT" "$EXPECT_BLOCKERS" "$BEFORE_HEAD" "$AFTER_HEAD" "$BEFORE_STATUS" "$AFTER_STATUS" "$UNCHANGED" "$SCRIPT_DIR" "$MATERIALIZERS" "$BEFORE_DIRTY_COUNT" "$AFTER_DIRTY_COUNT" "$TARGET_REPO_IDENTITY" "$PATCH_METADATA" "$ADVISOR_ABS" <<'PY'
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
    before_dirty_count,
    after_dirty_count,
    target_repo_identity,
    patch_metadata,
    source_advisor_artifact,
) = sys.argv[1:29]

script_dir_path = Path(script_dir)
materializer_list = [item for item in materializers.split(",") if item]
bounded_non_claims = [
    "This receipt does not apply patches.",
    "This receipt does not open downstream PRs or issues.",
    "This receipt does not mutate the target repo.",
    "This receipt does not install hooks or change target repo configuration.",
    "This receipt does not start a daemon, scheduler, queue, controller, retry loop, hidden registry, background sync, MCP server, watcher, cron job, service, or autopilot.",
    "This receipt does not perform automatic GitHub issue creation.",
    "This receipt does not claim the generated patch pack is safe to apply without explicit operator review and an explicit downstream write step outside this pilot.",
]
receipt_path = Path(receipt).resolve()
patch_dir_path = Path(patch_dir).resolve()
patch_metadata_path = Path(patch_metadata).resolve()
blockers_path = Path(blockers).resolve()
validate_log_path = Path(validate_log).resolve()
generate_log_path = Path(generate_log).resolve()
scorecard_path = Path(scorecard).resolve()
manifest_path = Path(manifest).resolve()
repo_path = Path(repo).resolve()
downstream_contract_reference = "https://github.com/briancl2/repo-agent-core/blob/main/docs/downstream-read-only-recovery-runtime-pilot-contract.md"
pilot_receipt = {
    "artifact": "DOWNSTREAM_READ_ONLY_RECOVERY_RUNTIME_PILOT_RECEIPT",
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "target_repo_identity": target_repo_identity,
    "target_path_or_name": str(repo_path),
    "target_git_head_before": before_head,
    "target_git_head_after": after_head,
    "target_dirty_count_before": int(before_dirty_count),
    "target_dirty_count_after": int(after_dirty_count),
    "auditor_as_replay_artifact_path": None,
    "advisor_artifact_path": str(manifest_path),
    "source_advisor_artifact_path": str(Path(source_advisor_artifact).resolve()) if source_advisor_artifact else None,
    "optimizer_replay_receipt_path": str(receipt_path),
    "generated_patch_pack_path": str(patch_dir_path),
    "patch_metadata_path": str(patch_metadata_path) if patch_metadata_path.exists() else None,
    "blocker_path": str(blockers_path) if blockers_path.exists() else None,
    "apply_check_result_path": str(validate_log_path),
    "bounded_non_claims": bounded_non_claims,
}
payload = {
    "schema_version": "1.0.0",
    "artifact": "RECOVERY_RUNTIME_REPLAY_RECEIPT",
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": status,
    "target_repo": str(repo_path),
    "target_repo_identity": target_repo_identity,
    "target_path_or_name": str(repo_path),
    "target_read_only": True,
    "materializers": materializer_list,
    "manifest_path": str(manifest_path),
    "advisor_artifact_path": str(manifest_path),
    "source_advisor_artifact_path": str(Path(source_advisor_artifact).resolve()) if source_advisor_artifact else None,
    "patch_dir": str(patch_dir_path),
    "generated_patch_pack_path": str(patch_dir_path),
    "patch_metadata_path": str(patch_metadata_path) if patch_metadata_path.exists() else None,
    "blocker_path": str(blockers_path) if blockers_path.exists() else None,
    "apply_check_result_path": str(validate_log_path),
    "patchability_blockers_path": str(blockers_path) if blockers_path.exists() else None,
    "receipt_path": str(receipt_path),
    "optimizer_replay_receipt_path": str(receipt_path),
    "optimization_scorecard_path": str(scorecard_path),
    "expected_patches": int(expected_patches),
    "patches_generated": int(patch_count),
    "patches_valid": int(patches_valid),
    "expected_blockers": int(expected_blockers),
    "blocker_count": int(blocker_count),
    "target_git_state_unchanged": unchanged == "true",
    "target_git_head_before": before_head,
    "target_git_head_after": after_head,
    "target_dirty_count_before": int(before_dirty_count),
    "target_dirty_count_after": int(after_dirty_count),
    "before_git_head": before_head,
    "after_git_head": after_head,
    "before_git_status": before_status,
    "after_git_status": after_status,
    "commands": [
        {
            "command": f"bash {script_dir_path / 'generate-patches.sh'} {repo} {manifest} {Path(patch_dir).parent}",
            "exit_code": int(generate_status),
            "log_path": str(generate_log_path),
        },
        {
            "command": f"bash {script_dir_path / 'validate-patches.sh'} {repo} {patch_dir}",
            "exit_code": int(validate_status),
            "log_path": str(validate_log_path),
        },
    ],
    "downstream_contract_reference": downstream_contract_reference,
    "downstream_pilot_receipt": pilot_receipt,
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
        "target": str(repo_path),
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

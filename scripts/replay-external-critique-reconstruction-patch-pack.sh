#!/usr/bin/env bash
# replay-external-critique-reconstruction-patch-pack.sh - Bounded read-only AS-08 patch-pack replay.
#
# Usage:
#   bash scripts/replay-external-critique-reconstruction-patch-pack.sh <repo_path> <output_dir> \
#     --from-advisor <OPPORTUNITIES.json> [--expect-patches <count>] [--expect-blockers <count>]
#
# Builds AS-08 optimization manifest rows from repo-upgrade-advisor
# external_critique_reconstruction_plan fields, generates a patch pack,
# validates it with git apply --check, and records target git state before/after.
# It never applies patches or mutates the target repository.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: replay-external-critique-reconstruction-patch-pack.sh <repo_path> <output_dir> --from-advisor <OPPORTUNITIES.json> [options]

Options:
  --from-advisor <json>    Read repo-upgrade-advisor OPPORTUNITIES.json AS-08 rows.
  --expect-patches <n>     Required generated patch count. Defaults to 1.
  --expect-blockers <n>    Required PATCHABILITY_BLOCKERS blocker_count. Defaults to the actual blocker count.
  -h, --help               Show this help.

The output directory must be outside the target repository. This replay writes
only output artifacts; it does not apply patches or mutate the target repository.
EOF
}

if [ $# -lt 2 ]; then
    usage
    exit 2
fi

REPO="${1:?repo path required}"
OUTPUT_DIR="${2:?output dir required}"
shift 2

FROM_ADVISOR=""
EXPECT_PATCHES=""
EXPECT_BLOCKERS=""

while [ $# -gt 0 ]; do
    case "$1" in
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

if [ -z "$FROM_ADVISOR" ]; then
    echo "ERROR: --from-advisor is required" >&2
    exit 2
fi

python3 - "$EXPECT_BLOCKERS" "$EXPECT_PATCHES" <<'PY'
import re
import sys

for label, value in (("--expect-blockers", sys.argv[1]), ("--expect-patches", sys.argv[2])):
    if value == "":
        continue
    if not re.fullmatch(r"[0-9]+", value):
        raise SystemExit(f"ERROR: {label} must be a non-negative integer")
PY

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: target path must be inside a git checkout: $REPO" >&2
    exit 1
fi
if [ ! -f "$FROM_ADVISOR" ]; then
    echo "ERROR: --from-advisor file does not exist: $FROM_ADVISOR" >&2
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
ADVISOR_ABS="$(python3 - "$FROM_ADVISOR" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=True))
PY
)"

case "$OUTPUT_ABS" in
    "$REPO_ABS"|"$REPO_ABS"/*)
        echo "ERROR: output_dir must be outside the target repository: $OUTPUT_DIR" >&2
        exit 1
        ;;
esac

BEFORE_HEAD="$(git -C "$REPO" rev-parse HEAD)"
BEFORE_STATUS="$(git -C "$REPO" status --short)"
BEFORE_DIRTY_COUNT="$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$OUTPUT_ABS/OPTIMIZATION_PLAN.md"
PATCH_DIR="$OUTPUT_ABS/PATCH_PACK"
PATCH_METADATA="$OUTPUT_ABS/PATCH_PACK_METADATA.json"
BLOCKERS="$OUTPUT_ABS/PATCHABILITY_BLOCKERS.json"
RECEIPT="$OUTPUT_ABS/EXTERNAL_CRITIQUE_RECONSTRUCTION_REPLAY_RECEIPT.json"
SCORECARD="$OUTPUT_ABS/OPTIMIZATION_SCORECARD.json"
GENERATE_LOG="$OUTPUT_ABS/external-critique-reconstruction-generate-patches.log"
VALIDATE_LOG="$OUTPUT_ABS/external-critique-reconstruction-validate-patches.log"

mkdir -p "$OUTPUT_ABS" "$PATCH_DIR"
find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' -delete
rm -f "$BLOCKERS" "$PATCH_METADATA"

python3 - "$MANIFEST" "$ADVISOR_ABS" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

manifest = Path(sys.argv[1])
advisor_path = Path(sys.argv[2])
payload = json.loads(advisor_path.read_text(encoding="utf-8"))


def scrub_text(value: Any, fallback: str = "unspecified") -> str:
    if value is None:
        return fallback
    text = re.sub(r"\s+", " ", str(value).strip()).replace("|", "/")
    text = re.sub(r"https?://\S+", "[redacted-url]", text)
    text = re.sub(r"\b\d[\d,._-]{3,}\b", "[redacted-number]", text)
    return text[:260] if text else fallback


def scrub_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {scrub_text(key): scrub_value(inner) for key, inner in value.items()}
    if isinstance(value, list):
        return [scrub_value(inner) for inner in value]
    if isinstance(value, str):
        return scrub_text(value)
    return value


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def safe_summary(target: str) -> str:
    return (
        f"Adds target-local AS-08 external critique reconstruction guidance to {scrub_text(target)}; "
        "includes before/after detector evidence, authority refs, local principles, validation commands, "
        "and redaction boundaries without retaining raw private evidence."
    )


lines = [
    "# Optimization Plan",
    "",
    "## Patch Manifest",
    "",
    "| Patch # | Findings | Files touched |",
    "|---|---|---:|",
]

recommendations = payload.get("recommendations")
if isinstance(recommendations, list):
    for idx, rec in enumerate(recommendations, start=1):
        if not isinstance(rec, dict):
            continue
        if rec.get("anti_pattern_family") != "external_critique_reconstruction_gap":
            continue
        plan = rec.get("external_critique_reconstruction_plan")
        if not isinstance(plan, dict):
            continue
        exact_files = plan.get("exact_files_to_change")
        if not isinstance(exact_files, list) or not exact_files:
            exact_files = rec.get("surfaces") if isinstance(rec.get("surfaces"), list) else []
        sanitized_plan = scrub_value(plan)
        metadata = {
            "recommendation_id": scrub_text(rec.get("id") or f"AS08-REC-{idx:02d}"),
            "title": scrub_text(rec.get("title")),
            "anti_pattern_family": "external_critique_reconstruction_gap",
            "owner_surface": scrub_text(rec.get("owner_surface")),
            "fix_summary": scrub_text(rec.get("fix_summary")),
            "bounded_non_claim": scrub_text(rec.get("bounded_non_claim")),
            "research_standard_guardrail": scrub_text(rec.get("research_standard_guardrail")),
            "privacy_safe_patch_summary": safe_summary(" / ".join(scrub_text(item) for item in exact_files)),
            "reconstruction_plan": sanitized_plan,
        }
        scan_context = rec.get("scan_context") if isinstance(rec.get("scan_context"), dict) else {
            "scanner": "repo-upgrade-advisor",
            "source": "--from-advisor",
            "source_signature": "AS-08",
            "scan_limited": True,
        }
        evidence_context = rec.get("evidence_context") if isinstance(rec.get("evidence_context"), dict) else None
        for target in exact_files:
            target_cell = scrub_text(target)
            findings = (
                f"external critique reconstruction for `{target_cell}` "
                f"scan_context={compact_json(scrub_value(scan_context))}"
            )
            if evidence_context:
                findings += f" evidence_context={compact_json(scrub_value(evidence_context))}"
            findings += f" advisor_metadata={compact_json(metadata)}"
            lines.append(f"| AS-08 | {findings} | 1 |")

manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

ROW_COUNT="$(grep -Ec '^\| AS-08 \|' "$MANIFEST" || true)"

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
if [ -s "$BLOCKERS" ]; then
    BLOCKER_COUNT="$(python3 - "$BLOCKERS" <<'PY'
import json
import sys

print(int(json.load(open(sys.argv[1], encoding="utf-8")).get("blocker_count", 0)))
PY
)"
fi

if [ -z "$EXPECT_PATCHES" ]; then
    EXPECT_PATCHES=1
fi
if [ -z "$EXPECT_BLOCKERS" ]; then
    EXPECT_BLOCKERS="$BLOCKER_COUNT"
fi

UNCHANGED=false
if [ "$BEFORE_HEAD" = "$AFTER_HEAD" ] && [ "$BEFORE_STATUS" = "$AFTER_STATUS" ]; then
    UNCHANGED=true
fi

STATUS="failed"
if [ "$ROW_COUNT" -gt 0 ] \
    && [ "$GENERATE_STATUS" -eq 0 ] \
    && [ "$VALIDATE_STATUS" -eq 0 ] \
    && [ "$PATCH_COUNT" -eq "$EXPECT_PATCHES" ] \
    && [ "$PATCHES_VALID" -eq "$PATCH_COUNT" ] \
    && [ "$BLOCKER_COUNT" -eq "$EXPECT_BLOCKERS" ] \
    && [ "$UNCHANGED" = "true" ]; then
    STATUS="completed"
fi

python3 - "$RECEIPT" "$SCORECARD" "$STATUS" "$REPO" "$MANIFEST" "$PATCH_DIR" "$PATCH_METADATA" "$BLOCKERS" "$GENERATE_LOG" "$VALIDATE_LOG" "$GENERATE_STATUS" "$VALIDATE_STATUS" "$PATCH_COUNT" "$PATCHES_VALID" "$EXPECT_PATCHES" "$BLOCKER_COUNT" "$EXPECT_BLOCKERS" "$ROW_COUNT" "$BEFORE_HEAD" "$AFTER_HEAD" "$BEFORE_STATUS" "$AFTER_STATUS" "$BEFORE_DIRTY_COUNT" "$AFTER_DIRTY_COUNT" "$UNCHANGED" "$SCRIPT_DIR" "$ADVISOR_ABS" <<'PY'
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
    patch_metadata,
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
    row_count,
    before_head,
    after_head,
    before_status,
    after_status,
    before_dirty_count,
    after_dirty_count,
    unchanged,
    script_dir,
    advisor_abs,
) = sys.argv[1:28]

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
script_dir_path = Path(script_dir)
patch_dir_path = Path(patch_dir).resolve()
patch_count_int = int(patch_count)
patches_valid_int = int(patches_valid)
blocker_count_int = int(blocker_count)
target_git_state_unchanged = unchanged == "true"
consumed_fields = [
    "recommendations[].anti_pattern_family",
    "recommendations[].external_critique_reconstruction_plan.plan_type",
    "recommendations[].external_critique_reconstruction_plan.detected_current_mechanism_version",
    "recommendations[].external_critique_reconstruction_plan.active_evidence_classes",
    "recommendations[].external_critique_reconstruction_plan.target_repo_authority_refs",
    "recommendations[].external_critique_reconstruction_plan.local_principles_to_preserve",
    "recommendations[].external_critique_reconstruction_plan.portable_invariants",
    "recommendations[].external_critique_reconstruction_plan.bma_terms_to_translate_or_remove",
    "recommendations[].external_critique_reconstruction_plan.exact_files_to_change",
    "recommendations[].external_critique_reconstruction_plan.minimal_wording_or_code_changes",
    "recommendations[].external_critique_reconstruction_plan.tests_or_validation_commands",
    "recommendations[].external_critique_reconstruction_plan.privacy_redaction_notes",
    "recommendations[].external_critique_reconstruction_plan.implementation_need",
    "recommendations[].external_critique_reconstruction_plan.owner_routing",
]
summary = (
    "AS-08 replay converts repo-upgrade-advisor external_critique_reconstruction_plan fields into "
    "target-local advisory patch recipes, then proves the generated patches with git apply --check "
    "without applying them."
)
bounded_non_claims = [
    "This receipt does not apply patches.",
    "This receipt does not mutate the target repo.",
    "This receipt does not create downstream issues or PRs.",
    "This receipt does not authorize live external critique probes.",
    "This receipt does not start a controller, scheduler, queue, daemon, dashboard, registry, retry loop, central service, automatic issue/PR system, or background memory.",
    "Generated patches remain advisory until a target owner reviews and applies them through a separate owner issue/PR.",
]
controlled_apply = {
    "eligible": status == "completed" and patch_count_int > 0 and patches_valid_int == patch_count_int and blocker_count_int == 0 and target_git_state_unchanged,
    "reason": (
        "generated_patch_pack_apply_check_clean"
        if patches_valid_int == patch_count_int and patch_count_int > 0 and blocker_count_int == 0
        else "apply_check_clean_but_blocked_rows_remain"
        if patches_valid_int == patch_count_int and patch_count_int > 0
        else "no_apply_check_clean_patch_pack"
    ),
    "generated_patch_count": patch_count_int,
    "valid_patch_count": patches_valid_int,
    "blocker_count": blocker_count_int,
    "mutation_boundary": "separate downstream owner PR only",
}
receipt_payload = {
    "schema_version": "1.0.0",
    "artifact": "EXTERNAL_CRITIQUE_RECONSTRUCTION_REPLAY_RECEIPT",
    "generated_at": now,
    "status": status,
    "target_repo": str(Path(repo).resolve()),
    "target_read_only": True,
    "source_advisor_artifact_path": str(Path(advisor_abs).resolve()),
    "manifest_path": str(Path(manifest).resolve()),
    "patch_dir": str(patch_dir_path),
    "patch_metadata_path": str(Path(patch_metadata).resolve()) if Path(patch_metadata).exists() else None,
    "blocker_path": str(Path(blockers).resolve()) if Path(blockers).exists() else None,
    "receipt_path": str(Path(receipt).resolve()),
    "patches_generated": patch_count_int,
    "patches_valid": patches_valid_int,
    "expected_patches": int(expected_patches),
    "blocker_count": blocker_count_int,
    "expected_blockers": int(expected_blockers),
    "manifest_as08_rows": int(row_count),
    "target_git_state_unchanged": target_git_state_unchanged,
    "before_git_head": before_head,
    "after_git_head": after_head,
    "before_git_status": before_status,
    "after_git_status": after_status,
    "before_dirty_count": int(before_dirty_count),
    "after_dirty_count": int(after_dirty_count),
    "arc3_consumed_fields": consumed_fields,
    "patch_recipe_summary": summary,
    "controlled_downstream_apply": controlled_apply,
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
    "schema_version": "1.0.0",
    "artifact": "OPTIMIZATION_SCORECARD",
    "generated_at": now,
    "patches_generated": patch_count_int,
    "patches_valid": patches_valid_int,
    "meta": {
        "patch_status": "patches_present" if patch_count_int > 0 else "fail_closed_patchability_blocked",
        "materializer": "AS-08",
        "source": "repo-upgrade-advisor external_critique_reconstruction_plan",
    },
    "external_critique_reconstruction": {
        "status": status,
        "arc3_consumed_fields": consumed_fields,
        "patch_recipe_summary": summary,
        "controlled_downstream_apply": controlled_apply,
    },
    "bounded_non_claims": bounded_non_claims,
}
Path(receipt).write_text(json.dumps(receipt_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
Path(scorecard).write_text(json.dumps(scorecard_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [ "$STATUS" != "completed" ]; then
    echo "ERROR: AS-08 external critique reconstruction replay failed; receipt: $RECEIPT" >&2
    exit 1
fi

echo "AS-08 external critique reconstruction replay completed"
echo "  manifest: $MANIFEST"
echo "  patch_dir: $PATCH_DIR"
echo "  receipt: $RECEIPT"

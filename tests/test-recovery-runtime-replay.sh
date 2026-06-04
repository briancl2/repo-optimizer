#!/usr/bin/env bash
# test-recovery-runtime-replay.sh — Verify bounded recovery-runtime replay patch packs.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="$(mktemp -d)"
OUTPUT_DIR="$(mktemp -d)"
ADVISOR_OUTPUT="$(mktemp -d)"
ADVISOR_BLOCKED_OUTPUT="$(mktemp -d)"
ADVISOR_ONLY_BLOCKER_OUTPUT="$(mktemp -d)"
ADVISOR_NOOP_OUTPUT="$(mktemp -d)"
ADVISOR_EMPTY_OUTPUT="$(mktemp -d)"
ADVISOR_MALFORMED_NOOP_OUTPUT="$(mktemp -d)"
ADVISOR_MIXED_OUTPUT="$(mktemp -d)"
MAKE_MIXED_ADVISOR_OUTPUT="$(mktemp -d)"
MAKE_ADVISOR_OUTPUT="$(mktemp -d)"
FORBIDDEN_APPLY_OUTPUT="$(mktemp -d)"
FORBIDDEN_DOC_APPLY_OUTPUT="$(mktemp -d)"
HIDDEN_PREFIX_APPLY_OUTPUT="$(mktemp -d)"
BLOCKED_OUTPUT="$(mktemp -d)"
BLOCKER_ONLY_OUTPUT="$(mktemp -d)"
LINK_PARENT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$OUTPUT_DIR" "$ADVISOR_OUTPUT" "$ADVISOR_BLOCKED_OUTPUT" "$ADVISOR_ONLY_BLOCKER_OUTPUT" "$ADVISOR_NOOP_OUTPUT" "$ADVISOR_EMPTY_OUTPUT" "$ADVISOR_MALFORMED_NOOP_OUTPUT" "$ADVISOR_MIXED_OUTPUT" "$MAKE_MIXED_ADVISOR_OUTPUT" "$MAKE_ADVISOR_OUTPUT" "$FORBIDDEN_APPLY_OUTPUT" "$FORBIDDEN_DOC_APPLY_OUTPUT" "$HIDDEN_PREFIX_APPLY_OUTPUT" "$BLOCKED_OUTPUT" "$BLOCKER_ONLY_OUTPUT" "$LINK_PARENT"' EXIT

mkdir -p "$TARGET_REPO/docs"
mkdir -p "$TARGET_REPO/data"
mkdir -p "$TARGET_REPO/.github/instructions"
cat > "$TARGET_REPO/docs/foreground-guide.md" <<'EOF'
# Foreground Guide

Existing foreground command guidance.
EOF
cat > "$TARGET_REPO/.github/instructions/recovery.md" <<'EOF'
# Recovery Instructions

Fixture instruction guidance.
EOF
cat > "$TARGET_REPO/data/holdings.md" <<'EOF'
# Holdings

Fixture portfolio data.
EOF
cat > "$TARGET_REPO/docs/advisor-foreground.md" <<'EOF'
# Advisor Foreground

Advisor foreground guidance target.
EOF
cat > "$TARGET_REPO/docs/learning-recovery.md" <<'EOF'
# Learning Recovery

Existing learning capture guidance.
EOF
cat > "$TARGET_REPO/docs/advisor-learning.md" <<'EOF'
# Advisor Learning

Advisor learning recovery target.
EOF
cat > "$TARGET_REPO/docs/secrets.md" <<'EOF'
# Secrets

Fixture sensitive documentation.
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
    git add docs data .github
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
PATCH_METADATA="$OUTPUT_DIR/PATCH_PACK_METADATA.json"
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

ADVISOR_JSON="$ADVISOR_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_JSON" <<'EOF'
{
  "target": "advisor-fixture",
  "recommendations": [
    {
      "id": "REC-01",
      "title": "Add foreground failure guidance",
      "patch_materializer": "FGR-01",
      "patch_target_file": "docs/advisor-foreground.md",
      "scan_context": {"scanner": "repo-upgrade-advisor", "scan_limited": true, "sample": "as-33"},
      "evidence_context": {"primary_class": "active_doc", "source": "AS-33"},
      "anti_pattern_family": "foreground_failure_guidance_gap",
      "evidence_refs": ["AS-33", "receipt:fgr"],
      "owner_surface": "BMA #417",
      "first_deliverable": "Patch bridge row",
      "downstream_pilot_receipt": {"artifact": "advisor-pilot", "id": "pilot-fgr"},
      "downstream_pilot_context": {"artifact": "advisor-context", "id": "context-fgr"}
    },
    {
      "id": "REC-02",
      "title": "Add learning recovery guidance",
      "patch_materializer": "LR-01",
      "patch_target_file": "docs/advisor-learning.md",
      "scan_context": {"scanner": "repo-upgrade-advisor", "scan_limited": true, "sample": "as-32"},
      "evidence_context": {"primary_class": "active_doc", "source": "AS-32"},
      "anti_pattern_family": "unanchored_self_learning_claim",
      "evidence_refs": ["AS-32"],
      "owner_surface": "BMA #417",
      "first_deliverable": "Learning bridge row"
    }
  ],
  "meta": {"timestamp": "2026-06-02T00:00:00Z", "advisor_version": "test"}
}
EOF
if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$ADVISOR_OUTPUT" \
    --from-advisor "$ADVISOR_JSON" >/dev/null; then
    echo "  ✓ recovery-runtime replay completed from advisor FGR-01/LR-01 rows without explicit targets"
else
    echo "  ✗ recovery-runtime replay failed from advisor safe rows"
    find "$ADVISOR_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_OUTPUT/recovery-runtime-generate-patches.log" ] && cat "$ADVISOR_OUTPUT/recovery-runtime-generate-patches.log"
    [ -f "$ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$ADVISOR_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && [ -s "$ADVISOR_OUTPUT/PATCH_PACK/FGR-01-foreground-failure-guidance-recovery.patch" ] \
    && [ -s "$ADVISOR_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] \
    && python3 - "$ADVISOR_OUTPUT/OPTIMIZATION_PLAN.md" "$ADVISOR_OUTPUT/PATCH_PACK_METADATA.json" "$ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

manifest = Path(sys.argv[1]).read_text()
metadata = json.loads(Path(sys.argv[2]).read_text())
receipt = json.loads(Path(sys.argv[3]).read_text())
target = Path(sys.argv[4])
assert "repo-upgrade-advisor" in manifest
assert "evidence_context={\"primary_class\":\"active_doc\"" in manifest
assert "anti_pattern_family" in manifest
rows = {row["target_file"]: row for row in metadata["patches"]}
fgr = rows["docs/advisor-foreground.md"]
lr = rows["docs/advisor-learning.md"]
assert fgr["row_id"] == "FGR-01"
assert lr["row_id"] == "LR-01"
assert fgr["scan_context"]["sample"] == "as-33"
assert lr["scan_context"]["sample"] == "as-32"
assert fgr["evidence_context"]["primary_class"] == "active_doc"
assert lr["evidence_context"]["primary_class"] == "active_doc"
assert fgr["advisor_metadata"]["anti_pattern_family"] == "foreground_failure_guidance_gap"
assert fgr["advisor_metadata"]["evidence_refs"] == ["AS-33", "receipt:fgr"]
assert fgr["advisor_metadata"]["owner_surface"] == "BMA #417"
assert fgr["advisor_metadata"]["first_deliverable"] == "Patch bridge row"
assert fgr["advisor_metadata"]["downstream_pilot_receipt"]["id"] == "pilot-fgr"
assert fgr["advisor_metadata"]["downstream_pilot_context"]["id"] == "context-fgr"
assert receipt["advisor_artifact_path"] == str(Path(sys.argv[1]).resolve())
assert receipt["source_advisor_artifact_path"]
assert receipt["materializers"] == ["FGR-01", "LR-01"]
assert receipt["target_git_state_unchanged"] is True
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ advisor-derived manifest preserves metadata and target cleanliness"
else
    echo "  ✗ advisor-derived metadata or cleanliness proof missing"
    [ -f "$ADVISOR_OUTPUT/OPTIMIZATION_PLAN.md" ] && cat "$ADVISOR_OUTPUT/OPTIMIZATION_PLAN.md"
    [ -f "$ADVISOR_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$ADVISOR_OUTPUT/PATCH_PACK_METADATA.json"
    [ -f "$ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

ADVISOR_NOOP_JSON="$ADVISOR_NOOP_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_NOOP_JSON" <<'EOF'
{
  "schema_version": "advisor-opportunities-v1",
  "target": {"name": "clean-noop-fixture"},
  "calibration": {
    "as_work_management_replay_noop": {
      "status": "clean_replay_noop",
      "source_artifact": "AS_WORK_MANAGEMENT_REPLAY",
      "source_report": "/tmp/as-work-management-replay.json",
      "signature_scope": ["AS-20", "AS-33"],
      "finding_count": 2,
      "fired_count": 0,
      "reason": "AS_WORK_MANAGEMENT_REPLAY fired_count is zero."
    }
  },
  "recommendations": [],
  "demoted": [
    {
      "id": "DEMOTED-01",
      "title": "Suppressed runner observation",
      "patch_materializer": "FGR-01",
      "patch_target_file": "docs/advisor-foreground.md",
      "reason": "Suppressed because AS_WORK_MANAGEMENT_REPLAY fired_count=0."
    }
  ],
  "meta": {"timestamp": "2026-06-03T00:00:00Z", "advisor_version": "test"}
}
EOF
if make -C "$OPT_DIR" recovery-runtime-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$ADVISOR_NOOP_OUTPUT/replay" \
    FROM_ADVISOR="$ADVISOR_NOOP_JSON" >/dev/null; then
    echo "  ✓ clean advisor recovery-runtime no-op succeeds with zero patches"
else
    echo "  ✗ clean advisor recovery-runtime no-op failed"
    find "$ADVISOR_NOOP_OUTPUT/replay" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    [ -f "$ADVISOR_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json"
    exit 1
fi

if [ -s "$ADVISOR_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] \
    && [ -d "$ADVISOR_NOOP_OUTPUT/replay/PATCH_PACK" ] \
    && [ ! -e "$ADVISOR_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$ADVISOR_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$ADVISOR_NOOP_OUTPUT/replay/OPTIMIZATION_SCORECARD.json" "$ADVISOR_NOOP_OUTPUT/replay/OPTIMIZATION_PLAN.md" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
scorecard = json.loads(Path(sys.argv[2]).read_text())
manifest = Path(sys.argv[3]).read_text()
target = Path(sys.argv[4])
assert receipt["status"] == "completed"
assert receipt["clean_advisor_noop"] is True
assert receipt["patches_generated"] == 0
assert receipt["patches_valid"] == 0
assert receipt["expected_patches"] == 0
assert receipt["blocker_count"] == 0
assert receipt["expected_blockers"] == 0
assert receipt["blocker_path"] is None
assert receipt["target_git_state_unchanged"] is True
assert receipt["source_advisor_artifact_path"].endswith("OPPORTUNITIES.json")
assert all(command["skipped"] is True for command in receipt["commands"])
assert {command["skip_reason"] for command in receipt["commands"]} == {"clean_advisor_recovery_runtime_noop"}
readiness = receipt["controlled_downstream_apply"]
assert readiness["eligible"] is False
assert readiness["reason"] == "clean_advisor_noop_no_generated_patches"
assert readiness["generated_patch_count"] == 0
assert readiness["valid_patch_count"] == 0
assert readiness["blocker_count"] == 0
assert readiness["mutation_boundary"] == "separate downstream PR only"
assert receipt["downstream_pilot_receipt"]["controlled_downstream_apply"] == readiness
assert scorecard["meta"]["patch_status"] == "clean_advisor_noop"
assert scorecard["controlled_downstream_apply"] == readiness
assert "repo-optimizer:clean-advisor-recovery-runtime-noop" in manifest
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ clean advisor no-op receipt records zero-output success"
else
    echo "  ✗ clean advisor no-op receipt did not preserve expected proof"
    [ -f "$ADVISOR_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    [ -f "$ADVISOR_NOOP_OUTPUT/replay/OPTIMIZATION_SCORECARD.json" ] && cat "$ADVISOR_NOOP_OUTPUT/replay/OPTIMIZATION_SCORECARD.json"
    exit 1
fi

if make -C "$OPT_DIR" validate OUTPUT_DIR="$ADVISOR_NOOP_OUTPUT/replay" >/dev/null; then
    echo "  ✓ clean advisor no-op replay output passes make validate"
else
    echo "  ✗ clean advisor no-op replay output failed make validate"
    find "$ADVISOR_NOOP_OUTPUT/replay" -maxdepth 3 -type f -print
    exit 1
fi

mkdir -p "$ADVISOR_NOOP_OUTPUT/replay/PATCH_PACK"
printf '%s\n' 'stale patch' > "$ADVISOR_NOOP_OUTPUT/replay/PATCH_PACK/stale.patch"
printf '%s\n' '{"stale": true}' > "$ADVISOR_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json"
printf '%s\n' '{"stale": true}' > "$ADVISOR_NOOP_OUTPUT/replay/PATCH_PACK_METADATA.json"
if make -C "$OPT_DIR" recovery-runtime-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$ADVISOR_NOOP_OUTPUT/replay" \
    FROM_ADVISOR="$ADVISOR_NOOP_JSON" >/dev/null \
    && [ ! -e "$ADVISOR_NOOP_OUTPUT/replay/PATCH_PACK/stale.patch" ] \
    && [ ! -e "$ADVISOR_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] \
    && [ ! -e "$ADVISOR_NOOP_OUTPUT/replay/PATCH_PACK_METADATA.json" ]; then
    echo "  ✓ clean advisor no-op clears stale patch-pack artifacts on reused output dirs"
else
    echo "  ✗ clean advisor no-op left stale patch-pack artifacts behind"
    find "$ADVISOR_NOOP_OUTPUT/replay" -maxdepth 3 -type f -print
    exit 1
fi

ADVISOR_EMPTY_JSON="$ADVISOR_EMPTY_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_EMPTY_JSON" <<'EOF'
{
  "target": "empty-untrusted-fixture",
  "recommendations": [],
  "meta": {"timestamp": "2026-06-03T00:00:00Z", "advisor_version": "test"}
}
EOF
if make -C "$OPT_DIR" recovery-runtime-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$ADVISOR_EMPTY_OUTPUT/replay" \
    FROM_ADVISOR="$ADVISOR_EMPTY_JSON" >/dev/null; then
    echo "  ✗ untrusted empty advisor recommendations succeeded as a no-op"
    find "$ADVISOR_EMPTY_OUTPUT/replay" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_EMPTY_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_EMPTY_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
else
    echo "  ✓ untrusted empty advisor recommendations still fail closed"
fi

if [ -s "$ADVISOR_EMPTY_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$ADVISOR_EMPTY_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["blocker_count"] == 1
assert payload["blockers"][0]["blocker_code"] == "manifest_rows_not_found"
PY
then
    echo "  ✓ untrusted empty advisor replay records manifest row blocker"
else
    echo "  ✗ untrusted empty advisor replay did not preserve manifest row blocker"
    [ -f "$ADVISOR_EMPTY_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_EMPTY_OUTPUT/replay/PATCHABILITY_BLOCKERS.json"
    exit 1
fi

ADVISOR_MALFORMED_NOOP_JSON="$ADVISOR_MALFORMED_NOOP_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_MALFORMED_NOOP_JSON" <<'EOF'
{
  "target": "malformed-noop-fixture",
  "calibration": {
    "as_work_management_replay_noop": {
      "status": "clean_replay_noop",
      "source_artifact": "AS_WORK_MANAGEMENT_REPLAY",
      "finding_count": "2",
      "fired_count": "0"
    }
  },
  "recommendations": [],
  "meta": {"timestamp": "2026-06-03T00:00:00Z", "advisor_version": "test"}
}
EOF
if make -C "$OPT_DIR" recovery-runtime-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$ADVISOR_MALFORMED_NOOP_OUTPUT/replay" \
    FROM_ADVISOR="$ADVISOR_MALFORMED_NOOP_JSON" >/dev/null; then
    echo "  ✗ malformed clean-noop calibration succeeded as a no-op"
    find "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
else
    echo "  ✓ malformed clean-noop calibration fails closed without crashing"
fi

if [ -s "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] \
    && ! grep -Fq 'repo-optimizer:clean-advisor-recovery-runtime-noop' "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/OPTIMIZATION_PLAN.md"; then
    echo "  ✓ malformed clean-noop calibration does not emit no-op proof marker"
else
    echo "  ✗ malformed clean-noop calibration emitted no-op proof or omitted blocker"
    [ -f "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/OPTIMIZATION_PLAN.md" ] && cat "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/OPTIMIZATION_PLAN.md"
    [ -f "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_MALFORMED_NOOP_OUTPUT/replay/PATCHABILITY_BLOCKERS.json"
    exit 1
fi

ADVISOR_BAD_JSON="$ADVISOR_BLOCKED_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_BAD_JSON" <<'EOF'
{
  "target": "advisor-fixture",
  "recommendations": [
    {"id": "REC-10", "title": "Unsupported materializer", "patch_materializer": "CR-01", "patch_target_file": "docs/advisor-foreground.md"},
    {"id": "REC-11", "title": "Unsafe materializer target", "patch_materializer": "FGR-01", "patch_target_file": "../escape.md"},
    "REC-12 missing recommendation object",
    {"id": "REC-13", "title": "Ambiguous broad row", "patch_materializer": "LR-01", "patch_target_file": ["docs/advisor-learning.md", "docs/learning-recovery.md"]}
  ],
  "meta": {"timestamp": "2026-06-02T00:00:00Z", "advisor_version": "test"}
}
EOF
if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$ADVISOR_BLOCKED_OUTPUT" \
    --from-advisor "$ADVISOR_BAD_JSON" \
    --expect-patches 0 \
    --expect-blockers 4 >/dev/null; then
    echo "  ✓ advisor invalid rows are routed to PATCHABILITY_BLOCKERS.json"
else
    echo "  ✗ advisor invalid rows were not routed to blockers as expected"
    find "$ADVISOR_BLOCKED_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$ADVISOR_BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_BLOCKED_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$ADVISOR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$ADVISOR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["blocker_count"] == 4
codes = {row["blocker_code"] for row in payload["blockers"]}
assert "advisor_unsupported_patch_materializer" in codes
assert "advisor_unsafe_patch_target_file" in codes
assert "advisor_missing_recommendation_object" in codes
assert "advisor_ambiguous_broad_row" in codes
assert all(row.get("advisor_row") for row in payload["blockers"])
PY
then
    echo "  ✓ advisor blockers preserve invalid row evidence"
else
    echo "  ✗ advisor blocker artifact missing invalid row evidence"
    [ -f "$ADVISOR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    exit 1
fi

ADVISOR_ONLY_BLOCKER_JSON="$ADVISOR_ONLY_BLOCKER_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_ONLY_BLOCKER_JSON" <<'EOF'
{
  "target": "advisor-only-blocker-fixture",
  "recommendations": [
    {
      "id": "REC-ONLY-BLOCKER-01",
      "title": "Unsupported recommendation without patch materializer",
      "anti_pattern_family": "reciprocal_proving_ground_gap",
      "owner_surface": "docs/CODE_REVIEW_GUIDE.md",
      "first_deliverable": "Open owner issue"
    }
  ],
  "meta": {"timestamp": "2026-06-03T00:00:00Z", "advisor_version": "test"}
}
EOF
if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$ADVISOR_ONLY_BLOCKER_OUTPUT" \
    --from-advisor "$ADVISOR_ONLY_BLOCKER_JSON" >/dev/null; then
    echo "  ✓ advisor non-bridge rows replay as clean zero-patch no-op"
else
    echo "  ✗ advisor non-bridge rows did not replay as clean zero-patch no-op"
    find "$ADVISOR_ONLY_BLOCKER_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_ONLY_BLOCKER_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_ONLY_BLOCKER_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi
if [ ! -e "$ADVISOR_ONLY_BLOCKER_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$ADVISOR_ONLY_BLOCKER_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
assert receipt["status"] == "completed"
assert receipt["patches_generated"] == 0
assert receipt["patches_valid"] == 0
assert receipt["expected_blockers"] == 0
assert receipt["blocker_count"] == 0
assert receipt["blocker_path"] is None
assert receipt["clean_advisor_noop"] is True
readiness = receipt["controlled_downstream_apply"]
assert readiness["eligible"] is False
assert readiness["reason"] == "clean_advisor_noop_no_generated_patches"
assert readiness["generated_patch_count"] == 0
assert readiness["blocker_count"] == 0
assert readiness["clean_advisor_noop"] is True
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ advisor non-bridge no-op preserves clean target and no blockers"
else
    echo "  ✗ advisor non-bridge no-op emitted blockers or invalid receipt"
    [ -f "$ADVISOR_ONLY_BLOCKER_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_ONLY_BLOCKER_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    [ -f "$ADVISOR_ONLY_BLOCKER_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_ONLY_BLOCKER_OUTPUT/PATCHABILITY_BLOCKERS.json"
    exit 1
fi
if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch" \
    --lr-target docs/learning-recovery.md \
    --from-advisor "$ADVISOR_ONLY_BLOCKER_JSON" >/dev/null; then
    echo "  ✓ explicit patch rows can coexist with non-bridge advisor guidance"
else
    echo "  ✗ explicit patch row failed beside non-bridge advisor guidance"
    find "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch" -maxdepth 3 -type f -print
    [ -f "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi
if [ -s "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] \
    && [ ! -e "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
assert receipt["status"] == "completed"
assert receipt["patches_generated"] == 1
assert receipt["patches_valid"] == 1
assert receipt["expected_blockers"] == 0
assert receipt["blocker_count"] == 0
assert receipt["blocker_path"] is None
assert receipt["clean_advisor_noop"] is False
readiness = receipt["controlled_downstream_apply"]
assert readiness["eligible"] is True
assert readiness["reason"] == "generated_patches_apply_check_clean"
assert readiness["generated_patch_count"] == 1
assert readiness["valid_patch_count"] == 1
assert readiness["blocker_count"] == 0
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ explicit patch replay stays apply-ready with non-bridge guidance"
else
    echo "  ✗ explicit patch replay lost apply readiness beside non-bridge guidance"
    [ -f "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    [ -f "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/PATCHABILITY_BLOCKERS.json" ] && cat "$ADVISOR_ONLY_BLOCKER_OUTPUT/with-explicit-patch/PATCHABILITY_BLOCKERS.json"
    exit 1
fi

if make -C "$OPT_DIR" recovery-runtime-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$MAKE_ADVISOR_OUTPUT" \
    FROM_ADVISOR="$ADVISOR_JSON" >/dev/null; then
    echo "  ✓ Makefile recovery-runtime-replay supports FROM_ADVISOR"
else
    echo "  ✗ Makefile recovery-runtime-replay failed with FROM_ADVISOR"
    find "$MAKE_ADVISOR_OUTPUT" -maxdepth 3 -type f -print
    exit 1
fi

ADVISOR_MIXED_JSON="$ADVISOR_MIXED_OUTPUT/OPPORTUNITIES.json"
cat > "$ADVISOR_MIXED_JSON" <<'EOF'
{
  "target": "advisor-mixed-fixture",
  "recommendations": [
    {
      "id": "REC-MIX-01",
      "title": "Add learning recovery guidance",
      "patch_materializer": "LR-01",
      "patch_target_file": "docs/advisor-learning.md",
      "scan_context": {"scanner": "repo-upgrade-advisor", "scan_limited": true, "sample": "as-32"},
      "evidence_context": {"primary_class": "active_doc", "source": "AS-32"},
      "anti_pattern_family": "unanchored_self_learning_claim",
      "evidence_refs": ["AS-32"],
      "owner_surface": "BMA #419",
      "first_deliverable": "Learning bridge row"
    },
    {
      "id": "REC-MIX-02",
      "title": "Preserve non-materialized proving-ground guidance",
      "anti_pattern_family": "reciprocal_proving_ground_gap",
      "evidence_refs": ["AS-24"],
      "owner_surface": "docs/CODE_REVIEW_GUIDE.md",
      "first_deliverable": "Open owner issue for proving-ground guidance"
    }
  ],
  "meta": {"timestamp": "2026-06-03T00:00:00Z", "advisor_version": "test"}
}
EOF
if make -C "$OPT_DIR" recovery-runtime-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$MAKE_MIXED_ADVISOR_OUTPUT" \
    FROM_ADVISOR="$ADVISOR_MIXED_JSON" >/dev/null; then
    echo "  ✓ Makefile recovery-runtime-replay tolerates advisor mixed patch and blocker rows"
else
    echo "  ✗ Makefile recovery-runtime-replay failed advisor mixed patch and blocker rows"
    find "$MAKE_MIXED_ADVISOR_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$MAKE_MIXED_ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$MAKE_MIXED_ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    [ -f "$MAKE_MIXED_ADVISOR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$MAKE_MIXED_ADVISOR_OUTPUT/PATCHABILITY_BLOCKERS.json"
    exit 1
fi

if [ -s "$MAKE_MIXED_ADVISOR_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] \
    && [ ! -e "$MAKE_MIXED_ADVISOR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$MAKE_MIXED_ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
assert receipt["status"] == "completed"
assert receipt["patches_generated"] == 1
assert receipt["patches_valid"] == 1
assert receipt["expected_blockers"] == 0
assert receipt["blocker_count"] == 0
assert receipt["blocker_path"] is None
assert receipt["target_git_state_unchanged"] is True
readiness = receipt["controlled_downstream_apply"]
assert readiness["eligible"] is True
assert readiness["reason"] == "generated_patches_apply_check_clean"
assert readiness["generated_patch_count"] == 1
assert readiness["valid_patch_count"] == 1
assert readiness["blocker_count"] == 0
assert readiness["target_git_state_unchanged"] is True
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ advisor mixed replay keeps valid patch apply-ready and skips non-bridge guidance"
else
    echo "  ✗ advisor mixed replay did not preserve apply-ready valid patch evidence"
    [ -f "$MAKE_MIXED_ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$MAKE_MIXED_ADVISOR_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    [ -f "$MAKE_MIXED_ADVISOR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$MAKE_MIXED_ADVISOR_OUTPUT/PATCHABILITY_BLOCKERS.json"
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
    && [ -s "$PATCH_METADATA" ] \
    && python3 - "$RECEIPT" "$SCORECARD" "$TARGET_REPO" "$MANIFEST" "$PATCH_METADATA" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
scorecard = json.loads(Path(sys.argv[2]).read_text())
target = Path(sys.argv[3]).resolve()
manifest = Path(sys.argv[4]).resolve()
metadata_path = Path(sys.argv[5]).resolve()
metadata = json.loads(metadata_path.read_text())
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
assert receipt["target_git_head_before"] == receipt["target_git_head_after"] == receipt["before_git_head"]
assert receipt["target_dirty_count_before"] == receipt["target_dirty_count_after"] == 0
assert receipt["downstream_contract_reference"].endswith("downstream-read-only-recovery-runtime-pilot-contract.md")
assert Path(receipt["manifest_path"]).resolve() == manifest
assert Path(receipt["optimization_scorecard_path"]).resolve() == Path(sys.argv[2]).resolve()
assert Path(receipt["generated_patch_pack_path"]).resolve() == Path(receipt["patch_dir"]).resolve()
assert Path(receipt["patch_metadata_path"]).resolve().name == "PATCH_PACK_METADATA.json"
assert receipt["blocker_path"] is None
assert Path(receipt["apply_check_result_path"]).resolve().name == "recovery-runtime-validate-patches.log"
pilot = receipt["downstream_pilot_receipt"]
assert pilot["artifact"] == "DOWNSTREAM_READ_ONLY_RECOVERY_RUNTIME_PILOT_RECEIPT"
assert pilot["schema_version"] == 1
assert pilot["target_path_or_name"] == str(target)
assert pilot["target_git_head_before"] == pilot["target_git_head_after"] == receipt["before_git_head"]
assert pilot["target_dirty_count_before"] == pilot["target_dirty_count_after"] == 0
assert pilot["optimizer_replay_receipt_path"] == receipt["receipt_path"]
assert Path(pilot["generated_patch_pack_path"]).resolve() == Path(receipt["patch_dir"]).resolve()
assert Path(pilot["patch_metadata_path"]).resolve().name == "PATCH_PACK_METADATA.json"
assert pilot["blocker_path"] is None
assert Path(pilot["apply_check_result_path"]).resolve().name == "recovery-runtime-validate-patches.log"
assert all("does not" in claim.lower() for claim in pilot["bounded_non_claims"])
readiness = receipt["controlled_downstream_apply"]
assert readiness["eligible"] is True
assert readiness["reason"] == "generated_patches_apply_check_clean"
assert readiness["generated_patch_count"] == 2
assert readiness["valid_patch_count"] == 2
assert readiness["blocker_count"] == 0
assert readiness["target_dirty_count_before"] == readiness["target_dirty_count_after"] == 0
assert readiness["mutation_boundary"] == "separate downstream PR only"
assert "portfolio data" in readiness["forbidden_touch_classes"]
assert pilot["controlled_downstream_apply"] == readiness
assert metadata["downstream_pilot_context"]["artifact"] == "DOWNSTREAM_READ_ONLY_RECOVERY_RUNTIME_PILOT_RECEIPT_CONTEXT"
assert metadata["downstream_pilot_context"]["schema_version"] == 1
assert Path(metadata["downstream_pilot_context"]["generated_patch_pack_path"]).resolve() == Path(receipt["patch_dir"]).resolve()
metadata_rows = {row["row_id"]: row for row in metadata["patches"]}
assert metadata_rows["FGR-01"]["downstream_pilot_context"]["target_file"] == "docs/foreground-guide.md"
assert metadata_rows["LR-01"]["downstream_pilot_context"]["target_file"] == "docs/learning-recovery.md"
assert Path(metadata_rows["FGR-01"]["downstream_pilot_context"]["patch_metadata_path"]).resolve() == metadata_path
assert scorecard["patches_generated"] == 2
assert scorecard["patches_valid"] == 2
assert scorecard["controlled_downstream_apply"] == readiness
assert scorecard["recommendation_strength"] == "limited"
assert scorecard["meta"]["status"] == "completed"
assert any("generate-patches.sh" in command["command"] for command in receipt["commands"])
assert any("validate-patches.sh" in command["command"] for command in receipt["commands"])
status = subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True)
assert status == ""
PY
then
    echo "  ✓ replay receipt preserves downstream pilot shape and unchanged target git proof"
else
    echo "  ✗ replay receipt missing expected proof"
    [ -f "$RECEIPT" ] && cat "$RECEIPT"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$FORBIDDEN_APPLY_OUTPUT" \
    --lr-target data/holdings.md \
    --expect-patches 1 >/dev/null; then
    echo "  ✓ forbidden downstream target replay completes but is not apply-ready"
else
    echo "  ✗ forbidden downstream target replay failed before readiness classification"
    find "$FORBIDDEN_APPLY_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$FORBIDDEN_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$FORBIDDEN_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$FORBIDDEN_APPLY_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] \
    && python3 - "$FORBIDDEN_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
readiness = receipt["controlled_downstream_apply"]
assert receipt["status"] == "completed"
assert receipt["patches_generated"] == 1
assert receipt["patches_valid"] == 1
assert receipt["blocker_count"] == 0
assert readiness["eligible"] is False
assert readiness["reason"] == "patch_targets_outside_allowed_touch_classes"
assert readiness["patch_target_files"] == ["data/holdings.md"]
unsafe = readiness["unsafe_patch_target_files"]
assert unsafe and unsafe[0]["target_file"] == "data/holdings.md"
assert unsafe[0]["reason"] == "forbidden_touch_class"
assert "data" in unsafe[0]["class"] or "holdings" in unsafe[0]["class"]
assert receipt["downstream_pilot_receipt"]["controlled_downstream_apply"] == readiness
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ apply-readiness rejects generated patches against forbidden target classes"
else
    echo "  ✗ apply-readiness allowed or misclassified forbidden target class"
    [ -f "$FORBIDDEN_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$FORBIDDEN_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$FORBIDDEN_DOC_APPLY_OUTPUT" \
    --lr-target docs/secrets.md \
    --expect-patches 1 >/dev/null; then
    echo "  ✓ allowed-prefix forbidden target replay completes but is not apply-ready"
else
    echo "  ✗ allowed-prefix forbidden target replay failed before readiness classification"
    find "$FORBIDDEN_DOC_APPLY_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$FORBIDDEN_DOC_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$FORBIDDEN_DOC_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$FORBIDDEN_DOC_APPLY_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] \
    && python3 - "$FORBIDDEN_DOC_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
readiness = receipt["controlled_downstream_apply"]
assert receipt["status"] == "completed"
assert receipt["patches_generated"] == 1
assert receipt["patches_valid"] == 1
assert readiness["eligible"] is False
assert readiness["reason"] == "patch_targets_outside_allowed_touch_classes"
assert readiness["patch_target_files"] == ["docs/secrets.md"]
unsafe = readiness["unsafe_patch_target_files"]
assert unsafe and unsafe[0]["target_file"] == "docs/secrets.md"
assert unsafe[0]["reason"] == "forbidden_touch_class"
assert "secrets" in unsafe[0]["class"] or "secret" in unsafe[0]["class"]
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ apply-readiness rejects forbidden filename stems under allowed prefixes"
else
    echo "  ✗ apply-readiness allowed or misclassified allowed-prefix forbidden target"
    [ -f "$FORBIDDEN_DOC_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$FORBIDDEN_DOC_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if bash "$OPT_DIR/scripts/replay-recovery-runtime-patch-pack.sh" \
    "$TARGET_REPO" \
    "$HIDDEN_PREFIX_APPLY_OUTPUT" \
    --lr-target .github/instructions/recovery.md \
    --expect-patches 1 >/dev/null; then
    echo "  ✓ hidden-prefix instruction target replay is apply-ready"
else
    echo "  ✗ hidden-prefix instruction target replay failed readiness classification"
    find "$HIDDEN_PREFIX_APPLY_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$HIDDEN_PREFIX_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$HIDDEN_PREFIX_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$HIDDEN_PREFIX_APPLY_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] \
    && python3 - "$HIDDEN_PREFIX_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" "$TARGET_REPO" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

receipt = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
readiness = receipt["controlled_downstream_apply"]
assert receipt["status"] == "completed"
assert receipt["patches_generated"] == 1
assert receipt["patches_valid"] == 1
assert receipt["blocker_count"] == 0
assert readiness["eligible"] is True
assert readiness["reason"] == "generated_patches_apply_check_clean"
assert readiness["patch_target_files"] == [".github/instructions/recovery.md"]
assert readiness["unsafe_patch_target_files"] == []
assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  ✓ apply-readiness accepts safe hidden-prefix instruction targets"
else
    echo "  ✗ apply-readiness rejected safe hidden-prefix instruction target"
    [ -f "$HIDDEN_PREFIX_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$HIDDEN_PREFIX_APPLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
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
assert blockers["downstream_pilot_context"]["artifact"] == "DOWNSTREAM_READ_ONLY_RECOVERY_RUNTIME_PILOT_RECEIPT_CONTEXT"
assert blockers["downstream_pilot_context"]["schema_version"] == 1
assert blockers["downstream_pilot_context"]["target_path_or_name"]
assert blockers["downstream_pilot_context"]["generated_patch_pack_path"]
row = blockers["blockers"][0]
assert row["row_id"] == "FGR-01"
assert row["blocker_code"] == "fgr01_already_grounded"
assert "already-grounded.md" in row["reason"]
assert row["downstream_pilot_context"]["target_file"] == "docs/already-grounded.md"
assert row["downstream_pilot_context"]["generated_patch_pack_path"] == blockers["downstream_pilot_context"]["generated_patch_pack_path"]
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
    "$BLOCKER_ONLY_OUTPUT" \
    --fgr-target docs/already-grounded.md \
    --expect-patches 0 \
    --expect-blockers 1 >/dev/null; then
    echo "  ✓ recovery-runtime replay completes blocker-only case without metadata path"
else
    echo "  ✗ recovery-runtime replay failed blocker-only case"
    find "$BLOCKER_ONLY_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$BLOCKER_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$BLOCKER_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$BLOCKER_ONLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$BLOCKER_ONLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
    exit 1
fi

if [ -s "$BLOCKER_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$BLOCKER_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" "$BLOCKER_ONLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" <<'PY'
import json
import sys
from pathlib import Path

blockers = json.loads(Path(sys.argv[1]).read_text())
receipt = json.loads(Path(sys.argv[2]).read_text())
assert blockers["patches_generated"] == 0
assert blockers["blocker_count"] == 1
assert receipt["patches_generated"] == 0
assert receipt["blocker_count"] == 1
assert receipt["patch_metadata_path"] is None
assert receipt["downstream_pilot_receipt"]["patch_metadata_path"] is None
assert blockers["downstream_pilot_context"]["patch_metadata_path"] is None
assert blockers["downstream_pilot_context"]["blocker_path"] == receipt["blocker_path"]
assert blockers["blockers"][0]["downstream_pilot_context"]["target_file"] == "docs/already-grounded.md"
PY
then
    echo "  ✓ blocker-only artifacts preserve receipt context without nonexistent patch metadata"
else
    echo "  ✗ blocker-only artifacts advertised nonexistent patch metadata"
    [ -f "$BLOCKER_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$BLOCKER_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$BLOCKER_ONLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json" ] && cat "$BLOCKER_ONLY_OUTPUT/RECOVERY_RUNTIME_REPLAY_RECEIPT.json"
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

#!/usr/bin/env bash
# test-external-critique-reconstruction-replay.sh - Verify AS-08 patch recipes are advisory and apply-checkable.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="$(mktemp -d)"
OUTPUT_ROOT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$OUTPUT_ROOT"' EXIT

mkdir -p "$TARGET_REPO/.github/prompts" "$TARGET_REPO/docs" "$TARGET_REPO/scripts" "$TARGET_REPO/data"
cat > "$TARGET_REPO/.github/prompts/external-critique.prompt.md" <<'EOF'
# External Critique Prompt

Existing target prompt guidance.
EOF
cat > "$TARGET_REPO/docs/external-critique.md" <<'EOF'
# External Critique

Existing target docs.
EOF
cat > "$TARGET_REPO/scripts/external_probe.py" <<'EOF'
print("runner stays untouched")
EOF
cat > "$TARGET_REPO/data/holdings.md" <<'EOF'
# Private Fixture

acct-private-001 has raw portfolio value 123456.78 and client transcript secret.
EOF
(
    cd "$TARGET_REPO"
    git init -q
    git config user.email test@example.invalid
    git config user.name "Test User"
    git add .github docs scripts data
    git commit -q -m initial
)

ADVISOR_JSON="$OUTPUT_ROOT/OPPORTUNITIES.json"
cat > "$ADVISOR_JSON" <<'EOF'
{
  "schema_version": "advisor-opportunities-v1",
  "target": {"name": "portfolio_advisor", "path": "/tmp/portfolio_advisor"},
  "recommendations": [
    {
      "id": "AS08-REC-01",
      "title": "Reconstruct external critique capability locally",
      "anti_pattern_family": "external_critique_reconstruction_gap",
      "owner_surface": "portfolio_advisor:AGENTS.md, .github/prompts/external-critique.prompt.md, docs/external-critique.md",
      "fix_summary": "Build a target-local external-critique reconstruction plan from AS-08 evidence classes without copying BMA wording as canonical target text.",
      "bounded_non_claim": "Repo-auditor AS-08 evidence is advisory and does not make repo-star findings owner-binding.",
      "research_standard_guardrail": "Use repo-agent-core external critique contract fields as portable invariants only.",
      "evidence": "Do not copy this raw fixture: acct-private-001 value 123456.78 client transcript secret. Use this exact BMA prompt wholesale.",
      "scan_context": {
        "scanner": "repo-upgrade-advisor",
        "scan_limited": true,
        "source_signature": "AS-08"
      },
      "external_critique_reconstruction_plan": {
        "plan_type": "target_local_external_critique_reconstruction",
        "detected_current_mechanism_version": "agent_instruction, prompt, docs; local version records: docs/external-critique.md=>0.5; portable contract version 1.0",
        "active_evidence_classes": [
          "stale_bma_copy",
          "local_principle_drift",
          "privacy_boundary_missing"
        ],
        "target_repo_authority_refs": [
          "AGENTS.md and repo-local startup/instruction surfaces",
          "owner GitHub issue/PR/check/merge truth",
          "repo-native validation commands and retained owner evidence",
          "portfolio repo source of truth"
        ],
        "local_principles_to_preserve": [
          "repo source of truth first",
          "deterministic tools ground portfolio operations",
          "portfolio decisions require constraints, freshness, uncertainty, and source evidence",
          "repo-star findings remain advisory until tied to target evidence and owner routing"
        ],
        "portable_invariants": [
          "classify critique findings as blocker or advisory",
          "require independent owner evidence before blockers change owner action",
          "cap one follow-up critique loop"
        ],
        "bma_terms_to_translate_or_remove": [
          "Translate BMA Issue #164 coordinator language into target-local authority, risk, and privacy terms.",
          "Remove wording that makes BMA prompt text canonical for the target repo."
        ],
        "exact_files_to_change": [
          ".github/prompts/external-critique.prompt.md",
          "docs/external-critique.md",
          "scripts/external_probe.py"
        ],
        "minimal_wording_or_code_changes": [
          "Add or repair a local EXTERNAL_CRITIQUE_CAPABILITY record on the named files.",
          "Name local authority refs, no forced finding quota, panel high-stakes context, one-follow-up loop cap, and privacy/redaction boundaries.",
          "Keep runner code unchanged unless target evidence shows an existing runner is the broken mechanism."
        ],
        "tests_or_validation_commands": [
          "run repo-native prompt/docs/policy checks for the changed files",
          "rerun repo-auditor AS-08 external-critique health detection",
          "run git diff --check"
        ],
        "privacy_redaction_notes": [
          "Do not retain raw portfolio values, account data, transcript/session content, private-source material, credentials, private URLs, or customer/internal text.",
          "Summarize or redact private evidence; retain only owner-routable, repo-safe evidence refs."
        ],
        "implementation_need": {
          "runner_code": "not required by AS-08 alone; only change if target evidence identifies an existing runner as the broken mechanism",
          "prompt_text": "update or create when prompt surfaces are listed or no capability exists",
          "docs": "update or create when docs surfaces are listed or no capability exists",
          "policy_only_guidance": "preferred default for missing_capability, stale_bma_copy, local_principle_drift, and privacy boundary repairs"
        },
        "owner_routing": "Repo-star findings remain advisory until tied to target evidence and owner routing; GitHub issue/PR/check/merge truth remains the closure authority."
      }
    }
  ],
  "meta": {"timestamp": "2026-06-22T00:00:00Z", "advisor_version": "test"}
}
EOF

OUTPUT_DIR="$OUTPUT_ROOT/replay"
if make -C "$OPT_DIR" external-critique-reconstruction-replay \
    TARGET="$TARGET_REPO" \
    OUTPUT_DIR="$OUTPUT_DIR" \
    FROM_ADVISOR="$ADVISOR_JSON" \
    EXPECT_PATCHES=1 \
    EXPECT_BLOCKERS=1 >/dev/null; then
    echo "  PASS: AS-08 external critique reconstruction replay completed"
else
    echo "  FAIL: AS-08 external critique reconstruction replay failed"
    find "$OUTPUT_DIR" -maxdepth 3 -type f -print 2>/dev/null || true
    [ -f "$OUTPUT_DIR/external-critique-reconstruction-generate-patches.log" ] && cat "$OUTPUT_DIR/external-critique-reconstruction-generate-patches.log"
    [ -f "$OUTPUT_DIR/EXTERNAL_CRITIQUE_RECONSTRUCTION_REPLAY_RECEIPT.json" ] && cat "$OUTPUT_DIR/EXTERNAL_CRITIQUE_RECONSTRUCTION_REPLAY_RECEIPT.json"
    exit 1
fi

MANIFEST="$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
PATCH="$OUTPUT_DIR/PATCH_PACK/AS-08-external-critique-reconstruction.patch"
METADATA="$OUTPUT_DIR/PATCH_PACK_METADATA.json"
BLOCKERS="$OUTPUT_DIR/PATCHABILITY_BLOCKERS.json"
RECEIPT="$OUTPUT_DIR/EXTERNAL_CRITIQUE_RECONSTRUCTION_REPLAY_RECEIPT.json"

if [ -s "$MANIFEST" ] \
    && grep -Fq '| AS-08 | external critique reconstruction for `.github/prompts/external-critique.prompt.md`' "$MANIFEST" \
    && grep -Fq '| AS-08 | external critique reconstruction for `docs/external-critique.md`' "$MANIFEST"; then
    echo "  PASS: replay wrote AS-08 manifest rows from advisor reconstruction plan"
else
    echo "  FAIL: replay manifest missing expected AS-08 rows"
    [ -f "$MANIFEST" ] && cat "$MANIFEST"
    exit 1
fi

if [ -s "$PATCH" ] && bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$OUTPUT_DIR/PATCH_PACK" >/dev/null; then
    echo "  PASS: AS-08 patch pack validates with git apply --check"
else
    echo "  FAIL: AS-08 patch pack did not validate"
    [ -f "$PATCH" ] && cat "$PATCH"
    exit 1
fi

if [ -s "$RECEIPT" ] \
    && [ -s "$METADATA" ] \
    && [ -s "$BLOCKERS" ] \
    && python3 - "$TARGET_REPO" "$MANIFEST" "$PATCH" "$METADATA" "$BLOCKERS" "$RECEIPT" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

target, manifest, patch, metadata, blockers, receipt = [Path(value) for value in sys.argv[1:7]]
patch_text = patch.read_text(encoding="utf-8")
combined_output = "\n".join(
    path.read_text(encoding="utf-8")
    for path in (manifest, patch, metadata, blockers, receipt)
)
receipt_payload = json.loads(receipt.read_text(encoding="utf-8"))
metadata_payload = json.loads(metadata.read_text(encoding="utf-8"))
blocker_payload = json.loads(blockers.read_text(encoding="utf-8"))

assert receipt_payload["status"] == "completed"
assert receipt_payload["patches_generated"] == 1
assert receipt_payload["patches_valid"] == 1
assert receipt_payload["blocker_count"] == 1
assert receipt_payload["target_git_state_unchanged"] is True
assert receipt_payload["before_git_head"] == receipt_payload["after_git_head"]
assert receipt_payload["before_git_status"] == receipt_payload["after_git_status"] == ""
assert "recommendations[].external_critique_reconstruction_plan.exact_files_to_change" in receipt_payload["arc3_consumed_fields"]
assert receipt_payload["controlled_downstream_apply"]["eligible"] is False
assert receipt_payload["controlled_downstream_apply"]["reason"] == "apply_check_clean_but_blocked_rows_remain"

assert "Before AS-08 detector evidence: stale_bma_copy, local_principle_drift, privacy_boundary_missing" in patch_text
assert "After AS-08 validation target" in patch_text
assert "portfolio repo source of truth" in patch_text
assert "repo source of truth first" in patch_text
assert "owner GitHub issue/PR/check/merge truth" in patch_text
assert "repo-agent-core `docs/external-critique-capability-contract.md`" in patch_text
assert "Runner code: not required by AS-08 alone" in patch_text
assert "scripts/external_probe.py" not in patch_text
assert "Use this exact BMA prompt wholesale" not in patch_text

rows = metadata_payload["patches"]
assert len(rows) == 2
assert {row["target_file"] for row in rows} == {
    ".github/prompts/external-critique.prompt.md",
    "docs/external-critique.md",
}
assert all(row["row_id"] == "AS-08" for row in rows)
assert all("privacy_safe_patch_summary" in row for row in rows)

assert blocker_payload["blocker_count"] == 1
blocker = blocker_payload["blockers"][0]
assert blocker["row_id"] == "AS-08"
assert blocker["blocker_code"] == "as08_runner_or_code_target_not_materialized"
assert "scripts/external_probe.py" in blocker["findings"]

for forbidden in ("acct-private-001", "123456.78", "client transcript secret"):
    assert forbidden not in combined_output, forbidden

assert subprocess.check_output(["git", "-C", str(target), "status", "--short"], text=True) == ""
PY
then
    echo "  PASS: AS-08 receipt, metadata, privacy, blocker, and target-cleanliness proof are present"
else
    echo "  FAIL: AS-08 replay outputs missing expected proof"
    [ -f "$PATCH" ] && cat "$PATCH"
    [ -f "$METADATA" ] && cat "$METADATA"
    [ -f "$BLOCKERS" ] && cat "$BLOCKERS"
    [ -f "$RECEIPT" ] && cat "$RECEIPT"
    exit 1
fi

echo ""
echo "=== external critique reconstruction replay test passed ==="

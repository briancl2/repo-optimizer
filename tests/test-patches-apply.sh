#!/usr/bin/env bash
# test-patches-apply.sh — Verify all patches in PATCH_PACK/ apply cleanly.
# Structural test: verifies validate-patches.sh script exists and is executable.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

echo "=== Patch Application Test ==="

# Check validate-patches.sh exists
if [ -x "$OPT_DIR/scripts/validate-patches.sh" ]; then
    echo "  ✓ validate-patches.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ validate-patches.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# Check fix-diff-headers.sh exists
if [ -x "$OPT_DIR/scripts/fix-diff-headers.sh" ]; then
    echo "  ✓ fix-diff-headers.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ fix-diff-headers.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# Check generate-patches.sh exists
if [ -x "$OPT_DIR/scripts/generate-patches.sh" ]; then
    echo "  ✓ generate-patches.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

TARGET_REPO="$(mktemp -d)"
EXTERNAL_FIXTURE="$(mktemp -d)"
OUTPUT_DIR="$(mktemp -d)"
PP_OUTPUT="$(mktemp -d)"
CAP_OUTPUT="$(mktemp -d)"
LIMIT_OUTPUT="$(mktemp -d)"
AUDIT_INPUT="$(mktemp -d)"
PIPELINE_OUTPUT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$EXTERNAL_FIXTURE" "$OUTPUT_DIR" "$PP_OUTPUT" "$CAP_OUTPUT" "$LIMIT_OUTPUT" "$AUDIT_INPUT" "$PIPELINE_OUTPUT"' EXIT

mkdir -p "$TARGET_REPO/scripts" "$TARGET_REPO/.agents/skills/reviewing-code-locally/scripts" "$TARGET_REPO/.agents/skills/template-validation" "$TARGET_REPO/.agents/skills/already-ready" "$TARGET_REPO/.agents/skills/escaped" "$TARGET_REPO/.agents/skills/out-of-row" "$TARGET_REPO/docs"
for n in 1 2 3 4 5 6 7; do
    mkdir -p "$TARGET_REPO/.agents/skills/too-many-$n"
    printf '%s\n' "# Too Many $n" "" "Skill fixture $n." > "$TARGET_REPO/.agents/skills/too-many-$n/SKILL.md"
done
printf '%s\n' '#!/bin/bash' '# pre-commit fixture' 'echo check' > "$TARGET_REPO/scripts/pre-commit-hook.sh"
printf '%s\n' '#!/bin/bash' '# local review fixture' 'echo review' > "$TARGET_REPO/.agents/skills/reviewing-code-locally/scripts/local_review.sh"
printf '%s\n' '#!/bin/bash' '# hook fixture' 'echo hook' > "$TARGET_REPO/scripts/post-merge-hook.sh"
printf '%s\n' '#!/bin/sh' '# non-bash hook fixture' 'echo hook' > "$TARGET_REPO/scripts/nonbash-hook.sh"
printf '%s\n' '#!/bin/bash' '# utility fixture' 'echo utility' > "$TARGET_REPO/scripts/utility.sh"
cat > "$TARGET_REPO/.agents/skills/template-validation/SKILL.md" <<'EOF'
# Template Validation

Validate templates without frontmatter.
EOF
cat > "$TARGET_REPO/.agents/skills/out-of-row/SKILL.md" <<'EOF'
# Out Of Row

This skill is mentioned outside the PP-1 manifest row.
EOF
printf '%s\n' '# Escaped Skill' > "$EXTERNAL_FIXTURE/escaped-skill.md"
ln -s "$EXTERNAL_FIXTURE/escaped-skill.md" "$TARGET_REPO/.agents/skills/escaped/SKILL.md"
cat > "$TARGET_REPO/.agents/skills/already-ready/SKILL.md" <<'EOF'
---
name: already-ready
description: "Already has frontmatter."
license: MIT
---

# Already Ready
EOF
cat > "$TARGET_REPO/AGENTS.md" <<'EOF'
# Agent Instructions

When asked for Issue #164 recommendations, offer a category such as "do real delivery" and let the operator pick the repo.
EOF
cat > "$TARGET_REPO/Makefile" <<'EOF'
help:
	@echo "make work-close WORK=<dir>"
EOF
cat > "$TARGET_REPO/docs/agent-operations.md" <<'EOF'
# Agent Operations

| Script | Purpose |
|---|---|
| `scripts/work-close.sh` | Work contract finalizer; runs the session grader |
EOF
cat > "$TARGET_REPO/docs/issue164-ecosystem-architecture.md" <<'EOF'
# Issue 164 Ecosystem Architecture

This fixture intentionally lacks the core-five proving-ground and capability-home guidance.
EOF
cat > "$TARGET_REPO/scripts/work-close.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORK_DIR="${1:?work dir required}"
shift || true
if [ -f scripts/score-session.sh ]; then
    bash scripts/score-session.sh "$WORK_DIR" "$(basename "$WORK_DIR")"
fi
echo "=== Done ==="
EOF
git -C "$TARGET_REPO" init -q
git -C "$TARGET_REPO" config user.email "test@example.com"
git -C "$TARGET_REPO" config user.name "Test User"
git -C "$TARGET_REPO" add .
git -C "$TARGET_REPO" commit -q -m "init patch target"

FINDINGS="$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
cat > "$FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| P4 | S-05 + S-06 + S-07 (bundled shell hardening) | 2 |
| WM-01 | no-handback recommendation contract | 3 |
| WM-02 | GitHub-native closeout bypass / closure authority clarification | 3 |
| WM-03 | core-five proving-ground guidance | 2 |
| WM-04 | capability-home / owner-surface table | 2 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$FINDINGS" "$OUTPUT_DIR" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for retained P4 shell hardening"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for retained P4 shell hardening"
    FAIL=$((FAIL + 1))
fi

PATCH_FILE="$OUTPUT_DIR/PATCH_PACK/P4-shell-hardening.patch"
if [ -s "$PATCH_FILE" ] \
    && grep -Fq 'diff --git a/scripts/pre-commit-hook.sh b/scripts/pre-commit-hook.sh' "$PATCH_FILE" \
    && grep -Fq 'diff --git a/.agents/skills/reviewing-code-locally/scripts/local_review.sh b/.agents/skills/reviewing-code-locally/scripts/local_review.sh' "$PATCH_FILE" \
    && grep -Fq '+#!/usr/bin/env bash' "$PATCH_FILE" \
    && grep -Fq '+set -euo pipefail' "$PATCH_FILE"; then
    echo "  ✓ retained P4 patch file materialized expected shell hardening"
    PASS=$((PASS + 1))
else
    echo "  ✗ retained P4 patch file missing expected shell hardening"
    [ -f "$PATCH_FILE" ] && cat "$PATCH_FILE"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$OUTPUT_DIR/PATCH_PACK" >/dev/null; then
    echo "  ✓ generated P4 patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ generated P4 patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

WM01_PATCH="$OUTPUT_DIR/PATCH_PACK/WM-01-no-handback-recommendation-contract.patch"
if [ -s "$WM01_PATCH" ] \
    && grep -Fq 'diff --git a/AGENTS.md b/AGENTS.md' "$WM01_PATCH" \
    && grep -Fq 'Goal-ready production episode' "$WM01_PATCH" \
    && grep -Fq 'owner surface' "$WM01_PATCH" \
    && grep -Fq 'first deliverable' "$WM01_PATCH" \
    && grep -Fq 'validation scope' "$WM01_PATCH" \
    && grep -Fq -- '-When asked for Issue #164 recommendations' "$WM01_PATCH"; then
    echo "  ✓ WM-01 patch materialized no-handback recommendation contract"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-01 patch missing no-handback recommendation contract"
    [ -f "$WM01_PATCH" ] && cat "$WM01_PATCH"
    FAIL=$((FAIL + 1))
fi

WM02_PATCH="$OUTPUT_DIR/PATCH_PACK/WM-02-github-native-closeout-bypass.patch"
if [ -s "$WM02_PATCH" ] \
    && grep -Fq 'diff --git a/scripts/work-close.sh b/scripts/work-close.sh' "$WM02_PATCH" \
    && grep -Fq -- '--github-native-closeout' "$WM02_PATCH" \
    && grep -Fq 'score-session-bypass.json' "$WM02_PATCH" \
    && grep -Fq 'score_session_not_authoritative' "$WM02_PATCH" \
    && grep -Fq 'GitHub-native issue/PR closure authority' "$WM02_PATCH"; then
    echo "  ✓ WM-02 patch materialized GitHub-native closeout bypass contract"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 patch missing GitHub-native closeout bypass contract"
    [ -f "$WM02_PATCH" ] && cat "$WM02_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$OUTPUT_DIR/PATCH_PACK" >/dev/null; then
    echo "  ✓ all generated patches pass git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ at least one generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

PP_FINDINGS="$PP_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$PP_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| PP-1 | add YAML frontmatter to `.agents/skills/template-validation/SKILL.md`; skip `.agents/skills/already-ready/SKILL.md`; reject `.agents/skills/escaped/SKILL.md` | 3 |
| PP-4 | hook safety flags for `scripts/post-merge-hook.sh`, skip `scripts/nonbash-hook.sh`, and ignore `scripts/utility.sh` | 3 |

## Notes

Mentioning `.agents/skills/out-of-row/SKILL.md` and `scripts/utility.sh` outside the matching row must not pull them into PP patches.
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$PP_FINDINGS" "$PP_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for PP-1/PP-4 pilot manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for PP-1/PP-4 pilot manifest"
    FAIL=$((FAIL + 1))
fi

PP1_PATCH="$PP_OUTPUT/PATCH_PACK/PP-1-skill-frontmatter.patch"
if [ -s "$PP1_PATCH" ] \
    && grep -Fq 'diff --git a/.agents/skills/template-validation/SKILL.md b/.agents/skills/template-validation/SKILL.md' "$PP1_PATCH" \
    && grep -Fq '+---' "$PP1_PATCH" \
    && grep -Fq '+name: template-validation' "$PP1_PATCH" \
    && grep -Fq '+description: "Template Validation"' "$PP1_PATCH" \
    && grep -Fq '+license: MIT' "$PP1_PATCH" \
    && ! grep -Fq 'already-ready/SKILL.md' "$PP1_PATCH" \
    && ! grep -Fq 'escaped/SKILL.md' "$PP1_PATCH" \
    && ! grep -Fq 'out-of-row/SKILL.md' "$PP1_PATCH"; then
    echo "  ✓ PP-1 patch materialized missing skill frontmatter only"
    PASS=$((PASS + 1))
else
    echo "  ✗ PP-1 patch missing expected skill frontmatter materialization"
    [ -f "$PP1_PATCH" ] && cat "$PP1_PATCH"
    FAIL=$((FAIL + 1))
fi

PP4_PATCH="$PP_OUTPUT/PATCH_PACK/PP-4-hook-safety-flags.patch"
if [ -s "$PP4_PATCH" ] \
    && grep -Fq 'diff --git a/scripts/post-merge-hook.sh b/scripts/post-merge-hook.sh' "$PP4_PATCH" \
    && grep -Fq '+#!/usr/bin/env bash' "$PP4_PATCH" \
    && grep -Fq '+set -euo pipefail' "$PP4_PATCH" \
    && ! grep -Fq 'scripts/nonbash-hook.sh' "$PP4_PATCH" \
    && ! grep -Fq 'scripts/utility.sh' "$PP4_PATCH"; then
    echo "  ✓ PP-4 patch materialized hook safety flags"
    PASS=$((PASS + 1))
else
    echo "  ✗ PP-4 patch missing expected hook safety flags"
    [ -f "$PP4_PATCH" ] && cat "$PP4_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$PP_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ PP-1/PP-4 generated patches pass git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ PP-1/PP-4 generated patches failed git apply --check"
    FAIL=$((FAIL + 1))
fi

CAP_FINDINGS="$CAP_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$CAP_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| P4 | S-05 + S-06 + S-07 (bundled shell hardening) | 2 |
| PP-1 | add YAML frontmatter to `.agents/skills/template-validation/SKILL.md` | 1 |
| PP-4 | hook safety flags for `scripts/post-merge-hook.sh` | 1 |
| WM-01 | no-handback recommendation contract | 3 |
| WM-02 | GitHub-native closeout bypass / closure authority clarification | 3 |
| WM-03 | core-five proving-ground guidance | 2 |
| WM-04 | capability-home / owner-surface table | 2 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$CAP_FINDINGS" "$CAP_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for seven-row patch manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for seven-row patch manifest"
    FAIL=$((FAIL + 1))
fi

CAP_PATCH_COUNT="$(find "$CAP_OUTPUT/PATCH_PACK" -maxdepth 1 -name '*.patch' | wc -l | tr -d ' ')"
if [ "$CAP_PATCH_COUNT" = "5" ] \
    && [ -s "$CAP_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$CAP_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 5; assert d['blocker_count'] == 2; assert {row['row_id'] for row in d['blockers']} == {'WM-03','WM-04'}; assert {row['blocker_code'] for row in d['blockers']} == {'patch_run_limit_exceeded'}"; then
    echo "  ✓ seven-row manifest caps output at five patches and blocks overflow rows"
    PASS=$((PASS + 1))
else
    echo "  ✗ seven-row manifest did not enforce five-patch cap"
    [ -f "$CAP_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$CAP_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$CAP_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ capped patch set passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ capped patch set failed git apply --check"
    FAIL=$((FAIL + 1))
fi

LIMIT_FINDINGS="$LIMIT_OUTPUT/OPTIMIZATION_PLAN.md"
{
    cat <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
EOF
    printf '| PP-1 | add YAML frontmatter to '
    for n in 1 2 3 4 5 6 7; do
        if [ "$n" -gt 1 ]; then
            printf ', '
        fi
        printf '`.agents/skills/too-many-%s/SKILL.md`' "$n"
    done
    printf ' | 7 |\n'
} > "$LIMIT_FINDINGS"

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$LIMIT_FINDINGS" "$LIMIT_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for over-limit PP-1 manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for over-limit PP-1 manifest"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$LIMIT_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$LIMIT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$LIMIT_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; assert d['blockers'][0]['row_id'] == 'PP-1'; assert d['blockers'][0]['blocker_code'] == 'patch_file_limit_exceeded'"; then
    echo "  ✓ over-limit PP-1 manifest preserves specific patchability blocker"
    PASS=$((PASS + 1))
else
    echo "  ✗ over-limit PP-1 manifest lost specific patchability blocker"
    [ -f "$LIMIT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$LIMIT_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

WM03_PATCH="$OUTPUT_DIR/PATCH_PACK/WM-03-core-five-proving-ground-guidance.patch"
if [ -s "$WM03_PATCH" ] \
    && grep -Fq 'diff --git a/AGENTS.md b/AGENTS.md' "$WM03_PATCH" \
    && grep -Fq 'diff --git a/docs/issue164-ecosystem-architecture.md b/docs/issue164-ecosystem-architecture.md' "$WM03_PATCH" \
    && grep -Fq 'core-five proving-ground guidance' "$WM03_PATCH" \
    && grep -Fq 'validate against each other read-only' "$WM03_PATCH" \
    && grep -Fq 'not downstream adoption' "$WM03_PATCH" \
    && grep -Fq 'own owner issue, branch, PR, checks, and merge' "$WM03_PATCH"; then
    echo "  ✓ WM-03 patch materialized core-five proving-ground guidance"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-03 patch missing core-five proving-ground guidance"
    [ -f "$WM03_PATCH" ] && cat "$WM03_PATCH"
    FAIL=$((FAIL + 1))
fi

WM04_PATCH="$OUTPUT_DIR/PATCH_PACK/WM-04-capability-home-owner-surface-table.patch"
if [ -s "$WM04_PATCH" ] \
    && grep -Fq 'diff --git a/AGENTS.md b/AGENTS.md' "$WM04_PATCH" \
    && grep -Fq 'diff --git a/docs/issue164-ecosystem-architecture.md b/docs/issue164-ecosystem-architecture.md' "$WM04_PATCH" \
    && grep -Fq 'capability-home owner-surface routing' "$WM04_PATCH" \
    && grep -Fq '| Audit/signature detection | repo-auditor |' "$WM04_PATCH" \
    && grep -Fq '| Recommendation packaging | repo-upgrade-advisor |' "$WM04_PATCH" \
    && grep -Fq '| Patch-pack materialization | repo-optimizer |' "$WM04_PATCH" \
    && grep -Fq '| Shared repo-agent contract | repo-agent-core |' "$WM04_PATCH"; then
    echo "  ✓ WM-04 patch materialized capability-home owner-surface table"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-04 patch missing capability-home owner-surface table"
    [ -f "$WM04_PATCH" ] && cat "$WM04_PATCH"
    FAIL=$((FAIL + 1))
fi

cat > "$AUDIT_INPUT/SCORECARD.json" <<'EOF'
{
  "composite": 81,
  "audit_status": "completed",
  "dimensions": {
    "D1_governance": {"score": 14, "max": 20},
    "D2_tests": {"score": 18, "max": 20},
    "D3_skill_maturity": {"score": 15, "max": 20}
  }
}
EOF
cat > "$AUDIT_INPUT/AUDIT_RUN_RECEIPT.json" <<'EOF'
{
  "status": "completed"
}
EOF
printf '%s\n' '# Audit Report' > "$AUDIT_INPUT/AUDIT_REPORT.md"
cp "$FINDINGS" "$AUDIT_INPUT/OPTIMIZATION_PLAN.md"

if OPTIMIZER_PREFLIGHT_ONLY=true bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$AUDIT_INPUT" "$PIPELINE_OUTPUT" --patch >/dev/null; then
    echo "  ✓ repo-optimizer.sh materializes retained audit-side patch manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ repo-optimizer.sh failed to materialize retained audit-side patch manifest"
    FAIL=$((FAIL + 1))
fi

if [ -s "$PIPELINE_OUTPUT/PATCH_PACK/P4-shell-hardening.patch" ] \
    && python3 -c "import json; d=json.load(open('$PIPELINE_OUTPUT/OPTIMIZATION_SCORECARD.json')); assert d['patches_generated'] >= 1 and d['patches_valid'] >= 1"; then
    echo "  ✓ optimizer scorecard reports generated and valid retained patches"
    PASS=$((PASS + 1))
else
    echo "  ✗ optimizer scorecard did not report generated and valid retained patches"
    FAIL=$((FAIL + 1))
fi

BLOCKED_OUTPUT="$(mktemp -d)"
BLOCKED_AUDIT_INPUT="$(mktemp -d)"
BLOCKED_PIPELINE_OUTPUT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$EXTERNAL_FIXTURE" "$OUTPUT_DIR" "$PP_OUTPUT" "$CAP_OUTPUT" "$LIMIT_OUTPUT" "$AUDIT_INPUT" "$PIPELINE_OUTPUT" "$BLOCKED_OUTPUT" "$BLOCKED_AUDIT_INPUT" "$BLOCKED_PIPELINE_OUTPUT"' EXIT
BLOCKED_FINDINGS="$BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| TP-01 | Transcript chunking boundary normalization | 2 |
| TP-02 | Speaker diarization fallback contract | 3 |
| TP-03 | OCR retry budget guidance | 2 |
| TP-04 | Metadata provenance receipt plumbing | 4 |
| TP-05 | Read-only pilot reporting guardrails | 2 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$BLOCKED_FINDINGS" "$BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for unsupported transcript pilot manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for unsupported transcript pilot manifest"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 5; assert {row['row_id'] for row in d['blockers']} == {'TP-01','TP-02','TP-03','TP-04','TP-05'}"; then
    echo "  ✓ unsupported transcript pilot manifest emits PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ unsupported transcript pilot manifest did not emit PATCHABILITY_BLOCKERS.json as expected"
    FAIL=$((FAIL + 1))
fi

cat > "$BLOCKED_AUDIT_INPUT/SCORECARD.json" <<'EOF'
{
  "composite": 81,
  "audit_status": "completed",
  "dimensions": {
    "D1_governance": {"score": 14, "max": 20},
    "D2_tests": {"score": 18, "max": 20},
    "D3_skill_maturity": {"score": 15, "max": 20}
  }
}
EOF
cat > "$BLOCKED_AUDIT_INPUT/AUDIT_RUN_RECEIPT.json" <<'EOF'
{
  "status": "completed"
}
EOF
printf '%s\n' '# Audit Report' > "$BLOCKED_AUDIT_INPUT/AUDIT_REPORT.md"
cp "$BLOCKED_FINDINGS" "$BLOCKED_AUDIT_INPUT/OPTIMIZATION_PLAN.md"

if OPTIMIZER_PREFLIGHT_ONLY=true bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$BLOCKED_AUDIT_INPUT" "$BLOCKED_PIPELINE_OUTPUT" --patch >/dev/null; then
    echo "  ✓ repo-optimizer.sh completed for unsupported transcript pilot manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ repo-optimizer.sh failed for unsupported transcript pilot manifest"
    FAIL=$((FAIL + 1))
fi

if [ -s "$BLOCKED_PIPELINE_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$BLOCKED_PIPELINE_OUTPUT/OPTIMIZATION_SCORECARD.json')); assert d['patches_generated'] == 0 and d['patches_valid'] == 0; assert d['meta']['patch_status'] == 'fail_closed_patchability_blocked'"; then
    echo "  ✓ optimizer scorecard and artifacts report patchability-blocked state"
    PASS=$((PASS + 1))
else
    echo "  ✗ optimizer scorecard did not report patchability-blocked state"
    FAIL=$((FAIL + 1))
fi

BLOCKED_VALIDATE_OUTPUT="$BLOCKED_OUTPUT/validate-output.txt"
if make -C "$OPT_DIR" validate OUTPUT_DIR="$BLOCKED_PIPELINE_OUTPUT" > "$BLOCKED_VALIDATE_OUTPUT" 2>&1 \
    && grep -Fq 'Patchability blockers: 5' "$BLOCKED_VALIDATE_OUTPUT" \
    && grep -Fq 'TP-01: unsupported_manifest_row' "$BLOCKED_VALIDATE_OUTPUT"; then
    echo "  ✓ make validate reports patchability blockers clearly"
    PASS=$((PASS + 1))
else
    echo "  ✗ make validate did not report patchability blockers clearly"
    cat "$BLOCKED_VALIDATE_OUTPUT" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

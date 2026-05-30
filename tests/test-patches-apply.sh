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
OUTPUT_DIR="$(mktemp -d)"
AUDIT_INPUT="$(mktemp -d)"
PIPELINE_OUTPUT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$OUTPUT_DIR" "$AUDIT_INPUT" "$PIPELINE_OUTPUT"' EXIT

mkdir -p "$TARGET_REPO/scripts" "$TARGET_REPO/.agents/skills/reviewing-code-locally/scripts" "$TARGET_REPO/docs"
printf '%s\n' '#!/bin/bash' '# pre-commit fixture' 'echo check' > "$TARGET_REPO/scripts/pre-commit-hook.sh"
printf '%s\n' '#!/bin/bash' '# local review fixture' 'echo review' > "$TARGET_REPO/.agents/skills/reviewing-code-locally/scripts/local_review.sh"
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

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

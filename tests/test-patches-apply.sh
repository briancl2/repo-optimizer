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
PP3_OUTPUT="$(mktemp -d)"
CAP_OUTPUT="$(mktemp -d)"
LIMIT_OUTPUT="$(mktemp -d)"
MIXED_OUTPUT="$(mktemp -d)"
STALE_OUTPUT="$(mktemp -d)"
REAL_OUTPUT="$(mktemp -d)"
PP4_RUNTIME_REPO="$(mktemp -d)"
PP4_UNSAFE_OUTPUT="$(mktemp -d)"
AUDIT_INPUT="$(mktemp -d)"
PIPELINE_OUTPUT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$EXTERNAL_FIXTURE" "$OUTPUT_DIR" "$PP_OUTPUT" "$PP3_OUTPUT" "$CAP_OUTPUT" "$LIMIT_OUTPUT" "$MIXED_OUTPUT" "$STALE_OUTPUT" "$REAL_OUTPUT" "$PP4_RUNTIME_REPO" "$PP4_UNSAFE_OUTPUT" "$AUDIT_INPUT" "$PIPELINE_OUTPUT"' EXIT

mkdir -p "$TARGET_REPO/scripts" "$TARGET_REPO/.agents/skills/reviewing-code-locally/scripts" "$TARGET_REPO/.agents/skills/template-validation" "$TARGET_REPO/.agents/skills/already-ready" "$TARGET_REPO/.agents/skills/metadata-target" "$TARGET_REPO/.agents/skills/escaped" "$TARGET_REPO/.agents/skills/out-of-row" "$TARGET_REPO/.agents/skills/anti-pattern-check" "$TARGET_REPO/.agents/skills/quality-benchmark" "$TARGET_REPO/.agents/skills/transcript-processing" "$TARGET_REPO/.agents/skills/glitch-detection" "$TARGET_REPO/.github/agents" "$TARGET_REPO/docs"
for n in 1 2 3 4 5 6 7; do
    mkdir -p "$TARGET_REPO/.agents/skills/too-many-$n"
    printf '%s\n' "# Too Many $n" "" "Skill fixture $n." > "$TARGET_REPO/.agents/skills/too-many-$n/SKILL.md"
done
printf '%s\n' '#!/bin/bash' '# pre-commit fixture' 'echo check' > "$TARGET_REPO/scripts/pre-commit-hook.sh"
printf '%s\n' '#!/bin/bash' '# local review fixture' 'echo review' > "$TARGET_REPO/.agents/skills/reviewing-code-locally/scripts/local_review.sh"
printf '%s\n' '#!/bin/bash' '# hook fixture' 'echo hook' > "$TARGET_REPO/scripts/post-merge-hook.sh"
printf '%s\n' '#!/bin/sh' '# non-bash hook fixture' 'echo hook' > "$TARGET_REPO/scripts/nonbash-hook.sh"
printf '%s\n' '#!/bin/bash' '# utility fixture' 'echo utility' > "$TARGET_REPO/scripts/utility.sh"
cat > "$TARGET_REPO/scripts/commit-msg-hook.sh" <<'EOF'
#!/bin/bash
# commit hook fixture
MSG_FILE="$1"
SUBJECT=$(head -1 "$MSG_FILE")
if echo "$SUBJECT" | grep -qE '(Spec-ID|Spec-Exempt):'; then
  TRAILER=$(echo "$SUBJECT" | grep -oE '(Spec-ID|Spec-Exempt): ?[^ ].*$')
  CLEAN_SUBJECT=$(echo "$SUBJECT" | sed -E 's/ *(Spec-ID|Spec-Exempt): ?[^ ].*$//')
  BODY=$(tail -n +2 "$MSG_FILE")
  { echo "$CLEAN_SUBJECT"; echo ""; echo "$TRAILER"; } > "$MSG_FILE"
  if [ -n "$BODY" ]; then
    BODY_WITHOUT_TRAILERS=$(printf '%s\n' "$BODY" | grep -vE '^(Spec-ID|Spec-Exempt):')
    if [ -n "$BODY_WITHOUT_TRAILERS" ]; then
      printf '%s\n' "$BODY_WITHOUT_TRAILERS" >> "$MSG_FILE"
    fi
  fi
fi
EOF
cat > "$TARGET_REPO/scripts/pre-push-hook.sh" <<'EOF'
#!/bin/bash
set -uo pipefail
# pre-push fixture
while read -r LOCAL_REF LOCAL_SHA REMOTE_REF REMOTE_SHA; do
    if [ "$LOCAL_SHA" = "0000000000000000000000000000000000000000" ]; then
        continue
    fi
    if [ "$REMOTE_SHA" = "0000000000000000000000000000000000000000" ]; then
        RANGE="$LOCAL_SHA"
    else
        RANGE="$REMOTE_SHA..$LOCAL_SHA"
    fi
    COMMIT_COUNT=$(git rev-list --count "$RANGE" 2>/dev/null || echo "0")
    FILE_COUNT=$(git diff --name-only "$REMOTE_SHA".."$LOCAL_SHA" 2>/dev/null | wc -l | tr -d ' ')
    echo "Pushing $COMMIT_COUNT commit(s) with $FILE_COUNT file(s) changed."
    echo "Manual diff: git diff $REMOTE_SHA..$LOCAL_SHA | head -200"
done
EOF
cat > "$TARGET_REPO/scripts/multi-sub-hook.sh" <<'EOF'
#!/bin/bash
# multi-substitution hook fixture
BODY="$1"
STAMP=$(date +%s) BODY_WITHOUT_TRAILERS=$(printf '%s\n' "$BODY" | grep -vE '^(Spec-ID|Spec-Exempt):')
printf '%s:%s\n' "$STAMP" "$BODY_WITHOUT_TRAILERS"
EOF
cat > "$TARGET_REPO/.agents/skills/template-validation/SKILL.md" <<'EOF'
# Template Validation

Validate templates without frontmatter.
EOF
cat > "$TARGET_REPO/.agents/skills/anti-pattern-check/SKILL.md" <<'EOF'
# Anti Pattern Check

Find common anti-patterns.
EOF
cat > "$TARGET_REPO/.agents/skills/quality-benchmark/SKILL.md" <<'EOF'
# Quality Benchmark

Run quality benchmark checks.
EOF
cat > "$TARGET_REPO/.agents/skills/transcript-processing/SKILL.md" <<'EOF'
# Transcript Processing

Process transcript files.
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
cat > "$TARGET_REPO/.agents/skills/metadata-target/SKILL.md" <<'EOF'
---
name: metadata-target
description: "Metadata target."
license: MIT
---

# Metadata Target
EOF
cat > "$TARGET_REPO/.agents/skills/glitch-detection/SKILL.md" <<'EOF'
---
name: glitch-detection
description: "Detect glitches."
license: MIT
---

# Glitch Detection
EOF
cat > "$TARGET_REPO/.agents/skills/reviewing-code-locally/SKILL.md" <<'EOF'
---
name: reviewing-code-locally
description: "Review code locally."
license: MIT
---

# Reviewing Code Locally
EOF
cat > "$TARGET_REPO/.agents/transcript-critic.agent.md" <<'EOF'
---
name: transcript-critic
description: "Review transcript output."
model: claude-sonnet-4.5
tools: [read, search]
---

# Transcript Critic
EOF
cat > "$TARGET_REPO/.github/agents/speckit.taskstoissues.agent.md" <<'EOF'
---
description: Convert tasks to GitHub issues.
tools: ['github/github-mcp-server/issue_write']
---

# Speckit Tasks To Issues
EOF
cat > "$TARGET_REPO/.github/agents/speckit.tasks.agent.md" <<'EOF'
---
description: Generate tasks.
handoffs:
  - label: Analyze
    agent: speckit.analyze
---

# Speckit Tasks
EOF
cat > "$TARGET_REPO/.github/agents/speckit.checklist.agent.md" <<'EOF'
---
description: Generate checklist.
---

# Speckit Checklist
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

PP3_FINDINGS="$PP3_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$PP3_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| PP-3 | additive `tools` / `stop_rules` metadata rows for `.agents/skills/metadata-target/SKILL.md` after excluding the rejected model-bump portion | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$PP3_FINDINGS" "$PP3_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for PP-3 metadata manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for PP-3 metadata manifest"
    FAIL=$((FAIL + 1))
fi

PP3_PATCH="$PP3_OUTPUT/PATCH_PACK/PP-3-additive-skill-metadata.patch"
if [ -s "$PP3_PATCH" ] \
    && grep -Fq 'diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md' "$PP3_PATCH" \
    && grep -Fq '+tools:' "$PP3_PATCH" \
    && grep -Fq '+  - repo-native checks' "$PP3_PATCH" \
    && grep -Fq '+stop_rules:' "$PP3_PATCH" \
    && grep -Fq '+  - no target mutation without owner issue/PR authorization' "$PP3_PATCH" \
    && ! grep -Fq '+model' "$PP3_PATCH"; then
    echo "  ✓ PP-3 patch materialized additive metadata without model changes"
    PASS=$((PASS + 1))
else
    echo "  ✗ PP-3 patch missing additive metadata contract"
    [ -f "$PP3_PATCH" ] && cat "$PP3_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$PP3_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ PP-3 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ PP-3 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

REAL_FINDINGS="$REAL_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$REAL_FINDINGS" <<'EOF'
# Optimization Plan

## 2. Approved Findings (prioritized)

| Pri | Rank · Domain | Finding | Target path(s) | Primary dim. lift | Action class |
|---:|---|---|---|---|---|
| P0 | Std #1 / Standardization | Add YAML frontmatter to `anti-pattern-check/SKILL.md` | `.agents/skills/anti-pattern-check/SKILL.md` | D3 skill_maturity | Additive |
| P0 | Std #2 / Standardization | Add YAML frontmatter to `quality-benchmark/SKILL.md` | `.agents/skills/quality-benchmark/SKILL.md` | D3 skill_maturity | Additive |
| P0 | Std #3 / Standardization | Add YAML frontmatter to `transcript-processing/SKILL.md` | `.agents/skills/transcript-processing/SKILL.md` | D3 skill_maturity | Additive |
| P2 | Std #4-bis / Standardization | Add `stop_rules` to `transcript-critic.agent.md` frontmatter | `.agents/transcript-critic.agent.md` | D3 skill_maturity | Additive |
| P2 | Std #12 / Standardization | Add `set -euo pipefail` to `commit-msg-hook.sh` | `scripts/commit-msg-hook.sh` | D1/D5 | Additive |
| P2 | Std #13 / Standardization | Add `-e` to `set -uo pipefail` in `pre-push-hook.sh` | `scripts/pre-push-hook.sh` | D1/D5 | Additive |

## 3. Downgraded Findings

| Rank · Domain | Original ask | Downgrade |
|---|---|---|
| Std #5 / Standardization | Add `model` + `tools` + `stop_rules` to `template-validation/SKILL.md` | Add only `tools` + `stop_rules`; omit `model` |
| Std #6 / Standardization | Same as #5 for `glitch-detection/SKILL.md` | Same downgrade |
| Std #7 / Standardization | Same as #5 for `reviewing-code-locally/SKILL.md` | Same downgrade |
| Std #8 / Standardization | Add `name`/`model`/`tools`/`stop_rules` to `speckit.taskstoissues.agent.md` | Add `name` + `tools` + `stop_rules` only |
| Std #9 / Standardization | Same as #8 for `speckit.tasks.agent.md` | Same downgrade |
| Std #10 / Standardization | Same as #8 for `speckit.checklist.agent.md` | Same downgrade |

## 4. Rejected Findings

Transparency record; not eligible for the patch manifest.

| Rank · Domain | Reason for rejection |
|---|---|
| Std #11 / Standardization | Hardening a deliberate no-op script would be metric chasing. |

## 5. Patch Manifest (PATCH=true mode)

| Patch | Approved finding(s) bundled | Files touched (est.) | Net lines (est.) | Class |
|---|---|---:|---:|---|
| PP-1 | Std #1, #2, #3 — add YAML frontmatter to three SKILL.md files | 3 | ~30 | Additive |
| PP-2 | F2 — extract duplicated `Domain Context` block + reference from 3 speckit agents | 4 | ~50 | Non-destructive extraction |
| PP-3 | Std #4-bis, Std #5/6/7 (downgraded additive parts: `tools`+`stop_rules`), Std #8/9/10 (`name`+`tools`+`stop_rules`) | ≤6 (split if needed) | ≤120 | Additive |
| PP-4 | Std #12, Std #13 — hook safety flags (`set -euo pipefail`, `-e`) | 2 | ~4 | Additive |
| PP-5 | EX-05 — `scorecard-delta-extractor` helper + caller updates | ≤3 | ~40 | Helper extraction |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$REAL_FINDINGS" "$REAL_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for actual-style finding-reference manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for actual-style finding-reference manifest"
    FAIL=$((FAIL + 1))
fi

REAL_PP1_PATCH="$REAL_OUTPUT/PATCH_PACK/PP-1-skill-frontmatter.patch"
REAL_PP3_SKILL_PATCH="$REAL_OUTPUT/PATCH_PACK/PP-3-additive-skill-metadata.patch"
REAL_PP3_AGENT_PATCH="$REAL_OUTPUT/PATCH_PACK/PP-3-additive-agent-metadata.patch"
REAL_PP4_PATCH="$REAL_OUTPUT/PATCH_PACK/PP-4-hook-safety-flags.patch"
if [ "$(grep -c '^diff --git' "$REAL_PP1_PATCH" 2>/dev/null || true)" = "3" ] \
    && [ "$(grep -c '^diff --git' "$REAL_PP3_SKILL_PATCH" 2>/dev/null || true)" = "2" ] \
    && [ "$(grep -c '^diff --git' "$REAL_PP3_AGENT_PATCH" 2>/dev/null || true)" = "4" ] \
    && [ "$(grep -c '^diff --git' "$REAL_PP4_PATCH" 2>/dev/null || true)" = "2" ] \
    && ! grep -Fq '+model' "$REAL_PP3_SKILL_PATCH" "$REAL_PP3_AGENT_PATCH" \
    && ! grep -Fq '+name:' "$REAL_PP3_SKILL_PATCH" "$REAL_PP3_AGENT_PATCH" \
    && grep -Fq 'diff --git a/.agents/skills/quality-benchmark/SKILL.md b/.agents/skills/quality-benchmark/SKILL.md' "$REAL_PP1_PATCH" \
    && grep -Fq 'diff --git a/scripts/pre-push-hook.sh b/scripts/pre-push-hook.sh' "$REAL_PP4_PATCH" \
    && grep -Fq 'diff --git a/scripts/commit-msg-hook.sh b/scripts/commit-msg-hook.sh' "$REAL_PP4_PATCH" \
    && grep -Fq '+    BODY_WITHOUT_TRAILERS=$(' "$REAL_PP4_PATCH" \
    && grep -Fq '+        printf' "$REAL_PP4_PATCH" \
    && grep -Fq 'grep -vE' "$REAL_PP4_PATCH" \
    && grep -Fq '|| {' "$REAL_PP4_PATCH" \
    && grep -Fq '[ "$status" -eq 1 ] || exit "$status"' "$REAL_PP4_PATCH" \
    && grep -Fq '+        FILE_COUNT=$(git diff-tree --no-commit-id --name-only -r --root "$LOCAL_SHA" 2>/dev/null | wc -l | tr -d '\'' '\'')' "$REAL_PP4_PATCH" \
    && grep -Fq '+        DIFF_HINT="git show --name-only --oneline $LOCAL_SHA | head -200"' "$REAL_PP4_PATCH"; then
    echo "  ✓ actual-style manifest resolves finding references into safe split patches"
    PASS=$((PASS + 1))
else
    echo "  ✗ actual-style manifest did not produce expected safe split patches"
    find "$REAL_OUTPUT" -maxdepth 3 -type f -print
    FAIL=$((FAIL + 1))
fi

if [ -s "$REAL_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$REAL_OUTPUT/PATCHABILITY_BLOCKERS.json')); codes={row['row_id']: row['blocker_code'] for row in d['blockers']}; assert d['patches_generated'] == 4; assert codes == {'PP-2':'unsupported_semantic_refactor','PP-5':'unsupported_helper_plus_caller_update'}"; then
    echo "  ✓ actual-style manifest keeps only explicit unsupported-row blockers"
    PASS=$((PASS + 1))
else
    echo "  ✗ actual-style manifest blocker output was not limited to PP-2/PP-5"
    [ -f "$REAL_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$REAL_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$REAL_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ actual-style generated patches pass git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ actual-style generated patches failed git apply --check"
    FAIL=$((FAIL + 1))
fi

cp -R "$TARGET_REPO/." "$PP4_RUNTIME_REPO/"
if git -C "$PP4_RUNTIME_REPO" apply "$REAL_PP4_PATCH"; then
    MSG_FILE="$PP4_RUNTIME_REPO/COMMIT_EDITMSG"
    printf '%s\n\n%s\n' "Repair hook Spec-Exempt: inline trailer" "Spec-Exempt: existing body trailer" > "$MSG_FILE"
    if bash "$PP4_RUNTIME_REPO/scripts/commit-msg-hook.sh" "$MSG_FILE" \
        && [ "$(cat "$MSG_FILE")" = "$(printf '%s\n\n%s' "Repair hook" "Spec-Exempt: inline trailer")" ]; then
        echo "  ✓ PP-4 semantic oracle preserves commit-msg all-trailer body case"
        PASS=$((PASS + 1))
    else
        echo "  ✗ PP-4 semantic oracle failed commit-msg all-trailer body case"
        cat "$MSG_FILE"
        FAIL=$((FAIL + 1))
    fi

    LOCAL_SHA="$(git -C "$PP4_RUNTIME_REPO" rev-parse HEAD)"
    ZERO_SHA="0000000000000000000000000000000000000000"
    PRE_PUSH_OUT="$PP4_RUNTIME_REPO/pre-push.out"
    if printf 'refs/heads/feature %s refs/heads/feature %s\n' "$LOCAL_SHA" "$ZERO_SHA" \
        | (cd "$PP4_RUNTIME_REPO" && bash scripts/pre-push-hook.sh origin git@example.invalid:test/repo.git) >"$PRE_PUSH_OUT" \
        && grep -Fq "Pushing 1 commit(s) with" "$PRE_PUSH_OUT" \
        && grep -Fq "Manual diff: git show --name-only --oneline $LOCAL_SHA | head -200" "$PRE_PUSH_OUT"; then
        echo "  ✓ PP-4 semantic oracle preserves new-branch pre-push case"
        PASS=$((PASS + 1))
    else
        echo "  ✗ PP-4 semantic oracle failed new-branch pre-push case"
        cat "$PRE_PUSH_OUT" 2>/dev/null || true
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ✗ PP-4 semantic runtime patch failed to apply"
    FAIL=$((FAIL + 2))
fi

PP4_UNSAFE_FINDINGS="$PP4_UNSAFE_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$PP4_UNSAFE_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch | Approved finding(s) bundled | Files touched (est.) | Net lines (est.) | Class |
|---|---|---:|---:|---|
| PP-4 | hook safety flags for `scripts/multi-sub-hook.sh` | 1 | ~2 | Additive |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$PP4_UNSAFE_FINDINGS" "$PP4_UNSAFE_OUTPUT" >/dev/null \
    && [ ! -s "$PP4_UNSAFE_OUTPUT/PATCH_PACK/PP-4-hook-safety-flags.patch" ] \
    && [ -s "$PP4_UNSAFE_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$PP4_UNSAFE_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; assert d['blockers'][0]['row_id'] == 'PP-4'; assert d['blockers'][0]['blocker_code'] == 'pp4_strict_grep_filter_unsafe'"; then
    echo "  ✓ PP-4 semantic oracle blocks ambiguous multi-substitution grep filters"
    PASS=$((PASS + 1))
else
    echo "  ✗ PP-4 semantic oracle failed to block ambiguous multi-substitution grep filter"
    find "$PP4_UNSAFE_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$PP4_UNSAFE_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$PP4_UNSAFE_OUTPUT/PATCHABILITY_BLOCKERS.json"
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

MIXED_FINDINGS="$MIXED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$MIXED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| SH-1 | S-05 + S-06 + S-07 bundled shell hardening alias | 2 |
| PP-1 | add YAML frontmatter to `.agents/skills/template-validation/SKILL.md` | 1 |
| PP-2 | extract duplicated domain-context text and replace with references | 3 |
| PP-5 | scorecard-delta helper plus caller updates | 4 |
| TP-99 | target-specific future work with no generic materializer | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$MIXED_FINDINGS" "$MIXED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for mixed patch/blocker manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for mixed patch/blocker manifest"
    FAIL=$((FAIL + 1))
fi

if [ -s "$MIXED_OUTPUT/PATCH_PACK/P4-shell-hardening.patch" ] \
    && [ -s "$MIXED_OUTPUT/PATCH_PACK/PP-1-skill-frontmatter.patch" ] \
    && [ -s "$MIXED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$MIXED_OUTPUT/PATCHABILITY_BLOCKERS.json')); codes={row['row_id']: row['blocker_code'] for row in d['blockers']}; assert d['patches_generated'] == 2; assert codes == {'PP-2':'unsupported_semantic_refactor','PP-5':'unsupported_helper_plus_caller_update','TP-99':'unsupported_manifest_row'}"; then
    echo "  ✓ mixed manifest preserves patch output plus explicit blocker reasons"
    PASS=$((PASS + 1))
else
    echo "  ✗ mixed manifest did not preserve explicit blocker reasons"
    [ -f "$MIXED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$MIXED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

STALE_FINDINGS="$STALE_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$STALE_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| PP-1 | add YAML frontmatter to `.agents/skills/template-validation/SKILL.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$STALE_FINDINGS" "$STALE_OUTPUT" >/dev/null \
    && [ -s "$STALE_OUTPUT/PATCH_PACK/PP-1-skill-frontmatter.patch" ]; then
    echo "  ✓ stale-output fixture seeded an initial patch"
    PASS=$((PASS + 1))
else
    echo "  ✗ stale-output fixture failed to seed an initial patch"
    FAIL=$((FAIL + 1))
fi

cat > "$STALE_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| TP-01 | unsupported transcript-only patch row | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$STALE_FINDINGS" "$STALE_OUTPUT" >/dev/null \
    && [ ! -e "$STALE_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$STALE_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$STALE_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; assert d['blockers'][0]['row_id'] == 'TP-01'"; then
    echo "  ✓ reused output directory clears stale patches before blocker generation"
    PASS=$((PASS + 1))
else
    echo "  ✗ reused output directory retained stale patch artifacts"
    find "$STALE_OUTPUT" -maxdepth 3 -type f -print
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
trap 'rm -rf "$TARGET_REPO" "$EXTERNAL_FIXTURE" "$OUTPUT_DIR" "$PP_OUTPUT" "$PP3_OUTPUT" "$CAP_OUTPUT" "$LIMIT_OUTPUT" "$MIXED_OUTPUT" "$STALE_OUTPUT" "$REAL_OUTPUT" "$AUDIT_INPUT" "$PIPELINE_OUTPUT" "$BLOCKED_OUTPUT" "$BLOCKED_AUDIT_INPUT" "$BLOCKED_PIPELINE_OUTPUT"' EXIT
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

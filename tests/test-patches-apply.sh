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
FLEET_REPORT_ONLY_OUTPUT="$(mktemp -d)"
REAL_OUTPUT="$(mktemp -d)"
HS_OUTPUT="$(mktemp -d)"
HS_BLOCKED_OUTPUT="$(mktemp -d)"
CR_OUTPUT="$(mktemp -d)"
CR_BLOCKED_OUTPUT="$(mktemp -d)"
NR_OUTPUT="$(mktemp -d)"
NR_APPEND_OUTPUT="$(mktemp -d)"
NR_BLOCKED_OUTPUT="$(mktemp -d)"
NR_CONTEXT_OUTPUT="$(mktemp -d)"
HFR_OUTPUT="$(mktemp -d)"
HFR_BLOCKED_OUTPUT="$(mktemp -d)"
FGR_OUTPUT="$(mktemp -d)"
FGR_BLOCKED_OUTPUT="$(mktemp -d)"
FGR_CONTEXT_OUTPUT="$(mktemp -d)"
LR_OUTPUT="$(mktemp -d)"
LR_BLOCKED_OUTPUT="$(mktemp -d)"
LR_CONTEXT_OUTPUT="$(mktemp -d)"
WM02_SAFE_REPO="$(mktemp -d)"
WM02_SAFE_OUTPUT="$(mktemp -d)"
WM02_CLEAN_OUTPUT="$(mktemp -d)"
WM02_BLOCKED_REPO="$(mktemp -d)"
WM02_BLOCKED_OUTPUT="$(mktemp -d)"
WM02_NO_ANCHOR_REPO="$(mktemp -d)"
WM02_NO_ANCHOR_OUTPUT="$(mktemp -d)"
PP4_RUNTIME_REPO="$(mktemp -d)"
PP4_UNSAFE_OUTPUT="$(mktemp -d)"
AUDIT_INPUT="$(mktemp -d)"
PIPELINE_OUTPUT="$(mktemp -d)"
trap 'rm -rf "$TARGET_REPO" "$EXTERNAL_FIXTURE" "$OUTPUT_DIR" "$PP_OUTPUT" "$PP3_OUTPUT" "$CAP_OUTPUT" "$LIMIT_OUTPUT" "$MIXED_OUTPUT" "$STALE_OUTPUT" "$FLEET_REPORT_ONLY_OUTPUT" "$REAL_OUTPUT" "$HS_OUTPUT" "$HS_BLOCKED_OUTPUT" "$CR_OUTPUT" "$CR_BLOCKED_OUTPUT" "$NR_OUTPUT" "$NR_APPEND_OUTPUT" "$NR_BLOCKED_OUTPUT" "$NR_CONTEXT_OUTPUT" "$HFR_OUTPUT" "$HFR_BLOCKED_OUTPUT" "$FGR_OUTPUT" "$FGR_BLOCKED_OUTPUT" "$FGR_CONTEXT_OUTPUT" "$LR_OUTPUT" "$LR_BLOCKED_OUTPUT" "$LR_CONTEXT_OUTPUT" "$WM02_SAFE_REPO" "$WM02_SAFE_OUTPUT" "$WM02_CLEAN_OUTPUT" "$WM02_BLOCKED_REPO" "$WM02_BLOCKED_OUTPUT" "$WM02_NO_ANCHOR_REPO" "$WM02_NO_ANCHOR_OUTPUT" "$PP4_RUNTIME_REPO" "$PP4_UNSAFE_OUTPUT" "$AUDIT_INPUT" "$PIPELINE_OUTPUT"' EXIT

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
cat > "$TARGET_REPO/docs/hermes-launch.md" <<'EOF'
# Hermes Launch

Hermes foreground wrapper:

```bash
timeout 900 hermes chat --provider copilot -m gpt-5.5 -q prompt -Q
status=$?
python3 scripts/validate-hermes-foreground-output.py --status-code "$status"
```
EOF
cat > "$TARGET_REPO/docs/capability-guidance.md" <<'EOF'
# Capability Guidance

The Hermes launch guidance describes default behavior but does not yet carry a
capability reconciliation record.
EOF
cat > "$TARGET_REPO/docs/pruning-continuity.md" <<'EOF'
# Pruning Continuity

Upstream capability intake found possible native replacements, but this target
does not yet carry a review-only pruning candidate matrix.
EOF
cat > "$TARGET_REPO/docs/pruning-continuity-existing.md" <<'EOF'
# Existing Pruning Continuity

## Native Replacement Pruning Candidates

| Native capability | Affected custom surface | Deletion/sunset confidence | Validation required before deletion | Owner action | Bounded non-claims |
|---|---|---|---|---|---|
| existing native capability | `scripts/existing-wrapper.sh` | Review-required candidate; no deletion proof by itself | Existing validation | Existing owner action | Existing non-claims |
EOF
cat > "$TARGET_REPO/docs/hermes-receipts.md" <<'EOF'
# Hermes Receipt Guidance

Use foreground Hermes commands for bounded local runs.
EOF
cat > "$TARGET_REPO/docs/hermes-receipts-grounded.md" <<'EOF'
# Grounded Hermes Receipt Guidance

## HERMES_FOREGROUND_RUN_RECEIPT

- Capture foreground Hermes command, exit status, stdout/stderr receipt path, and validation command.
EOF
cat > "$TARGET_REPO/docs/learning-recovery.md" <<'EOF'
# Learning Recovery Guidance

Use foreground owner issues and PRs for recovery records.
EOF
cat > "$TARGET_REPO/docs/learning-recovery-grounded.md" <<'EOF'
# Grounded Learning Recovery Guidance

## Learning / Recovery

- Decision changed: already recorded.
- GitHub surface: issue or PR.
- Raw evidence: command receipt.
- Optional GBrain slug: none.
- No-capture reason: duplicate.
- Reusable learning text: existing guidance.
- Owner action: owner issue.
- Bounded non-claims: no background memory.
EOF
cat > "$TARGET_REPO/docs/foreground-recovery.md" <<'EOF'
# Foreground Recovery Guidance

Capture foreground failures with bounded owner recovery steps.
EOF
cat > "$TARGET_REPO/docs/foreground-recovery-grounded.md" <<'EOF'
# Grounded Foreground Recovery Guidance

## Foreground Failure Guidance / Recovery

- Failure signal: already recorded.
- Recovery owner: owner issue.
- Recovery action: bounded foreground rerun.
- Evidence receipt: command receipt.
- Bounded non-claims: no target mutation.
EOF
cat > "$TARGET_REPO/scripts/generic-status.sh" <<'EOF'
#!/usr/bin/env bash
run_generic_tool
status=$?
echo "$status"
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
shift

# ── Parse flags ──────────────────────────────────────────────────────
NO_NOVEL_FINDINGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-novel-findings) NO_NOVEL_FINDINGS="${2:?--no-novel-findings requires a rationale}"; shift 2 ;;
        *) shift ;;
    esac
done

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
mkdir -p "$TARGET_REPO/.git/hooks"
printf '%s\n' '# internal Hermes receipt fixture' > "$TARGET_REPO/.git/hooks/hermes.md"

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
    && grep -Fq 'GitHub-native issue/PR closure authority' "$WM02_PATCH" \
    && ! grep -Fq '+    bash scripts/score-session.sh "$WORK_DIR" "$(basename "$WORK_DIR")"' "$WM02_PATCH"; then
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

mkdir -p "$WM02_SAFE_REPO/scripts" "$WM02_SAFE_REPO/docs"
cat > "$WM02_SAFE_REPO/scripts/work-close.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORK_DIR="${1:?work dir required}"
shift

# ── Parse flags ──────────────────────────────────────────────────────
NO_NOVEL_FINDINGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-novel-findings) NO_NOVEL_FINDINGS="${2:?--no-novel-findings requires a rationale}"; shift 2 ;;
        *) shift ;;
    esac
done

# ── Session grader (soft dependency) ─────────────────────────────────
SESSION_ID=$(basename "$WORK_DIR")
if [ -f scripts/score-session.sh ]; then
    echo "  Running session grader..."
    if bash scripts/score-session.sh "$WORK_DIR" "$SESSION_ID" 2>&1; then
        echo "  Session grader complete."
    else
        echo "  WARNING: Session grader failed (non-blocking)."
    fi
fi
echo "=== Done ==="
EOF
cat > "$WM02_SAFE_REPO/Makefile" <<'EOF'
help:
	@echo "make work-close WORK=<dir>"
EOF
cat > "$WM02_SAFE_REPO/docs/agent-operations.md" <<'EOF'
# Agent Operations

| Script | Purpose |
|---|---|
| `scripts/work-close.sh` | Work contract finalizer; runs the session grader |
EOF
git -C "$WM02_SAFE_REPO" init -q
git -C "$WM02_SAFE_REPO" config user.email "test@example.com"
git -C "$WM02_SAFE_REPO" config user.name "Test User"
git -C "$WM02_SAFE_REPO" add .
git -C "$WM02_SAFE_REPO" commit -q -m "init wm02 safe target"

WM02_SAFE_FINDINGS="$WM02_SAFE_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$WM02_SAFE_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| WM-02 | GitHub-native closeout bypass / closure authority clarification scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"wm02"} | 3 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$WM02_SAFE_REPO" "$WM02_SAFE_FINDINGS" "$WM02_SAFE_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for safe BMA-shaped WM-02 fixture"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for safe BMA-shaped WM-02 fixture"
    FAIL=$((FAIL + 1))
fi

WM02_SAFE_PATCH="$WM02_SAFE_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch"
if [ -s "$WM02_SAFE_PATCH" ] \
    && grep -Fq 'diff --git a/scripts/work-close.sh b/scripts/work-close.sh' "$WM02_SAFE_PATCH" \
    && grep -Fq '+GITHUB_NATIVE_CLOSEOUT=""' "$WM02_SAFE_PATCH" \
    && grep -Fq '+        --github-native-closeout) GITHUB_NATIVE_CLOSEOUT="${2:?--github-native-closeout requires a rationale}"; shift 2 ;;' "$WM02_SAFE_PATCH" \
    && grep -Fq '+if [ -n "$GITHUB_NATIVE_CLOSEOUT" ]; then' "$WM02_SAFE_PATCH" \
    && grep -Fq '+elif [ -f scripts/score-session.sh ]; then' "$WM02_SAFE_PATCH" \
    && ! grep -Fq '+    bash scripts/score-session.sh "$WORK_DIR" "$(basename "$WORK_DIR")"' "$WM02_SAFE_PATCH"; then
    echo "  ✓ WM-02 safe fixture anchors parser and score-session bypass without EOF fallback"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 safe fixture did not produce semantically anchored patch"
    [ -f "$WM02_SAFE_PATCH" ] && cat "$WM02_SAFE_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$WM02_SAFE_REPO" "$WM02_SAFE_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ WM-02 safe fixture patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 safe fixture patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

if [ -s "$WM02_SAFE_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && python3 -c "import json; d=json.load(open('$WM02_SAFE_OUTPUT/PATCH_PACK_METADATA.json')); row=next(r for r in d['patches'] if r['row_id'] == 'WM-02'); assert row['patch'] == 'WM-02-github-native-closeout-bypass.patch'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'wm02'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ WM-02 patch-pack metadata preserves inline scan_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 patch-pack metadata did not preserve inline scan_context"
    [ -f "$WM02_SAFE_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$WM02_SAFE_OUTPUT/PATCH_PACK_METADATA.json"
    FAIL=$((FAIL + 1))
fi

WM02_CLEAN_FINDINGS="$WM02_CLEAN_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$WM02_CLEAN_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| WM-02 | Direct Issue #164 campaign closure clean: closure_regrowth=>none and bypassed=>docs/issue164-direct-closure.md with github-native-closeout already present scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"wm02-clean"} | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$WM02_CLEAN_FINDINGS" "$WM02_CLEAN_OUTPUT" >/dev/null \
    && [ ! -e "$WM02_CLEAN_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$WM02_CLEAN_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$WM02_CLEAN_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; row=d['blockers'][0]; assert row['row_id'] == 'WM-02'; assert row['blocker_code'] == 'wm02_clean_direct_campaign_closure_no_patch'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'wm02-clean'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ WM-02 clean direct campaign closure row emits no patch and preserves scan context"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 clean direct campaign closure row generated a patch or lost no-op proof"
    find "$WM02_CLEAN_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$WM02_CLEAN_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$WM02_CLEAN_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$WM02_CLEAN_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch" ] && cat "$WM02_CLEAN_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch"
    FAIL=$((FAIL + 1))
fi

mkdir -p "$WM02_BLOCKED_REPO/scripts"
cat > "$WM02_BLOCKED_REPO/scripts/work-close.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORK_DIR="${1:?work dir required}"
shift || true
if [ -f scripts/score-session.sh ]; then
    bash scripts/score-session.sh "$WORK_DIR" "$(basename "$WORK_DIR")"
fi
if [ -f scripts/score-session.sh ]; then
    bash scripts/score-session.sh "$WORK_DIR" "second"
fi
EOF
cat > "$WM02_BLOCKED_REPO/Makefile" <<'EOF'
help:
	@echo "make work-close WORK=<dir>"
EOF
mkdir -p "$WM02_BLOCKED_REPO/docs"
cat > "$WM02_BLOCKED_REPO/docs/agent-operations.md" <<'EOF'
# Agent Operations

`scripts/work-close.sh` runs the session grader.
EOF
git -C "$WM02_BLOCKED_REPO" init -q
git -C "$WM02_BLOCKED_REPO" config user.email "test@example.com"
git -C "$WM02_BLOCKED_REPO" config user.name "Test User"
git -C "$WM02_BLOCKED_REPO" add .
git -C "$WM02_BLOCKED_REPO" commit -q -m "init ambiguous wm02 target"

WM02_BLOCKED_FINDINGS="$WM02_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$WM02_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| WM-02 | GitHub-native closeout bypass / closure authority clarification scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"wm02-blocked"} | 3 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$WM02_BLOCKED_REPO" "$WM02_BLOCKED_FINDINGS" "$WM02_BLOCKED_OUTPUT" >/dev/null \
    && [ ! -e "$WM02_BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$WM02_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$WM02_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; codes={b['blocker_code'] for b in d['blockers']}; assert 'wm02_parser_shape_ambiguous_or_absent' in codes; assert 'wm02_score_session_site_ambiguous_or_absent' in codes; row=next(b for b in d['blockers'] if b['blocker_code'] == 'wm02_score_session_site_ambiguous_or_absent'); assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'wm02-blocked'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ WM-02 ambiguous fixture emits explicit parser/site patchability blockers"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 ambiguous fixture did not emit expected blockers"
    [ -f "$WM02_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$WM02_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$WM02_BLOCKED_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch" ] && cat "$WM02_BLOCKED_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch"
    FAIL=$((FAIL + 1))
fi

mkdir -p "$WM02_NO_ANCHOR_REPO/scripts"
cat > "$WM02_NO_ANCHOR_REPO/scripts/work-close.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORK_DIR="${1:?work dir required}"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --no-novel-findings) echo "${2:?--no-novel-findings requires a rationale}" >/dev/null; shift 2 ;;
        *) shift ;;
    esac
done

if [ -f scripts/score-session.sh ]; then
    bash scripts/score-session.sh "$WORK_DIR" "$(basename "$WORK_DIR")"
fi
EOF
git -C "$WM02_NO_ANCHOR_REPO" init -q
git -C "$WM02_NO_ANCHOR_REPO" config user.email "test@example.com"
git -C "$WM02_NO_ANCHOR_REPO" config user.name "Test User"
git -C "$WM02_NO_ANCHOR_REPO" add .
git -C "$WM02_NO_ANCHOR_REPO" commit -q -m "init no-anchor wm02 target"

WM02_NO_ANCHOR_FINDINGS="$WM02_NO_ANCHOR_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$WM02_NO_ANCHOR_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| WM-02 | GitHub-native closeout bypass / closure authority clarification scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"wm02-no-anchor"} | 3 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$WM02_NO_ANCHOR_REPO" "$WM02_NO_ANCHOR_FINDINGS" "$WM02_NO_ANCHOR_OUTPUT" >/dev/null \
    && [ ! -e "$WM02_NO_ANCHOR_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$WM02_NO_ANCHOR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$WM02_NO_ANCHOR_OUTPUT/PATCHABILITY_BLOCKERS.json')); codes={b['blocker_code'] for b in d['blockers']}; assert 'wm02_parser_variable_anchor_absent' in codes; row=next(b for b in d['blockers'] if b['blocker_code'] == 'wm02_parser_variable_anchor_absent'); assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'wm02-no-anchor'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ WM-02 parser without nearby variable anchor fails closed"
    PASS=$((PASS + 1))
else
    echo "  ✗ WM-02 parser without nearby variable anchor did not fail closed"
    [ -f "$WM02_NO_ANCHOR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$WM02_NO_ANCHOR_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$WM02_NO_ANCHOR_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch" ] && cat "$WM02_NO_ANCHOR_OUTPUT/PATCH_PACK/WM-02-github-native-closeout-bypass.patch"
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
    && grep -Fq 'grep_status=$?' "$REAL_PP4_PATCH" \
    && grep -Fq '[ "$grep_status" -eq 1 ] || exit "$grep_status"' "$REAL_PP4_PATCH" \
    && ! grep -Fq '    status=$?' "$REAL_PP4_PATCH" \
    && ! grep -Fq '[ "$status" -eq 1 ] || exit "$status"' "$REAL_PP4_PATCH" \
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

HS_FINDINGS="$HS_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$HS_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| HS-01 | replace reserved Hermes launch `status=$?` in `docs/hermes-launch.md` scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"hs01"} | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$HS_FINDINGS" "$HS_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for HS-01 Hermes status materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for HS-01 Hermes status materializer"
    FAIL=$((FAIL + 1))
fi

HS_PATCH="$HS_OUTPUT/PATCH_PACK/HS-01-hermes-status-variable.patch"
if [ -s "$HS_PATCH" ] \
    && grep -Fq 'diff --git a/docs/hermes-launch.md b/docs/hermes-launch.md' "$HS_PATCH" \
    && grep -Fq '+hermes_status=$?' "$HS_PATCH" \
    && grep -Fq -- '--status-code "$hermes_status"' "$HS_PATCH" \
    && ! grep -Fq '+status=$?' "$HS_PATCH"; then
    echo "  ✓ HS-01 patch materialized safe Hermes status variable rewrite"
    PASS=$((PASS + 1))
else
    echo "  ✗ HS-01 patch missing safe Hermes status variable rewrite"
    [ -f "$HS_PATCH" ] && cat "$HS_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$HS_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ HS-01 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ HS-01 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

if [ -s "$HS_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && python3 -c "import json; d=json.load(open('$HS_OUTPUT/PATCH_PACK_METADATA.json')); row=next(r for r in d['patches'] if r['row_id'] == 'HS-01'); assert row['patch'] == 'HS-01-hermes-status-variable.patch'; assert row['target_file'] == 'docs/hermes-launch.md'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'hs01'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ HS-01 patch-pack metadata preserves inline scan_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ HS-01 patch-pack metadata did not preserve inline scan_context"
    [ -f "$HS_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$HS_OUTPUT/PATCH_PACK_METADATA.json"
    FAIL=$((FAIL + 1))
fi

HS_BLOCKED_FINDINGS="$HS_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$HS_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| HS-01 | generic reserved status rewrite in `scripts/generic-status.sh` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$HS_BLOCKED_FINDINGS" "$HS_BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for ambiguous HS-01 manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for ambiguous HS-01 manifest"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$HS_BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$HS_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$HS_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; assert d['blockers'][0]['row_id'] == 'HS-01'; assert d['blockers'][0]['blocker_code'] == 'hs01_ambiguous_status_assignment'"; then
    echo "  ✓ HS-01 ambiguous status rewrite emits PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ HS-01 ambiguous status rewrite did not emit expected blocker"
    [ -f "$HS_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$HS_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

CR_FINDINGS="$CR_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$CR_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| CR-01 | capability reconciliation for capability `Hermes -z` in `docs/capability-guidance.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$CR_FINDINGS" "$CR_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for CR-01 capability reconciliation materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for CR-01 capability reconciliation materializer"
    FAIL=$((FAIL + 1))
fi

CR_PATCH="$CR_OUTPUT/PATCH_PACK/CR-01-default-capability-reconciliation.patch"
if [ -s "$CR_PATCH" ] \
    && grep -Fq 'diff --git a/docs/capability-guidance.md b/docs/capability-guidance.md' "$CR_PATCH" \
    && grep -Fq 'Default Capability Reconciliation' "$CR_PATCH" \
    && grep -Fq '| Hermes -z | Upstream-main proof required before production default adoption | Local same-version proof required | Named owner surface required |' "$CR_PATCH"; then
    echo "  ✓ CR-01 patch materialized default capability reconciliation block"
    PASS=$((PASS + 1))
else
    echo "  ✗ CR-01 patch missing default capability reconciliation block"
    [ -f "$CR_PATCH" ] && cat "$CR_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$CR_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ CR-01 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ CR-01 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

CR_BLOCKED_FINDINGS="$CR_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$CR_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| CR-01 | capability reconciliation for `docs/capability-guidance.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$CR_BLOCKED_FINDINGS" "$CR_BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for blocked CR-01 manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for blocked CR-01 manifest"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$CR_BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$CR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$CR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; assert d['blockers'][0]['row_id'] == 'CR-01'; assert d['blockers'][0]['blocker_code'] == 'cr01_missing_named_capability'"; then
    echo "  ✓ CR-01 missing capability emits PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ CR-01 missing capability did not emit expected blocker"
    [ -f "$CR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$CR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

NR_FINDINGS="$NR_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$NR_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| NR-01 | native replacement pruning candidate for native capability `repo-agent-core upstream capability intake contract` in `docs/pruning-continuity.md` affected_surface: scripts/local-intake-wrapper.sh scan_context={"scanner":"repo-auditor-as","scanned_files":42,"eligible_files":50,"scan_limit":100,"scan_limited":true} evidence_context={"primary_class":"active_doc","source":"owner_issue_80"} | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$NR_FINDINGS" "$NR_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for NR-01 native pruning candidate materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for NR-01 native pruning candidate materializer"
    FAIL=$((FAIL + 1))
fi

NR_PATCH="$NR_OUTPUT/PATCH_PACK/NR-01-native-replacement-pruning-candidate.patch"
if [ -s "$NR_PATCH" ] \
    && grep -Fq 'diff --git a/docs/pruning-continuity.md b/docs/pruning-continuity.md' "$NR_PATCH" \
    && grep -Fq 'Native Replacement Pruning Candidates' "$NR_PATCH" \
    && grep -Fq '| repo-agent-core upstream capability intake contract | `scripts/local-intake-wrapper.sh` | Review-required candidate; no deletion proof by itself |' "$NR_PATCH" \
    && grep -Fq 'No target mutation, auto-apply, automatic PR creation, recurring inventory, scheduler, queue, registry, or background memory' "$NR_PATCH"; then
    echo "  ✓ NR-01 patch materialized review-only native pruning candidate block"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 patch missing review-only native pruning candidate block"
    [ -f "$NR_PATCH" ] && cat "$NR_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$NR_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ NR-01 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

if [ -s "$NR_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && python3 -c "import json; d=json.load(open('$NR_OUTPUT/PATCH_PACK_METADATA.json')); rows=d['patches']; row=next(r for r in rows if r['row_id'] == 'NR-01'); assert row['patch'] == 'NR-01-native-replacement-pruning-candidate.patch'; assert row['target_file'] == 'docs/pruning-continuity.md'; assert row['native_capability'] == 'repo-agent-core upstream capability intake contract'; assert row['affected_surface'] == 'scripts/local-intake-wrapper.sh'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scanned_files':42,'eligible_files':50,'scan_limit':100,'scan_limited':True}; assert row['evidence_context'] == {'primary_class':'active_doc','source':'owner_issue_80'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ NR-01 patch-pack metadata preserves scan/evidence context"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 patch-pack metadata did not preserve scan/evidence context"
    [ -f "$NR_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$NR_OUTPUT/PATCH_PACK_METADATA.json"
    FAIL=$((FAIL + 1))
fi

if git -C "$TARGET_REPO" diff --quiet -- docs/pruning-continuity.md; then
    echo "  ✓ NR-01 materializer left target repo unmodified"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 materializer mutated target repo"
    git -C "$TARGET_REPO" diff -- docs/pruning-continuity.md
    FAIL=$((FAIL + 1))
fi

NR_APPEND_FINDINGS="$NR_APPEND_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$NR_APPEND_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| NR-01 | native replacement pruning candidate for native capability `repo-agent-core upstream capability intake contract` in `docs/pruning-continuity-existing.md` affected_surface: scripts/new-wrapper.sh | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$NR_APPEND_FINDINGS" "$NR_APPEND_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for NR-01 append candidate materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for NR-01 append candidate materializer"
    FAIL=$((FAIL + 1))
fi

NR_APPEND_PATCH="$NR_APPEND_OUTPUT/PATCH_PACK/NR-01-native-replacement-pruning-candidate.patch"
if [ -s "$NR_APPEND_PATCH" ] \
    && grep -Fq '+| repo-agent-core upstream capability intake contract | `scripts/new-wrapper.sh` | Review-required candidate; no deletion proof by itself |' "$NR_APPEND_PATCH" \
    && ! grep -Fq -- '-| existing native capability | `scripts/existing-wrapper.sh` |' "$NR_APPEND_PATCH"; then
    echo "  ✓ NR-01 appends new candidate without deleting existing candidate rows"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 append patch did not preserve existing candidate rows"
    [ -f "$NR_APPEND_PATCH" ] && cat "$NR_APPEND_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$NR_APPEND_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ NR-01 append patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 append patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

NR_BLOCKED_FINDINGS="$NR_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$NR_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| NR-01 | native replacement pruning candidate in `docs/pruning-continuity.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$NR_BLOCKED_FINDINGS" "$NR_BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for blocked NR-01 manifest"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for blocked NR-01 manifest"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$NR_BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$NR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$NR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; assert d['blockers'][0]['row_id'] == 'NR-01'; assert d['blockers'][0]['blocker_code'] == 'nr01_missing_native_capability'"; then
    echo "  ✓ NR-01 missing native capability emits PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 missing native capability did not emit expected blocker"
    [ -f "$NR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$NR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

NR_CONTEXT_FINDINGS="$NR_CONTEXT_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$NR_CONTEXT_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| NR-01 | native replacement pruning candidate for native capability `repo-agent-core upstream capability intake contract` in `docs/pruning-continuity.md` scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"nr-evidence"} evidence_context={"primary_class":"historical_work","source":"closed_issue_474"} | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$NR_CONTEXT_FINDINGS" "$NR_CONTEXT_OUTPUT" >/dev/null \
    && [ ! -e "$NR_CONTEXT_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$NR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$NR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; row=d['blockers'][0]; assert row['row_id'] == 'NR-01'; assert row['blocker_code'] == 'nr01_non_active_evidence_context'; assert row['evidence_context'] == {'primary_class':'historical_work','source':'closed_issue_474'}; assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'nr-evidence'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ NR-01 non-active evidence_context fails closed with preserved metadata"
    PASS=$((PASS + 1))
else
    echo "  ✗ NR-01 non-active evidence_context did not fail closed with preserved metadata"
    [ -f "$NR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$NR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$NR_CONTEXT_OUTPUT/PATCH_PACK/NR-01-native-replacement-pruning-candidate.patch" ] && cat "$NR_CONTEXT_OUTPUT/PATCH_PACK/NR-01-native-replacement-pruning-candidate.patch"
    FAIL=$((FAIL + 1))
fi

HFR_FINDINGS="$HFR_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$HFR_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| HFR-01 | Hermes foreground receipt adoption guidance in `docs/hermes-receipts.md` scan_context={"scanner":"repo-auditor-as","scanned_files":200,"eligible_files":247,"scan_limit":200,"scan_limited":true} | 1 |
| HFR-01 | Hermes foreground receipt adoption guidance in `.agents/skills/metadata-target/SKILL.md` | 1 |
| HFR-01 | duplicate Hermes foreground receipt adoption guidance in `docs/hermes-receipts.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$HFR_FINDINGS" "$HFR_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for HFR-01 Hermes foreground receipt materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for HFR-01 Hermes foreground receipt materializer"
    FAIL=$((FAIL + 1))
fi

HFR_PATCH="$HFR_OUTPUT/PATCH_PACK/HFR-01-hermes-foreground-run-receipt.patch"
if [ -s "$HFR_PATCH" ] \
    && grep -Fq 'diff --git a/docs/hermes-receipts.md b/docs/hermes-receipts.md' "$HFR_PATCH" \
    && grep -Fq 'diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md' "$HFR_PATCH" \
    && grep -Fq '+## HERMES_FOREGROUND_RUN_RECEIPT' "$HFR_PATCH" \
    && grep -Fq 'foreground Hermes command' "$HFR_PATCH" \
    && grep -Fq 'exit status' "$HFR_PATCH" \
    && grep -Fq 'validation command' "$HFR_PATCH" \
    && ! grep -Fq 'controller' "$HFR_PATCH" \
    && ! grep -Fq 'scheduler' "$HFR_PATCH" \
    && ! grep -Fq 'daemon' "$HFR_PATCH" \
    && ! grep -Fq 'autofix loop' "$HFR_PATCH"; then
    echo "  ✓ HFR-01 patch materialized compact foreground receipt guidance only"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 patch missing compact foreground receipt guidance"
    [ -f "$HFR_PATCH" ] && cat "$HFR_PATCH"
    FAIL=$((FAIL + 1))
fi

if python3 - "$HFR_PATCH" <<'PY'
import sys

patch = open(sys.argv[1], encoding="utf-8").read()
marker = "diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md"
section = patch.split(marker, 1)[1].split("\ndiff --git ", 1)[0]
frontmatter = section.index("\n ---\n")
heading = section.index("\n # Metadata Target")
receipt = section.index("\n+## HERMES_FOREGROUND_RUN_RECEIPT")
assert frontmatter < heading < receipt
assert "\n+---\n" not in section
PY
then
    echo "  ✓ HFR-01 preserves YAML frontmatter before receipt guidance"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 did not preserve YAML frontmatter before receipt guidance"
    [ -f "$HFR_PATCH" ] && cat "$HFR_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$HFR_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ HFR-01 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

if [ -s "$HFR_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && python3 -c "import json; d=json.load(open('$HFR_OUTPUT/PATCH_PACK_METADATA.json')); rows=d['patches']; row=next(r for r in rows if r['target_file'] == 'docs/hermes-receipts.md'); assert row['row_id'] == 'HFR-01'; assert row['patch'] == 'HFR-01-hermes-foreground-run-receipt.patch'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scanned_files':200,'eligible_files':247,'scan_limit':200,'scan_limited':True}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ HFR-01 patch-pack metadata preserves inline scan_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 patch-pack metadata did not preserve inline scan_context"
    [ -f "$HFR_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$HFR_OUTPUT/PATCH_PACK_METADATA.json"
    FAIL=$((FAIL + 1))
fi

if [ -s "$HFR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$HFR_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 1; assert d['blocker_count'] == 1; assert d['blockers'][0]['blocker_code'] == 'hfr01_duplicate_target_file'"; then
    echo "  ✓ HFR-01 duplicate target row emits deterministic blocker"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 duplicate target row did not emit expected blocker"
    [ -f "$HFR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$HFR_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if git -C "$TARGET_REPO" diff --quiet; then
    echo "  ✓ HFR-01 materializer left target repo unmodified"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 materializer mutated target repo"
    git -C "$TARGET_REPO" diff --stat
    FAIL=$((FAIL + 1))
fi

HFR_BLOCKED_FINDINGS="$HFR_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$HFR_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| HFR-01 | Hermes foreground receipt adoption guidance in `docs/hermes-receipts.md` and `docs/hermes-receipts-grounded.md` | 2 |
| HFR-01 | broad Hermes foreground receipt adoption guidance in `docs/hermes-receipts.md` | 2 |
| HFR-01 | Hermes foreground receipt adoption guidance scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"missing-file"} | 1 |
| HFR-01 | Hermes foreground receipt adoption guidance in `.agents/skills/escaped/SKILL.md` | 1 |
| HFR-01 | Hermes foreground receipt adoption guidance in `docs/hermes-receipts-grounded.md` | 1 |
| HFR-01 | Hermes foreground receipt adoption guidance in `../../escape.md` | 1 |
| HFR-01 | Hermes foreground receipt adoption guidance in `.git/hooks/hermes.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$HFR_BLOCKED_FINDINGS" "$HFR_BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for blocked HFR-01 manifests"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for blocked HFR-01 manifests"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$HFR_BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); codes=[row['blocker_code'] for row in d['blockers']]; assert d['patches_generated'] == 0; assert d['blocker_count'] == 7; assert codes == ['hfr01_ambiguous_named_files','hfr01_broad_row_scope','hfr01_missing_named_file','hfr01_symlinked_target_file','hfr01_already_grounded','hfr01_unsafe_named_file','hfr01_unsafe_named_file']"; then
    echo "  ✓ HFR-01 unsafe rows emit PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 unsafe rows did not emit expected blockers"
    [ -f "$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if [ -s "$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); row=next(r for r in d['blockers'] if r['blocker_code'] == 'hfr01_missing_named_file'); assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'missing-file'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ HFR-01 blocker preserves inline scan_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ HFR-01 blocker did not preserve inline scan_context"
    [ -f "$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$HFR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

FGR_FINDINGS="$FGR_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$FGR_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| FGR-01 | foreground failure guidance recovery block in `docs/foreground-recovery.md` scan_context={"scanner":"repo-auditor-as","scanned_files":77,"eligible_files":111,"scan_limit":100,"scan_limited":true} evidence_context={"primary_class":"active_doc","source":"owner_issue_62"} | 1 |
| FGR-01 | foreground failure guidance recovery block in `.agents/skills/metadata-target/SKILL.md` | 1 |
| FGR-01 | duplicate foreground failure guidance recovery block in `docs/foreground-recovery.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$FGR_FINDINGS" "$FGR_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for FGR-01 foreground failure-guidance materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for FGR-01 foreground failure-guidance materializer"
    FAIL=$((FAIL + 1))
fi

FGR_PATCH="$FGR_OUTPUT/PATCH_PACK/FGR-01-foreground-failure-guidance-recovery.patch"
if [ -s "$FGR_PATCH" ] \
    && grep -Fq 'diff --git a/docs/foreground-recovery.md b/docs/foreground-recovery.md' "$FGR_PATCH" \
    && grep -Fq 'diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md' "$FGR_PATCH" \
    && grep -Fq '+## Foreground Failure Guidance / Recovery' "$FGR_PATCH" \
    && grep -Fq '+- Failure signal:' "$FGR_PATCH" \
    && grep -Fq '+- Recovery owner:' "$FGR_PATCH" \
    && grep -Fq '+- Recovery action:' "$FGR_PATCH" \
    && grep -Fq '+- Evidence receipt:' "$FGR_PATCH" \
    && grep -Fq '+- Bounded non-claims:' "$FGR_PATCH" \
    && grep -Fq 'does not authorize controllers, schedulers, queues, daemons, retry loops, retained reports, downstream mutation, or target mutation' "$FGR_PATCH"; then
    echo "  ✓ FGR-01 patch materialized compact foreground failure-guidance/recovery block only"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 patch missing compact foreground failure-guidance/recovery block"
    [ -f "$FGR_PATCH" ] && cat "$FGR_PATCH"
    FAIL=$((FAIL + 1))
fi

if python3 - "$FGR_PATCH" <<'PY'
import sys

patch = open(sys.argv[1], encoding="utf-8").read()
marker = "diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md"
section = patch.split(marker, 1)[1].split("\ndiff --git ", 1)[0]
frontmatter = section.index("\n ---\n")
heading = section.index("\n # Metadata Target")
fgr = section.index("\n+## Foreground Failure Guidance / Recovery")
assert frontmatter < heading < fgr
assert "\n+---\n" not in section
PY
then
    echo "  ✓ FGR-01 preserves YAML frontmatter before recovery guidance"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 did not preserve YAML frontmatter before recovery guidance"
    [ -f "$FGR_PATCH" ] && cat "$FGR_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$FGR_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ FGR-01 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

if [ -s "$FGR_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && python3 -c "import json; d=json.load(open('$FGR_OUTPUT/PATCH_PACK_METADATA.json')); rows=d['patches']; row=next(r for r in rows if r['target_file'] == 'docs/foreground-recovery.md'); assert row['row_id'] == 'FGR-01'; assert row['patch'] == 'FGR-01-foreground-failure-guidance-recovery.patch'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scanned_files':77,'eligible_files':111,'scan_limit':100,'scan_limited':True}; assert row['evidence_context'] == {'primary_class':'active_doc','source':'owner_issue_62'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ FGR-01 patch-pack metadata preserves inline scan_context/evidence_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 patch-pack metadata did not preserve inline scan_context"
    [ -f "$FGR_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$FGR_OUTPUT/PATCH_PACK_METADATA.json"
    FAIL=$((FAIL + 1))
fi

if [ -s "$FGR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$FGR_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 1; assert d['blocker_count'] == 1; assert d['blockers'][0]['blocker_code'] == 'fgr01_duplicate_target_file'"; then
    echo "  ✓ FGR-01 duplicate target row emits deterministic blocker"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 duplicate target row did not emit expected blocker"
    [ -f "$FGR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$FGR_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if git -C "$TARGET_REPO" diff --quiet; then
    echo "  ✓ FGR-01 materializer left target repo unmodified"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 materializer mutated target repo"
    git -C "$TARGET_REPO" diff --stat
    FAIL=$((FAIL + 1))
fi

FGR_BLOCKED_FINDINGS="$FGR_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$FGR_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| FGR-01 | foreground failure guidance recovery block in `docs/foreground-recovery.md` and `docs/foreground-recovery-grounded.md` | 2 |
| FGR-01 | broad foreground failure guidance recovery block in `docs/foreground-recovery.md` | 2 |
| FGR-01 | foreground failure guidance recovery block scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"missing-file"} | 1 |
| FGR-01 | foreground failure guidance recovery block in `.agents/skills/escaped/SKILL.md` | 1 |
| FGR-01 | foreground failure guidance recovery block in `docs/foreground-recovery-grounded.md` | 1 |
| FGR-01 | foreground failure guidance recovery block in `../../escape.md` | 1 |
| FGR-01 | foreground failure guidance recovery block in `.git/hooks/recovery.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$FGR_BLOCKED_FINDINGS" "$FGR_BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for blocked FGR-01 manifests"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for blocked FGR-01 manifests"
    FAIL=$((FAIL + 1))
fi

if ! compgen -G "$FGR_BLOCKED_OUTPUT/PATCH_PACK/*.patch" >/dev/null \
    && [ -s "$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); codes=[row['blocker_code'] for row in d['blockers']]; assert d['patches_generated'] == 0; assert d['blocker_count'] == 7; assert codes == ['fgr01_ambiguous_named_files','fgr01_broad_row_scope','fgr01_missing_named_file','fgr01_symlinked_target_file','fgr01_already_grounded','fgr01_unsafe_named_file','fgr01_unsafe_named_file']"; then
    echo "  ✓ FGR-01 unsafe rows emit PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 unsafe rows did not emit expected blockers"
    [ -f "$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if [ -s "$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); row=next(r for r in d['blockers'] if r['blocker_code'] == 'fgr01_missing_named_file'); assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'missing-file'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ FGR-01 blocker preserves inline scan_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 blocker did not preserve inline scan_context"
    [ -f "$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$FGR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

FGR_CONTEXT_FINDINGS="$FGR_CONTEXT_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$FGR_CONTEXT_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| FGR-01 | foreground failure guidance recovery block in `docs/foreground-recovery.md` scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"fgr-evidence"} evidence_context={"primary_class":"historical_work","source":"closed_issue_123"} | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$FGR_CONTEXT_FINDINGS" "$FGR_CONTEXT_OUTPUT" >/dev/null \
    && ! compgen -G "$FGR_CONTEXT_OUTPUT/PATCH_PACK/*.patch" >/dev/null \
    && [ -s "$FGR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$FGR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; row=d['blockers'][0]; assert row['row_id'] == 'FGR-01'; assert row['blocker_code'] == 'fgr01_non_active_evidence_context'; assert row['evidence_context'] == {'primary_class':'historical_work','source':'closed_issue_123'}; assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'fgr-evidence'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ FGR-01 non-active evidence_context fails closed with preserved metadata"
    PASS=$((PASS + 1))
else
    echo "  ✗ FGR-01 non-active evidence_context did not fail closed with preserved metadata"
    find "$FGR_CONTEXT_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$FGR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$FGR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$FGR_CONTEXT_OUTPUT/PATCH_PACK/FGR-01-foreground-failure-guidance-recovery.patch" ] && cat "$FGR_CONTEXT_OUTPUT/PATCH_PACK/FGR-01-foreground-failure-guidance-recovery.patch"
    FAIL=$((FAIL + 1))
fi

LR_FINDINGS="$LR_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$LR_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| LR-01 | foreground learning recovery block in `docs/learning-recovery.md` scan_context={"scanner":"repo-auditor-as","scanned_files":88,"eligible_files":120,"scan_limit":100,"scan_limited":true} evidence_context={"primary_class":"active_doc","source":"owner_issue_62"} | 1 |
| LR-01 | foreground learning recovery block in `.agents/skills/metadata-target/SKILL.md` | 1 |
| LR-01 | duplicate foreground learning recovery block in `docs/learning-recovery.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$LR_FINDINGS" "$LR_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for LR-01 foreground learning materializer"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for LR-01 foreground learning materializer"
    FAIL=$((FAIL + 1))
fi

LR_PATCH="$LR_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch"
if [ -s "$LR_PATCH" ] \
    && grep -Fq 'diff --git a/docs/learning-recovery.md b/docs/learning-recovery.md' "$LR_PATCH" \
    && grep -Fq 'diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md' "$LR_PATCH" \
    && grep -Fq '+## Learning / Recovery' "$LR_PATCH" \
    && grep -Fq '+- Decision changed:' "$LR_PATCH" \
    && grep -Fq '+- GitHub surface:' "$LR_PATCH" \
    && grep -Fq '+- Raw evidence:' "$LR_PATCH" \
    && grep -Fq '+- Optional GBrain slug:' "$LR_PATCH" \
    && grep -Fq '+- No-capture reason:' "$LR_PATCH" \
    && grep -Fq '+- Owner action:' "$LR_PATCH" \
    && grep -Fq '+- Bounded non-claims:' "$LR_PATCH" \
    && grep -Fq 'does not authorize background memory' "$LR_PATCH" \
    && grep -Fq 'schedulers, queues, daemons, controllers' "$LR_PATCH"; then
    echo "  ✓ LR-01 patch materialized compact foreground learning block only"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 patch missing compact foreground learning block"
    [ -f "$LR_PATCH" ] && cat "$LR_PATCH"
    FAIL=$((FAIL + 1))
fi

if python3 - "$LR_PATCH" <<'PY'
import sys

patch = open(sys.argv[1], encoding="utf-8").read()
marker = "diff --git a/.agents/skills/metadata-target/SKILL.md b/.agents/skills/metadata-target/SKILL.md"
section = patch.split(marker, 1)[1].split("\ndiff --git ", 1)[0]
frontmatter = section.index("\n ---\n")
heading = section.index("\n # Metadata Target")
learning = section.index("\n+## Learning / Recovery")
assert frontmatter < heading < learning
assert "\n+---\n" not in section
PY
then
    echo "  ✓ LR-01 preserves YAML frontmatter before learning guidance"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 did not preserve YAML frontmatter before learning guidance"
    [ -f "$LR_PATCH" ] && cat "$LR_PATCH"
    FAIL=$((FAIL + 1))
fi

if bash "$OPT_DIR/scripts/validate-patches.sh" "$TARGET_REPO" "$LR_OUTPUT/PATCH_PACK" >/dev/null; then
    echo "  ✓ LR-01 generated patch passes git apply --check"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 generated patch failed git apply --check"
    FAIL=$((FAIL + 1))
fi

if [ -s "$LR_OUTPUT/PATCH_PACK_METADATA.json" ] \
    && python3 -c "import json; d=json.load(open('$LR_OUTPUT/PATCH_PACK_METADATA.json')); rows=d['patches']; row=next(r for r in rows if r['target_file'] == 'docs/learning-recovery.md'); assert row['row_id'] == 'LR-01'; assert row['patch'] == 'LR-01-foreground-learning-recovery-block.patch'; assert row['scan_context'] == {'scanner':'repo-auditor-as','scanned_files':88,'eligible_files':120,'scan_limit':100,'scan_limited':True}; assert row['evidence_context'] == {'primary_class':'active_doc','source':'owner_issue_62'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ LR-01 patch-pack metadata preserves inline scan_context/evidence_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 patch-pack metadata did not preserve inline scan_context"
    [ -f "$LR_OUTPUT/PATCH_PACK_METADATA.json" ] && cat "$LR_OUTPUT/PATCH_PACK_METADATA.json"
    FAIL=$((FAIL + 1))
fi

if [ -s "$LR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$LR_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 1; assert d['blocker_count'] == 1; assert d['blockers'][0]['blocker_code'] == 'lr01_duplicate_target_file'"; then
    echo "  ✓ LR-01 duplicate target row emits deterministic blocker"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 duplicate target row did not emit expected blocker"
    [ -f "$LR_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$LR_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if git -C "$TARGET_REPO" diff --quiet; then
    echo "  ✓ LR-01 materializer left target repo unmodified"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 materializer mutated target repo"
    git -C "$TARGET_REPO" diff --stat
    FAIL=$((FAIL + 1))
fi

LR_BLOCKED_FINDINGS="$LR_BLOCKED_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$LR_BLOCKED_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| LR-01 | foreground learning recovery block in `docs/learning-recovery.md` and `docs/learning-recovery-grounded.md` | 2 |
| LR-01 | broad foreground learning recovery block in `docs/learning-recovery.md` | 2 |
| LR-01 | foreground learning recovery block scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"missing-file"} | 1 |
| LR-01 | foreground learning recovery block in `.agents/skills/escaped/SKILL.md` | 1 |
| LR-01 | foreground learning recovery block in `docs/learning-recovery-grounded.md` | 1 |
| LR-01 | foreground learning recovery block in `../../escape.md` | 1 |
| LR-01 | foreground learning recovery block in `.git/hooks/learning.md` | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$LR_BLOCKED_FINDINGS" "$LR_BLOCKED_OUTPUT" >/dev/null; then
    echo "  ✓ generate-patches.sh completed for blocked LR-01 manifests"
    PASS=$((PASS + 1))
else
    echo "  ✗ generate-patches.sh failed for blocked LR-01 manifests"
    FAIL=$((FAIL + 1))
fi

if [ ! -e "$LR_BLOCKED_OUTPUT/PATCH_PACK"/*.patch ] \
    && [ -s "$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); codes=[row['blocker_code'] for row in d['blockers']]; assert d['patches_generated'] == 0; assert d['blocker_count'] == 7; assert codes == ['lr01_ambiguous_named_files','lr01_broad_row_scope','lr01_missing_named_file','lr01_symlinked_target_file','lr01_already_grounded','lr01_unsafe_named_file','lr01_unsafe_named_file']"; then
    echo "  ✓ LR-01 unsafe rows emit PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 unsafe rows did not emit expected blockers"
    [ -f "$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

if [ -s "$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); row=next(r for r in d['blockers'] if r['blocker_code'] == 'lr01_missing_named_file'); assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'missing-file'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ LR-01 blocker preserves inline scan_context"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 blocker did not preserve inline scan_context"
    [ -f "$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$LR_BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

LR_CONTEXT_FINDINGS="$LR_CONTEXT_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$LR_CONTEXT_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| LR-01 | foreground learning recovery block in `docs/learning-recovery.md` scan_context={"scanner":"repo-auditor-as","scan_limited":true,"sample":"lr-evidence"} evidence_context={"primary_class":"debug_log","source":"runtime_log"} | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$LR_CONTEXT_FINDINGS" "$LR_CONTEXT_OUTPUT" >/dev/null \
    && ! compgen -G "$LR_CONTEXT_OUTPUT/PATCH_PACK/*.patch" >/dev/null \
    && [ -s "$LR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$LR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 1; row=d['blockers'][0]; assert row['row_id'] == 'LR-01'; assert row['blocker_code'] == 'lr01_non_active_evidence_context'; assert row['evidence_context'] == {'primary_class':'debug_log','source':'runtime_log'}; assert row['scan_context'] == {'scanner':'repo-auditor-as','scan_limited':True,'sample':'lr-evidence'}; assert any('scan-limited' in claim for claim in row['bounded_non_claims'])"; then
    echo "  ✓ LR-01 non-active evidence_context fails closed with preserved metadata"
    PASS=$((PASS + 1))
else
    echo "  ✗ LR-01 non-active evidence_context did not fail closed with preserved metadata"
    find "$LR_CONTEXT_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$LR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$LR_CONTEXT_OUTPUT/PATCHABILITY_BLOCKERS.json"
    [ -f "$LR_CONTEXT_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch" ] && cat "$LR_CONTEXT_OUTPUT/PATCH_PACK/LR-01-foreground-learning-recovery-block.patch"
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
trap 'rm -rf "$TARGET_REPO" "$EXTERNAL_FIXTURE" "$OUTPUT_DIR" "$PP_OUTPUT" "$PP3_OUTPUT" "$CAP_OUTPUT" "$LIMIT_OUTPUT" "$MIXED_OUTPUT" "$STALE_OUTPUT" "$FLEET_REPORT_ONLY_OUTPUT" "$REAL_OUTPUT" "$HS_OUTPUT" "$HS_BLOCKED_OUTPUT" "$PP4_RUNTIME_REPO" "$PP4_UNSAFE_OUTPUT" "$AUDIT_INPUT" "$PIPELINE_OUTPUT" "$BLOCKED_OUTPUT" "$BLOCKED_AUDIT_INPUT" "$BLOCKED_PIPELINE_OUTPUT"' EXIT
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
    && python3 -c "import json; d=json.load(open('$BLOCKED_OUTPUT/PATCHABILITY_BLOCKERS.json')); assert d['patches_generated'] == 0; assert d['blocker_count'] == 5; assert {row['row_id'] for row in d['blockers']} == {'TP-01','TP-02','TP-03','TP-04','TP-05'}; routes={}; [routes.__setitem__(row['route_class'], routes.get(row['route_class'], 0) + 1) for row in d['blockers']]; assert routes == {'unsupported_or_unpatchable_recommendation': 2, 'manual_target_owner_implementation': 2, 'unsafe_or_insufficient_authorization': 1}; assert all(row.get('route_reason') for row in d['blockers'])"; then
    echo "  ✓ unsupported transcript pilot manifest emits classified PATCHABILITY_BLOCKERS.json"
    PASS=$((PASS + 1))
else
    echo "  ✗ unsupported transcript pilot manifest did not emit classified PATCHABILITY_BLOCKERS.json as expected"
    FAIL=$((FAIL + 1))
fi

ROUTE_OUTPUT="$(mktemp -d)"
ROUTE_FINDINGS="$ROUTE_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$ROUTE_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| RC-01 | Missing patch_materializer bridge for custom adapter | 1 |
| RC-02 | Manual target-owner implementation for settings integration | 2 |
| RC-03 | Unsupported semantic recommendation requiring human rewrite | 1 |
| RC-04 | Read-only protected file change without approval | 1 |
| RC-05 | Cleanup contract conflict: delete stale doc but keep preserved owner reference | 1 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$ROUTE_FINDINGS" "$ROUTE_OUTPUT" >/dev/null \
    && [ -s "$ROUTE_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 -c "import json; d=json.load(open('$ROUTE_OUTPUT/PATCHABILITY_BLOCKERS.json')); routes={}; [routes.__setitem__(row['route_class'], routes.get(row['route_class'], 0) + 1) for row in d['blockers']]; assert routes == {'materializer_missing': 1, 'manual_target_owner_implementation': 1, 'unsupported_or_unpatchable_recommendation': 1, 'unsafe_or_insufficient_authorization': 1, 'contradictory_cleanup_contract': 1}; assert {row['blocker_code'] for row in d['blockers']} == {'unsupported_manifest_row'}"; then
    echo "  ✓ unsupported manifest rows emit all route classes without changing blocker_code"
    PASS=$((PASS + 1))
else
    echo "  ✗ unsupported manifest rows did not emit expected route classes"
    [ -f "$ROUTE_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$ROUTE_OUTPUT/PATCHABILITY_BLOCKERS.json"
    FAIL=$((FAIL + 1))
fi

FLEET_REPORT_ONLY_FINDINGS="$FLEET_REPORT_ONLY_OUTPUT/OPTIMIZATION_PLAN.md"
cat > "$FLEET_REPORT_ONLY_FINDINGS" <<'EOF'
# Optimization Plan

## Patch Manifest

| Patch # | Findings | Files touched |
|---|---|---:|
| closure_signal_integrity_gap | AS-54 closure signal integrity is a keep-candidate governance/meta friction class, not a target-file patch. | 0 |
| review_ergonomics_working_memory_lightness_gap | AS-55 review ergonomics and working-memory lightness is a governance/meta friction class from oversized state/review timeout signals. | 0 |
| validation_integrity_format_tracking_gap | Validation integrity format tracking is contract-backed/report-only with no live drift claim. | 0 |
EOF

if bash "$OPT_DIR/scripts/generate-patches.sh" "$TARGET_REPO" "$FLEET_REPORT_ONLY_FINDINGS" "$FLEET_REPORT_ONLY_OUTPUT" >/dev/null \
    && ! compgen -G "$FLEET_REPORT_ONLY_OUTPUT/PATCH_PACK/*.patch" >/dev/null \
    && [ -s "$FLEET_REPORT_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" ] \
    && python3 - "$FLEET_REPORT_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

expected = {
    "closure_signal_integrity_gap",
    "review_ergonomics_working_memory_lightness_gap",
    "validation_integrity_format_tracking_gap",
}
assert data["patches_generated"] == 0
assert data["blocker_count"] == 3
rows = {row["row_id"]: row for row in data["blockers"]}
assert set(rows) == expected
for row in rows.values():
    assert row["blocker_code"] == "unsupported_or_unpatchable_recommendation"
    assert row["route_class"] == "unsupported_or_unpatchable_recommendation"
    assert row["route_reason"]
    assert "report-only" in row["reason"]
    assert "materializer" in row["reason"]
PY
then
    echo "  ✓ fleet governance/meta friction families stay report-only patchability blockers"
    PASS=$((PASS + 1))
else
    echo "  ✗ fleet governance/meta friction families did not stay report-only"
    find "$FLEET_REPORT_ONLY_OUTPUT" -maxdepth 3 -type f -print
    [ -f "$FLEET_REPORT_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json" ] && cat "$FLEET_REPORT_ONLY_OUTPUT/PATCHABILITY_BLOCKERS.json"
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

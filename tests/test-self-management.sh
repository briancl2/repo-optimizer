#!/usr/bin/env bash
# tests/test-self-management.sh — Test self-management infrastructure
#
# Verifies work contracts, check, and grader are functional.
# Per spec 054 S14.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ── Test 1: LEARNINGS.md exists ──────────────────────────────────────
echo "=== Self-Management Infrastructure Tests ==="
check "LEARNINGS.md exists" "true" "$([ -f LEARNINGS.md ] && echo true || echo false)"

# ── Test 2: Constitution v2 has self-management section ──────────────
check "Constitution has self-management" "true" "$(grep -q 'Self-Management' .specify/memory/constitution.md 2>/dev/null && echo true || echo false)"

# ── Test 3: Constitution preserves domain principles 1-6 ─────────────
check "Constitution has Auditor-First" "true" "$(grep -q 'Auditor-First' .specify/memory/constitution.md 2>/dev/null && echo true || echo false)"
check "Constitution has Critic-Mandatory" "true" "$(grep -q 'Critic-Mandatory' .specify/memory/constitution.md 2>/dev/null && echo true || echo false)"
check "Constitution has Patch Validation" "true" "$(grep -q 'Patch Validation' .specify/memory/constitution.md 2>/dev/null && echo true || echo false)"

# ── Test 4: Makefile has required targets ────────────────────────────
check "Makefile has check target" "true" "$(grep -q '^check:' Makefile 2>/dev/null && echo true || echo false)"
check "Makefile has work target" "true" "$(grep -q '^work:' Makefile 2>/dev/null && echo true || echo false)"
check "Makefile has work-close target" "true" "$(grep -q '^work-close:' Makefile 2>/dev/null && echo true || echo false)"

# ── Test 5: Scripts exist and are executable ─────────────────────────
check "check.sh exists" "true" "$([ -f scripts/check.sh ] && echo true || echo false)"
check "work-init.sh exists" "true" "$([ -f scripts/work-init.sh ] && echo true || echo false)"
check "work-close.sh exists" "true" "$([ -f scripts/work-close.sh ] && echo true || echo false)"
check "score-session.sh exists" "true" "$([ -f scripts/score-session.sh ] && echo true || echo false)"
check "pre-commit-hook.sh exists" "true" "$([ -f scripts/pre-commit-hook.sh ] && echo true || echo false)"

# ── Test 6: Schema exists and is valid JSON ──────────────────────────
check "OPERATING_MODEL_SCORECARD schema exists" "true" "$([ -f schemas/OPERATING_MODEL_SCORECARD.schema.json ] && echo true || echo false)"
check "Schema is valid JSON" "true" "$(python3 -c 'import json; json.load(open("schemas/OPERATING_MODEL_SCORECARD.schema.json"))' 2>/dev/null && echo true || echo false)"

# ── Test 7: Invocation contract exists ───────────────────────────────
check "Invocation contract exists" "true" "$([ -f docs/invocation-contract.md ] && echo true || echo false)"

# ── Test 8: No "0 LLM tokens" occurrences ───────────────────────────
set +o pipefail
ZERO_LLM_COUNT=$(grep -ri "0 LLM tokens" scripts/ .agents/ AGENTS.md .specify/ 2>/dev/null | wc -l | tr -d ' ')
set -o pipefail
check "0 occurrences of '0 LLM tokens'" "0" "$ZERO_LLM_COUNT"

# ── Test 9: Agent file references invocation contract ────────────────
check "Agent file references invocation contract" "true" "$(grep -q 'invocation-contract' .agents/repo-optimizer.agent.md 2>/dev/null && echo true || echo false)"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Self-Management Test Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "  VERDICT: PASS"
    exit 0
else
    echo "  VERDICT: FAIL"
    exit 1
fi

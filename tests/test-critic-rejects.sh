#!/usr/bin/env bash
# test-critic-rejects.sh — Verify critic must reject ≥1 finding.
# This is a structural test — verifies the critic agent definition includes
# the rejection requirement.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

echo "=== Critic Rejection Requirement Test ==="

# Check critic agent exists
CRITIC="$OPT_DIR/.agents/repo-optimizer-critic.agent.md"
if [ ! -f "$CRITIC" ]; then
    echo "  ✗ repo-optimizer-critic.agent.md not found"
    exit 1
fi

# Check it mentions rejection requirement
if grep -qi "reject.*1\|MUST reject" "$CRITIC"; then
    echo "  ✓ Critic requires ≥1 rejection"
    PASS=$((PASS + 1))
else
    echo "  ✗ Critic does not mention rejection requirement"
    FAIL=$((FAIL + 1))
fi

# Check anti-goals are listed
if grep -qi "metric.chasing\|delta.hack\|premature.deletion" "$CRITIC"; then
    echo "  ✓ Anti-goals defined"
    PASS=$((PASS + 1))
else
    echo "  ✗ Anti-goals not defined"
    FAIL=$((FAIL + 1))
fi

# Check verdict format
if grep -q "VERDICT: APPROVED" "$CRITIC" && grep -q "VERDICT: REJECTED" "$CRITIC"; then
    echo "  ✓ Verdict format specified"
    PASS=$((PASS + 1))
else
    echo "  ✗ Verdict format not specified"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "  VERDICT: FAIL"
    exit 1
fi
echo "  VERDICT: PASS"

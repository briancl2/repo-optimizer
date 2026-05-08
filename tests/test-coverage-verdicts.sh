#!/usr/bin/env bash
# test-coverage-verdicts.sh — Coverage-aware optimizer verdict tests.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$OPT_DIR/work/test-coverage-verdicts"
TARGET_REPO="$TEST_ROOT/target-repo"
AUDIT_DIR="$TEST_ROOT/audit"
OUTPUT_DIR="$TEST_ROOT/output"
PASS=0
FAIL=0

trap 'rm -rf "$TEST_ROOT"' EXIT
rm -rf "$TEST_ROOT"
mkdir -p "$TARGET_REPO" "$AUDIT_DIR"

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

json_field() {
    python3 -c 'import functools,json,sys; data=json.load(open(sys.argv[1])); value=functools.reduce(lambda acc,key: acc.get(key) if isinstance(acc,dict) else None, sys.argv[2].split("."), data); print("true" if value is True else "false" if value is False else "" if value is None else value)' "$1" "$2"
}

json_contains() {
    python3 -c 'import functools,json,sys; data=json.load(open(sys.argv[1])); value=functools.reduce(lambda acc,key: acc.get(key) if isinstance(acc,dict) else None, sys.argv[2].split("."), data); print("true" if sys.argv[3] in (value or []) else "false")' "$1" "$2" "$3"
}

echo "=== Coverage Verdict Tests ==="

printf '%s\n' '# Target Repo' 'Optimizer coverage verdict fixture.' > "$TARGET_REPO/AGENTS.md"
git -C "$TARGET_REPO" init -q
git -C "$TARGET_REPO" config user.email "test@example.com"
git -C "$TARGET_REPO" config user.name "Test User"
git -C "$TARGET_REPO" add AGENTS.md
git -C "$TARGET_REPO" commit -q -m "init target fixture"

{
    printf '%s\n' '{'
    printf '%s\n' '  "composite": 50,'
    printf '%s\n' '  "dimensions": {'
    printf '%s\n' '    "D1_governance": {"score": 10, "max": 20},'
    printf '%s\n' '    "D2_surface_health": {"score": 8, "max": 20},'
    printf '%s\n' '    "D3_skill_maturity": {"score": 12, "max": 20}'
    printf '%s\n' '  },'
    printf '%s\n' '  "tier2_warnings": {"warnings": []}'
    printf '%s\n' '}'
} > "$AUDIT_DIR/SCORECARD.json"
printf '%s\n' '# Audit Report' '' 'Synthetic completed audit report.' > "$AUDIT_DIR/AUDIT_REPORT.md"
printf '%s\n' '{' '  "status": "completed"' '}' > "$AUDIT_DIR/AUDIT_RUN_RECEIPT.json"

FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN"
{
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' 'prompt=""'
    printf '%s\n' 'while [ "$#" -gt 0 ]; do'
    printf '%s\n' '    case "$1" in'
    printf '%s\n' '        -p)'
    printf '%s\n' '            prompt="$2"'
    printf '%s\n' '            shift 2'
    printf '%s\n' '            ;;'
    printf '%s\n' '        *)'
    printf '%s\n' '            shift'
    printf '%s\n' '            ;;'
    printf '%s\n' '    esac'
    printf '%s\n' 'done'
    printf '%s\n' 'case "$prompt" in'
    printf '%s\n' '    *".agents/repo-optimizer-critic.agent.md"*)'
    printf '%s\n' '        printf '\''%s\n'\'' '\''{"type":"assistant.message","data":{"content":"# Critic\n\n[VERDICT: APPROVED]\n[VERDICT: REJECTED]\n[VERDICT: DOWNGRADED]\n","toolRequests":[]}}'\'''
    printf '%s\n' '        ;;'
    printf '%s\n' '    *".agents/repo-optimizer-synthesis.agent.md"*)'
    printf '%s\n' '        printf '\''%s\n'\'' '\''{"type":"assistant.message","data":{"content":"# Optimization Plan\n\n## Approved Findings\n\n### Finding 1: Coverage fixture (APPROVED)\n- File: `AGENTS.md`\n- Recommendation: keep the fixture.\n","toolRequests":[]}}'\'''
    printf '%s\n' '        ;;'
    printf '%s\n' '    *".agents/extraction-optimizer.agent.md"*|*".agents/standardization-optimizer.agent.md"*)'
    printf '%s\n' '        exit 1'
    printf '%s\n' '        ;;'
    printf '%s\n' '    *"-optimizer.agent.md"*)'
    printf '%s\n' '        printf '\''%s\n'\'' '\''{"type":"tool.execution_complete","data":{"toolCallId":"tooluse_out","success":true,"result":{"content":"| Rank | Severity | Finding | File | Token Impact | Evidence Quote | Verification |\n|---:|---|---|---|---|---|---|\n| 1 | HIGH | Coverage-aware test finding. | AGENTS.md | ~10 | \"fixture\" | `test -f AGENTS.md` |\n"}}}'\'''
    printf '%s\n' '        ;;'
    printf '%s\n' '    *)'
    printf '%s\n' '        echo "unexpected prompt: $prompt" >&2'
    printf '%s\n' '        exit 1'
    printf '%s\n' '        ;;'
    printf '%s\n' 'esac'
} > "$FAKE_BIN/copilot"
chmod +x "$FAKE_BIN/copilot"

if PATH="$FAKE_BIN:$PATH" OPTIMIZER_TIMEOUT=30 OPTIMIZER_PROGRESS_INTERVAL=1 \
    bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$AUDIT_DIR" "$OUTPUT_DIR" > "$TEST_ROOT/run.log" 2>&1; then
    echo "  PASS: optimizer completed with 2/4 discovery domains"
    PASS=$((PASS + 1))
else
    echo "  FAIL: optimizer failed with 2/4 discovery domains"
    cat "$TEST_ROOT/run.log"
    FAIL=$((FAIL + 1))
fi

SCORECARD="$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json"
RUNTIME="$OUTPUT_DIR/RUNTIME_RECEIPTS.json"
PLAN="$OUTPUT_DIR/OPTIMIZATION_PLAN.md"

check "coverage verdict is pass_with_coverage_gap" "pass_with_coverage_gap" "$(json_field "$SCORECARD" "coverage_verdict")"
check "runtime coverage verdict matches" "pass_with_coverage_gap" "$(json_field "$RUNTIME" "coverage_verdict")"
check "completed domains count" "2" "$(json_field "$SCORECARD" "discovery_coverage.completed_count")"
check "missing domains count" "2" "$(json_field "$SCORECARD" "discovery_coverage.missing_count")"
check "missing extraction domain recorded" "true" "$(json_contains "$SCORECARD" "discovery_coverage.missing_domains" "extraction")"
check "missing standardization domain recorded" "true" "$(json_contains "$SCORECARD" "discovery_coverage.missing_domains" "standardization")"
check "recommendation strength constrained" "limited" "$(json_field "$SCORECARD" "recommendation_strength")"
check "count agreement recorded" "true" "$(json_field "$SCORECARD" "finding_count_agreement.matches_scorecard")"

if grep -Fq '## Coverage Verdict' "$PLAN" \
    && grep -Fq 'Machine finding counts: total=2; approved=1; rejected=1; downgraded=1.' "$PLAN" \
    && grep -Fq 'Complete discovery coverage was not observed' "$PLAN"; then
    echo "  PASS: plan carries deterministic coverage counts and non-claims"
    PASS=$((PASS + 1))
else
    echo "  FAIL: plan missing deterministic coverage counts or non-claims"
    cat "$PLAN"
    FAIL=$((FAIL + 1))
fi

if python3 "$OPT_DIR/scripts/coverage-verdict.py" check-counts --output-dir "$OUTPUT_DIR" >/dev/null; then
    echo "  PASS: count agreement checker accepts matching plan"
    PASS=$((PASS + 1))
else
    echo "  FAIL: count agreement checker rejected matching plan"
    FAIL=$((FAIL + 1))
fi

MISMATCH="$TEST_ROOT/mismatch"
cp -R "$OUTPUT_DIR" "$MISMATCH"
python3 -c 'import pathlib,sys; path=pathlib.Path(sys.argv[1]); text=path.read_text(encoding="utf-8"); path.write_text(text.replace("total=2;", "total=99;", 1), encoding="utf-8")' "$MISMATCH/OPTIMIZATION_PLAN.md"
if python3 "$OPT_DIR/scripts/coverage-verdict.py" check-counts --output-dir "$MISMATCH" >/dev/null 2>&1; then
    echo "  FAIL: count agreement checker accepted mismatched plan"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: count agreement checker rejects mismatched plan"
    PASS=$((PASS + 1))
fi

echo ""
echo "=== Coverage Verdict Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

#!/usr/bin/env bash
# test-target-policy-context.sh — deterministic tests for pointer-only policy context.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$OPT_DIR/work/test-target-policy-context-$$"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0
TOTAL=0

pass() {
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS ($TOTAL): $1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL ($TOTAL): $1"
}

expect_file_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if grep -Fq "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label"
        [ -f "$file" ] && sed -n '1,120p' "$file"
    fi
}

expect_json_scalar() {
    local file="$1"
    local path="$2"
    local expected="$3"
    local label="$4"
    local actual
    actual="$(python3 -c 'import functools,json,sys; data=json.load(open(sys.argv[1])); value=functools.reduce(lambda acc,key: acc.get(key) if isinstance(acc,dict) else None, sys.argv[2].split("."), data); print("true" if value is True else "false" if value is False else "" if value is None else value)' "$file" "$path")"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected $expected, got $actual)"
    fi
}

expect_policy_path() {
    local file="$1"
    local policy_path="$2"
    local label="$3"
    if python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); paths=[item["path"] for item in data["target_policy_context"]["policy_files"]]; raise SystemExit(0 if sys.argv[2] in paths else 1)' "$file" "$policy_path"; then
        pass "$label"
    else
        fail "$label"
        python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print([item["path"] for item in data["target_policy_context"]["policy_files"]])' "$file"
    fi
}

expect_policy_metadata() {
    local file="$1"
    local policy_path="$2"
    local label="$3"
    if python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); item=next((row for row in data["target_policy_context"]["policy_files"] if row["path"] == sys.argv[2]), {}); ok=item.get("policy_family") == "model_routing" and item.get("policy_role") == "target-local allowlist pointer" and item.get("file_type") == "json" and item.get("parse_status") == "parsed_json" and "description" in item.get("evidence_keys", []); raise SystemExit(0 if ok else 1)' "$file" "$policy_path"; then
        pass "$label"
    else
        fail "$label"
        python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(json.dumps(data["target_policy_context"], indent=2))' "$file"
    fi
}

init_target_repo() {
    local repo="$1"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    git -C "$repo" add .
    git -C "$repo" commit -q -m "init target fixture"
}

write_audit_fixture() {
    local audit_dir="$1"
    mkdir -p "$audit_dir"
    printf '%s\n' \
        '{' \
        '  "composite": 50,' \
        '  "dimensions": {' \
        '    "D1_governance": {"score": 10, "max": 20},' \
        '    "D2_surface_health": {"score": 5, "max": 20},' \
        '    "D3_velocity": {"score": 10, "max": 20},' \
        '    "D4_organicity": {"score": 15, "max": 20},' \
        '    "D5_trajectory": {"score": 10, "max": 20}' \
        '  },' \
        '  "tier2_warnings": {"warnings": []}' \
        '}' > "$audit_dir/SCORECARD.json"
    printf '%s\n' '# Synthetic Audit Report' '' 'Completed audit fixture for target policy context tests.' > "$audit_dir/AUDIT_REPORT.md"
    printf '%s\n' '{' '  "status": "completed"' '}' > "$audit_dir/AUDIT_RUN_RECEIPT.json"
}

echo "=== Target Policy Context Tests ==="

AUDIT_DIR="$TEST_DIR/audit"
write_audit_fixture "$AUDIT_DIR"

echo ""
echo "--- Policy-present target ---"
POLICY_REPO="$TEST_DIR/repo-policy-present"
mkdir -p "$POLICY_REPO/system/policy/allowlists" "$POLICY_REPO/.github" "$POLICY_REPO/docs"
printf '%s\n' '# Target Repo' > "$POLICY_REPO/AGENTS.md"
printf '%s\n' \
    '{' \
    '  "description": "Agent model pins are not expected unless a model-specific rationale is recorded.",' \
    '  "allowed_defaults": ["runtime-session-defaults"],' \
    '  "rationale_required": true' \
    '}' > "$POLICY_REPO/system/policy/allowlists/model_routing.json"
printf '%s\n' 'title: Repository Policy' 'description: GitHub policy pointer' > "$POLICY_REPO/.github/repo-policy.yml"
printf '%s\n' '# Model Policy' '' 'Runtime defaults own model selection.' > "$POLICY_REPO/docs/model-policy.md"
printf '%s\n' '{' '  "title": "Root Agent Policy"' '}' > "$POLICY_REPO/agent-policy.json"
printf '%s\n' '# Not Policy' > "$POLICY_REPO/docs/guide.md"
init_target_repo "$POLICY_REPO"

OUTPUT_POLICY="$TEST_DIR/out-policy"
if OPTIMIZER_PREFLIGHT_ONLY=true bash "$OPT_DIR/scripts/repo-optimizer.sh" "$POLICY_REPO" "$AUDIT_DIR" "$OUTPUT_POLICY" > "$TEST_DIR/policy-run.log" 2>&1; then
    pass "policy-present optimizer pre-flight completed"
else
    fail "policy-present optimizer pre-flight completed"
    sed -n '1,160p' "$TEST_DIR/policy-run.log"
fi

PREFLIGHT_POLICY="$OUTPUT_POLICY/pre-flight.json"
CONTEXT_POLICY="$OUTPUT_POLICY/runtime-safe-target-context.md"
POLICY_JSON="$OUTPUT_POLICY/target-policy-context.json"

expect_json_scalar "$PREFLIGHT_POLICY" "target_policy_context.discovery_mode" "pointer_only" "pre-flight discovery mode is pointer-only"
expect_json_scalar "$PREFLIGHT_POLICY" "target_policy_context.policy_files_count" "4" "pre-flight policy file count"
expect_json_scalar "$PREFLIGHT_POLICY" "target_policy_context.policy_context_non_claim" "listed files are for optimizer context and not fully interpreted" "pre-flight non-claim recorded"
expect_policy_path "$PREFLIGHT_POLICY" "system/policy/allowlists/model_routing.json" "system policy pointer listed"
expect_policy_path "$PREFLIGHT_POLICY" ".github/repo-policy.yml" ".github policy pointer listed"
expect_policy_path "$PREFLIGHT_POLICY" "docs/model-policy.md" "docs policy pointer listed"
expect_policy_path "$PREFLIGHT_POLICY" "agent-policy.json" "root policy pointer listed"
expect_policy_metadata "$PREFLIGHT_POLICY" "system/policy/allowlists/model_routing.json" "model routing metadata is compact and parsed"
expect_file_contains "$CONTEXT_POLICY" "## Target Policy Pointers" "runtime context has Target Policy Pointers section"
expect_file_contains "$CONTEXT_POLICY" "system/policy/allowlists/model_routing.json" "runtime context lists system policy pointer"
expect_file_contains "$CONTEXT_POLICY" "Pointer-only: listed files are for optimizer context and not fully interpreted." "runtime context carries non-claim"
expect_json_scalar "$POLICY_JSON" "policy_files_count" "4" "standalone target-policy-context artifact mirrors count"

if python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); paths=[item["path"] for item in data["target_policy_context"]["policy_files"]]; raise SystemExit(0 if "docs/guide.md" not in paths else 1)' "$PREFLIGHT_POLICY"; then
    pass "non-policy docs file is not listed"
else
    fail "non-policy docs file is not listed"
fi

echo ""
echo "--- No-policy target ---"
NO_POLICY_REPO="$TEST_DIR/repo-no-policy"
mkdir -p "$NO_POLICY_REPO"
printf '%s\n' '# Target Repo' > "$NO_POLICY_REPO/AGENTS.md"
printf '%s\n' '# README' > "$NO_POLICY_REPO/README.md"
init_target_repo "$NO_POLICY_REPO"

OUTPUT_NO_POLICY="$TEST_DIR/out-no-policy"
if OPTIMIZER_PREFLIGHT_ONLY=true bash "$OPT_DIR/scripts/repo-optimizer.sh" "$NO_POLICY_REPO" "$AUDIT_DIR" "$OUTPUT_NO_POLICY" > "$TEST_DIR/no-policy-run.log" 2>&1; then
    pass "no-policy optimizer pre-flight completed"
else
    fail "no-policy optimizer pre-flight completed"
    sed -n '1,160p' "$TEST_DIR/no-policy-run.log"
fi

PREFLIGHT_NO_POLICY="$OUTPUT_NO_POLICY/pre-flight.json"
CONTEXT_NO_POLICY="$OUTPUT_NO_POLICY/runtime-safe-target-context.md"
expect_json_scalar "$PREFLIGHT_NO_POLICY" "budget_tier" "full" "no-policy budget tier preserved"
expect_json_scalar "$PREFLIGHT_NO_POLICY" "file_count" "2" "no-policy file count preserved"
expect_json_scalar "$PREFLIGHT_NO_POLICY" "target_policy_context.discovery_mode" "pointer_only" "no-policy discovery mode still pointer-only"
expect_json_scalar "$PREFLIGHT_NO_POLICY" "target_policy_context.policy_files_count" "0" "no-policy count is zero"
if python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); raise SystemExit(0 if data["target_policy_context"]["policy_files"] == [] else 1)' "$PREFLIGHT_NO_POLICY"; then
    pass "no-policy list is empty"
else
    fail "no-policy list is empty"
fi
expect_file_contains "$CONTEXT_NO_POLICY" "| none | n/a | n/a | n/a | n/a | n/a |" "no-policy runtime context renders none row"

echo ""
echo "--- Prompt policy categories ---"
for category in \
    target_policy_explained \
    target_policy_conflict_downgraded \
    target_policy_absent_generic_allowed \
    stronger_target_authority_cited \
    policy_pointer_ambiguous \
    unclassified_requires_amendment; do
    expect_file_contains "$OPT_DIR/.agents/standardization-optimizer.agent.md" "$category" "standardization prompt includes $category"
    expect_file_contains "$OPT_DIR/.agents/repo-optimizer-critic.agent.md" "$category" "critic prompt includes $category"
done

echo ""
echo "=== Target Policy Context Tests: $PASS/$TOTAL passed ==="
if [ "$FAIL" -gt 0 ]; then
    echo "  FAILED: $FAIL tests"
    exit 1
fi

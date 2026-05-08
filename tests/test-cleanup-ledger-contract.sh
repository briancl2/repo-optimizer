#!/usr/bin/env bash
# test-cleanup-ledger-contract.sh — P5 cleanup-ledger contract tests.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$OPT_DIR/work/test-cleanup-ledger-contract"
PASS=0
FAIL=0

trap 'rm -rf "$TEST_ROOT"' EXIT
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"

pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

json_field() {
    python3 -c 'import functools,json,sys; data=json.load(open(sys.argv[1])); value=functools.reduce(lambda acc,key: acc.get(key) if isinstance(acc,dict) else None, sys.argv[2].split("."), data); print("true" if value is True else "false" if value is False else "" if value is None else value)' "$1" "$2"
}

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected=$expected, got=$actual)"
    fi
}

write_minimal_output() {
    local output="$1"
    mkdir -p "$output"
    printf '%s\n' \
        '{' \
        '  "findings_total": 0,' \
        '  "findings_approved": 0,' \
        '  "findings_rejected": 0,' \
        '  "patches_generated": 0,' \
        '  "patches_valid": 0,' \
        '  "expected_delta": 0,' \
        '  "meta": {}' \
        '}' > "$output/OPTIMIZATION_SCORECARD.json"
    printf '%s\n' '{' '  "schema_version": "1.0.0",' '  "phases": {}' '}' > "$output/RUNTIME_RECEIPTS.json"
    printf '%s\n' '# Optimization Plan' > "$output/OPTIMIZATION_PLAN.md"
}

echo "=== Cleanup Ledger Contract Tests ==="

NO_FINDINGS="$TEST_ROOT/no-findings"
write_minimal_output "$NO_FINDINGS"
python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$NO_FINDINGS" --patch-mode false
check "no findings cleanup contract is present" "0" "$(json_field "$NO_FINDINGS/OPTIMIZATION_SCORECARD.json" "cleanup_contract.findings_with_cleanup_class")"
check "no findings destructive count is zero" "0" "$(json_field "$NO_FINDINGS/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_total")"
if grep -Fq '## Cleanup Safety Summary' "$NO_FINDINGS/OPTIMIZATION_PLAN.md"; then
    pass "plan carries cleanup safety summary"
else
    fail "plan carries cleanup safety summary"
fi

BLOCKED="$TEST_ROOT/blocked"
write_minimal_output "$BLOCKED"
printf '%s\n' '# Optimization Plan' '' '- Recommendation: delete `archive/old.md` as cleanup.' > "$BLOCKED/OPTIMIZATION_PLAN.md"
python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$BLOCKED" --patch-mode false
check "destructive delete is classified" "1" "$(json_field "$BLOCKED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_total")"
check "unsafe destructive delete is blocked" "1" "$(json_field "$BLOCKED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_blocked")"
check "missing owner boundary counted" "1" "$(json_field "$BLOCKED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.missing_owner_boundary_count")"
check "missing keep set counted" "1" "$(json_field "$BLOCKED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.missing_keep_set_count")"
python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$BLOCKED" --patch-mode false
check "cleanup summary is idempotent on reapply" "1" "$(json_field "$BLOCKED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_total")"

METADATA_LINE="$TEST_ROOT/metadata-line"
write_minimal_output "$METADATA_LINE"
printf '%s\n' \
    '[VERDICT: REJECTED] unsafe cleanup' \
    'Cleanup metadata: cleanup_action_class=delete; cleanup_action_scope=single_file; destructive_action=true; target_paths=src/old.py; protected_keep_paths=none; keep_set_evidence=none; owner_boundary_class=target_owned; owner_boundary_evidence=none; authorization_status=blocked_unknown; evidence_threshold=insufficient' \
    > "$METADATA_LINE/critic-verdicts.md"
python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$METADATA_LINE" --patch-mode false
check "cleanup metadata line parses target path" "1" "$(json_field "$METADATA_LINE/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_total")"
check "cleanup metadata none keep-set is missing" "1" "$(json_field "$METADATA_LINE/OPTIMIZATION_SCORECARD.json" "cleanup_contract.missing_keep_set_count")"
check "cleanup metadata none owner boundary is missing" "1" "$(json_field "$METADATA_LINE/OPTIMIZATION_SCORECARD.json" "cleanup_contract.missing_owner_boundary_count")"

AUTHORIZED="$TEST_ROOT/authorized"
write_minimal_output "$AUTHORIZED"
printf '%s\n' \
    '[' \
    '  {' \
    '    "source": "test",' \
    '    "source_text": "delete generated cache",' \
    '    "cleanup_action_class": "delete",' \
    '    "cleanup_action_scope": "generated_artifact",' \
    '    "destructive_action": true,' \
    '    "target_paths": ["build/cache.tmp"],' \
    '    "protected_keep_paths": ["src/main.py"],' \
    '    "keep_set_evidence": ["src/main.py imported by tests"],' \
    '    "owner_boundary_class": "generated_or_cache",' \
    '    "owner_boundary_evidence": "README says build/ is generated cache",' \
    '    "authorization_status": "not_required",' \
    '    "evidence_threshold": "unreferenced_with_keep_set"' \
    '  }' \
    ']' > "$AUTHORIZED/CLEANUP_FINDINGS.json"
python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$AUTHORIZED" --patch-mode false
check "authorized destructive finding counted" "1" "$(json_field "$AUTHORIZED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_authorized")"
check "authorized destructive finding not blocked" "0" "$(json_field "$AUTHORIZED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_blocked")"

TARGET_NOT_REQUIRED="$TEST_ROOT/target-not-required"
write_minimal_output "$TARGET_NOT_REQUIRED"
printf '%s\n' \
    '[' \
    '  {' \
    '    "source": "test",' \
    '    "source_text": "delete target-owned file",' \
    '    "cleanup_action_class": "delete",' \
    '    "cleanup_action_scope": "single_file",' \
    '    "destructive_action": true,' \
    '    "target_paths": ["src/old.py"],' \
    '    "protected_keep_paths": ["src/main.py"],' \
    '    "keep_set_evidence": ["src/main.py imports replacement"],' \
    '    "owner_boundary_class": "target_owned",' \
    '    "owner_boundary_evidence": "src/ is target-owned source",' \
    '    "authorization_status": "not_required",' \
    '    "evidence_threshold": "unreferenced_with_keep_set"' \
    '  }' \
    ']' > "$TARGET_NOT_REQUIRED/CLEANUP_FINDINGS.json"
python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$TARGET_NOT_REQUIRED" --patch-mode false
check "target-owned not_required destructive finding is blocked" "1" "$(json_field "$TARGET_NOT_REQUIRED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_blocked")"

PATCH_BLOCK="$TEST_ROOT/patch-block"
write_minimal_output "$PATCH_BLOCK"
mkdir -p "$PATCH_BLOCK/PATCH_PACK"
printf '%s\n' 'diff --git a/archive/old.md b/archive/old.md' 'deleted file mode 100644' > "$PATCH_BLOCK/PATCH_PACK/delete-old.patch"
printf '%s\n' '# Optimization Plan' '' '- Recommendation: delete `archive/old.md` as cleanup.' > "$PATCH_BLOCK/OPTIMIZATION_PLAN.md"
if python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$PATCH_BLOCK" --patch-mode true >/dev/null 2>&1; then
    fail "patch mode blocks unsafe destructive patch"
else
    pass "patch mode blocks unsafe destructive patch"
fi
if [ -f "$PATCH_BLOCK/PATCH_BLOCKED_BY_CLEANUP_CONTRACT.json" ]; then
    pass "patch block receipt written"
else
    fail "patch block receipt written"
fi
check "patch deletion is counted alongside plan cleanup" "1" "$(json_field "$PATCH_BLOCK/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_total")"
check "patch block updates runtime status" "blocked_by_cleanup_contract" "$(json_field "$PATCH_BLOCK/RUNTIME_RECEIPTS.json" "phases.patch_generation.status")"

PATCH_UNRELATED="$TEST_ROOT/patch-unrelated"
write_minimal_output "$PATCH_UNRELATED"
mkdir -p "$PATCH_UNRELATED/PATCH_PACK"
printf '%s\n' 'diff --git a/src/safe.py b/src/safe.py' '--- a/src/safe.py' '+++ b/src/safe.py' '@@' '-old = 1' '+new = 1' > "$PATCH_UNRELATED/PATCH_PACK/safe.patch"
printf '%s\n' '# Optimization Plan' '' '- Recommendation: delete `archive/unrelated.md` as cleanup.' > "$PATCH_UNRELATED/OPTIMIZATION_PLAN.md"
if python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$PATCH_UNRELATED" --patch-mode true >/dev/null 2>&1; then
    pass "unrelated blocked cleanup does not block safe patch"
else
    fail "unrelated blocked cleanup does not block safe patch"
fi
check "unrelated safe patch not cleanup-blocked" "false" "$(json_field "$PATCH_UNRELATED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.patch_generation_blocked")"

PATCH_MIXED="$TEST_ROOT/patch-mixed"
write_minimal_output "$PATCH_MIXED"
mkdir -p "$PATCH_MIXED/PATCH_PACK"
printf '%s\n' 'diff --git a/archive/mixed.md b/archive/mixed.md' 'deleted file mode 100644' > "$PATCH_MIXED/PATCH_PACK/delete-mixed.patch"
printf '%s\n' \
    '[' \
    '  {' \
    '    "source": "test",' \
    '    "source_text": "keep source cleanup metadata only",' \
    '    "cleanup_action_class": "keep",' \
    '    "cleanup_action_scope": "single_file",' \
    '    "destructive_action": false,' \
    '    "target_paths": ["src/main.py"],' \
    '    "protected_keep_paths": ["src/main.py"],' \
    '    "keep_set_evidence": ["explicit keep set"],' \
    '    "owner_boundary_class": "target_owned",' \
    '    "owner_boundary_evidence": "source tree",' \
    '    "authorization_status": "not_required",' \
    '    "evidence_threshold": "literal_reference"' \
    '  }' \
    ']' > "$PATCH_MIXED/CLEANUP_FINDINGS.json"
if python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$PATCH_MIXED" --patch-mode true >/dev/null 2>&1; then
    fail "patch deletion is checked even with structured findings"
else
    pass "patch deletion is checked even with structured findings"
fi
check "patch fallback merged with structured findings" "2" "$(json_field "$PATCH_MIXED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.findings_with_cleanup_class")"

PATCH_REMOVE="$TEST_ROOT/patch-remove"
write_minimal_output "$PATCH_REMOVE"
mkdir -p "$PATCH_REMOVE/PATCH_PACK"
printf '%s\n' 'diff --git a/src/legacy.py b/src/legacy.py' '--- a/src/legacy.py' '+++ b/src/legacy.py' '@@' '-remove legacy behavior' '+pass' > "$PATCH_REMOVE/PATCH_PACK/remove-legacy.patch"
if python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$PATCH_REMOVE" --patch-mode true >/dev/null 2>&1; then
    fail "cleanup-signaled non-delete patch blocks without metadata"
else
    pass "cleanup-signaled non-delete patch blocks without metadata"
fi

PATCH_AUTHORIZED="$TEST_ROOT/patch-authorized"
write_minimal_output "$PATCH_AUTHORIZED"
mkdir -p "$PATCH_AUTHORIZED/PATCH_PACK"
printf '%s\n' 'diff --git a/build/cache.tmp b/build/cache.tmp' 'deleted file mode 100644' > "$PATCH_AUTHORIZED/PATCH_PACK/delete-cache.patch"
printf '%s\n' \
    '[' \
    '  {' \
    '    "source": "test",' \
    '    "source_text": "delete generated cache",' \
    '    "cleanup_action_class": "delete",' \
    '    "cleanup_action_scope": "generated_artifact",' \
    '    "destructive_action": true,' \
    '    "target_paths": ["build/cache.tmp"],' \
    '    "protected_keep_paths": ["src/main.py"],' \
    '    "keep_set_evidence": ["src/main.py imported by tests"],' \
    '    "owner_boundary_class": "generated_or_cache",' \
    '    "owner_boundary_evidence": "README says build/ is generated cache",' \
    '    "authorization_status": "not_required",' \
    '    "evidence_threshold": "unreferenced_with_keep_set"' \
    '  }' \
    ']' > "$PATCH_AUTHORIZED/CLEANUP_FINDINGS.json"
if python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$PATCH_AUTHORIZED" --patch-mode true >/dev/null 2>&1; then
    pass "authorized generated-cache delete patch is allowed"
else
    fail "authorized generated-cache delete patch is allowed"
fi
check "authorized delete patch not cleanup-blocked" "false" "$(json_field "$PATCH_AUTHORIZED/OPTIMIZATION_SCORECARD.json" "cleanup_contract.patch_generation_blocked")"

PATCH_ONLY="$TEST_ROOT/patch-only"
write_minimal_output "$PATCH_ONLY"
mkdir -p "$PATCH_ONLY/PATCH_PACK"
printf '%s\n' 'diff --git a/archive/hidden.md b/archive/hidden.md' 'deleted file mode 100644' > "$PATCH_ONLY/PATCH_PACK/delete-hidden.patch"
if python3 "$OPT_DIR/scripts/cleanup-contract.py" apply --output-dir "$PATCH_ONLY" --patch-mode true >/dev/null 2>&1; then
    fail "deletion patch without cleanup metadata blocks"
else
    pass "deletion patch without cleanup metadata blocks"
fi
check "deletion patch fallback is destructive" "1" "$(json_field "$PATCH_ONLY/OPTIMIZATION_SCORECARD.json" "cleanup_contract.destructive_findings_total")"

INTEGRATION_ROOT="$TEST_ROOT/integration"
TARGET_REPO="$INTEGRATION_ROOT/target"
AUDIT_DIR="$INTEGRATION_ROOT/audit"
OUTPUT_DIR="$INTEGRATION_ROOT/output"
mkdir -p "$TARGET_REPO" "$AUDIT_DIR"
printf '%s\n' '# Target Repo' > "$TARGET_REPO/AGENTS.md"
git -C "$TARGET_REPO" init -q
git -C "$TARGET_REPO" config user.email "test@example.com"
git -C "$TARGET_REPO" config user.name "Test User"
git -C "$TARGET_REPO" add AGENTS.md
git -C "$TARGET_REPO" commit -q -m "init target fixture"
printf '%s\n' \
    '{' \
    '  "composite": 50,' \
    '  "dimensions": {' \
    '    "D1_governance": {"score": 10, "max": 20},' \
    '    "D2_surface_health": {"score": 8, "max": 20},' \
    '    "D3_skill_maturity": {"score": 12, "max": 20}' \
    '  },' \
    '  "tier2_warnings": {"warnings": []}' \
    '}' > "$AUDIT_DIR/SCORECARD.json"
printf '%s\n' '# Audit Report' '' 'Synthetic completed audit report.' > "$AUDIT_DIR/AUDIT_REPORT.md"
printf '%s\n' '{' '  "status": "completed"' '}' > "$AUDIT_DIR/AUDIT_RUN_RECEIPT.json"
if OPTIMIZER_PREFLIGHT_ONLY=true bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$AUDIT_DIR" "$OUTPUT_DIR" > "$INTEGRATION_ROOT/run.log" 2>&1; then
    pass "preflight-only optimizer run completes with cleanup contract"
else
    fail "preflight-only optimizer run completes with cleanup contract"
    sed -n '1,160p' "$INTEGRATION_ROOT/run.log"
fi
check "integrated scorecard cleanup contract present" "0" "$(json_field "$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json" "cleanup_contract.findings_with_cleanup_class")"
check "integrated runtime cleanup contract present" "false" "$(json_field "$OUTPUT_DIR/RUNTIME_RECEIPTS.json" "cleanup_contract.patch_generation_blocked")"

for token in cleanup_action_class destructive_action authorization_status evidence_threshold owner_boundary; do
    if grep -Fq "$token" "$OPT_DIR/.agents/repo-optimizer-critic.agent.md" \
        && grep -Fq "$token" "$OPT_DIR/schemas/CLEANUP_FINDING_METADATA.schema.json"; then
        pass "critic prompt and schema include $token"
    else
        fail "critic prompt and schema include $token"
    fi
done

echo ""
echo "=== Cleanup Ledger Contract Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

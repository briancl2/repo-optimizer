#!/usr/bin/env bash
# test-audit-admission.sh — Partial/failed audit receipt admission gate tests.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$OPT_DIR/work/test-audit-admission"
TARGET_REPO="$TEST_ROOT/target-repo"
PASS=0
FAIL=0

trap 'rm -rf "$TEST_ROOT"' EXIT
rm -rf "$TEST_ROOT"
mkdir -p "$TARGET_REPO"
printf '%s\n' '# Target Repo' > "$TARGET_REPO/AGENTS.md"
git -C "$TARGET_REPO" init -q
git -C "$TARGET_REPO" config user.email "test@example.com"
git -C "$TARGET_REPO" config user.name "Test User"
git -C "$TARGET_REPO" add AGENTS.md
git -C "$TARGET_REPO" commit -q -m "init target fixture"

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

write_scorecard() {
    local audit_dir="$1"
    mkdir -p "$audit_dir"
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
    } > "$audit_dir/SCORECARD.json"
}

write_report() {
    printf '%s\n' '# Audit Report' '' 'Synthetic completed audit report.' > "$1/AUDIT_REPORT.md"
}

write_receipt() {
    printf '%s\n' '{' "  \"status\": \"$2\"" '}' > "$1/AUDIT_RUN_RECEIPT.json"
}

write_scan_limited_receipts() {
    {
        printf '%s\n' '{'
        printf '%s\n' '  "full_facts_inventory": {'
        printf '%s\n' '    "status": "available_limited",'
        printf '%s\n' '    "scan_limit_reached": true,'
        printf '%s\n' '    "scan_coverage_ratio": 0.25'
        printf '%s\n' '  },'
        printf '%s\n' '  "primary_surface_inventory": {'
        printf '%s\n' '    "status": "available_limited",'
        printf '%s\n' '    "scan_limit_reached": true'
        printf '%s\n' '  }'
        printf '%s\n' '}'
    } > "$1/SCORECARD_RECEIPTS.json"
}

write_snapshot_limited_receipts() {
    write_scan_limited_receipts "$1"
    python3 -c 'import json,sys; path=sys.argv[1]; data=json.load(open(path)); data["clean_head_snapshot"]={"mode":"clean-head-snapshot","non_authorization":True,"snapshot_status_clean":True}; json.dump(data, open(path,"w"))' "$1/SCORECARD_RECEIPTS.json"
    {
        printf '%s\n' '{'
        printf '%s\n' '  "mode": "clean-head-snapshot",'
        printf '%s\n' '  "non_authorization_statement": "snapshot evidence is not normal readiness authority"'
        printf '%s\n' '}'
    } > "$1/CLEAN_HEAD_SNAPSHOT_RECEIPT.json"
}

add_scorecard_audit_status() {
    python3 -c 'import json,sys; path=sys.argv[1]; data=json.load(open(path)); data.setdefault("meta", {})["audit_status"]=sys.argv[2]; json.dump(data, open(path, "w"))' "$1/SCORECARD.json" "$2"
}

setup_audit() {
    local name="$1" status="$2" report="$3" receipt="$4"
    local audit_dir="$TEST_ROOT/audit-$name"
    write_scorecard "$audit_dir"
    if [ "$report" = "yes" ]; then
        write_report "$audit_dir"
    fi
    if [ "$receipt" = "yes" ]; then
        write_receipt "$audit_dir" "$status"
    fi
    printf '%s\n' "$audit_dir"
}

run_optimizer() {
    local audit_dir="$1" output_dir="$2" research_mode="${3:-}"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    if [ -n "$research_mode" ]; then
        REPO_OPTIMIZER_RESEARCH_MODE="$research_mode" OPTIMIZER_PREFLIGHT_ONLY=true \
            bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$audit_dir" "$output_dir" > "$output_dir/run.log" 2>&1
    else
        OPTIMIZER_PREFLIGHT_ONLY=true \
            bash "$OPT_DIR/scripts/repo-optimizer.sh" "$TARGET_REPO" "$audit_dir" "$output_dir" > "$output_dir/run.log" 2>&1
    fi
}

capture_run() {
    local audit_dir="$1" output_dir="$2" research_mode="${3:-}"
    local rc=0
    if run_optimizer "$audit_dir" "$output_dir" "$research_mode"; then
        rc=0
    else
        rc=$?
    fi
    printf '%s\n' "$rc"
}

echo "=== Audit Admission Tests ==="

COMPLETED_AUDIT="$(setup_audit completed completed yes yes)"
COMPLETED_OUT="$TEST_ROOT/out-completed"
COMPLETED_RC="$(capture_run "$COMPLETED_AUDIT" "$COMPLETED_OUT")"
check "completed receipt is admitted" "0" "$COMPLETED_RC"
check "completed admission status" "admitted" "$(json_field "$COMPLETED_OUT/audit-admission-receipt.json" "admission_status")"
check "completed normal readiness claim" "true" "$(json_field "$COMPLETED_OUT/pre-flight.json" "normal_readiness_claim")"

SCAN_LIMITED_AUDIT="$(setup_audit scan-limited completed yes yes)"
write_scan_limited_receipts "$SCAN_LIMITED_AUDIT"
SCAN_LIMITED_OUT="$TEST_ROOT/out-scan-limited"
SCAN_LIMITED_RC="$(capture_run "$SCAN_LIMITED_AUDIT" "$SCAN_LIMITED_OUT")"
check "scan-limited completed audit is blocked" "1" "$SCAN_LIMITED_RC"
check "scan-limited blocker code" "scan_limited_audit_evidence" "$(json_field "$SCAN_LIMITED_OUT/audit-admission-receipt.json" "blocker.code")"
check "scan-limited evidence class" "scan_limited" "$(json_field "$SCAN_LIMITED_OUT/audit-admission-receipt.json" "audit_evidence_class")"
check "scan-limited has no normal readiness claim" "false" "$(json_field "$SCAN_LIMITED_OUT/pre-flight.json" "normal_readiness_claim")"

SNAPSHOT_LIMITED_AUDIT="$(setup_audit snapshot-limited completed yes yes)"
write_snapshot_limited_receipts "$SNAPSHOT_LIMITED_AUDIT"
SNAPSHOT_LIMITED_OUT="$TEST_ROOT/out-snapshot-limited"
SNAPSHOT_LIMITED_RC="$(capture_run "$SNAPSHOT_LIMITED_AUDIT" "$SNAPSHOT_LIMITED_OUT")"
check "snapshot-limited completed audit is blocked" "1" "$SNAPSHOT_LIMITED_RC"
check "snapshot-limited blocker code" "snapshot_limited_audit_evidence" "$(json_field "$SNAPSHOT_LIMITED_OUT/audit-admission-receipt.json" "blocker.code")"
check "snapshot-limited evidence class" "snapshot_limited" "$(json_field "$SNAPSHOT_LIMITED_OUT/audit-admission-receipt.json" "audit_evidence_class")"
check "snapshot-limited has no normal readiness claim" "false" "$(json_field "$SNAPSHOT_LIMITED_OUT/OPTIMIZATION_SCORECARD.json" "normal_readiness_claim")"

PARTIAL_AUDIT="$(setup_audit partial partial no yes)"
PARTIAL_OUT="$TEST_ROOT/out-partial"
PARTIAL_RC="$(capture_run "$PARTIAL_AUDIT" "$PARTIAL_OUT")"
check "partial receipt is blocked" "1" "$PARTIAL_RC"
check "partial blocked receipt" "blocked" "$(json_field "$PARTIAL_OUT/audit-admission-receipt.json" "admission_status")"
check "partial has no normal readiness claim" "false" "$(json_field "$PARTIAL_OUT/OPTIMIZATION_SCORECARD.json" "normal_readiness_claim")"

FAILED_AUDIT="$(setup_audit failed failed yes yes)"
FAILED_OUT="$TEST_ROOT/out-failed"
FAILED_RC="$(capture_run "$FAILED_AUDIT" "$FAILED_OUT")"
check "failed receipt is blocked" "1" "$FAILED_RC"
check "failed blocker code" "audit_status_failed" "$(json_field "$FAILED_OUT/audit-admission-receipt.json" "blocker.code")"
check "failed runtime receipt has no readiness claim" "false" "$(json_field "$FAILED_OUT/RUNTIME_RECEIPTS.json" "normal_readiness_claim")"

MISSING_RECEIPT_AUDIT="$(setup_audit missing-receipt completed yes no)"
MISSING_RECEIPT_OUT="$TEST_ROOT/out-missing-receipt"
MISSING_RECEIPT_RC="$(capture_run "$MISSING_RECEIPT_AUDIT" "$MISSING_RECEIPT_OUT")"
check "missing receipt is blocked" "1" "$MISSING_RECEIPT_RC"
check "missing receipt blocker code" "missing_audit_receipt" "$(json_field "$MISSING_RECEIPT_OUT/audit-admission-receipt.json" "blocker.code")"

MALFORMED_RECEIPT_AUDIT="$(setup_audit malformed-receipt completed yes yes)"
printf '%s\n' '{}' > "$MALFORMED_RECEIPT_AUDIT/AUDIT_RUN_RECEIPT.json"
add_scorecard_audit_status "$MALFORMED_RECEIPT_AUDIT" "completed"
MALFORMED_RECEIPT_OUT="$TEST_ROOT/out-malformed-receipt"
MALFORMED_RECEIPT_RC="$(capture_run "$MALFORMED_RECEIPT_AUDIT" "$MALFORMED_RECEIPT_OUT")"
check "malformed receipt with completed scorecard is blocked" "1" "$MALFORMED_RECEIPT_RC"
check "malformed receipt blocker code" "malformed_audit_receipt" "$(json_field "$MALFORMED_RECEIPT_OUT/audit-admission-receipt.json" "blocker.code")"
check "malformed receipt has no normal readiness claim" "false" "$(json_field "$MALFORMED_RECEIPT_OUT/pre-flight.json" "normal_readiness_claim")"

MISSING_REPORT_AUDIT="$(setup_audit missing-report completed no yes)"
MISSING_REPORT_OUT="$TEST_ROOT/out-missing-report"
MISSING_REPORT_RC="$(capture_run "$MISSING_REPORT_AUDIT" "$MISSING_REPORT_OUT")"
check "completed receipt missing report is blocked" "1" "$MISSING_REPORT_RC"
check "missing report blocker code" "completed_receipt_missing_report" "$(json_field "$MISSING_REPORT_OUT/audit-admission-receipt.json" "blocker.code")"

RESEARCH_OUT="$TEST_ROOT/research-mode/partial-audit-calibration/run"
RESEARCH_RC="$(capture_run "$PARTIAL_AUDIT" "$RESEARCH_OUT" "partial-audit-calibration")"
check "research mode admits partial calibration" "0" "$RESEARCH_RC"
check "research mode recorded in pre-flight" "partial-audit-calibration" "$(json_field "$RESEARCH_OUT/pre-flight.json" "research_mode")"
check "research mode recorded in optimization scorecard" "partial-audit-calibration" "$(json_field "$RESEARCH_OUT/OPTIMIZATION_SCORECARD.json" "research_mode")"
check "research mode recorded in operation eval" "partial-audit-calibration" "$(json_field "$RESEARCH_OUT/OPERATION_EVAL.json" "research_mode")"
check "research mode has no normal readiness claim" "false" "$(json_field "$RESEARCH_OUT/RUNTIME_RECEIPTS.json" "normal_readiness_claim")"

BAD_RESEARCH_OUT="$TEST_ROOT/not-research/run"
BAD_RESEARCH_RC="$(capture_run "$PARTIAL_AUDIT" "$BAD_RESEARCH_OUT" "partial-audit-calibration")"
check "research mode rejects unlabeled output path" "1" "$BAD_RESEARCH_RC"
check "research path blocker code" "invalid_research_output_path" "$(json_field "$BAD_RESEARCH_OUT/audit-admission-receipt.json" "blocker.code")"

RESEARCH_MISSING_RECEIPT_OUT="$TEST_ROOT/research-mode/partial-audit-calibration/missing-receipt"
RESEARCH_MISSING_RECEIPT_RC="$(capture_run "$MISSING_RECEIPT_AUDIT" "$RESEARCH_MISSING_RECEIPT_OUT" "partial-audit-calibration")"
check "research mode requires audit status evidence" "1" "$RESEARCH_MISSING_RECEIPT_RC"
check "research missing receipt blocker code" "research_mode_missing_audit_status" "$(json_field "$RESEARCH_MISSING_RECEIPT_OUT/audit-admission-receipt.json" "blocker.code")"

echo ""
echo "=== Audit Admission Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

#!/usr/bin/env bash
# test-delivery-admission.sh — Validate optimizer delivery-admission routing.

set -euo pipefail

OPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$OPT_DIR/work/test-delivery-admission"
PASS=0
FAIL=0

trap 'rm -rf "$TEST_ROOT"' EXIT
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"

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

json_failure_phases() {
    python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(",".join(str(item.get("phase")) for item in data.get("pipeline_failures", []) if isinstance(item, dict)))' "$1"
}

echo "=== Delivery Admission Tests ==="

REPORT_ONLY="$TEST_ROOT/report-only"
mkdir -p "$REPORT_ONLY"
printf '%s\n' '# Optimization Plan' '' 'Report-only fixture.' > "$REPORT_ONLY/OPTIMIZATION_PLAN.md"
cat > "$REPORT_ONLY/OPTIMIZATION_SCORECARD.json" <<'JSON'
{
  "patches_generated": 0,
  "patches_valid": 0,
  "coverage_verdict": "complete",
  "recommendation_strength": "strong",
  "meta": {
    "patch_status": "not_requested"
  }
}
JSON
python3 "$OPT_DIR/scripts/delivery-admission.py" apply --output-dir "$REPORT_ONLY" --patch-mode false
check "report-only status" "report_only" "$(json_field "$REPORT_ONLY/DELIVERY_ADMISSION.json" "admission_status")"
check "report-only not admitted" "false" "$(json_field "$REPORT_ONLY/DELIVERY_ADMISSION.json" "delivery_admitted")"
check "report-only scorecard summary" "report_only" "$(json_field "$REPORT_ONLY/OPTIMIZATION_SCORECARD.json" "delivery_admission.admission_status")"

BLOCKED="$TEST_ROOT/blocked"
mkdir -p "$BLOCKED"
cp "$OPT_DIR/tests/fixtures/patchability-blocked-operation/OPTIMIZATION_PLAN.md" "$BLOCKED/OPTIMIZATION_PLAN.md"
cp "$OPT_DIR/tests/fixtures/patchability-blocked-operation/PATCHABILITY_BLOCKERS.json" "$BLOCKED/PATCHABILITY_BLOCKERS.json"
cat > "$BLOCKED/OPTIMIZATION_SCORECARD.json" <<'JSON'
{
  "patches_generated": 0,
  "patches_valid": 0,
  "coverage_verdict": "pass_with_coverage_gap",
  "recommendation_strength": "limited",
  "discovery_coverage": {
    "coverage_verdict": "pass_with_coverage_gap",
    "recommendation_strength": "limited",
    "missing_domains": ["extraction", "standardization"]
  },
  "meta": {
    "patch_status": "fail_closed_patchability_blocked"
  }
}
JSON
python3 "$OPT_DIR/scripts/delivery-admission.py" apply --output-dir "$BLOCKED" --patch-mode true
check "blocked status combines coverage and patchability" "blocked_patchability_and_coverage" "$(json_field "$BLOCKED/DELIVERY_ADMISSION.json" "admission_status")"
check "blocked not admitted" "false" "$(json_field "$BLOCKED/DELIVERY_ADMISSION.json" "delivery_admitted")"
check "blocked unsupported rows counted" "5" "$(json_field "$BLOCKED/DELIVERY_ADMISSION.json" "patchability_blocker_codes.unsupported_manifest_row")"
check "blocked plan section written" "true" "$(grep -Fq '## Delivery Admission' "$BLOCKED/OPTIMIZATION_PLAN.md" && echo true || echo false)"
if make -C "$OPT_DIR" validate OUTPUT_DIR="$BLOCKED" >/dev/null; then
    echo "  PASS: bundle validator accepts delivery-admission artifact"
    PASS=$((PASS + 1))
else
    echo "  FAIL: bundle validator rejected delivery-admission artifact"
    FAIL=$((FAIL + 1))
fi

COVERAGE_ONLY="$TEST_ROOT/coverage-only"
mkdir -p "$COVERAGE_ONLY"
printf '%s\n' '# Optimization Plan' '' 'Coverage-only fixture.' > "$COVERAGE_ONLY/OPTIMIZATION_PLAN.md"
cat > "$COVERAGE_ONLY/OPTIMIZATION_SCORECARD.json" <<'JSON'
{
  "patches_generated": 0,
  "patches_valid": 0,
  "coverage_verdict": "partial",
  "recommendation_strength": "diagnostic",
  "discovery_coverage": {
    "coverage_verdict": "partial",
    "recommendation_strength": "diagnostic",
    "missing_domains": ["standardization"]
  },
  "meta": {
    "patch_status": "no_patches_generated"
  }
}
JSON
cat > "$COVERAGE_ONLY/RUNTIME_RECEIPTS.json" <<'JSON'
{
  "phases": {
    "critic": {
      "status": "completed",
      "receipt_class": "terminal_markdown_captured"
    },
    "synthesis": {
      "status": "completed",
      "receipt_class": "terminal_markdown_captured"
    },
    "patch_generation": {
      "status": "no_patches_generated",
      "patches_valid": 0
    }
  }
}
JSON
python3 "$OPT_DIR/scripts/delivery-admission.py" apply --output-dir "$COVERAGE_ONLY" --patch-mode true
check "valid pipeline partial coverage stays coverage-blocked" "blocked_coverage" "$(json_field "$COVERAGE_ONLY/DELIVERY_ADMISSION.json" "admission_status")"
check "valid pipeline partial coverage remains assessable" "true" "$(json_field "$COVERAGE_ONLY/DELIVERY_ADMISSION.json" "admission_assessable")"
check "valid pipeline partial coverage has no pipeline failures" "0" "$(json_field "$COVERAGE_ONLY/DELIVERY_ADMISSION.json" "pipeline_failure_count")"

PIPELINE_FAIL="$TEST_ROOT/pipeline-fail"
mkdir -p "$PIPELINE_FAIL"
printf '%s\n' '# Optimization Plan' '' 'Pipeline failure fixture.' > "$PIPELINE_FAIL/OPTIMIZATION_PLAN.md"
cat > "$PIPELINE_FAIL/OPTIMIZATION_SCORECARD.json" <<'JSON'
{
  "patches_generated": 0,
  "patches_valid": 0,
  "coverage_verdict": "partial",
  "recommendation_strength": "diagnostic",
  "discovery_coverage": {
    "coverage_verdict": "partial",
    "recommendation_strength": "diagnostic",
    "missing_domains": [],
    "critic_status": "failed_artifact_contract",
    "synthesis_status": "skipped_upstream_critic_failure"
  },
  "meta": {
    "patch_status": "fail_closed_critic_missing_terminal_non_tool_message"
  }
}
JSON
cat > "$PIPELINE_FAIL/RUNTIME_RECEIPTS.json" <<'JSON'
{
  "phases": {
    "critic": {
      "status": "failed_artifact_contract",
      "receipt_class": "missing_terminal_non_tool_message"
    },
    "synthesis": {
      "status": "skipped_upstream_critic_failure",
      "receipt_class": "upstream_critic_missing_terminal_non_tool_message"
    },
    "patch_generation": {
      "status": "fail_closed_critic_missing_terminal_non_tool_message",
      "patches_valid": 0
    }
  }
}
JSON
python3 "$OPT_DIR/scripts/delivery-admission.py" apply --output-dir "$PIPELINE_FAIL" --patch-mode true
check "pipeline failure status is not coverage" "blocked_pipeline_artifact_contract" "$(json_field "$PIPELINE_FAIL/DELIVERY_ADMISSION.json" "admission_status")"
check "pipeline failure not assessable" "false" "$(json_field "$PIPELINE_FAIL/DELIVERY_ADMISSION.json" "admission_assessable")"
check "pipeline failure not admitted" "false" "$(json_field "$PIPELINE_FAIL/DELIVERY_ADMISSION.json" "delivery_admitted")"
check "pipeline failure count" "2" "$(json_field "$PIPELINE_FAIL/DELIVERY_ADMISSION.json" "pipeline_failure_count")"
check "pipeline failure phases" "critic,synthesis" "$(json_failure_phases "$PIPELINE_FAIL/DELIVERY_ADMISSION.json")"
check "pipeline failure scorecard summary" "blocked_pipeline_artifact_contract" "$(json_field "$PIPELINE_FAIL/OPTIMIZATION_SCORECARD.json" "delivery_admission.admission_status")"
check "pipeline failure scorecard assessable summary" "false" "$(json_field "$PIPELINE_FAIL/OPTIMIZATION_SCORECARD.json" "delivery_admission.admission_assessable")"

PATCHED="$TEST_ROOT/patched"
mkdir -p "$PATCHED/PATCH_PACK"
printf '%s\n' '# Optimization Plan' '' 'Patch-present fixture.' > "$PATCHED/OPTIMIZATION_PLAN.md"
printf '%s\n' 'diff --git a/README.md b/README.md' > "$PATCHED/PATCH_PACK/P1.patch"
cat > "$PATCHED/OPTIMIZATION_SCORECARD.json" <<'JSON'
{
  "patches_generated": 1,
  "patches_valid": 1,
  "coverage_verdict": "complete",
  "recommendation_strength": "strong",
  "meta": {
    "patch_status": "patches_present"
  }
}
JSON
python3 "$OPT_DIR/scripts/delivery-admission.py" apply --output-dir "$PATCHED" --patch-mode true
check "patch-present admitted" "true" "$(json_field "$PATCHED/DELIVERY_ADMISSION.json" "delivery_admitted")"
check "patch-present status" "admitted_patch_review" "$(json_field "$PATCHED/DELIVERY_ADMISSION.json" "admission_status")"
check "patch-present evidence path" "PATCH_PACK" "$(json_field "$PATCHED/DELIVERY_ADMISSION.json" "evidence_paths.patch_pack")"

echo ""
echo "=== Delivery Admission Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

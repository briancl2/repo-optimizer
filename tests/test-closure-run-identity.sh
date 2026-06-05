#!/usr/bin/env bash
# tests/test-closure-run-identity.sh — Verify closure-run identity receipts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

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

json_field() {
    python3 - "$1" "$2" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload
for part in sys.argv[2].split("."):
    value = value.get(part)
print("" if value is None else value)
PY
}

echo "=== Closure-run identity tests ==="

before_status=$(git status --short)
default_json=$(env -u CLOSURE_RUN_ID -u CLOSURE_PHASE -u CLOSURE_TRIGGER \
    -u EVIDENCE_REUSE_KEY -u PARENT_COMMAND -u GITHUB_RUN_ID \
    -u GITHUB_RUN_ATTEMPT -u CLOSURE_IDENTITY_RECEIPT \
    python3 scripts/closure-run-identity.py \
        --phase check \
        --parent-command "make check")
after_status=$(git status --short)

default_run_id=$(json_field "$default_json" closure_run_id)
check "local closure_run_id uses local prefix" "true" "$([[ "$default_run_id" == local-* ]] && echo true || echo false)"
check "local closure_phase defaults to invoked gate" "check" "$(json_field "$default_json" closure_phase)"
check "local closure_trigger defaults to manual" "manual" "$(json_field "$default_json" closure_trigger)"
check "local parent_command records command" "make check" "$(json_field "$default_json" parent_command)"
check "local github_run_id omitted" "" "$(json_field "$default_json" github_run_id)"
check "local run does not dirty repo" "$before_status" "$after_status"

receipt="$TMPDIR/identity.json"
env_json=$(CLOSURE_RUN_ID=run-42 CLOSURE_PHASE=override-phase \
    CLOSURE_TRIGGER=operator EVIDENCE_REUSE_KEY=reuse-42 \
    PARENT_COMMAND="parent override" GITHUB_RUN_ID=987 GITHUB_RUN_ATTEMPT=3 \
    CLOSURE_IDENTITY_RECEIPT="$receipt" \
    python3 scripts/closure-run-identity.py \
        --phase test \
        --parent-command "make test")

check "explicit receipt written" "true" "$([ -s "$receipt" ] && echo true || echo false)"
check "env closure_run_id wins" "run-42" "$(json_field "$env_json" closure_run_id)"
check "env closure_phase wins" "override-phase" "$(json_field "$env_json" closure_phase)"
check "env closure_trigger wins" "operator" "$(json_field "$env_json" closure_trigger)"
check "env evidence_reuse_key wins" "reuse-42" "$(json_field "$env_json" evidence_reuse_key)"
check "env parent_command wins" "parent override" "$(json_field "$env_json" parent_command)"
check "github_run_id emitted" "987" "$(json_field "$env_json" github_run_id)"
check "github_run_attempt emitted" "3" "$(json_field "$env_json" github_run_attempt)"

ci_json=$(env -u CLOSURE_RUN_ID CLOSURE_TRIGGER=github_actions \
    GITHUB_RUN_ID=12345 GITHUB_RUN_ATTEMPT=6 \
    python3 scripts/closure-run-identity.py \
        --phase test \
        --parent-command "make test")
check "CI closure_run_id defaults to run-attempt" "12345-6" "$(json_field "$ci_json" closure_run_id)"
check "CI closure_trigger recorded" "github_actions" "$(json_field "$ci_json" closure_trigger)"

echo ""
echo "=== Closure-run Identity Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "  VERDICT: PASS"
    exit 0
else
    echo "  VERDICT: FAIL"
    exit 1
fi

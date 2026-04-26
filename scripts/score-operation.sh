#!/usr/bin/env bash
# scripts/score-operation.sh — Runtime evaluation of optimization quality (C1: Runtime Eval)
#
# Evaluates the QUALITY of a completed optimization operation — not whether it ran,
# but whether the output was complete, correct, and useful.
#
# Complements score-session.sh (session PROCESS) by measuring operational OUTPUT QUALITY:
# pre-flight completeness, patch validity, plan quality, SCORECARD generation.
#
# Usage: bash scripts/score-operation.sh <optimizer_output_dir> [--json]
#
# Checks (11 total, 26 points max):
#   1. pre-flight.json exists and valid (3pt)
#   2. Bottom-2 dimensions identified (2pt)
#   3. OPTIMIZATION_PLAN.md exists and non-trivial (3pt) — threshold: 50 lines
#   4. OPTIMIZATION_SCORECARD.json exists and valid (2pt)
#   5. Patch generation attempted (if --patch mode) (2pt)
#   6. No timeout/error indicators (2pt)
#   7. Budget tier assigned (2pt)
#   8. Input SCORECARD referenced (4pt)
#   9. Approved findings >=1 in plan (2pt) — content quality gate
#  10. Target files referenced in plan (2pt) — content quality gate
#  11. Command-output ROI (avoid copying raw command dumps into governed optimizer artifacts) (2pt)
#
# Exit codes:
#   0 — evaluation complete (score in stdout)
#   1 — missing inputs
#
# Source: Stage 11.2 (C1 runtime eval). Adapted from repo-auditor pattern.

set -euo pipefail

OPT_DIR="${1:?Usage: score-operation.sh <optimizer_output_dir> [--json]}"
JSON_MODE="false"

for arg in "$@"; do
    if [ "$arg" = "--json" ]; then JSON_MODE="true"; fi
done

if [ ! -d "$OPT_DIR" ]; then
    echo "ERROR: Optimizer output directory not found: $OPT_DIR" >&2
    exit 1
fi

SCORE=0
MAX=26
ISSUES=""
EVIDENCE=""
COMMAND_OUTPUT_RC=0
COMMAND_OUTPUT_VIOLATIONS_JSON="[]"
COMMAND_OUTPUT_ROI_RECEIPT="{}"

add_score() {
    local pts="$1"
    local label="$2"
    SCORE=$((SCORE + pts))
    EVIDENCE="${EVIDENCE}  +${pts}pt: $label\n"
}

add_issue() {
    local label="$1"
    ISSUES="${ISSUES}  - $label\n"
}

detect_command_output_noise() {
    python3 - "$OPT_DIR" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
raw_line = re.compile(
    r"^\s*(?:PASS|FAIL|WARN|ERROR|INFO):\s+|"
    r"^\s*(?:ok|not ok)\s+\d+\b|"
    r"^\s*(?:[+>$])\s*(?:make|bash|python3|git|npm|node|pytest|copilot)\b|"
    r"^\s*(?:npm ERR!|make(?:\[\d+\])?:|Traceback\b|File \".*\", line \d+)",
    re.IGNORECASE,
)


def raw_count(lines):
    return sum(1 for line in lines if raw_line.search(line))


def longest_raw_run(lines):
    longest = 0
    current = 0
    for line in lines:
        if raw_line.search(line):
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def add_violation(violations, artifact, location, reason, lines):
    violations.append(
        {
            "artifact": artifact,
            "location": location,
            "reason": reason,
            "raw_line_count": raw_count(lines),
            "longest_raw_run": longest_raw_run(lines),
        }
    )


def inspect_lines(artifact, lines):
    violations = []
    total = raw_count(lines)
    run = longest_raw_run(lines)
    if run >= 12:
        add_violation(violations, artifact, None, "governed artifact has consecutive raw-looking command output lines", lines)
    elif total >= 30:
        add_violation(violations, artifact, None, "governed artifact has excessive raw-looking command output lines", lines)

    in_fence = False
    fence_lines = []
    for line in lines + ["```"]:
        if line.startswith("```"):
            if in_fence:
                if longest_raw_run(fence_lines) >= 12 or raw_count(fence_lines) >= 20:
                    add_violation(violations, artifact, "fenced block", "governed artifact copied a raw command transcript block", fence_lines)
                    break
                fence_lines = []
                in_fence = False
            else:
                in_fence = True
                fence_lines = []
            continue
        if in_fence:
            fence_lines.append(line)
    return violations


def iter_json_strings(value, prefix="$"):
    if isinstance(value, str):
        yield prefix, value
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_json_strings(item, f"{prefix}[{index}]")
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from iter_json_strings(item, f"{prefix}.{key}")


violations = []
for name in ("OPTIMIZATION_PLAN.md", "critic-verdicts.md"):
    path = root / name
    if path.is_file():
        violations.extend(inspect_lines(path.name, path.read_text(encoding="utf-8", errors="replace").splitlines()))

path = root / "OPTIMIZATION_SCORECARD.json"
if path.is_file():
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        payload = None
    if payload is not None:
        total_raw_lines = 0
        for pointer, text in iter_json_strings(payload):
            lines = text.splitlines()
            total_raw_lines += raw_count(lines)
            if longest_raw_run(lines) >= 12 or raw_count(lines) >= 20:
                add_violation(violations, path.name, pointer, "governed machine artifact contains a raw-looking command transcript string", lines)
        if total_raw_lines >= 30:
            violations.append(
                {
                    "artifact": path.name,
                    "location": "all string values",
                    "reason": "governed machine artifact contains excessive raw-looking command lines across string values",
                    "raw_line_count": total_raw_lines,
                    "longest_raw_run": None,
                }
            )

print(json.dumps(violations))
raise SystemExit(1 if violations else 0)
PY
}

build_command_output_roi_receipt() {
    OPT_DIR="$OPT_DIR" \
    COMMAND_OUTPUT_RC="$COMMAND_OUTPUT_RC" \
    COMMAND_OUTPUT_VIOLATIONS_JSON="$COMMAND_OUTPUT_VIOLATIONS_JSON" \
    python3 - <<'PY'
import datetime as _dt
import json
import os
import pathlib

try:
    violations = json.loads(os.environ.get("COMMAND_OUTPUT_VIOLATIONS_JSON") or "[]")
except Exception:
    violations = [{"artifact": "unknown", "location": None, "reason": "command-output ROI detector returned malformed violation output", "raw_line_count": None, "longest_raw_run": None}]

failed = os.environ.get("COMMAND_OUTPUT_RC") != "0"
root = pathlib.Path(os.environ["OPT_DIR"])


def governed(path, artifact_class):
    return {
        "path": path,
        "artifact_class": artifact_class,
        "scanned": (root / path).is_file(),
    }


governed_artifacts = [
    governed("OPTIMIZATION_PLAN.md", "runtime_plan"),
    governed("OPTIMIZATION_SCORECARD.json", "machine_summary"),
    governed("critic-verdicts.md", "critic_output"),
]
if not any(row["scanned"] for row in governed_artifacts):
    violations = [
        {
            "artifact": "governed_artifacts",
            "location": None,
            "reason": "no governed optimizer artifacts were present to scan",
            "raw_line_count": None,
            "longest_raw_run": None,
        }
    ]
    verdict = "not-measured"
    raw_transcript_detected = False
else:
    verdict = "fail" if failed else "pass"
    raw_transcript_detected = failed

payload = {
    "generated_at": _dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "schema_version": "1.0.0",
    "artifact": "COMMAND_OUTPUT_ROI_RECEIPT",
    "receipt_id": "repo-optimizer-command-output-roi",
    "source_benchmark": {
        "tactic_id": "command_output_roi",
        "promotion_scope": "fleet-portable",
        "evidence_ref": "build-meta-analysis:research/reports/provider-neutral-tier3-live-paired-benchmark-2026-04-26.md",
    },
    "owner_surface": {
        "repo": "repo-optimizer",
        "runtime_surface": "scripts/score-operation.sh",
        "mode": "optimization output evaluation",
    },
    "governed_artifacts": governed_artifacts,
    "allowed_raw_receipt_artifacts": [
        "optimizer-stdout.txt",
        "*.jsonl",
        "RUNTIME_RECEIPTS.json",
        "critic-phase-receipt.json",
        "synthesis-phase-receipt.json",
    ],
    "verdict": verdict,
    "raw_transcript_detected": raw_transcript_detected,
    "violations": violations,
    "policy": {
        "summary_required": True,
        "raw_logs_allowed_in": ["receipt artifacts", "stdout/stderr logs", "raw jsonl transcripts"],
        "direct_metric_claim": False,
        "cache_claim": False,
    },
    "bounded_non_claims": [
        "This receipt does not prove cache savings.",
        "This receipt does not promote provider-scoped prompt/context tactics.",
        "This receipt does not authorize target-repo mutation.",
    ],
}
print(json.dumps(payload, separators=(",", ":")))
PY
}

# ── Check 1: pre-flight.json exists and valid (3pt) ──────────────────
PREFLIGHT="$OPT_DIR/pre-flight.json"
if [ -f "$PREFLIGHT" ]; then
    if python3 -c "import json; json.load(open('$PREFLIGHT'))" 2>/dev/null; then
        add_score 3 "pre-flight.json exists and valid JSON"
    else
        add_score 1 "pre-flight.json exists but invalid JSON"
        add_issue "pre-flight.json is not valid JSON"
    fi
else
    add_issue "pre-flight.json missing"
fi

# ── Check 2: Bottom-2 dimensions identified (2pt) ────────────────────
if [ -f "$PREFLIGHT" ]; then
    BOTTOM_DIMS=$(python3 -c "
import json
try:
    pf = json.load(open('$PREFLIGHT'))
    dims = pf.get('bottom_dimensions', pf.get('target_dimensions', []))
    print(len(dims))
except:
    print(0)
" 2>/dev/null || echo "0")
    if [ "$BOTTOM_DIMS" -ge 2 ]; then
        add_score 2 "Bottom dimensions identified ($BOTTOM_DIMS)"
    elif [ "$BOTTOM_DIMS" -ge 1 ]; then
        add_score 1 "Partial bottom dimensions ($BOTTOM_DIMS)"
        add_issue "Only $BOTTOM_DIMS bottom dimensions identified (expected 2)"
    else
        add_issue "No bottom dimensions identified in pre-flight"
    fi
fi

# ── Check 3: OPTIMIZATION_PLAN.md exists and non-trivial (3pt) ───────
PLAN="$OPT_DIR/OPTIMIZATION_PLAN.md"
if [ -f "$PLAN" ]; then
    PLAN_LINES=$(wc -l < "$PLAN" | tr -d ' ')
    if [ "$PLAN_LINES" -ge 50 ]; then
        add_score 3 "OPTIMIZATION_PLAN.md exists ($PLAN_LINES lines)"
    elif [ "$PLAN_LINES" -ge 20 ]; then
        add_score 2 "OPTIMIZATION_PLAN.md exists but short ($PLAN_LINES lines)"
        add_issue "OPTIMIZATION_PLAN.md is <50 lines ($PLAN_LINES lines)"
    elif [ "$PLAN_LINES" -ge 5 ]; then
        add_score 1 "OPTIMIZATION_PLAN.md exists but sparse ($PLAN_LINES lines)"
        add_issue "OPTIMIZATION_PLAN.md is sparse ($PLAN_LINES lines)"
    else
        add_issue "OPTIMIZATION_PLAN.md is trivial ($PLAN_LINES lines)"
    fi
else
    add_issue "OPTIMIZATION_PLAN.md missing"
fi

# ── Check 4: OPTIMIZATION_SCORECARD.json exists and valid (2pt) ──────
OPT_SC="$OPT_DIR/OPTIMIZATION_SCORECARD.json"
if [ -f "$OPT_SC" ]; then
    if python3 -c "import json; json.load(open('$OPT_SC'))" 2>/dev/null; then
        add_score 2 "OPTIMIZATION_SCORECARD.json exists and valid"
    else
        add_score 1 "OPTIMIZATION_SCORECARD.json exists but invalid JSON"
        add_issue "OPTIMIZATION_SCORECARD.json is not valid JSON"
    fi
else
    add_issue "OPTIMIZATION_SCORECARD.json missing"
fi

# ── Check 5: Patch generation (2pt — if PATCH_PACK dir exists) ───────
PATCH_DIR="$OPT_DIR/PATCH_PACK"
if [ -d "$PATCH_DIR" ]; then
    PATCH_COUNT=$(find "$PATCH_DIR" -name '*.patch' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PATCH_COUNT" -gt 0 ]; then
        add_score 2 "PATCH_PACK contains $PATCH_COUNT patches"
    else
        add_score 1 "PATCH_PACK dir exists but no patches"
        add_issue "PATCH_PACK directory exists but contains 0 patches"
    fi
else
    # Patch generation may not have been requested — partial credit
    add_score 1 "No PATCH_PACK (report-only mode)"
fi

# ── Check 6: Runtime receipts / timeout indicators (2pt) ─────────────
RUNTIME_RECEIPTS="$OPT_DIR/RUNTIME_RECEIPTS.json"
RUNTIME_PHASE_FAILURES=""
if [ -f "$RUNTIME_RECEIPTS" ]; then
    RUNTIME_PHASE_FAILURES=$(python3 - "$RUNTIME_RECEIPTS" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

issues = []
for phase_name in ("critic", "synthesis"):
    phase = payload.get("phases", {}).get(phase_name, {})
    status = phase.get("status", "")
    receipt_class = phase.get("receipt_class", "")
    if status.startswith("failed_") or status in {"skipped_missing_agent", "skipped_upstream_critic_failure"}:
        issues.append(f"{phase_name}:{status}/{receipt_class}")

print("; ".join(issues))
PY
)
fi

FALLBACK_SIGNALS=0
for f in "$OPT_DIR"/*.md "$OPT_DIR"/*.txt "$OPT_DIR"/*.json; do
    if [ -f "$f" ] && grep -qi 'timeout\|timed out\|TIMEOUT\|error.*fatal' "$f" 2>/dev/null; then
        FALLBACK_SIGNALS=$((FALLBACK_SIGNALS + 1))
    fi
done

if [ -n "$RUNTIME_PHASE_FAILURES" ]; then
    add_score 1 "Runtime receipts classify fail-closed phase issues ($RUNTIME_PHASE_FAILURES)"
    add_issue "Runtime receipts classify fail-closed phase issues: $RUNTIME_PHASE_FAILURES"
elif [ "$FALLBACK_SIGNALS" -eq 0 ]; then
    add_score 2 "No timeout or error indicators"
else
    add_score 1 "Timeout/error indicators detected ($FALLBACK_SIGNALS files)"
    add_issue "Timeout or error detected in optimizer artifacts"
fi

# ── Check 7: Budget tier assigned (2pt) ──────────────────────────────
if [ -f "$PREFLIGHT" ]; then
    BUDGET_TIER=$(python3 -c "
import json
try:
    pf = json.load(open('$PREFLIGHT'))
    tier = pf.get('budget_tier', pf.get('tier', ''))
    print(tier)
except:
    print('')
" 2>/dev/null || echo "")
    if [ -n "$BUDGET_TIER" ]; then
        add_score 2 "Budget tier assigned ($BUDGET_TIER)"
    else
        add_issue "No budget tier in pre-flight"
    fi
fi

# ── Check 8: Input SCORECARD referenced (4pt) ────────────────────────
if [ -f "$PREFLIGHT" ]; then
    SC_REF=$(python3 -c "
import json
try:
    pf = json.load(open('$PREFLIGHT'))
    composite = pf.get('input_composite', pf.get('scorecard_composite', pf.get('composite', 0)))
    print(composite)
except:
    print(0)
" 2>/dev/null || echo "0")
    if [ "$SC_REF" -gt 0 ] 2>/dev/null; then
        add_score 4 "Input SCORECARD composite referenced ($SC_REF)"
    else
        add_issue "No input SCORECARD composite in pre-flight"
    fi
fi

# ── Check 9: Approved findings >=1 in plan (2pt) ─────────────────────
if [ -f "$PLAN" ]; then
    # Look for positive approval indicators: "(APPROVED)", "## Approved", "Status: Approved"
    # Exclude negative phrases like "No findings approved" or "0 approved"
    APPROVED_COUNT=$(grep -ciE '(\(APPROVED\)|## Approved|Status:\s*Approved|findings?.*approved.*[1-9])' "$PLAN" 2>/dev/null || echo "0")
    if [ "$APPROVED_COUNT" -ge 1 ]; then
        add_score 2 "Plan contains approved findings ($APPROVED_COUNT)"
    else
        add_issue "0 approved findings in OPTIMIZATION_PLAN.md"
    fi
fi

# ── Check 10: Target files referenced in plan (2pt) ──────────────────
if [ -f "$PLAN" ]; then
    # Look for file path patterns: paths with extensions or directory separators
    FILE_REFS=$(grep -cE '(\./|/[a-zA-Z_-]+\.(sh|py|md|json|yml|yaml|js|ts|toml)|[a-zA-Z_-]+/[a-zA-Z_-]+\.[a-z]+)' "$PLAN" 2>/dev/null || echo "0")
    if [ "$FILE_REFS" -ge 1 ]; then
        add_score 2 "Plan references target files ($FILE_REFS references)"
    else
        add_issue "0 target files referenced in OPTIMIZATION_PLAN.md"
    fi
fi

# ── Check 11: Command-output ROI (2pt) ───────────────────────────────
set +e
COMMAND_OUTPUT_VIOLATIONS_JSON="$(detect_command_output_noise 2>/dev/null)"
COMMAND_OUTPUT_RC=$?
set -e
COMMAND_OUTPUT_ROI_RECEIPT="$(build_command_output_roi_receipt)"
COMMAND_OUTPUT_SCANNED_COUNT="$(
    COMMAND_OUTPUT_ROI_RECEIPT="$COMMAND_OUTPUT_ROI_RECEIPT" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("COMMAND_OUTPUT_ROI_RECEIPT") or "{}")
print(sum(1 for row in payload.get("governed_artifacts", []) if row.get("scanned") is True))
PY
)"
if [ "$COMMAND_OUTPUT_RC" -eq 0 ] && [ "$COMMAND_OUTPUT_SCANNED_COUNT" -gt 0 ]; then
    add_score 2 "Command output summarized instead of copied as raw dumps"
elif [ "$COMMAND_OUTPUT_SCANNED_COUNT" -eq 0 ]; then
    add_issue "Command-output ROI not measured: no governed optimizer artifacts were present to scan"
else
    COMMAND_OUTPUT_SUMMARY="$(
        COMMAND_OUTPUT_VIOLATIONS_JSON="$COMMAND_OUTPUT_VIOLATIONS_JSON" python3 - <<'PY'
import json
import os

try:
    rows = json.loads(os.environ.get("COMMAND_OUTPUT_VIOLATIONS_JSON") or "[]")
except Exception:
    rows = []
print("; ".join(f"{row.get('artifact')}: {row.get('reason')}" for row in rows) or "raw command transcript detected")
PY
    )"
    add_issue "Command-output ROI violation: summarize command evidence and retain raw logs separately ($COMMAND_OUTPUT_SUMMARY)"
fi

# ── Output ────────────────────────────────────────────────────────────
if [ "$JSON_MODE" = "true" ]; then
    ISSUES_JSON=$(printf '%b' "$ISSUES" | sed 's/^  - //' | python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
" 2>/dev/null || echo '[]')
    VERDICT="PASS"
    if [ "$SCORE" -lt 18 ]; then VERDICT="FAIL"; fi
    if [ "$SCORE" -ge 18 ] && [ "$SCORE" -lt 23 ]; then VERDICT="WARN"; fi
    if [ "${COMMAND_OUTPUT_RC:-0}" -ne 0 ]; then VERDICT="FAIL"; fi

    COMMAND_OUTPUT_ROI_RECEIPT="$COMMAND_OUTPUT_ROI_RECEIPT" python3 -c "
import json, os, sys
result = {
    'score': $SCORE,
    'max': $MAX,
    'verdict': '$VERDICT',
    'output_dir': '$OPT_DIR',
    'issues': $ISSUES_JSON,
    'command_output_roi_receipt': json.loads(os.environ.get('COMMAND_OUTPUT_ROI_RECEIPT') or '{}'),
    'timestamp': __import__('datetime').datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
}
json.dump(result, sys.stdout, indent=2)
print()
"
else
    echo "OPERATION EVAL: Optimization Quality Assessment"
    echo "  Output dir: $OPT_DIR"
    echo ""
    printf "%b" "$EVIDENCE"
    if [ -n "$ISSUES" ]; then
        echo ""
        echo "Issues detected (session grader would miss these):"
        printf "%b" "$ISSUES"
    fi
    echo ""
    VERDICT="PASS"
    if [ "$SCORE" -lt 18 ]; then VERDICT="FAIL"; fi
    if [ "$SCORE" -ge 18 ] && [ "$SCORE" -lt 23 ]; then VERDICT="WARN"; fi
    if [ "${COMMAND_OUTPUT_RC:-0}" -ne 0 ]; then VERDICT="FAIL"; fi
    echo "OPERATION EVAL: $SCORE/$MAX ($VERDICT)"
    if [ "$VERDICT" = "FAIL" ]; then
        echo "  NOTE: Score below 18/$MAX threshold or command-output ROI failed. Optimization output quality is degraded."
    fi
fi

exit 0

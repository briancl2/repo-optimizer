#!/usr/bin/env bash
# repo-optimizer.sh — 4-phase optimization pipeline orchestrator.
#
# Usage: bash scripts/repo-optimizer.sh <repo_path> <audit_dir> [output_dir] [--patch]
#
# Inputs:
#   repo_path  — Target repository to optimize
#   audit_dir  — Directory containing SCORECARD.json + AUDIT_REPORT.md (from repo-auditor)
#   output_dir — Where to write optimization artifacts (default: optimizer_output)
#   --patch    — Enable patch generation (default: report-only)
#
# Outputs:
#   OPTIMIZATION_PLAN.md       — Human-readable plan
#   OPTIMIZATION_SCORECARD.json — Machine-readable results
#   PATCH_PACK/*.patch         — Unified diff patches (only with --patch)
#
# Environment:
#   OPTIMIZER_PREFLIGHT_ONLY=true  Skip Copilot-backed phases 2-4 and emit
#                                  pre-flight stubs only. Intended for
#                                  deterministic tests and readiness probes.
#
# Pipeline:
#   Phase 1: Pre-flight (read SCORECARD, identify bottom-2 dimensions)
#   Phase 2: Discovery (4 domain subagents — requires LLM)
#   Phase 3: Critic (adversarial review — requires LLM)
#   Phase 4: Synthesis + optional patch generation
#
# Standard mode (this script) runs pre-flight deterministically,
# then outputs the optimization context for LLM agent phases.

set -euo pipefail

REPO="${1:?Usage: repo-optimizer.sh <repo_path> <audit_dir> [output_dir] [--patch]}"
AUDIT_DIR="${2:?Usage: repo-optimizer.sh <repo_path> <audit_dir> [output_dir] [--patch]}"
OUTPUT_DIR="${3:-optimizer_output}"
PATCH_MODE="false"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT_ONLY_RAW="$(printf '%s' "${OPTIMIZER_PREFLIGHT_ONLY:-false}" | tr '[:upper:]' '[:lower:]')"
PREFLIGHT_ONLY="false"

case "$PREFLIGHT_ONLY_RAW" in
    1|true|yes)
        PREFLIGHT_ONLY="true"
        ;;
esac

# Parse --patch flag
for arg in "$@"; do
    if [ "$arg" = "--patch" ]; then
        PATCH_MODE="true"
    fi
done

# Validate inputs
if [ ! -d "$REPO" ]; then
    echo "ERROR: Repository not found: $REPO" >&2
    exit 1
fi

if [ ! -f "$AUDIT_DIR/SCORECARD.json" ]; then
    echo "ERROR: SCORECARD.json not found in $AUDIT_DIR" >&2
    echo "  Run repo-auditor first: make audit TARGET=$REPO" >&2
    exit 1
fi

# ── C4: Shared lockdir (H3 fix: single definition, passed to guard) ──
LOCKDIR="/tmp/repo-optimizer-locks"

GUARD_SCRIPT="$SCRIPT_DIR/operation-guard.sh"
if [ -x "$GUARD_SCRIPT" ]; then
    if ! bash "$GUARD_SCRIPT" "$REPO" --lockdir "$LOCKDIR" 2>&1; then
        echo "ERROR: Operation guard FAILED. Aborting optimization." >&2
        exit 1
    fi
fi

# ── C4: Acquire operation lock (PID matches this process) ────────────
LOCKFILE="$LOCKDIR/$(echo "$REPO" | tr '/' '_').lock"
mkdir -p "$LOCKDIR"
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

REPO_NAME="$(basename "$REPO")"
mkdir -p "$OUTPUT_DIR"

DISCOVERY_CONTEXT_FILE="$OUTPUT_DIR/runtime-safe-target-context.md"
RUNTIME_RECEIPTS="$OUTPUT_DIR/RUNTIME_RECEIPTS.json"
DISCOVERY_OK=0
DISCOVERY_FAIL=0
CRITIC_STATUS="not_run"
SYNTH_STATUS="not_run"
PATCH_STATUS="not_requested"
COMMAND_BLOCKED="false"
PATCHES_VALID=0
RUNTIME_NOTES=""
CRITIC_PHASE_RECEIPT="$OUTPUT_DIR/critic-phase-receipt.json"
SYNTH_PHASE_RECEIPT="$OUTPUT_DIR/synthesis-phase-receipt.json"
CRITIC_RECEIPT_CLASS="not_run"
SYNTH_RECEIPT_CLASS="not_run"

append_runtime_note() {
    local note="$1"
    if [ -z "$note" ]; then
        return 0
    fi
    if [ -n "$RUNTIME_NOTES" ]; then
        RUNTIME_NOTES="${RUNTIME_NOTES}; "
    fi
    RUNTIME_NOTES="${RUNTIME_NOTES}${note}"
}

# Discovery phases must preserve the latest findings-style markdown artifact,
# not whichever assistant summary happens to be emitted last.
run_copilot_capture_discovery_payload() {
    local model="$1"
    local prompt_text="$2"
    local output_file="$3"
    local timeout_seconds="$4"
    local raw_file="${output_file}.jsonl"

    rm -f "$output_file" "$raw_file"

    if [ "$_has_timeout" = true ]; then
        if ! (cd "$SCRIPT_DIR/.." && "$_to" "$timeout_seconds" copilot --model "$model" \
            -p "$prompt_text" --allow-all --no-ask-user --output-format json \
            < /dev/null > "$raw_file" 2>/dev/null); then
            return 1
        fi
    else
        if ! (cd "$SCRIPT_DIR/.." && copilot --model "$model" \
            -p "$prompt_text" --allow-all --no-ask-user --output-format json \
            < /dev/null > "$raw_file" 2>/dev/null); then
            return 1
        fi
    fi

    python3 - "$raw_file" "$output_file" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HEADER_KEYWORDS = (
    "finding",
    "severity",
    "file",
    "verification",
    "evidence",
    "recommendation",
    "rank",
    "type",
    "line/section",
    "token impact",
)


def strip_numbered_prefixes(text: str) -> str:
    lines = text.splitlines()
    numbered = sum(1 for line in lines if re.match(r"^\d+\.\s", line))
    if numbered >= 2:
        return "\n".join(re.sub(r"^\d+\.\s?", "", line) for line in lines)
    return text


def normalize_artifact_text(text: str) -> str:
    normalized = strip_numbered_prefixes(text).strip()
    if not normalized:
        return ""

    lines = normalized.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    if lines and re.fullmatch(r"<exited with exit code \d+>", lines[-1].strip()):
        lines.pop()
    while lines and not lines[-1].strip():
        lines.pop()

    return "\n".join(lines).strip()


def trim_to_findings_table(text: str) -> str:
    normalized = normalize_artifact_text(text)
    if not normalized:
        return ""

    lines = normalized.splitlines()
    for start, line in enumerate(lines):
        if not line.strip().startswith("|"):
            continue

        table_lines: list[str] = []
        for candidate in lines[start:]:
            stripped = candidate.strip()
            if stripped.startswith("|"):
                table_lines.append(candidate.rstrip())
                continue
            if table_lines:
                break

        if len(table_lines) < 3:
            continue

        header = table_lines[0].lower()
        if sum(keyword in header for keyword in HEADER_KEYWORDS) < 2:
            continue

        if "---" not in table_lines[1]:
            continue

        data_rows = [row for row in table_lines[2:] if row.count("|") >= 2]
        if not data_rows:
            continue

        return "\n".join(table_lines).strip()

    return ""


raw_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
candidates: list[tuple[int, str]] = []
delta_chunks: dict[str, list[str]] = {}
delta_positions: dict[str, int] = {}

for index, line in enumerate(raw_path.read_text(encoding="utf-8", errors="replace").splitlines()):
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        continue

    event_type = payload.get("type")
    if event_type == "assistant.message_delta":
        data = payload.get("data", {})
        message_id = str(data.get("messageId", ""))
        delta_content = data.get("deltaContent", "")
        if not isinstance(delta_content, str):
            delta_content = str(delta_content)
        delta_chunks.setdefault(message_id, []).append(delta_content)
        delta_positions[message_id] = index
        continue

    if event_type == "tool.execution_complete":
        data = payload.get("data", {})
        result = data.get("result", {})
        content = result.get("content", "")
        if not isinstance(content, str):
            content = str(content)
        candidate = trim_to_findings_table(content)
        if candidate:
            candidates.append((index, candidate))
        continue

    if event_type != "assistant.message":
        continue

    data = payload.get("data", {})
    content = data.get("content", "")
    if not isinstance(content, str):
        content = str(content)
    candidate = trim_to_findings_table(content)
    if candidate:
        candidates.append((index, candidate))

for message_id, parts in delta_chunks.items():
    candidate = trim_to_findings_table("".join(parts))
    if candidate:
        candidates.append((delta_positions.get(message_id, -1), candidate))

if not candidates:
    raise SystemExit(1)

_, content = max(candidates, key=lambda item: item[0])
out_path.write_text(content if content.endswith("\n") else content + "\n", encoding="utf-8")
PY
}

phase_receipt_field() {
    local receipt_file="$1"
    local field_path="$2"
    python3 - "$receipt_file" "$field_path" <<'PY'
from __future__ import annotations

import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

value = payload
for part in sys.argv[2].split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

write_phase_receipt_stub() {
    local receipt_file="$1"
    local phase="$2"
    local status="$3"
    local receipt_class="$4"
    local artifact_file="$5"
    local raw_file="$6"
    local note="${7:-}"

    python3 - "$receipt_file" "$phase" "$status" "$receipt_class" "$artifact_file" "$raw_file" "$note" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

receipt_file, phase, status, receipt_class, artifact_file, raw_file, note = sys.argv[1:8]
notes = [note] if note else []
payload = {
    "phase": phase,
    "status": status,
    "receipt_class": receipt_class,
    "artifact_contract": "final_non_tool_assistant_message_markdown",
    "artifact_path": artifact_file,
    "raw_path": raw_file,
    "artifact_written": False,
    "copilot_exit_code": 0,
    "command_blocked_detected": False,
    "assistant_message_count": 0,
    "assistant_message_nonempty_count": 0,
    "assistant_messages_with_tool_requests": 0,
    "non_tool_assistant_message_count": 0,
    "assistant_message_delta_count": 0,
    "last_event_type": "",
    "last_assistant_message_content_length": 0,
    "last_assistant_message_tool_request_count": 0,
    "notes": notes,
}
Path(receipt_file).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

run_copilot_phase_with_receipt() {
    local phase="$1"
    local model="$2"
    local prompt_text="$3"
    local output_file="$4"
    local timeout_seconds="$5"
    local receipt_file="$6"
    local raw_file="${output_file}.jsonl"
    local copilot_exit=0

    rm -f "$output_file" "$raw_file" "$receipt_file"

    if [ "$_has_timeout" = true ]; then
        if ! (cd "$SCRIPT_DIR/.." && "$_to" "$timeout_seconds" copilot --model "$model" \
            -p "$prompt_text" --allow-all --no-ask-user --output-format json \
            < /dev/null > "$raw_file" 2>/dev/null); then
            copilot_exit=$?
        fi
    else
        if ! (cd "$SCRIPT_DIR/.." && copilot --model "$model" \
            -p "$prompt_text" --allow-all --no-ask-user --output-format json \
            < /dev/null > "$raw_file" 2>/dev/null); then
            copilot_exit=$?
        fi
    fi

    python3 "$SCRIPT_DIR/classify-phase-output.py" \
        --phase "$phase" \
        --raw "$raw_file" \
        --artifact "$output_file" \
        --copilot-exit-code "$copilot_exit" > "$receipt_file"

    [ "$(phase_receipt_field "$receipt_file" "status")" = "completed" ]
}

write_safe_discovery_context() {
    python3 - "$REPO" "$DISCOVERY_CONTEXT_FILE" <<'PY'
from __future__ import annotations

import os
import sys
from pathlib import Path

repo = Path(sys.argv[1])
output = Path(sys.argv[2])
exclude_dirs = {".git", "node_modules", "work", "runs", "dist", "build", "__pycache__"}
text_exts = {".md", ".sh", ".py", ".json", ".yaml", ".yml", ".toml", ".txt"}

records = []
for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in exclude_dirs]
    for name in files:
        path = Path(root) / name
        rel = path.relative_to(repo)
        line_count = ""
        if path.suffix in text_exts:
            try:
                line_count = str(sum(1 for _ in path.open(encoding="utf-8", errors="replace")))
            except OSError:
                line_count = ""
        records.append((str(rel), line_count))

ai_surface_files = []
workflow_files = []
for rel, line_count in records:
    if rel.endswith("AGENTS.md") or rel.endswith(".agent.md") or rel.endswith(".prompt.md") or rel.endswith("SKILL.md"):
        ai_surface_files.append((rel, line_count))
    lowered = rel.lower()
    if lowered.startswith("tools/") or lowered.startswith("scripts/"):
        workflow_files.append((rel, line_count))

large_files = [
    (rel, line_count)
    for rel, line_count in records
    if line_count and int(line_count) >= 120
]
large_files.sort(key=lambda item: int(item[1]), reverse=True)

output.parent.mkdir(parents=True, exist_ok=True)
with output.open("w", encoding="utf-8") as handle:
    handle.write("# Runtime-Safe Target Context\n\n")
    handle.write("> Deterministic inventory for optimizer discovery. Read this first before any optional shell exploration.\n\n")

    handle.write("## AI Surfaces\n\n")
    handle.write("| path | lines |\n|---|---:|\n")
    for rel, line_count in ai_surface_files[:40]:
        handle.write(f"| {rel} | {line_count or 'n/a'} |\n")
    if not ai_surface_files:
        handle.write("| none | n/a |\n")

    handle.write("\n## Workflow And Script Surfaces\n\n")
    handle.write("| path | lines |\n|---|---:|\n")
    for rel, line_count in workflow_files[:60]:
        handle.write(f"| {rel} | {line_count or 'n/a'} |\n")
    if not workflow_files:
        handle.write("| none | n/a |\n")

    handle.write("\n## Largest Text Files\n\n")
    handle.write("| path | lines |\n|---|---:|\n")
    for rel, line_count in large_files[:30]:
        handle.write(f"| {rel} | {line_count} |\n")
    if not large_files:
        handle.write("| none | n/a |\n")
PY
}

write_runtime_receipts() {
    python3 - "$RUNTIME_RECEIPTS" "$PATCH_MODE" "$PREFLIGHT_ONLY" "$DISCOVERY_OK" "$DISCOVERY_FAIL" \
        "$PATCH_STATUS" "$COMMAND_BLOCKED" "$PATCHES_VALID" "$DISCOVERY_CONTEXT_FILE" "$RUNTIME_NOTES" \
        "$CRITIC_PHASE_RECEIPT" "$SYNTH_PHASE_RECEIPT" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    out_path,
    patch_mode,
    preflight_only,
    discovery_ok,
    discovery_fail,
    patch_status,
    command_blocked,
    patches_valid,
    discovery_context_file,
    runtime_notes,
    critic_receipt_file,
    synth_receipt_file,
) = sys.argv[1:13]

notes = [note.strip() for note in runtime_notes.split(";") if note.strip()]


def load_receipt(path_str: str, phase: str) -> dict:
    path = Path(path_str)
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {
        "phase": phase,
        "status": "not_run",
        "receipt_class": "not_run",
    }


critic_receipt = load_receipt(critic_receipt_file, "critic")
synth_receipt = load_receipt(synth_receipt_file, "synthesis")
payload = {
    "schema_version": "1.0.0",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "patch_mode": patch_mode == "true",
    "preflight_only": preflight_only == "true",
    "command_blocked_detected": command_blocked == "true",
    "discovery_context_file": discovery_context_file,
    "phases": {
        "discovery": {
            "ok_count": int(discovery_ok),
            "fail_count": int(discovery_fail),
        },
        "critic": critic_receipt,
        "synthesis": synth_receipt,
        "patch_generation": {
            "status": patch_status,
            "patches_valid": int(patches_valid),
        },
    },
    "notes": notes,
}
Path(out_path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

echo "================================================================"
echo "Repo Optimizer: $REPO_NAME"
echo "================================================================"
echo ""
echo "Target:     $REPO"
echo "Audit dir:  $AUDIT_DIR"
echo "Output:     $OUTPUT_DIR"
echo "Patch mode: $PATCH_MODE"
echo ""

# ============================================================
# Phase 1: Pre-flight (deterministic)
# ============================================================
echo "--- Phase 1: Pre-flight ---"

# Read SCORECARD.json
COMPOSITE=$(python3 -c "import json; d=json.load(open('$AUDIT_DIR/SCORECARD.json')); print(d.get('composite', 0))" 2>/dev/null || echo "?")
echo "  Composite score: $COMPOSITE/100"

# Count files in target repo for budget tiering (exclude .git, node_modules)
FILE_COUNT=$(find "$REPO" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')
echo "  File count: $FILE_COUNT"

# Determine budget tier
if [ "$FILE_COUNT" -lt 200 ]; then
    BUDGET_TIER="full"
elif [ "$FILE_COUNT" -le 1000 ]; then
    BUDGET_TIER="focused"
else
    BUDGET_TIER="minimal"
fi
echo "  Budget tier: $BUDGET_TIER"

# Build discovery scope based on tier
ELIGIBLE_FILES="$FILE_COUNT"
SCOPE_DESC="All files"

if [ "$BUDGET_TIER" = "focused" ]; then
    # AI surfaces + governance files only
    ELIGIBLE_FILES=$(find "$REPO" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \( \
        -name "AGENTS.md" -o -name "*.agent.md" -o -name "*.prompt.md" \
        -o -name "*.instructions.md" -o -name "copilot-instructions.md" \
        -o -name ".cursorrules" -o -name "SKILL.md" \
        -o -name "Makefile" -o -name "README.md" -o -name "STATUS.md" \
        -o -name "LEARNINGS.md" -o -name ".gitignore" \
        -o -name "package.json" -o -name "pyproject.toml" \
        -o -name "Cargo.toml" -o -name "go.mod" \
    \) 2>/dev/null | wc -l | tr -d ' ')
    # Also count YAML files in root
    ROOT_YAML=$(find "$REPO" -maxdepth 1 -type f -not -path '*/.git/*' \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | wc -l | tr -d ' ')
    ELIGIBLE_FILES=$((ELIGIBLE_FILES + ROOT_YAML))
    SCOPE_DESC="AI surfaces + governance files"
elif [ "$BUDGET_TIER" = "minimal" ]; then
    # Scored-dimension files only — use bottom-2 dimension heuristics
    # D1 (governance): Makefile, README, .gitignore, CI configs
    # D2 (surface health): .agents/, *.agent.md, *.prompt.md, AGENTS.md
    # D3 (velocity): recent commits → hard to scope by file, use AI surfaces
    # D4 (organicity): skills/, SKILL.md, .agents/skills/
    # D5 (trajectory): STATUS.md, LEARNINGS.md, HANDOFF-*, ROADMAP.md
    # Fallback: AI surfaces + governance (same as focused) when mapping is unclear
    ELIGIBLE_FILES=$(find "$REPO" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \( \
        -name "AGENTS.md" -o -name "*.agent.md" -o -name "*.prompt.md" \
        -o -name "SKILL.md" -o -name "Makefile" -o -name "README.md" \
        -o -name "STATUS.md" -o -name "LEARNINGS.md" -o -name ".gitignore" \
    \) 2>/dev/null | wc -l | tr -d ' ')
    SCOPE_DESC="Scored-dimension files (bottom-2 focus)"
fi

COVERAGE_PCT=0
if [ "$FILE_COUNT" -gt 0 ]; then
    COVERAGE_PCT=$(python3 -c "print(round($ELIGIBLE_FILES / $FILE_COUNT * 100, 1))" 2>/dev/null || echo "?")
fi
echo "  Discovery scope: $ELIGIBLE_FILES/$FILE_COUNT files ($COVERAGE_PCT%) — $SCOPE_DESC"

# Find bottom-2 dimensions
echo "  Analyzing dimensions..."
python3 -c "
import json, sys

with open('$AUDIT_DIR/SCORECARD.json') as f:
    data = json.load(f)

dims = data.get('dimensions', {})
scores = []
for name, info in sorted(dims.items()):
    score = info.get('score', 0)
    max_score = info.get('max', 20)
    scores.append((name, score, max_score))
    print(f'  {name}: {score}/{max_score}')

# Sort by score ascending
scores.sort(key=lambda x: x[1])

print()
if len(scores) >= 2:
    print(f'  Bottom 2: {scores[0][0]} ({scores[0][1]}/{scores[0][2]}), {scores[1][0]} ({scores[1][1]}/{scores[1][2]})')
    # Write pre-flight context
    with open('$OUTPUT_DIR/pre-flight.json', 'w') as f:
        json.dump({
            'target': '$REPO_NAME',
            'composite': data.get('composite', 0),
            'bottom_2': [scores[0][0], scores[1][0]],
            'bottom_dimensions': [scores[0][0], scores[1][0]],
            'all_dimensions': {s[0]: {'score': s[1], 'max': s[2]} for s in scores},
            'patch_mode': $( [ "$PATCH_MODE" = "true" ] && echo "True" || echo "False" ),
            'budget_tier': '$BUDGET_TIER',
            'file_count': $FILE_COUNT,
            'discovery_scope': {
                'tier': '$BUDGET_TIER',
                'eligible_files': $ELIGIBLE_FILES,
                'total_files': $FILE_COUNT,
                'coverage_pct': $COVERAGE_PCT,
                'scope_description': '$SCOPE_DESC'
            }
        }, f, indent=2)
        print(f'  Pre-flight context → $OUTPUT_DIR/pre-flight.json')
" 2>/dev/null || echo "  WARNING: Could not parse SCORECARD.json"

# Check for T2 warnings
T2_WARNINGS=$(python3 -c "
import json
with open('$AUDIT_DIR/SCORECARD.json') as f:
    data = json.load(f)
warnings = data.get('tier2_warnings', {}).get('warnings', [])
for w in warnings:
    print(f'  ⚠️  {w}')
print(f'  Total T2 warnings: {len(warnings)}')
" 2>/dev/null || echo "  No T2 warnings found")
echo "$T2_WARNINGS"

# Check for AUDIT_REPORT.md
if [ -f "$AUDIT_DIR/AUDIT_REPORT.md" ]; then
    REPORT_LINES=$(wc -l < "$AUDIT_DIR/AUDIT_REPORT.md" | tr -d ' ')
    echo "  AUDIT_REPORT.md: ${REPORT_LINES}L"
fi

# Check for OPPORTUNITIES.md (optional advisor input)
if [ -f "$AUDIT_DIR/OPPORTUNITIES.md" ]; then
    OPP_LINES=$(wc -l < "$AUDIT_DIR/OPPORTUNITIES.md" | tr -d ' ')
    echo "  OPPORTUNITIES.md: ${OPP_LINES}L (advisor recommendations available)"
else
    echo "  OPPORTUNITIES.md: not present (advisor not run)"
fi

echo ""
echo "  ✅ Phase 1 complete"

write_safe_discovery_context
append_runtime_note "safe discovery context written to $(basename "$DISCOVERY_CONTEXT_FILE")"

# ============================================================
# Phase 2-4: LLM Agent Phases (subagent dispatch via copilot CLI)
# ============================================================
echo ""
echo "--- Phases 2-4: Domain Discovery + Critic + Synthesis ---"
echo ""
echo "  Pre-flight context written to $OUTPUT_DIR/pre-flight.json"

# Check if copilot CLI is available for direct dispatch
if [ "$PREFLIGHT_ONLY" = "true" ]; then
    echo "  Pre-flight-only mode enabled (OPTIMIZER_PREFLIGHT_ONLY=true) — skipping Copilot-backed phases"
    CRITIC_STATUS="skipped_preflight_only"
    SYNTH_STATUS="skipped_preflight_only"
    CRITIC_RECEIPT_CLASS="preflight_only"
    SYNTH_RECEIPT_CLASS="preflight_only"
    write_phase_receipt_stub \
        "$CRITIC_PHASE_RECEIPT" \
        "critic" \
        "$CRITIC_STATUS" \
        "$CRITIC_RECEIPT_CLASS" \
        "$OUTPUT_DIR/critic-verdicts.md" \
        "$OUTPUT_DIR/critic-verdicts.md.jsonl" \
        "Pre-flight-only mode skipped Copilot-backed critic phase."
    write_phase_receipt_stub \
        "$SYNTH_PHASE_RECEIPT" \
        "synthesis" \
        "$SYNTH_STATUS" \
        "$SYNTH_RECEIPT_CLASS" \
        "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" \
        "$OUTPUT_DIR/OPTIMIZATION_PLAN.md.jsonl" \
        "Pre-flight-only mode skipped Copilot-backed synthesis phase."
    if [ "$PATCH_MODE" = "true" ]; then
        PATCH_STATUS="fail_closed_preflight_only"
    else
        PATCH_STATUS="skipped_preflight_only"
    fi
elif command -v copilot >/dev/null 2>&1; then
    PAYLOADS_DIR="$OUTPUT_DIR/payloads"
    mkdir -p "$PAYLOADS_DIR"

    OPT_MODEL="${OPTIMIZER_DEEP_MODEL:-claude-sonnet-4.5}"
    OPT_TIMEOUT="${OPTIMIZER_TIMEOUT:-180}"
    _to="timeout"; command -v timeout >/dev/null 2>&1 || _to="gtimeout"
    _has_timeout=false; command -v "$_to" >/dev/null 2>&1 && _has_timeout=true
    AGENTS_DIR="$SCRIPT_DIR/../.agents"

    # Phase 2: Dispatch 4 domain agents
    echo "  Phase 2: Domain discovery..."
    OPT_DOMAINS="decomposition consolidation extraction standardization"
    OPT_OK=0
    OPT_FAIL=0

    for domain in $OPT_DOMAINS; do
        agent_file="$AGENTS_DIR/${domain}-optimizer.agent.md"
        payload_file="$PAYLOADS_DIR/${domain}.md"
        if [ ! -f "$agent_file" ]; then
            echo "    [$domain] SKIP: agent file not found"
            OPT_FAIL=$((OPT_FAIL + 1))
            continue
        fi
        echo "    [$domain] dispatching..."
        prompt_text="Read .agents/${domain}-optimizer.agent.md for instructions. Analyze target repo at $REPO using SCORECARD at $AUDIT_DIR/SCORECARD.json. Read $DISCOVERY_CONTEXT_FILE first and prefer that deterministic inventory before any extra shell work. Avoid shell loops, command substitution, arithmetic expansion, or parameter expansion. If extra reads are needed, use direct rg, sed, head, cat, ls, and find commands only. Write findings as a markdown table to stdout."
        dispatch_ok=false
        if run_copilot_capture_discovery_payload "$OPT_MODEL" "$prompt_text" "$payload_file" "$OPT_TIMEOUT"; then
            dispatch_ok=true
        fi
        if [ "$dispatch_ok" = true ] && [ -s "$payload_file" ]; then
            echo "    [$domain] done ($(wc -l < "$payload_file" | tr -d ' ') lines)"
            OPT_OK=$((OPT_OK + 1))
        else
            echo "    [$domain] FAILED"
            OPT_FAIL=$((OPT_FAIL + 1))
            if grep -qi "Command blocked:" "$payload_file" "$payload_file.jsonl" 2>/dev/null; then
                COMMAND_BLOCKED="true"
                append_runtime_note "$domain discovery hit COMMAND_BLOCKED"
            fi
        fi
    done
    DISCOVERY_OK="$OPT_OK"
    DISCOVERY_FAIL="$OPT_FAIL"
    echo "    Discovery: $OPT_OK OK, $OPT_FAIL failed"

    # Phase 3: Critic review
    if [ "$OPT_OK" -gt 0 ] && [ -f "$AGENTS_DIR/repo-optimizer-critic.agent.md" ]; then
        echo ""
        echo "  Phase 3: Critic review..."
        critic_prompt="Read .agents/repo-optimizer-critic.agent.md for instructions. Review all domain findings in $OUTPUT_DIR/payloads/. Use direct read-only commands only; do not use shell loops or command substitution. For each finding, assign verdict: APPROVED, DOWNGRADED, or REJECTED. Must reject at least 1. Return the verdict markdown in your final assistant response only. Do not use shell, heredocs, or execute-tool writes to emit the verdicts; stdout is captured automatically."
        critic_ok=false
        if run_copilot_phase_with_receipt \
            "critic" \
            "claude-opus-4.6" \
            "$critic_prompt" \
            "$OUTPUT_DIR/critic-verdicts.md" \
            "$OPT_TIMEOUT" \
            "$CRITIC_PHASE_RECEIPT"; then
            critic_ok=true
        fi
        CRITIC_STATUS="$(phase_receipt_field "$CRITIC_PHASE_RECEIPT" "status")"
        CRITIC_RECEIPT_CLASS="$(phase_receipt_field "$CRITIC_PHASE_RECEIPT" "receipt_class")"
        if [ "$(phase_receipt_field "$CRITIC_PHASE_RECEIPT" "command_blocked_detected")" = "true" ]; then
            COMMAND_BLOCKED="true"
        fi
        if [ "$critic_ok" = true ] && [ -s "$OUTPUT_DIR/critic-verdicts.md" ]; then
            echo "    Critic review done"
            append_runtime_note "critic receipt class: $CRITIC_RECEIPT_CLASS"
        else
            echo "    Critic review FAIL-CLOSED ($CRITIC_STATUS / $CRITIC_RECEIPT_CLASS)"
            append_runtime_note "critic fail-closed as $CRITIC_STATUS / $CRITIC_RECEIPT_CLASS"
        fi
    elif [ "$OPT_OK" -gt 0 ]; then
        CRITIC_STATUS="skipped_missing_agent"
        CRITIC_RECEIPT_CLASS="missing_agent"
        write_phase_receipt_stub \
            "$CRITIC_PHASE_RECEIPT" \
            "critic" \
            "$CRITIC_STATUS" \
            "$CRITIC_RECEIPT_CLASS" \
            "$OUTPUT_DIR/critic-verdicts.md" \
            "$OUTPUT_DIR/critic-verdicts.md.jsonl" \
            "Critic agent definition was missing."
    else
        CRITIC_STATUS="skipped_no_discovery_payloads"
        CRITIC_RECEIPT_CLASS="no_discovery_payloads"
        write_phase_receipt_stub \
            "$CRITIC_PHASE_RECEIPT" \
            "critic" \
            "$CRITIC_STATUS" \
            "$CRITIC_RECEIPT_CLASS" \
            "$OUTPUT_DIR/critic-verdicts.md" \
            "$OUTPUT_DIR/critic-verdicts.md.jsonl" \
            "No discovery payloads were available for critic review."
    fi

    # Phase 4: Synthesis
    if [ "$OPT_OK" -gt 0 ] && [ -f "$AGENTS_DIR/repo-optimizer-synthesis.agent.md" ] && [ "$CRITIC_STATUS" = "completed" ]; then
        echo ""
        echo "  Phase 4: Synthesis..."
        synth_prompt="Read .agents/repo-optimizer-synthesis.agent.md for instructions. Synthesize all domain findings from $OUTPUT_DIR/payloads/ and critic verdicts from $OUTPUT_DIR/critic-verdicts.md into OPTIMIZATION_PLAN.md. Use direct read-only commands only; avoid shell loops and command substitution. Return the full OPTIMIZATION_PLAN.md markdown in your final assistant response only. Do not use shell, heredocs, or execute-tool writes to create the plan; stdout is captured automatically."
        synth_ok=false
        if run_copilot_phase_with_receipt \
            "synthesis" \
            "claude-opus-4.6" \
            "$synth_prompt" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" \
            "$OPT_TIMEOUT" \
            "$SYNTH_PHASE_RECEIPT"; then
            synth_ok=true
        fi
        SYNTH_STATUS="$(phase_receipt_field "$SYNTH_PHASE_RECEIPT" "status")"
        SYNTH_RECEIPT_CLASS="$(phase_receipt_field "$SYNTH_PHASE_RECEIPT" "receipt_class")"
        if [ "$(phase_receipt_field "$SYNTH_PHASE_RECEIPT" "command_blocked_detected")" = "true" ]; then
            COMMAND_BLOCKED="true"
        fi
        if [ "$synth_ok" = true ]; then
            echo "    Synthesis done"
            append_runtime_note "synthesis receipt class: $SYNTH_RECEIPT_CLASS"
        else
            echo "    Synthesis FAIL-CLOSED ($SYNTH_STATUS / $SYNTH_RECEIPT_CLASS)"
            append_runtime_note "synthesis fail-closed as $SYNTH_STATUS / $SYNTH_RECEIPT_CLASS"
        fi
    elif [ "$OPT_OK" -gt 0 ] && [ "$CRITIC_STATUS" != "completed" ]; then
        SYNTH_STATUS="skipped_upstream_critic_failure"
        SYNTH_RECEIPT_CLASS="upstream_critic_${CRITIC_RECEIPT_CLASS}"
        write_phase_receipt_stub \
            "$SYNTH_PHASE_RECEIPT" \
            "synthesis" \
            "$SYNTH_STATUS" \
            "$SYNTH_RECEIPT_CLASS" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md.jsonl" \
            "Synthesis skipped because critic did not materialize its authoritative artifact."
        append_runtime_note "synthesis skipped after critic $CRITIC_STATUS / $CRITIC_RECEIPT_CLASS"
    elif [ "$OPT_OK" -gt 0 ]; then
        SYNTH_STATUS="skipped_missing_agent"
        SYNTH_RECEIPT_CLASS="missing_agent"
        write_phase_receipt_stub \
            "$SYNTH_PHASE_RECEIPT" \
            "synthesis" \
            "$SYNTH_STATUS" \
            "$SYNTH_RECEIPT_CLASS" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md.jsonl" \
            "Synthesis agent definition was missing."
    else
        SYNTH_STATUS="skipped_no_discovery_payloads"
        SYNTH_RECEIPT_CLASS="no_discovery_payloads"
        write_phase_receipt_stub \
            "$SYNTH_PHASE_RECEIPT" \
            "synthesis" \
            "$SYNTH_STATUS" \
            "$SYNTH_RECEIPT_CLASS" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" \
            "$OUTPUT_DIR/OPTIMIZATION_PLAN.md.jsonl" \
            "No discovery payloads were available for synthesis."
    fi
else
    echo "  copilot CLI not available — generating pre-flight stubs only"
    echo "  To run full optimization:"
    echo "    copilot --model claude-opus-4.6 \\"
    echo "      -p 'Read .agents/repo-optimizer.agent.md. Run phases 2-4 on target $REPO."
    echo "          SCORECARD at $AUDIT_DIR/SCORECARD.json."
    echo "          Write output to $OUTPUT_DIR/.' \\"
    echo "      --allow-all 2>&1 | tee $OUTPUT_DIR/optimizer-stdout.txt"
    CRITIC_STATUS="skipped_no_copilot"
    SYNTH_STATUS="skipped_no_copilot"
    CRITIC_RECEIPT_CLASS="no_copilot"
    SYNTH_RECEIPT_CLASS="no_copilot"
    write_phase_receipt_stub \
        "$CRITIC_PHASE_RECEIPT" \
        "critic" \
        "$CRITIC_STATUS" \
        "$CRITIC_RECEIPT_CLASS" \
        "$OUTPUT_DIR/critic-verdicts.md" \
        "$OUTPUT_DIR/critic-verdicts.md.jsonl" \
        "Copilot CLI was unavailable."
    write_phase_receipt_stub \
        "$SYNTH_PHASE_RECEIPT" \
        "synthesis" \
        "$SYNTH_STATUS" \
        "$SYNTH_RECEIPT_CLASS" \
        "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" \
        "$OUTPUT_DIR/OPTIMIZATION_PLAN.md.jsonl" \
        "Copilot CLI was unavailable."
    if [ "$PATCH_MODE" = "true" ]; then
        PATCH_STATUS="fail_closed_no_copilot"
    else
        PATCH_STATUS="skipped_no_copilot"
    fi
fi

PATCH_COUNT=0
if [ -d "$OUTPUT_DIR/PATCH_PACK" ]; then
    PATCH_COUNT=$(find "$OUTPUT_DIR/PATCH_PACK" -name '*.patch' -type f 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$PATCH_COUNT" -gt 0 ]; then
    for patch in "$OUTPUT_DIR"/PATCH_PACK/*.patch; do
        [ -f "$patch" ] || continue
        if cd "$REPO" && git apply --check "$patch" 2>/dev/null; then
            PATCHES_VALID=$((PATCHES_VALID + 1))
        fi
    done
fi

if [ "$PATCH_MODE" = "true" ]; then
    if [ "$PATCH_COUNT" -gt 0 ]; then
        PATCH_STATUS="patches_present"
    elif [ "$PATCH_STATUS" = "not_requested" ]; then
        if [ "$DISCOVERY_OK" -eq 0 ]; then
            PATCH_STATUS="fail_closed_no_discovery_payloads"
        elif [ "$CRITIC_STATUS" != "completed" ]; then
            PATCH_STATUS="fail_closed_critic_${CRITIC_RECEIPT_CLASS}"
        elif [ "$SYNTH_STATUS" != "completed" ]; then
            PATCH_STATUS="fail_closed_synthesis_${SYNTH_RECEIPT_CLASS}"
        else
            PATCH_STATUS="fail_closed_patch_generation_unavailable"
        fi
    fi
fi

if [ "$COMMAND_BLOCKED" = "true" ]; then
    append_runtime_note "COMMAND_BLOCKED detected in Copilot-backed phases"
fi
if [ "$PATCH_MODE" = "true" ] && [ "$PATCH_COUNT" -eq 0 ]; then
    append_runtime_note "patch mode requested but no patch artifacts were produced"
fi

write_runtime_receipts

# Generate stub OPTIMIZATION_PLAN.md from pre-flight data (only if phases 2-4 didn't produce one)
if [ ! -s "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" ]; then
    PREFLIGHT_SUMMARY=$(python3 -c "
import json
with open('$OUTPUT_DIR/pre-flight.json') as f:
    data = json.load(f)
bottom = data.get('bottom_2', [])
print(f'**Bottom-2 dimensions:** {bottom[0] if len(bottom) > 0 else \"?\"}, {bottom[1] if len(bottom) > 1 else \"?\"}')
print()
print('| Dimension | Score |')
print('|---|---:|')
for name, info in sorted(data.get('all_dimensions', {}).items()):
    print(f'| {name} | {info[\"score\"]}/{info[\"max\"]} |')
" 2>/dev/null || echo "Pre-flight data not available")

    PLAN_STUB_REASON="pre-flight-only, phases 2-4 pending"
    if [ "$PREFLIGHT_ONLY" != "true" ] && { [ "$CRITIC_STATUS" != "completed" ] || [ "$SYNTH_STATUS" != "completed" ]; }; then
        PLAN_STUB_REASON="fail-closed, see RUNTIME_RECEIPTS.json for explicit receipt classes"
    elif [ "$PREFLIGHT_ONLY" != "true" ] && { [ "$DISCOVERY_OK" -gt 0 ] || [ "$DISCOVERY_FAIL" -gt 0 ]; }; then
        PLAN_STUB_REASON="runtime-degraded, see RUNTIME_RECEIPTS.json for phase status"
    fi

    printf '# Optimization Plan: %s\n\n' "$REPO_NAME" > "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '> Generated by repo-optimizer.sh (%s)\n' "$PLAN_STUB_REASON" >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '> Date: %s\n' "$(date +%Y-%m-%d)" >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '> SCORECARD composite: %s/100\n' "$COMPOSITE" >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '> Budget tier: %s (%s files, %s eligible, %s%% coverage)\n\n' "$BUDGET_TIER" "$FILE_COUNT" "$ELIGIBLE_FILES" "$COVERAGE_PCT" >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '## Pre-flight Summary\n\n%s\n\n' "$PREFLIGHT_SUMMARY" >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '## Runtime Status\n\n- Discovery: %s ok / %s failed\n- Critic: %s (%s)\n- Synthesis: %s (%s)\n- Patch generation: %s\n- Runtime receipts: `RUNTIME_RECEIPTS.json`\n\n' "$DISCOVERY_OK" "$DISCOVERY_FAIL" "$CRITIC_STATUS" "$CRITIC_RECEIPT_CLASS" "$SYNTH_STATUS" "$SYNTH_RECEIPT_CLASS" "$PATCH_STATUS" >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
    printf '## Next Steps\n\nUse `RUNTIME_RECEIPTS.json` to determine whether the next move is a rerun, a prompt hardening change, or a fail-closed stop.\n' >> "$OUTPUT_DIR/OPTIMIZATION_PLAN.md"
fi

# Generate OPTIMIZATION_SCORECARD.json with runtime status
python3 -c "
import json
import pathlib
import re
with open('$OUTPUT_DIR/pre-flight.json') as f:
    preflight = json.load(f)

payload_dir = pathlib.Path('$OUTPUT_DIR/payloads')
critic_path = pathlib.Path('$OUTPUT_DIR/critic-verdicts.md')

def table_rows(path):
    if not path.exists():
        return 0
    count = 0
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        stripped = line.strip()
        if not stripped.startswith('|'):
            continue
        if '---' in stripped or 'Rank' in stripped or 'Severity' in stripped:
            continue
        count += 1
    return count

findings_total = 0
categories = {
    'decompose': 0,
    'consolidate': 0,
    'extract': 0,
    'standardize': 0
}
for name, key in (
    ('decomposition.md', 'decompose'),
    ('consolidation.md', 'consolidate'),
    ('extraction.md', 'extract'),
    ('standardization.md', 'standardize'),
):
    rows = table_rows(payload_dir / name)
    categories[key] = rows
    findings_total += rows

critic_text = ''
if critic_path.exists():
    critic_text = critic_path.read_text(encoding='utf-8', errors='replace')

allowed_non_fail_closed = {
    'completed',
    'not_run',
    'skipped_preflight_only',
    'skipped_no_copilot',
    'skipped_no_discovery_payloads',
}

phase_fail_closed = (
    ('$CRITIC_STATUS' not in allowed_non_fail_closed and '$DISCOVERY_OK' != '0')
    or ('$SYNTH_STATUS' not in allowed_non_fail_closed and '$DISCOVERY_OK' != '0')
)

scorecard = {
    'findings_total': findings_total,
    'findings_approved': critic_text.count('[VERDICT: APPROVED]'),
    'findings_rejected': critic_text.count('[VERDICT: REJECTED]'),
    'findings_downgraded': critic_text.count('[VERDICT: DOWNGRADED]'),
    'patches_generated': $PATCH_COUNT,
    'patches_valid': $PATCHES_VALID,
    'expected_delta': 0,
    'categories': categories,
    'meta': {
        'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
        'optimizer_version': '1.0.0',
        'scorecard_input': '$AUDIT_DIR/SCORECARD.json',
        'target': '$REPO_NAME',
        'status': (
            'pre-flight-only'
            if '$PREFLIGHT_ONLY' == 'true'
            else 'fail-closed'
            if '$PATCH_STATUS'.startswith('fail_closed') or phase_fail_closed
            else 'runtime-degraded'
            if '$DISCOVERY_FAIL' != '0'
            else 'completed'
        ),
        'discovery_ok': $DISCOVERY_OK,
        'discovery_fail': $DISCOVERY_FAIL,
        'critic_status': '$CRITIC_STATUS',
        'critic_receipt_class': '$CRITIC_RECEIPT_CLASS',
        'synthesis_status': '$SYNTH_STATUS',
        'synthesis_receipt_class': '$SYNTH_RECEIPT_CLASS',
        'patch_status': '$PATCH_STATUS',
        'runtime_receipts': 'RUNTIME_RECEIPTS.json',
        'command_blocked_detected': '$COMMAND_BLOCKED' == 'true'
    }
}
with open('$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json', 'w') as f:
    json.dump(scorecard, f, indent=2)
print('  ✅ OPTIMIZATION_SCORECARD.json written')
" 2>/dev/null || echo "  WARNING: Could not write OPTIMIZATION_SCORECARD.json"

echo "  ✅ OPTIMIZATION_PLAN.md written"
echo ""
echo "================================================================"
echo "Optimizer Pre-flight Complete: $REPO_NAME"
echo "================================================================"
echo ""
echo "Outputs:"
echo "  $OUTPUT_DIR/pre-flight.json"
echo "  $OUTPUT_DIR/runtime-safe-target-context.md"
echo "  $OUTPUT_DIR/critic-phase-receipt.json"
echo "  $OUTPUT_DIR/synthesis-phase-receipt.json"
echo "  $OUTPUT_DIR/OPTIMIZATION_PLAN.md"
echo "  $OUTPUT_DIR/OPTIMIZATION_SCORECARD.json"
echo "  $OUTPUT_DIR/RUNTIME_RECEIPTS.json"
echo "================================================================"

# ── C1: Runtime evaluation of optimization quality (Stage 11.2) ──────
EVAL_SCRIPT="$SCRIPT_DIR/score-operation.sh"
if [ -x "$EVAL_SCRIPT" ]; then
    echo ""
    bash "$EVAL_SCRIPT" "$OUTPUT_DIR" || true
    bash "$EVAL_SCRIPT" "$OUTPUT_DIR" --json > "$OUTPUT_DIR/OPERATION_EVAL.json" 2>/dev/null || true
fi

# Lockfile cleanup handled by trap EXIT (set at lock acquisition)

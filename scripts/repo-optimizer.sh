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

REPO_NAME="$(basename "$REPO")"
mkdir -p "$OUTPUT_DIR"

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
    ELIGIBLE_FILES=$(find "$REPO" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \(
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

# ============================================================
# Phase 2-4: LLM Agent Phases (require Copilot invocation)
# ============================================================
echo ""
echo "--- Phases 2-4: LLM Agent Discovery + Critic + Synthesis ---"
echo ""
echo "  Pre-flight context written to $OUTPUT_DIR/pre-flight.json"
echo "  To run full optimization with LLM agents:"
echo ""
echo "    copilot --model claude-opus-4.6 \\"
echo "      -p 'Read .agents/repo-optimizer.agent.md. Run phases 2-4 on target $REPO."
echo "          SCORECARD at $AUDIT_DIR/SCORECARD.json."
echo "          Write output to $OUTPUT_DIR/.' \\"
echo "      --allow-all 2>&1 | tee $OUTPUT_DIR/optimizer-stdout.txt"
echo ""

# Generate stub OPTIMIZATION_PLAN.md from pre-flight data
cat > "$OUTPUT_DIR/OPTIMIZATION_PLAN.md" << PLANEOF
# Optimization Plan: $REPO_NAME

> Generated by repo-optimizer.sh (pre-flight only, phases 2-4 pending)
> Date: $(date +%Y-%m-%d)
> SCORECARD composite: $COMPOSITE/100
> Budget tier: $BUDGET_TIER ($FILE_COUNT files, $ELIGIBLE_FILES eligible, $COVERAGE_PCT% coverage)

## Pre-flight Summary

$(python3 -c "
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

## Next Steps

Run phases 2-4 with LLM agents to discover, review, and generate patches.
PLANEOF

# Generate stub OPTIMIZATION_SCORECARD.json
python3 -c "
import json
with open('$OUTPUT_DIR/pre-flight.json') as f:
    preflight = json.load(f)
scorecard = {
    'findings_total': 0,
    'findings_approved': 0,
    'findings_rejected': 0,
    'findings_downgraded': 0,
    'patches_generated': 0,
    'patches_valid': 0,
    'expected_delta': 0,
    'categories': {
        'decompose': 0,
        'consolidate': 0,
        'extract': 0,
        'standardize': 0
    },
    'meta': {
        'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
        'optimizer_version': '1.0.0',
        'scorecard_input': '$AUDIT_DIR/SCORECARD.json',
        'target': '$REPO_NAME',
        'status': 'pre-flight-only'
    }
}
with open('$OUTPUT_DIR/OPTIMIZATION_SCORECARD.json', 'w') as f:
    json.dump(scorecard, f, indent=2)
print('  ✅ OPTIMIZATION_SCORECARD.json written (pre-flight stub)')
" 2>/dev/null || echo "  WARNING: Could not write OPTIMIZATION_SCORECARD.json"

echo "  ✅ OPTIMIZATION_PLAN.md written (pre-flight stub)"
echo ""
echo "================================================================"
echo "Optimizer Pre-flight Complete: $REPO_NAME"
echo "================================================================"
echo ""
echo "Outputs:"
echo "  $OUTPUT_DIR/pre-flight.json"
echo "  $OUTPUT_DIR/OPTIMIZATION_PLAN.md"
echo "  $OUTPUT_DIR/OPTIMIZATION_SCORECARD.json"
echo "================================================================"

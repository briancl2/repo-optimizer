# Invocation Contract -- repo-optimizer

> Version: 1.0 | Spec: 054 | Date: 2026-02-24

## Purpose

This contract defines the interface for invoking repo-optimizer, whether
called by an outer-loop orchestrator (run-continuous-loop.sh) or by an
agent (copilot CLI). All consumers must follow this contract.

## Required Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `repo_path` | filesystem path | YES | Absolute path to target repository |
| `audit_dir` | filesystem path | YES | Directory containing SCORECARD.json + AUDIT_REPORT.md from repo-auditor |
| `output_dir` | filesystem path | NO | Where to write optimization artifacts (default: `optimizer_output`) |
| `--patch` | flag | NO | Enable patch generation (default: report-only) |

## Expected Outputs

| Output | Always | Description |
|---|---|---|
| `OPTIMIZATION_PLAN.md` | YES | Human-readable optimization plan |
| `OPTIMIZATION_SCORECARD.json` | YES | Machine-readable scoring of optimization |
| `pre-flight.json` | YES | Pre-flight analysis (budget tier, bottom-2 dimensions) |
| `PATCH_PACK/*.patch` | Only with --patch | Unified diff patches |

## Error Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | SCORECARD.json not found in audit_dir |
| 1 | AUDIT_REPORT.md not found in audit_dir |
| 1 | Target repo path does not exist |
| 1 | Pre-flight failed |

## Invocation Patterns

### Pattern A: Bash (from orchestrator)

```bash
bash scripts/repo-optimizer.sh "$REPO" "$AUDIT_DIR" "$OUTPUT_DIR"
# With patches:
bash scripts/repo-optimizer.sh "$REPO" "$AUDIT_DIR" "$OUTPUT_DIR" --patch
```

### Pattern B: Agent (from copilot CLI)

```bash
cd ~/repos/repo-optimizer && timeout 600 copilot --model claude-opus-4.6 \
  -p "Read .agents/repo-optimizer.agent.md. Optimize $REPO. \
      AUDIT_DIR: $AUDIT_DIR. OUTPUT: $OUTPUT_DIR." \
  --allow-all --no-ask-user
```

**CRITICAL (L274/L6):** The agent MUST call `repo-optimizer.sh` as a single
command via `run_in_terminal`. Do NOT dispatch discovery subagents individually.
The bash orchestrator manages directory layout and phase sequencing.

## Artifact Path Conventions

All outputs go to `$output_dir/`:
- `$output_dir/pre-flight.json`
- `$output_dir/OPTIMIZATION_PLAN.md`
- `$output_dir/OPTIMIZATION_SCORECARD.json`
- `$output_dir/PATCH_PACK/*.patch` (if --patch)

## Version History

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-02-24 | Initial contract (spec 054) |

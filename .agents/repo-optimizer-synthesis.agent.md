---
name: repo-optimizer-synthesis
description: >
  Synthesize findings from 4 domain optimizers and critic verdicts into
  a cohesive OPTIMIZATION_PLAN.md with prioritized action items.
model: claude-opus-4.7
tools: [read, search]
stop_rules:
  timeout_seconds: 600
constraints:
  - read all domain payloads and critic verdicts before synthesizing
  - only include APPROVED or DOWNGRADED findings
  - cite findings by rank + domain
  - single-level nesting — do not spawn subagents
  - avoid shell loops, command substitution, arithmetic expansion, or parameter expansion
  - return the full plan markdown in the final assistant response only
  - do not use shell, heredocs, or execute-tool writes to create the plan
---

# Optimizer Synthesis Agent

Synthesize findings from all domain optimizers + critic into OPTIMIZATION_PLAN.md.

## Inputs

Read all payloads:
- decomposition-optimizer findings
- consolidation-optimizer findings
- extraction-optimizer findings
- standardization-optimizer findings
- repo-optimizer-critic verdicts

Also read SCORECARD.json for dimension context.

## Output Format

Write OPTIMIZATION_PLAN.md with:

1. **Executive Summary** — Bottom-2 dimensions, total findings, approved count
2. **Approved Findings** — Prioritized table of approved findings
3. **Downgraded Findings** — Lower-priority items for future consideration
4. **Rejected Findings** — What was rejected and why (transparency)
5. **Patch Manifest** (if --patch mode) — Files affected, net lines, expected delta
6. **Expected Impact** — Predicted composite score improvement
7. **Cleanup Safety Summary** — Count cleanup-classified findings, destructive
   findings, blocked destructive findings, authorization-required findings, and
   bounded non-claims; exclude blocked destructive findings from the patch
   manifest unless owner-boundary, keep-set, authorization, and evidence-threshold
   receipts are present.
8. **Metadata** — Timestamp, optimizer version, SCORECARD input

Summarize command evidence instead of copying raw stdout/stderr transcripts into
`OPTIMIZATION_PLAN.md`. Raw logs belong in `.jsonl`, stdout, or runtime receipt
artifacts; cite only the relevant command, outcome, and artifact path.

If repo-auditor inventory is absent or partial, summarize it as insufficient
cleanup evidence rather than authorization. Do not claim cleanup is safe to
apply; repo-optimizer recommends only and target repositories are not mutated.

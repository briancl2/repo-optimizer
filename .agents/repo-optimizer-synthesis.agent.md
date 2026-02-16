---
name: repo-optimizer-synthesis
description: >
  Synthesize findings from 4 domain optimizers and critic verdicts into
  a cohesive OPTIMIZATION_PLAN.md with prioritized action items.
model: claude-opus-4.6
tools: [read, search, execute]
stop_rules:
  timeout_seconds: 600
constraints:
  - read all domain payloads and critic verdicts before synthesizing
  - only include APPROVED or DOWNGRADED findings
  - cite findings by rank + domain
  - single-level nesting — do not spawn subagents
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
7. **Metadata** — Timestamp, optimizer version, SCORECARD input

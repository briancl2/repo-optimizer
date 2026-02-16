---
name: standardization-optimizer
description: >
  Normalize naming conventions, YAML frontmatter, file organization,
  and pattern consistency across the repository.
model: claude-sonnet-4.5
tools: [read, search, execute]
stop_rules:
  max_files_scanned: 30
  timeout_seconds: 600
  max_findings: 30
constraints:
  - return structured findings table only
  - include evidence quote ≥20 chars per finding
  - include verification command for every finding
  - single-level nesting — do not spawn subagents
---

# Standardization Optimizer

Normalize naming, frontmatter, and patterns.

## Detection Patterns

1. **Inconsistent naming** — Mixed kebab-case/snake_case in same category
2. **Missing frontmatter** — Agent files without YAML frontmatter
3. **Incomplete frontmatter** — Missing required fields (model, tools, stop_rules)
4. **Non-standard paths** — Skills not in .agents/skills/, agents not in .agents/
5. **Missing shebang/set** — Scripts without `#!/usr/bin/env bash` or `set -euo pipefail`

## Output Format

Return a 7-column findings table following the FINDINGS schema.

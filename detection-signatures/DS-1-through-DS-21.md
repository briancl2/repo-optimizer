# Detection Signatures — DS-1 through DS-21

> Reference document for the repo-auditor detection engine.
> Each signature identifies a specific maturity gap, stall risk, or operational health issue.
> Source: build-meta-analysis research/frameworks/MATURITY_MODEL.md + B5a validation.

---

## Phase 1→2 Transition

### DS-1: Monolithic Agent
- **Detects:** Agent file >200 lines with >3 phases/sections
- **Signal:** Skill extraction opportunity — large undifferentiated agents should be decomposed
- **Phase range:** Phase 1 → 2
- **Check:** `find .agents -name "*.agent.md" -exec wc -l {} + | awk '$1 > 200'`

---

## Phase 2→3 Transition

### DS-2: Missing Measurement
- **Detects:** >5 skills but 0 scoring tools
- **Signal:** Capability building without ability to measure quality
- **Phase range:** Phase 2 → 3
- **Check:** `skills=$(find . -name SKILL.md | wc -l); scoring=$(find scripts -name "score*" 2>/dev/null | wc -l); [[ $skills -gt 5 && $scoring -eq 0 ]]`

### DS-3: Delegation-Ready Workload
- **Detects:** Session action ratio >0.3 AND >100 tool calls AND 0 subagents
- **Signal:** Single-agent workload ripe for fleet delegation
- **Phase range:** Phase 2 → 3

### DS-4: Missing Hypothesis-Driven Dev
- **Detects:** >5 scoring runs but no HYPOTHESES.md or hypothesis tracking
- **Signal:** Measuring output without structured experimental design
- **Phase range:** Phase 2 → 3

### DS-10: Fragmented/Zombie Plans
- **Detects:** Plans in ≥3 directories OR >3 stalled plans (no activity 14+ days)
- **Signal:** Ad-hoc planning without structured skill-generated plans
- **Phase range:** Phase 2 → 3

---

## Phase 3→4 Transition

### DS-5: Missing Intelligence Mining
- **Detects:** Versioned output but no reference/intelligence directory
- **Signal:** Production output not feeding back into knowledge loop
- **Phase range:** Phase 3 → 4

### DS-7: Missing CI Quality Gates
- **Detects:** Build orchestrator exists but no CI pipeline
- **Signal:** Local automation without continuous integration
- **Phase range:** Phase 3 → 4
- **Check:** `test -d .github/workflows || test -f .gitlab-ci.yml`

### DS-9: Auditor Without Optimizer
- **Detects:** Audit reports exist (>5 files) but no optimization capabilities
- **Signal:** Has diagnostics but can't auto-remediate
- **Phase range:** Phase 3 → 4

### DS-11: Scoring Layer Gaps
- **Detects:** Scoring exists but missing cheapest-first layers
- **Signal:** Incomplete scoring pyramid (structural → heuristic → editorial → functional)
- **Phase range:** Phase 3 → 4

---

## Phase 4→5 / Governance

### DS-6: Duplicate Instruction Surfaces
- **Detects:** Both `copilot-instructions.md` AND `AGENTS.md` exist
- **Signal:** Fragmented governance — agents read conflicting instructions
- **Phase range:** Phase 4 → 5
- **Check:** `test -f .github/copilot-instructions.md && test -f AGENTS.md`

### DS-12: Cross-Platform Drift
- **Detects:** Multi-platform dirs + sync scripts + no CI enforcement
- **Signal:** Sync is manual, platforms will diverge
- **Phase range:** Phase 4+

---

## Stall Detection

### DS-8: Imported Framework
- **Detects:** >3 agents added in single commit, no domain-specific names
- **Signal:** Bulk-imported agent framework never customized (L52)
- **Phase range:** Phase 2 stall indicator

---

## Operational Health (DS-13 through DS-21)

### DS-13: No Self-Inventory
- **Detects:** ≥5 AI surfaces AND no inventory target/script
- **Signal:** Repo can't enumerate its own capabilities
- **Phase range:** Phase 2+
- **Check:** `surfaces=$(find . -name "*.agent.md" -o -name "SKILL.md" | wc -l); grep -q "inventory" Makefile 2>/dev/null`

### DS-14: No Quality Gate in CI
- **Detects:** ≥1 CI workflow AND no quality-gate language in workflows
- **Signal:** CI exists but doesn't enforce quality
- **Phase range:** Phase 3+

### DS-15: Low Automation Density
- **Detects:** Makefile exists AND ≥10 surfaces AND automation density <0.3
- **Signal:** Many capabilities but few automated entry points
- **Phase range:** Phase 3+

### DS-16: No Machine-Readable Scoring
- **Detects:** ≥1 scoring tool AND no JSON/YAML output
- **Signal:** Scoring exists but isn't machine-parseable for automation
- **Phase range:** Phase 3 → 4

### DS-17: Low Co-Evolution Ratio
- **Detects:** agents ≥3 AND co-evolution ratio (skills/agents) <0.5
- **Signal:** Agents accumulating without skill extraction — stall risk
- **Phase range:** Phase 2+
- **Check:** `agents=$(find . -name "*.agent.md" | wc -l); skills=$(find . -name SKILL.md | wc -l); ratio=$(echo "scale=2; $skills / $agents" | bc)`

### DS-18: Missing Code Review Gate
- **Detects:** No `reviewing-code-locally` skill AND no `make review` target
- **Signal:** No automated pre-commit code review capability (L102)
- **Phase range:** Phase 2+

### DS-19: No Session Log Management
- **Detects:** ≥1 agent AND ≥10 commits AND no session management tooling
- **Signal:** Active AI usage generating session logs with no archival/rotation
- **Phase range:** Phase 2+

### DS-20: Capability Drift
- **Detects:** ≥5 tools on disk AND drift >20% (tools not mentioned in docs)
- **Signal:** Documentation fallen out of sync with actual capabilities
- **Phase range:** Phase 3+

### DS-21: Automation Theater
- **Detects:** 7 signals for capabilities that exist but aren't exercised
- **Signals:**
  - S1: Hook scripts not installed
  - S2: Makefile targets never invoked
  - S3: Skills with zero session calls
  - S4: Protocol steps bypassed
  - S5: Agent files never dispatched
  - S6: Enforcement defaults to soft
  - S7: `--no-verify` in committed artifacts
- **Phase range:** Phase 3+
- **Dedicated script:** `scripts/detect-automation-theater.sh`

I have all inputs. Here is the synthesized plan:

---

# OPTIMIZATION_PLAN.md

**Target:** build-meta-analysis
**Run:** `work/20260428T221542Z/bma-optimizer-output`
**Mode:** report-only (no patches)

---

## 1. Executive Summary

The target repository scores **72/100 composite**, with two dimensions significantly below ceiling:

| Dimension | Score | Max | Gap |
|-----------|------:|----:|----:|
| D2 — Surface Health | 6 | 20 | −14 |
| D3 — Skill Maturity | 10 | 20 | −10 |
| D1 — Governance | 18 | 20 | −2 |
| D4 — Measurement | 19 | 20 | −1 |
| D5 — Self-Improvement | 19 | 20 | −1 |

**Bottom-2 dimensions:** D2 Surface Health, D3 Skill Maturity

Four domain optimizers produced **43 findings** total. The adversarial critic reviewed all 43 and rendered:

- **24 APPROVED** — actionable, evidence-verified
- **13 DOWNGRADED** — directionally valid but lower priority than claimed
- **6 REJECTED** — false evidence, insufficient evidence, or metric-chasing

---

## 2. Approved Findings (24)

### Priority Tier 1 — High Impact

| Rank | ID | Domain | Severity | Finding | Key Files | Estimated Impact |
|-----:|-----|--------|----------|---------|-----------|-----------------|
| 1 | EXT-005 | Extraction | HIGH | Session parsing logic duplicated across 9 scripts | `parse-session-log.py`, `analyze-phase-fingerprints.py`, `analyze-make-clock-time.py`, +6 others | Extract `scripts/lib/session_parser.py`; eliminates ~500 duplicated lines |
| 2 | C3 | Consolidation | MEDIUM | 3 orphaned `freeze-*.py` scripts (no callers in Makefile/AGENTS.md) | `freeze-external-critique-coverage.py` (612L), `freeze-external-critique-live-corpus.py` (296L), `freeze-simplification-confirmation-cases.py` (105L) | Remove ~1,013 lines of dead code |
| 3 | C4 | Consolidation | MEDIUM | 3 orphaned `validate-foundational-*.py` scripts | `validate-foundational-sync.py`, `validate-foundational-governance-replay.py`, `validate-foundational-reentry-gate.py` | Remove ~400 lines of dead code |
| 4 | STD-001–005 | Standardization | MEDIUM | 5 scripts use `#!/bin/bash` instead of `#!/usr/bin/env bash` | `audit-targets.sh`, `extract-repo-dna.sh`, `pre-commit-hook.sh`, `code-review-sweep.sh`, `stall-risk-score.sh` | Mechanical 1-line fix per file |
| 5 | D2 | Decomposition | HIGH | Largest monolith: 1,913-line token cost analysis bundle builder | `build-newsletter-token-cost-analysis.py` | Split into ≤4 focused modules |

### Priority Tier 2 — Medium Impact (Decomposition Targets)

| Rank | ID | Domain | Severity | Finding | File | Lines |
|-----:|-----|--------|----------|---------|------|------:|
| 6 | D1 | Decomposition | HIGH | Monolithic bundle builder — 11+ phases | `build-principle-realignment-bundle.py` | 1,611 |
| 7 | D3 | Decomposition | HIGH | Clock-time analyzer — mixed concerns | `analyze-make-clock-time.py` | 1,639 |
| 8 | D4 | Decomposition | HIGH | GPT-5.5 regression analyzer | `analyze-gpt55-runtime-regression.py` | 1,345 |
| 9 | D5 | Decomposition | HIGH | Token usage analyzer — multi-concern | `analyze-token-usage.py` | 1,432 |
| 10 | D6 | Decomposition | HIGH | Phase fingerprint analyzer | `analyze-phase-fingerprints.py` | 1,093 |
| 11 | D7 | Decomposition | HIGH | Closeout disposition validator | `closeout-disposition.py` | 1,062 |
| 12 | D8 | Decomposition | MEDIUM | Session grader — 4-dimension scoring | `score-session.sh` | 1,003 |
| 13 | D9 | Decomposition | MEDIUM | Handoff-closeout sync validator | `validate-handoff-closeout-sync.py` | 927 |
| 14 | D10 | Decomposition | MEDIUM | Stage 17 retro bundle builder | `build-stage17-post-closure-operating-model-retro-bundle.py` | 835 |
| 15 | D11 | Decomposition | MEDIUM | Closeout reconciliation handler | `closeout-reconciliation.py` | 761 |
| 16 | D12 | Decomposition | MEDIUM | Fleet output scorer | `score-fleet-output.sh` | 743 |
| 17 | D13 | Decomposition | MEDIUM | External critique mismatch reconciler | `reconcile-external-critique-mismatches.py` | 657 |
| 18 | D14 | Decomposition | MEDIUM | External critique coverage freezer (also orphan per C3) | `freeze-external-critique-coverage.py` | 612 |

### Priority Tier 3 — Consolidation & Extraction

| Rank | ID | Domain | Severity | Finding |
|-----:|-----|--------|----------|---------|
| 19 | C2 | Consolidation | MEDIUM | `ground-truth-t1.sh` / `ground-truth-t5.sh` share 80%+ structure — extract shared test harness |
| 20 | C5 | Consolidation | MEDIUM | Token/cost analysis scripts have overlapping functions |
| 21 | C6 | Consolidation | MEDIUM | `closeout-disposition.py` + `closeout-reconciliation.py` share validation patterns |
| 22 | C7 | Consolidation | LOW | Multiple `score*.sh` scripts share rubric/scoring logic |
| 23 | C8 | Consolidation | LOW | Identical `.shellcheckrc` in root and `targets/T1-build-meta-analysis/` |
| 24 | C10 | Consolidation | LOW | Two large bundle builders share report-generation helpers |

### Skill Extraction Candidates

| Rank | ID | Finding | Script | Rationale |
|-----:|-----|---------|--------|-----------|
| — | EXT-003 | `extract-repo-dna.sh` → skill | 236L, deterministic, zero-LLM-token | Reusable repo maturity fingerprint |
| — | EXT-004 | `compare-scorecards.sh` → skill | 276L, deterministic regression oracle | Repo-agnostic scorecard comparison |

---

## 3. Downgraded Findings (13)

These are directionally valid but lower-priority than originally claimed.

| ID | Domain | Original → New | Finding | Reason for Downgrade |
|----|--------|----------------|---------|---------------------|
| D15 | Decomposition | MEDIUM → LOW | `speckit.checklist.agent.md` (294L) | Declarative agent markdown; decomposition provides minimal benefit |
| D16 | Decomposition | MEDIUM → LOW | `speckit.specify.agent.md` (258L) | Same rationale — agent definitions are not executable code |
| D17 | Decomposition | MEDIUM → LOW | `extract-repo-dna.sh` (236L) | 236 lines is within normal range for a self-contained script |
| D18 | Decomposition | LOW → INFO | `spec-orchestrator.sh` (210L) | 210 lines for a 9-stage orchestrator is compact |
| C9 | Consolidation | LOW → INFO | Archived scripts count | Evidence inflated (claims 31 files, actual is 12) |
| EXT-006 | Extraction | MEDIUM → LOW | Work type canonicalization | Limited reuse evidence outside scoring context |
| EXT-009 | Extraction | MEDIUM → LOW | JSON extraction helpers | ≤20 lines of utility; extraction adds indirection without significant benefit |
| EXT-010 | Extraction | MEDIUM → LOW | Work contract management skill | Makefile already provides the interface; speculative |
| STD-006–014 | Standardization | MEDIUM → LOW | 9 speckit agent frontmatter findings | Agent runtime does not read these fields; cosmetic delta-hack |

---

## 4. Rejected Findings (6)

| ID | Domain | Finding | Rejection Reason |
|----|--------|---------|-----------------|
| C1 | Consolidation | "Missing" session-log-manager scripts | **False evidence** — all three scripts exist at the referenced paths; Makefile targets are valid |
| EXT-001 | Extraction | Tool name normalizer duplication (ACTION_NAMES) | **Insufficient evidence** — constants exist in only 1 file, not 4+ as claimed |
| EXT-002 | Extraction | Model name regex duplication (COPILOT_MODEL_RE) | **Insufficient evidence** — patterns found in only 1 file, not "multiple" |
| EXT-007 | Extraction | `extract-patterns-core.py` → skill (18,995L claimed) | **Fabricated evidence** — actual file is 529 lines (36× inflation) |
| EXT-008 | Extraction | Strategy classification duplication | **Insufficient evidence** — labels found in only 1 file, not 3 as claimed |
| STD-015 | Standardization | Minimal prompt frontmatter | **Metric-chasing** — finding acknowledges the pattern is already consistent |

---

## 5. Patch Manifest

**Patch mode: OFF** (`patch_mode: false` in SCORECARD.json).

No patches generated. The following table shows what would be prioritized if `--patch` were enabled:

| Priority | Patch | Files | Est. Net Lines | Risk |
|---------:|-------|------:|---------------:|------|
| 1 | Shebang normalization (STD-001–005) | 5 | 0 (in-place) | Zero |
| 2 | Remove orphaned freeze-*.py scripts (C3) | 3 | −1,013 | Zero (no callers) |
| 3 | Remove orphaned validate-foundational-*.py (C4) | 3 | −400 | Zero (no callers) |
| 4 | Deduplicate `.shellcheckrc` (C8) | 1 | −4 | Zero |
| 5 | Extract `session_parser.py` stub (EXT-005) | 1 new + 1 modified | +80 | Low |

---

## 6. Expected Impact

| Dimension | Current | Predicted | Delta | Rationale |
|-----------|--------:|----------:|------:|-----------|
| D2 — Surface Health | 6 | 10–12 | +4–6 | Orphan removal (C3, C4), shebang normalization (STD-001–005), `.shellcheckrc` dedup (C8) directly address surface health scoring |
| D3 — Skill Maturity | 10 | 12–14 | +2–4 | Skill extraction candidates (EXT-003, EXT-004) and session parser deduplication (EXT-005) improve skill maturity |
| **Composite** | **72** | **78–82** | **+6–10** | Conservative estimate; full decomposition work (D1–D14) would push higher |

---

## 7. Metadata

| Field | Value |
|-------|-------|
| Timestamp | 2026-04-28T22:15:42Z |
| Run ID | `20260428T221542Z` |
| Target | `build-meta-analysis` |
| SCORECARD input | `work/20260428T221542Z/bma-optimizer-output/pre-flight.json` |
| Composite score | 72/100 |
| Bottom-2 dimensions | D2_surface_health (6/20), D3_skill_maturity (10/20) |
| Patch mode | OFF |
| Budget tier | minimal |
| Discovery scope | 2,946 eligible / 144,885 total files (2.0% coverage) |
| Domain findings | 43 (Decomp: 18, Consol: 10, Extract: 10, Standard: 15) |
| Critic verdicts | 24 approved · 13 downgraded · 6 rejected |
| Critic rejection rate | 14% (6/43) — meets ≥1 mandatory rejection |
| Payloads | `work/20260428T221542Z/bma-optimizer-output/payloads/` |
| Critic verdicts | `work/20260428T221542Z/bma-optimizer-output/critic-verdicts.md` |

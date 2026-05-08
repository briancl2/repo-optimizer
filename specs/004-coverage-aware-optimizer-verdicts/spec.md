# Feature Specification: Coverage-Aware Optimizer Verdicts

**Feature Branch**: `bma-phase2-coverage-verdicts`
**Created**: 2026-05-08
**Status**: Draft
**Input**: User description: "Phase 2 PR 2A additive coverage-aware optimizer verdicts (P3)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mark Partial Discovery As Partial (Priority: P1)

As a downstream fleet operator, I need optimizer outputs to say when domain
coverage is incomplete, so a fresh run with only some discovery domains cannot be
reported as an unconditional optimization pass.

**Why this priority**: Phase 2 PR 2A is specifically the P3 guardrail for
coverage-aware optimizer verdicts.

**Independent Test**: Run the optimizer against a synthetic target with fake
Copilot output where only two of the four discovery domains produce payloads and
inspect `OPTIMIZATION_SCORECARD.json`, `RUNTIME_RECEIPTS.json`, and the plan.

**Acceptance Scenarios**:

1. **Given** two successful and two missing/failed discovery domains, **When**
   the optimizer completes, **Then** the scorecard coverage verdict is `partial`
   or `pass_with_coverage_gap`, not an unconditional pass.
2. **Given** all four discovery domains succeed, **When** the optimizer completes,
   **Then** the coverage verdict is `complete`.
3. **Given** zero discovery domains succeed, **When** the optimizer completes,
   **Then** the coverage verdict is `blocked`.

---

### User Story 2 - Keep Human And JSON Counts Consistent (Priority: P1)

As a reviewer, I need the human optimization plan and machine scorecard to agree
on finding counts, or to fail tests when they diverge, so downstream reporting
does not mix contradictory evidence.

**Why this priority**: The roadmap explicitly calls out count agreement between
human plan narrative and JSON scorecard finding counts.

**Independent Test**: Use a generated plan/scorecard fixture and assert the
coverage metadata's plan-declared count matches the JSON count.

**Acceptance Scenarios**:

1. **Given** a plan declaring approved/rejected/downgraded finding counts, **When**
   `OPTIMIZATION_SCORECARD.json` is generated, **Then** it records count-agreement
   status and the focused test fails on mismatch.

---

### User Story 3 - Constrain Recommendations When Coverage Is Missing (Priority: P2)

As an optimizer consumer, I need missing domains to weaken recommendation
strength and add non-claims, so partial discovery does not imply full target
knowledge.

**Why this priority**: Missing domains are expected in live runs and must bound
claims without requiring Phase 3 target-policy work.

**Independent Test**: Inspect outputs from a 2/4-domain run for missing-domain
lists, bounded non-claims, and a recommendation-strength value below `strong`.

**Acceptance Scenarios**:

1. **Given** any missing discovery domain, **When** outputs are generated, **Then**
   machine artifacts list missing domains, set recommendation strength to a
   constrained value, and include non-claims that complete discovery was not
   observed.

### Edge Cases

- Pre-flight-only deterministic runs keep `coverage_verdict=partial` because
  discovery was intentionally skipped.
- Admission-blocked runs keep `coverage_verdict=blocked`.
- Synthesis-authored plans are not rewritten except for bounded coverage metadata
  surfaces; generated stubs include the coverage note directly.
- Existing ROI and receipt scoring fields remain unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `OPTIMIZATION_SCORECARD.json` MUST include additive coverage verdict
  metadata without removing or renaming existing scoring fields.
- **FR-002**: Valid coverage verdict values MUST include `complete`, `partial`,
  `blocked`, and `pass_with_coverage_gap`.
- **FR-003**: A fresh run with only two of four discovery domains MUST NOT emit a
  coverage verdict equivalent to unconditional pass.
- **FR-004**: Missing discovery domains MUST constrain recommendation strength and
  emit bounded non-claims.
- **FR-005**: Runtime receipts MUST carry enough coverage metadata for downstream
  consumers to explain the verdict.
- **FR-006**: Tests MUST fail if plan-declared finding counts and JSON scorecard
  finding counts diverge on the covered surface.
- **FR-007**: Documentation MUST describe coverage verdict values and non-claims.
- **FR-008**: This PR MUST NOT implement Phase 3 target-policy/P4, P5 cleanup, P7
  denominator logic, repo-agent-core shared schemas, or BMA shared-surface edits.

### Key Entities

- **Discovery coverage**: Counts and names of expected, successful, and missing
  optimizer discovery domains.
- **Coverage verdict**: Additive machine-readable verdict about whether discovery
  coverage supports a full-strength optimization recommendation.
- **Count agreement**: Metadata comparing plan-declared finding counts with JSON
  scorecard counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Focused test proves a 2/4-domain run emits `partial` or
  `pass_with_coverage_gap` and constrains recommendation strength.
- **SC-002**: Focused test proves count-agreement metadata matches the human plan
  narrative and JSON scorecard counts.
- **SC-003**: `make test` and `make check` pass or any unrelated baseline blocker
  is captured exactly.
- **SC-004**: Final report states non-claims and whether the output helps BMA P7
  denominator study without mutating BMA.

# Feature Specification: Partial Audit Admission

**Feature Branch**: `003-partial-audit-admission`
**Created**: 2026-05-07
**Status**: Draft
**Input**: User description: "Phase 1 P1 partial audit admission"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admit Only Completed Audits (Priority: P1)

As an optimizer caller, I need normal optimizer runs to proceed only when the
auditor produced a completed receipt plus the required scorecard and report, so
partial audit diagnostics cannot be mistaken for optimizer readiness.

**Why this priority**: This is the Phase 1 P1 safety gate and must land before
any downstream optimizer run can claim readiness from repo-auditor output.

**Independent Test**: Run `repo-optimizer.sh` in pre-flight-only mode against
synthetic completed, partial, failed, missing-receipt, and missing-report audit
directories and inspect emitted receipts.

**Acceptance Scenarios**:

1. **Given** a completed audit receipt with `SCORECARD.json` and
   `AUDIT_REPORT.md`, **When** the optimizer runs normally, **Then** pre-flight
   proceeds and records `normal_readiness_claim=true`.
2. **Given** a partial or failed audit receipt, **When** the optimizer runs
   normally, **Then** it exits blocked and writes blocked receipt artifacts
   without a normal readiness claim.
3. **Given** a completed receipt whose existing scorecard receipt metadata says
   the scan was limited or came from a clean-head snapshot, **When** the
   optimizer runs normally, **Then** it exits blocked, records
   `audit_evidence_class=scan_limited` or `snapshot_limited`, and emits no
   normal readiness claim.
4. **Given** legacy audit output with no completed receipt or a completed receipt
   missing `AUDIT_REPORT.md`, **When** the optimizer runs normally, **Then** it
   exits blocked and records the exact blocker.

---

### User Story 2 - Preserve One Research Calibration Path (Priority: P1)

As a fleet calibrator, I need one explicit partial-audit calibration mode that
keeps the known partial diagnostic path reproducible without granting normal
readiness.

**Why this priority**: The roadmap requires preserving calibration evidence
while preventing accidental production admission.

**Independent Test**: Run a partial audit fixture with
`REPO_OPTIMIZER_RESEARCH_MODE=partial-audit-calibration` under both a
research-labeled output path and a normal output path.

**Acceptance Scenarios**:

1. **Given** a partial audit receipt and
   `REPO_OPTIMIZER_RESEARCH_MODE=partial-audit-calibration`, **When** the output
   path includes `research-mode/partial-audit-calibration/`, **Then** the run
   proceeds and records `research_mode=partial-audit-calibration` in pre-flight,
   the optimization scorecard, and operation eval.
2. **Given** the same research mode, **When** the output path is not
   research-labeled, **Then** the optimizer exits blocked before normal
   discovery.

### Edge Cases

- Missing `SCORECARD.json` blocks before optimizer discovery.
- Unsupported `REPO_OPTIMIZER_RESEARCH_MODE` values block instead of silently
  bypassing admission.
- Research-mode runs never set `normal_readiness_claim=true`.
- Research-mode runs still require an audit receipt or scorecard audit status so
  the calibration path cannot admit receipt-less legacy output.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Normal optimizer runs MUST require a completed audit receipt.
- **FR-002**: Normal optimizer runs MUST also require `SCORECARD.json` and
  `AUDIT_REPORT.md`.
- **FR-003**: Partial, failed, missing-receipt, and missing-report audit inputs
  MUST produce blocked receipts and no normal readiness claim.
- **FR-004**: The only bypass MUST be
  `REPO_OPTIMIZER_RESEARCH_MODE=partial-audit-calibration`.
- **FR-005**: Research-mode bypass MUST fail unless the output path includes
  `research-mode/partial-audit-calibration/`.
- **FR-006**: Research-mode bypass MUST require an incomplete audit receipt or
  scorecard audit status.
- **FR-007**: Research-mode runs MUST record
  `research_mode=partial-audit-calibration` in `pre-flight.json`,
  `OPTIMIZATION_SCORECARD.json`, and `OPERATION_EVAL.json`.
- **FR-008**: Documentation MUST describe completed, partial, failed, missing
  receipt/report admission behavior and the research-mode path.
- **FR-009**: This PR MUST NOT implement coverage verdicts, target policy
  adapters, repo-auditor changes, or BMA shared-surface edits.
- **FR-010**: Completed receipts with scan-limited or snapshot-limited evidence
  metadata MUST be blocked from normal optimizer readiness and classified
  explicitly in `audit-admission-receipt.json`.

### Key Entities

- **Audit admission receipt**: Optimizer-local receipt that records audit input
  shape, admission status, normal readiness claim, research mode, and blocker.
- **Research calibration mode**: The single explicit env-mode that admits partial
  audit inputs only under a research-labeled output path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Focused audit-admission tests cover completed, partial, failed,
  scan-limited, snapshot-limited, missing receipt, missing report, valid
  research mode, and invalid research output path.
- **SC-002**: `make check` and relevant tests pass before commit.
- **SC-003**: PR/handoff states the merge-order dependency that strict optimizer
  admission must not merge before repo-auditor emits the receipt shape unless
  both PRs merge in one coordinated window.

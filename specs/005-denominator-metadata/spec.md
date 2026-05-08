# Feature Specification: Denominator Metadata

**Feature Branch**: `bma-phase3a-denominator-metadata`
**Created**: 2026-05-08
**Status**: Draft
**Input**: BMA Phase 3A P7 lane request to make repo-optimizer pre-flight/discovery-scope denominator semantics explicit without changing count, coverage, or verdict behavior.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Explain optimizer budgeting denominator (Priority: P1)

As a BMA coordinator consuming repo-optimizer artifacts, I need pre-flight output to state what the optimizer budgeting denominator counts so Phase 3A/P7 reports can distinguish counted files from excluded path classes.

**Why this priority**: The metadata is needed for downstream interpretation while preserving current optimizer behavior.

**Independent Test**: Run a deterministic pre-flight-only optimizer invocation against a synthetic target and inspect `pre-flight.json`.

**Acceptance Scenarios**:

1. **Given** a target repo with ordinary files plus `.git` and `node_modules` paths, **When** pre-flight runs, **Then** `discovery_scope` includes machine-readable denominator semantics naming the counted denominator.
2. **Given** the same target repo, **When** pre-flight runs, **Then** `discovery_scope` includes machine-readable excluded path classes listing `.git` and `node_modules`.

---

### User Story 2 - Preserve existing counts and verdicts (Priority: P1)

As an existing SCORECARD or coverage consumer, I need the added metadata to be additive so current totals, eligibility counts, coverage percentage, and verdict behavior do not change.

**Why this priority**: This lane must not invalidate existing optimizer scorecard consumers or historical coverage comparisons.

**Independent Test**: Compare pre-flight count fields and coverage verdict tests before and after metadata emission.

**Acceptance Scenarios**:

1. **Given** a deterministic pre-flight fixture, **When** metadata is emitted, **Then** `total_files`, `eligible_files`, and `coverage_pct` remain the expected legacy values.
2. **Given** existing coverage-verdict tests, **When** the suite runs, **Then** coverage verdict outputs remain unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `pre-flight.json.discovery_scope` MUST include explicit denominator semantics for the optimizer budgeting denominator.
- **FR-002**: `pre-flight.json.discovery_scope` MUST include machine-readable excluded path-class metadata for excluded paths.
- **FR-003**: The excluded path classes MUST include `.git` and `node_modules` unless implementation evidence proves additional existing exclusions in the same denominator.
- **FR-004**: The change MUST NOT alter `file_count`, `discovery_scope.total_files`, `discovery_scope.eligible_files`, `discovery_scope.coverage_pct`, budget tier selection, coverage verdicts, or existing SCORECARD behavior.
- **FR-005**: Deterministic tests MUST avoid LLM-backed optimizer phases by using direct pre-flight or `OPTIMIZER_PREFLIGHT_ONLY=true`.

### Key Entities

- **Discovery Scope Metadata**: The `discovery_scope` object in `pre-flight.json` describing budget tier, eligible count, denominator count, coverage percentage, scope description, denominator semantics, and excluded path classes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A pre-flight-only test asserts the new metadata fields exist and carry `.git` and `node_modules` exclusions.
- **SC-002**: The same test asserts existing count and coverage fields retain their expected values.
- **SC-003**: `make test` and `make check` pass with the metadata change.

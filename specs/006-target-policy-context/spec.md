# Feature Specification: Target Policy Context Pointers

**Feature Branch**: `bma-widened-p4-policy-context`
**Created**: 2026-05-08
**Status**: Draft
**Input**: BMA work package `work/20260508T153929Z` admitted the repo-optimizer P4 target-policy context pointer lane.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Surface target-local policy pointers (Priority: P1)

As an optimizer consumer, I need deterministic runtime context to list obvious
target-local policy files so generic standardization recommendations can be
checked against target-owned policy authority before they are treated as safe.

**Why this priority**: BMA discovery found optimizer standardization can produce
generic recommendations that conflict with target model-routing policy when the
policy files are not surfaced in runtime-safe context.

**Independent Test**: Run a pre-flight-only optimizer invocation against a
synthetic target containing `system/policy/**`, `.github/**policy**`,
`docs/**policy**`, and root `*policy*.{json,yaml,yml,md}` files.

**Acceptance Scenarios**:

1. **Given** a target with obvious policy files, **When** pre-flight runs,
   **Then** `runtime-safe-target-context.md` includes a compact `Target Policy Pointers` section.
2. **Given** the same target, **When** pre-flight runs, **Then**
   `pre-flight.json.target_policy_context` includes `discovery_mode=pointer_only`,
   a count, a file list, parse status, evidence keys, and the non-claim that
   listed files are not fully interpreted.

---

### User Story 2 - Preserve no-policy behavior (Priority: P1)

As an existing optimizer caller, I need targets without policy files to retain
their current pre-flight behavior except for additive zero-count metadata.

**Independent Test**: Run a pre-flight-only optimizer invocation against a
synthetic target with no policy files.

**Acceptance Scenarios**:

1. **Given** a target with no matching policy files, **When** pre-flight runs,
   **Then** `target_policy_context.policy_files_count` is `0` and the runtime
   context renders a `none` row.
2. **Given** existing pre-flight tier tests, **When** the suite runs, **Then**
   budget tier, file count, eligible file count, and coverage behavior remain unchanged.

---

### User Story 3 - Policy-aware standardization and critic handling (Priority: P2)

As an optimizer reviewer, I need standardization and critic prompts to downgrade
or explain policy-conflicting findings unless stronger target-owner authority is cited.

**Independent Test**: Inspect prompt text for required policy interaction
categories.

**Acceptance Scenarios**:

1. **Given** target policy pointers are present, **When** standardization emits a
   possibly conflicting recommendation, **Then** it uses one of the target policy
   interaction categories.
2. **Given** the critic reviews a possibly policy-conflicting finding, **When**
   no stronger target authority is cited, **Then** the finding is downgraded or rejected.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Runtime-safe target context MUST include a compact `Target Policy Pointers` section.
- **FR-002**: Policy discovery MUST be pointer-only and limited to obvious target-local paths: `system/policy/**`, `.github/**policy**`, `docs/**policy**`, and root `*policy*.{json,yaml,yml,md}`.
- **FR-003**: Pre-flight metadata MUST include `target_policy_context.discovery_mode`, `policy_files_count`, `policy_files`, and a non-claim that listed files are optimizer context and not fully interpreted.
- **FR-004**: Each listed policy file SHOULD include path, policy family, role, type, description/title when cheaply available, evidence keys, and parse status.
- **FR-005**: Standardization and critic prompts MUST include policy interaction categories: `target_policy_explained`, `target_policy_conflict_downgraded`, `target_policy_absent_generic_allowed`, `stronger_target_authority_cited`, `policy_pointer_ambiguous`, and `unclassified_requires_amendment`.
- **FR-006**: The change MUST NOT implement cleanup-ledger fields, mutate target repositories, or perform broad policy ingestion.
- **FR-007**: Deterministic tests MUST avoid LLM-backed optimizer phases by using `OPTIMIZER_PREFLIGHT_ONLY=true`.

### Key Entities

- **Target Policy Context**: Pointer-only metadata describing obvious target-local policy files for optimizer context.
- **Policy Pointer**: A file path plus compact role/type/summary metadata; not a full policy interpretation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Policy-present fixture asserts `runtime-safe-target-context.md` and `pre-flight.json.target_policy_context` contain the expected pointers.
- **SC-002**: No-policy fixture asserts zero-count metadata and preserves existing pre-flight behavior.
- **SC-003**: Prompt tests assert all required policy interaction categories are present.
- **SC-004**: Targeted tests, `make test`, and `make check` pass.

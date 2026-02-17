# Feature Specification: Budget Tiering

> **ID:** 001-budget-tiering
> **Date:** 2026-02-17
> **Author:** build-meta-analysis pipeline (spec 013 fleet dispatch)
> **Status:** Draft
> **Constitution check:** ✅ §1 (Auditor-First — budget tiers depend on SCORECARD input), §2 (Critic-Mandatory — tier selection must be reviewable), §5 (Bounded Scope — tiers enforce file count limits), §6 (Budget Tiering — formalizes the existing partial implementation)

## Problem Statement

repo-optimizer has a budget tiering system partially implemented in `pre-flight.sh` that classifies target repos into three tiers based on file count: full (<200 files), focused (200-1000 files), and minimal (>1000 files). Each tier controls the discovery scope to prevent unbounded optimization runs on large repos. However, this tiering logic is undocumented at the spec level — there is no formal specification of the tier boundaries, the discovery scope per tier, or the expected behavior when a repo falls on a tier boundary. The constitution (§5, §6) mandates bounded scope and budget tiering, but without a spec, the implementation is the only source of truth.

This creates fragility: changes to tier boundaries or discovery scope have no contract to validate against, and downstream consumers (the outer loop's continuous pipeline) cannot predict optimizer behavior without reading source code.

## Goal

1. **Formalize the budget tiering contract** by specifying tier boundaries, discovery scope per tier, and pre-flight.json output fields
2. **Define edge case behavior** for repos exactly at tier boundaries (200 files, 1000 files)
3. **Ensure pre-flight.json records the selected tier** so downstream consumers can verify and log which tier was applied

## Non-Goals

- Changing the existing tier boundaries (this spec documents and tests them, not modifies them)
- Adding new tiers beyond the current three (full, focused, minimal)
- Modifying the optimizer pipeline beyond pre-flight (discovery, critic, and patch phases are out of scope)
- Performance optimization of the pre-flight scan itself

## Hypotheses

| ID | Hypothesis | Test Method | PASS Criterion |
|---|---|---|---|
| H-1 | If budget tiers are formally specified, then pre-flight.sh behavior can be validated against a contract instead of requiring source code inspection | Run pre-flight.sh against repos of different sizes and verify pre-flight.json output matches the spec's tier definitions | pre-flight.json `tier` field matches expected tier for 3 test repos (one per tier) |
| H-2 | If tier boundaries are documented with edge case behavior, then repos at exactly 200 or 1000 files produce predictable, documented behavior | Run pre-flight.sh against a repo with exactly 200 files and verify which tier is selected | Tier assignment matches the spec's documented boundary behavior |

## User Stories

### User Story 1 - Predictable Optimizer Scope (Priority: P1)

As a fleet pipeline operator running the continuous loop, I want the optimizer's discovery scope to be predictable based on target repo size, so that I can estimate run time and resource usage before starting an optimization cycle.

**Why this priority**: The continuous loop dispatches optimizer runs automatically. Without predictable scoping, large repos can cause timeout failures that halt the pipeline.

**Independent Test**: Run `pre-flight.sh` against repos of 3 different sizes and verify `pre-flight.json` contains the correct `tier` and `discovery_scope` fields matching the spec.

**Acceptance Scenarios**:

1. **Given** a target repo with fewer than 200 files, **When** `pre-flight.sh` runs, **Then** `pre-flight.json` contains `"tier": "full"` and all files are eligible for discovery.
2. **Given** a target repo with 200 to 1000 files, **When** `pre-flight.sh` runs, **Then** `pre-flight.json` contains `"tier": "focused"` and only AI surfaces and governance files are eligible.
3. **Given** a target repo with more than 1000 files, **When** `pre-flight.sh` runs, **Then** `pre-flight.json` contains `"tier": "minimal"` and only scored-dimension files are eligible.

---

### User Story 2 - Tier Transparency in Output (Priority: P2)

As a fleet maintainer reviewing optimizer output, I want `pre-flight.json` to clearly record which tier was selected and why, so that I can diagnose unexpected discovery scope without reading pre-flight.sh source code.

**Why this priority**: Debugging optimizer runs currently requires reading source code to understand why certain files were or weren't discovered.

**Independent Test**: Inspect `pre-flight.json` for `tier`, `file_count`, and `discovery_scope` fields after a run.

**Acceptance Scenarios**:

1. **Given** any target repo, **When** `pre-flight.sh` completes, **Then** `pre-flight.json` contains `tier`, `file_count`, and `discovery_scope` fields with non-empty values.

## Requirements

- **FR-001**: `pre-flight.sh` MUST classify repos into exactly one of three tiers: `full` (<200 files), `focused` (200-1000 files), or `minimal` (>1000 files).
- **FR-002**: `pre-flight.json` MUST include `tier`, `file_count`, and `discovery_scope` fields documenting the tier selection.
- **FR-003**: Tier boundaries MUST be inclusive on the lower bound: 200 files = `focused`, 1000 files = `minimal`.
- **FR-004**: Discovery scope per tier MUST be documented: `full` = all files, `focused` = AI surfaces + governance, `minimal` = scored-dimension files only.

## Success Criteria

- **SC-001**: `pre-flight.json` output from repos of each tier size contains the correct `tier` value
- **SC-002**: Edge case behavior at 200 and 1000 files is documented and matches actual pre-flight.sh behavior
- **SC-003**: Downstream consumers (continuous loop) can determine discovery scope from `pre-flight.json` without reading source code

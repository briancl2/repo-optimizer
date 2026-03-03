# Fix capability drift by documenting undocumented tools

> **ID:** 002-fix-capability-drift-by-documenting-undo
> **Date:** 2026-03-03
> **Source:** Fleet advisor (claude-opus-4.6) from DS-20 finding
> **Target:** repo-optimizer
> **Layer:** system

## Problem Statement

DS-20 capability drift at 34% (threshold 20%). 13 undocumented tools: 8 spec-kit agents (.github/agents/speckit.*.agent.md) and 5 .specify/scripts/bash/ helpers. All are spec-kit infrastructure added by spec 054 (self-management bootstrap).

**Evidence:**
- DS-20 capability drift at 34% (threshold 20%). 13 undocumented tools: 8 spec-kit agents (.github/agents/speckit.*.agent.md) and 5 .specify/scripts/bash/ helpers. All are spec-kit infrastructure added by spec 054 (self-management bootstrap).

## Goal

1. Resolve DS-20 finding: Fix capability drift by documenting undocumented tools
2. Verify fix with acceptance criteria
3. No regressions (make check passes)

## Acceptance Criteria

1. DS-20 no longer fires on target repo
2. make check passes
3. No regressions in SCORECARD composite

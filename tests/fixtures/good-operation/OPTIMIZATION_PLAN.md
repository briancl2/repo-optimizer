# Optimization Plan

## Summary

Target: repo-auditor
Composite: 60/100
Bottom dimensions: D2 (8/20), D3 (10/20)

## Approved Findings

### Finding 1: Agent Surface Consolidation (APPROVED)
- File: `.agents/repo-auditor.agent.md`
- Issue: Agent definitions scattered across `.github/agents/` and `.agents/`
- Fix: Consolidate all agent files to `.agents/` canonical path
- Expected impact: D1 +2, D2 +1

### Finding 2: Missing CI Pipeline (APPROVED)
- File: `.github/workflows/ci.yml` (create)
- Issue: No CI/CD pipeline for automated checks
- Fix: Add GitHub Actions workflow running make check
- Expected impact: D4 +1

### Finding 3: Skill Density Improvement (APPROVED)
- File: `.agents/skills/detection-signatures/SKILL.md` (create)
- Issue: Detection signature management not formalized as a skill
- Fix: Extract detection signature runner into proper skill definition
- Expected impact: D3 +2

## Patches

Generated 3 patches targeting:
- `scripts/repo-auditor.sh` - Add detection signature runner
- `.github/workflows/ci.yml` - Bootstrap CI
- `AGENTS.md` - Update skill count from 2 to 4

## Projected Delta

Pre: 60/100 -> Post: 65/100 (estimated +5)
D1: 12->14, D2: 8->9, D3: 10->12, D4: 15->16, D5: 15->15

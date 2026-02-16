---
name: bundle-integrity
version: 1.0.0
description: >
  Validate artifact bundle completeness and integrity.
  Checks manifest, SHA256 hashes, required files, and schema compliance.
author: briancl2
tags: [optimizer, validation, integrity, bundle]
---

# Bundle Integrity Skill

## Purpose

Validate that optimizer output bundles contain all required artifacts
with correct structure and content integrity. Used after every optimization
run to ensure no artifacts are missing or corrupted.

## When to Use

- After optimizer generates PATCH_PACK/
- Before committing optimization results
- In CI to validate optimizer output

## Scripts

| Script | Purpose |
|---|---|
| `scripts/validate-bundle.sh` | Check bundle completeness + SHA256 integrity |

## Usage

```bash
bash .agents/skills/bundle-integrity/scripts/validate-bundle.sh <output_dir>
```

## Required Bundle Contents

| File | Required? | Description |
|---|---|---|
| OPTIMIZATION_PLAN.md | YES | Human-readable optimization report |
| OPTIMIZATION_SCORECARD.json | YES | Machine-readable results |
| PATCH_PACK/*.patch | Only if --patch | Unified diff patches |
| manifest.json | YES | Bundle manifest with file list + hashes |

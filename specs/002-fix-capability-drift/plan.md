# Implementation Plan: Fix capability drift by documenting undocumented tools

**Spec:** 002-fix-capability-drift-by-documenting-undo | **Date:** 2026-03-03 | **Layer:** system

## Summary

Fix DS-20 (Fix capability drift by documenting undocumented tools) by following the standard spec-kit approach for fix-broken issues in the system layer.

## Approach

1. Run capability drift detection to identify undocumented tools
2. Categorize undocumented items: document, exclude, or archive
3. Update AGENTS.md with missing tool references
4. Verify drift <=20%

## Verification

```bash
make check
```

```bash
# Re-run DS detection to verify fix
```


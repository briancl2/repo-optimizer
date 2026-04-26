# .gitignore Analysis

## Contents

```
# Workspace intermediates (tracked for reproducibility)
!workspace/.gitkeep

# Benchmark data (large, not tracked)
benchmark/
# CI test fixtures (small subset of benchmark data, committed)
!tests/fixtures/benchmark/

# OS files
.DS_Store

# Python artifacts
__pycache__/
*.py[cod]

# Verification report (generated)
MIGRATION_VERIFICATION_REPORT.md
runs/
runs/sessions/
```

## Blocked Paths (Do NOT recommend files in these locations)

- `!workspace/.gitkeep`
- `benchmark/`
- `!tests/fixtures/benchmark/`
- `.DS_Store`
- `__pycache__/`
- `*.py[cod]`
- `MIGRATION_VERIFICATION_REPORT.md`
- `runs/`
- `runs/sessions/`


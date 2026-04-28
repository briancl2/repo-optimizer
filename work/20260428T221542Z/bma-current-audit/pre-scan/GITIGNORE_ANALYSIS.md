# .gitignore Analysis

## Contents

```
.DS_Store

# Target repo snapshots (large, local-only)
targets/T1-build-meta-analysis/
targets/T2-briancl2-customers-public/
targets/T3-transcript-processor/
targets/T4-territory-manager/
targets/T5-portfolio-advisor/
targets/T6-repo-upgrade-advisor-B4/
targets/T7-briancl2-customer-newsletter/
targets/T7-CP1/
targets/T7-CP2/
targets/T7-CP3/
targets/T8-portfolio-advisor-current/
targets/T9-obsidian-vault/
targets/T10-transcript-processor/
targets/T11-repo-upgrade-advisor-v2/
targets/T1-pre-skills/

# Quality test artifacts (generated, can be large)
# Keep the summaries but not the full stdout
# runs/*/quality/*/func-test-*.txt

# Evidence retention policy (L100):
# Keep summaries, scorecards, and reports in git.
# Compress/exclude heavy pre-scan dumps (AI surface full text).
# Compressed dumps (.gz) are committed; raw dumps are excluded.
runs/**/AI_SURFACES_FULL.md

# Session log archives (local-only, potentially large)
runs/sessions/

# Python cache
__pycache__/
*.pyc

# Self-audit outputs (transient, regenerable)
runs/self-audit/

# Work contract dirs (large audit artifacts, transient)
work/

# Staging area for fail-closed work-init startup
.work-init-staging/
```

## Blocked Paths (Do NOT recommend files in these locations)

- `.DS_Store`
- `targets/T1-build-meta-analysis/`
- `targets/T2-briancl2-customers-public/`
- `targets/T3-transcript-processor/`
- `targets/T4-territory-manager/`
- `targets/T5-portfolio-advisor/`
- `targets/T6-repo-upgrade-advisor-B4/`
- `targets/T7-briancl2-customer-newsletter/`
- `targets/T7-CP1/`
- `targets/T7-CP2/`
- `targets/T7-CP3/`
- `targets/T8-portfolio-advisor-current/`
- `targets/T9-obsidian-vault/`
- `targets/T10-transcript-processor/`
- `targets/T11-repo-upgrade-advisor-v2/`
- `targets/T1-pre-skills/`
- `runs/**/AI_SURFACES_FULL.md`
- `runs/sessions/`
- `__pycache__/`
- `*.pyc`
- `runs/self-audit/`
- `work/`
- `.work-init-staging/`


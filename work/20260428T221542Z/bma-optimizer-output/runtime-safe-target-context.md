# Runtime-Safe Target Context

> Deterministic inventory for optimizer discovery. Read this first before any optional shell exploration.

## AI Surfaces

| path | lines |
|---|---:|
| AGENTS.md | 119 |
| targets/T6-repo-upgrade-advisor-B4/pack/AGENTS.md | 18 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/target-profiler.agent.md | 34 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/spec-pack-builder.agent.md | 28 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/evidence-validator.agent.md | 32 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/critic.agent.md | 32 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/upgrade-advisor.agent.md | 42 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/patch-pack-generator.agent.md | 33 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/source-digestor.agent.md | 26 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/instruction-hierarchy-auditor.agent.md | 35 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/agents/opportunity-mapper.agent.md | 33 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/prompts/advisor-recommend-upgrades.prompt.md | 30 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/prompts/advisor-ingest-sources.prompt.md | 29 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/prompts/advisor-audit-target.prompt.md | 25 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/prompts/advisor-plan-migration.prompt.md | 30 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/prompts/advisor-generate-patches.prompt.md | 32 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/prompts/advisor-spec-pack.prompt.md | 28 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/prompts-to-skills-migration/SKILL.md | 32 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/spec-pack-builder/SKILL.md | 26 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/agent-architecture-audit/SKILL.md | 22 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/vscode-settings-recommender/SKILL.md | 25 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/breaking-change-detection/SKILL.md | 22 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/model-update-impact/SKILL.md | 23 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/capability-extraction/SKILL.md | 23 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/instruction-audit/SKILL.md | 23 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/source-ingestion/SKILL.md | 28 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/changelog-parsing/SKILL.md | 28 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/patch-pack-generator/SKILL.md | 41 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/mcp-config-audit/SKILL.md | 22 |
| targets/T6-repo-upgrade-advisor-B4/pack/.github/skills/copilot-cli-transcript-analysis/SKILL.md | 32 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.taskstoissues.agent.md | 30 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.tasks.agent.md | 137 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.checklist.agent.md | 294 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.clarify.agent.md | 181 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.constitution.agent.md | 82 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.specify.agent.md | 258 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.analyze.agent.md | 184 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.plan.agent.md | 89 |
| targets/T6-repo-upgrade-advisor-B4/.github/agents/speckit.implement.agent.md | 135 |
| targets/T6-repo-upgrade-advisor-B4/.github/prompts/speckit.plan.prompt.md | 3 |

## Workflow And Script Surfaces

| path | lines |
|---|---:|
| scripts/closeout-disposition.py | 1062 |
| scripts/quick-validate-signature.sh | 49 |
| scripts/classify-phase-output.py | 31 |
| scripts/score-output-quality.sh | 448 |
| scripts/run-closure-sequencing-pilot.py | 331 |
| scripts/audit-targets.sh | 46 |
| scripts/build-stage17-post-closure-operating-model-retro-bundle.py | 835 |
| scripts/extract-repo-dna.sh | 236 |
| scripts/validate-newsletter-proof-state.py | 203 |
| scripts/prepare-clean-audit-snapshot.py | 232 |
| scripts/validate-ds13-17.sh | 243 |
| scripts/validate-output-registry.py | 276 |
| scripts/analyze-phase-fingerprints.py | 1093 |
| scripts/freeze-simplification-confirmation-cases.py | 105 |
| scripts/spec-orchestrator.sh | 210 |
| scripts/code-review-sweep.sh | 198 |
| scripts/stall-risk-score.sh | 280 |
| scripts/review-budget.py | 319 |
| scripts/preflight-end-of-work.py | 237 |
| scripts/warn-ledger.sh | 213 |
| scripts/run-gap-analysis.sh | 152 |
| scripts/compare-scorecards.sh | 276 |
| scripts/review-reuse.py | 226 |
| scripts/run-make-critique.sh | 68 |
| scripts/finalize-simplification-confirmation.py | 68 |
| scripts/score-session.sh | 1003 |
| scripts/collect-session-metrics.sh | 202 |
| scripts/independent-canary.sh | 168 |
| scripts/validate-foundational-reentry-gate.py | 123 |
| scripts/build-post-migration-gap-review.py | 579 |
| scripts/extract-proven-patterns.sh | 187 |
| scripts/analyze-make-clock-time.py | 1639 |
| scripts/freeze-external-critique-coverage.py | 612 |
| scripts/pre-commit-hook.sh | 51 |
| scripts/freeze-external-critique-live-corpus.py | 296 |
| scripts/analyze-token-usage.py | 1432 |
| scripts/ground-truth-t5.sh | 134 |
| scripts/build-principle-realignment-bundle.py | 1611 |
| scripts/parse-session-log.py | 176 |
| scripts/validate-agents-md.py | 92 |
| scripts/diagnose-gate-cache.py | 209 |
| scripts/build-newsletter-token-cost-analysis.py | 1913 |
| scripts/gate-cache.py | 311 |
| scripts/reconcile-external-critique-mismatches.py | 657 |
| scripts/score-fleet-output.sh | 743 |
| scripts/classify-repo-maturity.sh | 160 |
| scripts/ground-truth-t1.sh | 184 |
| scripts/audit-simplification-reusable-candidates.py | 129 |
| scripts/fix-diff-headers.sh | 155 |
| scripts/closeout-reconciliation.py | 761 |
| scripts/build-artifact-index.sh | 134 |
| scripts/analyze-gpt55-runtime-regression.py | 1345 |
| scripts/run-propagation-pipeline.sh | 272 |
| scripts/session-tool-matrix.py | 255 |
| scripts/expand-external-critique-evidence.py | 302 |
| scripts/inspect-session-format.py | 69 |
| scripts/analyze-capability-drift.py | 451 |
| scripts/fleet-deep-analysis.py | 134 |
| scripts/validate-handoff-closeout-sync.py | 927 |
| scripts/backtest-simplification-method.py | 554 |

## Largest Text Files

| path | lines |
|---|---:|
| research/evidence/make-clock-next-session-2026-04-27/last-30d/session-scope.json | 64757 |
| research/evidence/work-closure-makefile-speedup-retrospective-2026-04-28/last-30d/session-scope.json | 62069 |
| research/evidence/closure-gate-delete-merge-analysis-2026-04-28/last-30d/session-scope.json | 61845 |
| targets/T9-obsidian-vault/Planning/meeting-prep-engine-research/data/02_attendee_graphs.json | 18164 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260205T053420/results.json | 16897 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260205T060845/results.json | 16897 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T191203/results.json | 16843 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T202433/results.json | 16843 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T202629/results.json | 16843 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T190315/results.json | 16824 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260202T080654/results.json | 16483 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260129T134726/results.json | 15632 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T154704/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T152832/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T153422/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T154606/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T152242/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T154534/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T185149/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260128T155804/results.json | 14547 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T154215/results.json | 14327 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T144710/results.json | 14327 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T143722/results.json | 14143 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T140822/results.json | 13999 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T140417/results.json | 13999 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T141018/results.json | 13999 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T140304/results.json | 13999 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T135852/results.json | 13999 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T141310/results.json | 13999 |
| targets/T9-obsidian-vault/Planning/diagnostic-logs/higr/20260126T140059/results.json | 13999 |

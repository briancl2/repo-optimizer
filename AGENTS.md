# AGENTS.md — repo-optimizer

> Produce concrete optimization plans and optional validated patches from
> repo-auditor output. Report-only is the default; `--patch` is explicit.

## Purpose

`repo-optimizer` reads `SCORECARD.json` and `AUDIT_REPORT.md`, then emits an
`OPTIMIZATION_PLAN.md`. With `PATCH=true` or `--patch`, it also emits unified
diffs validated with `git apply --check`. Keep this file as the live
bootloader; detailed agent, script, benchmark, and spec-kit inventories live in
`docs/agent-operations.md`.

## Operating Rules

- Report-only by default. Patch generation requires explicit `--patch` /
  `PATCH=true`.
- Target repositories are never modified directly; only reports and patch files
  are produced.
- Generated patches must pass `git apply --check`.
- Adversarial critique is mandatory and must reject at least one finding per
  run.
- `--no-verify` is never permitted.
- Deterministic tests that exercise `scripts/repo-optimizer.sh` must stay
  preflight-only with `OPTIMIZER_PREFLIGHT_ONLY=true`.
- Raw command output stays in `.jsonl`, stdout, or runtime receipts. Human and
  machine-facing summaries cite command, outcome, and retained path.

## Commands

```bash
make optimize TARGET=~/repos/some-repo AUDIT=path/to/audit_output
make optimize TARGET=~/repos/some-repo AUDIT=path/to/audit_output PATCH=true
make patch-check TARGET=~/repos/some-repo OUTPUT_DIR=optimizer_output
make transfer-oracle DECISIONS=<path> OUTPUT_DIR=<dir>
make benchmark-optimization-workloads CORPUS=<path> OUTPUT_DIR=<dir> MODE=retained-replay
make normalize-agent-run-receipts RECEIPTS=<path> OUTPUT_DIR=<dir>
make build-live-paired-corpus FIXTURES=<path> RECEIPTS=<path> OUTPUT_DIR=<dir>
make collect-live-agent-receipts FIXTURES=<path> ADAPTER=<codex|copilot|generic> OUTPUT_DIR=<dir>
make check
make test
make validate
make review
make work DESC="..."
make work-close WORK=work/<dir>
make install-hooks
```

## Patch Constraints

- Maximum 5 patches per run.
- Each patch touches at most 6 files and 160 net lines.
- No dependency changes.
- Hunk headers are post-processed and validated.
- Cleanup-ledger and patch-pack contracts must stay schema-valid.

## Stop Rules

- Halt if `SCORECARD.json` is missing.
- Max 200 files scanned per target.
- Max 30 findings per domain subagent.
- Max 900 seconds per run.
- Do not infer target-local proof from scan-limited, snapshot-only, or
  benchmark-only evidence.

## References

- Invocation contract: `docs/invocation-contract.md`
- Current program status: `docs/current-program-status.md`
- Provider-neutral Tier 3 benchmarks: `docs/provider-neutral-tier3-benchmarks.md`
- Agent operations inventory: `docs/agent-operations.md`
- Constitution: `.specify/memory/constitution.md`

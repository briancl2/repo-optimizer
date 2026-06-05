# repo-optimizer

## Learning / Recovery

- Decision changed: build-meta-analysis Issue #431 promoted repo-optimizer Issue #75 from AS-32 triage to a README-only owner repair after fresh merged-head replay produced a patch-ready LR-01 row and clean apply-check.
- GitHub surface / owner action: https://github.com/briancl2/repo-optimizer/issues/75 and the README-only owner PR that closes it.
- Raw runtime evidence: repo-auditor AS-32 reported `unanchored_self_learning_claim=>README.md`; repo-upgrade-advisor emitted `patch_target_file=README.md`; repo-optimizer replay wrote `RECOVERY_RUNTIME_REPLAY_RECEIPT.json`, `PATCH_PACK_METADATA.json`, and `recovery-runtime-validate-patches.log` under `/tmp/issue164-merged-head-20260604T111850Z/optimizer/repo-optimizer/`.
- GBrain disposition: `no_capture_reason=field replay evidence was sufficient and did not change the route through memory lookup`.
- Reusable learning text: self-management claims in root guidance need an owner GitHub surface, raw runtime evidence, memory disposition, and explicit non-claims before they are treated as grounded.
- Bounded non-claims: This block does not authorize background memory, schedulers, queues, daemons, controllers, autofix loops, autonomous downstream mutation, or target-repo mutation.

Standalone **repo optimizer** — produces concrete patches that improve audit scores for any AI-native repository. Part of the [repo-agent fleet](https://github.com/briancl2/repo-agent-core).

## Quick Start

```bash
# Optimize a target repository (reads SCORECARD.json + OPPORTUNITIES.md)
make optimize TARGET=~/repos/some-target-repo AUDIT=path/to/SCORECARD.json

# Review staged changes
make review
```

## What It Does

1. **Reads** SCORECARD.json (from repo-auditor) + OPPORTUNITIES.md (from repo-upgrade-advisor)
2. **Dispatches 4 domain subagents** — decomposition, consolidation, extraction, standardization
3. **Adversarial critic** reviews all findings, must reject ≥1 or justify
4. **Generates** validated unified-diff patches (≤6 files, ≤160 lines each)
5. **Produces** PATCH_PACK/ directory + OPTIMIZATION_SCORECARD.json

## Outputs

| File | Format | Consumer |
|---|---|---|
| `PATCH_PACK/*.patch` | Unified diff | Developer / continuous loop |
| `OPTIMIZATION_SCORECARD.json` | Machine-readable | Continuous loop |
| `OPTIMIZATION_REPORT.md` | Human-readable | Developer |

## Invocation Modes

- **Mode A (Outbound):** Run from this repo targeting an external repo
- **Mode B (Inbound):** Invoked from within a target repo pointing at this repo

See `docs/invocation-contract.md` for the full I/O contract.

## Self-Management (spec 054)

repo-optimizer is a self-managing repo-agent with governance, measurement, and self-improvement:

```bash
make check                     # Gate 2: shellcheck + inventory + trailers
make work DESC="description"   # Gate 1: open work contract
make work-close WORK=<dir>     # Gate 3: close contract + session grader
make test                      # All tests (domain + infrastructure)
make install-hooks             # Install pre-commit hook
```

`make test` is deterministic by contract. The suite uses `OPTIMIZER_PREFLIGHT_ONLY=true` when it exercises `repo-optimizer.sh` so budget-tier coverage never blocks on Copilot-backed phases.
GitHub Actions runs `make check` and `make test` on pull requests and pushes to `main`; the CI test job checks out `repo-agent-core` read-only and sets `REPO_AGENT_CORE` for shared schema validation.

See `AGENTS.md` for full script inventory and `.specify/memory/constitution.md` for governance.

## Live Capability Inventory

The [live capability inventory](docs/live-capability-inventory.md) records
repo-optimizer's live agents, scripts, Speckit helpers, and tracking decisions
for calibrated capability-drift checks. It is documentation, not a runtime
registry or generated control plane.

## Dependencies

Shared primitives from [repo-agent-core](https://github.com/briancl2/repo-agent-core) (copied, not symlinked).

## License

MIT

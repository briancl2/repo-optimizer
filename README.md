# repo-optimizer

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

See `AGENTS.md` for full script inventory and `.specify/memory/constitution.md` for governance.

## Dependencies

Shared primitives from [repo-agent-core](https://github.com/briancl2/repo-agent-core) (copied, not symlinked).

## License

MIT

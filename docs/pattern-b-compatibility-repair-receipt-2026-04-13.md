# Pattern B Compatibility Repair Receipt

## Operator Intent

Make the public Pattern B entrypoint retain a terminal bundle on the same
retained proof inputs instead of dying during shell-output wait, or fail with a
narrower owner-side cause.

## Delivered

- Updated `scripts/repo-optimizer.sh` so each long Copilot-backed phase emits
  bounded stdout progress while its raw JSONL transcript is still being
  captured to disk.
- Extended `tests/test-discovery-payload-capture.sh` to simulate slow Copilot
  phases and verify the orchestrator now prints bounded progress without
  breaking payload or receipt capture.
- Updated `docs/invocation-contract.md` so this bounded stdout progress is part
  of the public Pattern B contract rather than an implicit implementation
  detail.
- Ran `make test` successfully after the repair.
- Retained one fresh public Pattern B rerun under
  `work/20260413T225957Z/pattern-b-terminal-contract-fixed` against:
  - bound target repo: `repo-auditor@f31933cda7d297e13d18b7ccca7044d09a8fec43`
  - retained audit bundle:
    `/Users/briancl/repos/build-meta-analysis/work/20260411T192401Z/repo-star-proof/audit`
  - public wrapper prompt constrained to one exact shell command:
    `bash scripts/repo-optimizer.sh <bound-repo-auditor> <retained-audit-dir> <pattern-b-output> --patch`

## Outcome

The owner-side compatibility repair worked.

The fresh public Pattern B rerun no longer died at the shell-supervision layer.
Its top-level terminal log progressed past the earlier silent wait failure,
surfaced shell-output reads, and finished with `Pipeline completed successfully`
instead of `Operation cancelled by user`.

The retained output bundle now includes the terminal artifacts that were
missing in the earlier bounded receipt:

- `RUNTIME_RECEIPTS.json`
- `critic-phase-receipt.json`
- `synthesis-phase-receipt.json`
- `critic-verdicts.md`
- `OPTIMIZATION_PLAN.md`
- `OPTIMIZATION_SCORECARD.json`

On the decision fields that mattered for the `v423` owner-side question about
the `v414` proof line, the repaired public Pattern B run now matches the
already-retained root-command proof family:

- `patch_mode: true`
- critic `status: completed`
- synthesis `status: completed`
- patch generation `status: fail_closed_patch_generation_unavailable`
- `patches_valid: 0`
- no `PATCH_PACK/` artifacts produced

The repaired public Pattern B runtime also retained the same high-level
discovery shape as the earlier root-command proof family: 3 successful
discovery domains, 1 failed discovery domain, and `COMMAND_BLOCKED` still
detected somewhere inside the Copilot-backed discovery lane. In this repaired
public rerun the blocked discovery note landed on `standardization`; in the
earlier retained root receipt it landed on `decomposition`. That is a runtime
detail difference, but it does not change the owner-side answer on the exact
comparison fields that `v423` needed.

## Not Yet Delivered

- This batch does not eliminate `COMMAND_BLOCKED` inside discovery.
- It does not generate any patch artifact.
- It does not reopen the BMA-side boundary question; it only repairs and
  records the owner-side Pattern B compatibility result.

## Open Questions

Non-blocking: should `repo-optimizer` also harden discovery prompts further so
the remaining blocked discovery lane stops trying tool-based table emission and
materializes more than 3 successful discovery payloads on this proof input?

## Recommended Next Step

Hand this repaired owner-side receipt back to BMA and let the `v423` line use
it as the retained answer to the owner-side compatibility batch. If a new
owner-side batch is opened after that, make it about reducing the remaining
discovery `COMMAND_BLOCKED` rate rather than about shell-output survival.

## Human Input Needed

None for this owner-side repair. Human input is only needed if BMA wants to
decide whether the remaining blocked discovery lane matters for the downstream
proof beyond the exact comparison fields already repaired here.

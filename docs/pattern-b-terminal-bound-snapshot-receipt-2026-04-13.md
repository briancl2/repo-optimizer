# Pattern B Terminal Bound Snapshot Receipt

## Operator Intent

Retain one bounded public Pattern B terminal receipt on the bound snapshot for
the `v414` proof line so the owner surface can answer one exact question
truthfully: does public Pattern B reach the same terminal state already
retained for the root command, or expose a real divergence?

This receipt intentionally cites host-local absolute paths where needed because
the retained proof artifacts being compared live across sibling local repos and
work packages, not inside committed `repo-optimizer` surfaces alone.

## Delivered

- Opened `work/20260413T223123Z/WORK.md` for one runtime-evidence batch on the
  owner surface.
- Created detached bound-snapshot worktrees at the retained commits named by
  the proof family:
  `repo-optimizer@12f2b2a334337f9e86de2784a4eed57e548a3eae` and
  `repo-auditor@f31933cda7d297e13d18b7ccca7044d09a8fec43`.
- Reused the retained audit bundle
  `/Users/briancl/repos/build-meta-analysis/work/20260411T192401Z/repo-star-proof/audit`
  so the runtime inputs stayed on the same bound proof seam.
- Retained one invalid calibration attempt under
  `work/20260413T223123Z/pattern-b-terminal`, where the public Pattern B
  entrypoint drifted off-contract into
  `OPTIMIZER_PREFLIGHT_ONLY=true` plus manual phase dispatch. That attempt does
  not count as the requested receipt.
- Retained one contract-bound Pattern B attempt under
  `work/20260413T223123Z/pattern-b-terminal-contract`, whose terminal log shows
  the top-level agent reading
  `docs/invocation-contract.md`, then launching the exact public root command:
  `bash scripts/repo-optimizer.sh <bound-repo-auditor> <retained-audit-dir> <pattern-b-output> --patch`,
  where the angle-bracket tokens are schematic stand-ins for the concrete
  bound paths retained in the local terminal log.
- Compared that retained attempt against the invocation contract's
  always-expected outputs: `OPTIMIZATION_PLAN.md`,
  `OPTIMIZATION_SCORECARD.json`,
  `critic-phase-receipt.json`, `synthesis-phase-receipt.json`, and
  `RUNTIME_RECEIPTS.json`.
- Retained the post-run artifact inventory for that contract-bound attempt in
  `work/20260413T223123Z/pattern-b-terminal-contract/artifact-list.txt` and
  the top-level terminal log in
  `work/20260413T223123Z/pattern-b-terminal-contract/copilot-terminal.txt`.

## Outcome

This batch retained a bounded Pattern B terminal result, and it does expose a
real divergence from the already-retained root-command runtime.

The contract-bound Pattern B attempt did launch the exact admitted public root
command on the bound commits and retained audit bundle. But it did not reach
the retained root terminal state. The top-level Pattern B terminal log ends
after a `Read shell output Waiting up to 300 seconds for command output`
message and records `Operation aborted by user` / `Operation cancelled by
user`. The retained bundle for that same attempt contains only pre-flight and
discovery payload artifacts:

- `pre-flight.json`
- `runtime-safe-target-context.md`
- `payloads/decomposition.md.jsonl`
- `payloads/consolidation.md.jsonl`
- `payloads/extraction.md`
- `payloads/extraction.md.jsonl`
- `payloads/standardization.md.jsonl`

It does not contain the terminal artifacts that the retained root run already
has:

- no `RUNTIME_RECEIPTS.json`
- no `critic-phase-receipt.json`
- no `synthesis-phase-receipt.json`
- no `OPTIMIZATION_PLAN.md`
- no `OPTIMIZATION_SCORECARD.json`
- no `PATCH_PACK/` or retained `*.patch`

That differs directly from the retained root-command receipt already bound to
the same proof seam in
`/Users/briancl/repos/build-meta-analysis/work/20260411T192401Z/repo-star-proof/optimizer/RUNTIME_RECEIPTS.json`,
which records:

- `patch_mode: true`
- critic `status: completed`
- synthesis `status: completed`
- patch generation `status: fail_closed_patch_generation_unavailable`
- `patches_valid: 0`

So the truthful owner-side result is not “Pattern B matches the root.” It is:
on this host and bound snapshot, the public Pattern B entrypoint launches the
same root command, but the top-level agent path does not stay alive long enough
to retain the same terminal bundle.

That means the divergence is not only from the retained root replay. It is also
from `repo-optimizer`'s own invocation contract, which says those terminal
artifacts are expected outputs for every run.

## Exact Divergence

The divergence retained here is precise and bounded:

- Pattern B launches the correct bound root command.
- The run materializes pre-flight plus discovery payload artifacts.
- The top-level terminal log then cancels during a shell-output wait instead of
  reaching critic, synthesis, patch-generation, and runtime-receipt closeout.
- The durable owner-side conclusion is therefore about equivalence failure at
  the terminal-bundle layer, not about whether the public entrypoint can launch
  the correct root command.

This is enough to answer the `v423` owner-side question about the `v414` proof
line truthfully. Pattern B does not currently retain the same terminal
evidence family as the retained root-command run on this bound snapshot.

## Not Yet Delivered

- This batch does not produce a successful Pattern B terminal bundle that
  matches the retained root-command receipt.
- It does not produce any patch artifact.
- It does not adjudicate whether the divergence is a host-shell supervision
  problem, a Copilot CLI integration problem, or a broader Pattern B contract
  compatibility problem.
- It does not reopen the BMA-side boundary decision; it only reports the
  owner-side runtime result.

## Open Questions

Non-blocking: the exact owner-side divergence is now retained, but one repair
question remains open. Autonomous next step: decide whether `repo-optimizer`
should treat Pattern B’s current shell-output cancellation as an accepted
entrypoint limitation or repair it so Pattern B can retain the same terminal
bundle as the root command.

## Recommended Next Step

Open one bounded owner-side compatibility batch in `repo-optimizer` to make
the public Pattern B entrypoint retain a terminal bundle instead of cancelling
during shell-output wait. Success means one rerun on the same bound snapshot
reaches terminal artifacts comparable to the retained root receipt, or else
retains a narrower implementation-level reason why that cannot happen.

## Human Input Needed

None to retain the bounded runtime result recorded here. Human input is only
needed if BMA wants to treat this divergence as acceptable and keep using
Pattern B as equivalent to the root command without an owner-side repair.

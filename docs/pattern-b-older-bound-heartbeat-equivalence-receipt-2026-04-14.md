# Pattern B Older-Bound Heartbeat Equivalence Receipt

## Operator Intent

Retain one immutable owner-side artifact pinned to the actual older bound
`repo-optimizer@12f2b2a334337f9e86de2784a4eed57e548a3eae` surface that answers
the still-open `v425` equivalence-gap question truthfully: does the same
shell-output blocker family still hold on that older owner surface, or does
current retained evidence still need a broader replay to say so?

This receipt cites one sibling-repo proof anchor because the retained seam for
this question still spans the owner repo plus the already-bound BMA proof
bundle. In the operator environment used for this receipt,
`$BMA_REPO` resolves to `/Users/briancl/repos/build-meta-analysis`. That
cross-repo path is provenance for the reused audit bundle only; the owner-side
equivalence conclusion in this receipt is supported by the retained
`repo-optimizer` work artifacts named below.

## Delivered

- Opened `work/20260414T123522Z/WORK.md` for one older-bound owner-side
  equivalence batch.
- Reused the retained older-surface failure receipt in
  `docs/pattern-b-terminal-bound-snapshot-receipt-2026-04-13.md`, which had
  already shown that the unmodified older bound public Pattern B path launched
  the correct command, then stopped at shell-output wait before terminal
  closeout.
- Created fresh detached bound worktrees under
  `work/20260414T123522Z/bound/` for:
  - `repo-optimizer@12f2b2a334337f9e86de2784a4eed57e548a3eae`
  - `repo-auditor@f31933cda7d297e13d18b7ccca7044d09a8fec43`
- Derived one script-only repair delta in
  `work/20260414T123522Z/heartbeat-only-repair.patch` by diffing the older
  bound owner surface against the later owner-side heartbeat repair commit
  `e114efb`, but limiting the applied change to `scripts/repo-optimizer.sh`.
- Applied only that script-level bounded-stdout heartbeat delta to a disposable
  older-bound owner-surface copy at
  `work/20260414T123522Z/bound/repo-optimizer-old-heartbeat`.
- Replayed the same public Pattern B path against the same retained
  `repo-auditor` target and the same retained audit bundle from
  `$BMA_REPO/work/20260411T192401Z/repo-star-proof/audit`.
- Retained the patched older-surface output bundle in
  `work/20260414T123522Z/pattern-b-terminal-contract-old-heartbeat-fixed/`,
  including the top-level terminal log
  `copilot-terminal.txt`, `RUNTIME_RECEIPTS.json`, critic and synthesis
  receipts, `critic-verdicts.md`, `OPTIMIZATION_PLAN.md`, and
  `OPTIMIZATION_SCORECARD.json`.

## Outcome

This batch closes the owner-side equivalence gap directly on the actual older
bound owner surface.

The retained comparison is now:

- **unmodified older bound surface:** the earlier retained receipt stops after
  `Waiting up to 300 seconds for command output`, then records
  `Operation aborted by user` / `Operation cancelled by user`, and the output
  bundle contains only pre-flight plus discovery artifacts
- **same older bound surface plus only the script-level heartbeat delta:** the
  new retained terminal log also passes through a
  `Waiting up to 300 seconds for command output` window, but it then records
  `Pipeline completed successfully`, and the bundle reaches terminal closeout
  with `RUNTIME_RECEIPTS.json`, critic and synthesis receipts, and the final
  markdown artifacts

That matters because this batch did **not** widen the proof inputs:

- same older bound `repo-optimizer` commit family
- same retained `repo-auditor` target commit
- same retained audit bundle
- same public Pattern B shell-command path
- isolated owner-side delta limited to `scripts/repo-optimizer.sh`

On the key comparison fields already reused on the BMA seam, the patched
older-surface replay now lands in the same decision family as the retained
root-command proof:

- `patch_mode: true`
- critic `status: completed`
- synthesis `status: completed`
- patch generation `status: fail_closed_patch_generation_unavailable`
- `patches_valid: 0`
- no retained patch artifacts

The patched older-surface replay actually produced a cleaner discovery result
than the earlier retained root proof family (`4` discovery successes, `0`
fails, and `command_blocked_detected: false`). That is a real runtime detail,
but it is not needed for the bounded owner-side conclusion here.

The truthful owner-side result is therefore:

The same blocker family does hold on the actual older bound owner surface.
Without the bounded-stdout heartbeat behavior, the older public Pattern B path
fails before terminal closeout. Applying only that owner-side heartbeat
behavior on the older surface is enough to preserve the terminal bundle on the
same proof inputs. That closes the `v425` equivalence gap between the later
repaired-surface replay and the actual older bound owner surface.

## Not Yet Delivered

- This batch does not itself decide the downstream BMA `v425` blocker line or
  the stronger `v423` / `v414` exclusion line. It closes the owner-side
  equivalence question only.
- It does not claim that every broader host, wrapper, or future Copilot CLI
  release will behave the same way.
- It does not commit the experimental older-surface patch to the owner repo's
  main line, because that repair already exists separately in the later owner
  surface history.
- It does not generate any patch artifact for the target repo.

## Open Questions

None. Autonomous next step: return this retained owner-side equivalence receipt
to BMA so the downstream proof line can decide what it now truthfully proves
for the exact `v425` blocker line and the stronger `v423` / `v414` line.

## Recommended Next Step

Hand this receipt back to BMA and let the BMA-side proof line re-evaluate the
exact `v425` blocker line using this older-surface equivalence closure. If a
later owner-side follow-on is still wanted after that, make it about hardening
or monitoring heartbeat guarantees rather than re-asking whether the older
surface shared the same blocker family.

## Human Input Needed

None for this owner-side batch. Human input becomes relevant only if a later
surface wants to widen this bounded equivalence result into a broader claim
than the retained proof seam supports.

# Pattern B Shell-Output Causal Isolation Receipt

## Operator Intent

Retain one direct owner-side causal-isolation receipt showing whether the older
shell-output-wait failure was itself the exact blocker that kept the same-proof
public Pattern B path from preserving the terminal bundle without changing the
owner surface.

This receipt cites one local audit anchor because the retained proof seam for
this question spans sibling repos and work packages, not only committed
`repo-optimizer` surfaces. In the operator environment used for this receipt,
`$BMA_REPO` resolves to the sibling `build-meta-analysis` checkout.

## Delivered

- Opened `work/20260414T013625Z/WORK.md` for one owner-side causal-isolation
  batch.
- Created one fresh bound target checkout at
  `repo-auditor@f31933cda7d297e13d18b7ccca7044d09a8fec43` under
  `work/20260414T013625Z/bound/repo-auditor` so the replay used the same proof
  target as the retained `v414` owner-side line.
- Reused the same retained audit bundle from
  `$BMA_REPO/work/20260411T192401Z/repo-star-proof/audit`.
- Ran one fresh public Pattern B replay on the current owner surface with
  `OPTIMIZER_PROGRESS_INTERVAL=500` seconds, which effectively suppresses the
  bounded stdout heartbeat added by commit `e114efb`. The replay's top-level
  terminal log was retained in
  `work/20260414T013625Z/pattern-b-no-heartbeat-terminal.txt`.
- Retained the partial runtime bundle from that replay under
  `work/20260414T013625Z/pattern-b-terminal-contract-no-heartbeat/`.
- Compared that replay directly against the earlier bound failure receipt in
  `docs/pattern-b-terminal-bound-snapshot-receipt-2026-04-13.md`, the repaired
  success receipt in `docs/pattern-b-compatibility-repair-receipt-2026-04-13.md`,
  and the owner-surface repair diff in commit `e114efb`.

## Outcome

This batch isolates the owner-side causal bridge directly enough to settle the
question.

On the same proof inputs, suppressing the bounded progress heartbeat recreated
the shell-output-wait failure pattern at the public Pattern B layer. The new
top-level terminal log shows:

- the agent launched the same single-command orchestrator path
- one `Waiting up to 300 seconds for command output` pause that resumed only
  when a phase boundary emitted output (`Decomposition done, consolidation
  running`)
- then a second `Waiting up to 300 seconds for command output` pause that ended
  in `Operation aborted by user` / `Operation cancelled by user`

The retained bundle for that replay stopped at:

- `pre-flight.json`
- `runtime-safe-target-context.md`
- `payloads/decomposition.md`
- `payloads/decomposition.md.jsonl`
- `payloads/consolidation.md.jsonl`

It did **not** retain the terminal artifacts that the repaired receipt had
proven reachable on the same proof seam:

- no `critic-phase-receipt.json`
- no `synthesis-phase-receipt.json`
- no `critic-verdicts.md`
- no `OPTIMIZATION_PLAN.md`
- no `OPTIMIZATION_SCORECARD.json`
- no `RUNTIME_RECEIPTS.json`

That matters because commit `e114efb` did not change the target repo, audit
inputs, critic or synthesis artifact parsing, or the proof-line comparison
fields. Its owner-surface behavior change was the addition of bounded stdout
progress during long Copilot-backed phases, plus the matching invocation
contract update that made that behavior public.

So the truthful owner-side conclusion is now narrower and stronger than the
earlier failure-plus-repair comparison alone:

The older shell-output-wait failure was the exact owner-side blocker that kept
the same-proof public Pattern B path from preserving a terminal bundle without
the heartbeat repair. Restoring bounded stdout progress was not just correlated
with the repaired success; suppressing that progress on the same proof inputs
recreated the terminal-bundle loss.

## Not Yet Delivered

- This batch does not reopen the BMA-side exclusion-line decision on its own.
- It does not prove anything broader about every host or every future Copilot
  CLI release; it settles the retained owner-side proof seam used for the
  `v414` / `v423` / `v425` line.
- It does not generate any patch artifact for the target repo.

## Open Questions

None. The next live move is to hand this retained owner-side causal-isolation
receipt back to BMA so the downstream line can use it instead of the weaker
failure-plus-repair comparison alone.

## Recommended Next Step

Return this receipt to BMA and let the `v425` / `v423` / `v414` proof line
decide its exact blocker or exclusion-line claims using this owner-side causal
artifact. If a later owner-side follow-on is needed, make it about hardening
the heartbeat guarantee or proving an explicit maximum silent window, not about
re-asking whether shell-output wait was the blocker.

## Human Input Needed

None for the owner-side causal question. Human input is only needed if BMA
wants to promote this owner-side result into a broader cross-surface claim than
the retained proof seam actually covers.

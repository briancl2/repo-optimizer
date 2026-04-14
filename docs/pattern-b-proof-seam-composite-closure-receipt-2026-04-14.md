# Pattern B Proof-Seam Composite Closure Receipt

## Operator Intent

Retain one composite owner-side receipt on the frozen proof seam so BMA can
consume one exact owner-side object instead of stitching together older
snapshot failure, heartbeat-only equivalence, and admitted-path normalization
from multiple one-off receipts.

## Frozen Inputs

- older bound `repo-optimizer@12f2b2a334337f9e86de2784a4eed57e548a3eae`
- repair comparison commit `repo-optimizer@e114efb`
- retained target `repo-auditor@f31933cda7d297e13d18b7ccca7044d09a8fec43`
- retained audit bundle `/Users/briancl/repos/build-meta-analysis/work/20260411T192401Z/repo-star-proof/audit`
- machine-readable receipt `/Users/briancl/repos/repo-optimizer/work/20260414T153859Z/proof-seam-composite-receipt.json`

## Delivered

- Added one internal proof-seam harness in `scripts/proof-seam-closure.py`.
- Replayed the frozen owner-side comparison on disposable worktrees.
- Retained one machine-readable composite receipt plus this human-readable receipt.
- Recorded admitted-path normalization and patch-artifact scans for the documented public path set.

## Outcome

The frozen owner-side comparison now exists as one retained composite object.

- unmodified older Pattern B: `fresh_wait_message_seen=false`, `terminal_closeout_reached=false`, and `precloseout_failure_reproduced=true`
- older Pattern B plus only the script-level heartbeat delta: `wait_message_seen=false` and `terminal_closeout_reached=true`
- applied comparison delta check: `true`
- admitted-path normalization check: `true`
- admitted-path patch-artifact result: `true`

On this frozen seam, the later repair commit touches more than one file, but the
applied comparison retained here changes only `scripts/repo-optimizer.sh` between
the unmodified older worktree and the heartbeat-only worktree. Without that
script-level heartbeat behavior, public Pattern B still stalls at shell-output wait
before terminal closeout in the earlier retained bound-snapshot receipt, and the
fresh replay retained here reproduces the same pre-closeout partial bundle on the
same older surface before timing out. With only that script-level delta applied back to the
older bound surface, Pattern B reaches full terminal closeout on the same target
and audit bundle. On the admitted public path set, the wrapper, Pattern A, and
Pattern B all normalize to the same root command family. Pattern A and Pattern B
both reached terminal closeout without a generated patch artifact. The `make optimize`
wrapper path mechanically shells to that same root and its timed runtime snapshot also
contained no generated patch artifact before closeout.

## Delta Classification

- `.agents/speckit.analyze.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.checklist.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.clarify.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.constitution.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.implement.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.plan.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.specify.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.tasks.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.agents/speckit.taskstoissues.agent.md` — non_runtime: spec-kit helper not used by the proof seam
- `.github/agents/consolidation-optimizer.agent.md` — non_runtime: not loaded by repo-optimizer runtime; runtime reads .agents/
- `.github/agents/decomposition-optimizer.agent.md` — non_runtime: not loaded by repo-optimizer runtime; runtime reads .agents/
- `.github/agents/extraction-optimizer.agent.md` — non_runtime: not loaded by repo-optimizer runtime; runtime reads .agents/
- `.github/agents/repo-optimizer-synthesis.agent.md` — non_runtime: not loaded by repo-optimizer runtime; runtime reads .agents/
- `.github/agents/standardization-optimizer.agent.md` — non_runtime: not loaded by repo-optimizer runtime; runtime reads .agents/
- `LEARNINGS.md` — non_runtime: memory surface
- `docs/invocation-contract.md` — non_runtime: documentation or retained receipt
- `docs/pattern-b-compatibility-repair-receipt-2026-04-13.md` — non_runtime: documentation or retained receipt
- `docs/pattern-b-terminal-bound-snapshot-receipt-2026-04-13.md` — non_runtime: documentation or retained receipt
- `scripts/repo-optimizer.sh` — runtime_affecting: public root orchestrator used by all admitted paths
- `scripts/score-operation.sh` — runtime_affecting: post-run scorer invoked by repo-optimizer.sh
- `tests/fixtures/good-operation/OPTIMIZATION_PLAN.md` — non_runtime: test-only surface
- `tests/fixtures/good-operation/OPTIMIZATION_SCORECARD.json` — non_runtime: test-only surface
- `tests/fixtures/good-operation/PATCH_PACK/P1-test.patch` — non_runtime: test-only surface
- `tests/fixtures/good-operation/pre-flight.json` — non_runtime: test-only surface
- `tests/fixtures/stub-operation/OPTIMIZATION_PLAN.md` — non_runtime: test-only surface
- `tests/fixtures/stub-operation/OPTIMIZATION_SCORECARD.json` — non_runtime: test-only surface
- `tests/fixtures/stub-operation/pre-flight.json` — non_runtime: test-only surface
- `tests/test-discovery-payload-capture.sh` — non_runtime: test-only surface
- `tests/test-score-operation.sh` — non_runtime: test-only surface

## Admitted Path Scan

- `make_optimize` normalizes to `bash scripts/repo-optimizer.sh <repo-auditor> <audit-dir> <output-dir> --patch` and reports `patch_artifacts_present: false`, `command_exit_code: 124`, and `terminal_closeout_reached: false`
- `pattern_a_bash` normalizes to `bash scripts/repo-optimizer.sh <repo-auditor> <audit-dir> <output-dir> --patch` and reports `patch_artifacts_present: false`, `command_exit_code: 0`, and `terminal_closeout_reached: true`
- `pattern_b_agent` normalizes to `bash scripts/repo-optimizer.sh <repo-auditor> <audit-dir> <output-dir> --patch` and reports `patch_artifacts_present: false`, `command_exit_code: 0`, and `terminal_closeout_reached: true`

## Not Yet Delivered

- This owner-side receipt does not itself make the BMA `v425` ruling.
- It does not itself make the stronger current-live-boundary `v423` / `v414` ruling.
- It does not itself make the post-Stage17 approval decision.
- Fresh host output did not re-emit the literal shell-wait marker; that exact line
  remains anchored by `docs/pattern-b-terminal-bound-snapshot-receipt-2026-04-13.md`.

## Human Input Needed

None for the owner-side proof seam. The next move is BMA-side adjudication using
this composite receipt plus target-bound acceptance-startability verification.


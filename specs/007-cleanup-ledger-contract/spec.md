# Spec 007: Cleanup-Ledger Recommendation Contract

## Goal

Add an additive P5 cleanup-ledger contract to repo-optimizer so cleanup,
delete, archive, and compress recommendations carry machine-readable safety
metadata before any patch output is treated as usable.

## Requirements

- Keep repo-optimizer report-only by default.
- Do not mutate target repositories.
- Preserve existing finding counts, coverage verdicts, target-policy pointers,
  denominator metadata, and artifact-reuse harness behavior.
- Add cleanup metadata as an additive recommendation contract, not as a new score
  dimension or shared-core dependency.
- Fail closed in patch mode when destructive cleanup lacks owner-boundary,
  keep-set, authorization, or sufficient evidence receipts.
- Treat absent repo-auditor P5 dual inventory as insufficient evidence, not as
  authorization.

## Contract Fields

Per finding, the cleanup metadata vocabulary is:

- `cleanup_action_class`: `fix`, `compress`, `delete`, `archive`, `keep`,
  `defer`, `needs_authorization`, or `unclassified_requires_amendment`
- `cleanup_action_scope`: `single_file`, `directory`, `generated_artifact`,
  `archive_surface`, `customer_or_private_surface`, `unknown`
- `destructive_action`: boolean
- `destructive_action_reason`: string or null
- `target_paths`: array of repo-relative paths
- `protected_keep_paths`: array of repo-relative paths that must not be touched
- `keep_set_evidence`: array of evidence objects or strings
- `owner_boundary_class`: `target_owned`, `target_policy_owned`,
  `archive_or_historical`, `customer_or_private`, `generated_or_cache`,
  `third_party_or_vendor`, or `unknown`
- `owner_boundary_evidence`: object or string evidence
- `authorization_status`: `not_required`, `explicit_authorized`,
  `required_missing`, `policy_forbidden`, or `blocked_unknown`
- `evidence_threshold`: `literal_reference`, `reachable_by_command`,
  `unreferenced_with_keep_set`, `policy_conflict`, or `insufficient`
- `cleanup_safety_non_claims`: bounded non-claims for cleanup safety

The aggregate `OPTIMIZATION_SCORECARD.cleanup_contract` records classified
counts, destructive counts, blocked/authorized counts, missing evidence counts,
unclassified amendment counts, and bounded non-claims.

## Non-Claims

- This contract does not prove optimizer quality improved.
- This contract does not authorize target cleanup.
- This contract does not implement repo-auditor P5 dual inventory.
- This contract does not admit repo-agent-core shared extraction.
- This contract does not change target-policy pointer semantics.

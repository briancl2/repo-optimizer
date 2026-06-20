#!/usr/bin/env python3
"""Write a delivery-admission summary for optimizer output bundles."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


START_MARKER = "<!-- repo-optimizer:delivery-admission:start -->"
END_MARKER = "<!-- repo-optimizer:delivery-admission:end -->"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def as_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes"}


def patch_status(scorecard: dict[str, Any]) -> str:
    meta = scorecard.get("meta")
    if isinstance(meta, dict) and meta.get("patch_status"):
        return str(meta["patch_status"])
    if scorecard.get("patch_status"):
        return str(scorecard["patch_status"])
    return "unknown"


def coverage(scorecard: dict[str, Any]) -> dict[str, Any]:
    value = scorecard.get("discovery_coverage")
    return value if isinstance(value, dict) else {}


def coverage_verdict(scorecard: dict[str, Any]) -> str:
    value = scorecard.get("coverage_verdict") or coverage(scorecard).get("coverage_verdict")
    return str(value or "unknown")


def recommendation_strength(scorecard: dict[str, Any]) -> str:
    value = scorecard.get("recommendation_strength") or coverage(scorecard).get("recommendation_strength")
    return str(value or "unknown")


def blocker_codes(blockers: dict[str, Any]) -> dict[str, int]:
    rows = blockers.get("blockers")
    if not isinstance(rows, list):
        return {}
    counts: Counter[str] = Counter()
    for row in rows:
        if not isinstance(row, dict):
            continue
        code = row.get("blocker_code")
        counts[str(code or "unknown")] += 1
    return dict(sorted(counts.items()))


def pipeline_artifact_contract_failures(output_dir: Path, status: str) -> list[dict[str, str]]:
    runtime = load_json(output_dir / "RUNTIME_RECEIPTS.json")
    phases = runtime.get("phases")
    failures: list[dict[str, str]] = []
    if isinstance(phases, dict):
        for phase in ("critic", "synthesis"):
            receipt = phases.get(phase)
            if not isinstance(receipt, dict):
                continue
            phase_status = str(receipt.get("status") or "")
            receipt_class = str(receipt.get("receipt_class") or "")
            if phase_status in {"failed_artifact_contract", "skipped_upstream_critic_failure"}:
                failures.append(
                    {
                        "phase": phase,
                        "status": phase_status,
                        "receipt_class": receipt_class or "unknown",
                    }
                )

    if not failures and status.startswith(("fail_closed_critic_", "fail_closed_synthesis_")):
        failures.append(
            {
                "phase": "optimizer",
                "status": status,
                "receipt_class": "patch_status",
            }
        )
    return failures


def admission(
    output_dir: Path,
    patch_mode: bool,
    scorecard: dict[str, Any],
    blockers: dict[str, Any],
) -> dict[str, Any]:
    patch_count = int(scorecard.get("patches_generated", 0) or 0)
    patches_valid = int(scorecard.get("patches_valid", 0) or 0)
    blocker_count = int(blockers.get("blocker_count", 0) or 0)
    verdict = coverage_verdict(scorecard)
    strength = recommendation_strength(scorecard)
    status = patch_status(scorecard)
    missing_domains = coverage(scorecard).get("missing_domains")
    if not isinstance(missing_domains, list):
        missing_domains = []

    pipeline_failures = pipeline_artifact_contract_failures(output_dir, status)
    coverage_limited = verdict in {"blocked", "partial", "pass_with_coverage_gap"}
    patchability_blocked = blocker_count > 0 or status == "fail_closed_patchability_blocked"
    valid_patch_set = patch_count > 0 and patches_valid == patch_count

    if pipeline_failures:
        admission_status = "blocked_pipeline_artifact_contract"
        admitted = False
        next_owner_action = "Do not use this bundle for downstream repair selection; repair or rerun the optimizer phase artifact contract before evaluating coverage or patchability."
    elif not patch_mode:
        admission_status = "report_only"
        admitted = False
        next_owner_action = "Use this bundle for advisory triage only; rerun with patch mode when a target owner wants deterministic patch evidence."
    elif coverage_limited and patchability_blocked:
        admission_status = "blocked_patchability_and_coverage"
        admitted = False
        next_owner_action = "Do not start downstream repair from this bundle; rerun missing discovery domains or open an upstream materializer issue for unsupported rows."
    elif coverage_limited:
        admission_status = "blocked_coverage"
        admitted = False
        next_owner_action = "Do not start downstream repair from this bundle; rerun or repair optimizer discovery until coverage is complete or explicitly accepted by the target owner."
    elif patchability_blocked:
        admission_status = "blocked_patchability"
        admitted = False
        next_owner_action = "Open an upstream materializer issue or target-owner implementation issue for the blocked rows; do not apply recommendations as patches."
    elif valid_patch_set:
        admission_status = "admitted_patch_review"
        admitted = True
        next_owner_action = "Review generated patches and validate with git apply --check before any issue-backed target PR."
    elif patch_count > 0:
        admission_status = "blocked_patch_validation"
        admitted = False
        next_owner_action = "Repair patch generation or target compatibility before routing this bundle to a downstream PR."
    else:
        admission_status = "blocked_no_patch_evidence"
        admitted = False
        next_owner_action = "Treat findings as advisory only until deterministic patch evidence or an explicit target-owner implementation issue exists."

    return {
        "schema_version": "1.0.0",
        "artifact": "DELIVERY_ADMISSION",
        "generated_at": utc_now(),
        "output_dir": str(output_dir),
        "delivery_admitted": admitted,
        "admission_status": admission_status,
        "admission_assessable": not pipeline_failures,
        "next_owner_action": next_owner_action,
        "patch_mode": patch_mode,
        "patch_status": status,
        "patches_generated": patch_count,
        "patches_valid": patches_valid,
        "patchability_blocker_count": blocker_count,
        "patchability_blocker_codes": blocker_codes(blockers),
        "pipeline_failure_count": len(pipeline_failures),
        "pipeline_failures": pipeline_failures,
        "coverage_verdict": verdict,
        "recommendation_strength": strength,
        "missing_discovery_domains": [str(item) for item in missing_domains],
        "evidence_paths": {
            "scorecard": "OPTIMIZATION_SCORECARD.json",
            "runtime_receipts": "RUNTIME_RECEIPTS.json",
            "patchability_blockers": "PATCHABILITY_BLOCKERS.json" if blockers else None,
            "patch_pack": "PATCH_PACK" if (output_dir / "PATCH_PACK").exists() else None,
        },
        "bounded_non_claims": [
            "Delivery admission is advisory owner-routing metadata, not target mutation authority.",
            "Generated patches remain review-only and require git apply --check plus a target owner issue/PR before use.",
            "Coverage-limited or patchability-blocked bundles must not be summarized as delivery-ready.",
            "Pipeline/artifact-contract-blocked bundles are not valid delivery-admission evidence.",
        ],
    }


def section(payload: dict[str, Any]) -> str:
    blocker_codes = payload["patchability_blocker_codes"]
    blockers = ", ".join(f"{code}={count}" for code, count in blocker_codes.items()) or "none"
    missing = ", ".join(payload["missing_discovery_domains"]) or "none"
    lines = [
        START_MARKER,
        "## Delivery Admission",
        "",
        f"- Delivery admitted: `{str(payload['delivery_admitted']).lower()}`",
        f"- Admission assessable: `{str(payload['admission_assessable']).lower()}`",
        f"- Admission status: `{payload['admission_status']}`",
        f"- Recommendation strength: `{payload['recommendation_strength']}`",
        f"- Coverage verdict: `{payload['coverage_verdict']}`",
        f"- Missing discovery domains: {missing}",
        f"- Patch status: `{payload['patch_status']}`",
        f"- Patches: {payload['patches_valid']}/{payload['patches_generated']} valid",
        f"- Patchability blockers: {payload['patchability_blocker_count']} ({blockers})",
        f"- Pipeline artifact-contract failures: {payload['pipeline_failure_count']}",
        f"- Next owner action: {payload['next_owner_action']}",
        "",
        "### Bounded Non-Claims",
        "",
    ]
    lines.extend(f"- {claim}" for claim in payload["bounded_non_claims"])
    lines.append(END_MARKER)
    return "\n".join(lines) + "\n"


def replace_marked_section(text: str, new_section: str) -> str:
    if START_MARKER in text and END_MARKER in text:
        before = text[: text.index(START_MARKER)]
        after = text[text.index(END_MARKER) + len(END_MARKER) :]
        return before.rstrip() + "\n\n" + new_section + after.lstrip("\n")
    stripped = text.rstrip()
    return f"{stripped}\n\n{new_section}" if stripped else new_section


def apply(output_dir: Path, patch_mode: bool) -> int:
    scorecard_path = output_dir / "OPTIMIZATION_SCORECARD.json"
    blockers_path = output_dir / "PATCHABILITY_BLOCKERS.json"
    plan_path = output_dir / "OPTIMIZATION_PLAN.md"
    scorecard = load_json(scorecard_path)
    if not scorecard:
        raise SystemExit(f"missing or invalid scorecard: {scorecard_path}")

    payload = admission(output_dir, patch_mode, scorecard, load_json(blockers_path))
    write_json(output_dir / "DELIVERY_ADMISSION.json", payload)

    scorecard["delivery_admission"] = {
        "delivery_admitted": payload["delivery_admitted"],
        "admission_status": payload["admission_status"],
        "admission_assessable": payload["admission_assessable"],
        "next_owner_action": payload["next_owner_action"],
        "patchability_blocker_count": payload["patchability_blocker_count"],
        "pipeline_failure_count": payload["pipeline_failure_count"],
    }
    scorecard.setdefault("meta", {})
    scorecard["meta"]["delivery_admission_status"] = payload["admission_status"]
    write_json(scorecard_path, scorecard)

    if plan_path.is_file():
        text = plan_path.read_text(encoding="utf-8", errors="replace")
        plan_path.write_text(replace_marked_section(text, section(payload)), encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--output-dir", required=True)
    apply_parser.add_argument("--patch-mode", required=True)
    args = parser.parse_args()
    if args.command == "apply":
        return apply(Path(args.output_dir), as_bool(args.patch_mode))
    raise SystemExit(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())

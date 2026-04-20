#!/usr/bin/env python3
"""Evaluate bounded advisory decisions for repo-optimizer readiness."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SPECIAL_CALIBRATION_BASES = {
    "external_critique": "external_critique_mixed_gate_v1",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decisions", required=True, help="Path to ADVISORY_DECISIONS.json")
    parser.add_argument("--output", required=True, help="Path to TRANSFER_ORACLE_RECEIPT.json")
    parser.add_argument(
        "--capability-family",
        default="",
        help="Optional capability family filter; blank means all decisions.",
    )
    parser.add_argument(
        "--hotspot-id",
        default="",
        help="Optional hotspot filter; blank means all decisions.",
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def die(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def decision_capability_state(decision: dict[str, Any]) -> str:
    candidate = str(decision.get("capability_state") or "").strip()
    if candidate:
        return candidate
    if str(decision.get("transfer_status") or "") == "helper_only":
        return "helper_only"
    return "bounded_calibrated"


def decision_provider_scope(decision: dict[str, Any]) -> str:
    candidate = str(decision.get("provider_scope") or "").strip()
    if candidate:
        return candidate
    return "repo-upgrade-advisor:bounded_advisory_decision"


def decision_calibration_basis(decision: dict[str, Any]) -> str:
    candidate = str(decision.get("calibration_basis") or "").strip()
    if candidate:
        return candidate
    family = str(decision.get("capability_family") or "")
    return SPECIAL_CALIBRATION_BASES.get(family, "bounded_advisory_decision_v1")


def decision_evidence_provenance(decision: dict[str, Any], decisions_path: Path) -> list[str]:
    existing = decision.get("evidence_provenance")
    if isinstance(existing, list):
        cleaned = [str(item).strip() for item in existing if str(item).strip()]
        if cleaned:
            return cleaned
    hotspot = str(decision.get("hotspot_id") or "unknown")
    return [f"{str(decisions_path)}#{hotspot}"]


def admission_from_state(state: str) -> str:
    if state == "ready":
        return "ready"
    if state == "partial":
        return "bounded"
    return "blocked"


def decision_guidance(decision: dict[str, Any]) -> tuple[str, str, str | None]:
    verdict = str(decision.get("verdict") or "")
    transfer_status = str(decision.get("transfer_status") or "")
    capability_family = str(decision.get("capability_family") or "unspecified")

    if verdict == "candidate_remediation" and transfer_status in {"preserved", "partial"}:
        return (
            "ready",
            f"{capability_family} evidence supports a bounded optimizer follow-on on this hotspot.",
            None,
        )

    if verdict == "protect":
        return (
            "partial",
            f"{capability_family} hotspot stays measurement-protected only; do not convert it into optimizer action yet.",
            "protect verdict preserves the bucket but does not authorize optimizer mutation",
        )

    if verdict == "re-bucket":
        return (
            "partial",
            f"{capability_family} hotspot is still a measurement cleanup candidate only; optimizer action remains fail-closed.",
            "re-bucket verdict is attribution cleanup, not optimizer-ready remediation",
        )

    if transfer_status == "helper_only":
        return (
            "blocked",
            f"{capability_family} evidence is helper-only and cannot authorize optimizer action on its own.",
            "helper-only transfer must stay bounded until paired owner-side proof exists",
        )

    return (
        "blocked",
        f"{capability_family} evidence stays insufficient for optimizer action on this hotspot.",
        "insufficient evidence or withheld transfer state blocks optimizer follow-on",
    )


def summarize_state(states: list[str]) -> tuple[str, str]:
    if not states:
        return "blocked", "fail"
    if all(state == "ready" for state in states):
        return "ready", "pass"
    if any(state == "ready" for state in states) or any(state == "partial" for state in states):
        return "partial", "fail"
    return "blocked", "fail"


def summarize_capability_state(rows: list[dict[str, Any]], transfer_state: str) -> str:
    states = {str(row.get("capability_state") or "").strip() for row in rows}
    states.discard("")
    if transfer_state == "ready" or "reusable" in states:
        return "reusable"
    if states == {"helper_only"}:
        return "helper_only"
    return "bounded_calibrated"


def main() -> int:
    args = parse_args()
    decisions_path = Path(args.decisions).resolve()
    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        decision_root = load_json(decisions_path)
    except FileNotFoundError:
        return die(f"Decisions file not found: {decisions_path}")
    except json.JSONDecodeError as exc:
        return die(f"Invalid JSON in decisions file: {exc}")

    if not isinstance(decision_root.get("decisions"), list):
        return die("ADVISORY_DECISIONS payload is missing its decisions array.")

    capability_family_filter = args.capability_family.strip()
    hotspot_filter = args.hotspot_id.strip()

    selected = []
    for decision in decision_root["decisions"]:
        if capability_family_filter and decision.get("capability_family") != capability_family_filter:
            continue
        if hotspot_filter and decision.get("hotspot_id") != hotspot_filter:
            continue
        selected.append(decision)

    if not selected:
        if capability_family_filter or hotspot_filter:
            return die("No advisory decisions matched the requested filter.")
        return die("No advisory decisions were available to evaluate.")

    guidance_rows = []
    constraints: list[str] = []
    states: list[str] = []
    for decision in selected:
        state, guidance, constraint = decision_guidance(decision)
        states.append(state)
        if constraint:
            constraints.append(constraint)
        guidance_rows.append(
            {
                "hotspot_id": decision.get("hotspot_id"),
                "capability_family": decision.get("capability_family"),
                "verdict": decision.get("verdict"),
                "transfer_status": decision.get("transfer_status"),
                "capability_state": decision_capability_state(decision),
                "provider_scope": decision_provider_scope(decision),
                "calibration_basis": decision_calibration_basis(decision),
                "evidence_provenance": decision_evidence_provenance(decision, decisions_path),
                "downstream_admission": admission_from_state(state),
                "consumer_state": state,
                "guidance": guidance,
                "bounded_non_claim": decision.get("bounded_non_claim"),
            }
        )

    transfer_state, verdict = summarize_state(states)
    selected_families = sorted(
        {
            str(decision.get("capability_family") or "unspecified")
            for decision in selected
        }
    )
    family_label = "family" if len(selected_families) == 1 else "families"
    summary = (
        f"repo-optimizer evaluated {len(selected)} bounded advisory decision(s) from "
        f"{decisions_path.name} for capability {family_label} "
        f"{', '.join(selected_families)} and classified the current consumer state as {transfer_state}."
    )
    # Preserve first-seen order while avoiding repeated provenance entries.
    top_level_evidence_provenance = list(
        dict.fromkeys(
            item
            for row in guidance_rows
            for item in row.get("evidence_provenance", [])
        )
    )
    unique_calibration_bases = sorted(
        {
            str(row.get("calibration_basis") or "").strip()
            for row in guidance_rows
            if str(row.get("calibration_basis") or "").strip()
        }
    )
    generated_at = datetime.now(timezone.utc)
    generated_at_iso = generated_at.isoformat()
    receipt_suffix = generated_at.strftime("%Y%m%dT%H%M%S") + f".{generated_at.microsecond:06d}Z"

    receipt = {
        "generated_at": generated_at_iso,
        "schema_version": "1.0.0",
        "artifact": "TRANSFER_ORACLE_RECEIPT",
        "receipt_id": f"repo-optimizer:{transfer_state}:{len(selected)}:{receipt_suffix}",
        "transfer_state": transfer_state,
        "verdict": verdict,
        "source_surface": {
            "name": "repo-upgrade-advisor",
            "artifact": "ADVISORY_DECISIONS",
            "version": str(decision_root.get("schema_version") or "unknown"),
        },
        "target_surface": {
            "name": "repo-optimizer",
            "artifact": "optimizer advisory consumer",
            "version": "1.0.0",
        },
        "blocker_class": None if transfer_state == "ready" else "bounded_non_remediation",
        "receipt_summary": summary,
        "next_constraint": None if transfer_state == "ready" else "; ".join(sorted(set(constraints))),
        "capability_state": summarize_capability_state(guidance_rows, transfer_state),
        "provider_scope": "repo-optimizer:transfer_oracle_consumer",
        "calibration_basis": ", ".join(unique_calibration_bases) if unique_calibration_bases else "transfer_oracle_consumer_v1",
        "evidence_provenance": top_level_evidence_provenance,
        "downstream_admission": admission_from_state(transfer_state),
        "supporting_evidence": [
            str(decisions_path),
            *[
                f"{decisions_path.name}#{row['hotspot_id']}"
                for row in guidance_rows
            ],
        ],
        "bounded_non_claims": [
            "This receipt evaluates optimizer-readiness only; it does not claim an optimizer patch has been generated.",
            "A ready receipt still requires a repo-local optimizer run before any mutation claim becomes true.",
            "Partial or blocked receipts must stay fail-closed and may not be narrated as downstream fleet completion.",
        ],
        "consumer_guidance": guidance_rows,
        "selected_capability_families": selected_families,
    }

    output_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

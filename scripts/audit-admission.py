#!/usr/bin/env python3
"""Audit receipt admission gate for repo-optimizer.

The optimizer is a consumer of repo-auditor outputs.  This helper keeps the
normal path strict: only completed audit receipts with the required report
artifact are admitted.  Partial/failed/missing receipt shapes are blocked unless
the one explicitly labeled calibration mode is active.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

RESEARCH_MODE = "partial-audit-calibration"
RECEIPT_NAMES = ("AUDIT_RUN_RECEIPT.json", "AUDIT_RECEIPT.json", "SCORECARD_RECEIPTS.json")
EXPECTED_DISCOVERY_DOMAINS = ["decomposition", "consolidation", "extraction", "standardization"]


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        return None
    return payload if isinstance(payload, dict) else None


def normalize_status(value: Any) -> str | None:
    if value is None:
        return None
    status = str(value).strip().lower().replace("_", "-")
    if status in {"completed", "complete", "success", "succeeded", "passed", "pass"}:
        return "completed"
    if status in {"partial", "partially-completed", "incomplete", "degraded"}:
        return "partial"
    if status in {"failed", "failure", "error", "errored"}:
        return "failed"
    if status in {"blocked", "aborted"}:
        return "blocked"
    return status or None


def nested_value(payload: dict[str, Any], path: tuple[str, ...]) -> Any:
    value: Any = payload
    for key in path:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def first_status(payload: dict[str, Any], paths: tuple[tuple[str, ...], ...]) -> tuple[str | None, str | None]:
    for path in paths:
        status = normalize_status(nested_value(payload, path))
        if status:
            return status, ".".join(path)
    return None, None


def scorecard_status(scorecard_path: Path) -> tuple[str | None, str | None]:
    payload = read_json(scorecard_path)
    if payload is None:
        return None, None
    return first_status(
        payload,
        (
            ("audit_status",),
            ("audit_run_status",),
            ("audit_completion_status",),
            ("metadata", "audit_status"),
            ("metadata", "audit_run_status"),
            ("meta", "audit_status"),
            ("meta", "audit_run_status"),
            ("audit", "status"),
            ("audit_run", "status"),
            ("receipt", "status"),
        ),
    )


def receipt_status(audit_dir: Path) -> tuple[Path | None, dict[str, Any] | None, str | None, str | None]:
    for name in RECEIPT_NAMES:
        path = audit_dir / name
        payload = read_json(path)
        if payload is None:
            continue
        status, source = first_status(
            payload,
            (
                ("status",),
                ("audit_status",),
                ("audit_run_status",),
                ("completion_status",),
                ("run_status",),
                ("overall_status",),
                ("audit", "status"),
                ("audit_run", "status"),
                ("audit_run_receipt", "status"),
                ("receipt", "status"),
                ("summary", "status"),
                ("meta", "audit_status"),
                ("metadata", "audit_status"),
            ),
        )
        return path, payload, status, source
    return None, None, None, None


def research_output_path_valid(output_dir: Path) -> bool:
    parts = [part.lower() for part in output_dir.parts]
    for index, part in enumerate(parts):
        if part == "research-mode" and RESEARCH_MODE in parts[index + 1 :]:
            return True
    return False


def blocker(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


def evaluate_admission(audit_dir: Path, output_dir: Path, research_mode: str) -> dict[str, Any]:
    scorecard_path = audit_dir / "SCORECARD.json"
    report_path = audit_dir / "AUDIT_REPORT.md"
    receipt_path, receipt_payload, status, status_source = receipt_status(audit_dir)
    scorecard_fallback_status, scorecard_status_source = scorecard_status(scorecard_path)

    receipt_present = receipt_path is not None
    normalized_status = status if receipt_present else scorecard_fallback_status
    receipt_status_missing = receipt_present and status is None
    scorecard_present = scorecard_path.is_file()
    report_present = report_path.is_file()
    mode = research_mode.strip()
    research_path_ok = research_output_path_valid(output_dir) if mode else None

    block: dict[str, str] | None = None
    admission_status = "blocked"
    normal_readiness_claim = False

    if not scorecard_present:
        block = blocker("missing_scorecard", f"SCORECARD.json not found in {audit_dir}")
    elif mode and mode != RESEARCH_MODE:
        block = blocker(
            "unsupported_research_mode",
            f"Unsupported REPO_OPTIMIZER_RESEARCH_MODE={mode}; only {RESEARCH_MODE} is allowed.",
        )
    elif mode == RESEARCH_MODE and not research_path_ok:
        block = blocker(
            "invalid_research_output_path",
            "Research-mode output path must include research-mode/partial-audit-calibration/.",
        )
    elif mode == RESEARCH_MODE and receipt_status_missing:
        block = blocker(
            "malformed_audit_receipt",
            "Audit receipt is present but has no parseable status.",
        )
    elif mode == RESEARCH_MODE and not receipt_present and not scorecard_fallback_status:
        block = blocker(
            "research_mode_missing_audit_status",
            "Research mode requires an audit receipt or scorecard audit status to preserve calibration evidence.",
        )
    elif mode == RESEARCH_MODE and normalized_status == "completed" and report_present:
        block = blocker(
            "research_mode_requires_incomplete_audit",
            "Partial-audit calibration mode only admits incomplete audit shapes.",
        )
    elif mode == RESEARCH_MODE:
        admission_status = "research_admitted"
    elif not receipt_present:
        block = blocker("missing_audit_receipt", "Normal optimizer runs require a completed audit receipt.")
    elif receipt_status_missing:
        block = blocker(
            "malformed_audit_receipt",
            "Normal optimizer runs require a receipt-derived audit status.",
        )
    elif normalized_status != "completed":
        block = blocker(
            f"audit_status_{normalized_status or 'unknown'}",
            f"Normal optimizer runs require audit status completed; got {normalized_status or 'unknown'}.",
        )
    elif not report_present:
        block = blocker(
            "completed_receipt_missing_report",
            "Completed audit receipt is not admissible without AUDIT_REPORT.md.",
        )
    else:
        admission_status = "admitted"
        normal_readiness_claim = True

    if block is not None:
        admission_status = "blocked"

    source = {
        "receipt_file": str(receipt_path) if receipt_path else None,
        "receipt_status_path": status_source,
        "scorecard_status_path": scorecard_status_source,
        "receipt_payload_present": receipt_payload is not None,
    }
    return {
        "schema_version": "1.0.0",
        "artifact": "AUDIT_ADMISSION_RECEIPT",
        "timestamp": utc_now(),
        "audit_dir": str(audit_dir),
        "scorecard_path": str(scorecard_path),
        "scorecard_present": scorecard_present,
        "audit_report_path": str(report_path),
        "audit_report_present": report_present,
        "receipt_present": receipt_present,
        "receipt_path": str(receipt_path) if receipt_path else None,
        "receipt_status": normalized_status or ("missing" if not receipt_present else "unknown"),
        "admission_status": admission_status,
        "normal_readiness_claim": normal_readiness_claim,
        "research_mode": mode or None,
        "research_output_path_valid": research_path_ok,
        "blocker": block,
        "source": source,
        "bounded_non_claims": [
            "Blocked or research-admitted audits are not normal optimizer readiness claims.",
            "Research mode preserves calibration evidence only; it does not certify target quality.",
        ],
    }


def stable_fingerprint(payload: dict[str, Any]) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return f"sha256:{digest}"


def phase_stub(phase: str, status: str, receipt_class: str, artifact_path: Path, raw_path: Path, note: str) -> dict[str, Any]:
    notes = [note] if note else []
    evidence = {
        "status": status,
        "receipt_class": receipt_class,
        "artifact_exists": False,
        "artifact_startable": False,
        "phase_completed": False,
        "artifact_source": "none",
        "copilot_exit_code": 0,
        "command_blocked_detected": False,
        "assistant_message_count": 0,
        "assistant_message_nonempty_count": 0,
        "assistant_messages_with_tool_requests": 0,
        "non_tool_assistant_message_count": 0,
        "assistant_message_delta_count": 0,
        "tool_execution_complete_count": 0,
        "last_event_type": "",
        "last_assistant_message_content_length": 0,
        "last_assistant_message_tool_request_count": 0,
        "note_count": len(notes),
    }
    return {
        "phase": phase,
        "status": status,
        "receipt_class": receipt_class,
        "artifact_contract": "final_non_tool_assistant_message_markdown",
        "artifact_path": str(artifact_path),
        "raw_path": str(raw_path),
        "artifact_written": False,
        "copilot_exit_code": 0,
        "command_blocked_detected": False,
        "assistant_message_count": 0,
        "assistant_message_nonempty_count": 0,
        "assistant_messages_with_tool_requests": 0,
        "non_tool_assistant_message_count": 0,
        "assistant_message_delta_count": 0,
        "last_event_type": "",
        "last_assistant_message_content_length": 0,
        "last_assistant_message_tool_request_count": 0,
        "notes": notes,
        "proof_boundary": {
            "artifact_depth": "none",
            "receipt_depth": "phase",
            "heartbeat_status": "not_applicable",
            "authority_fingerprint": stable_fingerprint(
                {
                    "phase": phase,
                    "status": status,
                    "receipt_class": receipt_class,
                    "artifact_path": str(artifact_path),
                    "raw_path": str(raw_path),
                    "notes": notes,
                }
            ),
            "phase_classification_evidence": evidence,
        },
    }


def scorecard_summary(audit_dir: Path) -> tuple[int, list[str], dict[str, dict[str, Any]]]:
    payload = read_json(audit_dir / "SCORECARD.json") or {}
    composite = payload.get("composite", 0)
    dims = payload.get("dimensions", {})
    normalized: dict[str, dict[str, Any]] = {}
    rows: list[tuple[str, int | float, int | float]] = []
    if isinstance(dims, dict):
        for name, info in dims.items():
            if isinstance(info, dict):
                score = info.get("score", 0)
                max_score = info.get("max", 20)
            else:
                score = 0
                max_score = 20
            normalized[name] = {"score": score, "max": max_score}
            rows.append((name, score, max_score))
    rows.sort(key=lambda row: row[1])
    bottom = [row[0] for row in rows[:2]]
    try:
        composite_int = int(composite)
    except (TypeError, ValueError):
        composite_int = 0
    return composite_int, bottom, normalized


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def blocked_coverage(preflight_only: str) -> dict[str, Any]:
    return {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "coverage_verdict": "blocked",
        "coverage_reason": "audit_admission_blocked_before_discovery",
        "recommendation_strength": "none",
        "expected_domains": list(EXPECTED_DISCOVERY_DOMAINS),
        "completed_domains": [],
        "missing_domains": list(EXPECTED_DISCOVERY_DOMAINS),
        "completed_count": 0,
        "missing_count": len(EXPECTED_DISCOVERY_DOMAINS),
        "expected_count": len(EXPECTED_DISCOVERY_DOMAINS),
        "coverage_ratio": 0.0,
        "domain_finding_rows": {domain: 0 for domain in EXPECTED_DISCOVERY_DOMAINS},
        "discovery_attempted": False,
        "preflight_only": preflight_only == "true",
        "critic_status": "skipped_audit_admission_blocked",
        "synthesis_status": "skipped_audit_admission_blocked",
        "patch_status": "fail_closed_audit_admission_blocked",
        "bounded_non_claims": [
            "Optimizer discovery did not run because audit admission blocked the input.",
            "Blocked optimizer outputs are not recommendation-strength claims.",
            "Coverage verdicts do not implement target-policy/P4 or P7 denominator measurement.",
        ],
    }


def write_blocked_outputs(admission_receipt: Path, output_dir: Path, repo_name: str, patch_mode: str, preflight_only: str) -> None:
    admission = json.loads(admission_receipt.read_text(encoding="utf-8"))
    audit_dir = Path(admission["audit_dir"])
    composite, bottom, dims = scorecard_summary(audit_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    coverage = blocked_coverage(preflight_only)

    preflight = {
        "target": repo_name,
        "composite": composite,
        "bottom_2": bottom,
        "bottom_dimensions": bottom,
        "all_dimensions": dims,
        "patch_mode": patch_mode == "true",
        "budget_tier": None,
        "file_count": 0,
        "discovery_scope": {
            "tier": None,
            "eligible_files": 0,
            "total_files": 0,
            "coverage_pct": 0,
            "scope_description": "blocked before optimizer discovery",
            "denominator_semantics": {
                "name": "optimizer_budgeting_denominator",
                "description": (
                    "Regular files under the target repository after excluding "
                    "path classes that are outside optimizer budgeting scope."
                ),
                "total_files_field": "file_count and discovery_scope.total_files",
                "eligible_files_field": "discovery_scope.eligible_files",
                "coverage_pct_field": "discovery_scope.coverage_pct",
            },
            "excluded_path_classes": [".git", "node_modules"],
        },
        "audit_admission": admission,
        "normal_readiness_claim": False,
    }
    if admission.get("research_mode"):
        preflight["research_mode"] = admission["research_mode"]
    write_json(output_dir / "pre-flight.json", preflight)

    plan = [
        f"# Optimization Plan: {repo_name}",
        "",
        "> Blocked before optimizer discovery by audit receipt admission.",
        f"> SCORECARD composite: {composite}/100",
        "",
        "## Audit Admission",
        "",
        f"- Status: {admission.get('admission_status')}",
        f"- Receipt status: {admission.get('receipt_status')}",
        "- Normal readiness claim: false",
    ]
    if admission.get("research_mode"):
        plan.append(f"- Research mode: {admission['research_mode']}")
    block = admission.get("blocker") or {}
    if block:
        plan.extend(["", "## Blocker", "", f"- {block.get('code')}: {block.get('message')}"])
    plan.extend(
        [
            "",
            "## Coverage Verdict",
            "",
            "- Coverage verdict: `blocked`",
            "- Recommendation strength: `none`",
            f"- Discovery coverage: 0/{coverage['expected_count']} domains completed.",
            f"- Missing domains: {', '.join(coverage['missing_domains'])}",
            "- Machine finding counts: total=0; approved=0; rejected=0; downgraded=0.",
            "",
            "### Bounded Non-Claims",
            "",
        ]
    )
    plan.extend(f"- {claim}" for claim in coverage["bounded_non_claims"])
    (output_dir / "OPTIMIZATION_PLAN.md").write_text("\n".join(plan) + "\n", encoding="utf-8")

    critic_receipt = phase_stub(
        "critic",
        "skipped_audit_admission_blocked",
        "audit_admission_blocked",
        output_dir / "critic-verdicts.md",
        output_dir / "critic-verdicts.md.jsonl",
        "Audit admission blocked before critic phase.",
    )
    synth_receipt = phase_stub(
        "synthesis",
        "skipped_audit_admission_blocked",
        "audit_admission_blocked",
        output_dir / "OPTIMIZATION_PLAN.md",
        output_dir / "OPTIMIZATION_PLAN.md.jsonl",
        "Audit admission blocked before synthesis phase.",
    )
    write_json(output_dir / "critic-phase-receipt.json", critic_receipt)
    write_json(output_dir / "synthesis-phase-receipt.json", synth_receipt)

    runtime = {
        "schema_version": "1.0.0",
        "timestamp": utc_now(),
        "patch_mode": patch_mode == "true",
        "preflight_only": preflight_only == "true",
        "command_blocked_detected": False,
        "discovery_context_file": str(output_dir / "runtime-safe-target-context.md"),
        "audit_admission": admission,
        "normal_readiness_claim": False,
        "research_mode": admission.get("research_mode"),
        "coverage_verdict": coverage["coverage_verdict"],
        "recommendation_strength": coverage["recommendation_strength"],
        "discovery_coverage": coverage,
        "bounded_non_claims": coverage["bounded_non_claims"],
        "phases": {
            "discovery": {"ok_count": 0, "fail_count": 0, "status": "skipped_audit_admission_blocked"},
            "critic": critic_receipt,
            "synthesis": synth_receipt,
            "patch_generation": {"status": "fail_closed_audit_admission_blocked", "patches_valid": 0},
        },
        "notes": ["audit admission blocked optimizer run before discovery"],
        "proof_boundary": {
            "artifact_depth": "blocked",
            "receipt_depth": "runtime",
            "heartbeat_status": "not_applicable",
            "authority_fingerprint": stable_fingerprint(
                {
                    "audit_admission": admission,
                    "patch_mode": patch_mode == "true",
                    "preflight_only": preflight_only == "true",
                }
            ),
            "phase_classification_evidence": {
                "audit_admission": {
                    "admission_status": admission.get("admission_status"),
                    "normal_readiness_claim": False,
                    "blocker": admission.get("blocker"),
                },
                "discovery": {"ok_count": 0, "fail_count": 0},
                "discovery_coverage": coverage,
                "patch_generation": {"status": "fail_closed_audit_admission_blocked", "patches_valid": 0},
            },
        },
    }
    write_json(output_dir / "RUNTIME_RECEIPTS.json", runtime)

    opt_scorecard = {
        "findings_total": 0,
        "findings_approved": 0,
        "findings_rejected": 0,
        "findings_downgraded": 0,
        "patches_generated": 0,
        "patches_valid": 0,
        "expected_delta": 0,
        "categories": {"decompose": 0, "consolidate": 0, "extract": 0, "standardize": 0},
        "audit_admission": admission,
        "normal_readiness_claim": False,
        "research_mode": admission.get("research_mode"),
        "coverage_verdict": coverage["coverage_verdict"],
        "recommendation_strength": coverage["recommendation_strength"],
        "discovery_coverage": coverage,
        "bounded_non_claims": coverage["bounded_non_claims"],
        "finding_count_agreement": {
            "source": "OPTIMIZATION_PLAN.md coverage verdict section",
            "plan_declared_counts": {"total": 0, "approved": 0, "rejected": 0, "downgraded": 0},
            "scorecard_counts": {"total": 0, "approved": 0, "rejected": 0, "downgraded": 0},
            "matches_scorecard": True,
        },
        "meta": {
            "timestamp": utc_now(),
            "optimizer_version": "1.0.0",
            "scorecard_input": str(audit_dir / "SCORECARD.json"),
            "target": repo_name,
            "status": "blocked",
            "audit_admission_status": admission.get("admission_status"),
            "normal_readiness_claim": False,
            "research_mode": admission.get("research_mode"),
            "coverage_verdict": coverage["coverage_verdict"],
            "recommendation_strength": coverage["recommendation_strength"],
            "discovery_coverage": {
                "completed_count": coverage["completed_count"],
                "expected_count": coverage["expected_count"],
                "missing_count": coverage["missing_count"],
            },
            "runtime_receipts": "RUNTIME_RECEIPTS.json",
            "command_blocked_detected": False,
        },
    }
    write_json(output_dir / "OPTIMIZATION_SCORECARD.json", opt_scorecard)

    operation_eval = {
        "score": 0,
        "max": 26,
        "verdict": "BLOCKED",
        "output_dir": str(output_dir),
        "issues": [admission.get("blocker", {}).get("message", "Audit admission blocked optimizer run.")],
        "audit_admission": admission,
        "normal_readiness_claim": False,
        "research_mode": admission.get("research_mode"),
        "coverage_verdict": coverage["coverage_verdict"],
        "recommendation_strength": coverage["recommendation_strength"],
        "discovery_coverage": coverage,
        "bounded_non_claims": coverage["bounded_non_claims"],
        "timestamp": utc_now(),
    }
    write_json(output_dir / "OPERATION_EVAL.json", operation_eval)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    evaluate = subparsers.add_parser("evaluate")
    evaluate.add_argument("--audit-dir", required=True)
    evaluate.add_argument("--output-dir", required=True)
    evaluate.add_argument("--research-mode", default="")

    blocked = subparsers.add_parser("write-blocked")
    blocked.add_argument("--admission-receipt", required=True)
    blocked.add_argument("--output-dir", required=True)
    blocked.add_argument("--repo-name", required=True)
    blocked.add_argument("--patch-mode", required=True)
    blocked.add_argument("--preflight-only", required=True)

    args = parser.parse_args()
    if args.command == "evaluate":
        payload = evaluate_admission(Path(args.audit_dir), Path(args.output_dir), args.research_mode)
        print(json.dumps(payload, indent=2))
        return 0 if payload["admission_status"] in {"admitted", "research_admitted"} else 2

    write_blocked_outputs(
        Path(args.admission_receipt),
        Path(args.output_dir),
        args.repo_name,
        args.patch_mode,
        args.preflight_only,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

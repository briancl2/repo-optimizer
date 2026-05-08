#!/usr/bin/env python3
"""Apply additive discovery-coverage verdicts to optimizer outputs."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DOMAINS = (
    ("decomposition", "decomposition.md", "decompose"),
    ("consolidation", "consolidation.md", "consolidate"),
    ("extraction", "extraction.md", "extract"),
    ("standardization", "standardization.md", "standardize"),
)
START_MARKER = "<!-- repo-optimizer:coverage-verdict:start -->"
END_MARKER = "<!-- repo-optimizer:coverage-verdict:end -->"
COUNT_RE = re.compile(
    r"Machine finding counts:\s*total=(?P<total>\d+);\s*"
    r"approved=(?P<approved>\d+);\s*"
    r"rejected=(?P<rejected>\d+);\s*"
    r"downgraded=(?P<downgraded>\d+)",
    re.IGNORECASE,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        return {}
    return payload if isinstance(payload, dict) else {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def as_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes"}


def table_rows(path: Path) -> int:
    if not path.is_file():
        return 0
    count = 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [cell.strip().lower() for cell in stripped.strip("|").split("|")]
        if all(re.fullmatch(r"[:\-\s]+", cell or "-") for cell in cells):
            continue
        if len({"rank", "severity", "finding", "file"} & set(cells)) >= 2:
            continue
        count += 1
    return count


def payload_materialized(path: Path) -> bool:
    try:
        return path.is_file() and path.stat().st_size > 0
    except OSError:
        return False


def non_claims(verdict: str, missing_domains: list[str]) -> list[str]:
    claims = [
        "Coverage verdicts are discovery-coverage metadata, not target-policy/P4 decisions.",
        "Coverage verdicts do not implement P7 denominator measurement.",
    ]
    if verdict != "complete":
        claims.insert(
            0,
            "Complete discovery coverage was not observed; recommendations are bounded to completed domains.",
        )
    if missing_domains:
        claims.insert(
            1,
            "Missing discovery domains may contain higher-priority opportunities not represented in the plan.",
        )
    return claims


def compute_coverage(output_dir: Path, args: argparse.Namespace, scorecard: dict[str, Any]) -> dict[str, Any]:
    payload_dir = output_dir / "payloads"
    expected_domains = [domain for domain, _, _ in DOMAINS]
    completed_domains: list[str] = []
    domain_rows: dict[str, int] = {}
    categories = scorecard.setdefault("categories", {})

    for domain, filename, category in DOMAINS:
        path = payload_dir / filename
        rows = table_rows(path)
        domain_rows[domain] = rows
        categories.setdefault(category, rows)
        if payload_materialized(path):
            completed_domains.append(domain)

    missing_domains = [domain for domain in expected_domains if domain not in completed_domains]
    completed_count = len(completed_domains)
    expected_count = len(expected_domains)
    preflight_only = as_bool(args.preflight_only)
    discovery_attempted = int(args.discovery_ok) + int(args.discovery_fail) > 0
    critic_completed = args.critic_status == "completed"
    synthesis_completed = args.synthesis_status == "completed"

    if preflight_only:
        verdict = "partial"
        reason = "preflight_only_discovery_skipped"
    elif completed_count == 0:
        verdict = "blocked"
        reason = "no_discovery_domains_completed"
    elif missing_domains and critic_completed and synthesis_completed:
        verdict = "pass_with_coverage_gap"
        reason = "plan_materialized_with_missing_discovery_domains"
    elif missing_domains:
        verdict = "partial"
        reason = "missing_discovery_domains"
    elif critic_completed and synthesis_completed:
        verdict = "complete"
        reason = "all_discovery_domains_completed"
    else:
        verdict = "partial"
        reason = "downstream_phase_incomplete"

    strength = {
        "complete": "strong",
        "pass_with_coverage_gap": "limited",
        "partial": "diagnostic",
        "blocked": "none",
    }[verdict]

    return {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "coverage_verdict": verdict,
        "coverage_reason": reason,
        "recommendation_strength": strength,
        "expected_domains": expected_domains,
        "completed_domains": completed_domains,
        "missing_domains": missing_domains,
        "completed_count": completed_count,
        "missing_count": len(missing_domains),
        "expected_count": expected_count,
        "coverage_ratio": round(completed_count / expected_count, 3) if expected_count else 0,
        "domain_finding_rows": domain_rows,
        "discovery_attempted": discovery_attempted,
        "preflight_only": preflight_only,
        "critic_status": args.critic_status,
        "synthesis_status": args.synthesis_status,
        "patch_status": args.patch_status,
        "bounded_non_claims": non_claims(verdict, missing_domains),
    }


def scorecard_counts(scorecard: dict[str, Any]) -> dict[str, int]:
    return {
        "total": int(scorecard.get("findings_total", 0) or 0),
        "approved": int(scorecard.get("findings_approved", 0) or 0),
        "rejected": int(scorecard.get("findings_rejected", 0) or 0),
        "downgraded": int(scorecard.get("findings_downgraded", 0) or 0),
    }


def format_list(values: list[str]) -> str:
    return ", ".join(values) if values else "none"


def coverage_section(coverage: dict[str, Any], counts: dict[str, int]) -> str:
    lines = [
        START_MARKER,
        "## Coverage Verdict",
        "",
        f"- Coverage verdict: `{coverage['coverage_verdict']}`",
        f"- Recommendation strength: `{coverage['recommendation_strength']}`",
        (
            f"- Discovery coverage: {coverage['completed_count']}/"
            f"{coverage['expected_count']} domains completed."
        ),
        f"- Completed domains: {format_list(coverage['completed_domains'])}",
        f"- Missing domains: {format_list(coverage['missing_domains'])}",
        (
            "- Machine finding counts: "
            f"total={counts['total']}; approved={counts['approved']}; "
            f"rejected={counts['rejected']}; downgraded={counts['downgraded']}."
        ),
        "- Count agreement source: deterministic coverage section in this plan.",
        "",
        "### Bounded Non-Claims",
        "",
    ]
    lines.extend(f"- {claim}" for claim in coverage["bounded_non_claims"])
    lines.append(END_MARKER)
    return "\n".join(lines) + "\n"


def replace_marked_section(text: str, section: str) -> str:
    if START_MARKER in text and END_MARKER in text:
        pattern = re.compile(re.escape(START_MARKER) + r".*?" + re.escape(END_MARKER) + r"\n?", re.S)
        return pattern.sub(section, text)
    stripped = text.rstrip()
    return f"{stripped}\n\n{section}" if stripped else section


def parse_plan_counts(plan_path: Path) -> dict[str, int] | None:
    if not plan_path.is_file():
        return None
    text = plan_path.read_text(encoding="utf-8", errors="replace")
    if START_MARKER in text and END_MARKER in text:
        start = text.rfind(START_MARKER)
        end = text.find(END_MARKER, start)
        if end != -1:
            text = text[start : end + len(END_MARKER)]
    matches = list(COUNT_RE.finditer(text))
    if not matches:
        return None
    match = matches[-1]
    return {key: int(value) for key, value in match.groupdict().items()}


def count_agreement(plan_path: Path, counts: dict[str, int]) -> dict[str, Any]:
    declared = parse_plan_counts(plan_path)
    return {
        "source": "OPTIMIZATION_PLAN.md coverage verdict section",
        "plan_declared_counts": declared,
        "scorecard_counts": counts,
        "matches_scorecard": declared == counts,
    }


def apply_coverage(output_dir: Path, args: argparse.Namespace) -> int:
    scorecard_path = output_dir / "OPTIMIZATION_SCORECARD.json"
    runtime_path = output_dir / "RUNTIME_RECEIPTS.json"
    plan_path = output_dir / "OPTIMIZATION_PLAN.md"
    scorecard = load_json(scorecard_path)
    runtime = load_json(runtime_path)
    if not scorecard:
        raise SystemExit(f"missing or invalid scorecard: {scorecard_path}")

    coverage = compute_coverage(output_dir, args, scorecard)
    counts = scorecard_counts(scorecard)
    if plan_path.is_file():
        plan_text = plan_path.read_text(encoding="utf-8", errors="replace")
        plan_path.write_text(replace_marked_section(plan_text, coverage_section(coverage, counts)), encoding="utf-8")

    agreement = count_agreement(plan_path, counts)
    scorecard["coverage_verdict"] = coverage["coverage_verdict"]
    scorecard["recommendation_strength"] = coverage["recommendation_strength"]
    scorecard["discovery_coverage"] = coverage
    scorecard["finding_count_agreement"] = agreement
    scorecard["bounded_non_claims"] = coverage["bounded_non_claims"]
    scorecard.setdefault("meta", {})
    scorecard["meta"]["coverage_verdict"] = coverage["coverage_verdict"]
    scorecard["meta"]["recommendation_strength"] = coverage["recommendation_strength"]
    scorecard["meta"]["discovery_coverage"] = {
        "completed_count": coverage["completed_count"],
        "expected_count": coverage["expected_count"],
        "missing_count": coverage["missing_count"],
    }
    write_json(scorecard_path, scorecard)

    if runtime:
        runtime["coverage_verdict"] = coverage["coverage_verdict"]
        runtime["recommendation_strength"] = coverage["recommendation_strength"]
        runtime["discovery_coverage"] = coverage
        runtime["bounded_non_claims"] = coverage["bounded_non_claims"]
        proof = runtime.setdefault("proof_boundary", {})
        evidence = proof.setdefault("phase_classification_evidence", {})
        evidence["discovery_coverage"] = coverage
        write_json(runtime_path, runtime)

    if plan_path.is_file() and not agreement["matches_scorecard"]:
        raise SystemExit("plan and scorecard finding counts diverge")
    return 0


def check_counts(output_dir: Path) -> int:
    scorecard = load_json(output_dir / "OPTIMIZATION_SCORECARD.json")
    counts = scorecard_counts(scorecard)
    agreement = count_agreement(output_dir / "OPTIMIZATION_PLAN.md", counts)
    if agreement["matches_scorecard"]:
        print(json.dumps(agreement, indent=2))
        return 0
    print(json.dumps(agreement, indent=2))
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--output-dir", required=True)
    apply_parser.add_argument("--preflight-only", required=True)
    apply_parser.add_argument("--discovery-ok", required=True, type=int)
    apply_parser.add_argument("--discovery-fail", required=True, type=int)
    apply_parser.add_argument("--critic-status", required=True)
    apply_parser.add_argument("--synthesis-status", required=True)
    apply_parser.add_argument("--patch-status", required=True)

    check_parser = subparsers.add_parser("check-counts")
    check_parser.add_argument("--output-dir", required=True)

    args = parser.parse_args()
    if args.command == "apply":
        return apply_coverage(Path(args.output_dir), args)
    return check_counts(Path(args.output_dir))


if __name__ == "__main__":
    raise SystemExit(main())

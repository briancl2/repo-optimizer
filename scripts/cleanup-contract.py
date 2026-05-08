#!/usr/bin/env python3
"""Apply additive P5 cleanup-ledger metadata to optimizer outputs."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


START_MARKER = "<!-- repo-optimizer:cleanup-contract:start -->"
END_MARKER = "<!-- repo-optimizer:cleanup-contract:end -->"
ACTION_CLASSES = {
    "fix",
    "compress",
    "delete",
    "archive",
    "keep",
    "defer",
    "needs_authorization",
    "unclassified_requires_amendment",
}
SCOPES = {
    "single_file",
    "directory",
    "generated_artifact",
    "archive_surface",
    "customer_or_private_surface",
    "unknown",
}
OWNER_CLASSES = {
    "target_owned",
    "target_policy_owned",
    "archive_or_historical",
    "customer_or_private",
    "generated_or_cache",
    "third_party_or_vendor",
    "unknown",
}
AUTHORIZATION_STATUSES = {
    "not_required",
    "explicit_authorized",
    "required_missing",
    "policy_forbidden",
    "blocked_unknown",
}
EVIDENCE_THRESHOLDS = {
    "literal_reference",
    "reachable_by_command",
    "unreferenced_with_keep_set",
    "policy_conflict",
    "insufficient",
}
DESTRUCTIVE_ACTIONS = {"delete", "archive", "compress"}
UNSAFE_AUTH = {"required_missing", "policy_forbidden", "blocked_unknown"}
UNSAFE_EVIDENCE = {"policy_conflict", "insufficient"}
PATH_RE = re.compile(r"`([^`]+)`")
PATCH_HEADER_RE = re.compile(r"^diff --git a/(.*?) b/(.*?)$", re.M)
NONE_VALUES = {"", "none", "null", "n/a", "na", "missing"}
PATCH_CLEANUP_TOKENS = (
    "cleanup",
    "clean up",
    "delete",
    "remove",
    "prune",
    "archive",
    "compress",
    "consolidate",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError):
        return {}


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def enum_from_text(text: str, allowed: set[str], default: str) -> str:
    lowered = text.lower()
    for value in sorted(allowed, key=len, reverse=True):
        if value in lowered:
            return value
    return default


def action_from_text(text: str) -> str:
    lowered = text.lower()
    if "unclassified_requires_amendment" in lowered or "unclassified" in lowered:
        return "unclassified_requires_amendment"
    if "needs_authorization" in lowered or "needs authorization" in lowered:
        return "needs_authorization"
    if any(word in lowered for word in ("delete", "remove", "prune", "unlink")):
        return "delete"
    if "archive" in lowered:
        return "archive"
    if any(word in lowered for word in ("compress", "collapse", "consolidate")):
        return "compress"
    if "keep" in lowered:
        return "keep"
    if any(word in lowered for word in ("defer", "diagnostic", "blocked")):
        return "defer"
    if any(word in lowered for word in ("cleanup", "clean up", "fix")):
        return "fix"
    return "unclassified_requires_amendment"


def scope_from_text(text: str) -> str:
    lowered = text.lower()
    if "customer_or_private_surface" in lowered or "private" in lowered or "customer" in lowered:
        return "customer_or_private_surface"
    if "archive_surface" in lowered or "historical" in lowered:
        return "archive_surface"
    if "generated_artifact" in lowered or "generated" in lowered or "cache" in lowered:
        return "generated_artifact"
    if "directory" in lowered or "/" in lowered:
        return "directory"
    if "single_file" in lowered or "." in lowered:
        return "single_file"
    return "unknown"


def extract_paths(text: str) -> list[str]:
    paths: list[str] = []
    for candidate in PATH_RE.findall(text):
        if "/" in candidate or "." in candidate:
            paths.append(candidate)
    return sorted(dict.fromkeys(paths))


def is_absent_value(value: Any) -> bool:
    if value is None:
        return True
    normalized = str(value).strip().strip(".").lower()
    return normalized in NONE_VALUES


def cleanup_metadata_from_text(text: str) -> dict[str, str]:
    marker = "cleanup metadata:"
    lowered = text.lower()
    marker_index = lowered.find(marker)
    if marker_index < 0:
        return {}
    metadata_text = text[marker_index + len(marker) :].strip()
    fields: dict[str, str] = {}
    for part in metadata_text.split(";"):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        normalized_key = key.strip().lower()
        if normalized_key:
            fields[normalized_key] = value.strip()
    return fields


def list_from_metadata(value: Any) -> list[str]:
    if is_absent_value(value):
        return []
    values: list[str] = []
    for part in str(value).split(","):
        cleaned = part.strip().strip("`")
        if cleaned and not is_absent_value(cleaned):
            values.append(cleaned)
    return values


def evidence_list_from_metadata(value: Any) -> list[str]:
    if is_absent_value(value):
        return []
    return [str(value).strip()]


def evidence_value_from_metadata(value: Any) -> Any:
    if is_absent_value(value):
        return None
    return str(value).strip()


def has_evidence(text: str, *needles: str) -> bool:
    lowered = text.lower()
    return any(needle in lowered for needle in needles)


def bool_from_value(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes"}:
            return True
        if lowered in {"0", "false", "no"}:
            return False
    return bool(value)


def not_required_authorization_supported(scope: str, owner_boundary_class: str) -> bool:
    return scope == "generated_artifact" or owner_boundary_class == "generated_or_cache"


def load_structured_findings(output_dir: Path) -> list[dict[str, Any]]:
    payload = load_json(output_dir / "CLEANUP_FINDINGS.json")
    if not isinstance(payload, list):
        return []
    findings: list[dict[str, Any]] = []
    for index, item in enumerate(payload, start=1):
        if isinstance(item, dict):
            normalized = normalize_finding(item, f"structured-{index}")
            findings.append(normalized)
    return findings


def remove_generated_cleanup_section(text: str) -> str:
    if START_MARKER not in text or END_MARKER not in text:
        return text
    pattern = re.compile(re.escape(START_MARKER) + r".*?" + re.escape(END_MARKER), re.S)
    return pattern.sub("", text)


def candidate_lines(output_dir: Path) -> list[tuple[str, str]]:
    candidates: list[tuple[str, str]] = []
    for path in (output_dir / "critic-verdicts.md", output_dir / "OPTIMIZATION_PLAN.md"):
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if path.name == "OPTIMIZATION_PLAN.md":
            text = remove_generated_cleanup_section(text)
        for line in text.splitlines():
            lowered = line.lower()
            if any(
                token in lowered
                for token in (
                    "cleanup",
                    "clean up",
                    "delete",
                    "remove",
                    "archive",
                    "compress",
                    "keep_set",
                    "owner_boundary",
                    "authorization_status",
                    "evidence_threshold",
                )
            ):
                candidates.append((path.name, line.strip()))
    return candidates


def patch_pack_candidates(output_dir: Path) -> list[tuple[str, str]]:
    patch_dir = output_dir / "PATCH_PACK"
    if not patch_dir.is_dir():
        return []
    candidates: list[tuple[str, str]] = []
    for patch_path in sorted(patch_dir.glob("*.patch")):
        text = patch_path.read_text(encoding="utf-8", errors="replace")
        lowered = text.lower()
        is_file_delete = "deleted file mode" in lowered
        is_rename = "rename from " in lowered or "rename to " in lowered
        has_cleanup_signal = any(token in lowered for token in PATCH_CLEANUP_TOKENS)
        if not (is_file_delete or is_rename or has_cleanup_signal):
            continue
        action_class = action_from_text(text)
        if is_file_delete:
            action_class = "delete"
        elif is_rename and action_class == "unclassified_requires_amendment":
            action_class = "archive"
        paths = [new_path for _, new_path in PATCH_HEADER_RE.findall(text)] or [patch_path.name]
        for target_path in paths:
            candidates.append(
                (
                    f"PATCH_PACK/{patch_path.name}",
                    (
                        f"Patch requires cleanup contract review for `{target_path}`; "
                        f"cleanup_action_class={action_class}; "
                        "cleanup_action_scope=single_file; destructive_action=true; "
                        "target_paths="
                        f"{target_path}; protected_keep_paths=none; keep_set_evidence=none; "
                        "owner_boundary_class=unknown; owner_boundary_evidence=none; "
                        "authorization_status=blocked_unknown; evidence_threshold=insufficient."
                    ),
                )
            )
    return candidates


def all_patch_paths(output_dir: Path) -> set[str]:
    patch_dir = output_dir / "PATCH_PACK"
    if not patch_dir.is_dir():
        return set()
    paths: set[str] = set()
    for patch_path in sorted(patch_dir.glob("*.patch")):
        text = patch_path.read_text(encoding="utf-8", errors="replace")
        matches = PATCH_HEADER_RE.findall(text)
        if matches:
            paths.update(new_path for _, new_path in matches)
        else:
            paths.add(patch_path.name)
    return paths


def normalize_finding(item: dict[str, Any], finding_id: str) -> dict[str, Any]:
    source_text = str(item.get("source_text") or item.get("finding") or item.get("text") or "")
    metadata = cleanup_metadata_from_text(source_text)
    action_class = str(
        item.get("cleanup_action_class")
        or metadata.get("cleanup_action_class")
        or action_from_text(source_text)
    )
    if action_class not in ACTION_CLASSES:
        action_class = "unclassified_requires_amendment"
    scope = str(item.get("cleanup_action_scope") or metadata.get("cleanup_action_scope") or scope_from_text(source_text))
    if scope not in SCOPES:
        scope = "unknown"
    target_paths = item.get("target_paths")
    if not isinstance(target_paths, list):
        target_paths = (
            list_from_metadata(metadata["target_paths"])
            if "target_paths" in metadata
            else extract_paths(source_text)
        )
    protected_keep_paths = item.get("protected_keep_paths")
    if not isinstance(protected_keep_paths, list):
        if "protected_keep_paths" in metadata:
            protected_keep_paths = list_from_metadata(metadata["protected_keep_paths"])
        else:
            protected_keep_paths = target_paths if has_evidence(source_text, "protected_keep_paths") else []
    keep_set_evidence = item.get("keep_set_evidence")
    if not isinstance(keep_set_evidence, list):
        if "keep_set_evidence" in metadata:
            keep_set_evidence = evidence_list_from_metadata(metadata["keep_set_evidence"])
        else:
            keep_set_evidence = ["present"] if has_evidence(source_text, "keep_set_evidence") else []
    owner_boundary_class = str(
        item.get("owner_boundary_class")
        or metadata.get("owner_boundary_class")
        or enum_from_text(source_text, OWNER_CLASSES, "unknown")
    )
    if owner_boundary_class not in OWNER_CLASSES:
        owner_boundary_class = "unknown"
    owner_boundary_evidence = item.get("owner_boundary_evidence")
    if owner_boundary_evidence is None and "owner_boundary_evidence" in metadata:
        owner_boundary_evidence = evidence_value_from_metadata(metadata["owner_boundary_evidence"])
    owner_boundary_evidence_present = bool(owner_boundary_evidence)
    if owner_boundary_evidence is None and "owner_boundary_evidence" not in metadata:
        owner_boundary_evidence_present = has_evidence(
            source_text, "owner_boundary_evidence", "owner boundary evidence"
        )
    authorization_status = str(
        item.get("authorization_status")
        or metadata.get("authorization_status")
        or enum_from_text(source_text, AUTHORIZATION_STATUSES, "blocked_unknown")
    )
    if authorization_status not in AUTHORIZATION_STATUSES:
        authorization_status = "blocked_unknown"
    evidence_threshold = str(
        item.get("evidence_threshold")
        or metadata.get("evidence_threshold")
        or enum_from_text(source_text, EVIDENCE_THRESHOLDS, "insufficient")
    )
    if evidence_threshold not in EVIDENCE_THRESHOLDS:
        evidence_threshold = "insufficient"
    destructive_action = bool_from_value(
        item.get("destructive_action", metadata.get("destructive_action")),
        action_class in DESTRUCTIVE_ACTIONS,
    )
    destructive_action_reason = item.get("destructive_action_reason")
    if destructive_action and not destructive_action_reason:
        destructive_action_reason = f"cleanup_action_class={action_class}"

    block_reasons: list[str] = []
    if action_class == "unclassified_requires_amendment":
        block_reasons.append("unclassified_requires_amendment")
    if destructive_action:
        if not target_paths:
            block_reasons.append("missing_target_paths")
        if owner_boundary_class == "unknown" or not owner_boundary_evidence_present:
            block_reasons.append("missing_owner_boundary")
        if not keep_set_evidence:
            block_reasons.append("missing_keep_set")
        if authorization_status in UNSAFE_AUTH:
            block_reasons.append(f"authorization_{authorization_status}")
        if authorization_status == "not_required" and not not_required_authorization_supported(
            scope, owner_boundary_class
        ):
            block_reasons.append("authorization_not_required_without_generated_cache_boundary")
        if evidence_threshold in UNSAFE_EVIDENCE:
            block_reasons.append(f"evidence_{evidence_threshold}")

    patch_allowed = not block_reasons
    return {
        "id": finding_id,
        "source": item.get("source", "optimizer-output"),
        "cleanup_action_class": action_class,
        "cleanup_action_scope": scope,
        "destructive_action": destructive_action,
        "destructive_action_reason": destructive_action_reason,
        "target_paths": target_paths,
        "protected_keep_paths": protected_keep_paths,
        "keep_set_evidence": keep_set_evidence,
        "owner_boundary_class": owner_boundary_class,
        "owner_boundary_evidence": owner_boundary_evidence or None,
        "authorization_status": authorization_status,
        "evidence_threshold": evidence_threshold,
        "cleanup_safety_non_claims": [
            "Cleanup-safety metadata does not authorize target mutation.",
            "repo-optimizer recommends only; patch output remains gated by validation.",
        ],
        "patch_allowed": patch_allowed,
        "block_reasons": block_reasons,
        "source_text": source_text,
    }


def finding_target_path_set(finding: dict[str, Any]) -> set[str]:
    target_paths = finding.get("target_paths")
    if not isinstance(target_paths, list):
        return set()
    return {str(path) for path in target_paths if str(path)}


def dedupe_findings(findings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, str]] = set()
    deduped: list[dict[str, Any]] = []
    for finding in findings:
        key = (str(finding.get("source", "")), str(finding.get("source_text", "")))
        if key in seen:
            continue
        seen.add(key)
        finding["id"] = f"cleanup-{len(deduped) + 1}"
        deduped.append(finding)
    return deduped


def finding_overlaps_patch(finding: dict[str, Any], patch_paths: set[str]) -> bool:
    if str(finding.get("source", "")).startswith("PATCH_PACK/"):
        return True
    target_paths = finding_target_path_set(finding)
    return bool(target_paths and target_paths.intersection(patch_paths))


def discover_findings(output_dir: Path) -> list[dict[str, Any]]:
    findings = load_structured_findings(output_dir)
    findings.extend(
        normalize_finding({"source": source, "source_text": text}, f"cleanup-{index}")
        for index, (source, text) in enumerate(candidate_lines(output_dir), start=1)
    )

    destructive_paths = {
        target_path
        for finding in findings
        if finding["destructive_action"]
        for target_path in finding_target_path_set(finding)
    }
    patch_findings = [
        normalize_finding({"source": source, "source_text": text}, f"patch-{index}")
        for index, (source, text) in enumerate(patch_pack_candidates(output_dir), start=1)
    ]
    for patch_finding in patch_findings:
        patch_paths = finding_target_path_set(patch_finding)
        if patch_paths and patch_paths.issubset(destructive_paths):
            continue
        findings.append(patch_finding)
        destructive_paths.update(patch_paths)
    return dedupe_findings(findings)


def build_contract(output_dir: Path) -> dict[str, Any]:
    findings = discover_findings(output_dir)
    destructive = [finding for finding in findings if finding["destructive_action"]]
    blocked = [finding for finding in destructive if not finding["patch_allowed"]]
    authorized = [finding for finding in destructive if finding["patch_allowed"]]
    patch_paths = all_patch_paths(output_dir)
    patch_blocking = [finding for finding in blocked if finding_overlaps_patch(finding, patch_paths)]
    contract = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "findings_with_cleanup_class": len(findings),
        "destructive_findings_total": len(destructive),
        "destructive_findings_blocked": len(blocked),
        "destructive_findings_authorized": len(authorized),
        "missing_owner_boundary_count": sum(
            1 for finding in destructive if "missing_owner_boundary" in finding["block_reasons"]
        ),
        "missing_keep_set_count": sum(
            1 for finding in destructive if "missing_keep_set" in finding["block_reasons"]
        ),
        "authorization_required_missing_count": sum(
            1
            for finding in destructive
            if any(reason.startswith("authorization_") for reason in finding["block_reasons"])
        ),
        "unclassified_requires_amendment_count": sum(
            1 for finding in findings if finding["cleanup_action_class"] == "unclassified_requires_amendment"
        ),
        "patch_generation_blocked": bool(patch_blocking),
        "patch_blocked_findings": [finding["id"] for finding in patch_blocking],
        "bounded_non_claims": [
            "Cleanup contract metadata does not prove optimizer quality improved.",
            "Cleanup contract metadata does not authorize target cleanup.",
            "Absent or partial auditor inventory maps to insufficient evidence, not authorization.",
            "Patch mode must fail closed for unsafe destructive cleanup recommendations.",
        ],
        "findings": findings,
    }
    return contract


def cleanup_section(contract: dict[str, Any]) -> str:
    return "\n".join(
        [
            START_MARKER,
            "## Cleanup Safety Summary",
            "",
            f"- Cleanup-classified findings: {contract['findings_with_cleanup_class']}",
            f"- Destructive findings: {contract['destructive_findings_total']}",
            f"- Destructive findings blocked: {contract['destructive_findings_blocked']}",
            f"- Destructive findings authorized for patch consideration: {contract['destructive_findings_authorized']}",
            f"- Missing owner-boundary evidence: {contract['missing_owner_boundary_count']}",
            f"- Missing keep-set evidence: {contract['missing_keep_set_count']}",
            f"- Authorization missing/blocked: {contract['authorization_required_missing_count']}",
            f"- Unclassified findings requiring amendment: {contract['unclassified_requires_amendment_count']}",
            "",
            "### Bounded Non-Claims",
            "",
            *[f"- {claim}" for claim in contract["bounded_non_claims"]],
            END_MARKER,
            "",
        ]
    )


def replace_marked_section(text: str, section: str) -> str:
    if START_MARKER in text and END_MARKER in text:
        pattern = re.compile(re.escape(START_MARKER) + r".*?" + re.escape(END_MARKER) + r"\n?", re.S)
        return pattern.sub(section, text)
    stripped = text.rstrip()
    return f"{stripped}\n\n{section}" if stripped else section


def apply_contract(output_dir: Path, patch_mode: bool) -> int:
    scorecard_path = output_dir / "OPTIMIZATION_SCORECARD.json"
    runtime_path = output_dir / "RUNTIME_RECEIPTS.json"
    plan_path = output_dir / "OPTIMIZATION_PLAN.md"
    contract = build_contract(output_dir)
    write_json(output_dir / "CLEANUP_CONTRACT.json", contract)

    scorecard = load_json(scorecard_path)
    if isinstance(scorecard, dict) and scorecard:
        scorecard["cleanup_contract"] = contract
        scorecard.setdefault("meta", {})["cleanup_contract"] = {
            "findings_with_cleanup_class": contract["findings_with_cleanup_class"],
            "destructive_findings_total": contract["destructive_findings_total"],
            "destructive_findings_blocked": contract["destructive_findings_blocked"],
        }
        write_json(scorecard_path, scorecard)

    runtime = load_json(runtime_path)
    if isinstance(runtime, dict) and runtime:
        runtime["cleanup_contract"] = contract
        proof = runtime.setdefault("proof_boundary", {})
        evidence = proof.setdefault("phase_classification_evidence", {})
        evidence["cleanup_contract"] = {
            "patch_generation_blocked": contract["patch_generation_blocked"],
            "destructive_findings_blocked": contract["destructive_findings_blocked"],
        }
        write_json(runtime_path, runtime)

    if plan_path.is_file():
        plan_text = plan_path.read_text(encoding="utf-8", errors="replace")
        plan_path.write_text(replace_marked_section(plan_text, cleanup_section(contract)), encoding="utf-8")

    patch_count = len(list((output_dir / "PATCH_PACK").glob("*.patch"))) if (output_dir / "PATCH_PACK").is_dir() else 0
    if patch_mode and patch_count and contract["patch_generation_blocked"]:
        if isinstance(scorecard, dict) and scorecard:
            scorecard["cleanup_contract"] = contract
            meta = scorecard.setdefault("meta", {})
            meta["status"] = "fail-closed"
            meta["patch_status"] = "blocked_by_cleanup_contract"
            write_json(scorecard_path, scorecard)
        if isinstance(runtime, dict) and runtime:
            runtime["cleanup_contract"] = contract
            phases = runtime.setdefault("phases", {})
            patch_generation = phases.setdefault("patch_generation", {})
            patch_generation["status"] = "blocked_by_cleanup_contract"
            patch_generation["blocked_by_cleanup_contract"] = True
            proof = runtime.setdefault("proof_boundary", {})
            evidence = proof.setdefault("phase_classification_evidence", {})
            evidence["cleanup_contract"] = {
                "patch_generation_blocked": True,
                "destructive_findings_blocked": contract["destructive_findings_blocked"],
                "patch_blocked_findings": contract["patch_blocked_findings"],
            }
            write_json(runtime_path, runtime)
        receipt = {
            "schema_version": "1.0.0",
            "generated_at": utc_now(),
            "status": "blocked",
            "reason": "unsafe_destructive_cleanup_patch",
            "patch_count": patch_count,
            "patch_blocked_findings": contract["patch_blocked_findings"],
            "cleanup_contract": contract,
        }
        write_json(output_dir / "PATCH_BLOCKED_BY_CLEANUP_CONTRACT.json", receipt)
        return 2
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--output-dir", required=True)
    apply_parser.add_argument("--patch-mode", required=True)
    args = parser.parse_args()
    if args.command == "apply":
        return apply_contract(Path(args.output_dir), args.patch_mode.lower() in {"1", "true", "yes"})
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

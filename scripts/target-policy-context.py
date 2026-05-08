#!/usr/bin/env python3
"""Emit pointer-only target policy context for repo-optimizer."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any

EXCLUDE_DIRS = {".git", "node_modules", "work", "runs", "dist", "build", "__pycache__"}
ROOT_POLICY_EXTS = {".json", ".yaml", ".yml", ".md"}
POLICY_LIMIT = 40
NON_CLAIM = "listed files are for optimizer context and not fully interpreted"


def compact(value: Any, limit: int = 120) -> str:
    text = " ".join(str(value or "").replace("|", "\\|").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def markdown_cell(value: Any) -> str:
    return compact(value).replace("\n", " ")


def is_policy_pointer(rel: Path) -> bool:
    rel_text = rel.as_posix()
    lowered = rel_text.lower()
    name = rel.name.lower()
    if lowered.startswith("system/policy/"):
        return True
    if lowered.startswith(".github/") and "policy" in lowered:
        return True
    if lowered.startswith("docs/") and "policy" in lowered:
        return True
    if len(rel.parts) == 1 and "policy" in name and rel.suffix.lower() in ROOT_POLICY_EXTS:
        return True
    return False


def policy_family(rel: Path) -> str:
    lowered = rel.as_posix().lower()
    if "model" in lowered and "routing" in lowered:
        return "model_routing"
    if "allowlist" in lowered or "allowlists" in lowered:
        return "allowlist"
    if lowered.startswith("system/policy/"):
        return "system_policy"
    if lowered.startswith(".github/"):
        return "github_policy"
    if lowered.startswith("docs/"):
        return "docs_policy"
    if len(rel.parts) == 1:
        return "root_policy"
    return "target_policy"


def policy_role(rel: Path) -> str:
    lowered = rel.as_posix().lower()
    if "allowlist" in lowered or "allowlists" in lowered:
        return "target-local allowlist pointer"
    if lowered.startswith("system/policy/"):
        return "target-local policy pointer"
    if lowered.startswith(".github/"):
        return "repository platform policy pointer"
    if lowered.startswith("docs/"):
        return "documented target policy pointer"
    if len(rel.parts) == 1:
        return "root policy pointer"
    return "target policy pointer"


def summarize_json(path: Path) -> tuple[str, list[str], str]:
    payload = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    if isinstance(payload, dict):
        keys = [str(key) for key in payload.keys()][:8]
        for candidate in ("description", "title", "name", "summary"):
            if candidate in payload and isinstance(payload[candidate], (str, int, float)):
                return compact(payload[candidate]), keys, "parsed_json"
        return "", keys, "parsed_json"
    if isinstance(payload, list):
        return f"list with {len(payload)} entries", ["list_length"], "parsed_json"
    return "", [type(payload).__name__], "parsed_json"


def summarize_yaml_like(path: Path) -> tuple[str, list[str], str]:
    keys: list[str] = []
    summary = ""
    key_re = re.compile(r"^([A-Za-z0-9_.-]+):\s*(.*?)\s*$")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[:80]:
        match = key_re.match(line)
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip().strip("\"'")
        if key not in keys:
            keys.append(key)
        if key.lower() in {"description", "title", "name", "summary"} and value and not summary:
            summary = compact(value)
        if len(keys) >= 8 and summary:
            break
    return summary, keys[:8], "parsed_metadata" if keys else "no_summary"


def summarize_markdown(path: Path) -> tuple[str, list[str], str]:
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[:80]:
        stripped = line.strip()
        if stripped.startswith("#"):
            return compact(stripped.lstrip("#").strip()), ["first_heading"], "parsed_title"
    return "", [], "no_summary"


def summarize_file(path: Path) -> tuple[str, list[str], str]:
    suffix = path.suffix.lower()
    try:
        if suffix == ".json":
            return summarize_json(path)
        if suffix in {".yaml", ".yml"}:
            return summarize_yaml_like(path)
        if suffix == ".md":
            return summarize_markdown(path)
        return "", [], "not_parsed"
    except (OSError, UnicodeError):
        return "", [], "unreadable"
    except (json.JSONDecodeError, ValueError):
        return "", [], "parse_error"


def discover(repo: Path) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    for root, dirs, files in os.walk(repo):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
        for name in sorted(files):
            path = Path(root) / name
            rel = path.relative_to(repo)
            if not is_policy_pointer(rel):
                continue
            description, evidence_keys, parse_status = summarize_file(path)
            records.append(
                {
                    "path": rel.as_posix(),
                    "policy_family": policy_family(rel),
                    "policy_role": policy_role(rel),
                    "file_type": path.suffix.lower().lstrip(".") or "unknown",
                    "description_or_title": description,
                    "evidence_keys": evidence_keys,
                    "parse_status": parse_status,
                }
            )
    records.sort(key=lambda item: item["path"])
    visible_records = records[:POLICY_LIMIT]
    return {
        "schema_version": "1.0.0",
        "discovery_mode": "pointer_only",
        "policy_files_count": len(records),
        "policy_files": visible_records,
        "policy_files_omitted_count": max(0, len(records) - len(visible_records)),
        "policy_context_non_claim": NON_CLAIM,
    }


def render_markdown(context: dict[str, Any]) -> str:
    lines = [
        "",
        "## Target Policy Pointers",
        "",
        f"> Pointer-only: {context['policy_context_non_claim']}.",
        "",
        "| path | family | role | type | description_or_title | parse_status |",
        "|---|---|---|---|---|---|",
    ]
    policy_files = context.get("policy_files", [])
    if policy_files:
        for item in policy_files:
            lines.append(
                "| {path} | {family} | {role} | {file_type} | {description} | {parse_status} |".format(
                    path=markdown_cell(item.get("path")),
                    family=markdown_cell(item.get("policy_family")),
                    role=markdown_cell(item.get("policy_role")),
                    file_type=markdown_cell(item.get("file_type")),
                    description=markdown_cell(item.get("description_or_title") or "n/a"),
                    parse_status=markdown_cell(item.get("parse_status")),
                )
            )
    else:
        lines.append("| none | n/a | n/a | n/a | n/a | n/a |")
    omitted = int(context.get("policy_files_omitted_count") or 0)
    if omitted:
        lines.extend(["", f"_Omitted {omitted} additional policy pointer(s) to keep context compact._"])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    json_parser = subparsers.add_parser("json", help="write target policy context JSON")
    json_parser.add_argument("repo")
    json_parser.add_argument("output")
    markdown_parser = subparsers.add_parser("markdown", help="write target policy context markdown to stdout")
    markdown_parser.add_argument("repo")
    args = parser.parse_args()

    context = discover(Path(args.repo))
    if args.command == "json":
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(context, indent=2) + "\n", encoding="utf-8")
    elif args.command == "markdown":
        print(render_markdown(context), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

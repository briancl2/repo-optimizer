#!/usr/bin/env bash
# generate-patches.sh — Generate unified diff patches from approved findings.
#
# Usage: bash scripts/generate-patches.sh <repo_path> <findings_file> <output_dir>
#
# Reads approved findings and generates patch files in PATCH_PACK/ directory.
# Each patch is validated with git apply --check.

set -euo pipefail

REPO="${1:?Usage: generate-patches.sh <repo_path> <findings_file> <output_dir>}"
FINDINGS="${2:?Usage: generate-patches.sh <repo_path> <findings_file> <output_dir>}"
OUTPUT_DIR="${3:?Usage: generate-patches.sh <repo_path> <findings_file> <output_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$OUTPUT_DIR/PATCH_PACK"
mkdir -p "$PATCH_DIR"
find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' -delete
rm -f "$OUTPUT_DIR/PATCHABILITY_BLOCKERS.json" "$OUTPUT_DIR/PATCH_PACK_METADATA.json"

echo "=== Patch Generation ==="
echo "  Repo: $REPO"
echo "  Findings: $FINDINGS"
echo "  Output: $PATCH_DIR"
echo ""

# Validate patches exist
if [ ! -f "$FINDINGS" ]; then
    echo "ERROR: Findings file not found: $FINDINGS"
    exit 1
fi

python3 - "$REPO" "$FINDINGS" "$PATCH_DIR/P4-shell-hardening.patch" <<'PY'
from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
findings = Path(sys.argv[2])
patch_path = Path(sys.argv[3])

plan = findings.read_text(encoding="utf-8", errors="replace")

# First deterministic materializer: the retained P4/S-05/S-06/S-07 shell
# hardening patch. Other patch families remain recommendation-only until they
# get their own bounded materializer.
if not (
    re.search(r"\bS-05\b", plan)
    and re.search(r"\bS-06\b", plan)
    and re.search(r"\bS-07\b", plan)
):
    sys.exit(0)

targets = [
    "scripts/pre-commit-hook.sh",
    ".agents/skills/reviewing-code-locally/scripts/local_review.sh",
]


def harden_shell(lines: list[str]) -> list[str]:
    if not lines:
        return lines

    updated = list(lines)
    if updated[0] == "#!/bin/bash":
        updated[0] = "#!/usr/bin/env bash"

    if updated[0].startswith("#!") and "set -euo pipefail" not in updated[:5]:
        updated.insert(1, "set -euo pipefail")

    return updated


patch_parts: list[str] = []
changed_files = 0

for rel in targets:
    path = repo / rel
    if not path.exists():
        continue

    old = path.read_text(encoding="utf-8", errors="replace").splitlines()
    new = harden_shell(old)
    if old == new:
        continue

    diff = list(
        difflib.unified_diff(
            old,
            new,
            fromfile=f"a/{rel}",
            tofile=f"b/{rel}",
            lineterm="",
        )
    )
    if not diff:
        continue

    patch_parts.append(f"diff --git a/{rel} b/{rel}")
    patch_parts.extend(diff)
    changed_files += 1

if changed_files:
    patch_path.write_text("\n".join(patch_parts) + "\n", encoding="utf-8")
PY

python3 - "$REPO" "$FINDINGS" "$PATCH_DIR" <<'PY'
from __future__ import annotations

import difflib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

repo = Path(sys.argv[1])
findings = Path(sys.argv[2])
patch_dir = Path(sys.argv[3])
plan = findings.read_text(encoding="utf-8", errors="replace")
repo_root = repo.resolve()
overflow_blockers: list[dict[str, object]] = []
patch_metadata: list[dict[str, object]] = []
written_row_ids: set[str] = set()
if (patch_dir / "P4-shell-hardening.patch").exists():
    written_row_ids.add("P4")


def has_manifest_row(row_id: str) -> bool:
    return bool(re.search(rf"(?:^|[|\n\r])\s*{re.escape(row_id)}\b", plan, re.IGNORECASE))


def read_lines(path: Path) -> list[str] | None:
    if path.is_symlink():
        return None
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, OSError, RuntimeError):
        return None
    if not resolved.is_file():
        return None
    try:
        resolved.relative_to(repo_root)
    except ValueError:
        return None
    return resolved.read_text(encoding="utf-8", errors="replace").splitlines()


def record_patch_blocker(
    row_id: str,
    patch_name: str,
    code: str,
    reason: str,
    source_rows: list[dict[str, object]] | None = None,
) -> None:
    rows = source_rows or [
        {
            "row_id": row_id,
            "patch": patch_name,
            "findings": "",
            "files_touched": "",
        }
    ]
    for row in rows:
        blocker = {
            "row_id": str(row.get("row_id", row_id)),
            "patch": row.get("patch", patch_name) or patch_name,
            "findings": row.get("findings", ""),
            "files_touched": row.get("files_touched", ""),
            "blocker_code": code,
            "reason": reason,
        }
        scan_context = row.get("scan_context") if isinstance(row.get("scan_context"), dict) else None
        if scan_context:
            blocker["scan_context"] = scan_context
            claims = scan_limited_non_claim(scan_context)
            if claims:
                blocker["bounded_non_claims"] = claims
        overflow_blockers.append(blocker)


def write_patch(
    patch_path: Path,
    changes: list[tuple[str, list[str], list[str]]],
    row_id: str,
    source_rows: list[dict[str, object]] | None = None,
) -> bool:
    material_changes = [(rel, old, new) for rel, old, new in changes if old != new]
    if not material_changes:
        return False

    if len(material_changes) > 6:
        record_patch_blocker(
            row_id,
            patch_path.name,
            "patch_file_limit_exceeded",
            f"Materializer for {row_id} would touch {len(material_changes)} files, above the 6-file patch limit.",
        )
        return False

    net_lines = sum(abs(len(new) - len(old)) for _, old, new in material_changes)
    if net_lines > 160:
        record_patch_blocker(
            row_id,
            patch_path.name,
            "patch_line_limit_exceeded",
            f"Materializer for {row_id} would change {net_lines} net lines, above the 160-line patch limit.",
        )
        return False

    if len(list(patch_dir.glob("*.patch"))) >= 5:
        record_patch_blocker(
            row_id,
            patch_path.name,
            "patch_run_limit_exceeded",
            "This run already emitted the maximum 5 patch files; this row remains blocked for a later run.",
        )
        return False

    parts: list[str] = []
    for rel, old, new in material_changes:
        diff = list(
            difflib.unified_diff(
                old,
                new,
                fromfile=f"a/{rel}",
                tofile=f"b/{rel}",
                lineterm="",
            )
        )
        if not diff:
            continue
        parts.append(f"diff --git a/{rel} b/{rel}")
        parts.extend(diff)
    if parts:
        patch_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
        written_row_ids.add(row_id)
        if source_rows:
            patch_metadata.extend(patch_metadata_for_rows(patch_path.name, material_changes, source_rows))
        return True
    return False


def is_separator(cells: list[str]) -> bool:
    return all(re.fullmatch(r":?-{3,}:?", cell.strip() or "-") for cell in cells)


def is_patch_manifest_heading(text: str) -> bool:
    return bool(re.match(r"^#{1,6}\s*(?:\d+\.\s*)?Patch Manifest\b", text, re.IGNORECASE))


def extract_scan_context(text: str) -> dict[str, object] | None:
    marker = "scan_context="
    start = text.find(marker)
    if start < 0:
        return None
    brace_start = text.find("{", start + len(marker))
    if brace_start < 0:
        return None
    depth = 0
    in_string = False
    escape = False
    for idx in range(brace_start, len(text)):
        char = text[idx]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                try:
                    value = json.loads(text[brace_start : idx + 1])
                except json.JSONDecodeError:
                    return None
                return value if isinstance(value, dict) else None
    return None


def scan_limited_non_claim(scan_context: dict[str, object] | None) -> list[str]:
    if scan_context and scan_context.get("scan_limited") is True:
        return [
            "scan-limited metadata is preserved from the advisor recommendation; it does not prove repository-wide absence or presence beyond the recorded scan scope."
        ]
    return []


def manifest_rows(text: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    headers: list[str] | None = None
    in_manifest = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if is_patch_manifest_heading(stripped):
            in_manifest = True
            headers = None
            continue
        if in_manifest and stripped.startswith("## ") and not is_patch_manifest_heading(stripped):
            break
        if not in_manifest or not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) < 2 or is_separator(cells):
            continue
        if headers is None:
            headers = [cell.lower() for cell in cells]
            continue
        row_id = cells[0]
        patch_label = cells[1] if len(cells) > 1 else row_id
        findings_value = cells[2] if len(cells) > 2 and headers[1] in {"patch", "patch name"} else cells[1]
        files_touched = ""
        for idx, header in enumerate(headers):
            if "files" in header and idx < len(cells):
                files_touched = cells[idx]
                break
        rows.append(
            {
                "row_id": row_id,
                "patch": patch_label,
                "findings": findings_value,
                "files_touched": files_touched,
                "raw_row": raw,
                "scan_context": extract_scan_context(raw),
            }
        )
    return rows


def manifest_rows_for(row_id: str) -> list[dict[str, object]]:
    return [row for row in manifest_rows(plan) if str(row.get("row_id", "")) == row_id]


def patch_metadata_for_rows(
    patch_name: str,
    material_changes: list[tuple[str, list[str], list[str]]],
    source_rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    target_files = [rel for rel, _, _ in material_changes]
    metadata: list[dict[str, object]] = []
    for row in source_rows:
        scan_context = row.get("scan_context") if isinstance(row.get("scan_context"), dict) else None
        if not scan_context:
            continue
        entry: dict[str, object] = {
            "row_id": str(row.get("row_id", "unknown")),
            "patch": patch_name,
            "findings": row.get("findings", ""),
            "files_touched": row.get("files_touched", ""),
            "scan_context": scan_context,
            "target_files": target_files,
            "bounded_non_claims": scan_limited_non_claim(scan_context),
        }
        if len(target_files) == 1:
            entry["target_file"] = target_files[0]
        metadata.append(entry)
    return metadata


def blocker_for(row: dict[str, object]) -> dict[str, object]:
    row_text = " ".join(str(value) for value in row.values())
    row_id = str(row.get("row_id", "unknown"))
    special_reasons = {
        "PP-2": (
            "unsupported_semantic_refactor",
            "PP-2 requires semantic extraction/deduplication across target documentation and must remain blocked until a target owner issue names the exact keep/reference set.",
        ),
        "PP-5": (
            "unsupported_helper_plus_caller_update",
            "PP-5 requires adding a helper plus updating its callers, which is not safe as a generic patch materializer without target-owner implementation authority.",
        ),
    }
    if row_id in special_reasons:
        code, reason = special_reasons[row_id]
    else:
        supported = bool(
            row_id in {"P4", "PP-1", "PP-3", "PP-4", "WM-01", "WM-02", "WM-03", "WM-04", "HS-01", "CR-01", "HFR-01"}
            or re.search(r"\bS-05\b", row_text)
            and re.search(r"\bS-06\b", row_text)
            and re.search(r"\bS-07\b", row_text)
        )
        code = "supported_materializer_no_output" if supported else "unsupported_manifest_row"
        reason = (
            f"A deterministic materializer matched {row_id}, but the target had no apply-checkable change."
            if supported
            else f"No deterministic patch materializer is implemented for manifest row {row_id}."
        )
    blocker = {
        "row_id": row_id,
        "patch": row.get("patch", ""),
        "findings": row.get("findings", ""),
        "files_touched": row.get("files_touched", ""),
        "blocker_code": code,
        "reason": reason,
    }
    scan_context = row.get("scan_context") if isinstance(row.get("scan_context"), dict) else None
    if scan_context:
        blocker["scan_context"] = scan_context
        claims = scan_limited_non_claim(scan_context)
        if claims:
            blocker["bounded_non_claims"] = claims
    return blocker


def flush_manifest_blockers() -> None:
    rows = manifest_rows(plan)
    if "P4" in written_row_ids:
        for row in rows:
            row_text = " ".join(str(value) for value in row.values())
            if (
                re.search(r"\bS-05\b", row_text)
                and re.search(r"\bS-06\b", row_text)
                and re.search(r"\bS-07\b", row_text)
            ):
                written_row_ids.add(str(row.get("row_id", "unknown")))
    blockers = list(overflow_blockers)
    blocked_row_ids = {str(blocker.get("row_id", "")) for blocker in blockers}
    for row in rows:
        row_id = str(row.get("row_id", "unknown"))
        if row_id in written_row_ids or row_id in blocked_row_ids:
            continue
        blockers.append(blocker_for(row))
        blocked_row_ids.add(row_id)
    if not rows and not blockers:
        blockers = [
            {
                "row_id": "manifest",
                "patch": "",
                "findings": "",
                "files_touched": "",
                "blocker_code": "manifest_rows_not_found",
                "reason": "No parseable Patch Manifest table rows were found in the optimization plan.",
            }
        ]
    if not blockers:
        return
    out_path = patch_dir.parent / "PATCHABILITY_BLOCKERS.json"
    payload = {
        "schema_version": "1.0.0",
        "artifact": "PATCHABILITY_BLOCKERS",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_manifest": str(findings),
        "patch_dir": str(patch_dir),
        "patches_generated": len(list(patch_dir.glob("*.patch"))),
        "blocker_count": len(blockers),
        "blockers": blockers,
        "bounded_non_claims": [
            "This artifact records manifest rows blocked by patch-pack safety limits or unsupported materializer scope.",
            "It does not authorize target repository mutation or auto-apply behavior.",
        ],
    }
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def safe_rel_path(value: str) -> str | None:
    rel = value.strip().strip("`'\"")
    if not rel or rel.startswith("/") or rel.startswith("../") or "/../" in rel:
        return None
    return rel


def has_git_path_component(rel: str) -> bool:
    return any(part == ".git" for part in Path(rel).parts)


def dedupe_paths(values: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        deduped.append(value)
    return deduped


def manifest_row_text(row_id: str) -> str:
    in_manifest = False
    for raw in plan.splitlines():
        stripped = raw.strip()
        if is_patch_manifest_heading(stripped):
            in_manifest = True
            continue
        if in_manifest and stripped.startswith("## ") and not is_patch_manifest_heading(stripped):
            break
        if in_manifest and stripped.startswith("|") and re.search(rf"\|\s*{re.escape(row_id)}\b", stripped, re.IGNORECASE):
            return raw
    return ""


def extract_paths(text: str, pattern: str) -> list[str]:
    seen: set[str] = set()
    paths: list[str] = []
    for match in re.finditer(pattern, text):
        rel = safe_rel_path(match.group(1))
        if rel is None or rel in seen:
            continue
        seen.add(rel)
        paths.append(rel)
    return paths


def finding_refs(text: str) -> list[str]:
    refs: list[str] = []
    current_prefix: str | None = None
    pattern = re.compile(
        r"(?<!\w)(?:(Std|Decomp)\s*#(\d+(?:-bis)?(?:/\d+(?:-bis)?)*)|(EX)-(\d+)|(F)(\d+)|#(\d+(?:-bis)?))",
        re.IGNORECASE,
    )
    for match in pattern.finditer(text):
        if match.group(1):
            current_prefix = match.group(1).title()
            for part in match.group(2).split("/"):
                refs.append(f"{current_prefix} #{part.lower()}")
            continue
        if match.group(3):
            current_prefix = "EX"
            refs.append(f"EX-{int(match.group(4)):02d}")
            continue
        if match.group(5):
            current_prefix = "F"
            refs.append(f"F{int(match.group(6))}")
            continue
        if match.group(7) and current_prefix:
            suffix = match.group(7).lower()
            if current_prefix == "EX":
                refs.append(f"EX-{int(suffix):02d}" if suffix.isdigit() else f"EX-{suffix}")
            elif current_prefix == "F":
                refs.append(f"F{int(suffix)}" if suffix.isdigit() else f"F{suffix}")
            else:
                refs.append(f"{current_prefix} #{suffix}")
    seen: set[str] = set()
    ordered: list[str] = []
    for ref in refs:
        key = ref.lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(ref)
    return ordered


def resolve_path_fragment(fragment: str) -> str | None:
    rel = safe_rel_path(fragment)
    if rel is None:
        return None
    if not ("/" in rel or rel.endswith((".md", ".sh", ".py", ".json", ".yaml", ".yml", ".toml"))):
        return None

    direct = repo / rel
    if direct.exists():
        return rel

    suffix = rel.lstrip("./")
    matches: list[str] = []
    for candidate in repo.rglob(Path(suffix).name):
        try:
            resolved = candidate.resolve(strict=True)
        except (FileNotFoundError, OSError, RuntimeError):
            continue
        if ".git" in candidate.parts or not resolved.is_file():
            continue
        try:
            candidate_rel = str(resolved.relative_to(repo_root))
        except ValueError:
            continue
        if candidate_rel.endswith(suffix):
            matches.append(candidate_rel)
    unique = sorted(set(matches))
    return unique[0] if len(unique) == 1 else None


def code_span_paths(text: str) -> list[str]:
    resolved: list[str] = []
    for match in re.finditer(r"`([^`]+)`", text):
        value = resolve_path_fragment(match.group(1))
        if value is not None:
            resolved.append(value)
    return dedupe_paths(resolved)


_finding_path_index: dict[str, list[str]] | None = None


def finding_path_index() -> dict[str, list[str]]:
    global _finding_path_index
    if _finding_path_index is not None:
        return _finding_path_index

    index: dict[str, list[str]] = {}
    for raw in plan.splitlines():
        stripped = raw.strip()
        if not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) < 2 or is_separator(cells):
            continue
        row_paths = code_span_paths(raw)
        if not row_paths:
            continue
        for ref in finding_refs(raw):
            key = ref.lower()
            index.setdefault(key, [])
            index[key] = dedupe_paths(index[key] + row_paths)

    _finding_path_index = index
    return index


def manifest_paths(row_id: str, pattern: str) -> list[str]:
    row_text = manifest_row_text(row_id)
    paths = extract_paths(row_text, f"({pattern})")
    index = finding_path_index()
    for ref in finding_refs(row_text):
        paths.extend(index.get(ref.lower(), []))
    return dedupe_paths([path for path in paths if re.fullmatch(pattern, path)])


def harden_shell_lines(lines: list[str]) -> list[str]:
    if not lines:
        return lines

    updated = list(lines)
    if not re.search(r"\bbash\b", updated[0]):
        return lines

    if updated[0] == "#!/bin/bash":
        updated[0] = "#!/usr/bin/env bash"

    updated = [
        "set -euo pipefail" if re.fullmatch(r"\s*set\s+-uo\s+pipefail\s*", line) else line
        for line in updated
    ]

    if updated[0].startswith("#!") and "set -euo pipefail" not in updated[:5]:
        updated.insert(1, "set -euo pipefail")

    updated = add_strict_mode_zero_match_guards(updated)
    updated = repair_prepush_new_branch_file_count(updated)
    return updated


def add_strict_mode_zero_match_guards(lines: list[str]) -> list[str]:
    updated: list[str] = []
    for line in lines:
        stripped = line.rstrip()
        if (
            "$(" in stripped
            and "grep -vE" in stripped
            and "|| true" not in stripped
            and stripped.count("$(") == 1
            and stripped.endswith(")")
        ):
            base_indent = stripped[: len(stripped) - len(stripped.lstrip())]
            substitution_start = stripped.index("$(")
            prefix = stripped[:substitution_start]
            inner = stripped[substitution_start + 2 : -1].strip()
            guard_indent = base_indent + "    "
            updated.extend(
                [
                    prefix + "$(",
                    guard_indent + inner + " || {",
                    guard_indent + "    grep_status=$?",
                    guard_indent + '    [ "$grep_status" -eq 1 ] || exit "$grep_status"',
                    guard_indent + "}",
                    base_indent + ")",
                ]
            )
            continue
        updated.append(line)
    return updated


def repair_prepush_new_branch_file_count(lines: list[str]) -> list[str]:
    zero_sha = "0" * 40
    has_new_branch_range = any(line.strip() == 'RANGE="$LOCAL_SHA"' for line in lines) and any(
        line.strip() == 'RANGE="$REMOTE_SHA..$LOCAL_SHA"' for line in lines
    )
    has_zero_branch = any("REMOTE_SHA" in line and zero_sha in line for line in lines)
    has_common_file_count = any(is_unsafe_prepush_common_file_count(line.strip()) for line in lines)
    if not (has_zero_branch and has_new_branch_range and has_common_file_count):
        return lines

    has_new_branch_file_count = any(
        'git diff-tree --no-commit-id --name-only -r --root "$LOCAL_SHA"' in line for line in lines
    )
    has_common_diff_hint = any(is_unsafe_prepush_common_diff_hint(line.strip()) for line in lines)
    has_new_branch_diff_hint = any(
        line.strip().startswith('DIFF_HINT="git show --name-only --oneline $LOCAL_SHA') for line in lines
    )
    updated: list[str] = []
    in_zero_branch = False
    in_else_branch = False

    for line in lines:
        stripped = line.strip()
        indent = line[: len(line) - len(line.lstrip())]
        if "REMOTE_SHA" in stripped and zero_sha in stripped and stripped.startswith("if "):
            in_zero_branch = True
            in_else_branch = False
            updated.append(line)
            continue
        if in_zero_branch and stripped == "else":
            in_zero_branch = False
            in_else_branch = True
            updated.append(line)
            continue
        if in_else_branch and stripped == "fi":
            in_else_branch = False
            updated.append(line)
            continue

        if in_zero_branch and stripped == 'RANGE="$LOCAL_SHA"':
            updated.append(line)
            if not has_new_branch_file_count:
                updated.append(
                    indent
                    + 'FILE_COUNT=$(git diff-tree --no-commit-id --name-only -r --root "$LOCAL_SHA" 2>/dev/null | wc -l | tr -d \' \')'
                )
            if has_common_diff_hint and not has_new_branch_diff_hint:
                updated.append(indent + 'DIFF_HINT="git show --name-only --oneline $LOCAL_SHA | head -200"')
            continue

        if in_else_branch and stripped == 'RANGE="$REMOTE_SHA..$LOCAL_SHA"':
            updated.append(line)
            updated.append(indent + 'FILE_COUNT=$(git diff --name-only "$RANGE" 2>/dev/null | wc -l | tr -d \' \')')
            if has_common_diff_hint:
                updated.append(indent + 'DIFF_HINT="git diff $RANGE | head -200"')
            continue

        if is_unsafe_prepush_common_file_count(stripped):
            continue
        if has_common_diff_hint and stripped.startswith('DIFF_HINT="git diff $RANGE'):
            continue
        if has_common_diff_hint and "Manual diff: git diff $REMOTE_SHA..$LOCAL_SHA | head -200" in stripped:
            match = re.search(r'echo\s+"(?P<prefix>\s*)Manual diff:', stripped)
            prefix = match.group("prefix") if match else ""
            updated.append(indent + f'echo "{prefix}Manual diff: $DIFF_HINT"')
            continue

        updated.append(line)

    return updated


def is_unsafe_prepush_common_file_count(stripped: str) -> bool:
    return stripped.startswith('FILE_COUNT=$(git diff --name-only "$RANGE"') or (
        stripped.startswith("FILE_COUNT=$(git diff --name-only ")
        and '"$REMOTE_SHA".."$LOCAL_SHA"' in stripped
    )


def is_unsafe_prepush_common_diff_hint(stripped: str) -> bool:
    return stripped.startswith('DIFF_HINT="git diff $RANGE') or (
        "Manual diff: git diff $REMOTE_SHA..$LOCAL_SHA | head -200" in stripped
    )


def pp04_semantic_blockers(rel: str, lines: list[str]) -> list[tuple[str, str]]:
    blockers: list[tuple[str, str]] = []
    for line in lines:
        if "$(" in line and "grep -vE" in line and not grep_v_substitution_is_zero_match_safe(line):
            blockers.append(
                (
                    "pp4_strict_grep_filter_unsafe",
                    f"{rel} still has a grep -vE command substitution that can exit 1 under set -euo pipefail.",
                )
            )
    zero_sha = "0" * 40
    if (
        any("REMOTE_SHA" in line and zero_sha in line for line in lines)
        and any(is_unsafe_prepush_common_file_count(line.strip()) for line in lines)
        and not any('git diff-tree --no-commit-id --name-only -r --root "$LOCAL_SHA"' in line for line in lines)
    ):
        blockers.append(
            (
                "pp4_new_branch_prepush_unsafe",
                f"{rel} still counts new-branch pre-push files through git diff \"$RANGE\" instead of a --root diff-tree path.",
            )
        )
    if (
        any("REMOTE_SHA" in line and zero_sha in line for line in lines)
        and any(is_unsafe_prepush_common_diff_hint(line.strip()) for line in lines)
        and not any(line.strip().startswith('DIFF_HINT="git show --name-only --oneline $LOCAL_SHA') for line in lines)
    ):
        blockers.append(
            (
                "pp4_new_branch_prepush_hint_unsafe",
                f"{rel} still shows an invalid all-zero remote SHA manual diff hint for new-branch pushes.",
            )
        )
    return blockers


def grep_v_substitution_is_zero_match_safe(line: str) -> bool:
    if "grep -vE" not in line:
        return True
    return line.count("$(") == 1 and "|| {" in line and "[ \"$status\" -eq 1 ]" in line


def skill_name_from_path(rel: str) -> str:
    parent = Path(rel).parent.name or "skill"
    slug = re.sub(r"[^a-z0-9]+", "-", parent.lower()).strip("-")
    return slug or "skill"


def skill_heading(lines: list[str], fallback: str) -> str:
    for line in lines[:20]:
        if line.startswith("# "):
            heading = line[2:].strip()
            if heading:
                return heading
    return fallback.replace("-", " ").title()


def yaml_double_quoted(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def frontmatter_end(lines: list[str]) -> int | None:
    if not lines or lines[0].strip() != "---":
        return None
    for idx, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return idx
    return None


def has_frontmatter_key(lines: list[str], end_idx: int, key: str) -> bool:
    pattern = re.compile(rf"^{re.escape(key)}\s*:")
    return any(pattern.search(line) for line in lines[1:end_idx])


def add_skill_metadata(lines: list[str]) -> list[str]:
    end_idx = frontmatter_end(lines)
    if end_idx is None:
        return lines

    additions: list[str] = []
    if not has_frontmatter_key(lines, end_idx, "tools"):
        additions.extend(["tools:", "  - repo-native checks"])
    if not has_frontmatter_key(lines, end_idx, "stop_rules"):
        additions.extend(
            [
                "stop_rules:",
                "  - no target mutation without owner issue/PR authorization",
            ]
        )
    if not additions:
        return lines
    return lines[:end_idx] + additions + lines[end_idx:]


def insert_after_heading(lines: list[str], block: list[str]) -> list[str]:
    marker = block[0]
    if marker in lines:
        return lines
    if lines and lines[0].startswith("#"):
        return lines[:1] + [""] + block + lines[1:]
    return block + [""] + lines


def insert_after_frontmatter_or_heading(lines: list[str], block: list[str]) -> list[str]:
    marker = block[0]
    if marker in lines:
        return lines
    end_idx = frontmatter_end(lines)
    if end_idx is not None:
        insert_idx = end_idx + 1
        while insert_idx < len(lines) and lines[insert_idx] == "":
            insert_idx += 1
        if insert_idx < len(lines) and lines[insert_idx].startswith("#"):
            return lines[: insert_idx + 1] + [""] + block + lines[insert_idx + 1 :]
        return lines[: end_idx + 1] + [""] + block + lines[end_idx + 1 :]
    return insert_after_heading(lines, block)


def materialize_pp01() -> None:
    if not has_manifest_row("PP-1"):
        return

    candidates = manifest_paths("PP-1", r"[A-Za-z0-9_./-]+/SKILL\.md")
    changes: list[tuple[str, list[str], list[str]]] = []
    for rel in candidates:
        old = read_lines(repo / rel)
        if old is None or (old and old[0].strip() == "---"):
            continue

        name = skill_name_from_path(rel)
        heading = skill_heading(old, name)
        frontmatter = [
            "---",
            f"name: {name}",
            f"description: {yaml_double_quoted(heading)}",
            "license: MIT",
            "---",
            "",
        ]
        changes.append((rel, old, frontmatter + old))

    write_patch(patch_dir / "PP-1-skill-frontmatter.patch", changes, "PP-1", manifest_rows_for("PP-1"))


def materialize_pp03() -> None:
    if not has_manifest_row("PP-3"):
        return

    candidates = manifest_paths("PP-3", r"[A-Za-z0-9_./-]+(?:/SKILL\.md|\.agent\.md)")
    skill_changes: list[tuple[str, list[str], list[str]]] = []
    agent_changes: list[tuple[str, list[str], list[str]]] = []
    for rel in candidates:
        old = read_lines(repo / rel)
        if old is None:
            continue
        new = add_skill_metadata(old)
        if old != new:
            if rel.endswith("/SKILL.md"):
                skill_changes.append((rel, old, new))
            else:
                agent_changes.append((rel, old, new))

    write_patch(patch_dir / "PP-3-additive-skill-metadata.patch", skill_changes, "PP-3", manifest_rows_for("PP-3"))
    write_patch(patch_dir / "PP-3-additive-agent-metadata.patch", agent_changes, "PP-3", manifest_rows_for("PP-3"))


def materialize_pp04() -> None:
    if not has_manifest_row("PP-4"):
        return

    candidates = [
        rel
        for rel in manifest_paths("PP-4", r"[A-Za-z0-9_./-]+\.sh")
        if "hook" in Path(rel).name.lower()
    ]

    changes: list[tuple[str, list[str], list[str]]] = []
    for rel in candidates:
        old = read_lines(repo / rel)
        if old is None:
            continue
        new = harden_shell_lines(old)
        semantic_blockers = pp04_semantic_blockers(rel, new)
        if semantic_blockers:
            for code, reason in semantic_blockers:
                record_patch_blocker("PP-4", "PP-4-hook-safety-flags.patch", code, reason)
            continue
        if old != new:
            changes.append((rel, old, new))

    write_patch(patch_dir / "PP-4-hook-safety-flags.patch", changes, "PP-4", manifest_rows_for("PP-4"))


def materialize_wm01() -> None:
    if not has_manifest_row("WM-01"):
        return

    changes: list[tuple[str, list[str], list[str]]] = []
    rel = "AGENTS.md"
    path = repo / rel
    old = read_lines(path)
    if old is not None:
        block = [
            "## Issue #164 no-handback recommendation contract",
            "",
            "- Issue #164 recommendations must name a Goal-ready production episode, not a category or operator choice.",
            "- Each recommendation must name the exact owner surface, first deliverable or PR shape, advancement rationale, out-of-scope boundaries, fallback if blocked, and validation scope.",
            "- Category-only recommendations such as `do real delivery`, `work on repo-star`, or asking the operator to pick a repo are invalid unless paired with an exact owner surface and first deliverable.",
        ]
        new = insert_after_heading(old, block)
        new = [
            "Issue #164 recommendations must name a Goal-ready production episode with exact owner surface, first deliverable, advancement rationale, boundaries, fallback, and validation scope."
            if "let the operator pick" in line and "Issue #164" in line
            else line
            for line in new
        ]
        changes.append((rel, old, new))

    # Optional BMA owner-surface files. These are skipped when absent so target
    # repositories remain read-only and patch generation stays deterministic.
    optional_blocks = {
        ".agents/skills/checking-alignment/SKILL.md": [
            "## Issue #164 no-handback recommendation contract",
            "",
            "Raised-tempo Issue #164 recommendations must name a Goal-ready production episode rather than a category or operator choice.",
            "Required fields: Goal objective, exact owner surface, first deliverable, advancement rationale, boundaries/out-of-scope, fallback if blocked, and validation scope.",
        ],
        "docs/issue164-ecosystem-architecture.md": [
            "## No-handback recommendation contract",
            "",
            "Issue #164 recommendations are valid only when they name a Goal-ready production episode with exact owner surface, first deliverable, advancement rationale, boundaries, fallback if blocked, and validation scope.",
        ],
    }
    for rel, block in optional_blocks.items():
        old = read_lines(repo / rel)
        if old is None:
            continue
        changes.append((rel, old, insert_after_heading(old, block)))

    write_patch(patch_dir / "WM-01-no-handback-recommendation-contract.patch", changes, "WM-01", manifest_rows_for("WM-01"))


def wm02_record_blocker(code: str, reason: str) -> None:
    record_patch_blocker(
        "WM-02",
        "WM-02-github-native-closeout-bypass.patch",
        code,
        reason,
        manifest_rows_for("WM-02"),
    )


def wm02_parser_insert_index(lines: list[str]) -> int | None:
    matches: list[int] = []
    for idx in range(len(lines) - 6):
        window = [line.strip() for line in lines[idx : idx + 7]]
        if (
            window[0] == 'while [ $# -gt 0 ]; do'
            and window[1] == 'case "$1" in'
            and any('--no-novel-findings)' in item and 'shift 2' in item for item in window[2:5])
            and any(item == '*) shift ;;' for item in window[2:6])
            and 'esac' in window[4:6]
            and 'done' in window[5:7]
        ):
            for insert_idx in range(idx + 2, min(idx + 6, len(lines))):
                if lines[insert_idx].strip() == '*) shift ;;':
                    matches.append(insert_idx)
                    break
    return matches[0] if len(matches) == 1 else None


def wm02_parser_start_index(lines: list[str], insert_idx: int) -> int | None:
    for idx in range(insert_idx, -1, -1):
        if lines[idx].strip() == 'while [ $# -gt 0 ]; do':
            return idx
    return None


def wm02_variable_insert_index(lines: list[str], parser_start_idx: int) -> int | None:
    for idx in range(parser_start_idx - 1, max(-1, parser_start_idx - 8), -1):
        if lines[idx].strip().endswith('=""'):
            return idx
    return None


def wm02_score_session_site_index(lines: list[str]) -> int | None:
    matches = [
        idx
        for idx, line in enumerate(lines)
        if line.strip() == 'if [ -f scripts/score-session.sh ]; then'
        and any('scripts/score-session.sh' in candidate for candidate in lines[idx + 1 : idx + 6])
    ]
    return matches[0] if len(matches) == 1 else None


def wm02_row_is_clean_direct_campaign(row: dict[str, object]) -> bool:
    text = " ".join(str(value).lower() for value in row.values())
    clean_closure = (
        "closure_regrowth=>none" in text
        or "github_native_closure_regrowth_count" in text
        and re.search(r"github_native_closure_regrowth_count[\"'=:\s]+0", text) is not None
    )
    bypassed = (
        "bypassed=>" in text
        or "github-native-closeout" in text
        or "github_native_closeout_bypassed_count" in text
    )
    direct_campaign = (
        "direct campaign" in text
        or "issue #164" in text
        or "issue164" in text
        or "github-native closeout" in text
    )
    return clean_closure and bypassed and direct_campaign


def materialize_wm02() -> None:
    if not has_manifest_row("WM-02"):
        return

    wm02_rows = manifest_rows_for("WM-02")
    if wm02_rows and all(wm02_row_is_clean_direct_campaign(row) for row in wm02_rows):
        record_patch_blocker(
            "WM-02",
            "WM-02-github-native-closeout-bypass.patch",
            "wm02_clean_direct_campaign_closure_no_patch",
            "WM-02 row describes clean direct campaign closure with GitHub-native closeout already bypassing local authority; no patch should be generated.",
            wm02_rows,
        )
        return

    changes: list[tuple[str, list[str], list[str]]] = []
    core_blocked = False

    rel = "scripts/work-close.sh"
    old = read_lines(repo / rel)
    if old is None:
        core_blocked = True
        wm02_record_blocker(
            "wm02_work_close_unreadable",
            "WM-02 requires a readable, in-repository scripts/work-close.sh target file.",
        )
    elif not any("--github-native-closeout" in line for line in old):
        new = list(old)
        parser_insert_at = wm02_parser_insert_index(new)
        parser_start_at = wm02_parser_start_index(new, parser_insert_at) if parser_insert_at is not None else None
        variable_insert_at = wm02_variable_insert_index(new, parser_start_at) if parser_start_at is not None else None
        score_site_at = wm02_score_session_site_index(new)
        if parser_insert_at is None:
            core_blocked = True
            wm02_record_blocker(
                "wm02_parser_shape_ambiguous_or_absent",
                "WM-02 requires exactly one existing scripts/work-close.sh flag parser with the expected while/case shape before inserting --github-native-closeout.",
            )
        elif variable_insert_at is None:
            core_blocked = True
            wm02_record_blocker(
                "wm02_parser_variable_anchor_absent",
                "WM-02 requires a nearby existing flag variable initializer before the work-close flag parser so --github-native-closeout state is not inserted above the script preamble.",
            )
        if score_site_at is None:
            core_blocked = True
            wm02_record_blocker(
                "wm02_score_session_site_ambiguous_or_absent",
                "WM-02 requires exactly one existing scripts/score-session.sh invocation guard before inserting the bypass branch.",
            )
        if parser_insert_at is not None and variable_insert_at is not None and score_site_at is not None:
            parse_insert = [
                'GITHUB_NATIVE_CLOSEOUT=""',
                '        --github-native-closeout) GITHUB_NATIVE_CLOSEOUT="${2:?--github-native-closeout requires a rationale}"; shift 2 ;;',
            ]
            new.insert(variable_insert_at, parse_insert[0])
            case_insert_at = parser_insert_at + (1 if variable_insert_at <= parser_insert_at else 0)
            new.insert(case_insert_at, parse_insert[1])
            validation_block = [
                '',
                'if [ -n "$GITHUB_NATIVE_CLOSEOUT" ] && [ "${#GITHUB_NATIVE_CLOSEOUT}" -lt 30 ]; then',
                '    echo "ERROR: --github-native-closeout requires a concrete rationale (>=30 chars)." >&2',
                '    exit 1',
                'fi',
            ]
            parser_done_idx = next(idx for idx in range(case_insert_at, len(new)) if new[idx].strip() == 'done')
            new = new[: parser_done_idx + 1] + validation_block + new[parser_done_idx + 1 :]

            bypass_block = [
                'if [ -n "$GITHUB_NATIVE_CLOSEOUT" ]; then',
                '    BYPASS_FILE="$WORK_DIR/score-session-bypass.json"',
                '    python3 - "$BYPASS_FILE" "$WORK_DIR" "$GITHUB_NATIVE_CLOSEOUT" <<\'PYRECEIPT\'',
                'import json, os, sys',
                'from datetime import datetime, timezone',
                'out, work_dir, rationale = sys.argv[1:]',
                'receipt = {',
                '    "schema_version": "1.0.0",',
                '    "mode": "github_native_issue_pr",',
                '    "status": "score_session_not_authoritative",',
                '    "work_dir": os.path.relpath(work_dir, os.getcwd()),',
                '    "skipped_script": "scripts/score-session.sh",',
                '    "rationale": rationale,',
                '    "non_claims": [',
                '        "Does not prove GitHub issue closure by itself.",',
                '        "Does not apply to non-GitHub or session-local work.",',
                '        "Does not change score-session thresholds."',
                '    ],',
                '    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),',
                '}',
                'with open(out, "w", encoding="utf-8") as fh:',
                '    json.dump(receipt, fh, indent=2, sort_keys=True)',
                '    fh.write("\\n")',
                'PYRECEIPT',
                '    echo "  Session grader skipped: GitHub-native issue/PR closure authority."',
                'elif [ -f scripts/score-session.sh ]; then',
            ]
            score_site_at = wm02_score_session_site_index(new)
            if score_site_at is not None:
                new = new[:score_site_at] + bypass_block + new[score_site_at + 1 :]
                changes.append((rel, old, new))

    if not core_blocked:
        rel = "Makefile"
        old = read_lines(repo / rel)
        if old is not None and not any("--github-native-closeout" in line for line in old):
            new = list(old)
            help_line = '\t@echo "  bash scripts/work-close.sh <work-dir> --github-native-closeout \\\"...\\\""'
            inserted = False
            for idx, line in enumerate(new):
                if "make work-close" in line:
                    new.insert(idx + 1, help_line)
                    inserted = True
                    break
            if not inserted:
                new.append(help_line)
            changes.append((rel, old, new))

        rel = "docs/agent-operations.md"
        old = read_lines(repo / rel)
        if old is not None and not any("score-session-bypass.json" in line for line in old):
            new = [
                line.replace(
                    "runs the session grader",
                    "runs the session grader by default and writes `score-session-bypass.json` for explicit GitHub-native issue/PR closeout",
                )
                for line in old
            ]
            changes.append((rel, old, new))

    write_patch(patch_dir / "WM-02-github-native-closeout-bypass.patch", changes, "WM-02", manifest_rows_for("WM-02"))


def materialize_wm03() -> None:
    if not has_manifest_row("WM-03"):
        return

    changes: list[tuple[str, list[str], list[str]]] = []
    block = [
        "## Issue #164 core-five proving-ground guidance",
        "",
        "- The core five are reciprocal proving grounds: BMA, repo-auditor, repo-upgrade-advisor, repo-optimizer, and repo-agent-core may validate against each other read-only.",
        "- Core-five target use is ordinary validation, not downstream adoption or permission to mutate that target repo.",
        "- Each core-five repo changes only through its own owner issue, branch, PR, checks, and merge.",
    ]

    rel = "AGENTS.md"
    old = read_lines(repo / rel)
    if old is not None:
        changes.append((rel, old, insert_after_heading(old, block)))

    rel = "docs/issue164-ecosystem-architecture.md"
    old = read_lines(repo / rel)
    if old is not None:
        changes.append((rel, old, insert_after_heading(old, block)))

    write_patch(patch_dir / "WM-03-core-five-proving-ground-guidance.patch", changes, "WM-03", manifest_rows_for("WM-03"))


def materialize_wm04() -> None:
    if not has_manifest_row("WM-04"):
        return

    changes: list[tuple[str, list[str], list[str]]] = []
    block = [
        "## Issue #164 capability-home owner-surface routing",
        "",
        "| Capability family | Owner surface | First deliverable shape |",
        "|---|---|---|",
        "| Outer-loop campaign console | build-meta-analysis | Issue #164 child issue and GitHub-native PR |",
        "| Audit/signature detection | repo-auditor | Detector signature, fixture, and repo-native test |",
        "| Recommendation packaging | repo-upgrade-advisor | Recommendation template, scorer rule, and packaging fixture |",
        "| Patch-pack materialization | repo-optimizer | Deterministic patch materializer and `git apply --check` fixture |",
        "| Shared repo-agent contract | repo-agent-core | Copy-synced guidance contract after portability proof |",
    ]

    rel = "AGENTS.md"
    old = read_lines(repo / rel)
    if old is not None:
        changes.append((rel, old, insert_after_heading(old, block)))

    rel = "docs/issue164-ecosystem-architecture.md"
    old = read_lines(repo / rel)
    if old is not None:
        changes.append((rel, old, insert_after_heading(old, block)))

    write_patch(patch_dir / "WM-04-capability-home-owner-surface-table.patch", changes, "WM-04", manifest_rows_for("WM-04"))


def materialize_hs01() -> None:
    if not has_manifest_row("HS-01"):
        return

    candidates = manifest_paths("HS-01", r"[A-Za-z0-9_./-]+(?:\.md|\.sh|/SKILL\.md)")
    changes: list[tuple[str, list[str], list[str]]] = []
    for rel in candidates:
        old = read_lines(repo / rel)
        if old is None:
            continue
        new = list(old)
        changed = False
        blocked = False
        for idx, line in enumerate(old):
            if not re.search(r"(^|[;&|({\s])status\s*=\s*\$\?", line):
                continue
            window = "\n".join(old[max(0, idx - 4) : min(len(old), idx + 6)])
            if not re.search(
                r"\b(hermes|foreground|validate-hermes-foreground-output|zsh|launch contract)\b",
                window,
                re.IGNORECASE,
            ):
                record_patch_blocker(
                    "HS-01",
                    "HS-01-hermes-status-variable.patch",
                    "hs01_ambiguous_status_assignment",
                    f"{rel} contains a reserved lowercase status exit-code assignment without nearby Hermes/foreground/zsh launch context.",
                )
                blocked = True
                break
            new[idx] = re.sub(r"(^|[;&|({\s])status(\s*=\s*\$\?)", r"\1hermes_status\2", line)
            changed = True
            for follow_idx in range(idx + 1, min(len(old), idx + 8)):
                if "validate-hermes-foreground-output" in new[follow_idx] or "--status-code" in new[follow_idx]:
                    new[follow_idx] = (
                        new[follow_idx]
                        .replace('"$status"', '"$hermes_status"')
                        .replace("${status}", "${hermes_status}")
                    )
        if blocked:
            continue
        if changed:
            changes.append((rel, old, new))

    write_patch(patch_dir / "HS-01-hermes-status-variable.patch", changes, "HS-01", manifest_rows_for("HS-01"))


def manifest_capability(row_id: str) -> str | None:
    row_text = manifest_row_text(row_id)
    for value in re.findall(r"`([^`]+)`", row_text):
        if resolve_path_fragment(value) is None:
            capability = value.strip().replace("|", "/")
            if capability:
                return capability
    match = re.search(r"\bcapability\s*:\s*([^|]+)", row_text, re.IGNORECASE)
    if match:
        capability = match.group(1).strip().strip("`'\"").replace("|", "/")
        if capability:
            return capability
    return None


def default_capability_reconciliation_block(capability: str) -> list[str]:
    return [
        "## Default Capability Reconciliation",
        "",
        "| Capability | Source requirement | Local proof | Owner surface | Fallback | Validation |",
        "|---|---|---|---|---|---|",
        f"| {capability} | Upstream-main proof required before production default adoption | Local same-version proof required | Named owner surface required | Keep prior fallback or fail closed until proof passes | Repo-native checks plus read-only detector sweep |",
    ]


def upsert_reconciliation_block(lines: list[str], block: list[str]) -> list[str]:
    marker = block[0]
    for idx, line in enumerate(lines):
        if line.strip().lower() != marker.lower():
            continue
        end = idx + 1
        while end < len(lines):
            if lines[end].startswith("## ") and end > idx:
                break
            end += 1
        return lines[:idx] + block + [""] + lines[end:]
    return insert_after_heading(lines, block)


def materialize_cr01() -> None:
    if not has_manifest_row("CR-01"):
        return

    row_id = "CR-01"
    patch_name = "CR-01-default-capability-reconciliation.patch"
    candidates = manifest_paths(row_id, r"[A-Za-z0-9_./-]+(?:\.md|\.txt|\.json|\.yaml|\.yml|/SKILL\.md)")
    if not candidates:
        record_patch_blocker(
            row_id,
            patch_name,
            "cr01_missing_named_file",
            "CR-01 requires one explicitly named target file in the patch manifest row.",
        )
        return
    if len(candidates) > 1:
        record_patch_blocker(
            row_id,
            patch_name,
            "cr01_ambiguous_named_files",
            "CR-01 requires exactly one target file so capability reconciliation does not become a broad rewrite.",
        )
        return

    capability = manifest_capability(row_id)
    if capability is None:
        record_patch_blocker(
            row_id,
            patch_name,
            "cr01_missing_named_capability",
            "CR-01 requires an explicitly named capability such as `Hermes -z` in the patch manifest row.",
        )
        return

    rel = candidates[0]
    old = read_lines(repo / rel)
    if old is None:
        record_patch_blocker(
            row_id,
            patch_name,
            "cr01_target_file_unreadable",
            f"CR-01 target file is missing, unsafe, symlinked, or outside the repository: {rel}",
        )
        return

    block = default_capability_reconciliation_block(capability)
    new = upsert_reconciliation_block(old, block)
    write_patch(patch_dir / patch_name, [(rel, old, new)], row_id, manifest_rows_for(row_id))


def hfr01_receipt_block() -> list[str]:
    return [
        "## HERMES_FOREGROUND_RUN_RECEIPT",
        "",
        "- For explicit Hermes foreground runs, retain the foreground Hermes command, exit status, stdout/stderr receipt path, and validation command.",
        "- Treat the receipt as adoption evidence only for the named run; it does not authorize target mutation or unattended execution.",
    ]


def hfr01_has_receipt_guidance(lines: list[str]) -> bool:
    text = "\n".join(lines).lower()
    return "hermes_foreground_run_receipt" in text or (
        "foreground hermes" in text
        and "exit status" in text
        and "receipt" in text
        and "validation command" in text
    )


def hfr01_manifest_rows() -> list[dict[str, object]]:
    return [row for row in manifest_rows(plan) if str(row.get("row_id", "")) == "HFR-01"]


def hfr01_paths_for_row(row: dict[str, object]) -> list[str | None]:
    text = str(row.get("raw_row", ""))
    paths: list[str | None] = []
    for match in re.finditer(r"`([^`]+)`", text):
        value = match.group(1)
        rel = safe_rel_path(value)
        if rel is None or has_git_path_component(rel):
            paths.append(None)
            continue
        if re.fullmatch(r"[A-Za-z0-9_./-]+(?:\.md|\.txt|/SKILL\.md)", rel):
            paths.append(rel)
    return paths


def hfr01_record(row: dict[str, object], patch_name: str, code: str, reason: str) -> None:
    blocker = {
        "row_id": str(row.get("row_id", "HFR-01")),
        "patch": row.get("patch", ""),
        "findings": row.get("findings", ""),
        "files_touched": row.get("files_touched", ""),
        "blocker_code": code,
        "reason": reason,
    }
    scan_context = row.get("scan_context") if isinstance(row.get("scan_context"), dict) else None
    if scan_context:
        blocker["scan_context"] = scan_context
        claims = scan_limited_non_claim(scan_context)
        if claims:
            blocker["bounded_non_claims"] = claims
    overflow_blockers.append(blocker)


def materialize_hfr01() -> None:
    rows = hfr01_manifest_rows()
    if not rows:
        return

    patch_name = "HFR-01-hermes-foreground-run-receipt.patch"
    changes: list[tuple[str, list[str], list[str]]] = []
    metadata_rows: list[dict[str, object]] = []
    emitted_or_blocked = False
    processed_targets: set[str] = set()
    for row in rows:
        paths = hfr01_paths_for_row(row)
        files_touched = str(row.get("files_touched", "")).strip()
        if any(path is None for path in paths):
            hfr01_record(
                row,
                patch_name,
                "hfr01_unsafe_named_file",
                "HFR-01 requires a safe repository-relative named target file; absolute paths or parent traversal are not patchable.",
            )
            emitted_or_blocked = True
            continue
        concrete_paths = [path for path in paths if path is not None]
        if not concrete_paths:
            hfr01_record(
                row,
                patch_name,
                "hfr01_missing_named_file",
                "HFR-01 requires exactly one safe named target file in the manifest row.",
            )
            emitted_or_blocked = True
            continue
        if len(dedupe_paths(concrete_paths)) != 1:
            hfr01_record(
                row,
                patch_name,
                "hfr01_ambiguous_named_files",
                "HFR-01 requires exactly one target file so foreground receipt adoption does not become a broad rewrite.",
            )
            emitted_or_blocked = True
            continue
        if files_touched != "1":
            hfr01_record(
                row,
                patch_name,
                "hfr01_broad_row_scope",
                "HFR-01 requires a patch manifest row scoped to exactly one file; broad rows are not patchable.",
            )
            emitted_or_blocked = True
            continue

        rel = concrete_paths[0]
        if rel in processed_targets:
            hfr01_record(
                row,
                patch_name,
                "hfr01_duplicate_target_file",
                f"HFR-01 target file already has a materialized receipt patch in this run: {rel}",
            )
            emitted_or_blocked = True
            continue
        path = repo / rel
        if path.is_symlink():
            hfr01_record(
                row,
                patch_name,
                "hfr01_symlinked_target_file",
                f"HFR-01 target file is symlinked and is not safe for deterministic patch materialization: {rel}",
            )
            emitted_or_blocked = True
            continue
        old = read_lines(path)
        if old is None:
            hfr01_record(
                row,
                patch_name,
                "hfr01_target_file_unreadable",
                f"HFR-01 target file is missing, broad, unsafe, or outside the repository: {rel}",
            )
            emitted_or_blocked = True
            continue
        if hfr01_has_receipt_guidance(old):
            hfr01_record(
                row,
                patch_name,
                "hfr01_already_grounded",
                f"HFR-01 target file already contains Hermes foreground receipt guidance: {rel}",
            )
            emitted_or_blocked = True
            continue
        new = insert_after_frontmatter_or_heading(old, hfr01_receipt_block())
        changes.append((rel, old, new))
        scan_context = row.get("scan_context") if isinstance(row.get("scan_context"), dict) else None
        if scan_context:
            metadata_rows.append(
                {
                    "row_id": str(row.get("row_id", "HFR-01")),
                    "patch": patch_name,
                    "target_file": rel,
                    "scan_context": scan_context,
                    "bounded_non_claims": scan_limited_non_claim(scan_context),
                }
            )
        processed_targets.add(rel)
        emitted_or_blocked = True

    if changes:
        if write_patch(patch_dir / patch_name, changes, "HFR-01"):
            patch_metadata.extend(metadata_rows)
    elif emitted_or_blocked:
        written_row_ids.add("HFR-01")


def flush_patch_metadata() -> None:
    if not patch_metadata:
        return
    out_path = patch_dir.parent / "PATCH_PACK_METADATA.json"
    payload = {
        "schema_version": "1.0.0",
        "artifact": "PATCH_PACK_METADATA",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_manifest": str(findings),
        "patch_dir": str(patch_dir),
        "patches": patch_metadata,
        "bounded_non_claims": [
            "This metadata records patch-pack provenance and preserved advisor scan context only.",
            "It does not authorize target repository mutation or auto-apply behavior.",
        ],
    }
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


materialize_pp01()
materialize_pp03()
materialize_pp04()
materialize_wm01()
materialize_wm02()
materialize_wm03()
materialize_wm04()
materialize_hs01()
materialize_cr01()
materialize_hfr01()
flush_patch_metadata()
flush_manifest_blockers()
PY

# Post-process any existing patches
PATCH_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
    [ -f "$patch" ] || continue
    PATCH_COUNT=$((PATCH_COUNT + 1))

    # Fix diff headers if needed
    if [ -x "$SCRIPT_DIR/fix-diff-headers.sh" ]; then
        TMP_PATCH="$(mktemp)"
        if bash "$SCRIPT_DIR/fix-diff-headers.sh" "$patch" "$TMP_PATCH" >/dev/null 2>&1; then
            mv "$TMP_PATCH" "$patch"
        else
            rm -f "$TMP_PATCH"
        fi
    fi

    # Validate
    BASENAME="$(basename "$patch")"
    if cd "$REPO" && git apply --check "$patch" 2>/dev/null; then
        echo "  ✓ $BASENAME — applies cleanly"
    else
        echo "  ✗ $BASENAME — FAILS git apply --check"
    fi
done

if [ "$PATCH_COUNT" -eq 0 ]; then
    if [ ! -s "$OUTPUT_DIR/PATCHABILITY_BLOCKERS.json" ]; then
        python3 - "$FINDINGS" "$PATCH_DIR" "$OUTPUT_DIR/PATCHABILITY_BLOCKERS.json" <<'PY'
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

findings = Path(sys.argv[1])
patch_dir = Path(sys.argv[2])
out_path = Path(sys.argv[3])
plan = findings.read_text(encoding="utf-8", errors="replace")


def is_separator(cells: list[str]) -> bool:
    return all(re.fullmatch(r":?-{3,}:?", cell.strip() or "-") for cell in cells)


def is_patch_manifest_heading(text: str) -> bool:
    return bool(re.match(r"^#{1,6}\s*(?:\d+\.\s*)?Patch Manifest\b", text, re.IGNORECASE))


def extract_scan_context(text: str) -> dict[str, object] | None:
    marker = "scan_context="
    start = text.find(marker)
    if start < 0:
        return None
    brace_start = text.find("{", start + len(marker))
    if brace_start < 0:
        return None
    depth = 0
    in_string = False
    escape = False
    for idx in range(brace_start, len(text)):
        char = text[idx]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                try:
                    value = json.loads(text[brace_start : idx + 1])
                except json.JSONDecodeError:
                    return None
                return value if isinstance(value, dict) else None
    return None


def scan_limited_non_claim(scan_context: dict[str, object] | None) -> list[str]:
    if scan_context and scan_context.get("scan_limited") is True:
        return [
            "scan-limited metadata is preserved from the advisor recommendation; it does not prove repository-wide absence or presence beyond the recorded scan scope."
        ]
    return []


def manifest_rows(text: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    headers: list[str] | None = None
    in_manifest = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if is_patch_manifest_heading(stripped):
            in_manifest = True
            headers = None
            continue
        if in_manifest and stripped.startswith("## ") and not is_patch_manifest_heading(stripped):
            break
        if not in_manifest or not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) < 2 or is_separator(cells):
            continue
        if headers is None:
            headers = [cell.lower() for cell in cells]
            continue
        row_id = cells[0]
        patch_label = cells[1] if len(cells) > 1 else row_id
        findings_value = cells[2] if len(cells) > 2 and headers[1] in {"patch", "patch name"} else cells[1]
        files_touched = ""
        for idx, header in enumerate(headers):
            if "files" in header and idx < len(cells):
                files_touched = cells[idx]
                break
        rows.append(
            {
                "row_id": row_id,
                "patch": patch_label,
                "findings": findings_value,
                "files_touched": files_touched,
                "raw_row": raw,
                "scan_context": extract_scan_context(raw),
            }
        )
    return rows


def blocker_for(row: dict[str, object]) -> dict[str, object]:
    row_text = " ".join(str(value) for value in row.values())
    row_id = str(row.get("row_id", "unknown"))
    supported = bool(
        row_id in {"P4", "PP-1", "PP-3", "PP-4", "WM-01", "WM-02", "WM-03", "WM-04", "HS-01", "CR-01", "HFR-01"}
        or re.search(r"\bS-05\b", row_text)
        and re.search(r"\bS-06\b", row_text)
        and re.search(r"\bS-07\b", row_text)
    )
    code = "supported_materializer_no_output" if supported else "unsupported_manifest_row"
    reason = (
        f"A deterministic materializer matched {row_id}, but the target had no apply-checkable change."
        if supported
        else f"No deterministic patch materializer is implemented for manifest row {row_id}."
    )
    blocker = {
        "row_id": row_id,
        "patch": row.get("patch", ""),
        "findings": row.get("findings", ""),
        "files_touched": row.get("files_touched", ""),
        "blocker_code": code,
        "reason": reason,
    }
    scan_context = row.get("scan_context") if isinstance(row.get("scan_context"), dict) else None
    if scan_context:
        blocker["scan_context"] = scan_context
        claims = scan_limited_non_claim(scan_context)
        if claims:
            blocker["bounded_non_claims"] = claims
    return blocker


rows = manifest_rows(plan)
blockers = [blocker_for(row) for row in rows]
if not blockers:
    blockers = [
        {
            "row_id": "manifest",
            "patch": "",
            "findings": "",
            "files_touched": "",
            "blocker_code": "manifest_rows_not_found",
            "reason": "No parseable Patch Manifest table rows were found in the optimization plan.",
        }
    ]

payload = {
    "schema_version": "1.0.0",
    "artifact": "PATCHABILITY_BLOCKERS",
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_manifest": str(findings),
    "patch_dir": str(patch_dir),
    "patches_generated": 0,
    "blocker_count": len(blockers),
    "blockers": blockers,
    "bounded_non_claims": [
        "This artifact explains why patch mode emitted zero patch files.",
        "It does not authorize target repository mutation or auto-apply behavior.",
    ],
}
out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    fi
    echo "  Patchability blockers → $OUTPUT_DIR/PATCHABILITY_BLOCKERS.json"
    echo "  No patches found in $PATCH_DIR/"
fi

echo ""
echo "=== Done. $PATCH_COUNT patches processed ==="

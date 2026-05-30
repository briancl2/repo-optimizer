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
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
findings = Path(sys.argv[2])
patch_dir = Path(sys.argv[3])
plan = findings.read_text(encoding="utf-8", errors="replace")


def has_manifest_row(row_id: str) -> bool:
    return bool(re.search(rf"(?:^|[|\n\r])\s*{re.escape(row_id)}\b", plan, re.IGNORECASE))


def read_lines(path: Path) -> list[str] | None:
    if not path.exists() or not path.is_file():
        return None
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def write_patch(patch_path: Path, changes: list[tuple[str, list[str], list[str]]]) -> None:
    parts: list[str] = []
    for rel, old, new in changes:
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
        parts.append(f"diff --git a/{rel} b/{rel}")
        parts.extend(diff)
    if parts:
        patch_path.write_text("\n".join(parts) + "\n", encoding="utf-8")


def insert_after_heading(lines: list[str], block: list[str]) -> list[str]:
    marker = block[0]
    if marker in lines:
        return lines
    if lines and lines[0].startswith("#"):
        return lines[:1] + [""] + block + lines[1:]
    return block + [""] + lines


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

    write_patch(patch_dir / "WM-01-no-handback-recommendation-contract.patch", changes)


def materialize_wm02() -> None:
    if not has_manifest_row("WM-02"):
        return

    changes: list[tuple[str, list[str], list[str]]] = []

    rel = "scripts/work-close.sh"
    old = read_lines(repo / rel)
    if old is not None and not any("--github-native-closeout" in line for line in old):
        new = list(old)
        parse_block = [
            'GITHUB_NATIVE_CLOSEOUT=""',
            'while [ $# -gt 0 ]; do',
            '    case "$1" in',
            '        --github-native-closeout) GITHUB_NATIVE_CLOSEOUT="${2:?--github-native-closeout requires a rationale}"; shift 2 ;;',
            '        *) shift ;;',
            '    esac',
            'done',
            '',
            'if [ -n "$GITHUB_NATIVE_CLOSEOUT" ] && [ "${#GITHUB_NATIVE_CLOSEOUT}" -lt 30 ]; then',
            '    echo "ERROR: --github-native-closeout requires a concrete rationale (>=30 chars)." >&2',
            '    exit 1',
            'fi',
            '',
        ]
        inserted = False
        for idx, line in enumerate(new):
            if line.strip() in {'shift', 'shift || true'}:
                new = new[: idx + 1] + parse_block + new[idx + 1 :]
                inserted = True
                break
        if not inserted:
            insert_at = 2 if len(new) > 2 else len(new)
            new = new[:insert_at] + parse_block + new[insert_at:]

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
        replaced = False
        for idx, line in enumerate(new):
            if line.strip() == 'if [ -f scripts/score-session.sh ]; then':
                new = new[:idx] + bypass_block + new[idx + 1 :]
                replaced = True
                break
        if not replaced:
            new.extend([""] + bypass_block + [
                '    bash scripts/score-session.sh "$WORK_DIR" "$(basename "$WORK_DIR")"',
                'fi',
            ])
        changes.append((rel, old, new))

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

    write_patch(patch_dir / "WM-02-github-native-closeout-bypass.patch", changes)


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

    write_patch(patch_dir / "WM-03-core-five-proving-ground-guidance.patch", changes)


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

    write_patch(patch_dir / "WM-04-capability-home-owner-surface-table.patch", changes)


materialize_wm01()
materialize_wm02()
materialize_wm03()
materialize_wm04()
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


def manifest_rows(text: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    headers: list[str] | None = None
    in_manifest = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if re.search(r"patch\s+manifest", stripped, re.IGNORECASE):
            in_manifest = True
            headers = None
            continue
        if in_manifest and stripped.startswith("## ") and not re.search(r"patch\s+manifest", stripped, re.IGNORECASE):
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
            }
        )
    return rows


def blocker_for(row: dict[str, object]) -> dict[str, object]:
    row_text = " ".join(str(value) for value in row.values())
    row_id = str(row.get("row_id", "unknown"))
    supported = bool(
        row_id in {"P4", "WM-01", "WM-02", "WM-03", "WM-04"}
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
    return {
        "row_id": row_id,
        "patch": row.get("patch", ""),
        "findings": row.get("findings", ""),
        "files_touched": row.get("files_touched", ""),
        "blocker_code": code,
        "reason": reason,
    }


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
    echo "  Patchability blockers → $OUTPUT_DIR/PATCHABILITY_BLOCKERS.json"
    echo "  No patches found in $PATCH_DIR/"
fi

echo ""
echo "=== Done. $PATCH_COUNT patches processed ==="

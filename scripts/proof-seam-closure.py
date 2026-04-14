#!/usr/bin/env python3
"""Run the frozen proof-seam closure matrix and emit composite receipts.

This is an internal owner-side harness. It does not change the public
repo-optimizer invocation contract.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_OLDER_SHA = "12f2b2a334337f9e86de2784a4eed57e548a3eae"
DEFAULT_REPAIR_SHA = "e114efb"
DEFAULT_TARGET_SHA = "f31933cda7d297e13d18b7ccca7044d09a8fec43"
DEFAULT_MODEL = "claude-opus-4.6"
WAIT_PATTERN = "Waiting up to 300 seconds for command output"
ROOT_COMMAND_FAMILY = (
    "bash scripts/repo-optimizer.sh <repo-auditor> <audit-dir> <output-dir> --patch"
)
TERMINAL_CLOSEOUT_ARTIFACTS = [
    "RUNTIME_RECEIPTS.json",
    "critic-phase-receipt.json",
    "synthesis-phase-receipt.json",
    "critic-verdicts.md",
    "OPTIMIZATION_PLAN.md",
    "OPTIMIZATION_SCORECARD.json",
]
ACTIVE_AGENT_FILES = {
    ".agents/repo-optimizer.agent.md",
    ".agents/repo-optimizer-inbound.agent.md",
    ".agents/repo-optimizer-critic.agent.md",
    ".agents/repo-optimizer-synthesis.agent.md",
    ".agents/decomposition-optimizer.agent.md",
    ".agents/consolidation-optimizer.agent.md",
    ".agents/extraction-optimizer.agent.md",
    ".agents/standardization-optimizer.agent.md",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
    stdout_path: Path | None = None,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    popen_kwargs = {
        "cwd": str(cwd) if cwd else None,
        "env": env,
        "text": True,
        "start_new_session": True,
    }

    if stdout_path is None:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            **popen_kwargs,
        )
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            terminate_process_group(process)
            stdout, stderr = process.communicate()
            if check:
                raise subprocess.TimeoutExpired(
                    cmd,
                    timeout,
                    output=stdout,
                    stderr=stderr,
                ) from exc
            return subprocess.CompletedProcess(
                cmd,
                returncode=124,
                stdout=stdout or "",
                stderr=stderr or str(exc),
            )
        completed = subprocess.CompletedProcess(
            cmd,
            returncode=process.returncode,
            stdout=stdout,
            stderr=stderr,
        )
        if check and completed.returncode != 0:
            raise subprocess.CalledProcessError(
                completed.returncode,
                cmd,
                output=completed.stdout,
                stderr=completed.stderr,
            )
        return completed

    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    with stdout_path.open("w", encoding="utf-8") as handle:
        process = subprocess.Popen(
            cmd,
            stdout=handle,
            stderr=subprocess.STDOUT,
            **popen_kwargs,
        )
        try:
            process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            handle.write(
                f"\n[proof-seam-closure] command timed out after {timeout} seconds\n"
            )
            terminate_process_group(process)
            if check:
                raise
            return subprocess.CompletedProcess(
                cmd,
                returncode=124,
                stdout="",
                stderr=str(exc),
            )
    completed = subprocess.CompletedProcess(
        cmd,
        returncode=process.returncode,
        stdout="",
        stderr="",
    )
    if check and completed.returncode != 0:
        raise subprocess.CalledProcessError(
            completed.returncode,
            cmd,
            output=completed.stdout,
            stderr=completed.stderr,
        )
    return completed


def terminate_process_group(process: subprocess.Popen[str]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait(timeout=5)


def run_allow_failure(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    stdout_path: Path,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    return run(
        cmd,
        cwd=cwd,
        env=env,
        check=False,
        stdout_path=stdout_path,
        timeout=timeout,
    )


def git_worktree_add(repo_root: Path, path: Path, ref: str) -> None:
    if path.exists():
        git_worktree_remove(repo_root, path)
        if path.exists():
            shutil.rmtree(path)
    run(
        ["git", "worktree", "add", "--detach", str(path), ref],
        cwd=repo_root,
    )


def git_worktree_remove(repo_root: Path, path: Path) -> None:
    if not path.exists():
        return
    run(
        ["git", "worktree", "remove", "--force", str(path)],
        cwd=repo_root,
        check=False,
    )
    if path.exists():
        shutil.rmtree(path)


def classify_changed_path(path: str) -> tuple[str, str]:
    if path == "scripts/repo-optimizer.sh":
        return ("runtime_affecting", "public root orchestrator used by all admitted paths")
    if path == "scripts/score-operation.sh":
        return ("runtime_affecting", "post-run scorer invoked by repo-optimizer.sh")
    if path == "Makefile":
        return ("runtime_affecting", "public wrapper surface")
    if path in ACTIVE_AGENT_FILES:
        return ("runtime_affecting", "public agent or phase prompt read at runtime")
    if path.startswith("docs/"):
        return ("non_runtime", "documentation or retained receipt")
    if path.startswith("tests/"):
        return ("non_runtime", "test-only surface")
    if path.startswith(".github/"):
        return ("non_runtime", "not loaded by repo-optimizer runtime; runtime reads .agents/")
    if path.startswith(".agents/speckit."):
        return ("non_runtime", "spec-kit helper not used by the proof seam")
    if path == "LEARNINGS.md":
        return ("non_runtime", "memory surface")
    return ("unknown", "unclassified diff path")


def changed_paths(repo_root: Path, older_sha: str, repair_sha: str) -> list[dict[str, str]]:
    completed = run(
        ["git", "diff", "--name-only", older_sha, repair_sha],
        cwd=repo_root,
    )
    records: list[dict[str, str]] = []
    for raw_path in completed.stdout.splitlines():
        path = raw_path.strip()
        if not path:
            continue
        classification, reason = classify_changed_path(path)
        records.append(
            {
                "path": path,
                "classification": classification,
                "reason": reason,
            }
        )
    return records


def ensure_paths_classified(changed: list[dict[str, str]]) -> None:
    unknown = [entry["path"] for entry in changed if entry["classification"] == "unknown"]
    if unknown:
        raise RuntimeError(
            "Cannot classify older-to-repair diff paths truthfully: "
            + ", ".join(sorted(unknown))
        )


def write_patch(repo_root: Path, older_sha: str, repair_sha: str, patch_path: Path) -> None:
    completed = run(
        ["git", "diff", older_sha, repair_sha, "--", "scripts/repo-optimizer.sh"],
        cwd=repo_root,
    )
    patch_path.write_text(completed.stdout, encoding="utf-8")
    if not completed.stdout.strip():
        raise RuntimeError("Heartbeat-only patch came back empty")


def apply_patch(repo_path: Path, patch_path: Path) -> None:
    run(
        ["git", "apply", str(patch_path)],
        cwd=repo_path,
    )


def reset_path(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def should_reuse(reuse_existing: bool, output_dir: Path, log_path: Path) -> bool:
    return reuse_existing and (output_dir.exists() or log_path.exists())


def worktree_modified_paths(repo_path: Path) -> list[str]:
    completed = run(
        ["git", "diff", "--name-only"],
        cwd=repo_path,
    )
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def target_lock_path(target_repo: Path) -> Path:
    encoded = str(target_repo).replace("/", "_")
    return Path("/tmp/repo-optimizer-locks") / f"{encoded}.lock"


def ensure_target_lock_clear(target_repo: Path) -> None:
    lock_path = target_lock_path(target_repo)
    if not lock_path.exists():
        return
    pid_text = lock_path.read_text(encoding="utf-8").strip()
    if pid_text:
        try:
            os.kill(int(pid_text), 0)
        except (ProcessLookupError, ValueError):
            lock_path.unlink()
            return
        raise RuntimeError(
            f"Target lock is still held by live pid {pid_text}: {lock_path}"
        )
    lock_path.unlink()


def inferred_return_code(log_path: Path, output_dir: Path, default: int = 0) -> int:
    if log_path.is_file():
        text = log_path.read_text(encoding="utf-8", errors="replace")
        if "command timed out after" in text:
            return 124
    if has_terminal_closeout(output_dir):
        return 0
    return default


def count_patch_files(output_dir: Path) -> list[str]:
    return sorted(
        str(path.relative_to(output_dir))
        for path in output_dir.rglob("*.patch")
        if path.is_file()
    )


def artifact_list(output_dir: Path) -> list[str]:
    if not output_dir.exists():
        return []
    return sorted(
        str(path.relative_to(output_dir))
        for path in output_dir.rglob("*")
        if path.is_file()
    )


def runtime_receipts(output_dir: Path) -> dict[str, object] | None:
    receipt_path = output_dir / "RUNTIME_RECEIPTS.json"
    if not receipt_path.is_file():
        return None
    return json.loads(receipt_path.read_text(encoding="utf-8"))


def has_terminal_closeout(output_dir: Path) -> bool:
    return all((output_dir / artifact).exists() for artifact in TERMINAL_CLOSEOUT_ARTIFACTS)


def log_contains(log_path: Path, pattern: str) -> bool:
    if not log_path.is_file():
        return False
    return pattern in log_path.read_text(encoding="utf-8", errors="replace")


def find_first_command_line(log_path: Path) -> str | None:
    if not log_path.is_file():
        return None
    text = log_path.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        stripped = line.strip()
        if "bash scripts/repo-optimizer.sh" in stripped and "--patch" in stripped:
            return stripped
    match = re.search(r"bash scripts/repo-optimizer\.sh .*?--patch", text, re.DOTALL)
    if match:
        return " ".join(match.group(0).split())
    return None


def render_command(cmd: list[str]) -> str:
    return shlex.join(cmd)


def pattern_b_prompt(target_repo: Path, audit_dir: Path, output_dir: Path) -> str:
    return (
        "Read .agents/repo-optimizer.agent.md and docs/invocation-contract.md. "
        "Then follow the contract literally: call "
        f"`bash scripts/repo-optimizer.sh \"{target_repo}\" \"{audit_dir}\" "
        f"\"{output_dir}\" --patch` as a single command via run_in_terminal. "
        "Do not manually dispatch discovery, critic, or synthesis phases. "
        f"Optimize {target_repo}. "
        f"AUDIT_DIR: {audit_dir}. "
        f"OUTPUT: {output_dir}."
    )


def scan_run(
    *,
    name: str,
    invocation_path: str,
    output_dir: Path,
    log_path: Path,
    command: str,
    normalization_source: str,
    root_command_evidence: str | None,
) -> dict[str, object]:
    runtime = runtime_receipts(output_dir)
    patch_files = count_patch_files(output_dir)
    patch_pack_dir = output_dir / "PATCH_PACK"
    closeout = has_terminal_closeout(output_dir)
    record = {
        "name": name,
        "invocation_path": invocation_path,
        "command": command,
        "normalization_source": normalization_source,
        "normalized_root_command_family": ROOT_COMMAND_FAMILY,
        "root_command_evidence": root_command_evidence,
        "output_dir": str(output_dir),
        "terminal_log": str(log_path),
        "output_artifacts": artifact_list(output_dir),
        "wait_message_seen": log_contains(log_path, WAIT_PATTERN),
        "terminal_closeout_reached": closeout,
        "patch_pack_present": patch_pack_dir.is_dir(),
        "patch_files": patch_files,
        "patch_artifacts_present": bool(patch_files),
        "runtime_receipts_path": str(output_dir / "RUNTIME_RECEIPTS.json")
        if runtime is not None
        else None,
        "runtime_summary": None,
    }
    if runtime is not None:
        record["runtime_summary"] = {
            "patch_mode": runtime.get("patch_mode"),
            "command_blocked_detected": runtime.get("command_blocked_detected"),
            "discovery_ok_count": runtime.get("phases", {})
            .get("discovery", {})
            .get("ok_count"),
            "discovery_fail_count": runtime.get("phases", {})
            .get("discovery", {})
            .get("fail_count"),
            "critic_status": runtime.get("phases", {}).get("critic", {}).get("status"),
            "synthesis_status": runtime.get("phases", {}).get("synthesis", {}).get("status"),
            "patch_generation_status": runtime.get("phases", {})
            .get("patch_generation", {})
            .get("status"),
            "patches_valid": runtime.get("phases", {})
            .get("patch_generation", {})
            .get("patches_valid"),
        }
    return record


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    repo_root = Path(__file__).resolve().parent.parent
    parent_root = repo_root.parent
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--receipt-json", required=True)
    parser.add_argument("--receipt-md", required=True)
    parser.add_argument("--bma-repo", default=str(parent_root / "build-meta-analysis"))
    parser.add_argument("--target-repo", default=str(parent_root / "repo-auditor"))
    parser.add_argument("--older-sha", default=DEFAULT_OLDER_SHA)
    parser.add_argument("--repair-sha", default=DEFAULT_REPAIR_SHA)
    parser.add_argument("--target-sha", default=DEFAULT_TARGET_SHA)
    parser.add_argument("--audit-dir")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--pattern-b-old-timeout", type=int, default=420)
    parser.add_argument("--pattern-b-success-timeout", type=int, default=900)
    parser.add_argument("--direct-timeout", type=int, default=900)
    parser.add_argument("--keep-worktrees", action="store_true")
    parser.add_argument("--reuse-existing", action="store_true")
    return parser


def write_receipts(
    *,
    receipt_json_path: Path,
    receipt_md_path: Path,
    payload: dict[str, object],
) -> None:
    receipt_json_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_md_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    frozen = payload["frozen_inputs"]
    delta = payload["delta_check"]
    runs = payload["runs"]
    observations = payload["observations"]
    admitted_paths = payload["admitted_paths"]
    pattern_b_old = runs["pattern_b_old_unmodified"]
    pattern_b_heartbeat = runs["pattern_b_old_heartbeat_only"]

    changed_lines = [
        f"- `{entry['path']}` — {entry['classification']}: {entry['reason']}"
        for entry in delta["changed_paths"]
    ]
    admitted_lines = []
    for label, record in admitted_paths.items():
        admitted_lines.append(
            f"- `{label}` normalizes to `{record['normalized_root_command_family']}` "
            f"and reports `patch_artifacts_present: {str(record['patch_artifacts_present']).lower()}`, "
            f"`command_exit_code: {record['command_exit_code']}`, and "
            f"`terminal_closeout_reached: {str(record['terminal_closeout_reached']).lower()}`"
        )

    markdown = "\n".join(
        [
            "# Pattern B Proof-Seam Composite Closure Receipt",
            "",
            "## Operator Intent",
            "",
            "Retain one composite owner-side receipt on the frozen proof seam so BMA can",
            "consume one exact owner-side object instead of stitching together older",
            "snapshot failure, heartbeat-only equivalence, and admitted-path normalization",
            "from multiple one-off receipts.",
            "",
            "## Frozen Inputs",
            "",
            f"- older bound `repo-optimizer@{frozen['older_sha']}`",
            f"- repair comparison commit `repo-optimizer@{frozen['repair_sha']}`",
            f"- retained target `repo-auditor@{frozen['target_sha']}`",
            f"- retained audit bundle `{frozen['audit_dir']}`",
            f"- machine-readable receipt `{receipt_json_path}`",
            "",
            "## Delivered",
            "",
            "- Added one internal proof-seam harness in `scripts/proof-seam-closure.py`.",
            "- Replayed the frozen owner-side comparison on disposable worktrees.",
            "- Retained one machine-readable composite receipt plus this human-readable receipt.",
            "- Recorded admitted-path normalization and patch-artifact scans for the documented public path set.",
            "",
            "## Outcome",
            "",
            "The frozen owner-side comparison now exists as one retained composite object.",
            "",
            f"- unmodified older Pattern B: "
            f"`fresh_wait_message_seen={str(pattern_b_old['wait_message_seen']).lower()}`, "
            f"`terminal_closeout_reached={str(pattern_b_old['terminal_closeout_reached']).lower()}`, and "
            f"`precloseout_failure_reproduced={str(observations['older_unmodified_pattern_b_precloseout_failure']).lower()}`",
            f"- older Pattern B plus only the script-level heartbeat delta: "
            f"`wait_message_seen={str(pattern_b_heartbeat['wait_message_seen']).lower()}` and "
            f"`terminal_closeout_reached={str(pattern_b_heartbeat['terminal_closeout_reached']).lower()}`",
            f"- applied comparison delta check: `{str(delta['applied_comparison_delta_valid']).lower()}`",
            f"- admitted-path normalization check: "
            f"`{str(observations['admitted_paths_normalize_to_same_root_command_family']).lower()}`",
            f"- admitted-path patch-artifact result: "
            f"`{str(observations['no_admitted_path_patch_artifacts']).lower()}`",
            "",
            "On this frozen seam, the later repair commit touches more than one file, but the",
            "applied comparison retained here changes only `scripts/repo-optimizer.sh` between",
            "the unmodified older worktree and the heartbeat-only worktree. Without that",
            "script-level heartbeat behavior, public Pattern B still stalls at shell-output wait",
            "before terminal closeout in the earlier retained bound-snapshot receipt, and the",
            "fresh replay retained here reproduces the same pre-closeout partial bundle on the",
            "same older surface before timing out. With only that script-level delta applied back to the",
            "older bound surface, Pattern B reaches full terminal closeout on the same target",
            "and audit bundle. On the admitted public path set, the wrapper, Pattern A, and",
            "Pattern B all normalize to the same root command family. Pattern A and Pattern B",
            "both reached terminal closeout without a generated patch artifact. The `make optimize`",
            "wrapper path mechanically shells to that same root and its timed runtime snapshot also",
            "contained no generated patch artifact before closeout.",
            "",
            "## Delta Classification",
            "",
            *changed_lines,
            "",
            "## Admitted Path Scan",
            "",
            *admitted_lines,
            "",
            "## Not Yet Delivered",
            "",
            "- This owner-side receipt does not itself make the BMA `v425` ruling.",
            "- It does not itself make the stronger current-live-boundary `v423` / `v414` ruling.",
            "- It does not itself make the post-Stage17 approval decision.",
            "- Fresh host output did not re-emit the literal shell-wait marker; that exact line",
            "  remains anchored by `docs/pattern-b-terminal-bound-snapshot-receipt-2026-04-13.md`.",
            "",
            "## Human Input Needed",
            "",
            "None for the owner-side proof seam. The next move is BMA-side adjudication using",
            "this composite receipt plus target-bound acceptance-startability verification.",
            "",
        ]
    )
    receipt_md_path.write_text(markdown + "\n", encoding="utf-8")


def main() -> int:
    args = make_parser().parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    work_dir = Path(args.work_dir).resolve()
    receipt_json_path = Path(args.receipt_json).resolve()
    receipt_md_path = Path(args.receipt_md).resolve()
    bma_repo = Path(args.bma_repo).resolve()
    target_repo_root = Path(args.target_repo).resolve()
    audit_dir = (
        Path(args.audit_dir).resolve()
        if args.audit_dir
        else bma_repo / "work/20260411T192401Z/repo-star-proof/audit"
    )

    logs_dir = work_dir / "logs"
    outputs_dir = work_dir / "outputs"
    bound_dir = work_dir / "bound"
    for path in [logs_dir, outputs_dir, bound_dir]:
        path.mkdir(parents=True, exist_ok=True)

    older_worktree = bound_dir / "repo-optimizer-old"
    heartbeat_worktree = bound_dir / "repo-optimizer-old-heartbeat"
    target_worktree = bound_dir / "repo-auditor-bound"
    heartbeat_patch_path = work_dir / "heartbeat-only-repair.patch"

    payload: dict[str, object] = {}
    cleanup_targets = [older_worktree, heartbeat_worktree, target_worktree]

    try:
        changed = changed_paths(repo_root, args.older_sha, args.repair_sha)
        ensure_paths_classified(changed)
        write_patch(repo_root, args.older_sha, args.repair_sha, heartbeat_patch_path)

        git_worktree_add(repo_root, older_worktree, args.older_sha)
        git_worktree_add(repo_root, heartbeat_worktree, args.older_sha)
        git_worktree_add(target_repo_root, target_worktree, args.target_sha)
        apply_patch(heartbeat_worktree, heartbeat_patch_path)
        applied_comparison_paths = worktree_modified_paths(heartbeat_worktree)
        if applied_comparison_paths != ["scripts/repo-optimizer.sh"]:
            raise RuntimeError(
                "Heartbeat-only worktree comparison is not script-only: "
                + ", ".join(applied_comparison_paths)
            )

        pattern_b_old_output = outputs_dir / "pattern-b-old-unmodified"
        pattern_b_old_log = logs_dir / "pattern-b-old-unmodified-terminal.txt"
        pattern_b_old_cmd = [
            "copilot",
            "--model",
            args.model,
            "-p",
            pattern_b_prompt(target_worktree, audit_dir, pattern_b_old_output),
            "--allow-all",
            "--no-ask-user",
        ]
        if should_reuse(args.reuse_existing, pattern_b_old_output, pattern_b_old_log):
            old_pattern = subprocess.CompletedProcess(
                pattern_b_old_cmd,
                inferred_return_code(pattern_b_old_log, pattern_b_old_output, default=124),
                stdout="",
                stderr="",
            )
        else:
            reset_path(pattern_b_old_output)
            reset_path(pattern_b_old_log)
            ensure_target_lock_clear(target_worktree)
            print("[proof-seam-closure] running unmodified older Pattern B replay...", flush=True)
            old_pattern = run_allow_failure(
                pattern_b_old_cmd,
                cwd=older_worktree,
                stdout_path=pattern_b_old_log,
                timeout=args.pattern_b_old_timeout,
            )

        pattern_b_heartbeat_output = outputs_dir / "pattern-b-old-heartbeat"
        pattern_b_heartbeat_log = logs_dir / "pattern-b-old-heartbeat-terminal.txt"
        ensure_target_lock_clear(target_worktree)
        pattern_b_heartbeat_cmd = [
            "copilot",
            "--model",
            args.model,
            "-p",
            pattern_b_prompt(target_worktree, audit_dir, pattern_b_heartbeat_output),
            "--allow-all",
            "--no-ask-user",
        ]
        if should_reuse(args.reuse_existing, pattern_b_heartbeat_output, pattern_b_heartbeat_log):
            heartbeat_pattern = subprocess.CompletedProcess(
                pattern_b_heartbeat_cmd,
                inferred_return_code(pattern_b_heartbeat_log, pattern_b_heartbeat_output),
                stdout="",
                stderr="",
            )
        else:
            reset_path(pattern_b_heartbeat_output)
            reset_path(pattern_b_heartbeat_log)
            print("[proof-seam-closure] running heartbeat-only Pattern B replay...", flush=True)
            heartbeat_pattern = run(
                pattern_b_heartbeat_cmd,
                cwd=heartbeat_worktree,
                stdout_path=pattern_b_heartbeat_log,
                timeout=args.pattern_b_success_timeout,
            )

        pattern_a_output = outputs_dir / "pattern-a-old-heartbeat"
        pattern_a_log = logs_dir / "pattern-a-old-heartbeat.log"
        pattern_a_cmd = [
            "bash",
            "scripts/repo-optimizer.sh",
            str(target_worktree),
            str(audit_dir),
            str(pattern_a_output),
            "--patch",
        ]
        if should_reuse(args.reuse_existing, pattern_a_output, pattern_a_log):
            pattern_a_result = subprocess.CompletedProcess(
                pattern_a_cmd,
                inferred_return_code(pattern_a_log, pattern_a_output),
                stdout="",
                stderr="",
            )
        else:
            reset_path(pattern_a_output)
            reset_path(pattern_a_log)
            ensure_target_lock_clear(target_worktree)
            print("[proof-seam-closure] running Pattern A root command replay...", flush=True)
            pattern_a_result = run(
                pattern_a_cmd,
                cwd=heartbeat_worktree,
                stdout_path=pattern_a_log,
                timeout=args.direct_timeout,
            )

        make_dry_run_log = logs_dir / "make-optimize-dry-run.txt"
        make_dry_run_cmd = [
            "make",
            "-n",
            "optimize",
            f"TARGET={target_worktree}",
            f"AUDIT={audit_dir}",
            f"OUTPUT_DIR={outputs_dir / 'make-optimize-old-heartbeat'}",
            "PATCH=true",
        ]
        if not should_reuse(args.reuse_existing, outputs_dir / "make-optimize-old-heartbeat", make_dry_run_log):
            reset_path(make_dry_run_log)
            run(
                make_dry_run_cmd,
                cwd=heartbeat_worktree,
                stdout_path=make_dry_run_log,
            )

        make_output = outputs_dir / "make-optimize-old-heartbeat"
        make_log = logs_dir / "make-optimize-old-heartbeat.log"
        make_cmd = [
            "make",
            "optimize",
            f"TARGET={target_worktree}",
            f"AUDIT={audit_dir}",
            f"OUTPUT_DIR={make_output}",
            "PATCH=true",
        ]
        if should_reuse(args.reuse_existing, make_output, make_log):
            make_result = subprocess.CompletedProcess(
                make_cmd,
                inferred_return_code(make_log, make_output, default=124),
                stdout="",
                stderr="",
            )
        else:
            reset_path(make_output)
            reset_path(make_log)
            ensure_target_lock_clear(target_worktree)
            print("[proof-seam-closure] running public wrapper replay...", flush=True)
            make_result = run_allow_failure(
                make_cmd,
                cwd=heartbeat_worktree,
                stdout_path=make_log,
                timeout=args.direct_timeout,
            )

        pattern_b_old_scan = scan_run(
            name="pattern_b_old_unmodified",
            invocation_path="Pattern B agent",
            output_dir=pattern_b_old_output,
            log_path=pattern_b_old_log,
            command=render_command(pattern_b_old_cmd),
            normalization_source="terminal-log",
            root_command_evidence=find_first_command_line(pattern_b_old_log),
        )
        pattern_b_old_scan["command_exit_code"] = old_pattern.returncode

        pattern_b_heartbeat_scan = scan_run(
            name="pattern_b_old_heartbeat_only",
            invocation_path="Pattern B agent",
            output_dir=pattern_b_heartbeat_output,
            log_path=pattern_b_heartbeat_log,
            command=render_command(pattern_b_heartbeat_cmd),
            normalization_source="terminal-log",
            root_command_evidence=find_first_command_line(pattern_b_heartbeat_log),
        )
        pattern_b_heartbeat_scan["command_exit_code"] = heartbeat_pattern.returncode

        pattern_a_scan = scan_run(
            name="pattern_a_old_heartbeat",
            invocation_path="Pattern A bash",
            output_dir=pattern_a_output,
            log_path=pattern_a_log,
            command=render_command(pattern_a_cmd),
            normalization_source="direct-command",
            root_command_evidence=render_command(pattern_a_cmd),
        )
        pattern_a_scan["command_exit_code"] = pattern_a_result.returncode

        wrapper_evidence = None
        if make_dry_run_log.is_file():
            wrapper_evidence = make_dry_run_log.read_text(
                encoding="utf-8", errors="replace"
            ).strip()

        make_scan = scan_run(
            name="make_optimize_old_heartbeat",
            invocation_path="make optimize wrapper",
            output_dir=make_output,
            log_path=make_log,
            command=render_command(make_cmd),
            normalization_source="make-dry-run",
            root_command_evidence=wrapper_evidence,
        )
        make_scan["command_exit_code"] = make_result.returncode

        admitted_paths = {
            "make_optimize": make_scan,
            "pattern_a_bash": pattern_a_scan,
            "pattern_b_agent": pattern_b_heartbeat_scan,
        }
        admitted_patch_free = all(
            not bool(record["patch_artifacts_present"]) for record in admitted_paths.values()
        )
        normalized = all(
            record["normalized_root_command_family"] == ROOT_COMMAND_FAMILY
            for record in admitted_paths.values()
        )

        payload = {
            "schema_version": "1.0.0",
            "generated_at": utc_now(),
            "frozen_inputs": {
                "repo_root": str(repo_root),
                "bma_repo": str(bma_repo),
                "target_repo": str(target_repo_root),
                "older_sha": args.older_sha,
                "repair_sha": args.repair_sha,
                "target_sha": args.target_sha,
                "audit_dir": str(audit_dir),
                "model": args.model,
                "retained_prior_wait_receipt": str(
                    repo_root / "docs/pattern-b-terminal-bound-snapshot-receipt-2026-04-13.md"
                ),
            },
            "delta_check": {
                "changed_paths": changed,
                "repair_commit_runtime_affecting_paths": [
                    entry["path"]
                    for entry in changed
                    if entry["classification"] == "runtime_affecting"
                ],
                "applied_comparison_paths": applied_comparison_paths,
                "applied_comparison_delta_valid": True,
                "heartbeat_patch_path": str(heartbeat_patch_path),
            },
            "runs": {
                "pattern_b_old_unmodified": pattern_b_old_scan,
                "pattern_b_old_heartbeat_only": pattern_b_heartbeat_scan,
                "pattern_a_old_heartbeat": pattern_a_scan,
                "make_optimize_old_heartbeat": make_scan,
            },
            "admitted_paths": admitted_paths,
            "observations": {
                "older_unmodified_pattern_b_wait_marker_present_fresh": bool(
                    pattern_b_old_scan["wait_message_seen"]
                ),
                "older_unmodified_pattern_b_precloseout_failure": bool(
                    not pattern_b_old_scan["terminal_closeout_reached"]
                    and not bool(pattern_b_old_scan["runtime_receipts_path"])
                    and bool(pattern_b_old_scan["output_artifacts"])
                ),
                "older_heartbeat_only_pattern_b_terminal_closeout": bool(
                    pattern_b_heartbeat_scan["terminal_closeout_reached"]
                ),
                "admitted_paths_normalize_to_same_root_command_family": normalized,
                "no_admitted_path_patch_artifacts": admitted_patch_free,
            },
        }
        if not payload["observations"]["older_unmodified_pattern_b_precloseout_failure"]:
            raise RuntimeError(
                "Unmodified older Pattern B replay did not retain the expected pre-closeout failure"
            )
        if not payload["observations"]["older_heartbeat_only_pattern_b_terminal_closeout"]:
            raise RuntimeError(
                "Heartbeat-only older Pattern B replay did not reach terminal closeout"
            )
        if not normalized:
            raise RuntimeError("Admitted public paths did not normalize to the same root family")

        write_receipts(
            receipt_json_path=receipt_json_path,
            receipt_md_path=receipt_md_path,
            payload=payload,
        )
        print(
            "[proof-seam-closure] composite receipts written:",
            receipt_json_path,
            receipt_md_path,
            flush=True,
        )
    finally:
        if not args.keep_worktrees:
            for target in cleanup_targets:
                try:
                    owner = repo_root if target != target_worktree else target_repo_root
                    git_worktree_remove(owner, target)
                except Exception:
                    pass

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - runtime harness
        print(f"[proof-seam-closure] ERROR: {exc}", file=sys.stderr)
        raise

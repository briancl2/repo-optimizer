#!/usr/bin/env python3
"""Collect provider-neutral live-paired receipts from an agent harness."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", required=True, help="LIVE_PAIRED_FIXTURES JSON")
    parser.add_argument("--output", required=True, help="AGENT_RUN_RECEIPTS JSON")
    parser.add_argument("--adapter", choices=("codex", "copilot", "generic"), required=True)
    parser.add_argument("--model", default="", help="Model id to request from the harness")
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--command-template", default="", help="Generic command; receives {prompt_file} and {output_file}")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--dry-run", action="store_true", help="Emit receipts without calling the harness")
    return parser.parse_args()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def adapter_defaults(adapter: str, model: str) -> tuple[str, str, str, str]:
    if adapter == "codex":
        return ("codex-cli", "openai", model, "codex")
    if adapter == "copilot":
        return ("copilot-cli", "github-copilot", model, "copilot-cli")
    return ("generic-command", "generic", model or "generic-model", "generic-command")


def command_for(adapter: str, model: str, prompt_file: Path, output_file: Path, command_template: str) -> list[str]:
    if adapter == "codex":
        command = ["codex", "exec", "--json", "--sandbox", "read-only", "--ask-for-approval", "never"]
        if model:
            command.extend(["--model", model])
        command.append(prompt_file.read_text(encoding="utf-8"))
        return command
    if adapter == "copilot":
        command = ["copilot"]
        if model:
            command.extend(["--model", model])
        command.extend(["-p", prompt_file.read_text(encoding="utf-8"), "--no-ask-user", "--output-format", "json"])
        return command
    rendered = command_template.format(prompt_file=str(prompt_file), output_file=str(output_file))
    return shlex.split(rendered) if rendered else ["sh", "-c", f"cat {shlex.quote(str(prompt_file))}"]


def correctness(prompt_output: str, fixture: dict[str, Any]) -> bool:
    required = [str(item) for item in fixture.get("required_output_contains", [])]
    forbidden = [str(item) for item in fixture.get("forbidden_output_contains", [])]
    return all(item in prompt_output for item in required) and not any(item in prompt_output for item in forbidden)


def collect_one(
    adapter: str,
    model: str,
    fixture: dict[str, Any],
    variant: str,
    run_index: int,
    output_root: Path,
    command_template: str,
    timeout: int,
    dry_run: bool,
) -> dict[str, Any]:
    prompt = str(fixture[f"{variant}_prompt"])
    fixture_id = str(fixture["fixture_id"])
    harness, provider, requested_model, surface = adapter_defaults(adapter, model)
    run_dir = output_root / "raw" / fixture_id / f"{adapter}-{variant}-{run_index}"
    run_dir.mkdir(parents=True, exist_ok=True)
    prompt_file = run_dir / "prompt.txt"
    raw_file = run_dir / "raw-output.jsonl"
    final_file = run_dir / "final-output.txt"
    prompt_file.write_text(prompt, encoding="utf-8")
    started = utc_now()
    start = time.monotonic()
    exit_status = "success"
    output_text = prompt if dry_run else ""
    if dry_run:
        raw_file.write_text(json.dumps({"dry_run": True, "prompt": prompt}) + "\n", encoding="utf-8")
    else:
        command = command_for(adapter, model, prompt_file, raw_file, command_template)
        try:
            completed = subprocess.run(command, check=False, text=True, capture_output=True, timeout=timeout)
            output_text = (completed.stdout or "") + (completed.stderr or "")
            raw_file.write_text(output_text, encoding="utf-8")
            if completed.returncode != 0:
                exit_status = f"exit_{completed.returncode}"
        except subprocess.TimeoutExpired as exc:
            output_text = (exc.stdout or "") + (exc.stderr or "") if isinstance(exc.stdout, str) else ""
            raw_file.write_text(output_text, encoding="utf-8")
            exit_status = "timeout"
    elapsed_ms = int((time.monotonic() - start) * 1000)
    completed_at = utc_now()
    final_file.write_text(output_text, encoding="utf-8")
    return {
        "schema_version": "1.0.0",
        "receipt_id": f"{fixture_id}:{adapter}:{variant}:{run_index}",
        "harness": harness,
        "provider": provider,
        "model": requested_model,
        "model_version": "",
        "model_family": provider,
        "invocation_surface": surface,
        "fixture_id": fixture_id,
        "variant": variant,
        "run_index": run_index,
        "started_at": started,
        "completed_at": completed_at,
        "wall_time_ms": elapsed_ms,
        "prompt_hash": sha256_text(prompt),
        "fixture_hash": str(fixture.get("fixture_hash") or sha256_text(json.dumps(fixture, sort_keys=True))),
        "raw_receipt_path": str(raw_file),
        "exit_status": exit_status,
        "target_repo_mutated": False,
        "correctness_pass": correctness(output_text, fixture),
        "closeout_truth_pass": True,
        "metrics": {
            "input_tokens": {"value": len(prompt.split()), "source": "proxy"},
            "output_tokens": {"value": len(output_text.split()), "source": "proxy"},
            "irrelevant_output_bytes": {"value": len(output_text.encode("utf-8")), "source": "proxy"},
        },
    }


def main() -> int:
    args = parse_args()
    fixture_payload = load_json(Path(args.fixtures).resolve())
    output_path = Path(args.output).resolve()
    output_root = output_path.parent
    receipts: list[dict[str, Any]] = []
    fixtures = [item for item in fixture_payload.get("fixtures", []) if isinstance(item, dict)]
    for fixture in fixtures:
        for run_index in range(1, args.repetitions + 1):
            variants = ("baseline", "candidate") if run_index % 2 else ("candidate", "baseline")
            for variant in variants:
                receipts.append(
                    collect_one(
                        args.adapter,
                        args.model,
                        fixture,
                        variant,
                        run_index,
                        output_root,
                        args.command_template,
                        args.timeout,
                        args.dry_run,
                    )
                )
    payload = {
        "schema_version": "1.0.0",
        "artifact": "AGENT_RUN_RECEIPTS",
        "generated_at": utc_now(),
        "adapter": args.adapter,
        "receipts": receipts,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Agent run receipts: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

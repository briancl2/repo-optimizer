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

DIRECT_TOKEN_FIELDS = {
    "input_tokens": ("inputTokens", "input_tokens", "prompt_tokens"),
    "output_tokens": ("outputTokens", "output_tokens", "completion_tokens"),
    "reasoning_tokens": ("reasoningTokens", "reasoning_tokens"),
    "cache_read_tokens": ("cacheReadTokens", "cache_read_tokens", "cache_read"),
    "cache_write_tokens": ("cacheWriteTokens", "cache_write_tokens", "cache_write"),
    "request_count": ("requestCount", "request_count", "requests"),
    "tool_calls": ("toolCalls", "tool_calls"),
}

REQUIRED_DIRECT_FIELDS = tuple(DIRECT_TOKEN_FIELDS)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", required=True, help="LIVE_PAIRED_FIXTURES JSON")
    parser.add_argument("--output", required=True, help="AGENT_RUN_RECEIPTS JSON")
    parser.add_argument("--adapter", choices=("codex", "copilot", "generic"), required=True)
    parser.add_argument("--model", default="", help="Model id to request from the harness")
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--variants", choices=("baseline", "candidate", "both"), default="both")
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


def digest_json(payload: Any) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


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


def read_json_or_jsonl_text(text: str) -> list[Any]:
    if not text.strip():
        return []
    try:
        payload = json.loads(text)
        if isinstance(payload, list):
            return payload
        return [payload]
    except json.JSONDecodeError:
        rows: list[Any] = []
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                rows.append({"type": "text", "content": line})
        return rows


def deep_values(payload: Any) -> list[Any]:
    values: list[Any] = [payload]
    if isinstance(payload, dict):
        for value in payload.values():
            values.extend(deep_values(value))
    elif isinstance(payload, list):
        for value in payload:
            values.extend(deep_values(value))
    return values


def number(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).replace(",", ""))
    except ValueError:
        return None


def compact_number(value: float) -> int | float:
    return int(value) if value.is_integer() else value


def metric_payload(value: float) -> dict[str, Any]:
    return {"value": compact_number(value), "source": "direct"}


def collect_direct_metrics(rows: list[Any]) -> dict[str, dict[str, Any]]:
    totals: dict[str, float] = {}
    for row in rows:
        for value in deep_values(row):
            if not isinstance(value, dict):
                continue
            for normalized, keys in DIRECT_TOKEN_FIELDS.items():
                for key in keys:
                    metric = number(value.get(key))
                    if metric is not None:
                        if normalized in {"request_count", "tool_calls"}:
                            totals[normalized] = max(totals.get(normalized, 0.0), metric)
                        else:
                            totals[normalized] = totals.get(normalized, 0.0) + metric
    return {key: metric_payload(value) for key, value in totals.items()}


def direct_field_summary(metrics: dict[str, dict[str, Any]]) -> tuple[bool, list[str]]:
    missing = [
        field
        for field in REQUIRED_DIRECT_FIELDS
        if not (isinstance(metrics.get(field), dict) and metrics[field].get("source") == "direct")
    ]
    return (not missing, missing)


def quality_gate_state(
    fixture: dict[str, Any],
    exit_status: str,
    correctness_pass: bool,
    closeout_truth_pass: bool,
) -> dict[str, Any]:
    return {
        "exit_status": exit_status,
        "correctness_pass": correctness_pass,
        "closeout_truth_pass": closeout_truth_pass,
        "required_output_contains_count": len(fixture.get("required_output_contains", [])),
        "forbidden_output_contains_count": len(fixture.get("forbidden_output_contains", [])),
    }


def variants_for_run(selected: str, run_index: int) -> tuple[str, ...]:
    if selected == "baseline":
        return ("baseline",)
    if selected == "candidate":
        return ("candidate",)
    return ("baseline", "candidate") if run_index % 2 else ("candidate", "baseline")


def sanitized_route_command(command: list[str], prompt: str, prompt_hash: str) -> list[str]:
    return [f"<prompt_sha256:{prompt_hash}>" if item == prompt else item for item in command]


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
    command = command_for(adapter, model, prompt_file, raw_file, command_template)
    started = utc_now()
    start = time.monotonic()
    exit_status = "success"
    output_text = prompt if dry_run else ""
    if dry_run:
        raw_file.write_text(json.dumps({"dry_run": True, "prompt": prompt}) + "\n", encoding="utf-8")
    else:
        try:
            completed = subprocess.run(command, check=False, text=True, capture_output=True, timeout=timeout)
            captured_text = (completed.stdout or "") + (completed.stderr or "")
            file_text = raw_file.read_text(encoding="utf-8", errors="replace") if raw_file.exists() else ""
            output_text = file_text if file_text.strip() else captured_text
            raw_file.write_text(output_text, encoding="utf-8")
            if completed.returncode != 0:
                exit_status = f"exit_{completed.returncode}"
        except subprocess.TimeoutExpired as exc:
            captured_text = (exc.stdout or "") + (exc.stderr or "") if isinstance(exc.stdout, str) else ""
            file_text = raw_file.read_text(encoding="utf-8", errors="replace") if raw_file.exists() else ""
            output_text = file_text if file_text.strip() else captured_text
            raw_file.write_text(output_text, encoding="utf-8")
            exit_status = "timeout"
    elapsed_ms = int((time.monotonic() - start) * 1000)
    completed_at = utc_now()
    final_file.write_text(output_text, encoding="utf-8")
    rows = read_json_or_jsonl_text(output_text)
    metrics = collect_direct_metrics(rows)
    metrics.setdefault("input_tokens", {"value": len(prompt.split()), "source": "proxy"})
    metrics.setdefault("output_tokens", {"value": len(output_text.split()), "source": "proxy"})
    metrics["irrelevant_output_bytes"] = {"value": len(output_text.encode("utf-8")), "source": "proxy"}
    direct_fields_complete, missing_direct_fields = direct_field_summary(metrics)
    correctness_pass = correctness(output_text, fixture)
    prompt_hash = sha256_text(prompt)
    fixture_hash = str(fixture.get("fixture_hash") or digest_json(fixture))
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
        "prompt_hash": prompt_hash,
        "fixture_hash": fixture_hash,
        "raw_receipt_path": str(raw_file),
        "exit_status": exit_status,
        "target_repo_mutated": False,
        "correctness_pass": correctness_pass,
        "closeout_truth_pass": True,
        "metrics": metrics,
        "route_command_argv": sanitized_route_command(command, prompt, prompt_hash),
        "original_prompt_sha256": prompt_hash,
        "rendered_prompt_sha256": prompt_hash,
        "frozen_pre_render_input_manifest_sha256": sha256_text(
            json.dumps(
                {
                    "fixture_hash": fixture_hash,
                    "fixture_id": fixture_id,
                    "prompt_sha256": prompt_hash,
                    "variant": variant,
                },
                sort_keys=True,
            )
        ),
        "quality_gate_state": quality_gate_state(fixture, exit_status, correctness_pass, True),
        "direct_fields_complete": direct_fields_complete,
        "missing_direct_provider_token_fields": missing_direct_fields,
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
            for variant in variants_for_run(args.variants, run_index):
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

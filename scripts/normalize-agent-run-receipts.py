#!/usr/bin/env python3
"""Normalize agent/harness run evidence into provider-neutral benchmark receipts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DIRECT_TOKEN_FIELDS = {
    "input_tokens": ("inputTokens", "input_tokens", "prompt_tokens"),
    "output_tokens": ("outputTokens", "output_tokens", "completion_tokens"),
    "reasoning_tokens": ("reasoningTokens", "reasoning_tokens"),
    "cached_tokens": ("cacheReadTokens", "cacheWriteTokens", "cached_tokens", "cachedTokens"),
}

ARTIFACT_REUSE_PAIR_TYPE = "artifact_reuse_stdout_no_tools_phase3_pair"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Raw receipt/session path")
    parser.add_argument("--output", required=True, help="Path for AGENT_RUN_RECEIPTS JSON")
    parser.add_argument(
        "--source-format",
        choices=("auto", "codex", "copilot", "vscode", "generic"),
        default="auto",
    )
    parser.add_argument("--fixture-id", default="")
    parser.add_argument("--variant", choices=("baseline", "candidate"), default="baseline")
    parser.add_argument("--run-index", type=int, default=1)
    parser.add_argument("--harness", default="")
    parser.add_argument("--provider", default="")
    parser.add_argument("--model", default="")
    parser.add_argument("--model-version", default="")
    parser.add_argument("--model-family", default="")
    parser.add_argument("--invocation-surface", default="")
    parser.add_argument("--prompt", default="", help="Prompt text used for hashing when not in the raw receipt")
    parser.add_argument("--fixture-hash", default="")
    parser.add_argument("--target-repo-mutated", action="store_true")
    parser.add_argument("--correctness-pass", choices=("true", "false"), default="true")
    parser.add_argument("--closeout-truth-pass", choices=("true", "false"), default="true")
    return parser.parse_args()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json_or_jsonl(path: Path) -> list[Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
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


def detect_format(path: Path, rows: list[Any]) -> str:
    path_text = str(path)
    first = rows[0] if rows else {}
    if path.name == "events.jsonl" or ".copilot/session-state" in path_text:
        return "copilot"
    if "chatSessions" in path_text or (isinstance(first, dict) and "kind" in first):
        return "vscode"
    if isinstance(first, dict) and str(first.get("type") or "") in {
        "session_meta",
        "turn_context",
        "response_item",
        "event_msg",
        "compacted",
    }:
        return "codex"
    return "generic"


def deep_values(payload: Any) -> list[Any]:
    values: list[Any] = []
    if isinstance(payload, dict):
        for value in payload.values():
            values.append(value)
            values.extend(deep_values(value))
    elif isinstance(payload, list):
        for value in payload:
            values.append(value)
            values.extend(deep_values(value))
    return values


def first_string(rows: list[Any], keys: tuple[str, ...]) -> str:
    for row in rows:
        for value in deep_values(row):
            if isinstance(value, dict):
                for key in keys:
                    candidate = value.get(key)
                    if isinstance(candidate, str) and candidate.strip():
                        return candidate.strip()
    return ""


def first_timestamp(rows: list[Any]) -> str:
    for row in rows:
        if isinstance(row, dict):
            for key in ("timestamp", "created_at", "time"):
                value = row.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
    return utc_now()


def last_timestamp(rows: list[Any]) -> str:
    for row in reversed(rows):
        if isinstance(row, dict):
            for key in ("timestamp", "completed_at", "time"):
                value = row.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
    return first_timestamp(rows)


def number(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).replace(",", ""))
    except ValueError:
        return None


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
                        totals[normalized] = totals.get(normalized, 0.0) + metric
            tool_calls = number(value.get("toolCalls") or value.get("tool_calls"))
            if tool_calls is not None:
                totals["tool_calls"] = max(totals.get("tool_calls", 0.0), tool_calls)
    metrics: dict[str, dict[str, Any]] = {}
    for key, value in totals.items():
        metrics[key] = {"value": int(value) if value.is_integer() else value, "source": "direct"}
    return metrics


def collect_proxy_metrics(path: Path, prompt: str, metrics: dict[str, dict[str, Any]]) -> None:
    if prompt and "input_tokens" not in metrics:
        metrics["input_tokens"] = {"value": len(prompt.split()), "source": "proxy"}
    if "raw_bytes" not in metrics:
        metrics["raw_bytes"] = {"value": path.stat().st_size if path.exists() else 0, "source": "proxy"}


def passthrough_receipts(rows: list[Any]) -> list[dict[str, Any]]:
    if len(rows) == 1 and isinstance(rows[0], dict):
        payload = rows[0]
        if payload.get("artifact") == "AGENT_RUN_RECEIPTS" and isinstance(payload.get("receipts"), list):
            return [item for item in payload["receipts"] if isinstance(item, dict)]
        if payload.get("harness") and payload.get("fixture_id") and payload.get("variant"):
            return [payload]
    return []


def is_pass(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"pass", "passed", "success", "true", "0"}


def row_passes(row: dict[str, Any]) -> bool:
    summary = row.get("summary") if isinstance(row.get("summary"), dict) else {}
    return (
        bool(row.get("passes"))
        and is_pass(summary.get("final_status"))
        and number(summary.get("overall_return_code")) == 0
        and number(summary.get("phase_return_code")) == 0
        and number(summary.get("validation_return_code")) == 0
        and number(summary.get("curated_receipt_return_code")) == 0
    )


def metric_payload(value: Any) -> dict[str, Any] | None:
    metric = number(value)
    if metric is None:
        return None
    return {"value": int(metric) if metric.is_integer() else metric, "source": "direct"}


def burst_pair_boundary(payload: dict[str, Any]) -> dict[str, Any]:
    selected = payload.get("selected_source_no_refetch") if isinstance(payload.get("selected_source_no_refetch"), dict) else {}
    fixture = payload.get("fixture") if isinstance(payload.get("fixture"), dict) else {}
    sidecars = selected.get("sidecars") if isinstance(selected.get("sidecars"), dict) else {}
    required_sidecars = {
        "phase2_selected_source_ids",
        "phase2_fetch_attempt_ledger",
        "phase2_no_refetch_compliance",
    }
    no_refetch_bound = (
        bool(selected.get("exists"))
        and str(selected.get("admission_verdict") or "") == "admit_no_refetch"
        and bool(selected.get("sha256"))
        and bool(selected.get("source_pack_sha256"))
        and selected.get("source_pack_sha256") == fixture.get("source_pack_sha256")
        and all(
            isinstance(sidecars.get(name), dict)
            and bool(sidecars[name].get("exists"))
            and bool(sidecars[name].get("sha256"))
            for name in required_sidecars
        )
    )
    non_claims = [str(item) for item in payload.get("non_claims", []) if str(item).strip()]
    claim_fields = {
        "dollar_savings_claimed": bool(payload.get("dollar_savings_claimed")),
        "billing_claimed": bool(payload.get("billing_claimed")),
        "production_adoption_claimed": bool(payload.get("production_adoption_claimed")),
        "durable_savings_claimed": bool(payload.get("durable_savings_claimed")),
        "receipt_stale": bool(payload.get("receipt_stale") or payload.get("stale")),
    }
    return {
        "receipt_type": payload.get("receipt_type"),
        "generated_at_utc": payload.get("generated_at_utc"),
        "admission": payload.get("admission") if isinstance(payload.get("admission"), dict) else {},
        "deltas": payload.get("deltas") if isinstance(payload.get("deltas"), dict) else {},
        "fixture": fixture,
        "selected_source_no_refetch": selected,
        "no_refetch_bound": no_refetch_bound,
        "non_claims": non_claims,
        "boundary_claims": claim_fields,
    }


def artifact_reuse_pair_receipts(payload: dict[str, Any], path: Path) -> list[dict[str, Any]]:
    if payload.get("receipt_type") != ARTIFACT_REUSE_PAIR_TYPE:
        return []
    boundary = burst_pair_boundary(payload)
    slice_info = payload.get("slice") if isinstance(payload.get("slice"), dict) else {}
    fixture = boundary["fixture"]
    receipts: list[dict[str, Any]] = []
    for row_name, variant in (("control", "baseline"), ("candidate", "candidate")):
        row = payload.get(row_name) if isinstance(payload.get(row_name), dict) else {}
        summary = row.get("summary") if isinstance(row.get("summary"), dict) else {}
        metrics_source = row.get("metrics") if isinstance(row.get("metrics"), dict) else {}
        metrics: dict[str, dict[str, Any]] = {}
        metric_map = {
            "input_tokens": "input_tokens",
            "output_tokens": "output_tokens",
            "reasoning_tokens": "reasoning_tokens",
            "cache_read_tokens": "cache_read_tokens",
            "cache_write_tokens": "cache_write_tokens",
            "request_count": "request_count",
            "tool_calls": "tool_calls",
        }
        for output_name, source_name in metric_map.items():
            item = metric_payload(metrics_source.get(source_name))
            if item is not None:
                metrics[output_name] = item
        row_ok = row_passes(row)
        session_bound = (
            str(metrics_source.get("session_detection_status") or "") == "bound_candidate"
            and number(metrics_source.get("bound_candidate_count")) == 1
            and number(metrics_source.get("candidate_count")) == 1
        )
        direct_fields_complete = bool(metrics_source.get("direct_fields_complete")) and not metrics_source.get("missing_direct_provider_token_fields")
        run_id = str(summary.get("run_id") or slice_info.get("candidate_run_id") or "")
        receipt = {
            "schema_version": "1.0.0",
            "receipt_id": f"{ARTIFACT_REUSE_PAIR_TYPE}:{run_id}:{variant}",
            "harness": "private-newsletter-phase3",
            "provider": "openai",
            "model": str(metrics_source.get("model") or summary.get("model") or slice_info.get("model") or ""),
            "model_version": str(slice_info.get("model") or metrics_source.get("model") or ""),
            "model_family": "openai",
            "invocation_surface": "private-newsletter-stdout-no-tools" if variant == "candidate" else "private-newsletter-control",
            "fixture_id": str(fixture.get("manifest_id") or "artifact-reuse-stdout-no-tools-phase3"),
            "variant": variant,
            "run_index": 1,
            "started_at": str(payload.get("generated_at_utc") or utc_now()),
            "completed_at": str(payload.get("generated_at_utc") or utc_now()),
            "wall_time_ms": 0,
            "prompt_hash": str(metrics_source.get("prompt_sha256") or metrics_source.get("original_prompt_sha256") or row_name),
            "fixture_hash": str(fixture.get("manifest_sha256") or fixture.get("source_pack_sha256") or sha256_file(path)),
            "raw_receipt_path": str(path),
            "exit_status": "success" if row_ok else "failed",
            "target_repo_mutated": False,
            "correctness_pass": row_ok,
            "closeout_truth_pass": row_ok,
            "metrics": metrics,
            "artifact_reuse_stdout_no_tools_boundary": {
                **boundary,
                "row_name": row_name,
                "row_passes": row_ok,
                "session_bound": session_bound,
                "direct_fields_complete": direct_fields_complete,
                "missing_direct_provider_token_fields": metrics_source.get("missing_direct_provider_token_fields", []),
            },
            "source_format": ARTIFACT_REUSE_PAIR_TYPE,
        }
        receipts.append(receipt)
    return receipts


def parsed_defaults(fmt: str, rows: list[Any]) -> dict[str, str]:
    if fmt == "copilot":
        return {
            "harness": "copilot-cli",
            "provider": "github-copilot",
            "model": first_string(rows, ("selectedModel", "currentModel", "model")),
            "model_family": first_string(rows, ("modelFamily", "family")),
            "invocation_surface": "copilot-cli",
        }
    if fmt == "codex":
        return {
            "harness": "codex-cli",
            "provider": "openai",
            "model": first_string(rows, ("model", "model_slug", "default_model")),
            "model_family": "openai",
            "invocation_surface": "codex",
        }
    if fmt == "vscode":
        return {
            "harness": "vscode-chat",
            "provider": first_string(rows, ("provider", "vendor")) or "vscode",
            "model": first_string(rows, ("modelId", "model", "modelName")),
            "model_family": first_string(rows, ("modelFamily", "family")),
            "invocation_surface": "vscode-chat",
        }
    return {
        "harness": "generic-command",
        "provider": "generic",
        "model": first_string(rows, ("model", "model_id")),
        "model_family": first_string(rows, ("model_family", "family")),
        "invocation_surface": "generic-command",
    }


def build_receipt(args: argparse.Namespace, fmt: str, path: Path, rows: list[Any]) -> dict[str, Any]:
    defaults = parsed_defaults(fmt, rows)
    prompt = args.prompt or first_string(rows, ("prompt", "input", "instructions"))
    metrics = collect_direct_metrics(rows)
    collect_proxy_metrics(path, prompt, metrics)
    started = first_timestamp(rows)
    completed = last_timestamp(rows)
    return {
        "schema_version": "1.0.0",
        "harness": args.harness or defaults["harness"],
        "provider": args.provider or defaults["provider"],
        "model": args.model or defaults["model"],
        "model_version": args.model_version or first_string(rows, ("modelVersion", "model_version")),
        "model_family": args.model_family or defaults["model_family"],
        "invocation_surface": args.invocation_surface or defaults["invocation_surface"],
        "fixture_id": args.fixture_id,
        "variant": args.variant,
        "run_index": args.run_index,
        "started_at": started,
        "completed_at": completed,
        "wall_time_ms": 0,
        "prompt_hash": sha256_text(prompt) if prompt else sha256_file(path),
        "fixture_hash": args.fixture_hash or sha256_file(path),
        "raw_receipt_path": str(path),
        "exit_status": "success",
        "target_repo_mutated": bool(args.target_repo_mutated),
        "correctness_pass": args.correctness_pass == "true",
        "closeout_truth_pass": args.closeout_truth_pass == "true",
        "metrics": metrics,
        "source_format": fmt,
    }


def main() -> int:
    args = parse_args()
    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()
    rows = read_json_or_jsonl(input_path)
    fmt = detect_format(input_path, rows) if args.source_format == "auto" else args.source_format
    pair_receipts = artifact_reuse_pair_receipts(rows[0], input_path) if len(rows) == 1 and isinstance(rows[0], dict) else []
    receipts = passthrough_receipts(rows) or pair_receipts or [build_receipt(args, fmt, input_path, rows)]
    payload = {
        "schema_version": "1.0.0",
        "artifact": "AGENT_RUN_RECEIPTS",
        "generated_at": utc_now(),
        "source_format": fmt,
        "source_path": str(input_path),
        "receipts": receipts,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Agent run receipts: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Build a live-paired optimization benchmark corpus from normalized receipts."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PRIMARY_METRIC_BY_CLAIM = {
    "token": "input_tokens",
    "output_noise": "irrelevant_output_bytes",
    "wall_time": "wall_time_ms",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", required=True, help="LIVE_PAIRED_FIXTURES JSON")
    parser.add_argument("--receipts", required=True, help="AGENT_RUN_RECEIPTS JSON")
    parser.add_argument("--output", required=True, help="Generated OPTIMIZATION_BENCHMARK_CORPUS JSON")
    parser.add_argument("--minimum-total", type=int, default=1)
    return parser.parse_args()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest_json(payload: Any) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


def metric_value(receipt: dict[str, Any], metric: str, direct_only: bool = True) -> float | None:
    if metric == "wall_time_ms":
        value = receipt.get("wall_time_ms")
        return float(value) if isinstance(value, (int, float)) else None
    metrics = receipt.get("metrics") if isinstance(receipt.get("metrics"), dict) else {}
    item = metrics.get(metric)
    if not isinstance(item, dict):
        return None
    if direct_only and item.get("source") != "direct":
        return None
    value = item.get("value")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def avg(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def compact_number(value: float | None) -> float | int | None:
    if value is None:
        return None
    if float(value).is_integer():
        return int(value)
    return round(value, 6)


def receipt_stratum(receipt: dict[str, Any]) -> tuple[str, str, str, str]:
    return (
        str(receipt.get("provider") or ""),
        str(receipt.get("harness") or ""),
        str(receipt.get("model") or ""),
        str(receipt.get("model_version") or ""),
    )


def variant_key(receipt: dict[str, Any]) -> tuple[str, str, str, str, str, str]:
    provider, harness, model, model_version = receipt_stratum(receipt)
    return (str(receipt.get("fixture_id") or ""), provider, harness, model, model_version, str(receipt.get("variant") or ""))


def pair_deltas(
    baseline_receipts: list[dict[str, Any]],
    candidate_receipts: list[dict[str, Any]],
    metric: str,
) -> list[float]:
    baselines = {int(item.get("run_index") or 0): item for item in baseline_receipts}
    candidates = {int(item.get("run_index") or 0): item for item in candidate_receipts}
    deltas: list[float] = []
    for run_index in sorted(set(baselines) & set(candidates)):
        baseline = metric_value(baselines[run_index], metric)
        candidate = metric_value(candidates[run_index], metric)
        if baseline is None or candidate is None:
            continue
        deltas.append(baseline - candidate)
    return deltas


def proxy_metrics(receipts: list[dict[str, Any]]) -> dict[str, list[str]]:
    ignored: dict[str, list[str]] = {}
    for receipt in receipts:
        metrics = receipt.get("metrics") if isinstance(receipt.get("metrics"), dict) else {}
        for name, item in metrics.items():
            if isinstance(item, dict) and item.get("source") == "proxy":
                ignored.setdefault(name, []).append(str(receipt.get("raw_receipt_path") or ""))
    return ignored


def build_workload(
    fixture: dict[str, Any],
    provider: str,
    harness: str,
    model: str,
    model_version: str,
    baseline_receipts: list[dict[str, Any]],
    candidate_receipts: list[dict[str, Any]],
) -> dict[str, Any]:
    claim_types = [str(item) for item in fixture.get("claim_types", [])]
    primary_metric = next((PRIMARY_METRIC_BY_CLAIM[item] for item in claim_types if item in PRIMARY_METRIC_BY_CLAIM), "")
    baseline_metrics = [metric_value(item, primary_metric) for item in baseline_receipts] if primary_metric else []
    candidate_metrics = [metric_value(item, primary_metric) for item in candidate_receipts] if primary_metric else []
    baseline_values = [item for item in baseline_metrics if item is not None]
    candidate_values = [item for item in candidate_metrics if item is not None]
    deltas = pair_deltas(baseline_receipts, candidate_receipts, primary_metric) if primary_metric else []
    run_count = min(len(baseline_receipts), len(candidate_receipts))
    correctness_pass = all(bool(item.get("correctness_pass")) for item in baseline_receipts + candidate_receipts)
    closeout_truth_pass = all(bool(item.get("closeout_truth_pass")) for item in baseline_receipts + candidate_receipts)
    target_mutated = any(bool(item.get("target_repo_mutated")) for item in baseline_receipts + candidate_receipts)

    baseline: dict[str, Any] = {
        "input_hash": digest_json([item.get("prompt_hash") for item in baseline_receipts]),
        "correctness_pass": correctness_pass,
        "closeout_truth_pass": closeout_truth_pass,
        "run_count": run_count,
    }
    candidate: dict[str, Any] = {
        "input_hash": digest_json([item.get("prompt_hash") for item in candidate_receipts]),
        "correctness_pass": correctness_pass,
        "closeout_truth_pass": closeout_truth_pass,
        "run_count": run_count,
    }
    if primary_metric == "input_tokens":
        baseline_value = compact_number(avg(baseline_values))
        candidate_value = compact_number(avg(candidate_values))
        if baseline_value is not None:
            baseline["input_tokens"] = baseline_value
            baseline["input_tokens_source"] = "direct"
        if candidate_value is not None:
            candidate["input_tokens"] = candidate_value
            candidate["input_tokens_source"] = "direct"
    elif primary_metric == "irrelevant_output_bytes":
        baseline_value = compact_number(avg(baseline_values))
        candidate_value = compact_number(avg(candidate_values))
        if baseline_value is not None:
            baseline["irrelevant_output_bytes"] = baseline_value
        if candidate_value is not None:
            candidate["irrelevant_output_bytes"] = candidate_value
    elif primary_metric == "wall_time_ms":
        baseline_value = compact_number(avg(baseline_values))
        candidate_value = compact_number(avg(candidate_values))
        if baseline_value is not None:
            baseline["wall_time_ms"] = baseline_value
        if candidate_value is not None:
            candidate["wall_time_ms"] = candidate_value

    all_receipts = baseline_receipts + candidate_receipts
    return {
        "workload_id": f"{fixture['fixture_id']}--{provider or 'missing-provider'}--{harness or 'missing-harness'}--{model or 'missing-model'}",
        "source_repo": fixture.get("source_repo", "mixed"),
        "bucket": fixture.get("bucket", "mixed"),
        "tactic_id": fixture["tactic_id"],
        "workload_role": fixture.get("workload_role", "roi_candidate"),
        "live_tier": "tier3",
        "allowed_modes": ["live-paired"],
        "claim_types": claim_types,
        "target_repo_mutated": target_mutated,
        "counts_toward_promotion": bool(fixture.get("counts_toward_promotion", True)),
        "provider": provider,
        "harness": harness,
        "model": model,
        "model_version": model_version,
        "model_family": next((str(item.get("model_family") or "") for item in all_receipts if item.get("model_family")), ""),
        "observed_at": max([str(item.get("completed_at") or "") for item in all_receipts] or [""]),
        "prompt_hash": digest_json([item.get("prompt_hash") for item in all_receipts]),
        "fixture_hash": str(fixture.get("fixture_hash") or digest_json(fixture)),
        "observed_mean_delta": compact_number(avg(deltas)),
        "paired_delta_samples": [compact_number(item) for item in deltas],
        "baseline": baseline,
        "candidate": candidate,
        "evidence_refs": [str(item.get("raw_receipt_path") or "") for item in all_receipts],
        "normalized_receipt_ids": [str(item.get("receipt_id") or item.get("raw_receipt_path") or "") for item in all_receipts],
        "proxy_metrics_ignored": proxy_metrics(all_receipts),
    }


def main() -> int:
    args = parse_args()
    fixtures_path = Path(args.fixtures).resolve()
    receipts_path = Path(args.receipts).resolve()
    output_path = Path(args.output).resolve()
    fixture_payload = load_json(fixtures_path)
    receipt_payload = load_json(receipts_path)
    fixtures = [item for item in fixture_payload.get("fixtures", []) if isinstance(item, dict)]
    receipts = [item for item in receipt_payload.get("receipts", []) if isinstance(item, dict)]

    by_fixture_and_stratum: dict[tuple[str, str, str, str, str], dict[str, list[dict[str, Any]]]] = {}
    for receipt in receipts:
        fixture_id = str(receipt.get("fixture_id") or "")
        provider, harness, model, model_version = receipt_stratum(receipt)
        key = (fixture_id, provider, harness, model, model_version)
        by_fixture_and_stratum.setdefault(key, {"baseline": [], "candidate": []})
        variant = str(receipt.get("variant") or "")
        if variant in {"baseline", "candidate"}:
            by_fixture_and_stratum[key][variant].append(receipt)

    workloads: list[dict[str, Any]] = []
    fixture_by_id = {str(item.get("fixture_id")): item for item in fixtures}
    for (fixture_id, provider, harness, model, model_version), variants in sorted(by_fixture_and_stratum.items()):
        fixture = fixture_by_id.get(fixture_id)
        if not fixture:
            continue
        if not variants["baseline"] or not variants["candidate"]:
            continue
        workloads.append(
            build_workload(
                fixture,
                provider,
                harness,
                model,
                model_version,
                sorted(variants["baseline"], key=lambda item: int(item.get("run_index") or 0)),
                sorted(variants["candidate"], key=lambda item: int(item.get("run_index") or 0)),
            )
        )

    payload = {
        "schema_version": "1.0.0",
        "artifact": "OPTIMIZATION_BENCHMARK_CORPUS",
        "corpus_id": str(fixture_payload.get("corpus_id") or "provider-neutral-live-paired-corpus"),
        "target_label": str(fixture_payload.get("target_label") or "provider-neutral Tier 3 live-paired corpus"),
        "generated_at": utc_now(),
        "minimum_corpus": {
            "total_admitted": args.minimum_total,
            "buckets": {},
        },
        "thresholds": fixture_payload.get("thresholds", {}),
        "workloads": workloads,
        "non_claims": [
            "Provider-neutral receipts are the only benchmark input contract; Codex, Copilot, VS Code, and future harnesses are adapters.",
            "Proxy metrics are retained for diagnostics but cannot satisfy direct-token, direct-cost, or cache claims.",
            "Cache promotion is excluded from this Tier 3 package.",
        ],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Live-paired corpus: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

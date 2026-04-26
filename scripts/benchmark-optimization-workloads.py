#!/usr/bin/env python3
"""Benchmark prompt/context optimization workloads without mutating targets."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ALLOWED_DISPOSITIONS = {"promoted", "sandbox-only", "rejected", "not-measured"}
DEFAULT_THRESHOLDS = {
    "paired_fixture_count_minimum": 3,
    "token_or_input_size_delta": {"min_pct": 15.0, "min_absolute_tokens": 500},
    "output_noise_delta": {"min_pct": 20.0},
    "wall_time_delta": {"max_regression_pct": 10.0, "speed_claim_min_improvement_pct": 10.0},
    "llm_backed_run_count": 5,
    "variance_multiplier": 2.0,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", required=True, help="Path to OPTIMIZATION_BENCHMARK_CORPUS JSON")
    parser.add_argument("--output-dir", required=True, help="Directory for benchmark artifacts")
    parser.add_argument(
        "--mode",
        choices=("deterministic", "retained-replay", "live-paired"),
        default="retained-replay",
        help="Measurement mode. live-paired only evaluates rows with retained live metrics.",
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def die(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def as_number(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return None


def pct_reduction(baseline: float | None, candidate: float | None) -> float | None:
    if baseline is None or candidate is None or baseline <= 0:
        return None
    return ((baseline - candidate) / baseline) * 100.0


def merge_thresholds(corpus_thresholds: dict[str, Any]) -> dict[str, Any]:
    thresholds = json.loads(json.dumps(DEFAULT_THRESHOLDS))
    for key, value in corpus_thresholds.items():
        if isinstance(value, dict) and isinstance(thresholds.get(key), dict):
            thresholds[key].update(value)
        else:
            thresholds[key] = value
    return thresholds


def validate_corpus(corpus: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for field in ("schema_version", "corpus_id", "workloads"):
        if field not in corpus:
            errors.append(f"missing required corpus field: {field}")
    if not isinstance(corpus.get("workloads"), list):
        errors.append("workloads must be an array")
        return errors
    seen: set[str] = set()
    for index, workload in enumerate(corpus["workloads"]):
        if not isinstance(workload, dict):
            errors.append(f"workloads[{index}] must be an object")
            continue
        for field in ("workload_id", "source_repo", "bucket", "tactic_id", "baseline", "candidate"):
            if field not in workload:
                errors.append(f"workloads[{index}] missing {field}")
        workload_id = str(workload.get("workload_id") or "")
        if not workload_id:
            errors.append(f"workloads[{index}] has empty workload_id")
        elif workload_id in seen:
            errors.append(f"duplicate workload_id: {workload_id}")
        seen.add(workload_id)
        if not isinstance(workload.get("baseline"), dict):
            errors.append(f"{workload_id or index} baseline must be an object")
        if not isinstance(workload.get("candidate"), dict):
            errors.append(f"{workload_id or index} candidate must be an object")
    return errors


def bool_field(mapping: dict[str, Any], field: str, default: bool = True) -> bool:
    value = mapping.get(field)
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    return str(value).strip().lower() in {"1", "true", "yes", "pass", "passed"}


def claim_token_result(baseline: dict[str, Any], candidate: dict[str, Any], thresholds: dict[str, Any]) -> dict[str, Any]:
    if baseline.get("input_tokens_source") == "proxy" or candidate.get("input_tokens_source") == "proxy":
        return {
            "claim": "token_or_input_size",
            "measured": False,
            "passed": False,
            "delta_tokens": None,
            "delta_pct": None,
            "threshold": thresholds["token_or_input_size_delta"],
            "blocked_reason": "proxy token metrics cannot satisfy direct-token claims",
        }
    base = as_number(baseline.get("input_tokens"))
    cand = as_number(candidate.get("input_tokens"))
    delta = None if base is None or cand is None else base - cand
    pct = pct_reduction(base, cand)
    rule = thresholds["token_or_input_size_delta"]
    passed = (
        delta is not None
        and pct is not None
        and (delta >= float(rule["min_absolute_tokens"]) or pct >= float(rule["min_pct"]))
    )
    return {
        "claim": "token_or_input_size",
        "measured": delta is not None and pct is not None,
        "passed": passed,
        "delta_tokens": delta,
        "delta_pct": pct,
        "threshold": rule,
    }


def claim_output_noise_result(baseline: dict[str, Any], candidate: dict[str, Any], thresholds: dict[str, Any]) -> dict[str, Any]:
    base = as_number(baseline.get("irrelevant_output_bytes"))
    cand = as_number(candidate.get("irrelevant_output_bytes"))
    delta = None if base is None or cand is None else base - cand
    pct = pct_reduction(base, cand)
    rule = thresholds["output_noise_delta"]
    passed = delta is not None and pct is not None and pct >= float(rule["min_pct"])
    return {
        "claim": "output_noise",
        "measured": delta is not None and pct is not None,
        "passed": passed,
        "delta_bytes": delta,
        "delta_pct": pct,
        "threshold": rule,
    }


def claim_wall_time_result(baseline: dict[str, Any], candidate: dict[str, Any], thresholds: dict[str, Any]) -> dict[str, Any]:
    base = as_number(baseline.get("wall_time_ms"))
    cand = as_number(candidate.get("wall_time_ms"))
    pct = pct_reduction(base, cand)
    rule = thresholds["wall_time_delta"]
    regression_pct = None
    if base is not None and cand is not None and base > 0 and cand > base:
        regression_pct = ((cand - base) / base) * 100.0
    no_regression = regression_pct is None or regression_pct <= float(rule["max_regression_pct"])
    speed_claim_passed = pct is not None and pct >= float(rule["speed_claim_min_improvement_pct"])
    return {
        "claim": "wall_time",
        "measured": pct is not None,
        "passed": no_regression and speed_claim_passed,
        "no_regression": no_regression,
        "regression_pct": regression_pct,
        "delta_pct": pct,
        "threshold": rule,
    }


def claim_cache_result(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    base_hit = as_number(baseline.get("cache_hit_rate_pct"))
    cand_hit = as_number(candidate.get("cache_hit_rate_pct"))
    base_prefix = as_number(baseline.get("stable_prefix_tokens"))
    cand_prefix = as_number(candidate.get("stable_prefix_tokens"))
    direct_measured = base_hit is not None and cand_hit is not None
    proxy_measured = base_prefix is not None and cand_prefix is not None
    direct_delta = None if not direct_measured else cand_hit - base_hit
    proxy_delta = None if not proxy_measured else cand_prefix - base_prefix
    return {
        "claim": "prompt_cache",
        "measured": direct_measured or proxy_measured,
        "passed": bool(direct_measured and direct_delta is not None and direct_delta > 0),
        "proxy_only": bool(proxy_measured and not direct_measured and proxy_delta is not None and proxy_delta > 0),
        "direct_cache_hit_rate_delta_pct": direct_delta,
        "stable_prefix_delta_tokens": proxy_delta,
        "threshold": "direct provider cache telemetry required for cache-hit savings; stable prefix is cache-readiness only",
    }


def provider_stratum(workload: dict[str, Any]) -> dict[str, str]:
    return {
        "provider": str(workload.get("provider") or ""),
        "harness": str(workload.get("harness") or ""),
        "model": str(workload.get("model") or ""),
        "model_version": str(workload.get("model_version") or ""),
    }


def provider_stratum_key(row: dict[str, Any]) -> tuple[str, str, str, str]:
    return (
        str(row.get("provider") or ""),
        str(row.get("harness") or ""),
        str(row.get("model") or ""),
        str(row.get("model_version") or ""),
    )


def paired_variance_ok(workload: dict[str, Any], thresholds: dict[str, Any]) -> bool | None:
    deltas = workload.get("paired_delta_samples")
    observed = as_number(workload.get("observed_mean_delta"))
    if not isinstance(deltas, list) or observed is None:
        return None
    numeric = [as_number(item) for item in deltas]
    numeric = [item for item in numeric if item is not None]
    if len(numeric) < 2:
        return None
    mean = sum(numeric) / len(numeric)
    variance = sum((item - mean) ** 2 for item in numeric) / (len(numeric) - 1)
    stdev = math.sqrt(variance)
    return abs(observed) >= float(thresholds["variance_multiplier"]) * stdev


def compact_claim_metrics(claims: list[dict[str, Any]]) -> dict[str, Any]:
    metrics: dict[str, Any] = {}
    for claim in claims:
        claim_name = claim.get("claim")
        if claim_name == "token_or_input_size":
            metrics["token_delta"] = claim.get("delta_tokens")
            metrics["token_delta_pct"] = claim.get("delta_pct")
        elif claim_name == "output_noise":
            metrics["output_noise_delta_bytes"] = claim.get("delta_bytes")
            metrics["output_noise_delta_pct"] = claim.get("delta_pct")
        elif claim_name == "wall_time":
            metrics["wall_time_delta_pct"] = claim.get("delta_pct")
            metrics["wall_time_regression_pct"] = claim.get("regression_pct")
        elif claim_name == "prompt_cache":
            metrics["cache_hit_rate_delta_pct"] = claim.get("direct_cache_hit_rate_delta_pct")
            metrics["stable_prefix_delta_tokens"] = claim.get("stable_prefix_delta_tokens")
    return metrics


def evaluate_workload(workload: dict[str, Any], mode: str, thresholds: dict[str, Any]) -> dict[str, Any]:
    workload_id = str(workload.get("workload_id"))
    baseline = workload.get("baseline") if isinstance(workload.get("baseline"), dict) else {}
    candidate = workload.get("candidate") if isinstance(workload.get("candidate"), dict) else {}
    role = str(workload.get("workload_role") or "roi_candidate")
    allowed_modes = workload.get("allowed_modes") if isinstance(workload.get("allowed_modes"), list) else ["deterministic", "retained-replay"]
    live_tier = str(workload.get("live_tier") or "tier1")
    claim_types = [str(item) for item in workload.get("claim_types", []) if str(item).strip()]
    target_mutated = bool_field(workload, "target_repo_mutated", default=False)
    correctness_pass = bool_field(candidate, "correctness_pass", default=True)
    closeout_truth_pass = bool_field(candidate, "closeout_truth_pass", default=True)
    hard_regression = False
    reasons: list[str] = []
    claims: list[dict[str, Any]] = []
    variance_ok = None
    stratum = provider_stratum(workload)

    if str(workload.get("admission_status") or "admitted") != "admitted":
        return {
            "workload_id": workload_id,
            "source_repo": workload.get("source_repo"),
            "bucket": workload.get("bucket"),
            "tactic_id": workload.get("tactic_id"),
            "workload_role": role,
            "counts_toward_promotion": False,
            "disposition": "not-measured",
            "reason": str(workload.get("admission_status_reason") or "workload is not admitted to the corpus"),
            "hard_regression": False,
            "baseline_input_hash": baseline.get("input_hash"),
            "candidate_input_hash": candidate.get("input_hash"),
            "correctness_gate": {
                "correctness_pass": correctness_pass,
                "closeout_truth_pass": closeout_truth_pass,
                "target_repo_mutated": target_mutated,
            },
            "variance_gate": {"evaluated": False, "passed": None},
            "measured_metrics": {},
            "claims": [],
            **stratum,
        }

    if target_mutated:
        hard_regression = True
        reasons.append("target repository mutation is forbidden")
    if not correctness_pass:
        hard_regression = True
        reasons.append("candidate correctness gate failed")
    if not closeout_truth_pass:
        hard_regression = True
        reasons.append("candidate closeout-truth gate failed")
    if mode not in allowed_modes:
        reasons.append(f"mode {mode} is not allowed for this workload")
    if live_tier == "tier3" and mode != "live-paired":
        reasons.append("fresh live paired workload requires MODE=live-paired")
    if mode == "live-paired":
        missing_metadata = [key for key in ("provider", "harness", "model") if not stratum[key].strip()]
        if missing_metadata:
            reasons.append(f"live-paired measurement lacks provider metadata: {', '.join(missing_metadata)}")
        run_count = as_number(candidate.get("run_count"))
        if run_count is None or run_count < float(thresholds["llm_backed_run_count"]):
            reasons.append("live-paired measurement lacks the required paired repetition count")
        variance_ok = paired_variance_ok(workload, thresholds)
        if variance_ok is False:
            reasons.append("live-paired delta does not clear the variance rule")
        elif variance_ok is None:
            reasons.append("live-paired measurement lacks paired delta samples and observed mean delta")

    if role in {"correctness_control", "policy_control"}:
        disposition = "rejected" if hard_regression else "not-measured"
        reason = "; ".join(reasons) if reasons else f"{role} validates safety but does not count as ROI proof"
        return {
            "workload_id": workload_id,
            "source_repo": workload.get("source_repo"),
            "bucket": workload.get("bucket"),
            "tactic_id": workload.get("tactic_id"),
            "workload_role": role,
            "counts_toward_promotion": False,
            "disposition": disposition,
            "reason": reason,
            "hard_regression": hard_regression,
            "baseline_input_hash": baseline.get("input_hash"),
            "candidate_input_hash": candidate.get("input_hash"),
            "correctness_gate": {
                "correctness_pass": correctness_pass,
                "closeout_truth_pass": closeout_truth_pass,
                "target_repo_mutated": target_mutated,
            },
            "variance_gate": {"evaluated": variance_ok is not None, "passed": variance_ok},
            "measured_metrics": {},
            "claims": [],
            **stratum,
        }

    if "token" in claim_types:
        claims.append(claim_token_result(baseline, candidate, thresholds))
    if "output_noise" in claim_types:
        claims.append(claim_output_noise_result(baseline, candidate, thresholds))
    if "wall_time" in claim_types:
        wall_time = claim_wall_time_result(baseline, candidate, thresholds)
        claims.append(wall_time)
        if wall_time["measured"] and not wall_time["no_regression"]:
            hard_regression = True
            reasons.append("wall time regressed beyond threshold")
    if "cache" in claim_types:
        claims.append(claim_cache_result(baseline, candidate))

    measured_claims = [claim for claim in claims if claim.get("measured")]
    passed_direct_claims = [
        claim for claim in measured_claims
        if claim.get("passed") and not claim.get("proxy_only")
    ]
    proxy_only_claims = [claim for claim in measured_claims if claim.get("proxy_only")]

    if hard_regression:
        disposition = "rejected"
    elif reasons:
        disposition = "not-measured"
    elif not measured_claims:
        disposition = "not-measured"
        reasons.append("no measurable ROI fields were available")
    elif passed_direct_claims:
        disposition = "promoted"
    elif proxy_only_claims:
        disposition = "sandbox-only"
        reasons.append("proxy-only improvement cannot support a live savings claim")
    else:
        disposition = "rejected"
        reasons.append("measured deltas did not clear admission thresholds")

    return {
        "workload_id": workload_id,
        "source_repo": workload.get("source_repo"),
        "bucket": workload.get("bucket"),
        "tactic_id": workload.get("tactic_id"),
        "workload_role": role,
        "counts_toward_promotion": bool(workload.get("counts_toward_promotion", role == "roi_candidate")),
        "disposition": disposition,
        "reason": "; ".join(reasons) if reasons else "measured thresholds cleared for this workload",
        "hard_regression": hard_regression,
        "baseline_input_hash": baseline.get("input_hash"),
        "candidate_input_hash": candidate.get("input_hash"),
        "correctness_gate": {
            "correctness_pass": correctness_pass,
            "closeout_truth_pass": closeout_truth_pass,
            "target_repo_mutated": target_mutated,
        },
        "variance_gate": {"evaluated": variance_ok is not None, "passed": variance_ok},
        "measured_metrics": compact_claim_metrics(claims),
        "claims": claims,
        "evidence_refs": workload.get("evidence_refs", []),
        **stratum,
    }


def corpus_readiness(corpus: dict[str, Any]) -> dict[str, Any]:
    minimum = corpus.get("minimum_corpus") if isinstance(corpus.get("minimum_corpus"), dict) else {}
    bucket_requirements = minimum.get("buckets") if isinstance(minimum.get("buckets"), dict) else {}
    workloads = [item for item in corpus.get("workloads", []) if isinstance(item, dict)]
    admitted = [item for item in workloads if str(item.get("admission_status") or "admitted") == "admitted"]
    bucket_counts: dict[str, int] = {}
    for workload in admitted:
        bucket = str(workload.get("bucket") or "unknown")
        bucket_counts[bucket] = bucket_counts.get(bucket, 0) + 1
    total_required = int(minimum.get("total_admitted", 0) or 0)
    total_pass = len(admitted) >= total_required
    bucket_passes = {
        bucket: bucket_counts.get(bucket, 0) >= int(required)
        for bucket, required in bucket_requirements.items()
    }
    ready = total_pass and all(bucket_passes.values())
    return {
        "ready": ready,
        "admitted_workload_count": len(admitted),
        "required_admitted_workload_count": total_required,
        "bucket_counts": bucket_counts,
        "bucket_requirements": bucket_requirements,
        "bucket_passes": bucket_passes,
    }


def rollup_group(tactic: str, tactic_results: list[dict[str, Any]], thresholds: dict[str, Any]) -> dict[str, Any]:
    min_fixtures = int(thresholds["paired_fixture_count_minimum"])
    eligible = [
        result for result in tactic_results
        if result.get("counts_toward_promotion")
        and result.get("disposition") in {"promoted", "sandbox-only", "rejected"}
    ]
    hard_regressions = [result for result in eligible if result.get("hard_regression")]
    promoted = [result for result in eligible if result.get("disposition") == "promoted"]
    sandbox = [result for result in eligible if result.get("disposition") == "sandbox-only"]
    rejected = [result for result in eligible if result.get("disposition") == "rejected"]
    not_measured = [
        result for result in tactic_results
        if result.get("counts_toward_promotion") and result.get("disposition") == "not-measured"
    ]
    proxy_only = [
        result for result in eligible
        for claim in result.get("claims", [])
        if claim.get("proxy_only")
    ]

    if len(eligible) < min_fixtures:
        disposition = "not-measured"
        reason = f"only {len(eligible)} eligible paired fixture(s); requires {min_fixtures}"
    elif hard_regressions:
        disposition = "rejected"
        reason = "one or more eligible workloads violated correctness, closeout truth, target mutation, or wall-time regression gates"
    elif tactic == "prompt_cache_stability" and proxy_only and not promoted:
        disposition = "sandbox-only"
        reason = "cache-readiness improved by proxy, but direct cache telemetry is absent"
    elif len(promoted) >= 2:
        disposition = "promoted"
        reason = "at least two eligible paired workloads cleared material ROI thresholds with no hard regression"
    elif promoted or sandbox:
        disposition = "sandbox-only"
        reason = "some evidence improved, but the tactic did not clear the paired-workload promotion rule"
    elif rejected:
        disposition = "rejected"
        reason = "eligible measured workloads did not clear ROI thresholds"
    else:
        disposition = "not-measured"
        reason = "eligible workloads lacked measurable ROI fields"

    return {
        "tactic_id": tactic,
        "disposition": disposition,
        "reason": reason,
        "eligible_workload_count": len(eligible),
        "promoted_workload_count": len(promoted),
        "sandbox_workload_count": len(sandbox),
        "rejected_workload_count": len(rejected),
        "not_measured_workload_count": len(not_measured),
        "workload_ids": [str(result.get("workload_id")) for result in tactic_results],
    }


def roll_up_tactics(results: list[dict[str, Any]], thresholds: dict[str, Any]) -> list[dict[str, Any]]:
    by_tactic: dict[str, list[dict[str, Any]]] = {}
    for result in results:
        tactic = str(result.get("tactic_id") or "unknown")
        by_tactic.setdefault(tactic, []).append(result)

    rollups: list[dict[str, Any]] = []
    for tactic, tactic_results in sorted(by_tactic.items()):
        rollup = rollup_group(tactic, tactic_results, thresholds)
        has_provider_strata = any(
            result.get("provider") or result.get("harness") or result.get("model")
            for result in tactic_results
        )
        rollup["promotion_scope"] = "none"
        rollup["fleet_portable"] = False
        rollup["provider_strata"] = []
        if has_provider_strata:
            by_stratum: dict[tuple[str, str, str, str], list[dict[str, Any]]] = {}
            for result in tactic_results:
                by_stratum.setdefault(provider_stratum_key(result), []).append(result)
            strata = []
            for key, stratum_results in sorted(by_stratum.items()):
                stratum_rollup = rollup_group(tactic, stratum_results, thresholds)
                provider, harness, model, model_version = key
                stratum_rollup.update(
                    {
                        "provider": provider,
                        "harness": harness,
                        "model": model,
                        "model_version": model_version,
                    }
                )
                strata.append(stratum_rollup)
            promoted_strata = [item for item in strata if item["disposition"] == "promoted"]
            blocking_strata = [item for item in strata if item["disposition"] in {"rejected", "sandbox-only"}]
            independent_provider_harness = {
                (item.get("provider"), item.get("harness"))
                for item in promoted_strata
                if item.get("provider") and item.get("harness")
            }
            rollup["provider_strata"] = strata
            if len(independent_provider_harness) >= 2 and not blocking_strata:
                rollup["disposition"] = "promoted"
                rollup["promotion_scope"] = "fleet-portable"
                rollup["fleet_portable"] = True
                rollup["reason"] = "at least two independent provider/harness strata cleared promotion thresholds without contradictory strata"
            elif promoted_strata:
                rollup["disposition"] = "promoted"
                rollup["promotion_scope"] = "provider-scoped"
                rollup["fleet_portable"] = False
                if blocking_strata:
                    rollup["reason"] = "one or more provider/harness strata promoted, but failed or noisy strata block fleet portability"
                else:
                    rollup["reason"] = "one provider/harness/model stratum cleared promotion thresholds; fleet portability requires two independent passing strata"
            else:
                rollup["promotion_scope"] = "none"
        rollups.append(rollup)
    return rollups


def markdown_readout(results: dict[str, Any]) -> str:
    lines = [
        "# Optimization Benchmark Readout",
        "",
        f"- Corpus: `{results['corpus_id']}`",
        f"- Mode: `{results['mode']}`",
        f"- Generated: `{results['generated_at']}`",
        f"- Corpus ready for promotion claims: `{str(results['corpus_readiness']['ready']).lower()}`",
        "",
        "## Tactic Dispositions",
        "",
        "| Tactic | Disposition | Scope | Eligible | Reason |",
        "|---|---|---|---:|---|",
    ]
    for rollup in results["tactic_rollups"]:
        lines.append(
            f"| `{rollup['tactic_id']}` | `{rollup['disposition']}` | `{rollup.get('promotion_scope', 'none')}` | "
            f"{rollup['eligible_workload_count']} | {rollup['reason']} |"
        )
    lines.extend(["", "## Workload Dispositions", "", "| Workload | Source | Bucket | Disposition | Reason |", "|---|---|---|---|---|"])
    for result in results["workload_results"]:
        lines.append(
            f"| `{result['workload_id']}` | `{result.get('source_repo')}` | `{result.get('bucket')}` | "
            f"`{result['disposition']}` | {result['reason']} |"
        )
    lines.extend(["", "## Non-Claims", ""])
    for non_claim in results["non_claims"]:
        lines.append(f"- {non_claim}")
    lines.append("")
    return "\n".join(lines)


def optimization_plan_markdown(results: dict[str, Any]) -> str:
    promotion_allowed = bool(results["promotion_claims_allowed"])
    promoted_rollups = [item for item in results["tactic_rollups"] if item["disposition"] == "promoted"]
    promoted = promoted_rollups if promotion_allowed else []
    sandbox = [item for item in results["tactic_rollups"] if item["disposition"] == "sandbox-only"]
    rejected = [item for item in results["tactic_rollups"] if item["disposition"] == "rejected"]
    not_measured = [item for item in results["tactic_rollups"] if item["disposition"] == "not-measured"]
    target_label = str(results.get("target_label") or results["corpus_id"])
    lines = [
        "# Optimization Plan",
        "",
        "## Summary",
        "",
        f"Target: {target_label}",
        f"Corpus: {results['corpus_id']}",
        f"Mode: {results['mode']}",
        f"Corpus readiness: {str(results['corpus_readiness']['ready']).lower()}",
        f"Promotion claims allowed: {str(promotion_allowed).lower()}",
        (
            "Disposition mix: "
            f"{len(promoted_rollups)} promoted, {len(sandbox)} sandbox-only, "
            f"{len(rejected)} rejected, {len(not_measured)} not-measured"
        ),
        "",
        "## Approved Findings",
        "",
    ]
    if promoted:
        for index, rollup in enumerate(promoted, start=1):
            lines.extend(
                [
                    f"### Finding {index}: {rollup['tactic_id']} (APPROVED)",
                    "- File: OPTIMIZATION_BENCHMARK_RESULTS.json",
                    f"- Issue: {rollup['reason']}",
                    "- Fix: Keep the tactic eligible for downstream owner-side consumption after repo-native gates.",
                    f"- Expected impact: {rollup['promoted_workload_count']} retained workload(s) cleared material ROI thresholds",
                    f"- Promotion scope: {rollup.get('promotion_scope', 'none')}",
                    "",
                ]
            )
    else:
        lines.extend(
            [
                "No findings are approved for downstream consumption in this benchmark run.",
                "",
                (
                    "Promoted rollups, if any, remain blocked from approved output until the corpus-level "
                    "promotion gate is ready."
                ),
                "",
            ]
        )
    lines.extend(["## Patches", ""])
    if promoted:
        lines.append("No patches generated. This harness emits a benchmark ledger and disposition readout only.")
    else:
        lines.append("No patches generated. All tactics remain sandbox-only, rejected, or not-measured.")
    lines.extend(["", "## Projected Delta", ""])
    lines.append("Pre: unmeasured field evidence -> Post: machine-readable benchmark disposition ledger.")
    if promoted:
        lines.append(
            "Approved tactics may be consumed only by later owner-side batches that preserve the same correctness and non-mutation gates."
        )
    if sandbox:
        lines.append("Sandbox-only tactics require confirmatory paired evidence before promotion.")
    if rejected:
        lines.append("Rejected tactics must not be forwarded as recommendations without new evidence.")
    if not_measured:
        lines.append("Not-measured tactics require direct retained or live workload metrics before any ROI claim.")
    lines.append("")
    return "\n".join(lines)


def optimization_scorecard(results: dict[str, Any]) -> dict[str, Any]:
    rollups = results["tactic_rollups"]
    promotion_allowed = bool(results["promotion_claims_allowed"])
    promoted_rollups = [item for item in rollups if item["disposition"] == "promoted"]
    promoted = promoted_rollups if promotion_allowed else []
    blocked_promoted = [] if promotion_allowed else promoted_rollups
    rejected = [item for item in rollups if item["disposition"] == "rejected"]
    sandbox = [item for item in rollups if item["disposition"] == "sandbox-only"]
    not_measured = [item for item in rollups if item["disposition"] == "not-measured"]
    fleet_portable = [item for item in promoted if item.get("fleet_portable")]
    provider_scoped = [item for item in promoted if item.get("promotion_scope") == "provider-scoped"]
    target_label = str(results.get("target_label") or results["corpus_id"])
    return {
        "findings_total": len(rollups),
        "findings_approved": len(promoted),
        "findings_rejected": len(rejected) + len(sandbox) + len(not_measured) + len(blocked_promoted),
        "findings_downgraded": len(sandbox) + len(not_measured) + len(blocked_promoted),
        "patches_generated": 0,
        "patches_valid": 0,
        "expected_delta": 0,
        "categories": {
            "decompose": 0,
            "consolidate": 0,
            "extract": 0,
            "standardize": len(rollups),
        },
        "meta": {
            "timestamp": results["generated_at"],
            "optimizer_version": "benchmark-optimization-workloads-v1",
            "scorecard_input": results["corpus_id"],
            "target": target_label,
            "promotion_claims_allowed": promotion_allowed,
            "strict_rejected_count": len(rejected),
            "sandbox_only_count": len(sandbox),
            "not_measured_count": len(not_measured),
            "blocked_promoted_count": len(blocked_promoted),
            "fleet_portable_promoted_count": len(fleet_portable),
            "provider_scoped_promoted_count": len(provider_scoped),
        },
    }


def main() -> int:
    args = parse_args()
    corpus_path = Path(args.corpus).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        corpus = load_json(corpus_path)
    except FileNotFoundError:
        return die(f"Corpus file not found: {corpus_path}")
    except json.JSONDecodeError as exc:
        return die(f"Invalid corpus JSON: {exc}")
    if not isinstance(corpus, dict):
        return die("Corpus root must be an object")

    errors = validate_corpus(corpus)
    if errors:
        return die("; ".join(errors))

    thresholds = merge_thresholds(corpus.get("thresholds", {}) if isinstance(corpus.get("thresholds"), dict) else {})
    workload_results = [
        evaluate_workload(workload, args.mode, thresholds)
        for workload in corpus["workloads"]
    ]
    tactic_rollups = roll_up_tactics(workload_results, thresholds)
    readiness = corpus_readiness(corpus)
    disposition_counts: dict[str, int] = {key: 0 for key in sorted(ALLOWED_DISPOSITIONS)}
    for rollup in tactic_rollups:
        disposition_counts[rollup["disposition"]] += 1

    generated_at = datetime.now(timezone.utc).isoformat()
    results = {
        "schema_version": "1.0.0",
        "artifact": "OPTIMIZATION_BENCHMARK_RESULTS",
        "generated_at": generated_at,
        "mode": args.mode,
        "corpus_id": corpus["corpus_id"],
        "target_label": str(corpus.get("target_label") or corpus["corpus_id"]),
        "corpus_path": str(corpus_path),
        "corpus_sha256": sha256_file(corpus_path),
        "thresholds": thresholds,
        "corpus_readiness": readiness,
        "promotion_claims_allowed": readiness["ready"],
        "disposition_counts": disposition_counts,
        "tactic_rollups": tactic_rollups,
        "workload_results": workload_results,
        "non_claims": [
            "No target repository mutation is performed by this harness.",
            "Frontier or social evidence is hypothesis fuel only until local paired workload evidence clears thresholds.",
            "Provider-neutral receipts are the benchmark input contract; Codex, Copilot, VS Code, and future harnesses are adapters.",
            "Provider-scoped promotion is not fleet portability; fleet-portable promotion requires at least two independent passing provider/harness strata.",
            "Proxy token metrics are retained for diagnostics only and cannot satisfy direct-token or direct-cost claims.",
            "Stable-prefix metrics are cache-readiness proxies only; direct provider cache telemetry is required for cache-hit savings claims.",
            "Correctness-control workloads protect regressions but do not count as prompt/context ROI proof.",
        ],
    }

    write_json(output_dir / "OPTIMIZATION_BENCHMARK_RESULTS.json", results)
    (output_dir / "OPTIMIZATION_BENCHMARK_READOUT.md").write_text(markdown_readout(results), encoding="utf-8")
    (output_dir / "OPTIMIZATION_PLAN.md").write_text(optimization_plan_markdown(results), encoding="utf-8")
    write_json(output_dir / "OPTIMIZATION_SCORECARD.json", optimization_scorecard(results))
    output_names = [
        "OPTIMIZATION_BENCHMARK_RESULTS.json",
        "OPTIMIZATION_BENCHMARK_READOUT.md",
        "OPTIMIZATION_PLAN.md",
        "OPTIMIZATION_SCORECARD.json",
    ]
    write_json(
        output_dir / "manifest.json",
        {
            "schema_version": "1.0.0",
            "artifact": "OPTIMIZATION_BENCHMARK_MANIFEST",
            "generated_at": generated_at,
            "mode": args.mode,
            "corpus_path": str(corpus_path),
            "outputs": [
                {
                    "path": name,
                    "sha256": sha256_file(output_dir / name),
                }
                for name in output_names
            ],
        },
    )
    print(f"Benchmark results: {output_dir / 'OPTIMIZATION_BENCHMARK_RESULTS.json'}")
    print(f"Benchmark readout: {output_dir / 'OPTIMIZATION_BENCHMARK_READOUT.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Emit comparable closure-run identity for local and GitHub closure gates."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def env(name: str) -> str:
    return os.environ.get(name, "").strip()


def default_run_id() -> str:
    github_run_id = env("GITHUB_RUN_ID")
    github_run_attempt = env("GITHUB_RUN_ATTEMPT")
    if github_run_id and github_run_attempt:
        return f"{github_run_id}-{github_run_attempt}"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"local-{stamp}-{os.getpid()}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Emit closure-run identity JSON for validation gates."
    )
    parser.add_argument("--phase", required=True, help="Invoked closure gate.")
    parser.add_argument("--parent-command", required=True, help="Parent command.")
    parser.add_argument(
        "--receipt",
        default=env("CLOSURE_IDENTITY_RECEIPT"),
        help="Optional JSON receipt path. Defaults to CLOSURE_IDENTITY_RECEIPT.",
    )
    args = parser.parse_args()

    closure_run_id = env("CLOSURE_RUN_ID") or default_run_id()
    closure_phase = env("CLOSURE_PHASE") or args.phase
    closure_trigger = env("CLOSURE_TRIGGER") or "manual"
    parent_command = env("PARENT_COMMAND") or args.parent_command
    evidence_reuse_key = (
        env("EVIDENCE_REUSE_KEY") or f"{closure_run_id}:{closure_phase}:{parent_command}"
    )

    payload = {
        "closure_run_id": closure_run_id,
        "closure_phase": closure_phase,
        "closure_trigger": closure_trigger,
        "evidence_reuse_key": evidence_reuse_key,
        "parent_command": parent_command,
        "github_run_id": env("GITHUB_RUN_ID") or None,
        "github_run_attempt": env("GITHUB_RUN_ATTEMPT") or None,
    }

    text = json.dumps(payload, sort_keys=True)
    print(text)
    if args.receipt:
        receipt = Path(args.receipt)
        receipt.parent.mkdir(parents=True, exist_ok=True)
        receipt.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

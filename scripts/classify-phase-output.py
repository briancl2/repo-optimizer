#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

ARTIFACT_CONTRACT = "final_non_tool_assistant_message_markdown"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Classify Copilot JSONL output for a single optimizer phase."
    )
    parser.add_argument("--phase", required=True, help="Phase name, e.g. critic")
    parser.add_argument("--raw", required=True, help="Path to raw JSONL transcript")
    parser.add_argument(
        "--artifact",
        required=True,
        help="Path to the authoritative markdown artifact to materialize on success",
    )
    parser.add_argument(
        "--copilot-exit-code",
        type=int,
        default=0,
        help="Exit code from the copilot invocation",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    raw_path = Path(args.raw)
    artifact_path = Path(args.artifact)
    if artifact_path.exists():
        artifact_path.unlink()

    raw_text = ""
    if raw_path.exists():
        raw_text = raw_path.read_text(encoding="utf-8", errors="replace")

    assistant_message_count = 0
    assistant_message_nonempty_count = 0
    assistant_messages_with_tool_requests = 0
    non_tool_assistant_message_count = 0
    assistant_message_delta_count = 0

    last_event_type = ""
    last_assistant_message_content_length = 0
    last_assistant_message_tool_request_count = 0
    last_non_tool_content: str | None = None

    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue

        event_type = payload.get("type", "")
        if isinstance(event_type, str):
            last_event_type = event_type

        if event_type == "assistant.message_delta":
            assistant_message_delta_count += 1
            continue

        if event_type != "assistant.message":
            continue

        data = payload.get("data") or {}
        content = data.get("content", "")
        if not isinstance(content, str):
            content = str(content)
        tool_requests = data.get("toolRequests") or []
        if not isinstance(tool_requests, list):
            tool_requests = []

        assistant_message_count += 1
        if content.strip():
            assistant_message_nonempty_count += 1
        if tool_requests:
            assistant_messages_with_tool_requests += 1
        else:
            non_tool_assistant_message_count += 1
            last_non_tool_content = content

        last_assistant_message_content_length = len(content)
        last_assistant_message_tool_request_count = len(tool_requests)

    command_blocked_detected = "Command blocked:" in raw_text
    artifact_written = False
    notes: list[str] = []

    if last_non_tool_content is not None and last_non_tool_content.strip():
        status = "completed"
        receipt_class = "terminal_markdown_captured"
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_body = (
            last_non_tool_content
            if last_non_tool_content.endswith("\n")
            else last_non_tool_content + "\n"
        )
        artifact_path.write_text(artifact_body, encoding="utf-8")
        artifact_written = True
    elif command_blocked_detected:
        status = "failed_command_blocked"
        receipt_class = "command_blocked_no_terminal_artifact"
        notes.append("Command blocked detected in raw transcript.")
    elif assistant_message_count == 0:
        if args.copilot_exit_code != 0:
            status = "failed_runtime_exit"
            receipt_class = "no_assistant_message_after_nonzero_exit"
        else:
            status = "failed_artifact_contract"
            receipt_class = "no_assistant_message"
        notes.append("Raw transcript contained no assistant.message events.")
    elif non_tool_assistant_message_count == 0:
        status = "failed_artifact_contract"
        receipt_class = "missing_terminal_non_tool_message"
        notes.append(
            "Assistant emitted tool-request turns but no final non-tool assistant.message artifact."
        )
    elif last_non_tool_content is not None and not last_non_tool_content.strip():
        status = "failed_artifact_contract"
        receipt_class = "empty_terminal_non_tool_message"
        notes.append("Final non-tool assistant.message content was empty.")
    elif args.copilot_exit_code != 0:
        status = "failed_runtime_exit"
        receipt_class = "copilot_exit_nonzero_without_artifact"
        notes.append("Copilot exited non-zero before a terminal artifact was captured.")
    else:
        status = "failed_artifact_contract"
        receipt_class = "missing_terminal_artifact_unclassified"
        notes.append("Terminal artifact missing for an unclassified transcript shape.")

    if assistant_message_delta_count and not artifact_written:
        notes.append(
            "assistant.message_delta events were present without a captured terminal artifact."
        )

    payload = {
        "phase": args.phase,
        "status": status,
        "receipt_class": receipt_class,
        "artifact_contract": ARTIFACT_CONTRACT,
        "artifact_path": str(artifact_path),
        "raw_path": str(raw_path),
        "artifact_written": artifact_written,
        "copilot_exit_code": args.copilot_exit_code,
        "command_blocked_detected": command_blocked_detected,
        "assistant_message_count": assistant_message_count,
        "assistant_message_nonempty_count": assistant_message_nonempty_count,
        "assistant_messages_with_tool_requests": assistant_messages_with_tool_requests,
        "non_tool_assistant_message_count": non_tool_assistant_message_count,
        "assistant_message_delta_count": assistant_message_delta_count,
        "last_event_type": last_event_type,
        "last_assistant_message_content_length": last_assistant_message_content_length,
        "last_assistant_message_tool_request_count": last_assistant_message_tool_request_count,
        "notes": notes,
    }
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

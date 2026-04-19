#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ARTIFACT_CONTRACT = "final_non_tool_assistant_message_markdown"
NONTERMINAL_PREFIXES = (
    "Intent logged",
    "Output too large to read at once",
    "File too large to read at once",
    "<exited with exit code",
    "Line 0:",
    "Keys:",
    "Data keys:",
    "Total length:",
    "total ",
)


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
    parser.add_argument(
        "--heartbeat-count",
        type=int,
        default=0,
        help="Count of bounded progress heartbeats emitted while capturing the phase",
    )
    return parser.parse_args()


def strip_numbered_prefixes(text: str) -> str:
    lines = text.splitlines()
    numbered = sum(1 for line in lines if re.match(r"^\d+\.\s", line))
    if numbered >= 2:
        return "\n".join(re.sub(r"^\d+\.\s?", "", line) for line in lines)
    return text


def looks_like_terminal_markdown_artifact(text: str) -> bool:
    normalized = strip_numbered_prefixes(text).strip()
    if len(normalized) < 40:
        return False

    lowered = normalized.lower()
    for prefix in NONTERMINAL_PREFIXES:
        if lowered.startswith(prefix.lower()):
            return False

    lines = [line.strip() for line in normalized.splitlines() if line.strip()]
    pipe_lines = sum(1 for line in lines if line.count("|") >= 2)
    heading_lines = sum(1 for line in lines if line.startswith("#"))
    bullet_lines = sum(1 for line in lines if line.startswith("- ") or line.startswith("* "))

    if "[VERDICT:" in normalized:
        return True
    if pipe_lines >= 2 and ("|---" in normalized or "|------------" in normalized):
        return True
    if heading_lines >= 1 and len(lines) >= 3:
        return True
    if bullet_lines >= 3 and len(lines) >= 5:
        return True
    return False


def trim_to_markdown_start(text: str) -> str:
    normalized = strip_numbered_prefixes(text).strip()
    if not normalized:
        return ""

    lines = normalized.splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("|"):
            candidate = "\n".join(lines[index:]).strip()
            if candidate:
                return candidate
    return normalized


def reconstruct_critic_delta_artifact(
    delta_chunks: dict[str, list[str]],
) -> str | None:
    best_candidate: str | None = None

    for parts in delta_chunks.values():
        candidate = trim_to_markdown_start("".join(parts))
        if len(candidate) < 120:
            continue

        lines = [line.strip() for line in candidate.splitlines() if line.strip()]
        if not lines:
            continue

        pipe_lines = sum(1 for line in lines if line.count("|") >= 2)
        if not lines[0].startswith("#"):
            continue
        if "[VERDICT:" not in candidate:
            continue
        if pipe_lines < 2:
            continue

        if best_candidate is None or len(candidate) > len(best_candidate):
            best_candidate = candidate

    return best_candidate


def critic_phase_requires_authoritative_assistant_surface(phase: str) -> bool:
    return phase == "critic"


def stable_fingerprint(payload: dict[str, object]) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return f"sha256:{digest}"


def phase_artifact_depth(
    *,
    artifact_written: bool,
    status: str,
) -> str:
    if artifact_written and status == "completed":
        return "completed"
    if artifact_written:
        return "accepted"
    return "none"


def heartbeat_status(heartbeat_count: int, status: str) -> str:
    if heartbeat_count > 0:
        return "observed"
    if status.startswith("skipped_") or status == "not_run":
        return "not_applicable"
    return "absent"


def phase_classification_evidence(
    *,
    status: str,
    receipt_class: str,
    artifact_written: bool,
    artifact_source: str,
    copilot_exit_code: int,
    command_blocked_detected: bool,
    assistant_message_count: int,
    assistant_message_nonempty_count: int,
    assistant_messages_with_tool_requests: int,
    non_tool_assistant_message_count: int,
    assistant_message_delta_count: int,
    tool_execution_complete_count: int,
    last_event_type: str,
    last_assistant_message_content_length: int,
    last_assistant_message_tool_request_count: int,
    notes: list[str],
) -> dict[str, object]:
    artifact_exists = artifact_written
    artifact_startable = artifact_written and status == "completed"
    phase_completed = status == "completed"
    return {
        "status": status,
        "receipt_class": receipt_class,
        "artifact_exists": artifact_exists,
        "artifact_startable": artifact_startable,
        "phase_completed": phase_completed,
        "artifact_source": artifact_source,
        "copilot_exit_code": copilot_exit_code,
        "command_blocked_detected": command_blocked_detected,
        "assistant_message_count": assistant_message_count,
        "assistant_message_nonempty_count": assistant_message_nonempty_count,
        "assistant_messages_with_tool_requests": assistant_messages_with_tool_requests,
        "non_tool_assistant_message_count": non_tool_assistant_message_count,
        "assistant_message_delta_count": assistant_message_delta_count,
        "tool_execution_complete_count": tool_execution_complete_count,
        "last_event_type": last_event_type,
        "last_assistant_message_content_length": last_assistant_message_content_length,
        "last_assistant_message_tool_request_count": last_assistant_message_tool_request_count,
        "note_count": len(notes),
    }


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
    tool_execution_complete_count = 0
    assistant_message_delta_chunks: dict[str, list[str]] = {}

    last_event_type = ""
    last_assistant_message_content_length = 0
    last_assistant_message_tool_request_count = 0
    last_non_tool_content: str | None = None
    last_assistant_message_had_tool_requests = False
    final_turn_tool_results: list[dict[str, str | bool]] = []

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
            data = payload.get("data") or {}
            message_id = str(data.get("messageId", ""))
            delta_content = data.get("deltaContent", "")
            if not isinstance(delta_content, str):
                delta_content = str(delta_content)
            assistant_message_delta_chunks.setdefault(message_id, []).append(delta_content)
            continue

        if event_type == "tool.execution_complete":
            tool_execution_complete_count += 1
            data = payload.get("data") or {}
            result = data.get("result") or {}
            content = result.get("content", "")
            if not isinstance(content, str):
                content = str(content)
            final_turn_tool_results.append(
                {
                    "content": content,
                    "success": bool(data.get("success")),
                    "tool_call_id": str(data.get("toolCallId", "")),
                }
            )
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

        final_turn_tool_results = []
        assistant_message_count += 1
        if content.strip():
            assistant_message_nonempty_count += 1
        if tool_requests:
            assistant_messages_with_tool_requests += 1
        else:
            non_tool_assistant_message_count += 1
            last_non_tool_content = content

        last_assistant_message_had_tool_requests = bool(tool_requests)
        last_assistant_message_content_length = len(content)
        last_assistant_message_tool_request_count = len(tool_requests)

    command_blocked_detected = "Command blocked:" in raw_text
    artifact_written = False
    notes: list[str] = []
    artifact_source = "none"
    reconstructed_delta_artifact: str | None = None

    terminal_tool_result: dict[str, str | bool] | None = None
    if (
        last_assistant_message_had_tool_requests
        and not critic_phase_requires_authoritative_assistant_surface(args.phase)
    ):
        for candidate in reversed(final_turn_tool_results):
            content = candidate.get("content")
            if (
                candidate.get("success") is True
                and isinstance(content, str)
                and looks_like_terminal_markdown_artifact(content)
            ):
                terminal_tool_result = candidate
                break

    if args.phase == "critic":
        reconstructed_delta_artifact = reconstruct_critic_delta_artifact(
            assistant_message_delta_chunks
        )
        if final_turn_tool_results:
            notes.append(
                "Critic phase requires authoritative assistant-surface verdict markdown; "
                "tool.execution_complete fallback disabled."
            )

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
        artifact_source = "assistant.message"
    elif reconstructed_delta_artifact is not None:
        status = "completed"
        receipt_class = "critic_delta_markdown_captured"
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_body = (
            reconstructed_delta_artifact
            if reconstructed_delta_artifact.endswith("\n")
            else reconstructed_delta_artifact + "\n"
        )
        artifact_path.write_text(artifact_body, encoding="utf-8")
        artifact_written = True
        artifact_source = "assistant.message_delta"
        notes.append(
            "Reconstructed critic markdown artifact from assistant.message_delta events."
        )
    elif terminal_tool_result is not None:
        status = "completed"
        receipt_class = "terminal_tool_result_content_captured"
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_body = strip_numbered_prefixes(
            str(terminal_tool_result["content"])
        ).strip()
        artifact_body = artifact_body if artifact_body.endswith("\n") else artifact_body + "\n"
        artifact_path.write_text(artifact_body, encoding="utf-8")
        artifact_written = True
        artifact_source = "tool.execution_complete.result.content"
        notes.append(
            "Captured terminal markdown artifact from the final successful tool.execution_complete result."
        )
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
        if final_turn_tool_results:
            notes.append(
                "Final successful tool.execution_complete results did not meet terminal markdown artifact heuristics."
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

    proof_boundary = {
        "artifact_depth": phase_artifact_depth(
            artifact_written=artifact_written,
            status=status,
        ),
        "receipt_depth": "phase",
        "heartbeat_status": heartbeat_status(args.heartbeat_count, status),
        "authority_fingerprint": stable_fingerprint(
            {
                "phase": args.phase,
                "status": status,
                "receipt_class": receipt_class,
                "artifact_written": artifact_written,
                "artifact_source": artifact_source,
                "copilot_exit_code": args.copilot_exit_code,
                "heartbeat_count": args.heartbeat_count,
                "command_blocked_detected": command_blocked_detected,
                "assistant_message_count": assistant_message_count,
                "assistant_message_nonempty_count": assistant_message_nonempty_count,
                "assistant_messages_with_tool_requests": assistant_messages_with_tool_requests,
                "non_tool_assistant_message_count": non_tool_assistant_message_count,
                "assistant_message_delta_count": assistant_message_delta_count,
                "tool_execution_complete_count": tool_execution_complete_count,
                "last_event_type": last_event_type,
            }
        ),
        "phase_classification_evidence": phase_classification_evidence(
            status=status,
            receipt_class=receipt_class,
            artifact_written=artifact_written,
            artifact_source=artifact_source,
            copilot_exit_code=args.copilot_exit_code,
            command_blocked_detected=command_blocked_detected,
            assistant_message_count=assistant_message_count,
            assistant_message_nonempty_count=assistant_message_nonempty_count,
            assistant_messages_with_tool_requests=assistant_messages_with_tool_requests,
            non_tool_assistant_message_count=non_tool_assistant_message_count,
            assistant_message_delta_count=assistant_message_delta_count,
            tool_execution_complete_count=tool_execution_complete_count,
            last_event_type=last_event_type,
            last_assistant_message_content_length=last_assistant_message_content_length,
            last_assistant_message_tool_request_count=last_assistant_message_tool_request_count,
            notes=notes,
        ),
    }

    payload = {
        "phase": args.phase,
        "status": status,
        "receipt_class": receipt_class,
        "artifact_contract": ARTIFACT_CONTRACT,
        "artifact_path": str(artifact_path),
        "raw_path": str(raw_path),
        "artifact_written": artifact_written,
        "artifact_source": artifact_source,
        "copilot_exit_code": args.copilot_exit_code,
        "command_blocked_detected": command_blocked_detected,
        "assistant_message_count": assistant_message_count,
        "assistant_message_nonempty_count": assistant_message_nonempty_count,
        "assistant_messages_with_tool_requests": assistant_messages_with_tool_requests,
        "non_tool_assistant_message_count": non_tool_assistant_message_count,
        "assistant_message_delta_count": assistant_message_delta_count,
        "tool_execution_complete_count": tool_execution_complete_count,
        "final_turn_tool_result_count": len(final_turn_tool_results),
        "last_event_type": last_event_type,
        "last_assistant_message_content_length": last_assistant_message_content_length,
        "last_assistant_message_tool_request_count": last_assistant_message_tool_request_count,
        "notes": notes,
        "proof_boundary": proof_boundary,
    }
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

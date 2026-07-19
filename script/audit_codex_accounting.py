#!/usr/bin/env python3
"""Build and audit an isolated Codex accounting-only history snapshot.

Safety contract:
- The source tree is opened read-only.
- Every generated file, Swift module cache, harness, and report stays under /tmp.
- The frozen copy preserves relative session paths and verbatim relevant JSONL lines.
- TokenStep's production cache/App Support and installed/running app are never touched.

The Python implementation intentionally mirrors the current UsageCollector.swift
accounting revision. By default the script also compiles a temporary Swift harness from
the current working tree, runs the real collector twice against the frozen copy, and
checks the two implementations agree.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
import platform
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable, Optional


SCHEMA_VERSION = 1
ACCOUNTING_REVISION = 8
MAX_SWIFT_LINE_BYTES = 1_048_576
READ_CHUNK_BYTES = 1_048_576
RELEVANT_TYPES = {"session_meta", "turn_context", "token_count", "context_compacted"}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def is_under(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def integer_value(value: Any) -> int:
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return 0
    return 0


def nonempty_string(value: Any) -> Optional[str]:
    if isinstance(value, str) and value:
        return value
    return None


def parse_iso(value: Optional[str]) -> Optional[dt.datetime]:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except ValueError:
        return None


@dataclasses.dataclass(frozen=True)
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0
    cache_creation_input_tokens: int = 0
    cached_input_tokens: int = 0
    reasoning_output_tokens: int = 0
    total_tokens: int = 0

    def add(self, other: "Usage") -> "Usage":
        return Usage(
            input_tokens=self.input_tokens + other.input_tokens,
            output_tokens=self.output_tokens + other.output_tokens,
            cache_creation_input_tokens=self.cache_creation_input_tokens + other.cache_creation_input_tokens,
            cached_input_tokens=self.cached_input_tokens + other.cached_input_tokens,
            reasoning_output_tokens=self.reasoning_output_tokens + other.reasoning_output_tokens,
            total_tokens=self.total_tokens + other.total_tokens,
        )

    @property
    def fingerprint(self) -> str:
        return ":".join(
            map(
                str,
                (
                    self.total_tokens,
                    self.input_tokens,
                    self.cached_input_tokens,
                    self.output_tokens,
                    self.reasoning_output_tokens,
                    self.cache_creation_input_tokens,
                ),
            )
        )

    def report_dict(self) -> dict[str, int]:
        return {
            "processed_tokens": self.total_tokens,
            "input_tokens": self.input_tokens,
            "cached_input_tokens": self.cached_input_tokens,
            "uncached_input_tokens": max(
                0,
                self.input_tokens - self.cached_input_tokens - self.cache_creation_input_tokens,
            ),
            "output_tokens": self.output_tokens,
            "reasoning_tokens": self.reasoning_output_tokens,
            "cache_creation_input_tokens": self.cache_creation_input_tokens,
        }


def normalize_codex(raw: Any) -> Optional[Usage]:
    if not isinstance(raw, dict):
        return None

    def value(keys: Iterable[str]) -> int:
        for key in keys:
            if key in raw:
                return max(0, integer_value(raw.get(key)))
        return 0

    input_tokens = value(("input_tokens", "input"))
    output_tokens = value(("output_tokens", "output"))
    explicit_total_key = next((key for key in ("total_tokens", "total") if key in raw), None)
    total = max(0, integer_value(raw.get(explicit_total_key))) if explicit_total_key else input_tokens + output_tokens
    return Usage(
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_creation_input_tokens=value(("cache_creation_input_tokens", "cache_write_input_tokens")),
        cached_input_tokens=value(("cached_input_tokens", "cache_read_input_tokens", "cached")),
        reasoning_output_tokens=value(("reasoning_output_tokens", "reasoning_tokens", "thoughts")),
        total_tokens=total,
    )


def normalize_old(raw: Any) -> Usage:
    if not isinstance(raw, dict):
        return Usage()
    aliases = {
        "input": "input",
        "output": "output",
        "cached": "cached",
        "thoughts": "reasoning",
        "total": "total",
        "input_tokens": "input",
        "output_tokens": "output",
        "cache_creation_input_tokens": "cache_creation",
        "cache_read_input_tokens": "cached",
        "cached_input_tokens": "cached",
        "reasoning_output_tokens": "reasoning",
        "total_tokens": "total",
    }
    values = Counter()
    for key, raw_value in raw.items():
        mapped = aliases.get(key)
        if mapped:
            values[mapped] += integer_value(raw_value)
    total = values["total"]
    if total <= 0:
        total = values["input"] + values["output"] + values["cache_creation"] + values["cached"] + values["reasoning"]
    return Usage(
        input_tokens=values["input"],
        output_tokens=values["output"],
        cache_creation_input_tokens=values["cache_creation"],
        cached_input_tokens=values["cached"],
        reasoning_output_tokens=values["reasoning"],
        total_tokens=total,
    )


@dataclasses.dataclass
class TokenEvent:
    timestamp: Optional[str]
    cumulative_present: bool
    cumulative: Optional[Usage]
    last: Optional[Usage]
    old_last: Usage
    old_session_id: str
    model_context_window: int
    line_number: int


@dataclasses.dataclass
class ParsedFile:
    relative_path: str
    fallback_id: str
    canonical_session_id: str
    created_at: Optional[str]
    parent_session_id: Optional[str]
    events: list[TokenEvent]
    context_compacted_events: int
    session_meta_events: int


def parent_session_id(payload: Any) -> Optional[str]:
    if not isinstance(payload, dict):
        return None
    source = payload.get("source")
    if isinstance(source, dict):
        subagent = source.get("subagent")
        if isinstance(subagent, dict):
            thread_spawn = subagent.get("thread_spawn")
            if isinstance(thread_spawn, dict):
                parent = nonempty_string(thread_spawn.get("parent_thread_id"))
                if parent:
                    return parent
    return nonempty_string(payload.get("parent_thread_id")) or nonempty_string(payload.get("forked_from_id"))


def relevant_object(obj: Any) -> tuple[bool, Optional[str]]:
    if not isinstance(obj, dict):
        return False, None
    top_type = obj.get("type")
    payload = obj.get("payload")
    payload_type = payload.get("type") if isinstance(payload, dict) else None
    event_type = payload_type if payload_type in RELEVANT_TYPES else top_type
    return top_type in RELEVANT_TYPES or payload_type in RELEVANT_TYPES, event_type if isinstance(event_type, str) else None


def initial_source_entries(source_root: Path) -> list[tuple[Path, os.stat_result]]:
    entries: list[tuple[Path, os.stat_result]] = []
    for path in source_root.rglob("*.jsonl"):
        try:
            stat = path.stat()
        except OSError:
            continue
        if path.is_file():
            entries.append((path, stat))
    return sorted(entries, key=lambda item: str(item[0]))


def iter_prefix_lines(path: Path, byte_limit: int):
    """Yield (raw_line, oversized) while hashing exactly the enumerated prefix."""
    source_hash = hashlib.sha256()
    remaining = byte_limit
    pending = bytearray()
    oversized = False
    line_number = 0
    with path.open("rb") as handle:
        while remaining > 0:
            chunk = handle.read(min(READ_CHUNK_BYTES, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            source_hash.update(chunk)
            start = 0
            while start < len(chunk):
                newline = chunk.find(b"\n", start)
                end = len(chunk) if newline < 0 else newline + 1
                piece = chunk[start:end]
                if not oversized:
                    if len(pending) + len(piece) <= MAX_SWIFT_LINE_BYTES:
                        pending.extend(piece)
                    else:
                        pending.clear()
                        oversized = True
                if newline >= 0:
                    line_number += 1
                    yield line_number, bytes(pending), oversized
                    pending.clear()
                    oversized = False
                start = end
        if pending or oversized:
            line_number += 1
            yield line_number, bytes(pending), oversized
    if remaining != 0:
        raise RuntimeError(f"source truncated while freezing: {path} ({remaining} bytes missing)")
    return source_hash.hexdigest()


def freeze_accounting_copy(source_root: Path, output_root: Path) -> dict[str, Any]:
    frozen_sessions = output_root / "frozen-home" / ".codex" / "sessions"
    frozen_sessions.mkdir(parents=True)
    entries = initial_source_entries(source_root)
    manifest_files: list[dict[str, Any]] = []
    totals = Counter()
    event_counts = Counter()

    for index, (source, initial_stat) in enumerate(entries, start=1):
        relative = source.relative_to(source_root)
        target = frozen_sessions / relative
        target_handle = None
        filtered_hash = hashlib.sha256()
        source_hash = hashlib.sha256()
        source_lines = kept_lines = filtered_bytes = oversized_lines = invalid_candidate_lines = 0
        remaining = initial_stat.st_size
        pending = bytearray()
        oversized = False

        try:
            with source.open("rb") as handle:
                while remaining > 0:
                    chunk = handle.read(min(READ_CHUNK_BYTES, remaining))
                    if not chunk:
                        raise RuntimeError(f"source truncated while freezing: {source}")
                    remaining -= len(chunk)
                    source_hash.update(chunk)
                    start = 0
                    while start < len(chunk):
                        newline = chunk.find(b"\n", start)
                        end = len(chunk) if newline < 0 else newline + 1
                        piece = chunk[start:end]
                        if not oversized:
                            if len(pending) + len(piece) <= MAX_SWIFT_LINE_BYTES:
                                pending.extend(piece)
                            else:
                                pending.clear()
                                oversized = True
                        if newline >= 0:
                            source_lines += 1
                            if oversized:
                                oversized_lines += 1
                            else:
                                raw_line = bytes(pending)
                                try:
                                    obj = json.loads(raw_line.rstrip(b"\r\n"))
                                except (json.JSONDecodeError, UnicodeDecodeError):
                                    if any(marker.encode() in raw_line for marker in RELEVANT_TYPES):
                                        invalid_candidate_lines += 1
                                else:
                                    relevant, event_type = relevant_object(obj)
                                    if relevant:
                                        if target_handle is None:
                                            target.parent.mkdir(parents=True, exist_ok=True)
                                            target_handle = target.open("wb")
                                        target_handle.write(raw_line)
                                        filtered_hash.update(raw_line)
                                        kept_lines += 1
                                        filtered_bytes += len(raw_line)
                                        if event_type:
                                            event_counts[event_type] += 1
                            pending.clear()
                            oversized = False
                        start = end
                if pending or oversized:
                    source_lines += 1
                    if oversized:
                        oversized_lines += 1
                    else:
                        raw_line = bytes(pending)
                        try:
                            obj = json.loads(raw_line.rstrip(b"\r\n"))
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            if any(marker.encode() in raw_line for marker in RELEVANT_TYPES):
                                invalid_candidate_lines += 1
                        else:
                            relevant, event_type = relevant_object(obj)
                            if relevant:
                                if target_handle is None:
                                    target.parent.mkdir(parents=True, exist_ok=True)
                                    target_handle = target.open("wb")
                                target_handle.write(raw_line)
                                filtered_hash.update(raw_line)
                                kept_lines += 1
                                filtered_bytes += len(raw_line)
                                if event_type:
                                    event_counts[event_type] += 1
        finally:
            if target_handle is not None:
                target_handle.close()

        try:
            after = source.stat()
            after_size = after.st_size
            after_mtime_ns = after.st_mtime_ns
        except OSError:
            after_size = None
            after_mtime_ns = None
        changed = after_size != initial_stat.st_size or after_mtime_ns != initial_stat.st_mtime_ns
        manifest_files.append(
            {
                "relative_path": relative.as_posix(),
                "source_prefix_bytes": initial_stat.st_size,
                "source_prefix_sha256": source_hash.hexdigest(),
                "source_mtime_ns_at_enumeration": initial_stat.st_mtime_ns,
                "source_size_after_copy": after_size,
                "source_mtime_ns_after_copy": after_mtime_ns,
                "source_changed_after_enumeration": changed,
                "source_lines_in_prefix": source_lines,
                "frozen_lines": kept_lines,
                "frozen_bytes": filtered_bytes,
                "frozen_sha256": filtered_hash.hexdigest() if kept_lines else None,
                "oversized_lines_skipped_like_swift": oversized_lines,
                "invalid_relevant_candidate_lines": invalid_candidate_lines,
            }
        )
        totals["source_prefix_bytes"] += initial_stat.st_size
        totals["source_lines"] += source_lines
        totals["frozen_lines"] += kept_lines
        totals["frozen_bytes"] += filtered_bytes
        totals["oversized_lines"] += oversized_lines
        totals["invalid_candidate_lines"] += invalid_candidate_lines
        totals["changed_files"] += int(changed)
        totals["frozen_files"] += int(kept_lines > 0)
        if index % 100 == 0:
            print(f"freeze: {index}/{len(entries)} files", file=sys.stderr, flush=True)

    post_count = len(initial_source_entries(source_root))
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "created_at": utc_now(),
        "copy_kind": "semantic-complete accounting-only Codex JSONL prefix snapshot",
        "semantic_contract": (
            "All valid JSON objects consumed by TokenStep's current Codex accounting are copied verbatim and in source order: "
            "session_meta, turn_context, event_msg/token_count. event_msg/context_compacted is additionally retained for audit classification. "
            "Other event types are intentionally omitted. Lines over TokenStep's 1 MiB collector limit are omitted and counted."
        ),
        "snapshot_contract": (
            "The file list and byte size of every source file are captured before copying. Each copy is bounded to that enumerated prefix, "
            "so appends during the audit cannot change the frozen result."
        ),
        "source_root": str(source_root),
        "frozen_sessions_root": str(frozen_sessions),
        "source_file_count_at_enumeration": len(entries),
        "source_file_count_after_copy": post_count,
        "frozen_file_count": totals["frozen_files"],
        "source_prefix_bytes": totals["source_prefix_bytes"],
        "source_lines_in_prefix": totals["source_lines"],
        "frozen_lines": totals["frozen_lines"],
        "frozen_bytes": totals["frozen_bytes"],
        "source_changed_after_enumeration_files": totals["changed_files"],
        "oversized_lines_skipped_like_swift": totals["oversized_lines"],
        "invalid_relevant_candidate_lines": totals["invalid_candidate_lines"],
        "event_counts": dict(sorted(event_counts.items())),
        "files": manifest_files,
    }
    manifest_path = output_root / "manifest.json"
    write_json(manifest_path, manifest)
    manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    (output_root / "manifest.sha256").write_text(f"{manifest_hash}  manifest.json\n", encoding="utf-8")
    manifest["manifest_path"] = str(manifest_path)
    manifest["manifest_sha256"] = manifest_hash
    return manifest


def parse_frozen_sessions(frozen_root: Path) -> list[ParsedFile]:
    parsed_files: list[ParsedFile] = []
    for path in sorted(frozen_root.rglob("*.jsonl"), key=lambda item: str(item)):
        relative = path.relative_to(frozen_root).as_posix()
        fallback_id = path.stem
        canonical_id: Optional[str] = None
        created_at: Optional[str] = None
        parent_id: Optional[str] = None
        old_session_id = fallback_id
        events: list[TokenEvent] = []
        compactions = metas = 0
        with path.open("rb") as handle:
            for line_number, raw_line in enumerate(handle, start=1):
                try:
                    obj = json.loads(raw_line)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                top_type = obj.get("type") if isinstance(obj, dict) else None
                payload = obj.get("payload") if isinstance(obj, dict) else None
                payload = payload if isinstance(payload, dict) else {}
                payload_type = payload.get("type")
                if top_type == "session_meta":
                    metas += 1
                    meta_id = nonempty_string(payload.get("id"))
                    if meta_id:
                        old_session_id = meta_id
                        if canonical_id is None:
                            canonical_id = meta_id
                            created_at = nonempty_string(obj.get("timestamp")) or nonempty_string(payload.get("timestamp"))
                            parent_id = parent_session_id(payload)
                if top_type == "event_msg" and payload_type == "context_compacted":
                    compactions += 1
                if not (top_type == "event_msg" and payload_type == "token_count"):
                    continue
                info = payload.get("info")
                if not isinstance(info, dict):
                    continue
                events.append(
                    TokenEvent(
                        timestamp=nonempty_string(obj.get("timestamp")),
                        cumulative_present="total_token_usage" in info,
                        cumulative=normalize_codex(info.get("total_token_usage")),
                        last=normalize_codex(info.get("last_token_usage")),
                        old_last=normalize_old(info.get("last_token_usage")),
                        old_session_id=old_session_id,
                        model_context_window=integer_value(info.get("model_context_window")),
                        line_number=line_number,
                    )
                )
        parsed_files.append(
            ParsedFile(
                relative_path=relative,
                fallback_id=fallback_id,
                canonical_session_id=canonical_id or fallback_id,
                created_at=created_at,
                parent_session_id=parent_id,
                events=events,
                context_compacted_events=compactions,
                session_meta_events=metas,
            )
        )
    return parsed_files


def empty_file_result(scan: ParsedFile) -> dict[str, Any]:
    return {
        "relative_path": scan.relative_path,
        "canonical_session_id": scan.canonical_session_id,
        "parent_session_id": scan.parent_session_id,
        "context_compacted_events": scan.context_compacted_events,
        "raw_token_events": len(scan.events),
        "tokens": 0,
        "records": 0,
        "components": Usage().report_dict(),
        "diagnostics": {},
    }


def old_accounting(scans: list[ParsedFile]) -> dict[str, Any]:
    seen: set[str] = set()
    total = Usage()
    records = 0
    skipped = duplicates = 0
    per_file: dict[str, dict[str, Any]] = {}
    for scan in scans:
        file_usage = Usage()
        file_records = 0
        event_index = 0
        for event in scan.events:
            usage = event.old_last
            if usage.total_tokens <= 0 or parse_iso(event.timestamp) is None:
                skipped += 1
                continue
            event_index += 1
            key = f"{event.old_session_id}|{event.timestamp}|{event_index}|{usage.total_tokens}"
            if key in seen:
                duplicates += 1
                continue
            seen.add(key)
            records += 1
            file_records += 1
            total = total.add(usage)
            file_usage = file_usage.add(usage)
        row = empty_file_result(scan)
        row.update(tokens=file_usage.total_tokens, records=file_records, components=file_usage.report_dict())
        per_file[scan.relative_path] = row
    return {
        "algorithm": "v5_last_token_usage_sum",
        "tokens": total.total_tokens,
        "records": records,
        "components": total.report_dict(),
        "diagnostics": {"skipped_records": skipped, "duplicate_records": duplicates},
        "per_file": per_file,
    }


def is_breakdown_consistent(usage: Usage, total: int) -> bool:
    return (
        min(
            usage.input_tokens,
            usage.output_tokens,
            usage.cache_creation_input_tokens,
            usage.cached_input_tokens,
            usage.reasoning_output_tokens,
        )
        >= 0
        and usage.input_tokens + usage.output_tokens == total
        and usage.cache_creation_input_tokens + usage.cached_input_tokens <= usage.input_tokens
        and usage.reasoning_output_tokens <= usage.output_tokens
    )


def is_context_window_sentinel(event: TokenEvent) -> bool:
    current = event.cumulative
    return bool(
        current
        and current.input_tokens == 0
        and current.output_tokens == 0
        and current.cache_creation_input_tokens == 0
        and current.cached_input_tokens == 0
        and current.reasoning_output_tokens == 0
        and (event.last.total_tokens if event.last else 0) == 0
        and event.model_context_window > 0
        and current.total_tokens == event.model_context_window
    )


def is_credible_reset(index: int, events: list[TokenEvent], current: Usage, previous: Usage) -> bool:
    last = events[index].last
    if last and last.total_tokens == current.total_tokens and is_breakdown_consistent(last, current.total_tokens):
        return True
    for candidate in events[index + 1 :]:
        if not candidate.cumulative_present:
            continue
        next_usage = candidate.cumulative
        if not next_usage or next_usage.total_tokens <= 0:
            continue
        if next_usage.total_tokens == current.total_tokens:
            continue
        return next_usage.total_tokens > current.total_tokens and next_usage.total_tokens < previous.total_tokens
    return False


def increment_usage(current: Usage, previous: Optional[Usage], last: Optional[Usage], total: int) -> tuple[Usage, bool]:
    if last and last.total_tokens == total and is_breakdown_consistent(last, total):
        return dataclasses.replace(last, total_tokens=total), True
    baseline = previous or Usage()
    if (
        current.input_tokens < baseline.input_tokens
        or current.output_tokens < baseline.output_tokens
        or current.cache_creation_input_tokens < baseline.cache_creation_input_tokens
        or current.cached_input_tokens < baseline.cached_input_tokens
        or current.reasoning_output_tokens < baseline.reasoning_output_tokens
    ):
        return Usage(total_tokens=total), False
    result = Usage(
        input_tokens=current.input_tokens - baseline.input_tokens,
        output_tokens=current.output_tokens - baseline.output_tokens,
        cache_creation_input_tokens=(
            current.cache_creation_input_tokens - baseline.cache_creation_input_tokens
        ),
        cached_input_tokens=current.cached_input_tokens - baseline.cached_input_tokens,
        reasoning_output_tokens=current.reasoning_output_tokens - baseline.reasoning_output_tokens,
        total_tokens=total,
    )
    if not is_breakdown_consistent(result, total):
        return Usage(total_tokens=total), False
    return result, True


def run_self_test() -> None:
    previous = Usage(
        input_tokens=100,
        output_tokens=20,
        cache_creation_input_tokens=30,
        cached_input_tokens=40,
        reasoning_output_tokens=5,
        total_tokens=120,
    )
    current = Usage(
        input_tokens=160,
        output_tokens=30,
        cache_creation_input_tokens=50,
        cached_input_tokens=70,
        reasoning_output_tokens=7,
        total_tokens=190,
    )
    expected_increment = Usage(
        input_tokens=60,
        output_tokens=10,
        cache_creation_input_tokens=20,
        cached_input_tokens=30,
        reasoning_output_tokens=2,
        total_tokens=70,
    )
    increment, known = increment_usage(current, previous, None, 70)
    if not known or increment != expected_increment:
        raise AssertionError(f"cache-creation delta mismatch: {increment!r}, known={known}")
    if increment.report_dict()["uncached_input_tokens"] != 10:
        raise AssertionError(f"uncached input mismatch: {increment.report_dict()!r}")
    if not is_breakdown_consistent(increment, increment.total_tokens):
        raise AssertionError("valid cache-creation breakdown was rejected")

    invalid_breakdown = Usage(
        input_tokens=10,
        output_tokens=0,
        cache_creation_input_tokens=6,
        cached_input_tokens=5,
        total_tokens=10,
    )
    if is_breakdown_consistent(invalid_breakdown, invalid_breakdown.total_tokens):
        raise AssertionError("overlapping cache buckets were accepted as a valid input subset")

    cache_creation_sentinel = TokenEvent(
        timestamp="2026-07-19T00:00:00Z",
        cumulative_present=True,
        cumulative=Usage(cache_creation_input_tokens=1, total_tokens=100),
        last=Usage(),
        old_last=Usage(),
        old_session_id="self-test",
        model_context_window=100,
        line_number=1,
    )
    if is_context_window_sentinel(cache_creation_sentinel):
        raise AssertionError("nonzero cache-creation usage was discarded as a context-window sentinel")

    regressed_cache_creation = dataclasses.replace(
        current,
        input_tokens=200,
        output_tokens=40,
        cache_creation_input_tokens=20,
        cached_input_tokens=80,
        total_tokens=240,
    )
    unknown_increment, regressed_known = increment_usage(
        regressed_cache_creation,
        current,
        None,
        50,
    )
    if regressed_known or unknown_increment != Usage(total_tokens=50):
        raise AssertionError(
            "a regressed cache-creation counter was not downgraded to unknown breakdown"
        )


def fork_anchor(scan: ParsedFile, by_session: dict[str, ParsedFile]) -> Optional[Usage]:
    if not scan.parent_session_id:
        return None
    parent = by_session.get(scan.parent_session_id)
    child_created = parse_iso(scan.created_at)
    if not parent or child_created is None:
        return None
    anchor = None
    for event in parent.events:
        timestamp = parse_iso(event.timestamp)
        if (
            event.cumulative_present
            and event.cumulative
            and event.cumulative.total_tokens > 0
            and timestamp is not None
            and timestamp <= child_created
        ):
            anchor = event.cumulative
    return anchor


def add_diagnostics(target: Counter, source: Counter) -> None:
    for key, value in source.items():
        target[key] += value


def new_accounting(scans: list[ParsedFile]) -> dict[str, Any]:
    by_session: dict[str, ParsedFile] = {}
    for scan in scans:
        by_session.setdefault(scan.canonical_session_id, scan)
    seen: set[str] = set()
    total = Usage()
    total_records = 0
    all_diagnostics = Counter()
    per_file: dict[str, dict[str, Any]] = {}

    for scan in scans:
        diagnostics = Counter(raw_records=len(scan.events))
        file_usage = Usage()
        file_records = 0
        has_cumulative_schema = any(event.cumulative_present for event in scan.events)

        if not has_cumulative_schema:
            for event in scan.events:
                usage = event.last
                if not usage or usage.total_tokens <= 0 or parse_iso(event.timestamp) is None:
                    diagnostics["skipped_records"] += 1
                    continue
                request_id = f"codex:legacy:{scan.canonical_session_id}:{event.timestamp}:{usage.fingerprint}"
                if request_id in seen:
                    diagnostics["duplicate_records"] += 1
                    continue
                seen.add(request_id)
                file_usage = file_usage.add(usage)
                total = total.add(usage)
                file_records += 1
                total_records += 1
                diagnostics["legacy_records"] += 1
                if not is_breakdown_consistent(usage, usage.total_tokens):
                    diagnostics["unknown_breakdown_records"] += 1
        else:
            start_index = 0
            previous: Optional[Usage] = None
            anchor = fork_anchor(scan, by_session)
            if anchor and anchor.total_tokens > 0:
                anchor_index = next(
                    (
                        index
                        for index, event in enumerate(scan.events)
                        if event.cumulative_present and event.cumulative == anchor
                    ),
                    None,
                )
                if anchor_index is not None:
                    previous = anchor
                    start_index = anchor_index + 1
                    diagnostics["inherited_records"] = sum(
                        1 for event in scan.events[: anchor_index + 1] if event.cumulative_present
                    )
                    diagnostics["inherited_tokens"] = anchor.total_tokens

            epoch = 0
            for index in range(start_index, len(scan.events)):
                event = scan.events[index]
                if not event.cumulative_present:
                    diagnostics["skipped_records"] += 1
                    continue
                current = event.cumulative
                if not current or current.total_tokens <= 0 or parse_iso(event.timestamp) is None:
                    diagnostics["skipped_records"] += 1
                    continue
                reset = False
                if previous:
                    if current.total_tokens == previous.total_tokens:
                        diagnostics["duplicate_records"] += 1
                        continue
                    if current.total_tokens > previous.total_tokens:
                        delta_total = current.total_tokens - previous.total_tokens
                    elif is_context_window_sentinel(event):
                        diagnostics["skipped_records"] += 1
                        continue
                    elif is_credible_reset(index, scan.events, current, previous):
                        epoch += 1
                        diagnostics["counter_resets"] += 1
                        delta_total = current.total_tokens
                        reset = True
                    else:
                        diagnostics["skipped_records"] += 1
                        continue
                else:
                    delta_total = current.total_tokens
                if delta_total <= 0:
                    continue
                usage, known = increment_usage(current, None if reset else previous, event.last, delta_total)
                request_id = f"codex:cumulative:{scan.canonical_session_id}:{epoch}:{current.total_tokens}"
                if request_id in seen:
                    diagnostics["duplicate_records"] += 1
                    previous = current
                    continue
                seen.add(request_id)
                file_usage = file_usage.add(usage)
                total = total.add(usage)
                file_records += 1
                total_records += 1
                diagnostics["exact_records"] += 1
                if not known:
                    diagnostics["unknown_breakdown_records"] += 1
                previous = current

        row = empty_file_result(scan)
        row.update(
            tokens=file_usage.total_tokens,
            records=file_records,
            components=file_usage.report_dict(),
            diagnostics=dict(sorted(diagnostics.items())),
        )
        per_file[scan.relative_path] = row
        add_diagnostics(all_diagnostics, diagnostics)

    return {
        "algorithm": "total_token_usage_delta_v6_with_legacy_fallback",
        "accounting_revision": ACCOUNTING_REVISION,
        "tokens": total.total_tokens,
        "records": total_records,
        "components": total.report_dict(),
        "diagnostics": dict(sorted(all_diagnostics.items())),
        "per_file": per_file,
    }


def stable_projection(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "algorithm": result["algorithm"],
        "accounting_revision": result["accounting_revision"],
        "tokens": result["tokens"],
        "records": result["records"],
        "components": result["components"],
        "diagnostics": result["diagnostics"],
        "per_file": result["per_file"],
    }


def strict_normal_control(scan: ParsedFile, duplicate_ids: set[str]) -> bool:
    if (
        scan.parent_session_id
        or scan.context_compacted_events
        or scan.canonical_session_id in duplicate_ids
        or not scan.events
        or not all(event.cumulative_present for event in scan.events)
    ):
        return False
    previous = 0
    for event in scan.events:
        current = event.cumulative
        if not current or current.total_tokens <= previous or parse_iso(event.timestamp) is None:
            return False
        if event.old_last.total_tokens != current.total_tokens - previous:
            return False
        previous = current.total_tokens
    return True


def comparison_report(scans: list[ParsedFile], old: dict[str, Any], new: dict[str, Any], top_count: int) -> dict[str, Any]:
    per_file: list[dict[str, Any]] = []
    for scan in scans:
        old_row = old["per_file"][scan.relative_path]
        new_row = new["per_file"][scan.relative_path]
        per_file.append(
            {
                "relative_path": scan.relative_path,
                "canonical_session_id": scan.canonical_session_id,
                "parent_session_id": scan.parent_session_id,
                "context_compacted_events": scan.context_compacted_events,
                "old_tokens": old_row["tokens"],
                "new_tokens": new_row["tokens"],
                "old_minus_new": old_row["tokens"] - new_row["tokens"],
                "new_diagnostics": new_row["diagnostics"],
            }
        )
    top_differences = sorted(per_file, key=lambda row: abs(row["old_minus_new"]), reverse=True)[:top_count]

    compaction_rows = [row for row in per_file if row["context_compacted_events"] > 0]
    child_rows = [row for row in per_file if row["parent_session_id"]]
    replay_rows = [row for row in child_rows if row["new_diagnostics"].get("inherited_records", 0) > 0]
    isolated_rows = [row for row in child_rows if row["new_diagnostics"].get("inherited_records", 0) == 0]
    reset_rows = [row for row in per_file if row["new_diagnostics"].get("counter_resets", 0) > 0]
    legacy_rows = [row for row in per_file if row["new_diagnostics"].get("legacy_records", 0) > 0]

    id_counts = Counter(scan.canonical_session_id for scan in scans)
    duplicate_ids = {key for key, count in id_counts.items() if count > 1}
    controls = [scan for scan in scans if strict_normal_control(scan, duplicate_ids)]
    control_rows = [next(row for row in per_file if row["relative_path"] == scan.relative_path) for scan in controls]
    control_matches = [row for row in control_rows if row["old_tokens"] == row["new_tokens"]]
    control_mismatches = [row for row in control_rows if row["old_tokens"] != row["new_tokens"]]

    def cohort(rows: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "files": len(rows),
            "old_tokens": sum(row["old_tokens"] for row in rows),
            "new_tokens": sum(row["new_tokens"] for row in rows),
            "old_minus_new": sum(row["old_minus_new"] for row in rows),
        }

    old_tokens = old["tokens"]
    new_tokens = new["tokens"]
    return {
        "old_total_tokens": old_tokens,
        "new_total_tokens": new_tokens,
        "new_minus_old": new_tokens - old_tokens,
        "old_minus_new": old_tokens - new_tokens,
        "new_to_old_ratio": (new_tokens / old_tokens) if old_tokens else None,
        "repeated_cumulative_events": new["diagnostics"].get("duplicate_records", 0),
        "counter_resets": new["diagnostics"].get("counter_resets", 0),
        "legacy_fallback_records": new["diagnostics"].get("legacy_records", 0),
        "inherited_replay_records_removed": new["diagnostics"].get("inherited_records", 0),
        "inherited_parent_baseline_tokens": new["diagnostics"].get("inherited_tokens", 0),
        "compaction_cohort": {
            **cohort(compaction_rows),
            "context_compacted_events": sum(row["context_compacted_events"] for row in compaction_rows),
            "top_differences": sorted(compaction_rows, key=lambda row: abs(row["old_minus_new"]), reverse=True)[:top_count],
        },
        "subagent_cohort": {
            **cohort(child_rows),
            "replay_child_files": len(replay_rows),
            "isolated_child_files": len(isolated_rows),
            "replay_old_tokens": sum(row["old_tokens"] for row in replay_rows),
            "replay_new_tokens": sum(row["new_tokens"] for row in replay_rows),
            "inherited_parent_baseline_tokens": sum(
                row["new_diagnostics"].get("inherited_tokens", 0) for row in replay_rows
            ),
            "top_differences": sorted(child_rows, key=lambda row: abs(row["old_minus_new"]), reverse=True)[:top_count],
        },
        "reset_cohort": {**cohort(reset_rows), "details": reset_rows[:top_count]},
        "legacy_cohort": {**cohort(legacy_rows), "details": legacy_rows[:top_count]},
        "strict_normal_no_repeat_control": {
            "definition": (
                "root sessions with no compaction, no duplicate canonical ID, cumulative data on every token event, "
                "strictly increasing totals, and last_token_usage exactly equal to each cumulative delta"
            ),
            "files": len(control_rows),
            "matching_files": len(control_matches),
            "mismatching_files": len(control_mismatches),
            "old_tokens": sum(row["old_tokens"] for row in control_rows),
            "new_tokens": sum(row["new_tokens"] for row in control_rows),
            "mismatches": control_mismatches[:top_count],
        },
        "top_session_differences": top_differences,
    }


SWIFT_HARNESS = r'''
import Foundation

@main
struct TokenStepAccountingAuditHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: audit-harness <frozen-home>\n", stderr)
            exit(64)
        }
        let home = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let snapshot = UsageCollector.collectCodexUsageSnapshotForTests(homeURL: home)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(snapshot))
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
'''


def normalized_swift_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    normalized = json.loads(json.dumps(snapshot))
    normalized.pop("generated_at", None)
    return normalized


def compile_and_run_swift(repo_root: Path, output_root: Path, frozen_home: Path) -> dict[str, Any]:
    swift_dir = repo_root / "TokenStepSwift"
    source_paths = [
        swift_dir / "Sources/TokenStepSwift/Support/AppPaths.swift",
        swift_dir / "Sources/TokenStepSwift/Support/Localization.swift",
        swift_dir / "Sources/TokenStepSwift/Support/Theme.swift",
        swift_dir / "Sources/TokenStepSwift/Models/UsageModels.swift",
        swift_dir / "Sources/TokenStepSwift/Services/UsageCollector.swift",
    ]
    for source in source_paths:
        if not source.is_file():
            raise RuntimeError(f"missing Swift source: {source}")
    harness_dir = output_root / "swift-harness"
    module_cache = harness_dir / "module-cache"
    overlay_dir = harness_dir / "vfs-overlay"
    harness_dir.mkdir()
    module_cache.mkdir()
    overlay_dir.mkdir()
    harness_source = harness_dir / "main.swift"
    harness_source.write_text(SWIFT_HARNESS, encoding="utf-8")
    empty_modulemap = overlay_dir / "empty.modulemap"
    empty_modulemap.write_text("// Intentionally empty.\n", encoding="utf-8")
    overlay = overlay_dir / "overlay.yaml"
    write_json(
        overlay,
        {
            "version": 0,
            "roots": [
                {
                    "type": "directory",
                    "name": "/Library/Developer/CommandLineTools/usr/include/swift",
                    "contents": [
                        {
                            "type": "file",
                            "name": "module.modulemap",
                            "external-contents": str(empty_modulemap),
                        }
                    ],
                }
            ],
        },
    )
    source_hashes_before = {str(path.relative_to(repo_root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths}
    executable = harness_dir / "tokenstep-accounting-audit"
    machine = platform.machine()
    arch = "arm64" if machine == "arm64" else "x86_64"
    command = [
        "swiftc",
        "-target",
        f"{arch}-apple-macos14.0",
        "-vfsoverlay",
        str(overlay),
        "-Xcc",
        "-ivfsoverlay",
        "-Xcc",
        str(overlay),
        "-parse-as-library",
        *map(str, source_paths),
        str(harness_source),
        "-o",
        str(executable),
    ]
    env = os.environ.copy()
    env.update(
        {
            "TMPDIR": str(harness_dir / "tmp"),
            "CLANG_MODULE_CACHE_PATH": str(module_cache),
            "SWIFT_MODULECACHE_PATH": str(module_cache),
            "HOME": str(frozen_home),
        }
    )
    Path(env["TMPDIR"]).mkdir()
    compile_run = subprocess.run(command, cwd=repo_root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (harness_dir / "compile.log").write_text(compile_run.stdout, encoding="utf-8")
    if compile_run.returncode != 0:
        raise RuntimeError(f"Swift harness compile failed; see {harness_dir / 'compile.log'}")
    source_hashes_after = {str(path.relative_to(repo_root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths}
    if source_hashes_before != source_hashes_after:
        raise RuntimeError("Swift collector sources changed during harness compilation; rerun the audit")

    snapshots = []
    hashes = []
    for run_index in (1, 2):
        run = subprocess.run(
            [str(executable), str(frozen_home)],
            cwd=repo_root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        (harness_dir / f"run-{run_index}.stderr.log").write_text(run.stderr, encoding="utf-8")
        if run.returncode != 0:
            raise RuntimeError(f"Swift harness run {run_index} failed: {run.stderr.strip()}")
        try:
            snapshot = json.loads(run.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeError(f"Swift harness run {run_index} returned invalid JSON: {error}") from error
        write_json(harness_dir / f"run-{run_index}.json", snapshot)
        snapshots.append(snapshot)
        hashes.append(digest_json(normalized_swift_snapshot(snapshot)))
    return {
        "compiled_from_worktree": True,
        "compile_command": command,
        "source_sha256": source_hashes_after,
        "run_1_stable_sha256": hashes[0],
        "run_2_stable_sha256": hashes[1],
        "two_runs_identical": hashes[0] == hashes[1],
        "snapshot": snapshots[0],
        "artifacts": str(harness_dir),
    }


def swift_python_parity(swift: dict[str, Any], python_new: dict[str, Any]) -> dict[str, Any]:
    snapshot = swift["snapshot"]
    source = snapshot.get("sources", {}).get("Codex", {})
    fields = {
        "accounting_revision": (source.get("accounting_revision"), python_new["accounting_revision"]),
        "strategy": (source.get("strategy"), python_new["algorithm"]),
        "tokens": (snapshot.get("totals", {}).get("tokens"), python_new["tokens"]),
        "records": (source.get("records"), python_new["records"]),
        "raw_records": (source.get("raw_records"), python_new["diagnostics"].get("raw_records", 0)),
        "exact_records": (source.get("exact_records"), python_new["diagnostics"].get("exact_records", 0)),
        "legacy_records": (source.get("legacy_records"), python_new["diagnostics"].get("legacy_records", 0)),
        "duplicate_records": (source.get("duplicate_records"), python_new["diagnostics"].get("duplicate_records", 0)),
        "counter_resets": (source.get("counter_resets"), python_new["diagnostics"].get("counter_resets", 0)),
        "inherited_records": (source.get("inherited_records"), python_new["diagnostics"].get("inherited_records", 0)),
        "inherited_tokens": (source.get("inherited_tokens"), python_new["diagnostics"].get("inherited_tokens", 0)),
        "skipped_records": (source.get("skipped_records"), python_new["diagnostics"].get("skipped_records", 0)),
        "unknown_breakdown_records": (
            source.get("unknown_breakdown_records"),
            python_new["diagnostics"].get("unknown_breakdown_records", 0),
        ),
    }
    swift_breakdown = source.get("token_breakdown", {})
    for key in ("processed_tokens", "input_tokens", "cached_input_tokens", "uncached_input_tokens", "output_tokens", "reasoning_tokens"):
        fields[f"breakdown.{key}"] = (swift_breakdown.get(key), python_new["components"].get(key))
    mismatches = {key: {"swift": values[0], "python": values[1]} for key, values in fields.items() if values[0] != values[1]}
    return {"matches": not mismatches, "checked_fields": len(fields), "mismatches": mismatches}


def n(value: Any) -> str:
    return f"{value:,}" if isinstance(value, int) else str(value)


def markdown_report(report: dict[str, Any]) -> str:
    freeze = report["freeze"]
    compare = report["comparison"]
    validation = report["validation"]
    compaction = compare["compaction_cohort"]
    subagent = compare["subagent_cohort"]
    control = compare["strict_normal_no_repeat_control"]
    lines = [
        "# TokenStep Codex 历史 Token 记账审计",
        "",
        f"生成时间：`{report['generated_at']}`",
        "",
        "## 结论",
        "",
        f"- 旧口径（逐条累加 `last_token_usage`）：**{n(compare['old_total_tokens'])}** Token",
        f"- 当前新口径（`total_token_usage` 真实累计增量）：**{n(compare['new_total_tokens'])}** Token",
        f"- 校准差额（旧 - 新）：**{n(compare['old_minus_new'])}** Token",
        f"- 新 / 旧比例：**{compare['new_to_old_ratio']:.4f}**" if compare["new_to_old_ratio"] is not None else "- 新 / 旧比例：N/A",
        "",
        "## 安全与冻结证据",
        "",
        f"- 原日志只读目录：`{freeze['source_root']}`",
        f"- accounting-only 副本：`{freeze['frozen_sessions_root']}`",
        f"- 枚举源文件：**{n(freeze['source_file_count_at_enumeration'])}**；冻结文件：**{n(freeze['frozen_file_count'])}**",
        f"- 冻结相关行：**{n(freeze['frozen_lines'])}**；副本大小：**{n(freeze['frozen_bytes'])}** bytes",
        f"- Manifest SHA-256：`{freeze['manifest_sha256']}`",
        f"- 枚举后发生追加/变化的源文件：**{n(freeze['source_changed_after_enumeration_files'])}**（按枚举时 byte prefix 冻结，不影响结果）",
        f"- 超过 Swift 1 MiB 限制并按真实 collector 行为跳过的行：**{n(freeze['oversized_lines_skipped_like_swift'])}**",
        f"- 疑似相关但无效 JSON 行：**{n(freeze['invalid_relevant_candidate_lines'])}**",
        "",
        "该副本保留当前记账所需的全部有效 `session_meta`、`turn_context`、`token_count`，并额外保留 `context_compacted` 用于审计分类；其余对记账无影响的内容已省略。",
        "",
        "## 关键异常量化",
        "",
        f"- 重复累计事件（同累计记 0）：**{n(compare['repeated_cumulative_events'])}**",
        f"- 可信 counter reset：**{n(compare['counter_resets'])}**",
        f"- legacy fallback 记录：**{n(compare['legacy_fallback_records'])}**",
        f"- 子 Agent replay 移除记录：**{n(compare['inherited_replay_records_removed'])}**",
        f"- 子 Agent 父基线锚点合计：**{n(compare['inherited_parent_baseline_tokens'])}** Token",
        "",
        "### Context compaction 会话",
        "",
        f"- 文件：**{n(compaction['files'])}**；`context_compacted` 事件：**{n(compaction['context_compacted_events'])}**",
        f"- 旧：**{n(compaction['old_tokens'])}**；新：**{n(compaction['new_tokens'])}**；旧 - 新：**{n(compaction['old_minus_new'])}**",
        "",
        "### 子 Agent baseline 去重",
        "",
        f"- 子 Agent 文件：**{n(subagent['files'])}**；确认 replay：**{n(subagent['replay_child_files'])}**；独立计数器：**{n(subagent['isolated_child_files'])}**",
        f"- 子 Agent 旧：**{n(subagent['old_tokens'])}**；新：**{n(subagent['new_tokens'])}**；旧 - 新：**{n(subagent['old_minus_new'])}**",
        "",
        "### 正常无重复对照组",
        "",
        f"- 严格对照文件：**{n(control['files'])}**；旧新一致：**{n(control['matching_files'])}**；不一致：**{n(control['mismatching_files'])}**",
        f"- 对照组旧：**{n(control['old_tokens'])}**；新：**{n(control['new_tokens'])}**",
        "",
        "## 可重复性与实现一致性",
        "",
        f"- Python 当前口径镜像连续两次一致：**{'PASS' if validation['python_two_runs_identical'] else 'FAIL'}**",
    ]
    swift = validation.get("swift")
    if swift:
        lines.extend(
            [
                f"- 当前工作树 Swift 当前口径连续两次一致：**{'PASS' if swift['two_runs_identical'] else 'FAIL'}**",
                f"- Python 镜像与 Swift 关键字段一致：**{'PASS' if validation['swift_python_parity']['matches'] else 'FAIL'}**",
                f"- Swift 稳定结果 SHA-256：`{swift['run_1_stable_sha256']}`",
            ]
        )
    else:
        lines.append("- Swift harness：跳过")
    lines.extend(["", "## 差异最大的会话文件", "", "| 文件 | 旧 Token | 新 Token | 旧 - 新 | compaction | parent |", "|---|---:|---:|---:|---:|---|"])
    for row in compare["top_session_differences"]:
        parent = row["parent_session_id"] or ""
        lines.append(
            f"| `{row['relative_path']}` | {n(row['old_tokens'])} | {n(row['new_tokens'])} | {n(row['old_minus_new'])} | {n(row['context_compacted_events'])} | `{parent}` |"
        )
    lines.extend(
        [
            "",
            "## 验收状态",
            "",
            f"**{'PASS' if report['overall_pass'] else 'FAIL'}**",
            "",
            "完整机器可读数据见同目录 `report.json`；真实 Swift 两次输出及编译日志见 `swift-harness/`。",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path.home() / ".codex" / "sessions")
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--skip-swift", action="store_true", help="Run only the Python mirror (not sufficient for release proof).")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Verify cache-creation accounting semantics without reading local Codex data.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        run_self_test()
        print("audit_codex_accounting self-test passed")
        return 0

    source_root = args.source_root.expanduser().resolve()
    repo_root = args.repo_root.expanduser().resolve()
    tmp_root = Path("/tmp").resolve()
    if args.output_root:
        output_root = args.output_root.expanduser().resolve()
    else:
        stamp = dt.datetime.now().strftime("%Y%m%dT%H%M%S")
        output_root = (tmp_root / f"tokenstep-codex-accounting-audit-{stamp}-{os.getpid()}").resolve()
    if not source_root.is_dir():
        raise SystemExit(f"source root does not exist: {source_root}")
    if not is_under(output_root, tmp_root):
        raise SystemExit(f"refusing non-/tmp output: {output_root}")
    if output_root.exists():
        raise SystemExit(f"refusing to overwrite existing output: {output_root}")
    if is_under(output_root, source_root) or is_under(source_root, output_root):
        raise SystemExit("source and output trees must not overlap")
    output_root.mkdir(parents=True)

    print(f"audit output: {output_root}", file=sys.stderr, flush=True)
    print("phase 1/4: freezing accounting-only source prefixes", file=sys.stderr, flush=True)
    freeze = freeze_accounting_copy(source_root, output_root)
    frozen_root = Path(freeze["frozen_sessions_root"])

    print("phase 2/4: running old algorithm and current Python accounting twice", file=sys.stderr, flush=True)
    scans_1 = parse_frozen_sessions(frozen_root)
    old = old_accounting(scans_1)
    new_1 = new_accounting(scans_1)
    scans_2 = parse_frozen_sessions(frozen_root)
    new_2 = new_accounting(scans_2)
    python_hash_1 = digest_json(stable_projection(new_1))
    python_hash_2 = digest_json(stable_projection(new_2))
    comparison = comparison_report(scans_1, old, new_1, max(1, args.top))

    swift_result = None
    parity = None
    swift_error = None
    if not args.skip_swift:
        print("phase 3/4: compiling and running isolated current Swift accounting harness twice", file=sys.stderr, flush=True)
        try:
            swift_result = compile_and_run_swift(repo_root, output_root, output_root / "frozen-home")
            parity = swift_python_parity(swift_result, new_1)
        except Exception as error:  # Preserve Python audit evidence even when the harness fails.
            swift_error = str(error)
            (output_root / "swift-error.txt").write_text(swift_error + "\n", encoding="utf-8")

    print("phase 4/4: writing reports and evaluating gates", file=sys.stderr, flush=True)
    validation = {
        "python_run_1_sha256": python_hash_1,
        "python_run_2_sha256": python_hash_2,
        "python_two_runs_identical": python_hash_1 == python_hash_2,
        "swift": ({key: value for key, value in swift_result.items() if key != "snapshot"} if swift_result else None),
        "swift_error": swift_error,
        "swift_python_parity": parity,
    }
    overall_pass = (
        validation["python_two_runs_identical"]
        and comparison["strict_normal_no_repeat_control"]["mismatching_files"] == 0
        and freeze["invalid_relevant_candidate_lines"] == 0
        and (args.skip_swift or (swift_result is not None and swift_result["two_runs_identical"] and parity and parity["matches"]))
    )
    report = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": utc_now(),
        "safety": {
            "source_opened_read_only": True,
            "writes_confined_to_tmp": True,
            "production_tokenstep_cache_touched": False,
            "installed_or_running_app_touched": False,
        },
        "freeze": {key: value for key, value in freeze.items() if key != "files"},
        "old_algorithm": {key: value for key, value in old.items() if key != "per_file"},
        "new_algorithm": {key: value for key, value in new_1.items() if key != "per_file"},
        "comparison": comparison,
        "validation": validation,
        "overall_pass": bool(overall_pass),
        "artifacts": {
            "root": str(output_root),
            "manifest": str(output_root / "manifest.json"),
            "manifest_hash": str(output_root / "manifest.sha256"),
            "json_report": str(output_root / "report.json"),
            "markdown_report": str(output_root / "report.md"),
        },
    }
    write_json(output_root / "report.json", report)
    (output_root / "report.md").write_text(markdown_report(report), encoding="utf-8")
    print(f"report: {output_root / 'report.md'}", file=sys.stderr)
    print(f"result: {'PASS' if overall_pass else 'FAIL'}", file=sys.stderr)
    return 0 if overall_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())

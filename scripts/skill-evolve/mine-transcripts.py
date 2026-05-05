"""
mine-transcripts.py — Transcript miner for the skill-evolve pipeline.

Reads Claude Code session transcript JSONL files, runs per-turn friction
detection using taxonomy.py rules, and emits a friction-event JSONL to
stdout. Each emitted line is a valid JSON object with the 8-field schema.

Usage:
  python3 mine-transcripts.py [options] [transcript.jsonl ...]
  python3 mine-transcripts.py --all [options]

Options:
  --all               Glob all ~/.claude/projects/*/*.jsonl
  --since <iso8601>   Only process files modified after this date
                      (default: 30 days ago)
  --limit <N>         Stop after emitting N friction events (0 = unlimited)
  --help              Show this message and exit

Output:
  One JSON object per line on stdout. Fields:
    session_id       — UUID from transcript filename
    project          — parent directory name of the transcript
    transcript_path  — absolute path to the source JSONL
    turn_index       — 0-based index of the turn within the transcript
    category         — one of taxonomy.CATEGORIES
    evidence_quote   — ≤200-char snippet (redacted)
    fingerprint      — sha1 of normalized evidence
    occurred_at      — ISO8601 timestamp from the transcript turn
"""

import argparse
import glob
import hashlib
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone, timedelta

# Ensure the script's own directory is on the path so sibling modules load.
_HERE = pathlib.Path(__file__).parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import redact
import taxonomy

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_PROJECTS_ROOT = pathlib.Path("~/.claude/projects").expanduser()


def _normalize(text: str) -> str:
    """Normalize evidence for fingerprinting: lowercase, strip whitespace, remove digits."""
    s = text.lower()
    s = re.sub(r"\d+", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _fingerprint(evidence: str) -> str:
    """SHA1 hex digest of normalized evidence."""
    normalized = _normalize(evidence)
    return hashlib.sha1(normalized.encode("utf-8")).hexdigest()


def _extract_text(content) -> str:
    """
    Recursively extract plain text from a content field that may be:
    - a bare string
    - a list of content-block dicts with 'type' and 'text'
    """
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                t = item.get("type", "")
                if t in ("text", "thinking"):
                    parts.append(item.get("text", ""))
                elif t == "tool_result":
                    parts.append(_extract_text(item.get("content", "")))
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return ""


def _parse_turns(path: pathlib.Path):
    """
    Stream-parse a transcript JSONL file and yield turn dicts:
      {
        'turn_index': int,
        'type': 'user' | 'assistant',
        'timestamp': str,          # ISO8601 or empty
        'assistant_text': str,
        'user_text': str,
        'tool_result_texts': [str],
        'tool_uses': [(name, is_error)],  # from tool_result is_error flag
      }

    We accumulate tool_result items from user turns that follow an assistant
    turn (they carry the tool_result content blocks).
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return

    turn_index = 0
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            continue

        obj_type = obj.get("type")
        timestamp = obj.get("timestamp", "")

        if obj_type == "assistant":
            message = obj.get("message", {})
            content = message.get("content", [])
            assistant_text = ""
            tool_uses = []

            if isinstance(content, list):
                text_parts = []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type", "")
                    if btype in ("text", "thinking"):
                        text_parts.append(block.get("text", ""))
                    elif btype == "tool_use":
                        tool_uses.append(block.get("name", ""))
                assistant_text = "\n".join(text_parts)
            elif isinstance(content, str):
                assistant_text = content

            yield {
                "turn_index": turn_index,
                "type": "assistant",
                "timestamp": timestamp,
                "assistant_text": assistant_text,
                "user_text": "",
                "tool_result_texts": [],
                "tool_uses": tool_uses,
                "is_error": False,
            }
            turn_index += 1

        elif obj_type == "user":
            message = obj.get("message", {})
            content = message.get("content", [])

            user_text_parts = []
            tool_result_texts = []
            has_error = False

            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type", "")
                    if btype == "tool_result":
                        tr_content = _extract_text(block.get("content", ""))
                        tool_result_texts.append(tr_content)
                        if block.get("is_error"):
                            has_error = True
                    elif btype == "text":
                        user_text_parts.append(block.get("text", ""))
            elif isinstance(content, str):
                user_text_parts.append(content)

            yield {
                "turn_index": turn_index,
                "type": "user",
                "timestamp": timestamp,
                "assistant_text": "",
                "user_text": "\n".join(user_text_parts),
                "tool_result_texts": tool_result_texts,
                "tool_uses": [],
                "is_error": has_error,
            }
            turn_index += 1


# ---------------------------------------------------------------------------
# Core miner
# ---------------------------------------------------------------------------

def mine_file(path: pathlib.Path, session_id: str, project: str, limit: int, emitted: list[int]) -> None:
    """
    Mine one transcript file and write friction-event JSON lines to stdout.
    `emitted` is a 1-element list used as a mutable counter shared across calls.
    """
    retry_tracker = taxonomy.RetryTracker(window=3)

    # Track the most recent tool_uses from assistant turns for retry detection.
    last_assistant_tool_uses: list[str] = []

    for turn in _parse_turns(path):
        if limit > 0 and emitted[0] >= limit:
            return

        turn_index = turn["turn_index"]
        timestamp = turn["timestamp"] or ""

        events = []

        if turn["type"] == "assistant":
            matches = taxonomy.match_sources(
                assistant_text=turn["assistant_text"],
            )
            for m in matches:
                events.append(m)
            last_assistant_tool_uses = turn["tool_uses"]

        elif turn["type"] == "user":
            # Aggregate all tool_result text for detection
            combined_tool_result = "\n".join(turn["tool_result_texts"])

            matches = taxonomy.match_sources(
                user_text=turn["user_text"],
                tool_result_text=combined_tool_result,
            )
            for m in matches:
                events.append(m)

            # Retry detection: for each tool that had an error in the previous
            # user turn, check if any of the last assistant's tools match.
            if turn["is_error"]:
                for tool_name in last_assistant_tool_uses:
                    retry_tracker.observe(tool_name, is_error=True, turn_index=turn_index)
            else:
                for tool_name in last_assistant_tool_uses:
                    evidence = retry_tracker.observe(tool_name, is_error=False, turn_index=turn_index)
                    if evidence:
                        events.append({
                            "category": "retry",
                            "source": "tool_result_text",
                            "evidence": evidence,
                        })

        for event in events:
            if limit > 0 and emitted[0] >= limit:
                return

            raw_evidence = event["evidence"][:200]
            clean_evidence = redact.scrub(raw_evidence)
            fp = _fingerprint(clean_evidence)

            record = {
                "session_id": session_id,
                "project": project,
                "transcript_path": str(path),
                "turn_index": turn_index,
                "category": event["category"],
                "evidence_quote": clean_evidence,
                "fingerprint": fp,
                "occurred_at": timestamp,
            }
            sys.stdout.write(json.dumps(record, ensure_ascii=False) + "\n")
            emitted[0] += 1


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def _session_id_from_path(path: pathlib.Path) -> str:
    """Extract session UUID from filename (stem of the .jsonl file)."""
    return path.stem


def _project_from_path(path: pathlib.Path) -> str:
    """Extract project name from the parent directory of the transcript."""
    return path.parent.name


def _collect_files(args) -> list[pathlib.Path]:
    """Return sorted list of transcript paths to process, respecting --since."""
    since: datetime = args.since_dt

    if args.all:
        pattern = str(_PROJECTS_ROOT / "*" / "*.jsonl")
        raw = glob.glob(pattern)
    else:
        raw = args.transcripts or []

    paths = []
    for p in raw:
        fp = pathlib.Path(p)
        if not fp.is_file():
            continue
        # Filter by mtime using --since
        mtime = datetime.fromtimestamp(fp.stat().st_mtime, tz=timezone.utc)
        if mtime >= since:
            paths.append(fp)

    # Deterministic ordering: sort by path string.
    paths.sort(key=lambda p: str(p))
    return paths


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Mine Claude Code transcripts for friction events.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process all transcripts under ~/.claude/projects/",
    )
    parser.add_argument(
        "--since",
        metavar="ISO8601",
        default=None,
        help="Only process files modified after this date (default: 30 days ago)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        metavar="N",
        help="Stop after emitting N events (0 = unlimited)",
    )
    parser.add_argument(
        "transcripts",
        nargs="*",
        help="Transcript JSONL paths to process (alternative to --all)",
    )
    args = parser.parse_args(argv)

    # Resolve --since to a datetime
    if args.since:
        try:
            # Accept ISO8601 with or without time component
            s = args.since
            if "T" not in s and " " not in s:
                s = s + "T00:00:00"
            # Try with timezone offset
            for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
                try:
                    dt = datetime.strptime(args.since if "T" in args.since else s, fmt)
                    break
                except ValueError:
                    continue
            else:
                # Fallback: parse just the date
                dt = datetime.strptime(args.since[:10], "%Y-%m-%d")
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            args.since_dt = dt
        except Exception as e:
            parser.error(f"Invalid --since value {args.since!r}: {e}")
    else:
        args.since_dt = datetime.now(tz=timezone.utc) - timedelta(days=30)

    if not args.all and not args.transcripts:
        parser.print_help()
        sys.exit(0)

    return args


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    args = _parse_args(argv)
    files = _collect_files(args)

    emitted = [0]  # mutable counter

    for path in files:
        if args.limit > 0 and emitted[0] >= args.limit:
            break
        session_id = _session_id_from_path(path)
        project = _project_from_path(path)
        mine_file(path, session_id, project, args.limit, emitted)

    return 0


if __name__ == "__main__":
    sys.exit(main())

"""
propose-edits.py — Friction-cluster proposer for the skill-evolve pipeline.

Reads friction events (JSONL), clusters them, and writes a review directory
containing proposal.md, diff.patch, friction-events.jsonl, regression tests,
and summary.txt.

Usage:
    python3 propose-edits.py --out <review-dir> [--input <path>]
    python3 propose-edits.py --selftest

No pip installs. No LLM calls. Deterministic output.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Sprint 1 imports
# ---------------------------------------------------------------------------
_SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(_SCRIPT_DIR))

from redact import scrub  # noqa: E402
from cluster import Cluster, cluster_events  # noqa: E402

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Allowed out-dir prefix (after expanding ~ / $HOME).
_ALLOWED_PREFIX = "/root/.claude/docs/skill-evolution-proposals/"
# Fallback for non-root environments.
_ALLOWED_PREFIX_HOME = str(Path.home() / ".claude" / "docs" / "skill-evolution-proposals") + "/"

# Template path
_TEMPLATE = _SCRIPT_DIR / "regression-template.sh"

# Category → target file heuristic.
_CATEGORY_TARGETS: dict[str, str] = {
    "env-incompat": "/root/.claude/rules/environment.md",
    "retry": "/root/.claude/rules/quality.md",
    "refusal": "/root/.claude/CLAUDE.md",
    "workaround": "/root/.claude/CLAUDE.md",
    "missing-method": "/root/.claude/CLAUDE.md",
}


# ---------------------------------------------------------------------------
# Out-dir guard
# ---------------------------------------------------------------------------

def _resolve_out(raw: str) -> Path:
    """
    Expand ~ and resolve to an absolute path.
    Raises SystemExit (with stderr message) if the path is not under the
    allowed prefix.
    """
    expanded = os.path.expanduser(raw)
    resolved = str(Path(expanded).resolve())

    allowed = [_ALLOWED_PREFIX, _ALLOWED_PREFIX_HOME]
    ok = any(resolved.startswith(a) or resolved + "/" == a for a in allowed)

    # Also accept exact match (the proposals root itself, though unusual).
    if not ok:
        # Normalise trailing slash for comparison.
        norm = resolved.rstrip("/") + "/"
        ok = any(norm.startswith(a) for a in allowed)

    if not ok:
        msg = (
            f"refusing --out {raw}: must be under "
            f".claude/docs/skill-evolution-proposals/"
        )
        print(msg, file=sys.stderr)
        sys.exit(2)

    return Path(resolved)


# ---------------------------------------------------------------------------
# Target-file heuristic
# ---------------------------------------------------------------------------

def _target_file(cluster: Cluster) -> str:
    """
    Map a cluster's category to the skill/rules file most likely to contain
    the fix. Falls back to CLAUDE.md.
    """
    return _CATEGORY_TARGETS.get(cluster.category, "/root/.claude/CLAUDE.md")


# ---------------------------------------------------------------------------
# Regression test generation
# ---------------------------------------------------------------------------

def _load_template() -> str:
    if _TEMPLATE.exists():
        return _TEMPLATE.read_text()
    # Minimal fallback if the template is somehow missing.
    return (
        "#!/usr/bin/env bash\nset -uo pipefail\n"
        "# __CLUSTER_SLUG__ / __CATEGORY__\n"
        "# GATE: __GATE_COMMAND__\n"
        "echo 'stub test for __EVIDENCE_FINGERPRINT__'\nexit 0\n"
    )


def _generate_regression_test(cluster: Cluster, out_dir: Path) -> Path:
    """
    Write a regression test for `cluster` into `out_dir/regression-tests/`.
    Returns the path to the generated script.
    """
    tests_dir = out_dir / "regression-tests"
    tests_dir.mkdir(parents=True, exist_ok=True)

    template = _load_template()

    # Representative fingerprint from the first event.
    rep_fp = cluster.events[0].get("fingerprint", "") if cluster.events else ""

    # Gate command: STUB — reviewer MUST replace before wiring into run-all.sh.
    # Kept as a single line so it survives the template's double-quoted
    # GATE_COMMAND="..." variable assignment without breaking shell syntax.
    target = _target_file(cluster)
    redacted_quote = scrub(cluster.representative_quote).replace('"', '\\"')
    # Format: comments (via :;) then echo STUB message then exit 2.
    # Using colon-semicolons ": # comment;" keeps comments eval-safe.
    gate_cmd = (
        f": STUB-GATE-REVIEWER-MUST-REPLACE-BEFORE-WIRING;"
        f" : cluster={cluster.slug};"
        f" : category={cluster.category};"
        f" : target={target};"
        f" : evidence-redacted={redacted_quote!r};"
        f" : replace-this-exit-with-a-check-that-fails-under-buggy-state-and-passes-after-fix;"
        f' echo \\"STUB: gate not yet implemented for cluster {cluster.slug}\\" >&2;'
        f" exit 2"
    )

    filled = (
        template
        .replace("__CLUSTER_SLUG__", cluster.slug)
        .replace("__CATEGORY__", cluster.category)
        .replace("__EVIDENCE_FINGERPRINT__", rep_fp)
        .replace("__GATE_COMMAND__", gate_cmd)
    )

    test_path = tests_dir / f"test-skill-evolve-{cluster.slug}.sh"
    test_path.write_text(filled)
    test_path.chmod(test_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return test_path


# ---------------------------------------------------------------------------
# Patch generation
# ---------------------------------------------------------------------------

def _build_patch_hunk(cluster: Cluster) -> str:
    """
    Build a markdown patch hunk (not a real git diff) showing the proposed
    before/after change for manual review.
    """
    target = _target_file(cluster)
    quote = scrub(cluster.representative_quote)
    category = cluster.category

    # Draft a human-readable before/after comment.
    before_block = (
        f"# [existing text in {target} — locate the section describing {category}]"
    )
    after_block = (
        f"# [amended text — add guidance to avoid {category} friction]\n"
        f"# Evidence: {quote}"
    )
    hunk = (
        f"--- a{target}\n"
        f"+++ b{target}\n"
        f"@@ -1,1 +1,2 @@\n"
        f"-{before_block}\n"
        f"+{after_block}\n"
    )
    return hunk


def _try_generate_diff_patch(clusters: list[Cluster], out_dir: Path) -> tuple[str, dict[str, bool]]:
    """
    Attempt to produce a diff.patch from the cluster proposals.
    Returns (patch_content, {slug: patch_ok}) where patch_ok=False means
    the cluster's patch failed git-apply --check and needs the FAILED marker.

    Always writes out_dir/diff.patch (may be empty if git is unavailable).
    """
    patch_parts: list[str] = []
    patch_ok: dict[str, bool] = {}

    git_available = shutil.which("git") is not None

    for cluster in clusters:
        hunk = _build_patch_hunk(cluster)
        patch_parts.append(hunk)

        if not git_available:
            patch_ok[cluster.slug] = False
            continue

        # Try git apply --check in a temp dir against /root/.claude.
        with tempfile.NamedTemporaryFile(suffix=".patch", mode="w", delete=False) as tf:
            tf.write(hunk)
            tmp_patch = tf.name
        try:
            result = subprocess.run(
                ["git", "apply", "--check", tmp_patch],
                cwd="/root/.claude",
                capture_output=True,
                timeout=10,
            )
            patch_ok[cluster.slug] = result.returncode == 0
        except Exception:
            patch_ok[cluster.slug] = False
        finally:
            os.unlink(tmp_patch)

    patch_content = "\n".join(patch_parts)
    patch_file = out_dir / "diff.patch"
    patch_file.write_text(patch_content)
    return patch_content, patch_ok


# ---------------------------------------------------------------------------
# proposal.md writer
# ---------------------------------------------------------------------------

def _write_proposal(
    clusters: list[Cluster],
    patch_ok: dict[str, bool],
    out_dir: Path,
    test_paths: dict[str, Path],
) -> None:
    lines: list[str] = [
        "# Skill-Evolve Proposal",
        "",
        f"Review directory: `{out_dir}`",
        "",
    ]

    if not clusters:
        lines += [
            "no clusters — no friction events met the minimum threshold (≥ 2 events).",
            "",
        ]
    else:
        for cluster in clusters:
            quote = scrub(cluster.representative_quote)
            sessions = sorted({ev.get("session_id", "?") for ev in cluster.events})
            session_list = ", ".join(sessions)
            patch_status = patch_ok.get(cluster.slug, False)
            test_path = test_paths.get(cluster.slug)
            test_rel = str(test_path.relative_to(out_dir)) if test_path else "N/A"

            lines += [
                f"## Cluster: {cluster.slug}",
                "",
                f"**Category:** `{cluster.category}`",
                f"**Confidence:** {cluster.confidence}",
                f"**Evidence:** {len(cluster.events)} events from {session_list}",
                "",
                "**Representative quote:**",
                "```",
                quote,
                "```",
                "",
                f"**Proposed edit target:** `{_target_file(cluster)}`",
                "",
                "**Proposed change:**",
            ]

            if patch_status:
                lines += [
                    f"See `diff.patch` — hunk for cluster `{cluster.slug}`.",
                ]
            else:
                target = _target_file(cluster)
                before = (
                    f"# [existing text in {target} — "
                    f"locate the section describing {cluster.category}]"
                )
                after = (
                    f"# [amended text — add guidance to avoid "
                    f"{cluster.category} friction]\n"
                    f"# Evidence: {quote}"
                )
                lines += [
                    "[PATCH GENERATION FAILED] — apply the change manually:",
                    "",
                    "**Before:**",
                    "```",
                    before,
                    "```",
                    "",
                    "**After:**",
                    "```",
                    after,
                    "```",
                ]

            lines += [
                "",
                f"**Regression test:** `{test_rel}`",
                "",
            ]

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "proposal.md").write_text("\n".join(lines))


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run(input_path: str | None, out_dir: Path) -> None:
    # Read events.
    if input_path is None or input_path == "-":
        raw = sys.stdin.read()
    else:
        raw = Path(input_path).read_text()

    events: list[dict] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass  # Skip malformed lines.

    # Cluster.
    clusters = cluster_events(events)

    # Prepare out-dir.
    out_dir.mkdir(parents=True, exist_ok=True)

    # Copy friction events through (re-applying redaction to evidence_quote).
    redacted_events: list[dict] = []
    for ev in events:
        ev2 = dict(ev)
        if "evidence_quote" in ev2:
            ev2["evidence_quote"] = scrub(ev2["evidence_quote"])
        redacted_events.append(ev2)

    (out_dir / "friction-events.jsonl").write_text(
        "\n".join(json.dumps(e) for e in redacted_events) + ("\n" if redacted_events else "")
    )

    # Diff patch (always created, may be empty).
    _, patch_ok = _try_generate_diff_patch(clusters, out_dir)

    # Regression tests.
    test_paths: dict[str, Path] = {}
    for cluster in clusters:
        tp = _generate_regression_test(cluster, out_dir)
        test_paths[cluster.slug] = tp

    # Proposal.
    _write_proposal(clusters, patch_ok, out_dir, test_paths)

    # Summary.
    n = len(clusters)
    summary = f"Proposed {n} clusters; review at {out_dir}/proposal.md\n"
    (out_dir / "summary.txt").write_text(summary)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _selftest() -> None:
    import time
    import random
    import string

    pid = os.getpid()
    rand4 = "".join(random.choices(string.ascii_lowercase, k=4))
    run_id = f"{int(time.time())}-{rand4}"
    tmp_out = Path(
        f"/root/.claude/docs/skill-evolution-proposals/_selftest_{pid}_{rand4}/"
    )

    # Build a 4-event fixture forming 2 clusters.
    # Cluster A: category=retry, 2 events, same fingerprint
    # Cluster B: category=env-incompat, 2 events, same fingerprint
    token_fixture = "sk-" + "FAKE12345678901234" + "567890abcd"  # will be redacted

    events = [
        {
            "session_id": "sess-a1", "project": "proj", "transcript_path": "/t1",
            "turn_index": 1, "category": "retry",
            "evidence_quote": f"Retried Bash after error ({token_fixture})",
            "fingerprint": "retry-bash-after-error", "occurred_at": "2026-01-01T00:00:00Z",
        },
        {
            "session_id": "sess-a2", "project": "proj", "transcript_path": "/t2",
            "turn_index": 2, "category": "retry",
            "evidence_quote": "Retried Bash after error",
            "fingerprint": "retry-bash-after-error", "occurred_at": "2026-01-01T00:01:00Z",
        },
        {
            "session_id": "sess-b1", "project": "proj", "transcript_path": "/t3",
            "turn_index": 3, "category": "env-incompat",
            "evidence_quote": "command not found: brew",
            "fingerprint": "command-not-found-brew", "occurred_at": "2026-01-01T00:02:00Z",
        },
        {
            "session_id": "sess-b2", "project": "proj", "transcript_path": "/t4",
            "turn_index": 4, "category": "env-incompat",
            "evidence_quote": "command not found: brew",
            "fingerprint": "command-not-found-brew", "occurred_at": "2026-01-01T00:03:00Z",
        },
    ]

    # Write fixture JSONL to a tmp file.
    with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as f:
        for ev in events:
            f.write(json.dumps(ev) + "\n")
        fixture_path = f.name

    try:
        run(fixture_path, tmp_out)

        # A1: proposal.md exists with exactly 2 ## Cluster: sections.
        proposal = (tmp_out / "proposal.md").read_text()
        cluster_sections = [l for l in proposal.splitlines() if l.startswith("## Cluster:")]
        assert len(cluster_sections) == 2, (
            f"selftest A1 failed: expected 2 ## Cluster: sections, got {len(cluster_sections)}"
        )

        # A2: diff.patch exists (may be empty).
        assert (tmp_out / "diff.patch").exists(), "selftest A2 failed: diff.patch missing"

        # A3: friction-events.jsonl exists.
        assert (tmp_out / "friction-events.jsonl").exists(), (
            "selftest A3 failed: friction-events.jsonl missing"
        )

        # A4: regression-tests/ has exactly 2 executable .sh files.
        tests_dir = tmp_out / "regression-tests"
        assert tests_dir.exists(), "selftest A4 failed: regression-tests/ missing"
        sh_files = list(tests_dir.glob("test-skill-evolve-*.sh"))
        assert len(sh_files) == 2, (
            f"selftest A4 failed: expected 2 .sh files, got {len(sh_files)}"
        )
        for sh in sh_files:
            assert os.access(sh, os.X_OK), f"selftest A4 failed: {sh} not executable"

        # A5: summary.txt is exactly one line.
        summary_text = (tmp_out / "summary.txt").read_text()
        lines = [l for l in summary_text.splitlines() if l.strip()]
        assert len(lines) == 1, (
            f"selftest A5 failed: summary.txt should be 1 line, got {len(lines)}"
        )

        # A6: token is redacted in proposal.md (AC7 check within selftest).
        assert token_fixture not in proposal, (
            "selftest A6 failed: raw token leaked into proposal.md"
        )

        print(f"selftest: all 6 assertions passed. (out: {tmp_out})")

    finally:
        os.unlink(fixture_path)
        # Cleanup.
        shutil.rmtree(tmp_out, ignore_errors=True)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Propose edits from clustered friction events."
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="Run inline self-test and exit.",
    )
    parser.add_argument(
        "--input",
        metavar="PATH",
        default=None,
        help="JSONL friction events file (default: stdin).",
    )
    parser.add_argument(
        "--out",
        metavar="DIR",
        default=None,
        help="Review directory (REQUIRED unless --selftest).",
    )
    args = parser.parse_args()

    if args.selftest:
        _selftest()
        return

    if args.out is None:
        print("error: --out DIR is required", file=sys.stderr)
        parser.print_usage(sys.stderr)
        sys.exit(1)

    out_dir = _resolve_out(args.out)
    run(args.input, out_dir)


if __name__ == "__main__":
    main()

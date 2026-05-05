"""
cluster.py — Friction-event clustering for the skill-evolve pipeline.

Groups friction events by (category, fingerprint). Merges buckets whose
representative fingerprints differ by <= 10% Levenshtein distance (relative
to the length of the longer string). Returns only clusters with >= 2 events.

No pip installs. Levenshtein implemented with stdlib-only DP.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Levenshtein (stdlib only, small DP — fingerprints are short strings)
# ---------------------------------------------------------------------------

def _levenshtein(a: str, b: str) -> int:
    """Return the Levenshtein edit distance between strings a and b."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)

    # Keep only two rows to save memory.
    prev = list(range(len(b) + 1))
    curr = [0] * (len(b) + 1)

    for i, ca in enumerate(a, start=1):
        curr[0] = i
        for j, cb in enumerate(b, start=1):
            if ca == cb:
                curr[j] = prev[j - 1]
            else:
                curr[j] = 1 + min(prev[j - 1], prev[j], curr[j - 1])
        prev, curr = curr, prev

    return prev[len(b)]


def _relative_distance(a: str, b: str) -> float:
    """
    Levenshtein distance normalised by the length of the longer string.
    Returns a value in [0.0, 1.0]. 0.0 means identical.
    """
    if not a and not b:
        return 0.0
    max_len = max(len(a), len(b))
    return _levenshtein(a, b) / max_len


# ---------------------------------------------------------------------------
# Cluster dataclass
# ---------------------------------------------------------------------------

@dataclass
class Cluster:
    category: str
    representative_quote: str
    events: list[dict] = field(default_factory=list)
    slug: str = ""
    confidence: str = "high"  # "high" | "medium" | "low"

    def __post_init__(self) -> None:
        if not self.slug:
            self.slug = _make_slug(self.representative_quote)


def _make_slug(text: str, max_len: int = 40) -> str:
    """
    Derive a kebab-case slug from text, truncated to max_len chars.
    Uses only the first sentence/phrase to keep slugs readable.
    """
    # Lower-case, keep alphanumerics and spaces
    cleaned = re.sub(r"[^a-z0-9\s]", "", text.lower())
    # Collapse whitespace, join with hyphens
    words = cleaned.split()
    slug = "-".join(words)
    if len(slug) > max_len:
        slug = slug[:max_len].rstrip("-")
    return slug or "unknown"


# ---------------------------------------------------------------------------
# Core clustering logic
# ---------------------------------------------------------------------------

def cluster_events(events: list[dict]) -> list[Cluster]:
    """
    Bucket friction events by (category, fingerprint).
    Merge buckets whose representative fingerprints differ by <= 10%
    Levenshtein distance. Return only clusters with >= 2 events.

    Cluster ordering: by category then representative fingerprint (lex sort).

    Confidence rules:
      - "high"   if all events in the cluster have identical fingerprints
                 (no near-duplicate merging occurred).
      - "medium" if any near-duplicate merging happened (fingerprints differ
                 but were close enough to merge).
      - "low"    if cluster size is exactly 2 with no merging (fingerprints
                 were identical but there were only 2 events).
    """
    if not events:
        return []

    # Step 1: bucket by (category, fingerprint) — exact grouping first.
    buckets: dict[tuple[str, str], list[dict]] = {}
    for ev in events:
        cat = ev.get("category", "")
        fp = ev.get("fingerprint", "")
        key = (cat, fp)
        buckets.setdefault(key, []).append(ev)

    # Step 2: within each category, merge buckets with close fingerprints.
    # Build a list of (category, representative_fingerprint, events, merged)
    # then union-find merge.
    cat_buckets: dict[str, list[tuple[str, list[dict]]]] = {}
    for (cat, fp), evs in buckets.items():
        cat_buckets.setdefault(cat, []).append((fp, evs))

    clusters: list[Cluster] = []

    for cat, fp_groups in cat_buckets.items():
        # Sort for determinism.
        fp_groups.sort(key=lambda x: x[0])

        # Simple union-find (small N — O(n^2) fine for fingerprints).
        n = len(fp_groups)
        parent = list(range(n))

        def find(x: int) -> int:
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        def union(x: int, y: int) -> None:
            px, py = find(x), find(y)
            if px != py:
                parent[py] = px

        # Track which pairs were merged (near-duplicate).
        near_merged_groups: set[int] = set()

        for i in range(n):
            for j in range(i + 1, n):
                fp_i = fp_groups[i][0]
                fp_j = fp_groups[j][0]
                if fp_i == fp_j:
                    # Exact — merge, not near-duplicate.
                    union(i, j)
                elif _relative_distance(fp_i, fp_j) <= 0.10:
                    union(i, j)
                    near_merged_groups.add(find(i))
                    near_merged_groups.add(find(j))

        # Aggregate into final groups.
        group_map: dict[int, list[tuple[str, list[dict]]]] = {}
        for i in range(n):
            root = find(i)
            group_map.setdefault(root, []).append(fp_groups[i])

        for root, members in group_map.items():
            all_events: list[dict] = []
            all_fps: list[str] = []
            had_near_merge = root in near_merged_groups

            for fp, evs in members:
                all_events.extend(evs)
                all_fps.extend([fp] * len(evs))

            # Drop single-event clusters per invariant.
            if len(all_events) < 2:
                continue

            # Pick representative quote: first event's evidence_quote.
            rep_quote = all_events[0].get("evidence_quote", "")
            rep_fp = members[0][0]  # lex-first fingerprint (groups sorted above)

            # Confidence.
            unique_fps = set(ev.get("fingerprint", "") for ev in all_events)
            if had_near_merge:
                confidence = "medium"
            elif len(all_events) == 2 and len(unique_fps) == 1:
                confidence = "low"
            else:
                confidence = "high"

            clusters.append(Cluster(
                category=cat,
                representative_quote=rep_quote,
                events=all_events,
                slug=_make_slug(rep_fp if rep_fp else rep_quote),
                confidence=confidence,
            ))

    # Deterministic ordering: category, then representative slug.
    clusters.sort(key=lambda c: (c.category, c.slug))
    return clusters


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _selftest() -> None:
    import sys

    # T1: empty input → no clusters.
    result = cluster_events([])
    assert result == [], f"T1 failed: {result}"

    # T2: single event → no clusters (< 2 events).
    ev1 = {
        "session_id": "s1", "project": "p", "transcript_path": "/t",
        "turn_index": 1, "category": "retry", "evidence_quote": "retried Bash",
        "fingerprint": "retry-bash", "occurred_at": "2026-01-01T00:00:00Z",
    }
    result = cluster_events([ev1])
    assert result == [], f"T2 failed: {result}"

    # T3: two events with identical fingerprint → 1 cluster, confidence "low".
    ev2 = dict(ev1, session_id="s2", turn_index=2)
    result = cluster_events([ev1, ev2])
    assert len(result) == 1, f"T3 failed count: {len(result)}"
    assert result[0].confidence == "low", f"T3 bad confidence: {result[0].confidence}"

    # T4: three events with identical fingerprint → confidence "high" (>2, no merge).
    ev3 = dict(ev1, session_id="s3", turn_index=3)
    result = cluster_events([ev1, ev2, ev3])
    assert len(result) == 1, f"T4 failed count: {len(result)}"
    assert result[0].confidence == "high", f"T4 bad confidence: {result[0].confidence}"

    # T5: two events with near-duplicate fingerprints (within 10%) → merged, confidence "medium".
    ev_a = dict(ev1, fingerprint="retry-bash-tool")
    ev_b = dict(ev2, fingerprint="retry-bash-tol")  # 1 edit diff in 15-char = 6.7% < 10%
    result = cluster_events([ev_a, ev_b])
    assert len(result) == 1, f"T5 failed count: {len(result)}"
    assert result[0].confidence == "medium", f"T5 bad confidence: {result[0].confidence}"

    # T6: events from different categories do NOT merge.
    ev_c = dict(ev1, category="workaround", fingerprint="retry-bash-tool")
    ev_d = dict(ev2, category="refusal", fingerprint="retry-bash-tool")
    result = cluster_events([ev_c, ev_d])
    assert result == [], f"T6 failed — different categories should not cluster together"

    # T7: two events from same category same fingerprint → cluster created.
    ev_e = dict(ev_c, session_id="s1")
    ev_f = dict(ev_c, session_id="s2", turn_index=5)
    result = cluster_events([ev_e, ev_f])
    assert len(result) == 1, f"T7 failed count: {len(result)}"

    # T8: slug is kebab-case, max 40 chars.
    for c in result:
        assert re.match(r"^[a-z0-9][a-z0-9\-]*$", c.slug), f"T8 bad slug: {c.slug}"
        assert len(c.slug) <= 40, f"T8 slug too long: {c.slug}"

    # T9: Levenshtein correctness.
    assert _levenshtein("", "") == 0
    assert _levenshtein("abc", "") == 3
    assert _levenshtein("", "abc") == 3
    assert _levenshtein("abc", "abc") == 0
    assert _levenshtein("kitten", "sitting") == 3

    print("cluster selftest: all 9 assertions passed.")


if __name__ == "__main__":
    import sys
    if "--selftest" in sys.argv:
        _selftest()
    else:
        print("Usage: python3 cluster.py --selftest")

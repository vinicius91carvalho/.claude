"""
taxonomy.py — Friction event taxonomy for the skill-evolve miner.

Defines the closed vocabulary of friction categories and per-category
detection rules. All classification is deterministic regex/heuristic;
no LLM calls.
"""

import re
import sys

# Closed vocabulary — invariant: exactly these five strings.
CATEGORIES = frozenset({
    "workaround",
    "retry",
    "refusal",
    "env-incompat",
    "missing-method",
})

# ---------------------------------------------------------------------------
# Detection rules
#
# Each entry is a dict:
#   category:  one of CATEGORIES
#   source:    which message field to search — "assistant_text", "user_text",
#              or "tool_result_text"
#   pattern:   compiled regex; re.IGNORECASE already applied at build time
#   template:  f-string template for the evidence_quote; use {match} for the
#              matched span (truncated to 200 chars by the miner).
# ---------------------------------------------------------------------------

_RAW_RULES = [
    # ---- workaround --------------------------------------------------------
    {
        "category": "workaround",
        "source": "assistant_text",
        "pattern": r"let me try a different approach",
        "template": "{match}",
    },
    {
        "category": "workaround",
        "source": "assistant_text",
        "pattern": r"switching to\b",
        "template": "{match}",
    },
    {
        "category": "workaround",
        "source": "assistant_text",
        "pattern": r"instead[,\s]+(?:i['']ll|i will|let me) use\b",
        "template": "{match}",
    },
    {
        "category": "workaround",
        "source": "assistant_text",
        # Fallback language after a tool error in the same turn
        "pattern": r"(?:fallback|fall back|alternative approach|workaround)",
        "template": "{match}",
    },
    # ---- refusal -----------------------------------------------------------
    {
        "category": "refusal",
        "source": "tool_result_text",
        "pattern": r"(?:i cannot|i refuse|i'm unable to|i am unable to)\b",
        "template": "{match}",
    },
    {
        "category": "refusal",
        "source": "assistant_text",
        "pattern": r"(?:i cannot|i refuse|i'm unable to|i am unable to)\b",
        "template": "{match}",
    },
    {
        "category": "refusal",
        "source": "tool_result_text",
        # Hook blocks emitting SOFT_BLOCK or HARD_BLOCK
        "pattern": r"(?:SOFT_BLOCK_APPROVAL_NEEDED|HARD_BLOCK)\b",
        "template": "{match}",
    },
    # ---- env-incompat -------------------------------------------------------
    {
        "category": "env-incompat",
        "source": "tool_result_text",
        "pattern": r"command not found",
        "template": "{match}",
    },
    {
        "category": "env-incompat",
        "source": "tool_result_text",
        "pattern": r"permission denied",
        "template": "{match}",
    },
    {
        "category": "env-incompat",
        "source": "tool_result_text",
        "pattern": r"exec format error",
        "template": "{match}",
    },
    {
        "category": "env-incompat",
        "source": "tool_result_text",
        "pattern": r"wrong ELF",
        "template": "{match}",
    },
    {
        "category": "env-incompat",
        "source": "tool_result_text",
        "pattern": r"not portable",
        "template": "{match}",
    },
    {
        "category": "env-incompat",
        "source": "tool_result_text",
        # proot-distro specific strings
        "pattern": r"PRoot-Distro|proot",
        "template": "{match}",
    },
    # ---- missing-method ----------------------------------------------------
    {
        "category": "missing-method",
        "source": "tool_result_text",
        "pattern": r"AttributeError:[^\n]{0,120}has no attribute",
        "template": "{match}",
    },
    {
        "category": "missing-method",
        "source": "tool_result_text",
        "pattern": r"is not a function",
        "template": "{match}",
    },
    {
        "category": "missing-method",
        "source": "tool_result_text",
        "pattern": r"method does not exist",
        "template": "{match}",
    },
    {
        "category": "missing-method",
        "source": "tool_result_text",
        "pattern": r"unknown command",
        "template": "{match}",
    },
]

# Compile patterns once at import time.
RULES = []
for _r in _RAW_RULES:
    RULES.append({
        "category": _r["category"],
        "source": _r["source"],
        "pattern": re.compile(_r["pattern"], re.IGNORECASE),
        "template": _r["template"],
    })


def match_text(text: str) -> list[dict]:
    """
    Run all rules against a single text blob, returning a list of
    {'category': str, 'evidence': str} dicts for each match.
    """
    results = []
    for rule in RULES:
        m = rule["pattern"].search(text)
        if m:
            span = text[max(0, m.start() - 40): m.end() + 40].strip()
            evidence = span[:200]
            results.append({"category": rule["category"], "evidence": evidence})
    return results


def match_sources(
    assistant_text: str = "",
    user_text: str = "",
    tool_result_text: str = "",
) -> list[dict]:
    """
    Run all rules against the appropriate source field.
    Returns list of {'category': str, 'source': str, 'evidence': str}.
    Deduplicates by (category, evidence) within the call.
    """
    source_map = {
        "assistant_text": assistant_text,
        "user_text": user_text,
        "tool_result_text": tool_result_text,
    }
    seen = set()
    results = []
    for rule in RULES:
        text = source_map.get(rule["source"], "")
        if not text:
            continue
        m = rule["pattern"].search(text)
        if m:
            span = text[max(0, m.start() - 40): m.end() + 40].strip()
            evidence = span[:200]
            key = (rule["category"], evidence)
            if key not in seen:
                seen.add(key)
                results.append({
                    "category": rule["category"],
                    "source": rule["source"],
                    "evidence": evidence,
                })
    return results


# ---------------------------------------------------------------------------
# Retry detection: stateful, tracked by the miner across turns.
# The miner calls `RetryTracker.observe(tool_name, is_error, turn_index)`.
# ---------------------------------------------------------------------------

class RetryTracker:
    """
    Detects same tool called again within 3 turns after an error.
    Usage: call `observe()` for each tool_use in turn order.
    Returns friction evidence when a retry is detected.
    """

    def __init__(self, window: int = 3):
        self._window = window
        # Maps tool_name -> list of (turn_index, is_error)
        self._history: dict[str, list[tuple[int, bool]]] = {}

    def observe(self, tool_name: str, is_error: bool, turn_index: int) -> str | None:
        """
        Returns an evidence string if a retry pattern is detected, else None.
        """
        history = self._history.setdefault(tool_name, [])
        # Prune entries outside the window
        history[:] = [(ti, err) for ti, err in history if turn_index - ti <= self._window]

        result = None
        if not is_error:
            # Non-error call: check if there was a previous error call within window
            error_entries = [(ti, err) for ti, err in history if err]
            if error_entries:
                result = (
                    f"Tool '{tool_name}' retried at turn {turn_index} "
                    f"after error at turn {error_entries[-1][0]}"
                )

        history.append((turn_index, is_error))
        return result


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _selftest() -> None:
    # T1: CATEGORIES is exactly the five required strings
    expected = frozenset({"workaround", "retry", "refusal", "env-incompat", "missing-method"})
    assert CATEGORIES == expected, f"CATEGORIES mismatch: {CATEGORIES}"

    # T2: workaround rule fires on known phrase
    results = match_sources(assistant_text="Let me try a different approach here.")
    assert any(r["category"] == "workaround" for r in results), "workaround rule failed"

    # T3: env-incompat fires on 'command not found'
    results = match_sources(tool_result_text="bash: foo: command not found")
    assert any(r["category"] == "env-incompat" for r in results), "env-incompat rule failed"

    # T4: missing-method fires on AttributeError
    results = match_sources(tool_result_text="AttributeError: 'NoneType' has no attribute 'run'")
    assert any(r["category"] == "missing-method" for r in results), "missing-method rule failed"

    # T5: RetryTracker detects retry within 3 turns
    tracker = RetryTracker(window=3)
    tracker.observe("Bash", is_error=True, turn_index=10)
    evidence = tracker.observe("Bash", is_error=False, turn_index=12)
    assert evidence is not None, "RetryTracker failed to detect retry"

    print("taxonomy selftest: all 5 assertions passed.")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        print("Usage: python3 taxonomy.py --selftest")

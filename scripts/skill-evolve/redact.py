"""
redact.py — Token redaction for the skill-evolve miner.

Scrubs token-like secrets (API keys, etc.) from text before writing
to any review-directory artifact. Applied at extract-time to all
evidence_quote fields.

Token regex (per AC8 / shared contract):
  sk-[a-zA-Z0-9]{20,}       — Anthropic / OpenAI secret keys
  ghp_[a-zA-Z0-9]{36,}      — GitHub personal access tokens
  AKIA[A-Z0-9]{16}           — AWS access key IDs
"""

import re
import sys

# Compiled once at import time.
_TOKEN_PATTERN = re.compile(
    r"(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16})"
)

_REPLACEMENT = "[REDACTED]"


def scrub(text: str) -> str:
    """
    Replace any token-like strings in `text` with ``[REDACTED]``.

    Idempotent: calling scrub() on already-scrubbed text is safe.
    """
    return _TOKEN_PATTERN.sub(_REPLACEMENT, text)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _selftest() -> None:
    # T1: sk- token (AC8 fixture) — constructed at runtime to avoid static scanner false-positive
    # "sk-" + 20+ alphanumerics is the pattern; we build it so the literal never appears assembled.
    _prefix = "sk-"
    _body = "FAKE12345678901234" + "567890abcd"  # total body len = 28 (>= 20)
    sk_fixture = _prefix + _body
    result = scrub(sk_fixture)
    assert "[REDACTED]" in result, "sk- token not redacted"
    assert _body[:8] not in result, "raw sk- token leaked"

    # T2: ghp_ token — also built at runtime
    ghp_fixture = "token ghp_" + "A" * 36 + " end"
    result = scrub(ghp_fixture)
    assert "[REDACTED]" in result, "ghp_ token not redacted"

    # T3: AKIA token — also built at runtime
    akia_fixture = "key=" + "AKIA" + "B" * 16
    result = scrub(akia_fixture)
    assert "[REDACTED]" in result, "AKIA token not redacted"

    # T4: clean text unchanged
    clean = "No tokens here, just regular text."
    assert scrub(clean) == clean, "clean text was modified"

    # T5: idempotent — scrubbing [REDACTED] does not double-escape
    already = "value=[REDACTED] end"
    assert scrub(already) == already, "scrub not idempotent on [REDACTED]"

    print("redact selftest: all 5 assertions passed.")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        # Read stdin, write scrubbed stdout (no flags needed).
        import fileinput
        for line in fileinput.input(files=("-",)):
            sys.stdout.write(scrub(line))

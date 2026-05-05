#!/usr/bin/env bash
# active-plan-read.sh [<session_id>]
#
# Prints the pointer JSON for $CLAUDE_SESSION_ID (or the supplied id) to
# stdout. Touches last_seen_at as a side effect — every read is also a
# liveness signal that defers GC by gc-active-plans.sh.
#
# Exit codes:
#   0 — pointer printed (stdout has JSON)
#   1 — pointer not found (stdout empty)

set -euo pipefail

SESSION_ID="${1:-${CLAUDE_SESSION_ID:-}}"
[ -n "$SESSION_ID" ] || { exit 1; }

POINTER="$HOME/.claude/state/active-plan-${SESSION_ID}.json"
[ -f "$POINTER" ] || exit 1

if command -v jq >/dev/null 2>&1; then
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  TMP="$(mktemp "${POINTER}.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  if jq --arg now "$NOW" '.last_seen_at = $now' "$POINTER" > "$TMP" 2>/dev/null; then
    mv -f "$TMP" "$POINTER"
  fi
  trap - EXIT
fi

cat "$POINTER"

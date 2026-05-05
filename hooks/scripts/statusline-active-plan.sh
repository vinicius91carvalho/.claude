#!/usr/bin/env bash
# statusline-active-plan.sh
#
# Prints a compact "📋 <slug-tail> · <done>/<total>" segment for the
# Claude Code statusline, scoped to the current $CLAUDE_SESSION_ID.
# Prints nothing (and exits 0) when the session has no active-plan pointer
# or progress.json is unreadable.
#
# Designed to be cheap: at most one jq read per render.

set -eu

SESSION_ID="${CLAUDE_SESSION_ID:-}"
[ -n "$SESSION_ID" ] || exit 0

POINTER="$HOME/.claude/state/active-plan-${SESSION_ID}.json"
[ -f "$POINTER" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PRD_DIR="$(jq -r '.prd_dir // empty' "$POINTER" 2>/dev/null || true)"
PRD_SLUG="$(jq -r '.prd_slug // empty' "$POINTER" 2>/dev/null || true)"
[ -n "$PRD_DIR" ] || exit 0
[ -d "$PRD_DIR" ] || exit 0

PROGRESS="$PRD_DIR/progress.json"
[ -f "$PROGRESS" ] || exit 0

# Slug-tail: text after the last hyphen-separated dash following the timestamp,
# i.e. for "2026-04-28_1430-foo-bar" → "foo-bar". If the slug has no trailing
# tag, fall back to the whole slug.
SLUG_TAIL="${PRD_SLUG##*_[0-9][0-9][0-9][0-9]-}"
if [ "$SLUG_TAIL" = "$PRD_SLUG" ]; then
  SLUG_TAIL="$PRD_SLUG"
fi

STATS="$(jq -r '
  (.sprints // []) as $s
  | ($s | map(select(.status=="complete")) | length) as $done
  | ($s | length) as $total
  | "\($done)/\($total)"
' "$PROGRESS" 2>/dev/null || true)"

[ -n "$STATS" ] || exit 0

printf '\xf0\x9f\x93\x8b %s \xc2\xb7 %s' "$SLUG_TAIL" "$STATS"

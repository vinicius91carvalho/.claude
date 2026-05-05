#!/usr/bin/env bash
# active-plan-write.sh <prd_dir> [<session_id>]
#
# Atomically writes the active-plan pointer for a session at
# ~/.claude/state/active-plan-<session_id>.json. Pointer schema:
#
#   {
#     "session_id": "...",
#     "prd_dir":    "/abs/path/.../<prd_slug>",
#     "prd_slug":   "<basename of prd_dir>",
#     "repo_root":  "/abs/path/repo",
#     "created_at": "ISO-8601",
#     "last_seen_at": "ISO-8601",
#     "schema_version": 1
#   }
#
# session_id defaults to $CLAUDE_SESSION_ID. Idempotent: if the pointer
# already exists, created_at is preserved and only last_seen_at + prd_*
# are refreshed.

set -euo pipefail

err() { echo "active-plan-write: $*" >&2; exit 1; }

[ $# -ge 1 ] || err "usage: active-plan-write.sh <prd_dir> [<session_id>]"

PRD_DIR="$1"
SESSION_ID="${2:-${CLAUDE_SESSION_ID:-}}"

[ -n "$SESSION_ID" ] || err "session_id is empty (no CLAUDE_SESSION_ID and none passed)"
[ -d "$PRD_DIR" ]    || err "prd_dir does not exist: $PRD_DIR"

PRD_DIR_ABS="$(cd "$PRD_DIR" && pwd)"
PRD_SLUG="$(basename "$PRD_DIR_ABS")"

REPO_ROOT="$(git -C "$PRD_DIR_ABS" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(pwd)"
fi

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
POINTER="$STATE_DIR/active-plan-${SESSION_ID}.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

CREATED_AT="$NOW"
if [ -f "$POINTER" ] && command -v jq >/dev/null 2>&1; then
  prev="$(jq -r '.created_at // empty' "$POINTER" 2>/dev/null || true)"
  [ -n "$prev" ] && CREATED_AT="$prev"
fi

TMP="$(mktemp "${POINTER}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg sid "$SESSION_ID" \
    --arg dir "$PRD_DIR_ABS" \
    --arg slug "$PRD_SLUG" \
    --arg repo "$REPO_ROOT" \
    --arg created "$CREATED_AT" \
    --arg seen "$NOW" \
    '{
       session_id: $sid,
       prd_dir: $dir,
       prd_slug: $slug,
       repo_root: $repo,
       created_at: $created,
       last_seen_at: $seen,
       schema_version: 1
     }' > "$TMP"
else
  cat > "$TMP" <<EOF
{
  "session_id": "$SESSION_ID",
  "prd_dir": "$PRD_DIR_ABS",
  "prd_slug": "$PRD_SLUG",
  "repo_root": "$REPO_ROOT",
  "created_at": "$CREATED_AT",
  "last_seen_at": "$NOW",
  "schema_version": 1
}
EOF
fi

mv -f "$TMP" "$POINTER"
trap - EXIT

echo "$POINTER"

#!/usr/bin/env bash
# migrate-progress-v1-to-v2.sh <progress.json> <session_id> <mode>
#
# Idempotent v1 → v2 schema migration of progress.json.
#
# mode:
#   bind  — set owner_session_id to <session_id> (this session is the original author)
#   adopt — leave owner_session_id empty/preserved; append <session_id> to adopted_by
#
# Adds (when missing): schema_version=2, owner_session_id, owner_created_at,
# adopted_by, prd_slug. Existing fields are preserved.

set -euo pipefail

err() { echo "migrate-progress-v1-to-v2: $*" >&2; exit 1; }

[ $# -eq 3 ] || err "usage: migrate-progress-v1-to-v2.sh <progress.json> <session_id> <bind|adopt>"

PROGRESS="$1"
SESSION_ID="$2"
MODE="$3"

case "$MODE" in bind|adopt) ;; *) err "mode must be bind or adopt" ;; esac

[ -f "$PROGRESS" ] || err "progress.json not found: $PROGRESS"
command -v jq >/dev/null 2>&1 || err "jq required"

PRD_DIR="$(cd "$(dirname "$PROGRESS")" && pwd)"
PRD_SLUG="$(basename "$PRD_DIR")"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

LOCKFILE="$PRD_DIR/.progress.lock"
exec 9>"$LOCKFILE" || err "cannot open lockfile"
flock -x -w 10 9 || err "lock timeout"

current_version="$(jq -r '.schema_version // 0' "$PROGRESS")"
if [ "$current_version" -ge 2 ]; then
  if [ "$MODE" = "adopt" ]; then
    TMP="$(mktemp "${PROGRESS}.XXXXXX")"
    trap 'rm -f "$TMP"' EXIT
    jq --arg sid "$SESSION_ID" --arg now "$NOW" \
       '.adopted_by = ((.adopted_by // []) + [{session_id: $sid, adopted_at: $now, reason: "migrate-adopt"}])' \
       "$PROGRESS" > "$TMP"
    mv -f "$TMP" "$PROGRESS"
    trap - EXIT
  fi
  exit 0
fi

TMP="$(mktemp "${PROGRESS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

if [ "$MODE" = "bind" ]; then
  jq --arg sid "$SESSION_ID" --arg slug "$PRD_SLUG" --arg now "$NOW" \
     '. + {
        schema_version: 2,
        owner_session_id: $sid,
        owner_created_at: (.created // $now),
        adopted_by: (.adopted_by // []),
        prd_slug: (.prd_slug // $slug)
      }' \
     "$PROGRESS" > "$TMP"
else
  jq --arg sid "$SESSION_ID" --arg slug "$PRD_SLUG" --arg now "$NOW" \
     '. + {
        schema_version: 2,
        owner_session_id: (.owner_session_id // ""),
        owner_created_at: (.created // $now),
        adopted_by: ((.adopted_by // []) + [{session_id: $sid, adopted_at: $now, reason: "migrate-adopt"}]),
        prd_slug: (.prd_slug // $slug)
      }' \
     "$PROGRESS" > "$TMP"
fi

mv -f "$TMP" "$PROGRESS"
trap - EXIT

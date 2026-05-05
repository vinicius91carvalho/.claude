#!/usr/bin/env bash
# release-sprint.sh <progress.json> <sprint_id> <session_id> <new_status>
#
# Atomic end-of-sprint write. Refuses if claimed_by_session does not match
# the caller's session_id (defense in depth — a peer cannot accidentally
# complete your sprint).
#
# new_status: complete | blocked | not_started (the latter releases the
# claim without finalizing — useful for /adopt-plan reset).
#
# Exit codes:
#   0 — released
#   1 — claim mismatch (refusing to write)
#   3 — sprint already in the requested terminal state (idempotent no-op)
#   4 — I/O / arg / lock error

set -euo pipefail

err() { echo "release-sprint: $*" >&2; exit 4; }

[ $# -eq 4 ] || err "usage: release-sprint.sh <progress.json> <sprint_id> <session_id> <new_status>"

PROGRESS="$1"
SPRINT_ID="$2"
SESSION_ID="$3"
NEW_STATUS="$4"

case "$NEW_STATUS" in
  complete|blocked|not_started) ;;
  *) err "invalid new_status '$NEW_STATUS'" ;;
esac

[ -f "$PROGRESS" ] || err "progress.json not found: $PROGRESS"
command -v jq >/dev/null 2>&1 || err "jq required"

PRD_DIR="$(dirname "$PROGRESS")"
LOCKFILE="$PRD_DIR/.progress.lock"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

exec 9>"$LOCKFILE" || err "cannot open lockfile"
flock -x -w 10 9 || err "lock timeout"

current_status="$(jq -r --argjson id "$SPRINT_ID" \
  '.sprints[] | select((.id|tostring)==($id|tostring)) | .status // "missing"' \
  "$PROGRESS")"
current_claimer="$(jq -r --argjson id "$SPRINT_ID" \
  '.sprints[] | select((.id|tostring)==($id|tostring)) | .claimed_by_session // ""' \
  "$PROGRESS")"

[ "$current_status" = "missing" ] && err "sprint $SPRINT_ID not found"

if [ "$current_status" = "$NEW_STATUS" ] && [ "$NEW_STATUS" != "not_started" ]; then
  exit 3
fi

if [ -n "$current_claimer" ] && [ "$current_claimer" != "$SESSION_ID" ]; then
  echo "release-sprint: claim mismatch on sprint $SPRINT_ID — held by ${current_claimer:0:8}, caller is ${SESSION_ID:0:8}" >&2
  exit 1
fi

TMP="$(mktemp "${PROGRESS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

if [ "$NEW_STATUS" = "not_started" ]; then
  jq --argjson id "$SPRINT_ID" \
     '(.sprints[] | select((.id|tostring)==($id|tostring))) |=
        (.status = "not_started"
         | del(.claimed_by_session)
         | del(.claimed_at)
         | del(.claim_heartbeat_at))' \
     "$PROGRESS" > "$TMP"
else
  jq --argjson id "$SPRINT_ID" \
     --arg s "$NEW_STATUS" \
     --arg now "$NOW" \
     '(.sprints[] | select((.id|tostring)==($id|tostring))) |=
        (.status = $s
         | .completed_at = $now)' \
     "$PROGRESS" > "$TMP"
fi

mv -f "$TMP" "$PROGRESS"
trap - EXIT

exit 0

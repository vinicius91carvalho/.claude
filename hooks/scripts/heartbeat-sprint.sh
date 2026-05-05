#!/usr/bin/env bash
# heartbeat-sprint.sh <progress.json> <sprint_id> <session_id>
#
# Updates only claim_heartbeat_at on a sprint. Cheap — orchestrator calls
# this after each Step 5 collection so a peer can detect a dead claim.
# Refuses if claimed_by_session mismatches.
#
# Exit codes:
#   0 — heartbeat refreshed (or sprint not in_progress; quiet no-op)
#   1 — claim mismatch
#   4 — I/O / arg / lock error

set -euo pipefail

err() { echo "heartbeat-sprint: $*" >&2; exit 4; }

[ $# -eq 3 ] || err "usage: heartbeat-sprint.sh <progress.json> <sprint_id> <session_id>"

PROGRESS="$1"
SPRINT_ID="$2"
SESSION_ID="$3"

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
[ "$current_status" = "in_progress" ] || exit 0

if [ "$current_claimer" != "$SESSION_ID" ]; then
  echo "heartbeat-sprint: claim mismatch on sprint $SPRINT_ID" >&2
  exit 1
fi

TMP="$(mktemp "${PROGRESS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

jq --argjson id "$SPRINT_ID" \
   --arg now "$NOW" \
   '(.sprints[] | select((.id|tostring)==($id|tostring)) | .claim_heartbeat_at) = $now' \
   "$PROGRESS" > "$TMP"

mv -f "$TMP" "$PROGRESS"
trap - EXIT

exit 0

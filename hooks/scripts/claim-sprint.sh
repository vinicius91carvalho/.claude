#!/usr/bin/env bash
# claim-sprint.sh <progress.json> <sprint_id> <session_id> [--force]
#
# Atomic CAS claim of a sprint by a session, holding flock -x on
# <prd-dir>/.progress.lock for the entire read-modify-write window.
#
# Exit codes:
#   0 — claim succeeded; sprint moved to in_progress with claim fields set
#   1 — already claimed by a different *live* session (peer pointer is fresh)
#   2 — claim is stale (heartbeat older than 30 min OR claimer pointer gone),
#        force-adopt allowed via --force
#   3 — sprint is in terminal state (complete / blocked) — nothing to do
#   4 — I/O / arg / lock error
#
# Stale criteria (any of):
#   • claim_heartbeat_at older than 30 minutes
#   • ~/.claude/state/active-plan-<claimer>.json missing
#
# Idempotent: claiming a sprint already claimed by the SAME session is exit 0.

set -euo pipefail

err() { echo "claim-sprint: $*" >&2; exit 4; }

[ $# -ge 3 ] || err "usage: claim-sprint.sh <progress.json> <sprint_id> <session_id> [--force]"

PROGRESS="$1"
SPRINT_ID="$2"
SESSION_ID="$3"
FORCE="${4:-}"

[ -f "$PROGRESS" ] || err "progress.json not found: $PROGRESS"
command -v jq >/dev/null 2>&1 || err "jq required"

PRD_DIR="$(dirname "$PROGRESS")"
LOCKFILE="$PRD_DIR/.progress.lock"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"
STALE_AFTER_S=1800   # 30 minutes

exec 9>"$LOCKFILE" || err "cannot open lockfile $LOCKFILE"
flock -x -w 10 9 || err "timeout waiting for lock on $LOCKFILE"

read_field() {
  jq -r --argjson id "$SPRINT_ID" "$1" "$PROGRESS"
}

current_status="$(read_field '.sprints[] | select((.id|tostring)==($id|tostring)) | .status // "missing"')"
current_claimer="$(read_field '.sprints[] | select((.id|tostring)==($id|tostring)) | .claimed_by_session // ""')"
current_heartbeat="$(read_field '.sprints[] | select((.id|tostring)==($id|tostring)) | .claim_heartbeat_at // ""')"

if [ "$current_status" = "missing" ]; then
  echo "claim-sprint: sprint $SPRINT_ID not found in $PROGRESS" >&2
  exit 4
fi

case "$current_status" in
  complete|blocked)
    exit 3
    ;;
  in_progress)
    if [ "$current_claimer" = "$SESSION_ID" ]; then
      # idempotent self-claim — refresh heartbeat
      :
    else
      # is the existing claim live or stale?
      claimer_pointer="$HOME/.claude/state/active-plan-${current_claimer}.json"
      hb_epoch=0
      if [ -n "$current_heartbeat" ]; then
        hb_epoch="$(date -u -d "$current_heartbeat" +%s 2>/dev/null || echo 0)"
      fi
      age_s=$(( NOW_EPOCH - hb_epoch ))
      stale=0
      if [ ! -f "$claimer_pointer" ] || [ "$age_s" -gt "$STALE_AFTER_S" ]; then
        stale=1
      fi
      if [ "$stale" -eq 1 ]; then
        if [ "$FORCE" = "--force" ]; then
          : # fall through to overwrite claim
        else
          exit 2
        fi
      else
        exit 1
      fi
    fi
    ;;
  not_started)
    : # fall through to claim
    ;;
  *)
    echo "claim-sprint: unknown status '$current_status' on sprint $SPRINT_ID" >&2
    exit 4
    ;;
esac

TMP="$(mktemp "${PROGRESS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

jq --argjson id "$SPRINT_ID" \
   --arg sid "$SESSION_ID" \
   --arg now "$NOW" \
   '(.sprints[] | select((.id|tostring)==($id|tostring))) |=
      (.status = "in_progress"
       | .claimed_by_session = $sid
       | .claimed_at = (.claimed_at // $now)
       | .claim_heartbeat_at = $now)' \
   "$PROGRESS" > "$TMP"

mv -f "$TMP" "$PROGRESS"
trap - EXIT

exit 0

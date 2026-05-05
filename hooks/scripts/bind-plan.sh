#!/usr/bin/env bash
# bind-plan.sh <progress.json> <session_id>
#
# Atomically binds an unowned v2 plan to <session_id>, holding flock -x on
# <prd-dir>/.progress.lock for the read-modify-write window. Used by
# /plan-build-test Phase 0 when it discovers a v2 progress.json with
# owner_session_id null/empty (the standard /plan -> fresh-session handoff).
#
# Behavior:
#   - owner_session_id is null/empty/missing -> set it to <session_id>,
#     append { session_id, adopted_at, reason } to adopted_by[].
#   - owner_session_id == <session_id> already -> idempotent, exit 0.
#   - owner_session_id is some other session -> refuse, exit 2.
#   - schema_version != 2 -> refuse, exit 3.
#
# Exit codes:
#   0 - bound (or already bound to this session); progress.json is consistent
#   2 - refused: plan is owned by a different session (use /adopt-plan)
#   3 - refused: legacy v1 schema (use migrate-progress-v1-to-v2.sh)
#   4 - I/O / arg / lock error
#
# Does NOT write the active-plan pointer. Caller should run
# active-plan-write.sh after this exits 0.

set -euo pipefail

err() { echo "bind-plan: $*" >&2; exit 4; }

[ $# -ge 2 ] || err "usage: bind-plan.sh <progress.json> <session_id>"

PROGRESS="$1"
SESSION_ID="$2"

[ -f "$PROGRESS" ] || err "progress.json not found: $PROGRESS"
[ -n "$SESSION_ID" ] || err "session_id is empty"
command -v jq >/dev/null 2>&1 || err "jq required"

PRD_DIR="$(dirname "$PROGRESS")"
LOCKFILE="$PRD_DIR/.progress.lock"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

exec 9>"$LOCKFILE" || err "cannot open lockfile $LOCKFILE"
flock -x -w 10 9 || err "timeout waiting for lock on $LOCKFILE"

schema_version="$(jq -r '.schema_version // 0' "$PROGRESS")"
if [ "$schema_version" != "2" ]; then
  echo "bind-plan: progress.json is not v2 (schema_version=$schema_version) — use migrate-progress-v1-to-v2.sh first" >&2
  exit 3
fi

current_owner="$(jq -r '.owner_session_id // ""' "$PROGRESS")"

if [ -n "$current_owner" ] && [ "$current_owner" != "null" ]; then
  if [ "$current_owner" = "$SESSION_ID" ]; then
    echo "bind-plan: already bound to $SESSION_ID (idempotent)" >&2
    exit 0
  fi
  echo "bind-plan: progress.json owned by $current_owner, not unbound — use /adopt-plan to take over" >&2
  exit 2
fi

# Bind: set owner, append adopted_by entry, write atomically.
TMP="$(mktemp "${PROGRESS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

jq \
  --arg sid "$SESSION_ID" \
  --arg now "$NOW" \
  '.owner_session_id = $sid
   | .adopted_by = ((.adopted_by // []) + [{
       session_id: $sid,
       adopted_at: $now,
       reason: "first-executor-bind"
     }])' \
  "$PROGRESS" > "$TMP"

# Sanity check the result before swapping.
jq -e --arg sid "$SESSION_ID" '.owner_session_id == $sid' "$TMP" >/dev/null \
  || err "post-bind sanity check failed (owner_session_id mismatch)"

mv -f "$TMP" "$PROGRESS"
trap - EXIT

echo "bind-plan: bound $PROGRESS to $SESSION_ID at $NOW" >&2
exit 0

#!/usr/bin/env bash
# concurrent-two-session.sh — automated simulator that proves two claude
# sessions can each drive their own plan in the same repo without colliding
# on pointers, sprint claims, branches, worktrees, or the final merge to main.
#
# This is the hands-off equivalent of the manual two-terminal scenario at
# /root/projects/workflow/test-scenarios/concurrent-two-session.md. It calls
# the same helper scripts a real claude session would call, with two synthetic
# CLAUDE_SESSION_IDs.
#
# Run: bash /root/.claude/tests/concurrent-two-session.sh
# Exit: 0 = all passes; non-zero = first failure with a clear ✗ message.

set -euo pipefail

# ──────────────────────────── Setup ────────────────────────────

HOOKS="$HOME/.claude/hooks/scripts"
STATE="$HOME/.claude/state"
TMP="$(mktemp -d -t concurrent-2sess-XXXX)"
REPO="$TMP/repo"
SID_A="aaaa1111-test-session-A"
SID_B="bbbb2222-test-session-B"
PASS=0
FAIL=0
FAILED_TESTS=()

cleanup() {
  rm -f "$STATE/active-plan-${SID_A}.json" "$STATE/active-plan-${SID_B}.json" 2>/dev/null
  rm -f "$STATE/active/agent-test-A.json" "$STATE/active/agent-test-B.json" 2>/dev/null
  if [ -d "$TMP" ]; then
    find "$TMP" -type f -delete 2>/dev/null
    find "$TMP" -depth -type d -empty -delete 2>/dev/null
  fi
}
trap cleanup EXIT

ok()   { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); FAILED_TESTS+=("$*"); }
hdr()  { echo; echo "── $* ──"; }

# Synthetic PRD generator. Mirrors the layout that /plan emits.
make_prd() {
  local slug="$1"
  local prd_dir="$REPO/docs/tasks/feature/sample/$slug"
  mkdir -p "$prd_dir/sprints"
  cat > "$prd_dir/progress.json" <<EOF
{
  "schema_version": 2,
  "owner_session_id": "$2",
  "owner_created_at": "2026-04-28T00:00:00Z",
  "prd_slug": "$slug",
  "adopted_by": [],
  "sprints": [
    { "id": 1, "title": "bootstrap",  "status": "not_started",
      "branch": "sprint/$slug/01-bootstrap" },
    { "id": 2, "title": "core",       "status": "not_started",
      "branch": "sprint/$slug/02-core" }
  ]
}
EOF
  printf '# %s\n' "$slug"        > "$prd_dir/spec.md"
  printf '# Invariants\n'        > "$prd_dir/INVARIANTS.md"
  printf '# Sprint 1\n'          > "$prd_dir/sprints/01-bootstrap.md"
  printf '# Sprint 2\n'          > "$prd_dir/sprints/02-core.md"
  echo "$prd_dir"
}

# Mark a session "live" by dropping a heartbeat file into ~/.claude/state/active/
# (track-active-work.sh writes one of these for every running agent — we
# pretend a fake agent is keeping each session alive).
make_alive() {
  local sid="$1" id="$2"
  mkdir -p "$STATE/active"
  cat > "$STATE/active/agent-${id}.json" <<EOF
{"kind":"agent","id":"$id","name":"general-purpose","description":"test fake","started_at":$(date +%s),"background":"false","session_id":"$sid"}
EOF
}

mkdir -p "$REPO"
( cd "$REPO" && git init -q -b main && \
  git -c user.email=t@e.st -c user.name=t commit -q --allow-empty -m init )

hdr "Setup"
PRD_A="$(make_prd 2026-04-28_1430-feat-A "$SID_A")"
PRD_B="$(make_prd 2026-04-28_1431-feat-B "$SID_B")"
SLUG_A="$(basename "$PRD_A")"
SLUG_B="$(basename "$PRD_B")"
make_alive "$SID_A" "test-A"
make_alive "$SID_B" "test-B"
echo "  PRD A: $PRD_A"
echo "  PRD B: $PRD_B"

# Pointers
CLAUDE_SESSION_ID="$SID_A" bash "$HOOKS/active-plan-write.sh" "$PRD_A" >/dev/null
CLAUDE_SESSION_ID="$SID_B" bash "$HOOKS/active-plan-write.sh" "$PRD_B" >/dev/null

# ──────────────────────────── Tests ────────────────────────────

hdr "Test 1 — pointer-first plan resolution"
PTR_A="$STATE/active-plan-${SID_A}.json"
PTR_B="$STATE/active-plan-${SID_B}.json"
[ -f "$PTR_A" ] && ok "pointer A exists" || bad "pointer A missing"
[ -f "$PTR_B" ] && ok "pointer B exists" || bad "pointer B missing"

[ "$(jq -r .prd_slug "$PTR_A")" = "$SLUG_A" ] \
  && ok "pointer A → slug A" || bad "pointer A wrong slug"
[ "$(jq -r .prd_slug "$PTR_B")" = "$SLUG_B" ] \
  && ok "pointer B → slug B" || bad "pointer B wrong slug"

[ "$(jq -r .session_id "$PTR_A")" = "$SID_A" ] \
  && ok "pointer A bound to session A" || bad "pointer A wrong session"
[ "$(jq -r .session_id "$PTR_B")" = "$SID_B" ] \
  && ok "pointer B bound to session B" || bad "pointer B wrong session"


hdr "Test 2 — independent claims (A claims A's sprints, B claims B's)"
bash "$HOOKS/claim-sprint.sh" "$PRD_A/progress.json" 1 "$SID_A" >/dev/null \
  && ok "A claimed PRD A sprint 1" || bad "A failed to claim its own sprint"
bash "$HOOKS/claim-sprint.sh" "$PRD_B/progress.json" 1 "$SID_B" >/dev/null \
  && ok "B claimed PRD B sprint 1" || bad "B failed to claim its own sprint"

claimer_a="$(jq -r '.sprints[0].claimed_by_session' "$PRD_A/progress.json")"
claimer_b="$(jq -r '.sprints[0].claimed_by_session' "$PRD_B/progress.json")"
[ "$claimer_a" = "$SID_A" ] && ok "PRD A sprint 1 ← A" || bad "PRD A claim wrong: $claimer_a"
[ "$claimer_b" = "$SID_B" ] && ok "PRD B sprint 1 ← B" || bad "PRD B claim wrong: $claimer_b"


hdr "Test 3 — same-PRD race (B tries A's already-claimed sprint)"
set +e
bash "$HOOKS/claim-sprint.sh" "$PRD_A/progress.json" 1 "$SID_B" >/dev/null 2>&1
rc=$?
set -e
[ $rc -eq 1 ] && ok "B refused: exit 1 (peer-owned, fresh)" \
              || bad "B should have got exit 1, got $rc"
claim_after="$(jq -r '.sprints[0].claimed_by_session' "$PRD_A/progress.json")"
[ "$claim_after" = "$SID_A" ] && ok "A's claim survived race" \
                              || bad "A's claim was overwritten: now $claim_after"


hdr "Test 4 — terminal status protection"
# Force a sprint to complete and try to claim it: must exit 3.
jq '(.sprints[] | select(.id==2)).status = "complete"' "$PRD_A/progress.json" \
  > "$PRD_A/progress.json.tmp" && mv "$PRD_A/progress.json.tmp" "$PRD_A/progress.json"
set +e
bash "$HOOKS/claim-sprint.sh" "$PRD_A/progress.json" 2 "$SID_A" >/dev/null 2>&1
rc=$?
set -e
[ $rc -eq 3 ] && ok "complete sprint refused: exit 3" \
              || bad "complete sprint should give exit 3, got $rc"


hdr "Test 5 — stale-claim adoption (--force after pointer + heartbeat go away)"
# Make a third PRD where A claims, then kill A's pointer + heartbeat,
# forge a heartbeat 31 minutes old.
PRD_C="$(make_prd 2026-04-28_1432-feat-C "$SID_A")"
SLUG_C="$(basename "$PRD_C")"
bash "$HOOKS/claim-sprint.sh" "$PRD_C/progress.json" 1 "$SID_A" >/dev/null
old_ts="$(date -u -d '31 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
jq --arg t "$old_ts" '(.sprints[] | select(.id==1)).claim_heartbeat_at = $t' \
   "$PRD_C/progress.json" > "$PRD_C/progress.json.tmp" \
   && mv "$PRD_C/progress.json.tmp" "$PRD_C/progress.json"

# Without --force: stale → exit 2
set +e
bash "$HOOKS/claim-sprint.sh" "$PRD_C/progress.json" 1 "$SID_B" >/dev/null 2>&1
rc=$?
set -e
[ $rc -eq 2 ] && ok "stale claim: exit 2 without --force" \
              || bad "stale claim should give exit 2, got $rc"

# With --force: B takes over (legitimate adoption)
bash "$HOOKS/claim-sprint.sh" "$PRD_C/progress.json" 1 "$SID_B" --force >/dev/null \
  && ok "B force-adopted stale claim" || bad "force-adopt should succeed"
new_claim="$(jq -r '.sprints[0].claimed_by_session' "$PRD_C/progress.json")"
[ "$new_claim" = "$SID_B" ] && ok "PRD C sprint 1 ← B (after adoption)" \
                            || bad "force-adopt did not flip claim: $new_claim"


hdr "Test 6 — release-sprint refuses cross-session writes"
# B is now the claimer of PRD C sprint 1. Try to release as A — must fail.
set +e
bash "$HOOKS/release-sprint.sh" "$PRD_C/progress.json" 1 "$SID_A" complete >/dev/null 2>&1
rc=$?
set -e
[ $rc -ne 0 ] && ok "release by non-claimer rejected" \
              || bad "release should refuse session_id mismatch, got rc=0"
status_after="$(jq -r '.sprints[0].status' "$PRD_C/progress.json")"
[ "$status_after" = "in_progress" ] && ok "sprint state intact after rejected release" \
                                     || bad "rejected release leaked: status=$status_after"


hdr "Test 7 — heartbeat refresh"
prev_hb="$(jq -r '.sprints[0].claim_heartbeat_at' "$PRD_A/progress.json")"
sleep 1
bash "$HOOKS/heartbeat-sprint.sh" "$PRD_A/progress.json" 1 "$SID_A" >/dev/null \
  && ok "heartbeat ran" || bad "heartbeat failed"
new_hb="$(jq -r '.sprints[0].claim_heartbeat_at' "$PRD_A/progress.json")"
[ "$new_hb" != "$prev_hb" ] && ok "heartbeat advanced ($prev_hb → $new_hb)" \
                            || bad "heartbeat did not advance"


hdr "Test 8 — branch & worktree namespace are PRD-scoped"
( cd "$REPO" && \
  git branch "prd/$SLUG_A" main 2>/dev/null && \
  git branch "prd/$SLUG_B" main 2>/dev/null && \
  git worktree add -q -b "sprint/$SLUG_A/01-bootstrap" "$REPO/.worktrees/$SLUG_A/01-bootstrap" "prd/$SLUG_A" && \
  git worktree add -q -b "sprint/$SLUG_B/01-bootstrap" "$REPO/.worktrees/$SLUG_B/01-bootstrap" "prd/$SLUG_B" \
) || true
( cd "$REPO" && git branch -l ) > /tmp/branches-out.$$
grep -q "sprint/$SLUG_A/01-bootstrap" /tmp/branches-out.$$ && grep -q "sprint/$SLUG_B/01-bootstrap" /tmp/branches-out.$$ \
  && ok "both PRDs have namespaced sprint branches" \
  || bad "missing one of the namespaced sprint branches"
[ -d "$REPO/.worktrees/$SLUG_A/01-bootstrap" ] && [ -d "$REPO/.worktrees/$SLUG_B/01-bootstrap" ] \
  && ok "worktrees coexist under different slug roots" \
  || bad "namespaced worktrees missing"
rm -f /tmp/branches-out.$$


hdr "Test 9 — concurrent claims race against same sprint (real flock contention)"
PRD_D="$(make_prd 2026-04-28_1433-feat-D "$SID_A")"
LOG_A="$TMP/race-A.log"; LOG_B="$TMP/race-B.log"
( set +e
  bash "$HOOKS/claim-sprint.sh" "$PRD_D/progress.json" 1 "$SID_A" \
    >"$LOG_A" 2>&1
  echo $? >"$LOG_A.rc"
) &
( set +e
  bash "$HOOKS/claim-sprint.sh" "$PRD_D/progress.json" 1 "$SID_B" \
    >"$LOG_B" 2>&1
  echo $? >"$LOG_B.rc"
) &
wait
rc_a="$(cat "$LOG_A.rc")"; rc_b="$(cat "$LOG_B.rc")"
winners=0
[ "$rc_a" = "0" ] && winners=$((winners+1))
[ "$rc_b" = "0" ] && winners=$((winners+1))
[ $winners -eq 1 ] && ok "exactly one winner under contention (rc_A=$rc_a rc_B=$rc_b)" \
                   || bad "expected 1 winner, got $winners (rc_A=$rc_a rc_B=$rc_b)"


hdr "Test 10 — main-merge flock serializes"
LOCK="$REPO/.git/main-merge.lock"
RUN_LOG="$TMP/main-merge.log"
: > "$RUN_LOG"
critical_section() {
  local who="$1" hold="$2"
  exec 8>"$LOCK"
  flock -x -w 30 8
  echo "[$(date +%s.%N)] $who acquired" >> "$RUN_LOG"
  sleep "$hold"
  echo "[$(date +%s.%N)] $who released" >> "$RUN_LOG"
  exec 8>&-
}
critical_section A 1 &  pid_a=$!
critical_section B 1 &  pid_b=$!
wait "$pid_a" "$pid_b"
# The two sections must be sequential, not interleaved.
seq=$(awk '{print $2}' "$RUN_LOG" | tr '\n' ',')
case "$seq" in
  A,A,B,B,|B,B,A,A,) ok "merge sections serialized (sequence=${seq%,})" ;;
  *)                 bad "merge sections interleaved: ${seq%,}" ;;
esac


hdr "Test 11 — relocate-plan hook drops files into <project>/docs/plans/"
# Pretend ExitPlanMode just wrote a fresh plan into ~/.claude/plans/.
mkdir -p "$HOME/.claude/plans"
PLAN="$HOME/.claude/plans/test-relocate-$$.md"
printf '# Test relocate\n\nfoo\n' > "$PLAN"
( cd "$REPO" && \
  printf '%s' '{"tool_name":"ExitPlanMode","tool_input":{"plan":"# x"}}' \
  | bash "$HOME/.claude/hooks/relocate-plan.sh" >/dev/null 2>&1 ) || true
[ -f "$REPO/docs/plans/$(basename "$PLAN")" ] \
  && ok "plan landed at <project>/docs/plans/" \
  || bad "plan was not relocated into project"
[ ! -f "$PLAN" ] && ok "source removed from ~/.claude/plans/" \
                 || bad "source file still in ~/.claude/plans/"
rm -f "$PLAN.moved"


# ──────────────────────────── Result ────────────────────────────

echo
echo "──────────────────────────────"
echo "passed:   $PASS"
echo "failed:   $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "FAILURES:"
  for f in "${FAILED_TESTS[@]}"; do echo "  - $f"; done
  exit 1
fi
echo "All concurrency invariants hold."

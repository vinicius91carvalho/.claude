#!/usr/bin/env bash
set -uo pipefail

# Test suite for relocate-plan.sh — the PostToolUse hook that moves
# ExitPlanMode markdown out of ~/.claude/plans/ and into the project repo.
#
# Covers:
#   1. Relocates a fresh plan into <git-toplevel>/docs/plans/
#   2. Skips when tool_name != ExitPlanMode (no-op)
#   3. Skips a plan older than 60s (not from this turn)
#   4. Falls back to $PWD when not inside a git repo
#   5. Honors $CLAUDE_PROJECT_DIR if set
#   6. Suffixes destination filename when target already exists
#   7. Fail-open: never blocks the tool call (always exits 0)

HOOK="$HOME/.claude/hooks/relocate-plan.sh"
PLANS_DIR="$HOME/.claude/plans"
TMP_DIR=""

PASS=0
FAIL=0
ERRORS=()

pass() { PASS=$((PASS+1)); printf "  ✓ %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  ✗ %s (%s)\n" "$1" "$2"; ERRORS+=("$1: $2"); }
section() { printf "\n▸ %s\n" "$1"; }

if [ ! -x "$HOOK" ]; then
  printf "HOOK NOT EXECUTABLE: %s\n" "$HOOK"
  exit 1
fi

setup() {
  TMP_DIR="$(mktemp -d -t test-relocate-XXXX)"
  mkdir -p "$PLANS_DIR"
}

teardown() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    find "$TMP_DIR" -type f -delete 2>/dev/null
    find "$TMP_DIR" -depth -type d -empty -delete 2>/dev/null
  fi
  # Remove any leftover plan files this test created.
  find "$PLANS_DIR" -maxdepth 1 -name 'test-relocate-*.md*' -delete 2>/dev/null
}

trap teardown EXIT

setup

# ── 1. Happy path: fresh plan + git repo → moved into <toplevel>/docs/plans/
section "fresh plan + git repo → relocated"
mkdir -p "$TMP_DIR/repo1"
( cd "$TMP_DIR/repo1" && git init -q -b main && \
  git -c user.email=t@e.st -c user.name=t commit -q --allow-empty -m init )
PLAN_NAME="test-relocate-fresh-$$.md"
PLAN_PATH="$PLANS_DIR/$PLAN_NAME"
printf '# Fresh plan\n' > "$PLAN_PATH"
( cd "$TMP_DIR/repo1" && \
  printf '%s' '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}' \
    | bash "$HOOK" >/dev/null 2>&1 )
RC=$?
[ $RC -eq 0 ] && pass "exit 0" || fail "exit code" "got $RC"
[ -f "$TMP_DIR/repo1/docs/plans/$PLAN_NAME" ] \
  && pass "plan landed in repo's docs/plans/" \
  || fail "plan not relocated" "expected $TMP_DIR/repo1/docs/plans/$PLAN_NAME"
[ ! -f "$PLAN_PATH" ] && pass "source removed from ~/.claude/plans/" \
                     || fail "source still in ~/.claude/plans/" "$PLAN_PATH"

# ── 2. Wrong tool name → no-op
section "tool_name != ExitPlanMode → no-op"
PLAN2="$PLANS_DIR/test-relocate-noop-$$.md"
printf '# noop\n' > "$PLAN2"
( cd "$TMP_DIR/repo1" && \
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | bash "$HOOK" >/dev/null 2>&1 )
[ -f "$PLAN2" ] && pass "plan untouched on non-ExitPlanMode call" \
               || fail "wrong-tool no-op" "plan moved when it shouldn't have"
rm -f "$PLAN2"

# ── 3. Plan older than 60s → not picked up
section "plan older than 60s → ignored"
PLAN3="$PLANS_DIR/test-relocate-old-$$.md"
printf '# old\n' > "$PLAN3"
# Backdate to 90s ago.
touch -d '@'"$(($(date +%s) - 90))" "$PLAN3"
mkdir -p "$TMP_DIR/repo3"
( cd "$TMP_DIR/repo3" && git init -q -b main && \
  git -c user.email=t@e.st -c user.name=t commit -q --allow-empty -m init )
( cd "$TMP_DIR/repo3" && \
  printf '%s' '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}' \
    | bash "$HOOK" >/dev/null 2>&1 )
[ -f "$PLAN3" ] && pass "stale plan left in place" \
               || fail "stale-plan ignore" "old plan was moved"
[ ! -f "$TMP_DIR/repo3/docs/plans/$(basename "$PLAN3")" ] \
  && pass "destination not created for stale plan" \
  || fail "stale plan was relocated anyway" "found at $TMP_DIR/repo3/docs/plans/"
rm -f "$PLAN3"

# ── 4. No git repo → falls back to $PWD
section "no git repo → falls back to PWD"
mkdir -p "$TMP_DIR/no-git"
PLAN4="$PLANS_DIR/test-relocate-nogit-$$.md"
printf '# nogit\n' > "$PLAN4"
PLAN4_NAME="$(basename "$PLAN4")"
( cd "$TMP_DIR/no-git" && \
  printf '%s' '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}' \
    | bash "$HOOK" >/dev/null 2>&1 )
[ -f "$TMP_DIR/no-git/docs/plans/$PLAN4_NAME" ] \
  && pass "fallback to PWD when no git toplevel" \
  || fail "no-git fallback" "expected $TMP_DIR/no-git/docs/plans/$PLAN4_NAME"

# ── 5. CLAUDE_PROJECT_DIR overrides PWD
section "CLAUDE_PROJECT_DIR overrides PWD"
mkdir -p "$TMP_DIR/claude-proj"
mkdir -p "$TMP_DIR/elsewhere"
PLAN5="$PLANS_DIR/test-relocate-projdir-$$.md"
printf '# projdir\n' > "$PLAN5"
PLAN5_NAME="$(basename "$PLAN5")"
( cd "$TMP_DIR/elsewhere" && \
  CLAUDE_PROJECT_DIR="$TMP_DIR/claude-proj" \
  printf '%s' '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}' \
    | CLAUDE_PROJECT_DIR="$TMP_DIR/claude-proj" bash "$HOOK" >/dev/null 2>&1 )
if [ -f "$TMP_DIR/claude-proj/docs/plans/$PLAN5_NAME" ]; then
  pass "honors CLAUDE_PROJECT_DIR over PWD"
else
  fail "CLAUDE_PROJECT_DIR ignored" \
    "expected $TMP_DIR/claude-proj/docs/plans/$PLAN5_NAME, found $(ls "$TMP_DIR/elsewhere/docs/plans/" 2>/dev/null)"
fi

# ── 6. Filename collision → timestamp-suffixed
section "destination collision → timestamp-suffix preserves both"
mkdir -p "$TMP_DIR/repo6/docs/plans"
( cd "$TMP_DIR/repo6" && git init -q -b main && \
  git -c user.email=t@e.st -c user.name=t commit -q --allow-empty -m init )
COLLIDE_NAME="test-relocate-collide-$$.md"
printf '# pre-existing\n' > "$TMP_DIR/repo6/docs/plans/$COLLIDE_NAME"
PLAN6="$PLANS_DIR/$COLLIDE_NAME"
printf '# new\n' > "$PLAN6"
( cd "$TMP_DIR/repo6" && \
  printf '%s' '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}' \
    | bash "$HOOK" >/dev/null 2>&1 )
COUNT=$(find "$TMP_DIR/repo6/docs/plans" -name "test-relocate-collide-*.md" | wc -l)
[ "$COUNT" -eq 2 ] && pass "both files preserved (count=$COUNT)" \
                   || fail "collision handling" "expected 2 files, got $COUNT"

# ── 7. Fail-open: corrupt JSON input → still exits 0
section "corrupt JSON → fail-open (exit 0)"
PLAN7="$PLANS_DIR/test-relocate-corrupt-$$.md"
printf '# corrupt\n' > "$PLAN7"
echo '{not valid json' | bash "$HOOK" >/dev/null 2>&1
RC=$?
[ $RC -eq 0 ] && pass "fail-open on bad input (exit 0)" \
              || fail "fail-open" "got rc=$RC"
rm -f "$PLAN7"

# ── Summary
printf "\n──────────────────────────────\n"
printf "passed: %d\n" "$PASS"
printf "failed: %d\n" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "\nFAILURES:\n"
  for e in "${ERRORS[@]}"; do printf "  - %s\n" "$e"; done
  exit 1
fi
exit 0

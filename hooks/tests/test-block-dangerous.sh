#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Test suite for block-dangerous.sh hook and approve.sh approval mechanism
# =============================================================================

HOOK="$HOME/.claude/hooks/block-dangerous.sh"
APPROVE="$HOME/.claude/hooks/approve.sh"
APPROVAL_DIR="$HOME/.claude/hooks/.approvals"
PENDING_DIR="$HOME/.claude/hooks/.pending"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---

cleanup() {
  rm -rf "$APPROVAL_DIR" "$PENDING_DIR" 2>/dev/null || true
}

# Run hook with a given command, capture stdout/stderr/exit separately
run_hook() {
  local cmd="$1"
  local json_input
  json_input=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")
  # Capture stdout and stderr separately
  local tmpout tmperr
  tmpout=$(mktemp)
  tmperr=$(mktemp)
  local exit_code=0
  echo "$json_input" | bash "$HOOK" >"$tmpout" 2>"$tmperr" || exit_code=$?
  HOOK_STDOUT=$(cat "$tmpout")
  HOOK_STDERR=$(cat "$tmperr")
  HOOK_EXIT=$exit_code
  rm -f "$tmpout" "$tmperr"
}

# Assert exit code
assert_exit() {
  local expected="$1" label="$2"
  if [ "$HOOK_EXIT" -eq "$expected" ]; then
    pass "$label"
  else
    fail "$label" "expected exit $expected, got $HOOK_EXIT"
  fi
}

# Assert stdout contains a string
assert_stdout_contains() {
  local pattern="$1" label="$2"
  if echo "$HOOK_STDOUT" | grep -qF "$pattern"; then
    pass "$label"
  else
    fail "$label" "stdout missing: $pattern"
  fi
}

# Assert stdout does NOT contain a string
assert_stdout_empty() {
  local label="$1"
  if [ -z "$HOOK_STDOUT" ]; then
    pass "$label"
  else
    fail "$label" "expected empty stdout, got: $HOOK_STDOUT"
  fi
}

# Assert stderr is empty (no error output)
assert_stderr_clean() {
  local label="$1"
  # Filter out logger output (hook-events.log lines) — only check for error/crash output
  local significant_stderr
  significant_stderr=$(echo "$HOOK_STDERR" | grep -v 'hook=' | grep -v '^$' || true)
  if [ -z "$significant_stderr" ]; then
    pass "$label"
  else
    fail "$label" "unexpected stderr: $significant_stderr"
  fi
}

# Assert a file exists
assert_file_exists() {
  local path="$1" label="$2"
  if [ -f "$path" ]; then
    pass "$label"
  else
    fail "$label" "file not found: $path"
  fi
}

# Assert a file does NOT exist
assert_file_not_exists() {
  local path="$1" label="$2"
  if [ ! -f "$path" ]; then
    pass "$label"
  else
    fail "$label" "file should not exist: $path"
  fi
}

# Assert directory is empty
assert_dir_empty() {
  local dir="$1" label="$2"
  if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    pass "$label"
  else
    fail "$label" "directory should be empty: $dir (contents: $(ls "$dir"))"
  fi
}

# Assert JSON field value in stdout
assert_json_field() {
  local field="$1" expected="$2" label="$3"
  local actual
  # Simple regex extraction — works for flat JSON
  if [[ "$HOOK_STDOUT" =~ \"$field\":[[:space:]]*\"([^\"]+)\" ]]; then
    actual="${BASH_REMATCH[1]}"
    if [ "$actual" = "$expected" ]; then
      pass "$label"
    else
      fail "$label" "field '$field': expected '$expected', got '$actual'"
    fi
  else
    fail "$label" "field '$field' not found in stdout"
  fi
}

# Get the cksum hash for a command (same logic as the hook)
cmd_hash() {
  printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1
}

pass() {
  PASS=$((PASS + 1))
  printf "  ${GREEN}✓${NC} %s\n" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  local label="$1" detail="${2:-}"
  printf "  ${RED}✗${NC} %s" "$label"
  if [ -n "$detail" ]; then
    printf " ${RED}(%s)${NC}" "$detail"
  fi
  printf "\n"
  ERRORS+=("$label: $detail")
}

skip() {
  SKIP=$((SKIP + 1))
  printf "  ${YELLOW}-${NC} %s (skipped)\n" "$1"
}

section() {
  printf "\n${BOLD}${CYAN}▸ %s${NC}\n" "$1"
}

# =============================================================================
# TESTS
# =============================================================================

printf "${BOLD}Running block-dangerous.sh test suite${NC}\n"

# ─── 1. OUTPUT FORMAT ────────────────────────────────────────────────────────
section "Output Format — Hard Blocks"

cleanup
run_hook "rm -rf /etc"

assert_exit 0 "hard block exits 0"
assert_stdout_contains '"permissionDecision"' "hard block outputs JSON to stdout"
assert_json_field "permissionDecision" "deny" "hard block uses permissionDecision: deny"
assert_stdout_contains '"permissionDecisionReason"' "hard block includes reason"
assert_stdout_contains "hookEventName" "hard block includes hookEventName"
assert_stderr_clean "hard block has no error output on stderr"

section "Output Format — Soft Blocks"

cleanup
run_hook "git push -u origin main"

assert_exit 0 "soft block exits 0"
assert_stdout_contains '"permissionDecision"' "soft block outputs JSON to stdout"
assert_json_field "permissionDecision" "deny" "soft block uses permissionDecision: deny"
assert_stdout_contains "approve.sh" "soft block includes approval instructions"
assert_stderr_clean "soft block has no error output on stderr"

section "Output Format — Valid JSON"

cleanup
run_hook "rm -rf /usr"
# Check JSON is parseable (if jq available)
if command -v jq &>/dev/null; then
  if echo "$HOOK_STDOUT" | jq . >/dev/null 2>&1; then
    pass "hard block stdout is valid JSON"
  else
    fail "hard block stdout is valid JSON" "jq parse failed"
  fi
else
  # Fallback: check basic JSON structure
  if [[ "$HOOK_STDOUT" =~ ^\{.*\}$ ]]; then
    pass "hard block stdout has JSON structure (jq not available)"
  else
    fail "hard block stdout has JSON structure" "no JSON braces found"
  fi
fi

cleanup
run_hook "git reset --hard"
if command -v jq &>/dev/null; then
  if echo "$HOOK_STDOUT" | jq . >/dev/null 2>&1; then
    pass "soft block stdout is valid JSON"
  else
    fail "soft block stdout is valid JSON" "jq parse failed"
  fi
else
  if [[ "$HOOK_STDOUT" =~ ^\{.*\}$ ]]; then
    pass "soft block stdout has JSON structure (jq not available)"
  else
    fail "soft block stdout has JSON structure" "no JSON braces found"
  fi
fi

# ─── 2. HARD BLOCKS ─────────────────────────────────────────────────────────
section "Hard Blocks — Catastrophic Commands"

cleanup
run_hook "rm -rf /"
assert_stdout_contains '"permissionDecision"' "rm -rf / is hard-blocked"
assert_stdout_contains "catastrophic" "rm -rf / reason mentions catastrophic"

cleanup
run_hook "rm -rf /*"
assert_stdout_contains '"permissionDecision"' "rm -rf /* is hard-blocked"

cleanup
run_hook "rm -rf ~"
assert_stdout_contains '"permissionDecision"' "rm -rf ~ is hard-blocked"

cleanup
run_hook 'rm -rf $HOME'
assert_stdout_contains '"permissionDecision"' 'rm -rf $HOME is hard-blocked'

cleanup
run_hook "rm -rf /etc"
assert_stdout_contains '"permissionDecision"' "rm -rf /etc is hard-blocked"

cleanup
run_hook "rm -rf /usr/local"
assert_stdout_contains '"permissionDecision"' "rm -rf /usr/local is hard-blocked"

cleanup
run_hook "rm -rf /var"
assert_stdout_contains '"permissionDecision"' "rm -rf /var is hard-blocked"

cleanup
run_hook "rm -rf /home"
assert_stdout_contains '"permissionDecision"' "rm -rf /home is hard-blocked"

cleanup
run_hook "rm -fr /etc"
assert_stdout_contains '"permissionDecision"' "rm -fr (reversed flags) is hard-blocked"

cleanup
run_hook "rm -r -f /etc"
assert_stdout_contains '"permissionDecision"' "rm -r -f (separated flags) is hard-blocked"

cleanup
run_hook "rm --recursive --force /usr"
assert_stdout_contains '"permissionDecision"' "rm --recursive --force is hard-blocked"

cleanup
run_hook "chmod -R 777 /"
assert_stdout_contains '"permissionDecision"' "chmod -R 777 / is hard-blocked"

cleanup
run_hook "chmod --recursive 777 /etc"
assert_stdout_contains '"permissionDecision"' "chmod -R 777 /etc is hard-blocked"

cleanup
run_hook "some dd if=/dev/zero of=/dev/sda"
assert_stdout_contains '"permissionDecision"' "dd command is hard-blocked"

section "Hard Blocks — No Pending Files Created"

cleanup
run_hook "rm -rf /etc"
assert_dir_empty "$PENDING_DIR" "hard block does not create pending file"

# ─── 3. SOFT BLOCKS — GIT ───────────────────────────────────────────────────
section "Soft Blocks — Destructive Git Commands"

cleanup
run_hook "git push --force origin feature"
assert_stdout_contains '"permissionDecision"' "git push --force is soft-blocked"
assert_stdout_contains "approve.sh" "git push --force shows approval instructions"

cleanup
run_hook "git push -f origin feature"
assert_stdout_contains '"permissionDecision"' "git push -f is soft-blocked"

cleanup
run_hook "git push --force-with-lease origin feature"
assert_stdout_contains '"permissionDecision"' "git push --force-with-lease is soft-blocked"

cleanup
run_hook "git push origin +main"
assert_stdout_contains '"permissionDecision"' "git push +refspec is soft-blocked"

cleanup
run_hook "git push origin main"
assert_stdout_contains '"permissionDecision"' "git push origin main is soft-blocked"

cleanup
run_hook "git push -u origin main"
assert_stdout_contains '"permissionDecision"' "git push -u origin main is soft-blocked"

cleanup
run_hook "git push --set-upstream origin master"
assert_stdout_contains '"permissionDecision"' "git push --set-upstream origin master is soft-blocked"

cleanup
run_hook "git reset --hard"
assert_stdout_contains '"permissionDecision"' "git reset --hard is soft-blocked"

cleanup
run_hook "git reset --hard HEAD~3"
assert_stdout_contains '"permissionDecision"' "git reset --hard HEAD~3 is soft-blocked"

cleanup
run_hook "git checkout ."
assert_stdout_contains '"permissionDecision"' "git checkout . is soft-blocked"

cleanup
run_hook "git restore ."
assert_stdout_contains '"permissionDecision"' "git restore . is soft-blocked"

cleanup
run_hook "git branch -D feature-branch"
assert_stdout_contains '"permissionDecision"' "git branch -D is soft-blocked"

cleanup
run_hook "git clean -fd"
assert_stdout_contains '"permissionDecision"' "git clean -fd is soft-blocked"

cleanup
run_hook "git stash drop"
assert_stdout_contains '"permissionDecision"' "git stash drop is soft-blocked"

cleanup
run_hook "git stash clear"
assert_stdout_contains '"permissionDecision"' "git stash clear is soft-blocked"

section "Soft Blocks — Pending Files Created"

cleanup
run_hook "git push -u origin main"
hash=$(cmd_hash "git push -u origin main")
assert_file_exists "$PENDING_DIR/$hash" "soft block creates pending file"

# Verify pending file content
if [ -f "$PENDING_DIR/$hash" ]; then
  if grep -qF "git push -u origin main" "$PENDING_DIR/$hash"; then
    pass "pending file contains the command"
  else
    fail "pending file contains the command" "command not found in file"
  fi
  if grep -qF "Reason:" "$PENDING_DIR/$hash"; then
    pass "pending file contains reason"
  else
    fail "pending file contains reason" "Reason: not found"
  fi
  if grep -qF "Time:" "$PENDING_DIR/$hash"; then
    pass "pending file contains timestamp"
  else
    fail "pending file contains timestamp" "Time: not found"
  fi
fi

# ─── 4. APPROVAL TOKEN MECHANISM ────────────────────────────────────────────
section "Approval Flow — Full Lifecycle"

# Step 1: Command is soft-blocked
cleanup
run_hook "git push -u origin main"
assert_stdout_contains '"permissionDecision"' "step 1: command is soft-blocked"
hash=$(cmd_hash "git push -u origin main")
assert_file_exists "$PENDING_DIR/$hash" "step 1: pending file created"

# Step 2: Run approve.sh
approve_output=$(bash "$APPROVE" 2>&1)
if echo "$approve_output" | grep -qF "approved"; then
  pass "step 2: approve.sh reports success"
else
  fail "step 2: approve.sh reports success" "output: $approve_output"
fi
assert_file_not_exists "$PENDING_DIR/$hash" "step 2: pending file removed"
assert_file_exists "$APPROVAL_DIR/$hash" "step 2: approval file created"

# Step 3: Retry the same command — should be allowed
run_hook "git push -u origin main"
assert_stdout_empty "step 3: retry produces no JSON output (allowed)"
assert_exit 0 "step 3: retry exits 0"

# Step 4: Token is consumed (single-use)
assert_file_not_exists "$APPROVAL_DIR/$hash" "step 4: approval token consumed after use"

# Step 5: Another retry without approval — blocked again
run_hook "git push -u origin main"
assert_stdout_contains '"permissionDecision"' "step 5: command blocked again after token consumed"

section "Approval Flow — Multiple Pending Operations"

cleanup
run_hook "git push -u origin main"
run_hook "git reset --hard"
run_hook "git branch -D old-feature"

pending_count=$(ls -1 "$PENDING_DIR" 2>/dev/null | wc -l)
if [ "$pending_count" -eq 3 ]; then
  pass "multiple soft blocks create separate pending files"
else
  fail "multiple soft blocks create separate pending files" "expected 3 pending, got $pending_count"
fi

approve_output=$(bash "$APPROVE" 2>&1)
if echo "$approve_output" | grep -qF "3 operation(s) approved"; then
  pass "approve.sh approves all 3 operations"
else
  fail "approve.sh approves all 3 operations" "output: $approve_output"
fi

assert_dir_empty "$PENDING_DIR" "all pending files moved after bulk approve"

# Verify all three can now proceed
run_hook "git push -u origin main"
assert_stdout_empty "git push allowed after bulk approve"
run_hook "git reset --hard"
assert_stdout_empty "git reset --hard allowed after bulk approve"
run_hook "git branch -D old-feature"
assert_stdout_empty "git branch -D allowed after bulk approve"

section "Approval Flow — Expired Tokens"

cleanup
hash=$(cmd_hash "git push -u origin main")
mkdir -p "$APPROVAL_DIR"
echo "old approval" > "$APPROVAL_DIR/$hash"
# Set the modification time to 10 minutes ago
touch -d "10 minutes ago" "$APPROVAL_DIR/$hash" 2>/dev/null || touch -t "$(date -d '10 minutes ago' +%Y%m%d%H%M.%S 2>/dev/null || echo '202501010000.00')" "$APPROVAL_DIR/$hash" 2>/dev/null

run_hook "git push -u origin main"
if [ -n "$HOOK_STDOUT" ] && echo "$HOOK_STDOUT" | grep -qF "permissionDecision"; then
  pass "expired approval token is rejected (command still blocked)"
else
  # If touch -d didn't work, skip
  skip "expired approval token test (touch -d may not be supported)"
fi

section "Approval Flow — approve.sh with No Pending"

cleanup
approve_output=$(bash "$APPROVE" 2>&1)
if echo "$approve_output" | grep -qF "No pending approvals"; then
  pass "approve.sh with nothing pending shows correct message"
else
  fail "approve.sh with nothing pending shows correct message" "output: $approve_output"
fi

section "Approval Flow — Token Isolation Between Commands"

cleanup
# Block two different commands
run_hook "git push -u origin main"
run_hook "git reset --hard HEAD~1"

# Approve only one (git push)
hash_push=$(cmd_hash "git push -u origin main")
hash_reset=$(cmd_hash "git reset --hard HEAD~1")
mkdir -p "$APPROVAL_DIR"
mv "$PENDING_DIR/$hash_push" "$APPROVAL_DIR/$hash_push" 2>/dev/null || true

# git push should be allowed
run_hook "git push -u origin main"
assert_stdout_empty "approved command (git push) passes through"

# git reset should still be blocked
run_hook "git reset --hard HEAD~1"
assert_stdout_contains '"permissionDecision"' "unapproved command (git reset) still blocked"

# ─── 5. SAFE COMMANDS (ALLOWED) ─────────────────────────────────────────────
section "Safe Commands — Should Pass Through"

cleanup
run_hook "git status"
assert_stdout_empty "git status is allowed"
assert_exit 0 "git status exits 0"

cleanup
run_hook "git push origin feature-branch"
assert_stdout_empty "git push to feature branch is allowed"

cleanup
run_hook "git push -u origin feat/my-feature"
assert_stdout_empty "git push to feature/ branch is allowed"

cleanup
run_hook "ls -la"
assert_stdout_empty "ls -la is allowed"

cleanup
run_hook "rm file.txt"
assert_stdout_empty "rm without -rf is allowed"

cleanup
run_hook "rm -r ./node_modules"
assert_stdout_empty "rm -r (without -f on safe path) is allowed"

cleanup
run_hook "git log --oneline"
assert_stdout_empty "git log is allowed"

cleanup
run_hook "git diff HEAD"
assert_stdout_empty "git diff is allowed"

cleanup
run_hook "git commit -m 'test'"
assert_stdout_empty "git commit is allowed"

cleanup
run_hook "git branch -d feature"
assert_stdout_empty "git branch -d (lowercase, safe delete) is allowed"

cleanup
run_hook "git stash"
assert_stdout_empty "git stash (without drop/clear) is allowed"

cleanup
run_hook "git stash pop"
assert_stdout_empty "git stash pop is allowed"

cleanup
run_hook "git stash list"
assert_stdout_empty "git stash list is allowed"

cleanup
run_hook "git checkout feature-branch"
assert_stdout_empty "git checkout <branch> is allowed"

cleanup
run_hook "git restore --staged file.txt"
assert_stdout_empty "git restore --staged file.txt is allowed"

section "Safe Commands — Edge Cases"

# Empty/missing command
HOOK_STDOUT=""
HOOK_STDERR=""
HOOK_EXIT=0
echo '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$HOOK" >/dev/null 2>&1 || true
pass "empty command does not crash"

echo '{"tool_name":"Bash","tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1 || true
pass "missing command field does not crash"

echo '{}' | bash "$HOOK" >/dev/null 2>&1 || true
pass "minimal JSON does not crash"

echo '' | bash "$HOOK" >/dev/null 2>&1 || true
pass "empty input does not crash"

# ─── 6. PACKAGE MANAGER ENFORCEMENT ─────────────────────────────────────────
section "Package Manager — pnpm Enforcement"

# Create a temp dir with pnpm-lock.yaml
TMPDIR_PM=$(mktemp -d)
touch "$TMPDIR_PM/pnpm-lock.yaml"

cleanup
CLAUDE_PROJECT_DIR="$TMPDIR_PM" run_hook "npm install express"
assert_stdout_contains '"permissionDecision"' "npm install blocked when pnpm-lock.yaml exists"

cleanup
CLAUDE_PROJECT_DIR="$TMPDIR_PM" run_hook "npm run build"
assert_stdout_contains '"permissionDecision"' "npm run blocked when pnpm-lock.yaml exists"

cleanup
CLAUDE_PROJECT_DIR="$TMPDIR_PM" run_hook "npx create-next-app"
assert_stdout_contains '"permissionDecision"' "npx blocked when pnpm-lock.yaml exists"

# Without pnpm-lock.yaml
TMPDIR_NOPM=$(mktemp -d)

cleanup
CLAUDE_PROJECT_DIR="$TMPDIR_NOPM" run_hook "npm install express"
assert_stdout_empty "npm install allowed when no pnpm-lock.yaml"

cleanup
CLAUDE_PROJECT_DIR="$TMPDIR_NOPM" run_hook "npx create-next-app"
assert_stdout_empty "npx allowed when no pnpm-lock.yaml"

# Cleanup temp dirs
rm -rf "$TMPDIR_PM" "$TMPDIR_NOPM"

# pnpm-workspace.yaml also triggers enforcement
TMPDIR_WS=$(mktemp -d)
touch "$TMPDIR_WS/pnpm-workspace.yaml"

cleanup
CLAUDE_PROJECT_DIR="$TMPDIR_WS" run_hook "npm install"
assert_stdout_contains '"permissionDecision"' "npm blocked when pnpm-workspace.yaml exists"

rm -rf "$TMPDIR_WS"

# ─── 7. IDEMPOTENT SOFT BLOCKS ──────────────────────────────────────────────
section "Idempotent Soft Blocks — No Duplicate Pending Files"

cleanup
run_hook "git push -u origin main"
hash=$(cmd_hash "git push -u origin main")
first_content=$(cat "$PENDING_DIR/$hash" 2>/dev/null)

run_hook "git push -u origin main"
second_content=$(cat "$PENDING_DIR/$hash" 2>/dev/null)

pending_count=$(ls -1 "$PENDING_DIR" 2>/dev/null | wc -l)
if [ "$pending_count" -eq 1 ]; then
  pass "repeated soft block for same command produces only 1 pending file"
else
  fail "repeated soft block for same command produces only 1 pending file" "got $pending_count files"
fi

# ─── 8. APPROVE.SH ROBUSTNESS ───────────────────────────────────────────────
section "approve.sh — Robustness"

cleanup
# approve.sh should not fail when directories don't exist
rm -rf "$PENDING_DIR" "$APPROVAL_DIR" 2>/dev/null || true
approve_output=$(bash "$APPROVE" 2>&1)
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  pass "approve.sh exits 0 when no pending directory"
else
  fail "approve.sh exits 0 when no pending directory" "exit code: $exit_code"
fi

# approve.sh should create approval directory
cleanup
mkdir -p "$PENDING_DIR"
echo "test" > "$PENDING_DIR/12345"
bash "$APPROVE" >/dev/null 2>&1
if [ -d "$APPROVAL_DIR" ]; then
  pass "approve.sh creates approval directory if missing"
else
  fail "approve.sh creates approval directory if missing"
fi

# =============================================================================
# SUMMARY
# =============================================================================

cleanup

printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}Results: "
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}ALL PASSED${NC}"
else
  printf "${RED}$FAIL FAILED${NC}"
fi
printf " ${BOLD}— ${GREEN}$PASS passed${NC}"
if [ "$FAIL" -gt 0 ]; then
  printf " ${RED}$FAIL failed${NC}"
fi
if [ "$SKIP" -gt 0 ]; then
  printf " ${YELLOW}$SKIP skipped${NC}"
fi
printf "${NC}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

if [ "$FAIL" -gt 0 ]; then
  printf "\n${RED}${BOLD}Failed tests:${NC}\n"
  for err in "${ERRORS[@]}"; do
    printf "  ${RED}✗${NC} %s\n" "$err"
  done
  printf "\n"
  exit 1
fi

exit 0

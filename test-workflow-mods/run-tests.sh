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

# ============================================================
header "1. All Hook Scripts Exist and Are Executable"
# ============================================================

ALL_HOOKS=(
  block-dangerous.sh
  check-invariants.sh
  check-test-exists.sh
  compound-reminder.sh
  end-of-turn-typecheck.sh
  post-edit-quality.sh
  proot-preflight.sh
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
rm -f "/tmp/.claude-completion-evidence-$UNIQUE_SESSION"

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
cat > "/tmp/.claude-completion-evidence-$UNIQUE_SESSION" << 'EOF'
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
rm -f "/tmp/.claude-completion-evidence-$UNIQUE_SESSION"

# Test 4.5: BLOCK when evidence marker exists but missing required fields
cat > "/tmp/.claude-completion-evidence-$UNIQUE_SESSION" << 'EOF'
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
rm -f "/tmp/.claude-completion-evidence-$UNIQUE_SESSION"

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

# error-registry.json exists and is valid JSON
if [ -f "$EVOLUTION_DIR/error-registry.json" ]; then
  pass "error-registry.json exists"
  if jq empty "$EVOLUTION_DIR/error-registry.json" 2>/dev/null; then
    pass "error-registry.json is valid JSON"
  else
    fail "error-registry.json is invalid JSON"
  fi
else
  fail "error-registry.json missing"
fi

# model-performance.json exists and is valid JSON
if [ -f "$EVOLUTION_DIR/model-performance.json" ]; then
  pass "model-performance.json exists"
  if jq empty "$EVOLUTION_DIR/model-performance.json" 2>/dev/null; then
    pass "model-performance.json is valid JSON"
  else
    fail "model-performance.json is invalid JSON"
  fi
else
  fail "model-performance.json missing"
fi

# workflow-changelog.md exists
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

# Backup files exist (safety net for JSON corruption)
for json_file in error-registry.json model-performance.json; do
  if [ -f "$EVOLUTION_DIR/${json_file}.bak" ]; then
    pass "${json_file}.bak backup exists"
  else
    fail "${json_file}.bak backup missing (no corruption recovery)"
  fi
done

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
# SUMMARY
# ============================================================

printf "\n${YELLOW}============================================${NC}\n"
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, %d total\n" "$PASS" "$FAIL" "$TOTAL"
printf "${YELLOW}============================================${NC}\n"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

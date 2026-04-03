#!/usr/bin/env bash
set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 2' ERR

# PreToolUse(Write|Edit) hook: Enforce TDD by blocking production code edits
# when no corresponding test file exists.
#
# Language-universal — supports all major languages via lib/detect-project.sh.
#
# To add a new language: update is_test_file(), find_test_candidates(),
# and has_test_infra() in lib/detect-project.sh.
#
# Exit codes:
#   0 — allow (test exists, or file is not production code)
#   2 — block (production file has no corresponding test)

# Read JSON input from stdin
INPUT=$(cat)

# Extract file_path — try jq first, fall back to bash regex
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
else
  if [[ "$INPUT" =~ \"file_path\":\"(([^\"\\]|\\.)*)\" ]]; then
    FILE_PATH="${BASH_REMATCH[1]}"
    FILE_PATH="${FILE_PATH//\\\"/\"}"
    FILE_PATH="${FILE_PATH//\\\\/\\}"
  else
    exit 0
  fi
fi

if [ -z "${FILE_PATH:-}" ]; then
  exit 0
fi

# Resolve project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Make absolute
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$PROJECT_DIR/$FILE_PATH"
fi

# Source shared detection library
source ~/.claude/hooks/lib/detect-project.sh
source ~/.claude/hooks/lib/hook-logger.sh 2>/dev/null || true

# === SKIP CONDITIONS ===

# Skip non-code files
if ! is_code_file "$FILE_PATH"; then
  exit 0
fi

# Skip files that ARE test files already
if is_test_file "$FILE_PATH"; then
  exit 0
fi

# Skip config, setup, and infrastructure files
if is_config_file "$FILE_PATH"; then
  exit 0
fi

# Skip generated/vendor/build directories
if is_generated_path "$FILE_PATH"; then
  exit 0
fi

# Skip type declaration files (TypeScript)
case "$FILE_PATH" in
  *.d.ts) exit 0 ;;
esac

# Skip pure type/interface files in domain/types directories (no runtime behavior)
case "$FILE_PATH" in
  */domain/types/*.ts|*/domain/types/index.ts) exit 0 ;;
esac

# Skip CSS/style-only files
case "$FILE_PATH" in
  *.css|*.scss|*.less|*.styles.ts|*.styled.ts) exit 0 ;;
esac

# Skip entry points (index.ts, main.rs, __init__.py, etc.) — but only if they're short.
# Entry points with >20 lines likely contain real logic and should have tests.
if is_entry_point "$FILE_PATH"; then
  if [ -f "$FILE_PATH" ]; then
    LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null || echo 0)
    if [ "$LINE_COUNT" -le 20 ]; then
      exit 0
    fi
    # >20 lines: fall through to TDD enforcement
  else
    # File doesn't exist yet — allow creation of entry points
    exit 0
  fi
fi

# Detect the file's language
EXT="${FILE_PATH##*.}"
FILE_LANG=$(lang_for_extension "$EXT")

# Skip if the project has no test infrastructure for this language
if ! has_test_infra "$PROJECT_DIR" "$FILE_LANG"; then
  exit 0
fi

# === TEST FILE DISCOVERY ===

find_test_candidates "$FILE_PATH" "$PROJECT_DIR"

# Check if any test file exists
for candidate in "${TEST_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then
    exit 0  # Test exists — allow the edit
  fi
done

# === RUST SPECIAL CASE: inline tests ===
# Rust commonly uses #[cfg(test)] mod tests { ... } in the same file.
# If the source file exists and contains inline tests, allow the edit.
if [ "$FILE_LANG" = "rust" ] && [ -f "$FILE_PATH" ]; then
  if grep -q '#\[cfg(test)\]' "$FILE_PATH" 2>/dev/null; then
    exit 0
  fi
fi

# === ZIG SPECIAL CASE: inline tests ===
# Zig uses `test "name" { ... }` blocks inline.
if [ "$FILE_LANG" = "zig" ] && [ -f "$FILE_PATH" ]; then
  if grep -q '^test "' "$FILE_PATH" 2>/dev/null; then
    exit 0
  fi
fi

# No test file found — BLOCK
log_hook_event "check-test-exists" "blocked" "$FILE_PATH"
{
  echo "BLOCKED: TDD enforcement — no test file found for production code."
  echo "File: $FILE_PATH"
  echo "Language: ${FILE_LANG:-unknown}"
  echo ""
  echo "Write the test file FIRST (Red step), then edit the production code."
  echo "Expected test file in one of:"
  # Show first 4 candidates
  for candidate in "${TEST_CANDIDATES[@]:0:4}"; do
    echo "  - ${candidate#$PROJECT_DIR/}"
  done
  if [ "$FILE_LANG" = "rust" ]; then
    echo "  - Or add #[cfg(test)] mod tests { ... } inline in the source file"
  fi
  if [ "$FILE_LANG" = "zig" ]; then
    echo "  - Or add test \"name\" { ... } inline in the source file"
  fi
  echo ""
  echo "To skip: this file may need to be added to the skip list in check-test-exists.sh"
} >&2
exit 2

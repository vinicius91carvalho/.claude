#!/usr/bin/env bash
set -euo pipefail

# PreToolUse(Write|Edit) hook: Enforce TDD by blocking production code edits
# when no corresponding test file exists.
#
# Inspired by Jason Vertrees' "check-test-exists.sh" pattern from
# "From Vibe Coding to Agentic Engineering" — promotes TDD from a soft
# instruction to a hard gate. The agent CANNOT skip writing the failing test first.
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

# === SKIP CONDITIONS ===

# Skip non-code files (only enforce for TS/JS/Python/Go source)
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.py|*.go) ;;
  *) exit 0 ;;
esac

# Skip files that ARE test files already
case "$FILE_PATH" in
  *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx)
    exit 0 ;;
  *_test.py|*_test.go)
    exit 0 ;;
  */test_*.py)
    exit 0 ;;
  */__tests__/*)
    exit 0 ;;
  */tests/*|*/test/*)
    exit 0 ;;
esac

# Skip config, setup, and infrastructure files
case "$FILE_PATH" in
  *.config.*|*.setup.*|*vite.config*|*next.config*|*tailwind.config*)
    exit 0 ;;
  */migrations/*|*/seeds/*|*/fixtures/*|*/scripts/*|*/bin/*)
    exit 0 ;;
  *conftest.py|*setup.py|*setup.cfg|*pyproject.toml)
    exit 0 ;;
esac

# Skip generated, build, and vendor directories
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/coverage/*) exit 0 ;;
  */.turbo/*|*/__generated__/*|*/.generated/*|*/generated/*) exit 0 ;;
  */.cache/*|*/.output/*|*/.sst/*|*/.vercel/*) exit 0 ;;
esac

# Skip type declaration files, barrel exports, and entry points
case "$FILE_PATH" in
  *.d.ts) exit 0 ;;
  */index.ts|*/index.tsx|*/index.js|*/index.jsx) exit 0 ;;
  */main.ts|*/main.tsx|*/main.js|*/main.jsx) exit 0 ;;
  */app.ts|*/app.tsx|*/app.js|*/app.jsx) exit 0 ;;
  */__init__.py) exit 0 ;;
esac

# Skip CSS/style-only files (some have .ts extension for CSS-in-JS)
case "$FILE_PATH" in
  *.css|*.scss|*.less|*.styles.ts|*.styled.ts) exit 0 ;;
esac

# Skip documentation and non-logic files
case "$FILE_PATH" in
  *.md|*.txt|*.rst|*.json|*.yaml|*.yml|*.toml|*.env*) exit 0 ;;
  */docs/*|*/documentation/*) exit 0 ;;
  *Dockerfile*|*docker-compose*|*.dockerignore) exit 0 ;;
  *Makefile|*.mk) exit 0 ;;
esac

# Skip if the project has no test infrastructure at all
# (don't block on projects that haven't set up testing yet)
HAS_TEST_INFRA=false
for marker in \
  "$PROJECT_DIR/jest.config"* \
  "$PROJECT_DIR/vitest.config"* \
  "$PROJECT_DIR/pytest.ini" \
  "$PROJECT_DIR/pyproject.toml" \
  "$PROJECT_DIR/setup.cfg" \
  "$PROJECT_DIR/go.mod"; do
  if [ -f "$marker" ] 2>/dev/null; then
    HAS_TEST_INFRA=true
    break
  fi
done

# Also check package.json for test scripts
if [ "$HAS_TEST_INFRA" = false ] && [ -f "$PROJECT_DIR/package.json" ]; then
  if command -v jq &>/dev/null; then
    if jq -e '.scripts.test // .devDependencies.jest // .devDependencies.vitest // .devDependencies.mocha' "$PROJECT_DIR/package.json" &>/dev/null; then
      HAS_TEST_INFRA=true
    fi
  elif grep -q '"test"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_TEST_INFRA=true
  fi
fi

if [ "$HAS_TEST_INFRA" = false ]; then
  exit 0
fi

# === TEST FILE DISCOVERY ===

# Extract file components
DIRNAME=$(dirname "$FILE_PATH")
BASENAME=$(basename "$FILE_PATH")
FILENAME="${BASENAME%.*}"
EXTENSION="${BASENAME##*.}"

# Build list of possible test file locations
TEST_CANDIDATES=()

case "$EXTENSION" in
  ts|tsx|js|jsx)
    # Same directory: foo.test.ts, foo.spec.ts
    TEST_CANDIDATES+=(
      "$DIRNAME/${FILENAME}.test.${EXTENSION}"
      "$DIRNAME/${FILENAME}.spec.${EXTENSION}"
    )
    # For tsx -> test.tsx, for ts -> test.ts
    if [ "$EXTENSION" = "tsx" ]; then
      TEST_CANDIDATES+=("$DIRNAME/${FILENAME}.test.tsx" "$DIRNAME/${FILENAME}.spec.tsx")
    fi
    if [ "$EXTENSION" = "ts" ]; then
      TEST_CANDIDATES+=("$DIRNAME/${FILENAME}.test.ts" "$DIRNAME/${FILENAME}.spec.ts")
    fi
    # __tests__ directory
    TEST_CANDIDATES+=(
      "$DIRNAME/__tests__/${FILENAME}.test.${EXTENSION}"
      "$DIRNAME/__tests__/${FILENAME}.spec.${EXTENSION}"
    )
    # Parent __tests__
    PARENT=$(dirname "$DIRNAME")
    TEST_CANDIDATES+=(
      "$PARENT/__tests__/${FILENAME}.test.${EXTENSION}"
      "$PARENT/__tests__/${FILENAME}.spec.${EXTENSION}"
    )
    # tests/ directory at project root
    # Strip project dir prefix to get relative path
    REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
    REL_DIR=$(dirname "$REL_PATH")
    TEST_CANDIDATES+=(
      "$PROJECT_DIR/tests/${REL_DIR}/${FILENAME}.test.${EXTENSION}"
      "$PROJECT_DIR/test/${REL_DIR}/${FILENAME}.test.${EXTENSION}"
    )
    ;;
  py)
    # Same directory: test_foo.py, foo_test.py
    TEST_CANDIDATES+=(
      "$DIRNAME/test_${FILENAME}.py"
      "$DIRNAME/${FILENAME}_test.py"
    )
    # tests/ directory at project root
    REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
    REL_DIR=$(dirname "$REL_PATH")
    TEST_CANDIDATES+=(
      "$PROJECT_DIR/tests/test_${FILENAME}.py"
      "$PROJECT_DIR/tests/${REL_DIR}/test_${FILENAME}.py"
    )
    ;;
  go)
    # Go: test file is always same directory, same package
    TEST_CANDIDATES+=("$DIRNAME/${FILENAME}_test.go")
    ;;
esac

# Check if any test file exists
for candidate in "${TEST_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then
    exit 0  # Test exists — allow the edit
  fi
done

# No test file found — BLOCK
{
  echo "BLOCKED: TDD enforcement — no test file found for production code."
  echo "File: $FILE_PATH"
  echo ""
  echo "Write the test file FIRST (Red step), then edit the production code."
  echo "Expected test file in one of:"
  # Show first 4 candidates
  for candidate in "${TEST_CANDIDATES[@]:0:4}"; do
    echo "  - ${candidate#$PROJECT_DIR/}"
  done
  echo ""
  echo "To skip: this file may need to be added to the skip list in check-test-exists.sh"
} >&2
exit 2

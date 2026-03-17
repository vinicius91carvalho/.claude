#!/usr/bin/env bash
set -euo pipefail

# PostToolUse(Write|Edit) hook: Verify project invariants after code changes.
#
# Reads INVARIANTS.md from the project root. Each invariant has a machine-verifiable
# shell command. If any invariant is violated after an edit, the agent is notified
# immediately so it can fix the violation before proceeding.
#
# Inspired by Jason Vertrees' "check-invariants.sh" and "Architecture Invariant
# Registry" from "From Vibe Coding to Agentic Engineering" — formal contracts with
# preconditions, postconditions, and invariants (Design by Contract applied to
# cross-module integration seams).
#
# INVARIANTS.md format:
#   ## [Invariant Name]
#   - **Owner:** [bounded context]
#   - **Verify:** `shell command that exits 0 if invariant holds`
#   - **Fix:** [how to fix if violated]
#
# Invariants can also be scoped to directories via INVARIANTS.md files at any level.
# Project-level rules apply everywhere; component-level rules add constraints.
#
# Exit codes:
#   0 — all invariants hold (or no INVARIANTS.md found)
#   2 — one or more invariants violated

# Read JSON input from stdin
INPUT=$(cat)

# Extract file_path
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

# Source shared detection library for is_code_file and is_generated_path
source ~/.claude/hooks/lib/detect-project.sh

# Skip non-code files (invariant checks only matter for source code)
if ! is_code_file "$FILE_PATH"; then
  exit 0
fi

# Skip generated/vendor directories
if is_generated_path "$FILE_PATH"; then
  exit 0
fi

# === COLLECT INVARIANT FILES ===
# Walk from the edited file's directory up to the project root,
# collecting INVARIANTS.md files (component-level + project-level).

INVARIANT_FILES=()

# Project root INVARIANTS.md
if [ -f "$PROJECT_DIR/INVARIANTS.md" ]; then
  INVARIANT_FILES+=("$PROJECT_DIR/INVARIANTS.md")
fi

# Walk up from the file's directory to project root, collecting component-level files
CURRENT_DIR=$(dirname "$FILE_PATH")
while [ "$CURRENT_DIR" != "$PROJECT_DIR" ] && [[ "$CURRENT_DIR" == "$PROJECT_DIR"* ]]; do
  if [ -f "$CURRENT_DIR/INVARIANTS.md" ]; then
    INVARIANT_FILES+=("$CURRENT_DIR/INVARIANTS.md")
  fi
  CURRENT_DIR=$(dirname "$CURRENT_DIR")
done

# No invariant files found — nothing to check
if [ ${#INVARIANT_FILES[@]} -eq 0 ]; then
  exit 0
fi

# === PARSE AND VERIFY ===
# Extract verify commands from INVARIANTS.md files and run them.
# Format: - **Verify:** `command here`

VIOLATIONS=()
CHECKED=0

for INV_FILE in "${INVARIANT_FILES[@]}"; do
  CURRENT_INVARIANT=""

  while IFS= read -r line; do
    # Capture invariant name from ## headings
    if [[ "$line" =~ ^##[[:space:]]+(.+)$ ]]; then
      CURRENT_INVARIANT="${BASH_REMATCH[1]}"
      # Strip trailing formatting
      CURRENT_INVARIANT="${CURRENT_INVARIANT%%[[:space:]]*\{*}"
      CURRENT_INVARIANT=$(echo "$CURRENT_INVARIANT" | sed 's/[*_`]//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      continue
    fi

    # Capture verify commands: - **Verify:** `command`
    if [[ "$line" =~ \*\*Verify:\*\*[[:space:]]*\`(.+)\` ]]; then
      VERIFY_CMD="${BASH_REMATCH[1]}"
      CHECKED=$((CHECKED + 1))

      # Run the verify command in the project directory with a timeout
      if ! (cd "$PROJECT_DIR" && timeout 30 bash -c "$VERIFY_CMD" &>/dev/null); then
        VIOLATIONS+=("${CURRENT_INVARIANT:-Unknown}: ${VERIFY_CMD}")
      fi
    fi
  done < "$INV_FILE"
done

# No verify commands found — nothing actionable
if [ "$CHECKED" -eq 0 ]; then
  exit 0
fi

# Report violations
if [ ${#VIOLATIONS[@]} -gt 0 ]; then
  {
    echo "INVARIANT VIOLATION: ${#VIOLATIONS[@]} of $CHECKED invariants failed after editing $FILE_PATH"
    echo ""
    for v in "${VIOLATIONS[@]}"; do
      echo "  FAIL: $v"
    done
    echo ""
    echo "Fix the violations before continuing. Check INVARIANTS.md for fix instructions."
  } >&2
  exit 2
fi

exit 0

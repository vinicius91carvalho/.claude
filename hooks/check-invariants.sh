#!/usr/bin/env bash
set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 2' ERR

START_NS=$(date +%s%N 2>/dev/null || echo 0)

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
source ~/.claude/hooks/lib/hook-logger.sh 2>/dev/null || true
source ~/.claude/hooks/lib/project-cache.sh 2>/dev/null || true

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

# === CACHE SETUP ===
# Compute project hash for cache key namespacing.
# This ensures different projects don't share cache entries.
_PROJ_HASH=$(project_hash "$PROJECT_DIR" 2>/dev/null || printf '%s' "$PROJECT_DIR" | cksum | cut -d' ' -f1)
_FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo 0)

# === SANDBOX: Command whitelist/blocklist for verify commands ===
# INVARIANTS.md files may come from cloned repos. Restrict what verify commands can run.

SAFE_CMDS="grep|test|jq|wc|diff|cat|find|ls|head|tail|sort|uniq|echo|true|false|\\[|stat|file"
BLOCKED_PATTERNS="curl|wget|nc|ncat|bash|sh|zsh|python|python3|node|ruby|perl|eval|exec|source|\\.|sudo|su|chmod|chown|rm|mv|cp|dd|mkfs|mount|kill|pkill|xargs"

is_safe_verify_cmd() {
  local cmd="$1"
  # Block if command contains any dangerous pattern
  for pattern in ${BLOCKED_PATTERNS//|/ }; do
    # Match as a word boundary (start of command or after pipe/semicolon/&&)
    if [[ "$cmd" =~ (^|[|;&[:space:]])${pattern}([[:space:]]|$) ]]; then
      return 1
    fi
  done
  return 0
}

# === PARSE AND VERIFY ===
# Extract verify commands from INVARIANTS.md files and run them.
# Format: - **Verify:** `command here`

VIOLATIONS=()
CHECKED=0
SKIPPED=0
CACHE_HITS=0

for INV_FILE in "${INVARIANT_FILES[@]}"; do
  CURRENT_INVARIANT=""

  # === CONTENT-HASH CACHING FOR INVARIANTS.md ===
  # Compute hash of this INVARIANTS.md file. If it hasn't changed AND
  # the edited file hasn't changed since last check, we can skip re-running
  # all verify commands for this invariant file.
  INV_FILE_HASH=$(content_hash "$INV_FILE" 2>/dev/null || echo "nohash")
  INV_CACHE_KEY="inv_meta_${_PROJ_HASH}_${INV_FILE_HASH//[^a-zA-Z0-9]/_}"

  # Read cached mtime of the edited file from the last check of this invariant file
  _CACHED_FILE_MTIME=$(cache_get "$INV_CACHE_KEY" 300 2>/dev/null || true)

  # If the INVARIANTS.md hash matches cached state AND the edited file mtime is unchanged,
  # we can skip all verify commands — nothing has changed that would affect the outcome.
  if [ -n "$_CACHED_FILE_MTIME" ] && [ "$_CACHED_FILE_MTIME" = "$_FILE_MTIME" ]; then
    CACHE_HITS=$((CACHE_HITS + 1))
    continue
  fi

  # Cache miss or hash changed — parse and run verify commands for this invariant file
  _INV_RAN_ANY=0

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

      # Sandbox check: skip untrusted commands with a warning
      if ! is_safe_verify_cmd "$VERIFY_CMD"; then
        SKIPPED=$((SKIPPED + 1))
        echo "WARNING: Skipping untrusted invariant verify command: $VERIFY_CMD" >&2
        continue
      fi

      CHECKED=$((CHECKED + 1))
      _INV_RAN_ANY=1

      # Check per-command result cache.
      # Key: inv_cmd_{proj_hash}_{inv_file_hash}_{cmd_hash}_{file_mtime}
      CMD_HASH=$(printf '%s' "$VERIFY_CMD" | cksum | cut -d' ' -f1)
      CMD_CACHE_KEY="inv_cmd_${_PROJ_HASH}_${INV_FILE_HASH//[^a-zA-Z0-9]/_}_${CMD_HASH}_${_FILE_MTIME}"
      CACHED_RESULT=$(cache_get "$CMD_CACHE_KEY" 3600 2>/dev/null || true)

      if [ -n "$CACHED_RESULT" ]; then
        # Cache hit for this verify command
        CACHE_HITS=$((CACHE_HITS + 1))
        if [ "$CACHED_RESULT" = "FAIL" ]; then
          VIOLATIONS+=("${CURRENT_INVARIANT:-Unknown}: ${VERIFY_CMD}")
        fi
        continue
      fi

      # Run the verify command in the project directory with a timeout
      if ! (cd "$PROJECT_DIR" && timeout 30 bash -c "$VERIFY_CMD" &>/dev/null); then
        VIOLATIONS+=("${CURRENT_INVARIANT:-Unknown}: ${VERIFY_CMD}")
        cache_set "$CMD_CACHE_KEY" "FAIL" 2>/dev/null || true
      else
        cache_set "$CMD_CACHE_KEY" "PASS" 2>/dev/null || true
      fi
    fi
  done < "$INV_FILE"

  # Update the invariant-file-level cache with current edited file mtime.
  # Only cache if we actually ran verify commands (no verify cmds = nothing to cache).
  if [ "$_INV_RAN_ANY" -eq 1 ] && [ ${#VIOLATIONS[@]} -eq 0 ]; then
    cache_set "$INV_CACHE_KEY" "$_FILE_MTIME" 2>/dev/null || true
  fi
done

# No verify commands found — nothing actionable
if [ "$CHECKED" -eq 0 ]; then
  exit 0
fi

# Compute elapsed time
END_NS=$(date +%s%N 2>/dev/null || echo 0)
if [ "$START_NS" != "0" ] && [ "$END_NS" != "0" ]; then
  ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
else
  ELAPSED_MS=0
fi

# Report violations
if [ ${#VIOLATIONS[@]} -gt 0 ]; then
  log_hook_event "check-invariants" "violated" "${#VIOLATIONS[@]} of $CHECKED failed (${ELAPSED_MS}ms, ${CACHE_HITS} cached): $FILE_PATH"
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

log_hook_event "check-invariants" "passed" "checked=$CHECKED cached=${CACHE_HITS} elapsed=${ELAPSED_MS}ms: $FILE_PATH"
exit 0

#!/usr/bin/env bash
set -euo pipefail

# Stop hook: BLOCK if task files show completion but compound hasn't run.
#
# Checks:
# 1. Are there completed task/sprint files (progress.json with all "complete")?
# 2. Was /compound run? (approximated by checking if evolution files updated recently)
#
# This is BLOCKING (exit 2). The learning loop is the most important part of
# the system — without it, the workflow never improves.

# Check for jq — required for JSON parsing. Exit silently if missing
# (other hooks will warn about jq; avoid duplicate warnings)
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Read JSON input from stdin
INPUT=$(cat)

# Check stop_hook_active — prevent infinite loop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Resolve project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Skip if no task directory exists
TASK_DIR="$PROJECT_DIR/docs/tasks"
if [ ! -d "$TASK_DIR" ]; then
  exit 0
fi

# Check for any progress.json files with all sprints complete
COMPOUND_NEEDED=false
while IFS= read -r pjson; do
  if [ -f "$pjson" ]; then
    # Check if ALL sprints are complete (none with not_started or in_progress)
    INCOMPLETE=$(jq '[.sprints[] | select(.status != "complete")] | length' "$pjson" 2>/dev/null || echo "0")
    TOTAL=$(jq '.sprints | length' "$pjson" 2>/dev/null || echo "0")
    if [ "$TOTAL" -gt 0 ] && [ "$INCOMPLETE" -eq 0 ]; then
      COMPOUND_NEEDED=true
      break
    fi
  fi
done < <(find "$TASK_DIR" -name "progress.json" -type f 2>/dev/null)

if [ "$COMPOUND_NEEDED" = false ]; then
  exit 0
fi

# Check if compound was run this session.
# Primary: compound writes a marker file when it completes.
# Fallback: check if any evolution file was recently modified.
EVOLUTION_DIR="$HOME/.claude/evolution"
RECENT_UPDATE=false

# Primary check: marker file from compound (written by compound Step 8)
MARKER="/tmp/.claude-compound-done-${CLAUDE_SESSION_ID:-unknown}"
if [ -f "$MARKER" ]; then
  RECENT_UPDATE=true
fi

# Fallback: any evolution file updated in last 30 minutes
if [ "$RECENT_UPDATE" = false ] && [ -d "$EVOLUTION_DIR" ]; then
  RECENT=$(find "$EVOLUTION_DIR" -mmin -30 -type f 2>/dev/null | head -1)
  if [ -n "$RECENT" ]; then
    RECENT_UPDATE=true
  fi
fi

if [ "$RECENT_UPDATE" = false ]; then
  echo "BLOCKED: Completed task detected but /compound hasn't run." >&2
  echo "The learning loop captures errors, model performance, and patterns that prevent future failures." >&2
  echo "Run /compound to capture learnings, or dismiss this to skip (learnings will be lost)." >&2
  exit 2
fi

exit 0

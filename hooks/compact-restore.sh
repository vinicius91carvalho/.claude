#!/usr/bin/env bash
set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 0' ERR

# PostCompact hook: Auto-restore session state after context compaction.
# Outputs the last compact checkpoint so the agent knows where to resume.
# Non-blocking (exit 0) — advisory only.

source "${HOME}/.claude/hooks/lib/hook-logger.sh" 2>/dev/null || true

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Find session-learnings file
SESSION_LEARNINGS=""
for candidate in \
  "$PROJECT_DIR/docs/session-learnings.md" \
  "$PROJECT_DIR/session-learnings.md"; do
  if [ -f "$candidate" ]; then
    SESSION_LEARNINGS="$candidate"
    break
  fi
done

if [ -z "$SESSION_LEARNINGS" ] || [ ! -f "$SESSION_LEARNINGS" ]; then
  exit 0
fi

# Extract last compact checkpoint
LAST_CHECKPOINT=$(awk '/^## Compact Checkpoint/{found=1; buf=""} found{buf=buf"\n"$0} END{if(found) print buf}' "$SESSION_LEARNINGS" 2>/dev/null)

if [ -z "$LAST_CHECKPOINT" ]; then
  exit 0
fi

# Check for pending progress.json files
PENDING_WORK=""
if [ -d "$PROJECT_DIR/docs/tasks" ]; then
  while IFS= read -r pjson; do
    if command -v jq &>/dev/null; then
      PENDING=$(jq -r '.sprints[]? | select(.status != "complete") | .id' "$pjson" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
      if [ -n "$PENDING" ]; then
        PRD=$(jq -r '.prd // "unknown"' "$pjson" 2>/dev/null)
        PENDING_WORK="${PENDING_WORK}\n  - ${PRD}: pending=[${PENDING}]"
      fi
    fi
  done < <(find "$PROJECT_DIR/docs/tasks" -name "progress.json" -type f 2>/dev/null)
fi

# Output restore summary to stderr (visible to agent)
{
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  PostCompact: Session state restored             ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo "$LAST_CHECKPOINT"
  if [ -n "$PENDING_WORK" ]; then
    echo ""
    echo "Pending work:"
    echo -e "$PENDING_WORK"
  fi
  echo ""
  echo "→ Re-read: ${SESSION_LEARNINGS}"
  echo ""
} >&2

log_hook_event "compact-restore" "restored" "checkpoint loaded" 2>/dev/null || true

exit 0

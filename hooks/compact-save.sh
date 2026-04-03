#!/usr/bin/env bash
set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 0' ERR

# PreCompact hook: Auto-save session state before context compaction.
# Replaces the manual "Compact Recovery Protocol" with automated state capture.
# Non-blocking (exit 0) — compaction must never be prevented.

source "${HOME}/.claude/hooks/lib/hook-logger.sh" 2>/dev/null || true

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

# If no session-learnings file exists, create one at the default path
if [ -z "$SESSION_LEARNINGS" ]; then
  SESSION_LEARNINGS="$PROJECT_DIR/docs/session-learnings.md"
  mkdir -p "$(dirname "$SESSION_LEARNINGS")" 2>/dev/null || true
fi

# Find any active progress.json files
ACTIVE_SPRINTS=""
if [ -d "$PROJECT_DIR/docs/tasks" ]; then
  while IFS= read -r pjson; do
    if command -v jq &>/dev/null; then
      IN_PROGRESS=$(jq -r '.sprints[]? | select(.status == "in_progress") | .id' "$pjson" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
      if [ -n "$IN_PROGRESS" ]; then
        ACTIVE_SPRINTS="${ACTIVE_SPRINTS}${pjson}: ${IN_PROGRESS}\n"
      fi
    fi
  done < <(find "$PROJECT_DIR/docs/tasks" -name "progress.json" -type f 2>/dev/null)
fi

# Append compact checkpoint to session-learnings
{
  echo ""
  echo "## Compact Checkpoint — ${TIMESTAMP}"
  echo ""
  echo "- **CWD:** ${PROJECT_DIR}"
  if [ -n "$ACTIVE_SPRINTS" ]; then
    echo "- **Active sprints:**"
    echo -e "$ACTIVE_SPRINTS" | while IFS= read -r line; do
      [ -n "$line" ] && echo "  - $line"
    done
  fi
  echo "- **Action:** Re-read this file after compaction. Resume from last completed phase."
  echo ""
} >> "$SESSION_LEARNINGS" 2>/dev/null || true

log_hook_event "compact-save" "saved" "checkpoint at ${TIMESTAMP}" 2>/dev/null || true

# Output advisory to stderr (visible to agent after compact)
echo "PreCompact: Session state saved to ${SESSION_LEARNINGS}" >&2

exit 0

#!/usr/bin/env bash
set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 0' ERR

# SessionStart hook: Auto-detect environment and load session state.
# Runs when a session begins or resumes.
# Non-blocking (exit 0) — advisory only.

source "${HOME}/.claude/hooks/lib/hook-logger.sh" 2>/dev/null || true

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

WARNINGS=""

# 1. Detect proot-distro environment
IS_PROOT=false
if uname -r 2>/dev/null | grep -q "PRoot-Distro"; then
  IS_PROOT=true
  WARNINGS="${WARNINGS}\n• PRoot-Distro ARM64 detected — expect 3x slower builds, no bwrap sandbox"
fi

# 2. Check for session-learnings file
SESSION_LEARNINGS=""
for candidate in \
  "$PROJECT_DIR/docs/session-learnings.md" \
  "$PROJECT_DIR/session-learnings.md"; do
  if [ -f "$candidate" ]; then
    SESSION_LEARNINGS="$candidate"
    break
  fi
done

# 3. Check for pending work (progress.json with incomplete sprints)
PENDING_WORK=""
if [ -d "$PROJECT_DIR/docs/tasks" ]; then
  while IFS= read -r pjson; do
    if command -v jq &>/dev/null; then
      PENDING=$(jq -r '.sprints[]? | select(.status != "complete") | .id' "$pjson" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
      if [ -n "$PENDING" ]; then
        PRD=$(jq -r '.prd // "unknown"' "$pjson" 2>/dev/null)
        PENDING_WORK="${PENDING_WORK}\n  → ${PRD}: pending=[${PENDING}]"
      fi
    fi
  done < <(find "$PROJECT_DIR/docs/tasks" -name "progress.json" -type f 2>/dev/null)
fi

# 4. Check disk space
DISK_FREE_KB=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$DISK_FREE_KB" ] && [ "$DISK_FREE_KB" -lt 1048576 ]; then
  DISK_FREE_MB=$((DISK_FREE_KB / 1024))
  WARNINGS="${WARNINGS}\n• Low disk: ${DISK_FREE_MB}MB free"
fi

# Only output if there's something useful to report
HAS_OUTPUT=false
if [ -n "$SESSION_LEARNINGS" ] || [ -n "$PENDING_WORK" ] || [ -n "$WARNINGS" ]; then
  HAS_OUTPUT=true
fi

if [ "$HAS_OUTPUT" = "true" ]; then
  {
    echo ""
    echo "┌─ Session Start ─────────────────────────────────┐"
    if [ -n "$WARNINGS" ]; then
      echo -e "$WARNINGS"
    fi
    if [ -n "$SESSION_LEARNINGS" ]; then
      echo "  Session learnings: ${SESSION_LEARNINGS}"
    fi
    if [ -n "$PENDING_WORK" ]; then
      echo "  Pending work:"
      echo -e "$PENDING_WORK"
    fi
    echo "└─────────────────────────────────────────────────┘"
    echo ""
  } >&2
fi

log_hook_event "session-start" "initialized" "proot=${IS_PROOT}" 2>/dev/null || true

exit 0

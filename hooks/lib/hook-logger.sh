#!/usr/bin/env bash
# Shared hook logging utility.
# Source from any hook: source ~/.claude/hooks/lib/hook-logger.sh
#
# Usage:
#   log_hook_event "hook_name" "action" "details"
#   log_hook_event "check-test-exists" "blocked" "no test for src/foo.ts"
#   log_hook_event "block-dangerous" "allowed" "git status"
#
# Logs are stored in ~/.claude/hooks/logs/hook-events.log
# Format: [ISO-8601] hook=<name> action=<action> detail=<detail>

LOG_DIR="${HOME}/.claude/hooks/logs"
LOG_FILE="${LOG_DIR}/hook-events.log"

# Shared error trap for hooks. Source this, then call hook_error_trap.
# Usage: hook_error_trap [exit_code]
#   exit_code=2 (default) → block on crash (safety hooks)
#   exit_code=0 → allow on crash (informational hooks)
hook_error_trap() {
  local exit_code="${1:-2}"
  trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit '"$exit_code" ERR
}

log_hook_event() {
  local hook_name="${1:-unknown}"
  local action="${2:-unknown}"
  local detail="${3:-}"

  # Truncate detail to 120 chars to prevent log bloat
  if [ ${#detail} -gt 120 ]; then
    detail="${detail:0:117}..."
  fi

  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date +%s)"

  # Append to log file (create dir if needed, never fail the hook)
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  echo "[$timestamp] hook=$hook_name action=$action detail=$detail" >> "$LOG_FILE" 2>/dev/null || true

  # Rotate if >5000 lines (keep last 2000)
  if [ -f "$LOG_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt 5000 ]; then
      tail -2000 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
    fi
  fi
}

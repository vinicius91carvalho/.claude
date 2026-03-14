#!/usr/bin/env bash
set -euo pipefail

# PRoot-Distro Environment Detection & Preflight Check
# Runs as a PreToolUse hook on first Bash command per session
# Detects proot-distro ARM64 and warns about known limitations

# Fast detection: skip if not proot-distro ARM64
# Consistent with orchestrator, worktree-preflight, and sprint-executor detection
if ! uname -r 2>/dev/null | grep -q "PRoot-Distro" || [ "$(uname -m)" != "aarch64" ]; then
  exit 0
fi

# Only run preflight once per session (use a marker file, 2-hour expiry)
SESSION_MARKER="/tmp/.claude-proot-preflight-done"

if [ -f "$SESSION_MARKER" ]; then
  MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$SESSION_MARKER" 2>/dev/null || echo 0) ))
  if [ "$MARKER_AGE" -lt 7200 ]; then
    exit 0
  fi
fi

touch "$SESSION_MARKER"

# Resolve project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Collect warnings
WARNINGS=""

# Check disk space
DISK_FREE_KB=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$DISK_FREE_KB" ] && [ "$DISK_FREE_KB" -lt 1048576 ]; then  # < 1GB
  DISK_FREE_MB=$((DISK_FREE_KB / 1024))
  WARNINGS="${WARNINGS}\n⚠ LOW DISK: Only ${DISK_FREE_MB}MB free. Builds may fail."
fi

# Check for broken symlinks in node_modules
if [ -d "$PROJECT_DIR/node_modules/.bin" ]; then
  BROKEN_COUNT=$(find "$PROJECT_DIR/node_modules/.bin" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
  if [ "$BROKEN_COUNT" -gt 0 ]; then
    WARNINGS="${WARNINGS}\n⚠ BROKEN SYMLINKS: $BROKEN_COUNT broken symlinks in node_modules/.bin. Run: pnpm install"
  fi
fi

# Check for stale SST locks
if [ -f "$PROJECT_DIR/.sst/lock" ]; then
  WARNINGS="${WARNINGS}\n⚠ SST LOCK: Stale lock file found at .sst/lock. Remove if no deploy is running."
fi

# Check for .npmrc with node-linker
if [ -f "$PROJECT_DIR/.npmrc" ]; then
  if ! grep -q "node-linker" "$PROJECT_DIR/.npmrc" 2>/dev/null; then
    WARNINGS="${WARNINGS}\nℹ NPMRC: No node-linker setting. Consider adding node-linker=hoisted to .npmrc for proot compatibility."
  fi
fi

# Check NODE_OPTIONS
if [ -z "${NODE_OPTIONS:-}" ]; then
  WARNINGS="${WARNINGS}\nℹ MEMORY: NODE_OPTIONS not set. Consider: export NODE_OPTIONS='--max-old-space-size=2048'"
fi

# Only output if there are warnings
if [ -n "$WARNINGS" ]; then
  echo -e "🔍 PRoot-Distro ARM64 Environment Detected\n${WARNINGS}" >&2
fi

# Always exit 0 — this is informational, not blocking
exit 0

#!/usr/bin/env bash
set -euo pipefail

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed. Run: apt install jq" >&2
  exit 1
fi

# Read JSON input from stdin
INPUT=$(cat)

# Check stop_hook_active — prevent infinite loop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Resolve project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Check for tsconfig.json
if [ ! -f "$PROJECT_DIR/tsconfig.json" ]; then
  exit 0
fi

# Ensure log directory and log file exist (log file needed for -newer comparison)
LOG_DIR="$(eval echo ~)/.claude/hooks/logs"
mkdir -p "$LOG_DIR"
[ -f "$LOG_DIR/typecheck.log" ] || touch "$LOG_DIR/typecheck.log"

# Skip if no code was written this turn (no Write/Edit tool used)
# The hook input contains tool_results from the turn — check for Write/Edit usage
WROTE_CODE=$(echo "$INPUT" | jq -r '
  .transcript // [] | map(select(
    .tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit"
  )) | length
' 2>/dev/null || echo "0")
# If jq parsing fails or returns 0, also check a simpler heuristic:
# look for recent file modifications in the project (last 2 minutes)
if [ "$WROTE_CODE" = "0" ]; then
  RECENT_CHANGES=$(find "$PROJECT_DIR" \( -name "*.ts" -o -name "*.tsx" \) -newer "$LOG_DIR/typecheck.log" 2>/dev/null | head -1)
  if [ -z "$RECENT_CHANGES" ]; then
    exit 0
  fi
fi

# Find the native tsgo binary (not the Node.js shim)
find_tsgo_native() {
  local PROJ="$1"
  local PLATFORM="linux"
  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) return 1 ;;
  esac

  local PKG_NAME="native-preview-${PLATFORM}-${ARCH}"
  # Check direct node_modules path first (fastest)
  local DIRECT="$PROJ/node_modules/@typescript/${PKG_NAME}/lib/tsgo"
  if [ -x "$DIRECT" ]; then
    echo "$DIRECT"
    return 0
  fi
  # Search in pnpm store structure (pnpm uses @scope+pkg@ver in .pnpm dir)
  local SEARCH_DIR="$PROJ/node_modules/.pnpm"
  if [ -d "$SEARCH_DIR" ]; then
    local FOUND
    FOUND=$(find "$SEARCH_DIR" -name "tsgo" -path "*/${PKG_NAME}/lib/tsgo" 2>/dev/null | head -1)
    if [ -n "$FOUND" ] && [ -x "$FOUND" ]; then
      echo "$FOUND"
      return 0
    fi
  fi
  return 1
}

# Ensure proot-distro compatibility: copy lib .d.ts files to /.l2s/ if needed
# (proot translates /proc/self/exe to /.l2s/ paths, Go binaries resolve libs relative to exe)
ensure_proot_tsgo_compat() {
  local TSGO_BIN="$1"
  local LIB_DIR
  LIB_DIR=$(dirname "$TSGO_BIN")

  # Only needed if /.l2s/ exists (proot-distro environment)
  if [ -d "/.l2s" ] && [ -f "$LIB_DIR/lib.d.ts" ]; then
    # Check if lib.d.ts is already there and current
    if [ ! -f "/.l2s/lib.d.ts" ] || [ "$LIB_DIR/lib.d.ts" -nt "/.l2s/lib.d.ts" ]; then
      cp "$LIB_DIR"/lib*.d.ts /.l2s/ 2>/dev/null || true
    fi
  fi
}

# Determine type checker
TOOL_NAME=""
TOOL_CMD=""

# Use cached tsgo path if valid (avoids expensive `find` in proot-distro)
TSGO_CACHE="$LOG_DIR/.tsgo_cache_$(echo "$PROJECT_DIR" | md5sum | cut -d' ' -f1)"
TSGO_NATIVE=""
if [ -f "$TSGO_CACHE" ]; then
  CACHED=$(cat "$TSGO_CACHE")
  if [ -x "$CACHED" ]; then
    TSGO_NATIVE="$CACHED"
  else
    rm -f "$TSGO_CACHE"
  fi
fi
if [ -z "$TSGO_NATIVE" ]; then
  TSGO_NATIVE=$(find_tsgo_native "$PROJECT_DIR" 2>/dev/null) || true
  if [ -n "$TSGO_NATIVE" ]; then
    echo "$TSGO_NATIVE" > "$TSGO_CACHE"
  fi
fi

if [ -n "$TSGO_NATIVE" ]; then
  ensure_proot_tsgo_compat "$TSGO_NATIVE"
  TOOL_NAME="tsgo (native)"
  TOOL_CMD="$TSGO_NATIVE"
elif command -v tsgo &>/dev/null; then
  TOOL_NAME="tsgo (global)"
  TOOL_CMD="tsgo"
else
  TOOL_NAME="tsc"
  TOOL_CMD="pnpm tsc --noEmit --skipLibCheck"
fi

# Run type checker and capture output
START_NS=$(date +%s%N)
TYPECHECK_OUTPUT=""
TYPECHECK_EXIT=0

TYPECHECK_OUTPUT=$(cd "$PROJECT_DIR" && $TOOL_CMD 2>&1) || TYPECHECK_EXIT=$?

# If tsgo crashed (panic, segfault, etc.) rather than reporting type errors, fall back to tsc
if [ "$TOOL_NAME" != "tsc" ] && [ "$TYPECHECK_EXIT" -ne 0 ]; then
  if echo "$TYPECHECK_OUTPUT" | grep -qiE 'panic:|segfault|SIGSEGV|does not exist.*misplaced'; then
    TOOL_NAME="tsc (fallback from tsgo crash)"
    TOOL_CMD="pnpm tsc --noEmit --skipLibCheck"
    TYPECHECK_EXIT=0
    TYPECHECK_OUTPUT=$(cd "$PROJECT_DIR" && $TOOL_CMD 2>&1) || TYPECHECK_EXIT=$?
  fi
fi

END_NS=$(date +%s%N)
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))

# Log result
echo "[$(date -Iseconds)] tool=$TOOL_NAME elapsed=${ELAPSED_MS}ms exit=$TYPECHECK_EXIT" >> "$LOG_DIR/typecheck.log"

# If passed, exit silently
if [ "$TYPECHECK_EXIT" -eq 0 ]; then
  exit 0
fi

# Type check failed — output errors to stderr
TOTAL_LINES=$(echo "$TYPECHECK_OUTPUT" | wc -l)

if [ "$TOTAL_LINES" -le 15 ]; then
  echo "$TYPECHECK_OUTPUT" >&2
else
  REMAINING=$(( TOTAL_LINES - 10 ))
  echo "$TYPECHECK_OUTPUT" | head -n 10 >&2
  echo "... and $REMAINING more errors. Run the type checker to see all." >&2
fi

exit 2

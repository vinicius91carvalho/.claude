#!/usr/bin/env bash
set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 2' ERR

# Stop hook: Run static type checking at end of turn.
#
# Language-universal — auto-detects project type and runs the appropriate
# type checker. Supports TypeScript, Python, Go, Rust, Java, Kotlin, Dart,
# C#, Scala, Haskell, Swift, and Zig out of the box.
#
# To add a new language: update detect_typechecker() and
# code_extensions_for_lang() in lib/detect-project.sh.
#
# Exit codes:
#   0 — type check passed (or skipped)
#   2 — type errors found

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

# Skip if working in home directory (not a real project)
if [ "$PROJECT_DIR" = "$HOME" ] || [ "$PROJECT_DIR" = "/root" ]; then
  exit 0
fi

# Source shared detection library
source ~/.claude/hooks/lib/detect-project.sh

# Detect project languages
detect_project_langs "$PROJECT_DIR"
if [ ${#PROJECT_LANGS[@]} -eq 0 ]; then
  exit 0
fi

# Ensure log directory and log file exist
LOG_DIR="$(eval echo ~)/.claude/hooks/logs"
mkdir -p "$LOG_DIR"
[ -f "$LOG_DIR/typecheck.log" ] || touch "$LOG_DIR/typecheck.log"

# Skip if no code was written this turn
WROTE_CODE=$(echo "$INPUT" | jq -r '
  .transcript // [] | map(select(
    .tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit"
  )) | length
' 2>/dev/null || echo "0")

if [ "$WROTE_CODE" = "0" ]; then
  # Check for recent file modifications as fallback
  RECENT_CHANGES=""
  for lang in "${PROJECT_LANGS[@]}"; do
    EXT_PATTERN=$(code_extensions_for_lang "$lang")
    if [ -n "$EXT_PATTERN" ]; then
      RECENT_CHANGES=$(eval "find '$PROJECT_DIR' \( $EXT_PATTERN \) -newer '$LOG_DIR/typecheck.log'" 2>/dev/null | head -1) || true
      [ -n "$RECENT_CHANGES" ] && break
    fi
  done
  if [ -z "$RECENT_CHANGES" ]; then
    exit 0
  fi
fi

# ─── TYPESCRIPT-SPECIFIC: tsgo native binary detection ─────────────────
# This optimization is TypeScript-only (tsgo is a native Go binary for TS).

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
  local DIRECT="$PROJ/node_modules/@typescript/${PKG_NAME}/lib/tsgo"
  if [ -x "$DIRECT" ]; then
    echo "$DIRECT"
    return 0
  fi
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

ensure_proot_tsgo_compat() {
  local TSGO_BIN="$1"
  local LIB_DIR
  LIB_DIR=$(dirname "$TSGO_BIN")
  if [ -d "/.l2s" ] && [ -f "$LIB_DIR/lib.d.ts" ]; then
    if [ ! -f "/.l2s/lib.d.ts" ] || [ "$LIB_DIR/lib.d.ts" -nt "/.l2s/lib.d.ts" ]; then
      cp "$LIB_DIR"/lib*.d.ts /.l2s/ 2>/dev/null || true
    fi
  fi
}

# ─── RESOLVE TYPE CHECKER ──────────────────────────────────────────────

TOOL_NAME=""
TOOL_CMD=""

for lang in "${PROJECT_LANGS[@]}"; do
  # Skip languages that need installed dependencies when node_modules is missing
  case "$lang" in
    typescript|javascript)
      if ! has_node_deps_installed "$PROJECT_DIR"; then
        echo "⚠ Typecheck skipped: node_modules missing or empty. Run pnpm install." >&2
        exit 0
      fi
      ;;
  esac

  case "$lang" in
    typescript)
      # TypeScript has special tsgo optimization
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
        detect_pkg_manager "$PROJECT_DIR"
        TOOL_NAME="tsc"
        TOOL_CMD="${PKG_MGR:-npx} tsc --noEmit --skipLibCheck"
      fi
      break
      ;;
    *)
      # All other languages use the generic detector
      detect_typechecker "$PROJECT_DIR" "$lang"
      if [ -n "$TYPECHECKER_CMD" ]; then
        TOOL_NAME="$TYPECHECKER_NAME"
        TOOL_CMD="$TYPECHECKER_CMD"
        break
      fi
      ;;
  esac
done

# No type checker found — exit silently
if [ -z "$TOOL_CMD" ]; then
  exit 0
fi

# ─── RUN TYPE CHECKER ──────────────────────────────────────────────────

START_NS=$(date +%s%N)
TYPECHECK_OUTPUT=""
TYPECHECK_EXIT=0

TYPECHECK_OUTPUT=$(cd "$PROJECT_DIR" && eval $TOOL_CMD 2>&1) || TYPECHECK_EXIT=$?

# TypeScript-specific: if tsgo crashed, fall back to tsc
if [[ "$TOOL_NAME" == tsgo* ]] && [ "$TYPECHECK_EXIT" -ne 0 ]; then
  if echo "$TYPECHECK_OUTPUT" | grep -qiE 'panic:|segfault|SIGSEGV|does not exist.*misplaced'; then
    detect_pkg_manager "$PROJECT_DIR"
    TOOL_NAME="tsc (fallback from tsgo crash)"
    TOOL_CMD="${PKG_MGR:-npx} tsc --noEmit --skipLibCheck"
    TYPECHECK_EXIT=0
    TYPECHECK_OUTPUT=$(cd "$PROJECT_DIR" && eval $TOOL_CMD 2>&1) || TYPECHECK_EXIT=$?
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

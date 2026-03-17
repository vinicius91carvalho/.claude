#!/usr/bin/env bash
set -euo pipefail

# Read JSON input and extract command using bash builtins (avoids jq startup cost)
INPUT=$(cat)
# Fast extraction: tool_input.command is always a string value in the hook JSON
# Use parameter expansion to extract between "command":" and the next unescaped quote
if [[ "$INPUT" =~ \"command\":\"(([^\"\\]|\\.)*)\" ]]; then
  COMMAND="${BASH_REMATCH[1]}"
  # Unescape basic JSON escapes
  COMMAND="${COMMAND//\\\"/\"}"
  COMMAND="${COMMAND//\\\\/\\}"
else
  exit 0
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Helper to deny with reason
deny() {
  cat >&2 <<EOJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$1"
  }
}
EOJSON
  exit 2
}

# All pattern checks use bash built-in regex — no subprocesses
# === HARD BLOCKS ===

# Helper: match rm with recursive+force flags in any form
# Matches: rm -rf, rm -fr, rm -r -f, rm -f -r, rm --recursive --force, etc.
is_rm_rf() {
  local cmd="$1"
  # Combined flags: -rf, -fr, -rfi, etc.
  if [[ "$cmd" =~ rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*) ]]; then
    return 0
  fi
  # Separated flags: -r -f, -r ... -f, --recursive -f, -r --force, etc.
  if [[ "$cmd" =~ rm[[:space:]] ]] && \
     [[ "$cmd" =~ (-r[[:space:]]|--recursive) ]] && \
     [[ "$cmd" =~ (-f[[:space:]]|-f$|--force) ]]; then
    return 0
  fi
  return 1
}

# Root filesystem and wildcard
if is_rm_rf "$COMMAND" && [[ "$COMMAND" =~ [[:space:]]/[[:space:]]*$ ]]; then
  deny "BLOCKED: rm -rf / — catastrophic system deletion"
fi

if is_rm_rf "$COMMAND" && [[ "$COMMAND" =~ [[:space:]]/\* ]]; then
  deny "BLOCKED: rm -rf /* — catastrophic system deletion"
fi

# Home directory variants
if is_rm_rf "$COMMAND" && [[ "$COMMAND" =~ [[:space:]]~[[:space:]]*$ ]]; then
  deny "BLOCKED: rm -rf ~ — home directory deletion"
fi

if is_rm_rf "$COMMAND" && [[ "$COMMAND" =~ [[:space:]]\$HOME ]]; then
  deny "BLOCKED: rm -rf \$HOME — home directory deletion"
fi

# Current directory in dangerous locations
if is_rm_rf "$COMMAND" && [[ "$COMMAND" =~ [[:space:]]\.[[:space:]]*$ ]]; then
  CWD="${PWD:-$(pwd)}"
  HOME_DIR="$(eval echo ~)"
  if [ "$CWD" = "/" ] || [ "$CWD" = "$HOME_DIR" ]; then
    deny "BLOCKED: rm -rf . in $CWD — dangerous directory deletion"
  fi
fi

# Critical system directories — HARD block regardless of flag form
if is_rm_rf "$COMMAND" && [[ "$COMMAND" =~ [[:space:]]/(etc|usr|var|bin|sbin|lib|lib64|opt|root|home|boot|sys|proc|dev|srv|mnt)([[:space:]]|/|$) ]]; then
  deny "BLOCKED: rm -rf on system directory — catastrophic deletion"
fi

if [[ "$COMMAND" =~ chmod[[:space:]]+(-R|--recursive)[[:space:]]+777[[:space:]]+/(|[[:space:]]|usr|etc|var|bin|sbin|lib|opt|root) ]]; then
  deny "BLOCKED: chmod -R 777 on system path — security risk"
fi

if [[ "$COMMAND" =~ [[:space:]]dd[[:space:]]+if=|^dd[[:space:]]+if= ]]; then
  deny "BLOCKED: dd command — raw disk operation"
fi

if [[ "$COMMAND" =~ :\(\)\{.*:\|: ]]; then
  deny "BLOCKED: fork bomb detected"
fi

# === SOFT BLOCKS: Destructive git ===

if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]].*(-f[[:space:]]|-f$|--force[[:space:]]|--force$|--force-with-lease) ]]; then
  deny "SOFT BLOCK: git force push detected — may overwrite remote history. Re-approve if intentional."
fi

# Match "git push ... main/master" with any number of flags/options before the branch name
# Catches: git push origin main, git push -u origin main, git push --set-upstream origin main
if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]] ]] && [[ "$COMMAND" =~ [[:space:]](main|master)([[:space:]]|$) ]]; then
  deny "SOFT BLOCK: git push to main/master — use a PR instead. Re-approve if intentional."
fi

if [[ "$COMMAND" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  deny "SOFT BLOCK: git reset --hard — may discard uncommitted work. Re-approve if intentional."
fi

if [[ "$COMMAND" =~ git[[:space:]]+checkout[[:space:]]+\.[[:space:]]*$ ]]; then
  deny "SOFT BLOCK: git checkout . — discards all unstaged changes. Re-approve if intentional."
fi

if [[ "$COMMAND" =~ git[[:space:]]+restore[[:space:]]+\.[[:space:]]*$ ]]; then
  deny "SOFT BLOCK: git restore . — discards all unstaged changes. Re-approve if intentional."
fi

if [[ "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D ]]; then
  deny "SOFT BLOCK: git branch -D — force-deletes branch. Re-approve if intentional."
fi

if [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then
  deny "SOFT BLOCK: git clean -f — removes untracked files. Re-approve if intentional."
fi

if [[ "$COMMAND" =~ git[[:space:]]+stash[[:space:]]+(drop|clear) ]]; then
  deny "SOFT BLOCK: git stash drop/clear — permanently discards stashed changes. Re-approve if intentional."
fi

# === SOFT BLOCKS: Package manager enforcement ===
# Only block npm/npx if the project explicitly uses pnpm (detected by lockfile).
# This prevents forcing pnpm on projects that use npm, yarn, or bun.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD:-$(pwd)}}"
if [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] || [ -f "$PROJECT_DIR/pnpm-workspace.yaml" ]; then
  if [[ "$COMMAND" =~ (^|[[:space:]])npm[[:space:]]+(install|run|exec|start|test|build|ci|init)([[:space:]]|$) ]]; then
    deny "SOFT BLOCK: npm detected — this project uses pnpm (pnpm-lock.yaml found). Use pnpm instead."
  fi

  if [[ "$COMMAND" =~ (^|[[:space:]])npx[[:space:]]+ ]]; then
    deny "SOFT BLOCK: npx detected — this project uses pnpm (pnpm-lock.yaml found). Use pnpm dlx instead."
  fi
fi

# All checks passed
exit 0

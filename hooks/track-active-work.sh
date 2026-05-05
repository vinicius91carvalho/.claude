#!/usr/bin/env bash
# track-active-work.sh — record running agents and test/build commands so the
# statusline can show them as live indicators.
#
# Wired in settings.json on PreToolUse (write entry) and PostToolUse (remove entry)
# for matchers `Agent` and `Bash`. For Bash, only test/build/lint/typecheck commands
# are tracked — everything else is ignored.
#
# State directory: ~/.claude/state/active/
# File names:
#   agent-<id>.json   — one per running Agent invocation
#   bash-<id>.json    — one per running test/build/lint Bash command
#
# Stale files (>2h old) are pruned by the statusline at render time.
# Always exits 0 — never blocks tool execution.

set +e
trap 'exit 0' ERR

INPUT=$(cat)

ACTIVE_DIR="$HOME/.claude/state/active"
mkdir -p "$ACTIVE_DIR" 2>/dev/null || exit 0

HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
TOOL_USE_ID=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // ""' 2>/dev/null)

[ -z "$HOOK_EVENT" ] && exit 0
[ -z "$TOOL_NAME" ] && exit 0

# Stable id: prefer tool_use_id from Claude Code, fall back to a hash of tool_input
# (the same call hashes the same in PreToolUse and PostToolUse).
if [ -n "$TOOL_USE_ID" ]; then
  ID="$TOOL_USE_ID"
else
  ID=$(printf '%s' "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null | md5sum 2>/dev/null | awk '{print $1}' | head -c 16)
fi
[ -z "$ID" ] && exit 0

# Sanitize id for filesystem (alphanumerics + dashes only)
ID=$(printf '%s' "$ID" | tr -c 'a-zA-Z0-9_-' '_' | head -c 32)

NOW=$(date +%s)
SESSION_ID="${CLAUDE_SESSION_ID:-}"

case "$TOOL_NAME:$HOOK_EVENT" in
  Agent:PreToolUse)
    SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // "general-purpose"' 2>/dev/null)
    DESC=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null | head -c 80)
    BG=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
    jq -nc \
      --arg kind "agent" \
      --arg id "$ID" \
      --arg name "$SUBAGENT" \
      --arg description "$DESC" \
      --argjson started_at "$NOW" \
      --arg background "$BG" \
      --arg session_id "$SESSION_ID" \
      '{kind:$kind,id:$id,name:$name,description:$description,started_at:$started_at,background:$background,session_id:$session_id}' \
      > "$ACTIVE_DIR/agent-$ID.json" 2>/dev/null
    ;;
  Agent:PostToolUse)
    rm -f "$ACTIVE_DIR/agent-$ID.json" 2>/dev/null
    ;;
  Bash:PreToolUse)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    [ -z "$CMD" ] && exit 0
    # Only track recognised test/build/lint/typecheck/dev-server commands.
    # Pattern is intentionally broad — false positives are harmless (file gets
    # cleaned up by PostToolUse), false negatives are silent (no statusline entry).
    if printf '%s' "$CMD" | grep -qE '\b(pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(test|test:run|test:e2e|test:unit|test:int|test:integration|build|lint|check|typecheck|tsc|biome|format)\b|\b(pytest|jest|vitest|mocha|playwright[[:space:]]+test|cargo[[:space:]]+(test|build|check|clippy)|go[[:space:]]+test|tsc(\b|$)|biome[[:space:]]+(check|ci)|eslint|prettier[[:space:]]+--check|mintlify[[:space:]]+(broken-links|build)|mint[[:space:]]+(broken-links|build)|nx[[:space:]]+(test|build|lint)|turbo[[:space:]]+(test|build|lint)|rspec|rails[[:space:]]+test|phpunit)\b'; then
      DESC=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null | head -c 80)
      BG=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
      # Short label: first 3 tokens of the command (e.g. "pnpm test:run")
      LABEL=$(printf '%s' "$CMD" | awk '{ for(i=1;i<=3 && i<=NF;i++) printf "%s%s", $i, (i<3 && i<NF?" ":"") }')
      jq -nc \
        --arg kind "bash" \
        --arg id "$ID" \
        --arg label "$LABEL" \
        --arg command "$CMD" \
        --arg description "$DESC" \
        --argjson started_at "$NOW" \
        --arg background "$BG" \
        --arg session_id "$SESSION_ID" \
        '{kind:$kind,id:$id,label:$label,command:$command,description:$description,started_at:$started_at,background:$background,session_id:$session_id}' \
        > "$ACTIVE_DIR/bash-$ID.json" 2>/dev/null
    fi
    ;;
  Bash:PostToolUse)
    # PostToolUse for backgrounded Bash fires immediately when the command launches,
    # not when it finishes — so the entry disappears as soon as the call returns.
    # That's a known limitation of the foreground/background hook contract.
    rm -f "$ACTIVE_DIR/bash-$ID.json" 2>/dev/null
    ;;
esac

exit 0

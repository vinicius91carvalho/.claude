#!/usr/bin/env bash
set +e
trap 'exit 0' ERR

# PostToolUse(ExitPlanMode) hook: relocate the plan markdown that Claude Code
# writes under ~/.claude/plans/<slug>.md into the project where claude was
# launched, so plan artifacts live with the repo they describe instead of
# accumulating in the user's global directory.
#
# Destination: <project>/docs/plans/<slug>.md
# Project root resolution:
#   1. CLAUDE_PROJECT_DIR if set
#   2. `git rev-parse --show-toplevel` from $PWD
#   3. $PWD itself (final fallback — never give up; user asked for project-local)
#
# Fail-open: any error exits 0 silently. Never blocks the tool call.
#
# What we don't do:
#   - Rewrite the plan content
#   - Delete the source file if the destination move fails
#   - Move plans for tools other than ExitPlanMode
#
# Edge cases handled:
#   - ExitPlanMode with empty plan / cancelled plan → no file appears, hook
#     finds nothing recent, exits cleanly.
#   - Multiple plans within the same second → take the newest by mtime.
#   - Project dir is read-only / docs/plans/ can't be created → fail-open.

INPUT=$(cat)

if ! command -v jq &>/dev/null; then exit 0; fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "ExitPlanMode" ] || exit 0

PLANS_DIR="$HOME/.claude/plans"
[ -d "$PLANS_DIR" ] || exit 0

# Pick the most-recently-modified .md in the plans dir, but only if it was
# touched in the last 60 seconds — anything older is from a previous turn.
RECENT_PLAN=""
NOW=$(date +%s)
while IFS= read -r -d '' f; do
  mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  age=$(( NOW - mtime ))
  if [ "$age" -le 60 ]; then
    RECENT_PLAN="$f"
    break
  fi
done < <(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' -printf '%T@ %p\0' 2>/dev/null \
         | sort -rzn \
         | sed -z 's/^[^ ]* //')

[ -n "$RECENT_PLAN" ] || exit 0
[ -f "$RECENT_PLAN" ] || exit 0

# Resolve project root.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$PWD"
fi
[ -d "$PROJECT_DIR" ] || exit 0

DEST_DIR="$PROJECT_DIR/docs/plans"
mkdir -p "$DEST_DIR" 2>/dev/null || exit 0

BASENAME=$(basename "$RECENT_PLAN")
DEST="$DEST_DIR/$BASENAME"

# If a file with the same name already exists at the destination (rare but
# possible: same plan slug regenerated), keep both with a timestamp suffix.
if [ -e "$DEST" ]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  DEST="$DEST_DIR/${BASENAME%.md}-$STAMP.md"
fi

mv -f "$RECENT_PLAN" "$DEST" 2>/dev/null || exit 0

# Append a brief breadcrumb in the original location so a stale reference like
# "plan exists at ~/.claude/plans/foo.md" still resolves to a useful pointer.
# Tiny stub, no plan content — just a forwarding note. Caller (Claude) won't
# usually read this, but it's harmless and aids manual debugging.
printf 'moved to: %s\n' "$DEST" > "${RECENT_PLAN}.moved" 2>/dev/null || true

# Tell the model where the plan now lives. PostToolUse stderr is surfaced to
# the agent context, so the next turn knows the canonical location.
printf 'plan relocated: %s\n' "$DEST" >&2

exit 0

#!/usr/bin/env bash
set -euo pipefail

# Approves all pending soft-blocked hook operations.
# Usage: ! ~/.claude/hooks/approve.sh
#
# After approving, retry the blocked command — the hook will find the
# approval token and allow it (valid for 5 minutes).

PENDING_DIR="$HOME/.claude/hooks/.pending"
APPROVAL_DIR="$HOME/.claude/hooks/.approvals"
mkdir -p "$APPROVAL_DIR" 2>/dev/null || true

if [ ! -d "$PENDING_DIR" ] || [ -z "$(ls -A "$PENDING_DIR" 2>/dev/null)" ]; then
  echo "No pending approvals."
  exit 0
fi

count=0
for f in "$PENDING_DIR"/*; do
  [ -f "$f" ] || continue
  echo "Approving:"
  cat "$f"
  mv "$f" "$APPROVAL_DIR/$(basename "$f")"
  count=$((count + 1))
  echo "---"
done

echo ""
echo "✓ $count operation(s) approved. Retry the command now."

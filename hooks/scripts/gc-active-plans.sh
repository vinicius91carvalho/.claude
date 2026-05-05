#!/usr/bin/env bash
# gc-active-plans.sh
#
# Garbage-collect stale active-plan pointer files. A pointer is collectible
# only when ALL of the following hold:
#   • last_seen_at is older than 24h
#   • no live ~/.claude/state/active/agent-*.json entry has matching session_id
#   • no .stop-hooks-ok-<sid> or .sprint-finalized-<sid> newer than 24h
#
# NEVER deletes the PRD directory itself — only the pointer file. The plan
# remains adoptable via /adopt-plan.

set -euo pipefail

STATE_DIR="$HOME/.claude/state"
ACTIVE_DIR="$STATE_DIR/active"

[ -d "$STATE_DIR" ] || exit 0
shopt -s nullglob

NOW_EPOCH="$(date -u +%s)"
STALE_AFTER_S=$(( 24 * 3600 ))

deleted=0
for pointer in "$STATE_DIR"/active-plan-*.json; do
  [ -f "$pointer" ] || continue

  sid_file="$(basename "$pointer" .json)"
  sid="${sid_file#active-plan-}"
  [ -n "$sid" ] || continue

  if command -v jq >/dev/null 2>&1; then
    last_seen="$(jq -r '.last_seen_at // empty' "$pointer" 2>/dev/null || true)"
  else
    last_seen=""
  fi
  last_epoch=0
  if [ -n "$last_seen" ]; then
    last_epoch="$(date -u -d "$last_seen" +%s 2>/dev/null || stat -c %Y "$pointer" 2>/dev/null || echo 0)"
  else
    last_epoch="$(stat -c %Y "$pointer" 2>/dev/null || echo 0)"
  fi
  age=$(( NOW_EPOCH - last_epoch ))
  [ "$age" -gt "$STALE_AFTER_S" ] || continue

  live=0
  if [ -d "$ACTIVE_DIR" ]; then
    for agent_json in "$ACTIVE_DIR"/agent-*.json; do
      [ -f "$agent_json" ] || continue
      if command -v jq >/dev/null 2>&1; then
        a_sid="$(jq -r '.session_id // empty' "$agent_json" 2>/dev/null || true)"
      else
        a_sid="$(grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$agent_json" | head -1 | sed -E 's/.*"([^"]*)"$/\1/' || true)"
      fi
      if [ "$a_sid" = "$sid" ]; then
        live=1
        break
      fi
    done
  fi
  [ "$live" -eq 0 ] || continue

  recent_marker=0
  for marker in "$STATE_DIR/.stop-hooks-ok-$sid" "$STATE_DIR/.sprint-finalized-$sid"; do
    [ -f "$marker" ] || continue
    m_epoch="$(stat -c %Y "$marker" 2>/dev/null || echo 0)"
    if [ $(( NOW_EPOCH - m_epoch )) -lt "$STALE_AFTER_S" ]; then
      recent_marker=1
      break
    fi
  done
  [ "$recent_marker" -eq 0 ] || continue

  rm -f "$pointer"
  deleted=$(( deleted + 1 ))
done

if [ "$deleted" -gt 0 ]; then
  echo "gc-active-plans: removed $deleted stale pointer(s)"
fi

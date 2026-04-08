#!/usr/bin/env bash
# Claude Code statusLine — compact multi-line dashboard.
# Reads the statusLine JSON from stdin and renders a 3-5 line status block.
#
# Layout:
#   model   <name>  ·  $cost  ·  <duration>  ·  +added -removed
#   dir     <path>  [·  worktree <name> [branch]]
#   ctx     [███░░░░]  42%   84k / 200k
#   5h      [███░]  30% (2h14m)     │     7d   [██░]  15% (4d2h)
#   agent   <name> (<type>)  @ <model>               (only when running as subagent)

input=$(cat)

# ── colours ────────────────────────────────────────────────────────────────
R=$'\033[0;31m'   # red
G=$'\033[0;32m'   # green
Y=$'\033[0;33m'   # yellow
B=$'\033[0;34m'   # blue
M=$'\033[0;35m'   # magenta
C=$'\033[0;36m'   # cyan
W=$'\033[0;37m'   # white/light
D=$'\033[2m'      # dim
N=$'\033[0m'      # reset

# ── extract fields ─────────────────────────────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
model_id=$(echo "$input"   | jq -r '.model.id // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // ""')
[ -z "$project_dir" ] && project_dir=$(pwd)

# cost / timing (cost.* keys, all optional)
cost_usd=$(echo "$input"      | jq -r '.cost.total_cost_usd      // empty')
duration_ms=$(echo "$input"   | jq -r '.cost.total_duration_ms   // empty')
lines_added=$(echo "$input"   | jq -r '.cost.total_lines_added   // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# context window — current_usage.input_tokens matches used_percentage's numerator
cur_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
ctx_size=$(echo "$input"   | jq -r '.context_window.context_window_size // 200000')
used_pct=$(echo "$input"   | jq -r '.context_window.used_percentage // empty')
exceeds_200k=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')
[ -z "$cur_tokens" ] && cur_tokens=0
[ -z "$ctx_size" ]   && ctx_size=200000

# rate limits (Pro/Max only, appear after first API response)
five_pct=$(echo "$input"    | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at       // empty')
week_pct=$(echo "$input"    | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at       // empty')

# agent / worktree (only present in specific contexts)
agent_name=$(echo "$input"      | jq -r '.agent.name       // empty')
agent_type=$(echo "$input"      | jq -r '.agent.type       // empty')
worktree=$(echo "$input"        | jq -r '.worktree.name    // empty')
worktree_branch=$(echo "$input" | jq -r '.worktree.branch  // empty')

# ── helpers ────────────────────────────────────────────────────────────────

# progress_bar <pct 0-100> <width> <fill_color>
progress_bar() {
  local pct="$1" width="${2:-20}" fc="${3:-$G}"
  [ -z "$pct" ] && pct=0
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  local empty=$(( width - filled )) i
  printf "%s" "$fc"
  i=0; while [ $i -lt $filled ]; do printf '█'; i=$(( i + 1 )); done
  printf "%s" "$D"
  i=0; while [ $i -lt $empty ];  do printf '░'; i=$(( i + 1 )); done
  printf "%s" "$N"
}

# bar_color <pct>  →  echoes G / Y / R
bar_color() {
  local n
  n=$(printf "%.0f" "$1" 2>/dev/null || echo 0)
  if   [ "$n" -ge 80 ]; then printf '%s' "$R"
  elif [ "$n" -ge 60 ]; then printf '%s' "$Y"
  else                        printf '%s' "$G"
  fi
}

# fmt_tokens 30000 → 30k ; 1500000 → 1.5M
fmt_tokens() {
  local t="$1"
  [ -z "$t" ] && t=0
  if [ "$t" -ge 1000000 ] 2>/dev/null; then
    awk -v n="$t" 'BEGIN{printf "%.1fM", n/1000000}'
  elif [ "$t" -ge 1000 ] 2>/dev/null; then
    awk -v n="$t" 'BEGIN{printf "%.0fk", n/1000}'
  else
    printf "%s" "$t"
  fi
}

# fmt_duration <ms> → "2h14m" / "42m" / "18s"
fmt_duration() {
  local ms="$1"
  [ -z "$ms" ] && { printf '0s'; return; }
  local s=$(( ms / 1000 ))
  local h=$(( s / 3600 ))
  local m=$(( (s % 3600) / 60 ))
  if   [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else                      printf '%ds' "$s"
  fi
}

# fmt_resets <unix-epoch-seconds> → "2h14m" / "4d2h" / "now"
fmt_resets() {
  local at="$1"
  [ -z "$at" ] && return
  local now
  now=$(date +%s 2>/dev/null || echo 0)
  local diff=$(( at - now ))
  [ "$diff" -le 0 ] && { printf 'now'; return; }
  local m=$(( diff / 60 ))
  local h=$(( m / 60 ))
  local d=$(( h / 24 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" $(( h % 24 ))
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" $(( m % 60 ))
  else                      printf '%dm'   "$m"
  fi
}

# fmt_cost 0.4234 → "$0.42"
fmt_cost() {
  local c="$1"
  [ -z "$c" ] && { printf '$0.00'; return; }
  awk -v n="$c" 'BEGIN{printf "$%.2f", n}'
}

# ── line 1: model · cost · duration · diff ─────────────────────────────────
printf '%smodel%s %s%s%s' "$C" "$N" "$W" "$model_name" "$N"
if [ -n "$cost_usd" ]; then
  printf '  %s·%s  %s%s%s' "$D" "$N" "$G" "$(fmt_cost "$cost_usd")" "$N"
fi
if [ -n "$duration_ms" ]; then
  printf '  %s·%s  %s%s%s' "$D" "$N" "$W" "$(fmt_duration "$duration_ms")" "$N"
fi
if [ "$lines_added" -gt 0 ] 2>/dev/null || [ "$lines_removed" -gt 0 ] 2>/dev/null; then
  printf '  %s·%s  %s+%s%s %s-%s%s' "$D" "$N" "$G" "$lines_added" "$N" "$R" "$lines_removed" "$N"
fi
printf '\n'

# ── line 2: project dir [· worktree] ───────────────────────────────────────
printf '%sdir  %s %s%s%s' "$C" "$N" "$W" "$project_dir" "$N"
if [ -n "$worktree" ]; then
  printf '  %s·%s  %swt%s %s%s%s' "$D" "$N" "$Y" "$N" "$W" "$worktree" "$N"
  [ -n "$worktree_branch" ] && printf ' %s[%s]%s' "$D" "$worktree_branch" "$N"
fi
printf '\n'

# ── line 3: context window ─────────────────────────────────────────────────
if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
  bc_col=$(bar_color "$used_int")
  printf '%sctx  %s ' "$C" "$N"
  progress_bar "$used_int" 22 "$bc_col"
  printf '  %s%d%%%s  %s%s / %s%s' \
    "$W" "$used_int" "$N" \
    "$D" "$(fmt_tokens "$cur_tokens")" "$(fmt_tokens "$ctx_size")" "$N"
  [ "$exceeds_200k" = "true" ] && printf '  %s!>200k%s' "$R" "$N"
  printf '\n'
fi

# ── line 4: 5h + 7d rate limits (only shown when data is present) ──────────
if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
  # 5-hour block
  if [ -n "$five_pct" ]; then
    five_int=$(printf "%.0f" "$five_pct" 2>/dev/null || echo 0)
    five_col=$(bar_color "$five_int")
    printf '%s5h   %s ' "$C" "$N"
    progress_bar "$five_int" 10 "$five_col"
    printf '  %s%d%%%s' "$W" "$five_int" "$N"
    [ -n "$five_resets" ] && printf ' %s(%s)%s' "$D" "$(fmt_resets "$five_resets")" "$N"
  else
    printf '%s5h    —%s' "$D" "$N"
  fi

  printf '     %s│%s     ' "$D" "$N"

  # 7-day block
  if [ -n "$week_pct" ]; then
    week_int=$(printf "%.0f" "$week_pct" 2>/dev/null || echo 0)
    week_col=$(bar_color "$week_int")
    printf '%s7d%s   ' "$C" "$N"
    progress_bar "$week_int" 10 "$week_col"
    printf '  %s%d%%%s' "$W" "$week_int" "$N"
    [ -n "$week_resets" ] && printf ' %s(%s)%s' "$D" "$(fmt_resets "$week_resets")" "$N"
  else
    printf '%s7d    —%s' "$D" "$N"
  fi
  printf '\n'
fi

# ── line 5: subagent context (only when running as a subagent) ─────────────
if [ -n "$agent_name" ]; then
  printf '%sagent%s %s%s%s' "$M" "$N" "$W" "$agent_name" "$N"
  [ -n "$agent_type" ] && printf ' %s(%s)%s' "$D" "$agent_type" "$N"
  [ -n "$model_id" ]   && printf '  %s@%s %s%s%s' "$D" "$N" "$W" "$model_id" "$N"
  printf '\n'
fi

# statusLine MUST exit 0 — otherwise Claude Code suppresses the line
exit 0

#!/usr/bin/env bash
# Claude Code statusLine — compact multi-line dashboard.
# Reads the statusLine JSON from stdin and renders a 3-6 line status block.
#
# Layout:
#   model   <name>  ·  $cost  ·  <duration>  ·  +added -removed  [· effort]  [· vim]
#   dir     <path>  [·  worktree <name> [branch]]
#   ctx     [███░░░░]  42%   84k / 200k
#   5h      [███░]  30% (2h14m)     │     7d   [██░]  15% (4d2h)  (only shown for subscribers with active limits)
#   plan    <prd-name>  [·  sprint N/M  ·  <status>]  (only shown when a progress.json is found nearby)
#   work    agents N (names...)  [·  task N (commands...)]  (only shown when ~/.claude/state/active/ has entries)

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
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
[ -z "$cwd" ] && cwd="$project_dir"

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

# worktree (only present in worktree sessions)
worktree=$(echo "$input"        | jq -r '.worktree.name    // empty')
worktree_branch=$(echo "$input" | jq -r '.worktree.branch  // empty')

# effort + vim mode (optional)
effort_level=$(echo "$input"  | jq -r '.effort.level // empty')
vim_mode=$(echo "$input"      | jq -r '.vim.mode     // empty')

# agent info (optional)
agent_name=$(echo "$input"    | jq -r '.agent.name   // empty')

# session name (optional)
session_name=$(echo "$input"  | jq -r '.session_name // empty')

# ── plan/sprint discovery (per-session via active-plan pointer) ──────────
# Strict order:
#   1. ~/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json (pointer for THIS session)
#   2. fallback: scan docs/tasks for progress.json files
# This makes the plan line per-terminal — switching tmux panes flips the plan.
plan_prd=""
plan_total=0
plan_complete=0
plan_in_progress=0
plan_blocked=0

# Read this session's pointer if it exists.
_session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$_session_id" ] && _session_id="${CLAUDE_SESSION_ID:-}"

_pointer_progress_json() {
  [ -z "$_session_id" ] && return
  local ptr="$HOME/.claude/state/active-plan-${_session_id}.json"
  [ -f "$ptr" ] || return
  local prd_dir
  prd_dir=$(jq -r '.prd_dir // empty' "$ptr" 2>/dev/null)
  [ -z "$prd_dir" ] || [ "$prd_dir" = "null" ] && return
  [ -f "$prd_dir/progress.json" ] && echo "$prd_dir/progress.json"
}

# Try to find a progress.json near the cwd by searching docs/tasks tree
# Use a fast glob limited to 3 levels deep to avoid slowness.
_find_progress_json() {
  local base="$1"
  # Prefer the git root's docs/tasks tree if available
  local git_root
  git_root=$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || echo "")
  local search_root="${git_root:-$base}"
  # Find the most recently modified progress.json in docs/tasks (fast, bounded depth)
  if [ -d "$search_root/docs/tasks" ]; then
    find "$search_root/docs/tasks" -maxdepth 5 -name "progress.json" -not -path "*/node_modules/*" \
      2>/dev/null | head -5
  fi
}

_parse_progress_json() {
  local f="$1"
  [ -f "$f" ] || return
  local prd total complete in_progress blocked
  prd=$(jq -r '.prd // "spec.md"' "$f" 2>/dev/null || echo "")
  total=$(jq '.sprints | length' "$f" 2>/dev/null || echo "0")
  complete=$(jq '[.sprints[]? | select(.status == "complete")] | length' "$f" 2>/dev/null || echo "0")
  in_progress=$(jq '[.sprints[]? | select(.status == "in_progress")] | length' "$f" 2>/dev/null || echo "0")
  blocked=$(jq '[.sprints[]? | select(.status == "blocked")] | length' "$f" 2>/dev/null || echo "0")
  # derive a human-readable PRD name from the parent directory
  local prd_dir
  prd_dir=$(dirname "$f")
  prd=$(basename "$prd_dir")
  # strip YYYY-MM-DD_HHmm- prefix if present
  prd=$(echo "$prd" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{4\}-//')
  echo "$prd|$total|$complete|$in_progress|$blocked"
}

if command -v jq &>/dev/null && command -v git &>/dev/null; then
  # Pointer first — guarantees per-session plan even when multiple PRDs coexist.
  _pointer_file=$(_pointer_progress_json 2>/dev/null)
  if [ -n "$_pointer_file" ]; then
    _parsed=$(_parse_progress_json "$_pointer_file")
    plan_prd=$(echo "$_parsed"         | cut -d'|' -f1)
    plan_total=$(echo "$_parsed"       | cut -d'|' -f2)
    plan_complete=$(echo "$_parsed"    | cut -d'|' -f3)
    plan_in_progress=$(echo "$_parsed" | cut -d'|' -f4)
    plan_blocked=$(echo "$_parsed"     | cut -d'|' -f5)
    # touch last_seen_at on the pointer so GC and peers see this session as live
    if [ -x "$HOME/.claude/hooks/scripts/active-plan-read.sh" ]; then
      "$HOME/.claude/hooks/scripts/active-plan-read.sh" >/dev/null 2>&1 || true
    fi
  fi

  # Only fall back to filesystem scan if the pointer didn't provide a plan
  # (avoids a stale neighboring PRD masking THIS session's pointer-resolved one).
  _progress_files=""
  if [ -z "$plan_prd" ]; then
    _progress_files=$(_find_progress_json "$cwd" 2>/dev/null)
  fi
  if [ -n "$_progress_files" ]; then
    # Pick the one with the most in-progress or most recently modified
    # Prefer in_progress > not_started > complete
    _best_file=""
    _best_score="-1"
    while IFS= read -r _pf; do
      [ -f "$_pf" ] || continue
      _ip=$(jq '[.sprints[]? | select(.status == "in_progress")] | length' "$_pf" 2>/dev/null || echo "0")
      _ns=$(jq '[.sprints[]? | select(.status == "not_started")] | length' "$_pf" 2>/dev/null || echo "0")
      # score: in_progress * 10 + not_started (active PRDs rank highest)
      _score=$(( _ip * 10 + _ns ))
      if [ "$_score" -gt "$_best_score" ]; then
        _best_score=$_score
        _best_file=$_pf
      fi
    done <<< "$_progress_files"

    if [ -n "$_best_file" ]; then
      _parsed=$(_parse_progress_json "$_best_file")
      plan_prd=$(echo "$_parsed"         | cut -d'|' -f1)
      plan_total=$(echo "$_parsed"       | cut -d'|' -f2)
      plan_complete=$(echo "$_parsed"    | cut -d'|' -f3)
      plan_in_progress=$(echo "$_parsed" | cut -d'|' -f4)
      plan_blocked=$(echo "$_parsed"     | cut -d'|' -f5)
    fi
  fi
fi

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

# ── line 1: model · cost · duration · diff · effort · vim ─────────────────
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
if [ -n "$effort_level" ]; then
  # color by effort: xhigh/max=magenta, high=yellow, medium/low=dim
  case "$effort_level" in
    max|xhigh) _ec="$M" ;;
    high)      _ec="$Y" ;;
    *)         _ec="$D" ;;
  esac
  printf '  %s·%s  %s%s%s' "$D" "$N" "$_ec" "$effort_level" "$N"
fi
if [ -n "$vim_mode" ]; then
  case "$vim_mode" in
    INSERT)      _vc="$G" ;;
    NORMAL)      _vc="$C" ;;
    VISUAL*)     _vc="$Y" ;;
    *)           _vc="$D" ;;
  esac
  printf '  %s·%s  %s%s%s' "$D" "$N" "$_vc" "$vim_mode" "$N"
fi
if [ -n "$agent_name" ]; then
  printf '  %s·%s  %sagent:%s%s%s' "$D" "$N" "$M" "$W" "$agent_name" "$N"
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

# ── line 4: 5h + 7d rate limits (always shown; countdown refreshes every render) ──
# 5-hour block
if [ -n "$five_pct" ]; then
  five_int=$(printf "%.0f" "$five_pct" 2>/dev/null || echo 0)
  five_col=$(bar_color "$five_int")
  printf '%s5h   %s ' "$C" "$N"
  progress_bar "$five_int" 10 "$five_col"
  printf '  %s%d%%%s' "$W" "$five_int" "$N"
  if [ -n "$five_resets" ]; then
    printf ' %s(%s)%s' "$D" "$(fmt_resets "$five_resets")" "$N"
  fi
else
  printf '%s5h   %s %s——————————%s  %s—%%%s' "$C" "$N" "$D" "$N" "$D" "$N"
fi

printf '     %s│%s     ' "$D" "$N"

# 7-day block
if [ -n "$week_pct" ]; then
  week_int=$(printf "%.0f" "$week_pct" 2>/dev/null || echo 0)
  week_col=$(bar_color "$week_int")
  printf '%s7d%s   ' "$C" "$N"
  progress_bar "$week_int" 10 "$week_col"
  printf '  %s%d%%%s' "$W" "$week_int" "$N"
  if [ -n "$week_resets" ]; then
    printf ' %s(%s)%s' "$D" "$(fmt_resets "$week_resets")" "$N"
  fi
else
  printf '%s7d%s   %s——————————%s  %s—%%%s' "$C" "$N" "$D" "$N" "$D" "$N"
fi
printf '\n'

# ── line 5: plan / sprint progress (only shown when a progress.json is found) ──
if [ -n "$plan_prd" ] && [ "$plan_total" -gt 0 ] 2>/dev/null; then
  # Determine overall plan status color and label
  if [ "$plan_blocked" -gt 0 ] 2>/dev/null; then
    _plan_col="$R"
    _plan_status="BLOCKED"
  elif [ "$plan_in_progress" -gt 0 ] 2>/dev/null; then
    _plan_col="$Y"
    _plan_status="running"
  elif [ "$plan_complete" -eq "$plan_total" ] 2>/dev/null; then
    _plan_col="$G"
    _plan_status="done"
  else
    _plan_col="$W"
    _plan_status="queued"
  fi

  printf '%splan %s %s%s%s' "$C" "$N" "$W" "$plan_prd" "$N"
  printf '  %s·%s  sprint %s%d/%d%s' "$D" "$N" "$B" "$plan_complete" "$plan_total" "$N"

  # mini inline bar: one char per sprint
  # (capped at 20 chars; each position = one sprint)
  printf '  %s[%s' "$D" "$N"
  _sprint_idx=0
  while [ "$_sprint_idx" -lt "$plan_total" ] && [ "$_sprint_idx" -lt 20 ]; do
    _sprint_idx=$(( _sprint_idx + 1 ))
    if [ "$_sprint_idx" -le "$plan_complete" ] 2>/dev/null; then
      printf '%s█%s' "$B" "$N"
    elif [ "$plan_in_progress" -gt 0 ] && [ "$_sprint_idx" -eq $(( plan_complete + 1 )) ] 2>/dev/null; then
      printf '%s▶%s' "$Y" "$N"
    elif [ "$plan_blocked" -gt 0 ] && [ "$_sprint_idx" -eq $(( plan_complete + 1 )) ] 2>/dev/null; then
      printf '%s✗%s' "$R" "$N"
    else
      printf '%s░%s' "$D" "$N"
    fi
  done
  printf '%s]%s' "$D" "$N"

  printf '  %s%s%s' "$_plan_col" "$_plan_status" "$N"
  printf '\n'
fi

# ── line 6: live work (running agents + tracked bash tasks) ───────────────
# Reads heartbeat files dropped by ~/.claude/hooks/track-active-work.sh on
# PreToolUse(Agent|Bash). PostToolUse removes them. Stale files (>2h) are pruned
# here at render time so a crashed/unfinished tool call doesn't haunt the line.
_active_dir="$HOME/.claude/state/active"
if [ -d "$_active_dir" ] && command -v jq &>/dev/null; then
  find "$_active_dir" -maxdepth 1 -type f -name '*.json' -mmin +120 -delete 2>/dev/null || true

  shopt -s nullglob 2>/dev/null
  _agent_files=( "$_active_dir"/agent-*.json )
  _bash_files=( "$_active_dir"/bash-*.json )
  shopt -u nullglob 2>/dev/null
  _agent_count=${#_agent_files[@]}
  _bash_count=${#_bash_files[@]}

  if [ "$_agent_count" -gt 0 ] || [ "$_bash_count" -gt 0 ]; then
    printf '%swork %s ' "$C" "$N"
    _wrote_section=0
    if [ "$_agent_count" -gt 0 ]; then
      _agent_names=$(jq -r '.name' "${_agent_files[@]}" 2>/dev/null \
        | sort | uniq -c | sort -rn \
        | awk '{ if ($1 > 1) printf "%s×%s, ", $2, $1; else printf "%s, ", $2 }' \
        | sed 's/, $//')
      printf '%sagents %d%s %s(%s)%s' "$Y" "$_agent_count" "$N" "$D" "$_agent_names" "$N"
      _wrote_section=1
    fi
    if [ "$_bash_count" -gt 0 ]; then
      [ "$_wrote_section" -eq 1 ] && printf '  %s·%s  ' "$D" "$N"
      _bash_labels=$(jq -r '.label' "${_bash_files[@]}" 2>/dev/null \
        | sort | uniq -c | sort -rn \
        | awk '{ if ($1 > 1) printf "%s×%s, ", $2" "$3, $1; else { $1=""; sub(/^ /,""); printf "%s, ", $0 } }' \
        | sed 's/, $//')
      printf '%stask %d%s %s(%s)%s' "$Y" "$_bash_count" "$N" "$D" "$_bash_labels" "$N"
    fi
    printf '\n'
  fi
fi

# statusLine MUST exit 0 — otherwise Claude Code suppresses the line
exit 0

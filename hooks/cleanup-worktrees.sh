#!/usr/bin/env bash
# Stop hook: Prune stale worktrees and remove merged sprint branches
#
# Runs on every task end to guarantee worktree cleanup even if the orchestrator
# crashes mid-work, the user doesn't run the orchestrator, or worktrees accumulate
# between sessions.
#
# Safety invariants:
#   - NEVER deletes worktrees with unmerged changes — logs WARNING instead
#   - Uses `git branch -d` (lowercase) which refuses unmerged branches
#   - NEVER uses `git branch -D` (force delete)
#   - ALWAYS exits 0 — cleanup is best-effort, never blocks
#   - Skips if PROJECT_DIR is $HOME or /root
#   - Skips if not a git repository

# Cleanup hook crashes should never block — always exit 0
trap 'echo "HOOK WARNING: cleanup-worktrees.sh crashed at line $LINENO" >&2; exit 0' ERR

# Source shared logging utility
source ~/.claude/hooks/lib/hook-logger.sh 2>/dev/null || true

# Source shared stop-guard (fail-open: if missing, guard is a no-op)
source ~/.claude/hooks/lib/stop-guard.sh 2>/dev/null || true

# ─── CONFIGURATION ─────────────────────────────────────────────────────

HOOK_NAME="cleanup-worktrees"

# ─── READ STDIN INPUT ──────────────────────────────────────────────────

# Read JSON input from stdin (Stop hook protocol)
INPUT=""
if [ -t 0 ]; then
  # No stdin (running manually) — use pwd
  INPUT="{}"
else
  INPUT=$(cat 2>/dev/null || echo "{}")
fi

# Check stop_hook_active — prevent infinite loop
check_stop_hook_active "$INPUT"

# Only run when Claude explicitly signals task completion — skips during
# AskUserQuestion pauses, Monitor events, and intermediate turns. Keeps the
# hook's per-turn cost at ~1ms when the agent is still working.
check_completion_authorized "$INPUT"

# ─── RESOLVE PROJECT DIRECTORY ─────────────────────────────────────────

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Skip if working in home directory (not a real project)
if [ "$PROJECT_DIR" = "$HOME" ] || [ "$PROJECT_DIR" = "/root" ]; then
  log_hook_event "$HOOK_NAME" "skipped" "project dir is HOME — not a real project"
  exit 0
fi

# Skip if project directory doesn't exist
if [ ! -d "$PROJECT_DIR" ]; then
  log_hook_event "$HOOK_NAME" "skipped" "project dir does not exist: $PROJECT_DIR"
  exit 0
fi

# Skip if not a git repository
if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  log_hook_event "$HOOK_NAME" "skipped" "not a git repo: $PROJECT_DIR"
  exit 0
fi

# ─── BUILD FOREIGN-SLUG SKIPLIST (concurrent multi-session safety) ─────
#
# Read every active-plan pointer from peer sessions. Their (session_id, prd_slug)
# pairs are off-limits — never delete worktrees or branches in their namespace.
# Pointers older than 24h are still considered live here; the dedicated
# gc-active-plans.sh handles their reaping below.

OWN_SLUG=""
if [ -n "${CLAUDE_SESSION_ID:-}" ] && [ -f "$HOME/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json" ]; then
  OWN_SLUG=$(jq -r '.prd_slug // empty' "$HOME/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json" 2>/dev/null || echo "")
fi

declare -A FOREIGN_SLUGS=()
if compgen -G "$HOME/.claude/state/active-plan-*.json" >/dev/null 2>&1; then
  for ptr in "$HOME/.claude/state/active-plan-"*.json; do
    [ -f "$ptr" ] || continue
    sid=$(jq -r '.session_id // empty' "$ptr" 2>/dev/null || echo "")
    slug=$(jq -r '.prd_slug // empty' "$ptr" 2>/dev/null || echo "")
    [ -z "$slug" ] && continue
    [ "$sid" = "${CLAUDE_SESSION_ID:-}" ] && continue
    FOREIGN_SLUGS["$slug"]=1
  done
fi

# Run pointer GC ONCE per cleanup invocation (cheap, idempotent, never deletes PRDs).
if [ -x "$HOME/.claude/hooks/scripts/gc-active-plans.sh" ]; then
  bash "$HOME/.claude/hooks/scripts/gc-active-plans.sh" >/dev/null 2>&1 || true
fi

# ─── PRUNE STALE WORKTREE REFERENCES ───────────────────────────────────

# Remove worktree entries where the path no longer exists on disk
if git -C "$PROJECT_DIR" worktree prune 2>/dev/null; then
  log_hook_event "$HOOK_NAME" "pruned" "removed stale worktree references"
else
  log_hook_event "$HOOK_NAME" "prune-failed" "git worktree prune encountered an error (non-fatal)"
fi

# ─── LIST AND CLEAN MERGED WORKTREES ───────────────────────────────────

REMOVED_COUNT=0
WARNED_COUNT=0

# Parse worktree list (porcelain format):
#   worktree <path>
#   HEAD <sha>
#   branch refs/heads/<name>   (or "detached")
#   (blank line separates entries)
#
# We skip the first entry (main worktree) and process additional ones.

WORKTREE_LIST=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null || echo "")

if [ -z "$WORKTREE_LIST" ]; then
  log_hook_event "$HOOK_NAME" "completed" "no worktrees found"
  exit 0
fi

# ─── WORKTREE PROCESSOR (shared logic for loop body and final-entry case) ──

# extract_slug_from_branch BRANCH
# Returns the PRD slug for a sprint or PRD branch name, or empty if not namespaced.
#   sprint/<slug>/NN-title → <slug>
#   prd/<slug>             → <slug>
#   anything else          → ""
extract_slug_from_branch() {
  local b="$1"
  case "$b" in
    sprint/*) echo "$b" | awk -F/ '{print $2}' ;;
    prd/*)    echo "${b#prd/}" ;;
    *)        echo "" ;;
  esac
}

# process_worktree PATH BRANCH
# Namespace-aware cleanup:
#   1. Foreign-slug branches → skip (peer session owns this).
#   2. Sprint branches → check ancestry vs prd/<slug> (NOT main).
#   3. prd/<slug> branches → check ancestry vs main, only if owned by us.
#   4. Legacy unscoped sprint/* branches (no slug) → fall back to old main-ancestry behavior.
process_worktree() {
  local wt_path="$1" wt_branch="$2"
  local slug ancestry_target wt_dirty

  slug=$(extract_slug_from_branch "$wt_branch")

  # 1. Foreign slug — never touch.
  if [ -n "$slug" ] && [ "${FOREIGN_SLUGS[$slug]:-}" = "1" ]; then
    log_hook_event "$HOOK_NAME" "skipped-foreign" "$wt_path ($wt_branch) — owned by peer session"
    return
  fi

  # 2. Pick ancestry target by branch type.
  case "$wt_branch" in
    sprint/*/*)
      # Namespaced sprint: check vs prd/<slug>.
      ancestry_target="prd/$slug"
      if ! git -C "$PROJECT_DIR" rev-parse --verify "$ancestry_target" >/dev/null 2>&1; then
        # prd/<slug> deleted already → fall back to main.
        ancestry_target="main"
      fi
      ;;
    prd/*)
      # Integration branch: only delete if owned by us AND merged into main.
      if [ -n "$OWN_SLUG" ] && [ "$slug" = "$OWN_SLUG" ]; then
        ancestry_target="main"
      else
        log_hook_event "$HOOK_NAME" "skipped-non-owner" "$wt_path ($wt_branch) — not this session's PRD"
        return
      fi
      ;;
    sprint/*)
      # Legacy unscoped sprint/<title> (no PRD slug). Old behavior.
      ancestry_target="main"
      ;;
    *)
      # Non-orchestrator worktree (user-created). Don't touch.
      log_hook_event "$HOOK_NAME" "skipped-non-sprint" "$wt_path ($wt_branch)"
      return
      ;;
  esac

  if git -C "$PROJECT_DIR" rev-parse --verify "$ancestry_target" >/dev/null 2>&1 && \
     git -C "$PROJECT_DIR" merge-base --is-ancestor "$wt_branch" "$ancestry_target" 2>/dev/null; then
    wt_dirty=$(git -C "$wt_path" status --porcelain 2>/dev/null || echo "")
    if [ -n "$wt_dirty" ]; then
      log_hook_event "$HOOK_NAME" "WARNING" "worktree $wt_path has uncommitted changes despite merged branch — skipping"
      echo "HOOK WARNING: cleanup-worktrees: worktree has dirty state: $wt_path ($wt_branch)" >&2
      WARNED_COUNT=$((WARNED_COUNT + 1))
    elif git -C "$PROJECT_DIR" worktree remove "$wt_path" 2>/dev/null; then
      log_hook_event "$HOOK_NAME" "removed-worktree" "$wt_path (branch: $wt_branch, base: $ancestry_target)"
      if git -C "$PROJECT_DIR" branch -d "$wt_branch" 2>/dev/null; then
        log_hook_event "$HOOK_NAME" "deleted-branch" "$wt_branch (merged into $ancestry_target)"
      else
        log_hook_event "$HOOK_NAME" "branch-delete-skipped" "$wt_branch — git branch -d refused (safety net)"
      fi
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    else
      log_hook_event "$HOOK_NAME" "remove-failed" "could not remove worktree $wt_path"
    fi
  else
    log_hook_event "$HOOK_NAME" "WARNING" "worktree $wt_path (branch: $wt_branch) has unmerged changes vs $ancestry_target — skipping"
    echo "HOOK WARNING: cleanup-worktrees: unmerged worktree preserved: $wt_path ($wt_branch)" >&2
    WARNED_COUNT=$((WARNED_COUNT + 1))
  fi
}

# Track whether we are reading the first (main) worktree
IS_FIRST=true
CURRENT_PATH=""
CURRENT_BRANCH=""

while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    # Process previous worktree entry (if any and not main)
    if [ "$IS_FIRST" = "false" ] && [ -n "$CURRENT_PATH" ] && [ -n "$CURRENT_BRANCH" ]; then
      process_worktree "$CURRENT_PATH" "$CURRENT_BRANCH"
    fi

    # Start tracking new worktree entry
    CURRENT_PATH="${line#worktree }"
    CURRENT_BRANCH=""
    IS_FIRST="false"

    # The very first worktree entry is the main worktree — skip it.
    # Detect via canonical path comparison (readlink resolves symlinks and
    # trailing slashes, which a raw $PROJECT_DIR may have). Fallback to raw
    # compare if readlink is unavailable.
    _CANON_CURRENT="$CURRENT_PATH"
    _CANON_PROJECT="$PROJECT_DIR"
    if command -v readlink &>/dev/null; then
      _CANON_CURRENT=$(readlink -f "$CURRENT_PATH" 2>/dev/null || echo "$CURRENT_PATH")
      _CANON_PROJECT=$(readlink -f "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")
    fi
    if [ "$_CANON_CURRENT" = "$_CANON_PROJECT" ]; then
      IS_FIRST="true"
    fi

  elif [[ "$line" == branch\ * ]]; then
    # Extract branch name from "branch refs/heads/<name>"
    BRANCH_REF="${line#branch }"
    CURRENT_BRANCH="${BRANCH_REF#refs/heads/}"
  fi
done <<< "$WORKTREE_LIST"

# Process the last worktree entry (loop ends without a blank-line trigger)
if [ "$IS_FIRST" = "false" ] && [ -n "$CURRENT_PATH" ] && [ -n "$CURRENT_BRANCH" ]; then
  process_worktree "$CURRENT_PATH" "$CURRENT_BRANCH"
fi

# ─── SUMMARY ───────────────────────────────────────────────────────────

if [ "$REMOVED_COUNT" -gt 0 ] || [ "$WARNED_COUNT" -gt 0 ]; then
  log_hook_event "$HOOK_NAME" "completed" "removed $REMOVED_COUNT merged worktree(s), preserved $WARNED_COUNT unmerged (warnings logged)"
else
  log_hook_event "$HOOK_NAME" "completed" "no sprint worktrees found in $PROJECT_DIR"
fi

# Cleanup hook ALWAYS exits 0 — never blocks
exit 0

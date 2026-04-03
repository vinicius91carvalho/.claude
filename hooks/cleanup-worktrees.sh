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
STOP_HOOK_ACTIVE="false"
if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

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

# Track whether we are reading the first (main) worktree
IS_FIRST=true
CURRENT_PATH=""
CURRENT_BRANCH=""

while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    # Process previous worktree entry (if any and not main)
    if [ "$IS_FIRST" = "false" ] && [ -n "$CURRENT_PATH" ] && [ -n "$CURRENT_BRANCH" ]; then
      # Check if branch is merged into HEAD of main worktree
      MAIN_HEAD=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")
      if [ -n "$MAIN_HEAD" ] && git -C "$PROJECT_DIR" merge-base --is-ancestor "$CURRENT_BRANCH" HEAD 2>/dev/null; then
        # Branch is merged — check worktree is clean before removing
        WT_DIRTY=$(git -C "$CURRENT_PATH" status --porcelain 2>/dev/null || echo "")
        if [ -n "$WT_DIRTY" ]; then
          log_hook_event "$HOOK_NAME" "WARNING" "worktree $CURRENT_PATH has uncommitted changes despite merged branch — skipping"
          echo "HOOK WARNING: cleanup-worktrees: worktree has dirty state: $CURRENT_PATH ($CURRENT_BRANCH)" >&2
          WARNED_COUNT=$((WARNED_COUNT + 1))
        elif git -C "$PROJECT_DIR" worktree remove "$CURRENT_PATH" 2>/dev/null; then
          log_hook_event "$HOOK_NAME" "removed-worktree" "$CURRENT_PATH (branch: $CURRENT_BRANCH)"
          # Use -d (not -D) — will refuse if branch somehow has unmerged commits
          if git -C "$PROJECT_DIR" branch -d "$CURRENT_BRANCH" 2>/dev/null; then
            log_hook_event "$HOOK_NAME" "deleted-branch" "$CURRENT_BRANCH (merged)"
          else
            log_hook_event "$HOOK_NAME" "branch-delete-skipped" "$CURRENT_BRANCH — git branch -d refused (safety net)"
          fi
          REMOVED_COUNT=$((REMOVED_COUNT + 1))
        else
          log_hook_event "$HOOK_NAME" "remove-failed" "could not remove worktree $CURRENT_PATH"
        fi
      else
        # Branch has unmerged commits — log warning, do NOT delete
        log_hook_event "$HOOK_NAME" "WARNING" "worktree $CURRENT_PATH (branch: $CURRENT_BRANCH) has unmerged changes — skipping"
        echo "HOOK WARNING: cleanup-worktrees: unmerged worktree preserved: $CURRENT_PATH ($CURRENT_BRANCH)" >&2
        WARNED_COUNT=$((WARNED_COUNT + 1))
      fi
    fi

    # Start tracking new worktree entry
    CURRENT_PATH="${line#worktree }"
    CURRENT_BRANCH=""
    IS_FIRST="false"

    # The very first worktree entry is the main worktree — skip it
    # We detect it by checking if it matches the PROJECT_DIR
    if [ "$CURRENT_PATH" = "$PROJECT_DIR" ]; then
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
  MAIN_HEAD=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")
  if [ -n "$MAIN_HEAD" ] && git -C "$PROJECT_DIR" merge-base --is-ancestor "$CURRENT_BRANCH" HEAD 2>/dev/null; then
    WT_DIRTY=$(git -C "$CURRENT_PATH" status --porcelain 2>/dev/null || echo "")
    if [ -n "$WT_DIRTY" ]; then
      log_hook_event "$HOOK_NAME" "WARNING" "worktree $CURRENT_PATH has uncommitted changes despite merged branch — skipping"
      echo "HOOK WARNING: cleanup-worktrees: worktree has dirty state: $CURRENT_PATH ($CURRENT_BRANCH)" >&2
      WARNED_COUNT=$((WARNED_COUNT + 1))
    elif git -C "$PROJECT_DIR" worktree remove "$CURRENT_PATH" 2>/dev/null; then
      log_hook_event "$HOOK_NAME" "removed-worktree" "$CURRENT_PATH (branch: $CURRENT_BRANCH)"
      if git -C "$PROJECT_DIR" branch -d "$CURRENT_BRANCH" 2>/dev/null; then
        log_hook_event "$HOOK_NAME" "deleted-branch" "$CURRENT_BRANCH (merged)"
      else
        log_hook_event "$HOOK_NAME" "branch-delete-skipped" "$CURRENT_BRANCH — git branch -d refused (safety net)"
      fi
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    else
      log_hook_event "$HOOK_NAME" "remove-failed" "could not remove worktree $CURRENT_PATH"
    fi
  else
    log_hook_event "$HOOK_NAME" "WARNING" "worktree $CURRENT_PATH (branch: $CURRENT_BRANCH) has unmerged changes — skipping"
    echo "HOOK WARNING: cleanup-worktrees: unmerged worktree preserved: $CURRENT_PATH ($CURRENT_BRANCH)" >&2
    WARNED_COUNT=$((WARNED_COUNT + 1))
  fi
fi

# ─── SUMMARY ───────────────────────────────────────────────────────────

if [ "$REMOVED_COUNT" -gt 0 ] || [ "$WARNED_COUNT" -gt 0 ]; then
  log_hook_event "$HOOK_NAME" "completed" "removed $REMOVED_COUNT merged worktree(s), preserved $WARNED_COUNT unmerged (warnings logged)"
else
  log_hook_event "$HOOK_NAME" "completed" "no sprint worktrees found in $PROJECT_DIR"
fi

# Cleanup hook ALWAYS exits 0 — never blocks
exit 0

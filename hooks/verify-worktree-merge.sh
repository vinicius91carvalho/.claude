#!/usr/bin/env bash
# verify-worktree-merge.sh — Post-merge verification for worktree branches.
# Checks that files modified by previous sprints weren't silently overwritten.
#
# Usage: verify-worktree-merge.sh <worktree-branch> <main-branch> <previous-sprint-shas...>
# Exit codes: 0 = clean, 1 = potential overwrites detected
#
# Called by the orchestrator after merging a worktree branch back to main.

set -euo pipefail

WORKTREE_BRANCH="${1:?Usage: verify-worktree-merge.sh <worktree-branch> <main-branch> [prev-sha...]}"
MAIN_BRANCH="${2:-main}"
shift 2
PREV_SHAS=("$@")

if [ ${#PREV_SHAS[@]} -eq 0 ]; then
  exit 0  # No previous sprints to check against
fi

CONFLICTS=0

# Get files modified by the worktree merge
WORKTREE_FILES=$(git diff --name-only "$MAIN_BRANCH"..."$WORKTREE_BRANCH" 2>/dev/null || echo "")

if [ -z "$WORKTREE_FILES" ]; then
  exit 0
fi

# For each previous sprint SHA, check if any of its modified files overlap
for sha in "${PREV_SHAS[@]}"; do
  # Get files modified by that sprint (comparing the commit to its parent)
  SPRINT_FILES=$(git diff --name-only "${sha}^" "$sha" 2>/dev/null || echo "")

  if [ -z "$SPRINT_FILES" ]; then
    continue
  fi

  # Find overlapping files
  OVERLAP=$(comm -12 <(echo "$WORKTREE_FILES" | sort) <(echo "$SPRINT_FILES" | sort))

  if [ -n "$OVERLAP" ]; then
    echo "WARNING: Worktree branch '$WORKTREE_BRANCH' modifies files also changed by commit $sha:"
    echo "$OVERLAP" | sed 's/^/  /'
    echo "These files may have been silently overwritten. Verify manually."
    CONFLICTS=$((CONFLICTS + 1))
  fi
done

if [ "$CONFLICTS" -gt 0 ]; then
  echo ""
  echo "Found $CONFLICTS potential merge overwrites. Review before proceeding."
  exit 1
fi

exit 0

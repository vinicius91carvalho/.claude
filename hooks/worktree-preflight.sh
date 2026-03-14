#!/usr/bin/env bash
# Worktree Preflight — validates git and environment readiness for parallel sprint execution.
# Called by orchestrator Step 0. Can also be sourced manually: source ~/.claude/hooks/worktree-preflight.sh
#
# Exit codes:
#   0 — ready for worktree execution
#   1 — fatal error (cannot proceed)
#   2 — git was bootstrapped (new repo initialized)

set -euo pipefail

PREFLIGHT_LOG=""
log() { PREFLIGHT_LOG="${PREFLIGHT_LOG}$1\n"; echo "$1"; }

# --- 1. Git readiness ---

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "git: existing repo detected"
  GIT_BOOTSTRAPPED=false
else
  log "git: no repo found — bootstrapping"

  git init
  if [ ! -f .gitignore ]; then
    cat > .gitignore << 'GITIGNORE'
node_modules/
.next/
dist/
build/
.turbo/
.sst/
.env
.env.local
*.log
.DS_Store
GITIGNORE
    log "git: created .gitignore"
  fi

  git add -A
  git commit -m "chore: initial commit for sprint execution" --allow-empty
  GIT_BOOTSTRAPPED=true
  log "git: repo initialized with initial commit"
fi

# --- 2. Working tree hygiene ---

DIRTY=$(git status --porcelain 2>/dev/null | head -1)
if [ -n "$DIRTY" ]; then
  git add -A
  SNAPSHOT_SHA=$(git commit -m "chore: snapshot before sprint execution" 2>/dev/null | grep -oP '[a-f0-9]{7,}' | head -1 || true)
  log "git: dirty tree — snapshot commit ${SNAPSHOT_SHA:-created}"
else
  log "git: clean working tree"
fi

# --- 3. Stale worktree cleanup ---

STALE_COUNT=0
if git worktree list --porcelain >/dev/null 2>&1; then
  # Count stale worktrees BEFORE pruning, then prune
  STALE_COUNT=$(git worktree prune --dry-run 2>/dev/null | wc -l || echo 0)
  git worktree prune 2>/dev/null

  # Clean orphaned sprint branches (no worktree, not merged)
  git branch --list 'sprint/*' 2>/dev/null | while read -r branch; do
    branch=$(echo "$branch" | tr -d ' *')
    if ! git worktree list --porcelain 2>/dev/null | grep -q "$branch"; then
      git branch -d "$branch" 2>/dev/null && log "git: pruned orphan branch $branch" || true
    fi
  done
fi
log "git: pruned ${STALE_COUNT} stale worktrees"

# --- 4. proot-distro detection ---

PROOT_DETECTED=false
if uname -r 2>/dev/null | grep -q PRoot-Distro && [ "$(uname -m)" = "aarch64" ]; then
  PROOT_DETECTED=true
  export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
  export CHOKIDAR_USEPOLLING=true
  export WATCHPACK_POLLING=true
  log "proot: ARM64 detected — env vars set (NODE_OPTIONS, CHOKIDAR, WATCHPACK)"
else
  log "proot: not detected"
fi

# --- 5. Dependency baseline (Node projects) ---

DEPS_STATUS="skipped"
if [ -f package.json ]; then
  if [ ! -d node_modules ]; then
    DEPS_STATUS="installed"
    # Ensure hoisted layout for proot compat
    if [ "$PROOT_DETECTED" = true ] && ! grep -q 'node-linker=hoisted' .npmrc 2>/dev/null; then
      echo "node-linker=hoisted" >> .npmrc
      log "deps: added node-linker=hoisted to .npmrc"
    fi
    pnpm install 2>/dev/null || log "deps: pnpm install failed (may need manual intervention)"
  else
    BROKEN=$(find node_modules/.bin -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
    if [ "$BROKEN" -gt 0 ]; then
      DEPS_STATUS="repaired"
      log "deps: ${BROKEN} broken symlinks — reinstalling"
      pnpm install 2>/dev/null || true
    else
      DEPS_STATUS="ok"
    fi
  fi
  log "deps: ${DEPS_STATUS}"
else
  log "deps: no package.json — skipped"
fi

# --- Summary ---

echo ""
echo "=== Worktree Preflight Summary ==="
echo "git_bootstrapped: ${GIT_BOOTSTRAPPED}"
echo "proot_detected: ${PROOT_DETECTED}"
echo "deps_status: ${DEPS_STATUS}"
echo "stale_worktrees_pruned: ${STALE_COUNT}"
echo "==================================="

if [ "$GIT_BOOTSTRAPPED" = true ]; then
  exit 2
fi
exit 0

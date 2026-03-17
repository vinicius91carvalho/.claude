#!/usr/bin/env bash
# Worktree Preflight — validates git and environment readiness for parallel sprint execution.
# Called by orchestrator Step 0. Can also be sourced manually: source ~/.claude/hooks/worktree-preflight.sh
#
# Language-universal — auto-detects project type and manages dependencies accordingly.
#
# Exit codes:
#   0 — ready for worktree execution
#   1 — fatal error (cannot proceed)
#   2 — git was bootstrapped (new repo initialized)

set -euo pipefail

# Source shared detection library
source ~/.claude/hooks/lib/detect-project.sh

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
    # Detect project languages for gitignore
    detect_project_langs "$(pwd)"

    # Start with universal entries
    cat > .gitignore << 'GITIGNORE'
# Environment & secrets
.env
.env.local
.env.*.local

# OS
.DS_Store
Thumbs.db
*.log

# IDE
.idea/
.vscode/
*.swp
*.swo
*~
GITIGNORE

    # Append language-specific entries
    for lang in "${PROJECT_LANGS[@]}"; do
      case "$lang" in
        typescript|javascript)
          cat >> .gitignore << 'GITIGNORE'

# Node.js
node_modules/
dist/
build/
.next/
.turbo/
.sst/
coverage/
.cache/
.output/
.nuxt/
.vercel/
GITIGNORE
          ;;
        python)
          cat >> .gitignore << 'GITIGNORE'

# Python
__pycache__/
*.pyc
*.pyo
*.egg-info/
.eggs/
.venv/
venv/
.mypy_cache/
.pytest_cache/
.ruff_cache/
.tox/
.nox/
htmlcov/
GITIGNORE
          ;;
        go)
          cat >> .gitignore << 'GITIGNORE'

# Go
vendor/
GITIGNORE
          ;;
        rust)
          cat >> .gitignore << 'GITIGNORE'

# Rust
target/
Cargo.lock
GITIGNORE
          ;;
        ruby)
          cat >> .gitignore << 'GITIGNORE'

# Ruby
vendor/bundle/
.bundle/
coverage/
tmp/
GITIGNORE
          ;;
        java|kotlin)
          cat >> .gitignore << 'GITIGNORE'

# Java / Kotlin
build/
target/
.gradle/
*.class
*.jar
GITIGNORE
          ;;
        elixir)
          cat >> .gitignore << 'GITIGNORE'

# Elixir
_build/
deps/
.elixir_ls/
GITIGNORE
          ;;
        dart)
          cat >> .gitignore << 'GITIGNORE'

# Dart / Flutter
.dart_tool/
build/
.packages
pubspec.lock
GITIGNORE
          ;;
        csharp)
          cat >> .gitignore << 'GITIGNORE'

# .NET / C#
bin/
obj/
*.user
*.suo
GITIGNORE
          ;;
        c_cpp)
          cat >> .gitignore << 'GITIGNORE'

# C / C++
cmake-build-*/
*.o
*.a
*.so
*.dylib
GITIGNORE
          ;;
        scala)
          cat >> .gitignore << 'GITIGNORE'

# Scala
target/
.bsp/
.metals/
.bloop/
GITIGNORE
          ;;
        haskell)
          cat >> .gitignore << 'GITIGNORE'

# Haskell
.stack-work/
dist-newstyle/
GITIGNORE
          ;;
        zig)
          cat >> .gitignore << 'GITIGNORE'

# Zig
zig-cache/
zig-out/
GITIGNORE
          ;;
        swift)
          cat >> .gitignore << 'GITIGNORE'

# Swift
.build/
.swiftpm/
Packages/
GITIGNORE
          ;;
      esac
    done

    # If no languages detected, add common defaults
    if [ ${#PROJECT_LANGS[@]} -eq 0 ]; then
      cat >> .gitignore << 'GITIGNORE'

# Common build outputs
dist/
build/
target/
out/
vendor/
GITIGNORE
    fi

    log "git: created .gitignore (languages: ${PROJECT_LANGS[*]:-none detected})"
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
  STALE_COUNT=$(git worktree prune --dry-run 2>/dev/null | wc -l || echo 0)
  git worktree prune 2>/dev/null

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
  # Node.js-specific env vars (only if Node.js project)
  detect_project_langs "$(pwd)"
  for lang in "${PROJECT_LANGS[@]}"; do
    case "$lang" in
      typescript|javascript)
        export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
        export CHOKIDAR_USEPOLLING=true
        export WATCHPACK_POLLING=true
        log "proot: ARM64 detected — Node.js env vars set (NODE_OPTIONS, CHOKIDAR, WATCHPACK)"
        break
        ;;
    esac
  done
  if [[ ! " ${PROJECT_LANGS[*]:-} " =~ " typescript " ]] && [[ ! " ${PROJECT_LANGS[*]:-} " =~ " javascript " ]]; then
    log "proot: ARM64 detected — non-Node.js project, no extra env vars needed"
  fi
else
  log "proot: not detected"
fi

# --- 5. Dependency baseline (all languages) ---

DEPS_STATUS="skipped"
detect_project_langs "$(pwd)"

for lang in "${PROJECT_LANGS[@]}"; do
  case "$lang" in
    typescript|javascript)
      if [ -f package.json ]; then
        if [ ! -d node_modules ]; then
          DEPS_STATUS="installed"
          detect_pkg_manager "$(pwd)"
          # Ensure hoisted layout for proot compat
          if [ "$PROOT_DETECTED" = true ] && ! grep -q 'node-linker=hoisted' .npmrc 2>/dev/null; then
            echo "node-linker=hoisted" >> .npmrc
            log "deps: added node-linker=hoisted to .npmrc"
          fi
          ${PKG_MGR:-pnpm} install 2>/dev/null || log "deps: ${PKG_MGR:-pnpm} install failed (may need manual intervention)"
        else
          BROKEN=$(find node_modules/.bin -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
          if [ "$BROKEN" -gt 0 ]; then
            DEPS_STATUS="repaired"
            detect_pkg_manager "$(pwd)"
            log "deps: ${BROKEN} broken symlinks — reinstalling"
            ${PKG_MGR:-pnpm} install 2>/dev/null || true
          else
            DEPS_STATUS="ok"
          fi
        fi
        log "deps: node.js — ${DEPS_STATUS}"
      fi
      ;;
    python)
      if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f Pipfile ]; then
        if [ ! -d .venv ] && [ ! -d venv ]; then
          detect_dep_install_cmd "$(pwd)"
          if [ -n "$DEP_INSTALL_CMD" ]; then
            DEPS_STATUS="installed"
            eval "$DEP_INSTALL_CMD" 2>/dev/null || log "deps: python install failed"
          fi
        else
          DEPS_STATUS="ok"
        fi
        log "deps: python — ${DEPS_STATUS}"
      fi
      ;;
    go)
      if [ -f go.mod ]; then
        go mod download 2>/dev/null && DEPS_STATUS="ok" || DEPS_STATUS="failed"
        log "deps: go — ${DEPS_STATUS}"
      fi
      ;;
    rust)
      if [ -f Cargo.toml ]; then
        cargo fetch 2>/dev/null && DEPS_STATUS="ok" || DEPS_STATUS="failed"
        log "deps: rust — ${DEPS_STATUS}"
      fi
      ;;
    ruby)
      if [ -f Gemfile ]; then
        if [ ! -d vendor/bundle ] && ! bundle check &>/dev/null; then
          DEPS_STATUS="installed"
          bundle install 2>/dev/null || log "deps: bundle install failed"
        else
          DEPS_STATUS="ok"
        fi
        log "deps: ruby — ${DEPS_STATUS}"
      fi
      ;;
    elixir)
      if [ -f mix.exs ]; then
        mix deps.get 2>/dev/null && DEPS_STATUS="ok" || DEPS_STATUS="failed"
        log "deps: elixir — ${DEPS_STATUS}"
      fi
      ;;
    dart)
      if [ -f pubspec.yaml ]; then
        dart pub get 2>/dev/null && DEPS_STATUS="ok" || DEPS_STATUS="failed"
        log "deps: dart — ${DEPS_STATUS}"
      fi
      ;;
    java)
      if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
        DEPS_STATUS="ok"  # Gradle resolves dependencies at build time
        log "deps: java/gradle — ${DEPS_STATUS}"
      elif [ -f pom.xml ]; then
        DEPS_STATUS="ok"  # Maven resolves dependencies at build time
        log "deps: java/maven — ${DEPS_STATUS}"
      fi
      ;;
    *)
      # Other languages: just log
      log "deps: ${lang} — no automated dependency management"
      ;;
  esac
done

if [ "$DEPS_STATUS" = "skipped" ]; then
  log "deps: no recognized project files — skipped"
fi

# --- Summary ---

echo ""
echo "=== Worktree Preflight Summary ==="
echo "git_bootstrapped: ${GIT_BOOTSTRAPPED}"
echo "proot_detected: ${PROOT_DETECTED}"
echo "deps_status: ${DEPS_STATUS}"
echo "stale_worktrees_pruned: ${STALE_COUNT}"
echo "languages_detected: ${PROJECT_LANGS[*]:-none}"
echo "==================================="

if [ "$GIT_BOOTSTRAPPED" = true ]; then
  exit 2
fi
exit 0

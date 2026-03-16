#!/usr/bin/env bash
# check-docs-updated.sh — Validates that docs are updated when workflow files change.
# Designed to run as a PreToolUse(Bash) hook, triggered on git push commands.
# Also callable standalone: check-docs-updated.sh [base-branch]
#
# Exit codes: 0 = pass (docs updated or no workflow changes), 2 = block (docs stale)

set -euo pipefail

# When called as a hook, $1 is the tool input JSON. Detect if this is a push command.
if [ -n "${1:-}" ]; then
  # Check if this is a git push command
  COMMAND="$1"
  if ! echo "$COMMAND" | grep -qE 'git\s+push'; then
    exit 0  # Not a push — skip
  fi
fi

# Must be in the ~/.claude repo
REPO_ROOT="$(git -C ~/.claude rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ "$REPO_ROOT" != "$(cd ~/.claude && pwd)" ]; then
  exit 0  # Not in the workflow repo
fi

cd "$REPO_ROOT"

BASE_BRANCH="${1:-main}"
# If called as hook, base branch is always main
if echo "${1:-}" | grep -q 'git'; then
  BASE_BRANCH="main"
fi

# Get files changed compared to base branch (or HEAD~1 if on main)
if [ "$(git branch --show-current)" = "$BASE_BRANCH" ]; then
  CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null || true)
else
  CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || true)
fi

if [ -z "$CHANGED_FILES" ]; then
  exit 0  # No changes
fi

# Define workflow files that require doc updates
WORKFLOW_CHANGED=false
DOC_CATEGORIES=""

# Check hooks
if echo "$CHANGED_FILES" | grep -qE '^hooks/.*\.sh$'; then
  WORKFLOW_CHANGED=true
  DOC_CATEGORIES="$DOC_CATEGORIES hooks"
fi

# Check skills
if echo "$CHANGED_FILES" | grep -qE '^skills/.*SKILL\.md$'; then
  WORKFLOW_CHANGED=true
  DOC_CATEGORIES="$DOC_CATEGORIES skills"
fi

# Check agents
if echo "$CHANGED_FILES" | grep -qE '^agents/.*\.md$'; then
  WORKFLOW_CHANGED=true
  DOC_CATEGORIES="$DOC_CATEGORIES agents"
fi

# Check settings.json
if echo "$CHANGED_FILES" | grep -qE '^settings\.json$'; then
  WORKFLOW_CHANGED=true
  DOC_CATEGORIES="$DOC_CATEGORIES settings"
fi

if [ "$WORKFLOW_CHANGED" = "false" ]; then
  exit 0  # No workflow files changed
fi

# Check if docs were also updated
DOCS_UPDATED=false

if echo "$CHANGED_FILES" | grep -qE '^README\.md$'; then
  DOCS_UPDATED=true
fi

if echo "$CHANGED_FILES" | grep -qE '^workflow/'; then
  DOCS_UPDATED=true
fi

if [ "$DOCS_UPDATED" = "false" ]; then
  echo "BLOCKED: Workflow files changed (${DOC_CATEGORIES## }) but no documentation updated." >&2
  echo "" >&2
  echo "Changed workflow files:" >&2
  echo "$CHANGED_FILES" | grep -E '^(hooks/|skills/|agents/|settings\.json)' | sed 's/^/  - /' >&2
  echo "" >&2
  echo "Please update the relevant docs before pushing:" >&2
  echo "  - README.md (repository structure, hooks table, skills table)" >&2
  echo "  - workflow/03-architecture.md (repository structure)" >&2
  echo "  - workflow/08-skills-reference.md (if skills changed)" >&2
  echo "  - workflow/09-hooks-and-enforcement.md (if hooks changed)" >&2
  echo "  - workflow/07-agents.md (if agents changed)" >&2
  exit 2
fi

exit 0

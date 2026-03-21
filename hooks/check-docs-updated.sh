#!/usr/bin/env bash
# check-docs-updated.sh — Validates that docs are updated when workflow files change.
# Designed to run as a PreToolUse(Bash) hook, triggered on git push commands.
# Also callable standalone: check-docs-updated.sh [base-branch]
#
# Exit codes: 0 = pass (docs updated or no workflow changes), 2 = block (docs stale)

set -euo pipefail
trap 'echo "HOOK CRASH: $0 line $LINENO" >&2; exit 2' ERR

# Read JSON input from stdin (same pattern as block-dangerous.sh)
INPUT=$(cat)
if [[ "$INPUT" =~ \"command\":\"(([^\"\\]|\\.)*)\" ]]; then
  COMMAND="${BASH_REMATCH[1]}"
  COMMAND="${COMMAND//\\\"/\"}"
  COMMAND="${COMMAND//\\\\/\\}"
else
  # Standalone invocation — treat $1 as base branch
  COMMAND="${1:-git push}"
fi

# Only run on git push commands
if ! echo "$COMMAND" | grep -qE 'git\s+push'; then
  exit 0  # Not a push — skip
fi

# Must be pushing FROM the ~/.claude repo (not some other project)
CWD_REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
CLAUDE_DIR="$(cd ~/.claude && pwd)"
if [ -z "$CWD_REPO" ] || [ "$CWD_REPO" != "$CLAUDE_DIR" ]; then
  exit 0  # Not in the workflow repo
fi

cd "$CWD_REPO"

BASE_BRANCH="main"

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

source ~/.claude/hooks/lib/hook-logger.sh 2>/dev/null || true

if [ "$DOCS_UPDATED" = "false" ]; then
  log_hook_event "check-docs-updated" "blocked" "workflow changed (${DOC_CATEGORIES## }) without doc updates"
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

#!/usr/bin/env bash
set -euo pipefail

# Stop hook: Enforce Anti-Premature Completion Protocol as a hard gate.
#
# When the orchestrator or plan-build-test declares a task complete (all sprints
# done in progress.json), this hook verifies that proper completion evidence exists.
# Without evidence, the agent is BLOCKED from finishing — preventing the "Three
# Completion Lies" (tests pass ≠ works, build complete ≠ runs, items done ≠ verified).
#
# Evidence marker: /tmp/.claude-completion-evidence-${CLAUDE_SESSION_ID}
# Written by orchestrator Step 8.5 / plan-build-test Phase 5.5 after performing
# full verification (plan re-read, acceptance criteria citation, dev server check,
# non-privileged user testing).
#
# Exit codes:
#   0 — completion evidence exists (or no completed tasks to verify)
#   2 — task declared complete without proper verification evidence

# Check for jq
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Read JSON input from stdin
INPUT=$(cat)

# Check stop_hook_active — prevent infinite loop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Resolve project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Skip if no task directory exists
TASK_DIR="$PROJECT_DIR/docs/tasks"
if [ ! -d "$TASK_DIR" ]; then
  exit 0
fi

# Check for recently completed tasks (progress.json with all sprints "complete"
# AND the file was modified in the last 60 minutes — meaning it was just marked done)
RECENTLY_COMPLETED=false
COMPLETED_PRD=""

while IFS= read -r pjson; do
  if [ -f "$pjson" ]; then
    # Check if ALL sprints are complete
    INCOMPLETE=$(jq '[.sprints[] | select(.status != "complete")] | length' "$pjson" 2>/dev/null || echo "0")
    TOTAL=$(jq '.sprints | length' "$pjson" 2>/dev/null || echo "0")

    if [ "$TOTAL" -gt 0 ] && [ "$INCOMPLETE" -eq 0 ]; then
      # Check if this file was recently modified (within last 60 min)
      if [ "$(find "$pjson" -mmin -60 2>/dev/null | wc -l)" -gt 0 ]; then
        RECENTLY_COMPLETED=true
        COMPLETED_PRD="$pjson"
        break
      fi
    fi
  fi
done < <(find "$TASK_DIR" -name "progress.json" -type f 2>/dev/null)

if [ "$RECENTLY_COMPLETED" = false ]; then
  exit 0
fi

# Check for completion evidence marker
EVIDENCE_MARKER="/tmp/.claude-completion-evidence-${CLAUDE_SESSION_ID:-unknown}"

if [ -f "$EVIDENCE_MARKER" ]; then
  # Verify the evidence file has required fields
  VALID=true

  # Check required fields exist in the evidence file
  for field in "plan_reread" "dev_server_verified" "non_privileged_user_tested"; do
    if ! grep -q "$field" "$EVIDENCE_MARKER" 2>/dev/null; then
      VALID=false
      break
    fi
  done

  if [ "$VALID" = true ]; then
    exit 0  # Evidence exists and is valid
  fi
fi

# No evidence — BLOCK
{
  echo "BLOCKED: Anti-Premature Completion Protocol — task declared complete without verification evidence."
  echo ""
  echo "Completed task: $COMPLETED_PRD"
  echo ""
  echo "Before claiming completion, you MUST:"
  echo "  1. Re-read the original plan/spec file (not from memory)"
  echo "  2. Enumerate ALL remaining unchecked items"
  echo "  3. Cite specific evidence for each acceptance criterion"
  echo "  4. Start the dev server and verify content (not just HTTP 200)"
  echo "  5. Test as a non-privileged user (not admin/superuser)"
  echo ""
  echo "After verification, write evidence to: $EVIDENCE_MARKER"
  echo "Required fields: plan_reread, dev_server_verified, non_privileged_user_tested"
  echo ""
  echo "Evidence format (write with bash):"
  echo "  cat > $EVIDENCE_MARKER << 'EOF'"
  echo "  plan_reread: true"
  echo "  acceptance_criteria_cited: true"
  echo "  dev_server_verified: true"
  echo "  non_privileged_user_tested: true"
  echo "  timestamp: \$(date -Iseconds)"
  echo "  EOF"
} >&2
exit 2

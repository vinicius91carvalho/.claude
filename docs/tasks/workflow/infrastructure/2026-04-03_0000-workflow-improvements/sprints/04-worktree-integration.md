# Sprint 4: Worktree Cleanup & CLAUDE.md Integration

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 4 of 4
- **Depends on:** Sprint 2, Sprint 3
- **Batch:** 3 (sequential — needs Sprint 2's settings.json changes and Sprint 3's skill)
- **Model:** sonnet
- **Estimated effort:** M

## Objective

Add worktree cleanup guarantee via Stop hook and update CLAUDE.md and plan-build-test with all new capabilities from this PRD.

## File Boundaries

### Creates (new files)

- `/root/.claude/hooks/cleanup-worktrees.sh` — Stop hook that prunes stale worktrees and merged sprint branches

### Modifies (can touch)

- `/root/.claude/settings.json` — add cleanup-worktrees.sh to Stop hooks array (Sprint 2 already added cleanup-artifacts.sh)
- `/root/.claude/CLAUDE.md` — add artifact management rules, research skill reference, worktree cleanup docs
- `/root/.claude/skills/plan-build-test/SKILL.md` — add Phase 6 worktree cleanup step

### Read-Only (reference but do NOT modify)

- `/root/.claude/hooks/cleanup-artifacts.sh` — pattern reference for Stop hook structure
- `/root/.claude/skills/research/SKILL.md` — reference for CLAUDE.md skill documentation
- `/root/.claude/agents/orchestrator.md` — reference for existing worktree cleanup patterns
- `/root/.claude/hooks/verify-worktree-merge.sh` — reference for worktree safety patterns

### Shared Contracts (consume from prior sprints or PRD)

- Artifact Path Convention: `.artifacts/{category}/YYYY-MM-DD_HHmm/{filename}`
- Research Output Format (from Sprint 3)
- Cache File Convention (from Sprint 1)
- All contracts from PRD Section 12

### Consumed Invariants (from INVARIANTS.md)

- Worktree safety — NEVER delete unmerged branches
- Hook exit codes — exit 0 always (cleanup is best-effort, never blocks)

## Tasks

### Worktree Cleanup Hook

- [ ] Create `~/.claude/hooks/cleanup-worktrees.sh` with proper shebang, set -euo pipefail, and trap
- [ ] Read JSON input from stdin (same pattern as other Stop hooks)
- [ ] Skip if not in a git repository (`git rev-parse --git-dir` check)
- [ ] Skip if project dir is $HOME or /root
- [ ] Run `git worktree prune` to remove stale worktree references
- [ ] List remaining worktrees: `git worktree list --porcelain`
- [ ] For each non-main worktree: check if its branch is merged into current branch
- [ ] For merged worktrees: remove worktree (`git worktree remove <path>`) and delete branch (`git branch -d <branch>`)
- [ ] For unmerged worktrees: log a WARNING but do NOT delete (safety invariant)
- [ ] Log all actions via hook-logger
- [ ] Always exit 0 — cleanup is best-effort, never blocks

### Settings.json Update

- [ ] Add `cleanup-worktrees.sh` to settings.json Stop hooks array
- [ ] Position it AFTER cleanup-artifacts.sh and BEFORE compound-reminder.sh
- [ ] Verify resulting JSON is valid

### CLAUDE.md Updates

- [ ] Add `.artifacts/` convention to the "Global Rules" section:
  - All generated artifacts (screenshots, videos, reports, runtime outputs) go to `.artifacts/{category}/YYYY-MM-DD_HHmm/`
  - Categories: playwright, execution, research, configs, reports
  - `.artifacts/` is auto-added to `.gitignore` by cleanup hook
  - Never save Playwright or runtime tool outputs to project root
- [ ] Add `/research` skill to the "Skill Selection Decision Tree":
  - "Need deep research or multi-perspective analysis?" -> `/research`
  - Between "Build a feature" and "Ship what I've built"
- [ ] Add worktree cleanup guarantee to "Workflow" section or "Worktree Isolation" section:
  - Stop hook runs `git worktree prune` + removes merged sprint branches on every task end
  - Unmerged branches are preserved with warning
  - This guarantees cleanup even if orchestrator crashes mid-work
- [ ] Add `/research` to the autonomous pipeline documentation where appropriate
- [ ] Update the skills list comment near "The Full Pipeline" to include `/research`
- [ ] Add hook performance note: hooks now use caching for faster execution (reference Sprint 1)

### Plan-Build-Test Phase 6 Update

- [ ] Read current plan-build-test/SKILL.md Phase 6 (Learning & Self-Improvement)
- [ ] Add Phase 6.5 (or append to Phase 6): "Worktree & Artifact Cleanup"
  - Run `git worktree prune`
  - Remove any merged sprint/* branches
  - Verify `git worktree list` shows only main worktree
  - Move any stray artifacts from project root to `.artifacts/`
  - Log cleanup results to session learnings

## Acceptance Criteria

- [ ] `cleanup-worktrees.sh` runs `git worktree prune` on every task end
- [ ] Merged sprint branches are automatically cleaned up
- [ ] Unmerged branches are NEVER deleted — only a warning is logged
- [ ] `git worktree list` shows only the main worktree after Stop hook runs (when all work is merged)
- [ ] settings.json Stop hooks array includes both cleanup-artifacts.sh and cleanup-worktrees.sh in correct order
- [ ] CLAUDE.md documents `.artifacts/` convention in Global Rules
- [ ] CLAUDE.md includes `/research` in Skill Selection Decision Tree
- [ ] CLAUDE.md documents worktree cleanup guarantee
- [ ] plan-build-test SKILL.md includes Phase 6.5 for cleanup
- [ ] All CLAUDE.md changes are accurate and consistent with actual implementation from Sprints 1-3

## Verification

- [ ] Create a test worktree, merge its branch, run hook — worktree should be removed
- [ ] Create a test worktree with unmerged changes, run hook — worktree should be preserved with warning
- [ ] Run `git worktree list` after hook — should show only main
- [ ] settings.json is valid JSON with correct hook ordering
- [ ] CLAUDE.md changes are syntactically correct markdown
- [ ] plan-build-test SKILL.md changes are consistent with existing phase structure
- [ ] Read CLAUDE.md end-to-end to verify no contradictions with new content

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

### Current Worktree Cleanup (Gaps)

The orchestrator has two cleanup points:
1. **Step 0 (Preflight):** `git worktree prune` + remove orphan sprint/* branches — runs at START of orchestrator
2. **Step 6.5 (Post-merge):** `git worktree prune` + delete merged sprint branches — runs after successful merge

**Gaps:**
- No cleanup if orchestrator crashes mid-work (between Step 0 and Step 6.5)
- No cleanup at session end if user doesn't run orchestrator
- No cleanup for worktrees from manual `git worktree add` usage
- No cleanup between sessions (accumulation over time)

The Stop hook fills all these gaps by running on every task end, regardless of what happened during the task.

### Settings.json Stop Hook Order (Final)

After Sprint 2 and Sprint 4, the Stop hooks array should be:
```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "~/.claude/hooks/end-of-turn-typecheck.sh" },
      { "type": "command", "command": "~/.claude/hooks/cleanup-artifacts.sh" },
      { "type": "command", "command": "~/.claude/hooks/cleanup-worktrees.sh" },
      { "type": "command", "command": "~/.claude/hooks/compound-reminder.sh" },
      { "type": "command", "command": "~/.claude/hooks/verify-completion.sh" }
    ]
  }
]
```

Rationale for ordering:
1. Typecheck first (most important gate — catches type errors)
2. Artifact cleanup (organize files before any reporting)
3. Worktree cleanup (clean git state before compound review)
4. Compound reminder (learning capture — needs clean state)
5. Verify completion (final gate — everything should be done)

### CLAUDE.md Edit Locations

Key sections to modify:
1. **Skill Selection Decision Tree** (~line 392): Add `/research` branch
2. **The Full Pipeline** (~line 384): Add `/research` to skill list
3. **Global Rules** (~line 505+): Add artifact management subsection
4. **Worktree Isolation** (~line 288): Add cleanup guarantee note
5. **Deterministic Safety via Hooks** (~line 340): Document new Stop hooks

### Safety Invariant: Never Delete Unmerged Work

The cleanup hook MUST check merge status before deletion:
```bash
# Safe: only delete if branch is merged
git branch --merged | grep 'sprint/' | while read branch; do
  git branch -d "$branch"  # -d (not -D) fails on unmerged
done

# NEVER use -D (force delete)
# NEVER delete worktrees whose branch has unmerged commits
```

Using `git branch -d` (lowercase) instead of `-D` (uppercase) provides a safety net: git will refuse to delete a branch with unmerged changes.

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

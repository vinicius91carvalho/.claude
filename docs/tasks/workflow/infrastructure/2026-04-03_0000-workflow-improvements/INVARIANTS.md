# Architecture Invariant Registry: Workflow Improvements

## Hook Exit Code Contract

- **Owner:** settings.json (hook configuration)
- **Preconditions:** Hook receives valid JSON on stdin
- **Postconditions:** Exit 0 = pass/skip, Exit 2 = violation/block
- **Invariants:** Cleanup hooks (cleanup-artifacts, cleanup-worktrees) ALWAYS exit 0. Gate hooks (typecheck, check-invariants, verify-completion) may exit 2 to block.
- **Verify:** `grep -c 'exit 0' /root/.claude/hooks/cleanup-artifacts.sh /root/.claude/hooks/cleanup-worktrees.sh 2>/dev/null | grep -v ':0$' | wc -l | grep -q '^[2-9]'`
- **Fix:** Ensure cleanup hooks end with `exit 0` and catch all errors

## Artifact Path Structure

- **Owner:** cleanup-artifacts.sh (defines the convention)
- **Preconditions:** Project directory exists and is writable
- **Postconditions:** All stray artifacts in project root are moved to `.artifacts/{category}/YYYY-MM-DD_HHmm/`
- **Invariants:** Only project root files are moved. Subdirectory files are never touched. Category is one of: playwright, execution, research, configs, reports.
- **Verify:** `test -z "$(find "${CLAUDE_PROJECT_DIR:-.}" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) 2>/dev/null)"`
- **Fix:** Run cleanup-artifacts.sh manually or move files to `.artifacts/` by hand

## Cache Directory

- **Owner:** hooks/lib/project-cache.sh
- **Preconditions:** `~/.claude/hooks/logs/` directory exists
- **Postconditions:** `~/.claude/hooks/logs/.cache/` exists and is writable
- **Invariants:** Cache files are transient and can be deleted without data loss. Hooks must fall through to uncached behavior if cache is missing.
- **Verify:** `test -d /root/.claude/hooks/logs/.cache || echo "cache dir missing but hooks should auto-create"`
- **Fix:** `mkdir -p /root/.claude/hooks/logs/.cache`

## Worktree Safety

- **Owner:** cleanup-worktrees.sh
- **Preconditions:** Project is a git repository
- **Postconditions:** Stale worktrees pruned, merged sprint branches deleted. Unmerged branches NEVER deleted.
- **Invariants:** Uses `git branch -d` (safe delete, fails on unmerged) NEVER `git branch -D` (force delete). Logs warnings for unmerged branches.
- **Verify:** `grep -q '\-D' /root/.claude/hooks/cleanup-worktrees.sh 2>/dev/null && echo "VIOLATION: uses -D flag" && exit 1 || true`
- **Fix:** Replace any `git branch -D` with `git branch -d` in cleanup-worktrees.sh

## Settings.json Hook Ordering

- **Owner:** settings.json
- **Preconditions:** All referenced hook scripts exist at their paths
- **Postconditions:** Stop hooks execute in order: typecheck -> cleanup-artifacts -> cleanup-worktrees -> compound-reminder -> verify-completion
- **Invariants:** Gate hooks (typecheck, verify-completion) must run before/after cleanup hooks. Cleanup hooks must run before compound-reminder (clean state for learning capture).
- **Verify:** `jq -r '.hooks.Stop[0].hooks[].command' /root/.claude/settings.json 2>/dev/null | head -5 | grep -q 'end-of-turn-typecheck'`
- **Fix:** Reorder Stop hooks array in settings.json to match the documented order

## Research Skill Model Assignment

- **Owner:** skills/research/SKILL.md
- **Preconditions:** N/A
- **Postconditions:** Researchers use sonnet, synthesizer uses opus
- **Invariants:** Researcher agents specify `model: "sonnet"`. Synthesizer agent specifies `model: "opus"`. Minimum 5 researcher agents spawned in parallel.
- **Verify:** `grep -c 'sonnet' /root/.claude/skills/research/SKILL.md 2>/dev/null | grep -q '[1-9]' && grep -c 'opus' /root/.claude/skills/research/SKILL.md 2>/dev/null | grep -q '[1-9]'`
- **Fix:** Update model specifications in SKILL.md to match the invariant

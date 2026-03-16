# Workflow Changelog

Track every change to CLAUDE.md, skills, agents, and hooks with date, what changed, why, and source.

## 2026-03-16 — Workflow Audit Fixes (5 recommendations)

### Changes
- **Created:** `~/.claude/hooks/validate-i18n-keys.sh` — Generic i18n key validation script. Auto-detects next-intl/react-intl/i18next projects, cross-validates all locale JSON files have matching keys. Exits 0 for non-i18n projects.
- **Created:** `~/.claude/hooks/verify-worktree-merge.sh` — Post-merge verification for worktree branches. Detects files modified by both current and previous sprints to prevent silent overwrites.
- **Modified:** `ship-test-ensure/SKILL.md` — Phase 5 (PageSpeed) now optional: only runs if `pages_to_audit` is configured. Added API key support (`PSI_API_KEY` env var). 429 errors no longer block the pipeline. Added i18n validation to Phase 0.3 verification gate.
- **Modified:** `orchestrator.md` — Step 6.2 now runs `verify-worktree-merge.sh` before each merge to detect potential overwrites.
- **Modified:** `apps/website/package.json` — Dev script now clears `.next` cache on start (`rm -rf .next && next dev`).

### Why
- P1: Missing i18n keys caused 17 runtime errors not caught by build/lint/types (error-registry: MISSING_MESSAGE pattern)
- P1: Worktree merge overwrite is the highest-recurrence error (3x in one session, error-registry)
- P2: PSI API quota (429) blocked Phase 5 unnecessarily — should be optional since not all projects need Lighthouse
- P2: Stale .next cache caused MIME type errors requiring manual investigation (error-registry)
- P3: Haiku underutilization noted but not actioned (needs conscious delegation in future sessions)

### Source
- /workflow-audit after 2 sessions, 2026-03-16

---

## 2026-03-14 — SimUser AI Refinement Build Learnings

### Changes
- **Added:** `~/.claude/projects/-root-projects-simuser-ai/memory/feedback_worktree_merge.md` — worktree merge pattern causes silent overwrite of previous sprint changes in shared files
- **Updated:** `error-registry.json` — 3 new entries (worktree merge overwrite, large JSON context overflow, PRoot serve failure)
- **Updated:** `model-performance.json` — first real data points: sonnet 1/1 implementation, 0/1 orchestration; opus 2/3 complex_refactoring

### Why
- Worktree merge overwrite happened 3 times in one session — must be documented to prevent in future builds
- Large JSON i18n files (500+ lines) consistently caused agent context overflow — pattern needs recognition
- Model performance data now has real numbers for adaptation threshold checks

### Source
- /compound after simuser-ai website refinement build (5 sprints), 2026-03-14

---

## 2026-03-14 — Maturity & Robustness Audit (v4)

### Changes
- **Modified:** `block-dangerous.sh` — Added `is_rm_rf()` helper to catch all flag forms (`rm -r -f`, `rm --recursive --force`, etc.). Added hard block for system directories (`/etc`, `/usr`, `/var`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/opt`, `/root`, `/boot`, `/sys`, `/proc`, `/dev`, `/srv`, `/mnt`). Added soft block for `git stash drop/clear`.
- **Modified:** `proot-preflight.sh` — Removed dead `MARKER` variable (PID-specific marker was created but never checked; only `SESSION_MARKER` was used).
- **Modified:** `end-of-turn-typecheck.sh` — Added `typecheck.log` creation on first run. Previous behavior: `find -newer` against non-existent file had undefined behavior, could skip typecheck or trigger unnecessary runs.
- **Modified:** `compound-reminder.sh` — Added jq dependency check (exit 0 silently if missing). Previously, missing jq caused silent fallthrough making compound-reminder ineffective without any warning.
- **Modified:** `post-edit-quality.sh` — Changed jq dependency check from error (exit 1) to graceful skip (exit 0). Auto-formatting is non-critical; erroring on every non-code edit when jq is missing is wasteful.
- **Modified:** `verification-gates.md` — Removed stale "sprint-executor" from Gate 2 (Dev Server) and Gate 3 (Content Verification) headers. Sprint-executors don't run these gates since v3, but the doc wasn't updated.
- **Created:** `docs/project-claude-md-template.md` — Standardized template for project CLAUDE.md with Execution Config. All skills reference "Execution Config from project CLAUDE.md" but no template existed for new projects.

### Why
- P0: `rm --recursive --force /etc` and `rm -r -f /usr` bypassed block-dangerous.sh (only combined `-rf` was caught)
- P0: `git stash drop` (destructive, irreversible) was not caught by any hook
- P1: First-run typecheck had undefined behavior — `find -newer nonexistent_file` is platform-dependent
- P1: compound-reminder silently disabled without jq — the "blocking compound" promise was hollow on systems without jq
- P2: post-edit-quality errored (exit 1) on every markdown/JSON edit when jq was missing — unnecessary noise
- P2: verification-gates.md contradicted actual v3 behavior (stale docs cause confusion)
- P2: No project template meant every new project required reverse-engineering the Execution Config format from skill files

### Round 2 Changes (same audit)
- **Modified:** `block-dangerous.sh` — Fixed `git push -u origin main` bypass. Old regex required exactly one token between `push` and `main`; `-u origin` has two tokens. New pattern matches `git push ... main` regardless of flags.
- **Modified:** `ship-test-ensure/SKILL.md` — Fixed Phase 1 step ordering. Old: commit on current branch (main) then create feature branch (PR shows no diff). New: create branch first, then commit on branch. Also moved PRE_DEPLOY_SHA capture to before the commit (was after, giving wrong rollback point).
- **Modified:** `CLAUDE.md` — Fixed "Deterministic Safety via Hooks" section: accurately describes what each hook enforces (was overstating Anti-Goodhart enforcement by hooks; it's enforced by agent steps, not hooks). Added Notification hook mention. Updated hard/soft block lists to match actual hook behavior (system directories, git stash drop/clear).
- **Modified:** `CLAUDE.md` — Clarified Playwright exception: added proot-distro note (use `browser_snapshot` only, never `browser_take_screenshot`). Previous wording was ambiguous about whether Playwright works in proot.
- **Modified:** `CLAUDE.md` — Updated proot-distro section: accurately describes the three-layer proot handling (settings.json env, proot-preflight.sh warnings, worktree-preflight.sh setup). Previous version credited proot-preflight.sh for setting env vars it doesn't set.
- **Modified:** `settings.json` — Added `NODE_OPTIONS`, `CHOKIDAR_USEPOLLING`, `WATCHPACK_POLLING` to env section. These were documented as "ALWAYS set" but only set by orchestrator/sprint-executor during sprint runs. Now set globally for all Bash commands.

### Source
- Full workflow audit, 2026-03-14

---

## 2026-03-14 — Reliability & Evolution Audit (v3)

### Changes
- **Modified:** `compound-reminder.sh` — changed from advisory (exit 0) to BLOCKING (exit 2). The learning loop is non-negotiable.
- **Modified:** `sprint-executor` agent — removed redundant dev server smoke test (Steps 12-13 → Steps 11-13). Sprint-executors now do static verification only; orchestrator handles dev server after merge. Saves 3-5 dev server cycles per project.
- **Modified:** `sprint-executor` agent — added `model_performance` section to return summary (model_requested, first_try_success, task_types, retry_categories) for accurate evolution tracking.
- **Modified:** `orchestrator` agent — added Step 6.4 (file boundary validation pre-merge), Step 6.6 (code-reviewer agent spawn), sprint_model_performance in return metrics.
- **Modified:** `/compound` SKILL — added Step 4c (feedback capture from user corrections), updated Step 7a to ALWAYS write to error-registry on first occurrence (not just cross-project), added JSON safety (backup + validation) for evolution file writes, added `approaches_that_failed` to error-registry entries.
- **Modified:** `/plan` SKILL — spec self-evaluator now spawns a separate haiku agent instead of self-evaluation (prevents grading own homework).
- **Modified:** `/plan-build-test` SKILL — added Phase 0 Step 0.0 (proactive session-learnings file creation), added Phase 4.1 (code-reviewer agent before simplification).
- **Modified:** `/ship-test-ensure` SKILL — all deploys now go through CI/CD (branch → PR → merge, never push directly to main). Added proot detection for Lighthouse Phase 5 with configurable thresholds. Rollback also via PR.
- **Modified:** `CLAUDE.md` — removed push-to-main exception, added CI/CD rule, trimmed duplicated content (sprint JSON example, proot error table, session learnings schema, detailed self-improvement steps) with pointers to authoritative source files. Net reduction ~2.5KB.
- **Modified:** `error-registry.json` — added `approaches_that_failed` field to schema for negative learning.

### Why
- Comprehensive workflow audit identified 12 gaps across reliability, cost, and evolution
- P0: Evolution loop never ran because compound was unenforced (advisory hook)
- P1: Triple dev server verification wasted 7-14 min per project in proot
- P1: User corrections (richest learning signal) were not captured in evolution data
- P2: Direct push-to-main bypassed CI/CD safety gates
- P2: Lighthouse/proot contradiction could cause infinite fix loops
- P2: No JSON validation meant one bad write could corrupt entire learning system
- P2: Model tracking had no actual data source (sprint-executors didn't report model performance)
- P3: code-reviewer agent existed but was never wired into any workflow
- P3: File boundary enforcement was honor system with no validation
- P3: Self-graded spec evaluation was unreliable

### Source
- User-initiated full system audit, 2026-03-14

---

## 2026-03-14 — Workflow Evolution System (v2)

### Changes
- **Added:** `~/.claude/evolution/` directory — cross-project learning persistence
  - `error-registry.json` — structured error pattern database across projects
  - `model-performance.json` — tracks model success rates for adaptive model assignment
  - `workflow-changelog.md` — this file; tracks system evolution with provenance
  - `session-postmortems/` — structured post-session analysis
- **Modified:** `/compound` SKILL — added Steps 7-8 (cross-project promotion, session postmortem)
- **Modified:** `/ship-test-ensure` SKILL — PRE_DEPLOY_SHA capture, rollback protocol (auto `git revert`), compound integration in Phase 6
- **Modified:** `/plan-build-test` SKILL — metrics in progress.json, structured session learnings, targeted re-verification
- **Modified:** `orchestrator` agent — model changed from opus to sonnet (deterministic checklist doesn't need opus), metrics capture
- **Modified:** `sprint-executor` agent — metrics capture in return summary
- **Modified:** `settings.json` — added compound-reminder stop hook
- **Modified:** `end-of-turn-typecheck.sh` — skip when no code was written in current turn
- **Modified:** `CLAUDE.md` — updated Model Assignment Matrix, added Evolution section, adaptive retry budget, structured session learnings schema
- **Created:** `/workflow-audit` skill — periodic self-audit of workflow effectiveness
- **Created:** `compound-reminder.sh` — stop hook warning when compound wasn't run

### Why
- User review identified that the workflow learns per-project but not across projects
- Compound (the evolutionary engine) was optional and unenforced
- No metrics meant no evidence-based adaptation
- Model assignment was static despite varying success rates
- Cost inefficiencies: opus for orchestration, format-per-edit, typecheck on non-code turns

### Source
- User-initiated workflow review, 2026-03-14

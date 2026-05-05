# Sprint 2: Add `aggressive_fix_loop` mode to /plan-build-test Phase 5.7

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 2 of 3
- **Depends on:** None
- **Batch:** 1 (parallel with Sprint 1)
- **Model:** sonnet
- **Estimated effort:** S

## Objective

Extend `/plan-build-test` Phase 5.7 ("Handle Failures") to recognize an `aggressive-fix-loop` mode that raises the `logic` failure retry budget from 2 to 4, while leaving `transient`, `environment`, and `config` budgets untouched.

## File Boundaries

### Creates (new files)

- (none — modifying existing skill only)

### Modifies (can touch)

- `/root/.claude/skills/plan-build-test/SKILL.md` — add a `## Mode Flags` section (or extend if already added by Sprint 1's parallel work — coordinate via the section name only, no overlapping line edits since they edit different files); modify Phase 5.7 to insert a conditional that picks the larger budget for `logic` when `aggressive-fix-loop` is in `$CLAUDE_PIPELINE_MODE`. Document the budget-table-as-source-of-truth.

### Read-Only (reference but do NOT modify)

- `/root/.claude/CLAUDE.md` — adaptive retry budget table (in `rules/quality.md` actually — the global rule that defines the canonical per-category budgets)
- `/root/.claude/rules/quality.md` — for the canonical budget definitions
- `/root/.claude/skills/ship-test-ensure/SKILL.md` — for parallel-edit reference; do not modify
- `../spec.md` — PRD context

### Shared Contracts (consume from prior sprints or PRD)

- `CLAUDE_PIPELINE_MODE` env var (PRD Section 12) — uses the same env var as Sprint 1 but a different value (`aggressive-fix-loop`)
- Per-category retry budget table (canonical: `transient: 5, logic: 2, environment: 1, config: 3`); aggressive override: `logic: 4`
- Each retry under aggressive mode MUST use a different fix approach (existing protocol already says "try a different approach" after retry 2; aggressive mode gives the agent more attempts to do so)

### Consumed Invariants (from INVARIANTS.md)

- `Aggressive-fix-loop budget table` — this sprint owns the table; the SKILL.md is the single source of truth for per-category aggressive budgets
- Verify command: `grep -A 10 'aggressive-fix-loop' ~/.claude/skills/plan-build-test/SKILL.md | grep -E 'logic.*4|logic:.*4'`

## Tasks

- [ ] Read `~/.claude/skills/plan-build-test/SKILL.md` Phase 5.7 in full to identify exactly where the per-category budget logic lives (table, prose, or both). Locate the canonical numbers `transient: 5, logic: 2, environment: 1, config: 3`.
- [ ] Add (or extend if Sprint 1 didn't touch this file — Sprint 1 does NOT touch this file per File Boundaries) a `## Mode Flags` section near the top of the SKILL.md documenting `CLAUDE_PIPELINE_MODE` recognized values. List both `staging-only` and `aggressive-fix-loop` (the wrapper can set both simultaneously).
- [ ] Modify Phase 5.7 budget logic to include a conditional: when `$CLAUDE_PIPELINE_MODE` contains `aggressive-fix-loop`, treat the `logic` failure budget as `4` instead of `2`. Other categories remain unchanged. Document this with a small table showing default vs. aggressive budgets side-by-side.
- [ ] Add a one-paragraph note in Phase 5.7 explaining that aggressive mode does NOT raise `environment` retries (env doesn't change between retries) and does NOT remove the cap entirely (budget is still bounded; "no cap" is a danger flagged in the PRD). Reference the danger definition in the PRD Section 2.
- [ ] Add a requirement that under aggressive mode each retry beyond the second logic attempt MUST log its "different approach" rationale to session-learnings (the existing format from `~/.claude/rules/quality.md`).

## Acceptance Criteria

- [ ] AC1: `## Mode Flags` section exists in `/plan-build-test` SKILL.md and lists both `staging-only` (cross-reference) and `aggressive-fix-loop` with their meanings.
- [ ] AC2: Phase 5.7 contains a budget table showing the default and aggressive-mode budgets side-by-side, with `logic: 2 → 4` as the only delta.
- [ ] AC3: `grep -A 10 'aggressive-fix-loop' ~/.claude/skills/plan-build-test/SKILL.md | grep -E 'logic.*4'` returns at least one match.
- [ ] AC4: A reviewer reading Phase 5.7 can answer "what is the maximum number of `logic`-category retries under aggressive mode?" with `4` from a single passage of the SKILL.md.
- [ ] AC5: The session-learnings logging requirement is documented in Phase 5.7, with the format-pointer to `~/.claude/rules/quality.md`.

## Verification

- [ ] Build passes (N/A — markdown only)
- [ ] Lint passes (N/A — markdown)
- [ ] Type-check passes (N/A — markdown)
- [ ] Sprint-specific tests pass — run the verify command from "Consumed Invariants" and AC3 grep; both must produce matches.

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

The user's adaptive retry policy from `~/.claude/rules/quality.md`:
> - `transient` failures (network, timeout, flaky test) → up to 5 retries
> - `logic` failures (wrong approach, broken implementation) → max 2, then try different approach
> - `environment` failures (proot limitation, missing binary) → 1 retry, then mark BLOCKED
> - `config` failures (bad setting, wrong flag) → max 3 retries

The autonomous wrapper's value proposition is "fix all errors and finish" — but only `logic` failures benefit from more attempts, because they're the category where "try a different approach" is actually a fresh signal each iteration. `transient` already has 5; raising it doesn't help. `environment` retries don't help because the env doesn't change between retries (the proot environment lacks the same things attempt 1 and attempt N). `config` is already 3, which is enough for the typical "wrong flag → try the next plausible flag" loop.

So `aggressive-fix-loop` mode raises ONLY `logic` from 2 to 4. This gives the executor agent up to 4 distinct fix approaches before declaring BLOCKED. The "different approach" requirement is enforced by session-learnings logging — if the agent retries the same approach twice, that's a process violation visible in the artifact.

The mode is opt-in via env var. When invoked from `/autonomous-staging`, the env var is set automatically. When invoked from a direct user `/plan-build-test`, the env var is unset and default budgets apply — preserving existing behavior.

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

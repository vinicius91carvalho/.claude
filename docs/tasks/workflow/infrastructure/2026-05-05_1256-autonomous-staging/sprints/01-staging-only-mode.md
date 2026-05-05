# Sprint 1: Add `staging_only` mode to /ship-test-ensure

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 1 of 3
- **Depends on:** None
- **Batch:** 1 (parallel with Sprint 2)
- **Model:** sonnet
- **Estimated effort:** S

## Objective

Add a hard-structural `staging-only` mode to `/ship-test-ensure` so a parent wrapper can ship through staging while making any production-deploy code path unreachable by exit-99 guard.

## File Boundaries

### Creates (new files)

- (none — modifying existing skill only)

### Modifies (can touch)

- `/root/.claude/skills/ship-test-ensure/SKILL.md` — add `## Mode Flags` section near top documenting `CLAUDE_PIPELINE_MODE` recognized values; add a hard guard at the very top of "Phase 4: Deploy to Production" (or whatever the production-deploy phase header is named) that exits 99 with message `PROD-FORBIDDEN: staging-only mode active` if `$CLAUDE_PIPELINE_MODE` contains the substring `staging-only`; document the env-var contract.

### Read-Only (reference but do NOT modify)

- `/root/.claude/skills/plan-build-test/SKILL.md` — for cross-reference of the Phase numbering and mode-flag style; do not edit
- `/root/.claude/CLAUDE.md` — value hierarchy and "Stop Hook Authorization Protocol" — for tone alignment of the safety guard
- `../spec.md` — PRD context (read once at sprint start, then trust the sprint spec)

### Shared Contracts (consume from prior sprints or PRD)

- `CLAUDE_PIPELINE_MODE` env var format (PRD Section 12): comma-separated subset of `{staging-only, aggressive-fix-loop}`
- Exit code convention: `99` for "intentional safety guard exit" (distinct from any test/lint/deploy failure exit)

### Consumed Invariants (from INVARIANTS.md)

- `staging_only mode unreachability of Phod 4` — this sprint MUST satisfy: "guard is the first non-comment line of the production-deploy phase, exits before any deploy command"
- Verify command: `grep -A 5 -i 'phase.*4.*production\|deploy.*to.*production' ~/.claude/skills/ship-test-ensure/SKILL.md | grep -E 'staging-only.*exit|PROD-FORBIDDEN'`

## Tasks

- [ ] Read `~/.claude/skills/ship-test-ensure/SKILL.md` end-to-end to identify the exact Phase that triggers production deployment (header text, its position in the file, what comes immediately before/after).
- [ ] Insert a top-level `## Mode Flags` section after the skill's frontmatter and intro paragraph, documenting `CLAUDE_PIPELINE_MODE` and the two values it currently recognizes (`staging-only`, `aggressive-fix-loop`). Use comma-separated combination syntax (`staging-only,aggressive-fix-loop`).
- [ ] At the very start of the production-deploy phase (immediately under its `## Phase N: ...` header, before any other prose or commands), insert a guard block (bash code fence). The guard must: (a) detect `staging-only` substring in `$CLAUDE_PIPELINE_MODE`, (b) print `PROD-FORBIDDEN: staging-only mode active — refusing to enter <Phase name>`, (c) `exit 99`. Code must be copy-pasteable into the orchestrator context as-is.
- [ ] Add a single short note in the "Autonomous mode" or equivalent section that production gate (Phase 4.1 confirmation prompt) is now ALSO inert under `staging-only` — the guard fires before the prompt is reached, so the skill never asks under that mode. Cross-reference the new `## Mode Flags` section.
- [ ] Document return codes: `exit 0` after Phase 3 success under `staging-only` mode is the success signal that the wrapper consumes.

## Acceptance Criteria

- [ ] AC1: `## Mode Flags` section exists in the SKILL.md, lists both `staging-only` and `aggressive-fix-loop`, and explains comma-separated combination.
- [ ] AC2: The first non-prose content under the production-deploy phase header is the guard bash block (no commands or prose between header and guard).
- [ ] AC3: Running `grep -A 5 -i 'phase.*4.*production\|deploy.*to.*production' ~/.claude/skills/ship-test-ensure/SKILL.md` shows the guard with `staging-only` and `exit 99`.
- [ ] AC4: Running `grep -c 'CLAUDE_PIPELINE_MODE' ~/.claude/skills/ship-test-ensure/SKILL.md` returns at least 3 (mode-flag section, guard, autonomous-mode note).
- [ ] AC5: A semantic dry-read of the guard by a reviewer (or a sub-agent prompted "could this skill enter prod under CLAUDE_PIPELINE_MODE=staging-only?") returns NO.

## Verification

- [ ] Build passes (N/A — markdown only; treat as "no broken markdown reference / link" check)
- [ ] Lint passes (N/A — markdown)
- [ ] Type-check passes (N/A — markdown)
- [ ] Sprint-specific tests pass — run the verify command from "Consumed Invariants" and the AC3 grep; both must produce matches.

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

The existing `/ship-test-ensure` skill already has Phase 4.1 as the "production deploy gate" — a manual confirmation prompt that's described as "never skip, even in autonomous mode." This sprint does NOT remove that prompt. Instead, it adds a *prior* guard so that the prompt is unreachable when the wrapper invoked the skill in staging-only mode. The two safety mechanisms are complementary: the manual prompt protects the user when they invoke `/ship-test-ensure` directly; the guard protects when the wrapper invokes it.

Implementation style: the guard is a bash code block in the SKILL.md (which is how all the existing skills implement their gates). It will be read by the orchestrator and executed in the orchestrator's bash context. The exit-99 propagates up; the wrapper interprets exit 99 as "ran cleanly through staging, intentionally stopped before prod."

The mode-flag vocabulary is closed: only the two documented values are recognized. The skill MUST NOT silently accept arbitrary `CLAUDE_PIPELINE_MODE` values without warning — but adding warning logic is out of scope; this sprint only adds the guard for `staging-only`. Future modes are additive, same pattern.

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

# Sprint 3: Create `/autonomous-staging` skill (chains 1 + 2)

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 3 of 3
- **Depends on:** Sprint 1 (staging-only mode), Sprint 2 (aggressive-fix-loop mode)
- **Batch:** 2 (sequential after Batch 1)
- **Model:** sonnet
- **Estimated effort:** M

## Objective

Create a new `/autonomous-staging` skill that pre-flights, sets the mode-flag env vars from Sprints 1 and 2, chains `/plan-build-test` then `/ship-test-ensure`, and emits a single structured final report — without any user prompts between invocation and completion.

## File Boundaries

### Creates (new files)

- `/root/.claude/skills/autonomous-staging/SKILL.md` — the new skill file; full protocol with phases 0a (working-directory sanity), 0b (pre-flight ownership check), 1 (set env vars + invocation ID), 2 (invoke /plan-build-test), 3 (invoke /ship-test-ensure with staging-only), 4 (collect results + emit final report).

### Modifies (can touch)

- (none — Sprint 3 only creates one new file; Sprints 1 & 2 are the producers of the contracts this consumer uses)

### Read-Only (reference but do NOT modify)

- `/root/.claude/skills/plan-build-test/SKILL.md` — to learn the Phase 0a sanity-check pattern, active-plan discovery, and exit-code conventions
- `/root/.claude/skills/ship-test-ensure/SKILL.md` — to learn its exit codes (`0` = staging success, `99` = intentional staging-only stop), invocation interface
- `/root/.claude/skills/verify-staging/SKILL.md` — optional: for the AC-table generation in the final report
- `/root/.claude/hooks/scripts/active-plan-read.sh` — for PRD discovery
- `/root/.claude/hooks/scripts/bind-plan.sh` and `claim-sprint.sh` — for ownership semantics; the wrapper does NOT call these (the underlying `/plan-build-test` does)
- `/root/.claude/agents/orchestrator.md` — for the worktree-namespace convention
- `../spec.md` — PRD context

### Shared Contracts (consume from prior sprints or PRD)

- `CLAUDE_PIPELINE_MODE` env var (Sprints 1 + 2): set to `staging-only,aggressive-fix-loop` for the wrapper's invocation
- `CLAUDE_PIPELINE_INVOCATION_ID` env var (PRD Section 12): generated as `<unix-timestamp>-<random4>` (e.g. `1714914000-a3f2`); set by this skill, consumed by anything needing per-run namespacing
- Worktree path convention: `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/<sprint-name>` — namespacing extends the existing `.worktrees/$PRD_SLUG/` to add the per-invocation suffix
- Exit-code semantics: `/ship-test-ensure` returns `0` for full success (would only be reached if Phase 4 ran — which it doesn't here) OR `99` for "intentional staging-only stop" (the success signal under this wrapper)
- Final-report markdown shape (PRD Section 12): heading + one section each for PRD, Sprints (status table), PRs (URL list), Staging (URL + health snapshot), AC summary (table from PRD Section 6), Blocked items (with category + last attempt), Timing (start/end/duration)

### Consumed Invariants (from INVARIANTS.md)

- `CLAUDE_PIPELINE_MODE value vocabulary` — the wrapper sets only `staging-only,aggressive-fix-loop` (no other values)
- Verify: `grep "CLAUDE_PIPELINE_MODE" ~/.claude/skills/autonomous-staging/SKILL.md | grep -oE 'staging-only|aggressive-fix-loop' | sort -u | wc -l` returns 2
- `Pipeline invocation namespace` — wrapper computes `$INVOCATION_ID` and uses `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/`
- Verify: `grep -E '\.worktrees/.*\$PRD_SLUG.*run-\$INVOCATION_ID' ~/.claude/skills/autonomous-staging/SKILL.md` returns at least one match
- `Cross-skill mode-flag handshake` — wrapper documents the contract and references the producer skills by name
- Verify: `grep -lE 'staging-only.*ship-test-ensure|ship-test-ensure.*staging-only' ~/.claude/skills/autonomous-staging/SKILL.md` returns the file path

## Tasks

- [ ] Create `~/.claude/skills/autonomous-staging/` directory and `SKILL.md` file inside it.
- [ ] Write the SKILL.md frontmatter: `name: autonomous-staging`, `description:` two sentences explaining the autonomous PRD-to-staging chaining and the prod-unreachability guarantee. Include the trigger words "autonomous staging", "ship to staging unattended", "fire and forget", "ship the PRD".
- [ ] Write Phase 0a: working-directory sanity check, copying the pattern from `/plan-build-test` (umbrella detection, non-git exit). Reference the existing pattern by name; do not re-invent.
- [ ] Write Phase 0b: pre-flight ownership check. Read the active-plan pointer via `bash ~/.claude/hooks/scripts/active-plan-read.sh`. If no active plan: exit cleanly with "nothing to do" message (AC8). If active plan exists: read its `progress.json`, scan all sprints for `claimed_by_session` matching a non-self session ID with heartbeat younger than 30 minutes; if found, REFUSE with the conflicting session ID prefix (AC3) and exit non-zero. Also count eligible sprints: if zero (all complete or all permanently BLOCKED), exit cleanly with "nothing to do" (AC8).
- [ ] Write Phase 1: generate `$INVOCATION_ID` (`echo "$(date +%s)-$(head /dev/urandom | tr -dc a-z0-9 | head -c4)"`); export `CLAUDE_PIPELINE_MODE=staging-only,aggressive-fix-loop` and `CLAUDE_PIPELINE_INVOCATION_ID=$INVOCATION_ID`; record start timestamp.
- [ ] Write Phase 2: invoke `/plan-build-test` (via the same skill-invocation pattern the user uses — document precisely how this is done in the orchestrator context). Capture exit code and the path to its execution log if any. On non-zero exit: skip Phase 3, jump to Phase 4 reporting the failure category.
- [ ] Write Phase 3: invoke `/ship-test-ensure` with the env vars still set. Expected exit codes: `0` (success but odd — Phase 4 should be unreachable; treat as success and note in report) or `99` (intentional staging-only stop — the canonical success path). Any other exit code: capture and proceed to Phase 4 reporting failure.
- [ ] Write Phase 4: emit the final report. Read PRD's `progress.json` for sprint statuses, read PRD's `spec.md` Section 6 for AC list, optionally invoke `/verify-staging` to populate the staging-health and AC-evidence rows. Print the structured markdown to stdout. Compute total wall-clock from Phase 1 start. Exit `0` on full success, non-zero with category code on partial.
- [ ] Add a `## Standards (skill-specific)` section listing: (a) NEVER calls `AskUserQuestion` between Phase 0b refusal and Phase 4 report (autonomous contract), (b) NEVER touches `~/.claude/state/active-plan-*.json` directly (that's owned by `bind-plan.sh`), (c) NEVER unsets the env vars mid-run (downstream skills depend on them), (d) cleanup of per-run worktrees happens in the cleanup-worktrees Stop hook, NOT here.
- [ ] Cross-reference both upstream skills by name in the description and in the body (the invariant verify expects this).

## Acceptance Criteria

- [ ] AC1 (mirrors PRD AC1): The skill body contains zero `AskUserQuestion` invocations between Phase 0b refusal and Phase 4 report. `grep -c 'AskUserQuestion' ~/.claude/skills/autonomous-staging/SKILL.md` returns at most 1 (the prohibition note in `## Standards`).
- [ ] AC2 (mirrors PRD AC2): Phase 3 sets `CLAUDE_PIPELINE_MODE` to include `staging-only` before invoking `/ship-test-ensure`. Verifiable by reading Phase 3 prose.
- [ ] AC3 (mirrors PRD AC3): Phase 0b explicitly checks `claimed_by_session != $CLAUDE_SESSION_ID` AND heartbeat-age < 30 minutes; refusal message names the session prefix.
- [ ] AC4 (mirrors PRD AC4): Worktree path convention `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/` is documented in the SKILL.md and used in any worktree-creation example.
- [ ] AC7 (mirrors PRD AC7): Phase 4 prose specifies all required report sections (PRD, sprints table, PRs, staging URL+health, AC table, blocked, timing).
- [ ] AC8 (mirrors PRD AC8): Phase 0b's "nothing to do" exit path is documented and emits a single-line message in <10s, no agent spawn, no git changes.
- [ ] AC9 (mirrors PRD AC9): `grep -l 'staging-only' ~/.claude/skills/autonomous-staging/SKILL.md ~/.claude/skills/ship-test-ensure/SKILL.md` returns BOTH file paths (no orphan flag references).
- [ ] AC10 (mirrors PRD AC10): Phase 0a reuses the exact umbrella+non-git detection pattern from `/plan-build-test` (verbatim or near-verbatim block).

## Verification

- [ ] Build passes (N/A — markdown only)
- [ ] Lint passes (N/A — markdown)
- [ ] Type-check passes (N/A — markdown)
- [ ] Sprint-specific tests pass — run the three "Consumed Invariants" verify commands; all three must produce matches.

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

This is the consumer of the contracts established by Sprints 1 and 2. Both must merge before this sprint runs (handled by Batch 2 sequencing). The skill is a thin orchestration layer — the heavy logic remains in `/plan-build-test` and `/ship-test-ensure`. This wrapper's job is: pre-flight, set env vars, invoke, collect, report.

The skill uses the existing skill-invocation mechanism (the orchestrator picks up `/<skill-name>` and runs the SKILL.md protocol). Concrete invocation pattern: the SKILL.md prose instructs the orchestrator (the main Claude session) to "now run `/plan-build-test`" — which the user's session-level skill router resolves. The env vars set in this skill's bash blocks survive into the chained skill's bash blocks because they execute in the same shell context.

The "nothing to do" path is the most-frequent expected case after the first successful run: the user invokes `/autonomous-staging` again later, and there are no `not_started` sprints because all merged on the first run. The fast exit prevents the wrapper from spinning up agents just to confirm "nothing to do" — confirmable in <2 seconds by reading `progress.json`.

The final report is the user-facing artifact. It is the ONLY synchronous output the user reads when they return to the terminal. It MUST be self-explanatory: which PRD ran, what shipped to staging, what blocked, why. URLs are clickable in the user's terminal. The AC table is copy-pasted from the PRD spec with status filled in based on collected evidence.

Worktree namespace: existing convention is `.worktrees/$PRD_SLUG/<sprint-name>`. This skill extends to `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/<sprint-name>` so that two consecutive runs of `/autonomous-staging` against the same partial PRD don't collide on stale worktrees from the prior crashed run. The cleanup hook handles deletion at session end; this skill does NOT clean up its own worktrees mid-run (the next sprint may need them).

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

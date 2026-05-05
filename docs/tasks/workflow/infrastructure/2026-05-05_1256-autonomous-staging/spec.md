# Autonomous Staging Pipeline: Product Requirements Document

## 1. What & Why

**Problem:** The user's current pipeline is `/plan-build-test` (autonomous, local-only) → manual user testing → `/ship-test-ensure` (autonomous through staging, manual gate before prod). The middle step ("manual user testing") is a context-switch tax: the user already sees the verification report from `/plan-build-test` and knows the build is green; re-invoking `/ship-test-ensure` separately just to chain into staging deploy adds friction without value, and forces the user to be present at the handoff.

**Desired Outcome:** A single user-invoked skill, `/autonomous-staging`, that takes an active PRD and runs every sprint to completion, then ships to staging with full verification — without any human gates between invocation and "staging is green." The skill chains the existing `/plan-build-test` and `/ship-test-ensure` skills with autonomous flags, hard-stops before any production action, and emits one structured report at the end. The user can step away after invoking it and return to a deployed-and-verified staging environment or a clearly-marked BLOCKED PRD.

**Justification:** The user's insights report shows 7 plan-build-test sessions, 4 PR-merge-and-staging-verify sessions, and explicit feedback to remove manual checkpoints. They've already invested in autonomous defaults at every gate of `/plan-build-test`. The remaining friction is the cross-skill handoff. Eliminating it reclaims roughly one context-switch per PRD shipped, and turns "I shipped a PRD today" into a fire-and-forget operation. Production safety remains absolute (Phase 4 of `/ship-test-ensure` is never reached).

## 2. Correctness Contract

**Audience:** The user (single power user) invokes `/autonomous-staging` on demand, then steps away. Decisions made from the output: (a) read the final report, (b) decide which staged PRDs to promote to prod via `/ship-test-ensure`, (c) decide which BLOCKED sprints need manual diagnosis. The skill is NOT cron-triggered, NOT shared with collaborators, and NOT consumed by any downstream system.

**Failure Definition:** A run is useless if any of: (1) the pipeline exits without finishing all eligible sprints when no genuine blocker existed; (2) sprints are marked complete but their tests don't actually pass; (3) the pipeline silently exits without surfacing the reason; (4) the fix loop doesn't actually fix errors and just retries the same broken approach until budget exhaustion; (5) the final report omits enough detail that the user can't tell what was shipped vs. what's blocked.

**Danger Definition:** A run is actively harmful if any of: (1) any production deploy command runs (forbidden — Phase 4 of `/ship-test-ensure` is unreachable from this skill); (2) the pipeline grabs a sprint owned by a peer live session, eating that session's in-progress work; (3) the pipeline merges its own PRs to `main` without the staging verification passing first; (4) worktrees from this run collide with worktrees from a concurrent peer session because of namespace bugs; (5) a fix-loop runaway burns API tokens past a hard ceiling without converging.

**Risk Tolerance:** For prod-touching actions: confident-wrong is catastrophic — refuse absolutely. There is no "small prod deploy"; the skill must be incapable of triggering one. For staging actions: prefer making progress (best-effort fixes, retry forward) over refusal — staging is recoverable. For sprint ownership conflicts: confident-wrong is catastrophic (eating a peer's work) — refuse absolutely, never adopt. For fix loops: bound the cost (max retries per category from CLAUDE.md), then mark BLOCKED rather than spending forever.

**Session-identification contract (so a different agent can implement Sprint 3 unambiguously):** The skill runs inside the user's orchestrator Claude Code session. The environment variable `$CLAUDE_SESSION_ID` (set by `~/.claude/hooks/scripts/session-start.sh` and inherited by every bash block) identifies the current session as a string. The `progress.json` v2 schema includes a per-sprint `claimed_by_session` field (string, may be null) and `claim_heartbeat_at` field (ISO 8601 timestamp, may be null), both written by `~/.claude/hooks/scripts/claim-sprint.sh` when a sprint enters `in_progress`. The pre-flight ownership check is: read `$CLAUDE_SESSION_ID`, parse the active PRD's `progress.json`, iterate sprints; if any sprint has `claimed_by_session != null` AND `claimed_by_session != $CLAUDE_SESSION_ID` AND `claim_heartbeat_at` is newer than 30 minutes from now (parse with `date -d` or python `datetime.fromisoformat`), then refuse — print the first 8 chars of the conflicting `claimed_by_session` value and exit non-zero. Otherwise proceed. The wrapper itself never writes to `claimed_by_session` or `claim_heartbeat_at` — those remain owned by `claim-sprint.sh`, called transitively by `/plan-build-test`.

## 3. Context Loaded

- `~/.claude/skills/plan-build-test/SKILL.md`: Already fully autonomous through Phase 5 (Live Verification). Has Phase 5.7 "Handle Failures" with adaptive retry budgets per failure category (`transient: 5`, `logic: 2`, `environment: 1`, `config: 3`). The recently-added Phase 0a (this same conversation) blocks invocation from non-repo / umbrella cwd.
- `~/.claude/skills/ship-test-ensure/SKILL.md`: Phase 4.1 is the mandatory production-deploy gate ("never skip, even in autonomous mode"). Phases 0-3 (commit, branch, PR, staging deploy follow, staging E2E) are already autonomous. Reads Execution Config from project CLAUDE.md for staging URLs, e2e commands, deploy triggers.
- `~/.claude/skills/verify-staging/SKILL.md`: Just created — read-only health/smoke check against staging. Could be invoked by `/autonomous-staging` to produce the AC table in the final report, but is NOT a hard dependency.
- `~/.claude/agents/orchestrator.md`: Step 0 preflight includes "stale worktree cleanup" and "git readiness." `prd_slug`-namespaced worktrees and branches (`sprint/$PRD_SLUG/*`) prevent cross-session collision when both sessions follow the convention.
- `~/.claude/hooks/scripts/active-plan-read.sh`, `bind-plan.sh`, `claim-sprint.sh`: Existing concurrency primitives. `progress.json` v2 has `owner_session_id` for whole-PRD ownership and per-sprint `claimed_by_session` + `claim_heartbeat_at` for in-flight sprints.
- `~/.claude/CLAUDE.md` "Autonomous Pipeline" + "Stop Hook Authorization Protocol": Establishes the existing manual-gate pattern. This PRD removes the middle gate; the prod gate stays absolute.
- `~/.claude/rules/workflow.md` "Subagent Communication Protocol": every subagent prompt must end with structured-summary instructions (≤20 lines). The chained skills already follow this; the wrapper must too when relaying status.

## 4. Success Metrics

| Metric                                    | Current                          | Target                                           | How to Measure                                                                 |
| ----------------------------------------- | -------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------ |
| Manual checkpoints between PRD-ready and staging-verified | 2 (start `/plan-build-test`, start `/ship-test-ensure`) | 1 (start `/autonomous-staging`)                  | Count user-typed slash commands per PRD                                        |
| Time-to-staging from PRD-ready (active user attention) | ~5–15 min of intermittent attention | ~30 sec invocation, then walk away              | Subjective; measured by user's reported friction at next workflow audit        |
| Production deploys triggered by this skill | N/A                              | 0 — ever, by construction                        | `git log` + CI run history; any prod deploy attributed to `/autonomous-staging` is a P0 bug |
| Sprints completed when eligible work exists | Manual per-PRD                   | 100% (or BLOCKED with diagnosable reason)        | Compare progress.json `complete` count post-run vs. eligible count pre-run     |
| Cross-session worktree/branch collisions  | Possible (depends on slug uniqueness) | 0 — pre-flight rejects, namespacing isolates    | Hook-level audit: `git worktree list` post-run shows only this run's namespace |

## 5. User Stories

GIVEN a PRD with N `not_started` sprints and a Build Candidate tag, no peer session owns it
WHEN the user runs `/autonomous-staging` and walks away
THEN within ~30 minutes (depending on PRD size) the user returns to either: (a) all sprints `complete`, PR merged to staging, staging health green, Playwright smoke green, structured success report; OR (b) a clearly-marked BLOCKED report listing which sprints failed, with the failure category and last fix-attempt diff.

GIVEN a PRD with sprints partially `in_progress` from a previous failed `/autonomous-staging` run
WHEN the user re-invokes `/autonomous-staging`
THEN the skill resumes from the next eligible sprint, not from scratch — leveraging `/plan-build-test`'s existing resume logic via the active-plan pointer.

GIVEN a PRD where another live session owns one of the sprints
WHEN the user runs `/autonomous-staging`
THEN the skill refuses to start, names the conflicting session, and exits — never adopts a peer's sprint without explicit `/adopt-plan`.

GIVEN any state of any PRD
WHEN `/autonomous-staging` runs
THEN no production deploy command is ever executed — Phase 4 of `/ship-test-ensure` is unreachable through this skill, by construction (not by convention).

## 6. Acceptance Criteria

- [ ] AC1: Invoking `/autonomous-staging` from a repo with an active PRD runs all `not_started` sprints to completion or BLOCKED, with no `AskUserQuestion` calls between invocation and the final report.
- [ ] AC2: After all sprints succeed, the skill invokes `/ship-test-ensure` in staging-only mode, which runs Phases 0–3 (commit through staging E2E) and exits cleanly without entering Phase 4 (production).
- [ ] AC3: Pre-flight check refuses to start when any sprint in the active PRD has `claimed_by_session` set to a non-self session ID with a heartbeat younger than 30 minutes; the refusal message names the conflicting session prefix.
- [ ] AC4: Worktrees created during the run live under a namespace containing both `prd_slug` and a per-invocation suffix (e.g. `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/`), so a concurrent peer's worktrees in `.worktrees/$PRD_SLUG/` do not collide.
- [ ] AC5: The Phase 5.7 fix loop in `/plan-build-test`, when invoked under aggressive-mode, applies the per-category retry budgets from CLAUDE.md but with `logic` failures retried up to 4 instead of 2 (each retry must use a different fix approach, documented in session learnings).
- [ ] AC6: The `staging_only` mode in `/ship-test-ensure` is implemented as a documented mode flag (env var or invocation parameter), exits with code 0 after Phase 3 success, and contains an explicit guard that throws if Phase 4 logic is reached under this mode.
- [ ] AC7: The final report is a single structured markdown block printed at the end of the run, containing: PRD name, sprints (status per sprint), PRs opened/merged, staging URLs verified, AC summary table from PRD spec, list of BLOCKED items with failure category and last attempt, total wall-clock time.
- [ ] AC8: Running `/autonomous-staging` against a PRD with no eligible sprints (all complete or all BLOCKED with no retry signal) exits in <10 seconds with a one-line "nothing to do" report — does NOT spawn agents, does NOT touch git, does NOT enter the orchestrator loop.
- [ ] AC9: A grep of all skill SKILL.md files for the new mode flags (`staging_only`, `aggressive_fix_loop`) returns matches in both the producer (the skill that defines them) and the consumer (`/autonomous-staging`); no orphan flag references.
- [ ] AC10: The skill SKILL.md for `/autonomous-staging` includes the `Phase 0a` working-directory sanity check pattern from `/plan-build-test` (added earlier in this conversation) — fails fast on umbrella folders and non-git cwd.

## 7. Non-Goals (at least as detailed as goals)

- **Cron / scheduled triggers.** Excluded: user explicitly invokes the skill. Cron adds operational complexity (scheduler config, kill switch, ownership of the cron user) that the user has already declined. If desired later, a cron wrapper can call `/autonomous-staging` externally — but the skill itself is invocation-driven.
- **Production deploys.** Excluded: prod is human-gated by `/ship-test-ensure` Phase 4.1, and that gate is preserved. Adding a "yolo to prod" mode would defeat the user's stated value-hierarchy rule that production deploys are "MUST ask user" decisions.
- **Multi-PRD execution in one invocation.** Excluded: each `/autonomous-staging` run targets exactly one PRD (the active-plan pointer's). Running multiple PRDs back-to-back is `/plan-build-test`'s existing behavior (it loops to Phase 1 after each PRD); shipping each one to staging is a deliberate per-PRD choice. If the user wants two PRDs in staging today, they invoke the skill twice.
- **Self-healing CI failures beyond what `/ship-test-ensure` already does.** Excluded: that skill already has a Phase 2 fix loop for staging deploy failures and a Phase 3 fix loop for E2E failures. Layering more aggressive retries on top is scope creep; if those budgets are wrong, fix them in `/ship-test-ensure` directly rather than wrapping.
- **Replacing `/plan-build-test` or `/ship-test-ensure`.** Excluded: this skill is a thin orchestration wrapper, not a replacement. Both downstream skills must remain independently invocable for the cases where the user wants their existing two-step flow.
- **A "morning summary" or persistent log.** Excluded: the user invokes synchronously and reads the report at the end. No daily digest, no Slack notification, no dashboard — those are scope explosions for a synchronous on-demand skill.
- **Notifying anyone other than the invoker.** Excluded: single-user tool; no Slack/email/PagerDuty integration.

## 8. Technical Constraints

- **Stack:** Markdown-based skill files (Claude Code skill system). No new runtime dependencies, no new languages. All logic lives in SKILL.md files following the existing protocol pattern.
- **Architecture:** Thin orchestration wrapper. Must NOT reimplement logic that exists in `/plan-build-test` or `/ship-test-ensure` — instead, parameterize those skills with mode flags and chain them. Mode flags propagate via environment variables (e.g. `CLAUDE_PIPELINE_MODE=staging-only`) since skill invocations don't pass parameters cleanly.
- **Performance:** Pre-flight check in <2 seconds. Final report rendering in <2 seconds. Total skill overhead (excluding the actual /plan-build-test and /ship-test-ensure work) under 30 seconds wall-clock.
- **Concurrency:** Must coexist with concurrent peer sessions running `/plan-build-test`, `/ship-test-ensure`, or `/autonomous-staging` against different PRDs. Namespace via `$PRD_SLUG/run-$INVOCATION_ID` for worktrees; reuse `flock` from `/plan-build-test` Phase 4.5 for the main-merge serialization (the wrapper does NOT touch the lock — `/ship-test-ensure` already does, transitively via the merge protocol).
- **Tool surface:** Skill must work using only existing global tools (`Agent`, `Bash`, `Read`, `Write`, `Edit`, `AskUserQuestion` available but unused, `Glob`, `Grep`). No MCP server dependency.

## 9. Architecture Decisions

| Decision | Reversal Cost | Alternatives Considered | Rationale |
|----------|--------------|-------------------------|-----------|
| Wrapper skill that chains `/plan-build-test` + `/ship-test-ensure` rather than a monolith | Low | Build a single new skill that duplicates both | Wrapper preserves the user's existing two-step flow as independently-callable, halves the maintenance surface, and inherits future improvements to either downstream skill automatically |
| Mode flags via env var (`CLAUDE_PIPELINE_MODE`) rather than skill-arg parsing | Low | Slash-command arguments | Skill-arg passing across nested skill invocations is not first-class in the existing skill system; env var is uniform, greppable, and survives the orchestrator handoff |
| `staging_only` is a hard structural guard, not a polite request | High to revert | Trust the autonomous-mode flag | Production safety must be enforced by code-path unreachability, not by convention. A guard at the top of Phase 4.1 that `exit 1`s under `staging_only` mode is the minimum safe implementation |
| Per-invocation worktree namespace (`run-$INVOCATION_ID`) instead of just `$PRD_SLUG` | Low | Reuse existing `$PRD_SLUG` namespacing | Re-invoking `/autonomous-staging` against a partially-completed PRD must not collide with the previous run's worktrees if cleanup didn't fire (e.g. session crash mid-run). Per-invocation suffix isolates each attempt |
| Aggressive fix-loop tightens `logic` failure retries (2 → 4) but keeps `environment` at 1 | Medium | Raise all retry budgets uniformly; add a "yolo retry" mode with no cap | `logic` failures are the category that benefits most from "try a different approach" (the existing protocol already says "try a different approach" after retry 2). `environment` retries don't help because the env doesn't change. No cap is the cost-runaway danger the user explicitly flagged |
| Pre-flight check refuses on peer ownership conflict, never auto-adopts | High to revert | Auto-adopt if heartbeat is stale | Auto-adopting a peer's sprint is a "MUST ask user" action per CLAUDE.md value hierarchy. The user can resolve via existing `/adopt-plan` if needed; the autonomous skill must not |

## 10. Security Boundaries

- **Auth model:** No new auth surface. Inherits whatever auth the underlying `/plan-build-test` and `/ship-test-ensure` use (e.g. `gh` CLI auth for PRs, AWS OIDC for deploys). No tokens read or written by the wrapper itself.
- **Trust boundaries:** The PRD spec, sprint specs, and INVARIANTS.md are trusted inputs (they're authored by the user via `/plan`). The wrapper does NOT execute arbitrary text from them as shell — it passes them to `/plan-build-test`, which already has its own trust model. The active-plan pointer is trusted (it's owned by the user's session).
- **Data sensitivity:** Wrapper does not read/write secrets. Final report includes staging URLs (already public to the user) and PR URLs (public to the user via gh CLI). No PII, no tokens, no credentials surfaced.
- **Tenant isolation:** N/A — single-user tool. No multi-tenant surface.
- **Production safety:** `staging_only` mode is the security boundary. Implementation MUST be unreachable code (guard + exit), not unreachable behavior (skip + comment). Reviewer must verify by inspecting the final SKILL.md that no code path under `CLAUDE_PIPELINE_MODE=staging-only` can call any of: `deploy_commands.production`, `pages_to_audit` (Lighthouse runs on prod URLs), or anything from Phase 4+.

## 11. Data Model

N/A — this PRD does not introduce schema changes or new persistent data entities. Existing artifacts that the wrapper reads/writes:

- `progress.json` (read for state, untouched by the wrapper itself; `/plan-build-test` writes to it as it runs)
- Active-plan pointer (`~/.claude/state/active-plan-<session>.json` — read for PRD discovery, untouched)
- Session learnings file (`docs/session-learnings.md` per project — `/plan-build-test` writes; the wrapper appends a single end-of-run entry)
- Final report (printed to stdout, not persisted)

## 12. Shared Contracts

- **Mode-flag env vars:** `CLAUDE_PIPELINE_MODE` accepts the values `staging-only`, `aggressive-fix-loop`, and a comma-separated combination (e.g. `staging-only,aggressive-fix-loop`). Producers (`/ship-test-ensure`, `/plan-build-test`) parse the var and apply mode behavior; consumer (`/autonomous-staging`) sets it before invoking.
- **Invocation ID:** A per-run identifier `CLAUDE_PIPELINE_INVOCATION_ID=<unix-timestamp>-<random4>` set by `/autonomous-staging` and consumed by anything that needs per-run namespacing (worktree paths, log file names).
- **Final report shape:** Documented markdown structure (heading + sections per PRD/sprints/PRs/staging/ACs/blocked/timing). Both Sprint 3 (the wrapper that emits it) and any future tooling that wants to parse it must agree on this shape. Defined in `sprints/03-autonomous-staging-skill.md`.
- **Aggressive-fix-loop budget table:** A single source of truth (the table in Sprint 2's spec) defines per-category retry counts under aggressive mode. `/plan-build-test` Phase 5.7 reads from this table.

## 13. Architecture Invariant Registry

| Concept | Owner | Format/Values | Verify Command |
|---------|-------|---------------|----------------|
| `CLAUDE_PIPELINE_MODE` value vocabulary | This PRD's `/autonomous-staging` SKILL.md | Comma-separated subset of `{staging-only, aggressive-fix-loop}` | `grep -r "CLAUDE_PIPELINE_MODE" ~/.claude/skills/ \| awk -F'=' '{print $2}' \| sort -u` shows only documented values |
| `staging_only` mode unreachability of Phase 4 | `/ship-test-ensure` SKILL.md | Phase 4 entry must include guard `[ "$CLAUDE_PIPELINE_MODE" != *staging-only* ] \|\| { echo PROD-FORBIDDEN; exit 99; }` | `grep -A 2 'Phase 4: Deploy to Production' ~/.claude/skills/ship-test-ensure/SKILL.md \| grep -q 'staging-only.*exit'` |
| Pipeline invocation namespace | `/autonomous-staging` SKILL.md | `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/` | `git worktree list \| grep -E '\.worktrees/[^/]+/run-[0-9]+-[a-z0-9]+' \| wc -l` returns count of active runs |
| Cross-skill mode-flag handshake | This PRD | Producer skill defines flag in its SKILL.md; consumer skill (`/autonomous-staging`) references it by name | `grep -l "staging-only" ~/.claude/skills/{ship-test-ensure,autonomous-staging}/SKILL.md` shows both |

**Dependency direction:** `/autonomous-staging` depends on `/plan-build-test` and `/ship-test-ensure`. The downstream skills own the contract (define the modes, document the behavior); the wrapper consumes (sets the env vars, reads the exit codes).

## 14. Open Questions

- [ ] None blocking — the user clarified all major design decisions in the discovery exchange (no cron, no questions during run, staging-only, fix all errors, use worktrees). Open follow-ups (logged but NOT blocking this PRD): (1) should the wrapper detect Lighthouse audits in `/ship-test-ensure` as a "post-staging" concern that COULD run under staging-only mode against staging URLs? Decision: NO, defer — Lighthouse on staging is meaningful but the existing skill targets prod URLs and conflating modes risks the safety guard. (2) Should there be a `--dry-run` mode that prints the plan without executing? Decision: NO, defer — adds complexity without clear ROI for a single-user synchronous tool.

## 15. Uncertainty Policy

When uncertain about whether to enter Phase 4 of `/ship-test-ensure`: **STOP** (this is the prod-safety boundary; no judgment-call gray area).

When uncertain about adopting a peer-owned sprint: **STOP and refuse** (per CLAUDE.md value hierarchy, MUST ask user; the autonomous skill cannot ask).

When uncertain about whether a fix attempt converged on the right approach: **continue retrying within budget** (logic: 4 attempts under aggressive mode, then BLOCKED; do NOT escalate the budget at runtime).

When uncertain about whether a sprint's BLOCKED status is permanent vs. flaky: **mark BLOCKED, do NOT retry the whole pipeline** (the user re-invokes if they think the blocker was transient).

When `staging-only` conflicts with a downstream skill's autonomous default: prefer `staging-only` (the safety boundary always wins).

## 16. Verification

**Deterministic:**
- `grep` audits per the invariant table above (run from `~/.claude/`).
- After a dry-run invocation against a known-blocked PRD: skill exits in <10s with a "nothing to do" message and 0 git changes (`git status` clean before and after).
- Mode-flag round-trip test: `CLAUDE_PIPELINE_MODE=staging-only` env var set, invoke a tiny PRD, observe in the run trace that `/ship-test-ensure` Phase 4 was never entered (no log line matching "Phase 4" emitted).
- Cross-session safety test: pre-flight check rejects when a manually-injected `claimed_by_session` differs from `$CLAUDE_SESSION_ID` and heartbeat is recent.

**Manual:**
- Reviewer reads the final SKILL.md for `/autonomous-staging` and traces the chain end-to-end against the AC list.
- Reviewer inspects the modified Phase 4.1 of `/ship-test-ensure` and confirms the `staging_only` guard is a hard exit, not a soft skip.
- Reviewer runs the skill against a real small PRD in their own causeflow setup and confirms the staging deploy completes without prompts.

## 17. Sprint Decomposition

Sprint specs are written to: `sprints/NN-title.md`
Progress is tracked in: `progress.json`

### Sprint Overview

| Sprint | Title                                                       | Depends On | Batch | Model  | Parallel With |
|--------|-------------------------------------------------------------|------------|-------|--------|---------------|
| 1      | Add `staging_only` mode to /ship-test-ensure                | None       | 1     | sonnet | Sprint 2      |
| 2      | Add `aggressive_fix_loop` mode to /plan-build-test Phase 5.7 | None       | 1     | sonnet | Sprint 1      |
| 3      | Create `/autonomous-staging` skill (chains 1 + 2)            | 1, 2       | 2     | sonnet | —             |

Sprints 1 and 2 modify different files (`ship-test-ensure/SKILL.md` vs. `plan-build-test/SKILL.md`) and can run in parallel under worktree isolation. Sprint 3 creates a new file (`autonomous-staging/SKILL.md`) and depends on the mode-flag contracts established by Sprints 1 and 2.

## 18. Execution Log

[Filled during execution — tracked in progress.json]

## 19. Learnings (filled after all sprints complete)

[Compound step output]

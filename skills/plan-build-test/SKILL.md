---
name: plan-build-test
description: >
  Local-only feature builder that plans, implements, and tests code using
  agent teams — all locally, no deploy. Use this skill when the user describes
  a problem, feature request, bug, or improvement to build. Triggers on phrases
  like "build this", "implement", "create feature", "fix this problem", "add
  functionality", or when user provides a feature description to execute. Also
  triggers when user wants to work through pending task files. After local testing
  completes, user manually verifies, then uses /ship-test-ensure to deploy.
---

# Plan, Build & Test — Local Development Workflow

Plan, implement, and test features entirely locally: discover tasks, plan, implement with agent teams, run all tests and E2E locally, then learn. No commits, no deploys, no staging — that's what `/ship-test-ensure` is for after you've manually verified.

Operate as a **Team Lead** coordinating specialist agents — using parallel worktrees for independent tasks and sequential execution for dependent ones.

**Autonomous by default.** This skill runs without user interruption from start to finish.
The user's workflow is: review PRD → approve → this skill runs autonomously → user tests
manually. All intermediate checkpoints use safe defaults instead of asking. This is a
permanent design choice, not a workaround. See CLAUDE.md "Autonomous Pipeline" for details.

**Inherited from CLAUDE.md** (applies to all phases below):

- Autonomous Pipeline — run without interruption, use safe defaults at checkpoints
- Context Engineering — orchestrator pattern, subagent communication, context budget
- Model Assignment Matrix — haiku/sonnet/opus per task type
- Parallel Execution with Worktrees — batch planning, isolation, merge protocol
- Compact Recovery Protocol — re-read session learnings, resume from last phase
- Self-Improvement Protocol — compile, persist, generate rules

**Inherited from project knowledge files** (applies to all phases below):

- Troubleshooting patterns — known gotchas and their solutions
- Environment knowledge — project-specific constraints, port conflicts, runtime requirements

---

## Project Configuration

This skill reads project-specific commands from the project's `CLAUDE.md` under `## Execution Config`. Required keys: `build`, `test`, `lint`, `lint-fix`, `type-check`, `e2e`, `dev`, `kill`, plus `session-learnings-path`, `task-file-location`, and `knowledge-files`.

If the project CLAUDE.md does not define explicit commands, infer them from `package.json`, `Makefile`, or equivalent. Confirm with the user before executing inferred commands.

---

## Mode Flags (`$CLAUDE_PIPELINE_MODE`)

This skill recognizes an optional `CLAUDE_PIPELINE_MODE` environment variable. When set,
it activates named modes that alter retry budgets and execution behavior. Multiple modes
can be active simultaneously — they are combined as a single string (e.g.
`"staging-only aggressive-fix-loop"`). All checks use substring matching:
`[[ "$CLAUDE_PIPELINE_MODE" == *<mode-name>* ]]`.

| Mode value            | Set by                | Consumed by         | Effect summary                                                    |
|-----------------------|-----------------------|---------------------|-------------------------------------------------------------------|
| `staging-only`        | `/autonomous-staging` | `/ship-test-ensure` | Not consumed by this skill — passed through env to `/ship-test-ensure`, which exits 99 before its production-deploy phase. `/plan-build-test` runs all of Phases 1-6 normally. |
| `aggressive-fix-loop` | `/autonomous-staging` | `/plan-build-test`  | Raises `logic` failure retry budget in Phase 5.7 from 2 → 4 (this skill's only consumed mode flag) |

When `CLAUDE_PIPELINE_MODE` is unset (normal `/plan-build-test` invocation), all defaults
apply and existing behavior is fully preserved.

---

## Phase 0a: Working Directory Sanity Check (fail-fast)

**Runs before Phase 0. Prevents the recurring "invoked from umbrella / non-repo" misfire.**

The skill assumes the cwd is a single project repo with its own `CLAUDE.md`, `progress.json` location, and Execution Config. Invoking it from a parent folder that contains multiple sibling repos (e.g. `causeflow/` over `core/`, `web/`, `relay/`) cannot work — there is no single `package.json`, no single test runner, and no single staging URL.

Run this check first:

```bash
# (1) Are we in a git work tree?
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # (2) Is this an umbrella? (cwd is not a repo, but immediate children are)
  umbrella_children=$(find . -mindepth 2 -maxdepth 2 -type d -name '.git' -printf '%h\n' 2>/dev/null | sort)
  if [ -n "$umbrella_children" ]; then
    echo "BLOCKED: cwd is an umbrella folder containing multiple sibling repos:"
    printf '  - %s\n' $umbrella_children
    echo ""
    echo "cd into the specific repo you want to work in, then re-invoke /plan-build-test."
    exit 1
  fi
  echo "BLOCKED: cwd is not a git repository and has no child repos."
  echo "/plan-build-test needs a project repo with CLAUDE.md + Execution Config."
  exit 1
fi

# (3) Is there a CLAUDE.md? (warn, don't block — some projects use other names)
[ -f CLAUDE.md ] || echo "WARN: no CLAUDE.md in $(pwd) — Execution Config may be missing."
```

**On BLOCKED:** report the message to the user via plain text and STOP. Do NOT proceed to Phase 0. Do NOT spawn agents. Do NOT attempt discovery. The user must `cd` into a real repo first.

**On WARN:** continue, but be alert during Phase 0 that `task-file-location` and Execution Config may not be defined.

---

## Phase 0: Resume Gate (Always Runs First)

**Prevents re-discovery when a plan already exists.**

### Step 0.0: Ensure Session Learnings File Exists

Create the session learnings file at the configured path (from project CLAUDE.md `session-learnings-path`, default: `docs/session-learnings.md`) if it doesn't exist. This prevents learning loss on `/compact` or session end.

### Step 0.1: Resolve THIS Session's Plan (pointer-first)

**Concurrent multi-session safety:** Two terminals can each be driving their own plan. Discovery MUST be session-scoped — never grab a peer session's sprint. The active-plan pointer is the source of truth.

**Resolution order — first match wins:**

1. **Active-plan pointer (authoritative for this session):**
   ```bash
   bash ~/.claude/hooks/scripts/active-plan-read.sh
   ```
   If exit 0: parse the JSON for `prd_dir`. Read `$prd_dir/progress.json`. This is THIS session's plan — use it. The pointer also touches `last_seen_at` so the GC and statusline see this session as live. **Skip the rest of Step 0.1.**

2. **No pointer — fall back to ownership-filtered discovery:** the user is running `/plan-build-test` in a fresh terminal that has no pointer (e.g. resumed after `/compact` cleared state, or the pointer was GC'd). Search:

   a. **Build Candidate tags:** `git tag -l 'build-candidate/*'` — for each tag, locate the PRD directory via `git show <tag> --stat`.
   b. **Configured location:** `task-file-location` from project CLAUDE.md `## Execution Config`.
   c. **Convention fallbacks:** `docs/tasks/**/progress.json`, `tasks/**/progress.json`, `.tasks/**/progress.json`.

   For each `progress.json` found, classify by ownership:

   | progress.json state | Action |
   |---|---|
   | `schema_version: 2` AND `owner_session_id == $CLAUDE_SESSION_ID` | **Adopt silently** — this is mine, the pointer was just lost. Run `bash ~/.claude/hooks/scripts/active-plan-write.sh "$(dirname progress.json)"` to recreate the pointer, then use this plan. |
   | `schema_version: 2` AND `owner_session_id` is null/empty | **Bind silently** — this is the standard `/plan` → fresh-session handoff. The plan was published unbound; this session is the first executor to pick it up. Run `bash ~/.claude/hooks/scripts/bind-plan.sh <progress.json> "$CLAUDE_SESSION_ID"` (sets `owner_session_id` to this session and appends `{session_id, adopted_at, reason: "first-executor-bind"}` to `adopted_by[]`), then `bash ~/.claude/hooks/scripts/active-plan-write.sh "$(dirname progress.json)"`, then use this plan. If `bind-plan.sh` exits non-zero, treat as the matching row below (refused → skip / prompt). |
   | `schema_version: 2` AND `owner_session_id` is some other session | **Skip** — this is a peer's plan. Never touch it without an explicit `/adopt-plan`. (Note: this row only fires when ownership is non-empty AND non-self; the silent-bind row above handles the unbound-handoff case.) |
   | No `schema_version` (legacy v1, unowned) | **Prompt user once** via `AskUserQuestion`: "Found legacy plan at `<path>` with no owner. Bind (this is mine) / Adopt (was someone else's, taking over) / Skip?". On bind/adopt: run `bash ~/.claude/hooks/scripts/migrate-progress-v1-to-v2.sh <progress.json> $CLAUDE_SESSION_ID <bind\|adopt>`, then write the pointer and use it. |
   | All sprints `complete` | Eligible only for Phase 6 (Learning) if compound wasn't done. |

3. **Nothing matched:** no plan owned by this session. Also read the session learnings file for any `## Active Task Queue` (legacy simple-task format).

**If Build Candidate tags exist but the configured `task-file-location` missed them**, note this as a config drift to surface to the user after executing the plan, not before (don't block execution on config cleanup).

### Step 0.2: Route Decision

The progress.json referenced below is **this session's** progress.json (resolved in Step 0.1 — never a peer's).

| State                                                          | Action                                                                        |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **progress.json has not_started sprints**                      | **SKIP to Phase 3** (Execution). The plan exists with extracted sprint specs. |
| **progress.json has in_progress sprints (claimed by us)**      | **SKIP to Phase 3** — resume our own claim. Heartbeat will refresh on first orchestrator step. |
| **progress.json has in_progress sprints (claim mismatch / stale)** | See **Step 0.2.1** (inline stale-claim adoption).                          |
| **Session learnings has Active Task Queue (simple tasks)**     | **SKIP to Phase 3** via simple task route.                                    |
| **All sprints in progress.json are complete**                  | Go to Phase 6 (Learning) if compound wasn't done.                             |
| **All sprints in progress.json are blocked**                   | Report blocked sprints to user with reasons. Ask: retry, re-plan, or abandon. |
| **No progress.json AND no Active Task Queue**                  | Go to Phase 1 (Discovery) — fresh start.                                      |
| **User described a NEW task**                                  | Go to Phase 1 to scan + create new task.                                      |

**The key rule: If progress.json has pending sprints owned by THIS session, EXECUTE THEM. Don't re-plan.**

### Step 0.2.1: Inline Stale-Claim Adoption (auto-adopt with confirmation)

When this session legitimately owns a PRD (pointer matches `owner_session_id` OR last `adopted_by[].session_id`) but a sprint inside it is `in_progress` with `claimed_by_session != $CLAUDE_SESSION_ID`, the claim was left behind by an earlier instance of THIS plan (e.g. previous terminal of the same session that crashed before releasing). Decide based on heartbeat age:

| Heartbeat age vs `claim_heartbeat_at` | Action |
|---|---|
| < 30 min (live)                       | **Block** — a peer instance is actively running. Report which session prefix holds it and ask the user to wait or kill the peer. Do NOT proceed. |
| ≥ 30 min (stale)                      | **Prompt inline** via `AskUserQuestion`: show claimer session prefix, last heartbeat, sprint title — yes/no. On **yes**: run `bash ~/.claude/hooks/scripts/claim-sprint.sh <progress.json> <sprint_id> $CLAUDE_SESSION_ID --force`, append a row to `progress.json.adopted_by[]` (the script handles this), then proceed to Phase 3. On **no**: STOP — user will resolve manually. |

Detection during Phase 3 (mid-batch) is symmetric: `claim-sprint.sh` exit code 2 surfaces the same prompt. The whole-plan adoption case (a fresh terminal with no pointer adopting another session's PRD) is handled by `/adopt-plan`, not here.

---

## Phase 1: Discovery (Pending Task Scanner)

**Only runs when Phase 0 routes here (no existing plan).**

### Step 1.1: Spawn Discovery Agent

Spawn a single **Explore agent** (`subagent_type: "Explore"`, `model: "haiku"`) with this prompt:

> Search for pending work using this resolution order (merge results from every step that yields anything):
>
> a. **Build Candidate tags:** `git tag -l 'build-candidate/*'` — each tag points to a PRD directory. Read `git show <tag> --stat` to find the directory.
> b. **Configured location:** `task-file-location` from project CLAUDE.md `## Execution Config` (if present).
> c. **Convention fallbacks:** `docs/tasks/`, `tasks/`, `.tasks/`.
>
> Within each root, search all markdown files for unchecked items (`- [ ]`) and all `progress.json` files with incomplete sprints. For each file that contains pending items:
>
> 1. Return the full file path
> 2. Count the number of `- [ ]` (pending) and `- [x]` (completed) items
> 3. List each pending item's text
> 4. List ALL files referenced or likely modified by each pending item
> 5. If a `progress.json` exists in the same directory, note it
> 6. If the source was a Build Candidate tag, note the tag name too
>
> Also check if the user's current request describes a NEW task that doesn't have a task file yet.
>
> Return results grouped by file, sorted by modification date (oldest first).

### Step 1.2: Process Discovery Results

Based on discovery:

- **If PRD with progress.json exists:** Use the progress.json for sprint orchestration
- **If pending items in simple task files:** Add to session learnings `## Active Task Queue`
- **If user described a NEW feature/bug:** Route to `/plan` skill to create the PRD with extracted sprint specs, then return here for execution

---

## Phase 2: Batch Planning (Dependency Analysis)

**Only needed for simple tasks without sprint decomposition. PRD+Sprint tasks already have batch assignments in progress.json.**

### Step 2.1: Analyze Task Independence

Spawn a **general-purpose agent** (`model: "haiku"`) to analyze dependencies using the **Batch Planning** rules from CLAUDE.md:

> Given these task files and their pending items:
> [LIST TASK FILES WITH THEIR PENDING ITEMS AND REFERENCED FILES FROM DISCOVERY]
>
> Determine which tasks are **independent** vs **dependent** (see CLAUDE.md criteria).
>
> Return JSON with fields: `batches` (array of `{batch, tasks, parallel, reason}`) and `dependency_graph` (map of task → dependencies). When in doubt, mark tasks as DEPENDENT.

### Step 2.2: Assign Models to Tasks

For each task, determine complexity and assign a model per the CLAUDE.md Model Assignment Matrix:

- **Simple** (lint fixes, typo corrections, single-file changes): `haiku`
- **Standard** (feature implementation, bug fixes, test writing, scoped multi-file): `sonnet`
- **Complex** (architectural changes, cross-cutting refactors, 5+ files): `opus`

### Step 2.3: Present Execution Plan to User

Display the discovered queue with parallel batches, then ask:

> "I found N task files with M pending items total, organized into B batches:
>
> **Batch 1 (parallel — worktree isolation):**
>
> - `path/to/task1.md` — X pending items (model: sonnet)
> - `path/to/task2.md` — Y pending items (model: haiku)
>
> **Batch 2 (sequential — depends on Batch 1):**
>
> - `path/to/task3.md` — Z pending items (model: opus)
>
> How should I execute?"

**Autonomous mode (default):** Auto-select "Auto-start fresh context" and proceed without
asking. The user already approved the PRD — no further confirmation needed for execution
strategy. This is the permanent default behavior per CLAUDE.md "Autonomous Pipeline".

The autonomous default:

1. Write the full plan to the session learnings file with `## Execution Mode: Autonomous`
2. Set all task statuses to `NOT STARTED`
3. Output to the user: "Plan saved. Executing with fresh-context agents..."
4. **Begin the Phase 3 batch loop immediately** — the main context loops through ALL of the PRD's batches in this same session (Step 3.1 + Step 3.1.5 inter-batch handoff). After the PRD's final batch, run Phase 4/4.5/5/6, then return to Phase 1 if pending PRDs remain.
5. Report a brief summary to the user after each batch completes (≤10 lines).

**Override:** If the user explicitly asks for step-by-step execution or specific task
selection, use `AskUserQuestion` with these options:

- **Start fresh context** — Save the complete plan to the session learnings file (Active Task Queue, Parallel Batch Plan, execution mode set to "Autonomous"), then tell the user: "Plan saved. Start a new conversation and run `/plan-build-test` — it will pick up exactly where we left off and execute autonomously. Current context usage: ~X%." This preserves maximum context for execution.
- **Auto-start fresh context** — Same as above, but after saving the plan, immediately begin Phase 3 batch loop in this same session. The main context performs the orchestrator role directly per Step 3.1, looping through ALL batches; the inter-batch handoff (Step 3.1.5) plus the Compact Handling rules keep context lean across the loop without requiring fresh sessions per batch.
- **Run all autonomously** — Execute all batches (parallel where safe) without stopping in the current session
- **Run all step-by-step** — Pause after each batch for confirmation
- **Select specific tasks** — Let me choose which task files to work on

When the user selects **"Start fresh context"**:

1. Write the full plan to the session learnings file with `## Execution Mode: Autonomous`
2. Set all task statuses to `NOT STARTED`
3. Output to the user: "Plan saved to session learnings. Start a new `/plan-build-test` conversation to execute. Current context: ~X%."
4. **STOP. Do not execute anything.** The next invocation's Phase 0 will pick it up.

**NOTE:** Do NOT use `claude -p` to launch a new CLI session — it is single-turn print mode and cannot execute multi-step workflows.

---

## Phase 3: Execution — Route by Task Type

Execute task batches in order. The execution strategy depends on whether a task has sprint decomposition (progress.json) or is a simple task.

### Step 3.0: Classify Each Task

- **PRD+Sprint task** — Has a `progress.json` with sprint entries → **the main context performs the orchestrator role directly** (see Step 3.1). Do NOT spawn an `orchestrator` subagent.
- **Simple task** — Standard checklist without sprint structure → execute with **general-purpose agent**

### Step 3.1: For PRD+Sprint Tasks — Multi-Batch Execution Loop

**This skill loops through ALL of a PRD's batches in the same session.** Prompt
caching (5-min TTL) keeps progress.json, sprint specs, and Execution Config warm
across batch transitions, so finishing a PRD in one session is faster and cheaper
than restarting per batch. Multi-PRD: after a PRD's Phase 4/5/6 completes,
return to Phase 1 (Discovery) to pick up the next pending PRD — same session.

**Context discipline (this is what makes the multi-batch loop safe):**

1. **Subagent returns are strictly summarized.** Per the CLAUDE.md
   "Subagent Communication Protocol", every sprint-executor and code-reviewer
   prompt MUST end with "Return a structured summary: [exact fields]" and the
   target is 10–20 lines. If a subagent returns more than ~20 lines, write a
   ≤5-line digest of it to session-learnings BEFORE starting the next batch
   and treat the original verbose return as discarded. Never forward a raw
   subagent return into the next batch's prompts.
2. **Inter-batch handoff (Step 3.1.5)** runs after every batch and writes a
   durable `## Active Plan State` block to session-learnings — so a `/compact`
   at any point recovers cleanly.
3. **Compact handling** (table after Step 3.1.5) defines what to keep vs. drop
   when `/compact` fires mid-PRD.

**The main context IS the orchestrator** — do NOT spawn a separate `orchestrator`
subagent. The deterministic checklist lives in `~/.claude/agents/orchestrator.md`
(Steps 0–10); the main context follows it directly because (a) it has full tool
access including `Agent` for spawning sprint-executor and code-reviewer
subagents — a separate orchestrator subagent has been observed to land without
the `Agent` tool in some toolkit configurations, silently degrading to
single-context implementation; (b) it removes one context boundary that loses
progress.json/session-learnings state on return; (c) one main-context
orchestrator owns the whole PRD's mental model and benefits from prompt caching
across batches.

Execute each batch by following the orchestrator protocol in
`~/.claude/agents/orchestrator.md` directly from this main context.
Quick reference (read the agent file for full details):

1. **Step 0 — Preflight:** git readiness, working tree hygiene, stale worktree
   cleanup, proot detection, dependency baseline.
2. **Step 1 — Read State:** load `progress.json`, project CLAUDE.md Execution
   Config, session learnings (for accumulated rules), and prior sprints' Agent
   Notes; identify the lowest-numbered batch with `not_started`/`in_progress`
   sprints. This is THE batch.
3. **Step 2 — Load Sprint Specs:** read each sprint spec file in the batch;
   verify file boundaries don't conflict within the batch.
4. **Step 3 — Mark `in_progress`** in `progress.json`.
5. **Step 4 — Spawn sprint-executor(s)** via `Agent` (sonnet, `isolation:
   "worktree"` for independent sprints; sequential in the main worktree if
   `files_to_modify` overlap). Use a single message for parallel batches.
   Each sprint-executor prompt includes ONLY its own sprint spec content,
   prior Agent Notes, and Execution Config — never the full PRD.
6. **Step 5 — Collect results** and verify commits exist on each worktree
   branch (`git log <branch> --not main --oneline` + `git status --porcelain`).
   Self-reports are not trusted.
7. **Step 6 — Merge** (sequential, lowest sprint first), file-boundary
   validation, worktree cleanup.
8. **Step 6.6 — Code review:** spawn `code-reviewer` (sonnet, read-only) via
   `Agent`. Outcome: PASS / NEEDS CHANGES / BLOCKING.
9. **Step 7 — Coherence check.**
10. **Step 8 — Dev server smoke test (content-verified).**
11. **Step 8.5 — Plan completeness audit** (cite evidence per acceptance
    criterion; verify `INVARIANTS.md`; write completion evidence marker).
12. **Step 9 — Update `progress.json`** and append Agent Notes to each sprint
    spec file (decisions, assumptions, issues, follow-ups for next batch).

After the batch finishes:

- Re-read `progress.json` to confirm the canonical state on disk.
- Update session learnings (status, errors, new rules from this batch only).
- Route based on progress.json state:
  - **More `not_started`/`in_progress` batches remain:**
    Report a brief batch N summary (≤10 lines) to the user, then run
    **Step 3.1.5 — Inter-Batch Handoff**, then loop back to the top of
    Step 3.1 for batch N+1. Do NOT stop. Do NOT ask the user to start a
    new session.
  - **ALL batches in this PRD complete:**
    Proceed to Phase 4 (Post-Implementation Review), then Phase 4.5
    (integrate to main), then Phase 5 (Live Verification), then Phase 6
    (Learning). These phases run **after each PRD** — including when
    multiple PRDs are processed in the same session.
  - **Batch had blocked sprints:** Report blocked state and STOP — user
    decides retry / re-plan / abandon.

### Step 3.1.5: Inter-Batch Handoff (runs after EVERY batch, before the next)

This is what makes the multi-batch loop safe. Run these steps in order:

1. **Re-read `progress.json`** from disk — it is the canonical state. Do NOT trust an in-memory snapshot from before the batch ran.

2. **Write the `## Active Plan State` block** to the project's session-learnings file (path from project CLAUDE.md `session-learnings-path`, default `docs/session-learnings.md`). Replace any existing block of the same name — there is exactly one Active Plan State at a time. Format:
   ```markdown
   ## Active Plan State

   - PRD: <prd_dir absolute path>
   - PRD slug: <prd_slug>
   - Just completed: batch N (sprint IDs: ...)
   - Next batch: batch N+1 (sprint IDs: ...)
   - Next batch's sprint spec files:
     - <full path>
     - <full path>
   - Inter-batch rules learned this batch (≤5 bullets, each ≤1 line)
   - Updated: <ISO-8601 UTC>
   ```

3. **Discard previous-batch verbose subagent returns** from working memory. Concretely: if the just-completed batch's sprint-executor or code-reviewer returned more than ~20 lines, write a ≤5-line digest to session-learnings under the prior batch's heading, then treat the original as discarded. Never quote a previous batch's verbose return into the next batch's subagent prompts.

4. **Re-read only the next batch's sprint spec files** — not previous batches' specs, not the full PRD, not completed sprints' Agent Notes beyond the immediately previous one (per orchestrator Step 4 rules).

5. **Heartbeat refresh** for any sprints still `in_progress` from a partially-blocked batch (per orchestrator Step 5).

6. **Continue to the next batch** by jumping back to the top of Step 3.1.

### Compact Handling within `/plan-build-test`

When `/compact` fires mid-PRD (autocompact threshold, manual `/compact`, or unexpected), follow this allow/deny list:

| Keep (re-read from disk after compact) | Drop (do not re-load into context) |
|---|---|
| `progress.json` — single source of truth for batch/sprint status | Previous batches' sprint-executor full returns |
| The current batch's sprint spec files only | Previous batches' code-review full reports |
| `## Active Plan State` block from session-learnings | Phase 1 discovery output |
| `INVARIANTS.md` (if present) | Anything from before this PRD's adoption |
| Project CLAUDE.md `## Execution Config` | The full PRD `spec.md` (sprint specs are self-contained) |
| Active-plan pointer (`~/.claude/state/active-plan-<session>.json`) | Verbose tool outputs from completed verification steps |

The PreCompact hook (`~/.claude/hooks/compact-save.sh`) already writes a Compact Checkpoint to session-learnings before compaction, and PostCompact (`compact-restore.sh`) emits it back. **After PostCompact restore, re-read in this exact order:** active-plan pointer → progress.json → Active Plan State block → next batch's sprint specs → INVARIANTS.md → Execution Config. Do NOT re-read anything in the "Drop" column above.

### Step 3.2: For Simple Tasks — General-Purpose Agent

**Single-task batch (no worktree needed):**
Spawn a **general-purpose agent** (`model: [assigned]`) with the task prompt.

**Multi-task batch (parallel with worktrees):**
Spawn **all agents simultaneously in a single message** using `isolation: "worktree"`.

### Step 3.3: Simple Task Agent Prompt Template

> You are a Task Executor. Your job is to complete all pending items in the task file:
> `[FULL_PATH_TO_TASK_FILE]`
>
> **Rules:**
>
> 1. Read the task file first. Identify all `- [ ]` items.
> 2. Work through items **in order**, top to bottom.
> 3. For each item:
>    a. Locate the relevant code
>    b. Implement the fix/feature (follow TDD if writing new code)
>    c. Use `Edit` tool to change `- [ ]` to `- [x]` IMMEDIATELY after completing each item
>    d. Never batch checkbox updates — one at a time
> 4. If you encounter a blocker:
>    a. Log it in the task file under a `## Issues` section
>    b. Attempt to fix. If requires architectural changes, note it and move on.
> 5. After completing all items, run verification commands and report results:
>    - Build command (zero errors)
>    - Lint command (zero issues)
>    - Type-check command (zero errors)
> 6. Return structured summary:
>    - Items completed (count and list)
>    - Items failed (count and list with reasons)
>    - Errors encountered
>    - Files modified (full paths)
>    - Build/lint/type check results (pass/fail)
>
> **Standards:**
>
> - Use the project's package manager exclusively (from project CLAUDE.md)
> - Run the kill command from Execution Config before starting dev servers or tests
> - Follow mobile-first order for UI changes
> - Zero console errors in final result
>
> **Learnings from previous tasks in this session:**
> [PASTE RELEVANT RULES FROM SESSION LEARNINGS FILE HERE]
>
> **Known patterns (from project knowledge files):**
> [PASTE RELEVANT PATTERNS FROM PROJECT KNOWLEDGE FILES]

### Step 3.4: Post-Batch Merge

Follow the **Merge Protocol** from CLAUDE.md. Then:

1. Verify checkboxes were updated (read task/sprint spec files)
2. Update session learnings (completed tasks, merge log, errors, agent performance)
3. **Feed forward:** Extract rules from session learnings to include in NEXT batch's prompts

### Step 3.5: Phase 5 Checkpoint (MANDATORY)

After ALL batches complete:

1. Write to session learnings: `## Phase 5 Required — DO NOT SKIP`
2. If context is degrading: save state and tell user to start new session
3. Phase 5 verification is NOT optional. NEVER return "all tasks complete" without it.

### Step 3.6: Inter-Batch Learning Loop

Before spawning the next batch:

1. Re-read session learnings for accumulated knowledge
2. Include relevant `## Rules for Next Iteration` in each agent's prompt
3. If previous batch had merge conflicts, add a rule about the conflicting area

This creates a **batch learning chain**: Batch 1's mistakes become Batch 2's rules.

---

## Phase 4: Post-Implementation Review & Simplification

After all batches complete (and merge, if parallel):

### Step 4.1: Code Review

Spawn a `code-reviewer` agent to inspect ALL changes from this build:

```
Agent(description: "Review all build changes",
      prompt: "Review all files changed since the build started.
              Run: git diff --name-only [PRE_BUILD_SHA]..HEAD to find changed files.
              Check: correctness vs spec, security, patterns, edge cases, test coverage, coherence.
              Return: PASS / NEEDS CHANGES / BLOCKING ISSUES with severity-coded findings.",
      subagent_type: "code-reviewer",
      model: "sonnet")
```

- **BLOCKING ISSUES:** Fix before proceeding to Phase 5. Max 2 fix attempts.
- **NEEDS CHANGES:** Log findings; fix if quick, otherwise note for post-ship cleanup.
- **PASS:** Proceed.

### Step 4.2: Code Simplification

Use the **code-simplifier** plugin to review the changed code for reuse, quality, and efficiency. Fix any issues it finds before proceeding to verification.

**Fallback:** If the code-simplifier plugin is unavailable (disabled, marketplace issue), skip
this step and proceed to Phase 4.5. Code review (Step 4.1) already covers quality; simplification
is an optimization, not a gate.

---

## Phase 4.5: Integrate `prd/<slug>` to `main` (flock-serialized)

**Runs after each PRD's final batch — i.e. when all sprints in this PRD's `progress.json` are `complete` after Phase 4. If multiple PRDs are processed in one session, each PRD goes through its own Phase 4 → 4.5 → 5 → 6 cycle.**

Sprints during execution merge into the per-PRD integration branch `prd/<PRD_SLUG>`, never directly into `main`. This phase performs the single merge of `prd/<PRD_SLUG>` into `main`, serialized across concurrent sessions via a global `flock` so two PRDs finishing at the same time can't race on `main`.

### Step 4.5.1: Acquire the main-merge lock

```bash
PRD_SLUG="$(jq -r .prd_slug ~/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json)"
LOCK="$(git rev-parse --git-dir)/main-merge.lock"
exec 8>"$LOCK"
flock -x -w 600 8 || { echo "BLOCKED: peer holding main-merge.lock >10 min"; exit 1; }
```

If the lock times out (10 min), STOP and report BLOCKED — a peer session is mid-merge and the user must investigate. Do NOT bypass.

### Step 4.5.2: Fetch, check out main, merge `prd/<slug>`

```bash
git fetch
git checkout main
git pull --ff-only         # keep main fast-forwarded
git merge --no-ff "prd/$PRD_SLUG" -m "merge: PRD $PRD_SLUG"
```

**Conflict resolution:**

- ≤ 3 files conflicted → resolve inline using the **Merge Protocol** from CLAUDE.md.
- > 3 files conflicted → spawn an **opus agent** to resolve (matches the orchestrator's existing >3-file conflict path). Pass the merge context, list of conflicted files, and instructions to preserve both sides' intent.

### Step 4.5.3: Verify the integrated `main` builds

Run the gates against the integrated tree before releasing the lock:

```bash
[build] && [lint] && [type-check] && [test]
```

If ANY gate fails:

```bash
git reset --merge HEAD~1   # abort the merge cleanly
exec 8>&-                  # release the lock
```

Then report BLOCKED with the failing gate's output. The PRD branch is preserved untouched on `prd/<PRD_SLUG>` — the user can re-run `/plan-build-test` after fixing.

### Step 4.5.4: Release the lock

```bash
exec 8>&-
```

Phase 5 verification then runs against integrated `main`.

---

## Phase 5: Live Verification (MANDATORY — CANNOT BE SKIPPED)

**This is the quality gate. Everything before this is "probably works."
This phase proves it ACTUALLY works — with a running server, real HTTP requests,
and Playwright tests. The pipeline is NOT complete until this phase passes.**

**BLOCKING RULE: Do NOT report "all tasks complete" or present a session report
unless ALL steps in Phase 5 have passed. If any step is blocked, report BLOCKED
status and the reason — never silently skip.**

### Step 5.1: Static Verification

Run these commands directly (no subagent needed for simple commands):

```
1. Kill command (from Execution Config)
2. Build command → must exit 0
3. Lint command → must exit 0, 0 issues
4. Type-check command → must exit 0
5. Test command → must exit 0
```

If any fail: fix the issue, re-run. Max 3 fix attempts per command. If still
failing after 3: mark as BLOCKED, log in session learnings, report to user.

### Step 5.2: Dev Server Startup + Content Verification (MANDATORY)

Full protocol: `~/.claude/docs/on-demand/dev-server-protocol.md`

Summary: run kill command → start dev server (background, log to file) → poll log up to 60s
for ready signal → curl key routes, verify HTTP 200 AND inspect body for expected content /
absence of error strings → max 3 fix-retry cycles with a different fix each time → mark
BLOCKED if still failing (do NOT accept "environment limitation" as a reason to skip).

Tests passing does NOT mean the app works — content verification catches the gap. For each
key route modified by this task, verify actual rendered content matches acceptance criteria.
If Playwright MCP is available in context, use `browser_navigate` + `browser_snapshot` for
richer verification. **This step is BLOCKING. Do NOT proceed to Step 5.3 if it fails.**

### Step 5.3: Route Health Check (MANDATORY)

**Every route defined in the project must return HTTP 200. No exceptions.**

1. Determine all routes from the project's routing structure:
   - **Next.js App Router:** Glob for `app/**/page.tsx` files
   - **Next.js Pages Router:** Glob for `pages/**/*.tsx` (excluding `_app`, `_document`, `_error`)
   - **Remix/React Router:** Glob for `app/routes/**/*.tsx`
   - **SvelteKit:** Glob for `src/routes/**/+page.svelte`
   - **Astro:** Glob for `src/pages/**/*.astro`
   - **Other frameworks:** Check project CLAUDE.md Execution Config for `route_pattern`, or ask user
   - Convert file paths to URL paths (e.g., `app/[locale]/product/page.tsx` → `/en/product/`)
   - Include all locale variants (e.g., `/en/product/`, `/pt-br/product/`)

2. Curl each route with `curl -sL -o /dev/null -w "%{http_code}"` (follow redirects), printing `"$route → $code"` for each.

3. **ALL routes must return 200.** If any route returns 404, 500, or other error:
   - Investigate the cause (missing page, broken import, runtime error)
   - Fix the issue
   - Re-test ALL routes (not just the fixed one — fixes can cause regressions)
   - Max 3 fix-and-retry cycles

4. Report results as a table:
   ```
   | Route | Status | Result |
   |-------|--------|--------|
   | /en/  | 200    | PASS   |
   | /en/product/ | 200 | PASS |
   | /pt-br/ | 200 | PASS |
   ```

5. If any route still fails after 3 fix attempts: mark as BLOCKED, list the
   failing routes and their error codes. Do NOT proceed to Step 5.4.

### Step 5.4: Playwright E2E Tests (MANDATORY for UI projects)

**Run Playwright tests against the LIVE dev server. Screenshots must be captured.**

1. Ensure Playwright browsers are available:
   ```bash
   pnpm exec playwright install chromium
   ```
   **Note:** Chromium works in proot-distro ARM64 (`/usr/bin/chromium`). Playwright E2E tests
   run normally — do NOT skip or mark as BLOCKED.

2. If a Playwright test file exists (check `tests/` or `e2e/` directory):
   - Run: `pnpm exec playwright test`
   - All tests must pass

3. If NO Playwright test file exists, create a comprehensive screenshot test:
   ```
   - Navigate to every route (all locales)
   - At each of 4 viewports: 375px (mobile), 768px (tablet), 1280px (desktop), 1920px (wide)
   - Capture full-page screenshot
   - Capture and report any console errors
   - Save screenshots to tests/screenshots/
   ```

4. Run the Playwright test:
   - Must exit 0
   - Must produce screenshots for ALL routes at ALL viewports
   - Console errors count: must be 0

5. If Playwright tests fail:
   - Read the failure output
   - Fix the issue (broken component, console error, navigation failure)
   - Re-run the full test suite
   - Max 3 fix-and-retry cycles

6. Report results:
   ```
   - Playwright: PASS/FAIL (N tests, M passed, X failed)
   - Screenshots captured: N (expected: M)
   - Console errors: N (must be 0)
   - Failing tests: [list with reasons]
   ```

### Step 5.5: Task File Audit (Plan Completeness Re-Read)

**Re-read the ORIGINAL plan and enumerate what's done vs. what's not.**

1. Read each task/sprint spec file IN FULL — do not rely on memory
2. For every `- [ ]` item: list it explicitly as INCOMPLETE
3. For every `- [x]` item: verify it was actually completed (not just checkbox'd)
4. For every acceptance criterion in the spec:
   - State: MET / NOT MET / PARTIALLY MET
   - Cite specific evidence (command output, route verification, test name)
   - If you cannot cite evidence: it is NOT MET, even if you "think" you did it
5. Count total checked vs unchecked
6. **If ANY items are unchecked or criteria unmet:**
   - List them explicitly
   - Either complete them now or mark as BLOCKED with reason
   - Do NOT proceed to Step 5.9 with unfinished items

### Step 5.6: Regression Scan

Search source files (not node_modules) for:
- `console.log` / `console.debug` (should be removed)
- Unresolved `TODO` / `FIXME` comments
- Unused imports (rely on lint results)

### Step 5.7: Handle Failures (targeted re-verification with adaptive retries)

For ANY failure in Steps 5.1-5.6:

1. Log the failure in the session learnings file with category:
   `[ENV|LOGIC|CONFIG|DEPENDENCY|SECURITY|TEST|DEPLOY|PROOT|PERFORMANCE]`
2. Determine the fix approach:
   - Lint/format issue → `haiku` agent
   - Build/type error → `sonnet` agent
   - Logic/integration error → `opus` agent
   - Dev server/environment issue → fix directly (no agent needed)
3. Apply the fix
4. **Targeted re-verification** (not full restart):
   - If lint failed → re-run from lint forward (skip build if build already passed)
   - If type-check failed → re-run from type-check forward
   - If dev server failed → re-run from dev server forward (skip static checks)
   - If content verification failed → re-run from content verification forward
   - **Exception:** If the fix modified source code (not just config), re-run from build forward
5. **Adaptive retry budget** by failure category (canonical defaults from `~/.claude/rules/quality.md`):

   | Category      | Default budget | Aggressive-fix-loop budget | Delta  |
   |---------------|---------------|---------------------------|--------|
   | `transient`   | 5             | 5                         | —      |
   | `logic`       | 2             | **4**                     | +2     |
   | `environment` | 1             | 1                         | —      |
   | `config`      | 3             | 3                         | —      |

   **Mode detection:** check `[[ "$CLAUDE_PIPELINE_MODE" == *aggressive-fix-loop* ]]` before
   each `logic` failure retry. If the substring matches, apply the aggressive budget (4);
   otherwise apply the default (2). No other category is affected.

   **Rationale for raising only `logic`:** `logic` failures are the category where "try a
   different approach" yields fresh signal each attempt. `transient` already has 5 retries.
   `environment` retries are futile — the proot environment lacks the same things on attempt
   N as on attempt 1 (see PRD Section 2, Danger Definition). Raising `config` above 3 rarely
   helps — the fix space is small. Aggressive-fix-loop mode is for autonomous staging runs
   where logic failures often cluster (one failing test reveals a related test also failing);
   4 attempts lets the loop self-heal distinct logic-class failures without removing the cap
   entirely. A hard cap is mandatory — "no cap" is a danger (PRD Section 2).

   **`environment` budget is NOT raised in aggressive mode** — env failures indicate a
   systemic proot limitation that more attempts cannot resolve. Mark BLOCKED immediately
   after 1 retry regardless of `CLAUDE_PIPELINE_MODE`.

   **Session-learnings logging requirement (aggressive mode):** Each `logic` retry beyond
   attempt 2 (i.e., attempts 3 and 4) MUST log its "different approach" rationale to the
   session learnings file, using the structured format defined in `~/.claude/rules/quality.md`:
   ```
   [LOGIC-RETRY-<n>] <brief description of new approach tried and why prior approach failed>
   ```
   This makes repeated-approach violations visible in the artifact and distinguishes
   genuine iterative debugging from blind retry loops.

6. After retry budget exhausted: report BLOCKED with full details and category.

### Step 5.8: Kill Dev Server

After all verification passes, kill the dev server:
```bash
[kill command from Execution Config]
```

### Step 5.9: Final Gate — Verification Summary

Present this summary. ALL items must show PASS. Use the table template in `~/.claude/skills/plan-build-test/refs/final-gate-template.md`.

**If ALL items show PASS:**
→ "All live verification passed. Dev server tested with N routes returning 200,
   Playwright captured M screenshots with 0 console errors. Test manually, then
   run `/ship-test-ensure` to deploy."
→ Proceed to Phase 6 automatically (autonomous mode — no pause needed).

**If ANY item shows FAIL or BLOCKED:**
→ Report the failures clearly in the session report. Do NOT tell the user the build is complete.
→ Do NOT proceed to Phase 6.
→ In autonomous mode: exhaust all retry budgets first. If still failing after retries,
  report BLOCKED with full details and stop. The user will see the report and decide.
→ Do NOT silently accept failures — the report must be honest and complete.

---

## Phase 6: Learning & Self-Improvement

After Phase 5 passes, invoke `/compound` — it handles all learning capture (error-registry, model-performance, session-postmortem, workflow-changelog). Compound is the single authority for learning capture.

### Step 6.3: Session Report

Present the session report using the template in `~/.claude/skills/plan-build-test/refs/session-report-template.md`.

### Step 6.5: Worktree & Artifact Cleanup (namespace-scoped)

After learning capture, ensure a clean state — touching ONLY this session's namespace. Concurrent peer sessions may still have live worktrees and branches; this step must never delete them.

```bash
PRD_SLUG="$(jq -r .prd_slug ~/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json)"

git worktree prune

# Delete only this PRD's sprint branches that are merged into prd/<slug>.
git branch --list "sprint/$PRD_SLUG/*" --merged "prd/$PRD_SLUG" \
  | sed 's/^[* ]*//' \
  | xargs -r -n1 git branch -d

# Delete the integration branch only after main has it.
if git merge-base --is-ancestor "prd/$PRD_SLUG" main 2>/dev/null; then
  git branch -d "prd/$PRD_SLUG"
fi

# Remove this session's pointer (PRD itself stays — adoptable later).
rm -f "$HOME/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json"
```

Then:

1. Verify `git worktree list` shows no worktrees under `.worktrees/$PRD_SLUG/`. Peer slugs may still appear — that's expected.
2. Move any stray artifacts from project root to `.artifacts/` (the cleanup-artifacts.sh Stop hook handles this, but verify).
3. Log cleanup results to session learnings.

**Never** run `git branch --merged | grep sprint/` or `git worktree remove` against unfiltered patterns — that deletes peer sessions' work. Always scope to `$PRD_SLUG`. The `cleanup-worktrees.sh` Stop hook applies the same rule from the foreign-slug skiplist side.

---

## Standards (skill-specific, in addition to CLAUDE.md)

- Task file must always reflect actual progress — never stale
- progress.json must be updated after EVERY sprint completion (the main context updates it directly per Step 3.1)
- Session learnings file must be updated after EVERY batch
- Each batch inherits rules from all previous batches
- **ALWAYS persist new knowledge** to project knowledge files when something fails and gets fixed
- **NO commits, deploys, or staging** — this skill is local-only
- After local verification, tell user to test manually then run `/ship-test-ensure`
- Use the project's package manager, build tools, and commands from project CLAUDE.md
- Follow project-specific environment rules from project CLAUDE.md

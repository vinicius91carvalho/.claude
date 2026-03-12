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

Plan, implement, and test features entirely locally: discover tasks, simplify, plan, implement with agent teams, run all tests and E2E locally, then learn. No commits, no deploys, no staging — that's what `/ship-test-ensure` is for after you've manually verified.

Operate as a **Team Lead** coordinating specialist agents — using parallel worktrees for independent tasks and sequential execution for dependent ones.

**Inherited from CLAUDE.md** (applies to all phases below):

- Context Engineering — orchestrator pattern, subagent communication, context budget
- Model Assignment Matrix — haiku/sonnet/opus per task type
- Parallel Execution with Worktrees — batch planning, isolation, merge protocol
- Session Learnings — compact-safe memory at the path specified in project CLAUDE.md
- Self-Improvement Protocol — compile, persist, generate rules

**Inherited from project knowledge files** (applies to all phases below):

- Troubleshooting patterns — known gotchas and their solutions
- Environment knowledge — project-specific constraints, port conflicts, runtime requirements

---

## Project Configuration Contract

This skill reads project-specific commands and paths from the project's `CLAUDE.md` file. The project MUST define an `## Execution Config` section (or equivalent) containing:

| Key                      | Purpose                          | Example                                                   |
| ------------------------ | -------------------------------- | --------------------------------------------------------- |
| `build`                  | Build all packages/apps          | `pnpm turbo build`, `npm run build`, `make build`         |
| `test`                   | Run unit/integration tests       | `pnpm turbo test`, `npm test`, `cargo test`               |
| `lint`                   | Run linter/formatter check       | `pnpm exec biome check .`, `npm run lint`, `cargo clippy` |
| `lint-fix`               | Auto-fix lint/format issues      | `pnpm exec biome check --write .`, `npm run lint:fix`     |
| `type-check`             | Run type checker                 | `pnpm turbo check-types`, `tsc --noEmit`                  |
| `e2e`                    | Run E2E tests                    | `pnpm exec playwright test`, `npm run e2e`, `cypress run` |
| `dev`                    | Start dev server                 | `pnpm turbo dev`, `npm run dev`, `cargo run`              |
| `kill`                   | Kill running dev/test processes  | `pkill -f "next-server"`, `killall node`                  |
| `session-learnings-path` | Path to session learnings file   | `/path/to/session-learnings.md`                           |
| `task-file-location`     | Where task files live            | `docs/tasks/<app>/<category>/YYYY-MM-DD_HHmm-name.md`     |
| `knowledge-files`        | Project knowledge/patterns files | `patterns.md`, `MEMORY.md`                                |

If the project CLAUDE.md does not define explicit commands, infer them from the project's `package.json`, `Makefile`, `Cargo.toml`, or equivalent build configuration. Always confirm with the user before executing inferred commands.

---

## PHASE 0: RESUME GATE (Always Runs First)

**This phase determines where to start. It prevents the loop of re-discovery when a plan already exists.**

### Step 0.1: Read Session Learnings

Read the session learnings file from the path specified in the project's CLAUDE.md. Check for:

- `## Active Task Queue` — already-planned batches with task files
- `## Parallel Batch Plan` — batch structure (parallel/sequential, models, dependencies)
- `## Execution Mode` — user's chosen mode (autonomous, step-by-step, etc.)
- Task statuses: `NOT STARTED`, `IN PROGRESS`, `COMPLETE`

### Step 0.2: Route Decision

| Session Learnings State                                         | Action                                                                                                           |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Has Active Task Queue with NOT STARTED or IN PROGRESS tasks** | **SKIP to Phase 2** (Execution). The plan exists. Do NOT re-discover. Do NOT re-ask the user for execution mode. |
| **Has Active Task Queue but ALL tasks are COMPLETE**            | Go to Phase 5 (Learning) if compound wasn't done, otherwise tell user all tasks are complete.                    |
| **No Active Task Queue OR file doesn't exist**                  | Go to Phase 1 (Discovery) — this is a fresh start.                                                               |
| **User explicitly described a NEW task** (not in any task file) | Go to Phase 1 (Discovery) to scan existing tasks AND create a new task file for the user's request.              |

**The key rule: If session learnings already have a plan with pending tasks, EXECUTE IT. Don't re-plan.**

---

## Phase 1: Discovery (Pending Task Scanner)

**Only runs when Phase 0 routes here (no existing plan in session learnings).**

### Step 1.1: Spawn Discovery Agent

Spawn a single **Explore agent** (`subagent_type: "Explore"`, `model: "haiku"`) with this prompt:

> Search all markdown files in the task file directory (from project CLAUDE.md) for unchecked items (`- [ ]`). For each file that contains pending items:
>
> 1. Return the full file path
> 2. Count the number of `- [ ]` (pending) and `- [x]` (completed) items
> 3. List each pending item's text
> 4. List ALL files referenced or likely modified by each pending item (look for file paths, component names, page names in the item text)
>
> Also check if the user's current request describes a NEW task that doesn't have a task file yet.
>
> Return results grouped by file, sorted by modification date (oldest first).

### Step 1.2: Process Discovery Results

Based on the discovery agent's results, determine the work queue:

- **If pending items exist in existing task files:** Add them to the session learnings `## Active Task Queue`
- **If the user described a NEW feature/bug:** Create a new task file following CLAUDE.md conventions (using the task file location pattern from project CLAUDE.md), write the plan inside it, and add it to the queue

---

## Phase 1.5: Dependency Analysis & Parallel Batch Planning

### Step 1.5.1: Analyze Task Independence

Spawn a **general-purpose agent** (`model: "haiku"`) to analyze dependencies using the **Batch Planning** rules from CLAUDE.md:

> Given these task files and their pending items:
> [LIST TASK FILES WITH THEIR PENDING ITEMS AND REFERENCED FILES FROM DISCOVERY]
>
> Determine which tasks are **independent** vs **dependent** (see CLAUDE.md criteria).
>
> Return a JSON structure:
>
> ```json
> {
>   "batches": [
>     {
>       "batch": 1,
>       "tasks": ["task1.md", "task2.md"],
>       "parallel": true,
>       "reason": "touch different pages"
>     },
>     {
>       "batch": 2,
>       "tasks": ["task3.md"],
>       "parallel": false,
>       "reason": "depends on task1 shared layout changes"
>     }
>   ],
>   "dependency_graph": { "task3.md": ["task1.md"] }
> }
> ```
>
> When in doubt, mark tasks as DEPENDENT.

### Step 1.5.2: Assign Models to Tasks

For each task, determine complexity and assign a model per the CLAUDE.md Model Assignment Matrix:

- **Simple** (lint fixes, typo corrections, single-file changes): `haiku`
- **Standard** (feature implementation, bug fixes, test writing, scoped multi-file): `sonnet`
- **Complex** (architectural changes, cross-cutting refactors, 5+ files): `opus`

### Step 1.5.3: Present Execution Plan to User

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

Use `AskUserQuestion` with these options (MANDATORY — always present all):

- **Start fresh context (Recommended)** — Save the complete plan to the session learnings file (Active Task Queue, Parallel Batch Plan, execution mode set to "Autonomous"), then tell the user: "Plan saved. Start a new conversation and run `/plan-build-test` — it will pick up exactly where we left off and execute autonomously. Current context usage: ~X%." This preserves maximum context for execution.
- **Auto-start fresh context** — Same as above, but after saving the plan, automatically start a new Claude Code session by running: `claude -p "/plan-build-test"`. The new session picks up the plan from the session learnings file and executes autonomously. No manual intervention needed.
- **Run all autonomously** — Execute all batches (parallel where safe) without stopping in the current session
- **Run all step-by-step** — Pause after each batch for confirmation
- **Select specific tasks** — Let me choose which task files to work on

When the user selects **"Start fresh context"**:

1. Write the full plan to the session learnings file with `## Execution Mode: Autonomous`
2. Set all task statuses to `NOT STARTED`
3. Output to the user: "Plan saved to session learnings. Start a new `/plan-build-test` conversation to execute. Current context: ~X%."
4. **STOP. Do not execute anything.** The next invocation's Phase 0 will pick it up.

When the user selects **"Auto-start fresh context"**:

1. Write the full plan to the session learnings file with `## Execution Mode: Autonomous`
2. Set all task statuses to `NOT STARTED`
3. Output to the user: "Plan saved. Launching new session to execute..."
4. Run: `claude -p "/plan-build-test"` to start a new session that will pick up the plan
5. **STOP the current session.**

---

## Phase 2: Parallel Batch Execution with Worktrees

Execute task batches in order. Follow the **Parallel Execution with Worktrees** protocol from CLAUDE.md.

### Step 2.1: For Each Batch in the Queue

**Before spawning agents:**

1. Read all task files in this batch to get their current state
2. Update the session learnings file — mark batch as in-progress

#### Case A: Single-Task Batch (no worktree needed)

Spawn a **general-purpose agent** (`model: [assigned]`) with the task prompt (see Step 2.2).

#### Case B: Multi-Task Batch (parallel with worktrees)

Spawn **all agents simultaneously in a single message** using `isolation: "worktree"`:

```
Task(subagent_type: "general-purpose", model: "sonnet", isolation: "worktree", prompt: "...task1...")
Task(subagent_type: "general-purpose", model: "haiku", isolation: "worktree", prompt: "...task2...")
```

**Worktree agent rules:** Isolated branch from HEAD, cannot see other agents' changes, must NOT modify the session learnings file or install dependencies.

### Step 2.2: Task Agent Prompt Template

> You are a Task Executor. Your job is to complete all pending items in the task file:
> `[FULL_PATH_TO_TASK_FILE]`
>
> **Rules:**
>
> 1. Read the task file first. Identify all `- [ ]` items.
> 2. Work through items **in order**, top to bottom.
> 3. For each item:
>    a. Locate the relevant code
>    b. Implement the fix/feature (follow TDD if writing new code: tests first, then implementation)
>    c. Use `Edit` tool to change `- [ ]` to `- [x]` in the task file IMMEDIATELY after completing each item
>    d. Never batch checkbox updates — one at a time
> 4. If you encounter an error or blocker:
>    a. Log it in the task file under a `## Issues` section
>    b. Attempt to fix it. If the fix requires architectural changes, note it and move to the next item.
> 5. After completing all items, run these verification commands (from the project's Execution Config) and report results:
>    - Build command (zero errors)
>    - Lint command (zero lint issues)
>    - Type-check command (zero type errors)
> 6. Return a structured summary:
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
> - Add concise comments to any non-obvious logic you write (explain WHY, not WHAT)
>
> **Learnings from previous tasks in this session:**
> [PASTE RELEVANT RULES FROM SESSION LEARNINGS FILE HERE]
>
> **Known patterns (from project knowledge files):**
> [PASTE RELEVANT PATTERNS FROM PROJECT KNOWLEDGE FILES]

### Step 2.3: Post-Batch Merge

Follow the **Merge Protocol** from CLAUDE.md. Then:

1. Read each task file to verify checkboxes were updated
2. Update the session learnings file (completed tasks, merge log, errors, agent performance)
3. **Feed forward:** Extract rules from the session learnings file to include in the NEXT batch's agent prompts

### Step 2.4: Inter-Batch Learning Loop

Before spawning the next batch:

1. Re-read the session learnings file to get accumulated knowledge
2. Include relevant `## Rules for Next Iteration` in each agent's prompt
3. If a previous batch had merge conflicts, add a rule about the conflicting area

This creates a **batch learning chain**: Batch 1's mistakes become Batch 2's rules, etc.

---

## Phase 2.5: Post-Implementation Simplification

After all batches complete (and merge, if parallel), invoke the `/simplify` skill to review the changed code for reuse, quality, and efficiency. Fix any issues it finds before proceeding to verification.

---

## Phase 3: Local Verification

After ALL batches are processed:

### Step 3.1: Spawn Verification Agent

Spawn a **general-purpose agent** (`model: "sonnet"`) for comprehensive verification:

> You are a Verification Agent. All task files have been implemented. Independently verify the work.
>
> **Step A: Build & Test Suite**
> Run the kill command from Execution Config to stop running processes, then run and report results for each command from the project's Execution Config:
>
> - Build command
> - Test command
> - Lint command
> - Type-check command
>   Fix issues and re-run until clean.
>
> **Step B: Local E2E Tests**
> Run the E2E test command from Execution Config. If tests fail, fix and re-run until clean.
>
> **Step C: Task File Audit**
> Read each task file: [LIST ALL TASK FILES]. Verify all `- [ ]` -> `- [x]`, no silently skipped items.
>
> **Step D: Regression Scan**
> Search for: unused imports, console.log/debug code, unresolved TODO/FIXME.
>
> Return a structured report: pass/fail per command, E2E results, task file audit results, regression findings.

### Step 3.2: Handle Local Verification Failures

1. Log failures in the session learnings file
2. Assign fix agent model per CLAUDE.md matrix (lint -> haiku, build -> sonnet, logic -> opus)
3. Spawn fix agents sequentially, re-verify, repeat until clean

### Step 3.3: Visual Verification (if UI changes were made)

If the project has a visual verification skill or browser-based testing workflow, invoke it for Playwright/browser verification and user confirmation. Otherwise, instruct the user to manually verify UI changes via the dev server.

### Step 3.4: Code Simplification (Optional — Run First on Large Tasks)

Before implementing new features on complex codebases, simplify the affected code first. Simpler code = fewer bugs, easier maintenance, easier to read.

Invoke the `/simplify` skill. It will review the changed/affected code for reuse, quality, and efficiency, then fix any issues found automatically.

### Step 3.5: Dev Server Smoke Test

Start the dev server using the commands from Execution Config:

1. Run the kill command to stop any running processes
2. Run the dev server command

Check for console errors, hydration mismatches, and runtime exceptions. This is the user's signal that the code is ready for manual testing.

**After Phase 3 completes, tell the user:**

> "All local verification passed. The dev server is running — test the features manually. When you're satisfied, run `/ship-test-ensure` to commit, deploy, and verify in production."

---

## Phase 5: Learning & Self-Improvement

Follow the **Self-Improvement Protocol** from CLAUDE.md, plus:

### Step 5.1: Persist New Knowledge

For every issue encountered during the session — especially things that:

- Required multiple attempts to fix
- Revealed a pattern that wasn't in the project's knowledge files
- Were caused by test flakiness or environment issues

**Add them to the project's knowledge files** (as referenced in project CLAUDE.md) immediately with:

- What was tried and failed
- What the actual solution was
- A rule to follow next time

### Step 5.2: Session Report

```
## Build Complete

### Work Summary
- Task files processed: N
- Total items completed: M
- Items failed/skipped: X
- Parallel batches executed: B (N tasks parallelized)

### Parallelism Report
- Tasks run in parallel: N (across B batches via worktrees)
- Tasks run sequentially: M
- Merge conflicts encountered: X (resolved: Y)

### Model Usage
- haiku: N tasks (discovery, simple fixes, analysis)
- sonnet: M tasks (standard implementation, verification)
- opus: X tasks (complex refactoring, conflict resolution)

### Files Modified
- `path/to/file.ts` (+N/-M lines)

### Verification Results
- Local Build: PASS/FAIL
- Local Tests: PASS/FAIL (N passing, M failing)
- Local Lint: PASS/FAIL
- Local Types: PASS/FAIL
- Local E2E: PASS/FAIL

### New Knowledge Persisted
- [List of new entries added to project knowledge files]

### Task Files
- `path/to/task1.md` — COMPLETED (batch 1, parallel, sonnet)
- `path/to/task2.md` — COMPLETED (batch 1, parallel, haiku)

### Next Step
Run `/ship-test-ensure` when ready to deploy.
```

---

## Compact Recovery Protocol

If `/compact` is called at any point:

1. **Immediately re-read** the session learnings file — queue, batches, errors, rules, progress, merge log
2. **Re-read** project knowledge files — accumulated knowledge and troubleshooting patterns
3. Read the task file(s) currently in-progress (from `## Active Task Queue`)
4. Check `## Parallel Batch Plan` and `## Worktree Merge Log` for batch state
5. **Resume from where you left off** — do NOT restart from Phase 1
6. If a parallel batch was interrupted, re-run only incomplete agents
7. If a merge was interrupted, continue from the merge log

---

## Standards (skill-specific, in addition to CLAUDE.md)

- Screenshots saved to `./screenshots/[task-name]/` (if applicable)
- Task file must always reflect actual progress — never stale
- Session learnings file must be updated after EVERY significant event (batch, merge, verification)
- Each batch inherits rules from all previous batches in the session
- **ALWAYS persist new knowledge** to project knowledge files when something fails and gets fixed
- **NO commits, deploys, or staging** — this skill is local-only
- After local verification, tell the user to test manually then run `/ship-test-ensure`
- Add concise comments to non-obvious code (explain WHY, not WHAT)
- Use the project's package manager, build tools, and commands as defined in project CLAUDE.md
- Follow project-specific environment rules from project CLAUDE.md (env file conventions, port usage, etc.)

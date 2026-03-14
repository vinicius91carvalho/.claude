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

## Phase 0: Resume Gate (Always Runs First)

**Prevents re-discovery when a plan already exists.**

### Step 0.0: Ensure Session Learnings File Exists

Before anything else, create the session-learnings file if it doesn't exist.
This prevents learning loss on `/compact` or session end.

```bash
SESSION_FILE="${SESSION_LEARNINGS_PATH}"  # from project CLAUDE.md Execution Config
if [ -z "$SESSION_FILE" ]; then
  SESSION_FILE="docs/session-learnings.md"
fi
mkdir -p "$(dirname "$SESSION_FILE")"
if [ ! -f "$SESSION_FILE" ]; then
  echo "# Session Learnings" > "$SESSION_FILE"
  echo "" >> "$SESSION_FILE"
  echo "Created: $(date -Iseconds)" >> "$SESSION_FILE"
fi
```

### Step 0.1: Check for PRD with progress.json

Search the task file location (from project CLAUDE.md) for `progress.json` files:

1. Find all `progress.json` files in the task directory tree
2. Read each and check for sprints with `"status": "not_started"` or `"status": "in_progress"`
3. Also read the session learnings file for any `## Active Task Queue` (legacy format or simple tasks)

### Step 0.2: Route Decision

| State                                                         | Action                                                                        |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **progress.json exists with not_started/in_progress sprints** | **SKIP to Phase 3** (Execution). The plan exists with extracted sprint specs. |
| **Session learnings has Active Task Queue (simple tasks)**    | **SKIP to Phase 3** via simple task route.                                    |
| **All sprints in progress.json are complete**                 | Go to Phase 6 (Learning) if compound wasn't done.                             |
| **All sprints in progress.json are blocked**                  | Report blocked sprints to user with reasons. Ask: retry, re-plan, or abandon. |
| **No progress.json AND no Active Task Queue**                 | Go to Phase 1 (Discovery) — fresh start.                                      |
| **User described a NEW task**                                 | Go to Phase 1 to scan + create new task.                                      |

**The key rule: If progress.json has pending sprints, EXECUTE THEM. Don't re-plan.**

---

## Phase 1: Discovery (Pending Task Scanner)

**Only runs when Phase 0 routes here (no existing plan).**

### Step 1.1: Spawn Discovery Agent

Spawn a single **Explore agent** (`subagent_type: "Explore"`, `model: "haiku"`) with this prompt:

> Search all markdown files in the task file directory (from project CLAUDE.md) for unchecked items (`- [ ]`). Also search for `progress.json` files with incomplete sprints. For each file that contains pending items:
>
> 1. Return the full file path
> 2. Count the number of `- [ ]` (pending) and `- [x]` (completed) items
> 3. List each pending item's text
> 4. List ALL files referenced or likely modified by each pending item
> 5. If a `progress.json` exists in the same directory, note it
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
>     }
>   ],
>   "dependency_graph": { "task3.md": ["task1.md"] }
> }
> ```
>
> When in doubt, mark tasks as DEPENDENT.

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
4. **Begin the Phase 3 batch loop immediately** — each batch gets its own fresh orchestrator agent.
5. Report results to the user after each batch completes.

**Override:** If the user explicitly asks for step-by-step execution or specific task
selection, use `AskUserQuestion` with these options:

- **Start fresh context** — Save the complete plan to the session learnings file (Active Task Queue, Parallel Batch Plan, execution mode set to "Autonomous"), then tell the user: "Plan saved. Start a new conversation and run `/plan-build-test` — it will pick up exactly where we left off and execute autonomously. Current context usage: ~X%." This preserves maximum context for execution.
- **Auto-start fresh context** — Same as above, but after saving the plan, immediately begin Phase 3 batch loop. Each batch gets its own fresh orchestrator agent, providing fresh context per batch without needing a new CLI session.
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

- **PRD+Sprint task** — Has a `progress.json` with sprint entries → delegate to **orchestrator agent** (one per batch)
- **Simple task** — Standard checklist without sprint structure → execute with **general-purpose agent**

### Step 3.1: For PRD+Sprint Tasks — One Orchestrator Per Batch

**CRITICAL: Spawn one orchestrator agent per batch. Each gets fresh context.**

Read `progress.json` to determine batch order. Loop:

```
for each batch (ordered by batch number):
  1. Read progress.json for current state
  2. Read session learnings for accumulated rules
  3. Read previous batch's Agent Notes from sprint spec files
  4. Spawn orchestrator agent for THIS batch only:

     Agent(description: "Batch N: Sprint(s) [X,Y]",
           prompt: "Execute batch N.

           PRD directory: [path]
           progress.json path: [path]
           Batch assignment: Sprints [list]
           Previous Agent Notes: [from prior sprint spec files]
           Execution Config: [commands from project CLAUDE.md]
           Session learnings rules: [relevant rules]
           Context files: [key reference files]",
           subagent_type: "orchestrator",
           model: "sonnet")

  5. Receive results from orchestrator
  6. Re-read progress.json (orchestrator updated it)
  7. Update session learnings (status, errors, new rules)
  8. If batch had blocked sprints: decide whether to continue or stop
```

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
this step and proceed to Phase 5. Code review (Step 4.1) already covers quality; simplification
is an optimization, not a gate.

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

### Step 5.2: Dev Server Startup (MANDATORY)

**The dev server MUST start and respond to HTTP requests. This is not optional.**

```
1. Run kill command to free ports
2. Start dev server (dev command from Execution Config) in background
3. Wait up to 30 seconds for server to be ready
4. Verify server responds: curl the root URL, expect HTTP 200 or 3xx
```

**If dev server fails to start:**

1. Read the error output carefully
2. Diagnose the root cause (port conflict, missing dependency, system call error,
   config issue, symlink problem, etc.)
3. FIX the root cause — do not skip this step:
   - Port conflict → kill the process and retry
   - System call error → patch the problematic code (e.g., wrap in try/catch)
   - Config error → fix the config
   - Missing dependency → install it
   - Symlink issue → try without Turbopack, or fix the symlink
4. Retry starting the dev server
5. Max 3 fix-and-retry cycles. Each cycle must try a DIFFERENT fix.
6. If still failing after 3 distinct fixes: mark as BLOCKED, report to user with
   full error output and what was tried. Do NOT proceed to Step 5.3.

**CRITICAL: Do NOT accept "environment limitation" as an excuse to skip this step.
If the standard dev command fails, try alternatives:**

- Remove `--turbopack` flag (Turbopack has known issues in some environments)
- Patch system call failures (e.g., `os.networkInterfaces()` → wrap in try/catch)
- Use a static file server on the build output as a fallback
- Try a different port

**The dev server must be running before proceeding to Step 5.3.**

### Step 5.2.5: Runtime Content Verification (Don't Trust Test Counts)

**Tests passing does NOT mean the app works. This step catches the gap.**

Even if all tests pass with perfect scores, the running app can be broken due to:
cached state, missing runtime dependencies, environment differences, or test coverage gaps.

1. With the dev server running, use Playwright MCP `browser_snapshot` (NOT screenshots —
   Chromium doesn't run in proot) or `curl` to inspect actual rendered content:

2. For each key route modified by this task:
   a. Fetch the page content (curl with `-L` to follow redirects)
   b. Verify the response body contains:
      - Expected text content (headings, labels, data)
      - Expected HTML structure (key components, navigation elements)
      - NO error messages ("Internal Server Error", "Error", stack traces, "undefined")
      - NO empty body or loading-spinner-only state
   c. If using Playwright MCP: `browser_navigate` to the route, then `browser_snapshot`
      to capture the accessibility tree. Verify components render correctly.

3. Compare what you see against the acceptance criteria:
   - For each criterion, can you point to specific rendered content that proves it?
   - If a criterion says "user can see X" — verify X actually appears in the snapshot

4. If content verification reveals issues that tests missed:
   - Fix the issue FIRST
   - Then write a test that would have caught it
   - Re-run all tests to confirm
   - Log in session learnings: "Tests missed [X] — added test for it"

5. **This step is BLOCKING. Do NOT proceed to Step 5.3 if content verification fails.**

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

2. Curl each route (follow redirects with `-L`):
   ```bash
   for route in [ALL_ROUTES]; do
     code=$(curl -sL -o /dev/null -w "%{http_code}" "http://localhost:PORT${route}")
     echo "$route → $code"
   done
   ```

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
   # proot-distro guard: Chromium cannot run in proot ARM64
   if uname -r 2>/dev/null | grep -q PRoot-Distro; then
     echo "BLOCKED: proot-distro ARM64 — Chromium unavailable. Using browser_snapshot MCP instead."
     # Skip playwright install, use browser_snapshot for accessibility tree testing
   else
     pnpm exec playwright install chromium
   fi
   ```
   **In proot:** Skip Playwright screenshot tests entirely. Use `browser_snapshot` MCP
   (accessibility tree) for content verification instead. Mark Playwright E2E as
   `BLOCKED: proot-distro ARM64` in the Phase 5 results table.

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
5. **Adaptive retry budget** by failure category:
   - `transient` (network, timeout, flaky test) → up to 5 retries
   - `logic` (wrong approach, broken implementation) → max 2, then try a different approach
   - `environment` (proot limitation, missing binary) → 1 retry, then mark BLOCKED
   - `config` (bad setting, wrong flag) → max 3 retries
6. After retry budget exhausted: report BLOCKED with full details and category.

### Step 5.8: Kill Dev Server

After all verification passes, kill the dev server:
```bash
[kill command from Execution Config]
```

### Step 5.9: Final Gate — Verification Summary

Present this summary. ALL items must show PASS:

```
## Phase 5: Live Verification Results

| Check                    | Result      | Details                        |
|--------------------------|-------------|--------------------------------|
| Build                    | PASS/FAIL   | exit code, error count         |
| Lint                     | PASS/FAIL   | file count, issue count        |
| Types                    | PASS/FAIL   | exit code, error count         |
| Tests                    | PASS/FAIL   | pass/fail count                |
| Dev Server               | PASS/FAIL   | port, startup time             |
| Content Verification     | PASS/FAIL   | routes checked, content found  |
| Route Health (N routes)  | PASS/FAIL   | routes passing / total         |
| Playwright E2E           | PASS/FAIL   | tests pass/fail, screenshots   |
| Console Errors           | PASS/FAIL   | error count (must be 0)        |
| Plan Completeness        | PASS/FAIL   | tasks done/total, criteria met |
| Regression Scan          | PASS/FAIL   | issues found                   |
```

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

Follow the **Self-Improvement Protocol** from CLAUDE.md AND the `/compound` skill's Steps 7-8 (cross-project promotion).

### Step 6.1: Persist New Knowledge

For issues that required multiple attempts, revealed unknown patterns, or were caused by environment issues — add to project knowledge files.

### Step 6.2: Cross-Project Evolution (from /compound Steps 7-8)

1. **Update error registry:** Add any new errors to `~/.claude/evolution/error-registry.json`
2. **Update model performance:** Record model outcomes in `~/.claude/evolution/model-performance.json`
3. **Check adaptation thresholds:** If model performance data suggests upgrade/downgrade, report to user
4. **Log system changes:** If any skill/agent/hook was modified, log in `~/.claude/evolution/workflow-changelog.md`
5. **Write session postmortem:** Create `~/.claude/evolution/session-postmortems/YYYY-MM-DD_project-name.md`

### Step 6.3: Session Report

```
## Build Complete

### Work Summary
- Task files processed: N
- Total items completed: M
- Items failed/skipped: X
- Parallel batches executed: B

### Parallelism Report
- Tasks run in parallel: N (across B batches via worktrees)
- Tasks run sequentially: M
- Merge conflicts encountered: X (resolved: Y)

### Model Usage
- haiku: N tasks (first-try success: X/N)
- sonnet: M tasks (first-try success: X/M)
- opus: X tasks (first-try success: X/X)

### Error Categories
- [CATEGORY]: N occurrences → [brief summary]

### Metrics
- Total retries: N
- Verification gates that caught bugs: [list]
- Phase 5 duration: Ns
- Retry budget by category: transient=N, logic=N, environment=N, config=N

### Files Modified
- `path/to/file.ts` (+N/-M lines)

### Verification Results (Phase 5 — Live Verification)
- Build: PASS/FAIL (exit code)
- Lint: PASS/FAIL (file count, issue count)
- Types: PASS/FAIL (exit code)
- Tests: PASS/FAIL (N passing, M failing)
- Dev Server: PASS/FAIL (port, startup method)
- Content Verification: PASS/FAIL (routes checked, content found)
- Route Health: PASS/FAIL (N/M routes returning 200)
- Playwright E2E: PASS/FAIL (N tests, M screenshots, X console errors)
- Regression Scan: PASS/FAIL

### Evolution Updates
- Error registry entries added/updated: N
- Model performance data points recorded: N
- Session postmortem written: yes/no

### Task Files
- `path/to/task/spec.md` — COMPLETED (via progress.json)

### Next Step
Run `/ship-test-ensure` when ready to deploy.
```

---

## Standards (skill-specific, in addition to CLAUDE.md)

- Task file must always reflect actual progress — never stale
- progress.json must be updated after EVERY sprint completion (orchestrator handles this)
- Session learnings file must be updated after EVERY batch
- Each batch inherits rules from all previous batches
- **ALWAYS persist new knowledge** to project knowledge files when something fails and gets fixed
- **NO commits, deploys, or staging** — this skill is local-only
- After local verification, tell user to test manually then run `/ship-test-ensure`
- Use the project's package manager, build tools, and commands from project CLAUDE.md
- Follow project-specific environment rules from project CLAUDE.md

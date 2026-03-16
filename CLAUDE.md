# Personal AI Engineering System

Each unit of work must make subsequent units easier — not harder. This system implements Compound Engineering: a four-step loop (Plan, Work, Review, Compound) where the fourth step produces a system that builds features better each time. Skip it, and you have traditional engineering with AI assistance. Plan + Review = 80% of effort. Work + Compound = 20%.

---

## INTENT & DECISION BOUNDARIES

### Value Hierarchy (when values conflict, higher rank wins)

1. **Security & Privacy** — Auth integrity, data masking, secrets management are non-negotiable
2. **Functional Correctness** — Code that works correctly > code that looks elegant
3. **Robustness** — For core components: defensive coding, error handling, validation
4. **Iteration Speed** — For UI, prototypes, non-core features: ship fast, iterate later
5. **Performance** — Optimize only when measured data shows a bottleneck

### Autonomous Decision Authority

| Agent CAN decide alone               | Agent MUST ask user                            | Agent NEVER does                             |
| ------------------------------------ | ---------------------------------------------- | -------------------------------------------- |
| Variable/function naming             | Schema/API changes                             | Expose sensitive data in logs                |
| Choice between equivalent approaches | New dependency outside existing stack          | Delete passing tests                         |
| Implementation order within a phase  | Architectural pattern change                   | Deploy to production                         |
| CSS/styling decisions                | Remove existing functionality                  | Modify auth/permission config without review |
| Test structure and naming            | Tradeoffs affecting security/privacy           | Bypass rate limiting or validation           |
| Refactoring within a single file     | Scope significantly larger than expected (>2x) | Silently swallow errors                      |

### Tradeoff Resolution by Deliverable

| Deliverable   | Optimize for                      | Acceptable to sacrifice |
| ------------- | --------------------------------- | ----------------------- |
| API endpoint  | Security, validation, idempotency | Development speed       |
| UI component  | UX, responsiveness, accessibility | Marginal performance    |
| Data pipeline | Correctness, observability        | Code elegance           |
| Documentation | Clarity, accuracy                 | Completeness            |
| Prototype/POC | Speed, core functionality         | Tests, edge cases       |

### Escalation Logic

The agent MUST stop and ask when:

1. The task is ambiguous and there are 2+ reasonable interpretations
2. The proposed solution conflicts with a documented ADR or existing pattern
3. Actual scope is significantly larger than expected (>2x estimated files/effort)
4. An unrelated bug or problem is discovered during implementation
5. The decision falls in the "MUST ask user" column above
6. No relevant documentation exists for the area being modified
7. A dependency or external service behaves unexpectedly

Question format: `[DECISION NEEDED] Context: [brief]. Option A: [X]. Option B: [Y]. My recommendation: [A/B], because [reason]. Proceed?`

---

## WORKFLOW

### Mode Fluency Principle

Switch modes 2-3 times within a single task. Typical pattern: start in PRD+Sprint mode (plan), drop to Standard for straightforward sprints, drop to Quick Fix for trivial adjustments, return to Standard for the next piece. Before each sub-task, ask: "Quick Fix, Standard, or PRD+Sprint?" Switch freely.

### Execution Modes

#### Quick Fix

**When:** Single-file, < 30 lines, no architectural impact, clear fix.
**Process:** Fix directly, run tests, run micro-compound (1 question: "Would the system catch this next time?"). No PRD.
**Spec:** Intent Doc (4 lines): Task, Scope, Boundaries, If Uncertain.

#### Standard

**When:** Multi-file, clear scope, moderate complexity.
**Process:** Contract-First, Correctness Discovery, Minimal PRD, implement, verify, compound.

#### PRD + Sprint

**When:** Large feature, multi-component, or >1h of agent work.
**Process:** Contract-First, Correctness Discovery, Full PRD, Sprint decomposition, compound.

In autonomous mode: execute sprints sequentially, still ask on escalation criteria, pause between sprints to update PRD and evaluate context health.

### Autonomous Pipeline

The preferred end-to-end workflow is a hybrid autonomous pipeline that minimizes human
touchpoints while keeping the single highest-value safety gate (production deploy confirmation).

**The flow:**

```
/plan → User reviews PRDs → Approves → /plan-build-test (autonomous) → User tests manually → /ship-test-ensure (autonomous through staging, confirms before prod)
```

**Design goal:** The user reviews the plan once, approves once, tests manually once, and
confirms production deploy once. Everything else runs without interruption. This is a
permanent architectural decision — not a temporary workaround.

**How each skill behaves in autonomous mode:**

| Checkpoint | Default autonomous action | Rationale |
|---|---|---|
| `/plan-build-test` execution plan | Auto-select "Run all autonomously" | PRD was already reviewed |
| `/plan-build-test` verification failures | Exhaust retry budget, then report BLOCKED | User checks at end |
| `/ship-test-ensure` fresh context check | Auto-select "Continue here" | Advisory only |
| `/ship-test-ensure` deploy timeout (15min) | Wait 10 more minutes, then report BLOCKED | Safe default |
| `/ship-test-ensure` **production deploy** | **ALWAYS ask user** | Non-negotiable safety gate |
| `/ship-test-ensure` Lighthouse plateau | Accept current scores after max iterations | Performance, not correctness |
| `/ship-test-ensure` rollback decision | **ALWAYS ask user** | Destructive action needs human judgment |

**Activation:** Autonomous mode is the default behavior for `/plan-build-test` and
`/ship-test-ensure`. Skills detect it from the user's intent ("run it", "build this",
"ship it") or from `## Execution Mode: Autonomous` in the session learnings file.
No explicit flag is needed — autonomous is the norm, not the exception.

**Safety invariants that autonomous mode does NOT change:**
- Escalation Logic rules still apply (ambiguity, scope > 2x, etc.)
- "Agent NEVER does" column still enforced by hooks
- Production deploy requires user confirmation
- Rollback decisions require user confirmation
- Anti-Premature Completion Protocol still enforced
- Verification Integrity rules still enforced

### Contract-First Pattern (mandatory for Standard and PRD+Sprint)

Before executing any multi-step task, establish mutual agreement:

1. **Intent:** User describes what they want
2. **Mirror:** Agent mirrors understanding back, including ambiguities and planned tradeoffs
3. **Receipt:** User confirms, corrects, or refines

Only after Step 3 does execution begin. Quick Fix skips this.

### PRD-Driven Task System

**Location:** `docs/tasks/<area>/<category>/YYYY-MM-DD_HHmm-descriptive-name.md`
**Categories:** `feature`, `bugfix`, `refactor`, `infrastructure`, `security`, `documentation`

#### Correctness Discovery (scaled by mode)

**Standard mode (2 questions):**

1. **Audience:** Who uses this output and what decision will they make?
2. **Verification:** How would you check if the output is correct?

**PRD+Sprint mode (full 6 questions):**

1. **Audience:** Who uses this output and what decision will they make?
2. **Failure Definition:** What would make this output useless?
3. **Danger Definition:** What would make this output actively harmful?
4. **Uncertainty Policy:** Guess / Flag / Stop when uncertain?
5. **Risk Tolerance:** Confident wrong answer or refusal — which is worse?
6. **Verification:** How would you check if the output is correct?

Full framework with examples: `~/.claude/skills/plan/correctness-discovery.md`. PRD templates: `~/.claude/skills/plan/`.

### Sprint System

Large PRDs decompose into Sprints — self-contained units for one agent in a healthy context window.

**Rules:**

1. Each Sprint MUST be independently verifiable (own acceptance criteria and tests)
2. Each Sprint SHOULD produce a working state (builds and passes tests)
3. Ordered by dependency (N+1 may depend on N, never reverse)
4. Target size: 30-90 minutes of agent work. Larger: decompose further
5. Maximum 5 sprints per PRD. If >5 sprints needed, split by **independent deliverable** — the test: "could these be built by two teams who never talk?" If yes, split. If they share files, keep together.
6. Each sprint is **extracted into its own spec file** during planning (not inline in the PRD)
7. Sprint agents load ONLY their sprint spec file — never the full PRD

**Sprint File Structure:** `spec.md` + `progress.json` + `INVARIANTS.md` + `sprints/NN-title.md` per sprint. Each sprint spec declares **file boundaries** (`files_to_create`, `files_to_modify`, `files_read_only`, `shared_contracts`) to prevent parallel agents from conflicting. If two sprints need the same file, they MUST be sequential. Full structure and JSON schema in `~/.claude/skills/plan/SKILL.md`.

### Build Candidate

A **Build Candidate** is a tagged commit that declares "this specification is complete enough to build from" — analogous to a release candidate, but for the design phase. It is the formal gate between planning and execution.

**When to tag:** After the PRD, sprint specs, progress.json, and INVARIANTS.md are all written and reviewed. The `/plan` skill tags the Build Candidate; `/plan-build-test` verifies it exists before execution.

**What it includes:** PRD spec.md, all sprint specs, progress.json, INVARIANTS.md, and any shared contract definitions. Tag format: `build-candidate/<prd-name>`.

**Why it matters:** Without a formal design-done gate, agents start building from incomplete specs. Every ambiguity resolved before implementation is a wrong guess prevented during implementation.

### Architecture Invariant Registry (INVARIANTS.md)

**The Modular Success Trap:** Individual modules pass all tests in isolation, but integration seams break because agents independently invent incompatible vocabularies for shared concepts. AI amplifies this — velocity outpaces integration, agents excel at local correctness, and agents don't share working memory.

**Solution:** `INVARIANTS.md` at the project root (and optionally at component level) defines every cross-cutting concept with machine-verifiable contracts. Enforced by `check-invariants.sh` PostToolUse hook — violations are caught immediately after any edit.

**Format:**

```markdown
## [Concept Name]
- **Owner:** [bounded context that defines this concept]
- **Preconditions:** [what consumers must satisfy before using this]
- **Postconditions:** [what the owner guarantees after execution]
- **Invariants:** [what must always hold across all contexts]
- **Verify:** `shell command that exits 0 if invariant holds`
- **Fix:** [how to fix if violated]
```

**Dependency direction:** If A depends on B, B owns the contract. Consumers declare which contracts they consume and must satisfy preconditions. This prevents the failure where consumers independently invent expectations about a provider's behavior.

**Cascading invariants:** Project-level INVARIANTS.md applies everywhere. Component-level INVARIANTS.md adds constraints for specific directories. The hook walks up from the edited file to the project root, checking all levels.

**When to create:** During the `/plan` phase (PRD+Sprint mode), after sprint decomposition. The INVARIANTS.md is part of the Build Candidate. Each entry specifies owner, preconditions, postconditions, invariants, and a verify command.

**Orchestrator design:** Deterministic checklist — read progress.json → find next batch → spawn sprint-executors with ONLY their sprint spec → collect results → code review → merge → dev server verification → update progress.json → return. Minimal LLM judgment, maximum structure. Full protocol in `~/.claude/agents/orchestrator.md`.

### The Full Pipeline

Four skills form the end-to-end workflow:

```
[/plan] — PRD generation only. Use when you ONLY want to plan without executing.
[/plan-build-test] — Smart entry point: discovers pending tasks, plans if needed, executes, verifies locally. Runs autonomously by default.
[/ship-test-ensure] — CI/CD pipeline: commit, branch, PR, merge, staging E2E, production deploy, Lighthouse. Autonomous through staging; confirms before prod.
[/compound] — Post-task learning capture + cross-project evolution. Auto-runs after completion.
[/workflow-audit] — Periodic self-audit: reviews model performance, error patterns, rule staleness. Monthly or after 10+ sessions.
```

`/plan-build-test` can plan on its own — `/plan` is optional for when you want a PRD without execution.

**Autonomous Pipeline (preferred flow):** `/plan` → user reviews PRD → approves → `/plan-build-test` runs autonomously → user tests manually → `/ship-test-ensure` runs autonomously through staging, confirms before production deploy. See "Autonomous Pipeline" section above for full details.

### Skill Selection Decision Tree

```
"What do I need to do?"
│
├─ "Just plan, don't build yet"
│   └─ /plan
│
├─ "Build a feature / fix a bug / implement something"
│   ├─ Single file, < 30 lines, obvious fix?
│   │   └─ Quick Fix (no skill needed — just do it)
│   └─ Anything larger
│       └─ /plan-build-test (autonomous — plans if needed, then executes without interruption)
│
├─ "Ship what I've built to production"
│   └─ /ship-test-ensure (autonomous through staging → confirms before prod deploy)
│
├─ "Full autonomous pipeline (plan → build → test → ship)"
│   └─ /plan → review PRD → /plan-build-test → manual test → /ship-test-ensure
│
├─ "Wrap up / capture what I learned"
│   └─ /compound (auto-invoked after task completion, not after "ship it")
│
├─ "I have pending task files from a previous session"
│   └─ /plan-build-test (Phase 0 detects and resumes pending work)
│
└─ "Audit how the workflow itself is performing"
    └─ /workflow-audit (model adaptation, error trends, rule staleness)
```

**Project-specific commands** (build, test, lint, deploy, URLs, pages to audit) live in each project's CLAUDE.md under `## Execution Config`. Skills read from there — never hardcode project details.

**Fresh context principle:** Each major skill works best in a fresh context window. The plan saves state to session-learnings; the next skill reads it. This prevents context pollution across phases.

### Knowledge Promotion Chain

**Per-project:** session-learnings → `docs/solutions/` → ADRs → CLAUDE.md updates. Promote when a pattern proves useful across 2+ tasks.

**Cross-project:** session-learnings → `~/.claude/evolution/error-registry.json` → `~/.claude/evolution/model-performance.json` → `~/.claude/projects/-root/memory/` → CLAUDE.md / skills / agents / hooks.

Evolution data lives in `~/.claude/evolution/` (error-registry, model-performance, workflow-changelog, session-postmortems). `/compound` handles promotion after every task. `/workflow-audit` reviews effectiveness monthly. **Compound is BLOCKING** — the stop hook prevents session end without capturing learnings.

---

## CONTEXT ENGINEERING

### Agent Architecture (Native Subagents)

Agents live in `~/.claude/agents/`. Each has its own context window, tool permissions, model, and system prompt.

- **orchestrator** — Task management, sprint lifecycle, agent delegation. Full tool access. Uses sonnet (deterministic checklist doesn't need opus; opus reserved for merge conflicts >3 files).
- **sprint-executor** — Single sprint execution. Isolated worktree. Uses sonnet. Tools: Read, Write, Edit, Bash, Glob, Grep.
- **code-reviewer** — Read-only post-sprint review. Uses sonnet. Tools: Read, Grep, Glob.

### Worktree Isolation for Parallel Work

Sprint agents use `isolation: worktree` in frontmatter. Each gets its own git worktree and branch. Worktrees auto-clean when agent finishes without changes. Independent sprints can run in parallel; the orchestrator handles merging.

### Context Budget Rules

The main agent is an **orchestrator**, not a worker. Its context contains: system instructions + session learnings + subagent summaries + user messages. If reading file contents or build output directly, delegate to a subagent instead.

**Exceptions:** Playwright MCP interaction (`browser_snapshot`, `browser_navigate`, etc.) stays in main agent — never delegate browser interaction to subagents. In proot-distro: use `browser_snapshot` only (accessibility tree), never `browser_take_screenshot` (Chromium unavailable). Simple file edits (checkboxes, session-learnings) are done directly. Bug investigation may read up to 5 targeted files; more than that, delegate.

### Subagent Communication Protocol

- Every subagent prompt ends with: "Return a structured summary: [specify exact fields needed]"
- Never ask a subagent to "return everything" — specify exact data points
- Target 10-20 lines of actionable info per subagent result
- Chain subagents: extract only relevant fields from agent A to pass to agent B — never forward raw output

### Context Rot Protocol

**Signs:** Responses become generic, rules forgotten, questions re-asked, fixed errors reappear, tasks not checked off.

**Action:** Save state (update checkboxes, fill Agent Notes), write pending insights to session-learnings, report: "Context degrading. Recommend new session."

**Prevention:** Orchestrator keeps context lean. Sprint agents receive ONLY their sprint spec. Never forward raw output between sprints. Order context by stability: system instructions, docs, session state, current task.

---

## JUDGMENT PROTOCOLS

### Confidence Levels & Actions

| Level     | Meaning                                                 | Action                          |
| --------- | ------------------------------------------------------- | ------------------------------- |
| 🟢 HIGH   | Clear pattern in docs/solutions, existing tests confirm | Proceed autonomously            |
| 🟡 MEDIUM | Inferred from code but no explicit docs                 | Proceed but document assumption |
| 🔴 LOW    | Multiple valid interpretations, no precedent            | STOP and ask user               |

### Risk Categories

| Area           | Catastrophic (rollback immediately)          | Tolerable (fix forward)              |
| -------------- | -------------------------------------------- | ------------------------------------ |
| Auth/Security  | Any bypass, data leak, permission escalation | Error message copy, UI polish        |
| Data/API       | Data loss, schema break, contract violation  | Response format, non-critical field  |
| UI             | Crash, blank page, broken critical flow      | Pixel imperfection, animation glitch |
| Tests          | Deleting passing tests, making tests lie     | Flaky new test, missing edge case    |
| Infrastructure | Broken deploy, env leak, service outage      | Config optimization, log level       |

### Anti-Goodhart Verification

Before marking any task or sprint complete:

1. Do tests validate actual BEHAVIOR or just OUTPUT?
2. Did I add a test just to "make it pass" without verifying the real scenario?
3. Does E2E test the USER flow or just the DEVELOPER flow?
4. Are there scenarios the tests don't cover that acceptance criteria imply?
5. Could functional tests pass while security-relevant behaviors are missing?

Enforced via Verification Integrity rules (see Development Rules) and mandatory Phase 5 in plan-build-test.

### Scope Boundary Enforcement

If during implementation you discover:

- Related bug in different area — log in PRD under "Issues Found", do NOT fix
- Opportunity to improve unrelated code — log it, do NOT do it
- Already-broken test — log it, do NOT fix (unless in sprint scope)

Stay in scope. Resist "one more thing."

### Deterministic Safety via Hooks

The "Agent NEVER does" column is enforced as PreToolUse hooks in `~/.claude/settings.json`, not just prompt suggestions. What hooks actually enforce:

- **PreToolUse(Bash):** Blocks destructive commands and detects proot environment
- **PreToolUse(Write|Edit):** TDD enforcement — blocks production code edits if no corresponding test file exists (`check-test-exists.sh`). Write the test first.
- **PostToolUse(Write|Edit):** Auto-formats TS/JS files if Biome or ESLint is configured (skips silently if no linter found; exit 2 on unfixable lint errors). Then verifies INVARIANTS.md rules — blocks if any machine-verifiable invariant is violated (`check-invariants.sh`).
- **Stop:** Type-checks TypeScript (exit 2 on type errors), reminds to run /compound when PRD tasks complete (exit 2 if compound not run), and enforces Anti-Premature Completion Protocol — blocks if task marked complete without verification evidence (`verify-completion.sh`)
- **Notification:** Desktop alert when agent needs attention (no-op in proot)

Anti-Goodhart verification is enforced by sprint-executor Step 8, orchestrator Step 8.5, and plan-build-test Phase 5.5 — not by hooks.

- **Hard block** (always denied): `rm -rf /`, `rm -rf` on system directories (`/etc`, `/usr`, `/var`, `/home`, etc.), `dd`, fork bombs
- **Soft block** (warns and asks user for confirmation):
  - Destructive git: `git push --force`, `git push -f`, `git push --force-with-lease`, `git push ... main/master`, `git reset --hard`, `git checkout .`, `git restore .`, `git branch -D`, `git clean -f`, `git stash drop/clear`
  - Forbidden package managers: `npm install/run/exec/start/test/build/ci/init`, `npx` — project uses pnpm exclusively

Soft blocks exit 2 with a descriptive message — the user can re-approve if the operation is genuinely required.

---

## EVALUATION

### The Verification Pattern

LLMs are non-deterministic. The most reliable pattern combines:

1. **Prose specification** — intent, context, constraints (the PRD)
2. **Executable tests** — machine-verifiable correctness contract
3. **Iteration loops** — catch non-deterministic failures (run, fail, fix, run)

**Adaptive retry budget** (replaces fixed 3-retry):
- `transient` failures (network, timeout, flaky test) → up to 5 retries
- `logic` failures (wrong approach, broken implementation) → max 2, then try different approach
- `environment` failures (proot limitation, missing binary) → 1 retry, then mark BLOCKED
- `config` failures (bad setting, wrong flag) → max 3 retries

What tests cannot catch: security heuristics, architectural implications, complex layer interactions — human review is the judgment layer.

Full evaluation checklists (Stack Evaluation, Diagnostic Loop, Spec Self-Evaluator) live in `~/.claude/docs/evaluation-reference.md`. Load when needed for PRD review or post-sprint verification.

---

## HARNESS & TOOLING

### Model Assignment Matrix (adaptive — evolves via `~/.claude/evolution/model-performance.json`)

| Task Type                                     | Model    |
| --------------------------------------------- | -------- |
| File scanning, discovery, dependency analysis | `haiku`  |
| Simple fixes (lint, format, typos, CSS)       | `haiku`  |
| Session learnings compilation                 | `haiku`  |
| Standard implementation                       | `sonnet` |
| Bug fix implementation                        | `sonnet` |
| Test writing                                  | `sonnet` |
| Verification & regression scan                | `sonnet` |
| Sprint orchestration (deterministic checklist) | `sonnet` |
| Complex/multi-file refactoring                | `opus`   |
| Architectural decisions                       | `opus`   |
| Merge conflict resolution (>3 files)          | `opus`   |

**Adaptation rules:** After 10+ data points per task type, compound checks `model-performance.json`:
- If first-try success rate < 70% → propose upgrade to next model tier
- If first-try success rate > 90% → propose downgrade to save cost
- Changes require user approval; logged in `~/.claude/evolution/workflow-changelog.md`

### Parallel Execution with Worktrees

**Batch Planning:**

1. Analyze tasks for file overlap and dependencies
2. DEPENDENT if: same files, same component tree, shared config, output feeds another
3. INDEPENDENT if: different files/dirs, unrelated features, no shared deps
4. When in doubt, run sequentially — safe > fast

**Execution:** Spawn all batch agents in a single message. Each uses `isolation: worktree`. Worktree agents must NOT modify coordination files or install dependencies.

**Merge Protocol:** Merge each branch sequentially. Conflicts: spawn opus agent. After merges: run build. Build fails: spawn sonnet agent to fix.

### Hooks as Enforcement Layer

`~/.claude/settings.json` contains hooks that guarantee behavior CLAUDE.md can only suggest:

- **PreToolUse(Bash):** Block destructive commands (rm -rf, force push, deploy)
- **PreToolUse(Write|Edit):** TDD hard gate — block production code edits without corresponding test file (`check-test-exists.sh`)
- **PostToolUse(Write|Edit):** Auto-format after file changes (TS/JS files only, skips generated dirs). Verify INVARIANTS.md rules — block if any invariant violated (`check-invariants.sh`)
- **Stop:** Type-check at end of turn (skips if no code was written), compound reminder (warns if task complete but /compound not run), anti-premature completion gate (blocks if task marked complete without verification evidence — `verify-completion.sh`)
- **Notification:** Desktop alert when agent needs attention

### Code Intelligence

Prefer LSP over Grep/Glob/Read for code navigation:

| You say...                       | Claude uses...       |
| -------------------------------- | -------------------- |
| "Where is X defined?"            | `goToDefinition`     |
| "Find all usages of X"           | `findReferences`     |
| "What type is X?"                | `hover`              |
| "What functions are in file.ts?" | `documentSymbol`     |
| "Find the X class"               | `workspaceSymbol`    |
| "What implements X?"             | `goToImplementation` |
| "What calls X?"                  | `incomingCalls`      |
| "What does X call?"              | `outgoingCalls`      |

Before renaming or changing a function signature, use `findReferences` to find all call sites first. Use Grep/Glob only for text/pattern searches where LSP does not help. After writing or editing code, check LSP diagnostics and fix any type errors or missing imports immediately.

---

## DEVELOPMENT RULES

### TDD for Features (mandatory order)

1. Write **unit tests first** (Red, Green, Refactor)
2. Implement the code
3. Write **integration tests**
4. Write **E2E tests**
5. Run ALL tests after each feature — fix failures immediately

### TDD for Bug Fixes (different order)

1. **Reproduce:** Write a failing test that proves the bug exists
2. **Investigate:** Find and state the root cause (not the symptom)
3. **Fix:** Implement the fix targeting the root cause
4. **Verify:** Confirm the failing test now passes
5. **Regress:** Add regression tests if root cause reveals broader risk
6. Run ALL related tests — fix failures immediately

### Mobile First (mandatory order for UI work)

1. Mobile (< 640px) — implement first
2. Tablet (640px-1024px)
3. Desktop (1024px-1280px)
4. Wide Desktop (> 1280px)

### Rollback & Recovery Protocol

When a fix makes things worse, **stop layering fixes on top of broken fixes**:

1. **Revert** to the last known working state
2. **Reassess** — re-read the original bug/requirement with fresh eyes
3. **Try a different approach** — if the same approach failed twice, it is wrong
4. **Escalate to user** if you have tried 2+ distinct approaches and both failed

### When Tests Fail Unexpectedly

1. Test fails but implementation appears correct — investigate the test first
2. Test is flaky — fix the flake, do not disable the test
3. Test expectations are outdated — update the test, document why
4. Never change test assertions just to make them pass without understanding why they failed
5. Report to the user before changing test expectations on established tests

### Verification Integrity

- NEVER claim a command "passed" without running it and seeing the output
- NEVER write "lint: PASS (0 issues)" without a preceding lint command execution in the transcript
- NEVER mark E2E as "PASS" without a preceding E2E command execution in the transcript
- If a verification step is blocked (environment limitation, missing tool): mark it as `BLOCKED`, never as `PASS`
- Session learnings verification sections must include actual exit codes
- "Trust but verify" does not apply — VERIFY, period

### Anti-Premature Completion Protocol

**This protocol exists because of repeated incidents where tasks were declared "complete"
while the actual running application was broken. It is non-negotiable.**

#### The Three Completion Lies (never do these)

1. **"All tests pass"** — Tests passing does NOT mean the feature works. Tests can pass
   while the first route shows a visible bug, the dev server cache is corrupted, or
   runtime dependencies are missing. Test results are a necessary condition, not sufficient.

2. **"Build complete"** — A build completing does NOT mean the app runs. You MUST start
   the dev server and verify actual routes return correct content — not just HTTP 200,
   but actual rendered content matching acceptance criteria.

3. **"All items done"** — Claiming completion without re-reading the original plan is
   the most common failure. Before declaring done: re-read the plan/spec file, enumerate
   every item, and for each one cite the specific evidence it was completed.

#### Mandatory Completion Checklist (before ANY completion claim)

Before saying "done", "complete", "all tasks finished", or presenting a session report:

1. **Re-read the original plan/spec** — not from memory, actually read the file
2. **Enumerate remaining items** — list every unchecked `- [ ]` item explicitly
3. **Cite evidence for each criterion** — "acceptance criterion X was verified by [command]
   which returned [output]" — not just "tests pass"
4. **Start the dev server** — verify it starts and key routes serve correct content
5. **Test as the user, not the builder** — verify with non-privileged/non-admin accounts.
   Superuser accounts mask integration failures (bypass permission checks, pre-seeded data
   masks config gaps, admin roles paper over capability mismatches). Test as the user who
   will actually use the system.
6. **If ANY item is incomplete** — either complete it or report it as incomplete.
   NEVER claim completion with unfinished items.
7. **Write completion evidence** — after all checks pass, write the evidence marker file
   so the `verify-completion.sh` Stop hook can confirm verification was performed.

**Enforced as a hard gate:** The `verify-completion.sh` Stop hook blocks the agent from
finishing if a task is marked complete without a verification evidence marker. This
promotes the protocol from instructions to enforcement — the agent cannot claim "done"
without actually performing the checks.

#### When to STOP and Report Instead of Claiming Done

- Dev server won't start → BLOCKED, not "complete with known issue"
- Tests pass but you haven't visually verified the feature → NOT DONE
- You checked off tasks but didn't re-read the plan → NOT DONE
- You can't cite specific evidence for an acceptance criterion → NOT MET
- You only tested as admin/superuser → NOT DONE (test as a regular user)

### Post-Implementation Checklist

- All tests passing
- No unused components, imports, or dead code
- No console.logs or debug code
- No duplicated code
- Descriptive variable/function names
- Security check
- Performance check

---

## SESSION LEARNINGS

Maintain a session learnings file as **living memory** that survives `/compact`. Path from project CLAUDE.md `session-learnings-path`; default: `docs/session-learnings.md`. Created proactively by `/plan-build-test` Phase 0.

**Update rules:** Append errors as they occur, patterns when they repeat, rules when mistakes happen, task status as work progresses. Use structured format with categories (ENV, LOGIC, CONFIG, etc.) — full schema in `/compound` skill Step 6.

**Promotion:** 2+ tasks → `docs/solutions/`. 2+ projects → `~/.claude/evolution/error-registry.json` + memory.

---

## COMPACT RECOVERY PROTOCOL

When `/compact` is called or context is refreshed mid-task:

1. Re-read the session learnings file (path from project CLAUDE.md)
2. Re-read project knowledge files (patterns, MEMORY.md)
3. Resume from the last completed phase — do NOT restart
4. If mid-deploy or mid-monitoring, re-check current status before continuing

---

## SELF-IMPROVEMENT PROTOCOL

### Per-Task Compound (every task — enforced by stop hook)

1. **Capture:** What worked? What didn't? What is the reusable insight?
2. **Document:** Create solution doc if reusable. Update session learnings.
3. **Update the system:** If a rule/pattern/doc needs changing, do it now — not "later."
4. **Verify:** "Would the system catch this automatically next time?" If no, compound is incomplete.
5. **Capture user corrections** as error-registry entries and model-performance data (richest signal).

### Per-Session Compound (end of session)

Run `/compound` — it handles: compile, generate rules, promote to solutions, persist to memory, cross-project evolution (error-registry, model-performance, workflow-changelog, session postmortem). Full protocol in `~/.claude/skills/compound/SKILL.md`.

**Periodic:** Run `/workflow-audit` monthly or after 10+ sessions.

### The Three Compound Questions

1. "What was the hardest decision made here?"
2. "What alternatives were rejected, and why?"
3. "What are we least confident about?"

---

Anti-patterns reference: `~/.claude/docs/anti-patterns-full.md`. Key rule: match ceremony to complexity.

---

## GLOBAL RULES

### Git Workflow

- **Branching:** One branch per feature or bug fix. Name: `<type>/<short-description>`
- **Commits:** Atomic. Format: `<type>: <what changed>`
- **Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`
- **Never force-push to main.** Always create PRs for non-trivial changes.
- **All deploys go through CI/CD pipelines.** Never push directly to main. `/ship-test-ensure` creates a branch, opens a PR, merges via CI/CD, then follows the deploy pipeline. Rollback is also via PR (revert commit → PR → merge).
- **Before committing:** Run linter to catch lint/format issues.

### Security Checklist

- Input sanitization on all forms (XSS prevention)
- CSP headers configured
- No sensitive data exposed client-side
- HTTPS enforced
- Dependency audit clean
- Rate limiting on form endpoints
- CORS configured correctly
- No tokens or API keys in frontend code

### Performance Targets

- LCP < 2s, CLS < 0.1, FID/INP < 200ms
- Images: WebP, lazy loading, correct dimensions
- Fonts: preload + font-display: swap
- JS bundle < 200KB gzipped
- SSG for all content pages
- Lazy load non-critical components

### Documentation Update Rules

After every task, evaluate whether documentation needs updating (part of compound phase).

**When to update:** New route, new component/package, architecture change, new env var, new command/script, significant dependency change, new pattern (solution doc), deployment process change, bug class eliminated (prevention rule).

**When NOT to update:** Minor CSS/copy changes, internal refactors not changing interfaces, test-only changes, dependency patch updates.

---

## PROOT-DISTRO ARM64 ENVIRONMENT

**Auto-detection:** If `uname -r` contains `PRoot-Distro` AND `uname -m` = `aarch64`, all rules in this section are ACTIVE. Three layers handle proot:
- **settings.json env:** Sets `NODE_OPTIONS`, `CHOKIDAR_USEPOLLING`, `WATCHPACK_POLLING` globally (always active)
- **proot-preflight.sh:** Runs on first Bash command per session; WARNS about disk, symlinks, SST locks, .npmrc (informational only, exit 0)
- **worktree-preflight.sh:** Called by orchestrator Step 0; sets env vars and fixes deps for sprint execution

**Full reference:** `~/.claude/docs/proot-distro-environment.md`

### Mandatory Rules (when proot-distro detected)

1. **NEVER attempt `playwright install chromium`** or `browser_take_screenshot` — Chromium doesn't run in proot ARM64. Use `browser_snapshot` (accessibility tree) instead.
2. **NEVER trust `pnpm install` blindly** — Check `.npmrc` for `node-linker=hoisted` first. After install, verify: `find node_modules/.bin -type l ! -exec test -e {} \; -print | head -5`
3. **NEVER set tight timeouts** — Everything runs 2-5x slower. Multiply expected times by 3x minimum.
4. **NEVER use Lighthouse/PageSpeed as quality gates** — Performance scores are unreliable in proot. Mark as `BLOCKED: proot-distro ARM64`.
5. **NEVER rely on `inotify`** — Polling env vars are set globally in `settings.json`.
6. **ALWAYS check for SST state locks** before deploy: `ls .sst/lock* 2>/dev/null`
7. **NODE_OPTIONS is set globally** in `settings.json` — no manual export needed.
8. **ALWAYS use retry-with-backoff for external APIs** — `source ~/.claude/hooks/retry-with-backoff.sh`

### Known Native Module Failures

These packages have native binaries that WILL fail in proot-distro:
- `@parcel/watcher` → use `PARCEL_WATCHER_BACKEND=fs-events` or JS fallback
- `@rollup/rollup-linux-arm64-gnu` → use `--ignore-scripts` and rebuild selectively
- `sharp` → use JS-based image processing alternatives
- `turbo` (native) → use non-native mode
- Any `node-gyp` compilation → prefer JS alternatives

### Go Binary /.l2s/ Fix

Go binaries resolve libs via `/proc/self/exe`, which proot translates to `/.l2s/`. Copy required resource files there:
```bash
if [ -d "/.l2s" ]; then cp /path/to/lib/*.d.ts /.l2s/; fi
```
Already handled for tsgo in `end-of-turn-typecheck.sh`.

### Error Pattern → Automatic Response

Full error pattern table with root causes and fixes: `~/.claude/docs/proot-distro-environment.md`. Key patterns to recognize immediately: `ENOENT .bin/` (broken symlink → `pnpm install`), `spawn EACCES` (binary not executable → JS alternative), `heap out of memory` (→ `NODE_OPTIONS`), `Chromium not found` (→ `browser_snapshot` MCP), `SIGBUS/SIGSEGV` on native binary (→ JS fallback).

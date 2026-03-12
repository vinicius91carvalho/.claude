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
**Process:** Fix directly, run tests, update session-learnings if surprising. No PRD.
**Spec:** Intent Doc (4 lines): Task, Scope, Boundaries, If Uncertain.

#### Standard

**When:** Multi-file, clear scope, moderate complexity.
**Process:** Contract-First, Correctness Discovery, Minimal PRD, implement, verify, compound.

#### PRD + Sprint

**When:** Large feature, multi-component, or >1h of agent work.
**Process:** Contract-First, Correctness Discovery, Full PRD, Sprint decomposition, compound.

In autonomous mode: execute sprints sequentially, still ask on escalation criteria, pause between sprints to update PRD and evaluate context health.

### Contract-First Pattern (mandatory for Standard and PRD+Sprint)

Before executing any multi-step task, establish mutual agreement:

1. **Intent:** User describes what they want
2. **Mirror:** Agent mirrors understanding back, including ambiguities and planned tradeoffs
3. **Receipt:** User confirms, corrects, or refines

Only after Step 3 does execution begin. Quick Fix skips this.

### PRD-Driven Task System

**Location:** `docs/tasks/<area>/<category>/YYYY-MM-DD_HHmm-descriptive-name.md`
**Categories:** `feature`, `bugfix`, `refactor`, `infrastructure`, `security`, `documentation`

#### Correctness Discovery (mandatory before any PRD)

1. **Audience:** Who uses this output and what decision will they make?
2. **Failure Definition:** What would make this output useless?
3. **Danger Definition:** What would make this output actively harmful?
4. **Uncertainty Policy:** Guess / Flag / Stop when uncertain?
5. **Risk Tolerance:** Confident wrong answer or refusal — which is worse?
6. **Verification:** How would you check if the output is correct?

PRD templates (Minimal and Full) live in `~/.claude/skills/plan/` alongside the planning skill.

### Sprint System

Large PRDs decompose into Sprints — self-contained units for one agent in a healthy context window.

**Rules:**

1. Each Sprint MUST be independently verifiable (own acceptance criteria and tests)
2. Each Sprint SHOULD produce a working state (builds and passes tests)
3. Ordered by dependency (N+1 may depend on N, never reverse)
4. Target size: 30-90 minutes of agent work. Larger: decompose further
5. Maximum 8 sprints per PRD. More needed: split the PRD

Sprint execution is delegated to the `sprint-executor` agent (`~/.claude/agents/sprint-executor.md`). The orchestrator manages lifecycle and coherence.

### The Full Pipeline: Plan → Build+Test → Ship+Verify → Compound

These four skills form a complete end-to-end workflow. Each is auto-invoked or manually triggered:

```
User describes task
      │
      ▼
[/plan] — Classify mode, Contract-First, PRD, Sprint decomposition
      │
      ▼ (user says "build it" / "execute")
[/plan-build-test] — Discover tasks, batch plan, parallel worktree execution, local verification
      │
      ▼ (user manually tests, says "ship it")
[/ship-test-ensure] — Commit, push, staging deploy, staging E2E, production deploy, Lighthouse 100/100
      │
      ▼ (auto-invokes on completion)
[/compound] — Learning capture, knowledge promotion, session-learnings update
```

**Project-specific commands** (build, test, lint, deploy, URLs, pages to audit) live in each project's CLAUDE.md under `## Execution Config`. Skills read from there — never hardcode project details.

**Fresh context principle:** Each major skill works best in a fresh context window. The plan saves state to session-learnings; the next skill reads it. This prevents context pollution across phases.

### Knowledge Promotion Chain

session-learnings (ephemeral) → `docs/solutions/` (project knowledge) → ADRs (architectural decisions) → CLAUDE.md updates (workflow improvements). Promote when a pattern proves useful across 2+ tasks.

---

## CONTEXT ENGINEERING

### Agent Architecture (Native Subagents)

Agents live in `~/.claude/agents/`. Each has its own context window, tool permissions, model, and system prompt.

- **orchestrator** — Task management, sprint lifecycle, agent delegation. Full tool access. Uses opus.
- **sprint-executor** — Single sprint execution. Isolated worktree. Uses sonnet. Tools: Read, Write, Edit, Bash, Glob, Grep.
- **code-reviewer** — Read-only post-sprint review. Uses sonnet. Tools: Read, Grep, Glob.

### Worktree Isolation for Parallel Work

Sprint agents use `isolation: worktree` in frontmatter. Each gets its own git worktree and branch. Worktrees auto-clean when agent finishes without changes. Independent sprints can run in parallel; the orchestrator handles merging.

### Context Budget Rules

The main agent is an **orchestrator**, not a worker. Its context contains: system instructions + session learnings + subagent summaries + user messages. If reading file contents or build output directly, delegate to a subagent instead.

**Exceptions:** Playwright browser interaction stays in main agent. Simple file edits (checkboxes, session-learnings) are done directly. Bug investigation may read up to 5 targeted files; more than that, delegate.

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

Enforced via Stop hook in `settings.json` — agent cannot declare completion until verification passes.

### Scope Boundary Enforcement

If during implementation you discover:

- Related bug in different area — log in PRD under "Issues Found", do NOT fix
- Opportunity to improve unrelated code — log it, do NOT do it
- Already-broken test — log it, do NOT fix (unless in sprint scope)

Stay in scope. Resist "one more thing."

### Deterministic Safety via Hooks

The "Agent NEVER does" column is enforced as PreToolUse hooks in `~/.claude/settings.json`, not just prompt suggestions. PostToolUse hooks auto-format after edits. Stop hooks enforce Anti-Goodhart verification. These are hard rules the agent cannot bypass.

---

## EVALUATION

### The Verification Pattern

LLMs are non-deterministic. The most reliable pattern combines:

1. **Prose specification** — intent, context, constraints (the PRD)
2. **Executable tests** — machine-verifiable correctness contract
3. **Iteration loops** — catch non-deterministic failures (run, fail, fix, run)

Default iteration budget: 3 retries per task. What tests cannot catch: security heuristics, architectural implications, complex layer interactions — human review is the judgment layer.

### Stack Evaluation Checklist

| Layer     | Question                                                                          | Pass? |
| --------- | --------------------------------------------------------------------------------- | ----- |
| Prompt    | Did output match what was asked? Format, scope, constraints followed?             | [ ]   |
| Context   | Were all relevant docs read?                                                      | [ ]   |
| Intent    | Were tradeoffs resolved per Value Hierarchy?                                      | [ ]   |
| Judgment  | Were uncertainties documented? Assumptions flagged correctly?                     | [ ]   |
| Coherence | Does implementation follow existing patterns/ADRs? Consistent with previous work? | [ ]   |

### Diagnostic Loop

When output is unsatisfactory, diagnose WHICH layer failed:

1. Wrong format/scope/constraints? → **Prompt** issue
2. Missing/wrong information? → **Context** issue
3. Wrong tradeoffs? → **Intent** issue
4. Charged ahead on uncertain ground? → **Judgment** issue
5. Inconsistent with previous work? → **Coherence** issue

Re-enter at the failing layer. Often the fix is adding context or clarifying intent, not changing the prompt.

### Spec Self-Evaluator (run before executing any PRD)

- [ ] Problem stated before solution?
- [ ] Audience explicitly named?
- [ ] Success metrics quantitative and binary-testable?
- [ ] Failure modes enumerated?
- [ ] Danger modes enumerated?
- [ ] Non-goals at least as detailed as goals?
- [ ] All constraints explicit?
- [ ] Uncertainty policy stated?
- [ ] Tradeoff preferences stated?
- [ ] Verification steps described?
- [ ] All vague terms have measurable translations?
- [ ] No references to tacit knowledge without providing it?
- [ ] Abstraction level appropriate for task size?
- [ ] Could a different agent execute this unambiguously?

**Scoring:** 11-14 pass = ready. 7-10 = revise weak areas. Below 7 = fundamental rethink.

---

## HARNESS & TOOLING

### Model Assignment Matrix

| Task Type                                     | Model    |
| --------------------------------------------- | -------- |
| File scanning, discovery, dependency analysis | `haiku`  |
| Simple fixes (lint, format, typos, CSS)       | `haiku`  |
| Session learnings compilation                 | `haiku`  |
| Standard implementation                       | `sonnet` |
| Bug fix implementation                        | `sonnet` |
| Test writing                                  | `sonnet` |
| Verification & regression scan                | `sonnet` |
| Complex/multi-file refactoring                | `opus`   |
| Architectural decisions                       | `opus`   |
| Merge conflict resolution                     | `opus`   |

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

- **PostToolUse(Write|Edit):** Auto-format after every file change
- **PreToolUse(Bash):** Block destructive commands (rm -rf, force push, deploy)
- **Stop:** Anti-Goodhart enforcement — verify completion before allowing stop
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

For multi-task workflows, maintain a session learnings file as **living memory** that survives `/compact`. The project CLAUDE.md specifies the exact path; if none is specified, use `docs/session-learnings.md`.

**Update rules:** Append errors as they occur, patterns when they repeat across 2+ tasks, rules when mistakes happen, task status as work progresses, agent performance after each completes.

**Promotion rule:** When a session learning proves useful across 2+ tasks, promote it to a solution doc in `docs/solutions/`.

---

## SELF-IMPROVEMENT PROTOCOL

### Per-Task Compound (every task)

1. **Capture:** What worked? What didn't? What is the reusable insight?
2. **Document:** Create solution doc if pattern is reusable. Update session learnings.
3. **Update the system:** If a rule, pattern, or doc needs changing, do it now — not "later."
4. **Verify:** "Would the system catch this automatically next time?" If no, compound is incomplete.

### Per-Session Compound (end of session)

1. **Compile:** Analyze session learnings — error frequency, categories, model effectiveness
2. **Generate rules:** For each repeated error, create a rule with trigger/action/reason
3. **Promote to solutions:** Move confirmed patterns from session learnings to `docs/solutions/`
4. **Persist to MEMORY.md:** Only patterns confirmed across 2+ tasks
5. **Suggest CLAUDE.md updates** for workflow improvements

### The Three Compound Questions

Before closing any task:

1. "What was the hardest decision made here?"
2. "What alternatives were rejected, and why?"
3. "What are we least confident about?"

---

## ANTI-PATTERNS (Quick Reference)

**Specification:**

- **Kitchen Sink** — Everything in one massive spec. Fix: right-size to task.
- **Aspirational** — "Make it better." Fix: translate to measurable behavior.
- **Solution Spec** — Prescribing HOW not WHAT. Fix: separate functional from technical.
- **Assumption** — "Follow our patterns" without saying which. Fix: provide the pattern or path.
- **No-Boundary** — Goals without non-goals. Fix: non-goals as detailed as goals.

**Workflow:**

- **Mode Rigidity** — One mode regardless of task. Fix: switch freely.
- **Review Complacency** — Less critical as volume grows. Fix: rigor scales with risk.
- **False Sense of Control** — Templates guarantee compliance. Fix: trust but verify.
- **Spec-as-Bureaucracy** — Full PRD for a one-line fix. Fix: match ceremony to complexity.
- **No Feedback Loops** — Not tracking failures. Fix: log, find patterns, update templates.

---

## GLOBAL RULES

### Git Workflow

- **Branching:** One branch per feature or bug fix. Name: `<type>/<short-description>`
- **Commits:** Atomic. Format: `<type>: <what changed>`
- **Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`
- **Never force-push to main.** Always create PRs for non-trivial changes.
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

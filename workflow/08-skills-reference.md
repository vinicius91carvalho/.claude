# Skills Reference

Skills are auto-invocable workflows that live in `~/.claude/skills/`. Each skill has a `SKILL.md` file that defines the step-by-step procedure. Skills auto-invoke based on conversation context — you can also invoke them explicitly with `/skill-name`.

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SKILL PIPELINE                                │
│                                                                        │
│    /plan              Generate PRD only. For when you want to plan     │
│       │               without executing.                               │
│       ▼                                                                │
│    /plan-build-test   Smart entry point: discover tasks, plan if       │
│       │               needed, execute with agent teams, verify         │
│       │               locally. Runs autonomously by default.           │
│       ▼                                                                │
│    /update-docs       Analyze codebase and sync documentation.         │
│       │               Auto-invoked when push blocked by stale docs.    │
│       ▼                                                                │
│    /ship-test-ensure  CI/CD pipeline: branch, PR, merge, staging      │
│       │               E2E, production deploy, Lighthouse (optional).   │
│       │               Autonomous through staging; confirms before      │
│       │               production.                                      │
│       ▼                                                                │
│    /compound          Post-task learning capture. Auto-invoked         │
│       │               after completion. Cross-project knowledge        │
│       │               promotion.                                       │
│       ▼                                                                │
│    /workflow-audit    Periodic self-review. Monthly or after 10+       │
│                      sessions. Reviews model performance, error        │
│                      patterns, rule staleness.                         │
│                                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## /plan — Planning Only

**Trigger:** User describes a new task, feature, bug, or says "plan", "let's build", "I need", "implement".

**Output:** PRD file(s) at `docs/tasks/`. Does NOT execute — this skill produces the plan only.

### Steps

```
Step 1: Classify mode
        ├── Quick Fix → "No PRD needed"
        ├── Standard → Minimal PRD
        └── PRD+Sprint → Full PRD

Step 2: Contract-First (mirror understanding, get confirmation)

Step 3: Correctness Discovery (2 or 6 questions)

Step 4: Write PRD at docs/tasks/<area>/<category>/YYYY-MM-DD_HHmm-name/spec.md

Step 5: Spec Self-Evaluator
        ├── Spawn SEPARATE haiku agent (different perspective)
        ├── Score 14-point checklist
        ├── Must score 11+/14 to proceed
        └── Below 11: revise and re-evaluate

Step 6: Extract sprint specs (if PRD+Sprint)
        ├── Create sprints/ subdirectory
        ├── One file per sprint with file boundaries
        ├── Create progress.json
        └── Validate: max 5 sprints, no file conflicts within batches

Step 7: "PRD saved. Run /plan-build-test to execute."
```

**Key design decision:** A separate agent evaluates the spec. Using a separate agent prevents the author from grading their own homework — different context = more honest evaluation.

---

## /plan-build-test — The Local Pipeline

The most extensive skill. Operates as a **Team Lead** coordinating specialist agents. **Autonomous by default.**

### Phases

```
Phase 0: Resume Gate
         ├── progress.json with pending sprints?  → Phase 3 (execute)
         ├── All sprints complete?                → Phase 6 (learn)
         ├── All sprints blocked?                 → Report to user
         └── No progress.json?                    → Phase 1 (discover)

Phase 1: Discovery
         Spawn Explore agent (haiku) to find pending tasks

Phase 2: Batch Planning
         Analyze dependencies, assign models, auto-start

Phase 3: Execution
         For each batch:
         ├── PRD+Sprint task → spawn orchestrator agent
         │   (one per batch, fresh context)
         ├── Simple task → spawn general-purpose agent
         └── Inter-Batch Learning Loop:
             Batch 1's mistakes → Batch 2's rules

Phase 4: Post-Implementation
         ├── Code review (code-reviewer agent)
         └── Code simplification (code-simplifier plugin)

Phase 5: Live Verification (MANDATORY — CANNOT BE SKIPPED)
         ├── 5.1: Static verification (build, lint, types, tests)
         ├── 5.2: Dev server startup (MANDATORY)
         ├── 5.2.5: Runtime content verification
         ├── 5.3: Route health check (ALL routes must return 200)
         ├── 5.4: Playwright E2E tests
         ├── 5.5: Task file audit (plan completeness re-read)
         ├── 5.6: Regression scan
         ├── 5.7: Handle failures (adaptive retries)
         ├── 5.8: Kill dev server
         └── 5.9: Final gate — verification summary
              ALL items must show PASS to proceed

Phase 6: Learning & Self-Improvement
         ├── Persist to project knowledge files
         ├── Update error-registry.json
         ├── Update model-performance.json
         ├── Write session postmortem
         └── Generate session report
```

### The Inter-Batch Learning Loop

Before spawning the next batch, the skill re-reads session learnings to include rules from previous batches in the next agents' prompts. This creates a **learning chain**: Batch 1's mistakes become Batch 2's prevention rules.

---

## /ship-test-ensure — Deploy Pipeline

Takes code from "locally verified" to "production with perfect Lighthouse scores." **Autonomous through staging; confirms before production.**

### Phases

```
Phase 0: Context & Config
         Read Execution Config, detect changed apps, run local verification

Phase 1: Commit, Branch & PR
         ├── Capture PRE_DEPLOY_SHA (rollback point)
         ├── Create feature branch (ship/YYYYMMDD-HHMM-desc)
         ├── Stage specific files (never git add -A)
         ├── Commit, push, create PR
         ├── Wait for CI checks
         └── Merge via squash merge

Phase 2: Follow Staging Deploy
         ├── Monitor GitHub Actions (30s poll, 15min timeout)
         └── Max 3 retry cycles

Phase 3: E2E on Staging
         ├── Run E2E suite against staging URL
         ├── Categorize failures: actual bugs vs flaky vs staging-specific
         └── Max 5 fix-deploy-test cycles

Phase 4: Production Deploy
         ├── ★ MANDATORY USER CONFIRMATION ★
         ├── Trigger production deploy commands
         └── Monitor with same pattern as Phase 2

Phase 5: PageSpeed & Lighthouse (Optional — requires pages_to_audit config)
         ├── Skip entirely if no pages_to_audit configured
         ├── Test all configured pages (mobile + desktop)
         ├── Classify: code-fixable / infrastructure / third-party
         ├── Spawn fix agents
         ├── PSI API key supported (PSI_API_KEY env var)
         └── Max 5 iterations; plateau or 429 quota → accept current scores

Phase 6: Final Report & Compound
         ├── Final Lighthouse score table
         ├── Core Web Vitals report
         └── Rollback protocol (★ MANDATORY USER CONFIRMATION ★)
```

**Why CI/CD through PRs:** The system enforces PR workflow because: (1) CI checks run on the PR, (2) merge is auditable, (3) rollback is clean, (4) industry best practice.

---

## /compound — Learning Capture

The shortest skill but conceptually the most important:

### Steps

```
Steps 1-3: Review → Identify learnings → Update session-learnings

Step 4:    Knowledge Promotion Chain
           ├── Pattern repeats? → docs/solutions/
           ├── Affects architecture? → propose ADR
           ├── Workflow change? → propose CLAUDE.md update
           ├── System Update Loop:
           │   ├── Missing agent instructions → update agent file
           │   ├── Missing hook → propose settings.json change
           │   └── Skill gap → update skill file
           └── Feedback Capture:
               Mine user corrections from conversation
               → error-registry + model-performance + system updates

Step 5:    The Three Compound Questions
           ├── "What was the hardest decision made here?"
           ├── "What alternatives were rejected, and why?"
           └── "What are we least confident about?"

Steps 6-8: Cross-project promotion
           ├── Update error-registry.json
           ├── Update model-performance.json
           ├── Promote to cross-project memory (if 2+ projects)
           ├── Log in workflow-changelog.md
           └── Write session postmortem

Step 9:    Write completion marker

Step 10:   Workflow Integrity Gate (if ~/.claude/ files modified)
           Run test-workflow-mods/run-tests.sh (112 assertions)
           ├── All pass → proceed
           └── Failures → fix before finalizing

Step 11:   Suggest committing workflow changes (if using git backup)
```

### Quick Fix Micro-Compound

For trivial fixes, skip the full compound. Ask one question: "Would the system catch this automatically next time?" If no — add to error-registry or session-learnings.

---

## /workflow-audit — System Self-Review

Periodic audit of the workflow system itself. Run monthly or after 10+ sessions.

### Steps

```
Step 1: Load evolution data (error-registry, model-performance, changelog)

Step 2: Error pattern analysis
        ├── Frequency: which categories occur most?
        ├── Recurrence: errors that keep happening despite fix?
        ├── Resolution: % auto-preventable?
        └── Cross-project: errors in 3+ projects?

Step 3: Model performance analysis
        ├── Success rate table per model per task type
        ├── Upgrade candidates (<70% success with 10+ samples)
        ├── Downgrade candidates (>90% — save cost)
        └── Cost estimate for proposed changes

Step 4: Rule staleness check
        ├── List all rules (MUST, NEVER, ALWAYS)
        ├── Flag rules >90 days old and never triggered
        └── Check for contradictions

Step 5: Changelog review
        ├── Change velocity (0 = not learning, >10 = thrashing)
        └── Regression check (any reverted changes?)

Step 6: Session postmortem analysis

Step 7: Generate audit report (health score 1-10)

Step 8: Apply recommendations (with user approval only)
```

---

## /update-docs — Documentation Sync

Analyzes the codebase and updates project documentation to reflect the current state of the code. Works on any project — not just the workflow repo.

### Phases

```
Step 1: Detect Documentation Targets
        ├── Find existing docs (README.md, docs/, CHANGELOG.md, etc.)
        ├── Analyze codebase structure (Explore agent, haiku)
        └── Detect what changed since docs were last updated (git diff)

Step 2: Diff Analysis — What's Stale?
        ├── Compare code state vs. doc content
        ├── Identify: missing, stale, inaccurate, current
        └── Report audit to user before making changes

Step 3: Update Documentation
        ├── Delete stale/incorrect content
        ├── Update partially correct sections
        ├── Add new sections for undocumented components
        └── Follows project-type guidelines (web app, library, workflow, CLI)

Step 4: Verify
        ├── Check internal links (broken markdown references)
        ├── Check command accuracy (scripts exist?)
        └── Check path accuracy (referenced files exist?)

Step 5: Report
        Summary of changes + verification results
```

**Key principles:** Concise over verbose. Accurate over complete. Delete wrong docs rather than adding more. Examples over descriptions.

**Trigger:** "update docs", "sync readme", "docs are stale", or auto-invoked when `check-docs-updated.sh` blocks a push.

---

Next: [Hooks & Enforcement](09-hooks-and-enforcement.md)

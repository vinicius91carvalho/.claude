---
name: compound
description: >
  Post-task learning capture and knowledge promotion. Auto-invoke when a task
  or sprint is completed, when the user says "done", "finished", "wrap up",
  or when all acceptance criteria are checked off. Do NOT invoke when user
  says "ship it" — that triggers /ship-test-ensure instead.
context: fork
---

# Compound: Learning Capture & Knowledge Promotion

1. **Review what was done** — read PRD, recent changes, or conversation context
2. **Identify learnings:**
   - What worked well?
   - What didn't work or was surprising?
   - Were there any assumptions that turned out wrong?
   - Did any tool/pattern perform better or worse than expected?
3. **Update session-learnings** with key findings (use structured format — see Step 6)
4. **Knowledge Promotion Chain** — check if promotion is warranted:
   - Does this pattern repeat from previous session-learnings? → promote to `docs/solutions/`
   - Does this affect architecture? → propose an ADR in `docs/architecture/decisions/`
   - Does this suggest a workflow change? → propose CLAUDE.md update (ask user first)

   4b. **System Update Loop (when compound identifies workflow failures):**
   - If the failure was caused by missing/ambiguous agent instructions:
     → UPDATE the agent definition file directly (ask user first)
   - If the failure was caused by a missing enforcement hook:
     → PROPOSE a settings.json hook change (ask user first)
   - If the failure was caused by a skill gap:
     → UPDATE the skill file directly (ask user first)
   - Memory entries alone are NOT sufficient for systemic failures.
     Memory helps future conversations. System updates prevent future failures.
   - **Log every system change** in `~/.claude/evolution/workflow-changelog.md` with date, what, why, source.

   4c. **Feedback Capture (mine user corrections for learning signal):**
   User corrections are the richest learning signal. Scan the conversation for:
   - Explicit corrections: "no", "don't", "stop", "instead", "not that", "wrong"
   - Approach rejections: "let's not", "that's not right", "try X instead"
   - Preference signals: "I prefer", "always use", "never do"

   For each correction found:
   1. Is it project-specific? → session-learnings
   2. Is it a general pattern applicable to other projects? → error-registry entry
   3. Did the model fail at something it should handle? → model-performance (mark first_try_success = false)
   4. Does it imply a missing rule or hook? → propose system update (4b)
   5. Does it record a failed approach? → add to error-registry `approaches_that_failed`
5. **The Three Compound Questions:**
   - "What was the hardest decision made here?"
   - "What alternatives were rejected, and why?"
   - "What are we least confident about?"
6. **Structured Session Learnings** — when updating session-learnings, use categorized format:

   ```markdown
   ## Errors
   - [CATEGORY] description → fix applied
   Categories: ENV, LOGIC, CONFIG, DEPENDENCY, SECURITY, TEST, DEPLOY, PROOT, MERGE, PERFORMANCE

   ## Rules Generated
   - Rule text (category: CATEGORY)

   ## Model Performance
   - model_name: N/M tasks first-try success (note any upgrades/downgrades needed)

   ## Metrics
   - Total retries: N
   - Phases that caught bugs: [list]
   - Phase 5 duration: Ns
   ```

7. **Cross-Project Promotion** — check if learnings apply beyond the current project:

   a. **Error registry update** — ALWAYS write errors to the registry, even on first occurrence.
      You can't detect cross-project patterns without capturing data points from day one.
      - Read `~/.claude/evolution/error-registry.json`
      - **JSON safety:** Before writing, validate the file parses correctly. If corrupt,
        restore from `error-registry.json.bak` (or create empty `{"entries":[]}` if no backup).
      - Create backup: copy current file to `error-registry.json.bak` before modifying.
      - Add or update entry with:
        ```json
        {
          "pattern": "error message or symptom regex",
          "category": "ENV|LOGIC|CONFIG|...",
          "root_cause": "why it happens",
          "fix": "how to fix it",
          "auto_preventable": false,
          "prevention": "hook/rule that prevents it (if auto_preventable)",
          "approaches_that_failed": [
            { "approach": "what was tried", "why_bad": "why it didn't work" }
          ],
          "projects_seen": ["project-name"],
          "first_seen": "2026-03-14",
          "last_seen": "2026-03-14",
          "occurrences": 1
        }
        ```
      - If entry already exists for this pattern: increment `occurrences`, update `last_seen`, add project to `projects_seen`, merge any new `approaches_that_failed`
      - If pattern seen in 3+ projects and `auto_preventable: false`: flag for hook creation
      - **Write to temp file first**, validate JSON parses, then replace original

   b. **Model performance update** — ALWAYS record model performance, even on first session.
      - Read `~/.claude/evolution/model-performance.json`
      - **JSON safety:** Backup to `model-performance.json.bak` before modifying.
        Validate JSON before and after write. Restore from backup if corrupt.
      - For each model used in this session, update the relevant task type:
        - Increment `attempts`
        - If succeeded on first try: increment `first_try_success`
        - If model was upgraded mid-task: increment `required_upgrade`
      - **Source of truth for model performance:** Read from sprint-executor return summaries
        (`model_requested`, `first_try_success`, `task_types`) and orchestrator metrics
        (`sprint_model_performance`). Don't guess — use the structured data.
      - **Check adaptation thresholds:**
        - If any task type has `attempts >= 10` and `first_try_success / attempts < 0.7`:
          → Propose model upgrade to user (e.g., sonnet → opus for that task type)
        - If any task type has `attempts >= 10` and `first_try_success / attempts > 0.9`:
          → Propose model downgrade to user (e.g., sonnet → haiku for cost savings)

   c. **Memory promotion** — if a learning applies across all projects:
      - Write to `~/.claude/projects/-root/memory/` (use appropriate memory type: feedback, project, or reference)
      - Update `MEMORY.md` index
      - Only promote patterns confirmed across 2+ tasks (session-learnings) or 2+ projects (error-registry)

   d. **Workflow changelog** — if any system file was modified (CLAUDE.md, skill, agent, hook):
      - Append entry to `~/.claude/evolution/workflow-changelog.md` with date, what, why, source

8. **Session Postmortem** (run at end of session or when user says "wrap up"):

   Write a structured postmortem to `~/.claude/evolution/session-postmortems/YYYY-MM-DD_project-name.md`:

   ```markdown
   # Session Postmortem — [date] — [project]

   ## Summary
   - Tasks completed: N
   - Tasks blocked: N
   - Total retries: N
   - Models used: [list with task counts]

   ## Error Categories
   - [CATEGORY]: N occurrences

   ## Verification Gate Effectiveness
   - Gate that caught real bugs: [list]
   - Gates that always passed (may be redundant for this project): [list]

   ## Model Performance This Session
   | Model | Task Type | Attempts | 1st Try | Rate |
   |-------|-----------|----------|---------|------|

   ## Compound Actions Taken
   - [list of system updates, promotions, rules generated]

   ## Open Questions
   - [from Three Compound Questions]
   ```

9. **Write completion marker** so the compound-reminder hook knows compound ran:
   ```bash
   touch "${HOME}/.claude/state/.claude-compound-done-${CLAUDE_SESSION_ID:-unknown}"
   ```

10. **Workflow Integrity Gate** — if compound modified ANY workflow files (`~/.claude/` — hooks,
    skills, agents, settings.json, CLAUDE.md), run the integrity test suite:
    ```bash
    bash ~/.claude/test-workflow-mods/run-tests.sh
    ```
    - If all tests pass: proceed to step 11
    - If any tests fail: fix the failures before continuing. The test suite validates that
      all hooks exist and are executable, settings.json registrations are correct and
      cross-referenced, CLAUDE.md documents all key concepts, agent/skill files have correct
      structure, and evolution infrastructure is intact.
    - This step is MANDATORY when workflow files were modified. Skip ONLY if no `~/.claude/`
      files were touched during this compound cycle.

11. **If using git backup for `~/.claude/`:** suggest committing workflow changes

## Quick Fix Micro-Compound

When compound is triggered after a Quick Fix (single-file, <30 lines):

1. Skip steps 1-5 (full compound is overkill)
2. Ask ONE question: "Would the system catch this automatically next time?"
3. If NO:
   - Add to error-registry if cross-project
   - Add to session-learnings if project-specific
   - Propose a hook or rule if it's a recurring category
4. If YES: log brief entry in session-learnings and move on
5. Update model-performance.json with the model used and outcome

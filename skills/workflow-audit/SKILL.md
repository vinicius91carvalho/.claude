---
name: workflow-audit
description: >
  Periodic self-audit of the workflow system. Reviews rule effectiveness,
  model performance, error patterns, and stale configuration. Use monthly
  or when the user says "audit workflow", "review the system", "check workflow health".
---

# Workflow Audit — Periodic System Self-Review

Audit the workflow system for effectiveness, staleness, and optimization opportunities.
This skill reads from the evolution data (`~/.claude/evolution/`) and evaluates whether
the system is improving, stagnating, or accumulating dead weight.

---

## Step 1: Load Evolution Data

Read these files:

1. `~/.claude/evolution/error-registry.json` — cross-project error patterns
2. `~/.claude/evolution/model-performance.json` — model success rates
3. `~/.claude/evolution/workflow-changelog.md` — recent system changes
4. `~/.claude/evolution/session-postmortems/` — recent session reports
5. `~/.claude/CLAUDE.md` — current system rules
6. `~/.claude/projects/-root/memory/MEMORY.md` — cross-project memory index

---

## Step 2: Error Pattern Analysis

From `error-registry.json`:

1. **Frequency report:** Which error categories occur most? (ENV, LOGIC, CONFIG, etc.)
2. **Recurrence check:** Are there errors that keep recurring despite having a fix documented?
   - If yes → the fix isn't being applied automatically. Propose a hook or rule change.
3. **Resolution effectiveness:** What percentage of registered errors have `auto_preventable: true`?
   - Target: >80% of registered errors should be auto-preventable after the fix is documented.
4. **Cross-project patterns:** Which errors appear in 3+ projects?
   - These are candidates for CLAUDE.md rules or hooks.

---

## Step 3: Model Performance Analysis

From `model-performance.json`:

1. **Success rate table:**
   ```
   | Model  | Task Type        | Attempts | 1st Try Success | Rate  | Recommendation |
   |--------|------------------|----------|-----------------|-------|----------------|
   | sonnet | implementation   | 25       | 20              | 80%   | Keep           |
   | sonnet | bug_fix          | 12       | 7               | 58%   | Upgrade→opus   |
   | haiku  | simple_fixes     | 30       | 28              | 93%   | Keep           |
   ```

2. **Adaptation proposals** (only if min_samples threshold met):
   - If `first_try_success_rate < 70%` → propose upgrade
   - If `first_try_success_rate > 90%` → propose downgrade to save cost
   - Present proposals to user with data, don't auto-apply

3. **Cost estimate:** Based on approximate token costs per model, estimate monthly savings
   from proposed downgrades.

---

## Step 4: Rule Staleness Check

From `CLAUDE.md` and memory files:

1. **List all rules** (scan for imperative language: "MUST", "NEVER", "ALWAYS", etc.)
2. **Cross-reference with error-registry:** Is each rule backed by a real error that occurred?
   - Rules without backing evidence may be speculative — flag for review
3. **Recency check:** Are there rules that were added >90 days ago and never triggered?
   - These may be dead weight — propose removal or archiving
4. **Conflict check:** Do any rules contradict each other?

---

## Step 5: Workflow Changelog Review

From `workflow-changelog.md`:

1. **Change velocity:** How many changes in the last 30 days?
   - Too few (0) → system isn't learning
   - Too many (>10) → system may be thrashing
2. **Change provenance:** Do all changes have a "Why" and "Source"?
   - Changes without provenance can't be evaluated for effectiveness
3. **Regression check:** Were any changes reverted? What caused the revert?

---

## Step 6: Session Postmortem Analysis

From `session-postmortems/`:

1. **Aggregate metrics** across recent sessions:
   - Average retries per session
   - Most common blocked phases
   - Average Phase 5 duration
   - Compound completion rate (was /compound run?)
2. **Trend detection:**
   - Are retries increasing? (system getting fragile)
   - Are new error categories appearing? (new problem domain)
   - Is compound completion rate declining? (fatigue)

---

## Step 7: Generate Audit Report

Present findings as a structured report:

```markdown
## Workflow Audit Report — [date]

### Health Score: [1-10]

### Error Patterns
- Total registered: N
- Recurring (not auto-prevented): N — ACTION NEEDED
- Top 3 categories: [list]

### Model Performance
- Upgrade candidates: [list with data]
- Downgrade candidates (cost savings): [list with data]
- Estimated monthly token savings: $X

### Rule Health
- Total rules: N
- Rules with evidence: N
- Potentially stale (>90 days, never triggered): N — REVIEW
- Conflicts found: N

### Evolution Velocity
- Changes last 30 days: N
- Assessment: [healthy / stagnating / thrashing]

### Session Trends
- Compound completion rate: N%
- Average retries: N
- Most blocked phase: [phase]

### Recommendations (prioritized)
1. [action] — [evidence] — [expected impact]
2. ...
```

---

## Step 8: Apply Recommendations (with user approval)

For each recommendation:

1. Present the change with evidence
2. Ask user: approve / defer / reject
3. If approved: make the change directly (update CLAUDE.md, skill, hook, or agent file)
4. Log the change in `workflow-changelog.md`

---

## Standards

- This skill is READ-HEAVY — mostly analysis, minimal writes
- All recommendations must cite specific data from evolution files
- Never auto-apply changes — always ask user first
- Run this monthly or after 10+ sessions, whichever comes first
- If evolution data is empty (new system), report that and suggest running /compound after the next few tasks to build up data
- **CRITICAL: Do NOT recommend removing rules just because error-registry has no matching entries.** Rules may exist from user experience, security best practices, or prior incidents not captured in the registry. Only flag rules as "potentially stale" if they have been in place >90 days AND the error-registry has sufficient data (20+ entries) to establish that the rule's error pattern has never occurred.

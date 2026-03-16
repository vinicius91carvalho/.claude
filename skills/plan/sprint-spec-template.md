# Sprint [N]: [Title]

## Meta

- **PRD:** `../spec.md`
- **Sprint:** [N] of [total]
- **Depends on:** [Sprint N-1 / None]
- **Batch:** [N] ([sequential / parallel with Sprint X])
- **Model:** [sonnet / opus]
- **Estimated effort:** [S/M/L]

## Objective

[One sentence — what this sprint delivers]

## File Boundaries

### Creates (new files)

- `path/to/new-file.ts`

### Modifies (can touch)

- `path/to/existing-file.ts` — [what change and why]

### Read-Only (reference but do NOT modify)

- `path/to/shared-layout.ts` — [why needed for reference]

### Shared Contracts (consume from prior sprints or PRD)

- [Interface/type name from PRD Section 9]
- [Design token set]

### Consumed Invariants (from INVARIANTS.md)

- [Invariant name] — this sprint must satisfy [precondition/postcondition]
- [Invariant name] — verify command: `[command]`

## Tasks

- [ ] [Task 1 — atomic, verifiable]
- [ ] [Task 2 — atomic, verifiable]
- [ ] [Task 3 — atomic, verifiable]

## Acceptance Criteria

- [ ] [Binary-testable condition 1]
- [ ] [Binary-testable condition 2]

## Verification

- [ ] Build passes
- [ ] Lint passes
- [ ] Type-check passes
- [ ] Sprint-specific tests pass

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

[Any additional context the sprint agent needs — design details, API specs, component behavior. Keep this focused — only what's needed for THIS sprint, not the whole PRD.]

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

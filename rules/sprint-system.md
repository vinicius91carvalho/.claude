# Sprint System & Architecture Invariants

## Sprint Decomposition

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

## Build Candidate

A **Build Candidate** is a tagged commit that declares "this specification is complete enough to build from" — analogous to a release candidate, but for the design phase. It is the formal gate between planning and execution.

**When to tag:** After the PRD, sprint specs, progress.json, and INVARIANTS.md are all written and reviewed. The `/plan` skill tags the Build Candidate; `/plan-build-test` verifies it exists before execution.

**What it includes:** PRD spec.md, all sprint specs, progress.json, INVARIANTS.md, and any shared contract definitions. Tag format: `build-candidate/<prd-name>`.

**Why it matters:** Without a formal design-done gate, agents start building from incomplete specs. Every ambiguity resolved before implementation is a wrong guess prevented during implementation.

## Architecture Invariant Registry (INVARIANTS.md)

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

**Dependency direction:** If A depends on B, B owns the contract. Consumers declare which contracts they consume and must satisfy preconditions.

**Cascading invariants:** Project-level INVARIANTS.md applies everywhere. Component-level INVARIANTS.md adds constraints for specific directories. The hook walks up from the edited file to the project root, checking all levels.

**When to create:** During the `/plan` phase (PRD+Sprint mode), after sprint decomposition. The INVARIANTS.md is part of the Build Candidate.

**Orchestrator design:** Deterministic checklist — read progress.json → find next batch → spawn sprint-executors with ONLY their sprint spec → collect results → code review → merge → dev server verification → update progress.json → return. Minimal LLM judgment, maximum structure. Full protocol in `~/.claude/agents/orchestrator.md`.

## PRD-Driven Task System

**Location:** `docs/tasks/<area>/<category>/YYYY-MM-DD_HHmm-descriptive-name.md`
**Categories:** `feature`, `bugfix`, `refactor`, `infrastructure`, `security`, `documentation`

### Correctness Discovery (scaled by mode)

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

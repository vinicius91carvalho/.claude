# [Project Title]: Product Requirements Document

## 1. What & Why

**Problem:** [What pain point exists]
**Desired Outcome:** [What success looks like]
**Justification:** [Why this is worth doing now]

## 2. Correctness Contract

**Audience:** [Who uses this and what decisions they'll make]
**Failure Definition:** [What makes it useless]
**Danger Definition:** [What makes it harmful]
**Risk Tolerance:** [Confident wrong answer vs. refusal — which is worse?]

## 3. Context Loaded

- [Doc X]: [Key insight]
- [Doc Y]: [Key insight]

## 4. Success Metrics

| Metric   | Current | Target  | How to Measure |
| -------- | ------- | ------- | -------------- |
| [Metric] | [Value] | [Value] | [Method]       |

## 5. User Stories

GIVEN [precondition]
WHEN [action]
THEN [observable result]

## 6. Acceptance Criteria

- [ ] [Binary-testable — "QA can verify pass/fail"]

## 7. Non-Goals (at least as detailed as goals)

- [Exclusion 1 — and WHY excluded]
- [Exclusion 2 — and WHY excluded]

## 8. Technical Constraints

- Stack: [Languages, frameworks, libraries]
- Architecture: [Patterns to follow, files to reference]
- Performance: [Budgets if applicable]

## 9. Architecture Decisions

Significant decisions made in this PRD. Decisions rated "High" reversal cost deserve extra scrutiny during review.

| Decision | Reversal Cost | Alternatives Considered | Rationale |
|----------|--------------|------------------------|-----------|
| [What was decided] | Low/Med/High | [What else was considered, why rejected] | [Why this choice] |

## 10. Security Boundaries

- **Auth model:** [What auth is needed? Which endpoints/pages are protected?]
- **Trust boundaries:** [What is user-controlled input? Where does trusted/untrusted data cross?]
- **Data sensitivity:** [PII, credentials, tokens — what is handled and how?]
- **Tenant isolation:** [If multi-tenant: how is data segregated?]

## 11. Data Model (include if feature involves schema changes or new data entities)

**Access Patterns (define BEFORE schema):**
1. [Who queries what, how often, what filters, what latency requirement]

**Entities:** [Name, key attributes, relationships]
**Schema justification:** [How the chosen schema serves each access pattern above]

## 12. Shared Contracts

Define interfaces, types, design tokens, and component APIs that multiple sprints will consume. This is the coordination mechanism that replaces cross-sprint file sharing.

- **Design tokens:** [Colors, spacing, typography — reference or define here]
- **Component interfaces:** [Props, APIs that downstream sprints depend on]
- **Data types:** [Shared TypeScript types, schemas, API contracts]
- **Layout structure:** [Page layout, grid system, breakpoints]

## 13. Architecture Invariant Registry

Cross-cutting concepts that are defined in one bounded context and consumed by others.
Each entry becomes a machine-verifiable contract in INVARIANTS.md.

| Concept | Owner | Format/Values | Verify Command |
| ------- | ----- | ------------- | -------------- |
| [Permission strings] | [IAM] | `resource:action` | `grep -rn ... \| diff ...` |
| [Entity statuses] | [Core domain] | `draft\|active\|archived` | `grep -rn 'status' ...` |
| [Error codes] | [API layer] | `ERR_MODULE_NNNN` | `grep -rn 'ERR_' ...` |

**Dependency direction:** If A depends on B, B owns the contract.

## 14. Open Questions

- [ ] [Known unknown — who should answer?]

## 15. Uncertainty Policy

When uncertain: [Flag / Guess-and-document / Stop]
When [X] conflicts with [Y]: prefer [X/Y]

## 16. Verification

- Deterministic: [Tests, linters, type checks]
- Manual: [What human reviewer should check]

## 17. Sprint Decomposition

Maximum 5 sprints. Each sprint is extracted into its own file under `sprints/` during planning.

Sprint specs are written to: `[this-prd-directory]/sprints/NN-title.md`
Progress is tracked in: `[this-prd-directory]/progress.json`

### Sprint Overview

| Sprint | Title        | Depends On | Batch | Model  | Parallel With |
| ------ | ------------ | ---------- | ----- | ------ | ------------- |
| 1      | [Foundation] | None       | 1     | sonnet | —             |
| 2      | [Core UI]    | Sprint 1   | 2     | sonnet | —             |
| 3      | [Feature A]  | Sprint 2   | 3     | sonnet | Sprint 4      |
| 4      | [Feature B]  | Sprint 2   | 3     | sonnet | Sprint 3      |
| 5      | [Polish]     | 3, 4       | 4     | sonnet | —             |

### Sprint [N]: [Title] → `sprints/0N-title.md`

Each sprint spec file follows this structure (see sprint-spec-template.md):

**Objective:** [One sentence]
**Estimated effort:** [S/M/L]
**Dependencies:** [Sprint N-1 / None]

**File Boundaries:**

- `files_to_create`: [new files]
- `files_to_modify`: [existing files this sprint can touch]
- `files_read_only`: [files to reference but NOT modify]
- `shared_contracts`: [interfaces/types from Shared Contracts section above]

**Tasks:**

- [ ] [Task 1 — atomic, verifiable]
- [ ] [Task 2]

**Acceptance Criteria:**

- [ ] [Binary-testable condition]

**Verification:**

- [ ] [Test command]
- [ ] [Build command]

## 18. Execution Log

[Filled during execution — tracked in progress.json]

## 19. Learnings (filled after all sprints complete)

[Compound step output]

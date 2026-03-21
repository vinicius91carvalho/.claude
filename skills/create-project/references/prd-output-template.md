# PRD Output Template

Generate the final PRD as a single Markdown file with this structure.

---

```markdown
# [Product Name] — Product Requirements Document

> [One-line description]

**Version:** 1.0 | **Date:** [YYYY-MM-DD] | **Status:** Draft

---

## 1. Strategy

### 1.1 Vision
[What this product is, for whom, and why now]

### 1.2 Market Data
[Quantified problem: cost, waste, adoption rates, TAM]

### 1.3 Benchmark Analysis
[The best global product, what they do well, funding/scale, and what gap remains]

### 1.4 Competitive Landscape

| Competitor | Strengths | Weaknesses | Our Advantage |
|------------|-----------|------------|---------------|
| [Name]     | [...]     | [...]      | [...]         |

### 1.5 Positioning
[One sentence: "We are [X] but [Y] for [Z]"]

---

## 2. Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | [e.g., TypeScript 5.7+] | [Why] |
| Runtime | [e.g., Node.js 22+] | [Why] |
| Framework | [e.g., Hono] | [Why] |
| Database | [e.g., DynamoDB + ElectroDB] | [Why] |
| Cache | [e.g., Redis (ioredis)] | [Why] |
| Queue | [e.g., SQS] | [Why] |
| Auth | [e.g., jose (JWT)] | [Why] |
| Tests | [e.g., Vitest] | [Why] |
| IaC | [e.g., AWS CDK] | [Why] |
| CI/CD | [e.g., GitHub Actions] | [Why] |

---

## 3. Architecture Decision Records

### ADR-001: [Title]
- **Decision:** [What we chose]
- **Rationale:** [Why — with quantitative reasoning where possible]
- **Rejected:** [Alternative 1 (why not), Alternative 2 (why not), ...]

### ADR-002: [Title]
- **Decision:** [...]
- **Rationale:** [...]
- **Rejected:** [...]

_(Minimum 6 ADRs: compute, app architecture, database, auth/security, observability, testing)_

---

## 4. System Architecture

### 4.1 Module Structure
```
[Project tree showing directory structure and module boundaries]
```

### 4.2 Module Descriptions
[For each module: responsibility, domain entities, ports, communication pattern]

### 4.3 Architectural Layers
[Description of each layer: edge, modules, infrastructure, external]

### 4.4 Provider Abstraction (if multi-provider)
[Port interfaces with type definitions showing how the system abstracts external providers]

---

## 5. Data Layer

### 5.1 Access Patterns (BEFORE schema)
[Numbered list of primary query patterns and which index serves each]

### 5.2 Entity Definitions
[For each entity: attributes, indexes, access patterns — with code examples]

### 5.3 Schema Justification
[How the chosen schema serves each access pattern above]

---

## 6. Security

### 6.1 Credential Management
[How credentials flow, who holds what, TTL, rotation]

### 6.2 Threat Model

| Threat | Attack Vector | Mitigation |
|--------|---------------|------------|
| [...]  | [...]         | [...]      |

_(Minimum 8 threats with concrete mitigations)_

### 6.3 Worst-Case Scenario
[If the backend is fully compromised — what is the blast radius and what limits it?]

### 6.4 Compliance Mapping

| Requirement | Technical Control |
|-------------|------------------|
| [e.g., LGPD Art. 46] | [e.g., ephemeral credentials + TLS 1.3] |

---

## 7. Observability

### 7.1 Tooling
[What tools, self-hosted vs managed, why]

### 7.2 Key Metrics
[List of metrics that define system health and product success]

### 7.3 Evaluation Pipeline (if AI/ML)
[How model/agent quality is measured: eval suites, LLM-as-judge, A/B testing]

---

## 8. Developer Experience & Testing

### 8.1 Local Development
[How to go from `git clone` to running system — ideally one command]

### 8.2 Testing Pyramid
[Percentages: Unit / Integration / E2E / Smoke / Evals, with what each level covers]

---

## 9. Success Metrics

| Metric | Current | Target | How to Measure |
|--------|---------|--------|----------------|
| [...]  | [...]   | [...]  | [...]          |

---

## 10. User Stories

GIVEN [precondition]
WHEN [action]
THEN [observable result]

---

## 11. Acceptance Criteria

- [ ] [Binary-testable — "QA can verify pass/fail"]

---

## 12. Non-Goals

- [Exclusion 1 — and WHY excluded]
- [Exclusion 2 — and WHY excluded]

---

## 13. Shared Contracts

- **Design tokens:** [Colors, spacing, typography — if UI]
- **Component interfaces:** [Props, APIs downstream sprints depend on]
- **Data types:** [Shared TypeScript types, schemas, API contracts]
- **Port interfaces:** [Cross-module contracts]

---

## 14. Architecture Invariant Registry

| Concept | Owner | Format/Values | Verify Command |
|---------|-------|---------------|----------------|
| [Permission strings] | [IAM module] | `resource:action` | `grep -rn ...` |
| [Entity statuses] | [Core domain] | `draft\|active\|archived` | `grep -rn ...` |

---

## 15. Correctness Contract

**Audience:** [Who uses this product and what decisions they'll make]
**Failure Definition:** [What would make this product useless]
**Danger Definition:** [What would make this product actively harmful]
**Risk Tolerance:** [Confident wrong answer vs. refusal — which is worse?]

---

## 16. Uncertainty Policy

When uncertain: [Flag / Guess-and-document / Stop]
When [X] conflicts with [Y]: prefer [X/Y]

---

## 17. Open Questions

- [ ] [Known unknown — who should answer?]

---

## 18. Verification

- Deterministic: [Tests, linters, type checks]
- Manual: [What human reviewer should check]

---

## 19. Implementation Roadmap

### Sprint 1-2: [Title] (Weeks 1-4)
- [Deliverable 1]
- [Deliverable 2]

### Sprint 3-4: [Title] (Weeks 5-8)
- [Deliverable 1]

_(Repeat for all sprints)_

### MVP — Definition of Done
- [ ] [Observable behavior 1]
- [ ] [Observable behavior 2]

---

## 20. Sprint Decomposition

Maximum 5 sprints. Each sprint extracted to `sprints/NN-title.md`.

| Sprint | Title | Depends On | Batch | Model | Parallel With |
|--------|-------|------------|-------|-------|---------------|
| 1 | [Foundation] | None | 1 | sonnet | — |
| 2 | [Core] | Sprint 1 | 2 | sonnet | — |

---

## 21. Execution Log

[Filled during execution — tracked in progress.json]

## 22. Learnings (filled after all sprints complete)

[Compound step output]

---

## Appendix A: Port Interfaces (Code)

[Full type definitions for all port interfaces]

## Appendix B: Code Examples

[Data model entities, key architectural patterns with working code]

## Appendix C: Onboarding Flows (if B2B)

[Step-by-step flows for customer onboarding]
```

---

## Quality Checklist (verify before finalizing)

- [ ] Every ADR has 2+ rejected alternatives with WHY (not just names)
- [ ] Threat model has 8+ threats with architectural mitigations
- [ ] Access patterns defined BEFORE schema (query-first)
- [ ] Port interfaces have actual type definitions
- [ ] Roadmap has concrete deliverables (not "implement auth")
- [ ] MVP Definition of Done is observable behaviors
- [ ] Worst-case security scenario analyzed
- [ ] Each module independently implementable
- [ ] Code examples for: entities, ports, key patterns
- [ ] Compliance mapped to technical controls

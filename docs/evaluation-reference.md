# Evaluation Reference

Reference material for quality evaluation. Loaded by skills that need it, not every conversation.

## Stack Evaluation Checklist

| Layer     | Question                                                                          | Pass? |
| --------- | --------------------------------------------------------------------------------- | ----- |
| Prompt    | Did output match what was asked? Format, scope, constraints followed?             | [ ]   |
| Context   | Were all relevant docs read?                                                      | [ ]   |
| Intent    | Were tradeoffs resolved per Value Hierarchy?                                      | [ ]   |
| Judgment  | Were uncertainties documented? Assumptions flagged correctly?                     | [ ]   |
| Coherence | Does implementation follow existing patterns/ADRs? Consistent with previous work? | [ ]   |

## Diagnostic Loop

When output is unsatisfactory, diagnose WHICH layer failed:

1. Wrong format/scope/constraints? → **Prompt** issue
2. Missing/wrong information? → **Context** issue
3. Wrong tradeoffs? → **Intent** issue
4. Charged ahead on uncertain ground? → **Judgment** issue
5. Inconsistent with previous work? → **Coherence** issue

Re-enter at the failing layer. Often the fix is adding context or clarifying intent, not changing the prompt.

## Spec Self-Evaluator (run before executing any PRD)

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

## Cross-Section Validation (run after per-section evaluation passes)

Three targeted checks for internal PRD consistency. These catch contradictions that per-section evaluation cannot — each section may score well independently while conflicting with another.

1. **Architecture Decisions ↔ Security Boundaries:** Do any architecture decisions contradict security boundary mitigations? (e.g., choosing stateless JWT auth while requiring session revocation; choosing a public API gateway while security boundaries require mTLS between services)
2. **Data Model ↔ Access Patterns:** Can the data model serve the stated access patterns with the chosen technology? (e.g., schema with heavy JOINs on a database chosen for key-value access; access patterns requiring full-text search with no search index defined)
3. **Security Boundaries ↔ Sprint Decomposition:** Does every sprint that modifies a trust-boundary file include the relevant security mitigation in its spec? (e.g., a sprint creating an API endpoint without referencing the auth model; a sprint handling PII without referencing data sensitivity controls)

**How to evaluate:** For each check, identify the relevant sections in the PRD and compare them directly. If a contradiction exists, flag it with: which sections conflict, what the contradiction is, and a suggested resolution.

**Scoring:** Any cross-section contradiction is a FAIL requiring PRD revision before execution.

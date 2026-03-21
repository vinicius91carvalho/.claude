---
name: create-project
description: >
  Creates a new project from scratch with a production-grade PRD. Use this skill whenever the user
  wants to start a new project, build a new product, create a new application, or says things like
  "new project", "start a project", "build me an app", "create a new API", "I have an idea for",
  "let's build something new". This is for greenfield projects — not for adding features to existing
  ones (use /plan for that). Runs a structured discovery interview, applies battle-tested architecture
  defaults, generates a full PRD with adversarial analysis, and outputs sprint-ready specs compatible
  with /plan-build-test.
---

# Create Project: From Idea to Production-Grade PRD

This skill takes a project idea and produces a complete, sprint-ready PRD through structured
discovery and adversarial analysis. It bridges the gap between "I have an idea" and "here's
exactly what to build and how."

## How This Differs from /plan

`/plan` generates PRDs for tasks within an existing project (features, bugs, refactors).
`/create-project` generates PRDs for entirely new projects — it covers market strategy,
tech stack selection, architecture decisions, security model, data design, and
implementation roadmap. The output is compatible with the existing sprint system so
`/plan-build-test` can execute it.

## Process Overview

```
Phase 0: Discovery Interview (ask before generating anything)
Phase 1: Parallel Deep Analysis (5 virtual analysis tracks)
Phase 2: Cross-Agent Consolidation (consistency, gaps, feasibility)
Phase 3: PRD Generation (single markdown file)
Phase 4: Sprint Extraction (compatible with /plan-build-test)
```

---

## Phase 0 — Discovery Interview

Before generating anything, ask the user ALL discovery questions in a single message.
Group them clearly. Wait for answers before proceeding.

Read `~/.claude/skills/create-project/references/discovery-interview.md` for the full
question set. The questions cover four areas:

1. **Product & Market** (6 questions) — what it does, who it's for, competition, market data
2. **Technical Constraints** (4 questions) — stack, hard constraints, integrations, greenfield vs existing
3. **Scope & Timeline** (3 questions) — MVP definition, timeline, team
4. **Architecture Philosophy** (3 questions) — monolith vs modular, deployment, multi-tenancy

For any question where the user says "recommend" or doesn't have a preference, apply the
architecture defaults. Read `~/.claude/skills/create-project/references/architecture-defaults.md`
for the default decisions and their rationale.

**Important:** These defaults are battle-tested recommendations, not mandates. The user can
override any decision. When applying a default, briefly explain why it's the recommendation
so the user can make an informed choice. If the user specifies a different tech or pattern,
respect that completely — the defaults exist to reduce decision fatigue, not to force a stack.

### Handling "recommend" answers

When the user says "recommend" for the tech stack:
- Apply the defaults from architecture-defaults.md
- Present your recommendations as a summary table BEFORE proceeding
- Ask: "These are the recommended defaults based on production experience. Want to adjust any?"
- Only proceed to Phase 1 after the user confirms or adjusts

### When to suggest system-level tooling

Some tools benefit from being installed at the system level (not per-project). When the
architecture defaults suggest tools like pnpm, Docker, or LocalStack, tell the user:
"These tools work best installed globally on your system. Want me to check if they're
available and help set them up?" Only proceed with system setup if the user agrees.

---

## Phase 1 — Parallel Deep Analysis

After receiving answers, run five analysis tracks. These are "virtual agents" — structured
reasoning passes, each owning a domain. They challenge each other's assumptions, and only
surviving decisions make it to the final PRD.

### Track 1: Market & Strategy

**Input:** Product & Market answers.

1. Research the benchmark product (if named) — what they do well, where the gap is
2. Map the competitive landscape (capability vs. localization/compliance)
3. Identify the differentiator — what the benchmark does NOT do that this product MUST
4. Quantify the problem with available data (cost, waste, error rates)
5. Define positioning: "We are [benchmark] but [differentiator] for [segment]"

**Output:** Vision, Market Data, Benchmark Analysis, Competitor Map, Positioning.

### Track 2: Architecture Decisions

**Input:** Technical answers + architecture defaults.

For each major architectural decision, run the adversarial ADR process:

1. Frame the decision as a question
2. Generate 3-4 candidates with pros/cons for THIS context
3. Simulate a debate between "speed advocate" (ship fast) and "scale advocate" (build for 100x)
4. Apply elimination criteria:
   - Violates a hard constraint?
   - Creates vendor lock-in the user didn't want?
   - Requires expertise the team doesn't have?
   - Fails the "2am test" — can the team debug this at 2am?
5. Declare winner with rationale and rejected alternatives (with WHY rejected)

**Tiebreaker when speed and scale conflict:**
- Easy to change later (UI library, monitoring tool) → favor speed
- Hard to change later (database, auth model, data schema) → favor scale
- Impossible to change later (compliance model, encryption) → favor correctness

**Minimum ADRs:** Compute model, application architecture, database, auth/security,
observability, testing strategy. Add AI/agent architecture if the project uses AI/LLM.

### Track 3: Security & Compliance

**Input:** Constraints, multi-tenancy model, ADR outputs.

1. Identify every trust boundary (user → API, API → provider, tenant A → tenant B)
2. For each boundary, enumerate threats using STRIDE
3. For each threat, define an architectural mitigation (not "we'll be careful")
4. Define credential management (how secrets flow, TTL, rotation)
5. Map compliance requirements to technical controls
6. Analyze worst-case scenario: full backend compromise — blast radius and limits

**Output:** Credential Management, Threat Model table, Compliance Mapping, Worst-Case Analysis.

### Track 4: Module & Data Design

**Input:** ADR outputs, security constraints, integrations.

1. Decompose into bounded contexts / modules
2. Per module: responsibility, domain entities, ports, communication pattern
3. Design data model with access patterns FIRST, then schema
4. Define module communication (events, imports, API calls)
5. Define port interfaces for multi-provider support

**Output:** Project Structure, Module Descriptions, Data Model, Port Interfaces.

### Track 5: Implementation Planning

**Input:** All previous outputs, timeline, team.

1. Define sprint structure — each sprint is a self-contained deliverable
2. Order by dependency (foundation → core → integrations → polish)
3. Each sprint: name, duration, concrete deliverables (not vague tasks)
4. MVP "Definition of Done" as observable behaviors
5. Testing pyramid with percentages
6. Developer experience — how to go from clone to running

**Output:** Roadmap, MVP Definition of Done, Testing Pyramid, DX Plan.

---

## Phase 2 — Cross-Agent Consolidation

After all tracks complete, run a consolidation pass:

1. **Consistency:** Do ADRs contradict each other? Does the data model support the implied
   access patterns? Do security constraints conflict with DX goals?
2. **Gaps:** Any module without an owner? Security boundary without threat analysis?
   Sprint depending on something not built in a prior sprint?
3. **Feasibility:** Given team size and timeline, is the roadmap realistic? If not, propose
   cuts (what to defer post-MVP) — don't silently drop scope.
4. **Resolve contradictions:** If Track 2 chose X but Track 3's threat model makes X unsafe,
   resolve explicitly (change the ADR, add a mitigation, or accept the risk with documentation).

---

## Phase 3 — PRD Generation

Generate the final PRD. Read `~/.claude/skills/create-project/references/prd-output-template.md`
for the complete output format.

**Location:** `docs/tasks/project/feature/YYYY-MM-DD_HHmm-project-name/spec.md`

The PRD includes these sections:
1. Strategy (vision, market, benchmark, competitors, positioning)
2. Tech Stack (table with technology, rationale)
3. Architecture Decision Records (each with decision, rationale, rejected alternatives)
4. System Architecture (modules, layers, provider abstractions)
5. Data Layer (entities, access patterns — query-first)
6. Security (credentials, threat model, worst-case, compliance)
7. Observability (tooling, metrics, eval pipeline if AI)
8. Developer Experience & Testing (local dev, testing pyramid)
9. Implementation Roadmap (sprints, MVP definition of done)
10. Appendices (port interfaces code, onboarding flows)

---

## Phase 4 — Sprint Extraction

After writing `spec.md`, extract sprints using the existing sprint system:

1. Create `sprints/` subdirectory
2. For each sprint, create `sprints/NN-title.md` using `~/.claude/skills/plan/sprint-spec-template.md`
3. Determine file boundaries per sprint (files_to_create, files_to_modify, files_read_only, shared_contracts)
4. Create `progress.json` with initial state
5. Create `INVARIANTS.md` for cross-cutting concepts
6. Run `~/.claude/hooks/validate-sprint-boundaries.sh <prd-directory>` — mandatory, fix violations before proceeding
7. Tag as Build Candidate

This ensures full compatibility with `/plan-build-test` for execution.

---

## Quality Gate

The PRD is NOT complete unless:

- [ ] Every ADR has 2+ rejected alternatives with specific reasons (not just names)
- [ ] The threat model has 8+ threats with concrete mitigations (not "we'll add security")
- [ ] Data model has access patterns defined BEFORE schema (query-first design)
- [ ] Port interfaces have actual type definitions (not just descriptions)
- [ ] Roadmap has concrete deliverables per sprint (not "implement auth")
- [ ] MVP Definition of Done uses observable behaviors (not code tasks)
- [ ] Worst-case security scenario is explicitly analyzed
- [ ] Each module's responsibility is clear enough for independent implementation
- [ ] Code examples included for: data model entities, port interfaces, key patterns
- [ ] Compliance requirements mapped to specific technical controls

Run the **Spec Self-Evaluator** (same as /plan) — spawn a separate haiku agent to evaluate.
Must score 11+/14 with zero cross-section contradictions.

---

## After Completion

Tell the user:

"PRD saved at [directory-path]/. Sprint specs extracted to `sprints/`.
INVARIANTS.md created. Build Candidate tagged.

Run `/plan-build-test` to start building, or review and adjust first.

If you want to scaffold the project directory structure now, I can do that too."

Do NOT execute. This skill produces the plan only.

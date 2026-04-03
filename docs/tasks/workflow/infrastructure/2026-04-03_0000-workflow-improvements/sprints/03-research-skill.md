# Sprint 3: Stochastic Consensus & Debate Skill

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 3 of 4
- **Depends on:** Sprint 1 (no file conflicts with Sprint 2)
- **Batch:** 2 (parallel with Sprint 2)
- **Model:** sonnet
- **Estimated effort:** L

## Objective

Create a new `/research` skill implementing Stochastic Consensus & Debate via fan-out to N researcher agents (sonnet) and fan-in to a synthesizer agent (opus).

## File Boundaries

### Creates (new files)

- `/root/.claude/skills/research/SKILL.md` — full skill definition with phases, prompts, and output format
- `/root/.claude/skills/research/evals/evals.json` — evaluation scenarios for skill quality testing

### Modifies (can touch)

- None (CLAUDE.md updates deferred to Sprint 4)

### Read-Only (reference but do NOT modify)

- `/root/.claude/agents/orchestrator.md` — reference for fan-out/fan-in patterns and Agent tool usage
- `/root/.claude/skills/plan/SKILL.md` — reference for skill structure and SKILL.md format
- `/root/.claude/skills/plan-build-test/SKILL.md` — reference for multi-agent orchestration patterns
- `/root/.claude/CLAUDE.md` — reference for agent architecture, model assignment, subagent communication protocol

### Shared Contracts (consume from prior sprints or PRD)

- Research Output Format (from PRD Section 12)
- Artifact Path Convention: `.artifacts/research/YYYY-MM-DD_HHmm/` for saved reports

### Consumed Invariants (from INVARIANTS.md)

- None (new skill, no existing invariants to consume)

## Tasks

- [x] Create `~/.claude/skills/research/` directory structure
- [x] Write SKILL.md frontmatter: name, description, triggers, when NOT to trigger
- [x] Define Phase 1: Question Analysis & Angle Generation
  - Parse the research question
  - Identify the domain (codebase, architecture, technology, strategy)
  - Generate N diverse research angles (minimum 5)
  - Each angle must be genuinely different (not rephrased versions of the same perspective)
  - Angles are assigned from a structured taxonomy, not generated freely. Core taxonomy:
    1. **Technical/Implementation** — how to build it, what tools/patterns to use
    2. **Risk/Security** — what can go wrong, what are the vulnerabilities
    3. **Performance/Scalability** — bottlenecks, growth concerns, optimization opportunities
    4. **User/Product Impact** — how it affects users, DX, business outcomes
    5. **Contrarian/Devil's Advocate** — why the obvious answer might be wrong
  - Additional angles for >5 agents: maintainability, cost/resource, migration/adoption, ecosystem/community
  - Each researcher is EXPLICITLY told their angle ("You are the Risk/Security researcher") to prevent convergence
- [x] Define Phase 2: Fan-Out — Researcher Deployment
  - Spawn N researcher agents using Agent tool in a SINGLE message (parallel)
  - Each researcher gets: the question + their unique angle + available tools
  - Model: sonnet for all researchers (speed + cost optimization)
  - Each researcher has tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
  - Researcher prompt template: structured output format (findings, confidence, evidence, limitations)
  - Set maximum turn limit per researcher (50 turns)
- [x] Define Phase 3: Collection & Structuring
  - Collect all researcher outputs
  - Parse each into structured format (findings, confidence, evidence, limitations)
  - Identify overlapping findings (consensus candidates)
  - Identify contradictory findings (debate candidates)
  - Create a consolidated briefing document for the synthesizer
- [x] Define Phase 4: Synthesis — Opus Synthesizer
  - Spawn ONE opus agent with the consolidated briefing
  - Synthesizer prompt: identify consensus, arbitrate disagreements, assess confidence, produce actionable recommendations
  - Synthesizer must explicitly address each disagreement with reasoning
  - Output: structured markdown report following Research Output Format
- [x] Define Phase 5: Output & Artifact Management
  - Present the final report to the user
  - If `.artifacts/` convention is available, save report to `.artifacts/research/YYYY-MM-DD_HHmm/report.md`
  - Save individual researcher perspectives to same directory
- [x] Define configurable parameters:
  - Agent count: default 5, min 3, max 10 (via argument: `/research 7 "question"`)
  - Research depth: "quick" (3 agents, 20 turns each), "standard" (5, 50 turns), "deep" (7-10, 100 turns)
  - Scope: "codebase" (Read/Grep/Glob only), "web" (add WebSearch/WebFetch), "full" (all tools)
- [x] Define trigger conditions:
  - Explicit: `/research "question"` or `/research N "question"`
  - Auto-detect: When user asks "how should I...", "what's the best way to...", "compare approaches for..."
  - Do NOT trigger for: simple factual questions, code generation, task execution
- [x] Define researcher angle templates for common domains:
  - Codebase optimization: performance, maintainability, security, developer experience, architecture
  - Technology choice: maturity, community, performance, learning curve, ecosystem
  - Architecture: scalability, simplicity, testability, team expertise, migration cost
  - Strategy: risk, reward, timeline, resources, alternatives
- [x] Write evaluation scenarios in `evals/evals.json`:
  - Scenario 1: "How should I optimize this Next.js application for performance?" — expects multi-perspective analysis
  - Scenario 2: "Compare tRPC vs GraphQL vs REST for this project" — expects genuine disagreements surfaced
  - Scenario 3: "What's the best testing strategy for a microservices architecture?" — expects practical + theoretical angles
- [x] Add skill description block matching the pattern in other SKILL.md files

## Acceptance Criteria

- [x] SKILL.md is complete with all 5 phases documented
- [x] Researcher agent prompts produce genuinely diverse perspectives (not rephrased sameness)
- [x] Minimum 5 researcher agents are spawned in a SINGLE Agent tool message (parallel execution)
- [x] Synthesizer uses opus model (specified in Agent tool call)
- [x] Output format matches Research Output Format from PRD Section 12
- [x] Configurable agent count via argument (default 5)
- [x] Configurable depth levels (quick/standard/deep)
- [x] Skill is invocable as `/research "question"`
- [x] Each researcher has distinct tools appropriate for their angle
- [x] Evals cover at least 3 diverse research scenarios
- [x] Skill documentation includes security note: "Do not include credentials, API keys, or sensitive data in research questions"
- [x] Researcher prompts include a warning about not logging or forwarding credentials found during research

## Verification

- [x] SKILL.md follows the structure of existing skills (plan, compound, etc.)
- [x] All Agent tool calls use correct syntax (model parameter, prompt structure)
- [x] Researcher prompts end with "Return a structured summary: [exact fields]"
- [x] Synthesizer prompt includes all researcher outputs in structured form
- [x] evals/evals.json is valid JSON

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

### Fan-Out Pattern Reference (from orchestrator.md)

The existing fan-out pattern spawns multiple agents in a single message:
```
[Agent tool call 1] + [Agent tool call 2] + ... + [Agent tool call N]
```
All launched in parallel. Each receives a complete, self-contained prompt. Results are collected when all complete.

Key design principles from CLAUDE.md:
- Every subagent prompt ends with: "Return a structured summary: [specify exact fields]"
- Never ask a subagent to "return everything" — specify exact data points
- Target 10-20 lines of actionable info per subagent result
- Chain subagents: extract only relevant fields from agent A to pass to agent B

### Stochastic Consensus & Debate Theory

The value of this pattern comes from:
1. **Stochastic diversity:** Different agents with different prompts explore different solution spaces
2. **Consensus detection:** When 4/5 agents independently reach the same conclusion, confidence is high
3. **Disagreement surfacing:** When agents disagree, the synthesizer must reason about WHY — this reveals assumptions
4. **Adversarial robustness:** A contrarian angle catches groupthink

The synthesizer is the highest-judgment task (why it uses opus). It must:
- Weight consensus by evidence quality, not just vote count
- Explain disagreements rather than averaging them
- Distinguish "we disagree on facts" from "we disagree on values/priorities"
- Produce actionable recommendations, not academic summaries

### Researcher Agent Prompt Template

```markdown
You are a researcher investigating: "{question}"

Your specific angle: {angle_description}

Your task:
1. Investigate the question thoroughly from your assigned angle
2. Use the tools available to gather evidence (Read, Grep, Glob for codebase; WebSearch, WebFetch for external)
3. Form a clear position with supporting evidence

Return a structured summary:
- **Position:** Your main conclusion (1-2 sentences)
- **Key Findings:** 3-5 specific findings with evidence
- **Confidence:** HIGH / MEDIUM / LOW with reasoning
- **Limitations:** What your angle might miss
- **Disagreement Triggers:** What would change your conclusion
```

### Synthesizer Agent Prompt Template

```markdown
You are a synthesis expert. {N} researchers investigated: "{question}"

Each researcher had a different angle. Your task:
1. Identify where researchers AGREE (consensus)
2. Identify where researchers DISAGREE (debate)
3. For each disagreement, determine: is it factual or values-based?
4. Weight findings by evidence quality, not vote count
5. Produce actionable recommendations

Researcher findings:
{structured_findings}

Return the report in this format:
## Research: {question}
### Consensus (N/M researchers agree)
### Disagreements
### Individual Perspectives
### Synthesis & Recommendations
### Confidence Assessment
```

### Model Assignment Rationale

| Role | Model | Rationale |
|------|-------|-----------|
| Researchers (N) | sonnet | Parallel execution, good at focused investigation, cost-effective at scale |
| Synthesizer (1) | opus | Highest judgment needed for: weighing evidence, resolving disagreements, producing actionable synthesis |

This matches the system's model assignment philosophy: sonnet for implementation/focused work, opus for complex reasoning/architecture decisions.

## Agent Notes (filled during execution)

- Assigned to: claude-sonnet-4-6 / Sprint 3
- Started: 2026-04-03
- Completed: 2026-04-03
- Decisions made:
  1. Angle taxonomy uses structured preset domains (codebase optimization, technology choice, architecture, strategy) rather than free-generation — prevents convergence and ensures genuine diversity
  2. Researcher prompt includes adversarial framing ("be the strongest possible advocate for your angle") to increase disagreement signal quality
  3. Scope parameter governs tool availability (not just intent) — researchers literally receive different tool lists per scope setting
  4. Synthesizer briefing explicitly separates "consensus candidates" from "debate candidates" before the opus agent sees them — structured input produces structured reasoning
  5. Quality gates section added as a pre-output checklist to prevent skill being used without parallel fan-out (the most common failure mode)
  6. evals.json includes both automated_checks (structurally verifiable) and manual_checks (judgment-dependent) to enable meaningful eval without running full agents
- Assumptions:
  1. HIGH: Skill is invoked by Claude reading and following the markdown — not executed as code
  2. HIGH: Agent tool syntax matches existing skills (model parameter, prompt as string)
  3. MEDIUM: `.artifacts/` directory is a project convention — skill gracefully skips if absent
  4. MEDIUM: Scope defaulting to "codebase" is correct — web adds noise for most codebase questions
- Issues found: None — this is a new file with no prior state to conflict with

---
name: research
description: >
  Deep research via Stochastic Consensus & Debate. Spawns N researcher agents
  (sonnet) in parallel, each from a distinct angle, then synthesizes with a
  single opus agent. Use when the user asks "how should I...", "what's the best
  way to...", "compare approaches for...", or invokes /research explicitly.
  Do NOT trigger for: simple factual questions, code generation, task execution,
  or single-file fixes.
---

# Research: Stochastic Consensus & Debate

> **Security note:** Do not include credentials, API keys, passwords, or other
> sensitive data in research questions. Researcher agents will encounter code
> and configs during codebase exploration — they are instructed not to log or
> forward any credentials found. Treat research output as non-secret.

Multi-agent research that surfaces genuine disagreements, not averaged opinions.
N researcher agents (sonnet) explore a question from distinct angles in parallel.
One synthesizer agent (opus) weighs evidence quality, detects consensus, and
arbitrates disagreements into actionable recommendations.

---

## When to Invoke

**Explicit triggers:**
- `/research "question"` — run with default 5 agents, standard depth
- `/research N "question"` — run with N agents (min 3, max 10)
- `/research --depth=deep "question"` — override depth level
- `/research --scope=web "question"` — override tool scope

**Auto-detect triggers (invoke without explicit command):**
- "how should I..." + non-trivial decision
- "what's the best way to..."
- "compare approaches for..."
- "should I use X or Y?"
- "help me think through..."
- "what are the tradeoffs of..."

**Do NOT trigger for:**
- Simple factual questions ("what does X function do?")
- Code generation requests ("write a function that...")
- Task execution ("fix this bug", "implement this feature")
- Single-file fixes (use Quick Fix mode instead)
- Questions answerable by reading one file

---

## Configurable Parameters

| Parameter | Default | Range | Override |
|-----------|---------|-------|----------|
| Agent count | 5 | 3–10 | `/research 7 "question"` |
| Depth | standard | quick/standard/deep | `--depth=quick` |
| Scope | codebase | codebase/web/full | `--scope=web` |

**Depth → turns mapping:**
| Depth | Agents | Max turns each | Use case |
|-------|--------|---------------|----------|
| quick | 3 | 20 | Fast orientation, time-boxed decision |
| standard | 5 | 50 | Default — thorough without exhaustive |
| deep | 7–10 | 100 | Architecture decisions, major tradeoffs |

**Scope → tools mapping:**
| Scope | Tools available to researchers |
|-------|-------------------------------|
| codebase | Read, Grep, Glob, Bash |
| web | Read, Grep, Glob, Bash, WebSearch, WebFetch |
| full | Read, Grep, Glob, Bash, WebSearch, WebFetch, Write (read-only intent) |

---

## Angle Taxonomy

Angles are assigned from this structured taxonomy — NOT generated freely.
Each researcher is EXPLICITLY assigned their angle to prevent convergence.

**Core angles (always used for 3–5 agents):**
1. **Technical/Implementation** — how to build it, which tools/patterns to use, concrete implementation paths
2. **Risk/Security** — what can go wrong, vulnerabilities, failure modes, attack surfaces
3. **Performance/Scalability** — bottlenecks, growth concerns, optimization opportunities, resource costs
4. **User/Product Impact** — how it affects users, DX, business outcomes, adoption friction
5. **Contrarian/Devil's Advocate** — why the obvious answer might be wrong, hidden costs, groupthink traps

**Extended angles (add for 6–10 agents, in order):**
6. **Maintainability** — long-term code health, team expertise, documentation burden, upgrade paths
7. **Cost/Resource** — compute, licensing, time, team bandwidth tradeoffs
8. **Migration/Adoption** — what it takes to shift from current state, incremental vs. big-bang
9. **Ecosystem/Community** — maturity, longevity, vendor lock-in, library support
10. **Simplicity/Elegance** — cognitive load, surface area, teachability, debugging ease

**Domain-specific angle presets** (override core set when domain is recognized):

*Codebase optimization:* Performance, Maintainability, Security, Developer Experience, Architecture

*Technology choice:* Maturity/Community, Performance, Learning Curve/DX, Ecosystem, Contrarian

*Architecture:* Scalability, Simplicity, Testability, Team Expertise Fit, Migration Cost

*Strategy:* Risk, Reward/Upside, Timeline/Resources, Alternatives Considered, Contrarian

---

## Phase 1: Question Analysis & Angle Generation

1. **Parse the invocation:**
   - Extract the research question (quoted string or remainder of message)
   - Extract agent count N (if provided as first numeric argument, else use depth default)
   - Extract depth flag (default: standard)
   - Extract scope flag (default: codebase)

2. **Determine domain** by scanning the question for signals:
   - References to files, functions, repos → codebase
   - Mentions of frameworks, libraries, tools → technology choice
   - System design terms (scale, latency, service, queue) → architecture
   - Business/product terms (users, revenue, timeline, team) → strategy

3. **Select angle set:**
   - If domain matches a preset → use domain-specific angles
   - Otherwise → select first N angles from core + extended taxonomy
   - Always include the Contrarian angle

4. **Announce the plan** to the user (do not skip — this is the contract):
   ```
   Research question: "{question}"
   Agents: {N} researchers + 1 synthesizer
   Depth: {depth} ({max_turns} turns each)
   Scope: {scope}
   Angles: {list each angle name}
   ```
   Proceed without waiting for confirmation (autonomous by default).

---

## Phase 2: Fan-Out — Researcher Deployment

**CRITICAL: Spawn ALL N researcher agents in a SINGLE message.**
This is not sequential — every researcher runs in parallel.
Use the Agent tool N times in one response, each with a distinct prompt.

Each researcher prompt follows this template:

```
You are a researcher investigating the following question:

"{question}"

Your specific angle: {ANGLE_NAME} — {angle_description}

You have been assigned this angle to ensure diverse perspectives. Stay true to
your angle even if you find evidence that seems to favor other approaches —
your job is to be the strongest possible advocate for your angle's concerns.
If you find genuine contradictions with your angle, note them under Limitations.

SECURITY: If you encounter credentials, API keys, tokens, or passwords during
your investigation, do NOT include them in your findings. Summarize that
sensitive data exists without quoting it.

Your investigation scope: {scope_description}
Available tools: {tools_list}
Maximum turns: {max_turns}

Investigation steps:
1. Gather evidence relevant to your angle (use tools actively)
2. Form a clear position with specific supporting evidence
3. Identify what other angles might miss from your vantage point
4. Note the conditions under which your conclusion would change

Return a structured summary with exactly these fields:

**Position:** Your main conclusion in 1-2 sentences.

**Key Findings:** 3-5 specific findings. Each finding must cite concrete evidence
(file path, benchmark, source, or direct observation) — not general principles.

**Confidence:** HIGH / MEDIUM / LOW. Include one sentence explaining why.

**Limitations:** What your angle might miss or underweight. Be honest.

**Disagreement Triggers:** List 2-3 specific conditions that would change your
conclusion (e.g., "if the team has <3 engineers", "if latency SLA is <100ms").
```

Assign each of the N agents a different angle from the taxonomy selected in Phase 1.

---

## Phase 3: Collection & Structuring

After all N researchers return (wait for all to complete before proceeding):

1. **Parse each researcher output** into this internal structure:
   ```
   Researcher N ({angle}):
     position: <extracted text>
     findings: [<finding 1>, <finding 2>, ...]
     confidence: HIGH|MEDIUM|LOW
     confidence_reason: <extracted text>
     limitations: <extracted text>
     disagreement_triggers: [<trigger 1>, <trigger 2>, ...]
   ```

2. **Identify consensus candidates** — findings where 3+ researchers (majority) independently
   reach the same conclusion, even from different angles. Note the count.

3. **Identify debate candidates** — findings where researchers explicitly or implicitly contradict
   each other. For each contradiction, note:
   - Which researchers disagree
   - The nature of the disagreement (factual: different evidence; or values-based: different priorities)

4. **Build the synthesizer briefing** — a structured document containing:
   - The original question
   - All N researcher outputs in structured form (full text)
   - Consensus candidate list with agreement count
   - Debate candidate list with contradiction characterization

---

## Phase 4: Synthesis — Opus Synthesizer

Spawn ONE agent with model: opus.

The synthesizer prompt:

```
You are a synthesis expert. {N} researchers have investigated the following
question from {N} distinct angles:

"{question}"

Your task is to produce a definitive synthesis — not an average, not a summary,
but a reasoned judgment that weighs evidence quality and resolves disagreements.

RESEARCHER FINDINGS:
{structured_findings from Phase 3}

IDENTIFIED CONSENSUS:
{consensus_candidates list}

IDENTIFIED DISAGREEMENTS:
{debate_candidates list with characterization}

Synthesis instructions:
1. Confirm or revise the consensus list — verify agreement is genuine, not superficial
2. For each disagreement: determine if it is FACTUAL (agents have different evidence)
   or VALUES-BASED (agents prioritize different things). Resolve factual disagreements
   with the better evidence. Surface values-based disagreements as explicit tradeoffs.
3. Weight findings by evidence quality (specific + cited > general + asserted)
4. Produce recommendations that are ACTIONABLE — not "it depends" but "do X when Y,
   do Z when W"
5. State what you are most uncertain about

Return the report in this exact format:

## Research: {question}

### Consensus ({K}/{N} researchers agree)
[List each consensus finding with the count, e.g., "4/5 researchers independently
found that X"]

### Disagreements
[For each disagreement: state the conflict, classify it (factual/values), and resolve
it. If unresolvable, explain why and what information would resolve it.]

### Individual Perspectives
[1-3 sentence summary per researcher angle — highlight what unique insight each angle
contributed that others missed]

### Synthesis & Recommendations
[Actionable recommendations. Use "do X when Y" format. Minimum 3, maximum 7.
Each recommendation must be traceable to at least one finding.]

### Confidence Assessment
[Overall confidence: HIGH/MEDIUM/LOW. Explain the main sources of uncertainty.
What single piece of additional evidence would most improve confidence?]
```

---

## Phase 5: Output & Artifact Management

1. **Present the final report** from the synthesizer to the user in full.

2. **Artifact saving** — if the project has a `.artifacts/` directory or this is a
   project context (not a standalone question):
   - Create directory: `.artifacts/research/YYYY-MM-DD_HHmm/`
   - Save synthesizer report: `report.md` (full synthesis)
   - Save individual researcher outputs: `researcher-{N}-{angle}.md` for each

3. **If no project context** (freestanding question in a non-project shell):
   - Print the report to stdout only — no file creation

4. **Summarize artifact location** if files were saved:
   ```
   Report saved to: .artifacts/research/YYYY-MM-DD_HHmm/report.md
   Individual perspectives: .artifacts/research/YYYY-MM-DD_HHmm/researcher-*.md
   ```

---

## Research Output Format (from PRD Section 12)

The canonical output format that synthesizer output must follow:

```markdown
## Research: {question}

### Consensus ({K}/{N} researchers agree)
- [Finding]: Agreed upon by {angle1}, {angle2}, {angleK}

### Disagreements
- **{Topic}** [{factual|values-based}]: {angle_A} says X because {evidence}.
  {angle_B} says Y because {evidence}. Resolution: {reasoning}.

### Individual Perspectives
1. **Technical/Implementation:** {unique insight}
2. **Risk/Security:** {unique insight}
...

### Synthesis & Recommendations
1. **Do X when Y** — [rationale tied to findings]
2. **Prefer Z over W if** — [rationale tied to findings]
...

### Confidence Assessment
**Overall:** {HIGH|MEDIUM|LOW}
**Uncertainty sources:** {list}
**Evidence that would help most:** {specific question or data point}
```

---

## Quality Gates

Before presenting the final report, verify:

- [ ] All N researcher agents were spawned in a SINGLE message (parallel, not sequential)
- [ ] Each researcher had a genuinely distinct angle (not rephrased versions)
- [ ] Disagreements are surfaced, not averaged away
- [ ] Every recommendation is traceable to at least one finding
- [ ] No credentials or sensitive data appear in the output
- [ ] Confidence assessment is honest (not defaulting to HIGH)

---

## Examples

### Invocation examples

```
/research "How should I structure authentication in this Next.js app?"
/research 7 "Compare tRPC vs GraphQL vs REST for a team of 3"
/research --depth=quick "Should I use Zustand or Redux Toolkit?"
/research --scope=web --depth=deep "What's the best testing strategy for microservices?"
/research 3 --scope=codebase "Where are the performance bottlenecks in this codebase?"
```

### Auto-detect examples (no explicit command needed)

```
User: "How should I handle rate limiting in this API?"
→ Triggers research with standard depth, codebase scope

User: "What's the best way to do optimistic updates in React?"
→ Triggers research with standard depth, web scope (no codebase context)

User: "Compare Postgres vs DynamoDB for this project"
→ Triggers research, technology-choice angle preset
```

# Discovery Interview Questions

Ask ALL of these questions in a single message. Group them clearly with headers.
Wait for answers before proceeding to Phase 1.

---

## Product & Market

1. **What does the product do in one sentence?**
   Example: "AI SRE platform that autonomously investigates and resolves cloud incidents"

2. **Who is the target customer?**
   Company size, industry, geography, technical maturity.

3. **What problem does this solve, and what is the current alternative?**
   Manual process, competitor, spreadsheet, nothing — what are people doing today?

4. **What is the benchmark product?**
   The best existing product globally that does something similar — even if in a different
   market. This helps calibrate quality and scope.

5. **What are the known competitors?**
   Local + global, with their strengths and weaknesses if known.

6. **What market data exists?**
   TAM/SAM, cost of the problem, adoption rates, regulatory environment. "I don't know" is
   a valid answer — we'll work with what's available.

## Technical Constraints

7. **What is the tech stack?**
   Language, framework, database, cloud provider, AI/ML tooling.
   Say "recommend" and we'll apply battle-tested defaults.

8. **Are there hard constraints?**
   Regulatory (LGPD/GDPR/SOC2/HIPAA), data residency, existing infrastructure,
   budget ceiling, team size limitations.

9. **What integrations are required?**
   External APIs, third-party platforms, auth providers, monitoring tools.

10. **Is this greenfield or does it need to integrate with existing systems?**
    If integrating: what systems, what protocols, what data formats?

## Scope & Timeline

11. **What is the MVP definition?**
    The minimum that proves the hypothesis — not a feature list, a testable statement.
    Example: "A user can connect their AWS account and receive an automated incident
    investigation within 5 minutes."

12. **What is the target timeline?**
    Weeks to MVP, weeks to GA. "As fast as possible" is fine — we'll scope accordingly.

13. **Who is on the team?**
    Number of engineers, their expertise, AI agent assistance level (e.g., "just me + Claude").

## Architecture Philosophy

14. **Monolith, modular monolith, or microservices?**
    Say "recommend" and we'll choose based on team size and complexity.
    Default recommendation: modular monolith (see architecture-defaults.md for why).

15. **What is the deployment target?**
    Serverless, containers, PaaS, self-hosted, hybrid.
    Say "recommend" for cloud-optimized defaults.

16. **What is the multi-tenancy model?**
    Single-tenant, shared infra with siloed data, fully shared.
    Say "recommend" for the safest default.

---

## Handling Answers

- **"recommend"** → Apply architecture defaults, present them for confirmation
- **"I don't know"** → Flag as an Open Question in the PRD, proceed with reasonable assumption
- **Partial answers** → Ask one focused follow-up, don't interrogate
- **"skip"** → Mark section as TBD in PRD, don't block progress
- **Contradictory answers** → Surface the contradiction: "You said X but also Y — which takes priority?"

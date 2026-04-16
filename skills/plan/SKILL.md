---
name: plan
description: >
  Task planning and PRD generation. Auto-invoke when the user describes a new
  task, feature request, bug to fix (multi-file), refactoring need, or says
  "plan", "let's build", "I need", "implement", "create a PRD". Do NOT invoke
  for simple questions, conversations, or single-line fixes.
---

# Plan: Task Classification and PRD Generation

## Steps

1. **Classify mode** based on scope:
   - **Quick Fix:** Single-file, < 30 lines, no architectural impact → skip this skill, fix directly (no PRD needed)
   - **Standard:** Multi-file, clear scope, moderate complexity → Minimal PRD
   - **PRD + Sprint:** Large feature, multi-component, >1h of work → Full PRD

2. **If Quick Fix:** Tell the user this doesn't need a PRD — they can fix directly or use `/plan-build-test`. Done.

3. **If Standard or PRD+Sprint:**
   a. Run **Contract-First Pattern**: mirror your understanding back to user, get confirmation before proceeding
   b. Run **Correctness Discovery** (scaled by mode — see CLAUDE.md):
   - **Standard:** Audience + Verification (2 questions)
   - **PRD+Sprint:** All 6 questions (full framework in `~/.claude/skills/plan/correctness-discovery.md`)
     c. If project has a **Context Routing Table** in its CLAUDE.md → follow it. Otherwise → search for relevant docs manually
     d. Create PRD directory at `docs/tasks/<area>/<category>/YYYY-MM-DD_HHmm-name/` (create if needed)
     e. Write PRD as `spec.md` inside that directory (not as a standalone `.md` file)
     f. Fill "Context Loaded" section with what you learned from docs
     g. Write PRD using appropriate template (read from `~/.claude/skills/plan/prd-template-minimal.md` for Standard, `~/.claude/skills/plan/prd-template-full.md` for PRD+Sprint)
     h. Run **Spec Self-Evaluator** — spawn a **separate haiku agent** (different context = different perspective) to evaluate the spec:
        > Read `~/.claude/docs/on-demand/evaluation-reference.md` for the 14-point Spec Self-Evaluator checklist AND the Cross-Section Validation checks.
        > Then read the PRD at [spec.md path].
        > Phase 1: Score each of the 14 per-section criteria as PASS or FAIL with a brief reason.
        > Phase 2: Run the 3 cross-section validation checks:
        >   1. Architecture Decisions ↔ Security Boundaries (contradictions?)
        >   2. Data Model ↔ Access Patterns (technology fit?)
        >   3. Security Boundaries ↔ Sprint Decomposition (mitigations propagated?)
        > Return: total score, list of failures, cross-section contradictions, and specific suggestions to fix each.
        Must score 11+ out of 14 AND have zero cross-section contradictions to proceed. If below threshold: revise the PRD, then re-evaluate.
        Using a separate agent prevents the author from grading their own homework.

4. **If PRD+Sprint — Extract Sprint Specs, INVARIANTS.md, and Build Candidate (MANDATORY):**

   Sprint extraction protocol: `~/.claude/skills/plan/sprint-extraction-protocol.md`

   Summary: create `sprints/NN-title.md` per sprint (self-contained, includes file boundaries)
   → create `progress.json` (schema in protocol doc) → create `INVARIANTS.md` (machine-verifiable
   contracts for cross-cutting concepts) → run `bash ~/.claude/hooks/scripts/validate-sprint-boundaries.sh <prd-dir>`
   → tag Build Candidate (`git tag "build-candidate/<prd-name>"`). Maximum 5 sprints per PRD.

5. Tell the user: "PRD saved at [directory-path]/. Sprint specs extracted to `sprints/`. INVARIANTS.md created. Build Candidate tagged. **Stop this session.** Open a fresh session and run `/plan-build-test` to execute — do NOT continue in this window. Keeping planning and execution in separate context windows prevents `/compact` churn during the build."

6. **Do NOT execute. Do NOT invoke `/plan-build-test` from this session**, even if the user's next message asks for it — tell them to start a new session instead (context hygiene). This skill produces the plan only.

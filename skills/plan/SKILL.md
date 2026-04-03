---
name: plan
description: >
  Task planning and PRD generation. Auto-invoke when the user describes a new
  task, feature request, bug to fix (multi-file), refactoring need, or says
  "plan", "let's build", "I need", "implement", "create a PRD". Do NOT invoke
  for simple questions, conversations, or single-line fixes.
context: fork
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
        > Read `~/.claude/docs/evaluation-reference.md` for the 14-point Spec Self-Evaluator checklist AND the Cross-Section Validation checks.
        > Then read the PRD at [spec.md path].
        > Phase 1: Score each of the 14 per-section criteria as PASS or FAIL with a brief reason.
        > Phase 2: Run the 3 cross-section validation checks:
        >   1. Architecture Decisions ↔ Security Boundaries (contradictions?)
        >   2. Data Model ↔ Access Patterns (technology fit?)
        >   3. Security Boundaries ↔ Sprint Decomposition (mitigations propagated?)
        > Return: total score, list of failures, cross-section contradictions, and specific suggestions to fix each.
        Must score 11+ out of 14 AND have zero cross-section contradictions to proceed. If below threshold: revise the PRD, then re-evaluate.
        Using a separate agent prevents the author from grading their own homework.

4. **If PRD+Sprint — Extract Sprint Specs (MANDATORY):**

   After writing `spec.md`, extract each sprint into its own file. This is the critical step that enables context isolation.

   a. Create `sprints/` subdirectory inside the PRD directory
   b. For each sprint in the Sprint Decomposition:
   - Create `sprints/NN-title.md` using the sprint spec template (`~/.claude/skills/plan/sprint-spec-template.md`)
   - Copy the sprint's objective, tasks, acceptance criteria, verification into the spec file
   - **Determine file boundaries** by analyzing the tasks:
     - `files_to_create`: new files this sprint builds
     - `files_to_modify`: existing files this sprint can touch
     - `files_read_only`: files to reference but NOT modify
     - `shared_contracts`: interfaces/types from the PRD's Shared Contracts section
   - **Validate no file conflicts**: if two sprints in the same batch both list a file under `files_to_modify` or `files_to_create`, they CANNOT be parallel — move one to a later batch
   - Include relevant context from the PRD (design details, API specs) but NOT the entire PRD
     c. Create `progress.json` with initial state:

   ```json
   {
     "prd": "spec.md",
     "created": "[ISO timestamp]",
     "sprints": [
       {
         "id": 1,
         "file": "sprints/01-title.md",
         "title": "[Sprint title]",
         "status": "not_started",
         "depends_on": [],
         "batch": 1,
         "model": "sonnet",
         "branch": null,
         "merged": false
       }
     ]
   }
   ```

   d. **Validate sprint count**: maximum 5 sprints. If >5, the scope is too large — split into separate PRDs by independent deliverable (test: "could these be built by teams who never talk?"). If they share files, keep together and reduce scope.

5. **Sprint boundary validation (deterministic — MANDATORY after step 4):**

   Run `~/.claude/hooks/validate-sprint-boundaries.sh <prd-directory>` to verify:
   - No file appears in `files_to_create`/`files_to_modify` in two parallel sprints (same batch)
   - Every `files_to_modify` file either exists or is created by an earlier sprint
   - Sprint dependency graph has no cycles
   - INVARIANTS.md verify commands reference reachable files

   If validation fails: restructure batches/dependencies to fix violations, then re-run.
   `files_read_only` can overlap freely — reading is safe.

6. **If PRD+Sprint — Create INVARIANTS.md (MANDATORY):**

   After extracting sprint specs, identify every concept that is defined in one bounded
   context and consumed by others. Create `INVARIANTS.md` in the PRD directory with
   machine-verifiable contracts for each cross-cutting concept.

   For each shared concept, define:
   - **Owner:** Which bounded context defines this concept
   - **Preconditions:** What consumers must satisfy (caller's obligation)
   - **Postconditions:** What the owner guarantees (provider's guarantee)
   - **Invariants:** What must always hold across all contexts
   - **Verify:** Shell command that exits 0 if invariant holds
   - **Fix:** How to resolve if violated

   Common concepts to register: permission string formats, entity status vocabularies,
   error code families, event type definitions, routing identifiers, API contract shapes,
   shared type definitions.

   **Dependency direction:** If A depends on B, B owns the contract. This prevents
   consumers from independently inventing expectations about provider behavior.

   Copy the project-level INVARIANTS.md to the project root if one doesn't exist yet.

7. **Tag Build Candidate:**

   After all artifacts are written (spec.md, sprint specs, progress.json, INVARIANTS.md),
   tag the current state as a Build Candidate — a formal gate declaring "this specification
   is complete enough to build from."

   ```bash
   git add docs/tasks/<area>/<category>/<prd-dir>/
   git commit -m "docs: Build Candidate for <prd-name>"
   git tag "build-candidate/<prd-name>"
   ```

   This is analogous to a release candidate, but for the design phase. The tag is the
   contract: "everything needed to build is specified. Implementation can begin."

8. Tell the user: "PRD saved at [directory-path]/. Sprint specs extracted to `sprints/`. INVARIANTS.md created. Build Candidate tagged. Run `/plan-build-test` to execute, or review and adjust first."

9. **Do NOT execute.** This skill produces the plan only.

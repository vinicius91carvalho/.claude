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
     d. **Determine PRD location (READ CAREFULLY — common source of bugs):**

        - The PRD directory MUST live at the **repo root**, i.e. inside the directory returned by `git rev-parse --show-toplevel`. NEVER nest a PRD inside `apps/`, `packages/`, `services/`, or any sub-app subfolder — even if the changes are scoped to one app. Existing PRDs at `<repo-root>/docs/tasks/` are the convention; mirror them.
        - The full path is: `<repo-root>/docs/tasks/<area>/<category>/<dirname>/`.
        - **`<area>` and `<category>`** come from the project's CLAUDE.md `## Task File Location` (or `## Execution Config`) section. **Read that section first** to learn the allowed values — do NOT invent a new area or category. Existing siblings under `docs/tasks/<area>/` are the source of truth.
        - **`<dirname>` format is exactly `YYYY-MM-DD_HHmm-slug`.** The separator between the date and time is an **UNDERSCORE `_`**, NOT a hyphen. Common typo to avoid:
          - Right: `2026-04-27_1530-integration-hardening`
          - Wrong: `2026-04-27-1530-integration-hardening`
        - **Cross-repo PRDs (sibling repos in a parent monorepo-ish folder):** If the change spans multiple sibling repos, the PRD goes in the **first repo of the deploy chain** per the parent CLAUDE.md's deploy-order section. Sprints in that PRD may declare files from the other repos in their `files_to_modify` / `files_to_create` boundaries — but the PRD has exactly one home directory and one `progress.json`. Do NOT split a single PRD into duplicate copies under each repo's `docs/tasks/`.
        - **Verify before continuing:** before writing `spec.md`, echo the absolute path you're about to create and check that (i) it begins with `<repo-root>/docs/tasks/`, (ii) `<area>` and `<category>` exist in the project's CLAUDE.md task-file conventions, and (iii) the `_` is between date and time. If any check fails, recompute the path before any file is written.
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
   → create `progress.json` with v2 schema and `owner_session_id: null` (see protocol doc)
   → create `INVARIANTS.md` → run `bash ~/.claude/hooks/scripts/validate-sprint-boundaries.sh <prd-dir>`
   → tag Build Candidate (`git tag "build-candidate/<prd-name>"`). Maximum 5 sprints per PRD.

   **Do NOT write an active-plan pointer here.** The planning session is not the executing session — the standard handoff is `/plan` ends → user opens a fresh session → `/plan-build-test` claims the plan via `bind-plan.sh`. Writing a pointer at plan time would mark the planner as the live executor and cause the next session's `/plan-build-test` to refuse the plan as "owned by a peer." Leave `owner_session_id: null` and let the executor bind itself.

   **HARD GATE — run this self-check from inside the PRD directory before declaring planning done. Every line must print `OK`. If any prints `FAIL`, fix it and re-run the whole check before moving on:**

   ```bash
   PRD_NAME=$(basename "$PWD")
   [ -f spec.md ]                                            && echo "OK spec.md"               || echo "FAIL spec.md"
   [ -d sprints ] && [ "$(ls sprints/*.md 2>/dev/null | wc -l)" -gt 0 ] && echo "OK sprints/"             || echo "FAIL sprints/ (no NN-title.md files)"
   [ -f progress.json ] && python3 -c "import json,sys; d=json.load(open('progress.json')); s=d.get('sprints',[]); assert d.get('schema_version')==2 and d.get('owner_session_id') is None and s and all(x.get('status')=='not_started' for x in s)" 2>/dev/null && echo "OK progress.json (v2, unbound)" || echo "FAIL progress.json (missing or bad v2 schema/statuses, or owner_session_id is not null — must be null at plan time so the executor session can bind itself)"
   [ -f INVARIANTS.md ]                                      && echo "OK INVARIANTS.md"         || echo "FAIL INVARIANTS.md"
   bash ~/.claude/hooks/scripts/validate-sprint-boundaries.sh "$PWD" >/dev/null 2>&1 && echo "OK validate-sprint-boundaries" || echo "FAIL validate-sprint-boundaries (run it manually to see violations)"
   [ ! -f "$HOME/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json" ] && echo "OK no active-plan pointer (correct — pointer is written by the executor session, not here)" || echo "FAIL stray active-plan pointer (delete it: rm \"\$HOME/.claude/state/active-plan-\${CLAUDE_SESSION_ID}.json\")"
   git -C "$(git rev-parse --show-toplevel)" tag -l "build-candidate/$PRD_NAME" | grep -q . && echo "OK build-candidate tag" || echo "FAIL build-candidate tag (not created)"
   ```

   **The build-candidate tag is the handshake to `/plan-build-test`.** It identifies that a PRD exists at this commit. Ownership is established only when the first `/plan-build-test` session runs `bind-plan.sh`. If the tag step fails because the PRD isn't committed yet, commit `docs/tasks/<area>/<category>/<prd-dir>/` first (`git add` + `git commit -m "docs: Build Candidate for $PRD_NAME"`) — the tag must point at a real commit.

5. Tell the user: "PRD saved at [absolute-directory-path]/. Sprint specs extracted to `sprints/` (N files). `INVARIANTS.md` created. `progress.json` initialized with all sprints `not_started` and `owner_session_id: null` (unbound — the first `/plan-build-test` session will claim it). Build Candidate tagged as `build-candidate/<prd-name>`. **Stop this session.** Open a fresh session and run `/plan-build-test` — it will discover this plan, bind itself as the executor, and start the build. Keeping planning and execution in separate sessions prevents `/compact` churn during the build."

6. **Do NOT execute. Do NOT invoke `/plan-build-test` from this session**, even if the user's next message asks for it — tell them to start a new session instead (context hygiene). This skill produces the plan only.

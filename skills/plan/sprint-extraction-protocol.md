# Sprint Extraction Protocol

**Canonical definition. Referenced by:** `skills/plan/SKILL.md` Step 4, `skills/create-project/SKILL.md` Phase 4.

This protocol converts a finished `spec.md` into a set of sprint spec files, a `progress.json`,
an `INVARIANTS.md`, and a Build Candidate git tag. It is mandatory for all PRD+Sprint tasks.

---

## Step 1: Create Sprint Spec Files

1. Create a `sprints/` subdirectory inside the PRD directory.
2. For each sprint in the PRD's Sprint Decomposition, create `sprints/NN-title.md` using
   the sprint spec template at `~/.claude/skills/plan/sprint-spec-template.md`.
3. Each sprint spec must include:
   - Sprint objective (copied from the PRD, self-contained — no PRD lookup needed during execution)
   - All tasks as checkboxes (`- [ ]`)
   - All acceptance criteria and their verification commands
   - Relevant design details, API specs, or data model excerpts from the PRD
   - **File boundaries** (see Step 2) — mandatory for worktree isolation
   - Agent Notes section (left blank — sprint-executor fills this in during execution)

**Include enough context from the PRD so the sprint-executor never needs to read `spec.md`
during execution. The sprint spec file IS the executor's complete information source.**

---

## Step 2: Determine File Boundaries (per sprint)

Analyze each sprint's tasks and declare:

```
files_to_create:   new files this sprint builds (will not exist on disk yet)
files_to_modify:   existing files this sprint is allowed to change
files_read_only:   files to reference but NOT modify (safe to overlap across sprints)
shared_contracts:  interfaces/types from the PRD's Shared Contracts section that this sprint consumes
```

**Import path verification (MANDATORY):** Before writing import paths in sprint specs,
read the target package's `package.json` `exports` field to verify the actual export path.
Directory structure does NOT always match export paths (e.g., `domain/constants/integrations`
may export as just `constants`). Never assume — verify. For monorepo shared packages, run:
`cat packages/<pkg>/package.json | grep -A 20 '"exports"'`

**Conflict rule:** If two sprints in the SAME batch both list the same file under
`files_to_modify` or `files_to_create`, they CANNOT run in parallel — move one sprint
to a later batch (or make it a sequential dependency). `files_read_only` may overlap
freely across all sprints.

---

## Step 3: Create progress.json

Create `progress.json` in the PRD directory with this exact schema (v2 — supports concurrent multi-session execution):

```json
{
  "prd": "spec.md",
  "created": "[ISO 8601 timestamp, e.g. 2024-01-15T14:30:00Z]",

  "schema_version": 2,
  "owner_session_id": null,
  "owner_created_at": "[same as created]",
  "adopted_by": [],
  "prd_slug": "[basename of the PRD directory]",

  "sprints": [
    {
      "id": 1,
      "file": "sprints/01-title.md",
      "title": "[Sprint title matching the filename]",
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

**Plan time vs. execution time.** `owner_session_id` is intentionally **null at plan time** — the planning session is not the executing session. The `/plan` workflow ends with the user starting a fresh session (clean context for the build), and the first `/plan-build-test` to pick the plan up binds itself via `bind-plan.sh`. This avoids the dead-end where a fresh post-`/plan` session would otherwise see the plan as "owned by some other session" and refuse to touch it. Per-sprint claim fields (`claimed_by_session`, `claimed_at`, `claim_heartbeat_at`) are added later still, at sprint-claim time by `claim-sprint.sh`. The `prd_slug` field, set at plan time, is what scopes branches and worktrees.

**Field reference:**

| Field              | Type            | Values / Notes                                                              |
|--------------------|-----------------|-----------------------------------------------------------------------------|
| `schema_version`   | integer         | `2` — required for new plans. Plans without this field are legacy v1.       |
| `owner_session_id` | string \| null  | `null` at plan time. Set to `$CLAUDE_SESSION_ID` by `bind-plan.sh` when the first `/plan-build-test` claims the plan. `/adopt-plan` does NOT rewrite this — it appends to `adopted_by[]` instead. |
| `owner_created_at` | string          | ISO-8601 timestamp; usually equals `created`                                |
| `adopted_by`       | array           | Append-only audit trail. First entry has `reason: "first-executor-bind"` (from `bind-plan.sh`); later entries have `reason: "migrate-adopt"` or similar (from `/adopt-plan` and stale-claim prompts). |
| `prd_slug`         | string          | `basename` of the PRD directory; used in branch + worktree namespacing      |
| `id`               | integer       | Sequential from 1                                                           |
| `file`             | string        | Relative path from PRD directory to the sprint spec file                    |
| `title`            | string        | Human-readable sprint title, matches the filename slug                      |
| `status`           | string enum   | `"not_started"` `"in_progress"` `"complete"` `"blocked"`                    |
| `depends_on`       | integer[]     | IDs of sprints that must complete before this one starts (empty = no deps)  |
| `batch`            | integer       | Sprints with the same batch number can run in parallel (if no file overlap) |
| `model`            | string        | `"haiku"` `"sonnet"` `"opus"` — per Model Assignment Matrix in CLAUDE.md    |
| `branch`           | string\|null  | Git branch name — filled in by orchestrator during execution                |
| `merged`           | boolean       | Whether the branch has been merged — filled in by orchestrator              |

**Sprint count limit:** Maximum 5 sprints per PRD. If more than 5 are needed, the scope is
too large — split into separate PRDs by independent deliverable. Test: "could these be built
by two teams who never talk?" If yes → split. If they share files → keep together and reduce scope.

---

## Step 4: Create INVARIANTS.md

After extracting sprint specs, identify every concept that is defined in one bounded context
and consumed by another. Create `INVARIANTS.md` in the PRD directory.

For each shared concept, define one entry using this format:

```markdown
## [Concept Name]
- **Owner:** [bounded context / module that defines this concept]
- **Preconditions:** [what consumers must satisfy before using this — caller's obligation]
- **Postconditions:** [what the owner guarantees after execution — provider's guarantee]
- **Invariants:** [what must always hold across all contexts]
- **Verify:** `shell command that exits 0 if invariant holds`
- **Fix:** [how to resolve if the invariant is violated]
```

**Common concepts to register:** permission string formats, entity status vocabularies,
error code families, event type definitions, routing identifiers, API contract shapes,
shared type definitions, database table/column names used by multiple modules.

**Dependency direction:** If module A depends on module B, B owns the contract. Consumers
declare which contracts they consume and must satisfy the listed preconditions.

**Cascading invariants:** If a project-level `INVARIANTS.md` does not yet exist at the
project root, copy this file there. The `check-invariants.sh` PostToolUse hook walks from
the edited file up to the project root, checking all levels.

---

## Step 5: Run Sprint Boundary Validation (MANDATORY)

```bash
bash ~/.claude/hooks/scripts/validate-sprint-boundaries.sh <prd-directory>
```

This script verifies:
- No file appears in `files_to_create` or `files_to_modify` in two parallel sprints (same batch)
- Every file listed in `files_to_modify` either already exists on disk OR is created by an
  earlier sprint in the dependency chain
- The sprint dependency graph has no cycles
- `INVARIANTS.md` verify commands reference reachable files

**If validation fails:** restructure batches and/or dependency links to fix violations,
then re-run the validation. Do NOT proceed to Step 6 while violations exist.

`files_read_only` entries can overlap freely — reading the same file from multiple sprints
is always safe.

---

## Step 6: Tag the Build Candidate

After all artifacts are written (`spec.md`, sprint specs, `progress.json`, `INVARIANTS.md`):

```bash
git add docs/tasks/<area>/<category>/<prd-dir>/
git commit -m "docs: Build Candidate for <prd-name>"
git tag "build-candidate/<prd-name>"
```

The Build Candidate is the formal gate between planning and execution — analogous to a
release candidate, but for the design phase. The tag is the contract: "everything needed
to build is specified; implementation can begin."

`/plan-build-test` verifies the Build Candidate tag exists before starting execution.

---

## Completion Checklist

After running this protocol, all of the following must be true:

- [ ] `sprints/` directory exists with one `NN-title.md` file per sprint
- [ ] Each sprint spec is self-contained (no lookup of `spec.md` needed during execution)
- [ ] File boundaries declared in every sprint spec, with no parallel-batch conflicts
- [ ] `progress.json` exists with correct schema, `owner_session_id: null`, and `status: "not_started"` for all sprints
- [ ] `INVARIANTS.md` exists with entries for all cross-cutting shared concepts
- [ ] `validate-sprint-boundaries.sh` exits 0 (no violations)
- [ ] Build Candidate tag created and visible in `git tag`
- [ ] Sprint count ≤ 5 (or PRD has been split)

# Sprint 2: Proposer — Clustering + Review-Dir + Regression-Test Generation

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 2 of 3
- **Depends on:** None
- **Batch:** 1 (parallel with Sprint 1)
- **Model:** sonnet
- **Estimated effort:** M

## Objective

Build a Python script that consumes friction-events JSONL (the contract Sprint 1 produces), clusters by category + fingerprint, generates the review-directory layout (proposal.md, diff.patch, regression-tests/, summary.txt), and refuses to emit single-event clusters.

## File Boundaries

### Creates (new files)

- `/root/.claude/scripts/skill-evolve/propose-edits.py` — main proposer; reads friction-events JSONL from stdin or `--input <path>`, writes review-directory contents to `--out <dir>` (caller-provided path)
- `/root/.claude/scripts/skill-evolve/cluster.py` — importable clustering module (category + fingerprint bucketing, edit-distance merge for near-duplicates within 10%)
- `/root/.claude/scripts/skill-evolve/regression-template.sh` — shell-script template that generated `test-skill-evolve-<cluster>.sh` files inherit from; sources the same `lib/` paths the existing `~/.claude/hooks/tests/test-*.sh` use

### Modifies (can touch)

- (none — Sprint 2 only creates new scripts; the proposer writes ONLY into the caller-provided out directory)

### Read-Only (reference but do NOT modify)

- `/root/.claude/hooks/tests/test-block-dangerous.sh` and other `test-*.sh` — for shell-script style reference (assertion helpers, `set -uo pipefail` conventions, lib/ sourcing pattern)
- `/root/.claude/skills/` and `/root/.claude/rules/` — to identify which file a proposed edit should target (path-only inspection; no content modification)
- `../spec.md` — PRD context

### Shared Contracts (consume from prior sprints or PRD)

- Friction-event JSONL schema (PRD Section 11) — Sprint 1 produces, Sprint 2 consumes
- Friction taxonomy (PRD Section 12) — Sprint 1 owns, Sprint 2 consumes by category
- Token-redaction module from Sprint 1 (`redact.py`) — Sprint 2 imports and re-applies before any write into the review directory (defense in depth)
- Review-directory layout (PRD Section 12) — Sprint 2 owns the layout; Sprint 3 consumes by reading the same paths
- Run-ID format (PRD Section 12) — `<unix-timestamp>-<random4>` — Sprint 2 receives via `--out` argument; Sprint 3 generates and passes

### Consumed Invariants (from INVARIANTS.md)

- `Single-event clusters are not emitted as proposals` — this sprint OWNS the gate; clusters with <2 events are dropped silently from proposal.md
- `Skill never writes outside the review directory or evolution/` — this sprint receives `--out <dir>` from the caller and writes only there; the script itself MUST refuse to run if `--out` doesn't begin with the documented prefix
- Verify: `python3 /root/.claude/scripts/skill-evolve/propose-edits.py --out /tmp/foo --input /dev/null 2>&1 | grep -q 'refusing.*--out'` (refuses non-prefixed out path)
- Verify: synthesize a 1-event JSONL fixture, run the proposer, confirm proposal.md has zero cluster sections

## Tasks

- [ ] Write `cluster.py`: function `cluster_events(events: list[dict]) -> list[Cluster]`. Bucket by `(category, fingerprint)`. Merge buckets whose fingerprints differ by ≤10% Levenshtein distance. Return only clusters with ≥2 events. Each Cluster has `category`, `representative_quote`, `events: list[dict]`, `slug` (kebab-case derived from quote), `confidence` (`high` if all events fingerprint-identical, `medium` if any near-duplicate merging happened, `low` if cluster size is exactly 2).
- [ ] Write `regression-template.sh`: a parameterized bash test scaffold. Placeholders `__CLUSTER_SLUG__`, `__CATEGORY__`, `__EVIDENCE_FINGERPRINT__`, `__GATE_COMMAND__` get substituted by the proposer when generating each test file. The scaffold sources `~/.claude/hooks/lib/stop-guard.sh`-style helpers if available, sets `set -uo pipefail`, defines `assert_eq` if not sourced, and exits 0/1 by convention.
- [ ] Write `propose-edits.py` main: parse `--input` (default stdin) and `--out <dir>` (REQUIRED, must begin with `~/.claude/docs/skill-evolution-proposals/` or `/root/.claude/docs/skill-evolution-proposals/` after expansion). Refuse otherwise. Read events. Cluster. For each surviving cluster:
  - Determine target file: scan `~/.claude/skills/*/SKILL.md`, `~/.claude/rules/*.md`, `~/.claude/CLAUDE.md` and pick the most-likely target by category-to-file heuristic (e.g. `env-incompat` → `~/.claude/rules/environment.md`; `refusal` → most-recently-mentioned skill SKILL.md from the evidence; default to `~/.claude/CLAUDE.md`).
  - Draft a proposed edit as a markdown patch hunk (target file path + before/after blocks).
  - Generate a regression test from the template with the cluster's evidence as the gate.
  - Try to generate `diff.patch` via `git diff` (in a tmp checkout). If `git apply --check` against current HEAD fails, fall back to inline code blocks in proposal.md and append a `[PATCH GENERATION FAILED]` note.
- [ ] Write `proposal.md` with one `## Cluster: <slug>` section per surviving cluster. Each section has: `**Category:**`, `**Confidence:**`, `**Evidence:** <count> events from <session-list>`, fenced quote(s) of representative evidence (re-redacted), `**Proposed edit target:** <path>`, `**Proposed change:**` (summary), `**Regression test:**` (file path inside review dir).
- [ ] Write `summary.txt`: a single line "Proposed N clusters; review at `<out-dir>/proposal.md`" — Sprint 3 reads this and prints to stdout as the orchestrator's last line.
- [ ] Add `--selftest` mode that runs an inline 4-cluster fixture end-to-end against a tmp out-dir and asserts the layout matches PRD Section 12 (proposal.md, diff.patch attempted, friction-events.jsonl copied through, regression-tests/ has one file per cluster, summary.txt is one line).

## Acceptance Criteria

- [ ] AC1: `python3 /root/.claude/scripts/skill-evolve/propose-edits.py --selftest` exits 0.
- [ ] AC2: Running with `--out /tmp/anything` (not under the proposals prefix) exits non-zero with a `refusing` message on stderr.
- [ ] AC3: A fixture JSONL containing 1 event produces a review directory with `proposal.md` whose body says "no clusters" (single-event events are dropped per the invariant), and exits 0 (not an error — empty result is valid).
- [ ] AC4: A fixture JSONL containing 4 events forming 2 clusters (2+2) produces `proposal.md` with exactly 2 `## Cluster:` sections.
- [ ] AC5: Each generated `regression-tests/test-skill-evolve-<slug>.sh` is executable (`chmod +x`), starts with `#!/usr/bin/env bash`, and is structurally similar enough to the existing `test-*.sh` files that copying it to `~/.claude/hooks/tests/` would be auto-discovered by `run-all.sh`.
- [ ] AC6: When `git apply --check` fails for a generated patch, the proposer does NOT silently drop the proposal — proposal.md retains the cluster section with inline code blocks and the `[PATCH GENERATION FAILED]` marker.
- [ ] AC7: All evidence quotes in proposal.md are passed through `redact.py` before write — verifiable by injecting a fixture event with a fake token and confirming the token does NOT appear in the output proposal.md.

## Verification

- [ ] Build passes (N/A — Python)
- [ ] Lint passes — `python3 -m py_compile /root/.claude/scripts/skill-evolve/{propose-edits,cluster}.py` exits 0
- [ ] Type-check passes (N/A — type hints encouraged, not enforced)
- [ ] Sprint-specific tests pass — `--selftest` exits 0; AC2, AC3, AC6, AC7 fixtures all pass when run.

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

The proposer is the more judgment-heavy of the two scripts but is still deterministic — it does NOT call out to LLMs. Cluster targeting is heuristic (category-to-file lookup table); the user reviews the target choice in proposal.md.

The `--out` path guard is a defense-in-depth measure beyond Sprint 3's own SKILL.md guards. Even if Sprint 3 (or some misguided future caller) tries to point the proposer at `/root/.claude/skills/`, the proposer refuses. This makes the safety boundary structural at TWO layers, not one.

Generated regression tests are dropped into the review directory's `regression-tests/` subdirectory, NOT directly into `~/.claude/hooks/tests/`. The user moves them in after reviewing — that move is what auto-wires them via the existing `test-*.sh` glob in `run-all.sh`. This is the "force a manual move so the user notices generator misfires" decision from PRD Section 9.

The `confidence` field per cluster matters for the user's review prioritization. `high` clusters are byte-identical recurrences (strong signal). `medium` clusters merge near-duplicates. `low` clusters are size-2-and-merged — the user might want to wait for more occurrences before applying. Marking confidence in proposal.md sets the user's expectations.

Patch generation may legitimately fail when the target file structure doesn't match the proposer's assumptions (e.g. the SKILL.md was reorganized). Falling back to inline code blocks preserves the value of the proposal — the user can still translate the proposed change manually, even if the auto-patch path is broken.

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

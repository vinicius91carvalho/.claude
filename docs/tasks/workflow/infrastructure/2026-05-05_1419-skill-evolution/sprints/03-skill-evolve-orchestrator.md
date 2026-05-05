# Sprint 3: `/skill-evolve` SKILL.md — Orchestration + Safety Guards

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 3 of 3
- **Depends on:** Sprint 1 (miner), Sprint 2 (proposer)
- **Batch:** 2 (sequential after Batch 1)
- **Model:** sonnet
- **Estimated effort:** S

## Objective

Create `/root/.claude/skills/skill-evolve/SKILL.md` — the user-invoked orchestrator that runs miner → proposer with pre-flight, run-id namespacing, structural safety guards on every Write/Edit, and a one-line summary pointing the user at the review directory.

## File Boundaries

### Creates (new files)

- `/root/.claude/skills/skill-evolve/SKILL.md` — the new skill file with frontmatter + Phase 0a (sanity check) + Phase 0b (pre-flight: transcript freshness) + Phase 1 (run-id + out-dir creation) + Phase 2 (invoke miner) + Phase 3 (invoke proposer) + Phase 4 (read summary.txt and emit) + Standards section

### Modifies (can touch)

- (none — Sprint 3 only creates one new SKILL.md; Sprints 1 & 2 produce the scripts this skill orchestrates)

### Read-Only (reference but do NOT modify)

- `/root/.claude/scripts/skill-evolve/mine-transcripts.py` — invoke via Bash; do not edit
- `/root/.claude/scripts/skill-evolve/propose-edits.py` — invoke via Bash; do not edit
- `/root/.claude/skills/plan-build-test/SKILL.md` — for the Phase 0a sanity-check pattern (adapt for cwd-agnostic mode)
- `/root/.claude/skills/autonomous-staging/SKILL.md` — for the run-id generation pattern (`<unix>-<random4>`)
- `/root/.claude/skills/verify-staging/SKILL.md` — for the read-only-skill convention reference
- `../spec.md` — PRD context

### Shared Contracts (consume from prior sprints or PRD)

- Run-ID format (PRD Section 12): `<unix-timestamp>-<random4-lowercase>`
- Review-directory layout (PRD Section 12): see PRD; this skill creates the parent directory and passes `--out` to the proposer
- Friction-event JSONL schema (PRD Section 11): this skill does NOT parse it; it only chains the miner to the proposer via shell pipe
- Summary.txt single-line format (Sprint 2 owns the format; Sprint 3 reads and prints)

### Consumed Invariants (from INVARIANTS.md)

- `Skill never writes outside the review directory or evolution/` — this sprint OWNS the SKILL.md and is the primary surface where the invariant must hold
- Verify: `grep -E '(Write|Edit)' /root/.claude/skills/skill-evolve/SKILL.md | grep -vE 'skill-evolution-proposals|evolution/' | wc -l | grep -q '^0$'`
- `Regression tests are unmoved` — this sprint MUST NOT contain any `cp` or `mv` instruction targeting `~/.claude/hooks/tests/`
- Verify: `grep -E '(cp|mv).*hooks/tests' /root/.claude/skills/skill-evolve/SKILL.md | wc -l | grep -q '^0$'`

## Tasks

- [ ] Create `/root/.claude/skills/skill-evolve/` directory and `SKILL.md` file inside it.
- [ ] Frontmatter: `name: skill-evolve`, `description:` two-sentence pitch covering "mines transcripts for recurring friction" + "emits review directory, never modifies skill files directly". Trigger words: "evolve skills", "mine my transcripts", "what friction patterns am I hitting", "propose skill improvements".
- [ ] Phase 0a (working-directory sanity, cwd-agnostic variant): unlike `/plan-build-test` Phase 0a, this skill does NOT require a git repo cwd. It only requires `~/.claude/projects/` to exist. Write a small bash check: `[ -d "$HOME/.claude/projects" ] || { echo "BLOCKED: ~/.claude/projects does not exist"; exit 1; }`.
- [ ] Phase 0b (pre-flight transcript freshness): count `find ~/.claude/projects -name '*.jsonl' -mtime -30 | wc -l`. If 0, exit cleanly with "no transcripts in last 30 days — nothing to mine" message in <30 seconds (AC7).
- [ ] Phase 1 (run-id + out-dir): generate `RUN_ID="$(date +%s)-$(head /dev/urandom | tr -dc a-z0-9 | head -c4)"`. Compute `OUT_DIR="$HOME/.claude/docs/skill-evolution-proposals/$RUN_ID"`. `mkdir -p "$OUT_DIR/regression-tests"`. Record start timestamp.
- [ ] Phase 2 (invoke miner): `python3 ~/.claude/scripts/skill-evolve/mine-transcripts.py --all --since "$(date -d '30 days ago' --iso-8601=seconds)" > "$OUT_DIR/friction-events.jsonl"`. Capture exit code; on non-zero, emit a partial report and exit non-zero.
- [ ] Phase 3 (invoke proposer): `python3 ~/.claude/scripts/skill-evolve/propose-edits.py --input "$OUT_DIR/friction-events.jsonl" --out "$OUT_DIR"`. Capture exit code.
- [ ] Phase 4 (summary): `cat "$OUT_DIR/summary.txt"` → print to stdout as the LAST line. Compute total wall-clock from Phase 1 start; print on the second-to-last line.
- [ ] Add a `## Standards (skill-specific)` section enforcing: (a) NEVER `Write` or `Edit` any path NOT under `~/.claude/docs/skill-evolution-proposals/<run-id>/`; (b) NEVER `cp` or `mv` regression tests into `~/.claude/hooks/tests/`; (c) NEVER call `AskUserQuestion` (the skill is fully autonomous between Phase 0a and Phase 4); (d) NEVER modify `~/.claude/projects/` (transcripts are read-only).
- [ ] Add a `## How to apply a proposal` section at the bottom — a 4-line user guide: `cd ~/.claude && git apply <run-dir>/diff.patch && cp <run-dir>/regression-tests/*.sh hooks/tests/ && bash hooks/tests/run-all.sh`. This is informational only; the skill itself does not run these commands.
- [ ] Cross-reference both upstream scripts by absolute path in the SKILL.md body.

## Acceptance Criteria

- [ ] AC1: SKILL.md exists at `/root/.claude/skills/skill-evolve/SKILL.md`.
- [ ] AC2 (mirrors PRD AC9): `grep -E '(Write|Edit).*file_path' /root/.claude/skills/skill-evolve/SKILL.md | grep -vE 'skill-evolution-proposals/.*RUN_ID|skill-evolution-proposals/\$RUN_ID|evolution/' | wc -l` returns 0 (no Write/Edit references outside the review directory).
- [ ] AC3 (mirrors PRD AC10): Phase 0a includes the cwd-agnostic sanity check (`~/.claude/projects` existence) — pattern adapted from `/plan-build-test` Phase 0a.
- [ ] AC4 (mirrors PRD AC2): No instruction in the SKILL.md modifies any path under `~/.claude/skills/`, `~/.claude/rules/`, `~/.claude/agents/`, `~/.claude/hooks/scripts/`, or any project's `CLAUDE.md`. Verifiable by visual inspection AND grep audit.
- [ ] AC5: No `cp` or `mv` instruction in the SKILL.md targets `~/.claude/hooks/tests/`.
- [ ] AC6: No `AskUserQuestion` instruction appears in the body between Phase 0a and Phase 4.
- [ ] AC7 (mirrors PRD AC1): The last bash block of the skill ends with a single `echo` or `cat summary.txt` printing the review-directory path (so the orchestrator's last line is unambiguous to the user).
- [ ] AC8: The "How to apply" section is informational only — there is NO bash block in the skill that auto-runs `git apply` or `cp ... hooks/tests/`.

## Verification

- [ ] Build passes (N/A — markdown only)
- [ ] Lint passes (N/A — markdown)
- [ ] Type-check passes (N/A — markdown)
- [ ] Sprint-specific tests pass — both Consumed-Invariants verify commands return success; AC2, AC4, AC5, AC6, AC8 grep audits all return zero matches as expected.

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

This is the user-facing surface of the whole PRD. Everything Sprints 1 and 2 build is plumbing; Sprint 3 is what the user types. The SKILL.md is the safety boundary documented as code: every Write/Edit must point into the review directory; the absence of any instruction outside that prefix IS the invariant.

The skill is intentionally short — it's an orchestrator, not a worker. Phases 0a, 0b, 1 are precondition checks and setup. Phases 2, 3 are bash invocations of the upstream scripts. Phase 4 is summary emission. Total expected file size: ≤200 lines.

The "How to apply a proposal" section is informational because the SKILL.md is loaded into the user's context whenever they invoke the skill. Telling them how to apply is more useful than making them remember. But the skill itself MUST NOT execute those commands — that would be the auto-apply behavior the PRD's safety boundary forbids.

The cwd-agnostic Phase 0a is a deliberate departure from `/plan-build-test`'s Phase 0a, which requires a git repo cwd. This skill reads `~/.claude/projects/` regardless of where the user invokes from — it's a global tool, not a per-project one. The simplified Phase 0a check (`~/.claude/projects` existence only) is sufficient.

The pre-flight (Phase 0b) targets the empty-history case: a fresh `~/.claude` install or a new machine where the user just enabled transcript logging. Exit cleanly under 30 seconds rather than spinning up the miner against zero files.

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

# INVARIANTS — Skill Library Self-Evolution

Cross-cutting contracts shared between the transcript miner (Sprint 1), the proposer (Sprint 2), and the `/skill-evolve` orchestrator skill (Sprint 3).

---

## Skill Never Writes Outside the Review Directory or evolution/

- **Owner:** `/root/.claude/skills/skill-evolve/SKILL.md` (Sprint 3) — primary surface; `/root/.claude/scripts/skill-evolve/propose-edits.py` (Sprint 2) — secondary defense via `--out` path guard
- **Preconditions:** Caller of the skill must accept that any path under `~/.claude/skills/`, `~/.claude/rules/`, `~/.claude/agents/`, `~/.claude/hooks/scripts/`, or any project's `CLAUDE.md` is OFF-LIMITS for direct modification by this skill.
- **Postconditions:** After a `/skill-evolve` invocation completes, `git status ~/.claude/skills/ ~/.claude/rules/ ~/.claude/agents/ ~/.claude/hooks/scripts/ ~/.claude/CLAUDE.md` shows zero modified files. All written artifacts live under `~/.claude/docs/skill-evolution-proposals/<run-id>/`.
- **Invariants:** Every Write/Edit instruction in the SKILL.md targets a path under `~/.claude/docs/skill-evolution-proposals/<run-id>/` (review-only). The proposer script refuses any `--out` path that does not begin with `~/.claude/docs/skill-evolution-proposals/` (or its `/root/.claude/...` expansion).
- **Verify:** `grep -E '(Write\|Edit).*file_path' /root/.claude/skills/skill-evolve/SKILL.md | grep -vE 'skill-evolution-proposals/.*RUN_ID|skill-evolution-proposals/\$RUN_ID|evolution/' | wc -l | grep -q '^0$'`
- **Verify (proposer guard):** `python3 /root/.claude/scripts/skill-evolve/propose-edits.py --out /tmp/foo --input /dev/null 2>&1 | grep -q -i 'refus'`
- **Fix:** If verify returns nonzero, an instruction was added that targets a forbidden path. Move it inside the review directory or remove it. Self-modifying tooling is the highest-blast-radius operation in this PRD; this guard is non-negotiable.

---

## Friction Taxonomy is a Closed Vocabulary

- **Owner:** `/root/.claude/scripts/skill-evolve/taxonomy.py` (Sprint 1)
- **Preconditions:** Sprint 2 (proposer) must consume only the documented categories. Adding a sixth category requires updating `taxonomy.py`, the proposer's category-to-target mapping, and PRD Section 12.
- **Postconditions:** Every friction event emitted by the miner has `category` ∈ {`workaround`, `retry`, `refusal`, `env-incompat`, `missing-method`}.
- **Invariants:** No event written to the friction-events JSONL has a category outside the closed set. Adding a new category is a coordinated three-file change (taxonomy.py, propose-edits.py, this INVARIANTS entry).
- **Verify:** `python3 -c "import sys; sys.path.insert(0, '/root/.claude/scripts/skill-evolve'); from taxonomy import CATEGORIES; assert CATEGORIES == frozenset({'workaround','retry','refusal','env-incompat','missing-method'}), CATEGORIES"`
- **Fix:** If `CATEGORIES` drifts from the documented set, restore it. If a sixth category is genuinely needed, update all three locations atomically.

---

## Single-Event Clusters Are Not Emitted as Proposals

- **Owner:** `/root/.claude/scripts/skill-evolve/cluster.py` (Sprint 2)
- **Preconditions:** Friction events arrive from the miner with `fingerprint` populated.
- **Postconditions:** Every `## Cluster:` section in `proposal.md` cites ≥2 distinct source events. Single-event matches are dropped silently from the proposal (they may still appear in `friction-events.jsonl` for transparency, but never as proposals).
- **Invariants:** No proposal recommends an edit based on a single observation. The minimum-evidence-bar is 2 occurrences.
- **Verify:** After a run, `awk '/^## Cluster:/{c=1; next} c && /Evidence:.*([0-9]+) events/{match($0, /([0-9]+)/, a); if (a[1] < 2) print "FAIL"; c=0}' <run-dir>/proposal.md | grep -q FAIL` returns non-zero (no FAIL printed).
- **Fix:** Restore the `len(events) >= 2` filter in `cluster.py`. Single-event proposals are noise.

---

## Regression Tests Are Unmoved

- **Owner:** `/root/.claude/skills/skill-evolve/SKILL.md` (Sprint 3)
- **Preconditions:** The proposer (Sprint 2) writes regression tests to `<run-dir>/regression-tests/`.
- **Postconditions:** The orchestrator (Sprint 3) does NOT copy or move them anywhere. The user is expected to manually `cp` them into `~/.claude/hooks/tests/` after reviewing.
- **Invariants:** No `cp`, `mv`, `rsync`, `install`, or other file-relocation instruction in the SKILL.md targets `~/.claude/hooks/tests/`. After a fresh `/skill-evolve` run with no manual user action, `ls ~/.claude/hooks/tests/test-skill-evolve-* 2>/dev/null` is empty.
- **Verify:** `grep -E '(cp|mv|rsync|install).*hooks/tests' /root/.claude/skills/skill-evolve/SKILL.md | wc -l | grep -q '^0$'`
- **Fix:** If a copy/move instruction is added, remove it. The manual-move step exists by design (PRD Section 9: "auto-wiring untested generated code into the test runner could mask bugs in the generator itself").

---

## Token Redaction Applied to All Evidence Quotes

- **Owner:** `/root/.claude/scripts/skill-evolve/redact.py` (Sprint 1)
- **Preconditions:** Both Sprint 1 (miner) and Sprint 2 (proposer) MUST call `redact.scrub(text)` before writing any evidence quote pulled from a transcript.
- **Postconditions:** No raw token matching `(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16})` appears in any file under `<run-dir>/`.
- **Invariants:** The redaction is applied at extract-time (miner) and re-applied at write-time (proposer) — defense in depth. Adding a new token pattern is a single-file change in `redact.py`; both consumers automatically pick it up.
- **Verify:** After a run with a fixture transcript containing `sk-FAKE12345678901234567890abcd`: `grep -rE '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16})' <run-dir>/ | wc -l | grep -q '^0$'`
- **Fix:** If verify returns nonzero, the token leaked through. Inspect: did the proposer skip a `redact.scrub()` call? Did the regex miss a token format? Add the format to `redact.py` and re-run.

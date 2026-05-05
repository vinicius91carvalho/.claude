---
name: skill-evolve
description: >
  Mines the last 30 days of session transcripts for recurring friction patterns
  and emits a review directory of proposed edits to skills/rules/CLAUDE.md.
  Never modifies any skill, rule, agent, hook, or CLAUDE.md directly — outputs
  to `~/.claude/docs/skill-evolution-proposals/<run-id>/` only; the user
  reviews and applies manually.
triggers:
  - "evolve skills"
  - "mine my transcripts"
  - "what friction patterns am I hitting"
  - "propose skill improvements"
  - "/skill-evolve"
---

# /skill-evolve — Transcript Mining & Skill Proposal Pipeline

Mines session transcripts for recurring friction, clusters patterns, and
proposes concrete edits to skills/rules/CLAUDE.md — all in a review directory.
**The skill never writes to any skill, rule, agent, hook, or CLAUDE.md file.**

**Autonomous by default.** No AskUserQuestion calls between Phase 0a and
Phase 4. The user reviews the output directory after the skill completes.

---

## Phase 0a — Working-Directory Sanity (cwd-agnostic)

This skill does NOT require a git repo cwd — it is a global tool. It requires
only that `~/.claude/projects/` exists.

```bash
[ -d "$HOME/.claude/projects" ] || {
  echo "BLOCKED: ~/.claude/projects does not exist — no transcripts to mine."
  exit 1
}
```

---

## Phase 0b — Pre-flight Transcript Freshness

Count recent transcript files. If none exist in the last 30 days, exit cleanly
without creating a review directory (PRD AC7 — empty-history fast exit).

```bash
RECENT_COUNT=$(find ~/.claude/projects -name '*.jsonl' -mtime -30 2>/dev/null | wc -l)
if [ "$RECENT_COUNT" -eq 0 ]; then
  echo "no transcripts in last 30 days — nothing to mine"
  exit 0
fi
echo "found $RECENT_COUNT transcript file(s) modified in last 30 days"
```

---

## Phase 1 — Run-ID + Output Directory

```bash
RUN_ID="$(date +%s)-$(head /dev/urandom | tr -dc a-z0-9 | head -c4)"
OUT_DIR="$HOME/.claude/docs/skill-evolution-proposals/$RUN_ID"
mkdir -p "$OUT_DIR/regression-tests"
START_TS=$(date +%s)
echo "run-id: $RUN_ID"
echo "out:    $OUT_DIR"
```

---

## Phase 2 — Invoke Miner

Calls `/root/.claude/scripts/skill-evolve/mine-transcripts.py`. The miner
reads all `~/.claude/projects/*/*.jsonl` files modified in the last 30 days,
applies the friction taxonomy, and emits one JSONL line per friction event to
stdout. Transcripts are **read-only** — the miner never writes to them.

```bash
SINCE_DATE="$(date -d '30 days ago' --iso-8601=seconds 2>/dev/null || date -v-30d -u +%Y-%m-%dT%H:%M:%S)"

python3 /root/.claude/scripts/skill-evolve/mine-transcripts.py \
  --all \
  --since "$SINCE_DATE" \
  > "$OUT_DIR/friction-events.jsonl"
MINER_EXIT=$?

if [ $MINER_EXIT -ne 0 ]; then
  echo "miner exited non-zero ($MINER_EXIT); partial results at $OUT_DIR/friction-events.jsonl"
  exit $MINER_EXIT
fi

FRICTION_COUNT=$(wc -l < "$OUT_DIR/friction-events.jsonl")
echo "miner: $FRICTION_COUNT friction event(s) written to friction-events.jsonl"
```

---

## Phase 3 — Invoke Proposer

Calls `/root/.claude/scripts/skill-evolve/propose-edits.py`. The proposer
clusters friction events and writes the following to `$OUT_DIR`:

- `proposal.md` — one section per cluster (title, evidence, proposed edit, test ref)
- `diff.patch` — git-format-patch of proposed edits (applies with `git apply`)
- `friction-events.jsonl` — copy of miner output (already present from Phase 2)
- `regression-tests/test-skill-evolve-<cluster>.sh` — one test per cluster
- `summary.txt` — single-line human-readable summary

```bash
python3 /root/.claude/scripts/skill-evolve/propose-edits.py \
  --input "$OUT_DIR/friction-events.jsonl" \
  --out "$OUT_DIR"
PROPOSER_EXIT=$?

if [ $PROPOSER_EXIT -ne 0 ]; then
  echo "proposer exited non-zero ($PROPOSER_EXIT); partial results at $OUT_DIR"
  exit $PROPOSER_EXIT
fi
```

---

## Phase 4 — Summary Emission

Print elapsed time, review directory path, and the contents of `summary.txt`.
The last line of stdout is the summary line from `summary.txt` (PRD AC1).

```bash
ELAPSED=$(( $(date +%s) - START_TS ))
echo "elapsed: ${ELAPSED}s"
echo "review:  $OUT_DIR"
cat "$OUT_DIR/summary.txt"
```

---

## Standards (skill-specific)

These rules are enforced by construction — the skill's only Bash invocations
target the two upstream scripts, and all writes go through those scripts into
`$OUT_DIR` (which is always under `~/.claude/docs/skill-evolution-proposals/`).

(a) **NEVER** `Write` or `Edit` any path NOT under
    `~/.claude/docs/skill-evolution-proposals/<run-id>/` or
    `~/.claude/evolution/`. Every file created by this skill is namespaced
    under the run-id directory.

(b) **NEVER** `cp`, `mv`, `rsync`, or `install` regression tests into
    `~/.claude/hooks/tests/`. Proposed test files land in
    `$OUT_DIR/regression-tests/`. The user moves them manually after review
    (PRD Section 9 design — auto-wiring is forbidden).

(c) **NEVER** call `AskUserQuestion` between Phase 0a and Phase 4. The skill
    is fully autonomous — no interactive checkpoints in the mining pipeline.

(d) **NEVER** modify `~/.claude/projects/` — transcripts are read-only
    historical records. The miner reads them; it never writes back.

(e) The skill does **NOT** call out to LLMs. Both upstream scripts
    (`mine-transcripts.py` and `propose-edits.py`) are deterministic,
    rule-based, and make no network calls.

---

## How to Apply a Proposal

The skill itself does not run any of the steps below — **you do, after
reviewing the proposal.** Read `proposal.md` and `diff.patch` in `$OUT_DIR`
before applying anything.

```text
cd ~/.claude
git apply <run-dir>/diff.patch
bash hooks/tests/run-all.sh
```

Copy proposed regression tests into the runner directory first:

```text
cp <run-dir>/regression-tests/*.sh \
   ~/.claude/hooks/tests/
```

Replace `<run-dir>` with the full path printed on the `review:` line when the
skill ran (e.g.
`~/.claude/docs/skill-evolution-proposals/1746442800-a3f2`).

If `git apply --check` fails for any patch hunk, the proposer will have
included the proposed change as an inline code block in `proposal.md` instead
of in `diff.patch` — apply it manually or skip it. Never apply a patch you
have not read.

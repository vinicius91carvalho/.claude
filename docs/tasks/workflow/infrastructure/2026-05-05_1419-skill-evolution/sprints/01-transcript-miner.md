# Sprint 1: Transcript Miner — Friction Event Extraction + Redaction

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 1 of 3
- **Depends on:** None
- **Batch:** 1 (parallel with Sprint 2)
- **Model:** sonnet
- **Estimated effort:** M

## Objective

Build a deterministic Python script that scans `~/.claude/projects/*/*.jsonl` transcripts, classifies friction events using the closed taxonomy from PRD Section 12, applies token-redaction at extract-time, and emits a normalized friction-events JSONL stream to stdout.

## File Boundaries

### Creates (new files)

- `/root/.claude/scripts/skill-evolve/mine-transcripts.py` — main miner; reads transcript paths from argv or stdin, writes friction events to stdout
- `/root/.claude/scripts/skill-evolve/redact.py` — small, importable redaction module (regex per PRD AC8); also runnable standalone for testing
- `/root/.claude/scripts/skill-evolve/taxonomy.py` — taxonomy constants and the per-category event-detection rules; importable by mine-transcripts.py

### Modifies (can touch)

- (none — Sprint 1 only creates new scripts in a new subdirectory)

### Read-Only (reference but do NOT modify)

- `/root/.claude/projects/` — transcript data (sampled at sprint-execution time for fixture creation; never written)
- `/root/.claude/hooks/scripts/` — for shell-script style reference if any helper bash is needed
- `../spec.md` — PRD context (read once at sprint start)

### Shared Contracts (consume from prior sprints or PRD)

- Friction taxonomy (PRD Section 12): `workaround`, `retry`, `refusal`, `env-incompat`, `missing-method`
- Friction-event JSONL schema (PRD Section 11): one JSON object per line with fields `session_id`, `project`, `transcript_path`, `turn_index`, `category`, `evidence_quote`, `fingerprint`, `occurred_at`
- Token-redaction regex (PRD Section 12): `(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16})` → `[REDACTED]`

### Consumed Invariants (from INVARIANTS.md)

- `Friction taxonomy is a closed vocabulary` — this sprint OWNS the taxonomy module and is the single source of truth for category strings
- `Token redaction applied to all evidence quotes` — this sprint owns `redact.py`; every quote written by the miner passes through `redact.scrub(text)` first
- Verify: `python3 -c "from scripts.skill_evolve.taxonomy import CATEGORIES; assert CATEGORIES == frozenset({'workaround','retry','refusal','env-incompat','missing-method'})"`
- Verify: `echo 'sk-FAKE12345678901234567890abcd' | python3 /root/.claude/scripts/skill-evolve/redact.py | grep -q '\[REDACTED\]'`

## Tasks

- [ ] Create `/root/.claude/scripts/skill-evolve/` directory.
- [ ] Write `taxonomy.py`: define `CATEGORIES = frozenset({...})` with the five strings, plus a per-category list of detection rules. Each rule is a tuple `(regex, capture_template)` — the regex matches against either user message text, assistant message text, or tool_result text; the capture template formats the evidence quote.
  - `workaround`: assistant says "let me try a different approach", "switching to", "instead I'll use", or shows a fallback after a tool error
  - `retry`: same tool call within 3 turns of a failed identical tool call
  - `refusal`: subagent returns "I cannot" or "I refuse" or main agent halts on hook block
  - `env-incompat`: tool result contains "command not found", "permission denied", "exec format error", "wrong ELF", "not portable", or known proot-env strings
  - `missing-method`: tool result contains "AttributeError: ... has no attribute", "is not a function", "method does not exist", "unknown command"
- [ ] Write `redact.py`: function `scrub(text: str) -> str` applying the three regex substitutions. Standalone main reads stdin and prints scrubbed stdout. Add a 6-line unit-test stub at the bottom of the file (only runs under `if __name__ == '__main__' and '--selftest' in sys.argv`).
- [ ] Write `mine-transcripts.py`: takes one or more transcript paths (or `--all` to glob `~/.claude/projects/*/*.jsonl`), streams JSONL parse line-by-line, applies the taxonomy detectors per turn, emits friction-event JSONL to stdout. Each event has all fields from PRD Section 11. Compute `fingerprint` as `sha1(normalized_evidence)` where normalization lowercases, strips whitespace, removes digits.
- [ ] Add `--since <iso8601>` flag to filter transcripts by mtime — defaults to 30 days ago. Add `--limit <N>` for testing.
- [ ] Add minimal CLI help (`--help`) and a `--selftest` mode for `taxonomy.py` and `redact.py` that runs ≤5 inline assertions and exits non-zero on failure.
- [ ] Verify the miner produces deterministic output: same input transcripts twice → byte-identical stdout.

## Acceptance Criteria

- [ ] AC1: `python3 /root/.claude/scripts/skill-evolve/redact.py --selftest` exits 0; running with the regex examples from PRD AC8 produces `[REDACTED]` in output.
- [ ] AC2: `python3 /root/.claude/scripts/skill-evolve/taxonomy.py --selftest` exits 0; CATEGORIES matches the five strings exactly.
- [ ] AC3: `python3 /root/.claude/scripts/skill-evolve/mine-transcripts.py --all --limit 5 --since 2026-01-01` exits 0 on a real `~/.claude/projects/` and produces JSONL on stdout with at least the schema fields populated (zero events is allowed if no friction matched).
- [ ] AC4: Every JSONL line emitted parses as valid JSON, contains all 8 schema fields, and has `category` ∈ CATEGORIES.
- [ ] AC5: Running the miner twice on the same input produces byte-identical output (deterministic — no timestamps in the output that aren't sourced from the input).
- [ ] AC6: A fixture transcript containing the literal string `sk-FAKE12345678901234567890abcd` in a tool_result, when mined, produces a friction event whose `evidence_quote` contains `[REDACTED]` and does NOT contain the original token.

## Verification

- [ ] Build passes (N/A — Python script, no compile)
- [ ] Lint passes — `python3 -m py_compile /root/.claude/scripts/skill-evolve/*.py` exits 0
- [ ] Type-check passes (N/A — no type stubs required for this scope; type hints encouraged but not enforced)
- [ ] Sprint-specific tests pass — the three `--selftest` modes (redact, taxonomy, miner) all exit 0; the AC6 redaction fixture passes.

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

The miner runs as a deterministic preprocessor for the proposer. It must NOT call out to LLMs — all classification is rule-based. The five categories are chosen to cover the user's documented recurring friction (per the `/insights` report and the autonomous-staging PRD's discovery context):

- `workaround`: user's `/insights` flagged "missing client method's deleteBank workaround" — assistant tried API, hit error, switched to alternative
- `retry`: user's "Logic failures retried up to 4" pattern — same approach repeated
- `refusal`: subagents that "refused to act, forcing Bash fallback" per `/insights`
- `env-incompat`: proot-distro env limits (no AWS, no Clerk, native module rebuilds, grep portability)
- `missing-method`: SDK/CLI method absent at runtime (the `clearBankMemories` example)

The taxonomy is intentionally conservative — five categories cover the high-signal patterns. Sprint 2's clustering will further dedupe by fingerprint, so the miner can be permissive about matching (false positives at the event level become same-cluster duplicates that the proposer handles).

Determinism matters because the proposer is downstream and the user may inspect both. If miner output isn't deterministic, two runs against the same transcripts produce different review directories — confusing.

The redaction module is separated for two reasons: (1) Sprint 2 also calls it (proposer might re-render evidence quotes from the JSONL), and (2) the user may want to add more redaction patterns later (e.g. their own internal token formats) without touching the miner.

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

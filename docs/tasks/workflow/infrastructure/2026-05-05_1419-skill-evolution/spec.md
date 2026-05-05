# Skill Library Self-Evolution: Product Requirements Document

## 1. What & Why

**Problem:** The user's `/insights` reports surface recurring friction events that they themselves notice (non-portable shell idioms, sub-agent refusals forcing Bash fallback, missing client methods, tests placed outside the runner discovery path, etc.). Each friction is observed, manually translated into a SKILL.md or CLAUDE.md edit, and then forgotten until the same friction re-appears in a new context. There is no closed loop between "friction observed in transcripts" and "rule baked into the system." `/compound` captures per-task learnings, but cross-session pattern mining and proposed-edit generation remain manual.

**Desired Outcome:** A user-invoked skill, `/skill-evolve`, that mines the last N days of session transcripts (`~/.claude/projects/*/*.jsonl`), clusters recurring friction events, generates concrete proposed edits to the relevant SKILL.md / rules.md / CLAUDE.md files, generates regression tests that would have caught the original friction, drops everything into a single review directory under `~/.claude/docs/skill-evolution-proposals/<run-id>/`, and exits with a one-paragraph summary pointing the user at the review directory. The user reads the proposals, runs `git apply` (or rejects), and re-runs the test suite. The skill never modifies SKILL.md, rule files, or CLAUDE.md directly.

**Justification:** The user's own insights call out: "An agent could continuously mine your session transcripts, propose skill/SKILL.md improvements, generate regression tests for each fix, and require all 11+ existing suites to pass before self-merging the upgrade." They have already invested in 12 hook test suites with deterministic discovery (`hooks/tests/test-*.sh`). The missing piece is the proposer — and crucially, the safety-bounded proposer. Self-modifying tooling is high-blast-radius; the pattern that matches the user's documented value hierarchy ("MUST ask user" for changes affecting how the system behaves) is a propose-don't-apply skill that produces a review artifact, not auto-merging changes. This PRD delivers exactly that.

## 2. Correctness Contract

**Audience:** The user (single power user), invoking `/skill-evolve` periodically (weekly or after notable friction), then reviewing the generated proposals before manually applying any. The review directory is the single user-facing artifact. No downstream tooling consumes the output.

**Failure Definition:** A run is useless if any of: (1) the miner misses obvious recurring friction (e.g. sub-agent refusal happening in 5 sessions but cluster size reported as 0 or 1); (2) proposed edits are syntactically broken (won't apply with `git apply` or fail to parse as markdown); (3) regression tests don't actually fail under the original-buggy state (i.e. they trivially pass and don't gate anything); (4) the review directory is dropped silently with no summary or path emitted; (5) the run takes >10 minutes without checkpointing, and a context loss erases all work.

**Danger Definition:** A run is actively harmful if any of: (1) the skill modifies any file under `~/.claude/skills/`, `~/.claude/rules/`, `~/.claude/agents/`, `~/.claude/hooks/scripts/`, or any project's `CLAUDE.md` directly (auto-merge of proposed edits is forbidden — review-only); (2) the skill writes to `MEMORY.md` files autonomously (memory writes belong to the user's main agent context per the auto-memory protocol); (3) the skill reads transcript content and emits sensitive data (API keys, customer data appearing in transcripts) into the review directory verbatim without redaction; (4) the regression test files are dropped into `~/.claude/hooks/tests/` directly (auto-wiring) instead of into the review directory; (5) the skill commits to `~/.claude` `main` without explicit user action.

**Risk Tolerance:** For modifications to skill/rule/hook files: confident-wrong is catastrophic — refuse absolutely, emit proposals to review directory only. For transcript reading: prefer making progress (parse defensively, skip malformed lines) over refusal — transcripts are append-only and won't break under partial reads. For friction clustering: prefer false negatives (miss a cluster) over false positives (propose an edit for a non-issue) — false-positive proposals waste review time and erode trust in the skill. For regression test generation: prefer no test over an incorrect test — a missing regression test is recoverable; a misleading one is worse than none.

**Session-identification contract:** The skill runs in the user's orchestrator session and reads `$CLAUDE_SESSION_ID` from the env. Transcripts under `~/.claude/projects/*/<session-uuid>.jsonl` are scoped per-session; the miner reads ALL recent transcripts (across all sessions and all projects), not just the current session's. The skill does NOT need to hold any cross-session lock — its only writes are to `~/.claude/docs/skill-evolution-proposals/<run-id>/`, namespaced per invocation. Two concurrent `/skill-evolve` runs would produce two distinct review directories with no overlap.

## 3. Context Loaded

- `~/.claude/projects/` directory: per-project subdirectories (e.g. `-root-projects-causeflow/`) each containing JSONL transcript files keyed by session UUID. Files are append-only during a live session and immutable after session end. Schema is the standard Claude Code message log: alternating user/assistant turns with tool_use and tool_result blocks.
- `~/.claude/hooks/tests/run-all.sh` and `test-*.sh`: existing test runner with auto-discovery — any new file matching `test-*.sh` in this directory is automatically picked up. 12 suites currently exist; this skill MUST NOT drop new test files here directly — it emits proposed test files into the review directory, and the user moves them in (which auto-wires them via the runner's glob).
- `~/.claude/skills/` directory: SKILL.md files for all installed skills. This is the primary target of proposed edits.
- `~/.claude/rules/`: workflow.md, quality.md, environment.md, web.md — modular rule files imported into the global CLAUDE.md.
- `~/.claude/CLAUDE.md`: global instructions. Subject to proposed edits when friction is global.
- `~/.claude/skills/compound/SKILL.md`: existing per-task learning capture. `/skill-evolve` is the cross-session, cross-project complement: compound captures per-task, this captures patterns across many tasks. They are NOT redundant.
- `~/.claude/evolution/error-registry.json` and `model-performance.json`: existing structured stores for cross-project friction. The miner SHOULD enrich these (read-write), but writing is gated — additions go to the review directory as proposed-JSON-merge alongside the SKILL.md proposals.
- The autonomous-staging PRD (just-sealed Build Candidate `2026-05-05_1256-autonomous-staging`): same authoring style, same safety-boundary-as-code-path-unreachability pattern. This PRD mirrors that structure.

## 4. Success Metrics

| Metric | Current | Target | How to Measure |
|--------|---------|--------|----------------|
| Manual translation of friction observation → SKILL.md edit | Per-session, ad-hoc | Single `/skill-evolve` invocation produces all candidate edits for the period | Count user-typed slash commands that propose changes vs. user-typed direct edits in `~/.claude/skills/` over a week |
| Friction clusters surfaced per run | N/A (no current tool) | ≥3 clusters when ≥7 days of activity exist; reasoned "no clusters" message when activity is low | Inspect review directory file count after a typical run |
| False-positive proposed edits (proposals the user rejects without applying) | N/A | <30% of proposals rejected as "not real friction" | Track per-run via the proposal's outcome (apply / reject) recorded in the user's git log |
| Regression tests that actually gate (would fail under buggy state) | N/A | 100% of generated tests fail when `git revert`-ed to the pre-fix state | Run the proposed test against the pre-fix tree; assert non-zero exit |
| Skill/rule/hook files modified directly by the skill | N/A | 0 — ever, by construction | `git status ~/.claude/skills/ ~/.claude/rules/ ~/.claude/hooks/` after a `/skill-evolve` run shows zero changes |

## 5. User Stories

GIVEN at least 7 days of `~/.claude/projects/*/*.jsonl` activity with at least 3 distinct recurring friction patterns
WHEN the user runs `/skill-evolve`
THEN within ~5 minutes the skill produces a review directory at `~/.claude/docs/skill-evolution-proposals/<run-id>/` containing: a top-level `proposal.md` with one section per friction cluster, a `diff.patch` (git-format-patch) of the proposed edits, and a `regression-tests/` subdirectory with one `test-skill-evolve-<cluster>.sh` per cluster. The skill exits with a single line pointing at the review directory.

GIVEN a fresh `~/.claude` install with no transcript history
WHEN the user runs `/skill-evolve`
THEN the skill exits in <30 seconds with "no transcript history yet — nothing to mine" and creates no review directory.

GIVEN any state of the transcripts
WHEN `/skill-evolve` runs
THEN no file under `~/.claude/skills/`, `~/.claude/rules/`, `~/.claude/agents/`, `~/.claude/hooks/scripts/`, or `~/.claude/CLAUDE.md` is modified by the skill — only files under `~/.claude/docs/skill-evolution-proposals/<run-id>/` and (read-write, but gated through proposals) `~/.claude/evolution/*.json`.

GIVEN a friction cluster with ≥3 occurrences
WHEN the proposer generates a regression test for it
THEN running that test against the current `~/.claude/` checkout passes (because the proposed fix is hypothetical, not yet applied) — the test is designed to gate the FIX, not the bug — but applying the proposed `diff.patch` and re-running the test causes it to pass on a synthetic "pre-fix" snapshot the skill records alongside the test as `regression-tests/<cluster>-prefix-snapshot.txt`.

## 6. Acceptance Criteria

- [ ] AC1: Invoking `/skill-evolve` from any cwd (the skill is cwd-agnostic; it reads `~/.claude/projects/`) creates a review directory at `~/.claude/docs/skill-evolution-proposals/<run-id>/` and exits with the path printed on the last line.
- [ ] AC2: Running `git status ~/.claude/skills/ ~/.claude/rules/ ~/.claude/agents/ ~/.claude/hooks/scripts/` immediately after a `/skill-evolve` run shows no changes (the skill modifies none of these directly).
- [ ] AC3: The miner identifies friction events using the documented taxonomy (workaround, retry, refusal, env-incompat, missing-method) and clusters by similarity. Each cluster emitted to the review directory has ≥2 distinct source events cited (no single-event clusters proposed as edits).
- [ ] AC4: Each `regression-tests/test-skill-evolve-<cluster>.sh` follows the existing `~/.claude/hooks/tests/test-*.sh` shape (sources `lib/` if needed, uses the existing assertion helpers, exits 0 on pass / non-zero on fail) so that copying it into `~/.claude/hooks/tests/` auto-wires it via `run-all.sh`'s glob.
- [ ] AC5: The `proposal.md` file contains one section per cluster with: cluster title, friction-event evidence (file paths + line ranges of the source transcripts), proposed edit summary (which target file and what change), regression test reference (file path inside the review dir).
- [ ] AC6: The `diff.patch` file applies cleanly with `git apply --check` against the current `~/.claude/` HEAD. If the skill cannot produce a clean patch (e.g. target file moved), it emits the proposed edits as inline code blocks in `proposal.md` and notes the patch generation failed — does NOT silently drop the proposal.
- [ ] AC7: Pre-flight: if `~/.claude/projects/` is empty, contains no `.jsonl` files, or has files all <1 day old (insufficient signal), exit cleanly with a "nothing to mine" message in <30 seconds.
- [ ] AC8: Sensitive data redaction: any token-like string (regex `(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16})`) appearing in a friction-event quote pulled into the review directory is replaced with `[REDACTED]` before the file is written.
- [ ] AC9: A grep audit confirms safety boundary: `grep -r 'skills/\|rules/\|agents/\|hooks/scripts/' ~/.claude/skills/skill-evolve/SKILL.md | grep -E 'Write|Edit'` returns zero matches that would write outside the review directory (the only Write/Edit calls in the skill target the review dir).
- [ ] AC10: The `/skill-evolve` SKILL.md includes the `Phase 0a` working-directory sanity-check pattern from `/plan-build-test` adapted for cwd-agnostic mode (it does NOT require a git repo cwd, but does require `~/.claude/projects/` to exist).

## 7. Non-Goals

- **Auto-applying proposals.** Excluded: this is the entire safety boundary. The user reviews and applies manually. A future "low-friction apply" mode could be added later (e.g. `/skill-evolve --apply <cluster-id>` that applies a single approved cluster), but is out of scope.
- **Cron / scheduled runs.** Excluded: per the autonomous-staging PRD precedent, the user prefers manual invocation. A cron wrapper can call this skill externally if desired.
- **Modifying transcripts or `~/.claude/projects/`.** Excluded: transcripts are immutable historical record. The skill is read-only against them.
- **Cross-machine syncing of proposals.** Excluded: review directory is local-only. Sharing proposals with collaborators is out of scope (single-user system).
- **Modeling the user's preferences with ML or embeddings.** Excluded: the miner uses deterministic rules + a small classifier (regex + heuristics over transcript JSON). No model training, no embedding API calls, no LLM-as-classifier within the miner. The orchestrator agent IS the LLM that runs the miner script and drafts the proposals — but the miner script itself is deterministic.
- **Evolution beyond skill files.** Excluded: project-specific CLAUDE.md edits are out of scope (those are per-project and the user owns them per repo). This skill targets the global `~/.claude/` tooling only.
- **A web UI for reviewing proposals.** Excluded: review is `git log -p`, `cat proposal.md`, `git apply`. Single-user CLI tool.
- **Machine-merging the proposal back into the live skill files via PR.** Excluded: ~/.claude is the user's local config; PR machinery is out of scope.

## 8. Technical Constraints

- **Stack:** Bash + Python (3.x, already required by other hooks) + Markdown. No new runtime dependencies — uses only what's already in `~/.claude/hooks/scripts/` and `~/.claude/skills/` patterns.
- **Architecture:** Three-stage pipeline: (1) miner script reads transcripts, emits a JSONL of friction events; (2) proposer script reads the friction JSONL, clusters, and emits the review directory; (3) the SKILL.md orchestrates both with pre-flight + post-flight summary. Each script is independently invocable for testing.
- **Performance:** Mining target: <5 min for a year of transcripts (assume up to ~500 JSONL files at ~1MB each). Streaming JSONL parse, no in-memory accumulation of full transcripts. Proposer target: <2 min per cluster.
- **Concurrency:** No locks needed — output is namespaced per `<run-id>`. Two concurrent invocations produce two distinct directories.
- **Tool surface:** Skill orchestrator uses only Bash, Read, Write, Glob (for transcript discovery). No MCP. No network.

## 9. Architecture Decisions

| Decision | Reversal Cost | Alternatives Considered | Rationale |
|----------|--------------|-------------------------|-----------|
| Three-stage pipeline (miner → proposer → SKILL.md orchestrator) rather than a monolith | Low | Single Python script does it all | Three stages allow each to be unit-tested in isolation. The miner produces a JSONL artifact that the proposer can consume independently — useful for re-running the proposer with tweaked clustering thresholds without re-mining. |
| Review-directory output rather than auto-apply | High to revert | Auto-apply with `git revert` as undo | Self-modifying tooling without explicit human review violates the "MUST ask user" value-hierarchy rule for changes affecting how the system behaves. Auto-apply with revert is recoverable but the user might miss the change in the moment, leading to confusing future behavior. |
| Deterministic regex+heuristic miner (not LLM-classified) | Medium | Use the orchestrator agent to classify each transcript turn | Cost ceiling — LLM-classifying every transcript turn for friction is token-expensive and slow. Regex+heuristic catches the obvious recurring patterns (the high-value clusters); subtle cases the LLM might catch are by definition single-occurrence and not worth proposing as durable edits. |
| Regression tests follow `test-*.sh` discovery convention but live in review dir until user moves them | Low | Drop directly into `hooks/tests/` | Auto-wiring untested generated code into the test runner could mask bugs in the generator itself. Forcing a manual move step makes the user notice when the generator misfires. |
| Token-redaction at write-time (review-dir output) rather than at read-time (transcript ingest) | Low | Redact during mining | Transcripts on disk are already user-trusted (their own machine). The risk is the review directory ending up shared (e.g. pasted into a bug report). Redacting at write-time covers that case without re-processing transcripts. |
| Proposer emits inline-code-block fallback when `git apply` patch generation fails | Low | Always emit a patch; fail loudly otherwise | Soft failure surface is better than dropping work. The proposal is still valuable to the user even if the patch needs manual application. |

## 10. Security Boundaries

- **Auth model:** No new auth surface. No network calls.
- **Trust boundaries:** Transcripts are trusted input (the user's own session history). Skill/rule/hook files are read-only from this skill's perspective. The review directory is the only write surface.
- **Data sensitivity:** Transcripts can contain API tokens, customer data, secrets surfaced in tool output. AC8 redaction handles tokens. Customer-data redaction is out of scope (the user's own transcripts on their own machine are the user's own concern; a proposal review directory containing customer data is not exfiltrated unless the user pastes it elsewhere).
- **Tenant isolation:** N/A.
- **Self-modification safety boundary:** Implementation MUST be unreachable code, not unreachable behavior. The SKILL.md orchestrator's bash blocks MUST contain a guard at every `Write` or `Edit` instruction that asserts the target path begins with `~/.claude/docs/skill-evolution-proposals/` or `~/.claude/evolution/` (the latter is for proposed-JSON-merge files; actual JSON merge into the live `evolution/*.json` is still review-only). Any path outside those prefixes is a P0 bug. Reviewer verifies via `grep` audit per AC9.
- **Token redaction:** Any captured friction-event quote from a transcript that's written into `proposal.md` or `diff.patch` MUST be passed through the redaction filter (regex per AC8). Sprint 1 (miner) implements the filter; Sprint 2 (proposer) calls it before any write.

## 11. Data Model

The skill introduces one transient data shape: the friction-events JSONL produced by the miner and consumed by the proposer.

```json
// One JSON object per line. File: <review-dir>/friction-events.jsonl
{
  "session_id": "uuid-from-transcript-filename",
  "project": "-root-projects-causeflow",
  "transcript_path": "/root/.claude/projects/<dir>/<uuid>.jsonl",
  "turn_index": 142,
  "category": "workaround|retry|refusal|env-incompat|missing-method",
  "evidence_quote": "[redacted text snippet ≤200 chars]",
  "fingerprint": "sha1-of-normalized-evidence",
  "occurred_at": "2026-05-05T14:19:18Z"
}
```

Clustering: the proposer groups events by `category` + `fingerprint` (with edit-distance bucketing for fingerprints differing by <10%). A cluster with ≥2 events is eligible for a proposal.

No persistent schema added. The friction-events JSONL lives only inside the review directory (alongside `proposal.md` and `diff.patch`) for traceability — the user can inspect the raw evidence behind each cluster.

## 12. Shared Contracts

- **Friction taxonomy:** Five categories — `workaround`, `retry`, `refusal`, `env-incompat`, `missing-method`. Defined and owned by Sprint 1 (miner). Sprint 2 (proposer) consumes by category. Adding a sixth category is a coordinated change across both sprints.
- **Friction-event JSONL schema:** As above. Sprint 1 produces, Sprint 2 consumes.
- **Review-directory layout:**
  ```
  ~/.claude/docs/skill-evolution-proposals/<run-id>/
    proposal.md
    diff.patch           # may be absent if generation failed; proposal.md notes it
    friction-events.jsonl
    regression-tests/
      test-skill-evolve-<cluster-slug>.sh
      <cluster-slug>-prefix-snapshot.txt
    summary.txt          # one-line pointer for the orchestrator to print
  ```
- **Token-redaction regex** (Sprint 1, consumed by Sprint 2): `(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16})` — applied to all evidence quotes before write.
- **Run ID format:** `<unix-timestamp>-<random4-lowercase>` (same shape as `CLAUDE_PIPELINE_INVOCATION_ID` from the autonomous-staging PRD), set by Sprint 3.

## 13. Architecture Invariant Registry

| Concept | Owner | Format/Values | Verify Command |
|---------|-------|---------------|----------------|
| Skill never writes outside the review directory or evolution/ | `/skill-evolve` SKILL.md (Sprint 3) | All Write/Edit invocations target `~/.claude/docs/skill-evolution-proposals/<run-id>/...` or `~/.claude/evolution/*.json` (gated, review-only) | `grep -E '(Write\|Edit).*file_path' /root/.claude/skills/skill-evolve/SKILL.md \| grep -vE 'skill-evolution-proposals/.*run-id\|evolution/' \| wc -l \| grep -q '^0$'` |
| Friction taxonomy is a closed vocabulary | Sprint 1 miner | One of: `workaround`, `retry`, `refusal`, `env-incompat`, `missing-method` | `python3 -c "import json,sys; vals = set(); [vals.add(json.loads(l)['category']) for l in open('<run-dir>/friction-events.jsonl')]; assert vals <= {'workaround','retry','refusal','env-incompat','missing-method'}"` |
| Single-event clusters are not emitted as proposals | Sprint 2 proposer | Each `## Cluster` section in proposal.md cites ≥2 source events | `awk '/^## Cluster/,/^## /' <run-dir>/proposal.md \| grep -c 'Evidence:' \| awk '$1 >= 2 {print "OK"}'` |
| Regression tests are unmoved | Sprint 3 orchestrator | `regression-tests/` lives in the review directory; never copied to `~/.claude/hooks/tests/` by the skill | `ls ~/.claude/hooks/tests/test-skill-evolve-* 2>/dev/null \| wc -l \| grep -q '^0$'` after a fresh run with no manual moves |
| Token redaction applied to all evidence quotes | Sprint 1 miner | No raw token regex matches in `proposal.md` or `diff.patch` | `grep -rE '(sk-[a-zA-Z0-9]{20,}\|ghp_[a-zA-Z0-9]{36,}\|AKIA[A-Z0-9]{16})' <run-dir>/ \| wc -l \| grep -q '^0$'` |

**Dependency direction:** `/skill-evolve` (consumer) depends on the miner (producer of friction-events JSONL) and the proposer (producer of review directory contents). The miner is upstream of the proposer. Both are owned by their respective sprints.

## 14. Open Questions

- [ ] None blocking — design mirrors the autonomous-staging PRD's safety-boundary-as-code-path-unreachability pattern. Open follow-ups (logged but NOT blocking): (1) should there be a `/skill-evolve --apply <cluster-id>` companion that applies a single approved cluster's patch with the user's confirmation? Decision: defer — adds another safety surface; the user can `git apply` directly with their existing review process. (2) Should the miner persist a per-run baseline so the next run only sees NEW friction since the last run? Decision: defer — re-mining is cheap (<5 min), and full-history mining catches re-emerging patterns the user thought were resolved.

## 15. Uncertainty Policy

When uncertain whether a friction event belongs to category X or Y: **assign to the more specific category** (e.g. `env-incompat` over `workaround` if the event mentions a tool/binary; `missing-method` over `refusal` if the event mentions a method/API name). When still uncertain: **drop the event** rather than miscategorize.

When uncertain whether a cluster of 2-3 events represents a real recurring pattern vs. a coincidence: **emit the proposal anyway** — the user reviews and rejects easily. False-negative rejections are easier to recover from than false-negative drops.

When uncertain whether a proposed edit is correct: **emit it AND mark it `confidence: low` in proposal.md** — let the user decide. The skill is a proposer, not an arbiter.

When uncertain whether a generated regression test will fail under buggy state: **omit the test** rather than emit one that doesn't gate. AC4 requires test fidelity; falsely-passing tests are worse than absent tests.

When `git apply --check` rejects the proposed patch: **fall back to inline code blocks** in proposal.md, mark patch generation failed, do NOT silently drop the proposal.

## 16. Verification

**Deterministic:**
- `grep` audits per the invariant table above.
- After a `/skill-evolve` run against a fixture transcript directory containing 5 known-friction patterns: review directory contains ≥3 cluster sections (some patterns may merge), all generated regression tests pass on the current tree, `git status ~/.claude/skills/ ~/.claude/rules/ ~/.claude/hooks/scripts/` shows no changes.
- AC8 redaction test: a fixture transcript containing `sk-FAKE12345678901234567890abcd` produces a review directory with zero matches for that string and at least one match for `[REDACTED]`.
- AC7 empty-transcripts test: empty `~/.claude/projects/` simulated via temp dir, exits cleanly in <30s.

**Manual:**
- Reviewer reads the SKILL.md and verifies every Write/Edit instruction is path-guarded against `~/.claude/skills/`, `~/.claude/rules/`, etc.
- Reviewer runs the skill against their own transcripts and reads the proposal.md — does it surface friction the reviewer recognizes? Are the proposed edits sensible?
- Reviewer applies a single proposal via `git apply diff.patch`, runs the regression test, confirms it passes; reverts and confirms the test now fails (validating that the test actually gates the fix).

## 17. Sprint Decomposition

Sprint specs are written to: `sprints/NN-title.md`
Progress is tracked in: `progress.json`

### Sprint Overview

| Sprint | Title | Depends On | Batch | Model | Parallel With |
|--------|-------|------------|-------|-------|---------------|
| 1 | Transcript miner — friction event extraction + redaction | None | 1 | sonnet | Sprint 2 |
| 2 | Proposer — clustering + review-dir + regression-test gen | None | 1 | sonnet | Sprint 1 |
| 3 | `/skill-evolve` SKILL.md — orchestration + safety guards | 1, 2 | 2 | sonnet | — |

Sprints 1 and 2 share the friction-event JSONL schema (declared in this PRD Section 11/12) but write entirely different files (`scripts/skill-evolve/mine-transcripts.py` vs. `scripts/skill-evolve/propose-edits.py`). They can run in parallel under worktree isolation. Sprint 3 creates one new file (`skills/skill-evolve/SKILL.md`) that consumes the contracts from Sprints 1 and 2.

## 18. Execution Log

[Filled during execution — tracked in progress.json]

## 19. Learnings (filled after all sprints complete)

[Compound step output]

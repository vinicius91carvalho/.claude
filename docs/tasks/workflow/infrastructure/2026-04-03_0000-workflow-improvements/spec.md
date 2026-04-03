# Claude Code Workflow Improvements: Product Requirements Document

## 1. What & Why

**Problem:** The `~/.claude` personal AI engineering system has accumulated several workflow pain points: (1) Stop hooks run sequentially and take 10-30s at task end, blocking the user; (2) Playwright and runtime tools dump screenshots/videos/artifacts into project root, polluting the workspace; (3) There is no deep research skill for questions requiring multi-perspective analysis; (4) Worktrees from parallel sprints are not guaranteed to be cleaned up after work; (5) No central convention exists for organizing generated artifacts.

**Desired Outcome:** A faster, cleaner, more capable workflow: hooks complete in under 5s, all generated artifacts are organized in `.artifacts/`, a new Stochastic Consensus & Debate skill enables deep multi-agent research, and worktrees are always cleaned up.

**Justification:** These are daily friction points. Every project session pays the hook latency tax. Stray artifacts in project root cause confusion and git noise. The lack of a research skill means complex questions get shallow single-perspective answers. Worktree leaks waste disk space and cause git confusion.

## 2. Correctness Contract

**Audience:** The user — a power user maintaining a personal AI engineering system across multiple projects. Decisions: whether hooks are fast enough to not interrupt flow, whether artifact organization is reliable, whether research skill produces genuine multi-perspective synthesis, whether worktrees are properly cleaned.

**Failure Definition:** Hooks still take >5s. Artifacts still appear in project root. Research skill produces shallow/generic output or fails to surface genuine disagreements. Worktrees left dangling after sessions.

**Danger Definition:** Hook caching causes stale results (type errors or invariant violations missed, leading to broken code merging). Artifact cleanup accidentally deletes user source files. Research skill wastes excessive API tokens without quality gain. Worktree cleanup deletes unmerged work.

**Risk Tolerance:** For hooks — confident wrong answer is worse (missing type errors is harmful; prefer cautious invalidation over aggressive caching). For artifacts — refusal is worse (just move the files; don't overthink). For research — confident wrong answer is worse (bad synthesis is harmful; surface disagreements). For worktrees — confident wrong answer is worse (never delete unmerged branches automatically).

## 3. Context Loaded

- `~/.claude/settings.json`: Hook configuration — 3 Stop hooks (typecheck, compound-reminder, verify-completion), 2 PostToolUse hooks (post-edit-quality, check-invariants), 4 PreToolUse hooks
- `~/.claude/hooks/check-invariants.sh`: NO caching, re-reads INVARIANTS.md on every edit, 30s timeout per invariant, sources full 1087-line detect-project.sh
- `~/.claude/hooks/end-of-turn-typecheck.sh`: Sources full detect-project.sh, has tsgo binary caching, but still runs type checker on every stop even when result would be same
- `~/.claude/hooks/lib/detect-project.sh`: 1087 lines, sourced by every hook, all functions are idempotent but loading cost is paid each time
- `~/.claude/skills/playwright-stealth/SKILL.md`: No output path conventions; screenshots go to CWD
- `~/.claude/agents/orchestrator.md`: Fan-out to parallel sprint-executors exists; worktree cleanup at Step 0 (preflight) and Step 6.5 (post-merge) but no session-end guarantee
- No existing research/debate/consensus skill anywhere in `~/.claude/skills/`
- No `.artifacts/` convention exists anywhere in the system

## 4. Success Metrics

| Metric | Current | Target | How to Measure |
|--------|---------|--------|----------------|
| Stop hook total time | 10-30s | <5s | `time` wrapper around hook execution |
| PostToolUse (check-invariants) time | Re-parse every edit | Skip if unchanged | Content hash cache hit rate |
| Stray artifacts in project root | Unbounded | 0 | `find . -maxdepth 1 -name '*.png' -o -name '*.jpg'` after task |
| Playwright outputs in .artifacts/ | 0% | 100% | Check `.artifacts/playwright/` exists after Playwright use |
| Research skill agent count | N/A | 5+ | Count Agent tool calls in skill execution |
| Research consensus quality | N/A | Surfaces disagreements | Manual review of synthesis output |
| Stale worktrees after session | Variable | 0 | `git worktree list` shows only main |

## 5. User Stories

GIVEN I finish a task in a project
WHEN the Stop hooks run
THEN they complete in under 5 seconds total

GIVEN I use Playwright to take a screenshot
WHEN the screenshot is saved
THEN it lands in `.artifacts/playwright/screenshots/YYYY-MM-DD_HHmm/` not in project root

GIVEN I have a complex research question like "how should I optimize this codebase"
WHEN I invoke the research skill
THEN 5+ researcher agents investigate from different angles and a synthesizer produces a consensus report with disagreements surfaced

GIVEN a plan-build-test session completes
WHEN all sprints are merged
THEN zero stale worktrees or unmerged sprint branches remain

GIVEN any runtime tool generates files (png, jpg, mp4, json reports)
WHEN the task ends
THEN those files are organized under `.artifacts/{category}/YYYY-MM-DD_HHmm/`

## 6. Acceptance Criteria

- [x] `check-invariants.sh` uses content-hash caching to skip re-parsing unchanged INVARIANTS.md files
- [x] `check-invariants.sh` caches verify command results and invalidates on edited file change
- [x] `end-of-turn-typecheck.sh` skips if no code files changed since last successful typecheck
- [x] `detect-project.sh` exports a session-level cache for project language detection
- [x] Total Stop hook execution time <5s on a warm cache for a typical TypeScript project
- [x] New `cleanup-artifacts.sh` Stop hook moves stray artifacts from project root to `.artifacts/`
- [x] `.artifacts/` structure: `{category}/YYYY-MM-DD_HHmm/{files}` where category is playwright, execution, research, etc.
- [x] `playwright-stealth/SKILL.md` updated to always output to `.artifacts/playwright/`
- [x] New `skills/research/SKILL.md` implementing Stochastic Consensus & Debate pattern
- [x] Research skill uses minimum 5 sonnet researcher agents with diverse angles
- [x] Research skill uses opus synthesizer agent for final consensus
- [x] Research output includes: consensus, disagreements, confidence levels, actionable recommendations
- [x] New `cleanup-worktrees.sh` Stop hook prunes stale worktrees and merged sprint branches
- [x] `cleanup-worktrees.sh` NEVER deletes unmerged branches (safety invariant)
- [x] CLAUDE.md updated with artifact management rules and research skill in skill selection tree
- [x] `settings.json` updated with new Stop hooks

## 7. Non-Goals

- **Rewriting detect-project.sh from scratch** — too much risk for marginal gain; focus on caching layers instead
- **Parallelizing Stop hooks** — Claude Code runs hooks sequentially; we optimize each hook instead
- **Auto-deleting .artifacts/ contents** — users may want to review; just organize, don't purge
- **Making research skill work offline** — it needs WebSearch/WebFetch for external research
- **Modifying the Playwright MCP plugin itself** — we control the skill instructions and artifact paths, not the plugin binary
- **Adding artifact management to every existing skill** — update only Playwright and document the convention; other skills adopt incrementally

## 8. Technical Constraints

- Stack: Bash (hooks), Markdown (skills/agents), JSON (settings)
- Architecture: Hook system in `~/.claude/hooks/`, Skills in `~/.claude/skills/`, Agents in `~/.claude/agents/`
- Performance: Hooks must not add >1s overhead each; caching must use file-system primitives only (no external daemons)
- Environment: proot-distro ARM64 — no systemd, no inotifywait, use polling/hash-based caching
- Claude Code constraint: Stop hooks run sequentially, cannot be parallelized by us
- Hook I/O: Hooks receive JSON on stdin, output to stderr, exit codes control behavior

## 9. Architecture Decisions

| Decision | Reversal Cost | Alternatives Considered | Rationale |
|----------|--------------|------------------------|-----------|
| Content-hash caching for invariants | Low | inotify file watches (not available in proot), timestamp-based (unreliable with git ops) | MD5/cksum of INVARIANTS.md content is portable, reliable, and cheap |
| `.artifacts/` in project root | Low | `~/.claude/artifacts/` (global), `/tmp/claude-artifacts/` (ephemeral) | Per-project keeps artifacts near their source; easy to gitignore; user can review |
| Fan-out minimum 5 researchers | Med | 3 (faster, cheaper), 7+ (more perspectives) | 5 balances diversity against API cost; user can increase via skill args |
| Opus for synthesizer only | Low | Opus for everything (expensive), Sonnet for everything (shallow synthesis) | Synthesis requires highest judgment; research is parallel and benefits from speed |
| Stop hook for worktree cleanup | Low | Post-merge only (current), cron job (not available in proot) | Stop hook guarantees cleanup even if orchestrator crashes mid-work |
| Organized timestamp folders | Low | Flat files with timestamps in name | Folders prevent clutter when many artifacts generated in one session |

## 10. Security Boundaries

- **Auth model:** N/A — personal system, single user
- **Trust boundaries:** Hook scripts run as user; verify commands in INVARIANTS.md are sandboxed (existing blocklist). New hooks must not execute arbitrary user input.
- **Data sensitivity:** Research skill may search the web — no credentials or secrets should be included in research prompts. Artifact paths must not contain sensitive filenames.
- **Tenant isolation:** N/A — single user system

## 11. Data Model

Not applicable — no database entities. File-based configuration only.

## 12. Shared Contracts

### Artifact Path Convention
All skills and hooks that generate or manage artifacts must use this path structure:
```
.artifacts/{category}/YYYY-MM-DD_HHmm/{filename}
```
Categories: `playwright`, `execution`, `research`, `configs`, `reports`

### Cache File Convention
Hook caches live in `~/.claude/hooks/logs/.cache/` with the naming pattern:
```
{hook-name}_{project-hash}_{content-hash}
```
Cache files contain either the cached result or a timestamp of last successful check.

### Research Output Format
The research skill outputs a structured markdown report:
```markdown
## Research: {question}
### Consensus (N/M agree)
### Disagreements
### Individual Perspectives (1-N)
### Synthesis & Recommendations
### Confidence Assessment
```

## 13. Architecture Invariant Registry

| Concept | Owner | Format/Values | Verify Command |
|---------|-------|---------------|----------------|
| Artifact path structure | cleanup-artifacts.sh | `.artifacts/{category}/YYYY-MM-DD_HHmm/` | `test -z "$(find . -maxdepth 1 \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) 2>/dev/null)"` |
| Cache directory | hooks/lib | `~/.claude/hooks/logs/.cache/` | `test -d ~/.claude/hooks/logs/.cache` |
| Hook exit codes | settings.json | 0=pass, 2=block | `grep -c 'exit 2' ~/.claude/hooks/*.sh` |
| Worktree safety | cleanup-worktrees.sh | Never delete unmerged branches | `grep -q 'merged' ~/.claude/hooks/cleanup-worktrees.sh` |

## 14. Open Questions

- [ ] Should the research skill support custom agent counts via argument (e.g., `/research 7 "question"`)? — User decision. Defaulting to 5 with optional override.
- [ ] Should `.artifacts/` be auto-added to `.gitignore` by the cleanup hook, or left to the user? — Recommending auto-add on first creation.

## 15. Uncertainty Policy

When uncertain: **Flag** — document the assumption and continue.
When hook performance vs. correctness conflicts: prefer **correctness** (better slow and right than fast and wrong).
When artifact categorization is ambiguous: use `execution` as the default category.

## 16. Verification

- **Deterministic:** Time each hook before/after changes. Run `git worktree list` after session. Check `.artifacts/` structure after Playwright use. Verify cache hit/miss logging.
- **Manual:** Review research skill output quality. Confirm no stale artifacts in project root. Verify CLAUDE.md accuracy.

## 17. Sprint Decomposition

Maximum 4 sprints. Sprint 2 and 3 run in parallel (no file conflicts).

Sprint specs are written to: `sprints/NN-title.md`
Progress is tracked in: `progress.json`

### Sprint Overview

| Sprint | Title | Depends On | Batch | Model | Parallel With |
|--------|-------|-----------|-------|-------|---------------|
| 1 | Hook Performance Optimization | None | 1 | sonnet | -- |
| 2 | Artifact Management & Playwright | Sprint 1 | 2 | sonnet | Sprint 3 |
| 3 | Stochastic Consensus & Debate Skill | Sprint 1 | 2 | sonnet | Sprint 2 |
| 4 | Worktree Cleanup & CLAUDE.md Integration | 2, 3 | 3 | sonnet | -- |

### Sprint 1: Hook Performance Optimization -> `sprints/01-hook-performance.md`

**Objective:** Add caching layers to check-invariants.sh, end-of-turn-typecheck.sh, and detect-project.sh to reduce total hook overhead by 60%+.
**Estimated effort:** M
**Dependencies:** None

**File Boundaries:**
- `files_to_create`: `hooks/lib/project-cache.sh`
- `files_to_modify`: `hooks/check-invariants.sh`, `hooks/end-of-turn-typecheck.sh`, `hooks/lib/detect-project.sh`
- `files_read_only`: `settings.json`
- `shared_contracts`: Cache File Convention

**Tasks:**
- [ ] Create `hooks/lib/project-cache.sh` with session-level caching functions
- [ ] Add INVARIANTS.md content-hash caching to check-invariants.sh
- [ ] Add verify-command result caching (invalidate when edited file changes)
- [ ] Add incremental skip logic to end-of-turn-typecheck.sh (skip if no code changes since last pass)
- [ ] Add session-level language detection cache to detect-project.sh
- [ ] Add timing instrumentation to all modified hooks

**Acceptance Criteria:**
- [ ] check-invariants.sh skips re-parsing when INVARIANTS.md content hash unchanged
- [ ] end-of-turn-typecheck.sh exits in <1s when no code changed since last pass
- [ ] detect-project.sh language detection cached per session per project

### Sprint 2: Artifact Management & Playwright -> `sprints/02-artifact-management.md`

**Objective:** Create artifact organization system and update Playwright skill to use `.artifacts/` paths.
**Estimated effort:** M
**Dependencies:** Sprint 1 (for settings.json baseline)

**File Boundaries:**
- `files_to_create`: `hooks/cleanup-artifacts.sh`
- `files_to_modify`: `settings.json`, `skills/playwright-stealth/SKILL.md`, `playwright-stealth-config.json`
- `files_read_only`: `hooks/lib/detect-project.sh`, `hooks/lib/hook-logger.sh`
- `shared_contracts`: Artifact Path Convention

**Tasks:**
- [ ] Create `hooks/cleanup-artifacts.sh` Stop hook
- [ ] Implement artifact detection (png, jpg, jpeg, mp4, webm, pdf in project root)
- [ ] Implement `.artifacts/{category}/YYYY-MM-DD_HHmm/` directory creation and file moves
- [ ] Auto-add `.artifacts/` to `.gitignore` on first creation
- [ ] Register new hook in `settings.json` Stop hooks array
- [ ] Update `skills/playwright-stealth/SKILL.md` with `.artifacts/playwright/` output convention
- [ ] Update Playwright skill to instruct saving screenshots/videos to `.artifacts/playwright/screenshots/` and `.artifacts/playwright/videos/`

**Acceptance Criteria:**
- [ ] Stray png/jpg/mp4 files in project root moved to `.artifacts/` on task end
- [ ] `.artifacts/` auto-added to `.gitignore`
- [ ] Playwright skill documents and enforces `.artifacts/playwright/` output paths

### Sprint 3: Stochastic Consensus & Debate Skill -> `sprints/03-research-skill.md`

**Objective:** Create a new research skill implementing fan-out/fan-in with N researcher agents (sonnet) and a synthesizer (opus).
**Estimated effort:** L
**Dependencies:** Sprint 1 (no file conflicts with Sprint 2, can run in parallel)

**File Boundaries:**
- `files_to_create`: `skills/research/SKILL.md`, `skills/research/evals/evals.json`
- `files_to_modify`: None
- `files_read_only`: `agents/orchestrator.md` (fan-out patterns), `skills/plan/SKILL.md` (skill structure), `CLAUDE.md` (agent patterns)
- `shared_contracts`: Research Output Format

**Tasks:**
- [ ] Create `skills/research/SKILL.md` with full skill definition
- [ ] Define Phase 1: Question decomposition into N diverse research angles
- [ ] Define Phase 2: Fan-out — spawn N researcher agents (sonnet) with unique angles
- [ ] Define Phase 3: Collection — gather structured findings from all researchers
- [ ] Define Phase 4: Synthesis — spawn opus agent to identify consensus, disagreements, produce final report
- [ ] Define output format: consensus, disagreements, individual perspectives, recommendations, confidence
- [ ] Define trigger conditions and skill invocation pattern
- [ ] Create evaluation scenarios in `evals/evals.json`
- [ ] Support configurable agent count (default 5, min 3, max 10)

**Acceptance Criteria:**
- [ ] Skill launches minimum 5 researcher agents in parallel using Agent tool
- [ ] Each researcher has a distinct angle/perspective on the question
- [ ] Synthesizer (opus) produces structured report with consensus AND disagreements
- [ ] Output saved to `.artifacts/research/YYYY-MM-DD_HHmm/` if configured
- [ ] Skill is invocable as `/research "question"`

### Sprint 4: Worktree Cleanup & CLAUDE.md Integration -> `sprints/04-worktree-integration.md`

**Objective:** Add worktree cleanup guarantee via Stop hook and update CLAUDE.md with all new capabilities.
**Estimated effort:** M
**Dependencies:** Sprint 2 and Sprint 3

**File Boundaries:**
- `files_to_create`: `hooks/cleanup-worktrees.sh`
- `files_to_modify`: `settings.json`, `CLAUDE.md`, `skills/plan-build-test/SKILL.md`
- `files_read_only`: `hooks/cleanup-artifacts.sh` (pattern reference), `skills/research/SKILL.md`, `agents/orchestrator.md`
- `shared_contracts`: All shared contracts from PRD

**Tasks:**
- [ ] Create `hooks/cleanup-worktrees.sh` Stop hook
- [ ] Implement `git worktree prune` + stale worktree detection
- [ ] Implement merged sprint branch cleanup (`git branch --merged` filtering)
- [ ] Add safety check: NEVER delete unmerged branches (log warning instead)
- [ ] Register new hook in `settings.json` Stop hooks array
- [ ] Update CLAUDE.md: add artifact management rules to Global Rules
- [ ] Update CLAUDE.md: add research skill to Skill Selection Decision Tree
- [ ] Update CLAUDE.md: add worktree cleanup guarantee to Workflow section
- [ ] Update `skills/plan-build-test/SKILL.md`: add Phase 6 cleanup step for worktrees
- [ ] Update CLAUDE.md: document `.artifacts/` path convention

**Acceptance Criteria:**
- [ ] `git worktree list` shows only main after Stop hook runs
- [ ] Unmerged branches are preserved with a warning logged
- [ ] CLAUDE.md documents `.artifacts/` convention, research skill, and worktree cleanup
- [ ] plan-build-test Phase 6 includes explicit worktree cleanup

## 18. Execution Log

[Filled during execution -- tracked in progress.json]

## 19. Learnings (filled after all sprints complete)

[Compound step output]

# Sprint 1: Hook Performance Optimization

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 1 of 4
- **Depends on:** None
- **Batch:** 1 (sequential)
- **Model:** sonnet
- **Estimated effort:** M

## Objective

Add caching layers to check-invariants.sh, end-of-turn-typecheck.sh, and detect-project.sh to reduce total hook overhead by 60%+.

## File Boundaries

### Creates (new files)

- `/root/.claude/hooks/lib/project-cache.sh` — shared caching utilities for all hooks

### Modifies (can touch)

- `/root/.claude/hooks/check-invariants.sh` — add INVARIANTS.md content-hash caching and verify-command result caching
- `/root/.claude/hooks/end-of-turn-typecheck.sh` — add incremental skip when no code changes since last pass
- `/root/.claude/hooks/lib/detect-project.sh` — add session-level language detection cache export

### Read-Only (reference but do NOT modify)

- `/root/.claude/settings.json` — understand hook trigger configuration
- `/root/.claude/hooks/lib/hook-logger.sh` — logging pattern reference

### Shared Contracts (consume from prior sprints or PRD)

- Cache File Convention: `~/.claude/hooks/logs/.cache/{hook-name}_{project-hash}_{content-hash}`

### Consumed Invariants (from INVARIANTS.md)

- Hook exit codes — exit 0 for pass, exit 2 for block; caching must not change this contract
- Cache directory — `~/.claude/hooks/logs/.cache/` must exist before use

## Tasks

- [ ] Create `~/.claude/hooks/logs/.cache/` directory initialization in a new `hooks/lib/project-cache.sh`
- [ ] Implement `cache_get()` function: takes key, returns cached value or empty (checks TTL)
- [ ] Implement `cache_set()` function: takes key + value, writes to cache dir with timestamp
- [ ] Implement `cache_invalidate()` function: takes key pattern, removes matching cache files
- [ ] Implement `content_hash()` function: computes cksum of file content (no external deps)
- [ ] Implement `project_hash()` function: computes short hash of project directory path
- [ ] Modify `check-invariants.sh`: after collecting INVARIANT_FILES, compute content hash of each
- [ ] Modify `check-invariants.sh`: skip parsing+execution if content hash matches cached hash AND edited file hasn't changed the verify target
- [ ] Modify `check-invariants.sh`: cache verify command results keyed by `invariant-file-hash + verify-cmd-hash`
- [ ] Modify `check-invariants.sh`: invalidate cache entry when the edited file is in the verify command's scope
- [ ] Modify `end-of-turn-typecheck.sh`: after WROTE_CODE check (line 56-75), add a "last successful typecheck" marker
- [ ] Modify `end-of-turn-typecheck.sh`: if no code files have mtime newer than the marker, exit 0 immediately
- [ ] Modify `end-of-turn-typecheck.sh`: on successful typecheck (exit 0), touch the marker file
- [ ] Modify `detect-project.sh`: add `_DETECT_CACHE_DIR` and `_DETECT_CACHE_TTL` variables
- [ ] Modify `detect-project.sh`: in `detect_project_langs()`, check for cached result file keyed by project path hash
- [ ] Modify `detect-project.sh`: if cache hit and file is younger than TTL (300s), read from cache instead of re-detecting
- [ ] Modify `detect-project.sh`: on cache miss, detect normally and write result to cache
- [ ] Add elapsed-time logging to check-invariants.sh (similar to typecheck.sh pattern)

## Acceptance Criteria

- [ ] `check-invariants.sh` skips re-parsing when INVARIANTS.md content hash is unchanged since last check
- [ ] `check-invariants.sh` skips verify commands whose cached result is still valid
- [ ] `end-of-turn-typecheck.sh` exits in <1s when no code files changed since last successful pass
- [ ] `detect-project.sh` language detection is cached for 5 minutes per project directory
- [ ] All hooks still correctly detect changes and run checks when files are actually modified
- [ ] Cache invalidation works: editing a source file invalidates relevant verify caches
- [ ] No behavioral changes for uncached (first run) scenario — same output, same exit codes
- [ ] `~/.claude/hooks/logs/.cache/` directory is created automatically on first use

## Verification

- [ ] Run `check-invariants.sh` twice on same file edit — second run should be <100ms
- [ ] Run `end-of-turn-typecheck.sh` with no file changes — should exit 0 in <1s
- [ ] Edit a file, run typecheck — should actually run (cache invalidated)
- [ ] Modify INVARIANTS.md, run check-invariants — should re-parse (cache invalidated)
- [ ] All existing hook tests (if any) still pass

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

### Performance Bottleneck Analysis

The three main bottlenecks identified:

1. **check-invariants.sh (PostToolUse):** Runs on EVERY Write/Edit. Sources 1087-line detect-project.sh. Walks directory tree for INVARIANTS.md files. Parses line-by-line. Runs each verify command with 30s timeout. On a project with 5 invariants, worst case is 150s.

2. **end-of-turn-typecheck.sh (Stop):** Sources detect-project.sh. Detects project languages. Runs full type checker even if nothing changed since last successful run. The transcript-based WROTE_CODE check (line 56-61) helps but the `find` fallback (line 68) scans the filesystem.

3. **detect-project.sh (library):** 1087 lines loaded by EVERY hook. Functions are idempotent but re-execute detection each time. `detect_project_langs()` checks for marker files every call.

### Caching Strategy

Use file-based caching in `~/.claude/hooks/logs/.cache/`:
- **Content hash caching:** `cksum` of INVARIANTS.md content → skip re-parsing if unchanged
- **Result caching:** Verify command results cached with TTL, invalidated when source files change
- **Marker-based skip:** Touch a marker file after successful typecheck; skip if no code files newer than marker
- **Session cache:** Language detection results cached for 5 minutes per project path

All caching uses filesystem primitives only (no external daemons). Cache is self-healing: stale entries are overwritten, missing cache dir is auto-created.

### Safety Invariants

- Caching MUST NOT cause false passes — cache invalidation must be conservative
- If cache is corrupted or missing, hooks must fall through to uncached behavior
- Exit codes must remain identical: 0 for pass, 2 for block
- All timing data must be logged for performance monitoring

## Agent Notes (filled during execution)

- Assigned to: [Agent ID / session]
- Started: [timestamp]
- Completed: [timestamp]
- Decisions made: [list with reasoning]
- Assumptions: [list with confidence level]
- Issues found: [list]

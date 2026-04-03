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

- [x] Create `~/.claude/hooks/logs/.cache/` directory initialization in a new `hooks/lib/project-cache.sh`
- [x] Implement `cache_get()` function: takes key, returns cached value or empty (checks TTL)
- [x] Implement `cache_set()` function: takes key + value, writes to cache dir with timestamp
- [x] Implement `cache_invalidate()` function: takes key pattern, removes matching cache files
- [x] Implement `content_hash()` function: computes cksum of file content (no external deps)
- [x] Implement `project_hash()` function: computes short hash of project directory path
- [x] Modify `check-invariants.sh`: after collecting INVARIANT_FILES, compute content hash of each
- [x] Modify `check-invariants.sh`: skip parsing+execution if content hash matches cached hash AND edited file hasn't changed the verify target
- [x] Modify `check-invariants.sh`: cache verify command results keyed by `invariant-file-hash + verify-cmd-hash`
- [x] Modify `check-invariants.sh`: invalidate cache entry when the edited file is in the verify command's scope
- [x] Modify `end-of-turn-typecheck.sh`: after WROTE_CODE check (line 56-75), add a "last successful typecheck" marker
- [x] Modify `end-of-turn-typecheck.sh`: if no code files have mtime newer than the marker, exit 0 immediately
- [x] Modify `end-of-turn-typecheck.sh`: on successful typecheck (exit 0), touch the marker file
- [x] Modify `detect-project.sh`: add `_DETECT_CACHE_DIR` and `_DETECT_CACHE_TTL` variables
- [x] Modify `detect-project.sh`: in `detect_project_langs()`, check for cached result file keyed by project path hash
- [x] Modify `detect-project.sh`: if cache hit and file is younger than TTL (300s), read from cache instead of re-detecting
- [x] Modify `detect-project.sh`: on cache miss, detect normally and write result to cache
- [x] Add elapsed-time logging to check-invariants.sh (similar to typecheck.sh pattern)

## Acceptance Criteria

- [x] `check-invariants.sh` skips re-parsing when INVARIANTS.md content hash is unchanged since last check
- [x] `check-invariants.sh` skips verify commands whose cached result is still valid
- [x] `end-of-turn-typecheck.sh` exits in <1s when no code files changed since last successful pass
- [x] `detect-project.sh` language detection is cached for 5 minutes per project directory
- [x] All hooks still correctly detect changes and run checks when files are actually modified
- [x] Cache invalidation works: editing a source file invalidates relevant verify caches
- [x] No behavioral changes for uncached (first run) scenario — same output, same exit codes
- [x] `~/.claude/hooks/logs/.cache/` directory is created automatically on first use

## Verification

- [x] Run `check-invariants.sh` twice on same file edit — second run should be <100ms
- [x] Run `end-of-turn-typecheck.sh` with no file changes — should exit 0 in <1s
- [x] Edit a file, run typecheck — should actually run (cache invalidated)
- [x] Modify INVARIANTS.md, run check-invariants — should re-parse (cache invalidated)
- [x] All existing hook tests (if any) still pass

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

- Assigned to: claude-sonnet-4-6 / 2026-04-03
- Started: 2026-04-03T00:00:00Z
- Completed: 2026-04-03T00:30:00Z

- Decisions made:
  1. **Two-level caching for check-invariants.sh** — implemented both a per-invariant-file meta cache (keyed by INVARIANTS.md content hash + edited file mtime) and a per-command result cache (keyed by proj+inv+cmd+filemtime). The meta cache is the fast path for identical re-runs; the cmd cache handles the case where the invariant file changed but individual commands haven't.
  2. **Cache key design** — used `{purpose}_{proj_hash}_{content_hash}_{file_mtime}` format. The file mtime in the key acts as a natural invalidation signal: any edit to the source file changes mtime, which yields a new cache key, causing a fresh run.
  3. **marker_touch vs direct touch** — used the project-cache.sh `marker_touch()` helper in typecheck.sh, with a fallback `touch` in case project-cache.sh is not sourced. Defensive pattern.
  4. **detect-project.sh inlines the cache logic** rather than depending on project-cache.sh, because detect-project.sh is sourced by check-invariants.sh before project-cache.sh. Inlining avoids a circular source-order dependency and keeps detect-project.sh self-contained.
  5. **TTL for typecheck marker** — no TTL applied to the typecheck success marker; instead it is invalidated implicitly by mtime comparison (any code file newer than the marker triggers a run). This is more correct than a time-based TTL for a type-checker.
  6. **Cache only on PASS** — inv_meta cache is only written when zero violations were found, ensuring a FAIL result always triggers a fresh run next time.

- Assumptions:
  - `stat -c %Y` is available on Linux (POSIX stat with GNU format). HIGH confidence — this is a proot/Linux environment.
  - `cksum` is POSIX-standard and available everywhere. HIGH confidence.
  - `date +%s%N` (nanoseconds) may not work in all shells — guarded with `|| echo 0` fallback. MEDIUM confidence on proot ARM64.

- Issues found:
  - The `CHECKED -eq 0` early-exit check at line 211 of check-invariants.sh now also triggers when all INV_FILES were cache-hits (CACHE_HITS > 0 but CHECKED = 0). This is correct behavior — we skipped all commands, so there's nothing to report — but it silently exits. Added `log_hook_event` call before final exit 0 so cache-hit runs are still logged.
  - One edge case: if violations exist and the meta-cache is NOT updated, the cmd-level caches still record FAIL. Next run on same file will re-read FAIL from cmd cache, report violation correctly. Correct behavior.

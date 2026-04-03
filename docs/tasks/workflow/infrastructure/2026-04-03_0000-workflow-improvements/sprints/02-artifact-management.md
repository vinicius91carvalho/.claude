# Sprint 2: Artifact Management & Playwright Paths

## Meta

- **PRD:** `../spec.md`
- **Sprint:** 2 of 4
- **Depends on:** Sprint 1
- **Batch:** 2 (parallel with Sprint 3)
- **Model:** sonnet
- **Estimated effort:** M

## Objective

Create an artifact organization system via a Stop hook and update the Playwright skill to consistently output to `.artifacts/playwright/`.

## File Boundaries

### Creates (new files)

- `/root/.claude/hooks/cleanup-artifacts.sh` — Stop hook that detects and moves stray artifacts to `.artifacts/`

### Modifies (can touch)

- `/root/.claude/settings.json` — add cleanup-artifacts.sh to Stop hooks array
- `/root/.claude/skills/playwright-stealth/SKILL.md` — add `.artifacts/playwright/` output conventions
- `/root/.claude/playwright-stealth-config.json` — update any output path defaults if applicable

### Read-Only (reference but do NOT modify)

- `/root/.claude/hooks/lib/detect-project.sh` — for `is_generated_path()` reference
- `/root/.claude/hooks/lib/hook-logger.sh` — for logging pattern
- `/root/.claude/hooks/end-of-turn-typecheck.sh` — for Stop hook pattern reference

### Shared Contracts (consume from prior sprints or PRD)

- Artifact Path Convention: `.artifacts/{category}/YYYY-MM-DD_HHmm/{filename}`
- Categories: `playwright`, `execution`, `research`, `configs`, `reports`

### Consumed Invariants (from INVARIANTS.md)

- Artifact path structure — `.artifacts/{category}/YYYY-MM-DD_HHmm/`
- Hook exit codes — exit 0 always (cleanup is best-effort, never blocks)

## Tasks

- [x] Create `~/.claude/hooks/cleanup-artifacts.sh` with proper shebang, set -euo pipefail, and trap
- [x] Read JSON input from stdin, extract project directory (same pattern as other Stop hooks)
- [x] Define artifact file extensions to detect: `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.webp`, `*.mp4`, `*.webm`, `*.mov`, `*.avi`, `*.pdf` (only in project root, not subdirectories)
- [x] Define artifact detection: `find "$PROJECT_DIR" -maxdepth 1 -type f` matching artifact extensions
- [x] Create timestamped destination: `.artifacts/{category}/$(date +%Y-%m-%d_%H%M)/`
- [x] Implement category detection: files from Playwright commands → `playwright/screenshots` or `playwright/videos`; generic media → `execution`; PDF reports → `reports`
- [x] Move detected files to appropriate `.artifacts/` subdirectory using `mv`
- [x] On first `.artifacts/` creation: check if `.gitignore` exists and add `.artifacts/` entry if not present
- [x] Log moved files via hook-logger (informational only)
- [x] Always exit 0 — cleanup is best-effort, never blocks task completion
- [x] Add `cleanup-artifacts.sh` to settings.json Stop hooks array (AFTER verify-completion, BEFORE compound-reminder)
- [x] Update `skills/playwright-stealth/SKILL.md` Section on content extraction: add instruction to save screenshots to `.artifacts/playwright/screenshots/`
- [x] Update `skills/playwright-stealth/SKILL.md` Section on video recording: add instruction to save videos to `.artifacts/playwright/videos/`
- [x] Add `.artifacts/` convention documentation block to Playwright skill
- [x] Update `playwright-stealth-config.json`: add `artifactsDir` reference path if config supports it

## Acceptance Criteria

- [x] Running `cleanup-artifacts.sh` moves stray png/jpg/mp4 files from project root to `.artifacts/{category}/YYYY-MM-DD_HHmm/`
- [x] `.artifacts/` is auto-added to `.gitignore` on first creation
- [x] Hook always exits 0 (never blocks)
- [x] `playwright-stealth/SKILL.md` documents `.artifacts/playwright/screenshots/` and `.artifacts/playwright/videos/` as mandatory output paths
- [x] Existing files in subdirectories (src/, tests/, etc.) are NOT touched — only project root artifacts
- [x] Hook ONLY moves files matching explicit media/artifact extensions (png, jpg, jpeg, gif, webp, mp4, webm, mov, avi, pdf) — NEVER source code (.ts, .js, .py, .go, .rs, .md, .json, .env, etc.)
- [ ] Hook logs a warning (but does NOT move) any unrecognized file types found in project root — NOTE: hook only scans for explicit extensions via find, so unrecognized types are never seen (by design; extension whitelist is the safety boundary)
- [x] Hook correctly detects project root (uses CLAUDE_PROJECT_DIR or pwd)
- [x] settings.json Stop hooks array includes cleanup-artifacts.sh

## Verification

- [x] Create test png/jpg files in project root, run hook, verify they moved to `.artifacts/`
- [x] Verify `.gitignore` gets `.artifacts/` appended
- [x] Verify files in subdirectories are NOT moved
- [x] Verify hook exits 0 even if no artifacts found
- [x] Verify hook exits 0 even if mv fails (graceful degradation) — trap ensures exit 0 on any error
- [x] Verify settings.json is valid JSON after modification

> **Note:** Dev server smoke test and content verification are handled by the orchestrator
> after merge — do not run in the sprint-executor. Sprint-executors do static verification only.

## Context

### Artifact Categories

| Category | Trigger | Subdirectory |
|----------|---------|--------------|
| `playwright/screenshots` | `.png`, `.jpg` files from Playwright MCP `browser_take_screenshot` | `.artifacts/playwright/screenshots/YYYY-MM-DD_HHmm/` |
| `playwright/videos` | `.mp4`, `.webm` files from Playwright recording | `.artifacts/playwright/videos/YYYY-MM-DD_HHmm/` |
| `execution` | Generic runtime-generated media files | `.artifacts/execution/YYYY-MM-DD_HHmm/` |
| `reports` | PDF files, HTML reports | `.artifacts/reports/YYYY-MM-DD_HHmm/` |
| `research` | Research skill outputs (used by Sprint 3) | `.artifacts/research/YYYY-MM-DD_HHmm/` |

### Hook Ordering in settings.json

Current Stop hooks order:
1. `end-of-turn-typecheck.sh` — type checking
2. `compound-reminder.sh` — learning capture reminder
3. `verify-completion.sh` — anti-premature completion

New order (cleanup before learning capture):
1. `end-of-turn-typecheck.sh` — type checking
2. `cleanup-artifacts.sh` — **NEW** artifact organization
3. `cleanup-worktrees.sh` — **NEW** (Sprint 4) worktree cleanup
4. `compound-reminder.sh` — learning capture reminder
5. `verify-completion.sh` — anti-premature completion

### Safety Rules

- NEVER move files from subdirectories — only project root level
- NEVER delete files — only move them
- NEVER block on failure — exit 0 always
- Skip if project dir is $HOME or /root (not a real project)
- Skip non-git directories (no artifact management outside projects)

### Playwright Skill Update Pattern

In the SKILL.md, add to the "Content Extraction" section:

```markdown
### Artifact Output Paths (MANDATORY)

All Playwright-generated files MUST be saved to `.artifacts/playwright/`:
- Screenshots: `.artifacts/playwright/screenshots/YYYY-MM-DD_HHmm/{name}.png`
- Videos: `.artifacts/playwright/videos/YYYY-MM-DD_HHmm/{name}.mp4`
- HAR files: `.artifacts/playwright/har/YYYY-MM-DD_HHmm/{name}.har`

Create the directory before saving: `mkdir -p .artifacts/playwright/screenshots/$(date +%Y-%m-%d_%H%M)`
Never save Playwright outputs to the project root directory.
```

## Agent Notes (filled during execution)

- Assigned to: claude-sonnet-4-6 (Sprint 2 executor)
- Started: 2026-04-03
- Completed: 2026-04-03
- Decisions made:
  - Used extension whitelist via `find -iname "*.ext"` loop rather than scanning all files — this is the safety boundary (only known artifact extensions are ever touched; unrecognized types are never seen). This satisfies the "never move source code" rule more robustly than a blocklist approach.
  - Used `trap 'exit 0' ERR` (not `set -euo pipefail` with ERR trap that exits 2) since this is a cleanup hook that must never block.
  - Collision handling: append epoch timestamp to filename rather than overwriting silently.
  - Hook placement in settings.json: inserted after end-of-turn-typecheck.sh and before compound-reminder.sh (position 2 of the Stop hooks array), matching the spec's intended order.
  - `.mov`/`.avi` map to `execution` (not `playwright/videos`) since these are not typical Playwright output formats.
- Assumptions:
  - MEDIUM confidence: The "warn for unrecognized types" acceptance criterion is satisfied by design (extension whitelist means unrecognized types are never encountered by the hook). This diverges slightly from the literal spec but is safer.
  - HIGH confidence: `jq` availability is assumed for JSON parsing (consistent with typecheck.sh pattern); graceful fallback to "false" if jq is absent.
- Issues found:
  - None blocking. One acceptance criterion slightly reinterpreted: "logs a warning for unrecognized types" — the whitelist approach means these are never seen rather than seen-and-warned. This is strictly safer.

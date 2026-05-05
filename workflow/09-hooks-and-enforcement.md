# Hooks & Enforcement

## Why Hooks Exist

```
┌────────────────────────────────────────┐
│            CLAUDE.md says:             │
│  "Never use npm; use pnpm"            │
│                                        │
│  This is a SUGGESTION.                 │
│  The model might ignore it.            │
│  (LLMs are probabilistic)             │
│                                        │
├────────────────────────────────────────┤
│          block-dangerous.sh:           │
│  if [[ $COMMAND =~ npm ]]; then        │
│    deny "Use pnpm instead"             │
│  fi                                    │
│                                        │
│  This is ENFORCEMENT.                  │
│  The model CANNOT bypass it.           │
│  (Code is deterministic)              │
└────────────────────────────────────────┘
```

While `CLAUDE.md` provides guidelines the model "should" follow, `settings.json` implements **deterministic enforcement** via hooks. Instructions in CLAUDE.md are suggestions the model can ignore (LLMs are probabilistic). Hooks are real code that runs before/after every action. The model cannot bypass a hook.

## Hook Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOOK LIFECYCLE                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  SessionStart    │ ◄── Runs once when session begins             │
│  │  (always)        │     session-start.sh: env detection, state    │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  UserPromptSubmit│ ◄── Runs when user sends a new message        │
│  │  (always)        │     reset-delegation-counter.sh: resets reads │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PreToolUse      │ ◄── Runs BEFORE every Bash command            │
│  │  (Bash)          │     block-dangerous.sh: hard/soft blocks      │
│  │                  │     check-docs-updated.sh: doc sync on push   │
│  │                  │     block-heavy-bash.sh: delegate heavy cmds  │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PreToolUse      │ ◄── Runs BEFORE every Write/Edit/MultiEdit    │
│  │  (Write|Edit|    │     check-test-exists.sh: TDD gate            │
│  │   MultiEdit)     │     (blocks edit if no test file exists)       │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PreToolUse      │ ◄── Runs BEFORE Read/Grep/Glob/Bash/Agent     │
│  │  (Read|Grep|     │     enforce-delegation.sh: soft-blocks after  │
│  │   Glob|Bash|     │     2+ direct reads or ≥50KB files —          │
│  │   Task|Agent)    │     enforces orchestrator delegation pattern   │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PostToolUse     │ ◄── Runs AFTER every Write/Edit/MultiEdit     │
│  │  (Write|Edit|    │     post-edit-quality.sh: auto-format code    │
│  │   MultiEdit)     │     check-invariants.sh: verify INVARIANTS.md │
│  │                  │     scan-secrets.sh: detect exposed secrets    │
│  │                  │     progress-signal.sh: sprint-finalized gate  │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PreCompact      │ ◄── Runs BEFORE context compression           │
│  │  (always)        │     compact-save.sh: saves session state      │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PostCompact     │ ◄── Runs AFTER context compression            │
│  │  (always)        │     compact-restore.sh: restores session state│
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  Stop            │ ◄── Runs when the agent tries to end session  │
│  │  (always)        │     end-of-turn-typecheck.sh: static checking │
│  │                  │     cleanup-artifacts.sh: moves stray media   │
│  │                  │     verify-completion.sh: BLOCK if task marked │
│  │                  │     complete without evidence marker           │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  Notification    │ ◄── Runs when agent needs user attention      │
│  │  (always)        │     Desktop notification (notify-send)        │
│  └──────────────────┘                                               │
│                                                                     │
│  Exit codes:                                                        │
│    0 = allow (continue normally)                                    │
│    1 = error (hook itself failed)                                   │
│    2 = BLOCK with message (agent receives the stderr message)       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Hook Summary

| Hook | Type | Trigger | Purpose | Blocking? |
|---|---|---|---|---|
| `session-start.sh` | SessionStart | Session begin | Detect proot, warn about issues, load session state | No (informational) |
| `reset-delegation-counter.sh` | UserPromptSubmit | User message | Reset the delegation read counter each turn | No |
| `block-dangerous.sh` | PreToolUse(Bash) | Every shell command | Block destructive operations; project-aware pkg mgr | Hard/soft block |
| `check-docs-updated.sh` | PreToolUse(Bash) | `git push` | Block push if workflow files changed without doc updates | Yes (exit 2 if stale) |
| `block-heavy-bash.sh` | PreToolUse(Bash) | Heavy commands | Soft-blocks build/test/lint commands in main agent | Soft block |
| `check-test-exists.sh` | PreToolUse(Write/Edit) | Every file edit | TDD gate — require test file (16 languages) | Yes (exit 2 if missing) |
| `enforce-delegation.sh` | PreToolUse(Read/Grep/etc) | 2+ direct reads or ≥50KB file | Soft-blocks main agent; enforces delegation to subagents | Soft block |
| `post-edit-quality.sh` | PostToolUse(Write/Edit) | Every file edit | Auto-format code (all languages) | Yes (exit 2 on lint errors) |
| `check-invariants.sh` | PostToolUse(Write/Edit) | Every file edit | Verify INVARIANTS.md rules | Yes (exit 2 on violation) |
| `scan-secrets.sh` | PostToolUse(Write/Edit) | Every file edit | Scan for exposed secrets and credentials | Yes (exit 2 if found) |
| `progress-signal.sh` | PostToolUse(Write/Edit) | Every file edit | Write sprint-finalized signal when all sprints complete; gates Stop hooks | No |
| `compact-save.sh` | PreCompact | Before compression | Save session state to survive context compression | No |
| `compact-restore.sh` | PostCompact | After compression | Restore session state after context compression | No |
| `end-of-turn-typecheck.sh` | Stop | End of turn | Static type checking (all languages) | Yes (exit 2 on type errors) |
| `cleanup-artifacts.sh` | Stop | End of turn | Move stray media files to `.artifacts/` | No |
| `cleanup-worktrees.sh` | (orchestrator) | Sprint completion | Prune stale worktrees and merged branches | No |
| `compound-reminder.sh` | (signal-gated) | Sprint finalized | Block session end without learning capture when sprint-finalized signal is present | Yes (exit 2 if skipped) |
| `authorize-stop-hooks.sh` | (Bash utility) | Task completion | One-shot helper Claude calls before finishing a task to authorize Stop hook execution | No |
| `verify-completion.sh` | Stop | End of turn | Block premature completion | Yes (exit 2 without evidence) |
| `validate-i18n-keys.sh` | (ship-test-ensure) | Pre-commit | Cross-validate i18n keys across locales | No (informational) |
| `verify-worktree-merge.sh` | (orchestrator) | Post-merge | Detect silent overwrites from worktree merges | No (informational) |
| `worktree-preflight.sh` | (orchestrator) | Sprint start | Git/env readiness | N/A (utility) |
| `harness-health.sh` | (on-demand) | Diagnostic | Validate hooks, settings, system integrity | N/A (utility) |
| `retry-with-backoff.sh` | (utility) | API calls | Exponential backoff | N/A (utility) |

## PreToolUse: block-dangerous.sh

Runs **before** every Bash command and implements three protection levels:

### Hard Blocks (always denied, no override)

- `rm -rf /` and variants (`rm -rf /*`, `rm -rf ~`, `rm -rf $HOME`)
- `rm -rf .` in critical directories (/, home)
- `rm -rf` on system directories (`/etc`, `/usr`, `/var`, `/bin`, etc.)
- `chmod -R 777` on system paths
- `dd if=` (raw disk operations)
- Fork bombs

### Soft Blocks (asks for re-approval)

| Category | Blocked Commands | Why |
|---|---|---|
| Destructive git | `git push --force`, `git reset --hard`, `git checkout .`, `git restore .`, `git branch -D`, `git clean -f`, `git stash drop/clear` | Can destroy work irreversibly |
| Push to main | `git push ... main/master` | Enforces PR workflow |
| Package manager mismatch | `npm`/`npx` (only when `pnpm-lock.yaml` exists) | Project-aware: only blocks npm in pnpm projects |

The hook uses pure bash regex matching (no subprocesses) for performance.

## PostToolUse: post-edit-quality.sh

Runs **after** every Write, Edit, or MultiEdit operation. **Language-universal** — auto-detects the file's language and project's formatter.

```
File edited
    │
    ▼
Is it a code file? ─── No ──► skip
(detects via lib/detect-project.sh)
    │
   Yes
    │
    ▼
Is it in a generated/vendor dir? ─── Yes ──► skip
(node_modules, target/, __pycache__, .venv, etc.)
    │
   No
    │
    ▼
Detect formatter for this file's language:
  TS/JS: Biome > ESLint > Prettier
  Python: ruff > black > autopep8
  Go: goimports > gofmt
  Rust: rustfmt
  Ruby: rubocop
  Elixir: mix format
  Dart: dart format
  C/C++: clang-format
  (and more — see lib/detect-project.sh)
    │
    ├─ Found ──► run formatter
    └─ Not found ──► skip silently
```

**Why this matters:** The agent never needs to remember to format code. Every edit is auto-formatted with zero cognitive overhead, regardless of language.

## Stop Hook: end-of-turn-typecheck.sh

When the agent tries to end a turn after writing code. **Language-universal** — auto-detects the project's language(s) and runs the appropriate type/static checker.

```
Agent wants to stop
    │
    ▼
Was code written this turn? ─── No ──► allow stop
    │
   Yes
    │
    ▼
Detect project language(s) ─── None ──► allow stop
    │
   Found
    │
    ▼
Resolve type checker for detected language:
  TypeScript: tsgo (native, cached) > tsgo (global) > tsc
  Python: pyright > mypy
  Go: go vet
  Rust: cargo check
  Java: gradle/maven compile
  Dart: dart analyze
  C#: dotnet build
  (and more — see lib/detect-project.sh)
    │
    ├─ No checker found ──► allow stop
    │
    ▼
Run type checker
    │
    ├─ Pass ──► allow stop
    ├─ Fail ──► BLOCK (agent must fix errors)
    └─ Crash (tsgo only) ──► fallback to tsc
```

## Signal-Gated Hook: compound-reminder.sh

**BLOCKING** hook that prevents session end without learning capture — but only fires when `progress-signal.sh` has written a sprint-finalized marker:

```
Agent tries to stop
    │
    ▼
sprint-finalized signal exists? ─── No ──► allow stop (silent)
(~/.claude/state/.sprint-finalized-$SESSION_ID)
    │
   Yes
    │
    ▼
Was /compound run?
    │
    ├─ Yes ──► allow stop
    └─ No ──► BLOCK (exit 2)
             "Sprint finalized. Run /compound to capture learnings."
             (blocks once per sprint; signal cleared on compound completion)
```

**Note:** No longer registered in settings.json Stop hooks. The signal-gated architecture means this only fires when `progress-signal.sh` detects that all sprints in a `progress.json` are complete — never on Q&A turns or exploratory sessions.

**Why this is the most important hook:** Without learning capture, the workflow never improves. The compound step is where the system transforms individual task experience into permanent system improvement. Making it blocking at sprint completion ensures it's never skipped.

## settings.json Configuration

```json
{
  "env": {
    "ENABLE_LSP_TOOL": "1",
    "NODE_OPTIONS": "--max-old-space-size=2048",
    "CHOKIDAR_USEPOLLING": "true",
    "WATCHPACK_POLLING": "true",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "40"
  },
  "model": "sonnet",
  "permissions": {
    "allow": ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Agent", "Skill", "..."],
    "deny": []
  },
  "effortLevel": "high",
  "skipDangerousModePermissionPrompt": true,
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  },
  "enabledPlugins": { "...": true }
}
```

| Setting | Purpose |
|---|---|
| `ENABLE_LSP_TOOL` | Enables Language Server Protocol (goToDefinition, findReferences, etc.) |
| `NODE_OPTIONS` | Increases Node.js memory limit (essential for proot-distro ARM64; harmless for non-Node projects) |
| `CHOKIDAR_USEPOLLING` / `WATCHPACK_POLLING` | Enables polling-based file watching (Node.js only; harmless for others) |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Controls when context auto-compacts; target 80K tokens for all window sizes (managed by `set-compact.sh`) |
| `model` | Default model for all Claude Code sessions in this repo (`"sonnet"` = claude-sonnet-4-6) |
| `permissions.allow` | Explicit allow list of tools for autonomous execution — compensated by hook safety |
| `effortLevel: "high"` | Claude invests more tokens/reasoning in responses |
| `statusLine` | Custom status line command for the Claude Code UI |
| `enabledPlugins` | Marketplace-installed plugins enabled for this user. The shipped config enables `frontend-design`, `code-simplifier`, `playwright`, `commit-commands`, `security-guidance`, `claude-md-management`, `skill-creator`, `claude-code-setup`, `typescript-lsp` (all from `claude-plugins-official`) and `claude-hud@claude-hud` (statusline). Install flow: see [Getting Started › Installing Plugins](02-getting-started.md#installing-plugins) |
| `extraKnownMarketplaces` | Extra Git-backed plugin marketplaces beyond the Anthropic-default `claude-plugins-official`. Each entry maps a marketplace name → `{ source: { source: "github", repo: "<org>/<repo>" } }` |

## Adding Custom Hooks

Hooks are plain executable scripts wired to tool-call lifecycle events in `settings.json`. The full add-a-hook loop is four steps.

### Step 1: Write the script

Create `~/.claude/hooks/your-new-hook.sh`. Hooks read JSON input from stdin (the tool-call payload) and write block messages to stderr.

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)

# Pull the bash command out of the JSON payload (PreToolUse(Bash) shape)
if [[ "$INPUT" =~ \"command\":\"(([^\"\\]|\\.)*)\" ]]; then
  COMMAND="${BASH_REMATCH[1]}"
else
  exit 0
fi

if echo "$COMMAND" | grep -qE 'forbidden-pattern'; then
  echo "Blocked: forbidden-pattern is not allowed in this repo." >&2
  exit 2  # 2 = block with message
fi

exit 0  # allow
```

Mark it executable:

```bash
chmod +x ~/.claude/hooks/your-new-hook.sh
```

### Step 2: Register it in `settings.json`

Add an entry under the relevant lifecycle event. Available events: `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, `Notification`, `PreCompact`, `PostCompact`, `SessionStart`. The `matcher` is a regex over tool names (`Bash`, `Write|Edit|MultiEdit`, `Agent`, `ExitPlanMode`, etc.) — omit it (or set `""`) to match everything.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/your-new-hook.sh" }
        ]
      }
    ]
  }
}
```

Multiple hooks under the same matcher run in array order. Use `~/` (Claude Code expands it); avoid hardcoding absolute home paths so other users can clone the repo.

### Step 3: Convention — exit codes & contract

| Exit | Meaning | Where the message goes |
|---|---|---|
| `0` | Allow | (silent) |
| `1` | Error / hook crashed | stderr, treated as block |
| `2` | Block with message | stderr (shown to model + user) |

Soft blocks that prompt for re-approval use the `SOFT_BLOCK_APPROVAL_NEEDED:` stderr prefix (see `block-heavy-bash.sh` for the canonical example) — Claude then asks the user via `AskUserQuestion` and replays after `~/.claude/hooks/approve.sh`.

### Step 4: Test it

Add a behavioral test under `~/.claude/hooks/tests/test-your-new-hook.sh` that pipes a fake JSON payload into the hook and asserts the exit code:

```bash
echo '{"command":"forbidden-pattern foo"}' | ~/.claude/hooks/your-new-hook.sh
[ $? -eq 2 ] || { echo "FAIL: should have blocked"; exit 1; }
```

Then run the full suite:

```bash
bash ~/.claude/hooks/tests/run-all.sh
```

`run-all.sh` auto-discovers any `test-*.sh` in that directory, so a new test file is picked up with no further wiring.

## PreToolUse: check-test-exists.sh

Runs **before** every Write, Edit, or MultiEdit on production code files. Enforces TDD — you must write the test file before editing the implementation. **Language-universal** — supports 16 languages with idiomatic test patterns.

```
File about to be edited
    │
    ▼
Is it a code file? ─── No ──► allow
(any of 16 supported languages)
    │
   Yes
    │
    ▼
Is it skip-listed? ──── Yes ──► allow
(test files, config files, entry points,
 .d.ts, migrations, generated dirs, etc.)
    │
   No
    │
    ▼
Does project have test infrastructure? ─── No ──► allow
(language-aware: vitest, pytest, go.mod,
 Cargo.toml, rspec, gradle, etc.)
    │
   Yes
    │
    ▼
Does a matching test file exist? ─── Yes ──► allow
(language-idiomatic patterns:
 TS/JS: foo.test.ts, foo.spec.ts, __tests__/
 Python: test_foo.py, foo_test.py, tests/
 Go: foo_test.go
 Rust: tests/foo.rs, inline #[cfg(test)]
 Ruby: foo_spec.rb, spec/, test/
 Java: FooTest.java, src/test/java/
 and more...)
    │
   No
    │
    ▼
BLOCK (exit 2): "Write the test first"
  (includes language name and expected test locations)
```

**Why this matters:** TDD is mandatory. Without this hook, agents write implementation first and tests as an afterthought — leading to tests that validate output rather than behavior.

## PostToolUse: check-invariants.sh

Runs **after** every Write, Edit, or MultiEdit on code files. Validates all INVARIANTS.md rules by executing their `Verify` commands.

```
File was edited
    │
    ▼
Is it a code file? ─── No ──► skip
    │
   Yes
    │
    ▼
Walk up from file dir to project root,
collecting all INVARIANTS.md files
    │
    ├─ None found ──► skip
    │
    └─ Found ──► for each invariant:
                  extract Verify command
                  run command (cd to project root)
                  │
                  ├─ All pass ──► allow
                  └─ Any fail ──► BLOCK (exit 2)
                     Report which invariant failed
                     and the Fix instruction
```

**Why this matters:** INVARIANTS.md defines cross-cutting contracts (permission string formats, entity statuses, API conventions). Without enforcement, agents independently invent incompatible vocabularies — tests pass locally but integration breaks.

## PostToolUse: progress-signal.sh

Runs **after** every Write, Edit, or MultiEdit on any file. When the edited file is a `progress.json` under `docs/tasks/`, it checks whether all sprints are complete. If so, it writes a sprint-finalized signal that gates `compound-reminder.sh` and `verify-completion.sh`.

```
File was edited
    │
    ▼
Is it a progress.json under docs/tasks/? ─── No ──► skip
    │
   Yes
    │
    ▼
All sprints "complete"? ─── No ──► skip
    │
   Yes
    │
    ▼
Write ~/.claude/state/.sprint-finalized-$SESSION_ID
(contains absolute path of the finalized progress.json)
Clear compound-warned and verify-warned markers for this session
```

**Why this matters:** The signal-gated architecture means `compound-reminder.sh` and `verify-completion.sh` only fire after real sprint completion — not on every Q&A turn or exploratory session. This eliminates false positives that caused friction when the agent was not doing task work.

## Stop Hook: verify-completion.sh

**BLOCKING** hook that prevents the agent from claiming task completion without evidence. Guards on the `authorize-stop-hooks.sh` signal first to avoid firing on Q&A turns:

```
Agent wants to stop
    │
    ▼
stop_hook_active? ─── Yes ──► allow (prevents infinite loop)
    │
   No
    │
    ▼
~/.claude/state/.stop-hooks-ok-$SESSION_ID exists? ─── No ──► allow (not a task turn)
(signal written by authorize-stop-hooks.sh; consumed one-shot)
    │
   Yes (consume signal)
    │
    ▼
Any progress.json with "complete" sprints
modified in last 24h? ─── No ──► allow
    │
   Yes
    │
    ▼
Evidence marker file exists?
(/tmp/.claude-completion-evidence-$SESSION_ID)
    │
    ├─ No ──► BLOCK (exit 2)
    │         "Task marked complete but no verification evidence.
    │          Run the Anti-Premature Completion Checklist."
    │
    └─ Yes ──► Check required fields:
               plan_reread, acceptance_criteria_cited,
               dev_server_verified, non_privileged_user_tested
               │
               ├─ All present ──► allow
               └─ Missing ──► BLOCK (exit 2)
                  "Evidence marker incomplete: missing [field]"
```

**Why this matters:** This is the enforcement mechanism for the Anti-Premature Completion Protocol. Without it, the protocol is just instructions the model can ignore.

## PreToolUse: check-docs-updated.sh

Runs **before** every Bash command, but only activates on `git push`. Checks if workflow files (hooks, skills, agents, settings.json) were changed without corresponding documentation updates.

```
git push command detected
    │
    ▼
In ~/.claude repo? ─── No ──► skip
    │
   Yes
    │
    ▼
Workflow files changed vs main?
(hooks/*.sh, skills/*/SKILL.md, agents/*.md, settings.json)
    │
    ├─ No ──► exit 0
    │
    └─ Yes
        │
        ▼
    Docs also changed? (README.md or workflow/*)
        │
        ├─ Yes ──► exit 0
        └─ No ──► BLOCK (exit 2)
             "Workflow files changed but no documentation updated.
              Update README.md and relevant workflow/ docs."
```

**Why this matters:** Workflow changes that aren't reflected in docs create drift between what the system does and what the docs say. This hook enforces documentation-as-code for the workflow repo itself.

## Utility: validate-i18n-keys.sh

Called by `/ship-test-ensure` Phase 0.3 before committing. Auto-detects whether the project uses i18n (next-intl, react-intl, i18next) and exits 0 silently if not. For i18n projects, it cross-validates that all `t()` keys referenced in source code exist in all locale JSON files.

```
Project being committed
    │
    ▼
Has i18n dependency? ─── No ──► exit 0 (skip)
    │
   Yes
    │
    ▼
Find all locale JSON files
    │
    ▼
Extract all t() keys from source
    │
    ▼
Cross-validate keys exist in ALL locales
    │
    ├─ All present ──► exit 0
    └─ Missing keys ──► exit 1, report missing keys per locale
```

**Why this matters:** Build, lint, and type-check do NOT catch missing i18n keys — they only appear as runtime console errors. This hook catches them before they ship.

## Utility: verify-worktree-merge.sh

Called by the orchestrator (Step 6.2) before each worktree branch merge. Detects files that were modified by both the current worktree branch and previously merged sprint branches, which would be silently overwritten.

```
Worktree branch about to merge
    │
    ▼
Previous sprint SHAs provided? ─── No ──► exit 0 (skip)
    │
   Yes
    │
    ▼
Get files modified by worktree branch
    │
    ▼
Get files modified by each previous sprint
    │
    ▼
Find overlap (files touched by both)
    │
    ├─ No overlap ──► exit 0
    └─ Overlap found ──► exit 1, report files for manual verification
```

**Why this matters:** Worktrees branch from HEAD at creation time. Later sprint merges aren't visible to worktrees created earlier. Without this check, merging a worktree silently reverts changes from already-merged sprints in shared files.

## Workflow Integrity Tests

The system includes a self-test suite at `~/.claude/test-workflow-mods/` that validates the entire `~/.claude/` structure, plus behavioral tests for individual hooks in `~/.claude/hooks/tests/`.

**What it tests (405 assertions across 45 sections):**

| Section | What It Validates |
|---|---|
| Hook scripts | All executable hooks exist with +x permissions |
| TDD enforcement | Behavioral tests (allow/block based on test file presence) |
| Invariant verification | Behavioral tests (allow/block based on INVARIANTS.md rules) |
| Anti-premature completion | Behavioral tests (evidence marker handling) |
| Auto-format (Biome/ESLint) | Behavioral tests (skip non-code, skip excluded dirs, detect configs) |
| TypeScript type checking | Behavioral tests (skip conditions, tsconfig detection) |
| settings.json registration | Every hook registered to correct lifecycle event |
| settings.json cross-reference | Every registered hook command points to existing file |
| settings.json structural | Validates JSON structure, env vars, permissions |
| CLAUDE.md documentation | Key concepts documented across CLAUDE.md and @rules/ includes |
| Agent definitions | 3 agents with correct frontmatter, model, and behavioral checks |
| Skill definitions | All skills with SKILL.md and frontmatter |
| Plan skill | Build Candidate, INVARIANTS.md, support files |
| PRD template | Structure and section numbering |
| Sprint spec template | Consumed Invariants section |
| Evolution infrastructure | JSON validity, backups, directory structure |
| Compound self-test | Compound skill references test suite |
| check-docs-updated.sh | Docs gate on git push behavioral tests |
| create-project | Structure, discovery interview, architecture defaults, quality gate |
| block-dangerous.sh | Hard blocks vs soft blocks, force push via +refspec |
| Model assignment | Matrix compliance, agent frontmatter, skills consistency |
| Delegation rules | Mandatory rules in CLAUDE.md |
| Autocompact config | Per-window targets, SessionStart enforcement |
| Context engineering | Rules documentation completeness |

**Hook-level tests** (`hooks/tests/`): Additional behavioral tests for `block-dangerous.sh`, `block-heavy-bash.sh`, `check-test-exists.sh`, `enforce-delegation.sh`, and `scan-secrets.sh`.

**When it runs:** Automatically as Step 10 of `/compound` when any `~/.claude/` file was modified. This ensures workflow modifications don't silently break the system.

**To run manually:**
```bash
bash ~/.claude/test-workflow-mods/run-tests.sh
```

---

Next: [Evolution & Learning](10-evolution-and-learning.md)

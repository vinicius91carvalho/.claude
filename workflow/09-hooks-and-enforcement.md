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
│  │  PreToolUse      │ ◄── Runs BEFORE every Bash command            │
│  │  (Bash)          │     block-dangerous.sh: hard/soft blocks      │
│  │                  │     proot-preflight.sh: environment warnings   │
│  │                  │     check-docs-updated.sh: doc sync on push   │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PreToolUse      │ ◄── Runs BEFORE every Write/Edit/MultiEdit    │
│  │  (Write|Edit|    │     check-test-exists.sh: TDD gate            │
│  │   MultiEdit)     │     (blocks edit if no test file exists)       │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  PostToolUse     │ ◄── Runs AFTER every Write/Edit/MultiEdit     │
│  │  (Write|Edit|    │     post-edit-quality.sh: auto-format TS/JS   │
│  │   MultiEdit)     │     check-invariants.sh: verify INVARIANTS.md │
│  └──────────────────┘                                               │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  Stop            │ ◄── Runs when the agent tries to end session  │
│  │  (always)        │     end-of-turn-typecheck.sh: check TS types  │
│  │                  │     compound-reminder.sh: BLOCK if compound   │
│  │                  │     hasn't run after task completion           │
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
| `block-dangerous.sh` | PreToolUse(Bash) | Every shell command | Block destructive operations; project-aware pkg mgr | Hard/soft block |
| `proot-preflight.sh` | PreToolUse(Bash) | First command/session | Warn about proot issues (language-aware) | No (informational) |
| `check-test-exists.sh` | PreToolUse(Write/Edit) | Every file edit | TDD gate — require test file (16 languages) | Yes (exit 2 if missing) |
| `post-edit-quality.sh` | PostToolUse(Write/Edit) | Every file edit | Auto-format code (all languages) | Yes (exit 2 on lint errors) |
| `check-invariants.sh` | PostToolUse(Write/Edit) | Every file edit | Verify INVARIANTS.md rules | Yes (exit 2 on violation) |
| `end-of-turn-typecheck.sh` | Stop | End of turn | Static type checking (all languages) | Yes (exit 2 on type errors) |
| `compound-reminder.sh` | Stop | End of turn | Ensure /compound ran | Yes (exit 2 if skipped) |
| `verify-completion.sh` | Stop | End of turn | Block premature completion | Yes (exit 2 without evidence) |
| `validate-i18n-keys.sh` | (ship-test-ensure) | Pre-commit | Cross-validate i18n keys across locales | No (informational) |
| `verify-worktree-merge.sh` | (orchestrator) | Post-merge | Detect silent overwrites from worktree merges | No (informational) |
| `check-docs-updated.sh` | PreToolUse(Bash) | `git push` | Block push if workflow files changed without doc updates | Yes (exit 2 if stale) |
| `worktree-preflight.sh` | (orchestrator) | Sprint start | Git/env readiness | N/A (utility) |
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

## Stop Hook: compound-reminder.sh

**BLOCKING** hook that prevents session end without learning capture:

```
Agent wants to stop
    │
    ▼
Any progress.json with all sprints "complete"? ─── No ──► allow stop
    │
   Yes
    │
    ▼
Was /compound run?
    │
    ├─ Yes ──► allow stop
    └─ No ──► BLOCK
             "Completed task detected but /compound hasn't run.
              Run /compound to capture learnings, or dismiss to skip."
```

**Why this is the most important hook:** Without learning capture, the workflow never improves. The compound step is where the system transforms individual task experience into permanent system improvement. Making it blocking ensures it's never skipped.

## settings.json Configuration

```json
{
  "env": {
    "ENABLE_LSP_TOOL": "1",
    "NODE_OPTIONS": "--max-old-space-size=2048",
    "CHOKIDAR_USEPOLLING": "true",
    "WATCHPACK_POLLING": "true"
  },
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": []
  },
  "effortLevel": "high",
  "skipDangerousModePermissionPrompt": true
}
```

| Setting | Purpose |
|---|---|
| `ENABLE_LSP_TOOL` | Enables Language Server Protocol (goToDefinition, findReferences, etc.) |
| `NODE_OPTIONS` | Increases Node.js memory limit (essential for proot-distro ARM64; harmless for non-Node projects) |
| `CHOKIDAR_USEPOLLING` / `WATCHPACK_POLLING` | Enables polling-based file watching (Node.js only; harmless for others) |
| `bypassPermissions` | Allows autonomous execution — compensated by hook safety |
| `effortLevel: "high"` | Claude invests more tokens/reasoning in responses |

## Adding Custom Hooks

To add a new hook, add an entry to the relevant section in `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/your-new-hook.sh \"$TOOL_INPUT\""
          }
        ]
      }
    ]
  }
}
```

Exit codes: `0` = allow, `1` = error, `2` = block with message (stderr).

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

## Stop Hook: verify-completion.sh

**BLOCKING** hook that prevents the agent from claiming task completion without evidence:

```
Agent wants to stop
    │
    ▼
stop_hook_active? ─── Yes ──► allow (prevents infinite loop)
    │
   No
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

The system includes a self-test suite at `~/.claude/test-workflow-mods/` that validates the entire `~/.claude/` structure.

**What it tests (123 assertions across 16 sections):**

| Section | What It Validates |
|---|---|
| Hook scripts | All 9 executable hooks + 1 sourced utility exist with +x |
| TDD enforcement | 8 behavioral tests (allow/block based on test file presence) |
| Invariant verification | 5 behavioral tests (allow/block based on INVARIANTS.md rules) |
| Anti-premature completion | 5 behavioral tests (evidence marker handling) |
| Auto-format (Biome/ESLint) | 8 behavioral tests (skip non-TS, skip excluded dirs, detect configs) |
| TypeScript type checking | 3 behavioral tests (skip conditions, tsconfig detection) |
| settings.json registration | Every hook registered to correct lifecycle event |
| settings.json cross-reference | Every registered hook command points to existing file |
| CLAUDE.md documentation | 18 key concepts documented |
| Agent definitions | 3 agents with correct frontmatter, model, and behavioral checks |
| Skill definitions | 5 skills with SKILL.md and frontmatter |
| Plan skill | Build Candidate, INVARIANTS.md, support files |
| PRD template | Structure and section numbering |
| Sprint spec template | Consumed Invariants section |
| Evolution infrastructure | JSON validity, backups, directory structure |
| Compound self-test | Compound skill references test suite |

**When it runs:** Automatically as Step 10 of `/compound` when any `~/.claude/` file was modified. This ensures workflow modifications don't silently break the system.

**To run manually:**
```bash
bash ~/.claude/test-workflow-mods/run-tests.sh
```

---

Next: [Evolution & Learning](10-evolution-and-learning.md)

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
| `block-dangerous.sh` | PreToolUse(Bash) | Every shell command | Block destructive operations | Hard/soft block |
| `proot-preflight.sh` | PreToolUse(Bash) | First command/session | Warn about proot issues | No (informational) |
| `check-test-exists.sh` | PreToolUse(Write/Edit) | Every file edit | TDD gate — require test file | Yes (exit 2 if missing) |
| `post-edit-quality.sh` | PostToolUse(Write/Edit) | Every file edit | Auto-format TS/JS | Yes (exit 2 on lint errors) |
| `check-invariants.sh` | PostToolUse(Write/Edit) | Every file edit | Verify INVARIANTS.md rules | Yes (exit 2 on violation) |
| `end-of-turn-typecheck.sh` | Stop | End of turn | Type-check TypeScript | Yes (exit 2 on type errors) |
| `compound-reminder.sh` | Stop | End of turn | Ensure /compound ran | Yes (exit 2 if skipped) |
| `verify-completion.sh` | Stop | End of turn | Block premature completion | Yes (exit 2 without evidence) |
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
| Wrong package manager | `npm install/run/exec/start/test/build/ci/init`, `npx` | Project uses pnpm exclusively |

The hook uses pure bash regex matching (no subprocesses) for performance.

## PostToolUse: post-edit-quality.sh

Runs **after** every Write, Edit, or MultiEdit operation:

```
File edited
    │
    ▼
Is it a TS/JS file? ─── No ──► skip
    │
   Yes
    │
    ▼
Is it in an excluded dir? ─── Yes ──► skip
(node_modules, dist, .next, etc.)
    │
   No
    │
    ▼
Biome config exists? ─── Yes ──► biome check --write
    │
   No
    │
    ▼
ESLint config exists? ─── Yes ──► eslint --fix + prettier --write
    │
   No
    │
    ▼
skip (no linter found)
```

**Why this matters:** The agent never needs to remember to format code. Every edit is auto-formatted with zero cognitive overhead.

## Stop Hook: end-of-turn-typecheck.sh

When the agent tries to end a turn after writing code:

```
Agent wants to stop
    │
    ▼
Was code written this turn? ─── No ──► allow stop
    │
   Yes
    │
    ▼
Has tsconfig.json? ─── No ──► allow stop
    │
   Yes
    │
    ▼
Find type checker (preference order):
1. Native tsgo binary (cached path for speed)
2. Global tsgo
3. pnpm tsc --noEmit --skipLibCheck (fallback)
    │
    ▼
Run type checker
    │
    ├─ Pass ──► allow stop
    ├─ Fail ──► BLOCK (agent must fix types)
    └─ Crash ──► fallback to tsc
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
| `NODE_OPTIONS` | Increases Node.js memory limit (essential for proot-distro ARM64) |
| `CHOKIDAR_USEPOLLING` / `WATCHPACK_POLLING` | Enables polling-based file watching |
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

Runs **before** every Write, Edit, or MultiEdit on production code files. Enforces TDD — you must write the test file before editing the implementation.

```
File about to be edited
    │
    ▼
Is it a code file? (.ts/.tsx/.js/.jsx) ─── No ──► allow
    │
   Yes
    │
    ▼
Is it skip-listed? ──── Yes ──► allow
(test files, config files, index.ts,
 types.ts, .d.ts, migrations, etc.)
    │
   No
    │
    ▼
Does project have test infrastructure? ─── No ──► allow
(vitest.config, jest.config, etc.)
    │
   Yes
    │
    ▼
Does a matching test file exist? ─── Yes ──► allow
(__tests__/name.test.ts, name.test.ts,
 name.spec.ts, tests/name.test.ts)
    │
   No
    │
    ▼
BLOCK (exit 2): "Write the test first"
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

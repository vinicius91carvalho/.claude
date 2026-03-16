# Architecture

## Repository Structure

```
~/.claude/
├── CLAUDE.md                           # The brain — all rules and workflows
├── README.md                           # Documentation for humans
├── settings.json                       # Deterministic enforcement — hooks & permissions
├── .gitignore                          # What NOT to version control
│
├── agents/                             # Specialized agents with their own context
│   ├── orchestrator.md                 # Project manager — delegates, never implements
│   ├── sprint-executor.md              # Worker — implements a sprint in isolation
│   └── code-reviewer.md               # Auditor — read-only, cannot modify code
│
├── skills/                             # Auto-invocable workflows
│   ├── plan/                           # Planning and PRD generation
│   │   ├── SKILL.md                    # Planning workflow
│   │   ├── correctness-discovery.md    # 6-question correctness framework
│   │   ├── prd-template-minimal.md     # Minimal PRD template (Standard mode)
│   │   ├── prd-template-full.md        # Full PRD template (PRD+Sprint mode)
│   │   └── sprint-spec-template.md     # Sprint specification template
│   ├── plan-build-test/                # Full local pipeline
│   │   └── SKILL.md
│   ├── ship-test-ensure/               # Deploy pipeline
│   │   └── SKILL.md
│   ├── compound/                       # Post-task learning capture
│   │   └── SKILL.md
│   └── workflow-audit/                 # Periodic system self-review
│       └── SKILL.md
│
├── hooks/                              # Deterministic enforcement scripts
│   ├── block-dangerous.sh              # Blocks destructive commands
│   ├── check-test-exists.sh            # TDD gate — blocks edits without test file
│   ├── check-invariants.sh             # Verifies INVARIANTS.md rules after edits
│   ├── post-edit-quality.sh            # Auto-formats code after edits
│   ├── end-of-turn-typecheck.sh        # Type-checks TypeScript at end of turn
│   ├── compound-reminder.sh            # Blocks session end without learning capture
│   ├── verify-completion.sh            # Blocks premature completion claims
│   ├── validate-i18n-keys.sh           # Cross-validates i18n keys across locales
│   ├── verify-worktree-merge.sh        # Detects silent overwrites in worktree merges
│   ├── check-docs-updated.sh           # Blocks push if workflow changed without docs
│   ├── proot-preflight.sh              # Environment checks for proot-distro
│   ├── worktree-preflight.sh           # Git and dependency readiness
│   └── retry-with-backoff.sh           # Utility for API rate limit handling
│
├── test-workflow-mods/                 # Workflow integrity test suite
│   ├── run-tests.sh                    # 123 assertions validating ~/.claude/ structure
│   └── testdata/                       # Fixture projects for hook behavioral tests
│
├── docs/                               # Reference material (loaded on demand)
│   ├── evaluation-reference.md         # Quality evaluation checklists
│   ├── anti-patterns-full.md           # 10 anti-patterns with examples and fixes
│   ├── vague-requirements-translator.md
│   ├── verification-gates.md           # 6 blocking verification gates
│   ├── proot-distro-environment.md     # proot-distro ARM64 guide
│   └── project-claude-md-template.md   # Template for project-specific CLAUDE.md
│
├── workflow/                           # This documentation
│
└── evolution/                          # Cross-project learning data
    ├── error-registry.json             # Error patterns across projects
    ├── model-performance.json          # Model success rate tracking
    ├── workflow-changelog.md           # System evolution history
    └── session-postmortems/            # Structured post-session analysis
```

## The Five Layers

Each layer of the repository serves a distinct purpose with a specific enforcement model:

```
┌─────────────────────────────────────────────────────────┐
│                     CLAUDE.md                           │
│              The Constitution — fundamental rules       │
│         (loaded every session, costs context tokens)    │
├─────────────────────────────────────────────────────────┤
│                    settings.json                        │
│          The Police — deterministic enforcement         │
│              (hooks run as real code)                   │
├─────────────────────────────────────────────────────────┤
│                      agents/                            │
│         Specialized Workers — each with own role        │
│          (own context window, permissions, model)       │
├─────────────────────────────────────────────────────────┤
│                      skills/                            │
│        Operating Procedures — step-by-step workflows    │
│           (auto-invoked based on conversation)          │
├─────────────────────────────────────────────────────────┤
│                       docs/                             │
│          Reference Library — consulted on demand        │
│          (not loaded every session — saves context)     │
├─────────────────────────────────────────────────────────┤
│                     hooks/                              │
│         Enforcement Scripts — hard/soft blockers        │
│          (bash scripts, run before/after actions)       │
├─────────────────────────────────────────────────────────┤
│                    evolution/                           │
│        System Memory — cross-project learning           │
│           (error patterns, model performance)           │
└─────────────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Layer 1: CLAUDE.md (The Constitution)

- **What:** ~650 lines of rules, workflows, judgment protocols, and development standards
- **When loaded:** Every session start (costs context tokens)
- **Enforcement:** Probabilistic — the model "should" follow these rules but can deviate
- **Design rule:** Keep it dense and essential. If something can live in `docs/`, move it there

### Layer 2: settings.json + hooks/ (The Police)

- **What:** Shell scripts that run as hooks at specific lifecycle points
- **When loaded:** Every tool use (PreToolUse), every edit (PostToolUse), every session end (Stop)
- **Enforcement:** Deterministic — code runs regardless of what the model thinks
- **Design rule:** The model cannot bypass a hook. Use hooks for rules that must never be broken

### Layer 3: agents/ (The Workers)

- **What:** Specialized agents with their own context window, tools, model, and permissions
- **When loaded:** When spawned by the orchestrator or skills
- **Enforcement:** Tool-level — each agent only has access to specific tools
- **Design rule:** Principle of Least Privilege — give each agent only what it needs

### Layer 4: skills/ (The Procedures)

- **What:** Step-by-step workflows that auto-invoke based on conversation context
- **When loaded:** When triggered by user intent or explicit `/skill-name` command
- **Enforcement:** Process — skills define the order of operations
- **Design rule:** Skills never hardcode project details — they read from Execution Config

### Layer 5: docs/ (The Library)

- **What:** Detailed reference material for specific topics
- **When loaded:** On demand, when a skill or agent references them
- **Enforcement:** None — purely informational
- **Design rule:** Save context by keeping detailed content here, not in CLAUDE.md

### Layer 6: evolution/ (The Memory)

- **What:** Cross-project learning data — error patterns, model performance, system changelog
- **When loaded:** During `/compound` and `/workflow-audit`
- **Enforcement:** Adaptive — data drives model selection and rule creation
- **Design rule:** Capture everything, analyze periodically, promote proven patterns

## What Gets Version Controlled

The `.gitignore` reveals an important decision about what is **shared system** vs. **ephemeral state**:

**Versioned (the system):**
- `CLAUDE.md`, `settings.json`, `README.md`
- `agents/`, `skills/`, `hooks/`, `docs/`
- `evolution/` (error-registry, model-performance, changelog)

**Not versioned (the state):**
- `.state/`, `projects/`, `backups/`, `cache/`, `history.jsonl`
- `worktrees/` (temporary directories for parallel execution)
- `settings.local.json` (machine-specific overrides)
- `todoStorage.json`, `*.log`, `plans/`, `tasks/`, `telemetry/`

The key decision: **version the system (rules, agents, skills, hooks), not the state (cache, history, temporary data)**. This allows cloning the repository on any new machine and having the system work immediately.

## How the Layers Interact

```
User says: "I need to add OAuth login"

1. CLAUDE.md classifies this as PRD+Sprint mode
2. /plan skill auto-invokes (Layer 4)
3. Contract-First pattern runs (Layer 1 rule)
4. Correctness Discovery questions asked (Layer 4 references Layer 5)
5. PRD created, sprints extracted (Layer 4)
6. /plan-build-test spawns orchestrator agent (Layer 3)
7. Orchestrator spawns sprint-executor agents in worktrees (Layer 3)
8. block-dangerous.sh prevents any destructive commands (Layer 2)
9. post-edit-quality.sh auto-formats every edit (Layer 2)
10. End-of-turn typecheck catches type errors (Layer 2)
11. /compound captures learnings (Layer 4)
12. Error patterns saved to evolution/ (Layer 6)
13. compound-reminder.sh blocks session end without learnings (Layer 2)
```

Every layer plays its part. The system works because no single layer is responsible for everything.

---

Next: [The Constitution (CLAUDE.md)](04-constitution.md)

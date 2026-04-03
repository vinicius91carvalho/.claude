# Context Engineering

## Agent Architecture (Native Subagents)

Agents live in `~/.claude/agents/`. Each has its own context window, tool permissions, model, and system prompt.

- **orchestrator** — Task management, sprint lifecycle, agent delegation. Full tool access. Uses sonnet (deterministic checklist doesn't need opus; opus reserved for merge conflicts >3 files).
- **sprint-executor** — Single sprint execution. Isolated worktree. Uses sonnet. Tools: Read, Write, Edit, Bash, Glob, Grep.
- **code-reviewer** — Read-only post-sprint review. Uses sonnet. Tools: Read, Grep, Glob.

## Worktree Isolation for Parallel Work

Sprint agents use `isolation: worktree` in frontmatter. Each gets its own git worktree and branch. Worktrees auto-clean when agent finishes without changes. Independent sprints can run in parallel; the orchestrator handles merging.

**Cleanup guarantee:** The `cleanup-worktrees.sh` Stop hook runs on every task end, pruning stale worktrees and removing merged sprint branches. Unmerged branches are preserved with a warning.

## Fresh Context Principle

Each major skill works best in a fresh context window. The plan saves state to session-learnings; the next skill reads it. This prevents context pollution across phases.

## Context Budget Rules

The main agent is an **orchestrator**, not a worker. Its context contains: system instructions + session learnings + subagent summaries + user messages. If reading file contents or build output directly, delegate to a subagent instead.

**Exceptions:** Playwright MCP interaction (`browser_snapshot`, `browser_navigate`, etc.) stays in main agent — never delegate browser interaction to subagents. Simple file edits (checkboxes, session-learnings) are done directly. Bug investigation may read up to 5 targeted files; more than that, delegate.

## Subagent Communication Protocol

- Every subagent prompt ends with: "Return a structured summary: [specify exact fields needed]"
- Never ask a subagent to "return everything" — specify exact data points
- Target 10-20 lines of actionable info per subagent result
- Chain subagents: extract only relevant fields from agent A to pass to agent B — never forward raw output

## Context Rot Protocol

**Signs:** Responses become generic, rules forgotten, questions re-asked, fixed errors reappear, tasks not checked off.

**Action:** Save state (update checkboxes, fill Agent Notes), write pending insights to session-learnings, report: "Context degrading. Recommend new session."

**Prevention:** Orchestrator keeps context lean. Sprint agents receive ONLY their sprint spec. Never forward raw output between sprints. Order context by stability: system instructions, docs, session state, current task.

**Automated recovery:** PreCompact hook auto-saves state; PostCompact hook auto-restores. SessionStart hook loads session-learnings on session begin/resume.

## Parallel Execution with Worktrees

**Batch Planning:**

1. Analyze tasks for file overlap and dependencies
2. DEPENDENT if: same files, same component tree, shared config, output feeds another
3. INDEPENDENT if: different files/dirs, unrelated features, no shared deps
4. When in doubt, run sequentially — safe > fast

**Execution:** Spawn all batch agents in a single message. Each uses `isolation: worktree`. Worktree agents must NOT modify coordination files or install dependencies.

**Merge Protocol:** Merge each branch sequentially. Conflicts: spawn opus agent. After merges: run build. Build fails: spawn sonnet agent to fix.

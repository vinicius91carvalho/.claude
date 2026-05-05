# Getting Started

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- Git installed
- Node.js 18+ (if working with TypeScript/JavaScript projects)
- pnpm (recommended package manager — the system enforces pnpm over npm)

## Installation

> **CAUTION — User-Level Configuration Override**
>
> This system installs to `~/.claude/`, which is the **user-level** configuration directory for Claude Code. This means:
>
> - It **replaces your entire personal configuration** — `CLAUDE.md`, `settings.json`, hooks, and all other files in `~/.claude/`
> - It is **NOT per-project** — it applies globally to **every project** you open with Claude Code
> - Any existing personal customizations (custom hooks, settings, memory files, evolution data) **will be overwritten**
>
> **Always back up your existing `~/.claude/` directory before installing.** If you have custom configurations you want to preserve, review the backup after installation and merge them manually into the new system.

### Step 1: Back Up and Clone the Repository

```bash
# Back up your existing configuration (do NOT skip this)
cp -r ~/.claude ~/.claude.backup 2>/dev/null

# Clone the workflow system
git clone <repository-url> ~/.claude
```

### Step 2: Verify the Structure

```bash
ls ~/.claude/
# Expected: CLAUDE.md  README.md  settings.json  agents/  skills/  hooks/  docs/  evolution/
```

### Step 3: Open Any Project

```bash
cd /path/to/your/project
claude  # Start Claude Code — the system loads automatically
```

That's it. The system applies automatically to every project you open with Claude Code.

## How Auto-Loading Works

When Claude Code starts in any directory, it searches for `CLAUDE.md` files in several locations:

1. **`~/.claude/CLAUDE.md`** — Your global instructions (this system)
2. **`./CLAUDE.md`** — Project-specific instructions in the current directory
3. **`./CLAUDE.md` in parent directories** — Inherited instructions

The global `CLAUDE.md` from `~/.claude/` is **always loaded**, providing the base workflow. Project-specific `CLAUDE.md` files add project-specific commands, URLs, and conventions.

## Setting Up a New Project

For each project you work on, create a project-specific `CLAUDE.md` with an **Execution Config** section. This tells the skills what commands to run and where things are.

### Minimal Project CLAUDE.md

```markdown
# Project Name

Brief description of what this project is.

## Execution Config

### Commands
- build: `pnpm build`
- test: `pnpm test`
- lint: `pnpm lint`
- type-check: `pnpm tsc --noEmit`
- dev: `pnpm dev`
- kill: `pkill -f 'next-server' 2>/dev/null; true`

### Paths
- session-learnings-path: `docs/session-learnings.md`
- task-file-location: `docs/tasks`

### GitHub
- github-repo: `your-org/your-repo`

## Stack
- Next.js 15, React 19, TypeScript
- Database: PostgreSQL with Drizzle ORM
- Styling: Tailwind CSS

## Project-Specific Rules
- Use server components by default
- API routes go in `app/api/`
```

A full template is available at `~/.claude/docs/reference/project-claude-md-template.md`.

### Why Execution Config Matters

Skills like `/plan-build-test` and `/ship-test-ensure` never hardcode project details. Every command, URL, and path comes from the project's `CLAUDE.md`. This makes the skills portable across any project — the system works identically whether you're building a blog or a payment platform.

## First Run Checklist

After installation, verify everything works:

1. **Start Claude Code** in any project directory
2. **Try a Quick Fix** — ask Claude to fix something small (typo, CSS change). This exercises the basic workflow without the full pipeline.
3. **Check hooks are active** — try typing `npm install` in a Bash command. The `block-dangerous.sh` hook should block it and suggest `pnpm install` instead.
4. **Test auto-formatting** — edit a TypeScript file. The `post-edit-quality.sh` hook should auto-format it after saving.
5. **Try `/plan`** — describe a feature. The planning skill should auto-invoke and walk you through Contract-First and Correctness Discovery.

## Installing Plugins

Plugins extend Claude Code with extra skills, commands, agents, MCP servers, and statuslines. They live under `~/.claude/plugins/` and are enabled via `enabledPlugins` in `settings.json`. The system ships pre-wired with the official Anthropic marketplace plus `claude-hud` for the statusline.

### Step 1: Add a marketplace

A marketplace is a Git repo that exposes one or more plugins. Add it once per host. Two ways:

**A. Inside a Claude Code session:** ask Claude to run `/plugin marketplace add <github-org>/<repo>` (built-in CLI command). The marketplace is cloned to `~/.claude/plugins/marketplaces/<name>/`.

**B. Manually in `settings.json`:** add an entry under `extraKnownMarketplaces`:

```json
"extraKnownMarketplaces": {
  "claude-hud": {
    "source": { "source": "github", "repo": "jarrodwatts/claude-hud" }
  }
}
```

The shipped `settings.json` already registers `claude-plugins-official` (Anthropic's official marketplace, auto-known) and `claude-hud`.

### Step 2: Enable plugins

Add each plugin to `enabledPlugins` in `settings.json`, keyed as `<plugin-name>@<marketplace-name>`:

```json
"enabledPlugins": {
  "frontend-design@claude-plugins-official": true,
  "playwright@claude-plugins-official": true,
  "commit-commands@claude-plugins-official": true,
  "claude-md-management@claude-plugins-official": true,
  "skill-creator@claude-plugins-official": true,
  "claude-code-setup@claude-plugins-official": true,
  "code-simplifier@claude-plugins-official": true,
  "security-guidance@claude-plugins-official": true,
  "typescript-lsp@claude-plugins-official": true,
  "claude-hud@claude-hud": true
}
```

Restart any open `claude` session so the new plugins are loaded. Installed copies are cached at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` and tracked in `~/.claude/plugins/installed_plugins.json` (managed by Claude Code — do not hand-edit).

### Step 3: Verify

```bash
# Inside a session:
/plugin list

# From the shell:
ls ~/.claude/plugins/cache/
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins | keys'
```

Plugin-provided slash commands then appear under `/<plugin>:<command>` (for example `/commit-commands:commit-push-pr`, `/claude-md-management:revise-claude-md`).

### Updating, removing, switching scope

| Action | How |
|---|---|
| Update one plugin | `/plugin update <plugin>@<marketplace>` |
| Update all from a marketplace | `/plugin marketplace update <marketplace>` |
| Disable temporarily | Set its `enabledPlugins` value to `false` |
| Remove entirely | Delete its key from `enabledPlugins`; optionally `rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>` |

Plugins that ship a statusline (like `claude-hud`) are wired in via `settings.json > statusLine` — see the existing block in the shipped `settings.json` for the resolution shell snippet that picks the latest cached version.

## What Loads When

Understanding what loads when helps you manage context efficiently:

| What | When It Loads | Context Cost |
|------|---------------|--------------|
| `CLAUDE.md` | Every session start | ~650 lines (always) |
| `settings.json` hooks | Every tool use | Zero (runs as scripts) |
| Agent files | When an agent is spawned | Per-agent context window |
| Skill files | When a skill is invoked | Injected into conversation |
| `docs/` files | When referenced by a skill | On-demand only |
| `evolution/` data | During `/compound` and `/workflow-audit` | On-demand only |

The key insight: `CLAUDE.md` is the only file that costs context every session. Everything else loads on demand. Keep `CLAUDE.md` dense and essential; put detailed reference material in `docs/`.

## Configuration Options

### `settings.json` Key Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| `ENABLE_LSP_TOOL` | `"1"` | Enables Language Server Protocol for code navigation |
| `NODE_OPTIONS` | `"--max-old-space-size=2048"` | Increases Node.js memory limit |
| `CHOKIDAR_USEPOLLING` | `"true"` | Enables polling-based file watching |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"62"` | Context auto-compact threshold (managed by `set-compact.sh`) |
| `effortLevel` | `"high"` | Claude invests more reasoning in responses |
| `permissions.allow` | Explicit list | Allows autonomous execution for listed tools (compensated by hooks) |

### Customization

- **Add project-specific hooks** — extend `settings.json` with project-specific PreToolUse/PostToolUse hooks
- **Adjust model assignments** — modify the Model Assignment Matrix in `CLAUDE.md` based on your needs
- **Add new agents** — create new `.md` files in `agents/` with appropriate frontmatter
- **Create new skills** — add new directories in `skills/` with a `SKILL.md` file

---

Next: [Architecture](03-architecture.md)

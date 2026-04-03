---
name: update-docs
description: Analyze the codebase and update project documentation (README.md, docs/) to reflect the current state of the code. Use this skill when the user says "update docs", "update readme", "sync docs", "docs are stale", "refresh documentation", or when workflow files changed and docs need updating. Also auto-invoke when check-docs-updated.sh blocks a push, or when the user wants to document a project for the first time. Works on any project — not just the workflow repo.
context: fork
paths:
  - "**/README.md"
  - "**/docs/**"
---

# Update Docs

Analyze the codebase and update documentation to accurately reflect the current state of the code.
Produces concise, accurate documentation — not verbose filler.

## Step 1: Detect Documentation Targets

Identify what documentation exists and what the project contains.

### 1.1: Find existing docs

```
Search for:
- README.md (root and subdirectories)
- docs/ or documentation/ directories
- CHANGELOG.md
- Any .md files referenced in README
- API documentation (OpenAPI, Swagger)
- workflow/ directory (for workflow repos)
```

### 1.2: Analyze codebase structure

Spawn an **Explore agent** (haiku model) with this prompt:

> Analyze the project structure and return a structured summary:
>
> 1. **Project type:** (web app, CLI, library, monorepo, workflow system, etc.)
> 2. **Tech stack:** (languages, frameworks, key dependencies)
> 3. **Entry points:** (main files, exports, bin scripts)
> 4. **Directory structure:** (top-level dirs with purpose — 1 line each)
> 5. **Key components:** (modules, services, hooks, skills, agents — whatever the project uses)
> 6. **Scripts/commands:** (package.json scripts, Makefile targets, shell scripts)
> 7. **Configuration:** (env vars, config files, settings)
> 8. **Tests:** (test framework, test location, how to run)
>
> Be concise. One line per item. Skip empty categories.

### 1.3: Detect what changed (if applicable)

If in a git repo with history:
```bash
# What changed since docs were last updated?
DOCS_LAST_MODIFIED=$(git log -1 --format="%H" -- README.md docs/ 2>/dev/null)
if [ -n "$DOCS_LAST_MODIFIED" ]; then
  git diff --name-only "$DOCS_LAST_MODIFIED"..HEAD -- ':!README.md' ':!docs/'
fi
```

This tells you which code changed since docs were last touched.

## Step 2: Diff Analysis — What's Stale?

Compare the Explore agent's findings against existing documentation.

For each doc file, identify:
- **Missing:** Components/features in code but not in docs
- **Stale:** Docs describe something that no longer exists or changed
- **Inaccurate:** Docs describe something incorrectly (wrong paths, wrong commands, wrong behavior)
- **Current:** Docs accurately reflect the code

Create a mental checklist:
```
[ ] README.md — missing: [list], stale: [list]
[ ] docs/architecture.md — missing: [list], stale: [list]
...
```

Report this checklist to the user before making changes:
```
Documentation audit:
- README.md: 3 sections stale, 2 missing
- docs/hooks.md: 1 section stale
- docs/api.md: current (no changes needed)

Proceed with updates?
```

Wait for user confirmation unless running autonomously.

## Step 3: Update Documentation

### Principles

1. **Concise over verbose.** One clear sentence beats three fluffy ones.
2. **Accurate over complete.** Better to document 5 things correctly than 10 things approximately.
3. **Structure matches code.** If the code has 3 modules, docs should have 3 sections — not 7.
4. **Examples over descriptions.** Show a command, don't explain what a command would look like.
5. **Delete stale content.** Removing wrong docs is more valuable than adding new docs.

### Update order

1. **Delete** stale/incorrect content first
2. **Update** existing sections that are partially correct
3. **Add** new sections for undocumented components
4. **Verify** internal links and references still work

### Section guidelines by project type

**For any project README:**
- Project name + one-line description (what it does, not what it is)
- Quick start (3-5 commands max)
- Key concepts (only if non-obvious)
- Project structure (tree with 1-line descriptions)
- Available commands/scripts
- Configuration (env vars, config files)

**For workflow/system repos (like ~/.claude):**
- Component inventory (hooks, skills, agents, etc.) with tables
- How components connect (lifecycle, data flow)
- How to extend (add a hook, add a skill, etc.)

**For libraries/packages:**
- Installation
- Basic usage (code example)
- API reference (function signatures + 1-line descriptions)

**For web apps:**
- Setup & run
- Architecture overview
- Key routes/pages
- Environment variables

### What NOT to add

- Badges, shields, or decorative elements (unless user asks)
- "Contributing" sections for personal projects
- Verbose explanations of obvious things
- Duplicate information across multiple doc files
- TODOs or "coming soon" placeholders

## Step 4: Verify

After all edits:

1. **Check internal links:** Grep for `](` in markdown files and verify targets exist
2. **Check command accuracy:** If docs reference a command, verify it exists in package.json/Makefile/scripts
3. **Check path accuracy:** If docs reference a file path, verify the file exists
4. **Read the final result:** Read each updated file to confirm it reads well

```bash
# Quick link checker
grep -rn ']\(' README.md docs/ 2>/dev/null | grep -oP '\]\(\K[^)]+' | while read -r link; do
  if [[ "$link" != http* ]] && [[ ! -e "$link" ]]; then
    echo "BROKEN LINK: $link"
  fi
done
```

## Step 5: Report

Output a concise summary:
```
Documentation updated:
- README.md: updated project structure (+2 hooks), removed stale API section
- docs/hooks.md: added validate-i18n-keys.sh and verify-worktree-merge.sh sections
- docs/architecture.md: no changes needed

Verified: 0 broken links, 0 stale commands, 0 missing paths.
```

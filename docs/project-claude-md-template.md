# Project CLAUDE.md Template

Use this template when setting up a new project. Copy to the project root as `CLAUDE.md` and fill in the values.

---

# [Project Name]

## Overview

[One-sentence project description]

## Execution Config

```yaml
# Commands (all required — used by /plan-build-test, /ship-test-ensure, orchestrator, sprint-executor)
build: "pnpm turbo build"
test: "pnpm turbo test"
lint: "pnpm exec biome check ."
lint-fix: "pnpm exec biome check --write ."
type-check: "pnpm tsc --noEmit"
e2e: "pnpm exec playwright test tests/"
dev: "pnpm dev"
kill: "pkill -f 'next-server|next start|next dev' 2>/dev/null; true"
package-manager: "pnpm"

# Session learnings (compact-safe memory)
session-learnings-path: "docs/session-learnings.md"

# Task file location (where PRDs and sprint specs go)
task-file-location: "docs/tasks"

# Knowledge files (project-specific patterns and solutions)
knowledge-files:
  - "docs/solutions/"
  - "docs/architecture/decisions/"

# GitHub (required by /ship-test-ensure)
github-repo: "org/repo"

# URLs (required by /ship-test-ensure)
staging-url: "https://staging.example.com"
production-url: "https://example.com"

# Deploy (required by /ship-test-ensure)
deploy:
  staging-trigger: "auto"  # push to main triggers staging deploy
  production: 'gh workflow run "Deploy" --repo org/repo -f stage=production'

# Pages to audit (required by /ship-test-ensure Phase 5)
pages-to-audit:
  - "https://example.com/"
  - "https://example.com/about"

# E2E overrides per environment (optional)
e2e-staging: "BASE_URL=https://staging.example.com pnpm exec playwright test tests/"
e2e-production: "BASE_URL=https://example.com pnpm exec playwright test tests/"

# Lighthouse threshold (optional — default 100, proot default 90)
lighthouse-threshold: 100
```

## Tech Stack

- **Framework:** [e.g., Next.js 15 with App Router]
- **Language:** [e.g., TypeScript 5.x]
- **Styling:** [e.g., Tailwind CSS v4]
- **Database:** [e.g., Postgres via Drizzle ORM]
- **Hosting:** [e.g., AWS via SST]
- **CI/CD:** [e.g., GitHub Actions]

## Project Structure

```
src/
  app/          # Next.js App Router pages
  components/   # Shared UI components
  lib/          # Utilities and helpers
  server/       # Server-side code
```

## Key Patterns

- [Pattern 1: e.g., "All API routes use the `createApiHandler` wrapper"]
- [Pattern 2: e.g., "Database queries go through service layer, never direct in routes"]

## Environment Variables

| Variable | Purpose | Where Set |
|----------|---------|-----------|
| DATABASE_URL | Postgres connection | .env.local |

## Known Issues

- [Issue 1: description and workaround]

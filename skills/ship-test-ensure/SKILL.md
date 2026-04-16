---
name: ship-test-ensure
description: >
  End-to-end shipping pipeline that commits, pushes, follows CI/CD deploy to
  staging, runs all E2E tests on staging, deploys to production, follows that
  deploy, then runs Google PageSpeed Insights and Lighthouse audits on production
  until all categories score 100 with zero errors. Iterates and fixes at every
  step. Use when the user says "ship it", "deploy everything", "ship and verify",
  "push to prod", "full deploy pipeline", or wants to go from committed code to
  verified production with perfect scores.
---

# Ship, Test & Ensure — Full CI/CD Pipeline from Commit to Perfect Production Scores

End-to-end shipping pipeline: commit, push branch, create PR, merge via CI/CD, follow staging deploy, E2E on staging, deploy to production via CI/CD workflow, run PageSpeed/Lighthouse on production. Every step has a fix loop — issues found are fixed, re-pushed, and re-verified.

**All deploys go through CI/CD pipelines — never push directly to main.**

**Autonomous by default (with one mandatory gate).** This skill runs without user
interruption through commit, staging deploy, and staging E2E verification. The only
mandatory human checkpoint is **production deploy confirmation** (Phase 4.1). All other
checkpoints use safe defaults. This is a permanent design choice — the user's workflow
is: `/plan-build-test` (autonomous) → manual testing → `/ship-test-ensure` (autonomous
through staging, confirms before prod). See CLAUDE.md "Autonomous Pipeline" for details.

**Mandatory gates (always ask, even in autonomous mode):**
- Phase 4.1: Production deploy confirmation
- Phase 6.3: Rollback decision

**Inherited from CLAUDE.md** (applies to all phases below):

- Autonomous Pipeline — run without interruption, use safe defaults at checkpoints
- Context Engineering — orchestrator pattern, subagent communication, context budget
- Model Assignment Matrix — haiku/sonnet/opus per task type
- Session Learnings — compact-safe memory at the path specified in project CLAUDE.md

---

## Execution Config Dependency

This skill reads project-specific configuration from the project's `CLAUDE.md` under an `## Execution Config` section. Required keys: `build_command`, `test_command`, `lint_command`, `typecheck_command`, `kill_command`, `e2e_command`, `package_manager`, `github_repo`, `staging_urls`, `production_urls`, `deploy_commands` (with `staging_trigger` and `production` list), `pages_to_audit`, and `app_detection_paths`. Optional: `staging_credentials`, `e2e_staging`, `e2e_production`, `lighthouse_threshold`, `psi_api_key`.

The format is flexible (YAML-like, markdown tables, key-value). Parse whatever is present — keys and values matter, not syntax.

If `## Execution Config` is missing from the project CLAUDE.md, **STOP** and ask the user to add it before proceeding.

---

## PHASE 0: Context & Resume Gate (Always Runs First)

### Step 0.0: Fresh Context Check

This skill works best in a fresh context window — it's a long pipeline and context space matters.

**Autonomous mode (default):** Auto-select "Continue here" and proceed without asking.
The user invoked `/ship-test-ensure` expecting it to run — don't interrupt with context
management questions. If context becomes an issue during execution, the Context Rot
Protocol will catch it.

**Override:** If the user explicitly asks about context management, or if the current
context is severely degraded (signs from Context Rot Protocol), then present options via
`AskUserQuestion`:

- **Start fresh context** — Save pipeline state to session learnings file, then you start a new conversation and run `/ship-test-ensure`. The new session picks up from session learnings.
- **Continue here** — Run in the current context window.

**NOTE:** Do NOT use `claude -p` for fresh context — it is single-turn print mode and
cannot execute multi-step pipelines like ship-test-ensure.

If this IS a fresh context (first message or resumed from session learnings), skip to Step 0.1.

### Step 0.1: Read Session Learnings & Execution Config

1. Read the session learnings file (path from project CLAUDE.md) for context. Check if a previous ship-and-verify was interrupted (look for `## Ship Pipeline State`).
2. Read the project CLAUDE.md and extract the `## Execution Config` section. Parse all config values. If any required config is missing, ask the user.

### Step 0.2: Determine Which App(s) to Ship

**Sprint state is optional.** This skill does not require a `progress.json` or
completed sprint record — it ships whatever diverges from the remote. If PRD
state happens to exist, it's informational only; the authoritative signal is
"what is not yet on the tracking remote".

Detect all unpushed changes:

```bash
# All commits on the current branch not yet on the tracking remote branch
git log @{upstream}..HEAD --oneline 2>/dev/null || git log origin/main..HEAD --oneline
# Files changed across those commits
git diff @{upstream}..HEAD --name-only 2>/dev/null || git diff origin/main..HEAD --name-only
# Plus working tree
git diff --name-only              # unstaged
git diff --name-only --cached     # staged
```

Union the three file lists. Categorize using `app_detection_paths` from
Execution Config. Determine which app(s) are affected (or if only shared
packages changed — affects all apps).

**If there are zero unpushed commits AND zero staged/unstaged changes:** report
"nothing to ship — working tree matches remote" and stop. Do not fabricate a
no-op commit.

### Step 0.3: Local Verification Gate

Before committing, ensure local checks pass. Spawn a **sonnet agent**:

> Run these commands sequentially and report results:
>
> 1. `{kill_command}` (cleanup)
> 2. `{lint_command}` (lint + format)
> 3. `{typecheck_command}` (type checking)
> 4. `{build_command}` (build)
> 5. `{test_command}` (unit tests)
> 6. `bash ~/.claude/hooks/scripts/validate-i18n-keys.sh .` (i18n key validation — auto-skips if project has no i18n)
>
> If any step fails, report: which step, the error, and affected files.
> Return: pass/fail per step, error details if any.

All commands come from the project's Execution Config.

**If any check fails:** Spawn a fix agent (model per failure type), fix, re-run. Loop max 3 times. If still failing, report to user and stop.

---

## Phase 1: Commit, Branch & PR

**All code reaches main through a PR — never push directly.**

### Step 1.1: Capture Rollback Point and Create Branch

**IMPORTANT: Create the branch BEFORE committing.** Committing on main first would make the
PR show no diff (main already has the commit). The branch must diverge from main before
the commit is added.

```bash
# Capture the rollback point BEFORE any changes reach main
PRE_DEPLOY_SHA=$(git rev-parse main)
echo "Rollback SHA: $PRE_DEPLOY_SHA"

# Create feature branch from current HEAD
BRANCH_NAME="ship/$(date +%Y%m%d-%H%M)-$(echo '<brief-description>' | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 40)"
git checkout -b "$BRANCH_NAME"
```

### Step 1.2: Stage and Commit

Review changes with `git status` and `git diff`. Stage specific files (never `git add -A`). Create a commit on the feature branch:

```bash
git add [specific files]
git commit -m "$(cat <<'EOF'
<type>: <descriptive message>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Commit message should accurately describe all changes. Use conventional commit types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`.

Push the branch:

```bash
git push -u origin "$BRANCH_NAME"
```

### Step 1.3: Create PR and Merge

Create a PR targeting main:

```bash
gh pr create --repo {github_repo} --title "<type>: <description>" --body "$(cat <<'EOF'
## Summary
<bullet points>

## Verification
- Local build: PASS
- Local tests: PASS
- Local lint: PASS
- Local type-check: PASS

Generated by /ship-test-ensure pipeline
EOF
)"
```

**STOP and ask the user** how they want to merge:

> **PR created:** [PR_URL]
>
> How would you like to merge?
> - **I'll merge on GitHub** — I'll wait and follow the CI/CD deploy
> - **Auto-merge here** — I'll run `gh pr merge --squash --delete-branch`

If the user chooses auto-merge:

```bash
# Wait for CI checks
gh pr checks [PR_NUMBER] --repo {github_repo} --watch

# Merge via CI/CD (squash merge keeps history clean)
gh pr merge [PR_NUMBER] --repo {github_repo} --squash --delete-branch
```

If the user merges on GitHub: wait for confirmation, then sync local main (see below).

If CI checks fail on the PR: diagnose, fix, push to the same branch, wait for re-run. Max 3 cycles.

**After merge (both paths), sync local main:**

```bash
# IMPORTANT: Squash-merge creates a new commit on remote that differs from
# local pre-squash commits. A plain `git pull` will fail with "divergent branches".
# The correct sequence:
git checkout main
git fetch origin main
git pull --ff-only origin main
# If ff-only fails (local has pre-squash commits), reset to remote:
# git reset --hard origin/main  (safe: all our changes are in the squash commit)
```

### Step 1.4: Save Pipeline State

Update the session learnings file with a `## Ship Pipeline State` block recording: timestamp, apps, branch, PR number/URL, commit SHA, pre-deploy SHA, and current phase.

---

## Phase 2: Follow Staging Deploy

Staging deploys are triggered according to `deploy_commands.staging_trigger` in Execution Config. If `"auto"`, pushing to main triggers them. Otherwise, run the specified command.

### Step 2.1: Wait for Workflow Runs to Appear

```bash
sleep 10
gh run list --repo {github_repo} --limit 5 --json databaseId,name,status,conclusion,createdAt,headBranch,event
```

Identify the runs triggered by the push (match by `headBranch: main` and recent `createdAt`).

### Step 2.2: Monitor Runs Until Completion

For each relevant run, poll every 30 seconds with a **15-minute timeout**:

```bash
gh run view [RUN_ID] --repo {github_repo} --json jobs --jq '.jobs[] | {name, status, conclusion}'
```

Track elapsed time from first poll. If a workflow has not completed after **15 minutes**:

1. Get current job statuses: `gh run view [RUN_ID] --repo {github_repo} --json jobs`
2. Log to session learnings: "Deploy running 15+ minutes. [Job X] is still [status]."

**Autonomous mode (default):** Auto-select "Wait 10 more minutes" (extend timeout to
25 min total). If still not complete after 25 minutes, report BLOCKED to user with full
job statuses and stop the pipeline. Do not auto-cancel — that's a destructive action.

**Override:** If the user is actively watching, present options via `AskUserQuestion`:
   - **Wait 10 more minutes** — extend timeout once (25 min total max)
   - **Cancel and retry** — `gh run cancel [RUN_ID]` then re-push
   - **Investigate** — stop pipeline, user checks CI manually

Report progress to the user as steps complete:

> **[App Name] Deploy:** Build PASS | Deploy Staging IN PROGRESS...

### Step 2.3: Handle Staging Deploy Failures

If any workflow fails:

1. Get failure logs: `gh run view [RUN_ID] --repo {github_repo} --log-failed`
2. Spawn a **sonnet agent** to diagnose and fix
3. Commit the fix, push again
4. **Go back to Step 2.1** — follow the new run
5. Max 3 retry cycles before asking user for guidance

### Step 2.4: Confirm Staging Deploy Success

All workflows must show green. Update the `## Ship Pipeline State` in session learnings: phase 2 complete, run IDs and SUCCESS status for each app.

---

## Phase 3: E2E Tests on Staging

### Step 3.1: Run E2E Suite Against Staging

Determine which test suites to run based on affected apps. Build the E2E command using Execution Config:

- Use `e2e_staging` commands if defined, otherwise construct from `e2e_command` with staging URL
- Prepend `staging_credentials.env_var` if staging has auth gate
- Kill any existing test processes first: `{kill_command}`

Example construction:

```bash
{staging_credentials.env_var} BASE_URL={staging_url} {e2e_command}
```

Run with `--reporter=list` for detailed output (if the test runner supports it).

### Step 3.2: Analyze E2E Results

If tests fail:

1. Categorize failures: actual bugs vs flaky tests vs staging-specific issues
2. For **actual bugs**: Spawn a **sonnet agent** to fix the source code
3. For **flaky tests**: Spawn a **sonnet agent** to fix the test
4. For **staging-specific**: Investigate environment differences
5. After fixes: commit, push, **go back to Phase 2** (follow the new deploy, then re-run E2E)
6. Max 5 fix-deploy-test cycles

### Step 3.3: Confirm E2E Pass

All tests must pass. Update the `## Ship Pipeline State` in session learnings: phase 3 complete, E2E pass/fail counts per app.

---

## Phase 4: Deploy to Production

### Step 4.1: Confirm with User (MANDATORY — never skip, even in autonomous mode)

**This is a non-negotiable safety gate.** Production deploys always require explicit user
confirmation. This is the one checkpoint that autonomous mode does NOT bypass. The user
designed this workflow specifically to keep this gate while removing all others.

Use `AskUserQuestion`:

> **Staging verification complete.** All E2E tests passing on staging.
>
> Ready to deploy to production:
> [List production URLs from Execution Config]
>
> Proceed with production deploy?

Options: **Deploy all** | **[Per-app options from config]** | **Abort**

### Step 4.2: Trigger Production Deploys

Run the production deploy commands from Execution Config:

```bash
{deploy_commands.production[*].command}
```

Only trigger the app(s) the user approved.

### Step 4.3: Follow Production Deploy

Same monitoring pattern as Phase 2 — poll every 30 seconds with the same **15-minute timeout** and escalation protocol. Production deploys warrant extra caution: if timeout triggers, recommend **"Investigate"** as the default option rather than "Cancel and retry".

### Step 4.4: Handle Production Deploy Failures

Same fix loop as Phase 2.3, but with extra caution:

- Any fix must pass local verification AND staging E2E before pushing again
- Confirm with user before each retry push

### Step 4.5: Confirm Production Deploy Success

Update the `## Ship Pipeline State` in session learnings: phase 4 complete, run IDs and SUCCESS status for each app.

---

## Phase 5: PageSpeed Insights & Lighthouse Audit (Optional)

**This phase is optional.** Check `pages_to_audit` in Execution Config:
- If `pages_to_audit` is defined and non-empty → run this phase
- If `pages_to_audit` is missing or empty → skip entirely with a note in the final report:
  "Phase 5 skipped — no `pages_to_audit` configured in Execution Config"

This allows projects to opt-in to Lighthouse auditing without blocking the pipeline.

### Step 5.0: Environment Detection

```bash
PROOT_MODE=false
if uname -r 2>/dev/null | grep -q PRoot-Distro; then
  PROOT_MODE=true
fi
```

**If proot detected:**
- Skip local Lighthouse CLI (unreliable performance scores in proot ARM64)
- Use PageSpeed Insights API only (tests the remote production site, which is valid)
- Accept configurable thresholds: read `lighthouse_threshold` from project CLAUDE.md
  Execution Config (default: 100). In proot, if not configured, warn and default to 90.
- Mark local Lighthouse as `BLOCKED: proot-distro ARM64` in the report

**If NOT proot:** Use PageSpeed Insights API (preferred for production accuracy).
Local Lighthouse CLI is optional — PSI tests the actual deployed site which is more accurate.

**API key handling:** If `PSI_API_KEY` env var or `psi_api_key` Execution Config key is set,
append `&key=KEY` to PSI API requests. This removes daily quota limits. Without a key, the
API has a low daily quota and may return 429 errors — in that case, mark as
`BLOCKED: PSI API quota exceeded` and continue (do not fail the pipeline).

### Step 5.1: Run Google PageSpeed Insights API

Test production pages listed in `pages_to_audit` from Execution Config. Use the PageSpeed Insights API (no API key needed for basic usage):

**For each page, test both mobile and desktop:**

```bash
# Mobile
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=URL&strategy=mobile&category=performance&category=accessibility&category=best-practices&category=seo" | jq '{
  url: .id,
  strategy: "mobile",
  performance: (.lighthouseResult.categories.performance.score * 100),
  accessibility: (.lighthouseResult.categories.accessibility.score * 100),
  bestPractices: (.lighthouseResult.categories["best-practices"].score * 100),
  seo: (.lighthouseResult.categories.seo.score * 100),
  lcp: .lighthouseResult.audits["largest-contentful-paint"].displayValue,
  cls: .lighthouseResult.audits["cumulative-layout-shift"].displayValue,
  fcp: .lighthouseResult.audits["first-contentful-paint"].displayValue,
  tbt: .lighthouseResult.audits["total-blocking-time"].displayValue
}'

# Desktop
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=URL&strategy=desktop&category=performance&category=accessibility&category=best-practices&category=seo" | jq '{
  url: .id,
  strategy: "desktop",
  performance: (.lighthouseResult.categories.performance.score * 100),
  accessibility: (.lighthouseResult.categories.accessibility.score * 100),
  bestPractices: (.lighthouseResult.categories["best-practices"].score * 100),
  seo: (.lighthouseResult.categories.seo.score * 100)
}'
```

### Step 5.2: Analyze Results & Identify Issues

For each page/strategy combination, check:

| Category       | Target | Action if Below        |
| -------------- | ------ | ---------------------- |
| Performance    | 100    | Analyze failing audits |
| Accessibility  | 100    | Fix a11y issues        |
| Best Practices | 100    | Fix BP issues          |
| SEO            | 100    | Fix SEO issues         |

Extract the specific failing audits from the full Lighthouse response:

```bash
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=URL&strategy=STRATEGY&category=CATEGORY" | jq '[.lighthouseResult.audits | to_entries[] | select(.value.score != null and .value.score < 1) | {id: .key, title: .value.title, score: .value.score, displayValue: .value.displayValue, description: .value.description}]'
```

### Step 5.3: Present Score Report

Display a comprehensive table:

```
Page                    | Strategy | Perf | A11y | BP  | SEO
------------------------|----------|------|------|-----|-----
example.com/            | mobile   | 95   | 100  | 100 | 100
example.com/            | desktop  | 100  | 100  | 100 | 100
example.com/about       | mobile   | 92   | 98   | 100 | 100
...
```

List all failing audits grouped by fixability.

### Step 5.4: Fix Loop — Iterate Until Perfect

**For each category scoring below 100:**

1. **Classify the failing audit:**
   - **Code-fixable**: Missing alt text, color contrast, meta tags, render-blocking resources, image optimization, CLS issues, unused CSS/JS
   - **Infrastructure-fixable**: Server response time, caching headers, compression, CDN config
   - **Third-party**: External script issues (analytics, fonts) — may not be fixable to 100

2. **Spawn a fix agent** (model based on complexity):
   - a11y/SEO fixes → `haiku` (mechanical, well-defined)
   - Performance fixes → `sonnet` (requires analysis)
   - Complex performance (code splitting, lazy loading) → `opus`

3. **Agent prompt template:**

   > Fix these Lighthouse audit failures for [URL]:
   >
   > **Failing audits:**
   > [LIST OF AUDIT IDs, TITLES, DESCRIPTIONS]
   >
   > **Rules:**
   >
   > - Only fix what's reported — don't refactor unrelated code
   > - For images: ensure WebP, lazy loading, explicit width/height
   > - For a11y: WCAG 2.1 AA minimum
   > - For performance: focus on LCP, CLS, TBT
   > - For SEO: meta tags, structured data, canonical URLs
   > - Use `{package_manager}` exclusively
   >
   > Return: files modified, what changed, expected score improvement.

4. **After fixes:** Commit to the same branch, push, create PR, merge via CI/CD (Phase 1 + 2 + 4 fast path — skip E2E if changes are cosmetic/meta-only)

5. **Re-run PageSpeed** on the affected pages

6. **Repeat until all categories hit 100** or improvements plateau

**Max iterations:** 5 full fix-deploy-test cycles. If scores plateau (same score 2 cycles in a row):

**Autonomous mode (default):** Accept the current scores, classify remaining issues
(code-fixable / infrastructure / third-party), and include the classification in the
final report. Do not block the pipeline on Lighthouse scores — they are performance
optimizations, not correctness issues. The user will see the report and decide on
follow-up.

**Override:** If the user explicitly asked for perfect scores, report the plateau and
ask for guidance.

### Step 5.5: Handle Unfixable Scores

Some audits may be impossible to fix to 100 (e.g., third-party scripts, CDN latency). If a category plateaus:

1. List the remaining failing audits
2. Classify each as: fixable (we missed something) | infrastructure (needs cloud/CDN change) | third-party (out of our control)
3. Present to user with recommendations
4. User decides: accept current score, try infrastructure changes, or remove third-party scripts

---

## Phase 6: Final Report & Compound

### Step 6.1: Final Score Report

Present the final report using the template in `~/.claude/skills/ship-test-ensure/refs/final-report-template.md`.

### Step 6.2: Compound Knowledge

1. If any Lighthouse fix was non-obvious → create solution doc in `docs/solutions/performance/`
2. If a deploy failed for a new reason → document in `docs/solutions/infrastructure/`
3. Update the session learnings file with pipeline results
4. If any pattern repeated across pages → add prevention rule to the project's patterns/solutions docs
5. **Cross-project promotion** — run compound Steps 7-8 (from /compound skill):
   - Update `~/.claude/evolution/error-registry.json` with any deploy/staging/Lighthouse errors
   - Update `~/.claude/evolution/model-performance.json` with model performance this session
   - Log any system changes in `~/.claude/evolution/workflow-changelog.md`
   - Write session postmortem to `~/.claude/evolution/session-postmortems/`

### Step 6.3: Rollback Protocol

If production **deploy** (Phase 4) fails after 3 fix iterations, or if critical functional
issues are found post-deploy. Do NOT trigger rollback for Lighthouse score issues (Phase 5)
— those are performance optimizations, not production incidents.

**This is a mandatory gate — always ask the user, even in autonomous mode.** Rollback is
a destructive action that requires human judgment.

1. Present rollback option to user:
   > **Production verification failing after 3 fix cycles.**
   > Pre-deploy SHA: `{PRE_DEPLOY_SHA}`
   > Options: **Revert and redeploy** | **Continue fixing** | **Accept current state**

2. If user chooses revert: create a `revert/rollback-TIMESTAMP` branch, run `git revert --no-edit ${PRE_DEPLOY_SHA}..HEAD` to revert all commits since the pre-deploy SHA, push and create a PR via `gh pr create`, merge via the same pattern as Step 1.3, then follow the deploy to confirm rollback succeeded.

3. Log the rollback in session-learnings and error-registry

---

Follow the **Compact Recovery Protocol** from CLAUDE.md. For this skill specifically: look for `## Ship Pipeline State` in session learnings to determine resume point.

---

## Standards

- All `gh` commands target `--repo {github_repo}` from Execution Config
- Never force push
- Never skip staging verification before production
- Confirm with user before production deploy
- PageSpeed API: no key needed for public URLs, but rate-limited (~1 req/sec)
- Add 2-second delay between PageSpeed API calls to avoid rate limits
- Lighthouse scores can vary by ~3 points per run — run twice and take the lower score for accuracy
- Use `{kill_command}` from Execution Config before starting processes
- Use `{package_manager}` from Execution Config exclusively — never mix package managers
- Keep fix commits atomic — one fix per commit for easy revert
- Log every fix iteration to the session learnings file

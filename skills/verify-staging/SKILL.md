---
name: verify-staging
description: >
  Verify a feature is live and healthy on staging without deploying. Hits each
  staging health endpoint, runs the project's Playwright smoke suite against
  the staging URL, checks the active PRD's acceptance criteria one-by-one with
  cited evidence, and flags any unexpected production auto-deploys. Use when
  the user says "verify staging", "check staging", "is it live yet", or after a
  PR has merged to staging and they want a quick sign-off before manual QA.
  Does NOT deploy anything — that's `/ship-test-ensure`.
---

# Verify Staging — Health, Smoke, and AC Check Against Live Staging

Read-only verification pass against deployed staging. Codifies the
"hit health + Playwright smoke + match against PRD ACs" loop the user has
reassembled multiple times in past sessions.

**Does NOT deploy. Does NOT commit. Does NOT push.** It only reads:
- Staging health endpoints (HTTP)
- Staging URLs via Playwright (HTTP + screenshots)
- Active PRD acceptance criteria (filesystem)
- Recent CI runs (GitHub API, optional)

**Autonomous by default.** Runs end-to-end without interruption. Reports a
PASS/FAIL/BLOCKED summary at the end. The user can then decide to deploy to
prod via `/ship-test-ensure` or fix issues found.

---

## Phase 0: Working Directory Sanity Check

Same gate as `/plan-build-test` Phase 0a:

```bash
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  umbrella_children=$(find . -mindepth 2 -maxdepth 2 -type d -name '.git' -printf '%h\n' 2>/dev/null | sort)
  if [ -n "$umbrella_children" ]; then
    echo "BLOCKED: cwd is an umbrella folder. cd into one of:"
    printf '  - %s\n' $umbrella_children
    exit 1
  fi
  echo "BLOCKED: cwd is not a git repository."
  exit 1
fi
[ -f CLAUDE.md ] || echo "WARN: no CLAUDE.md — staging URLs must be supplied interactively."
```

On BLOCKED: report and STOP. Do not proceed.

---

## Phase 1: Discover Staging Targets

Resolution order — first match wins:

1. **Project CLAUDE.md `## Staging Verification` section.** Expected format:
   ```markdown
   ## Staging Verification
   - **Staging URL:** https://staging.example.com
   - **Health endpoint:** https://staging.example.com/api/health
   - **Playwright smoke:** `pnpm test:e2e:staging`
   - **CI workflow (prod gate):** .github/workflows/deploy-prod.yml
   ```
2. **Project CLAUDE.md `## Execution Config` section.** Look for keys: `staging_url`, `staging_health`, `e2e_staging`.
3. **Common config files:** `vercel.json` (alias/domain), `wrangler.toml` (`route`), `.github/workflows/deploy-staging.yml` (env URLs), `infrastructure/staging.tf` (DNS).
4. **Ask user via `AskUserQuestion`** with one question listing what was found, and a free-form fallback for the staging URL.

**Multi-app projects** (e.g. causeflow's `web/` has both `apps/website` and `apps/dashboard`): expect a list of `(app_name, staging_url, health_endpoint)` tuples. Verify each app independently in Phase 2.

Cache the resolved targets in working memory for subsequent phases — don't re-discover.

---

## Phase 2: Health Endpoint Sweep

For each `(app, staging_url, health_endpoint)` tuple, curl the health endpoint:

```bash
curl -sS -o /tmp/health-out -w "%{http_code} %{time_total}s\n" \
  --max-time 15 "$health_endpoint"
cat /tmp/health-out
```

Expected:
- HTTP 200
- Response time < 5s (warn if slower; fail if timed out)
- Body parses as JSON (or matches the project's documented health-response shape)

If the project documents a `status: "ok"` field or similar in its health-endpoint contract (search project CLAUDE.md / OpenAPI spec / inline route comment), assert it. Otherwise trust the 200.

**Report as a table:**

```
| App        | Endpoint                                | Status | Time   | Result |
|------------|-----------------------------------------|--------|--------|--------|
| core       | https://api-staging.example.com/health  | 200    | 0.42s  | PASS   |
| dashboard  | https://app-staging.example.com/api/h   | 200    | 0.38s  | PASS   |
| website    | https://staging.example.com/            | 200    | 0.21s  | PASS   |
```

**Any non-200 → mark BLOCKED for that app and skip its Phase 3 smoke.** Continue verifying other apps.

---

## Phase 3: Playwright Smoke Against Staging

For each app with a passing health check AND a Playwright command from Phase 1:

1. **Set the base URL via env** — convention is `BASE_URL=$staging_url` or `PLAYWRIGHT_BASE_URL=$staging_url`. Project CLAUDE.md should document which.
2. **Run the smoke command** (NOT the full E2E suite — staging verification should take < 2 min):
   ```bash
   BASE_URL="$staging_url" $playwright_smoke_command 2>&1 | tee /tmp/playwright-smoke-$app.log
   ```
3. **If no smoke command exists** in project config, create an inline ad-hoc smoke test:
   - Navigate to staging URL root
   - Wait for the page's documented "ready" selector (or DOMContentLoaded)
   - Screenshot at 4 viewports (375 / 768 / 1280 / 1920)
   - Capture browser console errors
   - Save screenshots to `.artifacts/playwright/screenshots/$(date +%F_%H%M)/$app/`

Do NOT spawn a sub-agent for this — Playwright must run in the orchestrator's context to keep browser state attached (per CLAUDE.md "What stays in the main agent").

**Pass criteria:**
- All Playwright tests exit 0
- Console errors count: 0
- Screenshots produced for each documented route × viewport

**On failure:**
- Capture full failure output
- Mark FAIL for that app — do NOT retry (this is read-only verification, not the build loop)
- Continue to next app

---

## Phase 4: Acceptance Criteria Check Against Active PRD

Read the active-plan pointer to find the PRD currently being executed:

```bash
bash ~/.claude/hooks/scripts/active-plan-read.sh
```

If exit 0, parse `prd_dir` from the JSON. Read `$prd_dir/spec.md` and any sprint specs in `$prd_dir/sprints/`. For each acceptance criterion (lines starting with `- [ ]` or `- [x]` under an `## Acceptance Criteria` heading):

For each AC:
1. Determine what evidence would prove it (route returning 200, content match, screenshot showing UI element, log line, etc.).
2. Check evidence collected in Phases 2-3 — does it satisfy the AC?
3. Mark: **MET** (with cited evidence), **NOT MET** (with reason), or **CANNOT VERIFY** (verification needs auth, data, or scope outside this skill).

**Report as a table:**

```
| AC                                              | Status        | Evidence                          |
|-------------------------------------------------|---------------|-----------------------------------|
| Dashboard renders incident timeline             | MET           | Playwright screenshot 1280px      |
| Health endpoint reports relay connection state  | MET           | curl /health body has relay:"ok"  |
| Tenant isolation enforced on /api/incidents     | CANNOT VERIFY | needs Clerk session (not in env)  |
| Sentry capture on uncaught exception            | NOT MET       | no Sentry events in last hour     |
```

**If no active PRD:** skip Phase 4 with a note: "No active plan — running staging verification standalone."

---

## Phase 5: Unexpected Production Auto-Deploy Check

A recurring incident: a merge to `main` triggered a prod deploy without going through `/ship-test-ensure`'s human gate. Detect this by inspecting recent CI runs:

```bash
# Last 24h of workflow runs across all workflows
gh run list --limit 50 --json name,event,createdAt,headBranch,conclusion,workflowName \
  --created ">$(date -u -d '24 hours ago' +%FT%TZ)" 2>/dev/null
```

Filter for workflows whose name matches `prod|production` and whose `event` is NOT `workflow_dispatch` (manual). Any such run is suspicious.

**Report findings:**
- Suspicious runs found → list them in the final report under `## ⚠ Unexpected Production Activity` and ask the user whether to investigate before continuing.
- Clean → one-line confirmation: "No unexpected prod deploys in last 24h."

If `gh` is not installed or not authed, skip this phase with a one-line note. Don't fail the whole verification on it.

---

## Phase 6: Final Report

Present a single markdown summary:

```markdown
# Staging Verification Report

**Project:** <repo name>
**Run at:** <ISO timestamp>
**Active PRD:** <prd_slug or "none">

## Health
[table from Phase 2]

## Smoke
[per-app Playwright result + screenshot path]

## Acceptance Criteria
[table from Phase 4, or "no active PRD"]

## Production Activity
[Phase 5 result]

## Verdict
- PASS — all health 200, smoke green, ACs met → ready for `/ship-test-ensure`
- FAIL — at least one health/smoke/AC failure → fix before deploying to prod
- BLOCKED — verification incomplete (env limitation, missing config) → resolve and re-run
```

Then exit. Do NOT auto-invoke `/ship-test-ensure` or any other skill — the user decides next steps.

---

## Standards (skill-specific, in addition to CLAUDE.md)

- **Read-only.** This skill never deploys, commits, pushes, or modifies the repo. Artifacts (screenshots, logs) go under `.artifacts/` per CLAUDE.md.
- **Per-app, not per-route.** A staging URL with 50 routes does not need 50 health checks — one health endpoint per app is canonical. Route-level verification belongs in `/plan-build-test` Phase 5.
- **Stateless across runs.** Each invocation re-discovers from project CLAUDE.md. Do not cache staging URLs across sessions.
- **Surface, don't fix.** This skill reports problems but does not fix them. Fixing belongs in `/plan-build-test`. Re-deploying belongs in `/ship-test-ensure`.

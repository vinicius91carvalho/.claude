# Verification Gates Reference

Every agent in the system has mandatory verification gates that BLOCK progression.
A gate that is not passed is either BLOCKED (with reason) or the agent loops to fix it.
A gate is NEVER skipped or silently marked as passed.

---

## Gate Philosophy

**The root cause of premature completion:**
- Tests pass but app is broken (cached state, coverage gaps, env differences)
- HTTP 200 returned but page contains error content
- Tasks checked off but acceptance criteria not actually verified
- Completion claimed from memory without re-reading the plan

**The fix: every completion claim requires cited evidence.**

"Tests pass" is not evidence. "Route /en/product returns 200 and response body contains
'Product Page' heading and product grid with 6 items" is evidence.

---

## Gate Definitions

### Gate 1: Static Analysis (sprint-executor, orchestrator, plan-build-test)

| Check | Pass criteria | Evidence required |
|-------|--------------|-------------------|
| Build | Exit code 0 | Actual exit code from command |
| Lint | Exit code 0, 0 issues | Actual exit code + issue count |
| Type-check | Exit code 0 | Actual exit code from command |
| Tests | Exit code 0, all pass | Actual exit code + pass/fail counts |

**Failure mode this catches:** Syntax errors, type mismatches, lint violations, test regressions.

**What this does NOT catch:** Runtime failures, rendering bugs, broken routes, cached state issues.

### Gate 2: Dev Server Startup (orchestrator, plan-build-test)

| Check | Pass criteria | Evidence required |
|-------|--------------|-------------------|
| Server starts | Process running, port open | PID, port number |
| Root URL responds | HTTP 200 within 60s | Actual HTTP status code |
| No startup errors | No error output | Absence of errors in stderr |

**Failure mode this catches:** Missing dependencies, config errors, port conflicts, broken imports.

**What this does NOT catch:** Routes that 200 but show error content, correct routes with wrong data.

### Gate 3: Content Verification (orchestrator, plan-build-test)

**Note:** Sprint-executors do NOT run Gate 2 or Gate 3 — these are integration concerns handled
by the orchestrator after merge (changed in v3 to eliminate redundant dev server cycles).

| Check | Pass criteria | Evidence required |
|-------|--------------|-------------------|
| Routes return expected content | Key text/headings present in response body | Specific strings found in curl/snapshot output |
| No error content | No "Internal Server Error", stack traces, "undefined" | Absence verified in response body |
| Acceptance criteria visible | Each criterion maps to rendered content | Criterion → content mapping cited |

**Failure mode this catches:** 200 responses with error pages, empty renders, wrong data, stale cache.

**This is the gate that catches "128/128 tests pass but site is broken."**

### Gate 4: Route Health (plan-build-test Phase 5)

| Check | Pass criteria | Evidence required |
|-------|--------------|-------------------|
| All routes return 200 | Every `app/**/page.tsx` route curled | Route → status code table |
| All locales work | Each locale variant tested | Locale routes in table |

**Failure mode this catches:** Missing pages, broken dynamic routes, locale config errors.

### Gate 5: Plan Completeness Audit (sprint-executor, orchestrator, plan-build-test)

| Check | Pass criteria | Evidence required |
|-------|--------------|-------------------|
| All tasks checked | Every `- [ ]` is now `- [x]` | Count of checked/total |
| All criteria met | Each acceptance criterion has evidence | Criterion → evidence mapping |
| Plan re-read | Agent re-read the actual file (not from memory) | File was read in this turn |

**Failure mode this catches:** Partial completion claimed as full, forgotten tasks, criteria assumed met.

**This is the gate that catches "implemented partial fixes and declared completion."**

### Gate 6: E2E / Playwright (plan-build-test Phase 5)

| Check | Pass criteria | Evidence required |
|-------|--------------|-------------------|
| Tests pass | Exit code 0 | Actual exit code + counts |
| Screenshots captured | All routes at all viewports | Screenshot count |
| Console errors | 0 errors | Error count from test output |

**proot-distro note:** Chromium works in proot (`/usr/bin/chromium`). Playwright tests, screenshots, and `browser_take_screenshot` all function normally.

---

## Gate Ordering

```
Sprint-Executor:
  Gate 1 (Static) → Gate 5 (Plan Audit)
  (Dev server and content verification are handled by the orchestrator after merge)

Orchestrator:
  Gate 1 (Coherence) → Gate 2 (Dev Server) → Gate 3 (Content) → Gate 5 (Plan Audit)

Plan-Build-Test Phase 5:
  Gate 1 (Static) → Gate 2 (Dev Server) → Gate 3 (Content) → Gate 4 (Routes) →
  Gate 6 (E2E) → Gate 5 (Plan Audit)
```

Each gate is BLOCKING. If a gate fails, the agent must fix or report BLOCKED.
Agents MUST NOT skip a gate to reach the next one.

---

## Anti-Patterns (things that look like verification but aren't)

| Looks like verification | Why it's not | What to do instead |
|------------------------|-------------|-------------------|
| "All 128 tests pass" | Tests can pass while app is broken | Start dev server, curl routes, check content |
| "Build succeeded" | Build ≠ runtime correctness | Start dev server and verify routes |
| "I completed all tasks" | Did you re-read the plan? | Re-read the spec file, enumerate remaining |
| "HTTP 200 on all routes" | 200 can contain error page | Check response body for expected content |
| "Dev server starts" | Starting ≠ serving correct content | Curl routes and inspect response bodies |
| "Acceptance criteria met" | Based on what evidence? | Cite specific command output for each criterion |

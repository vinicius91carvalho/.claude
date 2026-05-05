---
name: autonomous-staging
description: >
  End-to-end hands-off run from PRD to staging. Chains /plan-build-test then
  /ship-test-ensure with CLAUDE_PIPELINE_MODE=staging-only,aggressive-fix-loop.
  Halts before production with exit 99 — the canonical success state for staging-only
  delivery. User verifies staging, then runs /ship-test-ensure manually for prod.
  Use for "ship the PRD to staging unattended", "fire and forget", or "autonomous staging".
---

# Autonomous Staging — Hands-Off PRD → Staging Pipeline

This skill runs the full pipeline without interruption: pre-flight, adopt plan, set
mode flags, chain `/plan-build-test` (implementation + local tests), then
`/ship-test-ensure` (commit, PR, staging deploy, staging E2E) — no user prompts. It
halts at **exit 99** before production. That is the expected success state. After exit
99: inspect the staging report, then invoke `/ship-test-ensure` directly (without
`staging-only`) to promote to production.

**When to use:** "autonomous staging", "ship the PRD unattended", "fire and forget to
staging". Do NOT use when you need interactive checkpoints mid-pipeline.

---

## Mode Flags

This skill is the **sole producer** of `staging-only` and `aggressive-fix-loop`.
Consumer skills (`/plan-build-test`, `/ship-test-ensure`) only READ them — never set
them. Per **Invariant 4** (Cross-Skill Mode-Flag Handshake), any new mode flag must be
defined here AND in each consumer's `## Mode Flags` section. No orphan flags.

| Flag                  | Consumer | Effect |
|-----------------------|----------|--------|
| `staging-only`        | `/ship-test-ensure` | Exits 99 before Phase 4 production deploy (`PROD-FORBIDDEN: staging-only mode active`) |
| `aggressive-fix-loop` | `/plan-build-test`  | Raises `logic` retry budget from 2 → 4 in Phase 5.7 |

Both flags are always set together. `aggressive-fix-loop` compensates for the missing
human mid-pipeline; `staging-only` guarantees prod is unreachable. Consumers test via
substring match: `[[ "$CLAUDE_PIPELINE_MODE" == *staging-only* ]]`.

---

## Phase 0a: Working Directory Sanity Check

**Fail-fast. Same pattern as `/plan-build-test` Phase 0a.**

```bash
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  umbrella_children=$(find . -mindepth 2 -maxdepth 2 -type d -name '.git' -printf '%h\n' 2>/dev/null | sort)
  if [ -n "$umbrella_children" ]; then
    echo "BLOCKED: cwd is an umbrella folder containing multiple sibling repos:"
    printf '  - %s\n' $umbrella_children
    echo "cd into the specific repo you want to work in, then re-invoke /autonomous-staging."
    exit 2
  fi
  echo "BLOCKED: cwd is not a git repository and has no child repos."
  echo "/autonomous-staging needs a project repo with CLAUDE.md + Execution Config."
  exit 2
fi
[ -f CLAUDE.md ] || echo "WARN: no CLAUDE.md in $(pwd) — Execution Config may be missing."
```

On BLOCKED: report and STOP (exit 2). On WARN: continue; Phase 2 will surface config issues.

---

## Phase 0b: Ownership Pre-Flight

**Verify a build-candidate plan exists and no competing session owns it. Fast exit
(< 2 seconds, no agents, no git changes) when nothing to do.**

```bash
plan_json=$(bash ~/.claude/hooks/scripts/active-plan-read.sh 2>/dev/null) || {
  echo "Nothing to do: no active plan pointer. Run /plan or /adopt-plan first."
  exit 0
}
prd_dir=$(echo "$plan_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['prd_dir'])")
PRD_SLUG=$(echo "$plan_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['prd_slug'])")
export PRD_SLUG

progress_file="$prd_dir/progress.json"
if [ -f "$progress_file" ]; then
  # Refuse if another session has a live claim (heartbeat < 30 min, claimed_by_session != $CLAUDE_SESSION_ID)
  competing=$(python3 -c "
import json,datetime
data=json.load(open('$progress_file'))
threshold=int('$(date -d '30 minutes ago' +%s 2>/dev/null || date -v-30M +%s)')
for s in data.get('sprints',[]):
  owner=s.get('claimed_by_session','')
  if owner and owner!='$CLAUDE_SESSION_ID' and s.get('status')=='in_progress':
    try:
      hb=int(datetime.datetime.fromisoformat(s.get('claim_heartbeat_at','').replace('Z','+00:00')).timestamp())
      if hb>threshold: print(owner[:8]); break
    except: pass
" 2>/dev/null)
  [ -n "$competing" ] && {
    echo "REFUSED: sprint claimed by session ${competing}... (heartbeat < 30 min). Run /adopt-plan to force-release."
    exit 3
  }

  eligible=$(python3 -c "import json; d=json.load(open('$progress_file')); print(sum(1 for s in d.get('sprints',[]) if s.get('status')=='not_started'))" 2>/dev/null)
  [ "${eligible:-0}" -eq 0 ] && {
    echo "Nothing to do: all sprints complete or permanently BLOCKED in $PRD_SLUG."
    exit 0
  }
fi
```

---

## Phase 1: Set Pipeline Environment

```bash
# Invocation ID format: <unix-timestamp>-<random4-lowercase>
# openssl rand -hex 2 produces exactly 4 hex chars (e.g. a3f2)
export CLAUDE_PIPELINE_INVOCATION_ID="$(date +%s)-$(openssl rand -hex 2)"
export CLAUDE_PIPELINE_MODE="staging-only,aggressive-fix-loop"
export PIPELINE_START_TS=$(date +%s)
echo "ID: $CLAUDE_PIPELINE_INVOCATION_ID | Mode: $CLAUDE_PIPELINE_MODE"
echo "Worktree ns: .worktrees/$PRD_SLUG/run-$CLAUDE_PIPELINE_INVOCATION_ID/"
```

**Worktree namespace:** `.worktrees/$PRD_SLUG/run-$CLAUDE_PIPELINE_INVOCATION_ID/<sprint-name>`.
Extends the base `.worktrees/$PRD_SLUG/` with a per-invocation suffix so two consecutive
`/autonomous-staging` runs never collide. Cleanup is deferred to the `cleanup-worktrees.sh`
Stop hook — this skill does NOT clean up mid-run.

---

## Phase 2: Invoke /plan-build-test

With `CLAUDE_PIPELINE_MODE` exported, invoke `/plan-build-test`. It inherits both flags:
sees `aggressive-fix-loop` → raises logic retry budget to 4; runs Phases 1–6
(plan → implement → test → verify) autonomously without prompts.

**On success (exit 0):** proceed to Phase 3.
**On failure (non-zero):** skip Phase 3; jump to Phase 4 reporting:
```
/plan-build-test FAILED (exit <code>) — /ship-test-ensure NOT invoked.
Category: <transient|logic|environment|config> | Last error: <summary>
```

---

## Phase 3: Invoke /ship-test-ensure

With `CLAUDE_PIPELINE_MODE=staging-only,aggressive-fix-loop` still exported, invoke
`/ship-test-ensure`. It runs Phase 0–3 (commit, branch, PR, merge, staging deploy, E2E),
then reaches Phase 4 where the `staging-only` guard fires first:
```bash
if [[ "$CLAUDE_PIPELINE_MODE" == *staging-only* ]]; then
  echo "PROD-FORBIDDEN: staging-only mode active"; exit 99
fi
```

**Expected exit codes from /ship-test-ensure:**
- `99` — staging-only halt. **Canonical success path** for this wrapper.
- `0`  — full success (anomalous; Phase 4 guard may not have fired — treat as success, flag in report).
- other — actual failure; capture and surface in Phase 4 report.

---

## Phase 4: Final Report

Collect artifacts and print the structured report to stdout. Read `$prd_dir/progress.json`
for sprint statuses and PR URLs; read `$prd_dir/spec.md` Section 6 for AC list; optionally
invoke `/verify-staging` for staging-health and AC-evidence rows.

**Required sections:**
1. **Header** — Invocation ID, PRD slug, start time, total duration
2. **Sprints** — status table (title, status, branch, PR URL)
3. **Test pass rate** — unit / integration / E2E counts
4. **Staging** — URL, health status, E2E result, Lighthouse scores (LCP, CLS, INP)
5. **Acceptance Criteria** — AC table from PRD spec.md §6 with evidence and status
6. **Blocked items** — item, category, last attempt
7. **Session learnings** — any entries appended during this run
8. **Next step** — `exit 99 reached (expected success). Verify staging URL above, then run /ship-test-ensure (without staging-only flag) for prod.`

---

## Exit Code Contract

| Code | Meaning | Action |
|------|---------|--------|
| `0`  | Full pipeline success (anomalous under staging-only; Phase 4 guard may not have fired) | Treat as success, flag in report |
| `99` | **Staging-only halt — expected success state** | Verify staging, then run `/ship-test-ensure` for prod |
| `1`  | Sprint failure after exhausting aggressive-fix-loop budget | Fix root cause, re-invoke |
| `2`  | Phase 0a pre-flight: not a git repo or umbrella folder | `cd` into correct repo |
| `3`  | Phase 0b refusal: competing live session owns a sprint | Wait or run `/adopt-plan` |

**exit 99 is NOT an error.** Monitoring and CI consumers MUST treat exit 99 as the
staging-delivery success signal.

---

## Cross-Skill Mode-Flag Handshake

Per **Invariant 4**: `/autonomous-staging` is the sole producer. `/plan-build-test` and
`/ship-test-ensure` are consumers — they READ `CLAUDE_PIPELINE_MODE` but never SET it.

Verify no orphan flags:
```bash
for flag in staging-only aggressive-fix-loop; do
  count=$(grep -rl "$flag" ~/.claude/skills/ 2>/dev/null | wc -l)
  [ "$count" -ge 2 ] || { echo "FAIL: $flag in <2 SKILL.md files"; exit 1; }
done && echo OK
```

---

## Standards (skill-specific)

- **Never calls `AskUserQuestion`** between Phase 0b and Phase 4. Autonomous contract.
- **Never touches `~/.claude/state/active-plan-*.json` directly** — use `active-plan-read.sh`.
- **Never unsets `CLAUDE_PIPELINE_MODE` or `CLAUDE_PIPELINE_INVOCATION_ID` mid-run** — downstream skills depend on them.
- **Never includes production-deploy logic** — this skill must never trigger prod, directly or indirectly.
- **Worktree cleanup deferred to Stop hook** — `cleanup-worktrees.sh` runs at session end.

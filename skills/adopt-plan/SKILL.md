---
name: adopt-plan
description: >
  Adopt a PRD owned by another (typically dead) session — list adoptable plans
  in this repo, pick one, force-release any stuck sprint claims, and write a
  fresh active-plan pointer for THIS session. Auto-invoke when the user says
  "adopt plan", "take over plan", "resume someone else's plan", "my pointer is
  gone", or runs /adopt-plan. Do NOT auto-invoke on every fresh terminal —
  /plan-build-test Phase 0 already self-adopts when this session is the legitimate owner.
---

# Adopt Plan: Take Over a Foreign or Orphaned PRD

## When to use

- A previous session crashed mid-build and its pointer was GC'd. You want to finish its plan from a new terminal.
- You want to hand a plan from one terminal to another deliberately (e.g. tmux session ended).
- A peer dev started a plan, went home, and you're picking it up.

**Do NOT use this when:**

- This session legitimately owns the plan (`progress.json.owner_session_id == $CLAUDE_SESSION_ID`) — `/plan-build-test` Phase 0 self-adopts silently.
- The plan is fresh from `/plan` and has not been bound to any session yet (`progress.json.owner_session_id` is `null` or empty). This is the normal handoff — just run `/plan-build-test`; Phase 0 binds the plan automatically via `bind-plan.sh`.
- A peer session is actively running (claim heartbeat < 30 min). Wait or kill the peer first.

## Steps

### Step 1: Discover adoptable plans

Search the repo for `progress.json` files with at least one sprint that is `not_started` or `in_progress`. For each, classify:

```bash
git -C "$(git rev-parse --show-toplevel)" tag -l 'build-candidate/*'
# Plus: docs/tasks/**/progress.json (and convention fallbacks)
```

For each candidate, gather:

| Field | Source |
|---|---|
| PRD path | directory containing `progress.json` |
| `prd_slug` | `jq -r .prd_slug progress.json` (v2) or basename of dir (v1) |
| `owner_session_id` | `jq -r .owner_session_id progress.json` (v2) or `(legacy)` (v1) |
| Owner liveness | `[ -f $HOME/.claude/state/active-plan-${owner}.json ]` AND any `agent-*.json` in `~/.claude/state/active/` with matching `session_id` modified < 30 min ago |
| Sprint state | counts of `not_started` / `in_progress` / `complete` / `blocked` |
| Last activity | most recent `claim_heartbeat_at` across sprints, or `created` if never claimed |

Mark each as:

- **MINE** — `owner_session_id == $CLAUDE_SESSION_ID` or last `adopted_by[].session_id == $CLAUDE_SESSION_ID`. Tell the user `/plan-build-test` will self-adopt; no `/adopt-plan` needed. Skip.
- **UNBOUND** — `schema_version: 2` AND `owner_session_id` is null/empty AND `adopted_by[]` is empty. This is a fresh `/plan` output awaiting an executor. Tell the user to just run `/plan-build-test` — Phase 0 binds it automatically via `bind-plan.sh`. Skip.
- **LIVE PEER** — owner has live pointer + active agent — refuse to adopt; print the peer session prefix so the user can investigate.
- **STALE PEER** — owner has no live pointer OR last heartbeat > 30 min — adoptable.
- **LEGACY (v1)** — no `schema_version` field — adoptable, but bind/adopt prompt should ask the user which mode.

### Step 2: Present the list

Use `AskUserQuestion` with one option per adoptable plan. Format each option:

```
<prd_slug> — N sprints (X complete, Y in_progress, Z not_started). Owner: <prefix>... last seen <duration> ago.
```

Add `Cancel` as the last option.

### Step 3: Adopt the chosen plan

Once the user picks:

1. **Migrate schema if v1:** `bash ~/.claude/hooks/scripts/migrate-progress-v1-to-v2.sh "$PRD_DIR/progress.json" "$CLAUDE_SESSION_ID" adopt`. This sets `schema_version=2`, leaves `owner_session_id` empty (preserving original authorship audit trail), and appends `{session_id, adopted_at, reason: "migrate-adopt"}` to `adopted_by[]`.

2. **For v2 plans:** still record adoption — the helper appends to `adopted_by[]` even when no schema migration is needed.

3. **Force-release any stuck claims** owned by the old session:
   ```bash
   for SID in $(jq -r '.sprints[] | select(.status=="in_progress") | .id' "$PRD_DIR/progress.json"); do
     bash ~/.claude/hooks/scripts/release-sprint.sh "$PRD_DIR/progress.json" "$SID" "$ORIGINAL_OWNER" not_started
   done
   ```
   This resets stuck sprints to `not_started` so this session can re-claim them cleanly. Use the original owner's session id (read from `progress.json.owner_session_id` BEFORE migration). If the helper refuses (claim mismatch), use `claim-sprint.sh --force` instead — only the most recent adopter has the right to override.

   Note: `release-sprint.sh` strictly requires the caller's session_id to match `claimed_by_session`. For adoption we override via `claim-sprint.sh --force` which clears the stale claim atomically. If your release helper version doesn't support this exact flow, fall back to `claim-sprint.sh --force` followed by an immediate `release-sprint.sh ... not_started` from the new claimer's session.

4. **Write the active-plan pointer for this session:**
   ```bash
   bash ~/.claude/hooks/scripts/active-plan-write.sh "$PRD_DIR"
   ```
   Verify: `[ -f "$HOME/.claude/state/active-plan-${CLAUDE_SESSION_ID}.json" ]`.

5. **Verify integration branch exists** (`prd/<slug>`). If not, create it from `main`:
   ```bash
   git rev-parse --verify "prd/$PRD_SLUG" >/dev/null 2>&1 || git branch "prd/$PRD_SLUG" main
   ```

### Step 4: Report and stop

Tell the user:

> Adopted PRD `<slug>`. Pointer written for this session. Stuck claims released to `not_started`. Run `/plan-build-test` to resume — it will pick up from `progress.json`.

Do NOT auto-invoke `/plan-build-test`. The user starts a fresh execution turn.

## What this skill does NOT do

- Does NOT delete the original session's pointer (GC handles that on its own 24h schedule).
- Does NOT rewrite `owner_session_id` — only appends to `adopted_by[]`. The audit trail is permanent.
- Does NOT touch peer sessions' worktrees or branches. The orchestrator and `cleanup-worktrees.sh` use the new pointer's `prd_slug` to scope namespace operations.
- Does NOT adopt LIVE peer plans — refuses with a clear error.

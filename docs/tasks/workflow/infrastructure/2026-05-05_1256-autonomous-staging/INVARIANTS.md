# INVARIANTS — Autonomous Staging Pipeline

Cross-cutting contracts shared between `/autonomous-staging` (consumer), `/ship-test-ensure` (producer of `staging-only`), and `/plan-build-test` (producer of `aggressive-fix-loop`).

---

## CLAUDE_PIPELINE_MODE Value Vocabulary

- **Owner:** `~/.claude/skills/autonomous-staging/SKILL.md` (Sprint 3)
- **Preconditions:** Consumer skills (`/ship-test-ensure`, `/plan-build-test`) must parse `$CLAUDE_PIPELINE_MODE` as a comma-separated string and check for substring matches (e.g. `case "$CLAUDE_PIPELINE_MODE" in *staging-only*) ...`).
- **Postconditions:** Owner sets the env var to ONLY documented values (`staging-only`, `aggressive-fix-loop`, or comma-combination of both). Empty/unset is the canonical default.
- **Invariants:** Only two values exist in the vocabulary today: `staging-only`, `aggressive-fix-loop`. Adding a third requires updating this invariant + all three SKILL.md files.
- **Verify:** `grep -rhoE 'CLAUDE_PIPELINE_MODE=[a-z,-]+' ~/.claude/skills/ 2>/dev/null | awk -F'=' '{print $2}' | tr ',' '\n' | sort -u | grep -v '^$' | grep -vE '^(staging-only|aggressive-fix-loop)$' | wc -l | grep -q '^0$'`
- **Fix:** If verify returns nonzero, an undocumented mode value was introduced. Either document it here and in the consumer skills, or rename it to one of the two existing values.

---

## staging-only Mode Unreachability of Production Phase

- **Owner:** `~/.claude/skills/ship-test-ensure/SKILL.md` (Sprint 1)
- **Preconditions:** `/autonomous-staging` MUST set `$CLAUDE_PIPELINE_MODE` to include `staging-only` before invoking `/ship-test-ensure`. The env var must be exported (not just shell-local) so it propagates to subsequent bash blocks.
- **Postconditions:** When the producer skill enters its production-deploy phase under `staging-only` mode, the very first executable line is a guard that exits 99 with message `PROD-FORBIDDEN: staging-only mode active`. No deploy command can run between phase header and exit.
- **Invariants:** The guard is the FIRST non-comment, non-blank executable line of the production-deploy phase. Any commit that adds prose, tool calls, or commands between the phase header and the guard is a violation.
- **Verify:** `grep -B 0 -A 8 'Phase 4.*Production\|Phase 4.*Deploy.*Production\|Deploy to Production' ~/.claude/skills/ship-test-ensure/SKILL.md | grep -E 'staging-only.*exit 99|PROD-FORBIDDEN' | grep -q .`
- **Fix:** Move the guard back to the top of Phase 4. If new logic was needed before the guard, that logic itself MUST also be safe under staging-only mode (preferable to keep the guard first and split intervening logic into its own pre-guard phase).

---

## Pipeline Invocation Namespace

- **Owner:** `~/.claude/skills/autonomous-staging/SKILL.md` (Sprint 3)
- **Preconditions:** Owner generates `$CLAUDE_PIPELINE_INVOCATION_ID` as `<unix-timestamp>-<random4-lowercase>` (e.g. `1714914000-a3f2`) at the start of each run, and exports it. Consumers (downstream skills, sprint-executor agents) read it for worktree paths.
- **Postconditions:** All worktrees created during a single `/autonomous-staging` invocation live under `.worktrees/$PRD_SLUG/run-$INVOCATION_ID/`. No worktree from this invocation lands elsewhere.
- **Invariants:** Two concurrent invocations of `/autonomous-staging` against the same PRD slug MUST produce non-overlapping worktree paths (different `INVOCATION_ID`s guarantee this). The cleanup-worktrees Stop hook removes per-invocation directories on session end.
- **Verify:** `grep -E '\.worktrees/.*PRD_SLUG.*run-.*INVOCATION_ID' ~/.claude/skills/autonomous-staging/SKILL.md | grep -q .`
- **Fix:** If the path convention drifts (e.g. someone removes the `run-$INVOCATION_ID` segment), restore it. Concurrent invocations would otherwise stomp each other's worktrees.

---

## Cross-Skill Mode-Flag Handshake

- **Owner:** This PRD (declared in spec.md Section 12)
- **Preconditions:** Any new mode flag added to the vocabulary MUST be defined in exactly one producer skill's `## Mode Flags` section AND referenced (by name) in `/autonomous-staging` SKILL.md.
- **Postconditions:** Every mode flag string used in production (passed through `CLAUDE_PIPELINE_MODE`) appears in BOTH the producer's SKILL.md (definition + behavior) AND the consumer's SKILL.md (the wrapper that sets it).
- **Invariants:** No "orphan" flag — a flag the wrapper sets but no skill consumes, OR a flag a skill consumes but no skill sets — exists in the system at any committed state.
- **Verify:** `for flag in staging-only aggressive-fix-loop; do count=$(grep -rl "$flag" ~/.claude/skills/ 2>/dev/null | wc -l); [ "$count" -ge 2 ] || { echo "FAIL: $flag in <2 SKILL.md files"; exit 1; }; done; echo OK`
- **Fix:** If a flag appears in only one file, either remove it (orphan flag) or add it to the consumer/producer counterpart.

---

## Aggressive Fix Loop Budget Source of Truth

- **Owner:** `~/.claude/skills/plan-build-test/SKILL.md` Phase 5.7 (Sprint 2)
- **Preconditions:** Phase 5.7 must define BOTH the default budget table (canonical: `transient: 5, logic: 2, environment: 1, config: 3`) AND the aggressive-mode delta (only `logic: 4`).
- **Postconditions:** When `$CLAUDE_PIPELINE_MODE` contains `aggressive-fix-loop`, the executor uses `logic: 4` for that category. Other categories are unaffected.
- **Invariants:** No other file in the system *defines* per-category retry budgets. `~/.claude/rules/quality.md` may reference the canonical default for context but does NOT define an aggressive override. `/autonomous-staging` may *reference* the budget delta (cross-skill handshake docs) but MUST NOT redeclare it as a normative table or numeric assignment.
- **Verify:** `grep -rEn '^\| *(transient|logic|environment|config) *\| *[0-9]+ *\|' ~/.claude/skills/ ~/.claude/rules/ 2>/dev/null | grep -v 'plan-build-test/SKILL.md' | grep -v 'docs/tasks' | wc -l | grep -q '^0$'`
- **Fix:** If another file shadows the budget table, delete that copy and reference Phase 5.7 instead.

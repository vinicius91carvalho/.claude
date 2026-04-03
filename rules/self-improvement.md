# Self-Improvement Protocol

## Per-Task Compound (every task — enforced by stop hook)

1. **Capture:** What worked? What didn't? What is the reusable insight?
2. **Document:** Create solution doc if reusable. Update session learnings.
3. **Update the system:** If a rule/pattern/doc needs changing, do it now — not "later."
4. **Verify:** "Would the system catch this automatically next time?" If no, compound is incomplete.
5. **Capture user corrections** as error-registry entries and model-performance data (richest signal).

## Per-Session Compound (end of session)

Run `/compound` — it handles: compile, generate rules, promote to solutions, persist to memory, cross-project evolution (error-registry, model-performance, workflow-changelog, session postmortem). Full protocol in `~/.claude/skills/compound/SKILL.md`.

**Periodic:** Run `/workflow-audit` monthly or after 10+ sessions.

## The Three Compound Questions

1. "What was the hardest decision made here?"
2. "What alternatives were rejected, and why?"
3. "What are we least confident about?"

## Knowledge Promotion Chain

**Per-project:** session-learnings → `docs/solutions/` → ADRs → CLAUDE.md updates. Promote when a pattern proves useful across 2+ tasks.

**Cross-project:** session-learnings → `~/.claude/evolution/error-registry.json` → `~/.claude/evolution/model-performance.json` → `~/.claude/projects/-root/memory/` → CLAUDE.md / skills / agents / hooks.

Evolution data lives in `~/.claude/evolution/` (error-registry, model-performance, workflow-changelog, session-postmortems). `/compound` handles promotion after every task. `/workflow-audit` reviews effectiveness monthly. **Compound is BLOCKING** — the stop hook prevents session end without capturing learnings.

Anti-patterns reference: `~/.claude/docs/anti-patterns-full.md`. Key rule: match ceremony to complexity.

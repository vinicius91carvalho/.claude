# Session Learnings & Compact Recovery

## Session Learnings

Maintain a session learnings file as **living memory** that survives `/compact`. Path from project CLAUDE.md `session-learnings-path`; default: `docs/session-learnings.md`. Created proactively by `/plan-build-test` Phase 0.

**Update rules:** Append errors as they occur, patterns when they repeat, rules when mistakes happen, task status as work progresses. Use structured format with categories (ENV, LOGIC, CONFIG, etc.) — full schema in `/compound` skill Step 6.

**Promotion:** 2+ tasks → `docs/solutions/`. 2+ projects → `~/.claude/evolution/error-registry.json` + memory.

## Compact Recovery Protocol

Automated by PreCompact/PostCompact hooks. Manual fallback when hooks miss state:

1. Re-read the session learnings file (path from project CLAUDE.md)
2. Re-read project knowledge files (patterns, MEMORY.md)
3. Resume from the last completed phase — do NOT restart
4. If mid-deploy or mid-monitoring, re-check current status before continuing

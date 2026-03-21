# Model Assignment Matrix

Adaptive — evolves via `~/.claude/evolution/model-performance.json`.

| Task Type                                     | Model    |
| --------------------------------------------- | -------- |
| File scanning, discovery, dependency analysis | `haiku`  |
| Simple fixes (lint, format, typos, CSS)       | `haiku`  |
| Session learnings compilation                 | `haiku`  |
| Standard implementation                       | `sonnet` |
| Bug fix implementation                        | `sonnet` |
| Test writing                                  | `sonnet` |
| Verification & regression scan                | `sonnet` |
| Sprint orchestration (deterministic checklist) | `sonnet` |
| Complex/multi-file refactoring                | `opus`   |
| Architectural decisions                       | `opus`   |
| Merge conflict resolution (>3 files)          | `opus`   |

## Adaptation Rules

After 10+ data points per task type, compound checks `model-performance.json`:
- If first-try success rate < 70% → propose upgrade to next model tier
- If first-try success rate > 90% → propose downgrade to save cost
- Changes require user approval; logged in `~/.claude/evolution/workflow-changelog.md`

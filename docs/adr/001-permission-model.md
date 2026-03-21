# ADR-001: Permission Model — bypassPermissions vs acceptEdits

**Status:** Decided — keep `bypassPermissions`
**Date:** 2026-03-21
**Context:** Workflow audit evaluated whether `acceptEdits` provides safer defaults.

## Options Evaluated

| Mode | File Edits | Bash Commands | UX Impact |
|------|-----------|---------------|-----------|
| `bypassPermissions` | Auto-approved | Auto-approved | Seamless — hooks are sole safety layer |
| `acceptEdits` | Auto-approved | **Prompted every time** | Excessive prompts for power users |

## Decision

Keep `bypassPermissions` with hooks as the enforcement layer.

## Rationale

1. `acceptEdits` prompts for **every** Bash command, which fundamentally breaks autonomous workflows
   (`/plan-build-test`, `/ship-test-ensure`). These skills run hundreds of Bash commands per session.
2. The hook system provides equivalent or stronger safety:
   - `block-dangerous.sh` hard-blocks catastrophic commands (rm -rf /, dd, fork bombs)
   - `block-dangerous.sh` soft-blocks destructive git (force push, reset --hard, push to main)
   - All hooks now have crash detection traps (exit 2 on unexpected errors) — silent failures are eliminated
3. `bypassPermissions` + robust hooks = safety WITHOUT UX degradation.

## Risk Mitigation

- Hook crash detection (ERR trap) converts silent failures into visible blocks
- `skipDangerousModePermissionPrompt: true` suppresses the startup warning (user is aware of the tradeoff)
- If hooks fail to load entirely (settings.json corruption), the `run-tests.sh` integrity suite catches it

## Reversal

If a hook bypass incident occurs, switch to `acceptEdits` and accept the prompt overhead:
```json
{ "permissions": { "defaultMode": "acceptEdits" } }
```

# Evaluation

## The Verification Pattern

LLMs are non-deterministic. The most reliable pattern combines:

1. **Prose specification** — intent, context, constraints (the PRD)
2. **Executable tests** — machine-verifiable correctness contract
3. **Iteration loops** — catch non-deterministic failures (run, fail, fix, run)

**Adaptive retry budget** (replaces fixed 3-retry):
- `transient` failures (network, timeout, flaky test) → up to 5 retries
- `logic` failures (wrong approach, broken implementation) → max 2, then try different approach
- `environment` failures (proot limitation, missing binary) → 1 retry, then mark BLOCKED
- `config` failures (bad setting, wrong flag) → max 3 retries

What tests cannot catch: security heuristics, architectural implications, complex layer interactions — human review is the judgment layer.

Full evaluation checklists (Stack Evaluation, Diagnostic Loop, Spec Self-Evaluator) live in `~/.claude/docs/evaluation-reference.md`. Load when needed for PRD review or post-sprint verification.

## Model Assignment

Default: haiku for scanning/simple fixes, sonnet for implementation/tests/orchestration, opus for complex refactoring/architecture/merge conflicts. Adaptive — evolves via `~/.claude/evolution/model-performance.json`. Full matrix and adaptation rules: `~/.claude/docs/model-assignment.md`.

## Code Intelligence

Prefer LSP over Grep/Glob/Read for code navigation:

| You say...                       | Claude uses...       |
| -------------------------------- | -------------------- |
| "Where is X defined?"            | `goToDefinition`     |
| "Find all usages of X"           | `findReferences`     |
| "What type is X?"                | `hover`              |
| "What functions are in file.ts?" | `documentSymbol`     |
| "Find the X class"               | `workspaceSymbol`    |
| "What implements X?"             | `goToImplementation` |
| "What calls X?"                  | `incomingCalls`      |
| "What does X call?"              | `outgoingCalls`      |

Before renaming or changing a function signature, use `findReferences` to find all call sites first. Use Grep/Glob only for text/pattern searches where LSP does not help. After writing or editing code, check LSP diagnostics and fix any type errors or missing imports immediately.

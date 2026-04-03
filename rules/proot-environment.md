# PRoot-Distro ARM64 Environment

Auto-detected via `uname -r` containing `PRoot-Distro`. Three layers: settings.json env vars, proot-preflight.sh (per-session warnings), worktree-preflight.sh (per-sprint setup). Full rules, native module failures, language-specific workarounds, and error patterns: `~/.claude/docs/proot-distro-environment.md`.

SessionStart hook auto-detects the environment and warns about known limitations.

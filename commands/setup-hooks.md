Detect the project stack and verify the hooks system is properly configured for this project.

## Steps to execute:

1. **Detect project stack** by checking for these files in the current project directory:
   - `biome.json` or `biome.jsonc` → Biome detected
   - `tsconfig.json` → TypeScript detected
   - `pnpm-lock.yaml` → pnpm detected
   - `package.json` → Node.js project detected
   - `eslint.config.*` or `.eslintrc.*` → ESLint detected

2. **Check required tools:**
   - Run `jq --version` — if missing, tell user: "Install jq: `apt install jq`"
   - If Biome detected: check `pnpm biome --version` works
   - If TypeScript detected: check if `@typescript/native-preview` (tsgo) is in devDependencies. If not, suggest: `pnpm add -D @typescript/native-preview`
   - Check `pnpm tsc --version` works as fallback

3. **Verify hook scripts exist and are executable:**
   - `~/.claude/hooks/post-edit-quality.sh` — PostToolUse: auto-formats TS/JS after Write/Edit
   - `~/.claude/hooks/end-of-turn-typecheck.sh` — Stop: type-checks TypeScript at end of turn
   - `~/.claude/hooks/block-dangerous.sh` — PreToolUse: blocks destructive commands
   - `~/.claude/hooks/compound-reminder.sh` — Stop: blocks session end without /compound
   - `~/.claude/hooks/proot-preflight.sh` — PreToolUse: proot-distro environment warnings
   - `~/.claude/hooks/worktree-preflight.sh` — Called by orchestrator for worktree setup
   - `~/.claude/hooks/retry-with-backoff.sh` — Sourceable utility for API retries
   - If any are missing or not executable, report it

4. **Verify settings.json has hooks configured:**
   - Read `~/.claude/settings.json`
   - Check for PostToolUse (Write|Edit|MultiEdit matcher), Stop, PreToolUse (Bash matcher), and Notification hook entries
   - Verify env section includes: ENABLE_LSP_TOOL, NODE_OPTIONS, CHOKIDAR_USEPOLLING, WATCHPACK_POLLING
   - Report if any are missing

5. **Run validation tests** using a temporary file in the current project:
   - Create a temp file `_setup_hooks_test.ts` with badly formatted TypeScript code
   - Test PostToolUse hook: `echo '{"tool_name":"Edit","tool_input":{"file_path":"_setup_hooks_test.ts"}}' | CLAUDE_PROJECT_DIR="$(pwd)" ~/.claude/hooks/post-edit-quality.sh`
   - Verify it exits 0 and the file was reformatted (if Biome/ESLint is available)
   - Test block-dangerous hook: `echo '{"tool_input":{"command":"ls -la"}}' | ~/.claude/hooks/block-dangerous.sh` — should exit 0
   - Test block-dangerous hook: `echo '{"tool_input":{"command":"rm -rf /"}}' | ~/.claude/hooks/block-dangerous.sh` — should exit 2
   - Clean up the temp file
   - Report timing for each test

6. **Print summary report** with status of each component:

   ```
   === Hook System Status ===
   Project: [directory name]
   Stack: [detected tools]

   Hook Scripts:
     post-edit-quality.sh  ✓ executable  [Xms]
     end-of-turn-typecheck.sh  ✓ executable
     block-dangerous.sh  ✓ executable  [Xms]

   Settings: ✓ configured

   Tools:
     jq: ✓ installed
     biome: ✓/✗ [version]
     tsgo: ✓/✗ [suggest install if missing]
     tsc: ✓/✗ [version]
   ```

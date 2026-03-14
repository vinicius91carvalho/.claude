#!/usr/bin/env bash
set -euo pipefail

# Check for jq — exit silently if missing (auto-formatting is non-critical)
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Read JSON input from stdin
INPUT=$(cat)

# Extract file_path from tool_input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Skip if file_path is empty or null
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip non-TS/JS files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

# Skip excluded directories (generated/vendor/build output)
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/coverage/*) exit 0 ;;
  */.turbo/*|*/__generated__/*|*/.generated/*|*/generated/*) exit 0 ;;
  */.cache/*|*/.output/*|*/.nuxt/*|*/.svelte-kit/*|*/.vercel/*) exit 0 ;;
  */.graphql/*|*/graphql/generated/*|*/.prisma/*|*/prisma/generated/*) exit 0 ;;
  */.storybook/static/*|*/out/*|*/.parcel-cache/*|*/.turbopack/*) exit 0 ;;
esac

# Resolve project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Make file_path absolute if relative
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$PROJECT_DIR/$FILE_PATH"
fi

# Check if file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Detect package manager (don't hardcode pnpm — respect the project's choice)
PKG_MGR="pnpm"
if [ -f "$PROJECT_DIR/bun.lockb" ] || [ -f "$PROJECT_DIR/bun.lock" ]; then
  PKG_MGR="bun"
elif [ -f "$PROJECT_DIR/yarn.lock" ]; then
  PKG_MGR="yarn"
elif [ -f "$PROJECT_DIR/package-lock.json" ]; then
  PKG_MGR="npx"
fi

# Detect Biome
if [ -f "$PROJECT_DIR/biome.json" ] || [ -f "$PROJECT_DIR/biome.jsonc" ]; then
  # Run Biome check with auto-fix
  OUTPUT=$(cd "$PROJECT_DIR" && $PKG_MGR biome check --write "$FILE_PATH" 2>&1) || {
    EXIT_CODE=$?
    # Send first 10 lines of error to stderr
    echo "$OUTPUT" | head -n 10 >&2
    exit 2
  }
  exit 0
fi

# Detect ESLint
HAS_ESLINT=false
for f in "$PROJECT_DIR"/eslint.config.* "$PROJECT_DIR"/.eslintrc.*; do
  if [ -f "$f" ]; then
    HAS_ESLINT=true
    break
  fi
done

if [ "$HAS_ESLINT" = true ]; then
  # Run ESLint with fix
  OUTPUT=$(cd "$PROJECT_DIR" && $PKG_MGR eslint --fix "$FILE_PATH" 2>&1) || {
    EXIT_CODE=$?
    echo "$OUTPUT" | head -n 10 >&2
    exit 2
  }
  # Run Prettier
  OUTPUT=$(cd "$PROJECT_DIR" && $PKG_MGR prettier --write "$FILE_PATH" 2>&1) || {
    EXIT_CODE=$?
    echo "$OUTPUT" | head -n 10 >&2
    exit 2
  }
  exit 0
fi

# No linter found — skip silently
exit 0

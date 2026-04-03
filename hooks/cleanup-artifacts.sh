#!/usr/bin/env bash
# Stop hook: Move stray artifact files from project root to .artifacts/
#
# Detects media and artifact files left in the project root by Playwright,
# scripts, or other tools, and organizes them into .artifacts/{category}/YYYY-MM-DD_HHmm/
#
# Artifact categories:
#   playwright/screenshots  — .png, .jpg, .jpeg, .gif, .webp
#   playwright/videos       — .mp4, .webm
#   execution               — .mov, .avi (other video)
#   reports                 — .pdf
#
# Safety rules:
#   - ONLY moves files matching explicit extension list — never source code
#   - ONLY examines project root (-maxdepth 1), never subdirectories
#   - NEVER deletes files — only moves them
#   - ALWAYS exits 0 — cleanup is best-effort, never blocks
#   - Skips if PROJECT_DIR is $HOME or /root
#   - Skips if not a git repository

# Cleanup hook crashes should never block — always exit 0
trap 'echo "HOOK WARNING: cleanup-artifacts.sh crashed at line $LINENO" >&2; exit 0' ERR

# Source shared logging utility
source ~/.claude/hooks/lib/hook-logger.sh 2>/dev/null || true

# ─── CONFIGURATION ─────────────────────────────────────────────────────

HOOK_NAME="cleanup-artifacts"

# Image extensions → playwright/screenshots category
IMAGE_EXTS="png jpg jpeg gif webp"

# Video extensions → playwright/videos or execution category
PLAYWRIGHT_VIDEO_EXTS="mp4 webm"
OTHER_VIDEO_EXTS="mov avi"

# Report extensions → reports category
REPORT_EXTS="pdf"

# All artifact extensions combined (for detection)
ALL_ARTIFACT_EXTS="$IMAGE_EXTS $PLAYWRIGHT_VIDEO_EXTS $OTHER_VIDEO_EXTS $REPORT_EXTS"

# ─── READ STDIN INPUT ──────────────────────────────────────────────────

# Read JSON input from stdin (Stop hook protocol)
INPUT=""
if [ -t 0 ]; then
  # No stdin (running manually) — use pwd
  INPUT="{}"
else
  INPUT=$(cat 2>/dev/null || echo "{}")
fi

# Check stop_hook_active — prevent infinite loop
STOP_HOOK_ACTIVE="false"
if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# ─── RESOLVE PROJECT DIRECTORY ─────────────────────────────────────────

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Skip if working in home directory (not a real project)
if [ "$PROJECT_DIR" = "$HOME" ] || [ "$PROJECT_DIR" = "/root" ]; then
  log_hook_event "$HOOK_NAME" "skipped" "project dir is HOME — not a real project"
  exit 0
fi

# Skip if project directory doesn't exist
if [ ! -d "$PROJECT_DIR" ]; then
  log_hook_event "$HOOK_NAME" "skipped" "project dir does not exist: $PROJECT_DIR"
  exit 0
fi

# Skip if not a git repository
if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  log_hook_event "$HOOK_NAME" "skipped" "not a git repo: $PROJECT_DIR"
  exit 0
fi

# ─── TIMESTAMP FOR DESTINATION ─────────────────────────────────────────

TIMESTAMP=$(date +%Y-%m-%d_%H%M)

# ─── HELPER FUNCTIONS ──────────────────────────────────────────────────

# Ensure .artifacts/ is in .gitignore
ensure_gitignore_entry() {
  local gitignore="$PROJECT_DIR/.gitignore"
  if [ ! -f "$gitignore" ]; then
    printf '.artifacts/\n' > "$gitignore" 2>/dev/null || true
    log_hook_event "$HOOK_NAME" "created-gitignore" "added .artifacts/ entry to new .gitignore"
  elif ! grep -qxF '.artifacts/' "$gitignore" 2>/dev/null; then
    printf '\n# Artifact storage (auto-organized by cleanup-artifacts hook)\n.artifacts/\n' >> "$gitignore" 2>/dev/null || true
    log_hook_event "$HOOK_NAME" "updated-gitignore" "added .artifacts/ entry to existing .gitignore"
  fi
}

# Move a single file to the destination directory
move_artifact() {
  local src="$1"
  local dest_dir="$2"
  local filename
  filename=$(basename "$src")

  # Create destination directory (including .artifacts/ parent on first use)
  if [ ! -d "$PROJECT_DIR/.artifacts" ]; then
    mkdir -p "$dest_dir" 2>/dev/null || return 0
    ensure_gitignore_entry
  else
    mkdir -p "$dest_dir" 2>/dev/null || return 0
  fi

  # Move the file (never overwrite silently — append timestamp if collision)
  local dest_path="$dest_dir/$filename"
  if [ -e "$dest_path" ]; then
    local base="${filename%.*}"
    local ext="${filename##*.}"
    dest_path="$dest_dir/${base}_$(date +%s).${ext}"
  fi

  if mv "$src" "$dest_path" 2>/dev/null; then
    log_hook_event "$HOOK_NAME" "moved" "$(basename "$src") -> ${dest_path#$PROJECT_DIR/}"
    echo "  moved: $filename -> ${dest_path#$PROJECT_DIR/}" >&2
  else
    log_hook_event "$HOOK_NAME" "move-failed" "could not move $filename"
  fi
}

# ─── SCAN PROJECT ROOT FOR ARTIFACTS ──────────────────────────────────

MOVED_COUNT=0

# Process each artifact extension
for ext in $ALL_ARTIFACT_EXTS; do
  # Use find with maxdepth 1 to only examine project root files
  while IFS= read -r -d '' filepath; do
    [ -f "$filepath" ] || continue

    filename=$(basename "$filepath")

    # Determine category based on extension
    file_ext="${filename##*.}"
    file_ext_lower=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')

    case "$file_ext_lower" in
      png|jpg|jpeg|gif|webp)
        dest="$PROJECT_DIR/.artifacts/playwright/screenshots/$TIMESTAMP"
        ;;
      mp4|webm)
        dest="$PROJECT_DIR/.artifacts/playwright/videos/$TIMESTAMP"
        ;;
      mov|avi)
        dest="$PROJECT_DIR/.artifacts/execution/$TIMESTAMP"
        ;;
      pdf)
        dest="$PROJECT_DIR/.artifacts/reports/$TIMESTAMP"
        ;;
      *)
        # Should not reach here given our extension list, but be safe
        log_hook_event "$HOOK_NAME" "skipped-unknown-ext" "$filename"
        continue
        ;;
    esac

    move_artifact "$filepath" "$dest"
    MOVED_COUNT=$((MOVED_COUNT + 1))

  done < <(find "$PROJECT_DIR" -maxdepth 1 -type f -iname "*.${ext}" -print0 2>/dev/null)
done

# ─── SUMMARY ───────────────────────────────────────────────────────────

if [ "$MOVED_COUNT" -gt 0 ]; then
  log_hook_event "$HOOK_NAME" "completed" "moved $MOVED_COUNT artifact(s) to .artifacts/"
else
  log_hook_event "$HOOK_NAME" "completed" "no artifacts found in root of $PROJECT_DIR"
fi

# Cleanup hook ALWAYS exits 0 — never blocks
exit 0

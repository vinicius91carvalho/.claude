#!/usr/bin/env bash
# validate-sprint-boundaries.sh — Deterministic sprint boundary validation (ADR-006)
# Run after PRD generation to verify sprint file boundaries and dependency graph.
# Usage: validate-sprint-boundaries.sh <prd-directory>
# Exit 0 = valid, Exit 1 = violations found

set -euo pipefail

PRD_DIR="${1:?Usage: validate-sprint-boundaries.sh <prd-directory>}"
PROGRESS_FILE="$PRD_DIR/progress.json"
SPRINTS_DIR="$PRD_DIR/sprints"
ERRORS=()

if [ ! -f "$PROGRESS_FILE" ]; then
  echo "ERROR: progress.json not found at $PROGRESS_FILE"
  exit 1
fi

if [ ! -d "$SPRINTS_DIR" ]; then
  echo "ERROR: sprints/ directory not found at $SPRINTS_DIR"
  exit 1
fi

# --- Check 1: No file appears in files_to_create/files_to_modify in two parallel sprints ---
# Parse batch assignments from progress.json
declare -A SPRINT_BATCH
declare -A SPRINT_CREATE
declare -A SPRINT_MODIFY

while IFS= read -r line; do
  id=$(echo "$line" | sed 's/:.*//')
  batch=$(echo "$line" | sed 's/.*://')
  SPRINT_BATCH["$id"]="$batch"
done < <(python3 -c "
import json, sys
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
for s in data.get('sprints', []):
    print(f\"{s['id']}:{s.get('batch', s['id'])}\")
" 2>/dev/null || echo "")

# Extract file boundaries from each sprint spec
for spec_file in "$SPRINTS_DIR"/*.md; do
  [ -f "$spec_file" ] || continue
  sprint_num=$(basename "$spec_file" | grep -oE '^[0-9]+' | sed 's/^0*//' || echo "0")
  [ -z "$sprint_num" ] && sprint_num="0"

  # Extract files_to_create and files_to_modify sections
  in_creates=false
  in_modifies=false

  while IFS= read -r line; do
    # Detect section headers
    if echo "$line" | grep -qiE '^\s*###?\s*Creates|files_to_create'; then
      in_creates=true; in_modifies=false; continue
    fi
    if echo "$line" | grep -qiE '^\s*###?\s*Modifies|files_to_modify'; then
      in_creates=false; in_modifies=true; continue
    fi
    if echo "$line" | grep -qiE '^\s*###?\s*(Read-Only|Shared|Consumed)'; then
      in_creates=false; in_modifies=false; continue
    fi
    # Blank line or new section ends current section
    if echo "$line" | grep -qE '^\s*##'; then
      in_creates=false; in_modifies=false; continue
    fi

    # Extract file paths from bullet points
    filepath=$(echo "$line" | grep -oE '`[^`]+`' | head -1 | tr -d '`' || true)
    [ -z "$filepath" ] && continue

    if $in_creates; then
      SPRINT_CREATE["${sprint_num}:${filepath}"]=1
    fi
    if $in_modifies; then
      SPRINT_MODIFY["${sprint_num}:${filepath}"]=1
    fi
  done < "$spec_file"
done

# Check for file conflicts between parallel sprints
declare -A FILE_OWNERS
for key in "${!SPRINT_CREATE[@]}" "${!SPRINT_MODIFY[@]}"; do
  sprint=$(echo "$key" | cut -d: -f1)
  filepath=$(echo "$key" | cut -d: -f2-)
  batch="${SPRINT_BATCH[$sprint]:-$sprint}"

  existing="${FILE_OWNERS[$filepath]:-}"
  if [ -n "$existing" ]; then
    existing_batch=$(echo "$existing" | cut -d: -f2)
    existing_sprint=$(echo "$existing" | cut -d: -f1)
    if [ "$existing_batch" = "$batch" ] && [ "$existing_sprint" != "$sprint" ]; then
      ERRORS+=("CONFLICT: File '$filepath' is writable in Sprint $existing_sprint and Sprint $sprint (both batch $batch — cannot be parallel)")
    fi
  fi
  FILE_OWNERS["$filepath"]="${sprint}:${batch}"
done

# --- Check 2: files_to_modify references exist or are created by earlier sprint ---
for key in "${!SPRINT_MODIFY[@]}"; do
  sprint=$(echo "$key" | cut -d: -f1)
  filepath=$(echo "$key" | cut -d: -f2-)

  # Check if file exists in working tree
  if [ -f "$filepath" ]; then
    continue
  fi

  # Check if an earlier sprint creates it
  found=false
  for ckey in "${!SPRINT_CREATE[@]}"; do
    csprint=$(echo "$ckey" | cut -d: -f1)
    cpath=$(echo "$ckey" | cut -d: -f2-)
    if [ "$cpath" = "$filepath" ] && [ "$csprint" -lt "$sprint" ]; then
      found=true
      break
    fi
  done

  if ! $found; then
    ERRORS+=("MISSING: Sprint $sprint modifies '$filepath' but it doesn't exist and no earlier sprint creates it")
  fi
done

# --- Check 3: Dependency graph has no cycles ---
python3 -c "
import json, sys

with open('$PROGRESS_FILE') as f:
    data = json.load(f)

deps = {}
for s in data.get('sprints', []):
    sid = s['id']
    deps[sid] = s.get('depends_on', [])

# Topological sort cycle detection
visited = set()
in_stack = set()
cycle_found = False

def dfs(node):
    global cycle_found
    if node in in_stack:
        cycle_found = True
        return
    if node in visited:
        return
    in_stack.add(node)
    for dep in deps.get(node, []):
        dfs(dep)
    in_stack.discard(node)
    visited.add(node)

for node in deps:
    dfs(node)

if cycle_found:
    print('CYCLE: Sprint dependency graph contains a cycle')
    sys.exit(0)
" 2>/dev/null | while IFS= read -r line; do
  ERRORS+=("$line")
done

# --- Check 4: INVARIANTS.md verify commands reference reachable files ---
INVARIANTS_FILE="$PRD_DIR/INVARIANTS.md"
if [ -f "$INVARIANTS_FILE" ]; then
  while IFS= read -r verify_cmd; do
    # Extract file paths from verify commands
    for ref_file in $(echo "$verify_cmd" | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z]+' || true); do
      # Skip common command names and patterns
      echo "$ref_file" | grep -qE '^\.' && continue
      echo "$ref_file" | grep -qE '^(grep|diff|test|echo|cat)' && continue
      # Check if referenced file exists or will be created
      if [ ! -f "$ref_file" ]; then
        created=false
        for ckey in "${!SPRINT_CREATE[@]}"; do
          cpath=$(echo "$ckey" | cut -d: -f2-)
          if [ "$cpath" = "$ref_file" ]; then
            created=true
            break
          fi
        done
        if ! $created; then
          ERRORS+=("INVARIANT: Verify command references '$ref_file' which doesn't exist and isn't created by any sprint")
        fi
      fi
    done
  done < <(grep -E '^\s*\*\*Verify:\*\*' "$INVARIANTS_FILE" | sed 's/.*\*\*Verify:\*\*\s*//' | tr -d '`' || true)
fi

# --- Report ---
if [ ${#ERRORS[@]} -eq 0 ]; then
  echo "Sprint boundary validation: PASS (all checks clear)"
  exit 0
else
  echo "Sprint boundary validation: FAIL (${#ERRORS[@]} issue(s))"
  echo ""
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  exit 1
fi

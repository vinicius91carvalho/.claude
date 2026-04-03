#!/usr/bin/env bash
# Shared caching utilities for Claude Code hooks.
#
# Source from any hook:
#   source ~/.claude/hooks/lib/project-cache.sh
#
# === FUNCTIONS ===
#
#   _ensure_cache_dir        — create cache dir if missing
#   content_hash FILE        — portable cksum of file content
#   project_hash DIR         — short hash of project directory path
#   cache_get KEY [TTL]      — read cached value if fresh (default TTL=300s)
#   cache_set KEY VALUE      — write value to cache
#   cache_invalidate PATTERN — remove cache files matching glob pattern
#
# Cache files live in: ~/.claude/hooks/logs/.cache/
# File naming convention: {purpose}_{project-hash}_{content-hash}

# ─── INTERNAL CONSTANTS ────────────────────────────────────────────────

_CACHE_DIR="${HOME}/.claude/hooks/logs/.cache"
_CACHE_DEFAULT_TTL=300  # 5 minutes

# ─── DIRECTORY INIT ────────────────────────────────────────────────────

# Ensures the cache directory exists. Safe to call multiple times.
_ensure_cache_dir() {
  if [ ! -d "$_CACHE_DIR" ]; then
    mkdir -p "$_CACHE_DIR" 2>/dev/null || true
  fi
}

# ─── HASH UTILITIES ────────────────────────────────────────────────────

# Compute a portable content hash of a file using cksum (POSIX, no external deps).
# Returns: "<checksum> <size>" string suitable for stable cache keys.
# Usage: HASH=$(content_hash "/path/to/file")
content_hash() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "missing_0"
    return
  fi
  # cksum outputs: checksum byte-count filename
  # We use the first two fields (checksum + size) for a stable key.
  cksum < "$file" 2>/dev/null | cut -d' ' -f1-2 | tr ' ' '_'
}

# Compute a short hash of a project directory path string.
# Uses cksum on the path string (no filesystem access needed).
# Usage: PHASH=$(project_hash "/path/to/project")
project_hash() {
  local dir="${1:-$(pwd)}"
  # Use cksum on the path string directly via echo
  printf '%s' "$dir" | cksum | cut -d' ' -f1
}

# ─── CACHE GET / SET / INVALIDATE ─────────────────────────────────────

# Read a cached value, checking TTL.
# Returns: cached value string on stdout, empty string if miss/expired
# Usage: VALUE=$(cache_get "my_key") or VALUE=$(cache_get "my_key" 600)
cache_get() {
  local key="$1"
  local ttl="${2:-$_CACHE_DEFAULT_TTL}"
  local cache_file="${_CACHE_DIR}/${key}"

  _ensure_cache_dir

  # Cache miss
  if [ ! -f "$cache_file" ]; then
    return 0
  fi

  # TTL check using stat for precision (avoids find -mmin integer division rounding)
  local now
  local file_mtime
  now=$(date +%s 2>/dev/null || echo 0)
  file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
  if [ $(( now - file_mtime )) -ge "$ttl" ]; then
    # Cache expired — remove silently and return empty
    rm -f "$cache_file" 2>/dev/null || true
    return 0
  fi

  # Cache hit — output value
  cat "$cache_file" 2>/dev/null || true
}

# Write a value to cache.
# Usage: cache_set "my_key" "my_value"
cache_set() {
  local key="$1"
  local value="$2"

  _ensure_cache_dir

  local cache_file="${_CACHE_DIR}/${key}"
  printf '%s' "$value" > "$cache_file" 2>/dev/null || true
}

# Invalidate (delete) cache files matching a key prefix or glob pattern.
# Usage: cache_invalidate "inv_abc123*"
cache_invalidate() {
  local pattern="$1"
  _ensure_cache_dir

  # Use glob expansion; suppress errors if nothing matches
  rm -f "${_CACHE_DIR}"/${pattern} 2>/dev/null || true
}

# ─── MARKER UTILITIES ──────────────────────────────────────────────────

# Touch a marker file (create or update mtime). Used for "last successful X" tracking.
# Usage: marker_touch "typecheck_success_abc123"
marker_touch() {
  local name="$1"
  _ensure_cache_dir
  touch "${_CACHE_DIR}/${name}" 2>/dev/null || true
}

# Check if a marker file exists and is newer than a given reference file.
# Returns: 0 if marker exists and is newer, 1 otherwise
# Usage: marker_is_fresh "typecheck_success_abc123" "/path/to/reference"
marker_is_fresh() {
  local name="$1"
  local reference="${2:-}"
  local marker="${_CACHE_DIR}/${name}"

  [ -f "$marker" ] || return 1

  if [ -n "$reference" ]; then
    # marker must be newer than reference
    [ "$marker" -nt "$reference" ] || return 1
  fi

  return 0
}

# Get the path to a marker file (even if it doesn't exist yet).
# Usage: MARKER_PATH=$(marker_path "typecheck_success_abc123")
marker_path() {
  local name="$1"
  _ensure_cache_dir
  echo "${_CACHE_DIR}/${name}"
}

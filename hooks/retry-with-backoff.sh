#!/usr/bin/env bash
# Retry-with-backoff utility for proot-distro environment
# Source this file to get the retry function:
#   source ~/.claude/hooks/retry-with-backoff.sh
#   retry_with_backoff 3 2 gh api /repos/...

retry_with_backoff() {
  local max_retries="${1:-3}"
  local initial_delay="${2:-2}"
  shift 2
  local cmd=("$@")
  local attempt=0
  local delay="$initial_delay"

  while [ "$attempt" -lt "$max_retries" ]; do
    if "${cmd[@]}"; then
      return 0
    fi

    local exit_code=$?
    attempt=$((attempt + 1))

    if [ "$attempt" -lt "$max_retries" ]; then
      # Check if it's a rate limit error (HTTP 429 or common rate limit messages)
      echo "Attempt $attempt/$max_retries failed (exit $exit_code). Retrying in ${delay}s..." >&2
      sleep "$delay"
      delay=$((delay * 2))

      # Cap delay at 60 seconds
      if [ "$delay" -gt 60 ]; then
        delay=60
      fi
    fi
  done

  echo "All $max_retries attempts failed for: ${cmd[*]}" >&2
  return 1
}

# Specific wrapper for gh API calls with rate limit detection
gh_api_retry() {
  local max_retries="${1:-3}"
  shift
  local attempt=0
  local delay=5

  while [ "$attempt" -lt "$max_retries" ]; do
    local output
    local exit_code=0
    output=$(gh "$@" 2>&1) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
      echo "$output"
      return 0
    fi

    # Check for rate limit
    if echo "$output" | grep -qiE 'rate limit|API rate|403.*rate|429'; then
      attempt=$((attempt + 1))
      if [ "$attempt" -lt "$max_retries" ]; then
        echo "GitHub API rate limit hit. Waiting ${delay}s before retry $((attempt + 1))/$max_retries..." >&2
        sleep "$delay"
        delay=$((delay * 2))
        [ "$delay" -gt 120 ] && delay=120
        continue
      else
        # Rate limit on final attempt — explicit exit
        echo "Rate limit persists after $max_retries attempts for: gh $*" >&2
        return 1
      fi
    fi

    # Non-rate-limit error — don't retry
    echo "$output" >&2
    return "$exit_code"
  done

  # Unreachable (all paths return inside the loop), but safe fallback
  return 1
}

# SST state lock detection and cleanup
sst_check_lock() {
  local project_dir="${1:-.}"

  if [ ! -f "$project_dir/.sst/lock" ]; then
    return 0  # No lock
  fi

  # Try to read lock info
  local lock_info
  lock_info=$(cat "$project_dir/.sst/lock" 2>/dev/null || echo "unknown")

  echo "SST state lock detected: $lock_info" >&2
  echo "If no deploy is currently running, remove with: rm $project_dir/.sst/lock" >&2
  return 1
}

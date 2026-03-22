#!/usr/bin/env bash
# Tests for auto-version bump logic
set -euo pipefail

PASS=0
FAIL=0

assert_bump() {
  local expected="$1"
  shift
  local commits="$*"

  local bump="none"
  while IFS= read -r msg; do
    [ -z "$msg" ] && continue
    if echo "$msg" | grep -qE '^[a-z]+(\(.+\))?!:' || echo "$msg" | grep -qi 'BREAKING CHANGE'; then
      bump="major"; break
    fi
    if echo "$msg" | grep -qE '^feat(\(.+\))?:'; then
      [ "$bump" != "major" ] && bump="minor"
    fi
    if echo "$msg" | grep -qE '^(fix|perf)(\(.+\))?:'; then
      [ "$bump" = "none" ] && bump="patch"
    fi
  done <<< "$commits"

  if [ "$bump" = "$expected" ]; then
    echo "  PASS: expected=$expected got=$bump"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: expected=$expected got=$bump | commits: $commits"
    FAIL=$((FAIL + 1))
  fi
}

assert_version_bump() {
  local current="$1"
  local bump_type="$2"
  local expected="$3"

  IFS='.' read -r MAJOR MINOR PATCH <<< "$current"
  case "$bump_type" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac
  local result="${MAJOR}.${MINOR}.${PATCH}"

  if [ "$result" = "$expected" ]; then
    echo "  PASS: $current + $bump_type = $result"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $current + $bump_type → expected $expected, got $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Commit Message Parsing ==="
assert_bump "minor" "feat: add new feature"
assert_bump "minor" "feat(auth): add login"
assert_bump "patch" "fix: correct bug"
assert_bump "patch" "fix(ui): button alignment"
assert_bump "patch" "perf: optimize query"
assert_bump "patch" "perf(db): index lookup"
assert_bump "major" "feat!: breaking change"
assert_bump "major" "fix(auth)!: breaking fix"
assert_bump "none" "docs: update readme"
assert_bump "none" "test: add tests"
assert_bump "none" "chore: cleanup"
assert_bump "none" "refactor: restructure"
assert_bump "none" "chore(deps): update deps"

echo ""
echo "=== Priority Resolution ==="
assert_bump "major" "$(printf 'feat: something\nfix!: breaking')"
assert_bump "major" "$(printf 'docs: readme\nfeat!: breaking feature')"
assert_bump "minor" "$(printf 'fix: bug\nfeat: feature')"
assert_bump "minor" "$(printf 'docs: readme\nfeat: feature\nchore: cleanup')"
assert_bump "patch" "$(printf 'docs: readme\nfix: bug')"
assert_bump "patch" "$(printf 'chore: cleanup\nperf: speed up')"
assert_bump "none" "$(printf 'docs: readme\nchore: cleanup\ntest: add test\nrefactor: clean')"

echo ""
echo "=== Version Arithmetic ==="
assert_version_bump "1.0.0" "patch" "1.0.1"
assert_version_bump "1.0.0" "minor" "1.1.0"
assert_version_bump "1.0.0" "major" "2.0.0"
assert_version_bump "1.2.3" "patch" "1.2.4"
assert_version_bump "1.2.3" "minor" "1.3.0"
assert_version_bump "1.2.3" "major" "2.0.0"
assert_version_bump "0.9.9" "patch" "0.9.10"
assert_version_bump "0.9.9" "minor" "0.10.0"
assert_version_bump "0.9.9" "major" "1.0.0"
assert_version_bump "10.20.30" "patch" "10.20.31"

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1

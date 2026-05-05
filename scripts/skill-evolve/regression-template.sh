#!/usr/bin/env bash
# regression-template.sh — Regression test scaffold for skill-evolve proposals.
#
# Placeholders (substituted by propose-edits.py at generation time):
#   __CLUSTER_SLUG__          — kebab-case cluster identifier
#   __CATEGORY__              — friction taxonomy category
#   __EVIDENCE_FINGERPRINT__  — fingerprint string from the clustered events
#   __GATE_COMMAND__          — shell command that should exit 0 if the fix holds
#
# Style mirrors ~/.claude/hooks/tests/test-*.sh so run-all.sh's glob picks
# it up after the user manually copies it to ~/.claude/hooks/tests/.
#
# Usage: bash test-skill-evolve-__CLUSTER_SLUG__.sh
# Exit: 0 = all assertions passed, 1 = at least one assertion failed.

set -uo pipefail

# ── Optional: source stop-guard if available ─────────────────────────────────
if [ -f "$HOME/.claude/hooks/lib/stop-guard.sh" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.claude/hooks/lib/stop-guard.sh" 2>/dev/null || true
fi

# ── Counters ──────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

# ── Inline assert helpers (no external lib dependency) ───────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  OK  %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$label: expected='$expected' got='$actual'")
    printf "  FAIL %s (expected='%s' got='%s')\n" "$label" "$expected" "$actual"
  fi
}

assert_exit_0() {
  local label="$1"
  shift
  local exit_code=0
  "$@" >/dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  OK  %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$label: command exited $exit_code")
    printf "  FAIL %s (exit %d)\n" "$label" "$exit_code"
  fi
}

assert_file_exists() {
  local path="$1" label="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    printf "  OK  %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$label: file not found: $path")
    printf "  FAIL %s (file not found: %s)\n" "$label" "$path"
  fi
}

# ── Test metadata ─────────────────────────────────────────────────────────────
CLUSTER_SLUG="__CLUSTER_SLUG__"
CATEGORY="__CATEGORY__"
EVIDENCE_FINGERPRINT="__EVIDENCE_FINGERPRINT__"
GATE_COMMAND="__GATE_COMMAND__"

printf "Running regression test: skill-evolve/%s [%s]\n" \
  "$CLUSTER_SLUG" "$CATEGORY"

# ── T1: Gate command exits 0 (the proposed fix is in effect) ─────────────────
if [ -n "$GATE_COMMAND" ] && [ "$GATE_COMMAND" != "__GATE_COMMAND__" ]; then
  gate_exit=0
  eval "$GATE_COMMAND" >/dev/null 2>&1 || gate_exit=$?
  if [ "$gate_exit" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  OK  gate command exits 0\n"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("gate command failed: $GATE_COMMAND (exit $gate_exit)")
    printf "  FAIL gate command failed (exit %d): %s\n" "$gate_exit" "$GATE_COMMAND"
  fi
else
  printf "  --  gate command not set (placeholder not substituted) — skipping\n"
fi

# ── T2: Category is a known taxonomy member ───────────────────────────────────
known_categories="workaround retry refusal env-incompat missing-method"
if echo "$known_categories" | grep -qw "$CATEGORY"; then
  PASS=$((PASS + 1))
  printf "  OK  category '%s' is in taxonomy\n" "$CATEGORY"
else
  FAIL=$((FAIL + 1))
  ERRORS+=("unknown category: $CATEGORY")
  printf "  FAIL unknown category: %s\n" "$CATEGORY"
fi

# ── T3: Fingerprint is non-empty ──────────────────────────────────────────────
if [ -n "$EVIDENCE_FINGERPRINT" ] && [ "$EVIDENCE_FINGERPRINT" != "__EVIDENCE_FINGERPRINT__" ]; then
  PASS=$((PASS + 1))
  printf "  OK  evidence fingerprint is set\n"
else
  FAIL=$((FAIL + 1))
  ERRORS+=("evidence fingerprint is empty or not substituted")
  printf "  FAIL evidence fingerprint is empty or not substituted\n"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\nResults: %d passed" "$PASS"
if [ "$FAIL" -gt 0 ]; then
  printf ", %d failed" "$FAIL"
  printf "\nFailed:\n"
  for e in "${ERRORS[@]}"; do
    printf "  - %s\n" "$e"
  done
  exit 1
fi
printf "\n"
exit 0

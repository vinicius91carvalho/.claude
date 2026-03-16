#!/usr/bin/env bash
# validate-i18n-keys.sh — Validates that all i18n t() keys exist in all locale JSON files.
# Generic for any next-intl project. Detects i18n automatically; exits 0 if no i18n found.
#
# Usage: validate-i18n-keys.sh [project-root]
# Exit codes: 0 = pass (or no i18n), 1 = missing keys found

set -euo pipefail

PROJECT_ROOT="${1:-.}"

# Detect if project uses i18n (next-intl, react-intl, i18next, etc.)
if ! grep -rq '"next-intl"\|"react-intl"\|"i18next"\|"react-i18next"' \
    $(find "$PROJECT_ROOT" -name 'package.json' -not -path '*/node_modules/*' -maxdepth 4) 2>/dev/null; then
  exit 0  # Not an i18n project
fi

# Find all i18n JSON files grouped by locale
I18N_FILES=$(find "$PROJECT_ROOT" -path '*/i18n/*.json' -not -path '*/node_modules/*' 2>/dev/null | sort)
if [ -z "$I18N_FILES" ]; then
  exit 0  # No i18n files found
fi

# Get unique locales and contexts
LOCALES=$(echo "$I18N_FILES" | xargs -I{} basename {} .json | sort -u)
LOCALE_COUNT=$(echo "$LOCALES" | wc -l)

if [ "$LOCALE_COUNT" -lt 2 ]; then
  exit 0  # Single locale, nothing to cross-validate
fi

# Pick the first locale as reference
REF_LOCALE=$(echo "$LOCALES" | head -1)

ERRORS=0
MISSING_KEYS=""

# For each context directory that has i18n files
for dir in $(echo "$I18N_FILES" | xargs -I{} dirname {} | sort -u); do
  ref_file="$dir/$REF_LOCALE.json"
  [ -f "$ref_file" ] || continue

  # Get all keys from reference locale (flattened dot notation)
  ref_keys=$(python3 -c "
import json, sys

def flatten(obj, prefix=''):
    keys = []
    for k, v in obj.items():
        key = f'{prefix}.{k}' if prefix else k
        if isinstance(v, dict):
            keys.extend(flatten(v, key))
        else:
            keys.append(key)
    return keys

with open('$ref_file') as f:
    data = json.load(f)
for k in sorted(flatten(data)):
    print(k)
" 2>/dev/null)

  # Check each other locale has the same keys
  for locale in $LOCALES; do
    [ "$locale" = "$REF_LOCALE" ] && continue
    locale_file="$dir/$locale.json"
    [ -f "$locale_file" ] || continue

    locale_keys=$(python3 -c "
import json, sys

def flatten(obj, prefix=''):
    keys = []
    for k, v in obj.items():
        key = f'{prefix}.{k}' if prefix else k
        if isinstance(v, dict):
            keys.extend(flatten(v, key))
        else:
            keys.append(key)
    return keys

with open('$locale_file') as f:
    data = json.load(f)
for k in sorted(flatten(data)):
    print(k)
" 2>/dev/null)

    # Find keys in ref but not in locale
    missing=$(comm -23 <(echo "$ref_keys" | sort) <(echo "$locale_keys" | sort))
    if [ -n "$missing" ]; then
      context=$(basename "$(dirname "$dir")")
      count=$(echo "$missing" | wc -l)
      MISSING_KEYS="${MISSING_KEYS}${context}/${locale}.json: ${count} keys missing from ${REF_LOCALE}.json\n"
      ERRORS=$((ERRORS + count))
    fi

    # Find keys in locale but not in ref (extra keys)
    extra=$(comm -13 <(echo "$ref_keys" | sort) <(echo "$locale_keys" | sort))
    if [ -n "$extra" ]; then
      context=$(basename "$(dirname "$dir")")
      count=$(echo "$extra" | wc -l)
      MISSING_KEYS="${MISSING_KEYS}${context}/${REF_LOCALE}.json: ${count} keys missing from ${locale}.json\n"
      ERRORS=$((ERRORS + count))
    fi
  done
done

if [ "$ERRORS" -gt 0 ]; then
  echo "i18n validation: $ERRORS missing keys across locales"
  echo -e "$MISSING_KEYS"
  exit 1
fi

exit 0

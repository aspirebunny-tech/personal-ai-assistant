#!/bin/sh
set -eu

echo "[pre-commit] secret scan running..."

PATTERN='(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|OPENAI_API_KEY[[:space:]]*=[[:space:]]*sk-|OPENROUTER_API_KEY[[:space:]]*=[[:space:]]*sk-|Bearer[[:space:]]+[A-Za-z0-9._-]{20,})'

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMRT || true)
if [ -z "${STAGED_FILES}" ]; then
  exit 0
fi

# shellcheck disable=SC2086
if git diff --cached -U0 -- $STAGED_FILES | grep -E -n "$PATTERN" >/tmp/pai_secret_scan_hits.txt; then
  echo ""
  echo "ERROR: Potential secret detected in staged changes."
  echo "Matches:"
  cat /tmp/pai_secret_scan_hits.txt
  echo ""
  echo "Fix required: remove/mask secret before commit."
  exit 1
fi

rm -f /tmp/pai_secret_scan_hits.txt
echo "[pre-commit] secret scan passed."
exit 0

#!/usr/bin/env bash
# cotype-replace-section.sh — atomically replace ONE `### <ID> — …` section
# of an mr-review TODO without touching anyone else's sections.
#
# Usage:
#   cotype-replace-section.sh <ID> <TODO-path>
#
# Reads the new section body from stdin. The body must start with the
# `### <ID> — <claim>` heading and end before the next `### ` or `## ` line.
# Handles ConflictPending retries internally (up to 5 attempts).
#
# Why this script exists:
# `cotype save` is full-file CAS, not section-level. Naïvely piping a single
# section to it deletes the rest of the file. Every agent in step 4 of the
# mr-review skill needs the same boilerplate (open → awk-rewrite → save → retry
# on conflict). Encoding it here keeps agent prompts short and eliminates the
# whole class of "agent forgot to pipe back the full file" bugs.
#
# Exit codes:
#   0  section replaced successfully
#   1  usage error
#   2  cotype open/save failed after retries
#   3  section <ID> not found in the base file
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: cotype-replace-section.sh <ID> <TODO-path>" >&2
  echo "  body is read from stdin" >&2
  exit 1
fi

ID=$1
TODO=$2
BODY=$(cat)

if [ -z "$BODY" ]; then
  echo "error: section body on stdin is empty" >&2
  exit 1
fi

# Verify the body's first non-blank line is the right heading.
FIRST_LINE=$(printf '%s\n' "$BODY" | grep -m1 -v '^[[:space:]]*$' || true)
case "$FIRST_LINE" in
  "### $ID "*) ;;
  *)
    echo "error: stdin body must start with '### $ID — …', got: $FIRST_LINE" >&2
    exit 1
    ;;
esac

MAX_ATTEMPTS=5
attempt=0
while [ $attempt -lt $MAX_ATTEMPTS ]; do
  attempt=$((attempt + 1))
  META=$(cotype open "$TODO" --json) || {
    echo "error: cotype open failed (attempt $attempt)" >&2
    [ $attempt -lt $MAX_ATTEMPTS ] && sleep 1 && continue
    exit 2
  }
  BASE_SHA=$(printf '%s' "$META" | jq -r .base_sha)
  BASE_PATH=$(printf '%s' "$META" | jq -r .base_path)

  if ! grep -q "^### $ID " "$BASE_PATH"; then
    echo "error: section '### $ID' not found in $BASE_PATH" >&2
    exit 3
  fi

  # Strip any trailing blank lines from the user-supplied body so we control
  # the spacing before the next heading deterministically. Shell command
  # substitution strips trailing newlines, so we re-add exactly one blank
  # line via `printf` after the body inside the awk template.
  BODY_NORM=$(printf '%s\n' "$BODY" | awk '
    { lines[NR] = $0 }
    END {
      n = NR
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ')

  # Rewrite: replace lines from `### <ID>` up to (but not including) the next
  # `### ` or `## ` heading. Print the normalized body followed by exactly
  # one blank line before yielding to the next section.
  TMP=$(mktemp)
  awk -v id="$ID" -v body="$BODY_NORM" '
    BEGIN { in_section = 0; printed = 0 }
    /^### / {
      if ($0 ~ "^### " id " ") {
        if (!printed) { print body; print ""; printed = 1 }
        in_section = 1
        next
      } else {
        in_section = 0
      }
    }
    /^## / { in_section = 0 }
    !in_section { print }
  ' "$BASE_PATH" > "$TMP"

  # Sanity check: new file should not be wildly shorter than the base.
  BASE_LINES=$(wc -l < "$BASE_PATH")
  NEW_LINES=$(wc -l < "$TMP")
  MIN_LINES=$((BASE_LINES / 2))
  if [ "$NEW_LINES" -lt "$MIN_LINES" ]; then
    echo "error: new file ($NEW_LINES lines) is less than half the base ($BASE_LINES lines); refusing to save" >&2
    rm -f "$TMP"
    exit 2
  fi

  SAVE_OUTPUT=$(cotype save "$TODO" --base-sha "$BASE_SHA" --actor "$ID" --json < "$TMP" 2>&1) || {
    if printf '%s' "$SAVE_OUTPUT" | grep -q 'ConflictPending\|conflict'; then
      rm -f "$TMP"
      [ $attempt -lt $MAX_ATTEMPTS ] && continue
    fi
    echo "error: cotype save failed: $SAVE_OUTPUT" >&2
    rm -f "$TMP"
    exit 2
  }
  rm -f "$TMP"
  echo "section $ID replaced (attempt $attempt, base=$BASE_LINES new=$NEW_LINES lines)"
  exit 0
done

echo "error: exhausted $MAX_ATTEMPTS attempts" >&2
exit 2

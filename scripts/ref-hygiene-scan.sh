#!/usr/bin/env bash
# Emit branch artifacts for the ref-hygiene-checker subagent.
#
# One entry point so a single Bash allowlist rule
# (`Bash(./.claude/scripts/ref-hygiene-scan.sh *)`) covers every
# subcommand and avoids a permission prompt per call.
#
# Usage:
#   ref-hygiene-scan.sh scan [<base>]   # regex-anchored candidates with file:line citations
#   ref-hygiene-scan.sh diff [<base>]   # full branch diff vs base, filtered to source files
#   ref-hygiene-scan.sh log  [<base>]   # subject + body of every commit between base and HEAD
#
# `scan` is the deterministic pre-pass: emits one record per added
# comment line (file:line tracked across hunks) and per commit
# subject/body line, filtered by the anchor set covering rules 1-3 of
# the agent definition. Rule 4 (narrative phrasing) is LLM-judged — the
# agent reads `diff` and `log` for that pass.
#
# Defaults:
#   <base> = origin/master

set -euo pipefail

cmd="${1:-}"
base="${2:-origin/master}"

# Anchored regex set covering rules 1-3 from .claude/agents/ref-hygiene-checker.md.
anchors='(\b[A-Z]{2,}-[0-9]{2,}\b|(Closes|Fixes|Refs|Contributes):|[A-Za-z0-9_/.-]+-rfc[-.]|[A-Za-z0-9_/.-]+-spec\.md|[A-Za-z0-9_/.-]+-plan\.md|RFC[ ]§?[0-9]|![0-9]{3,}|#[0-9]{3,}|\bMR-[0-9]+\b)'

scan_diff() {
    git diff "$base...HEAD" -- '*.ml' '*.mli' '*.rs' '*.sh' \
        | awk '
            /^\+\+\+ \/dev\/null/ { file = ""; in_hunk = 0; next }
            /^\+\+\+ b\// { file = substr($0, 7); in_hunk = 0; next }
            /^\+\+\+/ { next }
            /^---/ { next }
            /^@@/ {
                if (match($0, /\+[0-9]+/)) {
                    line = substr($0, RSTART+1, RLENGTH-1) + 0
                }
                in_hunk = 1
                next
            }
            in_hunk && file != "" {
                c = substr($0, 1, 1)
                rest = substr($0, 2)
                if (c == "+") { print file ":" line ":" rest; line++ }
                else if (c == " ") { line++ }
            }
        ' \
        | grep -E "$anchors" || true
}

scan_log() {
    git log "$base..HEAD" --format='%H%n%s%n%b%n--END--' \
        | awk '
            /^[0-9a-f]{40}$/ { sha = substr($0, 1, 12); kind = "subject"; next }
            /^--END--$/      { kind = "subject"; next }
            /^$/             { kind = "body"; next }
            sha != ""        { print sha ":" kind ":" $0 }
        ' \
        | grep -E "$anchors" || true
}

case "$cmd" in
    scan)
        echo "=== code-comment-refs ==="
        scan_diff
        echo
        echo "=== commit-refs ==="
        scan_log
        ;;
    diff)
        git diff "$base...HEAD" -- '*.ml' '*.mli' '*.rs' '*.sh'
        ;;
    log)
        git log "$base..HEAD" --format='%n=== %H ===%n%s%n%n%b%n'
        ;;
    *)
        echo "usage: $(basename "$0") {scan|diff|log} [<base>]" >&2
        exit 2
        ;;
esac

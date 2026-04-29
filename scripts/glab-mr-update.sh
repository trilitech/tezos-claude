#!/usr/bin/env bash
# Update a GitLab MR description from a body file.
#
# Centralizes the `-R tezos/tezos` and `--description "$(cat ...)"`
# convention so MR description updates can be covered by a single
# Bash allowlist rule. Pair with a personal Write(/tmp/**) rule
# (settings.local.json) for a zero-prompt update flow.
#
# Usage: .claude/scripts/glab-mr-update.sh <mr-id> <body-file> [<repo>]
#
# Defaults:
#   <repo> = tezos/tezos

set -euo pipefail

usage() {
    echo "usage: $(basename "$0") <mr-id> <body-file> [<repo>]" >&2
    exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage

mr_id="$1"
body_file="$2"
repo="${3:-tezos/tezos}"

[[ -r "$body_file" ]] || { echo "body file not readable: $body_file" >&2; exit 2; }

glab mr update "$mr_id" --description "$(cat "$body_file")" -R "$repo"

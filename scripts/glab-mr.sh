#!/usr/bin/env bash
# Create or update a GitLab MR — single entry point.
#
# Centralizes the `-R tezos/tezos`, `--head tezos/tezos`, and body-file
# conventions so MR create/update operations can be covered by one Bash
# allowlist rule (`Bash(./.claude/scripts/glab-mr.sh:*)`). Pair with the
# scoped body-file rule (`Write(/tmp/claude-mr-body-*.md)`) for a
# zero-prompt flow without blanket /tmp write access.
#
# Usage:
#   .claude/scripts/glab-mr.sh create <body-file> [--title <title>] [--base <base>] [--repo <repo>] [--reviewer <a,b>] [--assignee <a,b>]
#   .claude/scripts/glab-mr.sh update <mr-id> <body-file> [--repo <repo>] [--reviewer <a,b>] [--assignee <a,b>]
#
# Defaults:
#   <base>  = master
#   <repo>  = tezos/tezos
#   <title> = latest commit subject (only for `create`)
#
# `--reviewer` / `--assignee` take comma-separated GitLab usernames and are
# passed straight through to `glab`. Omit them to leave the fields untouched.
#
# `create` pushes the current branch to `origin` before opening the MR.

set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") create <body-file> [--title <title>] [--base <base>] [--repo <repo>] [--reviewer <a,b>] [--assignee <a,b>]
       $(basename "$0") update <mr-id> <body-file> [--repo <repo>] [--reviewer <a,b>] [--assignee <a,b>]
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
    create)
        [[ $# -ge 1 ]] || usage
        body_file="$1"; shift
        title=""
        base="master"
        repo="tezos/tezos"
        reviewer=""
        assignee=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --title)    title="$2";    shift 2 ;;
                --base)     base="$2";     shift 2 ;;
                --repo)     repo="$2";     shift 2 ;;
                --reviewer) reviewer="$2"; shift 2 ;;
                --assignee) assignee="$2"; shift 2 ;;
                *) echo "unknown arg: $1" >&2; usage ;;
            esac
        done
        [[ -r "$body_file" ]] || { echo "body file not readable: $body_file" >&2; exit 2; }
        branch="$(git branch --show-current)"
        [[ -n "$branch" ]] || { echo "not on a branch" >&2; exit 2; }
        if [[ -z "$title" ]]; then
            title="$(git log -1 --pretty=format:%s)"
        fi
        git push -u origin "$branch"
        create_args=(
            --head tezos/tezos
            --target-branch "$base"
            --title "$title"
            --description-file "$body_file"
            -R "$repo"
        )
        [[ -n "$reviewer" ]] && create_args+=(--reviewer "$reviewer")
        [[ -n "$assignee" ]] && create_args+=(--assignee "$assignee")
        glab mr create "${create_args[@]}"
        ;;
    update)
        [[ $# -ge 2 ]] || usage
        mr_id="$1"; shift
        body_file="$1"; shift
        repo="tezos/tezos"
        reviewer=""
        assignee=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --repo)     repo="$2";     shift 2 ;;
                --reviewer) reviewer="$2"; shift 2 ;;
                --assignee) assignee="$2"; shift 2 ;;
                *) echo "unknown arg: $1" >&2; usage ;;
            esac
        done
        [[ -r "$body_file" ]] || { echo "body file not readable: $body_file" >&2; exit 2; }
        update_args=(--description "$(cat "$body_file")" -R "$repo")
        [[ -n "$reviewer" ]] && update_args+=(--reviewer "$reviewer")
        [[ -n "$assignee" ]] && update_args+=(--assignee "$assignee")
        glab mr update "$mr_id" "${update_args[@]}"
        ;;
    *)
        usage
        ;;
esac

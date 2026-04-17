# Team conventions

Team-level conventions for working on the Octez (Tezos) repository
with Claude Code. Read it on demand when creating commits, opening
MRs, or naming branches.

## Git commits

Use `--author="<CLAUDE_COMMIT_AUTHOR>"` (set in `CLAUDE.local.md` at
the Octez checkout root). If not set, fall back to the committer
identity (do not pass `--author`).

## Project management

Issues and cycles are tracked in Linear. The Linear plugin is enabled
in `.claude/settings.json`; ask Claude to install it if it is not
active.

## Merge requests

Every MR must link a Linear issue with estimation, cycle, team, and
owner set. Default cycle is current; default owner is the committer.
Ask the engineer for the estimation, team, and project before creating
the MR. When an MR already exists, verify the linked issue reflects
the latest branch state before pushing.

The description must follow `.claude/mr-template.md` — read it when
creating or updating an MR, not before. Replace `<LINEAR_ISSUE_URL>`
with the real URL, and pick `close` or `ref` on that line:

- `close` — the MR fully resolves the issue; merging it should
  transition the issue to Done.
- `ref` — the MR only contributes to the issue (partial work,
  follow-up, related change). The issue stays open after merge.

**Ask the engineer for help to tick the checklist if needed.**

## Repository hosting

Upstream lives on GitLab. Use the `glab` CLI; ask the engineer to
install it if missing.

## Branch naming

`<CLAUDE_BRANCH_PREFIX>@<description>` — prefix set in
`CLAUDE.local.md` at the Octez checkout root (e.g.
`alice@fix-ic-reset`).

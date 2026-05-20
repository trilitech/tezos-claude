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
creating or updating an MR, not before. The Linear issue line starts
with a Linear integration keyword (`Closes:`, `Fixes:`, or
`Contributes:`) followed by an inline markdown link with the Linear
ID as label — e.g. `Closes: [L2-1324](https://linear.app/tezos/issue/L2-1324/...)`.
Linear's GitLab integration parses these keywords and updates the
issue automatically on MR merge:

- `Closes:` / `Fixes:` — the MR fully resolves the issue; merging
  transitions the issue to Done.
- `Contributes:` — the MR contributes to the issue (partial work,
  follow-up, related change). The issue stays open after merge.

**Ask the engineer for help to tick the checklist if needed.**

### Description conventions

Layout (metadata block, sections, blank-line spacing) is defined by
`.claude/mr-template.md`. Content rules:

- **`# What` and `# Why` stay high-level.** Reviewers should be able
  to scan them; don't restate the diff.
- **`# Manually testing the MR`** — do **not** include checks CI
  already enforces (`make fmt`, `make check-linting`,
  `make -f etherlink.mk check`, etc.). Do **not** state test counts
  ("N tests pass") — they go stale on rebase.

## Changelog

Every MR must add an entry to the relevant `CHANGES*` file (find the
one closest to the component being modified). Do not open the MR
without a changelog entry — this matches the mandatory checkbox in
`.claude/mr-template.md`.

Each entry must:

- **Link to the MR.** Include the `!<id>` reference on the
  line so readers can jump from the changelog back to the discussion
  and diff.
- **Be descriptive and flag breaking changes explicitly.** Describe
  what changed from the user's perspective, not which file moved. If
  the change is breaking (removed/renamed CLI flag, RPC schema bump,
  on-disk format change, default behavior change), call it out in the
  line itself — consumers skim release notes and rely on the wording
  to notice.
- **Record cross-component version constraints at the release/version
  header, not only in a bullet.** When a release introduces an
  incompatibility with another component (e.g. an Etherlink kernel
  that requires EVM node ≥ X.Y, a node release that drops support for
  an older baker), state the required peer version in the version
  section so operators and releasers can gate upgrades on it without
  reading every bullet.

## Repository hosting

Upstream lives on GitLab. Use the `glab` CLI; ask the engineer to
install it if missing.

### `glab` usage

- **Creating or updating an MR.** Write the description to a body
  file at `/tmp/claude-mr-body-<id>.md` (the prefix matches the
  scoped allowlist rule) and run `.claude/scripts/glab-mr.sh`:
    - Create: `glab-mr.sh create <body-file> [--title T] [--base B] [--repo R]` — pushes the current branch to `origin`, then opens the MR with `--head tezos/tezos`.
    - Update: `glab-mr.sh update <mr-id> <body-file> [--repo R]` — replaces the description.

  The script wraps the `-R tezos/tezos` / `--head tezos/tezos` / body-file conventions. The team-shared `.claude/settings.json` allowlist covers both the script invocation and the body-file write under `/tmp/claude-mr-body-*` for all contributors. Do not use inline heredocs: `<<'EOF'` mangles bodies that contain backticks (the fix is *not* to escape them — single quotes preserve `\`` literally, leaving backslashes in the rendered description).
- **Reading JSON output.** Use `jq -r '.field'` on
  `glab ... --output json`. Do not invoke `python3 -c` for ad-hoc
  parsing.
- **Cross-fork pitfall.** Always pass `--head tezos/tezos` to
  `glab mr create`. Without it, glab auto-detects the fork
  relationship between `origin` (tezos/tezos) and `nl`
  (nomadic-labs/tezos) and resolves the source project as the fork
  even when the branch was pushed to `origin`, so the MR ends up
  pointing at a non-existent branch on `nomadic-labs/tezos`.

## Branch naming

`<CLAUDE_BRANCH_PREFIX>@<description>` — prefix set in
`CLAUDE.local.md` at the Octez checkout root (e.g.
`alice@fix-ic-reset`).

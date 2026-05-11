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

## Changelog

Every MR must add an entry to the relevant `CHANGES*` file (find the
one closest to the component being modified). Do not open the MR
without a changelog entry — this matches the mandatory checkbox in
`.claude/mr-template.md`.

Each entry must:

- **Link to the MR.** Include the MR URL or `!<id>` reference on the
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

- **Updating an MR description.** Write the description to a file
  (e.g. `/tmp/mr-body.md`) and run
  `.claude/scripts/glab-mr-update.sh <mr-id> /tmp/mr-body.md` — the
  script wraps the `-R tezos/tezos` and `--description "$(cat ...)"`
  convention. To skip the permission prompt, allowlist
  `Bash(./.claude/scripts/glab-mr-update.sh:*)` in your personal
  `settings.local.json` (it is intentionally not in the team-shared
  `settings.json` because the script silently posts to GitLab). Do
  not use inline heredocs: `<<'EOF'` mangles bodies that contain
  backticks (the fix is *not* to escape them — single quotes
  preserve `\`` literally, leaving backslashes in the rendered
  description).
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

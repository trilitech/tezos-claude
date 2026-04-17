# When to read each file in this stash

Lazy-loading index. Import this file from your project's root `CLAUDE.md`
or `CLAUDE.local.md` (e.g. `@.claude/loading.md`) so Claude sees the rules
below every turn. The rules then tell Claude which other files to pull in
on demand — keeping the per-turn context small.

## `.claude/conventions.md`

**When to read:** before creating a commit, opening or updating an MR, or
naming a new branch.

**Why:** defines the team's `--author` flag, MR checklist entries, Linear
linkage, GitLab `glab` usage, and branch-prefix rule.

## `.claude/mr-template.md`

**When to read:** when you are about to draft or update an MR description.

**Why:** the required template — structure (`What / Why / How / Manually
testing the MR / Checklist`) and the `<LINEAR_ISSUE_URL>` placeholder that
must be substituted.

## `.claude/CLAUDE.local.md.example`

**When to read:** during onboarding — only if the project-root
`CLAUDE.local.md` is missing and the user needs to create it.

**Why:** template for personal overrides (`CLAUDE_COMMIT_AUTHOR`,
`CLAUDE_BRANCH_PREFIX`).

## `.claude/settings.json`

**When to read:** never on demand — Claude Code auto-loads this file at
session start for plugins and permissions.

## `.claude/README.md`

**When to read:** if a teammate asks what this `.claude/` stash is, how to
install it, or how its loading model works. Not needed for day-to-day
tasks.

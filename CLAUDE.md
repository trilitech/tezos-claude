# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when
working with code in this repository.

## What this repository is

This is **not** application code. It is the `.claude/` stash — a
drop-in Claude Code configuration overlay for the Octez (Tezos)
monorepo, published at `github.com:trilitech/tezos-claude`. Contents
are Markdown conventions, MR templates, and `settings.json`
(plugins/permissions). No compilation, no tests, no lint.

Read `README.md` for the end-user installation story and `loading.md`
for the lazy-loading index.

## Two contexts you may be invoked in

1. **Editing the stash itself** (cwd is `.claude/`, as now). Git
   operations act on this overlay repo. The outer Octez checkout is
   untouched.
2. **Working inside an Octez checkout that has this stash installed**
   (cwd is the Octez root). `.claude/` is just config; the `@`-imports
   in the root `CLAUDE.md`/`CLAUDE.local.md` pull `loading.md` into
   context, and `loading.md` tells you which other files to read on
   demand.

When you are editing files here, you are in context 1. Changes are
published to teammates through their overlay pull, not through the
Octez repo.

## Git layout quirk

`.claude/.git` is a gitfile pointing to `.git-.claude/` at the Octez
root (this is how `git-overlay` keeps two histories side by side in
one working tree). `git status` run inside `.claude/` sees only this
overlay; run one level up, it sees only Octez. Do not try to "fix"
this — it is the design.

Remote: `github.com:trilitech/tezos-claude`. Default branch is
`master`; MRs target `main` on the overlay.

## When editing files here

- `loading.md` is the index Claude reads every turn in context 2. Keep
  its rules short and specific — each file's **When to read** line
  gates whether Claude pulls it in. Verbose entries cost context on
  every turn.
- `conventions.md`, `mr-template.md` are pulled on demand. They can be
  longer, but keep them focused on their trigger (commit/MR/branch
  work).
- `CLAUDE.local.md.example` is a template copied **one level up** into
  the Octez checkout root (not into `.claude/`). If you change the
  variables it documents (`CLAUDE_COMMIT_AUTHOR`,
  `CLAUDE_BRANCH_PREFIX`), update every file that references them.
- `settings.json` is team-shared (plugins, permissions everyone should
  have). `settings.local.json` is per-user and gitignored — never
  commit it, never read it as if it were authoritative.

## Commit/MR conventions for this repo

The conventions in `conventions.md` (Linear issue, MR template,
`glab`, branch prefix, `--author`) apply to Octez work. This overlay
repo is not tied to Linear and uses plain GitHub PRs. Do not force
Octez conventions onto commits here unless the user asks for them.

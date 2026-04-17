# A Claude Code stash for Octez work

This repository is **one possible** `.claude/` setup for working on
the Octez (Tezos) codebase with Claude Code. It is a collection of
helpers and conventions that one teammate has found useful and is
sharing — not a required configuration, not a team mandate, and not a
standard.

It is not a tool or a library. It is a drop-in `.claude/` folder.

## Who might want it

If you use Claude Code on Octez and you are curious what someone
else's setup looks like, take a look. Clone the whole thing, copy the
MR template, or just read it for ideas — whichever is useful to you.
If nothing here fits your workflow, that is fine too.

## Installing it in your checkout

### 1. Install the overlay

From an Octez checkout:

```
git-overlay --init .claude git@github.com:trilitech/tezos-claude.git
```

This creates `.claude/` in your working tree, tracked by a separate
git history. Your Octez repo is unaffected — `git status` stays clean.

### 2. Set your personal overrides

Copy the template **up one level**, into your Octez checkout root:

```
cp .claude/CLAUDE.local.md.example ./CLAUDE.local.md
```

So the final layout looks like:

```
tezos/                    ← your Octez checkout
├── CLAUDE.local.md       ← your personal overrides (auto-loaded by Claude Code)
└── .claude/
    ├── CLAUDE.local.md.example
    └── …
```

Claude Code auto-loads `CLAUDE.local.md` from the project root, not
from inside `.claude/` — that is why it goes one level up.

Edit the copy to fill in your commit-author identity and GitLab branch
prefix. The Octez repo's `.gitignore` already excludes root-level
`CLAUDE.local.md`, so it stays local to your checkout.

## How Claude Code loads it

Claude Code auto-discovers these at session start:

- `.claude/settings.json` — plugins, permissions
- `CLAUDE.local.md` at the project root (see step 2 above) — per-user
  overrides

The other files (`conventions.md`, `mr-template.md`, etc.) are **not**
auto-loaded. `.claude/loading.md` is a small index that tells Claude
which of them to read, and when.

To wire it in, add this line — **at column 1, not inside a code
fence** — to your project's root `CLAUDE.md` (or `CLAUDE.local.md`):

    @.claude/loading.md

Claude Code only processes `@`-imports when they appear as a plain
line; code-fenced text is treated as literal content and ignored.

That keeps the per-turn context tiny — Claude only loads the larger
files (`mr-template.md`, `conventions.md`) on demand, when the task
actually needs them.

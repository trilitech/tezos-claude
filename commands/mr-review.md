Review MR $ARGUMENTS against its spec and existing discussion.

## Step 1 — gather what you can automatically

Use `glab mr view $ARGUMENTS --comments` to fetch the MR: title, description,
author, linked issue references, and any existing review comments or discussions.

Use `glab mr diff $ARGUMENTS` to fetch the diff.

Extract any issue/Linear links from the MR description (look for `close`/`ref`
lines, `#NNN` issue refs, or Linear URLs like `linear.app/...`). If a GitLab
issue is linked, fetch it with `glab issue view NNN`. If a Linear issue is
linked, use the Linear MCP tool to read it.

Also read the commit messages from `glab mr view $ARGUMENTS` or via `git log`
if the branch is checked out.

## Step 2 — ask for more context

Report in one short paragraph what you found (MR title, linked issues/specs
you located, any gaps). Then ask:

> Anything else to add before I review? Paste links, spec excerpts, background,
> or related issues.

Wait for the user's reply before proceeding to Step 3.

## Step 3 — walk through the MR

Explain the MR as if to a reviewer seeing it for the first time:

- What problem it solves and why (drawing from the issue/spec)
- How it is structured: key commits, major files changed, overall approach
- Any non-obvious design choices or tradeoffs visible in the diff

Be thorough here — this is the main value. Cover the diff in enough detail
that the reviewer understands what every significant change does.

## Step 4 — review

After the walk-through, switch to critique mode. Check:

- **Spec coherence**: does the implementation match the spec/issue? Flag any
  missing cases, wrong behaviour, or deviations.
- **MR description coherence**: does the What/Why/How match what the diff
  actually does?
- **Commit messages**: do they accurately describe their commit's scope?
- **Existing comments**: are there open threads the author has not addressed?
- **Retro-compatibility**: unless the spec or MR explicitly states a breaking
  change is intentional, flag any behaviour that existing callers or users
  would observe differently (changed RPC responses, altered storage layout,
  different error codes, modified default values, etc.).
- **Code quality**: bugs, unsafe patterns, missing error handling at system
  boundaries, OCaml/Rust anti-patterns from the coding guidelines.

Follow the review format from AGENTS.md:

```
## Review

### BLOCKER 🔴
- <issue> (file:line)
- **Fix:** <concrete suggestion>

### Issues
- <issue> (file:line)

### Questions
- <clarification needed>
```

Do not praise working code. Do not report that tests pass. Be concise in the
review section (the walk-through is where detail lives).

Output everything as text only — do not post anything to GitLab.

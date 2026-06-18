---
name: mr-review
description: Review a GitLab MR with parallel investigation agents writing into a shared TODO via cotype, then run an interactive approve-post-next loop with the user. Takes a full MR URL — project and ID are both parsed from it.
---

# mr-review

Multi-agent MR review for GitLab. Parallel investigation populates a shared
TODO; the main agent then walks the user through approve / edit / skip for each
finding and posts comments to GitLab.

## Usage

`/mr-review <MR-URL>`

Example: `/mr-review https://gitlab.com/tezos/tezos/-/merge_requests/21875`

The URL is the single source of truth: host, project (`tezos/tezos`), and MR ID
(`21875`) are all extracted from it. Reject any input that doesn't match
`https?://<host>/<project-path>/-/merge_requests/<id>` and ask for a full URL.

## Workspace layout

The skill stores per-MR state in a workspace directory:

```
~/.local/share/mr-review/<host>/<project>/<mr_id>/
├── meta.json    # project, mr_id, host, diff_refs (base/start/head SHAs)
├── diff.patch
└── todo.md
```

Per-host/project nesting prevents collisions across MR IDs from different
projects. Everything that downstream tooling needs (SHAs, project slug) lives
in `meta.json`, so the rest of the procedure passes one path around instead of
five CLI args.

## Procedure

### 1. Setup

Parse the URL: `^https?://([^/]+)/(.+?)/-/merge_requests/(\d+)/?$` → `HOST`,
`PROJECT`, `MR_ID`. Compute:

- `WS=~/.local/share/mr-review/<HOST>/<PROJECT>/<MR_ID>`
- `TODO=$WS/todo.md`
- `SKILL_DIR=.claude/skills/mr-review` (relative to the repo root this skill is installed in)

Fetch and stash:

```bash
mkdir -p "$WS"
glab mr view "$MR_ID" --repo "$PROJECT" -F json > "$WS/meta.json.raw"
# Normalize meta.json to the contract the skill expects:
jq --arg project "$PROJECT" --arg host "$HOST" --argjson id "$MR_ID" '{
  project: $project, host: $host, mr_id: $id,
  title, source_branch, target_branch, author: .author.username,
  diff_refs
}' < "$WS/meta.json.raw" > "$WS/meta.json"
glab mr diff "$MR_ID" --repo "$PROJECT" > "$WS/diff.patch"
```

Read `$WS/meta.json` once and keep `diff_refs` at hand. **You will not need to
pass SHAs around again** — `post-comment.py` reads them from `meta.json`.

### 2. Initial review pass

Read `$WS/diff.patch`. Write `$TODO` with the Write tool using this exact
structure (the schema below is enforced — downstream parsing depends on it):

```markdown
# MR !<id> Review TODO

**Project:** <project>
**Title:** <title>
**Head SHA:** <head_sha>
**Base SHA:** <base_sha>
**Start SHA:** <start_sha>

## Workflow rules

- Re-read this file to find the next unchecked finding. Never rely on memory.
- During the parallel investigation phase (step 4), agents write via cotype.
- During the interactive loop (step 7), use plain Edit — there is exactly
  one author, cotype's CAS adds overhead with no concurrency to protect.
- Never post a comment without explicit per-item user approval.

## Comment-style rules

1. Lead with the suggestion, not the analysis.
2. ≤ 4 sentences plus an optional fenced code block.
3. Cite specific `file:line` references; no general phrasing.
4. Inline (anchored to a diff line) > top-level. Anchorable lines are
   added (`+`) lines and in-hunk context (` `); removed lines are not.
5. **Never reference internal finding IDs** (B1, I3, N2, …) in the
   posted body — they exist only in this workspace. To cross-reference
   a previously-posted comment, use a `{{ref:<ID>}}` token (see step 7)
   that `post-comment.py` substitutes with the real GitLab note URL.
   Otherwise rephrase so the comment stands alone.
6. Match local conventions: nits posted as `nit: …`, questions as
   `q: …`, blockers/issues without a prefix.

---

## Blockers
<!-- B1, B2, … sections go here -->

## Issues
<!-- I1, I2, … sections go here -->

## Nits
<!-- N1, N2, … sections go here -->

## Questions
<!-- Q1, Q2, … sections go here -->
```

Then, for each finding, append a section under its severity bucket with this
**exact** schema (one field per line, no variants — agents and parsers depend
on it):

```markdown
### <ID> — <one-line claim>

**Status:** unchecked
**Verdict:** TBD
**Anchor:** TBD
**Why:** TBD

**Draft:**
> TBD
```

Stable IDs: `B1, B2, …` (blockers), `I1, I2, …` (issues), `N1, …` (nits),
`Q1, …` (questions). Use `###` for finding headings (severity buckets are `##`).

### 3. Initialize cotype

```bash
cotype init "$TODO"
```

### 4. Parallel investigation

For each finding section, spawn one Explore agent in parallel — emit all
`Agent` tool calls in **one message**.

The agent prompt is short because the cotype boilerplate is hidden behind
`$SKILL_DIR/bin/cotype-replace-section.sh`. Each agent's prompt:

```
You are investigating one finding in an MR review TODO. Other findings
are being investigated in parallel by sibling agents — your only safe
write path is the helper script described below.

TODO file: <TODO-path>
Workspace: <WS-path>           # contains meta.json with diff_refs
Your section heading: `### <ID> — <claim>`
MR head SHA: <head_sha>        # for `git show <head>:<path>` reads
Helper: <SKILL_DIR>/bin/cotype-replace-section.sh

Task:
1. Read your section in the TODO.
2. Investigate the codebase. Determine the verdict:
   - REAL — the issue is reachable; suggest a fix.
   - UNREACHABLE — defensive code or unreachable in practice.
   - STRUCTURAL — answered by an existing invariant.
   - NEEDS-JUDGMENT — requires a human call.
3. Replace YOUR section by piping the new body to the helper:

   cat <<'EOF' | <SKILL_DIR>/bin/cotype-replace-section.sh <ID> <TODO-path>
   ### <ID> — <claim>

   **Status:** unchecked
   **Verdict:** <REAL|UNREACHABLE|STRUCTURAL|NEEDS-JUDGMENT>
   **Anchor:** <path>:<line>   # or N/A
   **Why:** <one sentence — the load-bearing fact>

   **Draft:**
   > <≤4-sentence comment, or N/A if verdict ≠ REAL>
   EOF

   The helper opens the TODO via cotype, rewrites only your section,
   retries on ConflictPending up to 5 times, and refuses to save if the
   resulting file is wildly shorter than the base.

CRITICAL — about the **Draft** field:
- It is a stand-alone comment to the MR author. They have no idea what
  "B1" or "I3" means — never reference internal IDs in the Draft. If
  your finding depends on another finding's outcome, write a
  self-contained sentence; the orchestrator will add a `{{ref:<other-ID>}}`
  cross-reference at post time if needed.
- Lead with the suggestion. ≤ 4 sentences. Cite file:line, not vague locations.
- For Nits, prefix the Draft with `nit:`. For Questions, prefix with `q:`.

DO NOT:
- Use Write/Edit on the TODO directly (bypasses CAS).
- Invoke `cotype save` yourself (the helper handles retries).
- Pipe only your section to `cotype save` (deletes other sections).

If the helper exits non-zero, do NOT silently report success — return
"section <ID> NOT updated: <reason>" so the orchestrator can re-spawn or
patch by hand.

Return on success: "section <ID> updated to verdict <V>". Under 100 words.
```

Spawn all in one message; wait for all to complete.

### 5. Post-fan-out validation

This step exists because:
- Agents occasionally fail silently (claim read-only mode, hit a tool error,
  forget to call cotype). Without this check, gaps reach the user.
- A linter or external hook may have rewritten the file's structure between
  saves; severity buckets and ordering must be re-established before step 7.

Do, in this order:

1. Re-read `$TODO`.
2. **Gap detection.** For each finding ID, check the section is present and
   that every field has a non-TBD value. Build a list of IDs with `**Verdict:**
   TBD` or missing entirely. If any:
   - Re-spawn investigation agents for those IDs (same prompt as step 4).
   - After they return, re-run this validation. Repeat at most once before
     surfacing the residual list to the user.
3. **Schema enforcement.** Each finding section must match the schema in
   step 4 exactly (one field per line, no `→` separators, no merged
   Status/Verdict lines). If a linter mangled them, rewrite the offending
   sections to the canonical form. Use Edit — the parallel phase is over.
4. **Structure restoration.** Ensure the four severity buckets exist (`##
   Blockers`, `## Issues`, `## Nits`, `## Questions`) in that order and that
   each finding section lives under the correct bucket based on its ID
   prefix. Move sections that drifted.

After this step, the TODO has a known shape and you can walk it
deterministically.

### 6. Batch skip pass (upfront)

Before walking the user through individual findings, present in one message
every finding with verdict `STRUCTURAL` or `UNREACHABLE`:

> The following findings are auto-skip candidates (verdict explains why the
> claim doesn't hold):
>
> - **N2** STRUCTURAL: ...
> - **Q2** STRUCTURAL: ...
>
> Skip all? (or name any to revisit)

For each ID the user does NOT call out, set `**Status:** skipped (verdict:
<V>)` via Edit. For called-out IDs, they re-enter the regular loop with
`unchecked` status.

This batch step exists because verdicts are known the moment fan-out finishes
— there's no reason to drip-feed obvious skips one by one.

### 7. Interactive loop

Walk the remaining `unchecked` findings in canonical order: Blockers → Issues
→ Nits → Questions, ascending within each bucket.

Re-read the TODO each iteration. Present the next unchecked finding:

> Next: **<ID>** (<severity>)
> Verdict: <V>. Why: <W>.
> Anchor: <path>:<line>
> Draft:
> > <D>

Ask: **post / edit / skip?**

- `post`: invoke
  ```
  $SKILL_DIR/post-comment.py "$WS" "<path>" "<line>" < draft.txt
  ```

  Before posting, scrub the draft of internal finding IDs — if you mention
  another finding's outcome (e.g., "see B2"), translate it to a
  `{{ref:B2}}` token and pass `--ref B2=<url>` where `<url>` is read from
  `$WS/posted.json` (which `post-comment.py` populates after each post).
  The script substitutes the token at post time.

  If the anchor is rejected (`post-comment.py` exits with code 1), the
  script prints the nearest postable lines — pick one of those, or anchor
  at the same line a related comment used. Do not silently re-try with a
  random nearby line; verify the new anchor makes semantic sense first.

  Optional dry-run before committing:
  `post-comment.py --dry-run "$WS" "<path>" "<line>" < draft.txt`
  prints the resolved payload without sending.

  On success, capture the discussion ID from stdout and set
  `**Status:** posted: <discussion-id>` via Edit.
- `edit`: take the user's reframing, redraft, re-present (no Status change).
- `skip`: set `**Status:** skipped (<rationale>)` via Edit.

**Use Edit, not cotype, for these status mutations** — there's one author
(you), no race to protect, and the CAS round-trip is pure overhead.

Continue until no `unchecked` findings remain.

### 8. Summary

When the loop exits, print a one-message summary. Each posted finding gets
a row with: topic (no internal ID), severity, and the note URL from
`$WS/posted.json`. Skipped findings get the rationale only — internal IDs
stay in the workspace TODO, never in the user-facing summary. Close with
the MR URL.

## Notes

- `post-comment.py` sends the position as a JSON body (not glab's `-f
  position[…]=`, which silently drops nested fields and produces a top-level
  note instead of a diff-anchored one). It reads project, MR ID, and SHAs from
  `<workspace>/meta.json`, validates that the anchor line is in a hunk for
  the target file, substitutes `{{ref:<ID>}}` tokens via `--ref`, and caches
  posted note URLs in `<workspace>/posted.json` keyed by a slug of the body.
- `bin/cotype-replace-section.sh` is the only safe way for agents to write
  to the TODO during fan-out. Agents call it with stdin = new section body;
  it handles the cotype open/awk/save retry loop and refuses to save if the
  result is implausibly short.
- Cotype is only used in step 4 (concurrent agent writes). Everywhere else,
  use Edit.
- For agents reading code at the MR's head revision: `git show <head_sha>:<path>`
  works if the commit is fetched locally. If not, fetch the MR head files via
  `glab api 'projects/<project-encoded>/repository/files/<path-encoded>/raw?ref=<sha>'`
  into a scratch directory and point the agents at it.
- An external linter may rewrite the file between cotype saves. The skill
  doesn't try to defeat it — step 5 restores canonical shape afterwards.

## Files

```
.claude/skills/mr-review/
├── SKILL.md                            # this file
├── post-comment.py                     # inline-comment poster with anchor validation + refs
└── bin/
    └── cotype-replace-section.sh       # section-scoped TODO write helper for fan-out agents
```

---
name: mr-status
description: Produce a status report on the user's open GitLab MRs on tezos/tezos — bucketed by Needs work / In review / Approved / On merge train / Draft, with rebase state, review status, and next-move advice. Invoke when the user asks for an MR status update, "where are my MRs", "what's blocked on me", or a dashboard / Firefox view of the same.
---

# MR status update

Produce a status report on the user's open MRs.

## Default scope

All open MRs (ready + draft) authored by the assistant on
`tezos/tezos`. Narrow the scope only if the engineer asks (one branch,
one Linear project, one stack).

## Default output channel

Markdown table in the chat. Build an HTML page **only** when the
engineer asks for a webpage / dashboard / Firefox view. See
[`HTML output`](#html-output) below.

## Data sources

All queries via `glab api`. The assistant's GitLab user id is
`33185120` (`SylvainAssistant`); the `tezos/tezos` project id is
`3836952`. For a different author, resolve via
`/users?username=<name>`.

1. **List MRs**:

    ```bash
    glab api "/merge_requests?author_id=33185120&scope=all&state=opened&order_by=updated_at&per_page=50"
    ```

2. **Per-MR detail** — needed for every MR in the list:

    ```bash
    glab api "/projects/3836952/merge_requests/<iid>?include_diverged_commits_count=true"
    ```

3. **Approvals** — needed for every ready (non-draft) MR to detect
   the Approved bucket. Use `/approval_state` and inspect the
   `Default` rule (Octez Merge Team requirement); `approvals_left = 0`
   means 2+ approvals received:

    ```bash
    glab api "/projects/3836952/merge_requests/<iid>/approval_state"
    ```

   The shorter `/approvals` endpoint also works (`approved_by | length
   >= 2` is the same condition), but the rule-aware endpoint is the
   authoritative check.

4. **Discussions** — only when `user_notes_count > 0` *or*
   `blocking_discussions_resolved` is false:

    ```bash
    glab api "/projects/3836952/merge_requests/<iid>/discussions?per_page=50"
    ```

5. **Merge train** — one call, fetches every car across all target
   branches in one go. Use to detect which MRs are already in the
   queue (state `fresh` / `stale` / `idle` / `merging`; `merged` cars
   are landed and can be ignored):

    ```bash
    glab api "/projects/3836952/merge_trains?per_page=100" \
      | jq '[.[] | select(.status != "merged")
                | {iid: .merge_request.iid, status, created_at, target_branch}]'
    ```

   Join the result against the MR list by `iid`. The car's
   `created_at` is when the train picked the MR up — that is the
   timestamp to render ("on train · Nh ago"), not the MR's own
   `updated_at`.

6. **Review queue** (MRs assigned to you that you did *not* author) —
   the inverse of the author query. Powers the *Assigned to you*
   section:

    ```bash
    glab api "/merge_requests?reviewer_id=33185120&scope=all&state=opened&order_by=updated_at&per_page=50"
    glab api "/merge_requests?assignee_id=33185120&scope=all&state=opened&order_by=updated_at&per_page=50"
    ```

   Union the two lists by `iid`, then **drop any where `author.id` is
   `33185120`** (those already show up in your own buckets above).

Batch calls in a single `Bash` invocation with a `for` loop and `jq`
projection to avoid per-MR round-trip latency.

## Fields and interpretation

| Field | Meaning | Mapping |
|-------|---------|---------|
| `draft` | Draft flag | true → "Open, draft" section |
| `has_conflicts` | Merge conflicts | true → rebase blocked, red badge |
| `diverged_commits_count` | Commits target gained since base | `>200` amber, `>1000` red ("very stale") |
| `target_branch` | What it merges into | `master` = standalone; `sribaroud@*` = stacked |
| `blocking_discussions_resolved` | All blocking review threads resolved | false → at least one reviewer thread awaits author reply (or vice versa); check discussions to be sure |
| `user_notes_count` | Total notes | inspect discussions when non-zero |
| `assignees[].username` | Octez convention: who owes the next move | only `sribaroud` → you; reviewers only → others; empty → unassigned |
| `detailed_merge_status` | GitLab mergeability code | `not_approved`, `discussions_not_resolved`, `checking`, `draft_status`, `mergeable` |
| `head_pipeline.status` | CI state | `manual` = start job not clicked; `running` / `failed` / `success` / `none` |
| merge train car `status` | Train state (joined by iid) | `fresh` / `idle` = queued, `stale` = needs rebase, `merging` = active, `merged` = landed (drop) |
| merge train car `created_at` | When the train picked the MR up | Render as "on train · Nh ago" — terminal state, ball is on the train |

## Five-section taxonomy

Classify each open MR into exactly one of five sections. Apply the
checks **in order**; the first one that matches wins.

1. **On merge train** — the MR appears in `/merge_trains` with a
   non-`merged` car status (`fresh` / `idle` / `stale` / `merging`).
   Terminal state: the queue owns the MR now, so residual
   `assignees`, open suggestion threads, or even `has_conflicts` are
   noise. The only follow-up is to babysit if the car turns `stale`
   or never lands.
2. **Draft** — `draft = true`.
3. **Needs work** — any of:
   - `has_conflicts = true`, **or**
   - author (`sribaroud`) appears in `assignees`, **or**
   - no `assignees` at all on a ready MR (author still needs to add
     reviewers), **or**
   - a reviewer-initiated discussion thread is `resolvable = true`,
     `resolved = false`, and the **last note in that thread is from a
     reviewer** (author hasn't replied yet).
4. **Approved** — ready MR that has reached the Octez Merge Team
   threshold of **2 approvals on the `Default` rule** (i.e.
   `approval_state.rules[name=Default].approvals_left = 0`), with no
   conflicts and no unaddressed reviewer threads, **and not yet on
   the train**. Ball is on the engineer to push it onto the train.
5. **In review** — everything else: ready MR with reviewer assignees
   only, no conflicts, every reviewer thread either resolved or
   already replied to by the author, but **fewer than 2 approvals**
   on the `Default` rule. Ball is on the reviewer to mark resolved /
   give approval.

### Approval caveat: rebases reset approvals

Octez configures GitLab to reset approvals on every push. So an
approval visible in the discussions log (e.g. "@phink approved this
merge request") may already be invalid if subsequent commits or a
rebase landed after it. Trust **only** the live
`/approval_state` query, never the discussions log.

### The "review not addressed" rule

GitLab's `blocking_discussions_resolved = false` flag fires whenever
there are unresolved threads — even after the author replied. So the
flag alone does **not** mean "Needs work"; only the *last-note-is-
reviewer* condition does. Otherwise the ball is on the reviewer to
resolve the thread, which is **In review**.

Resolve this by inspecting `/discussions` and checking each
`resolvable && !resolved` thread's last note's author. If every such
thread's last note is the author's, the MR is **In review**; if any
has a reviewer as the last note, **Needs work**.

## Assigned to you (review queue)

Separate from the five author-buckets above: a final **Assigned to
you** section listing MRs where you are a `reviewer`/`assignee` but
someone else is the `author` (data source 6). These are review
requests on your plate, not your own work. Columns: MR, Title, Author,
Rebase, Review, Next move — the "Next move" is typically *review and
resolve*, or *unassign yourself* if it's not actually yours. Render it
last, after Draft.

## Markdown output shape

Five tables, in pipeline-order **Needs work**, **In review**,
**Approved**, **On merge train**, **Draft** — actionable bucket first,
then progressively closer to merged, with Draft (WIP) last. *On merge
train* sits between *Approved* and *Draft* because the work is past
the engineer's hands but not yet landed.

An empty section is still rendered with its header and a single-row
"—" placeholder, so the engineer sees at a glance that nothing is in
that bucket today.
Each table uses the columns:

| Column | Content |
|--------|---------|
| MR | `!NNNN` linked to the GitLab MR |
| Title | Short title; use `` `code` `` for identifiers |
| Rebase | Badges: conflict status + `-N` behind target |
| Review | (In review / Needs work only) thread state, approvals |
| Train | (On merge train only) car status + "added Nh ago" |
| Next move | One-line action the engineer should take, or what's pending |

For chat output, render the same three tables in Markdown without the
HTML badges (use prose like &ldquo;clean&rdquo; / &ldquo;conflicts, -N&rdquo;).

## HTML output

Use [`template.html`](template.html) (sibling to this `SKILL.md`) as
the canonical layout. The template is **self-contained** (inline CSS,
no network deps, GitHub-dark palette) and shows one example row per
table.

To regenerate:

1. Write the filled page to the **stable path**
   `/tmp/mr-status-latest.html`. `/tmp` is tmpfs — survives until
   reboot, no persistent-disk cost. A fixed name (not a dated one) is
   what lets a single Firefox tab and the auto-refresh stay pointed at
   the freshest snapshot, and lets the recurring cron job overwrite in
   place. When the engineer explicitly wants a dated archival copy
   (e.g. to share), also `cp` it to `/tmp/mr-status-YYYY-MM-DD.html`.
2. Open with `xdg-open /tmp/mr-status-latest.html` in the background
   (`&` or `run_in_background`) **only if no tab is already open** —
   `xdg-open` launches the user's default browser, so don't hardcode
   `firefox` or any specific one. The template's
   `<meta http-equiv="refresh" content="900">` repaints an existing
   tab on its own, so a regen does not need a new browser call.
   Opening unconditionally spawns duplicate tabs on every cron fire.
3. Mention the file path so the engineer can re-open or share it.
4. Replace `master @ <SHA>` in the header with the current
   `git rev-parse --short tezos/master` value.

The `<meta>` refresh interval (900s) is tuned to the recommended
15-minute cron cadence; keep the two in sync if either changes.

## Stale snapshot caveat

Master and the engineer's stacked branches may have moved since the
last fetch. When the engineer asks for a status update, run
`git fetch tezos` first if more than a few minutes have passed since
the last fetch — `diverged_commits_count` is computed server-side, so
the GitLab numbers are fresh, but the local view used for any
follow-up rebase advice is not.

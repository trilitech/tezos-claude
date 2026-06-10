---
name: mr-from-spec
description: Ship a single MR end-to-end from a spec / RFC / Linear ticket / plan — whether the first MR or continuing work where previous MRs are in flight. Scope and plan the MR, create a branch (from origin/master, or from a previous MR's branch when stacking), spawn the implementer subagent, spawn the prep-reviewer subagent, iterate on BLOCKERs, draft the MR per `.claude/mr-template.md`, and — on user confirmation — dispatch `mr-handler` to push and open it. Phrases: "ship the first MR from this RFC", "ship the next MR from this RFC", "continue work on this RFC, previous MRs are <list>", "start work on this RFC", "draft an MR from this spec".
---

# MR from spec

## Procedure

1. **Read the source.** If only a URL is given, fetch and read it. Summarize the scope for the user.

2. **Plan the MR.** Scope to one atomic unit — a single reviewable change. If the source describes multiple MRs, plan only the first (or the one named). The plan should specify:
   - The atomic boundary (what's in, what's out)
   - The files / modules expected to change
   - **Commit breakdown** — an ordered list of small self-contained commits within the MR. Each commit compiles and passes the tests it cares about, does one thing (no mixing refactor + feature), and has a `<Component>: <subject>` heading. The implementer uses this list as the commit boundaries.
   - The verification the implementer will run
   - Test plan (what to add, what to update)

   Surface the plan before proceeding.

3. **Create the branch.** Default base: `origin/master`. For stacked work building on a previous MR, branch from that MR's branch instead. If the base is ambiguous (e.g. previous MR not yet merged but rebased), confirm with the user. Branch name per `.claude/conventions.md`.

4. **Spawn the implementer.** `Agent({ subagent_type: "implementer", prompt: "<plan + spec link>" })`. Wait for the commit set. If it returns "stopped early", surface the reason and decide whether to continue, fix the plan, or abandon.

5. **Spawn the prep-reviewer.** `Agent({ subagent_type: "prep-reviewer", prompt: "Review commits on <branch> against this plan: <plan>. Spec: <link>." })`. Wait for the review.

6. **Iterate when warranted.** After each review, decide whether the findings warrant another implementer pass — this is a judgment call, not a mechanical rule.

   - Use judgment: BLOCKERs (correctness, security, regression, spec violation) usually warrant iteration; Issues (style, naming, minor architecture) usually do not. Consider impact, scope, and whether the implementer can plausibly fix the finding without introducing new problems.
   - **Questions** → answer inline if the answer is obvious from spec / conventions / memory. If not, **stop and ask the user.** Resolve before continuing.
   - If you iterate: dispatch implementer with the review as context, re-run prep-reviewer.
   - If you don't iterate: note remaining findings in the MR description for human reviewers.

   Between iterations, surface a one-line status: "Iteration N: <summary>. Dispatching implementer." Keep the user in the loop.

   **Cap: after 2 iterations**, halt and surface remaining findings to the user instead of looping further.

7. **Check reference hygiene.** Once the prep-reviewer loop has converged, spawn `Agent({ subagent_type: "ref-hygiene-checker", prompt: "Check branch <branch> against base <base>." })`. The agent scans **code comments and commit messages** for text that points outside the current code — off-site refs (RFC/spec docs, Linear tickets outside TODO/FIXME, MR/PR numbers) or past-state phrasing — and **applies rewrites as `fixup!` commits** for the user to inspect.

   Surface the list of fixup commits the agent created (use `git log --oneline <base>..HEAD` to show them). Do not filter or second-guess the agent's choices — the user reviews directly and either squashes with `git rebase -i --autosquash <base>` or drops the fixups to discard.

   If the agent reports no findings, proceed silently.

   MR descriptions are out of scope for the agent; review the draft by hand at step 8.

8. **Draft the MR** per `.claude/mr-template.md`. Apply memory rules (skip CI-enforced checks in manual testing, no test counts). Self-check the draft for the same patterns the `ref-hygiene-checker` flags — off-site refs and past-state phrasing that the MR body shouldn't lean on either. Show the draft to the user. **Ask explicitly:** "Open the MR with this description?"
   - If approved → dispatch the `mr-handler` subagent to push the branch and open the MR.
   - If declined or revisions wanted → stop and surface the draft; the user will edit and re-invoke as needed.

9. **Summarize at the end:**
   - Commits produced (SHA + subject for each).
   - Iterations needed (one line per pass: what the review found, what changed).
   - Any Issues or Questions deferred (with the reason).
   - The MR URL if `mr-handler` dispatched; otherwise the draft.

## Hard constraints

- **Never call `git push` or `glab` directly.** Pushing and opening the MR happen only via the `mr-handler` subagent, and only after explicit user approval of the draft.
- **One MR per invocation.** If the spec calls for two MRs, run the skill twice.
- **Stop and ask on non-obvious Questions.** Do not silently pick a direction.

#!/usr/bin/env python3
"""Post a diff-anchored inline comment on a GitLab MR.

Usage:
    post-comment.py [--dry-run] [--ref ID=URL...] <workspace_dir> <path> <new_line>

Body is read from stdin.

<workspace_dir> must contain:
- `meta.json` with `project`, `mr_id`, and `diff_refs.{base_sha,start_sha,head_sha}`
  — produced by the skill's setup step.
- `diff.patch` — the MR's diff, used to validate that <new_line> is anchorable.

Before posting, validates the anchor: <new_line> must be either an added (`+`)
line or context (` `) line that appears in a hunk for <path>. If not, prints
the nearest valid lines and exits non-zero without posting.

Flags:
  --dry-run         Print the payload (body + resolved anchor) and exit 0 without
                    posting. Useful as a last-chance preview.
  --ref ID=URL...   Substitute `{{ref:ID}}` tokens in the body with URL. Use to
                    cross-reference previously-posted comments without hard-coding
                    GitLab note URLs in drafts.

Why JSON body and not glab `-f position[…]=value`:
glab's form encoder silently drops nested bracket fields, which turns the
discussion into a top-level note instead of a diff-anchored one. Sending the
position as a real JSON object fixes that.

On success, prints the discussion JSON to stdout and (unless --dry-run) caches
the {discussion_id, note_id, note_url} in `<workspace>/posted.json` keyed by a
short slug derived from the first ~40 chars of the body — so a follow-up
finding can reference it via --ref.

Exit codes:
  0  success (or dry-run)
  1  anchor invalid (line not in any hunk for path)
  2  usage error
  3  glab call failed
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import urllib.parse


def parse_diff_hunks(diff_text: str, target_path: str) -> list[dict]:
    """Return a list of hunks for `target_path`, each as {"new_start", "new_lines"}.

    `new_lines` is a list of (line_no, kind) where kind is "+" (added) or " " (context).
    Removed lines are not anchorable in DiffNote and are excluded.
    """
    hunks = []
    current_path = None
    in_target = False
    current_new_line = None
    current_hunk_lines: list[tuple[int, str]] = []
    hunk_re = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")

    for raw in diff_text.splitlines():
        if raw.startswith("--- "):
            # End previous hunk before switching files.
            if in_target and current_hunk_lines:
                hunks.append({"lines": current_hunk_lines})
                current_hunk_lines = []
            continue
        if raw.startswith("+++ "):
            # +++ b/path  or  +++ path
            p = raw[4:].strip()
            if p.startswith("b/"):
                p = p[2:]
            current_path = p
            in_target = current_path == target_path
            continue
        if not in_target:
            continue

        m = hunk_re.match(raw)
        if m:
            if current_hunk_lines:
                hunks.append({"lines": current_hunk_lines})
            current_new_line = int(m.group(1))
            current_hunk_lines = []
            continue

        if current_new_line is None:
            continue
        if raw.startswith("+") and not raw.startswith("+++"):
            current_hunk_lines.append((current_new_line, "+"))
            current_new_line += 1
        elif raw.startswith("-") and not raw.startswith("---"):
            # Removed line; doesn't advance new_line.
            pass
        elif raw.startswith(" ") or raw == "":
            current_hunk_lines.append((current_new_line, " "))
            current_new_line += 1
        # else: \ No newline at end of file etc. — ignore.

    if in_target and current_hunk_lines:
        hunks.append({"lines": current_hunk_lines})
    return hunks


def validate_anchor(diff_path: pathlib.Path, path: str, line: int) -> tuple[bool, str]:
    """Return (ok, message). On failure, message lists nearby valid lines."""
    if not diff_path.exists():
        # No diff to validate against — let the API decide.
        return True, ""
    hunks = parse_diff_hunks(diff_path.read_text(), path)
    if not hunks:
        return False, f"no hunks for {path!r} in diff.patch — file not in MR diff"
    all_lines = [(ln, k) for h in hunks for (ln, k) in h["lines"]]
    valid_lines = {ln for (ln, _) in all_lines}
    if line in valid_lines:
        return True, ""
    # Find the 3 nearest valid lines for a helpful error.
    nearby = sorted(valid_lines, key=lambda x: abs(x - line))[:6]
    nearby_sorted = sorted(nearby)
    examples = ", ".join(
        f"{ln} ({'+' if (ln, '+') in [(l, k) for (l, k) in all_lines] else ' '})"
        for ln in nearby_sorted
    )
    return False, (
        f"line {line} is not in any hunk for {path!r}; "
        f"nearest postable lines: {examples} "
        f"(+ = added, ' ' = context; both are anchorable, removed lines are not)"
    )


def cache_posted(workspace: pathlib.Path, body: str, response_json: dict) -> str:
    """Cache the posted note's URL keyed by a short slug from the body. Returns the URL."""
    posted_path = workspace / "posted.json"
    posted = {}
    if posted_path.exists():
        try:
            posted = json.loads(posted_path.read_text())
        except json.JSONDecodeError:
            pass
    # Build a stable URL from the response.
    note = response_json.get("notes", [{}])[0]
    note_id = note.get("id")
    discussion_id = response_json.get("id")
    meta = json.loads((workspace / "meta.json").read_text())
    host = meta.get("host", "gitlab.com")
    project = meta["project"]
    mr_id = meta["mr_id"]
    url = f"https://{host}/{project}/-/merge_requests/{mr_id}#note_{note_id}"
    # Slug: first 40 alphanumeric chars from the body.
    slug = re.sub(r"[^A-Za-z0-9]+", "-", body)[:40].strip("-").lower()
    posted[slug] = {
        "discussion_id": discussion_id,
        "note_id": note_id,
        "url": url,
    }
    posted_path.write_text(json.dumps(posted, indent=2, sort_keys=True))
    return url


def apply_refs(body: str, refs: dict[str, str]) -> str:
    """Substitute {{ref:ID}} tokens with URLs."""
    def sub(m: re.Match) -> str:
        key = m.group(1)
        if key not in refs:
            raise ValueError(f"unknown ref {key!r}; supply via --ref {key}=<url>")
        return refs[key]
    return re.sub(r"\{\{ref:([^}]+)\}\}", sub, body)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--ref", action="append", default=[])
    parser.add_argument("workspace")
    parser.add_argument("path")
    parser.add_argument("line", type=int)
    parser.add_argument("-h", "--help", action="store_true")
    try:
        args = parser.parse_args()
    except SystemExit:
        print(__doc__, file=sys.stderr)
        return 2
    if args.help:
        print(__doc__)
        return 0

    refs = {}
    for r in args.ref:
        if "=" not in r:
            print(f"--ref expects ID=URL, got {r!r}", file=sys.stderr)
            return 2
        k, v = r.split("=", 1)
        refs[k] = v

    workspace = pathlib.Path(args.workspace)
    meta = json.loads((workspace / "meta.json").read_text())
    project = meta["project"]
    iid = str(meta["mr_id"])
    refs_diff = meta["diff_refs"]
    raw_body = sys.stdin.read()
    try:
        body = apply_refs(raw_body, refs)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    # Validate anchor.
    ok, msg = validate_anchor(workspace / "diff.patch", args.path, args.line)
    if not ok:
        print(f"anchor validation failed: {msg}", file=sys.stderr)
        return 1

    payload = {
        "body": body,
        "position": {
            "base_sha": refs_diff["base_sha"],
            "start_sha": refs_diff["start_sha"],
            "head_sha": refs_diff["head_sha"],
            "position_type": "text",
            "new_path": args.path,
            "old_path": args.path,
            "new_line": args.line,
        },
    }

    if args.dry_run:
        print("=== DRY RUN — would post ===")
        print(f"anchor: {args.path}:{args.line}")
        print("---")
        print(body)
        print("---")
        print(f"diff_refs: {refs_diff}")
        return 0

    endpoint = (
        f"projects/{urllib.parse.quote(project, safe='')}"
        f"/merge_requests/{iid}/discussions"
    )
    cmd = [
        "glab", "api", "--method", "POST", endpoint,
        "--input", "-",
        "--header", "Content-Type: application/json",
    ]
    r = subprocess.run(cmd, input=json.dumps(payload), capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        return 3

    # Cache the URL for cross-references in future posts.
    try:
        cache_posted(workspace, body, json.loads(r.stdout))
    except (json.JSONDecodeError, KeyError, IndexError) as e:
        print(f"warning: could not cache posted URL: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

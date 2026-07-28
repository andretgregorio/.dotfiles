---
name: read-pr-comments
description: Fetches all open (unresolved) comments from a GitHub PR — both standalone PR comments and inline review thread comments — analyses each one, proposes implement/ignore decisions with reasoning, waits for user approval, applies approved changes, runs quality checks, pushes the branch, then replies to every comment with the outcome. Use when the user asks to "read PR comments", "address PR feedback", "respond to PR comments", "review PR comments", "apply PR feedback", or "handle review comments".
---

# Read PR Comments

Fetch every unresolved comment on a PR, decide what to do with each one, get the user's sign-off, apply the changes, run checks, push, and reply to all comments with a clear outcome statement.

## Step 1: Identify the PR

Look back through the current conversation for a PR number or URL (e.g. something produced by the `open-pr` skill, or a link the user pasted). If you find one, use it. If you cannot find one, ask:

> "Which PR should I address? Please share the PR number or URL."

## Step 2: Fetch All Unresolved Comments

Run the fetch script from the repo root:

```bash
bash ~/.claude/skills/read-pr-comments/scripts/fetch-pr-comments.sh <PR_NUMBER>
```

This returns a JSON array. Each element has:
- `id` — database ID (needed for replies)
- `type` — `"review"` (inline code comment) or `"standalone"` (PR-level comment)
- `author` — GitHub login
- `body` — the comment text
- `path` / `line` — file and line (review comments only)
- `createdAt` — timestamp

If the array is empty, tell the user there are no open comments and stop.

Skip comments created by Meticulous or @github-actions

## Step 3: Analyse and Present Each Comment

For every comment in the array, print a structured block. Work through them in chronological order (`createdAt` ascending).

**Format for each comment:**

```
─────────────────────────────────────────────────
COMMENT #<N> | <type> | @<author> | <path>:<line or "PR-level">
─────────────────────────────────────────────────
"<comment body>"

MY SUGGESTION: [IMPLEMENT] or [IGNORE]

REASONING:
<2–4 sentences explaining why you recommend implementing or ignoring this comment.
 Reference the specific code context, existing patterns, or tradeoffs.>
─────────────────────────────────────────────────
```

Decide `[IMPLEMENT]` when the comment identifies a real bug, a missing test, a security concern, a style violation that violates project conventions, or a clear improvement with low risk.

Decide `[IGNORE]` when the comment is a question that is already answered by the code, a purely subjective preference without justification, already addressed by another comment, or out of scope for this PR.

Print **all** blocks before asking for input — do not pause between comments.

## Step 4: Wait for User Validation

After printing all comment analyses, ask:

> "I've reviewed all N comments above.
> Please tell me which ones to apply (e.g. 'apply 1, 3, 5', 'apply all', 'skip 2 and 4', 'apply none').
> You can also say 'apply all' or 'skip all'."

Parse the user's response into two lists:
- **apply** — comment numbers to implement
- **skip** — comment numbers to ignore

## Step 5: Implement Approved Changes

For each comment in the **apply** list, implement the requested change. Work file by file to minimise context switching. After each change, briefly note what was done:

```
✓ Comment #<N> — <one-line description of the change made>
```

Do not implement anything from the **skip** list.

## Step 6: Run Quality Checks

Run the skill "/pr" to review the changes.

## Step 7: Push the Branch

```bash
git add -A
git commit -m "Address PR review comments"
git push
```

If the push is rejected (non-fast-forward), tell the user and ask them to resolve the conflict before continuing.

## Step 8: Reply to Every Comment

For **each comment** in the original list (both applied and skipped), post a reply:

```bash
bash ~/.claude/skills/read-pr-comments/scripts/reply-to-comment.sh \
  <PR_NUMBER> <COMMENT_ID> <TYPE> <AUTHOR> "<REPLY_BODY>"
```

**Reply body for applied comments:**
> "Done — <one-sentence description of the change made and the commit it landed in>."

**Reply body for skipped comments:**
> "Not applied — <one-sentence explanation of why this was not addressed>."

Confirm each reply with a short line:

```
↩ Replied to comment #<N> (@<author>)
```

## Output Summary

After all replies are posted, print a final summary:

```
═══════════════════════════════════════
PR COMMENTS — DONE
Applied:  <N> comments
Skipped:  <N> comments
Pushed:   ✓ / ✗
Replies:  <N>/<total> posted
═══════════════════════════════════════
```

## Troubleshooting

**`gh: command not found`**
Install the GitHub CLI: `brew install gh` (macOS) or see https://cli.github.com

**GraphQL returns empty `reviewThreads`**
The PR may have no inline review comments. Standalone comments will still appear under `comments`.

**`git push` rejected**
The remote branch has diverged. Ask the user to pull/rebase locally, then re-run from Step 7.

**Reply script fails with 404 on a review comment**
The comment ID may belong to a review thread whose root comment is different. The reply endpoint requires the ID of *any* comment in the thread — try the first comment's ID.

**Quality checks fail on unrelated code**
Flag the pre-existing failure to the user. Offer to skip checks with `--no-verify` only if the user explicitly approves it; add `# SECURITY OVERRIDE` comment if auth/input paths are involved.

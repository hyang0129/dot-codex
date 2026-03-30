---
description: Process approved PRs sequentially, rebasing or merging as needed.
---

# Merge Queue

## Purpose

Process all open PRs labeled `approved` in a single repo, merging what is ready and rebasing what is behind. Run this after labeling one or more PRs as approved.

Terminates when all labeled PRs have been either merged or had their label removed.

---

## Setup

### Git root detection (dev container safe)

Before any git operation, resolve the git working tree root. This is required because
in dev containers the shell may start at `/workspaces` which is above the repo mount:

```bash
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  # Try common dev container mount points
  for candidate in /workspaces/*; do
    if [ -d "$candidate/.git" ]; then
      GIT_ROOT="$candidate"
      break
    fi
  done
}
```

If `GIT_ROOT` is still empty, stop and tell the user:
"Could not find a git repository. Make sure you are inside a repo or pass the repo path."

**All `git` commands in this spec must run from `GIT_ROOT`** â€” either `cd "$GIT_ROOT"` first,
or use `git -C "$GIT_ROOT" <command>`.

### Parse arguments

Format is: `/merge-queue [label]`
- `label`: optional. Default: `approved`. The GitHub label that marks PRs as ready to merge.

### Repo detection

Detect the repo:
```bash
git remote -v
gh repo view --json nameWithOwner
```

From those results, determine the most likely `owner/repo`:
- If the working directory has exactly one GitHub remote, use it.
- If there are multiple remotes (e.g. `origin` + `upstream`), prefer `upstream` if present
  (fork workflow), otherwise prefer `origin`.
- If there is no git remote or the directory is not a git repo, check whether the conversation
  context mentions a repo name or URL.

**Always confirm before proceeding.** Present your guess to the user:

```
Repo detected: <owner/repo> (from <source: git remote origin | git remote upstream | gh repo view | conversation context>)

Proceed with merge queue for <owner/repo>? [yes / no / different-repo]
```

Wait for the user to confirm or correct before continuing.

If no repo can be guessed at all, ask:
```
Which GitHub repo should I process the merge queue for? (e.g. owner/repo)
```

Once confirmed, set `REPO=<owner/repo>` for all subsequent `gh` calls.

### Detect base branch

```bash
gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Store as `DEFAULT_BASE`. Typically `main` or `master`.

---

## Pre-flight â€” Clean checkout of base branch

Before doing anything, ensure a clean working tree on the base branch.

### Check for uncommitted changes

```bash
git -C "$GIT_ROOT" status --porcelain
```

If output is non-empty, ask the user:

> "There are uncommitted changes in the working tree. Discard them and continue, or stop?"

- **Discard**: `git -C "$GIT_ROOT" checkout -- . && git -C "$GIT_ROOT" clean -fd`
- **Stop**: abort the command immediately.

### Switch to base branch

```bash
git -C "$GIT_ROOT" checkout "$DEFAULT_BASE"
git -C "$GIT_ROOT" pull origin "$DEFAULT_BASE"
```

---

## Flow

```
Fetch labeled PRs
  |
  for each PR (sorted by number, ascending):
  |
  +-- CI failing or pending?
  |     +-- yes -> SKIP (leave label, log reason)
  |
  +-- Up-to-date with base + CI green?
  |     +-- yes -> MERGE (squash merge, delete branch, remove label)
  |
  +-- Behind base?
  |     +-- invoke /rebase on the branch
  |           +-- READY -> MERGE (squash merge, delete branch, remove label)
  |           +-- BLOCKER -> remove label, log blocker reason, continue
  |
  +-- next PR (re-fetch base since it may have moved)
```

---

## Step 1 â€” Fetch labeled PRs

```bash
gh pr list --repo "$REPO" --label "<label>" --state open --base "$DEFAULT_BASE" \
  --json number,headRefName,baseRefName,title,url,body \
  --jq 'sort_by(.number)'
```

If no PRs found: report "No open PRs with label `<label>` found." and stop.

Present the queue to the user:

```
## Merge queue: <REPO>

Label: <label>
Base:  <DEFAULT_BASE>

| #   | Branch                  | Title                        |
|-----|-------------------------|------------------------------|
| 123 | fix/issue-123-foo       | fix: foo                     |
| 145 | feat/issue-145-bar      | feat: bar                    |
| 201 | fix/issue-201-baz       | fix: baz                     |

Processing <N> PRs in order. Starting now.
```

Store the list as `QUEUE`.

---

## Step 2 â€” Process each PR

For each PR in `QUEUE`, in ascending order by PR number:

### 2a â€” Checkout and refresh state

Checkout the PR branch and fetch the latest base. A prior merge may have changed the base.

```bash
git -C "$GIT_ROOT" checkout <headRefName>
git -C "$GIT_ROOT" fetch origin "$DEFAULT_BASE"
```

Get PR CI status:

```bash
gh pr checks <PR_NUMBER> --repo "$REPO" --json name,state,conclusion
```

Classify:
- **CI passing**: all required checks have `conclusion: success` or `conclusion: skipped`
- **CI pending**: any required check has `state: pending` or `state: queued`
- **CI failing**: any required check has `conclusion: failure`

Get merge readiness:

```bash
gh pr view <PR_NUMBER> --repo "$REPO" --json mergeable,mergeStateStatus
```

- `mergeStateStatus: CLEAN` -> up-to-date, CI green, ready to merge
- `mergeStateStatus: BEHIND` -> needs rebase
- `mergeStateStatus: BLOCKED` -> check why (CI, conflicts, etc.)
- `mergeStateStatus: UNSTABLE` -> some non-required checks failing, but mergeable

### 2b â€” Route

| Condition | Action |
|-----------|--------|
| CI pending | **SKIP** â€” log `PR #<N>: CI still running, skipping`. Leave label. |
| CI failing + up-to-date | **SKIP** â€” log `PR #<N>: CI failing, skipping`. Leave label. |
| `CLEAN` or `UNSTABLE` | Go to **Step 3 â€” Merge** |
| `BEHIND` | Go to **Step 4 â€” Rebase** |
| `BLOCKED` (conflicts) | Go to **Step 4 â€” Rebase** |

---

## Step 3 â€” Merge

```bash
gh pr merge <PR_NUMBER> --repo "$REPO" --squash --delete-branch
```

If merge succeeds:
- Remove the label:
  ```bash
  gh pr edit <PR_NUMBER> --repo "$REPO" --remove-label "<label>"
  ```
- Write a merge report (see **Merge Reports** below).
- Log: `PR #<N>: merged.`
- Continue to next PR.

If merge fails (race condition, protection rule, etc.):
- Log the error.
- Do **not** remove the label.
- Continue to next PR.

---

## Step 4 â€” Rebase

The PR branch is behind the base. We are already checked out on `<headRefName>` from Step 2a.

Invoke `/rebase` to bring it up to date:

```
/rebase <headRefName> <DEFAULT_BASE>
```

**Wait for /rebase to complete.** It will terminate in one of two states:

### 4a â€” Handle /rebase result

**If READY:**

`/rebase` has already force-pushed and confirmed CI is passing.

Proceed to merge:

```bash
gh pr merge <PR_NUMBER> --repo "$REPO" --squash --delete-branch
```

If merge succeeds:
- Remove the label:
  ```bash
  gh pr edit <PR_NUMBER> --repo "$REPO" --remove-label "<label>"
  ```
- Write a merge report (see **Merge Reports** below).
- Log: `PR #<N>: rebased and merged.`

If merge fails:
- Log the error.
- Do **not** remove the label.

**If BLOCKER:**

`/rebase` could not complete. It has already posted a BLOCKER comment on the PR.

- Remove the label:
  ```bash
  gh pr edit <PR_NUMBER> --repo "$REPO" --remove-label "<label>"
  ```
- Log: `PR #<N>: rebase BLOCKER â€” label removed. Human intervention required.`

### 4b â€” Continue

Proceed to next PR. Step 2a will checkout the next branch.

---

## Step 5 â€” Return to base branch

```bash
git -C "$GIT_ROOT" checkout "$DEFAULT_BASE"
```

---

## Merge Reports

After each successful merge, write a short markdown report to `GIT_ROOT/merge-reports/<PR_NUMBER>.md`:

```markdown
# PR #<number>: <title>

- **PR**: <url>
- **Branch**: <headRefName>
- **Merged**: <timestamp>
- **Method**: <merged | rebased and merged>

## Summary

<1â€“3 sentence summary of what the PR changed and why, derived from the PR body>
```

Read the PR `body` (fetched in Step 1) to write the summary. If the body is empty or uninformative, summarize from the PR title instead.

Create the `merge-reports/` directory if it does not exist. These files are written to the working tree â€” they are **not** committed. The user can review, commit, or discard them.

---

## Step 6 â€” Summary

After processing all PRs, present a summary:

```
## Merge queue complete

| #   | Title                        | Result              |
|-----|------------------------------|---------------------|
| 123 | fix: foo                     | merged              |
| 145 | feat: bar                    | rebased and merged  |
| 201 | fix: baz                     | BLOCKER â€” removed   |
| 210 | feat: qux                    | skipped (CI pending)|

Merged: <N>
Blocked: <N>
Skipped: <N>
```

---

## Constraints

- **Never push to the base branch directly.** Only merge via `gh pr merge`.
- **Never force-push.** Only `/rebase` force-pushes (with `--force-with-lease`), and only to feature branches.
- Follow the repo's `AGENTS.md` or local project instructions before starting if present.
- **One PR at a time.** Do not attempt parallel merges. The sequential order ensures each rebase is against the latest base.
- **Do not modify code.** This command orchestrates merges and invokes `/rebase`. It does not fix tests, resolve conflicts, or edit files directly.
- **Leave label on skipped PRs.** If a PR is skipped (CI pending/failing), the label stays so it's picked up on the next run.
- **Remove label on BLOCKER.** The human needs to intervene, re-run `/rebase` manually, and re-label when ready.

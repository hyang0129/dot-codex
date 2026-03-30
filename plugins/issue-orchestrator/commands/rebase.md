---
description: Rebase a PR branch in Codex after review-fix using a bounded conflict resolver and intent validation.
---

# Rebase

## Preflight

Parse arguments as:
`/rebase [branch] [base-branch]`

- `branch`: optional. Defaults to the current branch.
- `base-branch`: optional. Defaults to the PR base branch or `main`.

Before doing anything else:
- Read `~/.codex/plugins/issue-orchestrator/guides/pr-guide.md`.
- Resolve the git root.
- Confirm the branch has an open PR.
- Confirm the working tree is clean.

## Plan

Run the post-review-fix rebase flow in Codex:

1. Read the `review-fix-summary` PR comment.
2. Capture pre-rebase CI state.
3. Remove planning and review artifacts.
4. Rebase onto the base branch.
5. If conflicts occur, spawn a bounded conflict resolver worker.
6. Spawn a senior intent reviewer explorer.
7. Run fast local sanity checks.
8. Push with `--force-with-lease`.
9. Wait for PR CI and compare with the baseline.
10. End in exactly one state: `READY` or `BLOCKER`.

## Commands

### 1. Git root, PR, and base branch

Resolve the git root:

```bash
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  for candidate in /workspaces/*; do
    if [ -d "$candidate/.git" ]; then
      GIT_ROOT="$candidate"
      break
    fi
  done
}
```

Determine the branch and PR:

```bash
git -C "$GIT_ROOT" branch --show-current
gh pr list --head <branch> --json number,title,url,baseRefName,state --limit 1
```

If no PR is found, stop.

### 2. Review-fix precondition

Read the PR comments and locate the comment containing:

```html
<!-- review-fix-summary -->
```

If that comment is missing:
- warn the user,
- ask whether to continue anyway,
- stop if they decline.

If the comment is present, inspect it for:
- remaining critical or major findings,
- high intent risks,
- overall cleanliness.

### 3. Capture CI baseline

Before rebasing, fetch the current PR check state:

```bash
gh pr checks <PR_NUMBER> --json name,status,conclusion
```

Store that as the baseline so you can tell whether failures after the force-push are new regressions or pre-existing failures.

### 4. Remove artifacts

List changed files:

```bash
git -C "$GIT_ROOT" diff <BASE>...HEAD --name-only
```

Remove planning/review artifacts such as:
- `ISSUE_*_PLAN.md`
- `ISSUE_*_ADR.md`
- `ISSUE_*_REVIEW.md`
- `REVIEW_FINDINGS*.md`
- `FIX_PLAN*.md`
- `FIX_RESULT_*.md`
- `INTENT_VALIDATION.md`
- `REBASE_INTENT_REVIEW.md`
- `CONFLICT_RESOLUTION.md`

Commit the artifact removal before the rebase if needed.

### 5. Rebase and Codex sub-agents

Run:

```bash
git -C "$GIT_ROOT" fetch origin
git -C "$GIT_ROOT" rebase origin/<BASE>
```

If the rebase is clean, continue.

If conflicts occur, spawn:
- Conflict Resolver worker: `spawn_agent(agent_type="worker", model="gpt-5.4-mini", ...)`

Conflict Resolver scope:
- only resolve lines inside conflict markers,
- preserve fix intent when possible,
- do not do unrelated cleanup,
- report any unresolvable conflict in `CONFLICT_RESOLUTION.md`.

If any conflict is unresolvable, abort the rebase and return BLOCKER.

### 6. Intent validation

After a clean rebase, spawn:
- Senior Review Engineer explorer: `spawn_agent(agent_type="explorer", model="gpt-5.4", ...)`

This agent must compare:
- the pre-rebase implementation intent,
- the post-rebase diff,
- whether the fix was weakened or inverted.

Write `REBASE_INTENT_REVIEW.md`.

If any `high` intent risk exists, stop with BLOCKER.
If `medium` risks exist, present them to the user and wait for a decision before continuing.

### 7. Local sanity checks

Run fast checks only:

```bash
<compile command if applicable>
<typecheck command if applicable>
<lint command if applicable>
```

Do not fix code here. If these checks fail, stop with BLOCKER.

### 8. Force push and CI watch

Push with:

```bash
git -C "$GIT_ROOT" push --force-with-lease origin <BRANCH>
```

Then watch CI:

```bash
gh pr checks <PR_NUMBER> --watch
```

If `--watch` is unavailable, poll:

```bash
gh pr checks <PR_NUMBER> --json name,status,conclusion
```

Compare the final state to the pre-rebase baseline:
- passing before and after: OK,
- failing before and after: note as pre-existing,
- passing before but failing after: BLOCKER,
- newly appeared and failing after the push: BLOCKER.

### 9. READY vs BLOCKER output

If clean:
- update the PR description,
- post a merge-ready comment,
- report `READY`.

If blocked:
- post a blocker comment with the reason,
- include the PR URL,
- stop further automation.

## Verification

Before finishing, confirm:
- the review-fix summary comment was read,
- artifact files were removed from the branch,
- the rebase either completed cleanly or was explicitly aborted,
- the push used `--force-with-lease`,
- the final state is unambiguously `READY` or `BLOCKER`.

## Summary

Return one of:

```md
## rebase complete
- **Branch**: <branch>
- **Base**: <base>
- **PR**: <url>
- **Status**: READY
```

```md
## rebase complete
- **Branch**: <branch>
- **Base**: <base>
- **PR**: <url>
- **Status**: BLOCKER
```

## Next Steps

- If READY, tell the user the PR is ready for human review and squash merge.
- If BLOCKER, tell the user exactly what must be fixed before rerunning `/rebase`.

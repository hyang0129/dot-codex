# Rebase Workflow

Use this flow after review-fix, or as a standalone post-review cleanup on an open PR branch.

## Inputs

- `branch`: optional, defaults to the current branch
- `base-branch`: optional, defaults to the PR base branch or `main`

## Plan

Run this post-review-fix rebase flow:

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

## PR and base branch discovery

- determine the branch and PR from the current repo state
- stop if no PR is found
- infer the base branch from the PR if not supplied

## Review-fix precondition

Locate the PR comment containing `<!-- review-fix-summary -->`.

If the comment is missing:
- warn the user
- ask whether to continue anyway
- stop if they decline

If the comment is present, inspect it for:
- remaining critical or major findings
- high intent risks
- overall cleanliness

## CI baseline

Before rebasing, fetch the current PR check state and store it as a baseline so new failures can be distinguished from pre-existing ones.

## Artifact cleanup

Remove planning and review artifacts such as:
- `ISSUE_*_PLAN.md`
- `ISSUE_*_ADR.md`
- `REVIEW_FINDINGS*.md`
- `FIX_PLAN*.md`
- `FIX_RESULT_*.md`
- `INTENT_VALIDATION.md`
- `REBASE_INTENT_REVIEW.md`
- `CONFLICT_RESOLUTION.md`

Commit the artifact removal before the rebase if needed.

## Rebase and conflict resolution

Run the rebase against the base branch.

If conflicts occur, spawn a Conflict Resolver worker with this scope:
- only resolve lines inside conflict markers
- preserve fix intent when possible
- do not do unrelated cleanup
- report any unresolvable conflict in `CONFLICT_RESOLUTION.md`

If any conflict is unresolvable, abort the rebase and return `BLOCKER`.

## Intent validation

After a clean rebase, spawn a senior review explorer to compare:
- the pre-rebase implementation intent
- the post-rebase diff
- whether the fix was weakened or inverted

Write `REBASE_INTENT_REVIEW.md`.

If any high intent risk exists, stop with `BLOCKER`.
If medium risks exist, present them to the user and wait for a decision before continuing.

## Sanity checks and push

Run fast local checks only:
- compile, if applicable
- typecheck, if applicable
- lint, if applicable

Do not fix code here. If these checks fail, stop with `BLOCKER`.

Push with `--force-with-lease`, then watch PR CI or poll until it completes.

Compare final CI state to the pre-rebase baseline:
- passing before and after: OK
- failing before and after: note as pre-existing
- passing before but failing after: `BLOCKER`
- newly appeared and failing after push: `BLOCKER`

## Final state

If clean:
- update the PR description
- post a merge-ready comment
- report `READY`

If blocked:
- post a blocker comment with the reason
- include the PR URL
- stop further automation

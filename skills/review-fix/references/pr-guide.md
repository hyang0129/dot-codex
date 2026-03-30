# PR Workflow Guide

## Reviewing a PR

When reviewing a PR, always create a task list of problems found:

1. Read through all changed files in the PR.
2. For each problem identified, add it as a task.
3. Use the task list as the source of truth for what must be resolved before the PR is ready.

## Pushing to a PR

Before pushing changes to a PR, cross-reference the review task list:

1. Check which reviewed problems have been resolved by the current changes.
2. Mark resolved tasks as completed.
3. If unresolved problems remain, note them rather than silently pushing.
4. Include a summary of which review items were addressed in the commit or push context.

## General Best Practices

- Understand the PR intent so fixes do not drift out of scope.
- Run tests after changes to confirm nothing is broken before pushing.
- Keep fixes in separate commits so reviewers can follow what changed and why.
- Re-read surrounding code after fixes to avoid introducing new problems.
- Respect draft PR status and do not push changes unless explicitly asked.
- When review-fix changes the state of the PR, update the PR description as well as the summary comment.
- Review comments should be legible to humans first: include findings fixed, outstanding risks, intent validation, and any decisions still needed.
- In `Review summary`, always include cycles run, findings fixed, findings deferred, current risk level, intent validation result, and whether the PR is clean or what remains.

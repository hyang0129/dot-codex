# PR Workflow Guide

## Reviewing a PR

When reviewing a PR, always create a task list of problems found:

1. Read through all changed files in the PR.
2. For each problem identified (bugs, style issues, missing tests, logic errors, etc.), add it as a task.
3. The task list serves as the source of truth for what needs to be resolved before the PR is ready.

## Pushing to a PR

Before pushing changes to a PR, cross-reference the review task list:

1. Check which reviewed problems have been resolved by the current changes.
2. Mark resolved tasks as completed.
3. If unresolved problems remain, note them — do not silently push without acknowledging outstanding issues.
4. Include a summary of which review items were addressed in the commit or push context.

## General Best Practices

- **Scope check**: Before making changes, understand the PR's intent so fixes don't drift out of scope. Don't refactor unrelated code or add features that belong in a separate PR.
- **Test verification**: Run tests after making changes to confirm nothing is broken before pushing.
- **Incremental commits**: Keep fixes in separate commits so reviewers can follow what changed and why. Don't squash unrelated fixes together.
- **Re-review after changes**: After fixing issues, re-read surrounding code to avoid introducing new problems while resolving old ones.
- **Draft awareness**: Respect draft PR status — review and provide feedback but don't push changes unless explicitly asked.

# Merge Queue Workflow

## Goal

Process all open PRs in one repository that carry a queue label, usually `approved`. Merge PRs that are ready, rebase branches that are behind, and stop short of manual code repair or conflict resolution.

Terminate when every labeled PR has been processed for this run as one of:
- merged
- rebased and merged
- blocked and de-labeled
- skipped because it is not ready yet

## Input Handling

Treat the command shape as:
- `repo`: optional, but confirm the detected repository before acting
- `label`: optional, default to `approved`

If the user does not specify a repository, inspect git remotes and PR context to infer one. Prefer `upstream` over `origin` in fork workflows. Show the inferred `owner/repo` and ask for confirmation before the queue run begins.

Detect the default base branch before listing PRs. Usually this is `main` or `master`.

## Safety Checks

Resolve the git root before any git command. If no git root can be found, stop and ask the user for the repository path or repository name.

Inspect the working tree before switching branches:
- if clean, continue
- if dirty, pause and ask whether to stop or discard the changes

Only discard changes with explicit user approval. If the user does not approve cleanup, stop the run.

After approval to proceed, switch to the default base branch and update it from the main remote before processing the queue.

## Queue Discovery

List open PRs in the confirmed repository that:
- have the requested label
- target the default base branch
- are sorted by PR number ascending

If there are no matching PRs, report that no queued PRs were found and stop.

Before processing, present:
- repository
- label
- base branch
- ordered PR table
- total count

## Per-PR Loop

For each queued PR in ascending order:

1. Refresh branch context.
   - check out the PR head branch locally if the workflow is using local git
   - fetch the latest base branch because prior merges may have moved it

2. Inspect checks and merge state.
   - classify CI as passing, pending, or failing
   - inspect merge readiness, especially whether the PR is `CLEAN`, `UNSTABLE`, `BEHIND`, or otherwise blocked

3. Route by state.

### Skip Cases

Skip the PR and leave its label untouched when:
- CI is still pending
- CI is failing and the PR is otherwise up to date
- mergeability is not ready for a reason that should simply be retried later

Log the reason in the run summary.

### Merge Cases

Merge immediately when the PR is ready and the checks policy allows it, typically for:
- `CLEAN`
- `UNSTABLE` if the repository policy still permits merge

Use squash merge and delete the branch when that is the repository norm. If merge succeeds:
- remove the queue label
- write a merge report
- log the result as `merged`

If the merge fails because of a race, branch protection, or a stale state:
- log the failure
- do not remove the label
- continue to the next PR

### Rebase Cases

Invoke `$rebase` when the PR is behind the base branch or blocked by branch divergence/conflicts that rebasing is expected to address.

Use the PR head branch and the current default base branch as inputs. Wait for `$rebase` to finish before continuing.

Handle the result like this:
- if `$rebase` ends in `READY`, attempt the squash merge, remove the label on success, write a merge report, and log `rebased and merged`
- if `$rebase` ends in `BLOCKER`, remove the queue label, assume the rebase flow already left enough context for a human, and log `BLOCKER - label removed`

If the follow-up merge after a successful rebase fails, log the failure and leave the label in place.

## Merge Reports

After each successful merge, write `merge-reports/<pr-number>.md` in the git root. Do not commit these files automatically.

Each report should contain:
- PR number and title
- PR URL
- source branch
- timestamp
- method: `merged` or `rebased and merged`
- a short 1-3 sentence summary based on the PR body when available, otherwise the title and other PR metadata

Create the `merge-reports/` directory if it does not exist.

## Completion

At the end of the run:
- return to the default base branch if local checkout was used
- present a summary table covering every processed PR
- include counts for merged, blocked, and skipped

## Constraints

- Never merge PRs in parallel.
- Never force-push from this skill.
- Never edit code as part of the queue run.
- Never remove the label from skipped PRs.
- Always remove the label from blocker cases that require human intervention.

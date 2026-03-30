# Fix Issue Workflow

Use this flow when Codex should take a GitHub issue from intake through planning, implementation, PR creation, review-fix, and rebase.

## Inputs

- `issue`: required, GitHub issue number or full issue URL
- `tier`: optional override, `1`, `2`, or `3`

## Preflight

Before doing anything else:
- read [agent-team-guide.md](./agent-team-guide.md)
- confirm `gh` is installed and authenticated
- resolve the git root
- verify the working tree is clean

If `issue` is only a number:
- detect the repo from git remotes or `gh repo view`
- confirm the detected repo with the user before fetching the issue

Stop if:
- no git repo can be found
- `gh` is unavailable
- the working tree is dirty
- the repo guess is ambiguous and the user has not confirmed it

## Plan

Run this as a single Codex-native orchestration flow:

1. Fetch the issue and assign it if needed.
2. Assess complexity and create the feature branch.
3. Spawn a Planner sub-agent first.
4. If the plan surfaces open architecture questions, spawn an Architect and pause for ADR approval.
5. After approval, spawn implementation sub-agents using Codex-native roles and model choices.
6. Validate, review, commit, push, and open the PR.
7. Continue directly into the review-fix phase when there are no blockers.
8. Continue directly into the rebase phase when review-fix finishes without blockers.

Do not reduce the flow to "go run another command" when the workflow can continue inline.

## Issue fetch and repo setup

If `issue` is a full URL, extract `owner/repo` and the issue number.

If `issue` is only a number:
- inspect `git remote -v`
- inspect `gh repo view --json nameWithOwner`
- present the detected repo and ask the user to confirm

Fetch the issue and assign it to `@me` if unassigned.

Inspect:
- current branch
- recent history
- working tree state

Create the feature branch as `fix/issue-<number>-<slug>`.

## Tiering

Use the tier rules from [agent-team-guide.md](./agent-team-guide.md).

- Tier 1: one area, clear requirements, small diff
- Tier 2: multiple areas, clear requirements
- Tier 3: architecture questions, shared interfaces, or substantial unknowns

If the user passed a tier override, respect it. Otherwise explain the tier choice briefly before proceeding.

## Planner phase

Spawn a Planner explorer with read-only responsibilities plus permission to write the plan file:
- read the full issue
- search the repo for affected files and relevant patterns
- produce `ISSUE_<number>_PLAN.md`

The plan should contain:
- summary
- affected files
- file ownership table
- task list by wave
- acceptance criteria
- open questions

After the Planner returns:
- read the plan
- post a pre-implementation check comment to the issue
- decide whether architecture review is required

## Architect and ADR gate

If Tier 2 has open architecture questions, or if the issue is Tier 3, spawn an Architect explorer.

Architect output:
- `ISSUE_<number>_ADR.md`
- options
- recommendation
- consequences
- updated acceptance criteria

Post the ADR back to the issue as checkbox decisions.

Pause implementation here. Do not spawn implementation workers until the user has approved the ADR on GitHub.

Poll issue comments until one of these happens:
- `APPROVED`: read the selected options, update ADR status to `ACCEPTED`, and continue
- `REJECT`: stop and report that implementation is paused

## Implementation phase

Use the plan and approved ADR to assign sub-agents.

Tier 1:
- spawn one Coder worker
- run checks
- spawn one Reviewer explorer

Tier 2:
- spawn parallel workers for independent Coder and Tester tasks
- wait for the whole wave
- run checks
- spawn Integrator
- spawn Reviewer

Tier 3:
- execute implementation in waves
- spawn all independent workers for the current wave
- wait for the whole wave
- run checks before moving to the next wave
- after all waves, spawn Integrator and one or more Reviewers

Every worker task spec must include:
- issue number and title
- exact files to read
- exact files allowed to edit
- files explicitly out of scope
- acceptance criteria
- required outputs

## Validation and PR creation

Run project-appropriate checks in this order:
- compile, if applicable
- typecheck, if applicable
- lint, if applicable
- test

If checks fail:
- route the failure back to the responsible worker
- retry with bounded scope
- do not commit broken code

After checks pass:
- stage only issue-scoped files
- commit with `fix(#<number>): <summary>`
- push the feature branch
- create the PR

Update the PR body with a human-readable implementation walkthrough before moving on.

## Inline review-fix continuation

Do not stop after creating the PR if there are no blockers.

Continue in the same flow using [review-fix.md](./review-fix.md):
- run the initial review
- partition findings
- spawn Fixer workers where needed
- commit review-fix batches
- produce the review-fix summary comment

Only stop here if review-fix encounters a blocker that requires human intervention.

## Inline rebase continuation

If the review-fix phase completes without blockers, continue in the same flow using [rebase.md](./rebase.md):
- capture pre-rebase CI
- remove artifact files
- rebase
- resolve conflicts with a bounded conflict resolver if needed
- validate intent
- push with `--force-with-lease`
- wait for PR CI
- post READY or BLOCKER

If the rebase phase reaches `BLOCKER`, stop and report it clearly.

## Final verification

Before finishing, confirm:
- the issue was fetched from the correct repo
- the branch exists and was pushed
- the PR was created
- the review-fix summary comment was posted if review-fix ran
- the rebase phase either reached `READY` or reported a clear `BLOCKER`
- any ADR pause or blocker state was made explicit to the user

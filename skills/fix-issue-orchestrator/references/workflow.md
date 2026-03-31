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
- inspect the GitHub issue for duplicate-run coordination signals before any local setup

This workflow is worktree-based. Do not implement on the user's current checkout when the issue-to-PR flow starts from the main repo working tree.

If `issue` is only a number:
- detect the repo from git remotes or `gh repo view`
- confirm the detected repo with the user before fetching the issue

Stop if:
- no git repo can be found
- `gh` is unavailable
- the working tree is dirty
- the repo guess is ambiguous and the user has not confirmed it

## Cross-container claim

Before creating a branch or worktree, check whether the issue already appears to be in progress elsewhere.

Inspect these GitHub signals:
- a top-level issue comment containing a stable sentinel such as `<!-- codex-fix-issue-claim -->`
- the timestamp and status on the latest claim comment
- whether the claim looks active, stale, or closed
- any open PR that already references the issue and appears to be an active implementation attempt
- optional coordination labels such as `codex:in-progress` when the repo uses them

Treat this as a soft lock, not a perfect distributed lock. It is meant to prevent human-gap duplicate invocations across dev containers, not simultaneous machine races.

Default decision rules:
- if there is a fresh active claim comment, stop and tell the user who started it and when
- if there is an open implementation PR for the same issue and no explicit override, stop and surface that PR
- if the latest claim is stale, report that it looks stale and reclaim it by posting a new active claim or updating the old one
- only override an active claim when the user explicitly tells you to continue anyway

The claim comment should include at least:
- issue number
- actor or runner identity when available
- repo identity
- start timestamp
- current status such as `claimed`, `planning`, `implementing`, `review-fix`, `rebase`, `done`, `blocked`, or `abandoned`
- branch name once known
- PR number once known
- a heartbeat timestamp
- the sentinel `<!-- codex-fix-issue-claim -->`

## Worktree setup

Before planning or implementation:
- choose a dedicated worktree path for the issue branch
- create the feature branch worktree from the repo root or attach to an existing issue worktree if one already exists for the same branch
- switch the main run to use that worktree as its execution root

Use the worktree for:
- planner artifacts
- ADR artifacts
- implementation worker edits
- validation
- commit, push, review-fix, and rebase work

Do not run the issue workflow from the user's primary checkout once the worktree has been created.

## Plan

Run this as a single Codex-native orchestration flow:

1. Fetch the issue and assign it if needed.
2. Assess complexity, create the feature branch, and create the dedicated worktree.
3. Spawn a Planner sub-agent first.
4. If the plan surfaces open architecture questions, spawn an Architect and pause for ADR approval.
5. After approval, spawn implementation sub-agents using Codex-native roles and model choices.
6. Validate, review, commit, push, and open the PR.
7. Run a dedicated documentation pass that rewrites the PR body from the issue, plan, and final diff into a reviewer-facing narrative.
8. Continue directly into the review-fix phase when there are no blockers.
9. Continue directly into the rebase phase when review-fix finishes without blockers.

Do not reduce the flow to "go run another command" when the workflow can continue inline.

## Issue fetch and repo setup

If `issue` is a full URL, extract `owner/repo` and the issue number.

If `issue` is only a number:
- inspect `git remote -v`
- inspect `gh repo view --json nameWithOwner`
- present the detected repo and ask the user to confirm

Fetch the issue and assign it to `@me` if unassigned.

Before creating the feature branch, create or refresh the active issue claim on GitHub so later invocations can see that this issue is already in progress.

Inspect:
- current branch
- recent history
- working tree state

Create the feature branch as `fix/issue-<number>-<slug>`.
Create a dedicated worktree for that branch before continuing.

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
- close or leave idle any planning-only agents before implementation begins
- refresh the issue claim heartbeat and mark the run as `planning` or `ready-for-implementation`

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

While paused for ADR approval, keep the issue claim current enough that a second invocation can see this run is still active.

## Implementation phase

Use the plan and approved ADR to assign sub-agents.

The orchestrator does not implement product changes in this phase or in later inline phases. All repository-file edits other than workflow artifacts must be delegated to workers.

Treat these as orchestrator-owned workflow artifacts only:
- `ISSUE_<number>_PLAN.md`
- `ISSUE_<number>_ADR.md`
- PR body updates and implementation walkthroughs
- issue comments and ADR decision summaries
- review-fix summary outputs
- rebase status outputs

The orchestrator must not edit:
- production code
- test files
- product documentation

Product documentation here means repository documentation such as `README`, changelog files, docs pages, and developer docs that ship with the repo. PR descriptions, issue comments, and workflow artifact files remain orchestrator-owned.

Those repository-file edits belong to implementation workers or to a fully local non-orchestrator flow where no implementation workers are spawned.

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

Once implementation workers are spawned, keep the orchestrator in coordination mode:
- inspect files and diffs
- run read-only discovery commands
- prepare validation and integration steps
- manage git and GitHub handoffs

Refresh the issue claim heartbeat at major phase changes and after any long pause so another container does not mistake this run for abandoned work.

Do not use the orchestrator to edit repository product files during implementation, review-fix, or rebase follow-through.

## Validation and PR creation

Run project-appropriate checks in this order:
- compile, if applicable
- typecheck, if applicable
- lint, if applicable
- test

If checks fail:
- route the failure back to the responsible worker
- retry with bounded scope
- allow at most 1 worker retry per failing implementation batch before escalating the failure back to the orchestrator summary
- do not commit broken code

After checks pass:
- stage only issue-scoped files
- commit with `fix(#<number>): <summary>`
- push the feature branch
- create the PR

After the PR is created, update the issue claim with the branch, PR number, and latest status so future invocations can stop early and redirect to the existing run.

Before moving on, update the PR body so it is a reviewer-facing deliverable rather than a loose summary.

Run a dedicated documentation pass before review-fix begins. The documentation pass may be performed by the orchestrator or by a bounded read-only explorer, but it must:
- read the issue, plan, ADR if present, and final implementation diff
- read surrounding code for the main changed functions, classes, methods, or modules
- rewrite the PR body as a coherent reviewer document instead of only filling headings
- prefer concrete behavioral explanation over diff narration
- use Mermaid when multiple layers or non-obvious control flow interact
- explicitly describe before and after execution for behavioral fixes

The PR body must include these sections, using `N/A` only when a section is truly not relevant:
- `What changed`
- `Implementation walkthrough`
- `How components interact` when multiple components or layers are involved
- `Default execution path`
- `Edge cases and error handling`
- `Tier / approach`
- `Acceptance criteria`
- `Outstanding items`
- `Review summary`
- `History`
- `Merge instructions`

Required content for each section:
- `What changed`: summarize the bug or root cause, the scope boundary of the fix, and the user-visible or developer-visible outcome after the change
- `Implementation walkthrough`: name the main files, functions, classes, methods, or modules changed and explain what each one now does
- `How components interact`: explain the control flow or data flow across the touched components, including call order and important preconditions or postconditions; include a diagram when the interaction spans multiple layers or would otherwise be hard to follow in prose
- `Default execution path`: describe the normal path before the fix, why the old behavior failed or drifted, and what the new steady-state path does instead
- `Edge cases and error handling`: enumerate invalid inputs, fallback behavior, retries, missing config or tooling behavior, and intentionally unchanged paths
- `Tier / approach`: explain the implementation approach chosen for the selected tier and why it fits the issue scope
- `Acceptance criteria`: map each issue criterion to an explicit `[x]` or `[ ]` item with a short note
- `Outstanding items`: list follow-ups, deferred work, or explicitly state that none remain
- `Review summary`: summarize the current review state, major findings fixed, findings deferred, current risk level, and whether the PR is clean or what still remains
- `History`: record implementation, review-fix, and rebase milestones in chronological order
- `Merge instructions`: state the intended merge strategy and any remaining human actions needed before merge

Style requirements for substantial PRs:
- prefer reviewer-facing explanations anchored to specific functions, files, and execution paths over generic summaries
- when the change fixes a behavioral bug, explicitly describe the old behavior, why it happened, and the new behavior
- name the main files and concrete code anchors in each narrative section whenever possible
- treat `Default execution path` as required for pipeline, middleware, adapter, agent, CLI, or multi-step behavior changes
- include intentionally unchanged paths or deferred follow-ups when they are likely reviewer questions
- do not rely on placeholder prose such as "updated logic" or "improved handling" without naming what changed

Populate the initial PR body with the implementation-stage information that is already known. Do not leave placeholder headings empty, and prefer concrete implementation anchors such as named functions, key methods, file roles, and control-flow steps.

The orchestrator owns the final PR narrative quality even when implementation and test edits were delegated. Before continuing to review-fix, verify that the PR body reads as one coherent explanation instead of a stitched set of worker notes.

## Inline review-fix continuation

Do not stop after creating the PR if there are no blockers.

Continue by invoking the standalone `$review-fix` skill as the source of truth for this phase:
- run the initial review
- partition findings
- spawn Fixer workers where needed
- commit review-fix batches
- produce the review-fix summary comment
- refresh the PR description after review-fix so `Review summary`, `Outstanding items`, `History`, `Acceptance criteria`, and `Merge instructions` reflect the latest verified state
- refresh the issue claim status to `review-fix`

Only stop here if review-fix encounters a blocker that requires human intervention.

## Inline rebase continuation

If the review-fix phase completes without blockers, continue by invoking the standalone `$rebase` skill as the source of truth for this phase:
- capture pre-rebase CI
- remove artifact files
- rebase
- resolve conflicts with a bounded conflict resolver if needed
- validate intent
- push with `--force-with-lease`
- wait for PR CI
- update the PR description with final intent, CI, history, and merge guidance
- post the required rebase comments ending in READY or BLOCKER
- refresh the issue claim status to `rebase` and then to `done` or `blocked` when the phase completes

If the rebase phase reaches `BLOCKER`, stop and report it clearly.

## Final verification

Before finishing, confirm:
- the issue was fetched from the correct repo
- the branch exists and was pushed
- the PR was created
- the PR description includes the required reviewer-facing sections and reflects the final post-review-fix and post-rebase state
- the standalone `$review-fix` flow completed and posted its summary comment if review-fix ran
- the standalone `$rebase` flow either reached `READY` or reported a clear `BLOCKER`
- any ADR pause or blocker state was made explicit to the user
- the issue claim comment was updated to its terminal state or clearly marked as abandoned when the run stopped early

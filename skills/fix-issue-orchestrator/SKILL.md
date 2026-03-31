---
name: fix-issue-orchestrator
description: "End-to-end GitHub issue implementation orchestration for Codex. Use when Codex needs to take a GitHub issue number or issue URL and drive the full issue-to-PR workflow in the current repo: fetch issue context, choose a complexity tier, create a branch, spawn sub-agents for planning and implementation, pause for ADR approval when architecture is unsettled, run review-fix, and finish with rebase and PR readiness checks. Also use for the standalone review-fix or rebase phases on an existing PR branch."
---

# Fix Issue Orchestrator

## Overview

Use this skill to run a Codex-native issue workflow instead of relying on a slash command. The skill turns a GitHub issue into a structured implementation plan, bounded sub-agent work, verification, PR creation, review-fix, and rebase readiness.

## Quick Start

Gather these inputs first:
- issue identifier: GitHub issue URL or issue number
- repo: current git repo, unless the issue URL already pins it
- optional tier override: `1`, `2`, or `3`

Normalize the request to this shape before proceeding:
- `issue`: required
- `tier`: optional override

Examples:
- "Implement issue 42 in this repo"
- "Take https://github.com/org/repo/issues/42 from issue to PR"
- "Run review-fix on the current PR branch"
- "Rebase this PR branch onto main"

## Workflow Entry Points

Choose the matching path:
- Full issue-to-PR flow: read [workflow.md](./references/workflow.md) and [agent-team-guide.md](./references/agent-team-guide.md) first.
- Standalone review-fix flow: use the dedicated `$review-fix` skill as the source of truth.
- Standalone rebase flow: use the dedicated `$rebase` skill as the source of truth.

## Operating Rules

- The main Codex run is the orchestrator. Use sub-agents only for bounded tasks.
- Run the workflow in a dedicated git worktree. Create or attach a feature-branch worktree before planning or implementation work, and treat that worktree as the execution root for the rest of the flow.
- The orchestrator does not implement product changes. All product changes, including small fixes, test edits, product documentation edits, and review-fix code changes, must be delegated to sub-agents.
- The orchestrator may inspect code, write workflow artifacts such as `ISSUE_<number>_PLAN.md`, `ISSUE_<number>_ADR.md`, PR descriptions and summaries, issue comments, and review/rebase status outputs, run git and worktree operations, review diffs, and run verification.
- Local orchestration does not permit local implementation. When the next blocking step is on the critical path, keep only orchestration, review, verification, and git or GitHub coordination local.
- Treat `review-fix` and `rebase` as continuations of the main workflow whenever it is safe to continue inline.
- The orchestrator owns final coherence. It is responsible for making sure the final branch, PR description, acceptance criteria mapping, review summary, and merge guidance tell one consistent reviewer-facing story across all worker outputs.
- Stop for human input only when repo identity is ambiguous, the working tree is dirty, ADR approval is required, or a blocker is hit.
- Do not promise completion without running the relevant verification steps.

## Preconditions

Before implementation work:
- confirm `gh` is installed and authenticated
- resolve the git root
- create or select the dedicated git worktree that will own the issue branch
- inspect branch and working tree state
- confirm the target repo if the issue identifier is only a number
- stop if the working tree is dirty, no repo can be found, or repo detection is ambiguous

## Output Expectations

For the full workflow, produce:
- `ISSUE_<number>_PLAN.md`
- `ISSUE_<number>_ADR.md` when architecture review is needed
- PR creation with a structured PR description that is kept current through implementation, review-fix, and rebase
- a dedicated post-PR documentation pass that rewrites the PR body from the final diff and issue context into a reviewer-facing narrative
- a PR body that includes these sections and their required reviewer-facing contents when applicable:
  `What changed`, `Implementation walkthrough`, `How components interact`, `Default execution path`, `Edge cases and error handling`, `Tier / approach`, `Acceptance criteria`, `Outstanding items`, `Review summary`, `History`, and `Merge instructions`
- PR body sections that include concrete file, function, class, method, and execution-path references rather than generic summaries
- review-fix summary comment when review-fix runs
- a detailed merge-ready or blocker comment plus a terminal READY or BLOCKER state after rebase

Keep this reviewer-facing PR body shape active in the main prompt, not only in reference files:
- `What changed`: root cause, scope boundary, and user-visible or developer-visible outcome
- `Implementation walkthrough`: named files and main functions, classes, methods, or modules changed, plus what each one now does
- `How components interact`: control flow or data flow across touched components, with Mermaid when multiple layers interact
- `Default execution path`: explicit before and after behavior for the happy path, especially for behavioral bug fixes
- `Edge cases and error handling`: invalid inputs, retries, fallbacks, missing config or tooling, and intentionally unchanged behavior
- `Tier / approach`: why the chosen implementation approach fits the issue scope
- `Acceptance criteria`: explicit `[x]` or `[ ]` mapping to the issue criteria
- `Outstanding items`: deferred work or an explicit `None`
- `Review summary`: cycles run, findings fixed, findings deferred, current risk level, and whether the PR is clean or what remains
- `History`: implementation, review-fix, and rebase milestones in chronological order
- `Merge instructions`: intended merge strategy and remaining human actions, if any

For standalone flows, produce the artifacts and summary states described in the reference file for that flow.

## References

- [workflow.md](./references/workflow.md): full issue-to-PR orchestration flow
- [agent-team-guide.md](./references/agent-team-guide.md): tiering and sub-agent role mapping
- [pr-guide.md](./references/pr-guide.md): PR review and push hygiene

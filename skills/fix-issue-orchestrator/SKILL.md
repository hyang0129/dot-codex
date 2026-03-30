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
- a PR body that includes these sections when applicable:
  `What changed`, `Implementation walkthrough`, `How components interact`, `Default execution path`, `Edge cases and error handling`, `Tier / approach`, `Acceptance criteria`, `Outstanding items`, `Review summary`, `History`, and `Merge instructions`
- review-fix summary comment when review-fix runs
- a detailed merge-ready or blocker comment plus a terminal READY or BLOCKER state after rebase

For standalone flows, produce the artifacts and summary states described in the reference file for that flow.

## References

- [workflow.md](./references/workflow.md): full issue-to-PR orchestration flow
- [agent-team-guide.md](./references/agent-team-guide.md): tiering and sub-agent role mapping
- [pr-guide.md](./references/pr-guide.md): PR review and push hygiene

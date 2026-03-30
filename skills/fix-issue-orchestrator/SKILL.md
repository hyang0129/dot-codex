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
- Standalone review-fix flow: read [review-fix.md](./references/review-fix.md) and [pr-guide.md](./references/pr-guide.md).
- Standalone rebase flow: read [rebase.md](./references/rebase.md) and [pr-guide.md](./references/pr-guide.md).

## Operating Rules

- The main Codex run is the orchestrator. Use sub-agents only for bounded tasks.
- Keep the critical path local when the next action immediately depends on it.
- Treat `review-fix` and `rebase` as continuations of the main workflow whenever it is safe to continue inline.
- Stop for human input only when repo identity is ambiguous, the working tree is dirty, ADR approval is required, or a blocker is hit.
- Do not promise completion without running the relevant verification steps.

## Preconditions

Before implementation work:
- confirm `gh` is installed and authenticated
- resolve the git root
- inspect branch and working tree state
- confirm the target repo if the issue identifier is only a number
- stop if the working tree is dirty, no repo can be found, or repo detection is ambiguous

## Output Expectations

For the full workflow, produce:
- `ISSUE_<number>_PLAN.md`
- `ISSUE_<number>_ADR.md` when architecture review is needed
- PR creation plus a human-readable implementation walkthrough
- review-fix summary comment when review-fix runs
- a final READY or BLOCKER state after rebase

For standalone flows, produce the artifacts and summary states described in the reference file for that flow.

## References

- [workflow.md](./references/workflow.md): full issue-to-PR orchestration flow
- [agent-team-guide.md](./references/agent-team-guide.md): tiering and sub-agent role mapping
- [review-fix.md](./references/review-fix.md): structured PR review-fix loop
- [rebase.md](./references/rebase.md): post-review-fix rebase and CI validation
- [pr-guide.md](./references/pr-guide.md): PR review and push hygiene

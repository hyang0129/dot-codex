---
name: rebase
description: "Post-review rebase orchestration for Codex. Use when Codex needs to rebase an open PR branch onto its base branch, resolve conflicts with bounded sub-agents, validate that the implementation intent survived the rebase, compare CI before and after the push, and finish in a clear READY or BLOCKER state. Trigger this skill when a user wants to rebase the current PR branch or a named PR branch."
---

# Rebase

## Overview

Use this skill to run the standalone rebase phase on an existing PR branch. It handles PR discovery, review-fix precondition checks, artifact cleanup, conflict resolution, intent review, and CI comparison after the force-push.

## Quick Start

Gather these inputs first:
- `branch`: optional, defaults to the current branch
- `base-branch`: optional, defaults to the PR base branch or `main`

Examples:
- "Use $rebase on the current PR branch"
- "Use $rebase on branch fix/issue-123-login onto main"

## Preconditions

Before doing anything else:
- read [workflow.md](./references/workflow.md)
- read [pr-guide.md](./references/pr-guide.md)
- resolve the git root
- confirm the branch has an open PR
- confirm the working tree is clean

## Operating Rules

- The main Codex run is the orchestrator.
- Require the `review-fix-summary` comment unless the user explicitly chooses to continue without it.
- Use a Conflict Resolver worker only for conflict markers.
- Use a senior review explorer to validate post-rebase intent.
- Finish in exactly `READY` or `BLOCKER`.

## Outputs

Produce these artifacts during the run:
- `REBASE_INTENT_REVIEW.md`
- `CONFLICT_RESOLUTION.md` when conflicts require a worker

Also update the PR with either a merge-ready comment or a blocker comment.

## References

- [workflow.md](./references/workflow.md): the standalone rebase flow
- [pr-guide.md](./references/pr-guide.md): PR review and push hygiene

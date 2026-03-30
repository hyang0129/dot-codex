---
name: review-fix
description: "Structured pull request review-fix orchestration for Codex. Use when Codex needs to inspect an open PR branch, generate Reviewer findings, batch and apply fixes with sub-agents, verify each fix set, produce intent validation, and post a review-fix summary comment. Trigger this skill when a user wants to run review-fix on the current PR branch or on a named PR branch."
---

# Review Fix

## Overview

Use this skill to run the standalone review-fix phase on an existing PR branch. It handles PR discovery, Reviewer and Fixer orchestration, verification, intent validation, and the final review summary comment.

## Quick Start

Gather these inputs first:
- `branch`: optional, defaults to the current branch
- `cycles`: optional, defaults to `2`

Examples:
- "Use $review-fix on the current PR branch"
- "Use $review-fix on branch fix/issue-123-login for 2 cycles"

## Preconditions

Before doing anything else:
- read [workflow.md](./references/workflow.md)
- read [pr-guide.md](./references/pr-guide.md)
- resolve the git root
- confirm the working tree is clean
- confirm the branch has an open PR

## Operating Rules

- The main Codex run is the orchestrator.
- Use a Reviewer explorer, Fixer workers, and an Intent Validator explorer for bounded subtasks.
- Commit only verified fix batches.
- Do not silently skip unresolved findings.
- Finish in `clean` or `blockers remain`.

## Outputs

Produce these artifacts during the run:
- `REVIEW_FINDINGS_<cycle>.md`
- `FIX_PLAN_<cycle>.md`
- `FIX_RESULT_<finding-id>.md`
- `INTENT_VALIDATION.md`

Also post a PR comment containing the sentinel `<!-- review-fix-summary -->`.

## References

- [workflow.md](./references/workflow.md): the standalone review-fix flow
- [pr-guide.md](./references/pr-guide.md): PR review and push hygiene

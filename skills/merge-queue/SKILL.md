---
name: merge-queue
description: "Sequential pull request merge-queue orchestration for a single GitHub repository. Use when Codex needs to process open PRs carrying a ready-to-merge label such as `approved`, merge the ones that are clean and green, invoke `$rebase` for branches that are behind the base branch, remove the queue label on blocker cases, and produce a concise run summary plus per-merge reports."
---

# Merge Queue

## Overview

Use this skill to process a labeled merge queue for one repository at a time. The skill handles queue discovery, conservative readiness checks, merge-or-rebase routing, label cleanup, and end-of-run reporting without editing application code directly.

## Quick Start

Gather these inputs first:
- `repo`: optional if it can be detected confidently from git remotes or the current PR context
- `label`: optional, defaults to `approved`

Examples:
- "Use $merge-queue in the current repo"
- "Use $merge-queue for label `approved`"
- "Use $merge-queue for `owner/repo` with label `ready-to-merge`"

## Preconditions

Before doing anything else:
- read [workflow.md](./references/workflow.md)
- resolve the git root
- detect the GitHub repo and confirm it with the user before acting
- detect the default base branch
- inspect the working tree for uncommitted changes

## Operating Rules

- Act on one repository and one PR at a time.
- Queue order is informational only. Use a stable order for reporting, but do not imply that PR number order has semantic priority unless the user or repository policy explicitly requires ordered processing.
- Never push directly to the base branch.
- Never force-push from this skill; only `$rebase` may force-push a feature branch with its own safeguards.
- Do not modify product code, resolve merge conflicts manually, or fix CI inside this skill.
- Bias toward blocking when merge safety is uncertain. False-positive blockers are acceptable; false-negative merges are not.
- Treat risky or weakly justified test changes as blockers unless a human has already approved them explicitly.
- Leave the queue label on skipped PRs so they remain eligible for a later run.
- Remove the queue label when `$rebase` ends in a blocker state so a human can intervene and re-label later.
- Return to the base branch before finishing if a local checkout was used.

## Outputs

Produce these artifacts during the run:
- a user-visible queue table before processing starts, using a stable display order only
- a per-PR result log as processing continues
- markdown reports under `merge-reports/<pr-number>.md` for each successful merge
- a final summary table with merged, blocked, and skipped counts

## References

- [workflow.md](./references/workflow.md): the detailed merge-queue procedure, routing rules, and reporting format

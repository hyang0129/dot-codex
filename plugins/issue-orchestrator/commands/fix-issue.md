---
description: Orchestrate a GitHub issue end-to-end in Codex using sub-agents, ADR review, PR creation, inline review-fix, and inline rebase.
---

# Fix Issue

## Preflight

Parse arguments as:
`/fix-issue <issue> [tier]`

- `issue`: required. GitHub issue number or full issue URL.
- `tier`: optional override: `1`, `2`, or `3`.

Examples:
- `/fix-issue 42`
- `/fix-issue 42 2`
- `/fix-issue https://github.com/org/repo/issues/42`

Before doing anything else:
- Read `~/.codex/plugins/issue-orchestrator/guides/agent-team-guide.md`.
- Confirm `gh` is installed and authenticated.
- Resolve the git root and verify the working tree is clean.
- If `issue` is only a number, detect the repo from `git remote -v` or `gh repo view --json nameWithOwner`.
- Always confirm the detected repo with the user before fetching the issue.

Stop if:
- no git repo can be found,
- `gh` is unavailable,
- the working tree is dirty,
- or the repo guess is ambiguous and the user has not confirmed it.

## Plan

Run this as a single Codex-native orchestration flow:

1. Fetch the issue and assign it if needed.
2. Assess complexity and create the feature branch.
3. Spawn a Planner sub-agent first.
4. If the plan surfaces open architecture questions, spawn an Architect sub-agent and pause for ADR approval on GitHub.
5. After approval, spawn implementation sub-agents using Codex-native roles and model choices.
6. Validate, review, commit, push, and open the PR.
7. Continue directly into the review-fix phase inside the same command run.
8. Continue directly into the rebase phase inside the same command run if review-fix finishes without blockers.

This command is the primary convenience entrypoint. Do not merely print `/review-fix` or `/rebase` as suggestions when the flow can continue inline.

## Commands

### 1. Issue fetch and repo setup

If `issue` is a full URL, extract `owner/repo` and the issue number from the URL.

If `issue` is just a number, detect the repo with:

```bash
git remote -v
gh repo view --json nameWithOwner
```

Then confirm:

```text
Repo detected: <owner/repo> (from <source>)

Proceed with issue #<number> in <owner/repo>? [yes / no / different-repo]
```

Fetch the issue:

```bash
gh issue view <number> --repo <owner/repo> --json number,title,body,labels,comments,assignees
```

If unassigned, try:

```bash
gh issue edit <number> --repo <owner/repo> --add-assignee @me
```

Resolve the git root with:

```bash
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  for candidate in /workspaces/*; do
    if [ -d "$candidate/.git" ]; then
      GIT_ROOT="$candidate"
      break
    fi
  done
}
```

Then inspect:

```bash
git -C "$GIT_ROOT" branch --show-current
git -C "$GIT_ROOT" log --oneline -10
git -C "$GIT_ROOT" status --short
```

Create the feature branch:

```bash
git -C "$GIT_ROOT" checkout -b fix/issue-<number>-<slug>
```

### 2. Tiering

Use the tier rules from `agent-team-guide.md`.

- Tier 1: one area, clear requirements, small diff.
- Tier 2: multiple areas, still clear requirements.
- Tier 3: architecture questions, shared interfaces, or substantial unknowns.

If the user passed a tier override, respect it. Otherwise explain the tier choice briefly before proceeding.

### 3. Codex sub-agent orchestration

Use Codex sub-agents explicitly:

- Planner: `spawn_agent(agent_type="explorer", model="gpt-5.4", ...)`
- Architect: `spawn_agent(agent_type="explorer", model="gpt-5.4", ...)`
- Reviewer: `spawn_agent(agent_type="explorer", model="gpt-5.4", ...)`
- Coders / Tester / Integrator: `spawn_agent(agent_type="worker", model="gpt-5.4-mini", ...)`

Coordination rules:
- The main command run is the orchestrator.
- Use `spawn_agent` for bounded subtasks only.
- Use `wait_agent` only when the next step is blocked on that result.
- While sub-agents run, continue with non-overlapping orchestration work.
- Do not spawn duplicate agents for the same unresolved task.

### 4. Planner phase

Spawn a Planner sub-agent with read-only responsibilities plus permission to write the plan file:

- Read the full issue.
- Search the repo for affected files and relevant patterns.
- Produce `ISSUE_<number>_PLAN.md` containing:
  - summary,
  - affected files,
  - file ownership table,
  - task list by wave,
  - acceptance criteria,
  - open questions.

After the Planner returns:
- read the plan,
- post a pre-implementation check comment to the issue,
- decide whether architecture review is required.

### 5. Architect and ADR gate

If Tier 2 has open architecture questions, or if the issue is Tier 3, spawn an Architect sub-agent.

Architect output:
- `ISSUE_<number>_ADR.md`
- options,
- recommendation,
- consequences,
- updated acceptance criteria.

Post the ADR back to the issue as checkbox decisions.

Pause implementation here. Do not spawn implementation workers until the user has approved the ADR on GitHub.

Poll issue comments until one of these happens:
- `APPROVED`: read the selected options, update ADR status to `ACCEPTED`, and continue.
- `REJECT`: stop and report that implementation is paused.

### 6. Implementation phase

Use the plan and approved ADR to assign sub-agents.

Tier 1:
- Spawn one Coder worker.
- Run checks.
- Spawn one Reviewer explorer.

Tier 2:
- Spawn parallel workers for independent Coder and Tester tasks.
- Wait for the whole wave.
- Run checks.
- Spawn Integrator.
- Spawn Reviewer.

Tier 3:
- Execute implementation in waves.
- Spawn all independent workers for the current wave.
- Wait for the whole wave.
- Run checks before moving to the next wave.
- After all waves, spawn Integrator and one or more Reviewers.

Every worker task spec must include:
- issue number and title,
- exact files to read,
- exact files allowed to edit,
- files explicitly out of scope,
- acceptance criteria,
- required outputs.

### 7. Validation and PR creation

Run project-appropriate checks in this order:

```bash
<compile command if applicable>
<typecheck command if applicable>
<lint command if applicable>
<test command>
```

If checks fail:
- route the failure back to the responsible worker,
- retry with bounded scope,
- do not commit broken code.

After checks pass:

```bash
git -C "$GIT_ROOT" add <only issue-scoped files>
git -C "$GIT_ROOT" commit -m "fix(#<number>): <summary>"
git -C "$GIT_ROOT" push -u origin fix/issue-<number>-<slug>
gh pr create --repo <owner/repo> --title "fix(#<number>): <title>" --body "<body>"
```

Update the PR body with a human-readable implementation walkthrough before moving on.

### 8. Inline review-fix continuation

Do not stop after creating the PR if there are no blockers.

Continue in the same command flow by reusing the review-fix logic from `review-fix.md`:
- run the initial review,
- partition findings,
- spawn Fixer workers where needed,
- commit review-fix batches,
- produce the review-fix summary comment.

Only stop here if review-fix encounters a blocker that requires human intervention.

### 9. Inline rebase continuation

If the review-fix phase completes without blockers, continue in the same command flow by reusing the rebase logic from `rebase.md`:
- capture pre-rebase CI,
- remove artifact files,
- rebase,
- resolve conflicts with a bounded conflict resolver if needed,
- validate intent,
- push with `--force-with-lease`,
- wait for PR CI,
- post READY or BLOCKER.

If the rebase phase reaches BLOCKER, stop and report it clearly.

## Verification

Before finishing, confirm:
- the issue was fetched from the correct repo,
- the branch exists and was pushed,
- the PR was created,
- the review-fix summary comment was posted if review-fix ran,
- the rebase phase either reached READY or reported a clear BLOCKER,
- any pause for ADR approval or blocker state was made explicit to the user.

## Summary

Return one of these shapes:

```md
## fix-issue complete
- **Issue**: #<number> <title>
- **Branch**: fix/issue-<number>-<slug>
- **PR**: <url>
- **Status**: READY
```

```md
## fix-issue paused
- **Issue**: #<number> <title>
- **Branch**: fix/issue-<number>-<slug>
- **PR**: <url or not created>
- **Status**: waiting for ADR approval | blocked during review-fix | blocked during rebase
```

## Next Steps

- If waiting on ADR approval, tell the user exactly which GitHub issue comment to review.
- If READY, tell the user the PR is ready for human review and merge.
- If BLOCKER, include the PR URL and the specific blocker.

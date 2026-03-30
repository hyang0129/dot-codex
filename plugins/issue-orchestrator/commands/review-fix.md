---
description: Run a Codex-native review-fix loop on an open PR branch using Reviewer, Fixer, and Intent Validator sub-agents.
---

# Review Fix

## Preflight

Parse arguments as:
`/review-fix [branch] [cycles]`

- `branch`: optional. Defaults to the current branch.
- `cycles`: optional. Defaults to `2`. Must be `>= 1`.

Before doing anything else:
- Read `~/.codex/plugins/issue-orchestrator/guides/pr-guide.md`.
- Resolve the git root.
- Confirm the working tree is clean.
- Confirm the branch has an open PR.

## Plan

Run a structured review loop using Codex sub-agents:

1. Gather PR context and existing review state.
2. Spawn a Reviewer explorer to produce findings.
3. If critical or major findings exist, partition them into fix batches.
4. Spawn Fixer workers for those batches.
5. Verify and commit each clean batch.
6. Repeat until the cycle limit is reached or no critical/major findings remain.
7. Run a final review and an Intent Validator.
8. Post the review-fix summary to the PR.

This command may be run standalone, but when `/fix-issue` calls into review-fix inline, keep the same logic rather than asking the user to rerun it manually.

## Commands

### 1. Setup and PR discovery

Resolve the git root:

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

Determine the branch:

```bash
git -C "$GIT_ROOT" branch --show-current
```

Find the associated PR:

```bash
gh pr list --head <branch> --json number,title,url,state --limit 1
gh pr view <pr-number> --json number,title,body,baseRefName,headRefName,files,additions,deletions
gh pr diff <pr-number>
```

Check whether reviews already exist:

```bash
gh pr view <pr-number> --json reviews --jq '.reviews | length'
```

### 2. Codex sub-agents

Use these roles:

- Reviewer: `spawn_agent(agent_type="explorer", model="gpt-5.4", ...)`
- Fixer: `spawn_agent(agent_type="worker", model="gpt-5.4-mini", ...)`
- Intent Validator: `spawn_agent(agent_type="explorer", model="gpt-5.4", ...)`

Use `wait_agent` only when the current fix phase is blocked on a result.

### 3. Reviewer phase

Spawn a Reviewer explorer that:
- reads the entire PR diff,
- reads the PR title and body,
- finds correctness, test, security, scope, and pattern-consistency issues,
- writes `REVIEW_FINDINGS_<cycle>.md`.

Finding format must include:
- severity,
- ID,
- file and line,
- problem,
- suggested fix,
- whether a decision is required,
- whether the fix is parallelizable,
- conflicts with other findings.

If this is the first review and the PR has no reviews yet, post the initial findings as a PR review comment before any fixes begin.

### 4. Fix planning and Fixer workers

The orchestrator must read `REVIEW_FINDINGS_<cycle>.md` and build `FIX_PLAN_<cycle>.md`.

Grouping rules:
- default to serial unless there are many truly independent findings,
- keep dependent findings serial,
- isolate human-decision findings,
- prioritize critical before major before minor.

For each actionable batch:
- spawn one Fixer worker per finding or per tightly related serial batch,
- give each Fixer exact file ownership,
- tell Fixers not to broaden scope.

Each Fixer must write `FIX_RESULT_<finding-id>.md` including:
- status,
- files changed,
- decisions made,
- impact trace for critical/major findings,
- notes.

### 5. Verification and commits

After each batch:
- re-read the touched files,
- run relevant tests/checks,
- confirm impact traces exist for critical and major findings,
- ensure fixes did not conflict.

Commit only the files touched by that verified batch:

```bash
git -C "$GIT_ROOT" add <batch files only>
git -C "$GIT_ROOT" commit -m "fix(review): address <finding ids>"
```

If a batch fails verification, do not commit it. Report it as needing manual attention.

### 6. Final review and intent validation

After all fix cycles:
- spawn a final Reviewer explorer,
- spawn an Intent Validator explorer.

The Intent Validator must compare:
- the original PR intent,
- the original diff,
- the post-fix state.

It should write `INTENT_VALIDATION.md` and classify risks as `high`, `medium`, or `low`.

### 7. PR summary output

Post a PR comment containing:
- cycle count,
- findings fixed,
- outstanding findings,
- decisions made,
- full intent validation,
- the sentinel:

```html
<!-- review-fix-summary -->
```

This sentinel is required because the rebase flow depends on it.

## Verification

Before finishing, confirm:
- every committed batch passed its checks,
- any uncommitted failing batch is called out explicitly,
- `REVIEW_FINDINGS_FINAL.md` exists,
- `INTENT_VALIDATION.md` exists,
- the PR comment containing `<!-- review-fix-summary -->` was posted.

## Summary

Return:

```md
## review-fix complete
- **Branch**: <branch>
- **PR**: <url>
- **Cycles Run**: <count>
- **Status**: clean | blockers remain
```

## Next Steps

- If blockers remain, include the PR URL and the blocked batch or intent risk.
- If clean, continue into the rebase phase when this command is running inline under `/fix-issue`.
- If run standalone and clean, tell the user they can now run `/rebase <branch>`.

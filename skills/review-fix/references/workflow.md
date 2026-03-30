# Review Fix Workflow

Use this flow on an open PR branch after the implementation phase, or as a standalone cleanup pass.

## Inputs

- `branch`: optional, defaults to the current branch
- `cycles`: optional, defaults to `2`, must be at least `1`

## Plan

Run this structured review loop:

1. Gather PR context and existing review state.
2. Spawn a Reviewer explorer to produce findings.
3. If critical or major findings exist, partition them into fix batches.
4. Spawn Fixer workers for those batches.
5. Verify and commit each clean batch.
6. Repeat until the cycle limit is reached or no critical or major findings remain.
7. Run a final review and an Intent Validator.
8. Post the review-fix summary to the PR.

## PR discovery

- determine the branch from the current branch or the input
- find the associated PR
- fetch the PR title, body, changed files, and diff
- check whether reviews already exist

## Sub-agent roles

- Reviewer: `explorer`, `gpt-5.4`
- Fixer: `worker`, `gpt-5.4-mini`
- Intent Validator: `explorer`, `gpt-5.4`

Use `wait_agent` only when the current fix phase is blocked on a result.

## Reviewer phase

Have the Reviewer:
- read the entire PR diff
- read the PR title and body
- find correctness, test, security, scope, and pattern-consistency issues
- write `REVIEW_FINDINGS_<cycle>.md`

Each finding should include:
- severity
- ID
- file and line
- problem
- suggested fix
- whether a decision is required
- whether the fix is parallelizable
- conflicts with other findings

If this is the first review and the PR has no reviews yet, post the initial findings to the PR before fixes begin.

When posting visible review artifacts, prefer a reviewer-facing format that clearly lists:
- findings by severity
- batches planned or executed
- decisions still needed
- what must happen before the PR is ready

## Fix planning and workers

The orchestrator should read `REVIEW_FINDINGS_<cycle>.md` and build `FIX_PLAN_<cycle>.md`.

Grouping rules:
- default to serial unless findings are truly independent
- keep dependent findings serial
- isolate human-decision findings
- prioritize critical before major before minor

For each actionable batch:
- spawn one Fixer worker per finding or tightly related serial batch
- give each Fixer exact file ownership
- tell Fixers not to broaden scope

Each Fixer should write `FIX_RESULT_<finding-id>.md` including:
- status
- files changed
- decisions made
- impact trace for critical and major findings
- notes

## Verification and commits

After each batch:
- re-read the touched files
- run relevant tests and checks
- confirm impact traces exist for critical and major findings
- ensure fixes did not conflict

Commit only verified batch files. If a batch fails verification, do not commit it and report it as needing manual attention.

## Final review and output

After all fix cycles:
- spawn a final Reviewer explorer
- spawn an Intent Validator explorer
- write `INTENT_VALIDATION.md`
- update the PR description so `Review summary`, `Outstanding items`, `Acceptance criteria`, `History`, and `Merge instructions` match the verified post-fix state
- ensure `Review summary` includes: cycles run, findings fixed, findings deferred, current risk level, intent validation result, and whether the PR is clean or what remains
- post a PR comment titled `Automated Review-Fix Summary` containing cycle count, findings fixed, outstanding findings, decisions made, full intent validation, a concise reviewer-facing readiness summary, and the sentinel `<!-- review-fix-summary -->`

Finish in one of these states:
- `clean`
- `blockers remain`

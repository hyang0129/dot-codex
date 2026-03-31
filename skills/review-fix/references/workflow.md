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

Bias toward high recall of merge blockers. If a finding might represent a real merge risk and the evidence is ambiguous, classify upward rather than downward.

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
- treat risky test changes as first-class review targets, not merely supporting edits
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

Severity guidance:
- use `critical` or `major` for anything that could plausibly let incorrect behavior merge, including suspicious test weakening
- when unsure between `minor` and `major` for merge safety, choose `major`

Treat these test-edit patterns as at least `major` unless there is strong evidence they are correct and intended:
- deleted or weakened assertions
- broader mocks or stubs that reduce behavioral coverage
- snapshot updates without a clear behavior explanation
- added skips, retries, or flake-suppressing logic
- changes that rewrite tests to match current buggy behavior instead of intended behavior
- removal of coverage around failure paths, permissions, edge cases, or data validation

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
- when there are fewer than 5 actionable findings in the cycle, prefer serial execution unless independence is obvious and high-confidence

For each actionable batch:
- spawn one Fixer worker per finding or tightly related serial batch
- give each Fixer exact file ownership
- tell Fixers not to broaden scope

Fixer guardrails for test changes:
- do not weaken tests just to make CI pass
- do not delete assertions, coverage, or failure-path checks unless the intended behavior changed and that change is explicitly justified
- do not update snapshots mechanically; explain the product-behavior reason for each snapshot change
- if the only apparent fix is to relax or rewrite a test oracle, stop and mark the finding as needing human review

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
- inspect any changed tests for oracle weakening, reduced coverage, or unexplained expectation drift

Commit only verified batch files. If a batch fails verification, do not commit it and report it as needing manual attention.

Do not mark the PR `clean` if risky test edits remain unresolved, even if the test suite is green.

Review-fix retry limits:
- run at most 2 fix cycles by default unless the user requested more
- if the same critical or major finding survives 2 fixer attempts without a materially different approach, stop and report it as a blocker rather than looping
- if verification fails twice for the same batch, stop retrying that batch automatically and surface it for human review

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

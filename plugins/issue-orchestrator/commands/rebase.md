---
description: Rebase a fix-issue PR branch safely after /review-fix has completed and stop in READY or BLOCKER.
---

# Rebase

## Purpose

Prepare a `fix-issue` PR branch for merge after `/review-fix` has completed.

Run this **after** `/review-fix`. It drives three specialized agents and terminates in exactly one of two states:

- **READY** â€” rebased cleanly, intent preserved, CI passing, force-pushed, PR updated
- **BLOCKER** â€” something requires human intervention; no further automated changes are made

---

## Setup

### Git root detection (dev container safe)

Before any git operation, resolve the git working tree root. This is required because
in dev containers the shell may start at `/workspaces` which is above the repo mount:

```bash
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  # Try common dev container mount points
  for candidate in /workspaces/*; do
    if [ -d "$candidate/.git" ]; then
      GIT_ROOT="$candidate"
      break
    fi
  done
}
```

If `GIT_ROOT` is still empty, stop and tell the user:
"Could not find a git repository. Make sure you are inside a repo or pass the repo path."

**All `git` commands in this spec must run from `GIT_ROOT`** â€” either `cd "$GIT_ROOT"` first,
or use `git -C "$GIT_ROOT" <command>`.

### Parse arguments

Format is: `/rebase [branch] [base-branch]`
- `branch`: optional. If omitted, use current branch.
- `base-branch`: optional. If omitted, read from PR metadata; default to `main`.

Examples:
- `/rebase` â†’ current branch, base from PR
- `/rebase fix/issue-42-foo` â†’ that branch, base from PR
- `/rebase fix/issue-42-foo develop` â†’ force base to develop

```bash
git -C "$GIT_ROOT" branch --show-current
gh pr list --head <branch> --json number,title,url,baseRefName,state --limit 1
```

If no open PR is found: stop â€” "No open PR found for branch `<branch>`. This skill requires an open PR."

Set:
- `BRANCH = <branch>`
- `PR_NUMBER = <from gh>`
- `BASE = <baseRefName from PR, or 'main'>`

Verify the working tree is clean:
```bash
git status --short
```
If uncommitted changes exist, stop and warn the user â€” do not proceed.

---

## Agent Roles

### Git Operator (orchestrator, inherits session model â€” should be GPT-5.4)

Owns the overall flow. Responsible for all git operations: squash, rebase, push, PR updates, issue comments. Spawns and sequences the other agents. Makes the final terminal-state determination. Does **not** fix application code.

### Merge Conflict Resolver (`model: "gpt-5.4-mini"`)

Activated only when `git rebase` hits conflict markers. Resolves conflict markers in the working tree. Scope is strictly limited to lines between `<<<<<<<` and `>>>>>>>`. Does **not** fix logic bugs, test failures, style issues, or anything beyond the conflict markers themselves. Reports each conflict as resolved or unresolvable.

### Senior Review Engineer (`model: "gpt-5.4"`)

Activated once after rebase completes (conflicts resolved or absent). Read-only â€” makes **no** file changes. Compares the pre-rebase diff against the post-rebase diff to verify the original fix intent is fully preserved. Reports clean or lists specific intent risks. Findings do not trigger automated fixes â€” they are either accepted by the Git Operator (trivial/cosmetic) or escalate to BLOCKER.

---

## Flow

```
Git Operator
  â”‚
  â”œâ”€ Pre-flight checks
  â”œâ”€ Inventory + remove artifact files
  â”œâ”€ git rebase origin/<BASE>
  â”‚     â”‚
  â”‚     â”œâ”€ conflicts? â”€â”€â–º Merge Conflict Resolver
  â”‚     â”‚                   â””â”€ unresolvable? â”€â”€â–º BLOCKER
  â”‚     â”‚
  â”‚     â””â”€ clean
  â”‚
  â”œâ”€ Senior Review Engineer (read-only)
  â”‚     â””â”€ intent risks found? â”€â”€â–º BLOCKER
  â”‚
  â”œâ”€ Local sanity checks (compile/lint â€” no tests)
  â”‚     â””â”€ failing? â”€â”€â–º BLOCKER
  â”‚
  â”œâ”€ force-push --force-with-lease
  â”‚
  â”œâ”€ Wait for PR CI checks to complete (gh pr checks --watch)
  â”‚     â””â”€ new failure vs pre-rebase baseline? â”€â”€â–º BLOCKER
  â”‚
  â””â”€ update PR, post comment â”€â”€â–º READY
```

---

## Step 1 â€” Pre-flight (Git Operator)

### Check `/review-fix` completeness

Locate the review-fix summary posted to the PR by `/review-fix`. It is identified by the
`<!-- review-fix-summary -->` sentinel in a PR comment body.

```bash
gh pr view <PR_NUMBER> --json comments --jq '
  .comments[]
  | select(.body | contains("<!-- review-fix-summary -->"))
  | .body'
```

**If no matching comment is found:**
Warn the user â€” "No `/review-fix` summary found on PR #<PR_NUMBER>. Consider running
`/review-fix` before rebasing. Continue anyway? [yes/no]"
Wait for user reply. If no, stop.

**If the comment is found**, parse it for the following signals:

1. **Critical or major findings remaining** â€” look for non-zero counts in the
   "Final review state" table or entries in "Outstanding findings" with severity
   `critical` or `major`.
   If found: warn â€” "Unresolved critical/major findings in the review-fix summary.
   Continue anyway? [yes/no]" Wait for user reply. If no, stop.

2. **Intent validation risks** â€” look for `high` risk entries under "Intent validation".
   If found: warn â€” "High intent risks flagged in the review-fix summary.
   Continue anyway? [yes/no]" Wait for user reply. If no, stop.

3. **Overall status** â€” extract for use in the final PR comment and READY/BLOCKER output.

Store the full comment body as `REVIEW_FIX_SUMMARY` for reference in Step 8 and
Terminal States output.

### Capture pre-rebase CI baseline from the PR

```bash
gh pr checks <PR_NUMBER> --json name,status,conclusion
```

Note which checks are currently failing or pending. This is the baseline â€” after the
force push, any check that was already failing before the rebase is not a rebase
regression. Store results as `PRE_REBASE_CI`.

If the command returns no checks at all, the PR may not have CI configured yet (e.g.
the branch was just pushed). That is acceptable â€” record `PRE_REBASE_CI = none` and
proceed. CI will be evaluated after the force push in Step 7b.

---

## Step 2 â€” Inventory + Remove Artifacts (Git Operator)

### List artifact files

```bash
git diff <BASE>...HEAD --name-only
```

Identify files matching these patterns â€” they are planning/review artifacts that must not land on the base branch:
- `ISSUE_*_PLAN.md`, `ISSUE_*_ADR.md`, `ISSUE_*_REVIEW.md`
- `REVIEW_FINDINGS*.md`, `FIX_PLAN*.md`, `FIX_RESULT_*.md`
- `INTENT_VALIDATION.md`, `REBASE_INTENT_REVIEW.md`, `CONFLICT_RESOLUTION.md`

### Present inventory to the user

```
## Rebase preparation: <BRANCH> â†’ <BASE>

### Commits on branch (<N> total)
  abc1234  fix(#42): implement feature X
  def5678  fix(#42): add tests
  111aaaa  fix(review): address F-1-1, F-1-2
  222bbbb  fix(review): address F-2-1

### Artifact files to remove (<N>)
  ISSUE_42_PLAN.md
  REVIEW_FINDINGS_1.md
  FIX_RESULT_F-1-1.md
  INTENT_VALIDATION.md
  ...

Proceeding â€” no user input required.
```

Branch will be squash-merged â€” individual commit history is discarded at merge time.

### Remove artifact files

```bash
git rm <artifact-file> [...]
```

If any artifact was never git-tracked, delete it from disk only.

Commit the removals:
```bash
git add -u
git commit -m "chore: remove fix-issue planning artifacts"
```

---

## Step 3 â€” Rebase (Git Operator)

```bash
git fetch origin
git rebase origin/<BASE>
```

If the rebase exits cleanly (no conflicts): proceed directly to Step 4.

If conflicts are reported: pause all other work and spawn the **Merge Conflict Resolver**.

---

## Merge Conflict Resolver â€” Instructions

**Scope**: conflict markers only. Do not touch any line that is not inside a conflict block.

For each conflicted file:

1. Read the file. Locate every block delimited by `<<<<<<<`, `=======`, `>>>>>>>`.

2. For each block:
   - `ours` (between `<<<<<<<` and `=======`) = the fix-branch version
   - `theirs` (between `=======` and `>>>>>>>`) = the base branch version
   - Default rule: **preserve the fix-branch intent**. When in doubt, keep `ours`.
   - If both sides changed genuinely independent lines (e.g. a function the base moved and a different function the fix changed), produce a merge that includes both.
   - If the same logic was changed on both sides and the changes are semantically incompatible, **do not guess** â€” mark as unresolvable.

3. After resolving a file: `git add <file>`

4. For each conflict report:
   ```
   ### Resolved: <filename>
   **Block**: line <N>â€“<M>
   **Ours**: <quoted lines>
   **Theirs**: <quoted lines>
   **Resolution**: kept ours / merged both / [explanation]

   ### Unresolvable: <filename>
   **Block**: line <N>â€“<M>
   **Ours**: <quoted lines>
   **Theirs**: <quoted lines>
   **Why unresolvable**: <explanation of incompatibility>
   ```

5. Output `CONFLICT_RESOLUTION.md` with all findings.

6. If all conflicts resolved: `git rebase --continue`
   If any unresolvable: `git rebase --abort` and return UNRESOLVABLE status to Git Operator.

**Do not** fix logic bugs discovered while reading. **Do not** improve code noticed along the way. **Do not** modify test files. Conflict markers only.

---

### Git Operator: handle Conflict Resolver result

- **All resolved**: read `CONFLICT_RESOLUTION.md`, confirm no unresolvable entries, proceed to Step 4.
- **Any unresolvable**: â†’ **BLOCKER** (see Terminal States).

---

## Step 4 â€” Intent Validation (Senior Review Engineer)

Spawn the **Senior Review Engineer** after the rebase is clean.

### Senior Review Engineer â€” Instructions

**Role**: Read-only. Make no file changes.

**Goal**: Verify the rebase + squash did not accidentally drop, invert, or neutralise any part of the original fix.

1. Fetch the PR's original intent:
   ```bash
   gh pr view <PR_NUMBER> --json title,body,number
   gh issue view <issue-number> --json title,body,comments
   ```
   Extract: what bug/feature was being addressed, what invariants the fix established.

2. Reconstruct the pre-rebase diff. Use the commit inventory from Step 2 to identify which commits were authored by fix-issue:
   ```bash
   # pre-rebase state: what the implementation commits actually changed
   git show <impl-commit-sha> --stat --patch
   ```
   If strategy A was used, the pre-rebase content is available in the reflog:
   ```bash
   git reflog | head -20
   git diff <pre-squash-sha>...HEAD
   ```

3. Compare pre-rebase vs post-rebase diff for every file in the PR:
   ```bash
   git diff origin/<BASE>...HEAD
   ```

4. Check explicitly for these failure patterns:
   - **Ordering reversals**: statements reordered by squash/rebase that change runtime behaviour
   - **Guard removal**: a defensive check added by the fix is no longer present
   - **Logic inversion**: a condition's polarity flipped
   - **Dead code path**: the fix's code path is now unreachable
   - **Config neutralisation**: a value set by the fix was overwritten

5. For each concern:
   ```
   ### [INTENT-RISK: high|medium|low] <short title>
   **File**: path/to/file:line
   **Original intent**: what the fix was establishing here
   **Pre-rebase**: <quoted lines>
   **Post-rebase**: <quoted lines>
   **Risk**: why this may undermine the fix
   **Recommended action**: revert automated change | manual review needed
   ```

6. If no concerns: output `No intent risks detected.`

7. Write `REBASE_INTENT_REVIEW.md`.

---

### Git Operator: handle Senior Review Engineer result

Read `REBASE_INTENT_REVIEW.md`.

- **No findings / low-risk only**: accept and proceed to Step 5. Note low-risk findings in the PR comment.
- **Medium-risk findings**: present to the user with recommended actions. Wait for user reply â€” user may accept or declare BLOCKER.
- **Any high-risk finding**: â†’ **BLOCKER** (see Terminal States).

---

## Step 5 â€” Local Sanity Checks (Git Operator)

Run any fast local checks to catch obvious breaks before wasting a CI run:

```bash
<compile command if applicable>
<typecheck command if applicable>
<lint command if applicable>
```

Do **not** run the full test suite here â€” that is the job of Step 7b (PR CI).

**Rules**:
- If local checks pass (or no local toolchain is configured): proceed to Step 7.
- If local checks fail: â†’ **BLOCKER**. Do not push broken code.
- **Do not modify any source files to fix failures.**
- **Do not modify any test files under any circumstances.**
- The Merge Conflict Resolver's scope ended at Step 4. No agent fixes code after rebase.

---

## Step 7 â€” Force Push (Git Operator)

Local checks pass and intent is validated. Push now so CI can run on the PR.

### Force push

```bash
git push --force-with-lease origin <BRANCH>
```

Rules:
- Always `--force-with-lease`, never bare `--force`.
- Never push to `main`, `master`, or any protected branch.
- If `--force-with-lease` fails (someone else pushed): fetch, re-examine, report to user before retrying.

---

## Step 7b â€” Wait for PR CI (Git Operator)

After the force push, GitHub Actions (or other CI) will re-run checks against the new
commit. Poll until all checks reach a terminal state:

```bash
# Poll every 30 seconds, up to 20 minutes
gh pr checks <PR_NUMBER> --watch
```

If `gh pr checks --watch` is unavailable, poll manually:
```bash
gh pr checks <PR_NUMBER> --json name,status,conclusion
```
Repeat until all entries show `status: completed`. Wait up to 20 minutes total.
If checks have not completed after 20 minutes, stop and report to the user â€”
do not proceed to READY while checks are still pending.

**Evaluate results** once all checks complete:

For each check, compare against `PRE_REBASE_CI` captured in Step 1:

| Scenario | Action |
|---|---|
| Check was passing before and is passing now | OK |
| Check was failing before and is still failing | Pre-existing failure â€” note it, do not block |
| Check was passing before and is now failing | **Rebase regression â†’ BLOCKER** |
| Check was absent before (new check triggered by push) and passes | OK |
| Check was absent before and fails | Treat as rebase regression â†’ **BLOCKER** |

If any **BLOCKER** condition is found:
- Do **not** update the PR description or post the merge-ready comment.
- Proceed directly to the BLOCKER terminal state.
- Report the failing check name, its log URL, and whether it was passing before the rebase.
- **Do not modify any source files or test files.**

If all checks pass (or only pre-existing failures remain): proceed to Step 8.

---

### Update PR description

```bash
gh pr view <PR_NUMBER> --json body --jq '.body'
```

Rewrite, preserving the original "What changed" and "Tier / approach" sections:

```bash
gh pr edit <PR_NUMBER> --body "$(cat <<'EOF'
Closes #<number>

## What changed
<preserved from original PR description>

## Tier / approach
<preserved from original PR description>

## Acceptance criteria
<from ISSUE_<number>_PLAN.md â€” all checked if final review was clean>
- [x] <criterion>
- [x] <criterion>

## Review summary
- Cycles run: <N>
- Findings fixed: <total>
- Intent validation: clean / <N> low-risk notes
- Outstanding: <deferred minor findings, or "None">

## History
Squash: <A: single commit | B: impl + review-fix | C: kept as-is>
Rebased onto `<BASE>` â€” PR CI passing.

## Merge instructions
Merge via **squash merge** (not merge commit or rebase merge).

ðŸ¤– Generated with Codex
EOF
)"
```

### Post merge-ready comment

```bash
gh pr comment <PR_NUMBER> --body "$(cat <<'EOF'
## Ready for merge

Branch `<BRANCH>` has been rebased onto `<BASE>`.

**Squash strategy**: <description>
**Conflicts**: <N resolved, or "none">
**Intent validation**: <clean | N low-risk notes â€” see REBASE_INTENT_REVIEW.md>
**PR CI**: all checks passing

Merge via **squash merge** when ready. No further automated changes will be made to this branch.
EOF
)"
```

---

## Terminal States

### READY

Reached when: rebase clean, no unresolved conflicts, intent validated, CI passing, force-pushed.

```bash
gh pr comment <PR_NUMBER> --body "$(cat <<'EOF'
## READY â€” terminal state reached

All automated rebase steps completed successfully. This PR requires no further automated work.

Next step: human approval, then merge via **squash merge**.
EOF
)"
```

Present final summary to user:

```
## rebase complete â€” READY

Branch:   <BRANCH>
Base:     <BASE>
Squash:   <A / B / C>
Commits:  <N before> â†’ <N after>
Artifacts removed: <N files>
Conflicts resolved: <N, or "none">
Intent validation: <clean / N low-risk notes>
PR CI: all checks passing
Push: force-with-lease âœ“

PR: <url>
Status: READY â€” awaiting human review, then squash merge
```

---

### BLOCKER

Reached when any of the following occur:
- Unresolvable merge conflict (Conflict Resolver returned UNRESOLVABLE)
- High-risk intent finding (Senior Review Engineer)
- New test/CI failure after rebase (Step 6)
- User declined to proceed at any confirmation prompt

**Immediately abort further automated steps.**

Do not push. Do not modify any files beyond what has already been staged/committed.

Post a blocker comment to the PR:

```bash
gh pr comment <PR_NUMBER> --body "$(cat <<'EOF'
## BLOCKER â€” human intervention required

Automated rebase could not complete. No push has been made.

**Reason**: <one of the below>

### Unresolvable conflict
File: <file>
Block: lines <N>â€“<M>
Ours:   <quoted>
Theirs: <quoted>
Why: <explanation>

### Intent risk (high)
<paste finding from REBASE_INTENT_REVIEW.md>

### CI regression after rebase
Failed check: <name>
Error output:
```
<error>
```
Note: test files were not modified. This regression requires human investigation.

---

Branch is at: <current SHA â€” safe to inspect>
To continue: resolve the blocker manually, then re-run `/rebase`.
EOF
)"
```

Present to user:

```
## rebase terminated â€” BLOCKER

Branch: <BRANCH> (not pushed)
Reason: <unresolvable conflict | intent risk | CI regression>

Details:
<paste the relevant section from the blocker comment above>

Action required: resolve manually, then re-run `/rebase`.
```

---

## Constraints (all agents)

- Follow `~/.codex/plugins/issue-orchestrator/guides/pr-guide.md` for all PR and commit interactions.
- **Never push to main, master, or any protected branch.**
- **Always use `--force-with-lease`**, never bare `--force`.
- **Never merge** â€” only prepare for merge.
- **Never modify test files** â€” under any circumstances, in any agent.
- **Merge Conflict Resolver scope**: conflict markers only. No other code changes.
- **Senior Review Engineer**: read-only. No file changes.
- **Git Operator**: git operations and PR metadata only. No application code fixes.
- If any agent is uncertain whether a change is within scope, the answer is no â€” stop and report to the Git Operator, which escalates to BLOCKER if needed.
- One terminal state per run. Once BLOCKER or READY is declared, no further automated changes are made.
- When handing off to a human (blockers, errors, confirmation prompts), always include the PR URL so the user can navigate to it directly.

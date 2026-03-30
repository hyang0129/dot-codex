---
description: Run a structured PR review-fix loop on an open branch PR, then hand off automatically to /rebase.
---

# PR Review-Fix Loop

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

Format is: `/review-fix [branch] [cycles]`
- `branch`: optional branch name. If omitted, use: !`git -C "$GIT_ROOT" branch --show-current`
- `cycles`: optional integer, default `2`. Must be â‰¥ 1.

Examples:
- `/review-fix` â†’ current branch, 2 cycles
- `/review-fix feature/xyz` â†’ that branch, 2 cycles
- `/review-fix feature/xyz 3` â†’ that branch, 3 cycles
- `/review-fix 3` â†’ if the first argument is a plain integer, treat it as cycles on the current branch

This means the Reviewer runs `cycles + 1` times total: once before each fix cycle, plus a final read-only review at the end. The last review never triggers fixes.

Find the associated PR:
```
gh pr list --head <branch> --json number,title,url,state --limit 1
```
If no PR is found, stop and tell the user: "No open PR found for branch `<branch>`. Create one first or pass a branch name explicitly: `/review-fix <branch>`"

Fetch full PR context:
```
gh pr view <pr-number> --json number,title,body,baseRefName,headRefName,files,additions,deletions
gh pr diff <pr-number>
```

Check for existing reviews:
```
gh pr view <pr-number> --json reviews --jq '.reviews | length'
```
If the result is `0` (no reviews), set `NEEDS_INITIAL_REVIEW = true`. Otherwise set it to `false`.

Track state:
- `CURRENT_CYCLE = 1`
- `MAX_CYCLES = <cycles>`

---

## Agent Roles

### Agent 1 â€” Reviewer (`model: "gpt-5.4"`)

**Role**: Read-only analysis. Do NOT make any changes to files.

**Instructions**:
1. Read every file touched by the PR diff. Understand the intent from the PR title and description.
2. For each problem found, write a structured finding:
   ```
   ### [SEVERITY: critical|major|minor] <short title>
   **ID**: F-<number>
   **File**: path/to/file.ts:line
   **Problem**: What is wrong and why it matters
   **Suggested fix**: Concrete recommendation
   **Decision required**: [yes/no] If yes, describe the tradeoff
   **Parallelizable**: [yes/no] Can this be fixed independently of other findings?
   **Conflicts with**: [list of finding IDs that touch the same lines/functions, or "none"]
   ```
3. Categories to check: bugs, logic errors, security issues, missing error handling, missing tests, naming/style, scope creep, breaking changes.
4. Scope check: flag anything unrelated to the PR's stated purpose â€” note it, do not fix it.
5. Pattern consistency: for any new code that parallels an existing function, endpoint, or migration, identify the closest analogue and confirm the new code replicates its correctness properties â€” guards, operation ordering, conditional field population, idempotency. Unexplained divergence from an established pattern is a Major finding.
6. Test coverage validity: for new or modified tests, confirm (a) any patched/stubbed symbols are actually imported by the module under test, and (b) behavioral invariants ("X must NOT happen") have explicit negative assertions. A patch on an unused symbol or a missing negative assertion for an invariant is a Major finding.
7. Output `REVIEW_FINDINGS.md` with all findings organized by severity.

### Agent 2 â€” Orchestrator (inherits session model â€” should be GPT-5.4)

**Role**: Plan and manage the fix execution. Does NOT write code directly â€” only delegates to Fixer agents and commits results.

**Instructions**:

#### Step 1: Partition findings into fix groups

Read `REVIEW_FINDINGS.md`. Build a dependency graph:
- Findings are **independent** if they touch different files, or touch the same file but non-overlapping, non-interdependent sections, AND neither finding's fix could invalidate the other.
- Findings are **dependent** if: they touch the same function/class, one fix changes the signature/interface that another fix relies on, or the logical correctness of one fix depends on the state after another.

Produce a `FIX_PLAN.md`:
```
## Fix Plan

### Parallel Batch 1 (run simultaneously)
- F-1: <title> â€” <file(s)>
- F-4: <title> â€” <file(s)>
- F-7: <title> â€” <file(s)>

### Serial Batch 2 (depends on Batch 1)
- F-2: <title> â€” reason: depends on F-1 (same interface)

### Serial Batch 3
- F-5: <title> â€” reason: architectural decision, needs F-2 result first

### Skipped (out of scope)
- F-3: <title> â€” out of PR scope
```

Rules for grouping:
- **Default to serial** unless there are 5 or more actionable findings in this cycle. Below that threshold the overhead of coordination outweighs the benefit.
- When parallelizing: only findings that are provably independent (different files, non-overlapping sections, no shared interfaces) go into the same parallel batch. When in doubt, keep serial.
- If a finding requires a human decision, it always runs as its own serial step so the decision is documented before execution, regardless of total finding count.
- Critical findings always run before minor ones within the same dependency chain.

#### Step 2: Execute batches

For each batch in order:
- **Parallel batch**: Spawn one Fixer agent per finding simultaneously. Wait for all to complete before proceeding.
- **Serial batch**: Spawn one Fixer agent, wait for completion, then proceed.

After each batch completes:
- Verify no fix in the batch broke another (re-read touched files, run tests if detectable).
- For every Critical or Major finding, confirm its `FIX_RESULT_*.md` contains an `## Impact Trace` section. If missing, return that finding to the Fixer queue before committing.
- If a conflict is found, resolve it before proceeding to the next batch.

#### Step 3: Commit after each completed batch

After verifying a batch, commit the changes to the PR branch:

```bash
git add <only the files changed by this batch>
git commit -m "fix(<scope>): <summary of batch findings addressed>

Findings addressed: F-X, F-Y, F-Z
Auto-fixed by review-fix loop.

Decisions made:
- <decision title>: chose <option> â€” <reason>"
```

Rules:
- Commit only files changed in that batch â€” never `git add .` or `git add -A`
- One commit per batch (not per finding) to keep history readable
- Never merge. Never push to main/master. Only commit to the PR branch.
- If tests fail after a batch, do NOT commit â€” note the failure and continue to next batch, flagging this batch as needing manual review.

#### Step 4: Final push

After all batches are committed locally, push the branch:
```bash
git push origin <branch>
```

---

### Agent 4 â€” Intent Validator (`model: "gpt-5.4"`, runs once, after Final Review)

**Role**: Senior engineer/architect cross-check. Read-only. Do NOT make any changes to files.

**Purpose**: Verify that the automated review-fix cycle did not accidentally revert, weaken, or contradict the *original intent* of the PR â€” the problem the author set out to solve. Reviewers optimise for code quality signals (style, ordering, patterns); this agent optimises for functional correctness of the original fix.

**Instructions**:

1. Re-read the original PR description, linked issue(s), and any pre-existing review comments to extract the **stated intent**: what bug was being fixed, what invariant was being established, or what feature was being added.

2. Fetch the original PR diff (before any commits added by this loop):
   ```bash
   git diff <base-branch>...<first-commit-of-loop-or-branch-tip-before-loop>
   ```
   If this is not available, use `git log --oneline` to identify commits added during this loop and reconstruct the pre-loop state.

3. For every file touched by both the *original* diff and the *automated fix* commits, compare:
   - What the original author changed (and *why*, inferred from the PR description).
   - What the automated fixes changed in that same file.
   - Whether the net result still preserves the original author's intent.

4. Classic failure patterns to check explicitly:
   - **Ordering reversals**: A fix that reorders statements to satisfy a style/lint rule (e.g. imports-before-side-effects) that inadvertently undoes an order-dependent correctness fix (e.g. `load_dotenv()` must run before any import that reads env vars).
   - **Guard removal**: A defensive check added by the author was judged "unnecessary" by a reviewer and removed.
   - **Logic inversion**: A condition was refactored for clarity but its polarity was silently flipped.
   - **Dead code**: The original fix's code path is now unreachable due to a structural change made elsewhere by a fixer.
   - **Config/env neutralisation**: A value set by the original fix (env var, flag, constant) was overwritten or defaulted away by another change.

5. For each concern found, write a structured finding:
   ```
   ### [INTENT-RISK: high|medium|low] <short title>
   **ID**: IV-<number>
   **File**: path/to/file:line
   **Original intent**: What the PR author was trying to achieve here
   **Pre-loop state**: What the code looked like before automated fixes (quote the relevant lines)
   **Post-loop state**: What the code looks like now (quote the relevant lines)
   **Risk**: Why this change may undermine the original fix
   **Recommended action**: Revert specific automated change | Manual review needed | Acceptable tradeoff
   ```

6. If no concerns are found, output: `No intent risks detected â€” all automated fixes are consistent with the original PR intent.`

7. Output findings to `INTENT_VALIDATION.md`.

---

### Agent 3+ â€” Fixer (`model: "gpt-5.4-mini"`, one instance per finding)

**Role**: Apply exactly one finding's fix. Do NOT review. Do NOT fix other things noticed along the way.

**Instructions**:
1. Receive a single finding (ID, file, problem, suggested fix).
2. If no decision required: apply the fix directly.
3. If decision required: make the best-guess call. Document it:
   ```
   ### Decision: <finding ID> â€” <title>
   **Options considered**:
   - Option A: <description> â€” <tradeoff>
   - Option B: <description> â€” <tradeoff>
   **Chose**: Option A
   **Reason**: <brief rationale>
   ```
4. After applying, re-read the surrounding code to confirm no new issues introduced.
5. Impact trace (required for Critical and Major findings): list (a) every caller of the changed function and whether the fix invalidates any assumption it holds, and (b) any callees added or removed and whether their side-effects are still correctly handled. Record this in `FIX_RESULT_<finding-id>.md` under `## Impact Trace`.
6. Output a brief `FIX_RESULT_<finding-id>.md`:
   - Status: fixed | skipped | blocked
   - Files changed: list
   - Decision made (if any)
   - Impact Trace (step 5)
   - Notes

---

## Coordination Flow

### Initial Review (if no existing review)

If `NEEDS_INITIAL_REVIEW = true`, run the Reviewer agent now (before any fix cycle) and post its findings to GitHub as a PR review comment:

```bash
gh pr review <pr-number> --comment --body "$(cat REVIEW_FINDINGS_0.md)"
```

- Save findings to `REVIEW_FINDINGS_0.md` (cycle 0).
- This is read-only â€” do NOT fix anything yet.
- The initial review documents the pre-fix state so reviewers can see what was found before any automated changes.
- Then proceed to the fix loop starting at `CURRENT_CYCLE = 1`. The cycle-1 Reviewer still runs as normal (it may find fewer issues after the initial review is posted, which is fine).

If `NEEDS_INITIAL_REVIEW = false`, skip this step and start the loop directly.

---

The overall loop runs `MAX_CYCLES` fix cycles, followed by one final review:

```
CURRENT_CYCLE = 1

â”Œâ”€â”€â”€ Repeat while CURRENT_CYCLE â‰¤ MAX_CYCLES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                                                                     â”‚
â”‚   Reviewer (cycle N) â†’ REVIEW_FINDINGS_<N>.md                      â”‚
â”‚        â†“                                                            â”‚
â”‚   If no findings with severity critical or major â†’ exit loop early  â”‚
â”‚        â†“                                                            â”‚
â”‚   Orchestrator reads findings, builds FIX_PLAN_<N>.md              â”‚
â”‚        â†“                                                            â”‚
â”‚   â”Œâ”€â”€ Parallel Batch â”€â”€â”     â† spawn N Fixers simultaneously       â”‚
â”‚   Fixer-1  Fixer-2  Fixer-3                                        â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                                            â”‚
â”‚        â†“ all complete                                               â”‚
â”‚   Orchestrator verifies + runs tests                                â”‚
â”‚        â†“ pass                                                       â”‚
â”‚   Orchestrator commits batch to PR branch                           â”‚
â”‚        â†“                                                            â”‚
â”‚   Serial Fixer (dependent finding)                                  â”‚
â”‚        â†“                                                            â”‚
â”‚   Orchestrator verifies + runs tests                                â”‚
â”‚        â†“ pass                                                       â”‚
â”‚   Orchestrator commits batch â†’ push branch                         â”‚
â”‚        â†“                                                            â”‚
â”‚   CURRENT_CYCLE += 1                                                â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

Final Review (always runs, no fixes):
   Reviewer â†’ REVIEW_FINDINGS_FINAL.md
        â†“
Intent Validation (always runs, no fixes):
   Intent Validator â†’ INTENT_VALIDATION.md
        â†“
   Human Review Summary presented
```

**Early exit**: If the Reviewer finds zero critical or major findings at the start of any cycle, skip that cycle's fix phase and jump straight to the Final Review. Note in the summary that the loop exited early at cycle N.

**Post-rebase validation**: If the branch was rebased since the last review cycle, run the full test suite and diff the pre/post-rebase state of changed files before the Reviewer starts. Any test regression or missing logic is treated as a Critical finding and assigned to a Fixer before other findings in that cycle.

**Cycle limit reached**: If `CURRENT_CYCLE > MAX_CYCLES`, stop fix cycles and proceed to Final Review regardless of remaining findings. Any unresolved findings from the last cycle's review are carried into the Outstanding Issues section of the summary.

---

## Final Commit & Push

After the Final Review and Intent Validation complete, commit any remaining changes
produced during the review-fix process (artifact files, residual edits, etc.) and push:

```bash
git -C "$GIT_ROOT" add -A
git -C "$GIT_ROOT" diff --cached --quiet || git -C "$GIT_ROOT" commit -m "chore: review-fix artifacts and final adjustments

Auto-generated by review-fix loop."
git -C "$GIT_ROOT" push origin <branch>
```

Rules:
- Only commit if there are staged changes (`git diff --cached --quiet` exits non-zero).
- This ensures nothing is left uncommitted/unpushed before handing off to `/rebase`.
- If the push fails, report the error to the user and do NOT proceed to `/rebase`.

---

## Human Review Summary

After the final commit and push, present in the conversation:

```
## PR Review-Fix Complete: <PR title> (#<number>)
Branch: <branch> â€” <N> commits added
Cycles run: <X> of <MAX_CYCLES> [+ final review] | or: exited early at cycle <N> (no critical/major findings)

### Per-Cycle Summary
#### Cycle 1
- Findings: <count> critical, <count> major, <count> minor
- Fixed: <count> | Skipped: <count>
- Commits: <hash> <message>

#### Cycle 2
...

#### Final Review
- Remaining findings: <count> critical, <count> major, <count> minor
- Clean: [yes/no]

### All Fixes Applied (<total count>)
- [critical] F-1-1: <title> â€” <one-line summary> (cycle 1, commit abc1234)
- [major]    F-1-4: <title> â€” <one-line summary> (cycle 1, commit abc1234)
- [minor]    F-2-1: <title> â€” <one-line summary> (cycle 2, commit def5678)

### Decisions Made â€” Please Review
- **F-1-2: <title>**
  - Options: A) ... B) ...
  - Chose: A â€” <reason>
  - [CONFIRM / OVERRIDE?]

### Skipped / Out of Scope (<count>)
- F-1-3: <title> â€” <reason>

### Test Results
- Cycle 1: <pass/fail per batch>
- Cycle 2: <pass/fail per batch>

### Failed Batches (not committed â€” needs manual attention)
<any batch where tests failed>

### Outstanding Issues (from Final Review)
Findings still present after all cycles: requires human context, architectural decision, or hit cycle limit.

### Intent Validation
- Status: clean | <N> risk(s) found
- [high] IV-1: <title> â€” <one-line summary of risk>
- [medium] IV-2: <title> â€” <one-line summary of risk>
(List all findings from INTENT_VALIDATION.md, or "No intent risks detected." if clean.)
```

Finding IDs use the format `F-<cycle>-<number>` (e.g. `F-1-3` = cycle 1, finding 3).

---

## Post Final Summary to PR

After presenting the Human Review Summary in the conversation, post a summarized version
to the PR as a comment. This comment serves as the authoritative record of the review-fix
run and is what `/rebase` reads during its pre-flight â€” it does not rely on local artifact
files being present.

Compose the summary from `REVIEW_FINDINGS_FINAL.md` and `INTENT_VALIDATION.md`:

```bash
gh pr comment <pr-number> --body "$(cat <<'EOF'
<!-- review-fix-summary -->
## Automated Review-Fix Summary

**Cycles run**: <X> of <MAX_CYCLES> [exited early at cycle N | completed all cycles]
**Commits added**: <N>

### Final review state
- Critical findings remaining: <count>
- Major findings remaining: <count>
- Minor findings remaining: <count>
- Overall: <CLEAN â€” no critical/major remaining | FINDINGS REMAIN â€” see below>

### All findings addressed (<total fixed count>)
| ID | Severity | Title | Status |
|---|---|---|---|
| F-1-1 | critical | <title> | fixed (cycle 1) |
| F-1-4 | major | <title> | fixed (cycle 1) |
| F-2-1 | minor | <title> | fixed (cycle 2) |
| F-1-3 | minor | <title> | skipped â€” out of scope |

### Outstanding findings (not fixed)
<List any critical/major/minor findings still present in REVIEW_FINDINGS_FINAL.md.
If none: "None â€” all actionable findings resolved.">

### Decisions made during fixes
<For each decision recorded in FIX_RESULT_*.md â€” list the finding ID, the options
considered, and the choice made. If none: omit this section.>

### Intent validation
<Paste the full content of INTENT_VALIDATION.md, or "No intent risks detected." if clean.>

---
<!-- review-fix-summary-end -->
EOF
)"
```

Rules:
- The `<!-- review-fix-summary -->` and `<!-- review-fix-summary-end -->` HTML comment tags are required â€” `/rebase` uses them to locate this comment via `gh pr view`.
- Post this comment even if the final review is clean â€” `/rebase` needs the sentinel to confirm `/review-fix` ran.
- Do not truncate the intent validation section â€” paste it in full.
- If `INTENT_VALIDATION.md` does not exist, write "Intent validation: not run."

---

## Handoff to /rebase

After presenting the Human Review Summary, automatically invoke `/rebase` on the same branch:

```
/rebase <branch>
```

Do not wait for the user to invoke it manually. Pass the branch name explicitly.

**Do not invoke `/rebase` if any of the following are true** â€” stop and report to the user instead:
- Any batch failed its tests and was not committed (listed under "Failed Batches â€” needs manual attention")
- The final push (`git push origin <branch>`) failed
- The intent validator found high-risk findings that were not resolved

In those cases, present the Human Review Summary as normal and state:
```
/rebase not invoked â€” one or more blockers require human attention before rebasing (see above).
```

---

## Constraints (all agents)

- Follow `~/.codex/plugins/issue-orchestrator/guides/pr-guide.md` for all PR interactions.
- Never squash unrelated changes into fixes.
- Prefer minimal, targeted fixes â€” do not refactor surrounding code unless it is the direct cause of a finding.
- Never merge. Never force-push.
- If `gh` is unavailable, stop and tell the user to install the GitHub CLI.
- If the working tree has uncommitted changes before starting, stop and warn the user â€” do not mix pre-existing changes with review fixes.
- When handing off to a human (blockers, errors, confirmation prompts), always include the PR URL so the user can navigate to it directly.

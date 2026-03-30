# Agent Team Guide for GitHub Issues

## Overview

This guide defines how to structure and run an agent team to implement a GitHub issue.
Always produce exactly **one PR per session**. Work one issue at a time unless issues are
tightly coupled (shared files, sequential dependencies), in which case they may be batched
into one PR with explicit justification.

---

## Step 0 â€” Before Spawning Any Agent

Read the issue fully. Collect:
- Linked issues and PRs for context
- Affected files (grep, git log, codebase search)
- Acceptance criteria (explicit or implied)
- Any architecture decisions that are open vs. already settled

Only after that assessment choose the complexity tier below.

---

## Complexity Tiers

### Tier 1 â€” Simple (serial, 2â€“3 agents)

**When to use:**
- Single-area change: one module, one bug, one small feature, config/docs tweak
- No architectural ambiguity
- Estimated diff < ~200 lines

**Team:**
```
Planner â†’ Coder â†’ Reviewer
```

**Flow:**
1. **Planner** reads issue + relevant files, writes a one-page implementation plan
   (what to change, why, files touched, acceptance criteria). No file writes.
2. Orchestrator reviews plan. If acceptable, spawns **Coder**.
3. **Coder** implements the change per the plan. Owns all files in scope.
4. Orchestrator runs binary checks (compile, tests). If passing, spawns **Reviewer**.
5. **Reviewer** checks correctness, security, and test coverage. Returns a short findings list.
6. Orchestrator applies any findings and finalises the PR.

---

### Tier 2 â€” Medium (partial parallelism, 3â€“5 agents)

**When to use:**
- Multi-area change: 2â€“4 loosely coupled modules or layers (e.g. frontend + backend, API + tests)
- Requirements are clear, architecture is settled
- Estimated diff 200â€“800 lines

**Team:**
```
Planner
  â””â”€â–º Coder A (domain/layer A)  â”€â”
  â””â”€â–º Coder B (domain/layer B)  â”€â”¤â”€â–º Integrator â”€â–º Reviewer
  â””â”€â–º Tester (spec-first tests) â”€â”˜
```

**Flow:**
1. **Planner** produces:
   - Implementation plan with explicit **file ownership table** (who owns what)
   - Task list with per-task acceptance criteria
   - Dependency graph (which tasks block others)
2. Orchestrator approves plan, then spawns parallel workers according to the DAG.
3. **Coders A & B** work in isolated git worktrees; each owns a non-overlapping file set.
4. **Tester** writes tests against the spec (not the implementation) in parallel with coders.
5. When all workers finish, **Integrator** (orchestrator or dedicated agent) merges worktrees,
   resolves conflicts, runs full test suite.
6. **Reviewer** applies a single review pass. Use separate invocations for different lenses
   (correctness first, then security, then perf) if the change warrants it.

---

### Tier 3 â€” Complex (full DAG with task queue, 5â€“10 agents)

**When to use:**
- Large feature spanning multiple subsystems
- Architecture decisions not fully settled in the issue
- Estimated diff > 800 lines, or significant unknowns

**Team:**
```
Orchestrator
  â””â”€â–º Architect (fills spec gaps, produces ADR)
        â””â”€â–º [approved ADR] â”€â–º Task Queue
              â”œâ”€â–º Coder A (subsystem A)
              â”œâ”€â–º Coder B (subsystem B)
              â”œâ”€â–º Coder C (subsystem C)
              â”œâ”€â–º Tester
              â””â”€â–º [wave complete] â”€â–º Integrator â”€â–º Reviewer(s)
```

**Flow:**
1. **Orchestrator** reads issue, identifies open architecture decisions, spawns **Architect**.
2. **Architect** (read-only) produces an Architecture Decision Record (ADR):
   - What decisions need to be made
   - Options considered with trade-offs
   - Recommended approach
   - Impact on file structure, APIs, data models
   - Updated acceptance criteria
3. **Orchestrator reviews ADR with the user** before proceeding. This is the gate that prevents
   building on wrong assumptions. Do not skip this step.
4. With approved ADR, orchestrator creates the **task queue**: a flat list of atomic tasks, each
   with a full task spec (see template below). Tasks are labelled with their wave (1, 2, ...) to
   encode dependencies.
5. **Wave 1** (parallel): independent implementation tasks. Each coder claims one task at a time.
6. After each wave, orchestrator runs binary checks. Only advance to the next wave if checks pass.
7. After all implementation waves, **Integrator** assembles and runs the full test suite.
8. **Reviewers** (one per lens: correctness, security, performance) run in parallel on the final diff.
9. Orchestrator applies reviewer findings and opens the PR.

---

## Role Definitions

| Role | Model | `model` param | Scope | File writes |
|---|---|---|---|---|
| **Orchestrator** | GPT-5.4 | _(inherits)_ | Full project | No direct writes; delegates |
| **Architect** | GPT-5.4 | `model: "gpt-5.4"` | Read-only research + ADR file | ADR doc only |
| **Planner** | GPT-5.4 | `model: "gpt-5.4"` | Read-only research + plan doc | Plan doc only |
| **Coder** | GPT-5.4-Mini | `model: "gpt-5.4-mini"` | Assigned file set only | Yes, owned files only |
| **Tester** | GPT-5.4-Mini | `model: "gpt-5.4-mini"` | Test files only | Yes, test files only |
| **Integrator** | GPT-5.4-Mini | `model: "gpt-5.4-mini"` | Integration branch | Yes, after merge |
| **Reviewer** | GPT-5.4 | `model: "gpt-5.4"` | Read-only | No â€” returns findings list |

When spawning agents via the `Agent` tool, pass the `model` parameter as shown above.
The orchestrator inherits the session model (should be run on GPT-5.4). All other agents
must have their model set explicitly to avoid inheriting the parent's model.

---

## Task Specification Template

Every task handed to a spawned agent MUST include all of these fields:

```
Issue: #<number> â€” <title>
ADR: <path to ADR if Tier 3, else "N/A">

Objective: [one sentence â€” what outcome defines success]

Input:
  - Files to read: [list]
  - Prior artifacts: [outputs from dependency tasks, file paths]

Output:
  - Deliverable: [exact filename(s) and format]
  - Must include: [required elements]

Scope (files you may edit):
  - <file or glob>

Out of scope (do not touch):
  - <file or glob>
  - <file or glob>

Acceptance criteria:
  - [ ] <binary, verifiable criterion>
  - [ ] <binary, verifiable criterion>

Tools allowed: [list â€” e.g., Read, Edit, Write, Bash, Grep, Glob]

Do not:
  - Do not modify files outside your scope list
  - Do not make architecture decisions not covered by the ADR
  - Do not open PRs or push branches
```

---

## File Ownership Rules

1. Before spawning any parallel agents, the orchestrator assigns a file ownership table.
2. No file appears in more than one agent's scope.
3. If a change requires touching a shared file (e.g., a config or index file), assign it to the
   Integrator, not to any Coder. Coders write stubs or placeholders; Integrator wires them.
4. Use git worktrees for Tier 2 and Tier 3 parallelism. Each Coder works in its own worktree
   on its own branch. Integrator merges into the feature branch.

---

## Validation Pipeline

Run in this order. Stop and fix before advancing.

1. **Static checks** (after each Coder wave): compile, typecheck, lint
2. **Unit tests**: existing suite must pass; new tests must pass
3. **Integration tests**: if present, run after Integrator step
4. **Maker-checker loop** (if a Coder's output is uncertain):
   - Max 3 rounds
   - Checker receives: the code, the task spec, and the acceptance criteria
   - Checker returns: pass/fail + specific failure description
   - On 3rd failure: escalate to orchestrator, do not loop further
5. **Review pass**: Reviewer(s) return a findings list; orchestrator triages and applies

---

## Architecture Decision Record (ADR) Template

For Tier 3 issues, the Architect produces this before any implementation begins:

```markdown
# ADR: <issue title>

## Status: PROPOSED / ACCEPTED / REJECTED

## Context
[What is the problem and what constraints apply]

## Open Decisions
[List each decision that the issue left unresolved]

## Decision N: <topic>
**Options:**
- Option A: ... [pros / cons]
- Option B: ... [pros / cons]
**Recommendation:** Option X because ...

## Consequences
[Impact on file structure, APIs, data models, tests, performance]

## Updated Acceptance Criteria
- [ ] ...
```

The orchestrator presents this to the user before spawning any implementation agents.

---

## Error Handling

| Failure type | Response |
|---|---|
| Agent stalls / no output | Kill after 3 min inactivity; re-spawn with same task spec + checkpoint artifacts |
| Tool error (transient) | Retry up to 3Ã— with exponential backoff; report if still failing |
| Binary check fails after Coder | Re-assign failing files to the same Coder with the error output as additional context |
| Binary check fails after Integration | Integrator gets conflict context and one retry; if still failing, orchestrator steps in |
| Reviewer finds blocking issue | Apply fix in a targeted edit; re-run binary checks; do not re-run the full review loop |
| ADR rejected by user | Architect revises ADR; no implementation work starts until ADR is re-approved |

---

## PR Checklist (Orchestrator, before opening PR)

- [ ] All binary checks pass (compile, typecheck, lint, tests)
- [ ] All acceptance criteria from the task specs are met
- [ ] All Reviewer findings are either fixed or explicitly acknowledged as out-of-scope
- [ ] PR description references the issue number, summarises the approach, and lists any deferred decisions
- [ ] No files outside the original scope were modified (check `git diff --name-only`)
- [ ] Commit history is clean: one commit per logical unit, no "fix typo" noise commits

---

## Quick-Reference: Tier Selection

```
Read the issue
    â”‚
    â”œâ”€ Single area, clear requirements, < 200 lines?
    â”‚       â””â”€â–º Tier 1 (Planner â†’ Coder â†’ Reviewer)
    â”‚
    â”œâ”€ Multi-area, clear requirements, 200â€“800 lines?
    â”‚       â””â”€â–º Tier 2 (parallel Coders + Tester â†’ Integrator â†’ Reviewer)
    â”‚
    â””â”€ Large / uncertain requirements / architecture gaps?
            â””â”€â–º Tier 3 (Architect ADR gate â†’ task queue DAG â†’ Integrator â†’ Reviewers)
```

When in doubt, start at the lower tier and escalate if you discover hidden complexity during planning.

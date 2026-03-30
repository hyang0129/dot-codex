# Agent Team Guide

Use this guide when the workflow needs real Codex sub-agent orchestration.

## Core principle

The main run is the orchestrator. Do not treat "agent teams" as a separate feature. Build the team explicitly with:
- `spawn_agent`
- `wait_agent`
- `send_input`

## Codex role mapping

| Workflow role | Codex shape | Model | Notes |
|---|---|---|---|
| Orchestrator | main run | inherited | owns branching, git, and handoffs |
| Planner | `explorer` | `gpt-5.4` | read-only research plus plan file |
| Architect | `explorer` | `gpt-5.4` | read-only research plus ADR file |
| Reviewer | `explorer` | `gpt-5.4` | read-only findings |
| Intent Validator | `explorer` | `gpt-5.4` | read-only intent check |
| Coder | `worker` | `gpt-5.4-mini` | bounded implementation work |
| Tester | `worker` | `gpt-5.4-mini` | bounded test work |
| Integrator | `worker` | `gpt-5.4-mini` | shared wiring and merge work |
| Fixer | `worker` | `gpt-5.4-mini` | single finding or single batch |
| Conflict Resolver | `worker` | `gpt-5.4-mini` | conflict markers only |

## Tier selection

### Tier 1

Use when:
- one module or one narrow workflow is affected
- requirements are clear
- architecture is already settled
- expected diff is small

Default team:
- Planner
- Coder
- Reviewer

### Tier 2

Use when:
- two to four loosely coupled areas are affected
- requirements are clear
- the work benefits from parallel implementation

Default team:
- Planner
- Coder A
- Coder B
- Tester
- Integrator
- Reviewer

### Tier 3

Use when:
- architecture is not fully decided
- shared interfaces or data models are affected
- the issue contains major unknowns

Default team:
- Planner
- Architect
- one or more implementation waves of Coders and Tester
- Integrator
- Reviewer
- optional Intent Validator if risk is high

## ADR gate

If the Planner surfaces architecture questions, or if the issue is Tier 3:
- spawn Architect
- write `ISSUE_<number>_ADR.md`
- post decisions to GitHub
- stop implementation until the user approves the ADR

Do not let workers implement around unresolved architecture questions.

## File ownership

Before spawning implementation workers:
- define a file ownership table
- ensure each editable file belongs to exactly one worker
- keep shared wiring files with the Integrator where possible

Workers must never broaden scope on their own.

## Delegation rules

- Prefer `explorer` for read-only research and analysis.
- Prefer `worker` for bounded code changes.
- Do not spawn an agent for the very next blocking step if the orchestrator can do it directly.
- Use `wait_agent` sparingly; do useful orchestration work while agents run.
- If parallel tasks overlap in write scope, do not run them in parallel.

## Task spec requirements

Every sub-agent task should include:
- issue title and number
- exact objective
- exact files to read
- exact files allowed to edit
- explicit out-of-scope files
- acceptance criteria
- required deliverables

## Validation rules

After each implementation wave:
- run compile, typecheck, lint, and test commands as appropriate
- stop and route failures back to the responsible worker
- do not advance to the next wave while checks are red

## Review and handoff

After implementation:
- run the review-fix logic
- if clean, run the rebase logic
- if blocked, stop and report with the PR URL

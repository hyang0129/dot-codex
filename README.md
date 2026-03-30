# dot-codex

Reusable Codex configuration: portable settings, custom skills, local plugins, automations, and starter templates.

## What's in here

| Path | Purpose |
|---|---|
| `config.toml` | Durable Codex settings to symlink into `~/.codex/config.toml` |
| `skills/` | Your custom Codex skills |
| `plugins/` | Local Codex plugins you want to keep in source control |
| `automations/` | Automation definitions you want to version |
| `.agents/plugins/marketplace.json` | Local plugin marketplace ordering / metadata |
| `templates/` | Starter files for project-level Codex setup |

## Install

Clone this folder into its own repo, then symlink the tracked files into `~/.codex`.

**Linux / macOS / WSL / Git Bash:**
```bash
git clone https://github.com/YOUR_USER/dot-codex.git
cd dot-codex
./install.sh
```

**Windows (cmd.exe):**
```batch
git clone https://github.com/YOUR_USER/dot-codex.git
cd dot-codex
install.cmd
```

The install script links tracked config into `~/.codex` and backs up anything already there. Runtime state such as auth, sessions, caches, sqlite files, logs, and sandbox directories is left alone.

## What to version

Good candidates:
- `config.toml`
- custom skills under `skills/`
- local plugins under `plugins/`
- intentional automation definitions under `automations/`
- `.agents/plugins/marketplace.json`

Usually do **not** version:
- `auth.json`, `cap_sid`
- `sessions/`, `memories/`, `sqlite/`, `tmp/`, `cache/`
- `.sandbox*`, logs, model caches, vendor imports

## Templates

### Project AGENTS.md

Copy `templates/project-AGENTS.md` into a project root when you want repo-specific Codex instructions.

## Included plugin

### Issue Orchestrator

This repo includes a local plugin at `plugins/issue-orchestrator/` that ports your old Claude slash-command workflow into Codex commands:
- `/fix-issue <issue-url-or-number>`
- `/review-fix [branch] [cycles]`
- `/rebase [branch] [base-branch]`
- `/merge-queue [label]`

After installing `dot-codex` into `~/.codex`, open Codex in a repo and use commands like:

```text
/fix-issue https://github.com/hyang0129/video_agent_long/issues/320
```

The command flow is designed to keep the same convenience as your previous setup:
`/fix-issue` -> ADR review when needed -> PR -> `/review-fix` -> `/rebase`.

## Next steps

1. Add your real `config.toml` preferences.
2. Move any custom skills into `skills/`.
3. Add local plugins to `plugins/` as needed.
4. Re-run the install script after adding new tracked directories.
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_TARGET="$HOME/.codex"
HOME_PLUGINS="$HOME/plugins"
HOME_AGENTS="$HOME/.agents/plugins"

mkdir -p "$CODEX_TARGET" "$CODEX_TARGET/skills" "$CODEX_TARGET/automations" "$HOME_PLUGINS" "$HOME_AGENTS"

backup_path() {
  local dst="$1"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    echo "  backup: $dst -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
}

link_path() {
  local src="$1" dst="$2"
  backup_path "$dst"
  ln -s "$src" "$dst"
  echo "  linked: $dst -> $src"
}

echo "Installing dot-codex from $SCRIPT_DIR"
echo ""

link_path "$SCRIPT_DIR/config.toml" "$CODEX_TARGET/config.toml"
link_path "$SCRIPT_DIR/skills" "$CODEX_TARGET/skills"
link_path "$SCRIPT_DIR/automations" "$CODEX_TARGET/automations"
link_path "$SCRIPT_DIR/plugins/issue-orchestrator" "$HOME_PLUGINS/issue-orchestrator"
link_path "$SCRIPT_DIR/.agents/plugins/marketplace.json" "$HOME_AGENTS/marketplace.json"

echo ""
echo "Done. Codex settings live under ~/.codex, and local plugin discovery lives under ~/.agents and ~/plugins."

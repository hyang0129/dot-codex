#!/usr/bin/env bash
set -euo pipefail

# Install dot-codex repo into ~/.codex
# Creates symlinks so edits in either location stay in sync.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.codex"

mkdir -p "$TARGET" "$TARGET/.agents/plugins"

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

link_path "$SCRIPT_DIR/config.toml" "$TARGET/config.toml"
link_path "$SCRIPT_DIR/skills" "$TARGET/skills"
link_path "$SCRIPT_DIR/plugins" "$TARGET/plugins"
link_path "$SCRIPT_DIR/automations" "$TARGET/automations"
link_path "$SCRIPT_DIR/.agents/plugins/marketplace.json" "$TARGET/.agents/plugins/marketplace.json"

echo ""
echo "Done. Runtime state (auth, sessions, sqlite, caches, sandbox dirs, etc.) is untouched."

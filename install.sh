#!/usr/bin/env bash
# install.sh — wire this repo into a fresh machine. Idempotent.
#
# Creates these symlinks:
#   ~/.config/cmux/cmux.json     → <repo>/cmux.json
#   ~/.local/bin/cmux-worktree   → <repo>/scripts/cmux-worktree.sh
#   ~/.local/bin/cwt             → <repo>/scripts/cmux-worktree.sh
#
# Leaves ~/.config/cmux/settings.json alone — that file is managed by the cmux app.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/cmux"
BIN_DIR="${HOME}/.local/bin"

mkdir -p "$CONFIG_DIR" "$BIN_DIR"

link() {
  local src=$1 dst=$2
  if [[ -L "$dst" ]]; then
    local current
    current=$(readlink "$dst")
    if [[ "$current" == "$src" ]]; then
      printf '  unchanged: %s\n' "$dst"
      return
    fi
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    printf '  backup: %s -> %s.bak\n' "$dst" "$dst"
    mv "$dst" "$dst.bak"
  fi
  ln -s "$src" "$dst"
  printf '  linked: %s -> %s\n' "$dst" "$src"
}

printf 'Installing cmux config from %s\n\n' "$REPO_ROOT"

# Make script executable in case the checkout lost the bit (e.g., zip download).
chmod +x "$REPO_ROOT/scripts/cmux-worktree.sh" 2>/dev/null || true

link "$REPO_ROOT/cmux.json"                "$CONFIG_DIR/cmux.json"
link "$REPO_ROOT/scripts/cmux-worktree.sh" "$BIN_DIR/cmux-worktree"
link "$REPO_ROOT/scripts/cmux-worktree.sh" "$BIN_DIR/cwt"

printf '\nSanity checks:\n'
if command -v cmux >/dev/null 2>&1; then
  printf '  [ok] cmux on PATH (%s)\n' "$(command -v cmux)"
else
  printf '  [warn] cmux not on PATH. Install: brew install --cask cmux\n'
fi
if command -v claude >/dev/null 2>&1; then
  printf '  [ok] claude on PATH (%s)\n' "$(command -v claude)"
else
  printf '  [info] claude not on PATH. Set CMUX_WORKTREE_AGENT=<agent> if not using claude.\n'
fi
case ":$PATH:" in
  *":$BIN_DIR:"*) printf '  [ok] %s is on PATH\n' "$BIN_DIR" ;;
  *)              printf '  [warn] %s is NOT on PATH. Add to your shell rc:\n         export PATH="$HOME/.local/bin:$PATH"\n' "$BIN_DIR" ;;
esac

printf '\nNext steps:\n'
printf '  - run once: cmux setup-hooks   (so agent rings/notifications work)\n'
printf '  - try it:  cwt --help\n'
printf '\nDone.\n'

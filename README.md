# cmux

Personal cmux configuration and helper scripts. Provides `cwt`, a CLI that creates a git worktree and opens it as a cmux workspace (or as tabs in the current workspace) in one command.

> Requires [cmux](https://cmux.com) — a macOS-only Ghostty-based terminal. Install with `brew install --cask cmux`.

## Install

```bash
git clone git@github.com:WadeSeidule/cmux.git ~/dev/cmux
cd ~/dev/cmux
./install.sh
```

The installer is idempotent — re-run it any time after `git pull`. It creates these symlinks:

| Symlink | Source |
|---|---|
| `~/.config/cmux/cmux.json` | `~/dev/cmux/cmux.json` |
| `~/.local/bin/cwt` | `~/dev/cmux/scripts/cmux-worktree.sh` |
| `~/.local/bin/cmux-worktree` | `~/dev/cmux/scripts/cmux-worktree.sh` |

It also backs up any existing real files at the target paths to `*.bak`, and warns if `cmux`, `claude`, or `~/.local/bin/` aren't set up yet.

After install, run once:

```bash
cmux setup-hooks       # so agent rings and notifications work
```

`~/.config/cmux/settings.json` is left alone — that file belongs to the cmux app.

## `cwt` — usage

```
cwt <slug> [flags]                        # shorthand for: cwt new <slug>
cwt new  <slug> [-d desc] [-a agent] [-b branch] [-p path] [-B base] [--no-agent]
cwt tabs <slug...> [-a agent] [-B base] [--no-agent]
cwt done <slug> [--force] [--keep-branch]
cwt list
cwt --help
```

### Pick a mode: workspace or tabs

| Mode | Command | When to use |
|---|---|---|
| **Workspace** | `cwt <slug>` | One feature you'll context-switch to. Each gets its own sidebar entry with branch, PR status, ports, and a notification ring. |
| **Tabs** | `cwt tabs <slug>...` | Tightly-coupled parallel work (race the same task across N agents). Tabs share one workspace and stay visible at once. **Must be run from inside a cmux terminal.** |

### Examples

```bash
# One feature, default agent (claude)
cwt fix-leak

# Different agent, with a sidebar description
cwt PROJ-123 -a codex -d "deadlock in queue"

# Branch off a release tag instead of HEAD
cwt hotfix-3.7.3 -B v3.7.2

# Plain shell, no agent
cwt poke-around --no-agent

# Race three agents across three worktrees, all in the current workspace
cwt tabs leak-claude leak-codex leak-opencode -a claude

# Tear down (closes workspace, removes worktree, deletes branch)
cwt done fix-leak

# Discard uncommitted changes during teardown
cwt done failed-experiment --force

# Cleanup but keep the branch (e.g., PR still open on remote)
cwt done feat-X --keep-branch

# Show worktrees joined with their cmux workspaces
cwt list
```

### Slug → branch derivation

The shape of the slug determines the branch namespace. Slugs with no recognized prefix are used as-is (no implicit namespace). Override with `-b <branch>`.

| Slug | Branch |
|---|---|
| `fix-leak` | `fix/leak` |
| `hotfix-3.7.3` | `hotfix/3.7.3` |
| `exp-rewrite` | `exp/rewrite` |
| `wip-foo` | `wip/foo` |
| `refactor-types` | `refactor/types` |
| `chore-deps` | `chore/deps` |
| `docs-readme` | `docs/readme` |
| `PROJ-123` | `PROJ-123` (passed through unchanged) |
| `fix/cache` | `fix/cache` (slash kept as-is) |

### Worktree location

Default: `<repo-root>/.worktrees/<slug>`. Override via `CMUX_WORKTREE_REPO_DIR`:

| `CMUX_WORKTREE_REPO_DIR` | Resolves to |
|---|---|
| (unset) | `<repo>/.worktrees/<slug>` |
| `foo` | `<repo>/foo/<slug>` (relative to repo root) |
| `/abs/path` | `/abs/path/<slug>` (absolute) |

Per-call override: `-p <path>` wins over the env var.

> **Tip:** Add `.worktrees/` to your repo's `.gitignore` to keep `git status` quiet.

### Agent override

Default agent: `claude`. Override:

- Per-call: `-a "<command>"` — e.g., `-a codex`, `-a "claude --model sonnet"`
- Globally: `export CMUX_WORKTREE_AGENT=<command>` in your shell rc

## Palette commands

Open the cmux command palette and type `worktree` to see:

| Palette name | Command pasted into focused terminal |
|---|---|
| New worktree | `cwt ` |
| New worktree (codex) | `cwt -a codex ` |
| New worktree (no agent) | `cwt --no-agent ` |
| Tabs (worktrees in current workspace) | `cwt tabs ` |
| Close worktree | `cwt done ` *(prompts for confirmation)* |
| List worktrees | `cwt list` |

Each palette entry pastes the command prefix; finish by typing the slug and Enter.

## Updating

```bash
cd ~/dev/cmux
git pull
./install.sh           # idempotent — re-run after every pull
```

cmux auto-reloads `cmux.json` on file change, so palette updates take effect without restarting the app.

## Troubleshooting

### `cwt: command not found`

`~/.local/bin/` isn't on your `$PATH`. Add this to your shell rc:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload the shell (or open a new terminal).

### `cwt tabs` errors with "must be run inside a cmux workspace"

`cwt tabs` adds tabs to the *current* cmux workspace, so it needs to run inside a cmux terminal. If you're in a regular terminal, open cmux first and run it from there.

### Palette commands don't show up

Check the symlink resolves:

```bash
readlink ~/.config/cmux/cmux.json
# expected: /Users/<you>/dev/cmux/cmux.json
```

If the symlink is missing or points elsewhere, re-run `./install.sh`.

### `cwt done` complains about uncommitted changes

The script refuses to remove a worktree with uncommitted changes — that's the data-loss guard. Either commit/stash the work first, or pass `--force` to discard:

```bash
cwt done <slug> --force
```

### `cwt new` fails with "branch already exists"

The slug-to-branch derivation collided with an existing branch. Pick a different slug, or pass `-b <branch>` to choose the branch name explicitly.

## Uninstall

```bash
rm ~/.config/cmux/cmux.json
rm ~/.local/bin/cwt ~/.local/bin/cmux-worktree
rm -rf ~/dev/cmux
```

`~/.config/cmux/settings.json` is left in place — the cmux app owns it.

## Related

For the full cmux reference (object model, CLI catalog, multi-agent integrations, workflow recipes), see the cmux skill at `~/.claude/skills/cmux/SKILL.md`.

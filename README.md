# cmux

Personal cmux configuration and helper scripts.

## What's here

| File | Purpose |
|---|---|
| `cmux.json` | Global cmux command palette config |
| `scripts/cmux-worktree.sh` | `cwt` — worktree + workspace + agent helper |
| `install.sh` | Idempotent installer (symlinks into `~/.config/cmux/` and `~/.local/bin/`) |

## Install

```bash
git clone <this-repo> ~/dev/cmux
cd ~/dev/cmux
./install.sh
```

After install:

- `cwt` and `cmux-worktree` are on `$PATH` (via `~/.local/bin/`)
- `cmux.json` palette commands are loaded by cmux globally
- `~/.config/cmux/settings.json` is **not** touched — it's owned by the cmux app

To pick up changes from the repo, `git pull` and re-run `./install.sh` (it's idempotent).

## Usage

```bash
cwt fix-leak                          # worktree + new workspace + claude
cwt PROJ-123 -a codex                 # different agent
cwt hotfix-3.7.3 -B v3.7.2            # branch off a tag

cwt tabs slug1 slug2 slug3            # N worktrees, N tabs in CURRENT workspace
                                      # (must be run from inside a cmux terminal)

cwt done fix-leak                     # tear down (workspace + worktree + branch)
cwt list                              # show worktrees joined with cmux workspaces
cwt --help
```

### Slug → branch derivation

| Slug | Branch |
|---|---|
| `fix-leak` | `fix/leak` |
| `hotfix-3.7.3` | `hotfix/3.7.3` |
| `exp-rewrite` | `exp/rewrite` |
| `PROJ-123` | `feat/PROJ-123` |
| `fix/cache` | `fix/cache` (slash kept) |

### Worktree location

Default: `<repo-root>/.worktrees/<slug>`. Override with `CMUX_WORKTREE_REPO_DIR` (relative paths resolve against the repo root, absolute paths are used as-is).

Tip: add `.worktrees/` to your repo's `.gitignore` to keep `git status` quiet.

### Agent override

Default agent: `claude`. Override globally via `CMUX_WORKTREE_AGENT` env var, or per-call with `-a "<command>"`.

## Related

Full docs live in the cmux skill at `~/.claude/skills/cmux/SKILL.md` (object model, CLI reference, multi-agent integrations, workflow recipes, evals).

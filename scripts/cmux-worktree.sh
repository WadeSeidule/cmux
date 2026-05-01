#!/usr/bin/env bash
# cmux-worktree — create git worktrees + cmux UI together, with smart defaults
# so the common case is one short command.
#
# Subcommands (the first arg can also be a slug — implicit `new`):
#   new  <slug>           one worktree + new cmux workspace + agent
#   tabs <slug...>        N worktrees + N tabs in the current cmux workspace
#                         (each tab cd's into its own worktree and runs an agent)
#   done <slug>           close cmux workspace + remove worktree + delete branch
#   list                  list worktrees that have a matching cmux workspace
#
# Worktree location (override with -p):
#   default                            <repo-root>/.worktrees/<slug>
#   CMUX_WORKTREE_REPO_DIR=foo         <repo-root>/foo/<slug>
#   CMUX_WORKTREE_REPO_DIR=/abs/path   /abs/path/<slug>
#   tip: add `.worktrees/` to your repo's .gitignore to keep `git status` clean
#
# Branch derivation from slug (override with -b):
#   slug "fix-leak"        → branch fix/leak
#   slug "hotfix-3.7.3"    → branch hotfix/3.7.3
#   slug "exp-rewrite"     → branch exp/rewrite
#   slug "PROJ-123"        → branch PROJ-123        (no recognized prefix → branch is the slug)
#   slug "fix/cache"       → branch fix/cache       (slash kept as-is)
#
# new flags:
#   -d, --description <text>   workspace description (default: slug)
#   -a, --agent <cmd>          startup command (default: claude, env: CMUX_WORKTREE_AGENT)
#   -b, --branch <name>        branch name (default: derived from slug)
#   -p, --path <path>          worktree path (default: <worktrees-root>/<slug>)
#   -B, --base <ref>           base ref for the new branch (default: HEAD)
#       --no-agent             create the workspace without running any startup command
#
# done flags:
#       --force                proceed even with uncommitted changes
#       --keep-branch          remove worktree but keep the branch

set -euo pipefail

PROG="${0##*/}"
DEFAULT_AGENT="${CMUX_WORKTREE_AGENT:-claude}"

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# Resolve the directory that holds worktrees for this repo.
# Honors CMUX_WORKTREE_REPO_DIR: absolute paths used as-is, relative paths
# resolved against the repo root. Default: <repo-root>/.worktrees.
worktrees_root_for() {
  local repo_root=$1
  local override=${CMUX_WORKTREE_REPO_DIR:-}
  if [[ -z "$override" ]]; then
    printf '%s/.worktrees' "$repo_root"
  elif [[ "$override" = /* ]]; then
    printf '%s' "$override"
  else
    printf '%s/%s' "$repo_root" "$override"
  fi
}

# Map a slug to a branch name. Common prefixes (fix-, hotfix-, exp-, wip-,
# refactor-, chore-, docs-) become namespaces. Slugs already containing a slash
# are used verbatim. Everything else passes through unchanged (the slug *is*
# the branch name — no implicit namespace).
slug_to_branch() {
  local s=$1
  if [[ "$s" == */* ]]; then
    printf '%s' "$s"
    return
  fi
  case "$s" in
    fix-*|fix_*)            printf 'fix/%s'      "${s#fix[-_]}" ;;
    hotfix-*|hotfix_*)      printf 'hotfix/%s'   "${s#hotfix[-_]}" ;;
    exp-*|exp_*)            printf 'exp/%s'      "${s#exp[-_]}" ;;
    wip-*|wip_*)            printf 'wip/%s'      "${s#wip[-_]}" ;;
    refactor-*|refactor_*)  printf 'refactor/%s' "${s#refactor[-_]}" ;;
    chore-*|chore_*)        printf 'chore/%s'    "${s#chore[-_]}" ;;
    docs-*|docs_*)          printf 'docs/%s'     "${s#docs[-_]}" ;;
    *)                      printf '%s'          "$s" ;;
  esac
}

# Sanitize a slug for use in a filesystem path (always flat, no slashes).
slug_to_path_token() {
  printf '%s' "$1" | tr '/' '-' | tr -cd '[:alnum:]_.-'
}

usage() {
  cat <<EOF
Usage:
  $PROG <slug> [flags]                      # shorthand for: $PROG new <slug>
  $PROG new  <slug> [-d desc] [-a agent] [-b branch] [-p path] [-B base] [--no-agent]
  $PROG tabs <slug...> [-a agent] [-B base] [--no-agent]
  $PROG done <slug> [--force] [--keep-branch]
  $PROG list

Slug → branch:
  fix-leak       → fix/leak
  hotfix-3.7.3   → hotfix/3.7.3
  PROJ-123       → PROJ-123       (no recognized prefix → branch matches slug)
  fix/cache      → fix/cache      (already namespaced)

Defaults:
  agent  \$CMUX_WORKTREE_AGENT or 'claude'
  path   <repo>/.worktrees/<slug>  (override per-repo with \$CMUX_WORKTREE_REPO_DIR)

Examples:
  $PROG fix-leak                                # one worktree + new workspace
  $PROG PROJ-123 -a codex -d "deadlock in queue"
  $PROG hotfix-3.7.3 -B v3.7.2
  $PROG tabs leak-1 leak-2 leak-3 -a claude     # 3 worktrees, 3 tabs in this workspace
  $PROG done fix-leak                           # tear down (workspace + worktree + branch)
EOF
}

resolve_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "not in a git repository"
}

# Find the cmux workspace ref whose name matches the slug. Empty string if none.
find_workspace_ref_by_name() {
  local slug=$1
  cmux list-workspaces --json 2>/dev/null \
    | python3 -c "
import json, sys
slug = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for ws in data if isinstance(data, list) else data.get('workspaces', []):
    name = ws.get('name') or ws.get('title') or ''
    if name == slug:
        print(ws.get('ref') or ws.get('id') or '')
        break
" "$slug"
}

cmd_new() {
  local slug="" desc="" agent="$DEFAULT_AGENT" branch="" path="" base="HEAD" no_agent=0
  while (($#)); do
    case "$1" in
      -d|--description) desc="$2"; shift 2 ;;
      -a|--agent)       agent="$2"; shift 2 ;;
      -b|--branch)      branch="$2"; shift 2 ;;
      -p|--path)        path="$2";   shift 2 ;;
      -B|--base)        base="$2";   shift 2 ;;
      --no-agent)       no_agent=1;  shift ;;
      -h|--help)        usage; exit 0 ;;
      -*)               die "unknown flag: $1" ;;
      *) [[ -z "$slug" ]] && slug="$1" || die "unexpected arg: $1"; shift ;;
    esac
  done
  [[ -n "$slug" ]] || { usage; exit 1; }

  need git
  need cmux
  local repo_root repo_name
  repo_root=$(resolve_repo_root)
  repo_name=$(basename "$repo_root")
  branch="${branch:-$(slug_to_branch "$slug")}"
  local slug_token
  slug_token=$(slug_to_path_token "$slug")
  if [[ -z "$path" ]]; then
    path="$(worktrees_root_for "$repo_root")/$slug_token"
  fi
  desc="${desc:-$slug}"

  # Resolve absolute path so cmux --cwd is unambiguous regardless of where we run.
  local abs_path
  abs_path=$(cd "$repo_root" && cd "$(dirname "$path")" 2>/dev/null && printf '%s/%s' "$PWD" "$(basename "$path")") \
    || abs_path="$path"

  if [[ -e "$abs_path" ]]; then
    die "worktree path already exists: $abs_path (use -p to override)"
  fi
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    die "branch already exists: $branch (use -b to override)"
  fi

  # git worktree add does not create parent directories; ensure they exist.
  local parent_dir="${abs_path%/*}"
  [[ -d "$parent_dir" ]] || mkdir -p "$parent_dir"

  printf '→ creating worktree: %s\n' "$abs_path"
  git -C "$repo_root" worktree add -b "$branch" "$abs_path" "$base"

  printf '→ opening cmux workspace: %s\n' "$slug"
  if (( no_agent )); then
    cmux new-workspace --cwd "$abs_path" --name "$slug" --description "$desc" </dev/null
  else
    cmux new-workspace --cwd "$abs_path" --name "$slug" --description "$desc" --command "$agent" </dev/null
  fi

  printf '✓ ready: %s @ %s (branch %s)\n' "$slug" "$abs_path" "$branch"
}

cmd_done() {
  local slug="" force=0 keep_branch=0
  while (($#)); do
    case "$1" in
      --force)        force=1; shift ;;
      --keep-branch)  keep_branch=1; shift ;;
      -h|--help)      usage; exit 0 ;;
      -*)             die "unknown flag: $1" ;;
      *) [[ -z "$slug" ]] && slug="$1" || die "unexpected arg: $1"; shift ;;
    esac
  done
  [[ -n "$slug" ]] || { usage; exit 1; }

  need git
  need cmux
  local repo_root
  repo_root=$(resolve_repo_root)
  local slug_token
  slug_token=$(slug_to_path_token "$slug")

  # Resolve worktree path: prefer one git knows about whose basename matches
  # the slug exactly (new layout: .worktrees/<slug>) or ends with `-<slug>`
  # (legacy layout: ../<repo>-<slug>). Falls back to the new-layout default.
  local wt_path=""
  while IFS= read -r line; do
    [[ "$line" == worktree\ * ]] || continue
    local p="${line#worktree }"
    local base="${p##*/}"
    if [[ "$base" == "$slug_token" || "$base" == *"-$slug_token" ]]; then
      wt_path="$p"
      break
    fi
  done < <(git -C "$repo_root" worktree list --porcelain)

  local default_path
  default_path="$(worktrees_root_for "$repo_root")/$slug_token"
  wt_path="${wt_path:-$default_path}"
  local abs_path
  abs_path=$(cd "$(dirname "$wt_path")" 2>/dev/null && printf '%s/%s' "$PWD" "$(basename "$wt_path")") \
    || abs_path="$wt_path"

  # Safety: refuse if uncommitted changes (unless --force).
  if [[ -d "$abs_path" ]] && (( ! force )); then
    if ! git -C "$abs_path" diff --quiet || ! git -C "$abs_path" diff --cached --quiet; then
      die "uncommitted changes in $abs_path (use --force to discard)"
    fi
  fi

  # Close cmux workspace by name (if found).
  local ws_ref
  ws_ref=$(find_workspace_ref_by_name "$slug" || true)
  if [[ -n "$ws_ref" ]]; then
    printf '→ closing cmux workspace: %s (%s)\n' "$slug" "$ws_ref"
    cmux close-workspace --workspace "$ws_ref" </dev/null || true
  else
    printf '→ no matching cmux workspace for %s (skipping close)\n' "$slug"
  fi

  if [[ -d "$abs_path" ]]; then
    printf '→ removing worktree: %s\n' "$abs_path"
    if (( force )); then
      git -C "$repo_root" worktree remove --force "$abs_path"
    else
      git -C "$repo_root" worktree remove "$abs_path"
    fi
  else
    printf '→ no worktree at %s\n' "$abs_path"
  fi

  if (( ! keep_branch )); then
    local branch
    branch=$(slug_to_branch "$slug")
    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
      printf '→ deleting branch: %s\n' "$branch"
      if (( force )); then
        git -C "$repo_root" branch -D "$branch"
      else
        git -C "$repo_root" branch -d "$branch" || \
          printf '  (branch %s not fully merged; pass --force to force-delete)\n' "$branch"
      fi
    fi
  fi

  printf '✓ done: %s\n' "$slug"
}

cmd_tabs() {
  local agent="$DEFAULT_AGENT" base="HEAD" no_agent=0
  local slugs=()
  while (($#)); do
    case "$1" in
      -a|--agent)  agent="$2"; shift 2 ;;
      -B|--base)   base="$2";  shift 2 ;;
      --no-agent)  no_agent=1; shift ;;
      -h|--help)   usage; exit 0 ;;
      -*)          die "unknown flag: $1" ;;
      *)           slugs+=("$1"); shift ;;
    esac
  done
  (( ${#slugs[@]} > 0 )) || { usage; exit 1; }

  need git
  need cmux
  need python3

  local ws="${CMUX_WORKSPACE_ID:-}"
  [[ -n "$ws" ]] || die "must be run inside a cmux workspace (CMUX_WORKSPACE_ID is unset)"

  local repo_root
  repo_root=$(resolve_repo_root)

  for slug in "${slugs[@]}"; do
    local branch slug_token path abs_path
    branch=$(slug_to_branch "$slug")
    slug_token=$(slug_to_path_token "$slug")
    path="$(worktrees_root_for "$repo_root")/$slug_token"
    abs_path=$(cd "$repo_root" && cd "$(dirname "$path")" 2>/dev/null && printf '%s/%s' "$PWD" "$(basename "$path")") \
      || abs_path="$path"

    if [[ -e "$abs_path" ]]; then
      printf '  skip %s: worktree already exists at %s\n' "$slug" "$abs_path" >&2
      continue
    fi
    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
      printf '  skip %s: branch already exists: %s\n' "$slug" "$branch" >&2
      continue
    fi

    local parent_dir="${abs_path%/*}"
    [[ -d "$parent_dir" ]] || mkdir -p "$parent_dir"

    printf '→ %s: worktree %s (branch %s)\n' "$slug" "$abs_path" "$branch"
    git -C "$repo_root" worktree add -b "$branch" "$abs_path" "$base"

    # new-surface doesn't print refs, so capture before/after surface refs and diff.
    local before after new_ref
    before=$(cmux --json list-pane-surfaces </dev/null 2>/dev/null \
             | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(s.get("ref","")) for s in d.get("surfaces",[]) if s.get("ref")]' \
             | sort -u)
    cmux new-surface --type terminal --workspace "$ws" </dev/null
    after=$(cmux --json list-pane-surfaces </dev/null 2>/dev/null \
            | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(s.get("ref","")) for s in d.get("surfaces",[]) if s.get("ref")]' \
            | sort -u)
    new_ref=$(comm -13 <(echo "$before") <(echo "$after") | head -1)

    if [[ -z "$new_ref" ]]; then
      printf '  warn %s: created surface but could not resolve its ref; skipping rename and agent launch\n' "$slug" >&2
      continue
    fi

    cmux rename-tab --surface "$new_ref" -- "$slug" </dev/null
    if (( ! no_agent )); then
      cmux send --surface "$new_ref" -- "cd '$abs_path' && $agent\n" </dev/null
    fi

    printf '✓ %s: tab %s ready\n' "$slug" "$new_ref"
  done
}

cmd_list() {
  need git
  need cmux
  local repo_root
  repo_root=$(resolve_repo_root)

  cmux list-workspaces --json </dev/null 2>/dev/null \
    | python3 -c '
import json, os, subprocess, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
workspaces = data if isinstance(data, list) else data.get("workspaces", [])
ws_by_cwd = {}
for ws in workspaces:
    cwd = ws.get("cwd") or ws.get("path") or ""
    if cwd:
        ws_by_cwd[os.path.realpath(cwd)] = ws

repo_root = sys.argv[1]
out = subprocess.check_output(
    ["git", "-C", repo_root, "worktree", "list", "--porcelain"],
    text=True,
)
worktree, branch = None, None
rows = []
for line in out.splitlines() + [""]:
    if line.startswith("worktree "):
        worktree = line[len("worktree "):]
    elif line.startswith("branch "):
        branch = line[len("branch "):]
    elif line == "":
        if worktree:
            ws = ws_by_cwd.get(os.path.realpath(worktree))
            ref = (ws or {}).get("ref") or (ws or {}).get("id") or "-"
            name = (ws or {}).get("name") or (ws or {}).get("title") or "-"
            rows.append((name, ref, branch or "-", worktree))
        worktree, branch = None, None

if not rows:
    sys.exit(0)
widths = [max(len(r[i]) for r in rows + [("NAME", "REF", "BRANCH", "PATH")]) for i in range(4)]
fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
print(fmt.format("NAME", "REF", "BRANCH", "PATH"))
for r in rows:
    print(fmt.format(*r))
' "$repo_root"
}

main() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  case "$1" in
    new)            shift; cmd_new  "$@" ;;
    tabs)           shift; cmd_tabs "$@" ;;
    done)           shift; cmd_done "$@" ;;
    list|ls)        shift; cmd_list "$@" ;;
    -h|--help|help) usage ;;
    -*)             die "unknown flag: $1 (try $PROG --help)" ;;
    *)              cmd_new "$@" ;;  # implicit `new`: cwt <slug> [flags]
  esac
}

main "$@"

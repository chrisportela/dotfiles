# `wt` completions + squash-merge-aware cleanup — design

**Date:** 2026-04-16
**Target package:** `pkgs/wt/`
**Status:** Approved, pending implementation plan

## Problem

The `wt` worktree helper has two rough edges:

1. **No shell autocompletion.** Subcommands and branch/worktree names must be
   typed in full across every shell the user runs (zsh, bash, fish, nushell).
2. **Branch cleanup is blind to squash-merges.** When a PR is merged on the
   remote via squash or rebase, the local branch's commits have different SHAs
   than the merge commit, so `git branch -d` refuses it as "not fully merged".
   Today the user is prompted `Force delete branch? [y/N]` with default **No**
   — the safe default, but wrong for the common case where the remote branch
   has already been deleted as part of the PR merge.

## Goals

- Ship autocompletion for **zsh, bash, fish, and nushell** covering subcommands
  and positional arguments (`wt add <branch>`, `wt rm <branch>`).
- In `wt rm`, detect when the branch's upstream tracking ref is gone and, when
  that's the case, **explain the assumption and recommend force delete**
  (flipped default, not auto-delete).
- Keep the package shape (`writeShellApplication`) unless a real constraint
  forces otherwise.

## Non-goals

- Patch-equivalent squash-merge detection via `git cherry` /
  `git commit-tree`. Covers rarer cases (squash-merged but remote branch not
  yet deleted) and adds complexity. Deferred.
- Auto-running `git fetch -p` before the cleanup check. If the user's view of
  the remote is stale, making `wt rm` phone home implicitly would be
  surprising.
- The future `wt add` scaffolding (env copy, direnv/mise trust, tmux launch,
  per-project services). Captured separately as **DF-10**; requires its own
  config-file design.

## Design

### 1. Package structure

Keep `writeShellApplication` and extend via `.overrideAttrs` to install
completion files. New layout:

```
pkgs/wt/
├── default.nix
├── README.md               # purpose, options, deps (per repo CLAUDE.md rule)
└── completions/
    ├── wt.bash
    ├── _wt                 # zsh (underscore-prefix = zsh autoload convention)
    ├── wt.fish
    └── wt.nu
```

`default.nix` adds `installShellFiles` to `nativeBuildInputs` and a
`postInstall` that:

- Calls `installShellCompletion --cmd wt --bash … --zsh … --fish …` for the
  three supported shells.
- Manually installs `wt.nu` to `$out/share/nushell/vendor/autoload/wt.nu`
  (nushell's standard vendor-autoload path; `installShellCompletion` has no
  nushell flag).

**Module wiring:** move `wt` out of the `lib.optionals stdenv.isLinux` guard
in `modules/home/default.nix` and add it unconditionally. The guard was a
workaround for the nixpkgs `Wt` (C++ toolkit) shadowing issue, resolved in
commit `dfbd70d`. The package itself only needs `git` + coreutils, both
cross-platform.

### 2. Completion behavior

Semantics must be identical across all four shells:

| Invocation            | Completions                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------ |
| `wt <TAB>`            | `init add ls rm help`                                                                                        |
| `wt add <TAB>`        | Existing local + remote branches, deduped. `refs/heads/*` ∪ `refs/remotes/*/*` minus `HEAD`. Hint, not gate. |
| `wt rm <TAB>`         | Only directory names under `$(git rev-parse --show-toplevel)/.worktrees/`. Narrower than branch list.        |
| `wt init\|ls\|help …` | No further argument completions.                                                                             |

**Why `wt rm` uses worktree dirs, not branches:** `cmd_rm` only accepts names
that exist as worktrees under `.worktrees/`. Completing from the full branch
list would offer candidates the command will reject.

**Shell-specific implementation notes:**

- **bash:** `complete -F _wt wt`, uses `COMP_WORDS` / `COMP_CWORD`, helper
  functions `_wt_branches` / `_wt_worktrees` shell out to `git` / `ls`.
- **zsh:** `#compdef wt`, `_arguments -C`, `_values` for subcommands, custom
  `_wt_branches` / `_wt_worktrees` completion functions.
- **fish:** `complete -c wt -n '__fish_use_subcommand' -a '…'` for subcommands,
  chained `complete -c wt -n '__fish_seen_subcommand_from add'` for args.
- **nushell:** `export extern "wt add" [branch?: string@"nu-complete wt-branches"]`
  declarations for each subcommand, plus `nu-complete wt-*` custom completers.

All four completion scripts rely on the same two git queries (branches,
worktree dirs), so they should produce consistent candidate lists.

### 3. Squash-merge-aware cleanup in `cmd_rm`

Add a helper:

```bash
upstream_gone() {
  # $1 = branch name
  # Returns 0 iff the branch had an upstream and that upstream is now gone.
  local track
  track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$1")
  [[ "$track" == *"[gone]"* ]]
}
```

Replace the current "not fully merged" branch in `cmd_rm` (lines 186–196 of
`pkgs/wt/default.nix`) with:

```text
If `git branch -d "$branch"` fails AND merged=false:
  If upstream_gone "$branch":
    echo "Branch '$branch' is not fully merged locally, but its upstream"
    echo "tracking branch is gone. This usually means it was squash- or"
    echo "rebase-merged on the remote and then deleted (common on GitHub"
    echo "PR merge). Recommending force delete."
    Prompt: "Force delete branch? [Y/n]"   # default Yes
  Else:
    echo "Branch '$branch' is not fully merged."
    Prompt: "Force delete branch? [y/N]"   # default No (current behavior)
```

The explanation is as important as the flipped default: the user should see
**why** we recommend force delete (upstream gone → assume upstream merged and
cleaned up) so they can override when that assumption doesn't hold (e.g., the
remote was deleted for reasons unrelated to merge).

## Trade-offs acknowledged

- **Four completion scripts, not one generator.** Each shell has its own
  completion grammar; there's no clean cross-shell generator worth the
  dependency. Writing four focused scripts is less code than adopting a
  generator framework and keeps the package's only build dep at
  `installShellFiles`.
- **`[gone]` heuristic has false negatives.** A branch squash-merged but whose
  remote ref wasn't deleted will still land in the `else` branch with the safe
  default. The message still tells the truth in that case ("not fully
  merged"), just without the recommendation. User can still say y.
- **`[gone]` heuristic has false positives.** A remote branch deleted for
  non-merge reasons (abandoned work, force-pushed and renamed) would trigger
  the recommendation. The explanation names the assumption, so the user has
  the information needed to type `n`.
- **Branches with no upstream configured at all** (never pushed) naturally
  fall through to the `else` branch because `%(upstream:track)` returns empty
  — `""` does not match `*"[gone]"*`. This is correct: we have no signal
  that anything was merged upstream, so keep the safe default.

## Files touched

- `pkgs/wt/default.nix` — extend with completions install, add `upstream_gone`
  helper, update `cmd_rm` flow.
- `pkgs/wt/completions/wt.bash` — new.
- `pkgs/wt/completions/_wt` — new (zsh).
- `pkgs/wt/completions/wt.fish` — new.
- `pkgs/wt/completions/wt.nu` — new.
- `pkgs/wt/README.md` — new (repo rule: every `pkgs/` entry needs one).
- `modules/home/default.nix` — move `wt` out of the `stdenv.isLinux`
  conditional.

## Verification

- `nix build .#wt` succeeds.
- `nix build .` (full home-manager config) succeeds on both Linux and Darwin
  hosts.
- Smoke test in a fresh shell of each type: `wt <TAB>` shows subcommands;
  `wt add <TAB>` shows branches; `wt rm <TAB>` shows worktree dirs.
- Manual test for squash-merge flow: create a branch, push, squash-merge a PR,
  delete the remote branch, `git fetch -p`, then `wt rm <branch>` — expect the
  "upstream gone / recommending force delete" message with `[Y/n]` prompt.
- Manual test for non-squash case: create a local branch with unmerged
  commits and no upstream — expect the original "[y/N]" prompt.
- Manual test for never-pushed branch: create a local branch with no upstream
  configured — expect the original "[y/N]" prompt (not the `[gone]` path).

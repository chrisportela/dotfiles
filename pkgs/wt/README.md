# wt

A thin wrapper around `git worktree` that keeps all worktrees under a
single `.worktrees/` directory at the repo root.

## Commands

- `wt init` — create `.worktrees/` and add it to `.git/info/exclude`
- `wt add [--no-direnv] <branch>` — create a worktree. Branch resolution
  matches `git checkout`'s DWIM:
    - existing local branch → checks it out;
    - exactly one remote-tracking branch with the same name → creates a
      tracking branch off it;
    - multiple remotes have it → errors with the candidates listed and
      asks the user to qualify the desired remote;
    - none of the above → creates a new branch off `HEAD`.
  By default, runs `direnv allow` on every `.envrc` found under the new
  worktree (excluding `.git/`), so the dev shell is activated for the
  worktree root and any nested sub-shell envrcs (e.g. monorepo
  `src/.envrc` + `infra/.envrc`). Pass `--no-direnv` to skip approval.
  If `direnv` is not on `PATH`, the approval step is silently skipped.
- `wt ls` — list active worktrees (passes through to `git worktree list`)
- `wt rm <branch>` — remove a worktree with prompts for uncommitted changes,
  an optional merge, and branch deletion. When the branch's upstream
  tracking ref is gone, recommends force delete (assumes squash-/rebase-merge)
- `wt help` — print usage

## Dependencies

- `git` — all worktree operations
- `coreutils` — basic shell utilities
- `direnv` (optional) — when present, `wt add` auto-allows discovered
  `.envrc` files. Missing `direnv` is not an error; the step is skipped.

Shell completions are installed for bash, zsh, fish, and nushell.

## Testing

Run the standalone behavior tests:

```
bash pkgs/wt/tests/test-upstream-gone.sh
bash pkgs/wt/tests/test-add-direnv.sh
bash pkgs/wt/tests/test-remote-matches.sh
```

# wt

Git worktree manager, written in Rust. Keeps all worktrees under a single
`.worktrees/` directory at the repo root (branch names keep their slashes:
`cportela/foo` lives at `.worktrees/cportela/foo`), sets each one up for
work (env files, direnv), and opens a tmux window with panes for claude and
a working shell.

## Commands

- `wt init` — create `.worktrees/` and add it to `.git/info/exclude`.
  Resolves the exclude file via `git rev-parse --git-common-dir`, so it also
  works from inside a worktree.
- `wt add [--no-direnv] [--no-env] [--no-tmux] [--session] <branch>` —
  create a worktree and set it up. Branch resolution matches `git
  checkout`'s DWIM:
    - existing local branch → checks it out;
    - exactly one remote-tracking branch with the same name → creates a
      tracking branch off it;
    - multiple remotes have it → errors with the candidates listed;
    - none of the above → creates a new branch off `HEAD`.

  Setup, in order (each opt-out independent):
    1. copies untracked/excluded `.envrc` files from the main checkout (they
       don't materialize in a fresh worktree when listed in
       `.git/info/exclude` or `.gitignore`);
    2. copies untracked `.env` files the same way (`--no-env` skips);
    3. `direnv allow` on every `.envrc` under the worktree, then primes the
       environment with `direnv exec <wt> true` so the first (possibly slow)
       nix eval happens before any tmux pane spawns (`--no-direnv` skips;
       missing direnv is silently skipped);
    4. inside tmux: opens a new window named after the branch with two
       panes titled `claude` and `shell`, both in the worktree. The claude
       pane gets the text `claude` *typed but not entered* — edit flags,
       press Enter. Pane titles are locked (`allow-set-title off`) so shell
       title escapes don't overwrite them. `--session` creates a detached
       session instead (also works outside tmux); `--no-tmux` skips.
- `wt ls` — list active worktrees (passes through to `git worktree list`).
- `wt rm [--no-tmux] <branch>` — remove a worktree with prompts for
  uncommitted changes, an optional merge, and branch deletion. When the
  branch's upstream tracking ref is gone, recommends force delete (assumes
  squash-/rebase-merge). Cleans up emptied parent directories under
  `.worktrees/` and finally offers to kill the branch's tmux window
  (`--no-tmux` skips). Targets are resolved against `git worktree list`, so
  stale directories are a clean error, not a crash.
- `wt --dry-run …` — print mutating commands instead of executing them
  (read-only queries still run, so the plan reflects real state).
- `wt help` — print usage.

## Completions

bash, zsh, fish, and nushell completions are thin wrappers over the hidden
`wt __complete <worktrees|branches>` helper, which enumerates *registered*
worktrees from `git worktree list --porcelain` — so nested slashed names
complete fully (zsh uses `_multi_parts` for segment-by-segment completion)
and stale directories are never offered.

## Dependencies

Resolved from the user's `PATH` at runtime, deliberately not wrapped into
the Nix closure — wt orchestrates the user's own environment:

- `git` — all worktree operations
- `tmux` (optional) — window/session automation
- `direnv` (optional) — `.envrc` approval and priming; skipped when absent
- `claude` — only ever *typed* into a pane, never executed by wt

## Testing

Unit + hermetic integration tests (real git repo in a tempdir, private tmux
server via `WT_TMUX_SOCKET`, logging PATH shims for direnv/claude):

```
cd pkgs/wt && cargo test
```

`nix build .#wt` runs the same suite in the checkPhase. Set `WT_IT_KEEP=1`
to preserve a failed test's tempdir for post-mortem.

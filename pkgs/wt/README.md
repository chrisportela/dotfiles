# wt

A thin wrapper around `git worktree` that keeps all worktrees under a
single `.worktrees/` directory at the repo root.

## Commands

- `wt init` — create `.worktrees/` and add it to `.git/info/exclude`
- `wt add <branch>` — create a worktree; checks out an existing branch or
  creates a new one off `HEAD`
- `wt ls` — list active worktrees (passes through to `git worktree list`)
- `wt rm <branch>` — remove a worktree with prompts for uncommitted changes,
  an optional merge, and branch deletion. When the branch's upstream
  tracking ref is gone, recommends force delete (assumes squash-/rebase-merge)
- `wt help` — print usage

## Dependencies

- `git` — all worktree operations
- `coreutils` — basic shell utilities

Shell completions are installed for bash, zsh, fish, and nushell.

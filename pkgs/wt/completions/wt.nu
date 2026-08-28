# wt(1) nushell completion — candidates come from `wt __complete`.

def "nu-complete wt-subcommand" [] {
  [
    { value: "init", description: "setup .worktrees and exclude" }
    { value: "add",  description: "create a worktree" }
    { value: "open", description: "reopen tmux workspaces for existing worktrees" }
    { value: "ls",   description: "list active worktrees" }
    { value: "rm",   description: "remove a worktree" }
    { value: "help", description: "show help" }
  ]
}

def "nu-complete wt-branches" [] {
  do -i { ^wt __complete branches } | lines
}

def "nu-complete wt-targets" [] {
  do -i { ^wt __complete targets } | lines
}

# Top-level dispatch so `wt <TAB>` offers subcommands
export extern "wt" [
  command?: string@"nu-complete wt-subcommand"
  ...args: string
  --dry-run    # print planned commands instead of executing
]

# Per-subcommand externs for positional arg completion
export extern "wt init" []
export extern "wt add" [
  branch?: string@"nu-complete wt-branches"
  --no-direnv  # skip direnv allow / devshell priming
  --no-env     # skip copying .env files
  --no-tmux    # skip tmux window creation
  --session    # create a detached tmux session instead
]
export extern "wt open" [
  target?: string@"nu-complete wt-targets"
  --session    # create a detached tmux session instead
  --branch     # treat target strictly as a branch name
  --folder     # treat target strictly as a .worktrees/ folder name
  --path       # treat target strictly as a filesystem path
]
export extern "wt ls" []
export extern "wt rm" [
  target?: string@"nu-complete wt-targets"
  --no-tmux    # skip killing the matching tmux window
  --branch     # treat target strictly as a branch name
  --folder     # treat target strictly as a .worktrees/ folder name
  --path       # treat target strictly as a filesystem path
]
export extern "wt help" []

# wt(1) nushell completion

def "nu-complete wt-subcommand" [] {
  [
    { value: "init", description: "setup .worktrees and exclude" }
    { value: "add",  description: "create a worktree" }
    { value: "ls",   description: "list active worktrees" }
    { value: "rm",   description: "remove a worktree" }
    { value: "help", description: "show help" }
  ]
}

def "nu-complete wt-branches" [] {
  let local_refs = (do -i { git for-each-ref --format='%(refname:short)' refs/heads } | lines)
  let remote_refs = (do -i { git for-each-ref --format='%(refname:lstrip=3)' refs/remotes } | lines)
  $local_refs | append $remote_refs | where $it != "HEAD" | uniq
}

def "nu-complete wt-worktrees" [] {
  let root = (do -i { git rev-parse --show-toplevel } | str trim)
  if ($root | is-empty) { return [] }
  let wtdir = $"($root)/.worktrees"
  if not ($wtdir | path exists) { return [] }
  ls $wtdir | where type == dir | get name | path basename
}

# Top-level dispatch so `wt <TAB>` offers subcommands
export extern "wt" [
  command?: string@"nu-complete wt-subcommand"
  ...args: string
]

# Per-subcommand externs for positional arg completion
export extern "wt init" []
export extern "wt add" [
  branch?: string@"nu-complete wt-branches"
  --no-direnv  # skip direnv allow on .envrc files
]
export extern "wt ls" []
export extern "wt rm" [branch?: string@"nu-complete wt-worktrees"]
export extern "wt help" []

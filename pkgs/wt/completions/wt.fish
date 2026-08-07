# wt(1) fish completion — candidates come from `wt __complete`.

# Disable file completion by default; subcommand-specific rules re-enable dynamic args.
complete -c wt -f

# Subcommands (only when no subcommand chosen yet)
complete -c wt -n __fish_use_subcommand -a init -d 'setup .worktrees and exclude'
complete -c wt -n __fish_use_subcommand -a add  -d 'create a worktree'
complete -c wt -n __fish_use_subcommand -a ls   -d 'list active worktrees'
complete -c wt -n __fish_use_subcommand -a rm   -d 'remove a worktree'
complete -c wt -n __fish_use_subcommand -a help -d 'show help'

# Args
complete -c wt -n '__fish_seen_subcommand_from add' -a '(wt __complete branches)'
complete -c wt -n '__fish_seen_subcommand_from add' -l no-direnv -d 'skip direnv allow / devshell priming'
complete -c wt -n '__fish_seen_subcommand_from add' -l no-env -d 'skip copying .env files'
complete -c wt -n '__fish_seen_subcommand_from add' -l no-tmux -d 'skip tmux window creation'
complete -c wt -n '__fish_seen_subcommand_from add' -l session -d 'create a detached tmux session instead'
complete -c wt -n '__fish_seen_subcommand_from rm'  -a '(wt __complete worktrees)'
complete -c wt -n '__fish_seen_subcommand_from rm'  -l no-tmux -d 'skip killing the matching tmux window'
complete -c wt -l dry-run -d 'print planned commands instead of executing'

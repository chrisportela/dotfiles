function __wt_branches
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null
end

function __wt_worktrees
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    or return
    if test -d "$root/.worktrees"
        for d in $root/.worktrees/*/
            basename $d
        end
    end
end

# Disable file completion by default; subcommand-specific rules re-enable dynamic args.
complete -c wt -f

# Subcommands (only when no subcommand chosen yet)
complete -c wt -n __fish_use_subcommand -a init -d 'setup .worktrees and exclude'
complete -c wt -n __fish_use_subcommand -a add  -d 'create a worktree'
complete -c wt -n __fish_use_subcommand -a ls   -d 'list active worktrees'
complete -c wt -n __fish_use_subcommand -a rm   -d 'remove a worktree'
complete -c wt -n __fish_use_subcommand -a help -d 'show help'

# Args
complete -c wt -n '__fish_seen_subcommand_from add' -a '(__wt_branches)'
complete -c wt -n '__fish_seen_subcommand_from add' -l no-direnv -d 'skip direnv allow on .envrc files'
complete -c wt -n '__fish_seen_subcommand_from rm'  -a '(__wt_worktrees)'

# wt(1) bash completion
_wt() {
  local cur subcmd
  cur="${COMP_WORDS[COMP_CWORD]}"
  subcmd="${COMP_WORDS[1]:-}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "init add ls rm help" -- "$cur") )
    return
  fi

  case "$subcmd" in
    add)
      if [[ $COMP_CWORD -eq 2 ]]; then
        local branches
        branches=$(
          {
            git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
            git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null
          } | grep -vE '^HEAD$' | sort -u
        )
        COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
      fi
      ;;
    rm)
      if [[ $COMP_CWORD -eq 2 ]]; then
        local root wts
        root=$(git rev-parse --show-toplevel 2>/dev/null) || return
        if [[ -d "$root/.worktrees" ]]; then
          wts=$(command ls -1 "$root/.worktrees" 2>/dev/null)
          COMPREPLY=( $(compgen -W "$wts" -- "$cur") )
        fi
      fi
      ;;
  esac
}
complete -F _wt wt

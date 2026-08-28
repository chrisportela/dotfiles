# wt(1) bash completion — candidates come from `wt __complete`.
_wt() {
  local cur subcmd
  cur="${COMP_WORDS[COMP_CWORD]}"
  subcmd="${COMP_WORDS[1]:-}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "init add open ls rm help" -- "$cur") )
    return
  fi

  case "$subcmd" in
    add)
      if [[ "$cur" == --* ]]; then
        COMPREPLY=( $(compgen -W "--no-direnv --no-env --no-tmux --session --dry-run" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$(wt __complete branches 2>/dev/null)" -- "$cur") )
      fi
      ;;
    open)
      if [[ "$cur" == --* ]]; then
        COMPREPLY=( $(compgen -W "--session --branch --folder --path --dry-run" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$(wt __complete targets 2>/dev/null)" -- "$cur") )
      fi
      ;;
    rm)
      if [[ "$cur" == --* ]]; then
        COMPREPLY=( $(compgen -W "--no-tmux --branch --folder --path --dry-run" -- "$cur") )
      else
        COMPREPLY=( $(compgen -W "$(wt __complete targets 2>/dev/null)" -- "$cur") )
      fi
      ;;
  esac
}
complete -F _wt wt

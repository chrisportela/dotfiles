# aws-client-vpn(1) bash completion — candidates come from
# `aws-client-vpn __complete`.
_aws_client_vpn() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]:-}"

  case "$prev" in
    -c | --config)
      COMPREPLY=( $(compgen -W "$(aws-client-vpn __complete configs 2>/dev/null)" -- "$cur") )
      # Profiles kept anywhere else still complete as ordinary paths.
      compopt -o default 2>/dev/null
      return
      ;;
    -e | --endpoint)
      COMPREPLY=( $(compgen -W "$(aws-client-vpn __complete endpoints 2>/dev/null)" -- "$cur") )
      return
      ;;
    -p | --profile)
      COMPREPLY=( $(compgen -W "$(aws-client-vpn __complete profiles 2>/dev/null)" -- "$cur") )
      return
      ;;
    -r | --region)
      COMPREPLY=( $(compgen -W "$(aws-client-vpn __complete regions 2>/dev/null)" -- "$cur") )
      return
      ;;
    --dns)
      COMPREPLY=( $(compgen -W "auto systemd-resolved none" -- "$cur") )
      return
      ;;
    --port | --timeout)
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "$(aws-client-vpn __complete flags 2>/dev/null)" -- "$cur") )
  else
    compopt -o default 2>/dev/null
  fi
}
complete -F _aws_client_vpn aws-client-vpn

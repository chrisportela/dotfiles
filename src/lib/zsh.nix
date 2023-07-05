{ lib, config, ... }: {

  programs.zsh = {
    enable = true;
    enableAutosuggestions = lib.mkDefault false;
    enableCompletion = lib.mkDefault false;
    autocd = lib.mkDefault true;
    # envExtra = ''. "$HOME/.cargo/env"'';
    history = {
      extended = true;
      share = true;
      ignoreDups = false;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
    };

    initExtraBeforeCompInit = ''
      if type brew &>/dev/null
      then
        FPATH="$(brew --prefix)/share/zsh/site-functions:$FPATH"
      fi
    '';

    initExtra = ''
      if [ -e ${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh ]; then
          source ${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh;
      fi # added by Nix installer

      if [[ -f "${config.home.homeDirectory}/.cargo/env" ]]; then
          source "${config.home.homeDirectory}/.cargo/env"
      fi

      if [[ -f "/opt/homebrew/bin/brew" ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      export ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=YES
      source ${../common/iterm2_shell_integration.zsh}

      if [[ "$TERM_PROGRAM" = vscode ]]; then
        export EDITOR=code;
        alias vim=code;
      fi

      if command -v pyenv 1>/dev/null 2>&1; then
        eval "$(pyenv init -)"
      fi

      source ${../common/shell_functions.sh}
    '';
  };
}

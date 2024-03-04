{ lib, config, pkgs, ... }: {
  home.shellAliases =
    let
      git = "${pkgs.git}/bin/git";
      readlink = "${pkgs.coreutils}/bin/readlink";
    in
    {
      "reload" = "[[ -o login ]] && exec $SHELL -l || exec $SHELL";
      "realcd" = "cd $(${readlink} -f .)";

      "g" = "${git} ";
      "gs" = "${git} status ";
      "gl" = "${git} log ";
      "ga" = "${git} add ";
      "gb" = "${git} branch";
      "push" = "${git} push ";
      "pusho" = "${git} push origin HEAD";
      "fpush" = "${git} push --force-with-lease";
      "pull" = "${git} pull --ff --tags --prune";
      "fpull" = "${git} pull --force --ff --tags --prune";
      # "grh" = "${git} reset --hard origin/HEAD";

      # These are just nice helpers for whatever "terraform" is in the environment.
      "t" = "terraform";
      "tf" = "terraform";
      "tip" = "terraform init && terraform plan -out plan.out";
      "tp" = "terraform plan -out plan.out";
      "tap" = "terraform apply plan.out";
    };

  programs.fzf = {
    enable = lib.mkDefault true;
    enableZshIntegration = lib.mkDefault true;
    defaultCommand = "fd --type f";
    defaultOptions = [ "--height 40%" "--border" ];
    fileWidgetCommand = "fd --type f";
    fileWidgetOptions = [ "--preview 'head {}'" ];
    changeDirWidgetCommand = "fd --type d";
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
    tmux.enableShellIntegration = lib.mkDefault true;
    historyWidgetOptions = [ "--sort" "--exact" ];
  };

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
      source ${./iterm2_shell_integration.zsh}

      if [[ "$TERM_PROGRAM" = vscode ]]; then
        export EDITOR=code;
        alias vim=code;
      fi

      if command -v pyenv 1>/dev/null 2>&1; then
        eval "$(pyenv init -)"
      fi

      source ${./shell_functions.sh}

      notify() {
        "${pkgs.notify-desktop}/bin/notify-desktop" -u critical "Command finished: $?" "!!" 1>/dev/null
      }
    '';
  };

  programs.starship = {
    enable = lib.mkDefault true;
    enableZshIntegration = true;
    settings =
      let
        username = config.home.username;
      in
      {
        add_newline = false;
        format = lib.concatStrings [
          "$env_var"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_commit"
          "$git_state"
          "$git_metrics"
          "$git_status"
          "$hg_branch"
          "$kubernetes"
          "$docker_context"
          "$package"
          "$c"
          "$cmake"
          "$helm"
          "$terraform"
          "$nix_shell"
          "$memory_usage"
          "$gcloud"
          "$custom"
          "$sudo"
          "$cmd_duration"
          "$line_break"
          "$jobs"
          "$time"
          "$status"
          "$shell"
          "$character"
        ];
        cmd_duration = {
          min_time = 10000;
          format = " took [$duration]($style)";
        };
        directory = {
          truncation_length = 5;
          format = "in [$path]($style)[$lock_symbol]($lock_style) ";
        };
        kubernetes = {
          disabled = false;
        };
        package.disabled = true;
        gcloud = {
          disabled = true;
          format = "on [$symbol$account(@$domain)(\($region\))]($style) ";
        };
        hostname = {
          ssh_only = false;
          ssh_symbol = "🌐 ";
          format = "on [$ssh_symbol$hostname]($style) ";
          style = "dimmed italic green";
        };
        env_var = {
          username = {
            format = "[$env_value]($style) ";
            style = "dimmed purple";
          };
          workspace = {
            variable = "CODER_WORKSPACE_NAME";
            format = "on [$env_value]($style) ";
            style = "dimmed italic green";
          };
        };
      };
  };
}

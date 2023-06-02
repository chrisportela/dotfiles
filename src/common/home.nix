({ pkgs, lib, config, ... }: {
  imports = [ ];
  home.username = lib.mkDefault "cmp";
  home.homeDirectory = lib.mkDefault if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";
  home.stateVersion = lib.mkDefault "22.11";
  home.packages = with pkgs; [
    curl
    ripgrep
    ripgrep-all
    du-dust
  ];

  home.shellAliases = {
    "reload" = "[[ -o login ]] && exec $SHELL -l || exec $SHELL";

    "g" = "${pkgs.git}/bin/git ";
    "gs" = "${pkgs.git}/bin/git status ";
    "gl" = "${pkgs.git}/bin/git log ";
    "ga" = "${pkgs.git}/bin/git add ";
    "gb" = "${pkgs.git}/bin/git branch";
    "push" = "${pkgs.git}/bin/git push ";
    "pusho" = "${pkgs.git}/bin/git push origin HEAD";
    "fpush" = "${pkgs.git}/bin/git push --force-with-lease";
    "pull" = "${pkgs.git}/bin/git pull --ff --tags --prune";
    "fpull" = "${pkgs.git}/bin/git pull --force --ff --tags --prune";
    # "grh" = "git reset --hard origin/HEAD";

    # These are just nice helpers for whatever "terraform" is in the environment.
    "t" = "terraform";
    "tf" = "terraform";
    "tip" = "terraform init && terraform plan -out plan.out";
    "tp" = "terraform plan -out plan.out";
    "tap" = "terraform apply plan.out";
  };

  programs.home-manager.enable = true;

  programs = {
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "fd --type f";
      defaultOptions = [ "--height 40%" "--border" ];
      fileWidgetCommand = "fd --type f";
      fileWidgetOptions = [ "--preview 'head {}'" ];
      changeDirWidgetCommand = "fd --type d";
      changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
      tmux.enableShellIntegration = true;
      historyWidgetOptions = [ "--sort" "--exact" ];
    };

    htop.enable = lib.mkDefault true;

    jq.enable = lib.mkDefault true;

    bat.enable = lib.mkDefault true;

    exa = {
      enable = lib.mkDefault true;
      enableAliases = lib.mkDefault true;
    };

    nushell.enable = lib.mkDefault true;

    gh = {
      enable = lib.mkDefault true;
      # Note: copy to places you want gh settings set
      settings = {
        git_protocol = lib.mkDefault "https";
      };
    };

    git = {
      enable = true;
      delta.enable = true;
      userName = lib.mkDefault "Chris Portela";
      userEmail = lib.mkDefault "chris@chrisportela.com";
    };

    neovim = {
      enable = lib.mkDefault true;
      viAlias = lib.mkDefault true;
      vimAlias = lib.mkDefault true;
      vimdiffAlias = lib.mkDefault true;
      extraConfig = ''
        set nocompatible
        set nobackup
      '';
      plugins = with pkgs.vimPlugins; [ vim-nix ];
    };

    tmux = {
      enable = true;
      #shortcut = "a";
      keyMode = "vi";
      baseIndex = 1;
      #terminal = "xterm-256color";
      clock24 = true;
      newSession = true;
      secureSocket = false;
      prefix = "C-a";
      terminal = "screen-256color";
      escapeTime = 50;
      historyLimit = 30000;
      extraConfig = ''
        set-option -g allow-passthrough on;
      '';
      plugins = with pkgs.tmuxPlugins; [ ];
    };

    bash.enable = true;
    readline = {
      enable = true;
      extraConfig = (builtins.readFile ./inputrc);
    };
    zsh = {
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
      '';
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    starship = {
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
  };
})

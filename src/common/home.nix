({ pkgs, lib, config, ... }: {
  imports = [
    ../lib/fzf.nix
    ../lib/neovim.nix
    ../lib/starship.nix
    ../lib/zsh.nix
    ../lib/tmux.nix
  ];
  home.username = lib.mkDefault "cmp";
  home.homeDirectory = lib.mkDefault (if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}");
  home.stateVersion = lib.mkDefault "22.11";
  home.packages = with pkgs; [
    curl
    ripgrep
    ripgrep-all
    du-dust
    vault
    nixpkgs-fmt
  ];

  home.shellAliases = {
    "reload" = "[[ -o login ]] && exec $SHELL -l || exec $SHELL";
    "realcd" = "cd $(${pkgs.coreutils}/bin/readlink -f .)";

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


    bash.enable = true;
    readline = {
      enable = true;
      extraConfig = (builtins.readFile ./inputrc);
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

  };
})

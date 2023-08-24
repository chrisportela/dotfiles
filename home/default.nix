({ pkgs, lib, config, ... }:
with lib;
{
  imports = [
    ./shell.nix
    ./neovim.nix
    ./tmux.nix
  ];

  home = {
    homeDirectory = (if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}");
    stateVersion = mkDefault "22.11";
    packages = with pkgs; [
      curl
      du-dust
      ripgrep
      ripgrep-all
      vault
      nixpkgs-fmt
    ];

    shellAliases = {
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
  };


  programs = {
    home-manager.enable = true;

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    htop.enable = true;

    jq.enable = true;

    bat.enable = true;

    exa = {
      enable = true;
      enableAliases = true;
    };

    nushell.enable = true;

    gh = {
      enable = true;
      # Note: copy to places you want gh settings set
      settings = {
        git_protocol = "https";
      };
    };

    git = {
      enable = true;
      delta.enable = true;
      userName = mkDefault "Chris Portela";
      userEmail = mkDefault "chris@chrisportela.com";
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

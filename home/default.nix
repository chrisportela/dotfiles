{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./modules/nixpkgs.nix
    ./modules/difftastic.nix
    ./modules/experiment.nix
    ./modules/desktop.nix
    ./modules/shell
    ./modules/tmux
  ];

  home = {
    homeDirectory = (
      if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
    );
    stateVersion = lib.mkDefault "22.11";
    packages = with pkgs; [
      curl
      dogdns
      doggo
      dust
      ripgrep

      nixfmt-rfc-style
      git-annex
      gnupg
      ntfy-sh
      rclone
      git-annex-remote-rclone
      nixd
    ];
  };

  programs = {
    home-manager.enable = true;

    fd.enable = true;
    ripgrep.enable = true;
    btop.enable = true;
    htop.enable = true;
    jq.enable = true;
    bat.enable = true;
    eza.enable = true;
    nushell.enable = true;

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
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
      plugins = with pkgs.vimPlugins; [
        fugitive
        surround
        vim-nix
      ];
    };

    gh = {
      enable = true;

      settings = {
        git_protocol = "https";
      };
    };

    git = {
      enable = true;
      delta.enable = true;
      userName = lib.mkDefault "Chris Portela";
      userEmail = lib.mkDefault "chris@chrisportela.com";
      package = pkgs.gitFull;
      extraConfig = {
        credential.helper = if pkgs.stdenv.isLinux then "libsecret" else "osxkeychain";
        safe.directory = [ ];
      };
    };
    difftastic.enable = true;

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

  };
}

({ pkgs, lib, config, ... }: with lib; {
  imports = [
    ./shell.nix
    ./tmux.nix
    ./modules/difftastic.nix
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "vault-bin"
  ];

  home = {
    homeDirectory = (if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}");
    stateVersion = mkDefault "22.11";
    packages = with pkgs; [
      curl
      dogdns
      doggo
      du-dust
      ripgrep
      vault-bin
      nixpkgs-fmt
      git-annex
      ntfy-sh
      rclone
      git-annex-remote-rclone
    ];
  };

  programs = {
    home-manager.enable = true;

    fd.enable = true;
    ripgrep.enable = true;
    btop.enable = true;

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
      plugins = with pkgs.vimPlugins; [ vim-nix ];
    };

    htop.enable = true;

    jq.enable = true;

    bat.enable = true;

    eza.enable = true;

    nushell.enable = true;

    gh = {
      enable = true;

      settings = {
        git_protocol = "https";
      };
    };

    git = {
      enable = true;
      delta.enable = true;
      userName = mkDefault "Chris Portela";
      userEmail = mkDefault "chris@chrisportela.com";
      package = pkgs.gitFull;
      extraConfig = {
        credential.helper = "libsecret";
        # safe.directory = [ ];
      };
    };
    difftastic.enable = true;

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

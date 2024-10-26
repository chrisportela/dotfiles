({ pkgs, lib, config, ... }: {
  imports = [
    ./modules/nixpkgs.nix
    ./modules/difftastic.nix
    ./shell.nix
    ./tmux.nix
  ];

  allowedUnfree = [ "vault-bin" ];

  home = {
    homeDirectory = (if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}");
    stateVersion = lib.mkDefault "22.11";
    packages = with pkgs; [
      curl
      dogdns
      doggo
      du-dust
      ripgrep
      coder
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

    # Tryouts
    # zed-editor.enable = true;
    pyenv.enable = false;
    poetry.enable = true;
    # ruff.enable = true; # need settings set
    zk.enable = true;
    vifm.enable = true;
    kitty.enable = true;
    rio.enable = true;
    neovide = {
      enable = true;
      settings = {
        # basic example settings
        fork = false;
        frame = "full";
        idle = true;
        maximized = false;
        neovim-bin = "/usr/bin/nvim";
        no-multigrid = false;
        srgb = false;
        tabs = true;
        theme = "auto";
        title-hidden = true;
        vsync = true;
        wsl = false;

        font = {
          normal = [ ];
          size = 14.0;
        };
      };
    };
    fastfetch.enable = true;
    bun.enable = true;
    ranger.enable = true;
    # arrpc.enable = false; # https://arrpc.openasar.dev/
    mise.enable = false; # https://mise.jdx.dev/about.html
    granted.enable = false; # https://github.com/common-fate/granted
    bacon.enable = false; # https://github.com/Canop/bacon background rust checker
    carapace = {
      # https://github.com/carapace-sh/carapace smart shell complete
      enable = false;
      # enableBashIntegration = false;
      # enableFishIntegration = false;
      # enableNushellIntegration = false;
      # enableZshIntegration = false;
    };
    yazi.enable = false; # https://github.com/sxyazi/yazi
    qcal.enable = false; # https://git.sr.ht/~psic4t/qcal
    # git-sync.enable = false; # https://github.com/simonthum/git-sync
    # https://github.com/pimalaya?view_as=public
    comodoro.enable = false;
    # See Also: services.comodoro.enable = false;
    git-credential-oauth.enable = false;
    # git-credential-manager.enable = false;
    # git-credential-keepassxc.enable = false;
    jujutsu.enable = false;
    rbenv.enable = false;
    yt-dlp.enable = false;
    # --- end

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
      plugins = with pkgs.vimPlugins; [ fugitive surround vim-nix ];
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

{ lib, pkgs, ... }: with lib; {
  imports = [ ];

  config = {
    # boot.tmp.cleanOnBoot = true;
    # zramSwap.enable = false;

    time.timeZone = mkDefault "Etc/UTC";

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    environment.systemPackages = with pkgs; [
      nixpkgs-fmt
      curl
      git
    ];

    security.sudo.wheelNeedsPassword = mkDefault true;

    users = {
      defaultUserShell = pkgs.zsh;

      groups.cmp = { };

      users = {
        cmp = {
          isNormalUser = true;
          group = "cmp";
          extraGroups = [ "wheel" ];
          packages = [ ];
          openssh.authorizedKeys.keys = (import ../sshKeys.nix).cmp;
        };
      };
    };


    programs = {
      zsh = {
        enable = true;
        enableCompletion = true;
        enableBashCompletion = true;
      };

      neovim = {
        enable = mkDefault true;
        vimAlias = mkDefault true;
        viAlias = mkDefault true;
        defaultEditor = mkDefault true;
      };

      tmux = {
        enable = true;
        terminal = "screen-256color";
        clock24 = true;
        baseIndex = 1;
        newSession = true;
        plugins = with pkgs.tmuxPlugins; [ sensible ];
      };
    };

    system.stateVersion = mkDefault "23.05";
  };
}

{ lib, pkgs, ... }: with lib; {
  imports = [ ];

  config = {
    # boot.tmp.cleanOnBoot = true;
    # zramSwap.enable = false;

    time.timeZone = mkDefault "Etc/UTC";

    i18n.defaultLocale = "en_US.UTF-8";

    environment.systemPackages = with pkgs; [
      nixpkgs-fmt
      curl
      git
    ];

    security.sudo.wheelNeedsPassword = mkDefault false;

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

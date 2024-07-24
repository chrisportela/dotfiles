{ lib, pkgs, config, ... }:
let
  cfg = config.chrisportela.common;
  sshKeys = (import ../../sshKeys.nix);
in
{
  options.chrisportela.common = {
    enable = lib.mkEnable "Common configuration";
    enableDualbootSettings = lib.mkEnable "Dual Boot Settings";
  };

  config = lib.mkIf cfg.enable {
    imports = [
      ./nixpkgs.nix
    ];

    time.timeZone = lib.mkDefault "Etc/UTC";
    time.hardwareClockInLocalTime = lib.mkIf cfg.enableDualbootSettings true;

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

    environment.systemPackages = with pkgs; [ curl git ];

    security.sudo.wheelNeedsPassword = mkDefault true;

    # users = {
    #   defaultUserShell = pkgs.zsh;

    #   groups.cmp = { };

    #   users = {
    #     cmp = {
    #       isNormalUser = true;
    #       group = "cmp";
    #       extraGroups = [ "wheel" ];
    #       packages = [ ];
    #       openssh.authorizedKeys.keys = sshKeys.users.cmp;
    #     };
    #   };
    # };


    programs = {
      zsh = {
        enable = true;
        enableCompletion = true;
        enableBashCompletion = true;
      };

      git = {
        enable = true;
        lfs.enable = true;
      };

      neovim = {
        enable = true;
        vimAlias = true;
        viAlias = true;
        defaultEditor = true;
      };

      tmux = {
        enable = true;
        terminal = "screen-256color";
        clock24 = true;
        baseIndex = 0;
        newSession = true;
        plugins = with pkgs.tmuxPlugins; [ sensible ];
      };
    };

    system.stateVersion = lib.mkDefault "24.05";
  };
}

{ lib, config, pkgs, ... }: {
  imports = [
    ./base.nix
    ./nix.nix
    ./openssh.nix
  ];

  options = {
    base = {
      # For migration flags
    };
  };

  config = {

    boot.tmp.cleanOnBoot = true;
    zramSwap.enable = false;

    time.timeZone = lib.mkDefault "Etc/UTC";

    i18n.defaultLocale = "en_US.UTF-8";
    console = {
      font = "Lat2-Terminus16";
      keyMap = "us";
    };

    services.xserver.enable = false;
    sound.enable = false;
    hardware.pulseaudio.enable = false;

    services = {
      avahi = {
        enable = false;
        publish = {
          enable = true;
          addresses = true;
          workstation = true;
        };
      };

      resolved = {
        enable = false;
        fallbackDns = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
      parted
    ];

    security.sudo.wheelNeedsPassword = false;

    users = {
      defaultUserShell = pkgs.zsh;

      groups.cmp = { };

      users = {
        cmp = {
          isNormalUser = true;
          group = "cmp";
          extraGroups = [ "wheel" ];
          packages = [ ];
          openssh.authorizedKeys.keys = (import ../../sshKeys.nix).cmp;
        };
      };
    };

    system.stateVersion = lib.mkDefault "23.05";
  };
}

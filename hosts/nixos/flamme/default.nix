{
  pkgs,
  config,
  lib,
  ...
}:
{
  allowedUnfree = [
    "ookla-speedtest"
  ];

  cafecitocloud.enable = true;

  chrisportela = {
    network.speedtest-utils = true;
    gaming.enable = true;
    agent-vms = {
      enable = true;
      nat.externalInterface = "eno1";
      user.authorizedKeys = (import ../../../lib/ssh-keys.nix).users.cmp;
    };
  };

  networking = {
    hostId = "ebcd55e8";
    wireless.enable = lib.mkForce false;
  };
  systemd.network.wait-online.enable = false;

  # GNOME
  services.xserver = {
    enable = true;
    dpi = 180;
    desktopManager.gnome.enable = true;
    displayManager.gdm.enable = true;
  };
  services.displayManager.sddm.enable = false;

  services.logind.lidSwitchExternalPower = "ignore";
  services.flatpak.enable = true;

  users.users.cmp = {
    extraGroups = [
      "networkmanager"
      "wheel"
      "tss"
    ];
    packages = with pkgs; [ firefox ];
  };
}

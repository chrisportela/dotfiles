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
    network = {
      speedtest-utils = true;
      mDNS = true;
    };
    gaming.enable = true;
    agent-vms = {
      enable = true;
      nat.externalInterface = "eno1";
      defaults.claude = true;
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
  };
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.sddm.enable = false;

  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
  services.flatpak.enable = true;

  # Virtualization
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
      };
    };
    docker.enable = true;
  };
  programs.virt-manager.enable = true;

  # Cross-compilation
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "armv6l-linux"
  ];

  nix.settings.trusted-users = [
    "root"
    "cmp"
  ];

  users.users.cmp = {
    extraGroups = [
      "networkmanager"
      "wheel"
      "tss"
      "libvirtd"
      "docker"
    ];
    packages = with pkgs; [ firefox ];
  };
}

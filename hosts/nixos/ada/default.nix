{
  pkgs,
  config,
  lib,
  ...
}:
{
  allowedUnfree = [
    "ookla-speedtest"
    "claude-code"
    "nvidia-persistenced"
    "nvidia-settings"
    "nvidia-x11"
  ];

  cafecitocloud.enable = true;

  chrisportela = {
    network = {
      speedtest-utils = true;
      mDNS = true;
    };
    gaming.enable = true;
  };

  networking = {
    hostId = "5bc6e263";
    bridges."br0".interfaces = [ "wlo1" ];
    interfaces.br0.useDHCP = true;
    interfaces.enp6s0.useDHCP = true;
    interfaces.wlo1.useDHCP = true;
    firewall.trustedInterfaces = [ "docker0" ];
  };

  systemd.services.tailscaled.after = [ "NetworkManager-wait-online.service" ];
  systemd.network.wait-online = {
    enable = true;
    anyInterface = true;
    ignoredInterfaces = [ "tailscale0" ];
  };

  environment.systemPackages = with pkgs; [
    nvtopPackages.full
    psmisc
    rclone
    git-annex-remote-rclone
    reptyr
    rmlint
    wget
    curl
    openssl
    attic-client

    # KDE
    kdePackages.plasma-thunderbolt
    kdePackages.kate

    rclone-browser
    cachix
    virt-manager
    virt-viewer
    spice
    spice-gtk
    spice-protocol
    virtio-win
    win-spice
    pkgs.disko
  ];

  # KDE Plasma 6
  services.xserver.dpi = 180;
  services.desktopManager.plasma6.enable = true;
  services.displayManager = {
    sddm.enable = true;
    sddm.enableHidpi = true;
    sddm.settings.General = { };
    sddm.wayland.enable = true;
  };
  security.pam.services.kwallet.enableKwallet = true;

  programs.firefox.enable = true;
  programs.localsend = {
    enable = true;
    openFirewall = true;
  };

  # Virtualization
  virtualisation = {
    virtualbox.host.enable = true;
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
      };
    };
    docker = {
      enable = true;
      # storageDriver = "zfs";
    };
    oci-containers.backend = "docker";
  };
  services.spice-vdagentd.enable = true;
  programs.virt-manager.enable = true;
  programs.dconf.enable = true;
  boot.extraModprobeConfig = "options kvm_intel nested=1";

  services.vscode-server.enable = lib.mkDefault true;

  # ZFS
  services.zfs = {
    trim = {
      enable = true;
      interval = "daily";
    };
    autoScrub = {
      enable = true;
      pools = [ "zroot" ];
      interval = "monthly";
    };
  };

  # NVIDIA + Docker
  hardware.nvidia-container-toolkit.enable = true;

  # Cross-compilation
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "armv6l-linux"
  ];
  boot.binfmt.registrations."aarch64-linux".interpreter =
    let
      fastQemu = pkgs.writeShellScript "qemu-aarch64-fast" ''
        exec ${pkgs.qemu-user}/bin/qemu-aarch64 -cpu max -tb-size 536870912 "$@"
      '';
      wrapper = pkgs.wrapQemuBinfmtP "qemu-aarch64-binfmt-P-fast" fastQemu;
    in
    "${wrapper}/bin/qemu-aarch64-binfmt-P-fast";

  nix.settings.trusted-users = [
    "root"
    "cmp"
  ];

  users.users.cmp.extraGroups = [
    "networkmanager"
    "wheel"
    "libvirtd"
    "ddc"
    "docker"
  ];
}

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

    # CI runner for git.cafecito.cloud: shares the x86_64-linux `nix-docker`
    # queue with lucy (infra repo). Jobs run in containers with the host
    # /nix/store + nix-daemon shared, so aarch64 binfmt builds work too.
    forgejo-runner = {
      enable = true;
      instances.flamme-docker = {
        backend = "docker";
        # Printed by `forgejo-cli actions register` on liara (also visible in
        # the forgejo DB's action_runner table). Not sensitive.
        uuid = "07cf9508-59bd-4e95-89cf-fcb28aa0c3fe";
        tokenFile = config.age.secrets.flamme-forgejo-runner-token.path;
        labels = [
          "flamme-docker:docker://docker.gitea.com/runner-images:ubuntu-latest"
          "nix-docker:docker://docker.gitea.com/runner-images:ubuntu-latest"
        ];
        docker.shareHostNixStore = true;
        docker.shareHostCAs = true;
      };
    };
  };

  age.secrets.flamme-forgejo-runner-token = {
    # TOKEN=<40-hex> env format, read by the runner service's EnvironmentFile.
    file = ../../../secrets/flamme-forgejo-runner-token.age;
    mode = "400";
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

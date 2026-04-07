{ pkgs, config, lib, ... }:
{
  allowedUnfree = [
    "ookla-speedtest"
    "elasticsearch"
    "claude-code"
    "nvidia-persistenced"
    "nvidia-settings"
    "nvidia-x11"
  ];

  cafecitocloud = {
    enable = true;
    enableACME = true;
  };

  chrisportela = {
    network = {
      speedtest-utils = true;
      mDNS = true;
    };
    ftp = {
      enable = false;
      directory = "/mnt/tank/photo-dump";
      domain = "ftp.ada.i.cafecito.cloud";
    };
    samba = {
      enable = true;
      openFirewall = true;
      users = [ "cmp" ];
      passwordFile = config.age.secrets.ada-samba-passwords.path;
      shares = {
        photography = {
          type = "private";
          browseable = true;
          path = "/home/cmp/tank/photography";
          users = [ "cmp" ];
          createDir = false;
        };
        home-shared = {
          type = "private";
          browseable = true;
          path = "/home/cmp/shared";
          users = [ "cmp" ];
        };
        tank-shared = {
          type = "private";
          browseable = true;
          path = "/mnt/tank/shared";
          users = [ "cmp" ];
        };
        tank-public = {
          type = "public";
          path = "/mnt/tank/public";
          users = [ "cmp" ];
        };
      };
    };
    gaming.enable = true;
    local-llm.enable = true;
    agent-vms = {
      enable = true;
      nat.externalInterface = "enp6s0";
      defaults.claude = true;
      user.authorizedKeys = (import ../../../lib/ssh-keys.nix).users.cmp ++ [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILsqpaOSjCbxoTry3oYRHElBMbnFvZVVa5sxjbTZO/lX cmp@ada"
      ];
    };
  };

  age.secrets.ada-samba-passwords.file = ../../../secrets/ada-samba-passwords.age;

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

  # Elasticsearch (disabled)
  services.elasticsearch = {
    enable = false;
    listenAddress = "127.0.0.1";
    port = 9200;
    single_node = true;
    extraConf = ''
      xpack.security.enabled: true
      xpack.security.authc.api_key.enabled: true
    '';
  };

  virtualisation.oci-containers.containers.kibana-test = {
    autoStart = false;
    image = "docker.elastic.co/kibana/kibana:7.17.24";
    volumes = [
      "${config.users.users.cmp.home}/.config/kibana/:/usr/share/kibana/config/"
      "${config.users.users.cmp.home}/.local/share/kibana:/usr/share/kibana/data"
    ];
    extraOptions = [
      "--network=host"
      "--add-host=host.containers.internal:host-gateway"
    ];
    environment = {
      SERVER_NAME = "kibana-test.ada.i.cafecito.cloud";
      ELASTICSEARCH_HOSTS = "http://127.0.0.1:9200";
    };
  };

  services.nginx = {
    enable = true;
    clientMaxBodySize = "20m";
    virtualHosts."kibana.ada.i.cafecito.cloud" = {
      forceSSL = true;
      enableACME = true;
      locations."/".proxyPass = "http://127.0.0.1:5601";
      locations."/".recommendedProxySettings = true;
      extraConfig = ''
        access_log /var/log/nginx/kiabana-cafeito_cloud.access.log;
        error_log /var/log/nginx/kibana-cafeito_cloud.error.log;
      '';
    };
  };
  users.users.nginx.extraGroups = [ "acme" ];

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

  nix.settings.trusted-users = [ "root" "cmp" ];

  users.users.cmp.extraGroups = [
    "networkmanager"
    "wheel"
    "libvirtd"
    "ddc"
    "docker"
  ];
}

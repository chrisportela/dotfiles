{ inputs, nixos ? inputs.nixos, overlays ? [ ], system ? "x86_64-linux", ... }:
let
  nginx = { ... }: { };
in
nixos.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs system;
    nixpkgs = nixos;
  };

  modules = [
    inputs.vscode-server.nixosModules.default
    ../hardware/ada.nix

    ../modules/nixpkgs.nix
    ../modules/common.nix
    ../modules/network.nix
    ../modules/openssh.nix
    ../modules/cafecitocloud
    ../modules/gaming.nix
    ../modules/local-llm

    ({ pkgs, config, lib, ... }: {

      allowedUnfree = [
        "1password"
        "1password-cli"
        "ookla-speedtest"
        "elasticsearch"

        # Must include because gaming is only enabled in desktop mode
        "nvidia-persistenced"
        "nvidia-settings"
        "nvidia-x11"
      ];

      cafecitocloud = {
        enable = true;
        enableACME = true;
      };

      chrisportela = {
        common.enable = true;
        network = {
          enable = true;
          speedtest-utils = true;
          tailscale = {
            enable = true;
            ssh = true;
          };
        };
        gaming.enable = true;
        local-llm.enable = true;
      };

      services.pcscd.enable = true; # For configuring Yubikey

      # Enable networking
      networking = {
        hostName = "ada";
        hostId = "5bc6e263";

        # wireless.enable = true; # Enables wireless support via wpa_supplicant.
        dhcpcd.enable = false;
        useDHCP = false;
        useNetworkd = true;
        networkmanager.enable = true;
        # networkmanager.unmanaged = [ "tailscale0" "docker0" ];

        interfaces.enp6s0.useDHCP = true;
        interfaces.wlo1.useDHCP = true;

        nftables.enable = true;
        nftables.checkRuleset = true;
        firewall = {
          enable = true;
          allowedTCPPorts = config.services.openssh.ports;
          allowedUDPPorts = [ config.services.tailscale.port ];
          trustedInterfaces = [ "tailscale0" "docker0" ];
        };
      };

      systemd.services.tailscaled.after = [ "NetworkManager-wait-online.service" ];

      # Prevent wait-online from stopping boot or switching config
      boot.initrd.systemd.network.wait-online = {
        enable = false;
        anyInterface = true;
        ignoredInterfaces = [ "tailscale0" ];
      };
      systemd.network.wait-online = {
        enable = true;
        anyInterface = true;
        ignoredInterfaces = [ "tailscale0" ];
      };

      environment.systemPackages = with pkgs; [
        btop
        nvtopPackages.full
        psmisc
        rclone
        git-annex-remote-rclone
        quickemu

        # Hardware
        lm_sensors
        pciutils
        glxinfo
        hdparm

        # Network
        inetutils
        nftables
        tcpdump
        traceroute
      ];

      time.timeZone = lib.mkForce "America/New_York";

      services.xserver = {
        # Enable the X11 windowing system.
        # enable = true;

        dpi = 180;

        # Configure keymap in X11
        xkb = {
          layout = "us";
          variant = "";
        };

        # Enable the KDE Plasma Desktop Environment.
        # desktopManager.plasma5.enable = true;
        # desktopManager.plasma5.useQtScaling = true;
      };

      # plasma6
      services.desktopManager.plasma6.enable = true;

      services.displayManager = {
        sddm.enable = true;
        sddm.enableHidpi = true;
        sddm.settings = {
          General = {
            GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2,QT_FONT_DPI=192";
          };
        };
        sddm.wayland.enable = true;
      };
      programs.xwayland.enable = true;

      services.printing.enable = false;

      # Enable sound with pipewire.
      sound.enable = true;
      hardware.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      programs._1password.enable = true;
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = [ "cmp" ];
      };
      security.pam.services.kwallet.enableKwallet = true;

      virtualisation = {
        virtualbox.host.enable = true;
        libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm;
            ovmf = {
              enable = true;
              packages = [ pkgs.OVMFFull.fd ];
            };
            swtpm.enable = true;
          };
        };
      };
      programs.dconf.enable = true; # For libvirtd

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
      };


      boot.plymouth = {
        enable = true;
        # logo = "";
        # theme = "bgrt";
      };

      services.vscode-server.enable = lib.mkDefault true;

      services.zfs = {
        trim = {
          enable = true;
          # interval = "daily";
        };

        autoScrub = {
          enable = true;
          pools = [ "spool" "tank" ];
          interval = "monthly";
        };

      };

      virtualisation = {
        docker = {
          enable = true;
          # enableNvidia = true;# Deprecated
          storageDriver = "zfs";
        };
        # TODO: switch to podman
        oci-containers.backend = "docker";
      };

      services.elasticsearch = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9200;
        single_node = true;
        extraConf = ''
          xpack.security.enabled: true
          xpack.security.authc.api_key.enabled: true
        '';
      };

      # TODO ensure kibana folders are created
      virtualisation.oci-containers.containers.kibana-test = {
        autoStart = true;
        image = "docker.elastic.co/kibana/kibana:7.17.24";
        volumes = [
          "${config.users.users.cmp.home}/.config/kibana/:/usr/share/kibana/config/"
          "${config.users.users.cmp.home}/.local/share/kibana:/usr/share/kibana/data"
        ];
        extraOptions = [ "--network=host" "--add-host=host.containers.internal:host-gateway" ];
        environment = {
          SERVER_NAME = "kibana-test.ada.i.cafecito.cloud";
          # SERVER_BASEPATH = "";
          ELASTICSEARCH_HOSTS = "http://127.0.0.1:9200";
        };
      };

      services.nginx.virtualHosts = {
        "kibana.ada.i.cafecito.cloud" = {
          forceSSL = true;
          enableACME = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:5601";
            recommendedProxySettings = true;
            # extraConfig = ''
            #   proxy_set_header Host localhost:11434;
            # '';
          };

          extraConfig = ''
            access_log /var/log/nginx/kiabana-cafeito_cloud.access.log;
            error_log /var/log/nginx/kibana-cafeito_cloud.error.log;
          '';
        };
      };

      services.nginx.enable = true;
      users.users.nginx.extraGroups = [ "acme" ];

      users.users.cmp = {
        extraGroups = [
          "networkmanager"
          "wheel"
          "libvirtd"
          "ddc"
          "docker"
        ];

        packages = with pkgs; [
          firefox
          kate
          virt-manager
          rclone-browser

        ];
      };

      system.stateVersion = "23.05";
    })
  ];
}

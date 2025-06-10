{
  inputs,
  nixos ? inputs.nixos,
  overlays ? [ ],
  system ? "x86_64-linux",
  ...
}:
let
  nginx = { ... }: { };
in
nixos.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs system overlays;
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
    ../modules/ftp.nix

    (
      {
        pkgs,
        config,
        lib,
        ...
      }:
      {

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
          ftp = {
            enable = false;
            directory = "/mnt/tank/photo-dump";
            domain = "ftp.ada.i.cafecito.cloud";
          };
          gaming.enable = true;
          local-llm.enable = true;
        };

        # tpm
        security.tpm2.enable = true;
        security.tpm2.pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
        security.tpm2.tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
        # users.users.cmp.extraGroups = [ "tss" ]; # tss group has access to TPM devices
        # Enroll: sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0 /dev/nvme0n1p2
        # pcrs=0+7 if secure booted

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
          # networkmanager.unmanaged = [ "br0" "virbr0" ];

          bridges = {
            "br0" = {
              #interfaces = [ "enp6s0" ];
              interfaces = [ "wlo1" ];
            };
          };
          interfaces.br0.useDHCP = true;
          interfaces.enp6s0.useDHCP = true;
          interfaces.wlo1.useDHCP = true;

          nftables.enable = true;
          nftables.checkRuleset = true;
          firewall = {
            enable = true;
            allowedTCPPorts = config.services.openssh.ports;
            allowedUDPPorts = [ config.services.tailscale.port ];
            trustedInterfaces = [
              "tailscale0"
              "docker0"
            ];
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
          #quickemu
          reptyr

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

          # KDE
          kdePackages.plasma-thunderbolt
          #kdePackages.yakuake
          #kdePackages.xdg-desktop-portal-kde
          #kdePackages.tokodon
          #kdePackages.syntax-highlighting
          #kdePackages.sweeper
          kdePackages.kate

          rclone-browser
          cachix
          virt-manager
          virt-viewer
          spice
          spice-gtk
          spice-protocol
          win-virtio
          win-spice

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
              # GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2,QT_FONT_DPI=192";
            };
          };
          sddm.wayland.enable = true;
        };
        programs.xwayland.enable = true;

        services.printing.enable = false;

        # Enable sound with pipewire.
        hardware.pulseaudio.enable = false;
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        programs.firefox = {
          enable = true;
        };

        programs.localsend = {
          enable = true;
          openFirewall = true;
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
        services.spice-vdagentd.enable = true;
        programs.virt-manager.enable = true;
        programs.dconf.enable = true; # For libvirtd
        boot.extraModprobeConfig = "options kvm_intel nested=1"; # Enable nested virt

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
            pools = [
              "spool"
              "tank"
            ];
            interval = "monthly";
          };

        };

        hardware.nvidia-container-toolkit = {
          enable = true;
          mount-nvidia-executables = true;
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
          enable = false;
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

        services.nginx = {
          enable = true;
          clientMaxBodySize = "20m";
        };
        users.users.nginx.extraGroups = [ "acme" ];

        boot.binfmt.emulatedSystems = ["aarch64-linux" "armv6l-linux" ];
        nix.settings.trusted-users = [
          "root"
          "cmp"
        ];
        users.users.cmp = {
          extraGroups = [
            "networkmanager"
            "wheel"
            "libvirtd"
            "ddc"
            "docker"
          ];

          packages = with pkgs; [
          ];
        };

        system.stateVersion = "23.05";
      }
    )
  ];
}
